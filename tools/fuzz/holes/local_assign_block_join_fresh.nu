// local_assign_block_join_fresh: agora #199 — local `: ~ String o … = o { : i k 1 ? c ( string_from "y" ) ( string_from "x" ) }`: marked as borrow, the fresh string leaked (local_assign_block_join_fresh).
// Closed: mem_udrop_bind_flag judges a block ending in a join as that join (__val_eff_tt; agora #199).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h920 | agora #199: local `: ~ String o … = o { : i k 1 ? c ( string_from … ) ( string_from … ) }`: marked as borrow, the fresh string leaked
$ `stdlib/core/string.nu`

@ pick b c → i {
    : ~ String o ( string_from `initial` )
    = o { : i k 1 ? c ( string_from `y` ) ( string_from `x` ) }
    ^ ( string_len o )
}

@ main → i {
    ( pick T )
    ( pick F )
    ^ 0
}
