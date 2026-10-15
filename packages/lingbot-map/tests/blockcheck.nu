// blockcheck.nu — run one full transformer block over a deterministic
// input with deterministic weights and print every output value, in the
// format tests/block_oracle.py emits from the reference Block.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/block.nu`

// The same generator the oracle uses: a bounded, non-repeating sequence
// so nothing is accidentally symmetric.
@ gen ( Slice f ) p i n f phase → v {
    : ~ i j 0
    ~ < j n { ( slice_put [f] p j * 0.3 ( float_sin + phase * 0.019 # f j ) ) = j + j 1 }
}

@ genpos ( Slice f ) p i n f phase f base → v {
    : ~ i j 0
    ~ < j n { ( slice_put [f] p j + base * 0.1 ( float_sin + phase * 0.023 # f j ) ) = j + j 1 }
}

@ case i gw i gh i nspecial i dim i heads i hidden → v {
    : i n + nspecial * gw gh
    : i hd / dim heads
    : ( Vec f ) x__v ( vec_zeroed [f] * n dim )
    : ( Slice f ) x ( slice_from_vec [f] x__v )
    ( gen x * n dim 0.11 )
    : ( Vec f ) n1g__v ( vec_zeroed [f] dim )
    : ( Slice f ) n1g ( slice_from_vec [f] n1g__v ) ( genpos n1g dim 0.2 1.0 )
    : ( Vec f ) n1b__v ( vec_zeroed [f] dim )
    : ( Slice f ) n1b ( slice_from_vec [f] n1b__v ) ( gen n1b dim 0.3 )
    : ( Vec f ) qw__v ( vec_zeroed [f] * * 3 dim dim )
    : ( Slice f ) qw ( slice_from_vec [f] qw__v ) ( gen qw * * 3 dim dim 0.4 )
    : ( Vec f ) qb__v ( vec_zeroed [f] * 3 dim )
    : ( Slice f ) qb ( slice_from_vec [f] qb__v ) ( gen qb * 3 dim 0.5 )
    : ( Vec f ) qng__v ( vec_zeroed [f] hd )
    : ( Slice f ) qng ( slice_from_vec [f] qng__v ) ( genpos qng hd 0.6 1.0 )
    : ( Vec f ) qnb__v ( vec_zeroed [f] hd )
    : ( Slice f ) qnb ( slice_from_vec [f] qnb__v ) ( gen qnb hd 0.7 )
    : ( Vec f ) kng__v ( vec_zeroed [f] hd )
    : ( Slice f ) kng ( slice_from_vec [f] kng__v ) ( genpos kng hd 0.8 1.0 )
    : ( Vec f ) knb__v ( vec_zeroed [f] hd )
    : ( Slice f ) knb ( slice_from_vec [f] knb__v ) ( gen knb hd 0.9 )
    : ( Vec f ) pw__v ( vec_zeroed [f] * dim dim )
    : ( Slice f ) pw ( slice_from_vec [f] pw__v ) ( gen pw * dim dim 1.0 )
    : ( Vec f ) pb__v ( vec_zeroed [f] dim )
    : ( Slice f ) pb ( slice_from_vec [f] pb__v ) ( gen pb dim 1.1 )
    : ( Vec f ) ls1__v ( vec_zeroed [f] dim )
    : ( Slice f ) ls1 ( slice_from_vec [f] ls1__v ) ( genpos ls1 dim 1.2 0.05 )
    : ( Vec f ) n2g__v ( vec_zeroed [f] dim )
    : ( Slice f ) n2g ( slice_from_vec [f] n2g__v ) ( genpos n2g dim 1.3 1.0 )
    : ( Vec f ) n2b__v ( vec_zeroed [f] dim )
    : ( Slice f ) n2b ( slice_from_vec [f] n2b__v ) ( gen n2b dim 1.4 )
    : ( Vec f ) f1w__v ( vec_zeroed [f] * hidden dim )
    : ( Slice f ) f1w ( slice_from_vec [f] f1w__v ) ( gen f1w * hidden dim 1.5 )
    : ( Vec f ) f1b__v ( vec_zeroed [f] hidden )
    : ( Slice f ) f1b ( slice_from_vec [f] f1b__v ) ( gen f1b hidden 1.6 )
    : ( Vec f ) f2w__v ( vec_zeroed [f] * dim hidden )
    : ( Slice f ) f2w ( slice_from_vec [f] f2w__v ) ( gen f2w * dim hidden 1.7 )
    : ( Vec f ) f2b__v ( vec_zeroed [f] dim )
    : ( Slice f ) f2b ( slice_from_vec [f] f2b__v ) ( gen f2b dim 1.8 )
    : ( Vec f ) ls2__v ( vec_zeroed [f] dim )
    : ( Slice f ) ls2 ( slice_from_vec [f] ls2__v ) ( genpos ls2 dim 1.9 0.05 )
    : ( Vec i ) rows__v ( vec_zeroed [i] n )
    : ( Slice i ) rows ( slice_from_vec [i] rows__v )
    : ( Vec i ) cols__v ( vec_zeroed [i] n )
    : ( Slice i ) cols ( slice_from_vec [i] cols__v )
    : ~ i t 0
    ~ < t nspecial { ( slice_put [i] rows t 0 ) ( slice_put [i] cols t 0 ) = t + t 1 }
    : ~ i y 0
    ~ < y gh {
        : ~ i xx 0
        ~ < xx gw {
            : i idx + nspecial + * y gw xx
            ( slice_put [i] rows idx + y 1 )
            ( slice_put [i] cols idx + xx 1 )
            = xx + xx 1
        }
        = y + y 1
    }
    : i maxpos + 2 ? > gw gh gw gh
    : ( Vec f ) ct__v ( vec_zeroed [f] * maxpos / hd 2 )
    : ( Slice f ) ct ( slice_from_vec [f] ct__v )
    : ( Vec f ) st__v ( vec_zeroed [f] * maxpos / hd 2 )
    : ( Slice f ) st ( slice_from_vec [f] st__v )
    ( rope2d_tables / hd 2 maxpos ct st )
    : ( Vec f ) scratch__v ( vec_zeroed [f] + * 4 * n dim * n n )
    : ( Slice f ) scratch ( slice_from_vec [f] scratch__v )
    ( bk_block x n dim heads hidden n1g n1b qw qb qng qnb kng knb pw pb ls1
    n2g n2b f1w f1b f2w f2b ls2 rows cols ct st scratch )
    ( nurl_print `b` ) ( nurl_print ( nurl_str_int gw ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int gh ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int nspecial ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int dim ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int heads ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int hidden ) )
    : ~ i j 0
    ~ < j * n dim { ( nurl_print ` ` ) ( nurl_print ( nurl_str_float ( slice_at [f] x j ) ) ) = j + j 1 }
    ( nurl_print `\n` )
}

@ main → i {
    ( case 3 2 1 16 2 32 )
    ( case 4 3 6 32 4 64 )
    ^ 0
}
