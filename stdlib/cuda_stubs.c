/* stdlib/cuda_stubs.c — fallback definitions of the CUDA Driver API symbols
 * packages/gpu/src/cuda.nu binds. nurl.sh / nurl.bat link THIS translation
 * unit instead of -lcuda when libcuda (nvcuda.dll on Windows) is not
 * available at link time, so a program that references the CUDA backend
 * still LINKS and LOADS on a machine with no NVIDIA driver — every call
 * returns a non-zero CUresult, which makes gpu_open fall back to the CPU
 * backend (packages/gpu/src/cpu.nu).
 *
 * THIS LIST MUST COVER EVERY `& `cuda` @ …` DECLARATION IN cuda.nu. A symbol
 * bound there but missing here is not a compile error — it is an undefined
 * symbol at link time, on every host without a driver. When you add an FFI
 * binding to cuda.nu, add its stub here in the same commit:
 *     grep -o '@ cu[A-Za-z0-9_]*' packages/gpu/src/cuda.nu | sort -u
 *
 * Empty parameter lists (K&R, no prototype) so each stub is callable with the
 * driver's real argument counts; the few that must zero an out-parameter
 * declare just the leading arguments they touch, which is ABI-safe on both
 * SysV and Win64 (the caller cleans up). Never linked alongside the real
 * libcuda (that would be a duplicate-symbol error) — the launcher picks
 * exactly one. */

#define CUDA_ERROR_NO_DEVICE 100

/* ── init / device query ─────────────────────────────────────── */
int cuInit()                 { return CUDA_ERROR_NO_DEVICE; }
int cuDeviceGetCount(void *c){ if (c) *(int *)c = 0; return CUDA_ERROR_NO_DEVICE; }
int cuDeviceGet()            { return CUDA_ERROR_NO_DEVICE; }
int cuDeviceGetName()        { return CUDA_ERROR_NO_DEVICE; }
int cuDeviceGetAttribute(void *o) { if (o) *(int *)o = 0; return CUDA_ERROR_NO_DEVICE; }
int cuDeviceTotalMem_v2(void *b)  { if (b) *(unsigned long long *)b = 0; return CUDA_ERROR_NO_DEVICE; }

/* ── contexts ────────────────────────────────────────────────── */
int cuCtxCreate_v2(void *p)  { if (p) *(void **)p = 0; return CUDA_ERROR_NO_DEVICE; }
int cuCtxDestroy_v2()        { return CUDA_ERROR_NO_DEVICE; }
int cuCtxSetCurrent()        { return CUDA_ERROR_NO_DEVICE; }
int cuCtxSynchronize()       { return CUDA_ERROR_NO_DEVICE; }
int cuDevicePrimaryCtxRetain(void *p) { if (p) *(void **)p = 0; return CUDA_ERROR_NO_DEVICE; }
int cuDevicePrimaryCtxRelease_v2()    { return CUDA_ERROR_NO_DEVICE; }

/* ── modules / kernels ───────────────────────────────────────── */
int cuModuleLoadData(void *m){ if (m) *(void **)m = 0; return CUDA_ERROR_NO_DEVICE; }
int cuModuleUnload()         { return CUDA_ERROR_NO_DEVICE; }
int cuModuleGetFunction(void *f) { if (f) *(void **)f = 0; return CUDA_ERROR_NO_DEVICE; }
int cuLaunchKernel()         { return CUDA_ERROR_NO_DEVICE; }

/* ── device memory ───────────────────────────────────────────── */
int cuMemAlloc_v2(void *d)   { if (d) *(unsigned long long *)d = 0; return CUDA_ERROR_NO_DEVICE; }
int cuMemFree_v2()           { return CUDA_ERROR_NO_DEVICE; }
int cuMemGetInfo_v2(void *f, void *t) {
    if (f) *(unsigned long long *)f = 0;
    if (t) *(unsigned long long *)t = 0;
    return CUDA_ERROR_NO_DEVICE;
}
int cuMemcpyHtoD_v2()        { return CUDA_ERROR_NO_DEVICE; }
int cuMemcpyDtoH_v2()        { return CUDA_ERROR_NO_DEVICE; }
int cuMemcpyDtoD_v2()        { return CUDA_ERROR_NO_DEVICE; }
int cuMemcpyHtoDAsync_v2()   { return CUDA_ERROR_NO_DEVICE; }

/* ── pinned / registered host memory ─────────────────────────── */
int cuMemHostAlloc(void *pp) { if (pp) *(void **)pp = 0; return CUDA_ERROR_NO_DEVICE; }
int cuMemFreeHost()          { return CUDA_ERROR_NO_DEVICE; }
int cuMemHostRegister_v2()   { return CUDA_ERROR_NO_DEVICE; }
int cuMemHostUnregister()    { return CUDA_ERROR_NO_DEVICE; }

/* ── streams ─────────────────────────────────────────────────── */
int cuStreamCreate(void *o)  { if (o) *(void **)o = 0; return CUDA_ERROR_NO_DEVICE; }
int cuStreamSynchronize()    { return CUDA_ERROR_NO_DEVICE; }
int cuStreamBeginCapture_v2(){ return CUDA_ERROR_NO_DEVICE; }
int cuStreamEndCapture(void *s, void *g) { (void)s; if (g) *(void **)g = 0; return CUDA_ERROR_NO_DEVICE; }

/* ── graphs ──────────────────────────────────────────────────── */
int cuGraphInstantiateWithFlags(void *e) { if (e) *(void **)e = 0; return CUDA_ERROR_NO_DEVICE; }
int cuGraphLaunch()          { return CUDA_ERROR_NO_DEVICE; }
int cuGraphExecDestroy()     { return CUDA_ERROR_NO_DEVICE; }
int cuGraphDestroy()         { return CUDA_ERROR_NO_DEVICE; }

/* ── events ──────────────────────────────────────────────────── */
int cuEventCreate(void *p)   { if (p) *(void **)p = 0; return CUDA_ERROR_NO_DEVICE; }
int cuEventRecord()          { return CUDA_ERROR_NO_DEVICE; }
int cuEventSynchronize()     { return CUDA_ERROR_NO_DEVICE; }
int cuEventElapsedTime(void *ms) { if (ms) *(float *)ms = 0.0f; return CUDA_ERROR_NO_DEVICE; }
int cuEventDestroy_v2()      { return CUDA_ERROR_NO_DEVICE; }

/* ── diagnostics ─────────────────────────────────────────────── */
/* Unlike the rest, this one SUCCEEDS: a caller that reports an error
 * dereferences the string it hands back, so returning a failure with the
 * out-pointer untouched would turn a clean CPU-fallback message into a
 * null dereference. Hand out a real static string and return CUDA_SUCCESS. */
int cuGetErrorName(int err, void *pstr) {
    static const char *name = "CUDA_ERROR_NO_DEVICE (no driver; CPU fallback)";
    (void)err;
    if (pstr) *(const char **)pstr = name;
    return 0;
}

/* ── legacy aliases ──────────────────────────────────────────── */
/* Pre-_v2 spellings, kept so an older pinned packages/gpu that binds the
 * un-suffixed names still links against this same object. */
int cuCtxCreate()            { return CUDA_ERROR_NO_DEVICE; }
int cuCtxDestroy()           { return CUDA_ERROR_NO_DEVICE; }
int cuDeviceTotalMem(void *b){ if (b) *(unsigned long long *)b = 0; return CUDA_ERROR_NO_DEVICE; }
int cuMemAlloc(void *d)      { if (d) *(unsigned long long *)d = 0; return CUDA_ERROR_NO_DEVICE; }
int cuMemFree()              { return CUDA_ERROR_NO_DEVICE; }
int cuMemcpyHtoD()           { return CUDA_ERROR_NO_DEVICE; }
int cuMemcpyDtoH()           { return CUDA_ERROR_NO_DEVICE; }
