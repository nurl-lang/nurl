// fresh_returning_helper_below_grown_inline_runs_clean: agora #349 — a fresh-returning helper defined below, written inline as the grown argument, past a view of `vs[0]`
// The shape the fix must keep: a callee not compiled yet no longer stands for every argument (agora #349).
// main 21a0fb5: refused (a false positive).
// map: §2.10 | A2 | runs-clean | - | agora #349: a fresh-returning helper defined below, grown inline
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `abc` ) )
    : s d ( string_data ( vec_at [String] vs 0 ) )
    ( string_push_str ( helper vs ) `0123456789012345678901234567890123456789012345678901234567890123456789` )
    ( puts d )
    ^ 0
}

@ helper ( Vec String ) vs → String {
    ^ ( string_from `a fresh string, not one of vs` )
}
