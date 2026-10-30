// H863: agora #194 — `( keep \ ( getr w ) )`, `keep` taking a `sink` (try_call_lend_sink_arg).
// Closed: A try over a call hands on that call's provenance (g_blk_tail_eff, set by gen_try_expr): a returned literal's payload, a `sink` argument, a return and a binding or assignment see the call, so a lend of a local is copied (agora #194).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ keep sink String x → i { ^ ( string_len x ) }

@ run → !i E {
    : W w ( mkw )
    : i n ( keep \ ( getr w ) )
    ^ @ !i E { T + n ( string_len . w s ) }
}

@ main → i {
    ?? ( run ) { T n → ( nurl_println_int n ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
