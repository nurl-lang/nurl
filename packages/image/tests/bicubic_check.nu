// bicubic_check.nu — resize a deterministic test raster with
// image_resize_bicubic at a spread of scales, and print every output
// byte. tests/bicubic_oracle.py prints the same thing out of Pillow; the
// test is a byte diff.
//
// Alpha-carrying images are NOT in this set on purpose: Pillow
// premultiplies alpha before resampling an LA/RGBA image and this
// function resamples channels independently, so the two disagree
// wherever alpha varies. That difference is documented at the function,
// and pinning it against Pillow here would assert the opposite.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/core.nu`
$ `src/ops.nu`

// A raster with structure at several frequencies — flat regions would
// hide a wrong coefficient window, and pure noise would hide an off-by-one
// in the pixel centre.
@ make_src i w i h i ch → Image {
    : Image im ( image_new w h ch )
    : ~ i y 0
    ~ < y h {
        : ~ i x 0
        ~ < x w {
            : ~ i k 0
            ~ < k ch {
                : i v % + + + * 37 x * 61 y * 91 k * 13 % * x y 7 251
                ( image_set im x y k v )
                = k + k 1
            }
            = x + x 1
        }
        = y + y 1
    }
    ^ im
}

@ dump s label Image im → v {
    ( nurl_print label )
    ( nurl_print ` ` ) ( nurl_print ( nurl_str_int . im width ) )
    ( nurl_print `x` ) ( nurl_print ( nurl_str_int . im height ) )
    ( nurl_print `x` ) ( nurl_print ( nurl_str_int . im channels ) )
    : ~ i y 0
    ~ < y . im height {
        : ~ i x 0
        ~ < x . im width {
            : ~ i k 0
            ~ < k . im channels {
                ( nurl_print ` ` )
                ( nurl_print ( nurl_str_int ( image_get im x y k ) ) )
                = k + k 1
            }
            = x + x 1
        }
        = y + y 1
    }
    ( nurl_print `\n` )
}

@ case i w i h i ch i nw i nh → v {
    : Image src ( make_src w h ch )
    : Image out ( image_resize_bicubic src nw nh )
    : String lab ( string_from `r` )
    ( string_push_int lab w ) ( string_push_char lab 95 )
    ( string_push_int lab h ) ( string_push_char lab 95 )
    ( string_push_int lab ch ) ( string_push_char lab 95 )
    ( string_push_int lab nw ) ( string_push_char lab 95 )
    ( string_push_int lab nh )
    ( dump ( string_data lab ) out )
    ( string_free lab )
    ( image_free out )
    ( image_free src )
}

@ main → i {
    ( case 16 12 3 8 6 )  // clean 2x downscale
    ( case 16 12 3 32 24 )  // clean 2x upscale
    ( case 17 13 3 11 7 )  // awkward downscale, both axes
    ( case 17 13 3 23 29 )  // awkward upscale, both axes
    ( case 17 13 3 23 7 )  // up on one axis, down on the other
    ( case 20 20 1 7 7 )  // greyscale
    ( case 9 9 3 1 1 )  // degenerate: single output pixel
    ( case 1 1 3 5 5 )  // degenerate: single input pixel
    ( case 31 5 3 5 31 )  // extreme aspect swap
    ^ 0
}
