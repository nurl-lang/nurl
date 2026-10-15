// diag_closure_inout_captured_inline.nu — a field of `c` passed `inout`
// beside an inline closure that captures `c`: the closure could resize the
// Vec under the element the callee is holding.
$ `stdlib/core/vec.nu`

: Fd { i pos }
: Ctx { ( Vec Fd ) fds }

@ bad inout Ctx c → b {
    ^ ( vec_update [Fd] . c fds 0 \ inout Fd f → v { ( vec_clear [Fd] . c fds ) = . f pos 1 } )
}

@ main → i {
    : ~ Ctx c @ Ctx { ( vec_new [Fd] ) }
    ( vec_push [Fd] . c fds @ Fd { 0 } )
    : b r ( bad c )
    ^ 0
}
