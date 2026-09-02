# Networking

NURL reaches the network through a pure-POSIX socket layer in the C runtime
(`nurl_tcp_*` / `nurl_udp_*` / `nurl_dns_*`) — no framework, and no libcurl
at this layer. (The stdlib HTTP *client* `ext/http.nu` and the reverse proxy
are separate, optional libcurl bridges.) Four primitives, every one
dual-stack IPv4/IPv6 and integrated with the fiber scheduler's I/O layer
for async I/O — the `epoll` netpoller on Linux, the portable `poll(2)`
reactor elsewhere (see [`ASYNC.md`](ASYNC.md)).

- **TCP server** — `tcp_listen` / `tcp_listen_tls` + `tcp_accept`, with a full
  HTTP server stack on top (`stdlib/ext/http_*` — HTTP/1.1 **and HTTP/2 on
  every listener**, routing, static files, middleware, multipart, WebSockets,
  TLS with ALPN; see [HTTPS / TLS](#https--tls) and [HTTP/2](#http2) below).
- **TCP client** — `tcp_connect` (plain) / `tcp_connect_tls` (TLS client
  handshake with SNI; the `verify` flag turns on peer-certificate chain +
  host-name verification against the system trust store — the primitive
  behind any outbound TLS application).
- **UDP** (`stdlib/std/udp.nu`) — `udp_bind` (dual-stack wildcard),
  `udp_connect`, `udp_send_to` / `udp_recv_from`, connected-mode `udp_send` /
  `udp_recv`, broadcast and multicast (`udp_join_group` / `_leave_group` /
  `_set_multicast_ttl` / `_set_multicast_loop`). Sync + fiber-aware async on
  every send/recv.
- **DNS** (`stdlib/std/dns.nu`) — system-resolver wrappers over
  `getaddrinfo` / `getnameinfo`, no c-ares dep. `dns_resolve host → ! (Vec
  String) NetErr` lists A/AAAA literals in the kernel's preferred order;
  `dns_resolve_port host port` formats each entry as `"ip:port"` (IPv4) or
  `"[ip]:port"` (IPv6, RFC 3986) ready for `tcp_connect` / `udp_connect`;
  `dns_reverse ip → ? String` runs `NI_NAMEREQD`.

## MQTT 5.0 client — `stdlib/ext/mqtt.nu`

A production-grade MQTT 5.0 client built on the TCP/TLS layer. The whole
packet codec is pure NURL over `( Vec u )` — no dependencies beyond the
runtime's libssl. The client connects over **TLS** (default broker port
8883); the `MqttConfig.tls_verify` field (default **on**) controls
certificate verification.

```
$ `stdlib/ext/mqtt.nu`

@ main → i {
    : !MqttClient MqttErr r ( mqtt_connect
        `broker.example.com` 8883 `client-id` `user` `pass` )
    ?? r {
        T cl → {
            : !v MqttErr s ( mqtt_subscribe cl `sensors/#` )
            ?? s { T → {} F e → {} }
            : !v MqttErr p ( mqtt_publish1 cl `sensors/temp` `21.4` )
            ?? p { T → {} F e → {} }
            ( mqtt_disconnect cl )
            ^ 0
        }
        F e → { ( nurl_eprint ( mqtt_err_name e ) ) ^ 1 }
    }
}
```

What it covers:

- MQTT 5.0 CONNECT via a configurable `MqttConfig` — Last Will, session
  expiry, clean-start, and `tls_verify` (default on — leave it on over any
  untrusted network; disable only for a self-signed broker in a trusted
  environment).
- PUBLISH at **QoS 0 / 1 / 2** (full PUBREC/PUBREL/PUBCOMP exchange), the
  `retain` flag, and MQTT 5 user properties.
- SUBSCRIBE / UNSUBSCRIBE at a chosen max QoS, including multi-topic
  `mqtt_subscribe_many` (one packet, N filters); `mqtt_receive` returns
  inbound messages and auto-acknowledges QoS 1/2. **Inbound QoS 2 is
  exactly-once** — a DUP retransmit is acknowledged but delivered once.
- A **framed packet reader** — a packet split across TCP segments, or several
  packets in one segment, is reassembled correctly.
- Keep-alive (`mqtt_ping` / deadline-aware `mqtt_keepalive_tick`), a rotating
  packet-id allocator, `mqtt_reconnect`, and `mqtt_listen` — a background
  reader thread that feeds inbound messages through a channel while the
  application does other work.
- Typed errors (`MqttErr`): transport faults are distinct from broker
  rejections (`MqttBadAuth`, `MqttNotAuthorized`, …).

> **Not yet:** pipelined (multiple-in-flight) publishing — calls are
> synchronous, one packet in flight.

## HTTPS / TLS

The runtime offers a `libssl`-backed TLS integration (**optional**
dependency — required only by the `tcp_connect_tls` / `tcp_listen_tls`
family below; see the pure-NURL alternative in the next section). The HTTP
server stack picks it up transparently — swap `tcp_listen` for
`tcp_listen_tls`.

| Capability | Notes |
|---|---|
| **TLS server-side** — `tcp_listen_tls host port cert_path key_path → !TcpListener NetErr` | HttpServer integrates without code changes. |
| **TLS client-side** — `tcp_connect_tls host port server_name verify` | Client handshake with SNI; `verify` enables peer-certificate chain + host-name verification against the system trust store — or against `$SSL_CERT_FILE` when that is set, which **replaces** the system bundle (OpenSSL semantics) and fails closed if unreadable, so a private CA or a self-signed lab server no longer means editing `/etc/ssl` or giving up on verification. The primitive behind the MQTT client and any outbound TLS. |
| TLS 1.2 minimum | TLS 1.0 / 1.1 / SSL 3.0 disabled in the SSL_CTX. |
| **SNI** (RFC 6066 §3) — `tcp_tls_add_sni listener hostname cert key` | Multi-tenant HTTPS — per-hostname cert/key pairs on one listener; handshake-time selection; no-match falls through to the default cert. |
| **ALPN** (RFC 7301) — `tcp_listen_tls_with_alpn host port backlog cert key "h2 http/1.1"`; `tcp_alpn_protocol conn` | Server-side selection in the pure TLS 1.3 server: the first protocol in the listener's order that the client also offered, announced in EncryptedExtensions; a client offering ALPN with nothing in common is refused with a fatal `no_application_protocol` alert; no ALPN from the client negotiates nothing (`""`). Required by HTTP/2-over-TLS (RFC 9113 §3.3). |
| **Mutual TLS (mTLS)** — `tcp_tls_require_client_cert listener ca_bundle strict?`; `tcp_peer_cert_subject conn` | Strict (handshake fails without a cert) and opportunistic modes. |
| **Live cert reload** — `tcp_tls_reload listener hostname cert key` | Hot-swaps the SSL_CTX under a per-listener mutex; in-flight reads/writes on the old ctx survive until close. Standard Let's Encrypt-rotation use case. |

### Pure-NURL TLS (no OpenSSL)

TLS is a **pure-NURL TLS 1.3 client and server** in the standard library
([`std/tls.nu`](../stdlib/std/tls.nu) / `std/tls_server.nu`; full design in
[`docs/CRYPTO.md`](CRYPTO.md)) — no `libssl`/OpenSSL anywhere. It implements
the handshake, the record layer and full certificate verification from scratch
in NURL, with **no FFI beyond the
libc TCP socket**. It negotiates ChaCha20-Poly1305 / AES-128-GCM over
X25519 or NIST P-256, verifies the chain against the system trust store by
default, and runs on a host with nothing installed. `tls_attach` upgrades
an already-connected socket, which is what STARTTLS-style protocols need.

A program that never calls `tcp_connect_tls` / `tcp_listen_tls` (a
pure-NURL-TLS client, or plain TCP) links `libc` only. The
[`psql`](../packages/psql) package builds on the pure-NURL TLS client to
reach PostgreSQL securely with no libpq and no OpenSSL.

## HTTP/2

Every HTTP server listener — `server_run`, `server_run_pool`,
`server_run_async`, and so the `packages/http` HttpApp facade
(`http_app_listen` / `http_app_listen_tls`) — serves **HTTP/2 (RFC 9113 +
HPACK, RFC 7541) alongside HTTP/1.1**, with the same
`( @ HttpResponse HttpRequest )` handler, the same routes and middleware,
the same DoS gate, idle timeout and body limit. Nothing in application
code chooses a protocol; the connection does:

| How a client reaches HTTP/2 | What decides | Where |
|---|---|---|
| TLS, ALPN `h2` (RFC 9113 §3.3) | `http_app_listen_tls` advertises `h2 http/1.1`; per connection `tcp_alpn_is conn "h2"` routes to the HTTP/2 state machine before a byte is parsed | browsers, `curl --http2`, `oha --http2` over https |
| Cleartext, prior knowledge (§3.4) | the keep-alive loop recognises the 24-byte `PRI * HTTP/2.0` preface in the first bytes and hands the connection — bytes and all — to `h2_conn_new_buffered`; anything else is HTTP/1.1 | `curl --http2-prior-knowledge`, `h2load`, `oha --http2` over http |
| `Upgrade: h2c` | not implemented — deprecated by RFC 9113 | — |

On a cleartext port shared with HTTP/1.1 a first line that is neither the
preface nor HTTP gets HTTP/1.1's `400 Bad Request`; h2spec's §3.5/2
("invalid connection preface") expects a GOAWAY there and is the one case
the shared-port run fails, by design. Over ALPN-`h2` the connection is
HTTP/2 from its first byte and the GOAWAY is sent.

The implementation is pure NURL: `stdlib/ext/http2_frame.nu` (framing,
buffered reads), `http2_hpack.nu` (static + dynamic table, Huffman),
`http2_conn.nu` (connection + stream state machine, flow control, request
assembly, response emission), `http2_client.nu` (multiplexed client:
`h2_client_connect_tls` / `h2_client_connect_h2c`, `h2_client_submit`).
`http2_serve` (`stdlib/ext/http2_server.nu`) drives one HTTP/2 connection
for a program with its own accept loop (`examples/h2c_server.nu`).

Conformance is a CI gate, not a claim: `tools/h2spec_gate.sh` runs h2spec
2.6.0 against the HttpApp TLS listener and the HTTP/2-only example
(146/146, strict 147/147) and the shared plaintext port (145/146 with
§3.5/2 pinned by name), then confirms the negotiated protocol with curl.
`compiler/tests/http2_in_http_server.nu` proves the same with the in-repo
client. Performance is measured separately in
[`bench/HTTP2_RESULTS.md`](../bench/HTTP2_RESULTS.md) (`bench/run_http2.sh`),
next to the HTTP/1.1 report.

Limits: the handler runs synchronously inside the connection's frame loop,
one stream at a time — a slow handler delays the other streams on that
connection (each connection is its own fiber, so other connections are
unaffected). Server push is disabled (`SETTINGS_ENABLE_PUSH = 0`); the
streaming / WebSocket upgrade hooks are HTTP/1.1-only. An idle HTTP/2
connection whose deadline fires is closed with GOAWAY(NO_ERROR).
