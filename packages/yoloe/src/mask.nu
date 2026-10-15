// packages/yoloe/src/mask.nu — instance-segmentation mask decode + overlay.
//
// YOLOE-seg has two outputs: output0 [1, 4+nc+nm, na] (boxes, class scores,
// and nm=32 mask coefficients per anchor) and output1 [1, nm, MH, MW] — the
// mask "prototypes" (MH=MW=160, a quarter of the 640 input). The mask for a
// detection is a linear combination of the prototypes weighted by that
// anchor's 32 coefficients, then thresholded:
//
//     logit[y,x] = Σ_m coeff[m] · proto[m,y,x]          (160×160)
//     mask       = sigmoid(logit) > 0.5   ⟺   logit > 0
//
// cropped to the box and upsampled to image resolution (bilinear) — exactly
// `ops.process_mask(..., upsample=True)` in the reference. We precompute the
// 160×160 logit map per detection, then bilinear-sample it as we paint the
// box region of the original image, blending a translucent colour where the
// mask is set. This matches onnxruntime's masks (the proto tensor itself is
// bit-checked against onnxruntime in tests/seg_fwd.nu).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `image.nu`
$ `decode.nu`
$ `stdlib/core/slice.nu`

// Mask prototype geometry: 32 coefficients, 160×160 prototypes at stride 4.
@ mask_nm → i { ^ 32 }

@ mask_dim → i { ^ 160 }

@ mask_stride → i { ^ 4 }

// Read a detection's nm mask coefficients from output0 (channels
// 4+nc .. 4+nc+nm at anchor `ai`). Each is the f32 value, exactly.
@ mask_coeffs GpuHost out i na i nc i ai → ( Vec f ) {
    : i nm ( mask_nm )
    : ( Vec f ) cv ( vec_with_cap [f] nm )
    : ~ i m 0
    ~ < m nm {
        ( vec_push [f] cv ( gpu_host_get_f32 out + * + + 4 nc m na ai ) )
        = m + m 1
    }
    ^ cv
}

// Build the 160×160 mask logit map for one detection: logit[y,x] =
// Σ_m coeff[m]·proto[m,y,x]. proto is laid out [nm, MH, MW] row-major.
// Each pixel sums its terms in m order, as one loop per pixel did, but a
// prototype plane at a time: the inner loop runs over contiguous windows
// and vectorises. Each logit is rounded to f32, as the map was always
// stored. A proto smaller than that is no mask: every logit 0.
@ mask_logits GpuHost proto ( Vec f ) coeff i MH i MW → ( Vec f ) {
    : i nm ( mask_nm )
    : i hw ? | < MH 0 < MW 0 0 * MH MW
    : ( Vec f ) acc ( vec_zeroed [f] hw )
    ? < ( gpu_host_bytes proto ) * * nm hw 4 { ^ acc } {}
    : ( Slice f32 ) pr ( gpu_host_f32 proto )
    : ( Slice f ) cs ( slice_prefix [f] ( slice_from_vec [f] coeff ) nm )
    : ( Slice f ) ac ( slice_from_vec [f] acc )
    : ~ i m 0
    ~ < m nm {
        : f c ( slice_at [f] cs m )
        : ( Slice f32 ) plane ( slice_window [f32] pr * m hw hw )
        : ~ i p 0
        ~ < p hw {
            ( slice_put [f] ac p + ( slice_at [f] ac p ) * c # f ( slice_at [f32] plane p ) )
            = p + p 1
        }
        = m + m 1
    }
    : ~ i q 0
    ~ < q hw {
        ( slice_put [f] ac q # f # f32 ( slice_at [f] ac q ) )
        = q + q 1
    }
    ^ acc
}

// Bilinear sample of an MH×MW grid at fractional (fy,fx); out-of-range
// coordinates clamp to the edge (align_corners=False convention).
@ mask_sample ( Slice f ) L i MH i MW f fy f fx → f {
    : f cy ? < fy 0.0 0.0 ? > fy # f - MH 1 # f - MH 1 fy
    : f cx ? < fx 0.0 0.0 ? > fx # f - MW 1 # f - MW 1 fx
    : i y0 # i cy
    : i x0 # i cx
    : i y1 ? < y0 - MH 1 + y0 1 y0
    : i x1 ? < x0 - MW 1 + x0 1 x0
    : f dy - cy # f y0
    : f dx - cx # f x0
    : f v00 ( slice_at [f] L + * y0 MW x0 )
    : f v01 ( slice_at [f] L + * y0 MW x1 )
    : f v10 ( slice_at [f] L + * y1 MW x0 )
    : f v11 ( slice_at [f] L + * y1 MW x1 )
    : f top + * - 1.0 dx v00 * dx v01
    : f bot + * - 1.0 dx v10 * dx v11
    ^ + * - 1.0 dy top * dy bot
}

// Blend colour (r,g,b) into a pixel at alpha/256 (alpha 0..256).
@ mask_blend Image im i x i y i r i gg i bb i alpha → v {
    : i or ( img_get im x y 0 )
    : i og ( img_get im x y 1 )
    : i ob ( img_get im x y 2 )
    : i a ? > alpha 256 256 ? < alpha 0 0 alpha
    : i ia - 256 a
    ( img_set im x y 0 / + * a r * ia or 256 )
    ( img_set im x y 1 / + * a gg * ia og 256 )
    ( img_set im x y 2 / + * a bb * ia ob 256 )
}

// Overlay one detection's mask onto the original image. The box is given in
// ORIGINAL-image pixels (x0,y0,ow,oh); for each pixel we map back through the
// letterbox to the 160×160 mask grid and threshold the bilinearly-sampled
// logit at 0 (sigmoid > 0.5). `S` is the model input side (640).
@ mask_overlay Image im ( Vec f ) L__v Letterbox lb i S i x0 i y0 i ow i oh i r i gg i bb i alpha → i {
    : i MH ( mask_dim )
    : i MW ( mask_dim )
    : f scale . lb scale
    : ( Slice f ) L ( slice_from_vec [f] L__v )
    : i padx . lb padx
    : i pady . lb pady
    : f rh / # f MH # f S
    : f rw / # f MW # f S
    : ~ i count 0
    : ~ i oy y0
    ~ < oy + y0 oh {
        : ~ i ox x0
        ~ < ox + x0 ow {
            // original → letterbox pixel → mask-grid coordinate
            : f lx + * # f ox scale # f padx
            : f ly + * # f oy scale # f pady
            : f fx - * + lx 0.5 rw 0.5
            : f fy - * + ly 0.5 rh 0.5
            : f v ( mask_sample L MH MW fy fx )
            ? > v 0.0 { ( mask_blend im ox oy r gg bb alpha ) = count + count 1 } {}
            = ox + ox 1
        }
        = oy + oy 1
    }
    ^ count
}
