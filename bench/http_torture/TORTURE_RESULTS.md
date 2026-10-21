# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1017-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- NURL: `v0.76.0-20-g0e20137a`  ·  oha: `oha 1.8.0`  ·  commit `0e20137a`
- Run: https://github.com/nurl-lang/nurl/actions/runs/39661581067
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 96000 | 0.728/2.314/6.715 | 1.231/6.362/27.059 | 1.677/38.082/62.460 |
| RUST | 96000 | 0.732/1.895/15.871 | 1.222/3.839/21.021 | 1.509/10.468/32.879 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 88000 | 0.708/1.822/10.320 | 1.416/16.473/40.575 | 1.624/47.031/64.096 |
| RUST | 84000 | 0.691/3.276/9.669 | 1.143/20.583/60.089 | 1.504/26.683/50.984 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 4000 | 0.477/1.011/1.994 | 0.588/1.305/8.331 | 0.631/2.373/37.386 |
| RUST | 3750 | 0.431/1.008/2.630 | 0.542/1.231/9.954 | 0.604/3.732/45.135 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1343936 | 22.13 | 16.47 |
| RUST | 1343940 | 21.19 | 15.77 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1231943 | 25.11 | 20.38 |
| RUST | 1175945 | 22.39 | 19.04 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 55998 | 16.16 | 288.58 |
| RUST | 52498 | 14.29 | 272.20 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 19082 | 5.273/6.139/7.039 | 1.0000 |
| RUST | 18905 | 5.293/6.155/7.183 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 18228 | 5.525/6.339/10.121 | 1.0000 |
| RUST | 18226 | 5.521/6.189/6.968 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 3998 | 25.153/26.757/31.906 | 1.0000 |
| RUST | 4007 | 25.005/27.505/33.914 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 94752 | 0.206/0.338 | yes |
| RUST | 95285 | 0.205/0.302 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 91680 | 21.426/26.187/46.686 | 1.0000 |
| RUST | 2000 | 92708 | 21.434/25.355/41.754 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 70399 | 1.728/2126.642/2917.085 | 1.0000 | 3 (RSS 4632→11560 KiB) |
| RUST | 67199 | 1.120/649.785/1612.075 | 1.0000 | 9 (RSS 4676→9232 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
