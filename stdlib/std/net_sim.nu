// stdlib/std/net_sim.nu — a simulated network behind TcpListener / TcpConn.
//
// A server built on std/net's handles runs here unchanged: a NetSim is
// a set of nodes, each a whole sans-IO TCP/IP stack (stdlib/net/:
// Ethernet, ARP, IPv4, TCP, the socket layer's fd table), whose frames
// travel between the nodes over the seeded bus of stdlib/dist/sim.nu —
// with its drops, latency, jitter (so reordering) and partitions. A
// listener or connection made here is an ordinary TcpListener /
// TcpConn: every tcp_* operation goes to this file through std/net's
// transport seam (the NetTransport trait), so HttpServer, the HttpApp
// facade and anything else written against those handles serve over the
// simulated wire exactly as they do over the kernel's. No operating
// system socket is opened.
//
//   ( netsim_new      i nodes i seed i drop_pct i latency_ms i jitter_ms ) → NetSim
//   ( netsim_listen   NetSim n i node i port )                  → !TcpListener NetErr
//   ( netsim_connect  NetSim n i node s host i port i ms )      → !TcpConn NetErr
//   ( netsim_node_ip  NetSim n i node )                         → String   "10.0.0.<node+1>"
//   ( netsim_partition NetSim n i a i b ) / ( netsim_heal NetSim n i a i b )
//   ( netsim_heal_all NetSim n )
//   ( netsim_delivered NetSim n ) / ( netsim_dropped NetSim n ) → i  frames
//
// Node k answers to 10.0.0.<k+1>/24 (MAC 02:00:00:00:00:<k+1>), so at
// most 254 nodes; every node already knows every other's MAC (its ARP
// cache is seeded), and when an entry ages out the request is broadcast
// over the bus like any other frame. `port` 0 in netsim_listen picks a
// free one (tcp_local_addr reads it back); netsim_connect dials `host`
// — a node's address, or 127.0.0.1 for the node itself — from `node`,
// giving up after `ms` (<= 0: no deadline of its own). A refused or
// reset connect reports NetClosed, a deadline NetTimeout, and a
// partition that drops every SYN the second of those.
//
// ── time and blocking ────────────────────────────────────────────
//
// The clock is the runtime's (monotonic, in ms), and a wait is the
// runtime's: a fiber parks (nurl_fiber_park_with_mutex_ms), a thread
// blocks on the network's condition variable, each for as long as the
// next thing that can change the answer — the bus's next delivery, a
// node's next TCP timer, or the caller's own deadline. So on today's
// runtime a test runs in real time, and under a runtime whose clock and
// scheduler are themselves simulated (DST: a seeded scheduler, timers on
// a virtual clock) the same code runs on virtual time, reproducibly by
// seed — nothing in this file decides what time it is.
//
// Whoever waits moves the network, as unikernel/net/sockets.nu does:
// before every check a waiter delivers what is due and runs the timers
// that have fired, and every operation that moved a frame wakes every
// waiter to look again. A waiter blocks only on a quiet network — no
// frame queued, nothing due — because a queued frame is exactly what
// can make its socket ready, and nobody else is going to deliver it.
//
// ── memory and threads ───────────────────────────────────────────
//
// NetSim is a handle: every copy is the same network, and the last
// owner — the harness's copy or the last socket's — releases it. All of
// it is reached under one mutex, which is never held while user code
// runs, so it is shared by any number of threads and fibers (Sync). A
// socket is a NetTransport object owned by its TcpConn / TcpListener:
// its drop closes it (FIN on a connection, the port freed on a
// listener), so nothing is closed by hand, and an fd number reused by a
// later socket is never reached through an old one — each socket
// carries the id it was given, and the node's table says which id holds
// each fd now.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`
$ `stdlib/core/rcbox.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/async_ffi.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/net.nu`
$ `stdlib/net/pktbuf.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/eth.nu`
$ `stdlib/net/arp.nu`
$ `stdlib/net/ipv4.nu`
$ `stdlib/net/stack.nu`
$ `stdlib/net/tcp.nu`
$ `stdlib/net/tcpstack.nu`
$ `stdlib/net/socket.nu`
$ `stdlib/dist/sim.nu`
$ `stdlib/std/random.nu`

// ── addresses ────────────────────────────────────────────────────

@ __ns_mac_base → i { ^ 2199023255552 }  // 02:00:00:00:00:00

@ __ns_mac i node → i { ^ + + ( __ns_mac_base ) node 1 }

@ __ns_ip i node → i { ^ ( ipv4_make 10 0 0 + node 1 ) }

@ __ns_mask → i { ^ ( ipv4_make 255 255 255 0 ) }

@ __ns_loopback → i { ^ ( ipv4_make 127 0 0 1 ) }

@ __ns_max_nodes → i { ^ 254 }

// "ip:port", owned.
@ __ns_addr_string i ip i port → String {
    : String out ( ipv4_str ip )
    ( string_push_str out `:` )
    ( string_push_int out port )
    ^ out
}

// ── the network ──────────────────────────────────────────────────

// One node: its stack, and which socket holds each of its fds now
// (`sids`, by fd - 3; 0 = none) — what keeps a closed socket from
// reaching whoever was given its fd number next.
: NsNode {
    NetStack net
    TcpStack ts
    SockTab st
    ( Vec i ) sids
    ( Vec i ) wshut  // 1 = the write side was shut (nt_shutdown both)
}

: NetSimImpl {
    Mutex m
    Cond c  // threads waiting for the network to move
    ( Vec i ) fibers  // parked fibers waiting for the same
    i threads  // threads in cond_wait_ms
    SimNet bus
    ( Vec ( Box NsNode ) ) nodes  // a block each, so a node's address stays put
    i next_sid
}

: NetSim { ( Shared NetSimImpl ) ctl }

// Every copy is the same network, reached only under its own mutex —
// which is never held while a caller's code runs — by as many threads
// and fibers as hold a copy (stdlib/core/marker.nu). An assertion, not a
// proof; what backs it is that every function below that touches the
// state takes the lock first (__ns_lock) and lets it go before it
// returns or blocks.
% Sync NetSim {}

@ NetSim_share NetSim h → NetSim { ^ @ NetSim { ( shared_clone [NetSimImpl] . h ctl ) } }

@ NetSim_drop sink NetSim h → v {}

@ __ns_ptr NetSim h → *NetSimImpl { ^ ( shared_ptr [NetSimImpl] . h ctl ) }

@ __ns_lock NetSim h → *NetSimImpl {
    : *NetSimImpl w ( __ns_ptr h )
    ( mutex_lock . w m )
    ^ w
}

@ __ns_unlock * NetSimImpl w → v { ( mutex_unlock . w m ) }

@ __ns_now → i { ^ / ( monotonic_ns ) 1000000 }

@ __ns_node * NetSimImpl w i k → *NsNode {
    ^ ( box_ptr [NsNode] ( vec_at [( Box NsNode )] . w nodes k ) )
}

@ __ns_count * NetSimImpl w → i { ^ ( vec_len [( Box NsNode )] . w nodes ) }

// A network of `nodes` stacks (1..254) over a bus seeded with `seed`:
// each frame is lost with probability drop_pct/100, and the rest arrive
// latency_ms plus 0..jitter_ms later (so out of order when jitter > 0).
// Seed 0 is the run's own: it is drawn from the entropy source, which a
// simulation (nurl --sim, NURL_SIM=<seed>) draws from its seed — so
// `nurlpkg test --sim --seeds N` varies the network's drops, jitter and
// sequence numbers with the run's seed, and replays them with it. A
// test that passes its own seed keeps exactly that network.
@ netsim_new i nodes i seed_arg i drop_pct i latency_ms i jitter_ms → NetSim {
    : i seed ? == seed_arg 0 | & ( rand_u64 ) 2147483647 1 seed_arg
    : i n ? < nodes 1 1 ? > nodes ( __ns_max_nodes ) ( __ns_max_nodes ) nodes
    : i now ( __ns_now )
    : ( Vec ( Box NsNode ) ) list ( vec_with_cap [( Box NsNode )] n )
    : ~ i k 0
    ~ < k n {
        : NetStack net ( stack_new ( __ns_mac k ) ( __ns_ip k ) ( __ns_mask ) 0 )
        // The initial sequence numbers come from the seed too: the same
        // seed, the same segments.
        : TcpStack ts ( tstack_new net + * seed 7919 + * k 104729 1 )
        : SockTab st ( sock_new ts ( __ns_ip k ) )
        // An interface knows its own MAC, and on this network it knows
        // every neighbour's: no connect waits a retransmit for ARP.
        ( sock_seed_self st now )
        ( sock_seed_addr st ( __ns_loopback ) now )
        : ~ i j 0
        ~ < j n {
            ? != j k { ( arp_cache_insert ( stack_arp net ) ( __ns_ip j ) ( __ns_mac j ) now ) } {}
            = j + j 1
        }
        ( vec_push [( Box NsNode )] list ( box_new [NsNode] @ NsNode { net ts st ( vec_new [i] ) ( vec_new [i] ) } ) )
        = k + k 1
    }
    ^ @ NetSim { ( shared_new [NetSimImpl] @ NetSimImpl {
            ( mutex_new )
            ( cond_new )
            ( vec_new [i] )
            0
            ( sim_net_new n seed drop_pct latency_ms jitter_ms )
            list
            1
        } ) }
}

// The address node `node` answers to.
@ netsim_node_ip NetSim h i node → String { ^ ( ipv4_str ( __ns_ip node ) ) }

// Cut the link between nodes a and b both ways: every frame between them
// is lost until netsim_heal. TCP sees it as loss — retransmits, and a
// connection that is not healed in time gives up.
@ netsim_partition NetSim h i a i b → v {
    : *NetSimImpl w ( __ns_lock h )
    ( sim_partition . w bus a b )
    ( __ns_unlock w )
}

@ netsim_heal NetSim h i a i b → v {
    : *NetSimImpl w ( __ns_lock h )
    ( sim_heal . w bus a b )
    // Nothing is delivered by the heal itself: TCP's own retransmit
    // timer resends, and the waiters it concerns are parked until then.
    ( __ns_wake_all w )
    ( __ns_unlock w )
}

@ netsim_heal_all NetSim h → v {
    : *NetSimImpl w ( __ns_lock h )
    ( sim_heal_all . w bus )
    ( __ns_wake_all w )
    ( __ns_unlock w )
}

// Frames the bus delivered / lost (to the drop roll or a partition).
@ netsim_delivered NetSim h → i {
    : *NetSimImpl w ( __ns_lock h )
    : i d ( sim_delivered . w bus )
    ( __ns_unlock w )
    ^ d
}

@ netsim_dropped NetSim h → i {
    : *NetSimImpl w ( __ns_lock h )
    : i d ( sim_dropped . w bus )
    ( __ns_unlock w )
    ^ d
}

// ── moving the network (lock held) ───────────────────────────────

// A frame `src` put on its wire goes where its destination MAC says:
// to that node, or — a broadcast, an ARP request — to every other one.
// A MAC no node has is lost, as on a real segment.
@ __ns_route * NetSimImpl w i src ( Vec u ) f i now → v {
    : EthHdr eh ( eth_parse f )
    ? ! . eh valid { ^ v } {}
    : i n ( __ns_count w )
    ? ( mac_is_broadcast . eh dst ) {
        : ~ i k 0
        ~ < k n {
            ? != k src { ( sim_send . w bus src k f now ) } {}
            = k + k 1
        }
        ^ v
    } {}
    : i dst - - . eh dst ( __ns_mac_base ) 1
    ? && >= dst 0 < dst n { ( sim_send . w bus src dst f now ) } {}
}

// Deliver everything the network has to deliver at `now`: what each
// node queued goes on the bus, what the bus has due goes into its node,
// the timers that have fired run — round after round, until a round
// moves nothing. T when anything moved.
@ __ns_pump * NetSimImpl w i now → b {
    : i n ( __ns_count w )
    : ~ b moved F
    : ~ b going T
    ~ going {
        : ~ b any F
        : ~ i k 0
        ~ < k n {
            : *NsNode nd ( __ns_node w k )
            ? > ( sock_pending_frames . nd st ) 0 {
                // Taken, not walked in place: delivering a frame can
                // queue more on the same node.
                : PktBuf out ( sock_take_out . nd st )
                : i nf ( pktbuf_count out )
                : ~ i j 0
                ~ < j nf {
                    : ( Vec u ) f ( vec_new [u] )
                    : i _c ( pktbuf_copy_to f out j )
                    ( __ns_route w k f now )
                    = j + j 1
                }
                = any T
            } {}
            = k + k 1
        }
        : ( Vec SimMsg ) due ( sim_due . w bus now )
        : i nd ( vec_len [SimMsg] due )
        : ~ i d 0
        ~ < d nd {
            ?? ( vec_get [SimMsg] due d ) {
                T msg → {
                    : *NsNode dn ( __ns_node w ( sim_msg_dst msg ) )
                    : i _r ( sock_rx . dn st ( sim_msg_bytes msg ) now )
                }
                F → {}
            }
            = d + d 1
        }
        ? > nd 0 { = any T } {}
        = k 0
        ~ < k n {
            : *NsNode nt ( __ns_node w k )
            ? > ( sock_tick . nt st now ) 0 { = any T } {}
            = k + k 1
        }
        ? any { = moved T } { = going F }
    }
    ^ moved
}

// Milliseconds until the next thing that can change a socket's state —
// the bus's next delivery or any node's next TCP timer — or -1 when
// nothing is scheduled.
@ __ns_next_ms * NetSimImpl w i now → i {
    : ~ i best -1
    : i due ( sim_next_due . w bus )
    ? >= due 0 { = best ? > due now - due now 0 } {}
    : i n ( __ns_count w )
    : ~ i k 0
    ~ < k n {
        : i t ( sock_next_timeout . ( __ns_node w k ) st now )
        ? >= t 0 { ? || < best 0 < t best { = best t } {} } {}
        = k + k 1
    }
    ^ best
}

// Wake every waiter to look again: a frame moved, a socket closed or
// shut, a link healed. Each one re-checks its own socket.
@ __ns_wake_all * NetSimImpl w → v {
    ~ > ( vec_len [i] . w fibers ) 0 {
        ?? ( vec_pop [i] . w fibers ) {
            T fh → { : i _w ( nurl_fiber_wake fh ) }
            F → {}
        }
    }
    ? > . w threads 0 { ( cond_broadcast . w c ) } {}
}

// Block until woken or `ms` pass (< 0: until woken) — a fiber parked, a
// thread on the condition variable. The lock is held on entry and on
// return, and let go while blocked.
@ __ns_block * NetSimImpl w i ms → v {
    : i fcur ( nurl_fiber_current )
    ? != fcur 0 {
        ( vec_push [i] . w fibers fcur )
        : i rc ( nurl_fiber_park_with_mutex_ms # i ( mutex_raw . w m ) ms )
        ? >= rc 0 {
            ( mutex_lock . w m )
            // Its deadline came first: still listed, so it leaves.
            : i nf ( vec_len [i] . w fibers )
            : ~ i k 0
            ~ < k nf {
                ? == ( vec_at [i] . w fibers k ) fcur {
                    : ?i _gone ( vec_remove [i] . w fibers k )
                    break
                } {}
                = k + k 1
            }
            ^ v
        } {}
        // No fiber backend after all: the mutex is still held.
        : ?i _back ( vec_pop [i] . w fibers )
    } {}
    = . w threads + . w threads 1
    : b _sig ( cond_wait_ms . w c . w m ms )
    = . w threads - . w threads 1
}

// ── sockets (lock held) ──────────────────────────────────────────

// Does socket `sid` still hold fd `fd` on node `node`?
@ __ns_holds * NetSimImpl w i node i fd i sid → b {
    : *NsNode nd ( __ns_node w node )
    : i slot - fd 3
    ? || < slot 0 >= slot ( vec_len [i] . nd sids ) { ^ F } {}
    ^ == ( vec_at [i] . nd sids slot ) sid
}

// Give fd `fd` of node `node` to a new socket; its id back.
@ __ns_claim * NetSimImpl w i node i fd → i {
    : *NsNode nd ( __ns_node w node )
    : i slot - fd 3
    ~ <= ( vec_len [i] . nd sids ) slot {
        ( vec_push [i] . nd sids 0 )
        ( vec_push [i] . nd wshut 0 )
    }
    : i sid . w next_sid
    = . w next_sid + sid 1
    : b _a ( vec_set [i] . nd sids slot sid )
    : b _b ( vec_set [i] . nd wshut slot 0 )
    ^ sid
}

@ __ns_release * NetSimImpl w i node i fd → v {
    : *NsNode nd ( __ns_node w node )
    : i slot - fd 3
    ? || < slot 0 >= slot ( vec_len [i] . nd sids ) { ^ v } {}
    : b _a ( vec_set [i] . nd sids slot 0 )
}

@ __ns_wshut * NetSimImpl w i node i fd → b {
    : *NsNode nd ( __ns_node w node )
    : i slot - fd 3
    ? || < slot 0 >= slot ( vec_len [i] . nd wshut ) { ^ F } {}
    ^ != ( vec_at [i] . nd wshut slot ) 0
}

// 0 read, 1 write, 2 either. A socket that is gone or broken reports
// itself ready: its waiter must wake to find out.
@ __ns_ready * NetSimImpl w i node i fd i sid i mode → b {
    ? ! ( __ns_holds w node fd sid ) { ^ T } {}
    : SockTab st . ( __ns_node w node ) st
    ? == mode 1 { ^ ( sock_writable st fd ) } {}
    ? == mode 2 { ^ | ( sock_readable st fd ) ( sock_writable st fd ) } {}
    ^ ( sock_readable st fd )
}

// Nothing left to deliver right now: no frame queued on any node and
// nothing due on the bus.
@ __ns_quiet * NetSimImpl w i now → b {
    : i n ( __ns_count w )
    : ~ i k 0
    ~ < k n {
        ? > ( sock_pending_frames . ( __ns_node w k ) st ) 0 { ^ F } {}
        = k + k 1
    }
    : i due ( sim_next_due . w bus )
    ^ | < due 0 > due now
}

// Wait until socket `sid` (fd `fd` on `node`) is ready for `mode`, or
// `timeout_ms` passes (< 0: no deadline; 0: look once, after delivering
// what is due). 1 ready, 0 the deadline passed. Lock held, and let go
// only while blocked.
@ __ns_wait * NetSimImpl w i node i fd i sid i mode i timeout_ms → i {
    : i start ( __ns_now )
    ~ T {
        : i now ( __ns_now )
        ? ( __ns_pump w now ) { ( __ns_wake_all w ) } {}
        ? ( __ns_ready w node fd sid mode ) { ^ 1 } {}
        : i spent - now start
        ? & >= timeout_ms 0 >= spent timeout_ms { ^ 0 } {}
        ? ( __ns_quiet w now ) {
            : ~ i d ( __ns_next_ms w now )
            ? == d 0 { = d 1 } {}
            ? >= timeout_ms 0 {
                : i left - timeout_ms spent
                ? | < d 0 < left d { = d left } {}
            } {}
            ( __ns_block w d )
        } {}
    }
    ^ 0
}

// After an operation: deliver what it queued, and wake whoever that
// concerns.
@ __ns_settle * NetSimImpl w → v {
    ? ( __ns_pump w ( __ns_now ) ) { ( __ns_wake_all w ) } {}
}

// ── the transport ────────────────────────────────────────────────

// One socket of the network: which node, which fd there, and the id it
// was given for that fd. Never changes once made; what changes is in the
// network, under its lock. (Its address rides beside it in the handle:
// tcp_conn_over / tcp_listener_over.)
: NsSock {
    NetSim w
    i node
    i fd
    i sid
}

% Drop NsSock {
    @ drop NsSock k → v { ( __ns_close k ) }
}

// Close the socket, once: a FIN for a connection (a RST when unread data
// is thrown away, as close(2) does), the port freed for a listener. The
// fd's id is cleared first, so a later operation through this socket —
// and the drop after an early close — reaches nothing.
@ __ns_close NsSock k → v {
    : *NetSimImpl w ( __ns_lock . k w )
    ? ( __ns_holds w . k node . k fd . k sid ) {
        ( __ns_release w . k node . k fd )
        ( sock_close . ( __ns_node w . k node ) st . k fd ( __ns_now ) )
        ( __ns_settle w )
        // Whoever was waiting on it wakes to find it gone.
        ( __ns_wake_all w )
    } {}
    ( __ns_unlock w )
}

@ __ns_sock NetSim h i node i fd i sid sink String peer → TcpConn {
    ^ ( tcp_conn_over ( dyn NetTransport @ NsSock { h node fd sid } ) peer )
}

// A socket-layer count (`- err` below 0) as a NetErr result.
@ __ns_count_result i n → !i NetErr {
    ? >= n 0 { ^ @ !i NetErr { T n } } {}
    ^ @ !i NetErr { F ( _net_err_of - 0 n ) }
}

// `len` bytes of `src` from `off` into the socket: `wait` T sends them
// all (or fails, `- again` when the write deadline or the timeout passed
// first); F takes what fits now, possibly 0. A count, or `- err`.
@ __ns_write NsSock k ( Vec u ) src i off i len b wait → i {
    ? <= len 0 { ^ 0 } {}
    : *NetSimImpl w ( __ns_lock . k w )
    : ~ i r - 0 ( sock_err_closed )
    : ~ i sent 0
    ~ ( __ns_holds w . k node . k fd . k sid ) {
        ? ( __ns_wshut w . k node . k fd ) { = r - 0 ( sock_err_closed ) break } {}
        : SockTab st . ( __ns_node w . k node ) st
        ? >= sent len { = r sent break } {}
        : i n ( sock_write st . k fd src + off sent - len sent ( __ns_now ) )
        ? > n 0 {
            = sent + sent n
            // Out of the door now: the peer cannot answer bytes that are
            // still queued here.
            ( __ns_settle w )
            ? | ! wait ( sock_is_nonblock st . k fd ) { = r sent break } {}
        } {
            ? != n - 0 ( sock_err_again ) { = r n break } {}
            ? | ! wait ( sock_is_nonblock st . k fd ) { = r sent break } {}
            // The send queue is full: wait for room, as long as the write
            // deadline and the socket's timeout allow. Running out ends
            // the write even after part of it went — the caller must
            // retire a connection holding half a message.
            : i ms ( sock_write_wait_ms st . k fd ( monotonic_ns ) )
            ? == ms 0 { = r - 0 ( sock_err_again ) break } {}
            ? == ( __ns_wait w . k node . k fd . k sid 1 ms ) 0 { = r - 0 ( sock_err_again ) break } {}
            = r - 0 ( sock_err_closed )
        }
    }
    ( __ns_settle w )
    ( __ns_unlock w )
    ^ r
}

% NetTransport NsSock {
    @ nt_accept NsSock k → !TcpConn NetErr {
        : *NetSimImpl w ( __ns_lock . k w )
        ~ T {
            ? ! ( __ns_holds w . k node . k fd . k sid ) {
                ( __ns_unlock w )
                ^ @ !TcpConn NetErr { F # NetErr NetAccept }
            } {}
            : SockTab st . ( __ns_node w . k node ) st
            : i r ( sock_accept st . k fd )
            ? > r 0 {
                : i sid ( __ns_claim w . k node r )
                : String peer ( __ns_addr_string ( sock_peer_ip st r ) ( sock_peer_port st r ) )
                ( __ns_settle w )
                ( __ns_unlock w )
                // Made with the lock let go: a socket's drop takes it.
                ^ @ !TcpConn NetErr { T ( __ns_sock . k w . k node r sid peer ) }
            } {}
            ? != r - 0 ( sock_err_again ) {
                ( __ns_unlock w )
                ^ @ !TcpConn NetErr { F ( _net_err_of - 0 r ) }
            } {}
            // An accept has no deadline: it waits until a connection
            // arrives or the listener is stopped.
            : i _rc ( __ns_wait w . k node . k fd . k sid 0 -1 )
        }
        ( __ns_unlock w )
        ^ @ !TcpConn NetErr { F # NetErr NetOther }
    }

    @ nt_read_into NsSock k ( Vec u ) buf i max b wait → !i NetErr {
        ? <= max 0 { ^ @ !i NetErr { T 0 } } {}
        : *NetSimImpl w ( __ns_lock . k w )
        : ~ i r - 0 ( sock_err_closed )
        ~ ( __ns_holds w . k node . k fd . k sid ) {
            : SockTab st . ( __ns_node w . k node ) st
            : i n ( sock_read st . k fd buf max ( __ns_now ) )
            = r n
            ? != n - 0 ( sock_err_again ) { break } {}
            ? | ! wait ( sock_is_nonblock st . k fd ) { break } {}
            // Not there yet: wait as long as the socket's timeout says
            // (0 = none set = for ever). A deadline that passes leaves the
            // "again" in `r`: NetTimeout.
            : i tmo ( sock_timeout st . k fd )
            ? == ( __ns_wait w . k node . k fd . k sid 0 ? > tmo 0 tmo -1 ) 0 { break } {}
            = r - 0 ( sock_err_closed )
        }
        // A read opens the window: the update it queued goes out.
        ( __ns_settle w )
        ( __ns_unlock w )
        // tcp_read_into's results: data, the end of the stream as
        // NetClosed — and, not waiting, "nothing yet" as Ok(0).
        ? > r 0 { ^ @ !i NetErr { T r } } {}
        ? == r 0 { ^ @ !i NetErr { F # NetErr NetClosed } } {}
        ? & ! wait == r - 0 ( sock_err_again ) { ^ @ !i NetErr { T 0 } } {}
        ^ @ !i NetErr { F ( _net_err_of - 0 r ) }
    }

    @ nt_write NsSock k ( Vec u ) bytes → !v NetErr {
        : i r ( __ns_write k bytes 0 ( vec_len [u] bytes ) T )
        ? < r 0 { ^ @ !v NetErr { F ( _net_err_of - 0 r ) } } {}
        ^ @ !v NetErr { T 0 }
    }

    @ nt_write_all NsSock k ( Vec u ) head ( Vec u ) body → !v NetErr {
        : i r1 ( __ns_write k head 0 ( vec_len [u] head ) T )
        ? < r1 0 { ^ @ !v NetErr { F ( _net_err_of - 0 r1 ) } } {}
        : i r2 ( __ns_write k body 0 ( vec_len [u] body ) T )
        ? < r2 0 { ^ @ !v NetErr { F ( _net_err_of - 0 r2 ) } } {}
        ^ @ !v NetErr { T 0 }
    }

    @ nt_try_write NsSock k ( Vec u ) wire i off → !i NetErr {
        ^ ( __ns_count_result ( __ns_write k wire off - ( vec_len [u] wire ) off F ) )
    }

    @ nt_wait_io NsSock k b readable b writable i timeout_ms → i {
        ? & ! readable ! writable { ^ -1 } {}
        : i mode ? & readable writable 2 ? writable 1 0
        : *NetSimImpl w ( __ns_lock . k w )
        : ~ i wait timeout_ms
        ? & writable ( __ns_holds w . k node . k fd . k sid ) {
            : i left ( sock_write_wait_ms . ( __ns_node w . k node ) st . k fd ( monotonic_ns ) )
            ? == left 0 { ( __ns_unlock w ) ^ 0 } {}
            ? & >= left 0 | < wait 0 < left wait { = wait left } {}
        } {}
        : i rc ( __ns_wait w . k node . k fd . k sid mode wait )
        ( __ns_unlock w )
        ^ rc
    }

    @ nt_close NsSock k → v { ( __ns_close k ) }

    @ nt_shutdown NsSock k b both → v {
        : *NetSimImpl w ( __ns_lock . k w )
        ? ( __ns_holds w . k node . k fd . k sid ) {
            // The read side (a listener: accepting) refuses from here, and
            // a reader parked on it wakes to find that out; `both` shuts
            // the write side too.
            ( sock_shutdown . ( __ns_node w . k node ) st . k fd )
            ? both {
                : *NsNode nd ( __ns_node w . k node )
                : b _s ( vec_set [i] . nd wshut - . k fd 3 1 )
            } {}
            ( __ns_wake_all w )
        } {}
        ( __ns_unlock w )
    }

    @ nt_set_timeout NsSock k i ms → v {
        : *NetSimImpl w ( __ns_lock . k w )
        ? ( __ns_holds w . k node . k fd . k sid ) { ( sock_set_timeout . ( __ns_node w . k node ) st . k fd ms ) } {}
        ( __ns_unlock w )
    }

    @ nt_timeout_ms NsSock k → i {
        : *NetSimImpl w ( __ns_lock . k w )
        : i ms ? ( __ns_holds w . k node . k fd . k sid ) ( sock_timeout . ( __ns_node w . k node ) st . k fd ) 0
        ( __ns_unlock w )
        ^ ms
    }

    @ nt_set_write_deadline NsSock k i ns → v {
        : *NetSimImpl w ( __ns_lock . k w )
        ? ( __ns_holds w . k node . k fd . k sid ) { ( sock_set_write_deadline . ( __ns_node w . k node ) st . k fd ns ) } {}
        ( __ns_unlock w )
    }

    @ nt_write_deadline NsSock k → i {
        : *NetSimImpl w ( __ns_lock . k w )
        : i ns ? ( __ns_holds w . k node . k fd . k sid ) ( sock_write_deadline . ( __ns_node w . k node ) st . k fd ) 0
        ( __ns_unlock w )
        ^ ns
    }

    @ nt_set_nonblock NsSock k b on → v {
        : *NetSimImpl w ( __ns_lock . k w )
        ? ( __ns_holds w . k node . k fd . k sid ) { ( sock_set_nonblock . ( __ns_node w . k node ) st . k fd on ) } {}
        ( __ns_unlock w )
    }

}

// ── listen and connect ───────────────────────────────────────────

// Listen on `port` of node `node` (0: a free port, read back with
// tcp_local_addr). A taken port is NetAddrInUse, as bind(2) says.
@ netsim_listen NetSim h i node i port → !TcpListener NetErr {
    : *NetSimImpl w ( __ns_lock h )
    ? | < node 0 >= node ( __ns_count w ) {
        ( __ns_unlock w )
        ^ @ !TcpListener NetErr { F # NetErr NetBind }
    } {}
    : SockTab st . ( __ns_node w node ) st
    : i fd ( sock_listen st ( __ns_ip node ) port ( tcp_listen_default_backlog ) )
    : i err ( sock_err st fd )
    ? != err 0 {
        ( sock_close st fd ( __ns_now ) )
        ( __ns_unlock w )
        ^ @ !TcpListener NetErr { F ( _net_err_of err ) }
    } {}
    : i sid ( __ns_claim w node fd )
    : String local ( __ns_addr_string ( __ns_ip node ) ( sock_local_port st fd ) )
    ( __ns_unlock w )
    ^ @ !TcpListener NetErr { T ( tcp_listener_over ( dyn NetTransport @ NsSock { h node fd sid } ) local ) }
}

// The node a dialled address names, from `node`'s point of view: one of
// the network's addresses, or loopback for `node` itself. -1: none.
@ __ns_dial_node * NetSimImpl w i node s host → i {
    ?? ( ipv4_parse host ) {
        T ip → {
            ? == ip ( __ns_loopback ) { ^ node } {}
            : i last - & ip 255 1
            ? && == & ip ( __ns_mask ) & ( __ns_ip 0 ) ( __ns_mask ) && >= last 0 < last ( __ns_count w ) { ^ last } {}
            ^ -1
        }
        F → { ^ -1 }
    }
}

// Connect from node `node` to `host`:`port`, waiting at most `ms`
// (<= 0: until TCP itself gives up). The connection comes back
// established, or the error: NetClosed for a refusal or a reset,
// NetTimeout for the deadline, NetOther for an address no node has.
@ netsim_connect NetSim h i node s host i port i ms → !TcpConn NetErr {
    : *NetSimImpl w ( __ns_lock h )
    ? | < node 0 >= node ( __ns_count w ) {
        ( __ns_unlock w )
        ^ @ !TcpConn NetErr { F # NetErr NetOther }
    } {}
    : i to ( __ns_dial_node w node host )
    ? < to 0 {
        ( __ns_unlock w )
        ^ @ !TcpConn NetErr { F # NetErr NetOther }
    } {}
    : i dst_ip ? == to node ( __ns_ip node ) ( __ns_ip to )
    : SockTab st . ( __ns_node w node ) st
    : i fd ( sock_connect st dst_ip port 0 ( __ns_now ) )
    : i err ( sock_err st fd )
    ? != err 0 {
        ( sock_close st fd ( __ns_now ) )
        ( __ns_unlock w )
        ^ @ !TcpConn NetErr { F ( _net_err_of err ) }
    } {}
    : i sid ( __ns_claim w node fd )
    ( __ns_settle w )
    : i start ( __ns_now )
    ~ T {
        : i status ( sock_status st fd )
        ? == status ( sock_conn_ready ) {
            : String peer ( __ns_addr_string dst_ip port )
            ( __ns_unlock w )
            ^ @ !TcpConn NetErr { T ( __ns_sock h node fd sid peer ) }
        } {}
        : ~ NetErr fail NetClosed
        : ~ b give_up == status ( sock_conn_failed )
        ? ! give_up {
            // A pending connection becomes writable exactly when it is
            // established (or fails), so the ordinary wait does it.
            : i left ? > ms 0 - ms - ( __ns_now ) start -1
            ? & > ms 0 <= left 0 { = give_up T = fail NetTimeout } {
                ? == ( __ns_wait w node fd sid 1 left ) 0 { = give_up T = fail NetTimeout } {}
            }
        } {}
        ? give_up {
            ( __ns_release w node fd )
            ( sock_close st fd ( __ns_now ) )
            ( __ns_settle w )
            ( __ns_unlock w )
            ^ @ !TcpConn NetErr { F fail }
        } {}
    }
    ( __ns_unlock w )
    ^ @ !TcpConn NetErr { F # NetErr NetOther }
}
