# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1019-azure` — AMD EPYC 7763 64-Core Processor (4 CPUs)
- CPU family `amd-avx2-vaes-sha-adx` (bench/cpu_env.py) — flags: `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq`
- NURL: `v0.91.1-112-gab45d9db`  ·  Rust peer: rustc `1.100.0`, hyper 1.11.1, rustls 0.23.43, tokio 1.53.1  ·  oha: `oha 1.8.0`  ·  commit `ab45d9db`
- Run: https://github.com/nurl-lang/nurl/actions/runs/43501326708
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.
- **†** the VM's steal passed 2 % of the cell's window (a stall coordinated-omission correction charges to the server being measured). **‡** the generator used ≥ 90 % of its cores (`2-3`): the rate is oha's ceiling, not the server's. On a capacity cell a mark means the run at the knee carried it. **errors**: server-attributable count and its commonest type, then the harness artefacts in brackets — the full list is under *Errors by type*.

### Body 1k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 96000 ‡ | 0.716/1.417/6.484 | 1.230 / 3.81 [3.41–54.08] / 13.96 [8.23–89.69] | 2.233/223.414/231.566 ‡ | 15.35 / 15.21 / 15.64 | 0 (+21 harness: deadline) |
| RUST | 96000 ‡ | 0.695/2.474/7.138 | 1.205 / 10.19 [9.43–11.86] / 42.54 [29.05–43.32] | 1.552/8.560/40.143 | 15.77 / 15.64 / 15.97 | 0 (+24 harness: deadline) |

### Body 16k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: RUST.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 84000 ‡ | 0.683/3.525/11.028 | 1.101 / 5.90 [3.80–70.24] / 29.11 [9.14–73.69] | 1.573/20.658/45.105 | 18.37 / 18.23 / 18.33 | 0 (+22 harness: deadline) |
| RUST | 76000 | 0.546/4.183/12.843 | 0.941 / 11.31 [3.48–28.69] / 30.10 [9.76–38.16] | 1.361/59.448/97.711 | 19.87 / 18.80 / 18.71 | 0 (+25 harness: deadline) |

### Body 1m — sustainable capacity & tail under load

Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 4250 | 0.562/1.198/1.578 | 0.738/1.775/20.088 | 0.828/14.696/88.946 | 244.73 / 275.75 / 278.92 | 0 (+21 harness: deadline) |
| RUST | 4000 | 0.456/0.898/1.463 | 0.611/1.315/7.222 | 0.698/5.801/50.368 | 318.26 / 302.20 / 301.34 | 0 (+10 harness: deadline) |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 18837 ‡ | 5.343/6.068/6.878 | 1.0000 | 0 (+85 harness: deadline) |
| RUST | 18886 ‡ | 5.315/6.142/6.765 | 1.0000 | 0 (+93 harness: deadline) |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 18099 ‡ | 5.591/6.144/7.441 | 1.0000 | 0 (+88 harness: deadline) |
| RUST | 18000 ‡ | 5.599/6.246/6.943 | 1.0000 | 0 (+96 harness: deadline) |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 3947 ‡ | 25.415/27.569/32.055 | 1.0000 | 0 (+92 harness: deadline) |
| RUST | 4053 ‡ | 24.762/26.902/29.587 | 1.0000 | 0 (+97 harness: deadline) |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived | errors |
|---|--:|--:|:--:|--:|
| NURL | 94789 ‡ | 0.208/0.312 | yes | 0 (+17 harness: deadline) |
| RUST | 94274 ‡ | 0.207/0.313 | yes | 0 (+15 harness: deadline) |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|--:|
| NURL | 2000 | 91233 ‡ | 21.050/35.581/62.452 | 1.0000 | 0 (+1736 harness: deadline) |
| RUST | 2000 | 90566 ‡ | 21.692/27.101/43.224 | 1.0000 | 0 (+1715 harness: deadline) |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k), sampled every 10s

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors | RSS KiB start→end (max) | RSS KiB/min | CPU % of a core | open fds start→end (max) | steal > 2 % |
|---|--:|--:|--:|--:|--:|--:|--:|--:|---|
| NURL | 67199 | 1.186/831.947/1673.989 | 1.0000 | 0 (+8 harness: deadline) | 5036→8568 (max 9144) | +21.8 | 119 | 9→9 (max 409) | none |
| RUST | 60799 | 0.943/376.353/1135.755 | 1.0000 | 0 (+11 harness: deadline) | 4736→9452 (max 10212) | +34.1 | 111 | 9→9 (max 409) | none |

---

### Errors by type

Harness artefacts are errors the measurement makes (`deadline`, `EMFILE`, `EADDRNOTAVAIL`); every other message counts against the server. Server-attributable errors in this run: **0**.

| Cell | Server | Kind | Error | Count |
|---|---|---|---|--:|
| 1k capacity search | NURL | harness | aborted due to deadline | 47 |
| 1k load 50% | NURL | harness | aborted due to deadline | 5 |
| 1k load 80% | NURL | harness | aborted due to deadline | 14 |
| 1k load 95% | NURL | harness | aborted due to deadline | 2 |
| 1k capacity search | RUST | harness | aborted due to deadline | 69 |
| 1k load 50% | RUST | harness | aborted due to deadline | 6 |
| 1k load 80% | RUST | harness | aborted due to deadline | 11 |
| 1k load 95% | RUST | harness | aborted due to deadline | 7 |
| 16k capacity search | RUST | harness | aborted due to deadline | 98 |
| 16k load 50% | RUST | harness | aborted due to deadline | 3 |
| 16k load 80% | RUST | harness | aborted due to deadline | 18 |
| 16k load 95% | RUST | harness | aborted due to deadline | 4 |
| 16k capacity search | NURL | harness | aborted due to deadline | 120 |
| 16k load 50% | NURL | harness | aborted due to deadline | 2 |
| 16k load 80% | NURL | harness | aborted due to deadline | 17 |
| 16k load 95% | NURL | harness | aborted due to deadline | 3 |
| 1m capacity search | NURL | harness | aborted due to deadline | 685 |
| 1m load 50% | NURL | harness | aborted due to deadline | 5 |
| 1m load 80% | NURL | harness | aborted due to deadline | 9 |
| 1m load 95% | NURL | harness | aborted due to deadline | 7 |
| 1m capacity search | RUST | harness | aborted due to deadline | 458 |
| 1m load 50% | RUST | harness | aborted due to deadline | 6 |
| 1m load 80% | RUST | harness | aborted due to deadline | 2 |
| 1m load 95% | RUST | harness | aborted due to deadline | 2 |
| 1k churn | RUST | harness | aborted due to deadline | 93 |
| 1k churn | NURL | harness | aborted due to deadline | 85 |
| 16k churn | NURL | harness | aborted due to deadline | 88 |
| 16k churn | RUST | harness | aborted due to deadline | 96 |
| 1m churn | RUST | harness | aborted due to deadline | 97 |
| 1m churn | NURL | harness | aborted due to deadline | 92 |
| slowloris | NURL | harness | aborted due to deadline | 17 |
| slowloris | RUST | harness | aborted due to deadline | 15 |
| keep-alive scale | RUST | harness | aborted due to deadline | 1715 |
| keep-alive scale | NURL | harness | aborted due to deadline | 1736 |
| soak | NURL | harness | aborted due to deadline | 8 |
| soak | RUST | harness | aborted due to deadline | 11 |

### Environment per cell (max over the cell's runs, % of the window)

| Cell | Server | steal | iowait | generator CPU |
|---|---|--:|--:|--:|
| 1k capacity search | NURL | 0.0 | 0.0 | 98 |
| 1k load 50% | NURL | 0.0 | 0.0 | 49 |
| 1k load 80% | NURL | 0.0 | 0.0 | 74 |
| 1k load 95% | NURL | 0.0 | 0.0 | 91 |
| 1k capacity search | RUST | 0.0 | 0.0 | 97 |
| 1k load 50% | RUST | 0.0 | 0.0 | 48 |
| 1k load 80% | RUST | 0.0 | 0.0 | 75 |
| 1k load 95% | RUST | 0.0 | 0.0 | 88 |
| 16k capacity search | RUST | 0.0 | 0.0 | 98 |
| 16k load 50% | RUST | 0.0 | 0.0 | 47 |
| 16k load 80% | RUST | 0.0 | 0.0 | 69 |
| 16k load 95% | RUST | 0.0 | 0.0 | 80 |
| 16k capacity search | NURL | 0.0 | 0.0 | 98 |
| 16k load 50% | NURL | 0.0 | 0.0 | 48 |
| 16k load 80% | NURL | 0.0 | 0.0 | 75 |
| 16k load 95% | NURL | 0.0 | 0.0 | 88 |
| 1m capacity search | NURL | 0.0 | 0.0 | 90 |
| 1m load 50% | NURL | 0.0 | 0.0 | 33 |
| 1m load 80% | NURL | 0.0 | 0.0 | 50 |
| 1m load 95% | NURL | 0.0 | 0.0 | 56 |
| 1m capacity search | RUST | 0.0 | 0.0 | 90 |
| 1m load 50% | RUST | 0.0 | 0.0 | 33 |
| 1m load 80% | RUST | 0.0 | 0.0 | 48 |
| 1m load 95% | RUST | 0.0 | 0.0 | 55 |
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
| soak | NURL | 0.0 | 0.0 | 74 |
| soak | RUST | 0.0 | 0.0 | 68 |

### Wall time per dimension

| Dimension | wall |
|---|--:|
| build | 1 min 11 s |
| settle | 2 min 0 s |
| loadlevels | 13 min 19 s |
| churn | 2 min 1 s |
| slowloris | 0 min 19 s |
| keepalive | 0 min 41 s |
| tls_resume | 0 min 3 s |
| soak | 20 min 27 s |
| **all** | **40 min 2 s** |

### Reading these numbers

- **A ‡ on a 1 KB capacity is the generator's ceiling, not the server's.** When both servers report a ‡ capacity, that is `oha` on 2-3 hitting its own generation limit — the honest conclusion is "both faster than this host can drive".
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request column makes it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body).
- **A tail claim needs the spread.** The 80 % cell of 1 KB and 16 KB is several runs; a difference inside their [min–max] ranges is not a difference.
- **Read the soak's drift, not its tail.** A † names a stall the VM's host caused, which coordinated-omission correction back-charges to the server being measured. The RSS slope and the fd counts are the server-specific signal (bounded per-connection buffers, freed at connection close).
