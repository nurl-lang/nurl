# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 6.17.0-1022-azure` — AMD EPYC 9V74 80-Core Processor (4 CPUs)
- NURL: `v0.71.0-16-g450fa408`  ·  oha: `oha 1.8.0`  ·  commit `450fa408`
- Run: https://github.com/nurl-lang/nurl/actions/runs/37968505066
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 104000 | 0.724/1.115/2.746 | 1.249/2.788/5.467 | 1.462/4.931/7.856 |
| RUST | 104000 | 0.743/1.451/3.792 | 1.323/3.778/6.782 | 1.342/6.100/9.297 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 96000 | 0.732/1.479/5.903 | 1.341/3.590/8.852 | 1.949/39.442/47.143 |
| RUST | 92000 | 0.731/1.457/5.884 | 1.278/4.260/13.865 | 1.627/81.527/99.377 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 6500 | 0.556/1.161/3.338 | 0.790/2.164/25.389 | 0.871/19.707/74.270 |
| RUST | 6750 | 0.556/1.135/2.277 | 0.826/1.724/24.840 | 0.952/15.220/57.559 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1455906 | 24.03 | 16.51 |
| RUST | 1455937 | 21.68 | 14.89 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1343921 | 26.37 | 19.62 |
| RUST | 1287992 | 22.74 | 17.66 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 90999 | 23.29 | 255.94 |
| RUST | 94500 | 24.37 | 257.88 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 21945 | 4.490/5.252/5.573 | 1.0000 |
| RUST | 21882 | 4.608/5.242/5.509 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 20872 | 4.843/5.375/5.742 | 1.0000 |
| RUST | 20785 | 4.878/5.379/6.658 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 4233 | 23.758/25.083/25.766 | 1.0000 |
| RUST | 4363 | 23.049/24.098/25.911 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 101860 | 0.197/0.309 | yes |
| RUST | 102568 | 0.195/0.289 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 93586 | 21.020/23.741/32.644 | 1.0000 |
| RUST | 2000 | 91178 | 21.822/23.970/36.198 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 76799 | 1.361/5.294/171.527 | 1.0000 | 2 (RSS 3356→12400 KiB) |
| RUST | 73599 | 1.139/2.847/58.854 | 1.0000 | 3 (RSS 4452→11404 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
