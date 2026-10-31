// try_call_param_lend_guard: agora #194 — the try over a call lending a parameter: still a lend (try_call_param_lend_guard).
// Closed: A try over a call hands on that call's provenance (g_blk_tail_eff, set by gen_try_expr): a returned literal's payload, a `sink` argument, a return and a binding or assignment see the call, so a lend of a local is copied (agora #194).
// main: accepted and ran clean (kept as a guard).
// map: §7.6 | A2 | runs-clean | h864 | agora #194: the try over a call lending a parameter: still a lend
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ pick W p → !String E { ^ @ !String E { T \ ( getr p ) } }

@ main → i {
    : W p ( mkw )
    ?? ( pick p ) { T x → ( nurl_println_int ( string_len x ) ) F _ → ( nurl_println `bad` ) }
    ( nurl_println_int ( string_len . p s ) )
    ^ 0
}
