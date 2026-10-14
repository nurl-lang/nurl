// packages/map-anything/src/sky.nu — optional sky masking, the way the
// LingBot-Map demo does it (--mask_sky): JianyuanWang's skyseg.onnx
// (a U²-Net) scores sky per pixel, and a pixel survives only where the
// upsampled score sits at the map's own minimum.
//
// The reference arithmetic, reproduced exactly:
//   1. the preprocessed view → 320×320 (bilinear, u8)
//   2. ImageNet-normalise, NCHW f32 → the ONNX graph (first output)
//   3. min–max normalise the 320×320 score map, quantise to u8
//      (truncating, as numpy's astype does)
//   4. bilinear-resize the u8 map to the view size
//   5. non-sky ⇔ resized value == 0 — the reference's
//      "1 − clip(u8, 0, 1) > 0.1" collapses to exactly this, and it is
//      no accident: the U²-Net's sigmoid saturates, so ~96% of a real
//      outdoor frame sits at the exact minimum
//
// MapAnything's own non-ambiguous mask already catches much of the sky;
// this is the belt to that suspender, for outdoor scenes where the
// depth head hallucinates a far wall instead.
//
//   ( sky_open path )                  → Sky      (ok=F on any failure)
//   ( sky_mask s chw w h mask )       → b   AND non-sky into mask

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `deps/image/src/core.nu`
$ `deps/image/src/ops.nu`
$ `deps/onnx/src/pb.nu`
$ `deps/onnx/src/model.nu`
$ `deps/onnx/src/runtime.nu`

: i SKY_N 320

: Sky {
    OGraph g
    ? Engine e
    b ok
}

@ sky_open s path → Sky {
    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ?? ( read_file_bytes path ) {
        T mb → { = g ( onnx_parse mb ) }
        F _ → { ^ @ Sky { g @ ?Engine { F } F } }
    }
    : Engine e ( rt_open 0 )
    ? ( rt_ok e ) {} { ^ @ Sky { g @ ?Engine { T e } F } }
    ^ @ Sky { g @ ?Engine { T e } T }
}

// AND "not sky" into `mask` for one view. `chw` is the fitted frame's
// [3, h, w] planar [0,1] host buffer (pp_data), `mask` h·w bytes.
@ sky_mask Sky s ( Slice f ) chw i w i h ( Slice u ) mask → b {
    ? . s ok {} { ^ F }
    : Engine eng ?? . s e { T x → x F → { ^ F } }
    // planar floats → interleaved u8, then the reference's 320×320
    : Image im ( image_new w h 3 )
    : ( Slice u ) ip ( slice_from_vec [u] . im data )
    : i hw * w h
    : ~ i j 0
    ~ < j hw {
        : ~ i c 0
        ~ < c 3 {
            : ~ i v # i + * ( slice_at [f] chw + * c hw j ) 255.0 0.5
            ? < v 0 { = v 0 } {}
            ? > v 255 { = v 255 } {}
            ( slice_put [u] ip + * j 3 c # u v )
            = c + c 1
        }
        = j + j 1
    }
    : Image sm ( image_resize im SKY_N SKY_N )
    // ImageNet normalise into the NCHW f32 input buffer
    : i n2 * SKY_N SKY_N
    : ( Vec u ) inb__v ( vec_zeroed [u] * * 3 n2 4 )
    : ( Slice u ) inb ( slice_from_vec [u] inb__v )
    : ( Slice u ) sp ( slice_from_vec [u] . sm data )
    : ( Vec f ) mean__v ( vec_zeroed [f] 3 )
    : ( Slice f ) mean ( slice_from_vec [f] mean__v )
    : ( Vec f ) std__v ( vec_zeroed [f] 3 )
    : ( Slice f ) std ( slice_from_vec [f] std__v )
    ( slice_put [f] mean 0 0.485 ) ( slice_put [f] mean 1 0.456 ) ( slice_put [f] mean 2 0.406 )
    ( slice_put [f] std 0 0.229 ) ( slice_put [f] std 1 0.224 ) ( slice_put [f] std 2 0.225 )
    = j 0
    ~ < j n2 {
        : ~ i c 0
        ~ < c 3 {
            : f v / # f # i ( slice_at [u] sp + * j 3 c ) 255.0
            ( slice_put_u32_le inb * 4 + * c n2 j ( f32_to_bits # f32 / - v ( slice_at [f] mean c ) ( slice_at [f] std c ) ) )
            = c + c 1
        }
        = j + j 1
    }

    : ( Vec i ) shape ( vec_with_cap [i] 4 )
    ( vec_push [i] shape 1 ) ( vec_push [i] shape 3 )
    ( vec_push [i] shape SKY_N ) ( vec_push [i] shape SKY_N )
    : RTensor out ( rt_run_shaped eng . s g inb shape )
    ? == . out nelem n2 {} { ^ F }
    : GpuHost score__h ( rt_download eng out )
    : ( Slice f32 ) score ( gpu_host_f32 score__h )

    // min–max → u8 (truncating), as run_skyseg does
    : ~ f mn # f ( slice_at [f32] score 0 )
    : ~ f mx mn
    = j 1
    ~ < j n2 {
        : f v # f ( slice_at [f32] score j )
        ? < v mn { = mn v } {}
        ? > v mx { = mx v } {}
        = j + j 1
    }
    : ~ f denom - mx mn
    ? < denom 0.00000001 { = denom 0.00000001 } {}
    : Image m8 ( image_new SKY_N SKY_N 1 )
    : ( Slice u ) mp ( slice_from_vec [u] . m8 data )
    = j 0
    ~ < j n2 {
        : f v * / - # f ( slice_at [f32] score j ) mn denom 255.0
        ( slice_put [u] mp j # u # i v )
        = j + j 1
    }
    // back to the view's size; a pixel is sky the moment the resized
    // score leaves zero
    : Image mfull ( image_resize m8 w h )
    : ( Slice u ) fp ( slice_from_vec [u] . mfull data )
    = j 0
    ~ < j hw {
        ? != # i ( slice_at [u] fp j ) 0 { ( slice_put [u] mask j # u 0 ) } {}
        = j + j 1
    }
    ^ T
}
