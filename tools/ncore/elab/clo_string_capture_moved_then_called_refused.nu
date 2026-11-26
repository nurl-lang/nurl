// A closure reads a String it captured by name; the String moves into a sink, then the closure runs (the checker refuses it).
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : String s ( string_from `a captured string long enough for a heap buffer` )
    : ( @ i i ) f \ i x → i { ^ + x ( string_len s ) }
    : i n ( eat s )
    ^ + n ( f 1 )
}
