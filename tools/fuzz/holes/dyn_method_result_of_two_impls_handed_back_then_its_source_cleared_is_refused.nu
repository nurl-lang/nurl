// dyn_method_result_of_two_impls_handed_back_then_its_source_cleared_is_refused: the forwarder over a trait with a lending impl and a fresh one: the union lends `v`
// Closed: agora #699, the virtual's lends are the union of its impls'.
// main 4dfee821: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #699: a dyn forwarder over a lending and a fresh impl lends `v`
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

% Src B { @ first B b ( Vec S ) v → S { ^ ( mks `fresh` ) } }

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
