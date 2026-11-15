// map: §2.10 | A2 | rejected | - | agora #479: a closure over an inout parameter hands a sink its payload; the caller's option is read after
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ use inout ?String o → i {
    : ( @ i ) c \ → i { ?? o { T s → { ^ ( eat s ) } F → { ^ 0 } } }
    ^ ( c )
}

@ main → i {
    : ~ ?String x @ ?String { T ( string_from `a caller option long enough for the heap buffer, surely` ) }
    ( nurl_println_int ( use x ) )
    ?? x { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
