// view_of_a_result_lent_by_either_argument_pushed_into_the_callers_vec_runs_clean: agora #679 — a function that lends one of its two arguments on every call; the caller pushes a view of the result into a Vec its own caller holds
// Control for agora #679: a result every path lends is no storage of the binding's own, so its view may outlive the binding.
// map: §2.7 | A2 | runs-clean | - | agora #679: a function that lends one of its two arguments on every call; the caller pushes a view of the result into a Vec its own caller holds
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ pick ( Vec S ) va S d b k → S {
    ? k { ^ d } {}
    ^ ( vec_at [S] va 0 )
}

@ g ( Vec S ) v S d b own ( Vec s ) outv → v {
    : S r ( pick v d own )
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
