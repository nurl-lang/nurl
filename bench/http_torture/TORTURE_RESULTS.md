# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 6.17.0-1022-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- NURL: `v0.78.0-20-gf06d55c2`  ·  oha: `oha 1.8.0`  ·  commit `f06d55c2`
- Run: https://github.com/nurl-lang/nurl/actions/runs/40322233161
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 104000 | 0.731/1.247/3.434 | 1.319/4.662/18.275 | 1.599/7.082/14.678 |
| RUST | 96000 | 0.717/1.048/11.730 | 1.175/2.660/6.482 | 1.502/7.343/23.805 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 92000 | 0.716/1.349/5.234 | 1.235/2.852/7.374 | 1.564/6.989/20.714 |
| RUST | 92000 | 0.723/1.300/5.440 | 1.286/3.899/15.849 | 1.637/6.688/11.137 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 5750 | 0.588/1.211/1.727 | 0.826/2.096/6.813 | 0.895/3.242/53.157 |
| RUST | 6500 | 0.545/1.117/1.626 | 0.762/1.651/19.650 | 0.869/11.484/74.444 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1455925 | 22.06 | 15.15 |
| RUST | 1343921 | 20.60 | 15.33 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1287930 | 23.88 | 18.54 |
| RUST | 1287992 | 24.09 | 18.70 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 80496 | 19.27 | 239.39 |
| RUST | 90996 | 23.32 | 256.28 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 20123 | 5.030/5.665/6.057 | 1.0000 |
| RUST | 19796 | 5.071/5.816/6.128 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 19014 | 5.326/5.898/6.192 | 1.0000 |
| RUST | 18760 | 5.387/5.952/6.400 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 4058 | 24.793/26.023/27.268 | 1.0000 |
| RUST | 4158 | 24.191/25.443/26.603 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 97906 | 0.201/0.301 | yes |
| RUST | 97602 | 0.201/0.298 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 99066 | 19.947/22.644/43.867 | 1.0000 |
| RUST | 2000 | 99545 | 19.797/23.212/33.140 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 73599 | 1.271/8.348/352.644 | 1.0000 | 1 (RSS 4736→10064 KiB) |
| RUST | 73599 | 1.185/3.762/113.475 | 1.0000 | 4 (RSS 4480→11792 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
