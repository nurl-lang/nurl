// dyn_holder_defined_below_a_closure_literal: a dyn method defined below hands back a Vec viewing its receiver's String; a closure literal follows the call; the receiver is released before the Vec is read.
// Closed: a closure literal's own walk set-up no longer empties the enclosing function's `rvcallees`: the function is walked after the impls it waits for (__gen_closure_expr).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §6.2 | A2 | rejected | - | agora #422: a dyn holder defined below, then a closure literal: the result is tied to the receiver
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
    : ( @ i ) f \ → i { ^ 7 }
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
