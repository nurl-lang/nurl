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
//     the count alone (Arc), or shared state threads change, held in
//     a `Locked` (the Arc[Locked] pattern, stdlib/std/thread.nu).
//
// Do NOT use when:
//   * Single-threaded — `Rc[T]` saves the atomic-op overhead.
//   * Unambiguous owner — `Box[T]` is one allocation away.
//
// API:
//
//   ( arc_new      [T] x )         → ( Arc T )   count = 1
//   ( arc_zero     [T] )           → ( Arc T )   count = 1, value zero-init
//   ( arc_get      [T] r )         → T           the payload, read-only (see below)
//   ( arc_set      [T] r x )       → v           overwrite value (unsafe only)
//   ( arc_ptr      [T] r )         → *T          borrowed raw pointer
//   ( arc_clone    [T] r )         → ( Arc T )   atomic count++
//   ( arc_strong   [T] r )         → i           current count (snapshot, racy)
//   ( arc_free     [T] r )         → v           early release (a handle is dropped by its owner)
//   ( arc_free_with [T] r drop )   → v           atomic dec; drop(T) before free
//   ( arc_into_word [T] r )        → i           the handle as a word (raw: unsafe only)
//   ( arc_from_word [T] w )        → ( Arc T )   …and back
//   ( arc_word_share [T] w )       → ( Arc T )   another owner, the word keeps its own
//
// Layout (SAME as Rc but the count is touched only via atomics):
//
//   ArcImpl[T] = { i count, T value }
//
// An Arc's payload is frozen once made (docs/MEMORY.md §6.5):
//
//   Only the COUNT is touched atomically; the payload is read with
//   ordinary loads by every thread holding a clone. So safe code never
//   changes it after `arc_new`: a mutation of what `arc_get` lends — a
//   container mutator, a field, a helper or a String's or a map's own
//   mutator handed it — is a compile error, wherever it is and whatever
//   lock is held (a lock the compiler cannot tie to the data proves
//   nothing). Build the value first and `arc_new` it whole. State
//   threads share and change goes in a `Locked` (stdlib/std/thread.nu):
//   a shared handle of its own, reached only through `locked_with` /
//   `locked_get` / `locked_set`, which hold its lock for the call:
//
//     : ( Locked ( Vec i ) ) shared ( locked_new [( Vec i )] v )
//     // in each worker:
//     ( locked_with [( Vec i )] shared \ ( Vec i ) xs → v { ( vec_push [i] xs 1 ) } )
//
//   A payload whose type synchronises itself (asserted `% Sync`: a
//   Mutex, a Channel, a Locked) is changed through its own operations.
//   State one thread changes belongs in an `Rc`. `arc_set` replaces the
//   payload in place, so it is `unsafe`: raw code vouches that no other
//   thread can see it.
//
//   Because an Arc exists to be SHARED, its payload is the one place
//   the compiler asks the harder of the two thread-safety questions:
//   T must be `Sync`, not merely `Send` (stdlib/core/marker.nu). That
//   is why `( Arc ( Rc i ) )` and `( Arc Cell )` are rejected at the
//   thread boundary while a bare `Cell` capture — moved, not shared —
//   is fine.

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

// The counts as the rcbox handles keep theirs (runtime_core.c): an owner
// that finds itself the only one — strong count 1 and no Weak — skips the
// locked read-modify-write. _share hands back the count before; _release
// is 1 for the last strong owner and 2 for the only owner of a block no
// Weak names (the block is then its to free). nurl_rc_release on the weak
// count: 1 for the last holder of the block.
& `c` @ nurl_arc_share *u p → i

& `c` @ nurl_arc_release *u p → i

& `c` @ nurl_rc_release *u p → i

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

unsafe @ arc_set [A] ( Arc A ) r A x → v {
    ( mem_ts_frozen_only [( Arc A )] arc_set )
    : *( ArcImpl A ) impl # *( ArcImpl A ) . r ctl
    = . impl value x  // drops the old value
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
    ( nurl_arc_share cp )
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
        : i last ( nurl_arc_release cp )
        ? != 0 last {
            : *( ArcImpl A ) impl # *( ArcImpl A ) . r ctl
            : A v . impl value
            ( mem_take v )
            ? == last 2 { ( nurl_free # s cp ) } { ( __arc_weak_release # s cp ) }
        } {}
    }
}

// The strong handles' shared Weak, or a Weak handle, goes: the last frees
// the block.
@ __arc_weak_release s ctl → v {
    : *u wp # *u + # i ctl 8
    ? != 0 ( nurl_rc_release wp ) { ( nurl_free ctl ) } {}
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
        : i last ( nurl_arc_release cp )
        ? != 0 last {
            : *( ArcImpl A ) impl # *( ArcImpl A ) . r ctl
            : A v . impl value
            ( mem_take v )
            ( drop v )
            ? == last 2 { ( nurl_free # s impl ) } { ( __arc_weak_release # s impl ) }
        } {}
    }
}

// ── As one word ─────────────────────────────────────────────────────

// A handle as a plain word, for state a module keeps in a global (a
// global holds a scalar): arc_into_word gives the handle's ownership to the
// word, arc_from_word takes it back, arc_word_share makes another owner
// and leaves the word its own. The word carries no type, so these are raw
// primitives (spec §3.3d): only an `unsafe` function may call them, and
// only with a word arc_into_word made for the same A.
@ arc_into_word [A] sink ( Arc A ) r → i {
    ( mem_forget r )
    ^ # i . r ctl
}

@ arc_from_word [A] i w → ( Arc A ) {
    : s c # s w
    ^ @ ( Arc A ) { c }
}

@ arc_word_share [A] i w → ( Arc A ) {
    ( nurl_arc_share # *u w )
    : s c # s w
    ^ @ ( Arc A ) { c }
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
