// H829: agora #188 — `{ : W w … ( gets w ) }` as the fall-off value: a call lending the block's own local (fall_off_block_own_local_call).
// Closed: A bare `{ … }` block that is its function's fall-off value is a value block and returns as `^ { … }` does (__is_fall_value_stmt, g_blk_fall_value): it does not drop at its `}` what it hands back (agora #188).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ pick → String {
    : i z 1
    {
        : W w @ W { ( string_from `element string long enough for a heap buffer` ) }
        ( gets w )
    }
}

@ main → i {
    : String a ( pick )
    ( nurl_println_int ( string_len a ) )
    ^ 0
}
