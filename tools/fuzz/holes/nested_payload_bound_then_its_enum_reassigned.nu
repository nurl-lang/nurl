// nested_payload_bound_then_its_enum_reassigned: agora #175 — an option payload's payload bound through an inner match, then the enum reassigned (nested_payload_bound_then_its_enum_reassigned).
// Closed: handing out an option payload's payload takes that option out of the enum (__etake_rec; agora #175).
// v0.80.0: accepted; LeakSanitizer. main: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h675 | agora #175: an option payload's payload bound through an inner match, then the enum reassigned
$ `stdlib/core/string.nu`

: | E {
    Opt ? String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ E e @ E { Opt @ ?String { T ( mk ) } }
    : String t ?? e { Opt o → ?? o { T s → s F → ( mk ) } NoVal → ( mk ) }
    = e @ E { NoVal }
    ( nurl_println ( string_data t ) )
    ^ 0
}
