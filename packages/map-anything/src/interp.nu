// packages/map-anything/src/interp.nu — torch's upsample_bicubic2d,
// WITHOUT antialias, which is what DINOv2's interpolate_pos_encoding
// calls for the torch-hub models (interpolate_antialias=False,
// interpolate_offset=0.1).
//
// This is a DIFFERENT kernel from both of the other two bicubics in this
// codebase, and mixing them up is a silent-wrongness trap:
//
//   * Pillow / image package:      a = −0.5, support scaled when
//                                  shrinking (antialiased)
//   * torch _upsample_bicubic2d_aa a = −0.5 antialiased (what
//     (lingbot-map's interp.nu):   lingbot-map's pos_embed wants)
//   * THIS:                        a = −0.75, four fixed taps, never
//                                  antialiased, torch's plain
//                                  `interpolate(mode="bicubic")`
//
// The historical-kludge offset matters too: DINOv2 passes
// scale_factor=(gh+0.1)/37 rather than an output size, and torch then
// maps output row o to source coordinate (o+0.5)/scale_factor − 0.5 —
// with the +0.1 folded in, that is NOT the same grid as size-based
// interpolation. The caller passes the reciprocal (`rscale` =
// 37/(gh+0.1)) so this file has no opinion about where the scale came
// from.
//
//   ( interp_bicubic_torch pin ih iw c oh ow rsy rsx pout ) → v
//     pin  planar [c, ih, iw] f64, pout planar [c, oh, ow] f64
//     src_y = rsy·(oy+0.5) − 0.5, src_x likewise; taps edge-clamped.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`

// torch's upsample_get_cubic_coefficients, A = −0.75: t in [0,1), the
// four weights for taps at floor(src)−1 … floor(src)+2. Written as the
// two cubic_convolution polynomials, exactly.
@ __it_cc1 f t → f {
    // ((A+2)·t − (A+3))·t² + 1, A = −0.75
    ^ + * * - * 1.25 t 2.25 t t 1.0
}

@ __it_cc2 f t → f {
    // ((A·t − 5A)·t + 8A)·t − 4A, A = −0.75:
    // ((−0.75·t + 3.75)·t − 6)·t + 3
    : f a + * -0.75 t 3.75
    : f b - * a t 6.0
    ^ + * b t 3.0
}

// One axis's tap start and weights for output index o. Returns the
// clamped base index; writes the four weights into w[0..3].
@ __it_axis i o f rscale i insize * f w → i {
    : f src - * rscale + # f o 0.5 0.5
    : f fl ( float_floor src )
    : i i0 # i fl
    : f t - src fl
    = . w 0 ( __it_cc2 + t 1.0 )
    = . w 1 ( __it_cc1 t )
    = . w 2 ( __it_cc1 - 1.0 t )
    = . w 3 ( __it_cc2 - 2.0 t )
    ^ i0
}

@ __it_clamp i v i hi → i {
    ? < v 0 { ^ 0 } {}
    ? > v hi { ^ hi } {}
    ^ v
}

@ interp_bicubic_torch * f pin i ih i iw i c i oh i ow f rsy f rsx * f pout → v {
    ? | | | <= ih 0 <= iw 0 <= oh 0 <= ow 0 { ^ v } {}
    : *f wy # *f ( nurl_zalloc 32 )
    : *f wx # *f ( nurl_zalloc 32 )
    : ~ i oy 0
    ~ < oy oh {
        : i y0 ( __it_axis oy rsy ih wy )
        : ~ i ox 0
        ~ < ox ow {
            : i x0 ( __it_axis ox rsx iw wx )
            : ~ i k 0
            ~ < k c {
                : i plane * k * ih iw
                : ~ f acc 0.0
                : ~ i dy 0
                ~ < dy 4 {
                    : i sy ( __it_clamp + y0 - dy 1 - ih 1 )
                    : i rowb + plane * sy iw
                    : ~ f racc 0.0
                    : ~ i dx 0
                    ~ < dx 4 {
                        : i sx ( __it_clamp + x0 - dx 1 - iw 1 )
                        = racc + racc * . pin + rowb sx . wx dx
                        = dx + dx 1
                    }
                    = acc + acc * racc . wy dy
                    = dy + dy 1
                }
                = . pout + * k * oh ow + * oy ow ox acc
                = k + k 1
            }
            = ox + ox 1
        }
        = oy + oy 1
    }
    ( nurl_free # s wy )
    ( nurl_free # s wx )
}
