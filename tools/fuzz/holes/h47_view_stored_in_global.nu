// H47: a string view is stored into a global; the String dies; the global is read.
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
