// drop_ret_block_join_local: agora #188 — the same with a `% Drop` local: it cannot be copied (drop_ret_block_join_local).
// Closed: `^` of a block whose tail is a `?` / `??` is a join return (ret_eff_tt): what its arms lend of the block's locals is copied, or refused when it cannot be (agora #188).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h836 | agora #188: the same with a `% Drop` local: it cannot be copied
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick b c → D {
    ^ {
        : D l @ D { ( string_from `a string long enough for a heap buffer` ) }
        ? c l @ D { ( string_from `another string long enough for a heap buffer` ) }
    }
}

@ main → i {
    : D a ( pick T )
    : D b ( pick F )
    ( nurl_println_int + ( string_len . a s ) ( string_len . b s ) )
    ^ 0
}
