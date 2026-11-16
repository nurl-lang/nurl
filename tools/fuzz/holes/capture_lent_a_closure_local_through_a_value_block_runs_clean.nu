// capture_lent_a_closure_local_through_a_value_block_runs_clean: `= o { ( id other ) }`, the block-local copy now made by the capture rule
// Closed: a capture by pointer is a place outside the closure's frame, as an `inout` parameter is: what a call lends it of anything but its own value is copied in where the call lent, and the capture owns it (gen_assign __cp_call; the engine and tools/ncore read it so; agora #872).
// main 525613db: runs clean (guard).
// map: §7.4 | A2 | runs-clean | - | AGORA-872: `= o { ( id other ) }`, the block-local copy now made by the capture rule
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
    : ~ ( @ v ) f \ → v {
        : ?String other ( mk `a closure local value long enough for heap` )
        = o { ( id other ) }
    }
    ( f )
    ( show o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
