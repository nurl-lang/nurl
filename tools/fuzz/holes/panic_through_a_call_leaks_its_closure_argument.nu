// panic_through_a_call_leaks_its_closure_argument: a closure literal handed to a call that panics: the call site drops the closure's env after the call returns, and a panic unwound past that drop, so the env and what it captured leaked.
// Closed: an argument's closure temporary is journaled while the call runs (mem_journal_push_cloenv, agora #131).
// v0.79.0: accepted; LSan reported a direct leak (the env).
// map: §7.2 | A2 | runs-clean | h375 | a closure literal handed to a call that panics: the env, dropped after the call, leaked; an argument's closure temporary is journaled while the call runs
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

@ run ( @ v ) f → v { ( nurl_panic `boom` ) }

@ case → v {
    : String a ( string_from `a string long enough to own a heap buffer here` )
    ( run \ → v { ( nurl_println ( string_data a ) ) } )
}

@ main → i {
    : !v PanicInfo r ( recover \ → v { ( case ) } )
    ( nurl_println `recovered` )
    ^ 0
}
