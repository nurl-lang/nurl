// closure_handed_back_on_one_path_under_a_defer_is_released_on_the_others: `: ( @ i i ) c ( mkc … )  ; { ( c 1 ) }  ? d { ^ c } {}  ^ \ … { … }`.
// Closed: fn_cleanup releases a closure that has an owner slot under that slot, which the path that handed the closure back has cleared (mem_retclo_own_result); the list of bindings some `^` named (`__dret_skips__`) no longer keeps its env back on every path (agora #655).
// main ee9d2c5: accepted; one `^ c` anywhere under a defer kept c's env back on all paths: on the path that hands back something else it is never released (LeakSanitizer).
// map: §7.4 | A2 | runs-clean | - | agora #655: a closure a defer keeps, handed back on one path, was never released on the others
$ `stdlib/core/string.nu`

@ mkc sink String tag → ( @ i i ) {
    ^ \ i x → i { ^ + x ( string_len tag ) }
}

@ f i n → ( @ i i ) {
    : ( @ i i ) c ( mkc ( string_from `a tag long enough for a heap buffer, yes indeed` ) )
    ; { ( nurl_println_int ( c 1 ) ) }
    ? == n 1 { ^ c } {}
    ^ \ i x → i { ^ + x 7 }
}

@ main → i {
    : ( @ i i ) a ( f 1 )
    ( nurl_println_int ( a 2 ) )
    : ( @ i i ) b ( f 9 )
    ( nurl_println_int ( b 2 ) )
    ^ 0
}
