// view_of_a_payload_of_a_result_assigned_a_lend_on_both_arms_handed_back_runs_clean: agora #679 — a `: ~` option that starts as `None` and is assigned `vec_get`'s lend on both arms, handed back; its caller hands back a view of the payload
// Control for agora #679: every value the binding is given is a lend or holds nothing, so the function hands over no storage of its own and its caller's view is a view of the argument.
// map: §2.8 | A2 | runs-clean | - | agora #679: a `: ~` option that starts as `None` and is assigned `vec_get`'s lend on both arms, handed back; its caller hands back a view of the payload
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ pick ( Vec S ) v b own → ?S {
    : ~ ? S o @ ?S { F @ S { ( string_new ) 0 } }
    ? own { = o ( vec_get [S] v 0 ) } { = o ( vec_get [S] v 0 ) }
    ^ o
}

@ f ( Vec S ) v b own → s {
    : ?S o ( pick v own )
    ?? o {
        T e → { ^ ( string_data . e name ) }
        F → { ^ `` }
    }
    ^ ``
}

@ main → i {
    : ~ ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks `a lent string long enough to live on the heap, for sure` ) )
    ( nurl_println ( f v T ) )
    ( nurl_println ( f v F ) )
    ^ 0
}
