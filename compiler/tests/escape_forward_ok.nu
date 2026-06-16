// Negative control for the deferred forward-escape check (§3). A helper
// defined AFTER its caller that only *invokes* its closure parameter
// does not escape it, so the parked check resolves to nothing — passing
// it a stack-reference closure stays legal. Must COMPILE, LINK and RUN
// clean: the deferred replay must not turn a forward call into a false
// positive just because the callee was unknown at the call site.
: Counter { i n i max }

@ caller → i {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ( run_twice f )
    ^ . c n
}

@ run_twice ( @ v ) cb → v {
    ( cb )
    ( cb )
}

@ main → i {
    ( nurl_print_int ( caller ) )
    ^ 0
}
