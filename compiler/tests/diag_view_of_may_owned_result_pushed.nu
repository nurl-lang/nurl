// diag_view_of_may_owned_result_pushed.nu — agora #679: `pick2` hands back
// its `sink` argument or lends its other one. A binding bound to a call of
// it whose sunk argument is itself a call (a fresh value) keeps "may own"
// where the nested call's lend began its borrow again; a view of it pushed
// into a Vec the function's own caller holds would outlive the binding
// (it used to compile: use after free when the sunk value came back).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ pick2 sink S o S d b k → S {
    ? k { ^ o } {}
    ^ d
}

@ g ( Vec S ) v S d b own ( Vec s ) outv → v {
    : S r ( pick2 ( mks `an owned string long enough to live on the heap, for sure` ) d own )
    ( vec_push [s] outv ( string_data . r name ) )
}

@ main → i {
    : ~ ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks `a lent string long enough to live on the heap, for sure` ) )
    : S d ( mks `a default string long enough to live on the heap, for sure` )
    : ~ ( Vec s ) outv ( vec_new [s] )
    ( g v d T outv )
    ( g v d F outv )
    ( nurl_println ( vec_at [s] outv 0 ) )
    ( nurl_println ( vec_at [s] outv 1 ) )
    ^ 0
}
