// packages/map-anything/src/preproc.nu — images in, model input out.
//
// The reference's `load_images(resize_mode="fixed_mapping",
// resolution_set=518, patch_size=14, norm_type="dinov2")`, which is what
// demo_images_only_inference.py runs:
//
//   1. decode every image, force RGB (PIL `.convert("RGB")` — alpha is
//      DROPPED, not composited; that is what the reference does)
//   2. average the images' aspect ratios W/H and pick ONE shared target
//      size for the whole set from a fixed table of ten 14-divisible
//      resolutions (518×518 … 518×168 and the portrait transposes)
//   3. per image: scale = max(tw/W, th/H) + 1e-8, resize to
//      (floor(W·scale), floor(H·scale)) — LANCZOS when shrinking,
//      BICUBIC when growing, and specifically PIL's kernels, which the
//      image package matches byte for byte
//   4. centre-crop to exactly (tw, th)
//   5. scale to [0, 1]
//
// ImageNet mean/std normalisation is NOT done here — it is applied at
// the encoder input, and the un-normalised [0,1] pixels are also what
// the point cloud's colours come from.
//
// Output is one f32 plane-major (CHW) buffer per image, C = 3.
//
//   ( pp_open path )              → !Image String    decoded, forced RGB
//   ( pp_pick_target avg_aspect ) → i                packed (w<<16)|h
//   ( pp_fit im tw th )           → !*Frame String
//   ( pp_free fr )                → v
//   ( pp_width fr ) ( pp_height fr ) → i
//   ( pp_data fr )                → *f   CHW, [0,1], borrowed
//
// EXIF orientation is NOT applied — the reference calls
// `exif_transpose`, but the image package does not surface EXIF, and
// silently ignoring a rotation is better than silently applying the
// wrong one. Applying it belongs with EXIF support in `image`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/image/src/core.nu`
$ `deps/image/src/ops.nu`
$ `deps/image/src/image.nu`

: Frame {
    i width
    i height
    ( Vec f ) data  // CHW, 3 planes, values in [0, 1]
}

@ pp_width * Frame fr → i { ^ . fr width }

@ pp_height * Frame fr → i { ^ . fr height }

@ pp_data * Frame fr → *f { ^ ( vec_data [f] . fr data ) }

@ pp_free * Frame fr → v {
    ( vec_free [f] . fr data )
    ( nurl_free # s fr )
}

// The reference's RESOLUTION_MAPPINGS[518]: aspect-ratio key → (w, h),
// all divisible by 14. Keys ascending, exactly the floats the table
// spells, because ties in "closest" must break the way Python's min()
// breaks them (first, i.e. smallest key, wins).
: i __PP_N_RES 10

@ __pp_res_key i k → f {
    ? == k 0 { ^ 0.486 } {}
    ? == k 1 { ^ 0.567 } {}
    ? == k 2 { ^ 0.649 } {}
    ? == k 3 { ^ 0.757 } {}
    ? == k 4 { ^ 1.000 } {}
    ? == k 5 { ^ 1.321 } {}
    ? == k 6 { ^ 1.542 } {}
    ? == k 7 { ^ 1.762 } {}
    ? == k 8 { ^ 2.056 } {}
    ^ 3.083
}

@ __pp_res_w i k → i {
    ? == k 0 { ^ 252 } {}
    ? == k 1 { ^ 294 } {}
    ? == k 2 { ^ 336 } {}
    ? == k 3 { ^ 392 } {}
    ^ 518
}

@ __pp_res_h i k → i {
    ? == k 4 { ^ 518 } {}
    ? == k 5 { ^ 392 } {}
    ? == k 6 { ^ 336 } {}
    ? == k 7 { ^ 294 } {}
    ? == k 8 { ^ 252 } {}
    ? == k 9 { ^ 168 } {}
    ^ 518
}

// The shared target size for a set whose average aspect ratio is `ar`,
// packed (w << 16) | h so the pair survives a single return value.
@ pp_pick_target f ar → i {
    : ~ i best 0
    : ~ f bestd 1000000.0
    : ~ i k 0
    ~ < k __PP_N_RES {
        : f d ( float_abs - ( __pp_res_key k ) ar )
        ? < d bestd {
            = bestd d
            = best k
        } {}
        = k + k 1
    }
    ^ | << ( __pp_res_w best ) 16 ( __pp_res_h best )
}

@ pp_target_w i packed → i { ^ >> packed 16 }

@ pp_target_h i packed → i { ^ & packed 65535 }

@ __pp_err s msg s detail → !*Frame String {
    : String m ( string_from msg )
    ( string_push_str m detail )
    ^ @ !*Frame String { F m }
}

// Decode one image and force RGB the way PIL's `.convert("RGB")` does:
// grey expands, alpha is dropped. image_convert does exactly that.
@ pp_open s path → !Image String {
    ?? ( image_load path ) {
        F → {
            : String m ( string_from `map-anything: cannot decode ` )
            ( string_push_str m path )
            ( string_push_str m ` — ` )
            ( string_push_str m ( image_error ) )
            ^ @ !Image String { F m }
        }
        T im → {
            ? == . im channels 3 { ^ @ !Image String { T im } } {}
            : Image rgb ( image_convert im 3 )
            ( image_free im )
            ^ @ !Image String { T rgb }
        }
    }
}

// Resize + centre-crop one decoded RGB image to the shared target size,
// and hand back the model-input planes. The image is BORROWED.
//
// scale = max(tw/w, th/h) + 1e-8; the intermediate size floors, the
// kernel is LANCZOS going down and BICUBIC going up, the crop offsets
// floor — each of those is the reference's own arithmetic, not an
// approximation of it.
@ pp_fit Image im i tw i th → !*Frame String {
    : i w . im width
    : i h . im height
    ? | | <= w 0 <= h 0 != . im channels 3 {
        ^ ( __pp_err `map-anything: not a decodable RGB image` `` )
    } {}
    : f sx / # f tw # f w
    : f sy / # f th # f h
    : f scale + ? > sx sy sx sy 0.00000001
    : i iw # i ( float_floor * # f w scale )
    : i ih # i ( float_floor * # f h scale )
    : Image resized ? < scale 1.0 ( image_resize_lanczos im iw ih ) ( image_resize_bicubic im iw ih )
    : i left / - iw tw 2
    : i top / - ih th 2
    ? | < left 0 < top 0 {
        ( image_free resized )
        ^ ( __pp_err `map-anything: crop outside the resized image` `` )
    } {}
    : Image fit ( image_crop resized left top tw th )
    ( image_free resized )
    // Interleaved bytes to planar floats through the raw pointers — at
    // three planes of 518×392 that is 609k per-element calls saved.
    : ( Vec f ) data ( vec_with_cap [f] * 3 * tw th )
    : b _dl ( vec_set_len [f] data * 3 * tw th )
    : *f dp ( vec_data [f] data )
    : *u sp ( vec_data [u] . fit data )
    : ~ i k 0
    ~ < k 3 {
        : i plane * k * tw th
        : ~ i y 0
        ~ < y th {
            : i row * * y tw 3
            : i orow + plane * y tw
            : ~ i x 0
            ~ < x tw {
                = . dp + orow x / # f # i . sp + + row * x 3 k 255.0
                = x + x 1
            }
            = y + y 1
        }
        = k + k 1
    }
    ( image_free fit )
    : *Frame fr # *Frame ( nurl_alloc Z Frame )
    = . fr width tw
    = . fr height th
    = . fr data data
    ^ @ !*Frame String { T fr }
}
