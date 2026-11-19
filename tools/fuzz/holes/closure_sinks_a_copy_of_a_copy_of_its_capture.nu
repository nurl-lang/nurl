// closure_sinks_a_copy_of_a_copy_of_its_capture: AGORA-479 — `\ → i { : String y x : String z y ^ ( eat z ) }`, called twice: a copy of a copy of the capture handed to a sink
// AGORA-479 (this shape, closed; github#2068's review): refused - the copy chain is followed to the capture
// map: §2.10 | A2 | rejected | - | AGORA-479: a closure body hands a sink a copy of a copy of its capture, called twice
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : String x ( string_from `a captured string long enough for the heap buffer, surely` )
    : ( @ i ) c \ → i { : String y x : String z y ^ ( eat z ) }
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
