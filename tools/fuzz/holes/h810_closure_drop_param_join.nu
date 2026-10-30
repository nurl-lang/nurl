// H810: agora #186 — a closure handing back its `% Drop` parameter through a `?` (closure_drop_param_join).
// Closed: A closure's `?` / `??` whose value cannot be copied hands over the body's own on every path: an arm that lends is refused (g_join_lent), and an arm's call that may lend is judged at module end as a bare call is (__nc_ret_check; agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ main → i {
    : D x @ D { ( string_from `outer string long enough for a heap buffer` ) }
    : ( @ D D b ) f \ D p b c → D { ^ ? c p @ D { ( string_from `fresh string long enough for a heap buffer` ) } }
    : D a ( f x T )
    ( nurl_println_int + ( string_len . a s ) ( string_len . x s ) )
    ^ 0
}
