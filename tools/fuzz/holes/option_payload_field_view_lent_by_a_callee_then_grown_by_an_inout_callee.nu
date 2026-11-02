// option_payload_field_view_lent_by_a_callee_then_grown_by_an_inout_callee: agora #411 — as option_payload_field_view_lent_by_a_callee_then_the_option_replaced, the field grown by an `inout` callee through its own `??` over its parameter
// Closed: a change a callee makes through a `??` payload of its parameter is that parameter's in its mutation summaries — its own buffer and an element's (gen_call's mutation and irealloc edges, agora #411).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #411: as option_payload_field_view_lent_by_a_callee_then_the_option_replaced, the field grown by an `inout` callee through its own `??` over its parameter
$ `stdlib/core/string.nu`

: H { String name }

@ mk → ?H { ^ @ ?H { T @ H { ( string_from `the payload's name, short` ) } } }

@ name_of ? H o → s { ?? o { T p → { ^ ( string_data . p name ) } F → { ^ `` } } }

@ grow inout ? H o → v {
    ?? o {
        T q → { ( string_push_str . q name ` and a much longer tail that makes the buffer move elsewhere on the heap` ) }
        F → {}
    }
}

@ main → i {
    : ~ ? H oh ( mk )
    : s w ( name_of oh )
    ( grow oh )
    ( nurl_println w )
    ^ 0
}
