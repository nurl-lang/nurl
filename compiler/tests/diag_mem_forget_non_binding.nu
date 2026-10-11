// diag_mem_forget_non_binding.nu — 'mem_forget' gives up the value a
// BINDING holds; handed an expression there is no binding whose drop
// it could cancel.

unsafe @ main → i {
    ( mem_forget ( string_from `x` ) )
    ^ 0
}
