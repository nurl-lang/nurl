# NURL HTTP-server peer-comparison

Generated `2026-08-12T16:32:07Z` by `bench/run_http.sh`. **Do not edit by hand** — the next run overwrites it.

Each implementation accepts a TCP connection, parses one HTTP/1.1 request and writes a 14-byte `Hello, World!\n` body (`text/plain`), keep-alive. The TLS section runs the *same* servers and the same load over a self-signed EC (P-256) certificate; the load generator (`oha`) accepts it with `--insecure`. The NURL server is the `packages/http` HttpApp facade (`http_app_listen` / `http_app_listen_tls`) with a 10-thread worker pool — the surface a real NURL service deploys.

## Environment

| Item | Value |
|---|---|
| Host | `Linux x86_64` |
| Kernel | `Linux 7.0.0-28-generic x86_64` |
| CPU | Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz (12 logical cores) |
| Memory | 32770952 KiB |
| Commit | `3a75c2ec737b02e1de3352fad56335eb4d733bdc` |
| NURL | `v0.39.0-9-gdf2f443-dirty` |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v24.15.0 |
| Load generator | oha 1.8.0 |

| Setting | Value |
|---|---|
| Measurement | median of 3 × 10 s runs per cell, HTTP/1.1 keep-alive |
| Concurrencies | 1 , 10 , 50 , 200 |
| TLS cert | self-signed EC P-256, `CN=localhost` |

## 1. Plaintext HTTP

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **12 760** | **163 508** | 142 039 | 148 157 |
|              | Rust    | 11 718 | 144 619 | **207 764** | **292 159** |
|              | Node    | 9 625 | 26 943 | 28 145 | 27 485 |
| **p50 (ms)** | NURL    | **0.08** | **0.06** | **0.06** | **0.06** |
|              | Rust    | 0.09 | **0.06** | 0.20 | 0.63 |
|              | Node    | 0.09 | 0.32 | 1.64 | 6.86 |
| **p99 (ms)** | NURL    | **0.14** | **0.10** | **0.13** | **0.12** |
|              | Rust    | 0.16 | 0.14 | 0.75 | 1.65 |
|              | Node    | 0.19 | 0.73 | 3.62 | 13.40 |

## 2. TLS (HTTPS)

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | 10 646 | **130 281** | 113 308 | 116 459 |
|              | Rust    | **11 396** | 122 741 | **171 182** | **227 012** |
|              | Node    | 8 027 | 20 162 | 20 994 | 18 880 |
| **p50 (ms)** | NURL    | 0.09 | **0.07** | **0.07** | **0.07** |
|              | Rust    | **0.08** | 0.08 | 0.25 | 0.83 |
|              | Node    | 0.11 | 0.43 | 2.28 | 10.48 |
| **p99 (ms)** | NURL    | 0.16 | **0.12** | **0.15** | **0.16** |
|              | Rust    | **0.15** | 0.15 | 0.85 | 2.02 |
|              | Node    | 0.21 | 0.98 | 3.07 | 12.84 |

(Best per row in **bold**. Higher is better for req/s, lower for latency. `n/a` = tool absent at measurement time; `FAIL` = the server did not complete that cell.)

## Notes

- The TLS rows carry the full handshake + record-layer cost of NURL's pure-NURL TLS 1.3 stack (no OpenSSL); with keep-alive the handshake is amortised across a connection's requests, so the gap to plaintext is the per-record AEAD, not a per-request handshake.
- Rust serves TLS through `tokio-rustls`; Node through its built-in `https` module. Each implementation uses its conventional stack, so the columns compare deployments, not just ciphers.
- Loopback only, HTTP/1.1 only. No HTTP/2. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
