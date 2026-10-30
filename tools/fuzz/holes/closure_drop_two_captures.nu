// closure_drop_two_captures: agora #186 — a closure handing back one of two `% Drop` captures through a `?` (closure_drop_two_captures).
// Closed: A closure's `?` / `??` whose value cannot be copied hands over the body's own on every path: an arm that lends is refused (g_join_lent), and an arm's call that may lend is judged at module end as a bare call is (__nc_ret_check; agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h808 | agora #186: a closure handing back one of two `% Drop` captures through a `?`
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ main → i {
    : D c1 @ D { ( string_from `first captured string long enough for a heap buffer` ) }
    : D c2 @ D { ( string_from `second captured string long enough for a heap buffer` ) }
    : ( @ D b ) f \ b c → D { ^ ? c c1 c2 }
    : D a ( f T )
    : D b ( f F )
    ( nurl_println_int + ( string_len . a s ) ( string_len . b s ) )
    ^ 0
}
