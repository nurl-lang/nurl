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

    ^ ? all 0 1
}
