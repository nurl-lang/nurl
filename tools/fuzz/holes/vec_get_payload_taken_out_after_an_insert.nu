// vec_get_payload_taken_out_after_an_insert: the vec_insert twin of vec_get_payload_taken_out_after_a_swap: inserting at 0 moves the borrowed element to slot 1.
// Closed: the take empties the slot that holds the value it hands on, found by the value's own bytes (nurl_vec_slot_take_if): slot k where it was read, or the slot a swap, an insert or a reverse moved it to since (agora #373). No borrow is ended, so reading or taking a borrow across a reorder stays accepted and correct.
// main cadaae58: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #373: a vec_get payload taken out after its Vec was reordered
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `the first element of vs long enough for the heap allocation` ) )
    ( vec_push [String] vs ( string_from `the second element of vs long enough for the heap allocation` ) )
    : ?String o ( vec_get [String] vs 0 )
    ( vec_insert [String] vs 0 ( string_from `an inserted element long enough for the heap allocation path` ) )
    ?? o { T e → { ^ e } F → {} }
    ^ ( string_from `none placeholder long enough for the heap allocation path yes` )
}

@ main → i { : String b ( pick ) ( nurl_println ( string_data b ) ) ^ 0 }
