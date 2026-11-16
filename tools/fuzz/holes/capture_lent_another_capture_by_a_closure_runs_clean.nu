// capture_lent_another_capture_by_a_closure_runs_clean: a closure gives capture o a lend of capture other; other replaced after the call, o read
// Closed: a capture by pointer is a place outside the closure's frame, as an `inout` parameter is: what a call lends it of anything but its own value is copied in where the call lent, and the capture owns it (gen_assign __cp_call; the engine and tools/ncore read it so; agora #872).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §7.4 | A2 | runs-clean | - | AGORA-872: a closure gives capture o a lend of capture other; other replaced after the call, o read
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }
@ gid [T] T a → T { ^ a }
@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }
@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ( @ v ) f \ → v { = o ( id other ) }
    ( f )
    = other ( mk `a replacement value long enough for the heap` )
    ( show o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
