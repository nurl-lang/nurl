// packages/octree/tests/octree_test.nu — build octrees and check what a
// level-of-detail client and a tiler rely on.
//
//   nurl tests/octree_test.nu /tmp/oc && /tmp/oc

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/sort.nu`
$ `../src/octree.nu`

@ __fin f x → b { ^ & == 0 ( nurl_is_nan x ) == 0 ( nurl_is_inf x ) }

@ __say b ok s what → i {
    ? ok { ( nurl_print `PASS ` ) } { ( nurl_print `FAIL ` ) }
    ( nurl_print what ) ( nurl_print `\n` )
    ^ ? ok 0 1
}

// The properties, over one tree of `np` input points of which `nfin` are
// finite. Returns the number of failures.
@ __check Octree t ( Slice f ) xyz i nfin i cap i grid s name → i {
    : ~ i bad 0
    : i n ( oc_count t )
    : i np / ( slice_len [f] xyz ) 3
    // every finite point in exactly one node
    : ( Vec i ) seen__v ( vec_zeroed [i] np )
    : ( Slice i ) seen ( slice_from_vec [i] seen__v )
    : ~ i placed 0
    : ~ b inside T
    : ~ b order T
    : ~ b nested T
    : ~ b cells T
    : ~ b leaves T
    : ~ b halves T
    : ( Vec i ) kids__v ( vec_zeroed [i] n )
    : ( Slice i ) kids ( slice_from_vec [i] kids__v )
    : ~ i k 0
    ~ < k n {
        : i pa ( oc_parent t k )
        ? > k 0 {
            ? | < pa 0 >= pa k { = order F } {
                ( slice_put [i] kids pa + ( slice_at [i] kids pa ) 1 )
                ? > ( float_abs - * 2.0 ( oc_half t k ) ( oc_half t pa ) ) * 1.0e-9 ( oc_half t pa ) { = halves F } {}
                : ~ i a 0
                ~ < a 3 {
                    : f tol + * ( oc_half t pa ) 1.0e-6 * 1.0e-14 + 1.0 ( float_abs ( oc_center t pa a ) )
                    ? > + ( float_abs - ( oc_center t k a ) ( oc_center t pa a ) ) ( oc_half t k ) + ( oc_half t pa ) tol { = nested F } {}
                    = a + a 1
                }
            }
        } { ? != pa -1 { = order F } {} }
        = k + k 1
    }
    = k 0
    ~ < k n {
        : ( Slice i ) own ( oc_points t k )
        : f h ( oc_half t k )
        : f sp ( oc_spacing t k )
        // an inner node keeps at most one point per sampling cell
        : ( Vec i ) cellv ( vec_new [i] )
        : ~ i j 0
        ~ < j ( slice_len [i] own ) {
            : i p ( slice_at [i] own j )
            ( slice_put [i] seen p + ( slice_at [i] seen p ) 1 )
            = placed + placed 1
            : ~ i cell 0
            : ~ i a 0
            ~ < a 3 {
                : f v ( slice_at [f] xyz + * p 3 a )
                // float64 rounding of the centre, relative to the coordinates
                : f tol + * h 1.0e-9 * 1.0e-14 + 1.0 ( float_abs v )
                ? > - ( float_abs - v ( oc_center t k a ) ) h tol { = inside F } {}
                // the build's own cell rule, from (v - centre) / half
                : f u + * 0.5 / - v ( oc_center t k a ) h 0.5
                : ~ i c 0
                ? >= u 1.0 { = c - grid 1 } { ? > u 0.0 { = c # i ( float_floor * u # f grid ) } {} }
                = cell + * cell grid c
                = a + a 1
            }
            ( vec_push [i] cellv cell )
            = j + j 1
        }
        ? > ( slice_at [i] kids k ) 0 {
            ( sort_by [i] cellv \ i x i y → i { ^ ? < x y -1 ? > x y 1 0 } )
            : ( Slice i ) cs ( slice_from_vec [i] cellv )
            = j 1
            ~ < j ( slice_len [i] cs ) {
                ? == ( slice_at [i] cs j ) ( slice_at [i] cs - j 1 ) { = cells F } {}
                = j + j 1
            }
        } {
            // the build's own leaf rule: at the depth limit, or a cube too
            // small to halve at these coordinates, a leaf may hold more
            : b tiny <= h * 1.0e-12 + + + ( float_abs ( oc_center t k 0 ) ) ( float_abs ( oc_center t k 1 ) ) ( float_abs ( oc_center t k 2 ) ) 1.0
            ? & & > ( slice_len [i] own ) cap < ( oc_level t k ) OC_MAX_DEPTH ! tiny { = leaves F } {}
        }
        = k + k 1
    }
    : ~ b once T
    = k 0
    ~ < k np {
        : ~ b fin T
        : ~ i a 0
        ~ < a 3 {
            : f x ( slice_at [f] xyz + * k 3 a )
            ? | != 0 ( nurl_is_nan x ) != 0 ( nurl_is_inf x ) { = fin F } {}
            = a + a 1
        }
        ? fin { ? != ( slice_at [i] seen k ) 1 { = once F } {} } { ? != ( slice_at [i] seen k ) 0 { = once F } {} }
        = k + k 1
    }
    // tight bounds: exactly the subtree's extremes, computed the slow way
    : ~ b tight T
    = k 0
    ~ < k n {
        : ~ i a 0
        ~ < a 3 {
            : ~ f lo 1.0e308
            : ~ f hi -1.0e308
            : ~ i q 0
            ~ < q n {
                // q is in k's subtree when walking up from q reaches k
                : ~ i u q
                ~ & > u k >= u 0 { = u ( oc_parent t u ) }
                ? == u k {
                    : ( Slice i ) own ( oc_points t q )
                    : ~ i j 0
                    ~ < j ( slice_len [i] own ) {
                        : f v ( slice_at [f] xyz + * ( slice_at [i] own j ) 3 a )
                        ? < v lo { = lo v } {}
                        ? > v hi { = hi v } {}
                        = j + j 1
                    }
                } {}
                = q + q 1
            }
            ? | != lo ( oc_min t k a ) != hi ( oc_max t k a ) { = tight F } {}
            = a + a 1
        }
        = k + k 1
    }
    : String w ( string_from name )
    ( string_push_str w `: ` )
    ( string_push_int w n )
    ( string_push_str w ` nodes, ` )
    ( string_push_int w placed )
    ( string_push_str w ` points placed` )
    = bad + bad ( __say & == placed nfin once ( string_data w ) )
    = bad + bad ( __say order `  parents come before their children` )
    = bad + bad ( __say & nested halves `  a child's cube is a half-size octant of its parent's` )
    = bad + bad ( __say inside `  every point lies in its node's cube` )
    = bad + bad ( __say cells `  an inner node keeps at most one point per sampling cell` )
    = bad + bad ( __say leaves `  a leaf holds at most the capacity (below the depth limit)` )
    = bad + bad ( __say tight `  tight bounds are the subtree's exact extremes` )
    ^ bad
}

@ main → i {
    : ~ i bad 0
    // 60 000 points: a noisy terrain plus a dense blob, and three that are not finite
    : Rng g ( rng_seed 7 )
    : ( Vec f ) a__v ( vec_new [f] )
    : ~ i k 0
    ~ < k 50000 {
        : f x * 100.0 ( rng_u01 g )
        : f y * 100.0 ( rng_u01 g )
        ( vec_push [f] a__v x ) ( vec_push [f] a__v y )
        ( vec_push [f] a__v + * 3.0 ( float_sin * 0.1 x ) ( rng_u01 g ) )
        = k + k 1
    }
    ~ < k 60000 {
        ( vec_push [f] a__v + 50.0 ( rng_u01 g ) ) ( vec_push [f] a__v + 50.0 ( rng_u01 g ) ) ( vec_push [f] a__v + 2.0 ( rng_u01 g ) )
        = k + k 1
    }
    : f nan / 0.0 0.0
    ( vec_push [f] a__v nan ) ( vec_push [f] a__v 1.0 ) ( vec_push [f] a__v 1.0 )
    ( vec_push [f] a__v 1.0 ) ( vec_push [f] a__v / 1.0 0.0 ) ( vec_push [f] a__v 1.0 )
    ( vec_push [f] a__v 1.0 ) ( vec_push [f] a__v 1.0 ) ( vec_push [f] a__v nan )
    : ( Slice f ) a ( slice_from_vec [f] a__v )
    : Octree t ( oc_build a 2000 16 42 )
    = bad + bad ( __check t a 60000 2000 16 `terrain` )
    = bad + bad ( __say == ( oc_dropped t ) 3 `  the three non-finite points are dropped, and counted` )
    // the same seed builds the same tree; another seed another sample
    : Octree t2 ( oc_build a 2000 16 42 )
    : Octree t3 ( oc_build a 2000 16 43 )
    : ( Slice i ) r1 ( oc_points t 0 )
    : ( Slice i ) r2 ( oc_points t2 0 )
    : ( Slice i ) r3 ( oc_points t3 0 )
    : ~ b same == ( slice_len [i] r1 ) ( slice_len [i] r2 )
    : ~ b differ F
    = k 0
    ~ & same < k ( slice_len [i] r1 ) {
        ? != ( slice_at [i] r1 k ) ( slice_at [i] r2 k ) { = same F } {}
        ? & < k ( slice_len [i] r3 ) != ( slice_at [i] r1 k ) ( slice_at [i] r3 k ) { = differ T } {}
        = k + k 1
    }
    = bad + bad ( __say & & same differ == ( oc_count t ) ( oc_count t2 ) `the same seed builds the same tree; another seed samples differently` )
    // the root's sample is even: its points spread over the terrain, not
    // bunched where the input began (the first 2000 input points are one
    // corner's worth if the shuffle were missing)
    : ~ f sx 0.0
    = k 0
    ~ < k ( slice_len [i] r1 ) { = sx + sx ( slice_at [f] a * ( slice_at [i] r1 k ) 3 ) = k + k 1 }
    : f mean / sx # f ( slice_len [i] r1 )
    = bad + bad ( __say & > mean 35.0 < mean 65.0 `the root's sample is spread evenly (mean x near the middle)` )
    // 6 000 copies of one point: the depth limit ends it
    : ( Vec f ) d__v ( vec_new [f] )
    = k 0
    ~ < k 6000 { ( vec_push [f] d__v 3.0 ) ( vec_push [f] d__v 3.0 ) ( vec_push [f] d__v 3.0 ) = k + k 1 }
    : ( Slice f ) d ( slice_from_vec [f] d__v )
    : Octree td ( oc_build d 1000 8 1 )
    = bad + bad ( __check td d 6000 1000 8 `one point 6000 times` )
    = bad + bad ( __say < ( oc_count td ) OC_MAX_DEPTH `  ...and stops once the cube is too small to halve, before the depth limit` )
    // far from the origin (a georeferenced survey): the same, a million metres out
    : ( Vec f ) far__v ( vec_new [f] )
    = k 0
    ~ < k 3000 {
        ( vec_push [f] far__v + 6700000.0 * 0.001 ( rng_u01 g ) ) ( vec_push [f] far__v + 3400000.0 * 0.001 ( rng_u01 g ) ) ( vec_push [f] far__v 120.0 )
        = k + k 1
    }
    : ( Slice f ) far ( slice_from_vec [f] far__v )
    : Octree tf ( oc_build far 100 8 1 )
    = bad + bad ( __check tf far 3000 100 8 `3000 points within a millimetre, 6700 km out` )
    = bad + bad ( __say > ( oc_count tf ) 1 `  ...still divided into nodes` )
    // at float64's limit: 1e308 + 1e308 is infinite, the build must not add them
    : ( Vec f ) x__v ( vec_new [f] )
    = k 0
    ~ < k 400 {
        : f sgn ? == 0 % k 2 1.0 -1.0
        ( vec_push [f] x__v * sgn * 1.0e308 ( rng_u01 g ) ) ( vec_push [f] x__v * -1.0e308 ( rng_u01 g ) ) ( vec_push [f] x__v * 1.0e308 ( rng_u01 g ) )
        = k + k 1
    }
    ( vec_push [f] x__v 1.7e308 ) ( vec_push [f] x__v -1.7e308 ) ( vec_push [f] x__v 1.0 )
    ( vec_push [f] x__v -1.7e308 ) ( vec_push [f] x__v 1.7e308 ) ( vec_push [f] x__v -1.0 )
    : ( Slice f ) xs ( slice_from_vec [f] x__v )
    : Octree tx ( oc_build xs 50 8 1 )
    = bad + bad ( __check tx xs 402 50 8 `402 points out to 1.7e308` )
    = bad + bad ( __say & ( __fin ( oc_center tx 0 0 ) ) ( __fin ( oc_half tx 0 ) ) `  ...the root's cube is finite` )
    : ( Vec f ) e__v ( vec_new [f] )
    : Octree te ( oc_build ( slice_from_vec [f] e__v ) 10 8 1 )
    = bad + bad ( __say == ( oc_count te ) 0 `no points, no nodes` )
    ^ ? == bad 0 0 1
}
