// H123: a string field its struct owns (the literal gave it a fresh string), assigned a view of a String: the struct freed the String's buffer, and so did the String — a double free.
$ `stdlib/core/string.nu`

: Rec { s name i n }

@ main → i {
    : String t ( string_from `view` )
    : ~ Rec r @ Rec { ( nurl_str_cat `a` `b` ) 1 }
    = . r name ( string_data t )
    ( nurl_print_int ( nurl_str_len . r name ) ) ( nurl_print `\n` )
    ^ 0
}
