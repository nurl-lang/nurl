// stdlib/std/rc.nu — single-threaded reference-counted heap allocation.
//
// `Rc[T]` is a shared-ownership heap slot: several handles point at one
// value of type T, and the value is dropped when the LAST handle goes —
// handles are dropped by their owners like any library handle (docs/
// MEMORY.md §7.6); `rc_free` is an early release. NOT thread-safe: the
// counts use ordinary reads and writes, and since `Send`/`Sync`
// (stdlib/core/marker.nu) an Rc reaching `thread_spawn`, `spawn` or
// `chan_send` — directly, through a field, an element, a payload or a
// closure capture — is a compile error. Cross-thread sharing is `Arc[T]`
// (stdlib/std/arc.nu).
//
// Cycles are collected. A value that, through its own contents, holds an
// Rc to itself (a graph node listing its neighbours, a closure stored in
// the value it captured) keeps its count above zero forever under plain
// counting. For a payload type whose ownership graph can close — the
// compiler decides (`mem_cyclic`) — every handle that goes without
// reaching zero files its block as a possible root, and the context's
// cycle collector (stdlib/runtime_core.c) finds and releases the
// unreachable cycles: when enough roots pile up, and when the thread, the
// fiber or the program ends (docs/MEMORY.md §7.7). An acyclic payload —
// every Rc[String], Rc[Config], a tree of Rc whose nodes hold no Rc back —
// never pays for it. `Weak[T]` (rc_downgrade / weak_upgrade) is a
// non-owning handle for back-edges whose target must not be kept alive.
//
// API:
//
//   ( rc_new       [T] x )          → ( Rc T )    count = 1
//   ( rc_zero      [T] )            → ( Rc T )    count = 1, value zero-init
//   ( rc_get       [T] r )          → T           the shared value, lent
//   ( rc_set       [T] r x )        → v           overwrite (shared: every handle sees it)
//   ( rc_replace   [T] r x )        → T           store new, return old
//   ( rc_ptr       [T] r )          → *T          raw pointer (FFI; manual territory)
//   ( rc_clone     [T] r )          → ( Rc T )    another handle, count + 1
//   ( rc_strong    [T] r )          → i           current strong count
//   ( rc_weak      [T] r )          → i           current weak count
//   ( rc_is_unique [T] r )          → b           count == 1 (safe to mutate)
//   ( rc_free      [T] r )          → v           early release of this handle
//   ( rc_free_with [T] r look )     → v           release; the last handle lends `look` the value first
//   ( rc_downgrade [T] r )          → ( Weak T )  a non-owning handle
//   ( weak_upgrade [T] w )          → ?( Rc T )   a handle again, if the value is still alive
//   ( rc_collect )                  → v           collect this context's cycles now
//
// Layout: ( Rc T ) and ( Weak T ) are one pointer to
//   RcImpl[T] = [ i strong ][ i weak ][ i cc ][ T value ]
// The value is dropped when the strong count reaches zero; the block is
// freed when the weak count is zero too (and the collector no longer
// lists it). `cc` is the collector's word (colour, buffered, dead).
//
// Shared mutation: `rc_set` / `rc_replace` change what EVERY handle sees —
// there is no copy-on-write. Check `rc_is_unique` first when that matters.

& `c` @ nurl_cc_possible_root s impl s ops → v

& `c` @ nurl_cc_dead s impl → i32

& `c` @ nurl_rc_drop_value s impl s ops → v

& `c` @ nurl_cc_buffered s impl → i32

& `c` @ nurl_cc_collect → v

: RcImpl [A] {
    i count
    i weak
    i cc
    A value
}

: Rc [A] { s ctl }

: Weak [A] { s ctl }

// ── Constructors ────────────────────────────────────────────────────

@ rc_new [A] A x → ( Rc A ) {
    : *( RcImpl A ) impl # *( RcImpl A ) ( nurl_alloc Z ( RcImpl A ) )
    = . impl count 1
    = . impl weak 0
    = . impl cc 0
    = . impl value x
    ^ @ ( Rc A ) { # s impl }
}

@ rc_zero [A] → ( Rc A ) {
    : *( RcImpl A ) impl # *( RcImpl A ) ( nurl_zalloc Z ( RcImpl A ) )
    = . impl count 1
    ^ @ ( Rc A ) { # s impl }
}

// ── Inspectors ──────────────────────────────────────────────────────

@ rc_strong [A] ( Rc A ) r → i {
    : *( RcImpl A ) impl # *( RcImpl A ) . r ctl
    ^ . impl count
}

@ rc_weak [A] ( Rc A ) r → i {
    : *( RcImpl A ) impl # *( RcImpl A ) . r ctl
    ^ . impl weak
}

@ rc_is_unique [A] ( Rc A ) r → b {
    : *( RcImpl A ) impl # *( RcImpl A ) . r ctl
    ^ == . impl count 1
}

// ── Access ──────────────────────────────────────────────────────────

// The shared value, lent: a binding of it borrows from the handle, and
// storing or returning it copies (docs/MEMORY.md §7.6).
@ rc_get [A] ( Rc A ) r → A {
    : *( RcImpl A ) impl # *( RcImpl A ) . r ctl
    ^ . impl value
}

// Overwrite the shared value; the old one is dropped. EVERY handle sees
// the new value.
@ rc_set [A] ( Rc A ) r A x → v {
    : *( RcImpl A ) impl # *( RcImpl A ) . r ctl
    : A old . impl value
    ( mem_take old )
    = . impl value x
}

// Overwrite and hand back the old value (the caller's from now on).
@ rc_replace [A] ( Rc A ) r A x → A {
    : *( RcImpl A ) impl # *( RcImpl A ) . r ctl
    : A old . impl value
    ( mem_take old )
    = . impl value x
    ^ old
}

// A raw `*T` to the shared value's slot, for FFI that fills a struct in
// place. Writing a value through it is manual memory management: the
// slot's previous value is not dropped (docs/MEMORY.md §7.4).
@ rc_ptr [A] ( Rc A ) r → *A {
    : *( RcImpl A ) impl # *( RcImpl A ) . r ctl
    : i base # i impl
    ^ # *A + base 24
}

// ── Handles ─────────────────────────────────────────────────────────

// Another handle on the same value: the count goes up, nothing is copied.
@ rc_clone [A] ( Rc A ) r → ( Rc A ) {
    : *( RcImpl A ) impl # *( RcImpl A ) . r ctl
    = . impl count + . impl count 1
    : s c . r ctl
    ^ @ ( Rc A ) { c }
}

// What dropping a handle does (its owner does it at scope exit): the
// count goes down; the last handle drops the value, and the block goes
// once no Weak is left. A handle that leaves the count above zero may
// have left a cycle behind: for a payload that can form one, the block
// is filed with the collector.
@ Rc_drop [A] sink ( Rc A ) r → v {
    // This IS the drop: `r` is not dropped again on the way out.
    ( mem_forget r )
    : *( RcImpl A ) impl # *( RcImpl A ) . r ctl
    ? == 0 # i impl { ^ } {}
    ? ( mem_cyclic [A] ) {
        // An edge out of a value the collector is releasing: the block it
        // points at is being released too, or was counted already.
        ? != 0 ( nurl_cc_dead # s impl ) { ^ } {}
    } {}
    = . impl count - . impl count 1
    ? <= . impl count 0 {
        // A value that holds handles of its own is released by the runtime
        // (nurl_rc_drop_value), which keeps a long chain of releases off the
        // stack; a leaf value is dropped right here.
        ? ( mem_rc_nested [A] ) { ( nurl_rc_drop_value # s impl ( mem_cc_ops [A] ) ) ^ } {}
        : A v . impl value
        ( mem_take v )
        ? == 0 . impl weak { ( nurl_free # s impl ) } {}
    } {
        ? ( mem_cyclic [A] ) { ( nurl_cc_possible_root # s impl ( mem_cc_ops [A] ) ) } {}
    }
}

// Another owner of the same value: the count goes up, nothing is copied.
@ Rc_share [A] ( Rc A ) r → ( Rc A ) {
    ^ ( rc_clone [A] r )
}

// Early release of this handle (Rc_drop).
@ rc_free [A] sink ( Rc A ) r → v {}

// Release this handle as `rc_free` does; when it is the last one, `look`
// is lent the final value first. The hook only borrows (a closure's
// parameters always do, docs/MEMORY.md §7.5).
@ rc_free_with [A] sink ( Rc A ) r ( @ v A ) look → v {
    : *( RcImpl A ) impl # *( RcImpl A ) . r ctl
    ? & != 0 # i impl == . impl count 1 { ( look . impl value ) } {}
}

// ── Weak handles ────────────────────────────────────────────────────

// A handle that does not keep the value alive: for a back-edge (a child's
// pointer to its parent) whose target lives exactly as long as its strong
// handles say.
@ rc_downgrade [A] ( Rc A ) r → ( Weak A ) {
    : *( RcImpl A ) impl # *( RcImpl A ) . r ctl
    = . impl weak + . impl weak 1
    : s c . r ctl
    ^ @ ( Weak A ) { c }
}

// A strong handle again while the value is alive, `F` once it is gone.
@ weak_upgrade [A] ( Weak A ) w → ?( Rc A ) {
    : *( RcImpl A ) impl # *( RcImpl A ) . w ctl
    ? | == 0 # i impl <= . impl count 0 { ^ @ ?( Rc A ) { F } } {}
    = . impl count + . impl count 1
    : s c . w ctl
    ^ @ ?( Rc A ) { T @ ( Rc A ) { c } }
}

@ Weak_drop [A] sink ( Weak A ) w → v {
    ( mem_forget w )
    : *( RcImpl A ) impl # *( RcImpl A ) . w ctl
    ? == 0 # i impl { ^ } {}
    = . impl weak - . impl weak 1
    ? & == 0 . impl weak <= . impl count 0 {
        ? == 0 ( nurl_cc_buffered # s impl ) { ( nurl_free # s impl ) } {}
    } {}
}

@ Weak_share [A] ( Weak A ) w → ( Weak A ) {
    : *( RcImpl A ) impl # *( RcImpl A ) . w ctl
    ? != 0 # i impl { = . impl weak + . impl weak 1 } {}
    : s c . w ctl
    ^ @ ( Weak A ) { c }
}

// ── Collection ──────────────────────────────────────────────────────

// Collect this context's unreachable cycles now (it also happens on its
// own, and at the end of every thread, fiber and the program).
@ rc_collect → v {
    ( nurl_cc_collect )
}
