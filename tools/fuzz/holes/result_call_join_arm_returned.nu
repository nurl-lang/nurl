// result_call_join_arm_returned: agora #198 — `^ ? c ( getr w ) ( okf )`: an arm's call whose result lends part of the local `w` (result_call_join_arm_returned).
// Closed: A returned join lends a local through an arm's call, a try over one or its scrutinee: copied there; one that cannot be copied is refused (agora #198).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h881 | agora #198: `^ ? c ( getr w ) ( okf )`: an arm's call whose result lends part of the local `w`
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ okf → !String E { ^ @ !String E { T ( string_from `fresh` ) } }

@ pick b c → !String E {
    : W w ( mkw )
    ^ ? c ( getr w ) ( okf )
}

@ main → i {
    ?? ( pick T ) { T x → ( nurl_println_int ( string_len x ) ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
