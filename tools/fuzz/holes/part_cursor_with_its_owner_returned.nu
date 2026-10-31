// part_cursor_with_its_owner_returned: agora #195 — `^ @ R { s w }`: a returned literal holding both the part cursor `s` and the local `w` it is part of (part_cursor_with_its_owner_returned).
// Closed: A cursor over part of a local is never that local's whole value (__part_src): the local goes on dropping all of itself, and the cursor's value leaves as a copy where it does not own it (agora #195).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h911 | agora #195: `^ @ R { s w }`: a returned literal holding both the part cursor `s` and the local `w` it is part of
$ `stdlib/core/string.nu`

: W { String s String t }

: R { String a W w }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) ( string_from `another string long enough for a heap buffer` ) } }

@ pick → R {
    : W w ( mkw )
    : String s ( gets w )
    ^ @ R { s w }
}

@ main → i {
    : R r ( pick )
    ( nurl_println_int ( string_len . r a ) )
    ( nurl_println_int ( string_len . . r w t ) )
    ^ 0
}
