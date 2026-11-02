// option_inner_payload_view_lent_by_a_callee_then_grown_through_nested_matches: agora #411 — a view of an option's payload's inner option's field, handed back by a callee through two `??` (the inner one over a field, `?? . p inner`), read after the field is grown through `?? oh { T q → ?? . q inner { T r → … } }`
// Closed: a payload of a field-path match is part of that field's binding (`__plroot`), so the callee lends the parameter; a change through a borrow of a cursor payload's field reaches the cursor's option (bck_cursor_edit, agora #411).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #411: a view of an option's payload's inner option's field, handed back by a callee through two `??` (the inner one over a field, `?? . p inner`), read after the field is grown through `?? oh { T q → ?? . q inner { T r → … } }`
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
    ?? oh {
        T q → { ?? . q inner { T r → { ( string_push_str . r name ` and a much longer tail that makes the buffer move elsewhere on the heap` ) } F → {} } }
        F → {}
    }
    ( nurl_println w )
    ^ 0
}
