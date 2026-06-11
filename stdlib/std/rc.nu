// stdlib/std/rc.nu — single-threaded reference-counted heap allocation.
//
// `Rc[T]` is a shared-ownership heap slot: multiple handles can point
// at the same value of type T, and the storage is released exactly
// when the LAST handle calls `rc_free`. Conceptually identical to
// Rust's `Rc<T>` or C++'s `std::shared_ptr<T>` — but NOT thread-safe;
// the counter uses ordinary reads / writes. Cross-thread sharing
// requires `Arc[T]` (stdlib/std/arc.nu) which has atomic counter ops.
//
// Use when:
//   * Multiple modules need read access to the same large struct
//     (config / parsed-AST shared across passes).
//   * A graph / tree has nodes referenced from several parents
//     within a single thread.
//   * You want shared semantics without the lifetime gymnastics of
//     bare pointers.
//
// Do NOT use when:
//   * The owner is unambiguous — `Box[T]` is cheaper (one alloc, no
//     count field, no clone/free count manipulation).
//   * You spawn worker threads holding the same handle — that's
//     `Arc[T]`. An `Rc[T]` shared across threads is UB.
//
// API:
//
//   ( rc_new      [T] x )          → ( Rc T )   count = 1
//   ( rc_zero     [T] )            → ( Rc T )   count = 1, value zero-init
//   ( rc_get      [T] r )          → T          load value by value (see TRAP)
//   ( rc_set      [T] r x )        → v          overwrite value (CAUTION: shared)
//   ( rc_replace  [T] r x )        → T          store new, return old
//   ( rc_ptr      [T] r )          → *T         borrowed raw pointer (FFI)
//   ( rc_clone    [T] r )          → ( Rc T )   bump count, share storage
//   ( rc_strong   [T] r )          → i          current strong count
//   ( rc_is_unique [T] r )         → b          count == 1 (safe to mutate)
//   ( rc_free     [T] r )          → v          dec count; free when 0
//   ( rc_free_with [T] r drop )    → v          dec count; if 0 run drop(T) then free
//
// Layout:
//
//   ( Rc T ) is a single-pointer handle to a `RcImpl[T]`:
//     RcImpl[T] = { i count, T value }
//   so the heap allocation holds the count interleaved with the
//   value. `rc_ptr` returns `&impl.value` (offset 8 from the alloc
//   base). `rc_clone` increments `count` without copying the value.
//
// TRAP — shared mutation:
//
//   Multiple handles share one storage slot. Calling `rc_set` /
//   `rc_replace` mutates what EVERY clone sees — there is no copy-
//   on-write. If you need that, check `rc_is_unique` first:
//
//     ? ( rc_is_unique r ) { ( rc_set r x ) }
//     { : ( Rc T ) fresh ( rc_new x ) /* and rewire the clone tree */ }
//
//   The same shared-state trap exists in Rust's `Rc<RefCell<T>>` —
//   NURL's solution is the same: only mutate when you can prove
//   you're alone. For multi-writer scenarios with multiple threads
//   use `Arc[Mutex<T>]` — wrap an Arc around a Mutex around T.
//
// TRAP — owned-T copy semantics:
//
//   Same as `box_get` (see stdlib/core/box.nu). For owned T (String,
//   Vec, HashMap, nested Rc/Box), `rc_get` bitwise-aliases the inner
//   pointer. Use `rc_ptr` to read through, or `rc_clone_with` if you
//   need an owned-T independent copy out of the shared slot.
//
// Lifecycle pattern:
//
//   : ( Rc Config ) cfg ( rc_new ( parse_config ) )
//   ( http_serve ( rc_clone cfg ) )      // server thread gets a clone
//   ( metrics_emit ( rc_clone cfg ) )    // metrics thread gets a clone
//   ( rc_free_with cfg \ c → v { ( config_free c ) } )
//   // each rc_clone'd recipient also calls rc_free_with on shutdown;
//   // the last one runs the drop closure.


: RcImpl [T] {
    i count
    T value
}

: Rc [T] { s ctl }

// ── Constructors ────────────────────────────────────────────────────

@ rc_new [T] T x → ( Rc T ) {
    : *( RcImpl T ) impl # *( RcImpl T ) ( nurl_alloc Z ( RcImpl T ) )
    = . impl count 1
    = . impl value x
    ^ @ ( Rc T ) { # s impl }
}

@ rc_zero [T] → ( Rc T ) {
    : *( RcImpl T ) impl # *( RcImpl T ) ( nurl_zalloc Z ( RcImpl T ) )
    = . impl count 1
    ^ @ ( Rc T ) { # s impl }
}

// ── Inspectors ──────────────────────────────────────────────────────

@ rc_strong [T] ( Rc T ) r → i {
    : *( RcImpl T ) impl # *( RcImpl T ) . r ctl
    ^ . impl count
}

@ rc_is_unique [T] ( Rc T ) r → b {
    : *( RcImpl T ) impl # *( RcImpl T ) . r ctl
    ^ == . impl count 1
}

// ── Access ──────────────────────────────────────────────────────────

@ rc_get [T] ( Rc T ) r → T {
    : *( RcImpl T ) impl # *( RcImpl T ) . r ctl
    ^ . impl value
}

// Overwrite the shared value. EVERY rc_clone of this handle sees the
// new value — there is no copy-on-write. See TRAP comment above.
@ rc_set [T] ( Rc T ) r T x → v {
    : *( RcImpl T ) impl # *( RcImpl T ) . r ctl
    = . impl value x
}

// Overwrite and return the old value. Same shared-mutation caveat.
// Required for owned-T payloads — gives the caller ownership of the
// previous value so cleanup can run on it.
@ rc_replace [T] ( Rc T ) r T x → T {
    : *( RcImpl T ) impl # *( RcImpl T ) . r ctl
    : T old . impl value
    = . impl value x
    ^ old
}

// Borrowed raw `*T` to the shared value's slot. Useful for FFI calls
// that mutate through a pointer (initialising a struct in place).
// Valid until the LAST rc_free; immune to rc_clone (the storage
// outlives any single handle by design).
@ rc_ptr [T] ( Rc T ) r → *T {
    : *( RcImpl T ) impl # *( RcImpl T ) . r ctl
    // Compute &impl->value by GEPing past the count field. NURL's
    // `. impl value` syntax loads the value; for a pointer we take
    // the impl pointer, add `Z i` (= 8) bytes, and bitcast to *T.
    : i base # i impl
    : *T p # *T + base ( field_off_value )
    ^ p
}

// Helper: byte offset of `value` within RcImpl[T]. Counted as one
// i64 (the count field) wide. Kept as a one-line @-fn so the
// constant is visible in IR and the lowering is predictable.
@ field_off_value → i {
    ^ 8
}

// ── Cloning ─────────────────────────────────────────────────────────

// Increment the strong count; return a new handle pointing at the
// same storage. O(1). After `rc_clone` you have TWO handles that
// must both eventually `rc_free`.
@ rc_clone [T] ( Rc T ) r → ( Rc T ) {
    : *( RcImpl T ) impl # *( RcImpl T ) . r ctl
    = . impl count + . impl count 1
    ^ @ ( Rc T ) { . r ctl }
}

// ── Lifecycle ───────────────────────────────────────────────────────

// Decrement the strong count. If the count reaches zero, release the
// storage — but DOES NOT run any per-payload drop. For owned-T
// payloads use `rc_free_with`.
@ rc_free [T] ( Rc T ) r → v {
    : *( RcImpl T ) impl # *( RcImpl T ) . r ctl
    ? == 0 # i impl {} {
        = . impl count - . impl count 1
        ? <= . impl count 0 { ( nurl_free # s impl ) } {}
    }
}

// Decrement the strong count. If it reaches zero, run `drop` on the
// final value, then release the storage. Use for owned-T payloads:
//   ( rc_free_with [Config] cfg \ c → v { ( config_free c ) } )
@ rc_free_with [T] ( Rc T ) r ( @ v T ) drop → v {
    : *( RcImpl T ) impl # *( RcImpl T ) . r ctl
    ? == 0 # i impl {} {
        = . impl count - . impl count 1
        ? <= . impl count 0 {
            ( drop . impl value )
            ( nurl_free # s impl )
        } {}
    }
}
