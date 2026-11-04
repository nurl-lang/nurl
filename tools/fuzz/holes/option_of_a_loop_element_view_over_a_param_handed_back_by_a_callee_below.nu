// option_of_a_loop_element_view_over_a_param_handed_back_by_a_callee_below: agora #471 — `@ mk ( Vec String ) p → ?s`, defined below its caller, hands back `@ ?s { T ( string_data x ) }` from `~ x p`; the caller clears its Vec, then reads the payload
// Closed: a caller waits for a callee not walked yet whose result is a struct, an option or an enum of views (class 2), as for a bare `s` (__rv_waits; agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: an option of a loop element view over a parameter, handed back by a callee below
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the caller clears before reading its view` ) )
    : ?s o ( mk t )
    ( vec_clear [String] t )
    ?? o { T w → ( nurl_println w ) F → {} }
    ^ 0
}

@ mk ( Vec String ) p → ?s {
    ~ x p { ^ @ ?s { T ( string_data x ) } }
    ^ @ ?s { F }
}
