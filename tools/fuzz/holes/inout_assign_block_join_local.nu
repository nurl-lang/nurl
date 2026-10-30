// inout_assign_block_join_local: agora #199 — `@ put inout String o b c → v { : W w ( mkw ) = o { : i k 1 ? c ( gets w ) ( string_from "x" ) } }`: a block ending in a join over an inout parameter (inout_assign_block_join_local).
// Closed: gen_assign's inout branch judges a block ending in a join as that join (__val_eff_tt; agora #199).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h918 | agora #199: `@ put inout String o b c → v { : W w ( mkw ) = o { : i k 1 ? c ( gets w ) ( string_from … ) } }`: a block ending in a join over an inout parameter
$ `stdlib/core/string.nu`

: W { String s }

@ mkw → W { ^ @ W { ( string_from `a heap buffer to trigger use after free` ) } }

@ gets W w → String { ^ . w s }

@ put inout String o b c → v {
    : W w ( mkw )
    = o { : i k 1 ? c ( gets w ) ( string_from `x` ) }
}

@ main → i {
    : ~ String s ( string_from `initial` )
    ( put s T )
    ( nurl_println ( string_data s ) )
    ( put s F )
    ( nurl_println ( string_data s ) )
    ^ 0
}
