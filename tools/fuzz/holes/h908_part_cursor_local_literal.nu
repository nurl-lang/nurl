// H908: agora #195 — `: H h @ H { s }`, a literal this function keeps (part_cursor_local_literal).
// Closed: A cursor over part of a local is never that local's whole value (__part_src): the local goes on dropping all of itself, and the cursor's value leaves as a copy where it does not own it (agora #195).
// main: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`

: W { String s String t }

: H { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) ( string_from `another string long enough for a heap buffer` ) } }

@ put i n → v {
    : W w ( mkw )
    : String s ( gets w )
    : H h @ H { s }
    ( nurl_println_int ( string_len . h s ) )
}

@ main → i {
    ( put 1 )
    ^ 0
}
