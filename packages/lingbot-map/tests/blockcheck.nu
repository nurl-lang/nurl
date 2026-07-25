// blockcheck.nu — run one full transformer block over a deterministic
// input with deterministic weights and print every output value, in the
// format tests/block_oracle.py emits from the reference Block.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/block.nu`

// The same generator the oracle uses: a bounded, non-repeating sequence
// so nothing is accidentally symmetric.
@ gen * f p i n f phase → v {
    : ~ i j 0
    ~ < j n { = . p j * 0.3 ( float_sin + phase * 0.019 # f j ) = j + j 1 }
}

@ genpos * f p i n f phase f base → v {
    : ~ i j 0
    ~ < j n { = . p j + base * 0.1 ( float_sin + phase * 0.023 # f j ) = j + j 1 }
}

@ case i gw i gh i nspecial i dim i heads i hidden → v {
    : i n + nspecial * gw gh
    : i hd / dim heads
    : *f x # *f ( nurl_zalloc * 8 * n dim )
    ( gen x * n dim 0.11 )
    : *f n1g # *f ( nurl_zalloc * 8 dim ) ( genpos n1g dim 0.2 1.0 )
    : *f n1b # *f ( nurl_zalloc * 8 dim ) ( gen n1b dim 0.3 )
    : *f qw # *f ( nurl_zalloc * 8 * * 3 dim dim ) ( gen qw * * 3 dim dim 0.4 )
    : *f qb # *f ( nurl_zalloc * 8 * 3 dim ) ( gen qb * 3 dim 0.5 )
    : *f qng # *f ( nurl_zalloc * 8 hd ) ( genpos qng hd 0.6 1.0 )
    : *f qnb # *f ( nurl_zalloc * 8 hd ) ( gen qnb hd 0.7 )
    : *f kng # *f ( nurl_zalloc * 8 hd ) ( genpos kng hd 0.8 1.0 )
    : *f knb # *f ( nurl_zalloc * 8 hd ) ( gen knb hd 0.9 )
    : *f pw # *f ( nurl_zalloc * 8 * dim dim ) ( gen pw * dim dim 1.0 )
    : *f pb # *f ( nurl_zalloc * 8 dim ) ( gen pb dim 1.1 )
    : *f ls1 # *f ( nurl_zalloc * 8 dim ) ( genpos ls1 dim 1.2 0.05 )
    : *f n2g # *f ( nurl_zalloc * 8 dim ) ( genpos n2g dim 1.3 1.0 )
    : *f n2b # *f ( nurl_zalloc * 8 dim ) ( gen n2b dim 1.4 )
    : *f f1w # *f ( nurl_zalloc * 8 * hidden dim ) ( gen f1w * hidden dim 1.5 )
    : *f f1b # *f ( nurl_zalloc * 8 hidden ) ( gen f1b hidden 1.6 )
    : *f f2w # *f ( nurl_zalloc * 8 * dim hidden ) ( gen f2w * dim hidden 1.7 )
    : *f f2b # *f ( nurl_zalloc * 8 dim ) ( gen f2b dim 1.8 )
    : *f ls2 # *f ( nurl_zalloc * 8 dim ) ( genpos ls2 dim 1.9 0.05 )
    : *i rows # *i ( nurl_zalloc * 8 n )
    : *i cols # *i ( nurl_zalloc * 8 n )
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
    : i maxpos + 2 ? > gw gh gw gh
    : *f ct # *f ( nurl_zalloc * 8 * maxpos / hd 2 )
    : *f st # *f ( nurl_zalloc * 8 * maxpos / hd 2 )
    ( rope2d_tables / hd 2 maxpos ct st )
    : *f scratch # *f ( nurl_zalloc * 8 + * 4 * n dim * n n )
    ( bk_block x n dim heads hidden n1g n1b qw qb qng qnb kng knb pw pb ls1
    n2g n2b f1w f1b f2w f2b ls2 rows cols ct st scratch )
    ( nurl_print `b` ) ( nurl_print ( nurl_str_int gw ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int gh ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int nspecial ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int dim ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int heads ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int hidden ) )
    : ~ i j 0
    ~ < j * n dim { ( nurl_print ` ` ) ( nurl_print ( nurl_str_float . x j ) ) = j + j 1 }
    ( nurl_print `\n` )
    ( nurl_free # s x ) ( nurl_free # s n1g ) ( nurl_free # s n1b )
    ( nurl_free # s qw ) ( nurl_free # s qb ) ( nurl_free # s qng )
    ( nurl_free # s qnb ) ( nurl_free # s kng ) ( nurl_free # s knb )
    ( nurl_free # s pw ) ( nurl_free # s pb ) ( nurl_free # s ls1 )
    ( nurl_free # s n2g ) ( nurl_free # s n2b ) ( nurl_free # s f1w )
    ( nurl_free # s f1b ) ( nurl_free # s f2w ) ( nurl_free # s f2b )
    ( nurl_free # s ls2 ) ( nurl_free # s rows ) ( nurl_free # s cols )
    ( nurl_free # s ct ) ( nurl_free # s st ) ( nurl_free # s scratch )
}

@ main → i {
    ( case 3 2 1 16 2 32 )
    ( case 4 3 6 32 4 64 )
    ^ 0
}
