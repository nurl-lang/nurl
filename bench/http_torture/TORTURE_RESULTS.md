# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1017-azure` — AMD EPYC 9V74 80-Core Processor (4 CPUs)
- NURL: `v0.80.0-54-g29401773`  ·  oha: `oha 1.8.0`  ·  commit `29401773`
- Run: https://github.com/nurl-lang/nurl/actions/runs/40868083024
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 120000 | 0.674/1.775/25.840 | 1.032/2.700/11.716 | 1.378/65.243/90.576 |
| RUST | 136000 | 0.743/1.922/19.687 | 1.337/14.660/47.455 | 1.372/67.029/85.702 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 112000 | 0.716/2.801/29.632 | 1.236/3.556/8.780 | 1.551/49.865/62.626 |
| RUST | 112000 | 0.714/2.082/10.094 | 1.164/4.619/28.349 | 1.444/9.762/74.027 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 4750 | 0.438/0.915/1.311 | 0.605/1.307/6.524 | 0.626/1.719/46.411 |
| RUST | 4500 | 0.328/0.756/1.384 | 0.436/0.919/6.182 | 0.512/1.429/46.928 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1679966 | 19.65 | 11.70 |
| RUST | 1903965 | 22.04 | 11.58 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1567888 | 22.10 | 14.10 |
| RUST | 1567884 | 22.29 | 14.22 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 66499 | 12.83 | 192.94 |
| RUST | 62996 | 12.78 | 202.87 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 27986 | 3.608/4.059/4.978 | 1.0000 |
| RUST | 27732 | 3.648/4.117/4.951 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 26299 | 3.872/4.197/5.432 | 1.0000 |
| RUST | 26154 | 3.884/4.256/5.227 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 4608 | 21.723/23.490/25.048 | 1.0000 |
| RUST | 4554 | 21.995/23.869/26.222 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 131694 | 0.152/0.210 | yes |
| RUST | 129889 | 0.154/0.210 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 97696 | 20.266/22.626/49.373 | 1.0000 |
| RUST | 2000 | 98660 | 20.099/25.053/50.457 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 89599 | 1.134/606.678/1357.683 | 1.0000 | 4 (RSS 4836→10184 KiB) |
| RUST | 89599 | 1.129/401.701/1255.698 | 1.0000 | 2 (RSS 4804→9324 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
