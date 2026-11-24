// packages/tiles3d/tests/terrain.nu — a small terrain as a two-level
// octree tileset of point tiles, plus the tilesets ts_json must refuse.
//
//   nurl tests/terrain.nu /tmp/terrain && /tmp/terrain <dir>
//
// The terrain is a 64 x 64 height field over 8 x 8 metres, z up. Each
// point goes to exactly one tile (ADD refinement): every 16th to the root,
// every 4th of the rest to a level-1 quadrant, the rest to a level-2 one.
// The tiles' glb content is in glTF axes, (x, z, -y), as the format wants.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/float.nu`
$ `../src/tiles3d.nu`
$ `../../glb/src/glb.nu`

: f SIZE 8.0
: i GRID 64

@ __height f x f y → f { ^ + 1.0 * 0.5 ( float_sin + * x 0.9 * y 0.6 ) }

// Which tile a lattice point belongs to: 0 the root, 1..4 level 1, 5..20
// level 2 (quadrant q of level 1 holds level-2 tiles 5 + 4q .. 8 + 4q).
@ __tile_of i gx i gy → i {
    ? & == 0 % gx 4 == 0 % gy 4 { ^ 0 } {}
    : i q1 + * / gy 32 2 / gx 32
    ? & == 0 % gx 2 == 0 % gy 2 { ^ + 1 q1 } {}
    : i lx / % gx 32 16
    : i ly / % gy 32 16
    ^ + + 5 * q1 4 + * ly 2 lx
}

@ __write_tile s dir i tile i rc → i {
    : ~ GlbMesh m ( glb_mesh_new )
    : ~ i gy 0
    ~ < gy GRID {
        : ~ i gx 0
        ~ < gx GRID {
            ? == ( __tile_of gx gy ) tile {
                : f x * # f gx / SIZE # f GRID
                : f y * # f gy / SIZE # f GRID
                : f z ( __height x y )
                : i _v ( glb_vertex m x z - 0.0 y )  // tileset (x, y, z) → glTF (x, z, -y)
                ( glb_color m # i * 60.0 z 120 # i * 30.0 x 255 )
            } {}
            = gx + gx 1
        }
        = gy + gy 1
    }
    : String name ( string_from `t` )
    ( string_push_int name tile )
    ( string_push_str name `.glb` )
    : String p ( path_join dir ( string_data name ) )
    ?? ( glb_points_write m ( string_data p ) `tiles3d test` ) {
        T _ → { ^ rc }
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ^ 1 }
    }
}

@ __uri i tile → String {
    : String u ( string_from `t` )
    ( string_push_int u tile )
    ( string_push_str u `.glb` )
    ^ u
}

@ __refused Tileset t s what → i {
    ?? ( ts_json t ) {
        T _ → { ( nurl_print `FAIL accepted: ` ) ( nurl_print what ) ( nurl_print `\n` ) ^ 1 }
        F e → { ( nurl_print `refused: ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ^ 0 }
    }
}

@ main → i {
    ? < ( nurl_argc ) 2 { ( nurl_print `usage: terrain <dir>\n` ) ^ 2 } {}
    : s dir ( nurl_argv 1 )
    : ~ i rc 0
    // z spans 0.5 .. 1.5 (the height field); boxes are a little taller
    : f h * SIZE 0.5
    : ~ Tileset t ( ts_new 4.0 )
    : i root ( ts_tile t -1 h h 1.0 h h 0.6 2.0 )
    ( ts_refine t root TS_ADD )
    : String ru ( __uri 0 )
    ( ts_content t root ( string_data ru ) )
    : ~ i q 0
    ~ < q 4 {
        : f qx + * # f % q 2 h * h 0.5
        : f qy + * # f / q 2 h * h 0.5
        : i l1 ( ts_tile t root qx qy 1.0 * h 0.5 * h 0.5 0.6 0.5 )
        : String u1 ( __uri + 1 q )
        ( ts_content t l1 ( string_data u1 ) )
        : ~ i r 0
        ~ < r 4 {
            : f rx + - qx * h 0.5 + * # f % r 2 * h 0.5 * h 0.25
            : f ry + - qy * h 0.5 + * # f / r 2 * h 0.5 * h 0.25
            : i l2 ( ts_tile t l1 rx ry 1.0 * h 0.25 * h 0.25 0.6 0.0 )
            : String u2 ( __uri + + 5 * q 4 r )
            ( ts_content t l2 ( string_data u2 ) )
            = r + r 1
        }
        = q + q 1
    }
    : ~ i k 0
    ~ < k 21 { = rc ( __write_tile dir k rc ) = k + k 1 }
    : String tp ( path_join dir `tileset.json` )
    ?? ( ts_write t ( string_data tp ) ) {
        T _ → { ( nurl_print `wrote tileset.json (` ) ( nurl_print ( nurl_str_int ( ts_count t ) ) ) ( nurl_print ` tiles)\n` ) }
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) = rc 1 }
    }

    // refusals
    : Tileset none ( ts_new 1.0 )
    = rc + rc ( __refused none `an empty tileset` )
    : ~ Tileset norf ( ts_new 1.0 )
    : i _a ( ts_tile norf -1 0.0 0.0 0.0 1.0 1.0 1.0 1.0 )
    = rc + rc ( __refused norf `a root without refine` )
    : ~ Tileset two ( ts_new 1.0 )
    : i _b ( ts_tile two -1 0.0 0.0 0.0 1.0 1.0 1.0 1.0 )
    ( ts_refine two 0 TS_ADD )
    : i _c ( ts_tile two -1 0.0 0.0 0.0 1.0 1.0 1.0 0.5 )
    = rc + rc ( __refused two `a second root` )
    : ~ Tileset fwd ( ts_new 1.0 )
    : i _d ( ts_tile fwd -1 0.0 0.0 0.0 1.0 1.0 1.0 1.0 )
    ( ts_refine fwd 0 TS_ADD )
    : i _e ( ts_tile fwd 2 0.0 0.0 0.0 1.0 1.0 1.0 0.5 )
    : i _f ( ts_tile fwd 0 0.0 0.0 0.0 1.0 1.0 1.0 0.5 )
    = rc + rc ( __refused fwd `a parent made after its child` )
    : ~ Tileset up ( ts_new 1.0 )
    : i _g ( ts_tile up -1 0.0 0.0 0.0 1.0 1.0 1.0 0.5 )
    ( ts_refine up 0 TS_REPLACE )
    : i _h ( ts_tile up 0 0.0 0.0 0.0 1.0 1.0 1.0 0.7 )
    = rc + rc ( __refused up `a child with more error than its parent` )
    : ~ Tileset low ( ts_new 0.1 )
    : i _i ( ts_tile low -1 0.0 0.0 0.0 1.0 1.0 1.0 0.5 )
    ( ts_refine low 0 TS_ADD )
    = rc + rc ( __refused low `a tileset error below the root's` )
    : ~ Tileset neg ( ts_new 1.0 )
    : i _j ( ts_tile neg -1 0.0 0.0 0.0 1.0 -1.0 1.0 0.5 )
    ( ts_refine neg 0 TS_ADD )
    = rc + rc ( __refused neg `a negative half size` )
    ^ rc
}
