// closure_returned_captures_an_option_of_an_option: agora #463 — `: ??String x …  ^ \ → i { ?? x { … } }`
// Closed: a returned closure cannot be given a copy of an option of an option it captures: refused (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | rejected | - | agora #463: `: ??String x …  ^ \ → i { ?? x { … } }`
$ `stdlib/core/string.nu`

@ cap → ( @ i ) {
    : ?? String x @ ?? String { T @ ?String { T ( string_from `a nested value long enough for the heap` ) } }
    ^ \ → i { ?? x { T y → { ?? y { T s → { ^ ( string_len s ) } F → { ^ 1 } } } F → { ^ 0 } } }
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ^ 0
}
