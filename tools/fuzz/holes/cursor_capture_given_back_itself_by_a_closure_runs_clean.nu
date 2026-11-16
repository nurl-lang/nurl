// cursor_capture_given_back_itself_by_a_closure_runs_clean: a capture given back its own value, `= o ( sid o )`: no copy, its own value by key
// Closed: a capture by pointer is a place outside the closure's frame, as an `inout` parameter is: what a call lends it of anything but its own value is copied in where the call lent, and the capture owns it (gen_assign __cp_call; the engine and tools/ncore read it so; agora #872).
// main 525613db: runs clean (guard).
// map: §7.4 | A2 | runs-clean | - | AGORA-872: a capture given back its own value, `= o ( sid o )`: no copy, its own value by key
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id ? String a → ?String { ^ a }

@ gid [T] T a → T { ^ a }

@ sid String a → String { ^ a }

@ vid ( Vec i ) a → ( Vec i ) { ^ a }

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `first value long enough for the heap` ) )
    : ~ String o ( string_from `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v { = o ( sid o ) }
    ( f )
    ( nurl_println ( string_data o ) )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
