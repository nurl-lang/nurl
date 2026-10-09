// H125: an owned field assigned a string literal: the struct freed the literal at its scope's end.
$ `stdlib/core/string.nu`

: Rec { s name i n }

@ main → i {
    : ~ Rec r @ Rec { ( nurl_str_cat `a` `b` ) 1 }
    = . r name `lit`
    ( nurl_print_int ( nurl_str_len . r name ) ) ( nurl_print `\n` )
    ^ 0
}
