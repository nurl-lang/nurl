// H756: agora #182 — a payload, or a field of one, of an enum literal scrutinee returned (literal_scrutinee_payload_returned).
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

@ part → String { ^ ?? @ E { S ( mk ) } { S x → x V p → . p s NoVal → ( mk ) } }

@ part2 → String { ^ ?? @ E { V @ P { ( mk ) 1 } } { S x → x V p → . p s NoVal → ( mk ) } }

@ main → i {
    ( nurl_println_int + ( string_len ( part ) ) ( string_len ( part2 ) ) )
    ^ 0
}
