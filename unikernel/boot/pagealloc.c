/*
 * NURL unikernel — unikernel/boot/pagealloc.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The guest's page allocator: what `mmap` and `munmap` are made of when
 * there is no kernel underneath to keep a page table of who owns what.
 *
 * WHY THIS FILE EXISTS. The first version was a bump pointer and a
 * `munmap` that returned success without doing anything. That is fine
 * for a program that runs once and exits, and wrong for the thing this
 * target is for: a server. Measured, before this file: a guest with 256
 * MiB that allocates a megabyte and frees it, four hundred times over,
 * dies on the two hundred and fiftieth — every large allocation the
 * program gave back was gone for good. A unikernel that cannot serve its
 * two-hundred-and-fifty-first request is not a unikernel.
 *
 * WHAT IT IS. A sorted free list of page-aligned ranges over one
 * contiguous region, best fit, with coalescing on both sides. Nothing
 * cleverer, on purpose: the allocator above this one (nolibc's
 * size-class malloc) already handles small objects and asks for
 * megabyte arenas, so this one sees few, large, long-lived requests —
 * exactly the shape first fit and best fit disagree about least, and
 * exactly the shape where a bug is a corrupted heap rather than a slow
 * one.
 *
 * PORTABLE C, and that is the point: it has no idea what a page table
 * or a hypervisor is, so `unikernel/tests/pagealloc_fuzz.c` runs it on
 * the host against a model that tracks every live range and checks, on
 * every operation, that no two of them overlap. A page allocator that is
 * only ever exercised inside a virtual machine is a page allocator whose
 * bugs arrive as a triple fault.
 *
 * SPLITTING RANGES COSTS A SLOT. The free list is a fixed array because
 * an allocator that allocates is a bootstrapping problem. If it fills —
 * 256 disjoint holes, which needs a pathological pattern — a freed range
 * that cannot be recorded is COUNTED in `pa_lost` rather than dropped
 * silently, and `pa_stats` reports it. A leak you can see is a bug
 * report; a leak you cannot is a mystery six months later.
 */

typedef unsigned long pa_size_t;

#define PA_PAGE      4096UL
#define PA_MAX_FREE  256

struct pa_range {
    pa_size_t base;
    pa_size_t len;
};

static struct pa_range pa_free_list[PA_MAX_FREE];
static int             pa_nfree;

static pa_size_t pa_base;        /* the region, as given to pa_init */
static pa_size_t pa_next;        /* the tail nobody has ever been handed */
static pa_size_t pa_end;
static pa_size_t pa_live;        /* bytes currently handed out */
static pa_size_t pa_peak;        /* the most that was ever live at once */
static pa_size_t pa_lost_bytes;  /* freed, but the list had no room */

static pa_size_t pa_round(pa_size_t n) {
    return (n + PA_PAGE - 1) & ~(PA_PAGE - 1);
}

/* The region is [base, base+len), page-aligned by the caller's own
 * rounding. Called once, before anything asks for memory. */
void pa_init(pa_size_t base, pa_size_t len) {
    pa_base = pa_round(base);
    pa_next = pa_base;
    pa_end  = base + len;
    if (pa_end < pa_next) pa_end = pa_next;
    pa_nfree = 0;
    pa_live = 0;
    pa_peak = 0;
    pa_lost_bytes = 0;
}

static void pa_insert(int at, pa_size_t base, pa_size_t len) {
    for (int i = pa_nfree; i > at; i--) pa_free_list[i] = pa_free_list[i - 1];
    pa_free_list[at].base = base;
    pa_free_list[at].len  = len;
    pa_nfree++;
}

static void pa_remove(int at) {
    for (int i = at; i < pa_nfree - 1; i++) pa_free_list[i] = pa_free_list[i + 1];
    pa_nfree--;
}

/* Best fit: the smallest hole that still fits. With few, large requests
 * the difference from first fit is small, and it is in this direction —
 * first fit shaves the front of the biggest hole and leaves the next big
 * request without one. */
pa_size_t pa_alloc(pa_size_t want) {
    pa_size_t need = pa_round(want);
    if (need == 0) return 0;

    int best = -1;
    for (int i = 0; i < pa_nfree; i++) {
        if (pa_free_list[i].len < need) continue;
        if (best < 0 || pa_free_list[i].len < pa_free_list[best].len) best = i;
    }
    if (best >= 0) {
        pa_size_t p = pa_free_list[best].base;
        if (pa_free_list[best].len == need) pa_remove(best);
        else {
            pa_free_list[best].base += need;
            pa_free_list[best].len  -= need;
        }
        pa_live += need;
        if (pa_live > pa_peak) pa_peak = pa_live;
        return p;
    }

    /* Nothing reusable: carve from the tail. */
    if (pa_end - pa_next < need) return 0;
    pa_size_t p = pa_next;
    pa_next += need;
    pa_live += need;
    if (pa_live > pa_peak) pa_peak = pa_live;
    return p;
}

/* A free range that ends where the tail begins IS the tail: rolling it
 * back keeps the list short and, more importantly, keeps the region's
 * end in one piece. Without this the last hole and the untouched tail
 * are adjacent and never merge, and a request for "almost all of it"
 * fails on a machine that is entirely free. */
static void pa_absorb_tail(void) {
    while (pa_nfree > 0 &&
           pa_free_list[pa_nfree - 1].base + pa_free_list[pa_nfree - 1].len == pa_next) {
        pa_next = pa_free_list[pa_nfree - 1].base;
        pa_nfree--;
    }
}

/* Give a range back. `len` is the length that was asked for, rounded the
 * same way the allocation rounded it — a caller that frees a different
 * length than it allocated is a bug in the caller, and this allocator
 * has no header to check it against, which is the price of not spending
 * a word on every page. */
/* Is this range one of ours? The same bounds test `pa_free` makes,
 * exposed because the caller has something to do BEFORE handing a range
 * back — see `munmap` in the platform files: a page that was protected
 * while it was in use has to be made writable again before it returns
 * to the pool, and doing that to a mapping that is not ours would be a
 * write to somebody else's page tables. */
int pa_owns(pa_size_t p, pa_size_t len) {
    pa_size_t n = pa_round(len);
    if (p == 0 || n == 0) return 0;
    if (p < pa_base || p + n > pa_end || p + n < p) return 0;
    return 1;
}

int pa_free(pa_size_t p, pa_size_t len) {
    pa_size_t n = pa_round(len);
    if (p == 0 || n == 0) return 0;
    /* Outside the region, or wrapped: not ours, and recording it would
     * hand it out later. */
    if (p < pa_base || p + n > pa_end || p + n < p) return -1;

    pa_live = pa_live >= n ? pa_live - n : 0;

    /* Returning the tail is not a hole at all: it is the tail again.
     * Checked before the list is consulted, so a program that allocates
     * and frees in order never fills the list — and, at the other end,
     * so a full list cannot lose a range that did not need a slot. */
    if (p + n == pa_next) {
        pa_next = p;
        pa_absorb_tail();
        return 0;
    }

    /* Sorted insert, coalescing with the neighbour on each side. */
    int at = 0;
    while (at < pa_nfree && pa_free_list[at].base < p) at++;

    int join_prev = at > 0 &&
        pa_free_list[at - 1].base + pa_free_list[at - 1].len == p;
    int join_next = at < pa_nfree && p + n == pa_free_list[at].base;

    if (join_prev && join_next) {
        pa_free_list[at - 1].len += n + pa_free_list[at].len;
        pa_remove(at);
    } else if (join_prev) {
        pa_free_list[at - 1].len += n;
    } else if (join_next) {
        pa_free_list[at].base = p;
        pa_free_list[at].len += n;
    } else if (pa_nfree < PA_MAX_FREE) {
        pa_insert(at, p, n);
    } else {
        pa_lost_bytes += n;
        return -1;
    }
    pa_absorb_tail();
    return 0;
}

/* What the machine can still hand out, in bytes: the untouched tail plus
 * every hole. A caller that wants to know whether the next megabyte will
 * work wants the largest hole instead, which is why both are here. */
void pa_stats(pa_size_t *live, pa_size_t *peak, pa_size_t *avail,
              pa_size_t *largest, pa_size_t *lost, int *holes) {
    pa_size_t sum = pa_end - pa_next;
    pa_size_t big = pa_end - pa_next;
    for (int i = 0; i < pa_nfree; i++) {
        sum += pa_free_list[i].len;
        if (pa_free_list[i].len > big) big = pa_free_list[i].len;
    }
    if (live)    *live    = pa_live;
    if (peak)    *peak    = pa_peak;
    if (avail)   *avail   = sum;
    if (largest) *largest = big;
    if (lost)    *lost    = pa_lost_bytes;
    if (holes)   *holes   = pa_nfree;
}
