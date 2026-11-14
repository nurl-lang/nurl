# NURL HTTP + database peer-comparison

Generated `2026-11-14T05:05:02Z` by `bench/run_http.sh --suite db`. **Do not edit by hand** — the next run overwrites it.

The endpoints a service puts in front of a database — TechEmpower's five tests and HttpArena's `async-db` profile — served by `bench/http_server.nu` (the `packages/http` HttpApp facade in `http_app_async` mode, the database through `packages/psql`: one connection that every fiber's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `pg_query_many`) and by the Rust peer `bench/rust_http_server` (hyper on tokio's multi-thread runtime, the database through `tokio-postgres`: one client every task's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `try_join_all`). Both serve the same bytes (`bench/http_db_schema.sql`: 10 000 `world` rows, TechEmpower's 12 fortunes, 100 000 `items`, deterministic), and every endpoint is checked on both before a request is timed. Node has no database peer here.

**`CPU us/req` is the column to compare.** Server CPU time (`utime+stime` over every thread, read from `/proc/<pid>/stat` around the measured window) divided by the exact number of responses: what one request costs the server, whoever is the bottleneck. `req/s` here is often the database's ceiling rather than the server's — the database has cores of its own, one backend per connection — so two servers can show the same `req/s` at very different costs. The latency columns are closed-loop, as in `HTTP_RESULTS.md` (‡ = fewer connections in flight than offered, by Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366632 KiB |
| Commit | `ede65cf52ce96593ff73d62343a11d24a1a5081d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43558112811 |
| NURL | `v0.91.1-118-gede65cf5` |
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
| Machine load | 1.72 at start (quiet) |

## Endpoint check

Before any timing: `/json`; `/db`; `/queries` with 20, 0, `foo` and 501 (→ 20, 1, 1, 500 rows); `/fortunes` (13 rows, the `<script>` row escaped, the added row present, byte order); `/updates?queries=5`; `/async-db?min=10&max=50&limit=5` (5 items in range, `tags` a list, `rating` an object).

| Server | Check |
|---|---|
| NURL | passed |
| Rust | passed |

## At a glance: server CPU per request

| Endpoint | NURL C=64 | Rust C=64 | NURL/Rust | NURL C=256 | Rust C=256 | NURL/Rust |
|---|---:|---:|---:|---:|---:|---:|
| `/json` | 16.73 | 17.45 | 0.96 | 15.91 | 16.63 | 0.96 |
| `/db` | 45.56 | 45.43 | 1.00 | 46.55 | 44.89 | 1.04 |
| `/queries?queries=20` | 281.95 | 260.38 | 1.08 | 326.85 | 280.82 | 1.16 |
| `/fortunes` | 46.69 | 47.84 | 0.98 | 47.23 | 46.48 | 1.02 |
| `/updates?queries=20` | 382.82 | 281.61 | 1.36 | 400.97 | 282.08 | 1.42 |
| `/async-db?limit=50` | 120.62 | 86.53 | 1.39 | 121.69 | 89.78 | 1.36 |

(µs of server CPU per request; NURL/Rust below 1 means NURL spends less.)

## 1. `/json`

A `{"message":"hello, world!"}` object serialised per request — no database.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **84 268** | **85 829** |
|              | Rust    | 84 201 | 85 228 |
| **p50 (ms)** | NURL    | **0.42** | **1.89** |
|              | Rust    | **0.42** | 2.41 |
| **p99 (ms)** | NURL    | 3.49 | 5.01 |
|              | Rust    | **3.48** | **4.97** |
| **CPU us/req** | NURL    | **16.73** | **15.91** |
|              | Rust    | 17.45 | 16.63 |

## 2. `/db`

One random `world` row by primary key, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **33 697** | 33 521 |
|              | Rust    | 33 235 | **33 909** |
| **p50 (ms)** | NURL    | **1.89** | 7.64 |
|              | Rust    | 1.91 | **7.57** |
| **p99 (ms)** | NURL    | 2.36 | 8.76 |
|              | Rust    | **2.25** | **8.66** |
| **CPU us/req** | NURL    | 45.56 | 46.55 |
|              | Rust    | **45.43** | **44.89** |

## 3. `/queries?queries=20`

N random `world` rows, one query each — all n sent together — as a json array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **2 572** | **2 652** |
|              | Rust    | 2 474 | 2 509 |
| **p50 (ms)** | NURL    | **24.87** | **96.70** |
|              | Rust    | 25.86 | 102.69 |
| **p99 (ms)** | NURL    | **26.87** | **101.53** |
|              | Rust    | 27.57 | 105.76 |
| **CPU us/req** | NURL    | 281.95 | 326.85 |
|              | Rust    | **260.38** | **280.82** |

## 4. `/fortunes`

Every `fortune` row plus one added at request time, sorted by message, as an escaped html table.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **37 082** | **37 692** |
|              | Rust    | 35 244 | 35 832 |
| **p50 (ms)** | NURL    | **1.70** | **6.74** |
|              | Rust    | 1.80 | 7.14 |
| **p99 (ms)** | NURL    | **2.17** | 8.31 |
|              | Rust    | **2.17** | **8.11** |
| **CPU us/req** | NURL    | **46.69** | 47.23 |
|              | Rust    | 47.84 | **46.48** |

## 5. `/updates?queries=20`

N random `world` rows read one query each, each given a new random number, written back by one `update … from unnest(…)`, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 1 843 | **1 996** |
|              | Rust    | **1 868** | 1 895 |
| **p50 (ms)** | NURL    | 34.63 | **128.89** |
|              | Rust    | **34.22** | 134.87 |
| **p99 (ms)** | NURL    | **38.24** | **140.36** |
|              | Rust    | 38.78 | 143.95 |
| **CPU us/req** | NURL    | 382.82 | 400.97 |
|              | Rust    | **281.61** | **282.08** |

## 6. `/async-db?limit=50`

Up to `limit` `items` rows with `price between min and max` (no index: a scan), as `{"items":[…],"count":n}` with a nested `rating` and a jsonb `tags` array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **6 702** | **6 679** |
|              | Rust    | 6 201 | 6 206 |
| **p50 (ms)** | NURL    | **9.54** | **38.34** |
|              | Rust    | 10.30 | 41.25 |
| **p99 (ms)** | NURL    | **10.17** | **39.44** |
|              | Rust    | 10.65 | 42.46 |
| **CPU us/req** | NURL    | 120.62 | 121.69 |
|              | Rust    | **86.53** | **89.78** |

(Best per row in **bold**; latency winners only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server failed its check or did not complete the cell.)

## Notes

- **One database connection per server**, pipelined — the shape both drivers are built for, and one PostgreSQL backend (one core) behind each server. A server that is cheaper per request than the database can keep up with shows it in `CPU us/req`, not in `req/s`.
- **`/updates`** reads its rows one query each (as TechEmpower requires) and writes them back in one statement, ids sorted so two requests touching the same rows lock them in the same order.
- **Against HttpArena's profiles.** `async-db` here has HttpArena's query, parameters, clamping and response shape over synthetic data of the same schema; HttpArena's `fortunes` has 200 rows where TechEmpower's (used here) has 12, so its pages are 15–30x larger.
- Loopback only, HTTP/1.1, plaintext to the database. Compare columns within one run, not across machines.
