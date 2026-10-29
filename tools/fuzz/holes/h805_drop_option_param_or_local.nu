// H805: agora #186 — `^ ? c xo lo` over options of a `% Drop` value, a parameter and a local (drop_option_param_or_local).
// Closed: `^` of a `?` / `??` hands the join to the caller at receiver depth 0 (g_join_rdepth): a local an arm selects moves out on its path, and what stays lent is the caller's, answered per call (agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick ? D xo b c → ?D {
    : ?D lo @ ?D { T @ D { ( string_from `local string long enough for a heap buffer` ) } }
    ^ ? c xo lo
}

@ main → i {
    : ?D o @ ?D { T @ D { ( string_from `outer string long enough for a heap buffer` ) } }
    : ?D a ( pick o T )
    : ?D b ( pick o F )
    ?? b { T d → ( nurl_println_int ( string_len . d s ) ) F → ( nurl_println `none` ) }
    ^ 0
}
