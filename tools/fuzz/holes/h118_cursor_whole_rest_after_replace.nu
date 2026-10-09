// H118: the split-on-delimiter cursor — `: s nm ? < dt 0 rest ( slice … )` then `= rest ? < dt 0 `` ( slice … )`: the last piece IS the rest, and the literal arm is copied to own the join, so the assignment freed the buffer the piece points into.
$ `stdlib/core/string.nu`

@ rows s defs → i {
    : ~ s rest defs
    : ~ i n 0
    ~ != 0 ( nurl_str_len rest ) {
        : i dt ( nurl_str_find rest `\t` )
        : i dl ( nurl_str_len rest )
        : s nm ? < dt 0 rest ( nurl_str_slice rest 0 dt )
        = rest ? < dt 0 `` ( nurl_str_slice rest + dt 1 - dl + dt 1 )
        = n + n ( nurl_str_len nm )
    }
    ^ n
}

@ main → i {
    ( nurl_print_int ( rows `ab\tcde\tf` ) ) ( nurl_print `\n` )
    ^ 0
}
