// packages/map-anything/src/voxel.nu — voxel fusion of the finished cloud.
//
// Every view contributes a point per pixel, so a surface seen by twenty
// views is twenty slightly different copies of itself: a thick, noisy
// shell, and a file whose size grows with the number of views rather than
// with the scene. Fusing on a metric voxel grid (the scale is metric, so
// the size is in metres) keeps one point per occupied cell, at the mean
// position and mean colour of what fell in it. Averaging n samples cuts
// their scatter by √n, near-duplicate layers closer than a cell collapse
// into one, and the cloud's density becomes uniform — which is also what
// makes a phone able to download and orbit it.
//
//   ( vx_merge xyz col size ply ) → i    points written
//
// `xyz` is [n, 3] interleaved, `col` [n] packed 0xRRGGBB.
//
// The table is open addressing over packed integer cell keys, no closures:
// a few million inserts are a fraction of a second.

$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/ply/src/ply.nu`

: i VX_OFF 524288  // 2^19 cells either side of the origin per axis (5 km at 1 cm)
: i VX_SPAN 1048576  // 2^20, so a packed key stays below 2^60

@ __vx_cell f v f size → i {
    : i c + # i ( float_floor / v size ) VX_OFF
    ? < c 0 { ^ 0 } {}
    ? >= c VX_SPAN { ^ - VX_SPAN 1 } {}
    ^ c
}

@ vx_merge ( Vec f ) xyz ( Vec i ) col f size PlyW ply → i {
    : i n ( vec_len [i] col )
    : ~ i cap 16
    ~ < cap * 2 n { = cap * cap 2 }
    : i msk - cap 1
    // slot → 1 + accumulator index (0 = empty), and the key in the slot
    : ( Vec i ) slot__v ( vec_zeroed [i] cap )
    : ( Slice i ) slot ( slice_from_vec [i] slot__v )
    : ( Vec i ) skey__v ( vec_zeroed [i] cap )
    : ( Slice i ) skey ( slice_from_vec [i] skey__v )
    : ( Vec f ) acc ( vec_new [f] )  // per voxel: x y z r g b count
    : ( Slice f ) pts ( slice_from_vec [f] xyz )
    : ( Slice i ) cs ( slice_from_vec [i] col )
    : ~ i nvox 0
    : ~ i k 0
    ~ < k n {
        : f x ( slice_at [f] pts * k 3 )
        : f y ( slice_at [f] pts + * k 3 1 )
        : f z ( slice_at [f] pts + * k 3 2 )
        : i ix ( __vx_cell x size )
        : i iy ( __vx_cell y size )
        : i iz ( __vx_cell z size )
        : i key + * + * ix VX_SPAN iy VX_SPAN iz
        : ~ i h & ^^ ^^ * ix 73856093 * iy 19349663 * iz 83492791 msk
        : ~ i at -1
        ~ < at 0 {
            : i sv ( slice_at [i] slot h )
            ? == sv 0 {
                ( slice_put [i] slot h + nvox 1 )
                ( slice_put [i] skey h key )
                ( vec_push [f] acc 0.0 ) ( vec_push [f] acc 0.0 ) ( vec_push [f] acc 0.0 )
                ( vec_push [f] acc 0.0 ) ( vec_push [f] acc 0.0 ) ( vec_push [f] acc 0.0 )
                ( vec_push [f] acc 0.0 )
                = at nvox
                = nvox + nvox 1
            } {
                ? == ( slice_at [i] skey h ) key { = at - sv 1 } { = h & + h 1 msk }
            }
        }
        : i c ( slice_at [i] cs k )
        : ( Slice f ) a ( slice_from_vec [f] acc )
        : i b * at 7
        ( slice_put [f] a b + ( slice_at [f] a b ) x )
        ( slice_put [f] a + b 1 + ( slice_at [f] a + b 1 ) y )
        ( slice_put [f] a + b 2 + ( slice_at [f] a + b 2 ) z )
        ( slice_put [f] a + b 3 + ( slice_at [f] a + b 3 ) # f & / c 65536 255 )
        ( slice_put [f] a + b 4 + ( slice_at [f] a + b 4 ) # f & / c 256 255 )
        ( slice_put [f] a + b 5 + ( slice_at [f] a + b 5 ) # f & c 255 )
        ( slice_put [f] a + b 6 + ( slice_at [f] a + b 6 ) 1.0 )
        = k + k 1
    }
    : ( Slice f ) a ( slice_from_vec [f] acc )
    : ~ i v 0
    ~ < v nvox {
        : i b * v 7
        : f m ( slice_at [f] a + b 6 )
        ( ply_vertex ply / ( slice_at [f] a b ) m / ( slice_at [f] a + b 1 ) m / ( slice_at [f] a + b 2 ) m
        # i + / ( slice_at [f] a + b 3 ) m 0.5 # i + / ( slice_at [f] a + b 4 ) m 0.5 # i + / ( slice_at [f] a + b 5 ) m 0.5 )
        = v + v 1
    }
    ^ nvox
}
