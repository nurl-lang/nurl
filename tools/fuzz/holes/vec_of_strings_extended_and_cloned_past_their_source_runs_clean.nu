// vec_of_strings_extended_and_cloned_past_their_source_runs_clean: agora #347 — the control: the same copies of a `( Vec String )` copy each element deep, so the copies hold nothing of the block's and are read after it.
// Closed: an element read through a pointer into one parameter's buffer and stored through another pointer, for an element type that can hold a view, makes the function copy that parameter's views (g_fn_vcopies, inferred from the pointers' provenance: __note_rawsrc, __note_vcopy); the container it was handed first, or the result, then depends on what they view (agora #347).
// main: accepted and clean.
// map: §2.11 | A2 | runs-clean | - | agora #347: copies of owned elements carry nothing
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ~ ( Vec String ) ws ( vec_new [String] )
    : ~ ( Vec String ) wc ( vec_new [String] )
    : ~ ( Vec String ) wv ( vec_new [String] )
    {
        : ~ ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `an owned element long enough for the heap` ) )
        ( vec_extend [String] ws t )
        ( vec_extend_range [String] ws t 0 1 )
        = wc ( vec_clone [String] t )
        = wv ( slice_to_vec [String] ( slice_from_vec [String] t ) )
    }
    ( nurl_println ( string_data ( vec_at [String] ws 1 ) ) )
    ( nurl_println ( string_data ( vec_at [String] wc 0 ) ) )
    ( nurl_println ( string_data ( vec_at [String] wv 0 ) ) )
    ^ 0
}
