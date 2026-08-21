// net_securedgram.nu — the encrypted-UDP leg, chunking included.
//
// Two SecureNodes on loopback handshake and exchange messages, small
// and BIG: a message over securedgram_chunk_bytes travels as several
// AEAD datagrams and securedgram_recv hands back only the whole,
// reassembled message. The reassembler is also fed BY HAND with the
// hostile sequences a socket cannot conveniently produce — the chunk
// header is authenticated, so the attacker model is a hostile-but-
// authentic peer, and each bound below is a refusal of its worst case:
//   * out-of-order arrival completes; a duplicate slot is dropped
//   * a chunk disagreeing with its own header (short non-final, bad
//     idx/cnt) is dropped, never buffered
//   * the partial table is capped: the oldest in-flight message is
//     evicted, the table never grows
//
// requires: live

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/crypto.nu`
$ `stdlib/net/securedgram.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ k32 i b → ( Vec u ) { : ( Vec u ) v ( vec_with_cap [u] 32 ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u b ) = k + k 1 } ^ v }

// A patterned payload whose content survives a reorder test: byte k is
// a function of k, so any misplaced chunk shows as a value mismatch.
@ pattern i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u & + * k 31 7 255 ) = k + k 1 }
    ^ v
}

@ veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a )
    ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T
    : ~ i k 0
    ~ & e < k n {
        : i x ?? ( vec_get [u] a k ) { T t → # i t F → -1 }
        : i y ?? ( vec_get [u] b k ) { T t → # i t F → -2 }
        ? != x y { = e F } {}
        = k + k 1
    }
    ^ e
}

// Pump `node` until a transport message arrives (bounded — chunked
// messages take several datagrams before one completes).
@ pump * SecureNode node i tries → ?RecvData {
    : ~ i t 0
    : ~ b done F
    : ~ ? RecvData out @ ?RecvData { F # RecvData 0 }
    ~ & ! done < t tries {
        : ?RecvData r ( securedgram_recv node 2048 )
        ?? r { T d → { = out @ ?RecvData { T d } = done T } F → {} }
        = t + t 1
    }
    ^ out
}

// A bare PeerState with only what __sdg_reasm touches — the hand-fed
// hostile cases go straight at the reassembler.
@ mk_peer → *PeerState {
    : *PeerState p # *PeerState ( nurl_alloc Z PeerState )
    = . p pubkey ( vec_new [u] )
    = . p ehost ( string_new )
    = . p eport 0
    = . p local_index 0
    = . p remote_index 0
    = . p hs # s 0
    = . p session # s 0
    = . p established 0
    = . p tx_msg_id 0
    = . p partials ( vec_new [s] )
    ^ p
}

// One chunk of `whole` as __sdg_reasm wants it fed.
@ chunk_of ( Vec u ) whole i idx i cnt → ( Vec u ) {
    : i cb ( securedgram_chunk_bytes )
    : i off * idx cb
    : i len ( vec_len [u] whole )
    : i take ? > + off cb len - len off cb
    : ( Vec u ) v ( vec_with_cap [u] take )
    : ~ i k 0
    ~ < k take { ( vec_push [u] v # u ?? ( vec_get [u] whole + off k ) { T x → # i x F → 0 } ) = k + k 1 }
    ^ v
}

@ main → i {
    : i cb ( securedgram_chunk_bytes )

    // ── the reassembler, fed by hand ────────────────────────────
    : *PeerState hp ( mk_peer )
    : ( Vec u ) m2 ( pattern + * 2 cb 0 )  // exactly 2 full chunks... minus nothing: 2*cb → last chunk full-size is LEGAL? cnt=2, last must be 1..cb → cb ok
    // out of order: idx 1 first, then idx 0 completes
    : ?( Vec u ) r1 ( __sdg_reasm hp 7 1 2 ( chunk_of m2 1 2 ) )
    ( pb `chunk 1 alone incomplete: ` ?? r1 { T w → { ( vec_free [u] w ) F } F → T } )
    : ?( Vec u ) r2 ( __sdg_reasm hp 7 0 2 ( chunk_of m2 0 2 ) )
    ?? r2 {
        T w → { ( pb `out-of-order completes:   ` ( veq w m2 ) ) ( vec_free [u] w ) }
        F → { ( pb `out-of-order completes:   ` F ) }
    }
    // duplicate slot: same idx twice never completes a 3-chunk message
    : ( Vec u ) m3 ( pattern + * 2 cb 5 )
    : ?( Vec u ) d1 ( __sdg_reasm hp 8 0 3 ( chunk_of m3 0 3 ) )
    : ?( Vec u ) d2 ( __sdg_reasm hp 8 0 3 ( chunk_of m3 0 3 ) )
    ( pb `duplicate idx dropped:    ` ?? d2 { T w → { ( vec_free [u] w ) F } F → T } )
    // a short NON-final chunk must be refused (never buffered)
    : ( Vec u ) shortc ( pattern 10 )
    : ?( Vec u ) s1 ( __sdg_reasm hp 9 0 3 shortc )
    ( pb `short non-final refused:  ` ?? s1 { T w → { ( vec_free [u] w ) F } F → T } )
    // cnt below 2 and idx past cnt are refused
    : ?( Vec u ) b1 ( __sdg_reasm hp 10 0 1 ( chunk_of m2 0 2 ) )
    : ?( Vec u ) b2 ( __sdg_reasm hp 11 5 2 ( chunk_of m2 0 2 ) )
    ( pb `cnt/idx bounds refused:   ` && ?? b1 { T w → { ( vec_free [u] w ) F } F → T } ?? b2 { T w → { ( vec_free [u] w ) F } F → T } )
    // eviction: opening a 5th partial evicts the OLDEST (msg 7 is long
    // gone; 8 was opened first of the living) — finish msg 8 after four
    // newer ones opened; its first chunk must have been evicted, so the
    // finish opens a FRESH partial instead of completing
    : ?( Vec u ) e1 ( __sdg_reasm hp 20 0 3 ( chunk_of m3 0 3 ) )
    : ?( Vec u ) e2 ( __sdg_reasm hp 21 0 3 ( chunk_of m3 0 3 ) )
    : ?( Vec u ) e3 ( __sdg_reasm hp 22 0 3 ( chunk_of m3 0 3 ) )
    : ?( Vec u ) e4 ( __sdg_reasm hp 23 0 3 ( chunk_of m3 0 3 ) )
    : ?( Vec u ) e5 ( __sdg_reasm hp 8 1 3 ( chunk_of m3 1 3 ) )
    : ?( Vec u ) e6 ( __sdg_reasm hp 8 2 3 ( chunk_of m3 2 3 ) )
    ( pb `oldest partial evicted:   ` ?? e6 { T w → { ( vec_free [u] w ) F } F → T } )
    ( vec_free [u] m2 )
    ( vec_free [u] m3 )
    ( __peer_free hp )

    // ── two real nodes over loopback ────────────────────────────
    : CryptoKeypair akp ?? ( x25519_keygen ) { T k → k F _ → @ CryptoKeypair { ( vec_new [u] ) ( vec_new [u] ) } }
    : CryptoKeypair bkp ?? ( x25519_keygen ) { T k → k F _ → @ CryptoKeypair { ( vec_new [u] ) ( vec_new [u] ) } }
    : ( Vec u ) psk ( k32 42 )
    : !*SecureNode NetErr ar ( securedgram_open `127.0.0.1` 9830 akp psk )
    : !*SecureNode NetErr br ( securedgram_open `127.0.0.1` 9831 bkp psk )
    ?? ar {
        T an → {
            ?? br {
                T bn → {
                    ( securedgram_add_peer an . bkp pk `127.0.0.1` 9831 )
                    ( securedgram_add_peer bn . akp pk `127.0.0.1` 9830 )
                    : !v NetErr _c ( securedgram_connect an . bkp pk )
                    : ?RecvData _h1 ( securedgram_recv bn 2048 )
                    : ?RecvData _h2 ( securedgram_recv an 2048 )
                    // small message: the [0] fast path
                    : ( Vec u ) small ( pattern 100 )
                    : !v NetErr _s1 ( securedgram_send an . bkp pk small )
                    ?? ( pump bn 20 ) {
                        T d → { ( pb `small round trip:         ` ( veq . d data small ) ) ( recvdata_free d ) }
                        F → { ( pb `small round trip:         ` F ) }
                    }
                    ( vec_free [u] small )
                    // A multi-chunk message, sized so the burst fits the
                    // SMALLEST default UDP receive buffer among the
                    // platforms this suite runs on: this test sends
                    // everything before it reads a byte, and FreeBSD's
                    // default udp recvspace (~42 kB) is a fifth of
                    // Linux's — at 100 kB the chunks were dropped by the
                    // kernel, the message never completed, and the test
                    // spent its whole timeout budget in 500 ms recv
                    // timeouts. A real receiver drains as chunks land;
                    // this one deliberately does not, so it must stay
                    // under the buffer. 24 kB = 21 chunks.
                    : ( Vec u ) big ( pattern 24000 )
                    : !v NetErr _s2 ( securedgram_send an . bkp pk big )
                    ?? ( pump bn 300 ) {
                        T d → { ( pb `24 kB chunked trip:       ` ( veq . d data big ) ) ( recvdata_free d ) }
                        F → { ( pb `24 kB chunked trip:       ` F ) }
                    }
                    // and back, the other direction, right after
                    : !v NetErr _s3 ( securedgram_send bn . akp pk big )
                    ?? ( pump an 300 ) {
                        T d → { ( pb `reverse chunked trip:     ` ( veq . d data big ) ) ( recvdata_free d ) }
                        F → { ( pb `reverse chunked trip:     ` F ) }
                    }
                    ( vec_free [u] big )
                    // an oversize send is refused up front, not
                    // truncated and not half-sent
                    : ( Vec u ) huge ( pattern + ( securedgram_max_msg ) 1 )
                    : !v NetErr toolarge ( securedgram_send an . bkp pk huge )
                    ( pb `oversize refused:         ` ?? toolarge { T _ → F F e → T } )
                    ( vec_free [u] huge )
                    ( securedgram_close bn )
                    ( securedgram_close an )
                }
                F e → { ( nurl_print `FAIL: node B did not open\n` ) }
            }
        }
        F e → { ( nurl_print `FAIL: node A did not open\n` ) }
    }
    ( vec_free [u] psk )
    ( nurl_print `net_securedgram done\n` )
    ^ 0
}
