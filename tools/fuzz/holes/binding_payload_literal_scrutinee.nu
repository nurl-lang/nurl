// binding_payload_literal_scrutinee: agora #182 — an enum literal scrutinee holding a binding's value (binding_payload_literal_scrutinee).
// Closed: a `??` over an enum literal gives the literal an owner of its own, as a call's result has: dropped at the scope's end, its payload taken out by an arm that hands it on (gen_match `__m_tmp_slot__`; agora #182).
// v0.80.0 and main: ran clean (the value is moved into the literal, which now drops it).
// map: §7.6 | A2 | runs-clean | h759 | agora #182: an enum literal scrutinee holding a binding's value
$ `stdlib/core/string.nu`

: | E {
    S String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : String s ( mk )
    ?? @ E { S s } { S x → { ( nurl_println_int ( string_len x ) ) } NoVal → {} }
    ^ 0
}
