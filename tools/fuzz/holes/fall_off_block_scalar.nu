// fall_off_block_scalar: agora #188 — a fall-off block whose value is a number read from its own String (fall_off_block_scalar).
// Closed: A bare `{ … }` block that is its function's fall-off value is a value block and returns as `^ { … }` does (__is_fall_value_stmt, g_blk_fall_value): it does not drop at its `}` what it hands back (agora #188).
// main: accepted and ran clean (kept as a guard).
// map: §7.6 | A2 | runs-clean | h837 | agora #188: a fall-off block whose value is a number read from its own String
$ `stdlib/core/string.nu`

@ pick → i {
    : i z 1
    {
        : String w ( string_from `a string long enough for a heap buffer` )
        ( string_len w )
    }
}

@ main → i {
    ( nurl_println_int ( pick ) )
    ^ 0
}
