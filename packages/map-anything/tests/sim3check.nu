// tests/sim3check.nu — gm_sim3_fit against a known transform.
//
// Synthesises a point set, applies a known Sim(3) (+ optional noise),
// recovers it, and checks both the parameters and the point residual.
// Self-contained (no oracle): the ground truth is the transform itself.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/geom.nu`

: ~ i __s3_fails 0

@ __s3_check b ok s what → v {
    : String m ( string_from ? ok `ok   ` `FAIL ` )
    ( string_push_str m what )
    ( puts ( string_data m ) )
    ? ok {} { = __s3_fails + __s3_fails 1 }
}

unsafe

@ __s3_case f s f ax f ay f az f angle f tx f ty f tz f noise s label → v {
    : i n 500
    // unit axis + quaternion for the ground-truth rotation
    : f al ( float_sqrt + + * ax ax * ay ay * az az )
    : f ux / ax al
    : f uy / ay al
    : f uz / az al
    : f half * angle 0.5
    : f sw ( float_sin half )
    : ( Vec u ) r__v ( vec_zeroed [u] 72 )
    : *f r # *f ( vec_data [u] r__v )
    ( gm_quat_to_mat * ux sw * uy sw * uz sw ( float_cos half ) r )
    : ( Vec u ) xs__v ( vec_zeroed [u] * 24 n )
    : *f xs # *f ( vec_data [u] xs__v )
    : ( Vec u ) ys__v ( vec_zeroed [u] * 24 n )
    : *f ys # *f ( vec_data [u] ys__v )
    : ~ i j 0
    ~ < j n {
        // a deterministic pseudo-random cloud with real 3-D spread
        : f x0 - / # f % * j 37 251 251.0 0.5
        : f x1 - / # f % * j 73 251 251.0 0.5
        : f x2 - / # f % * j 113 251 251.0 0.5
        = . xs * j 3 x0
        = . xs + * j 3 1 x1
        = . xs + * j 3 2 x2
        : f nz * noise - / # f % * j 151 251 251.0 0.5
        = . ys * j 3 + + * s + + * . r 0 x0 * . r 1 x1 * . r 2 x2 tx nz
        = . ys + * j 3 1 + + * s + + * . r 3 x0 * . r 4 x1 * . r 5 x2 ty nz
        = . ys + * j 3 2 + + * s + + * . r 6 x0 * . r 7 x1 * . r 8 x2 tz nz
        = j + j 1
    }
    : ( Vec u ) xf__v ( vec_zeroed [u] 104 )
    : *f xf # *f ( vec_data [u] xf__v )
    : b fitok ( gm_sim3_fit xs ys n xf )
    ( __s3_check fitok label )
    ? fitok {
        // residual after applying the fit
        ( gm_sim3_apply xs n xf )
        : ~ f worst 0.0
        = j 0
        ~ < j n {
            : ~ i c 0
            ~ < c 3 {
                : f d ( float_abs - . xs + * j 3 c . ys + * j 3 c )
                ? > d worst { = worst d } {}
                = c + c 1
            }
            = j + j 1
        }
        : f gate ? > noise 0.0 * noise 4.0 0.000001
        : String m ( string_from `  residual ` )
        ( string_push_float m worst )
        ( puts ( string_data m ) )
        ( __s3_check < worst gate label )
    } {}
}

@ main → i {
    ( __s3_case 1.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 `identity` )
    ( __s3_case 2.5 0.3 -0.7 0.5 1.1 4.0 -2.0 9.0 0.0 `scale+rot+trans, exact` )
    ( __s3_case 0.4 1.0 0.2 -0.9 2.7 -3.0 0.5 1.5 0.0 `shrink+big-rot, exact` )
    ( __s3_case 1.7 -0.2 0.9 0.1 0.6 10.0 20.0 -5.0 0.01 `with noise` )
    ? == __s3_fails 0 { ( puts `sim3check: all ok` ) ^ 0 } {}
    ( puts `sim3check: FAILURES` )
    ^ 1
}
