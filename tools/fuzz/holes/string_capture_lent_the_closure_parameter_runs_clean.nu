// string_capture_lent_the_closure_parameter_runs_clean: a String capture given `( sid p )`, p the closure's parameter
// Closed: a capture by pointer is a place outside the closure's frame, as an `inout` parameter is: what a call lends it of anything but its own value is copied in where the call lent, and the capture owns it (gen_assign __cp_call; the engine and tools/ncore read it so; agora #872).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §7.4 | A2 | runs-clean | - | AGORA-872: a String capture given `( sid p )`, p the closure's parameter
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
    : ~ String o ( string_from `a value long enough for the heap here` )
    : ~ ( @ v String ) f \ String p → v { = o ( sid p ) }
    ( f ( string_from `a closure argument value long enough for heap` ) )
    ( nurl_println ( string_data o ) )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
