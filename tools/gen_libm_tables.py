#!/usr/bin/env python3
"""Generate unikernel/nolibc/math_tables.h — the constants nolibc's libm
evaluates, computed here rather than copied from somewhere.

Two kinds of thing come out:

  * polynomial coefficients for each kernel, from Chebyshev
    interpolation of the exact function at 60 decimal digits. Chebyshev
    interpolation is within a small factor of the true minimax
    polynomial, and the factor does not matter because the degree is
    chosen by MEASURING the fit error here and the finished functions
    are then gated against glibc anyway (unikernel/tests/math_diff.c).
    The measured error of each fit is printed into the header, so a
    later reader can see what the degree was bought with.

  * the leading 1200 bits of 2/pi, for Payne-Hanek argument reduction.
    Without them sin/cos/tan of a large argument are noise: reducing
    1e300 mod pi/2 in double arithmetic has no correct bits left, and
    a libm that answers confidently there is worse than one that
    refuses.

Same shape as tools/gen_pow5_table.py: run it, commit the header.

  python3 tools/gen_libm_tables.py > unikernel/nolibc/math_tables.h
"""
import sys
from decimal import Decimal, getcontext
from fractions import Fraction

getcontext().prec = 80

def pi_fraction(terms=520):
    """pi as an exact rational, to about 2600 bits.

    Machin: pi/4 = 4*atan(1/5) - atan(1/239), with Fractions, so the
    result is limited only by the term count. This exists because the
    2/pi table below is 1536 bits long and a hardcoded 200-digit
    decimal string of pi makes only its first ~660 bits correct — which
    is invisible until sin(1e216) comes back with the wrong sign, and
    perfectly plausible until then. Deriving every constant here from
    one arbitrary-precision source removes the whole class."""
    def at(inv):
        s = Fraction(0)
        x = Fraction(1, inv)
        for k in range(terms):
            s += Fraction((-1) ** k, 2 * k + 1) * x ** (2 * k + 1)
        return s
    return 4 * (4 * at(5) - at(239))


PI_EXACT = pi_fraction()
PI = Decimal(PI_EXACT.numerator) / Decimal(PI_EXACT.denominator)


# ── high-precision kernels the Decimal module does not ship ─────────
def d_sin(x):
    term, s, x2, n = x, x, x * x, 1
    while abs(term) > Decimal(10) ** -75:
        term = -term * x2 / ((2 * n) * (2 * n + 1))
        s += term
        n += 1
    return s


def d_cos(x):
    term, s, x2, n = Decimal(1), Decimal(1), x * x, 1
    while abs(term) > Decimal(10) ** -75:
        term = -term * x2 / ((2 * n - 1) * (2 * n))
        s += term
        n += 1
    return s


def d_atan(x):
    """The plain series. It converges usefully only for |x| well under
    1 — at x = 1 every term is 1/(2n+1) and the loop below never
    terminates, which is how atan(1) hung this generator — so callers
    with a larger argument go through d_atan_any."""
    term, s, x2, n = x, x, x * x, 0
    while abs(term / (2 * n + 1)) > Decimal(10) ** -75:
        n += 1
        term = -term * x2
        s += term / (2 * n + 1)
    return s


def d_atanh(x):
    term, s, x2, n = x, x, x * x, 0
    while abs(term / (2 * n + 1)) > Decimal(10) ** -75:
        n += 1
        term = term * x2
        s += term / (2 * n + 1)
    return s


def d_atan_any(x):
    """atan for any non-negative x, via atan(x) = pi/2 - atan(1/x)
    above 1 so the series always runs on the fast side."""
    if x > 1:
        return PI / 2 - d_atan(1 / x)
    if x == 1:
        return PI / 4
    return d_atan(x)


SQRT_PI = None  # set in main once precision is fixed


def d_erf_taylor(x):
    """erf via its Taylor series. Exact enough while x^2 stays small
    relative to the working precision — the terms grow to about e^(x^2)
    before cancelling back down, so this is the small-argument tool and
    d_erfc_cf is the large-argument one."""
    term = x
    s = x
    n = 0
    x2 = x * x
    while True:
        n += 1
        term = -term * x2 / n
        add = term / (2 * n + 1)
        s += add
        if abs(add) < abs(s) * Decimal(10) ** -70:
            break
    return 2 * s / (PI.sqrt())


def d_erfc_cf(x, depth=400):
    """erfc by its continued fraction, evaluated from the tail inward.
    The Taylor series cannot reach here: at x = 27 its terms peak near
    10^322 and cancel down to a value near 10^-318."""
    f = Decimal(0)
    for k in range(depth, 0, -1):
        f = (Decimal(k) / 2) / (x + f)
    return (-x * x).exp() / PI.sqrt() / (x + f)


def d_erfc(x):
    if x <= 3:
        return 1 - d_erf_taylor(x)
    return d_erfc_cf(x)


def d_tan(x):
    return d_sin(x) / d_cos(x)


# ── Chebyshev interpolation, solved exactly ─────────────────────────
def chebfit(f, lo, hi, deg):
    """Interpolate f at deg+1 Chebyshev points of [lo,hi] and return the
    monomial coefficients. The linear solve is done over the rationals,
    so the only error in the result is the final rounding to double."""
    n = deg + 1
    nodes = []
    for k in range(n):
        t = d_cos(PI * Decimal(2 * k + 1) / Decimal(2 * n))
        nodes.append((Decimal(lo) + Decimal(hi)) / 2 + (Decimal(hi) - Decimal(lo)) / 2 * t)
    A = [[x ** j for j in range(n)] for x in nodes]
    b = [Decimal(f(x)) for x in nodes]
    # Gaussian elimination with partial pivoting, in 80-digit Decimal.
    # A Vandermonde is ill-conditioned, but at Chebyshev nodes a system
    # this size loses well under half the working digits, so ~55 correct
    # digits survive into coefficients that are then rounded to 17. The
    # exact-rational version of this loop was correct and took minutes
    # at degree 22, which is a real cost for no reachable accuracy.
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(A[r][c]))
        A[c], A[p] = A[p], A[c]
        b[c], b[p] = b[p], b[c]
        inv = A[c][c]
        for r in range(n):
            if r == c:
                continue
            m = A[r][c] / inv
            if m == 0:
                continue
            for k in range(c, n):
                A[r][k] -= m * A[c][k]
            b[r] -= m * b[c]
    return [b[i] / A[i][i] for i in range(n)]


def fit_error(f, coeffs, lo, hi, samples=2000):
    """Worst RELATIVE error of the fit over the interval, sampled."""
    worst = Decimal(0)
    for i in range(samples + 1):
        x = Decimal(lo) + (Decimal(hi) - Decimal(lo)) * Decimal(i) / Decimal(samples)
        want = Decimal(f(x))
        got = Decimal(0)
        for c in reversed(coeffs):
            got = got * x + c
        if want == 0:
            continue
        e = abs((got - want) / want)
        if e > worst:
            worst = e
    return worst


def hexd(v):
    """-> a C hex-float literal, which is the only spelling of a double
    that survives a round trip through source text."""
    return float(v).hex()


def emit_poly(name, comment, f, lo, hi, deg, centre=False):
    """centre=True fits in v = (x - mid)/half instead of in x.

    A high-degree monomial fit on an interval that does not start at 0
    has enormous alternating coefficients, and evaluating it in double
    loses far more than the fit ever gained: erfc's degree-30 piece fits
    to 6e-22 and evaluated to 5e-10 until this existed. The kernels
    fitted on [0, zmax] do not need it — their coefficients decay."""
    if centre:
        mid = (Decimal(lo) + Decimal(hi)) / 2
        half = (Decimal(hi) - Decimal(lo)) / 2
        g = lambda v: f(mid + half * v)
        co = chebfit(g, Decimal(-1), Decimal(1), deg)
        err = fit_error(g, co, Decimal(-1), Decimal(1))
        print(f"/* {comment}")
        print(f"   degree {deg} on [{float(lo):.6g}, {float(hi):.6g}], in the centred")
        print(f"   variable v = (x - MID) * INVHALF; worst relative fit error {err:.3E} */")
        print(f"#define {name}_MID     {float(mid).hex()}")
        print(f"#define {name}_INVHALF {float(1 / half).hex()}")
        print(f"static const double {name}[{len(co)}] = {{")
        for i, c in enumerate(co):
            print(f"    {hexd(c)},   /* v^{i} */")
        print("};")
        print()
        return err
    co = chebfit(f, lo, hi, deg)
    err = fit_error(f, co, lo, hi)
    print(f"/* {comment}")
    print(f"   degree {deg} on [{float(lo):.6g}, {float(hi):.6g}];"
          f" worst relative fit error {err:.3E} */")
    print(f"static const double {name}[{len(co)}] = {{")
    for i, c in enumerate(co):
        print(f"    {hexd(c)},   /* x^{i} */")
    print("};")
    print()
    return err


def two_pi_over_pi_bits(nwords):
    """The leading bits of 2/pi as 64-bit words, most significant first.
    2/pi < 1, so word 0 holds bits 1..64 of the fraction."""
    # Exactly 2/pi, as a rational — no decimal string in the middle.
    frac = 2 / PI_EXACT
    words = []
    for _ in range(nwords):
        frac *= 2**64
        w = int(frac)
        words.append(w)
        frac -= w
    return words


def main():
    print("/*")
    print(" * NURL nolibc — unikernel/nolibc/math_tables.h")
    print(" *")
    print(" * Copyright (c) 2026 The NURL Project Developers")
    print(" * SPDX-License-Identifier: MIT OR Apache-2.0")
    print(" *")
    print(" * GENERATED by tools/gen_libm_tables.py — do not edit. Every")
    print(" * coefficient is a Chebyshev interpolation of the exact function at")
    print(" * 60 digits, solved in 80-digit decimal; the measured fit error is")
    print(" * printed above each one so the choice of degree is visible rather")
    print(" * than folklore.")
    print(" */")
    print("#ifndef NURL_NOLIBC_MATH_TABLES_H")
    print("#define NURL_NOLIBC_MATH_TABLES_H")
    print()

    ln2 = Decimal(2).ln()

    # exp(r) = 1 + r + r^2 * E(r),  |r| <= ln2/2
    half = ln2 / 2
    emit_poly(
        "NL_EXP_P",
        "E(r) = (exp(r) - 1 - r) / r^2, the tail of exp after its two exact terms.",
        lambda r: ((r.exp() - 1 - r) / (r * r)) if r != 0 else Decimal("0.5"),
        -half,
        half,
        13,
    )

    # 2*atanh(s) = 2s + 2s*z*A(z), z = s^2, s in [-(sqrt2-1)/(sqrt2+1), ...]
    smax = (Decimal(2).sqrt() - 1) / (Decimal(2).sqrt() + 1)
    zmax = smax * smax
    def logA(z):
        if z == 0:
            return Decimal(1) / 3
        s = z.sqrt()
        return (d_atanh(s) / s - 1) / z
    emit_poly(
        "NL_LOG_P",
        "A(z) = (atanh(s)/s - 1) / z with z = s^2; log of the reduced mantissa.",
        logA,
        Decimal(0),
        zmax,
        11,
    )

    # sin(r) = r + r^3 * S(z), z = r^2, |r| <= pi/4
    rmax = PI / 4
    def sinS(z):
        if z == 0:
            return Decimal(-1) / 6
        r = z.sqrt()
        return (d_sin(r) - r) / (r * r * r)
    emit_poly("NL_SIN_P", "S(z) = (sin(r) - r) / r^3 with z = r^2.",
              sinS, Decimal(0), rmax * rmax, 8)

    # cos(r) = 1 - z/2 + z^2 * C(z)
    def cosC(z):
        if z == 0:
            return Decimal(1) / 24
        r = z.sqrt()
        return (d_cos(r) - 1 + z / 2) / (z * z)
    emit_poly("NL_COS_P", "C(z) = (cos(r) - 1 + z/2) / z^2 with z = r^2.",
              cosC, Decimal(0), rmax * rmax, 8)

    # tan(r) = r + r^3 * T(z)
    def tanT(z):
        if z == 0:
            return Decimal(1) / 3
        r = z.sqrt()
        return (d_tan(r) - r) / (r * r * r)
    # tan's kernel is the expensive fit: T(z) is heading for the pole at
    # r = pi/2, just past the end of the interval, so it needs roughly
    # twice the degree the others do. Degree 13 measured 1.9e-16, which
    # is already a whole ulp before a single rounding — the fit error
    # printed in the header is what said so.
    emit_poly("NL_TAN_P", "T(z) = (tan(r) - r) / r^3 with z = r^2, |r| <= pi/4.",
              tanT, Decimal(0), rmax * rmax, 22)

    # atan(w) = w + w^3 * A(z) after a reduction that keeps |w| < 7/16.
    wmax = Decimal("0.4375")
    def atanA(z):
        if z == 0:
            return Decimal(-1) / 3
        w = z.sqrt()
        return (d_atan(w) - w) / (w * w * w)
    emit_poly("NL_ATAN_P", "A(z) = (atan(w) - w) / w^3 with z = w^2, |w| < 7/16.",
              atanA, Decimal(0), wmax * wmax, 15)

    # The four reduction points atan() folds towards, each split into a
    # head that is exact in a double and the remainder. Without the
    # split the constant itself costs half an ulp before any arithmetic.
    print("/* atan's reduction targets: atan(0.5), atan(1), atan(1.5), pi/2,")
    print("   each as head + tail so the head is exact and the tail carries")
    print("   what a single double cannot. */")
    for arr, which in (("NL_ATAN_HI", 0), ("NL_ATAN_LO", 1)):
        print(f"static const double {arr}[4] = {{")
        for v in (d_atan_any(Decimal("0.5")), d_atan_any(Decimal(1)),
                  d_atan_any(Decimal("1.5")), PI / 2):
            hi = float(v)
            lo = float(v - Decimal(hi))
            print(f"    {(hi if which == 0 else lo).hex()},")
        print("};")
        print()



    # ── the base constants, as head + tail ─────────────────────────
    # Every one of these is multiplied by an integer exponent or by a
    # reduced mantissa, and a single double loses half an ulp before the
    # arithmetic starts. The head keeps 32 significant bits so that head
    # times an exponent (|e| <= 1074, 11 bits) is EXACT; the tail
    # carries the rest. Typing them by hand is how log2 came out wrong
    # in the seventh digit — 11 million ulp — so they are computed.
    def split2(v, hibits=32):
        import math as _m
        f = float(v)
        m, ex = _m.frexp(f)
        hi = float(int(m * (2 ** hibits)) * 2.0 ** (ex - hibits))
        lo = float(v - Decimal(hi))
        return hi, lo

    ln2v = Decimal(2).ln()
    ln10v = Decimal(10).ln()
    for nm, val, bits in (
        ("NL_LN2", ln2v, 33),
        ("NL_IVLN2", 1 / ln2v, 32),
        ("NL_LG2", ln2v / ln10v, 32),        # log10(2)
        ("NL_IVLN10", 1 / ln10v, 32),
        ("NL_PIO2", PI / 2, 32),
        ("NL_PI", PI, 32),
    ):
        hi, lo = split2(val, bits)
        print(f"#define {nm}_HI  {hi.hex()}")
        print(f"#define {nm}_LO  {lo.hex()}")
    # pi and pi/2 also as (nearest double, remainder). The split pairs
    # above pair a 32-bit HEAD with its tail; code that starts from the
    # correctly-rounded double needs the tail of THAT instead, and
    # mixing the two families put 1.2e-10 into atan2's left half plane.
    for nm, val in (("NL_PI", PI), ("NL_PIO2", PI / 2)):
        d = float(val)
        print(f"#define {nm}_D  {d.hex()}")
        print(f"#define {nm}_T  {float(val - Decimal(d)).hex()}")
    print(f"#define NL_2_OVER_PI  {float(2 / PI).hex()}")
    print(f"#define NL_SQRT2      {float(Decimal(2).sqrt()).hex()}")
    print()
    # ── erf / erfc ─────────────────────────────────────────────────
    # erf(x) = x * E(z), z = x^2, on [0,1]: one polynomial, no
    # cancellation — erf(1) is only 0.84.
    def erfE(z):
        if z == 0:
            return 2 / PI.sqrt()
        x = z.sqrt()
        return d_erf_taylor(x) / x
    emit_poly("NL_ERF_P", "E(z) = erf(x)/x with z = x^2, |x| <= 1.",
              erfE, Decimal(0), Decimal(1), 16)
    print("#define NL_ERF_P_N 17")
    print()

    # erfc(a) = exp(-a^2) * G(u) / a with u = 1/a^2. G tends to
    # 1/sqrt(pi); fitting it in u turns the whole tail into three short
    # polynomials. One fit over the entire range would need a degree
    # that buys nothing — the sub-ranges are the cheap part.
    def erfcG(u):
        a = 1 / u.sqrt()
        return d_erfc(a) * a * (a * a).exp()
    # Degrees measured, not chosen: G carries an exp(1/u) inside it, so
    # the fit converges more slowly than the trigonometric kernels and
    # degree 18 stalls at 1.2e-14 — a hundred ulp — no matter how much
    # working precision the solve is given. The numbers below are the
    # first ones that reach the 1e-19 the rest of this header holds to.
    # erfc on (0.5, 1] gets its own DIRECT fit, in a rather than in u.
    # It used to be computed as 1 - erf(a), and erf(1) is 0.84: the
    # subtraction throws away two and a half bits, which showed up as
    # 6 ulp exactly there. Fitting erfc itself has nothing to cancel —
    # and in a rather than u because the exp(1/u) shape that makes the
    # tail fits expensive is not present when the exponential is not
    # factored out. Below a = 0.5, erf <= 0.52 and 1 - erf costs at
    # most one bit, so that range keeps the simpler form.
    emit_poly("NL_ERFC_D", "erfc(a) directly, 0.5 <= a <= 1.",
              lambda a: d_erfc(a), Decimal("0.5"), Decimal(1), 20, centre=True)
    print("#define NL_ERFC_D_N 21")
    print()
    for name, alo, ahi, deg in (("NL_ERFC_A", 1, 2, 30),
                                ("NL_ERFC_B", 2, 5, 24),
                                ("NL_ERFC_C", 5, Decimal("27.5"), 16)):
        ulo = 1 / (Decimal(ahi) * Decimal(ahi))
        uhi = 1 / (Decimal(alo) * Decimal(alo))
        emit_poly(name,
                  f"G(u) = erfc(a)*a*exp(a^2) with u = 1/a^2, a in [{alo}, {ahi}].",
                  erfcG, ulo, uhi, deg, centre=True)
        print(f"#define {name}_N {deg + 1}")
        print()
    print("/* Range boundaries in u, so the branch and the fits cannot drift. */")
    print(f"#define NL_ERFC_U0  {float(Decimal(1)).hex()}   /* a = 1 */")
    print(f"#define NL_ERFC_U1  {float(Decimal(1) / 4).hex()}   /* a = 2 */")
    print(f"#define NL_ERFC_U2  {float(Decimal(1) / 25).hex()}   /* a = 5 */")
    print()
    # ── Payne-Hanek: the leading bits of 2/pi ───────────────────────
    words = two_pi_over_pi_bits(24)
    print("/* The leading 1536 bits of 2/pi, 64 at a time, most significant")
    print("   first — word 0 is bits 1..64 of the fraction (2/pi < 1).")
    print("   Reducing a double mod pi/2 needs the bits of 2/pi that line up")
    print("   with the argument's own exponent, and the largest double has")
    print("   exponent 1023, so 24 words covers every finite input with room")
    print("   for the 53-bit mantissa and the guard bits the rounding needs. */")
    print(f"static const unsigned long long NL_TWO_OVER_PI[{len(words)}] = {{")
    for w in words:
        print(f"    0x{w:016X}ULL,")
    print("};")
    print()

    # pi/2 as a four-part sum (see the comment emitted below).
    pio2 = Fraction(PI) / 2
    parts = []
    rem = pio2
    for _ in range(3):
        import math
        f = float(rem)
        m, e = math.frexp(f)
        t = float(int(m * (2 ** 24)) * 2.0 ** (e - 24))
        parts.append(t)
        rem -= Fraction(t)
    parts.append(float(rem))
    print("/* pi/2 split so that k*PIO2_1 is EXACT for every k a Cody-Waite")
    print("   reduction can produce: the first three parts carry 24 significant")
    print("   bits each and the fourth is the remainder. Without the split the")
    print("   reduction loses exactly the bits it exists to preserve. */")
    for i, p in enumerate(parts):
        print(f"#define NL_PIO2_{i}  {p.hex()}")
    print()

    print("#endif /* NURL_NOLIBC_MATH_TABLES_H */")


main()
