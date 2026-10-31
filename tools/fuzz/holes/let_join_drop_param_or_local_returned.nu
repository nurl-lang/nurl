// let_join_drop_param_or_local_returned: agora #242 — `: D t ? c x l` (`D` has a `% Drop`, `x` a borrowed parameter, `l` a local), then `^ t`: handed back as owned on `x`'s path too, the caller released its own argument (let_join_drop_param_or_local_returned).
// Closed: `l` moves into `t` on its path (§2.2), and handing back a binding that cannot be copied, owned per path and lending only what is not this frame's, answers per call with its flag (gen_ret, mem_hown_mark_dyn; agora #242).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #242: a `?` over a borrowed `% Drop` parameter and a local, bound by `:` and handed back by name
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick D x b c → D {
    : D l @ D { ( string_from `local string long enough for a heap buffer` ) }
    : D t ? c x l
    ^ t
}

@ main → i {
    : D d @ D { ( string_from `outer string long enough for a heap buffer` ) }
    : D r ( pick d T )
    : D q ( pick d F )
    ( nurl_println_int + + ( string_len . r s ) ( string_len . q s ) ( string_len . d s ) )
    ^ 0
}
