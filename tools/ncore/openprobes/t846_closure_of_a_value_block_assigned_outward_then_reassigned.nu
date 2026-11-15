// map: §7.6 | A2 | rejected | - | agora #846: `: g { : f \ … = keep f f }  = keep ( mkn 2 )  ( g 1 )`: a value block's closure given to an outer binding, which is reassigned
$ `stdlib/core/string.nu`

@ mkn i n → ( @ i i ) { ^ \ i x → i { ^ + x n } }

@ main → i {
    : String tag ( string_from `a captured tag long enough for a heap buffer` )
    : ~ ( @ i i ) keep ( mkn 1 )
    : ( @ i i ) g { : ( @ i i ) f \ i x → i { ^ + x ( string_len tag ) } = keep f f }
    = keep ( mkn 2 )
    ( nurl_println_int + ( g 1 ) ( keep 1 ) )
    ^ 0
}
