// diag_mem_put_back_non_binding.nu — 'mem_put_back' marks the next
// store of a BINDING as a write-back; an expression is never stored.

@ main → i {
    ( mem_put_back ( string_from `x` ) )
    ^ 0
}
