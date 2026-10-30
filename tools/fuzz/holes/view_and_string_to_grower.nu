// view_and_string_to_grower: a string view and its String handed to one function that grows the String, then reads the view.
// map: CallT.args | A1 | rejected | h65 | view and its String passed to fn that grows String then reads view
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
