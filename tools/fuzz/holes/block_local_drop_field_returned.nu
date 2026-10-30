// block_local_drop_field_returned: agora #180 — a `% Drop` field of a value block's own struct, returned: it cannot be copied (block_local_drop_field_returned).
// Closed: `^` of a block whose tail is a field read hands the field back as `^ . q s` does — moved out of the block's own struct, or copied (ret_eff_tt, g_blk_froot; agora #180).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h748 | agora #180: a `% Drop` field of a value block's own struct, returned: it cannot be copied
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
