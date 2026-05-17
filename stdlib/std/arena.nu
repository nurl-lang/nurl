// stdlib/std/arena.nu — bump-pointer arena allocator.
//
// An `Arena` owns a single contiguous byte buffer. `arena_alloc`
// hands out 8-byte-aligned pointers into that buffer in O(1) bump.
// `arena_reset` invalidates every outstanding pointer and rewinds
// the bump cursor to 0 — the buffer can be reused. `arena_free`
// releases the buffer.
//
// Designed for parser / AST / regex-NFA / per-request workloads:
// hundreds of small allocations whose lifetimes are tied to a single
// outer scope. Single `nurl_free` at the end instead of one per
// allocation. No need to track per-allocation ownership.
//
// API:
//
//   ( arena_new )              → Arena                empty (cap = 0)
//   ( arena_with_cap n )       → Arena                preallocated
//   ( arena_alloc a n )        → *u                   8-byte aligned, NULL on OOM
//   ( arena_alloc_aligned a n align ) → *u            custom alignment
//   ( arena_used a )           → i                    bytes consumed
//   ( arena_cap a )            → i                    buffer capacity
//   ( arena_remaining a )      → i                    cap - used
//   ( arena_reset a )          → v                    rewind to empty, keep buffer
//   ( arena_free a )           → v                    release buffer + handle
//
// Memory model:
//
//   * `Arena { s ctl }` is a single-pointer handle to a heap-allocated
//     `ArenaImpl`. Passing an Arena by value copies the 8-byte handle
//     — every copy shares the same underlying buffer + bump cursor.
//     This is the same opaque-handle pattern as `Channel` and `String`.
//   * `arena_alloc` returns a BORROWED pointer into the arena's
//     buffer. Pointers are valid until `arena_reset` (invalidates
//     ALL outstanding pointers) or `arena_free` (frees the buffer
//     entirely). Never `nurl_free` a pointer returned by
//     `arena_alloc` — the arena owns the storage.
//   * `arena_alloc` returns NULL when the next allocation would
//     exceed `cap`. Callers MUST check. The arena does not grow
//     automatically (growth would require either reallocating the
//     buffer — invalidating outstanding pointers — or chaining
//     additional chunks; both are explicit follow-ups, not v1).
//   * Default alignment is 8 bytes: sufficient for `i64`, `f64`,
//     pointers, and any single-pointer-handle struct on x86-64 /
//     AArch64 targets NURL ships to. `arena_alloc_aligned` covers
//     SIMD (16 / 32) or byte-tight (1) cases.
//
// Lifecycle pattern:
//
//   : Arena ar ( arena_with_cap 65536 )
//   : *u p1 ( arena_alloc ar 128 )
//   : *u p2 ( arena_alloc ar 512 )
//   // ... use p1, p2 freely; they live until arena_reset / arena_free
//   ( arena_free ar )    // releases buffer + handle
//
// Reset-and-reuse pattern (per-request workloads, regex engine):
//
//   : Arena scratch ( arena_with_cap 16384 )
//   ~ have_work {
//       ( do_work scratch )   // allocates into `scratch`
//       ( arena_reset scratch ) // rewind, ready for next iteration
//   }
//   ( arena_free scratch )
//
// What this module is NOT (yet):
//
//   * A growing arena. `arena_alloc` returns NULL on OOM; it does
//     not realloc the buffer (would invalidate outstanding pointers)
//     nor chain additional chunks (would need a linked list of
//     buffers). Both are tractable v2 work — chained chunks keep
//     pointer validity and is the canonical arena model.
//   * A typed allocator. `arena_alloc` returns `*u` (byte pointer);
//     callers cast to `*T` via `# *T ptr`. A generic
//     `arena_alloc_n [T] arena count → *T` wrapper is straight-line
//     work atop the byte allocator; defer until a real call site
//     asks for it.

$ `stdlib/core/string.nu`
$ `stdlib/core/mem.nu`

: ArenaImpl {
    *u data
    i used
    i cap
}

: Arena { s ctl }

// ── Constructors ─────────────────────────────────────────────────────

@ arena_new → Arena {
    : *ArenaImpl impl # *ArenaImpl ( nurl_alloc Z ArenaImpl )
    = . impl data # *u 0
    = . impl used 0
    = . impl cap 0
    ^ @ Arena { # s impl }
}

@ arena_with_cap i n → Arena {
    : Arena a ( arena_new )
    ? > n 0 {
        : *ArenaImpl impl # *ArenaImpl . a ctl
        : *u buf # *u ( nurl_alloc n )
        = . impl data buf
        = . impl cap n
    } {}
    ^ a
}

// ── Inspectors ───────────────────────────────────────────────────────

@ arena_used Arena a → i {
    : *ArenaImpl impl # *ArenaImpl . a ctl
    ^ . impl used
}

@ arena_cap Arena a → i {
    : *ArenaImpl impl # *ArenaImpl . a ctl
    ^ . impl cap
}

@ arena_remaining Arena a → i {
    : *ArenaImpl impl # *ArenaImpl . a ctl
    ^ - . impl cap . impl used
}

// ── Allocation ───────────────────────────────────────────────────────

// Allocate `n` bytes, 8-byte aligned. Returns NULL on overflow.
@ arena_alloc Arena a i n → *u {
    ? <= n 0 { ^ # *u 0 } {}
    : *ArenaImpl impl # *ArenaImpl . a ctl
    // Align `used` UP to the next 8-byte boundary. `& (x + 7) -8` =
    // `(x + 7) & ~7` since -8 is two's-complement all-ones-with-low-
    // three-bits-zero.
    : i used_aligned & + . impl used 7 -8
    : i needed + used_aligned n
    ? > needed . impl cap { ^ # *u 0 } {}
    : *u p # *u + # i . impl data used_aligned
    = . impl used needed
    ^ p
}

// Allocate `n` bytes with the requested alignment. `align` must be a
// power of two. `align <= 1` is treated as no-alignment. Returns NULL
// on overflow (after alignment).
@ arena_alloc_aligned Arena a i n i align → *u {
    ? <= n 0 { ^ # *u 0 } {}
    : *ArenaImpl impl # *ArenaImpl . a ctl
    : ~ i used_aligned . impl used
    ? > align 1 {
        : i mask - align 1
        = used_aligned & + . impl used mask - 0 align
    } {}
    : i needed + used_aligned n
    ? > needed . impl cap { ^ # *u 0 } {}
    : *u p # *u + # i . impl data used_aligned
    = . impl used needed
    ^ p
}

// ── Lifecycle ────────────────────────────────────────────────────────

// Rewind to empty. All previously-issued pointers become invalid.
// The underlying buffer is retained for reuse.
@ arena_reset Arena a → v {
    : *ArenaImpl impl # *ArenaImpl . a ctl
    = . impl used 0
}

// Release the buffer and the impl block. After this the handle is
// dead — do not pass it to any other arena_* function.
@ arena_free Arena a → v {
    : *ArenaImpl impl # *ArenaImpl . a ctl
    ? != 0 # i . impl data {
        ( nurl_free # s . impl data )
    } {}
    ( nurl_free # s impl )
}
