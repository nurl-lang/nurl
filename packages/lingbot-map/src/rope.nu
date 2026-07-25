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

// ── 3-D rotary position embedding (the global blocks) ───────────────
//
// The aggregator's GLOBAL blocks do not use the 2-D rope above. With
// `enable_3d_rope` — which is demo.py's default — they use
// `WanRotaryPosEmbed`, and it differs in three ways at once:
//
//   * three axes, not two: (frame, row, column), with the 64-dim head
//     split 20 / 22 / 22 rather than in half;
//   * theta 10000, not 100;
//   * the rotation pairs are INTERLEAVED — (x₀,x₁), (x₂,x₃), … — where
//     the 2-D rope splits each half at half/2. Same idea, incompatible
//     memory order, and nothing about a wrong choice looks wrong.
//
// A position is a triple, and the token layout fixes it:
//
//   special token j  → (f, j, j)                    j = 0 … 5
//   patch (py, px)   → (f, psi + py, psi + px)      psi = 6
//
// so the special tokens sit on the diagonal below the patch grid and
// never collide with it.
//
//   ( rope3d_tables maxpos cos sin )    → v   [maxpos, 32] each
//   ( rope3d_apply x heads n dim fr rw cl cos sin ) → v   in place

: f ROPE3_THETA 10000.0
: i R3_T 20  // head-dim slice for the frame axis
: i R3_H 22  // … for the row axis
: i R3_W 22  // … for the column axis

// Half-widths, i.e. how many complex frequencies each axis contributes.
@ rope3d_nt → i { ^ / R3_T 2 }

@ rope3d_nh → i { ^ / R3_H 2 }

@ rope3d_nw → i { ^ / R3_W 2 }

@ rope3d_width → i { ^ + ( rope3d_nt ) + ( rope3d_nh ) ( rope3d_nw ) }

// cos/sin for one axis, written into `out` at column `col0` of a row of
// `width` — the three axes share one table so a token's 32 frequencies
// are contiguous.
@ __r3_axis i dim i maxpos i col0 i width * f cos_t * f sin_t → v {
    : i half / dim 2
    : ~ i p 0
    ~ < p maxpos {
        : ~ i i0 0
        ~ < i0 half {
            : f expo / # f * 2 i0 # f dim
            : f inv / 1.0 ( float_pow ROPE3_THETA expo )
            : f ang * # f p inv
            = . cos_t + * p width + col0 i0 ( float_cos ang )
            = . sin_t + * p width + col0 i0 ( float_sin ang )
            = i0 + i0 1
        }
        = p + p 1
    }
}

// [maxpos, (t+h+w)/2] cos and sin, laid out t | h | w.
//
// The split is a parameter because this model uses TWO of them: the
// aggregator's global blocks have head_dim 64 and split 20/22/22, the
// camera head's trunk has head_dim 128 and splits 40/44/44. Same
// kernel, same theta, different geometry.
@ rope3d_tables_fhw i td i hd i wd i maxpos * f cos_t * f sin_t → v {
    : i width / + + td hd wd 2
    ( __r3_axis td maxpos 0 width cos_t sin_t )
    ( __r3_axis hd maxpos / td 2 width cos_t sin_t )
    : i woff + / td 2 / hd 2
    ( __r3_axis wd maxpos woff width cos_t sin_t )
}

// The aggregator's split: 20/22/22 over a 64-dim head.
@ rope3d_tables i maxpos * f cos_t * f sin_t → v {
    ( rope3d_tables_fhw R3_T R3_H R3_W maxpos cos_t sin_t )
}

// Rotate `x` [heads, n, dim] in place. `fr` / `rw` / `cl` hold each
// token's (frame, row, column) position. dim must be 2·width (64).
@ rope3d_apply_fhw * f x i heads i n i dim i nt i nh * i fr * i rw * i cl
* f cos_t * f sin_t → v {
    : i width / dim 2
    ? | <= heads 0 <= n 0 { ^ v } {}
    : ~ i h 0
    ~ < h heads {
        : ~ i t 0
        ~ < t n {
            : i base + * h * n dim * t dim
            : ~ i j 0
            ~ < j width {
                // which axis this frequency belongs to picks the position
                : i pos ? < j nt . fr t ? < j + nt nh . rw t . cl t
                : i tbl + * pos width j
                : f c . cos_t tbl
                : f s . sin_t tbl
                : f x1 . x + base * 2 j
                : f x2 . x + base + * 2 j 1
                = . x + base * 2 j - * x1 c * x2 s
                = . x + base + * 2 j 1 + * x1 s * x2 c
                = j + j 1
            }
            = t + t 1
        }
        = h + h 1
    }
}

@ rope3d_apply * f x i heads i n i dim * i fr * i rw * i cl * f cos_t * f sin_t → v {
    ( rope3d_apply_fhw x heads n dim ( rope3d_nt ) ( rope3d_nh ) fr rw cl cos_t sin_t )
}
