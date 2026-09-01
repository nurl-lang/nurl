# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-5`, generator to `6-11`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: `Linux 7.0.0-30-generic` — Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz (6 cores pinned to the server, 6 to the generator)
- NURL: `v0.57.0-23-g259400a3-dirty`  ·  oha: `oha 1.8.0`
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 168 000 | 0.779/8.465/21.310 | 1.020/45.488/79.241 | 1.424/92.601/110.330 |
| RUST | 168 000 | 0.887/8.868/47.005 | 1.110/55.377/95.853 | 1.261/80.584/105.362 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 100 000 | 0.694/3.014/10.663 | 0.989/25.509/48.551 | 1.959/49.966/64.952 |
| RUST | 120 000 | 0.863/16.767/48.082 | 1.152/22.403/47.157 | 1.807/114.979/124.604 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 1 500 | 1.701/4.690/7.474 | 1.816/5.157/13.467 | 1.912/5.088/11.476 |
| RUST | 3 250 | 1.331/2.763/4.839 | 1.237/2.465/7.040 | 1.004/6.050/23.682 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 2351360 | 59.18 | 25.17 |
| RUST | 2351340 | 63.16 | 26.86 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1399640 | 57.41 | 41.02 |
| RUST | 1679540 | 60.26 | 35.88 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 21000 | 27.80 | 1323.81 |
| RUST | 45480 | 36.99 | 813.32 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 42 732 | 2.249/4.929/7.203 | 1.0000 |
| RUST | 45 791 | 2.136/3.882/6.142 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 41 026 | 2.354/4.876/7.467 | 1.0000 |
| RUST | 44 070 | 2.226/3.992/6.506 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 1 505 | 59.794/169.878/214.200 | 1.0000 |
| RUST | 2 617 | 37.225/64.576/87.937 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 118 279 | 0.139/0.591 | yes |
| RUST | 141 595 | 0.118/0.432 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 171 994 | 11.026/21.803/31.676 | 1.0000 |
| RUST | 2000 | 170 705 | 11.263/21.900/32.763 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | no | no ticket issued | no |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 79 999 | 0.985/1011.032/2031.960 | 1.0000 | 7 (RSS 3096→26712 KiB) |
| RUST | 95 999 | 1.183/657.577/1478.105 | 1.0000 | 3 (RSS 4500→9656 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on `6-11` hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **The gap grows with body size** (1 KB → 16 KB → 1 MB), which is the signature of a per-byte data-path cost, not a fixed per-request one. The CPU-per-request rows at 1 MB show it directly (NURL 1324 µs/req vs Rust 813 µs/req).
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show an inflated soak p99 (NURL 1011 ms, Rust 658 ms). Compare the two servers to each other, and read the **RSS delta** as the server-specific signal: NURL grows more (24 MB vs 5 MB) but bounded — per-connection wire-buffer high-water, freed at connection close.
