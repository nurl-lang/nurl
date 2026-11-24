$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_from `abcdefghijklmnopqrstuvwxyz0123456789` )
    : s v ( string_data t )
    ( string_free t )
    : String u ( string_from v )
    ^ ( string_len u )
}
