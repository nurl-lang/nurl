// owned_local_into_owned_field: an owned field assigned an owned local string: both the field and the local freed the one buffer.
// map: §2.12 | A2 | rejected | h124 | owned s field assigned owned local; both free the buffer
$ `stdlib/core/string.nu`

: Rec { s name i n }

@ main → i {
    : ~ Rec r @ Rec { ( nurl_str_cat `a` `b` ) 1 }
    : s x ( nurl_str_cat `x` `yz` )
    = . r name x
    ( nurl_print_int ( nurl_str_len . r name ) ) ( nurl_print `\n` )
    ^ 0
}
