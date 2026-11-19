// map: §2.10 | A2 | rejected | - | AGORA-479: a closure over a borrowed parameter hands a sink its payload; the caller's option is freed again
// AGORA-479 (this shape, closed): refused - a closure body may not hand a sink a copy or a part of its capture, which the environment still releases (main b215deb5: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ use ? String o → i {
    : ( @ i ) c \ → i { ?? o { T s → { ^ ( eat s ) } F → { ^ 0 } } }
    ^ ( c )
}

@ main → i {
    : ?String x @ ?String { T ( string_from `a caller option long enough for the heap buffer, surely` ) }
    ( nurl_println_int ( use x ) )
    ?? x { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
