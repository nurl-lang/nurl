# Networking

NURL reaches the network through a pure-POSIX socket layer in the C runtime
(`nurl_tcp_*` / `nurl_udp_*` / `nurl_dns_*`) — no framework, and no libcurl
at this layer. (The stdlib HTTP *client* `ext/http.nu` and the reverse proxy
are separate, optional libcurl bridges.) Four primitives, every one
dual-stack IPv4/IPv6 and integrated with the fiber reactor for async I/O.

- **TCP server** — `tcp_listen` / `tcp_listen_tls` + `tcp_accept`, with a full
  HTTP/1.1 server stack on top (`stdlib/ext/http_*` — routing, static files,
  middleware, multipart, WebSockets, TLS with SNI + ALPN + mTLS + live cert
  reload; see [HTTPS / TLS](#https--tls) below).
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
| **ALPN** (RFC 7301) — `tcp_listen_tls_with_alpn`; `tcp_alpn_protocol conn` | Required by HTTP/2-over-TLS (RFC 9113 §3.3). |
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
