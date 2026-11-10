### Fixed

- **A value block's own local, handed out to a binding that outlives it, is moved** (Agora #574). `= w { : ~ ( Vec i ) u ( vec_new [i] ) … u }` in a loop body with `w` outside the loop, or `= v { … }` of the same kind with `v` an `inout` parameter, left `w` or `v` borrowing `u`, which was then dropped at the end of its scope; reading `w` after the loop, or the caller's argument, read freed memory (a heap-use-after-free). An assignment's value block whose tail is a binding is now read as that binding, as `= w u` is, so the value moves.
