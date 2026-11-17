// part_of_owner_vec_element_handed_back_by_a_callee_defined_below_runs_clean: as part_of_owner_vec_element_handed_back_in_a_literal_runs_clean, kid defined below
// AGORA-907: accepted (github#1936: heap-use-after-free in this order)
// map: §7.6 | A2 | runs-clean | - | AGORA-907
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: N { String s ( Vec N ) kids }

@ nshow ? N o → v { ?? o { T n → { ( nurl_println ( string_data . n s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ( Vec N ) ks ( vec_new [N] )
    ( vec_push [N] ks @ N { ( string_from `the kid string long enough for the heap buffer` ) ( vec_new [N] ) } )
    : ~ ? N o @ ?N { T @ N { ( string_from `the outer node string long enough for the heap` ) ks } }
    = o ( kid o )
    ( nshow o )
    ^ 0
}

@ kid ? N o → ?N {
    ?? o { T n → { ? > ( vec_len [N] . n kids ) 0 { ^ @ ?N { T ( vec_at [N] . n kids 0 ) } } {} } F → {} }
    ^ @ ?N { F }
}
