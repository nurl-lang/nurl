// option_vec_payload_sliced_while_a_second_match_pushes_to_it: a slice of a Vec payload, a second match pushes onto it
// Closed: a change through a `??` payload binding that may move its buffer ends the views of every other payload binding of the same value - its option's other cursors, an enum's other payloads read in place, and, through a borrow, the payload cursors of the owners it borrows from (bck_borrow_sweep, bck_cursor_follow; agora #874).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-874: a slice of a Vec payload, a second match pushes onto it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { String name }
: | E { EN ES H }

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ grow String s → v { ( string_push_str s `, and a long tail appended to grow the buffer past its room and more` ) }

@ run i k → v {
    : ~ ? ( Vec i ) o @ ?( Vec i ) { T ( vec_new [i] ) }
    ?? o { T a → { ( vec_push [i] a 1 ) } F → {} }
    ?? o { T a → {
            : ( Slice i ) sl ( slice_from_vec [i] a )
            ?? o { T b → { : ~ i j 0 ~ < j 100 { ( vec_push [i] b j ) = j + j 1 } } F → {} }
            ( nurl_println ( nurl_str_int ( slice_at [i] sl 0 ) ) )
        } F → {} }
}

@ main → i {
    ( run 0 )
    ^ 0
}
