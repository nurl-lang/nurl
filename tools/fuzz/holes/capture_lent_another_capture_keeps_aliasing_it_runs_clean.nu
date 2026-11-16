// capture_lent_another_capture_keeps_aliasing_it_runs_clean: `= o ( vid other )`, other a capture: o still aliases other, as outside a closure (prints 2)
// Closed: a capture by pointer given a lend of what dies with the closure (a local or a parameter of it) is given a copy it owns, as an `inout` parameter is (gen_assign; agora #872).
// main 525613db: runs clean (guard: no copy of another capture).
// map: §7.4 | A2 | runs-clean | - | AGORA-872: `= o ( vid other )`, other a capture: o still aliases other, as outside a closure (prints 2)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id ? String a → ?String { ^ a }

@ gid [T] T a → T { ^ a }

@ sid String a → String { ^ a }

@ vid ( Vec i ) a → ( Vec i ) { ^ a }

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ( Vec i ) other ( vec_new [i] )
    ( vec_push [i] other 1 )
    : ~ ( Vec i ) o ( vec_new [i] )
    : ~ ( @ v ) f \ → v { = o ( vid other ) }
    ( f )
    ( vec_push [i] other 2 )
    ( nurl_println_int ( vec_len [i] o ) )
    ( nurl_println_int ( vec_len [i] other ) )
    ^ 0
}
