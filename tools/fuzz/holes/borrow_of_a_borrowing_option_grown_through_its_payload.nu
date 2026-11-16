// borrow_of_a_borrowing_option_grown_through_its_payload: `: o ( id other )  : o2 ( id o )`, grown through `?? o2`
// Closed: a change through a `??` payload binding that may move its buffer ends the views of every other payload binding of the same value - its option's other cursors, an enum's other payloads read in place, and, through a borrow, the payload cursors of the owners it borrows from (bck_borrow_sweep, bck_cursor_follow; agora #874).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-874: `: o ( id other )  : o2 ( id o )`, grown through `?? o2`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { String name }
: | E { EN ES H }

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ grow String s → v { ( string_push_str s `, and a long tail appended to grow the buffer past its room and more` ) }

@ run i k → v {
    : ?String other ( mk `another value long enough for the heap` )
    : ?String o ( id other )
    : ?String o2 ( id o )
    ?? other { T so → {
            : s v ( string_data so )
            ?? o2 { T s → { ( string_push_str s `, and a long tail appended to grow the buffer past its room and more` ) } F → {} }
            ( nurl_println v )
        } F → {} }
}

@ main → i {
    ( run 0 )
    ^ 0
}
