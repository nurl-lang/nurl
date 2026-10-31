// nested_payload_returned_out_of_a_sink_enum: agora #175 — an option payload's payload returned out of a sink enum through an inner match (nested_payload_returned_out_of_a_sink_enum).
// Closed: handing out an option payload's payload takes that option out of the enum (__etake_rec; agora #175).
// v0.80.0: accepted; LeakSanitizer. main: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h674 | agora #175: an option payload's payload returned out of a sink enum through an inner match
$ `stdlib/core/string.nu`

: | E {
    Opt ? String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ inner sink E e → String { ^ ?? e { Opt o → ?? o { T s → s F → ( mk ) } NoVal → ( mk ) } }

@ main → i {
    : String t ( inner @ E { Opt @ ?String { T ( mk ) } } )
    ( nurl_println ( string_data t ) )
    ^ 0
}
