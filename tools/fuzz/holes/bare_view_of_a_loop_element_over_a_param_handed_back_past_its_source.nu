// bare_view_of_a_loop_element_over_a_param_handed_back_past_its_source: agora #471 — `@ first ( Vec String ) p → s { ~ x p { ^ ( string_data x ) } ^ `none` }`; the caller clears its Vec, then reads the view
// Closed: a bare `s` handed back answers `^k` for what it views only through a parameter's elements (bck_ret_view_check, `__src_indirect` of its sources): here the own storage of a loop element over the parameter (`fe_`), which codegen's lend answer does not see (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of a parameter's loop element handed back, read after the caller cleared its argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first ( Vec String ) p → s {
    ~ x p { ^ ( string_data x ) }
    ^ `none`
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the caller clears before reading its view` ) )
    : s v ( first t )
    ( vec_clear [String] t )
    ( nurl_println v )
    ^ 0
}
