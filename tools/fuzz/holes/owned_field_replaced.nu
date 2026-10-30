// owned_field_replaced: an owned field given fresh strings: each one it replaced was never freed.
// map: §2.13 | A2 | rejected | h126 | owned s field replaced by fresh strings; old ones leak
$ `stdlib/core/string.nu`

: Rec { s name i n }

@ main → i {
    : ~ Rec r @ Rec { ( nurl_str_cat `a` `b` ) 1 }
    = . r name ( nurl_str_cat `c` `de` )
    = . r name ( nurl_str_cat `f` `ghi` )
    ( nurl_print_int ( nurl_str_len . r name ) ) ( nurl_print `\n` )
    ^ 0
}
