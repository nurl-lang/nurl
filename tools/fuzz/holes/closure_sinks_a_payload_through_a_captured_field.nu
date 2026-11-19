// map: §2.10 | A2 | rejected | - | AGORA-479: a closure body hands a sink a payload read through its struct capture's field, called twice
// AGORA-479 (this shape, closed): refused - a closure body may not hand a sink a copy or a part of its capture, which the environment still releases (main b215deb5: accepted, heap-use-after-free)
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
