/*
 * NURL nolibc — unikernel/nolibc/dtoa.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * `%f`, `%e` and `%g` for the printf in stdio.c — exactly, at any
 * precision, with no floating-point arithmetic anywhere in the
 * conversion.
 *
 * This is NOT the same problem the runtime solves in runtime_core §2b.
 * That one asks "what is the SHORTEST decimal that reads back as this
 * double" and answers it with a 125-bit table. C's `%g` asks something
 * else: "round this double to P significant digits", P defaulting to 6,
 * and 0.1 at six digits is 0.100000 — a question about the value's real
 * decimal expansion, not about round-tripping. Two questions, two
 * algorithms; sharing one would give the wrong answer to one of them.
 *
 * The expansion is finite and can be written down exactly, which is
 * what this does:
 *
 *     value = m · 2^e   with m < 2^53
 *     e >= 0:  N = m · 2^e,        value = N            (an integer)
 *     e <  0:  N = m · 5^(-e),     value = N · 10^e
 *
 * because m/2^k = m·5^k/10^k. So one bignum multiply by a power of five
 * (or a shift) produces every digit the double has — at most ~770 of
 * them — and rounding to P of them is then a decision about digits we
 * are holding, not an estimate. `-e` reaches 1074 for a subnormal, so
 * N reaches ~2500 bits; the buffer is sized for that and the bound is
 * checked rather than trusted.
 */
#include "nolibc.h"

#define NL_DTOA_W    96      /* u32 limbs: 5^1074 needs 79 */
#define NL_DTOA_DIGS 800     /* decimal digits of the largest N */

struct nl_bignum { unsigned int w[NL_DTOA_W]; int n; };

static void nl_bn_set(struct nl_bignum *b, unsigned long long v) {
    b->w[0] = (unsigned int)v;
    b->w[1] = (unsigned int)(v >> 32);
    b->n = b->w[1] ? 2 : (b->w[0] ? 1 : 0);
}

static int nl_bn_mul(struct nl_bignum *b, unsigned int m) {
    unsigned long long carry = 0;
    int i;
    for (i = 0; i < b->n; i++) {
        unsigned long long t = (unsigned long long)b->w[i] * m + carry;
        b->w[i] = (unsigned int)t;
        carry = t >> 32;
    }
    while (carry) {
        if (b->n >= NL_DTOA_W) return 0;          /* would truncate: refuse */
        b->w[b->n++] = (unsigned int)carry;
        carry >>= 32;
    }
    return 1;
}

static int nl_bn_shl(struct nl_bignum *b, int bits) {
    int words = bits >> 5, sh = bits & 31, i;
    if (b->n == 0) return 1;
    if (sh) {
        unsigned int carry = 0;
        for (i = 0; i < b->n; i++) {
            unsigned int nv = (b->w[i] << sh) | carry;
            carry = (unsigned int)((unsigned long long)b->w[i] >> (32 - sh));
            b->w[i] = nv;
        }
        if (carry) {
            if (b->n >= NL_DTOA_W) return 0;
            b->w[b->n++] = carry;
        }
    }
    if (words) {
        if (b->n + words > NL_DTOA_W) return 0;
        for (i = b->n - 1; i >= 0; i--) b->w[i + words] = b->w[i];
        for (i = 0; i < words; i++) b->w[i] = 0;
        b->n += words;
    }
    return 1;
}

/* b /= 1e9, returning the remainder — the digit pump. */
static unsigned int nl_bn_div1e9(struct nl_bignum *b) {
    unsigned long long rem = 0;
    int i;
    for (i = b->n - 1; i >= 0; i--) {
        unsigned long long cur = (rem << 32) | b->w[i];
        b->w[i] = (unsigned int)(cur / 1000000000ULL);
        rem = cur % 1000000000ULL;
    }
    while (b->n && b->w[b->n - 1] == 0) b->n--;
    return (unsigned int)rem;
}

/* Every decimal digit of the double, most significant first.
 * Returns the digit count, writes the decimal exponent of the FIRST
 * digit into *exp10 (value = 0.d1d2… · 10^(exp10+1)), or -1 if the
 * value is not finite. `digits` needs NL_DTOA_DIGS bytes. */
static int nl_exact_digits(double v, char *digits, int *exp10) {
    unsigned long long bits, mant;
    unsigned int be;
    int e2, k, nd = 0, i, j;
    struct nl_bignum b;
    char group[10];

    memcpy(&bits, &v, 8);
    be = (unsigned int)((bits >> 52) & 0x7ff);
    mant = bits & 0xfffffffffffffULL;
    if (be == 0x7ff) return -1;
    if (be == 0) { e2 = -1074; }
    else { mant |= 1ULL << 52; e2 = (int)be - 1075; }
    if (mant == 0) { digits[0] = '0'; *exp10 = 0; return 1; }

    nl_bn_set(&b, mant);
    if (e2 >= 0) {
        if (!nl_bn_shl(&b, e2)) return -1;
        k = 0;                                    /* value = N */
    } else {
        k = -e2;                                  /* value = N · 10^-k */
        /* 5^k by chunks of 5^13, the largest power of five in a u32. */
        for (i = k; i >= 13; i -= 13) if (!nl_bn_mul(&b, 1220703125u)) return -1;
        { static const unsigned int p5[13] = { 1u, 5u, 25u, 125u, 625u, 3125u,
              15625u, 78125u, 390625u, 1953125u, 9765625u, 48828125u, 244140625u };
          int rest = k % 13;
          if (rest && !nl_bn_mul(&b, p5[rest])) return -1; }
    }

    /* Pump nine digits at a time, least significant first, then reverse. */
    while (b.n) {
        unsigned int r = nl_bn_div1e9(&b);
        for (i = 0; i < 9; i++) { group[i] = (char)('0' + r % 10u); r /= 10u; }
        for (i = 0; i < 9; i++) {
            if (nd >= NL_DTOA_DIGS) return -1;
            digits[nd++] = group[i];
        }
    }
    while (nd > 1 && digits[nd - 1] == '0') nd--;   /* leading zeros, reversed */
    for (i = 0, j = nd - 1; i < j; i++, j--) { char t = digits[i]; digits[i] = digits[j]; digits[j] = t; }
    /* value = digits · 10^-k, so the first digit's place value is: */
    *exp10 = nd - 1 - k;
    /* Trailing zeros carry no information for a formatter that pads. */
    while (nd > 1 && digits[nd - 1] == '0') nd--;
    return nd;
}

/* Round the digit string to `keep` significant digits, half away from
 * zero — which is what every libc's printf does for the decimal
 * expansion of a binary float (the expansion is exact, so a tie is a
 * real tie, and C leaves the rule to the implementation; glibc rounds
 * half to even on the EXACT value, and an exact tie can only happen
 * when the remaining digits are exactly 5 followed by zeros). */
static int nl_round_digits(char *d, int nd, int keep, int *exp10) {
    int i, tie = 1;
    if (keep >= nd) return nd;
    if (keep <= 0) {
        /* Every digit is below the last place we keep — `%.4f` of
         * 8.87e-5, say. It rounds to nothing, UNLESS it can carry one
         * into that place, which only the digit immediately below can
         * do. Getting this wrong prints 0.0000 for a number that is
         * 0.0001, and it is invisible in any test whose values happen
         * to be larger than their precision. */
        int carry = 0;
        if (keep == 0 && nd > 0) {
            if (d[0] > '5') carry = 1;
            else if (d[0] == '5') {
                for (i = 1; i < nd; i++) if (d[i] != '0') { carry = 1; break; }
                /* an exact tie rounds to even, and the digit above an
                 * empty result is an implicit 0 — so it stays 0 */
            }
        }
        if (carry) { d[0] = '1'; (*exp10)++; return 1; }
        return 0;
    }
    if (d[keep] < '5') return keep;
    if (d[keep] == '5') {
        for (i = keep + 1; i < nd; i++) if (d[i] != '0') { tie = 0; break; }
        /* exact tie -> to even, matching glibc on the exact value */
        if (tie && ((d[keep - 1] - '0') & 1) == 0) return keep;
    }
    for (i = keep - 1; i >= 0; i--) {
        if (d[i] != '9') { d[i]++; return keep; }
        d[i] = '0';
    }
    /* every digit was 9: 999 -> 1000, one place further left */
    d[0] = '1';
    (*exp10)++;
    return keep;
}

/* The printf-side entry point. `conv` is 'f', 'e' or 'g'; `prec` is the
 * precision as C defines it for that conversion (6 when unspecified);
 * `alt` is the '#' flag. Writes into out (>= 1100 bytes) and returns
 * the length. */
int nl_format_double(char *out, double v, char conv, int prec, int alt) {
    char digits[NL_DTOA_DIGS];
    int nd, exp10, i, o = 0, neg;
    unsigned long long bits;

    memcpy(&bits, &v, 8);
    neg = (int)(bits >> 63);
    if (((bits >> 52) & 0x7ff) == 0x7ff) {
        const char *s = (bits & 0xfffffffffffffULL) ? "nan"
                      : (neg ? "-inf" : "inf");
        while (*s) out[o++] = *s++;
        return o;
    }
    if (neg) out[o++] = '-';

    nd = nl_exact_digits(v, digits, &exp10);
    if (nd < 0) { out[o++] = '?'; return o; }

    if (conv == 'g') {
        int P = prec == 0 ? 1 : prec;
        int keep;
        nd = nl_round_digits(digits, nd, P, &exp10);
        keep = nd;
        /* C's rule: style e when the exponent is < -4 or >= P. */
        if (exp10 < -4 || exp10 >= P) conv = 'e';
        else conv = 'f';
        if (!alt) {                       /* %g drops trailing zeros */
            while (keep > 1 && digits[keep - 1] == '0') keep--;
            nd = keep;
        }
        prec = (conv == 'e') ? nd - 1 : nd - 1 - exp10;
        if (prec < 0) prec = 0;
    }

    if (conv == 'e') {
        int ex, a;
        nd = nl_round_digits(digits, nd, prec + 1, &exp10);
        out[o++] = nd > 0 ? digits[0] : '0';
        if (prec > 0 || alt) {
            out[o++] = '.';
            for (i = 1; i <= prec; i++) out[o++] = i < nd ? digits[i] : '0';
        }
        out[o++] = 'e';
        ex = exp10;
        out[o++] = ex < 0 ? '-' : '+';
        a = ex < 0 ? -ex : ex;
        if (a >= 100) out[o++] = (char)('0' + a / 100);
        out[o++] = (char)('0' + (a / 10) % 10);
        out[o++] = (char)('0' + a % 10);
        return o;
    }

    /* style f: exp10 is the place value of the first digit */
    nd = nl_round_digits(digits, nd, exp10 + 1 + prec, &exp10);
    if (exp10 < 0) {
        out[o++] = '0';
    } else {
        for (i = 0; i <= exp10; i++) out[o++] = i < nd ? digits[i] : '0';
    }
    if (prec > 0 || alt) {
        out[o++] = '.';
        for (i = 1; i <= prec; i++) {
            int idx = exp10 + i;              /* digit index for 10^-i */
            out[o++] = (idx >= 0 && idx < nd) ? digits[idx] : '0';
        }
    }
    return o;
}
