// H929: agora #202 — `: i v \ o` over an option parameter: the failure's bare `ret` left the local `s` undropped (try_binding_fail_drops_locals).
// Closed: A try's fail path leaves the function as `^` does (gen_ret_term): the tried binding is skipped as `^ o` skips it, and a failure that owns nothing raises no question for any other operand (agora #202).
// main: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`

@ f ? i o → ?i {
    : String s ( string_from `a string long enough for a heap buffer` )
    : i v \ o
    ( nurl_println_int ( string_len s ) )
    ^ @ ?i { T + v 1 }
}

@ main → i {
    ?? ( f @ ?i { F 0 } ) { T x → ( nurl_println_int x ) F → ( nurl_println `none` ) }
    ?? ( f @ ?i { T 4 } ) { T x → ( nurl_println_int x ) F → ( nurl_println `none` ) }
    ^ 0
}
