// try_join_arm_bound_wrap: agora #195 — `: String s ? c \ ( getr w ) ( … )` then handed back in a returned result (try_join_arm_bound_wrap).
// Closed: A call whose result holds part of a local (its returned-part summary) makes the binding of that result, or of its payload, a cursor over part of the local; handed back, it is copied where it does not own its value (agora #195).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h899 | agora #195: `: String s ? c \ ( getr w ) ( … )` then handed back in a returned result
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ pick b c → !String E {
    : W w ( mkw )
    : String s ? c \ ( getr w ) ( string_from `fresh` )
    ^ @ !String E { T s }
}

@ main → i {
    ?? ( pick T ) { T x → ( nurl_println_int ( string_len x ) ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
