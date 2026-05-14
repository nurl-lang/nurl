// Test: Result combinators + error enums
$ `stdlib/core/result.nu`
$ `stdlib/core/errors.nu`

@ main → i {
    : !i ParseErr ok1 @ !i ParseErr { T 42 }
    : !i ParseErr err1 @ !i ParseErr { F @ ParseErr { BadFormat } }

    ( nurl_print ? ( res_is_ok [i ParseErr] ok1 ) `ok1_is_ok\n` `ok1_bad\n` )
    ( nurl_print ? ( res_is_err [i ParseErr] ok1 ) `ok1_err\n` `ok1_no_err\n` )
    ( nurl_print ? ( res_is_ok [i ParseErr] err1 ) `err1_ok\n` `err1_no_ok\n` )
    ( nurl_print ? ( res_is_err [i ParseErr] err1 ) `err1_is_err\n` `err1_bad\n` )

    // render error with parse_err_msg
    ( nurl_print ( parse_err_msg # ParseErr . err1 1 ) ) ( nurl_print `\n` )

    // works with string error type too
    : !i s ok2 @ !i s { T 5 }
    : !i s err2 @ !i s { F `boom` }
    ( nurl_print ? ( res_is_ok [i s] ok2 ) `ok2_is_ok\n` `ok2_bad\n` )
    ( nurl_print ? ( res_is_err [i s] err2 ) `err2_is_err\n` `err2_bad\n` )

    // unwrap_or: Ok → payload; Err → default
    ( nurl_print ( nurl_str_int ( res_unwrap_or [i ParseErr] ok1 0 ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( res_unwrap_or [i ParseErr] err1 0 ) ) ) ( nurl_print `\n` )

    // map: Ok 42 → Ok 43; Err passes through
    : ( @ i i ) bump \ i x → i { ^ + x 1 }
    : !i ParseErr m1 ( res_map [i i ParseErr] ok1 bump )
    : !i ParseErr m2 ( res_map [i i ParseErr] err1 bump )
    ( nurl_print ( nurl_str_int ( res_unwrap_or [i ParseErr] m1 0 ) ) ) ( nurl_print `\n` )
    ( nurl_print ? ( res_is_err [i ParseErr] m2 ) `map_err_preserved\n` `map_err_lost\n` )

    // and_then: Ok 42 → Ok 84; Err passes through
    : ( @ !i ParseErr i ) double_ok \ i x → !i ParseErr { ^ @ !i ParseErr { T * x 2 } }
    : !i ParseErr a1 ( res_and_then [i i ParseErr] ok1 double_ok )
    : !i ParseErr a2 ( res_and_then [i i ParseErr] err1 double_ok )
    ( nurl_print ( nurl_str_int ( res_unwrap_or [i ParseErr] a1 0 ) ) ) ( nurl_print `\n` )
    ( nurl_print ? ( res_is_err [i ParseErr] a2 ) `and_then_err_preserved\n` `and_then_err_lost\n` )

    // map_err: rewrite a string error to an enum
    : ( @ ParseErr s ) str_to_parse_err \ s _e → ParseErr { ^ @ ParseErr { Overflow } }
    : !i ParseErr me1 ( res_map_err [i s ParseErr] err2 str_to_parse_err )
    ( nurl_print ? ( res_is_err [i ParseErr] me1 ) `map_err_is_err\n` `map_err_bad\n` )
    ( nurl_print ( parse_err_msg # ParseErr . me1 1 ) ) ( nurl_print `\n` )

    ^ 0
}
