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

## Phase 3 — Production hardening — SHIPPED

- [x] **Configurable connect** — `MqttConfig` struct + `mqtt_connect_cfg`
      (clean-start, keep-alive, will, session expiry). `mqtt_connect`
      keeps the common-case 3-string signature.
- [x] **Last Will & Testament** — will flag + will-QoS in the connect
      flags; will topic / payload in the payload.
- [x] **Session Expiry Interval** — emitted as CONNECT property 0x11.
- [x] **Subscribe max-QoS** — `mqtt_subscribe_qos` (subscription-options
      QoS bits). no-local / retain-handling bits still default 0.
- [x] **Retain flag** — `mqtt_publish_retain`; unified `__mqtt_do_publish`
      drives every QoS + retain.
- [x] **MQTT 5 user properties** — `mqtt_publish_props` attaches a
      `( Vec ( Pair String String ) )` to the PUBLISH property block;
      `mqtt_receive` parses inbound property blocks (a full property-id
      length table skips non-user-property entries) into
      `MqttMessage.props`. `mqtt_message_prop` looks one up.
- [x] **Typed reason codes** — every MQTT call returns `! T MqttErr`.
      Transport faults (`MqttTransport` / `MqttTimeout` / `MqttClosed`),
      protocol faults (`MqttProtocol`), and broker rejections
      (`MqttRefused` / `MqttBadAuth` / `MqttNotAuthorized` from CONNACK,
      `MqttSubFailed` from SUBACK) are distinct — a caller tells "wrong
      password" from "network down". `mqtt_err_name` renders one.
- [ ] *(optional, later)* typed accessors for content-type /
      response-topic / correlation-data properties (parsed-and-skipped
      today; expose if a use case needs them).

## Phase 4 — Long-lived connections — SHIPPED

- [x] **Keep-alive timer** — `MqttClient` tracks a `now_ms` ping
      deadline; `mqtt_keepalive_tick` emits a PINGREQ only when the
      deadline is due (no-op otherwise). The caller ticks it from an
      idle loop. Fully-background pinging waits on the receive thread.
- [x] **Reconnection** — `mqtt_reconnect` closes a dropped connection
      and re-runs TLS + CONNECT, leaving the `MqttClient` reusable.
- [ ] *(optional, later)* **Reconnect polish** — automatic drop
      detection + backoff, and remembering subscriptions to re-issue
      them (today the caller re-subscribes).
- [x] **Packet-id allocator** — `MqttClient.next_pid` rotates 1..65535;
      `__mqtt_next_pid` hands a fresh id to every QoS 1/2 PUBLISH,
      SUBSCRIBE and UNSUBSCRIBE. The await paths verify the ack carries
      the matching id (PUBACK / PUBREC / PUBCOMP / SUBACK / UNSUBACK).
      Publishing is still synchronous — one in flight — so this is
      currently hygiene + the groundwork for pipelined publishing.
- [x] **Background receive** — `mqtt_listen` spawns a reader thread
      (`std/thread.nu`) that owns the socket: it frames inbound packets,
      pushes every PUBLISH onto a `Channel MqttMessage`, consumes
      PINGRESP, and emits its own keep-alive PINGREQ. The app pulls
      messages with `mqtt_listener_recv` while doing other work;
      `mqtt_listener_stop` closes the channel, joins the thread, and the
      thread closes the connection on its way out — no socket-shutdown
      race. `example/mqtt_listener.nu` verifies it live (publisher +
      background subscriber, two connections).

## Phase 5 — Quality — PARTIAL

- [x] **Offline codec tests** — `compiler/tests/mqtt_codec.nu`. Covers
      the Variable Byte Integer encode/decode round-trip (1–4-byte
      values, incl. the 0x0FFFFFFF maximum), the unsigned byte reader
      (`__mqtt_byte`'s `& 255` mask on 0x80+ bytes), MQTT UTF-8 string
      framing, the CONNECT packet byte layout, CONNACK reason
      extraction, MQTT 5 user-property parsing, the typed `MqttErr`
      names, and topic-filter matching. No network — runs
      unconditionally in `run_tests.sh`, CI-safe.
- [ ] Gated live integration test (`NURL_NET_TESTS=1`). The
      `example/mqtt_*.nu` programs already verify the client end to end
      against a live broker; a CI-gated test still needs a broker
      fixture (a loopback mock or a spawned `mosquitto`).
- [x] **Topic-filter wildcard matching** — `mqtt_topic_matches s filter
      s topic → b` implements the MQTT 5.0 §4.7 rules: `+` matches one
      level, `#` matches the remainder (zero or more levels, so
      `sport/#` matches the parent `sport`). Includes the §4.7.2 guard
      — a filter whose first level is a wildcard never matches a topic
      whose first level begins with `$` (a `#` subscription does not
      pick up `$SYS/...`). For client-side dispatch when one connection
      carries several subscriptions.

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
