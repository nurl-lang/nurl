// drop_join_local_defer_releases: agora #186 — the same with a `% Drop` local: it cannot be copied (drop_join_local_defer_releases).
// Closed: `^` of a `?` / `??` moves a selected local out only when no `;` defer is active (g_defer_count): a defer runs after the value is the caller's and may release the owner, so the lend is copied there, or refused when it cannot be (agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h853 | agora #186: the same with a `% Drop` local: it cannot be copied
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → D { ^ @ D { ( string_from `a string long enough for a heap buffer` ) } }

@ keep sink D d → v { ( nurl_println_int ( string_len . d s ) ) }

@ pick b c → D {
    : D l ( mk )
    ; { ( keep l ) }
    ^ ? c l ( mk )
}

@ main → i {
    : D a ( pick T )
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
