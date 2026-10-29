// diag_block_tail_field_not_copyable.nu — `^` of a value block whose tail
// reads a field of the block's own struct hands that field back as `^ . h
// d` would (agora #180). The struct is dropped on the way out, so a field
// that cannot be copied (a `% Drop` value) is refused.

$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part → D { ^ { : H h @ H { @ D { ( mk ) } 1 } . h d } }

@ main → i {
    : D t ( part )
    ( nurl_println_int ( string_len . t s ) )
    ^ 0
}
