// onnx/tensor_bridge.nu — zero-copy seam between the tensor package's
// device tensors (DTensor) and the onnx graph runtime (M4a).
//
// The gpu package opens the device's PRIMARY CUDA context, so every
// package in the process shares one device address space: a DTensor's
// GkBuf and an Engine's RTensor are pointers into the same heap. That
// makes composition free of host roundtrips:
//
//     preprocess with dtensor_* ops  →  run the graph  →  postprocess
//     with dtensor_* ops — the activations never touch the host.
//
// Ownership rules:
//   * rt_run_dtensor registers another owner of the input DTensor's
//     device block as the graph input: the block lives as long as the run
//     needs it, whatever the caller does with the DTensor.
//   * dtensor_from_output COPIES the output device-to-device into a fresh
//     owned DTensor (released with its last owner). A copy, not a share,
//     because a graph output may ALIAS another tensor's block at an
//     offset (Reshape/Split), and a DTensor is the caller's to write.
//
// Only TE_F32 tensors cross the seam — graphs compute in float32.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/tensor/src/dev.nu`
$ `runtime.nu`

// Run a graph with a device-resident input: no host staging, no upload.
// The DTensor must be TE_F32 and shaped as the graph expects. Returns the
// graph's first output.
@ rt_run_dtensor Engine h OGraph g DTensor d → RTensor {
    ? & ( dtensor_ok d ) == ( dtensor_dtype d ) TE_F32 {} { ^ ( _rt_none ) }
    : ~ EngineImpl e ( locked_take [EngineImpl] . h l )
    ( _rt_set_graph e g )
    ( rt_load_inits e g )
    ( rt_put e ( string_data . g input_name ) ( gk_buf_view . d buf 0 ( gk_buf_len . d buf ) ) ( _shape_copy . d shape ) )
    : RTensor out ( _rt_run_nodes e g )
    ( locked_restore [EngineImpl] . h l e )
    ^ out
}

// Copy a run's output into an OWNED device tensor (device-to-device — see
// the ownership note above). The result lives independently of the
// engine and of the output.
@ dtensor_from_output GpuKit kit Engine e RTensor t → DTensor {
    : i n . t nelem
    ? & > n 0 ( gk_buf_ok . t buf ) {} {
        ^ @ DTensor { TE_F32 ( vec_new [i] ) ( gk_buf_none GK_F32 ) }
    }
    : GkBuf b ( gk_dbuf_new kit n GK_F32 )
    ? ( gk_dbuf_copy kit b . t buf ) {} {
        ^ @ DTensor { TE_F32 ( vec_new [i] ) ( gk_buf_none GK_F32 ) }
    }
    ^ @ DTensor { TE_F32 ( _shape_copy . t shape ) b }
}
