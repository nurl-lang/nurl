# HTTP torture — NURL vs Rust (hyper/rustls)

Open-loop, coordinated-omission corrected (`oha -q --latency-correction`). Server pinned to cores `0-1`, generator to `2-3`. Both peers serve byte-identical bodies. MODE=**full**.

- Host: **GitHub Actions ubuntu-latest runner** — `Linux 7.0.0-1019-azure` — INTEL(R) XEON(R) PLATINUM 8573C (4 CPUs)
- CPU family `intel-avx512ifma-vaes-sha-adx` (bench/cpu_env.py) — flags: `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq gfni avx512f avx512vl avx512bw avx512ifma avx512vbmi`
- NURL: `v0.92.1-82-ge15ed57f`  ·  Rust peer: rustc `1.100.0`, hyper 1.11.1, rustls 0.23.43, tokio 1.53.1  ·  oha: `oha 1.8.0`  ·  commit `e15ed57f`
- Run: https://github.com/nurl-lang/nurl/actions/runs/44499671282
- Sustainable capacity = highest offered rate with achieved ≥ 97% of target and p99 ≤ 50 ms.
- **†** the VM's steal passed 2 % of the cell's window (a stall coordinated-omission correction charges to the server being measured). **‡** the generator used ≥ 90 % of its cores (`2-3`): the rate is oha's ceiling, not the server's. On a capacity cell a mark means the run at the knee carried it. **errors**: server-attributable count and its commonest type, then the harness artefacts in brackets — the full list is under *Errors by type*.

### Body 1k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 144000 ‡ | 0.729/3.717/28.081 | 1.228 / 60.61 [41.07–61.97] / 96.14 [66.89–97.23] | 1.164/93.252/115.349 ‡ | 10.08 / 9.76 / 9.79 | 0 (+31 harness: deadline) |
| RUST | 152000 ‡ | 0.772/1.785/9.064 | 1.274 / 69.35 [68.00–69.52] / 99.91 [99.16–102.51] | 0.929/99.070/115.720 ‡ | 10.26 / 9.83 / 9.94 | 0 (+19 harness: deadline) |

### Body 16k — sustainable capacity & tail under load

The 80 % cell is 3 runs: p50 / p99 / p99.9 as median [min–max] (ms). Measured first: RUST.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 116000 ‡ | 0.737/2.337/15.480 | 1.120 / 20.58 [16.27–60.78] / 43.30 [35.63–85.96] | 0.930/69.657/90.275 ‡ | 14.77 / 14.18 / 13.92 | 0 (+21 harness: deadline) |
| RUST | 124000 ‡ | 0.740/2.319/8.456 | 1.181 / 20.95 [6.60–21.50] / 41.96 [20.59–52.36] | 4.514/129.887/138.660 ‡ | 14.24 / 14.15 / 14.57 | 0 (+62 harness: deadline) |

### Body 1m — sustainable capacity & tail under load

Measured first: NURL.

| Server | Sustainable req/s | 50% p50/p99/p99.9 (ms) | 80% p50/p99/p99.9 | 95% p50/p99/p99.9 | CPU µs/req at 50/80/95% | errors |
|---|--:|--:|--:|--:|--:|--:|
| NURL | 4750 | 0.488/0.954/1.524 | 0.707/1.604/12.467 | 0.773/10.459/45.936 | 189.48 / 218.96 / 231.73 | 0 (+20 harness: deadline) |
| RUST | 4250 | 0.415/0.879/1.306 | 0.596/1.416/8.795 | 0.639/7.850/50.449 | 244.48 / 244.71 / 252.92 | 0 (+12 harness: deadline) |

### Body 1k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 37677 ‡ | 2.688/3.063/4.155 | 1.0000 | 0 (+88 harness: deadline) |
| RUST | 37054 ‡ | 2.663/3.159/4.163 | 1.0000 | 0 (+90 harness: deadline) |

### Body 16k — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 34796 ‡ | 2.919/3.216/4.355 | 1.0000 | 0 (+97 harness: deadline) |
| RUST | 34394 ‡ | 2.913/3.354/4.260 | 1.0000 | 0 (+97 harness: deadline) |

### Body 1m — connection churn (no keep-alive, fresh conn/request)

| Server | req/s (churn) | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|
| NURL | 4606 ‡ | 21.735/26.201/40.480 | 1.0000 | 0 (+93 harness: deadline) |
| RUST | 4585 ‡ | 21.837/24.806/35.955 | 1.0000 | 0 (+97 harness: deadline) |

### Slowloris — 200 trickle clients held open, fast-client latency meanwhile (16k)

| Server | fast-client req/s | p50/p99 (ms) | survived | errors |
|---|--:|--:|:--:|--:|
| NURL | 142730 ‡ | 0.133/0.266 | yes | 0 (+18 harness: deadline) |
| RUST | 145572 ‡ | 0.133/0.202 | yes | 0 (+14 harness: deadline) |

### Keep-alive scale — 2000 concurrent keep-alive connections (1k body)

| Server | conns | req/s | p50/p99/p99.9 (ms) | ok | errors |
|---|--:|--:|--:|--:|--:|
| NURL | 2000 | 119710 ‡ | 16.428/22.533/53.726 | 1.0000 | 0 (+1617 harness: deadline) |
| RUST | 2000 | 117640 ‡ | 16.673/23.790/43.367 | 1.0000 | 0 (+1715 harness: deadline) |

### TLS 1.3 session resumption — does a reconnect skip the full handshake?

| Server | resumption supported? | ticket | reconnect |
|---|:--:|:--:|:--:|
| NURL | yes | ticket issued | yes (Reused) |
| RUST | yes | ticket issued | yes (Reused) |

### Soak — 600s open-loop at 80% of capacity (16k), sampled every 10s

| Server | req/s | p50/p99/p99.9 (ms) | ok | errors | RSS KiB start→end (max) | RSS KiB/min | CPU % of a core | open fds start→end (max) | steal > 2 % |
|---|--:|--:|--:|--:|--:|--:|--:|--:|---|
| NURL | 92799 | 1.056/610.980/1439.582 | 1.0000 | 0 (+23 harness: deadline) | 4968→8496 (max 9072) | +21.8 | 122 | 9→9 (max 409) | none |
| RUST | 99199 | 1.196/725.078/1510.386 | 1.0000 | 0 (+2 harness: deadline) | 4676→8920 (max 9936) | +29.3 | 134 | 9→9 (max 409) | none |

---

### Errors by type

Harness artefacts are errors the measurement makes (`deadline`, `EMFILE`, `EADDRNOTAVAIL`); every other message counts against the server. Server-attributable errors in this run: **0**.

| Cell | Server | Kind | Error | Count |
|---|---|---|---|--:|
| 1k capacity search | NURL | harness | aborted due to deadline | 92 |
| 1k load 50% | NURL | harness | aborted due to deadline | 4 |
| 1k load 80% | NURL | harness | aborted due to deadline | 13 |
| 1k load 95% | NURL | harness | aborted due to deadline | 14 |
| 1k capacity search | RUST | harness | aborted due to deadline | 101 |
| 1k load 50% | RUST | harness | aborted due to deadline | 2 |
| 1k load 80% | RUST | harness | aborted due to deadline | 9 |
| 1k load 95% | RUST | harness | aborted due to deadline | 8 |
| 16k capacity search | RUST | harness | aborted due to deadline | 49 |
| 16k load 50% | RUST | harness | aborted due to deadline | 7 |
| 16k load 80% | RUST | harness | aborted due to deadline | 12 |
| 16k load 95% | RUST | harness | aborted due to deadline | 43 |
| 16k capacity search | NURL | harness | aborted due to deadline | 77 |
| 16k load 50% | NURL | harness | aborted due to deadline | 8 |
| 16k load 80% | NURL | harness | aborted due to deadline | 12 |
| 16k load 95% | NURL | harness | aborted due to deadline | 1 |
| 1m capacity search | NURL | harness | aborted due to deadline | 289 |
| 1m load 50% | NURL | harness | aborted due to deadline | 6 |
| 1m load 80% | NURL | harness | aborted due to deadline | 8 |
| 1m load 95% | NURL | harness | aborted due to deadline | 6 |
| 1m capacity search | RUST | harness | aborted due to deadline | 316 |
| 1m load 50% | RUST | harness | aborted due to deadline | 4 |
| 1m load 80% | RUST | harness | aborted due to deadline | 3 |
| 1m load 95% | RUST | harness | aborted due to deadline | 5 |
| 1k churn | RUST | harness | aborted due to deadline | 90 |
| 1k churn | NURL | harness | aborted due to deadline | 88 |
| 16k churn | NURL | harness | aborted due to deadline | 97 |
| 16k churn | RUST | harness | aborted due to deadline | 97 |
| 1m churn | RUST | harness | aborted due to deadline | 97 |
| 1m churn | NURL | harness | aborted due to deadline | 93 |
| slowloris | NURL | harness | aborted due to deadline | 18 |
| slowloris | RUST | harness | aborted due to deadline | 14 |
| keep-alive scale | RUST | harness | aborted due to deadline | 1715 |
| keep-alive scale | NURL | harness | aborted due to deadline | 1617 |
| soak | NURL | harness | aborted due to deadline | 23 |
| soak | RUST | harness | aborted due to deadline | 2 |

### Environment per cell (max over the cell's runs, % of the window)

| Cell | Server | steal | iowait | generator CPU |
|---|---|--:|--:|--:|
| 1k capacity search | NURL | 0.0 | 0.0 | 97 |
| 1k load 50% | NURL | 0.0 | 0.0 | 53 |
| 1k load 80% | NURL | 0.0 | 0.0 | 78 |
| 1k load 95% | NURL | 0.0 | 0.0 | 91 |
| 1k capacity search | RUST | 0.0 | 0.0 | 97 |
| 1k load 50% | RUST | 0.0 | 0.0 | 57 |
| 1k load 80% | RUST | 0.0 | 0.0 | 82 |
| 1k load 95% | RUST | 0.0 | 0.0 | 96 |
| 16k capacity search | RUST | 0.0 | 0.0 | 97 |
| 16k load 50% | RUST | 0.0 | 0.0 | 58 |
| 16k load 80% | RUST | 0.0 | 0.0 | 88 |
| 16k load 95% | RUST | 0.0 | 0.0 | 97 |
| 16k capacity search | NURL | 0.0 | 0.0 | 97 |
| 16k load 50% | NURL | 0.0 | 0.0 | 58 |
| 16k load 80% | NURL | 0.0 | 0.0 | 82 |
| 16k load 95% | NURL | 0.0 | 0.0 | 94 |
| 1m capacity search | NURL | 0.0 | 0.0 | 99 |
| 1m load 50% | NURL | 0.0 | 0.0 | 36 |
| 1m load 80% | NURL | 0.0 | 0.0 | 53 |
| 1m load 95% | NURL | 0.0 | 0.0 | 61 |
| 1m capacity search | RUST | 0.0 | 0.0 | 100 |
| 1m load 50% | RUST | 0.0 | 0.0 | 34 |
| 1m load 80% | RUST | 0.0 | 0.0 | 49 |
| 1m load 95% | RUST | 0.0 | 0.0 | 57 |
| 1k churn | RUST | 0.0 | 0.0 | 99 |
| 1k churn | NURL | 0.0 | 0.0 | 99 |
| 16k churn | NURL | 0.0 | 0.6 | 99 |
| 16k churn | RUST | 0.0 | 0.6 | 99 |
| 1m churn | RUST | 0.0 | 0.0 | 100 |
| 1m churn | NURL | 0.0 | 0.0 | 100 |
| slowloris | NURL | 0.0 | 0.0 | 96 |
| slowloris | RUST | 0.0 | 0.0 | 97 |
| keep-alive scale | RUST | 0.0 | 0.0 | 98 |
| keep-alive scale | NURL | 0.0 | 0.0 | 98 |
| soak | NURL | 0.0 | 0.0 | 79 |
| soak | RUST | 0.0 | 0.0 | 85 |

### Wall time per dimension

| Dimension | wall |
|---|--:|
| build | 0 min 25 s |
| settle | 2 min 0 s |
| loadlevels | 13 min 46 s |
| churn | 2 min 2 s |
| slowloris | 0 min 19 s |
| keepalive | 0 min 41 s |
| tls_resume | 0 min 3 s |
| soak | 20 min 35 s |
| **all** | **39 min 53 s** |

### Reading these numbers

- **A ‡ on a 1 KB capacity is the generator's ceiling, not the server's.** When both servers report a ‡ capacity, that is `oha` on 2-3 hitting its own generation limit — the honest conclusion is "both faster than this host can drive".
- **Read the body-size axis as the data path.** A difference that grows from 1 KB to 16 KB to 1 MB is a per-byte cost, not a per-request one; the CPU-per-request column makes it visible directly. The two such costs this harness found — the response body copied into the connection's wire buffer before the write, and the handler's buffer copied into the response — are gone (head and body leave in one `sendmsg`; a response can borrow a caller-owned body).
- **A tail claim needs the spread.** The 80 % cell of 1 KB and 16 KB is several runs; a difference inside their [min–max] ranges is not a difference.
- **Read the soak's drift, not its tail.** A † names a stall the VM's host caused, which coordinated-omission correction back-charges to the server being measured. The RSS slope and the fd counts are the server-specific signal (bounded per-connection buffers, freed at connection close).
