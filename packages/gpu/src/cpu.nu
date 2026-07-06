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
$ `stdlib/std/fs.nu`

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
#define __device__ static
#define __restrict__
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
@ __parse_casts s src → String {
    : i n ( nurl_str_len src )
    : ~ i op - 0 1
    : ~ i i 0
    ~ & < i n < op 0 { ? == ( nurl_str_get src i ) 40 { = op i } {} = i + i 1 }
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

// Compile CUDA-C `src` (entry `name`) to a host shared object and dlopen it.
// Returns the dlopen handle (0 on failure), analogous to cuda_module_load.
@ cpu_compile s src s name → *u {
    : String casts ( __parse_casts src )
    : String c ( string_with_cap + 2048 ( nurl_str_len src ) )
    ( string_push_str c ( __cpu_header ) )
    ( string_push_str c src )
    ( string_push_str c `\nextern "C" void __cpu_launch(long long* p, long long grid, long long block){\nlong long __N=grid*block;\n#pragma omp parallel for schedule(static)\nfor(long long __i=0;__i<__N;__i++){\nlong long __b=__i/block,__t=__i%block;\nblockIdx.x=(int)__b;blockIdx.y=0;blockIdx.z=0;threadIdx.x=(int)__t;threadIdx.y=0;threadIdx.z=0;blockDim.x=(int)block;blockDim.y=1;blockDim.z=1;gridDim.x=(int)grid;gridDim.y=1;gridDim.z=1;\n` )
    ( string_push_str c name )
    ( string_push_char c 40 )
    ( string_push_str c ( string_data casts ) )
    ( string_push_str c `);\n}\n}\n` )
    ( string_free casts )

    : String cpath ( __tmp_path name `.cc` )
    : String sopath ( __tmp_path name `.so` )
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
    ( string_push_str base `${CXX:-c++} -O2 -fPIC -shared -o ` )
    ( string_push_str base ( string_data sopath ) )
    ( string_push_char base 32 )
    ( string_push_str base ( string_data cpath ) )
    ( string_push_str base ` 2>/tmp/nurlcpu_cc.log` )
    : String omp ( string_with_cap 256 )
    ( string_push_str omp `${CXX:-c++} -O2 -fPIC -shared -fopenmp -o ` )
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
#define __device__ static
#define __restrict__
`
}

// One kernel: its source (C++-only \`extern "C"\` stripped) plus the
// serial launcher `__nurl_sl_<entry>(void** p, long long grid, long
// long block)` mirroring cpu_compile's generated __cpu_launch.
@ cpu_static_unit s ename s src → String {
    : String srcs ( string_from src )
    : String cleaned ( string_replace srcs `extern "C" ` `` )
    ( string_free srcs )
    : String casts ( __parse_casts src )
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
