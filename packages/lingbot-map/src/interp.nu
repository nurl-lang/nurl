// packages/lingbot-map/src/interp.nu — torch-compatible bicubic
// resampling of a float feature grid.
//
// DINOv2 ships one position embedding for a 37x37 patch grid, and a frame
// of 518x294 is 37x21 patches — so every forward pass begins by resampling
// `pos_embed` to the frame's grid. The reference does it with
//
//     F.interpolate(..., mode="bicubic", antialias=True, size=(h0, w0))
//
// and that is NOT the same resampler as the one preprocessing uses:
//
//                          kernel a   arithmetic
//   PIL (preprocessing)       −0.5     8-bit, fixed point, clamped
//   torch antialias=True       −0.5     float, unclamped   ← this file
//   torch antialias=False     −0.75     float, border-replicated
//
// The two −0.5 rows are the same kernel by design: torch's antialias
// path was written to reproduce PIL. The −0.75 row is torch's ORDINARY
// bicubic, which is what every reference to "torch bicubic" means and
// which must NOT be used here. Getting that wrong is a silent
// few-percent error everywhere, not a crash.
//
// This is torch's `_upsample_bicubic2d_aa` for the size-given,
// align_corners=false case: scale = in/out per axis, support = 2·scale
// when shrinking and 2 when growing, coefficients normalised over the
// clipped window, two separable passes.
//
//   ( interp_bicubic_aa src sw sh planes dw dh dst ) → v
//     src, dst: planar f64, `planes` planes of sw*sh / dw*dh

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`

// The cubic kernel torch's ANTIALIAS path uses — a = −0.5.
//
// Not −0.75. torch's two bicubic implementations disagree on the
// constant: the ordinary `mode="bicubic"` path uses a = −0.75 (the
// Keys/OpenCV value), and the `antialias=True` path uses a = −0.5,
// because it was written to reproduce PIL. Reading the value off the
// non-AA path — which is what the documentation and every tutorial
// show — gives a kernel that is wrong by a few percent everywhere and
// right nowhere, with no error to notice. Recovered here by probing
// torch with unit impulses and solving for `a`; it comes out −0.49997.
//
//   |t| < 1 :  (a+2)|t|³ − (a+3)|t|² + 1     =  1.5t³ − 2.5t² + 1
//   |t| < 2 :  a|t|³ − 5a|t|² + 8a|t| − 4a   = −0.5t³ + 2.5t² − 4t + 2
//
// Both are zero at t = 1 and t = 2 — worth checking by hand after any
// edit, because a mis-parenthesised Horner form still looks like a
// plausible bell curve and silently resamples everything slightly wrong.
@ __ip_cubic f x → f {
    : f t ? < x 0.0 - 0.0 x x
    ? < t 1.0 { ^ + * * t - * 1.5 t 2.5 t 1.0 } {}
    ? < t 2.0 { ^ + * - * - 2.5 * 0.5 t t 4.0 t 2.0 } {}
    ^ 0.0
}

// Coefficient window for one output position along one axis.
// Fills `wts` with the weights and returns the packed
// (xmin + 65536·count) so a caller gets both without a second call.
@ __ip_window i insize i outsize i idx * f wts → i {
    : f scale / # f insize # f outsize
    : f support ? >= scale 1.0 * 2.0 scale 2.0
    : f invscale ? >= scale 1.0 / 1.0 scale 1.0
    : f center * scale + # f idx 0.5
    : ~ i xmin # i + - center support 0.5
    ? < xmin 0 { = xmin 0 } {}
    : ~ i xmax # i + + center support 0.5
    ? > xmax insize { = xmax insize } {}
    : i cnt ? > - xmax xmin 0 - xmax xmin 0
    : ~ f total 0.0
    : ~ i j 0
    ~ < j cnt {
        : f w ( __ip_cubic * invscale - + # f + j xmin 0.5 center )
        = . wts j w
        = total + total w
        = j + j 1
    }
    ? != total 0.0 {
        = j 0
        ~ < j cnt { = . wts j / . wts j total = j + j 1 }
    } {}
    ^ + xmin * cnt 65536
}

// Worst-case window width for an axis — the coefficient buffer size.
@ __ip_ksize i insize i outsize → i {
    : f scale / # f insize # f outsize
    : f support ? >= scale 1.0 * 2.0 scale 2.0
    ^ + * 2 # i ( float_ceil support ) 2
}

// Resample `planes` planar grids from sw×sh to dw×dh.
//
// Separable, horizontal first, exactly as torch does it — resampling both
// axes at once would give different sums.
@ interp_bicubic_aa * f src i sw i sh i planes i dw i dh * f dst → v {
    ? | | | | <= sw 0 <= sh 0 <= dw 0 <= dh 0 <= planes 0 { ^ v } {}
    : i kx ( __ip_ksize sw dw )
    : i ky ( __ip_ksize sh dh )
    : *f wx ( nurl_zalloc * 8 kx )
    : *f wy ( nurl_zalloc * 8 ky )
    // horizontal: sw → dw, rows unchanged
    : *f mid ( nurl_zalloc * 8 * planes * dw sh )
    : ~ i ox 0
    ~ < ox dw {
        : i packed ( __ip_window sw dw ox wx )
        : i xmin % packed 65536
        : i cnt / packed 65536
        : ~ i p 0
        ~ < p planes {
            : i sbase * p * sw sh
            : i mbase * p * dw sh
            : ~ i y 0
            ~ < y sh {
                : ~ f acc 0.0
                : ~ i j 0
                ~ < j cnt {
                    = acc + acc * . src + + sbase * y sw + xmin j . wx j
                    = j + j 1
                }
                = . mid + mbase + * y dw ox acc
                = y + y 1
            }
            = p + p 1
        }
        = ox + ox 1
    }
    // vertical: sh → dh
    : ~ i oy 0
    ~ < oy dh {
        : i packed ( __ip_window sh dh oy wy )
        : i ymin % packed 65536
        : i cnt / packed 65536
        : ~ i p 0
        ~ < p planes {
            : i mbase * p * dw sh
            : i dbase * p * dw dh
            : ~ i x 0
            ~ < x dw {
                : ~ f acc 0.0
                : ~ i j 0
                ~ < j cnt {
                    = acc + acc * . mid + mbase + * + ymin j dw x . wy j
                    = j + j 1
                }
                = . dst + dbase + * oy dw x acc
                = x + x 1
            }
            = p + p 1
        }
        = oy + oy 1
    }
    ( nurl_free # s mid )
    ( nurl_free # s wx )
    ( nurl_free # s wy )
}
