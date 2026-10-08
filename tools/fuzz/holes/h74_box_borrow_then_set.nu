// H74: a box_get borrow; box_set replaces the value; the borrow is read.
$ `stdlib/core/box.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Box String ) b ( box_new [String] ( string_from `a long boxed string on the heap` ) )
    : String e ( box_get [String] b )
    ( box_set [String] b ( string_from `replacement` ) )
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
