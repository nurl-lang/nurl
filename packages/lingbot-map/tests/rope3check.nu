// rope3check.nu — apply the 3-D rope to a deterministic tensor and print
// every value, in the format tests/rope3_oracle.py emits from the
// reference WanRotaryPosEmbed + apply_rotary_emb.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/rope.nu`

: i PSI 6  // special tokens per frame: camera + 4 registers + scale

@ case i heads i ppf i pph i ppw i fstart → v {
    : i per + PSI * pph ppw
    : i n * ppf per
    : i dim 64
    : ( Vec f ) x__v ( vec_zeroed [f] * heads * n dim )
    : ( Slice f ) x ( slice_from_vec [f] x__v )
    : ( Vec i ) fr__v ( vec_zeroed [i] n )
    : ( Slice i ) fr ( slice_from_vec [i] fr__v )
    : ( Vec i ) rw__v ( vec_zeroed [i] n )
    : ( Slice i ) rw ( slice_from_vec [i] rw__v )
    : ( Vec i ) cl__v ( vec_zeroed [i] n )
    : ( Slice i ) cl ( slice_from_vec [i] cl__v )
    : ~ i t 0
    ~ < t * heads * n dim {
        ( slice_put [f] x t ( float_sin + 0.13 * 0.017 # f t ) )
        = t + t 1
    }
    // token layout: per frame, the special tokens on the diagonal
    // (f, j, j), then the patch grid offset by PSI on both axes
    : ~ i f 0
    ~ < f ppf {
        : i fbase * f per
        : ~ i j 0
        ~ < j PSI {
            ( slice_put [i] fr + fbase j + fstart f )
            ( slice_put [i] rw + fbase j j )
            ( slice_put [i] cl + fbase j j )
            = j + j 1
        }
        : ~ i y 0
        ~ < y pph {
            : ~ i xx 0
            ~ < xx ppw {
                : i idx + fbase + PSI + * y ppw xx
                ( slice_put [i] fr idx + fstart f )
                ( slice_put [i] rw idx + PSI y )
                ( slice_put [i] cl idx + PSI xx )
                = xx + xx 1
            }
            = y + y 1
        }
        = f + f 1
    }
    : i maxpos 1024
    : ( Vec f ) ct__v ( vec_zeroed [f] * maxpos ( rope3d_width ) )
    : ( Slice f ) ct ( slice_from_vec [f] ct__v )
    : ( Vec f ) st__v ( vec_zeroed [f] * maxpos ( rope3d_width ) )
    : ( Slice f ) st ( slice_from_vec [f] st__v )
    ( rope3d_tables maxpos ct st )
    ( rope3d_apply x heads n dim fr rw cl ct st )
    ( nurl_print `w` ) ( nurl_print ( nurl_str_int heads ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int ppf ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int pph ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int ppw ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int fstart ) )
    : ~ i j 0
    ~ < j * heads * n dim {
        ( nurl_print ` ` ) ( nurl_print ( nurl_str_float ( slice_at [f] x j ) ) )
        = j + j 1
    }
    ( nurl_print `\n` )
}

@ main → i {
    ( case 2 1 3 4 0 )
    ( case 1 3 2 2 0 )
    ( case 2 2 3 2 7 )  // a non-zero frame start: the streaming case
    ^ 0
}
