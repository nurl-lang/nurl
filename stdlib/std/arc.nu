// stdlib/std/arc.nu — atomic reference-counted heap allocation.
//
// `Arc[T]` is the multi-threaded counterpart of `Rc[T]`: shared
// ownership over a single heap slot with the refcount manipulated
// via SEQ_CST atomic ops. Two threads can each hold a clone of the
// same Arc; one calling `arc_clone` while the other is calling
// `arc_free` is well-defined.
//
// Use when:
//   * The handle has to cross a thread boundary — passed into
//     `thread_spawn`'s closure env, or pushed onto a `Channel`.
//   * Multiple threads each `arc_free` independently; whichever
//     calls last releases the storage.
//   * You want shared semantics with thread safety guaranteed by
//     the count alone (Arc), or combined with an inner `Mutex`
//     (Arc[Mutex] pattern, for shared mutation).
//
// Do NOT use when:
//   * Single-threaded — `Rc[T]` saves the atomic-op overhead.
//   * Unambiguous owner — `Box[T]` is one allocation away.
//
// API:
//
//   ( arc_new      [T] x )         → ( Arc T )   count = 1
//   ( arc_zero     [T] )           → ( Arc T )   count = 1, value zero-init
//   ( arc_get      [T] r )         → T           load value (race-prone, see TRAP)
//   ( arc_set      [T] r x )       → v           overwrite value (NOT atomic on T)
//   ( arc_ptr      [T] r )         → *T          borrowed raw pointer
//   ( arc_clone    [T] r )         → ( Arc T )   atomic count++
//   ( arc_strong   [T] r )         → i           current count (snapshot, racy)
//   ( arc_free     [T] r )         → v           early release (a handle is dropped by its owner)
//   ( arc_free_with [T] r drop )   → v           atomic dec; drop(T) before free
//
// Layout (SAME as Rc but the count is touched only via atomics):
//
//   ArcImpl[T] = { i count, T value }
//
// TRAP — value reads ARE NOT atomic:
//
//   Only the COUNT is touched atomically. `arc_get` / `arc_set`
//   read/write the value field with ordinary loads/stores. If T is
//   larger than the platform's pointer (i.e. anything but a single
//   integer / pointer / bool), concurrent reads and writes are a
//   data race. The Arc protects ownership/lifetime, NOT field
//   integrity.
//
//   Because an Arc exists to be SHARED, its payload is the one place
//   the compiler asks the harder of the two thread-safety questions:
//   T must be `Sync`, not merely `Send` (stdlib/core/marker.nu). That
//   is why `( Arc ( Rc i ) )` and `( Arc Cell )` are rejected at the
//   thread boundary while a bare `Cell` capture — moved, not shared —
//   is fine. What the check does NOT do is stop two threads mutating
//   a `( Arc ( Vec i ) )`'s contents: `Vec` is Sync, correctly, since
//   sharing one read-only is ordinary code. That race is caught
//   separately, at the mutation, by the shared-mutation check
//   (docs/MEMORY.md §6.5) — which recommends exactly the pattern
//   below.
//
//   For shared MUTATION across threads, wrap T in a
//   Mutex (the Arc[Mutex[T]] pattern):
//
//     : ( Arc Mutex ) shared ( arc_new ( mutex_new ) )
//     // every thread holds an arc_clone of `shared`; locks the
//     // mutex before touching the data the mutex protects.
//
//   Or for read-mostly: have each thread hold an arc_clone of an
//   immutable T; rebuild a NEW Arc on update and swap atomically
//   via a separate pointer slot (the canonical Arc-swap pattern).
//
// TRAP — owned-T copy semantics:
//
//   Same as `box_get` / `rc_get`. Bitwise copy aliases inner
//   pointers. For thread-safe owned-T sharing use Arc[Mutex<…>]
//   plus deep-clone whenever a copy is needed.

// FFI: atomic refcount primitives (stdlib/runtime.c).
//   nurl_atomic_i64_inc(p)       → old value (fetch-add 1)
//   nurl_atomic_i64_dec_fetch(p) → NEW value (sub-fetch 1)
//   nurl_atomic_i64_load(p)      → current value (acquire-load)
& `c` @ nurl_atomic_i64_inc *u p → i

& `c` @ nurl_atomic_i64_dec_fetch *u p → i

& `c` @ nurl_atomic_i64_load *u p → i

& `c` @ nurl_atomic_i64_inc_if_live *u p → i

// [ count ][ weak ][ value ]. `weak` counts the Weak handles plus one held
// by the strong handles together: the last strong handle drops the value
// and gives that one up, and whoever takes `weak` to zero frees the block
// (Rust's scheme — no strong and weak race over the free).
: ArcImpl [A] {
    i count
    i weak
    A value
}

: Arc [A] { s ctl }

: ArcWeak [A] { s ctl }

// ── Constructors ────────────────────────────────────────────────────

@ arc_new [A] A x → ( Arc A ) {
    : *( ArcImpl A ) impl # *( ArcImpl A ) ( nurl_alloc Z ( ArcImpl A ) )
    = . impl count 1
    = . impl weak 1
    = . impl value x
    ^ @ ( Arc A ) { # s impl }
}

@ arc_zero [A] → ( Arc A ) {
    : *( ArcImpl A ) impl # *( ArcImpl A ) ( nurl_zalloc Z ( ArcImpl A ) )
    = . impl count 1
    = . impl weak 1
    ^ @ ( Arc A ) { # s impl }
}

// ── Inspectors ──────────────────────────────────────────────────────

// Snapshot of the count. Racy by definition — by the time the value
// is returned, another thread may have already cloned or freed. Use
// for diagnostics and tests; do not branch on it for correctness.
@ arc_strong [A] ( Arc A ) r → i {
    : *u cp # *u . r ctl
    ^ ( nurl_atomic_i64_load cp )
}

// ── Access ──────────────────────────────────────────────────────────

// The shared value. For a payload that can hold a handle back to this Arc
// (mem_ts_cyclic) it is a COPY: such an Arc is frozen once made, so no
// cycle of shared handles can be closed through it (docs/MEMORY.md §7.7).
@ arc_get [A] ( Arc A ) r → A {
    : *( ArcImpl A ) impl # *( ArcImpl A ) . r ctl
    ? ( mem_ts_cyclic [( Arc A )] ) {
        : A v . impl value
        ^ ( mem_dup v )
    } {}
    ^ . impl value
}

@ arc_set [A] ( Arc A ) r A x → v {
    ( mem_ts_frozen_only [( Arc A )] arc_set )
    : *( ArcImpl A ) impl # *( ArcImpl A ) . r ctl
    // The old value is dropped.
    : A old . impl value
    ( mem_take old )
    = . impl value x
}

@ arc_ptr [A] ( Arc A ) r → *A {
    ( mem_ts_frozen_only [( Arc A )] arc_ptr )
    : i base # i . r ctl
    : *A p # *A + base 16
    ^ p
}

// ── Cloning ─────────────────────────────────────────────────────────

// Atomic increment of the strong count. After this call you have
// two Arc handles to the same storage, each dropped by its owner.
@ arc_clone [A] ( Arc A ) r → ( Arc A ) {
    : *u cp # *u . r ctl
    ( nurl_atomic_i64_inc cp )
    // A handle of its own (not a view of `r`): the caller owns it.
    : s c . r ctl
    ^ @ ( Arc A ) { c }
}

// ── Lifecycle ───────────────────────────────────────────────────────

// What dropping a handle does (its owner does it at scope exit — docs/
// MEMORY.md §7.6): an atomic decrement, and the last handle drops the
// value and releases the storage.
@ Arc_drop [A] sink ( Arc A ) r → v {
    // This IS the drop: `r` is not dropped again on the way out.
    ( mem_forget r )
    : *u cp # *u . r ctl
    ? == 0 # i cp {} {
        : i n ( nurl_atomic_i64_dec_fetch cp )
        ? <= n 0 {
            : *( ArcImpl A ) impl # *( ArcImpl A ) . r ctl
            : A v . impl value
            ( mem_take v )
            ( __arc_weak_release # s cp )
        } {}
    }
}

// The strong handles' shared Weak, or a Weak handle, goes: the last frees
// the block.
@ __arc_weak_release s ctl → v {
    : *u wp # *u + # i ctl 8
    ? <= ( nurl_atomic_i64_dec_fetch wp ) 0 { ( nurl_free ctl ) } {}
}

// Another owner of the same value: the count goes up, nothing is copied.
@ Arc_share [A] ( Arc A ) r → ( Arc A ) {
    ^ ( arc_clone [A] r )
}

// Early release of this handle (Arc_drop).
@ arc_free [A] sink ( Arc A ) r → v {}

// Release this handle as `arc_free` does (an atomic decrement); the owner
// that takes the count to zero lends `drop` the final value first (then the
// value is dropped and the storage released). The hook only borrows — see
// vec_free_with.
@ arc_free_with [A] sink ( Arc A ) r ( @ v A ) drop → v {
    ( mem_forget r )
    : *u cp # *u . r ctl
    ? == 0 # i cp {} {
        : i n ( nurl_atomic_i64_dec_fetch cp )
        ? <= n 0 {
            : *( ArcImpl A ) impl # *( ArcImpl A ) . r ctl
            : A v . impl value
            ( mem_take v )
            ( drop v )
            ( __arc_weak_release # s impl )
        } {}
    }
}

// ── Weak handles ────────────────────────────────────────────────────

// A handle that does not keep the value alive — for a back-edge (a child's
// pointer to its parent, a callback that must not own the server it is
// stored in) that would otherwise close a cycle of strong handles, which
// counting never frees (docs/MEMORY.md §7.7).
@ arc_downgrade [A] ( Arc A ) r → ( ArcWeak A ) {
    : *u wp # *u + # i . r ctl 8
    ( nurl_atomic_i64_inc wp )
    : s c . r ctl
    ^ @ ( ArcWeak A ) { c }
}

// A strong handle again while the value is alive, `F` once it is gone.
@ arc_weak_upgrade [A] ( ArcWeak A ) w → ?( Arc A ) {
    : *u cp # *u . w ctl
    ? == 0 ( nurl_atomic_i64_inc_if_live cp ) { ^ @ ?( Arc A ) { F } } {}
    : s c . w ctl
    ^ @ ?( Arc A ) { T @ ( Arc A ) { c } }
}

@ ArcWeak_drop [A] sink ( ArcWeak A ) w → v {
    ( mem_forget w )
    ? == 0 # i . w ctl { ^ } {}
    ( __arc_weak_release . w ctl )
}

@ ArcWeak_share [A] ( ArcWeak A ) w → ( ArcWeak A ) {
    : *u wp # *u + # i . w ctl 8
    ( nurl_atomic_i64_inc wp )
    : s c . w ctl
    ^ @ ( ArcWeak A ) { c }
}
