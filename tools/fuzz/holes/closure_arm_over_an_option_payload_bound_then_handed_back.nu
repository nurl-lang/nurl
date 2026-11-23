// map: §7.5 | A2 | rejected | - | AGORA-958: a `??` arm closure capturing a local option's payload, bound by `:` then handed back
// AGORA-958 (closed): refused - a bound closure arm captures what the scrutinee holds (main 26f26b53: accepted, heap-use-after-free under ASan)
$ `stdlib/core/string.nu`

@ cap → ( @ i ) {
    : ?String o @ ?String { T ( string_from `an inner option value long enough for the heap` ) }
    : ( @ i ) c ?? o { T s → \ → i { ^ ( string_len s ) } F → \ → i { ^ 0 } }
    ^ c
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ^ 0
}
