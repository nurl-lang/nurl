# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 6.17.0-1022-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- NURL: `v0.77.2-40-g92f437fb`  ·  oha: `oha 1.8.0`  ·  commit `92f437fb`
- Run: https://github.com/nurl-lang/nurl/actions/runs/40084156574
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 104000 | 0.723/1.138/3.556 | 1.290/12.490/32.258 | 1.537/5.734/10.036 |
| RUST | 104000 | 0.734/1.397/6.330 | 1.206/2.780/6.095 | 1.519/5.623/8.427 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 92000 | 0.710/1.432/8.727 | 1.159/2.724/6.437 | 1.587/5.844/11.238 |
| RUST | 92000 | 0.706/1.302/5.284 | 1.167/3.527/11.248 | 1.550/7.104/19.655 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 6500 | 0.647/1.294/1.709 | 0.865/2.279/21.483 | 0.925/13.877/72.318 |
| RUST | 6750 | 0.571/1.131/1.855 | 0.776/1.645/21.568 | 0.915/14.963/63.830 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1455908 | 21.92 | 15.06 |
| RUST | 1455924 | 22.20 | 15.25 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1287934 | 23.24 | 18.04 |
| RUST | 1287934 | 24.25 | 18.83 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 91000 | 22.47 | 246.92 |
| RUST | 94496 | 24.08 | 254.83 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 20448 | 4.935/5.634/5.947 | 1.0000 |
| RUST | 19889 | 5.047/5.795/6.090 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 19347 | 5.233/5.793/6.106 | 1.0000 |
| RUST | 19238 | 5.244/5.839/6.221 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 4144 | 24.318/25.302/26.189 | 1.0000 |
| RUST | 4252 | 23.692/24.714/25.648 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 99274 | 0.197/0.302 | yes |
| RUST | 96256 | 0.204/0.306 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 103249 | 19.170/21.446/40.395 | 1.0000 |
| RUST | 2000 | 103558 | 19.115/22.110/86.658 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 73599 | 1.117/2.869/119.198 | 1.0000 | 4 (RSS 4696→10024 KiB) |
| RUST | 73599 | 1.147/3.497/230.244 | 1.0000 | 3 (RSS 4420→10568 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
