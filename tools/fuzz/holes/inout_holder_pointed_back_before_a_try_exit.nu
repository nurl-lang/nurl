// inout_holder_pointed_back_before_a_try_exit: agora #379 — guard: the holder is pointed back at a literal before the \, so the failure path hands back nothing of the local
// Runs clean: the tryret row's checks see the holder pointed back (agora #379).
// main: accepted; ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #379: guard: the holder is pointed back at a literal before the \, so the failure path hands back nothing of the local
$ `stdlib/core/string.nu`

: | E { Bad }

: W { s v }

@ may i k → !i E {
    ? == k 1 { ^ @ !i E { F Bad } } {}
    ^ @ !i E { T k }
}

@ fill inout W w i k → !i E {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    = w @ W { ( string_data b ) }
    ( nurl_println . w v )
    = w @ W { `literal` }
    : i x \ ( may k )
    ^ @ !i E { T x }
}

@ main → i {
    : ~ W w @ W { `literal` }
    ?? ( fill w 1 ) { T _ → {} F _ → {} }
    ( nurl_println . w v )
    ^ 0
}
