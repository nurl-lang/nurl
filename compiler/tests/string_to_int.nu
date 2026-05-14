// Test: string_to_int → ! i ParseErr
$ `stdlib/core/string.nu`
$ `stdlib/core/result.nu`

@ show_res ! i ParseErr r → v {
    ? ( res_is_ok [i ParseErr] r ) {
        ( nurl_print `ok=` )
        ( nurl_print ( nurl_str_int . r 1 ) )
        ( nurl_print `\n` )
    } {
        ( nurl_print `err=` )
        ( nurl_print ( parse_err_msg # ParseErr . r 1 ) )
        ( nurl_print `\n` )
    }
}

@ parse_and_show s raw → v {
    : String t ( string_from raw )
    ( show_res ( string_to_int t ) )
    ( string_free t )
}

@ main → i {
    ( parse_and_show `42` )  // ok=42
    ( parse_and_show `-17` )  // ok=-17
    ( parse_and_show `+5` )  // ok=5
    ( parse_and_show `0` )  // ok=0
    ( parse_and_show `` )  // err=empty input
    ( parse_and_show `-` )  // err=empty input
    ( parse_and_show `+` )  // err=empty input
    ( parse_and_show `abc` )  // err=bad format
    ( parse_and_show `12abc` )  // err=bad format
    ( parse_and_show `-9x` )  // err=bad format
    ( parse_and_show `1234567890` )  // ok=1234567890
    ^ 0
}
