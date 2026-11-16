// map: §2.10 | A2 | rejected | - | agora #479: a closure body hands a sink a payload read through its struct capture's field, called twice
$ `stdlib/core/string.nu`

: H { ? String o i n }

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : H h @ H { @ ?String { T ( string_from `a field payload long enough for the heap buffer, surely` ) } 3 }
    : ( @ i ) c \ → i { ?? . h o { T s → { ^ ( eat s ) } F → { ^ 0 } } }
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
