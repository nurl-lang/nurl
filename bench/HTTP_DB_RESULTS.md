# NURL HTTP + database peer-comparison

Generated `2026-11-13T20:46:58Z` by `bench/run_http.sh --suite db`. **Do not edit by hand** — the next run overwrites it.

The endpoints a service puts in front of a database — TechEmpower's five tests and HttpArena's `async-db` profile — served by `bench/http_server.nu` (the `packages/http` HttpApp facade in `http_app_async` mode, the database through `packages/psql`: one connection that every fiber's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `pg_query_many`) and by the Rust peer `bench/rust_http_server` (hyper on tokio's multi-thread runtime, the database through `tokio-postgres`: one client every task's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `try_join_all`). Both serve the same bytes (`bench/http_db_schema.sql`: 10 000 `world` rows, TechEmpower's 12 fortunes, 100 000 `items`, deterministic), and every endpoint is checked on both before a request is timed. Node has no database peer here.

**`CPU us/req` is the column to compare.** Server CPU time (`utime+stime` over every thread, read from `/proc/<pid>/stat` around the measured window) divided by the exact number of responses: what one request costs the server, whoever is the bottleneck. `req/s` here is often the database's ceiling rather than the server's — the database has cores of its own, one backend per connection — so two servers can show the same `req/s` at very different costs. The latency columns are closed-loop, as in `HTTP_RESULTS.md` (‡ = fewer connections in flight than offered, by Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `ab45d9db114a58fdab60f618c679e8af95643b5d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43501771359 |
| NURL | `v0.91.1-112-gab45d9db` |
| Rust | rustc 1.100.0 (0ef1bc386 2026-11-09) |
| Load generator | oha 1.8.0 |
| Database | throwaway PostgreSQL 18.6 (Ubuntu 18.6-1.pgdg26.04+2) on cores `2-2` (`taskset`), durability off |

| Setting | Value |
|---|---|
| Each cell | median of 3 x 10 s closed-loop runs, keep-alive; both servers up for the whole run, their cells alternating (NURL's, then Rust's, per path and concurrency) so a noisy stretch of a shared machine lands on both |
| Concurrencies | 64 , 256 |
| Core isolation | server on cores `0-1`, generator on cores `3-3` (`taskset`); the database as above |
| Worker threads | 2 per server (`NURL_WORKERS` / `TOKIO_WORKER_THREADS`) |
| CPU steal | 0.00 % of the machine's time over the measured cells (a VM's host taking its cores back) |
| Machine load | 1.95 at start (quiet) |

## Endpoint check

Before any timing: `/json`; `/db`; `/queries` with 20, 0, `foo` and 501 (→ 20, 1, 1, 500 rows); `/fortunes` (13 rows, the `<script>` row escaped, the added row present, byte order); `/updates?queries=5`; `/async-db?min=10&max=50&limit=5` (5 items in range, `tags` a list, `rating` an object).

| Server | Check |
|---|---|
| NURL | passed |
| Rust | passed |

## At a glance: server CPU per request

| Endpoint | NURL C=64 | Rust C=64 | NURL/Rust | NURL C=256 | Rust C=256 | NURL/Rust |
|---|---:|---:|---:|---:|---:|---:|
| `/json` | 11.83 | 12.11 | 0.98 | 12.60 | 12.41 | 1.02 |
| `/db` | 26.36 | 25.48 | 1.03 | 26.65 | 23.36 | 1.14 |
| `/queries?queries=20` | 192.36 | 184.12 | 1.04 | 229.66 | 198.88 | 1.15 |
| `/fortunes` | 29.03 | 28.37 | 1.02 | 31.00 | 27.61 | 1.12 |
| `/updates?queries=20` | 252.06 | 192.30 | 1.31 | 288.98 | 201.28 | 1.44 |
| `/async-db?limit=50` | 86.93 | 59.84 | 1.45 | 88.52 | 60.38 | 1.47 |

(µs of server CPU per request; NURL/Rust below 1 means NURL spends less.)

## 1. `/json`

A `{"message":"hello, world!"}` object serialised per request — no database.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **104 756** | 92 171 |
|              | Rust    | 103 818 | **95 911** |
| **p50 (ms)** | NURL    | 0.28 | 1.63 |
|              | Rust    | **0.27** | **1.51** |
| **p99 (ms)** | NURL    | **3.42** | 4.93 |
|              | Rust    | 3.43 | **4.81** |
| **CPU us/req** | NURL    | **11.83** | 12.60 |
|              | Rust    | 12.11 | **12.41** |

## 2. `/db`

One random `world` row by primary key, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 65 504 | **65 479** |
|              | Rust    | **66 086** | 63 419 |
| **p50 (ms)** | NURL    | 0.50 | **4.81** |
|              | Rust    | **0.49** | 4.87 |
| **p99 (ms)** | NURL    | 3.60 | **5.76** |
|              | Rust    | **3.59** | 6.15 |
| **CPU us/req** | NURL    | 26.36 | 26.65 |
|              | Rust    | **25.48** | **23.36** |

## 3. `/queries?queries=20`

N random `world` rows, one query each — all n sent together — as a json array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 4 509 | **4 635** |
|              | Rust    | **4 541** | 4 547 |
| **p50 (ms)** | NURL    | 14.07 | **55.31** |
|              | Rust    | **14.03** | 56.23 |
| **p99 (ms)** | NURL    | 16.39 | **58.21** |
|              | Rust    | **15.27** | 58.75 |
| **CPU us/req** | NURL    | 192.36 | 229.66 |
|              | Rust    | **184.12** | **198.88** |

## 4. `/fortunes`

Every `fortune` row plus one added at request time, sorted by message, as an escaped html table.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **64 297** | **55 193** |
|              | Rust    | 63 393 | 55 156 |
| **p50 (ms)** | NURL    | **0.89** | **5.19** |
|              | Rust    | 0.96 | 5.20 |
| **p99 (ms)** | NURL    | 3.60 | 7.29 |
|              | Rust    | **3.40** | **7.06** |
| **CPU us/req** | NURL    | 29.03 | 31.00 |
|              | Rust    | **28.37** | **27.61** |

## 5. `/updates?queries=20`

N random `world` rows read one query each, each given a new random number, written back by one `update … from unnest(…)`, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 2 986 | **3 123** |
|              | Rust    | **3 130** | **3 123** |
| **p50 (ms)** | NURL    | 21.25 | **81.81** |
|              | Rust    | **20.40** | 82.00 |
| **p99 (ms)** | NURL    | 26.59 | **90.05** |
|              | Rust    | **22.80** | 90.08 |
| **CPU us/req** | NURL    | 252.06 | 288.98 |
|              | Rust    | **192.30** | **201.28** |

## 6. `/async-db?limit=50`

Up to `limit` `items` rows with `price between min and max` (no index: a scan), as `{"items":[…],"count":n}` with a nested `rating` and a jsonb `tags` array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **9 678** | **9 596** |
|              | Rust    | 9 050 | 9 125 |
| **p50 (ms)** | NURL    | **6.60** | **26.64** |
|              | Rust    | 7.05 | 28.09 |
| **p99 (ms)** | NURL    | **7.08** | **28.44** |
|              | Rust    | 7.47 | 28.58 |
| **CPU us/req** | NURL    | 86.93 | 88.52 |
|              | Rust    | **59.84** | **60.38** |

(Best per row in **bold**; latency winners only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server failed its check or did not complete the cell.)

## Notes

- **One database connection per server**, pipelined — the shape both drivers are built for, and one PostgreSQL backend (one core) behind each server. A server that is cheaper per request than the database can keep up with shows it in `CPU us/req`, not in `req/s`.
- **`/updates`** reads its rows one query each (as TechEmpower requires) and writes them back in one statement, ids sorted so two requests touching the same rows lock them in the same order.
- **Against HttpArena's profiles.** `async-db` here has HttpArena's query, parameters, clamping and response shape over synthetic data of the same schema; HttpArena's `fortunes` has 200 rows where TechEmpower's (used here) has 12, so its pages are 15–30x larger.
- Loopback only, HTTP/1.1, plaintext to the database. Compare columns within one run, not across machines.
