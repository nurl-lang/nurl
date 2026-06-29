// packages/gpu/src/main.nu — packages/gpu PoC demo.
//
// Proves GPU compute works from pure NURL: it lists the CUDA devices,
// compiles two CUDA-C kernels at runtime (NVRTC), runs them on the GPU
// over the neutral gpu.nu interface, and verifies the results against a
// CPU reference. No CUDA toolkit calls in the program — just gpu.nu.
//
//   gpu            # run the demo on device 0
//   gpu <ordinal>  # run on a specific device
//
// Build:  nurlpkg install gpu   (or ./nurl.sh packages/gpu/src/main.nu)

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/vec.nu`
$ `gpu.nu`

// ── kernels (CUDA-C, compiled at runtime) ─────────────────────────
@ k_vadd → s {
    ^ `extern "C" __global__ void vadd(const float* a, const float* b, float* c, int n){
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) c[i] = a[i] + b[i];
    }`
}

@ k_saxpy → s {
    ^ `extern "C" __global__ void saxpy(float alpha, const float* x, float* y, int n){
        int i = blockIdx.x*blockDim.x + threadIdx.x;
        if (i < n) y[i] = alpha*x[i] + y[i];
    }`
}

// ── helpers ───────────────────────────────────────────────────────
@ approx f a f b → b {
    : ~ f d - a b
    ? < d 0.0 { = d - 0.0 d } {}
    ^ < d 0.001
}

@ say s msg → v { ( nurl_print msg ) ( nurl_print `\n` ) }

// ── demo: vector add  c = a + b ───────────────────────────────────
@ demo_vadd Gpu g i n → i {
    ( say `\n[vadd] c[i] = a[i] + b[i]` )
    : GpuKernel k ( gpu_compile g ( k_vadd ) `vadd` )
    ? ! ( gpu_kernel_ok k ) { ( say `  compile FAILED` ) ^ 1 } {}

    : i bytes * n 4
    : *u ha ( gpu_host_alloc bytes )
    : *u hb ( gpu_host_alloc bytes )
    : *u hc ( gpu_host_alloc bytes )
    : ~ i i 0
    ~ < i n {
        ( gpu_host_set_f32 ha i # f i )
        ( gpu_host_set_f32 hb i # f * 2 i )
        = i + i 1
    }

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

    : i block 256
    : i r ( gpu_launch k ( gpu_grid n block ) block args )
    ? != r 0 { ( say `  launch FAILED` ) ^ 1 } {}
    ( gpu_sync g )
    ( gpu_download hc dc )

    : ~ i bad 0
    : ~ i j 0
    ~ < j n {
        ? ! ( approx ( gpu_host_get_f32 hc j ) # f * 3 j ) { = bad + bad 1 } {}
        = j + j 1
    }
    : i c7 # i ( gpu_host_get_f32 hc 7 )
    ( gpu_free da ) ( gpu_free db ) ( gpu_free dc )
    ( gpu_host_free ha ) ( gpu_host_free hb ) ( gpu_host_free hc )
    ( gpu_kernel_free k )

    ? == bad 0 {
        ( nurl_print `  OK — ` ) ( nurl_print ( nurl_str_int n ) )
        ( nurl_print ` elems, spot c[7]=` )
        ( nurl_print ( nurl_str_int c7 ) ) ( nurl_print ` (=3*7)\n` )
        ^ 0
    } {
        ( nurl_print `  MISMATCH: ` ) ( nurl_print ( nurl_str_int bad ) ) ( nurl_print ` wrong\n` )
        ^ 1
    }
}

// ── demo: SAXPY  y = alpha*x + y  (scalar float + int args) ───────
@ demo_saxpy Gpu g i n → i {
    ( say `\n[saxpy] y[i] = alpha*x[i] + y[i],  alpha=2.5` )
    : GpuKernel k ( gpu_compile g ( k_saxpy ) `saxpy` )
    ? ! ( gpu_kernel_ok k ) { ( say `  compile FAILED` ) ^ 1 } {}

    : f alpha 2.5
    : i bytes * n 4
    : *u hx ( gpu_host_alloc bytes )
    : *u hy ( gpu_host_alloc bytes )
    : ~ i i 0
    ~ < i n {
        ( gpu_host_set_f32 hx i # f i )
        ( gpu_host_set_f32 hy i 1.0 )
        = i + i 1
    }

    : GpuBuffer dx ( gpu_alloc g bytes )
    : GpuBuffer dy ( gpu_alloc g bytes )
    ( gpu_upload dx hx )
    ( gpu_upload dy hy )

    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gpu_arg_f32 alpha ) )
    ( vec_push [i] args ( gpu_arg_buffer dx ) )
    ( vec_push [i] args ( gpu_arg_buffer dy ) )
    ( vec_push [i] args ( gpu_arg_i32 n ) )

    : i block 256
    : i r ( gpu_launch k ( gpu_grid n block ) block args )
    ? != r 0 { ( say `  launch FAILED` ) ^ 1 } {}
    ( gpu_sync g )
    ( gpu_download hy dy )

    : ~ i bad 0
    : ~ i j 0
    ~ < j n {
        : f want + * alpha # f j 1.0
        ? ! ( approx ( gpu_host_get_f32 hy j ) want ) { = bad + bad 1 } {}
        = j + j 1
    }
    ( gpu_free dx ) ( gpu_free dy )
    ( gpu_host_free hx ) ( gpu_host_free hy )
    ( gpu_kernel_free k )

    ? == bad 0 {
        ( say `  OK — verified vs CPU` )
        ^ 0
    } {
        ( nurl_print `  MISMATCH: ` ) ( nurl_print ( nurl_str_int bad ) ) ( nurl_print ` wrong\n` )
        ^ 1
    }
}

@ main → i {
    : ~ i ordinal 0
    ? > ( env_args_count ) 1 {
        : ( Vec String ) av ( env_args_list )
        ?? ( vec_get [String] av 1 )
        { T a → = ordinal ( nurl_str_to_int ( string_data a ) ) F _ → {} }
    } {}

    : i count ( gpu_device_count )
    ? <= count 0 {
        ( say `No CUDA devices found (is the NVIDIA driver loaded?).` )
        ^ 1
    } {}
    ( nurl_print `CUDA devices: ` ) ( nurl_print ( nurl_str_int count ) ) ( nurl_print `\n` )

    : Gpu g ( gpu_open ordinal )
    ? ! ( gpu_ok g ) {
        ( nurl_print `Failed to open device ` ) ( nurl_print ( nurl_str_int ordinal ) ) ( nurl_print `\n` )
        ^ 1
    } {}
    ( nurl_print `Using device ` ) ( nurl_print ( nurl_str_int ordinal ) )
    ( nurl_print `: ` ) ( nurl_print ( gpu_name g ) ) ( nurl_print `\n` )

    : i n 1000000
    : ~ i fails 0
    = fails + fails ( demo_vadd g n )
    = fails + fails ( demo_saxpy g n )

    ( gpu_close g )
    ? == fails 0 {
        ( say `\nAll GPU kernels verified. ✓` )
        ^ 0
    } {
        ( say `\nSome kernels failed. ✗` )
        ^ 1
    }
}
