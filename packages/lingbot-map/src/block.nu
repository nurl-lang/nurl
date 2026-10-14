// packages/lingbot-map/src/block.nu — the transformer block, 72 of which
// make up this model (24 DINOv2 + 24 frame + 24 global).
//
//     x = x + ls1 · attn(norm1(x))
//     x = x + ls2 · mlp(norm2(x))
//
// with pre-norm LayerNorm, LayerScale on both residual branches, exact
// (erf) GELU in the MLP, and attention that layer-normalises q and k per
// head before rotating them — `qk_norm=True`, which is not the DINOv2
// default and is easy to drop on the floor when porting.
//
// Host f64, one frame at a time. This is the reference the device path
// has to agree with, and the shape everything downstream is written
// against; the matmuls inside are the only parts that move to kernels.
//
//   ( bk_layernorm x rows cols g b eps out )
//   ( bk_gelu x n out )
//   ( bk_linear x rows k w bias n out )     out = x·Wᵀ + b, W is [n, k]
//   ( bk_attention x n dim heads qkv_w qkv_b qn_g qn_b kn_g kn_b
//                  proj_w proj_b rows cols cos sin out scratch )
//   ( bk_block ... )                        the whole thing

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/rope.nu`

: f BK_EPS 0.000001  // norm1 / norm2: DINOv2's partial(LayerNorm, eps=1e-6)

// q_norm / k_norm use a DIFFERENT eps, and not on purpose: Block builds
// its Attention without passing norm_layer, so the qk norms fall back to
// nn.LayerNorm's default 1e-5 while norm1/norm2 get DINOv2's 1e-6. The
// reference is what it is; matching it means carrying both constants.
: f BK_QK_EPS 0.00001

// out[r, :] = (x[r, :] − mean) / sqrt(var + eps) · g + b, biased variance.
@ bk_layernorm ( Slice f ) x i rows i cols ( Slice f ) g ( Slice f ) b f eps ( Slice f ) out → v {
    ? | <= rows 0 <= cols 0 { ^ v } {}
    : ~ i r 0
    ~ < r rows {
        : i base * r cols
        : ~ f s 0.0
        : ~ i j 0
        ~ < j cols { = s + s ( slice_at [f] x + base j ) = j + j 1 }
        : f mu / s # f cols
        : ~ f q 0.0
        = j 0
        ~ < j cols { : f d - ( slice_at [f] x + base j ) mu = q + q * d d = j + j 1 }
        : f var / q # f cols
        : f inv / 1.0 ( float_sqrt + var eps )
        = j 0
        ~ < j cols {
            ( slice_put [f] out + base j + * * - ( slice_at [f] x + base j ) mu inv ( slice_at [f] g j ) ( slice_at [f] b j ) )
            = j + j 1
        }
        = r + r 1
    }
}

// Exact GELU: x · Φ(x) = 0.5x(1 + erf(x/√2)). torch's nn.GELU default is
// the exact form, NOT the tanh approximation — they differ in the fourth
// decimal, which is plenty to move a pose.
@ bk_gelu ( Slice f ) x i n ( Slice f ) out → v {
    : ~ i j 0
    ~ < j n {
        : f v ( slice_at [f] x j )
        ( slice_put [f] out j * * 0.5 v + 1.0 ( float_erf / v 1.4142135623730951 ) )
        = j + j 1
    }
}

// out[rows, n] = x[rows, k] · weightᵀ + bias, weight laid out [n, k]
// (torch's nn.Linear order). bias may be a null pointer for no bias.
@ bk_linear ( Slice f ) x i rows i k ( Slice f ) weight ( Slice f ) bias i n ( Slice f ) out → v {
    : ~ i r 0
    ~ < r rows {
        : i xr * r k
        : ~ i o 0
        ~ < o n {
            : i wr * o k
            : ~ f acc 0.0
            : ~ i j 0
            ~ < j k { = acc + acc * ( slice_at [f] x + xr j ) ( slice_at [f] weight + wr j ) = j + j 1 }
            ( slice_put [f] out + * r n o ? == # i bias 0 acc + acc ( slice_at [f] bias o ) )
            = o + o 1
        }
        = r + r 1
    }
}

// Softmax over the last axis, max-subtracted.
@ bk_softmax_rows ( Slice f ) x i rows i cols → v {
    : ~ i r 0
    ~ < r rows {
        : i base * r cols
        : ~ f m ( slice_at [f] x base )
        : ~ i j 1
        ~ < j cols { ? > ( slice_at [f] x + base j ) m { = m ( slice_at [f] x + base j ) } {} = j + j 1 }
        : ~ f s 0.0
        = j 0
        ~ < j cols {
            : f e ( float_exp - ( slice_at [f] x + base j ) m )
            ( slice_put [f] x + base j e )
            = s + s e
            = j + j 1
        }
        = j 0
        ~ < j cols { ( slice_put [f] x + base j / ( slice_at [f] x + base j ) s ) = j + j 1 }
        = r + r 1
    }
}

// Multi-head self-attention with per-head qk LayerNorm and 2-D RoPE.
//
// `scratch` must hold at least 3·n·dim + n·n doubles: q, k, v laid out
// [heads, n, head_dim] and then one attention matrix.
@ bk_attention ( Slice f ) x i n i dim i heads ( Slice f ) qkv_w ( Slice f ) qkv_b
( Slice f ) qn_g ( Slice f ) qn_b ( Slice f ) kn_g ( Slice f ) kn_b ( Slice f ) proj_w ( Slice f ) proj_b
( Slice i ) grow ( Slice i ) gcol ( Slice f ) cos_t ( Slice f ) sin_t ( Slice f ) out ( Slice f ) scratch → v {
    ? | | <= n 0 <= heads 0 != % dim heads 0 { ^ v } {}
    : i hd / dim heads
    : i nd * n dim
    // q/k/v are [heads, n, head_dim]: a head's stride is n*hd, NOT n*dim.
    // Using nd here leaves every head past the first reading zeros — and
    // the attention still produces plausible numbers, so it shows up as a
    // few percent of error rather than as anything obviously broken.
    : i hs * n hd
    : ( Vec f ) qkv__v ( vec_zeroed [f] * 3 nd )
    : ( Slice f ) qkv ( slice_from_vec [f] qkv__v )
    ( bk_linear x n dim qkv_w qkv_b * 3 dim qkv )
    // [n, 3, heads, hd] → q/k/v each [heads, n, hd]
    : ( Slice f ) q ( slice_window [f] scratch 0 nd )
    : ( Slice f ) k ( slice_window [f] scratch nd nd )
    : ( Slice f ) v ( slice_window [f] scratch * 2 nd nd )
    : ~ i t 0
    ~ < t n {
        : ~ i h 0
        ~ < h heads {
            : ~ i d 0
            ~ < d hd {
                : i src + * t * 3 dim + * h hd d
                : i dst + * h hs * t hd
                ( slice_put [f] q + dst d ( slice_at [f] qkv src ) )
                ( slice_put [f] k + dst d ( slice_at [f] qkv + src dim ) )
                ( slice_put [f] v + dst d ( slice_at [f] qkv + src * 2 dim ) )
                = d + d 1
            }
            = h + h 1
        }
        = t + t 1
    }
    // qk LayerNorm is per HEAD, over head_dim — heads·n independent rows
    // qk-norm and rope are both optional and both signalled by an empty
    // slice: DINOv2's own blocks have neither (they add a position
    // embedding at the input instead), the aggregator's frame and global
    // blocks have both.
    ? > ( slice_len [f] qn_g ) 0 {
        ( bk_layernorm q * heads n hd qn_g qn_b BK_QK_EPS q )
        ( bk_layernorm k * heads n hd kn_g kn_b BK_QK_EPS k )
    } {}
    ? > ( slice_len [f] cos_t ) 0 {
        ( rope2d_apply q heads n hd grow gcol cos_t sin_t )
        ( rope2d_apply k heads n hd grow gcol cos_t sin_t )
    } {}
    // scaled dot-product attention, per head
    : ( Slice f ) att ( slice_window [f] scratch * 3 nd * n n )
    : f scale / 1.0 ( float_sqrt # f hd )
    : ( Vec f ) ctx__v ( vec_zeroed [f] nd )
    : ( Slice f ) ctx ( slice_from_vec [f] ctx__v )
    : ~ i h 0
    ~ < h heads {
        : i hb * h hs
        : ~ i i0 0
        ~ < i0 n {
            : ~ i j 0
            ~ < j n {
                : ~ f acc 0.0
                : ~ i d 0
                ~ < d hd { = acc + acc * ( slice_at [f] q + hb + * i0 hd d ) ( slice_at [f] k + hb + * j hd d ) = d + d 1 }
                ( slice_put [f] att + * i0 n j * acc scale )
                = j + j 1
            }
            = i0 + i0 1
        }
        ( bk_softmax_rows att n n )
        = i0 0
        ~ < i0 n {
            : ~ i d 0
            ~ < d hd {
                : ~ f acc 0.0
                : ~ i j 0
                ~ < j n { = acc + acc * ( slice_at [f] att + * i0 n j ) ( slice_at [f] v + hb + * j hd d ) = j + j 1 }
                ( slice_put [f] ctx + * i0 dim + * h hd d acc )
                = d + d 1
            }
            = i0 + i0 1
        }
        = h + h 1
    }
    ( bk_linear ctx n dim proj_w proj_b dim out )
}

// One full transformer block.
//
//   x ← x + ls1 · attn(norm1(x))
//   x ← x + ls2 · mlp(norm2(x))
//
// `x` is [n, dim] and is updated in place. `scratch` needs
// 3·n·dim + n·n + n·dim + n·hidden doubles.
@ bk_block ( Slice f ) x i n i dim i heads i hidden
( Slice f ) n1_g ( Slice f ) n1_b ( Slice f ) qkv_w ( Slice f ) qkv_b
( Slice f ) qn_g ( Slice f ) qn_b ( Slice f ) kn_g ( Slice f ) kn_b ( Slice f ) proj_w ( Slice f ) proj_b ( Slice f ) ls1
( Slice f ) n2_g ( Slice f ) n2_b ( Slice f ) fc1_w ( Slice f ) fc1_b ( Slice f ) fc2_w ( Slice f ) fc2_b ( Slice f ) ls2
( Slice i ) grow ( Slice i ) gcol ( Slice f ) cos_t ( Slice f ) sin_t ( Slice f ) scratch → v {
    : i nd * n dim
    : ( Vec f ) norm__v ( vec_zeroed [f] nd )
    : ( Slice f ) norm ( slice_from_vec [f] norm__v )
    : ( Vec f ) branch__v ( vec_zeroed [f] nd )
    : ( Slice f ) branch ( slice_from_vec [f] branch__v )
    : ( Vec f ) hid__v ( vec_zeroed [f] * n hidden )
    : ( Slice f ) hid ( slice_from_vec [f] hid__v )

    ( bk_layernorm x n dim n1_g n1_b BK_EPS norm )
    ( bk_attention norm n dim heads qkv_w qkv_b qn_g qn_b kn_g kn_b
    proj_w proj_b grow gcol cos_t sin_t branch scratch )
    : ~ i j 0
    ~ < j nd { ( slice_put [f] x j + ( slice_at [f] x j ) * ( slice_at [f] branch j ) ( slice_at [f] ls1 % j dim ) ) = j + j 1 }

    ( bk_layernorm x n dim n2_g n2_b BK_EPS norm )
    ( bk_linear norm n dim fc1_w fc1_b hidden hid )
    ( bk_gelu hid * n hidden hid )
    ( bk_linear hid n hidden fc2_w fc2_b dim branch )
    = j 0
    ~ < j nd { ( slice_put [f] x j + ( slice_at [f] x j ) * ( slice_at [f] branch j ) ( slice_at [f] ls2 % j dim ) ) = j + j 1 }

}
