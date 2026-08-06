/*
 * NURL nolibc — unikernel/nolibc/malloc.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Size-class allocator over anonymous mappings. Small requests come out
 * of per-class free lists carved from 1 MiB arenas; anything past the
 * largest class gets its own mapping and gives it back on free.
 *
 * Single-threaded by design, and that is a *checked* assumption, not a
 * hope: the freestanding profile has one vCPU and cooperative fibers
 * (unikernel plan B0), so there is no preemption point inside these
 * functions. If that ever changes, the fix is a lock here, not an
 * atomic sprinkled somewhere else — and the assumption is stated at the
 * one place a reader will look.
 *
 * The runtime asks for `malloc_usable_size`, so every block carries its
 * class size in a header word; that also makes realloc's "does it still
 * fit?" test free.
 */
#include "nolibc.h"

extern void *nl_map(nl_size_t len);
extern int   nl_unmap(void *p, nl_size_t len);

#define NL_ALIGN     16
#define NL_ARENA     (1UL << 20)          /* 1 MiB per carve */
#define NL_CLASSES   9                    /* 32 … 8192 bytes */
#define NL_MAXSMALL  (32UL << (NL_CLASSES - 1))

struct nl_head {
    nl_size_t size;      /* usable bytes (class size, or the mapping) */
    nl_size_t kind;      /* class index, or NL_BIG */
};
#define NL_BIG ((nl_size_t)-1)

static void *nl_free_list[NL_CLASSES];
static unsigned char *nl_arena_p;
static nl_size_t nl_arena_left;

static int nl_class_of(nl_size_t n) {
    nl_size_t sz = 32;
    int c = 0;
    while (c < NL_CLASSES && sz < n) { sz <<= 1; c++; }
    return c < NL_CLASSES ? c : -1;
}
static nl_size_t nl_class_size(int c) { return 32UL << c; }

static void *nl_carve(nl_size_t bytes) {
    if (nl_arena_left < bytes) {
        nl_size_t want = bytes > NL_ARENA ? bytes : NL_ARENA;
        unsigned char *p = (unsigned char *)nl_map(want);
        if (!p) return 0;
        /* The tail of the old arena is abandoned rather than tracked:
         * at most one class size per megabyte, and a free-list entry
         * for it would cost more code than the bytes are worth. */
        nl_arena_p = p;
        nl_arena_left = want;
    }
    { void *r = nl_arena_p; nl_arena_p += bytes; nl_arena_left -= bytes; return r; }
}

void *malloc(nl_size_t n) {
    struct nl_head *h;
    int c;
    if (n == 0) n = 1;
    /* A length that cannot have a header and a page of rounding added to
     * it is a length no allocation can satisfy. Saying so here is not
     * pedantry: without it `n + sizeof(head)` wraps, lands in a small
     * size class, and a request for nearly the whole address space is
     * answered with a 32-byte block — which the caller then fills. Sizes
     * near the top come from length arithmetic on attacker-supplied
     * numbers often enough that this is the ordinary case, not the
     * exotic one. */
    if (n > (nl_size_t)-1 - sizeof(struct nl_head) - 4095) return 0;
    c = nl_class_of(n + sizeof(struct nl_head));
    if (c < 0) {                                   /* big: its own mapping */
        nl_size_t total = n + sizeof(struct nl_head);
        total = (total + 4095) & ~(nl_size_t)4095;
        h = (struct nl_head *)nl_map(total);
        if (!h) return 0;
        h->size = total - sizeof(struct nl_head);
        h->kind = NL_BIG;
        return (void *)(h + 1);
    }
    if (nl_free_list[c]) {
        void *p = nl_free_list[c];
        nl_free_list[c] = *(void **)p;             /* next pointer lives in
                                                    * the free block itself */
        h = (struct nl_head *)p;
        h->size = nl_class_size(c) - sizeof(struct nl_head);
        h->kind = (nl_size_t)c;
        return (void *)(h + 1);
    }
    h = (struct nl_head *)nl_carve(nl_class_size(c));
    if (!h) return 0;
    h->size = nl_class_size(c) - sizeof(struct nl_head);
    h->kind = (nl_size_t)c;
    return (void *)(h + 1);
}

void free(void *p) {
    struct nl_head *h;
    if (!p) return;
    h = ((struct nl_head *)p) - 1;
    if (h->kind == NL_BIG) {
        nl_unmap(h, h->size + sizeof(struct nl_head));
        return;
    }
    *(void **)h = nl_free_list[h->kind];
    nl_free_list[h->kind] = h;
}

nl_size_t malloc_usable_size(void *p) {
    if (!p) return 0;
    return (((struct nl_head *)p) - 1)->size;
}

void *calloc(nl_size_t n, nl_size_t sz) {
    nl_size_t total;
    void *p;
    if (n && sz && n > (nl_size_t)-1 / sz) return 0;   /* overflow is a NULL,
                                                        * never a short block */
    total = n * sz;
    p = malloc(total);
    if (p) memset(p, 0, total);
    return p;
}

void *realloc(void *p, nl_size_t n) {
    struct nl_head *h;
    void *q;
    nl_size_t old;
    if (!p) return malloc(n);
    if (n == 0) { free(p); return 0; }
    h = ((struct nl_head *)p) - 1;
    old = h->size;
    if (n <= old) return p;                       /* still fits its class */
    q = malloc(n);
    if (!q) return 0;
    memcpy(q, p, old);
    free(p);
    return q;
}
