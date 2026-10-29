// H794: agora #186 — the same result passed straight to a call that only reads it (dyn_drop_result_as_argument).
// Closed: A `% Drop` value that cannot be copied, lent on one path and made on another, is answered per call as a String is: gen_cond / gen_match publish such a join's ownership (`__last_join_own__`), and the caller drops what it owns (agora #186).
// main: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pickd D d b c → D { ^ ? c d @ D { ( mk ) } }

@ len D d → i { ^ ( string_len . d s ) }

@ main → i {
    : D d @ D { ( mk ) }
    ( nurl_println_int + ( len ( pickd d F ) ) ( len ( pickd d T ) ) )
    ^ 0
}
