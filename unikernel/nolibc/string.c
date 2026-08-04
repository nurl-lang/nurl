/*
 * NURL nolibc — unikernel/nolibc/string.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Byte loops, deliberately. The plan's own note on this: `strcmp` is the
 * hottest of these in a self-compile (84 call sites), and a
 * word-at-a-time version can read past the end of a page and fault, so
 * the plain loop ships first and anything cleverer waits for a profile
 * that demands it AND the aligned-read technique that makes it safe.
 *
 * A subtlety that is NOT optional: clang recognises these loops and may
 * rewrite them into calls to memcpy/memset — including inside the very
 * functions that define them, which recurses until the stack ends.
 * `-fno-builtin` on this file is what prevents that, and the build
 * script passes it; the __attribute__((optnone)) fallbacks are not used
 * because they would cost the loops their speed everywhere else.
 */
#include "nolibc.h"

void *memcpy(void *d, const void *s, nl_size_t n) {
    unsigned char *dst = (unsigned char *)d;
    const unsigned char *src = (const unsigned char *)s;
    nl_size_t i;
    /* Word-at-a-time while both sides are aligned and there is a word
     * left: same page-safety argument as strcmp — a copy never reads
     * past `n`, so widening is safe here in a way it is not there. */
    if (((unsigned long)dst % 8) == 0 && ((unsigned long)src % 8) == 0) {
        unsigned long *dw = (unsigned long *)d;
        const unsigned long *sw = (const unsigned long *)s;
        for (i = 0; i + 8 <= n; i += 8) *dw++ = *sw++;
        dst += i; src += i;
        for (; i < n; i++) *dst++ = *src++;
        return d;
    }
    for (i = 0; i < n; i++) dst[i] = src[i];
    return d;
}

void *memmove(void *d, const void *s, nl_size_t n) {
    unsigned char *dst = (unsigned char *)d;
    const unsigned char *src = (const unsigned char *)s;
    nl_size_t i;
    if (dst == src || n == 0) return d;
    if (dst < src) { for (i = 0; i < n; i++) dst[i] = src[i]; return d; }
    for (i = n; i > 0; i--) dst[i - 1] = src[i - 1];
    return d;
}

void *memset(void *d, int c, nl_size_t n) {
    unsigned char *dst = (unsigned char *)d;
    unsigned char v = (unsigned char)c;
    nl_size_t i;
    if (((unsigned long)dst % 8) == 0) {
        unsigned long w = 0x0101010101010101UL * v;
        unsigned long *dw = (unsigned long *)d;
        for (i = 0; i + 8 <= n; i += 8) *dw++ = w;
        dst += i;
        for (; i < n; i++) *dst++ = v;
        return d;
    }
    for (i = 0; i < n; i++) dst[i] = v;
    return d;
}

void *memchr(const void *s, int c, nl_size_t n) {
    const unsigned char *p = (const unsigned char *)s;
    unsigned char v = (unsigned char)c;
    nl_size_t i;
    for (i = 0; i < n; i++) if (p[i] == v) return (void *)(p + i);
    return 0;
}

int memcmp(const void *a, const void *b, nl_size_t n) {
    const unsigned char *x = (const unsigned char *)a;
    const unsigned char *y = (const unsigned char *)b;
    nl_size_t i;
    for (i = 0; i < n; i++) if (x[i] != y[i]) return (int)x[i] - (int)y[i];
    return 0;
}

/* clang emits calls to bcmp for `memcmp(...) == 0` comparisons. Same
 * function, and the sign of the result is explicitly unspecified. */
int bcmp(const void *a, const void *b, nl_size_t n) { return memcmp(a, b, n); }

nl_size_t strlen(const char *s) {
    const char *p = s;
    while (*p) p++;
    return (nl_size_t)(p - s);
}

int strcmp(const char *a, const char *b) {
    const unsigned char *x = (const unsigned char *)a;
    const unsigned char *y = (const unsigned char *)b;
    while (*x && *x == *y) { x++; y++; }
    return (int)*x - (int)*y;
}
