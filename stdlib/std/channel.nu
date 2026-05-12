// stdlib/std/channel.nu — Channel: thread-safe FIFO queue of i64 slots
//
// MVP unbounded FIFO. Mutex protects the queue + closed flag; cond
// signals waiting receivers when a value lands. Built entirely on top
// of `stdlib/std/thread.nu` + `stdlib/core/vec.nu` — no runtime/compiler
// additions required.
//
// Element type is i64 (NURL `i`) so that integer values flow directly
// and pointer / handle values can be cast across with `# i ptr`. A
// fully generic `Channel[T]` would need nested-generic instantiation
// (Channel[T] embedding Vec[T] inside an internal struct) which the
// text-level `scan_generic_structs` pre-pass doesn't yet propagate
// across; the i64-channel pattern matches what `process.nu`'s
// reader-thread bridge does in C and is the lowest-overhead shape.
//
// API:
//
//   ( chan_new )                 → Channel
//   ( chan_send      Channel ch i v )  → b   F if channel is closed
//   ( chan_recv      Channel ch )      → ? i  None when closed AND empty
//   ( chan_try_recv  Channel ch )      → ? i  non-blocking — None if empty
//   ( chan_close     Channel ch )      → v   wakes every blocked recv
//   ( chan_len       Channel ch )      → i   queue depth (snapshot)
//   ( chan_is_closed Channel ch )      → b
//   ( chan_free      Channel ch )      → v   release queue + mutex + cond
//
// Memory model:
//
//   * Channel is an opaque single-pointer handle (`{ s ctl }`); copying
//     the handle by value shares the same heap-allocated ChannelImpl,
//     which is exactly what producer/consumer threads need. All threads
//     observe each other's pushes through the mutex.
//   * Caller MUST call `chan_close` before `chan_free` to wake every
//     blocked receiver — otherwise a `chan_recv` waiter would deadlock
//     on a freed cond+mutex pair.
//   * Closed channel: send returns F (caller's value is dropped — the
//     i64 slot is not freed since we don't know what it points at);
//     recv drains remaining items, then returns None.
//
// Producer / consumer pattern:
//
//   : Channel ch ( chan_new )
//   // worker thread:
//   ~ ! done {
//     : ? i opt ( chan_recv ch )
//     ?? opt {
//       T v → { handle v }
//       F   → { = done T }
//     }
//   }
//   // main thread:
//   ( chan_send ch 42 )
//   ( chan_close ch )
//   ( thread_join worker )
//   ( chan_free ch )

$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

// ── Internal heap-allocated state ──────────────────────────────────

: ChannelImpl {
  Mutex     m
  Cond      c
  ( Vec i ) q          // FIFO: push back, pop front
  i         closed     // 0 = open, 1 = closed
}

: Channel { s ctl }

// ── Constructor ────────────────────────────────────────────────────

@ chan_new → Channel {
  : *ChannelImpl impl # *ChannelImpl ( nurl_alloc Z ChannelImpl )
  =. impl m ( mutex_new )
  =. impl c ( cond_new )
  =. impl q ( vec_new [i] )
  =. impl closed 0
  ^ @ Channel { #s impl }
}

// ── Send / receive ─────────────────────────────────────────────────

// Push v onto the back of the queue. Returns F if the channel is
// already closed (caller's v is silently dropped — the i64 slot has no
// inherent ownership; if it carried a heap pointer the caller must
// release it themselves on the F branch).
@ chan_send Channel ch i v → b {
  : *ChannelImpl impl #*ChannelImpl . ch ctl
  ( mutex_lock . impl m )
  ? != 0 . impl closed {
    ( mutex_unlock . impl m )
    ^ F
  } {}
  ( vec_push [i] . impl q v )
  ( cond_signal . impl c )
  ( mutex_unlock . impl m )
  ^ T
}

// Pop the front of the queue, blocking until either an item arrives
// or the channel is closed (and drained). Returns None only when the
// channel is closed AND empty.
@ chan_recv Channel ch → ? i {
  : *ChannelImpl impl #*ChannelImpl . ch ctl
  ( mutex_lock . impl m )
  ~ & == ( vec_len [i] . impl q ) 0 == . impl closed 0 {
    ( cond_wait . impl c . impl m )
  }
  ? == ( vec_len [i] . impl q ) 0 {
    // Closed AND empty.
    ( mutex_unlock . impl m )
    ^ @ ? i { F 0 }
  } {}
  // Pop front element. vec_pop pops from the BACK; for FIFO we want
  // the front. vec_remove [i] 0 shifts the rest left — O(n) but the
  // queue depth is typically small. (For high-throughput a ring
  // buffer would be better; defer until profiling motivates it.)
  : ? i opt ( vec_remove [i] . impl q 0 )
  ( mutex_unlock . impl m )
  ^ opt
}

// Non-blocking variant: returns None immediately when the queue is
// empty (regardless of closed state). Useful for poll-style consumers
// that interleave channel reads with other work.
@ chan_try_recv Channel ch → ? i {
  : *ChannelImpl impl #*ChannelImpl . ch ctl
  ( mutex_lock . impl m )
  ? == ( vec_len [i] . impl q ) 0 {
    ( mutex_unlock . impl m )
    ^ @ ? i { F 0 }
  } {}
  : ? i opt ( vec_remove [i] . impl q 0 )
  ( mutex_unlock . impl m )
  ^ opt
}

// ── Close + introspection ──────────────────────────────────────────

@ chan_close Channel ch → v {
  : *ChannelImpl impl #*ChannelImpl . ch ctl
  ( mutex_lock . impl m )
  =. impl closed 1
  ( cond_broadcast . impl c )
  ( mutex_unlock . impl m )
}

@ chan_len Channel ch → i {
  : *ChannelImpl impl #*ChannelImpl . ch ctl
  ( mutex_lock . impl m )
  : i n ( vec_len [i] . impl q )
  ( mutex_unlock . impl m )
  ^ n
}

@ chan_is_closed Channel ch → b {
  : *ChannelImpl impl #*ChannelImpl . ch ctl
  ( mutex_lock . impl m )
  : b cl != 0 . impl closed
  ( mutex_unlock . impl m )
  ^ cl
}

// ── Cleanup ────────────────────────────────────────────────────────

@ chan_free Channel ch → v {
  : *ChannelImpl impl #*ChannelImpl . ch ctl
  ( vec_free [i] . impl q )
  ( cond_free . impl c )
  ( mutex_free . impl m )
  ( nurl_free #s impl )
}
