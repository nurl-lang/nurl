// defer_body_binding_named_like_an_outer_one_read_after_the_defer: `: i a 5`, `; { : i a … }`, `^ a`; the same with a closure and with a String.
// Closed: a `;` defer body's names are its own (gen_defer pushes a scope): what it binds is named inside it only, and lives on to the function's cleanup as before. Bound in the enclosing scope, the body's binding took the name over for the rest of the function, and the later read reached the body's storage, written only when the defer runs (agora #636).
// main d96ebfa: accepted; the scalar returns uninitialised stack memory, the closure and the String fault (AddressSanitizer: SEGV).
// map: §7.1 | A2 | runs-clean | - | agora #636: a binding made in a `;` defer body takes over an outer binding's name — the later read is of storage the defer has not written yet
$ `stdlib/core/string.nu`

@ scalar i n → i {
    : i a 5
    ; { : i a + n 7 ( nurl_println_int a ) }
    ^ a
}

@ closure i n → i {
    : ( @ i i ) f \ i x → i { ^ + x 1 }
    ; { : ( @ i i ) f \ i x → i { ^ + x n } ( nurl_println_int ( f 100 ) ) }
    ^ ( f 0 )
}

@ text i n → i {
    : String s ( string_from `the outer string, long enough for the heap` )
    ; { : String s ( string_from `the defer body's own string, also long enough` ) ( nurl_println_int ( string_len s ) ) }
    ^ + n ( string_len s )
}

@ main → i {
    ( nurl_println_int ( scalar 1 ) )
    ( nurl_println_int ( closure 3 ) )
    ( nurl_println_int ( text 2 ) )
    ^ 0
}
