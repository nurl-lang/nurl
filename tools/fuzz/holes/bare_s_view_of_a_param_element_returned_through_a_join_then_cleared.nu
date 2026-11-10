// bare_s_view_of_a_param_element_returned_through_a_join_then_cleared: agora #487 — `^ ? c ( string_data ( vec_at [String] p 0 ) ) ```: the join's arm is a view of p's element, and the caller clears p while holding the result
// main: accepted; heap-use-after-free (the join's arms read p on its edge rows, so the return was read through nothing and lent by no parameter).
// map: §2.10 | A2 | rejected | - | agora #487: `^ ? c ( string_data ( vec_at [String] p 0 ) ) ```: the join's arm is a view of p's element, and the caller clears p while holding the result
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ f ( Vec String ) p b c → s {
    ^ ? c ( string_data ( vec_at [String] p 0 ) ) ``
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer` ) )
    : s v ( f t T )
    ( vec_clear [String] t )
    ( nurl_println v )
    ^ 0
}
