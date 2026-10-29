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
// items remain pending. Sending into a closed channel (chan_send
// returns F) drops the value: nothing leaks.
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
//   ( chan_free     [A] ( Channel A ) ch )      → v      early release of this owner (optional)
//   ( Channel_share [A] ( Channel A ) ch )      → ( Channel A )   another owner
//
// Memory model:
//
//   * `Channel[A]` is an opaque single-pointer handle (`{ s ctl }`) on
//     a reference-counted `ChannelImpl[A]`: every copy (a thread's or a
//     fiber's capture, a struct field) is the same channel, which is
//     exactly what producer/consumer threads AND fibers need, and the
//     last owner to go releases it with anything still queued. Nothing
//     to free by hand.
//   * `chan_close` wakes every blocked receiver; a receiver holds its
//     own copy, so the channel outlives it.
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

$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

// ── Fiber FFI bridge — pulled from the standalone `_ffi` module so
//    both `stdlib/std/async.nu` (the wrapper API) and this file can
//    reach the same `nurl_fiber_*` C symbols without producing
//    duplicate `declare`-lines at LLVM link time. nurl_fiber_current
//    returns 0 outside a fiber; park / unpark are stubs on WASI /
//    Windows.

$ `stdlib/std/async_ffi.nu`

$ `stdlib/core/rcbox.nu`
$ `stdlib/core/box.nu`

// ── Internal heap-allocated state ──────────────────────────────────

// What a channel holds, behind the handle's count (a Shared block): its
// last owner drops the lot — the queue with whatever is still in it, the
// waiter lists, the lock — and releases the block.
: ChImpl [A] {
    Mutex m
    Cond c
    ( Vec A ) q  // FIFO: push back, pop front
    i closed  // 0 = open, 1 = closed
    ( Vec i ) recv_fibers  // parked fiber handles awaiting recv (FIFO)
    ( Vec ( Shared SelectWaiter ) ) select_waiters  // one share of each armed `?? {}` select waiter
}

// The counted block as the operations reach it: the owner count the
// Shared block keeps in front of the value, then the value's fields
// (stdlib/core/rcbox.nu's RcBox layout).
: ChannelImpl [A] {
    i owners  // copies of the handle alive (the Shared count)
    Mutex m
    Cond c
    ( Vec A ) q  // FIFO: push back, pop front
    i closed  // 0 = open, 1 = closed
    ( Vec i ) recv_fibers  // parked fiber handles awaiting recv (FIFO)
    ( Vec ( Shared SelectWaiter ) ) select_waiters  // one share of each armed `?? {}` select waiter
}

// A handle every copy of which is the same channel: the producer's and
// the consumer's copies (a thread closure's capture, a struct field)
// share it, and the last one to go releases it and anything still queued.
: Channel [A] { ( Shared ( ChImpl A ) ) ctl }

// A Channel is reached from every thread that holds a copy and changes
// only under its own lock (chan_send / chan_recv): its contents are
// synchronised, so one inside an Arc may be sent to and received from by
// every thread (docs/MEMORY.md §6.5). What may travel through it is still
// asked of the element (`chan_send` needs it Send).
% Sync Channel {}

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
    i owners
    Mutex m
    Cond c
    ( Vec i ) q
    i closed
    ( Vec i ) recv_fibers
    ( Vec ( Shared SelectWaiter ) ) select_waiters
}

// The block behind a SelWaiter (the select machinery below): `fired` is
// the condition predicate guarding lost + spurious wakeups, reset to 0 at
// the top of every scan iteration (select_waiter_prepare).
: SelectWaiter {
    Mutex m
    Cond c
    i fired
}

// ── Constructor ────────────────────────────────────────────────────

@ chan_new [A] → ( Channel A ) {
    ^ @ ( Channel A ) { ( shared_new [( ChImpl A )] @ ( ChImpl A ) { ( mutex_new ) ( cond_new ) ( vec_new [A] ) 0 ( vec_new [i] ) ( vec_new [( Shared SelectWaiter )] ) } ) }
}

// ── Send / receive ─────────────────────────────────────────────────

// Push v onto the back of the queue. Returns F if the channel is
// already closed (v is then dropped).
// Wakes one parked receiver — a fiber (via unpark) or a pthread
// (via cond_signal) — depending on which arrived first.
@ chan_send [A] ( Channel A ) ch A v → b {
    // `v` goes to whichever thread receives it: a handle in it whose copies
    // are one state may have no owner on this side (docs/MEMORY.md §6.5).
    ( mem_send_check [A] v `chan_send` )
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . . ch ctl ctl
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
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . . ch ctl ctl
    ( mutex_lock . impl m )
    ~ & == ( vec_len [A] . impl q ) 0 == . impl closed 0 {
        : i fcur ( nurl_fiber_current )
        ? != fcur 0 {
            // On a fiber — push handle, park atomically with mutex
            // release. The worker loop releases . impl m AFTER our
            // swap-out completes, so a concurrent sender sees the
            // queued waiter on a stable PARKED state.
            ( vec_push [i] . impl recv_fibers fcur )
            // The pthread_mutex_t itself — the C side casts it back.
            : *u mptr ( mutex_raw . impl m )
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
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . . ch ctl ctl
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
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . . ch ctl ctl
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
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . . ch ctl ctl
    ( mutex_lock . impl m )
    : i n ( vec_len [A] . impl q )
    ( mutex_unlock . impl m )
    ^ n
}

@ chan_is_closed [A] ( Channel A ) ch → b {
    : *( ChannelImpl A ) impl # *( ChannelImpl A ) . . ch ctl ctl
    ( mutex_lock . impl m )
    : b cl != 0 . impl closed
    ( mutex_unlock . impl m )
    ^ cl
}

// ── Cleanup ────────────────────────────────────────────────────────

@ Channel_share [A] ( Channel A ) ch → ( Channel A ) {
    ^ @ ( Channel A ) { ( shared_clone [( ChImpl A )] . ch ctl ) }
}

// The last owner releases the channel and whatever is still queued in it
// (the Shared field's drop).
@ Channel_drop [A] sink ( Channel A ) ch → v {}

// Let go of `ch` now rather than at the end of its owner's scope.
@ chan_free [A] sink ( Channel A ) ch → v {}

// ── select (`?? {}`) machinery ─────────────────────────────────────
//
// The compiler lowers a `?? { [T] ch → v { … } … }` select into calls to
// the functions below (compiler/nurlc.nu gen_select). Each takes the
// Channel itself and the select's waiter, so nothing raw reaches the
// lowered program: the element type is a type argument, and the only
// element-typed operation is the `chan_try_recv [T]` of the chosen arm.
//
// Protocol (no default arm):
//   : SelWaiter w ( select_waiter_new )
//   loop until an arm is chosen:
//     select_waiter_prepare w                   // fired = 0
//     chan_select_arm [T] ch_i w                // for every case channel
//     // poll, in case order: the first ready arm is chosen and its
//     // value taken with chan_try_recv (None when the channel closed)
//     select_waiter_wait w                      // only if none was ready
//     chan_select_disarm [T] ch_i w             // for every case channel
//   run the chosen arm's body                   // after the disarm
//   (w is dropped when the select's block ends)
//
// With a `_ → { … }` default arm there is no waiter at all: poll once,
// then run the default body.

// A select rendezvous token: one per in-flight blocking select. The
// selecting thread arms it on every channel it waits on, and a sender or
// closer fires it (__select_waiter_fire). Its block is counted (Shared):
// every channel it is armed on holds a share until the disarm, so a
// waiter dropped while still armed — which the lowering never does, but
// a program calling chan_select_arm itself can — stays alive for the
// channel's next fire, and the channel's drop lets the last share go
// (agora #167).
: SelWaiter { ( Shared SelectWaiter ) ctl }

@ select_waiter_new → SelWaiter {
    ^ @ SelWaiter { ( shared_new [SelectWaiter] @ SelectWaiter { ( mutex_new ) ( cond_new ) 0 } ) }
}

// One share fewer; the last owner drops the block (its lock and condvar
// with it).
@ SelWaiter_drop sink SelWaiter h → v {}

// Reset the fired flag before a scan iteration arms its channels. Done
// under the waiter mutex so a fire racing the reset is ordered.
@ select_waiter_prepare SelWaiter h → v {
    : *SelectWaiter w ( shared_ptr [SelectWaiter] . h ctl )
    ( mutex_lock . w m )
    = . w fired 0
    ( mutex_unlock . w m )
}

// Block until some armed channel fires us. Standard condvar predicate
// loop on `fired`, so a fire that arrives between arming and waiting is
// not lost (fired is already 1 → no sleep).
@ select_waiter_wait SelWaiter h → v {
    : *SelectWaiter w ( shared_ptr [SelectWaiter] . h ctl )
    ( mutex_lock . w m )
    ~ == . w fired 0 {
        ( cond_wait . w c . w m )
    }
    ( mutex_unlock . w m )
}

// Register / unregister the selecting thread's waiter on a channel.
@ chan_select_arm [A] ( Channel A ) ch SelWaiter h → v { ( __chan_raw_arm ( shared_addr [( ChImpl A )] . ch ctl ) . h ctl ) }

@ chan_select_disarm [A] ( Channel A ) ch SelWaiter h → v { ( __chan_raw_disarm ( shared_addr [( ChImpl A )] . ch ctl ) ( shared_addr [SelectWaiter] . h ctl ) ) }

// Readiness: 0 not ready, 1 a value is queued, 2 closed and drained.
@ chan_select_poll [A] ( Channel A ) ch → i { ^ ( __chan_raw_poll ( shared_addr [( ChImpl A )] . ch ctl ) ) }

// Called by a sender / closer (while holding the channel mutex) for
// each registered selecting thread.
@ __select_waiter_fire ( Shared SelectWaiter ) h → v {
    : *SelectWaiter w ( shared_ptr [SelectWaiter] h )
    ( mutex_lock . w m )
    = . w fired 1
    ( cond_signal . w c )
    ( mutex_unlock . w m )
}

@ __chan_fire_select_waiters ( Vec ( Shared SelectWaiter ) ) ws → v {
    : i n ( vec_len [( Shared SelectWaiter )] ws )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [( Shared SelectWaiter )] ws k ) {
            T wh → { ( __select_waiter_fire wh ) }
            F → {}
        }
        = k + k 1
    }
}

// Register / unregister a selecting thread's waiter on a channel.
// The channel takes a share of the waiter: it stays alive while armed.
@ __chan_raw_arm i ctl ( Shared SelectWaiter ) wh → v {
    : *ChannelRaw impl # *ChannelRaw ctl
    ( mutex_lock . impl m )
    ( vec_push [( Shared SelectWaiter )] . impl select_waiters ( shared_clone [SelectWaiter] wh ) )
    ( mutex_unlock . impl m )
}

@ __chan_raw_disarm i ctl i wp → v {
    : *ChannelRaw impl # *ChannelRaw ctl
    ( mutex_lock . impl m )
    : i n ( vec_len [( Shared SelectWaiter )] . impl select_waiters )
    : ~ i k 0
    : ~ b done2 F
    ~ & < k n ! done2 {
        : i val ?? ( vec_get [( Shared SelectWaiter )] . impl select_waiters k ) { T wh → ( shared_addr [SelectWaiter] wh ) F → 0 }
        ? == val wp {
            // the channel's share goes with the removed element
            : ?( Shared SelectWaiter ) _rm ( vec_remove [( Shared SelectWaiter )] . impl select_waiters k )
            = done2 T
        } { = k + k 1 }
    }
    ( mutex_unlock . impl m )
}

// Type-erased readiness probe used by the compiler-emitted select scan:
//   0  not ready (queue empty AND channel open)
//   1  a value is queued        → the chosen arm's chan_try_recv gets it
//   2  closed and drained       → chan_recv would yield None (closed signal)
// Reads only the queue length + closed flag, both element-type-agnostic.
@ __chan_raw_poll i ctl → i {
    : *ChannelRaw impl # *ChannelRaw ctl
    ( mutex_lock . impl m )
    : i ql ( vec_len [i] . impl q )
    : ~ i r 0
    ? > ql 0 { = r 1 } { ? != 0 . impl closed { = r 2 } {} }
    ( mutex_unlock . impl m )
    ^ r
}
