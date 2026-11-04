// bare_view_of_a_loop_element_of_a_local_vec_handed_back: agora #471 — `@ mk1 → s` builds a local `( Vec String )` and hands back `( string_data x )` from inside `~ x t`
// Closed: the view is reached through an element of `t`, which the function releases on its way out (bck_ret_view_check's local-source check; agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of a loop element of the function's own local Vec handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk1 → s {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string local to the function, freed when it returns` ) )
    ~ x t { ^ ( string_data x ) }
    ^ `none`
}

@ main → i {
    : s v ( mk1 )
    ( nurl_println v )
    ^ 0
}
