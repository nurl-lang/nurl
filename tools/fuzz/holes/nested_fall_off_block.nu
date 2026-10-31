// nested_fall_off_block: agora #188 — the fall-off block nested in another (nested_fall_off_block).
// Closed: A bare `{ … }` block that is its function's fall-off value is a value block and returns as `^ { … }` does (__is_fall_value_stmt, g_blk_fall_value): it does not drop at its `}` what it hands back (agora #188).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h832 | agora #188: the fall-off block nested in another
$ `stdlib/core/string.nu`

@ pick → String {
    : i z 1
    {
        : i y 2
        {
            : String w ( string_from `a string from a nested block` )
            w
        }
    }
}

@ main → i {
    : String a ( pick )
    ( nurl_println_int ( string_len a ) )
    ^ 0
}
