# gpu — GPU compute for NURL

A backend-neutral GPU compute interface for NURL, with **two backends: CUDA
and CPU**. You write a kernel in CUDA-C, and it runs either on the GPU (NVRTC
compiles it to PTX at runtime; the CUDA Driver API launches it — bound
directly from pure NURL, no C bridge in the core runtime) **or on the CPU**
when no GPU is available.

## CPU backend (v0.2.0) — run with no GPU

`gpu_open` selects CUDA when a device is present, and otherwise **falls back
to the CPU backend** (`NURL_GPU=cpu` forces it). The CPU backend runs the
*same* CUDA-C kernels: each is wrapped in a small CUDA-compatibility shim
(`blockIdx` / `threadIdx` / `blockDim` / `gridDim` as thread-locals,
`__global__` / `__device__` as no-op macros) plus a generated grid-loop entry
point, compiled to a shared object by the system C++ compiler, `dlopen`'d, and
run — with **OpenMP parallelising the grid across cores**. `gpu_launch`'s
`void**` argument array is byte-for-byte what CUDA passes, so the neutral
`Gpu` / `GpuKernel` / `GpuBuffer` surface is unchanged and every caller
(`onnx`, `objdet`, `yoloe`) gets the fallback for free. The only host
requirement is a **C++ compiler on `PATH`** — the CPU analogue of NVRTC.

Verified identical results CPU vs GPU: the onnx tiny MLP matches the
onnxruntime reference, and the full **267-node YOLOE-seg forward** gives the
same detections on the CPU as on an RTX 4090.

On a machine with **no NVIDIA driver at all**, the toolchain links small
stub objects (`stdlib/{cuda,nvrtc}_stubs.o`) in place of `-lcuda` / `-lnvrtc`,
so a `packages/gpu` program still **links and loads** and auto-falls-back to
the CPU. Build a portable CPU-only binary even on a GPU host with
`NURL_GPU_STUBS=1`.

```
gpu            # run the PoC demo on device 0
gpu <ordinal>  # run on a specific device
```

```
CUDA devices: 2
Using device 0: NVIDIA GeForce RTX 4090

[vadd] c[i] = a[i] + b[i]
  OK — 1000000 elems, spot c[7]=21 (=3*7)

[saxpy] y[i] = alpha*x[i] + y[i],  alpha=2.5
  OK — verified vs CPU

All GPU kernels verified. ✓
```

## Design — why it stays out of the core

NURL's core (`runtime.c`) installs unchanged on machines with **no GPU**
(e.g. a MILK-V Duo). So this package touches none of it:

- The CUDA Driver API (`& \`cuda\``) and NVRTC (`& \`nvrtc\``) are bound
  with **inline FFI declarations in `src/cuda.nu`** — the only file that
  imports anything external.
- The toolchain auto-links `-lcuda` / `-lnvrtc` **only when a program
  actually references those symbols** (the same mechanism used for opus /
  ALSA / SDL2). A GPU-less program never grows the dependency.
- `libcuda` ships with the **NVIDIA driver** — no CUDA *toolkit* needed at
  runtime. Runtime kernel compilation needs **NVRTC** (`libnvrtc`, from
  the toolkit); a program that embeds pre-built PTX needs only the driver.

The only core addition is four generic, dependency-free typed-buffer
accessors in `runtime.c` (`nurl_peek_f32` / `nurl_poke_f32` / `_i32`) —
4-byte-stride access to the `float32` / `int32` arrays that are the native
GPU element layout (the stock 8-byte `nurl_peek`/`poke` can't address
them). They ship to every target and require no GPU.

## API (`src/gpu.nu`)

Backend-neutral types — `Gpu`, `GpuKernel`, `GpuBuffer` — so a future
backend (ROCm/HIP, OpenCL, a CPU fallback) slots in behind the same names.

| function | purpose |
|---|---|
| `gpu_device_count → i` | number of CUDA devices |
| `gpu_open i ordinal → Gpu` | init driver, bind device, retain the PRIMARY context (shared process-wide) |
| `gpu_ok Gpu → b` / `gpu_name Gpu → s` | status / device name |
| `gpu_compile Gpu s src s name → GpuKernel` | NVRTC compile + load `extern "C" __global__` entry |
| `gpu_alloc Gpu i bytes → GpuBuffer` | device allocation |
| `gpu_host_alloc i bytes → *u` | host staging buffer (+ `gpu_host_{set,get}_{f32,i32}`) |
| `gpu_upload GpuBuffer *u host → i` | host → device |
| `gpu_download *u host GpuBuffer → i` | device → host |
| `gpu_arg_buffer/_i32/_i64/_f32 → i` | encode one kernel argument |
| `gpu_launch GpuKernel i grid i block (Vec i) args → i` | 1-D launch |
| `gpu_grid i n i block → i` | ceil-div grid size |
| `gpu_sync Gpu → i` | block until work completes |
| `gpu_free` / `gpu_kernel_free` / `gpu_close` | release |

## Example

```
$ `gpu.nu`

@ main → i {
    : Gpu g ( gpu_open 0 )
    : GpuKernel k ( gpu_compile g
        `extern "C" __global__ void vadd(const float* a, const float* b, float* c, int n){
             int i = blockIdx.x*blockDim.x + threadIdx.x; if (i<n) c[i]=a[i]+b[i]; }`
        `vadd` )

    : i n 1024
    : i bytes * n 4
    : *u ha ( gpu_host_alloc bytes )      // fill ha, hb with gpu_host_set_f32 ...
    : GpuBuffer da ( gpu_alloc g bytes )
    ( gpu_upload da ha )                   // ... db, dc likewise

    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gpu_arg_buffer da ) )   // a, b, c, then:
    ( vec_push [i] args ( gpu_arg_i32 n ) )
    ( gpu_launch k ( gpu_grid n 256 ) 256 args )
    ( gpu_sync g )
    ( gpu_download hc dc )
    ( gpu_close g )
    ^ 0
}
```

## Kernel-argument ABI

`gpu_launch` takes a `Vec i` of arguments built with the `gpu_arg_*`
encoders. Each encodes one value into an `i64` cell; `gpu_launch` builds
the `void**` array CUDA's `cuLaunchKernel` expects, pointing each entry at
its cell. CUDA reads `sizeof(param)` bytes, so a 4-byte `int`/`float` in
the low bytes of an 8-byte cell is correct on little-endian. **A `float`
scalar must go through `gpu_arg_f32`** (it stores the 32-bit IEEE-754
pattern); passing a raw double would mis-encode it.

## Requirements

- NVIDIA driver (`libcuda.so`) — for any GPU work.
- NVRTC (`libnvrtc.so`, CUDA toolkit) — for `gpu_compile`. Embed PTX to
  avoid it.
- Tested against CUDA 13 driver / CUDA 12 toolkit on GTX 970 + RTX 4090.

## Status & roadmap

v0.1.0 is a PoC: 1-D launches, synchronous execution, f32/i32/pointer
arguments. Not yet: streams/async, multi-dimensional grids beyond x,
shared-memory configuration, a second backend. The interface is shaped to
add them without breaking callers.
