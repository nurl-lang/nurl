// struct_field_view_kept_past_a_push_through_a_cursor_copy_of_its_owner: agora #411 — a view of a struct's String field kept while the field is grown through a `: ~` copy of the struct (`: ~ H q hs  ( string_push_str . q name … )`)
// Closed: a borrow that is a copy of an owner's own handle (`cborrow` / `tborrow`, or bytes copied whole) moves THAT owner's buffer at the same path: the views of `. hs name` end (bck_view_end_via; agora #293, #411).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A1 | rejected | - | agora #411: a view of a struct's String field kept while the field is grown through a `: ~` copy of the struct (`: ~ H q hs  ( string_push_str . q name … )`)
$ `stdlib/core/string.nu`

: W { s v }
: H { String name }

@ main → i {
    : H hs @ H { ( string_from `the struct's name, short` ) }
    : ~ W w @ W { ( string_data . hs name ) }
    : ~ H q hs
    ( string_push_str . q name ` and a much longer tail that makes the buffer move elsewhere on the heap` )
    ( nurl_println . w v )
    ^ 0
}
