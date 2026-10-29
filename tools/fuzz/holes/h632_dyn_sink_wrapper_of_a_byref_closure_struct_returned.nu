// H632: agora #156 — the same through a sink parameter, the literal built at the call (dyn_sink_wrapper_of_a_byref_closure_struct_returned).
// Closed: a dyn object holds what its operand held — its stack referent, its parameter carriers and its source expression (gen_dyn_construct; agora #156).
// v0.80.0: accepted; AddressSanitizer reported stack-use-after-scope.
% Runner [T] {
    @ run T self → i
}

: B { ( @ i ) cb i pad }

% Runner B { @ run B b → i { : ( @ i ) c . b cb ^ ( c ) } }

@ wrap sink B b → %Runner { ^ ( dyn Runner b ) }

@ mk → %Runner {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : %Runner r ( wrap @ B { f 0 } )
    ^ r
}

@ main → i {
    : %Runner r ( mk )
    ( nurl_println_int ( run r ) )
    ^ 0
}
