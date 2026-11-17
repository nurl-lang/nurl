// part_of_owner_vec_element_handed_back_in_a_literal_runs_clean: `= o ( kid o )`, kid handing back `@ ?N { T ( vec_at [N] . n kids 0 ) }` of o's own kids
// AGORA-906: accepted - copied in on the runs kid lends (main 81530211: heap-use-after-free)
// map: §7.6 | A2 | runs-clean | - | AGORA-906: a Vec element of the owner, handed back in a literal
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: N { String s ( Vec N ) kids }

@ kid ? N o → ?N {
    ?? o { T n → { ? > ( vec_len [N] . n kids ) 0 { ^ @ ?N { T ( vec_at [N] . n kids 0 ) } } {} } F → {} }
    ^ @ ?N { F }
}

@ nshow ? N o → v { ?? o { T n → { ( nurl_println ( string_data . n s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ( Vec N ) ks ( vec_new [N] )
    ( vec_push [N] ks @ N { ( string_from `the kid string long enough for the heap buffer` ) ( vec_new [N] ) } )
    : ~ ? N o @ ?N { T @ N { ( string_from `the outer node string long enough for the heap` ) ks } }
    = o ( kid o )
    ( nshow o )
    ^ 0
}
