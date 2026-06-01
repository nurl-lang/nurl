# Networking

NURL reaches the network through a pure-POSIX socket layer in the C runtime
(`nurl_tcp_*` / `nurl_udp_*` / `nurl_dns_*`) — no libcurl, no framework. Four
primitives, every one dual-stack IPv4/IPv6 and integrated with the fiber
reactor for async I/O.

- **TCP server** — `tcp_listen` / `tcp_listen_tls` + `tcp_accept`, with a full
  HTTP/1.1 server stack on top (`stdlib/ext/http_*` — routing, static files,
  middleware, multipart, WebSockets, TLS with SNI + ALPN + mTLS + live cert
  reload; see [`LIMITATIONS.md` → HTTPS/TLS](LIMITATIONS.md)).
- **TCP client** — `tcp_connect` / `tcp_connect_tls`. TLS client handshake
  with SNI; the `verify` flag turns on peer-certificate chain + host-name
  verification against the system trust store. The primitive behind the MQTT
  client and any outbound TLS application.
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
