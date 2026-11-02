// element_view_kept_past_a_push_through_a_binding_of_the_element: agora #439 — `: s v ( string_data ( vec_at vs 0 ) )`, then `: String e ( vec_at vs 0 )` grown in place, then v read
// Closed: where an element's buffer may move — through a borrow of it, a callee that moves one (g_fn_ireallocs), a value lent from the owner — the views recorded of the owner end too: a view taken through an element a call lends is recorded as one (agora #439, #349).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #439: `: s v ( string_data ( vec_at vs 0 ) )`, then `: String e ( vec_at vs 0 )` grown in place, then v read
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `the element, short` ) )
    : s v ( string_data ( vec_at [String] vs 0 ) )
    : String e ( vec_at [String] vs 0 )
    ( string_push_str e ` and a much longer tail that makes the buffer move elsewhere on the heap` )
    ( nurl_println v )
    ^ 0
}
