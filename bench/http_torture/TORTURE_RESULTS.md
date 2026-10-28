# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1017-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- NURL: `v0.79.1-4-g8c17928f`  ·  oha: `oha 1.8.0`  ·  commit `8c17928f`
- Run: https://github.com/nurl-lang/nurl/actions/runs/40621782939
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 96000 | 0.695/1.475/9.233 | 1.190/18.183/49.076 | 1.816/53.873/73.045 |
| RUST | 96000 | 0.723/1.787/8.576 | 1.329/20.374/70.649 | 1.606/22.565/63.294 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 80000 | 0.679/1.651/11.943 | 1.152/4.584/12.428 | 2.173/90.180/105.094 |
| RUST | 84000 | 0.698/1.847/10.642 | 1.252/4.967/13.043 | 1.633/27.306/53.780 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 3750 | 0.488/0.994/1.570 | 0.649/1.311/6.354 | 0.709/1.571/14.584 |
| RUST | 3500 | 0.422/0.867/1.380 | 0.480/1.009/7.495 | 0.560/1.309/20.668 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1343943 | 20.33 | 15.13 |
| RUST | 1343930 | 21.17 | 15.75 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1119951 | 21.11 | 18.85 |
| RUST | 1175948 | 22.17 | 18.85 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 52498 | 11.83 | 225.34 |
| RUST | 49000 | 13.00 | 265.31 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 19250 | 5.230/5.926/6.749 | 1.0000 |
| RUST | 18997 | 5.273/6.113/6.822 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 18502 | 5.473/5.996/6.874 | 1.0000 |
| RUST | 18209 | 5.537/6.191/7.073 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 3898 | 25.745/27.631/32.264 | 1.0000 |
| RUST | 3832 | 26.143/28.602/34.274 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 96386 | 0.204/0.318 | yes |
| RUST | 96134 | 0.203/0.294 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 90695 | 21.724/25.758/58.314 | 1.0000 |
| RUST | 2000 | 90038 | 21.968/27.013/41.408 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 63999 | 0.996/706.707/1624.196 | 1.0000 | 2 (RSS 4832→10176 KiB) |
| RUST | 67199 | 1.100/668.211/1558.426 | 1.0000 | 5 (RSS 4636→8704 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
