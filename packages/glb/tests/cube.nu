// packages/glb/tests/cube.nu — write a coloured cube (24 vertices, face
// normals, 12 triangles) and a bare triangle (positions only) as .glb, plus
// the meshes the writer must refuse.
//
//   nurl tests/cube.nu /tmp/cube && /tmp/cube <dir>

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/path.nu`
$ `../src/glb.nu`

@ __face inout GlbMesh m f nx f ny f nz i r i g i b → v {
    // the face's four corners, counter-clockwise seen from outside
    : ( Vec f ) c ( vec_new [f] )
    ? != nx 0.0 {
        ( vec_push [f] c nx ) ( vec_push [f] c -1.0 ) ( vec_push [f] c -1.0 )
        ( vec_push [f] c nx ) ( vec_push [f] c 1.0 ) ( vec_push [f] c -1.0 )
        ( vec_push [f] c nx ) ( vec_push [f] c 1.0 ) ( vec_push [f] c 1.0 )
        ( vec_push [f] c nx ) ( vec_push [f] c -1.0 ) ( vec_push [f] c 1.0 )
    } {}
    ? != ny 0.0 {
        ( vec_push [f] c -1.0 ) ( vec_push [f] c ny ) ( vec_push [f] c -1.0 )
        ( vec_push [f] c -1.0 ) ( vec_push [f] c ny ) ( vec_push [f] c 1.0 )
        ( vec_push [f] c 1.0 ) ( vec_push [f] c ny ) ( vec_push [f] c 1.0 )
        ( vec_push [f] c 1.0 ) ( vec_push [f] c ny ) ( vec_push [f] c -1.0 )
    } {}
    ? != nz 0.0 {
        ( vec_push [f] c -1.0 ) ( vec_push [f] c -1.0 ) ( vec_push [f] c nz )
        ( vec_push [f] c 1.0 ) ( vec_push [f] c -1.0 ) ( vec_push [f] c nz )
        ( vec_push [f] c 1.0 ) ( vec_push [f] c 1.0 ) ( vec_push [f] c nz )
        ( vec_push [f] c -1.0 ) ( vec_push [f] c 1.0 ) ( vec_push [f] c nz )
    } {}
    : ( Slice f ) s ( slice_from_vec [f] c )
    : i base ( glb_vertex_count m )
    : ~ i k 0
    ~ < k 4 {
        : i _v ( glb_vertex m ( slice_at [f] s * k 3 ) ( slice_at [f] s + * k 3 1 ) ( slice_at [f] s + * k 3 2 ) )
        ( glb_normal m nx ny nz )
        ( glb_color m r g b 255 )
        = k + k 1
    }
    // winding: flip when the corner order above runs clockwise from outside
    : b flip | | < nx 0.0 < ny 0.0 < nz 0.0
    ? flip {
        ( glb_tri m base + base 2 + base 1 ) ( glb_tri m base + base 3 + base 2 )
    } {
        ( glb_tri m base + base 1 + base 2 ) ( glb_tri m base + base 2 + base 3 )
    }
}

@ main → i {
    ? < ( nurl_argc ) 2 { ( nurl_print `usage: cube <dir>\n` ) ^ 2 } {}
    : s dir ( nurl_argv 1 )
    : ~ i rc 0
    : ~ GlbMesh m ( glb_mesh_new )
    ( __face m 1.0 0.0 0.0 230 60 60 ) ( __face m -1.0 0.0 0.0 60 230 60 )
    ( __face m 0.0 1.0 0.0 60 60 230 ) ( __face m 0.0 -1.0 0.0 230 230 60 )
    ( __face m 0.0 0.0 1.0 230 60 230 ) ( __face m 0.0 0.0 -1.0 60 230 230 )
    : String cp ( path_join dir `cube.glb` )
    ?? ( glb_write m ( string_data cp ) `glb test cube` ) {
        T _ → { ( nurl_print `wrote cube.glb (24 vertices, 12 triangles)\n` ) }
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) = rc 1 }
    }
    // positions only
    : ~ GlbMesh t ( glb_mesh_new )
    : i a ( glb_vertex t 0.0 0.0 0.0 )
    : i b ( glb_vertex t 1.0 0.0 0.0 )
    : i c ( glb_vertex t 0.0 1.0 0.0 )
    ( glb_tri t a b c )
    : String tp ( path_join dir `tri.glb` )
    ?? ( glb_write t ( string_data tp ) `` ) {
        T _ → { ( nurl_print `wrote tri.glb (3 vertices, 1 triangle)\n` ) }
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) = rc 1 }
    }
    // refusals: a dangling index, half the vertices coloured, no triangles
    : ~ GlbMesh bad ( glb_mesh_new )
    : i x ( glb_vertex bad 0.0 0.0 0.0 )
    ( glb_tri bad x x 7 )
    ?? ( glb_bytes bad `` ) { T _ → { ( nurl_print `FAIL a dangling index was accepted\n` ) = rc 1 } F e → { ( nurl_print `refused: ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) } }
    : ~ GlbMesh half ( glb_mesh_new )
    : i h0 ( glb_vertex half 0.0 0.0 0.0 )
    ( glb_color half 1 2 3 255 )
    : i h1 ( glb_vertex half 1.0 0.0 0.0 )
    : i h2 ( glb_vertex half 0.0 1.0 0.0 )
    ( glb_tri half h0 h1 h2 )
    ?? ( glb_bytes half `` ) { T _ → { ( nurl_print `FAIL a half-coloured mesh was accepted\n` ) = rc 1 } F e → { ( nurl_print `refused: ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) } }
    : GlbMesh empty ( glb_mesh_new )
    ?? ( glb_bytes empty `` ) { T _ → { ( nurl_print `FAIL an empty mesh was accepted\n` ) = rc 1 } F e → { ( nurl_print `refused: ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) } }
    ^ rc
}
