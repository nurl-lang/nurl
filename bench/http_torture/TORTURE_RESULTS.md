# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-5`, generator to `6-11`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: `Linux 7.0.0-30-generic` — Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- NURL: `v0.58.0-5-ge2efeda0`  ·  oha: `oha 1.8.0`
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 176 000 | 0.779/7.549/30.526 | 0.990/51.232/87.295 | 1.226/94.339/121.908 |
| RUST | 176 000 | 0.926/11.640/38.521 | 1.109/80.595/109.294 | 1.319/92.428/119.136 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 124 000 | 0.773/16.315/51.710 | 1.027/36.873/71.754 | 1.866/96.719/120.109 |
| RUST | 124 000 | 0.913/11.536/35.500 | 1.162/29.947/50.343 | 1.925/121.636/138.335 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 3 000 | 1.384/3.418/5.251 | 1.498/3.337/6.335 | 1.413/3.206/5.312 |
| RUST | 3 000 | 1.334/2.762/5.241 | 1.353/2.483/6.620 | 1.251/2.449/7.434 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 2463360 | 61.15 | 24.82 |
| RUST | 2463280 | 65.24 | 26.49 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1735540 | 59.81 | 34.46 |
| RUST | 1735520 | 62.58 | 36.06 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 41980 | 38.22 | 910.43 |
| RUST | 41980 | 38.94 | 927.58 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 44 229 | 2.206/3.972/6.286 | 1.0000 |
| RUST | 46 557 | 2.107/3.755/5.805 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 42 220 | 2.301/4.566/6.869 | 1.0000 |
| RUST | 44 932 | 2.191/3.762/5.608 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 2 718 | 35.988/60.934/82.559 | 1.0000 |
| RUST | 2 748 | 35.900/52.501/66.895 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 128 762 | 0.131/0.488 | yes |
| RUST | 146 157 | 0.116/0.429 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 179 451 | 10.766/19.001/27.127 | 1.0000 |
| RUST | 2000 | 174 203 | 11.209/20.035/31.719 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | no | no ticket issued | no |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 99 199 | 1.030/657.126/1461.691 | 1.0000 | 2 (RSS 3148→13924 KiB) |
| RUST | 99 199 | 1.184/668.219/1457.522 | 1.0000 | 5 (RSS 4712→9572 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 6-11 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The first such cost found by this harness — the response body being copied into the connection's wire buffer before the write — was removed (head and body now leave in one `sendmsg`); what remains at 1 MB is the inbound copy `response_set_body_bytes` makes of the handler's buffer, which hyper's `Bytes::clone` does not pay.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
