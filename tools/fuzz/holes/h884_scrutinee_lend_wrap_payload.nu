// H884: agora #198 — `^ @ !String E { T ?? ( getr w ) { T x → x … } }`: the scrutinee's lend of a local in a returned payload (scrutinee_lend_wrap_payload).
// Closed: A returned join lends a local through an arm's call, a try over one or its scrutinee: copied there; one that cannot be copied is refused (agora #198).
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
    ^ @ !String E { T ?? ( getr w ) { T x → x F _ → ( string_from `bad` ) } }
}

@ main → i {
    ?? ( pick T ) { T x → ( nurl_println_int ( string_len x ) ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
