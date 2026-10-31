// p256_field_op_given_short_limbs: p256_field.nu's field operations (`p256ct_mul`, `p256ct_add`,
// `p256ct_inv`, the `_p256_*_d` workers, the table and point helpers, …)
// were callable by any program and read and wrote four limbs of each
// operand through `vec_data` unchecked: empty operands read unallocated
// memory. (`_mag4` / `_magn` also handed safe code uninitialised limbs.)
// Closed: every helper that requires four-limb operands (or a sized
// table, or uninitialised limbs to be written first) is `raw`; a program
// calls the byte-level surface (p256ct_scalarmult*, std/ecdsa_p256).
// v0.80.0: accepted; AddressSanitizer reported SEGV.
// map: §3.3d | B | rejected | h460 | p256_field.nu's field operations (`p256ct_mul`, `p256ct_add`, `p256ct_inv`, the `_p256_*_d` workers, the table and point helpers, …) were callable by any program and read and wrote four limbs of…
$ `stdlib/core/vec.nu`
$ `stdlib/std/p256_field.nu`

@ main → i {
    : ( Vec i ) a ( vec_new [i] )
    : ( Vec i ) b ( vec_new [i] )
    : ( Vec i ) r ( p256ct_mul a b )
    ( nurl_println_int ( vec_len [i] r ) )
    ^ 0
}
