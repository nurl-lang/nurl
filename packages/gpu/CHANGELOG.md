# Changelog

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
