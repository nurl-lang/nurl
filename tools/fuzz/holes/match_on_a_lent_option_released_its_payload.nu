// match_on_a_lent_option_released_its_payload: a match on an option parameter the function only borrows — `?? o { T r → … }` with `o` a `?Res`, `Res` a `% Drop` value with no clone — made the arm's payload its own: the arm released the caller's value, and the caller's next use read freed memory.
// Closed: the payload of an option parameter is a cursor over it (the caller's); consuming it consumes the parameter, as for a String payload.
// main (before this PR): ASan heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h226 | match on borrowed option param makes %Drop payload owned; released
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ peek ? Res o → i {
    ?? o { T r → { ^ ( vec_len [i] . r buf ) } F _ → { ^ 0 } }
}

@ main → i {
    : ?Res p @ ?Res { T @ Res { ( vec_new [i] ) } }
    ( nurl_println_int ( peek p ) )
    ( nurl_println_int ( peek p ) )
    ^ 0
}
