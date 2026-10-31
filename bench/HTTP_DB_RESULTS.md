# NURL HTTP + database peer-comparison

Generated `2026-10-31T12:24:46Z` by `bench/run_http.sh --suite db`. **Do not edit by hand** — the next run overwrites it.

The endpoints a service puts in front of a database — TechEmpower's five tests and HttpArena's `async-db` profile — served by `bench/http_server.nu` (the `packages/http` HttpApp facade in `http_app_async` mode, the database through `packages/psql`: one connection that every fiber's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `pg_query_many`) and by the Rust peer `bench/rust_http_server` (hyper on tokio's multi-thread runtime, the database through `tokio-postgres`: one client every task's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `try_join_all`). Both serve the same bytes (`bench/http_db_schema.sql`: 10 000 `world` rows, TechEmpower's 12 fortunes, 100 000 `items`, deterministic), and every endpoint is checked on both before a request is timed. Node has no database peer here.

**`CPU us/req` is the column to compare.** Server CPU time (`utime+stime` over every thread, read from `/proc/<pid>/stat` around the measured window) divided by the exact number of responses: what one request costs the server, whoever is the bottleneck. `req/s` here is often the database's ceiling rather than the server's — the database has cores of its own, one backend per connection — so two servers can show the same `req/s` at very different costs. The latency columns are closed-loop, as in `HTTP_RESULTS.md` (‡ = fewer connections in flight than offered, by Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `cloud VM (Claude Code session, local run)` |
| Kernel | `Linux 6.18.44-fc-v185 x86_64` |
| CPU | Intel(R) Xeon(R) Processor @ 2.10GHz (4 logical cores) |
| Memory | 16477352 KiB |
| Commit | `b6c930d3c88f42938687f3938bf77d75b4f25c71` |
| NURL | `v0.82.0-40-gb6c930d3` |
| Rust | rustc 1.97.0 (2d8144b78 2026-07-07) |
| Load generator | oha 1.16.0 |
| Database | throwaway PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1) on cores `2-2` (`taskset`), durability off |

| Setting | Value |
|---|---|
| Each cell | median of 3 x 10 s closed-loop runs, keep-alive; both servers up for the whole run, their cells alternating (NURL's, then Rust's, per path and concurrency) so a noisy stretch of a shared machine lands on both |
| Concurrencies | 64 , 256 |
| Core isolation | server on cores `0-1`, generator on cores `3-3` (`taskset`); the database as above |
| Worker threads | 2 per server (`NURL_WORKERS` / `TOKIO_WORKER_THREADS`) |
| CPU steal | 0.90 % of the machine's time over the measured cells (a VM's host taking its cores back) |
| Machine load | 1.50 at start (quiet) |

## Endpoint check

Before any timing: `/json`; `/db`; `/queries` with 20, 0, `foo` and 501 (→ 20, 1, 1, 500 rows); `/fortunes` (13 rows, the `<script>` row escaped, the added row present, byte order); `/updates?queries=5`; `/async-db?min=10&max=50&limit=5` (5 items in range, `tags` a list, `rating` an object).

| Server | Check |
|---|---|
| NURL | passed |
| Rust | passed |

## At a glance: server CPU per request

| Endpoint | NURL C=64 | Rust C=64 | NURL/Rust | NURL C=256 | Rust C=256 | NURL/Rust |
|---|---:|---:|---:|---:|---:|---:|
| `/json` | 11.47 | 11.63 | 0.99 | 11.10 | 10.44 | 1.06 |
| `/db` | 20.54 | 19.42 | 1.06 | 20.84 | 19.17 | 1.09 |
| `/queries?queries=20` | 230.52 | 210.63 | 1.09 | 254.01 | 230.31 | 1.10 |
| `/fortunes` | 29.07 | 24.67 | 1.18 | 28.22 | 23.49 | 1.20 |
| `/updates?queries=20` | 297.52 | 251.08 | 1.18 | 332.90 | 265.32 | 1.25 |
| `/async-db?limit=50` | 246.50 | 112.93 | 2.18 | 239.32 | 113.36 | 2.11 |

(µs of server CPU per request; NURL/Rust below 1 means NURL spends less.)

## 1. `/json`

A `{"message":"hello, world!"}` object serialised per request — no database.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **85 078** | **96 163** |
|              | Rust    | 83 529 | 93 655 |
| **p50 (ms)** | NURL    | **0.18** | **0.66** |
|              | Rust    | **0.18** | 0.67 |
| **p99 (ms)** | NURL    | **12.31** | 16.61 |
|              | Rust    | 12.33 | **16.58** |
| **CPU us/req** | NURL    | **11.47** | 11.10 |
|              | Rust    | 11.63 | **10.44** |

## 2. `/db`

One random `world` row by primary key, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 84 039 | 80 372 |
|              | Rust    | **86 495** | **88 789** |
| **p50 (ms)** | NURL    | 0.69 | 2.96 |
|              | Rust    | **0.58** | **1.45** |
| **p99 (ms)** | NURL    | **2.46** | **13.01** |
|              | Rust    | 3.97 | 16.74 |
| **CPU us/req** | NURL    | 20.54 | 20.84 |
|              | Rust    | **19.42** | **19.17** |

## 3. `/queries?queries=20`

N random `world` rows, one query each — all n sent together — as a json array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 3 468 | **5 572** |
|              | Rust    | **3 614** | 3 625 |
| **p50 (ms)** | NURL    | 17.40 | **41.77** |
|              | Rust    | **16.96** | 65.44 |
| **p99 (ms)** | NURL    | 31.05 | **92.56** |
|              | Rust    | **30.69** | 114.25 |
| **CPU us/req** | NURL    | 230.52 | 254.01 |
|              | Rust    | **210.63** | **230.31** |

## 4. `/fortunes`

Every `fortune` row plus one added at request time, sorted by message, as an escaped html table.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 63 019 | 63 965 |
|              | Rust    | **75 310** | **79 744** |
| **p50 (ms)** | NURL    | 0.95 | 3.78 |
|              | Rust    | **0.82** | **2.92** |
| **p99 (ms)** | NURL    | 2.24 | **8.94** |
|              | Rust    | **2.16** | 13.13 |
| **CPU us/req** | NURL    | 29.07 | 28.22 |
|              | Rust    | **24.67** | **23.49** |

## 5. `/updates?queries=20`

N random `world` rows read one query each, each given a new random number, written back by one `update … from unnest(…)`, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **2 036** | **2 329** |
|              | Rust    | 1 977 | 2 047 |
| **p50 (ms)** | NURL    | **29.59** | **101.25** |
|              | Rust    | 31.41 | 118.15 |
| **p99 (ms)** | NURL    | **50.13** | **183.89** |
|              | Rust    | 50.43 | 196.84 |
| **CPU us/req** | NURL    | 297.52 | 332.90 |
|              | Rust    | **251.08** | **265.32** |

## 6. `/async-db?limit=50`

Up to `limit` `items` rows with `price between min and max` (no index: a scan), as `{"items":[…],"count":n}` with a nested `rating` and a jsonb `tags` array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 6 813 | 7 884 |
|              | Rust    | **7 355** | **8 410** |
| **p50 (ms)** | NURL    | 9.02 | 31.40 |
|              | Rust    | **7.60** | **27.43** |
| **p99 (ms)** | NURL    | 15.06 | **47.13** |
|              | Rust    | **13.26** | 49.93 |
| **CPU us/req** | NURL    | 246.50 | 239.32 |
|              | Rust    | **112.93** | **113.36** |

(Best per row in **bold**; latency winners only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server failed its check or did not complete the cell.)

## Notes

- **One database connection per server**, pipelined — the shape both drivers are built for, and one PostgreSQL backend (one core) behind each server. A server that is cheaper per request than the database can keep up with shows it in `CPU us/req`, not in `req/s`.
- **`/updates`** reads its rows one query each (as TechEmpower requires) and writes them back in one statement, ids sorted so two requests touching the same rows lock them in the same order.
- **Against HttpArena's profiles.** `async-db` here has HttpArena's query, parameters, clamping and response shape over synthetic data of the same schema; HttpArena's `fortunes` has 200 rows where TechEmpower's (used here) has 12, so its pages are 15–30x larger.
- Loopback only, HTTP/1.1, plaintext to the database. Compare columns within one run, not across machines.
