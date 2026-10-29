// H667: agora #175 — a payload returned through a ? join in one arm (payload_returned_through_a_join_in_an_arm).
// Closed: an arm or a return that hands out a payload of an enum this function owns takes it out: the slot is zeroed, a box freed, the value owned (mem_enum_take; agora #175).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: | E {
    S String
    Pair String String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pick sink E e b alt → String {
    ^ ?? e { S s → ? alt ( mk ) s Pair a b2 → a NoVal → ( mk ) }
}

@ main → i {
    : String t ( pick @ E { S ( mk ) } T )
    : String u ( pick @ E { S ( mk ) } F )
    ( nurl_println_int + ( string_len t ) ( string_len u ) )
    ^ 0
}
