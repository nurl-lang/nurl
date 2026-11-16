// capture_given_a_fresh_value_by_a_closure_runs_clean: a capture given a fresh value
// Closed: a capture by pointer is a place outside the closure's frame, as an `inout` parameter is: what a call lends it of anything but its own value is copied in where the call lent, and the capture owns it (gen_assign __cp_call; the engine and tools/ncore read it so; agora #872).
// main 525613db: runs clean (guard).
// map: §7.4 | A2 | runs-clean | - | AGORA-872: a capture given a fresh value
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
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v { = o ( mk `fresh value long enough for the heap here` ) }
    ( f )
    ( show o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
