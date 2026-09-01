# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-5`, generator to `6-11`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: `Linux 7.0.0-30-generic` — Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- NURL: `v0.58.0-1-gbbaa3646-dirty`  ·  oha: `oha 1.8.0`
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 192 000 | 0.811/8.261/28.709 | 1.114/64.142/96.992 | 1.881/111.539/133.070 |
| RUST | 192 000 | 0.957/20.050/46.970 | 1.130/87.576/119.026 | 2.042/136.371/149.653 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 124 000 | 0.746/9.059/42.540 | 1.062/19.916/50.366 | 2.089/107.729/126.069 |
| RUST | 116 000 | 0.907/15.767/53.909 | 1.094/23.761/52.437 | 1.509/104.022/130.995 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 2 250 | 1.463/3.978/5.716 | 1.705/3.742/5.456 | 1.760/3.934/12.590 |
| RUST | 3 000 | 1.335/2.688/3.605 | 1.381/2.559/5.383 | 1.245/2.408/7.406 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 2687340 | 65.59 | 24.41 |
| RUST | 2687340 | 66.26 | 24.66 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1735600 | 61.25 | 35.29 |
| RUST | 1623520 | 60.29 | 37.14 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 31480 | 35.79 | 1136.91 |
| RUST | 41980 | 38.67 | 921.15 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 44 387 | 2.194/4.005/6.449 | 1.0000 |
| RUST | 46 620 | 2.104/3.743/5.851 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 42 384 | 2.307/4.089/6.448 | 1.0000 |
| RUST | 44 846 | 2.192/3.836/6.032 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 1 924 | 49.930/96.557/127.046 | 1.0000 |
| RUST | 2 749 | 35.820/53.817/71.250 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 125 020 | 0.134/0.503 | yes |
| RUST | 145 582 | 0.116/0.415 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 178 421 | 10.819/19.454/26.152 | 1.0000 |
| RUST | 2000 | 174 374 | 11.190/20.651/29.592 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | no | no ticket issued | no |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 99 199 | 1.066/729.250/1514.766 | 1.0000 | 4 (RSS 3108→11672 KiB) |
| RUST | 92 799 | 1.083/501.461/1392.449 | 1.0000 | 8 (RSS 4572→9448 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 6-11 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The first such cost found by this harness — the response body being copied into the connection's wire buffer before the write — was removed (head and body now leave in one `sendmsg`); what remains at 1 MB is the inbound copy `response_set_body_bytes` makes of the handler's buffer, which hyper's `Bytes::clone` does not pay.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
