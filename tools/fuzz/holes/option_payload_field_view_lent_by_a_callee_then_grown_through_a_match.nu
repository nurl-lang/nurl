// option_payload_field_view_lent_by_a_callee_then_grown_through_a_match: agora #411 — as option_payload_field_view_lent_by_a_callee_then_the_option_replaced, the payload's field grown in place through a `??` of the same option
// Closed: a change made in place through a cursor payload, or a field of it, ends what borrows from the option it is a cursor over, as through the option itself (bck_cursor_edit; A2's editB, agora #411).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #411: as option_payload_field_view_lent_by_a_callee_then_the_option_replaced, the payload's field grown in place through a `??` of the same option
$ `stdlib/core/string.nu`

: H { String name }

@ mk → ?H { ^ @ ?H { T @ H { ( string_from `the payload's name, short` ) } } }

@ name_of ? H o → s { ?? o { T p → { ^ ( string_data . p name ) } F → { ^ `` } } }

@ main → i {
    : ~ ? H oh ( mk )
    : s w ( name_of oh )
    ?? oh {
        T q → { ( string_push_str . q name ` and a much longer tail that makes the buffer move elsewhere on the heap` ) }
        F → {}
    }
    ( nurl_println w )
    ^ 0
}
