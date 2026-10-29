// H746: agora #180 — a value block's tail field of the block's own struct, returned (block_local_field_returned).
// Closed: `^` of a block whose tail is a field read hands the field back as `^ . q s` does — moved out of the block's own struct, or copied (ret_eff_tt, g_blk_froot; agora #180).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part → String { ^ { : P q @ P { ( mk ) 1 } . q s } }

@ main → i {
    : String x ( part )
    ( nurl_println_int ( string_len x ) )
    ^ 0
}
