// bare_view_of_a_loop_element_over_a_param_handed_back_by_a_callee_below: agora #471 — the same with `first` defined below its caller, whose walk would otherwise run before `first`'s answer exists
// Closed: a caller of a bare-`s` callee not walked yet waits for its answer (`rvcallees`, __rv_bare_view), as a caller of a holder-returning one does (agora #471, #422).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of a parameter's loop element handed back by a callee defined below its caller
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the caller clears before reading its view` ) )
    : s v ( first t )
    ( vec_clear [String] t )
    ( nurl_println v )
    ^ 0
}

@ first ( Vec String ) p → s {
    ~ x p { ^ ( string_data x ) }
    ^ `none`
}
