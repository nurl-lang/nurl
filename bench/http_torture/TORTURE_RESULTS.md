# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 6.17.0-1022-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- NURL: `v0.78.0-12-gd216fa60`  ·  oha: `oha 1.8.0`  ·  commit `d216fa60`
- Run: https://github.com/nurl-lang/nurl/actions/runs/40301939473
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 104000 | 0.719/1.253/7.802 | 1.211/3.131/14.833 | 1.540/7.780/20.672 |
| RUST | 104000 | 0.735/1.292/3.987 | 1.158/2.855/8.090 | 1.546/6.723/16.241 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 92000 | 0.710/1.239/6.176 | 1.142/3.708/10.372 | 1.510/5.657/16.025 |
| RUST | 92000 | 0.714/1.231/6.812 | 1.140/2.976/14.798 | 1.716/75.223/91.746 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 6250 | 0.621/1.257/1.690 | 0.810/2.102/17.333 | 0.901/7.526/69.724 |
| RUST | 6500 | 0.527/1.076/1.601 | 0.766/1.629/19.468 | 0.863/5.212/61.485 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1455859 | 21.82 | 14.99 |
| RUST | 1455942 | 22.23 | 15.27 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1287936 | 23.45 | 18.21 |
| RUST | 1287939 | 23.61 | 18.33 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 87500 | 20.69 | 236.46 |
| RUST | 90996 | 22.75 | 250.01 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 20186 | 4.982/5.715/5.958 | 1.0000 |
| RUST | 19824 | 5.050/5.829/6.146 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 19331 | 5.232/5.839/6.145 | 1.0000 |
| RUST | 19034 | 5.297/5.885/6.177 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 4135 | 24.338/25.486/26.485 | 1.0000 |
| RUST | 4230 | 23.744/25.241/26.284 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 99613 | 0.197/0.297 | yes |
| RUST | 98099 | 0.199/0.295 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 102929 | 19.122/21.740/39.699 | 1.0000 |
| RUST | 2000 | 102520 | 19.137/22.837/65.823 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 73599 | 1.123/2.907/85.568 | 1.0000 | 4 (RSS 4692→10024 KiB) |
| RUST | 73599 | 1.107/2.850/109.888 | 1.0000 | 2 (RSS 4448→11608 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
