// H801: agora #186 — the returned join's local under a `;` defer: not moved out from under the defer, and it cannot be copied (drop_join_local_under_defer).
// Closed: `^` of a `?` / `??` moves a selected local out only when no `;` defer is active (g_defer_count): a defer may release it after the value is the caller's, so a lend that cannot be copied is refused (agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick b c → D {
    : D l @ D { ( string_from `local string long enough for a heap buffer` ) }
    ; { ( nurl_println_int ( string_len . l s ) ) }
    ^ ? c l @ D { ( string_from `fresh string long enough for a heap buffer` ) }
}

@ main → i {
    : D r ( pick T )
    : D q ( pick F )
    ( nurl_println_int + ( string_len . r s ) ( string_len . q s ) )
    ^ 0
}
