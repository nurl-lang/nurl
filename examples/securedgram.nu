// examples/securedgram.nu — pubkey-addressed encrypted UDP with roaming
// (TODO §7.4 Phase 0). Two nodes in one process: A handshakes with B,
// sends an encrypted datagram, then ROAMS to a new local port mid-session;
// B authenticates the next datagram, learns A's new endpoint, and its
// reply reaches A at the new port — all keyed only by static pubkey.
//
//   ./nurl.sh examples/securedgram.nu

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/crypto.nu`
$ `stdlib/net/securedgram.nu`

@ veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a ) ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n {
        : i x ?? ( vec_get [u] a k ) { T t → # i t F → -1 }
        : i y ?? ( vec_get [u] b k ) { T t → # i t F → -2 }
        ? != x y { = e F } {}
        = k + k 1
    }
    ^ e
}

@ pt s text → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) ( bytes_extend_str v text ) ^ v }

@ asstr ( Vec u ) v → String { ^ ( bytes_to_str v ) }

@ k32 i b → ( Vec u ) { : ( Vec u ) v ( vec_with_cap [u] 32 ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u b ) = k + k 1 } ^ v }

// Pump B until it returns a transport datagram (handshake packets → None).
@ pump * SecureNode node → ?RecvData {
    : ~ i tries 0
    : ~ b done F
    : ~ ? RecvData out @ ?RecvData { F # RecvData 0 }
    ~ & ! done < tries 20 {
        : ?RecvData r ( securedgram_recv node 2048 )
        ?? r { T d → { = out @ ?RecvData { T d } = done T } F → {} }
        = tries + tries 1
    }
    ^ out
}

@ show s who ? RecvData r ( Vec u ) expect → b {
    ^ ?? r {
        T d → {
            : String got ( asstr . d data )
            ( nurl_print who ) ( nurl_print ` got: ` ) ( nurl_print ( string_data got ) ) ( nurl_print `\n` )
            : b ok ( veq . d data expect )
            ( string_free got )
            ( recvdata_free d )
            ok
        }
        F → { ( nurl_print who ) ( nurl_print ` got nothing\n` ) F }
    }
}

@ main → i {
    : CryptoKeypair akp ?? ( x25519_keygen ) { T k → k F _ → @ CryptoKeypair { ( vec_new [u] ) ( vec_new [u] ) } }
    : CryptoKeypair bkp ?? ( x25519_keygen ) { T k → k F _ → @ CryptoKeypair { ( vec_new [u] ) ( vec_new [u] ) } }
    : ( Vec u ) psk ( k32 77 )

    : !*SecureNode NetErr ar ( securedgram_open `127.0.0.1` 9810 akp psk )
    : !*SecureNode NetErr br ( securedgram_open `127.0.0.1` 9811 bkp psk )
    ?? ar { T an → {
            ?? br { T bn → {
                    ( securedgram_add_peer an . bkp pk `127.0.0.1` 9811 )
                    ( securedgram_add_peer bn . akp pk `127.0.0.1` 9810 )

                    // handshake: A → msg1, B → msg2, A establishes
                    : !v NetErr _c ( securedgram_connect an . bkp pk )
                    : ?RecvData _h1 ( securedgram_recv bn 2048 )  // B handles init, sends msg2
                    : ?RecvData _h2 ( securedgram_recv an 2048 )  // A handles resp

                    // A → B encrypted datagram
                    : ( Vec u ) m1 ( pt `hello over noise` )
                    : !v NetErr _s1 ( securedgram_send an . bkp pk m1 )
                    ( nurl_print `direct: ` ) ( nurl_print ? ( show `B` ( pump bn ) m1 ) `OK\n` `FAIL\n` )

                    // ROAM: A rebinds to a new local port mid-session, then sends again
                    : !v NetErr _rb ( securedgram_rebind an `127.0.0.1` 9820 )
                    : ( Vec u ) m2 ( pt `after roaming` )
                    : !v NetErr _s2 ( securedgram_send an . bkp pk m2 )
                    ( nurl_print `roamed:  ` ) ( nurl_print ? ( show `B` ( pump bn ) m2 ) `OK\n` `FAIL\n` )

                    // B replies — must reach A at its NEW port (proves B learned the new endpoint)
                    : ( Vec u ) rep ( pt `reply to new endpoint` )
                    : !v NetErr _s3 ( securedgram_send bn . akp pk rep )
                    ( nurl_print `reply:   ` ) ( nurl_print ? ( show `A` ( pump an ) rep ) `OK\n` `FAIL\n` )

                    ( vec_free [u] m1 ) ( vec_free [u] m2 ) ( vec_free [u] rep )
                    ( securedgram_close bn )
                } F _ → ( nurl_print `B bind failed\n` ) }
            ( securedgram_close an )
        } F _ → ( nurl_print `A bind failed\n` ) }

    ( vec_free [u] psk )
    ( vec_free [u] . akp sk ) ( vec_free [u] . akp pk )
    ( vec_free [u] . bkp sk ) ( vec_free [u] . bkp pk )
    ^ 0
}
