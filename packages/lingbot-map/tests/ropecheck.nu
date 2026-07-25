// ropecheck.nu — apply rope2d to a deterministic q tensor and print
// every value, in the format tests/rope_oracle.py emits from the
// reference RotaryPositionEmbedding2D.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/rope.nu`

@ case i heads i gw i gh i dim i nspecial → v {
    : i npatch * gw gh
    : i n + nspecial npatch
    : *f x # *f ( nurl_zalloc * 8 * heads * n dim )
    : *i rows # *i ( nurl_zalloc * 8 n )
    : *i cols # *i ( nurl_zalloc * 8 n )
    // special tokens at (0,0); patches at (y+1, x+1), row-major
    : ~ i t 0
    ~ < t nspecial { = . rows t 0 = . cols t 0 = t + t 1 }
    : ~ i y 0
    ~ < y gh {
        : ~ i xx 0
        ~ < xx gw {
            : i idx + nspecial + * y gw xx
            = . rows idx + y 1
            = . cols idx + xx 1
            = xx + xx 1
        }
        = y + y 1
    }
    : ~ i h 0
    ~ < h heads {
        = t 0
        ~ < t n {
            : ~ i d 0
            ~ < d dim {
                : f v ( float_sin + 0.11 * 0.37 # f + * h 1000 + * t 7 d )
                = . x + * h * n dim + * t dim d v
                = d + d 1
            }
            = t + t 1
        }
        = h + h 1
    }
    : i maxpos + 2 ? > gw gh gw gh
    : *f ct # *f ( nurl_zalloc * 8 * maxpos / dim 2 )
    : *f st # *f ( nurl_zalloc * 8 * maxpos / dim 2 )
    ( rope2d_tables / dim 2 maxpos ct st )
    ( rope2d_apply x heads n dim rows cols ct st )
    ( nurl_print `r` ) ( nurl_print ( nurl_str_int heads ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int gw ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int gh ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int dim ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int nspecial ) )
    : ~ i j 0
    ~ < j * heads * n dim {
        ( nurl_print ` ` ) ( nurl_print ( nurl_str_float . x j ) )
        = j + j 1
    }
    ( nurl_print `\n` )
    ( nurl_free # s x ) ( nurl_free # s rows ) ( nurl_free # s cols )
    ( nurl_free # s ct ) ( nurl_free # s st )
}

@ main → i {
    ( case 2 3 2 8 1 )
    ( case 1 4 4 16 6 )
    ( case 3 5 2 8 0 )
    ^ 0
}
