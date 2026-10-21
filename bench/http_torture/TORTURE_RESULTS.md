# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1017-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- NURL: `v0.76.0-15-g79092641`  ·  oha: `oha 1.8.0`  ·  commit `79092641`
- Run: https://github.com/nurl-lang/nurl/actions/runs/39620252634
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 88000 | 0.743/1.500/18.847 | 1.263/8.937/48.027 | 1.799/11.811/36.376 |
| RUST | 88000 | 0.713/1.438/5.907 | 1.305/17.938/51.850 | 1.619/34.945/59.751 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 76000 | 0.703/1.611/17.749 | 1.271/6.423/26.742 | 1.994/40.933/77.248 |
| RUST | 76000 | 0.712/2.482/16.528 | 1.228/4.680/10.961 | 1.678/11.425/33.859 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 3250 | 0.448/0.970/1.375 | 0.590/1.182/2.926 | 0.615/1.352/18.300 |
| RUST | 3500 | 0.439/0.903/1.479 | 0.548/1.130/11.592 | 0.600/1.427/31.234 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1231938 | 22.63 | 18.37 |
| RUST | 1231930 | 21.70 | 17.61 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1063948 | 23.26 | 21.86 |
| RUST | 1060590 | 22.47 | 21.19 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 45499 | 12.21 | 268.36 |
| RUST | 48998 | 13.77 | 281.03 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 18062 | 5.569/6.436/6.948 | 1.0000 |
| RUST | 18018 | 5.567/6.442/7.106 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 17193 | 5.855/6.802/7.382 | 1.0000 |
| RUST | 17105 | 5.884/6.625/7.353 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 3577 | 28.107/30.627/35.560 | 1.0000 |
| RUST | 3442 | 28.875/32.597/35.616 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 94127 | 0.207/0.323 | yes |
| RUST | 93436 | 0.208/0.318 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 81486 | 24.161/29.647/51.349 | 1.0000 |
| RUST | 2000 | 80546 | 24.576/27.697/55.701 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 60799 | 1.326/750.294/1770.038 | 1.0000 | 7 (RSS 4480→11420 KiB) |
| RUST | 60799 | 1.200/910.107/1396.734 | 1.0000 | 8 (RSS 4784→9020 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
