// H796: agora #186 — a `?` over a `% Drop` parameter and a literal as the function's fall-off value (dyn_drop_join_fall_off).
// Closed: A `% Drop` value that cannot be copied, lent on one path and made on another, is answered per call as a String is: gen_cond / gen_match publish such a join's ownership (`__last_join_own__`), and the caller drops what it owns (agora #186).
// main: accepted; the fresh value's `% Drop` never ran — no sanitizer finding (compiler/tests/drop_join_returned_ok pins the count).
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pickf D d b c → D { ? c d @ D { ( mk ) } }

@ main → i {
    : D d @ D { ( mk ) }
    : D r ( pickf d F )
    : D q ( pickf d T )
    ( nurl_println_int + + ( string_len . r s ) ( string_len . q s ) ( string_len . d s ) )
    ^ 0
}
