// ret_block_join_local: agora #188 — `^ { : String w … ? c w ( mk ) }`: a block whose tail join lends its own local (ret_block_join_local).
// Closed: `^` of a block whose tail is a `?` / `??` is a join return (ret_eff_tt): what its arms lend of the block's locals is copied, or refused when it cannot be (agora #188).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h835 | agora #188: `^ { : String w … ? c w ( mk ) }`: a block whose tail join lends its own local
$ `stdlib/core/string.nu`

@ pick b c → String {
    ^ {
        : String w ( string_from `a string long enough for a heap buffer` )
        ? c w ( string_from `another string long enough for a heap buffer` )
    }
}

@ main → i {
    : String a ( pick T )
    : String b ( pick F )
    ( nurl_println_int + ( string_len a ) ( string_len b ) )
    ^ 0
}
