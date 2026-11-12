// dyn_method_result_handed_back_read_before_its_source_ends_runs_clean: the dyn forwarders above (one impl, two impls one of them fresh, the result bound first), their result read before the caller clears its Vec
// Guard for agora #699's fix: the forwarder lends what the impls lend, and a use before the source ends stays accepted.
// main 4dfee821: accepted, clean.
// map: §2.10 | A2 | runs-clean | - | agora #699 guard: a dyn forwarder's result read before its source ends is accepted
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

@ viaobj %Src o ( Vec S ) v → S { ^ ( first o v ) }

@ main → i {
    : ~ ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va ( mks `an element string long enough for a heap buffer` ) )
    : A aa @ A { 1 }
    : %Src o ( dyn Src aa )
    : S e ( viaobj o va )
    ( nurl_println ( string_data . e name ) )
    ( vec_clear [S] va )
    ^ 0
}
