// vec_foreach.nu — `~ x xs { ... }` over a ( Vec T ).
//
// Until 2026-05-24 gen_foreach assumed slice layout `{ T*, i64 }`
// and miscompiled Vec iteration with an OOB extractvalue + empty-
// type getelementptr; the IR was rejected by clang. This test
// exercises the Vec branch added to gen_foreach so the regression
// cannot re-land silently.

$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 3 )
    ( vec_push [i] xs 7 )
    ( vec_push [i] xs 11 )
    ( vec_push [i] xs 17 )

    : ~ i sum 0
    ~ x xs {
        = sum + sum x
    }

    ( nurl_print `sum=` )
    ( nurl_print ( nurl_str_int sum ) )
    ( nurl_print `\n` )

    // Independent control: an `f` Vec also iterates cleanly — exercises
    // the demangle_type path for `%Vec__f64` rather than `%Vec__i64`.
    : ( Vec f ) ys ( vec_new [f] )
    ( vec_push [f] ys 0.5 )
    ( vec_push [f] ys 1.5 )
    ( vec_push [f] ys 2.0 )

    : ~ f total 0.0
    ~ y ys {
        = total + total y
    }
    : i total_int # i total
    ( nurl_print `total_int=` )
    ( nurl_print ( nurl_str_int total_int ) )
    ( nurl_print `\n` )

    ( vec_free [i] xs )
    ( vec_free [f] ys )
    ^ 0
}
