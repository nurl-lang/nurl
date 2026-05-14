// Test: stdlib/std/int.nu — int_parse
$ `stdlib/std/int.nu`

@ show ! i ParseErr r → v {
    ?? r {
        T x → { ( nurl_print `OK ` ) ( nurl_print ( nurl_str_int x ) ) ( nurl_print `\n` ) }
        F e → { ( nurl_print `ERR ` ) ( nurl_print ( parse_err_msg e ) ) ( nurl_print `\n` ) }
    }
}

@ main → i {
    ( show ( int_parse `42` ) )
    ( show ( int_parse `-17` ) )
    ( show ( int_parse `+9` ) )
    ( show ( int_parse `0` ) )
    ( show ( int_parse `` ) )
    ( show ( int_parse `-` ) )
    ( show ( int_parse `+` ) )
    ( show ( int_parse `12a` ) )
    ( show ( int_parse `abc` ) )
    ( show ( int_parse ` 5` ) )
    ( show ( int_parse `5 ` ) )
    ( show ( int_parse `1234567890` ) )
    ^ 0
}
