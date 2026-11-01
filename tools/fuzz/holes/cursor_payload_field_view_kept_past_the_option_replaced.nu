// cursor_payload_field_view_kept_past_the_option_replaced: agora #336 — as cursor_payload_field_view_kept_past_its_arm, the option given a new value before the read.
// Closed: a match payload that is a cursor over a binding that still owns it ends nothing at its arm's end: what borrows from its fields borrows from that binding from then on (bck_ids_end, __cursor_paths_to; agora #336).
// main: rejected.
// map: §2.10 | A2 | rejected | - | agora #336: a cursor payload's field view read after its option is replaced
$ `stdlib/core/string.nu`

: W { s v }
: H { String name }

@ mk → ?H { ^ @ ?H { T @ H { ( string_from `the option's payload's name, alive` ) } } }

@ main → i {
    : ~ ? H oh ( mk )
    : ~ W w @ W { `literal` }
    ?? oh {
        T p → { = w @ W { ( string_data . p name ) } }
        F → {}
    }
    = oh ( mk )
    ( nurl_println . w v )
    ^ 0
}
