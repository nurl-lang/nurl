// packages/map-anything/src/geom.nu — output geometry and masks, host
// f64.
//
// The model's scene representation is raydirs+depth+pose: per pixel a
// unit ray direction and a depth along it, per view a cam2world pose as
// translation + unit quaternion in (x, y, z, w) — SCALAR-LAST, the
// reference's own convention — and one global metric scale. World
// points are
//
//     p_world = scale · (R(q) · (dir · depth) + t)
//
// (OpenCV axes: +x right, +y down, +z forward; view 0 is the world
// frame, so its pose is near-identity but still predicted.)
//
// The masks reproduce inference.py's postprocessing exactly:
//   * non-ambiguous: sigmoid(logit) > 0.5, i.e. logit > 0
//   * optional confidence percentile (the reference's
//     apply_confidence_mask, default off)
//   * edge mask: a pixel is dropped when BOTH the depth-edge test
//     (3×3 max-pool difference, relative tol 0.03 on z-depth) AND the
//     normals-edge test (3×3 angle spread over 5°, computed from the
//     world points, then max-pooled) flag it — flying pixels at depth
//     discontinuities, killed the way MoGe kills them.
//
//   ( gm_quat_to_mat qx qy qz qw R )            → v    R: *f, 9
//   ( gm_world_points dirs depth pose scale n out ) → v
//   ( gm_nonambig logits n mask )               → v    mask: *u8 0/1
//   ( gm_conf_percentile conf n pct mask )      → v    AND into mask
//   ( gm_edge_mask pts depthz h w mask )        → v    AND into mask

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/sort.nu`

// (x, y, z, w) → row-major 3×3, the reference's quaternion_to_rotation_matrix.
@ gm_quat_to_mat f x f y f z f w * f r → v {
    : f n ( float_sqrt + + + * x x * y y * z z * w w )
    : f nn ? > n 0.0 n 1.0
    : f qx / x nn
    : f qy / y nn
    : f qz / z nn
    : f qw / w nn
    = . r 0 - 1.0 * 2.0 + * qy qy * qz qz
    = . r 1 * 2.0 - * qx qy * qw qz
    = . r 2 * 2.0 + * qx qz * qw qy
    = . r 3 * 2.0 + * qx qy * qw qz
    = . r 4 - 1.0 * 2.0 + * qx qx * qz qz
    = . r 5 * 2.0 - * qy qz * qw qx
    = . r 6 * 2.0 - * qx qz * qw qy
    = . r 7 * 2.0 + * qy qz * qw qx
    = . r 8 - 1.0 * 2.0 + * qx qx * qy qy
}

// World points for one view. `dirs` is [3, n] planar (the DPT head's
// layout), `depth` is [n], `pose` is the head's 7 floats
// [tx ty tz qx qy qz qw], `out` is [n, 3] interleaved — the layout the
// PLY writer wants. Also emits the z-depth (camera-frame z · scale)
// into `depthz`, which the edge mask needs.
@ gm_world_points * f dirs * f depth * f pose f scale i n * f out * f depthz → v {
    : *f r # *f ( nurl_zalloc 72 )
    ( gm_quat_to_mat . pose 3 . pose 4 . pose 5 . pose 6 r )
    : f tx . pose 0
    : f ty . pose 1
    : f tz . pose 2
    : ~ i j 0
    ~ < j n {
        : f cx * . dirs j . depth j
        : f cy * . dirs + n j . depth j
        : f cz * . dirs + * 2 n j . depth j
        = . out * j 3 * scale + + + * . r 0 cx * . r 1 cy * . r 2 cz tx
        = . out + * j 3 1 * scale + + + * . r 3 cx * . r 4 cy * . r 5 cz ty
        = . out + * j 3 2 * scale + + + * . r 6 cx * . r 7 cy * . r 8 cz tz
        = . depthz j * scale cz
        = j + j 1
    }
    ( nurl_free # s r )
}

// sigmoid(x) > 0.5  ⇔  x > 0
@ gm_nonambig * f logits i n * u mask → v {
    : ~ i j 0
    ~ < j n {
        = . mask j ? > . logits j 0.0 # u 1 # u 0
        = j + j 1
    }
}

// AND a "confidence above the pct-th percentile" test into `mask`.
// torch.quantile with linear interpolation, over ALL pixels (the
// reference quantiles the un-masked confidence map).
@ gm_conf_percentile * f conf i n f pct * u mask → v {
    ? <= n 0 { ^ v } {}
    : ( Vec f ) sorted ( vec_with_cap [f] n )
    : ~ i j 0
    ~ < j n { ( vec_push [f] sorted . conf j ) = j + j 1 }
    ( sort_by [f] sorted \ f a f b → i { ^ ? < a b -1 ? > a b 1 0 } )
    : f pos * / pct 100.0 # f - n 1
    : i lo # i ( float_floor pos )
    : i hi ? < + lo 1 n + lo 1 - n 1
    : f frac - pos # f lo
    : f vlo ?? ( vec_get [f] sorted lo ) { T v → v F → 0.0 }
    : f vhi ?? ( vec_get [f] sorted hi ) { T v → v F → 0.0 }
    : f thr + vlo * frac - vhi vlo
    ( vec_free [f] sorted )
    = j 0
    ~ < j n {
        ? > . conf j thr {} { = . mask j # u 0 }
        = j + j 1
    }
}

: f __GM_INF 1000000000000000000000000000000.0  // inf sentinel; real depths are ~1e0..1e4

// stdlib has no acos; atan2(√(1−d²), d) is exact over [−1, 1].
@ __gm_acos f d → f {
    : ~ f s - 1.0 * d d
    ? < s 0.0 { = s 0.0 } {}
    ^ ( float_atan2 ( float_sqrt s ) d )
}

// 3×3 max of `v` masked by `m` (invalid → −inf), −inf outside.
@ __gm_pool3 * f v * u m i h i w i y i x → f {
    : ~ f best - 0.0 __GM_INF
    : ~ i dy -1
    ~ <= dy 1 {
        : ~ i dx -1
        ~ <= dx 1 {
            : i yy + y dy
            : i xx + x dx
            ? & & & >= yy 0 < yy h >= xx 0 < xx w {
                : i idx + * yy w xx
                ? != # i . m idx 0 {
                    ? > . v idx best { = best . v idx } {}
                } {}
            } {}
            = dx + dx 1
        }
        = dy + dy 1
    }
    ^ best
}

// The reference's edge mask: drop pixels where the depth-edge AND the
// normals-edge tests both fire. `pts` is [n, 3] world points (already
// masked-invalid entries are excluded via `mask`), `depthz` [n], and
// `mask` is updated in place.
@ gm_edge_mask * f pts * f depthz i h i w * u mask → v {
    : i n * h w
    // ── depth edge: maxpool(d) + maxpool(−d), relative tol 0.03 ──
    : f rtol 0.03
    : *u dedge # *u ( nurl_zalloc n )
    : ~ i y 0
    ~ < y h {
        : ~ i x 0
        ~ < x w {
            : i idx + * y w x
            : f mx ( __gm_pool3 depthz mask h w y x )
            // max of −d without a second buffer: min of d, negated
            : ~ f mn __GM_INF
            : ~ i dy -1
            ~ <= dy 1 {
                : ~ i dx -1
                ~ <= dx 1 {
                    : i yy + y dy
                    : i xx + x dx
                    ? & & & >= yy 0 < yy h >= xx 0 < xx w {
                        : i i2 + * yy w xx
                        ? != # i . mask i2 0 {
                            ? < . depthz i2 mn { = mn . depthz i2 } {}
                        } {}
                    } {}
                    = dx + dx 1
                }
                = dy + dy 1
            }
            : f diff - mx mn
            ? & & > mx - 0.0 __GM_INF < mn __GM_INF > / diff . depthz idx rtol {
                = . dedge idx # u 1
            } {}
            = x + x 1
        }
        = y + y 1
    }

    // ── normals from the point map (4 cross products per pixel) ──
    : f tol 0.0872664625997164787  // 5° in radians
    : *f nrm # *f ( nurl_zalloc * 24 n )
    : *u nmask # *u ( nurl_zalloc n )
    = y 0
    ~ < y h {
        : ~ i x 0
        ~ < x w {
            : i idx + * y w x
            ? != # i . mask idx 0 {
                : ~ f ax 0.0
                : ~ f ay 0.0
                : ~ f az 0.0
                : ~ b any F
                // the four (edge-pair, cross-order) combinations:
                // up×left, left×down, down×right, right×up
                : ~ i k 0
                ~ < k 4 {
                    : i d1y ? == k 0 -1 ? == k 1 0 ? == k 2 1 0
                    : i d1x ? == k 0 0 ? == k 1 -1 ? == k 2 0 1
                    : i d2y ? == k 0 0 ? == k 1 1 ? == k 2 0 -1
                    : i d2x ? == k 0 -1 ? == k 1 0 ? == k 2 1 0
                    : i y1 + y d1y
                    : i x1 + x d1x
                    : i y2 + y d2y
                    : i x2 + x d2x
                    : b in1 & & & >= y1 0 < y1 h >= x1 0 < x1 w
                    : b in2 & & & >= y2 0 < y2 h >= x2 0 < x2 w
                    : b ok1 ? in1 != # i . mask + * y1 w x1 0 F
                    : b ok2 ? in2 != # i . mask + * y2 w x2 0 F
                    ? & ok1 ok2 {
                        : i i1 + * y1 w x1
                        : i i2 + * y2 w x2
                        : f ux - . pts * i1 3 . pts * idx 3
                        : f uy - . pts + * i1 3 1 . pts + * idx 3 1
                        : f uz - . pts + * i1 3 2 . pts + * idx 3 2
                        : f vx - . pts * i2 3 . pts * idx 3
                        : f vy - . pts + * i2 3 1 . pts + * idx 3 1
                        : f vz - . pts + * i2 3 2 . pts + * idx 3 2
                        : f cx - * uy vz * uz vy
                        : f cy - * uz vx * ux vz
                        : f cz - * ux vy * uy vx
                        : f cn + ( float_sqrt + + * cx cx * cy cy * cz cz ) 0.000000000001
                        = ax + ax / cx cn
                        = ay + ay / cy cn
                        = az + az / cz cn
                        = any T
                    } {}
                    = k + k 1
                }
                ? any {
                    : f nn + ( float_sqrt + + * ax ax * ay ay * az az ) 0.000000000001
                    = . nrm * idx 3 / ax nn
                    = . nrm + * idx 3 1 / ay nn
                    = . nrm + * idx 3 2 / az nn
                    = . nmask idx # u 1
                } {}
            } {}
            = x + x 1
        }
        = y + y 1
    }

    // ── normals edge: max angle to any valid 3×3 neighbour, then a
    // second 3×3 max-pool, > 5° ──
    : *f ang # *f ( nurl_zalloc * 8 n )
    = y 0
    ~ < y h {
        : ~ i x 0
        ~ < x w {
            : i idx + * y w x
            : ~ f amax 0.0
            : ~ i dy -1
            ~ <= dy 1 {
                : ~ i dx -1
                ~ <= dx 1 {
                    // edge-replicated padding, as np.pad(mode="edge")
                    : ~ i yy + y dy
                    : ~ i xx + x dx
                    ? < yy 0 { = yy 0 } {}
                    ? >= yy h { = yy - h 1 } {}
                    ? < xx 0 { = xx 0 } {}
                    ? >= xx w { = xx - w 1 } {}
                    : i i2 + * yy w xx
                    ? != # i . nmask i2 0 {
                        : ~ f d + + * . nrm * idx 3 . nrm * i2 3
                        * . nrm + * idx 3 1 . nrm + * i2 3 1
                        * . nrm + * idx 3 2 . nrm + * i2 3 2
                        ? > d 1.0 { = d 1.0 } {}
                        ? < d -1.0 { = d -1.0 } {}
                        : f a ( __gm_acos d )
                        ? > a amax { = amax a } {}
                    } {}
                    = dx + dx 1
                }
                = dy + dy 1
            }
            = . ang idx amax
            = x + x 1
        }
        = y + y 1
    }
    // second max-pool (out-of-bounds ignored, as the nan-padding does)
    : *u nedge # *u ( nurl_zalloc n )
    = y 0
    ~ < y h {
        : ~ i x 0
        ~ < x w {
            : i idx + * y w x
            : ~ f amax - 0.0 __GM_INF
            : ~ i dy -1
            ~ <= dy 1 {
                : ~ i dx -1
                ~ <= dx 1 {
                    : i yy + y dy
                    : i xx + x dx
                    ? & & & >= yy 0 < yy h >= xx 0 < xx w {
                        : f a . ang + * yy w xx
                        ? > a amax { = amax a } {}
                    } {}
                    = dx + dx 1
                }
                = dy + dy 1
            }
            ? > amax tol { = . nedge idx # u 1 } {}
            = x + x 1
        }
        = y + y 1
    }

    // keep = !(depth_edge & normals_edge)
    : ~ i j 0
    ~ < j n {
        ? & != # i . dedge j 0 != # i . nedge j 0 { = . mask j # u 0 } {}
        = j + j 1
    }
    ( nurl_free # s dedge )
    ( nurl_free # s nrm )
    ( nurl_free # s nmask )
    ( nurl_free # s ang )
    ( nurl_free # s nedge )
}

// ── Sim(3) alignment (windowed long-capture mode) ───────────────────
//
// Two overlapping windows reconstruct the SAME frames, pixel for pixel,
// so the correspondence problem is already solved: pixel j of an
// overlap view has a point in the previous window's (global) frame and
// one in the new window's (local) frame. The similarity that maps local
// onto global is closed-form: Horn's quaternion method for the
// rotation (the largest eigenvector of the 4×4 correlation form, found
// by cyclic Jacobi — always a proper rotation, no reflection case),
// then s = Σ(yc·Rxc)/Σ‖xc‖² and t = μy − sRμx.
//
//   ( gm_sim3_fit xs ys n out )   → b    out: [s | R row-major 9 | t 3]
//   ( gm_sim3_apply pts n out13 ) → v    in place

// Largest-eigenvalue eigenvector of a symmetric 4×4 by cyclic Jacobi.
@ __gm_jacobi4 * f a * f evec → v {
    // V ← I
    : *f v # *f ( nurl_zalloc 128 )
    : ~ i k 0
    ~ < k 4 { = . v + * k 4 k 1.0 = k + k 1 }
    : ~ i sweep 0
    ~ < sweep 32 {
        : ~ f off 0.0
        : ~ i p 0
        ~ < p 4 {
            : ~ i q + p 1
            ~ < q 4 {
                = off + off ( float_abs . a + * p 4 q )
                = q + q 1
            }
            = p + p 1
        }
        ? < off 0.000000000001 { = sweep 32 } {
            = p 0
            ~ < p 4 {
                : ~ i q + p 1
                ~ < q 4 {
                    : f apq . a + * p 4 q
                    ? > ( float_abs apq ) 0.0000000000001 {
                        : f app . a + * p 4 p
                        : f aqq . a + * q 4 q
                        : f theta / - aqq app * 2.0 apq
                        : ~ f t / 1.0 + ( float_abs theta ) ( float_sqrt + * theta theta 1.0 )
                        ? < theta 0.0 { = t - 0.0 t } {}
                        : f c / 1.0 ( float_sqrt + * t t 1.0 )
                        : f s * t c
                        // rotate rows/cols p,q of a
                        : ~ i r 0
                        ~ < r 4 {
                            : f arp . a + * r 4 p
                            : f arq . a + * r 4 q
                            = . a + * r 4 p - * c arp * s arq
                            = . a + * r 4 q + * s arp * c arq
                            = r + r 1
                        }
                        = r 0
                        ~ < r 4 {
                            : f apr . a + * p 4 r
                            : f aqr . a + * q 4 r
                            = . a + * p 4 r - * c apr * s aqr
                            = . a + * q 4 r + * s apr * c aqr
                            = r + r 1
                        }
                        = r 0
                        ~ < r 4 {
                            : f vrp . v + * r 4 p
                            : f vrq . v + * r 4 q
                            = . v + * r 4 p - * c vrp * s vrq
                            = . v + * r 4 q + * s vrp * c vrq
                            = r + r 1
                        }
                    } {}
                    = q + q 1
                }
                = p + p 1
            }
            = sweep + sweep 1
        }
    }
    // pick the column with the largest diagonal eigenvalue
    : ~ i best 0
    : ~ f bv . a 0
    = k 1
    ~ < k 4 {
        ? > . a + * k 4 k bv { = bv . a + * k 4 k = best k } {}
        = k + k 1
    }
    = k 0
    ~ < k 4 { = . evec k . v + * k 4 best = k + k 1 }
    ( nurl_free # s v )
}

// Fit local→global: xs, ys are [n, 3] interleaved. Fails (F) below 3
// pairs or on a degenerate spread.
@ gm_sim3_fit * f xs * f ys i n * f out → b {
    ? < n 3 { ^ F } {}
    : f fn # f n
    : ~ f mx0 0.0
    : ~ f mx1 0.0
    : ~ f mx2 0.0
    : ~ f my0 0.0
    : ~ f my1 0.0
    : ~ f my2 0.0
    : ~ i j 0
    ~ < j n {
        = mx0 + mx0 . xs * j 3
        = mx1 + mx1 . xs + * j 3 1
        = mx2 + mx2 . xs + * j 3 2
        = my0 + my0 . ys * j 3
        = my1 + my1 . ys + * j 3 1
        = my2 + my2 . ys + * j 3 2
        = j + j 1
    }
    = mx0 / mx0 fn = mx1 / mx1 fn = mx2 / mx2 fn
    = my0 / my0 fn = my1 / my1 fn = my2 / my2 fn
    // correlation M = Σ yc xcᵀ (3×3) and var_x
    : *f m # *f ( nurl_zalloc 72 )
    : ~ f varx 0.0
    = j 0
    ~ < j n {
        : f x0 - . xs * j 3 mx0
        : f x1 - . xs + * j 3 1 mx1
        : f x2 - . xs + * j 3 2 mx2
        : f y0 - . ys * j 3 my0
        : f y1 - . ys + * j 3 1 my1
        : f y2 - . ys + * j 3 2 my2
        = varx + varx + + * x0 x0 * x1 x1 * x2 x2
        = . m 0 + . m 0 * y0 x0
        = . m 1 + . m 1 * y0 x1
        = . m 2 + . m 2 * y0 x2
        = . m 3 + . m 3 * y1 x0
        = . m 4 + . m 4 * y1 x1
        = . m 5 + . m 5 * y1 x2
        = . m 6 + . m 6 * y2 x0
        = . m 7 + . m 7 * y2 x1
        = . m 8 + . m 8 * y2 x2
        = j + j 1
    }
    ? < varx 0.000000000001 { ( nurl_free # s m ) ^ F } {}
    // Horn's N (4×4 symmetric), from M with x as "left" set:
    // q rotates x onto y: R(q)·xc ≈ yc
    : f sxx . m 0
    : f sxy . m 3
    : f sxz . m 6
    : f syx . m 1
    : f syy . m 4
    : f syz . m 7
    : f szx . m 2
    : f szy . m 5
    : f szz . m 8
    // NOTE the index convention: m holds Σ yc xcᵀ, so m[r][c] = Σ y_r x_c;
    // Horn's S_ab = Σ x_a y_b = m[b][a] — the reads above already swap.
    : *f nmat # *f ( nurl_zalloc 128 )
    = . nmat 0 + + sxx syy szz
    = . nmat 1 - syz szy
    = . nmat 2 - szx sxz
    = . nmat 3 - sxy syx
    = . nmat 4 . nmat 1
    = . nmat 5 - - sxx syy szz
    = . nmat 6 + sxy syx
    = . nmat 7 + szx sxz
    = . nmat 8 . nmat 2
    = . nmat 9 . nmat 6
    = . nmat 10 - - syy sxx szz
    = . nmat 11 + syz szy
    = . nmat 12 . nmat 3
    = . nmat 13 . nmat 7
    = . nmat 14 . nmat 11
    = . nmat 15 - - szz sxx syy
    : *f q # *f ( nurl_zalloc 32 )
    ( __gm_jacobi4 nmat q )
    : f qw . q 0
    : f qx . q 1
    : f qy . q 2
    : f qz . q 3
    // R from the unit quaternion (w, x, y, z)
    : *f r # *f ( nurl_zalloc 72 )
    ( gm_quat_to_mat qx qy qz qw r )
    // s = Σ yc·(R xc) / var_x — recompute with R in hand
    : ~ f num 0.0
    = j 0
    ~ < j n {
        : f x0 - . xs * j 3 mx0
        : f x1 - . xs + * j 3 1 mx1
        : f x2 - . xs + * j 3 2 mx2
        : f y0 - . ys * j 3 my0
        : f y1 - . ys + * j 3 1 my1
        : f y2 - . ys + * j 3 2 my2
        : f rx0 + + * . r 0 x0 * . r 1 x1 * . r 2 x2
        : f rx1 + + * . r 3 x0 * . r 4 x1 * . r 5 x2
        : f rx2 + + * . r 6 x0 * . r 7 x1 * . r 8 x2
        = num + num + + * y0 rx0 * y1 rx1 * y2 rx2
        = j + j 1
    }
    : f s / num varx
    ? <= s 0.0 {
        ( nurl_free # s m ) ( nurl_free # s nmat ) ( nurl_free # s q ) ( nurl_free # s r )
        ^ F
    } {}
    = . out 0 s
    = j 0
    ~ < j 9 { = . out + 1 j . r j = j + j 1 }
    = . out 10 - my0 * s + + * . r 0 mx0 * . r 1 mx1 * . r 2 mx2
    = . out 11 - my1 * s + + * . r 3 mx0 * . r 4 mx1 * . r 5 mx2
    = . out 12 - my2 * s + + * . r 6 mx0 * . r 7 mx1 * . r 8 mx2
    ( nurl_free # s m ) ( nurl_free # s nmat ) ( nurl_free # s q ) ( nurl_free # s r )
    ^ T
}

// p ← s·R·p + t, in place over [n, 3] interleaved points.
@ gm_sim3_apply * f pts i n * f xf → v {
    : f s . xf 0
    : ~ i j 0
    ~ < j n {
        : f x . pts * j 3
        : f y . pts + * j 3 1
        : f z . pts + * j 3 2
        = . pts * j 3 + * s + + * . xf 1 x * . xf 2 y * . xf 3 z . xf 10
        = . pts + * j 3 1 + * s + + * . xf 4 x * . xf 5 y * . xf 6 z . xf 11
        = . pts + * j 3 2 + * s + + * . xf 7 x * . xf 8 y * . xf 9 z . xf 12
        = j + j 1
    }
}
