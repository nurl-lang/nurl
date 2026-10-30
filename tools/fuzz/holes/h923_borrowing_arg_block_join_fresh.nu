// H923: agora #199 — `( slen { : i k 1 ? c ( string_from "y" ) ( string_from "x" ) } )`: temporary join ownership unrecorded, argument leaked (borrowing_arg_block_join_fresh).
// Closed: gen_call's arg_join_own records temporary join ownership for a block ending in a join (__val_eff_tt; agora #199).
// main: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`

@ slen String s → i {
    ^ ( string_len s )
}

@ testit b c → i {
    ^ ( slen { : i k 1 ? c ( string_from `y` ) ( string_from `x` ) } )
}

@ main → i {
    ( testit T )
    ( testit F )
    ^ 0
}
