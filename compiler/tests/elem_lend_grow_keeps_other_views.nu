// elem_lend_grow_keeps_other_views.nu — growing ONE element of a
// Vec through a value a call lends out of it, `( string_push_str ( vec_at
// vs 0 ) … )`, moves that element's buffer alone (AGORA-374). A view of
// another element, by its index literal, stays: `( vec_at vs 1 )`'s data,
// its bytes. So does a view of the Vec's own block, a slice of it, read
// after the push, in a loop over each element, and through a forwarder.
// Every one runs clean under AddressSanitizer.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ grow String s → v { ( string_push_str s `a long tail that grows the buffer several times over` ) }

@ two → ( Vec String ) {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `short` ) )
    ( vec_push [String] vs ( string_from `second element string long enough for the heap` ) )
    ^ vs
}

@ other_element → v {
    : ( Vec String ) vs ( two )
    : s d1 ( string_data ( vec_at [String] vs 1 ) )
    ( string_push_str ( vec_at [String] vs 0 ) `a long tail that grows the buffer several times over` )
    ( nurl_println d1 )
}

@ other_element_bytes → v {
    : ( Vec String ) vs ( two )
    : ( Slice u8 ) by ( string_bytes ( vec_at [String] vs 1 ) )
    ( string_push_str ( vec_at [String] vs 0 ) `a long tail that grows the buffer several times over` )
    ( nurl_println_int ( slice_len [u8] by ) )
}

@ slice_of_the_vec → v {
    : ( Vec String ) vs ( two )
    : ( Slice String ) sl ( slice_from_vec [String] vs )
    ( string_push_str ( vec_at [String] vs 0 ) `a long tail that grows the buffer several times over` )
    ( nurl_println ( string_data ( slice_at [String] sl 1 ) ) )
    ( nurl_println_int ( string_len ( slice_at [String] sl 0 ) ) )
}

@ each_element_in_a_loop → v {
    : ( Vec String ) vs ( two )
    : ( Slice String ) sl ( slice_from_vec [String] vs )
    : ~ i k 0
    ~ < k ( slice_len [String] sl ) {
        ( string_push_str ( vec_at [String] vs k ) `a long tail that grows the buffer several times over` )
        = k + k 1
    }
    ( nurl_println_int ( string_len ( slice_at [String] sl 1 ) ) )
}

@ through_a_forwarder → v {
    : ( Vec String ) vs ( two )
    : ( Slice String ) sl ( slice_from_vec [String] vs )
    ( grow ( vec_at [String] vs 0 ) )
    ( nurl_println_int ( slice_len [String] sl ) )
}

@ main → i {
    ( other_element )
    ( other_element_bytes )
    ( slice_of_the_vec )
    ( each_element_in_a_loop )
    ( through_a_forwarder )
    ^ 0
}
