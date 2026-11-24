// packages/recon-kit/src/sharp.nu — choose views across a capture,
// the sharp ones.
//
// A cap on the number of views used to keep the FIRST n frames, so a long
// walk came back as its opening seconds. What a reconstruction wants is
// coverage: n views spread over the whole capture. And a hand-held video
// is full of frames smeared by motion, which cost a view and blur the
// depth it predicts — so where there are several candidates for a slot,
// the sharpest one takes it.
//
//   ( sh_pick frames n verbose ) → v   frames: in place, n of them kept
//   ( sh_score path )            → f   sharpness, -1.0 when undecodable
//
// The frames are split into n consecutive runs of (nearly) equal length;
// each run gives its sharpest frame, so the kept views stay in order and
// evenly spread. Sharpness is the variance of the Laplacian of the frame's
// luminance at 320 px wide — the classic focus measure: an edge keeps its
// second derivative high, motion blur and defocus flatten it. A run of one
// is taken as it is, unscored.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `deps/image/src/core.nu`
$ `deps/image/src/ops.nu`
$ `deps/image/src/image.nu`

@ sh_score s path → f {
    ?? ( image_load path ) {
        F → { ^ -1.0 }
        T im → {
            : i w . im width
            : i h . im height
            : i ch . im channels
            ? | | < w 3 < h 3 < ch 1 { ^ -1.0 } {}
            // a fixed working size, never upscaled
            : i tw ? > w 320 320 w
            : ~ i th / * h tw w
            ? < th 3 { = th 3 } {}
            : Image sm ( image_resize_area im tw th )
            : ( Slice u ) px ( slice_from_vec [u] . sm data )
            : i n * tw th
            : ( Vec f ) g__v ( vec_zeroed [f] n )
            : ( Slice f ) g ( slice_from_vec [f] g__v )
            : ~ i k 0
            ~ < k n {
                : i b * k ch
                ? >= ch 3 {
                    ( slice_put [f] g k + + * 0.299 # f ( slice_at [u] px b ) * 0.587 # f ( slice_at [u] px + b 1 ) * 0.114 # f ( slice_at [u] px + b 2 ) )
                } {
                    ( slice_put [f] g k # f ( slice_at [u] px b ) )
                }
                = k + k 1
            }
            // the 4-neighbour Laplacian over the interior: mean, then variance
            : ~ f sum 0.0
            : ~ f sq 0.0
            : ~ i cnt 0
            : ~ i y 1
            ~ < y - th 1 {
                : ~ i x 1
                ~ < x - tw 1 {
                    : i c + * y tw x
                    : f l - - - - * 4.0 ( slice_at [f] g c ) ( slice_at [f] g - c 1 ) ( slice_at [f] g + c 1 ) ( slice_at [f] g - c tw ) ( slice_at [f] g + c tw )
                    = sum + sum l
                    = sq + sq * l l
                    = cnt + cnt 1
                    = x + x 1
                }
                = y + y 1
            }
            ? == cnt 0 { ^ -1.0 } {}
            : f mean / sum # f cnt
            ^ - / sq # f cnt * mean mean
        }
    }
}

@ sh_pick ( Vec String ) frames i n i verbose → v {
    : i c ( vec_len [String] frames )
    ? | <= n 0 <= c n { ^ v } {}
    : ( Vec String ) kept ( vec_new [String] )
    : ~ i scored 0
    : ~ i b 0
    ~ < b n {
        : i lo / * b c n
        : i hi / * + b 1 c n
        : ~ i best lo
        ? > - hi lo 1 {
            : ~ f bs -2.0
            : ~ i k lo
            ~ < k hi {
                ?? ( vec_get [String] frames k ) {
                    T p → {
                        : f sc ( sh_score ( string_data p ) )
                        = scored + scored 1
                        ? > sc bs { = bs sc = best k } {}
                    }
                    F → {}
                }
                = k + k 1
            }
        } {}
        ?? ( vec_get [String] frames best ) {
            T p → { ( vec_push [String] kept ( string_from ( string_data p ) ) ) }
            F → {}
        }
        ? != verbose 0 {
            ( nurl_print `select  view ` )
            ( nurl_print ( nurl_str_int + b 1 ) )
            ( nurl_print `/` )
            ( nurl_print ( nurl_str_int n ) )
            ( nurl_print `\r` )
        } {}
        = b + b 1
    }
    ? != verbose 0 {
        ( nurl_print `views   ` )
        ( nurl_print ( nurl_str_int n ) )
        ( nurl_print ` of ` )
        ( nurl_print ( nurl_str_int c ) )
        ( nurl_print `, spread over all of them` )
        ? > scored 0 { ( nurl_print `, the sharpest of each run` ) } {}
        ( nurl_print `\n` )
    } {}
    ( vec_clear [String] frames )
    ( vec_append [String] frames kept )
}
