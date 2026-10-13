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
//   ( arena_free a )           → v        early release (optional: the last
//                                         owner releases every chunk)
//
// Memory model:
//
//   * `Arena { s ctl }` is a single-pointer handle to a heap-allocated
//     `ArenaImpl`. Passing an Arena by value copies the 8-byte handle
//     — every copy shares the same chunk list + bump cursor, and the
//     last owner releases the chunks. Same opaque-handle pattern as
//     `Channel` and `String`.
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

// One contiguous buffer (a RawBlock, which releases itself) and its bump
// cursor. A GROWING arena keeps its chunks in a Vec, oldest first: the
// first is the base kept across a reset, the last is the one allocations
// come from. A FIXED arena has exactly one. Dropping the arena drops the
// Vec, and with it every chunk — nothing here releases memory by hand.
$ `stdlib/core/mem.nu`
$ `stdlib/core/rcbox.nu`

: ArenaChunk {
    RawBlock data
    i used
    i cap
}

: ArenaImpl {
    ( Vec ArenaChunk ) chunks
    i chunk_sz  // 0 = FIXED (no auto-grow); >0 = GROWING default chunk size
}

: Arena { ( Shared ArenaImpl ) ctl }

// ── Internal chunk helpers ───────────────────────────────────────────

@ __arena_impl Arena a → *ArenaImpl { ^ ( shared_ptr [ArenaImpl] . a ctl ) }

// Append a chunk with a `cap`-byte buffer; the new head.
@ __arena_push_chunk * ArenaImpl impl i cap → *ArenaChunk {
    ( vec_push [ArenaChunk] . impl chunks @ ArenaChunk { ( raw_block cap ) 0 cap } )
    ^ ( __arena_head impl )
}

// The chunk allocations come from (NULL when there is none yet).
@ __arena_head * ArenaImpl impl → *ArenaChunk {
    : i n ( vec_len [ArenaChunk] . impl chunks )
    ? == n 0 { ^ # *ArenaChunk 0 } {}
    ^ # *ArenaChunk + # i ( vec_data [ArenaChunk] . impl chunks ) * - n 1 Z ArenaChunk
}

@ __arena_sum * ArenaImpl impl b caps → i {
    : i n ( vec_len [ArenaChunk] . impl chunks )
    : *ArenaChunk cs ( vec_data [ArenaChunk] . impl chunks )
    : ~ i acc 0
    : ~ i k 0
    ~ < k n {
        = acc + acc ? caps . . cs k cap . . cs k used
        = k + k 1
    }
    ^ acc
}

// ── Constructors ─────────────────────────────────────────────────────

@ arena_new → Arena {
    ^ @ Arena { ( shared_new [ArenaImpl] @ ArenaImpl { ( vec_new [ArenaChunk] ) 0 } ) }
}

@ arena_with_cap i n → Arena {
    : Arena a ( arena_new )
    ? > n 0 { : *ArenaChunk _c ( __arena_push_chunk ( __arena_impl a ) n ) } {}
    ^ a
}

// A growing arena. `chunk_sz` is the default size of each chunk; a
// request larger than `chunk_sz` gets its own exact-fit chunk so a
// single big allocation never wastes a whole default chunk. The first
// chunk is created lazily on the first allocation.
@ arena_growing i chunk_sz → Arena {
    : Arena a ( arena_new )
    = . ( __arena_impl a ) chunk_sz ? > chunk_sz 0 chunk_sz 1
    ^ a
}

// ── Inspectors ───────────────────────────────────────────────────────

@ arena_used Arena a → i { ^ ( __arena_sum ( __arena_impl a ) F ) }

@ arena_cap Arena a → i { ^ ( __arena_sum ( __arena_impl a ) T ) }

// Bytes left in the CURRENT chunk before a grow (FIXED: cap − used).
@ arena_remaining Arena a → i {
    : *ArenaChunk h ( __arena_head ( __arena_impl a ) )
    ? == 0 # i h { ^ 0 } {}
    ^ - . h cap . h used
}

@ arena_chunk_count Arena a → i {
    ^ ( vec_len [ArenaChunk] . ( __arena_impl a ) chunks )
}

// ── Allocation ───────────────────────────────────────────────────────

// Allocate `n` bytes with the requested alignment (`align` a power of two;
// `align <= 1` means none). FIXED: NULL once the buffer is full. GROWING:
// a fresh chunk when the head cannot satisfy the request — its base comes
// from malloc, aligned for 8 and 16 already, so the request starts at 0.
@ __arena_take Arena a i n i align → *u {
    ? <= n 0 { ^ # *u 0 } {}
    : *ArenaImpl impl ( __arena_impl a )
    : *ArenaChunk h ( __arena_head impl )
    ? != 0 # i h {
        : ~ i used_aligned . h used
        ? > align 1 {
            : i mask - align 1
            = used_aligned & + . h used mask - 0 align
        } {}
        : i needed + used_aligned n
        ? <= needed . h cap {
            : *u p # *u + # i ( raw_block_ptr . h data ) used_aligned
            = . h used needed
            ^ p
        } {}
    } {}
    ? <= . impl chunk_sz 0 { ^ # *u 0 } {}
    : *ArenaChunk nc ( __arena_push_chunk impl ? > n . impl chunk_sz n . impl chunk_sz )
    = . nc used n
    ^ ( raw_block_ptr . nc data )
}

// Allocate `n` bytes, 8-byte aligned. FIXED: NULL once the buffer is
// full. GROWING: adds a fresh chunk when the current one is full.
@ arena_alloc Arena a i n → *u { ^ ( __arena_take a n 8 ) }

// Allocate `n` bytes with the requested alignment. `align` must be a
// power of two; `align <= 1` means no alignment. FIXED: NULL on
// overflow (after alignment). GROWING: a fresh chunk if the head can't
// satisfy the aligned request.
@ arena_alloc_aligned Arena a i n i align → *u { ^ ( __arena_take a n align ) }

// Typed allocation: `count` contiguous items of T, 8-byte aligned.
// Returns a borrowed `*T` into the arena (NULL on OOM, like
// `arena_alloc`). The arena owns the storage.
@ arena_alloc_n [T] Arena a i count → *T {
    ? <= count 0 { ^ # *T 0 } {}
    ^ # *T ( arena_alloc a * count Z T )
}

// ── Lifecycle ────────────────────────────────────────────────────────

// Rewind to empty. All previously-issued pointers become invalid. The
// base chunk's buffer is retained for reuse; any extra chunks a GROWING
// arena added are released.
@ arena_reset Arena a → v {
    : *ArenaImpl impl ( __arena_impl a )
    ? > ( vec_len [ArenaChunk] . impl chunks ) 0 {
        : b _t ( vec_truncate [ArenaChunk] . impl chunks 1 )
        = . ( __arena_head impl ) used 0
    } {}
}

// Another owner of the same arena; the last one releases its chunks.
@ Arena_share Arena a → Arena { ^ @ Arena { ( shared_clone [ArenaImpl] . a ctl ) } }

@ Arena_drop sink Arena a → v {}

// Let go of `a` now rather than at the end of its owner's scope.
@ arena_free sink Arena a → v {}
