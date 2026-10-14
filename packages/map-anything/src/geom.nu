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
@ gm_quat_to_mat f x f y f z f w ( Slice f ) r → v {
    : f n ( float_sqrt + + + * x x * y y * z z * w w )
    : f nn ? > n 0.0 n 1.0
    : f qx / x nn
    : f qy / y nn
    : f qz / z nn
    : f qw / w nn
    ( slice_put [f] r 0 - 1.0 * 2.0 + * qy qy * qz qz )
    ( slice_put [f] r 1 * 2.0 - * qx qy * qw qz )
    ( slice_put [f] r 2 * 2.0 + * qx qz * qw qy )
    ( slice_put [f] r 3 * 2.0 + * qx qy * qw qz )
    ( slice_put [f] r 4 - 1.0 * 2.0 + * qx qx * qz qz )
    ( slice_put [f] r 5 * 2.0 - * qy qz * qw qx )
    ( slice_put [f] r 6 * 2.0 - * qx qz * qw qy )
    ( slice_put [f] r 7 * 2.0 + * qy qz * qw qx )
    ( slice_put [f] r 8 - 1.0 * 2.0 + * qx qx * qy qy )
}

// World points for one view. `dirs` is [3, n] planar (the DPT head's
// layout), `depth` is [n], `pose` is the head's 7 floats
// [tx ty tz qx qy qz qw], `out` is [n, 3] interleaved — the layout the
// PLY writer wants. Also emits the z-depth (camera-frame z · scale)
// into `depthz`, which the edge mask needs.
@ gm_world_points ( Slice f ) dirs ( Slice f ) depth ( Slice f ) pose f scale i n ( Slice f ) out ( Slice f ) depthz → v {
    : ( Vec f ) r__v ( vec_zeroed [f] 9 )
    : ( Slice f ) r ( slice_from_vec [f] r__v )
    ( gm_quat_to_mat ( slice_at [f] pose 3 ) ( slice_at [f] pose 4 ) ( slice_at [f] pose 5 ) ( slice_at [f] pose 6 ) r )
    : f tx ( slice_at [f] pose 0 )
    : f ty ( slice_at [f] pose 1 )
    : f tz ( slice_at [f] pose 2 )
    : ~ i j 0
    ~ < j n {
        : f cx * ( slice_at [f] dirs j ) ( slice_at [f] depth j )
        : f cy * ( slice_at [f] dirs + n j ) ( slice_at [f] depth j )
        : f cz * ( slice_at [f] dirs + * 2 n j ) ( slice_at [f] depth j )
        ( slice_put [f] out * j 3 * scale + + + * ( slice_at [f] r 0 ) cx * ( slice_at [f] r 1 ) cy * ( slice_at [f] r 2 ) cz tx )
        ( slice_put [f] out + * j 3 1 * scale + + + * ( slice_at [f] r 3 ) cx * ( slice_at [f] r 4 ) cy * ( slice_at [f] r 5 ) cz ty )
        ( slice_put [f] out + * j 3 2 * scale + + + * ( slice_at [f] r 6 ) cx * ( slice_at [f] r 7 ) cy * ( slice_at [f] r 8 ) cz tz )
        ( slice_put [f] depthz j * scale cz )
        = j + j 1
    }
}

// sigmoid(x) > 0.5  ⇔  x > 0
@ gm_nonambig ( Slice f ) logits i n ( Slice u ) mask → v {
    : ~ i j 0
    ~ < j n {
        ( slice_put [u] mask j ? > ( slice_at [f] logits j ) 0.0 # u 1 # u 0 )
        = j + j 1
    }
}

// AND a "confidence above the pct-th percentile" test into `mask`.
// torch.quantile with linear interpolation, over ALL pixels (the
// reference quantiles the un-masked confidence map).
@ gm_conf_percentile ( Slice f ) conf i n f pct ( Slice u ) mask → v {
    ? <= n 0 { ^ v } {}
    : ( Vec f ) sorted ( vec_with_cap [f] n )
    : ~ i j 0
    ~ < j n { ( vec_push [f] sorted ( slice_at [f] conf j ) ) = j + j 1 }
    ( sort_by [f] sorted \ f a f b → i { ^ ? < a b -1 ? > a b 1 0 } )
    : f pos * / pct 100.0 # f - n 1
    : i lo # i ( float_floor pos )
    : i hi ? < + lo 1 n + lo 1 - n 1
    : f frac - pos # f lo
    : f vlo ?? ( vec_get [f] sorted lo ) { T v → v F → 0.0 }
    : f vhi ?? ( vec_get [f] sorted hi ) { T v → v F → 0.0 }
    : f thr + vlo * frac - vhi vlo
    = j 0
    ~ < j n {
        ? > ( slice_at [f] conf j ) thr {} { ( slice_put [u] mask j # u 0 ) }
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
@ __gm_pool3 ( Slice f ) v ( Slice u ) m i h i w i y i x → f {
    : ~ f best - 0.0 __GM_INF
    : ~ i dy -1
    ~ <= dy 1 {
        : ~ i dx -1
        ~ <= dx 1 {
            : i yy + y dy
            : i xx + x dx
            ? & & & >= yy 0 < yy h >= xx 0 < xx w {
                : i idx + * yy w xx
                ? != # i ( slice_at [u] m idx ) 0 {
                    ? > ( slice_at [f] v idx ) best { = best ( slice_at [f] v idx ) } {}
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
@ gm_edge_mask ( Slice f ) pts ( Slice f ) depthz i h i w ( Slice u ) mask → v {
    : i n * h w
    // ── depth edge: maxpool(d) + maxpool(−d), relative tol 0.03 ──
    : f rtol 0.03
    : ( Vec u ) dedge__v ( vec_zeroed [u] n )
    : ( Slice u ) dedge ( slice_from_vec [u] dedge__v )
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
                        ? != # i ( slice_at [u] mask i2 ) 0 {
                            ? < ( slice_at [f] depthz i2 ) mn { = mn ( slice_at [f] depthz i2 ) } {}
                        } {}
                    } {}
                    = dx + dx 1
                }
                = dy + dy 1
            }
            : f diff - mx mn
            ? & & > mx - 0.0 __GM_INF < mn __GM_INF > / diff ( slice_at [f] depthz idx ) rtol {
                ( slice_put [u] dedge idx # u 1 )
            } {}
            = x + x 1
        }
        = y + y 1
    }

    // ── normals from the point map (4 cross products per pixel) ──
    : f tol 0.0872664625997164787  // 5° in radians
    : ( Vec f ) nrm__v ( vec_zeroed [f] * 3 n )
    : ( Slice f ) nrm ( slice_from_vec [f] nrm__v )
    : ( Vec u ) nmask__v ( vec_zeroed [u] n )
    : ( Slice u ) nmask ( slice_from_vec [u] nmask__v )
    = y 0
    ~ < y h {
        : ~ i x 0
        ~ < x w {
            : i idx + * y w x
            ? != # i ( slice_at [u] mask idx ) 0 {
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
                    : b ok1 ? in1 != # i ( slice_at [u] mask + * y1 w x1 ) 0 F
                    : b ok2 ? in2 != # i ( slice_at [u] mask + * y2 w x2 ) 0 F
                    ? & ok1 ok2 {
                        : i i1 + * y1 w x1
                        : i i2 + * y2 w x2
                        : f ux - ( slice_at [f] pts * i1 3 ) ( slice_at [f] pts * idx 3 )
                        : f uy - ( slice_at [f] pts + * i1 3 1 ) ( slice_at [f] pts + * idx 3 1 )
                        : f uz - ( slice_at [f] pts + * i1 3 2 ) ( slice_at [f] pts + * idx 3 2 )
                        : f vx - ( slice_at [f] pts * i2 3 ) ( slice_at [f] pts * idx 3 )
                        : f vy - ( slice_at [f] pts + * i2 3 1 ) ( slice_at [f] pts + * idx 3 1 )
                        : f vz - ( slice_at [f] pts + * i2 3 2 ) ( slice_at [f] pts + * idx 3 2 )
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
                    ( slice_put [f] nrm * idx 3 / ax nn )
                    ( slice_put [f] nrm + * idx 3 1 / ay nn )
                    ( slice_put [f] nrm + * idx 3 2 / az nn )
                    ( slice_put [u] nmask idx # u 1 )
                } {}
            } {}
            = x + x 1
        }
        = y + y 1
    }

    // ── normals edge: max angle to any valid 3×3 neighbour, then a
    // second 3×3 max-pool, > 5° ──
    : ( Vec f ) ang__v ( vec_zeroed [f] n )
    : ( Slice f ) ang ( slice_from_vec [f] ang__v )
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
                    ? != # i ( slice_at [u] nmask i2 ) 0 {
                        : ~ f d + + * ( slice_at [f] nrm * idx 3 ) ( slice_at [f] nrm * i2 3 )
                        * ( slice_at [f] nrm + * idx 3 1 ) ( slice_at [f] nrm + * i2 3 1 )
                        * ( slice_at [f] nrm + * idx 3 2 ) ( slice_at [f] nrm + * i2 3 2 )
                        ? > d 1.0 { = d 1.0 } {}
                        ? < d -1.0 { = d -1.0 } {}
                        : f a ( __gm_acos d )
                        ? > a amax { = amax a } {}
                    } {}
                    = dx + dx 1
                }
                = dy + dy 1
            }
            ( slice_put [f] ang idx amax )
            = x + x 1
        }
        = y + y 1
    }
    // second max-pool (out-of-bounds ignored, as the nan-padding does)
    : ( Vec u ) nedge__v ( vec_zeroed [u] n )
    : ( Slice u ) nedge ( slice_from_vec [u] nedge__v )
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
                        : f a ( slice_at [f] ang + * yy w xx )
                        ? > a amax { = amax a } {}
                    } {}
                    = dx + dx 1
                }
                = dy + dy 1
            }
            ? > amax tol { ( slice_put [u] nedge idx # u 1 ) } {}
            = x + x 1
        }
        = y + y 1
    }

    // keep = !(depth_edge & normals_edge)
    : ~ i j 0
    ~ < j n {
        ? & != # i ( slice_at [u] dedge j ) 0 != # i ( slice_at [u] nedge j ) 0 { ( slice_put [u] mask j # u 0 ) } {}
        = j + j 1
    }
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
@ __gm_jacobi4 ( Slice f ) a ( Slice f ) evec → v {
    // V ← I
    : ( Vec f ) v__v ( vec_zeroed [f] 16 )
    : ( Slice f ) v ( slice_from_vec [f] v__v )
    : ~ i k 0
    ~ < k 4 { ( slice_put [f] v + * k 4 k 1.0 ) = k + k 1 }
    : ~ i sweep 0
    ~ < sweep 32 {
        : ~ f off 0.0
        : ~ i p 0
        ~ < p 4 {
            : ~ i q + p 1
            ~ < q 4 {
                = off + off ( float_abs ( slice_at [f] a + * p 4 q ) )
                = q + q 1
            }
            = p + p 1
        }
        ? < off 0.000000000001 { = sweep 32 } {
            = p 0
            ~ < p 4 {
                : ~ i q + p 1
                ~ < q 4 {
                    : f apq ( slice_at [f] a + * p 4 q )
                    ? > ( float_abs apq ) 0.0000000000001 {
                        : f app ( slice_at [f] a + * p 4 p )
                        : f aqq ( slice_at [f] a + * q 4 q )
                        : f theta / - aqq app * 2.0 apq
                        : ~ f t / 1.0 + ( float_abs theta ) ( float_sqrt + * theta theta 1.0 )
                        ? < theta 0.0 { = t - 0.0 t } {}
                        : f c / 1.0 ( float_sqrt + * t t 1.0 )
                        : f s * t c
                        // rotate rows/cols p,q of a
                        : ~ i r 0
                        ~ < r 4 {
                            : f arp ( slice_at [f] a + * r 4 p )
                            : f arq ( slice_at [f] a + * r 4 q )
                            ( slice_put [f] a + * r 4 p - * c arp * s arq )
                            ( slice_put [f] a + * r 4 q + * s arp * c arq )
                            = r + r 1
                        }
                        = r 0
                        ~ < r 4 {
                            : f apr ( slice_at [f] a + * p 4 r )
                            : f aqr ( slice_at [f] a + * q 4 r )
                            ( slice_put [f] a + * p 4 r - * c apr * s aqr )
                            ( slice_put [f] a + * q 4 r + * s apr * c aqr )
                            = r + r 1
                        }
                        = r 0
                        ~ < r 4 {
                            : f vrp ( slice_at [f] v + * r 4 p )
                            : f vrq ( slice_at [f] v + * r 4 q )
                            ( slice_put [f] v + * r 4 p - * c vrp * s vrq )
                            ( slice_put [f] v + * r 4 q + * s vrp * c vrq )
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
    : ~ f bv ( slice_at [f] a 0 )
    = k 1
    ~ < k 4 {
        ? > ( slice_at [f] a + * k 4 k ) bv { = bv ( slice_at [f] a + * k 4 k ) = best k } {}
        = k + k 1
    }
    = k 0
    ~ < k 4 { ( slice_put [f] evec k ( slice_at [f] v + * k 4 best ) ) = k + k 1 }
}

// Fit local→global: xs, ys are [n, 3] interleaved. Fails (F) below 3
// pairs or on a degenerate spread.
@ gm_sim3_fit ( Slice f ) xs ( Slice f ) ys i n ( Slice f ) out → b {
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
        = mx0 + mx0 ( slice_at [f] xs * j 3 )
        = mx1 + mx1 ( slice_at [f] xs + * j 3 1 )
        = mx2 + mx2 ( slice_at [f] xs + * j 3 2 )
        = my0 + my0 ( slice_at [f] ys * j 3 )
        = my1 + my1 ( slice_at [f] ys + * j 3 1 )
        = my2 + my2 ( slice_at [f] ys + * j 3 2 )
        = j + j 1
    }
    = mx0 / mx0 fn = mx1 / mx1 fn = mx2 / mx2 fn
    = my0 / my0 fn = my1 / my1 fn = my2 / my2 fn
    // correlation M = Σ yc xcᵀ (3×3) and var_x
    : ( Vec f ) m__v ( vec_zeroed [f] 9 )
    : ( Slice f ) m ( slice_from_vec [f] m__v )
    : ~ f varx 0.0
    = j 0
    ~ < j n {
        : f x0 - ( slice_at [f] xs * j 3 ) mx0
        : f x1 - ( slice_at [f] xs + * j 3 1 ) mx1
        : f x2 - ( slice_at [f] xs + * j 3 2 ) mx2
        : f y0 - ( slice_at [f] ys * j 3 ) my0
        : f y1 - ( slice_at [f] ys + * j 3 1 ) my1
        : f y2 - ( slice_at [f] ys + * j 3 2 ) my2
        = varx + varx + + * x0 x0 * x1 x1 * x2 x2
        ( slice_put [f] m 0 + ( slice_at [f] m 0 ) * y0 x0 )
        ( slice_put [f] m 1 + ( slice_at [f] m 1 ) * y0 x1 )
        ( slice_put [f] m 2 + ( slice_at [f] m 2 ) * y0 x2 )
        ( slice_put [f] m 3 + ( slice_at [f] m 3 ) * y1 x0 )
        ( slice_put [f] m 4 + ( slice_at [f] m 4 ) * y1 x1 )
        ( slice_put [f] m 5 + ( slice_at [f] m 5 ) * y1 x2 )
        ( slice_put [f] m 6 + ( slice_at [f] m 6 ) * y2 x0 )
        ( slice_put [f] m 7 + ( slice_at [f] m 7 ) * y2 x1 )
        ( slice_put [f] m 8 + ( slice_at [f] m 8 ) * y2 x2 )
        = j + j 1
    }
    ? < varx 0.000000000001 { ^ F } {}
    // Horn's N (4×4 symmetric), from M with x as "left" set:
    // q rotates x onto y: R(q)·xc ≈ yc
    : f sxx ( slice_at [f] m 0 )
    : f sxy ( slice_at [f] m 3 )
    : f sxz ( slice_at [f] m 6 )
    : f syx ( slice_at [f] m 1 )
    : f syy ( slice_at [f] m 4 )
    : f syz ( slice_at [f] m 7 )
    : f szx ( slice_at [f] m 2 )
    : f szy ( slice_at [f] m 5 )
    : f szz ( slice_at [f] m 8 )
    // NOTE the index convention: m holds Σ yc xcᵀ, so m[r][c] = Σ y_r x_c;
    // Horn's S_ab = Σ x_a y_b = m[b][a] — the reads above already swap.
    : ( Vec f ) nmat__v ( vec_zeroed [f] 16 )
    : ( Slice f ) nmat ( slice_from_vec [f] nmat__v )
    ( slice_put [f] nmat 0 + + sxx syy szz )
    ( slice_put [f] nmat 1 - syz szy )
    ( slice_put [f] nmat 2 - szx sxz )
    ( slice_put [f] nmat 3 - sxy syx )
    ( slice_put [f] nmat 4 ( slice_at [f] nmat 1 ) )
    ( slice_put [f] nmat 5 - - sxx syy szz )
    ( slice_put [f] nmat 6 + sxy syx )
    ( slice_put [f] nmat 7 + szx sxz )
    ( slice_put [f] nmat 8 ( slice_at [f] nmat 2 ) )
    ( slice_put [f] nmat 9 ( slice_at [f] nmat 6 ) )
    ( slice_put [f] nmat 10 - - syy sxx szz )
    ( slice_put [f] nmat 11 + syz szy )
    ( slice_put [f] nmat 12 ( slice_at [f] nmat 3 ) )
    ( slice_put [f] nmat 13 ( slice_at [f] nmat 7 ) )
    ( slice_put [f] nmat 14 ( slice_at [f] nmat 11 ) )
    ( slice_put [f] nmat 15 - - szz sxx syy )
    : ( Vec f ) q__v ( vec_zeroed [f] 4 )
    : ( Slice f ) q ( slice_from_vec [f] q__v )
    ( __gm_jacobi4 nmat q )
    : f qw ( slice_at [f] q 0 )
    : f qx ( slice_at [f] q 1 )
    : f qy ( slice_at [f] q 2 )
    : f qz ( slice_at [f] q 3 )
    // R from the unit quaternion (w, x, y, z)
    : ( Vec f ) r__v ( vec_zeroed [f] 9 )
    : ( Slice f ) r ( slice_from_vec [f] r__v )
    ( gm_quat_to_mat qx qy qz qw r )
    // s = Σ yc·(R xc) / var_x — recompute with R in hand
    : ~ f num 0.0
    = j 0
    ~ < j n {
        : f x0 - ( slice_at [f] xs * j 3 ) mx0
        : f x1 - ( slice_at [f] xs + * j 3 1 ) mx1
        : f x2 - ( slice_at [f] xs + * j 3 2 ) mx2
        : f y0 - ( slice_at [f] ys * j 3 ) my0
        : f y1 - ( slice_at [f] ys + * j 3 1 ) my1
        : f y2 - ( slice_at [f] ys + * j 3 2 ) my2
        : f rx0 + + * ( slice_at [f] r 0 ) x0 * ( slice_at [f] r 1 ) x1 * ( slice_at [f] r 2 ) x2
        : f rx1 + + * ( slice_at [f] r 3 ) x0 * ( slice_at [f] r 4 ) x1 * ( slice_at [f] r 5 ) x2
        : f rx2 + + * ( slice_at [f] r 6 ) x0 * ( slice_at [f] r 7 ) x1 * ( slice_at [f] r 8 ) x2
        = num + num + + * y0 rx0 * y1 rx1 * y2 rx2
        = j + j 1
    }
    : f s / num varx
    ? <= s 0.0 {
        ^ F
    } {}
    ( slice_put [f] out 0 s )
    = j 0
    ~ < j 9 { ( slice_put [f] out + 1 j ( slice_at [f] r j ) ) = j + j 1 }
    ( slice_put [f] out 10 - my0 * s + + * ( slice_at [f] r 0 ) mx0 * ( slice_at [f] r 1 ) mx1 * ( slice_at [f] r 2 ) mx2 )
    ( slice_put [f] out 11 - my1 * s + + * ( slice_at [f] r 3 ) mx0 * ( slice_at [f] r 4 ) mx1 * ( slice_at [f] r 5 ) mx2 )
    ( slice_put [f] out 12 - my2 * s + + * ( slice_at [f] r 6 ) mx0 * ( slice_at [f] r 7 ) mx1 * ( slice_at [f] r 8 ) mx2 )
    ^ T
}

// p ← s·R·p + t, in place over [n, 3] interleaved points.
@ gm_sim3_apply ( Slice f ) pts i n ( Slice f ) xf → v {
    : f s ( slice_at [f] xf 0 )
    : ~ i j 0
    ~ < j n {
        : f x ( slice_at [f] pts * j 3 )
        : f y ( slice_at [f] pts + * j 3 1 )
        : f z ( slice_at [f] pts + * j 3 2 )
        ( slice_put [f] pts * j 3 + * s + + * ( slice_at [f] xf 1 ) x * ( slice_at [f] xf 2 ) y * ( slice_at [f] xf 3 ) z ( slice_at [f] xf 10 ) )
        ( slice_put [f] pts + * j 3 1 + * s + + * ( slice_at [f] xf 4 ) x * ( slice_at [f] xf 5 ) y * ( slice_at [f] xf 6 ) z ( slice_at [f] xf 11 ) )
        ( slice_put [f] pts + * j 3 2 + * s + + * ( slice_at [f] xf 7 ) x * ( slice_at [f] xf 8 ) y * ( slice_at [f] xf 9 ) z ( slice_at [f] xf 12 ) )
        = j + j 1
    }
}
