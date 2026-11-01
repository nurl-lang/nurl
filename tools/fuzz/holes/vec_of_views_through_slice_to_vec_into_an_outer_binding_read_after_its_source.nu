// vec_of_views_through_slice_to_vec_into_an_outer_binding_read_after_its_source: agora #347 — the same with `= ws ( slice_to_vec [s] ( slice_from_vec [s] t ) )`.
// Closed: an element read through a pointer into one parameter's buffer and stored through another pointer, for an element type that can hold a view, makes the function copy that parameter's views (g_fn_vcopies, inferred from the pointers' provenance: __note_rawsrc, __note_vcopy); the container it was handed first, or the result, then depends on what they view (agora #347).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #347: slice_to_vec's result holds its argument's views
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ~ ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = ws ( slice_to_vec [s] ( slice_from_vec [s] t ) )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
