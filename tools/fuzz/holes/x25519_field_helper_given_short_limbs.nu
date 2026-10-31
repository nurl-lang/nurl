// x25519_field_helper_given_short_limbs: x25519.nu's five-limb field helpers (`_A`, `_M`, `_pack25519`, …)
// carry one underscore, so any program could call them, and each indexes
// its operands' five limbs through `vec_data` unchecked: empty operands
// read and wrote unallocated memory.
// Closed: the helpers that require five limbs (or 32 bytes) are `raw`;
// only an `unsafe` caller, vouching for the sizes, may call them.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
// map: §3.3d | B | rejected | h436 | x25519.nu's five-limb field helpers (`_A`, `_M`, `_pack25519`, …) carry one underscore, so any program could call them, and each indexes its operands' five limbs through `vec_data` unchecked:…
$ `stdlib/core/vec.nu`
$ `stdlib/std/x25519.nu`

@ main → i {
    : ( Vec i ) a ( vec_new [i] )
    : ( Vec i ) b ( vec_new [i] )
    : ( Vec i ) o ( vec_new [i] )
    ( _A o a b )
    : ( Vec u ) r ( _pack25519 a )
    ( nurl_println ( nurl_str_int ( vec_len [u] r ) ) )
    ^ 0
}
