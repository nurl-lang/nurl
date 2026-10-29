// H663: agora #175 — an option payload returned out of a sink enum parameter (option_payload_returned_out_of_a_sink_enum).
// Closed: an arm or a return that hands out a payload of an enum this function owns takes it out: the slot is zeroed, a box freed, the value owned (mem_enum_take; agora #175).
// v0.80.0: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`

: | E {
    Opt ? String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ unbox sink E e → ?String { ^ ?? e { Opt o → o NoVal → @ ?String { F } } }

@ main → i {
    : ?String o ( unbox @ E { Opt @ ?String { T ( mk ) } } )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
