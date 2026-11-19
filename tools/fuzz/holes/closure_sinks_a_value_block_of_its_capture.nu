// map: §2.10 | A2 | rejected | - | AGORA-479: a closure body hands a sink a value block whose tail is its String capture (`: String y { x }`), called twice
// AGORA-479 (this shape, closed; github#2068's review): refused - a value block whose tail is the capture is that capture (main 58ab3032: accepted)
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : String x ( string_from `a captured string long enough for the heap buffer, surely` )
    : ( @ i ) c \ → i { : String y { x } ^ ( eat y ) }
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
