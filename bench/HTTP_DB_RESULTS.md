# NURL HTTP + database peer-comparison

Generated `2026-11-06T17:12:48Z` by `bench/run_http.sh --suite db`. **Do not edit by hand** — the next run overwrites it.

The endpoints a service puts in front of a database — TechEmpower's five tests and HttpArena's `async-db` profile — served by `bench/http_server.nu` (the `packages/http` HttpApp facade in `http_app_async` mode, the database through `packages/psql`: one connection that every fiber's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `pg_query_many`) and by the Rust peer `bench/rust_http_server` (hyper on tokio's multi-thread runtime, the database through `tokio-postgres`: one client every task's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `try_join_all`). Both serve the same bytes (`bench/http_db_schema.sql`: 10 000 `world` rows, TechEmpower's 12 fortunes, 100 000 `items`, deterministic), and every endpoint is checked on both before a request is timed. Node has no database peer here.

**`CPU us/req` is the column to compare.** Server CPU time (`utime+stime` over every thread, read from `/proc/<pid>/stat` around the measured window) divided by the exact number of responses: what one request costs the server, whoever is the bottleneck. `req/s` here is often the database's ceiling rather than the server's — the database has cores of its own, one backend per connection — so two servers can show the same `req/s` at very different costs. The latency columns are closed-loop, as in `HTTP_RESULTS.md` (‡ = fewer connections in flight than offered, by Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `a3be3e7c7302008216b075e2746e99a350284802` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42256463950 |
| NURL | `v0.89.0-4-ga3be3e7c` |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Load generator | oha 1.8.0 |
| Database | throwaway PostgreSQL 18.6 (Ubuntu 18.6-1.pgdg26.04+2) on cores `2-2` (`taskset`), durability off |

| Setting | Value |
|---|---|
| Each cell | median of 3 x 10 s closed-loop runs, keep-alive; both servers up for the whole run, their cells alternating (NURL's, then Rust's, per path and concurrency) so a noisy stretch of a shared machine lands on both |
| Concurrencies | 64 , 256 |
| Core isolation | server on cores `0-1`, generator on cores `3-3` (`taskset`); the database as above |
| Worker threads | 2 per server (`NURL_WORKERS` / `TOKIO_WORKER_THREADS`) |
| CPU steal | 0.00 % of the machine's time over the measured cells (a VM's host taking its cores back) |
| Machine load | 1.74 at start (quiet) |

## Endpoint check

Before any timing: `/json`; `/db`; `/queries` with 20, 0, `foo` and 501 (→ 20, 1, 1, 500 rows); `/fortunes` (13 rows, the `<script>` row escaped, the added row present, byte order); `/updates?queries=5`; `/async-db?min=10&max=50&limit=5` (5 items in range, `tags` a list, `rating` an object).

| Server | Check |
|---|---|
| NURL | passed |
| Rust | passed |

## At a glance: server CPU per request

| Endpoint | NURL C=64 | Rust C=64 | NURL/Rust | NURL C=256 | Rust C=256 | NURL/Rust |
|---|---:|---:|---:|---:|---:|---:|
| `/json` | 16.61 | 17.27 | 0.96 | 16.00 | 16.43 | 0.97 |
| `/db` | 45.69 | 45.10 | 1.01 | 45.25 | 44.79 | 1.01 |
| `/queries?queries=20` | 271.76 | 270.11 | 1.01 | 306.27 | 273.09 | 1.12 |
| `/fortunes` | 46.57 | 46.48 | 1.00 | 46.55 | 46.33 | 1.00 |
| `/updates?queries=20` | 353.92 | 276.65 | 1.28 | 382.74 | 279.76 | 1.37 |
| `/async-db?limit=50` | 116.47 | 86.02 | 1.35 | 118.16 | 89.48 | 1.32 |

(µs of server CPU per request; NURL/Rust below 1 means NURL spends less.)

## 1. `/json`

A `{"message":"hello, world!"}` object serialised per request — no database.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **83 739** | **84 485** |
|              | Rust    | 83 450 | 83 468 |
| **p50 (ms)** | NURL    | **0.42** | **3.51** |
|              | Rust    | 0.43 | 4.40 |
| **p99 (ms)** | NURL    | **3.49** | **4.89** |
|              | Rust    | **3.49** | 5.10 |
| **CPU us/req** | NURL    | **16.61** | **16.00** |
|              | Rust    | 17.27 | 16.43 |

## 2. `/db`

One random `world` row by primary key, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **32 818** | **33 483** |
|              | Rust    | 32 799 | 33 264 |
| **p50 (ms)** | NURL    | **1.94** | **7.65** |
|              | Rust    | **1.94** | 7.69 |
| **p99 (ms)** | NURL    | **2.23** | **8.31** |
|              | Rust    | 2.27 | 8.40 |
| **CPU us/req** | NURL    | 45.69 | 45.25 |
|              | Rust    | **45.10** | **44.79** |

## 3. `/queries?queries=20`

N random `world` rows, one query each — all n sent together — as a json array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 2 473 | **2 612** |
|              | Rust    | **2 482** | 2 466 |
| **p50 (ms)** | NURL    | 25.90 | **98.21** |
|              | Rust    | **25.77** | 104.43 |
| **p99 (ms)** | NURL    | **27.21** | **105.33** |
|              | Rust    | 28.41 | 111.61 |
| **CPU us/req** | NURL    | 271.76 | 306.27 |
|              | Rust    | **270.11** | **273.09** |

## 4. `/fortunes`

Every `fortune` row plus one added at request time, sorted by message, as an escaped html table.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **37 071** | **37 695** |
|              | Rust    | 36 235 | 35 682 |
| **p50 (ms)** | NURL    | **1.71** | **6.78** |
|              | Rust    | 1.75 | 7.16 |
| **p99 (ms)** | NURL    | 2.10 | **7.76** |
|              | Rust    | **2.07** | 7.92 |
| **CPU us/req** | NURL    | 46.57 | 46.55 |
|              | Rust    | **46.48** | **46.33** |

## 5. `/updates?queries=20`

N random `world` rows read one query each, each given a new random number, written back by one `update … from unnest(…)`, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **1 900** | **1 970** |
|              | Rust    | 1 877 | 1 883 |
| **p50 (ms)** | NURL    | **33.41** | **130.02** |
|              | Rust    | 33.94 | 136.72 |
| **p99 (ms)** | NURL    | **37.58** | 158.03 |
|              | Rust    | 38.07 | **140.56** |
| **CPU us/req** | NURL    | 353.92 | 382.74 |
|              | Rust    | **276.65** | **279.76** |

## 6. `/async-db?limit=50`

Up to `limit` `items` rows with `price between min and max` (no index: a scan), as `{"items":[…],"count":n}` with a nested `rating` and a jsonb `tags` array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **6 688** | **6 621** |
|              | Rust    | 6 138 | 6 140 |
| **p50 (ms)** | NURL    | **9.55** | **38.65** |
|              | Rust    | 10.41 | 41.66 |
| **p99 (ms)** | NURL    | **10.01** | **40.78** |
|              | Rust    | 10.69 | 42.90 |
| **CPU us/req** | NURL    | 116.47 | 118.16 |
|              | Rust    | **86.02** | **89.48** |

(Best per row in **bold**; latency winners only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server failed its check or did not complete the cell.)

## Notes

- **One database connection per server**, pipelined — the shape both drivers are built for, and one PostgreSQL backend (one core) behind each server. A server that is cheaper per request than the database can keep up with shows it in `CPU us/req`, not in `req/s`.
- **`/updates`** reads its rows one query each (as TechEmpower requires) and writes them back in one statement, ids sorted so two requests touching the same rows lock them in the same order.
- **Against HttpArena's profiles.** `async-db` here has HttpArena's query, parameters, clamping and response shape over synthetic data of the same schema; HttpArena's `fortunes` has 200 rows where TechEmpower's (used here) has 12, so its pages are 15–30x larger.
- Loopback only, HTTP/1.1, plaintext to the database. Compare columns within one run, not across machines.
