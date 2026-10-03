// gen_static_kernels.nu — write kernels_static.c: every kernel the onnx
// executor can launch, precompiled form for the gpu package's STATIC
// backend (backend 2 — no NVRTC, no host C++ compiler, no dlopen). The
// set is derived from the executor itself; see src/static_kernels.nu.
//
//   (from packages/onnx)  ../../nurl.sh tools/gen_static_kernels.nu gen
//   ./gen <out.c>
//
// Compile the output into any build:
//   native:  cc -O2 -c kernels_static.c && NURL_EXTRA_OBJS=kernels_static.o ./nurl.sh ...
//   wasm:    zig cc --target=wasm32-wasi -O2 -c kernels_static.c
// and select the backend with NURL_GPU=static or ( gpu_force_static ).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `src/static_kernels.nu`

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 2 { ( nurl_print `usage: gen_static_kernels <out.c>\n` ) ^ 2 } {}
    : String op ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }

    : String out ( string_with_cap 131072 )
    : ( Vec String ) names ( vec_new [String] )
    ? > ( onnx_static_kernels_c out names ) 0 {
        ( nurl_eprint `gen_static_kernels: no file written\n` )
        ^ 1
    } {}

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
