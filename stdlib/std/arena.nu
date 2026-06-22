// stdlib/std/arena.nu — bump-pointer arena allocator.
//
// An `Arena` hands out 8-byte-aligned pointers in O(1) bump. It comes in
// two flavours that share one API:
//
//   * FIXED   — a single contiguous buffer of a chosen capacity.
//               `arena_alloc` returns NULL once the buffer is full.
//               Construct with `arena_new` / `arena_with_cap`.
//   * GROWING — a linked list of chunks. When the current chunk can't
//               satisfy a request the arena allocates a fresh chunk and
//               keeps allocating; pointers handed out from earlier chunks
//               stay valid (chunks are never realloc'd or moved). This is
//               the canonical arena model. Construct with `arena_growing`.
//
// `arena_reset` invalidates every outstanding pointer and rewinds the
// bump cursor — the buffer (FIXED) or the base chunk (GROWING) is kept
// for reuse; any extra chunks are released. `arena_free` releases
// everything.
//
// Designed for parser / AST / regex-NFA / per-request workloads:
// hundreds of small allocations whose lifetimes are tied to a single
// outer scope. One `arena_free` at the end instead of one free per
// allocation. No need to track per-allocation ownership.
//
// API:
//
//   ( arena_new )              → Arena    empty FIXED arena (cap = 0)
//   ( arena_with_cap n )       → Arena    FIXED arena, buffer preallocated
//   ( arena_growing chunk_sz ) → Arena    GROWING arena; chunks default to
//                                          `chunk_sz` bytes (a larger request
//                                          gets its own exact-fit chunk)
//   ( arena_alloc a n )        → *u       8-byte aligned, NULL on OOM
//   ( arena_alloc_aligned a n align ) → *u   custom alignment
//   ( arena_alloc_n [T] a count ) → *T    typed: count items of T, 8-aligned
//   ( arena_used a )           → i        total bytes consumed (all chunks)
//   ( arena_cap a )            → i        total capacity (all chunks)
//   ( arena_remaining a )      → i        bytes left in the current chunk
//   ( arena_chunk_count a )    → i        number of live chunks (>1 ⇒ grew)
//   ( arena_reset a )          → v        rewind to empty, keep base storage
//   ( arena_free a )           → v        release every chunk + handle
//
// Memory model:
//
//   * `Arena { s ctl }` is a single-pointer handle to a heap-allocated
//     `ArenaImpl`. Passing an Arena by value copies the 8-byte handle
//     — every copy shares the same chunk list + bump cursor. Same
//     opaque-handle pattern as `Channel` and `String`.
//   * `arena_alloc` returns a BORROWED pointer into a chunk's buffer.
//     Pointers are valid until `arena_reset` (invalidates ALL
//     outstanding pointers) or `arena_free`. Never `nurl_free` a
//     pointer returned by `arena_alloc` — the arena owns the storage.
//   * A GROWING arena keeps every pointer valid across growth: new
//     chunks are linked in, old ones are never moved or freed until
//     reset/free. A FIXED arena returns NULL when the next allocation
//     would exceed `cap`; callers MUST check.
//   * Default alignment is 8 bytes: sufficient for `i64`, `f64`,
//     pointers, and any single-pointer-handle struct on x86-64 /
//     AArch64 targets NURL ships to. `arena_alloc_aligned` covers
//     SIMD (16 / 32) or byte-tight (1) cases. (Custom alignment aligns
//     the offset within the chunk and so assumes the chunk's base
//     pointer is at least as aligned, which `nurl_alloc` provides for
//     the 8/16-byte cases in practice.)
//
// Lifecycle pattern (fixed):
//
//   : Arena ar ( arena_with_cap 65536 )
//   : *u p1 ( arena_alloc ar 128 )
//   : *u p2 ( arena_alloc ar 512 )
//   // ... use p1, p2 freely; they live until arena_reset / arena_free
//   ( arena_free ar )    // releases buffer + handle
//
// Reset-and-reuse pattern (per-request workloads, regex engine):
//
//   : Arena scratch ( arena_growing 16384 )
//   ~ have_work {
//       ( do_work scratch )      // allocates into `scratch`, growing if needed
//       ( arena_reset scratch )  // rewind, keep the base chunk, ready again
//   }
//   ( arena_free scratch )

// One contiguous buffer + its bump cursor. A GROWING arena links these
// into a list (`next` points at the previously-current chunk); a FIXED
// arena has exactly one. `next` is a self-referential pointer field —
// NURL resolves the forward reference to `ArenaChunk` itself.
: ArenaChunk {
    * u data
    i used
    i cap
    * ArenaChunk next
}

: ArenaImpl {
    * ArenaChunk head  // current chunk to allocate from (newest)
    * ArenaChunk base  // first chunk ever created (kept across reset); 0 if none
    i chunk_sz  // 0 = FIXED (no auto-grow); >0 = GROWING default chunk size
}

: Arena { s ctl }

// ── Internal chunk helpers ───────────────────────────────────────────

// Allocate one chunk with a `cap`-byte buffer. Returns NULL on OOM (and
// frees the partial allocation so nothing leaks).
@ __arena_new_chunk i cap → *ArenaChunk {
    : *ArenaChunk c # *ArenaChunk ( nurl_alloc Z ArenaChunk )
    ? == 0 # i c { ^ # *ArenaChunk 0 } {}
    : *u buf # *u ( nurl_alloc cap )
    ? == 0 # i buf {
        ( nurl_free # s c )
        ^ # *ArenaChunk 0
    } {}
    = . c data buf
    = . c used 0
    = . c cap cap
    = . c next # *ArenaChunk 0
    ^ c
}

@ __arena_free_chunk * ArenaChunk c → v {
    ? != 0 # i . c data { ( nurl_free # s . c data ) } {}
    ( nurl_free # s c )
}

@ __arena_sum_used * ArenaChunk head → i {
    : ~ i acc 0
    : ~ * ArenaChunk cur head
    ~ != 0 # i cur {
        = acc + acc . cur used
        = cur . cur next
    }
    ^ acc
}

@ __arena_sum_cap * ArenaChunk head → i {
    : ~ i acc 0
    : ~ * ArenaChunk cur head
    ~ != 0 # i cur {
        = acc + acc . cur cap
        = cur . cur next
    }
    ^ acc
}

// ── Constructors ─────────────────────────────────────────────────────

@ arena_new → Arena {
    : *ArenaImpl impl # *ArenaImpl ( nurl_alloc Z ArenaImpl )
    = . impl head # *ArenaChunk 0
    = . impl base # *ArenaChunk 0
    = . impl chunk_sz 0
    ^ @ Arena { # s impl }
}

@ arena_with_cap i n → Arena {
    : Arena a ( arena_new )
    ? > n 0 {
        : *ArenaImpl impl # *ArenaImpl . a ctl
        : *ArenaChunk c ( __arena_new_chunk n )
        = . impl head c
        = . impl base c
    } {}
    ^ a
}

// A growing arena. `chunk_sz` is the default size of each chunk; a
// request larger than `chunk_sz` gets its own exact-fit chunk so a
// single big allocation never wastes a whole default chunk. The first
// chunk is created lazily on the first allocation.
@ arena_growing i chunk_sz → Arena {
    : Arena a ( arena_new )
    : *ArenaImpl impl # *ArenaImpl . a ctl
    = . impl chunk_sz ? > chunk_sz 0 chunk_sz 1
    ^ a
}

// ── Inspectors ───────────────────────────────────────────────────────

@ arena_used Arena a → i {
    : *ArenaImpl impl # *ArenaImpl . a ctl
    ^ ( __arena_sum_used . impl head )
}

@ arena_cap Arena a → i {
    : *ArenaImpl impl # *ArenaImpl . a ctl
    ^ ( __arena_sum_cap . impl head )
}

// Bytes left in the CURRENT chunk before a grow (FIXED: cap − used).
@ arena_remaining Arena a → i {
    : *ArenaImpl impl # *ArenaImpl . a ctl
    : *ArenaChunk h . impl head
    ? == 0 # i h { ^ 0 } {}
    ^ - . h cap . h used
}

@ arena_chunk_count Arena a → i {
    : *ArenaImpl impl # *ArenaImpl . a ctl
    : ~ i n 0
    : ~ * ArenaChunk cur . impl head
    ~ != 0 # i cur {
        = n + n 1
        = cur . cur next
    }
    ^ n
}

// ── Allocation ───────────────────────────────────────────────────────

// Allocate `n` bytes, 8-byte aligned. FIXED: NULL once the buffer is
// full. GROWING: links a fresh chunk and never returns NULL unless the
// underlying `nurl_alloc` itself fails.
@ arena_alloc Arena a i n → *u {
    ? <= n 0 { ^ # *u 0 } {}
    : *ArenaImpl impl # *ArenaImpl . a ctl
    : *ArenaChunk h . impl head
    // Try the current head chunk first.
    ? != 0 # i h {
        : i used_aligned & + . h used 7 -8
        : i needed + used_aligned n
        ? <= needed . h cap {
            : *u p # *u + # i . h data used_aligned
            = . h used needed
            ^ p
        } {}
    } {}
    // Head full (or none yet). FIXED arena → OOM.
    ? <= . impl chunk_sz 0 { ^ # *u 0 } {}
    // GROWING arena → new chunk big enough for n (default size, or exact
    // fit for an oversized request).
    : i want ? > n . impl chunk_sz n . impl chunk_sz
    : *ArenaChunk nc ( __arena_new_chunk want )
    ? == 0 # i nc { ^ # *u 0 } {}
    = . nc next . impl head
    = . impl head nc
    ? == 0 # i . impl base { = . impl base nc } {}
    : *u p # *u # i . nc data
    = . nc used n
    ^ p
}

// Allocate `n` bytes with the requested alignment. `align` must be a
// power of two; `align <= 1` means no alignment. FIXED: NULL on
// overflow (after alignment). GROWING: a fresh chunk if the head can't
// satisfy the aligned request.
@ arena_alloc_aligned Arena a i n i align → *u {
    ? <= n 0 { ^ # *u 0 } {}
    : *ArenaImpl impl # *ArenaImpl . a ctl
    : *ArenaChunk h . impl head
    ? != 0 # i h {
        // Align `used` UP to `align`: `(used + align-1) & -align`. -align
        // is two's-complement all-ones with the low log2(align) bits zero.
        : ~ i used_aligned . h used
        ? > align 1 {
            : i mask - align 1
            = used_aligned & + . h used mask - 0 align
        } {}
        : i needed + used_aligned n
        ? <= needed . h cap {
            : *u p # *u + # i . h data used_aligned
            = . h used needed
            ^ p
        } {}
    } {}
    ? <= . impl chunk_sz 0 { ^ # *u 0 } {}
    // GROWING arena: a fresh chunk's `nurl_alloc` base is already
    // 8/16-byte aligned and its cursor starts at 0, so the aligned offset
    // is 0 — allocate `n` straight from the chunk's base.
    : i base_want ? > n . impl chunk_sz n . impl chunk_sz
    : *ArenaChunk nc ( __arena_new_chunk base_want )
    ? == 0 # i nc { ^ # *u 0 } {}
    = . nc next . impl head
    = . impl head nc
    ? == 0 # i . impl base { = . impl base nc } {}
    : *u p # *u # i . nc data
    = . nc used n
    ^ p
}

// Typed allocation: `count` contiguous items of T, 8-byte aligned.
// Returns a borrowed `*T` into the arena (NULL on OOM, like
// `arena_alloc`). Never `nurl_free` it — the arena owns the storage.
@ arena_alloc_n [T] Arena a i count → *T {
    ? <= count 0 { ^ # *T 0 } {}
    ^ # *T ( arena_alloc a * count Z T )
}

// ── Lifecycle ────────────────────────────────────────────────────────

// Rewind to empty. All previously-issued pointers become invalid. The
// base chunk's buffer is retained for reuse; any extra chunks a GROWING
// arena added are released.
@ arena_reset Arena a → v {
    : *ArenaImpl impl # *ArenaImpl . a ctl
    : *ArenaChunk base . impl base
    ? != 0 # i base {
        // Free every chunk from head down to (but not including) base.
        : ~ * ArenaChunk cur . impl head
        ~ != # i cur # i base {
            : *ArenaChunk nxt . cur next
            ( __arena_free_chunk cur )
            = cur nxt
        }
        = . base used 0
        = . base next # *ArenaChunk 0
        = . impl head base
    } {}
}

// Release every chunk and the impl block. After this the handle is dead
// — do not pass it to any other arena_* function.
@ arena_free Arena a → v {
    : *ArenaImpl impl # *ArenaImpl . a ctl
    : ~ * ArenaChunk cur . impl head
    ~ != 0 # i cur {
        : *ArenaChunk nxt . cur next
        ( __arena_free_chunk cur )
        = cur nxt
    }
    ( nurl_free # s impl )
}
