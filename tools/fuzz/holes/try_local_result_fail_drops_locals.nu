// try_local_result_fail_drops_locals: agora #202 — `: !i String r ( mk ok )  : i v \ r`: the local `s` leaked, r's error went to the caller (try_local_result_fail_drops_locals).
// Closed: A try's fail path leaves the function as `^` does (gen_ret_term): the tried binding is skipped as `^ o` skips it, and a failure that owns nothing raises no question for any other operand (agora #202).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h932 | agora #202: `: !i String r ( mk ok )  : i v \ r`: the local `s` leaked, r's error went to the caller
$ `stdlib/core/string.nu`

: | E { Bad }

@ mk b ok → !i String { ? ok { ^ @ !i String { T 1 } } { ^ @ !i String { F ( string_from `an error string long enough for the heap` ) } } }

@ f b ok → !i String {
    : String s ( string_from `a string long enough for a heap buffer` )
    : !i String r ( mk ok )
    : i v \ r
    ( nurl_println_int ( string_len s ) )
    ^ @ !i String { T + v 1 }
}

@ main → i {
    ?? ( f F ) { T x → ( nurl_println_int x ) F e → ( nurl_println ( string_data e ) ) }
    ?? ( f T ) { T x → ( nurl_println_int x ) F e → ( nurl_println ( string_data e ) ) }
    ^ 0
}
