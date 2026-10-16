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

// (Up to 0.12.2 conv2d had a hand-written C override here, because the
// kernel gpukit generated for it left a CPU vectoriser nothing
// unit-stride. gpukit's host conv2d is now written for the host's
// vectoriser itself — a run of output columns per thread, read from a
// local copy of the input row — and the generic translation of it runs
// tinyyolov2 on the native static backend in 1.65 s against the
// override's 2.17 s. It is also bit-identical to the CPU and CUDA
// backends, which the override was not: it skipped the padding taps the
// kernel adds as zeros, so a negative zero sum came out positive.)

@ __fail s what s name → i {
    ( nurl_eprint `gen_static_kernels: ` ) ( nurl_eprint what ) ( nurl_eprint name ) ( nurl_eprint `\n` )
    ^ 1
}

// Build kernels_static.c from a census kit's record into `out`; the
// emitted entry names go to `names`. Returns the number of problems
// (0 = the file is complete).
@ onnx_static_c_from GpuKit kit String out ( Vec String ) names → i {
    : ~ i bad 0
    ( string_push_str out ( cpu_static_header ) )
    : i n ( gk_kernel_count kit )
    : ~ i k 0
    ~ < k n {
        : String name__s ( gk_census_name kit k )
        : s name ( string_data name__s )
        : String src__s ( gk_census_src kit k )
        : s src ( string_data src__s )
        // the static launcher runs a block's threads one after another:
        // a kernel that waits on its block (a barrier, shared memory)
        // cannot run there and must not be silently miscompiled
        ? | >= ( nurl_str_find src `__syncthreads` ) 0 >= ( nurl_str_find src `__shared__` ) 0 {
            = bad + bad ( __fail `kernel needs block barriers, which the static backend cannot run: ` name )
        } {}
        : String unit ( cpu_static_unit name src )
        ( string_push_str out ( string_data unit ) )
        ( vec_push [String] names ( string_from name ) )
        = k + k 1
    }
    : String reg ( cpu_static_registry names )
    ( string_push_str out ( string_data reg ) )
    ^ bad
}

// The whole file, from a fresh census: kernels_static.c into `out`, the
// emitted entry names into `names`. Returns the number of problems — a
// census call gpukit rejected or a kernel the static backend cannot run —
// each reported on stderr; 0 = complete.
@ onnx_static_kernels_c String out ( Vec String ) names → i {
    : GpuKit kit ( gk_open_census )
    : i rejected ( rt_kernel_census kit )
    ? > rejected 0 { ^ rejected } {}
    ^ ( onnx_static_c_from kit out names )
}
