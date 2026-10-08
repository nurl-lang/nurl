// H68: string_push_str of the String's own view: the push reallocates, then copies from freed memory.
$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_from `abcdefghijklmnopqrstuvwxyz0123456789` )
    ( string_push_str t ( string_data t ) )
    ( string_push_str t ( string_data t ) )
    ( string_push_str t ( string_data t ) )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
