// result_kept_through_a_panicking_defer_raw_string_and_closure_runs_clean: under recover, a function's result is held while a `;` defer body panics (a literal, an option over a binding, a fresh raw string), and while a local's destructor panics at the exit (a fresh raw string, a `?` join of two, a closure literal, a closure a call made).
// Guard for agora #620: on a return through the defer chain the result is in the function's result slot, journaled until the chain's end has read it (mem_ret_guard_into; a raw string by its address); a fresh raw string and a closure's environment are journaled while the locals are dropped (mem_ret_guard_raw).
// main 70f7232: accepted, LeakSanitizer: each result, its destructor (or free) never run.
// map: §7.2 | A2 | runs-clean | - | agora #620 guard: a result held through a panicking defer, a fresh raw string and a closure result are each released once by the unwind
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ? == . b boom 1 { ( panic `panic in drop` ) } {} } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

@ d1 → Bomb { ; { ( panic `panic in a defer` ) } ^ @ Bomb { ( string_from `result` ) 0 } }

@ d2 → ?String { ; { ( panic `panic in a defer` ) } : String s ( string_from `a value long enough for the heap` ) ^ @ ?String { T s } }

@ d3 → s { ; { ( panic `panic in a defer` ) } ^ ( nurl_str_cat `a raw result string, ` `with a defer` ) }

@ r1 → s { : Bomb loc ( bomb `local` 1 ) ^ ( nurl_str_cat `a raw result string, ` `concatenated on the heap` ) }

@ r2 i k → s { : Bomb loc ( bomb `local` 1 ) ^ ? == k 0 ( nurl_str_cat `join a ` `on the heap` ) ( nurl_str_cat `join b ` `on the heap` ) }

@ c1 → ( @ i ) {
    : Bomb loc ( bomb `local` 1 )
    : String cap ( string_from `a captured string on the heap, long` )
    ^ \ → i { ^ ( string_len cap ) }
}

@ mk → ( @ i ) { : String cap ( string_from `a captured string on the heap, long` ) ^ \ → i { ^ ( string_len cap ) } }

@ c2 → ( @ i ) { : Bomb loc ( bomb `local` 1 ) ^ ( mk ) }

@ main → i {
    : !v PanicInfo a ( recover \ → v { : Bomb g ( d1 ) } )
    : !v PanicInfo b ( recover \ → v { : ?String g ( d2 ) } )
    : !v PanicInfo c ( recover \ → v { : s g ( d3 ) } )
    : !v PanicInfo d ( recover \ → v { : s g ( r1 ) } )
    : !v PanicInfo e ( recover \ → v { : s g ( r2 1 ) } )
    : !v PanicInfo f ( recover \ → v { : ( @ i ) g ( c1 ) } )
    : !v PanicInfo h ( recover \ → v { : ( @ i ) g ( c2 ) } )
    ^ 0
}
