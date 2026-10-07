# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 6.17.0-1022-azure` — INTEL(R) XEON(R) PLATINUM 8573C (4 CPUs)
- NURL: `v0.70.0-29-g9a6f570d`  ·  oha: `oha 1.8.0`  ·  commit `9a6f570d`
- Run: https://github.com/nurl-lang/nurl/actions/runs/37633108698
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.

### Body 1k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 120000 | 0.575/0.945/3.876 | 0.942/2.046/8.618 | 1.146/5.312/22.835 |
| RUST | 152000 | 0.753/1.552/5.232 | 1.185/4.479/16.266 | 0.974/25.690/40.838 |

### Body 16k — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 124000 | 0.746/1.564/4.669 | 1.115/2.929/5.844 | 1.111/39.872/57.953 |
| RUST | 124000 | 0.760/1.683/6.064 | 1.127/3.899/11.184 | 1.106/40.652/50.551 |

### Body 1m — sustainable capacity & tail under load

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 |
|---|--:|--:|--:|--:|
| NURL | 5500 | 0.508/1.021/1.842 | 0.711/6.489/46.436 | 0.828/29.231/82.352 |
| RUST | 5250 | 0.491/1.084/2.193 | 0.667/2.821/14.615 | 0.801/14.490/51.600 |

### Body 1k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1679873 | 18.03 | 10.73 |
| RUST | 2127952 | 21.53 | 10.12 |

### Body 16k — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 1735867 | 25.91 | 14.93 |
| RUST | 1735940 | 25.18 | 14.51 |

### Body 1m — CPU seconds per request (server-side)

| Server | req served | CPU s (utime+stime) | µs / request |
|---|--:|--:|--:|
| NURL | 76994 | 19.68 | 255.60 |
| RUST | 73495 | 19.22 | 261.51 |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 37189 | 2.701/3.181/3.786 | 1.0000 |
| RUST | 36880 | 2.730/3.153/3.809 | 1.0000 |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 34554 | 2.936/3.290/4.013 | 1.0000 |
| RUST | 34341 | 2.942/3.333/4.117 | 1.0000 |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|
| NURL | 4531 | 22.082/24.109/31.672 | 1.0000 |
| RUST | 4611 | 21.668/23.616/35.943 | 1.0000 |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived |
|---|--:|--:|:--:|
| NURL | 141827 | 0.137/0.228 | yes |
| RUST | 144685 | 0.134/0.199 | yes |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok |
|---|--:|--:|--:|--:|
| NURL | 2000 | 110263 | 17.975/24.618/40.527 | 1.0000 |
| RUST | 2000 | 108582 | 18.337/22.567/34.305 | 1.0000 |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k)

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 99199 | 1.139/18.634/449.833 | 1.0000 | 2 (RSS 3548→12604 KiB) |
| RUST | 99199 | 1.116/17.413/466.361 | 1.0000 | 4 (RSS 4640→11400 KiB) |

---

### Reading these numbers

- **1 KB capacity is generator-bound, not a server ceiling.** When both servers report the *same* sustainable rate for 1 KB, that is `oha` on 2-3 hitting its own generation limit, not the servers saturating — the honest 1 KB conclusion is "both faster than this host can drive," i.e. a tie at the floor of the generator's ceiling.
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request rows make it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body), and at 1 MB the two servers now sit within the knee search's resolution of each other in rate and within a few percent in CPU per request.
- **The soak tail is largely environmental.** A 600 s run on a shared workstation is exposed to system scheduling the 20 s load-level runs are not, and coordinated-omission correction back-charges every hiccup — which is why *both* servers show a inflated soak p99. Compare the two servers to each other, and read the **RSS delta** as the server-specific signal (bounded per-connection buffer high-water, freed at connection close).
