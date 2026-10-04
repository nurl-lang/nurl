# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 6.17.0-1022-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- NURL: `v0.70.0-3-gf7fb2d1a`  ·  oha: `oha 1.8.0`  ·  commit `f7fb2d1a`
- Run: https://github.com/nurl-lang/nurl/actions/runs/37230900263
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 104000 | 0.726/1.352/7.883 | 1.321/3.896/9.626 | 1.649/6.666/9.977 |
| RUST | 104000 | 0.723/1.307/3.167 | 1.224/3.021/11.518 | 1.583/8.682/21.936 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 88000 | 0.698/1.275/8.016 | 1.255/2.943/8.019 | 1.603/7.864/30.985 |
| RUST | 92000 | 0.723/1.379/5.928 | 1.267/2.933/7.282 | 1.653/21.555/39.315 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 6500 | 0.647/1.304/2.048 | 0.911/2.498/41.734 | 0.949/20.928/93.598 |
| RUST | 6500 | 0.535/1.104/1.869 | 0.951/1.966/16.546 | 1.098/15.561/77.517 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1455919 | 23.63 | 16.23 |
| RUST | 1455981 | 22.85 | 15.69 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1231935 | 24.32 | 19.74 |
| RUST | 1287942 | 24.52 | 19.04 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 90996 | 26.38 | 289.90 |
| RUST | 90996 | 25.96 | 285.29 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 19658 | 5.049/5.913/6.164 | 1.0000 |
| RUST | 19610 | 5.125/5.876/6.197 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 18899 | 5.323/6.051/6.292 | 1.0000 |
| RUST | 18628 | 5.420/6.002/6.312 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 4024 | 24.996/26.494/27.682 | 1.0000 |
| RUST | 4140 | 24.268/25.632/27.414 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 95764 | 0.204/0.336 | yes |
| RUST | 94435 | 0.208/0.312 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 98459 | 19.935/23.677/60.032 | 1.0000 |
| RUST | 2000 | 97860 | 20.178/22.710/33.082 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 60s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 70392 | 1.154/3.492/47.276 | 1.0000 | 4 (RSS 3356→11224 KiB) |
| RUST | 73592 | 1.297/3.952/39.230 | 1.0000 | 3 (RSS 4588→8776 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
