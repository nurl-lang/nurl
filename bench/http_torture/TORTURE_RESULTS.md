# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 6.17.0-1022-azure` — AMD EPYC 9V74 80-Core Processor (4 CPUs)
- NURL: `v0.58.0-6-g07f21d04`  ·  oha: `oha 1.8.0`  ·  commit `07f21d04`
- Run: https://github.com/nurl-lang/nurl/actions/runs/33598821637
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 128000 | 0.759/1.463/4.837 | 1.288/3.491/5.614 | 1.717/8.229/14.085 |
| RUST | 128000 | 0.748/1.420/4.865 | 1.242/3.145/4.754 | 1.425/6.593/19.796 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 108000 | 0.712/1.487/5.749 | 1.151/2.855/5.882 | 6.910/391.569/397.580 |
| RUST | 120000 | 0.719/2.024/15.763 | 1.308/4.000/7.576 | 1.801/51.453/58.661 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 7250 | 2744.593/5316.772/5372.713 | 5495.623/10759.780/10855.263 | 0.782/25.181/98.087 |
| RUST | 7000 | 2539.209/5800.068/5891.011 | 5107.922/10271.228/10355.550 | 0.739/9.082/62.115 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1791540 | 23.15 | 12.92 |
| RUST | 1791560 | 22.53 | 12.58 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1511500 | 23.67 | 15.66 |
| RUST | 1679580 | 26.42 | 15.73 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 68180 | 37.65 | 552.21 |
| RUST | 59420 | 39.28 | 661.06 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 24346 | 4.107/4.904/8.110 | 1.0000 |
| RUST | 25408 | 3.946/4.622/5.125 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 24167 | 4.164/4.775/5.739 | 1.0000 |
| RUST | 24389 | 4.131/4.658/5.174 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 3960 | 25.383/29.684/35.344 | 1.0000 |
| RUST | 4152 | 24.125/28.906/31.630 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 126224 | 0.146/0.461 | yes |
| RUST | 129799 | 0.154/0.219 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 99642 | 19.701/27.048/48.652 | 1.0000 |
| RUST | 2000 | 114878 | 17.200/20.810/29.775 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 60s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 86394 | 0.973/2.519/22.194 | 1.0000 | 6 (RSS 3168→11296 KiB) |
| RUST | 95991 | 1.093/3.078/40.324 | 1.0000 | 2 (RSS 4644→9200 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
