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

& `c` @ nurl_peek_f32 *u base i idx → f
& `c` @ nurl_poke_f32 *u base i idx f val → v

// Mask prototype geometry: 32 coefficients, 160×160 prototypes at stride 4.
@ mask_nm → i { ^ 32 }
@ mask_dim → i { ^ 160 }
@ mask_stride → i { ^ 4 }

// Read a detection's nm mask coefficients from output0 (channels
// 4+nc .. 4+nc+nm at anchor `ai`) into a fresh host buffer (caller frees).
@ mask_coeffs *u out i na i nc i ai → *u {
    : i nm ( mask_nm )
    : *u c ( nurl_alloc * nm 4 )
    : ~ i m 0
    ~ < m nm {
        ( nurl_poke_f32 c m ( nurl_peek_f32 out + * + + 4 nc m na ai ) )
        = m + m 1
    }
    ^ c
}

// Build the 160×160 mask logit map for one detection: logit[y,x] =
// Σ_m coeff[m]·proto[m,y,x]. proto is laid out [nm, MH, MW] row-major.
// Returns a fresh host f32 buffer of MH*MW (caller frees).
@ mask_logits *u proto *u coeff i MH i MW → *u {
    : i nm ( mask_nm )
    : i hw * MH MW
    : *u L ( nurl_alloc * hw 4 )
    : ~ i p 0
    ~ < p hw {
        : ~ f acc 0.0
        : ~ i m 0
        ~ < m nm {
            = acc + acc * ( nurl_peek_f32 coeff m ) ( nurl_peek_f32 proto + * m hw p )
            = m + m 1
        }
        ( nurl_poke_f32 L p acc )
        = p + p 1
    }
    ^ L
}

// Bilinear sample of an MH×MW grid at fractional (fy,fx); out-of-range
// coordinates clamp to the edge (align_corners=False convention).
@ mask_sample *u L i MH i MW f fy f fx → f {
    : f cy ? < fy 0.0 0.0 ? > fy # f - MH 1 # f - MH 1 fy
    : f cx ? < fx 0.0 0.0 ? > fx # f - MW 1 # f - MW 1 fx
    : i y0 # i cy
    : i x0 # i cx
    : i y1 ? < y0 - MH 1 + y0 1 y0
    : i x1 ? < x0 - MW 1 + x0 1 x0
    : f dy - cy # f y0
    : f dx - cx # f x0
    : f v00 ( nurl_peek_f32 L + * y0 MW x0 )
    : f v01 ( nurl_peek_f32 L + * y0 MW x1 )
    : f v10 ( nurl_peek_f32 L + * y1 MW x0 )
    : f v11 ( nurl_peek_f32 L + * y1 MW x1 )
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
@ mask_overlay Image im *u L Letterbox lb i S i x0 i y0 i ow i oh i r i gg i bb i alpha → i {
    : i MH ( mask_dim )
    : i MW ( mask_dim )
    : f scale . lb scale
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
