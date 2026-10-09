// H113: a copy of a string binding that owns its buffer is a view of that buffer — `: s y x` read after `= x …` freed it (an `s` was taken for a view of nothing, so the copy borrowed nothing).
$ `stdlib/core/string.nu`

@ main → i {
    : ~ s x ( nurl_str_cat `ab` `cd` )
    : s y x
    = x ( nurl_str_cat `ef` `gh!` )
    ( nurl_print_int ( nurl_str_len y ) ) ( nurl_print `\n` )
    ^ 0
}
