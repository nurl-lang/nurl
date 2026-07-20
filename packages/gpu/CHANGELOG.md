# Changelog

## 0.9.0

- **Pinned-staged uploads.** `gpu_upload` copies of 64 MB or more go
  through two page-locked staging buffers with `cuMemcpyHtoDAsync`, so
  the host memcpy of chunk N+1 overlaps the DMA of chunk N, and the
  chunk memcpy itself runs as four parallel stripes (a single thread
  copying out of the page cache tops out around 5 GB/s, which — not
  PCIe — is the upload wall at model sizes). Serial fallback when
  thread spawn or pinned allocation fails; `gpu_staging_free` releases
  the buffers once a loader is done. New bindings: `cuda_host_alloc`,
  `cuda_host_free`, `cuda_htod_async`, `cuda_stream_sync`.
- **`gpu_host_register` / `gpu_host_unregister`** — page-lock an
  existing host range (e.g. a small mmap'd region) so uploads out of it
  are direct DMA; uploads whose source lies in the registered range
  skip the staging path. Note: registering a whole multi-GB model file
  measures ~1 GB/s on Linux, so for big files staging wins.

## 0.8.0

- **CUBIN kernel cache (CUDA).** `gpu_compile` now compiles straight to a
  device-specific CUBIN (`nvrtcGetCUBIN` with `-arch=sm_<cc>`) and caches
  that, so `cuModuleLoadData` needs no driver JIT — loading the previous
  PTX cache made the driver re-JIT every kernel on every process start,
  which was the exact latency the cache existed to remove. Falls back to
  the old PTX path (and its cache) on any failure, e.g. an NVRTC too old
  to emit CUBINs. New binding: `cuda_compile_cubin`.

## 0.3.0

- **Primary CUDA context.** `gpu_open` now retains the device's PRIMARY
  context (`cuDevicePrimaryCtxRetain` + `cuCtxSetCurrent`) instead of
  creating a private one — the same convention the CUDA runtime API uses.
  Every consumer in the process that opens the same device shares ONE
  context and therefore one device address space, so device pointers flow
  between packages (a gpukit buffer straight into an onnx graph, …).
  `gpu_close` releases the retain.
- **Modern driver ABI (`_v2` symbols).** All memory/copy/context entry
  points now bind the 64-bit `_v2` driver symbols (`cuMemAlloc_v2`,
  `cuMemFree_v2`, `cuMemcpyHtoD_v2`, `cuMemcpyDtoH_v2`, `cuCtxDestroy_v2`,
  `cuDevicePrimaryCtxRelease_v2`). The old unversioned names are the
  legacy pre-CUDA-3.2 ABI with 32-bit device addresses — they happened to
  work inside a legacy `cuCtxCreate` context (low addresses) and silently
  break with 64-bit addresses; this was a live 4 GB landmine.
- **`gpu_dtod`** — device→device copy from a raw device pointer into a
  `GpuBuffer` (`cuMemcpyDtoD_v2`; plain memcpy on the CPU backend). The
  primitive the tensor↔onnx zero-copy bridge builds on.

## 0.2.1

- Leak fixes (`__outslot`, `cpu_compile`) — ASan-clean.

## 0.2.0

- CPU backend: the same CUDA-C kernels run on the host via `c++`/OpenMP
  when no device is present (`NURL_GPU=cpu` forces it).

## 0.1.0

- Initial release: CUDA driver API + NVRTC from pure NURL — open device,
  JIT-compile kernels, allocate/upload/download, launch, sync.
