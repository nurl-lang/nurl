// element_of_a_slice_built_over_a_vec_parameter_copied_by_the_caller_runs_clean: agora #594 — the caller copies what the function lent (`mem_dup`) before it clears the Vec
// Control for agora #594: a copy of the lent element is the caller's own.
// map: §2.10 | A2 | runs-clean | - | agora #594: the caller copies what the function lent (`mem_dup`) before it clears the Vec
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
    : String r ( mem_dup ( first vs ) )
    ( vec_clear [String] vs )
    ( nurl_println ( string_data r ) )
    ^ 0
}
