// dyn_method_result_handed_back_by_a_forwarder_then_its_source_cleared_is_refused: `@ viaobj %Src o ( Vec S ) v → S { ^ ( first o v ) }`, `first` an impl handing back `( vec_at [S] v 0 )`, then the caller clears its Vec and reads the result
// Closed: a `dyn` method's virtual callee lends what its impls lend in the provenance pass too (__rpg_dyn_refresh), so the forwarder lends `v` (agora #699).
// main 4dfee821: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #699: a function handing back a dyn method's result lends what the impls lend
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
