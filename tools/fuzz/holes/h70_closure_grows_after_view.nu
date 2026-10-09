// H70: a closure that grows a String is built before a view of it is taken; the closure runs; the view is read.
$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_from `abc` )
    : ( @ v ) f \ → v { : ~ i k 0 ~ < k 200 { ( string_push_str t `xxxxxxxxxxxxxxxx` ) = k + k 1 } }
    : s p ( string_data t )
    ( f )
    ( nurl_println p )
    ^ 0
}
