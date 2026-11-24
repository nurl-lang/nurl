// packages/octree/src/octree.nu — an octree over points, each node holding
// an even sample of what falls in it: the structure behind level of detail
// for big point clouds (Potree, 3D Tiles point tilesets) and a spatial index.
//
//   ( oc_build xyz capacity grid seed )      → Octree   xyz: 3 numbers a point
//   ( oc_count t )                           → i        nodes
//   ( oc_parent t k ) ( oc_level t k )       → i        -1 for the root's parent
//   ( oc_points t k )                        → ( Slice i ) the node's own points
//   ( oc_center t k axis ) ( oc_half t k )   → f        the node's cube
//   ( oc_min t k axis ) ( oc_max t k axis )  → f        tight bounds of its subtree
//   ( oc_spacing t k )                       → f        its sampling cell's size
//   ( oc_used t ) ( oc_dropped t )           → i        points placed / not finite
//
// How a node is filled. The root's cube encloses every point. A node lays a
// grid of grid^3 cells over its cube and keeps the first point to land in
// each empty cell; what is left goes down to the eight children (one per
// octant that has any), whose cubes are half the size, so their cells are
// too. A node with at most `capacity` candidates keeps them all and is a
// leaf. Every point ends in exactly one node, so a node together with its
// ancestors is a sample of its region at that node's spacing — drawing a
// node adds detail to what its ancestors drew (3D Tiles' ADD refinement).
// The points are visited in a shuffled order (seeded, so a build is
// repeatable): "the first to land in a cell" is then a random one, and the
// sample is even rather than biased to the input's write order.
//
// A node is a leaf when it has at most `capacity` candidates, at depth
// OC_MAX_DEPTH, or when its cube is too small to halve at its coordinates
// (1e-12 of their size, four digits above float64's resolution): one
// point copied many times stops there.
//
// Nodes are numbered breadth first: every parent before its children, and
// a node's children consecutive. Memory: a few integers a point, plus one
// stamp per grid cell (grid 128 is 2 M cells, 16 MB).

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/rng.nu`

: i OC_MAX_DEPTH 24

: Octree {
    ( Vec i ) order  // point indices, grouped node by node
    ( Vec i ) start  // per node: where its points begin in `order`
    ( Vec i ) count  // per node: how many
    ( Vec i ) parent
    ( Vec i ) level
    ( Vec f ) cube  // 4 per node: centre x y z, half size
    ( Vec f ) tight  // 6 per node: min x y z, max x y z of its subtree
    i grid
    i dropped
}

@ oc_count Octree t → i { ^ ( vec_len [i] . t start ) }

@ oc_parent Octree t i k → i { ^ ( slice_at [i] ( slice_from_vec [i] . t parent ) k ) }

@ oc_level Octree t i k → i { ^ ( slice_at [i] ( slice_from_vec [i] . t level ) k ) }

@ oc_center Octree t i k i axis → f { ^ ( slice_at [f] ( slice_from_vec [f] . t cube ) + * k 4 axis ) }

@ oc_half Octree t i k → f { ^ ( slice_at [f] ( slice_from_vec [f] . t cube ) + * k 4 3 ) }

@ oc_min Octree t i k i axis → f { ^ ( slice_at [f] ( slice_from_vec [f] . t tight ) + * k 6 axis ) }

@ oc_max Octree t i k i axis → f { ^ ( slice_at [f] ( slice_from_vec [f] . t tight ) + + * k 6 3 axis ) }

@ oc_spacing Octree t i k → f { ^ / * 2.0 ( oc_half t k ) # f . t grid }

@ oc_used Octree t → i { ^ ( vec_len [i] . t order ) }

@ oc_dropped Octree t → i { ^ . t dropped }

@ oc_points Octree t i k → ( Slice i ) {
    : i s ( slice_at [i] ( slice_from_vec [i] . t start ) k )
    : i n ( slice_at [i] ( slice_from_vec [i] . t count ) k )
    ^ ( slice_window [i] ( slice_from_vec [i] . t order ) s n )
}

@ __oc_fin f x → b { ^ & == 0 ( nurl_is_nan x ) == 0 ( nurl_is_inf x ) }

@ __oc_max f a f b → f { ^ ? > a b a b }

// infinity, the bounds' starting point: any finite value replaces it
@ __oc_inf → f { ^ / 1.0 0.0 }

// The cell of v along one axis of a cube (centre c, half size h), from
// (v - c) / h: v lies within h of c, so nothing here can overflow even for
// coordinates near float64's limit.
@ __oc_cell f v f c f h i grid → i {
    : f u + * 0.5 / - v c h 0.5
    ? | != 0 ( nurl_is_nan u ) < u 0.0 { ^ 0 } {}
    ? >= u 1.0 { ^ - grid 1 } {}
    : i cell # i ( float_floor * u # f grid )
    ? < cell 0 { ^ 0 } {}
    ? >= cell grid { ^ - grid 1 } {}
    ^ cell
}

@ __oc_node inout Octree t i parent i level f cx f cy f cz f h → i {
    : i k ( oc_count t )
    ( vec_push [i] . t start 0 ) ( vec_push [i] . t count 0 )
    ( vec_push [i] . t parent parent ) ( vec_push [i] . t level level )
    ( vec_push [f] . t cube cx ) ( vec_push [f] . t cube cy ) ( vec_push [f] . t cube cz ) ( vec_push [f] . t cube h )
    : ~ i a 0
    ~ < a 3 { ( vec_push [f] . t tight ( __oc_inf ) ) = a + a 1 }
    = a 0
    ~ < a 3 { ( vec_push [f] . t tight - 0.0 ( __oc_inf ) ) = a + a 1 }
    ^ k
}

@ oc_build ( Slice f ) xyz i capacity i grid i seed → Octree {
    : i g ? < grid 1 1 grid
    : i cap ? < capacity 1 1 capacity
    : ~ Octree t @ Octree { ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
        ( vec_new [f] ) ( vec_new [f] ) g 0 }
    : i np / ( slice_len [f] xyz ) 3
    // the candidates: the finite points, shuffled
    : ( Vec i ) cand__v ( vec_with_cap [i] np )
    : ~ f lx ( __oc_inf )
    : ~ f ly ( __oc_inf )
    : ~ f lz ( __oc_inf )
    : ~ f hx - 0.0 ( __oc_inf )
    : ~ f hy - 0.0 ( __oc_inf )
    : ~ f hz - 0.0 ( __oc_inf )
    : ~ i p 0
    ~ < p np {
        : f x ( slice_at [f] xyz * p 3 )
        : f y ( slice_at [f] xyz + * p 3 1 )
        : f z ( slice_at [f] xyz + * p 3 2 )
        ? & & ( __oc_fin x ) ( __oc_fin y ) ( __oc_fin z ) {
            ( vec_push [i] cand__v p )
            ? < x lx { = lx x } {}
            ? < y ly { = ly y } {}
            ? < z lz { = lz z } {}
            ? > x hx { = hx x } {}
            ? > y hy { = hy y } {}
            ? > z hz { = hz z } {}
        } { = . t dropped + . t dropped 1 }
        = p + p 1
    }
    : i nc ( vec_len [i] cand__v )
    ? == nc 0 { ^ t } {}
    : ( Slice i ) cand ( slice_from_vec [i] cand__v )
    : Rng g0 ( rng_seed seed )
    : ~ i q - nc 1
    ~ > q 0 {
        : i r ( rng_below g0 + q 1 )
        : i tmp ( slice_at [i] cand q )
        ( slice_put [i] cand q ( slice_at [i] cand r ) )
        ( slice_put [i] cand r tmp )
        = q - q 1
    }
    // the root: a cube around everything, a hair larger so no point sits
    // exactly on its far faces
    // half extents and centres from halves, so neither overflows for
    // coordinates near float64's limit (1e308 + 1e308 is infinite)
    : f ex ( __oc_max - * 0.5 hx * 0.5 lx ( __oc_max - * 0.5 hy * 0.5 ly - * 0.5 hz * 0.5 lz ) )
    // the smallest cube is one the coordinates can still tell apart: far
    // from the origin (georeferenced data) a micrometre nears float64's
    // resolution
    : f mag ( __oc_max ( __oc_max ( float_abs lx ) ( float_abs hx ) ) ( __oc_max ( __oc_max ( float_abs ly ) ( float_abs hy ) ) ( __oc_max ( float_abs lz ) ( float_abs hz ) ) ) )
    : f hmin ( __oc_max 0.000001 * mag 0.000000000001 )
    : f h0 ( __oc_max * ex 1.0000002 hmin )
    : i _root ( __oc_node t -1 0 + * 0.5 lx * 0.5 hx + * 0.5 ly * 0.5 hy + * 0.5 lz * 0.5 hz h0 )
    // per node: its candidates' range in `cand`; children get sub-ranges
    : ( Vec i ) cs__v ( vec_new [i] )
    : ( Vec i ) cc__v ( vec_new [i] )
    ( vec_push [i] cs__v 0 ) ( vec_push [i] cc__v nc )
    : ( Vec i ) stamp__v ( vec_zeroed [i] * * g g g )
    : ( Slice i ) stamp ( slice_from_vec [i] stamp__v )
    : ( Vec i ) rest__v ( vec_zeroed [i] nc )
    : ( Slice i ) rest ( slice_from_vec [i] rest__v )
    : ( Vec u ) oct__v ( vec_zeroed [u] nc )
    : ( Slice u ) oct ( slice_from_vec [u] oct__v )
    : ( Vec i ) obuck__v ( vec_zeroed [i] 9 )
    : ( Slice i ) obuck ( slice_from_vec [i] obuck__v )
    : ~ i k 0
    ~ < k ( oc_count t ) {
        : i c0 ( slice_at [i] ( slice_from_vec [i] cs__v ) k )
        : i cn ( slice_at [i] ( slice_from_vec [i] cc__v ) k )
        : i lev ( oc_level t k )
        : f cx ( oc_center t k 0 )
        : f cy ( oc_center t k 1 )
        : f cz ( oc_center t k 2 )
        : f h ( oc_half t k )
        : b _s ( vec_set [i] . t start k ( vec_len [i] . t order ) )
        : ~ i kept 0
        : ~ i nrest 0
        // a leaf: few enough points, deep enough, or a cube too small to
        // halve at these coordinates (one point copied many times ends here)
        : b tiny <= h * 0.000000000001 + ( __oc_max ( float_abs cx ) ( __oc_max ( float_abs cy ) ( float_abs cz ) ) ) 1.0
        ? | | <= cn cap >= lev OC_MAX_DEPTH tiny {
            : ~ i j 0
            ~ < j cn { ( vec_push [i] . t order ( slice_at [i] cand + c0 j ) ) = j + j 1 }
            = kept cn
        } {
            : i mark + k 1
            : ~ i j 0
            ~ < j cn {
                : i pi ( slice_at [i] cand + c0 j )
                : f x ( slice_at [f] xyz * pi 3 )
                : f y ( slice_at [f] xyz + * pi 3 1 )
                : f z ( slice_at [f] xyz + * pi 3 2 )
                : i cell + ( __oc_cell x cx h g ) * g + ( __oc_cell y cy h g ) * g ( __oc_cell z cz h g )
                ? != ( slice_at [i] stamp cell ) mark {
                    ( slice_put [i] stamp cell mark )
                    ( vec_push [i] . t order pi )
                    = kept + kept 1
                } {
                    ( slice_put [i] rest nrest pi )
                    : i o + + ? >= x cx 1 0 ? >= y cy 2 0 ? >= z cz 4 0
                    ( slice_put [u] oct nrest # u o )
                    = nrest + nrest 1
                }
                = j + j 1
            }
            // the rest back into this node's range, octant by octant
            : ~ i o 0
            ~ < o 9 { ( slice_put [i] obuck o 0 ) = o + o 1 }
            = j 0
            ~ < j nrest {
                : i oo # i ( slice_at [u] oct j )
                ( slice_put [i] obuck + oo 1 + ( slice_at [i] obuck + oo 1 ) 1 )
                = j + j 1
            }
            = o 0
            ~ < o 8 { ( slice_put [i] obuck + o 1 + ( slice_at [i] obuck + o 1 ) ( slice_at [i] obuck o ) ) = o + o 1 }
            // obuck[o] is now where octant o starts; place, then re-derive
            = j 0
            ~ < j nrest {
                : i oo # i ( slice_at [u] oct j )
                : i at ( slice_at [i] obuck oo )
                ( slice_put [i] cand + c0 at ( slice_at [i] rest j ) )
                ( slice_put [i] obuck oo + at 1 )
                = j + j 1
            }
            // obuck[o] is now where octant o ends: its start is the one before
            : ~ i from 0
            = o 0
            ~ < o 8 {
                : i upto ( slice_at [i] obuck o )
                ? > upto from {
                    : f q2 * h 0.5
                    : f ox ? == 1 & o 1 + cx q2 - cx q2
                    : f oy ? == 2 & o 2 + cy q2 - cy q2
                    : f oz ? == 4 & o 4 + cz q2 - cz q2
                    : i _c ( __oc_node t k + lev 1 ox oy oz q2 )
                    ( vec_push [i] cs__v + c0 from ) ( vec_push [i] cc__v - upto from )
                } {}
                = from upto
                = o + o 1
            }
        }
        : b _n ( vec_set [i] . t count k kept )
        = k + k 1
    }
    // tight bounds: each node's own points, then children into parents
    : ( Slice f ) tb ( slice_from_vec [f] . t tight )
    = k 0
    ~ < k ( oc_count t ) {
        : ( Slice i ) own ( oc_points t k )
        : ~ i j 0
        ~ < j ( slice_len [i] own ) {
            : i pi ( slice_at [i] own j )
            : ~ i a 0
            ~ < a 3 {
                : f v ( slice_at [f] xyz + * pi 3 a )
                ? < v ( slice_at [f] tb + * k 6 a ) { ( slice_put [f] tb + * k 6 a v ) } {}
                ? > v ( slice_at [f] tb + + * k 6 3 a ) { ( slice_put [f] tb + + * k 6 3 a v ) } {}
                = a + a 1
            }
            = j + j 1
        }
        = k + k 1
    }
    = k - ( oc_count t ) 1
    ~ > k 0 {
        : i pa ( oc_parent t k )
        : ~ i a 0
        ~ < a 3 {
            ? < ( slice_at [f] tb + * k 6 a ) ( slice_at [f] tb + * pa 6 a ) { ( slice_put [f] tb + * pa 6 a ( slice_at [f] tb + * k 6 a ) ) } {}
            ? > ( slice_at [f] tb + + * k 6 3 a ) ( slice_at [f] tb + + * pa 6 3 a ) { ( slice_put [f] tb + + * pa 6 3 a ( slice_at [f] tb + + * k 6 3 a ) ) } {}
            = a + a 1
        }
        = k - k 1
    }
    ^ t
}
