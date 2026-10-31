// payload_bound_then_its_enum_reassigned: agora #175 — a payload bound out of an enum that is then reassigned (payload_bound_then_its_enum_reassigned).
// Closed: an arm or a return that hands out a payload of an enum this function owns takes it out: the slot is zeroed, a box freed, the value owned (mem_enum_take; agora #175).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h666 | agora #175: a payload bound out of an enum that is then reassigned
$ `stdlib/core/string.nu`

: | E {
    S String
    Pair String String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ E e @ E { S ( mk ) }
    : String t ?? e { S s → s Pair a b → a NoVal → ( mk ) }
    = e @ E { Pair ( mk ) ( mk ) }
    ( nurl_println ( string_data t ) )
    ?? e { S s → {} Pair a b → { ( nurl_println ( string_data b ) ) } NoVal → {} }
    ^ 0
}
