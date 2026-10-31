// closure_drop_capture_join: agora #186 — a closure handing back a `% Drop` capture through `^ ?`: it keeps the capture for its next call (closure_drop_capture_join).
// Closed: A closure's `?` / `??` whose value cannot be copied hands over the body's own on every path: an arm that lends is refused (g_join_lent), and an arm's call that may lend is judged at module end as a bare call is (__nc_ret_check; agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h806 | agora #186: a closure handing back a `% Drop` capture through `^ ?`: it keeps the capture for its next call
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ main → i {
    : D cap @ D { ( string_from `captured string long enough for a heap buffer` ) }
    : ( @ D b ) f \ b c → D { ^ ? c cap @ D { ( string_from `fresh string long enough for a heap buffer` ) } }
    : D a ( f T )
    : D b ( f T )
    ( nurl_println_int + ( string_len . a s ) ( string_len . b s ) )
    ^ 0
}
