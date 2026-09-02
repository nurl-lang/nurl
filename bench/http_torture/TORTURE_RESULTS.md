# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 6.17.0-1022-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- NURL: `v0.58.0-12-ge2bd3e5e`  ·  oha: `oha 1.8.0`  ·  commit `e2bd3e5e`
- Run: https://github.com/nurl-lang/nurl/actions/runs/33632397503
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 88000 | 0.568/0.961/6.125 | 1.002/2.419/6.318 | 1.318/3.688/6.489 |
| RUST | 96000 | 0.731/1.202/6.551 | 1.164/2.770/5.195 | 1.591/6.647/18.585 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 84000 | 0.703/1.361/6.341 | 1.128/2.919/7.131 | 1.756/21.474/31.025 |
| RUST | 88000 | 0.713/1.422/6.388 | 1.208/5.298/29.545 | 1.668/6.633/11.218 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 6000 | 0.545/1.109/2.074 | 0.732/2.861/39.758 | 0.847/27.777/115.133 |
| RUST | 6250 | 0.547/1.166/2.939 | 0.775/1.694/19.962 | 0.867/21.281/80.725 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1231560 | 21.02 | 17.07 |
| RUST | 1343520 | 23.03 | 17.14 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1175600 | 23.05 | 19.61 |
| RUST | 1231560 | 24.08 | 19.55 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 83980 | 21.29 | 253.51 |
| RUST | 87480 | 22.42 | 256.29 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 19002 | 5.197/6.190/6.484 | 1.0000 |
| RUST | 19281 | 5.215/5.970/6.283 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 18400 | 5.433/6.224/6.438 | 1.0000 |
| RUST | 18213 | 5.543/6.136/6.472 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 3744 | 26.810/28.966/30.143 | 1.0000 |
| RUST | 3858 | 25.978/28.893/30.085 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 94412 | 0.208/0.340 | yes |
| RUST | 94726 | 0.207/0.307 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 86353 | 23.108/25.614/41.860 | 1.0000 |
| RUST | 2000 | 86558 | 22.882/25.401/37.440 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 67199 | 1.171/3.920/263.914 | 1.0000 | 5 (RSS 3108→8352 KiB) |
| RUST | 70399 | 1.286/5.067/234.717 | 1.0000 | 5 (RSS 4524→11976 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
