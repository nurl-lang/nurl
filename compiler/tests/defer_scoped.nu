// defer_scoped.nu — defer registration is reachability-armed: the body
// runs at function exit iff its `;` statement executed, at most once
// per site, LIFO across sites. A defer inside an untaken arm must NOT
// run (its armed flag stays null — emit_hoisted null-inits the i8*
// flag alloca at entry); a loop-body defer runs once, not per
// iteration. Previously a scoped defer emitted a `br` to a fn_cleanup
// label that was never emitted — invalid IR, a clang error.

$ `stdlib/core/string.nu`

@ taken b c → v {
    ? c { ; { ( nurl_print `taken-arm defer\n` ) } } {}
    ( nurl_print `body done\n` )
}

@ loop_defer → v {
    : ~ i k 0
    ~ < k 3 {
        ; { ( nurl_print `loop defer once\n` ) }
        = k + k 1
    }
    ( nurl_print `loop done k=` ) ( nurl_print ( nurl_str_int k ) ) ( nurl_print `\n` )
}

@ lifo → v {
    ; { ( nurl_print `first\n` ) }
    ; { ( nurl_print `second\n` ) }
    ( nurl_print `lifo body\n` )
}

@ main → i {
    ( taken T )
    ( taken F )
    ( loop_defer )
    ( lifo )
    ^ 0
}
