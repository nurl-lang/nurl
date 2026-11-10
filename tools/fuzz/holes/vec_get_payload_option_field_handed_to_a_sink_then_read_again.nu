// vec_get_payload_option_field_handed_to_a_sink_then_read_again: a `?String` field of a vec_get payload handed to a sink, then read again through a second vec_get: the option field took neither the take nor the copy, and the callee freed what the element still held.
// Closed: the field-argument path takes the field's whole type (an option's has blanks of its own) and knows an enum payload by its slot (`__enum_plp`), so a lent payload's owning field is copied for a consuming callee, as #357 does for handles (agora #559).
// main 7b7dccb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #559: an option field, or an enum payload field bound to a local, of a lent payload handed to a sink
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`

: H { ? String t i n }

@ eat sink ? String x → i { ^ ?? x { T s → ( string_len s ) F → 0 } }

@ main → i {
    : ( Vec H ) vs ( vec_new [H] )
    ( vec_push [H] vs @ H { @ ?String { T ( string_from `hey` ) } 1 } )
    ?? ( vec_get [H] vs 0 ) { T p → { : i n ( eat . p t ) ( nurl_println_int n ) } F _ → {} }
    ?? ( vec_get [H] vs 0 ) { T q → ( nurl_println_int ( eat2 . q t ) ) F _ → {} }
    ^ 0
}

@ eat2 ? String x → i { ^ ?? x { T s → ( string_len s ) F → 0 } }
