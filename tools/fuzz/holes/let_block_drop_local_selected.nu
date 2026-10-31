// let_block_drop_local_selected: agora #222 — the same with a `% Drop` local the join selects: it cannot be copied out (let_block_drop_local_selected).
// Closed: rule (A) refuses a value lent out of a block's own local that cannot be copied; the message says to declare the local where the binding is.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #222: a typed binding of a block whose tail selects its own `% Drop` local: it cannot be copied
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick b c → D {
    : D t {
        : D l @ D { ( string_from `a string long enough for a heap buffer` ) }
        ? c l @ D { ( string_from `another string long enough for a heap buffer` ) }
    }
    ^ t
}

@ main → i {
    : D a ( pick T )
    : D b ( pick F )
    ( nurl_println_int + ( string_len . a s ) ( string_len . b s ) )
    ^ 0
}
