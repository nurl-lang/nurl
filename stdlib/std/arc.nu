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
//   ( arc_free     [T] r )         → v           atomic dec; free when 0
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
//   integrity. For shared MUTATION across threads, wrap T in a
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

: ArcImpl [T] {
    i count
    T value
}

: Arc [T] { s ctl }

// ── Constructors ────────────────────────────────────────────────────

@ arc_new [T] T x → ( Arc T ) {
    : *( ArcImpl T ) impl # *( ArcImpl T ) ( nurl_alloc Z ( ArcImpl T ) )
    = . impl count 1
    = . impl value x
    ^ @ ( Arc T ) { # s impl }
}

@ arc_zero [T] → ( Arc T ) {
    : *( ArcImpl T ) impl # *( ArcImpl T ) ( nurl_zalloc Z ( ArcImpl T ) )
    = . impl count 1
    ^ @ ( Arc T ) { # s impl }
}

// ── Inspectors ──────────────────────────────────────────────────────

// Snapshot of the count. Racy by definition — by the time the value
// is returned, another thread may have already cloned or freed. Use
// for diagnostics and tests; do not branch on it for correctness.
@ arc_strong [T] ( Arc T ) r → i {
    : *u cp # *u . r ctl
    ^ ( nurl_atomic_i64_load cp )
}

// ── Access ──────────────────────────────────────────────────────────

@ arc_get [T] ( Arc T ) r → T {
    : *( ArcImpl T ) impl # *( ArcImpl T ) . r ctl
    ^ . impl value
}

@ arc_set [T] ( Arc T ) r T x → v {
    : *( ArcImpl T ) impl # *( ArcImpl T ) . r ctl
    = . impl value x
}

@ arc_ptr [T] ( Arc T ) r → *T {
    : i base # i . r ctl
    : *T p # *T + base 8
    ^ p
}

// ── Cloning ─────────────────────────────────────────────────────────

// Atomic increment of the strong count. After this call you have
// two Arc handles to the same storage; both must eventually call
// `arc_free` (or `arc_free_with`).
@ arc_clone [T] ( Arc T ) r → ( Arc T ) {
    : *u cp # *u . r ctl
    ( nurl_atomic_i64_inc cp )
    ^ @ ( Arc T ) { . r ctl }
}

// ── Lifecycle ───────────────────────────────────────────────────────

// Atomic-decrement the strong count. If it reaches zero, the storage
// is released. Caller is responsible for any per-payload cleanup
// when T is owned — use `arc_free_with` instead.
@ arc_free [T] ( Arc T ) r → v {
    : *u cp # *u . r ctl
    ? == 0 # i cp {} {
        : i n ( nurl_atomic_i64_dec_fetch cp )
        ? <= n 0 { ( nurl_free # s cp ) } {}
    }
}

// Atomic-decrement; if the count reached zero, run `drop` on the
// final value and then release the storage.
@ arc_free_with [T] ( Arc T ) r ( @ v T ) drop → v {
    : *u cp # *u . r ctl
    ? == 0 # i cp {} {
        : i n ( nurl_atomic_i64_dec_fetch cp )
        ? <= n 0 {
            : *( ArcImpl T ) impl # *( ArcImpl T ) . r ctl
            ( drop . impl value )
            ( nurl_free # s impl )
        } {}
    }
}
