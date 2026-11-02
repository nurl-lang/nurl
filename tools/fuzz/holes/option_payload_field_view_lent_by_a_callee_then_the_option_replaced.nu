// option_payload_field_view_lent_by_a_callee_then_the_option_replaced: agora #411 — a view of an option parameter's payload field handed back by a callee from its own `??` arm (`: s w ( name_b oh )`), read after the option is given a new value
// Closed: an option parameter is storage the provenance graph follows, and a `??` payload reaches what its matched binding does: the callee lends the parameter, so the caller's view borrows from the option (__rprov_storage_params, mem_note_plend; agora #411).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #411: a view of an option parameter's payload field handed back by a callee from its own `??` arm (`: s w ( name_b oh )`), read after the option is given a new value
$ `stdlib/core/string.nu`

: H { String name }

@ name_b ? H o → s { ?? o { T p → { ^ ( string_data . p name ) } F → { ^ `` } } }

@ main → i {
    : ~ ? H oh @ ?H { T @ H { ( string_from `y` ) } }
    : s w ( name_b oh )
    = oh @ ?H { F }
    ( nurl_println w )
    ^ 0
}
