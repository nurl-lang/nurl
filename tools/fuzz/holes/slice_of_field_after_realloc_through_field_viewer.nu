// slice_of_field_after_realloc_through_field_viewer: agora #293 — a slice of `. o buf`, then `: ( Vec i ) w . o buf` and `( vec_reserve [i] w 4096 )`, then a read of the slice: the field's buffer moved through a field viewer of it (slice_of_field_after_realloc_through_field_viewer).
// Closed: the field viewer's code is odd (`o`'s own bytes), so the realloc ends the views of `o` and of its fields (bck_paths_overlap).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A1 | rejected | - | agora #293: a slice of a struct's field read after its buffer moved through a field viewer
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf i n }

@ main → i {
    : S o @ S { ( vec_new [i] ) 1 }
    ( vec_push [i] . o buf 7 )
    : ( Slice i ) sl ( slice_from_vec [i] . o buf )
    : ( Vec i ) w . o buf
    ( vec_reserve [i] w 4096 )
    ( nurl_println_int ( slice_at [i] sl 0 ) )
    ^ 0
}
