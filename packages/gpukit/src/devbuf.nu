// gpukit/devbuf.nu — the device buffer type (GkBuf) and the owner of its
// block, on their own so that dev.nu and checked.nu can both name them
// before either's functions (dev.nu's ops run as checked kernels, and a
// checked call binds GkBufs).

$ `stdlib/std/arc.nu`
$ `gpukit.nu`

: i GK_F64 0
: i GK_F32 1
: i GK_I64 2

// An element-typed device allocation: `dptr`, `n` and `dtype` are plain
// fields (read them freely), `mem` owns the block. dptr 0 = failed or
// empty. Every copy of a GkBuf — a struct field, a Vec element, a view
// into it — holds the block, and its LAST owner hands it back to the
// kit's pool (gpukit.nu): nothing is freed by hand. gk_dbuf_free is an
// optional early release of one owner.
raw : GkBuf {
    i dptr
    i n
    i dtype
    ? GkMem mem
}

// The owner of one pooled block: its device pointer and the kit whose
// pool it came from (held, so the kit — and its device — outlive it).
// A census kit's block is `host` itself — bytes this owner holds, given
// back to no pool.
raw : GkMemImpl { i dptr GpuKit kit ( Vec u ) host }

% Drop GkMemImpl { @ drop GkMemImpl x → v { ? == 0 ( vec_len [u] . x host ) { ( _gk_pool_give . x kit . x dptr ) } {} } }

: GkMem { ( Arc GkMemImpl ) a }

@ GkMem_share GkMem h → GkMem { ^ @ GkMem { ( arc_clone [GkMemImpl] . h a ) } }

@ GkMem_drop sink GkMem h → v {}
