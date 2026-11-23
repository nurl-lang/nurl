// map: §7.5 | A2 | runs-clean | - | AGORA-958 guard: a `??` arm closure capturing a local option's payload, bound by `:` and called where the option lives, stays accepted
// AGORA-958: the closure does not outlive the option
$ `stdlib/core/string.nu`

@ main → i {
    : ?String o @ ?String { T ( string_from `an inner option value long enough for the heap` ) }
    : ( @ i ) c ?? o { T s → \ → i { ^ ( string_len s ) } F → \ → i { ^ 0 } }
    ( nurl_println_int ( c ) )
    ^ 0
}
