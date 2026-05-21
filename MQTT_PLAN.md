# MQTT Client — implementation plan

`stdlib/ext/mqtt.nu` — an MQTT 5.0 client for NURL. Goal: a
production-grade client a NURL program can rely on for real
broker workloads.

Built on the runtime's client-side TCP/TLS connect (`nurl_tcp_connect`
/ `nurl_tcp_connect_tls`, runtime.c §18b/§18c). The packet codec is
pure NURL on `( Vec u )`.

**Status legend:** `[x]` done · `[ ]` todo

---

## Phase 1 — Connection — SHIPPED

- [x] Client TCP + TLS connect (runtime §18b/§18c; SNI; DNS).
- [x] MQTT 5.0 CONNECT / CONNACK; clientId, username, password.
- [x] `MqttClient` handle = connection + leftover-byte buffer.
- [x] Framed packet reader — reads exactly one packet, buffering bytes
      split across (or bundled beyond) TCP segments. `__mqtt_read_packet`.
- [x] DISCONNECT.

## Phase 2 — Messaging — SHIPPED

- [x] PUBLISH QoS 0 (`mqtt_publish`).
- [x] PUBLISH QoS 1 — packet id + PUBACK wait (`mqtt_publish1`).
- [x] PUBLISH QoS 2 — PUBLISH/PUBREC/PUBREL/PUBCOMP (`mqtt_publish2`).
- [x] SUBSCRIBE / UNSUBSCRIBE + SUBACK / UNSUBACK check.
- [x] Inbound PUBLISH via `mqtt_receive` → `MqttMessage{topic,payload}`;
      auto-PUBACK (QoS 1) and PUBREC/PUBCOMP (QoS 2).
- [x] PINGREQ / PINGRESP (`mqtt_ping`).

Verified end to end against a live broker — `example/mqtt_pubsub.nu`.

## Phase 3 — Production hardening — TODO

- [ ] **Configurable connect** — clean-start vs resume, session expiry,
      a `MqttConfig` struct instead of fixed keep-alive 60 / clean start.
- [ ] **Last Will & Testament** — will flag, will topic/payload/QoS in
      CONNECT so the broker announces an ungraceful disconnect.
- [ ] **MQTT 5 properties** — currently every property block is empty
      (length 0). Surface at least: session-expiry, receive-maximum,
      user properties, content-type, response-topic; parse inbound
      property blocks (the reader already skips them correctly).
- [ ] **Subscribe options** — max-QoS 1/2, no-local, retain-handling
      (the options byte is hardcoded 0).
- [ ] **Retain flag** on publish.
- [ ] **Reason codes** — surface MQTT 5 reason codes (a typed `MqttErr`)
      instead of collapsing failures to `NetOther`.

## Phase 4 — Long-lived connections — TODO

- [ ] **Automatic keep-alive** — track the keep-alive deadline with
      `now_ms` and emit PINGREQ from the receive loop without the caller
      having to call `mqtt_ping`.
- [ ] **Packet-id allocator** — rotating 1..65535 ids so multiple QoS
      1/2 messages can be in flight (today: fixed id 1, correct only for
      strictly synchronous use).
- [ ] **Reconnection** — detect a dropped connection and reconnect with
      backoff; re-subscribe.
- [ ] **Background receive** — a reader thread (`std/thread.nu`) so
      inbound PUBLISH is handled while the app does other work.

## Phase 5 — Quality — TODO

- [ ] Offline codec tests in `compiler/tests/` (CONNECT byte layout,
      varint encode/decode round-trip, CONNACK/PUBLISH parse) — no
      network, CI-safe.
- [ ] Gated live integration test (`NURL_NET_TESTS=1`).
- [ ] Topic-filter wildcard matching (`+`, `#`) for client-side dispatch
      across multiple subscriptions.

---

## Design notes

- **Synchronous core.** `mqtt_publish1/2`, `mqtt_subscribe`, `mqtt_ping`
  each block for their acknowledgement. A synchronous client keeps one
  packet in flight, which is why a fixed packet id is currently correct.
  Phase 4's id allocator + background receive lift that restriction.
- **Framing is mandatory.** MQTT has no message delimiter beyond the
  Remaining Length varint; `__mqtt_read_packet` is the single choke
  point that turns the byte stream into whole packets. Everything else
  reads through it.
- **No libcurl, no extra libraries** — pure POSIX socket + libssl,
  same as the HTTP server stack.
