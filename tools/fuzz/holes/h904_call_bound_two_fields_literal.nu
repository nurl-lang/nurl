// H904: agora #195 — `: String s ( gets w )  ^ @ !String E { T s }` with `w` holding a second field: taken for w's whole value, the other field leaked (call_bound_two_fields_literal).
// Closed: A cursor over part of a local is never that local's whole value (__part_src): the local goes on dropping all of itself, and the cursor's value leaves as a copy where it does not own it (agora #195).
// main: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s String t }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) ( string_from `another string long enough for a heap buffer` ) } }

@ pick → !String E {
    : W w ( mkw )
    : String s ( gets w )
    ^ @ !String E { T s }
}

@ main → i {
    ?? ( pick ) { T x → ( nurl_println_int ( string_len x ) ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
