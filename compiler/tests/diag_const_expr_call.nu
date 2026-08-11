// diag_const_expr_call.nu — a call in a top-level constant's value. A
// constant is folded at compile time, so only integer literals and the
// listed operators can appear.
: i K + 1 ( f )

@ main → i { ^ 0 }
