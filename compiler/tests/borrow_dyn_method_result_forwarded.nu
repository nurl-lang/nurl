// borrow_dyn_method_result_forwarded.nu — a function handing back a dyn
// method's result (`^ ( first o v )`) lends what the impls lend: the
// caller's binding of it borrows its Vec, and clearing the Vec before the
// read is refused, as the direct dyn call already was (Agora #699). The
// virtual callee's lends were joined only after the pass that computes a
// forwarder's, which found it lending nothing.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

% Src [T] {
    @ first T self ( Vec S ) v → S
}

: A { i n }

% Src A { @ first A a ( Vec S ) v → S { ^ ( vec_at [S] v 0 ) } }

@ viaobj %Src o ( Vec S ) v → S { ^ ( first o v ) }

@ main → i {
    : ~ ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va ( mks `an element string long enough for a heap buffer` ) )
    : A aa @ A { 1 }
    : %Src o ( dyn Src aa )
    : S e ( viaobj o va )
    ( vec_clear [S] va )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}
