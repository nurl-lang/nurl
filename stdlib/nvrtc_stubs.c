/* stdlib/nvrtc_stubs.c — fallback definitions of the NVRTC symbols
 * packages/gpu/src/cuda.nu binds. nurl.sh links this instead of -lnvrtc when
 * libnvrtc is absent, so a CUDA-referencing program links on a host with no
 * CUDA toolkit. Every call returns a non-zero nvrtcResult; with no GPU the
 * CPU backend runs the kernels instead, so these are never reached. Never
 * linked alongside the real libnvrtc. */
int nvrtcCreateProgram()      { return 1; }
int nvrtcCompileProgram()     { return 1; }
int nvrtcGetPTXSize(void *a, void *b) { if (b) *(long*)b = 0; return 1; }
int nvrtcGetPTX()             { return 1; }
int nvrtcGetCUBINSize(void *a, void *b) { if (b) *(long*)b = 0; return 1; }
int nvrtcGetCUBIN()           { return 1; }
int nvrtcGetProgramLogSize(void *a, void *b) { if (b) *(long*)b = 0; return 1; }
int nvrtcGetProgramLog()      { return 1; }
int nvrtcDestroyProgram()     { return 1; }
