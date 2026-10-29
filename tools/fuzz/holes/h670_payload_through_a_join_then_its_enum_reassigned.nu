// H670: agora #175 — a payload bound through a `?` in an arm, then its enum reassigned (payload_through_a_join_then_its_enum_reassigned).
// Closed: a join whose value is taken takes a payload of an enum this function owns out of it (mem_arm_hown, mem_enum_take; agora #175).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: | E {
    S String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ E e @ E { S ( mk ) }
    : b c T
    : String t ?? e { S s → ? c s ( mk ) NoVal → ( mk ) }
    = e @ E { NoVal }
    ( nurl_println ( string_data t ) )
    ^ 0
}
