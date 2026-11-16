// enum_payload_field_viewed_while_a_second_match_grows_it: a program enum: a view of one arm's payload field, a second match of it grows the field
// Closed: a change through a `??` payload binding that may move its buffer ends the views of every other payload binding of the same value - its option's other cursors, an enum's other payloads read in place, and, through a borrow, the payload cursors of the owners it borrows from (bck_borrow_sweep, bck_cursor_follow; agora #874).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-874: a program enum: a view of one arm's payload field, a second match of it grows the field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { String name }
: | E { EN ES H }

@ id ? String a → ?String { ^ a }
@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }
@ grow String s → v { ( string_push_str s `, and a long tail appended to grow the buffer past its room and more` ) }

@ run i k → v {
    : ~ E e @ E { ES @ H { ( string_from `an enum payload value long enough for the heap` ) } }
    ?? e { ES a → {
            : s v ( string_data . a name )
            ?? e { ES b → { ( string_push_str . b name `, and a long tail appended to grow the buffer past its room and more` ) } EN → {} }
            ( nurl_println v )
        } EN → {} }
}

@ main → i {
    ( run 0 )
    ^ 0
}
