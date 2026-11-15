// map: §2.10 | A2 | rejected | - | agora #479: a closure body hands a sink the payload of its capture's payload, called twice
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ?? String oo @ ?? String { T @ ?String { T ( string_from `an inner payload long enough for the heap buffer, surely` ) } }
    : ( @ i ) c \ → i { ?? oo { T inner → { ?? inner { T s → { ^ ( eat s ) } F → { ^ 1 } } } F → { ^ 0 } } }
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
