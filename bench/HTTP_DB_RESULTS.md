# NURL HTTP + database peer-comparison

Generated `2026-11-19T10:06:18Z` by `bench/run_http.sh --suite db`. **Do not edit by hand** — the next run overwrites it.

The endpoints a service puts in front of a database — TechEmpower's five tests and HttpArena's `async-db` profile — served by `bench/http_server.nu` (the `packages/http` HttpApp facade in `http_app_async` mode, the database through `packages/psql`: one connection that every fiber's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `pg_query_many`) and by the Rust peer `bench/rust_http_server` (hyper on tokio's multi-thread runtime, the database through `tokio-postgres`: one client every task's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `try_join_all`). Both serve the same bytes (`bench/http_db_schema.sql`: 10 000 `world` rows, TechEmpower's 12 fortunes, 100 000 `items`, deterministic), and every endpoint is checked on both before a request is timed. Node has no database peer here.

**`CPU us/req` is the column to compare.** Server CPU time (`utime+stime` over every thread, read from `/proc/<pid>/stat` around the measured window) divided by the exact number of responses: what one request costs the server, whoever is the bottleneck. `req/s` here is often the database's ceiling rather than the server's — the database has cores of its own, one backend per connection — so two servers can show the same `req/s` at very different costs. The latency columns are closed-loop, as in `HTTP_RESULTS.md` (‡ = fewer connections in flight than offered, by Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `e15ed57f998cbc8deb360fef791281fe77b5e588` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/44499612820 |
| NURL | `v0.92.1-82-ge15ed57f` |
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
| Machine load | 1.85 at start (quiet) |

## Endpoint check

Before any timing: `/json`; `/db`; `/queries` with 20, 0, `foo` and 501 (→ 20, 1, 1, 500 rows); `/fortunes` (13 rows, the `<script>` row escaped, the added row present, byte order); `/updates?queries=5`; `/async-db?min=10&max=50&limit=5` (5 items in range, `tags` a list, `rating` an object).

| Server | Check |
|---|---|
| NURL | passed |
| Rust | passed |

## At a glance: server CPU per request

| Endpoint | NURL C=64 | Rust C=64 | NURL/Rust | NURL C=256 | Rust C=256 | NURL/Rust |
|---|---:|---:|---:|---:|---:|---:|
| `/json` | 11.72 | 11.97 | 0.98 | 12.08 | 12.46 | 0.97 |
| `/db` | 26.03 | 24.56 | 1.06 | 27.86 | 23.41 | 1.19 |
| `/queries?queries=20` | 186.10 | 183.11 | 1.02 | 230.72 | 188.90 | 1.22 |
| `/fortunes` | 29.28 | 27.97 | 1.05 | 28.60 | 27.23 | 1.05 |
| `/updates?queries=20` | 237.80 | 182.11 | 1.31 | 279.14 | 191.74 | 1.46 |
| `/async-db?limit=50` | 84.15 | 57.45 | 1.46 | 89.97 | 59.75 | 1.51 |

(µs of server CPU per request; NURL/Rust below 1 means NURL spends less.)

## 1. `/json`

A `{"message":"hello, world!"}` object serialised per request — no database.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 104 350 | **97 334** |
|              | Rust    | **104 406** | 94 349 |
| **p50 (ms)** | NURL    | **0.27** | **1.49** |
|              | Rust    | 0.28 | 1.56 |
| **p99 (ms)** | NURL    | **3.41** | **4.68** |
|              | Rust    | 3.44 | 4.84 |
| **CPU us/req** | NURL    | **11.72** | **12.08** |
|              | Rust    | 11.97 | 12.46 |

## 2. `/db`

One random `world` row by primary key, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 67 157 | 58 782 |
|              | Rust    | **67 221** | **60 771** |
| **p50 (ms)** | NURL    | **0.48** | 5.06 |
|              | Rust    | **0.48** | **4.97** |
| **p99 (ms)** | NURL    | 3.59 | 6.05 |
|              | Rust    | **3.58** | **5.78** |
| **CPU us/req** | NURL    | 26.03 | 27.86 |
|              | Rust    | **24.56** | **23.41** |

## 3. `/queries?queries=20`

N random `world` rows, one query each — all n sent together — as a json array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 4 572 | **4 669** |
|              | Rust    | **4 597** | 4 583 |
| **p50 (ms)** | NURL    | 13.97 | **54.93** |
|              | Rust    | **13.87** | 55.81 |
| **p99 (ms)** | NURL    | 15.38 | **57.42** |
|              | Rust    | **15.21** | 59.73 |
| **CPU us/req** | NURL    | 186.10 | 230.72 |
|              | Rust    | **183.11** | **188.90** |

## 4. `/fortunes`

Every `fortune` row plus one added at request time, sorted by message, as an escaped html table.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 62 914 | 65 205 |
|              | Rust    | **64 488** | **66 306** |
| **p50 (ms)** | NURL    | 0.98 | 3.86 |
|              | Rust    | **0.95** | **3.80** |
| **p99 (ms)** | NURL    | **1.57** | 5.95 |
|              | Rust    | 1.76 | **5.89** |
| **CPU us/req** | NURL    | 29.28 | 28.60 |
|              | Rust    | **27.97** | **27.23** |

## 5. `/updates?queries=20`

N random `world` rows read one query each, each given a new random number, written back by one `update … from unnest(…)`, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 3 104 | 3 275 |
|              | Rust    | **3 284** | **3 288** |
| **p50 (ms)** | NURL    | 20.53 | 78.28 |
|              | Rust    | **19.41** | **77.94** |
| **p99 (ms)** | NURL    | 23.60 | 84.36 |
|              | Rust    | **21.64** | **81.50** |
| **CPU us/req** | NURL    | 237.80 | 279.14 |
|              | Rust    | **182.11** | **191.74** |

## 6. `/async-db?limit=50`

Up to `limit` `items` rows with `price between min and max` (no index: a scan), as `{"items":[…],"count":n}` with a nested `rating` and a jsonb `tags` array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **10 009** | **10 031** |
|              | Rust    | 9 152 | 9 177 |
| **p50 (ms)** | NURL    | **6.39** | **25.50** |
|              | Rust    | 6.97 | 27.93 |
| **p99 (ms)** | NURL    | **6.64** | **27.14** |
|              | Rust    | 7.43 | 28.38 |
| **CPU us/req** | NURL    | 84.15 | 89.97 |
|              | Rust    | **57.45** | **59.75** |

(Best per row in **bold**; latency winners only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server failed its check or did not complete the cell.)

## Notes

- **One database connection per server**, pipelined — the shape both drivers are built for, and one PostgreSQL backend (one core) behind each server. A server that is cheaper per request than the database can keep up with shows it in `CPU us/req`, not in `req/s`.
- **`/updates`** reads its rows one query each (as TechEmpower requires) and writes them back in one statement, ids sorted so two requests touching the same rows lock them in the same order.
- **Against HttpArena's profiles.** `async-db` here has HttpArena's query, parameters, clamping and response shape over synthetic data of the same schema; HttpArena's `fortunes` has 200 rows where TechEmpower's (used here) has 12, so its pages are 15–30x larger.
- Loopback only, HTTP/1.1, plaintext to the database. Compare columns within one run, not across machines.
