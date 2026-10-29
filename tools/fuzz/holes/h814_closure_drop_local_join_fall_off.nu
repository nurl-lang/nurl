// H814: agora #186 — the same as the closure's fall-off value: the local would be lent past the body, and cannot be copied (closure_drop_local_join_fall_off).
// Closed: A closure's `?` / `??` whose value cannot be copied hands over the body's own on every path: an arm that lends is refused (g_join_lent), and an arm's call that may lend is judged at module end as a bare call is (__nc_ret_check; agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → D { ^ @ D { ( string_from `fresh string long enough for a heap buffer` ) } }

@ main → i {
    : ( @ D b ) f \ b c → D {
        : D l ( mk )
        ? c l ( mk )
    }
    : D a ( f T )
    : D b ( f F )
    ( nurl_println_int + ( string_len . a s ) ( string_len . b s ) )
    ^ 0
}
