// map: §7.5 | A2 | rejected | - | AGORA-958: a `??` arm closure capturing an inner block's option payload, bound by `:` then assigned to an outer closure binding
// AGORA-958 (closed): refused - a bound closure arm captures what the scrutinee holds (main 26f26b53: accepted, heap-use-after-free under ASan)
$ `stdlib/core/string.nu`

@ main → i {
    : ~ ( @ i ) g \ → i { ^ 7 }
    ? T {
        : ?String o @ ?String { T ( string_from `an inner option value long enough for the heap` ) }
        : ( @ i ) c ?? o { T s → \ → i { ^ ( string_len s ) } F → \ → i { ^ 0 } }
        = g c
    } {}
    ( nurl_println_int ( g ) )
    ^ 0
}
