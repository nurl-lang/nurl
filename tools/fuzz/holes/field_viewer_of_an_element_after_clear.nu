// field_viewer_of_an_element_after_clear: agora #267 — `: S e ( vec_at [S] vs 0 )`, `: String f . e name`, then `( vec_clear [S] vs )` and a read of `f`: the field viewer survived the elements changing, though the handle it copied was the dropped element's (field_viewer_of_an_element_after_clear).
// Closed: a borrow survives elements changing only when its bytes are a binding's own or part of the value the change went through (bck_byte_root, bck_br_survives); `e` was read out of the elements, and so `f` with it.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A1 | rejected | - | agora #267: a field viewer of a vector element read after the vector was cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ main → i {
    : ( Vec S ) vs ( vec_new [S] )
    ( vec_push [S] vs @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : S e ( vec_at [S] vs 0 )
    : String f . e name
    ( vec_clear [S] vs )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
