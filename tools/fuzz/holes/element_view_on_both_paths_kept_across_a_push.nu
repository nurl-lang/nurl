// element_view_on_both_paths_kept_across_a_push: agora #399 — guard: the binding views only an element of vv on both paths of the ?; a push grows vv and the element's bytes stay put
// Runs clean: an element-only borrow on every path stays element-only past the join (agora #399).
// main: accepted; ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #399: guard: the binding views only an element of vv on both paths of the ?; a push grows vv and the element's bytes stay put
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
    ? == n 1 {
        : String e2 ( vec_at [String] vv 0 )
        = a @ W { ( slice_from_vec [String] vv2 ) ( string_data e2 ) }
    } {}
    : ~ i k 0
    ~ < k 64 { ( vec_push [String] vv ( string_from `more strings to make the buffer move` ) ) = k + k 1 }
    ( nurl_println . a part )
    ^ 0
}
