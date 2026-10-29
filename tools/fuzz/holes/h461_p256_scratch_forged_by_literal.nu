// H461: `@ P256Scratch { … }` (and `@ P256Pt { … }`) in safe code: a
// scratch whose registers were empty Vecs, which the point formulas
// write four limbs at a time.
// Closed: P256Scratch and P256Pt are sealed (`raw :`); a literal of one
// is raw memory, which only an `unsafe` function may build.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/std/p256_field.nu`

@ main → i {
    : P256Scratch scr @ P256Scratch { ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) }
    : P256Pt p ( p256ct_identity )
    ( _p256_jdbl_d scr p )
    ^ 0
}
