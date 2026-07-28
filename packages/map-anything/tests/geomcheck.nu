// tests/geomcheck.nu — geometry + masks against the reference.
// Reads dirs/depth/pose/logits.bin, normalises the rays the way the DPT
// adaptor does, runs gm_world_points + gm_nonambig + gm_edge_mask, and
// writes nurl_pts.bin (f32 [H,W,3]) and nurl_mask.bin (u8 [H,W]).
//
//   geomcheck <dir> <H> <W>

$ `stdlib/core/string.nu`
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

@ __gc_read s dir s name i n → *f {
    : String p ( string_from dir )
    ( string_push_str p name )
    : ~ * f out # *f 0
    ?? ( read_file_bytes ( string_data p ) ) {
        F → {}
        T raw → {
            ? == ( vec_len [u] raw ) * n 4 {
                = out # *f ( nurl_zalloc * 8 n )
                : *u rp ( vec_data [u] raw )
                : ~ i j 0
                ~ < j n {
                    : i o * j 4
                    : i bits | # i . rp o | << # i . rp + o 1 8 | << # i . rp + o 2 16 << # i . rp + o 3 24
                    = . out j # f ( bits_to_f32 bits )
                    = j + j 1
                }
            } {}
            ( vec_free [u] raw )
        }
    }
    ( string_free p )
    ^ out
}

@ main → i {
    ? < ( nurl_argc ) 4 { ^ ( __gc_die `usage: geomcheck <dir> <H> <W>` ) } {}
    : s dir ( nurl_argv 1 )
    : i h ( nurl_str_to_int ( nurl_argv 2 ) )
    : i w ( nurl_str_to_int ( nurl_argv 3 ) )
    : i n * h w

    : *f dirs ( __gc_read dir `/dirs.bin` * 3 n )
    : *f depth ( __gc_read dir `/depth.bin` n )
    : *f pose ( __gc_read dir `/pose.bin` 7 )
    : *f logits ( __gc_read dir `/logits.bin` n )
    ? & & & != # i dirs 0 != # i depth 0 != # i pose 0 != # i logits 0 {} {
        ^ ( __gc_die `cannot read inputs` )
    }

    // unit-sphere normalise, as the DPT adaptor does (clip 1e-8)
    : ~ i j 0
    ~ < j n {
        : f x . dirs j
        : f y . dirs + n j
        : f z . dirs + * 2 n j
        : ~ f nn ( float_sqrt + + * x x * y y * z z )
        ? < nn 0.00000001 { = nn 0.00000001 } {}
        = . dirs j / x nn
        = . dirs + n j / y nn
        = . dirs + * 2 n j / z nn
        = j + j 1
    }

    // the head normalises the quaternion before it hands the pose over
    : f qx . pose 3
    : f qy . pose 4
    : f qz . pose 5
    : f qw . pose 6
    : ~ f qn ( float_sqrt + + + * qx qx * qy qy * qz qz * qw qw )
    ? < qn 0.00000001 { = qn 0.00000001 } {}
    = . pose 3 / qx qn
    = . pose 4 / qy qn
    = . pose 5 / qz qn
    = . pose 6 / qw qn

    : *f pts # *f ( nurl_zalloc * 24 n )
    : *f depthz # *f ( nurl_zalloc * 8 n )
    ( gm_world_points dirs depth pose GC_SCALE n pts depthz )
    : *u mask # *u ( nurl_zalloc n )
    ( gm_nonambig logits n mask )
    ( gm_edge_mask pts depthz h w mask )

    // dump pts as f32 and mask as u8
    : ( Vec u ) pout ( vec_with_cap [u] * * 3 n 4 )
    : b _pl ( vec_set_len [u] pout * * 3 n 4 )
    : *u pp ( vec_data [u] pout )
    = j 0
    ~ < j * 3 n {
        : i bits # i ( f32_to_bits # f32 . pts j )
        : i o * j 4
        = . pp o # u & bits 255
        = . pp + o 1 # u & >> bits 8 255
        = . pp + o 2 # u & >> bits 16 255
        = . pp + o 3 # u & >> bits 24 255
        = j + j 1
    }
    : String p1 ( string_from dir )
    ( string_push_str p1 `/nurl_pts.bin` )
    ?? ( write_file_bytes ( string_data p1 ) pout ) {
        T → {}
        F → { ^ ( __gc_die `write pts` ) }
    }
    ( vec_free [u] pout )
    : ( Vec u ) mout ( vec_with_cap [u] n )
    = j 0
    ~ < j n { ( vec_push [u] mout . mask j ) = j + j 1 }
    : String p2 ( string_from dir )
    ( string_push_str p2 `/nurl_mask.bin` )
    ?? ( write_file_bytes ( string_data p2 ) mout ) {
        T → {}
        F → { ^ ( __gc_die `write mask` ) }
    }
    ( puts `wrote nurl_pts/mask.bin` )
    ^ 0
}
