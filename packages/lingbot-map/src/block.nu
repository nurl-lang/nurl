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
@ bk_layernorm * f x i rows i cols * f g * f b f eps * f out → v {
    ? | <= rows 0 <= cols 0 { ^ v } {}
    : ~ i r 0
    ~ < r rows {
        : i base * r cols
        : ~ f s 0.0
        : ~ i j 0
        ~ < j cols { = s + s . x + base j = j + j 1 }
        : f mu / s # f cols
        : ~ f q 0.0
        = j 0
        ~ < j cols { : f d - . x + base j mu = q + q * d d = j + j 1 }
        : f var / q # f cols
        : f inv / 1.0 ( float_sqrt + var eps )
        = j 0
        ~ < j cols {
            = . out + base j + * * - . x + base j mu inv . g j . b j
            = j + j 1
        }
        = r + r 1
    }
}

// Exact GELU: x · Φ(x) = 0.5x(1 + erf(x/√2)). torch's nn.GELU default is
// the exact form, NOT the tanh approximation — they differ in the fourth
// decimal, which is plenty to move a pose.
@ bk_gelu * f x i n * f out → v {
    : ~ i j 0
    ~ < j n {
        : f v . x j
        = . out j * * 0.5 v + 1.0 ( float_erf / v 1.4142135623730951 )
        = j + j 1
    }
}

// out[rows, n] = x[rows, k] · weightᵀ + bias, weight laid out [n, k]
// (torch's nn.Linear order). bias may be a null pointer for no bias.
@ bk_linear * f x i rows i k * f weight * f bias i n * f out → v {
    : ~ i r 0
    ~ < r rows {
        : i xr * r k
        : ~ i o 0
        ~ < o n {
            : i wr * o k
            : ~ f acc 0.0
            : ~ i j 0
            ~ < j k { = acc + acc * . x + xr j . weight + wr j = j + j 1 }
            = . out + * r n o ? == # i bias 0 acc + acc . bias o
            = o + o 1
        }
        = r + r 1
    }
}

// Softmax over the last axis, max-subtracted.
@ bk_softmax_rows * f x i rows i cols → v {
    : ~ i r 0
    ~ < r rows {
        : i base * r cols
        : ~ f m . x base
        : ~ i j 1
        ~ < j cols { ? > . x + base j m { = m . x + base j } {} = j + j 1 }
        : ~ f s 0.0
        = j 0
        ~ < j cols {
            : f e ( float_exp - . x + base j m )
            = . x + base j e
            = s + s e
            = j + j 1
        }
        = j 0
        ~ < j cols { = . x + base j / . x + base j s = j + j 1 }
        = r + r 1
    }
}

// Multi-head self-attention with per-head qk LayerNorm and 2-D RoPE.
//
// `scratch` must hold at least 3·n·dim + n·n doubles: q, k, v laid out
// [heads, n, head_dim] and then one attention matrix.
@ bk_attention * f x i n i dim i heads * f qkv_w * f qkv_b
* f qn_g * f qn_b * f kn_g * f kn_b * f proj_w * f proj_b
* i grow * i gcol * f cos_t * f sin_t * f out * f scratch → v {
    ? | | <= n 0 <= heads 0 != % dim heads 0 { ^ v } {}
    : i hd / dim heads
    : i nd * n dim
    // q/k/v are [heads, n, head_dim]: a head's stride is n*hd, NOT n*dim.
    // Using nd here leaves every head past the first reading zeros — and
    // the attention still produces plausible numbers, so it shows up as a
    // few percent of error rather than as anything obviously broken.
    : i hs * n hd
    : *f qkv # *f ( nurl_zalloc * 8 * 3 nd )
    ( bk_linear x n dim qkv_w qkv_b * 3 dim qkv )
    // [n, 3, heads, hd] → q/k/v each [heads, n, hd]
    : *f q scratch
    : *f k # *f + # i scratch * 8 nd
    : *f v # *f + # i scratch * 8 * 2 nd
    : ~ i t 0
    ~ < t n {
        : ~ i h 0
        ~ < h heads {
            : ~ i d 0
            ~ < d hd {
                : i src + * t * 3 dim + * h hd d
                : i dst + * h hs * t hd
                = . q + dst d . qkv src
                = . k + dst d . qkv + src dim
                = . v + dst d . qkv + src * 2 dim
                = d + d 1
            }
            = h + h 1
        }
        = t + t 1
    }
    ( nurl_free # s qkv )
    // qk LayerNorm is per HEAD, over head_dim — heads·n independent rows
    // qk-norm and rope are both optional and both signalled by a null
    // pointer: DINOv2's own blocks have neither (they add a position
    // embedding at the input instead), the aggregator's frame and global
    // blocks have both.
    ? != # i qn_g 0 {
        ( bk_layernorm q * heads n hd qn_g qn_b BK_QK_EPS q )
        ( bk_layernorm k * heads n hd kn_g kn_b BK_QK_EPS k )
    } {}
    ? != # i cos_t 0 {
        ( rope2d_apply q heads n hd grow gcol cos_t sin_t )
        ( rope2d_apply k heads n hd grow gcol cos_t sin_t )
    } {}
    // scaled dot-product attention, per head
    : *f att # *f + # i scratch * 8 * 3 nd
    : f scale / 1.0 ( float_sqrt # f hd )
    : *f ctx # *f ( nurl_zalloc * 8 nd )
    : ~ i h 0
    ~ < h heads {
        : i hb * h hs
        : ~ i i0 0
        ~ < i0 n {
            : ~ i j 0
            ~ < j n {
                : ~ f acc 0.0
                : ~ i d 0
                ~ < d hd { = acc + acc * . q + hb + * i0 hd d . k + hb + * j hd d = d + d 1 }
                = . att + * i0 n j * acc scale
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
                ~ < j n { = acc + acc * . att + * i0 n j . v + hb + * j hd d = j + j 1 }
                = . ctx + * i0 dim + * h hd d acc
                = d + d 1
            }
            = i0 + i0 1
        }
        = h + h 1
    }
    ( bk_linear ctx n dim proj_w proj_b dim out )
    ( nurl_free # s ctx )
}

// One full transformer block.
//
//   x ← x + ls1 · attn(norm1(x))
//   x ← x + ls2 · mlp(norm2(x))
//
// `x` is [n, dim] and is updated in place. `scratch` needs
// 3·n·dim + n·n + n·dim + n·hidden doubles.
@ bk_block * f x i n i dim i heads i hidden
* f n1_g * f n1_b * f qkv_w * f qkv_b
* f qn_g * f qn_b * f kn_g * f kn_b * f proj_w * f proj_b * f ls1
* f n2_g * f n2_b * f fc1_w * f fc1_b * f fc2_w * f fc2_b * f ls2
* i grow * i gcol * f cos_t * f sin_t * f scratch → v {
    : i nd * n dim
    : *f norm # *f ( nurl_zalloc * 8 nd )
    : *f branch # *f ( nurl_zalloc * 8 nd )
    : *f hid # *f ( nurl_zalloc * 8 * n hidden )

    ( bk_layernorm x n dim n1_g n1_b BK_EPS norm )
    ( bk_attention norm n dim heads qkv_w qkv_b qn_g qn_b kn_g kn_b
    proj_w proj_b grow gcol cos_t sin_t branch scratch )
    : ~ i j 0
    ~ < j nd { = . x j + . x j * . branch j . ls1 % j dim = j + j 1 }

    ( bk_layernorm x n dim n2_g n2_b BK_EPS norm )
    ( bk_linear norm n dim fc1_w fc1_b hidden hid )
    ( bk_gelu hid * n hidden hid )
    ( bk_linear hid n hidden fc2_w fc2_b dim branch )
    = j 0
    ~ < j nd { = . x j + . x j * . branch j . ls2 % j dim = j + j 1 }

    ( nurl_free # s norm )
    ( nurl_free # s branch )
    ( nurl_free # s hid )
}
