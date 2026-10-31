// payload_returned_out_of_a_temporary_enum: agora #175 — a payload returned out of a call's enum matched unbound (payload_returned_out_of_a_temporary_enum).
// Closed: an arm or a return that hands out a payload of an enum this function owns takes it out: the slot is zeroed, a box freed, the value owned (mem_enum_take; agora #175).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h665 | agora #175: a payload returned out of a call's enum matched unbound
$ `stdlib/core/string.nu`

: | E {
    S String
    Pair String String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ make → E { ^ @ E { S ( mk ) } }

@ get → String { ^ ?? ( make ) { S s → s Pair a b → b NoVal → ( mk ) } }

@ main → i {
    : String t ( get )
    ( nurl_println ( string_data t ) )
    ^ 0
}
