// diag_number_into_handle.nu — a number from a call cannot be bound as a
// handle struct.
//
// `: H h ( rcbox_new [T] … )` without the `@ H { # s … }` wrapper compiled:
// the binding was built by reinterpreting the number as the handle's
// pointer field, and it owned nothing it was given (a leak, or a
// use-after-free once the real owner let go — packages/safetensor). NURL has
// no implicit conversions; the literal says what the value is.

: H { s ctl }

@ mk → i { ^ 42 }

@ main → i {
    : H h ( mk )
    ^ 0
}
