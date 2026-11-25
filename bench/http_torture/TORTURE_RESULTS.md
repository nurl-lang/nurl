# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1020-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- CPU family `amd-avx2-vaes-sha-adx` (bench/cpu_env.py) — flags: `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq`
- NURL: `v0.94.0-88-gc46fd726f`  ·  Rust peer: rustc `1.100.0`, hyper 1.11.1, rustls 0.23.43, tokio 1.53.1  ·  oha: `oha 1.8.0`  ·  commit `c46fd726f`
- Run: https://github.com/nurl-lang/nurl/actions/runs/45589024916
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.
- **†** the VM's steal passed 2 % of the cell's window (a stall coordinated-omission correction charges to the server being measured). **‡** the generator used ≥ 90 % of its cores (`2-3`): the rate is oha's ceiling, not the server's. On a capacity cell a mark means the run at the knee carried it. **errors**: server-attributable count and its commonest type, then the harness artefacts in brackets — the full list is under *Errors by type*.

### Body 1k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 88000 ‡ | 0.523/1.661/9.552 | 1.005 / 7.22 [4.13–16.61] / 52.38 [22.36–61.53] | 1.433/25.098/66.908 | 15.74 / 15.44 / 15.65 | 0 (+20 harness: deadline) |
| RUST | 88000 ‡ | 0.637/1.794/10.272 | 1.028 / 3.41 [3.28–77.04] / 11.46 [8.26–97.21] | 1.409/5.095/24.275 | 16.44 / 15.95 / 15.94 | 0 (+19 harness: deadline) |

### Body 16k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: RUST.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 76000 | 0.579/1.432/9.861 | 0.959 / 14.00 [4.57–40.74] / 21.06 [12.68–66.49] | 1.365/10.827/59.137 | 19.67 / 18.93 / 18.71 | 0 (+26 harness: deadline) |
| RUST | 84000 ‡ | 0.719/3.941/12.288 | 1.170 / 18.40 [5.45–217.74] / 38.07 [24.96–273.57] | 1.574/38.377/61.964 | 20.80 / 19.50 / 19.35 | 0 (+49 harness: deadline) |

### Body 1m — sustainable capacity & tail under load

Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 3750 | 0.495/1.006/1.460 | 0.665/1.638/4.826 | 0.715/3.901/47.017 | 206.14 / 236.67 / 240.75 | 0 (+13 harness: deadline) |
| RUST | 3750 | 0.420/0.885/1.443 | 0.507/1.107/7.726 | 0.602/2.584/38.179 | 283.21 / 265.51 / 258.71 | 0 (+16 harness: deadline) |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 18548 ‡ | 5.427/6.159/7.048 | 1.0000 | 0 (+88 harness: deadline) |
| RUST | 18491 ‡ | 5.429/6.275/7.060 | 1.0000 | 0 (+93 harness: deadline) |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 17876 ‡ | 5.660/6.231/8.028 | 1.0000 | 0 (+99 harness: deadline) |
| RUST | 17818 ‡ | 5.662/6.310/7.224 | 1.0000 | 0 (+96 harness: deadline) |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 3735 ‡ | 26.851/29.037/32.191 | 1.0000 | 0 (+98 harness: deadline) |
| RUST | 3871 ‡ | 25.858/28.389/31.329 | 1.0000 | 0 (+97 harness: deadline) |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived | errors |
|---|--:|--:|:--:|--:|
| NURL | 93028 ‡ | 0.213/0.309 | yes | 0 (+20 harness: deadline) |
| RUST | 92868 ‡ | 0.209/0.314 | yes | 0 (+17 harness: deadline) |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|--:|
| NURL | 2000 | 84727 ‡ | 22.927/38.263/60.585 | 1.0000 | 0 (+1767 harness: deadline) |
| RUST | 2000 | 87874 ‡ | 22.488/27.134/41.545 | 1.0000 | 0 (+1694 harness: deadline) |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k), sampled every 10s

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors | RSS KiB start→end (max) | RSS KiB/min | CPU % of a core | open fds start→end (max) | steal > 2 % |
|---|--:|--:|--:|--:|--:|--:|--:|--:|---|
| NURL | 60799 | 0.982/876.277/1939.287 | 1.0000 | 0 (+6 harness: deadline) | 5008→8536 (max 9112) | +21.8 | 112 | 9→9 (max 409) | none |
| RUST | 67199 | 1.187/986.421/1610.177 | 1.0000 | 0 (+4 harness: deadline) | 4652→9316 (max 9828) | +34.3 | 123 | 9→9 (max 409) | none |

---

### Errors by type

Harness artefacts are errors the measurement makes (`deadline`, `EMFILE`, `EADDRNOTAVAIL`); every other message counts against the server. Server-attributable errors in this run: **0**.

| Cell | Server | Kind | Error | Count |
|---|---|---|---|--:|
| 1k capacity search | NURL | harness | aborted due to deadline | 43 |
| 1k load 50% | NURL | harness | aborted due to deadline | 2 |
| 1k load 80% | NURL | harness | aborted due to deadline | 14 |
| 1k load 95% | NURL | harness | aborted due to deadline | 4 |
| 1k capacity search | RUST | harness | aborted due to deadline | 58 |
| 1k load 50% | RUST | harness | aborted due to deadline | 5 |
| 1k load 80% | RUST | harness | aborted due to deadline | 12 |
| 1k load 95% | RUST | harness | aborted due to deadline | 2 |
| 16k capacity search | RUST | harness | aborted due to deadline | 83 |
| 16k load 50% | RUST | harness | aborted due to deadline | 9 |
| 16k load 80% | RUST | harness | aborted due to deadline | 18 |
| 16k load 95% | RUST | harness | aborted due to deadline | 22 |
| 16k capacity search | NURL | harness | aborted due to deadline | 78 |
| 16k load 50% | NURL | harness | aborted due to deadline | 4 |
| 16k load 80% | NURL | harness | aborted due to deadline | 17 |
| 16k load 95% | NURL | harness | aborted due to deadline | 5 |
| 1m capacity search | NURL | harness | aborted due to deadline | 56 |
| 1m load 50% | NURL | harness | aborted due to deadline | 1 |
| 1m load 80% | NURL | harness | aborted due to deadline | 6 |
| 1m load 95% | NURL | harness | aborted due to deadline | 6 |
| 1m capacity search | RUST | harness | aborted due to deadline | 75 |
| 1m load 50% | RUST | harness | aborted due to deadline | 6 |
| 1m load 80% | RUST | harness | aborted due to deadline | 3 |
| 1m load 95% | RUST | harness | aborted due to deadline | 7 |
| 1k churn | RUST | harness | aborted due to deadline | 93 |
| 1k churn | NURL | harness | aborted due to deadline | 88 |
| 16k churn | NURL | harness | aborted due to deadline | 99 |
| 16k churn | RUST | harness | aborted due to deadline | 96 |
| 1m churn | RUST | harness | aborted due to deadline | 97 |
| 1m churn | NURL | harness | aborted due to deadline | 98 |
| slowloris | NURL | harness | aborted due to deadline | 20 |
| slowloris | RUST | harness | aborted due to deadline | 17 |
| keep-alive scale | RUST | harness | aborted due to deadline | 1694 |
| keep-alive scale | NURL | harness | aborted due to deadline | 1767 |
| soak | NURL | harness | aborted due to deadline | 6 |
| soak | RUST | harness | aborted due to deadline | 4 |

### Environment per cell (max over the cell's runs, % of the window)

| Cell | Server | steal | iowait | generator CPU |
|---|---|--:|--:|--:|
| 1k capacity search | NURL | 0.0 | 0.0 | 98 |
| 1k load 50% | NURL | 0.0 | 0.0 | 47 |
| 1k load 80% | NURL | 0.0 | 0.0 | 71 |
| 1k load 95% | NURL | 0.0 | 0.0 | 83 |
| 1k capacity search | RUST | 0.0 | 0.0 | 97 |
| 1k load 50% | RUST | 0.0 | 0.0 | 47 |
| 1k load 80% | RUST | 0.0 | 0.0 | 71 |
| 1k load 95% | RUST | 0.0 | 0.0 | 83 |
| 16k capacity search | RUST | 0.0 | 0.0 | 98 |
| 16k load 50% | RUST | 0.0 | 0.0 | 53 |
| 16k load 80% | RUST | 0.0 | 0.0 | 77 |
| 16k load 95% | RUST | 0.0 | 0.0 | 88 |
| 16k capacity search | NURL | 0.0 | 0.0 | 98 |
| 16k load 50% | NURL | 0.0 | 0.0 | 47 |
| 16k load 80% | NURL | 0.0 | 0.0 | 70 |
| 16k load 95% | NURL | 0.0 | 0.0 | 81 |
| 1m capacity search | NURL | 0.0 | 0.0 | 56 |
| 1m load 50% | NURL | 0.0 | 0.0 | 30 |
| 1m load 80% | NURL | 0.0 | 0.0 | 43 |
| 1m load 95% | NURL | 0.0 | 0.0 | 50 |
| 1m capacity search | RUST | 0.0 | 0.0 | 55 |
| 1m load 50% | RUST | 0.0 | 0.0 | 30 |
| 1m load 80% | RUST | 0.0 | 0.0 | 42 |
| 1m load 95% | RUST | 0.0 | 0.0 | 49 |
| 1k churn | RUST | 0.0 | 0.0 | 100 |
| 1k churn | NURL | 0.0 | 0.0 | 100 |
| 16k churn | NURL | 0.0 | 0.0 | 100 |
| 16k churn | RUST | 0.0 | 0.0 | 100 |
| 1m churn | RUST | 0.0 | 0.0 | 100 |
| 1m churn | NURL | 0.0 | 0.0 | 100 |
| slowloris | NURL | 0.0 | 0.0 | 98 |
| slowloris | RUST | 0.0 | 0.0 | 98 |
| keep-alive scale | RUST | 0.0 | 0.0 | 99 |
| keep-alive scale | NURL | 0.0 | 0.0 | 97 |
| soak | NURL | 0.0 | 0.0 | 70 |
| soak | RUST | 0.0 | 0.0 | 75 |

### Wall time per dimension

| Dimension | wall |
|---|--:|
| build | 0 min 34 s |
| settle | 2 min 0 s |
| loadlevels | 12 min 58 s |
| churn | 2 min 1 s |
| slowloris | 0 min 19 s |
| keepalive | 0 min 41 s |
| tls_resume | 0 min 3 s |
| soak | 20 min 27 s |
| **all** | **39 min 4 s** |

### Reading these numbers

- **A ‡ on a 1 KB capacity is the generator's ceiling, not the server's.** When both servers report a ‡ capacity, that is `oha` on 2-3 hitting its own generation limit — the honest conclusion is "both faster than this host can drive".
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request column makes it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body).
- **A tail claim needs the spread.** The 80 % cell of 1 KB and 16 KB is several runs; a difference inside their [min–max] ranges is not a difference.
- **Read the soak's drift, not its tail.** A † names a stall the VM's host caused, which coordinated-omission correction back-charges to the server being measured. The RSS slope and the fd counts are the server-specific signal (bounded per-connection buffers, freed at connection close).
