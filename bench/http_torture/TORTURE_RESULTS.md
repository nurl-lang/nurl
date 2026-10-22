# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1017-azure` — AMD EPYC 9V74 80-Core Processor (4 CPUs)
- NURL: `v0.76.0-31-g44aff7b9`  ·  oha: `oha 1.8.0`  ·  commit `44aff7b9`
- Run: https://github.com/nurl-lang/nurl/actions/runs/39729616407
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 120000 | 0.542/1.597/24.380 | 1.047/4.031/33.611 | 1.349/74.310/100.136 |
| RUST | 136000 | 0.741/1.675/5.797 | 1.227/3.963/17.501 | 1.332/63.785/104.265 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 112000 | 0.696/2.247/22.562 | 1.257/21.159/45.437 | 1.399/7.040/68.691 |
| RUST | 120000 | 0.706/2.158/28.479 | 1.172/11.109/35.348 | 1.548/86.321/107.436 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 5250 | 0.419/0.971/1.877 | 0.605/1.641/18.406 | 0.642/4.256/62.525 |
| RUST | 4750 | 0.311/0.714/1.166 | 0.460/0.959/8.589 | 0.520/1.524/53.875 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1679881 | 19.74 | 11.75 |
| RUST | 1903969 | 22.28 | 11.70 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1567971 | 21.93 | 13.99 |
| RUST | 1679887 | 22.95 | 13.66 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 73496 | 13.93 | 189.53 |
| RUST | 66496 | 13.39 | 201.37 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 28034 | 3.586/4.077/4.757 | 1.0000 |
| RUST | 27636 | 3.649/4.149/4.965 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 26452 | 3.844/4.212/5.076 | 1.0000 |
| RUST | 26212 | 3.872/4.250/5.264 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 4950 | 20.159/22.503/35.843 | 1.0000 |
| RUST | 4877 | 20.585/22.057/23.704 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 129914 | 0.155/0.215 | yes |
| RUST | 130547 | 0.155/0.208 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 104082 | 18.935/22.303/56.947 | 1.0000 |
| RUST | 2000 | 104167 | 18.843/26.394/49.495 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 89599 | 1.275/722.724/1472.128 | 1.0000 | 2 (RSS 4848→10180 KiB) |
| RUST | 95999 | 1.227/398.702/962.901 | 1.0000 | 5 (RSS 4820→9216 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
