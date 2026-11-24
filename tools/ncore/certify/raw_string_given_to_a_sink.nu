$ `stdlib/core/string.nu`

@ eat sink s t → i { ^ ( nurl_str_len t ) }

@ main → i {
    : s b ( nurl_str_cat `a` `x` )
    : i n ( eat b )
    ^ n
}
