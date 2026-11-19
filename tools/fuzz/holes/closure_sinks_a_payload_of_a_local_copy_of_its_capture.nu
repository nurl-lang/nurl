// map: §2.10 | A2 | rejected | - | AGORA-479: a closure body hands a sink the payload of a local copy of its option capture, called twice
// AGORA-479 (this shape, closed): refused - a closure body may not hand a sink a copy or a part of its capture, which the environment still releases (main b215deb5: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ?String x @ ?String { T ( string_from `an option capture long enough for the heap buffer, surely` ) }
    : ( @ i ) c \ → i { : ?String y x ?? y { T s → { ^ ( eat s ) } F → { ^ 0 } } }
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
