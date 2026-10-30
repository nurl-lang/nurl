// H898: agora #195 — `: String s ?? ( getr w ) { T x → x … }  ^ @ !String E { T s }` (match_bound_payload_wrap).
// Closed: A call whose result holds part of a local (its returned-part summary) makes the binding of that result, or of its payload, a cursor over part of the local; handed back, it is copied where it does not own its value (agora #195).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ pick → !String E {
    : W w ( mkw )
    : String s ?? ( getr w ) { T x → x F _ → ( string_from `none` ) }
    ^ @ !String E { T s }
}

@ main → i {
    ?? ( pick ) { T x → ( nurl_println_int ( string_len x ) ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
