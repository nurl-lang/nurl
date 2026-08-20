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
//   ( tcp_local_addr      TcpListener l )                   → String OWNED
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
// A TLS listener carries the loaded certificate_list (already framed as
// CertificateEntry blobs, leaf first) + the leaf's private key, so each
// accept can run the pure handshake (is_tls = 1). keytype selects the
// key form: 0 = EC P-256 (kp1 = 32-byte scalar, kp2 unused), 1 = RSA
// (kp1 = modulus n, kp2 = private exponent d), both big-endian. All are
// held as raw malloc'd (ptr, len) pairs — NOT Vec fields — because a
// value struct returned with owned-Vec fields is auto-dropped at the
// constructing function's exit (a borrowck escape gap), which would free
// the buffers out from under the listener.
: TcpListener { s raw i is_tls i keytype i certp i certlen i kp1 i kl1 i kp2 i kl2 i kp3 i kl3 }
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
    : i raw ( nurl_tcp_listen host port backlog )
    ? == raw 0 { ^ @ !TcpListener NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind raw )
    ? != ek 0 {
        ( nurl_tcp_close raw )
        ^ @ !TcpListener NetErr { F ( _net_err_of ek ) }
    } {}
    : s rp # s raw
    : TcpListener l @ TcpListener { rp 0 0 0 0 0 0 0 0 0 0 }
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
        ( string_free suf )
        ? < rel 0 { = pos total } {
            : i bi + pos rel
            : String suf2 ( string_substr pem bi - total bi )
            : i erel ( nurl_str_find ( string_data suf2 ) `-----END CERTIFICATE-----` )
            ( string_free suf2 )
            ? < erel 0 { = pos total } {
                : i blen + erel 25  // through the END marker (25 chars)
                : String block ( string_substr pem bi blen )
                ?? ( pem_to_der ( string_data block ) ) {
                    T der → {
                        : ( Vec u ) e ( tls_cert_entry der )
                        ( bytes_extend_bytes list e )
                        ( vec_free [u] e ) ( vec_free [u] der )
                    }
                    F _ → {}
                }
                ( string_free block )
                = pos + bi blen
            }
        }
    }
    ^ list
}

// Load cert chain + private key from PEM files into a TLS listener. Fills
// `cert_out` with the framed certificate_list and `k1`/`k2` with the key
// material; returns the keytype (0 = EC P-256 scalar in k1; 1 = RSA with
// modulus in k1, private exponent in k2), or a NEGATIVE NetErr-style code
// on failure (-10 cert, -11 key). The key form is auto-detected: EC and
// RSA parsers each cleanly reject the other's encoding.
@ __load_tls_creds s cert_path s key_path ( Vec u ) cert_out ( Vec u ) k1 ( Vec u ) k2 ( Vec u ) k3 → i {
    : String certpem ?? ( read_file cert_path ) { T p → p F _ → ( string_new ) }
    : ( Vec u ) chain ( __net_cert_chain certpem )
    ( string_free certpem )
    ? == ( vec_len [u] chain ) 0 { ( vec_free [u] chain ) ^ -10 } {}
    ( bytes_extend_bytes cert_out chain )
    ( vec_free [u] chain )
    : String keypem ?? ( read_file key_path ) { T p → p F _ → ( string_new ) }
    // EC first; on failure try RSA (the parsers reject foreign encodings).
    : ?( Vec u ) ec ?? ( ec_p256_priv_from_pem ( string_data keypem ) ) {
        T sc → @ ?( Vec u ) { T sc } F _ → @ ?( Vec u ) { F # ( Vec u ) 0 }
    }
    ?? ec {
        T sc → { ( bytes_extend_bytes k1 sc ) ( vec_free [u] sc ) ( string_free keypem ) ^ 0 }
        F _ → {}
    }
    : i kt ?? ( rsa_priv_from_pem ( string_data keypem ) ) {
        T k → {
            ( bytes_extend_bytes k1 . k n ) ( bytes_extend_bytes k2 . k d )
            ( bytes_extend_bytes k3 . k e )  // public exponent — for sign-time blinding
            ( rsa_priv_free k ) 1
        }
        F _ → -11
    }
    ( string_free keypem )
    ^ kt
}

@ tcp_listen_tls_with_backlog s host i port i backlog s cert_path s key_path → !TcpListener NetErr {
    : ( Vec u ) cert ( vec_new [u] )
    : ( Vec u ) k1 ( vec_new [u] )
    : ( Vec u ) k2 ( vec_new [u] )
    : ( Vec u ) k3 ( vec_new [u] )
    : i keytype ( __load_tls_creds cert_path key_path cert k1 k2 k3 )
    ? < keytype 0 {
        ( vec_free [u] cert ) ( vec_free [u] k1 ) ( vec_free [u] k2 ) ( vec_free [u] k3 )
        ^ @ !TcpListener NetErr { F ( _net_err_of - 0 keytype ) }
    } {}
    : i raw ( nurl_tcp_listen host port backlog )
    ? == raw 0 { ( vec_free [u] cert ) ( vec_free [u] k1 ) ( vec_free [u] k2 ) ( vec_free [u] k3 ) ^ @ !TcpListener NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind raw )
    ? != ek 0 {
        ( nurl_tcp_close raw ) ( vec_free [u] cert ) ( vec_free [u] k1 ) ( vec_free [u] k2 ) ( vec_free [u] k3 )
        ^ @ !TcpListener NetErr { F ( _net_err_of ek ) }
    } {}
    // Copy cert list / key material into raw heap buffers, then drop the Vecs.
    : i certp ( __net_dup cert )
    : i certlen ( vec_len [u] cert )
    : i kp1 ( __net_dup k1 )
    : i kl1 ( vec_len [u] k1 )
    : i kp2 ( __net_dup k2 )
    : i kl2 ( vec_len [u] k2 )
    : i kp3 ( __net_dup k3 )
    : i kl3 ( vec_len [u] k3 )
    ( vec_free [u] cert ) ( vec_free [u] k1 ) ( vec_free [u] k2 ) ( vec_free [u] k3 )
    : s rp # s raw
    ^ @ !TcpListener NetErr { T @ TcpListener { rp 1 keytype certp certlen kp1 kl1 kp2 kl2 kp3 kl3 } }
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

// Read the negotiated ALPN protocol off a TLS conn (client kind 1 or a
// STARTTLS upgrade). Returns "" for plaintext conns or when no ALPN was
// negotiated. Server-side ALPN is not parsed yet.
@ tcp_alpn_protocol TcpConn c → String {
    : i tp ( __conn_tlsptr c )
    ? == tp 0 { ^ ( string_new ) } {}
    ^ ( tls_alpn_selected # *TlsConn tp )
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
    ^ ( tls_group # *TlsConn tp )
}

// T when this connection's key exchange has a post-quantum component,
// so its forward secrecy survives an adversary recording it today and
// factoring later.
@ tcp_is_post_quantum TcpConn c → b {
    ^ == ( tcp_tls_group c ) 4588
}

// Open a plain (unencrypted) TCP client connection. Returns a
// polymorphic TcpConn (kind 0) usable with the same tcp_read/tcp_write
// family as accepted connections. For an encrypted connection use
// tcp_connect_tls below.
@ tcp_connect s host i port → !TcpConn NetErr {
    : i craw ( nurl_tcp_connect host port )
    ? == craw 0 { ^ @ !TcpConn NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind craw )
    ? != ek 0 {
        ( nurl_tcp_close craw )
        ^ @ !TcpConn NetErr { F ( _net_err_of ek ) }
    } {}
    : s crp # s craw
    ^ @ !TcpConn NetErr { T @ TcpConn { crp 0 0 } }
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

// As tcp_connect_tls, but offers a single ALPN protocol (e.g. "h2").
// After connecting, the negotiated protocol is read with
// tcp_alpn_protocol — empty if the server declined ALPN. With verify the
// chain is validated AND the ALPN handshake runs; on TLS 1.2 servers the
// pure stack does not parse ALPN, so callers requiring h2 should check.
@ tcp_connect_tls_alpn s host i port s server_name i verify s alpn → !TcpConn NetErr {
    : i raw ( nurl_tcp_connect host port )
    ? <= raw 0 { ^ @ !TcpConn NetErr { F # NetErr NetTlsHandshake } } {}
    : !*TlsConn TlsErr r ? != verify 0 ( tls_attach_alpn_verify raw server_name alpn ) ( tls_attach_alpn raw server_name alpn )
    ?? r {
        F _ → ^ @ !TcpConn NetErr { F # NetErr NetTlsHandshake }
        T tc → ^ @ !TcpConn NetErr { T @ TcpConn { # s 0 1 # i tc } }
    }
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
        ? != . l kp1 0 { ( nurl_free # s . l kp1 ) } {}
        ? != . l kp2 0 { ( nurl_free # s . l kp2 ) } {}
        ? != . l kp3 0 { ( nurl_free # s . l kp3 ) } {}
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

// ── STARTTLS registry ──────────────────────────────────────────────
//
// An in-place TLS upgrade (tcp_starttls) attaches a *TlsConn to an
// ALREADY-connected fd (SMTP STARTTLS, etc). A TcpConn is passed BY
// VALUE, so the upgraded `tlsh`/`kind` can't be written back into the
// caller's copy. Because the fd is the stable identity across the
// upgrade, the fd→*TlsConn mapping lives here instead and is consulted
// by the read/write/close dispatch. The whole thing is gated on
// g_st_n: a process that never calls tcp_starttls does ZERO lookups.
//
// Storage is a malloc'd i64 array of (fd, ptr) pairs (2 words each),
// grown by doubling. nurl_peek/poke are word-indexed (8-byte cells).
: ~ i g_st_base 0
: ~ i g_st_cap 0
: ~ i g_st_n 0

@ __starttls_grow → v {
    : i newcap ? == g_st_cap 0 8 * g_st_cap 2
    : s nb # s ( malloc * newcap 16 )
    ? != g_st_base 0 {
        ( nurl_memcpy # *u nb # *u g_st_base * g_st_n 16 )
        ( nurl_free # s g_st_base )
    } {}
    = g_st_base # i nb
    = g_st_cap newcap
}

@ __starttls_register i fd i ptr → v {
    ? >= g_st_n g_st_cap { ( __starttls_grow ) } {}
    : s b # s g_st_base
    ( nurl_poke b * g_st_n 2 fd )
    ( nurl_poke b + * g_st_n 2 1 ptr )
    = g_st_n + g_st_n 1
}

@ __starttls_lookup i fd → i {
    ? == g_st_n 0 { ^ 0 } {}
    : s b # s g_st_base
    : ~ i k 0
    ~ < k g_st_n {
        ? == ( nurl_peek b * k 2 ) fd { ^ ( nurl_peek b + * k 2 1 ) } {}
        = k + k 1
    }
    ^ 0
}

@ __starttls_unregister i fd → v {
    ? != g_st_n 0 {
        : s b # s g_st_base
        : ~ i k 0
        : ~ i found 0
        ~ & == found 0 < k g_st_n {
            ? == ( nurl_peek b * k 2 ) fd {
                : i last - g_st_n 1
                ( nurl_poke b * k 2 ( nurl_peek b * last 2 ) )
                ( nurl_poke b + * k 2 1 ( nurl_peek b + * last 2 1 ) )
                = g_st_n last
                = found 1
            } {}
            = k + k 1
        }
    } {}
}

// Resolve a TcpConn's *TlsConn (as i64), or 0 if the conn is plaintext.
// kinds 1/2 carry it inline in `tlsh`; a STARTTLS-upgraded kind-0 conn
// is found via the fd registry.
@ __conn_tlsptr TcpConn c → i {
    ? != . c tlsh 0 { ^ . c tlsh } {}
    ? == . c kind 0 { ^ ( __starttls_lookup # i . c raw ) } {}
    ^ 0
}

// The fd backing a TcpConn — the runtime handle for plaintext, or the
// pure TLS conn's socket fd for TLS (kinds 1/2 or STARTTLS-upgraded).
@ __conn_fd TcpConn c → i {
    : i tp ( __conn_tlsptr c )
    ? != tp 0 {
        : *TlsConn tc # *TlsConn tp
        ^ . tc fd
    } {}
    ^ # i . c raw
}

// Run the server-side pure-TLS handshake over a freshly accepted raw
// conn handle, using the listener's parked cert/key material. Consumes
// `craw` (the *TlsConn owns the socket on success; closed on failure).
@ __tls_accept_handshake TcpListener l i craw → !TcpConn NetErr {
    : ( Vec u ) cert ( __net_vecview . l certp . l certlen )
    : ( Vec u ) k1 ( __net_vecview . l kp1 . l kl1 )
    // keytype 1 = RSA (k1 = n, k2 = d, k3 = e); else EC P-256 (k1 = scalar).
    : !*TlsConn TlsErr r ? == . l keytype 1
    { : ( Vec u ) k2 ( __net_vecview . l kp2 . l kl2 )
        : ( Vec u ) k3 ( __net_vecview . l kp3 . l kl3 )
        : !*TlsConn TlsErr rr ( tls_accept_rsa craw cert k1 k3 k2 )
        ( vec_free [u] k2 ) ( vec_free [u] k3 )
        rr }
    ( tls_accept craw cert k1 )
    ( vec_free [u] cert )
    ( vec_free [u] k1 )
    ?? r {
        F _ → ^ @ !TcpConn NetErr { F # NetErr NetTlsHandshake }
        T tc → ^ @ !TcpConn NetErr { T @ TcpConn { # s 0 2 # i tc } }
    }
}

// Accept ONLY the transport (TCP) connection — even on a TLS listener,
// no handshake runs here. Context-aware: on a fiber the wait parks on
// the reactor. This is the building block a fiber-per-connection
// server wants: accept cheaply on the accept fiber, then let each
// CONNECTION's fiber run `tcp_conn_complete_tls`, so handshakes
// proceed concurrently instead of serialising on the accept loop.
@ tcp_accept_transport TcpListener l → !TcpConn NetErr {
    : i fcur ( nurl_fiber_current )
    ? != fcur 0 { ^ ( tcp_accept_async l ) } {}
    : i lraw # i . l raw
    : i craw ( nurl_tcp_accept lraw )
    ? == craw 0 { ^ @ !TcpConn NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind craw )
    ? != ek 0 {
        ( nurl_tcp_close craw )
        ^ @ !TcpConn NetErr { F ( _net_err_of ek ) }
    } {}
    : TcpConn c @ TcpConn { # s craw 0 0 }
    ^ @ !TcpConn NetErr { T c }
}

// Complete a TLS listener's server handshake over a transport conn from
// `tcp_accept_transport`. Consumes `c` — on success the returned conn
// supersedes it (the *TlsConn owns the socket); on Err the socket is
// already closed by the TLS layer. A plaintext listener returns `c`
// unchanged. The handshake's record I/O is context-aware, so on a fiber
// a slow client parks this fiber instead of blocking the worker.
@ tcp_conn_complete_tls TcpListener l TcpConn c → !TcpConn NetErr {
    ? == . l is_tls 0 { ^ @ !TcpConn NetErr { T c } } {}
    ^ ( __tls_accept_handshake l # i . c raw )
}

@ tcp_accept TcpListener l → !TcpConn NetErr {
    // Context-aware: on a fiber, the transport accept parks on the
    // reactor so the worker pthread stays free while we wait. For a
    // TLS listener the handshake then runs right here in the calling
    // context (fiber-aware record I/O parks; a plain thread blocks).
    : !TcpConn NetErr acc ( tcp_accept_transport l )
    ? == . l is_tls 0 { ^ acc } {}
    ?? acc {
        T rawc → ^ ( __tls_accept_handshake l # i . rawc raw )
        F e → ^ @ !TcpConn NetErr { F e }
    }
}

@ tcp_close_conn TcpConn c → v {
    : i tp ( __conn_tlsptr c )
    ? != tp 0 {
        ( __starttls_unregister # i . c raw )
        // kind 2 = pure-NURL TLS server conn: its close_notify must be
        // encrypted under the server write keys (tls_server_close);
        // tls_close's alert uses the client direction.
        ? == . c kind 2 { ( tls_server_close # *TlsConn tp ) } { ( tls_close # *TlsConn tp ) }
    } { ( nurl_tcp_close # i . c raw ) }
}

// In-place STARTTLS upgrade: run a pure TLS 1.3 handshake over an
// already-connected plaintext TcpConn's fd, registering the resulting
// *TlsConn against that fd so subsequent read/write/close on the SAME
// (by-value) conn transparently go through TLS. `server_name` drives
// SNI + (when verify) certificate validation. Used by SMTP STARTTLS,
// IMAP/POP STLS, etc. The conn keeps its identity — no new TcpConn is
// returned, so callers holding the conn by value see the upgrade.
@ tcp_starttls TcpConn c s server_name b verify → !v NetErr {
    : i tp ( __conn_tlsptr c )
    ? != tp 0 { ^ @ !v NetErr { T 0 } } {}
    : i fd # i . c raw
    : !*TlsConn TlsErr r ? verify ( tls_attach_verify fd server_name ) ( tls_attach fd server_name )
    ?? r {
        F _ → ^ @ !v NetErr { F # NetErr NetTlsHandshake }
        T tc → {
            ( __starttls_register fd # i tc )
            ^ @ !v NetErr { T 0 }
        }
    }
}

@ tcp_peer_addr TcpConn c → s {
    ^ ( nurl_tcp_peer_addr ( __conn_fd c ) )
}

& `c` @ nurl_tcp_local_addr i handle → s

// OWNED String "ip:port" of the address a listener is actually bound to,
// read fresh from getsockname. This is the counterpart of listening on
// port 0: the kernel picks the port, and this is how the process that
// asked for it finds out. Caller frees with `string_free`.
//
// Note the ownership difference from `tcp_peer_addr`, which hands back a
// BORROWED view cached on the handle: there is no cached local address,
// so this one is computed and owned. Same shape as `udp_local_addr`.
@ tcp_local_addr TcpListener l → String {
    : s raw_s ( nurl_tcp_local_addr # i . l raw )
    : String out ( string_from raw_s )
    ( nurl_free raw_s )
    ^ out
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
    : *TlsConn tc # *TlsConn ( __conn_tlsptr c )
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
    : *TlsConn tc # *TlsConn ( __conn_tlsptr c )
    : !v TlsErr r ? == . c kind 2 ( tls_server_write tc bytes ) ( tls_write tc bytes )
    ?? r { T _ → ^ @ !v NetErr { T 0 } F _ → ^ @ !v NetErr { F # NetErr NetWrite } }
}

// with a clean peer shutdown. Caller frees the Vec on the Ok path.
@ tcp_read_chunk TcpConn c i max → !( Vec u ) NetErr {
    ? != ( __conn_tlsptr c ) 0 { ^ ( __tls_read_net c max ) } {}
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
        ^ @ !( Vec u ) NetErr { F ( _net_err_of ek ) }
    } {}
    ? == n 0 {
        ( vec_free [u] v )
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
    ? != ( __conn_tlsptr c ) 0 {
        // TLS: the record layer necessarily materialises decrypted
        // bytes in their own Vec; append and release it.
        : !( Vec u ) NetErr r ( __tls_read_net c max )
        ?? r {
            T v → {
                : i n ( vec_len [u] v )
                ( vec_extend [u] buf v )
                ( vec_free [u] v )
                ^ @ !i NetErr { T n }
            }
            F e → ^ @ !i NetErr { F e }
        }
    } {}
    : s rp . c raw
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

// ── Writing ────────────────────────────────────────────────────────

@ tcp_write_all TcpConn c ( Vec u ) bytes → !v NetErr {
    ? != ( __conn_tlsptr c ) 0 { ^ ( __tls_write_net c bytes ) } {}
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
        ^ @ !v NetErr { F ( _net_err_of ek ) }
    } {}
    ^ @ !v NetErr { T 0 }
}

// Convenience: write a NUL-terminated `s` (the typical HTTP header /
// status-line case). The bytes [0..len) are sent — the trailing NUL is
// NOT transmitted.
@ tcp_write_str TcpConn c s text → !v NetErr {
    ? != ( __conn_tlsptr c ) 0 {
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
        ^ @ !v NetErr { F ( _net_err_of ek ) }
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

// nurl_tcp_get_fd / nurl_tcp_timeout_ms / nurl_tcp_set_nonblock are
// declared in async_ffi.nu (imported above) so the pure TLS stack can
// use them too without an import cycle.

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
                // ACCEPT KEEPS WAITING. `tcp_set_timeout` is about a
                // CONNECTION's reads and writes; a listener has no such
                // deadline, and a server loop reads "the accept ended"
                // as "we were stopped" — report a timeout there and
                // every clean shutdown becomes an error.
                : i rc ( nurl_reactor_wait_read fd - 0 1 )
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
                ( vec_free [u] v )
                ^ @ !( Vec u ) NetErr { F # NetErr NetTimeout }
            } {}
            ? == rc 0 {
                ( vec_free [u] v )
                ^ @ !( Vec u ) NetErr { F # NetErr NetTimeout }
            } {}
        } {
            ( vec_free [u] v )
            ^ @ !( Vec u ) NetErr { F ( _net_err_of ek ) }
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
                    : i rc ( nurl_reactor_wait_write fd ( __wait_ms raw ) )
                    ? <= rc 0 {
                        ^ @ !v NetErr { F # NetErr NetTimeout }
                    } {}
                } {
                    ^ @ !v NetErr { F ( _net_err_of ek ) }
                }
            } {
                // n == 0 — kernel says "wrote nothing" without error.
                // Treat as EAGAIN to avoid spinning.
                : i rc ( nurl_reactor_wait_write fd ( __wait_ms raw ) )
                ? <= rc 0 { ^ @ !v NetErr { F # NetErr NetTimeout } } {}
            }
        }
    }
    ^ @ !v NetErr { T 0 }
}
