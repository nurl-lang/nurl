// H661: agora #175 — a boxed struct payload returned out of a sink enum parameter (struct_payload_returned_out_of_a_sink_enum).
// Closed: an arm or a return that hands out a payload of an enum this function owns takes it out: the slot is zeroed, a box freed, the value owned (mem_enum_take; agora #175).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: P { String s i n }

: | E {
    V P
    NoVal
}

@ unbox sink E e → P { ^ ?? e { V p → p NoVal → @ P { ( string_from `x` ) 0 } } }

@ main → i {
    : P p ( unbox @ E { V @ P { ( string_from `hello world, long enough for a heap buffer` ) 1 } } )
    ( nurl_println ( string_data . p s ) )
    ^ 0
}
