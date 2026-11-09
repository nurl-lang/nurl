// forwarder_to_a_fresh_returning_helper_below_runs_clean: agora #349 — `mk` (above) forwards to `helper` (below) that returns a fresh String, grown past a view of `vs[0]`
// The shape the fix must keep: a callee not compiled yet no longer stands for every argument (agora #349).
// main 21a0fb5: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #349: a forwarder to a fresh-returning helper defined below
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ mk ( Vec String ) vs → String {
    ^ ( helper vs )
}

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `abc` ) )
    : s d ( string_data ( vec_at [String] vs 0 ) )
    ( string_push_str ( mk vs ) `0123456789012345678901234567890123456789012345678901234567890123456789` )
    ( puts d )
    ^ 0
}

@ helper ( Vec String ) vs → String {
    ^ ( string_from `a fresh string, not one of vs` )
}
