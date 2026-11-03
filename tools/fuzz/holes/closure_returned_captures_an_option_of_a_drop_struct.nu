// closure_returned_captures_an_option_of_a_drop_struct: agora #463 — `: ?Res x …  ^ \ → i { ?? x { … } }`, `Res` with a `% Drop` and no Clone
// Closed: a returned closure cannot be given a copy of an option it captures whose payload has no Clone: refused (agora #463).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.5 | A2 | rejected | - | agora #463: `: ?Res x …  ^ \ → i { ?? x { … } }`, `Res` with a `% Drop` and no Clone
$ `stdlib/core/string.nu`

: Res { String name }

% Drop Res {
    @ drop Res r → v { ( nurl_println `dropped` ) }
}

@ cap → ( @ i ) {
    : ?Res x @ ?Res { T @ Res { ( string_from `a resource name long enough for the heap` ) } }
    ^ \ → i { ?? x { T r → { ^ ( string_len . r name ) } F → { ^ 0 } } }
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ^ 0
}
