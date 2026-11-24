$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_from `abcdefghijklmnopqrstuvwxyz0123456789` )
    ( string_push_str t ( string_data t ) )
    ^ ( string_len t )
}
