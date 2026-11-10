// enum_payload_field_bound_to_a_local_then_sunk: `?? o { Some p → { : ( Vec u ) x . p buf  ( take x ) } … }`, then the enum matched again: x read the payload's field, and the sink freed what the enum kept.
// Closed: the field-argument path takes the field's whole type (an option's has blanks of its own) and knows an enum payload by its slot (`__enum_plp`), so a lent payload's owning field is copied for a consuming callee, as #357 does for handles (agora #559).
// main 7b7dccb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #559: an option field, or an enum payload field bound to a local, of a lent payload handed to a sink
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`

: H { ( Vec u ) buf i n }
: | E { Some H None }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ main → i {
    : E o @ E { Some @ H { ( vec_new [u] ) 1 } }
    ?? o { Some p → { : ( Vec u ) x . p buf : i n ( take x ) } None → {} }
    ?? o { Some q → { ( vec_push [u] . q buf # u 65 ) ( nurl_println_int ( vec_len [u] . q buf ) ) } None → {} }
    ^ 0
}
