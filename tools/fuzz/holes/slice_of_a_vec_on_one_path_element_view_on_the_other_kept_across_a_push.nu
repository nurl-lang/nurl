// slice_of_a_vec_on_one_path_element_view_on_the_other_kept_across_a_push: agora #399 — a struct binding holds a slice of vv on one path of a ? and only a view of vv's element on the other; a push moves vv's buffer and the slice is read
// Closed: a borrow's element-only fact (vi_) holds past a ?/?? join only where every path that borrows the source says so (__vi_combine).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #399: a struct binding holds a slice of vv on one path of a ? and only a view of vv's element on the other; a push moves vv's buffer and the slice is read
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
    : i n 1
    ? == n 1 { = a @ W { ( slice_from_vec [String] vv ) `static` } } {}
    : ~ i k 0
    ~ < k 64 { ( vec_push [String] vv ( string_from `more strings to make the buffer move` ) ) = k + k 1 }
    ( nurl_println_int ( string_len ( slice_at [String] . a whole 0 ) ) )
    ( nurl_println . a part )
    ^ 0
}
