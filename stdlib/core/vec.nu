// stdlib/core/vec.nu — owned growable Vec[A]
//
// Vec[A] is an opaque generic handle around a heap-allocated control
// block {data, len, cap}. The handle is passed by value; all mutations
// go through the heap pointer, so the caller's handle stays valid
// across pushes (even when the buffer is reallocated). Aliasing
// behaviour mirrors String — two Vec handles pointing at the same
// buffer see each other's mutations.
//
// The type parameter A is *phantom* — the control block layout does
// not depend on A, only element size (`Z A`) does. Mixing Vec[i] and
// Vec[s] through type coercion is undefined at runtime; the compiler
// keeps them distinct by mangling `%Vec__i64` vs `%Vec__str`.
//
// Control block layout (3 × i64 = 24 bytes, accessed via nurl_peek/poke):
//   word 0: data pointer (ptrtoint'd to i64; 0 when no buffer allocated)
//   word 1: len
//   word 2: cap
//
// Ownership:
//   vec_new / vec_with_cap → owned Vec, caller must vec_free when done.
//   For trivial element types (i, f, b) use `vec_free`. For owned
//   element types (String, nested Vec, HashMap) use `vec_free_with`
//   passing a per-element drop closure — `vec_free_with` walks the
//   live range [0..len) calling drop_fn before releasing the buffer,
//   closing the Vec[String]-leak trap that the bare `vec_free` leaves.
//
// The type-var name is `A` (not `T`) because the boolean literal `T`
// collides with whole-identifier substitution at monomorphisation time.
//
// API:
//   ( vec_new [A] )                → ( Vec A )   empty, no alloc
//   ( vec_with_cap [A] n )         → ( Vec A )   preallocated
//   ( vec_zeroed [A] n )           → ( Vec A )   n zero-filled elements,
//                                                len == n, one calloc
//   ( vec_len [A] v )              → i          current length
//   ( vec_cap [A] v )              → i          current capacity
//   ( vec_is_empty [A] v )         → b          len == 0
//   ( vec_data [A] v )             → *A         borrowed raw pointer
//   ( vec_get [A] v i )            → ? A        None if idx out of range
//   ( vec_set [A] v i x )          → b          false if idx out of range
//   ( vec_push [A] v x )           → v          grows buffer if needed
//   ( vec_pop [A] v )              → ? A        None if empty
//   ( vec_insert [A] v idx x )     → b          F if idx out of range; idx == len → push
//   ( vec_remove [A] v idx )       → ? A        None if idx out of range
//   ( vec_clear [A] v )            → v          sets len=0, keeps cap
//   ( vec_set_len [A] v n )        → b          commit raw-pointer writes
//                                                up to index n; F when n
//                                                is negative or > current
//                                                cap (no-op then). Used
//                                                by FFI bridges that fill
//                                                a Vec via vec_data + the
//                                                runtime (TCP, file IO,
//                                                Vec[u]-backed crypto).
//   ( vec_swap [A] v i j )         → b          swaps two slots
//   ( vec_reverse [A] v )          → v          in-place reverse
//   ( vec_reserve [A] v n )        → v          ensure cap ≥ len + n
//   ( vec_resize_zeroed [A] v n )  → b          set len to exactly n;
//                                                a longer n zero-fills the
//                                                new tail in one memset
//   ( vec_shrink_to_fit [A] v )    → v          release unused capacity
//   ( vec_extend [A] dst src )     → v          bitwise copy of src's elements
//                                                onto dst (trivial element types
//                                                only — same caveat as vec_map)
//
//   Equality (closure-based, mirrors HashMap eq_fn convention):
//   ( vec_contains [A] v target eq_fn ) → b     eq_fn : (@ b A A)
//   ( vec_index_of [A] v target eq_fn ) → ? i   first index or None
//   ( vec_eq [A] a b eq_fn )            → b     element-wise equal lengths + eq_fn
//   ( vec_free [A] v )             → v          release buffer; call once
//   ( vec_free_with [A] v drop )   → v          drop : (@ v A) — call drop
//                                                per element in [0..len)
//                                                before releasing buffer.
//                                                Use for Vec[String] etc.
//
//   Higher-order (element-preserving — caller still owns the Vec):
//   ( vec_each [A] v f )           → v          f : (@ v A)
//   ( vec_fold [A B] v init f )    → B          f : (@ B B A)
//
//   Higher-order (allocate a new Vec — same single-owner caveats apply
//   to element types: bitwise-copy is safe for i/f/b/raw-s/slice, NOT
//   for owned String/Vec/HashMap; for those build manually):
//   ( vec_map [A B] v f )          → ( Vec B )  f : (@ B A)
//   ( vec_filter [A] v pred )      → ( Vec A )  pred : (@ b A); trivial
//   ( vec_filter_with [A] v pred clone ) → ( Vec A )  owned-safe filter —
//                                                clone : (@ A A) clones
//                                                every kept element
//
//   Higher-order (search — no allocation):
//   ( vec_find [A] v pred )        → ? A        first match or None
//   ( vec_any  [A] v pred )        → b          short-circuit
//   ( vec_all  [A] v pred )        → b          short-circuit on first F
//
//   Clone (mirrors the vec_free / vec_free_with split):
//   ( vec_clone [A] v )            → ( Vec A )  bitwise shallow copy;
//                                                trivial elements only
//   ( vec_clone_with [A] v clone ) → ( Vec A )  deep copy; clone : (@ A A)
//                                                runs per element. Use for
//                                                Vec[String] / nested Vec.
//
// A bare `vec_clone` over an owned element type aliases every heap
// pointer and double-frees at scope exit — the same trap as bare
// `vec_free` over Vec[String]. Use `vec_clone_with` whenever the element
// owns heap storage; pass a closure that returns an independently-owned
// element (e.g. wrap `string_clone` in a `\`).

: Vec [A] { s ctl }

// ── Internal helpers ────────────────────────────────────────────────

@ __vec_data_raw s ctl → s {
    ^ # s ( nurl_peek ctl 0 )
}

@ __vec_len_raw s ctl → i {
    ^ ( nurl_peek ctl 1 )
}

@ __vec_cap_raw s ctl → i {
    ^ ( nurl_peek ctl 2 )
}

// Grow the underlying buffer so that cap >= need. Uses nurl_realloc;
// safe to call when the current data pointer is null (cap == 0).
@ __vec_grow [A] s ctl i need → v {
    : i cap ( __vec_cap_raw ctl )
    ? < cap need {
        : ~ i new_cap ? == cap 0 4 cap
        ~ < new_cap need { = new_cap * new_cap 2 }
        : s cur ( __vec_data_raw ctl )
        : i bytes * Z A new_cap
        // If `cur` lives in the same alloc as ctl (the packed-string
        // layout from string_from_bytes_packed — data sits at ctl+24),
        // realloc() would walk into the middle of another malloc block
        // and crash. Detect that, malloc-copy-out into a fresh buffer
        // instead; the next free of this Vec then frees both blocks
        // (the packed-aware vec_free below skips the in-ctl buffer).
        : i ctl_end + # i ctl 24
        ? & != 0 # i cur == # i cur ctl_end {
            : s fresh ( nurl_alloc bytes )
            : i len ( __vec_len_raw ctl )
            : i copy_bytes * Z A len
            ? > copy_bytes 0 { ( nurl_memcpy fresh cur copy_bytes ) } {}
            ( nurl_poke ctl 0 # i fresh )
            ( nurl_poke ctl 2 new_cap )
        } {
            ? == 0 # i cur {
                // First growth: nurl_alloc, not realloc(NULL, n) — the
                // runtime's small-allocation cache sits behind
                // nurl_alloc/nurl_free, and a Vec's first buffer is the
                // most recycled block shape there is.
                : s fresh ( nurl_alloc bytes )
                ( nurl_poke ctl 0 # i fresh )
                ( nurl_poke ctl 2 new_cap )
            } {
                : s fresh ( nurl_realloc cur bytes )
                ( nurl_poke ctl 0 # i fresh )
                ( nurl_poke ctl 2 new_cap )
            }
        }
    } {}
}

// ── Constructors ────────────────────────────────────────────────────

@ vec_new [A] → ( Vec A ) {
    : s ctl ( nurl_zalloc 24 )
    ^ @ ( Vec A ) { ctl }
}

@ vec_with_cap [A] i n → ( Vec A ) {
    : s ctl ( nurl_zalloc 24 )
    : i want ? > n 0 n 0
    ? > want 0 { ( __vec_grow [A] ctl want ) } {}
    ^ @ ( Vec A ) { ctl }
}

// `n` zero-filled elements in ONE allocation, with `len` already at n —
// the calloc-shaped sibling of `vec_with_cap`. Reaching the same state
// by pushing a zero n times costs n bounds checks, n length stores and
// log2(n) reallocations, and it writes every page; this hands the size
// straight to `nurl_zalloc`, so a large buffer arrives as untouched
// zero pages from the kernel and costs nothing until it is written.
//
// Bitwise zero has to be a valid A — the same trivial-element-type rule
// as `vec_extend` / `vec_map`. `n <= 0` is an empty Vec with no buffer.
@ vec_zeroed [A] i n → ( Vec A ) {
    : s ctl ( nurl_zalloc 24 )
    ? > n 0 {
        : s data ( nurl_zalloc * Z A n )
        ( nurl_poke ctl 0 # i data )
        ( nurl_poke ctl 1 n )
        ( nurl_poke ctl 2 n )
    } {}
    ^ @ ( Vec A ) { ctl }
}

// ── Inspectors ──────────────────────────────────────────────────────

@ vec_len [A] ( Vec A ) v → i {
    ^ ( __vec_len_raw . v ctl )
}

@ vec_cap [A] ( Vec A ) v → i {
    ^ ( __vec_cap_raw . v ctl )
}

@ vec_is_empty [A] ( Vec A ) v → b {
    ^ == ( __vec_len_raw . v ctl ) 0
}

@ vec_data [A] ( Vec A ) v → *A {
    ^ # *A ( nurl_peek . v ctl 0 )
}

// ── Access ──────────────────────────────────────────────────────────

@ vec_get [A] ( Vec A ) v i idx → ?A {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    ? | < idx 0 >= idx len { ^ @ ?A { F # A 0 } } {}
    : *A data # *A ( nurl_peek ctl 0 )
    : A x . data idx
    ^ @ ?A { T x }
}

@ vec_set [A] ( Vec A ) v i idx A x → b {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    ? | < idx 0 >= idx len { ^ F } {}
    : *A data # *A ( nurl_peek ctl 0 )
    = . data idx x
    ^ T
}

// ── Mutation ────────────────────────────────────────────────────────

@ vec_push [A] ( Vec A ) v A x → v {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    // Only call into __vec_grow when the buffer is actually full: the
    // grow path is too big to inline, and paying a call per push showed
    // up at ~6 % of a parse-heavy profile. The common push is then a
    // load, a compare, a store and a length bump.
    ? >= len ( __vec_cap_raw ctl ) { ( __vec_grow [A] ctl + len 1 ) } {}
    : *A data # *A ( nurl_peek ctl 0 )
    = . data len x
    ( nurl_poke ctl 1 + len 1 )
}

// Insert `x` at index `idx`, shifting existing [idx..len) right by one.
// Valid indices: [0..len]. idx == len behaves like vec_push. Returns
// false if idx is out of range. Out-of-range insert is a no-op.
@ vec_insert [A] ( Vec A ) v i idx A x → b {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    ? | < idx 0 > idx len { ^ F } {}
    ( __vec_grow [A] ctl + len 1 )
    : *A data # *A ( nurl_peek ctl 0 )
    // Shift right [idx..len) → [idx+1..len+1). Walk from the tail to
    // keep adjacent slots from clobbering each other.
    : ~ i i len
    ~ > i idx {
        = . data i . data - i 1
        = i - i 1
    }
    = . data idx x
    ( nurl_poke ctl 1 + len 1 )
    ^ T
}

// Remove the element at `idx`, shifting the tail down by one. Returns
// the removed element wrapped in Some, or None if idx is out of range.
@ vec_remove [A] ( Vec A ) v i idx → ?A {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    ? | < idx 0 >= idx len { ^ @ ?A { F # A 0 } } {}
    : *A data # *A ( nurl_peek ctl 0 )
    : A x . data idx
    : ~ i i idx
    ~ < i - len 1 {
        = . data i . data + i 1
        = i + i 1
    }
    ( nurl_poke ctl 1 - len 1 )
    ^ @ ?A { T x }
}

@ vec_pop [A] ( Vec A ) v → ?A {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    ? == len 0 { ^ @ ?A { F # A 0 } } {}
    : i last - len 1
    : *A data # *A ( nurl_peek ctl 0 )
    : A x . data last
    ( nurl_poke ctl 1 last )
    ^ @ ?A { T x }
}

@ vec_clear [A] ( Vec A ) v → v {
    ( nurl_poke . v ctl 1 0 )
}

// Commit a raw write that the caller performed via `vec_data` directly
// — used by FFI bridges (TCP read, binary file IO, hash digest sinks)
// that hand the Vec's data pointer to the runtime and then need to
// promote `len` from 0 to the number of bytes the runtime stored.
//
// Returns F (no-op) if `n` is negative or larger than the current cap.
// Caller is responsible for ensuring slots [0..n) are initialised
// before calling — `vec_set_len` does NOT zero-fill.
@ vec_set_len [A] ( Vec A ) v i n → b {
    ? < n 0 { ^ F } {}
    : s ctl . v ctl
    : i cap ( __vec_cap_raw ctl )
    ? > n cap { ^ F } {}
    ( nurl_poke ctl 1 n )
    ^ T
}

// Fresh Vec[i] pre-filled with [lo, lo+1, ..., hi-1]. hi <= lo is a
// fresh empty Vec[i]. Single allocation, no per-element grow. Useful
// when sorting an index permutation.
//
// NOTE: defined AFTER vec_with_cap / vec_data / vec_set_len because
// the compiler resolves call-site return types via top-down scan; a
// forward reference here corrupts return-type specialization (the
// callee is treated as i64-returning and downstream stores then mismatch).
@ vec_iota i lo i hi → ( Vec i ) {
    : i n ? > hi lo - hi lo 0
    : ( Vec i ) v ( vec_with_cap [i] n )
    ? > n 0 {
        : *i data ( vec_data [i] v )
        : ~ i k 0
        ~ < k n {
            = . data k + lo k
            = k + k 1
        }
        : b _ok ( vec_set_len [i] v n )
    } {}
    ^ v
}

@ vec_swap [A] ( Vec A ) v i i_idx i j_idx → b {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    ? | | | < i_idx 0 >= i_idx len < j_idx 0 >= j_idx len { ^ F } {}
    ? == i_idx j_idx { ^ T } {}
    : *A data # *A ( nurl_peek ctl 0 )
    : A a . data i_idx
    : A b . data j_idx
    = . data i_idx b
    = . data j_idx a
    ^ T
}

@ vec_reverse [A] ( Vec A ) v → v {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    ? > len 1 {
        : *A data # *A ( nurl_peek ctl 0 )
        : ~ i i 0
        : ~ i j - len 1
        ~ < i j {
            : A a . data i
            : A b . data j
            = . data i b
            = . data j a
            = i + i 1
            = j - j 1
        }
    } {}
}

// ── Capacity ────────────────────────────────────────────────────────

// Ensure cap ≥ len + n. n ≤ 0 is a no-op. Allocates lazily; safe on a
// fresh Vec with cap == 0.
@ vec_reserve [A] ( Vec A ) v i n → v {
    ? > n 0 {
        : s ctl . v ctl
        : i len ( __vec_len_raw ctl )
        ( __vec_grow [A] ctl + len n )
    } {}
}

// Set the length to exactly `n`. Growing zero-fills the new tail with a
// single `nurl_memset` instead of a push-a-zero loop; shrinking only
// lowers the length, running no per-element drop, so the same
// trivial-element-type rule as `vec_extend` applies. Returns F — and
// changes nothing — for a negative `n`.
@ vec_resize_zeroed [A] ( Vec A ) v i n → b {
    ? < n 0 { ^ F } {}
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    ? <= n len { ( nurl_poke ctl 1 n ) ^ T } {}
    ( __vec_grow [A] ctl n )
    : s data ( __vec_data_raw ctl )
    : s tail # s + # i data * Z A len
    ( nurl_memset tail 0 * Z A - n len )
    ( nurl_poke ctl 1 n )
    ^ T
}

// Release any unused capacity. If len == 0 the buffer is freed entirely
// (cap → 0, data → null). Otherwise the buffer is realloc'd down to len.
@ vec_shrink_to_fit [A] ( Vec A ) v → v {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    : i cap ( __vec_cap_raw ctl )
    ? == len 0 {
        : s data ( __vec_data_raw ctl )
        ? != 0 # i data { ( nurl_free data ) } {}
        ( nurl_poke ctl 0 0 )
        ( nurl_poke ctl 2 0 )
    } {
        ? < len cap {
            : s cur ( __vec_data_raw ctl )
            : s fresh ( nurl_realloc cur * Z A len )
            ( nurl_poke ctl 0 # i fresh )
            ( nurl_poke ctl 2 len )
        } {}
    }
}

// Append `src[off .. off+n)` to `dst` (bitwise), with the same
// trivial-element-type rule as vec_extend below.
//
// The whole-vector form makes a caller who has only a sub-range build a
// temporary Vec to pass it — a full copy of the data, plus an
// allocation and a free, to move bytes it already had. net/tcpstack.nu
// hits this on every outgoing segment (TCP carries no length field, so
// the segments arrive as offsets into one buffer), which is the wrong
// place to be allocating.
//
// Out-of-range requests are clamped rather than trapped: `off` past the
// end appends nothing, and a length running past the end appends what
// is there. A caller computing a range from a parsed header should not
// have to re-verify what the vector can already answer.
@ vec_extend_range [A] ( Vec A ) dst ( Vec A ) src i off i n → v {
    : s sctl . src ctl
    : i slen ( __vec_len_raw sctl )
    : i start ? < off 0 0 off
    ? >= start slen { ^ } {}
    : i want ? < n 0 0 n
    : i cnt ? > + start want slen - slen start want
    ? <= cnt 0 { ^ } {}
    : s dctl . dst ctl
    : i dlen ( __vec_len_raw dctl )
    ( __vec_grow [A] dctl + dlen cnt )
    : *A ddata # *A ( nurl_peek dctl 0 )
    : *A sdata # *A ( nurl_peek sctl 0 )
    : ~ i i 0
    ~ < i cnt {
        = . ddata + dlen i . sdata + start i
        = i + i 1
    }
    ( nurl_poke dctl 1 + dlen cnt )
}

// Append every element of `src` to `dst` (bitwise). Like vec_map, this
// is safe only for trivial element types (i, f, b, raw s, slice). For
// owned element types the caller must clone manually with vec_each +
// vec_push and an explicit element clone, otherwise the dst would alias
// src's heap buffers and break the single-owner invariant.
@ vec_extend [A] ( Vec A ) dst ( Vec A ) src → v {
    : s sctl . src ctl
    : i n ( __vec_len_raw sctl )
    ? > n 0 {
        : s dctl . dst ctl
        : i dlen ( __vec_len_raw dctl )
        ( __vec_grow [A] dctl + dlen n )
        : *A ddata # *A ( nurl_peek dctl 0 )
        : *A sdata # *A ( nurl_peek sctl 0 )
        : ~ i i 0
        ~ < i n {
            = . ddata + dlen i . sdata i
            = i + i 1
        }
        ( nurl_poke dctl 1 + dlen n )
    } {}
}

// ── Cleanup ─────────────────────────────────────────────────────────

@ vec_free [A] ( Vec A ) v → v {
    : s ctl . v ctl
    : s data ( __vec_data_raw ctl )
    // `string_from_bytes_packed` (core/string.nu) lays the data
    // buffer immediately after the 24-byte ctl in a single alloc.
    // Detect that case (data == ctl + 24) and skip the separate
    // buffer-free — both regions live in the one block freed below.
    : i ctl_end + # i ctl 24
    ? & != 0 # i data != # i data ctl_end { ( nurl_free data ) } {}
    ( nurl_free ctl )
}

// Drop-aware free: invokes `drop` for every live element in [0..len)
// before releasing the buffer + control block. Pass a closure that
// performs whatever per-element cleanup the element type needs
// (`string_free`, nested `vec_free`, `map_free`, …). For trivial
// element types use the bare `vec_free` instead — calling
// `vec_free_with` with a no-op closure works but is wasteful.
@ vec_free_with [A] ( Vec A ) v ( @ v A ) drop → v {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    : s data ( __vec_data_raw ctl )
    ? != 0 # i data {
        : *A buf # *A data
        : ~ i i 0
        ~ < i len {
            ( drop . buf i )
            = i + i 1
        }
        // Skip the buffer free when it lives in the same alloc as the
        // ctl (see vec_free above for the packed-string layout).
        : i ctl_end + # i ctl 24
        ? != # i data ctl_end { ( nurl_free data ) } {}
    } {}
    ( nurl_free ctl )
}

// ── Clone ───────────────────────────────────────────────────────────

// Shallow bitwise copy: a fresh Vec with the same length whose elements
// are copied verbatim. Safe ONLY for trivial element types (i, f, b,
// raw s pointers, fat-ptr slices). For an owned element type this would
// alias every heap buffer across two Vecs and double-free at scope exit
// — use `vec_clone_with` instead. Mirrors the `vec_free` / `vec_free_with`
// split: bare = trivial, `_with` = owned.
@ vec_clone [A] ( Vec A ) v → ( Vec A ) {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    : ( Vec A ) out ( vec_with_cap [A] len )
    ? > len 0 {
        : *A src # *A ( nurl_peek ctl 0 )
        : *A dst ( vec_data [A] out )
        : ~ i i 0
        ~ < i len {
            = . dst i . src i
            = i + i 1
        }
        : b _ok ( vec_set_len [A] out len )
    } {}
    ^ out
}

// Deep copy: a fresh Vec whose elements are produced by calling `clone`
// on every element of `v` in order. `clone` must return an element that
// owns its own heap storage independently of the source — for Vec[String]
// pass `\ String s → String { ^ ( string_clone s ) }`, for Vec[Json]
// `\ Json j → Json { ^ ( json_clone j ) }`, etc. The source Vec is left
// untouched; the caller owns both Vecs and frees each with the matching
// `vec_free_with`.
@ vec_clone_with [A] ( Vec A ) v ( @ A A ) clone → ( Vec A ) {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    : ( Vec A ) out ( vec_with_cap [A] len )
    ? > len 0 {
        : *A src # *A ( nurl_peek ctl 0 )
        : ~ i i 0
        ~ < i len {
            : A x . src i
            ( vec_push [A] out ( clone x ) )
            = i + i 1
        }
    } {}
    ^ out
}

// ── Higher-order ────────────────────────────────────────────────────

@ vec_each [A] ( Vec A ) v ( @ v A ) f → v {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    ? > len 0 {
        : *A data # *A ( nurl_peek ctl 0 )
        : ~ i i 0
        ~ < i len {
            ( f . data i )
            = i + i 1
        }
    } {}
}

@ vec_fold [A B] ( Vec A ) v B init ( @ B B A ) f → B {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    : *A data # *A ( nurl_peek ctl 0 )
    : ~ B acc init
    : ~ i i 0
    ~ < i len {
        : A x . data i
        = acc ( f acc x )
        = i + i 1
    }
    ^ acc
}

// Map every element through `f` into a fresh Vec[B]. The source Vec is
// not modified; the caller owns both. Element bytes are copied bitwise
// — safe for trivial element types (i, f, b, raw s pointers, fat-ptr
// slices). For owned types like String, vec_map would alias buffers
// across two Vecs and break the single-owner invariant; build a Vec
// manually with vec_each + vec_push and an explicit clone.
@ vec_map [A B] ( Vec A ) v ( @ B A ) f → ( Vec B ) {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    : ( Vec B ) out ( vec_with_cap [B] len )
    : *A data # *A ( nurl_peek ctl 0 )
    : ~ i i 0
    ~ < i len {
        : A x . data i
        ( vec_push [B] out ( f x ) )
        = i + i 1
    }
    ^ out
}

// Keep elements where `pred` returns T. Same trivial-element caveat as
// vec_map: the kept elements are bitwise-copied into the output Vec.
@ vec_filter [A] ( Vec A ) v ( @ b A ) pred → ( Vec A ) {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    : ( Vec A ) out ( vec_new [A] )
    : *A data # *A ( nurl_peek ctl 0 )
    : ~ i i 0
    ~ < i len {
        : A x . data i
        ? ( pred x ) { ( vec_push [A] out x ) } {}
        = i + i 1
    }
    ^ out
}

// Owned-safe filter: keep elements where `pred` returns T, but push a
// `clone` of each kept element into the output instead of a bitwise
// alias. The result Vec owns its elements independently of `v`, so both
// can be freed with `vec_free_with` without a double-free. Use this for
// Vec[String] / Vec[Json] / nested containers; `vec_filter` stays the
// faster path for trivial element types.
@ vec_filter_with [A] ( Vec A ) v ( @ b A ) pred ( @ A A ) clone → ( Vec A ) {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    : ( Vec A ) out ( vec_new [A] )
    : *A data # *A ( nurl_peek ctl 0 )
    : ~ i i 0
    ~ < i len {
        : A x . data i
        ? ( pred x ) { ( vec_push [A] out ( clone x ) ) } {}
        = i + i 1
    }
    ^ out
}

// First element matching `pred`, or None.
@ vec_find [A] ( Vec A ) v ( @ b A ) pred → ?A {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    : *A data # *A ( nurl_peek ctl 0 )
    : ~ i i 0
    ~ < i len {
        : A x . data i
        ? ( pred x ) { ^ @ ?A { T x } } {}
        = i + i 1
    }
    ^ @ ?A { F # A 0 }
}

// True if any element satisfies `pred`. Short-circuits.
@ vec_any [A] ( Vec A ) v ( @ b A ) pred → b {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    : *A data # *A ( nurl_peek ctl 0 )
    : ~ i i 0
    ~ < i len {
        : A x . data i
        ? ( pred x ) { ^ T } {}
        = i + i 1
    }
    ^ F
}

// True if `target` is present in `v` (according to `eq_fn`). Short-circuits.
// Use the same eq closures HashMap takes (`eq_int`, `eq_string`) or a custom
// one. For trivial element types the closure body is just `== a b`.
@ vec_contains [A] ( Vec A ) v A target ( @ b A A ) eq_fn → b {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    : *A data # *A ( nurl_peek ctl 0 )
    : ~ i i 0
    ~ < i len {
        : A x . data i
        ? ( eq_fn x target ) { ^ T } {}
        = i + i 1
    }
    ^ F
}

// First byte index where `target` occurs in `v`, or None. Same eq_fn
// convention as vec_contains.
@ vec_index_of [A] ( Vec A ) v A target ( @ b A A ) eq_fn → ?i {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    : *A data # *A ( nurl_peek ctl 0 )
    : ~ i i 0
    ~ < i len {
        : A x . data i
        ? ( eq_fn x target ) { ^ @ ?i { T i } } {}
        = i + i 1
    }
    ^ @ ?i { F 0 }
}

// Length-equal + element-wise equality under `eq_fn`. Short-circuits.
@ vec_eq [A] ( Vec A ) a ( Vec A ) b ( @ b A A ) eq_fn → b {
    : s actl . a ctl
    : s bctl . b ctl
    : i la ( __vec_len_raw actl )
    : i lb ( __vec_len_raw bctl )
    ? != la lb { ^ F } {}
    : *A da # *A ( nurl_peek actl 0 )
    : *A db # *A ( nurl_peek bctl 0 )
    : ~ i i 0
    ~ < i la {
        : A x . da i
        : A y . db i
        : b ok ( eq_fn x y )
        ? ! ok { ^ F } {}
        = i + i 1
    }
    ^ T
}

// True if every element satisfies `pred`. Short-circuits on first F.
@ vec_all [A] ( Vec A ) v ( @ b A ) pred → b {
    : s ctl . v ctl
    : i len ( __vec_len_raw ctl )
    : *A data # *A ( nurl_peek ctl 0 )
    : ~ i i 0
    ~ < i len {
        : A x . data i
        : b ok ( pred x )
        ? ! ok { ^ F } {}
        = i + i 1
    }
    ^ T
}
