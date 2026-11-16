// vec_capture_lent_a_closure_local_runs_clean: a captured Vec owner given a lend of a closure-local Vec
// Closed: a capture by pointer is a place outside the closure's frame, as an `inout` parameter is: what a call lends it of anything but its own value is copied in where the call lent, and the capture owns it (gen_assign __cp_call; the engine and tools/ncore read it so; agora #872).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §7.4 | A2 | runs-clean | - | AGORA-872: a captured Vec owner given a lend of a closure-local Vec
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
    : ~ ( Vec i ) o ( vec_new [i] )
    ( vec_push [i] o 1 )
    : ~ ( @ v ) f \ → v {
        : ( Vec i ) loc ( vec_new [i] )
        ( vec_push [i] loc 2 )
        = o ( vid loc )
    }
    ( f )
    ( nurl_println ( nurl_str_int ( vec_at [i] o 0 ) ) )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
