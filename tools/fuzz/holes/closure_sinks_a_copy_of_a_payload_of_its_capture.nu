// closure_sinks_a_copy_of_a_payload_of_its_capture: AGORA-479 — `?? x { T p → { : String y p ^ ( eat y ) } … }` in a closure body, called twice: a `:` copy of a payload read straight out of the capture (github#2068's review)
// AGORA-479 (this shape, closed): refused
// map: §2.10 | A2 | rejected | - | AGORA-479: a closure body hands a sink a copy of a payload of its capture, called twice
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ?String x @ ?String { T ( string_from `an option capture long enough for the heap buffer, surely` ) }
    : ( @ i ) c \ → i { ?? x { T p → { : String y p ^ ( eat y ) } F → { ^ 0 } } }
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
