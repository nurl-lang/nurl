// packages/pctiles/src/pctiles.nu — a point cloud as a 3D Tiles tileset.
//
//   ( pct_build xyz rgb up capacity grid seed dir verbose ) → !PctStats String
//
// The cloud goes into an octree (octree), each node becomes a tile whose
// content is that node's own points as a POINTS glb (glb), and the tree is
// written as tileset.json (tiles3d). Every point is in exactly one tile, so
// the tileset refines by ADD: a client draws the root's sample first, and
// children add detail where the camera is close enough to see it.
//
//   - `up` names the cloud's up axis: PCT_UP_NEG_Y (OpenCV, what
//     reconstructions write), PCT_UP_POS_Y (glTF) or PCT_UP_POS_Z. The
//     tileset is z-up; points are turned to it once, before the octree.
//   - A tile's box is the tight bounds of its subtree's points, so a client
//     culls on what is really there, not on the octree's cubes.
//   - A tile's geometric error is its sampling spacing — the gap its points
//     leave, which its children fill — times PCT_ERROR_SCALE (8). Clients
//     refine a tile while its error shows larger than a pixel threshold,
//     16 by default in CesiumJS and Cesium for Unreal and Unity; scaled so,
//     that default refines until the gaps are about 2 pixels, which is when
//     a cloud looks solid. A leaf's error is 0. The tileset's is the root
//     box's diagonal (with nothing drawn, the whole extent is missing).
//   - Content: `n<k>.glb` beside tileset.json, positions in glTF axes
//     (tileset (x, y, z) as (x, z, -y)), colours as COLOR_0 when the cloud
//     has them.
//
// Positions in glb are float32. That is a tenth of a millimetre over a
// kilometre around the origin, which a reconstruction never leaves; a
// georeferenced cloud far from the origin would need tile-relative
// positions (a translation per tile), which this does not write yet.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/time.nu`
$ `deps/octree/src/octree.nu`
$ `deps/tiles3d/src/tiles3d.nu`
$ `deps/glb/src/glb.nu`

: i PCT_UP_NEG_Y 0
: i PCT_UP_POS_Y 1
: i PCT_UP_POS_Z 2
: f PCT_ERROR_SCALE 8.0

: PctStats {
    i points  // placed in tiles
    i dropped  // not finite
    i tiles
    i depth  // levels below the root
    i largest  // points in the fullest tile
    i ms  // wall time
}

// One point of the cloud in the tileset's z-up frame.
@ __pct_zup ( Slice f ) xyz i p i up i axis → f {
    : f x ( slice_at [f] xyz * p 3 )
    : f y ( slice_at [f] xyz + * p 3 1 )
    : f z ( slice_at [f] xyz + * p 3 2 )
    ? == axis 0 { ^ x } {}
    ? == up PCT_UP_NEG_Y { ^ ? == axis 1 z - 0.0 y } {}  // y down, z forward
    ? == up PCT_UP_POS_Y { ^ ? == axis 1 - 0.0 z y } {}  // y up, z towards the viewer
    ^ ? == axis 1 y z
}

@ __pct_max f a f b → f { ^ ? > a b a b }

@ __pct_uri i k → String {
    : String u ( string_from `n` )
    ( string_push_int u k )
    ( string_push_str u `.glb` )
    ^ u
}

// Built in a staging directory beside `dir`, and swapped in only once every
// tile and the manifest are written: a build that fails part-way leaves
// the tileset that was there before as it was, not old tiles mixed with
// new ones under a manifest that no longer describes them.
@ pct_build ( Slice f ) xyz ( Slice u ) rgb i up i capacity i grid i seed s dir i verbose → !PctStats String {
    : String stage ( string_from dir )
    ( string_push_str stage `.building-` )
    ( string_push_int stage ( monotonic_ns ) )
    : !PctStats String r ( __pct_build_into xyz rgb up capacity grid seed ( string_data stage ) verbose )
    ?? r {
        F e → {
            ?? ( dir_remove_all ( string_data stage ) ) { T _ → {} F _e → {} }
            ^ @ !PctStats String { F e }
        }
        T st → {
            : String old ( string_from dir )
            ( string_push_str old `.old-` )
            ( string_push_int old ( monotonic_ns ) )
            : b had != 0 ( nurl_path_type dir )
            ? had {
                ?? ( fs_rename dir ( string_data old ) ) {
                    T _ → {}
                    F _e → {
                        ?? ( dir_remove_all ( string_data stage ) ) { T _ → {} F _e2 → {} }
                        : String m ( string_from `pctiles: cannot move the old tileset aside: ` )
                        ( string_push_str m dir )
                        ^ @ !PctStats String { F m }
                    }
                }
            } {}
            ?? ( fs_rename ( string_data stage ) dir ) {
                T _ → {}
                F _e → {
                    // put the old one back where it was
                    ? had { ?? ( fs_rename ( string_data old ) dir ) { T _ → {} F _e3 → {} } } {}
                    : String m ( string_from `pctiles: cannot move the new tileset into place: ` )
                    ( string_push_str m dir )
                    ^ @ !PctStats String { F m }
                }
            }
            ? had { ?? ( dir_remove_all ( string_data old ) ) { T _ → {} F _e4 → {} } } {}
            ^ @ !PctStats String { T st }
        }
    }
}

@ __pct_build_into ( Slice f ) xyz ( Slice u ) rgb i up i capacity i grid i seed s dir i verbose → !PctStats String {
    : i t0 ( monotonic_ns )
    : i np / ( slice_len [f] xyz ) 3
    : b col == ( slice_len [u] rgb ) * np 3
    ? & > ( slice_len [u] rgb ) 0 ! col { ^ @ !PctStats String { F ( string_from `pctiles: the colours are not 3 bytes a point` ) } } {}
    ? == np 0 { ^ @ !PctStats String { F ( string_from `pctiles: the cloud has no points` ) } } {}
    // the cloud in the tileset's frame
    : ( Vec f ) zu__v ( vec_with_cap [f] * np 3 )
    : ~ i p 0
    ~ < p np {
        ( vec_push [f] zu__v ( __pct_zup xyz p up 0 ) )
        ( vec_push [f] zu__v ( __pct_zup xyz p up 1 ) )
        ( vec_push [f] zu__v ( __pct_zup xyz p up 2 ) )
        = p + p 1
    }
    : ( Slice f ) zu ( slice_from_vec [f] zu__v )
    : Octree t ( oc_build zu capacity grid seed )
    : i nn ( oc_count t )
    ? == nn 0 { ^ @ !PctStats String { F ( string_from `pctiles: no point of the cloud is finite` ) } } {}
    ?? ( dir_create_all dir ) {
        T _ → {}
        F _e → {
            : String m ( string_from `pctiles: cannot create ` )
            ( string_push_str m dir )
            ^ @ !PctStats String { F m }
        }
    }
    : ~ i depth 0
    : ~ i largest 0
    // the root box's diagonal: the tileset's error
    : f dx - ( oc_max t 0 0 ) ( oc_min t 0 0 )
    : f dy - ( oc_max t 0 1 ) ( oc_min t 0 1 )
    : f dz - ( oc_max t 0 2 ) ( oc_min t 0 2 )
    : f diag ( float_sqrt + + * dx dx * dy dy * dz dz )
    // at least the root's own error, which a coarse grid can push above the
    // diagonal (grid 2 on a cube: 8 x the root's half-size cells)
    : f rooterr ? > nn 1 * PCT_ERROR_SCALE ( oc_spacing t 0 ) 0.0
    : ~ Tileset ts ( ts_new ( __pct_max ( __pct_max diag rooterr ) 1.0e-9 ) )
    // which nodes have children: a leaf's error is 0
    : ( Vec i ) kids__v ( vec_zeroed [i] nn )
    : ( Slice i ) kids ( slice_from_vec [i] kids__v )
    : ~ i k 1
    ~ < k nn {
        ( slice_put [i] kids ( oc_parent t k ) 1 )
        = k + k 1
    }
    = k 0
    ~ < k nn {
        : f cx * 0.5 + ( oc_min t k 0 ) ( oc_max t k 0 )
        : f cy * 0.5 + ( oc_min t k 1 ) ( oc_max t k 1 )
        : f cz * 0.5 + ( oc_min t k 2 ) ( oc_max t k 2 )
        // a box never flat: a tile of coplanar points still has a volume
        : f eps * 0.000001 + 1.0 diag
        : f hx + * 0.5 - ( oc_max t k 0 ) ( oc_min t k 0 ) eps
        : f hy + * 0.5 - ( oc_max t k 1 ) ( oc_min t k 1 ) eps
        : f hz + * 0.5 - ( oc_max t k 2 ) ( oc_min t k 2 ) eps
        : f err ? == 1 ( slice_at [i] kids k ) * PCT_ERROR_SCALE ( oc_spacing t k ) 0.0
        : i tk ( ts_tile ts ( oc_parent t k ) cx cy cz hx hy hz err )
        ? == k 0 { ( ts_refine ts tk TS_ADD ) } {}
        // the content: this node's own points
        : ( Slice i ) own ( oc_points t k )
        : i no ( slice_len [i] own )
        ? > no largest { = largest no } {}
        ? > ( oc_level t k ) depth { = depth ( oc_level t k ) } {}
        : ~ GlbMesh m ( glb_mesh_new )
        : ~ i j 0
        ~ < j no {
            : i q ( slice_at [i] own j )
            // tileset (x, y, z) → glTF (x, z, -y)
            : i _v ( glb_vertex m ( slice_at [f] zu * q 3 ) ( slice_at [f] zu + * q 3 2 ) - 0.0 ( slice_at [f] zu + * q 3 1 ) )
            ? col {
                ( glb_color m # i ( slice_at [u] rgb * q 3 ) # i ( slice_at [u] rgb + * q 3 1 ) # i ( slice_at [u] rgb + * q 3 2 ) 255 )
            } {}
            = j + j 1
        }
        : String uri ( __pct_uri k )
        : String path ( path_join dir ( string_data uri ) )
        ?? ( glb_points_write m ( string_data path ) `pctiles` ) {
            T _ → {}
            F e → { ^ @ !PctStats String { F e } }
        }
        ( ts_content ts tk ( string_data uri ) )
        ? & != verbose 0 == 0 % + k 1 500 {
            ( nurl_print `tiles  ` ) ( nurl_print ( nurl_str_int + k 1 ) ) ( nurl_print ` / ` ) ( nurl_print ( nurl_str_int nn ) ) ( nurl_print `\n` )
        } {}
        = k + k 1
    }
    : String tj ( path_join dir `tileset.json` )
    ?? ( ts_write ts ( string_data tj ) ) {
        T _ → {}
        F e → { ^ @ !PctStats String { F e } }
    }
    : i ms / - ( monotonic_ns ) t0 1000000
    ^ @ !PctStats String { T @ PctStats { ( oc_used t ) ( oc_dropped t ) nn depth largest ms } }
}
