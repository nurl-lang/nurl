// packages/recon-kit/src/voxel.nu — voxel fusion of the finished cloud.
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
//   ( vx_new size )                 → VxGrid
//   ( vx_add g x y z r gg b )       → v    one observation, accumulated
//   ( vx_write g ply )              → i    cells written
//
// The grid accumulates as the points arrive, so what it holds grows with
// the occupied cells, not with every observation of the same surface. A
// cell is keyed by its full integer coordinates — nothing is clamped, so
// two different cells never share a key — in an open-addressing table
// that doubles as it fills. A point whose cell index would not fit an
// integer (a non-finite coordinate, or a cell size absurdly small for the
// scene) is skipped and counted, never merged into a neighbour.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/float.nu`
$ `deps/ply/src/ply.nu`

: VxGrid {
    f size  // the cell edge, metres
    i cap  // table slots, a power of two
    i nvox  // occupied cells
    i skipped  // observations whose cell is out of integer range
    ( Vec i ) slot  // cap entries: 0 = empty, else 1 + cell index
    ( Vec i ) keys  // per cell: ix iy iz
    ( Vec f ) acc  // per cell: Σx Σy Σz Σr Σg Σb n
}

@ vx_new f size → VxGrid {
    ^ @ VxGrid { size 1024 0 0 ( vec_zeroed [i] 1024 ) ( vec_new [i] ) ( vec_new [f] ) }
}

// A cell index, or F past ±2^62 (and for NaN, which fails both tests).
@ __vx_cell f v f size → ?i {
    : f q ( float_floor / v size )
    ? & > q -4611686018427387904.0 < q 4611686018427387904.0 { ^ @ ?i { T # i q } } {}
    ^ @ ?i { F 0 }
}

// The hash looks at the low 20 bits of each coordinate (no overflow in the
// products); equality looks at all of them.
@ __vx_hash i ix i iy i iz i msk → i {
    ^ & ^^ ^^ * & ix 1048575 73856093 * & iy 1048575 19349663 * & iz 1048575 83492791 msk
}

// Re-seat every cell in a table twice the size.
@ __vx_grow inout VxGrid g → v {
    : i ncap * . g cap 2
    : i msk - ncap 1
    : ( Vec i ) ns__v ( vec_zeroed [i] ncap )
    : ( Slice i ) ns ( slice_from_vec [i] ns__v )
    : ( Slice i ) ks ( slice_from_vec [i] . g keys )
    : ~ i c 0
    ~ < c . g nvox {
        : ~ i h ( __vx_hash ( slice_at [i] ks * c 3 ) ( slice_at [i] ks + * c 3 1 ) ( slice_at [i] ks + * c 3 2 ) msk )
        ~ != ( slice_at [i] ns h ) 0 { = h & + h 1 msk }
        ( slice_put [i] ns h + c 1 )
        = c + c 1
    }
    = . g slot ns__v
    = . g cap ncap
}

@ vx_add inout VxGrid g f x f y f z i r i gg i b → v {
    : f size . g size
    : ?i cx ( __vx_cell x size )
    : ?i cy ( __vx_cell y size )
    : ?i cz ( __vx_cell z size )
    : ~ i ix 0
    : ~ i iy 0
    : ~ i iz 0
    : ~ b ok T
    ?? cx { T v → { = ix v } F → { = ok F } }
    ?? cy { T v → { = iy v } F → { = ok F } }
    ?? cz { T v → { = iz v } F → { = ok F } }
    ? ok {} {
        = . g skipped + . g skipped 1
        ^ v
    }
    ? > * + . g nvox 1 2 . g cap { ( __vx_grow g ) } {}
    : i msk - . g cap 1
    : ~ i h ( __vx_hash ix iy iz msk )
    : ~ i at -1
    ~ < at 0 {
        : i sv ( slice_at [i] ( slice_from_vec [i] . g slot ) h )
        ? == sv 0 {
            ( slice_put [i] ( slice_from_vec [i] . g slot ) h + . g nvox 1 )
            ( vec_push [i] . g keys ix ) ( vec_push [i] . g keys iy ) ( vec_push [i] . g keys iz )
            : ~ i e 0
            ~ < e 7 { ( vec_push [f] . g acc 0.0 ) = e + e 1 }
            = at . g nvox
            = . g nvox + . g nvox 1
        } {
            : ( Slice i ) ks ( slice_from_vec [i] . g keys )
            : i kb * - sv 1 3
            ? & & == ( slice_at [i] ks kb ) ix == ( slice_at [i] ks + kb 1 ) iy == ( slice_at [i] ks + kb 2 ) iz {
                = at - sv 1
            } { = h & + h 1 msk }
        }
    }
    : ( Slice f ) a ( slice_from_vec [f] . g acc )
    : i ab * at 7
    ( slice_put [f] a ab + ( slice_at [f] a ab ) x )
    ( slice_put [f] a + ab 1 + ( slice_at [f] a + ab 1 ) y )
    ( slice_put [f] a + ab 2 + ( slice_at [f] a + ab 2 ) z )
    ( slice_put [f] a + ab 3 + ( slice_at [f] a + ab 3 ) # f r )
    ( slice_put [f] a + ab 4 + ( slice_at [f] a + ab 4 ) # f gg )
    ( slice_put [f] a + ab 5 + ( slice_at [f] a + ab 5 ) # f b )
    ( slice_put [f] a + ab 6 + ( slice_at [f] a + ab 6 ) 1.0 )
}

@ vx_write VxGrid g PlyW ply → i {
    : ( Slice f ) a ( slice_from_vec [f] . g acc )
    : ~ i v 0
    ~ < v . g nvox {
        : i b * v 7
        : f m ( slice_at [f] a + b 6 )
        ( ply_vertex ply / ( slice_at [f] a b ) m / ( slice_at [f] a + b 1 ) m / ( slice_at [f] a + b 2 ) m
        # i + / ( slice_at [f] a + b 3 ) m 0.5 # i + / ( slice_at [f] a + b 4 ) m 0.5 # i + / ( slice_at [f] a + b 5 ) m 0.5 )
        = v + v 1
    }
    ^ . g nvox
}
