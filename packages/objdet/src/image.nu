// packages/objdet/src/image.nu — detector-facing adapter over packages/image.
//
// The codecs and raster ops live in the image package (PNG/JPEG/PPM decode,
// bilinear resize, rectangle drawing — see deps/image); this file keeps only
// what is detector-specific: loading ANY supported format as guaranteed-RGB,
// saving by extension, saturating pixel stores, and packing to the NCHW
// float tensor the model consumes. The Image type is the image package's
// (width/height/channels/data).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/image/src/image.nu`

& `c` @ nurl_poke_f32 *u base i idx f val → v

@ img_w Image im → i { ^ . im width }

@ img_h Image im → i { ^ . im height }

// A blank (black) RGB image.
@ img_blank i w i h → Image { ^ ( image_new w h 3 ) }

@ img_get Image im i x i y i ch → i { ^ ( image_get im x y ch ) }

// Saturating store (image_set masks to the low byte; the detector's callers
// pass computed values that must clamp, not wrap).
@ img_set Image im i x i y i ch i val → v {
    : i cv ? < val 0 { 0 } { ? > val 255 { 255 } { val } }
    ( image_set im x y ch cv )
}

@ img_resize Image im i nw i nh → Image { ^ ( image_resize im nw nh ) }

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

@ __od_sfx s path s sfx → b {
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
    ? ( __od_sfx path `.png` ) { ^ ( image_save_png path im ) } {}
    ? | ( __od_sfx path `.jpg` ) ( __od_sfx path `.jpeg` ) { ^ ( image_save_jpeg path im 90 ) } {}
    ^ ( image_save_ppm path im )
}

// Draw a thickness-2 rectangle outline in the given colour.
@ img_draw_rect Image im i x0 i y0 i x1 i y1 i r i gg i bb → v {
    : i rgba + + + * r 16777216 * gg 65536 * bb 256 255
    ( image_draw_rect im x0 y0 x1 y1 2 rgba )
}

// ── pack to NCHW float tensor (values 0..255) ─────────────────────
// Writes a fresh host buffer of 3*H*W floats in CHW order; the model's
// in-graph preprocessor scales by 1/255.
@ img_to_nchw Image im → *u {
    : i W . im width
    : i H . im height
    : *u host ( nurl_alloc * * * 3 H W 4 )
    : ~ i c 0
    ~ < c 3 {
        : ~ i y 0
        ~ < y H {
            : ~ i x 0
            ~ < x W {
                ( nurl_poke_f32 host + * c * H W + * y W x # f ( image_get im x y c ) )
                = x + x 1
            }
            = y + y 1
        }
        = c + c 1
    }
    ^ host
}
