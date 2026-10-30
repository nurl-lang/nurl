// H933: agora #202 — the same under a `;` defer: the defer chain dropped r, error and all, under the caller (try_local_result_fail_under_defer).
// Closed: A try's fail path leaves the function as `^` does (gen_ret_term): the tried binding is skipped as `^ o` skips it, and a failure that owns nothing raises no question for any other operand (agora #202).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ mk b ok → !i String { ? ok { ^ @ !i String { T 1 } } { ^ @ !i String { F ( string_from `an error string long enough for the heap` ) } } }

@ f b ok → !i String {
    : !i String r ( mk ok )
    ; { ( nurl_println `deferred` ) }
    : i v \ r
    ^ @ !i String { T + v 1 }
}

@ main → i {
    ?? ( f F ) { T x → ( nurl_println_int x ) F e → ( nurl_println ( string_data e ) ) }
    ^ 0
}
