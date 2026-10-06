// packages/onnx/tests/webgpu/run.nu — run one ONNX forward on the gpu
// package's WebGPU backend, as a wasm32-wasi command (tests/webgpu_test.sh
// builds it; tests/webgpu/run.mjs hosts it in a browser / Deno).
//
//   host_blob_size(k) / host_blob_read(k, dst)
//        k = 0 model.onnx, 1 input (raw f32), 2 input shape (i64 per dim)
//   host_result(out, n)   the output tensor, n f32 values
//
// Exit status: 0 ran, 1 bad blobs, 2 no WebGPU (gpu_open / rt_open failed).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/pb.nu`
$ `src/model.nu`
$ `src/runtime.nu`

& `c` @ host_blob_size i kind → i

& `c` @ host_blob_read i kind *u dst → i

& `c` @ host_result *u data i n → v

unsafe @ blob i kind → ( Vec u ) {
    : i n ( host_blob_size kind )
    : ( Vec u ) b ( vec_with_cap [u] ? > n 0 n 1 )
    ? > n 0 {
        : i _r ( host_blob_read kind ( vec_data [u] b ) )
        : b _s ( vec_set_len [u] b n )
    } {}
    ^ b
}

unsafe @ main → i {
    ( gpu_force_webgpu )
    : ( Vec u ) mb ( blob 0 )
    : ( Vec u ) input ( blob 1 )
    : ( Vec u ) sb ( blob 2 )
    ? | | == ( vec_len [u] mb ) 0 == ( vec_len [u] input ) 0 == ( vec_len [u] sb ) 0 { ^ 1 } {}
    : ( Vec i ) shape ( vec_new [i] )
    : ~ i k 0
    ~ < k / ( vec_len [u] sb ) 8 {
        ( vec_push [i] shape ( nurl_peek # s ( vec_data [u] sb ) k ) )
        = k + k 1
    }
    : OGraph g ( onnx_parse mb )
    : Engine e ( rt_open 0 )
    ? ! ( rt_ok e ) { ^ 2 } {}
    ( nurl_print `device: ` ) ( nurl_print ( rt_name e ) ) ( nurl_print `\n` )
    : RTensor out ( rt_run_shaped e g ( vec_data [u] input ) shape )
    : GpuHost h ( rt_download e out )
    ( host_result ( gpu_host_ptr h ) . out nelem )
    ^ 0
}
