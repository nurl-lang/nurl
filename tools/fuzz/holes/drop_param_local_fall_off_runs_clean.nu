// drop_param_local_fall_off_runs_clean: agora #186 / AGORA-866 — `? c x l` as a function's fall-off value, `x` a `% Drop` parameter and `l` a local: the local moves out on its path, as for `^ ? c x l`
// Closed: A `?` / `??` the body falls off with returns as `^` of it does (__fall_join_is_tail): the owner an arm selects moves out on that path, and what stays lent is the caller's, answered per call (AGORA-866).
// Earlier: accepted with a use-after-free under ASan (agora #186), then refused as "a borrowed 'D' would have to be copied here", while the same join after `^` - the same IR - was accepted.
// map: §7.6 | A2 | runs-clean | h804 | `? c x l` as a function's fall-off value, `x` a `% Drop` parameter and `l` a local: the local moves out on its path, as for `^ ? c x l`
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick D x b c → D {
    : D l @ D { ( string_from `local string long enough for a heap buffer` ) }
    ? c x l
}

@ main → i {
    : D d @ D { ( string_from `outer string long enough for a heap buffer` ) }
    : D r ( pick d T )
    : D q ( pick d F )
    ( nurl_println_int + + ( string_len . r s ) ( string_len . q s ) ( string_len . d s ) )
    ^ 0
}
