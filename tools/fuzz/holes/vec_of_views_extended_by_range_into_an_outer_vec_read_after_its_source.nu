// vec_of_views_extended_by_range_into_an_outer_vec_read_after_its_source: agora #347 — the same with `vec_extend_range`.
// Closed: an element read through a pointer into one parameter's buffer and stored through another pointer, for an element type that can hold a view, makes the function copy that parameter's views (g_fn_vcopies, inferred from the pointers' provenance: __note_rawsrc, __note_vcopy); the container it was handed first, or the result, then depends on what they view (agora #347).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #347: vec_extend_range copies its source's views into its destination
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ~ ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        ( vec_extend_range [s] ws t 0 1 )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
