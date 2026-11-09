// inline_grown_element_handed_beside_a_view_of_it_to_one_call: agora #349 — an exclusive call handed `( vec_at vv 0 )` to grow and a view of that element's bytes
// Closed: an exclusive call reads an inline lend as the element it is (bck_sx_mut_storage, agora #349).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #349: an inline grown element handed beside a view of it to one call
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec String ) arena ( vec_new [String] )
    ( vec_push [String] arena ( string_from `the first string of the arena, which the push doubles` ) )
    ( string_push_str ( vec_at [String] arena 0 ) ( string_data ( vec_at [String] arena 0 ) ) )
    ( nurl_println_int ( string_len ( vec_at [String] arena 0 ) ) )
    ^ 0
}
