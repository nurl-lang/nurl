# NURL HTTP/3-server peer-comparison

Generated `2026-09-03T09:53:18Z` by `bench/run_http3.sh`. **Do not edit by hand** — the next run overwrites it.

The HTTP/3 companion of [`HTTP_RESULTS.md`](HTTP_RESULTS.md) (HTTP/1.1) and [`HTTP2_RESULTS.md`](HTTP2_RESULTS.md) (HTTP/2), which stay as they are. Each implementation terminates QUIC (RFC 9000/9001/9002) on a UDP socket, speaks HTTP/3 (RFC 9114 + QPACK, RFC 9204) and answers every request on every stream with the same 14-byte `Hello, World!\n` body (`text/plain`), over a self-signed EC (P-256) certificate the generator accepts without verification.

The NURL server is `bench/http_server.nu` **unchanged from the HTTP/1.1 and HTTP/2 benchmarks**: the `packages/http` HttpApp facade's TLS listener also binds its port over UDP and serves HTTP/3 there through the same routes; the QUIC transport, the TLS 1.3 handshake inside it, QPACK and the HTTP/3 framing are all pure NURL. The Rust peer is `quinn` + `h3` (`h3-quinn`) on tokio with rustls — the stack behind most Rust HTTP/3 servers.

**Cells are `C x M`: C client connections, each with M concurrent streams** (`h2load --h3 -c C -m M`), so C x M requests are in flight. The same closed-loop caveat as the HTTP/2 report applies: at high in-flight counts read `req/s`, not the latency columns; cells whose effective concurrency (`req/s x mean-latency`) falls well short of C x M are marked ‡ and left un-bold.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `cdd5b317376ef7fa7f153c44af8daa78577536c9` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33740577353 |
| NURL | `v0.59.0-3-gcdd5b317` |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |
| Load generator | h2load nghttp2/1.70.0 (docker nghttp2-h3) |

| Setting | Value |
|---|---|
| Throughput/latency | median of 3 x 10 s closed-loop runs |
| Cells (C x M) | 1x1 , 1x10 , 1x100 , 10x1 , 10x10 , 50x1 , 50x10 |
| Connection setup | 100 fresh connections, one request each, median of 3 runs |
| TLS cert | self-signed EC P-256, `CN=localhost`, ALPN `h3` |

## 1. HTTP/3 over QUIC

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **10 223** | **65 648** | **167 693** | **36 044** | **137 410** | **35 170** | **139 478** |
|              | Rust    | 52 | 20 157 | 48 742 | 400 | 37 527 | 1 920 | 25 834 |
| **p50 (ms)** | NURL    | **0.09** | **0.14** | 0.45‡ | **0.25** | 0.70 | **1.40** | **3.53** |
|              | Rust    | 26.39 | 0.44 | 1.41‡ | 26.19 | **0.52** | 26.24 | 26.02 |
| **p99 (ms)** | NURL    | **0.12** | **0.18** | 0.73‡ | **0.47** | **1.36** | **1.64** | **6.46** |
|              | Rust    | 26.73 | 1.24 | 3.02‡ | 27.12 | 26.20 | 27.27 | 27.35 |

‡ closed-loop starved (NURL 1x100: ~78.8 in flight; Rust 1x100: ~71.7 in flight).

## 2. NURL, same server and listener: HTTP/3 vs HTTP/2 (M = 1)

The same binary and the same host:port — QUIC over UDP for HTTP/3, TLS over TCP with ALPN `h2` for HTTP/2 — driven by the same `h2load`. The gap is the transports' own cost (packet protection and per-packet framing for QUIC, records for TLS/TCP) with everything else held equal. HTTP/1.1 on this listener is in `HTTP_RESULTS.md` (oha): h2load's HTTP/1.1 mode paces itself and would misreport it.

| C | HTTP/3 req/s | HTTP/2 req/s | HTTP/3 / HTTP/2 | HTTP/3 p50 (ms) | HTTP/2 p50 (ms) |
|--:|-----------:|-----------:|---------------:|----------------:|----------------:|
| 1 | 10 223 | 1 000 | 10.22x | 0.09 | 0.04 |
| 10 | 36 044 | 10 000 | 3.60x | 0.25 | 0.21 |
| 50 | 35 170 | 32 473 | 1.08x | 1.40 | 0.79 |

## 3. Connection setup rate

100 clients each open a fresh connection, make one request and close: a QUIC handshake (Initial + Handshake, one round trip, keys derived on both ends) for HTTP/3, a TLS 1.3 handshake over a new TCP connection for HTTP/2. Connections per second, median of the runs.

| Server | Protocol | conn/s |
|---|---|------:|
| NURL | HTTP/3 (QUIC) | 1 089 |
| NURL | HTTP/2 (TLS+TCP) | 935 |
| Rust | HTTP/3 (QUIC) | 1 008 |

(Best per column in **bold**; latency winners are chosen only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server did not complete that cell.)

## Notes

- The load generator is nghttp2's `h2load` built with ngtcp2 + nghttp3 (the distribution package is HTTP/2-only), run from a docker image built from nghttp2's own `docker/Dockerfile`. `oha`, the generator of the other two reports, has no HTTP/3 client.
- No Node column: Node has no HTTP/3 server. The Rust peer is `bench/rust_http3_server/` (quinn + h3 + rustls), run with quinn's default transport settings.
- **Read the Rust column as "quinn's defaults under this generator".** An h2load trace shows an ACK interlock at low concurrency: quinn does not piggyback a pending (delayed) ACK on the response packet and sends it alone up to `max_ack_delay` (25 ms) later, and ngtcp2's client does not open its next request stream until the packet that carried the previous one is acknowledged — so with few streams in flight every request costs ~25 ms regardless of the server's work. NURL bundles the pending ACK into any packet it sends (RFC 9000 §13.2.1), which is why its columns do not show it. The cells with many streams per connection are the ones where both servers are actually busy.
- HTTP/3 conformance is not this report's job: `tools/h3spec_gate.sh` runs h3spec (49/49: 34 QUIC-transport + 15 HTTP/3 and QPACK error cases) against the same NURL HttpApp listener in CI. A fast server that fails h3spec would not be listed as a win.
- Loopback only, 14-byte body, no packet loss: what is measured is per-packet CPU cost (AEAD, header protection, framing, ACK bookkeeping), not congestion control. Compare columns within one run, not across machines.

### Planned rigor

1. **Realistic bodies** (1 KB / 16 KB / 1 MB) where flow control, pacing and datagram size matter.
2. **Lossy paths** (`tc netem` loss/delay) — the QUIC recovery machinery is not exercised on loopback.
3. **Batched UDP I/O** (`recvmmsg` / GSO) and core isolation, as in the torture harness.
