// dyn_drop_result_pushed: agora #186 — the same result handed to `vec_push`, which keeps it: it cannot be copied (dyn_drop_result_pushed).
// Closed: A `% Drop` value that cannot be copied, lent on one path and made on another, is answered per call as a String is: gen_cond / gen_match publish such a join's ownership (`__last_join_own__`), and the caller drops what it owns (agora #186).
// main: rejected the same way (kept as the refusal's guard).
// map: §7.6 | A2 | rejected | h793 | agora #186: the same result handed to `vec_push`, which keeps it: it cannot be copied
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pickd D d b c → D { ^ ? c d @ D { ( mk ) } }

@ main → i {
    : D d @ D { ( mk ) }
    : ( Vec D ) v ( vec_new [D] )
    ( vec_push [D] v ( pickd d F ) )
    ( nurl_println_int ( vec_len [D] v ) )
    ^ 0
}
