// H795: agora #186 — a `??` handing back a `% Drop` parameter on one arm and a fresh value on the other (dyn_drop_match_returned).
// Closed: A `% Drop` value that cannot be copied, lent on one path and made on another, is answered per call as a String is: gen_cond / gen_match publish such a join's ownership (`__last_join_own__`), and the caller drops what it owns (agora #186).
// main: accepted; the fresh value's `% Drop` never ran — no sanitizer finding (compiler/tests/drop_join_returned_ok pins the count).
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pickm D d ? i o → D { ^ ?? o { T x → d F → @ D { ( mk ) } } }

@ main → i {
    : D d @ D { ( mk ) }
    : D r ( pickm d @ ?i { F } )
    : D q ( pickm d @ ?i { T 1 } )
    ( nurl_println_int + + ( string_len . r s ) ( string_len . q s ) ( string_len . d s ) )
    ^ 0
}
