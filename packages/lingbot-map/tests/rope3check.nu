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
    : *f x # *f ( nurl_zalloc * 8 * heads * n dim )
    : *i fr # *i ( nurl_zalloc * 8 n )
    : *i rw # *i ( nurl_zalloc * 8 n )
    : *i cl # *i ( nurl_zalloc * 8 n )
    : ~ i t 0
    ~ < t * heads * n dim {
        = . x t ( float_sin + 0.13 * 0.017 # f t )
        = t + t 1
    }
    // token layout: per frame, the special tokens on the diagonal
    // (f, j, j), then the patch grid offset by PSI on both axes
    : ~ i f 0
    ~ < f ppf {
        : i fbase * f per
        : ~ i j 0
        ~ < j PSI {
            = . fr + fbase j + fstart f
            = . rw + fbase j j
            = . cl + fbase j j
            = j + j 1
        }
        : ~ i y 0
        ~ < y pph {
            : ~ i xx 0
            ~ < xx ppw {
                : i idx + fbase + PSI + * y ppw xx
                = . fr idx + fstart f
                = . rw idx + PSI y
                = . cl idx + PSI xx
                = xx + xx 1
            }
            = y + y 1
        }
        = f + f 1
    }
    : i maxpos 1024
    : *f ct # *f ( nurl_zalloc * 8 * maxpos ( rope3d_width ) )
    : *f st # *f ( nurl_zalloc * 8 * maxpos ( rope3d_width ) )
    ( rope3d_tables maxpos ct st )
    ( rope3d_apply x heads n dim fr rw cl ct st )
    ( nurl_print `w` ) ( nurl_print ( nurl_str_int heads ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int ppf ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int pph ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int ppw ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int fstart ) )
    : ~ i j 0
    ~ < j * heads * n dim {
        ( nurl_print ` ` ) ( nurl_print ( nurl_str_float . x j ) )
        = j + j 1
    }
    ( nurl_print `\n` )
    ( nurl_free # s x ) ( nurl_free # s fr ) ( nurl_free # s rw )
    ( nurl_free # s cl ) ( nurl_free # s ct ) ( nurl_free # s st )
}

@ main → i {
    ( case 2 1 3 4 0 )
    ( case 1 3 2 2 0 )
    ( case 2 2 3 2 7 )  // a non-zero frame start: the streaming case
    ^ 0
}
