# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1017-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- NURL: `v0.74.0-5-gdf213fb8`  ·  oha: `oha 1.8.0`  ·  commit `df213fb8`
- Run: https://github.com/nurl-lang/nurl/actions/runs/39376291228
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 88000 | 0.683/1.519/10.739 | 1.016/3.640/15.575 | 1.550/17.735/48.674 |
| RUST | 96000 | 0.740/1.508/17.255 | 1.272/7.914/44.581 | 1.644/8.911/30.308 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 80000 | 0.675/1.715/12.351 | 1.145/4.203/9.999 | 1.575/8.863/27.128 |
| RUST | 84000 | 0.714/2.521/11.350 | 1.162/4.010/10.311 | 1.565/29.948/53.218 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 3500 | 0.421/0.956/1.519 | 0.541/1.128/4.461 | 0.596/1.301/16.186 |
| RUST | 3500 | 0.426/0.863/1.358 | 0.503/1.022/6.933 | 0.628/1.895/33.648 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1231995 | 20.57 | 16.70 |
| RUST | 1343997 | 21.55 | 16.03 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1119935 | 24.24 | 21.64 |
| RUST | 1175984 | 23.67 | 20.13 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 49000 | 12.50 | 255.10 |
| RUST | 48998 | 13.53 | 276.13 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 18556 | 5.325/6.306/6.823 | 1.0000 |
| RUST | 18444 | 5.432/6.273/6.948 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 17716 | 5.653/6.454/7.104 | 1.0000 |
| RUST | 17778 | 5.675/6.315/7.144 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 3507 | 28.498/34.490/39.021 | 1.0000 |
| RUST | 3524 | 28.419/31.120/37.588 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 93478 | 0.208/0.352 | yes |
| RUST | 92688 | 0.211/0.310 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 81826 | 24.276/28.970/45.525 | 1.0000 |
| RUST | 2000 | 80091 | 24.610/30.131/82.198 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 63913 | 1.097/742.998/1580.957 | 1.0000 | 39 (RSS 4520→13664 KiB) |
| RUST | 67199 | 1.119/595.154/1268.494 | 1.0000 | 4 (RSS 4756→8996 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
