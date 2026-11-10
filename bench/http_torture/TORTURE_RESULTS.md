# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1019-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- CPU family `amd-avx2-vaes-sha-adx` (bench/cpu_env.py) — flags: `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq`
- NURL: `v0.90.0-107-g94ee1161`  ·  Rust peer: rustc `1.99.1`, hyper 1.11.1, rustls 0.23.43, tokio 1.53.1  ·  oha: `oha 1.8.0`  ·  commit `94ee1161`
- Run: https://github.com/nurl-lang/nurl/actions/runs/42897351425
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.
- **†** the VM's steal passed 2 % of the cell's window (a stall coordinated-omission correction charges to the server being measured). **‡** the generator used ≥ 90 % of its cores (`2-3`): the rate is oha's ceiling, not the server's. On a capacity cell a mark means the run at the knee carried it. **errors**: server-attributable count and its commonest type, then the harness artefacts in brackets — the full list is under *Errors by type*.

### Body 1k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 88000 ‡ | 0.668/1.570/12.420 | 1.016 / 9.94 [6.71–18.68] / 38.44 [31.69–50.46] | 1.457/50.233/73.536 | 16.07 / 15.51 / 15.44 | 0 (+18 harness: deadline) |
| RUST | 88000 ‡ | 0.603/1.381/5.300 | 0.985 / 4.16 [3.16–52.79] / 23.39 [8.99–74.31] | 1.622/250.164/261.774 | 16.61 / 15.84 / 16.08 | 0 (+34 harness: deadline) |

### Body 16k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: RUST.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 80000 ‡ | 0.663/3.204/17.127 | 1.025 / 20.76 [7.53–98.57] / 56.82 [24.70–107.87] | 2.089/375.782/386.832 | 19.49 / 18.87 / 19.49 | 0 (+29 harness: deadline) |
| RUST | 80000 ‡ | 0.648/1.674/8.431 | 1.017 / 4.87 [4.08–111.52] / 21.65 [21.25–123.71] | 1.535/85.567/111.210 | 19.51 / 19.07 / 18.97 | 0 (+22 harness: deadline) |

### Body 1m — sustainable capacity & tail under load

Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 4000 | 0.567/1.154/1.460 | 0.743/1.647/5.898 | 0.839/4.320/47.837 | 237.26 / 281.56 / 286.07 | 0 (+12 harness: deadline) |
| RUST | 4000 | 0.474/1.213/2.217 | 0.628/1.513/12.835 | 0.718/14.964/77.781 | 329.50 / 311.58 / 310.14 | 0 (+12 harness: deadline) |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 18718 ‡ | 5.377/6.118/7.137 | 1.0000 | 0 (+96 harness: deadline) |
| RUST | 18792 ‡ | 5.322/6.217/6.926 | 1.0000 | 0 (+90 harness: deadline) |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 17748 ‡ | 5.700/6.276/7.310 | 1.0000 | 0 (+93 harness: deadline) |
| RUST | 17717 ‡ | 5.685/6.381/7.285 | 1.0000 | 0 (+91 harness: deadline) |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 3456 ‡ | 29.008/32.030/34.620 | 1.0000 | 0 (+95 harness: deadline) |
| RUST | 3579 ‡ | 27.863/32.220/34.388 | 1.0000 | 0 (+95 harness: deadline) |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived | errors |
|---|--:|--:|:--:|--:|
| NURL | 93344 ‡ | 0.209/0.362 | yes | 0 (+17 harness: deadline) |
| RUST | 94658 ‡ | 0.206/0.315 | yes | 0 (+19 harness: deadline) |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|--:|
| NURL | 2000 | 84386 ‡ | 23.456/27.872/61.803 | 1.0000 | 0 (+1604 harness: deadline) |
| RUST | 2000 | 82496 ‡ | 24.047/28.964/41.597 | 1.0000 | 0 (+1713 harness: deadline) |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k), sampled every 10s

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors | RSS KiB start→end (max) | RSS KiB/min | CPU % of a core | open fds start→end (max) | steal > 2 % |
|---|--:|--:|--:|--:|--:|--:|--:|--:|---|
| NURL | 63994 | 1.504/1651.793/1920.218 | 1.0000 | 0 (+2 harness: deadline) | 4976→9304 (max 9880) | +29.0 | 126 | 9→9 (max 409) | none |
| RUST | 63999 | 1.339/851.145/1785.464 | 1.0000 | 0 (+7 harness: deadline) | 4636→9140 (max 9888) | +33.1 | 127 | 9→9 (max 409) | none |

---

### Errors by type

Harness artefacts are errors the measurement makes (`deadline`, `EMFILE`, `EADDRNOTAVAIL`); every other message counts against the server. Server-attributable errors in this run: **0**.

| Cell | Server | Kind | Error | Count |
|---|---|---|---|--:|
| 1k capacity search | NURL | harness | aborted due to deadline | 162 |
| 1k load 50% | NURL | harness | aborted due to deadline | 4 |
| 1k load 80% | NURL | harness | aborted due to deadline | 11 |
| 1k load 95% | NURL | harness | aborted due to deadline | 3 |
| 1k capacity search | RUST | harness | aborted due to deadline | 52 |
| 1k load 50% | RUST | harness | aborted due to deadline | 7 |
| 1k load 80% | RUST | harness | aborted due to deadline | 21 |
| 1k load 95% | RUST | harness | aborted due to deadline | 6 |
| 16k capacity search | RUST | harness | aborted due to deadline | 121 |
| 16k load 50% | RUST | harness | aborted due to deadline | 6 |
| 16k load 80% | RUST | harness | aborted due to deadline | 12 |
| 16k load 95% | RUST | harness | aborted due to deadline | 4 |
| 16k capacity search | NURL | harness | aborted due to deadline | 128 |
| 16k load 50% | NURL | harness | aborted due to deadline | 4 |
| 16k load 80% | NURL | harness | aborted due to deadline | 18 |
| 16k load 95% | NURL | harness | aborted due to deadline | 7 |
| 1m capacity search | NURL | harness | aborted due to deadline | 425 |
| 1m load 50% | NURL | harness | aborted due to deadline | 4 |
| 1m load 80% | NURL | harness | aborted due to deadline | 5 |
| 1m load 95% | NURL | harness | aborted due to deadline | 3 |
| 1m capacity search | RUST | harness | aborted due to deadline | 410 |
| 1m load 50% | RUST | harness | aborted due to deadline | 7 |
| 1m load 80% | RUST | harness | aborted due to deadline | 1 |
| 1m load 95% | RUST | harness | aborted due to deadline | 4 |
| 1k churn | RUST | harness | aborted due to deadline | 90 |
| 1k churn | NURL | harness | aborted due to deadline | 96 |
| 16k churn | NURL | harness | aborted due to deadline | 93 |
| 16k churn | RUST | harness | aborted due to deadline | 91 |
| 1m churn | RUST | harness | aborted due to deadline | 95 |
| 1m churn | NURL | harness | aborted due to deadline | 95 |
| slowloris | NURL | harness | aborted due to deadline | 17 |
| slowloris | RUST | harness | aborted due to deadline | 19 |
| keep-alive scale | RUST | harness | aborted due to deadline | 1713 |
| keep-alive scale | NURL | harness | aborted due to deadline | 1604 |
| soak | NURL | harness | aborted due to deadline | 2 |
| soak | RUST | harness | aborted due to deadline | 7 |

### Environment per cell (max over the cell's runs, % of the window)

| Cell | Server | steal | iowait | generator CPU |
|---|---|--:|--:|--:|
| 1k capacity search | NURL | 0.0 | 0.0 | 96 |
| 1k load 50% | NURL | 0.0 | 0.0 | 48 |
| 1k load 80% | NURL | 0.0 | 0.0 | 71 |
| 1k load 95% | NURL | 0.0 | 0.0 | 82 |
| 1k capacity search | RUST | 0.0 | 0.0 | 97 |
| 1k load 50% | RUST | 0.0 | 0.0 | 47 |
| 1k load 80% | RUST | 0.0 | 0.0 | 70 |
| 1k load 95% | RUST | 0.0 | 0.0 | 82 |
| 16k capacity search | RUST | 0.0 | 0.0 | 98 |
| 16k load 50% | RUST | 0.0 | 0.0 | 47 |
| 16k load 80% | RUST | 0.0 | 0.0 | 73 |
| 16k load 95% | RUST | 0.0 | 0.0 | 85 |
| 16k capacity search | NURL | 0.0 | 0.0 | 98 |
| 16k load 50% | NURL | 0.0 | 0.0 | 48 |
| 16k load 80% | NURL | 0.0 | 0.0 | 74 |
| 16k load 95% | NURL | 0.0 | 0.0 | 88 |
| 1m capacity search | NURL | 0.0 | 0.0 | 90 |
| 1m load 50% | NURL | 0.0 | 0.0 | 31 |
| 1m load 80% | NURL | 0.0 | 0.0 | 48 |
| 1m load 95% | NURL | 0.0 | 0.0 | 55 |
| 1m capacity search | RUST | 0.0 | 0.0 | 90 |
| 1m load 50% | RUST | 0.0 | 0.0 | 34 |
| 1m load 80% | RUST | 0.0 | 0.0 | 49 |
| 1m load 95% | RUST | 0.0 | 0.0 | 57 |
| 1k churn | RUST | 0.0 | 0.0 | 100 |
| 1k churn | NURL | 0.0 | 0.0 | 100 |
| 16k churn | NURL | 0.0 | 0.0 | 100 |
| 16k churn | RUST | 0.0 | 0.0 | 100 |
| 1m churn | RUST | 0.0 | 0.0 | 100 |
| 1m churn | NURL | 0.0 | 0.0 | 100 |
| slowloris | NURL | 0.0 | 0.0 | 97 |
| slowloris | RUST | 0.0 | 0.0 | 98 |
| keep-alive scale | RUST | 0.0 | 0.0 | 99 |
| keep-alive scale | NURL | 0.0 | 0.0 | 99 |
| soak | NURL | 0.0 | 0.0 | 79 |
| soak | RUST | 0.0 | 0.0 | 77 |

### Wall time per dimension

| Dimension | wall |
|---|--:|
| build | 1 min 14 s |
| settle | 2 min 0 s |
| loadlevels | 13 min 19 s |
| churn | 2 min 1 s |
| slowloris | 0 min 19 s |
| keepalive | 0 min 41 s |
| tls_resume | 0 min 3 s |
| soak | 20 min 26 s |
| **all** | **40 min 4 s** |

### Reading these numbers

- **A ‡ on a 1 KB capacity is the generator's ceiling, not the server's.** When both servers report a ‡ capacity, that is `oha` on 2-3 hitting its own generation limit — the honest conclusion is "both faster than this host can drive".
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request column makes it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body).
- **A tail claim needs the spread.** The 80 % cell of 1 KB and 16 KB is several runs; a difference inside their [min–max] ranges is not a difference.
- **Read the soak's drift, not its tail.** A † names a stall the VM's host caused, which coordinated-omission correction back-charges to the server being measured. The RSS slope and the fd counts are the server-specific signal (bounded per-connection buffers, freed at connection close).
