### Changed

- **The HTTP torture report says why a cell looks the way it does, and
  the whole workflow fits in an hour** (Agora #120).
  - Every cell's errors are split into harness artefacts and
    server-attributable ones; the artefacts are a request still in flight
    when oha's `-z` ends, and the generator's own fd and port limits.
    Every distinct message is listed per cell. The soak's "1 to 9 errors,
    never 0" were all `aborted due to deadline`: requests in flight when
    the run ended, which oha itself leaves out of its success rate. Server
    errors on a smoke run of every dimension: 0.
  - **†** marks a cell whose window lost more than 2 % to the VM's steal.
    **‡** marks one whose generator used ≥ 90 % of its cores. This replaces
    the "1 KB is generator-bound" prose with a measurement.
  - The server's CPU per request is reported at 50, 80 and 95 % load, and
    the separate `cpu` dimension is gone (`cpu` remains an alias of
    `loadlevels` for one release).
  - The 1 KB and 16 KB 80 % cell runs three times and reports p99 and
    p99.9 as median [min–max].
  - Which server goes first alternates per body size.
  - The soak, still one continuous run, is sampled every 10 s for RSS (and
    its slope per minute), CPU, open fds and steal.
  - The header records the CPU family and flags (`bench/cpu_env.py`, now
    shared with tls-bench), the Rust peer's rustc / hyper / rustls / tokio
    versions, and the wall time per dimension.
  - The workflow caches oha and the Rust peer's build. It has a `mode`
    input, and commits its report only from a full run on main.
