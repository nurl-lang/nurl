// packages/tiles3d/src/tiles3d.nu — OGC 3D Tiles 1.1 tilesets (tileset.json).
//
// 3D Tiles is how large 3-D data streams: a tree of tiles, each with a
// bounding volume, a geometric error (how wrong the scene looks, in metres,
// if this tile is drawn and its children are not) and optionally content —
// a glTF file in 1.1. A client walks the tree and loads only the tiles
// whose error would show on screen. CesiumJS reads it, and so do Cesium
// for Unreal and Cesium for Unity, which stream it into a game engine.
//
// This file is the format only: it builds the tree and writes the JSON. What
// goes into the tiles (points, meshes) and how the space is divided is the
// caller's business.
//
//   ( ts_new gerr )                                   → Tileset
//   ( ts_tile t parent cx cy cz hx hy hz gerr )      → i   the new tile's index
//   ( ts_content t tile uri )                         → v
//   ( ts_refine t tile TS_ADD | TS_REPLACE )          → v
//   ( ts_transform t tile m )                         → v   16 numbers, column-major
//   ( ts_count t )                                    → i
//   ( ts_json t )                                     → !String String
//   ( ts_write t path )                               → !v String
//
// The first tile is the root (parent -1); every other tile names a parent
// made before it, so the tiles always form one tree. Boxes are axis-aligned
// in the tileset's frame (its centre and half sizes). Before anything is
// written, ts_json checks the rules the specification states:
//   - one root, and every parent exists;
//   - the root says how it refines (ADD: children add to it, REPLACE:
//     children replace it); other tiles inherit unless they say otherwise;
//   - no tile's geometric error is above its parent's, and the tileset's
//     own error is at least the root's;
//   - every number is finite, errors and half sizes are not negative;
//   - a transform is affine (bottom row 0 0 0 1);
//   - a content uri is not empty.
//
// Frames: a tileset is z-up. glTF content is y-up, and clients turn it to
// z-up as they load it (+90 degrees about x). A point (x, y, z) of the
// tileset therefore goes into a glTF tile as (x, z, -y).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/json.nu`

: i TS_INHERIT 0
: i TS_ADD 1
: i TS_REPLACE 2

// One tile per index across the vectors.
: Tileset {
    f gerr  // the tileset's geometric error: the error with nothing drawn
    ( Vec i ) parent  // -1 for the root
    ( Vec f ) box  // 6 per tile: centre x y z, half size x y z
    ( Vec f ) err  // geometric error per tile
    ( Vec i ) refine  // TS_INHERIT / TS_ADD / TS_REPLACE
    ( Vec String ) uri  // content, or empty
    ( Vec f ) xf  // 16 per tile (column-major), meaningful when has_xf
    ( Vec i ) has_xf
}

@ ts_new f gerr → Tileset {
    ^ @ Tileset { gerr ( vec_new [i] ) ( vec_new [f] ) ( vec_new [f] ) ( vec_new [i] ) ( vec_new [String] )
        ( vec_new [f] ) ( vec_new [i] ) }
}

@ ts_count Tileset t → i { ^ ( vec_len [i] . t parent ) }

@ ts_tile inout Tileset t i parent f cx f cy f cz f hx f hy f hz f gerr → i {
    : i n ( ts_count t )
    ( vec_push [i] . t parent parent )
    ( vec_push [f] . t box cx ) ( vec_push [f] . t box cy ) ( vec_push [f] . t box cz )
    ( vec_push [f] . t box hx ) ( vec_push [f] . t box hy ) ( vec_push [f] . t box hz )
    ( vec_push [f] . t err gerr )
    ( vec_push [i] . t refine TS_INHERIT )
    ( vec_push [String] . t uri ( string_new ) )
    : ~ i k 0
    ~ < k 16 { ( vec_push [f] . t xf 0.0 ) = k + k 1 }
    ( vec_push [i] . t has_xf 0 )
    ^ n
}

// Setters on a tile that does not exist do nothing: ts_json then reports
// nothing wrong about a call that never took effect, so they are checked
// by the caller's own count (ts_count).
@ ts_content inout Tileset t i tile s uri → v {
    ? | < tile 0 >= tile ( ts_count t ) { ^ } {}
    : b _s ( vec_set [String] . t uri tile ( string_from uri ) )
}

@ ts_refine inout Tileset t i tile i mode → v {
    ? | < tile 0 >= tile ( ts_count t ) { ^ } {}
    : b _s ( vec_set [i] . t refine tile mode )
}

@ ts_transform inout Tileset t i tile ( Slice f ) m → v {
    ? | | < tile 0 >= tile ( ts_count t ) != ( slice_len [f] m ) 16 { ^ } {}
    : ~ i k 0
    ~ < k 16 {
        : b _s ( vec_set [f] . t xf + * tile 16 k ( slice_at [f] m k ) )
        = k + k 1
    }
    : b _h ( vec_set [i] . t has_xf tile 1 )
}

@ __ts_fin f x → b { ^ & == 0 ( nurl_is_nan x ) == 0 ( nurl_is_inf x ) }

@ __ts_err s msg i tile → String {
    : String e ( string_from `tiles3d: tile ` )
    ( string_push_int e tile )
    ( string_push_str e `: ` )
    ( string_push_str e msg )
    ^ e
}

// One tile and, recursively, its children. `first`/`next` thread each
// parent's children in the order they were made.
@ __ts_node Tileset t ( Slice i ) first ( Slice i ) next i k → Json {
    : ( Slice f ) bx ( slice_from_vec [f] . t box )
    : Json box ( json_arr_new )
    : b _c0 ( json_arr_push box ( json_float ( slice_at [f] bx * k 6 ) ) )
    : b _c1 ( json_arr_push box ( json_float ( slice_at [f] bx + * k 6 1 ) ) )
    : b _c2 ( json_arr_push box ( json_float ( slice_at [f] bx + * k 6 2 ) ) )
    // the half axes: x, y and z, each a vector
    : ~ i a 0
    ~ < a 3 {
        : ~ i c 0
        ~ < c 3 {
            : f v ? == a c ( slice_at [f] bx + + * k 6 3 a ) 0.0
            : b _h ( json_arr_push box ( json_float v ) )
            = c + c 1
        }
        = a + a 1
    }
    : Json bv ( json_obj_new )
    : b _b ( json_obj_set bv `box` box )
    : Json o ( json_obj_new )
    : b _o1 ( json_obj_set o `boundingVolume` bv )
    : b _o2 ( json_obj_set o `geometricError` ( json_float ( slice_at [f] ( slice_from_vec [f] . t err ) k ) ) )
    : i r ( slice_at [i] ( slice_from_vec [i] . t refine ) k )
    ? == r TS_ADD { : b _r ( json_obj_set o `refine` ( json_str_lit `ADD` ) ) } {}
    ? == r TS_REPLACE { : b _r ( json_obj_set o `refine` ( json_str_lit `REPLACE` ) ) } {}
    ?? ( vec_get [String] . t uri k ) {
        T u → {
            ? > ( string_len u ) 0 {
                : Json ct ( json_obj_new )
                : b _u ( json_obj_set ct `uri` ( json_str_lit ( string_data u ) ) )
                : b _c ( json_obj_set o `content` ct )
            } {}
        }
        F → {}
    }
    ? == 1 ( slice_at [i] ( slice_from_vec [i] . t has_xf ) k ) {
        : ( Slice f ) xs ( slice_from_vec [f] . t xf )
        : Json m ( json_arr_new )
        : ~ i q 0
        ~ < q 16 { : b _m ( json_arr_push m ( json_float ( slice_at [f] xs + * k 16 q ) ) ) = q + q 1 }
        : b _x ( json_obj_set o `transform` m )
    } {}
    : ~ i ch ( slice_at [i] first k )
    ? >= ch 0 {
        : Json kids ( json_arr_new )
        ~ >= ch 0 {
            : b _k ( json_arr_push kids ( __ts_node t first next ch ) )
            = ch ( slice_at [i] next ch )
        }
        : b _ks ( json_obj_set o `children` kids )
    } {}
    ^ o
}

// The tileset.json text, or what breaks the specification.
@ ts_json Tileset t → !String String {
    : i n ( ts_count t )
    ? == n 0 { ^ @ !String String { F ( string_from `tiles3d: the tileset has no tiles` ) } } {}
    ? ( __ts_fin . t gerr ) {} { ^ @ !String String { F ( string_from `tiles3d: the tileset's geometric error is not a finite number` ) } }
    ? < . t gerr 0.0 { ^ @ !String String { F ( string_from `tiles3d: the tileset's geometric error is negative` ) } } {}
    : ( Slice i ) par ( slice_from_vec [i] . t parent )
    : ( Slice f ) bx ( slice_from_vec [f] . t box )
    : ( Slice f ) er ( slice_from_vec [f] . t err )
    : ( Slice i ) rf ( slice_from_vec [i] . t refine )
    : ( Slice f ) xs ( slice_from_vec [f] . t xf )
    ? != ( slice_at [i] par 0 ) -1 { ^ @ !String String { F ( __ts_err `the first tile is the root and has no parent (-1)` 0 ) } } {}
    ? == ( slice_at [i] rf 0 ) TS_INHERIT { ^ @ !String String { F ( __ts_err `the root must say how it refines (TS_ADD or TS_REPLACE)` 0 ) } } {}
    ? > ( slice_at [f] er 0 ) . t gerr { ^ @ !String String { F ( string_from `tiles3d: the tileset's geometric error is below the root's` ) } } {}
    : ( Vec i ) first__v ( vec_new [i] )
    : ( Vec i ) next__v ( vec_new [i] )
    : ( Vec i ) last__v ( vec_new [i] )
    : ~ i k 0
    ~ < k n { ( vec_push [i] first__v -1 ) ( vec_push [i] next__v -1 ) ( vec_push [i] last__v -1 ) = k + k 1 }
    = k 0
    ~ < k n {
        : i p ( slice_at [i] par k )
        ? > k 0 {
            ? == p -1 { ^ @ !String String { F ( __ts_err `only the first tile is the root (parent -1)` k ) } } {}
            ? | < p 0 >= p k { ^ @ !String String { F ( __ts_err `its parent must be a tile made before it` k ) } } {}
            ? > ( slice_at [f] er k ) ( slice_at [f] er p ) { ^ @ !String String { F ( __ts_err `its geometric error is above its parent's` k ) } } {}
            ? == ( slice_at [i] ( slice_from_vec [i] last__v ) p ) -1 {
                : b _f ( vec_set [i] first__v p k )
            } {
                : b _n ( vec_set [i] next__v ( slice_at [i] ( slice_from_vec [i] last__v ) p ) k )
            }
            : b _l ( vec_set [i] last__v p k )
        } {}
        : f e ( slice_at [f] er k )
        ? ( __ts_fin e ) {} { ^ @ !String String { F ( __ts_err `its geometric error is not a finite number` k ) } }
        ? < e 0.0 { ^ @ !String String { F ( __ts_err `its geometric error is negative` k ) } } {}
        : i r ( slice_at [i] rf k )
        ? | < r TS_INHERIT > r TS_REPLACE { ^ @ !String String { F ( __ts_err `unknown refine mode` k ) } } {}
        : ~ i a 0
        ~ < a 6 {
            : f v ( slice_at [f] bx + * k 6 a )
            ? ( __ts_fin v ) {} { ^ @ !String String { F ( __ts_err `a box number is not finite` k ) } }
            ? & >= a 3 < v 0.0 { ^ @ !String String { F ( __ts_err `a box half size is negative` k ) } } {}
            = a + a 1
        }
        ? == 1 ( slice_at [i] ( slice_from_vec [i] . t has_xf ) k ) {
            = a 0
            ~ < a 16 {
                ? ( __ts_fin ( slice_at [f] xs + * k 16 a ) ) {} { ^ @ !String String { F ( __ts_err `a transform number is not finite` k ) } }
                = a + a 1
            }
            // affine: the bottom row (column-major elements 3, 7, 11, 15) is 0 0 0 1
            ? & & & == ( slice_at [f] xs + * k 16 3 ) 0.0 == ( slice_at [f] xs + * k 16 7 ) 0.0 == ( slice_at [f] xs + * k 16 11 ) 0.0 == ( slice_at [f] xs + * k 16 15 ) 1.0 {} {
                ^ @ !String String { F ( __ts_err `a transform is not affine (its bottom row must be 0 0 0 1)` k ) }
            }
        } {}
        = k + k 1
    }
    : Json asset ( json_obj_new )
    : b _a ( json_obj_set asset `version` ( json_str_lit `1.1` ) )
    : Json root ( json_obj_new )
    : b _r1 ( json_obj_set root `asset` asset )
    : b _r2 ( json_obj_set root `geometricError` ( json_float . t gerr ) )
    : b _r3 ( json_obj_set root `root` ( __ts_node t ( slice_from_vec [i] first__v ) ( slice_from_vec [i] next__v ) 0 ) )
    ^ @ !String String { T ( json_stringify root ) }
}

@ ts_write Tileset t s path → !v String {
    ?? ( ts_json t ) {
        F e → { ^ @ !v String { F e } }
        T js → {
            ?? ( write_file path ( string_data js ) ) {
                T _ → { ^ @ !v String { T 0 } }
                F _e → {
                    : String msg ( string_from `tiles3d: cannot write ` )
                    ( string_push_str msg path )
                    ^ @ !v String { F msg }
                }
            }
        }
    }
}
