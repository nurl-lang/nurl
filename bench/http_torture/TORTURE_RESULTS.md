# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1017-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- CPU family `amd-avx2-vaes-sha-adx` (bench/cpu_env.py) — flags: `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq`
- NURL: `v0.82.0-76-g87108acb`  ·  Rust peer: rustc `1.99.1`, hyper 1.11.1, rustls 0.23.43, tokio 1.53.1  ·  oha: `oha 1.8.0`  ·  commit `87108acb`
- Run: https://github.com/nurl-lang/nurl/actions/runs/41245691117
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.
- **†** the VM's steal passed 2 % of the cell's window (a stall coordinated-omission correction charges to the server being measured). **‡** the generator used ≥ 90 % of its cores (`2-3`): the rate is oha's ceiling, not the server's. On a capacity cell a mark means the run at the knee carried it. **errors**: server-attributable count and its commonest type, then the harness artefacts in brackets — the full list is under *Errors by type*.

### Body 1k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 96000 ‡ | 0.721/1.317/5.646 | 1.196 / 19.16 [3.03–108.50] / 51.72 [7.17–121.67] | 1.563/36.684/58.159 | 15.62 / 15.47 / 15.62 | 0 (+14 harness: deadline) |
| RUST | 96000 ‡ | 0.722/1.670/19.432 | 1.201 / 5.40 [3.16–135.02] / 33.48 [9.25–146.06] | 1.806/380.164/401.555 | 16.07 / 15.66 / 16.06 | 0 (+26 harness: deadline) |

### Body 16k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: RUST.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 84000 ‡ | 0.664/1.524/13.374 | 1.129 / 22.46 [5.58–138.81] / 52.26 [20.49–159.15] | 2.476/473.997/499.055 ‡ | 19.18 / 19.01 / 19.73 | 0 (+39 harness: deadline) |
| RUST | 84000 ‡ | 0.682/3.643/19.556 | 1.173 / 38.07 [5.00–170.19] / 69.13 [32.96–182.11] | 1.595/24.767/37.242 | 19.76 / 19.37 / 19.35 | 0 (+27 harness: deadline) |

### Body 1m — sustainable capacity & tail under load

Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 4000 | 0.482/1.142/1.665 | 0.684/1.451/8.977 | 0.718/1.784/23.860 | 211.76 / 244.86 / 248.30 | 0 (+17 harness: deadline) |
| RUST | 3750 | 0.422/1.004/1.927 | 0.566/1.214/10.119 | 0.623/2.399/39.837 | 288.27 / 280.67 / 267.98 | 0 (+21 harness: deadline) |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 19341 ‡ | 5.219/5.901/6.638 | 1.0000 | 0 (+96 harness: deadline) |
| RUST | 19045 ‡ | 5.270/6.080/6.712 | 1.0000 | 0 (+84 harness: deadline) |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 18444 ‡ | 5.499/5.988/6.717 | 1.0000 | 0 (+92 harness: deadline) |
| RUST | 18239 ‡ | 5.525/6.194/7.138 | 1.0000 | 0 (+95 harness: deadline) |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 4135 ‡ | 24.211/26.504/29.112 | 1.0000 | 0 (+97 harness: deadline) |
| RUST | 4014 ‡ | 24.993/27.215/29.861 | 1.0000 | 0 (+96 harness: deadline) |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived | errors |
|---|--:|--:|:--:|--:|
| NURL | 96660 ‡ | 0.203/0.304 | yes | 0 (+16 harness: deadline) |
| RUST | 88265 ‡ | 0.207/0.460 | yes | 0 (+16 harness: deadline) |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|--:|
| NURL | 2000 | 93486 ‡ | 21.177/24.573/56.851 | 1.0000 | 0 (+1663 harness: deadline) |
| RUST | 2000 | 91146 ‡ | 21.715/26.065/41.354 | 1.0000 | 0 (+1706 harness: deadline) |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k), sampled every 10s

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors | RSS KiB start→end (max) | RSS KiB/min | CPU % of a core | open fds start→end (max) | steal > 2 % |
|---|--:|--:|--:|--:|--:|--:|--:|--:|---|
| NURL | 67199 | 1.228/851.089/1712.510 | 1.0000 | 0 (+4 harness: deadline) | 4808→10156 (max 10156) | +55.1 | 125 | 9→9 (max 409) | none |
| RUST | 67199 | 1.323/1461.147/2316.899 | 1.0000 | 0 (+4 harness: deadline) | 4584→8920 (max 9792) | +28.7 | 129 | 9→9 (max 409) | none |

---

### Errors by type

Harness artefacts are errors the measurement makes (`deadline`, `EMFILE`, `EADDRNOTAVAIL`); every other message counts against the server. Server-attributable errors in this run: **0**.

| Cell | Server | Kind | Error | Count |
|---|---|---|---|--:|
| 1k capacity search | NURL | harness | aborted due to deadline | 39 |
| 1k load 50% | NURL | harness | aborted due to deadline | 4 |
| 1k load 80% | NURL | harness | aborted due to deadline | 6 |
| 1k load 95% | NURL | harness | aborted due to deadline | 4 |
| 1k capacity search | RUST | harness | aborted due to deadline | 44 |
| 1k load 50% | RUST | harness | aborted due to deadline | 5 |
| 1k load 80% | RUST | harness | aborted due to deadline | 19 |
| 1k load 95% | RUST | harness | aborted due to deadline | 2 |
| 16k capacity search | RUST | harness | aborted due to deadline | 107 |
| 16k load 50% | RUST | harness | aborted due to deadline | 1 |
| 16k load 80% | RUST | harness | aborted due to deadline | 21 |
| 16k load 95% | RUST | harness | aborted due to deadline | 5 |
| 16k capacity search | NURL | harness | aborted due to deadline | 221 |
| 16k load 50% | NURL | harness | aborted due to deadline | 7 |
| 16k load 80% | NURL | harness | aborted due to deadline | 15 |
| 16k load 95% | NURL | harness | aborted due to deadline | 17 |
| 1m capacity search | NURL | harness | aborted due to deadline | 418 |
| 1m load 50% | NURL | harness | aborted due to deadline | 6 |
| 1m load 80% | NURL | harness | aborted due to deadline | 7 |
| 1m load 95% | NURL | harness | aborted due to deadline | 4 |
| 1m capacity search | RUST | harness | aborted due to deadline | 80 |
| 1m load 50% | RUST | harness | aborted due to deadline | 3 |
| 1m load 80% | RUST | harness | aborted due to deadline | 9 |
| 1m load 95% | RUST | harness | aborted due to deadline | 9 |
| 1k churn | RUST | harness | aborted due to deadline | 84 |
| 1k churn | NURL | harness | aborted due to deadline | 96 |
| 16k churn | NURL | harness | aborted due to deadline | 92 |
| 16k churn | RUST | harness | aborted due to deadline | 95 |
| 1m churn | RUST | harness | aborted due to deadline | 96 |
| 1m churn | NURL | harness | aborted due to deadline | 97 |
| slowloris | NURL | harness | aborted due to deadline | 16 |
| slowloris | RUST | harness | aborted due to deadline | 16 |
| keep-alive scale | RUST | harness | aborted due to deadline | 1706 |
| keep-alive scale | NURL | harness | aborted due to deadline | 1663 |
| soak | NURL | harness | aborted due to deadline | 4 |
| soak | RUST | harness | aborted due to deadline | 4 |

### Environment per cell (max over the cell's runs, % of the window)

| Cell | Server | steal | iowait | generator CPU |
|---|---|--:|--:|--:|
| 1k capacity search | NURL | 0.0 | 0.0 | 98 |
| 1k load 50% | NURL | 0.0 | 0.0 | 49 |
| 1k load 80% | NURL | 0.0 | 0.0 | 74 |
| 1k load 95% | NURL | 0.0 | 0.0 | 88 |
| 1k capacity search | RUST | 0.0 | 0.0 | 98 |
| 1k load 50% | RUST | 0.0 | 0.0 | 49 |
| 1k load 80% | RUST | 0.0 | 0.0 | 76 |
| 1k load 95% | RUST | 0.0 | 0.0 | 87 |
| 16k capacity search | RUST | 0.0 | 0.0 | 98 |
| 16k load 50% | RUST | 0.0 | 0.0 | 49 |
| 16k load 80% | RUST | 0.0 | 0.0 | 77 |
| 16k load 95% | RUST | 0.0 | 0.0 | 89 |
| 16k capacity search | NURL | 0.0 | 0.0 | 98 |
| 16k load 50% | NURL | 0.0 | 0.0 | 49 |
| 16k load 80% | NURL | 0.0 | 0.0 | 76 |
| 16k load 95% | NURL | 0.0 | 0.0 | 90 |
| 1m capacity search | NURL | 0.0 | 0.0 | 92 |
| 1m load 50% | NURL | 0.0 | 0.0 | 31 |
| 1m load 80% | NURL | 0.0 | 0.0 | 46 |
| 1m load 95% | NURL | 0.0 | 0.0 | 52 |
| 1m capacity search | RUST | 0.0 | 0.0 | 56 |
| 1m load 50% | RUST | 0.0 | 0.0 | 30 |
| 1m load 80% | RUST | 0.0 | 0.0 | 43 |
| 1m load 95% | RUST | 0.0 | 0.0 | 50 |
| 1k churn | RUST | 0.0 | 0.0 | 100 |
| 1k churn | NURL | 0.0 | 0.0 | 100 |
| 16k churn | NURL | 0.0 | 0.0 | 100 |
| 16k churn | RUST | 0.0 | 0.0 | 100 |
| 1m churn | RUST | 0.0 | 0.0 | 100 |
| 1m churn | NURL | 0.0 | 0.0 | 100 |
| slowloris | NURL | 0.0 | 0.0 | 98 |
| slowloris | RUST | 0.0 | 0.0 | 94 |
| keep-alive scale | RUST | 0.0 | 0.0 | 99 |
| keep-alive scale | NURL | 0.0 | 0.0 | 99 |
| soak | NURL | 0.0 | 0.0 | 76 |
| soak | RUST | 0.0 | 0.0 | 78 |

### Wall time per dimension

| Dimension | wall |
|---|--:|
| build | 1 min 16 s |
| settle | 2 min 0 s |
| loadlevels | 13 min 10 s |
| churn | 2 min 1 s |
| slowloris | 0 min 19 s |
| keepalive | 0 min 41 s |
| tls_resume | 0 min 3 s |
| soak | 20 min 28 s |
| **all** | **39 min 59 s** |

### Reading these numbers

- **A ‡ on a 1 KB capacity is the generator's ceiling, not the server's.** When both servers report a ‡ capacity, that is `oha` on 2-3 hitting its own generation limit — the honest conclusion is "both faster than this host can drive".
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request column makes it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body).
- **A tail claim needs the spread.** The 80 % cell of 1 KB and 16 KB is several runs; a difference inside their [min–max] ranges is not a difference.
- **Read the soak's drift, not its tail.** A † names a stall the VM's host caused, which coordinated-omission correction back-charges to the server being measured. The RSS slope and the fd counts are the server-specific signal (bounded per-connection buffers, freed at connection close).
