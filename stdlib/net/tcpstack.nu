// stdlib/net/tcpstack.nu — TCP over the sans-IO IPv4 stack.
//
// net/tcp.nu owns one connection's state machine and speaks in
// segments. net/stack.nu owns Ethernet, ARP, routing and IPv4 and
// speaks in frames. This is the layer between them: the table that says
// which connection a segment belongs to, and the code that wraps a
// segment in a datagram and hands it down.
//
// It is still sans-IO. Frames in, frames out, `now` supplied by the
// caller:
//
//     ( tstack_rx  ts frame now out )  → TRx
//     ( tstack_tick ts now out )       → i    (segments the timers produced)
//
// Nothing here allocates a socket, blocks, or reads a clock — the same
// property that lets the whole stack run under a scripted clock on the
// host also lets it run unmodified inside a unikernel. The socket shims
// (phase A4) sit ON TOP of this and are where blocking appears.
//
// WHAT THIS LAYER ADDS OVER tcp.nu
//
//   * demultiplexing. A segment belongs to the connection whose
//     four-tuple it matches; failing that, to a listener on its
//     destination port; failing that, to nothing — and a segment that
//     matches nothing gets a RST, because silence there is how a
//     half-open peer is left retransmitting into a void.
//   * the passive open. `tcp.nu` has a LISTEN state but no notion of
//     "a listener spawns connections": a SYN to a listening port
//     creates a NEW connection in SYN_RCVD and leaves the listener
//     listening.
//   * addressing. A Tcb emits segments; segments need a source and
//     destination address to be checksummed at all, so the four-tuple
//     lives here rather than in the state machine.
//   * the ARP wait. The first segment to a new peer may leave before
//     the peer's MAC is known. It is not queued — TCP already owns a
//     retransmit timer, and using it is both less code and more honest
//     than a second queue with its own drop policy.
//
// MEMORY. A `TcpStack` (from `tstack_new`) is a handle (rcbox): every
// copy is the same table, and its last owner releases it — every
// connection, listener and Tcb in it, and its own owner's share of the
// NetStack it was given. `tstack_free` is an early release (optional).
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/ipv4.nu`
$ `stdlib/net/tcpseg.nu`
$ `stdlib/net/tcp.nu`
$ `stdlib/net/pktbuf.nu`
$ `stdlib/net/stack.nu`
$ `stdlib/core/rcbox.nu`

// ── rx outcomes ──────────────────────────────────────────────────
//
// What the caller above (the socket layer) needs to know after a frame
// went in. Anything not TCP-shaped is reported as `trx_other` with the
// underlying RxResult kind, so a caller can still run UDP and ICMP
// through the same door.

@ trx_other → i { ^ 0 }  // not TCP — `kind` carries stack.nu's verdict

@ trx_none → i { ^ 1 }  // TCP, consumed, nothing for the caller yet

@ trx_data → i { ^ 2 }  // a connection has readable bytes

@ trx_accepted → i { ^ 3 }  // a listener produced a new connection

@ trx_closed → i { ^ 4 }  // a connection reached CLOSED

@ trx_reset → i { ^ 5 }  // the peer reset us

@ trx_no_conn → i { ^ 6 }  // matched nothing; a RST went out

: TRx {
    i result  // trx_*
    i kind  // stack.nu's RxResult kind when result == trx_other
    i conn  // index into the connection table, or -1
    i emitted  // bytes appended to `out`
    // The verdict for everything that was not TCP, passed through
    // intact. A caller that also speaks UDP would otherwise have to
    // parse the frame a second time to learn what this layer already
    // knows — and the two parses would be free to disagree.
    i src_ip
    i dst_ip
    i src_port
    i dst_port
    i payload_off  // into the frame handed to tstack_rx
    i payload_len
}

@ __trx i result i kind i conn i emitted → TRx {
    ^ @ TRx { result kind conn emitted 0 0 0 0 0 0 }
}

@ __trx_other RxResult rr → TRx {
    ^ @ TRx { ( trx_other ) . rr kind -1 . rr emitted . rr src_ip . rr dst_ip
        . rr src_port . rr dst_port . rr payload_off . rr payload_len }
}

// ── the connection table ─────────────────────────────────────────
//
// A flat vector with a free list. Connections are identified to the
// caller by INDEX, not by pointer: an index stays valid across a
// reallocation and can cross the FFI boundary as an integer, which is
// what the socket shims need. A generation counter makes a stale index
// detectable rather than silently aliasing a recycled slot — the
// use-after-close bug this table would otherwise invite.

: TConn {
    Tcb tcb
    i local_ip
    i local_port
    i remote_ip
    i remote_port
    i gen  // bumped on every reuse of this slot
    b used
    b passive  // arrived through a listener
    i listener  // index of the listener that spawned it, or -1
}

: TListener {
    i local_ip
    i local_port
    i backlog
    ( Vec i ) pending  // connection indices waiting to be accepted
    b used
    i gen
}

: TcpStackImpl {
    NetStack net
    ( Vec i ) conns  // *TConn, as integers — NURL has no Vec of pointers
    ( Vec i ) listeners  // *TListener, likewise
    i iss  // initial send sequence, advanced per connection
    i ephemeral  // next ephemeral local port
    i rst_sent
    i no_conn
}

// A TcpStack is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: TcpStack { s ctl }

@ TcpStack_share TcpStack h → TcpStack { ^ @ TcpStack { # s ( rcbox_share # i . h ctl ) } }

@ TcpStack_drop sink TcpStack h → v {
    ( mem_forget h )
    ( rcbox_release [TcpStackImpl] # i . h ctl )
}

@ __TcpStack_ptr TcpStack h → *TcpStackImpl { ^ ( rcbox_ptr [TcpStackImpl] # i . h ctl ) }

// The connection and listener blocks are raw memory (the table keeps
// them as integers): releasing them, and the Tcb each connection holds,
// is the table's own drop. Its NetStack and vectors are dropped after.
% Drop TcpStackImpl {
    @ drop TcpStackImpl ts → v {
        : i n ( vec_len [i] . ts conns )
        : ~ i k 0
        ~ < k n {
            : *TConn c # *TConn ?? ( vec_get [i] . ts conns k ) { T p → p F → 0 }
            ? != # i c 0 {
                // A released slot holds a null Tcb; letting go of one is
                // a no-op, so every slot is released the same way.
                ( tcb_free . c tcb )
                ( nurl_free # s c )
            } {}
            = k + k 1
        }
        : i m ( vec_len [i] . ts listeners )
        : ~ i j 0
        ~ < j m {
            : *TListener l # *TListener ?? ( vec_get [i] . ts listeners j ) { T p → p F → 0 }
            ? != # i l 0 {
                ( vec_free [i] . l pending )
                ( nurl_free # s l )
            } {}
            = j + j 1
        }
    }
}

@ __tconn_ptr * TcpStackImpl ts i idx → *TConn {
    ^ # *TConn ?? ( vec_get [i] . ts conns idx ) { T p → p F → 0 }
}

@ __tlisten_ptr * TcpStackImpl ts i idx → *TListener {
    ^ # *TListener ?? ( vec_get [i] . ts listeners idx ) { T p → p F → 0 }
}

@ tstack_new NetStack net i iss_seed → TcpStack {
    : i ts__box ( rcbox_zero [TcpStackImpl] )
    : *TcpStackImpl ts ( rcbox_ptr [TcpStackImpl] ts__box )
    // Another owner of the stack, not a view of the caller's: this table
    // sends through it for as long as the table lives.
    = . ts net ( NetStack_share net )
    = . ts conns ( vec_new [i] )
    = . ts listeners ( vec_new [i] )
    = . ts iss iss_seed
    = . ts ephemeral 49152
    = . ts rst_sent 0
    = . ts no_conn 0
    ^ @ TcpStack { # s ts__box }
}

// Let go of `ts` now rather than at the end of its owner's scope.
@ tstack_free sink TcpStack ts → v {}

// The IPv4 stack this table sends through, lent: the socket layer
// routes UDP and seeds ARP through the same one.
@ tstack_net TcpStack ts__h → NetStack {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    ^ . ts net
}

// Segments that matched no connection, and the RSTs sent for them.
@ tstack_no_conn TcpStack ts__h → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    ^ . ts no_conn
}

@ tstack_rst_sent TcpStack ts__h → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    ^ . ts rst_sent
}

// Take a free slot, or grow the table. The freed slots keep their
// allocation so an index that was handed out and closed can still be
// looked up and rejected by generation, rather than pointing at
// whatever was allocated next.
@ __conn_alloc * TcpStackImpl ts → i {
    : i n ( vec_len [i] . ts conns )
    : ~ i k 0
    ~ < k n {
        : *TConn c ( __tconn_ptr ts k )
        ? ! . c used {
            = . c used T
            = . c gen + . c gen 1
            = . c tcb ( tcb_new )
            = . c listener -1
            = . c passive F
            ^ k
        } {}
        = k + k 1
    }
    : *TConn c # *TConn ( nurl_alloc Z TConn )
    = . c used T
    = . c gen 1
    = . c tcb ( tcb_new )
    = . c listener -1
    = . c passive F
    ( vec_push [i] . ts conns # i c )
    ^ n
}

@ __conn_release * TcpStackImpl ts i idx → v {
    : *TConn c ( __tconn_ptr ts idx )
    ? == # i c 0 { ^ } {}
    ? ! . c used { ^ } {}
    // The slot gives its Tcb up (dropped here) and keeps a null one.
    : Tcb gone . c tcb
    ( mem_take gone )
    = . c tcb @ Tcb { # s 0 }
    = . c used F
}

// Generation-checked accessor: the socket layer holds (index, gen)
// pairs and every lookup goes through here, so a read on a closed
// connection is an error rather than a read of the next connection to
// take that slot.
@ tstack_conn_live TcpStack ts__h i idx i gen → b {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    ? || < idx 0 >= idx ( vec_len [i] . ts conns ) { ^ F } {}
    : *TConn c ( __tconn_ptr ts idx )
    ? == # i c 0 { ^ F } {}
    ^ && . c used == . c gen gen
}

@ tstack_conn_gen TcpStack ts__h i idx → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : *TConn c ( __tconn_ptr ts idx )
    ? == # i c 0 { ^ 0 } {}
    ^ . c gen
}

@ tstack_conn_tcb TcpStack ts__h i idx → Tcb {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : *TConn c ( __tconn_ptr ts idx )
    ? == # i c 0 { ^ @ Tcb { # s 0 } } {}
    ^ . c tcb
}

@ tstack_conn_state TcpStack ts__h i idx → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : *TConn c ( __tconn_ptr ts idx )
    ? == # i c 0 { ^ ( tcp_closed ) } {}
    ? ! . c used { ^ ( tcp_closed ) } {}
    ^ ( tcb_state . c tcb )
}

@ tstack_conn_peer_ip TcpStack ts__h i idx → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : *TConn c ( __tconn_ptr ts idx )
    ? == # i c 0 { ^ 0 } {}
    ^ . c remote_ip
}

@ tstack_conn_peer_port TcpStack ts__h i idx → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : *TConn c ( __tconn_ptr ts idx )
    ? == # i c 0 { ^ 0 } {}
    ^ . c remote_port
}

@ tstack_conn_local_port TcpStack ts__h i idx → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : *TConn c ( __tconn_ptr ts idx )
    ? == # i c 0 { ^ 0 } {}
    ^ . c local_port
}

// ── listeners ────────────────────────────────────────────────────

@ tstack_listen TcpStack ts__h i local_ip i port i backlog → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : i n ( vec_len [i] . ts listeners )
    : ~ i slot -1
    : ~ i k 0
    ~ < k n {
        : *TListener l ( __tlisten_ptr ts k )
        ? ! . l used { = slot k = k n } { = k + k 1 }
    }
    ? < slot 0 {
        : *TListener l # *TListener ( nurl_alloc Z TListener )
        = . l pending ( vec_new [i] )
        = . l gen 0
        ( vec_push [i] . ts listeners # i l )
        = slot n
    } {}
    : *TListener l ( __tlisten_ptr ts slot )
    = . l local_ip local_ip
    = . l local_port port
    = . l backlog ? > backlog 0 backlog 16
    = . l used T
    = . l gen + . l gen 1
    ( vec_clear [i] . l pending )
    ^ slot
}

@ tstack_listener_close TcpStack ts__h i idx → v {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : *TListener l ( __tlisten_ptr ts idx )
    ? == # i l 0 { ^ } {}
    ( vec_clear [i] . l pending )
    = . l used F
}

// Hand back the next connection this listener has completed, or -1.
// A connection is only offered once — it moves out of `pending` here.
@ tstack_accept TcpStack ts__h i idx → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : *TListener l ( __tlisten_ptr ts idx )
    ? == # i l 0 { ^ -1 } {}
    ? ! . l used { ^ -1 } {}
    ? == 0 ( vec_len [i] . l pending ) { ^ -1 } {}
    : i c ?? ( vec_get [i] . l pending 0 ) { T v → v F → -1 }
    ( vec_remove [i] . l pending 0 )
    ^ c
}

@ tstack_pending_count TcpStack ts__h i idx → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : *TListener l ( __tlisten_ptr ts idx )
    ? == # i l 0 { ^ 0 } {}
    ^ ( vec_len [i] . l pending )
}

// ── sending ──────────────────────────────────────────────────────

// Drain a connection's PktBuf into `out` as IPv4 datagrams — one
// datagram per SEGMENT, which is why PktBuf carries end offsets at all:
// TCP has no length field of its own and concatenating segments into
// one buffer is irreversible.
@ __flush * TcpStackImpl ts i idx PktBuf o i now PktBuf out → i {
    : *TConn c ( __tconn_ptr ts idx )
    : i nseg ( pktbuf_count o )
    : ~ i emitted 0
    : ~ i k 0
    ~ < k nseg {
        : i s ( pktbuf_start o k )
        : i n ( pktbuf_len o k )
        // Straight from the PktBuf buffer — no temporary Vec, because
        // the segment is already sitting there as a range.
        // FROM the address this connection was checksummed with. A
        // connection to 127.0.0.1 is sourced from 127.0.0.1 even on a
        // machine whose interface has an address of its own; sending it
        // from the interface's address instead makes the pseudo-header
        // disagree with the receiver's and the segment vanishes.
        : TxResult r ( stack_tx_ip4 . ts net . c local_ip . c remote_ip ( ip_proto_tcp ) ( pktbuf_bytes o ) s n now out )
        = emitted + emitted . r emitted
        = k + k 1
    }
    ( pktbuf_clear o )
    ^ emitted
}

// ── receive ──────────────────────────────────────────────────────

@ __find_conn * TcpStackImpl ts i local_ip i local_port i remote_ip i remote_port → i {
    : i n ( vec_len [i] . ts conns )
    : ~ i k 0
    ~ < k n {
        : *TConn c ( __tconn_ptr ts k )
        ? && . c used && == . c local_port local_port && == . c remote_port remote_port && == . c remote_ip remote_ip || == . c local_ip local_ip == . c local_ip 0 {
            ^ k
        } {}
        = k + k 1
    }
    ^ -1
}

@ __find_listener * TcpStackImpl ts i local_ip i port → i {
    : i n ( vec_len [i] . ts listeners )
    : ~ i k 0
    ~ < k n {
        : *TListener l ( __tlisten_ptr ts k )
        ? && . l used && == . l local_port port || == . l local_ip local_ip == . l local_ip 0 {
            ^ k
        } {}
        = k + k 1
    }
    ^ -1
}

// RFC 793: a segment that belongs to no connection is answered with a
// RST, unless it IS a RST — which would loop forever between two hosts
// that each think the other is confused.
@ __send_rst * TcpStackImpl ts i src_ip i dst_ip TcpSeg s i now PktBuf out → i {
    ? == & . s flags 4 4 { ^ 0 } {}
    = . ts rst_sent + . ts rst_sent 1
    : ( Vec u ) dg ( vec_new [u] )
    : ( Vec u ) empty ( vec_new [u] )
    // An ACKed segment is refused from its own ACK number and carries no
    // ACK of its own; an unACKed one is refused with ACK = its sequence
    // plus its length, which is what the peer is waiting to hear.
    ? == & . s flags 16 16 {
        ( tcpseg_push dg dst_ip src_ip . s dst_port . s src_port . s ack 0 4 0 0 -1 empty 0 0 )
    } {
        ( tcpseg_push dg dst_ip src_ip . s dst_port . s src_port 0
        ( seq_add . s seq ( tcpseg_seq_len s ) ) 20 0 0 -1 empty 0 0 )
    }
    // The refusal comes from the address the offending segment was sent
    // TO — including 127.0.0.1, whose RST must not claim to come from
    // the interface.
    : TxResult r ( stack_tx_ip4 . ts net dst_ip src_ip ( ip_proto_tcp ) dg 0 ( vec_len [u] dg ) now out )
    ^ . r emitted
}

// A SYN to a listening port. The listener stays listening; a new
// connection is created in SYN_RCVD and queued for accept.
@ __passive_open * TcpStackImpl ts i lidx i local_ip i local_port TcpSeg s i src_ip i now ( Vec u ) frame PktBuf o PktBuf out → TRx {
    : *TListener l ( __tlisten_ptr ts lidx )
    ? >= ( vec_len [i] . l pending ) . l backlog {
        // The backlog is full. Dropping the SYN is what a listening
        // socket does under load — the peer retransmits, and by then
        // the queue may have drained. Answering RST would tell it the
        // port is closed, which is a different and false thing.
        ^ ( __trx ( trx_none ) 0 -1 0 )
    } {}
    : i idx ( __conn_alloc ts )
    : *TConn c ( __tconn_ptr ts idx )
    = . c local_ip local_ip
    = . c local_port local_port
    = . c remote_ip src_ip
    = . c remote_port . s src_port
    = . c passive T
    = . c listener lidx
    ( tcb_listen . c tcb local_ip local_port )
    // The Tcb keeps its OWN four-tuple — it has to, because that is what
    // the pseudo-header checksum is computed over — and tcb_input can
    // only learn the ports from the segment: a TcpSeg carries no
    // addresses, those live in the IP header this layer already parsed.
    // Filling in TConn's copy and not the Tcb's leaves every segment the
    // connection emits checksummed against 0.0.0.0, which the peer
    // silently drops as corrupt. That is what it did.
    ( tcb_set_remote_ip . c tcb src_ip )
    ( tcb_set_remote_port . c tcb . s src_port )
    ( tcb_set_iss . c tcb ( __next_iss ts ) )
    : i r ( tcb_input . c tcb s frame now o )
    : i emitted ( __flush ts idx o now out )
    ( vec_push [i] . l pending idx )
    ^ ( __trx ( trx_accepted ) 0 idx emitted )
}

@ __next_iss * TcpStackImpl ts → i {
    // A per-connection ISS that advances. RFC 793's clock-driven ISS is
    // about old-duplicate protection across incarnations; TIME_WAIT
    // covers that here, and a monotone step keeps the unit tests
    // reproducible, which a clock-derived value would not.
    = . ts iss ( seq_add . ts iss 64000 )
    ^ . ts iss
}

// Feed one frame in. Non-TCP frames are handed to stack.nu and their
// verdict passed straight through, so a caller can run one loop for
// everything rather than two that disagree about which is authoritative.
@ tstack_rx TcpStack ts__h ( Vec u ) frame i now PktBuf out → TRx {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : RxResult rr ( stack_rx . ts net frame now out )
    ? != . rr kind ( rx_tcp ) { ^ ( __trx_other rr ) } {}
    : TcpSeg s ( tcpseg_parse frame . rr payload_off . rr payload_len . rr src_ip . rr dst_ip )
    ? ! . s valid { ^ ( __trx ( trx_none ) 0 -1 0 ) } {}

    : i idx ( __find_conn ts . rr dst_ip . s dst_port . rr src_ip . s src_port )
    : PktBuf o ( pktbuf_new )
    ? >= idx 0 {
        : *TConn c ( __tconn_ptr ts idx )
        : i before ( tcb_recv_queue_len . c tcb )
        : i r ( tcb_input . c tcb s frame now o )
        : i emitted ( __flush ts idx o now out )
        : i st ( tcb_state . c tcb )
        ? ( tcb_was_reset . c tcb ) {
            ( __conn_release ts idx )
            ^ ( __trx ( trx_reset ) 0 idx emitted )
        } {}
        ? == st ( tcp_closed ) {
            ( __conn_release ts idx )
            ^ ( __trx ( trx_closed ) 0 idx emitted )
        } {}
        ? > ( tcb_recv_queue_len . c tcb ) before {
            ^ ( __trx ( trx_data ) 0 idx emitted )
        } {}
        ^ ( __trx ( trx_none ) 0 idx emitted )
    } {}

    // No connection. A SYN with no ACK may open one; anything else is
    // addressed to a connection that does not exist.
    ? && == & . s flags 2 2 != & . s flags 16 16 {
        : i lidx ( __find_listener ts . rr dst_ip . s dst_port )
        ? >= lidx 0 {
            : TRx res ( __passive_open ts lidx . rr dst_ip . s dst_port s . rr src_ip now frame o out )
            ^ res
        } {}
    } {}
    = . ts no_conn + . ts no_conn 1
    : i em ( __send_rst ts . rr src_ip . rr dst_ip s now out )
    ^ ( __trx ( trx_no_conn ) 0 -1 em )
}

// ── active open ──────────────────────────────────────────────────

@ __next_ephemeral * TcpStackImpl ts → i {
    = . ts ephemeral + . ts ephemeral 1
    ? > . ts ephemeral 65535 { = . ts ephemeral 49152 } {}
    ^ . ts ephemeral
}

// Start a connection. Returns its index; the caller polls
// `tstack_conn_state` (or waits for the socket layer's wakeup) for
// ESTABLISHED. A SYN that could not be framed because ARP has not
// resolved yet is NOT an error — the retransmit timer will send it.
@ tstack_connect TcpStack ts__h i remote_ip i remote_port i local_port i now PktBuf out → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : i idx ( __conn_alloc ts )
    : *TConn c ( __tconn_ptr ts idx )
    = . c local_ip ( stack_our_ip . ts net )
    = . c local_port ? > local_port 0 local_port ( __next_ephemeral ts )
    = . c remote_ip remote_ip
    = . c remote_port remote_port
    : PktBuf o ( pktbuf_new )
    ( tcb_connect . c tcb . c local_ip . c local_port remote_ip remote_port ( __next_iss ts ) now o )
    ( __flush ts idx o now out )
    ^ idx
}

// ── the rest of the socket surface, as pure logic ────────────────

@ tstack_write TcpStack ts__h i idx ( Vec u ) data i off i len i now PktBuf out → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : *TConn c ( __tconn_ptr ts idx )
    ? == # i c 0 { ^ -1 } {}
    ? ! . c used { ^ -1 } {}
    : i n ( tcb_write . c tcb data off len 65536 )
    : PktBuf o ( pktbuf_new )
    ( tcb_pump . c tcb now o )
    ( __flush ts idx o now out )
    ^ n
}

@ tstack_read TcpStack ts__h i idx ( Vec u ) dst i n → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : *TConn c ( __tconn_ptr ts idx )
    ? == # i c 0 { ^ -1 } {}
    ? ! . c used { ^ -1 } {}
    ^ ( tcb_read . c tcb dst n )
}

@ tstack_close TcpStack ts__h i idx i now PktBuf out → v {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : *TConn c ( __tconn_ptr ts idx )
    ? == # i c 0 { ^ } {}
    ? ! . c used { ^ } {}
    : PktBuf o ( pktbuf_new )
    ( tcb_close . c tcb now o )
    ( __flush ts idx o now out )
    ? == ( tcb_state . c tcb ) ( tcp_closed ) { ( __conn_release ts idx ) } {}
}

@ tstack_abort TcpStack ts__h i idx i now PktBuf out → v {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : *TConn c ( __tconn_ptr ts idx )
    ? == # i c 0 { ^ } {}
    ? ! . c used { ^ } {}
    : PktBuf o ( pktbuf_new )
    ( tcb_abort . c tcb o )
    ( __flush ts idx o now out )
    ( __conn_release ts idx )
}

// ── timers ───────────────────────────────────────────────────────
//
// Every connection's retransmit, persist and TIME_WAIT timer, plus the
// ARP cache's own expiry. Returns the number of frames emitted, so a
// caller that wants to know whether the loop did anything does not have
// to diff the output buffer.
@ tstack_tick TcpStack ts__h i now PktBuf out → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    ( stack_tick . ts net now out )
    : i n ( vec_len [i] . ts conns )
    : ~ i emitted 0
    : ~ i k 0
    ~ < k n {
        : *TConn c ( __tconn_ptr ts k )
        ? && != # i c 0 . c used {
            : PktBuf o ( pktbuf_new )
            : i fired ( tcb_tick . c tcb now o )
            = emitted + emitted ( __flush ts k o now out )
            ? == ( tcb_state . c tcb ) ( tcp_closed ) { ( __conn_release ts k ) } {}
        } {}
        = k + k 1
    }
    ^ emitted
}

// The earliest deadline any connection is waiting on, or -1 when none
// is. An event loop that has nothing else to do sleeps until this
// rather than spinning — the difference between a guest that idles and
// one that burns its only vCPU.
@ tstack_next_timeout TcpStack ts__h i now → i {
    : *TcpStackImpl ts ( __TcpStack_ptr ts__h )
    : i n ( vec_len [i] . ts conns )
    : ~ i best -1
    : ~ i k 0
    ~ < k n {
        : *TConn c ( __tconn_ptr ts k )
        ? && != # i c 0 . c used {
            : i d ( tcb_next_timeout . c tcb now )
            ? >= d 0 { ? || < best 0 < d best { = best d } {} } {}
        } {}
        = k + k 1
    }
    ^ best
}
