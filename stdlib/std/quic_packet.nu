// stdlib/std/quic_packet.nu — QUIC v1 packet headers and packet
// protection (RFC 9000 §17, RFC 9001 §5). Pure codec: bytes in, bytes
// out, no sockets, no connection state. Known-answer tested against
// RFC 9001 Appendix A in compiler/tests/quic_packet_vectors.nu.
//
// Keys (one direction, one encryption level):
//
//   ( quic_initial_secret dcid )                 → ( Vec u )  HKDF-Extract(initial_salt, dcid)
//   ( quic_initial_keys dcid is_client )         → *QuicKeys  "client in" / "server in" → key/iv/hp
//   ( quic_keys_derive cipher secret )           → *QuicKeys  cipher 1 = AES-128-GCM, 2 = ChaCha20-Poly1305
//   ( quic_keys_update k )                       → *QuicKeys  next key phase: secret' = Expand-Label(secret, "quic ku") (§6)
//   ( quic_keys_free k )                         → v
//
// Protection:
//
//   ( quic_nonce iv pn )                         → ( Vec u )  iv XOR packet number (§5.3)
//   ( quic_seal k pn header payload )            → ( Vec u )  ct||tag, AAD = the unprotected header
//   ( quic_open k pn header ct_tag )             → ?( Vec u )
//   ( quic_hp_mask k sample )                    → ( Vec u )  5 bytes (§5.4)
//   ( quic_hp_apply k pkt pn_off pn_len )        → v          protect first byte + pn in place
//   ( quic_hp_remove k pkt pn_off )              → i          unprotect in place; the pn length (1..4), -1 if the
//                                                              packet is too short to sample
//   ( quic_packet_protect k header pn pn_len payload ) → ( Vec u )  the whole thing: header ends with the pn
//
// Headers (§17.2 / §17.3):
//
//   ( quic_hdr_parse pkt off short_dcid_len )    → *QuicHdr   0 on a malformed header; fields below
//   ( quic_hdr_free h )                          → v
//   ( quic_long_hdr_build ptype dcid scid token length pn pn_len ) → ( Vec u )
//   ( quic_short_hdr_build dcid key_phase pn pn_len )              → ( Vec u )
//   ( quic_retry_tag odcid retry_without_tag )   → ( Vec u )  16-byte Retry Integrity Tag (§5.8)
//   ( quic_retry_build dcid scid odcid token )   → ( Vec u )
//   ( quic_vn_build dcid scid versions )         → ( Vec u )  Version Negotiation (§17.2.1)
//
// Packet types (`ptype`): 0 Initial · 1 0-RTT · 2 Handshake · 3 Retry ·
// 4 short header (1-RTT) · 5 Version Negotiation (parse only).

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hkdf.nu`
$ `stdlib/std/aes_gcm.nu`
$ `stdlib/std/chacha20poly1305.nu`
$ `stdlib/std/quic_varint.nu`

@ __qp_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

@ quic_version_1 → i { ^ 1 }

// ── Keys ─────────────────────────────────────────────────────────

: QuicKeys {
    i cipher
    ( Vec u ) secret
    ( Vec u ) key
    ( Vec u ) iv
    ( Vec u ) hp
    * AesGcmKey aead
    * AesGcmKey hpk
}

@ quic_keys_derive i cipher ( Vec u ) secret → *QuicKeys {
    : *QuicKeys k # *QuicKeys ( nurl_alloc Z QuicKeys )
    : i klen ? == cipher 1 16 32
    : ( Vec u ) empty ( vec_new [u] )
    = . k cipher cipher
    = . k secret ( bytes_slice secret 0 ( vec_len [u] secret ) )
    = . k key ( hkdf_expand_label secret `quic key` empty klen )
    = . k iv ( hkdf_expand_label secret `quic iv` empty 12 )
    = . k hp ( hkdf_expand_label secret `quic hp` empty klen )
    ( vec_free [u] empty )
    ? == cipher 1 {
        = . k aead ( aes_gcm_key_new . k key )
        = . k hpk ( aes_gcm_key_new . k hp )
    } {
        = . k aead # *AesGcmKey 0
        = . k hpk # *AesGcmKey 0
    }
    ^ k
}

@ quic_keys_free * QuicKeys k → v {
    ? == # i k 0 { ^ } {}
    ( vec_free [u] . k secret )
    ( vec_free [u] . k key )
    ( vec_free [u] . k iv )
    ( vec_free [u] . k hp )
    ( aes_gcm_key_free . k aead )
    ( aes_gcm_key_free . k hpk )
    ( nurl_free # s k )
}

// Key update (RFC 9001 §6.1): the next secret is derived from the
// current one; the header-protection key does NOT change.
@ quic_keys_update * QuicKeys k → *QuicKeys {
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) next ( hkdf_expand_label . k secret `quic ku` empty 32 )
    ( vec_free [u] empty )
    : *QuicKeys n ( quic_keys_derive . k cipher next )
    ( vec_free [u] next )
    ^ n
}

@ quic_initial_secret ( Vec u ) dcid → ( Vec u ) {
    : ( Vec u ) salt ?? ( bytes_from_hex `38762cf7f55934b34d179ae6a4c80cadccbb7f0a` ) { T v → v F _ → ( vec_new [u] ) }
    : ( Vec u ) s ( hkdf_extract salt dcid )
    ( vec_free [u] salt )
    ^ s
}

// Initial packets are always AES-128-GCM (§5.2).
@ quic_initial_keys ( Vec u ) dcid b is_client → *QuicKeys {
    : ( Vec u ) initial ( quic_initial_secret dcid )
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) secret ? is_client ( hkdf_expand_label initial `client in` empty 32 ) ( hkdf_expand_label initial `server in` empty 32 )
    : *QuicKeys k ( quic_keys_derive 1 secret )
    ( vec_free [u] secret )
    ( vec_free [u] empty )
    ( vec_free [u] initial )
    ^ k
}

// ── Packet protection ────────────────────────────────────────────

// The 12-byte IV XOR the packet number, right-aligned (§5.3).
@ quic_nonce ( Vec u ) iv i pn → ( Vec u ) {
    : ( Vec u ) n ( bytes_slice iv 0 12 )
    : ~ i b 0
    ~ < b 8 {
        : i sb & >> pn * 8 - 7 b 255
        : b _ok ( vec_set [u] n + 4 b # u ^^ ( __qp_bget n + 4 b ) sb )
        = b + b 1
    }
    ^ n
}

@ quic_seal * QuicKeys k i pn ( Vec u ) header ( Vec u ) payload → ( Vec u ) {
    : ( Vec u ) nonce ( quic_nonce . k iv pn )
    : ( Vec u ) out ? == . k cipher 1 ( aes_gcm_seal . k aead nonce header payload ) ( aead_encrypt . k key nonce header payload )
    ( vec_free [u] nonce )
    ^ out
}

@ quic_open * QuicKeys k i pn ( Vec u ) header ( Vec u ) ct_tag → ?( Vec u ) {
    : ( Vec u ) nonce ( quic_nonce . k iv pn )
    : ?( Vec u ) out ? == . k cipher 1 ( aes_gcm_open . k aead nonce header ct_tag ) ( aead_decrypt . k key nonce header ct_tag )
    ( vec_free [u] nonce )
    ^ out
}

// Header-protection mask from a 16-byte sample (§5.4.3 / §5.4.4).
@ quic_hp_mask * QuicKeys k ( Vec u ) sample → ( Vec u ) {
    ? == . k cipher 1 {
        : ( Vec u ) block ( aes_block_encrypt . k hpk sample )
        : ( Vec u ) m ( bytes_slice block 0 5 )
        ( vec_free [u] block )
        ^ m
    } {}
    // ChaCha20: counter = sample[0..4] little-endian, nonce = sample[4..16].
    : i counter | | | ( __qp_bget sample 0 ) << ( __qp_bget sample 1 ) 8 << ( __qp_bget sample 2 ) 16 << ( __qp_bget sample 3 ) 24
    : ( Vec u ) nonce ( bytes_slice sample 4 16 )
    : ( Vec u ) block ( chacha20_block . k hp counter nonce )
    : ( Vec u ) m ( bytes_slice block 0 5 )
    ( vec_free [u] block )
    ( vec_free [u] nonce )
    ^ m
}

// The sample starts 4 bytes after the start of the packet number field,
// whatever the pn length (§5.4.2).
@ __qp_sample ( Vec u ) pkt i pn_off → ( Vec u ) {
    ^ ( bytes_slice pkt + pn_off 4 + pn_off 20 )
}

@ quic_hp_apply * QuicKeys k ( Vec u ) pkt i pn_off i pn_len → v {
    : ( Vec u ) sample ( __qp_sample pkt pn_off )
    : ( Vec u ) mask ( quic_hp_mask k sample )
    : i b0 ( __qp_bget pkt 0 )
    : i lowmask ? != & b0 128 0 15 31
    : b _f ( vec_set [u] pkt 0 # u ^^ b0 & ( __qp_bget mask 0 ) lowmask )
    : ~ i i 0
    ~ < i pn_len {
        : b _ok ( vec_set [u] pkt + pn_off i # u ^^ ( __qp_bget pkt + pn_off i ) ( __qp_bget mask + 1 i ) )
        = i + i 1
    }
    ( vec_free [u] mask )
    ( vec_free [u] sample )
}

@ quic_hp_remove * QuicKeys k ( Vec u ) pkt i pn_off → i {
    ? < ( vec_len [u] pkt ) + pn_off 20 { ^ -1 } {}
    : ( Vec u ) sample ( __qp_sample pkt pn_off )
    : ( Vec u ) mask ( quic_hp_mask k sample )
    : i b0 ( __qp_bget pkt 0 )
    : i lowmask ? != & b0 128 0 15 31
    : i nb0 ^^ b0 & ( __qp_bget mask 0 ) lowmask
    : b _f ( vec_set [u] pkt 0 # u nb0 )
    : i pn_len + & nb0 3 1
    : ~ i i 0
    ~ < i pn_len {
        : b _ok ( vec_set [u] pkt + pn_off i # u ^^ ( __qp_bget pkt + pn_off i ) ( __qp_bget mask + 1 i ) )
        = i + i 1
    }
    ( vec_free [u] mask )
    ( vec_free [u] sample )
    ^ pn_len
}

// Read the (already unprotected) truncated packet number at pn_off.
@ quic_pn_read ( Vec u ) pkt i pn_off i pn_len → i {
    : ~ i v 0
    : ~ i i 0
    ~ < i pn_len { = v | << v 8 ( __qp_bget pkt + pn_off i ) = i + i 1 }
    ^ v
}

// Seal + header-protect in one go. `header` must already end with the
// `pn_len`-byte packet number and (for long headers) carry a Length
// that counts pn_len + payload + 16.
@ quic_packet_protect * QuicKeys k ( Vec u ) header i pn i pn_len ( Vec u ) payload → ( Vec u ) {
    : ( Vec u ) ct ( quic_seal k pn header payload )
    : ( Vec u ) pkt ( bytes_slice header 0 ( vec_len [u] header ) )
    ( bytes_extend_bytes pkt ct )
    ( vec_free [u] ct )
    ( quic_hp_apply k pkt - ( vec_len [u] header ) pn_len pn_len )
    ^ pkt
}

// ── Headers ──────────────────────────────────────────────────────

: QuicHdr {
    i ptype
    i first
    i version
    i dcid_off
    i dcid_len
    i scid_off
    i scid_len
    i token_off
    i token_len
    i length
    i pn_off
    i end
}

@ quic_hdr_free * QuicHdr h → v {
    ? == # i h 0 { ^ } {}
    ( nurl_free # s h )
}

@ quic_hdr_dcid * QuicHdr h ( Vec u ) pkt → ( Vec u ) {
    ^ ( bytes_slice pkt . h dcid_off + . h dcid_off . h dcid_len )
}

@ quic_hdr_scid * QuicHdr h ( Vec u ) pkt → ( Vec u ) {
    ^ ( bytes_slice pkt . h scid_off + . h scid_off . h scid_len )
}

@ quic_hdr_token * QuicHdr h ( Vec u ) pkt → ( Vec u ) {
    ^ ( bytes_slice pkt . h token_off + . h token_off . h token_len )
}

// Parse one packet header starting at `off` (a datagram may coalesce
// several). Stops before the packet number, which is still protected.
// `short_dcid_len` is the length of the connection IDs this endpoint
// issues (a short header carries no length byte). Returns 0 when the
// bytes are not a well-formed header: too short, a connection ID over
// 20 bytes, a Length that runs past the datagram, a cleared fixed bit.
@ quic_hdr_parse ( Vec u ) pkt i off i short_dcid_len → *QuicHdr {
    : i n ( vec_len [u] pkt )
    ? >= off n { ^ # *QuicHdr 0 } {}
    : i b0 ( __qp_bget pkt off )
    : *QuicHdr h # *QuicHdr ( nurl_alloc Z QuicHdr )
    = . h first b0
    ? == & b0 128 0 {
        // Short header: first byte, DCID, packet number, payload to the end.
        ? == & b0 64 0 { ( nurl_free # s h ) ^ # *QuicHdr 0 } {}
        ? > + + off 1 short_dcid_len n { ( nurl_free # s h ) ^ # *QuicHdr 0 } {}
        = . h ptype 4
        = . h version 1
        = . h dcid_off + off 1
        = . h dcid_len short_dcid_len
        = . h pn_off + + off 1 short_dcid_len
        = . h end n
        ^ h
    } {}
    ? > + off 7 n { ( nurl_free # s h ) ^ # *QuicHdr 0 } {}
    : i ver | | | << ( __qp_bget pkt + off 1 ) 24 << ( __qp_bget pkt + off 2 ) 16 << ( __qp_bget pkt + off 3 ) 8 ( __qp_bget pkt + off 4 )
    = . h version ver
    : i dlen ( __qp_bget pkt + off 5 )
    = . h dcid_off + off 6
    = . h dcid_len dlen
    : i p1 + + off 6 dlen
    ? > + p1 1 n { ( nurl_free # s h ) ^ # *QuicHdr 0 } {}
    : i slen ( __qp_bget pkt p1 )
    = . h scid_off + p1 1
    = . h scid_len slen
    : ~ i p + + p1 1 slen
    ? > p n { ( nurl_free # s h ) ^ # *QuicHdr 0 } {}
    ? == ver 0 {
        // Version Negotiation: the rest is a list of versions.
        = . h ptype 5
        = . h pn_off p
        = . h end n
        ^ h
    } {}
    ? | > dlen 20 > slen 20 { ( nurl_free # s h ) ^ # *QuicHdr 0 } {}
    ? == & b0 64 0 { ( nurl_free # s h ) ^ # *QuicHdr 0 } {}
    : i ptype & >> b0 4 3
    = . h ptype ptype
    ? == ptype 3 {
        // Retry: token to the end minus the 16-byte integrity tag.
        ? < - n p 16 { ( nurl_free # s h ) ^ # *QuicHdr 0 } {}
        = . h token_off p
        = . h token_len - - n p 16
        = . h pn_off n
        = . h end n
        ^ h
    } {}
    ? == ptype 0 {
        : i tl ( quic_varint_read pkt p )
        ? < tl 0 { ( nurl_free # s h ) ^ # *QuicHdr 0 } {}
        = p + p ( quic_varint_len_at pkt p )
        ? > + p tl n { ( nurl_free # s h ) ^ # *QuicHdr 0 } {}
        = . h token_off p
        = . h token_len tl
        = p + p tl
    } {}
    : i len ( quic_varint_read pkt p )
    ? < len 0 { ( nurl_free # s h ) ^ # *QuicHdr 0 } {}
    = p + p ( quic_varint_len_at pkt p )
    ? > + p len n { ( nurl_free # s h ) ^ # *QuicHdr 0 } {}
    = . h length len
    = . h pn_off p
    = . h end + p len
    ^ h
}

@ __qp_push_pn ( Vec u ) out i pn i pn_len → v {
    : ~ i i - pn_len 1
    ~ >= i 0 {
        ( vec_push [u] out # u & >> pn * 8 i 255 )
        = i - i 1
    }
}

// Long header up to and including the packet number. `length` is the
// value of the Length field (pn_len + payload + tag), written as a
// 2-byte varint so a builder can size it before sealing.
@ quic_long_hdr_build i ptype ( Vec u ) dcid ( Vec u ) scid ( Vec u ) token i length i pn i pn_len → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    ( vec_push [u] out # u | | 192 << ptype 4 - pn_len 1 )
    ( bytes_push_u32_be out # u32 1 )
    ( vec_push [u] out # u ( vec_len [u] dcid ) )
    ( bytes_extend_bytes out dcid )
    ( vec_push [u] out # u ( vec_len [u] scid ) )
    ( bytes_extend_bytes out scid )
    ? == ptype 0 {
        ( quic_varint_push out ( vec_len [u] token ) )
        ( bytes_extend_bytes out token )
    } {}
    ( quic_varint_push_len out length ? < length 16384 2 4 )
    ( __qp_push_pn out pn pn_len )
    ^ out
}

@ quic_short_hdr_build ( Vec u ) dcid i key_phase i pn i pn_len → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] 32 )
    ( vec_push [u] out # u | | 64 ? != key_phase 0 4 0 - pn_len 1 )
    ( bytes_extend_bytes out dcid )
    ( __qp_push_pn out pn pn_len )
    ^ out
}

// Retry Integrity Tag (§5.8): AES-128-GCM with fixed key and nonce over
// an empty plaintext, AAD = ODCID length ‖ ODCID ‖ the Retry packet
// without its tag.
@ quic_retry_tag ( Vec u ) odcid ( Vec u ) retry_without_tag → ( Vec u ) {
    : ( Vec u ) key ?? ( bytes_from_hex `be0c690b9f66575a1d766b54e368c84e` ) { T v → v F _ → ( vec_new [u] ) }
    : ( Vec u ) nonce ?? ( bytes_from_hex `461599d35d632bf2239825bb` ) { T v → v F _ → ( vec_new [u] ) }
    : ( Vec u ) aad ( vec_with_cap [u] + 24 ( vec_len [u] retry_without_tag ) )
    ( vec_push [u] aad # u ( vec_len [u] odcid ) )
    ( bytes_extend_bytes aad odcid )
    ( bytes_extend_bytes aad retry_without_tag )
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) tag ( aes128_gcm_encrypt key nonce aad empty )
    ( vec_free [u] empty )
    ( vec_free [u] aad )
    ( vec_free [u] nonce )
    ( vec_free [u] key )
    ^ tag
}

@ quic_retry_build ( Vec u ) dcid ( Vec u ) scid ( Vec u ) odcid ( Vec u ) token → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    ( vec_push [u] out # u 255 )
    ( bytes_push_u32_be out # u32 1 )
    ( vec_push [u] out # u ( vec_len [u] dcid ) )
    ( bytes_extend_bytes out dcid )
    ( vec_push [u] out # u ( vec_len [u] scid ) )
    ( bytes_extend_bytes out scid )
    ( bytes_extend_bytes out token )
    : ( Vec u ) tag ( quic_retry_tag odcid out )
    ( bytes_extend_bytes out tag )
    ( vec_free [u] tag )
    ^ out
}

// Version Negotiation (§17.2.1): version 0, the client's IDs swapped,
// then the versions this server speaks. The unused low bits of the first
// byte are random-looking per spec, but the fixed bit need not be set.
@ quic_vn_build ( Vec u ) dcid ( Vec u ) scid ( Vec i ) versions → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    ( vec_push [u] out # u 128 )
    ( bytes_push_u32_be out # u32 0 )
    ( vec_push [u] out # u ( vec_len [u] dcid ) )
    ( bytes_extend_bytes out dcid )
    ( vec_push [u] out # u ( vec_len [u] scid ) )
    ( bytes_extend_bytes out scid )
    : ~ i i 0
    ~ < i ( vec_len [i] versions ) {
        : i v ?? ( vec_get [i] versions i ) { T x → x F → 0 }
        ( bytes_push_u32_be out # u32 v )
        = i + i 1
    }
    ^ out
}
