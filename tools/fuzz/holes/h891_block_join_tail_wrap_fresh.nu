// H891: agora #198 — the same with two fresh arms: copied as if lent, the original leaked (block_join_tail_wrap_fresh).
// Closed: A returned literal's field judges a block ending in a join as that join (__val_eff_tt; agora #198).
// main: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ okf → !String E { ^ @ !String E { T ( string_from `fresh` ) } }

@ gets W w → String { ^ . w s }

@ pick b c → !String E {
    : W w ( mkw )
    ^ @ !String E { T { : i k 1 ? c ( string_from `fresh` ) ( string_from `other` ) } }
}

@ main → i {
    ?? ( pick T ) { T x → ( nurl_println_int ( string_len x ) ) F _ → ( nurl_println `bad` ) }
    ?? ( pick F ) { T x → ( nurl_println_int ( string_len x ) ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
