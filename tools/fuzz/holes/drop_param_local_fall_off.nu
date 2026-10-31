// drop_param_local_fall_off: agora #186 — `? c x l` as the fall-off value: the local would be lent past its frame, and cannot be copied (drop_param_local_fall_off).
// Closed: A fall-off join that lends a local of the frame is copied, and refused when the value cannot be copied — the fall-off no longer passed such a lend on as the caller's (agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h804 | agora #186: `? c x l` as the fall-off value: the local would be lent past its frame, and cannot be copied
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
