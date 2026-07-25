// packages/lingbot-map/src/preproc.nu — frames in, model input out.
//
// The reference's `load_and_preprocess_images(mode="crop", image_size=518,
// patch_size=14)`, which is what demo.py runs:
//
//   1. decode, drop any alpha onto white, force RGB
//   2. resize to width = 518, height = round(h · 518/w / 14) · 14
//      — BICUBIC, and specifically PIL's bicubic (a = −0.5), which is a
//      different kernel from torch's (a = −0.75). The model was trained
//      on frames that went through PIL, so PIL is what has to be matched.
//   3. centre-crop the height back to 518 if the resize overshot
//   4. scale to [0, 1]
//
// ImageNet mean/std normalisation is NOT done here: the aggregator applies
// it internally, and doing it twice is the kind of mistake that produces a
// plausible-looking but wrong reconstruction.
//
// Output is one f32 plane-major (CHW) buffer per frame, C = 3.
//
//   ( pp_load path size patch )  → !*Frame String
//   ( pp_free fr )               → v
//   ( pp_width fr ) ( pp_height fr )   → i
//   ( pp_data fr )               → *f   CHW, [0,1], borrowed
//
// EXIF orientation is NOT applied — see the note at pp_load.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
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

@ __pp_err s msg s detail → !*Frame String {
    : String m ( string_from msg )
    ( string_push_str m detail )
    ^ @ !*Frame String { F m }
}

// round-half-away-from-zero on a non-negative ratio, matching python's
// round() closely enough for the only use here (h · size / w / patch,
// which is never a .5 tie in practice) while staying integer-only.
@ __pp_round_div i num i den → i {
    ? <= den 0 { ^ 0 } {}
    ^ / + * 2 num den * 2 den
}

// Resize + centre-crop one decoded image to the model's input geometry.
// Returns a NEW image; the caller frees both.
@ pp_fit Image im i size i patch → Image {
    : i w . im width
    : i h . im height
    ? | <= w 0 <= h 0 { ^ ( image_new 0 0 3 ) } {}
    : i nw size
    // round(h * (nw/w) / patch) * patch — the height is snapped to a whole
    // number of patches, so the ViT never sees a partial row.
    : i nh_patches ( __pp_round_div * h nw * w patch )
    : i nh ? > nh_patches 0 * nh_patches patch patch
    : Image resized ( image_resize_bicubic im nw nh )
    ? <= nh size { ^ resized } {}
    : i start_y / - nh size 2
    : Image cropped ( image_crop resized 0 start_y nw size )
    ( image_free resized )
    ^ cropped
}

// Decode a frame file and put it in model-input form.
//
// EXIF orientation is deliberately not applied. The reference calls
// `ImageOps.exif_transpose`, which matters for phone and Sony stills
// stored landscape with Orientation=6/8 — but the image package does not
// surface EXIF, and silently ignoring a rotation is better than silently
// applying the wrong one. Video-derived frames, which is what streaming
// reconstruction is actually fed, carry no EXIF. Applying it belongs with
// EXIF support in `image`, not with a guess here.
@ pp_load s path i size i patch → !*Frame String {
    ?? ( image_load path ) {
        F → {
            : String m ( string_from `lingbot-map: cannot decode ` )
            ( string_push_str m path )
            ( string_push_str m ` — ` )
            ( string_push_str m ( image_error ) )
            ^ @ !*Frame String { F m }
        }
        T im → {
            // Alpha composited onto WHITE, as the reference does, then RGB.
            : Image rgb ( __pp_flatten im )
            ( image_free im )
            : Image fit ( pp_fit rgb size patch )
            ( image_free rgb )
            : i w . fit width
            : i h . fit height
            ? | <= w 0 <= h 0 {
                ( image_free fit )
                ^ ( __pp_err `lingbot-map: empty frame after resize: ` path )
            } {}
            : ( Vec f ) data ( vec_with_cap [f] * 3 * w h )
            : ~ i k 0
            ~ < k 3 {
                : ~ i y 0
                ~ < y h {
                    : ~ i x 0
                    ~ < x w {
                        ( vec_push [f] data / # f ( image_get fit x y k ) 255.0 )
                        = x + x 1
                    }
                    = y + y 1
                }
                = k + k 1
            }
            ( image_free fit )
            : *Frame fr # *Frame ( nurl_alloc Z Frame )
            = . fr width w
            = . fr height h
            = . fr data data
            ^ @ !*Frame String { T fr }
        }
    }
}

// RGBA → RGB over a white background, matching the reference's
// `alpha_composite(Image.new("RGBA", size, white), img)`. A source with no
// alpha is just converted.
@ __pp_flatten Image im → Image {
    : i ch . im channels
    ? | == ch 1 == ch 3 { ^ ( image_convert im 3 ) } {}
    : i w . im width
    : i h . im height
    : Image out ( image_new w h 3 )
    : i ai - ch 1
    : ~ i y 0
    ~ < y h {
        : ~ i x 0
        ~ < x w {
            : i a ( image_get im x y ai )
            : ~ i k 0
            ~ < k 3 {
                : i src ? == ch 2 ( image_get im x y 0 ) ( image_get im x y k )
                // src·a + 255·(1−a), rounded — integer, exactly as PIL does it
                : i v / + + * src a * 255 - 255 a 127 255
                ( image_set out x y k ? > v 255 255 v )
                = k + k 1
            }
            = x + x 1
        }
        = y + y 1
    }
    ^ out
}
