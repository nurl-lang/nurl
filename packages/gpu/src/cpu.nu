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
// the CPU analogue of NVRTC: $CXX, else `c++` (POSIX) or `clang++`
// (Windows, where the object is a DLL that exports __cpu_launch and the
// libomp.dll beside clang runs its OpenMP).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/hash.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/sysinfo.nu`

// The C ABI's `int`s are i32: on x86-64 an i64 in their place happens to
// work, but a wasm32 module that declares dlopen(…, i64) is INVALID — the
// call's operand type must match wasi-libc's signature, so every wasm
// build that linked this file failed to compile in the browser.
& `c` @ dlopen s path i32 flags → *u

& `c` @ dlsym *u handle s name → *u

& `c` @ dlclose *u handle → i32

& `c` @ system s cmd → i32

& `c` @ nurl_peek_i32 in *u base i idx → i32

& `c` @ nurl_poke_i32 *u base i idx i32 val → v

& `c` @ nurl_cpu_launch *u fn *u params i grid i block → v

// The float transcendentals every kernel calls, the same bits on every
// host (agora #548): pushed after the shim and before the kernels, in the
// JIT backend (with __cpu_detmath_cxx) and the static one.
@ cpu_detmath → s {
    ^ `// ── Deterministic float transcendentals (agora #548) ───────────────
// A kernel's expf / logf / powf / sinf / cosf / tanhf / erff / log1pf
// come from here, not the host libm: glibc, UCRT and macOS's libm round
// them differently, so the same kernel gave other bits on another OS.
// Each is computed in double with IEEE + - * / only (no fma: the backend
// builds with -ffp-contract=off, and no libm call), to a relative error
// near 1e-16, and rounded once to float: the same bits on every host, and
// the correctly rounded float in all but the rarest midpoint cases.
#include <stdint.h>
#include <string.h>
static inline uint64_t __nm_bits(double d) { uint64_t u; memcpy(&u, &d, 8); return u; }
static inline double __nm_from(uint64_t u) { double d; memcpy(&d, &u, 8); return d; }
static inline uint32_t __nm_fbits(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }
static inline float __nm_ffrom(uint32_t u) { float f; memcpy(&f, &u, 4); return f; }
// 2^k for k in [-1022, 1023], exact.
static inline double __nm_pow2(int k) { return __nm_from((uint64_t)(k + 1023) << 52); }
// Nearest integer of |t| < 2^51 (ties to even), by the 1.5*2^52 shift.
static inline double __nm_rint(double t) { const double s = 0x1.8p52; return (t + s) - s; }

// e^x for |x| <= 104 (k = round(x/ln2) fits [-151, 151]).
static inline double __nm_exp(double x) {
    const double ln2hi = 0x1.62e42fee00000p-1, ln2lo = 0x1.a39ef35793c76p-33;
    double kd = __nm_rint(x * 0x1.71547652b82fep0);
    double r = (x - kd * ln2hi) - kd * ln2lo;
    double p = 0x1.6124613a86d09p-33;
    p = p * r + 0x1.1eed8eff8d898p-29;
    p = p * r + 0x1.ae64567f544e4p-26;
    p = p * r + 0x1.27e4fb7789f5cp-22;
    p = p * r + 0x1.71de3a556c734p-19;
    p = p * r + 0x1.a01a01a01a01ap-16;
    p = p * r + 0x1.a01a01a01a01ap-13;
    p = p * r + 0x1.6c16c16c16c17p-10;
    p = p * r + 0x1.1111111111111p-7;
    p = p * r + 0x1.5555555555555p-5;
    p = p * r + 0x1.5555555555555p-3;
    p = p * r + 0.5;
    p = p * r + 1.0;
    p = p * r + 1.0;
    return p * __nm_pow2((int)kd);
}
// e^t - 1, accurate near 0, for |t| <= 104.
static inline double __nm_expm1(double t) {
    if (t > 0.34 || t < -0.34) return __nm_exp(t) - 1.0;
    // t + t^2 (1/2! + t/3! + ... + t^15/17!): |t| <= 0.34 leaves 1e-24.
    double p = 0x1.952c77030ad4ap-49;
    p = p * t + 0x1.ae7f3e733b81fp-45;
    p = p * t + 0x1.ae7f3e733b81fp-41;
    p = p * t + 0x1.93974a8c07c9dp-37;
    p = p * t + 0x1.6124613a86d09p-33;
    p = p * t + 0x1.1eed8eff8d898p-29;
    p = p * t + 0x1.ae64567f544e4p-26;
    p = p * t + 0x1.27e4fb7789f5cp-22;
    p = p * t + 0x1.71de3a556c734p-19;
    p = p * t + 0x1.a01a01a01a01ap-16;
    p = p * t + 0x1.a01a01a01a01ap-13;
    p = p * t + 0x1.6c16c16c16c17p-10;
    p = p * t + 0x1.1111111111111p-7;
    p = p * t + 0x1.5555555555555p-5;
    p = p * t + 0x1.5555555555555p-3;
    p = p * t + 0.5;
    return t + (t * t) * p;
}
// log(x) for a positive, finite, normal double x.
static inline double __nm_log(double x) {
    uint64_t u = __nm_bits(x);
    int e = (int)(u >> 52) - 1023;
    double m = __nm_from((u & 0x000fffffffffffffULL) | 0x3ff0000000000000ULL);
    if (m > 0x1.6a09e667f3bcdp0) { m = m * 0.5; e = e + 1; }
    double f = m - 1.0;
    double s = f / (2.0 + f);
    double z = s * s;
    double p = 1.0 / 25.0;
    p = p * z + 1.0 / 23.0;
    p = p * z + 1.0 / 21.0;
    p = p * z + 1.0 / 19.0;
    p = p * z + 1.0 / 17.0;
    p = p * z + 1.0 / 15.0;
    p = p * z + 1.0 / 13.0;
    p = p * z + 1.0 / 11.0;
    p = p * z + 1.0 / 9.0;
    p = p * z + 1.0 / 7.0;
    p = p * z + 1.0 / 5.0;
    p = p * z + 1.0 / 3.0;
    // log m = 2 atanh s = 2 s (1 + z/3 + z^2/5 + ...), f - s f = 2 s.
    double lm = (s + s) + (s + s) * (z * p);
    return (double)e * 0x1.62e42fefa39efp-1 + lm;
}

static inline float __nurl_expf(float x) {
    if (x != x) return x;
    if (x > 0x1.62e42ep6f) return __nm_ffrom(0x7f800000u);
    if (x < -0x1.9fe368p6f) return 0.0f;
    return (float)__nm_exp((double)x);
}
static inline float __nurl_logf(float x) {
    if (x != x) return x;
    if (x < 0.0f) return __nm_ffrom(0x7fc00000u);
    if (x == 0.0f) return -__nm_ffrom(0x7f800000u);
    if (x == __nm_ffrom(0x7f800000u)) return x;
    return (float)__nm_log((double)x);
}
static inline float __nurl_log1pf(float x) {
    if (x != x) return x;
    if (x < -1.0f) return __nm_ffrom(0x7fc00000u);
    if (x == -1.0f) return -__nm_ffrom(0x7f800000u);
    if (x == __nm_ffrom(0x7f800000u)) return x;
    double d = (double)x;
    // 1 + x is exact in double for |x| >= 2^-29; below, log1p x = x - x^2/2.
    if (d < 0x1p-29 && d > -0x1p-29) return (float)(d - d * d * 0.5);
    return (float)__nm_log(1.0 + d);
}
static inline float __nurl_tanhf(float x) {
    if (x != x) return x;
    if (x > 10.0f) return 1.0f;
    if (x < -10.0f) return -1.0f;
    double d = (double)x;
    double e = __nm_expm1(d + d);
    return (float)(e / (e + 2.0));
}
static inline float __nurl_erff(float x) {
    if (x != x) return x;
    if (x >= 4.0f) return 1.0f;
    if (x <= -4.0f) return -1.0f;
    // erf x = 2/sqrt(pi) sum (-1)^n x^(2n+1) / (n! (2n+1)): the largest
    // term below |x| = 4 is ~1e5, so the sum keeps ~1e-11 absolute.
    double d = (double)x, z = d * d, term = d, sum = d;
    for (int n = 1; n < 80; n++) {
        term = -term * z / (double)n;
        double add = term / (double)(2 * n + 1);
        sum = sum + add;
        if (add < 1e-19 && add > -1e-19) break;
    }
    return (float)(sum * 0x1.20dd750429b6dp0);
}

// 64 bits of 2/pi from bit index k0 on (bit k weighs 2^-k; k <= 0 is 0),
// out of its 24-bit chunks.
static inline uint64_t __nm_2opi64(int k0) {
    static const uint32_t c[] = {
        0xA2F983, 0x6E4E44, 0x1529FC, 0x2757D1, 0xF534DD, 0xC0DB62,
        0x95993C, 0x439041, 0xFE5163, 0xABDEBB, 0xC561B7, 0x246E3A,
        0x424DD2, 0xE00649, 0x2EEA09, 0xD1921C };
    int b = k0 - 1;
    int ci = b >= 0 ? b / 24 : -((-b + 23) / 24);
    int off = b - 24 * ci;
    uint64_t w[4];
    for (int j = 0; j < 4; j++) { int i = ci + j; w[j] = i >= 0 ? c[i] : 0u; }
    // The 96 bits w0 w1 w2 w3 as hi (bits 95..32) and lo (31..0); the 64
    // wanted start off bits below the top: the window shifted right by
    // 32 - off.
    uint64_t hi = (w[0] << 40) | (w[1] << 16) | (w[2] >> 8);
    uint64_t lo = ((w[2] & 0xff) << 24) | w[3];
    int s = 32 - off;
    return (hi << (32 - s)) | (lo >> s);
}
// x reduced by pi/2: r in [-pi/4, pi/4] and the quadrant q (mod 4), for a
// finite float x.
static inline double __nm_rem_pio2f(float x, int* q) {
    uint32_t u = __nm_fbits(x) & 0x7fffffffu;
    // |x| < 2^19: Cody-Waite in three parts. k pio2_1 and k pio2_2 are
    // exact (k < 2^19, the parts have 33 and 32 bits), and so are the two
    // subtractions (their bits span under 53); only k pio2_2t rounds.
    if (u < 0x49000000u) {
        double xd = (double)x;
        double kd = __nm_rint(xd * 0x1.45f306dc9c883p-1);
        double r = ((xd - kd * 0x1.921fb54400000p0) - kd * 0x1.0b4611a600000p-34) - kd * 0x1.3198a2e037073p-69;
        *q = (int)kd & 3;
        return r;
    }
    // Larger: Payne-Hanek with integers. x = M 2^E, and x 2/pi mod 4 is M
    // times the bits of 2/pi from 2^-(E-1) on, mod 4 (the bits above make a
    // multiple of 4, and M times one stays one); 128 of them are kept.
    uint64_t M = (uint64_t)((u & 0x7fffff) | 0x800000);
    int E = (int)(u >> 23) - 150;
    uint64_t t1 = __nm_2opi64(E - 1), t0 = __nm_2opi64(E + 63);
    // V = (t1, t0) M mod 2^128, a Q2.126 fixed-point number, by 32-bit limbs.
    uint64_t p0 = (t0 & 0xffffffffu) * M, p1 = (t0 >> 32) * M;
    uint64_t v0 = p0 + (p1 << 32);
    uint64_t carry = (p1 >> 32) + (v0 < p0 ? 1 : 0);
    uint64_t v1 = t1 * M + carry;
    int qq = (int)(v1 >> 62);
    // The fraction, Q0.128, read signed: f - 1 when f >= 1/2, the nearest
    // quadrant being the next one then.
    uint64_t fh = (v1 << 2) | (v0 >> 62), fl = v0 << 2;
    int neg = (int)(fh >> 63);
    if (neg) { qq = qq + 1; fl = ~fl + 1; fh = ~fh + (fl == 0 ? 1 : 0); }
    // (To double: its top 64 bits, rounded once. All 128 go in, so r keeps
    // its precision near a multiple of pi/2.)
    double m;
    if (fh) {
        int lz = __builtin_clzll(fh);
        uint64_t top = lz ? ((fh << lz) | (fl >> (64 - lz))) : fh;
        m = (double)top * __nm_pow2(-64 - lz);
    } else m = (double)fl * 0x1p-128;
    double r = (neg ? -m : m) * 0x1.921fb54442d18p0;
    if (__nm_fbits(x) >> 31) { r = -r; qq = -qq; }
    *q = qq & 3;
    return r;
}
static inline double __nm_sin_k(double r) {
    double z = r * r, p;
    // (Taylor, r^15/15! down; |r| <= pi/4 leaves r^17/17! ~ 5e-17 r.)
    p = -0x1.ae7f3e733b81fp-41;            // -1/15!
    p = p * z + 0x1.6124613a86d09p-33;     //  1/13!
    p = p * z - 0x1.ae64567f544e4p-26;     // -1/11!
    p = p * z + 0x1.71de3a556c734p-19;     //  1/9!
    p = p * z - 0x1.a01a01a01a01ap-13;     // -1/7!
    p = p * z + 0x1.1111111111111p-7;      //  1/5!
    p = p * z - 0x1.5555555555555p-3;      // -1/3!
    return r + r * (z * p);
}
static inline double __nm_cos_k(double r) {
    double z = r * r;
    double p = 0x1.ae7f3e733b81fp-45;      //  1/16!
    p = p * z - 0x1.93974a8c07c9dp-37;     // -1/14!
    p = p * z + 0x1.1eed8eff8d898p-29;     //  1/12!
    p = p * z - 0x1.27e4fb7789f5cp-22;     // -1/10!
    p = p * z + 0x1.a01a01a01a01ap-16;     //  1/8!
    p = p * z - 0x1.6c16c16c16c17p-10;     // -1/6!
    p = p * z + 0x1.5555555555555p-5;      //  1/4!
    p = p * z - 0.5;
    return 1.0 + z * p;
}
static inline float __nurl_sinf(float x) {
    if (x != x) return x;
    uint32_t a = __nm_fbits(x) & 0x7fffffffu;
    if (a >= 0x7f800000u) return __nm_ffrom(0x7fc00000u);
    if (a <= 0x3f490fdau) return (float)__nm_sin_k((double)x);
    int q; double r = __nm_rem_pio2f(x, &q);
    double v = (q & 1) ? __nm_cos_k(r) : __nm_sin_k(r);
    return (float)((q & 2) ? -v : v);
}
static inline float __nurl_cosf(float x) {
    if (x != x) return x;
    uint32_t a = __nm_fbits(x) & 0x7fffffffu;
    if (a >= 0x7f800000u) return __nm_ffrom(0x7fc00000u);
    if (a <= 0x3f490fdau) return (float)__nm_cos_k((double)x);
    int q; double r = __nm_rem_pio2f(x, &q);
    double v = (q & 1) ? __nm_sin_k(r) : __nm_cos_k(r);
    return (float)(((q + 1) & 2) ? -v : v);
}
// Is the float y an integer, and an odd one?
static inline int __nm_fint(float y) {
    uint32_t a = __nm_fbits(y) & 0x7fffffffu;
    int ex = (int)(a >> 23) - 127;
    if (ex >= 24) return 2;                       // even integer
    if (ex < 0) return a == 0 ? 2 : 0;
    uint32_t frac = (a & 0x7fffff) | 0x800000;
    int sh = 23 - ex;
    if (frac & ((1u << sh) - 1)) return 0;        // not an integer
    return ((frac >> sh) & 1) ? 1 : 2;            // 1 odd, 2 even
}
static inline float __nurl_powf(float x, float y) {
    const float inf = __nm_ffrom(0x7f800000u);
    if (y == 0.0f || x == 1.0f) return 1.0f;
    if (x != x || y != y) return __nm_ffrom(0x7fc00000u);
    int yi = __nm_fint(y);
    float ax = x < 0.0f ? -x : x;
    if (y == inf || y == -inf) {
        if (ax == 1.0f) return 1.0f;
        return ((ax > 1.0f) == (y > 0.0f)) ? inf : 0.0f;
    }
    int neg = (x < 0.0f || (x == 0.0f && (__nm_fbits(x) >> 31))) && yi == 1;
    if (x == 0.0f) { float v = y < 0.0f ? inf : 0.0f; return neg ? -v : v; }
    if (ax == inf) { float v = y < 0.0f ? 0.0f : inf; return neg ? -v : v; }
    if (x < 0.0f && yi == 0) return __nm_ffrom(0x7fc00000u);
    double t = (double)y * __nm_log((double)ax);
    float v;
    if (t > 89.0) v = inf;
    else if (t < -104.0) v = 0.0f;
    else v = (float)__nm_exp(t);
    return neg ? -v : v;
}
// A kernel's call of one of them is this one's.
#define expf(x) __nurl_expf(x)
#define logf(x) __nurl_logf(x)
#define log1pf(x) __nurl_log1pf(x)
#define tanhf(x) __nurl_tanhf(x)
#define erff(x) __nurl_erff(x)
#define sinf(x) __nurl_sinf(x)
#define cosf(x) __nurl_cosf(x)
#define powf(x, y) __nurl_powf(x, y)
`
}

@ __cpu_detmath_cxx → s {
    ^ `// C++ (the JIT backend): exp, log, … of a float are the float functions,
// as in CUDA; of anything else, the double ones as before.
#define __NURL_DM1(N) static inline float __nurl_##N(float x) { return __nurl_##N##f(x); } template <class T> static inline double __nurl_##N(T x) { return (N)((double)x); }
__NURL_DM1(exp)
__NURL_DM1(log)
__NURL_DM1(log1p)
__NURL_DM1(tanh)
__NURL_DM1(erf)
__NURL_DM1(sin)
__NURL_DM1(cos)
static inline float __nurl_pow(float x, float y) { return __nurl_powf(x, y); }
template <class A, class B> static inline double __nurl_pow(A x, B y) { return (pow)((double)x, (double)y); }
#define exp(x) __nurl_exp(x)
#define log(x) __nurl_log(x)
#define log1p(x) __nurl_log1p(x)
#define tanh(x) __nurl_tanh(x)
#define erf(x) __nurl_erf(x)
#define sin(x) __nurl_sin(x)
#define cos(x) __nurl_cos(x)
#define pow(x, y) __nurl_pow(x, y)
`
}

// ── CUDA-C → host source generation ───────────────────────────────
@ __cpu_header → s {
    ^ `#include <math.h>
#include <stdint.h>
typedef struct { int x, y, z; } __nurl_dim3;
static __thread __nurl_dim3 blockIdx, threadIdx, blockDim, gridDim;
// A kernel is inlined into the launch loop: the coordinates the loop has
// just stored are then read back from registers, not thread-local storage,
// and the arguments the loop holds need no call per element.
#define __global__ __attribute__((always_inline)) inline
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
#include <stdlib.h>
#include <string.h>
#define __shared__ static __thread
#define __NURL_STK (64*1024)
static __thread long long* __nurl_p = 0;
static __thread void (*__nurl_fn)(void) = 0;
static __thread unsigned char* __nurl_fin = 0;
static __thread int __nurl_cap = 0, __nurl_cur = 0;
// __nurl_run_block(n, fn): run fn as the n threads of the current block,
// each to its end, switching at every __syncthreads(). POSIX switches with
// ucontext; Windows, which has none, with its own fibers: one per thread
// slot, made once per host thread and reused by every block it runs.
#ifdef _WIN32
#define __NURL_EXPORT extern "C" __declspec(dllexport)
extern "C" {
__declspec(dllimport) void* __stdcall ConvertThreadToFiber(void*);
__declspec(dllimport) void* __stdcall CreateFiber(size_t, void (__stdcall*)(void*), void*);
__declspec(dllimport) void __stdcall SwitchToFiber(void*);
__declspec(dllimport) int __stdcall IsThreadAFiber(void);
}
#include <intrin.h>
// The running fiber: winnt.h's GetCurrentFiber, the TEB's FiberData. Every
// kernel is a DLL of its own with its own __nurl_sched, so the host thread
// is often a fiber already — another kernel's DLL converted it.
static inline void* __nurl_this_fiber(void) {
#if defined(_M_ARM64) || defined(__aarch64__)
    return (void*)__readx18qword(0x20);
#else
    return (void*)__readgsqword(0x20);
#endif
}
static __thread void* __nurl_sched = 0;
static __thread void** __nurl_ctx = 0;
static inline void __syncthreads(void) { SwitchToFiber(__nurl_sched); }
static void __stdcall __nurl_fiber(void* arg) {
    (void)arg;
    for (;;) {
        __nurl_fn();
        __nurl_fin[__nurl_cur] = 1;
        SwitchToFiber(__nurl_sched);
    }
}
static void __nurl_ensure(int n) {
    if (!__nurl_sched) {
        __nurl_sched = IsThreadAFiber() ? __nurl_this_fiber() : ConvertThreadToFiber(0);
        if (!__nurl_sched) abort();
    }
    if (n > __nurl_cap) {
        void** c = (void**)realloc(__nurl_ctx, (size_t)n * sizeof(void*));
        unsigned char* f = (unsigned char*)realloc(__nurl_fin, (size_t)n);
        if (!c || !f) abort();
        __nurl_ctx = c; __nurl_fin = f;
        for (int t = __nurl_cap; t < n; t++) {
            __nurl_ctx[t] = CreateFiber(__NURL_STK, __nurl_fiber, 0);
            if (!__nurl_ctx[t]) abort();
        }
        __nurl_cap = n;
    }
}
static inline void __nurl_arm(int t) { (void)t; }
static inline void __nurl_start(int t) { SwitchToFiber(__nurl_ctx[t]); }
#else
#define __NURL_EXPORT extern "C"
#include <ucontext.h>
static __thread ucontext_t __nurl_sched, __nurl_tmpl;
static __thread ucontext_t* __nurl_ctx = 0;
static __thread char* __nurl_stk = 0;
static __thread int __nurl_ready = 0;
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
static void __nurl_tramp(void) { __nurl_fn(); __nurl_fin[__nurl_cur] = 1; }
static inline void __nurl_arm(int t) {
    memcpy(&__nurl_ctx[t], &__nurl_tmpl, sizeof(ucontext_t));
    __nurl_ctx[t].uc_stack.ss_sp = __nurl_stk + (size_t)t * __NURL_STK;
    __nurl_ctx[t].uc_stack.ss_size = __NURL_STK;
    __nurl_ctx[t].uc_link = &__nurl_sched;
    makecontext(&__nurl_ctx[t], (void(*)(void))__nurl_tramp, 0);
}
static inline void __nurl_start(int t) { swapcontext(&__nurl_sched, &__nurl_ctx[t]); }
#endif
static void __nurl_run_block(int n, void (*fn)(void)) {
    __nurl_ensure(n);
    __nurl_fn = fn;
    for (int t = 0; t < n; t++) { __nurl_arm(t); __nurl_fin[t] = 0; }
    int left = n;
    while (left > 0) {
        for (int t = 0; t < n; t++) {
            if (__nurl_fin[t]) continue;
            __nurl_cur = t; threadIdx.x = t; threadIdx.y = 0; threadIdx.z = 0;
            __nurl_start(t);
            if (__nurl_fin[t]) left--;
        }
    }
}
`
}

@ __cpu_ws i c → b { ^ | == c 32 | == c 9 | == c 10 == c 13 }

@ __cpu_id i c → b { ^ | | | & >= c 48 <= c 57 & >= c 65 <= c 90 & >= c 97 <= c 122 == c 95 }

// Append one CUDA kernel parameter's cast — `*(<type>*)p[idx]` — to `out`.
// `src[start..end)` is "const float* A" / "int M" / "float alpha"; the type
// is everything but the trailing identifier (the parameter name).
@ __emit_param s src i start i end String out i idx → v {
    : ( Slice u ) src_v ( slice_of_str src )
    : ~ i a start
    ~ & < a end ( __cpu_ws ( slice_byte src_v a ) ) { = a + a 1 }
    : ~ i b end
    ~ & > b a ( __cpu_ws ( slice_byte src_v - b 1 ) ) { = b - b 1 }
    ? <= b a { ^ {} } {}
    : ~ i e b
    ~ & > e a ( __cpu_id ( slice_byte src_v - e 1 ) ) { = e - e 1 }
    ~ & > e a ( __cpu_ws ( slice_byte src_v - e 1 ) ) { = e - e 1 }
    ? > idx 0 { ( string_push_str out `, ` ) } {}
    ( string_push_str out `*(` )
    : ~ i k a
    ~ < k e { ( string_push_char out ( slice_byte src_v k ) ) = k + k 1 }
    // The params array cells are ALWAYS 8 bytes (gpu_launch pokes i64
    // addresses); reading them as `void*` walks a 4-byte stride on
    // wasm32 and every argument after the first comes out garbage.
    // `p` is therefore `long long*` and each cell round-trips through
    // uintptr_t — identical codegen on 64-bit hosts, correct on wasm32.
    ( string_push_str out `*)(uintptr_t)p[` )
    ( string_push_str out ( nurl_str_int idx ) )
    ( string_push_char out 93 )  // ]
}

// `auto __aK = <cast K>;` into `c` for each argument cast of `casts` (as
// __parse_casts builds them), and the call's argument list over them.
@ __cpu_hoist_args s casts String c → String {
    : ( Slice u ) v ( slice_of_str casts )
    : i n ( slice_len [u] v )
    : ~ String args ( string_new )
    ? == n 0 { ^ args } {}
    : ~ i k 0
    : ~ i s0 0
    : ~ i idx 0
    ~ <= k n {
        // items are separated by ", *(" — a cast's own text has no ", *("
        : b cut | == k n & & & < + k 3 n == ( slice_byte v k ) 44 == ( slice_byte v + k 1 ) 32 & == ( slice_byte v + k 2 ) 42 == ( slice_byte v + k 3 ) 40
        ? cut {
            ( string_push_str c `auto __a` ) ( string_push_int c idx ) ( string_push_str c ` = ` )
            ( string_push_window c v s0 - k s0 )
            ( string_push_str c `;\n` )
            ? > idx 0 { ( string_push_str args `, ` ) } {}
            ( string_push_str args `__a` ) ( string_push_int args idx )
            = idx + idx 1
            = s0 + k 2
            = k + k 2
        } { = k + k 1 }
    }
    ^ args
}

// Parse the kernel signature and build the comma-separated call argument list
// (`*(T0*)p[0], *(T1*)p[1], …`) from the FIRST `(...)` in `src`.
@ __parse_casts s src s name → String {
    : ( Slice u ) src_v ( slice_of_str src )
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
    : ~ i op - 0 1
    ? >= hit 0 { = op + hit - nlen 1 } {
        : ~ i i 0
        ~ & < i n < op 0 { ? == ( slice_byte src_v i ) 40 { = op i } {} = i + i 1 }
    }
    : String out ( string_new )
    ? < op 0 { ^ out } {}
    : ~ i depth 1
    : ~ i j + op 1
    : ~ i start + op 1
    : ~ i argn 0
    ~ & > depth 0 < j n {
        : i ch ( slice_byte src_v j )
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
            ^ p
        }
        F → {}
    }
    ? == ( sys_os ) SYS_OS_WINDOWS {
        ?? ( env_get `LOCALAPPDATA` ) {
            T v → {
                : String p ( path_join ( string_data v ) `nurl-gpu` )
                ^ p
            }
            F → {}
        }
    } {}
    : String home ( env_var_or `HOME` `.` )
    : String c ( path_join ( string_data home ) `.cache` )
    : String p ( path_join ( string_data c ) `nurl-gpu` )
    ^ p
}

// Compiler flags, best first. `cpu_compile` walks this list and keeps the
// first set that builds, so a toolchain missing -march=native or OpenMP
// degrades instead of failing.
@ __cpu_cc_flags i n → s {
    ? == n 0 { ^ `-O3 -march=native -fopenmp` } {}
    ? == n 1 { ^ `-O3 -fopenmp` } {}
    ? == n 2 { ^ `-O2 -fopenmp` } {}
    ^ `-O2`
}

// A host shared object's suffix: Windows loads a DLL.
@ __cpu_so_suffix → s { ^ ? == ( sys_os ) SYS_OS_WINDOWS `.dll` `.so` }

// The host C++ compiler: $CXX (it may carry words of its own, `ccache
// g++`), else `c++` — on Windows `clang++`, which LLVM's installer puts on
// PATH beside the libomp.dll its -fopenmp links.
@ __cpu_cxx → String {
    ?? ( env_get `CXX` ) {
        T v → { ? > ( string_len v ) 0 { ^ v } {} }
        F → {}
    }
    ^ ( string_from ? == ( sys_os ) SYS_OS_WINDOWS `clang++` `c++` )
}

// `p` quoted for the host shell: cmd.exe takes "…" (a Windows path has
// no `"`), a POSIX sh '…' (a cache path has no `'`).
@ __cpu_push_quoted String cmd s p b win → v {
    : i q ? win 34 39
    ( string_push_char cmd q )
    ( string_push_str cmd p )
    ( string_push_char cmd q )
}

@ __cpu_cache_path s src → String {
    : String dir ( __cpu_cache_dir )
    : !v IoErr _mk ( dir_create_all ( string_data dir ) )
    // The flags are part of the key: an object built by an older, slower
    // flag set must not be re-dlopened after the flags change, and
    // -march=native means the object is only valid for THIS host anyway.
    : String keyed ( string_from ( __cpu_cc_flags 0 ) )
    ( string_push_char keyed 10 )
    ( string_push_str keyed src )
    : ( Vec u ) sb ( bytes_from_str ( string_data keyed ) )
    : String hex ( blake3_hex sb )
    : String nm ( string_from `cpu-` )
    ( string_push_str nm ( string_data hex ) )
    ( string_push_str nm ( __cpu_so_suffix ) )
    : String p ( path_join ( string_data dir ) ( string_data nm ) )
    ^ p
}

// Compile CUDA-C `src` (entry `name`) to a host shared object and dlopen it.
// Returns the dlopen handle (0 on failure), analogous to cuda_module_load.
raw @ cpu_compile s src s name → *u {
    : String casts ( __parse_casts src name )
    : String c ( string_with_cap + 2048 ( nurl_str_len src ) )
    ( string_push_str c ( __cpu_header ) )
    ( string_push_str c ( cpu_detmath ) )
    ( string_push_str c ( __cpu_detmath_cxx ) )
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
        ( string_push_str c `);\n}\n__NURL_EXPORT void __cpu_launch(long long* p, long long grid, long long block){\n#pragma omp parallel for schedule(static)\nfor(long long __b=0;__b<grid;__b++){\nint n=(int)block;\n__nurl_p=p;\nblockIdx.x=(int)__b;blockIdx.y=0;blockIdx.z=0;\nblockDim.x=n;blockDim.y=1;blockDim.z=1;\ngridDim.x=(int)grid;gridDim.y=1;gridDim.z=1;\n__nurl_run_block(n,__nurl_entry);\n}\n}\n` )
    } {
        // The arguments are read out of `p` once, before the loop, and the
        // coordinates that do not change are set once per host thread: per
        // element only blockIdx.x / threadIdx.x move, and (block, thread)
        // come from a collapsed loop rather than a division. A kernel with
        // many arguments (a checked kernel passes each buffer's length)
        // pays nothing per element for them.
        ( string_push_str c `\n__NURL_EXPORT void __cpu_launch(long long* p, long long grid, long long block){\n(void)p;\n` )
        : String args ( __cpu_hoist_args ( string_data casts ) c )
        ( string_push_str c `#pragma omp parallel\n{\nblockIdx.y=0;blockIdx.z=0;threadIdx.y=0;threadIdx.z=0;blockDim.x=(int)block;blockDim.y=1;blockDim.z=1;gridDim.x=(int)grid;gridDim.y=1;gridDim.z=1;\n#pragma omp for collapse(2) schedule(static)\nfor(long long __b=0;__b<grid;__b++){\nfor(long long __t=0;__t<block;__t++){\nblockIdx.x=(int)__b;threadIdx.x=(int)__t;\n` )
        ( string_push_str c name )
        ( string_push_char c 40 )
        ( string_push_str c ( string_data args ) )
        ( string_push_str c `);\n}\n}\n}\n}\n` )
    }

    // Cache key: the hash of the GENERATED source (kernel + shim +
    // launcher), so an edited kernel misses and rebuilds while a
    // repeat run just dlopens the existing object — the CPU backend's
    // c++ invocation is otherwise paid on every process start.
    : ~ b use_cache ! ( __cpu_cache_off )
    : ~ String sopath ( string_new )
    ? use_cache {
        = sopath ( __cpu_cache_path ( string_data c ) )
        ? ( file_exists ( string_data sopath ) ) {
            : *u h0 ( dlopen ( string_data sopath ) 2 )
            ? != # i h0 0 {
                // Cache hit — the generated source was only needed to
                // compute the key.
                ^ h0
            } {}
        } {}
    } {}
    // Every compile builds in a directory of its own: the source, the
    // object and the compiler's log are never a path another process (or
    // thread) compiling a same-named kernel writes too. They were shared
    // /tmp names, and two compiles could build each other's source into a
    // cache entry keyed by the wrong hash — a kernel whose arguments are
    // not the ones its caller lays out. The object reaches the cache by an
    // atomic rename (the build directory sits in the cache directory, on
    // the same filesystem), so no process dlopens a half-written one.
    : String bdir_parent ? use_cache ( __cpu_cache_dir ) ( env_temp_dir )
    : !v IoErr _mk ( dir_create_all ( string_data bdir_parent ) )
    : String bdir ?? ( fs_tempdir ( string_data bdir_parent ) `.nurlcpu-build-` ) {
        T d → d
        F _e → {
            ( nurl_eprint `[gpu/cpu] cannot make a build directory in ` ) ( nurl_eprint ( string_data bdir_parent ) ) ( nurl_eprint `\n` )
            ^ # *u 0
        }
    }
    : String cpath ( path_join ( string_data bdir ) `k.cc` )
    : String oname ( string_from `k` )
    ( string_push_str oname ( __cpu_so_suffix ) )
    : String opath ( path_join ( string_data bdir ) ( string_data oname ) )
    : String lpath ( path_join ( string_data bdir ) `cc.log` )
    : i wr ( __write_file ( string_data cpath ) ( string_data c ) )
    ? != 0 wr {
        ( nurl_eprint `[gpu/cpu] cannot write ` ) ( nurl_eprint ( string_data cpath ) ) ( nurl_eprint `\n` )
        ^ # *u 0
    } {}

    // Optimisation level matters far more here than for a GPU: this is the
    // only backend where the arithmetic actually runs on the host, and a
    // register-tiled kernel is ~5x faster at -O3 -march=native than at -O2
    // (the vector unit is unreachable without knowing the target ISA).
    // -ffp-contract=off stays in every variant — it is what keeps a host
    // kernel bit-identical to the CUDA one, which the whole ecosystem's
    // CPU-vs-GPU equality tests rest on. Candidates are tried in order and
    // the first that compiles wins, so a toolchain without -march=native
    // (or without OpenMP) still builds.
    //
    // The command line is the host shell's: system() hands it to sh on
    // POSIX and to cmd.exe on Windows, which takes no -fPIC for a DLL and
    // strips the outer pair of quotes of a line that holds several.
    : b win == ( sys_os ) SYS_OS_WINDOWS
    : String cxx ( __cpu_cxx )
    : ~ i rc -1
    : ~ i cand 0
    ~ & != rc 0 < cand 4 {
        : String cmd ( string_with_cap 256 )
        ? win { ( string_push_char cmd 34 ) } {}
        ( string_push_str cmd ( string_data cxx ) )
        ( string_push_char cmd 32 )
        ( string_push_str cmd ( __cpu_cc_flags cand ) )
        ( string_push_str cmd ? win ` -ffp-contract=off -shared -o ` ` -ffp-contract=off -fPIC -shared -o ` )
        ( __cpu_push_quoted cmd ( string_data opath ) win )
        ( string_push_char cmd 32 )
        ( __cpu_push_quoted cmd ( string_data cpath ) win )
        ( string_push_str cmd ` 2>` )
        ( __cpu_push_quoted cmd ( string_data lpath ) win )
        ? win { ( string_push_char cmd 34 ) } {}
        = rc # i ( system ( string_data cmd ) )
        = cand + cand 1
    }
    ? != rc 0 {
        // No compiler at all — sh's exit status 127, cmd.exe's 9009 — or
        // the compiler refusing this kernel, whose own words say why.
        ? ? win == rc 9009 == / rc 256 127 {
            ( nurl_eprint `[gpu/cpu] no C++ compiler on PATH (set CXX) for ` ) ( nurl_eprint name ) ( nurl_eprint `\n` )
        } {
            ( nurl_eprint `[gpu/cpu] host compile failed for ` ) ( nurl_eprint name ) ( nurl_eprint `:\n` )
            ?? ( read_file ( string_data lpath ) ) {
                T log → {
                    : i n ( string_len log )
                    ( nurl_eprint ( string_data ( string_substr log 0 ? > n 2000 2000 n ) ) )
                    ? > n 2000 { ( nurl_eprint `\n…\n` ) } {}
                }
                F _e → {}
            }
        }
        : !v IoErr _rm0 ( dir_remove_all ( string_data bdir ) )
        ^ # *u 0
    } {}
    // Into the cache, whole; without one (or should the rename fail) the
    // object is opened where it was built. Either way the build directory
    // goes: an opened object stays mapped after its file is removed.
    : ~ String lib ( string_from ( string_data opath ) )
    ? use_cache {
        ?? ( fs_rename ( string_data opath ) ( string_data sopath ) ) {
            T _ → { = lib ( string_from ( string_data sopath ) ) }
            F _e → {}
        }
    } {}
    : *u handle ( dlopen ( string_data lib ) 2 )  // RTLD_NOW
    : !v IoErr _rm ( dir_remove_all ( string_data bdir ) )
    ^ handle
}

// The generated grid-loop entry point in a compiled module (0 if absent).
unsafe @ cpu_function * u handle → i { ^ # i ( dlsym handle `__cpu_launch` ) }
// Do NOT dlclose: a kernel module compiled with -fopenmp keeps libgomp worker
// threads alive; unloading it out from under them crashes libgomp at thread
// teardown. Leaving the (small) module mapped for the process lifetime is the
// standard workaround — it's freed when the process exits anyway.
@ cpu_module_free sink * u handle → v {}

// ── "device" memory — plain host RAM on this backend ──────────────
// Buffers are f32/i32/i64 arrays (4-byte-aligned, sizes a multiple of 4), so
// copy word-by-word — avoids declaring libc memcpy (the compiler emits its
// own memcpy for aggregate copies, and a duplicate FFI declaration collides).
unsafe @ __copy_words * u dst * u src i bytes → v {
    : i words / bytes 4
    : ~ i k 0
    ~ < k words { ( nurl_poke_i32 dst k ( nurl_peek_i32 src k ) ) = k + k 1 }
}

raw @ cpu_htod i dst * u host i bytes → i { ( __copy_words # *u dst host bytes ) ^ 0 }

raw @ cpu_dtoh * u host i src i bytes → i { ( __copy_words host # *u src bytes ) ^ 0 }

// Run a compiled kernel: `fn` is the __cpu_launch pointer, `params` the same
// void** array gpu_launch builds for CUDA. 0 == success.
raw @ cpu_launch i fn i params i grid i block → i {
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
    ^ out
}

// The registry: a name→launcher table + the strong nurl_static_kernel.
// The table always carries one extra row, CPU_STATIC_SENTINEL, bound to a
// no-op: gpu_open probes for it to tell "a static set is linked" from the
// runtime's weak NULL stub without naming any real kernel — kernel names
// belong to whatever library generated the set and change with it.
: s CPU_STATIC_SENTINEL `__nurl_static_set`

@ cpu_static_registry ( Vec String ) entries → String {
    : String out ( string_with_cap 2048 )
    ( string_push_str out `\nstatic void __nurl_sl___nurl_static_set(long long* p, long long grid, long long block){(void)p;(void)grid;(void)block;}\n` )
    ( string_push_str out `\ntypedef struct { const char* name; void (*fn)(long long*, long long, long long); } __NurlStaticK;\nstatic const __NurlStaticK __nurl_static_tab[] = {\n  { "__nurl_static_set", __nurl_sl___nurl_static_set },\n` )
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
