// A String grown from a literal, from another String and from a view.
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String s ( string_from `ab` )
    : String t ( string_from `cd` )
    ( string_push_str s `ef` )
    ( string_push_str s ( string_data t ) )
    : s v ( string_data t )
    ( string_push_str s v )
    ^ ( string_len s )
}
