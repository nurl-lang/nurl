// H7: a view taken, the String grows (realloc), the view is read.
$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_from `abc` )
    : s v ( string_data t )
    : ~ i k 0
    ~ < k 200 { ( string_push_str t `xxxxxxxxxxxxxxxx` ) = k + k 1 }
    ( nurl_println v )
    ^ 0
}
