// enum_payload_option_field_handed_to_a_sink_then_matched_again: the user enum twin: a `?String` field of an enum binding's payload handed to a sink, then the enum matched again.
// Closed: the field-argument path takes the field's whole type (an option's has blanks of its own) and knows an enum payload by its slot (`__enum_plp`), so a lent payload's owning field is copied for a consuming callee, as #357 does for handles (agora #559).
// main 7b7dccb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #559: an option field, or an enum payload field bound to a local, of a lent payload handed to a sink
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`

: H { ? String t i n }

@ eat sink ? String x → i { ^ ?? x { T s → ( string_len s ) F → 0 } }

: | E { Some H None }

@ main → i {
    : E o @ E { Some @ H { @ ?String { T ( string_from `hey` ) } 1 } }
    ?? o { Some p → { : i n ( eat . p t ) } None → {} }
    ?? o { Some q → ( nurl_println_int ( eat2 . q t ) ) None → {} }
    ^ 0
}

@ eat2 ? String x → i { ^ ?? x { T s → ( string_len s ) F → 0 } }
