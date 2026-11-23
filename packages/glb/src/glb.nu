// packages/glb/src/glb.nu — triangle meshes as binary glTF 2.0 (.glb).
//
// A .glb is the one-file form of glTF, the format Blender, three.js, the
// Windows 3D viewer, Android's Scene Viewer and iOS (via conversion) all
// open. This writes the plain case a reconstruction or a generator
// produces: ONE mesh of triangles, each vertex with a position, optionally
// a normal and an RGBA colour, in a single scene node.
//
//   ( glb_mesh_new )                         → GlbMesh
//   ( glb_vertex m x y z )                   → i   the new vertex's index
//   ( glb_normal m nx ny nz )                → v   for the last vertex
//   ( glb_color m r g b a )                  → v   for the last vertex, 0..255
//   ( glb_tri m a b c )                      → v   counter-clockwise = front
//   ( glb_vertex_count m ) ( glb_tri_count m ) → i
//   ( glb_bytes m generator )                → !( Vec u ) String
//   ( glb_write m path generator )           → !v String
//
// Normals and colours are all-or-nothing: either every vertex has one or
// the attribute is left out (a mesh with some is refused, not guessed).
// Normals are written unit length (glTF requires it; scaled first, so any
// non-zero size keeps its direction; a zero normal becomes +Z). Positions
// must be finite as f32. Colours go out as normalised unsigned bytes (COLOR_0, VEC4), the
// form every importer reads as vertex colour.
//
// glTF's frame is right-handed, +Y up, the front facing +Z. Converting a
// caller's own frame (an OpenCV camera frame is +Y DOWN, +Z forward, so
// (x, -y, -z)) is the caller's business; this file writes what it is given.
//
// Layout: the 12-byte header, a JSON chunk (padded with spaces) and a BIN
// chunk (padded with zeros), every bufferView 4-byte aligned: positions
// (f32×3), normals (f32×3), colours (u8×4), indices (u32). POSITION carries
// the min/max the spec requires. The material is unlit-friendly PBR white,
// double-sided, so vertex colours show as they are and an inside-out patch
// of a scanned surface is not invisible.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/ext/json.nu`

: GlbMesh {
    ( Vec f ) pos  // x y z per vertex
    ( Vec f ) nrm  // nx ny nz per vertex, or empty
    ( Vec u ) col  // r g b a per vertex, or empty
    ( Vec i ) idx  // a b c per triangle
}

@ glb_mesh_new → GlbMesh {
    ^ @ GlbMesh { ( vec_new [f] ) ( vec_new [f] ) ( vec_new [u] ) ( vec_new [i] ) }
}

@ glb_vertex_count GlbMesh m → i { ^ / ( vec_len [f] . m pos ) 3 }

@ glb_tri_count GlbMesh m → i { ^ / ( vec_len [i] . m idx ) 3 }

@ glb_vertex inout GlbMesh m f x f y f z → i {
    : i n ( glb_vertex_count m )
    ( vec_push [f] . m pos x ) ( vec_push [f] . m pos y ) ( vec_push [f] . m pos z )
    ^ n
}

@ glb_normal inout GlbMesh m f nx f ny f nz → v {
    ( vec_push [f] . m nrm nx ) ( vec_push [f] . m nrm ny ) ( vec_push [f] . m nrm nz )
}

@ __glb_u8 i v → u {
    ? < v 0 { ^ # u 0 } {}
    ? > v 255 { ^ # u 255 } {}
    ^ # u v
}

@ glb_color inout GlbMesh m i r i g i b i a → v {
    ( vec_push [u] . m col ( __glb_u8 r ) ) ( vec_push [u] . m col ( __glb_u8 g ) )
    ( vec_push [u] . m col ( __glb_u8 b ) ) ( vec_push [u] . m col ( __glb_u8 a ) )
}

@ glb_tri inout GlbMesh m i a i b i c → v {
    ( vec_push [i] . m idx a ) ( vec_push [i] . m idx b ) ( vec_push [i] . m idx c )
}

@ __glb_pad4 i n → i { ^ * / + n 3 4 4 }

@ __glb_u32 ( Vec u ) out i n → v { ( bytes_push_u32_le out # u32 n ) }

@ __glb_f32 ( Vec u ) out f x → v { ( bytes_push_f32_le out # f32 x ) }

// One accessor object.
@ __glb_accessor i view i ctype i count s kind b normalized → Json {
    : Json a ( json_obj_new )
    : b _v ( json_obj_set a `bufferView` ( json_int view ) )
    : b _c ( json_obj_set a `componentType` ( json_int ctype ) )
    : b _n ( json_obj_set a `count` ( json_int count ) )
    : b _t ( json_obj_set a `type` ( json_str_lit kind ) )
    ? normalized { : b _z ( json_obj_set a `normalized` ( json_bool T ) ) } {}
    ^ a
}

@ __glb_view i off i len i target → Json {
    : Json v ( json_obj_new )
    : b _b ( json_obj_set v `buffer` ( json_int 0 ) )
    : b _o ( json_obj_set v `byteOffset` ( json_int off ) )
    : b _l ( json_obj_set v `byteLength` ( json_int len ) )
    : b _t ( json_obj_set v `target` ( json_int target ) )
    ^ v
}

@ __glb_vec3 f a f b f c → Json {
    : Json j ( json_arr_new )
    : b _a ( json_arr_push j ( json_float a ) )
    : b _b ( json_arr_push j ( json_float b ) )
    : b _c ( json_arr_push j ( json_float c ) )
    ^ j
}

// The whole file in memory. F says what is wrong with the mesh.
@ glb_bytes GlbMesh m s generator → !( Vec u ) String {
    : i nv ( glb_vertex_count m )
    : i nt ( glb_tri_count m )
    ? == nv 0 { ^ @ !( Vec u ) String { F ( string_from `glb: the mesh has no vertices` ) } } {}
    ? == nt 0 { ^ @ !( Vec u ) String { F ( string_from `glb: the mesh has no triangles` ) } } {}
    : i nn / ( vec_len [f] . m nrm ) 3
    : i nc / ( vec_len [u] . m col ) 4
    ? & != nn 0 != nn nv { ^ @ !( Vec u ) String { F ( string_from `glb: some vertices have a normal and some do not` ) } } {}
    ? & != nc 0 != nc nv { ^ @ !( Vec u ) String { F ( string_from `glb: some vertices have a colour and some do not` ) } } {}
    // exactly four bytes a vertex: a stray byte written straight into `col`
    // would shift the indices off their 4-byte alignment
    ? & != ( vec_len [u] . m col ) 0 != ( vec_len [u] . m col ) * nv 4 { ^ @ !( Vec u ) String { F ( string_from `glb: each vertex colour must be four bytes` ) } } {}
    ? != ( vec_len [f] . m pos ) * nv 3 { ^ @ !( Vec u ) String { F ( string_from `glb: each vertex position must be three numbers` ) } } {}
    ? & != ( vec_len [f] . m nrm ) 0 != ( vec_len [f] . m nrm ) * nv 3 { ^ @ !( Vec u ) String { F ( string_from `glb: each vertex normal must be three numbers` ) } } {}
    : ( Slice f ) p ( slice_from_vec [f] . m pos )
    : ( Slice i ) ix ( slice_from_vec [i] . m idx )
    : ~ i k 0
    ~ < k * 3 nt {
        : i v ( slice_at [i] ix k )
        ? | < v 0 >= v nv { ^ @ !( Vec u ) String { F ( string_from `glb: a triangle names a vertex that does not exist` ) } } {}
        = k + k 1
    }

    // ── the binary buffer ──
    : ( Vec u ) bin ( vec_with_cap [u] + * nv 28 * nt 12 )
    : ~ f mnx ( slice_at [f] p 0 )
    : ~ f mny ( slice_at [f] p 1 )
    : ~ f mnz ( slice_at [f] p 2 )
    : ~ f mxx mnx
    : ~ f mxy mny
    : ~ f mxz mnz
    = k 0
    ~ < k nv {
        // the bounds of the values as stored, i.e. after rounding to f32
        : f x # f # f32 ( slice_at [f] p * k 3 )
        : f y # f # f32 ( slice_at [f] p + * k 3 1 )
        : f z # f # f32 ( slice_at [f] p + * k 3 2 )
        // glTF forbids non-finite components; a finite f64 too large for
        // f32 becomes infinite here too
        ? | | | | | != 0 ( nurl_is_nan x ) != 0 ( nurl_is_inf x ) != 0 ( nurl_is_nan y ) != 0 ( nurl_is_inf y ) != 0 ( nurl_is_nan z ) != 0 ( nurl_is_inf z ) {
            ^ @ !( Vec u ) String { F ( string_from `glb: a vertex position is not a finite number` ) }
        } {}
        ( __glb_f32 bin x ) ( __glb_f32 bin y ) ( __glb_f32 bin z )
        ? < x mnx { = mnx x } {}
        ? < y mny { = mny y } {}
        ? < z mnz { = mnz z } {}
        ? > x mxx { = mxx x } {}
        ? > y mxy { = mxy y } {}
        ? > z mxz { = mxz z } {}
        = k + k 1
    }
    : i pos_len * nv 12
    : i nrm_off pos_len
    ? > nn 0 {
        : ( Slice f ) q ( slice_from_vec [f] . m nrm )
        = k 0
        ~ < k nv {
            : f a ( slice_at [f] q * k 3 )
            : f b ( slice_at [f] q + * k 3 1 )
            : f c ( slice_at [f] q + * k 3 2 )
            // scaled by the largest component first, so a tiny normal keeps
            // its direction and a huge one does not overflow when squared;
            // only an exactly zero (or non-finite) one becomes +Z
            : f aa ? < a 0.0 - 0.0 a a
            : f ab ? < b 0.0 - 0.0 b b
            : f ac ? < c 0.0 - 0.0 c c
            : f mx ? > aa ? > ab ac ab ac aa ? > ab ac ab ac
            : b usable & > mx 0.0 == 0 ( nurl_is_inf mx )
            ? & usable == 0 ( nurl_is_nan + + a b c ) {
                : f sa / a mx
                : f sb / b mx
                : f sc / c mx
                : f l ( float_sqrt + + * sa sa * sb sb * sc sc )
                ( __glb_f32 bin / sa l ) ( __glb_f32 bin / sb l ) ( __glb_f32 bin / sc l )
            } {
                ( __glb_f32 bin 0.0 ) ( __glb_f32 bin 0.0 ) ( __glb_f32 bin 1.0 )
            }
            = k + k 1
        }
    } {}
    : i col_off ( vec_len [u] bin )
    ? > nc 0 { ( vec_append [u] bin ( vec_clone [u] . m col ) ) } {}
    : i idx_off ( vec_len [u] bin )
    = k 0
    ~ < k * 3 nt { ( __glb_u32 bin ( slice_at [i] ix k ) ) = k + k 1 }
    : i bin_len ( vec_len [u] bin )
    ~ != ( vec_len [u] bin ) ( __glb_pad4 bin_len ) { ( vec_push [u] bin # u 0 ) }

    // ── the JSON ──
    : Json views ( json_arr_new )
    : Json accs ( json_arr_new )
    : Json attrs ( json_obj_new )
    : ~ i nview 0
    : b _p1 ( json_arr_push views ( __glb_view 0 pos_len 34962 ) )
    : Json pa ( __glb_accessor nview 5126 nv `VEC3` F )
    : b _mn ( json_obj_set pa `min` ( __glb_vec3 mnx mny mnz ) )
    : b _mx ( json_obj_set pa `max` ( __glb_vec3 mxx mxy mxz ) )
    : b _p2 ( json_arr_push accs pa )
    : b _p3 ( json_obj_set attrs `POSITION` ( json_int nview ) )
    = nview + nview 1
    ? > nn 0 {
        : b _n1 ( json_arr_push views ( __glb_view nrm_off * nv 12 34962 ) )
        : b _n2 ( json_arr_push accs ( __glb_accessor nview 5126 nv `VEC3` F ) )
        : b _n3 ( json_obj_set attrs `NORMAL` ( json_int nview ) )
        = nview + nview 1
    } {}
    ? > nc 0 {
        : b _c1 ( json_arr_push views ( __glb_view col_off * nv 4 34962 ) )
        : b _c2 ( json_arr_push accs ( __glb_accessor nview 5121 nv `VEC4` T ) )
        : b _c3 ( json_obj_set attrs `COLOR_0` ( json_int nview ) )
        = nview + nview 1
    } {}
    : b _i1 ( json_arr_push views ( __glb_view idx_off * nt 12 34963 ) )
    : b _i2 ( json_arr_push accs ( __glb_accessor nview 5125 * nt 3 `SCALAR` F ) )

    : Json prim ( json_obj_new )
    : b _q1 ( json_obj_set prim `attributes` attrs )
    : b _q2 ( json_obj_set prim `indices` ( json_int nview ) )
    : b _q3 ( json_obj_set prim `material` ( json_int 0 ) )
    : b _q4 ( json_obj_set prim `mode` ( json_int 4 ) )
    : Json prims ( json_arr_new )
    : b _q5 ( json_arr_push prims prim )
    : Json mesh ( json_obj_new )
    : b _q6 ( json_obj_set mesh `primitives` prims )
    : Json meshes ( json_arr_new )
    : b _q7 ( json_arr_push meshes mesh )

    : Json pbr ( json_obj_new )
    : Json white ( json_arr_new )
    : b _w1 ( json_arr_push white ( json_float 1.0 ) ) : b _w2 ( json_arr_push white ( json_float 1.0 ) )
    : b _w3 ( json_arr_push white ( json_float 1.0 ) ) : b _w4 ( json_arr_push white ( json_float 1.0 ) )
    : b _r1 ( json_obj_set pbr `baseColorFactor` white )
    : b _r2 ( json_obj_set pbr `metallicFactor` ( json_float 0.0 ) )
    : b _r3 ( json_obj_set pbr `roughnessFactor` ( json_float 1.0 ) )
    : Json mat ( json_obj_new )
    : b _m1 ( json_obj_set mat `pbrMetallicRoughness` pbr )
    : b _m2 ( json_obj_set mat `doubleSided` ( json_bool T ) )
    : Json mats ( json_arr_new )
    : b _m3 ( json_arr_push mats mat )

    : Json node ( json_obj_new )
    : b _o1 ( json_obj_set node `mesh` ( json_int 0 ) )
    : Json nodes ( json_arr_new )
    : b _o2 ( json_arr_push nodes node )
    : Json sn ( json_arr_new )
    : b _s1 ( json_arr_push sn ( json_int 0 ) )
    : Json scene ( json_obj_new )
    : b _s2 ( json_obj_set scene `nodes` sn )
    : Json scenes ( json_arr_new )
    : b _s3 ( json_arr_push scenes scene )
    : Json buf ( json_obj_new )
    : b _b1 ( json_obj_set buf `byteLength` ( json_int ( vec_len [u] bin ) ) )
    : Json bufs ( json_arr_new )
    : b _b2 ( json_arr_push bufs buf )
    : Json asset ( json_obj_new )
    : b _a1 ( json_obj_set asset `version` ( json_str_lit `2.0` ) )
    ? > ( nurl_str_len generator ) 0 { : b _a2 ( json_obj_set asset `generator` ( json_str_lit generator ) ) } {}

    : Json root ( json_obj_new )
    : b _t1 ( json_obj_set root `asset` asset )
    : b _t2 ( json_obj_set root `scene` ( json_int 0 ) )
    : b _t3 ( json_obj_set root `scenes` scenes )
    : b _t4 ( json_obj_set root `nodes` nodes )
    : b _t5 ( json_obj_set root `meshes` meshes )
    : b _t6 ( json_obj_set root `materials` mats )
    : b _t7 ( json_obj_set root `buffers` bufs )
    : b _t8 ( json_obj_set root `bufferViews` views )
    : b _t9 ( json_obj_set root `accessors` accs )
    : String js ( json_stringify root )
    : ( Vec u ) jb ( bytes_from_str ( string_data js ) )
    : i jlen ( vec_len [u] jb )
    ~ != ( vec_len [u] jb ) ( __glb_pad4 jlen ) { ( vec_push [u] jb # u 32 ) }

    // ── the container ──
    : i total + + 12 + 8 ( vec_len [u] jb ) + 8 ( vec_len [u] bin )
    : ( Vec u ) out ( vec_with_cap [u] total )
    ( __glb_u32 out 1179937895 )  // "glTF"
    ( __glb_u32 out 2 )
    ( __glb_u32 out total )
    ( __glb_u32 out ( vec_len [u] jb ) )
    ( __glb_u32 out 1313821514 )  // "JSON"
    ( vec_append [u] out jb )
    ( __glb_u32 out ( vec_len [u] bin ) )
    ( __glb_u32 out 5130562 )  // "BIN\0"
    ( vec_append [u] out bin )
    ^ @ !( Vec u ) String { T out }
}

@ glb_write GlbMesh m s path s generator → !v String {
    ?? ( glb_bytes m generator ) {
        F e → { ^ @ !v String { F e } }
        T bytes → {
            ?? ( write_file_bytes path bytes ) {
                T _ → { ^ @ !v String { T 0 } }
                F _e → {
                    : String msg ( string_from `glb: cannot write ` )
                    ( string_push_str msg path )
                    ^ @ !v String { F msg }
                }
            }
        }
    }
}
