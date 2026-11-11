// element_of_a_slice_built_over_a_vec_parameter_read_before_the_vec_is_cleared_runs_clean: agora #594 — the caller reads what the function lent before it clears the Vec
// Control for agora #594: the lend refuses only a use after the clear.
// map: §2.10 | A2 | runs-clean | - | agora #594: the caller reads what the function lent before it clears the Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mkvs → ( Vec String ) {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `hello world slice element number zero` ) )
    ^ vs
}

@ first ( Vec String ) vs → String {
    : ( Slice String ) sl ( slice_from_vec [String] vs )
    ^ ( slice_at [String] sl 0 )
}

@ main → i {
    : ( Vec String ) vs ( mkvs )
    : String r ( first vs )
    ( nurl_println ( string_data r ) )
    ( vec_clear [String] vs )
    ^ 0
}
