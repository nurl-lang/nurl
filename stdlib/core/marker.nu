// stdlib/core/marker.nu — Send / Sync, the thread-safety marker traits.
//
// Two questions a thread boundary asks about a type, and nothing else:
//
//   Send — may a value of this type MOVE to another thread?
//   Sync — may two threads reach ONE value of this type at once?
//
// Both are marker traits: no methods, no runtime representation, no
// dispatch. A `% Send T { }` block is not code — it is an assertion,
// NURL's spelling of Rust's `unsafe impl Send for T`.
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
// examined, because you have taken responsibility for it.
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
// for a contradiction to resolve in.
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
pub %Send [T] {}

// Two threads may reach one value of `T` at the same time.
pub %Sync [T] {}

// `T` must never cross a thread boundary, whatever its fields suggest.
pub %NotSend [T] {}

// Two threads must never reach one `T` at the same time.
pub %NotSync [T] {}
