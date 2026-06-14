// noise_handshake.nu — offline test for stdlib/net/noise.nu. The keys are
// random, so we assert PROPERTIES (deterministic YES/NO), not byte values:
//   1. msg1 + msg2 both verify (handshake completes)
//   2. the responder learns the initiator's static key (IK identity)
//   3. both sides derive matching transport keys (init.send == resp.recv,
//      init.recv == resp.send)
//   4. a message encrypted with init.send decrypts with resp.recv

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/crypto.nu`
$ `stdlib/net/noise.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a )
    ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b eq T
    : ~ i k 0
    ~ & eq < k n {
        : i x ?? ( vec_get [u] a k ) { T t → # i t F → -1 }
        : i y ?? ( vec_get [u] b k ) { T t → # i t F → -2 }
        ? != x y { = eq F } {}
        = k + k 1
    }
    ^ eq
}

@ fill32 i b → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] 32 )
    : ~ i k 0
    ~ < k 32 { ( vec_push [u] v # u b ) = k + k 1 }
    ^ v
}

@ main → i {
    : CryptoKeypair rkp ?? ( x25519_keygen ) { T k → k F _ → @ CryptoKeypair { ( vec_new [u] ) ( vec_new [u] ) } }
    : CryptoKeypair ikp ?? ( x25519_keygen ) { T k → k F _ → @ CryptoKeypair { ( vec_new [u] ) ( vec_new [u] ) } }
    : ( Vec u ) psk ( fill32 66 )

    // initiator knows the responder's static public; responder passes its own.
    : *Handshake ih ( noise_init T ikp . rkp pk psk )
    : *Handshake rh ( noise_init F rkp . rkp pk psk )

    : ( Vec u ) m1 ( noise_write_msg1 ih )
    : !v NoiseErr r1 ( noise_read_msg1 rh m1 )
    ( pb `msg1 verified: ` ?? r1 { T _ → T F _ → F } )

    : ( Vec u ) m2 ( noise_write_msg2 rh )
    : !v NoiseErr r2 ( noise_read_msg2 ih m2 )
    ( pb `msg2 verified: ` ?? r2 { T _ → T F _ → F } )

    // responder learned initiator's static (IK)
    ( pb `responder learned init static: ` ( veq . rh rs . ikp pk ) )

    : NoiseKeys ik ( noise_split ih )
    : NoiseKeys rk ( noise_split rh )
    ( pb `keys agree (send/recv): ` & ( veq . ik send . rk recv ) ( veq . ik recv . rk send ) )

    // transport round trip with the split keys
    : ( Vec u ) nonce ( vec_with_cap [u] 12 )
    : ~ i z 0
    ~ < z 12 { ( vec_push [u] nonce # u 0 ) = z + z 1 }
    : ( Vec u ) ad ( vec_new [u] )
    : ( Vec u ) pt ( vec_new [u] )
    ( bytes_extend_str pt `hello mesh` )
    : ( Vec u ) ct ?? ( chacha20poly1305_encrypt . ik send nonce ad pt ) { T x → x F _ → ( vec_new [u] ) }
    : ( Vec u ) dec ?? ( chacha20poly1305_decrypt . rk recv nonce ad ct ) { T x → x F _ → ( vec_new [u] ) }
    ( pb `transport round-trip: ` ( veq dec pt ) )

    ( vec_free [u] m1 ) ( vec_free [u] m2 )
    ( noise_keys_free ik ) ( noise_keys_free rk )
    ( noise_free ih ) ( noise_free rh )
    ( vec_free [u] psk ) ( vec_free [u] nonce ) ( vec_free [u] ad )
    ( vec_free [u] pt ) ( vec_free [u] ct ) ( vec_free [u] dec )
    ( vec_free [u] . rkp sk ) ( vec_free [u] . rkp pk )
    ( vec_free [u] . ikp sk ) ( vec_free [u] . ikp pk )
    ^ 0
}
