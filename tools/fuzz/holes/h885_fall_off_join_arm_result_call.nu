// H885: agora #198 — `? c ( getr w ) ( okf )` as the function's fall-off value (fall_off_join_arm_result_call).
// Closed: A function's fall-off `?` / `??` is handed back as `^` hands one back (mem_ret_join_own): what it lends of a local is copied, what it lends of a parameter is in the summary (agora #198).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ okf → !String E { ^ @ !String E { T ( string_from `fresh` ) } }

@ gets W w → String { ^ . w s }

@ pick b c → !String E {
    : W w ( mkw )
    ? c ( getr w ) ( okf )
}

@ main → i {
    ?? ( pick T ) { T x → ( nurl_println_int ( string_len x ) ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
