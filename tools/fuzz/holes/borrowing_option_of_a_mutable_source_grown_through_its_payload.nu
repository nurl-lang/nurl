// borrowing_option_of_a_mutable_source_grown_through_its_payload: the same with other a `: ~` binding
// Closed: a change through a `??` payload binding that may move its buffer ends the views of every other payload binding of the same value - its option's other cursors, an enum's other payloads read in place, and, through a borrow, the payload cursors of the owners it borrows from (bck_borrow_sweep, bck_cursor_follow; agora #874).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-874: the same with other a `: ~` binding
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    = o ( id other )
    ?? other { T so → {
            : s view ( string_data so )
            ?? o { T s → { ( string_push_str s `, and a long tail appended to grow the buffer past its room and more` ) } F → {} }
            ( nurl_println view )
        } F → {} }
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
