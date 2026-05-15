// stdlib/std/net.nu — TCP sockets (HTTP server foundation)
//
// Wraps the runtime bridge in stdlib/runtime.c (§18). Single-threaded
// blocking sockets — Phase 1 of HTTP_SERVER_PLAN.md. Concurrency
// (thread-per-connection or epoll) is layered on top in Phase 5.
//
// API (this revision):
//
//   ( tcp_listen          s host i port )                   → ! TcpListener NetErr
//   ( tcp_listen_with_backlog s host i port i backlog )     → ! TcpListener NetErr
//   ( tcp_accept          TcpListener l )                   → ! TcpConn NetErr
//   ( tcp_read_chunk      TcpConn c i max )                 → ! ( Vec u ) NetErr
//   ( tcp_write_all       TcpConn c ( Vec u ) bytes )       → ! v NetErr
//   ( tcp_write_str       TcpConn c s text )                → ! v NetErr
//   ( tcp_close_listener  TcpListener l )                   → v
//   ( tcp_close_conn      TcpConn c )                       → v
//   ( tcp_peer_addr       TcpConn c )                       → s    BORROWED view
//   ( tcp_set_timeout     TcpConn c i ms )                  → v
//   ( net_err_name        NetErr e )                        → s    diagnostic
//
// Memory model:
//
//   * Both TcpListener and TcpConn are opaque single-field handles
//     wrapping a heap NurlTcp pointer (the runtime owns the FD + a
//     sideband err_kind). The handle is moved into the wrapper struct
//     and OUT again on accept; the caller must `tcp_close_*` exactly
//     once per Result-Ok path.
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
//   NetOther        8   anything else / unsupported target (WASI)
//   NetTlsCtxInit   9   SSL_CTX_new failed OR build lacks openssl
//   NetTlsCertLoad  10  SSL_CTX_use_certificate_chain_file failed
//   NetTlsKeyLoad   11  SSL_CTX_use_PrivateKey_file / check_private_key failed
//   NetTlsHandshake 12  SSL_accept failed on a freshly-accepted conn
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
//   - Non-blocking / async I/O — Phase 5 brings threads instead.
//   - TLS — Phase 9 (libssl wrap).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`

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
: TcpListener { s raw }
: TcpConn { s raw }

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

// Internal: classify the runtime err_kind into a NetErr variant.
// `deflt` is the variant to return for any unmapped err_kind (kept
// caller-controlled because read/write/listen each have a different
// "natural" fallback).
@ __net_err_of i ek → NetErr {
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
@ tcp_listen_with_backlog s host i port i backlog → !TcpListener NetErr {
    : i raw ( nurl_tcp_listen host port backlog )
    ? == raw 0 { ^ @ !TcpListener NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind raw )
    ? != ek 0 {
        ( nurl_tcp_close raw )
        ^ @ !TcpListener NetErr { F ( __net_err_of ek ) }
    } {}
    : s rp # s raw
    : TcpListener l @ TcpListener { rp }
    ^ @ !TcpListener NetErr { T l }
}

// Convenience: same as tcp_listen_with_backlog with backlog = 128.
@ tcp_listen s host i port → !TcpListener NetErr {
    ^ ( tcp_listen_with_backlog host port 128 )
}

// TLS listener — binds and starts listening exactly like tcp_listen,
// then configures an SSL_CTX from the given PEM cert + private key
// files. On accept the per-conn SSL handshake runs transparently;
// the returned TcpConn is polymorphic — `tcp_read_chunk` /
// `tcp_write_all` dispatch via libssl underneath, so HttpServer
// (and any other code that consumed TcpConn) gets HTTPS without
// changes. Cert and key are loaded once at listener creation; v1
// has no SNI, no ALPN, no client-cert-auth, no live cert reload.
//
// Build-time dependency: openssl detected via pkg-config in build.sh.
// When absent, every call here returns NetTlsCtxInit unconditionally.
@ tcp_listen_tls_with_backlog s host i port i backlog s cert_path s key_path → !TcpListener NetErr {
    : i raw ( nurl_tcp_listen_tls host port backlog cert_path key_path )
    ? == raw 0 { ^ @ !TcpListener NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind raw )
    ? != ek 0 {
        ( nurl_tcp_close raw )
        ^ @ !TcpListener NetErr { F ( __net_err_of ek ) }
    } {}
    : s rp # s raw
    : TcpListener l @ TcpListener { rp }
    ^ @ !TcpListener NetErr { T l }
}

@ tcp_listen_tls s host i port s cert_path s key_path → !TcpListener NetErr {
    ^ ( tcp_listen_tls_with_backlog host port 128 cert_path key_path )
}

@ tcp_close_listener TcpListener l → v {
    : s rp . l raw
    : i raw # i rp
    ( nurl_tcp_close raw )
}

// Soft-shutdown: close the underlying socket but KEEP the handle's
// runtime struct alive. Used by `server_run_pool`'s shutdown thread —
// every worker blocked in `tcp_accept` wakes up with a NetClosed /
// NetAccept error and proceeds to read `h->err_kind` as part of its
// normal exit. Calling `tcp_close_listener` here would race with
// those reads (use-after-free observed empirically as ~40% SIGSEGV
// at exit on Windows). Pair this with a final `tcp_close_listener`
// after every worker has joined to release the runtime struct.
@ tcp_shutdown_listener TcpListener l → v {
    : s rp . l raw
    : i raw # i rp
    ( nurl_tcp_shutdown raw )
}

// ── Connection acceptance ──────────────────────────────────────────

@ tcp_accept TcpListener l → !TcpConn NetErr {
    : s lrp . l raw
    : i lraw # i lrp
    : i craw ( nurl_tcp_accept lraw )
    ? == craw 0 { ^ @ !TcpConn NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind craw )
    ? != ek 0 {
        ( nurl_tcp_close craw )
        ^ @ !TcpConn NetErr { F ( __net_err_of ek ) }
    } {}
    : s crp # s craw
    : TcpConn c @ TcpConn { crp }
    ^ @ !TcpConn NetErr { T c }
}

@ tcp_close_conn TcpConn c → v {
    : s rp . c raw
    : i raw # i rp
    ( nurl_tcp_close raw )
}

@ tcp_peer_addr TcpConn c → s {
    : s rp . c raw
    : i raw # i rp
    ^ ( nurl_tcp_peer_addr raw )
}

@ tcp_set_timeout TcpConn c i ms → v {
    : s rp . c raw
    : i raw # i rp
    ( nurl_tcp_set_timeout raw ms )
}

// ── Reading ────────────────────────────────────────────────────────

// Issue ONE recv(2). The returned Vec[u] holds 0..max bytes. EOF is
// surfaced as `Err(NetClosed)` so empty Ok-vectors are never confused
// with a clean peer shutdown. Caller frees the Vec on the Ok path.
@ tcp_read_chunk TcpConn c i max → !( Vec u ) NetErr {
    : s rp . c raw
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
        ( vec_free [u] v )
        : i ek ( nurl_tcp_err_kind raw )
        ^ @ !( Vec u ) NetErr { F ( __net_err_of ek ) }
    } {}
    ? == n 0 {
        ( vec_free [u] v )
        ^ @ !( Vec u ) NetErr { F # NetErr NetClosed }
    } {}
    ( vec_set_len [u] v n )
    ^ @ !( Vec u ) NetErr { T v }
}

// ── Writing ────────────────────────────────────────────────────────

@ tcp_write_all TcpConn c ( Vec u ) bytes → !v NetErr {
    : s rp . c raw
    : i raw # i rp
    : i n ( vec_len [u] bytes )
    ? <= n 0 { ^ @ !v NetErr { T 0 } } {}
    : *u p ( vec_data [u] bytes )
    : s pbuf # s p
    : i wn ( nurl_tcp_write raw pbuf n )
    ? < wn 0 {
        : i ek ( nurl_tcp_err_kind raw )
        ^ @ !v NetErr { F ( __net_err_of ek ) }
    } {}
    ^ @ !v NetErr { T 0 }
}

// Convenience: write a NUL-terminated `s` (the typical HTTP header /
// status-line case). The bytes [0..len) are sent — the trailing NUL is
// NOT transmitted.
@ tcp_write_str TcpConn c s text → !v NetErr {
    : s rp . c raw
    : i raw # i rp
    : i n ( nurl_str_len text )
    ? <= n 0 { ^ @ !v NetErr { T 0 } } {}
    : i wn ( nurl_tcp_write raw text n )
    ? < wn 0 {
        : i ek ( nurl_tcp_err_kind raw )
        ^ @ !v NetErr { F ( __net_err_of ek ) }
    } {}
    ^ @ !v NetErr { T 0 }
}
