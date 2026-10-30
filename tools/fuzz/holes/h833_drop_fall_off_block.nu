// H833: agora #188 — the fall-off block handing back its own `% Drop` value (drop_fall_off_block).
// Closed: A bare `{ … }` block that is its function's fall-off value is a value block and returns as `^ { … }` does (__is_fall_value_stmt, g_blk_fall_value): it does not drop at its `}` what it hands back (agora #188).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick → D {
    : i z 1
    {
        : D d @ D { ( string_from `a string long enough for a heap buffer` ) }
        d
    }
}

@ main → i {
    : D a ( pick )
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
