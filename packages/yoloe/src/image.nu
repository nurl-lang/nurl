// packages/yoloe/src/image.nu — YOLO-facing adapter over packages/image.
//
// The codecs and raster ops live in the image package (PNG / baseline +
// progressive JPEG / PPM decode+encode, rectangle drawing — see deps/image);
// this file keeps only what is YOLO-specific: letterbox preprocessing
// (aspect-preserving nearest resize + grey-114 pad, matching ultralytics),
// packing to the [0,1]-normalised NCHW float tensor the model consumes,
// edge-clamped reads for the mask overlay, and load/save-by-extension.
// The Image type is the image package's (width/height/channels/data).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/image/src/image.nu`

& `c` @ nurl_poke_f32 *u base i idx f val → v

// Letterbox result: the square image plus the transform back to original
// pixels (orig = (lb - pad) / scale).
: Letterbox { Image img f scale i padx i pady }

@ img_w Image im → i { ^ . im width }

@ img_h Image im → i { ^ . im height }

// Edge-clamped read (the mask overlay and letterbox sample with clamping).
@ img_get Image im i x i y i ch → i {
    : i xx ? < x 0 { 0 } { ? >= x . im width { - . im width 1 } { x } }
    : i yy ? < y 0 { 0 } { ? >= y . im height { - . im height 1 } { y } }
    ^ ( image_get im xx yy ch )
}

// Saturating store (image_set masks to the low byte; overlay math must clamp).
@ img_set Image im i x i y i ch i val → v {
    : i cv ? < val 0 { 0 } { ? > val 255 { 255 } { val } }
    ( image_set im x y ch cv )
}

// An RGB image filled with a constant grey level.
@ img_blank i w i h i fill → Image {
    : Image im ( image_new w h 3 )
    : i n * * w h 3
    : ~ i k 0
    ~ < k n { ( vec_set [u] . im data k # u fill ) = k + k 1 }
    ^ im
}

// Load any supported format (PNG / baseline+progressive JPEG / PPM) as
// 3-channel RGB. On None, ( image_error ) says why.
@ img_load s path → ?Image {
    ?? ( image_load path ) {
        T im → {
            ? == ( image_channels im ) 3 { ^ @ ?Image { T im } } {}
            : Image rgb ( image_convert im 3 )
            ( image_free im )
            ^ @ ?Image { T rgb }
        }
        F _ → { ^ @ ?Image { F } }
    }
}

@ __ye_sfx s path s sfx → b {
    : i n ( nurl_str_len path )
    : i m ( nurl_str_len sfx )
    ? < n m { ^ F } {}
    : ~ i k 0
    ~ < k m {
        ? == ( nurl_str_get path + - n m k ) ( nurl_str_get sfx k ) {} { ^ F }
        = k + k 1
    }
    ^ T
}

// Save by extension: .png / .jpg / .jpeg (quality 90) / anything else = PPM.
@ img_save s path Image im → b {
    ? ( __ye_sfx path `.png` ) { ^ ( image_save_png path im ) } {}
    ? | ( __ye_sfx path `.jpg` ) ( __ye_sfx path `.jpeg` ) { ^ ( image_save_jpeg path im 90 ) } {}
    ^ ( image_save_ppm path im )
}

// ── letterbox to S×S (aspect-preserving, grey 114 pad) ────────────
@ letterbox Image im i S → Letterbox {
    : i W . im width
    : i H . im height
    : f sx / # f S # f W
    : f sy / # f S # f H
    : f scale ? < sx sy sx sy
    : i nw # i * # f W scale
    : i nh # i * # f H scale
    : i padx / - S nw 2
    : i pady / - S nh 2
    : Image out ( img_blank S S 114 )
    : ~ i oy 0
    ~ < oy nh {
        : f srcyf / # f oy scale
        : i syi # i srcyf
        : ~ i ox 0
        ~ < ox nw {
            : f srcxf / # f ox scale
            : i sxi # i srcxf
            : ~ i c 0
            ~ < c 3 { ( img_set out + ox padx + oy pady c ( img_get im sxi syi c ) ) = c + c 1 }
            = ox + ox 1
        }
        = oy + oy 1
    }
    ^ @ Letterbox { out scale padx pady }
}

// Pack to NCHW float tensor normalised to [0,1].
@ img_to_nchw_norm Image im → *u {
    : i W . im width
    : i H . im height
    : *u host ( nurl_alloc * * * 3 H W 4 )
    : ~ i c 0
    ~ < c 3 {
        : ~ i y 0
        ~ < y H {
            : ~ i x 0
            ~ < x W {
                ( nurl_poke_f32 host + * c * H W + * y W x / # f ( image_get im x y c ) 255.0 )
                = x + x 1
            }
            = y + y 1
        }
        = c + c 1
    }
    ^ host
}

// Draw a thickness-3 rectangle outline in the given colour.
@ img_draw_rect Image im i x0 i y0 i x1 i y1 i r i gg i bb → v {
    : i rgba + + + * r 16777216 * gg 65536 * bb 256 255
    ( image_draw_rect im x0 y0 x1 y1 3 rgba )
}
