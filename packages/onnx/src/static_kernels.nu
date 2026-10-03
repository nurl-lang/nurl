// packages/onnx/src/static_kernels.nu — kernels_static.c for the gpu
// package's STATIC backend (backend 2: precompiled kernels, no NVRTC, no
// host compiler, no dlopen — the backend of wasm32 and sealed native
// builds), derived from the executor.
//
// The kernel set is not listed anywhere. rt_kernel_census (runtime.nu)
// issues every gkd_* call the executor makes on a gpukit census kit,
// which records each kernel's entry name and exact source from gpukit's
// own builders, taking the branches the static backend takes; this file
// turns the record into C. A kernel the executor gains, or a kernel body
// gpukit changes, reaches the static set with no edit here. (Up to 0.9.0
// the generator mirrored a kernel list by hand, and when the executor
// moved onto gpukit the mirror kept importing a file that no longer
// existed: the static and wasm builds were broken for three releases.)
//
// tools/gen_static_kernels.nu is the command-line front end;
// tests/census_test.nu checks the census covers the executor.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `runtime.nu`

// ── Hand-optimised overrides ─────────────────────────────────────────
//
// conv2d dominates inference wall-clock. The static backend runs a CUDA
// kernel as a serial loop over (block, thread), and gpukit's conv2d
// thread owns a 4x4 tile with the kernel-tap loops inside it — a shape
// that keeps a GPU's registers busy but hands a CPU / -msimd128 vectoriser
// nothing unit-stride to work with. This override computes whole output
// rows with a unit-stride ox inner loop, the shape the autovectoriser
// wants. Each output still sums bias, then ic, ky, kx ascending — the
// order the CUDA kernel uses — so its output is bit-identical to the
// generic translation's: tinyyolov2 on the native static backend (cc
// -O2) runs 2.41 s per frame with it, 3.14 s without.
//
// An override reads the SAME param cells as the kernel it replaces, so
// the swap is invisible to the runtime — which makes the cell layout a
// contract. `sig` is the exact parameter list the override was written
// against; the generator refuses to emit it unless the recorded kernel
// still declares precisely that list, and refuses an override whose
// kernel the census no longer records at all.

: Override { s name s sig s body }

@ __overrides → ( Vec Override ) {
    : ( Vec Override ) v ( vec_new [Override] )
    ( vec_push [Override] v @ Override {
        `gk32_conv2d`
        `(const float* X, const float* Wt, const float* B, float* Y, long long Cin, long long H, long long W, long long Cout, long long kh, long long kw, long long OH, long long OW, long long ph, long long pw, long long sh, long long sw, long long hasB)`
        `
static void __nurl_sl_gk32_conv2d(long long* p, long long grid, long long block) {
    (void)grid; (void)block;
    const float* X  = *(const float**)(uintptr_t)p[0];
    const float* Wt = *(const float**)(uintptr_t)p[1];
    const float* B  = *(const float**)(uintptr_t)p[2];
    float* Y        = *(float**)(uintptr_t)p[3];
    long long Cin  = *(long long*)(uintptr_t)p[4];
    long long H    = *(long long*)(uintptr_t)p[5];
    long long W    = *(long long*)(uintptr_t)p[6];
    long long Cout = *(long long*)(uintptr_t)p[7];
    long long kh   = *(long long*)(uintptr_t)p[8];
    long long kw   = *(long long*)(uintptr_t)p[9];
    long long OH   = *(long long*)(uintptr_t)p[10];
    long long OW   = *(long long*)(uintptr_t)p[11];
    long long ph   = *(long long*)(uintptr_t)p[12];
    long long pw   = *(long long*)(uintptr_t)p[13];
    long long sh   = *(long long*)(uintptr_t)p[14];
    long long sw   = *(long long*)(uintptr_t)p[15];
    long long hasB = *(long long*)(uintptr_t)p[16];
    for (long long co = 0; co < Cout; co++) {
        float bias = hasB ? B[co] : 0.0f;
        for (long long oy = 0; oy < OH; oy++) {
            float* yrow = Y + (co * OH + oy) * OW;
            for (long long ox = 0; ox < OW; ox++) yrow[ox] = bias;
            for (long long ci = 0; ci < Cin; ci++) {
                for (long long ky = 0; ky < kh; ky++) {
                    long long iy = oy * sh - ph + ky;
                    if (iy < 0 || iy >= H) continue;
                    const float* xrow = X + (ci * H + iy) * W;
                    const float* wrow = Wt + ((co * Cin + ci) * kh + ky) * kw;
                    for (long long kx = 0; kx < kw; kx++) {
                        float wv = wrow[kx];
                        long long ix0 = kx - pw;
                        if (sw == 1) {
                            long long lo = ix0 < 0 ? -ix0 : 0;
                            long long hi = W - ix0; if (hi > OW) hi = OW;
                            const float* xr = xrow + ix0;
                            for (long long ox = lo; ox < hi; ox++) yrow[ox] += wv * xr[ox];
                        } else {
                            for (long long ox = 0; ox < OW; ox++) {
                                long long ix = ox * sw + ix0;
                                if (ix >= 0 && ix < W) yrow[ox] += wv * xrow[ix];
                            }
                        }
                    }
                }
            }
        }
    }
}
` } )
    ^ v
}

@ __fail s what s name → i {
    ( nurl_eprint `gen_static_kernels: ` ) ( nurl_eprint what ) ( nurl_eprint name ) ( nurl_eprint `\n` )
    ^ 1
}

// The override for kernel `name`, or -1.
@ __override_at ( Vec Override ) ov s name → i {
    : ~ i k 0
    ~ < k ( vec_len [Override] ov ) {
        ?? ( vec_get [Override] ov k ) { T o → { ? ( nurl_str_eq . o name name ) { ^ k } {} } F _ → {} }
        = k + k 1
    }
    ^ -1
}

// Build kernels_static.c from a census kit's record into `out`; the
// emitted entry names go to `names`. Returns the number of problems
// (0 = the file is complete and every override still fits).
@ onnx_static_c_from GpuKit kit String out ( Vec String ) names → i {
    : ~ i bad 0
    : ( Vec Override ) ov ( __overrides )
    ( string_push_str out ( cpu_static_header ) )
    : i n ( gk_kernel_count kit )
    : ~ i k 0
    ~ < k n {
        : s name ( gk_census_name kit k )
        : s src ( gk_census_src kit k )
        // the static launcher runs a block's threads one after another:
        // a kernel that waits on its block (a barrier, shared memory)
        // cannot run there and must not be silently miscompiled
        ? | >= ( nurl_str_find src `__syncthreads` ) 0 >= ( nurl_str_find src `__shared__` ) 0 {
            = bad + bad ( __fail `kernel needs block barriers, which the static backend cannot run: ` name )
        } {}
        : i oi ( __override_at ov name )
        ? >= oi 0 {
            ?? ( vec_get [Override] ov oi ) {
                T o → {
                    : String want ( string_from name )
                    ( string_push_str want . o sig )
                    ? >= ( nurl_str_find src ( string_data want ) ) 0 {
                        ( string_push_str out . o body )
                    } {
                        = bad + bad ( __fail `override no longer matches the kernel's parameter list (update its param cells): ` name )
                    }
                }
                F _ → {}
            }
        } {
            : String unit ( cpu_static_unit name src )
            ( string_push_str out ( string_data unit ) )
        }
        ( vec_push [String] names ( string_from name ) )
        = k + k 1
    }
    // an override whose kernel is gone is dead code that still claims a
    // layout — refuse it rather than carry it
    : ~ i j 0
    ~ < j ( vec_len [Override] ov ) {
        ?? ( vec_get [Override] ov j ) {
            T o → {
                : ~ b seen F
                : ~ i q 0
                ~ < q n { ? ( nurl_str_eq ( gk_census_name kit q ) . o name ) { = seen T } {} = q + q 1 }
                ? seen {} { = bad + bad ( __fail `override for a kernel the executor no longer launches: ` . o name ) }
            }
            F _ → {}
        }
        = j + j 1
    }
    : String reg ( cpu_static_registry names )
    ( string_push_str out ( string_data reg ) )
    ^ bad
}

// The whole file, from a fresh census: kernels_static.c into `out`, the
// emitted entry names into `names`. Returns the number of problems — a
// census call gpukit rejected, a kernel the static backend cannot run, an
// override that no longer fits — each reported on stderr; 0 = complete.
@ onnx_static_kernels_c String out ( Vec String ) names → i {
    : GpuKit kit ( gk_open_census )
    : i rejected ( rt_kernel_census kit )
    ? > rejected 0 { ^ rejected } {}
    ^ ( onnx_static_c_from kit out names )
}
