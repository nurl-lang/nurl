// slice_owned_on_some_runs_unwound_by_a_panic: a panic under `recover` past slices owned on some runs (from a function handing back its own slice or its parameter) and a mutable owned slice given the caller's slice. The unwind journal held each binding's buffer whether it owned it or not, and released the caller's.
// Closed: a binding with an owner flag journals its buffer only when the flag says it owns it (agora #540); `= e a` over a longer-lived owner makes e a view.
// main ad960922: AddressSanitizer: heap-use-after-free reading `a` after the recover.
// map: §7.6 | A2 | runs-clean | - | agora #540: the unwind journal released slices their bindings did not own
$ `stdlib/std/panic.nu`

@ pick b c [i p → [i {
    ? c { ^ p } {}
    ^ [i | 1 2]
}

@ work [i a → v {
    : [i q ( pick F a )
    : [i r ( pick T a )
    : ~ [i e [i | 4]
    = e a
    ( panic `boom` )
}

@ guard ( @ v ) w → v {
    ?? ( recover w ) {
        T _ → { ( nurl_exit 2 ) }
        F info → { ( panic_info_free info ) }
    }
}

@ main → i {
    : [i a [i | 5 6]
    ( guard \ → v { ( work a ) } )
    ~ x a { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
