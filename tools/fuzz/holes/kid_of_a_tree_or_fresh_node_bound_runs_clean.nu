// kid_of_a_tree_or_fresh_node_bound_runs_clean: agora #739 — `@ kid Node n b c → Node { ? c { ^ ( vec_at [Node] . n kids 0 ) } {} ^ ( mkn 0 ) }` bound: the fresh Node leaked
// Closed: as for agora #625 — a lend of a parameter's field or part beside a fresh value answers per call (__hown_mixed); a temporary of a type with a `% Drop` of its own handed back whole on some runs is dropped on the runs the call's answer says its result is its own (agora #739, #457).
// main b64e33a1: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #739: `@ kid Node n b c → Node { ? c { ^ ( vec_at [Node] . n kids 0 ) } {} ^ ( mkn 0 ) }` bound: the fresh Node leaked
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Node { ( Vec Node ) kids ( Vec String ) ss }

@ mkn i d → Node {
    : ( Vec String ) ss ( vec_new [String] )
    ( vec_push [String] ss ( string_from `an element string long enough for the heap` ) )
    : ( Vec Node ) ks ( vec_new [Node] )
    ? > d 0 { ( vec_push [Node] ks ( mkn - d 1 ) ) } {}
    ^ @ Node { ks ss }
}

@ kid Node n b c → Node { ? c { ^ ( vec_at [Node] . n kids 0 ) } {} ^ ( mkn 0 ) }

@ run b c → i {
    : Node e0 ( mkn 1 )
    : Node e1 ( kid e0 c )
    ( nurl_println_int ( vec_len [String] . e1 ss ) )
    ^ 0
}

@ main → i {
    ( run F )
    ( run T )
    ^ 0
}
