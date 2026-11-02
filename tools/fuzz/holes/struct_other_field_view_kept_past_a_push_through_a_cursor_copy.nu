// struct_other_field_view_kept_past_a_push_through_a_cursor_copy: agora #411 — a view of a struct's OTHER field kept while one field is grown through a `: ~` copy of the struct (the shape the fix must keep)
// Closed: only the views at the path the change went through end (bck_view_end_via, agora #411).
// main: accepted, ran clean.
// map: §2.10 | A1 | runs-clean | - | agora #411: a view of a struct's OTHER field kept while one field is grown through a `: ~` copy of the struct (the shape the fix must keep)
$ `stdlib/core/string.nu`

: W { s v }
: H { String name String other }

@ main → i {
    : H hs @ H { ( string_from `the struct's name, short` ) ( string_from `the other field, kept apart` ) }
    : ~ W w @ W { ( string_data . hs other ) }
    : ~ H q hs
    ( string_push_str . q name ` and a much longer tail that makes the buffer move elsewhere on the heap` )
    ( nurl_println . w v )
    ^ 0
}
