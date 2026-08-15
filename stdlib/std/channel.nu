// stdlib/std/channel.nu — Channel[A]: thread-safe FIFO queue, generic
// over the element type.
//
// Unbounded FIFO. Mutex protects the queue + closed flag. Receivers
// that find the queue empty wait via one of two paths:
//   * OS-thread callers (legacy `thread_spawn` consumers) use
//     `cond_wait` on the per-channel condvar — same as v1.
//   * Fiber callers (`async.nu` spawn/spawn_joinable) park on the
//     channel's per-fiber waiter list and resume when the next
//     sender arrives. The pthread is NOT blocked — the worker
//     continues running other fibers.
//
// Selection is by `nurl_fiber_current() != 0`. A caller that holds
// the mutex while calling `nurl_fiber_park_with_mutex` is guaranteed
// to be visible to a concurrent sender (the worker loop releases the
// mutex only AFTER swap-out is complete), so the lost-wakeup race
// of "unlock then park" is closed by the runtime.
//
// Element type `A` is whatever scalar, pointer, or single-handle struct
// you instantiate the channel with. Multi-field structs work too — Vec
// stores them in-place via vec_push/vec_remove. For ownership-sensitive
// payloads, the sender hands ownership over on `chan_send`; if the
// channel is later closed and `chan_recv` returns None after drain, no
// items remain pending. The send-into-closed branch (chan_send returns
// F) is the one place a caller-owned value isn't taken — the caller
// must free it themselves on F.
//
// A channel is a THREAD BOUNDARY, so `A` must be `Send`
// (stdlib/core/marker.nu): whatever `chan_send` accepts, some other
// thread or fiber receives. `( Channel ( Rc i ) )` is rejected at the
// send, with the same reason and the same wording a `thread_spawn`
// closure capturing that Rc would get — one situation, one verdict,
// however it is spelled. Send the data rather than the handle when the
// payload is not Send: read the value out on this side and send that.
//
// API (unchanged from v1):
//
//   ( chan_new      [A] )                  → ( Channel A )
//   ( chan_send     [A] ( Channel A ) ch A v )  → b      F if closed
//   ( chan_recv     [A] ( Channel A ) ch )      → ?A     None when closed AND empty
//   ( chan_try_recv [A] ( Channel A ) ch )      → ?A     non-blocking
//   ( chan_close    [A] ( Channel A ) ch )      → v      wakes blocked recvs (threads + fibers)
//   ( chan_len      [A] ( Channel A ) ch )      → i      queue depth (snapshot)
//   ( chan_is_closed [A] ( Channel A ) ch )     → b
//   ( chan_free     [A] ( Channel A ) ch )      → v      releases queue + mutex + cond + waiter list
//
// Memory model:
//
//   * `Channel[A]` is an opaque single-pointer handle (`{ s ctl }`);
//     copying the handle by value shares the same heap-allocated
//     `ChannelImpl[A]`, which is exactly what producer/consumer threads
//     AND fibers need.
//   * Caller MUST call `chan_close` before `chan_free` to wake every
//     blocked receiver — otherwise a `chan_recv` waiter would deadlock
//     on a freed cond+mutex pair OR a parked fiber would never resume.
//   * Closed channel: send returns F (caller's value is dropped — the
//     slot is not freed since we don't know what it points at); recv
//     drains remaining items, then returns None.
//
// Producer / consumer pattern (works identically on threads or fibers):
//
//   : ( Channel i ) ch ( chan_new [i] )
//   // worker:
//   ~ ! done {
//     : ?i opt ( chan_recv [i] ch )
//     ?? opt {
//       T v → { handle v }
//       F   → { = done T }
//     }
//   }
//   // main:
//   ( chan_send [i] ch 42 )
//   ( chan_close [i] ch )
//   ( chan_free [i] ch )

$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

// ── Fiber FFI bridge — pulled from the standalone `_ffi` module so
//    both `stdlib/std/async.nu` (the wrapper API) and this file can
//    reach the same `nurl_fiber_*` C symbols without producing
//    duplicate `declare`-lines at LLVM link time. nurl_fiber_current
//    returns 0 outside a fiber; park / unpark are stubs on WASI /
//    Windows.

$ `stdlib/std/async_ffi.nu`

// ── Internal heap-allocated state ──────────────────────────────────

: ChannelImpl [A] {
    Mutex m
    Cond c
    ( Vec A ) q  // FIFO: push back, pop front
    i closed  // 0 = open, 1 = closed
    ( Vec i ) recv_fibers  // parked fiber handles awaiting recv (FIFO)
    ( Vec i ) select_waiters  // raw SelectWaiter* of threads in a `?? {}` select
}

: Channel [A] { s ctl }

// Type-erased view of ChannelImpl[A]. Every field of ChannelImpl[A] is
// exactly one machine word — Mutex / Cond / Vec are single-pointer
// handles, `closed` is an i64 — so the struct layout is INDEPENDENT of
// the element type A. The select machinery is driven by the compiler
// with the element type erased to a raw `ctl` pointer; it reads the
// queue depth, the closed flag, and the waiter list through this view
// without knowing A. `q` / `recv_fibers` are declared `( Vec i )` here
// purely as layout placeholders — select never touches element bytes,
// only the queue's length word (vec_len reads it type-agnostically from
// the control block).
//
// INVARIANT: ChannelRaw's field order + count MUST mirror
// ChannelImpl[A] exactly. The select_basic test catches drift.
: ChannelRaw {
    Mutex m
    Cond c
    ( Vec i ) q
    i closed
    ( Vec i ) recv_fibers
    ( Vec i ) select_waiters
}

// A select rendezvous token. One per in-flight `?? {}` select; the
// selecting thread registers its address on every channel it waits on
// (chan_raw_arm), then blocks on `c` until any of those channels fires
// it (a sender / closer calls __select_waiter_fire). `fired` is the
// condition predicate guarding lost + spurious wakeups; reset to 0 at
// the top of every scan iteration (select_waiter_prepare).
: SelectWaiter {
    Mutex m
    Cond c
    i fired
}

// ── Constructor ────────────────────────────────────────────────────

@ chan_new [A] → ( Channel A ) {
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) ( nurl_alloc Z ( ChannelImpl A ) )
    = . impl m ( mutex_new )
    = . impl c ( cond_new )
    = . impl q ( vec_new [A] )
    = . impl closed 0
    = . impl recv_fibers ( vec_new [i] )
    = . impl select_waiters ( vec_new [i] )
    ^ @ ( Channel A ) { # s impl }
}

// ── Send / receive ─────────────────────────────────────────────────

// Push v onto the back of the queue. Returns F if the channel is
// already closed (caller's v is silently dropped; if it carried a heap
// pointer the caller must release it themselves on the F branch).
// Wakes one parked receiver — a fiber (via unpark) or a pthread
// (via cond_signal) — depending on which arrived first.
@ chan_send [A] ( Channel A ) ch A v → b {
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . ch ctl
    ( mutex_lock . impl m )
    ? != 0 . impl closed {
        ( mutex_unlock . impl m )
        ^ F
    } {}
    ( vec_push [A] . impl q v )
    // Wake any selecting thread parked in a `?? {}` over this channel.
    // Done under the mutex so a concurrent selector that has registered
    // its waiter (also under the mutex) is guaranteed visible. Lock
    // order is always impl.m → waiter.m, never the reverse.
    ( __chan_fire_select_waiters . impl select_waiters )
    // Wake a fiber waiter first if any — fiber wakes don't block
    // the OS thread, so they're cheaper than a cond_signal that
    // would force a pthread context switch. Then signal a pthread
    // waiter in case both kinds are queued.
    ? > ( vec_len [i] . impl recv_fibers ) 0 {
        : ?i opt ( vec_remove [i] . impl recv_fibers 0 )
        ?? opt {
            T fh → { ( nurl_fiber_unpark fh ) }
            F → {}
        }
    } {}
    ( cond_signal . impl c )
    ( mutex_unlock . impl m )
    ^ T
}

// Pop the front of the queue, blocking until either an item arrives
// or the channel is closed (and drained). Returns None only when the
// channel is closed AND empty.
//
// From a fiber: parks the fiber on the channel's waiter list
// (worker thread keeps running other fibers). From an OS thread:
// `cond_wait`s the calling pthread as before.
@ chan_recv [A] ( Channel A ) ch → ?A {
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . ch ctl
    ( mutex_lock . impl m )
    ~ & == ( vec_len [A] . impl q ) 0 == . impl closed 0 {
        : i fcur ( nurl_fiber_current )
        ? != fcur 0 {
            // On a fiber — push handle, park atomically with mutex
            // release. The worker loop releases . impl m AFTER our
            // swap-out completes, so a concurrent sender sees the
            // queued waiter on a stable PARKED state.
            ( vec_push [i] . impl recv_fibers fcur )
            // Mutex.c is a Cell over pthread_mutex_t (PURIFY Phase 6
            // batch 1). cell_ptr returns *u directly into the mutex
            // bytes — the C side casts back to pthread_mutex_t*.
            : *u mptr ( cell_ptr . . impl m c )
            : i mraw # i mptr
            ( nurl_fiber_park_with_mutex mraw )
            // Re-acquire the mutex on resume and loop the predicate.
            ( mutex_lock . impl m )
        } {
            // Plain OS-thread caller — cond_wait atomically releases
            // and reacquires the mutex.
            ( cond_wait . impl c . impl m )
        }
    }
    ? == ( vec_len [A] . impl q ) 0 {
        // Closed AND empty.
        ( mutex_unlock . impl m )
        ^ @ ?A { F # A 0 }
    } {}
    : ?A opt ( vec_remove [A] . impl q 0 )
    ( mutex_unlock . impl m )
    ^ opt
}

// Non-blocking variant: returns None immediately when the queue is
// empty (regardless of closed state). Useful for poll-style consumers
// that interleave channel reads with other work.
@ chan_try_recv [A] ( Channel A ) ch → ?A {
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . ch ctl
    ( mutex_lock . impl m )
    ? == ( vec_len [A] . impl q ) 0 {
        ( mutex_unlock . impl m )
        ^ @ ?A { F # A 0 }
    } {}
    : ?A opt ( vec_remove [A] . impl q 0 )
    ( mutex_unlock . impl m )
    ^ opt
}

// ── Close + introspection ──────────────────────────────────────────

@ chan_close [A] ( Channel A ) ch → v {
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . ch ctl
    ( mutex_lock . impl m )
    = . impl closed 1
    // A closed channel is permanently "ready" for select (recv returns
    // None immediately), so wake every selecting thread too.
    ( __chan_fire_select_waiters . impl select_waiters )
    // Wake every parked fiber receiver — they re-check the predicate,
    // see closed, and return None.
    ~ > ( vec_len [i] . impl recv_fibers ) 0 {
        : ?i opt ( vec_remove [i] . impl recv_fibers 0 )
        ?? opt {
            T fh → { ( nurl_fiber_unpark fh ) }
            F → {}
        }
    }
    ( cond_broadcast . impl c )
    ( mutex_unlock . impl m )
}

@ chan_len [A] ( Channel A ) ch → i {
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . ch ctl
    ( mutex_lock . impl m )
    : i n ( vec_len [A] . impl q )
    ( mutex_unlock . impl m )
    ^ n
}

@ chan_is_closed [A] ( Channel A ) ch → b {
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . ch ctl
    ( mutex_lock . impl m )
    : b cl != 0 . impl closed
    ( mutex_unlock . impl m )
    ^ cl
}

// ── Cleanup ────────────────────────────────────────────────────────

@ chan_free [A] ( Channel A ) ch → v {
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . ch ctl
    ( vec_free [A] . impl q )
    ( vec_free [i] . impl recv_fibers )
    ( vec_free [i] . impl select_waiters )
    ( cond_free . impl c )
    ( mutex_free . impl m )
    ( nurl_free # s impl )
}

// ── select (`?? {}`) machinery ─────────────────────────────────────
//
// The compiler lowers a `?? { [T] ch → v { … } … }` select into calls
// to the helpers below. ALL of them are non-generic and take a raw
// `ctl` pointer (the Channel handle's single field, as an i64) so the
// element type drops out — the only type-specific operation is the
// `chan_try_recv [T]` the compiler emits for the chosen arm.
//
// Protocol (no default arm):
//   loop:
//     select_waiter_prepare w          // fired = 0
//     chan_raw_arm ctl_i w             // for every case channel
//     // poll, in case order:
//     : ?T bi ( chan_try_recv [T] ch_i )    // atomic pop-if-present
//     ?? bi { T v → disarm all; <body>; done
//             F   → ? chan_raw_closed ctl_i { disarm all; <body w/ None>; done } {} }
//     select_waiter_wait w             // block until fired
//     chan_raw_disarm ctl_i w          // for every case channel
//     goto loop
//   done: select_waiter_free w
//
// With a `_ → { … }` default arm there is no waiter at all: poll once,
// then run the default body.

@ select_waiter_new → i {
    : *SelectWaiter w # *SelectWaiter ( nurl_alloc Z SelectWaiter )
    = . w m ( mutex_new )
    = . w c ( cond_new )
    = . w fired 0
    ^ # i w
}

@ select_waiter_free i wp → v {
    : *SelectWaiter w # *SelectWaiter wp
    ( cond_free . w c )
    ( mutex_free . w m )
    ( nurl_free # s w )
}

// Reset the fired flag before a scan iteration arms its channels. Done
// under the waiter mutex so a fire racing the reset is ordered.
@ select_waiter_prepare i wp → v {
    : *SelectWaiter w # *SelectWaiter wp
    ( mutex_lock . w m )
    = . w fired 0
    ( mutex_unlock . w m )
}

// Block until some armed channel fires us. Standard condvar predicate
// loop on `fired`, so a fire that arrives between arming and waiting is
// not lost (fired is already 1 → no sleep).
@ select_waiter_wait i wp → v {
    : *SelectWaiter w # *SelectWaiter wp
    ( mutex_lock . w m )
    ~ == . w fired 0 {
        ( cond_wait . w c . w m )
    }
    ( mutex_unlock . w m )
}

// Called by a sender / closer (while holding the channel mutex) for
// each registered selecting thread.
@ __select_waiter_fire i wp → v {
    : *SelectWaiter w # *SelectWaiter wp
    ( mutex_lock . w m )
    = . w fired 1
    ( cond_signal . w c )
    ( mutex_unlock . w m )
}

@ __chan_fire_select_waiters ( Vec i ) ws → v {
    : i n ( vec_len [i] ws )
    : ~ i k 0
    ~ < k n {
        : ?i ov ( vec_get [i] ws k )
        ?? ov {
            T wp → { ( __select_waiter_fire wp ) }
            F → {}
        }
        = k + k 1
    }
}

// Register / unregister a selecting thread's waiter on a channel.
@ chan_raw_arm i ctl i wp → v {
    : *ChannelRaw impl # *ChannelRaw ctl
    ( mutex_lock . impl m )
    ( vec_push [i] . impl select_waiters wp )
    ( mutex_unlock . impl m )
}

@ chan_raw_disarm i ctl i wp → v {
    : *ChannelRaw impl # *ChannelRaw ctl
    ( mutex_lock . impl m )
    : i n ( vec_len [i] . impl select_waiters )
    : ~ i k 0
    : ~ b done2 F
    ~ & < k n ! done2 {
        : ?i ov ( vec_get [i] . impl select_waiters k )
        ?? ov {
            T val → {
                ? == val wp {
                    : ?i rm ( vec_remove [i] . impl select_waiters k )
                    = done2 T
                } { = k + k 1 }
            }
            F → { = k + k 1 }
        }
    }
    ( mutex_unlock . impl m )
}

// True once the channel is closed (drained or not) — a closed channel
// makes its select case permanently ready (recv yields None).
@ chan_raw_closed i ctl → b {
    : *ChannelRaw impl # *ChannelRaw ctl
    ( mutex_lock . impl m )
    : b cl != 0 . impl closed
    ( mutex_unlock . impl m )
    ^ cl
}

// Type-erased readiness probe used by the compiler-emitted select scan:
//   0  not ready (queue empty AND channel open)
//   1  a value is queued        → the chosen arm's chan_try_recv gets it
//   2  closed and drained       → chan_recv would yield None (closed signal)
// Reads only the queue length + closed flag, both element-type-agnostic.
@ chan_raw_poll i ctl → i {
    : *ChannelRaw impl # *ChannelRaw ctl
    ( mutex_lock . impl m )
    : i ql ( vec_len [i] . impl q )
    : ~ i r 0
    ? > ql 0 { = r 1 } { ? != 0 . impl closed { = r 2 } {} }
    ( mutex_unlock . impl m )
    ^ r
}
