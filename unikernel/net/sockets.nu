// unikernel/net/sockets.nu — the socket ABI, implemented in NURL.
//
// Phase A4.2. `nurl_tcp_listen`, `nurl_tcp_read`, `nurl_reactor_wait_read`
// and the rest are C functions in `stdlib/runtime_ffi.c`, which is the
// one file a freestanding target cannot have: it is sockets, poll,
// pipes, fork and pthreads. `unikernel/runtime_bare.c` supplies the
// threads and the fibers and deliberately leaves the socket surface
// ABSENT rather than stubbed — a program that needs a socket fails to
// LINK instead of quietly computing nothing.
//
// This file is what it links against instead: the same symbols, in
// NURL, over the sans-IO stack in `stdlib/net/`. Nothing above it
// changes. `stdlib/std/net.nu` still declares them as C imports and
// still calls them the same way; nurlc suppresses the declaration when
// a definition exists, which is the whole point of that rule.
//
// WHY IT LIVES HERE AND NOT IN stdlib/net/
//
// `stdlib/net/` is sans-IO and that guarantee is checked by grep: no
// FFI, no clock, no device. This file is the opposite of all three —
// it reads the clock, drives the machine, and decides what "blocking"
// means. Keeping the two apart is what lets the protocol layers be
// tested under a scripted clock and this one be tested by running the
// ordinary corpus with no libc underneath it.
//
// ── what "blocking" means with no operating system ───────────────
//
// A blocking read has to wait for something else to run. There is no
// kernel to hand the CPU to, so the wait loop IS the scheduler's
// customer: it drives the stack (deliver queued frames, expire
// timers), and when the stack has nothing to do it yields — to another
// coroutine if one is runnable, to a real sleep if a timer is armed.
//
// When neither is true, nothing can ever make this fd ready, and that
// is DECIDABLE here in a way it is not on a hosted runtime: no frames
// queued, no coroutine runnable, no timer armed, and no device that
// could deliver unprompted. The wait reports failure instead of
// spinning forever. `g_has_device` is what makes that judgement
// honest — a machine with a real NIC can receive at any moment, so
// this build (loopback only) sets it to 0 and the virtio-net build
// will set it to 1.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/time.nu`
$ `stdlib/net/pktbuf.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/eth.nu`
$ `stdlib/net/ipv4.nu`
$ `stdlib/net/arp.nu`
$ `stdlib/net/icmp.nu`
$ `stdlib/net/udp4.nu`
$ `stdlib/net/stack.nu`
$ `stdlib/net/tcpseg.nu`
$ `stdlib/net/tcp.nu`
$ `stdlib/net/tcpstack.nu`
$ `stdlib/net/socket.nu`

// One coroutine step, and whether anything ran. Main context only —
// `nurl_bare_poll` answers 0 on a fiber rather than switching through
// the loop context it would have to return through.
& `c` @ nurl_bare_poll → i

// 1 when another coroutine is ready to run.
& `c` @ nurl_bare_runnable → i

// 1 when the MAIN context is parked inside the scheduler rather than
// running application code.
& `c` @ nurl_bare_blocked → i

// Milliseconds until the earliest armed timer, or -1 if none is armed.
& `c` @ nurl_bare_timer_ms → i

& `c` @ nurl_fiber_current → i

& `c` @ nurl_fiber_yield → v

& `c` @ nurl_fiber_sleep_ms i ms → i

// Park the current coroutine until it is unparked or `ms` pass
// (ms < 0 = no deadline). 1 = woken, 0 = the deadline passed, -1 = not
// on a coroutine. This is what a socket wait uses INSTEAD of polling.
& `c` @ nurl_bare_park_ms i ms → i

& `c` @ nurl_fiber_unpark i handle → v

: Shim {
    * NetStack net
    * TcpStack ts
    * SockTab st
    ( Vec i ) peer  // cached "ip:port" per fd slot — see nurl_tcp_peer_addr
    // The waiter registry: who is parked on which fd. Three parallel
    // vectors rather than a vector of structs, because a Vec of
    // pointers is not a thing here and the three are always written
    // together. `coro` 0 means the slot is free.
    ( Vec i ) w_fd
    ( Vec i ) w_wr
    ( Vec i ) w_coro
    i has_device
}

: ~ i g_shim 0

@ __lo_mac → i { ^ 2199023255553 }  // 02:00:00:00:00:01

@ __lo_ip → i { ^ ( ipv4_make 127 0 0 1 ) }

@ __lo_mask → i { ^ ( ipv4_make 255 0 0 0 ) }

@ __ms → i { ^ / ( monotonic_ns ) 1000000 }

@ __shim → *Shim {
    ? != g_shim 0 { ^ # *Shim g_shim } {}
    : *Shim sh # *Shim ( nurl_alloc Z Shim )
    : i now ( __ms )
    = . sh net ( stack_new ( __lo_mac ) ( __lo_ip ) ( __lo_mask ) 0 )
    // The ISS seed is the clock. RFC 793 wants a clock-driven initial
    // sequence number so an old duplicate from a previous incarnation
    // cannot be mistaken for live data, and a machine that boots into
    // the same program every time has no other source of variety.
    = . sh ts ( tstack_new . sh net & now 4294967295 )
    = . sh st ( sock_new . sh ts ( __lo_ip ) )
    = . sh peer ( vec_new [i] )
    = . sh w_fd ( vec_new [i] )
    = . sh w_wr ( vec_new [i] )
    = . sh w_coro ( vec_new [i] )
    = . sh has_device 0
    // An interface knows its own MAC. Without this the first connect
    // to 127.0.0.1 ARPs for itself and waits a retransmit timeout for
    // the answer.
    ( sock_seed_self . sh st now )
    = g_shim # i sh
    ^ sh
}

@ __tab → *SockTab { ^ . ( __shim ) st }

// ── the waiter registry ──────────────────────────────────────────
//
// A coroutine waiting on an fd PARKS, and whoever moves the stack wakes
// it. The alternative — polling — is what this file did first, and the
// cost is not efficiency: a polling waiter is RUNNABLE, so the
// scheduler can never say "nothing can run", which is the one statement
// this runtime exists to be able to make. Two pollers then each
// conclude the other is making progress and neither ever gives up.

@ __waiter_add i fd i for_write → i {
    : *Shim sh ( __shim )
    : i me ( nurl_fiber_current )
    ? == me 0 { ^ -1 } {}  // the main context cannot park inside itself
    : i n ( vec_len [i] . sh w_coro )
    : ~ i k 0
    ~ < k n {
        ? == 0 ?? ( vec_get [i] . sh w_coro k ) { T x → x F → 1 } {
            : b _a ( vec_set [i] . sh w_fd k fd )
            : b _b ( vec_set [i] . sh w_wr k for_write )
            : b _c ( vec_set [i] . sh w_coro k me )
            ^ k
        } {}
        = k + k 1
    }
    ( vec_push [i] . sh w_fd fd )
    ( vec_push [i] . sh w_wr for_write )
    ( vec_push [i] . sh w_coro me )
    ^ n
}

@ __waiter_del i slot → v {
    ? < slot 0 { ^ } {}
    : *Shim sh ( __shim )
    ? >= slot ( vec_len [i] . sh w_coro ) { ^ } {}
    : b _ok ( vec_set [i] . sh w_coro slot 0 )
}

// Wake every parked waiter whose fd has become ready. Called after
// anything that can change readiness — frames delivered, a timer fired,
// a shutdown. Unparking a coroutine that is not parked is banked as a
// permit by the runtime, so waking one that is mid-check is harmless.
@ __wake_ready → v {
    : *Shim sh ( __shim )
    : i me ( nurl_fiber_current )
    : i n ( vec_len [i] . sh w_coro )
    : ~ i k 0
    ~ < k n {
        : i coro ?? ( vec_get [i] . sh w_coro k ) { T x → x F → 0 }
        ? && != coro 0 != coro me {
            : i fd ?? ( vec_get [i] . sh w_fd k ) { T x → x F → 0 }
            : i wr ?? ( vec_get [i] . sh w_wr k ) { T x → x F → 0 }
            ? ( __ready fd wr ) { ( nurl_fiber_unpark coro ) } {}
        } {}
        = k + k 1
    }
}

// ── driving the machine ──────────────────────────────────────────

// One turn of the event loop: deliver what the stack has queued, then
// let its timers run. Returns 1 if anything happened.
@ __drive i now → i {
    : *SockTab st ( __tab )
    ? > ( sock_loopback st now ) 0 { ( __wake_ready ) ^ 1 } {}
    ? > ( sock_tick st now ) 0 { ( __wake_ready ) ^ 1 } {}
    ^ 0
}

@ __ready i fd i for_write → b {
    : *SockTab st ( __tab )
    ? != for_write 0 { ^ ( sock_writable st fd ) } {}
    ^ ( sock_readable st fd )
}

// How long may this waiter park? The earliest of the stack's own next
// deadline (a retransmit, a persist probe, TIME_WAIT) and whatever is
// left of the caller's timeout. -1 = neither: park until woken, and if
// nobody ever does, the scheduler's own detector says so — with every
// waiter parked and no timer armed, "nothing is runnable" is a proof
// again rather than a symptom.
@ __park_ms i now i timeout_ms i start → i {
    : i tmo ( sock_next_timeout ( __tab ) now )
    : ~ i d -1
    ? >= tmo 0 { = d ? > tmo 0 tmo 1 } {}
    ? > timeout_ms 0 {
        : i left - timeout_ms - now start
        : i l ? > left 0 left 0
        ? || < d 0 < l d { = d l } {}
    } {}
    ^ d
}

// Wait until `fd` is ready. 1 = ready, 0 = the deadline passed,
// -1 = nothing can ever make it ready (see the header).
//
// On a coroutine this PARKS: it registers on the fd, and whoever moves
// the stack wakes it. On the main context — which cannot park inside
// the scheduler it is — it drives the scheduler a step at a time, and a
// step that runs nothing, with no frames queued and no device, is the
// end of the road for this wait.
@ __wait i fd i for_write i timeout_ms → i {
    : i start ( __ms )
    : i slot ( __waiter_add fd for_write )
    : ~ i rc -1
    : ~ b again T
    ~ again {
        ? ( __ready fd for_write ) { = rc 1 = again F } {
            : i now ( __ms )
            : i moved ( __drive now )
            ? ( __ready fd for_write ) { = rc 1 = again F } {
                ? >= slot 0 {
                    : i unused ( nurl_bare_park_ms ( __park_ms now timeout_ms start ) )
                } {
                    ? == ( nurl_bare_poll ) 0 {
                        ? && == 0 ( sock_pending_frames ( __tab ) ) == 0 . ( __shim ) has_device {
                            = rc -1
                            = again F
                        } {}
                    } {}
                }
                ? && again > timeout_ms 0 {
                    ? >= - ( __ms ) start timeout_ms { = rc 0 = again F } {}
                } {}
            }
        }
    }
    ( __waiter_del slot )
    ^ rc
}

// The blocking/non-blocking decision, in one place. Returns 1 when the
// caller should retry the operation, 0 when it should report `err`.
@ __should_retry i fd i for_write → i {
    : *SockTab st ( __tab )
    ? ( sock_is_nonblock st fd ) { ^ 0 } {}
    : i tmo ( sock_timeout st fd )
    : i r ( __wait fd for_write tmo )
    ? == r 1 { ^ 1 } {}
    // A deadline that passed is SO_RCVTIMEO firing, which the socket
    // ABI reports as NetTimeout — the same code as EAGAIN, and the
    // caller above already knows the difference from context.
    ^ 0
}

// ── the ABI ──────────────────────────────────────────────────────

@ nurl_tcp_err_kind i handle → i { ^ ( sock_err ( __tab ) handle ) }

@ nurl_tcp_get_fd i handle → i { ^ handle }

@ nurl_tcp_set_nonblock i handle i on → v {
    ( sock_set_nonblock ( __tab ) handle != on 0 )
}

@ nurl_tcp_set_timeout i handle i ms → v { ( sock_set_timeout ( __tab ) handle ms ) }

@ nurl_tcp_ref i handle → v { ( sock_ref ( __tab ) handle ) }

@ nurl_tcp_unref i handle → v { ( nurl_tcp_close handle ) }

@ nurl_tcp_shutdown i handle → v {
    ( sock_shutdown ( __tab ) handle )
    // A shut fd reports itself ready so a waiter wakes and finds the
    // error — but only if something wakes it. Nothing else will: this
    // path emits no frames.
    ( __wake_ready )
}

@ nurl_tcp_close i handle → v {
    : *Shim sh ( __shim )
    ( __peer_forget sh handle )
    ( sock_close . sh st handle ( __ms ) )
    // Anyone parked on this fd has to wake and find it gone. Closing a
    // listener from another context IS how a server is stopped — the
    // workers are parked in accept and nothing else is going to move
    // the stack on their behalf.
    ( __wake_ready )
    // Give the FIN a chance to leave and be answered. A close that
    // returns before its own frames are on the wire would strand the
    // peer on a connection this side has already forgotten — on a
    // hosted socket the kernel does this after the process is gone.
    : ~ i k 0
    ~ && < k 8 > ( sock_pending_frames . sh st ) 0 {
        ( __drive ( __ms ) )
        = k + k 1
    }
}

// The address to bind or connect to. This machine has exactly one
// address, so anything that is neither it nor the wildcard is not
// reachable from here — and saying so is better than binding
// something the caller did not ask for.
@ __resolve s host → i {
    ?? ( ipv4_parse host ) {
        T a → a
        F → -1
    }
}

@ nurl_tcp_listen s host i port i backlog → i {
    : *SockTab st ( __tab )
    : i ip ( __resolve host )
    ? < ip 0 { ^ ( sock_err_fd st ( sock_err_bind ) ) } {}
    ? && != ip 0 != ip ( __lo_ip ) { ^ ( sock_err_fd st ( sock_err_bind ) ) } {}
    ^ ( sock_listen st ip port backlog )
}

@ nurl_tcp_accept i listener → i {
    : *SockTab st ( __tab )
    ~ T {
        : i fd ( sock_accept st listener )
        ? >= fd 0 { ^ fd } {}
        : i err - 0 fd
        ? != err ( sock_err_again ) { ^ ( sock_err_fd st err ) } {}
        ? == ( __should_retry listener 0 ) 0 {
            ^ ( sock_err_fd st ( sock_err_again ) )
        } {}
    }
    ^ ( sock_err_fd st ( sock_err_other ) )
}

// Blocking connect: the handle comes back either connected or
// carrying the error, which is the contract every caller of
// `tcp_connect` is written against.
@ nurl_tcp_connect s host i port → i {
    : *SockTab st ( __tab )
    : i ip ( __resolve host )
    ? < ip 0 { ^ ( sock_err_fd st ( sock_err_other ) ) } {}
    : i fd ( sock_connect st ip port 0 ( __ms ) )
    ? != ( sock_err st fd ) 0 { ^ fd } {}
    ~ T {
        : i s ( sock_status st fd )
        ? == s ( sock_conn_ready ) { ^ fd } {}
        ? == s ( sock_conn_failed ) {
            ( sock_close st fd ( __ms ) )
            ^ ( sock_err_fd st ( sock_err_closed ) )
        } {}
        // Not there yet. A pending connection becomes writable exactly
        // when it is established, so the ordinary wait does the job.
        : i r ( __wait fd 1 ( sock_timeout st fd ) )
        ? != r 1 {
            ( sock_close st fd ( __ms ) )
            ^ ( sock_err_fd st ? == r 0 ( sock_err_again ) ( sock_err_closed ) )
        } {}
    }
    ^ fd
}

@ nurl_tcp_read i conn s buf i cap → i {
    : *SockTab st ( __tab )
    ? <= cap 0 { ^ 0 } {}
    ~ T {
        : ( Vec u ) tmp ( vec_new [u] )
        : i n ( sock_read st conn tmp cap )
        ? > n 0 {
            ( nurl_memcpy buf # s ( vec_data [u] tmp ) n )
            ( vec_free [u] tmp )
            ^ n
        } {}
        ( vec_free [u] tmp )
        ? == n 0 { ^ 0 } {}
        : i err - 0 n
        ? != err ( sock_err_again ) { ^ -1 } {}
        ? == ( __should_retry conn 0 ) 0 { ^ -1 } {}
    }
    ^ -1
}

@ nurl_tcp_write i conn s buf i len → i {
    : *SockTab st ( __tab )
    ? <= len 0 { ^ 0 } {}
    : ( Vec u ) src ( vec_new [u] )
    ( bytes_extend_raw src buf len )
    // A BLOCKING write writes everything. The socket layer accepts what
    // fits in the send queue and says so, which is right for a
    // non-blocking fd — but `tcp_write_all`'s synchronous path issues
    // exactly one call and treats what comes back as the whole thing,
    // because that is what send(2) on a blocking socket does. A short
    // count there is not a slow write, it is silent data loss, and a
    // 64 KB send buffer makes it reachable with one ordinary HTTP body.
    //
    // No early `^` inside the loop: the Vec built above has one owner
    // and one release, and NURL has no `break` to jump to it from.
    : ~ i sent 0
    : ~ i rc -1
    : ~ b again T
    ~ again {
        : i n ( sock_write st conn src sent - len sent ( __ms ) )
        ? > n 0 {
            = sent + sent n
            // Push what was queued out of the door: the caller's next
            // act is usually to wait for the answer, and the peer
            // cannot answer bytes that never left.
            ( __drive ( __ms ) )
            ? >= sent len { = rc sent = again F } {
                ? ( sock_is_nonblock st conn ) { = rc sent = again F } {}
            }
        } {
            : i err - 0 n
            ? != err ( sock_err_again ) {
                = rc ? > sent 0 sent -1
                = again F
            } {
                ? == ( __should_retry conn 1 ) 0 {
                    = rc ? > sent 0 sent -1
                    = again F
                } {}
            }
        }
    }
    ( vec_free [u] src )
    ^ rc
}

@ nurl_reactor_wait_read i fd i timeout_ms → i { ^ ( __wait fd 0 timeout_ms ) }

@ nurl_reactor_wait_write i fd i timeout_ms → i { ^ ( __wait fd 1 timeout_ms ) }

// ── addresses ────────────────────────────────────────────────────

@ __addr_string i ip i port → s {
    : String s1 ( ipv4_str ip )
    : s a ( nurl_str_cat3 ( string_data s1 ) `:` ( nurl_str_int port ) )
    ( string_free s1 )
    ^ a
}

// OWNED "ip:port" — the caller frees it. The counterpart of binding
// port 0: the stack picked the port and this is how the program that
// asked finds out.
@ nurl_tcp_local_addr i handle → s {
    : *SockTab st ( __tab )
    ^ ( __addr_string ( sock_local_ip st handle ) ( sock_local_port st handle ) )
}

// BORROWED — the contract says the view lives as long as the
// connection does, so the string is cached per fd and released by
// close. A fresh allocation per call would leak on every caller that
// (correctly, per that contract) does not free it.
@ nurl_tcp_peer_addr i conn → s {
    : *Shim sh ( __shim )
    : i slot - conn 3
    ? < slot 0 { ^ `` } {}
    ~ <= ( vec_len [i] . sh peer ) slot { ( vec_push [i] . sh peer 0 ) }
    : i cached ?? ( vec_get [i] . sh peer slot ) { T x → x F → 0 }
    ? != cached 0 { ^ # s cached } {}
    : s a ( __addr_string ( sock_peer_ip . sh st conn ) ( sock_peer_port . sh st conn ) )
    : b _ok ( vec_set [i] . sh peer slot # i a )
    ^ # s a
}

@ __peer_forget * Shim sh i conn → v {
    : i slot - conn 3
    ? || < slot 0 >= slot ( vec_len [i] . sh peer ) { ^ } {}
    : i cached ?? ( vec_get [i] . sh peer slot ) { T x → x F → 0 }
    ? == cached 0 { ^ } {}
    ( nurl_free # s cached )
    : b _ok ( vec_set [i] . sh peer slot 0 )
}
