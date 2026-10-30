// drop_join_returns_local: agora #186 — `^ ? c l @ D { … }` with `l` a `% Drop` local: the local moves out on its path (drop_join_returns_local).
// Closed: `^` of a `?` / `??` hands the join to the caller at receiver depth 0 (g_join_rdepth): a local an arm selects moves out on its path, and what stays lent is the caller's, answered per call (agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h799 | agora #186: `^ ? c l @ D { … }` with `l` a `% Drop` local: the local moves out on its path
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pickl b c → D {
    : D l @ D { ( mk ) }
    ^ ? c l @ D { ( mk ) }
}

@ main → i {
    : D r ( pickl T )
    : D q ( pickl F )
    ( nurl_println_int + ( string_len . r s ) ( string_len . q s ) )
    ^ 0
}
