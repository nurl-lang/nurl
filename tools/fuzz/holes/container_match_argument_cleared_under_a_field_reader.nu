// container_match_argument_cleared_under_a_field_reader: agora #314 — as container_join_argument_cleared_under_a_field_reader, through a `??`.
// Closed: a `?` / `??` join as a call's argument hands the callee what one of its arms selects: the bindings its identifier arms name (`__last_phi_idents__`) get the rows a call made with them would (`pendjoin`), so a callee that drops, replaces or moves what it is handed ends their borrows and views, as for the join bound first (agora #314).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #314: a `??` as vec_clear's container argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ main → i {
    : ( Vec S ) vs ( vec_new [S] )
    ( vec_push [S] vs @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ( Vec S ) vt ( vec_new [S] )
    : S e ( vec_at [S] vs 0 )
    : String f . e name
    : ?i o ( vec_get [i] ( vec_new [i] ) 0 )
    ( vec_clear [S] ?? o { T _ → vt F → vs } )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
