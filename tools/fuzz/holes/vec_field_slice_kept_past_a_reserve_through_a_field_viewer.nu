// vec_field_slice_kept_past_a_reserve_through_a_field_viewer: agora #293 — a slice of a struct's Vec field kept while the field's buffer is reserved through a field viewer of it (`: ( Vec i ) w . o buf`)
// Closed: a field viewer is a copy of the field's handle: the buffer it moves is the field's, and the views of `. o buf` end (bck_view_end_via; agora #293).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A1 | rejected | - | agora #293: a slice of a struct's Vec field kept while the field's buffer is reserved through a field viewer of it (`: ( Vec i ) w . o buf`)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf }

@ main → i {
    : ( Vec i ) vs ( vec_new [i] )
    ( vec_push [i] vs 1 )
    ( vec_push [i] vs 2 )
    : S o @ S { vs }
    : ( Slice i ) sl ( slice_from_vec [i] . o buf )
    : ( Vec i ) w . o buf
    ( vec_reserve [i] w 4096 )
    ?? ( slice_get [i] sl 1 ) { T x → ( nurl_print_int x ) F → {} }
    ^ 0
}
