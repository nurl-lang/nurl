// net_socket.nu — Phase A4.1: BSD socket semantics over the sans-IO
// stack, with no operating system anywhere in the picture.
//
// One address space, one stack, one loopback "device" — the frames a
// stack emits are the frames it receives, which is all 127.0.0.1 ever
// was. A server and a client live in the same fd table and talk to
// each other through real Ethernet frames with real checksums, under a
// clock the test supplies.
//
// What is asserted is what this layer owns and the layers below do
// not:
//
//   * the fd table: small integers, an out-of-band error per fd, and
//     an operation on a closed fd refused rather than misdirected;
//   * bind semantics — an ephemeral port that can be read back, and a
//     second listener on a taken port refused with ADDRINUSE;
//   * the errno seam: `again` for "not yet", 0 from read for the end
//     of the stream, `closed` for a peer that reset;
//   * readiness, answered without performing the operation, and
//     answering TRUE for a dead fd so a waiter wakes to find out;
//   * that nothing is queued behind ARP — the SYN waits for TCP's own
//     retransmit timer — and that seeding our own address removes that
//     wait entirely.
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
$ `stdlib/net/socket.nu`

@ lo_mac → i { ^ 2199023255553 }  // 02:00:00:00:00:01

@ lo_ip → i { ^ ( ipv4_make 127 0 0 1 ) }

@ lo_mask → i { ^ ( ipv4_make 255 0 0 0 ) }

: ~ i g_fail 0

@ pb s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `ok` `FAIL` )
    ( nurl_print `\n` )
    ? ! ok { = g_fail + g_fail 1 } {}
}

// Run the loopback until the stack has nothing more to say, or
// `rounds` is up. This is the whole event loop of a single-threaded
// driver: deliver what is queued, then deliver what that produced.
@ pump * SockTab st i now i rounds → i {
    : ~ i total 0
    : ~ i k 0
    ~ && < k rounds > ( sock_pending_frames st ) 0 {
        = total + total ( sock_loopback st now )
        = k + k 1
    }
    ^ total
}

@ again → i { ^ - 0 ( sock_err_again ) }

@ main → i {
    : *NetStack net ( stack_new ( lo_mac ) ( lo_ip ) ( lo_mask ) 0 )
    : *TcpStack ts ( tstack_new net 1000 )
    : *SockTab st ( sock_new ts ( lo_ip ) )
    : ( Vec u ) scratch ( vec_new [u] )

    // ── bind ─────────────────────────────────────────────────────
    : i l0 ( sock_listen st 0 0 4 )
    : i lp ( sock_local_port st l0 )
    ( pb `an ephemeral bind picks a port: ` > lp 0 )
    ( pb `and reports no error: ` == 0 ( sock_err st l0 ) )
    ( pb `the fd is a listener: ` == ( sock_kind st l0 ) ( sock_kind_listener ) )

    : i dup ( sock_listen st 0 lp 4 )
    ( pb `a second listener on that port is refused: ` == ( sock_err st dup ) ( sock_err_addr_in_use ) )
    ( sock_close st dup 0 )

    : i bad ( sock_listen st 0 70000 4 )
    ( pb `an impossible port is a bind error: ` == ( sock_err st bad ) ( sock_err_bind ) )
    ( sock_close st bad 0 )

    ( pb `accept with nothing pending says "again": ` == ( sock_accept st l0 ) ( again ) )
    ( pb `and the listener is not readable: ` ! ( sock_readable st l0 ) )
    ( pb `a listener is never writable: ` ! ( sock_writable st l0 ) )

    // ── connect: ARP first, and nothing is queued behind it ──────
    : i c ( sock_connect st ( lo_ip ) lp 0 1000 )
    ( pb `connect returns an fd: ` > c 0 )
    ( pb `one frame is out — the ARP request, not the SYN: ` && == 1 ( sock_pending_frames st ) == 42 ( pktbuf_len ( sock_out st ) 0 ) )
    ( pb `the connection is pending: ` == ( sock_status st c ) ( sock_conn_pending ) )
    ( pb `a pending connection is not writable: ` ! ( sock_writable st c ) )
    ( pb `writing to it says "again": ` == ( sock_write st c scratch 0 4 1000 ) ( again ) )

    ( pump st 1000 8 )
    ( pb `ARP resolved against ourselves: ` ?? ( arp_cache_lookup . net arp ( lo_ip ) 1000 ) { T m → == m ( lo_mac ) F → F } )
    ( pb `but the SYN still has not gone: ` == ( sock_status st c ) ( sock_conn_pending ) )
    ( pb `nothing was queued waiting for it: ` == 0 ( sock_pending_frames st ) )

    // TCP's retransmit timer is what sends it — the reason the layer
    // below refuses to grow a second queue with its own drop policy.
    ( sock_tick st 2100 )
    ( pb `the RTO sent the SYN: ` > ( sock_pending_frames st ) 0 )
    ( pump st 2100 12 )
    ( pb `the connection is established: ` == ( sock_status st c ) ( sock_conn_ready ) )
    ( pb `and now it is writable: ` ( sock_writable st c ) )
    ( pb `the listener has something to accept: ` ( sock_readable st l0 ) )

    : i s0 ( sock_accept st l0 )
    ( pb `accept produced a connection fd: ` > s0 0 )
    ( pb `it is a connection, not a listener: ` == ( sock_kind st s0 ) ( sock_kind_conn ) )
    ( pb `the server sees the client's port: ` == ( sock_peer_port st s0 ) ( sock_local_port st c ) )
    ( pb `the client sees the server's port: ` == ( sock_peer_port st c ) lp )
    ( pb `the listener is back to empty: ` == ( sock_accept st l0 ) ( again ) )

    // ── data ─────────────────────────────────────────────────────
    ( pb `a fresh connection has nothing to read: ` == ( sock_read st s0 scratch 8 ) ( again ) )
    ( pb `and is not readable: ` ! ( sock_readable st s0 ) )

    : ( Vec u ) req ( vec_new [u] )
    ( bytes_extend_str req `GET /unikernel HTTP/1.0\r\n\r\n` )
    : i wn ( sock_write st c req 0 ( vec_len [u] req ) 3000 )
    ( pb `the client wrote the whole request: ` == wn ( vec_len [u] req ) )
    ( pump st 3000 12 )
    ( pb `the server can read it: ` ( sock_readable st s0 ) )

    : ( Vec u ) got ( vec_new [u] )
    : i rn ( sock_read st s0 got ( vec_len [u] req ) )
    ( pb `and reads exactly what was sent: ` && == rn ( vec_len [u] req ) ( bytes_eq got req ) )
    ( pb `after which there is nothing left: ` == ( sock_read st s0 got 8 ) ( again ) )
    ( pb `the send queue drained: ` == 0 ( sock_send_queue st c ) )

    : ( Vec u ) resp ( vec_new [u] )
    ( bytes_extend_str resp `HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nhi` )
    ( sock_write st s0 resp 0 ( vec_len [u] resp ) 3100 )
    ( pump st 3100 12 )
    : ( Vec u ) got2 ( vec_new [u] )
    : i rn2 ( sock_read st c got2 ( vec_len [u] resp ) )
    ( pb `the client reads the response: ` && == rn2 ( vec_len [u] resp ) ( bytes_eq got2 resp ) )

    // A short read is a read, not an error: ask for less than is
    // there and the rest stays queued.
    ( sock_write st s0 resp 0 8 3200 )
    ( pump st 3200 12 )
    : ( Vec u ) part ( vec_new [u] )
    ( pb `a short read takes what it asked for: ` == 3 ( sock_read st c part 3 ) )
    ( pb `and the rest is still there: ` == 5 ( sock_read st c part 99 ) )

    // ── end of stream ────────────────────────────────────────────
    ( sock_close st s0 3300 )
    ( pump st 3300 12 )
    ( pb `the client is readable at EOF: ` ( sock_readable st c ) )
    ( pb `read answers 0, which is not an error: ` == 0 ( sock_read st c got2 64 ) )
    ( pb `and keeps answering 0: ` == 0 ( sock_read st c got2 64 ) )
    ( pb `the connection is still alive for writing: ` != ( sock_state st c ) ( tcp_closed ) )
    ( sock_close st c 3400 )
    ( pump st 3400 12 )
    ( pb `an operation on a closed fd is refused: ` == ( sock_read st c got2 8 ) - 0 ( sock_err_other ) )

    // ── a peer that resets ───────────────────────────────────────
    : i c2 ( sock_connect st ( lo_ip ) lp 0 4000 )
    ( pump st 4000 12 )
    ( pb `the second connection is established: ` == ( sock_status st c2 ) ( sock_conn_ready ) )
    : i s2 ( sock_accept st l0 )
    ( pb `and was accepted: ` > s2 0 )

    ( sock_abort st s2 4100 )
    ( pump st 4100 12 )
    ( pb `the reset peer reads as closed: ` == ( sock_read st c2 got2 8 ) - 0 ( sock_err_closed ) )
    ( pb `the error is on the fd too: ` == ( sock_err st c2 ) ( sock_err_closed ) )
    ( pb `a reset connection is readable — the waiter must wake: ` ( sock_readable st c2 ) )
    ( pb `writing to it fails, and not with "again": ` == ( sock_write st c2 req 0 4 4100 ) - 0 ( sock_err_closed ) )
    ( sock_close st c2 4200 )

    // ── backlog, and two connections at once ─────────────────────
    : i c3 ( sock_connect st ( lo_ip ) lp 0 5000 )
    : i c4 ( sock_connect st ( lo_ip ) lp 0 5000 )
    ( pump st 5000 24 )
    ( pb `both connections came up: ` && == ( sock_status st c3 ) ( sock_conn_ready ) == ( sock_status st c4 ) ( sock_conn_ready ) )
    : i s3 ( sock_accept st l0 )
    : i s4 ( sock_accept st l0 )
    ( pb `both were accepted, as distinct fds: ` && && > s3 0 > s4 0 != s3 s4 )
    ( pb `with distinct peer ports: ` != ( sock_peer_port st s3 ) ( sock_peer_port st s4 ) )

    // The four-tuple is what demultiplexes: two connections from the
    // same address to the same port must not cross their streams.
    : ( Vec u ) m3 ( vec_new [u] )
    ( bytes_extend_str m3 `three` )
    : ( Vec u ) m4 ( vec_new [u] )
    ( bytes_extend_str m4 `four` )
    ( sock_write st c3 m3 0 5 5100 )
    ( sock_write st c4 m4 0 4 5100 )
    ( pump st 5100 24 )
    : ( Vec u ) r3 ( vec_new [u] )
    : ( Vec u ) r4 ( vec_new [u] )
    : i n3 ( sock_read st s3 r3 32 )
    : i n4 ( sock_read st s4 r4 32 )
    // s3 and s4 arrived in accept order, which is connect order.
    ( pb `each stream landed on its own connection: ` && && == n3 5 == n4 4 && ( bytes_eq r3 m3 ) ( bytes_eq r4 m4 ) )

    // ── shutdown wakes an accept ─────────────────────────────────
    ( sock_shutdown st l0 )
    ( pb `accept on a shut listener fails rather than waiting: ` == ( sock_accept st l0 ) - 0 ( sock_err_accept ) )
    ( pb `and a shut fd reports itself readable: ` ( sock_readable st l0 ) )

    // ── reference counting ───────────────────────────────────────
    ( sock_ref st s3 )
    ( sock_close st s3 6000 )
    ( pb `a referenced fd survives one close: ` == ( sock_kind st s3 ) ( sock_kind_conn ) )
    ( sock_close st s3 6000 )
    ( pb `and is gone after the second: ` == ( sock_kind st s3 ) ( sock_kind_free ) )

    // ── a stack that knows its own address ───────────────────────
    // Everything above resolved 127.0.0.1 by asking the wire for it and
    // waiting a retransmit timeout for the answer. An interface knows
    // its own MAC without asking, and a second stack — cache empty,
    // seeded instead — completes a connect in the same millisecond.
    : *NetStack net2 ( stack_new ( lo_mac ) ( lo_ip ) ( lo_mask ) 0 )
    : *TcpStack ts2 ( tstack_new net2 7000 )
    : *SockTab st2 ( sock_new ts2 ( lo_ip ) )
    ( sock_seed_self st2 7000 )
    : i l2 ( sock_listen st2 0 8443 4 )
    : i k2 ( sock_connect st2 ( lo_ip ) 8443 0 7000 )
    ( pb `the seeded stack sends the SYN, not an ARP request: ` > ( pktbuf_len ( sock_out st2 ) 0 ) 42 )
    ( pump st2 7000 12 )
    ( pb `and connects with no retransmit at all: ` == ( sock_status st2 k2 ) ( sock_conn_ready ) )
    : i a2 ( sock_accept st2 l2 )
    ( pb `the far end accepted it: ` > a2 0 )
    ( sock_close st2 a2 7000 ) ( sock_close st2 k2 7000 ) ( sock_close st2 l2 7000 )
    ( pump st2 7000 12 )
    ( sock_free st2 )
    ( tstack_free ts2 )
    ( stack_free net2 )

    // ── teardown ─────────────────────────────────────────────────
    // Every handle here is manually managed and this stack is bound
    // for a machine with no process exit to sweep up after it, so the
    // test is held leak-clean from its first commit (CI runs it under
    // LSan).
    ( sock_close st s4 6100 )
    ( sock_close st c3 6100 )
    ( sock_close st c4 6100 )
    ( sock_close st l0 6100 )
    ( pump st 6100 24 )
    ( sock_tick st + 6100 ( tcp_2msl_ms ) )
    ( pb `no fd is left open: ` == 0 ( sock_open_count st ) )

    ( vec_free [u] scratch )
    ( vec_free [u] req ) ( vec_free [u] got ) ( vec_free [u] got2 )
    ( vec_free [u] resp ) ( vec_free [u] part )
    ( vec_free [u] m3 ) ( vec_free [u] m4 )
    ( vec_free [u] r3 ) ( vec_free [u] r4 )
    ( sock_free st )
    ( tstack_free ts )
    ( stack_free net )

    ( nurl_print ? == g_fail 0 `net_socket: all ok\n` `net_socket: FAILURES\n` )
    ^ ? == g_fail 0 0 1
}
