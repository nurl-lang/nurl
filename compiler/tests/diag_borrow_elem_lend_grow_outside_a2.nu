// diag_borrow_elem_lend_grow_outside_a2.nu — formal A2 keeps a view of one
// element past a change inside another only when both are the library's own
// forms: the view `vec_at`, perhaps under `string_data`, `string_bytes` or
// `slice_from_vec` (RhsT.atIdx, RhsT.view), and the change a push, set or
// truncation through `( vec_at vs K )` (StmtT.editB, Eff.dropInAt). A call is a boundary that keeps no index
// (Kind.coarse), so each of these ends the view (AGORA-1037). The first is
// CodeRabbit's on github#2370: `x` is element 1 through `a1`, and a run
// read it freed.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ sel String a String b → String { ^ b }

@ grow String s → v { ( string_push_str s `a long tail that grows the buffer several times over` ) }

@ idv String s → s { ^ ( string_data s ) }

@ two → ( Vec String ) {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `short` ) )
    ( vec_push [String] vs ( string_from `second` ) )
    ^ vs
}

@ through_another_binding → v {
    : ( Vec String ) vs ( two )
    : String a1 ( vec_at [String] vs 1 )
    : s x ( string_data ( sel ( vec_at [String] vs 0 ) a1 ) )
    ( string_push_str ( vec_at [String] vs 1 ) `a long tail that grows the buffer several times over` )
    ( nurl_println x )
}

@ grown_by_a_function → v {
    : ( Vec String ) vs ( two )
    : s d1 ( string_data ( vec_at [String] vs 1 ) )
    ( grow ( vec_at [String] vs 0 ) )
    ( nurl_println d1 )
}

@ viewed_through_a_function → v {
    : ( Vec String ) vs ( two )
    : s d1 ( idv ( vec_at [String] vs 1 ) )
    ( string_push_str ( vec_at [String] vs 0 ) `a long tail that grows the buffer several times over` )
    ( nurl_println d1 )
}

@ main → i {
    ( through_another_binding )
    ( grown_by_a_function )
    ( viewed_through_a_function )
    ^ 0
}
