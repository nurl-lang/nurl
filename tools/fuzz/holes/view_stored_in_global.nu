// view_stored_in_global: a string view is stored into a global; the String dies; the global is read.
// map: §2.10 | A2 | rejected | h47 | view of a local String stored into a global; String dies; global read
$ `stdlib/core/string.nu`

: ~ s g_name `init`

@ keep → v {
    : String t ( string_from `a long string whose view goes into a global` )
    = g_name ( string_data t )
}

@ main → i {
    ( keep )
    ( nurl_println g_name )
    ^ 0
}
