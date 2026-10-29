// stdlib/std/tls_server.nu — pure-NURL TLS 1.3 server handshake.
//
// The mirror image of the client in tls.nu: it reuses that module's record
// framing, key schedule, AEAD, transcript hashing and byte helpers, and
// adds the server-role pieces — ClientHello parsing, the ServerHello /
// EncryptedExtensions / Certificate / CertificateVerify / Finished flight,
// and server-direction record I/O (write under the server keys, read under
// the client keys; tls.nu's client functions are hardwired the other way).
//
// Scope: TLS 1.3 only; an EC P-256 leaf (CertificateVerify signed with
// ecdsa_secp256r1_sha256), an RSA leaf (rsa_pss_rsae_sha256) or an ML-DSA
// leaf (mldsa44/65/87) — or a classical leaf AND an ML-DSA leaf together,
// chosen per connection from the client's signature_algorithms
// (`tls_accept_dual_alpn`, RFC 8446 §4.4.2.2); the X25519MLKEM768, X25519
// and secp256r1 groups; the AES-128-GCM / ChaCha20-Poly1305 cipher
// suites — i.e. exactly what tls.nu's client offers, so the two
// interoperate. A full certificate chain (leaf + intermediates) is
// supported via the tls_cert_entry-framed cert_chain argument.
//
// On X25519MLKEM768 the server is the *encapsulating* side: the client
// sends an ML-KEM encapsulation key and gets back a ciphertext, not a
// public key. `tcp_tls_group` / `tcp_is_post_quantum` (std/net.nu)
// report what a given connection settled on, which is worth asking —
// a client without ML-KEM falls back to a classical group silently.
//
//   ( tls_accept     i raw ( Vec u ) cert_chain ( Vec u ) priv )
//   ( tls_accept_rsa i raw ( Vec u ) cert_chain ( Vec u ) n ( Vec u ) e ( Vec u ) d )
//                                              → !TlsConn TlsErr
//   ( tls_accept_alpn / tls_accept_rsa_alpn / tls_accept_mldsa_alpn … ( Vec u ) alpn_prefs )
//       the same, with a server ALPN preference list (RFC 7301) in wire
//       form — `tls_alpn_pack "h2 http/1.1"`; the pick lands in
//       tls_alpn_selected, no common protocol is a fatal alert
//       raw        = an accepted libc socket fd (from nurl_tcp_accept)
//       cert_chain = the certificate_list: tls_cert_entry blobs
//                    concatenated, leaf first (a single leaf is fine)
//       priv       = 32-byte EC P-256 private scalar (see std/pkey.nu)
//       n / d      = RSA modulus / private exponent, big-endian
//                    (std/pkey.nu rsa_priv_from_pem → RsaPriv)
//   ( tls_accept_mldsa i raw ( Vec u ) cert_chain i level ( Vec u ) sk )
//       an ML-DSA leaf: level 44 / 65 / 87, sk = the FIPS 204 secret key
//   ( tls_accept_dual_alpn i raw cert_chain keytype ec_priv n e d pq_chain pq_level pq_sk alpn_prefs )
//       a classical leaf plus an ML-DSA leaf; the client's
//       signature_algorithms picks which one it is shown
//
// A server that accepts more than once prepares its identities once and
// accepts with those — what every entry point above does per call:
//   ( tls_ident_ec ( Vec u ) cert_chain ( Vec u ) priv )        → ( Arc TlsIdent )
//   ( tls_ident_rsa ( Vec u ) cert_chain RsaKey key )            → ( Arc TlsIdent )
//   ( tls_ident_mldsa ( Vec u ) cert_chain i level ( Vec u ) sk ) → ( Arc TlsIdent )
//   ( tls_accept_ident i raw ( Arc TlsIdent ) id ( Vec u ) alpn_prefs ) → !TlsConn TlsErr
//   ( tls_accept_ident_dual i raw ( Arc TlsIdent ) id ( Arc TlsIdent ) pq ( Vec u ) alpn_prefs )
//   ( tls_server_read  TlsConn c i max )       → !( Vec u ) TlsErr
//   ( tls_server_read_into TlsConn c dst max ) → !i TlsErr  (appended to dst; 0 at EOF)
//   ( tls_server_write TlsConn c ( Vec u ) )   → !v TlsErr
//   ( tls_server_close TlsConn c )             → v   close_notify + close the socket
//
// A TlsConn is a handle (std/tls.nu): the connection's memory goes with
// its last owner, and a socket nobody closed is closed then too.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hkdf.nu`
$ `stdlib/std/x25519.nu`
$ `stdlib/std/mlkem.nu`
$ `stdlib/std/mldsa.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/std/rsa.nu`
$ `stdlib/std/chacha20poly1305.nu`
$ `stdlib/std/aes_gcm.nu`
$ `stdlib/core/rcbox.nu`
$ `stdlib/std/arc.nu`

& `c` @ nurl_rand_fill *u buf i n → i

// ── session tickets (RFC 8446 §4.6.1) ───────────────────────────────
//
// Tickets are STATELESS: the ticket a client gets back is its PSK
// (plus issue time and lifetime) sealed under a process-wide key, so
// any worker thread can take it back later without a shared session
// table, and nothing accumulates per connection. Only psk_dhe_ke is
// offered or accepted, and there is no early data: a resumed connection
// still runs a fresh (EC)DHE, so a ticket that leaks later never
// decrypts a recording, and RFC 8446 §8's replay concern (0-RTT) does
// not arise — which is what makes a stateless, re-offerable ticket safe
// to issue.
//
// KEY ROTATION without shared mutable state. rustls' Ticketer rotates
// its key on a timer and keeps the previous one for a grace window,
// which needs a swap every worker sees and a retirement every worker
// has stopped using. Here the sealing key is a pure function of time:
// a 32-byte MASTER is drawn once per process (at TLS-listener setup,
// while single-threaded, or on first use through a compare-and-swap so
// concurrent first users agree), and the key for EPOCH e is
// HKDF-Expand-Label(master, "ticket key", e, 32), e = floor(now / 6 h).
// Every worker derives the same key for the same epoch with nothing to
// publish or free; a ticket records its epoch, and one from the previous
// epoch still opens (ticket lifetime 2 h < epoch 6 h), so rotation never
// cuts a live ticket short. A process restart draws a new master and
// invalidates outstanding tickets — a full handshake, not a failure.
: ~ i g_tls_ticket_master 0

// Runtime publish-once slots (stdlib/runtime_core.c nurl_once_slot,
// offered through vec_publish_once in stdlib/core/vec.nu): the first
// non-zero value published into a slot wins; every caller gets the winner
// back. Slot ids in use across the stdlib:
//   1  TLS server ticket master (this module)
//   2  HTTP client session cache (ext/http_pure.nu)
//   3  SHA-256 round constants (std/hash_sha256.nu)
//   4  X25519 niels table (std/x25519.nu)
//   5  P-256 fixed-base comb table, 52 windows × 16 (std/p256_field.nu)
//   6  free (was the second P-256 comb table)
//   7  CRC-32 slicing-by-8 tables (std/deflate.nu)
//   8, 9  base64 decode tables, standard and URL alphabets (std/encode.nu)
//   10  Keccak-f[1600] round constants (std/hash_sha3.nu)
//   11  P-256 affine table 0·G … 15·G for signature verification (std/ecdsa_p256.nu)
//   12  ML-KEM NTT zeta tables, scalar and per-lane (std/mlkem.nu)

@ _tls_ticket_key_ensure → v {
    ? != g_tls_ticket_master 0 { ^ } {}
    // 32 CSPRNG bytes (_rand_bytes fails closed).
    : ( Vec u ) k ( _rand_bytes 32 )
    // Publish unless someone else already did; the loser's draw is
    // dropped and it adopts the winner's. The winner lives for the rest
    // of the program, through the global — a cache of the slot: every
    // thread that fills it writes the same value.
    = g_tls_ticket_master ( vec_publish_once [u] 1 k )
}

// The sealing key for one 6-hour epoch (see above).
@ __tls_ticket_key_for i epoch → ( Vec u ) {
    ( _tls_ticket_key_ensure )
    // The process-wide master, lent.
    : ( Vec u ) master # ( Vec u ) g_tls_ticket_master
    : ( Vec u ) ctx ( vec_with_cap [u] 4 )
    ( _tls_u32 ctx epoch )
    : ( Vec u ) key ( hkdf_expand_label master `ticket key` ctx 32 )
    ^ key
}

@ __tls_ticket_epoch_now → i {
    ^ / ( now_ms ) 21600000
}

// ticket = epoch(4) ‖ nonce(12) ‖ AEAD(key_epoch, nonce, "", psk(32) ‖ issued_ms(8) ‖ lifetime_s(4))
@ __tls_ticket_seal ( Vec u ) psk i lifetime → ( Vec u ) {
    : i epoch ( __tls_ticket_epoch_now )
    : ( Vec u ) key ( __tls_ticket_key_for epoch )
    : ( Vec u ) nonce ( __srv_rand 12 )
    : ( Vec u ) aad ( vec_new [u] )
    : ( Vec u ) plain ( vec_with_cap [u] 44 )
    ( _tls_cat plain psk )
    ( _tls_u64 plain ( now_ms ) )
    ( _tls_u32 plain lifetime )
    : ( Vec u ) sealed ( aead_encrypt key nonce aad plain )
    : ( Vec u ) out ( vec_with_cap [u] + 16 ( vec_len [u] sealed ) )
    ( _tls_u32 out epoch )
    ( _tls_cat out nonce )
    ( _tls_cat out sealed )
    ^ out
}

// The PSK inside a ticket we issued — or an empty Vec when the ticket is
// not ours, was altered, is from an epoch we no longer honour, or has
// outlived its lifetime.
@ __tls_ticket_open ( Vec u ) ticket → ( Vec u ) {
    : i n ( vec_len [u] ticket )
    ? | == g_tls_ticket_master 0 != n 76 { ^ ( vec_new [u] ) } {}
    : i epoch ( _rdint ticket 0 4 )
    : i cur ( __tls_ticket_epoch_now )
    ? & != epoch cur != epoch - cur 1 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) key ( __tls_ticket_key_for epoch )
    : ( Vec u ) nonce ( bytes_slice ticket 4 16 )
    : ( Vec u ) ct ( bytes_slice ticket 16 n )
    : ( Vec u ) aad ( vec_new [u] )
    : ?( Vec u ) r ( aead_decrypt key nonce aad ct )
    ?? r {
        F _ → ^ ( vec_new [u] )
        T plain → {
            : i issued ( _rdint plain 32 8 )
            : i life ( _rdint plain 40 4 )
            : i age - ( now_ms ) issued
            : ( Vec u ) psk ? & & == ( vec_len [u] plain ) 44 >= age 0 <= age * life 1000 ( bytes_slice plain 0 32 ) ( vec_new [u] )
            ^ psk
        }
    }
}

// Did the ClientHello carry psk_key_exchange_modes with psk_dhe_ke? A
// server MUST NOT send a NewSessionTicket to a client that did not
// (RFC 8446 §4.2.9) — the client is saying it cannot resume, and a
// strict one may treat an unsolicited ticket as an error.
@ __srv_client_can_resume ( Vec u ) ch i es i ee → b {
    : i modes ( __srv_find_ext ch es ee 45 )
    ? < modes 0 { ^ F } {}
    : i mlen ( _t_bget ch modes )
    : ~ i mk 0
    ~ < mk mlen {
        ? == ( _t_bget ch + + modes 1 mk ) 1 { ^ T } {}
        = mk + mk 1
    }
    ^ F
}

// The resumption offer in a ClientHello, if it is one we can honour: a
// ticket of ours, offered with psk_dhe_ke, whose binder verifies over the
// hello truncated before the binders list (RFC 8446 §4.2.11.2). Appends
// the PSK to `out` and returns the selected identity index, or -1 (and
// leaves `out` empty) — the caller then runs the full handshake.
@ __srv_psk_offer ( Vec u ) ch i es i ee ( Vec u ) out → i {
    : i modes ( __srv_find_ext ch es ee 45 )
    ? < modes 0 { ^ -1 } {}
    : i mlen ( _t_bget ch modes )
    : ~ b dhe F
    : ~ i mk 0
    ~ < mk mlen {
        ? == ( _t_bget ch + + modes 1 mk ) 1 { = dhe T } {}
        = mk + mk 1
    }
    ? ! dhe { ^ -1 } {}
    : i pe ( __srv_find_ext ch es ee 41 )
    ? < pe 0 { ^ -1 } {}
    : i idlen ( _rdint ch pe 2 )
    : i ids + pe 2
    : i idend + ids idlen
    ? > + idend 2 ee { ^ -1 } {}
    : i blen ( _rdint ch idend 2 )
    : i bstart + idend 2
    // pre_shared_key must be the last extension: the binder covers
    // everything up to its binders list, so nothing may follow.
    ? != + bstart blen ee { ^ -1 } {}
    : ~ i p ids
    : ~ i bp bstart
    : ~ i idx 0
    : ~ i sel -1
    ~ & == sel -1 < + p 6 + idend 1 {
        : i tl ( _rdint ch p 2 )
        : i tstart + p 2
        : i tend + tstart tl
        ? | > + tend 4 idend >= bp + bstart blen { = p idend } {
            : i bl ( _t_bget ch bp )
            : ( Vec u ) ticket ( bytes_slice ch tstart tend )
            : ( Vec u ) psk ( __tls_ticket_open ticket )
            ? & == ( vec_len [u] psk ) 32 == bl 32 {
                : ( Vec u ) early ( _psk_early psk )
                : ( Vec u ) want ( _psk_binder_over early ch idend )
                ? ( _ct_eq32 ch + bp 1 want ) {
                    = sel idx
                    ( _tls_cat out psk )
                } {}
            } {}
            = p + tend 4
            = bp + + bp 1 bl
            = idx + idx 1
        }
    }
    ^ sel
}

// ── server-direction record I/O ─────────────────────────────────────

// Encrypt one record under the SERVER write keys (s_key/s_iv/s_seq) and
// APPEND its wire bytes to `out` — no socket write. The handshake path
// batches its whole first flight (SH‥Finished) into one buffer and one
// send() through this; __srv_send_enc below wraps it for the callers
// that do want an immediate write (application data, alerts).
@ __srv_enc_rec_to inout TlsConnImpl c ( Vec u ) out i content_type ( Vec u ) content → v {
    ( _tls_rec_range_to c out 0 content_type content 0 ( vec_len [u] content ) )
}

// Append one PLAINTEXT record (rtype, body) to `out` — the unencrypted
// ServerHello / CCS legs of the batched first flight.
@ __srv_plain_rec_to ( Vec u ) out i rtype ( Vec u ) body → v {
    ( vec_push [u] out # u rtype )
    ( vec_push [u] out # u 3 )
    ( vec_push [u] out # u 3 )
    ( _tls_u16 out ( vec_len [u] body ) )
    ( _tls_cat out body )
}

// Encrypt + send one record under the SERVER write keys (s_key/s_iv/s_seq),
// sealed in place in the connection's txbuf.
@ __srv_send_enc inout TlsConnImpl c i content_type ( Vec u ) content → !v TlsErr {
    : ( Vec u ) buf ( _tls_tx_take c )
    ( __srv_enc_rec_to c buf content_type content )
    : !v TlsErr r ( _tls_tx_flush c buf )
    ( _tls_tx_put c buf )
    ^ r
}

// AEAD-decrypt one record body under the CLIENT write keys (c_key/c_iv/c_seq).
@ __srv_decrypt inout TlsConnImpl c ( Vec u ) body → ?( Vec u ) {
    ^ ( _tls_open_body c 1 body )
}

// Pull the next complete handshake message from the client. Plaintext
// type-22 records (the ClientHello flight) are taken verbatim; type-23
// records are decrypted under the client handshake keys (the Finished).
@ __srv_next_hs inout TlsConnImpl c → !( Vec u ) TlsErr {
    : ~ i need 1
    ~ == need 1 {
        : i have ( vec_len [u] . c hsbuf )
        ? >= have 4 {
            : i mlen ( _rdint . c hsbuf 1 3 )
            ? >= have + 4 mlen {
                : ( Vec u ) msg ( bytes_slice . c hsbuf 0 + 4 mlen )
                : ( Vec u ) rest ( bytes_slice . c hsbuf + 4 mlen have )
                = . c hsbuf rest
                ^ @ !( Vec u ) TlsErr { T msg }
            } {}
        } {}
        : !TlsRecord TlsErr rr ( _read_record c )
        ?? rr {
            F e → { ^ @ !( Vec u ) TlsErr { F e } }
            T rec → {
                ? == . rec rtype 20 {
                } {
                    ? == . rec rtype 23 {
                        ?? ( __srv_decrypt c . rec body ) {
                            T inner → {
                                : i ct ( _inner_type inner )
                                ? == ct 22 {
                                    ( _tls_cat . c hsbuf inner )
                                } {
                                    ? == ct 21 { ^ @ !( Vec u ) TlsErr { F # TlsErr TlsAlert } } {}
                                    ^ @ !( Vec u ) TlsErr { F # TlsErr TlsProtocol }
                                }
                            }
                            F _ → {
                                ^ @ !( Vec u ) TlsErr { F # TlsErr TlsDecrypt }
                            }
                        }
                    } {
                        ? == . rec rtype 22 {
                            ( _tls_cat . c hsbuf . rec body )
                        } {
                            ^ @ !( Vec u ) TlsErr { F # TlsErr TlsProtocol }
                        }
                    }
                }
            }
        }
    }
    ^ @ !( Vec u ) TlsErr { F # TlsErr TlsProtocol }
}

// ── ClientHello parsing ─────────────────────────────────────────────

// Find extension `want` in msg's extension block [es, ee); returns the
// extension-body start offset, or -1. Sets nothing else; caller reads the
// length via _rdint at off-2.
@ __srv_find_ext ( Vec u ) msg i es i ee i want → i {
    : ~ i p es
    : ~ i found -1
    ~ & < + p 4 + ee 1 == found -1 {
        : i et ( _rdint msg p 2 )
        : i el ( _rdint msg + p 2 2 )
        ? == et want { = found + p 4 } { = p + + p 4 el }
    }
    ^ found
}

// The client's key_exchange for one named group, or an empty Vec if it
// did not send a share for it.
//
// Separate from picking the group because preference and presence are
// different questions: the client lists its shares in ITS order, and a
// server that takes the first one it recognises lets the client decide
// the group. Asking for the groups we want, most-preferred first, keeps
// that decision here.
@ __srv_find_share ( Vec u ) ch i ks i ksend i want → ( Vec u ) {
    : ~ i kp + ks 2
    ~ < + kp 4 + ksend 1 {
        : i g ( _rdint ch kp 2 )
        : i klen ( _rdint ch + kp 2 2 )
        ? == g want {
            ^ ( bytes_slice ch + kp 4 + + kp 4 klen )
        } {}
        = kp + + kp 4 klen
    }
    ^ ( vec_new [u] )
}

// ── server-flight message builders ──────────────────────────────────

@ __srv_hs_wrap i htype ( Vec u ) body → ( Vec u ) {
    : ( Vec u ) hs ( vec_with_cap [u] + ( vec_len [u] body ) 4 )
    ( vec_push [u] hs # u htype )
    ( _u24 hs ( vec_len [u] body ) )
    ( _tls_cat hs body )
    ^ hs
}

// DER-encode a 32-byte big-endian magnitude as an ASN.1 INTEGER.
@ __srv_der_int ( Vec u ) out ( Vec u ) v → v {
    : i n ( vec_len [u] v )
    : ~ i s 0
    ~ & < s - n 1 == ( _t_bget v s ) 0 { = s + s 1 }
    : i mag - n s
    : b hi != 0 & ( _t_bget v s ) 128
    ( vec_push [u] out # u 2 )
    ( vec_push [u] out # u ? hi + mag 1 mag )
    ? hi { ( vec_push [u] out # u 0 ) } {}
    : ~ i k s
    ~ < k n { ( vec_push [u] out # u ( _t_bget v k ) ) = k + k 1 }
}

// raw r‖s (64 bytes) → DER SEQUENCE { INTEGER r, INTEGER s }.
@ __srv_der_ecdsa ( Vec u ) rs → ( Vec u ) {
    : ( Vec u ) r ( bytes_slice rs 0 32 )
    : ( Vec u ) sv ( bytes_slice rs 32 64 )
    : ( Vec u ) inner ( vec_new [u] )
    ( __srv_der_int inner r )
    ( __srv_der_int inner sv )
    : ( Vec u ) out ( vec_with_cap [u] + ( vec_len [u] inner ) 2 )
    ( vec_push [u] out # u 48 )
    ( vec_push [u] out # u ( vec_len [u] inner ) )
    ( _tls_cat out inner )
    ^ out
}

// CertificateVerify signed content: 64 × 0x20, the context string, a 0x00
// separator, then the transcript hash through Certificate.
@ __srv_cv_content ( Vec u ) th → ( Vec u ) {
    : ( Vec u ) m ( vec_new [u] )
    : ~ i k 0
    ~ < k 64 { ( vec_push [u] m # u 32 ) = k + k 1 }
    ( bytes_extend_str m `TLS 1.3, server CertificateVerify` )
    ( vec_push [u] m # u 0 )
    ( _tls_cat m th )
    ^ m
}

// ── server identities ──────────────────────────────────────────────
//
// What a server presents and signs with: the certificate_list
// (tls_cert_entry blobs, leaf first) and the private key, PREPARED — an
// RSA key's Montgomery contexts and limbs (std/rsa.nu RsaKey), an ML-DSA
// key's NTT forms and Â (std/mldsa.nu MldsaKey) — so nothing the key
// alone determines is derived per handshake. `keytype` 0 = EC P-256
// (`ec`, the 32-byte scalar; ECDSA signing has nothing per key to
// precompute: its fixed-base tables are the generator's, shared by every
// key), 1 = RSA (`rsa`), 2 = ML-DSA (`ml`); the other key fields are
// empty. An identity is never written after it is made and travels in an
// Arc: a listener builds its identities at load, and each handshake on
// each worker takes a count.
: TlsIdent { ( Vec u ) chain i keytype ( Vec u ) ec RsaKey rsa MldsaKey ml }

@ __srv_copy ( Vec u ) b → ( Vec u ) { ^ ( bytes_slice b 0 ( vec_len [u] b ) ) }

@ tls_ident_ec ( Vec u ) cert_chain ( Vec u ) priv → ( Arc TlsIdent ) {
    ^ ( arc_new [TlsIdent] @ TlsIdent { ( __srv_copy cert_chain ) 0 ( __srv_copy priv ) # RsaKey 0 # MldsaKey 0 } )
}

@ tls_ident_rsa ( Vec u ) cert_chain sink RsaKey key → ( Arc TlsIdent ) {
    ^ ( arc_new [TlsIdent] @ TlsIdent { ( __srv_copy cert_chain ) 1 ( vec_new [u] ) key # MldsaKey 0 } )
}

// `level` is 44, 65 or 87 and must match the key the certificate carries.
@ tls_ident_mldsa ( Vec u ) cert_chain i level ( Vec u ) sk → ( Arc TlsIdent ) {
    ^ ( arc_new [TlsIdent] @ TlsIdent { ( __srv_copy cert_chain ) 2 ( vec_new [u] ) # RsaKey 0 ( mldsa_sign_key level sk ) } )
}

// The identity the byte-vector entry points describe: keytype 0 = EC
// (`ec_priv`), 1 = RSA (`rsa_n` / `rsa_e` / `rsa_d`, the plain private
// exponent), 2 = ML-DSA (`ec_priv` the secret key at `ml_level`).
@ __srv_ident_of ( Vec u ) cert_chain i keytype ( Vec u ) ec_priv ( Vec u ) rsa_n ( Vec u ) rsa_e ( Vec u ) rsa_d i ml_level → ( Arc TlsIdent ) {
    ? == keytype 1 { ^ ( tls_ident_rsa cert_chain ( rsa_key_plain rsa_n rsa_e rsa_d ) ) } {}
    ? == keytype 2 { ^ ( tls_ident_mldsa cert_chain ml_level ec_priv ) } {}
    ^ ( tls_ident_ec cert_chain ec_priv )
}

@ tls_ident_keytype ( Arc TlsIdent ) id → i { ^ . ( arc_get [TlsIdent] id ) keytype }

// The SignatureScheme an identity signs CertificateVerify with.
@ __srv_ident_scheme TlsIdent id → i {
    ? == . id keytype 2 { ^ ( __srv_mldsa_scheme ( mldsa_key_level . id ml ) ) } {}
    ^ ? == . id keytype 1 2052 1027
}

// Build the CertificateVerify body (SignatureScheme + signature) over the
// SHA-256 digest `cvdig` of the signed content, with identity `id`'s key.
// RSA-PSS (rsa_pss_rsae_sha256, 0x0804) hashes with SHA-256 so the message
// digest IS cvdig; so does EC P-256 (ecdsa_secp256r1_sha256, 0x0403).
// ML-DSA takes `cvc` — the signed *content* — not the digest: it hashes
// internally, so handing it a SHA-256 digest would sign the wrong thing
// and still verify against nothing.
@ __srv_cv_body TlsIdent id ( Vec u ) cvdig ( Vec u ) cvc → ( Vec u ) {
    : ( Vec u ) cvbody ( vec_new [u] )
    ? == . id keytype 2 {
        : ( Vec u ) ctx ( vec_new [u] )
        : ( Vec u ) sig ( mldsa_sign_with . id ml cvc ctx )
        ( _tls_u16 cvbody ( __srv_ident_scheme id ) )
        ( _tls_u16 cvbody ( vec_len [u] sig ) )
        ( _tls_cat cvbody sig )
        ^ cvbody
    } {}
    ? == . id keytype 1 {
        : ( Vec u ) salt ( _rand_bytes 32 )
        : ( Vec u ) sig ( rsa_pss_sign_sha256_key . id rsa cvdig salt )
        ( _tls_u16 cvbody 2052 )  // rsa_pss_rsae_sha256 = 0x0804
        ( _tls_u16 cvbody ( vec_len [u] sig ) )
        ( _tls_cat cvbody sig )
    } {
        : ( Vec u ) rs ( ecdsa_p256_sign . id ec cvdig )
        : ( Vec u ) der ( __srv_der_ecdsa rs )
        ( _tls_u16 cvbody 1027 )  // ecdsa_secp256r1_sha256 = 0x0403
        ( _tls_u16 cvbody ( vec_len [u] der ) )
        ( _tls_cat cvbody der )
    }
    ^ cvbody
}

// Frame one DER certificate as a TLS 1.3 CertificateEntry:
// [u24 cert_len][DER][u16 extensions_len = 0]. Concatenate these (leaf
// first, then intermediates) to form the cert_chain argument of
// tls_accept / tls_accept_rsa.
@ tls_cert_entry ( Vec u ) der → ( Vec u ) {
    : ( Vec u ) e ( vec_new [u] )
    ( _u24 e ( vec_len [u] der ) )
    ( _tls_cat e der )
    ( _tls_u16 e 0 )  // per-cert extensions = empty
    ^ e
}

// ── accept ──────────────────────────────────────────────────────────

// Abandon a handshake: close the socket (tls_close with established = 0
// sends no alert). The connection's buffers go with its handle.
@ __srv_abort inout TlsConnImpl c → !v TlsErr {
    ( _tls_close_in c )
    ^ @ !v TlsErr { F # TlsErr TlsHandshake }
}

// Fail the handshake with a fatal alert. Only valid BEFORE the
// ServerHello has gone out — the alert is a plaintext record, which is
// what a peer expects at that stage (RFC 8446 §6: alerts share the
// record protection of the current epoch, and before the ServerHello
// there is none). Used for no_application_protocol (120, RFC 7301 §3.2).
@ __srv_abort_alert inout TlsConnImpl c i desc → !v TlsErr {
    : ( Vec u ) body ( vec_with_cap [u] 2 )
    ( vec_push [u] body # u 2 )  // AlertLevel fatal
    ( vec_push [u] body # u desc )
    : ( Vec u ) rec ( vec_with_cap [u] 7 )
    ( __srv_plain_rec_to rec 21 body )
    : b _w ( _tls_sock_write . c fd rec )
    ^ ( __srv_abort c )
}

// ALPN (RFC 7301). `prefs` is the server's protocol list in wire form —
// a sequence of [len:1][name] entries, most-preferred first — and the
// ClientHello's application_layer_protocol_negotiation body is
// [list_len:2] followed by the same kind of entries. Returns a copy of
// the first SERVER preference the client also offered (§3.2: the server
// picks, in its own order), or an empty Vec when the client sent no ALPN
// extension, sent an empty/garbled one, or offered nothing we serve.
// Whether the empty result is "no ALPN" or "no overlap" is the caller's
// question — it has the extension's presence from __srv_find_ext.
@ __srv_select_alpn ( Vec u ) ch i es i ee ( Vec u ) prefs → ( Vec u ) {
    : ( Vec u ) sel ( vec_new [u] )
    : i np ( vec_len [u] prefs )
    ? == np 0 { ^ sel } {}
    : i ao ( __srv_find_ext ch es ee 16 )
    ? < ao 0 { ^ sel } {}
    : i al ( _rdint ch - ao 2 2 )  // extension_data length
    : i aend + ao al
    ? | > aend ee < al 2 { ^ sel } {}
    : i ll ( _rdint ch ao 2 )  // ProtocolNameList length
    : i lend + + ao 2 ll
    ? > lend aend { ^ sel } {}
    : ~ i pp 0
    : ~ b found F
    ~ & ! found < pp np {
        : i pl ( _t_bget prefs pp )
        : i pstart + pp 1
        ? | == pl 0 > + pstart pl np { = pp np } {
            // Walk the client's list looking for this exact name.
            : ~ i cp + ao 2
            ~ & ! found < cp lend {
                : i cl ( _t_bget ch cp )
                : i cstart + cp 1
                ? | == cl 0 > + cstart cl lend { = cp lend } {
                    ? == cl pl {
                        : ~ i k 0
                        : ~ b same T
                        ~ & same < k pl {
                            ? != ( _t_bget prefs + pstart k ) ( _t_bget ch + cstart k ) { = same F } {}
                            = k + k 1
                        }
                        ? same {
                            = found T
                            = k 0
                            ~ < k pl { ( vec_push [u] sel # u ( _t_bget prefs + pstart k ) ) = k + k 1 }
                        } {}
                    } {}
                    = cp + cstart cl
                }
            }
            = pp + pstart pl
        }
    }
    ^ sel
}

// ── Message-level handshake machine ───────────────────────────────
//
// The TLS 1.3 server handshake as a state machine over handshake
// MESSAGES: ClientHello in, ServerHello + {EncryptedExtensions,
// Certificate, CertificateVerify, Finished} out, client Finished in,
// NewSessionTicket out — and the traffic secrets each step makes
// available. It knows nothing about records or sockets. Two callers
// drive it:
//
//   * `__tls_accept_impl` below (TCP): reads records, feeds messages,
//     wraps the outputs in records, installs the secrets as record keys.
//   * `std/quic_tls.nu` (QUIC, RFC 9001): feeds CRYPTO frame bytes,
//     sends the outputs as CRYPTO frames at the matching encryption
//     level, derives packet keys from the same secrets, and carries the
//     `quic_transport_parameters` extension through `ext_want` /
//     `ext_in` / `ext_out`.
//
// Failures are TLS alert descriptions (RFC 8446 §6.2) so each caller
// can say them in its own way — an alert record, or a QUIC
// CONNECTION_CLOSE with 0x100 + description.
//
//   ( _srv_hs_new ( Arc TlsIdent ) id alpn_prefs ) → SrvHs
//   ( _srv_hs_set_pq hs ( Arc TlsIdent ) pq )  → v   a second identity, picked per ClientHello
//   ( _srv_hs_set_ext hs want ext_out )       → v   require CH extension `want` (0 = none), append
//                                                   `ext_out` (wire-framed extension(s)) to EE
//   ( _srv_hs_client_hello hs ch )            → i   0 ok · alert description otherwise; fills
//                                                   out_sh, out_hs, c_hs/s_hs, c_ap/s_ap, alpn_sel, cipher
//   ( _srv_hs_client_finished hs fin )        → i   0 ok · 51 decrypt_error; fills res_master, out_ticket
//   ( _srv_hs_out_sh hs ) … ( _srv_hs_s_ap hs )       the machine's fields, read (Vecs lent)
//   ( _srv_hs_free hs )                       → v   early release (optional)
//
// A SrvHs is a library handle (docs/MEMORY.md §7.6): its last owner
// releases it, so a handshake abandoned at any step leaks nothing. Every
// `( Vec u )` field is owned by the machine; a caller that wants to keep
// one copies it.

// Sealed (`raw`): the handshake trusts its keys and buffers to be the
// ones it set.
raw : SrvHsImpl {
    // The identity this handshake presents and signs with (a count on
    // the caller's): the one it was made with, or `pq` once
    // `__srv_pick_cert` chose that.
    ( Arc TlsIdent ) id
    ( Vec u ) alpn_prefs
    i ext_want
    ( Vec u ) ext_in
    i ext_in_present
    ( Vec u ) ext_out
    i state
    Sha256 trh  // incremental transcript hash
    i cipher
    i resumed
    i can_resume
    i kx_group
    ( Vec u ) alpn_sel
    ( Vec u ) c_hs
    ( Vec u ) s_hs
    ( Vec u ) c_ap
    ( Vec u ) s_ap
    ( Vec u ) master
    ( Vec u ) th_sf
    ( Vec u ) res_master
    ( Vec u ) out_sh
    ( Vec u ) out_hs
    ( Vec u ) out_ticket
    // Optional second identity (an ML-DSA leaf), selected per
    // ClientHello by `__srv_pick_cert` when the client's
    // signature_algorithms lists its scheme. F when the caller
    // configured a single certificate.
    ? ( Arc TlsIdent ) pq
}

// A SrvHs is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: SrvHs { ( Shared SrvHsImpl ) ctl }

@ SrvHs_share SrvHs h → SrvHs { ^ @ SrvHs { ( shared_clone [SrvHsImpl] . h ctl ) } }

@ SrvHs_drop sink SrvHs h → v {}

@ __SrvHs_ptr SrvHs h → *SrvHsImpl { ^ ( shared_ptr [SrvHsImpl] . h ctl ) }

@ _srv_hs_new ( Arc TlsIdent ) id ( Vec u ) alpn_prefs → SrvHs {
    : ( Shared SrvHsImpl ) h__box ( shared_zero [SrvHsImpl] )
    : *SrvHsImpl h ( shared_ptr [SrvHsImpl] h__box )
    = . h id ( arc_clone [TlsIdent] id )
    = . h alpn_prefs ( bytes_slice alpn_prefs 0 ( vec_len [u] alpn_prefs ) )
    = . h ext_want 0
    = . h ext_in ( vec_new [u] )
    = . h ext_in_present 0
    = . h ext_out ( vec_new [u] )
    = . h state 0
    // Incremental transcript hash: absorb each handshake message as it
    // is appended and SNAPSHOT the digest at the checkpoints, instead of
    // accumulating a transcript Vec and re-hashing it from scratch at
    // every checkpoint (~4.3 KB hashed per handshake where ~1.3 KB
    // suffices).
    = . h trh ( sha256_init )
    = . h cipher 0
    = . h resumed 0
    = . h can_resume 0
    = . h kx_group 0
    = . h alpn_sel ( vec_new [u] )
    = . h c_hs ( vec_new [u] )
    = . h s_hs ( vec_new [u] )
    = . h c_ap ( vec_new [u] )
    = . h s_ap ( vec_new [u] )
    = . h master ( vec_new [u] )
    = . h th_sf ( vec_new [u] )
    = . h res_master ( vec_new [u] )
    = . h out_sh ( vec_new [u] )
    = . h out_hs ( vec_new [u] )
    = . h out_ticket ( vec_new [u] )
    = . h pq @ ?( Arc TlsIdent ) { F }
    ^ @ SrvHs { h__box }
}

// Give the handshake a second, post-quantum identity (tls_ident_mldsa).
// Which of the two identities a connection gets is decided per
// ClientHello — see `__srv_pick_cert`. Takes a count, like the
// constructor.
@ _srv_hs_set_pq SrvHs h__h ( Arc TlsIdent ) pq → v {
    : *SrvHsImpl h ( __SrvHs_ptr h__h )
    = . h pq @ ?( Arc TlsIdent ) { T ( arc_clone [TlsIdent] pq ) }
}

@ _srv_hs_set_ext SrvHs h__h i want ( Vec u ) ext_out → v {
    : *SrvHsImpl h ( __SrvHs_ptr h__h )
    = . h ext_want want
    ( vec_clear [u] . h ext_out )
    ( bytes_extend_bytes . h ext_out ext_out )
}

// Let go of `h` now rather than at the end of its owner's scope.
@ _srv_hs_free sink SrvHs h → v {}

// What the drivers read off the machine (std/quic_tls.nu, and the TCP
// one below through its own pointer). Vecs are the machine's own, lent.
@ _srv_hs_cipher SrvHs h → i { ^ . ( __SrvHs_ptr h ) cipher }

@ _srv_hs_kx_group SrvHs h → i { ^ . ( __SrvHs_ptr h ) kx_group }

@ _srv_hs_resumed SrvHs h → i { ^ . ( __SrvHs_ptr h ) resumed }

@ _srv_hs_out_sh SrvHs h → ( Vec u ) { ^ . ( __SrvHs_ptr h ) out_sh }

@ _srv_hs_out_hs SrvHs h → ( Vec u ) { ^ . ( __SrvHs_ptr h ) out_hs }

@ _srv_hs_out_ticket SrvHs h → ( Vec u ) { ^ . ( __SrvHs_ptr h ) out_ticket }

@ _srv_hs_ext_in SrvHs h → ( Vec u ) { ^ . ( __SrvHs_ptr h ) ext_in }

@ _srv_hs_alpn_sel SrvHs h → ( Vec u ) { ^ . ( __SrvHs_ptr h ) alpn_sel }

@ _srv_hs_res_master SrvHs h → ( Vec u ) { ^ . ( __SrvHs_ptr h ) res_master }

@ _srv_hs_c_hs SrvHs h → ( Vec u ) { ^ . ( __SrvHs_ptr h ) c_hs }

@ _srv_hs_s_hs SrvHs h → ( Vec u ) { ^ . ( __SrvHs_ptr h ) s_hs }

@ _srv_hs_c_ap SrvHs h → ( Vec u ) { ^ . ( __SrvHs_ptr h ) c_ap }

@ _srv_hs_s_ap SrvHs h → ( Vec u ) { ^ . ( __SrvHs_ptr h ) s_ap }

// Mark the machine failed and hand back the alert description.
@ __srv_hs_fail inout SrvHsImpl h i desc → i {
    = . h state 3
    ^ desc
}

// The TLS SignatureScheme for an ML-DSA parameter set
// (draft-ietf-tls-mldsa): mldsa44 0x0904, mldsa65 0x0905, mldsa87 0x0906.
@ __srv_mldsa_scheme i level → i {
    ^ ? == level 44 2308 ? == level 65 2309 2310
}

// Certificate selection, RFC 8446 §4.4.2.2: a server with more than one
// identity picks the one whose signature scheme the client listed in
// signature_algorithms. Here that is a choice between the classical
// leaf the handshake was constructed with and the ML-DSA leaf parked
// by `_srv_hs_set_pq`; the ML-DSA leaf wins whenever the client says it
// can verify it — a client that offers `mldsaNN` is asking for it, and
// nothing classical is left in the handshake once it is chosen. A
// client without the scheme (every stack older than 2025, and every
// OpenSSL before 3.5) gets the classical leaf exactly as before, so
// adding a post-quantum certificate never costs a connection.
//
// No `pq_chain` → nothing to choose. No signature_algorithms extension
// at all is a client that must be refused later anyway (§4.2.3 makes
// it mandatory for certificate authentication); it gets the classical
// leaf and the failure it was heading for.
// The scheme this handshake signs (or signed) its CertificateVerify with.
@ _srv_hs_sig_scheme SrvHs h__h → i {
    : ~ * SrvHsImpl h ( __SrvHs_ptr h__h )
    ^ ( __srv_sig_scheme_of . h 0 )
}

@ __srv_sig_scheme_of inout SrvHsImpl h → i { ^ ( __srv_ident_scheme ( arc_get [TlsIdent] . h id ) ) }

@ __srv_pick_cert inout SrvHsImpl h ( Vec u ) ch i es i ee → v {
    : i want ?? . h pq { T a → ( __srv_ident_scheme ( arc_get [TlsIdent] a ) ) F → 0 }
    ? == want 0 { ^ } {}
    : i sa ( __srv_find_ext ch es ee 13 )
    ? < sa 0 { ^ } {}
    : i extlen ( _rdint ch - sa 2 2 )
    ? | < extlen 2 > + sa extlen ee { ^ } {}
    : i salen ( _rdint ch sa 2 )
    : i saend + + sa 2 salen
    ? > saend + sa extlen { ^ } {}
    : ~ i p + sa 2
    : ~ i hit 0
    ~ & < + p 1 saend == hit 0 {
        ? == ( _rdint ch p 2 ) want { = hit 1 } {}
        = p + p 2
    }
    ? == hit 0 { ^ } {}
    : ( Arc TlsIdent ) chosen ?? . h pq { T a → ( arc_clone [TlsIdent] a ) F → ( arc_clone [TlsIdent] . h id ) }
    = . h id chosen
}

@ _srv_hs_client_hello SrvHs h__h ( Vec u ) ch → i {
    : ~ * SrvHsImpl h ( __SrvHs_ptr h__h )
    ^ ( _srv_hs_client_hello_in . h 0 ch )
}

@ _srv_hs_client_hello_in inout SrvHsImpl h ( Vec u ) ch → i {
    ? != . h state 0 { ^ ( __srv_hs_fail h 10 ) } {}
    // handshake type 1, and a body at least as long as its fixed part
    ? | < ( vec_len [u] ch ) 39 != ( _t_bget ch 0 ) 1 { ^ ( __srv_hs_fail h 50 ) } {}
    ( sha256_update . h trh ch )

    : i sidlen ( _t_bget ch 38 )
    : i p1 + 39 sidlen
    : i cslen ( _rdint ch p1 2 )
    // Choose the cipher. AES-128-GCM (0x1301) when the CPU has the
    // hardware crypto tier — AES-NI and PCLMULQDQ, or AES and PMULL on
    // AArch64 (nurl_cpu_has_aes) — and the client offers it;
    // otherwise ChaCha20-Poly1305 (0x1303) when offered; otherwise
    // AES-128-GCM — TLS_AES_128_GCM_SHA256 is the one suite RFC 8446
    // requires every implementation to have, so every client offers it.
    //
    // That order is what OpenSSL and rustls pick, for the same reason:
    // with AES instructions AES-GCM is the faster suite, without them
    // ChaCha is. It used to be ChaCha unconditionally here — back when
    // AES-GCM ran at 0.5 MB/s, then bitsliced at ~113 MB/s against
    // ChaCha's ~370, NURL having no AES instruction path. With the
    // crypto tier (std/aes_gcm.nu's hardware path) AES-128-GCM seals a
    // 16 KB record at ~3 GB/s on a Haswell (~9–12 on VAES) against
    // ChaCha's ~1.4, and a 32-byte one in a third of the time even when
    // the key is expanded per record. The two
    // suites are equally strong.
    : b hw_aes ( nurl_cpu_has_aes )
    : ~ b off_aes F
    : ~ b off_cc F
    : ~ i ci 0
    ~ < ci cslen {
        : i s2 ( _rdint ch + + p1 2 ci 2 )
        ? == s2 4865 { = off_aes T } {}
        ? == s2 4867 { = off_cc T } {}
        = ci + ci 2
    }
    : ~ i suite 4867
    ? & hw_aes off_aes { = suite 4865 } { ? off_cc { = suite 4867 } { ? off_aes { = suite 4865 } {} } }
    = . h cipher ? == suite 4865 1 0
    : i p2 + + p1 2 cslen
    : i complen ( _t_bget ch p2 )
    : i p3 + + p2 1 complen
    : i extlen ( _rdint ch p3 2 )
    : i es + p3 2
    : i ee + es extlen
    ? > ee ( vec_len [u] ch ) { ^ ( __srv_hs_fail h 50 ) } {}

    // Which identity this connection gets (§4.4.2.2) — decided before
    // anything below reads the identity.
    ( __srv_pick_cert h ch es ee )

    // key_share (0x0033): pick x25519 (0x001d) if offered, else secp256r1.
    : i ks ( __srv_find_ext ch es ee 51 )
    ? < ks 0 { ^ ( __srv_hs_fail h 109 ) } {}
    : i kslen ( _rdint ch ks 2 )  // client_shares length (first 2 bytes of ext body)
    : i ksend + + ks 2 kslen
    : ~ i grp 0
    : ~ ( Vec u ) cpub ( vec_new [u] )
    // Preference order, most-preferred first: X25519MLKEM768, x25519,
    // secp256r1. A share whose length is wrong for its group is ignored
    // rather than trusted — every one of these is a fixed size, and the
    // slicing below depends on it.
    : ( Vec u ) sh_pq ( __srv_find_share ch ks ksend 4588 )
    ? == ( vec_len [u] sh_pq ) 1216 {
        = grp 4588
        = cpub ( bytes_slice sh_pq 0 1216 )
    } {}
    ? == grp 0 {
        : ( Vec u ) sh_x ( __srv_find_share ch ks ksend 29 )
        ? == ( vec_len [u] sh_x ) 32 {
            = grp 29
            = cpub ( bytes_slice sh_x 0 32 )
        } {}
    } {}
    ? == grp 0 {
        : ( Vec u ) sh_p ( __srv_find_share ch ks ksend 23 )
        ? == ( vec_len [u] sh_p ) 65 {
            = grp 23
            = cpub ( bytes_slice sh_p 0 65 )
        } {}
    } {}
    ? == grp 0 {
        ^ ( __srv_hs_fail h 40 )
    } {}

    // ── the caller's required extension (QUIC: transport parameters) ──
    ? != . h ext_want 0 {
        : i xo ( __srv_find_ext ch es ee . h ext_want )
        ? < xo 0 {
            ^ ( __srv_hs_fail h 109 )
        } {}
        : i xl ( _rdint ch - xo 2 2 )
        ? > + xo xl ee {
            ^ ( __srv_hs_fail h 50 )
        } {}
        = . h ext_in_present 1
        ( vec_clear [u] . h ext_in )
        : ( Vec u ) xb ( bytes_slice ch xo + xo xl )
        ( bytes_extend_bytes . h ext_in xb )
    } {}

    // ── ALPN (RFC 7301) ──
    // Decided here, before anything is sent: a client that offered ALPN
    // but nothing we serve gets a fatal no_application_protocol alert
    // (§3.2) instead of a connection it will then misuse. A client that
    // sent no ALPN, or a listener with no preference list, negotiates
    // nothing and the EncryptedExtensions below stay empty.
    : ( Vec u ) alpn_sel ( __srv_select_alpn ch es ee . h alpn_prefs )
    ? & & > ( vec_len [u] . h alpn_prefs ) 0 >= ( __srv_find_ext ch es ee 16 ) 0
    == ( vec_len [u] alpn_sel ) 0 {
        ^ ( __srv_hs_fail h 120 )
    } {}
    = . h alpn_sel alpn_sel

    // ── resumption offer? ──
    // A ticket of ours with a good binder makes this the abbreviated
    // handshake: early secret from the PSK, ServerHello says which
    // identity, no Certificate / CertificateVerify. The (EC)DHE above
    // still happens (psk_dhe_ke), so the keys are fresh either way.
    : ( Vec u ) psk ( vec_new [u] )
    : i psk_sel ( __srv_psk_offer ch es ee psk )
    ? >= psk_sel 0 { = . h resumed 1 } {}
    = . h can_resume ? ( __srv_client_can_resume ch es ee ) 1 0

    // ── server ephemeral + shared secret ──
    //
    // For X25519MLKEM768 the server is the *encapsulating* side: the
    // client sent an ML-KEM encapsulation key, and the reply carries the
    // ciphertext, not a public key. Both halves keep the group's byte
    // order — ML-KEM first, X25519 second — in the share and in the
    // secret alike.
    = . h kx_group grp
    : ( Vec u ) eph ( __srv_rand 32 )
    : ~ ( Vec u ) spub ( vec_new [u] )
    : ~ ( Vec u ) ecdhe ( vec_new [u] )
    ? == grp 4588 {
        : ( Vec u ) cek ( bytes_slice cpub 0 1184 )
        : ( Vec u ) cx ( bytes_slice cpub 1184 1216 )
        : MlkemEncap en ( mlkem_encaps 768 cek )
        : ( Vec u ) sx ( x25519_base eph )
        : ( Vec u ) xs ( x25519 eph cx )
        = spub ( bytes_slice ( mlkem_ct en ) 0 1088 )
        ( bytes_extend_bytes spub sx )
        // The X25519 half is checked on its own, before the halves are
        // joined: a low-order client point zeroes it while the ML-KEM
        // half stays random, so the concatenation would look fine.
        // Leaving `ecdhe` empty here makes the shared all-zero test
        // below fail closed.
        ? ( _all_zero xs ) {} {
            = ecdhe ( bytes_slice ( mlkem_ss en ) 0 32 )
            ( bytes_extend_bytes ecdhe xs )
        }
    } {
        = spub ? == grp 29 ( x25519_base eph ) ( p256_ecdh_keygen eph )
        = ecdhe ? == grp 29 ( x25519 eph cpub ) ( p256_ecdh_shared eph cpub )
    }
    // H3: RFC 8446 §7.4.2 — reject a degenerate (all-zero) ECDHE secret from a
    // low-order client key_share before it can seed the key schedule.
    ? ( _all_zero ecdhe ) {
        ^ ( __srv_hs_fail h 47 )
    } {}

    // ── ServerHello ──
    : ( Vec u ) srand ( __srv_rand 32 )
    : ( Vec u ) sh ( __srv_build_sh srand ch sidlen suite grp spub psk_sel )
    ( sha256_update . h trh sh )
    ( vec_clear [u] . h out_sh )
    ( bytes_extend_bytes . h out_sh sh )

    // ── key schedule (handshake) ──
    : ( Vec u ) z32 ( __srv_zeros 32 )
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) ehash ( sha256_pure empty )
    : ( Vec u ) early ? == . h resumed 1 ( _psk_early psk ) ( hkdf_extract empty z32 )
    : ( Vec u ) derived1 ( derive_secret early `derived` ehash )
    // handshake_secret derives three secrets: prepared once.
    : ( Vec u ) hs_secret ( hkdf_extract derived1 ecdhe )
    : HmacSha256 hsk ( hmac_sha256_key hs_secret )
    : ( Vec u ) th_sh ( sha256_snapshot . h trh )
    = . h c_hs ( derive_secret_prk hsk `c hs traffic` th_sh )
    = . h s_hs ( derive_secret_prk hsk `s hs traffic` th_sh )
    : ( Vec u ) derived2 ( derive_secret_prk hsk `derived` ehash )
    = . h master ( hkdf_extract derived2 z32 )

    // ── EncryptedExtensions ──
    // Empty unless ALPN was negotiated and/or the caller has extensions
    // to carry (QUIC transport parameters). ALPN is one
    // application_layer_protocol_negotiation (0x0010) extension carrying
    // a one-entry ProtocolNameList with the selected name (RFC 7301
    // §3.1; RFC 8446 §4.3.1 puts it here, not in the ServerHello).
    : ( Vec u ) eebody ( vec_new [u] )
    : i asl ( vec_len [u] . h alpn_sel )
    : ( Vec u ) exts ( vec_with_cap [u] + + asl 7 ( vec_len [u] . h ext_out ) )
    ? > asl 0 {
        : ( Vec u ) alp ( vec_with_cap [u] + asl 3 )
        ( _tls_u16 alp + asl 1 )  // ProtocolNameList length
        ( vec_push [u] alp # u asl )  // protocol name length
        ( _tls_cat alp . h alpn_sel )
        ( _tls_u16 exts 16 )
        ( _blk16 exts alp )
    } {}
    ( _tls_cat exts . h ext_out )
    ( _blk16 eebody exts )  // extensions length + extensions
    : ( Vec u ) ee ( __srv_hs_wrap 8 eebody )
    ( sha256_update . h trh ee )
    ( vec_clear [u] . h out_hs )
    ( bytes_extend_bytes . h out_hs ee )

    // ── Certificate + CertificateVerify (full handshake only) ──
    // A resumed handshake carries neither: the PSK is the proof of
    // identity (RFC 8446 §4.4.2 — no Certificate when a PSK is in use).
    ? == . h resumed 0 {
        // cert_chain is the certificate_list body: one or more CertificateEntry
        // structs (each [u24 cert_len][DER][u16 ext_len]) already concatenated
        // by the caller via tls_cert_entry — leaf first, then intermediates.
        : ( Vec u ) certbody ( vec_new [u] )
        ( vec_push [u] certbody # u 0 )  // certificate_request_context = empty
        : TlsIdent me ( arc_get [TlsIdent] . h id )
        ( _u24 certbody ( vec_len [u] . me chain ) )  // certificate_list length
        ( _tls_cat certbody . me chain )
        : ( Vec u ) certmsg ( __srv_hs_wrap 11 certbody )
        ( sha256_update . h trh certmsg )
        ( bytes_extend_bytes . h out_hs certmsg )

        // ── CertificateVerify ──
        : ( Vec u ) th_cert ( sha256_snapshot . h trh )
        : ( Vec u ) cvc ( __srv_cv_content th_cert )
        : ( Vec u ) cvdig ( sha256_pure cvc )
        : ( Vec u ) cvbody ( __srv_cv_body me cvdig cvc )
        : ( Vec u ) cvmsg ( __srv_hs_wrap 15 cvbody )
        ( sha256_update . h trh cvmsg )
        ( bytes_extend_bytes . h out_hs cvmsg )
    } {}

    // ── server Finished ──
    : ( Vec u ) th_cv ( sha256_snapshot . h trh )
    : ( Vec u ) sfin ( _finished_mac . h s_hs th_cv )
    : ( Vec u ) sfmsg ( __srv_hs_wrap 20 sfin )
    ( sha256_update . h trh sfmsg )
    ( bytes_extend_bytes . h out_hs sfmsg )

    // ── application keys (transcript through server Finished) ──
    = . h th_sf ( sha256_snapshot . h trh )
    : HmacSha256 mk ( hmac_sha256_key . h master )
    = . h c_ap ( derive_secret_prk mk `c ap traffic` . h th_sf )
    = . h s_ap ( derive_secret_prk mk `s ap traffic` . h th_sf )

    // free scratch / handshake secrets
    = . h state 1
    ^ 0
}

// The client's Finished (under the client handshake keys). On success
// the resumption master secret is derived and, when the client said it
// can resume (§4.2.9), a NewSessionTicket message is built for the
// caller to send first thing under the application keys.
@ _srv_hs_client_finished SrvHs h__h ( Vec u ) cf → i {
    : ~ * SrvHsImpl h ( __SrvHs_ptr h__h )
    ^ ( _srv_hs_client_finished_in . h 0 cf )
}

@ _srv_hs_client_finished_in inout SrvHsImpl h ( Vec u ) cf → i {
    ? != . h state 1 { ^ ( __srv_hs_fail h 10 ) } {}
    ? != ( _t_bget cf 0 ) 20 { ^ ( __srv_hs_fail h 10 ) } {}
    : ( Vec u ) cexp ( _finished_mac . h c_hs . h th_sf )
    : b ok ( _cmp_finished cf cexp )
    ? ! ok { ^ ( __srv_hs_fail h 51 ) } {}
    // The transcript through the client's Finished is what the
    // resumption secret is derived from.
    ( sha256_update . h trh cf )
    : ( Vec u ) th_cf ( sha256_final . h trh )
    = . h res_master ( derive_secret . h master `res master` th_cf )
    ( vec_clear [u] . h out_ticket )
    ? == . h can_resume 1 {
        : ( Vec u ) t ( __srv_ticket_msg . h res_master )
        ( bytes_extend_bytes . h out_ticket t )
    } {}
    = . h state 2
    ^ 0
}

// One NewSessionTicket message. PSK = HKDF-Expand-Label(
// resumption_master_secret, "resumption", nonce, 32) with nonce 0x0000 —
// one ticket per connection.
@ __srv_ticket_msg ( Vec u ) res_master → ( Vec u ) {
    : i lifetime 7200
    : ( Vec u ) nonce ( vec_with_cap [u] 2 )
    ( vec_push [u] nonce # u 0 )
    ( vec_push [u] nonce # u 0 )
    : ( Vec u ) psk ( hkdf_expand_label res_master `resumption` nonce 32 )
    : ( Vec u ) ticket ( __tls_ticket_seal psk lifetime )
    : ( Vec u ) age_add ( __srv_rand 4 )
    : ( Vec u ) body ( vec_new [u] )
    ( _tls_u32 body lifetime )
    ( _tls_cat body age_add )
    ( vec_push [u] body # u 2 )
    ( _tls_cat body nonce )
    ( _blk16 body ticket )
    ( _tls_u16 body 0 )
    : ( Vec u ) msg ( __srv_hs_wrap 4 body )
    ^ msg
}

// Split a concatenation of handshake messages ([type][u24 len][body]…)
// into one record each — the TCP flight keeps one message per record,
// which is what the bytes on the wire have always been.
@ __srv_enc_msgs_to inout TlsConnImpl c ( Vec u ) flight ( Vec u ) msgs → v {
    : ~ i off 0
    : i n ( vec_len [u] msgs )
    ~ < + off 4 n {
        : i mlen ( _rdint msgs + off 1 3 )
        : i end + + off 4 mlen
        ? > end n { ^ } {}
        : ( Vec u ) m ( bytes_slice msgs off end )
        ( __srv_enc_rec_to c flight 22 m )
        = off end
    }
}

@ __tls_accept_impl i raw ( Arc TlsIdent ) id ? ( Arc TlsIdent ) pq ( Vec u ) alpn_prefs → !TlsConn TlsErr {
    ? <= raw 0 { ^ @ !TlsConn TlsErr { F # TlsErr TlsConnect } } {}
    : TlsConn c__h ( _tls_conn_new raw )
    : ~ * TlsConnImpl c ( _tls_ptr c__h )
    // The machine goes with this scope, on every path out of it.
    : SrvHs hs__h ( _srv_hs_new id alpn_prefs )
    ?? pq { T a → ( _srv_hs_set_pq hs__h a ) F → {} }
    : ~ * SrvHsImpl hs ( __SrvHs_ptr hs__h )
    : !v TlsErr r ( __srv_accept . c 0 . hs 0 )
    ^ ?? r { T _ → @ !TlsConn TlsErr { T c__h } F e → @ !TlsConn TlsErr { F e } }
}

// The record layer around the machine: the client's hello in, the first
// flight out in one write, the client's Finished in, keys installed on `c`.
@ __srv_accept inout TlsConnImpl c inout SrvHsImpl hs → !v TlsErr {
    // ── ClientHello ──
    : !( Vec u ) TlsErr chr ( __srv_next_hs c )
    : ( Vec u ) ch ?? chr { T m → m F _ → ( vec_new [u] ) }
    : i rc ( _srv_hs_client_hello_in hs ch )
    ? != rc 0 {
        // no_application_protocol is said out loud (RFC 7301 §3.2);
        // every other refusal closes as it always has.
        ? == rc 120 { ^ ( __srv_abort_alert c 120 ) } {}
        ^ ( __srv_abort c )
    } {}
    = . c cipher . hs cipher
    = . c kx_group . hs kx_group
    = . c resumed . hs resumed
    = . c cv_scheme ? == . hs resumed 0 ( __srv_sig_scheme_of hs ) 0
    = . c alpn_sel ( bytes_slice . hs alpn_sel 0 ( vec_len [u] . hs alpn_sel ) )

    // ── the first flight ──
    // The whole first flight — SH, CCS, EE, Certificate, CertificateVerify,
    // server Finished — is batched into `flight` and leaves in ONE send()
    // after the Finished is built. Six separate writes cost six syscalls
    // and six client-side wakeups per handshake; one flight is also what
    // rustls/OpenSSL put on the wire. A write failure surfaces exactly
    // like any torn handshake: the client-Finished read below fails and
    // the handshake ends in TlsHandshake.
    : ( Vec u ) flight ( vec_with_cap [u] 2048 )
    ( __srv_plain_rec_to flight 22 . hs out_sh )
    // optional CCS for middlebox compatibility
    : ( Vec u ) ccs ( vec_with_cap [u] 1 )
    ( vec_push [u] ccs # u 1 )
    ( __srv_plain_rec_to flight 20 ccs )
    // handshake keys: server writes under s_hs, reads the client under c_hs
    ( _set_keys c 0 . hs s_hs )
    ( _set_keys c 1 . hs c_hs )
    = . c enc_read 1
    ( __srv_enc_msgs_to c flight . hs out_hs )
    : b fw ( _tls_sock_write . c fd flight )
    ? fw {} { ( nurl_eprintln `tls: server flight write failed` ) }

    // ── client Finished (under client handshake keys) ──
    : !( Vec u ) TlsErr cfr ( __srv_next_hs c )
    : ~ i finok 0
    ?? cfr {
        T cf → {
            ? == ( _srv_hs_client_finished_in hs cf ) 0 { = finok 1 } {}
        }
        F _ → {}
    }
    = . c res_master ( bytes_slice . hs res_master 0 ( vec_len [u] . hs res_master ) )

    // switch to application keys
    ( _set_keys c 0 . hs s_ap )
    ( _set_keys c 1 . hs c_ap )
    = . c established 1
    = . c server 1

    // A ticket for next time, first thing under the application keys —
    // only for a client that said it can resume (§4.2.9).
    ? & == finok 1 > ( vec_len [u] . hs out_ticket ) 0 {
        : !v TlsErr _w ( __srv_send_enc c 22 . hs out_ticket )
    } {}

    ? == finok 0 { ( _tls_close_in c ) ^ @ !v TlsErr { F # TlsErr TlsHandshake } } {}
    ( _tls_ktls_auto c )
    ^ @ !v TlsErr { T 0 }
}

// Accept a TLS 1.3 connection with an EC P-256 leaf certificate. `priv`
// is the 32-byte P-256 private scalar (see std/pkey.nu). `cert_chain` is
// a tls_cert_entry-framed certificate_list (leaf first, then any
// intermediates). The original single-cert entry point.
@ tls_accept i raw ( Vec u ) cert_chain ( Vec u ) priv → !TlsConn TlsErr {
    : ( Vec u ) noalpn ( vec_new [u] )
    : !TlsConn TlsErr r ( tls_accept_alpn raw cert_chain priv noalpn )
    ^ r
}

// tls_accept with an ALPN preference list (RFC 7301): `alpn_prefs` is
// the server's protocols in wire form — [len:1][name] entries, most-
// preferred first (`tls_alpn_pack` builds one from "h2 http/1.1"). The
// negotiated protocol is read back with tls_alpn_selected; a client that
// offers ALPN with no protocol in common is refused with a fatal
// no_application_protocol alert. An empty list means "no ALPN".
@ tls_accept_alpn i raw ( Vec u ) cert_chain ( Vec u ) priv ( Vec u ) alpn_prefs → !TlsConn TlsErr {
    : !TlsConn TlsErr r ( tls_accept_ident raw ( tls_ident_ec cert_chain priv ) alpn_prefs )
    ^ r
}

// Accept with a prepared identity (tls_ident_ec / tls_ident_rsa /
// tls_ident_mldsa) — the form a server that accepts more than once uses:
// the key is prepared once, and each handshake takes a count on it.
@ tls_accept_ident i raw ( Arc TlsIdent ) id ( Vec u ) alpn_prefs → !TlsConn TlsErr {
    ^ ( __tls_accept_impl raw id @ ?( Arc TlsIdent ) { F } alpn_prefs )
}

// tls_accept_ident with a second identity `pq` (an ML-DSA leaf), shown to
// every client whose signature_algorithms lists its scheme — see
// tls_accept_dual_alpn.
@ tls_accept_ident_dual i raw ( Arc TlsIdent ) id ( Arc TlsIdent ) pq ( Vec u ) alpn_prefs → !TlsConn TlsErr {
    ^ ( __tls_accept_impl raw id @ ?( Arc TlsIdent ) { T ( arc_clone [TlsIdent] pq ) } alpn_prefs )
}

// `tls_alpn_pack` (the wire form of a "h2 http/1.1" list) lives in
// tls.nu: the client offers with it, the listener prefers with it.

// Accept a TLS 1.3 connection with an RSA leaf certificate, signing the
// CertificateVerify with RSASSA-PSS (rsa_pss_rsae_sha256). `rsa_n` /
// `rsa_e` / `rsa_d` are the modulus / public / private exponent,
// big-endian. `cert_chain` is a tls_cert_entry-framed certificate_list.
// The key is prepared per call and without its factors; a server keeps a
// tls_ident_rsa of std/pkey.nu's rsa_priv_sign_key instead.
@ tls_accept_rsa i raw ( Vec u ) cert_chain ( Vec u ) rsa_n ( Vec u ) rsa_e ( Vec u ) rsa_d → !TlsConn TlsErr {
    : ( Vec u ) noalpn ( vec_new [u] )
    : !TlsConn TlsErr r ( tls_accept_rsa_alpn raw cert_chain rsa_n rsa_e rsa_d noalpn )
    ^ r
}

// tls_accept_rsa with an ALPN preference list — see tls_accept_alpn.
@ tls_accept_rsa_alpn i raw ( Vec u ) cert_chain ( Vec u ) rsa_n ( Vec u ) rsa_e ( Vec u ) rsa_d ( Vec u ) alpn_prefs → !TlsConn TlsErr {
    : !TlsConn TlsErr r ( tls_accept_ident raw ( tls_ident_rsa cert_chain ( rsa_key_plain rsa_n rsa_e rsa_d ) ) alpn_prefs )
    ^ r
}

// Accept a TLS 1.3 connection with an ML-DSA leaf certificate, signing
// the CertificateVerify with ML-DSA itself (`mldsa44`/`mldsa65`/
// `mldsa87`). `sk` is the raw FIPS 204 secret key; `level` is 44, 65 or
// 87 and must match the key the certificate carries.
//
// Combined with the X25519MLKEM768 group this module already prefers,
// nothing in the resulting handshake is breakable by a quantum
// adversary: the traffic keys cannot be recovered from a recording, and
// the server's identity cannot be forged either. No public CA issues
// ML-DSA certificates yet, so the chain has to be private or
// self-signed — `x509_selfsigned_mldsa` in std/x509_gen.nu makes one.
@ tls_accept_mldsa i raw ( Vec u ) cert_chain i level ( Vec u ) sk → !TlsConn TlsErr {
    : ( Vec u ) noalpn ( vec_new [u] )
    : !TlsConn TlsErr r ( tls_accept_mldsa_alpn raw cert_chain level sk noalpn )
    ^ r
}

// tls_accept_mldsa with an ALPN preference list — see tls_accept_alpn.
@ tls_accept_mldsa_alpn i raw ( Vec u ) cert_chain i level ( Vec u ) sk ( Vec u ) alpn_prefs → !TlsConn TlsErr {
    : !TlsConn TlsErr r ( tls_accept_ident raw ( tls_ident_mldsa cert_chain level sk ) alpn_prefs )
    ^ r
}

// Accept with TWO identities and let the client's signature_algorithms
// decide which one it sees (RFC 8446 §4.4.2.2): the classical leaf
// (`keytype` 0 = EC P-256 with `ec_priv`; 1 = RSA with `rsa_n` / `rsa_e`
// / `rsa_d`) for clients that cannot verify ML-DSA, the ML-DSA leaf
// (`pq_chain`, `pq_level`, `pq_sk` — the tls_accept_mldsa inputs) for
// every client that lists `mldsaNN`. This is how a server serves a
// post-quantum certificate to browsers and curl builds that understand
// it while the rest of the world keeps its ECDSA — the same operation
// OpenSSL performs when a context holds one certificate per key type.
// `tcp_listen_tls_dual` (std/net.nu) is the PEM-file front of this.
//
// An empty `pq_chain` makes it tls_accept_alpn / tls_accept_rsa_alpn.
// Both keys are prepared per call (tls_accept_ident_dual takes them
// prepared).
@ tls_accept_dual_alpn i raw ( Vec u ) cert_chain i keytype ( Vec u ) ec_priv ( Vec u ) rsa_n ( Vec u ) rsa_e ( Vec u ) rsa_d ( Vec u ) pq_chain i pq_level ( Vec u ) pq_sk ( Vec u ) alpn_prefs → !TlsConn TlsErr {
    : ( Arc TlsIdent ) id ( __srv_ident_of cert_chain keytype ec_priv rsa_n rsa_e rsa_d 0 )
    ? == ( vec_len [u] pq_chain ) 0 { ^ ( tls_accept_ident raw id alpn_prefs ) } {}
    ^ ( tls_accept_ident_dual raw id ( tls_ident_mldsa pq_chain pq_level pq_sk ) alpn_prefs )
}

@ __srv_rand i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u 0 ) = k + k 1 }
    : i r ( nurl_rand_fill # *u ( vec_data [u] v ) n )
    // L4: fail closed on CSPRNG failure — these bytes are the server random
    // and the ECDHE private scalar.
    ? & > n 0 == r 0 { ( nurl_panic `tls server: CSPRNG (nurl_rand_fill) failed` ) } {}
    ^ v
}

@ __srv_zeros i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u 0 ) = k + k 1 }
    ^ v
}

// Build the ServerHello handshake message.
@ __srv_build_sh ( Vec u ) srand ( Vec u ) ch i sidlen i suite i grp ( Vec u ) spub i psk_sel → ( Vec u ) {
    : ( Vec u ) body ( vec_new [u] )
    ( _tls_u16 body 771 )  // legacy_version 0x0303
    ( _tls_cat body srand )  // 32-byte random
    ( vec_push [u] body # u sidlen )  // echo legacy session id
    : ~ i k 0
    ~ < k sidlen { ( vec_push [u] body # u ( _t_bget ch + 39 k ) ) = k + k 1 }
    ( _tls_u16 body suite )  // cipher suite
    ( vec_push [u] body # u 0 )  // compression = null
    // extensions: supported_versions (0x002b)=0x0304 + key_share (0x0033)
    : ( Vec u ) ext ( vec_new [u] )
    ( _tls_u16 ext 43 )
    ( _tls_u16 ext 2 )
    ( _tls_u16 ext 772 )  // 0x0304 TLS 1.3
    ( _tls_u16 ext 51 )
    ( _tls_u16 ext + 4 ( vec_len [u] spub ) )
    ( _tls_u16 ext grp )
    ( _tls_u16 ext ( vec_len [u] spub ) )
    ( _tls_cat ext spub )
    // pre_shared_key (0x0029): the identity we took, when resuming.
    ? >= psk_sel 0 {
        ( _tls_u16 ext 41 )
        ( _tls_u16 ext 2 )
        ( _tls_u16 ext psk_sel )
    } {}
    ( _blk16 body ext )
    : ( Vec u ) hs ( __srv_hs_wrap 2 body )
    ^ hs
}

// ── post-handshake server I/O (server keys for write, client for read) ──

// Application data is split into ≤16384-byte records — the RFC 8446
// §5.1 plaintext cap; peers reject larger records, and past 65535 the
// header's u16 length wraps (a >64 KB response used to come out as
// garbage the client reported as "bad record mac").
@ tls_server_write TlsConn c__h ( Vec u ) data → !v TlsErr {
    : ~ * TlsConnImpl c ( _tls_ptr c__h )
    ^ ( _tls_server_write_in . c 0 data )
}

@ _tls_server_write_in inout TlsConnImpl c ( Vec u ) data → !v TlsErr {
    ?? ( _tls_flush_control c 0 ) { T _ → {} F error → { ^ @ !v TlsErr { F error } } }
    ? != . c closed 0 { ^ @ !v TlsErr { F TlsClosed } } {}
    ^ ( _tls_write_records c 0 data data ( vec_len [u] data ) T )
}

// Server-direction counterpart of tls_prepare_write; no socket I/O.
@ tls_server_prepare_write TlsConn c__h ( Vec u ) data → !( Vec u ) TlsErr {
    : ~ * TlsConnImpl c ( _tls_ptr c__h )
    ^ ( _tls_server_prepare_write_in . c 0 data )
}

@ _tls_server_prepare_write_in inout TlsConnImpl c ( Vec u ) data → !( Vec u ) TlsErr {
    ? | != . c closed 0 != . c established 1 {
        ^ @ !( Vec u ) TlsErr { F TlsClosed }
    } {}
    ? & != . c fatal_alert 0 > ( vec_len [u] data ) 0 { ^ @ !( Vec u ) TlsErr { F TlsProtocol } } {}
    : ( Vec u ) wire ( vec_new [u] )
    ( _tls_control_to c wire 0 )
    : ~ i offset 0
    : i size ( vec_len [u] data )
    ~ < offset size {
        : i end ? < - size offset 16384 size + offset 16384
        ( _tls_rec_range_to c wire 0 23 data offset end )
        = offset end
    }
    ^ @ !( Vec u ) TlsErr { T wire }
}

// Pair variant of tls_server_prepare_write: records are cut from
// `head`‖`body` straight into `out` — the caller's ciphertext FIFO — so a
// queued HTTP/2 frame (9-byte header + payload) is sealed once with no
// intermediate plaintext or wire buffer. Same record boundaries as
// tls_server_write2 over the joined bytes.
@ tls_server_prepare_write2_to TlsConn c__h ( Vec u ) out ( Vec u ) head ( Vec u ) body → !v TlsErr {
    : ~ * TlsConnImpl c ( _tls_ptr c__h )
    ^ ( _tls_server_prepare_write2_to_in . c 0 out head body )
}

@ _tls_server_prepare_write2_to_in inout TlsConnImpl c ( Vec u ) out ( Vec u ) head ( Vec u ) body → !v TlsErr {
    ? | != . c closed 0 != . c established 1 { ^ @ !v TlsErr { F TlsClosed } } {}
    : i n + ( vec_len [u] head ) ( vec_len [u] body )
    ? & != . c fatal_alert 0 > n 0 { ^ @ !v TlsErr { F TlsProtocol } } {}
    ( _tls_control_to c out 0 )
    : ~ i off 0
    ~ < off n {
        : ~ i hi + off 16384
        ? > hi n { = hi n } {}
        ( _tls_rec_pair_to c out 0 23 head body off hi )
        = off hi
    }
    ^ @ !v TlsErr { T 0 }
}

// Two-buffer variant for net.nu's tcp_write_all2: records are cut from
// the logical concatenation `head`‖`body` (see _tls_pair_slice), so the
// HTTP server's response head and body are never joined into one
// plaintext buffer first. Record boundaries are identical to
// tls_server_write over the joined bytes — same wire, one copy less.
@ tls_server_write2 TlsConn c__h ( Vec u ) head ( Vec u ) body → !v TlsErr {
    : ~ * TlsConnImpl c ( _tls_ptr c__h )
    ^ ( _tls_server_write2_in . c 0 head body )
}

@ _tls_server_write2_in inout TlsConnImpl c ( Vec u ) head ( Vec u ) body → !v TlsErr {
    ?? ( _tls_flush_control c 0 ) { T _ → {} F error → { ^ @ !v TlsErr { F error } } }
    ? != . c closed 0 { ^ @ !v TlsErr { F TlsClosed } } {}
    ^ ( _tls_write_records c 0 head body + ( vec_len [u] head ) ( vec_len [u] body ) F )
}

// Server-side close. The close_notify alert must go out under the
// SERVER write keys — tls_close's alert path encrypts with the
// client-direction keys (right for a client conn, garbage from the
// server: an OpenSSL peer that reads to EOF aborted with "bad record
// mac" on our alert, while a Content-Length-bounded client never
// noticed). Send the alert under s_key/s_seq here, then let tls_close
// do the shared teardown (its alert is skipped once closed = 1).
@ tls_server_close TlsConn c__h → v {
    : ~ * TlsConnImpl c ( _tls_ptr c__h )
    ( _tls_server_close_in . c 0 )
}

@ _tls_server_close_in inout TlsConnImpl c → v {
    ? != . c fatal_alert 0 {
        : !v TlsErr sent ( _tls_flush_control c 0 )
        ?? sent { T _ → {} F _ → {} }
    } {}
    ? & == . c closed 0 == . c established 1 {
        : ( Vec u ) alert ( vec_with_cap [u] 2 )
        ( vec_push [u] alert # u 1 )
        ( vec_push [u] alert # u 0 )
        : !v TlsErr _w ( __srv_send_enc c 21 alert )
        = . c closed 1
    } {}
    ( _tls_close_in c )
}

@ tls_server_read TlsConn c__h i max → !( Vec u ) TlsErr {
    : ~ * TlsConnImpl c ( _tls_ptr c__h )
    ^ ( _tls_server_read_in . c 0 max )
}

@ _tls_server_read_in inout TlsConnImpl c i max → !( Vec u ) TlsErr {
    : ( Vec u ) out ( vec_new [u] )
    : !i TlsErr r ( _tls_read_into_in c 1 out max )
    ?? r { T _ → ^ @ !( Vec u ) TlsErr { T out } F e → ^ @ !( Vec u ) TlsErr { F e } }
}

// Server-side tls_read_into: up to `max` decrypted application bytes
// appended to `dst`, Ok(n), 0 on clean EOF; the plaintext is copied once,
// from the record buffer into `dst`.
@ tls_server_read_into TlsConn c__h ( Vec u ) dst i max → !i TlsErr {
    : ~ * TlsConnImpl c ( _tls_ptr c__h )
    ^ ( _tls_read_into_in . c 0 1 dst max )
}
