// diag_view_of_may_owned_result_reassigned.nu — agora #679: a binding that
// can be assigned again may own what any value it was ever given hands
// over. `pick` binds `vec_get`'s lend, assigns a fresh option over it on
// one path and hands the binding back, so it answers per call and its
// caller's binding may own its value: a view of the payload handed back is
// a view of a local (it used to compile: use after free on the fresh
// path).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ pick ( Vec S ) v b own → ?S {
    : ~ ? S o ( vec_get [S] v 0 )
    ? own { = o @ ?S { T ( mks `an owned string long enough to live on the heap, for sure` ) } } {}
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
