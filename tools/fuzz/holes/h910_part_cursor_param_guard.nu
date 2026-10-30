// H910: agora #195 — `: String s ( gets w )` over a parameter `w`, handed back: still the caller's lend, not copied (part_cursor_param_guard).
// Closed: A cursor over part of a local is never that local's whole value (__part_src): the local goes on dropping all of itself, and the cursor's value leaves as a copy where it does not own it (agora #195).
// main: ran clean (a guard).
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s String t }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) ( string_from `another string long enough for a heap buffer` ) } }

@ pick W w → !String E {
    : String s ( gets w )
    ^ @ !String E { T s }
}

@ main → i {
    : W w ( mkw )
    ?? ( pick w ) { T x → ( nurl_println_int ( string_len x ) ) F _ → ( nurl_println `bad` ) }
    ( nurl_println_int ( string_len . w t ) )
    ^ 0
}
