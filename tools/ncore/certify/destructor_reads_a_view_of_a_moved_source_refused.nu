$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ take sink String s → i { ^ ( string_len s ) }

@ main → i {
    : String s ( string_from `a string handed away while w still views it` )
    : W w @ W { ( string_data s ) }
    : i n ( take s )
    ^ 0
}
