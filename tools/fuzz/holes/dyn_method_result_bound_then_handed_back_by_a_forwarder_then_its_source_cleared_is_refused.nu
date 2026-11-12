// dyn_method_result_bound_then_handed_back_by_a_forwarder_then_its_source_cleared_is_refused: `: S r ( first o v ) ^ r` in the forwarder
// Closed: agora #699.
// main 4dfee821: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #699: a dyn method result bound and then handed back lends what the impls lend
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

% Src [T] {
    @ first T self ( Vec S ) v → S
}

: A { i n }
: B { i n }

% Src A { @ first A a ( Vec S ) v → S { ^ ( vec_at [S] v 0 ) } }

@ viaobj %Src o ( Vec S ) v → S { : S r ( first o v ) ^ r }

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
