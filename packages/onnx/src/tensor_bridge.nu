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
//   * rt_run_dtensor BORROWS the input DTensor (the engine registers the
//     pointer but never frees it — the caller still dtensor_frees it, but
//     only AFTER the run's outputs are consumed or copied out).
//   * dtensor_from_output COPIES the output device-to-device into a fresh
//     owned DTensor. A copy (not an ownership transfer) because graph
//     outputs may ALIAS an owned base allocation at an offset
//     (Reshape/Split); freeing such a pointer would corrupt the heap, and
//     the engine frees its own allocations at the next rt_reset anyway.
//
// Only TE_F32 tensors cross the seam — graphs compute in float32.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/tensor/src/dev.nu`
$ `runtime.nu`

// Run a graph with a device-resident input: no host staging, no upload.
// The DTensor must be TE_F32 and shaped as the graph expects. Returns the
// graph's first output (engine-owned, valid until the next rt_reset).
@ rt_run_dtensor * Engine e OGraph g DTensor d → RTensor {
    ? & ( dtensor_ok d ) == ( dtensor_dtype d ) TE_F32 {} {
        ^ @ RTensor { ( string_new ) 0 ( vec_new [i] ) 0 }
    }
    ( rt_reset e )
    ( _rt_set_graph e g )
    ( rt_load_inits e g )
    ( rt_put e ( string_data . g input_name ) ( gk_arg_dev . d buf ) ( _shape_copy . d shape ) )
    ^ ( _rt_run_nodes e g )
}

// Wrap a run's output as an OWNED device tensor (device-to-device copy —
// see the ownership note above). The result lives independently of the
// engine: rt_reset / rt_close do not touch it; free with dtensor_free.
@ dtensor_from_output * GpuKit kit * Engine e RTensor t → DTensor {
    : i n . t nelem
    ? & > n 0 != . t dptr 0 {} {
        ^ @ DTensor { TE_F32 ( vec_new [i] ) @ GkBuf { 0 0 GK_F32 } }
    }
    : GkBuf b ( gk_dbuf_new kit n GK_F32 )
    ? ( gk_buf_ok b ) {} {
        ^ @ DTensor { TE_F32 ( vec_new [i] ) @ GkBuf { 0 0 GK_F32 } }
    }
    : GpuBuffer dst @ GpuBuffer { . b dptr * n 4 }
    ? == ( gpu_dtod dst . t dptr ) 0 {} {
        ( gk_dbuf_free b )
        ^ @ DTensor { TE_F32 ( vec_new [i] ) @ GkBuf { 0 0 GK_F32 } }
    }
    ^ @ DTensor { TE_F32 ( _shape_copy . t shape ) b }
}
