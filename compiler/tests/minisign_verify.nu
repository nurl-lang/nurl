// minisign_verify.nu — pure-NURL minisign verification against a REAL
// signature produced by minisign 0.11 (`minisign -S`, default prehashed `ED`
// mode). Pins: a valid signature verifies; a tampered message is rejected;
// the wrong public key is rejected.

$ `stdlib/std/minisign.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

// The signed message was exactly "hello nurl signing\n".
@ msg → ( Vec u ) { ^ ( bytes_from_str `hello nurl signing\n` ) }

@ report s label b got b want → b {
    : b ok == got want
    ( nurl_print label ) ( nurl_print ? ok ` ok\n` ` FAIL\n` )
    ^ ok
}

@ main → i {
    : s good_pub `RWReZ7BZS0qAJzqoeFaEsqbNLrUuFLgq1vLoavX51L1di/EBO4kX921b`
    : s good_sig `RUReZ7BZS0qAJ66Y3rmtIP3Umsna5fGt43lbQyNv1QWtQxkKrkqYg7NjthCT6FgcStvfus2KM8iBozAzRdN8asG7zcY3LcVQHQ8=`
    // a different, unrelated minisign public key
    : s wrong_pub `RWQT5WWtjTnEyaYAG5X4HKCRtb7rFT5psjJVGB5Q9kVQBI71F5jfPWUf`

    : ~ b all T

    // 1. valid signature → true
    : ( Vec u ) m1 ( msg )
    = all & all ( report `valid    ` ( minisign_verify_b64 m1 good_pub good_sig ) T )
    ( vec_free [u] m1 )

    // 2. tampered message → false
    : ( Vec u ) m2 ( bytes_from_str `hello nurl signingX` )
    = all & all ( report `tampered ` ( minisign_verify_b64 m2 good_pub good_sig ) F )
    ( vec_free [u] m2 )

    // 3. wrong public key → false
    : ( Vec u ) m3 ( msg )
    = all & all ( report `wrongkey ` ( minisign_verify_b64 m3 wrong_pub good_sig ) F )
    ( vec_free [u] m3 )

    // 4. Payloads produced by the pure-NURL signing helpers verify together.
    : ( Vec u ) seed ( bytes_from_str `0123456789abcdef0123456789abcdef` )
    : ( Vec u ) keyid ( bytes_from_str `nurltest` )
    : ( Vec u ) m4 ( msg )
    : String made_pub ( minisign_pubkey_b64 seed keyid )
    : String made_sig ( minisign_sign_b64 seed keyid m4 )
    = all & all ( report `generated` ( minisign_verify_b64 m4 ( string_data made_pub ) ( string_data made_sig ) ) T )

    // 5. The generated signature is still bound to the exact message.
    : ( Vec u ) changed ( bytes_from_str `hello nurl signing?` )
    = all & all ( report `genchange` ( minisign_verify_b64 changed ( string_data made_pub ) ( string_data made_sig ) ) F )

    // 6. A seed or key id of the wrong size produces no payload.
    : ( Vec u ) short_seed ( bytes_from_str `too short` )
    : ( Vec u ) short_id ( bytes_from_str `short` )
    = all & all ( report `badseed  ` == ( string_len ( minisign_pubkey_b64 short_seed keyid ) ) 0 T )
    = all & all ( report `badkeyid ` == ( string_len ( minisign_sign_b64 seed short_id m4 ) ) 0 T )

    ^ ? all 0 1
}
