// H909: agora #195 — a returned closure capturing `s` (part_cursor_closure_capture).
// Closed: A cursor over part of a local is never that local's whole value (__part_src): the local goes on dropping all of itself, and the cursor's value leaves as a copy where it does not own it (agora #195).
// main: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`

: W { String s String t }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) ( string_from `another string long enough for a heap buffer` ) } }

@ mk → ( @ i ) {
    : W w ( mkw )
    : String s ( gets w )
    ^ \ → i { ^ ( string_len s ) }
}

@ main → i {
    : ( @ i ) f ( mk )
    ( nurl_println_int ( f ) )
    ^ 0
}
