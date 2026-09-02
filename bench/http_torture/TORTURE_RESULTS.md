# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-5`, generator to `6-11`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: `Linux 7.0.0-30-generic` — Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- NURL: `v0.58.0-5-ge2efeda0-dirty`  ·  oha: `oha 1.8.0`
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 168 000 | 0.777/7.319/31.090 | 0.967/48.246/85.581 | 1.178/90.547/120.673 |
| RUST | 176 000 | 0.933/12.442/43.709 | 1.083/70.413/109.135 | 1.349/117.797/142.938 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 124 000 | 0.751/14.031/39.901 | 1.058/26.396/52.189 | 1.856/111.963/123.016 |
| RUST | 120 000 | 0.893/10.211/30.927 | 1.149/21.294/48.880 | 1.680/130.545/149.884 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 3 250 | 1.439/3.572/5.132 | 1.411/3.228/9.508 | 1.356/3.272/14.062 |
| RUST | 3 000 | 1.327/2.705/4.933 | 1.297/2.476/5.115 | 1.245/2.475/5.906 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 2351400 | 59.07 | 25.12 |
| RUST | 2463240 | 65.34 | 26.53 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1735560 | 59.07 | 34.04 |
| RUST | 1679580 | 61.85 | 36.82 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 45480 | 39.66 | 872.03 |
| RUST | 41980 | 36.34 | 865.65 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 44 177 | 2.202/4.122/6.645 | 1.0000 |
| RUST | 46 490 | 2.112/3.723/5.605 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 42 428 | 2.301/4.104/6.691 | 1.0000 |
| RUST | 44 839 | 2.191/3.854/6.421 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 2 742 | 35.787/54.964/68.533 | 1.0000 |
| RUST | 2 747 | 35.904/52.944/69.619 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 127 577 | 0.132/0.482 | yes |
| RUST | 145 094 | 0.116/0.417 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 176 121 | 10.905/19.452/26.945 | 1.0000 |
| RUST | 2000 | 174 321 | 11.159/19.551/29.689 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 99 199 | 1.044/677.947/1484.873 | 1.0000 | 6 (RSS 3144→13684 KiB) |
| RUST | 95 999 | 1.127/614.001/1477.160 | 1.0000 | 4 (RSS 4708→9064 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 6-11 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
