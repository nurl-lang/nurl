// map: §7.5 | A2 | runs-clean | - | AGORA-958 guard: a `??` arm closure capturing a parameter option's payload, bound by `:` then handed back, stays accepted
// AGORA-958: the caller owns the option the closure views
$ `stdlib/core/string.nu`

@ cap ? String o → ( @ i ) {
    : ( @ i ) c ?? o { T s → \ → i { ^ ( string_len s ) } F → \ → i { ^ 0 } }
    ^ c
}

@ main → i {
    : ?String o @ ?String { T ( string_from `an inner option value long enough for the heap` ) }
    : ( @ i ) c ( cap o )
    ( nurl_println_int ( c ) )
    ^ 0
}
