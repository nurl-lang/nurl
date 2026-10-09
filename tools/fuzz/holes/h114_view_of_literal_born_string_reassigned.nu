// H114: the H113 shape over a binding born from a literal (it owns a copy of it, and every value assigned after): the view of it outlived the next assignment.
$ `stdlib/core/string.nu`

@ main → i {
    : ~ s y ``
    = y ( nurl_str_cat `ab` `cd` )
    : s v y
    = y ( nurl_str_cat `ef` `gh!` )
    ( nurl_print_int ( nurl_str_len v ) ) ( nurl_print `\n` )
    ^ 0
}
