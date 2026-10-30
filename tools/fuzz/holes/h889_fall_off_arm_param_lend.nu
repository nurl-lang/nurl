// H889: agora #198 — the same through a fall-off `?` arm's call (fall_off_arm_param_lend).
// Closed: A function's fall-off `?` / `??` is handed back as `^` hands one back (mem_ret_join_own): what it lends of a local is copied, what it lends of a parameter is in the summary (agora #198).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ okf → !String E { ^ @ !String E { T ( string_from `fresh` ) } }

@ gets W w → String { ^ . w s }

@ pick2 W w b c → String {
    ? c ( gets w ) ( string_from `fresh` )
}

@ outer b c → String {
    : W w ( mkw )
    ^ ( pick2 w c )
}

@ main → i {
    : String x ( outer T )
    ( nurl_println_int ( string_len x ) )
    ^ 0
}
