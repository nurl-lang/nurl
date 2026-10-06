// blockcheck.nu — run one full transformer block over a deterministic
// input with deterministic weights and print every output value, in the
// format tests/block_oracle.py emits from the reference Block.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/block.nu`

// The same generator the oracle uses: a bounded, non-repeating sequence
// so nothing is accidentally symmetric.
unsafe

@ gen * f p i n f phase → v {
    : ~ i j 0
    ~ < j n { = . p j * 0.3 ( float_sin + phase * 0.019 # f j ) = j + j 1 }
}

unsafe

@ genpos * f p i n f phase f base → v {
    : ~ i j 0
    ~ < j n { = . p j + base * 0.1 ( float_sin + phase * 0.023 # f j ) = j + j 1 }
}

unsafe

@ case i gw i gh i nspecial i dim i heads i hidden → v {
    : i n + nspecial * gw gh
    : i hd / dim heads
    : ( Vec u ) x__v ( vec_zeroed [u] * 8 * n dim )
    : *f x # *f ( vec_data [u] x__v )
    ( gen x * n dim 0.11 )
    : ( Vec u ) n1g__v ( vec_zeroed [u] * 8 dim )
    : *f n1g # *f ( vec_data [u] n1g__v ) ( genpos n1g dim 0.2 1.0 )
    : ( Vec u ) n1b__v ( vec_zeroed [u] * 8 dim )
    : *f n1b # *f ( vec_data [u] n1b__v ) ( gen n1b dim 0.3 )
    : ( Vec u ) qw__v ( vec_zeroed [u] * 8 * * 3 dim dim )
    : *f qw # *f ( vec_data [u] qw__v ) ( gen qw * * 3 dim dim 0.4 )
    : ( Vec u ) qb__v ( vec_zeroed [u] * 8 * 3 dim )
    : *f qb # *f ( vec_data [u] qb__v ) ( gen qb * 3 dim 0.5 )
    : ( Vec u ) qng__v ( vec_zeroed [u] * 8 hd )
    : *f qng # *f ( vec_data [u] qng__v ) ( genpos qng hd 0.6 1.0 )
    : ( Vec u ) qnb__v ( vec_zeroed [u] * 8 hd )
    : *f qnb # *f ( vec_data [u] qnb__v ) ( gen qnb hd 0.7 )
    : ( Vec u ) kng__v ( vec_zeroed [u] * 8 hd )
    : *f kng # *f ( vec_data [u] kng__v ) ( genpos kng hd 0.8 1.0 )
    : ( Vec u ) knb__v ( vec_zeroed [u] * 8 hd )
    : *f knb # *f ( vec_data [u] knb__v ) ( gen knb hd 0.9 )
    : ( Vec u ) pw__v ( vec_zeroed [u] * 8 * dim dim )
    : *f pw # *f ( vec_data [u] pw__v ) ( gen pw * dim dim 1.0 )
    : ( Vec u ) pb__v ( vec_zeroed [u] * 8 dim )
    : *f pb # *f ( vec_data [u] pb__v ) ( gen pb dim 1.1 )
    : ( Vec u ) ls1__v ( vec_zeroed [u] * 8 dim )
    : *f ls1 # *f ( vec_data [u] ls1__v ) ( genpos ls1 dim 1.2 0.05 )
    : ( Vec u ) n2g__v ( vec_zeroed [u] * 8 dim )
    : *f n2g # *f ( vec_data [u] n2g__v ) ( genpos n2g dim 1.3 1.0 )
    : ( Vec u ) n2b__v ( vec_zeroed [u] * 8 dim )
    : *f n2b # *f ( vec_data [u] n2b__v ) ( gen n2b dim 1.4 )
    : ( Vec u ) f1w__v ( vec_zeroed [u] * 8 * hidden dim )
    : *f f1w # *f ( vec_data [u] f1w__v ) ( gen f1w * hidden dim 1.5 )
    : ( Vec u ) f1b__v ( vec_zeroed [u] * 8 hidden )
    : *f f1b # *f ( vec_data [u] f1b__v ) ( gen f1b hidden 1.6 )
    : ( Vec u ) f2w__v ( vec_zeroed [u] * 8 * dim hidden )
    : *f f2w # *f ( vec_data [u] f2w__v ) ( gen f2w * dim hidden 1.7 )
    : ( Vec u ) f2b__v ( vec_zeroed [u] * 8 dim )
    : *f f2b # *f ( vec_data [u] f2b__v ) ( gen f2b dim 1.8 )
    : ( Vec u ) ls2__v ( vec_zeroed [u] * 8 dim )
    : *f ls2 # *f ( vec_data [u] ls2__v ) ( genpos ls2 dim 1.9 0.05 )
    : ( Vec u ) rows__v ( vec_zeroed [u] * 8 n )
    : *i rows # *i ( vec_data [u] rows__v )
    : ( Vec u ) cols__v ( vec_zeroed [u] * 8 n )
    : *i cols # *i ( vec_data [u] cols__v )
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
    : ( Vec u ) ct__v ( vec_zeroed [u] * 8 * maxpos / hd 2 )
    : *f ct # *f ( vec_data [u] ct__v )
    : ( Vec u ) st__v ( vec_zeroed [u] * 8 * maxpos / hd 2 )
    : *f st # *f ( vec_data [u] st__v )
    ( rope2d_tables / hd 2 maxpos ct st )
    : ( Vec u ) scratch__v ( vec_zeroed [u] * 8 + * 4 * n dim * n n )
    : *f scratch # *f ( vec_data [u] scratch__v )
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
}

@ main → i {
    ( case 3 2 1 16 2 32 )
    ( case 4 3 6 32 4 64 )
    ^ 0
}
