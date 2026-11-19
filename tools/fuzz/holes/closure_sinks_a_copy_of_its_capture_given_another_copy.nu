// closure_sinks_a_copy_of_its_capture_given_another_copy: AGORA-479 guard — refused: `: ~ String y x = y ( string_from … ) ^ ( eat y )` in a closure body, called twice: y is given another copy of the capture (github#2068's review)
// map: §2.10 | A2 | rejected | - | AGORA-479 guard: a copy of the capture given another copy of it before it is handed to a sink, called twice
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : String x ( string_from `a captured string long enough for the heap buffer, surely` )
    : ( @ i ) c \ → i { : ~ String y x : String w x = y w ^ ( eat y ) }
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
