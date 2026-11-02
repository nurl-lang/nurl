// slice_of_a_vec_before_a_zero_trip_loop_that_rebinds_it_to_an_element_view: agora #399 — the binding holds a slice of vv on entry; a loop that runs zero times re-gives it only a view of vv's element; a push moves vv's buffer and the slice is read
// Closed: the loop head joins vi_ with bs_ (__bs_snapshot / __bs_join): a source borrowed directly on either path is borrowed directly (agora #399).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #399: the binding holds a slice of vv on entry; a loop that runs zero times re-gives it only a view of vv's element; a push moves vv's buffer and the slice is read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: W { ( Slice String ) whole s part }

@ main → i {
    : ( Vec String ) vv2 ( vec_new [String] )
    ( vec_push [String] vv2 ( string_from `an older string in another vector` ) )
    : ( Vec String ) vv ( vec_new [String] )
    ( vec_push [String] vv ( string_from `the first string in the vector that grows` ) )
    : String e ( vec_at [String] vv 0 )
    : ~ W a @ W { ( slice_from_vec [String] vv ) `static` }
    : i n 0
    : ~ i j 0
    ~ < j n { = a @ W { ( slice_from_vec [String] vv2 ) ( string_data e ) } = j + j 1 }
    : ~ i k 0
    ~ < k 64 { ( vec_push [String] vv ( string_from `more strings to make the buffer move` ) ) = k + k 1 }
    ( nurl_println_int ( string_len ( slice_at [String] . a whole 0 ) ) )
    ( nurl_println . a part )
    ^ 0
}
