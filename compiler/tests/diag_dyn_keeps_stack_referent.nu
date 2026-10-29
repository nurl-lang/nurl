// diag_dyn_keeps_stack_referent.nu — a trait object holds what its operand
// held (agora #156): over a struct whose closure captured a local by
// reference, `( dyn Trait b )` still points into this frame, bound first or
// built by a wrapper that boxes its parameter.

% Runner [T] {
    @ run T self → i
}

: B { ( @ i ) cb i pad }

% Runner B { @ run B b → i { : ( @ i ) c . b cb ^ ( c ) } }

@ wrap B b → %Runner { ^ ( dyn Runner b ) }

@ bound_then_returned → %Runner {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : B b @ B { f 0 }
    : %Runner r ( dyn Runner b )
    ^ r
}

@ through_a_wrapper → %Runner {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : B b @ B { f 0 }
    ^ ( wrap b )
}

@ main → i { ^ 0 }
