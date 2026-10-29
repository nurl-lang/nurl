// H660: agora #175 — a String payload returned out of a sink enum parameter (string_payload_returned_out_of_a_sink_enum).
// Closed: an arm or a return that hands out a payload of an enum this function owns takes it out: the slot is zeroed, a box freed, the value owned (mem_enum_take; agora #175).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: | E {
    S String
    NoVal
}

@ unbox sink E e → String { ^ ?? e { S s → s NoVal → ( string_from `x` ) } }

@ main → i {
    : String s ( unbox @ E { S ( string_from `hello world, long enough for a heap buffer` ) } )
    ( nurl_println ( string_data s ) )
    ^ 0
}
