$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ take sink String s → i { ^ ( string_len s ) }

@ pick i k → i {
    : String s ( string_from `a string handed away on the early return's path` )
    : W w @ W { ( string_data s ) }
    ? == k 0 { : i n ( take s ) ^ n } {}
    ^ 0
}

@ main → i { ^ ( pick 0 ) }
