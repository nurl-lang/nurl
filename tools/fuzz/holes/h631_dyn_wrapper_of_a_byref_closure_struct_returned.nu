// H631: agora #156 — a wrapper boxing its parameter with dyn: the caller returns the object of a by-reference closure struct (dyn_wrapper_of_a_byref_closure_struct_returned).
// Closed: a dyn object holds what its operand held — its stack referent, its parameter carriers and its source expression (gen_dyn_construct; agora #156).
// v0.80.0: accepted; AddressSanitizer reported stack-use-after-scope.
% Runner [T] {
    @ run T self → i
}

: B { ( @ i ) cb i pad }

% Runner B { @ run B b → i { : ( @ i ) c . b cb ^ ( c ) } }

@ wrap B b → %Runner { ^ ( dyn Runner b ) }

@ mk → %Runner {
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : B b @ B { f 0 }
    ^ ( wrap b )
}

@ main → i {
    : %Runner r ( mk )
    ( nurl_println_int ( run r ) )
    ^ 0
}
