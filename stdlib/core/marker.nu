// stdlib/core/marker.nu — Send / Sync, the thread-safety marker traits, Frozen and Resource.
//
// Two questions a thread boundary asks about a type, and nothing else:
//
//   Send — may a value of this type MOVE to another thread?
//   Sync — may two threads reach ONE value of this type at once?
//
// Both are marker traits: no methods, no runtime representation, no
// dispatch. A `% Send T { }` block is not code — it is an assertion,
// NURL's spelling of Rust's `unsafe impl Send for T`, and outside the
// standard library it is written that way: `unsafe % Send T { }`
// (docs/MEMORY.md §3; `nurlc --unsafe-report` lists it).
//
// You rarely write either. The compiler DERIVES both structurally over
// a type's whole graph — struct fields, enum payloads, generic
// arguments, aggregate members, closure captures — and checks them
// where a value actually crosses a thread boundary:
//
//   ( thread_spawn f )   every value `f` captures must be Send
//   ( spawn f )          same (fibers migrate across M:N workers)
//   ( chan_send ch v )   `v` must be Send
//   ( Arc T )            T must be Send AND Sync — an Arc exists to be
//                        shared, so its payload faces the harder question
//   ( RwLocked T )       T must be Send AND Sync — several readers reach it
//                        at once; a Locked's, a Channel's or a Pool's T
//                        must be Send, even where a `% Sync` marker on the
//                        container stops the walk (it vouches for the
//                        container, never for what it holds)
//
// A handle whose copies are one state (a library handle over a counted
// block — a PNCounter, a TcpConn, a Cell — not asserted Sync) is Send, but
// only with every owner of that state: a copy left on this side would be
// changed by two threads with no lock. No type says how many copies a
// value has, so the crossing asks at run time: `( mem_send_check [T] x
// what )`, in thread_spawn, spawn, chan_send and a Locked's operations,
// panics unless every such handle x reaches has one owner
// (docs/MEMORY.md §6.5).
//
// The derivation has three levels, worst-wins across the graph:
//
//   Send + Sync    the default — scalars, strings, handles, structs of them
//   Send, !Sync    `Cell` — a raw byte buffer with unsynchronised writes
//   !Send, !Sync   `Rc`   — a non-atomic refcount; two threads touching
//                           the count is a data race on the count itself
//
// Those two leaves are language-level facts and live in the compiler.
// Everything else follows from them by construction: `( Vec ( Rc i ) )`,
// `( Arc ( Rc i ) )`, `( Box ( Rc i ) )`, a struct with an `( Rc i )`
// field, an enum variant carrying one, an option holding one, and a
// closure capturing any of those are all !Send for the same one reason,
// and the diagnostic names that reason rather than the spelling.
//
// A trait object is the one type whose graph cannot be walked: a
// `%Job` boxes whichever type implements `Job`, and its type does not
// say which. Its trait answers for it instead. `% Job [T] : Send { … }`
// holds every type implementing `Job` to Send where its impl is, and
// then a `%Job` may move; `: Send Sync` lets one be shared as well.
// Without the promise a trait object stays on the thread that made it.
//
// ── When you DO write one ──────────────────────────────────────────
//
// The derivation is structural, so it is wrong in exactly two ways,
// and there is one marker for each.
//
// **The compiler is too pessimistic.** A type whose innards look unsafe
// but which is safe by construction — a lock, a channel, an atomic
// handle. `Mutex` is literally `{ Cell c }`, and a bare `Cell` is !Sync,
// yet a Mutex is the thing that MAKES its contents shareable. Assert it:
//
//     % Sync Mutex { }        // and `% Send Mutex { }`
//
// An explicit impl STOPS the walk at that type: nothing inside is
// examined, because you have taken responsibility for it. That is why a
// program's own positive marker is `unsafe % Send T { }` /
// `unsafe % Sync T { }`: without the prefix it is an error.
//
// **The compiler is too optimistic.** A type that derives clean but
// wraps thread-hostile state the compiler cannot see — an FFI handle.
// A `sqlite3*` is an `s` and a `FILE*` is an `s`, and `s` is Send;
// neither connection is. Say so:
//
//     : Db { s handle }
//     % NotSend Db { }        // never crosses a thread boundary
//
// `NotSend` / `NotSync` propagate exactly like the built-in leaves: a
// struct holding a `Db`, a `( Vec Db )`, a closure capturing one are
// all rejected at the boundary, naming `Db`.
//
// A negative marker always wins over a positive one on the same type —
// if both are written, the type is rejected. That is the safe direction
// for a contradiction to resolve in. A negative marker only adds checks,
// so it is ordinary safe code: no `unsafe`.
//
// ── As a bound ─────────────────────────────────────────────────────
//
// Because they are ordinary traits, they work as ordinary bounds, and
// the bound is satisfied by the DERIVATION — not by hunting for an
// impl. `[T: Send]` accepts `i`, `s`, `( Vec i )` and rejects
// `( Rc i )`:
//
//     @ run_on_worker [T: Send] ( Channel T ) ch T v → b {
//         ^ ( chan_send [T] ch v )
//     }
//
// ── What this does NOT prove ───────────────────────────────────────
//
// Send/Sync answer "may this value cross?", never "is this program
// race-free". Two threads mutating one `( Vec i )` they both hold a
// handle to is a race that no marker forbids — `Vec` is Send and Sync,
// and correctly so, because sharing it read-only is fine. That race is
// caught separately, at the mutation, by the shared-mutation check
// (`docs/MEMORY.md` §6.5). The two checks are complementary and
// neither subsumes the other.
//
// Like every other check in this compiler the derivation can only MISS
// (an unmarked FFI handle, a type graph deeper than the walk's cap),
// never invent: it is a sound lint, not a proof (`docs/MEMORY.md` §6.3).

// A value of `T` may be moved to another thread.
pub % Send [T] {}

// Two threads may reach one value of `T` at the same time.
pub % Sync [T] {}

// `T` must never cross a thread boundary, whatever its fields suggest.
pub % NotSend [T] {}

// Two threads must never reach one `T` at the same time.
pub % NotSync [T] {}

// Frozen — what a value of `T` lends is read-only. A function that takes
// a `T` and hands back something it holds (an accessor) lends a view of
// it, and no call may change that view or anything reached through it:
// not a container mutator, not `slice_put`, not a helper of the program's
// that does, at any depth (docs/MEMORY.md §6.5). An `Arc` is frozen by
// construction — its payload is read by every thread holding a clone
// without a lock. Mark a handle of your own the same way when what it
// lends is shared with other threads reading at the same time: a read
// guard of a reader-writer lock (stdlib/std/rwlock.nu) is the shape —
//
//     % Frozen RGuard { }
//
// Unlike Send and Sync it only adds checks: the compiler follows every
// view the handle lends and rejects a change to one where it is made, so
// a safe module may mark a type of its own (no `unsafe`). What is trusted
// is the other direction — a handle of the standard library's that lends
// shared data and is NOT marked would lend it mutable.
pub % Frozen [T] {}

// Resource — a type whose drop is observable outside the program: it
// closes a file descriptor, a socket, a database connection, reaps a child
// process. Not a thread-safety question: the Rc cycle collector asks it. A
// cycle of Rc handles that can hold a Resource is released the moment it
// becomes unreachable (docs/MEMORY.md §7.7), so a file in a graph closes
// where the last handle into the graph went — not whenever the collector
// next runs, which a program opening files in a loop would notice as
// running out of descriptors. Everything that owns a Resource (a struct
// field, an element, a payload, an Rc it holds) is one by structure; only
// the OS handles themselves carry the mark:
//
//     % Resource File { }
//
// Mark a type of your own the same way when its drop does something the
// outside world sees (an FFI close, a flush to a socket). Freeing memory,
// releasing a lock or a count is not that: a Mutex is not a Resource.
pub % Resource [T] {}
