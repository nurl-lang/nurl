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
}

: Channel [A] { s ctl }

// ── Constructor ────────────────────────────────────────────────────

@ chan_new [A] → ( Channel A ) {
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) ( nurl_alloc Z ( ChannelImpl A ) )
    = . impl m ( mutex_new )
    = . impl c ( cond_new )
    = . impl q ( vec_new [A] )
    = . impl closed 0
    = . impl recv_fibers ( vec_new [i] )
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
            : s mrp . . impl m raw
            : i mraw # i mrp
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
    ( cond_free . impl c )
    ( mutex_free . impl m )
    ( nurl_free # s impl )
}
