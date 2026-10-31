// closure_fall_off_block: agora #188 — a closure body ending in a bare block that hands back its own String (closure_fall_off_block).
// Closed: A bare `{ … }` block that is its function's fall-off value is a value block and returns as `^ { … }` does (__is_fall_value_stmt, g_blk_fall_value): it does not drop at its `}` what it hands back (agora #188).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h831 | agora #188: a closure body ending in a bare block that hands back its own String
$ `stdlib/core/string.nu`

@ main → i {
    : ( @ String ) f \ → String {
        : i z 1
        {
            : String w ( string_from `a string from a closure's block` )
            w
        }
    }
    : String a ( f )
    ( nurl_println_int ( string_len a ) )
    ^ 0
}
