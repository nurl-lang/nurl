# NURL HTTP + database peer-comparison

Generated `2026-11-25T10:07:35Z` by `bench/run_http.sh --suite db`. **Do not edit by hand** — the next run overwrites it.

The endpoints a service puts in front of a database — TechEmpower's five tests and HttpArena's `async-db` profile — served by `bench/http_server.nu` (the `packages/http` HttpApp facade in `http_app_async` mode, the database through `packages/psql`: one connection that every fiber's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `pg_query_many`) and by the Rust peer `bench/rust_http_server` (hyper on tokio's multi-thread runtime, the database through `tokio-postgres`: one client every task's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `try_join_all`). Both serve the same bytes (`bench/http_db_schema.sql`: 10 000 `world` rows, TechEmpower's 12 fortunes, 100 000 `items`, deterministic), and every endpoint is checked on both before a request is timed. Node has no database peer here.

**`CPU us/req` is the column to compare.** Server CPU time (`utime+stime` over every thread, read from `/proc/<pid>/stat` around the measured window) divided by the exact number of responses: what one request costs the server, whoever is the bottleneck. `req/s` here is often the database's ceiling rather than the server's — the database has cores of its own, one backend per connection — so two servers can show the same `req/s` at very different costs. The latency columns are closed-loop, as in `HTTP_RESULTS.md` (‡ = fewer connections in flight than offered, by Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1016-aws x86_64` |
| CPU | Intel(R) Xeon(R) 6975P-C (4 logical cores) |
| Memory | 16077548 KiB |
| Commit | `c46fd726f851b3938d5fbdea2c3dc3edabd20edf` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/45588846151 |
| NURL | `v0.94.0-88-gc46fd726f` |
| Rust | rustc 1.100.0 (0ef1bc386 2026-11-09) |
| Load generator | oha 1.8.0 |
| Database | throwaway PostgreSQL 18.7 (Ubuntu 18.7-1.pgdg26.04+2) on cores `2-2` (`taskset`), durability off |

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
| `/json` | 7.79 | 7.64 | 1.02 | 8.05 | 8.23 | 0.98 |
| `/db` | 16.56 | 16.07 | 1.03 | 15.92 | 14.83 | 1.07 |
| `/queries?queries=20` | 132.23 | 138.62 | 0.95 | 205.55 | 143.32 | 1.43 |
| `/fortunes` | 18.71 | 18.38 | 1.02 | 18.66 | 18.07 | 1.03 |
| `/updates?queries=20` | 181.03 | 141.79 | 1.28 | 221.33 | 152.57 | 1.45 |
| `/async-db?limit=50` | 70.37 | 51.90 | 1.36 | 73.36 | 52.00 | 1.41 |

(µs of server CPU per request; NURL/Rust below 1 means NURL spends less.)

## 1. `/json`

A `{"message":"hello, world!"}` object serialised per request — no database.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **145 719** | **123 738** |
|              | Rust    | 143 023 | 123 180 |
| **p50 (ms)** | NURL    | **0.20** | **1.01** |
|              | Rust    | **0.20** | 1.02 |
| **p99 (ms)** | NURL    | **3.31** | **4.29** |
|              | Rust    | 3.32 | **4.29** |
| **CPU us/req** | NURL    | 7.79 | **8.05** |
|              | Rust    | **7.64** | 8.23 |

## 2. `/db`

One random `world` row by primary key, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **115 253** | 115 426 |
|              | Rust    | 114 642 | **115 956** |
| **p50 (ms)** | NURL    | **0.54** | 2.14 |
|              | Rust    | **0.54** | **2.13** |
| **p99 (ms)** | NURL    | **0.77** | **4.85** |
|              | Rust    | 0.79 | 5.10 |
| **CPU us/req** | NURL    | 16.56 | 15.92 |
|              | Rust    | **16.07** | **14.83** |

## 3. `/queries?queries=20`

N random `world` rows, one query each — all n sent together — as a json array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **6 801** | 6 267 |
|              | Rust    | 6 457 | **6 476** |
| **p50 (ms)** | NURL    | **9.40** | 40.94 |
|              | Rust    | 9.91 | **39.61** |
| **p99 (ms)** | NURL    | **9.85** | 42.79 |
|              | Rust    | 10.28 | **40.99** |
| **CPU us/req** | NURL    | **132.23** | 205.55 |
|              | Rust    | 138.62 | **143.32** |

## 4. `/fortunes`

Every `fortune` row plus one added at request time, sorted by message, as an escaped html table.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 105 227 | 105 286 |
|              | Rust    | **105 417** | **106 998** |
| **p50 (ms)** | NURL    | **0.60** | 2.39 |
|              | Rust    | **0.60** | **2.37** |
| **p99 (ms)** | NURL    | **0.81** | **3.83** |
|              | Rust    | 0.92 | 4.28 |
| **CPU us/req** | NURL    | 18.71 | 18.66 |
|              | Rust    | **18.38** | **18.07** |

## 5. `/updates?queries=20`

N random `world` rows read one query each, each given a new random number, written back by one `update … from unnest(…)`, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 4 255 | 4 429 |
|              | Rust    | **4 633** | **4 681** |
| **p50 (ms)** | NURL    | 14.98 | 57.76 |
|              | Rust    | **13.85** | **54.91** |
| **p99 (ms)** | NURL    | 16.25 | 62.47 |
|              | Rust    | **15.19** | **57.85** |
| **CPU us/req** | NURL    | 181.03 | 221.33 |
|              | Rust    | **141.79** | **152.57** |

## 6. `/async-db?limit=50`

Up to `limit` `items` rows with `price between min and max` (no index: a scan), as `{"items":[…],"count":n}` with a nested `rating` and a jsonb `tags` array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 14 084 | 14 012 |
|              | Rust    | **15 114** | **15 405** |
| **p50 (ms)** | NURL    | 4.54 | 18.28 |
|              | Rust    | **4.23** | **16.54** |
| **p99 (ms)** | NURL    | **4.68** | **18.62** |
|              | Rust    | 4.94 | 19.34 |
| **CPU us/req** | NURL    | 70.37 | 73.36 |
|              | Rust    | **51.90** | **52.00** |

(Best per row in **bold**; latency winners only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server failed its check or did not complete the cell.)

## Notes

- **One database connection per server**, pipelined — the shape both drivers are built for, and one PostgreSQL backend (one core) behind each server. A server that is cheaper per request than the database can keep up with shows it in `CPU us/req`, not in `req/s`.
- **`/updates`** reads its rows one query each (as TechEmpower requires) and writes them back in one statement, ids sorted so two requests touching the same rows lock them in the same order.
- **Against HttpArena's profiles.** `async-db` here has HttpArena's query, parameters, clamping and response shape over synthetic data of the same schema; HttpArena's `fortunes` has 200 rows where TechEmpower's (used here) has 12, so its pages are 15–30x larger.
- Loopback only, HTTP/1.1, plaintext to the database. Compare columns within one run, not across machines.
