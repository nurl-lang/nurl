// closure_drop_local_join_fall_off_runs_clean: agora #186 / AGORA-866 — the same as a closure's fall-off value: the local moves out on its path, as for `^ ? c l ( mk )`
// Closed: A closure body's fall-off `?` / `??` returns as `^` of it does (__fall_join_is_tail; AGORA-866).
// Earlier: accepted with a use-after-free under ASan (agora #186), then refused as "a borrowed 'D' would have to be copied here", while the same join after `^` - the same IR - was accepted.
// map: §7.6 | A2 | runs-clean | h814 | the same as a closure's fall-off value: the local moves out on its path, as for `^ ? c l ( mk )`
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → D { ^ @ D { ( string_from `fresh string long enough for a heap buffer` ) } }

@ main → i {
    : ( @ D b ) f \ b c → D {
        : D l ( mk )
        ? c l ( mk )
    }
    : D a ( f T )
    : D b ( f F )
    ( nurl_println_int + ( string_len . a s ) ( string_len . b s ) )
    ^ 0
}
