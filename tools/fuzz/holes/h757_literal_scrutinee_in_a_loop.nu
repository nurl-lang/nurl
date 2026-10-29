// H757: agora #182 — an enum literal scrutinee in a loop (literal_scrutinee_in_a_loop).
// Closed: a `??` over an enum literal gives the literal an owner of its own, as a call's result has: dropped at the scope's end, its payload taken out by an arm that hands it on (gen_match `__m_tmp_slot__`; agora #182).
// v0.80.0 and main: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`

: P { String s i n }

: | E {
    S String
    V P
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ i k 0
    : ~ i acc 0
    ~ < k 20 {
        ?? @ E { V @ P { ( mk ) k } } { S x → { = acc + acc ( string_len x ) } V p → { = acc + acc . p n } NoVal → {} }
        = k + k 1
    }
    ( nurl_println_int acc )
    ^ 0
}
