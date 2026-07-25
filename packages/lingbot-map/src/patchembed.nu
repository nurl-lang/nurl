// packages/lingbot-map/src/patchembed.nu — the model's entry point.
//
// DINOv2's patch embedding is `Conv2d(3, 1024, kernel=14, stride=14)`.
// Kernel and stride are equal, so the patches do not overlap and the
// convolution is exactly a matmul: lay each 14x14x3 patch out as one
// row of 588 values and multiply by the reshaped weight.
//
//     img [3, H, W]  ──im2col──▶  P x 588  ──▶  P x 1024  (+ bias)
//
// with P = (H/14) x (W/14) patches in ROW-MAJOR order, and 588 =
// 3 x 14 x 14 laid out channel-major then row then column — the order
// torch's Conv2d weight already has, so the weight is used as-is with
// no transposition beyond the one the matmul wants.
//
// im2col is written out rather than fused into the multiply because the
// multiply is the part that belongs on a device kernel later, and the
// layout is the part that has to be right first.
//
//   ( pe_patches h w patch )              → i    P
//   ( pe_im2col img c h w patch cols )    → v    P x (c·patch²)
//   ( pe_project cols p k weight bias out ) → v  P x k · k x n → P x n

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pe_grid_h i h i patch → i { ^ / h patch }

@ pe_grid_w i w i patch → i { ^ / w patch }

@ pe_patches i h i w i patch → i { ^ * / h patch / w patch }

// Planar image [c, h, w] → one row per patch, `c·patch·patch` wide.
// Row order is row-major over the patch grid; within a row the order is
// channel, then kernel row, then kernel column — Conv2d's weight layout.
@ pe_im2col * f img i c i h i w i patch * f cols → v {
    ? | | | <= c 0 <= patch 0 < h patch < w patch { ^ v } {}
    : i gh / h patch
    : i gw / w patch
    : i row_len * c * patch patch
    : ~ i py 0
    ~ < py gh {
        : ~ i px 0
        ~ < px gw {
            : i dst * + * py gw px row_len
            : ~ i ci 0
            ~ < ci c {
                : i plane * ci * h w
                : ~ i ky 0
                ~ < ky patch {
                    : i src + plane * + * py patch ky w
                    : i dbase + dst + * ci * patch patch * ky patch
                    : ~ i kx 0
                    ~ < kx patch {
                        = . cols + dbase kx . img + src + * px patch kx
                        = kx + kx 1
                    }
                    = ky + ky 1
                }
                = ci + ci 1
            }
            = px + px 1
        }
        = py + py 1
    }
}

// out[P, n] = cols[P, k] · weightᵀ[k, n] + bias[n].
//
// `weight` is torch's Conv2d weight flattened, [n, k] — output channel
// major — so this reads it along a row per output channel, which is a
// dot product against the patch row. Swapped for a device GEMM once the
// weights live on the device; the loop is the reference the GEMM has to
// agree with.
@ pe_project * f cols i p i k * f weight * f bias i n * f out → v {
    ? | | | <= p 0 <= k 0 <= n 0 == # i out 0 { ^ v } {}
    : ~ i r 0
    ~ < r p {
        : i crow * r k
        : ~ i o 0
        ~ < o n {
            : i wrow * o k
            : ~ f acc 0.0
            : ~ i j 0
            ~ < j k { = acc + acc * . cols + crow j . weight + wrow j = j + j 1 }
            = . out + * r n o + acc . bias o
            = o + o 1
        }
        = r + r 1
    }
}
