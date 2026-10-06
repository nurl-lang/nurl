// interpcheck.nu — resample deterministic feature grids with
// interp_bicubic_aa and print every output value, in the format
// tests/interp_oracle.py emits from torch's
// F.interpolate(mode="bicubic", antialias=True).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/interp.nu`

// The same closed-form grid the oracle builds: smooth enough that a
// wrong kernel shows as a smooth error rather than noise, structured
// enough that a transposed axis is obvious.
unsafe @ fill * f p i w i h i planes → v {
    : ~ i c 0
    ~ < c planes {
        : ~ i y 0
        ~ < y h {
            : ~ i x 0
            ~ < x w {
                : f fx / # f x # f w
                : f fy / # f y # f h
                : f v + + ( float_sin * 6.2831853 fx ) ( float_cos * 4.1887902 fy ) * 0.25 # f c
                = . p + * c * w h + * y w x v
                = x + x 1
            }
            = y + y 1
        }
        = c + c 1
    }
}

unsafe @ case i sw i sh i planes i dw i dh → v {
    : ( Vec u ) src__v ( vec_zeroed [u] * 8 * planes * sw sh )
    : *f src # *f ( vec_data [u] src__v )
    : ( Vec u ) dst__v ( vec_zeroed [u] * 8 * planes * dw dh )
    : *f dst # *f ( vec_data [u] dst__v )
    ( fill src sw sh planes )
    ( interp_bicubic_aa src sw sh planes dw dh dst )
    ( nurl_print `g` ) ( nurl_print ( nurl_str_int sw ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int sh ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int planes ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int dw ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int dh ) )
    : ~ i j 0
    ~ < j * planes * dw dh {
        ( nurl_print ` ` ) ( nurl_print ( nurl_str_float . dst j ) )
        = j + j 1
    }
    ( nurl_print `\n` )
}

@ main → i {
    ( case 37 37 2 37 21 )  // the real one: DINOv2's grid → a 518x294 frame
    ( case 37 37 1 37 37 )  // identity size — must be a no-op resample
    ( case 37 37 1 11 9 )  // hard downscale, both axes
    ( case 8 8 2 19 23 )  // upscale, both axes
    ( case 16 4 1 5 13 )  // down on one axis, up on the other
    ^ 0
}
