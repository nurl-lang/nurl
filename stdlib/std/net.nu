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
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/tls_server.nu`
$ `stdlib/std/pkey.nu`

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
// A TLS listener carries the loaded leaf-cert DER + EC P-256 private
// scalar so each accept can run the pure handshake (is_tls = 1). They are
// held as raw malloc'd (ptr, len) pairs — NOT Vec fields — because a
// value struct returned with owned-Vec fields is auto-dropped at the
// constructing function's exit (a borrowck escape gap), which would free
// the buffers out from under the listener.
: TcpListener { s raw i is_tls i certp i certlen i privp i privlen }
// kind: 0 = plaintext (raw is the runtime socket handle), 1 = pure TLS
// client, 2 = pure TLS server. For kinds 1/2 `tlsh` is the *TlsConn (as
// i64) and reads/writes dispatch to the pure stack.
: TcpConn { s raw i kind i tlsh }

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
    : TcpListener l @ TcpListener { rp 0 0 0 0 0 }
    ^ @ !TcpListener NetErr { T l }
}

// malloc a copy of `v`'s bytes; returns the pointer as i64 (0 if empty).
@ __net_dup ( Vec u ) v → i {
    : i n ( vec_len [u] v )
    ? <= n 0 { ^ 0 } {}
    : s buf # s ( malloc n )
    ( nurl_memcpy # *u buf ( vec_data [u] v ) n )
    ^ # i buf
}

// Build a fresh Vec view over a raw (ptr, len) cert/key blob.
@ __net_vecview i ptr i len → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ? > len 0 { ( bytes_extend_raw v # s ptr len ) } {}
    ^ v
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
// Load the leaf-cert DER + EC P-256 private scalar from PEM files for a
// pure-TLS listener. The cert PEM's first block is taken as the leaf.
@ __load_tls_creds s cert_path s key_path ( Vec u ) cert_out ( Vec u ) priv_out → i {
    : !( Vec u ) ParseErr cr ?? ( read_file cert_path ) {
        T pem → ( pem_to_der ( string_data pem ) )
        F _ → @ !( Vec u ) ParseErr { F @ ParseErr { BadFormat } }
    }
    ?? cr { T der → { ( bytes_extend_bytes cert_out der ) ( vec_free [u] der ) } F _ → ^ 10 }
    : !( Vec u ) ParseErr kr ?? ( read_file key_path ) {
        T pem → ( ec_p256_priv_from_pem ( string_data pem ) )
        F _ → @ !( Vec u ) ParseErr { F @ ParseErr { BadFormat } }
    }
    ?? kr { T sc → { ( bytes_extend_bytes priv_out sc ) ( vec_free [u] sc ) } F _ → ^ 11 }
    ^ 0
}

@ tcp_listen_tls_with_backlog s host i port i backlog s cert_path s key_path → !TcpListener NetErr {
    : ( Vec u ) cert ( vec_new [u] )
    : ( Vec u ) priv ( vec_new [u] )
    : i lr ( __load_tls_creds cert_path key_path cert priv )
    ? != lr 0 {
        ( vec_free [u] cert ) ( vec_free [u] priv )
        ^ @ !TcpListener NetErr { F ( __net_err_of lr ) }
    } {}
    : i raw ( nurl_tcp_listen host port backlog )
    ? == raw 0 { ( vec_free [u] cert ) ( vec_free [u] priv ) ^ @ !TcpListener NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind raw )
    ? != ek 0 {
        ( nurl_tcp_close raw ) ( vec_free [u] cert ) ( vec_free [u] priv )
        ^ @ !TcpListener NetErr { F ( __net_err_of ek ) }
    } {}
    // Copy cert/key into raw heap buffers, then drop the Vecs.
    : i certp ( __net_dup cert )
    : i certlen ( vec_len [u] cert )
    : i privp ( __net_dup priv )
    : i privlen ( vec_len [u] priv )
    ( vec_free [u] cert )
    ( vec_free [u] priv )
    : s rp # s raw
    ^ @ !TcpListener NetErr { T @ TcpListener { rp 1 certp certlen privp privlen } }
}

@ tcp_listen_tls s host i port s cert_path s key_path → !TcpListener NetErr {
    ^ ( tcp_listen_tls_with_backlog host port 128 cert_path key_path )
}

// TLS listener with ALPN. The pure handshake does not yet advertise ALPN,
// so the protocol list is accepted for source compatibility but ignored
// (clients negotiate nothing → fall back to HTTP/1.1). ALPN is a planned
// addition to the pure stack.
@ tcp_listen_tls_with_alpn s host i port i backlog s cert_path s key_path s alpn_protocols → !TcpListener NetErr {
    ^ ( tcp_listen_tls_with_backlog host port backlog cert_path key_path )
}

// Read the negotiated ALPN protocol off an accepted TLS conn. The pure
// stack does not negotiate ALPN yet, so this returns "".
@ tcp_alpn_protocol TcpConn c → String {
    ^ ( string_new )
}

// Open a verified (or, with verify = 0, encrypted-only) pure-TLS client
// connection. Returns a polymorphic TcpConn (kind 1) whose reads/writes
// dispatch to the pure client stack.
@ tcp_connect_tls s host i port s server_name i verify → !TcpConn NetErr {
    : i raw ( nurl_tcp_connect host port )
    ? <= raw 0 { ^ @ !TcpConn NetErr { F # NetErr NetTlsHandshake } } {}
    : !*TlsConn TlsErr r ? != verify 0 ( tls_attach_verify raw server_name ) ( tls_attach raw server_name )
    ?? r {
        F _ → ^ @ !TcpConn NetErr { F # NetErr NetTlsHandshake }
        T tc → ^ @ !TcpConn NetErr { T @ TcpConn { # s 0 1 # i tc } }
    }
}

// Register a per-hostname cert/key pair on a TLS listener for Server
// Name Indication (RFC 6066 §3). The cert presented to the client is
// selected at handshake time based on the client's SNI extension:
// matching hostname → its dedicated SSL_CTX; no match → falls through
// to the listener's default cert. May be called repeatedly; in-flight
// connections are unaffected. Idempotent on re-add (replaces the
// stored cert/key for an existing hostname). Required for multi-tenant
// HTTPS where one listener serves several virtual hosts.
@ tcp_tls_add_sni TcpListener l s hostname s cert_path s key_path → !v NetErr {
    : s rp . l raw
    : i raw # i rp
    : i rc ( nurl_tcp_tls_add_sni raw hostname cert_path key_path )
    ? != 0 rc {
        ^ @ !v NetErr { F ( __net_err_of rc ) }
    } {}
    ^ @ !v NetErr { T 0 }
}

// Reload the cert/key on a live TLS listener without dropping pending
// connections. `hostname` selects the target:
//   * empty string → the listener's DEFAULT cert (set at listen time)
//   * any other value → the matching SNI entry (Err if not registered)
// Implementation: build a fresh SSL_CTX from the new cert/key, swap
// it in atomically under a per-listener mutex, and SSL_CTX_free the
// old one. OpenSSL refcounts SSL_CTX internally, so any in-flight
// SSL_read / SSL_write on the old ctx survives until close. Standard
// use case: Let's Encrypt cert rotation triggered from a control
// endpoint or SIGHUP handler.
@ tcp_tls_reload TcpListener l s hostname s cert_path s key_path → !v NetErr {
    : s rp . l raw
    : i raw # i rp
    : i rc ( nurl_tcp_tls_reload raw hostname cert_path key_path )
    ? != 0 rc {
        ^ @ !v NetErr { F ( __net_err_of rc ) }
    } {}
    ^ @ !v NetErr { T 0 }
}

// Require (mTLS) or request (opportunistic) client-cert authentication.
// `ca_bundle_path` points to a PEM file with the trust roots used to
// verify peer certificates. When `strict` is true, the handshake fails
// outright if the client doesn't present a cert; when false, the
// handshake completes regardless and the application reads
// `tcp_peer_cert_subject` to decide what to do.
@ tcp_tls_require_client_cert TcpListener l s ca_bundle_path b strict → !v NetErr {
    : s rp . l raw
    : i raw # i rp
    : i rc ( nurl_tcp_tls_require_client_cert raw ca_bundle_path ? strict 1 0 )
    ? != 0 rc {
        ^ @ !v NetErr { F ( __net_err_of rc ) }
    } {}
    ^ @ !v NetErr { T 0 }
}

// Read the peer's certificate Distinguished Name (OpenSSL one-line
// format, e.g. "/CN=client.example.com/O=Acme/C=US") off a completed
// TLS conn. Empty when no cert was presented OR the conn is non-TLS.
// Caller compares against an expected allow-list — this is the
// primary identity hook for mTLS-authenticated requests.
// Peer certificate subject. The pure TLS stack verifies the chain during
// the handshake but does not expose the subject string, so this returns
// "" (client-cert inspection is not supported on the pure path).
@ tcp_peer_cert_subject TcpConn c → String {
    ^ ( string_new )
}

@ tcp_close_listener TcpListener l → v {
    ( nurl_tcp_close # i . l raw )
    ? != . l is_tls 0 {
        ? != . l certp 0 { ( nurl_free # s . l certp ) } {}
        ? != . l privp 0 { ( nurl_free # s . l privp ) } {}
    } {}
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

// The fd backing a TcpConn — the runtime handle for plaintext, or the
// pure TLS conn's socket fd for kinds 1/2.
@ __conn_fd TcpConn c → i {
    ? != . c kind 0 {
        : *TlsConn tc # *TlsConn . c tlsh
        ^ . tc fd
    } {}
    ^ # i . c raw
}

@ tcp_accept TcpListener l → !TcpConn NetErr {
    // Context-aware: on a fiber, dispatch to the async path so the worker
    // pthread stays free while we wait. TLS listeners take the blocking
    // path (the pure handshake is synchronous).
    ? == . l is_tls 0 {
        : i fcur ( nurl_fiber_current )
        ? != fcur 0 { ^ ( tcp_accept_async l ) } {}
    } {}
    : i lraw # i . l raw
    : i craw ( nurl_tcp_accept lraw )
    ? == craw 0 { ^ @ !TcpConn NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind craw )
    ? != ek 0 {
        ( nurl_tcp_close craw )
        ^ @ !TcpConn NetErr { F ( __net_err_of ek ) }
    } {}
    ? != . l is_tls 0 {
        : ( Vec u ) cert ( __net_vecview . l certp . l certlen )
        : ( Vec u ) priv ( __net_vecview . l privp . l privlen )
        : !*TlsConn TlsErr r ( tls_accept craw cert priv )
        ( vec_free [u] cert )
        ( vec_free [u] priv )
        ?? r {
            F _ → ^ @ !TcpConn NetErr { F # NetErr NetTlsHandshake }
            T tc → ^ @ !TcpConn NetErr { T @ TcpConn { # s 0 2 # i tc } }
        }
    } {}
    : TcpConn c @ TcpConn { # s craw 0 0 }
    ^ @ !TcpConn NetErr { T c }
}

@ tcp_close_conn TcpConn c → v {
    ? != . c kind 0 { ( tls_close # *TlsConn . c tlsh ) } { ( nurl_tcp_close # i . c raw ) }
}

@ tcp_peer_addr TcpConn c → s {
    ^ ( nurl_tcp_peer_addr ( __conn_fd c ) )
}

@ tcp_set_timeout TcpConn c i ms → v {
    ( nurl_tcp_set_timeout ( __conn_fd c ) ms )
}

// ── Reading ────────────────────────────────────────────────────────

// Issue ONE recv(2). The returned Vec[u] holds 0..max bytes. EOF is
// surfaced as `Err(NetClosed)` so empty Ok-vectors are never confused
// Pure-TLS read dispatch (kind 1 = client, kind 2 = server). Clean EOF
// (tls_read returns []) is surfaced as NetClosed to match the plain path.
@ __tls_read_net TcpConn c i max → !( Vec u ) NetErr {
    : *TlsConn tc # *TlsConn . c tlsh
    : !( Vec u ) TlsErr r ? == . c kind 2 ( tls_server_read tc max ) ( tls_read tc max )
    ?? r {
        F e → {
            : NetErr ne ?? e { TlsClosed → # NetErr NetClosed _ → # NetErr NetRead }
            ^ @ !( Vec u ) NetErr { F ne }
        }
        T v → {
            ? == ( vec_len [u] v ) 0 {
                ( vec_free [u] v )
                ^ @ !( Vec u ) NetErr { F # NetErr NetClosed }
            } {}
            ^ @ !( Vec u ) NetErr { T v }
        }
    }
}

@ __tls_write_net TcpConn c ( Vec u ) bytes → !v NetErr {
    : *TlsConn tc # *TlsConn . c tlsh
    : !v TlsErr r ? == . c kind 2 ( tls_server_write tc bytes ) ( tls_write tc bytes )
    ?? r { T _ → ^ @ !v NetErr { T 0 } F _ → ^ @ !v NetErr { F # NetErr NetWrite } }
}

// with a clean peer shutdown. Caller frees the Vec on the Ok path.
@ tcp_read_chunk TcpConn c i max → !( Vec u ) NetErr {
    ? != . c kind 0 { ^ ( __tls_read_net c max ) } {}
    // Context-aware dispatch — see tcp_accept's note.
    : i fcur ( nurl_fiber_current )
    ? != fcur 0 { ^ ( tcp_read_chunk_async c max ) } {}
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
    ? != . c kind 0 { ^ ( __tls_write_net c bytes ) } {}
    // Context-aware dispatch — see tcp_accept's note.
    : i fcur ( nurl_fiber_current )
    ? != fcur 0 { ^ ( tcp_write_all_async c bytes ) } {}
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
    ? != . c kind 0 {
        : ( Vec u ) b ( bytes_from_str text )
        : !v NetErr r ( __tls_write_net c b )
        ( vec_free [u] b )
        ^ r
    } {}
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

& `c` @ nurl_tcp_get_fd i handle → i

& `c` @ nurl_tcp_set_nonblock i handle i on → v

& `c` @ nurl_tcp_ref i handle → v

& `c` @ nurl_tcp_unref i handle → v

// Take/drop an extra reference on a listener handle so it survives a
// concurrent `tcp_close_listener` (e.g. `server_stop` fired from another
// thread). `server_run_async` retains the listener for the life of its
// accept fiber and releases it once the fiber has exited — without this,
// closing the listener mid-accept frees the struct out from under the
// parked fiber (use-after-free). Each retain MUST be paired with one
// release.
@ tcp_listener_retain TcpListener l → v {
    : s rp . l raw
    ( nurl_tcp_ref # i rp )
}

@ tcp_listener_release TcpListener l → v {
    : s rp . l raw
    ( nurl_tcp_unref # i rp )
}

// Set non-blocking mode (idempotent). Used internally by the async
// wrappers on first call. Exposed in case callers want to manage the
// mode explicitly (e.g. a custom proactor loop).
@ tcp_set_nonblock_listener TcpListener l i on → v {
    : s rp . l raw
    : i raw # i rp
    ( nurl_tcp_set_nonblock raw on )
}

@ tcp_set_nonblock_conn TcpConn c i on → v {
    : s rp . c raw
    : i raw # i rp
    ( nurl_tcp_set_nonblock raw on )
}

// Non-blocking accept. Loops: try accept; if NetTimeout (EAGAIN),
// wait_readable on listener fd, retry. On non-fiber callers,
// wait_readable returns -1 immediately and we fall back to the
// existing sync `tcp_accept` (which blocks on the kernel).
@ tcp_accept_async TcpListener l → !TcpConn NetErr {
    : s lrp . l raw
    : i lraw # i lrp
    ( nurl_tcp_set_nonblock lraw 1 )
    : i fd ( nurl_tcp_get_fd lraw )
    ~ T {
        : i craw ( nurl_tcp_accept lraw )
        ? == craw 0 { ^ @ !TcpConn NetErr { F # NetErr NetOther } } {}
        : i ek ( nurl_tcp_err_kind craw )
        ? == ek 0 {
            : s crp # s craw
            : TcpConn c @ TcpConn { crp 0 0 }
            ^ @ !TcpConn NetErr { T c }
        } {
            ( nurl_tcp_close craw )
            ? == ek 7 {  // NetTimeout / EAGAIN
                : i rc ( nurl_reactor_wait_read fd - 0 1 )
                // wait_readable returns -1 outside a fiber; in that
                // case the sync accept already blocked, so EAGAIN
                // shouldn't recur — bail to NetAccept.
                ? < rc 0 { ^ @ !TcpConn NetErr { F # NetErr NetAccept } } {}
            } {
                ^ @ !TcpConn NetErr { F ( __net_err_of ek ) }
            }
        }
    }
    ^ @ !TcpConn NetErr { F # NetErr NetOther }
}

// Non-blocking single recv. Same shape as tcp_read_chunk; loops on
// EAGAIN via the reactor.
@ tcp_read_chunk_async TcpConn c i max → !( Vec u ) NetErr {
    : s rp . c raw
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
            ( vec_free [u] v )
            ^ @ !( Vec u ) NetErr { F # NetErr NetClosed }
        } {}
        : i ek ( nurl_tcp_err_kind raw )
        ? == ek 7 {
            : i rc ( nurl_reactor_wait_read fd - 0 1 )
            ? < rc 0 {
                ( vec_free [u] v )
                ^ @ !( Vec u ) NetErr { F # NetErr NetTimeout }
            } {}
        } {
            ( vec_free [u] v )
            ^ @ !( Vec u ) NetErr { F ( __net_err_of ek ) }
        }
    }
    ( vec_free [u] v )
    ^ @ !( Vec u ) NetErr { F # NetErr NetOther }
}

// Non-blocking write-all. Loops issuing send(2) until the full Vec
// is delivered, parking on wait_writable when the kernel returns
// EAGAIN.
@ tcp_write_all_async TcpConn c ( Vec u ) bytes → !v NetErr {
    : s rp . c raw
    : i raw # i rp
    ( nurl_tcp_set_nonblock raw 1 )
    : i fd ( nurl_tcp_get_fd raw )
    : i total ( vec_len [u] bytes )
    ? <= total 0 { ^ @ !v NetErr { T 0 } } {}
    : *u p ( vec_data [u] bytes )
    : s pbuf # s p
    : ~ i sent 0
    ~ < sent total {
        : i remaining - total sent
        : s slice # s + # i pbuf sent
        : i n ( nurl_tcp_write raw slice remaining )
        ? > n 0 {
            = sent + sent n
        } {
            ? < n 0 {
                : i ek ( nurl_tcp_err_kind raw )
                ? == ek 7 {
                    : i rc ( nurl_reactor_wait_write fd - 0 1 )
                    ? < rc 0 {
                        ^ @ !v NetErr { F # NetErr NetTimeout }
                    } {}
                } {
                    ^ @ !v NetErr { F ( __net_err_of ek ) }
                }
            } {
                // n == 0 — kernel says "wrote nothing" without error.
                // Treat as EAGAIN to avoid spinning.
                : i rc ( nurl_reactor_wait_write fd - 0 1 )
                ? < rc 0 { ^ @ !v NetErr { F # NetErr NetTimeout } } {}
            }
        }
    }
    ^ @ !v NetErr { T 0 }
}
