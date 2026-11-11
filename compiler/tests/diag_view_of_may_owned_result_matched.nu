// diag_view_of_may_owned_result_matched.nu — agora #679: the same with the
// call matched directly. The option `?? ( pick v own ) { … }` matches is
// the `??`'s own temporary, released with it when `pick` handed over
// storage of its own; the payload borrows the arguments and may be that
// storage besides, so a view of it handed back is a view of a local (it
// used to compile: use after free on the fresh path).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ pick ( Vec S ) v b own → ?S {
    ? own { ^ @ ?S { T ( mks `an owned string long enough to live on the heap, for sure` ) } } {}
    ^ ( vec_get [S] v 0 )
}

@ f ( Vec S ) v b own → s {
    ?? ( pick v own ) {
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
