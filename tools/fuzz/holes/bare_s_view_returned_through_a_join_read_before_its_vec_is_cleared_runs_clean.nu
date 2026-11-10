// bare_s_view_returned_through_a_join_read_before_its_vec_is_cleared_runs_clean: agora #487 — a join's view of p's element, read by the caller before it clears p
// Control for agora #487: the lend answer refuses only a use after the clear.
// map: §2.10 | A2 | runs-clean | - | agora #487: a join's view of p's element, read by the caller before it clears p
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f ( Vec String ) p b c → s {
    ^ ? c ( string_data ( vec_at [String] p 0 ) ) ``
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer` ) )
    : s v ( f t T )
    ( nurl_println v )
    ( vec_clear [String] t )
    ^ 0
}
