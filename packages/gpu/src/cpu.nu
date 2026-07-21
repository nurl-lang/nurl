// packages/gpu/src/cpu.nu — a CPU backend for packages/gpu.
//
// Runs the very same CUDA-C kernels the CUDA backend does, but on the host:
// each kernel source is wrapped in a CUDA-compatibility shim (blockIdx /
// threadIdx / blockDim / gridDim as thread-locals, `__global__` etc. as
// no-op macros) plus a generated grid-loop entry point, compiled to a shared
// object by the system C++ compiler, dlopen'd, and run — with OpenMP
// parallelising the grid across cores. `gpu_launch`'s void** argument array
// is byte-for-byte what CUDA passes, so the generated wrapper just casts each
// slot per the kernel's parameter type: no change to the neutral surface.
//
// This makes an onnx/YOLOE model runnable with no GPU at all (see gpu.nu's
// backend fallback). The only host requirement is a C++ compiler on PATH —
// the CPU analogue of NVRTC.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/hash.nu`
$ `stdlib/ext/env.nu`

& `c` @ dlopen s path i flags → *u

& `c` @ dlsym *u handle s name → *u

& `c` @ dlclose *u handle → i

& `c` @ system s cmd → i

& `c` @ nurl_peek_i32 *u base i idx → i32

& `c` @ nurl_poke_i32 *u base i idx i32 val → v

& `c` @ nurl_cpu_launch *u fn *u params i grid i block → v

// ── CUDA-C → host source generation ───────────────────────────────
@ __cpu_header → s {
    ^ `#include <math.h>
#include <stdint.h>
typedef struct { int x, y, z; } __nurl_dim3;
static __thread __nurl_dim3 blockIdx, threadIdx, blockDim, gridDim;
#define __global__
// __device__ is an execution-space qualifier, NOT a storage class:
// "__device__ static inline f()" is legal CUDA, so expanding it to
// "static" would emit "static static inline" (duplicate specifier).
// It means nothing on the host — expand it away and let the kernel's
// own storage class stand.
#define __device__
#define __restrict__
// CUDA-only math intrinsics that C99 math.h lacks — a kernel using
// them must run identically on this backend.
static inline float rsqrtf(float x) { return 1.0f/sqrtf(x); }
static inline double rsqrt(double x) { return 1.0/sqrt(x); }
// Explicit round-to-nearest arithmetic (the bit-exactness discipline:
// kernels spell accumulation chains with these so NVRTC cannot fmad-fuse
// them). On the host one IEEE double op IS round-to-nearest, and the
// backend compiles with -ffp-contract=off, so plain expressions cannot
// be re-fused here either.
static inline double __dadd_rn(double a, double b) { return a + b; }
static inline double __dsub_rn(double a, double b) { return a - b; }
static inline double __dmul_rn(double a, double b) { return a * b; }
static inline double __ddiv_rn(double a, double b) { return a / b; }
static inline float __fadd_rn(float a, float b) { return a + b; }
static inline float __fsub_rn(float a, float b) { return a - b; }
static inline float __fmul_rn(float a, float b) { return a * b; }
static inline float __fdiv_rn(float a, float b) { return a / b; }

// ── Cooperative kernels: __shared__ and __syncthreads() ───────────
//
// A block's threads are run as FIBERS on one host thread, so:
//
//   __shared__      → storage private to the host thread, hence shared by
//                     exactly the threads of one block, and reused by the
//                     next block that host thread picks up (which is what
//                     CUDA's shared memory is: uninitialised per block).
//   __syncthreads() → the fiber yields to the scheduler, which resumes it
//                     only after every other unfinished thread of the block
//                     has run to ITS next barrier. That is the barrier.
//
// Fibers rather than host threads because the barrier has to be free —
// a block is 256 threads and a kernel crosses a barrier in an inner loop,
// so a futex per barrier per thread would cost more than the arithmetic.
// And fibers rather than nothing, because a barrier cannot be expressed at
// all in a flat "run every (block, thread) pair in one loop" launcher, which
// is what this backend used to be: it would run thread 0 to completion before
// thread 1 started, so half of a barrier's threads would already be gone by
// the time the other half arrived. Any kernel with a __syncthreads() in it
// silently computed the wrong answer. Now it computes the right one.
//
// threadIdx is re-stamped on every resume — a fiber that reads threadIdx.x
// after a barrier must see its OWN index, not the last one the scheduler set.
#include <ucontext.h>
#include <stdlib.h>
#include <string.h>
#define __shared__ static __thread
#define __NURL_STK (64*1024)
static __thread ucontext_t __nurl_sched, __nurl_tmpl;
static __thread ucontext_t* __nurl_ctx = 0;
static __thread char* __nurl_stk = 0;
static __thread unsigned char* __nurl_fin = 0;
static __thread long long* __nurl_p = 0;
static __thread int __nurl_cap = 0, __nurl_cur = 0, __nurl_ready = 0;
static inline void __syncthreads(void) {
    swapcontext(&__nurl_ctx[__nurl_cur], &__nurl_sched);
}
static void __nurl_ensure(int n) {
    if (n > __nurl_cap) {
        free(__nurl_ctx); free(__nurl_stk); free(__nurl_fin);
        __nurl_ctx = (ucontext_t*)malloc((size_t)n * sizeof(ucontext_t));
        __nurl_stk = (char*)malloc((size_t)n * __NURL_STK);
        __nurl_fin = (unsigned char*)malloc((size_t)n);
        __nurl_cap = n;
    }
    // getcontext() is a system call (it reads the signal mask). Taking one
    // template per host thread and memcpy'ing it per fiber keeps it off the
    // per-block path.
    if (!__nurl_ready) { getcontext(&__nurl_tmpl); __nurl_ready = 1; }
}
`
}

@ __cpu_ws i c → b { ^ | == c 32 | == c 9 | == c 10 == c 13 }

@ __cpu_id i c → b { ^ | | | & >= c 48 <= c 57 & >= c 65 <= c 90 & >= c 97 <= c 122 == c 95 }

// Append one CUDA kernel parameter's cast — `*(<type>*)p[idx]` — to `out`.
// `src[start..end)` is "const float* A" / "int M" / "float alpha"; the type
// is everything but the trailing identifier (the parameter name).
@ __emit_param s src i start i end String out i idx → v {
    : ~ i a start
    ~ & < a end ( __cpu_ws ( nurl_str_get src a ) ) { = a + a 1 }
    : ~ i b end
    ~ & > b a ( __cpu_ws ( nurl_str_get src - b 1 ) ) { = b - b 1 }
    ? <= b a { ^ {} } {}
    : ~ i e b
    ~ & > e a ( __cpu_id ( nurl_str_get src - e 1 ) ) { = e - e 1 }
    ~ & > e a ( __cpu_ws ( nurl_str_get src - e 1 ) ) { = e - e 1 }
    ? > idx 0 { ( string_push_str out `, ` ) } {}
    ( string_push_str out `*(` )
    : ~ i k a
    ~ < k e { ( string_push_char out ( nurl_str_get src k ) ) = k + k 1 }
    // The params array cells are ALWAYS 8 bytes (gpu_launch pokes i64
    // addresses); reading them as `void*` walks a 4-byte stride on
    // wasm32 and every argument after the first comes out garbage.
    // `p` is therefore `long long*` and each cell round-trips through
    // uintptr_t — identical codegen on 64-bit hosts, correct on wasm32.
    ( string_push_str out `*)(uintptr_t)p[` )
    ( string_push_str out ( nurl_str_int idx ) )
    ( string_push_char out 93 )  // ]
}

// Parse the kernel signature and build the comma-separated call argument list
// (`*(T0*)p[0], *(T1*)p[1], …`) from the FIRST `(...)` in `src`.
@ __parse_casts s src s name → String {
    : i n ( nurl_str_len src )
    // Locate the ENTRY kernel's own parameter list — "void <name>(" —
    // not merely the first '(' in the source. A kernel is free to
    // declare __device__ helpers above itself (nurllama's quant
    // matvecs decode f16 through one), and taking the first paren
    // would then parse the helper's parameters and emit a launch stub
    // with the wrong arity. Falls back to the first '(' when the
    // signature cannot be located, preserving the old behaviour.
    : String needle ( string_from `void ` )
    ( string_push_str needle name )
    ( string_push_char needle 40 )
    : i hit ( nurl_str_find src ( string_data needle ) )
    : i nlen ( string_len needle )
    ( string_free needle )
    : ~ i op - 0 1
    ? >= hit 0 { = op + hit - nlen 1 } {
        : ~ i i 0
        ~ & < i n < op 0 { ? == ( nurl_str_get src i ) 40 { = op i } {} = i + i 1 }
    }
    : String out ( string_new )
    ? < op 0 { ^ out } {}
    : ~ i depth 1
    : ~ i j + op 1
    : ~ i start + op 1
    : ~ i argn 0
    ~ & > depth 0 < j n {
        : i ch ( nurl_str_get src j )
        : ~ b boundary F
        ? == ch 40 { = depth + depth 1 } {}
        ? == ch 41 { = depth - depth 1 ? == depth 0 { = boundary T } {} } {}
        ? & == ch 44 == depth 1 { = boundary T } {}
        ? boundary {
            ( __emit_param src start j out argn )
            = argn + argn 1
            = start + j 1
        } {}
        = j + j 1
    }
    ^ out
}

@ __tmp_path s name s ext → String {
    : String p ( string_with_cap 64 )
    ( string_push_str p `/tmp/nurlcpu_` )
    ( string_push_str p name )
    ( string_push_str p ext )
    ^ p
}

@ __write_file s path s content → i {
    ?? ( write_file path content ) { T _ → ^ 0 F _ → ^ - 0 1 }
}

// Cache directory + key, shared with the CUDA path's policy
// (NURL_GPU_CACHE / XDG_CACHE_HOME / ~/.cache/nurl-gpu, "off" to
// disable). Defined here because cpu.nu is imported before gpu.nu.
@ __cpu_cache_off → b {
    ?? ( env_get `NURL_GPU_CACHE` ) {
        T v → {
            : b off ? ( nurl_str_eq ( string_data v ) `off` ) T F
            ( string_free v )
            ^ off
        }
        F → { ^ F }
    }
}

@ __cpu_cache_dir → String {
    ?? ( env_get `NURL_GPU_CACHE` ) {
        T v → { ^ v }
        F → {}
    }
    ?? ( env_get `XDG_CACHE_HOME` ) {
        T v → {
            : String p ( path_join ( string_data v ) `nurl-gpu` )
            ( string_free v )
            ^ p
        }
        F → {}
    }
    : String home ( env_var_or `HOME` `.` )
    : String c ( path_join ( string_data home ) `.cache` )
    : String p ( path_join ( string_data c ) `nurl-gpu` )
    ( string_free home )
    ( string_free c )
    ^ p
}

@ __cpu_cache_path s src → String {
    : String dir ( __cpu_cache_dir )
    : !v IoErr _mk ( dir_create_all ( string_data dir ) )
    : ( Vec u ) sb ( bytes_from_str src )
    : String hex ( blake3_hex sb )
    ( vec_free [u] sb )
    : String nm ( string_from `cpu-` )
    ( string_push_str nm ( string_data hex ) )
    ( string_push_str nm `.so` )
    ( string_free hex )
    : String p ( path_join ( string_data dir ) ( string_data nm ) )
    ( string_free dir )
    ( string_free nm )
    ^ p
}

// Compile CUDA-C `src` (entry `name`) to a host shared object and dlopen it.
// Returns the dlopen handle (0 on failure), analogous to cuda_module_load.
@ cpu_compile s src s name → *u {
    : String casts ( __parse_casts src name )
    : String c ( string_with_cap + 2048 ( nurl_str_len src ) )
    ( string_push_str c ( __cpu_header ) )
    ( string_push_str c src )
    // A kernel with a barrier in it needs its block's threads to be able to
    // WAIT for each other, so its block runs as fibers on one host thread. A
    // kernel without one does not, and pays nothing: the flat grid loop, one
    // OpenMP iteration per (block, thread) pair, is what every kernel in this
    // ecosystem so far has run on and it stays exactly that.
    ? >= ( nurl_str_find src `__syncthreads` ) 0 {
        ( string_push_str c `\nstatic void __nurl_entry(void){\nlong long* p = __nurl_p;\n` )
        ( string_push_str c name )
        ( string_push_char c 40 )
        ( string_push_str c ( string_data casts ) )
        ( string_push_str c `);\n__nurl_fin[__nurl_cur]=1;\n}\nextern "C" void __cpu_launch(long long* p, long long grid, long long block){\n#pragma omp parallel for schedule(static)\nfor(long long __b=0;__b<grid;__b++){\nint n=(int)block;\n__nurl_ensure(n);\n__nurl_p=p;\nblockIdx.x=(int)__b;blockIdx.y=0;blockIdx.z=0;\nblockDim.x=n;blockDim.y=1;blockDim.z=1;\ngridDim.x=(int)grid;gridDim.y=1;gridDim.z=1;\nfor(int t=0;t<n;t++){\nmemcpy(&__nurl_ctx[t],&__nurl_tmpl,sizeof(ucontext_t));\n__nurl_ctx[t].uc_stack.ss_sp=__nurl_stk+(size_t)t*__NURL_STK;\n__nurl_ctx[t].uc_stack.ss_size=__NURL_STK;\n__nurl_ctx[t].uc_link=&__nurl_sched;\nmakecontext(&__nurl_ctx[t],(void(*)(void))__nurl_entry,0);\n__nurl_fin[t]=0;\n}\nint left=n;\nwhile(left>0){\nfor(int t=0;t<n;t++){\nif(__nurl_fin[t])continue;\n__nurl_cur=t;threadIdx.x=t;threadIdx.y=0;threadIdx.z=0;\nswapcontext(&__nurl_sched,&__nurl_ctx[t]);\nif(__nurl_fin[t])left--;\n}\n}\n}\n}\n` )
    } {
        ( string_push_str c `\nextern "C" void __cpu_launch(long long* p, long long grid, long long block){\nlong long __N=grid*block;\n#pragma omp parallel for schedule(static)\nfor(long long __i=0;__i<__N;__i++){\nlong long __b=__i/block,__t=__i%block;\nblockIdx.x=(int)__b;blockIdx.y=0;blockIdx.z=0;threadIdx.x=(int)__t;threadIdx.y=0;threadIdx.z=0;blockDim.x=(int)block;blockDim.y=1;blockDim.z=1;gridDim.x=(int)grid;gridDim.y=1;gridDim.z=1;\n` )
        ( string_push_str c name )
        ( string_push_char c 40 )
        ( string_push_str c ( string_data casts ) )
        ( string_push_str c `);\n}\n}\n` )
    }
    ( string_free casts )

    // Cache key: the hash of the GENERATED source (kernel + shim +
    // launcher), so an edited kernel misses and rebuilds while a
    // repeat run just dlopens the existing object — the CPU backend's
    // c++ invocation is otherwise paid on every process start.
    : ~ b use_cache ! ( __cpu_cache_off )
    : ~ String sopath ( string_new )
    ? use_cache {
        ( string_free sopath )
        = sopath ( __cpu_cache_path ( string_data c ) )
        ? ( file_exists ( string_data sopath ) ) {
            : *u h0 ( dlopen ( string_data sopath ) 2 )
            ? != # i h0 0 {
                // Cache hit — the generated source was only needed to
                // compute the key; free it on the way out.
                ( string_free c )
                ( string_free sopath )
                ^ h0
            } {}
        } {}
    } {
        ( string_free sopath )
        = sopath ( __tmp_path name `.so` )
    }
    : String cpath ( __tmp_path name `.cc` )
    : i wr ( __write_file ( string_data cpath ) ( string_data c ) )
    ( string_free c )
    ? != 0 wr {
        ( nurl_eprint `[gpu/cpu] cannot write ` ) ( nurl_eprint ( string_data cpath ) ) ( nurl_eprint `\n` )
        ( string_free cpath )
        ( string_free sopath )
        ^ # *u 0
    } {}

    // Prefer OpenMP; fall back to a serial build if -fopenmp isn't available.
    : String base ( string_with_cap 256 )
    ( string_push_str base `${CXX:-c++} -O2 -ffp-contract=off -fPIC -shared -o ` )
    ( string_push_str base ( string_data sopath ) )
    ( string_push_char base 32 )
    ( string_push_str base ( string_data cpath ) )
    ( string_push_str base ` 2>/tmp/nurlcpu_cc.log` )
    : String omp ( string_with_cap 256 )
    ( string_push_str omp `${CXX:-c++} -O2 -ffp-contract=off -fPIC -shared -fopenmp -o ` )
    ( string_push_str omp ( string_data sopath ) )
    ( string_push_char omp 32 )
    ( string_push_str omp ( string_data cpath ) )
    ( string_push_str omp ` 2>/tmp/nurlcpu_cc.log` )
    : ~ i rc ( system ( string_data omp ) )
    ? != rc 0 { = rc ( system ( string_data base ) ) } {}
    ( string_free omp )
    ( string_free base )
    ( string_free cpath )
    ? != rc 0 {
        ( nurl_eprint `[gpu/cpu] host compile failed for ` ) ( nurl_eprint name )
        ( nurl_eprint ` (see /tmp/nurlcpu_cc.log; need a C++ compiler on PATH)\n` )
        ( string_free sopath )
        ^ # *u 0
    } {}
    : *u handle ( dlopen ( string_data sopath ) 2 )  // RTLD_NOW
    ( string_free sopath )
    ^ handle
}

// The generated grid-loop entry point in a compiled module (0 if absent).
@ cpu_function * u handle → i { ^ # i ( dlsym handle `__cpu_launch` ) }
// Do NOT dlclose: a kernel module compiled with -fopenmp keeps libgomp worker
// threads alive; unloading it out from under them crashes libgomp at thread
// teardown. Leaving the (small) module mapped for the process lifetime is the
// standard workaround — it's freed when the process exits anyway.
@ cpu_module_free * u handle → v {}

// ── "device" memory — plain host RAM on this backend ──────────────
// Buffers are f32/i32/i64 arrays (4-byte-aligned, sizes a multiple of 4), so
// copy word-by-word — avoids declaring libc memcpy (the compiler emits its
// own memcpy for aggregate copies, and a duplicate FFI declaration collides).
@ cpu_malloc i bytes → i { ^ # i ( nurl_alloc bytes ) }

@ cpu_free i ptr → v { ( nurl_free # *u ptr ) }

@ __copy_words * u dst * u src i bytes → v {
    : i words / bytes 4
    : ~ i k 0
    ~ < k words { ( nurl_poke_i32 dst k ( nurl_peek_i32 src k ) ) = k + k 1 }
}

@ cpu_htod i dst * u host i bytes → i { ( __copy_words # *u dst host bytes ) ^ 0 }

@ cpu_dtoh * u host i src i bytes → i { ( __copy_words host # *u src bytes ) ^ 0 }

// Run a compiled kernel: `fn` is the __cpu_launch pointer, `params` the same
// void** array gpu_launch builds for CUDA. 0 == success.
@ cpu_launch i fn i params i grid i block → i {
    ( nurl_cpu_launch # *u fn # *u params grid block )
    ^ 0
}

// ── static-kernel C generation (backend 2, build-time) ──────────────
//
// Emits plain C (no C++, no dlopen, no OpenMP) for a FIXED set of
// kernels: the same CUDA-compat shim, each kernel with its `extern "C"`
// prefix stripped, a per-kernel serial grid-loop launcher, and a strong
// nurl_static_kernel(name) that overrides runtime_core.c's weak stub.
// Compile the result into any build — native or wasm32-wasi — and
// NURL_GPU=static / ( gpu_force_static ) runs models with no compiler
// or dlopen on the host at all. See packages/onnx/tools/
// gen_static_kernels.nu for the generator that feeds this.

@ cpu_static_header → s {
    ^ `/* generated by gen_static_kernels.nu — do not edit */
#include <math.h>
#include <stdint.h>
typedef struct { int x, y, z; } __nurl_dim3;
static __nurl_dim3 blockIdx, threadIdx, blockDim, gridDim;
#define __global__
// __device__ is an execution-space qualifier, NOT a storage class:
// "__device__ static inline f()" is legal CUDA, so expanding it to
// "static" would emit "static static inline" (duplicate specifier).
// It means nothing on the host — expand it away and let the kernel's
// own storage class stand.
#define __device__
#define __restrict__
static inline double __dadd_rn(double a, double b) { return a + b; }
static inline double __dsub_rn(double a, double b) { return a - b; }
static inline double __dmul_rn(double a, double b) { return a * b; }
static inline double __ddiv_rn(double a, double b) { return a / b; }
static inline float __fadd_rn(float a, float b) { return a + b; }
static inline float __fsub_rn(float a, float b) { return a - b; }
static inline float __fmul_rn(float a, float b) { return a * b; }
static inline float __fdiv_rn(float a, float b) { return a / b; }
`
}

// One kernel: its source (C++-only \`extern "C"\` stripped) plus the
// serial launcher `__nurl_sl_<entry>(void** p, long long grid, long
// long block)` mirroring cpu_compile's generated __cpu_launch.
@ cpu_static_unit s ename s src → String {
    : String srcs ( string_from src )
    : String cleaned ( string_replace srcs `extern "C" ` `` )
    ( string_free srcs )
    : String casts ( __parse_casts src ename )
    : String out ( string_with_cap + 1024 ( string_len cleaned ) )
    ( string_push_str out ( string_data cleaned ) )
    ( string_push_str out `\nstatic void __nurl_sl_` )
    ( string_push_str out ename )
    ( string_push_str out `(long long* p, long long grid, long long block){\nlong long __N=grid*block;\nfor(long long __i=0;__i<__N;__i++){\nlong long __b=__i/block,__t=__i%block;\nblockIdx.x=(int)__b;blockIdx.y=0;blockIdx.z=0;threadIdx.x=(int)__t;threadIdx.y=0;threadIdx.z=0;blockDim.x=(int)block;blockDim.y=1;blockDim.z=1;gridDim.x=(int)grid;gridDim.y=1;gridDim.z=1;\n` )
    ( string_push_str out ename )
    ( string_push_char out 40 )
    ( string_push_str out ( string_data casts ) )
    ( string_push_str out `);\n}\n}\n` )
    ( string_free casts )
    ( string_free cleaned )
    ^ out
}

// The registry: a name→launcher table + the strong nurl_static_kernel.
@ cpu_static_registry ( Vec String ) entries → String {
    : String out ( string_with_cap 2048 )
    ( string_push_str out `\ntypedef struct { const char* name; void (*fn)(long long*, long long, long long); } __NurlStaticK;\nstatic const __NurlStaticK __nurl_static_tab[] = {\n` )
    : i n ( vec_len [String] entries )
    : ~ i k 0
    ~ < k n {
        : s e ?? ( vec_get [String] entries k ) { T x → ( string_data x ) F _ → `` }
        ( string_push_str out `  { "` )
        ( string_push_str out e )
        ( string_push_str out `", __nurl_sl_` )
        ( string_push_str out e )
        ( string_push_str out ` },\n` )
        = k + k 1
    }
    ( string_push_str out `};\nvoid* nurl_static_kernel(const char* name) {\n  unsigned n = sizeof(__nurl_static_tab)/sizeof(__nurl_static_tab[0]);\n  for (unsigned i = 0; i < n; i++) {\n    const char* a = __nurl_static_tab[i].name; const char* b = name;\n    while (*a && *a == *b) { a++; b++; }\n    if (*a == 0 && *b == 0) return (void*)__nurl_static_tab[i].fn;\n  }\n  return 0;\n}\n` )
    ^ out
}
