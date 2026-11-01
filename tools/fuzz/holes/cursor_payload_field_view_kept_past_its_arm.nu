// cursor_payload_field_view_kept_past_its_arm: agora #336 — a view of a cursor payload's field stored into an outer holder inside a `??` arm, read after the arm while the option still owns the payload (the shape the fix must keep).
// Closed: a match payload that is a cursor over a binding that still owns it ends nothing at its arm's end: what borrows from its fields borrows from that binding from then on (bck_ids_end, __cursor_paths_to; agora #336).
// main: rejected.
// map: §2.10 | A2 | runs-clean | - | agora #336: a view of a cursor payload's field kept past its arm
$ `stdlib/core/string.nu`

: W { s v }
: H { String name }

@ mk → ?H { ^ @ ?H { T @ H { ( string_from `the option's payload's name, alive` ) } } }

@ main → i {
    : ?H oh ( mk )
    : ~ W w @ W { `literal` }
    ?? oh {
        T p → { = w @ W { ( string_data . p name ) } }
        F → {}
    }
    ( nurl_println . w v )
    ^ 0
}
