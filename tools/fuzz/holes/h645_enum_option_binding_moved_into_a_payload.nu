// H645: agora #155 — an option binding moved into an enum payload (enum_option_binding_moved_into_a_payload).
// Closed: an anonymous-aggregate payload is heap-boxed and owned by the enum, its closure env adopted or copied (enum_payload_storage 3, __enum_box_payload; agora #155).
// v0.80.0: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`

: | E {
    Opt ? String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ?String o @ ?String { T ( mk ) }
    : E e @ E { Opt o }
    ?? e {
        Opt p → { ?? p { T s → { ( nurl_println ( string_data s ) ) } F → {} } }
        NoVal → {}
    }
    ^ 0
}
