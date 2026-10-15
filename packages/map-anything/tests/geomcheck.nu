// tests/geomcheck.nu — geometry + masks against the reference.
// Reads dirs/depth/pose/logits.bin, normalises the rays the way the DPT
// adaptor does, runs gm_world_points + gm_nonambig + gm_edge_mask, and
// writes nurl_pts.bin (f32 [H,W,3]) and nurl_mask.bin (u8 [H,W]).
//
//   geomcheck <dir> <H> <W>

$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `src/geom.nu`

: f GC_SCALE 1.7

@ __gc_die s msg → i {
    ( puts msg )
    ^ 1
}

// The `n` f32s of `dir/name` as f64s; empty when the file is missing or
// the wrong size.
@ __gc_read s dir s name i n → ( Vec f ) {
    : String p ( string_from dir )
    ( string_push_str p name )
    ?? ( read_file_bytes ( string_data p ) ) {
        F → {}
        T raw → {
            ? == ( vec_len [u] raw ) * n 4 {
                : ( Vec f ) out ( vec_zeroed [f] n )
                : ( Slice f ) op ( slice_from_vec [f] out )
                : ( Slice u ) rp ( slice_from_vec [u] raw )
                : ~ i j 0
                ~ < j n {
                    : i o * j 4
                    : i bits | # i ( slice_at [u] rp o ) | << # i ( slice_at [u] rp + o 1 ) 8 | << # i ( slice_at [u] rp + o 2 ) 16 << # i ( slice_at [u] rp + o 3 ) 24
                    ( slice_put [f] op j # f ( bits_to_f32 bits ) )
                    = j + j 1
                }
                ^ out
            } {}
        }
    }
    ^ ( vec_new [f] )
}

@ main → i {
    ? < ( nurl_argc ) 4 { ^ ( __gc_die `usage: geomcheck <dir> <H> <W>` ) } {}
    : s dir ( nurl_argv 1 )
    : i h ( nurl_str_to_int ( nurl_argv 2 ) )
    : i w ( nurl_str_to_int ( nurl_argv 3 ) )
    : i n * h w

    : ( Vec f ) dirs_v ( __gc_read dir `/dirs.bin` * 3 n )
    : ( Vec f ) depth_v ( __gc_read dir `/depth.bin` n )
    : ( Vec f ) pose_v ( __gc_read dir `/pose.bin` 7 )
    : ( Vec f ) logits_v ( __gc_read dir `/logits.bin` n )
    ? & & & > ( vec_len [f] dirs_v ) 0 > ( vec_len [f] depth_v ) 0 > ( vec_len [f] pose_v ) 0 > ( vec_len [f] logits_v ) 0 {} {
        ^ ( __gc_die `cannot read inputs` )
    }
    : ( Slice f ) dirs ( slice_from_vec [f] dirs_v )
    : ( Slice f ) depth ( slice_from_vec [f] depth_v )
    : ( Slice f ) pose ( slice_from_vec [f] pose_v )
    : ( Slice f ) logits ( slice_from_vec [f] logits_v )

    // unit-sphere normalise, as the DPT adaptor does (clip 1e-8)
    : ~ i j 0
    ~ < j n {
        : f x ( slice_at [f] dirs j )
        : f y ( slice_at [f] dirs + n j )
        : f z ( slice_at [f] dirs + * 2 n j )
        : ~ f nn ( float_sqrt + + * x x * y y * z z )
        ? < nn 0.00000001 { = nn 0.00000001 } {}
        ( slice_put [f] dirs j / x nn )
        ( slice_put [f] dirs + n j / y nn )
        ( slice_put [f] dirs + * 2 n j / z nn )
        = j + j 1
    }

    // the head normalises the quaternion before it hands the pose over
    : f qx ( slice_at [f] pose 3 )
    : f qy ( slice_at [f] pose 4 )
    : f qz ( slice_at [f] pose 5 )
    : f qw ( slice_at [f] pose 6 )
    : ~ f qn ( float_sqrt + + + * qx qx * qy qy * qz qz * qw qw )
    ? < qn 0.00000001 { = qn 0.00000001 } {}
    ( slice_put [f] pose 3 / qx qn )
    ( slice_put [f] pose 4 / qy qn )
    ( slice_put [f] pose 5 / qz qn )
    ( slice_put [f] pose 6 / qw qn )

    : ( Vec f ) pts__v ( vec_zeroed [f] * 3 n )
    : ( Slice f ) pts ( slice_from_vec [f] pts__v )
    : ( Vec f ) depthz__v ( vec_zeroed [f] n )
    : ( Slice f ) depthz ( slice_from_vec [f] depthz__v )
    ( gm_world_points dirs depth pose GC_SCALE n pts depthz )
    : ( Vec u ) mask__v ( vec_zeroed [u] n )
    : ( Slice u ) mask ( slice_from_vec [u] mask__v )
    ( gm_nonambig logits n mask )
    ( gm_edge_mask pts depthz h w mask )

    // dump pts as f32 and mask as u8
    : ( Vec u ) pout ( vec_zeroed [u] * * 3 n 4 )
    : ( Slice u ) pp ( slice_from_vec [u] pout )
    = j 0
    ~ < j * 3 n {
        : i bits # i ( f32_to_bits # f32 ( slice_at [f] pts j ) )
        : i o * j 4
        ( slice_put [u] pp o # u & bits 255 )
        ( slice_put [u] pp + o 1 # u & >> bits 8 255 )
        ( slice_put [u] pp + o 2 # u & >> bits 16 255 )
        ( slice_put [u] pp + o 3 # u & >> bits 24 255 )
        = j + j 1
    }
    : String p1 ( string_from dir )
    ( string_push_str p1 `/nurl_pts.bin` )
    ?? ( write_file_bytes ( string_data p1 ) pout ) {
        T → {}
        F → { ^ ( __gc_die `write pts` ) }
    }
    : ( Vec u ) mout ( vec_with_cap [u] n )
    = j 0
    ~ < j n { ( vec_push [u] mout ( slice_at [u] mask j ) ) = j + j 1 }
    : String p2 ( string_from dir )
    ( string_push_str p2 `/nurl_mask.bin` )
    ?? ( write_file_bytes ( string_data p2 ) mout ) {
        T → {}
        F → { ^ ( __gc_die `write mask` ) }
    }
    ( puts `wrote nurl_pts/mask.bin` )
    ^ 0
}
