// vec_slice_kept_past_a_reserve_through_a_cursor_copy: agora #293 — a slice of a Vec kept while the Vec's buffer is reserved through a `: ~` copy of its handle
// Closed: a `: ~` copy of an owner's handle (`cborrow`) moves that owner's buffer: its views end (bck_view_end_via; agora #293, #411).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A1 | rejected | - | agora #293: a slice of a Vec kept while the Vec's buffer is reserved through a `: ~` copy of its handle
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) vs ( vec_new [i] )
    ( vec_push [i] vs 1 )
    ( vec_push [i] vs 2 )
    : ( Slice i ) sl ( slice_from_vec [i] vs )
    : ~ ( Vec i ) w vs
    ( vec_reserve [i] w 4096 )
    ?? ( slice_get [i] sl 1 ) { T x → ( nurl_print_int x ) F → {} }
    ^ 0
}
