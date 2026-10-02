// stdlib/net/socket.nu — BSD socket semantics over the sans-IO stack.
//
// Phase A4. Below this file everything speaks frames and segments and
// takes `now` as an argument; above it, a program calls `tcp_listen` /
// `tcp_accept` / `tcp_read_chunk` and expects a socket. This is the
// layer that turns one into the other, and it is STILL sans-IO: no
// clock, no device, no fibers, no FFI. What it adds is everything a
// socket has that a connection does not:
//
//   * a file-descriptor table, so a connection is named by a small
//     integer that survives the table moving underneath it;
//   * the errno seam — every operation reports one of the runtime's
//     NURL_NET_ERR_* codes, `sock_err_again` being the one that means
//     "not now, come back", which is what a blocking wrapper turns
//     into a park and a non-blocking one into EAGAIN;
//   * readiness, so an event loop can ask what to wake without
//     performing the operation;
//   * bind semantics: ephemeral ports, and a second listener on a
//     taken port failing with ADDRINUSE rather than quietly stealing
//     the first one's traffic.
//
// WHAT IS NOT HERE, ON PURPOSE
//
// Blocking. A socket read that must wait cannot be expressed without a
// clock and a scheduler, and both are the caller's. `sock_read`
// answers `-sock_err_again` and the caller decides whether that means
// "park this fiber" (the unikernel's runtime_bare shims), "return
// EAGAIN" (a non-blocking fd) or "pump the device once more and retry"
// (a single-threaded driver). Keeping that decision out of this file
// is what lets the whole socket surface be tested under a scripted
// clock with no operating system in the picture.
//
// ── the fd contract ──────────────────────────────────────────────
//
// An fd is a positive integer. Every operation that can fail returns
// either a non-negative result or `- err` (a negative errno), AND
// records the same code on the fd, because the runtime's socket ABI
// reports errors out of band through `nurl_tcp_err_kind`.
//
// A connection is identified inside the stack by (index, generation).
// An fd holds both, so an operation on a closed connection whose slot
// has been recycled is refused rather than silently addressed to
// whoever moved in — the use-after-close a bare index would invite.
//
// ── memory ───────────────────────────────────────────────────────
//
// A `SockTab` (from `sock_new`) is a handle (rcbox): every copy is the
// same table, and its last owner releases it — every fd still open,
// UDP mailboxes included, its output buffer, and its share of the
// TcpStack it was given. `sock_free` is an early release (optional).
// Closing an fd (`sock_close`) is protocol, not memory: it sends the
// FIN and frees the slot for reuse.
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/pktbuf.nu`
$ `stdlib/net/inet.nu`
$ `stdlib/net/arp.nu`
$ `stdlib/net/ipv4.nu`
$ `stdlib/net/tcp.nu`
$ `stdlib/net/stack.nu`
$ `stdlib/net/tcpstack.nu`
$ `stdlib/core/rcbox.nu`

// ── error codes ──────────────────────────────────────────────────
//
// These ARE the runtime's NURL_NET_ERR_* constants (stdlib/runtime.c
// §18, mirrored in stdlib/std/net.nu's `_net_err_of`). The socket
// shims hand them to `nurl_tcp_err_kind` unchanged, so a NURL program
// gets the same `NetErr` variant whether its bytes went through a
// Linux kernel or through this file.

@ sock_err_none → i { ^ 0 }

@ sock_err_bind → i { ^ 1 }

@ sock_err_addr_in_use → i { ^ 2 }

@ sock_err_accept → i { ^ 3 }

@ sock_err_read → i { ^ 4 }

@ sock_err_write → i { ^ 5 }

@ sock_err_closed → i { ^ 6 }

// EAGAIN / EWOULDBLOCK. The runtime spells it NetTimeout because a
// blocking socket only produces it once SO_RCVTIMEO fires; here it is
// the ordinary "the answer is not here yet" and every waiting caller
// keys on it.
@ sock_err_again → i { ^ 7 }

@ sock_err_other → i { ^ 8 }

// ── fd kinds ─────────────────────────────────────────────────────

@ sock_kind_free → i { ^ 0 }

@ sock_kind_listener → i { ^ 1 }

@ sock_kind_conn → i { ^ 2 }

@ sock_kind_udp → i { ^ 3 }

// ── connection status, as `connect` reports it ───────────────────

@ sock_conn_pending → i { ^ 0 }

@ sock_conn_ready → i { ^ 1 }

@ sock_conn_failed → i { ^ 2 }

// A bound UDP socket's mailbox. Datagram boundaries are the whole
// point of UDP, so the payloads go in a PktBuf — the same "bytes plus
// where each one ends" the frame path uses — and the sender's address
// travels alongside, two integers per datagram.
: UdpBox {
    PktBuf q
    ( Vec i ) src  // stride 2: ip, port — one pair per datagram in `q`
    i head  // datagrams already delivered; `q` is drained on read
    i last_ip  // sender of the datagram the last recv returned
    i last_port
}

// The mailbox lives in an rcbox (stdlib/core/rcbox.nu) behind this handle:
// a UDP socket's Sock holds one (a null one otherwise), and dropping the
// handle releases the mailbox with its PktBuf and Vec.
: UdpMailbox { s ctl }

@ UdpMailbox_share UdpMailbox h → UdpMailbox { ^ @ UdpMailbox { # s ( rcbox_share # i . h ctl ) } }

@ UdpMailbox_drop sink UdpMailbox h → v {
    ( mem_forget h )
    ( rcbox_release [UdpBox] # i . h ctl )
}

@ __udp_mailbox_ptr UdpMailbox h → *UdpBox { ^ ( rcbox_ptr [UdpBox] # i . h ctl ) }

: Sock {
    i kind
    i idx  // index into the TcpStack's connection or listener table
    i gen  // its generation when this fd was made
    i err  // last error — what nurl_tcp_err_kind reports
    i refs
    i local_ip
    i local_port
    i peer_ip
    i peer_port
    i timeout_ms
    i write_deadline_ns
    b nonblock
    b eof  // peer FIN seen AND the receive queue drained
    b shut  // sock_shutdown was called: wake and refuse
    b used
    UdpMailbox udp  // a UDP socket's mailbox; a null handle otherwise
    b connected  // UDP: a default peer is set
    i opts  // UDP: setsockopt bits, recorded and answered
}

: SockTabImpl {
    TcpStack ts
    PktBuf out  // frames waiting for the device
    ( Vec i ) fds  // *Sock, as integers — NURL has no Vec of pointers
    i ephemeral  // next ephemeral port for an unbound listener
    i our_ip
    i max_fds  // the ceiling; 0 means "no ceiling"
}

// A SockTab is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: SockTab { s ctl }

@ SockTab_share SockTab h → SockTab { ^ @ SockTab { # s ( rcbox_share # i . h ctl ) } }

@ SockTab_drop sink SockTab h → v {
    ( mem_forget h )
    ( rcbox_release [SockTabImpl] # i . h ctl )
}

@ __SockTab_ptr SockTab h → *SockTabImpl { ^ ( rcbox_ptr [SockTabImpl] # i . h ctl ) }

// The Sock blocks are raw memory the table keeps as integers: releasing
// them — and the mailbox handle a UDP one holds — is the table's own
// drop. Its TcpStack, output buffer and fd vector are dropped after.
% Drop SockTabImpl {
    @ drop SockTabImpl st → v {
        : i n ( vec_len [i] . st fds )
        : ~ i k 0
        ~ < k n {
            : *Sock s # *Sock ?? ( vec_get [i] . st fds k ) { T p → p F → 0 }
            ? != # i s 0 {
                // A UDP socket still open at teardown owns its mailbox
                // (any other Sock holds a null handle, released as nothing).
                : UdpMailbox mb . s udp
                ( mem_take mb )
                ( nurl_free # s s )
            } {}
            = k + k 1
        }
    }
}

// How many sockets may be open at once. A hosted program has this
// whether it asks for one or not — the kernel answers EMFILE and the
// server keeps serving what it already has. This layer had no such
// limit: the table grew for every concurrent connection, so a peer that
// opens ten thousand of them against a small machine does not get
// refused, it gets the machine. A ceiling turns that back into what
// every server's accept loop is already written for.
//
// 1024 is the number a POSIX programmer expects, and the point of the
// default is familiarity rather than tuning — `sock_set_max_fds` is
// there for a machine that knows its own size.
@ sock_default_max_fds → i { ^ 1024 }

// fds start at 3. Not decoration: 0 is how the socket ABI spells a
// failed handle, and a program that prints an fd should not be able to
// confuse one with stdin/stdout/stderr on the host it is pretending to
// be.
@ __fd_base → i { ^ 3 }

@ sock_new TcpStack ts i our_ip → SockTab {
    : i st__box ( rcbox_zero [SockTabImpl] )
    : *SockTabImpl st ( rcbox_ptr [SockTabImpl] st__box )
    // Another owner of the table, not a view of the caller's: every fd
    // operation goes through it for as long as this table lives.
    = . st ts ( TcpStack_share ts )
    = . st out ( pktbuf_new )
    = . st fds ( vec_new [i] )
    = . st ephemeral 32768
    = . st our_ip our_ip
    = . st max_fds ( sock_default_max_fds )
    ^ @ SockTab { # s st__box }
}

// Let go of `st` now rather than at the end of its owner's scope.
@ sock_free sink SockTab st → v {}

// The connection table under the fds, lent.
@ sock_tcpstack SockTab st__h → TcpStack {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    ^ . st ts
}

@ __sock_at * SockTabImpl st i slot → *Sock {
    ^ # *Sock ?? ( vec_get [i] . st fds slot ) { T p → p F → 0 }
}

// The Sock behind an fd, or a null pointer. Bounds and the used flag
// are checked here so no caller has to.
@ __sock * SockTabImpl st i fd → *Sock {
    : i slot - fd ( __fd_base )
    ? || < slot 0 >= slot ( vec_len [i] . st fds ) { ^ # *Sock 0 } {}
    : *Sock s ( __sock_at st slot )
    ? == # i s 0 { ^ # *Sock 0 } {}
    ? ! . s used { ^ # *Sock 0 } {}
    ^ s
}

// Every field, in one place. `nurl_alloc Z Sock` is sizeof-and-malloc,
// NOT calloc, and the runtime recycles small blocks through a freelist
// — so a fresh Sock arrives full of the last one's bytes, and a `b`
// field left unwritten is not merely undefined, it is reliably true
// about a third of the time. A fresh slot and a recycled slot need
// exactly the same initialisation, so they share it: the version of
// this file that wrote the fields out twice had one path setting `shut`
// and the other not, and the symptom was a freshly accepted connection
// answering "closed" to its first read.
@ __sock_reset * Sock s → v {
    = . s kind ( sock_kind_free )
    = . s idx -1
    = . s gen 0
    = . s err 0
    = . s refs 1
    = . s local_ip 0
    = . s local_port 0
    = . s peer_ip 0
    = . s peer_port 0
    = . s timeout_ms 0
    = . s write_deadline_ns 0
    = . s nonblock F
    = . s eof F
    = . s shut F
    = . s used T
    = . s udp @ UdpMailbox { # s 0 }
    = . s connected F
    = . s opts 0
}

// The ceiling, and a way to raise or remove it (0 = no ceiling). A
// machine that knows how much memory it has knows this number better
// than the default does.
@ sock_set_max_fds SockTab st__h i n → v {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    = . st max_fds ? > n 0 n 0
}

@ sock_max_fds SockTab st__h → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    ^ . st max_fds
}

// Would one more socket fit? Asked BEFORE anything irreversible
// happens — `sock_accept` in particular checks it before dequeuing a
// pending connection, so a refusal leaves that connection in the
// backlog for the next call instead of orphaning an established one
// nobody holds an fd for.
@ sock_can_open SockTab st__h → b { ^ ( __sock_can_open ( __SockTab_ptr st__h ) ) }

@ __sock_can_open * SockTabImpl st → b {
    ? <= . st max_fds 0 { ^ T } {}
    ^ < ( __sock_open_count st ) . st max_fds
}

@ __alloc_fd_unbounded * SockTabImpl st → i {
    : i n ( vec_len [i] . st fds )
    : ~ i k 0
    ~ < k n {
        : *Sock s ( __sock_at st k )
        ? && != # i s 0 ! . s used {
            ( __sock_reset s )
            ^ + k ( __fd_base )
        } {}
        = k + k 1
    }
    : *Sock s # *Sock ( nurl_alloc Z Sock )
    ( __sock_reset s )
    ( vec_push [i] . st fds # i s )
    ^ + n ( __fd_base )
}

// -1 when the table is full. Every caller turns that into the error its
// own operation reports, because "too many open files" arrives at a
// NURL program through whatever `accept` or `listen` answers.
@ __alloc_fd * SockTabImpl st → i {
    ? ! ( __sock_can_open st ) { ^ -1 } {}
    ^ ( __alloc_fd_unbounded st )
}

// An fd that exists only to carry an error. The socket ABI reports a
// failed `connect`/`listen`/`accept` as a HANDLE whose `err_kind` is
// set — not as a null — because the caller closes it either way. This
// is what the shims hand back on those paths.
//
// It IGNORES the ceiling, and has to: the ceiling's whole purpose is to
// turn "the machine ran out" into an error the caller receives, and an
// error that cannot be allocated is not an error the caller receives.
// These handles are transient — every caller closes one immediately —
// so the exemption is bounded by the number of failures in flight.
@ sock_err_fd SockTab st__h i err → i { ^ ( __sock_err_fd ( __SockTab_ptr st__h ) err ) }

@ __sock_err_fd * SockTabImpl st i err → i {
    : i fd ( __alloc_fd_unbounded st )
    : *Sock s ( __sock st fd )
    = . s err err
    ^ fd
}

@ sock_err SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ ( sock_err_other ) } {}
    ^ . s err
}

@ sock_clear_err SockTab st__h i fd → v {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ } {}
    = . s err 0
}

@ sock_set_nonblock SockTab st__h i fd b on → v {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ } {}
    = . s nonblock on
}

@ sock_is_nonblock SockTab st__h i fd → b {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ F } {}
    ^ . s nonblock
}

@ sock_set_timeout SockTab st__h i fd i ms → v {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ } {}
    = . s timeout_ms ms
}

@ sock_timeout SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ 0 } {}
    ^ . s timeout_ms
}

// Absolute deadlines remain sans-IO: the socket ABI supplies now_ns.
@ sock_set_write_deadline SockTab st__h i fd i ns → v {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock socket ( __sock st fd )
    ? == # i socket 0 { ^ } {}
    = . socket write_deadline_ns ? > ns 0 ns 0
}

@ sock_write_deadline SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock socket ( __sock st fd )
    ? == # i socket 0 { ^ 0 } {}
    ^ . socket write_deadline_ns
}

@ sock_write_wait_ms SockTab st__h i fd i now_ns → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock socket ( __sock st fd )
    ? == # i socket 0 { ^ 0 } {}
    : ~ i ms ? > . socket timeout_ms 0 . socket timeout_ms -1
    ? > . socket write_deadline_ns 0 {
        ? >= now_ns . socket write_deadline_ns {
            = . socket err ( sock_err_again )
            ^ 0
        } {}
        : i left + / - - . socket write_deadline_ns now_ns 1 1000000 1
        ? | < ms 0 < left ms { = ms left } {}
    } {}
    ^ ms
}

@ sock_kind SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ ( sock_kind_free ) } {}
    ^ . s kind
}

@ sock_ref SockTab st__h i fd → v {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ } {}
    = . s refs + . s refs 1
}

@ sock_local_ip SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ 0 } {}
    ^ . s local_ip
}

@ sock_local_port SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ 0 } {}
    ^ . s local_port
}

@ sock_peer_ip SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ 0 } {}
    ^ . s peer_ip
}

@ sock_peer_port SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ 0 } {}
    ^ . s peer_port
}

// ── the device seam ──────────────────────────────────────────────

// Everything the stack wants to transmit, boundaries intact. BORROWED:
// the driver walks it and then either clears it or takes it.
@ sock_out SockTab st__h → PktBuf {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    ^ . st out
}

@ sock_pending_frames SockTab st__h → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    ^ ( pktbuf_count . st out )
}

// Hand the pending frames to the caller and install a fresh buffer.
// A driver MUST take rather than iterate in place: delivering a frame
// can emit more frames into the same buffer, and a loop over a vector
// that grows underneath it is the oldest bug there is. The caller owns
// the returned PktBuf; its last owner releases it.
@ sock_take_out SockTab st__h → PktBuf { ^ ( __sock_take_out ( __SockTab_ptr st__h ) ) }

@ __sock_take_out * SockTabImpl st → PktBuf {
    : PktBuf p . st out
    // The table gives the buffer up — the slot gets a fresh one next —
    // so `p` owns it from here (a field read through a pointer is
    // otherwise a view of the table's own).
    ( mem_take p )
    = . st out ( pktbuf_new )
    ^ p
}

// One received frame in. Returns tcpstack's TRx result code so a
// driver can count what it delivered; every socket-visible effect is
// observable through the fd operations, so nothing here has to be
// wired to a callback.
@ sock_rx SockTab st__h ( Vec u ) frame i now → i { ^ ( __sock_rx ( __SockTab_ptr st__h ) frame now ) }

@ __sock_rx * SockTabImpl st ( Vec u ) frame i now → i {
    : TRx r ( tstack_rx . st ts frame now . st out )
    ? && == . r result ( trx_other ) == . r kind ( rx_udp ) {
        ( __udp_deliver st frame r )
    } {}
    ^ . r result
}

// A received datagram belongs to the socket bound to its destination
// port. No match is not an error here: ICMP port-unreachable is what a
// host owes the sender, and this stack does not send it yet — dropping
// it silently is at least honest about that, where inventing a reply
// would not be.
@ __udp_deliver * SockTabImpl st ( Vec u ) frame TRx r → v {
    : i n ( vec_len [i] . st fds )
    : ~ i k 0
    ~ < k n {
        : *Sock s ( __sock_at st k )
        ? && != # i s 0 && . s used && == . s kind ( sock_kind_udp )
        && == . s local_port . r dst_port
        || == . s local_ip 0 == . s local_ip . r dst_ip {
            : *UdpBox b ( __udp_mailbox_ptr . s udp )
            ? != # i b 0 {
                ( vec_extend_range [u] ( pktbuf_bytes . b q ) frame . r payload_off . r payload_len )
                // …_empty, not _mark: a zero-length datagram is a
                // datagram, and it has to arrive as one.
                ( pktbuf_mark_empty . b q )
                ( vec_push [i] . b src . r src_ip )
                ( vec_push [i] . b src . r src_port )
            } {}
            ^
        } {}
        = k + k 1
    }
}

@ sock_tick SockTab st__h i now → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    ^ ( tstack_tick . st ts now . st out )
}

@ sock_next_timeout SockTab st__h i now → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    ^ ( tstack_next_timeout . st ts now )
}

// The device that is not a device: every complete frame goes straight
// back in. That is what 127.0.0.1 is — a stack configured on a
// loopback address ARPs for itself, answers itself, and its own frames
// are the ones it receives — and it is enough to run a server and a
// client in one address space with no hardware under either.
//
// Returns the number of frames looped. Runs ONE round: frames produced
// by delivering these are left for the next call, so a caller in an
// event loop keeps its own turn bounded.
@ sock_loopback SockTab st__h i now → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : PktBuf w ( __sock_take_out st )
    : i n ( pktbuf_count w )
    : ~ i k 0
    ~ < k n {
        : ( Vec u ) f ( vec_new [u] )
        ( pktbuf_copy_to f w k )
        : i _r ( __sock_rx st f now )
        = k + k 1
    }
    ^ n
}

// Put our own address in the ARP cache. An interface knows its own
// MAC without asking for it, and on loopback the alternative is real:
// the first SYN cannot be framed, nothing queues it, and the
// connection waits a full retransmit timeout — a second of latency on
// every connect to 127.0.0.1 — before the second attempt finds the
// answer the stack had all along.
@ sock_seed_self SockTab st__h i now → v {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : NetStack net ( tstack_net . st ts )
    ? == ( stack_our_ip net ) 0 { ^ } {}
    ( __sock_seed_addr st ( stack_our_ip net ) now )
}

// The same, for an address we answer to that is not the interface's:
// 127.0.0.1 is ours whatever DHCP later says, and a loopback frame has
// to find a MAC for it before the interface has an address at all.
@ sock_seed_addr SockTab st__h i ip i now → v { ( __sock_seed_addr ( __SockTab_ptr st__h ) ip now ) }

@ __sock_seed_addr * SockTabImpl st i ip i now → v {
    : NetStack net ( tstack_net . st ts )
    ( arp_cache_insert ( stack_arp net ) ip ( stack_our_mac net ) now )
}

// The address the socket layer reports as local. DHCP changes it after
// the fact, and an fd table that kept the boot-time answer would hand
// out a source address the peer cannot reply to.
@ sock_set_our_ip SockTab st__h i ip → v {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    = . st our_ip ip
}

// ── binding ──────────────────────────────────────────────────────

// Is `port` already bound — in THIS protocol's port space? TCP and UDP
// have separate ones, and a check that pooled them would refuse a DNS
// client on 53 because something was listening on TCP 53.
@ __port_taken_kind * SockTabImpl st i kind i port → b {
    : i n ( vec_len [i] . st fds )
    : ~ i k 0
    ~ < k n {
        : *Sock s ( __sock_at st k )
        ? && != # i s 0 && . s used && == . s kind kind == . s local_port port {
            ^ T
        } {}
        = k + k 1
    }
    ^ F
}

@ __next_free_port * SockTabImpl st → i {
    : ~ i tries 0
    ~ < tries 16384 {
        : i p . st ephemeral
        = . st ephemeral ? >= + p 1 49152 32768 + p 1
        // An ephemeral port must be free in BOTH spaces: the caller
        // asked for "a port nobody is using", and handing back one
        // that the other protocol holds makes the next bind on it fail
        // for a reason nobody can see.
        ? && ! ( __port_taken_kind st ( sock_kind_listener ) p ) ! ( __port_taken_kind st ( sock_kind_udp ) p ) { ^ p } {}
        = tries + tries 1
    }
    ^ 0
}

// Bind and listen. `port` 0 means "pick a free one" — the POSIX
// contract, and the only way to take a port without racing whoever
// else wants it; `sock_local_port` reads back what was chosen.
//
// Always returns an fd, even on failure, with the error recorded on
// it: that is the socket ABI's shape, and the caller closes the handle
// either way.
@ sock_listen SockTab st__h i ip i port i backlog → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    ? || < port 0 > port 65535 {
        ^ ( __sock_err_fd st ( sock_err_bind ) )
    } {}
    : i p ? == port 0 ( __next_free_port st ) port
    ? == p 0 { ^ ( __sock_err_fd st ( sock_err_bind ) ) } {}
    ? && != port 0 ( __port_taken_kind st ( sock_kind_listener ) p ) {
        ^ ( __sock_err_fd st ( sock_err_addr_in_use ) )
    } {}
    : i lidx ( tstack_listen . st ts ip p backlog )
    ? < lidx 0 { ^ ( __sock_err_fd st ( sock_err_bind ) ) } {}
    ? ! ( __sock_can_open st ) {
        ( tstack_listener_close . st ts lidx )
        ^ ( __sock_err_fd st ( sock_err_other ) )
    } {}
    : i fd ( __alloc_fd st )
    : *Sock s ( __sock st fd )
    = . s kind ( sock_kind_listener )
    = . s idx lidx
    = . s local_ip ip
    = . s local_port p
    ^ fd
}

// Take the next completed connection, or `- sock_err_again` when none
// is waiting. A listener that has been shut down answers
// `- sock_err_accept` instead, so a thread parked on it wakes up and
// stops rather than waiting for a connection that will never come.
@ sock_accept SockTab st__h i lfd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock l ( __sock st lfd )
    ? == # i l 0 { ^ - 0 ( sock_err_other ) } {}
    ? != . l kind ( sock_kind_listener ) {
        = . l err ( sock_err_accept )
        ^ - 0 ( sock_err_accept )
    } {}
    ? . l shut {
        = . l err ( sock_err_accept )
        ^ - 0 ( sock_err_accept )
    } {}
    // The ceiling is checked BEFORE the connection is dequeued. Taking
    // it out of the backlog and then finding nowhere to put it would
    // leave an established connection nobody holds an fd for — the peer
    // thinks it is connected and nothing will ever read it. Left in the
    // backlog it is simply not accepted yet, which is a state TCP and
    // every accept loop already understand.
    //
    // The error is `accept`, not `again`: `again` means "ask me later"
    // and a listener with a pending connection stays readable, so a
    // reactor would hand the loop straight back and spin. A hard error
    // stops that, and the connection is still there when an fd frees.
    ? ! ( __sock_can_open st ) {
        = . l err ( sock_err_accept )
        ^ - 0 ( sock_err_accept )
    } {}
    : i cidx ( tstack_accept . st ts . l idx )
    ? < cidx 0 {
        = . l err ( sock_err_again )
        ^ - 0 ( sock_err_again )
    } {}
    : i fd ( __alloc_fd st )
    : *Sock s ( __sock st fd )
    = . s kind ( sock_kind_conn )
    = . s idx cidx
    = . s gen ( tstack_conn_gen . st ts cidx )
    = . s local_ip . l local_ip
    = . s local_port . l local_port
    = . s peer_ip ( tstack_conn_peer_ip . st ts cidx )
    = . s peer_port ( tstack_conn_peer_port . st ts cidx )
    = . l err 0
    ^ fd
}

// Wake anything waiting on this fd and refuse further use of it. The
// listener half of this is how a server is stopped from another
// context; the connection half makes a parked reader give up.
@ sock_shutdown SockTab st__h i fd → v {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ } {}
    = . s shut T
}

@ sock_is_shutdown SockTab st__h i fd → b {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ F } {}
    ^ . s shut
}

// ── UDP ──────────────────────────────────────────────────────────
//
// A datagram socket has no state machine, no window and no timers —
// what it has is a mailbox, and what this layer owes it is the same fd
// semantics TCP gets: an ephemeral bind that reads back, ADDRINUSE,
// `again` when the mailbox is empty, and readiness an event loop can
// ask about.

@ sock_udp_bind SockTab st__h i ip i port → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    ? || < port 0 > port 65535 { ^ ( __sock_err_fd st ( sock_err_bind ) ) } {}
    : i p ? == port 0 ( __next_free_port st ) port
    ? == p 0 { ^ ( __sock_err_fd st ( sock_err_bind ) ) } {}
    ? && != port 0 ( __port_taken_kind st ( sock_kind_udp ) p ) {
        ^ ( __sock_err_fd st ( sock_err_addr_in_use ) )
    } {}
    ? ! ( __sock_can_open st ) { ^ ( __sock_err_fd st ( sock_err_other ) ) } {}
    : i fd ( __alloc_fd st )
    : *Sock s ( __sock st fd )
    : i box ( rcbox_new [UdpBox] @ UdpBox { ( pktbuf_new ) ( vec_new [i] ) 0 0 0 } )
    = . s kind ( sock_kind_udp )
    = . s idx -1
    = . s local_ip ip
    = . s local_port p
    = . s udp @ UdpMailbox { # s box }
    ^ fd
}

@ __udp_box * SockTabImpl st i fd → *UdpBox {
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ # *UdpBox 0 } {}
    ? != . s kind ( sock_kind_udp ) { ^ # *UdpBox 0 } {}
    ^ ( __udp_mailbox_ptr . s udp )
}

@ sock_udp_pending SockTab st__h i fd → i { ^ ( __sock_udp_pending ( __SockTab_ptr st__h ) fd ) }

@ __sock_udp_pending * SockTabImpl st i fd → i {
    : *UdpBox b ( __udp_box st fd )
    ? == # i b 0 { ^ 0 } {}
    ^ - ( pktbuf_count . b q ) . b head
}

// Set a default peer. UDP's `connect` filters nothing here — it
// records where `sock_udp_send` goes, which is the half of the POSIX
// contract a caller can actually observe on a host with one address.
@ sock_udp_connect SockTab st__h i fd i ip i port → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ - 0 ( sock_err_other ) } {}
    ? != . s kind ( sock_kind_udp ) { ^ - 0 ( sock_err_other ) } {}
    = . s peer_ip ip
    = . s peer_port port
    = . s connected T
    ^ 0
}

@ sock_udp_is_connected SockTab st__h i fd → b {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ F } {}
    ^ . s connected
}

@ sock_udp_send_to SockTab st__h i fd i ip i port ( Vec u ) src i off i len i now → i { ^ ( __sock_udp_send_to ( __SockTab_ptr st__h ) fd ip port src off len now ) }

@ __sock_udp_send_to * SockTabImpl st i fd i ip i port ( Vec u ) src i off i len i now → i {
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ - 0 ( sock_err_other ) } {}
    ? != . s kind ( sock_kind_udp ) { ^ - 0 ( sock_err_write ) } {}
    ? . s shut {
        = . s err ( sock_err_closed )
        ^ - 0 ( sock_err_closed )
    } {}
    // A socket bound to loopback sends FROM loopback; an unbound one
    // passes 0 and gets the interface's address.
    : TxResult t ( stack_tx_udp ( tstack_net . st ts ) . s local_ip ip . s local_port port src off len now . st out )
    ? == . t status ( tx_sent ) {
        = . s err 0
        ^ len
    } {}
    // ARP has not resolved yet, or there is no route. A datagram
    // socket has no retransmit timer to fall back on, so this is
    // `again` rather than a loss the caller never hears about.
    = . s err ( sock_err_again )
    ^ - 0 ( sock_err_again )
}

@ sock_udp_send SockTab st__h i fd ( Vec u ) src i off i len i now → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ - 0 ( sock_err_other ) } {}
    ? ! . s connected {
        = . s err ( sock_err_write )
        ^ - 0 ( sock_err_write )
    } {}
    ^ ( __sock_udp_send_to st fd . s peer_ip . s peer_port src off len now )
}

// Take the next datagram into `dst`, truncating to `max` — which is
// what recvfrom(2) does, and the reason a caller passes a buffer at
// least as large as the MTU. The sender's address is readable with
// `sock_udp_last_ip` / `sock_udp_last_port` until the next recv.
@ sock_udp_recv_from SockTab st__h i fd ( Vec u ) dst i max → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ - 0 ( sock_err_other ) } {}
    ? . s shut {
        = . s err ( sock_err_closed )
        ^ - 0 ( sock_err_closed )
    } {}
    : *UdpBox b ( __udp_box st fd )
    ? == # i b 0 {
        = . s err ( sock_err_read )
        ^ - 0 ( sock_err_read )
    } {}
    ? >= . b head ( pktbuf_count . b q ) {
        = . s err ( sock_err_again )
        ^ - 0 ( sock_err_again )
    } {}
    : i idx . b head
    : i start ( pktbuf_start . b q idx )
    : i n ( pktbuf_len . b q idx )
    : i take ? < max n max n
    ? > take 0 { ( vec_extend_range [u] dst ( pktbuf_bytes . b q ) start take ) } {}
    = . b last_ip ?? ( vec_get [i] . b src * idx 2 ) { T x → x F → 0 }
    = . b last_port ?? ( vec_get [i] . b src + * idx 2 1 ) { T x → x F → 0 }
    = . b head + idx 1
    // Drained: reclaim rather than grow a queue that is never reset.
    // A socket that receives for a week would otherwise hold every
    // datagram it ever saw.
    ? >= . b head ( pktbuf_count . b q ) {
        ( pktbuf_clear . b q )
        ( vec_clear [i] . b src )
        = . b head 0
    } {}
    = . s err 0
    ^ take
}

@ sock_udp_last_ip SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *UdpBox b ( __udp_box st fd )
    ? == # i b 0 { ^ 0 } {}
    ^ . b last_ip
}

@ sock_udp_last_port SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *UdpBox b ( __udp_box st fd )
    ? == # i b 0 { ^ 0 } {}
    ^ . b last_port
}

// setsockopt, recorded rather than performed. Broadcast, multicast TTL
// and multicast loopback are properties of a driver this build does
// not have; answering OK and remembering the bit is what lets a
// program that sets them run, and `sock_udp_opts` is how a future
// driver reads what it was asked for. Nothing here pretends a
// multicast datagram left the machine.
@ sock_udp_setopt SockTab st__h i fd i bit → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ - 0 ( sock_err_other ) } {}
    ? != . s kind ( sock_kind_udp ) { ^ - 0 ( sock_err_other ) } {}
    = . s opts | . s opts bit
    ^ 0
}

@ sock_udp_opts SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ 0 } {}
    ^ . s opts
}

// ── connecting ───────────────────────────────────────────────────

// Start an active open. The fd is usable immediately and the
// connection is NOT established yet — `sock_status` says when it is.
// A SYN that could not be framed because ARP has not resolved is not
// an error: TCP's own retransmit timer sends it.
@ sock_connect SockTab st__h i ip i port i local_port i now → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    ? || <= port 0 > port 65535 { ^ ( __sock_err_fd st ( sock_err_other ) ) } {}
    // Before the connection exists, not after: a SYN sent for a socket
    // that cannot be created is a connection the peer accepts and this
    // machine has forgotten about.
    ? ! ( __sock_can_open st ) { ^ ( __sock_err_fd st ( sock_err_other ) ) } {}
    : i cidx ( tstack_connect . st ts ip port local_port now . st out )
    ? < cidx 0 { ^ ( __sock_err_fd st ( sock_err_other ) ) } {}
    : i fd ( __alloc_fd st )
    : *Sock s ( __sock st fd )
    = . s kind ( sock_kind_conn )
    = . s idx cidx
    = . s gen ( tstack_conn_gen . st ts cidx )
    = . s local_ip . st our_ip
    = . s local_port ( tstack_conn_local_port . st ts cidx )
    = . s peer_ip ip
    = . s peer_port port
    ^ fd
}

@ __live * SockTabImpl st * Sock s → b {
    ? != . s kind ( sock_kind_conn ) { ^ F } {}
    ^ ( tstack_conn_live . st ts . s idx . s gen )
}

// Where an active open has got to. A connection that vanished from the
// table without this layer ever seeing a FIN did not close, it DIED —
// a RST, or a retransmit timer that ran out of patience — because a
// peer's FIN leaves the connection in CLOSE_WAIT, alive and readable,
// until the application closes its side.
@ sock_status SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ ( sock_conn_failed ) } {}
    ? ! ( __live st s ) { ^ ? . s eof ( sock_conn_ready ) ( sock_conn_failed ) } {}
    : i state ( tstack_conn_state . st ts . s idx )
    ? == state ( tcp_syn_sent ) { ^ ( sock_conn_pending ) } {}
    ? == state ( tcp_syn_rcvd ) { ^ ( sock_conn_pending ) } {}
    ? == state ( tcp_closed ) { ^ ( sock_conn_failed ) } {}
    ^ ( sock_conn_ready )
}

@ sock_state SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ ( tcp_closed ) } {}
    ? ! ( __live st s ) { ^ ( tcp_closed ) } {}
    ^ ( tstack_conn_state . st ts . s idx )
}

// ── reading and writing ──────────────────────────────────────────

// Drain up to `max` received bytes into `dst`.
//
//   > 0   bytes appended
//     0   end of stream: the peer sent FIN and everything it sent has
//         been read. This is `read()` returning 0, and it is a
//         DIFFERENT thing from an error, which is why it is not an
//         error code.
//   < 0   `- err`
@ sock_read SockTab st__h i fd ( Vec u ) dst i max → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ - 0 ( sock_err_other ) } {}
    ? != . s kind ( sock_kind_conn ) {
        = . s err ( sock_err_read )
        ^ - 0 ( sock_err_read )
    } {}
    ? . s shut {
        = . s err ( sock_err_closed )
        ^ - 0 ( sock_err_closed )
    } {}
    ? ! ( __live st s ) {
        ? . s eof { ^ 0 } {}
        = . s err ( sock_err_closed )
        ^ - 0 ( sock_err_closed )
    } {}
    ? <= max 0 { ^ 0 } {}
    : i n ( tstack_read . st ts . s idx dst max )
    ? > n 0 {
        = . s err 0
        ^ n
    } {}
    // Nothing buffered. If the peer has sent its FIN, this is the end
    // of the stream rather than a stall — the whole reason the state
    // machine keeps `fin_rcvd` around after it has ACKed it.
    : Tcb c ( tstack_conn_tcb . st ts . s idx )
    ? && != 0 # i . c ctl ( tcb_fin_rcvd c ) {
        = . s eof T
        = . s err 0
        ^ 0
    } {}
    = . s err ( sock_err_again )
    ^ - 0 ( sock_err_again )
}

// Queue bytes for transmission. Returns how many were ACCEPTED into
// the send buffer — a short write is normal and means the window or
// the buffer is full, exactly as `send(2)` on a non-blocking socket.
// Zero accepted with bytes offered is reported as `- sock_err_again`
// so a caller never spins on a full buffer mistaking it for progress.
@ sock_write SockTab st__h i fd ( Vec u ) src i off i len i now → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ - 0 ( sock_err_other ) } {}
    ? != . s kind ( sock_kind_conn ) {
        = . s err ( sock_err_write )
        ^ - 0 ( sock_err_write )
    } {}
    ? ! ( __live st s ) {
        = . s err ( sock_err_closed )
        ^ - 0 ( sock_err_closed )
    } {}
    : i state ( tstack_conn_state . st ts . s idx )
    ? || == state ( tcp_syn_sent ) == state ( tcp_syn_rcvd ) {
        = . s err ( sock_err_again )
        ^ - 0 ( sock_err_again )
    } {}
    // Our own FIN is out: the send side is closed and more data would
    // arrive after the end of the stream.
    : Tcb c ( tstack_conn_tcb . st ts . s idx )
    ? && != 0 # i . c ctl ( tcb_fin_sent c ) {
        = . s err ( sock_err_write )
        ^ - 0 ( sock_err_write )
    } {}
    ? <= len 0 { ^ 0 } {}
    : i n ( tstack_write . st ts . s idx src off len now . st out )
    ? < n 0 {
        = . s err ( sock_err_write )
        ^ - 0 ( sock_err_write )
    } {}
    ? == n 0 {
        = . s err ( sock_err_again )
        ^ - 0 ( sock_err_again )
    } {}
    = . s err 0
    ^ n
}

// Bytes queued for transmission and not yet acknowledged. A caller
// that wants "everything is on the wire" waits for this to reach 0
// rather than assuming a return from `sock_write` means delivery.
@ sock_send_queue SockTab st__h i fd → i {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ 0 } {}
    ? ! ( __live st s ) { ^ 0 } {}
    : Tcb c ( tstack_conn_tcb . st ts . s idx )
    ? == 0 # i . c ctl { ^ 0 } {}
    ^ ( tcb_send_queue_len c )
}

// ── readiness ────────────────────────────────────────────────────
//
// What an event loop asks BEFORE performing an operation. Both answer
// true for a dead or shut-down fd on purpose: the waiter must wake and
// discover the error, and a readiness predicate that answers "not
// ready" for a connection that will never be ready is a hang.

@ sock_readable SockTab st__h i fd → b {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ T } {}
    ? . s shut { ^ T } {}
    ? == . s kind ( sock_kind_listener ) {
        ^ > ( tstack_pending_count . st ts . s idx ) 0
    } {}
    ? == . s kind ( sock_kind_udp ) { ^ > ( __sock_udp_pending st fd ) 0 } {}
    ? ! ( __live st s ) { ^ T } {}
    : Tcb c ( tstack_conn_tcb . st ts . s idx )
    ? == 0 # i . c ctl { ^ T } {}
    ^ || > ( tcb_recv_queue_len c ) 0 ( tcb_fin_rcvd c )
}

@ sock_writable SockTab st__h i fd → b {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ T } {}
    ? . s shut { ^ T } {}
    // A datagram socket is always writable: there is no window to
    // fill and nothing to wait for.
    ? == . s kind ( sock_kind_udp ) { ^ T } {}
    ? != . s kind ( sock_kind_conn ) { ^ F } {}
    ? ! ( __live st s ) { ^ T } {}
    : i state ( tstack_conn_state . st ts . s idx )
    ? || == state ( tcp_syn_sent ) == state ( tcp_syn_rcvd ) { ^ F } {}
    : Tcb c ( tstack_conn_tcb . st ts . s idx )
    ? == 0 # i . c ctl { ^ T } {}
    ? ( tcb_fin_sent c ) { ^ T } {}
    ^ < ( tcb_send_queue_len c ) ( sock_send_buf_max )
}

// The send-queue ceiling `sock_write` fills to. Matches the limit
// tcpstack passes to `tcb_write`; a writability test that used a
// different number would either report a socket writable that accepts
// nothing, or never report one writable at all.
@ sock_send_buf_max → i { ^ 65536 }

// ── closing ──────────────────────────────────────────────────────

// Release the fd. The CONNECTION may outlive it — a FIN has to be
// acknowledged and TIME_WAIT has to elapse — which is precisely why
// the connection table reclaims by timer and the fd table does not.
@ sock_close SockTab st__h i fd i now → v {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ } {}
    // Closed is closed, whoever else still holds a reference. A pooled
    // server retains its listener for the spawn→join window precisely
    // so a concurrent stop cannot free the handle underneath the
    // workers — and those workers are parked in accept, waiting for
    // this fd to say something. Marking it shut is what says it: the
    // waiters wake, `sock_accept` refuses, and the last reference
    // releases the connection.
    = . s shut T
    = . s refs - . s refs 1
    ? > . s refs 0 { ^ } {}
    ? == . s kind ( sock_kind_udp ) {
        // The socket gives its mailbox up (dropped here).
        : UdpMailbox gone . s udp
        ( mem_take gone )
        = . s udp @ UdpMailbox { # s 0 }
    } {}
    ? == . s kind ( sock_kind_listener ) {
        ( tstack_listener_close . st ts . s idx )
    } {
        ? == . s kind ( sock_kind_conn ) {
            ? ( __live st s ) { ( tstack_close . st ts . s idx now . st out ) } {}
        } {}
    }
    = . s used F
    = . s kind ( sock_kind_free )
}

// Tear the connection down with a RST rather than a FIN — what a
// server does to a client that has misbehaved, and what SO_LINGER 0
// buys on a hosted socket. The peer sees a reset, not an orderly
// close, which is the honest signal when the application is refusing
// to continue.
@ sock_abort SockTab st__h i fd i now → v {
    : *SockTabImpl st ( __SockTab_ptr st__h )
    : *Sock s ( __sock st fd )
    ? == # i s 0 { ^ } {}
    ? && == . s kind ( sock_kind_conn ) ( __live st s ) {
        ( tstack_abort . st ts . s idx now . st out )
    } {}
    = . s refs 0
    = . s used F
    = . s kind ( sock_kind_free )
}

// ── statistics ───────────────────────────────────────────────────

@ sock_open_count SockTab st__h → i { ^ ( __sock_open_count ( __SockTab_ptr st__h ) ) }

@ __sock_open_count * SockTabImpl st → i {
    : i n ( vec_len [i] . st fds )
    : ~ i live 0
    : ~ i k 0
    ~ < k n {
        : *Sock s ( __sock_at st k )
        ? && != # i s 0 . s used { = live + live 1 } {}
        = k + k 1
    }
    ^ live
}
