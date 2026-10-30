// H886: agora #198 — `?? ( getr w ) { T x → x … }` as the fall-off value (fall_off_match_scrutinee_lend).
// Closed: A function's fall-off `?` / `??` is handed back as `^` hands one back (mem_ret_join_own): what it lends of a local is copied, what it lends of a parameter is in the summary (agora #198).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ okf → !String E { ^ @ !String E { T ( string_from `fresh` ) } }

@ gets W w → String { ^ . w s }

@ pick b c → String {
    : W w ( mkw )
    ?? ( getr w ) { T x → x F _ → ( string_from `bad` ) }
}

@ main → i {
    : String x ( pick T )
    ( nurl_println_int ( string_len x ) )
    ^ 0
}
