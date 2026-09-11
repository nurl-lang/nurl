// diag_empty_body_value_fn.nu — a function that declares a return type
// and has an EMPTY body. The fall-off battery catches a body whose last
// statement yields nothing, but an empty body never reached it:
// gen_block_ret left `nurl_get_last_type` holding whatever the previous
// statement anywhere had set (i64 by default), so the no-value check saw
// a type it liked and the function emitted `ret i64 undef` — returning
// garbage, silently. An empty block is the unit value and now says so.

@ f → i {}

@ main → i {
    ^ ( f )
}
