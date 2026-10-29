// H664: agora #175 — one of a variant's two payloads returned, the other dropped with the enum (one_of_two_payloads_returned_out_of_an_enum).
// Closed: an arm or a return that hands out a payload of an enum this function owns takes it out: the slot is zeroed, a box freed, the value owned (mem_enum_take; agora #175).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: | E {
    S String
    Pair String String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ first sink E e → String { ^ ?? e { S s → s Pair a b → a NoVal → ( mk ) } }

@ main → i {
    : String t ( first @ E { Pair ( mk ) ( mk ) } )
    ( nurl_println ( string_data t ) )
    ^ 0
}
