// part_cursor_vec_push: agora #195 — `: String s ( gets w )  ( vec_push [String] v s )`, v a parameter (part_cursor_vec_push).
// Closed: A cursor over part of a local is never that local's whole value (__part_src): the local goes on dropping all of itself, and the cursor's value leaves as a copy where it does not own it (agora #195).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h905 | agora #195: `: String s ( gets w )  ( vec_push [String] v s )`, v a parameter
$ `stdlib/core/string.nu`

: W { String s String t }

: H { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) ( string_from `another string long enough for a heap buffer` ) } }

@ put ( Vec String ) v → v {
    : W w ( mkw )
    : String s ( gets w )
    ( vec_push [String] v s )
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( put v )
    ( nurl_println_int ( string_len ( vec_at [String] v 0 ) ) )
    ^ 0
}
