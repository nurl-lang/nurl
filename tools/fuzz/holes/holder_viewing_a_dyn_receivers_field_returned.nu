// holder_viewing_a_dyn_receivers_field_returned: a dyn method hands back a holder viewing a String field of its receiver.
// Closed: what a function hands back views of its parameters is its borrow walk's answer where it returns (g_fn_rviews: `k` a parameter's own storage, `^k` only its elements'), and the caller's result depends on those arguments (bck_sx_ev); a callee parked until the module has compiled parks its caller behind it (agora #422).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #422: a dyn method hands back a holder viewing a String field of its receiver
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Src { String text }

% Lex [T] { @ toks T self → ( Vec s ) }

% Lex Src {
    @ toks Src self → ( Vec s ) {
        : ( Vec s ) h ( vec_new [s] )
        ( vec_push [s] h ( string_data . self text ) )
        ^ h
    }
}

@ main → i {
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : %Lex d ( dyn Lex @ Src { ( string_from `a heap string long enough to be on the heap for sure` ) } )
        = hold ( toks d )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
