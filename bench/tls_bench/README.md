# TLS benchmark — NURL vs Rust, every cost a TLS 1.3 HTTP stack pays

`bench/http_torture` asks how an HTTP server behaves under load; this asks
what its **TLS** costs, piece by piece, against the stack production Rust
deploys — rustls on aws-lc-rs (assembly AES-GCM and X25519, the
X25519MLKEM768 hybrid), hyper on tokio, reqwest — so the report can say
which piece to work on next.

Each report leads with **Where to focus**: every headline metric as
NURL's share of Rust's, worst first, each with what the measurements say
the gap is made of. Everything below that table is the evidence for it.
There is one report per **CPU family** (below); `TLS_RESULTS.md` is the
index that sets the families side by side.

## What it measures

| Section | Question it answers |
|---|---|
| `prims` | What does each primitive a handshake and a record are made of cost, single core? X25519, P-256 ECDH, ML-KEM-768 encaps, ECDSA P-256 sign / verify, RSA-2048 PSS sign, HKDF-Expand-Label, SHA-256, AES-128-GCM and ChaCha20-Poly1305 sealing a 16 KB record. |
| `handshake` | Full and resumed handshakes per second at saturation, per group (X25519, P-256, X25519MLKEM768) and certificate (ECDSA P-256, RSA-2048) — and the **server CPU per handshake**, split into the *crypto budget* (that handshake's primitives from `prims`) and the *rest* (protocol code, allocation, runtime, socket I/O). |
| `latency` | The same handshakes one at a time: unloaded handshake latency. |
| `records` | Small keep-alive requests (1 KB) over TLS and over plaintext: the record layer's CPU per request-response, as the difference of the two. |
| `bulk` | One connection downloading 1 MB bodies: MB/s and server CPU per KB per cipher suite, against the plaintext baseline and the AEAD's own floor — and NURL with kTLS (`NURL_KTLS=1`), with the kernel's counter saying whether it engaged. |
| `client` | `packages/http-client` against reqwest, single-threaded, against the same server: a new connection per request with and without resumption, keep-alive 1 KB, keep-alive 1 MB. |

## Fairness

- **Same surfaces an application uses.** The NURL server is the
  `packages/http` HttpApp in `http_app_async` mode
  (`bench/http_torture/server.nu`, the same binary the torture harness
  measures); the Rust server is hyper 1.x on tokio with tokio-rustls
  (`rust/src/bin/tls_server.rs`). Same routes, byte-identical bodies, TLS
  1.3 only, ALPN `http/1.1`, one session ticket per connection on both.
- **One generator for both.** `tls_load` is a thin tokio-rustls HTTP/1.1
  client; it pins the group and suite each row measures, so neither
  server's preference order decides a row. It verifies the
  CertificateVerify signature (a real client's cost) but accepts the
  self-signed certificate.
- **Cores.** The server gets `SRV_CORES` (default the lowest quarter of the
  CPUs, at least one — core 0 on a 4-vCPU runner), the generator the rest:
  a TLS client costs about as much per handshake as the server, so the
  generator needs the bigger share. Every saturation cell records the
  server's CPU utilisation, and the report marks (†) any cell where the
  server was not the bottleneck.
- **CPU per operation is the absolute number.** Rates scale with cores;
  server CPU per handshake / request / KB does not.
- **Primitives on the same discipline.** `prims.nu` uses stdlib
  `bench_auto`; `tls_prims` re-implements its ramp (4× until a pass clears
  50 ms, then one calibrated pass).

## Running

```bash
# smoke (~3 min; checks the pipeline end to end)
bench/tls_bench/run_tls.sh

# the real run (~10 min of measurement after the builds)
MODE=full bench/tls_bench/run_tls.sh

# a subset
DIMS="handshake latency" MODE=full bench/tls_bench/run_tls.sh

# record the run as its CPU family's latest (what the workflow does)
STORE=1 MODE=full bench/tls_bench/run_tls.sh
```

The run's own report goes to `$MD_OUT` (default: the scratch directory);
only `STORE=1` touches the committed files.

Needs `cargo` (and `cmake`, for aws-lc-rs), `openssl`, `curl`, `taskset`,
`python3` and a built NURL toolchain (`./build.sh`). The raw results and
server logs stay in the scratch directory printed at the end.

## Files

| File | |
|---|---|
| `run_tls.sh` | the driver: builds, makes the certificates, runs every cell, writes the report |
| `gen_tls_results.py` | raw results → a run's report; `--store` / `--render`: the per-family reports and the index |
| `runs/<family>.tsv` | the raw results of each CPU family's latest full run (generated) |
| `TLS_RESULTS.<family>.md`, `TLS_RESULTS.md` | each family's report, and the index (generated) |
| `prims.nu` | the NURL primitives; `prims --tiers` prints NURL's CPU probes and each primitive's kernel |
| `client.nu` | the NURL client rows, on `packages/http-client` |
| `rust/` | `tls_server`, `tls_load`, `tls_prims`, `tls_client` (reqwest) |

## CPU families

The `ubuntu-latest` pool is not one machine. Runs have landed on AMD EPYC
7763 (Zen 3: AVX2, ADX, SHA-NI, 256-bit VAES, no AVX-512), AMD EPYC 9V45
(Zen 5: AVX-512 with IFMA and 512-bit VAES) and Intel Xeon 8370C (Ice
Lake: likewise), and the ratios move with the machine, not with the code:
AES-128-GCM sealing ran at 179 % of aws-lc on Zen 3 and 83 % on Zen 5, and
aws-lc signs RSA-2048 on its IFMA path on the AVX-512 hosts and on its ADX
path on Zen 3. Both sides pick kernels by CPUID, so a ratio is a property
of a family.

A run's **family** is its CPU vendor and flags — never its model string:
`<vendor>-<vector ISA>[-vaes][-sha][-adx]`, the vector ISA being
`avx512ifma`, `avx512`, `avx2` (AArch64: `sve`, `neon`). Zen 3 is
`amd-avx2-vaes-sha-adx`, Zen 4/5 `amd-avx512ifma-vaes-sha-adx`, Ice Lake
`intel-avx512ifma-vaes-sha-adx`. Every run records what decides it and
what NURL did with it: `cpu_vendor` and `cpu_flags` (the crypto-relevant
flags present), NURL's CPU probes and the kernel each primitive engaged
(`prims --tiers`, from each module's `*_cpu_tier`), any `NURL_CPU_*`
masking and aws-lc's `OPENSSL_ia32cap`. A run missing any of them is
refused by the generator rather than reported without them.

A full run replaces only its own family's `runs/<family>.tsv`; every
report is re-rendered from `runs/`, so each family keeps its latest run
until the pool lands on it again. Each report states its date and commit,
so a stale family shows as stale.

**On the runner** — when a perf task's DONE WHEN says "on the runner", it
means on **every family in `TLS_RESULTS.md`**. The pull request that
closes the task quotes the rows of each family, and says which families
were re-measured after the change; a family whose run predates the change
is either re-run (`tls-bench` again, until the pool lands on it) or named
as unmeasured.

## Whose numbers are in `TLS_RESULTS*.md`

Whatever the **`tls-bench` GitHub Action** (`.github/workflows/tls-bench.yml`,
manual) last recorded in `full` mode on an `ubuntu-latest` runner of each
family; each report's header names the CPU and links the run. Workstation
runs are posted in the pull requests that change the numbers, not
committed. When citing a cell, say which family and which run produced it.
