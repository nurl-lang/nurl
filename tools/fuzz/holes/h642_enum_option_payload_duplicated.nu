// H642: agora #155 — an enum with an option-of-String payload, copied with mem_dup (enum_option_payload_duplicated).
// Closed: an anonymous-aggregate payload is heap-boxed and owned by the enum, its closure env adopted or copied (enum_payload_storage 3, __enum_box_payload; agora #155).
// v0.80.0: accepted; LeakSanitizer (both copies).
$ `stdlib/core/string.nu`

: | E {
    Opt ? String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : E e @ E { Opt @ ?String { T ( mk ) } }
    : E c ( mem_dup e )
    ?? c {
        Opt o → { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} } }
        NoVal → {}
    }
    ^ 0
}
