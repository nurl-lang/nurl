// inout_assign_block_join_fresh: agora #199 — the same with two fresh arms: not judged as a join, the fresh string leaked (inout_assign_block_join_fresh).
// Closed: gen_assign's inout branch judges a block ending in a join as that join (__val_eff_tt; agora #199).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h919 | agora #199: `= o { : i k 1 ? c ( string_from … ) ( string_from … ) }` over `inout String o`: not judged as a join, the fresh string leaked
$ `stdlib/core/string.nu`

@ put inout String o b c → v {
    = o { : i k 1 ? c ( string_from `y` ) ( string_from `x` ) }
}

@ main → i {
    : ~ String s ( string_from `initial` )
    ( put s T )
    ( nurl_println ( string_data s ) )
    ( put s F )
    ( nurl_println ( string_data s ) )
    ^ 0
}
