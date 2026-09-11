// diag_block_binding_void.nu — the other half of block_expr_binding.nu.
// An EMPTY block is the unit value, so it has nothing to bind; the same
// is true of a block whose tail statement produces no value. Both used to
// be swallowed silently, leaving the program without the binding it
// declared. They are now ordinary "no value to bind" rejections.

@ main → i {
    : i x {}
    ( nurl_print ( nurl_str_int x ) )
    ^ 0
}
