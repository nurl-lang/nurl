// closure_drop_local_join_returned: agora #186 — a closure handing back its own `% Drop` local through `^ ?`: the local moves out (closure_drop_local_join_returned).
// Closed: A closure body's tail join says what it owns past the body's scope (gen_block_expr): a fresh value is handed over, not copied and leaked; a local moved out by `^` is the caller's (agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h813 | agora #186: a closure handing back its own `% Drop` local through `^ ?`: the local moves out
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → D { ^ @ D { ( string_from `fresh string long enough for a heap buffer` ) } }

@ main → i {
    : ( @ D b ) f \ b c → D {
        : D l ( mk )
        ^ ? c l ( mk )
    }
    : D a ( f T )
    : D b ( f F )
    ( nurl_println_int + ( string_len . a s ) ( string_len . b s ) )
    ^ 0
}
