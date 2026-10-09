// H80: a view of a String's bytes; a user helper grows the String (its buffer moves); the view is printed.
$ `stdlib/core/string.nu`

@ grow String t → v {
    : ~ i k 0
    ~ < k 200 { ( string_push_str t `xxxxxxxxxxxxxxxx` ) = k + k 1 }
}

@ main → i {
    : String t ( string_from `abc` )
    : s p ( string_data t )
    ( grow t )
    ( nurl_println p )
    ^ 0
}
