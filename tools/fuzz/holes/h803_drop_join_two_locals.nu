// H803: agora #186 — `^ ? c l1 l2`, both arms `% Drop` locals (drop_join_two_locals).
// Closed: `^` of a `?` / `??` hands the join to the caller at receiver depth 0 (g_join_rdepth): a local an arm selects moves out on its path, and what stays lent is the caller's, answered per call (agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick b c → D {
    : D l1 @ D { ( string_from `first local string long enough for a heap buffer` ) }
    : D l2 @ D { ( string_from `second local string long enough for a heap buffer` ) }
    ^ ? c l1 l2
}

@ main → i {
    : D a ( pick T )
    : D b ( pick F )
    ( nurl_println_int + ( string_len . a s ) ( string_len . b s ) )
    ^ 0
}
