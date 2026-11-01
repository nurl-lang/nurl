// A callee that leaves one argument viewing another argument's own
// storage (`string_data src` stored into an `inout` struct of views) is
// refused a temporary there: the temporary is released when the
// statement ends, and the argument would point into freed memory
// (agora #301). Bound to a name that outlives the holder, it is accepted.

$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ main → i {
    : ~ W w @ W { `literal` }
    ( repoint w ( string_from `a temporary, released after the call` ) )
    ( nurl_println . w v )
    ^ 0
}
