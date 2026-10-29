// H834: agora #188 — the fall-off block ending in `? c w ( mk )` over its own local (fall_off_block_join_local).
// Closed: A bare `{ … }` block that is its function's fall-off value is a value block and returns as `^ { … }` does (__is_fall_value_stmt, g_blk_fall_value): it does not drop at its `}` what it hands back (agora #188).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ pick b c → String {
    : i z 1
    {
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
