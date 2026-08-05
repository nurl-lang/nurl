// net_tcpstack.nu — Phase A4.0: TCP over the sans-IO IPv4 stack.
//
// net_tcp.nu already drives two Tcbs against each other with segments.
// This is the layer under that: two whole stacks wired frame-to-frame,
// so every segment travels as a real Ethernet frame with a real IPv4
// header and a checksum computed over the real pseudo-header, and the
// connection it belongs to is found by demultiplexing rather than by
// the test handing it over.
//
// What is asserted here is what only exists at this layer:
//
//   * the passive open — a SYN to a listening port creates a NEW
//     connection and leaves the listener listening;
//   * the ARP wait — the very first SYN to an unresolved peer cannot
//     be framed, and the retransmit timer is what sends it. No queue;
//   * demultiplexing by four-tuple, including two connections from the
//     same peer to the same port, which is the case a table keyed on
//     anything less would get wrong;
//   * a segment for no connection gets a RST, and a RST for no
//     connection does not (or two hosts trade them forever);
//   * a full-duplex transfer and an orderly close, end to end.
//
// Scripted clock throughout: no sockets, no device, no wall clock.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
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

@ mac_a → i { ^ 2199023255553 }  // 02:00:00:00:00:01

@ mac_b → i { ^ 2199023255554 }  // 02:00:00:00:00:02

@ ip_a → i { ^ ( ipv4_make 10 0 0 1 ) }

@ ip_b → i { ^ ( ipv4_make 10 0 0 2 ) }

@ mask24 → i { ^ ( ipv4_make 255 255 255 0 ) }

@ ip_gw → i { ^ ( ipv4_make 10 0 0 254 ) }

: ~ i g_fail 0

@ pb s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `ok` `FAIL` )
    ( nurl_print `\n` )
    ? ! ok { = g_fail + g_fail 1 } {}
}

// Deliver every frame sitting in `wire` to `dst`, collecting whatever
// it answers into `back`. One frame at a time, which is what a device
// does — the buffer carries its own boundaries (net/pktbuf.nu), so
// nothing here has to re-parse a header to find out where a frame ends.
@ deliver_all * TcpStack dst * PktBuf wire i now * PktBuf back → i {
    : i n ( pktbuf_count wire )
    : ~ i k 0
    ~ < k n {
        : ( Vec u ) f ( vec_new [u] )
        ( pktbuf_copy_to f wire k )
        : TRx r ( tstack_rx dst f now back )
        ( vec_free [u] f )
        = k + k 1
    }
    ^ n
}

// Run the two stacks against each other until neither has anything to
// say, or `rounds` is up. Returns how many frames crossed.
//
// CONSUMES `from_a`: it becomes the first wire and is freed with every
// other buffer the exchange produces. Vec is outside auto-drop
// (docs/MEMORY.md §7.4), so saying who frees what is the whole
// contract, and a caller that also freed it would double-free.
@ settle * TcpStack a * TcpStack b * PktBuf from_a i now i rounds → i {
    : ~ i crossed 0
    : ~ * PktBuf wire from_a
    : ~ i side 0
    : ~ i k 0
    ~ && < k rounds > ( pktbuf_count wire ) 0 {
        : *PktBuf back ( pktbuf_new )
        : i n ? == side 0 ( deliver_all b wire now back ) ( deliver_all a wire now back )
        = crossed + crossed n
        ( pktbuf_free wire )
        = wire back
        = side ? == side 0 1 0
        = k + k 1
    }
    ( pktbuf_free wire )
    ^ crossed
}

@ main → i {
    : *NetStack na ( stack_new ( mac_a ) ( ip_a ) ( mask24 ) ( ip_gw ) )
    : *NetStack nb ( stack_new ( mac_b ) ( ip_b ) ( mask24 ) ( ip_gw ) )
    : *TcpStack a ( tstack_new na 1000 )
    : *TcpStack b ( tstack_new nb 500000 )

    // ── B listens ────────────────────────────────────────────────
    : i lst ( tstack_listen b ( ip_b ) 80 4 )
    ( pb `listener created: ` >= lst 0 )
    ( pb `nothing pending yet: ` == 0 ( tstack_pending_count b lst ) )

    // ── A connects: the first SYN cannot be framed ───────────────
    // A has never spoken to B, so ARP has not resolved. What goes on
    // the wire is an ARP request, NOT the SYN — and the connection is
    // nonetheless open, waiting on its own retransmit timer.
    : *PktBuf w1 ( pktbuf_new )
    : i ca ( tstack_connect a ( ip_b ) 80 0 1000 w1 )
    ( pb `connection allocated: ` >= ca 0 )
    ( pb `A is in SYN_SENT: ` == ( tstack_conn_state a ca ) ( tcp_syn_sent ) )
    ( pb `first frame out is ARP, not the SYN: ` && == ( pktbuf_count w1 ) 1 == ( pktbuf_len w1 0 ) 42 )
    ( pb `B has still seen nothing: ` == 0 ( tstack_pending_count b lst ) )

    // ARP resolves.
    ( settle a b w1 1000 4 )
    ( pb `A resolved B's MAC: ` ?? ( arp_cache_lookup . na arp ( ip_b ) 1000 ) { T m → == m ( mac_b ) F → F } )

    // The retransmit timer sends the SYN that ARP held up. This is the
    // whole argument for not queueing it: TCP already owns this timer.
    : *PktBuf w2 ( pktbuf_new )
    ( tstack_tick a 2100 w2 )
    ( pb `the RTO resent the SYN: ` > ( pktbuf_count w2 ) 0 )
    ( settle a b w2 2100 6 )

    ( pb `A is ESTABLISHED: ` == ( tstack_conn_state a ca ) ( tcp_established ) )
    ( pb `B queued a connection: ` == 1 ( tstack_pending_count b lst ) )
    : i cb ( tstack_accept b lst )
    ( pb `B accepted it: ` >= cb 0 )
    ( pb `and it is ESTABLISHED: ` == ( tstack_conn_state b cb ) ( tcp_established ) )
    ( pb `accept consumed the queue entry: ` == 0 ( tstack_pending_count b lst ) )
    ( pb `the listener is still listening: ` >= ( tstack_listen b ( ip_b ) 80 4 ) 0 )
    ( pb `B sees A's address: ` == ( tstack_conn_peer_ip b cb ) ( ip_a ) )
    ( pb `B sees A's port: ` == ( tstack_conn_peer_port b cb ) ( tstack_conn_local_port a ca ) )

    // ── data, both ways ──────────────────────────────────────────
    : ( Vec u ) msg ( vec_new [u] )
    ( bytes_extend_str msg `GET /unikernel HTTP/1.0` )
    : *PktBuf w3 ( pktbuf_new )
    : i wrote ( tstack_write a ca msg 0 ( vec_len [u] msg ) 3000 w3 )
    ( pb `A queued the request: ` == wrote ( vec_len [u] msg ) )
    ( settle a b w3 3000 6 )

    : ( Vec u ) got ( vec_new [u] )
    : i nread ( tstack_read b cb got ( vec_len [u] msg ) )
    ( pb `B read the whole request: ` == nread ( vec_len [u] msg ) )
    ( pb `and the bytes match: ` ( bytes_eq got msg ) )

    : ( Vec u ) reply ( vec_new [u] )
    ( bytes_extend_str reply `HTTP/1.0 200 OK` )
    : *PktBuf w4 ( pktbuf_new )
    ( tstack_write b cb reply 0 ( vec_len [u] reply ) 3100 w4 )
    ( settle b a w4 3100 6 )
    : ( Vec u ) got2 ( vec_new [u] )
    : i nread2 ( tstack_read a ca got2 ( vec_len [u] reply ) )
    ( pb `A read the whole reply: ` == nread2 ( vec_len [u] reply ) )
    ( pb `and those bytes match too: ` ( bytes_eq got2 reply ) )

    // ── a second connection from the same peer to the same port ──
    // The case a table keyed on anything less than the four-tuple gets
    // wrong: same source address, same destination port, different
    // source port.
    : *PktBuf w5 ( pktbuf_new )
    : i ca2 ( tstack_connect a ( ip_b ) 80 0 4000 w5 )
    ( settle a b w5 4000 8 )
    ( pb `the second connection is ESTABLISHED: ` == ( tstack_conn_state a ca2 ) ( tcp_established ) )
    ( pb `it is a different connection: ` != ca2 ca )
    ( pb `with a different local port: ` != ( tstack_conn_local_port a ca2 ) ( tstack_conn_local_port a ca ) )
    ( pb `B queued the second one: ` == 1 ( tstack_pending_count b lst ) )
    : i cb2 ( tstack_accept b lst )
    ( pb `and it is not the first: ` != cb2 cb )
    ( pb `the first is still ESTABLISHED: ` == ( tstack_conn_state b cb ) ( tcp_established ) )

    // ── a segment for nothing gets a RST ─────────────────────────
    : *PktBuf w6 ( pktbuf_new )
    : i cx ( tstack_connect a ( ip_b ) 9999 0 5000 w6 )
    : *PktBuf back ( pktbuf_new )
    ( deliver_all b w6 5000 back )
    ( pb `a SYN to a closed port is refused: ` > ( pktbuf_count back ) 0 )
    ( pb `B counted it: ` == 1 . b no_conn )
    // …and A's connection dies on the RST rather than retrying forever.
    : *PktBuf w7 ( pktbuf_new )
    ( deliver_all a back 5000 w7 )
    ( pb `A gave up on the refused connection: ` != ( tstack_conn_state a cx ) ( tcp_syn_sent ) )
    ( pb `the RST drew no reply: ` == 0 ( pktbuf_count w7 ) )

    // ── orderly close ────────────────────────────────────────────
    : *PktBuf w8 ( pktbuf_new )
    ( tstack_close a ca 6000 w8 )
    ( settle a b w8 6000 8 )
    ( pb `B saw the FIN: ` || == ( tstack_conn_state b cb ) ( tcp_close_wait ) == ( tstack_conn_state b cb ) ( tcp_closed ) )
    : *PktBuf w9 ( pktbuf_new )
    ( tstack_close b cb 6100 w9 )
    ( settle b a w9 6100 8 )
    ( pb `A reached TIME_WAIT: ` || == ( tstack_conn_state a ca ) ( tcp_time_wait ) == ( tstack_conn_state a ca ) ( tcp_closed ) )
    // 2MSL later the connection is reclaimed by the timer, not by a
    // caller remembering to.
    : *PktBuf w10 ( pktbuf_new )
    ( tstack_tick a + 6100 ( tcp_2msl_ms ) w10 )
    ( pb `TIME_WAIT expired into CLOSED: ` == ( tstack_conn_state a ca ) ( tcp_closed ) )
    ( pb `and the slot is reusable: ` ! ( tstack_conn_live a ca ( tstack_conn_gen a ca ) ) )

    // ── the event loop's question ────────────────────────────────
    // With a connection still open and a retransmit armed, "how long
    // may I sleep?" must have an answer; with nothing armed it must
    // say so rather than return 0 and spin.
    : i tmo ( tstack_next_timeout b 7000 )
    ( pb `next timeout is a real deadline or none: ` >= tmo -1 )

    // ── teardown ─────────────────────────────────────────────────
    // Everything here is a manually-managed handle. This stack is bound
    // for a unikernel, where there is no process exit to sweep up after
    // a leak, so it is held leak-clean from its first commit — the CI
    // leak gate runs this test under LSan.
    //
    // The `w*` buffers handed to `settle` are gone already: it consumes
    // its wire. The rest are ours.
    ( pktbuf_free w6 ) ( pktbuf_free w7 ) ( pktbuf_free w10 )
    ( pktbuf_free back )
    ( vec_free [u] msg ) ( vec_free [u] got )
    ( vec_free [u] reply ) ( vec_free [u] got2 )
    ( tstack_free a )
    ( tstack_free b )
    ( stack_free na )
    ( stack_free nb )

    ( nurl_print ? == g_fail 0 `net_tcpstack: all ok\n` `net_tcpstack: FAILURES\n` )
    ^ ? == g_fail 0 0 1
}
