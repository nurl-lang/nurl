// option_payload_viewed_while_a_loop_of_second_matches_grows_it: the second match in a loop
// Closed: a change through a `??` payload binding that may move its buffer ends the views of every other payload binding of the same value - its option's other cursors, an enum's other payloads read in place, and, through a borrow, the payload cursors of the owners it borrows from (bck_borrow_sweep, bck_cursor_follow; agora #874).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-874: the second match in a loop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { String name }
: | E { EN ES H }

@ id ? String a → ?String { ^ a }
@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }
@ grow String s → v { ( string_push_str s `, and a long tail appended to grow the buffer past its room and more` ) }

@ run i k → v {
    : ~ ? String o ( mk `a value long enough for the heap here` )
    ?? o { T a → {
            : s v ( string_data a )
            : ~ i j 0
            ~ < j 2 { ?? o { T b → { ( string_push_str b `, and a long tail appended to grow the buffer past its room and more` ) } F → {} }  = j + j 1 }
            ( nurl_println v )
        } F → {} }
}

@ main → i {
    ( run 0 )
    ^ 0
}
