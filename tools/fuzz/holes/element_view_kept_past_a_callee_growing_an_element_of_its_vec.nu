// element_view_kept_past_a_callee_growing_an_element_of_its_vec: agora #349 — a view of `( vec_at vs 0 )` kept while `( work vs )` grows `( vec_at p 0 )` in place
// Closed: where an element's buffer may move — through a borrow of it, a callee that moves one (g_fn_ireallocs), a value lent from the owner — the views recorded of the owner end too: a view taken through an element a call lends is recorded as one (agora #439, #349).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: a view of `( vec_at vs 0 )` kept while `( work vs )` grows `( vec_at p 0 )` in place
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ work ( Vec String ) p → v { ( string_push_str ( vec_at [String] p 0 ) ` and a long tail that moves the buffer somewhere else on the heap` ) }

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element, short` ) )
    : s v ( string_data ( vec_at [String] vs 0 ) )
    ( work vs )
    ( nurl_println v )
    ^ 0
}
