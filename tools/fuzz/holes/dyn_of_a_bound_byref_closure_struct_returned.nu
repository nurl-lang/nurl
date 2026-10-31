// dyn_of_a_bound_byref_closure_struct_returned: agora #156 — a struct holding a by-reference closure, bound, then boxed with dyn and returned (dyn_of_a_bound_byref_closure_struct_returned).
// Closed: a dyn object holds what its operand held — its stack referent, its parameter carriers and its source expression (gen_dyn_construct; agora #156).
// v0.80.0: accepted; AddressSanitizer reported stack-use-after-scope.
// map: §2.8 | A2 | rejected | h630 | agora #156: a struct holding a by-reference closure, bound, then boxed with dyn and returned
% Runner [T] {
    @ run T self → i
}

: B { ( @ i ) cb i pad }

% Runner B { @ run B b → i { : ( @ i ) c . b cb ^ ( c ) } }

@ mk → %Runner {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : B b @ B { f 0 }
    : %Runner r ( dyn Runner b )
    ^ r
}

@ main → i {
    : %Runner r ( mk )
    ( nurl_println_int ( run r ) )
    ^ 0
}
