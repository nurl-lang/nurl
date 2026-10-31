# HTTP torture — NURL vs Rust, the numbers a hello-world bench hides

`bench/run_http.sh` is a **closed-loop, 14-byte-body** peer bench. It is
honest about what it measures, but two things it cannot see decide whether
a server is actually fast in production:

1. **Closed loop measures burst, not sustainable rate.** `oha -c N` holds N
   connections open and fires the next request the instant one returns, so
   a server that saturates below N just queues the surplus *inside the load
   generator*. `req/s` is real, but the latency percentiles describe only
   the few requests in flight — coordinated omission. The rate a service
   can actually sustain within a latency SLO is lower, and it is the number
   an SLA is written against.
2. **A 14-byte body hides the data path.** Real responses are kilobytes to
   megabytes. Per-byte costs in how a server forms and writes a body are
   invisible at 14 bytes and dominant at a megabyte.

This harness fixes both. It is **open-loop** (`oha -q <rate>
--latency-correction`, which back-charges the latency a coordinated-omission
run would hide) over **1 KB / 16 KB / 1 MB** bodies, and it measures the
**tail** (p50 / p99 / p99.9), which is what the load generator's honest
numbers are.

## What it measures

| Dimension | Question it answers |
|---|---|
| `capacity` | The highest offered rate the server sustains with achieved ≥ 97% of target **and** p99 ≤ `KNEE_MS` — the real ceiling, found by a doubling-then-bisection knee search (body-size agnostic: works at 1 MB's few-thousand req/s and 1 KB's past-200k alike). |
| `loadlevels` | p50 / p99 / p99.9 at **50 / 80 / 95 %** of that capacity — how the tail behaves as you approach the ceiling — and the server's **CPU µs per request** at each of the three (`/proc/<pid>/stat` utime+stime around the cell, divided by the exact response count). The 80 % cell of 1 KB and 16 KB runs `TAIL_RUNS` (3) times and reports median [min–max], so no single 20 s sample carries a tail claim. `cpu`, the separate CPU dimension this replaced, is accepted as an alias of `loadlevels` for one release. |
| `churn` | Connection churn: a fresh TCP connection per request (no keep-alive) — accept + teardown cost. |
| `slowloris` | Many byte-at-a-time clients held open while a fast client is measured — does slow-client resource capture starve normal traffic? |
| `keepalive` | Many concurrent keep-alive connections — per-connection state cost at scale. |
| `tls_resume` | Does a TLS 1.3 reconnect skip the full handshake? (openssl issues a real request, stays connected for the post-handshake ticket, then reconnects with `-sess_in`.) |
| `soak` | A 10-minute open-loop run at 80 % — one continuous oha run, sampled every 10 s beside it for the server's RSS, CPU, open fds and the VM's steal: RSS start→end (max) and slope per minute, fds start→end (max), and the windows whose steal passed 2 %. |

## Why a cell looks the way it does

Every cell is one or more oha runs, and each run leaves its oha JSON plus
the environment around it (`lib.py`, controls in
`tools/tests/test_http_torture_lib.py`):

- **errors** — oha's `errorDistribution`, split. *Harness artefacts* are
  errors the measurement makes: `aborted due to deadline` (a request still
  in flight when `-z` ends; oha leaves those out of its success rate too —
  an open-loop run at rate q with latency L has about q·L of them),
  `Too many open files` and `Cannot assign requested address` (the
  generator's own fd or port limits). Every other message counts against
  the server, so the expected server count is 0 and anything else is a
  finding. The cell shows the server count and its commonest type, the
  artefacts in brackets; *Errors by type* at the end lists every message
  per cell and server.
- **†** — the VM's steal passed 2 % of the cell's window (from
  `/proc/stat`). Coordinated-omission correction back-charges such a stall
  to whichever server was being measured.
- **‡** — the generator used ≥ 90 % of its cores (`GEN_CORES`) over the
  cell: the rate is oha's ceiling, not the server's. On a capacity cell
  the mark comes from the two ramp runs at the knee.
- *Environment per cell* lists the steal, iowait and generator CPU behind
  the marks; *Wall time per dimension* says where the run's time went.
- The header records the CPU family and flags (`bench/cpu_env.py`, the
  same helper the TLS bench keys its per-family reports on), the Rust
  peer's rustc / hyper / rustls / tokio versions and oha's.

## Fairness

- Both servers are pinned to the **same** cores (`SRV_CORES`); the load
  generator to disjoint cores (`GEN_CORES`), so the generator never steals
  the server's CPU and vice versa. The defaults split the online CPUs in
  half (`0-5` / `6-11` on a 12-thread host, `0-1` / `2-3` on a 4-vCPU
  runner); the NURL server sizes its worker pool by that affinity mask,
  exactly as tokio does.
- Both peers serve **byte-identical bodies** (`/` = 14 B, `/1k`, `/16k`,
  `/1m`), each built once at startup and handed to a response per request.
  The NURL peer is the `packages/http` HttpApp facade in `http_app_async`
  mode — the surface a real NURL service deploys. The Rust peer is
  hyper 1.x on tokio's multi-thread runtime with tokio-rustls for TLS (a
  ticketer installed, so it genuinely resumes) — the stack `axum`/`warp`
  build on.
- Whether the generator is the bottleneck is **measured per cell**: oha's
  own CPU time over the cell against its cores, marked ‡ at ≥ 90 % (see
  below). The ramp only trusts a rate where achieved tracked target.
- **Which server goes first alternates per body size** (1 KB NURL first,
  16 KB Rust first, …), so the first cell after the settle, the one a
  still-warm box biases, is not the same server's every time.

## Running

```bash
# smoke (short, ~a few minutes; validates the pipeline)
bench/http_torture/run_torture.sh

# the real run (under 60 min on the CI runner, build and two 10-min soaks
# included; the report's "Wall time per dimension" says where it went)
MODE=full bench/http_torture/run_torture.sh

# a subset
SIZES="16k" DIMS="capacity loadlevels" bench/http_torture/run_torture.sh
```

Needs `oha`, `cargo`, `openssl`, `taskset`, and a built NURL toolchain.
The report is written to `TORTURE_RESULTS.md`; the scratch directory
(per-cell oha JSON, server logs) is printed at the end for inspection.

`server.nu` is the NURL peer; `rust/` the hyper peer; `slowloris.py` and
`tls_resume.py` are the two probes bash can't express; `lib.py` extracts
the oha JSON fields.

## Whose numbers are in `TORTURE_RESULTS.md`

The committed table is whatever the **`http-torture` GitHub Action** last
wrote: a full run on an `ubuntu-latest` runner (4 vCPUs — servers on
cores 0-1, the generator on 2-3), committed to `main` the same way
`bench/HTTP_RESULTS.md` and `bench/PQ_RESULTS.md` are. Its header names
the host and links the run. Absolute numbers there are a fraction of a
workstation's; read the two servers against each other on the same
cores. Workstation runs (12 threads, servers on 0-5 / generator on 6-11)
are posted in the pull requests that changed the numbers (#1053, #1054,
#1055), not committed. When citing a cell, say which host produced it.
