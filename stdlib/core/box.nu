// stdlib/core/box.nu — owned, single-T, heap-stable allocation.
//
// `Box[T]` is the most basic building block of NURL's heap allocator
// surface: an opaque 8-byte handle wrapping a heap allocation that
// holds exactly one value of type `T`. Used wherever a struct must
// have a *stable address* — passable by value through closures, FFI
// parameters, channels, or thread spawns — without copying the value
// every time the handle moves.
//
// Conceptually the same role `Box<T>` plays in Rust or `Box[T]` plays
// in Zig's std.heap, with NURL's single-owner discipline: every Box
// has exactly one owner, and that owner calls `box_free` exactly once
// when done. There is no static checker behind this; the convention
// matches `vec_free` / `hashmap_free` / `arena_free` already in core.
//
// API:
//
//   ( box_new  [T] x )            → ( Box T )    heap-allocate, store x
//   ( box_zero [T] )              → ( Box T )    heap-allocate, zero-init
//   ( box_get  [T] b )            → T            load by value (see TRAP)
//   ( box_set  [T] b x )          → v            overwrite payload
//   ( box_replace [T] b x )       → T            store new, return old
//   ( box_ptr  [T] b )            → *T           borrowed raw pointer (FFI)
//   ( box_into [T] b )            → T            consume + free the box
//   ( box_clone [T] b )           → ( Box T )    bitwise shallow copy
//   ( box_clone_with [T] b f )    → ( Box T )    deep copy via f : (@ T T)
//   ( box_free [T] b )            → v            release storage
//   ( box_free_with [T] b drop )  → v            drop : (@ v T); runs first
//   ( box_is_null [T] b )         → b            T iff allocation failed
//
// Memory model:
//
//   * `Box[T]` is a single-pointer handle. The 8-byte handle is the
//     value passed around; the actual T storage lives in a dedicated
//     `nurl_alloc(Z T)` block whose address the handle holds.
//   * Copying a `Box[T]` by value — assigning it to a new binding,
//     passing it to a function — duplicates the handle, not the
//     storage. Both handles see the same heap slot, like `Channel` /
//     `String` / `Arena`. Mutate through either; both observe the
//     change. The owner discipline says ONE handle is responsible for
//     calling `box_free` exactly once.
//   * `box_ptr b` returns a raw `*T` borrowed from the box's slot.
//     The pointer is valid until `box_free` (which deallocates) or
//     `box_set` (which overwrites the slot but keeps the address).
//     Never `nurl_free` a pointer from `box_ptr`; the Box owns it.
//   * `box_into b` is the only operation that consumes a Box: it
//     copies the T out by value, frees the slot, and renders the
//     handle dead. Any prior `box_ptr` borrow is now dangling.
//
// TRAP — owned-T copy semantics:
//
//   For trivial element types (`i`, `f`, `b`, raw `s`, slice), `box_get`
//   bitwise-copies T out — safe.
//   For owned element types (`String`, `Vec`, `HashMap`, nested `Box`),
//   `box_get` aliases the heap pointer inside T: now BOTH the Box and
//   the returned T own the same underlying allocation. The next
//   `box_free` plus the returned-T's auto-drop will double-free.
//
//   Use `box_into` to MOVE the payload out (the box dies, the T lives
//   on), or `box_clone_with` with a deep-clone closure (`string_clone`
//   for `Box[String]`, `vec_clone_with` for `Box[Vec[…]]`, etc.). This
//   is the same `_with` convention `vec_clone` / `vec_free` use.
//
// Why a *single*-T heap slot when arena/vec already exist:
//
//   * Arena gives a *bump-allocated, lifetime-tied-to-the-arena* region;
//     pointers become invalid on `arena_reset`. Box gives a *dedicated,
//     independently-freeable* slot with a lifetime tied only to the
//     handle's owner. Different use case.
//   * Vec[T] of length 1 gives 24 bytes of overhead (data + len + cap)
//     for what should be 8 (just the pointer). Vec also forbids holding
//     a stable `*T` across pushes (realloc), while Box guarantees the
//     address never moves until `box_free`.
//   * Heap-stable structs (DoS state, libcurl session, sqlite prepared-
//     statement view) need a stable address but no growth. Box is
//     the precise primitive — what PURIFY Phase 6/8/11/12 was missing.
//
// Lifecycle pattern:
//
//   : ( Box DosState ) s ( box_new @ DosState { 0 0 0 ( map_new ) m } )
//   ( do_work s )                     // s is a single handle, address stable
//   ( box_free_with s @ DosState d → v { ( map_free . d table ) } )

$ `stdlib/core/mem.nu`

: Box [T] { s ptr }

// ── Constructors ────────────────────────────────────────────────────

// Allocate sizeof(T) bytes, store `x` at offset 0, return a Box[T]
// handle. Returns a box with a NULL ptr on allocation failure (zero
// bytes asked, or malloc returned NULL) — callers can detect via
// `box_is_null`.
@ box_new [T] T x → ( Box T ) {
    : *T p ( alloc [T] 1 )
    ? != 0 # i p { = . p 0 x } {}
    ^ @ ( Box T ) { # s p }
}

// Allocate sizeof(T) bytes, zero-initialised. Suitable for T whose
// zero pattern is meaningful (pointer fields = null, integer = 0,
// boolean = F).
@ box_zero [T] → ( Box T ) {
    : *T p ( zalloc [T] 1 )
    ^ @ ( Box T ) { # s p }
}

// ── Inspectors ──────────────────────────────────────────────────────

@ box_is_null [T] ( Box T ) b → b {
    ^ == 0 # i . b ptr
}

// ── Access ──────────────────────────────────────────────────────────

// Load the payload by value. SEE TRAP in the file header for owned T.
@ box_get [T] ( Box T ) b → T {
    : *T p # *T . b ptr
    ^ . p 0
}

// Overwrite the payload in place. Old value is discarded by bitwise
// overwrite — for owned T, drop the old value separately first or
// leak it. Use `box_replace` when the old value still matters.
@ box_set [T] ( Box T ) b T x → v {
    : *T p # *T . b ptr
    = . p 0 x
}

// Store `x`, return the old payload. Caller now owns the old value
// and is responsible for any cleanup (e.g. `string_free` on
// Box[String], `vec_free` on Box[Vec[…]]). For owned-T this is the
// SAFE way to update — `box_set` leaks the old payload silently.
@ box_replace [T] ( Box T ) b T x → T {
    : *T p # *T . b ptr
    : T old . p 0
    = . p 0 x
    ^ old
}

// Borrowed raw pointer into the box's slot. Valid until `box_free` /
// `box_into`. FFI-friendly: pass `( box_ptr b )` directly to libc
// functions expecting `T *`.
@ box_ptr [T] ( Box T ) b → *T {
    ^ # *T . b ptr
}

// ── Consumers ───────────────────────────────────────────────────────

// Move the payload OUT of the box; free the box's storage; return T.
// The handle `b` is dead afterwards — do not call any other box_* on
// it. This is the only owner-respecting way to extract owned T.
@ box_into [T] ( Box T ) b → T {
    : *T p # *T . b ptr
    : T v . p 0
    ( nurl_free # s p )
    ^ v
}

// ── Cloning ─────────────────────────────────────────────────────────

// Bitwise shallow copy. Safe for trivial T; aliases owned heap state
// inside T (same trap as `vec_clone` over `Vec[String]`).
@ box_clone [T] ( Box T ) b → ( Box T ) {
    : *T src # *T . b ptr
    ? == 0 # i src { ^ @ ( Box T ) { # s 0 } } {}
    : T v . src 0
    ^ ( box_new [T] v )
}

// Deep clone: caller supplies `f : (@ T T)` that returns an
// independently-owned copy of its argument. Use for owned-T payloads.
//   ( box_clone_with [String] sb \ x → x { ( string_clone x ) } )
@ box_clone_with [T] ( Box T ) b ( @ T T ) f → ( Box T ) {
    : *T src # *T . b ptr
    ? == 0 # i src { ^ @ ( Box T ) { # s 0 } } {}
    : T orig . src 0
    : T copy ( f orig )
    ^ ( box_new [T] copy )
}

// ── Lifecycle ───────────────────────────────────────────────────────

// Release the box's storage. The handle is dead afterwards. Idempotent
// against a NULL-pointer box (e.g. `box_zero` over a zero-sized type
// where alloc returned NULL); not idempotent over an already-freed
// non-NULL box — calling twice is undefined behaviour (double-free),
// matching `vec_free` / `nurl_free`.
@ box_free [T] ( Box T ) b → v {
    : *T p # *T . b ptr
    ? != 0 # i p { ( nurl_free # s p ) } {}
}

// Free with a per-payload drop closure. Used for owned-T boxes:
//   ( box_free_with [String] sb \ x → v { ( string_free x ) } )
// Equivalent to `( drop ( box_get b ) )` followed by `( box_free b )`,
// but expressed as one call to mirror `vec_free_with`.
@ box_free_with [T] ( Box T ) b ( @ v T ) drop → v {
    : *T p # *T . b ptr
    ? != 0 # i p {
        : T v . p 0
        ( drop v )
        ( nurl_free # s p )
    } {}
}
