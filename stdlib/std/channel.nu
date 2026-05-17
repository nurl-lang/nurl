// stdlib/std/channel.nu — Channel[A]: thread-safe FIFO queue, generic
// over the element type.
//
// Unbounded FIFO. Mutex protects the queue + closed flag; cond signals
// waiting receivers when a value lands. Built on `stdlib/std/thread.nu`
// + `stdlib/core/vec.nu` — no runtime/compiler additions required.
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
// API:
//
//   ( chan_new      [A] )                  → ( Channel A )
//   ( chan_send     [A] ( Channel A ) ch A v )  → b      F if closed
//   ( chan_recv     [A] ( Channel A ) ch )      → ?A     None when closed AND empty
//   ( chan_try_recv [A] ( Channel A ) ch )      → ?A     non-blocking
//   ( chan_close    [A] ( Channel A ) ch )      → v      wakes blocked recvs
//   ( chan_len      [A] ( Channel A ) ch )      → i      queue depth (snapshot)
//   ( chan_is_closed [A] ( Channel A ) ch )     → b
//   ( chan_free     [A] ( Channel A ) ch )      → v      releases queue + mutex + cond
//
// Memory model:
//
//   * `Channel[A]` is an opaque single-pointer handle (`{ s ctl }`);
//     copying the handle by value shares the same heap-allocated
//     `ChannelImpl[A]`, which is exactly what producer/consumer threads
//     need. All threads observe each other's pushes through the mutex.
//   * Caller MUST call `chan_close` before `chan_free` to wake every
//     blocked receiver — otherwise a `chan_recv` waiter would deadlock
//     on a freed cond+mutex pair.
//   * Closed channel: send returns F (caller's value is dropped — the
//     slot is not freed since we don't know what it points at); recv
//     drains remaining items, then returns None.
//
// Producer / consumer pattern:
//
//   : ( Channel i ) ch ( chan_new [i] )
//   // worker thread:
//   ~ ! done {
//     : ?i opt ( chan_recv [i] ch )
//     ?? opt {
//       T v → { handle v }
//       F   → { = done T }
//     }
//   }
//   // main thread:
//   ( chan_send [i] ch 42 )
//   ( chan_close [i] ch )
//   ( thread_join worker )
//   ( chan_free [i] ch )

$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

// ── Internal heap-allocated state ──────────────────────────────────

: ChannelImpl [A] {
    Mutex m
    Cond c
    ( Vec A ) q  // FIFO: push back, pop front
    i closed  // 0 = open, 1 = closed
}

: Channel [A] { s ctl }

// ── Constructor ────────────────────────────────────────────────────

@ chan_new [A] → ( Channel A ) {
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) ( nurl_alloc Z ( ChannelImpl A ) )
    = . impl m ( mutex_new )
    = . impl c ( cond_new )
    = . impl q ( vec_new [A] )
    = . impl closed 0
    ^ @ ( Channel A ) { # s impl }
}

// ── Send / receive ─────────────────────────────────────────────────

// Push v onto the back of the queue. Returns F if the channel is
// already closed (caller's v is silently dropped; if it carried a heap
// pointer the caller must release it themselves on the F branch).
@ chan_send [A] ( Channel A ) ch A v → b {
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . ch ctl
    ( mutex_lock . impl m )
    ? != 0 . impl closed {
        ( mutex_unlock . impl m )
        ^ F
    } {}
    ( vec_push [A] . impl q v )
    ( cond_signal . impl c )
    ( mutex_unlock . impl m )
    ^ T
}

// Pop the front of the queue, blocking until either an item arrives
// or the channel is closed (and drained). Returns None only when the
// channel is closed AND empty.
@ chan_recv [A] ( Channel A ) ch → ?A {
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . ch ctl
    ( mutex_lock . impl m )
    ~ & == ( vec_len [A] . impl q ) 0 == . impl closed 0 {
        ( cond_wait . impl c . impl m )
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
    ( cond_free . impl c )
    ( mutex_free . impl m )
    ( nurl_free # s impl )
}
