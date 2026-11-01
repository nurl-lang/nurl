// container_join_bound_then_cleared_under_a_field_reader: agora #314 — the control: the same `?` bound first, then cleared (refused before).
// Closed: a `?` / `??` join as a call's argument hands the callee what one of its arms selects: the bindings its identifier arms name (`__last_phi_idents__`) get the rows a call made with them would (`pendjoin`), so a callee that drops, replaces or moves what it is handed ends their borrows and views, as for the join bound first (agora #314).
// main: rejected.
// map: §2.10 | A2 | rejected | - | agora #314: a `?` bound, then cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ main → i {
    : ( Vec S ) vs ( vec_new [S] )
    ( vec_push [S] vs @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ( Vec S ) vt ( vec_new [S] )
    : S e ( vec_at [S] vs 0 )
    : String f . e name
    : i c ( vec_len [S] vs )
    : ( Vec S ) j ? == c 1 vs vt
    ( vec_clear [S] j )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
