// H758: agora #182 — an enum literal scrutinee whose payload is an enum literal (nested_literal_scrutinee).
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

: | Fz {
    In E
    Nil
}

@ main → i {
    ?? @ Fz { In @ E { S ( mk ) } } { In e → { ?? e { S x → { ( nurl_println_int ( string_len x ) ) } V p → {} NoVal → {} } } Nil → {} }
    ^ 0
}
