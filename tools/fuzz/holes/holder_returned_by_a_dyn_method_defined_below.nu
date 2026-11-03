// holder_returned_by_a_dyn_method_defined_below: a dyn method defined below its caller hands back a holder viewing its receiver's String field.
// Closed: what a function hands back views of its parameters is its borrow walk's answer where it returns (g_fn_rviews); an indirect callee answers with what it may run (a dyn method's impls, a closure node's members), and a callee parked until the module has compiled parks its caller behind it (agora #422).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #422: a dyn method defined below its caller hands back a holder viewing its receiver's String field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Src { String text }

% Lex [T] { @ toks T self → ( Vec s ) }

@ main → i {
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : %Lex d ( dyn Lex @ Src { ( string_from `a heap string long enough to be on the heap for sure` ) } )
        = hold ( toks d )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}

% Lex Src {
    @ toks Src self → ( Vec s ) {
        : ( Vec s ) h ( vec_new [s] )
        ( vec_push [s] h ( string_data . self text ) )
        ^ h
    }
}
