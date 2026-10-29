// H753: agora #182 — a `??` over an enum literal with a String payload (string_payload_literal_scrutinee).
// Closed: a `??` over an enum literal gives the literal an owner of its own, as a call's result has: dropped at the scope's end, its payload taken out by an arm that hands it on (gen_match `__m_tmp_slot__`; agora #182).
// v0.80.0 and main: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`

: | E {
    S String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    ?? @ E { S ( mk ) } { S s → { ( nurl_println_int ( string_len s ) ) } NoVal → {} }
    ^ 0
}
