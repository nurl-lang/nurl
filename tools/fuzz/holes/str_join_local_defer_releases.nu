// str_join_local_defer_releases: agora #186 — `^ ? c l ( mk )` with a `;` defer handing `l` to a `sink`: the local is copied, not moved out from under the defer (str_join_local_defer_releases).
// Closed: `^` of a `?` / `??` moves a selected local out only when no `;` defer is active (g_defer_count): a defer runs after the value is the caller's and may release the owner, so the lend is copied there, or refused when it cannot be (agora #186).
// main: accepted and ran clean (a copy); the first version of #186 moved the local out and the defer released it under the caller.
// map: §7.6 | A2 | runs-clean | h852 | agora #186: `^ ? c l ( mk )` with a `;` defer handing `l` to a `sink`: the local is copied, not moved out from under the defer
$ `stdlib/core/string.nu`

@ keep sink String d → v { ( nurl_println_int ( string_len d ) ) }

@ pick b c → String {
    : String l ( string_from `a local string long enough for a heap buffer` )
    ; { ( keep l ) }
    ^ ? c l ( string_from `fresh` )
}

@ main → i {
    : String a ( pick T )
    ( nurl_println_int ( string_len a ) )
    ^ 0
}
