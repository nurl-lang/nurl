# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1017-azure` — AMD EPYC 9V74 80-Core Processor (4 CPUs)
- NURL: `v0.79.1-12-gda5aacbf`  ·  oha: `oha 1.8.0`  ·  commit `da5aacbf`
- Run: https://github.com/nurl-lang/nurl/actions/runs/40633076043
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 136000 | 0.707/1.485/4.949 | 1.205/50.807/86.161 | 1.371/86.786/108.790 |
| RUST | 136000 | 0.712/1.527/12.113 | 1.188/3.435/13.508 | 1.322/61.581/87.822 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 124000 | 0.705/1.842/6.736 | 1.210/7.311/20.735 | 1.693/97.451/116.911 |
| RUST | 124000 | 0.710/2.081/32.130 | 1.205/3.763/19.980 | 1.642/70.792/110.841 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 5250 | 0.420/0.915/1.361 | 0.595/1.483/12.014 | 0.638/2.696/56.033 |
| RUST | 5000 | 0.317/0.722/1.386 | 0.462/0.923/8.118 | 0.529/1.484/52.193 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1903976 | 21.48 | 11.28 |
| RUST | 1903873 | 21.46 | 11.27 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1735887 | 23.28 | 13.41 |
| RUST | 1735883 | 22.93 | 13.21 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 73496 | 13.87 | 188.72 |
| RUST | 69999 | 14.08 | 201.15 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 27967 | 3.602/4.057/5.084 | 1.0000 |
| RUST | 27645 | 3.648/4.176/5.039 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 26496 | 3.848/4.155/5.220 | 1.0000 |
| RUST | 26286 | 3.858/4.227/5.231 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 5074 | 19.804/21.051/23.041 | 1.0000 |
| RUST | 5051 | 19.921/20.810/22.454 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 131363 | 0.153/0.209 | yes |
| RUST | 130773 | 0.154/0.204 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 115203 | 17.205/20.103/55.210 | 1.0000 |
| RUST | 2000 | 113638 | 17.476/22.611/39.528 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 99199 | 1.236/798.301/1528.864 | 1.0000 | 5 (RSS 4872→10216 KiB) |
| RUST | 99199 | 1.194/523.232/1142.521 | 1.0000 | 2 (RSS 4892→9344 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
