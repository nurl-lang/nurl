// should_fail_inout_field_immut.nu — an `inout` field target
// `. obj field` requires `obj` to be a mutable (`: ~`)
// binding, since the callee mutates that field in place. A field
// target naming an immutable struct binding is rejected. Expect
// COMPILE FAIL.

: Counter { i n i max }

@ add100 inout i x → v {
    = x + x 100
}

@ main → i {
    : Counter c @ Counter { 5 10 }  // immutable — no ': ~'
    ( add100 . c n )  // field target on immutable c — rejected
    ^ 0
}
