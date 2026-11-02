// slice_taken_on_a_continue_path_then_rebound_to_an_element_view: agora #399 — as slice_taken_on_a_break_path_then_rebound_to_an_element_view, through a continue to the loop's head
// Closed: a continue's borrows are joined at the loop's head (agora #399).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #399: as slice_taken_on_a_break_path_then_rebound_to_an_element_view, through a continue to the loop's head
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
    : ~ W a @ W { ( slice_from_vec [String] vv2 ) ( string_data e ) }
    : ~ i j 0
    ~ < j 2 {
        ? == j 1 { = a @ W { ( slice_from_vec [String] vv ) `static` } = j + j 1 continue } {}
        = a @ W { ( slice_from_vec [String] vv2 ) ( string_data e ) }
        = j + j 1
    }
    : ~ i k 0
    ~ < k 64 { ( vec_push [String] vv ( string_from `more strings to make the buffer move` ) ) = k + k 1 }
    ( nurl_println_int ( string_len ( slice_at [String] . a whole 0 ) ) )
    ( nurl_println . a part )
    ^ 0
}
