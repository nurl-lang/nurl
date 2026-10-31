### Changed

- **tls-bench keeps one result per CPU family, and every run says which
  CPU and which NURL kernels produced it** (Agora #112). The runner pool
  hands out AMD Zen 3, AMD Zen 5 and Intel Ice Lake machines, and NURL's
  share of aws-lc's speed flips with the family — AES-128-GCM sealing at
  179 % on Zen 3 and 83 % on Zen 5 — while each run overwrote the one
  report. Now a full run is recorded as its family's latest
  (`bench/tls_bench/runs/<family>.tsv`), every family has its own
  `TLS_RESULTS.<family>.md`, and `TLS_RESULTS.md` is an index that sets
  the families side by side, worst metric first, marking each metric
  whose verdict differs between them. The family is the CPU's vendor and
  flags (`amd-avx2-vaes-sha-adx`, `amd-avx512ifma-vaes-sha-adx`,
  `intel-avx512ifma-vaes-sha-adx`, …), never its model string. Each run
  records the crypto-relevant CPU flags, NURL's CPU probes, the kernel
  each primitive engaged, and any `NURL_CPU_*` / `OPENSSL_ia32cap`
  masking; the generator refuses a run missing any of them. A perf task
  "on the runner" now means on every family in the index
  (bench/tls_bench/README.md). Gate: `tools/tests/test_tls_bench_report.py`
  in CI. A local `run_tls.sh` no longer overwrites the committed report;
  `STORE=1` records a run.

### Added

- `aes_gcm_cpu_tier`, `chacha20poly1305_cpu_tier`, `sha256_cpu_tier`,
  `rsa_cpu_tier`, `p256_cpu_tier`, `x25519_cpu_tier` and `mlkem_cpu_tier`
  name the kernel each module runs on this CPU (`vaes512`, `adx`, `sha-ni`,
  `ifma`, `avx2`, `portable`, …), after any `NURL_CPU_*=0` masking — each
  sits next to the dispatch it describes. The P-256 and X25519 answers
  come from the compiler's field kernels themselves, so they hold on every
  target. `bench/tls_bench/prims.nu --tiers` prints them.
