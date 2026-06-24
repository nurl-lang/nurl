// chacha20poly1305_vectors.nu — RFC 8439 known-answer tests for the
// pure-NURL ChaCha20, Poly1305, and ChaCha20-Poly1305 AEAD.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/chacha20poly1305.nu`

@ hx s raw → ( Vec u ) {
    ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) }
}

@ check s label ( Vec u ) got s want → i {
    : String gh ( bytes_to_hex got )
    ? ( nurl_str_eq ( string_data gh ) want ) {
        ( nurl_print label ) ( nurl_print `: PASS\n` )
        ( string_free gh )
        ^ 0
    } {
        ( nurl_print label ) ( nurl_print `: FAIL got ` )
        ( nurl_print ( string_data gh ) ) ( nurl_print ` want ` )
        ( nurl_print want ) ( nurl_print `\n` )
        ( string_free gh )
        ^ 1
    }
}

@ main → i {
    : ~ i fails 0

    : ( Vec u ) key1 ( hx `000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f` )

    // RFC 8439 §2.4.2 — ChaCha20 encryption, counter starts at 1.
    : ( Vec u ) n24 ( hx `000000000000004a00000000` )
    : ( Vec u ) pt ( hx `4c616469657320616e642047656e746c656d656e206f662074686520636c617373206f66202739393a204966204920636f756c64206f6666657220796f75206f6e6c79206f6e652074697020666f7220746865206675747572652c2073756e73637265656e20776f756c642062652069742e` )
    : ( Vec u ) ct ( chacha20_xor key1 1 n24 pt )
    = fails + fails ( check `chacha20_encrypt` ct `6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0bf91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d807ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab77937365af90bbf74a35be6b40b8eedf2785e42874d` )
    // Round-trip back to plaintext.
    : ( Vec u ) dt ( chacha20_xor key1 1 n24 ct )
    = fails + fails ( check `chacha20_decrypt` dt `4c616469657320616e642047656e746c656d656e206f662074686520636c617373206f66202739393a204966204920636f756c64206f6666657220796f75206f6e6c79206f6e652074697020666f7220746865206675747572652c2073756e73637265656e20776f756c642062652069742e` )

    // RFC 8439 §2.5.2 — Poly1305.
    : ( Vec u ) otk ( hx `85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b` )
    : ( Vec u ) pmsg ( hx `43727970746f6772617068696320466f72756d2052657365617263682047726f7570` )
    : ( Vec u ) tag ( poly1305_mac otk pmsg )
    = fails + fails ( check `poly1305` tag `a8061dc1305136c6c22b8baf0c0127a9` )

    // RFC 8439 §2.8.2 — AEAD encryption (ciphertext ‖ tag).
    : ( Vec u ) akey ( hx `808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f` )
    : ( Vec u ) anonce ( hx `070000004041424344454647` )
    : ( Vec u ) aad ( hx `50515253c0c1c2c3c4c5c6c7` )
    : ( Vec u ) sealed ( aead_encrypt akey anonce aad pt )
    = fails + fails ( check `aead_seal` sealed `d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd0600691` )

    // AEAD round-trip: decrypt the sealed blob back to the plaintext.
    ?? ( aead_decrypt akey anonce aad sealed ) {
        T opened → {
            = fails + fails ( check `aead_open` opened `4c616469657320616e642047656e746c656d656e206f662074686520636c617373206f66202739393a204966204920636f756c64206f6666657220796f75206f6e6c79206f6e652074697020666f7220746865206675747572652c2073756e73637265656e20776f756c642062652069742e` )
            ( vec_free [u] opened )
        }
        F _ → { ( nurl_print `aead_open: FAIL (rejected valid tag)\n` ) = fails + fails 1 }
    }

    // AEAD tamper detection: flip one ciphertext byte → must reject.
    ( vec_set [u] sealed 0 # u ^^ 255 ?? ( vec_get [u] sealed 0 ) { T x → # i x F _ → 0 } )
    ?? ( aead_decrypt akey anonce aad sealed ) {
        T bad → { ( nurl_print `aead_tamper: FAIL (accepted forgery)\n` ) = fails + fails 1 ( vec_free [u] bad ) }
        F _ → { ( nurl_print `aead_tamper: PASS\n` ) }
    }

    ? == fails 0 { ( nurl_print `chacha20poly1305: all vectors PASS\n` ) } { ( nurl_print `chacha20poly1305: FAILURES\n` ) }
    ^ fails
}
