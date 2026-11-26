// A view of a String read after the String moved away (the checker refuses it).
$ `stdlib/core/string.nu`

@ take sink String s → i { ^ ( string_len s ) }

@ main → i {
    : String t ( string_from `abc` )
    : s v ( string_data t )
    : i n ( take t )
    ^ + n ( nurl_str_len v )
}
