// should_fail_inout_immut.nu — BORROW.md Phase 4: an `inout`
// argument must be a mutable (`: ~`) binding. The callee mutates it
// in place, so passing an immutable binding (or a temporary) would
// silently discard the mutation. The compiler rejects it at the call
// site. Expect COMPILE FAIL.

: Counter { i n  i max }

@ bump inout Counter c → v {
    = . c n + . c n 1
}

@ main → i {
    // `c` is immutable (no `: ~`) — it cannot be passed as `inout`.
    : Counter c @ Counter { 0 10 }
    ( bump c )
    ^ 0
}
