// H938: agora #202 — `: i v \ { ? c a b }` over two `!i String` parameters: the same through a join (try_join_param_results_error).
// Closed: A try's failure that owns its error and is no binding's (a field, a join's pick) is copied for the caller: its owner keeps the original (agora #202).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ f ! i String a ! i String b b c → !i String {
    : i v \ { ? c a b }
    ^ @ !i String { T + v 1 }
}

@ main → i {
    : !i String a @ !i String { F ( string_from `an error string long enough for the heap` ) }
    : !i String b @ !i String { T 2 }
    ?? ( f a b T ) { T x → ( nurl_println_int x ) F e → ( nurl_println ( string_data e ) ) }
    ^ 0
}
