// H907: agora #195 — `= o s` over an `inout String o`: the caller kept a lend of `w` (part_cursor_inout_assign).
// Closed: A cursor over part of a local is never that local's whole value (__part_src): the local goes on dropping all of itself, and the cursor's value leaves as a copy where it does not own it (agora #195).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: W { String s String t }

: H { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) ( string_from `another string long enough for a heap buffer` ) } }

@ put inout String o → v {
    : W w ( mkw )
    : String s ( gets w )
    = o s
}

@ main → i {
    : ~ String o ( string_from `init` )
    ( put o )
    ( nurl_println_int ( string_len o ) )
    ^ 0
}
