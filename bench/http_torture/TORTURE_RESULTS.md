# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1019-azure` — AMD EPYC 9V74 80-Core Processor (4 CPUs)
- CPU family `amd-avx512ifma-vaes-sha-adx` (bench/cpu_env.py) — flags: `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq gfni avx512f avx512vl avx512bw avx512ifma avx512vbmi`
- NURL: `v0.89.0-4-ga3be3e7c`  ·  Rust peer: rustc `1.99.1`, hyper 1.11.1, rustls 0.23.43, tokio 1.53.1  ·  oha: `oha 1.8.0`  ·  commit `a3be3e7c`
- Run: https://github.com/nurl-lang/nurl/actions/runs/42260759682
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.
- **†** the VM's steal passed 2 % of the cell's window (a stall coordinated-omission correction charges to the server being measured). **‡** the generator used ≥ 90 % of its cores (`2-3`): the rate is oha's ceiling, not the server's. On a capacity cell a mark means the run at the knee carried it. **errors**: server-attributable count and its commonest type, then the harness artefacts in brackets — the full list is under *Errors by type*.

### Body 1k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 136000 ‡ | 0.732/1.900/5.629 | 1.217 / 44.19 [15.97–56.29] / 86.06 [53.23–87.96] | 1.341/81.516/100.447 | 11.63 / 11.50 / 11.65 | 0 (+21 harness: deadline) |
| RUST | 136000 ‡ | 0.721/1.433/8.260 | 1.217 / 30.09 [16.87–47.80] / 72.76 [68.06–78.94] | 1.322/67.060/93.138 ‡ | 11.45 / 11.33 / 11.61 | 0 (+22 harness: deadline) |

### Body 16k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: RUST.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 124000 ‡ | 0.715/2.600/27.717 | 1.247 / 15.40 [8.12–26.48] / 42.81 [35.43–44.65] | 1.713/78.999/98.808 ‡ | 14.01 / 13.90 / 14.09 | 0 (+23 harness: deadline) |
| RUST | 124000 ‡ | 0.716/2.498/8.134 | 1.222 / 6.28 [4.81–71.10] / 32.95 [18.01–110.08] | 1.561/78.327/99.566 ‡ | 13.80 / 13.47 / 13.66 | 0 (+23 harness: deadline) |

### Body 1m — sustainable capacity & tail under load

Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 5500 | 0.517/1.156/2.564 | 0.701/5.992/18.341 | 0.781/3.921/67.562 | 217.83 / 234.55 / 232.44 | 0 (+9 harness: deadline) |
| RUST | 5250 | 0.367/0.860/1.389 | 0.569/1.395/11.729 | 0.608/1.877/48.230 | 237.91 / 243.10 / 238.32 | 0 (+14 harness: deadline) |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 27865 ‡ | 3.626/4.083/5.289 | 1.0000 | 0 (+93 harness: deadline) |
| RUST | 27563 ‡ | 3.652/4.190/5.333 | 1.0000 | 0 (+90 harness: deadline) |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 27116 ‡ | 3.758/4.077/5.625 | 1.0000 | 0 (+94 harness: deadline) |
| RUST | 26845 ‡ | 3.773/4.264/5.843 | 1.0000 | 0 (+84 harness: deadline) |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 5149 ‡ | 19.364/22.017/39.698 | 1.0000 | 0 (+97 harness: deadline) |
| RUST | 5156 ‡ | 19.258/22.624/38.669 | 1.0000 | 0 (+95 harness: deadline) |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived | errors |
|---|--:|--:|:--:|--:|
| NURL | 133040 ‡ | 0.151/0.207 | yes | 0 (+15 harness: deadline) |
| RUST | 130071 ‡ | 0.151/0.320 | yes | 0 (+16 harness: deadline) |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|--:|
| NURL | 2000 | 110459 ‡ | 17.630/25.758/52.306 | 1.0000 | 0 (+1670 harness: deadline) |
| RUST | 2000 | 110929 ‡ | 17.628/22.047/43.882 | 1.0000 | 0 (+1732 harness: deadline) |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k), sampled every 10s

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors | RSS KiB start→end (max) | RSS KiB/min | CPU % of a core | open fds start→end (max) | steal > 2 % |
|---|--:|--:|--:|--:|--:|--:|--:|--:|---|
| NURL | 99199 | 1.275/545.432/1164.530 | 1.0000 | 0 (+3 harness: deadline) | 4660→8984 (max 9564) | +28.8 | 133 | 9→9 (max 409) | none |
| RUST | 99199 | 1.246/486.076/1133.555 | 1.0000 | 0 (+6 harness: deadline) | 4664→9264 (max 9792) | +30.9 | 132 | 9→9 (max 409) | none |

---

### Errors by type

Harness artefacts are errors the measurement makes (`deadline`, `EMFILE`, `EADDRNOTAVAIL`); every other message counts against the server. Server-attributable errors in this run: **0**.

| Cell | Server | Kind | Error | Count |
|---|---|---|---|--:|
| 1k capacity search | NURL | harness | aborted due to deadline | 83 |
| 1k load 50% | NURL | harness | aborted due to deadline | 6 |
| 1k load 80% | NURL | harness | aborted due to deadline | 12 |
| 1k load 95% | NURL | harness | aborted due to deadline | 3 |
| 1k capacity search | RUST | harness | aborted due to deadline | 103 |
| 1k load 50% | RUST | harness | aborted due to deadline | 3 |
| 1k load 80% | RUST | harness | aborted due to deadline | 16 |
| 1k load 95% | RUST | harness | aborted due to deadline | 3 |
| 16k capacity search | RUST | harness | aborted due to deadline | 40 |
| 16k load 50% | RUST | harness | aborted due to deadline | 7 |
| 16k load 80% | RUST | harness | aborted due to deadline | 15 |
| 16k load 95% | RUST | harness | aborted due to deadline | 1 |
| 16k capacity search | NURL | harness | aborted due to deadline | 73 |
| 16k load 50% | NURL | harness | aborted due to deadline | 2 |
| 16k load 80% | NURL | harness | aborted due to deadline | 16 |
| 16k load 95% | NURL | harness | aborted due to deadline | 5 |
| 1m capacity search | NURL | harness | aborted due to deadline | 262 |
| 1m load 50% | NURL | harness | aborted due to deadline | 3 |
| 1m load 80% | NURL | harness | aborted due to deadline | 3 |
| 1m load 95% | NURL | harness | aborted due to deadline | 3 |
| 1m capacity search | RUST | harness | aborted due to deadline | 92 |
| 1m load 50% | RUST | harness | aborted due to deadline | 6 |
| 1m load 80% | RUST | harness | aborted due to deadline | 2 |
| 1m load 95% | RUST | harness | aborted due to deadline | 6 |
| 1k churn | RUST | harness | aborted due to deadline | 90 |
| 1k churn | NURL | harness | aborted due to deadline | 93 |
| 16k churn | NURL | harness | aborted due to deadline | 94 |
| 16k churn | RUST | harness | aborted due to deadline | 84 |
| 1m churn | RUST | harness | aborted due to deadline | 95 |
| 1m churn | NURL | harness | aborted due to deadline | 97 |
| slowloris | NURL | harness | aborted due to deadline | 15 |
| slowloris | RUST | harness | aborted due to deadline | 16 |
| keep-alive scale | RUST | harness | aborted due to deadline | 1732 |
| keep-alive scale | NURL | harness | aborted due to deadline | 1670 |
| soak | NURL | harness | aborted due to deadline | 3 |
| soak | RUST | harness | aborted due to deadline | 6 |

### Environment per cell (max over the cell's runs, % of the window)

| Cell | Server | steal | iowait | generator CPU |
|---|---|--:|--:|--:|
| 1k capacity search | NURL | 0.0 | 0.0 | 97 |
| 1k load 50% | NURL | 0.0 | 0.0 | 51 |
| 1k load 80% | NURL | 0.0 | 0.0 | 78 |
| 1k load 95% | NURL | 0.0 | 0.0 | 90 |
| 1k capacity search | RUST | 0.0 | 0.0 | 97 |
| 1k load 50% | RUST | 0.0 | 0.0 | 50 |
| 1k load 80% | RUST | 0.0 | 0.0 | 78 |
| 1k load 95% | RUST | 0.0 | 0.0 | 91 |
| 16k capacity search | RUST | 0.0 | 0.0 | 97 |
| 16k load 50% | RUST | 0.0 | 0.0 | 52 |
| 16k load 80% | RUST | 0.0 | 0.0 | 79 |
| 16k load 95% | RUST | 0.0 | 0.0 | 92 |
| 16k capacity search | NURL | 0.0 | 0.3 | 97 |
| 16k load 50% | NURL | 0.0 | 0.0 | 52 |
| 16k load 80% | NURL | 0.0 | 0.0 | 80 |
| 16k load 95% | NURL | 0.0 | 0.0 | 94 |
| 1m capacity search | NURL | 0.0 | 0.3 | 85 |
| 1m load 50% | NURL | 0.0 | 0.0 | 32 |
| 1m load 80% | NURL | 0.0 | 0.1 | 48 |
| 1m load 95% | NURL | 0.0 | 0.0 | 55 |
| 1m capacity search | RUST | 0.0 | 0.0 | 84 |
| 1m load 50% | RUST | 0.0 | 0.0 | 31 |
| 1m load 80% | RUST | 0.0 | 0.0 | 46 |
| 1m load 95% | RUST | 0.0 | 0.0 | 53 |
| 1k churn | RUST | 0.0 | 0.0 | 99 |
| 1k churn | NURL | 0.0 | 0.0 | 99 |
| 16k churn | NURL | 0.0 | 0.0 | 100 |
| 16k churn | RUST | 0.0 | 0.0 | 100 |
| 1m churn | RUST | 0.0 | 0.0 | 100 |
| 1m churn | NURL | 0.0 | 0.0 | 100 |
| slowloris | NURL | 0.0 | 0.0 | 98 |
| slowloris | RUST | 0.0 | 0.0 | 97 |
| keep-alive scale | RUST | 0.0 | 0.0 | 99 |
| keep-alive scale | NURL | 0.0 | 0.0 | 99 |
| soak | NURL | 0.0 | 0.0 | 80 |
| soak | RUST | 0.0 | 0.0 | 80 |

### Wall time per dimension

| Dimension | wall |
|---|--:|
| build | 0 min 26 s |
| settle | 2 min 0 s |
| loadlevels | 13 min 42 s |
| churn | 2 min 1 s |
| slowloris | 0 min 19 s |
| keepalive | 0 min 41 s |
| tls_resume | 0 min 3 s |
| soak | 20 min 29 s |
| **all** | **39 min 42 s** |

### Reading these numbers

- **A ‡ on a 1 KB capacity is the generator's ceiling, not the server's.** When both servers report a ‡ capacity, that is `oha` on 2-3 hitting its own generation limit — the honest conclusion is "both faster than this host can drive".
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request column makes it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body).
- **A tail claim needs the spread.** The 80 % cell of 1 KB and 16 KB is several runs; a difference inside their [min–max] ranges is not a difference.
- **Read the soak's drift, not its tail.** A † names a stall the VM's host caused, which coordinated-omission correction back-charges to the server being measured. The RSS slope and the fd counts are the server-specific signal (bounded per-connection buffers, freed at connection close).
