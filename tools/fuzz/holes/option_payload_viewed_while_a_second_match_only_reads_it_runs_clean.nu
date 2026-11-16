// option_payload_viewed_while_a_second_match_only_reads_it_runs_clean: the second match only reads the payload
// Closed: a change through a `??` payload binding that may move its buffer ends the views of every other payload binding of the same value - its option's other cursors, an enum's other payloads read in place, and, through a borrow, the payload cursors of the owners it borrows from (bck_borrow_sweep, bck_cursor_follow; agora #874).
// main 525613db: runs clean (guard).
// map: §2.10 | A2 | runs-clean | - | AGORA-874: the second match only reads the payload
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
            ?? o { T b → { ( nurl_println ( string_data b ) ) } F → {} }
            ( nurl_println v )
        } F → {} }
}

@ main → i {
    ( run 0 )
    ^ 0
}
