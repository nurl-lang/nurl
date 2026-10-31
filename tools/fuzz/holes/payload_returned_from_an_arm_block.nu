// payload_returned_from_an_arm_block: agora #175 — a payload returned by ^ inside an arm of a statement match (payload_returned_from_an_arm_block).
// Closed: an arm or a return that hands out a payload of an enum this function owns takes it out: the slot is zeroed, a box freed, the value owned (mem_enum_take; agora #175).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h668 | agora #175: a payload returned by ^ inside an arm of a statement match
$ `stdlib/core/string.nu`

: | E {
    S String
    Pair String String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ get sink E e → String {
    ?? e { S s → { ^ s } Pair a b → { ^ b } NoVal → {} }
    ^ ( mk )
}

@ main → i {
    : String t ( get @ E { S ( mk ) } )
    : String u ( get @ E { Pair ( mk ) ( mk ) } )
    ( nurl_println_int + ( string_len t ) ( string_len u ) )
    ^ 0
}
