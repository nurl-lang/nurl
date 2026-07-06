# gpukit — the GPU-compute toolkit for NURL

One dependency for running compute on the GPU without the marshalling
boilerplate. The [`gpu`](../gpu) package is the low-level interface — open a
device, JIT-compile a CUDA-C kernel (NVRTC, or the host-C++ CPU backend),
allocate device buffers, upload/download, build the argument vector, compute a
grid, launch, sync, free. Every GPU-using package re-writes the same ~35 lines
of that dance for each kernel. `gpukit` is that glue, as a facade.

## Before / after

Hand-marshalled (the pattern in onnx / anomaly today):

```nurl
: GpuBuffer b_x   ( gpu_alloc g (* n 8) )
: GpuBuffer b_out ( gpu_alloc g (* n 8) )
( gpu_upload b_x (# *u (vec_data [f] xs)) )
: (Vec i) args ( vec_new [i] )
( vec_push [i] args (gpu_arg_buffer b_x) )
( vec_push [i] args (gpu_arg_i64 n) )
( vec_push [i] args (gpu_arg_buffer b_out) )
( gpu_launch k (gpu_grid n 256) 256 args )
( gpu_sync g )
( gpu_download (# *u (vec_data [f] out)) b_out )
( gpu_free b_x ) ( gpu_free b_out ) ( vec_free [i] args )
```

With gpukit:

```nurl
: (Vec GkArg) call ( vec_new [GkArg] )
( vec_push [GkArg] call ( gk_in_f  xs ) )
( vec_push [GkArg] call ( gk_i64   n  ) )
( vec_push [GkArg] call ( gk_out_f out ) )
( gk_run kit src `my_kernel` ( gk_grid n 256 ) 256 call )
( vec_free [GkArg] call )
```

`gk_run` compiles-and-caches the kernel by name, allocates a device buffer per
buffer binding, uploads inputs, marshals the args in binding order, launches,
syncs, downloads outputs, and frees every device buffer.

## Ready-made kernels

For the common cases you don't write a kernel at all:

```nurl
: GpuKit kit ( gk_open 0 )
( gk_add_f kit out a b )                 // out = a + b   (also sub/mul/div)
( gk_map_f kit `relu` out x `x>0.0?x:0.0` )   // out[i] = f(x)
( gk_matmul_f kit c a b m k n )          // C[m×n] = A[m×k]·B[k×n]
: ?f s ( gk_reduce_sum_f kit x )         // Σ x
: ?f d ( gk_dot_f kit a b )              // a·b
( gk_close kit )
```

## API

Lifecycle:

| Call | |
| --- | --- |
| `( gk_open ordinal )` → `GpuKit` | open a device (CUDA, else CPU backend) |
| `( gk_ok kit )` → `b`, `( gk_backend kit )` → `s`, `( gk_device_name kit )` → `s` | |
| `( gk_close kit )` | free cached kernels + close the device |
| `( gk_grid n block )` → `i` | grid size for `n` threads |

Bindings (`f` is a C `double`, `i` a C `long long`):

| Call | |
| --- | --- |
| `( gk_in_f v )` / `( gk_in_i v )` | input `double[]` / `long long[]` |
| `( gk_out_f v )` / `( gk_out_i v )` | output (caller pre-sizes) |
| `( gk_buf_in host bytes )` / `( gk_buf_out host bytes )` | raw buffer (e.g. packed f32) |
| `( gk_i64 v )` / `( gk_i32 v )` / `( gk_f32 v )` | scalar |

Workhorse:

| Call | |
| --- | --- |
| `( gk_run kit src name grid block call )` → `b` | compile-cached, marshal, launch, sync, download, free |

The `call` is a `Vec GkArg` listing the kernel's arguments in declaration
order (buffers and scalars interleaved exactly as the signature expects).

Ready-made f64 kernels: `gk_add_f` / `gk_sub_f` / `gk_mul_f` / `gk_div_f`,
`gk_map_f`, `gk_matmul_f`, `gk_reduce_sum_f`, `gk_dot_f`.

## Numerics

gpukit adds no numerics of its own — it only marshals — so a kernel runs
bit-for-bit the same through `gk_run` as through hand-written `gpu_*` calls,
and the gpu package's **CUDA / CPU-backend / pure equivalence is preserved**.
The elementwise ops and `gk_matmul_f` accumulate in the same order a
sequential host loop would, so they are **bit-identical** to a naive host
implementation. `gk_reduce_sum_f` / `gk_dot_f` combine per-thread partial sums
(a parallel order), matching a host sum to rounding but not guaranteed
bit-identical to a strictly sequential accumulation.

## Memory

`GpuKit` carries a stable kernel-cache Vec, so it is passed by value and
mutated across calls (like an `ArgParser`). Free it with `gk_close`.

## Device-resident buffers (`src/dev.nu`)

`gk_run` marshals host↔device per call; chained pipelines want data to
STAY on the device. `GkBuf` is an element-typed device allocation
(`GK_F32` | `GK_F64`) with `gk_dbuf_new/_free/_upload/_download`, and
`gk_run_dev` launches a cached kernel over raw device args with zero
copies. Ready-made dtype-generic kernels: `gkd_add/sub/mul/div`
(1-element scalar broadcast via the same kernel), `gkd_relu/sigmoid/
exp/tanh/sqrt/log`, `gkd_matmul`, `gkd_softmax_rows`, `gkd_sum`.
GK_F32 computes in true float32 (accumulation included);
`tests/devcheck.nu` verifies 12/12 vs numpy per dtype on CUDA and the
CPU backend.

## Tests

`./tests/gpukit_test.sh` builds `tests/demo.nu` and runs it on the default
backend and, when a host C++ compiler is present, on the CPU backend —
checking every bit-identical op with `==` against a host computation. On an
RTX 4090 and on the CPU backend: **14 / 14**.
