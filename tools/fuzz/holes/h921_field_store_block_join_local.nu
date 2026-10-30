// H921: agora #199 — `= . h s { : i k 1 ? c ( gets w ) ( string_from "x" ) }` over `inout H h`: fresh arm copied as if lent, the original leaked (field_store_block_join_local).
// Closed: gen_field_rhs judges a block ending in a join as that join (__val_eff_tt; agora #199).
// main: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`

: W { String s }

@ mkw → W { ^ @ W { ( string_from `a heap buffer` ) } }

@ gets W w → String { ^ . w s }

: H { String s }

@ put inout H h b c → v {
    : W w ( mkw )
    = . h s { : i k 1 ? c ( gets w ) ( string_from `x` ) }
}

@ main → i {
    : ~ H h @ H { ( string_from `initial` ) }
    ( put h T )
    ( nurl_println ( string_data . h s ) )
    ( put h F )
    ( nurl_println ( string_data . h s ) )
    ^ 0
}
