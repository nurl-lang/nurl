// closure_local_picked_into_a_captured_string_owner_runs_clean: a closure local picked into a captured String owner, `= o ( spick o other k )`
// Closed: a capture by pointer is a place outside the closure's frame, as an `inout` parameter is: what a call lends it of anything but its own value is copied in where the call lent, and the capture owns it (gen_assign __cp_call; the engine and tools/ncore read it so; agora #872).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §7.4 | A2 | runs-clean | - | AGORA-872: a closure local picked into a captured String owner, `= o ( spick o other k )`
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ spick String a String b i k → String { ? == k 0 { ^ a } { ^ b } }

@ run i k → v {
    : ~ String o ( string_from `a value long enough for the heap here` )
    : ~ ( @ v ) f \ → v {
        : String other ( string_from `a closure local value long enough for heap` )
        = o ( spick o other k )
    }
    ( f )
    ( nurl_println ( string_data o ) )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
