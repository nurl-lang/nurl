# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1017-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- CPU family `amd-avx2-vaes-sha-adx` (bench/cpu_env.py) — flags: `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq`
- NURL: `v0.84.0-13-g38c8f6c8`  ·  Rust peer: rustc `1.99.1`, hyper 1.11.1, rustls 0.23.43, tokio 1.53.1  ·  oha: `oha 1.8.0`  ·  commit `38c8f6c8`
- Run: https://github.com/nurl-lang/nurl/actions/runs/41412348952
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.
- **†** the VM's steal passed 2 % of the cell's window (a stall coordinated-omission correction charges to the server being measured). **‡** the generator used ≥ 90 % of its cores (`2-3`): the rate is oha's ceiling, not the server's. On a capacity cell a mark means the run at the knee carried it. **errors**: server-attributable count and its commonest type, then the harness artefacts in brackets — the full list is under *Errors by type*.

### Body 1k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 88000 ‡ | 0.704/2.454/9.567 | 1.026 / 3.68 [2.72–122.73] / 16.21 [7.57–129.77] | 1.518/12.083/61.779 | 17.31 / 16.02 / 16.27 | 0 (+26 harness: deadline) |
| RUST | 80000 | 0.522/1.110/12.033 | 0.985 / 3.46 [3.02–40.51] / 30.91 [9.20–56.31] | 1.408/39.556/61.322 | 18.03 / 16.98 / 16.84 | 0 (+22 harness: deadline) |

### Body 16k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: RUST.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 72000 | 0.631/1.506/19.427 | 0.994 / 4.78 [3.55–88.85] / 27.65 [8.67–151.80] | 1.392/6.907/28.589 | 21.14 / 20.70 / 20.32 | 0 (+33 harness: deadline) |
| RUST | 76000 ‡ | 0.701/1.705/13.564 | 1.064 / 6.23 [4.28–178.17] / 30.00 [11.50–199.35] | 2.169/386.603/399.838 | 21.12 / 20.21 / 21.23 | 0 (+22 harness: deadline) |

### Body 1m — sustainable capacity & tail under load

Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 3750 | 0.488/1.052/1.636 | 0.664/1.615/4.328 | 0.721/1.932/41.279 | 208.54 / 239.00 / 245.79 | 0 (+22 harness: deadline) |
| RUST | 3750 | 0.414/0.889/1.557 | 0.561/1.122/13.499 | 0.620/2.728/41.210 | 285.08 / 274.50 / 265.46 | 0 (+11 harness: deadline) |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 19147 ‡ | 5.258/5.964/6.594 | 1.0000 | 0 (+87 harness: deadline) |
| RUST | 18962 ‡ | 5.291/6.125/6.807 | 1.0000 | 0 (+90 harness: deadline) |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 18341 ‡ | 5.518/6.067/7.389 | 1.0000 | 0 (+92 harness: deadline) |
| RUST | 18075 ‡ | 5.569/6.236/7.282 | 1.0000 | 0 (+97 harness: deadline) |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 3705 ‡ | 27.073/29.666/33.408 | 1.0000 | 0 (+96 harness: deadline) |
| RUST | 3576 ‡ | 28.029/31.178/34.323 | 1.0000 | 0 (+97 harness: deadline) |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived | errors |
|---|--:|--:|:--:|--:|
| NURL | 94865 ‡ | 0.208/0.307 | yes | 0 (+17 harness: deadline) |
| RUST | 95147 ‡ | 0.205/0.310 | yes | 0 (+16 harness: deadline) |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|--:|
| NURL | 2000 | 83091 ‡ | 23.480/38.871/61.876 | 1.0000 | 0 (+1763 harness: deadline) |
| RUST | 2000 | 84567 ‡ | 23.218/28.313/46.489 | 1.0000 | 0 (+1708 harness: deadline) |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k), sampled every 10s

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors | RSS KiB start→end (max) | RSS KiB/min | CPU % of a core | open fds start→end (max) | steal > 2 % |
|---|--:|--:|--:|--:|--:|--:|--:|--:|---|
| NURL | 57599 | 0.962/711.331/1422.661 | 1.0000 | 0 (+3 harness: deadline) | 4652→8976 (max 9552) | +28.9 | 111 | 9→9 (max 409) | none |
| RUST | 60799 | 1.020/652.979/1480.766 | 1.0000 | 0 (+5 harness: deadline) | 4648→9220 (max 9636) | +35.5 | 117 | 9→9 (max 409) | none |

---

### Errors by type

Harness artefacts are errors the measurement makes (`deadline`, `EMFILE`, `EADDRNOTAVAIL`); every other message counts against the server. Server-attributable errors in this run: **0**.

| Cell | Server | Kind | Error | Count |
|---|---|---|---|--:|
| 1k capacity search | NURL | harness | aborted due to deadline | 45 |
| 1k load 50% | NURL | harness | aborted due to deadline | 3 |
| 1k load 80% | NURL | harness | aborted due to deadline | 14 |
| 1k load 95% | NURL | harness | aborted due to deadline | 9 |
| 1k capacity search | RUST | harness | aborted due to deadline | 140 |
| 1k load 50% | RUST | harness | aborted due to deadline | 8 |
| 1k load 80% | RUST | harness | aborted due to deadline | 12 |
| 1k load 95% | RUST | harness | aborted due to deadline | 2 |
| 16k capacity search | RUST | harness | aborted due to deadline | 197 |
| 16k load 50% | RUST | harness | aborted due to deadline | 4 |
| 16k load 80% | RUST | harness | aborted due to deadline | 12 |
| 16k load 95% | RUST | harness | aborted due to deadline | 6 |
| 16k capacity search | NURL | harness | aborted due to deadline | 185 |
| 16k load 50% | NURL | harness | aborted due to deadline | 6 |
| 16k load 80% | NURL | harness | aborted due to deadline | 23 |
| 16k load 95% | NURL | harness | aborted due to deadline | 4 |
| 1m capacity search | NURL | harness | aborted due to deadline | 67 |
| 1m load 50% | NURL | harness | aborted due to deadline | 6 |
| 1m load 80% | NURL | harness | aborted due to deadline | 8 |
| 1m load 95% | NURL | harness | aborted due to deadline | 8 |
| 1m capacity search | RUST | harness | aborted due to deadline | 58 |
| 1m load 50% | RUST | harness | aborted due to deadline | 3 |
| 1m load 80% | RUST | harness | aborted due to deadline | 3 |
| 1m load 95% | RUST | harness | aborted due to deadline | 5 |
| 1k churn | RUST | harness | aborted due to deadline | 90 |
| 1k churn | NURL | harness | aborted due to deadline | 87 |
| 16k churn | NURL | harness | aborted due to deadline | 92 |
| 16k churn | RUST | harness | aborted due to deadline | 97 |
| 1m churn | RUST | harness | aborted due to deadline | 97 |
| 1m churn | NURL | harness | aborted due to deadline | 96 |
| slowloris | NURL | harness | aborted due to deadline | 17 |
| slowloris | RUST | harness | aborted due to deadline | 16 |
| keep-alive scale | RUST | harness | aborted due to deadline | 1708 |
| keep-alive scale | NURL | harness | aborted due to deadline | 1763 |
| soak | NURL | harness | aborted due to deadline | 3 |
| soak | RUST | harness | aborted due to deadline | 5 |

### Environment per cell (max over the cell's runs, % of the window)

| Cell | Server | steal | iowait | generator CPU |
|---|---|--:|--:|--:|
| 1k capacity search | NURL | 0.0 | 0.0 | 98 |
| 1k load 50% | NURL | 0.0 | 0.0 | 49 |
| 1k load 80% | NURL | 0.0 | 0.0 | 73 |
| 1k load 95% | NURL | 0.0 | 0.0 | 86 |
| 1k capacity search | RUST | 0.0 | 0.0 | 98 |
| 1k load 50% | RUST | 0.0 | 0.0 | 46 |
| 1k load 80% | RUST | 0.0 | 0.0 | 69 |
| 1k load 95% | RUST | 0.0 | 0.0 | 80 |
| 16k capacity search | RUST | 0.0 | 0.0 | 98 |
| 16k load 50% | RUST | 0.0 | 0.0 | 50 |
| 16k load 80% | RUST | 0.0 | 0.0 | 75 |
| 16k load 95% | RUST | 0.0 | 0.0 | 89 |
| 16k capacity search | NURL | 0.0 | 0.0 | 98 |
| 16k load 50% | NURL | 0.0 | 0.0 | 47 |
| 16k load 80% | NURL | 0.0 | 0.0 | 71 |
| 16k load 95% | NURL | 0.0 | 0.0 | 81 |
| 1m capacity search | NURL | 0.0 | 0.0 | 56 |
| 1m load 50% | NURL | 0.0 | 0.0 | 29 |
| 1m load 80% | NURL | 0.0 | 0.0 | 43 |
| 1m load 95% | NURL | 0.0 | 0.0 | 50 |
| 1m capacity search | RUST | 0.0 | 0.1 | 55 |
| 1m load 50% | RUST | 0.0 | 0.0 | 30 |
| 1m load 80% | RUST | 0.0 | 0.0 | 43 |
| 1m load 95% | RUST | 0.0 | 0.0 | 49 |
| 1k churn | RUST | 0.0 | 0.0 | 100 |
| 1k churn | NURL | 0.0 | 0.0 | 100 |
| 16k churn | NURL | 0.0 | 0.0 | 100 |
| 16k churn | RUST | 0.0 | 0.0 | 99 |
| 1m churn | RUST | 0.0 | 0.0 | 100 |
| 1m churn | NURL | 0.0 | 0.0 | 100 |
| slowloris | NURL | 0.0 | 0.0 | 98 |
| slowloris | RUST | 0.0 | 0.0 | 98 |
| keep-alive scale | RUST | 0.0 | 0.0 | 99 |
| keep-alive scale | NURL | 0.0 | 0.0 | 97 |
| soak | NURL | 0.0 | 0.0 | 69 |
| soak | RUST | 0.0 | 0.0 | 72 |

### Wall time per dimension

| Dimension | wall |
|---|--:|
| build | 0 min 39 s |
| settle | 2 min 0 s |
| loadlevels | 12 min 58 s |
| churn | 2 min 1 s |
| slowloris | 0 min 19 s |
| keepalive | 0 min 41 s |
| tls_resume | 0 min 3 s |
| soak | 20 min 25 s |
| **all** | **39 min 8 s** |

### Reading these numbers

- **A ‡ on a 1 KB capacity is the generator's ceiling, not the server's.** When both servers report a ‡ capacity, that is `oha` on 2-3 hitting its own generation limit — the honest conclusion is "both faster than this host can drive".
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request column makes it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body).
- **A tail claim needs the spread.** The 80 % cell of 1 KB and 16 KB is several runs; a difference inside their [min–max] ranges is not a difference.
- **Read the soak's drift, not its tail.** A † names a stall the VM's host caused, which coordinated-omission correction back-charges to the server being measured. The RSS slope and the fd counts are the server-specific signal (bounded per-connection buffers, freed at connection close).
