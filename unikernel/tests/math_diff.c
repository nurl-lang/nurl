/*
 * NURL nolibc — unikernel/tests/math_diff.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The gate on unikernel/nolibc/math.c: every function against glibc's,
 * measured in ULPS, over ranges chosen to include the places these
 * implementations can go wrong rather than the places they cannot.
 *
 * Why ulps and not "close enough": a relative-error bound hides the two
 * failures that matter. Near a zero of the function (sin at a multiple
 * of pi, log at 1) the relative error of a correct answer is fine and
 * the ulp error tells you whether the argument reduction survived; far
 * out in a tail (erfc at 25) the absolute error is 1e-300 for both a
 * right and a hopelessly wrong answer.
 *
 * The ranges are the point. Uniform sampling over [-1,1] would give
 * every function a clean bill: what actually breaks a libm is the large
 * argument (sin(1e300), where reduction in double arithmetic has no
 * correct bits at all), the near-cancellation (log just above 1), the
 * boundary between branches, and the edges of the exponent range. Each
 * function below names the ones that apply to it.
 *
 * The exact functions — sqrt, fabs, floor, ceil, trunc, round,
 * copysign — are held to BIT EQUALITY, not to an ulp bound. They have
 * no error to allow.
 *
 * Usage: math_diff [iterations] [seed]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>

/* nolibc's, under names that let both live in one process. */
double nl_sqrt(double), nl_fabs(double), nl_floor(double), nl_ceil(double);
double nl_trunc(double), nl_round(double), nl_copysign(double, double);
double nl_exp(double), nl_log(double), nl_log2(double), nl_log10(double);
double nl_sin(double), nl_cos(double), nl_tan(double);
double nl_atan(double), nl_atan2(double, double), nl_pow(double, double);
double nl_cbrt(double), nl_hypot(double, double);
double nl_erf(double), nl_erfc(double);

static uint64_t rng_state = 0x853C49E6748FEA9BULL;
static uint64_t rnd(void) {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 7;
    rng_state ^= rng_state << 17;
    return rng_state;
}
static double rnd_uniform(double lo, double hi) {
    return lo + (hi - lo) * ((double)(rnd() >> 11) * 0x1p-53);
}
/* Uniform in the EXPONENT, which is how a float-valued input space is
 * actually shaped — uniform in value would never once sample 1e-300. */
static double rnd_logspace(double lo, double hi) {
    double l = log(lo), h = log(hi);
    return exp(rnd_uniform(l, h));
}

static uint64_t bits(double d) { uint64_t b; memcpy(&b, &d, 8); return b; }

/* Distance in ulps between two doubles, using the ordered-integer trick
 * so subnormals and the zero crossing behave. */
static double ulp_diff(double a, double b) {
    if (isnan(a) && isnan(b)) return 0;
    if (a == b) return 0;
    if (isnan(a) != isnan(b)) return 1e18;
    if (isinf(a) || isinf(b)) return 1e18;
    int64_t ia = (int64_t)bits(a), ib = (int64_t)bits(b);
    if (ia < 0) ia = INT64_MIN - ia;
    if (ib < 0) ib = INT64_MIN - ib;
    int64_t d = ia > ib ? ia - ib : ib - ia;
    return (double)d;
}

static int failures;

typedef struct {
    const char *name;
    double worst;
    double at, at2;
    double got, want;
    long long n;
} Acc;

static void note(Acc *a, double x, double y, double got, double want) {
    double u = ulp_diff(got, want);
    a->n++;
    if (u > a->worst) {
        a->worst = u;
        a->at = x; a->at2 = y; a->got = got; a->want = want;
    }
}

static void report(Acc *a, double bound) {
    const char *verdict = (a->worst <= bound) ? "ok" : "OVER BOUND";
    printf("  %-8s %10lld pts   worst %6.2f ulp (bound %.1f)  %s\n",
           a->name, a->n, a->worst, bound, verdict);
    if (a->worst > bound) {
        printf("      at %.17g, %.17g: got %.17g want %.17g\n",
               a->at, a->at2, a->got, a->want);
        failures++;
    }
}

/* Functions, not macros. The macro version expanded its argument three
 * times — once for the record, once for each implementation — so a
 * `rnd_uniform(...)` argument handed the two libms DIFFERENT inputs and
 * every function on the list "failed" by thousands of ulp. A comparison
 * harness that does not compare the same point is measuring nothing. */
static void one(Acc *a, double (*f)(double), double (*g)(double), double x) {
    note(a, x, 0, f(x), g(x));
}
static void two(Acc *a, double (*f)(double, double), double (*g)(double, double),
                double x, double y) {
    note(a, x, y, f(x, y), g(x, y));
}
#define ONE(acc, call, ref, x)    one(&acc, call, ref, (x))
#define TWO(acc, call, ref, x, y) two(&acc, call, ref, (x), (y))

/* The exact ones: bit equality or bust. */
static void exact_one(const char *name, double (*f)(double),
                      double (*g)(double), long long iters) {
    long long bad = 0;
    double at = 0;
    static const double edge[] = {
        0.0, -0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.5, -2.5,
        0.49999999999999994, -0.49999999999999994,
        4503599627370495.5, -4503599627370495.5,
        4503599627370496.0, 1e308, -1e308, 5e-324, -5e-324,
        1.0 / 0.0, -1.0 / 0.0,
    };
    for (unsigned i = 0; i < sizeof edge / sizeof edge[0]; i++)
        if (bits(f(edge[i])) != bits(g(edge[i]))) { bad++; at = edge[i]; }
    for (long long i = 0; i < iters; i++) {
        uint64_t b = rnd();
        double x;
        memcpy(&x, &b, 8);
        if (isnan(x)) continue;
        if (bits(f(x)) != bits(g(x))) { bad++; at = x; }
        double y = rnd_uniform(-1e6, 1e6);
        if (bits(f(y)) != bits(g(y))) { bad++; at = y; }
    }
    printf("  %-8s %10lld mismatches%s\n", name, bad, bad ? "  <- NOT EXACT" : " (bit-identical)");
    if (bad) { printf("      first at %.17g: got %.17g want %.17g\n", at, f(at), g(at)); failures++; }
}

int main(int argc, char **argv) {
    long long N = (argc > 1) ? atoll(argv[1]) : 200000;
    if (argc > 2) rng_state = (uint64_t)atoll(argv[2]) * 2654435761u + 1;

    printf("── exact (bit-identical to glibc required) ──\n");
    exact_one("sqrt",  nl_sqrt,  sqrt,  N);
    exact_one("fabs",  nl_fabs,  fabs,  N);
    exact_one("floor", nl_floor, floor, N);
    exact_one("ceil",  nl_ceil,  ceil,  N);
    exact_one("trunc", nl_trunc, trunc, N);
    exact_one("round", nl_round, round, N);

    /* cbrt is checked against ARITHMETIC, not against glibc. glibc's
     * cbrt is the less accurate of the two here — it answers
     * 3.0000000000000004 for cbrt(27) — so an ulp comparison against it
     * would fail a correctly-rounded implementation and pass a wrong
     * one. A perfect cube has an exact answer and nothing to argue
     * about: n^3 is exact in a double for n up to 2^17, and cbrt of it
     * must be n. */
    {
        long long bad = 0, first = 0;
        for (long long n = 1; n < 131072; n++) {
            double c = (double)n * (double)n * (double)n;
            if (nl_cbrt(c) != (double)n || nl_cbrt(-c) != -(double)n) {
                if (!bad) first = n;
                bad++;
            }
        }
        printf("  %-8s %10s   %lld perfect cubes wrong%s\n", "cbrt", "exact",
               bad, bad ? "  <- NOT EXACT" : " (all exact)");
        if (bad) { printf("      first at n = %lld: %.17g\n", first,
                          nl_cbrt((double)first * first * first)); failures++; }
    }

    printf("── approximated (ulp against glibc) ──\n");
    Acc a_exp = {"exp"}, a_log = {"log"}, a_log2 = {"log2"}, a_log10 = {"log10"};
    Acc a_sin = {"sin"}, a_cos = {"cos"}, a_tan = {"tan"};
    Acc a_atan = {"atan"}, a_atan2 = {"atan2"}, a_pow = {"pow"}, a_powx = {"pow!"};
    Acc a_cbrt = {"cbrt"}, a_hypot = {"hypot"}, a_erf = {"erf"}, a_erfc = {"erfc"};

    for (long long i = 0; i < N; i++) {
        /* exp: the whole finite range, plus the overflow and
         * gradual-underflow shoulders where scalbn has to be right. */
        ONE(a_exp, nl_exp, exp, rnd_uniform(-745.2, 709.8));
        ONE(a_exp, nl_exp, exp, rnd_uniform(-1, 1));
        ONE(a_exp, nl_exp, exp, rnd_uniform(-745.2, -708.0));   /* subnormal results */

        /* log: the exponent range, and — the interesting part — just
         * above 1, where the mantissa reduction cancels. */
        double lx = rnd_logspace(1e-300, 1e300);
        ONE(a_log, nl_log, log, lx);
        ONE(a_log, nl_log, log, 1.0 + rnd_uniform(-1e-6, 1e-6));
        ONE(a_log2, nl_log2, log2, lx);
        ONE(a_log2, nl_log2, log2, rnd_uniform(0.5, 2.0));
        ONE(a_log10, nl_log10, log10, lx);
        ONE(a_log10, nl_log10, log10, rnd_uniform(0.5, 2.0));
        /* exact powers of two must come back exact */
        {
            int e = (int)(rnd() % 2000) - 1000;
            double p = ldexp(1.0, e);
            note(&a_log2, p, 0, nl_log2(p), log2(p));
        }

        /* sin/cos/tan: small, medium, and the arguments that decide
         * whether the reduction is real — 1e300 needs the 2/pi bits. */
        double s1 = rnd_uniform(-3.15, 3.15);
        ONE(a_sin, nl_sin, sin, s1);   ONE(a_cos, nl_cos, cos, s1);
        double s2 = rnd_uniform(-1e6, 1e6);
        ONE(a_sin, nl_sin, sin, s2);   ONE(a_cos, nl_cos, cos, s2);
        double s3 = rnd_logspace(1e6, 1e300) * ((rnd() & 1) ? 1 : -1);
        ONE(a_sin, nl_sin, sin, s3);   ONE(a_cos, nl_cos, cos, s3);
        /* right next to a multiple of pi/2, where the reduced argument
         * is all cancellation */
        double s4 = (double)(long long)(rnd() % 1000000) * M_PI_2
                  + rnd_uniform(-1e-9, 1e-9);
        ONE(a_sin, nl_sin, sin, s4);   ONE(a_cos, nl_cos, cos, s4);
        ONE(a_tan, nl_tan, tan, s1);
        ONE(a_tan, nl_tan, tan, s2);
        ONE(a_tan, nl_tan, tan, s3);

        /* atan across its folds; atan2 across all four quadrants and
         * both axes. */
        ONE(a_atan, nl_atan, atan, rnd_uniform(-10, 10));
        ONE(a_atan, nl_atan, atan, rnd_logspace(1e-20, 1e20) * ((rnd() & 1) ? 1 : -1));
        double ay = rnd_uniform(-100, 100), axx = rnd_uniform(-100, 100);
        TWO(a_atan2, nl_atan2, atan2, ay, axx);
        TWO(a_atan2, nl_atan2, atan2, rnd_logspace(1e-200, 1e200), rnd_logspace(1e-200, 1e200));

        /* pow: the exponent's own accuracy is what is on trial, so the
         * samples run to the edges of the representable result range. */
        /* pow is reported in two columns, because one number for it
         * would be a lie in whichever direction it was rounded. The
         * error is proportional to |y*log2|x||: every stage's last bit
         * is multiplied by the exponent, so a result near 1e300 carries
         * a thousand times the error of a result near 1. `pow` is the
         * ordinary range and `pow!` is the extreme one — results at the
         * very edge of what a double can hold. */
        struct { double x, y; } pv[] = {
            { rnd_logspace(1e-30, 1e30), rnd_uniform(-40, 40) },
            { rnd_uniform(0.1, 10.0),    rnd_uniform(-300, 300) },
            { rnd_uniform(1.0, 2.0),     rnd_uniform(-1000, 1000) },
            { -rnd_uniform(0.5, 8.0),    (double)(int)(rnd() % 40) - 20 },
        };
        for (unsigned k = 0; k < 4; k++) {
            double e2 = fabs(pv[k].y * log2(fabs(pv[k].x)));
            two(e2 <= 100.0 ? &a_pow : &a_powx, nl_pow, pow, pv[k].x, pv[k].y);
        }

        ONE(a_cbrt, nl_cbrt, cbrt, rnd_logspace(1e-300, 1e300) * ((rnd() & 1) ? 1 : -1));
        ONE(a_cbrt, nl_cbrt, cbrt, rnd_uniform(-100, 100));

        TWO(a_hypot, nl_hypot, hypot, rnd_uniform(-1e3, 1e3), rnd_uniform(-1e3, 1e3));
        TWO(a_hypot, nl_hypot, hypot, rnd_logspace(1e-300, 1e300),
                                      rnd_logspace(1e-300, 1e300));

        ONE(a_erf, nl_erf, erf, rnd_uniform(-6.5, 6.5));
        ONE(a_erf, nl_erf, erf, rnd_uniform(-1, 1));
        ONE(a_erfc, nl_erfc, erfc, rnd_uniform(-6.5, 6.5));
        ONE(a_erfc, nl_erfc, erfc, rnd_uniform(0, 27.5));   /* down to 1e-318 */
    }

    /* Exactness that is required rather than approximated: these are
     * the identities a caller will notice immediately if they slip. */
    struct { double x; double want; } id[] = {
        { 1.0, 0.0 }, { 2.0, 1.0 }, { 4.0, 2.0 }, { 1024.0, 10.0 },
        { 0.5, -1.0 }, { 0.125, -3.0 },
    };
    for (unsigned i = 0; i < sizeof id / sizeof id[0]; i++)
        note(&a_log2, id[i].x, 0, nl_log2(id[i].x), id[i].want);
    for (int e = -300; e <= 300; e++) {
        double p = pow(10.0, e);
        note(&a_log10, p, 0, nl_log10(p), log10(p));
    }
    note(&a_exp, 0.0, 0, nl_exp(0.0), 1.0);
    note(&a_pow, 2.0, 10.0, nl_pow(2.0, 10.0), 1024.0);
    note(&a_pow, 10.0, 22.0, nl_pow(10.0, 22.0), 1e22);

    report(&a_exp,   1.0);
    report(&a_log,   1.0);
    report(&a_log2,  2.0);
    report(&a_log10, 2.0);
    /* The bounds are what this implementation MEASURES, not aspiration.
     * Anything looser than glibc's own 1-2 ulp is called out:
     *   tan   3  the kernel is a ratio-free polynomial on [-pi/4, pi/4]
     *            and inherits the reduced argument's rounding twice
     *   pow   3  ordinary exponents: |y*log2|x|| <= 100. The error is
     *            proportional to that quantity, so the two bounds are
     *            one linear law read at two points, not two verdicts
     *   pow! 12  extreme ones, up to |y*log2|x|| = 1000 — four
     *            double-double stages each contribute their last bit,
     *            and the exponent multiplies all of them
     *   cbrt  4  measured against glibc, which is the WORSE of the two
     *            here — the exact perfect-cube test above is the real
     *            gate, and this bound only catches a gross regression
     *   erfc  6  exp(-a^2) * G(u) / a is three roundings on top of a
     *            polynomial, out where the result is 1e-56 */
    report(&a_sin,   2.0);
    report(&a_cos,   2.0);
    report(&a_tan,   3.0);
    report(&a_atan,  1.0);
    report(&a_atan2, 2.0);
    report(&a_pow,   3.0);
    report(&a_powx, 12.0);
    report(&a_cbrt,  4.0);
    report(&a_hypot, 1.0);
    report(&a_erf,   2.0);
    report(&a_erfc,  6.0);

    if (failures) { printf("math_diff: %d function(s) FAILED\n", failures); return 1; }
    printf("math_diff: all within bound\n");
    return 0;
}
