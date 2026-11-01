// container_join_argument_cleared_after_its_reads: agora #314 — as container_join_argument_cleared_under_a_field_reader, everything read out of the element copied before the clear (the shape the fix must keep).
// Closed: a `?` / `??` join as a call's argument hands the callee what one of its arms selects: the bindings its identifier arms name (`__last_phi_idents__`) get the rows a call made with them would (`pendjoin`), so a callee that drops, replaces or moves what it is handed ends their borrows and views, as for the join bound first (agora #314).
// main: accepted; ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #314: a `?` as vec_clear's container argument, nothing held across
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ main → i {
    : ( Vec S ) vs ( vec_new [S] )
    ( vec_push [S] vs @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ( Vec S ) vt ( vec_new [S] )
    : S e ( vec_at [S] vs 0 )
    : i n0 ( string_len . e name )
    : i c ( vec_len [S] vs )
    ( vec_clear [S] ? == c 1 vs vt )
    ( nurl_println_int n0 )
    ( nurl_println_int ( vec_len [S] vs ) )
    ^ 0
}
