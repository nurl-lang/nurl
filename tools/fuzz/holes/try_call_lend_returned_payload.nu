// try_call_lend_returned_payload: agora #194 — `^ @ !String E { T \ ( getr w ) }`: a try over a call lending the local `w` as a returned result's payload (try_call_lend_returned_payload).
// Closed: A try over a call hands on that call's provenance (g_blk_tail_eff, set by gen_try_expr): a returned literal's payload, a `sink` argument, a return and a binding or assignment see the call, so a lend of a local is copied (agora #194).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h862 | agora #194: `^ @ !String E { T \ ( getr w ) }`: a try over a call lending the local `w` as a returned result's payload
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ pick → !String E {
    : W w ( mkw )
    ^ @ !String E { T \ ( getr w ) }
}

@ main → i {
    ?? ( pick ) { T x → ( nurl_println_int ( string_len x ) ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
