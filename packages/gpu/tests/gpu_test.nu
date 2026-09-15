// packages/gpu/tests/gpu_test.nu — tests for packages/gpu.
//
// Pure-CPU assertions always run (arg encoding, grid math). The on-device
// section runs a real vector-add and verifies it — but SKIPS cleanly
// (still exit 0) when no CUDA device is present, so the suite passes on a
// GPU-less CI box. Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/gpu_test.nu /tmp/gt && /tmp/gt

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/gpu.nu`

& `c` @ nurl_bits_to_f32 i b → f32

: ~ i g_fail 0

@ check b cond s name → v {
    ? cond { ( nurl_print `  ok  ` ) } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print name ) ( nurl_print `\n` )
}

// ── pure-CPU: argument encoding round-trips ──────────────────────
@ test_args → v {
    ( nurl_print `[args]\n` )
    // f32 encoder must reproduce the IEEE-754 bit pattern of 2.5f.
    : i bits ( gpu_arg_f32 2.5 )
    : f back # f ( nurl_bits_to_f32 bits )
    ( check & > back 2.49 < back 2.51 `f32 arg round-trips 2.5` )
    // int encoders are identity.
    ( check == ( gpu_arg_i32 42 ) 42 `i32 arg is identity` )
    // grid: ceil-div.
    ( check == ( gpu_grid 1000 256 ) 4 `grid(1000,256)=4` )
    ( check == ( gpu_grid 1024 256 ) 4 `grid(1024,256)=4` )
    ( check == ( gpu_grid 1025 256 ) 5 `grid(1025,256)=5` )
}

// ── on-device: real vector add ───────────────────────────────────
@ test_device → v {
    ( nurl_print `[device]\n` )
    : i count ( gpu_device_count )
    ? <= count 0 {
        ( nurl_print `  skip (no CUDA device)\n` )
        ^ {}
    } {}

    : Gpu g ( gpu_open 0 )
    ? ! ( gpu_ok g ) { ( check F `open device 0` ) ^ {} } {}

    : i n 4096
    : GpuKernel k ( gpu_compile g `extern "C" __global__ void vadd(const float* a, const float* b, float* c, int n){ int i=blockIdx.x*blockDim.x+threadIdx.x; if(i<n) c[i]=a[i]+b[i]; }` `vadd` )
    ? ! ( gpu_kernel_ok k ) { ( check F `compile vadd` ) ( gpu_close g ) ^ {} } {}

    : i bytes * n 4
    : *u ha ( gpu_host_alloc bytes )
    : *u hb ( gpu_host_alloc bytes )
    : *u hc ( gpu_host_alloc bytes )
    : ~ i i 0
    ~ < i n { ( gpu_host_set_f32 ha i # f i ) ( gpu_host_set_f32 hb i # f * 10 i ) = i + i 1 }

    : GpuBuffer da ( gpu_alloc g bytes )
    : GpuBuffer db ( gpu_alloc g bytes )
    : GpuBuffer dc ( gpu_alloc g bytes )
    ( gpu_upload da ha )
    ( gpu_upload db hb )

    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gpu_arg_buffer da ) )
    ( vec_push [i] args ( gpu_arg_buffer db ) )
    ( vec_push [i] args ( gpu_arg_buffer dc ) )
    ( vec_push [i] args ( gpu_arg_i32 n ) )
    ( gpu_launch k ( gpu_grid n 256 ) 256 args )
    ( gpu_sync g )
    ( gpu_download hc dc )

    : ~ i bad 0
    : ~ i j 0
    ~ < j n {
        : ~ f d - ( gpu_host_get_f32 hc j ) # f * 11 j
        ? < d 0.0 { = d - 0.0 d } {}
        ? > d 0.001 { = bad + bad 1 } {}
        = j + j 1
    }
    ( check == bad 0 `vadd 4096 elems == 11*i` )

    ( gpu_free da ) ( gpu_free db ) ( gpu_free dc )
    ( gpu_host_free ha ) ( gpu_host_free hb ) ( gpu_host_free hc )
    ( gpu_kernel_free k )
    ( gpu_close g )
}

// ── cooperative kernels: __shared__ + __syncthreads() ────────────
//
// A block reduction. It is not a kernel that merely HAPPENS to use shared
// memory — it cannot produce the right answer without the barrier: thread 0
// reads what thread 128 wrote.
//
// On the CPU backend this did not compile at all until the launcher learned to
// run a block's threads as fibers: `__shared__` and `__syncthreads()` were
// simply not defined, so the host compile failed and the kernel came back
// unusable. The package's promise is that the SAME CUDA-C runs on both
// backends, and for any cooperative kernel — which is most real CUDA — it was
// not true. This test is what holds it true.
//
// Runs on whichever backend gpu_open picks, so the suite is run twice.
@ test_coop → v {
    ( nurl_print `[cooperative]\n` )
    : Gpu g ( gpu_open ( gpu_best_device ) )
    ? ! ( gpu_ok g ) { ( check F `open a device (any backend)` ) ^ {} } {}

    : GpuKernel k ( gpu_compile g `extern "C" __global__ void blocksum(const float* x, float* out, int n){
        __shared__ float s[256];
        int t = threadIdx.x;
        int i = blockIdx.x*blockDim.x + t;
        s[t] = (i < n) ? x[i] : 0.f;
        __syncthreads();
        for (int off = blockDim.x >> 1; off > 0; off >>= 1) {
            if (t < off) s[t] += s[t + off];
            __syncthreads();
        }
        if (t == 0) out[blockIdx.x] = s[0];
    }` `blocksum` )
    ? ! ( gpu_kernel_ok k ) { ( check F `compile a kernel with __shared__ and __syncthreads()` ) ( gpu_close g ) ^ {} } {}

    : i n 4096
    : i nb / n 256
    : *u hx ( gpu_host_alloc * n 4 )
    : *u ho ( gpu_host_alloc * nb 4 )
    : ~ i i 0
    ~ < i n { ( gpu_host_set_f32 hx i # f i ) = i + i 1 }
    : GpuBuffer dx ( gpu_alloc g * n 4 )
    : GpuBuffer dout ( gpu_alloc g * nb 4 )
    ( gpu_upload dx hx )

    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gpu_arg_buffer dx ) )
    ( vec_push [i] args ( gpu_arg_buffer dout ) )
    ( vec_push [i] args ( gpu_arg_i32 n ) )
    ( gpu_launch k nb 256 args )
    ( gpu_sync g )
    ( gpu_download ho dout )

    // block b sums i = 256b … 256b+255 → 256*(256b) + (0+…+255)
    : ~ i bad 0
    : ~ i b 0
    ~ < b nb {
        : f want + * 256.0 # f * 256 b 32640.0
        : ~ f d - ( gpu_host_get_f32 ho b ) want
        ? < d 0.0 { = d - 0.0 d } {}
        ? > d 0.5 { = bad + bad 1 } {}
        = b + b 1
    }
    ( check == bad 0 `a shared-memory block reduction sums every block correctly (16 blocks x 256 threads)` )

    ( gpu_free dx ) ( gpu_free dout )
    ( gpu_host_free hx ) ( gpu_host_free ho )
    ( gpu_kernel_free k )
    ( gpu_close g )
}

// ── gpu_upload_batch: many tensors, one streamed pass ────────────
//
// The packing has three boundaries to get right: a tensor that starts
// mid-chunk and ends in the next (the 70 MB one crosses the 64 MB chunk),
// a run of small tensors sharing one chunk, and the partial chunk at the
// end. Each buffer gets its own pattern (value = index*7 + tensor id) so a
// byte landing in the wrong buffer or at the wrong offset is caught by the
// spot checks at both ends and the middle of every tensor.
@ test_batch → v {
    ( nurl_print `[upload_batch]\n` )
    : Gpu g ( gpu_open ( gpu_best_device ) )
    ? ! ( gpu_ok g ) { ( check F `open a device (any backend)` ) ^ {} } {}
    : ( Vec i ) sizes ( vec_new [i] )
    ( vec_push [i] sizes 73400320 )  // 70 MB: crosses a chunk boundary
    ( vec_push [i] sizes 4 )  // one float
    ( vec_push [i] sizes 5120 )
    ( vec_push [i] sizes 3276800 )  // a 1280x640 f32 matrix
    ( vec_push [i] sizes 3276800 )
    ( vec_push [i] sizes 13107200 )  // fc1-sized
    ( vec_push [i] sizes 1024 )
    : i nt ( vec_len [i] sizes )
    : ( Vec GpuCopy ) items ( vec_new [GpuCopy] )
    : ( Vec i ) hosts ( vec_new [i] )
    : ~ i t 0
    : ~ b alloc_ok T
    ~ < t nt {
        : ~ i bytes 0
        ?? ( vec_get [i] sizes t ) { T x → { = bytes x } F → {} }
        : *u h ( gpu_host_alloc bytes )
        : i nf / bytes 4
        : ~ i j 0
        // (index masked to 20 bits: the pattern must stay exact in an f32)
        ~ < j nf { ( gpu_host_set_f32 h j # f + * & j 1048575 7 t ) = j + j 1 }
        : GpuBuffer d ( gpu_alloc g bytes )
        ? == . d dptr 0 { = alloc_ok F } {}
        ( vec_push [GpuCopy] items @ GpuCopy { . d dptr # i h bytes } )
        ( vec_push [i] hosts # i h )
        = t + t 1
    }
    ( check alloc_ok `allocate 7 device buffers (94 MB)` )
    : i rc ( gpu_upload_batch items )
    ( check == rc 0 `gpu_upload_batch returns 0` )
    : ~ i bad 0
    = t 0
    ~ < t nt {
        ?? ( vec_get [GpuCopy] items t ) {
            T c → {
                : *u back ( gpu_host_alloc . c bytes )
                ( gpu_download back @ GpuBuffer { . c dptr . c bytes } )
                : i nf / . c bytes 4
                // first, middle, last — and every 1013th element in between
                : ~ i j 0
                ~ < j nf {
                    : f want # f + * & j 1048575 7 t
                    : ~ f d - ( gpu_host_get_f32 back j ) want
                    ? < d 0.0 { = d - 0.0 d } {}
                    ? > d 0.001 { = bad + bad 1 } {}
                    = j ? == j - nf 1 nf ? >= + j 1013 - nf 1 - nf 1 + j 1013
                }
                ( gpu_host_free back )
                ( gpu_free @ GpuBuffer { . c dptr . c bytes } )
            }
            F → {}
        }
        = t + t 1
    }
    ( check == bad 0 `every tensor lands whole, in its own buffer, at offset 0 (7 tensors, chunk-crossing 70 MB one included)` )
    = t 0
    ~ < t nt {
        ?? ( vec_get [i] hosts t ) { T h → { ( gpu_host_free # *u h ) } F → {} }
        = t + t 1
    }
    ( vec_free [i] hosts )
    ( vec_free [GpuCopy] items )
    ( vec_free [i] sizes )
    ( gpu_staging_free )
    ( gpu_close g )
}

@ main → i {
    ( test_args )
    ( test_device )
    ( test_coop )
    ( test_batch )
    ? == g_fail 0 { ( nurl_print `\nALL PASS\n` ) ^ 0 }
    { ( nurl_print `\n` ) ( nurl_print ( nurl_str_int g_fail ) ) ( nurl_print ` FAILED\n` ) ^ 1 }
}
