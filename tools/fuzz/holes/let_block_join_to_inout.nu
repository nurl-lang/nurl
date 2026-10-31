// let_block_join_to_inout: agora #242 — `: String t { ? c ( string_from … ) ( string_from … ) }` then `= o t` over an `inout String`: the same through a value block (let_block_join_to_inout).
// Closed: as let_join_fresh_to_inout (agora #242).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.4 | A2 | runs-clean | - | agora #242: a value block ending in a `?` of fresh Strings, bound by `:` and assigned to an `inout` parameter
$ `stdlib/core/string.nu`

@ put inout String o b c → v {
    : String t { ? c ( string_from `yes string long enough for a heap buffer` ) ( string_from `no string long enough for a heap buffer` ) }
    = o t
}

@ main → i {
    : ~ String s ( string_from `initial string long enough for a heap buffer` )
    ( put s T )
    ( nurl_println ( string_data s ) )
    ( put s F )
    ( nurl_println ( string_data s ) )
    ^ 0
}
