// stdlib/std/atomic.nu — a 64-bit integer every thread may change at once.
//
// A counter that threads share and change — the next transaction id, a
// log sequence number, a pin count, a stop flag — is neither an `Arc`
// (whose payload is frozen once made, docs/MEMORY.md §6.5) nor worth a
// `Locked` (a mutex round trip for one add). An `Atomic` is a shared handle
// over one word that is only ever read and written with atomic
// instructions, so safe code on any number of threads changes it without
// a lock and without a data race. Every copy of the handle is the same
// word; the last one releases it.
//
//   ( atomic_new x )                 → Atomic   a word holding x
//   ( atomic_load a )                → i
//   ( atomic_store a x )             → v
//   ( atomic_add a d )               → i        fetch-add: the value BEFORE
//   ( atomic_sub a d )               → i        fetch-sub: the value BEFORE
//   ( atomic_swap a x )              → i        the value it replaced
//   ( atomic_cas a expect desired )  → b        stored `desired` iff the
//                                               value was `expect`
//   ( atomic_max a x )               → i        raise to at least x; the
//                                               value BEFORE
//
// Every operation is sequentially consistent: what one thread wrote before
// an operation is visible to a thread that sees its result. The word lives
// in a counted block (stdlib/core/rcbox.nu), so capture the handle in the
// closures a thread runs, store it in a struct or an `Arc`'s payload, or
// send it through a channel: every copy reaches the same word.

$ `stdlib/core/rcbox.nu`

& `c` @ nurl_atomic_i64_load in *u p → i

& `c` @ nurl_atomic_i64_store sync *u p i v → v

& `c` @ nurl_atomic_i64_fetch_add sync *u p i d → i

& `c` @ nurl_atomic_i64_swap sync *u p i v → i

& `c` @ nurl_atomic_i64_cas sync *u p i expect i desired → i

& `c` @ nurl_atomic_i64_fetch_max sync *u p i v → i

// The word: the block's value, reached only through the calls below.
: AtomicCell { i v }

: Atomic { ( Shared AtomicCell ) ctl }

// One word, changed only atomically: what any thread may hold and change.
% Send Atomic {}

% Sync Atomic {}

@ Atomic_share Atomic a → Atomic { ^ @ Atomic { ( shared_clone [AtomicCell] . a ctl ) } }

@ Atomic_drop sink Atomic a → v {}

@ atomic_new i x → Atomic { ^ @ Atomic { ( shared_new [AtomicCell] @ AtomicCell { x } ) } }

// The word's address: the cell is the block's whole value.
@ __atomic_word Atomic a → *u { ^ # *u ( shared_ptr [AtomicCell] . a ctl ) }

@ atomic_load Atomic a → i { ^ ( nurl_atomic_i64_load ( __atomic_word a ) ) }

@ atomic_store Atomic a i x → v { ( nurl_atomic_i64_store ( __atomic_word a ) x ) }

@ atomic_add Atomic a i d → i { ^ ( nurl_atomic_i64_fetch_add ( __atomic_word a ) d ) }

@ atomic_sub Atomic a i d → i { ^ ( nurl_atomic_i64_fetch_add ( __atomic_word a ) - 0 d ) }

@ atomic_swap Atomic a i x → i { ^ ( nurl_atomic_i64_swap ( __atomic_word a ) x ) }

@ atomic_cas Atomic a i expect i desired → b {
    ^ == ( nurl_atomic_i64_cas ( __atomic_word a ) expect desired ) expect
}

@ atomic_max Atomic a i x → i { ^ ( nurl_atomic_i64_fetch_max ( __atomic_word a ) x ) }
