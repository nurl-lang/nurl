// diag_mem_take_non_binding.nu — 'mem_take' makes a BINDING the owner
// of the value it read out of a container; an expression has no
// binding to own it.

@ main → i {
    ( mem_take ( string_from `x` ) )
    ^ 0
}
