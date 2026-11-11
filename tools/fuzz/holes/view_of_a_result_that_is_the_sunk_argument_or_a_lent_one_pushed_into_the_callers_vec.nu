// view_of_a_result_that_is_the_sunk_argument_or_a_lent_one_pushed_into_the_callers_vec: agora #679 — `pick2` hands back its `sink` argument or lends its other one; the caller binds the result of a call whose sunk argument is a fresh value and pushes a view of it into a Vec its own caller holds — freed with the binding when the sunk one came back
// Closed: a binding bound to a call whose arguments hold a nested call keeps `may own` where that call's lend began its borrow again, so the view is a view of a local.
// main a9be57b: accepted; heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #679: `pick2` hands back its `sink` argument or lends its other one; the caller binds the result of a call whose sunk argument is a fresh value and pushes a view of it into a Vec its own caller holds — freed with the binding when the sunk one came back
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
