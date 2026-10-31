// stdlib/std/net.nu — TCP sockets (HTTP server foundation)
//
// Wraps the runtime bridge in stdlib/runtime.c (§18). Blocking sockets
// at this layer; concurrency (thread-per-connection or epoll) is
// layered on top in the HTTP server.
//
// API (this revision):
//
//   ( tcp_listen          s host i port )                   → ! TcpListener NetErr
//   ( tcp_listen_with_backlog s host i port i backlog )     → ! TcpListener NetErr
//   ( tcp_accept          TcpListener l )                   → ! TcpConn NetErr
//   ( tcp_connect         s host i port )                   → ! TcpConn NetErr
//   ( tcp_connect_timeout s host i port i ms )              → ! TcpConn NetErr
//   ( tcp_connect_tls_timeout s host i port s sni i verify s alpn ( Vec u ) sess i ms )
//                                                           → ! TcpConn NetErr
//   ( tcp_read_chunk      TcpConn c i max )                 → ! ( Vec u ) NetErr
//   ( tcp_write_all       TcpConn c ( Vec u ) bytes )       → ! v NetErr
//   ( tcp_write_all2      TcpConn c ( Vec u ) head ( Vec u ) body ) → ! v NetErr
//   ( tcp_write_str       TcpConn c s text )                → ! v NetErr
//   ( tcp_sendfile        TcpConn c PFile f i off i len )   → ! i NetErr  sendfile(2) where it can
//   ( tcp_tls_ktls        TcpConn c )                       → i    kTLS handover, see std/tls.nu
//   ( tcp_close_listener  TcpListener l )                   → v    early close (optional)
//   ( tcp_close_conn      TcpConn c )                       → v    early close (optional)
//   ( tcp_conn_adopt      i raw )                           → TcpConn  owns the runtime socket
//   ( tcp_conn_view       i raw )                           → TcpConn  never closes it
//   ( tcp_peer_addr       TcpConn c )                       → s    BORROWED view
//   ( tcp_local_addr      TcpListener l )                   → String OWNED
//   ( tcp_set_timeout     TcpConn c i ms )                  → v
//   ( net_err_name        NetErr e )                        → s    diagnostic
//   ( tcp_conn_over       %NetTransport t String peer )     → TcpConn      over a transport
//   ( tcp_listener_over   %NetTransport t String local )    → TcpListener  that is not an OS socket
//
// Transports: a TcpListener or TcpConn is a socket of the operating
// system (a runtime handle), or a socket of a network that is not the
// operating system's — a NetTransport object (see "The transport seam"
// below). The simulated network of stdlib/std/net_sim.nu is one: the
// sans-IO TCP/IP stack over a seeded bus with drops, latency and
// partitions, so a server built on these handles runs in a test
// unchanged. Every tcp_* operation works on either.
//
// Memory model:
//
//   * TcpListener and TcpConn are handles over a counted block holding
//     the runtime's NurlTcp pointer (the runtime owns the FD + a
//     sideband err_kind): every copy is the same socket, and its last
//     owner closes it — nothing to close by hand. `tcp_close_*` closes
//     it early, for every copy. A conn made with `tcp_conn_view` is a
//     view of a socket something else closes, and closes nothing.
//   * `tcp_read_chunk` returns an OWNED Vec[u]. Caller frees with
//     `( vec_free [u] v )`. EOF is reported as the NetClosed variant
//     so empty payloads (max <= 0) don't get conflated with a clean
//     peer shutdown.
//   * `tcp_write_all` and `tcp_write_str` BORROW their input — the
//     caller still owns the Vec[u] / `s` after the call returns.
//   * `tcp_peer_addr` returns a BORROWED view ("ip:port") whose
//     lifetime is tied to the TcpConn. Copy with `string_from` if
//     a long-lived String is needed.
//   * Error arms never carry a handle: the runtime frees its half on
//     dispatch, so the NURL caller has nothing to release on Err.
//
// Errors — `NetErr` tags must mirror the runtime constants in
// stdlib/runtime.c §18 (NURL_NET_ERR_*):
//
//   NetBind         1   bind / listen failed (bad host, perm, …)
//   NetAddrInUse    2   EADDRINUSE on bind
//   NetAccept       3   accept(2) failed
//   NetRead         4   recv(2) failed (non-timeout)
//   NetWrite        5   send(2) failed (non-timeout, non-closed)
//   NetClosed       6   peer reset / clean EOF on read
//   NetTimeout      7   EAGAIN/EWOULDBLOCK after SO_*TIMEO
//   NetOther        8   anything else / unsupported target (WASI); also
//                       the TLS-listener features the pure server lacks
//                       (tcp_tls_add_sni / tcp_tls_reload /
//                       tcp_tls_require_client_cert)
//   NetTlsCtxInit   9   not produced by the pure TLS stack — kept so the
//                       tags still mirror the runtime; only its inert
//                       nurl_tcp_*_tls* stubs set it, and no .nu calls them
//   NetTlsCertLoad  10  TLS listener: cert PEM unreadable or has no
//                       parsable CERTIFICATE block (_load_tls_ident)
//   NetTlsKeyLoad   11  TLS listener: key PEM is not an EC P-256, RSA or
//                       ML-DSA PKCS#8 key, or tcp_listen_tls_dual's second
//                       identity is not ML-DSA
//   NetTlsHandshake 12  pure TLS handshake failed — server side on accept
//                       (tls_server.nu) or client side in tcp_connect_tls*
//                       / tcp_starttls (tls.nu). A TCP connect that fails
//                       under tcp_connect_tls* reports its own error
//                       (NetTimeout, NetOther, …), not this
//
// Platform notes:
//
//   * POSIX backend is plain BSD sockets — `socket`/`bind`/`listen`/
//     `accept`/`recv`/`send`. `MSG_NOSIGNAL` is set on send to avoid
//     SIGPIPE, so a peer-closed connection surfaces as NetClosed
//     instead of killing the process.
//   * Win32 backend uses Winsock2 (`-lws2_32`); the runtime calls
//     WSAStartup lazily on the first listen.
//   * wasm32-wasi targets compile but every call returns NetOther.
//
// MVP scope — explicitly left for later phases:
//   - IPv6 (`AF_INET6`) — Phase 1.x extension.
//
// TLS is not among them: it is pure NURL — stdlib/std/tls.nu (client) and
// stdlib/std/tls_server.nu (TLS 1.3 server), run over these plain sockets
// by tcp_connect_tls* / tcp_starttls / tcp_listen_tls* below.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/pfile.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/tls_server.nu`
$ `stdlib/std/pkey.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

: | NetErr {
    NetBind
    NetAddrInUse
    NetAccept
    NetRead
    NetWrite
    NetClosed
    NetTimeout
    NetOther
    NetTlsCtxInit
    NetTlsCertLoad
    NetTlsKeyLoad
    NetTlsHandshake
}

// Listener and connection are intentionally distinct types — the
// compiler refuses to mix them at call sites, which catches the
// classic "passed listener to read" mistake at type-check time.
// A TLS listener carries its identity — the loaded certificate_list
// (CertificateEntry blobs, leaf first) and the leaf's private key,
// prepared for signing when the listener is made (std/tls_server.nu
// TlsIdent) — so each accept runs the pure handshake (is_tls = 1) with
// nothing derived from the key on the way. `pq` is an OPTIONAL second
// identity — an ML-DSA chain and key served beside the classical one to
// clients that list its scheme (`tcp_listen_tls_dual`). `alpn` is the
// TLS listener's ALPN preference list in wire form ([len:1][name]
// entries, server order — see tls_alpn_pack), empty when the listener
// does not negotiate ALPN. The listener is a plain value every accepting
// worker copies, so the material lives in a table of the module's
// (g_tls_lcreds below) and `creds` names its slot (0 on a plaintext
// listener).
: TlsCreds {
    ( Arc TlsIdent ) id
    ? ( Arc TlsIdent ) pq
    ( Vec u ) alpn
}

// The listener's state: the runtime socket handle, and for a TLS
// listener its credentials slot — or, for a listener of another
// transport, one owner of that transport as a word (`nt`, see "The
// transport seam"; `raw` is 0 then, and `nt` is 0 on an OS socket). None
// of it changes once made: an early tcp_close_listener stops the socket
// (closing a runtime fd) and empties the slot, and the last owner
// releases the handle and gives the transport back, whose own drop
// closes its socket.
// Sealed (`raw`): `raw` is a runtime socket handle, `nt` a transport
// owner, both given back by its drop.
raw : TcpListenerImpl { i raw i is_tls i creds i nt }

% Drop TcpListenerImpl {
    @ drop TcpListenerImpl l → v {
        ( nurl_tcp_close . l raw )
        ? != . l creds 0 { ( __tls_lcreds_close . l creds ) } {}
        ? != . l nt 0 { ( __nt_release . l nt ) } {}
    }
}

// A listener is a handle: every copy (each accepting worker's) is the
// same socket, and the last owner closes it — nothing to close by hand.
: TcpListener { ( Shared TcpListenerImpl ) ctl }

// Its drop closes something the outside world sees (stdlib/core/marker.nu).
% Resource TcpListener {}

// Its copies are made to be used by several threads at once — workers
// accepting on one socket, another thread closing it to stop them. That
// is an assertion, not a proof (stdlib/core/marker.nu). What backs it:
// the fields never change after tcp_listen; the runtime socket's accept
// counts itself in before it reads the fd, and its stop
// (tcp_close_listener / tcp_shutdown_listener, idempotent) closes the fd
// only once no accept is in progress (nurl__tcp_listener_stop,
// stdlib/runtime_ffi.c); the TLS material's slot is read and emptied
// under its lock.
% Sync TcpListener {}

@ TcpListener_share TcpListener h → TcpListener { ^ @ TcpListener { ( shared_clone [TcpListenerImpl] . h ctl ) } }

@ TcpListener_drop sink TcpListener h → v {}

@ __tli TcpListener l → *TcpListenerImpl { ^ ( shared_ptr [TcpListenerImpl] . l ctl ) }

@ __tcp_listener_make i raw i is_tls i creds → TcpListener {
    ^ @ TcpListener { ( shared_new [TcpListenerImpl] @ TcpListenerImpl { raw is_tls creds 0 } ) }
}

// The runtime handle behind a listener.
@ tcp_listener_raw TcpListener l → i { ^ . ( __tli l ) raw }

// Every TLS listener's material, by slot (a listener's `creds` is its
// slot + 1). A handshake takes a share of its own under the lock, and
// tcp_close_listener empties the slot: the material goes with the last
// share, so a handshake still running when the listener closes keeps
// what it reads. The table and its lock are made by the first TLS
// listen, while the process is still single-threaded (as the ticket key
// is), and every other use follows one.
: TlsSlot { ? ( Arc TlsCreds ) creds }

: ~ ( Vec TlsSlot ) g_tls_lcreds 0
: ~ Mutex g_tls_lcreds_mu 0
: ~ b g_tls_lcreds_made F

@ __tls_lcreds_add sink ( Arc TlsCreds ) c → i {
    ? ! g_tls_lcreds_made {
        = g_tls_lcreds ( vec_new [TlsSlot] )
        = g_tls_lcreds_mu ( mutex_new )
        = g_tls_lcreds_made T
    } {}
    ( mutex_lock g_tls_lcreds_mu )
    ( vec_push [TlsSlot] g_tls_lcreds @ TlsSlot { @ ?( Arc TlsCreds ) { T c } } )
    : i slot ( vec_len [TlsSlot] g_tls_lcreds )
    ( mutex_unlock g_tls_lcreds_mu )
    ^ slot
}

@ __tls_lcreds_get i slot → ?( Arc TlsCreds ) {
    ( mutex_lock g_tls_lcreds_mu )
    : TlsSlot e ( vec_at [TlsSlot] g_tls_lcreds - slot 1 )
    : ?( Arc TlsCreds ) out ?? . e creds {
        T a → @ ?( Arc TlsCreds ) { T ( arc_clone [TlsCreds] a ) }
        F → @ ?( Arc TlsCreds ) { F }
    }
    ( mutex_unlock g_tls_lcreds_mu )
    ^ out
}

@ __tls_lcreds_close i slot → v {
    ( mutex_lock g_tls_lcreds_mu )
    ( vec_put [TlsSlot] g_tls_lcreds - slot 1 @ TlsSlot { @ ?( Arc TlsCreds ) { F } } )
    ( mutex_unlock g_tls_lcreds_mu )
}
// kind: 0 = plaintext (raw is the runtime socket handle), 1 = pure TLS
// client, 2 = pure TLS server, 3 = another transport's socket. For kinds
// 1/2 `tlsh` is one owner of the TlsConn as a word (`_tls_word`;
// tcp_close_conn gives it back) and reads/writes dispatch to the pure
// stack. For kind 3 `tlsh` is one owner of the transport as a word (see
// "The transport seam"), `raw` is 0, and nothing here ever changes — so
// another thread's tcp_conn_shutdown can read it while its owner closes
// it; the drop gives the transport back.
// Sealed (`raw`): `raw` and `tlsh` are runtime handles its drop closes.
raw : TcpConnImpl { i raw i kind i tlsh b owns }

% Drop TcpConnImpl {
    @ drop TcpConnImpl c → v {
        ? . c owns { ( __tcp_conn_close_parts . c raw . c kind . c tlsh ) } {}
    }
}

// A connection is a handle: every copy is the same connection, and the
// last owner closes it — nothing to close by hand (tcp_close_conn closes
// it early). A view (tcp_conn_view) of a socket something else owns
// never closes it.
: TcpConn { ( Shared TcpConnImpl ) ctl }

// Its drop closes something the outside world sees (stdlib/core/marker.nu).
% Resource TcpConn {}

@ TcpConn_share TcpConn h → TcpConn { ^ @ TcpConn { ( shared_clone [TcpConnImpl] . h ctl ) } }

@ TcpConn_drop sink TcpConn h → v {}

@ __tci TcpConn c → *TcpConnImpl { ^ ( shared_ptr [TcpConnImpl] . c ctl ) }

@ __tcp_conn_make i raw i kind i tlsh b owns → TcpConn {
    ^ @ TcpConn { ( shared_new [TcpConnImpl] @ TcpConnImpl { raw kind tlsh owns } ) }
}

// ── The transport seam ─────────────────────────────────────────────
//
// A socket that is not the operating system's: an object of a type that
// implements NetTransport, owned by a TcpConn (kind 3) or TcpListener
// (`nt` set) made over it with tcp_conn_over / tcp_listener_over. Every
// tcp_* operation on such a handle goes to the object's methods. The
// simulated network of stdlib/std/net_sim.nu is the transport this was
// made for; nothing in this file links it in, so a program that never
// makes one pays nothing for it — no code, no compile time, no bytes (the
// state keeps its layout: a listener's transport takes the slot of a key
// type nothing read, a connection's the TLS handle's word), and on the
// plaintext path no extra test: the transport `kind` is tested first,
// where the TLS handle was.
//
// The methods answer in the tcp_* functions' own results, so the
// operations here hand them straight back and every conversion lives in
// the transport — code a program that never makes one does not compile.
// Blocking is the transport's own business and has to be context-aware
// like the rest of this file: a method that waits parks a fiber and
// blocks a thread, as long as the socket's timeout says (nt_set_timeout;
// 0 = no deadline). What never changes about a socket — the address
// tcp_peer_addr / tcp_local_addr report — is not asked of the transport
// at all: the handle keeps it beside the transport (NetTransportBox), so
// the string is a plain field view, not a call's result. The object is
// the socket: its drop closes it, so nothing is closed by hand, and
// nt_close is the early close (idempotent — the drop that follows it
// closes nothing). Several threads may hold one (a listener's workers,
// the HTTP server's drain shutting a connection down), hence Send Sync.
//
// The handle holds its transport as ONE OWNER IN A WORD, as it holds a
// TlsConn, not as a typed field. A trait object in TcpConn's type would
// make every TcpConn a value whose captures the compiler cannot follow,
// and storing one into a handle shared across threads — the HTTP
// server's drain table does, for every connection — is then refused
// (docs/MEMORY.md §7.7: it might close a cycle of counts nothing frees).
// What makes the word sound is the contract on the two constructors: a
// transport holds nothing that can reach a TcpConn or TcpListener — so
// no cycle can pass through one — which is why they are `raw`: the
// standard library's transports keep it (net_sim's socket holds its
// network: stacks, a bus, a lock), and a program's own needs `unsafe`.
% NetTransport [T] : Send Sync {
    // The next connection on a listening socket, waiting for one for as
    // long as it takes (an accept has no deadline; tcp_close_listener
    // ends the wait with NetAccept).
    @ nt_accept T self → !TcpConn NetErr
    // Append up to `max` received bytes to `buf`. `wait` T is
    // tcp_read_into: Ok(n > 0), the peer's end of stream NetClosed, a
    // deadline NetTimeout. `wait` F is tcp_try_read_into: Ok(0) when
    // nothing is there yet.
    @ nt_read_into T self ( Vec u ) buf i max b wait → !i NetErr
    // All of `bytes` (tcp_write_all): NetTimeout when the write deadline
    // or the timeout passed first.
    @ nt_write T self ( Vec u ) bytes → !v NetErr
    // `head` then `body`, all of both, as one stream (tcp_write_all2).
    @ nt_write_all T self ( Vec u ) head ( Vec u ) body → !v NetErr
    // What of `wire` from `off` fits now (tcp_try_write_wire): Ok(n),
    // Ok(0) when nothing does.
    @ nt_try_write T self ( Vec u ) wire i off → !i NetErr
    // 1 when readable / writable as asked, 0 when `timeout_ms` passed
    // first (0 = poll, < 0 = no deadline), -1 when neither was asked.
    @ nt_wait_io T self b readable b writable i timeout_ms → i
    @ nt_close T self → v
    // A connection: its read side (a blocked read returns), with `both`
    // its write side too. A listener: accepting stops.
    @ nt_shutdown T self b both → v
    @ nt_set_timeout T self i ms → v
    @ nt_timeout_ms T self → i
    @ nt_set_write_deadline T self i ns → v
    @ nt_write_deadline T self → i
    @ nt_set_nonblock T self b on → v
}

// The transport in a counted block, with the socket's address ("ip:port"
// of the peer for a connection, its own for a listener): its owner
// travels as the block's address (one word), and the last owner drops
// both.
: NetTransportBox {
    % NetTransport t
    String addr
}

// requires: the word is given back, once, with __nt_release; and the
// transport holds nothing that can reach a TcpConn or TcpListener.
// TODO(#248): a known compromise. Once the §7.7 store rule judges a trait
// object by its impls' types, the handles hold a typed field instead of
// this word, and tcp_conn_over / tcp_listener_over stop being raw.
raw @ __nt_word sink %NetTransport t sink String addr → i {
    ^ ( shared_into_word [NetTransportBox] ( shared_new [NetTransportBox] @ NetTransportBox { t addr } ) )
}

// requires: `w` came from __nt_word and is given back only this once.
raw @ __nt_release i w → v { : ( Shared NetTransportBox ) _back ( shared_from_word [NetTransportBox] w ) }

// The transport an owner word names, lent for as long as that owner —
// the handle's state, alive while any copy of the handle is — lives.
@ __nt i w → %NetTransport { ^ . ( rcbox_ptr [NetTransportBox] w ) t }

// Its address, lent the same way.
@ __nt_addr i w → s { ^ ( string_data . ( rcbox_ptr [NetTransportBox] w ) addr ) }

// A connection over `t`, which it now owns, to the peer at `peer`
// ("ip:port", what tcp_peer_addr reports): its last owner drops `t`
// (closing the socket); tcp_close_conn closes it early, for every copy.
// requires: `t` holds nothing that can reach a TcpConn or TcpListener
// (see "The transport seam").
raw @ tcp_conn_over sink %NetTransport t sink String peer → TcpConn {
    ^ @ TcpConn { ( shared_new [TcpConnImpl] @ TcpConnImpl { 0 3 ( __nt_word t peer ) T } ) }
}

// A listener over `t`, bound to `local` ("ip:port", what tcp_local_addr
// reports): tcp_accept takes its connections (nt_accept),
// tcp_close_listener stops it, the last owner drops `t`.
// requires: as tcp_conn_over.
raw @ tcp_listener_over sink %NetTransport t sink String local → TcpListener {
    ^ @ TcpListener { ( shared_new [TcpListenerImpl] @ TcpListenerImpl { 0 0 0 ( __nt_word t local ) } ) }
}

// A TLS listener over `t`: as tcp_listener_over, and its connections are
// handshaken as tcp_listen_tls's are — identity `id` (tls_ident_pem, …),
// ALPN list `alpn_protocols` ("h2 http/1.1"; "" = none) — the TLS running
// over the transport (agora #250).
// requires: as tcp_listener_over.
raw @ tcp_listener_over_tls sink %NetTransport t sink String local ( Arc TlsIdent ) id s alpn_protocols → TcpListener {
    ( _tls_ticket_key_ensure )
    : ( Arc TlsCreds ) creds ( arc_new [TlsCreds] @ TlsCreds { id @ ?( Arc TlsIdent ) { F } ( tls_alpn_pack alpn_protocols ) } )
    ^ @ TcpListener { ( shared_new [TcpListenerImpl] @ TcpListenerImpl { 0 1 ( __tls_lcreds_add creds ) ( __nt_word t local ) } ) }
}

// A connection's transport, when it has one (kind 3).
// Close a transport by its owner word. tcp_close_conn hands over the
// word rather than a view of the conn: it writes the conn's fields
// afterwards on its other paths, and a transport method called on a
// view of that same state made the borrow checker take every caller's
// result for a view of the conn.
@ __nt_close_word i w → v { ( nt_close ( __nt w ) ) }

@ __tc_is_nt TcpConn c → b { ^ == . ( __tci c ) kind 3 }

@ __tc_nt TcpConn c → %NetTransport { ^ ( __nt . ( __tci c ) tlsh ) }

// ── TLS over a transport (agora #250) ──
//
// A connection of another transport (kind 3) carries TLS like a runtime
// socket does: its transport moves into the TLS connection, whose record
// layer reads and writes it (std/tls.nu's TlsTransport), and the conn
// becomes a TLS conn (tcp_starttls) or hands the TLS state to the server
// that accepted it (tls_accept_conn).

// The bytes under TLS: a NetTransport, by its owner word, which this owns.
: NtTlsStream { i w }

% Drop NtTlsStream {
    @ drop NtTlsStream x → v { ? != . x w 0 { ( __nt_release . x w ) } {} }
}

% TlsTransport NtTlsStream {
    @ tt_read NtTlsStream self ( Vec u ) buf i max b wait → i {
        ^ ?? ( nt_read_into ( __nt . self w ) buf max wait ) {
            // (Nothing there yet, when not waiting: not the end of stream.)
            T n → ? & ! wait == n 0 -1 n
            F e → ?? e { NetClosed → 0 _ → -1 }
        }
    }
    @ tt_write NtTlsStream self ( Vec u ) bytes → b { ^ ?? ( nt_write ( __nt . self w ) bytes ) { T _ → T F _ → F } }
    @ tt_set_timeout NtTlsStream self i ms → v { ( nt_set_timeout ( __nt . self w ) ms ) }
    @ tt_set_write_deadline NtTlsStream self i ns → v { ( nt_set_write_deadline ( __nt . self w ) ns ) }
    @ tt_close NtTlsStream self → v { ( nt_close ( __nt . self w ) ) }
    @ tt_peer NtTlsStream self → s { ^ ( __nt_addr . self w ) }
}

// A TLS conn whose TlsConn runs over a transport (not a runtime socket).
@ __tc_tls_tt TcpConn c → b {
    : i tp ( __conn_tlsptr c )
    ^ & != tp 0 ( tls_over_transport # TlsConn tp )
}

// The transport of kind-3 conn `c`, taken over: the word is the caller's
// to own, and the conn — every copy — is left closed, as tcp_close_conn
// leaves one. 0 when it has none any more.
@ __tc_take_nt TcpConn c → i {
    : *TcpConnImpl p ( __tci c )
    : i w ? == . p kind 3 . p tlsh 0
    = . p owns F
    = . p raw 0
    = . p kind 0
    = . p tlsh 0
    ^ w
}

// A connection on runtime socket handle `raw`, which the TcpConn now owns:
// its last owner (or tcp_close_conn) closes it.
@ tcp_conn_adopt i raw → TcpConn { ^ ( __tcp_conn_make raw 0 0 T ) }

// A TcpConn over a socket something else owns and closes (a protocol
// client that keeps the runtime handle in its own record): reads and
// writes go to it, and neither its drop nor tcp_close_conn closes it.
@ tcp_conn_view i raw → TcpConn { ^ ( __tcp_conn_make raw 0 0 F ) }

// The runtime handle field of a connection (0 for a TLS conn, whose
// socket lives in its TlsConn, and once it is closed).
@ tcp_conn_raw TcpConn c → i { ^ . ( __tci c ) raw }

// Hand the socket over (to the TLS layer): its runtime handle, which this
// conn — and every copy of it — no longer closes.
@ __tcp_conn_release TcpConn c → i {
    : *TcpConnImpl p ( __tci c )
    // Another transport has no runtime handle to hand over: 0, which the
    // TLS layer refuses, and the conn keeps (and closes) its own socket.
    ? == . p kind 3 { ^ 0 } {}
    = . p owns F
    ^ . p raw
}

// The server side of a TLS handshake over an accepted plaintext conn, with
// a certificate chain and key in memory (tls_accept): the TlsConn takes
// the socket over, and `c` — every copy of it — no longer closes it. On a
// failed handshake the TLS layer has closed the socket.
@ tls_accept_conn TcpConn c ( Vec u ) cert_chain ( Vec u ) priv → !TlsConn TlsErr {
    ^ ( tls_accept_conn_ident c ( tls_ident_ec cert_chain priv ) ( vec_new [u] ) )
}

// tls_accept_conn with a prepared identity (tls_ident_pem, tls_ident_ec,
// …) and an ALPN preference list in wire form (empty: none), over a
// runtime socket or another transport's — a simulated network's — alike.
@ tls_accept_conn_ident TcpConn c ( Arc TlsIdent ) id ( Vec u ) alpn_prefs → !TlsConn TlsErr {
    ? ( __tc_is_nt c ) {
        : i w ( __tc_take_nt c )
        ? == w 0 { ^ @ !TlsConn TlsErr { F # TlsErr TlsConnect } } {}
        ^ ( tls_accept_over ( dyn TlsTransport @ NtTlsStream { w } ) id alpn_prefs )
    } {}
    ^ ( tls_accept_ident ( __tcp_conn_release c ) id alpn_prefs )
}

// Render a NetErr variant name as a raw `s` for log lines.
@ net_err_name NetErr e → s {
    ^ ?? e {
        NetBind → `NetBind`
        NetAddrInUse → `NetAddrInUse`
        NetAccept → `NetAccept`
        NetRead → `NetRead`
        NetWrite → `NetWrite`
        NetClosed → `NetClosed`
        NetTimeout → `NetTimeout`
        NetOther → `NetOther`
        NetTlsCtxInit → `NetTlsCtxInit`
        NetTlsCertLoad → `NetTlsCertLoad`
        NetTlsKeyLoad → `NetTlsKeyLoad`
        NetTlsHandshake → `NetTlsHandshake`
    }
}

// True iff a NetErr is a recv/send TIMEOUT (SO_*TIMEO fired) rather than a
// hard failure — the caller can retry the same operation. A partial-frame
// reader uses this to distinguish "the rest is still coming" from "the peer
// is gone".
@ net_is_timeout NetErr e → b { ^ ?? e { NetTimeout → T _ → F } }

// Internal: classify the runtime err_kind into a NetErr variant.
// `deflt` is the variant to return for any unmapped err_kind (kept
// caller-controlled because read/write/listen each have a different
// "natural" fallback).
@ _net_err_of i ek → NetErr {
    ? == ek 1 { ^ # NetErr NetBind } {}
    ? == ek 2 { ^ # NetErr NetAddrInUse } {}
    ? == ek 3 { ^ # NetErr NetAccept } {}
    ? == ek 4 { ^ # NetErr NetRead } {}
    ? == ek 5 { ^ # NetErr NetWrite } {}
    ? == ek 6 { ^ # NetErr NetClosed } {}
    ? == ek 7 { ^ # NetErr NetTimeout } {}
    ? == ek 9 { ^ # NetErr NetTlsCtxInit } {}
    ? == ek 10 { ^ # NetErr NetTlsCertLoad } {}
    ? == ek 11 { ^ # NetErr NetTlsKeyLoad } {}
    ? == ek 12 { ^ # NetErr NetTlsHandshake } {}
    ^ # NetErr NetOther
}

// ── Listener lifecycle ─────────────────────────────────────────────

// Bind on host:port and start listening with the given backlog.
//
// `port` 0 means "let the kernel pick a free ephemeral port" — the way
// to bind without racing another process for a fixed number. Read back
// what it picked with `tcp_local_addr`.
@ tcp_listen_with_backlog s host i port i backlog → !TcpListener NetErr {
    ^ ( tcp_listen_with host port @ TcpListenOpts { backlog F } )
}

// Listener options:
//   backlog     the accept queue's length (the kernel caps it at its own
//               maximum — net.core.somaxconn on Linux); <= 0 → 16.
//   reuse_port  SO_REUSEPORT: several listeners may bind the same address
//               (each must ask, the first included), and the kernel spreads
//               incoming connections across them — one listener, and one
//               accept loop, per worker. Linux and the BSDs; ignored where
//               the platform has no such option.
: TcpListenOpts { i backlog b reuse_port }

// The accept-queue length every listener gets unless it asks otherwise:
// 4096, the kernel's own default ceiling (Linux's somaxconn since 5.4;
// the kernel clamps it to the configured one). 128 — the old default,
// and the pre-5.4 somaxconn — overflows under a burst of connections: the
// kernel drops the SYNs it has no room for, and each dropped client waits
// out a 1 s retransmission. A long queue costs nothing until it is used.
@ tcp_listen_default_backlog → i { ^ 4096 }

@ tcp_listen_opts_default → TcpListenOpts { ^ @ TcpListenOpts { ( tcp_listen_default_backlog ) F } }

unsafe & `c` @ nurl_tcp_listen_opts s host i port i backlog i flags → i

// Bind on host:port and listen with `o` (TcpListenOpts).
@ tcp_listen_with s host i port TcpListenOpts o → !TcpListener NetErr {
    : i raw ( nurl_tcp_listen_opts host port . o backlog ? . o reuse_port 1 0 )
    ? == raw 0 { ^ @ !TcpListener NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind raw )
    ? != ek 0 {
        ( nurl_tcp_close raw )
        ^ @ !TcpListener NetErr { F ( _net_err_of ek ) }
    } {}
    ^ @ !TcpListener NetErr { T ( __tcp_listener_make raw 0 0 ) }
}

// Convenience: tcp_listen_with and the default options
// (tcp_listen_default_backlog, no SO_REUSEPORT).
@ tcp_listen s host i port → !TcpListener NetErr {
    ^ ( tcp_listen_with host port ( tcp_listen_opts_default ) )
}

// TLS listener — loads the PEM cert chain + private key files (EC P-256,
// RSA or ML-DSA key), then binds and starts listening exactly like
// tcp_listen. On accept the per-conn pure TLS 1.3 server handshake
// (tls_server.nu) runs transparently; the returned TcpConn is
// polymorphic — `tcp_read_chunk` / `tcp_write_all` dispatch to the pure
// record layer, so HttpServer (and any other code that consumed
// TcpConn) gets HTTPS without changes. Cert and key are loaded once at
// listener creation. ALPN is negotiated when the listener was made with
// tcp_listen_tls_with_alpn; SNI cert selection, client-cert auth and
// live cert reload are not implemented in the pure stack
// (tcp_tls_add_sni / tcp_tls_reload / tcp_tls_require_client_cert
// return NetOther).
// Frame every `-----BEGIN CERTIFICATE-----` block in `pem` as a TLS 1.3
// CertificateEntry (tls_cert_entry) and concatenate them, leaf first —
// the certificate_list the server sends. Supports a single leaf or a
// full chain (fullchain.pem: leaf + intermediates). Returns an empty Vec
// if no cert block parses.
@ __net_cert_chain String pem → ( Vec u ) {
    : ( Vec u ) list ( vec_new [u] )
    : i total ( string_len pem )
    : ~ i pos 0
    : ~ i guard 0
    ~ & < pos total < guard 64 {
        = guard + guard 1
        : String suf ( string_substr pem pos - total pos )
        : i rel ( nurl_str_find ( string_data suf ) `-----BEGIN CERTIFICATE-----` )
        ? < rel 0 { = pos total } {
            : i bi + pos rel
            : String suf2 ( string_substr pem bi - total bi )
            : i erel ( nurl_str_find ( string_data suf2 ) `-----END CERTIFICATE-----` )
            ? < erel 0 { = pos total } {
                : i blen + erel 25  // through the END marker (25 chars)
                : String block ( string_substr pem bi blen )
                ?? ( pem_to_der ( string_data block ) ) {
                    T der → {
                        : ( Vec u ) e ( tls_cert_entry der )
                        ( bytes_extend_bytes list e )
                    }
                    F _ → {}
                }
                = pos + bi blen
            }
        }
    }
    ^ list
}

// Load cert chain + private key from PEM files into a server identity:
// the framed certificate_list and the key, prepared for signing
// (tls_ident_ec / tls_ident_rsa / tls_ident_mldsa). Fails with
// NetTlsCertLoad / NetTlsKeyLoad. The key form is auto-detected: the EC,
// RSA and ML-DSA PKCS#8 parsers each cleanly reject the others'
// encodings.
@ _load_tls_ident s cert_path s key_path → !( Arc TlsIdent ) NetErr {
    : String certpem ?? ( read_file cert_path ) { T p → p F _ → ( string_new ) }
    : String keypem ?? ( read_file key_path ) { T p → p F _ → ( string_new ) }
    ^ ( tls_ident_pem certpem keypem )
}

// A server identity from its PEM text in memory — the certificate chain
// (leaf first) and the private key (EC P-256, RSA or ML-DSA, PKCS#8 or
// the key's own form): what a TLS listener loads from its files, for a
// server whose identity is not in files (a generated one, a test's, one
// from a secret store). NetTlsCertLoad when no certificate parses,
// NetTlsKeyLoad when the key does not.
@ tls_ident_pem String certpem String keypem → !( Arc TlsIdent ) NetErr {
    : ( Vec u ) chain ( __net_cert_chain certpem )
    ? == ( vec_len [u] chain ) 0 { ^ @ !( Arc TlsIdent ) NetErr { F ( _net_err_of 10 ) } } {}
    // EC first; on failure try RSA (the parsers reject foreign encodings).
    ?? ( ec_p256_priv_from_pem ( string_data keypem ) ) {
        T sc → { ^ @ !( Arc TlsIdent ) NetErr { T ( tls_ident_ec chain sc ) } }
        F _ → {}
    }
    ?? ( rsa_priv_from_pem ( string_data keypem ) ) {
        T k → {
            // CRT form when the key carries its factors (std/pkey.nu)
            ?? ( rsa_priv_sign_key k ) {
                T sk → { ^ @ !( Arc TlsIdent ) NetErr { T ( tls_ident_rsa chain sk ) } }
                F → { ^ @ !( Arc TlsIdent ) NetErr { F ( _net_err_of 11 ) } }
            }
        }
        F _ → {}
    }
    ?? ( mldsa_priv_from_pem ( string_data keypem ) ) {
        T mk → { ^ @ !( Arc TlsIdent ) NetErr { T ( tls_ident_mldsa chain ( mldsa_level_of_sk_len ( vec_len [u] . mk sk ) ) . mk sk ) } }
        F _ → {}
    }
    ^ @ !( Arc TlsIdent ) NetErr { F ( _net_err_of 11 ) }
}

@ tcp_listen_tls_with_backlog s host i port i backlog s cert_path s key_path → !TcpListener NetErr {
    ^ ( __tcp_listen_tls_impl host port backlog cert_path key_path `` `` `` )
}

// Shared body of the TLS listener constructors. `alpn_protocols` is a
// space-separated server preference list ("h2 http/1.1") or "" for no
// ALPN; it is packed to wire form once here and parked on the listener
// like the cert and key. `pq_cert_path` / `pq_key_path` name an optional
// ML-DSA chain + key to serve beside the classical pair ("" for none).
@ __tcp_listen_tls_impl s host i port i backlog s cert_path s key_path s alpn_protocols s pq_cert_path s pq_key_path → !TcpListener NetErr {
    : ( Arc TlsIdent ) id ?? ( _load_tls_ident cert_path key_path ) {
        T x → x
        F e → { ^ @ !TcpListener NetErr { F e } }
    }
    // The second identity: it has to BE an ML-DSA key — a classical key
    // here would be a configuration mistake, and is refused as a key
    // load error rather than silently served as a second ECDSA cert.
    : ~ ? ( Arc TlsIdent ) pq @ ?( Arc TlsIdent ) { F }
    ? > ( nurl_str_len pq_cert_path ) 0 {
        : ( Arc TlsIdent ) p2 ?? ( _load_tls_ident pq_cert_path pq_key_path ) {
            T x → x
            F e → { ^ @ !TcpListener NetErr { F e } }
        }
        ? != ( tls_ident_keytype p2 ) 2 {
            ^ @ !TcpListener NetErr { F ( _net_err_of 11 ) }
        } {}
        = pq @ ?( Arc TlsIdent ) { T p2 }
    } {}
    : i raw ( nurl_tcp_listen host port backlog )
    ? == raw 0 {
        ^ @ !TcpListener NetErr { F # NetErr NetOther }
    } {}
    : i ek ( nurl_tcp_err_kind raw )
    ? != ek 0 {
        ( nurl_tcp_close raw )
        ^ @ !TcpListener NetErr { F ( _net_err_of ek ) }
    } {}
    // The session-ticket key is drawn here, while the process is still
    // single-threaded, so every worker that later accepts on this
    // listener seals and opens tickets under the same key.
    ( _tls_ticket_key_ensure )
    // The identities move into the listener's shared credentials.
    : ( Vec u ) alpn ( tls_alpn_pack alpn_protocols )
    : ( Arc TlsCreds ) creds ( arc_new [TlsCreds] @ TlsCreds { id pq alpn } )
    ^ @ !TcpListener NetErr { T ( __tcp_listener_make raw 1 ( __tls_lcreds_add creds ) ) }
}

@ tcp_listen_tls s host i port s cert_path s key_path → !TcpListener NetErr {
    ^ ( tcp_listen_tls_with_backlog host port ( tcp_listen_default_backlog ) cert_path key_path )
}

// TLS listener with ALPN (RFC 7301). `alpn_protocols` is a space-separated
// preference list, most-preferred first — "h2 http/1.1" is what an
// HTTP/2-capable HTTPS server advertises. Per accepted connection the
// handshake picks the first protocol in THIS order that the client also
// offered and announces it in EncryptedExtensions; read it back with
// tcp_alpn_protocol. A client that offers ALPN with nothing in common is
// refused with a fatal no_application_protocol alert (§3.2); a client
// that sends no ALPN negotiates nothing and gets "" — the caller decides
// what that means (HTTP servers treat it as HTTP/1.1).
@ tcp_listen_tls_with_alpn s host i port i backlog s cert_path s key_path s alpn_protocols → !TcpListener NetErr {
    ^ ( __tcp_listen_tls_impl host port backlog cert_path key_path alpn_protocols `` `` )
}

// A TLS listener with TWO identities: the classical `cert_path` /
// `key_path` (EC P-256 or RSA) and a post-quantum `pq_cert_path` /
// `pq_key_path` (an ML-DSA-44/65/87 leaf, PKCS#8 key). Each accepted
// connection is shown the one its ClientHello can verify: the ML-DSA
// leaf when the client's signature_algorithms lists its scheme
// (RFC 8446 §4.4.2.2), the classical leaf otherwise — so a server can
// deploy an ML-DSA certificate for the clients that understand it
// without turning away a single client that does not. With the
// X25519MLKEM768 group the handshake already prefers, such a
// connection has no classical asymmetric operation left in it.
// `tcp_is_post_quantum` reports the group; `tcp_tls_sig_scheme` the
// scheme the server signed with.
//
// The PQ key file must hold an ML-DSA key — a classical key there is
// refused with NetTlsKeyLoad, since serving it as a second ECDSA
// identity would silently not be what was asked for.
@ tcp_listen_tls_dual s host i port i backlog s cert_path s key_path s pq_cert_path s pq_key_path s alpn_protocols → !TcpListener NetErr {
    ^ ( __tcp_listen_tls_impl host port backlog cert_path key_path alpn_protocols pq_cert_path pq_key_path )
}

// Read the negotiated ALPN protocol off a TLS conn — a client conn (kind
// 1), a STARTTLS upgrade, or a conn accepted by a tcp_listen_tls_with_alpn
// listener (kind 2). Returns "" for plaintext conns or when no ALPN was
// negotiated.
@ tcp_alpn_protocol TcpConn c → String {
    : i tp ( __conn_tlsptr c )
    ? == tp 0 { ^ ( string_new ) } {}
    ^ ( tls_alpn_selected # TlsConn tp )
}

// True iff this conn negotiated exactly `proto` over ALPN. F for a
// plaintext conn or when nothing was negotiated. No allocation — this is
// the per-connection protocol dispatch in the HTTP server.
@ tcp_alpn_is TcpConn c s proto → b {
    : i tp ( __conn_tlsptr c )
    ? == tp 0 { ^ F } {}
    ^ ( tls_alpn_is # TlsConn tp proto )
}

// The key-exchange group this connection negotiated, as its IANA
// number — 4588 X25519MLKEM768, 29 x25519, 23 secp256r1 — or 0 for a
// plaintext conn or one that has not got that far.
//
// Worth asking rather than assuming, on either side. A peer that has
// not deployed ML-KEM falls back to a classical group silently, and
// nothing else about the connection looks different; a server that
// wants to log, require or report post-quantum key exchange has no
// other way to find out.
@ tcp_tls_group TcpConn c → i {
    : i tp ( __conn_tlsptr c )
    ? == tp 0 { ^ 0 } {}
    ^ ( tls_group # TlsConn tp )
}

// kTLS on this TLS connection (std/tls.nu tls_ktls): hand its record
// protection to the kernel where it can go and report what the kernel
// now protects — 1 the write side, 2 the read side, 3 both, 0 neither
// (or not a TLS connection).
@ tcp_tls_ktls TcpConn c → i {
    : i tp ( __conn_tlsptr c )
    ? == tp 0 { ^ 0 } {}
    ^ ( tls_ktls # TlsConn tp )
}

// T when this TLS connection was established from a session ticket
// (RFC 8446 §4.6.1) rather than a full handshake — on the server, one
// of its own tickets; on a client, the exported session it offered.
// F for plaintext connections.
@ tcp_tls_resumed TcpConn c → b {
    : i tp ( __conn_tlsptr c )
    ? == tp 0 { ^ F } {}
    ^ ( tls_is_resumed # TlsConn tp )
}

// T when this connection's key exchange has a post-quantum component,
// so its forward secrecy survives an adversary recording it today and
// factoring later.
@ tcp_is_post_quantum TcpConn c → b {
    ^ == ( tcp_tls_group c ) 4588
}

// The SignatureScheme the CertificateVerify of this TLS connection was
// signed with — on an accepted connection, which of the listener's
// identities this client was shown: ecdsa_secp256r1_sha256 0x0403 (1027),
// rsa_pss_rsae_sha256 0x0804 (2052), mldsa44/65/87 0x0904–0x0906
// (2308–2310). 0 for plaintext and for resumed handshakes (no certificate).
@ tcp_tls_sig_scheme TcpConn c → i {
    : i tp ( __conn_tlsptr c )
    ? == tp 0 { ^ 0 } {}
    ^ ( tls_cv_scheme # TlsConn tp )
}

& `c` @ nurl_tcp_connect_ms s host i port i ms → i

& `c` @ nurl_monotonic_ns → i

// The runtime half of every client connect: a connected runtime handle,
// or the transport's own NetErr (the failed handle already closed).
//
// Context-aware like the reads: on a fiber, neither the name lookup nor
// the TCP handshake holds the worker — a name resolves on a runtime
// resolver thread and the handshake waits on the netpoller, while the
// other fibers on that worker keep running. A numeric address never
// reaches a resolver. Every address the name resolves to is tried in
// order until one connects. Off a fiber the call blocks the thread, as
// it always has. `ms` > 0 bounds the whole call — lookup and handshake
// — and reports NetTimeout once it passes; 0 waits as long as the
// resolver and the kernel do (an unanswered SYN: minutes).
@ __tcp_connect_raw s host i port i ms → !i NetErr {
    : i raw ( nurl_tcp_connect_ms host port ? > ms 0 ms 0 )
    ? == raw 0 { ^ @ !i NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind raw )
    ? != ek 0 {
        ( nurl_tcp_close raw )
        ^ @ !i NetErr { F ( _net_err_of ek ) }
    } {}
    ^ @ !i NetErr { T raw }
}

// Open a plain (unencrypted) TCP client connection. Returns a
// polymorphic TcpConn (kind 0) usable with the same tcp_read/tcp_write
// family as accepted connections. For an encrypted connection use
// tcp_connect_tls below. No deadline of its own: see
// tcp_connect_timeout.
@ tcp_connect s host i port → !TcpConn NetErr {
    ^ ( tcp_connect_timeout host port 0 )
}

// tcp_connect, giving up after `ms` milliseconds with NetTimeout. The
// budget covers the name lookup and the TCP handshake together, and is
// honoured on a fiber (a netpoller deadline — the worker keeps running
// other fibers meanwhile) and off one (poll(2)) alike. ms <= 0 = no
// deadline. For TLS with one deadline over both handshakes, see
// tcp_connect_tls_timeout.
@ tcp_connect_timeout s host i port i ms → !TcpConn NetErr {
    ?? ( __tcp_connect_raw host port ms ) {
        F e → ^ @ !TcpConn NetErr { F e }
        T raw → ^ @ !TcpConn NetErr { T ( tcp_conn_adopt raw ) }
    }
}

// Open a verified (or, with verify = 0, encrypted-only) pure-TLS client
// connection. Returns a polymorphic TcpConn (kind 1) whose reads/writes
// dispatch to the pure client stack.
@ tcp_connect_tls s host i port s server_name i verify → !TcpConn NetErr {
    : i raw ?? ( __tcp_connect_raw host port 0 ) { F e → ^ @ !TcpConn NetErr { F e } T r → r }
    : !TlsConn TlsErr r ? != verify 0 ( tls_attach_verify raw server_name ) ( tls_attach raw server_name )
    ?? r {
        F _ → ^ @ !TcpConn NetErr { F # NetErr NetTlsHandshake }
        T tc → ^ @ !TcpConn NetErr { T ( __tcp_conn_make 0 1 ( _tls_word tc ) T ) }
    }
}

// As tcp_connect_tls, but offers ALPN protocols — one ("h2") or a
// preference list ("h2 http/1.1", most preferred first, RFC 7301). After
// connecting, the negotiated protocol is read with tcp_alpn_protocol —
// empty if the server declined ALPN. With verify the chain is validated
// AND the ALPN handshake runs; on TLS 1.2 servers the pure stack does
// not parse ALPN, so callers requiring h2 should check.
@ tcp_connect_tls_alpn s host i port s server_name i verify s alpn → !TcpConn NetErr {
    : i raw ?? ( __tcp_connect_raw host port 0 ) { F e → ^ @ !TcpConn NetErr { F e } T r → r }
    : !TlsConn TlsErr r ? != verify 0 ( tls_attach_alpn_verify raw server_name alpn ) ( tls_attach_alpn raw server_name alpn )
    ?? r {
        F _ → ^ @ !TcpConn NetErr { F # NetErr NetTlsHandshake }
        T tc → ^ @ !TcpConn NetErr { T ( __tcp_conn_make 0 1 ( _tls_word tc ) T ) }
    }
}

// tcp_connect_tls_alpn with a resumption offer as well: `sess` is what
// tcp_tls_session_export returned from an earlier connection to the same
// server (empty = full handshake). ALPN, resumption and verification in
// one call — what an HTTP client that pools connections needs, since the
// one-knob variants each leave one of the three out.
@ tcp_connect_tls_full s host i port s server_name i verify s alpn ( Vec u ) sess → !TcpConn NetErr {
    ^ ( tcp_connect_tls_timeout host port server_name verify alpn sess 0 )
}

// tcp_connect_tls_full with ONE deadline, `ms` milliseconds, over the
// whole connect: name lookup, TCP handshake and TLS handshake. Running
// out reports NetTimeout, at whichever step it happens; ms <= 0 = no
// deadline (each handshake read then waits up to 20 s, as in
// tcp_connect_tls*). For the one-knob forms pass `` alpn and an empty
// session: verify 1 `` ( vec_new [u] ) is tcp_connect_tls with a
// deadline. On a fiber every wait parks; off one it is poll(2) and the
// socket timeouts.
@ tcp_connect_tls_timeout s host i port s server_name i verify s alpn ( Vec u ) sess i ms → !TcpConn NetErr {
    : i deadline ? > ms 0 + ( nurl_monotonic_ns ) * ms 1000000 0
    : i raw ?? ( __tcp_connect_raw host port ms ) { F e → ^ @ !TcpConn NetErr { F e } T r → r }
    : !TlsConn TlsErr r ( tls_attach_full_until raw server_name alpn sess verify deadline )
    ?? r {
        F _ → {
            ? & > deadline 0 >= ( nurl_monotonic_ns ) deadline {
                ^ @ !TcpConn NetErr { F # NetErr NetTimeout }
            } {}
            ^ @ !TcpConn NetErr { F # NetErr NetTlsHandshake }
        }
        T tc → ^ @ !TcpConn NetErr { T ( __tcp_conn_make 0 1 ( _tls_word tc ) T ) }
    }
}

// Wrap a TLS connection the caller established itself (tls_attach_full /
// tls_connect_full — say, to read the ALPN pick before deciding which
// protocol stack to hand the socket to) as a client TcpConn (kind 1).
// The TcpConn holds an owner of it from here: tcp_close_conn closes it.
@ tcp_conn_from_tls TlsConn tc → TcpConn {
    ^ ( __tcp_conn_make 0 1 ( _tls_word tc ) T )
}

// The resumption session of a TLS client conn (tls_session_export): offer
// it to tcp_connect_tls_full on the next connection to the same server.
// Empty for plaintext conns and when the server issued no ticket.
@ tcp_tls_session_export TcpConn c → ( Vec u ) {
    : i tp ( __conn_tlsptr c )
    ? == tp 0 { ^ ( vec_new [u] ) } {}
    ^ ( tls_session_export # TlsConn tp )
}

// ── Dialers ────────────────────────────────────────────────────────
// How a client reaches a server, chosen when the client is made rather
// than by a switch anything else can flip: the kernel's TCP
// (net_dialer_kernel, the default — tcp_connect_timeout), or any network
// that hands out TcpConns, such as a simulated one (std/net_sim.nu's
// netsim_dialer). A client library takes a NetDialer at construction and
// dials through it, so the same client runs over the real network and a
// simulated one unchanged.
//
//   ( net_dialer_kernel )                  → NetDialer   the default; allocates nothing
//   ( net_dial d host port timeout_ms )    → !TcpConn NetErr
//   ( net_dialer_is_kernel d )             → b
//   raw ( net_dialer_over d )              → NetDialer   any `% NetDialer`
//
// A dialer is plaintext: TLS over a dialed connection is #250, so a
// client asked for TLS through anything but the kernel's dialer says so
// rather than quietly using the real network.

% NetDialer [T] : Send Sync {
    // A connection to host:port, waiting at most `timeout_ms` (<= 0: no
    // deadline) — NetDns, NetConnect, NetTimeout as tcp_connect_timeout.
    @ nd_dial T self s host i port i timeout_ms → !TcpConn NetErr
}

: NetDialerBox { % NetDialer d }

// requires: as __nt_word — given back once (__nd_release), and the dialer
// holds nothing that can reach a TcpConn or a NetDialer.
// TODO(#248): the same known compromise as the transport seam's word.
raw @ __nd_word sink %NetDialer d → i {
    ^ ( shared_into_word [NetDialerBox] ( shared_new [NetDialerBox] @ NetDialerBox { d } ) )
}

// requires: `w` came from __nd_word and is given back only this once.
raw @ __nd_release i w → v { : ( Shared NetDialerBox ) _back ( shared_from_word [NetDialerBox] w ) }

@ __nd i w → %NetDialer { ^ . ( rcbox_ptr [NetDialerBox] w ) d }

// The dialer's state: the owner word of its box.
: NetDialerImpl { i w }

% Drop NetDialerImpl {
    @ drop NetDialerImpl x → v { ? != . x w 0 { ( __nd_release . x w ) } {} }
}

// A dialer is a handle: every copy is the same one, the last owner lets it
// go. The kernel's has no state at all (a null handle).
: NetDialer { ( Shared NetDialerImpl ) ctl }

// Every copy may be used from any thread: its state is set once, at
// construction, and only read after; the dialer it holds is Sync (the
// trait's bound), and dialing changes nothing in it.
% Sync NetDialer {}

@ NetDialer_share NetDialer h → NetDialer { ^ @ NetDialer { ( shared_clone [NetDialerImpl] . h ctl ) } }

@ NetDialer_drop sink NetDialer h → v {}

@ net_dialer_kernel → NetDialer { ^ @ NetDialer { ( shared_null [NetDialerImpl] ) } }

@ net_dialer_is_kernel NetDialer d → b { ^ == 0 ( shared_addr [NetDialerImpl] . d ctl ) }

// A dialer over `d`, which it now owns.
// requires: `d` holds nothing that can reach a TcpConn or a NetDialer.
raw @ net_dialer_over sink %NetDialer d → NetDialer {
    ^ @ NetDialer { ( shared_new [NetDialerImpl] @ NetDialerImpl { ( __nd_word d ) } ) }
}

@ net_dial NetDialer d s host i port i timeout_ms → !TcpConn NetErr {
    ? ( net_dialer_is_kernel d ) { ^ ( tcp_connect_timeout host port timeout_ms ) } {}
    : *NetDialerImpl p ( shared_ptr [NetDialerImpl] . d ctl )
    ^ ( nd_dial ( __nd . p w ) host port timeout_ms )
}

// Register a per-hostname cert/key pair on a TLS listener for Server
// Name Indication (RFC 6066 §3). NOT YET SUPPORTED on the pure-NURL TLS
// server (tls_server.nu serves a single default cert) — returns NetOther
// so callers can detect the gap rather than silently serving the wrong
// cert. (The old OpenSSL-backed multi-cert SNI path was removed with
// libssl.) TODO: per-SNI cert selection in tls_accept.
@ tcp_tls_add_sni TcpListener l s hostname s cert_path s key_path → !v NetErr {
    ^ @ !v NetErr { F # NetErr NetOther }
}

// Reload the cert/key on a live TLS listener. NOT YET SUPPORTED on the
// pure-NURL TLS server — returns NetOther. (Was OpenSSL SSL_CTX hot-swap;
// removed with libssl.) TODO: atomic cert reload for the pure listener.
@ tcp_tls_reload TcpListener l s hostname s cert_path s key_path → !v NetErr {
    ^ @ !v NetErr { F # NetErr NetOther }
}

// Require/request client-cert (mTLS) authentication. NOT YET SUPPORTED on
// the pure-NURL TLS server — returns NetOther DELIBERATELY: silently
// returning Ok would let a caller believe mTLS is enforced when it is not
// (a security footgun). (Was OpenSSL client-cert verification; removed
// with libssl.) TODO: client-cert request + verify in tls_accept.
@ tcp_tls_require_client_cert TcpListener l s ca_bundle_path b strict → !v NetErr {
    ^ @ !v NetErr { F # NetErr NetOther }
}

// Peer certificate subject. Always "" on the pure TLS stack: it verifies
// the chain during the handshake but does not expose the subject string,
// and the pure server never requests a client cert, so there is no mTLS
// identity to read. (Was the OpenSSL one-line DN, e.g.
// "/CN=client.example.com/O=Acme/C=US"; removed with libssl.)
@ tcp_peer_cert_subject TcpConn c → String {
    ^ ( string_new )
}

// Close the listener now rather than with its last owner, from any
// thread. Every copy sees it closed: an accept in progress returns
// NetAccept, and so does every later one. The runtime handle stays
// named until the last owner: a worker that retained it
// (tcp_listener_retain) still releases it.
@ tcp_close_listener TcpListener l → v {
    : *TcpListenerImpl p ( __tli l )
    // (Another network's listener stops the same way; its socket goes
    // with the last owner, as the runtime handle's does.)
    ? != . p nt 0 { ( nt_shutdown ( __nt . p nt ) T ) ^ v } {}
    ( nurl_tcp_shutdown . p raw )
    ? != . p creds 0 { ( __tls_lcreds_close . p creds ) } {}
}

// Stop the listener's socket — every accept in progress returns NetAccept,
// and so does every later one — and leave its TLS material in place.
// `server_run_pool`'s shutdown thread stops its workers so; the last
// owner releases the rest.
@ tcp_shutdown_listener TcpListener l → v {
    : *TcpListenerImpl p ( __tli l )
    ? != . p nt 0 { ( nt_shutdown ( __nt . p nt ) T ) ^ v } {}
    : s rp # s . p raw
    : i raw # i rp
    ( nurl_tcp_shutdown raw )
}

// ── Connection acceptance ──────────────────────────────────────────

// ── STARTTLS registry ──────────────────────────────────────────────
//
// An in-place TLS upgrade (tcp_starttls) attaches a TlsConn to an
// ALREADY-connected fd (SMTP STARTTLS, etc). A TcpConn is passed BY
// VALUE, so the upgraded `tlsh`/`kind` can't be written back into the
// caller's copy. Because the fd is the stable identity across the
// upgrade, the fd→TlsConn mapping lives here instead and is consulted
// by the read/write/close dispatch. The whole thing is gated on
// g_st_n: a process that never calls tcp_starttls does ZERO lookups.
//
// Storage is an owned `( Vec i )` of (fd, ptr) pairs, two words each.
: ~ ( Vec i ) g_st 0
: ~ b g_st_made F
: ~ i g_st_n 0

@ __starttls_register i fd i ptr → v {
    ? ! g_st_made { = g_st ( vec_new [i] ) = g_st_made T } {}
    ( vec_push [i] g_st fd )
    ( vec_push [i] g_st ptr )
    = g_st_n + g_st_n 1
}

@ __starttls_lookup i fd → i {
    ? == g_st_n 0 { ^ 0 } {}
    : *i b ( vec_data [i] g_st )
    : ~ i k 0
    ~ < k g_st_n {
        ? == . b * k 2 fd { ^ . b + * k 2 1 } {}
        = k + k 1
    }
    ^ 0
}

@ __starttls_unregister i fd → v {
    ? == g_st_n 0 { ^ } {}
    : *i b ( vec_data [i] g_st )
    : ~ i k 0
    : ~ i found 0
    ~ & == found 0 < k g_st_n {
        ? == . b * k 2 fd {
            : i last - g_st_n 1
            = . b * k 2 . b * last 2
            = . b + * k 2 1 . b + * last 2 1
            : b _t ( vec_truncate [i] g_st * last 2 )
            = g_st_n last
            = found 1
        } {}
        = k + k 1
    }
}

// Resolve a TcpConn's TlsConn (as its word), or 0 if the conn is plaintext.
// kinds 1/2 carry it inline in `tlsh`; a STARTTLS-upgraded kind-0 conn
// is found via the fd registry; a kind-3 conn (another transport) has
// none. The kind is tested first: on the plaintext path that is the one
// test this takes before the registry's (which a process that never
// upgrades answers with its count), and it is what lets each operation
// below test for kind 3 without adding a compare to that path.
@ __conn_tlsptr TcpConn c → i {
    : *TcpConnImpl p ( __tci c )
    ? == . p kind 0 { ^ ( __starttls_lookup . p raw ) } {}
    ? == . p kind 3 { ^ 0 } {}
    ^ . p tlsh
}

// The fd backing a TcpConn — the runtime handle for plaintext, or the
// pure TLS conn's socket fd for TLS (kinds 1/2 or STARTTLS-upgraded).
@ __conn_fd TcpConn c → i {
    : i tp ( __conn_tlsptr c )
    ? != tp 0 { ^ ( tls_socket # TlsConn tp ) } {}
    ^ . ( __tci c ) raw
}

// The runtime socket handle behind ANY TcpConn — plaintext, pure-TLS
// client or server, STARTTLS-upgraded — for readiness polling with
// nurl_reactor_wait_read / nurl_tcp_get_fd. A TLS conn keeps its handle
// inside the TlsConn and has raw = 0; reading `. c raw` directly, as the
// HTTP/2 client did, polls handle 0 — which on the hosted runtime is a
// null handle (never readable, so the probe merely fell through to the
// blocking read) and on the pure in-process stack is somebody else's
// socket, reported readable while the caller's own had nothing.
@ tcp_conn_fd TcpConn c → i { ^ ( __conn_fd c ) }

// Run the server-side pure-TLS handshake over a freshly accepted raw
// conn handle, using the listener's parked cert/key material. Consumes
// `craw` (the TlsConn owns the socket on success; closed on failure).
@ __tls_accept_handshake TcpListener l i craw → !TcpConn NetErr {
    // A share of its own for the handshake's whole run.
    ?? ( __tls_lcreds_get . ( __tli l ) creds ) {
        T a → { ^ ( __tls_accept_with l ( arc_ptr [TlsCreds] a ) craw ) }
        F → {
            ( nurl_tcp_close craw )
            ^ @ !TcpConn NetErr { F # NetErr NetTlsHandshake }
        }
    }
}

@ __tls_accept_with TcpListener l * TlsCreds c i craw → !TcpConn NetErr {
    // With a second identity parked on the listener the handshake
    // chooses between the two per ClientHello (tls_accept_ident_dual).
    : !TlsConn TlsErr r ?? . c pq {
        T pq → ( tls_accept_ident_dual craw . c id pq . c alpn )
        F → ( tls_accept_ident craw . c id . c alpn )
    }
    ?? r {
        F _ → ^ @ !TcpConn NetErr { F # NetErr NetTlsHandshake }
        T tc → ^ @ !TcpConn NetErr { T ( __tcp_conn_make 0 2 ( _tls_word tc ) T ) }
    }
}

// Accept ONLY the transport (TCP) connection — even on a TLS listener,
// no handshake runs here. Context-aware: on a fiber the wait parks on
// the reactor. This is the building block a fiber-per-connection
// server wants: accept cheaply on the accept fiber, then let each
// CONNECTION's fiber run `tcp_conn_complete_tls`, so handshakes
// proceed concurrently instead of serialising on the accept loop.
@ tcp_accept_transport TcpListener l → !TcpConn NetErr {
    // Another network's listener: its transport accepts (and waits as
    // the context it runs in allows).
    : *TcpListenerImpl lp ( __tli l )
    ? != . lp nt 0 { ^ ( nt_accept ( __nt . lp nt ) ) } {}
    : i fcur ( nurl_fiber_current )
    ? != fcur 0 { ^ ( tcp_accept_async l ) } {}
    : i lraw . lp raw
    : i craw ( nurl_tcp_accept lraw )
    ? == craw 0 { ^ @ !TcpConn NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind craw )
    ? != ek 0 {
        ( nurl_tcp_close craw )
        ^ @ !TcpConn NetErr { F ( _net_err_of ek ) }
    } {}
    : TcpConn c ( tcp_conn_adopt craw )
    ^ @ !TcpConn NetErr { T c }
}

// Complete a TLS listener's server handshake over a transport conn from
// `tcp_accept_transport`. Consumes `c` — on success the returned conn
// supersedes it (the TlsConn owns the socket); on Err the socket is
// already closed by the TLS layer. A plaintext listener returns `c`
// unchanged. The handshake's record I/O is context-aware, so on a fiber
// a slow client parks this fiber instead of blocking the worker.
@ tcp_conn_complete_tls TcpListener l TcpConn c → !TcpConn NetErr {
    ? == . ( __tli l ) is_tls 0 { ^ @ !TcpConn NetErr { T c } } {}
    ? ( __tc_is_nt c ) { ^ ( __tls_accept_handshake_nt l c ) } {}
    ^ ( __tls_accept_handshake l ( __tcp_conn_release c ) )
}

// The listener's handshake on a connection of another transport: its
// transport moves into the server's TlsConn (agora #250).
@ __tls_accept_handshake_nt TcpListener l TcpConn c → !TcpConn NetErr {
    ?? ( __tls_lcreds_get . ( __tli l ) creds ) {
        T a → {
            : *TlsCreds cr ( arc_ptr [TlsCreds] a )
            : i w ( __tc_take_nt c )
            ? == w 0 { ^ @ !TcpConn NetErr { F # NetErr NetClosed } } {}
            : !TlsConn TlsErr r ( tls_accept_over ( dyn TlsTransport @ NtTlsStream { w } ) ( arc_clone [TlsIdent] . cr id ) . cr alpn )
            ?? r {
                F _ → ^ @ !TcpConn NetErr { F # NetErr NetTlsHandshake }
                T tc → ^ @ !TcpConn NetErr { T ( __tcp_conn_make 0 2 ( _tls_word tc ) T ) }
            }
        }
        F → { ^ @ !TcpConn NetErr { F # NetErr NetTlsHandshake } }
    }
}

@ tcp_accept TcpListener l → !TcpConn NetErr {
    // Context-aware: on a fiber, the transport accept parks on the
    // reactor so the worker pthread stays free while we wait. For a
    // TLS listener the handshake then runs right here in the calling
    // context (fiber-aware record I/O parks; a plain thread blocks).
    : !TcpConn NetErr acc ( tcp_accept_transport l )
    ? == . ( __tli l ) is_tls 0 { ^ acc } {}
    ?? acc {
        T rawc → ^ ( tcp_conn_complete_tls l rawc )
        F e → ^ @ !TcpConn NetErr { F e }
    }
}

// Close `raw` / its TLS connection (kind, tlsh as in TcpConnImpl).
@ __tcp_conn_close_parts i raw i kind i tlsh → v {
    // Another transport's owner goes back; its drop closes the socket.
    ? == kind 3 {
        ? != tlsh 0 { ( __nt_release tlsh ) } {}
        ^ v
    } {}
    : i tp ? != tlsh 0 tlsh ? == kind 0 ( __starttls_lookup raw ) 0
    ? != tp 0 {
        ( __starttls_unregister raw )
        // kind 2 = pure-NURL TLS server conn: its close_notify must be
        // encrypted under the server write keys (tls_server_close);
        // tls_close's alert uses the client direction.
        ? == kind 2 { ( tls_server_close # TlsConn tp ) } { ( tls_close # TlsConn tp ) }
        // …and the conn's owner of it goes back: the last one frees it.
        ( _tls_word_release tp )
    } { ( nurl_tcp_close raw ) }
}

// Close the connection now rather than with its last owner. Every copy
// sees it closed; a view closes nothing.
@ tcp_close_conn TcpConn c → v {
    : *TcpConnImpl p ( __tci c )
    // Another transport closes its socket and the state stays as it is
    // (see TcpConnImpl): every copy then reads a closed socket.
    ? == . p kind 3 { ( __nt_close_word . p tlsh ) ^ v } {}
    ? . p owns { ( __tcp_conn_close_parts . p raw . p kind . p tlsh ) } {}
    = . p owns F
    = . p raw 0
    = . p kind 0
    = . p tlsh 0
}

// In-place STARTTLS upgrade: run a pure TLS 1.3 handshake over an
// already-connected plaintext TcpConn's fd, registering the resulting
// TlsConn against that fd so subsequent read/write/close on the SAME
// (by-value) conn transparently go through TLS. `server_name` drives
// SNI + (when verify) certificate validation. Used by SMTP STARTTLS,
// IMAP/POP STLS, etc. The conn keeps its identity — no new TcpConn is
// returned, so callers holding the conn by value see the upgrade.
@ tcp_starttls TcpConn c s server_name b verify → !v NetErr { ^ ( tcp_starttls_until c server_name verify 0 ) }

// tcp_starttls with the whole handshake bounded by `deadline_ns` (absolute
// monotonic ns, std/time.nu's monotonic_ns; 0 = none — then each read
// waits up to 20 s): a deadline that passes fails it with NetTimeout, over
// a runtime socket or another transport alike. A failed handshake leaves
// the conn closed.
@ tcp_starttls_until TcpConn c s server_name b verify i deadline_ns → !v NetErr {
    ? ( __tc_is_nt c ) { ^ ( __starttls_over c server_name verify deadline_ns ) } {}
    : i tp ( __conn_tlsptr c )
    ? != tp 0 { ^ @ !v NetErr { T 0 } } {}
    : i fd . ( __tci c ) raw
    : !TlsConn TlsErr r ? > deadline_ns 0 ( __starttls_fd_until fd server_name verify deadline_ns ) ? verify ( tls_attach_verify fd server_name ) ( tls_attach fd server_name )
    ?? r {
        F _ → {
            // A failed handshake (or a certificate refused) closed the
            // socket with the TLS state that took it over: the conn
            // holds a closed handle now, which its drop must not close
            // a second time (a use-after-free of the runtime's record).
            : *TcpConnImpl p ( __tci c )
            = . p owns F
            = . p raw 0
            ^ @ !v NetErr { F ( __starttls_err deadline_ns ) }
        }
        T tc → {
            ( __starttls_register fd ( _tls_word tc ) )
            ^ @ !v NetErr { T 0 }
        }
    }
}

// tls_attach_full_until over the conn's own socket (no ALPN, no session).
@ __starttls_fd_until i fd s server_name b verify i deadline_ns → !TlsConn TlsErr {
    ^ ( tls_attach_full_until fd server_name `` ( vec_new [u] ) ? verify 1 0 deadline_ns )
}

// A failed handshake's error: NetTimeout once its deadline has passed.
@ __starttls_err i deadline_ns → NetErr {
    ? & > deadline_ns 0 >= ( nurl_monotonic_ns ) deadline_ns { ^ # NetErr NetTimeout } {}
    ^ # NetErr NetTlsHandshake
}

// tcp_starttls on a connection of another transport: the handshake runs
// over its transport, which the TLS connection takes over, and the conn
// becomes a TLS client conn holding it — every copy sees the upgrade, as
// over a runtime socket. A failed handshake has closed the transport.
@ __starttls_over TcpConn c s server_name b verify i deadline_ns → !v NetErr {
    : i w ( __tc_take_nt c )
    ? == w 0 { ^ @ !v NetErr { F # NetErr NetClosed } } {}
    : !TlsConn TlsErr r ( tls_attach_over ( dyn TlsTransport @ NtTlsStream { w } ) server_name `` ( vec_new [u] ) ? verify 1 0 deadline_ns )
    ?? r {
        T tc → {
            : *TcpConnImpl p ( __tci c )
            = . p tlsh ( _tls_word tc )
            = . p kind 1
            = . p owns T
            ^ @ !v NetErr { T 0 }
        }
        F _ → { ^ @ !v NetErr { F ( __starttls_err deadline_ns ) } }
    }
}

@ tcp_peer_addr TcpConn c → s {
    ? ( __tc_is_nt c ) { ^ ( __nt_addr . ( __tci c ) tlsh ) } {}
    ? ( __tc_tls_tt c ) { ^ ( tls_transport_peer # TlsConn ( __conn_tlsptr c ) ) } {}
    ^ ( nurl_tcp_peer_addr ( __conn_fd c ) )
}

unsafe & `c` @ nurl_tcp_local_addr i handle → sink s

// OWNED String "ip:port" of the address a listener is actually bound to,
// read fresh from getsockname. This is the counterpart of listening on
// port 0: the kernel picks the port, and this is how the process that
// asked for it finds out. Caller frees with `string_free`.
//
// Note the ownership difference from `tcp_peer_addr`, which hands back a
// BORROWED view cached on the handle: there is no cached local address,
// so this one is computed and owned. Same shape as `udp_local_addr`.
@ tcp_local_addr TcpListener l → String {
    : *TcpListenerImpl p ( __tli l )
    ? != . p nt 0 { ^ ( string_from ( __nt_addr . p nt ) ) } {}
    ^ ( string_adopt ( nurl_tcp_local_addr . p raw ) )
}

@ tcp_set_timeout TcpConn c i ms → v {
    ? ( __tc_is_nt c ) { ( nt_set_timeout ( __tc_nt c ) ms ) ^ v } {}
    ? ( __tc_tls_tt c ) { ( tls_transport_set_timeout # TlsConn ( __conn_tlsptr c ) ms ) ^ v } {}
    ( nurl_tcp_set_timeout ( __conn_fd c ) ms )
}

unsafe & `c` @ nurl_tcp_set_send_buffer i handle i bytes → i

// Request the native TCP send-buffer size in bytes (1..2147483647).
// The operating system may adjust this value. TLS uses the same underlying
// socket; providers without native buffer tuning return NetOther.
@ tcp_set_send_buffer TcpConn c i bytes → !v NetErr {
    ? ( __tc_is_nt c ) { ^ @ !v NetErr { F # NetErr NetOther } } {}
    : i error ( nurl_tcp_set_send_buffer ( __conn_fd c ) bytes )
    ? != error 0 { ^ @ !v NetErr { F ( _net_err_of error ) } } {}
    ^ @ !v NetErr { T 0 }
}

unsafe & `c` @ nurl_tcp_conn_shutdown i handle i both → v

// Shut the connection down — from any thread — without closing it: its
// read side (a read blocked on it, on a thread or a fiber, returns EOF;
// writes still go out), or with `both` its write side too (a blocked
// write fails). The connection is still closed as usual by its owner.
// The HTTP server's graceful drain ends idle keep-alive connections this
// way. Windows always shuts both sides; a provider with no way to shut a
// socket does nothing.
@ tcp_conn_shutdown TcpConn c b both → v {
    ? ( __tc_is_nt c ) { ( nt_shutdown ( __tc_nt c ) both ) ^ v } {}
    ( nurl_tcp_conn_shutdown ( __conn_fd c ) ? both 1 0 )
}

// Absolute monotonic nanoseconds; zero clears the write bound. Unlike
// the idle timeout this survives partial writes and every TLS record.
@ tcp_set_write_deadline TcpConn c i ns → v {
    ? ( __tc_is_nt c ) { ( nt_set_write_deadline ( __tc_nt c ) ns ) ^ v } {}
    ( nurl_tcp_set_write_deadline ( __conn_fd c ) ns )
}

@ tcp_write_deadline TcpConn c → i {
    ? ( __tc_is_nt c ) { ^ ( nt_write_deadline ( __tc_nt c ) ) } {}
    ^ ( nurl_tcp_write_deadline ( __conn_fd c ) )
}

// ── Reading ────────────────────────────────────────────────────────

// Issue ONE recv(2). The returned Vec[u] holds 0..max bytes. EOF is
// surfaced as `Err(NetClosed)` so empty Ok-vectors are never confused
// Pure-TLS read dispatch (kind 1 = client, kind 2 = server). Clean EOF
// (tls_read returns []) is surfaced as NetClosed to match the plain path.
@ __tls_read_net TcpConn c i max → !( Vec u ) NetErr {
    : TlsConn tc # TlsConn ( __conn_tlsptr c )
    : !( Vec u ) TlsErr r ? == . ( __tci c ) kind 2 ( tls_server_read tc max ) ( tls_read tc max )
    ?? r {
        F e → {
            : NetErr ne ?? e { TlsClosed → # NetErr NetClosed _ → # NetErr NetRead }
            ^ @ !( Vec u ) NetErr { F ne }
        }
        T v → {
            ? == ( vec_len [u] v ) 0 {
                ^ @ !( Vec u ) NetErr { F # NetErr NetClosed }
            } {}
            ^ @ !( Vec u ) NetErr { T v }
        }
    }
}

@ __tls_write_net TcpConn c ( Vec u ) bytes → !v NetErr {
    : TlsConn tc # TlsConn ( __conn_tlsptr c )
    : !v TlsErr r ? == . ( __tci c ) kind 2 ( tls_server_write tc bytes ) ( tls_write tc bytes )
    ?? r { T _ → ^ @ !v NetErr { T 0 } F _ → ^ @ !v NetErr { F ? == ( nurl_tcp_err_kind ( __conn_fd c ) ) 7 # NetErr NetTimeout # NetErr NetWrite } }
}

// Two-buffer TLS write: the record layer seals `head`‖`body` into
// records straight from the two buffers (see tls_server_write2), so the
// plaintext is never joined into one buffer first.
@ __tls_write_net2 TcpConn c ( Vec u ) head ( Vec u ) body → !v NetErr {
    : TlsConn tc # TlsConn ( __conn_tlsptr c )
    : !v TlsErr r ? == . ( __tci c ) kind 2 ( tls_server_write2 tc head body ) ( tls_write2 tc head body )
    ?? r { T _ → ^ @ !v NetErr { T 0 } F _ → ^ @ !v NetErr { F ? == ( nurl_tcp_err_kind ( __conn_fd c ) ) 7 # NetErr NetTimeout # NetErr NetWrite } }
}

// with a clean peer shutdown. Caller frees the Vec on the Ok path.
@ tcp_read_chunk TcpConn c i max → !( Vec u ) NetErr {
    ? ( __tc_is_nt c ) { ^ ( __nt_read_chunk c max ) } {}
    ? != ( __conn_tlsptr c ) 0 { ^ ( __tls_read_net c max ) } {}
    // Context-aware dispatch — see tcp_accept's note.
    : i fcur ( nurl_fiber_current )
    ? != fcur 0 { ^ ( tcp_read_chunk_async c max ) } {}
    : s rp # s . ( __tci c ) raw
    : i raw # i rp
    ? <= max 0 {
        : ( Vec u ) v ( vec_new [u] )
        ^ @ !( Vec u ) NetErr { T v }
    } {}
    : ( Vec u ) v ( vec_with_cap [u] max )
    : *u p ( vec_data [u] v )
    : s pbuf # s p
    : i n ( nurl_tcp_read raw pbuf max )
    ? < n 0 {
        : i ek ( nurl_tcp_err_kind raw )
        ^ @ !( Vec u ) NetErr { F ( _net_err_of ek ) }
    } {}
    ? == n 0 {
        ^ @ !( Vec u ) NetErr { F # NetErr NetClosed }
    } {}
    ( vec_set_len [u] v n )
    ^ @ !( Vec u ) NetErr { T v }
}

// ONE recv(2), appended IN PLACE: up to `max` bytes land directly in
// `buf`'s spare capacity (reserved here, grown at most once). This is
// tcp_read_chunk minus its per-call throwaway Vec — on the HTTP keep-
// alive hot path that per-read allocate + copy-into-carry + free pair
// is pure overhead, since every caller immediately appends the chunk
// to a connection-level buffer anyway. Context-aware like the rest of
// the family: TLS conns route through the record layer, fibers park on
// the reactor for EAGAIN, plain threads block.
//
// Ok(n) = n > 0 bytes appended. EOF is Err(NetClosed), a fiber-side
// deadline overrun Err(NetTimeout) — identical to tcp_read_chunk.
@ tcp_read_into TcpConn c ( Vec u ) buf i max → !i NetErr {
    ? <= max 0 { ^ @ !i NetErr { T 0 } } {}
    ? ( __tc_is_nt c ) { ^ ( nt_read_into ( __tc_nt c ) buf max T ) } {}
    ? != ( __conn_tlsptr c ) 0 {
        // TLS: records are opened in place in the connection's record
        // buffer and the plaintext copied once, straight into `buf`.
        : TlsConn tc # TlsConn ( __conn_tlsptr c )
        : !i TlsErr r ? == . ( __tci c ) kind 2 ( tls_server_read_into tc buf max ) ( tls_read_into tc buf max )
        ?? r {
            T n → {
                ? == n 0 { ^ @ !i NetErr { F # NetErr NetClosed } } {}
                ^ @ !i NetErr { T n }
            }
            F e → {
                : NetErr ne ?? e { TlsClosed → # NetErr NetClosed _ → # NetErr NetRead }
                ^ @ !i NetErr { F ne }
            }
        }
    } {}
    : s rp # s . ( __tci c ) raw
    : i raw # i rp
    ( vec_reserve [u] buf max )
    : i len ( vec_len [u] buf )
    : *u p ( vec_data [u] buf )
    : s pbuf # s + # i p len
    : i fcur ( nurl_fiber_current )
    ? == fcur 0 {
        : i n ( nurl_tcp_read raw pbuf max )
        ? > n 0 {
            : b _ok ( vec_set_len [u] buf + len n )
            ^ @ !i NetErr { T n }
        } {}
        ? == n 0 { ^ @ !i NetErr { F # NetErr NetClosed } } {}
        ^ @ !i NetErr { F ( _net_err_of ( nurl_tcp_err_kind raw ) ) }
    } {}
    // Fiber path: mirrors tcp_read_chunk_async (EAGAIN → park with the
    // socket's OWN deadline; see that function's timeout note).
    ( nurl_tcp_set_nonblock raw 1 )
    : i fd ( nurl_tcp_get_fd raw )
    ~ T {
        : i n ( nurl_tcp_read raw pbuf max )
        ? > n 0 {
            : b _ok ( vec_set_len [u] buf + len n )
            ^ @ !i NetErr { T n }
        } {}
        ? == n 0 { ^ @ !i NetErr { F # NetErr NetClosed } } {}
        : i ek ( nurl_tcp_err_kind raw )
        ? == ek 7 {
            : i rc ( nurl_reactor_wait_read fd ( __wait_ms raw ) )
            ? <= rc 0 { ^ @ !i NetErr { F # NetErr NetTimeout } } {}
        } {
            ^ @ !i NetErr { F ( _net_err_of ek ) }
        }
    }
    ^ @ !i NetErr { F # NetErr NetOther }
}

// tcp_read_chunk over a transport: one read into a Vec of its own.
@ __nt_read_chunk TcpConn c i max → !( Vec u ) NetErr {
    : ( Vec u ) v ( vec_with_cap [u] max )
    ?? ( nt_read_into ( __tc_nt c ) v max T ) {
        T _ → ^ @ !( Vec u ) NetErr { T v }
        F e → ^ @ !( Vec u ) NetErr { F e }
    }
}

// Queue-ready I/O: encoding and socket progress are separate. Prepared
// TLS records must leave in FIFO order and be retried by byte offset.
@ tcp_prepare_write TcpConn c ( Vec u ) bytes → !( Vec u ) NetErr {
    : i tls ( __conn_tlsptr c )
    ? == tls 0 { ^ @ !( Vec u ) NetErr { T ( bytes_slice bytes 0 ( vec_len [u] bytes ) ) } } {}
    : TlsConn state # TlsConn tls
    : !( Vec u ) TlsErr result ? == . ( __tci c ) kind 2
    ( tls_server_prepare_write state bytes ) ( tls_prepare_write state bytes )
    ?? result {
        T wire → ^ @ !( Vec u ) NetErr { T wire }
        F _ → ^ @ !( Vec u ) NetErr { F NetClosed }
    }
}

// Pair form for a queued writer: `head`‖`body` goes straight onto the end
// of `out` — appended as-is on plaintext, sealed into ≤16 KB records on
// TLS — so a frame header and its payload never meet in a scratch buffer.
@ tcp_prepare_write2_to TcpConn c ( Vec u ) out ( Vec u ) head ( Vec u ) body → !v NetErr {
    : i tls ( __conn_tlsptr c )
    ? == tls 0 {
        ( vec_extend [u] out head )
        ( vec_extend [u] out body )
        ^ @ !v NetErr { T 0 }
    } {}
    : TlsConn state # TlsConn tls
    : !v TlsErr result ? == . ( __tci c ) kind 2
    ( tls_server_prepare_write2_to state out head body ) ( tls_prepare_write2_to state out head body )
    ?? result {
        T _ → ^ @ !v NetErr { T 0 }
        F _ → ^ @ !v NetErr { F NetClosed }
    }
}

// Append source-generated TLS control records to the caller's existing
// ciphertext FIFO; returns the byte count (0 = none pending, and nothing
// is touched — plaintext connections cost a handle check). No socket I/O.
@ tcp_prepare_control_to TcpConn c ( Vec u ) out → i {
    : i tls ( __conn_tlsptr c )
    ? == tls 0 { ^ 0 } {}
    : ~ * TlsConnImpl state ( _tls_ptr # TlsConn tls )
    ? != . state closed 0 { ^ 0 } {}
    ? & == . state update_pending 0 == . state fatal_alert 0 { ^ 0 } {}
    : i before ( vec_len [u] out )
    ( _tls_control_to . state 0 out ? == . ( __tci c ) kind 2 0 1 )
    ^ - ( vec_len [u] out ) before
}

// Same, into a fresh Vec. Empty output means none pending.
@ tcp_prepare_control TcpConn c → !( Vec u ) NetErr {
    : ( Vec u ) wire ( vec_new [u] )
    : i appended ( tcp_prepare_control_to c wire )
    ^ @ !( Vec u ) NetErr { T wire }
}

@ __tcp_write_failed TcpConn c → v {
    : i tls ( __conn_tlsptr c )
    ? != tls 0 { : *TlsConnImpl state ( _tls_ptr # TlsConn tls ) = . state closed 1 } {}
}

// Positive byte count, zero would-block, or a typed terminal error. No
// blocking-mode or read-timeout changes, and no encryption on retries.
@ tcp_try_write_wire TcpConn c ( Vec u ) wire i offset → !i NetErr {
    : i size ( vec_len [u] wire )
    ? | < offset 0 > offset size { ^ @ !i NetErr { F NetOther } } {}
    ? == offset size { ^ @ !i NetErr { T 0 } } {}
    ? ( __tc_is_nt c ) { ^ ( nt_try_write ( __tc_nt c ) wire offset ) } {}
    : i raw ( __conn_fd c )
    : i wrote ( nurl_tcp_write_nowait raw # s + # i ( vec_data [u] wire ) offset - size offset )
    ? > wrote 0 { ^ @ !i NetErr { T wrote } } {}
    : i error ( nurl_tcp_err_kind raw )
    ? & == error 7 != ( nurl_tcp_write_wait_ms raw ) 0 { ^ @ !i NetErr { T 0 } } {}
    ( __tcp_write_failed c )
    ^ @ !i NetErr { F ? == wrote 0 # NetErr NetWrite ( _net_err_of error ) }
}

// Append immediately available plaintext, retaining incomplete TLS records.
// Zero means would-block; EOF is NetClosed. Control records may be consumed
// without producing plaintext, and never force a blocking read for the next.
@ tcp_try_read_into TcpConn c ( Vec u ) bytes i max → !i NetErr {
    ? <= max 0 { ^ @ !i NetErr { T 0 } } {}
    ? ( __tc_is_nt c ) { ^ ( nt_read_into ( __tc_nt c ) bytes max F ) } {}
    : i raw ( __conn_fd c )
    : i tls ( __conn_tlsptr c )
    ? != tls 0 {
        : TlsConn conn # TlsConn tls
        : *TlsConnImpl state ( _tls_ptr conn )
        : i previous . state read_nowait
        = . state read_nowait 1
        : !i TlsErr result ? == . ( __tci c ) kind 2 ( tls_server_read_into conn bytes max ) ( tls_read_into conn bytes max )
        = . state read_nowait previous
        ?? result {
            T count → {
                ? == count 0 { ^ @ !i NetErr { F NetClosed } } {}
                ^ @ !i NetErr { T count }
            }
            F error → {
                ?? error {
                    TlsRead → { ? | != . state update_pending 0 == ( nurl_tcp_err_kind raw ) 7 { ^ @ !i NetErr { T 0 } } {} }
                    TlsProtocol → { ? != . state fatal_alert 0 { ^ @ !i NetErr { T 0 } } {} }
                    TlsClosed → { ^ @ !i NetErr { F NetClosed } }
                    _ → {}
                }
                ^ @ !i NetErr { F NetRead }
            }
        }
    } {}
    ( vec_reserve [u] bytes max )
    : i length ( vec_len [u] bytes )
    : i got ( nurl_tcp_read_nowait raw # s + # i ( vec_data [u] bytes ) length max )
    ? > got 0 {
        : b sized ( vec_set_len [u] bytes + length got )
        ^ @ !i NetErr { T got }
    } {}
    ? == got 0 { ^ @ !i NetErr { F NetClosed } } {}
    : i error ( nurl_tcp_err_kind raw )
    ? == error 7 { ^ @ !i NetErr { T 0 } } {}
    ^ @ !i NetErr { F ( _net_err_of error ) }
}

@ __tcp_buffered_read TcpConn c → b {
    : i tls ( __conn_tlsptr c )
    ? == tls 0 { ^ F } {}
    : *TlsConnImpl state ( _tls_ptr # TlsConn tls )
    ? | != . state closed 0 | != . state fatal_alert 0 > ( vec_len [u] . state appbuf ) 0 { ^ T } {}
    : i size ( vec_len [u] . state rxbuf )
    ? < size 5 { ^ F } {}
    : *u data ( vec_data [u] . state rxbuf )
    ^ >= size + 5 | << # i . data 3 8 # i . data 4
}

@ tcp_wait_io TcpConn c b readable b writable i timeout_ms → i {
    ? ( __tc_is_nt c ) { ^ ( nt_wait_io ( __tc_nt c ) readable writable timeout_ms ) } {}
    ? & readable ( __tcp_buffered_read c ) { ^ 1 } {}
    : i events + ? readable 1 0 ? writable 2 0
    ? == events 0 { ^ -1 } {}
    : i raw ( __conn_fd c )
    : ~ i wait timeout_ms
    ? writable {
        : i remaining ( nurl_tcp_write_wait_ms raw )
        ? == remaining 0 { ^ 0 } {}
        ? & >= remaining 0 | < wait 0 < remaining wait { = wait remaining } {}
    } {}
    ? != ( nurl_fiber_current ) 0 {
        ^ ( nurl_reactor_wait_io ( nurl_tcp_get_fd raw ) events wait )
    } {}
    ^ ( nurl_tcp_wait_io raw events wait )
}

// Readiness permits a try-read; a TLS peer may have sent a partial record.
@ tcp_read_ready TcpConn c → b { ^ > ( tcp_wait_io c T F 0 ) 0 }

// ── Writing ────────────────────────────────────────────────────────

// Two-segment send: `b1[0..n1)` then `b2[0..n2)` through ONE
// sendmsg(2)/WSASend, returning the count written across both (short
// counts allowed; -1 = nothing written, err_kind set). With one segment
// empty it is exactly nurl_tcp_write. Declared here rather than in the
// compiler preamble, like the other stdlib-only runtime entry points.
unsafe & `c` @ nurl_tcp_write2 i conn *u b1 i n1 *u b2 i n2 → i

unsafe & `c` @ nurl_tcp_sendfile i conn i fd i off i n → i

// The one blocking send loop behind tcp_write_all, tcp_write_str and
// tcp_write_all2: writes the logical concatenation `p1[0..n1)‖p2[0..n2)`
// to the raw handle, re-pointing the pair at the unsent remainder after
// every short count. A single buffer is the pair with `n2 == 0`.
//
// write(2) on a blocking socket is NOT all-or-nothing: it returns as soon
// as it has copied SOME bytes into the send buffer, and with SO_SNDTIMEO
// set (tcp_set_timeout) it returns a short count when the timer fires with
// the peer's window full. Writing once and reporting success left the rest
// of the buffer unsent, and — because the frame header had already
// announced the full length — DESYNCED the stream: the peer's next
// read_exact spliced the tail of one frame onto the head of the next and
// handed up a frame of the right length with the wrong bytes. Loopback
// hides it (the receiver drains as fast as the sender fills, so one write
// takes everything); a real network path with an autotuned 64 KiB initial
// send buffer does not, past a few hundred KiB. Loop until it is all gone,
// exactly as the async twin below does.
@ __tcp_write_pair_sync i raw s p1 i n1 s p2 i n2 → !v NetErr {
    : i total + n1 n2
    ? <= total 0 { ^ @ !v NetErr { T 0 } } {}
    : ~ i sent 0
    ~ < sent total {
        : ~ s a p1
        : ~ i an - n1 sent
        : ~ i bn n2
        ? < sent n1 { = a # s + # i p1 sent } {
            = a # s + # i p2 - sent n1
            = an - total sent
            = bn 0
        }
        : i wn ( nurl_tcp_write2 raw a an p2 bn )
        ? > wn 0 { = sent + sent wn } {
            : i ek ( nurl_tcp_err_kind raw )
            ^ @ !v NetErr { F ? == wn 0 # NetErr NetWrite ( _net_err_of ek ) }
        }
    }
    ^ @ !v NetErr { T 0 }
}

@ tcp_write_all TcpConn c ( Vec u ) bytes → !v NetErr {
    ? ( __tc_is_nt c ) { ^ ( nt_write ( __tc_nt c ) bytes ) } {}
    ? != ( __conn_tlsptr c ) 0 { ^ ( __tls_write_net c bytes ) } {}
    // Context-aware dispatch — see tcp_accept's note.
    : i fcur ( nurl_fiber_current )
    ? != fcur 0 { ^ ( tcp_write_all_async c bytes ) } {}
    : s rp # s . ( __tci c ) raw
    : i raw # i rp
    : *u p ( vec_data [u] bytes )
    ^ ( __tcp_write_pair_sync raw # s p ( vec_len [u] bytes ) # s 0 0 )
}

// `len` bytes of `f` from offset `off` to the connection. On a plain
// TCP connection, and on a TLS one whose write side the kernel seals
// (kTLS, tls_ktls), the kernel copies them straight from the page cache
// (sendfile(2)) — the bytes never enter this process, and under kTLS
// the records are sealed on the way out. A TLS connection sealing its
// own records, or a platform without sendfile, reads the file in 64 KB
// slices into one buffer and writes them through tcp_write_all. Ok(the
// bytes sent: `len`, fewer when the file ends first).
@ tcp_sendfile TcpConn c PFile f i off i len → !i NetErr {
    ? <= len 0 { ^ @ !i NetErr { T 0 } } {}
    : i tls ( __conn_tlsptr c )
    // Another transport has no kernel to copy from the page cache: it
    // takes the read-and-write path below.
    : b kernel ? ( __tc_is_nt c ) F ? == tls 0 T ( tls_ktls_tx_ready # TlsConn tls )
    : ~ i sent 0
    ? kernel {
        // The socket's runtime handle: a TLS connection's own (__conn_fd),
        // not TcpConnImpl.raw, which only a plaintext connection fills.
        : i raw ( __conn_fd c )
        : i fd ( _pfile_fd f )
        : b on_fiber != ( nurl_fiber_current ) 0
        ? on_fiber { ( nurl_tcp_set_nonblock raw 1 ) } {}
        ~ < sent len {
            : i n ( nurl_tcp_sendfile raw fd + off sent - len sent )
            ? > n 0 { = sent + sent n } {
                ? == n 0 { ^ @ !i NetErr { T sent } } {}
                ? == n -2 { break } {}
                : i error ( nurl_tcp_err_kind raw )
                ? | != error 7 ! on_fiber { ^ @ !i NetErr { F ( _net_err_of error ) } } {}
                : i remaining ( nurl_tcp_write_wait_ms raw )
                ? == remaining 0 { ^ @ !i NetErr { F NetTimeout } } {}
                ? <= ( nurl_reactor_wait_write ( nurl_tcp_get_fd raw ) remaining ) 0 { ^ @ !i NetErr { F NetTimeout } } {}
            }
        }
        ? >= sent len { ^ @ !i NetErr { T sent } } {}
    } {}
    // Read-and-write: one 64 KB buffer reused for every slice.
    : ( Vec u ) buf ( vec_with_cap [u] 65536 )
    ~ < sent len {
        : i want ? < - len sent 65536 - len sent 65536
        ( vec_clear [u] buf )
        ?? ( pfile_read_vec_into f buf + off sent want ) {
            T got → {
                ? == got 0 { ^ @ !i NetErr { T sent } } {}
                ?? ( tcp_write_all c buf ) { T _ → {} F e → { ^ @ !i NetErr { F e } } }
                = sent + sent got
            }
            F _ → { ^ @ !i NetErr { F NetRead } }
        }
    }
    ^ @ !i NetErr { T sent }
}

// Write `head` then `body` as ONE logical message. On the plaintext
// path both segments leave in a single sendmsg(2), so a caller that
// keeps a message head and its payload in separate buffers (the HTTP
// server: serialised head in the connection's wire buffer, body still
// in the response) pays neither the concat copy nor a second syscall.
// On TLS the record layer seals the pair straight from the two buffers.
// Both inputs are BORROWED, as for tcp_write_all.
@ tcp_write_all2 TcpConn c ( Vec u ) head ( Vec u ) body → !v NetErr {
    ? ( __tc_is_nt c ) { ^ ( nt_write_all ( __tc_nt c ) head body ) } {}
    ? != ( __conn_tlsptr c ) 0 { ^ ( __tls_write_net2 c head body ) } {}
    : s rp # s . ( __tci c ) raw
    : i raw # i rp
    : *u hp ( vec_data [u] head )
    : i hn ( vec_len [u] head )
    : *u bp ( vec_data [u] body )
    : i bn ( vec_len [u] body )
    : i fcur ( nurl_fiber_current )
    ? != fcur 0 { ^ ( __tcp_write_pair_async raw # s hp hn # s bp bn ) } {}
    ^ ( __tcp_write_pair_sync raw # s hp hn # s bp bn )
}

// Convenience: write a NUL-terminated `s` (the typical HTTP header /
// status-line case). The bytes [0..len) are sent — the trailing NUL is
// NOT transmitted.
@ tcp_write_str TcpConn c s text → !v NetErr {
    ? ( __tc_is_nt c ) { ^ ( nt_write ( __tc_nt c ) ( bytes_from_str text ) ) } {}
    ? != ( __conn_tlsptr c ) 0 {
        : ( Vec u ) b ( bytes_from_str text )
        : !v NetErr r ( __tls_write_net c b )
        ^ r
    } {}
    : s rp # s . ( __tci c ) raw
    : i raw # i rp
    // Same short-write rule as tcp_write_all — see __tcp_write_pair_sync.
    // Status lines and headers are small enough that one write almost
    // always takes them, which is exactly why a partial one here would be
    // a rare, load-dependent corruption rather than an outright failure.
    ^ ( __tcp_write_pair_sync raw text ( nurl_str_len text ) # s 0 0 )
}

// ── Phase 6 — fiber-aware async TCP wrappers ───────────────────────
//
// These mirror the sync API one-to-one. Inside a fiber, an EAGAIN /
// EWOULDBLOCK from the underlying socket is converted into a park on
// the reactor; the worker pthread is NOT blocked. From outside a
// fiber (e.g. main thread with no scheduler attached), the reactor
// returns -1 immediately and the async wrapper falls back to the
// blocking variant transparently.
//
// First call on a (listener / conn) handle flips its fd to
// O_NONBLOCK via `nurl_tcp_set_nonblock` — subsequent sync calls on
// the SAME handle will start surfacing NetTimeout on no-data; mixing
// sync + async on one handle is not supported.

$ `stdlib/std/async_ffi.nu`

// nurl_tcp_get_fd / nurl_tcp_timeout_ms / nurl_tcp_set_nonblock are
// declared in async_ffi.nu (imported above) so the pure TLS stack can
// use them too without an import cycle.

unsafe & `c` @ nurl_tcp_ref i handle → v

unsafe & `c` @ nurl_tcp_unref i handle → v

// Take/drop an extra reference on a listener handle so it survives a
// concurrent `tcp_close_listener` (e.g. `server_stop` fired from another
// thread). `server_run_async` retains the listener for the life of its
// accept fiber and releases it once the fiber has exited — without this,
// closing the listener mid-accept frees the struct out from under the
// parked fiber (use-after-free). Each retain MUST be paired with one
// release.
@ tcp_listener_retain TcpListener l → v {
    : s rp # s . ( __tli l ) raw
    ( nurl_tcp_ref # i rp )
}

@ tcp_listener_release TcpListener l → v {
    : s rp # s . ( __tli l ) raw
    ( nurl_tcp_unref # i rp )
}

// Set non-blocking mode (idempotent). Used internally by the async
// wrappers on first call. Exposed in case callers want to manage the
// mode explicitly (e.g. a custom proactor loop).
@ tcp_set_nonblock_listener TcpListener l i on → v {
    : s rp # s . ( __tli l ) raw
    : i raw # i rp
    ( nurl_tcp_set_nonblock raw on )
}

@ tcp_set_nonblock_conn TcpConn c i on → v {
    ? ( __tc_is_nt c ) { ( nt_set_nonblock ( __tc_nt c ) != on 0 ) ^ v } {}
    : s rp # s . ( __tci c ) raw
    : i raw # i rp
    ( nurl_tcp_set_nonblock raw on )
}

// The deadline to hand the reactor for this socket: what the caller set
// with `tcp_set_timeout`, or −1 ("no deadline") when they set none. The
// reactor spells "for ever" as −1 and 0 would mean "do not wait at all",
// so the translation lives here rather than at four call sites.
@ __wait_ms i raw → i {
    : i ms ( nurl_tcp_timeout_ms raw )
    ^ ? > ms 0 ms - 0 1
}

// Non-blocking accept. Loops: try accept; if NetTimeout (EAGAIN),
// wait_readable on listener fd, retry. On non-fiber callers,
// wait_readable returns -1 immediately and we fall back to the
// existing sync `tcp_accept` (which blocks on the kernel).
@ tcp_accept_async TcpListener l → !TcpConn NetErr {
    // (A transport's accept is context-aware already.)
    ? != . ( __tli l ) nt 0 { ^ ( tcp_accept_transport l ) } {}
    : s lrp # s . ( __tli l ) raw
    : i lraw # i lrp
    ( nurl_tcp_set_nonblock lraw 1 )
    : i fd ( nurl_tcp_get_fd lraw )
    ~ T {
        : i craw ( nurl_tcp_accept lraw )
        ? == craw 0 { ^ @ !TcpConn NetErr { F # NetErr NetOther } } {}
        : i ek ( nurl_tcp_err_kind craw )
        ? == ek 0 {
            ^ @ !TcpConn NetErr { T ( tcp_conn_adopt craw ) }
        } {
            ( nurl_tcp_close craw )
            ? == ek 7 {  // NetTimeout / EAGAIN
                // ACCEPT KEEPS WAITING. `tcp_set_timeout` is about a
                // CONNECTION's reads and writes; a listener has no such
                // deadline, and a server loop reads "the accept ended"
                // as "we were stopped" — report a timeout there and
                // every clean shutdown becomes an error. The accept wait
                // runs this fiber as soon as the listener is ready, ahead
                // of everything queued: accepting is how the connections
                // waiting in the kernel enter the service order, so it
                // does not wait its turn behind work that became runnable
                // after they arrived (Admission, stdlib/runtime_ffi.c).
                : i rc ( nurl_reactor_wait_accept fd - 0 1 )
                // wait_readable returns -1 outside a fiber; in that
                // case the sync accept already blocked, so EAGAIN
                // shouldn't recur — bail to NetAccept.
                ? < rc 0 { ^ @ !TcpConn NetErr { F # NetErr NetAccept } } {}
            } {
                ^ @ !TcpConn NetErr { F ( _net_err_of ek ) }
            }
        }
    }
    ^ @ !TcpConn NetErr { F # NetErr NetOther }
}

// Non-blocking single recv. Same shape as tcp_read_chunk; loops on
// EAGAIN via the reactor.
@ tcp_read_chunk_async TcpConn c i max → !( Vec u ) NetErr {
    ? ( __tc_is_nt c ) { ^ ( __nt_read_chunk c max ) } {}
    : s rp # s . ( __tci c ) raw
    : i raw # i rp
    ( nurl_tcp_set_nonblock raw 1 )
    : i fd ( nurl_tcp_get_fd raw )
    ? <= max 0 {
        : ( Vec u ) v0 ( vec_new [u] )
        ^ @ !( Vec u ) NetErr { T v0 }
    } {}
    : ( Vec u ) v ( vec_with_cap [u] max )
    : *u p ( vec_data [u] v )
    : s pbuf # s p
    ~ T {
        : i n ( nurl_tcp_read raw pbuf max )
        ? > n 0 {
            ( vec_set_len [u] v n )
            ^ @ !( Vec u ) NetErr { T v }
        } {}
        ? == n 0 {
            ^ @ !( Vec u ) NetErr { F # NetErr NetClosed }
        } {}
        : i ek ( nurl_tcp_err_kind raw )
        ? == ek 7 {
            // The socket's OWN deadline, not "for ever". A blocking read
            // gets it from SO_RCVTIMEO; a parked fiber has to be told,
            // and a hard-coded −1 here silently discarded every
            // `tcp_set_timeout` the caller had made. It cost a
            // distributed node its startup: a relay read that should
            // have given up after 150 ms waited for a message that was
            // never going to come, and only on a runtime where threads
            // ARE fibers — which is why no hosted test saw it.
            : i rc ( nurl_reactor_wait_read fd ( __wait_ms raw ) )
            ? < rc 0 {
                ^ @ !( Vec u ) NetErr { F # NetErr NetTimeout }
            } {}
            ? == rc 0 {
                ^ @ !( Vec u ) NetErr { F # NetErr NetTimeout }
            } {}
        } {
            ^ @ !( Vec u ) NetErr { F ( _net_err_of ek ) }
        }
    }
    ^ @ !( Vec u ) NetErr { F # NetErr NetOther }
}

// Non-blocking write-all. Loops issuing send(2) until the full Vec
// is delivered, parking on wait_writable when the kernel returns
// EAGAIN.
@ tcp_write_all_async TcpConn c ( Vec u ) bytes → !v NetErr {
    ? ( __tc_is_nt c ) { ^ ( nt_write ( __tc_nt c ) bytes ) } {}
    : s rp # s . ( __tci c ) raw
    : i raw # i rp
    : *u p ( vec_data [u] bytes )
    ^ ( __tcp_write_pair_async raw # s p ( vec_len [u] bytes ) # s 0 0 )
}

// The non-blocking twin of __tcp_write_pair_sync: same pair-of-segments
// contract, parking the fiber on the reactor instead of blocking in the
// kernel when the socket would block.
@ __tcp_write_pair_async i raw s p1 i n1 s p2 i n2 → !v NetErr {
    ( nurl_tcp_set_nonblock raw 1 )
    : i fd ( nurl_tcp_get_fd raw )
    : i total + n1 n2
    ? <= total 0 { ^ @ !v NetErr { T 0 } } {}
    : ~ i sent 0
    // A timeout ends this write even after partial progress. The caller
    // must retire the connection rather than reuse a truncated frame.
    ~ < sent total {
        : ~ s a p1
        : ~ i an - n1 sent
        : ~ i bn n2
        ? < sent n1 { = a # s + # i p1 sent } {
            = a # s + # i p2 - sent n1
            = an - total sent
            = bn 0
        }
        : i n ( nurl_tcp_write2 raw a an p2 bn )
        ? > n 0 {
            = sent + sent n
        } {
            : i error ( nurl_tcp_err_kind raw )
            ? & < n 0 != error 7 { ^ @ !v NetErr { F ( _net_err_of error ) } } {}
            : i remaining ( nurl_tcp_write_wait_ms raw )
            ? == remaining 0 { ^ @ !v NetErr { F NetTimeout } } {}
            : i ready ( nurl_reactor_wait_write fd remaining )
            ? <= ready 0 { ^ @ !v NetErr { F NetTimeout } } {}
        }
    }
    ^ @ !v NetErr { T 0 }
}
