// noise_session.nu — offline test for stdlib/net/session.nu. Keys come from a
// real (random) Noise handshake, so we assert outcomes (accept/reject,
// plaintext match), which are deterministic regardless of the key bytes:
//   * in-order messages decrypt to the original plaintext
//   * a replayed datagram is rejected (sliding-window dedup)
//   * out-of-order delivery within the window is accepted
//   * a tampered ciphertext fails authentication

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/crypto.nu`
$ `stdlib/net/noise.nu`
$ `stdlib/net/session.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a )
    ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n {
        : i x ?? ( vec_get [u] a k ) { T t → # i t F → -1 }
        : i y ?? ( vec_get [u] b k ) { T t → # i t F → -2 }
        ? != x y { = e F } {}
        = k + k 1
    }
    ^ e
}

@ mkpt s text → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( bytes_extend_str v text )
    ^ v
}

@ k32 i b → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] 32 )
    : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u b ) = k + k 1 }
    ^ v
}

// open + check accept AND plaintext == expected; frees the result.
@ open_eq *NoiseSession rx i ctr ( Vec u ) ad Sealed s ( Vec u ) expect → b {
    : ?( Vec u ) r ( session_open rx ctr ad . s ct )
    ^ ?? r { T pt → { : b ok ( veq pt expect ) ( vec_free [u] pt ) ok } F → F }
}

@ open_rejected *NoiseSession rx i ctr ( Vec u ) ad ( Vec u ) ct → b {
    : ?( Vec u ) r ( session_open rx ctr ad ct )
    ^ ?? r { T pt → { ( vec_free [u] pt ) F } F → T }   // T = correctly rejected
}

@ main → i {
    // establish keys via a real handshake
    : CryptoKeypair rkp ?? ( x25519_keygen ) { T k → k F _ → @ CryptoKeypair { ( vec_new [u] ) ( vec_new [u] ) } }
    : CryptoKeypair ikp ?? ( x25519_keygen ) { T k → k F _ → @ CryptoKeypair { ( vec_new [u] ) ( vec_new [u] ) } }
    : ( Vec u ) psk ( k32 9 )
    : *Handshake ih ( noise_init T ikp . rkp pk psk )
    : *Handshake rh ( noise_init F rkp . rkp pk psk )
    : ( Vec u ) m1 ( noise_write_msg1 ih )
    : !v NoiseErr _r1 ( noise_read_msg1 rh m1 )
    : ( Vec u ) m2 ( noise_write_msg2 rh )
    : !v NoiseErr _r2 ( noise_read_msg2 ih m2 )
    : NoiseKeys ik ( noise_split ih )
    : NoiseKeys rk ( noise_split rh )

    : *NoiseSession tx ( session_new ik )    // initiator sends
    : *NoiseSession rx ( session_new rk )    // responder receives
    : ( Vec u ) ad ( vec_new [u] )

    : ( Vec u ) p0 ( mkpt `frame-0` )
    : ( Vec u ) p1 ( mkpt `frame-1` )
    : ( Vec u ) p2 ( mkpt `frame-2` )
    : ( Vec u ) p3 ( mkpt `frame-3` )

    : Sealed s0 ( session_seal tx ad p0 )
    : Sealed s1 ( session_seal tx ad p1 )
    : Sealed s2 ( session_seal tx ad p2 )
    : Sealed s3 ( session_seal tx ad p3 )

    ( pb `in-order 0: ` ( open_eq rx . s0 counter ad s0 p0 ) )
    ( pb `in-order 1: ` ( open_eq rx . s1 counter ad s1 p1 ) )
    ( pb `replay 0 rejected: ` ( open_rejected rx . s0 counter ad . s0 ct ) )

    // out-of-order within window: deliver 3 before 2
    ( pb `reorder 3 then 2: ` & ( open_eq rx . s3 counter ad s3 p3 ) ( open_eq rx . s2 counter ad s2 p2 ) )

    // tampered ciphertext (flip first byte) fails auth
    : ( Vec u ) p4 ( mkpt `frame-4` )
    : Sealed s4 ( session_seal tx ad p4 )
    : ( Vec u ) bad ( vec_new [u] )
    ( vec_extend [u] bad . s4 ct )
    ?? ( vec_get [u] bad 0 ) { T b0 → ( vec_set [u] bad 0 # u + & # i b0 1 1 ) F → {} }
    ( pb `tamper rejected: ` ( open_rejected rx . s4 counter ad bad ) )

    ( vec_free [u] m1 ) ( vec_free [u] m2 )
    ( noise_keys_free ik ) ( noise_keys_free rk )
    ( noise_free ih ) ( noise_free rh )
    ( session_free tx ) ( session_free rx )
    ( sealed_free s0 ) ( sealed_free s1 ) ( sealed_free s2 ) ( sealed_free s3 ) ( sealed_free s4 )
    ( vec_free [u] ad ) ( vec_free [u] psk ) ( vec_free [u] bad )
    ( vec_free [u] p0 ) ( vec_free [u] p1 ) ( vec_free [u] p2 ) ( vec_free [u] p3 ) ( vec_free [u] p4 )
    ( vec_free [u] . rkp sk ) ( vec_free [u] . rkp pk )
    ( vec_free [u] . ikp sk ) ( vec_free [u] . ikp pk )
    ^ 0
}
