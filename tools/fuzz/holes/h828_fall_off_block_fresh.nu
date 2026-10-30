// H828: agora #188 — `{ : String w ( mk ) w }` as a function's fall-off value: the block dropped `w` at its `}` (fall_off_block_fresh).
// Closed: A bare `{ … }` block that is its function's fall-off value is a value block and returns as `^ { … }` does (__is_fall_value_stmt, g_blk_fall_value): it does not drop at its `}` what it hands back (agora #188).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ pick → String {
    : i z 1
    {
        : String w ( string_from `element string long enough for a heap buffer` )
        w
    }
}

@ main → i {
    : String a ( pick )
    ( nurl_println_int ( string_len a ) )
    ^ 0
}
