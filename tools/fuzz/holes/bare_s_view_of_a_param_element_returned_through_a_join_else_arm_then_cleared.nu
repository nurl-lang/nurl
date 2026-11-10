// bare_s_view_of_a_param_element_returned_through_a_join_else_arm_then_cleared: agora #487 — the same with the view in the join's else arm
// main: accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #487: the same with the view in the join's else arm
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ f ( Vec String ) p b c → s {
    ^ ? c `` ( string_data ( vec_at [String] p 0 ) )
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer` ) )
    : s v ( f t F )
    ( vec_clear [String] t )
    ( nurl_println v )
    ^ 0
}
