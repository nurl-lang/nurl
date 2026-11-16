// closure_parameter_lent_to_a_captured_owner_runs_clean: the closure's own parameter lent to a captured owner, `= o ( id other )`
// Closed: a capture by pointer is a place outside the closure's frame, as an `inout` parameter is: what a call lends it of anything but its own value is copied in where the call lent, and the capture owns it (gen_assign __cp_call; the engine and tools/ncore read it so; agora #872).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §7.4 | A2 | runs-clean | - | AGORA-872: the closure's own parameter lent to a captured owner, `= o ( id other )`
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ( @ v ? String ) f \ ? String other → v {
        = o ( id other )
    }
    ( f ( mk `a closure argument value long enough for heap` ) )
    ( show o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
