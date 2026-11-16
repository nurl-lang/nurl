// option_struct_payload_field_viewed_while_a_second_match_grows_it: a view of `. a name`, a second match grows `. b name`
// Closed: a change through a `??` payload binding that may move its buffer ends the views of every other payload binding of the same value - its option's other cursors, an enum's other payloads read in place, and, through a borrow, the payload cursors of the owners it borrows from (bck_borrow_sweep, bck_cursor_follow; agora #874).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-874: a view of `. a name`, a second match grows `. b name`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { String name }
: | E { EN ES H }

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ grow String s → v { ( string_push_str s `, and a long tail appended to grow the buffer past its room and more` ) }

@ run i k → v {
    : ~ ? H o @ ?H { T @ H { ( string_from `a struct payload name long enough for the heap` ) } }
    ?? o { T a → {
            : s v ( string_data . a name )
            ?? o { T b → { ( string_push_str . b name `, and a long tail appended to grow the buffer past its room and more` ) } F → {} }
            ( nurl_println v )
        } F → {} }
}

@ main → i {
    ( run 0 )
    ^ 0
}
