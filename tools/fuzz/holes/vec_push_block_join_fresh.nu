// vec_push_block_join_fresh: agora #199 — `( vec_push [String] v { : i k 1 ? c … } )`: lentness judged by first token, the pushed string leaked (vec_push_block_join_fresh).
// Closed: gen_call's arg_eff_tt judges a block ending in a join as that join (__val_eff_tt; agora #199).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h922 | agora #199: `( vec_push [String] v { : i k 1 ? c ( string_from … ) ( string_from … ) } )`: lentness judged by first token, the pushed string leaked
$ `stdlib/core/string.nu`

@ pushit inout ( Vec String ) v b c → v {
    ( vec_push [String] v { : i k 1 ? c ( string_from `y` ) ( string_from `x` ) } )
}

@ main → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( pushit v T )
    ( pushit v F )
    ^ 0
}
