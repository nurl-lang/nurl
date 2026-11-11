// diag_view_of_may_owned_result_bound.nu — agora #679: `pick` hands back a
// fresh option on one path and `vec_get`'s lend on the other, so it
// answers "yours" or "lent" per call. A binding bound to such a call
// borrows the argument and may own its value besides: it is released with
// the binding when the call handed over storage of its own. A view of its
// payload handed back is therefore a view of a local (it used to compile,
// and on the fresh path the caller read freed memory).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ pick ( Vec S ) v b own → ?S {
    ? own { ^ @ ?S { T ( mks `an owned string long enough to live on the heap, for sure` ) } } {}
    : ?S found ( vec_get [S] v 0 )
    ^ found
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
