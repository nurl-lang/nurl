// packages/lingbot-map/src/rope.nu — 2-D rotary position embedding.
//
// The aggregator's attention rotates q and k by the token's position in
// the patch GRID, not its index in the sequence: the head dimension is
// split in half, the first half rotated by the row coordinate and the
// second by the column. That is what makes a token's relationship to its
// neighbour above the same as to its neighbour to the left.
//
// Following the reference (`RotaryPositionEmbedding2D`, frequency 100):
//
//   half   = D / 2                     features per spatial axis
//   inv_f  = 100 ^ −(2i / half)        i = 0 … half/2 − 1
//   angles = pos · inv_f, concatenated with itself → half values
//   out    = x · cos(angles) + rotate(x) · sin(angles)
//   rotate = (x₁, x₂) ↦ (−x₂, x₁)      split at half/2
//
// Two details that are easy to get wrong and silent when wrong:
//
//   * the rotation splits each HALF at half/2, not the full D at D/2;
//   * `positions` carries (row, col) in that order, and row drives the
//     first half. Swapping them transposes the model's idea of the
//     image without changing any shape.
//
// Special tokens (camera / register / scale) sit at position 0 and the
// patches start at 1 — see the caller; this module just applies what it
// is given.
//
//   ( rope2d_tables half maxpos cos sin )  → v   tables, [maxpos, half]
//   ( rope2d_apply x heads n dim rows cols cos sin ) → v   in place

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`

: f ROPE_FREQ 100.0

// cos/sin tables for one spatial axis: [maxpos, half] each.
// `half` is the per-axis feature count (D/2) and must be even.
//
// `maxpos` only has to exceed the largest COORDINATE, not the token
// count — entry p depends on p alone. The reference sizes its table by
// the sequence length, which is simply a generous upper bound (783
// tokens for a 37x21 grid whose largest coordinate is 37).
@ rope2d_tables i half i maxpos * f cos_t * f sin_t → v {
    ? | <= half 0 <= maxpos 0 { ^ v } {}
    : i quarter / half 2
    : ~ i p 0
    ~ < p maxpos {
        : ~ i i0 0
        ~ < i0 quarter {
            // exponent 2i/half, so inv_freq = 100^-(2i/half)
            : f expo / # f * 2 i0 # f half
            : f inv / 1.0 ( float_pow ROPE_FREQ expo )
            : f ang * # f p inv
            : f c ( float_cos ang )
            : f s ( float_sin ang )
            // the table is the angle block concatenated with itself
            = . cos_t + * p half i0 c
            = . cos_t + * p half + i0 quarter c
            = . sin_t + * p half i0 s
            = . sin_t + * p half + i0 quarter s
            = i0 + i0 1
        }
        = p + p 1
    }
}

// Rotate `x` in place. `x` is [heads, n, dim] contiguous; `rows` and
// `cols` are the per-token grid coordinates (length n); the tables come
// from rope2d_tables with half = dim/2.
@ rope2d_apply * f x i heads i n i dim * i rows * i cols * f cos_t * f sin_t → v {
    ? | | | <= heads 0 <= n 0 <= dim 0 != % dim 2 0 { ^ v } {}
    : i half / dim 2
    : i quarter / half 2
    ? != % half 2 0 { ^ v } {}
    : ~ i h 0
    ~ < h heads {
        : ~ i t 0
        ~ < t n {
            : i base + * h * n dim * t dim
            // first half rotated by the ROW coordinate, second by the column
            : ~ i axis 0
            ~ < axis 2 {
                : i off + base * axis half
                : i pos ? == axis 0 . rows t . cols t
                : i tbl * pos half
                : ~ i j 0
                ~ < j quarter {
                    : f x1 . x + off j
                    : f x2 . x + off + j quarter
                    : f c1 . cos_t + tbl j
                    : f s1 . sin_t + tbl j
                    : f c2 . cos_t + tbl + j quarter
                    : f s2 . sin_t + tbl + j quarter
                    // rotate(x) = (−x2, x1)
                    = . x + off j - * x1 c1 * x2 s1
                    = . x + off + j quarter + * x2 c2 * x1 s2
                    = j + j 1
                }
                = axis + axis 1
            }
            = t + t 1
        }
        = h + h 1
    }
}
