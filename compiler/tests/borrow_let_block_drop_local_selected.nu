// borrow_let_block_drop_local_selected.nu — agora #222 stage 1 (rule (A)). The
// block's tail selects its own `% Drop` local `l`, which ends at the block's
// `}`: a `D` cannot be copied out of it. It is refused; the message says to
// declare `l` where `t` is, so `t` can take it over.

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
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
