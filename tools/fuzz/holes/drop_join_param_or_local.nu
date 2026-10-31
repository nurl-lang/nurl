// drop_join_param_or_local: agora #186 — `^ ? c x l`, a `% Drop` parameter on one path and a local on the other (drop_join_param_or_local).
// Closed: `^` of a `?` / `??` hands the join to the caller at receiver depth 0 (g_join_rdepth): a local an arm selects moves out on its path, and what stays lent is the caller's, answered per call (agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h800 | agora #186: `^ ? c x l`, a `% Drop` parameter on one path and a local on the other
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick D x b c → D {
    : D l @ D { ( string_from `local string long enough for a heap buffer` ) }
    ^ ? c x l
}

@ main → i {
    : D d @ D { ( string_from `outer string long enough for a heap buffer` ) }
    : D r ( pick d T )
    : D q ( pick d F )
    ( nurl_println_int + + ( string_len . r s ) ( string_len . q s ) ( string_len . d s ) )
    ^ 0
}
