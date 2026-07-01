/* stdlib/cuda_stubs.c — weak-free fallback definitions of the CUDA Driver API
 * symbols packages/gpu/src/cuda.nu binds. nurl.sh links THIS object instead of
 * -lcuda when libcuda is not available on the build host, so a program that
 * references the CUDA backend still LINKS and LOADS on a machine with no
 * NVIDIA driver — every call returns a non-zero CUresult, which makes
 * gpu_open fall back to the CPU backend (packages/gpu/src/cpu.nu).
 *
 * Empty parameter lists (K&R, no prototype) so each stub is callable with the
 * driver's real argument counts. Never linked alongside the real libcuda (that
 * would be a duplicate-symbol error) — nurl.sh picks exactly one. */
int cuInit()                { return 100; }  /* CUDA_ERROR_NO_DEVICE-ish */
int cuDeviceGetCount(void *c){ if (c) *(int*)c = 0; return 100; }
int cuDeviceGet()           { return 100; }
int cuDeviceGetName()       { return 100; }
int cuCtxCreate()           { return 100; }
int cuCtxDestroy()          { return 100; }
int cuCtxSynchronize()      { return 100; }
int cuModuleLoadData()      { return 100; }
int cuModuleUnload()        { return 100; }
int cuModuleGetFunction()   { return 100; }
int cuMemAlloc()            { return 100; }
int cuMemFree()             { return 100; }
int cuMemcpyHtoD()          { return 100; }
int cuMemcpyDtoH()          { return 100; }
int cuLaunchKernel()        { return 100; }
int cuGetErrorName()        { return 100; }
