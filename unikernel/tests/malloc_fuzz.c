/*
 * NURL nolibc — unikernel/tests/malloc_fuzz.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Random-op fuzzer for the nolibc allocator, built with -nostdlib so it
 * exercises the real one rather than glibc's.
 *
 * ASan cannot be pointed at this: it works by REPLACING malloc, so the
 * allocator under test would not run. The oracle is therefore the data
 * itself — every block is filled with a pattern derived from its own
 * identity and re-checked on every touch, so an allocator that hands
 * the same bytes to two live blocks, or loses part of a block across a
 * realloc, corrupts a pattern and the run fails with the block that
 * caught it. Overlap is the failure mode a "it didn't crash" test
 * misses, and it is exactly what a size-class free list gets wrong.
 */
#include "../nolibc/nolibc.h"

#define SLOTS 512
#define OPS   400000

struct slot { unsigned char *p; nl_size_t n; unsigned seed; };
static struct slot slot[SLOTS];

static unsigned long long rng_state = 0x2545F4914F6CDD1DULL;
static unsigned long long rnd(void) {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 7;
    rng_state ^= rng_state << 17;
    return rng_state;
}

static void fill(struct slot *s) {
    nl_size_t i;
    unsigned x = s->seed;
    for (i = 0; i < s->n; i++) {
        x = x * 1103515245u + 12345u;
        s->p[i] = (unsigned char)(x >> 16);
    }
}
static int verify(struct slot *s, nl_size_t upto) {
    nl_size_t i;
    unsigned x = s->seed;
    for (i = 0; i < upto; i++) {
        x = x * 1103515245u + 12345u;
        if (s->p[i] != (unsigned char)(x >> 16)) return 0;
    }
    return 1;
}

int main(void) {
    long i;
    long allocs = 0, reallocs = 0, frees = 0, callocs = 0;
    nl_size_t live_bytes = 0;

    for (i = 0; i < OPS; i++) {
        unsigned k = (unsigned)(rnd() % SLOTS);
        struct slot *s = &slot[k];
        unsigned op = (unsigned)(rnd() % 100);

        if (s->p) {
            if (!verify(s, s->n)) {
                printf("CORRUPT slot %u (%llu bytes) at op %ld\n",
                       k, (unsigned long long)s->n, i);
                return 1;
            }
            if (malloc_usable_size(s->p) < s->n) {
                printf("usable_size %llu < requested %llu at op %ld\n",
                       (unsigned long long)malloc_usable_size(s->p),
                       (unsigned long long)s->n, i);
                return 1;
            }
        }

        if (op < 35 || !s->p) {                        /* allocate */
            nl_size_t n;
            if (s->p) { free(s->p); live_bytes -= s->n; s->p = 0; frees++; }
            n = (nl_size_t)(rnd() % ((rnd() % 8 == 0) ? 200000 : 600)) + 1;
            if (op % 7 == 0) { s->p = (unsigned char *)calloc(n, 1); callocs++; }
            else             { s->p = (unsigned char *)malloc(n); allocs++; }
            if (!s->p) { printf("allocation of %llu failed at op %ld\n",
                                (unsigned long long)n, i); return 1; }
            if (op % 7 == 0) {                          /* calloc must zero */
                nl_size_t j;
                for (j = 0; j < n; j++) if (s->p[j]) {
                    printf("calloc left byte %llu non-zero at op %ld\n",
                           (unsigned long long)j, i);
                    return 1;
                }
            }
            s->n = n;
            s->seed = (unsigned)rnd() | 1u;
            fill(s);
            live_bytes += n;
        } else if (op < 60) {                          /* grow or shrink */
            nl_size_t old = s->n;
            nl_size_t n = (nl_size_t)(rnd() % 4000) + 1;
            unsigned char *q = (unsigned char *)realloc(s->p, n);
            if (!q) { printf("realloc to %llu failed at op %ld\n",
                             (unsigned long long)n, i); return 1; }
            /* realloc keeps min(old, new) bytes — that is the contract,
             * and the pattern check below is what proves it. */
            s->p = q;
            live_bytes += n - old;
            s->n = n;
            if (!verify(s, old < n ? old : n)) {
                printf("realloc lost data (%llu -> %llu) at op %ld\n",
                       (unsigned long long)old, (unsigned long long)n, i);
                return 1;
            }
            fill(s);
            reallocs++;
        } else if (op < 75) {                          /* free */
            free(s->p);
            live_bytes -= s->n;
            s->p = 0;
            frees++;
        }
        /* the remaining 25 % is the verify above, and nothing else:
         * a block that is merely held has to keep its bytes too */
    }

    for (i = 0; i < SLOTS; i++)
        if (slot[i].p && !verify(&slot[i], slot[i].n)) {
            printf("CORRUPT slot %ld at the end\n", i);
            return 1;
        }
    printf("malloc fuzz ok: %ld ops (%ld malloc, %ld calloc, %ld realloc, %ld free)\n",
           (long)OPS, allocs, callocs, reallocs, frees);
    return 0;
}
