// packages/map-anything/src/mesh.nu — a 3-D object from the kept views.
//
//   ( ms_auto_box sc box )                         → b   2–98 % bounds
//   ( ms_mesh sc box res keep verbose )            → !GlbMesh String
//
// A point cloud is samples; an object is a surface. The views a run kept
// (scene.nu) hold what a surface needs and a cloud has lost: each camera,
// each pixel's depth along its ray, which pixels survived the filters.
// So the surface is fused from them, not fitted to the points.
//
// TSDF fusion. A grid of `res` cells along the box's longest side holds,
// at each grid point, a truncated signed distance to the surface — the
// running average, over every view that sees the point, of (depth the
// view measured at the pixel the point projects to) − (the point's own
// depth in that camera), divided by the truncation (4 cells) and clamped
// to ≤ 1. Positive is free space in front of a surface, negative is just
// behind one; a point more than the truncation behind what a view saw is
// hidden from that view and left alone. Colours average only the views
// that put the point within the truncation of their surface — a view
// that sees straight past a point is looking at something else.
//
// Marching tetrahedra. Each grid cell whose eight corners were all seen is
// cut into six tetrahedra around its main diagonal (Freudenthal's split,
// the same in every cell, so the pieces meet without cracks), and each
// tetrahedron the zero level crosses yields one triangle or two, at the
// zero crossings along its edges. A crossing is a vertex shared by every
// triangle that uses that grid edge (keyed by the edge), its colour
// interpolated like its position. Every triangle is turned so it faces
// from the inside (negative) out, which is the side the cameras were on.
//
// Then the loose bits go: triangles are grouped into connected pieces,
// and a piece with fewer than `keep` × the largest piece's triangles is
// dropped (the speckle a few noisy pixels leave in free space). Normals
// are the area-weighted average of the faces at each vertex.
//
// The result is in glTF's frame — +Y up, centred on the box — metres:
// (x, y, z) of the reconstruction (camera 0's OpenCV frame, +Y down)
// becomes (x − cx, −(y − cy), −(z − cz)).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/sort.nu`
$ `deps/glb/src/glb.nu`
$ `scene.nu`

// ── the box ─────────────────────────────────────────────────────────

// The world point of pixel (x, y) of view v at depth d.
@ __ms_world Scene sc i v f px f py f d ( Slice f ) out → v {
    : ( Slice f ) ss ( slice_from_vec [f] . sc sims )
    : ( Slice f ) kk ( slice_from_vec [f] . sc ks )
    : i sb * v 13
    : i kb * v 4
    : f cx * / - px ( slice_at [f] kk + kb 2 ) ( slice_at [f] kk kb ) d
    : f cy * / - py ( slice_at [f] kk + kb 3 ) ( slice_at [f] kk + kb 1 ) d
    : f s ( slice_at [f] ss sb )
    : ~ i r 0
    ~ < r 3 {
        ( slice_put [f] out r + * s + + * ( slice_at [f] ss + + sb 1 * r 3 ) cx * ( slice_at [f] ss + + sb 2 * r 3 ) cy * ( slice_at [f] ss + + sb 3 * r 3 ) d ( slice_at [f] ss + + sb 10 r ) )
        = r + r 1
    }
}

@ __ms_pct ( Vec f ) v f p → f {
    : i n ( vec_len [f] v )
    ? == n 0 { ^ 0.0 } {}
    : i k # i * p # f - n 1
    ^ ?? ( vec_get [f] v k ) { T x → x F → 0.0 }
}

// The 2nd–98th percentile of the views' points on each axis, padded by 2 %
// of the extent: the scene without its far outliers. F when no view has a
// valid pixel.
@ ms_auto_box Scene sc ( Slice f ) box → b {
    : i hw * . sc h . sc w
    : ( Vec f ) xs ( vec_new [f] )
    : ( Vec f ) ys ( vec_new [f] )
    : ( Vec f ) zs ( vec_new [f] )
    : ( Vec f ) p__v ( vec_zeroed [f] 3 )
    : ( Slice f ) p ( slice_from_vec [f] p__v )
    : ( Slice u ) m ( slice_from_vec [u] . sc mask )
    : ( Slice f32 ) dz ( slice_from_vec [f32] . sc dz )
    // a sample of the valid pixels, at a PRIME stride that does not divide
    // the width — so it is coprime to it and the rows' offsets sweep every
    // column (9 against 42 would see only every third); with nothing on
    // that lattice, every pixel
    : ~ i st 7
    ~ == 0 % . sc w st { = st ? == st 7 11 ? == st 11 13 ? == st 13 17 ? == st 17 19 + st 4 }
    : ~ i pass 0
    ~ & < pass 2 == ( vec_len [f] xs ) 0 {
        : i step ? == pass 0 st 1
        : ~ i v 0
        ~ < v . sc n {
            : ~ i j 0
            ~ < j hw {
                : i q + * v hw j
                ? != # i ( slice_at [u] m q ) 0 {
                    ( __ms_world sc v # f % j . sc w # f / j . sc w # f ( slice_at [f32] dz q ) p )
                    ( vec_push [f] xs ( slice_at [f] p 0 ) )
                    ( vec_push [f] ys ( slice_at [f] p 1 ) )
                    ( vec_push [f] zs ( slice_at [f] p 2 ) )
                } {}
                = j + j step
            }
            = v + v 1
        }
        = pass + pass 1
    }
    ? == ( vec_len [f] xs ) 0 { ^ F } {}
    ( sort_by [f] xs \ f a f b → i { ^ ? < a b -1 ? > a b 1 0 } )
    ( sort_by [f] ys \ f a f b → i { ^ ? < a b -1 ? > a b 1 0 } )
    ( sort_by [f] zs \ f a f b → i { ^ ? < a b -1 ? > a b 1 0 } )
    ( __ms_axis xs 0 box )
    ( __ms_axis ys 1 box )
    ( __ms_axis zs 2 box )
    ^ T
}

@ __ms_axis ( Vec f ) arr i ax ( Slice f ) box → v {
    : f lo ( __ms_pct arr 0.02 )
    : f hi ( __ms_pct arr 0.98 )
    : f pad * 0.02 - hi lo
    ( slice_put [f] box ax - lo pad )
    ( slice_put [f] box + 3 ax + hi pad )
}

// ── the edge-vertex table ───────────────────────────────────────────

// open addressing over i keys (≥ 0), value = vertex index
: MsTab {
    ( Vec i ) keys  // key + 1, 0 = empty
    ( Vec i ) vals
    i cap
    i n
}

@ __ms_tab_new → MsTab { ^ @ MsTab { ( vec_zeroed [i] 4096 ) ( vec_zeroed [i] 4096 ) 4096 0 } }

@ __ms_hash i k i msk → i { ^ & ^^ * & k 1073741823 2654435761 >> k 30 msk }

@ __ms_tab_grow inout MsTab t → v {
    : i ncap * . t cap 2
    : i msk - ncap 1
    : ( Vec i ) nk__v ( vec_zeroed [i] ncap )
    : ( Vec i ) nv__v ( vec_zeroed [i] ncap )
    : ( Slice i ) nk ( slice_from_vec [i] nk__v )
    : ( Slice i ) nv ( slice_from_vec [i] nv__v )
    : ( Slice i ) ok ( slice_from_vec [i] . t keys )
    : ( Slice i ) ov ( slice_from_vec [i] . t vals )
    : ~ i j 0
    ~ < j . t cap {
        : i k1 ( slice_at [i] ok j )
        ? != k1 0 {
            : ~ i h ( __ms_hash - k1 1 msk )
            ~ != ( slice_at [i] nk h ) 0 { = h & + h 1 msk }
            ( slice_put [i] nk h k1 )
            ( slice_put [i] nv h ( slice_at [i] ov j ) )
        } {}
        = j + j 1
    }
    = . t keys nk__v
    = . t vals nv__v
    = . t cap ncap
}

// the vertex for key k, or -1
@ __ms_tab_get MsTab t i k → i {
    : i msk - . t cap 1
    : ( Slice i ) ks ( slice_from_vec [i] . t keys )
    : ~ i h ( __ms_hash k msk )
    ~ T {
        : i e ( slice_at [i] ks h )
        ? == e 0 { ^ -1 } {}
        ? == e + k 1 { ^ ( slice_at [i] ( slice_from_vec [i] . t vals ) h ) } {}
        = h & + h 1 msk
    }
    ^ -1
}

@ __ms_tab_put inout MsTab t i k i val → v {
    ? > * + . t n 1 2 . t cap { ( __ms_tab_grow t ) } {}
    : i msk - . t cap 1
    : ~ i h ( __ms_hash k msk )
    ~ != ( slice_at [i] ( slice_from_vec [i] . t keys ) h ) 0 { = h & + h 1 msk }
    ( slice_put [i] ( slice_from_vec [i] . t keys ) h + k 1 )
    ( slice_put [i] ( slice_from_vec [i] . t vals ) h val )
    = . t n + . t n 1
}

// ── fusion and extraction ───────────────────────────────────────────

: MsGrid {
    i nx
    i ny
    i nz
    f vs
    f x0
    f y0
    f z0
    ( Vec f32 ) sdf
    ( Vec f32 ) wt
    ( Vec f32 ) cr
    ( Vec f32 ) cg
    ( Vec f32 ) cb
    ( Vec f32 ) cw
}

// the surface being built: vertices (x y z, r g b) and triangles
: MsSurf {
    ( Vec f ) vp
    ( Vec f ) vc
    ( Vec i ) tri
    MsTab tab
}

// The vertex on the grid edge between corners ga and gb (linear indices;
// the edge key is the lower corner and the corner-offset code).
@ __ms_edge_vertex inout MsSurf s MsGrid g i ga i gb i code → i {
    : i lo ? < ga gb ga gb
    : i hi ? < ga gb gb ga
    : i key + * lo 8 code
    : i got ( __ms_tab_get . s tab key )
    ? >= got 0 { ^ got } {}
    : ( Slice f32 ) sd ( slice_from_vec [f32] . g sdf )
    : f a # f ( slice_at [f32] sd lo )
    : f b # f ( slice_at [f32] sd hi )
    : f t ? == a b 0.5 / a - a b
    : i nxy * . g nx . g ny
    : f lx # f % lo . g nx
    : f ly # f % / lo . g nx . g ny
    : f lz # f / lo nxy
    : f hx # f % hi . g nx
    : f hy # f % / hi . g nx . g ny
    : f hz # f / hi nxy
    : f vs . g vs
    ( vec_push [f] . s vp + . g x0 * vs + lx * t - hx lx )
    ( vec_push [f] . s vp + . g y0 * vs + ly * t - hy ly )
    ( vec_push [f] . s vp + . g z0 * vs + lz * t - hz lz )
    // colour: the edge's ends, weighted by t, each only if it has one
    : ( Slice f32 ) cw ( slice_from_vec [f32] . g cw )
    : f wa ? > ( slice_at [f32] cw lo ) # f32 0.0 - 1.0 t 0.0
    : f wb ? > ( slice_at [f32] cw hi ) # f32 0.0 t 0.0
    : f ws + wa wb
    : ( Slice f32 ) cr ( slice_from_vec [f32] . g cr )
    : ( Slice f32 ) cg ( slice_from_vec [f32] . g cg )
    : ( Slice f32 ) cb ( slice_from_vec [f32] . g cb )
    ( vec_push [f] . s vc ? > ws 0.0 / + * wa # f ( slice_at [f32] cr lo ) * wb # f ( slice_at [f32] cr hi ) ws 128.0 )
    ( vec_push [f] . s vc ? > ws 0.0 / + * wa # f ( slice_at [f32] cg lo ) * wb # f ( slice_at [f32] cg hi ) ws 128.0 )
    ( vec_push [f] . s vc ? > ws 0.0 / + * wa # f ( slice_at [f32] cb lo ) * wb # f ( slice_at [f32] cb hi ) ws 128.0 )
    : i id - / ( vec_len [f] . s vp ) 3 1
    ( __ms_tab_put . s tab key id )
    ^ id
}

// The vertex on the edge between cube corners ka and kb (Freudenthal
// edges join a corner to one whose bits include its own: that is the low
// end, and ka ^ kb the edge's direction code).
@ __ms_ev inout MsSurf s MsGrid g ( Slice i ) gc i ka i kb → i {
    : i lo ? == & ka kb ka ka kb
    : i hi ? == lo ka kb ka
    ^ ( __ms_edge_vertex s g ( slice_at [i] gc lo ) ( slice_at [i] gc hi ) ^^ ka kb )
}

// One triangle, turned to face along `o` (from inside to outside).
@ __ms_emit inout MsSurf s i a i b i c f ox f oy f oz → v {
    : ( Slice f ) p ( slice_from_vec [f] . s vp )
    : f ux - ( slice_at [f] p * b 3 ) ( slice_at [f] p * a 3 )
    : f uy - ( slice_at [f] p + * b 3 1 ) ( slice_at [f] p + * a 3 1 )
    : f uz - ( slice_at [f] p + * b 3 2 ) ( slice_at [f] p + * a 3 2 )
    : f wx - ( slice_at [f] p * c 3 ) ( slice_at [f] p * a 3 )
    : f wy - ( slice_at [f] p + * c 3 1 ) ( slice_at [f] p + * a 3 1 )
    : f wz - ( slice_at [f] p + * c 3 2 ) ( slice_at [f] p + * a 3 2 )
    : f nx - * uy wz * uz wy
    : f ny - * uz wx * ux wz
    : f nz - * ux wy * uy wx
    ? == + + * nx nx * ny ny * nz nz 0.0 { ^ v } {}  // degenerate: skip
    ? < + + * nx ox * ny oy * nz oz 0.0 {
        ( vec_push [i] . s tri a ) ( vec_push [i] . s tri c ) ( vec_push [i] . s tri b )
    } {
        ( vec_push [i] . s tri a ) ( vec_push [i] . s tri b ) ( vec_push [i] . s tri c )
    }
}

@ __ms_find ( Slice i ) par i x → i {
    : ~ i r x
    ~ != ( slice_at [i] par r ) r { = r ( slice_at [i] par r ) }
    // path compression
    : ~ i y x
    ~ != ( slice_at [i] par y ) r {
        : i nxt ( slice_at [i] par y )
        ( slice_put [i] par y r )
        = y nxt
    }
    ^ r
}

@ ms_mesh Scene sc ( Slice f ) box i res f keep i verbose → !GlbMesh String {
    : f ex - ( slice_at [f] box 3 ) ( slice_at [f] box 0 )
    : f ey - ( slice_at [f] box 4 ) ( slice_at [f] box 1 )
    : f ez - ( slice_at [f] box 5 ) ( slice_at [f] box 2 )
    ? | | <= ex 0.0 <= ey 0.0 <= ez 0.0 { ^ @ !GlbMesh String { F ( string_from `map-anything mesh: the box is empty` ) } } {}
    : f longest ? > ex ? > ey ez ey ez ex ? > ey ez ey ez
    : f vs / longest # f ? < res 8 8 res
    : i nx + # i ( float_ceil / ex vs ) 1
    : i ny + # i ( float_ceil / ey vs ) 1
    : i nz + # i ( float_ceil / ez vs ) 1
    : i nvox * * nx ny nz
    ? > nvox 60000000 { ^ @ !GlbMesh String { F ( string_from `map-anything mesh: the grid is too large; lower --res` ) } } {}
    : f trunc * 4.0 vs
    ? != verbose 0 {
        ( nurl_print `grid    ` ) ( nurl_print ( nurl_str_int nx ) ) ( nurl_print `x` )
        ( nurl_print ( nurl_str_int ny ) ) ( nurl_print `x` ) ( nurl_print ( nurl_str_int nz ) )
        ( nurl_print ` points, ` ) ( nurl_print ( nurl_str_float / ( float_round * 10000.0 vs ) 10.0 ) )
        ( nurl_print ` mm cells\n` )
    } {}
    : ~ MsGrid g @ MsGrid { nx ny nz vs ( slice_at [f] box 0 ) ( slice_at [f] box 1 ) ( slice_at [f] box 2 )
        ( vec_zeroed [f32] nvox ) ( vec_zeroed [f32] nvox ) ( vec_zeroed [f32] nvox )
        ( vec_zeroed [f32] nvox ) ( vec_zeroed [f32] nvox ) ( vec_zeroed [f32] nvox ) }
    : ( Slice f32 ) sdf ( slice_from_vec [f32] . g sdf )
    : ( Slice f32 ) wt ( slice_from_vec [f32] . g wt )
    : ( Slice f32 ) gr ( slice_from_vec [f32] . g cr )
    : ( Slice f32 ) gg ( slice_from_vec [f32] . g cg )
    : ( Slice f32 ) gb ( slice_from_vec [f32] . g cb )
    : ( Slice f32 ) gcw ( slice_from_vec [f32] . g cw )
    : ( Slice f ) ss ( slice_from_vec [f] . sc sims )
    : ( Slice f ) kk ( slice_from_vec [f] . sc ks )
    : ( Slice f32 ) dz ( slice_from_vec [f32] . sc dz )
    : ( Slice u ) mk ( slice_from_vec [u] . sc mask )
    : ( Slice u ) rgb ( slice_from_vec [u] . sc rgb )
    : i w . sc w
    : i h . sc h
    : i hw * h w

    // ── integrate every view ──
    : ~ i v 0
    ~ < v . sc n {
        : i sb * v 13
        : i kb * v 4
        : f s ( slice_at [f] ss sb )
        // c = Rᵀ (X − t) / s = A X + b0
        : f a00 / ( slice_at [f] ss + sb 1 ) s
        : f a01 / ( slice_at [f] ss + sb 4 ) s
        : f a02 / ( slice_at [f] ss + sb 7 ) s
        : f a10 / ( slice_at [f] ss + sb 2 ) s
        : f a11 / ( slice_at [f] ss + sb 5 ) s
        : f a12 / ( slice_at [f] ss + sb 8 ) s
        : f a20 / ( slice_at [f] ss + sb 3 ) s
        : f a21 / ( slice_at [f] ss + sb 6 ) s
        : f a22 / ( slice_at [f] ss + sb 9 ) s
        : f tx ( slice_at [f] ss + sb 10 )
        : f ty ( slice_at [f] ss + sb 11 )
        : f tz ( slice_at [f] ss + sb 12 )
        : f fx ( slice_at [f] kk kb )
        : f fy ( slice_at [f] kk + kb 1 )
        : f px0 ( slice_at [f] kk + kb 2 )
        : f py0 ( slice_at [f] kk + kb 3 )
        : f sx * a00 vs
        : f sy * a10 vs
        : f sz * a20 vs
        : i vb * v hw
        : ~ i iz 0
        ~ < iz nz {
            : f zw - + . g z0 * # f iz vs tz
            : ~ i iy 0
            ~ < iy ny {
                : f yw - + . g y0 * # f iy vs ty
                : f xw - . g x0 tx
                : ~ f cx + + * a00 xw * a01 yw * a02 zw
                : ~ f cy + + * a10 xw * a11 yw * a12 zw
                : ~ f cz + + * a20 xw * a21 yw * a22 zw
                : i row * + * iz ny iy nx
                : ~ i ix 0
                ~ < ix nx {
                    ? > cz 0.000001 {
                        : i u # i ( float_floor + + * fx / cx cz px0 0.5 )
                        : i vv # i ( float_floor + + * fy / cy cz py0 0.5 )
                        ? & & & >= u 0 < u w >= vv 0 < vv h {
                            : i q + vb + * vv w u
                            ? != # i ( slice_at [u] mk q ) 0 {
                                // the residual in world metres: the camera
                                // frame is the world's divided by s
                                : f d * s - # f ( slice_at [f32] dz q ) cz
                                ? >= d - 0.0 trunc {
                                    : i gi + row ix
                                    : f tv ? > d trunc 1.0 / d trunc
                                    : f w0 # f ( slice_at [f32] wt gi )
                                    ( slice_put [f32] sdf gi # f32 / + * # f ( slice_at [f32] sdf gi ) w0 tv + w0 1.0 )
                                    ( slice_put [f32] wt gi # f32 + w0 1.0 )
                                    ? < d trunc {
                                        : f c0 # f ( slice_at [f32] gcw gi )
                                        : f c1 + c0 1.0
                                        : i pj + * vv w u
                                        : i cb + * * v 3 hw pj
                                        ( slice_put [f32] gr gi # f32 / + * # f ( slice_at [f32] gr gi ) c0 # f ( slice_at [u] rgb cb ) c1 )
                                        ( slice_put [f32] gg gi # f32 / + * # f ( slice_at [f32] gg gi ) c0 # f ( slice_at [u] rgb + cb hw ) c1 )
                                        ( slice_put [f32] gb gi # f32 / + * # f ( slice_at [f32] gb gi ) c0 # f ( slice_at [u] rgb + cb * 2 hw ) c1 )
                                        ( slice_put [f32] gcw gi # f32 c1 )
                                    } {}
                                } {}
                            } {}
                        } {}
                    } {}
                    = cx + cx sx
                    = cy + cy sy
                    = cz + cz sz
                    = ix + ix 1
                }
                = iy + iy 1
            }
            = iz + iz 1
        }
        ? != verbose 0 {
            ( nurl_print `fuse    view ` ) ( nurl_print ( nurl_str_int + v 1 ) )
            ( nurl_print `/` ) ( nurl_print ( nurl_str_int . sc n ) ) ( nurl_print `\r` )
        } {}
        = v + v 1
    }
    ? != verbose 0 { ( nurl_print `\n` ) } {}

    // ── marching tetrahedra ──
    : ~ MsSurf su @ MsSurf { ( vec_new [f] ) ( vec_new [f] ) ( vec_new [i] ) ( __ms_tab_new ) }
    // Freudenthal: six tetrahedra around the diagonal from corner 0 to 7
    // (corner k = (k & 1, k >> 1 & 1, k >> 2 & 1))
    : ( Vec i ) tets__v ( vec_new [i] )
    ( vec_push [i] tets__v 0 ) ( vec_push [i] tets__v 7 ) ( vec_push [i] tets__v 1 ) ( vec_push [i] tets__v 3 )
    ( vec_push [i] tets__v 0 ) ( vec_push [i] tets__v 7 ) ( vec_push [i] tets__v 3 ) ( vec_push [i] tets__v 2 )
    ( vec_push [i] tets__v 0 ) ( vec_push [i] tets__v 7 ) ( vec_push [i] tets__v 2 ) ( vec_push [i] tets__v 6 )
    ( vec_push [i] tets__v 0 ) ( vec_push [i] tets__v 7 ) ( vec_push [i] tets__v 6 ) ( vec_push [i] tets__v 4 )
    ( vec_push [i] tets__v 0 ) ( vec_push [i] tets__v 7 ) ( vec_push [i] tets__v 4 ) ( vec_push [i] tets__v 5 )
    ( vec_push [i] tets__v 0 ) ( vec_push [i] tets__v 7 ) ( vec_push [i] tets__v 5 ) ( vec_push [i] tets__v 1 )
    : ( Slice i ) tets ( slice_from_vec [i] tets__v )
    : i nxy * nx ny
    : ( Vec i ) gc__v ( vec_zeroed [i] 8 )
    : ( Slice i ) gc ( slice_from_vec [i] gc__v )
    : ( Vec f ) sv__v ( vec_zeroed [f] 8 )
    : ( Slice f ) sv ( slice_from_vec [f] sv__v )
    : ( Vec i ) ins__v ( vec_zeroed [i] 4 )
    : ( Slice i ) ins ( slice_from_vec [i] ins__v )
    : ( Vec i ) outs__v ( vec_zeroed [i] 4 )
    : ( Slice i ) outs ( slice_from_vec [i] outs__v )
    : ~ i mz 0
    ~ < mz - nz 1 {
        : ~ i my 0
        ~ < my - ny 1 {
            : ~ i mx 0
            ~ < mx - nx 1 {
                : i g0 + + * mz nxy * my nx mx
                : ~ b seen T
                : ~ i npos 0
                : ~ i k 0
                ~ & seen < k 8 {
                    : i gk + + + g0 & k 1 * & >> k 1 1 nx * & >> k 2 1 nxy
                    ( slice_put [i] gc k gk )
                    ? > ( slice_at [f32] wt gk ) # f32 0.0 {
                        : f val # f ( slice_at [f32] sdf gk )
                        ( slice_put [f] sv k val )
                        ? >= val 0.0 { = npos + npos 1 } {}
                    } { = seen F }
                    = k + k 1
                }
                ? & & seen > npos 0 < npos 8 {
                    : ~ i t 0
                    ~ < t 6 {
                        : ~ i nin 0
                        : ~ i nout 0
                        : ~ f ox 0.0
                        : ~ f oy 0.0
                        : ~ f oz 0.0
                        : ~ f ix0 0.0
                        : ~ f iy0 0.0
                        : ~ f iz0 0.0
                        : ~ i e 0
                        ~ < e 4 {
                            : i ck ( slice_at [i] tets + * t 4 e )
                            : f cxk # f & ck 1
                            : f cyk # f & >> ck 1 1
                            : f czk # f & >> ck 2 1
                            ? < ( slice_at [f] sv ck ) 0.0 {
                                ( slice_put [i] ins nin ck ) = nin + nin 1
                                = ix0 + ix0 cxk = iy0 + iy0 cyk = iz0 + iz0 czk
                            } {
                                ( slice_put [i] outs nout ck ) = nout + nout 1
                                = ox + ox cxk = oy + oy cyk = oz + oz czk
                            }
                            = e + e 1
                        }
                        ? & > nin 0 > nout 0 {
                            // inside → outside: the difference of the means
                            = ox - / ox # f nout / ix0 # f nin
                            = oy - / oy # f nout / iy0 # f nin
                            = oz - / oz # f nout / iz0 # f nin
                            ? == nin 1 {
                                : i a ( __ms_ev su g gc ( slice_at [i] ins 0 ) ( slice_at [i] outs 0 ) )
                                : i b ( __ms_ev su g gc ( slice_at [i] ins 0 ) ( slice_at [i] outs 1 ) )
                                : i c ( __ms_ev su g gc ( slice_at [i] ins 0 ) ( slice_at [i] outs 2 ) )
                                ( __ms_emit su a b c ox oy oz )
                            } {
                                ? == nin 3 {
                                    : i a ( __ms_ev su g gc ( slice_at [i] ins 0 ) ( slice_at [i] outs 0 ) )
                                    : i b ( __ms_ev su g gc ( slice_at [i] ins 1 ) ( slice_at [i] outs 0 ) )
                                    : i c ( __ms_ev su g gc ( slice_at [i] ins 2 ) ( slice_at [i] outs 0 ) )
                                    ( __ms_emit su a b c ox oy oz )
                                } {
                                    // two in, two out: a quad
                                    : i ac ( __ms_ev su g gc ( slice_at [i] ins 0 ) ( slice_at [i] outs 0 ) )
                                    : i ad ( __ms_ev su g gc ( slice_at [i] ins 0 ) ( slice_at [i] outs 1 ) )
                                    : i bd ( __ms_ev su g gc ( slice_at [i] ins 1 ) ( slice_at [i] outs 1 ) )
                                    : i bc ( __ms_ev su g gc ( slice_at [i] ins 1 ) ( slice_at [i] outs 0 ) )
                                    ( __ms_emit su ac ad bd ox oy oz )
                                    ( __ms_emit su ac bd bc ox oy oz )
                                }
                            }
                        } {}
                        = t + t 1
                    }
                } {}
                = mx + mx 1
            }
            = my + my 1
        }
        = mz + mz 1
    }
    : i nv0 / ( vec_len [f] . su vp ) 3
    : i nt0 / ( vec_len [i] . su tri ) 3
    ? == nt0 0 { ^ @ !GlbMesh String { F ( string_from `map-anything mesh: no surface in the box (is it around the object?)` ) } } {}

    // ── drop the loose bits ──
    : ( Vec i ) par__v ( vec_zeroed [i] nv0 )
    : ( Slice i ) par ( slice_from_vec [i] par__v )
    : ~ i j 0
    ~ < j nv0 { ( slice_put [i] par j j ) = j + j 1 }
    : ( Slice i ) tr ( slice_from_vec [i] . su tri )
    = j 0
    ~ < j nt0 {
        : i ra ( __ms_find par ( slice_at [i] tr * j 3 ) )
        : i rb ( __ms_find par ( slice_at [i] tr + * j 3 1 ) )
        : i rc ( __ms_find par ( slice_at [i] tr + * j 3 2 ) )
        ? != ra rb { ( slice_put [i] par rb ra ) } {}
        : i ra2 ( __ms_find par ra )
        ? != ra2 rc { ( slice_put [i] par rc ra2 ) } {}
        = j + j 1
    }
    : ( Vec i ) cnt__v ( vec_zeroed [i] nv0 )
    : ( Slice i ) cnt ( slice_from_vec [i] cnt__v )
    : ~ i big 0
    = j 0
    ~ < j nt0 {
        : i r ( __ms_find par ( slice_at [i] tr * j 3 ) )
        ( slice_put [i] cnt r + ( slice_at [i] cnt r ) 1 )
        ? > ( slice_at [i] cnt r ) big { = big ( slice_at [i] cnt r ) } {}
        = j + j 1
    }
    : i need # i * keep # f big

    // ── normals, the frame change, the mesh ──
    : ( Vec f ) nrm__v ( vec_zeroed [f] * 3 nv0 )
    : ( Slice f ) nrm ( slice_from_vec [f] nrm__v )
    : ( Slice f ) vp ( slice_from_vec [f] . su vp )
    : ( Slice f ) vc ( slice_from_vec [f] . su vc )
    : ( Vec i ) remap__v ( vec_zeroed [i] nv0 )
    : ( Slice i ) remap ( slice_from_vec [i] remap__v )
    = j 0
    ~ < j nv0 { ( slice_put [i] remap j -1 ) = j + j 1 }
    : ~ i kept 0
    = j 0
    ~ < j nt0 {
        : i r ( __ms_find par ( slice_at [i] tr * j 3 ) )
        ? >= ( slice_at [i] cnt r ) need {
            : i a ( slice_at [i] tr * j 3 )
            : i b ( slice_at [i] tr + * j 3 1 )
            : i c ( slice_at [i] tr + * j 3 2 )
            : f ux - ( slice_at [f] vp * b 3 ) ( slice_at [f] vp * a 3 )
            : f uy - ( slice_at [f] vp + * b 3 1 ) ( slice_at [f] vp + * a 3 1 )
            : f uz - ( slice_at [f] vp + * b 3 2 ) ( slice_at [f] vp + * a 3 2 )
            : f wx - ( slice_at [f] vp * c 3 ) ( slice_at [f] vp * a 3 )
            : f wy - ( slice_at [f] vp + * c 3 1 ) ( slice_at [f] vp + * a 3 1 )
            : f wz - ( slice_at [f] vp + * c 3 2 ) ( slice_at [f] vp + * a 3 2 )
            : f nx2 - * uy wz * uz wy
            : f ny2 - * uz wx * ux wz
            : f nz2 - * ux wy * uy wx
            : ~ i e 0
            ~ < e 3 {
                : i q ( slice_at [i] tr + * j 3 e )
                ( slice_put [f] nrm * q 3 + ( slice_at [f] nrm * q 3 ) nx2 )
                ( slice_put [f] nrm + * q 3 1 + ( slice_at [f] nrm + * q 3 1 ) ny2 )
                ( slice_put [f] nrm + * q 3 2 + ( slice_at [f] nrm + * q 3 2 ) nz2 )
                = e + e 1
            }
            = kept + kept 1
        } {}
        = j + j 1
    }
    : f ccx * 0.5 + ( slice_at [f] box 0 ) ( slice_at [f] box 3 )
    : f ccy * 0.5 + ( slice_at [f] box 1 ) ( slice_at [f] box 4 )
    : f ccz * 0.5 + ( slice_at [f] box 2 ) ( slice_at [f] box 5 )
    : ~ GlbMesh m ( glb_mesh_new )
    = j 0
    ~ < j nt0 {
        : i r ( __ms_find par ( slice_at [i] tr * j 3 ) )
        ? >= ( slice_at [i] cnt r ) need {
            : ~ i e 0
            : ( Vec i ) ids ( vec_new [i] )
            ~ < e 3 {
                : i q ( slice_at [i] tr + * j 3 e )
                ? < ( slice_at [i] remap q ) 0 {
                    : i nid ( glb_vertex m - ( slice_at [f] vp * q 3 ) ccx - 0.0 - ( slice_at [f] vp + * q 3 1 ) ccy - 0.0 - ( slice_at [f] vp + * q 3 2 ) ccz )
                    ( glb_normal m ( slice_at [f] nrm * q 3 ) - 0.0 ( slice_at [f] nrm + * q 3 1 ) - 0.0 ( slice_at [f] nrm + * q 3 2 ) )
                    ( glb_color m # i + ( slice_at [f] vc * q 3 ) 0.5 # i + ( slice_at [f] vc + * q 3 1 ) 0.5 # i + ( slice_at [f] vc + * q 3 2 ) 0.5 255 )
                    ( slice_put [i] remap q nid )
                } {}
                ( vec_push [i] ids ( slice_at [i] remap q ) )
                = e + e 1
            }
            : ( Slice i ) is ( slice_from_vec [i] ids )
            ( glb_tri m ( slice_at [i] is 0 ) ( slice_at [i] is 1 ) ( slice_at [i] is 2 ) )
        } {}
        = j + j 1
    }
    ? != verbose 0 {
        ( nurl_print `surface ` ) ( nurl_print ( nurl_str_int nt0 ) )
        ( nurl_print ` triangles, ` ) ( nurl_print ( nurl_str_int kept ) )
        ( nurl_print ` kept in the pieces of at least ` ) ( nurl_print ( nurl_str_int need ) )
        ( nurl_print ` (` ) ( nurl_print ( nurl_str_int ( glb_vertex_count m ) ) )
        ( nurl_print ` vertices)\n` )
    } {}
    ^ @ !GlbMesh String { T m }
}

// ── the subcommand ──────────────────────────────────────────────────

@ __ms_usage → v {
    ( nurl_print `usage: map-anything mesh <scene> -o <object.glb> [options]\n\n` )
    ( nurl_print `  A 3-D object (.glb) from the views a run kept with --scene: TSDF\n` )
    ( nurl_print `  fusion of their depths inside a box, then the zero surface.\n\n` )
    ( nurl_print `  -o, --out FILE           the object (default object.glb)\n` )
    ( nurl_print `  --box x0 y0 z0 x1 y1 z1  the region, in the point cloud's coordinates\n` )
    ( nurl_print `                           (default: the scene without its 2 % outliers)\n` )
    ( nurl_print `  --res N                  grid cells along the box's longest side (default 256)\n` )
    ( nurl_print `  --keep F                 drop pieces smaller than F x the largest (default 0.02)\n` )
    ( nurl_print `  -q, --quiet              only errors\n` )
}

@ __ms_eq s a s b → b { ^ == 0 ( nurl_str_cmp a b ) }

// A decimal, possibly negative (the box is in world coordinates).
@ __ms_num s a → b {
    : ( Slice u ) bs ( slice_of_str a )
    : i n ( slice_len [u] bs )
    : ~ i k ? & > n 0 == ( slice_byte bs 0 ) 45 1 0
    ? >= k n { ^ F } {}
    : ~ i dots 0
    : ~ i digits 0
    ~ < k n {
        : i c ( slice_byte bs k )
        ? == c 46 { = dots + dots 1 } {
            ? & >= c 48 <= c 57 { = digits + digits 1 } { ^ F }
        }
        = k + k 1
    }
    ^ & <= dots 1 > digits 0
}

// `map-anything mesh ...` — argv[1] is "mesh". Returns the exit code.
@ ms_main → i {
    : i argc ( nurl_argc )
    : ~ s scene ``
    : ~ s out `object.glb`
    : ~ i res 256
    : ~ f keep 0.02
    : ~ i verbose 1
    : ~ b hasbox F
    : ( Vec f ) box__v ( vec_zeroed [f] 6 )
    : ( Slice f ) box ( slice_from_vec [f] box__v )
    : ~ i k 2
    ~ < k argc {
        : s a ( nurl_argv k )
        : b has < + k 1 argc
        ? & | ( __ms_eq a `-o` ) ( __ms_eq a `--out` ) has { = out ( nurl_argv + k 1 ) = k + k 1 } {
            ? & ( __ms_eq a `--res` ) has { = res ( nurl_str_to_int ( nurl_argv + k 1 ) ) = k + k 1 } {
                ? & ( __ms_eq a `--keep` ) has {
                    ? ( __ms_num ( nurl_argv + k 1 ) ) { = keep ( nurl_str_to_float ( nurl_argv + k 1 ) ) } {
                        ( nurl_print `map-anything mesh: --keep wants a number\n` ) ^ 1
                    }
                    = k + k 1
                } {
                    ? ( __ms_eq a `--box` ) {
                        ? < + k 6 argc {} { ( nurl_print `map-anything mesh: --box wants six numbers\n` ) ^ 1 }
                        : ~ i j 0
                        ~ < j 6 {
                            : s t ( nurl_argv + + k 1 j )
                            ? ( __ms_num t ) { ( slice_put [f] box j ( nurl_str_to_float t ) ) } {
                                ( nurl_print `map-anything mesh: --box wants six numbers, got ` ) ( nurl_print t ) ( nurl_print `\n` )
                                ^ 1
                            }
                            = j + j 1
                        }
                        = hasbox T
                        = k + k 6
                    } {
                        ? | ( __ms_eq a `-q` ) ( __ms_eq a `--quiet` ) { = verbose 0 } {
                            ? | ( __ms_eq a `-h` ) ( __ms_eq a `--help` ) { ( __ms_usage ) ^ 0 } {
                                ? & > ( nurl_str_len a ) 0 != ( nurl_str_get a 0 ) 45 {
                                    = scene a
                                } {
                                    ( nurl_print `map-anything mesh: unknown option ` ) ( nurl_print a ) ( nurl_print `\n\n` )
                                    ( __ms_usage )
                                    ^ 1
                                }
                            }
                        }
                    }
                }
            }
        }
        = k + k 1
    }
    ? == ( nurl_str_len scene ) 0 { ( __ms_usage ) ^ 1 } {}
    ? | < res 8 > res 1024 { ( nurl_print `map-anything mesh: --res wants 8..1024\n` ) ^ 1 } {}
    : Scene sc ?? ( sc_load scene ) {
        T x → x
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ^ 1 }
    }
    ? != verbose 0 {
        ( nurl_print `scene   ` ) ( nurl_print scene ) ( nurl_print `  ` )
        ( nurl_print ( nurl_str_int . sc n ) ) ( nurl_print ` views @ ` )
        ( nurl_print ( nurl_str_int . sc w ) ) ( nurl_print `x` ) ( nurl_print ( nurl_str_int . sc h ) ) ( nurl_print `\n` )
    } {}
    ? hasbox {
        : ~ i ax 0
        ~ < ax 3 {
            ? > ( slice_at [f] box ax ) ( slice_at [f] box + ax 3 ) {
                : f t ( slice_at [f] box ax )
                ( slice_put [f] box ax ( slice_at [f] box + ax 3 ) )
                ( slice_put [f] box + ax 3 t )
            } {}
            = ax + ax 1
        }
    } {
        ? ( ms_auto_box sc box ) {} { ( nurl_print `map-anything mesh: the scene has no valid pixel\n` ) ^ 1 }
    }
    ? != verbose 0 {
        ( nurl_print `box     ` )
        : ~ i j 0
        ~ < j 6 { ( nurl_print ( nurl_str_float / ( float_round * 1000.0 ( slice_at [f] box j ) ) 1000.0 ) ) ( nurl_print ` ` ) = j + j 1 }
        ( nurl_print `\n` )
    } {}
    ?? ( ms_mesh sc box res keep verbose ) {
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ^ 1 }
        T m → {
            ?? ( glb_write m out `map-anything mesh, pure NURL` ) {
                F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ^ 1 }
                T _ → {
                    ? != verbose 0 {
                        ( nurl_print `wrote   ` ) ( nurl_print out ) ( nurl_print ` (` )
                        ( nurl_print ( nurl_str_int ( glb_tri_count m ) ) ) ( nurl_print ` triangles)\n` )
                    } {}
                }
            }
        }
    }
    ^ 0
}
