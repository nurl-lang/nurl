/*
 * NURL unikernel — unikernel/tests/pagealloc_fuzz.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The guest's page allocator, fuzzed on the host against a model.
 *
 * `boot/pagealloc.c` is what `mmap` and `munmap` are made of inside the
 * unikernel, and inside the unikernel a bug in it is a triple fault with
 * nothing printed. So it is written as portable C with no idea what a
 * page table is, and this file runs it here, where a bug is a line of
 * output instead.
 *
 * The oracle is not "it didn't crash" — a bump allocator never crashes
 * and that is exactly what was wrong with the one this replaced. It is a
 * model of every live range, checked on every operation:
 *
 *   1. no two live ranges overlap, ever — the failure mode that turns
 *      into two objects sharing memory;
 *   2. every range is inside the region and page-aligned;
 *   3. accounting agrees: the allocator's own `live` equals the sum of
 *      the model's ranges;
 *   4. nothing is lost — after freeing everything, one allocation of the
 *      WHOLE region must succeed. That is coalescing, stated as a
 *      property rather than as an inspection of the free list, and it
 *      is what a version that forgets to merge neighbours fails.
 *
 * The region is a real mmap'd block on the host, so the addresses the
 * allocator hands out are addresses this test can actually write to —
 * and it writes a pattern derived from each range's identity and checks
 * it on free, which catches an overlap even if the model somehow agrees.
 */
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>

typedef unsigned long pa_size_t;

void          pa_init(pa_size_t base, pa_size_t len);
pa_size_t     pa_alloc(pa_size_t want);
int           pa_free(pa_size_t p, pa_size_t len);
void          pa_stats(pa_size_t *live, pa_size_t *peak, pa_size_t *avail,
                       pa_size_t *largest, pa_size_t *lost, int *holes);

#define PAGE      4096UL
#define REGION    (64UL * 1024 * 1024)
#define SLOTS     192
#define OPS       200000

struct slot { pa_size_t p, n; unsigned seed; };
static struct slot slot[SLOTS];

static unsigned long long rng = 0x9E3779B97F4A7C15ULL;
static unsigned long long rnd(void) {
    rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17;
    return rng;
}

static pa_size_t region_base;

static void fill(struct slot *s) {
    unsigned char *p = (unsigned char *)s->p;
    unsigned x = s->seed;
    /* One byte per page is enough to catch an overlap and keeps the
     * fuzzer's own cost off the profile. */
    for (pa_size_t off = 0; off < s->n; off += PAGE) {
        x = x * 1103515245u + 12345u;
        p[off] = (unsigned char)(x >> 16);
    }
}
static int verify(struct slot *s) {
    unsigned char *p = (unsigned char *)s->p;
    unsigned x = s->seed;
    for (pa_size_t off = 0; off < s->n; off += PAGE) {
        x = x * 1103515245u + 12345u;
        if (p[off] != (unsigned char)(x >> 16)) return 0;
    }
    return 1;
}

static int overlaps(int k, pa_size_t p, pa_size_t n) {
    for (int i = 0; i < SLOTS; i++) {
        if (i == k || !slot[i].p) continue;
        if (p < slot[i].p + slot[i].n && slot[i].p < p + n) return 1;
    }
    return 0;
}

int main(void) {
    void *region = mmap(0, REGION, PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (region == MAP_FAILED) { printf("mmap failed\n"); return 1; }
    region_base = (pa_size_t)region;
    pa_init(region_base, REGION);

    long allocs = 0, frees = 0, refusals = 0;
    pa_size_t model_live = 0;

    for (long i = 0; i < OPS; i++) {
        int k = (int)(rnd() % SLOTS);
        struct slot *s = &slot[k];

        if (s->p) {
            if (!verify(s)) {
                printf("pattern mismatch in slot %d at %#lx (%lu bytes) — "
                       "two live ranges share memory\n", k, s->p, s->n);
                return 1;
            }
            if (pa_free(s->p, s->n) != 0) {
                printf("pa_free refused a range it handed out: %#lx+%lu\n",
                       s->p, s->n);
                return 1;
            }
            model_live -= s->n;
            frees++;
            s->p = 0;
            continue;
        }

        /* A mix of sizes: single pages, the megabyte arenas nolibc's
         * malloc asks for, the occasional large one that only fits when
         * the free list has coalesced — and sizes that are NOT page
         * multiples, because `mmap` takes a length in bytes and rounding
         * it is this allocator's job. A version that skips the rounding
         * hands out misaligned addresses and overlapping ranges, and
         * without this case nothing here would notice. */
        pa_size_t want;
        switch (rnd() % 5) {
        case 0:  want = PAGE * (1 + rnd() % 4); break;
        case 1:  want = PAGE * (16 + rnd() % 64); break;
        case 2:  want = 1024UL * 1024; break;
        case 3:  want = 1 + rnd() % (8 * PAGE); break;      /* ragged */
        default: want = PAGE * (256 + rnd() % 512); break;
        }
        pa_size_t rounded = (want + PAGE - 1) & ~(PAGE - 1);
        pa_size_t p = pa_alloc(want);
        if (!p) { refusals++; continue; }

        if (p < region_base || p + rounded > region_base + REGION) {
            printf("pa_alloc handed out %#lx+%lu, outside the region\n", p, rounded);
            return 1;
        }
        if (p % PAGE) { printf("pa_alloc handed out a misaligned %#lx\n", p); return 1; }
        if (overlaps(k, p, rounded)) {
            printf("pa_alloc handed out %#lx+%lu, which overlaps a live range\n",
                   p, rounded);
            return 1;
        }
        s->p = p; s->n = rounded; s->seed = (unsigned)rnd() | 1;
        fill(s);
        model_live += rounded;
        allocs++;

        pa_size_t live = 0, lost = 0;
        pa_stats(&live, 0, 0, 0, &lost, 0);
        if (live != model_live) {
            printf("accounting drifted: allocator says %lu live, model says %lu\n",
                   live, model_live);
            return 1;
        }
        if (lost) { printf("the free list overflowed and lost %lu bytes\n", lost); return 1; }
    }

    /* Everything back, and then the whole region in one piece: the
     * property that says the holes really did merge. */
    for (int i = 0; i < SLOTS; i++) {
        if (!slot[i].p) continue;
        if (!verify(&slot[i])) { printf("pattern mismatch at the end, slot %d\n", i); return 1; }
        pa_free(slot[i].p, slot[i].n);
        slot[i].p = 0;
    }
    pa_size_t live = 0, avail = 0, largest = 0, lost = 0;
    int holes = 0;
    pa_stats(&live, 0, &avail, &largest, &lost, &holes);
    if (live != 0) { printf("after freeing everything, %lu bytes are still live\n", live); return 1; }
    if (lost != 0) { printf("%lu bytes were lost along the way\n", lost); return 1; }

    pa_size_t whole = pa_alloc(REGION - PAGE);
    if (!whole) {
        printf("after freeing everything, the region does not fit in itself: "
               "avail=%lu largest=%lu holes=%d — the free list did not coalesce\n",
               avail, largest, holes);
        return 1;
    }
    pa_free(whole, REGION - PAGE);

    /* Exhaustion is a refusal, not a wild pointer: ask for more than the
     * machine has and the answer must be zero. */
    if (pa_alloc(REGION * 2) != 0) {
        printf("pa_alloc answered a request larger than the region\n");
        return 1;
    }
    /* A range that was never handed out is not ours to record. */
    if (pa_free(region_base - PAGE, PAGE) == 0) {
        printf("pa_free accepted a range outside the region\n");
        return 1;
    }

    /* ── coalescing in the middle, where the tail cannot rescue it ──
     *
     * Random traffic frees most things next to the region's end, and
     * rolling the tail back merges neighbours whether or not the free
     * list does. So the merge is asserted directly instead: eight blocks
     * in a row, the LAST one held live so the tail is blocked, and the
     * other seven freed in order. Seven adjacent holes must become one —
     * ascending frees exercise the merge with the left neighbour and
     * descending frees the merge with the right one, and a version
     * missing either leaves seven holes and cannot answer a request for
     * the seven megabytes it is sitting on.
     */
    for (int pass = 0; pass < 2; pass++) {
        const pa_size_t blk = 1024UL * 1024;
        pa_size_t b[8];
        for (int i = 0; i < 8; i++) {
            b[i] = pa_alloc(blk);
            if (!b[i]) { printf("directed: allocation %d refused\n", i); return 1; }
        }
        for (int i = 0; i < 7; i++) {
            int k = pass == 0 ? i : 6 - i;      /* ascending, then descending */
            pa_free(b[k], blk);
        }
        pa_stats(0, 0, 0, 0, 0, &holes);
        if (holes != 1) {
            printf("directed (%s): seven adjacent holes became %d, not 1 — "
                   "the free list does not coalesce with its %s neighbour\n",
                   pass == 0 ? "ascending" : "descending", holes,
                   pass == 0 ? "left" : "right");
            return 1;
        }
        pa_size_t big = pa_alloc(7 * blk);
        if (!big) {
            printf("directed (%s): seven freed megabytes do not fit in the "
                   "hole they made\n", pass == 0 ? "ascending" : "descending");
            return 1;
        }
        pa_free(big, 7 * blk);
        pa_free(b[7], blk);
    }

    printf("pagealloc fuzz ok: %ld ops (%ld allocs, %ld frees, %ld refusals)\n",
           (long)OPS, allocs, frees, refusals);
    return 0;
}
