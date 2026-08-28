// Negative control for the interprocedural escape check (§2.7). A
// helper that only *invokes* its closure parameter does not retain it,
// so it is NOT an escaping parameter — handing it a stack-reference
// closure (one capturing a `: ~`-mutable struct by pointer) is
// perfectly legal: the closure never outlives the frame it points
// into. Must COMPILE, LINK and RUN clean (no false positive).
: Counter { i n i max }

@ run_twice ( @ v ) cb → v {
    ( cb )
    ( cb )
}

@ main → i {
    : ~ Counter c @ Counter { 0 5 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ( run_twice f )
    ( nurl_println_int . c n )
    ^ 0
}
