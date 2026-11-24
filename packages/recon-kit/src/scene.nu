// packages/recon-kit/src/scene.nu — the reconstruction's views, kept.
//
// A point cloud throws away what made it: which camera saw which pixel at
// what depth. A mesh wants exactly that (TSDF fusion carves free space
// along each camera's rays), so a run asked for `--scene FILE` keeps, for
// every view it emits:
//
//   the camera as a similarity, world = s·R·c + t (sim3: s | R 9 | t 3,
//     with the view alignment AND the window stitch folded in — the frame
//     the PLY's points are in), the pinhole fitted to its rays (fx fy cx
//     cy), the camera-frame z-depth per pixel, the pixel mask after every
//     filter, and the colours.
//
// File: little-endian, "MAS1" h w, then per view "VIEW" sim3 (13 f64) k
// (4 f64) depth (h·w f32) mask (h·w u8) rgb (3·h·w u8, planar), and a
// trailer "MEND" n. The count is at the end so the writer never seeks, and
// a file cut short (a run killed mid-write) has no trailer and is refused.
//
//   ( sc_create path h w )                               → !ScW String
//   ( sc_view sw sim k dz dzoff mask moff rgb )          → b
//   ( sc_finish sw )                                     → b
//   ( sc_load path )                                     → !Scene String

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`

: i SC_MAGIC 827539789  // "MAS1"
: i SC_VIEW 1464158550  // "VIEW"
: i SC_END 1145980237  // "MEND"

: ScW {
    File f
    i h
    i w
    i n
    b ok
}

: Scene {
    i n
    i h
    i w
    ( Vec f ) sims  // 13 per view
    ( Vec f ) ks  // 4 per view
    ( Vec f32 ) dz  // h·w per view
    ( Vec u ) mask  // h·w per view
    ( Vec u ) rgb  // 3·h·w per view, planar
}

@ __sc_u32 ( Vec u ) b i v → v { ( bytes_push_u32_le b # u32 v ) }

@ sc_create s path i h i w → !ScW String {
    ?? ( file_create path ) {
        F _e → {
            : String m ( string_from `cannot create the scene file ` )
            ( string_push_str m path )
            ^ @ !ScW String { F m }
        }
        T f → {
            : ( Vec u ) b ( vec_new [u] )
            ( __sc_u32 b SC_MAGIC ) ( __sc_u32 b h ) ( __sc_u32 b w )
            : ~ b ok T
            ?? ( file_write_chunk f b ) { T _ → {} F _e → { = ok F } }
            ^ @ !ScW String { T @ ScW { f h w 0 ok } }
        }
    }
}

// One view. `dz` and `mask` are read from offset dzoff / moff (a window's
// buffers hold several views); `rgb` is the view's own [0,1] planar frame.
@ sc_view inout ScW sw ( Slice f ) sim ( Slice f ) k ( Slice f ) dz i dzoff ( Slice u ) mask i moff ( Slice f ) rgb → b {
    : i hw * . sw h . sw w
    : ( Vec u ) b ( vec_with_cap [u] + 140 * hw 8 )
    ( __sc_u32 b SC_VIEW )
    : ~ i j 0
    ~ < j 13 { ( bytes_push_f64_le b ( slice_at [f] sim j ) ) = j + j 1 }
    = j 0
    ~ < j 4 { ( bytes_push_f64_le b ( slice_at [f] k j ) ) = j + j 1 }
    = j 0
    ~ < j hw { ( bytes_push_f32_le b # f32 ( slice_at [f] dz + dzoff j ) ) = j + j 1 }
    = j 0
    ~ < j hw { ( vec_push [u] b ( slice_at [u] mask + moff j ) ) = j + j 1 }
    = j 0
    ~ < j * 3 hw {
        : f c * ( slice_at [f] rgb j ) 255.0
        ( vec_push [u] b # u ? < c 0.0 0 ? > c 255.0 255 # i + c 0.5 )
        = j + j 1
    }
    ?? ( file_write_chunk . sw f b ) { T _ → {} F _e → { = . sw ok F } }
    = . sw n + . sw n 1
    ^ . sw ok
}

@ sc_finish ScW sw → b {
    : ( Vec u ) b ( vec_new [u] )
    ( __sc_u32 b SC_END ) ( __sc_u32 b . sw n )
    : ~ b ok . sw ok
    ?? ( file_write_chunk . sw f b ) { T _ → {} F _e → { = ok F } }
    ( file_close . sw f )
    ^ ok
}

@ __sc_rd32 ( Slice u ) b i off → i {
    ^ + + + ( slice_byte b off ) * 256 ( slice_byte b + off 1 ) * 65536 ( slice_byte b + off 2 ) * 16777216 ( slice_byte b + off 3 )
}

@ __sc_rdf64 ( Slice u ) b i off → f {
    : i lo ( __sc_rd32 b off )
    : i hi ( __sc_rd32 b + off 4 )
    // a shift, not a multiply: the top word of a negative double has its
    // sign bit set, and hi × 2^32 would overflow
    ^ ( bits_to_f64 | lo << hi 32 )
}

@ __sc_bad s why → !Scene String {
    : String m ( string_from `not a usable scene file: ` )
    ( string_push_str m why )
    ^ @ !Scene String { F m }
}

@ sc_load s path → !Scene String {
    : ~ ( Vec u ) raw ( vec_new [u] )
    ?? ( read_file_bytes path ) {
        T v → { = raw v }
        F _e → {
            : String m ( string_from `cannot read ` )
            ( string_push_str m path )
            ^ @ !Scene String { F m }
        }
    }
    : ( Slice u ) b ( slice_from_vec [u] raw )
    : i len ( slice_len [u] b )
    ? < len 20 { ^ ( __sc_bad `too short` ) } {}
    ? != ( __sc_rd32 b 0 ) SC_MAGIC { ^ ( __sc_bad `wrong magic` ) } {}
    ? != ( __sc_rd32 b - len 8 ) SC_END { ^ ( __sc_bad `no trailer (the run did not finish writing it)` ) } {}
    : i n ( __sc_rd32 b - len 4 )
    : i h ( __sc_rd32 b 4 )
    : i w ( __sc_rd32 b 8 )
    // the dimensions against the payload before any product of them, so a
    // forged header cannot wrap h·w and pass the size check
    ? | | | < n 1 < h 1 < w 1 < len 160 { ^ ( __sc_bad `the header is empty` ) } {}
    ? > h / / - len 160 8 w { ^ ( __sc_bad `the header claims more pixels than the file holds` ) } {}
    : i hw * h w
    : i per + + 4 136 * hw 8
    ? | | <= n 0 <= hw 0 != len + + 12 * n per 8 { ^ ( __sc_bad `the size does not match its header` ) } {}
    : ( Vec f ) sims ( vec_with_cap [f] * 13 n )
    : ( Vec f ) ks ( vec_with_cap [f] * 4 n )
    : ( Vec f32 ) dz ( vec_with_cap [f32] * n hw )
    : ( Vec u ) mask ( vec_with_cap [u] * n hw )
    : ( Vec u ) rgb ( vec_with_cap [u] * * 3 n hw )
    : ~ i v 0
    ~ < v n {
        : i o + 12 * v per
        ? != ( __sc_rd32 b o ) SC_VIEW { ^ ( __sc_bad `a view block is out of place` ) } {}
        : ~ i j 0
        ~ < j 13 { ( vec_push [f] sims ( __sc_rdf64 b + + o 4 * j 8 ) ) = j + j 1 }
        = j 0
        ~ < j 4 { ( vec_push [f] ks ( __sc_rdf64 b + + o 108 * j 8 ) ) = j + j 1 }
        : i od + o 140
        = j 0
        ~ < j hw { ( vec_push [f32] dz ( bits_to_f32 ( __sc_rd32 b + od * j 4 ) ) ) = j + j 1 }
        : i om + od * hw 4
        = j 0
        ~ < j hw { ( vec_push [u] mask ( slice_at [u] b + om j ) ) = j + j 1 }
        : i oc + om hw
        = j 0
        ~ < j * 3 hw { ( vec_push [u] rgb ( slice_at [u] b + oc j ) ) = j + j 1 }
        = v + v 1
    }
    ^ @ !Scene String { T @ Scene { n h w sims ks dz mask rgb } }
}
