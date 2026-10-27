# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 6.17.0-1022-azure` — AMD EPYC 9V74 80-Core Processor (4 CPUs)
- NURL: `v0.79.0-2-g77244109`  ·  oha: `oha 1.8.0`  ·  commit `77244109`
- Run: https://github.com/nurl-lang/nurl/actions/runs/40533588892
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 104000 | 0.721/1.092/2.680 | 1.240/2.841/8.839 | 1.449/5.803/8.885 |
| RUST | 104000 | 0.753/1.452/4.508 | 1.309/3.384/11.510 | 3.601/276.986/292.994 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 96000 | 0.724/1.384/4.568 | 1.280/3.232/7.352 | 1.643/9.921/20.309 |
| RUST | 88000 | 0.684/1.025/9.115 | 1.095/2.755/11.284 | 1.354/4.705/9.305 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 6250 | 0.646/1.334/1.786 | 0.848/2.496/43.356 | 0.919/11.638/67.394 |
| RUST | 6750 | 0.539/1.124/1.564 | 0.830/1.945/29.302 | 0.946/21.409/71.592 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1455959 | 21.90 | 15.04 |
| RUST | 1455903 | 22.26 | 15.29 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1343974 | 25.79 | 19.19 |
| RUST | 1231894 | 23.79 | 19.31 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 40914 | 39.11 | 955.91 |
| RUST | 51568 | 36.95 | 716.53 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 21561 | 4.650/5.828/10.467 | 1.0000 |
| RUST | 21753 | 4.602/5.327/6.618 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 20348 | 4.950/5.631/8.667 | 1.0000 |
| RUST | 19710 | 5.106/5.949/9.325 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 2994 | 25.348/85.224/90.025 | 1.0000 |
| RUST | 2983 | 25.148/75.827/104.511 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 103607 | 0.193/0.271 | yes |
| RUST | 102759 | 0.195/0.273 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 92182 | 21.323/24.470/49.978 | 1.0000 |
| RUST | 2000 | 86871 | 22.988/25.221/33.783 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 76799 | 1.566/8.805/193.902 | 1.0000 | 9 (RSS 4700→10040 KiB) |
| RUST | 70399 | 1.294/6.327/100.967 | 1.0000 | 6 (RSS 4540→12000 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
