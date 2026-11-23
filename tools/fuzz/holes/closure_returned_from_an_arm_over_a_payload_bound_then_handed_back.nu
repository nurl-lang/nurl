// map: §7.5 | A2 | rejected | - | AGORA-958 (AGORA-242's twin): a `??` whose arms are closures capturing a payload of a local, bound by `:` then handed back
// AGORA-958 (closed): refused - a bound closure arm captures what the scrutinee holds (main 26f26b53: accepted, heap-use-after-free under ASan); twin of tools/fuzz/holes/closure_returned_from_an_arm_over_a_payload.nu
$ `stdlib/core/string.nu`

@ cap → ( @ i ) {
    : ?? String oo @ ?? String { T @ ?String { T ( string_from `an inner option value long enough for the heap` ) } }
    : __el ?? oo { T inner → \ → i { ?? inner { T s → { ^ ( string_len s ) } F → { ^ 1 } } } F → \ → i { ^ 0 } }
    ^ __el
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ^ 0
}
