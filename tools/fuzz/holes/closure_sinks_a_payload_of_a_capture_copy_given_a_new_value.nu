// closure_sinks_a_payload_of_a_capture_copy_given_a_new_value: AGORA-479 — `: ~ ?String y x  ?? y { T p → { = y … ( eat p ) } … }` in a closure body, called twice: p is a payload of the capture, however y is given a new value (github#2068's review)
// AGORA-479 (this shape, closed): refused
// map: §2.10 | A2 | rejected | - | AGORA-479: a payload of a capture copy handed to a sink after the copy is given a new value, called twice
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ?String x @ ?String { T ( string_from `an option capture long enough for the heap buffer, surely` ) }
    : ( @ i ) c \ → i {
        : ~ ? String y x
        ?? y { T p → { = y @ ?String { F } ^ ( eat p ) } F → { ^ 0 } }
    }
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
