/*
 * NURL runtime — stdlib/runtime_wasm_alloc.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * A locked heap for the wasi-threads build, and ONLY for it.
 *
 * wasm32's libc allocator is single-threaded by design — zig's is
 * `std.heap.WasmAllocator`, documented as "appropriate for WebAssembly …
 * in single-threaded release modes" — and there is no seam to lock it
 * from outside: `--wrap` is not available through zig's linker driver,
 * and no `dl*`-style alias is exported. Two guest threads allocating at
 * once would corrupt the heap, and NURL allocates on every string and
 * vector.
 *
 * So this file provides the whole C allocation surface itself. Defining
 * these symbols means the libc object that would define them is never
 * pulled from the archive, which is why the list has to be COMPLETE —
 * miss one and the linker pulls that object in for it and then reports a
 * duplicate `malloc`. Everything the guest allocates now goes through one
 * mutex, including allocations made inside libc (stdio buffers, strdup).
 *
 * The allocator itself is deliberately the boring one: an
 * address-ordered free list with splitting and coalescing over an arena
 * grown with `memory.grow`. First fit, 16-byte alignment, an 16-byte
 * header per block. An interpreter runs the guest ~50x slower than
 * native, so allocator constant factors are not what anyone will notice;
 * being obviously correct is.
 *
 * Included by runtime.c BEFORE the rest, so every later `malloc` in the
 * runtime's own C is this one.
 */

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdatomic.h>

#define NURL_WA_ALIGN 16u
/* Grow by at least this much, so a run of small allocations does not
 * make a memory.grow call each time. */
#define NURL_WA_CHUNK (1024u * 1024u)

typedef struct NurlWaBlk {
    uint32_t size;   /* total block size, header included */
    uint32_t free;   /* 1 when on the free list */
    struct NurlWaBlk *next;  /* free-list link, address-ordered */
} NurlWaBlk;

/* sizeof(NurlWaBlk) is 12 on wasm32; the payload still has to start
 * 16-byte aligned, so the header occupies a full alignment unit. */
#define NURL_WA_HDR NURL_WA_ALIGN

static NurlWaBlk *nurl_wa_free_list = NULL;
static _Atomic int32_t nurl_wa_lock = 0;

/* The same three-state futex mutex the pthread shim uses. Kept separate
 * so the allocator never depends on pthread's own initialisation. */
static void nurl_wa_acquire(void) {
    int32_t expected = 0;
    if (atomic_compare_exchange_strong(&nurl_wa_lock, &expected, 1)) return;
    do {
        expected = 1;
        if (atomic_load(&nurl_wa_lock) == 2 ||
            atomic_compare_exchange_strong(&nurl_wa_lock, &expected, 2))
            __builtin_wasm_memory_atomic_wait32((int32_t*)&nurl_wa_lock, 2, -1);
        expected = 0;
    } while (!atomic_compare_exchange_strong(&nurl_wa_lock, &expected, 2));
}

static void nurl_wa_release(void) {
    if (atomic_fetch_sub(&nurl_wa_lock, 1) != 1) {
        atomic_store(&nurl_wa_lock, 0);
        __builtin_wasm_memory_atomic_notify((int32_t*)&nurl_wa_lock, 1);
    }
}

static uint32_t nurl_wa_round(uint32_t n) {
    return (n + (NURL_WA_ALIGN - 1)) & ~(NURL_WA_ALIGN - 1);
}

/* Insert `b` into the address-ordered free list, coalescing with the
 * neighbours it touches. */
static void nurl_wa_insert(NurlWaBlk *b) {
    b->free = 1;
    NurlWaBlk **link = &nurl_wa_free_list;
    while (*link && (uintptr_t)*link < (uintptr_t)b) link = &(*link)->next;
    b->next = *link;
    *link = b;
    /* forward merge */
    if (b->next && (uint8_t*)b + b->size == (uint8_t*)b->next) {
        b->size += b->next->size;
        b->next = b->next->next;
    }
    /* backward merge: find the predecessor again (the list is short in
     * practice and this keeps the structure a single pointer) */
    if (link != &nurl_wa_free_list) {
        NurlWaBlk *p = nurl_wa_free_list;
        while (p && p->next != b) p = p->next;
        if (p && (uint8_t*)p + p->size == (uint8_t*)b) {
            p->size += b->size;
            p->next = b->next;
        }
    }
}

/* Take `bytes` of fresh linear memory from memory.grow. */
static NurlWaBlk *nurl_wa_arena(uint32_t bytes) {
    uint32_t want = bytes < NURL_WA_CHUNK ? NURL_WA_CHUNK : bytes;
    uint32_t pages = (want + 65535u) / 65536u;
    intptr_t prev = __builtin_wasm_memory_grow(0, (uintptr_t)pages);
    if (prev < 0) return NULL;
    NurlWaBlk *b = (NurlWaBlk*)((uintptr_t)prev * 65536u);
    b->size = pages * 65536u;
    b->free = 0;
    b->next = NULL;
    return b;
}

static void *nurl_wa_alloc(size_t n) {
    if (n == 0) n = 1;
    if (n > 0xF0000000u) return NULL;
    uint32_t need = nurl_wa_round((uint32_t)n) + NURL_WA_HDR;

    NurlWaBlk **link = &nurl_wa_free_list;
    NurlWaBlk *b = NULL;
    while (*link) {
        if ((*link)->size >= need) { b = *link; *link = b->next; break; }
        link = &(*link)->next;
    }
    if (!b) {
        b = nurl_wa_arena(need);
        if (!b) return NULL;
    }
    /* split when the tail is worth keeping */
    if (b->size >= need + NURL_WA_HDR + NURL_WA_ALIGN) {
        NurlWaBlk *rest = (NurlWaBlk*)((uint8_t*)b + need);
        rest->size = b->size - need;
        rest->free = 0;
        rest->next = NULL;
        b->size = need;
        nurl_wa_insert(rest);
    }
    b->free = 0;
    b->next = NULL;
    return (uint8_t*)b + NURL_WA_HDR;
}

void *malloc(size_t n) {
    nurl_wa_acquire();
    void *p = nurl_wa_alloc(n);
    nurl_wa_release();
    return p;
}

void free(void *p) {
    if (!p) return;
    NurlWaBlk *b = (NurlWaBlk*)((uint8_t*)p - NURL_WA_HDR);
    nurl_wa_acquire();
    if (!b->free) nurl_wa_insert(b);  /* a double free is ignored, not fatal */
    nurl_wa_release();
}

size_t malloc_usable_size(void *p) {
    if (!p) return 0;
    NurlWaBlk *b = (NurlWaBlk*)((uint8_t*)p - NURL_WA_HDR);
    return b->size - NURL_WA_HDR;
}

void *calloc(size_t n, size_t m) {
    size_t total = n * m;
    if (n != 0 && total / n != m) return NULL;
    void *p = malloc(total);
    if (p) memset(p, 0, total);
    return p;
}

void *realloc(void *p, size_t n) {
    if (!p) return malloc(n);
    if (n == 0) { free(p); return NULL; }
    NurlWaBlk *b = (NurlWaBlk*)((uint8_t*)p - NURL_WA_HDR);
    size_t have = b->size - NURL_WA_HDR;
    if (have >= n) return p;
    void *q = malloc(n);
    if (!q) return NULL;
    memcpy(q, p, have);
    free(p);
    return q;
}

void *reallocarray(void *p, size_t n, size_t m) {
    size_t total = n * m;
    if (n != 0 && total / n != m) return NULL;
    return realloc(p, total);
}

/* Alignments above 16 are served by over-allocating and storing the
 * block's own start just below the aligned pointer, so `free` still
 * finds a header where it expects one. */
void *aligned_alloc(size_t align, size_t n) {
    if (align <= NURL_WA_ALIGN) return malloc(n);
    size_t extra = align + NURL_WA_HDR;
    uint8_t *raw = (uint8_t*)malloc(n + extra);
    if (!raw) return NULL;
    uintptr_t aligned = ((uintptr_t)raw + extra) & ~(uintptr_t)(align - 1);
    NurlWaBlk *orig = (NurlWaBlk*)(raw - NURL_WA_HDR);
    NurlWaBlk *shim = (NurlWaBlk*)(aligned - NURL_WA_HDR);
    shim->size = (uint32_t)(orig->size - (uintptr_t)(aligned - (uintptr_t)raw));
    shim->free = 0;
    shim->next = NULL;
    return (void*)aligned;
}

void *memalign(size_t align, size_t n) { return aligned_alloc(align, n); }

void *valloc(size_t n) { return aligned_alloc(65536, n); }

int posix_memalign(void **out, size_t align, size_t n) {
    if (!out) return 22;  /* EINVAL */
    void *p = aligned_alloc(align, n);
    if (!p) return 12;    /* ENOMEM */
    *out = p;
    return 0;
}
