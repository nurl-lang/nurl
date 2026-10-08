// H65: a string view and its String handed to one function that grows the String, then reads the view.
$ `stdlib/core/string.nu`

@ grow_then_print String t s p → v {
    : ~ i k 0
    ~ < k 200 { ( string_push_str t `xxxxxxxxxxxxxxxx` ) = k + k 1 }
    ( nurl_println p )
}

@ main → i {
    : String t ( string_from `abc` )
    ( grow_then_print t ( string_data t ) )
    ^ 0
}
