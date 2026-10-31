// fall_off_block_outer_local_call: agora #188 — `: W w …  { ( gets w ) }`: the call lends the function's local, which is dropped on the way out (fall_off_block_outer_local_call).
// Closed: A bare `{ … }` block that is its function's fall-off value is a value block and returns as `^ { … }` does (__is_fall_value_stmt, g_blk_fall_value): it does not drop at its `}` what it hands back (agora #188).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h830 | agora #188: `: W w …  { ( gets w ) }`: the call lends the function's local, which is dropped on the way out
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ pick → String {
    : W w @ W { ( string_from `element string long enough for a heap buffer` ) }
    { ( gets w ) }
}

@ main → i {
    : String a ( pick )
    ( nurl_println_int ( string_len a ) )
    ^ 0
}
