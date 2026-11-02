// option_inner_payload_view_lent_by_a_callee_then_the_option_replaced: agora #411 — as option_inner_payload_view_lent_by_a_callee_then_grown_through_nested_matches, the option given a new value
// Closed: a payload of a field-path match is part of that field's binding (`__plroot`): the callee lends the parameter, and the caller's view borrows from the option (agora #411).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #411: as option_inner_payload_view_lent_by_a_callee_then_grown_through_nested_matches, the option given a new value
$ `stdlib/core/string.nu`

: In { String name }
: H { ? In inner }

@ mk → ?H { ^ @ ?H { T @ H { @ ?In { T @ In { ( string_from `the inner payload's name, short` ) } } } } }

@ name_of ? H o → s {
    ?? o {
        T p → { ?? . p inner { T i → { ^ ( string_data . i name ) } F → { ^ `` } } }
        F → { ^ `` }
    }
}

@ main → i {
    : ~ ? H oh ( mk )
    : s w ( name_of oh )
    = oh ( mk )
    ?? oh {
        T q → { ?? . q inner { T r → { ( string_push_str . r name ` and a much longer tail that makes the buffer move elsewhere on the heap` ) } F → {} } }
        F → {}
    }
    ( nurl_println w )
    ^ 0
}
