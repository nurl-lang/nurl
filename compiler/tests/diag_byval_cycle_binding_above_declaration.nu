// diag_byval_cycle_binding_above_declaration.nu — two structs that hold
// each other by value, declared below a function that binds one: still
// refused as having no finite size now that layouts are read before any
// body (agora #772); main crashed here (__type_needs_drop round the cycle).

@ f → i {
    : A x ( mk )
    ^ 0
}

@ mk → A { ^ ( mk ) }

: A { B b }
: B { A a }

@ main → i { ^ ( f ) }
