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
| `loadlevels` | p50 / p99 / p99.9 at **50 / 80 / 95 %** of that capacity — how the tail behaves as you approach the ceiling. |
| `cpu` | CPU seconds per request (`/proc/<pid>/stat` utime+stime over a fixed run) — the efficiency number, independent of concurrency. |
| `churn` | Connection churn: a fresh TCP connection per request (no keep-alive) — accept + teardown cost. |
| `slowloris` | Many byte-at-a-time clients held open while a fast client is measured — does slow-client resource capture starve normal traffic? |
| `keepalive` | Many concurrent keep-alive connections — per-connection state cost at scale. |
| `tls_resume` | Does a TLS 1.3 reconnect skip the full handshake? (openssl issues a real request, stays connected for the post-handshake ticket, then reconnects with `-sess_in`.) |
| `soak` | A 10-minute open-loop run at 80 % — latency drift and RSS growth over time. |

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
- The generator is **verified not to be the bottleneck**: the ramp only
  trusts a rate where achieved tracked target, and the two servers plateau
  at *different* rates (proof the ceiling is the server, not `oha`).

## Running

```bash
# smoke (short, ~a few minutes; validates the pipeline)
bench/http_torture/run_torture.sh

# the real run (~80 min: a 120 s settle after the build, then every cell incl. two 10-min soaks)
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
