// owner_or_its_vec_element_or_a_fresh_one_with_no_copy_picked_back: `= o ( pk o ( mkn ) k )`, pk handing back o itself, `( vec_get [N] . n kids 0 )` of it, or the fresh N it was handed; N with a `% Drop` of its own
// AGORA-907 (CodeRabbit on github#1938): refused by the walk (#412), the engine and tools/ncore - the owned result still holds o whole and in part (main e7133a6c: the engine and tools/ncore accepted)
// map: §7.6 | A2 | rejected | - | AGORA-907: whole or part per run beside a fresh temporary, no copy
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: N { String s ( Vec N ) kids }

% Drop N { @ drop N x → v { ( nurl_println `drop` ) } }

@ mkn → ?N { ^ @ ?N { T @ N { ( string_from `a fresh node string long enough for the heap` ) ( vec_new [N] ) } } }

@ pk ? N o ? N f i k → ?N {
    ? == k 0 { ^ o } {}
    ? == k 2 { ^ f } {}
    ?? o { T n → { ^ ( vec_get [N] . n kids 0 ) } F → {} }
    ^ @ ?N { F }
}

@ nshow ? N o → v { ?? o { T n → { ( nurl_println ( string_data . n s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ( Vec N ) ks ( vec_new [N] )
    ( vec_push [N] ks @ N { ( string_from `the kid string long enough for the heap buffer` ) ( vec_new [N] ) } )
    : ~ ? N o @ ?N { T @ N { ( string_from `the outer node string long enough for the heap` ) ks } }
    = o ( pk o ( mkn ) k )
    ( nshow o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ( run 2 )
    ^ 0
}
