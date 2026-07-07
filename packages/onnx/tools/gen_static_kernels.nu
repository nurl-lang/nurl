// gen_static_kernels.nu — emit kernels_static.c: every CUDA-C kernel the
// onnx runtime uses, precompiled form for the gpu package's STATIC
// backend (backend 2 — no NVRTC, no host C++ compiler, no dlopen).
//
//   (from packages/onnx)  ../../nurl.sh tools/gen_static_kernels.nu gen
//   ./gen <out.c>
//
// Compile the output into any build:
//   native:  cc -O2 -c kernels_static.c && NURL_EXTRA_OBJS=kernels_static.o ./nurl.sh ...
//   wasm:    zig cc --target=wasm32-wasi -O2 -c kernels_static.c
// and select the backend with NURL_GPU=static or ( gpu_force_static ).
//
// The kernel list mirrors ops_compile in src/ops.nu — a new kernel there
// must be added here (the runtime fails loudly if one is missing:
// "[gpu/static] kernel not in the linked set").

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `deps/gpu/src/gpu.nu`
$ `src/ops.nu`

@ __add String out ( Vec String ) names s ename s src → v {
    : String unit ( cpu_static_unit ename src )
    ( string_push_str out ( string_data unit ) )
    ( string_free unit )
    ( vec_push [String] names ( string_from ename ) )
}

// conv2d dominates inference wall-clock, and the 1:1 CUDA translation
// (one grid "thread" per output element, kernel-tap inner loop) defeats
// both the vectorizer and the cache. This override computes whole
// output rows with a unit-stride ox inner loop — the shape -msimd128
// autovectorizes — reading the SAME param cells as the CUDA kernel, so
// the registry swap is invisible to the runtime. ~an order of magnitude
// on wasm and static-native builds.
@ __add_opt_conv String out ( Vec String ) names → v {
    ( string_push_str out `
static void __nurl_sl_conv2d(long long* p, long long grid, long long block) {
    (void)grid; (void)block;
    const float* X  = *(const float**)(uintptr_t)p[0];
    const float* Wt = *(const float**)(uintptr_t)p[1];
    const float* B  = *(const float**)(uintptr_t)p[2];
    float* Y        = *(float**)(uintptr_t)p[3];
    int Cin  = *(int*)(uintptr_t)p[4];
    int H    = *(int*)(uintptr_t)p[5];
    int W    = *(int*)(uintptr_t)p[6];
    int Cout = *(int*)(uintptr_t)p[7];
    int kh   = *(int*)(uintptr_t)p[8];
    int kw   = *(int*)(uintptr_t)p[9];
    int OH   = *(int*)(uintptr_t)p[10];
    int OW   = *(int*)(uintptr_t)p[11];
    int ph   = *(int*)(uintptr_t)p[12];
    int pw   = *(int*)(uintptr_t)p[13];
    int sh   = *(int*)(uintptr_t)p[14];
    int sw   = *(int*)(uintptr_t)p[15];
    int hasB = *(int*)(uintptr_t)p[16];
    for (int co = 0; co < Cout; co++) {
        float bias = hasB ? B[co] : 0.0f;
        for (int oy = 0; oy < OH; oy++) {
            float* yrow = Y + (co * OH + oy) * OW;
            for (int ox = 0; ox < OW; ox++) yrow[ox] = bias;
            for (int ci = 0; ci < Cin; ci++) {
                for (int ky = 0; ky < kh; ky++) {
                    int iy = oy * sh - ph + ky;
                    if (iy < 0 || iy >= H) continue;
                    const float* xrow = X + (ci * H + iy) * W;
                    const float* wrow = Wt + ((co * Cin + ci) * kh + ky) * kw;
                    for (int kx = 0; kx < kw; kx++) {
                        float wv = wrow[kx];
                        if (wv == 0.0f) continue;
                        int ix0 = kx - pw;
                        if (sw == 1) {
                            int lo = ix0 < 0 ? -ix0 : 0;
                            int hi = W - ix0; if (hi > OW) hi = OW;
                            const float* xr = xrow + ix0;
                            for (int ox = lo; ox < hi; ox++) yrow[ox] += wv * xr[ox];
                        } else {
                            for (int ox = 0; ox < OW; ox++) {
                                int ix = ox * sw + ix0;
                                if (ix >= 0 && ix < W) yrow[ox] += wv * xrow[ix];
                            }
                        }
                    }
                }
            }
        }
    }
}
` )
    ( vec_push [String] names ( string_from `conv2d` ) )
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 2 { ( nurl_print `usage: gen_static_kernels <out.c>\n` ) ^ 2 } {}
    : String op ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }

    : String out ( string_with_cap 65536 )
    ( string_push_str out ( cpu_static_header ) )
    : ( Vec String ) names ( vec_new [String] )

    ( __add out names `gemm` ( __k_gemm ) )
    ( __add out names `relu` ( __k_relu ) )
    ( __add_opt_conv out names )
    ( __add out names `maxpool2d` ( __k_pool ) )
    ( __add out names `batchnorm` ( __k_bn ) )
    ( __add out names `leakyrelu` ( __k_lrelu ) )
    ( __add out names `eltwise` ( __k_elt ) )
    ( __add out names `osigmoid` ( __k_sig ) )
    ( __add out names `resize_nn` ( __k_resize ) )
    ( __add out names `perm6` ( __k_perm ) )
    ( __add out names `softmax_ax` ( __k_softmax ) )
    ( __add out names `copy_ax` ( __k_cpyax ) )
    ( __add out names `reducel2` ( __k_rl2 ) )
    ( __add out names `clipk` ( __k_clip ) )
    ( __add out names `expandlast` ( __k_expand ) )
    ( __add out names `slice_ax` ( __k_slice ) )
    ( __add out names `layernorm` ( __k_lnorm ) )
    ( __add out names `erfk` ( __k_erf ) )
    ( __add out names `gather` ( __k_gather ) )
    ( __add out names `bmm` ( __k_bmm ) )
    ( __add out names `argmaxk` ( __k_amax ) )
    ( __add out names `argmaxk_i64` ( __k_amax_i64 ) )
    ( __add out names `eos_gather` ( __k_eosgather ) )
    ( __add out names `convtranspose2d` ( __k_convt ) )

    : String reg ( cpu_static_registry names )
    ( string_push_str out ( string_data reg ) )
    ( string_free reg )

    ?? ( write_file ( string_data op ) ( string_data out ) ) {
        T _ → {
            ( nurl_print `wrote ` ) ( nurl_print ( string_data op ) )
            ( nurl_print ` (` ) ( nurl_print ( nurl_str_int ( vec_len [String] names ) ) )
            ( nurl_print ` kernels)\n` )
            ^ 0
        }
        F _ → { ( nurl_print `write failed\n` ) ^ 1 }
    }
}
