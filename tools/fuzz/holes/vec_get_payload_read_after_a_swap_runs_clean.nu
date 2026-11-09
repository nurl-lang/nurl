// vec_get_payload_read_after_a_swap_runs_clean: a `??` payload of `( vec_get [String] vs 0 )` read after `( vec_swap [String] vs 0 1 )`: the payload is the element it borrowed, which lives on in slot 1, and the read is right.
// Closed: the take empties the slot that holds the value it hands on, found by the value's own bytes (nurl_vec_slot_take_if): slot k where it was read, or the slot a swap, an insert or a reverse moved it to since (agora #373). No borrow is ended, so reading or taking a borrow across a reorder stays accepted and correct.
// main cadaae58: runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #373: a vec_get payload taken out after its Vec was reordered
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `the first element of vs long enough for the heap allocation` ) )
    ( vec_push [String] vs ( string_from `the second element of vs long enough for the heap allocation` ) )
    : ?String o ( vec_get [String] vs 0 )
    ?? o { T e → { ( vec_swap [String] vs 0 1 ) ( nurl_println ( string_data e ) ) } F → {} }
    ^ 0
}
