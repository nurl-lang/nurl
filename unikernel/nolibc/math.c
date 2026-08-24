/*
 * NURL nolibc — unikernel/nolibc/math.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The libm subset NURL programs call. `stdlib/std/float.nu` declares
 * exactly nineteen entries; this file is those nineteen and nothing
 * else, on the same measured-not-guessed rule as the rest of nolibc.
 * The runtime itself needs none of them — `isnan`/`isinf` compile to
 * bit tests — so this is the second half of finding 22: nolibc covers
 * what NURL PROGRAMS call, not only what the runtime does.
 *
 * ACCURACY IS THE WHOLE POINT
 *
 * A math library that is merely plausible is the worst kind of stub:
 * every caller gets an answer, none of them can tell it is wrong, and
 * the error shows up as a slightly-off image or a failing checksum
 * months later. So the gate is a differential against glibc measured in
 * ulps (unikernel/tests/math_diff.c), the polynomial coefficients are
 * generated rather than transcribed (tools/gen_libm_tables.py, which
 * prints the fit error it achieved), and the argument reduction is the
 * exact one:
 *
 *   sin/cos/tan of a large argument are decided by the bits of 2/pi
 *   that line up with the argument's exponent. Reducing 1e300 mod pi/2
 *   in double arithmetic leaves no correct bits at all — the classic
 *   way a home-grown libm produces confident noise — so this file
 *   carries 1536 bits of 2/pi and does the Payne-Hanek reduction.
 *
 * Two things are stated rather than hidden. Correct rounding is NOT
 * claimed: these are 1-2 ulp implementations, like every other libm
 * that is not CRlibm, and the differential prints the worst ulp it
 * found per function so the number is on the record. And errno is not
 * set — NURL's float.nu never reads it, and the freestanding target has
 * no errno worth the name.
 *
 * WHAT IS EXACT
 *
 * sqrt (the hardware instruction, correctly rounded by IEEE-754),
 * fabs, floor, ceil, trunc, round and copysign are bit operations with
 * no error at all. They are not approximations and are not gated by an
 * ulp bound — the differential asserts they are bit-identical to
 * glibc's.
 */
#include "nolibc.h"
#include "math_tables.h"

typedef unsigned long long u64;
typedef unsigned __int128  u128;

/* Bit reinterpretation through a union: a memcpy here would be a real
 * call under -fno-builtin, in functions that are otherwise a dozen
 * instructions. */
union nl_dbits { double d; u64 u; };
static double nl_D(u64 u) { union nl_dbits v; v.u = u; return v.d; }
static u64    nl_B(double d) { union nl_dbits v; v.d = d; return v.u; }

#define NL_SIGN   0x8000000000000000ULL
#define NL_EXPMSK 0x7ff0000000000000ULL
#define NL_MANMSK 0x000fffffffffffffULL

static const double NL_INF_D  = 0x1.0p1023 * 2.0;   /* folded at compile time */

static double nl_inf(void)  { return nl_D(0x7ff0000000000000ULL); }
static double nl_nan(void)  { return nl_D(0x7ff8000000000000ULL); }

/* ── exact, bitwise ─────────────────────────────────────────────── */

double fabs(double x) { return nl_D(nl_B(x) & ~NL_SIGN); }

double copysign(double x, double y) {
    return nl_D((nl_B(x) & ~NL_SIGN) | (nl_B(y) & NL_SIGN));
}

/* The hardware square root is correctly rounded, so there is nothing to
 * approximate. Written as asm rather than __builtin_sqrt because
 * -fno-builtin is on for this directory and the builtin would lower to
 * a call to this very function. Every target this file is built for
 * has the instruction; one that does not would need an algorithm here,
 * not a silently different answer, so the #error says so. */
double sqrt(double x) {
    double r;
#if defined(__x86_64__)
    __asm__("sqrtsd %1, %0" : "=x"(r) : "x"(x));
#elif defined(__aarch64__)
    __asm__("fsqrt %d0, %d1" : "=w"(r) : "w"(x));
#elif defined(__riscv) && defined(__riscv_flen) && __riscv_flen >= 64
    __asm__("fsqrt.d %0, %1" : "=f"(r) : "f"(x));
#else
#  error "nolibc sqrt: no hardware square root known for this target"
#endif
    return r;
}

/* Drop the fractional bits by masking. -march=x86-64 is SSE2, so
 * `roundsd` (SSE4.1) is not available, and masking is exact and
 * independent of the current rounding mode — which `x + 2^52 - 2^52`
 * is not. */
double trunc(double x) {
    u64 b = nl_B(x);
    int e = (int)((b >> 52) & 0x7ff) - 1023;
    if (e < 0) return nl_D(b & NL_SIGN);          /* |x| < 1 → ±0 */
    if (e >= 52) return x;                        /* already integral, or inf/nan */
    return nl_D(b & ~(NL_MANMSK >> e));
}

double floor(double x) {
    double t = trunc(x);
    if (t != x && nl_B(x) & NL_SIGN) t -= 1.0;
    return t;
}

double ceil(double x) {
    double t = trunc(x);
    if (t != x && !(nl_B(x) & NL_SIGN)) t += 1.0;
    return t;
}

/* C's round(): halfway cases go away from zero, which is NOT what any
 * rounding mode does, so it is spelled out. `x - t` is exact (Sterbenz),
 * so the 0.5 test is exact too — 0.49999999999999994 must round to 0
 * and does. */
double round(double x) {
    double t = trunc(x);
    if (t != x && fabs(x - t) >= 0.5) t += copysign(1.0, x);
    return t;
}

/* rint(): round to the nearest integer, ties to EVEN — what wasm's
 * f32.nearest / f64.nearest and the FPU's default mode both mean.
 * Spelled in exact arithmetic like trunc rather than as the
 * x + 2^52 - 2^52 idiom, so the answer does not depend on the current
 * rounding mode. `x - t` is exact (Sterbenz), t*0.5 is exact (power-
 * of-two scale), so both the half test and the evenness test are
 * exact. |x| >= 2^52, inf and nan all take the d == 0 path and come
 * back unchanged. */
double rint(double x) {
    double t = trunc(x);
    double d = fabs(x - t);
    if (d > 0.5) t += copysign(1.0, x);
    else if (d == 0.5) {
        if (t != 2.0 * trunc(t * 0.5)) t += copysign(1.0, x);  /* tie, t odd → away */
    }
    if (t == 0.0) return copysign(0.0, x);   /* rint(-0.3) is -0.0 */
    return t;
}

/* The float entries the wasm interpreter's f32 ops link against —
 * directly, and via LLVM, which folds (float)floor((double)x) into a
 * floorf() call whenever inlining exposes the pattern, so the whole
 * rounding family has to exist under its f32 names. Each one goes
 * through the double path exactly: every float is exactly a double,
 * the double result is integer-valued, and every integer a float
 * rounds to is float-representable (floats at or above 2^23 already
 * are integers). sqrtf: hardware, like sqrt — the single-precision
 * instruction rounds once, which is the correct answer by
 * definition. */
float truncf(float x) { return (float)trunc(x); }
float floorf(float x) { return (float)floor(x); }
float ceilf(float x) { return (float)ceil(x); }
float rintf(float x) { return (float)rint(x); }
float nearbyintf(float x) { return (float)rint(x); }
float roundf(float x) { return (float)round(x); }
float fabsf(float x) { return (float)fabs(x); }
float copysignf(float x, float y) { return (float)copysign(x, y); }

float sqrtf(float x) {
    float r;
#if defined(__x86_64__)
    __asm__("sqrtss %1, %0" : "=x"(r) : "x"(x));
#elif defined(__aarch64__)
    __asm__("fsqrt %s0, %s1" : "=w"(r) : "w"(x));
#elif defined(__riscv) && defined(__riscv_flen) && __riscv_flen >= 32
    __asm__("fsqrt.s %0, %1" : "=f"(r) : "f"(x));
#else
#  error "nolibc sqrtf: no hardware square root known for this target"
#endif
    return r;
}

/* x * 2^n, correct through the subnormal range. Done in at most two
 * multiplications by exact powers of two, so no bits are lost that
 * gradual underflow would not lose anyway. */
static double nl_scalbn(double x, int n) {
    if (n > 1023) {
        x *= 0x1p1023;
        n -= 1023;
        if (n > 1023) {
            x *= 0x1p1023;
            n -= 1023;
            if (n > 1023) n = 1023;
        }
    } else if (n < -1022) {
        /* Two steps of -969 keep the intermediate normal. */
        x *= 0x1p-969;
        n += 969;
        if (n < -1022) {
            x *= 0x1p-969;
            n += 969;
            if (n < -1022) n = -1022;
        }
    }
    return x * nl_D(((u64)(n + 1023)) << 52);
}

/* ── double-double helpers (no FMA at -march=x86-64) ─────────────── */

static void nl_two_sum(double a, double b, double *s, double *e) {
    double t = a + b;
    double bb = t - a;
    *e = (a - (t - bb)) + (b - bb);
    *s = t;
}

/* Dekker's product. FMA would make this three instructions; the
 * baseline this target pins (-march=x86-64, SSE2 only) has none, and
 * inventing one with -mfma would #UD on the first machine without it. */
static void nl_two_prod(double a, double b, double *p, double *e) {
    const double SPLIT = 134217729.0;               /* 2^27 + 1 */
    double c = SPLIT * a, ah = c - (c - a), al = a - ah;
    double d = SPLIT * b, bh = d - (d - b), bl = b - bh;
    double q = a * b;
    *e = ((ah * bh - q) + ah * bl + al * bh) + al * bl;
    *p = q;
}

/* ── exp ────────────────────────────────────────────────────────── */


static double nl_exp_poly(double r) {
    double p = NL_EXP_P[13];
    for (int i = 12; i >= 0; i--) p = p * r + NL_EXP_P[i];
    return p;
}

/* exp(x) = 2^k * exp(r), r = x - k*ln2 with |r| <= ln2/2.
 * k*NL_LN2_HI is EXACT: the head carries 33 significant bits and |k| <= 1075
 * needs 11, so the product fits a double with room to spare. Without
 * that split the reduction would lose the low bits of x, which is the
 * only place exp's accuracy can come from. */
double exp(double x) {
    u64 b = nl_B(x), ax = b & ~NL_SIGN;
    if (ax >= 0x7ff0000000000000ULL)                 /* inf / nan */
        return (ax > 0x7ff0000000000000ULL) ? x + x : ((b & NL_SIGN) ? 0.0 : x);
    if (x > 709.782712893383973096) return NL_INF_D * NL_INF_D;
    if (x < -745.1332191019411)     return 0.0;
    if (ax < 0x3c90000000000000ULL) return 1.0 + x;  /* |x| < 2^-54 */

    double kd = x * NL_IVLN2_HI;
    int k = (int)(kd + copysign(0.5, kd));
    double kf = (double)k;
    double r = (x - kf * NL_LN2_HI) - kf * NL_LN2_LO;
    double y = 1.0 + (r + r * r * nl_exp_poly(r));
    return nl_scalbn(y, k);
}

/* ── log family ─────────────────────────────────────────────────── */

/* Reduce x to 2^e * m with m in [sqrt(2)/2, sqrt(2)), then
 * log(m) = 2*atanh(s), s = (m-1)/(m+1) — the classical form, because
 * it is the one whose series converges on the whole reduced range.
 * Returns log(m); *ep receives e. Caller adds e*ln2 in whatever base. */
static double nl_log_mant(double x, int *ep) {
    u64 b = nl_B(x);
    int e = 0;
    if (b < 0x0010000000000000ULL) {                 /* subnormal */
        x *= 0x1p54;
        e = -54;
        b = nl_B(x);
    }
    e += (int)((b >> 52) & 0x7ff) - 1023;
    double m = nl_D((b & NL_MANMSK) | 0x3ff0000000000000ULL);
    if (m > NL_SQRT2) { m *= 0.5; e += 1; }
    *ep = e;
    /* f = m-1 is EXACT (Sterbenz: m is within a factor of two of 1),
     * and 2*atanh(s) = f - s*(f - R) with s = f/(2+f) and R = 2z*A(z).
     * Writing it that way keeps the exact f as the leading term and
     * makes everything else a small correction — the algebraically
     * equivalent `2s + 2s*z*A` starts from a rounded quotient instead
     * and costs a whole ulp just above 1, which is precisely where log
     * is asked for its relative accuracy. */
    double f = m - 1.0;
    double s = f / (2.0 + f);
    double z = s * s;
    double p = NL_LOG_P[11];
    for (int i = 10; i >= 0; i--) p = p * z + NL_LOG_P[i];
    double R = 2.0 * z * p;
    return f - s * (f - R);
}

/* The same reduction and the same polynomial, with every step's error
 * term kept. Used only by pow, which is the only caller whose result
 * multiplies this by up to a thousand.
 *
 * The identity is unchanged — log(m) = f - s*(f - R) — but f is exact,
 * s is computed with its residual, and the product s*(f-R) is formed
 * with two_prod, so what comes out is good to about 2^-100 rather than
 * 2^-53. */
static void nl_log_mant_dd(double x, int *ep, double *hi, double *lo) {
    u64 b = nl_B(x);
    int e = 0;
    if (b < 0x0010000000000000ULL) { x *= 0x1p54; e = -54; b = nl_B(x); }
    e += (int)((b >> 52) & 0x7ff) - 1023;
    double m = nl_D((b & NL_MANMSK) | 0x3ff0000000000000ULL);
    if (m > NL_SQRT2) { m *= 0.5; e += 1; }
    *ep = e;

    double f = m - 1.0;                    /* exact */
    double d, dl;
    nl_two_sum(2.0, f, &d, &dl);           /* 2 + f, with its residual */
    double s = f / d;
    double sd, sde;
    nl_two_prod(s, d, &sd, &sde);
    double slo = ((f - sd) - sde - s * dl) / d;    /* Newton on the quotient */

    /* R is small, but pow multiplies log(m) by up to a thousand, so
     * even R's own last bit is a visible ulp of the answer. Both its
     * roundings — z's and the product's — are kept. */
    double z, ze;
    nl_two_prod(s, s, &z, &ze);
    double p = NL_LOG_P[11];
    for (int i = 10; i >= 0; i--) p = p * z + NL_LOG_P[i];
    double R, Re;
    nl_two_prod(2.0 * z, p, &R, &Re);
    Re += 2.0 * ze * p;

    /* f - R must keep its own rounding too: it is about -0.31 here, so
     * dropping the 3e-17 the subtraction discards puts 0.06 ulp into
     * log(m) — invisible on its own, and multiplied by an exponent of
     * 1000 inside pow it is forty ulp of the answer. The error grew
     * exactly linearly in y, which is what said the fault was in the
     * logarithm and not in the exponential. */
    double u, ul;
    nl_two_sum(f, -R, &u, &ul);
    ul -= Re;
    double ph, pl;
    nl_two_prod(s, u, &ph, &pl);
    pl += slo * u + s * ul;
    double th, tl;
    nl_two_sum(f, -ph, &th, &tl);
    *hi = th;
    *lo = tl - pl;
}

/* The three logs differ only in what they multiply the exponent and the
 * mantissa term by, so they share one kernel and one shape. Each
 * constant is a two-part split for the same reason ln2 is in exp: the
 * head times a small integer is exact. */
static double nl_log_base(double x, double khi, double klo,
                          double chi, double clo)
{
    u64 b = nl_B(x);
    if ((b & ~NL_SIGN) == 0) return -(NL_INF_D * NL_INF_D);     /* ±0 → -inf */
    if (b & NL_SIGN) return nl_nan();                            /* x < 0 */
    if ((b & NL_EXPMSK) == NL_EXPMSK)                            /* inf / nan */
        return (b & NL_MANMSK) ? x + x : x;
    int e;
    double t = nl_log_mant(x, &e);
    double ef = (double)e;
    /* e*khi is exact — khi is a 32-bit head and |e| <= 1074 — but
     * t*chi is not, and neither is their sum. Both are formed with
     * their error terms and the two are added in double-double, which
     * is what takes log10 from 3 ulp to 1: the plain expression throws
     * away one rounding per product and then a third on the sum. */
    double eh, el, th, tl, sum, se;
    nl_two_prod(ef, khi, &eh, &el);
    nl_two_prod(t, chi, &th, &tl);
    nl_two_sum(eh, th, &sum, &se);
    return sum + (se + ((el + tl) + (ef * klo + t * clo)));
}

double log(double x)   { return nl_log_base(x, NL_LN2_HI, NL_LN2_LO, 1.0, 0.0); }
double log2(double x)  { return nl_log_base(x, 1.0, 0.0, NL_IVLN2_HI, NL_IVLN2_LO); }
double log10(double x) { return nl_log_base(x, NL_LG2_HI, NL_LG2_LO,
                                            NL_IVLN10_HI, NL_IVLN10_LO); }

/* ── argument reduction for the trigonometric functions ─────────── */

/* Payne-Hanek. x = m*2^e with m a 53-bit integer. Only the bits of 2/pi
 * from index e-1 downward can affect x*(2/pi) mod 4: everything above
 * multiplies out to a multiple of 4 and vanishes. So take 192 bits of
 * 2/pi starting there, multiply by m exactly, and read the answer off
 * the product — 192 bits is far past the ~61 bits the worst-case double
 * cancels, so nothing is left to chance.
 *
 * Returns the quadrant; *rp gets the reduced argument in [-pi/4, pi/4]. */
static int nl_rem_pio2_big(double x, double *rp) {
    u64 b = nl_B(x);
    int sign = (int)(b >> 63);
    int ex = (int)((b >> 52) & 0x7ff);
    u64 m;
    int e;
    if (ex == 0) {                                   /* subnormal */
        m = b & NL_MANMSK;
        e = -1074;
        while (!(m >> 52)) { m <<= 1; e--; }         /* normalise */
        e += 0;
    } else {
        m = (b & NL_MANMSK) | (1ULL << 52);
        e = ex - 1075;                               /* x = m * 2^e */
    }

    /* k0 = e-1 is what makes the DISCARDED head a multiple of 4, which
     * is the whole reason the quadrant survives. Clamping it to 1 for
     * small exponents — as the first version did — silently changes the
     * scale factor from 4 to 2^e and turns every medium argument into
     * noise. Bits at index <= 0 are bits of the integer part of 2/pi,
     * which is 0, so the stream is simply zero there and the index is
     * allowed to go negative. */
    int k0 = e - 1;
    int idx = k0 - 1;
    int w = (idx >= 0) ? idx / 64 : -(((-idx) + 63) / 64);
    int off = idx - w * 64;                       /* floor semantics: 0..63 */

    u64 p[3];
    for (int i = 0; i < 3; i++) {
        int wi = w + i;
        u64 hi = (wi >= 0 && wi < 24) ? NL_TWO_OVER_PI[wi] : 0ULL;
        u64 lo = (wi + 1 >= 0 && wi + 1 < 24) ? NL_TWO_OVER_PI[wi + 1] : 0ULL;
        p[i] = off ? ((hi << off) | (lo >> (64 - off))) : hi;
    }

    /* P = m * (p0:p1:p2), a 245-bit product; we need its low 192 bits. */
    u128 t;
    u64 w0, w1, w2, c;
    t  = (u128)m * p[2];         w0 = (u64)t;              c = (u64)(t >> 64);
    t  = (u128)m * p[1] + c;     w1 = (u64)t;              c = (u64)(t >> 64);
    t  = (u128)m * p[0] + c;     w2 = (u64)t;

    /* x*(2/pi) mod 4 == (w2:w1:w0) * 2^-190, so the quadrant is the top
     * two bits of w2 and the rest is the fraction. */
    int n = (int)(w2 >> 62);
    u64 q2 = w2 & 0x3FFFFFFFFFFFFFFFULL;
    int neg = 0;

    /* Fold a fraction above 1/2 into the next quadrant IN THE INTEGER
     * DOMAIN. Rounding to double first and then subtracting 1.0 loses
     * everything the reduction was for: at x = 723442.8 the fraction is
     * 0.99999999999944, a double holds 53 bits of it, and the
     * subtraction leaves thirteen correct bits — sin then came back
     * with a relative error of 1e-4 having done 192 bits of exact work
     * to get there. Two's complement over the 190-bit fraction keeps
     * all of them. */
    if (q2 >> 61) {
        n++;
        neg = 1;
        u128 lo  = ((u128)w1 << 64) | w0;
        u128 nlo = (u128)0 - lo;                       /* 2^128 - lo */
        u64 borrow = (lo != 0) ? 1 : 0;
        q2 = (0x4000000000000000ULL - q2 - borrow) & 0x3FFFFFFFFFFFFFFFULL;
        w1 = (u64)(nlo >> 64);
        w0 = (u64)nlo;
    }
    /* Normalise, then convert 64 bits — ONE rounding, and no helper.
     *
     * Casting the `u128` straight to double lowers to __floattidf, a
     * compiler-rt routine that a -nostdlib link does not have; the
     * hosted differential linked libgcc and never noticed, and the
     * freestanding build is where it surfaced. The obvious replacement
     * — three scaled terms added together — links, but rounds three
     * times and costs sin an ulp. Shifting the top set bit to position
     * 63 and letting the hardware round 64 bits to 53 gives back the
     * single rounding, and the 64 bits below that are worth less than
     * 2^-64 of the result. */
    double frac;
    {
        u128 n = ((u128)q2 << 64) | w1;
        if (n) {
            u64 h = (u64)(n >> 64);
            int lz = h ? __builtin_clzll(h) : 64 + __builtin_clzll((u64)n);
            n <<= lz;
            frac = nl_scalbn((double)(u64)(n >> 64), -126 - lz + 64);
        } else {
            frac = (double)w0 * 0x1p-190;
        }
    }
    if (neg) frac = -frac;

    /* pi/2 in two parts so the multiply keeps its low bits. */
    double r = frac * NL_PIO2_D + frac * NL_PIO2_T;
    if (sign) { r = -r; n = -n; }
    *rp = r;
    return n & 3;
}

/* Cody-Waite for the arguments that do not need the big machinery.
 * |n| < 2^20 keeps every n*PIO2_i product exact (24-bit heads), so the
 * only inexactness is the final part — and the guard below sends the
 * cancelling cases to Payne-Hanek rather than trusting them. */
static int nl_rem_pio2(double x, double *rp) {
    double ax = fabs(x);
    if (ax <= 0x1.921fb54442d18p-1) { *rp = x; return 0; }   /* |x| <= pi/4 */
    if (ax < 0x1.0p20) {
        double fn = x * NL_2_OVER_PI;
        int n = (int)(fn + copysign(0.5, fn));
        double nf = (double)n;
        double r = x - nf * NL_PIO2_0;
        r -= nf * NL_PIO2_1;
        r -= nf * NL_PIO2_2;
        r -= nf * NL_PIO2_3;
        /* Heavy cancellation means the low bits that survived are the
         * only ones left, and Cody-Waite has none to give. */
        if (fabs(r) > 0x1.0p-25) { *rp = r; return n & 3; }
    }
    return nl_rem_pio2_big(x, rp);
}

/* ── sin / cos / tan ────────────────────────────────────────────── */

static double nl_sin_k(double r) {
    double z = r * r;
    double p = NL_SIN_P[8];
    for (int i = 7; i >= 0; i--) p = p * z + NL_SIN_P[i];
    return r + (r * z) * p;
}

static double nl_cos_k(double r) {
    double z = r * r;
    double p = NL_COS_P[8];
    for (int i = 7; i >= 0; i--) p = p * z + NL_COS_P[i];
    /* 1 - z/2 written as (1 - z/2) + z*z*p: for |r| <= pi/4 the leading
     * term never cancels, so no compensation is needed. */
    return (1.0 - 0.5 * z) + (z * z) * p;
}

static double nl_tan_k(double r) {
    double z = r * r;
    double p = NL_TAN_P[22];
    for (int i = 21; i >= 0; i--) p = p * z + NL_TAN_P[i];
    return r + (r * z) * p;
}

double sin(double x) {
    u64 ax = nl_B(x) & ~NL_SIGN;
    if (ax >= 0x7ff0000000000000ULL) return x - x;   /* inf/nan → nan */
    if (ax < 0x3e40000000000000ULL) return x;        /* |x| < 2^-27 */
    double r;
    int n = nl_rem_pio2(x, &r);
    switch (n) {
        case 0:  return  nl_sin_k(r);
        case 1:  return  nl_cos_k(r);
        case 2:  return -nl_sin_k(r);
        default: return -nl_cos_k(r);
    }
}

double cos(double x) {
    u64 ax = nl_B(x) & ~NL_SIGN;
    if (ax >= 0x7ff0000000000000ULL) return x - x;
    if (ax < 0x3e40000000000000ULL) return 1.0;
    double r;
    int n = nl_rem_pio2(x, &r);
    switch (n) {
        case 0:  return  nl_cos_k(r);
        case 1:  return -nl_sin_k(r);
        case 2:  return -nl_cos_k(r);
        default: return  nl_sin_k(r);
    }
}

double tan(double x) {
    u64 ax = nl_B(x) & ~NL_SIGN;
    if (ax >= 0x7ff0000000000000ULL) return x - x;
    if (ax < 0x3e40000000000000ULL) return x;
    double r;
    int n = nl_rem_pio2(x, &r);
    double t = nl_tan_k(r);
    return (n & 1) ? -1.0 / t : t;
}

/* ── atan / atan2 ───────────────────────────────────────────────── */

static double nl_atan_poly(double z) {
    double p = NL_ATAN_P[15];
    for (int i = 14; i >= 0; i--) p = p * z + NL_ATAN_P[i];
    return p;
}

/* Fold the argument towards one of four points — 0.5, 1, 1.5 and
 * infinity — so the polynomial only ever sees |w| < 7/16. Each target's
 * atan is stored as head + tail, so the fold costs no accuracy. */
double atan(double x) {
    u64 b = nl_B(x), ax = b & ~NL_SIGN;
    int sign = (int)(b >> 63);
    if (ax >= 0x7ff0000000000000ULL)
        return (ax > 0x7ff0000000000000ULL) ? x + x
                                            : (sign ? -NL_ATAN_HI[3] : NL_ATAN_HI[3]);
    if (ax >= 0x4410000000000000ULL) {               /* |x| >= 2^66 */
        double r = NL_ATAN_HI[3] + NL_ATAN_LO[3];
        return sign ? -r : r;
    }
    if (ax < 0x3e40000000000000ULL) return x;        /* |x| < 2^-27 */

    double a = nl_D(ax);
    int id;
    if (a < 0.4375) id = -1;
    else if (a < 1.1875) {
        if (a < 0.6875) { id = 0; a = (2.0 * a - 1.0) / (2.0 + a); }
        else            { id = 1; a = (a - 1.0) / (a + 1.0); }
    } else if (a < 2.4375) { id = 2; a = (a - 1.5) / (1.0 + 1.5 * a); }
    else                   { id = 3; a = -1.0 / a; }

    double z = a * a;
    double t = a + (a * z) * nl_atan_poly(z);
    double r = (id < 0) ? t : (NL_ATAN_HI[id] + (t + NL_ATAN_LO[id]));
    return sign ? -r : r;
}

double atan2(double y, double x) {
    u64 by = nl_B(y), bx = nl_B(x);
    if ((by & ~NL_SIGN) > 0x7ff0000000000000ULL) return y + y;   /* nan */
    if ((bx & ~NL_SIGN) > 0x7ff0000000000000ULL) return x + x;
    int sy = (int)(by >> 63);

    if ((by & ~NL_SIGN) == 0)                       /* y = ±0 */
        return (bx & NL_SIGN) ? (sy ? -NL_PI_D : NL_PI_D) : y;
    if ((bx & ~NL_SIGN) == 0)                       /* x = ±0 */
        return sy ? -(NL_PIO2_D) : (NL_PIO2_D);

    if ((bx & ~NL_SIGN) == 0x7ff0000000000000ULL) { /* x = ±inf */
        if ((by & ~NL_SIGN) == 0x7ff0000000000000ULL) {
            double q = (bx & NL_SIGN) ? 3.0 * (NL_PI_D / 4) : (NL_PI_D / 4);
            return sy ? -q : q;
        }
        double q = (bx & NL_SIGN) ? NL_PI_D : 0.0;
        return sy ? -q : q;
    }
    if ((by & ~NL_SIGN) == 0x7ff0000000000000ULL)   /* y = ±inf */
        return sy ? -(NL_PIO2_D) : (NL_PIO2_D);

    double t = atan(fabs(y / x));
    if (!(bx & NL_SIGN)) return sy ? -t : t;        /* right half plane */
    /* Left half: pi - t, with pi's tail carried so the subtraction does
     * not lose what atan just computed. */
    double r = (NL_PI_D - (t - NL_PI_T));
    return sy ? -r : r;
}

/* ── cbrt ───────────────────────────────────────────────────────── */

/* The exponent of x^(1/3) is a third of x's, which is one integer
 * division on the bit pattern — the classic seed. Two Newton steps take
 * it to about 1 ulp; the third is done on the residual so the last step
 * corrects rather than re-derives. */
double cbrt(double x) {
    u64 b = nl_B(x), ax = b & ~NL_SIGN;
    if (ax == 0 || ax >= 0x7ff0000000000000ULL) return x + x == x ? x : x + x;
    int sign = (int)(b >> 63);
    double a = nl_D(ax);
    int scale = 0;
    if (ax < 0x0010000000000000ULL) { a *= 0x1p60; scale = -20; }

    u64 t = nl_B(a) / 3 + 0x2A9F76253119D328ULL;
    double y = nl_D(t);
    /* The bit-pattern seed is good for about five bits and each Newton
     * step doubles that, so three steps reach ~40 — close enough to
     * look right and three ulp short. Four reach the full 53, and the
     * residual step below then corrects rather than converges. */
    for (int i = 0; i < 4; i++) y = (2.0 * y + a / (y * y)) / 3.0;
    /* One residual step: y^3 - a computed with the error term, so the
     * correction sees the bits the plain iteration cannot. */
    double y2, y2e, y3, y3e;
    nl_two_prod(y, y, &y2, &y2e);
    nl_two_prod(y2, y, &y3, &y3e);
    double res = (y3 - a) + (y3e + y2e * y);
    y -= res / (3.0 * y2);

    y = nl_scalbn(y, scale);
    return sign ? -y : y;
}

/* ── hypot ──────────────────────────────────────────────────────── */

/* sqrt(x^2 + y^2) without the overflow that squaring invites, and
 * without the ulp that a plain sqrt(a*a + b*b) throws away: the sum is
 * formed in double-double and the square root corrected once. */
double hypot(double x, double y) {
    double a = fabs(x), b = fabs(y);
    u64 ba = nl_B(a), bb = nl_B(b);
    if (ba == 0x7ff0000000000000ULL || bb == 0x7ff0000000000000ULL) return nl_inf();
    if (ba > 0x7ff0000000000000ULL || bb > 0x7ff0000000000000ULL) return x + y;
    if (b > a) { double t = a; a = b; b = t; }
    if (b == 0.0) return a;

    int k = 0;
    int ea = (int)((nl_B(a) >> 52) & 0x7ff);
    if (ea > 1023 + 500) { k = 600;  a *= 0x1p-600; b *= 0x1p-600; }
    else if (ea < 1023 - 500) { k = -600; a *= 0x1p600; b *= 0x1p600; }

    double aa, aae, bbq, bbe;
    nl_two_prod(a, a, &aa, &aae);
    nl_two_prod(b, b, &bbq, &bbe);
    double s, se;
    nl_two_sum(aa, bbq, &s, &se);
    se += aae + bbe;
    double r = sqrt(s);
    /* Newton on r^2 = s: one step from a correctly-rounded sqrt of the
     * high part, using the residual the double-double kept. */
    double r2, r2e;
    nl_two_prod(r, r, &r2, &r2e);
    r += ((s - r2) + (se - r2e)) / (2.0 * r);
    return nl_scalbn(r, k);
}

/* ── pow ────────────────────────────────────────────────────────── */

/* 2^f for |f| <= 0.5, through the exp kernel with f*ln2 carried in two
 * parts so the reduction's own rounding does not eat the result's low
 * bits. */
static double nl_exp2_frac(double fhi, double flo) {
    double p, e;
    nl_two_prod(fhi, NL_LN2_HI, &p, &e);
    double rl = e + fhi * NL_LN2_LO + flo * NL_LN2_HI;
    /* The kernel must see the FULL reduced argument. Evaluating it at
     * the head alone and adding the tail only to the linear term looks
     * harmless — the tail is 4e-11 — but d(r^2*E)/dr is about 0.3
     * there, so it puts 1e-11 into every pow(): pow(2, 0.5) came back
     * as 1.4142135623513 instead of ...3730951. */
    double rf = p + rl;
    double rlo = rl - (rf - p);            /* what the sum could not hold */
    double t = 1.0 + rf + (rf * rf) * nl_exp_poly(rf);
    return t + t * rlo;                    /* exp(rf + rlo) = exp(rf)*(1+rlo) */
}

/* Is y an integer, and if so is it odd? 0 = not an integer, 1 = odd,
 * 2 = even. Every one of pow's sign rules turns on this. */
static int nl_int_kind(double y) {
    u64 b = nl_B(y), ay = b & ~NL_SIGN;
    int e = (int)((ay >> 52) & 0x7ff) - 1023;
    if (ay == 0) return 2;
    if (e < 0) return 0;
    if (e >= 52) return 2;                 /* too large to be odd */
    u64 m = (ay & NL_MANMSK) | (1ULL << 52);
    u64 low = m & (NL_MANMSK >> e);
    if (low) return 0;
    return ((m >> (52 - e)) & 1) ? 1 : 2;
}

double pow(double x, double y) {
    u64 bx = nl_B(x), by = nl_B(y);
    u64 axb = bx & ~NL_SIGN, ayb = by & ~NL_SIGN;

    if (ayb == 0) return 1.0;                        /* x^0 = 1, even nan^0 */
    if (bx == 0x3ff0000000000000ULL) return 1.0;     /* 1^y = 1, even nan */
    if (axb > 0x7ff0000000000000ULL || ayb > 0x7ff0000000000000ULL)
        return x + y;                                /* nan */

    int yk = nl_int_kind(y);
    int xneg = (int)(bx >> 63);
    if (xneg && yk == 0) return nl_nan();            /* negative^non-integer */
    int negresult = (xneg && yk == 1);

    if (ayb == 0x7ff0000000000000ULL) {              /* y = ±inf */
        if (axb == 0x3ff0000000000000ULL) return 1.0;    /* (-1)^inf */
        int big = axb > 0x3ff0000000000000ULL;
        return (big == !(by >> 63)) ? nl_inf() : 0.0;
    }
    if (axb == 0) {                                  /* x = ±0 */
        double r = (by >> 63) ? nl_inf() : 0.0;
        return negresult ? -r : r;
    }
    if (axb == 0x7ff0000000000000ULL) {              /* x = ±inf */
        double r = (by >> 63) ? 0.0 : nl_inf();
        return negresult ? -r : r;
    }

    /* |x|^y = 2^(y * log2|x|), and the exponent is where all of pow's
     * accuracy lives: an absolute error d in y*log2|x| is a RELATIVE
     * error of d*ln2 in the answer, so at y*log2|x| = 900 an ordinary
     * double's last bit is already 1e-13 of the result. Hence a
     * double-double all the way down — including the log kernel, whose
     * own single-double result would otherwise cap pow at ~300 ulp no
     * matter how carefully the rest is carried. */
    double a = nl_D(axb);
    int e;
    double thi, tlo;
    nl_log_mant_dd(a, &e, &thi, &tlo);
    double lhi, llo;
    nl_two_prod(thi, NL_IVLN2_HI, &lhi, &llo);
    llo += thi * NL_IVLN2_LO + tlo * NL_IVLN2_HI;
    double Lhi, Llo;
    nl_two_sum((double)e, lhi, &Lhi, &Llo);
    Llo += llo;

    double phi, plo;
    nl_two_prod(y, Lhi, &phi, &plo);
    plo += y * Llo;

    if (phi > 1024.0) return negresult ? -(NL_INF_D * NL_INF_D)
                                       :  (NL_INF_D * NL_INF_D);
    if (phi < -1080.0) return negresult ? -0.0 : 0.0;

    double n = round(phi);
    double fhi, flo;
    nl_two_sum(phi - n, plo, &fhi, &flo);
    double r = nl_exp2_frac(fhi, flo);
    r = nl_scalbn(r, (int)n);
    return negresult ? -r : r;
}

/* ── erf / erfc ─────────────────────────────────────────────────── */

/* Both are built from the same two pieces:
 *
 *   |x| <= 1     erf(x) = x * E(x^2), a single polynomial. erfc is
 *                1 - erf, which loses nothing here because erf(1) is
 *                only 0.84 — the cancellation people warn about starts
 *                further out, and further out is where the other branch
 *                takes over.
 *   |x| >  1     erfc(x) = exp(-x^2) * G(x) / x, and erf = 1 - erfc.
 *                G is fitted in u = 1/x^2 over three sub-ranges,
 *                because one fit across the whole tail needs a degree
 *                the accuracy does not justify.
 *
 * exp(-x^2) is the delicate part: x^2 must be formed in double-double
 * or its rounding alone costs the result a factor of e^(1 ulp of x^2),
 * which at x = 20 is 400 ulp. */
static double nl_erf_small(double x) {
    double z = x * x;
    double p = NL_ERF_P[NL_ERF_P_N - 1];
    for (int i = NL_ERF_P_N - 2; i >= 0; i--) p = p * z + NL_ERF_P[i];
    return x * p;
}

/* erfc on (0.5, 1], straight from a polynomial in a. See the header of
 * the generated table: subtracting erf from 1 here costs two and a half
 * bits, and there is nothing in this range that needs subtracting. */
static double nl_erfc_mid(double a) {
    double v = (a - NL_ERFC_D_MID) * NL_ERFC_D_INVHALF;
    double p = NL_ERFC_D[NL_ERFC_D_N - 1];
    for (int i = NL_ERFC_D_N - 2; i >= 0; i--) p = p * v + NL_ERFC_D[i];
    return p;
}

static double nl_erfc_tail(double a) {
    double u = 1.0 / (a * a);
    const double *P;
    int n;
    double mid, invhalf;
    if (u >= NL_ERFC_U1) {
        P = NL_ERFC_A; n = NL_ERFC_A_N;
        mid = NL_ERFC_A_MID; invhalf = NL_ERFC_A_INVHALF;
    } else if (u >= NL_ERFC_U2) {
        P = NL_ERFC_B; n = NL_ERFC_B_N;
        mid = NL_ERFC_B_MID; invhalf = NL_ERFC_B_INVHALF;
    } else {
        P = NL_ERFC_C; n = NL_ERFC_C_N;
        mid = NL_ERFC_C_MID; invhalf = NL_ERFC_C_INVHALF;
    }
    /* Evaluated in the centred variable the generator fitted in — a
     * degree-30 monomial fit on [0.25,1] has alternating coefficients
     * in the thousands and loses twelve digits to cancellation, which
     * is how a 6e-22 fit produced a 5e-10 answer. */
    double v = (u - mid) * invhalf;
    double g = P[n - 1];
    for (int i = n - 2; i >= 0; i--) g = g * v + P[i];

    /* exp(-a^2) with a^2 in two parts: exp(-hi) * exp(-lo). */
    double hi, lo;
    nl_two_prod(a, a, &hi, &lo);
    return exp(-hi) * exp(-lo) * g / a;
}

double erf(double x) {
    u64 b = nl_B(x), ax = b & ~NL_SIGN;
    if (ax >= 0x7ff0000000000000ULL)
        return (ax > 0x7ff0000000000000ULL) ? x + x : ((b & NL_SIGN) ? -1.0 : 1.0);
    double a = nl_D(ax);
    double r = (a <= 1.0) ? nl_erf_small(a)
                          : (a >= 6.0 ? 1.0 : 1.0 - nl_erfc_tail(a));
    return (b & NL_SIGN) ? -r : r;
}

double erfc(double x) {
    u64 b = nl_B(x), ax = b & ~NL_SIGN;
    if (ax >= 0x7ff0000000000000ULL)
        return (ax > 0x7ff0000000000000ULL) ? x + x : ((b & NL_SIGN) ? 2.0 : 0.0);
    double a = nl_D(ax);
    if (b & NL_SIGN) {
        /* erfc(-x) = 2 - erfc(x); for large x that is exactly 2. */
        if (a > 6.0) return 2.0;
        return (a <= 1.0) ? 1.0 + nl_erf_small(a) : 2.0 - nl_erfc_tail(a);
    }
    if (a <= 0.5) return 1.0 - nl_erf_small(a);
    if (a <= 1.0) return nl_erfc_mid(a);
    if (a >= 27.25) return 0.0;                      /* underflows */
    return nl_erfc_tail(a);
}
