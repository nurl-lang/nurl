# NURL HTTP + database peer-comparison

Generated `2026-11-26T22:14:31Z` by `bench/run_http.sh --suite db`. **Do not edit by hand** — the next run overwrites it.

The endpoints a service puts in front of a database — TechEmpower's five tests and HttpArena's `async-db` profile — served by `bench/http_server.nu` (the `packages/http` HttpApp facade in `http_app_async` mode, the database through `packages/psql`: one connection that every fiber's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `pg_query_many`) and by the Rust peer `bench/rust_http_server` (hyper on tokio's multi-thread runtime, the database through `tokio-postgres`: one client every task's queries are pipelined on, statements prepared once, and the N queries of one `/queries` or `/updates` request sent together with `try_join_all`). Both serve the same bytes (`bench/http_db_schema.sql`: 10 000 `world` rows, TechEmpower's 12 fortunes, 100 000 `items`, deterministic), and every endpoint is checked on both before a request is timed. Node has no database peer here.

**`CPU us/req` is the column to compare.** Server CPU time (`utime+stime` over every thread, read from `/proc/<pid>/stat` around the measured window) divided by the exact number of responses: what one request costs the server, whoever is the bottleneck. `req/s` here is often the database's ceiling rather than the server's — the database has cores of its own, one backend per connection — so two servers can show the same `req/s` at very different costs. The latency columns are closed-loop, as in `HTTP_RESULTS.md` (‡ = fewer connections in flight than offered, by Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1018-aws x86_64` |
| CPU | Intel(R) Xeon(R) 6975P-C (4 logical cores) |
| Memory | 16077528 KiB |
| Commit | `986339c9f1d1a3b3cd6d7ed4a5b4d1191a490e30` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/45901383287 |
| NURL | `v0.95.0-8-g986339c9f` |
| Rust | rustc 1.100.0 (0ef1bc386 2026-11-09) |
| Load generator | oha 1.8.0 |
| Database | throwaway PostgreSQL 18.7 (Ubuntu 18.7-1.pgdg26.04+5) on cores `2-2` (`taskset`), durability off |

| Setting | Value |
|---|---|
| Each cell | median of 3 x 10 s closed-loop runs, keep-alive; both servers up for the whole run, their cells alternating (NURL's, then Rust's, per path and concurrency) so a noisy stretch of a shared machine lands on both |
| Concurrencies | 64 , 256 |
| Core isolation | server on cores `0-1`, generator on cores `3-3` (`taskset`); the database as above |
| Worker threads | 2 per server (`NURL_WORKERS` / `TOKIO_WORKER_THREADS`) |
| CPU steal | 0.00 % of the machine's time over the measured cells (a VM's host taking its cores back) |
| Machine load | 1.89 at start (quiet) |

## Endpoint check

Before any timing: `/json`; `/db`; `/queries` with 20, 0, `foo` and 501 (→ 20, 1, 1, 500 rows); `/fortunes` (13 rows, the `<script>` row escaped, the added row present, byte order); `/updates?queries=5`; `/async-db?min=10&max=50&limit=5` (5 items in range, `tags` a list, `rating` an object).

| Server | Check |
|---|---|
| NURL | passed |
| Rust | passed |

## At a glance: server CPU per request

| Endpoint | NURL C=64 | Rust C=64 | NURL/Rust | NURL C=256 | Rust C=256 | NURL/Rust |
|---|---:|---:|---:|---:|---:|---:|
| `/json` | 7.68 | 7.57 | 1.01 | 7.92 | 8.26 | 0.96 |
| `/db` | 16.63 | 16.18 | 1.03 | 16.19 | 15.02 | 1.08 |
| `/queries?queries=20` | 134.95 | 146.50 | 0.92 | 215.81 | 152.01 | 1.42 |
| `/fortunes` | 19.23 | 18.68 | 1.03 | 19.63 | 18.58 | 1.06 |
| `/updates?queries=20` | 181.10 | 144.27 | 1.26 | 218.90 | 150.83 | 1.45 |
| `/async-db?limit=50` | 72.43 | 51.56 | 1.40 | 73.42 | 56.54 | 1.30 |

(µs of server CPU per request; NURL/Rust below 1 means NURL spends less.)

## 1. `/json`

A `{"message":"hello, world!"}` object serialised per request — no database.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **146 183** | **124 734** |
|              | Rust    | 142 900 | 121 214 |
| **p50 (ms)** | NURL    | **0.20** | **1.00** |
|              | Rust    | **0.20** | 1.03 |
| **p99 (ms)** | NURL    | **3.31** | **4.27** |
|              | Rust    | 3.32 | 4.31 |
| **CPU us/req** | NURL    | 7.68 | **7.92** |
|              | Rust    | **7.57** | 8.26 |

## 2. `/db`

One random `world` row by primary key, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 113 780 | 113 098 |
|              | Rust    | **114 076** | **114 782** |
| **p50 (ms)** | NURL    | 0.55 | **2.06** |
|              | Rust    | **0.54** | **2.06** |
| **p99 (ms)** | NURL    | **0.85** | **4.87** |
|              | Rust    | 1.06 | 5.09 |
| **CPU us/req** | NURL    | 16.63 | 16.19 |
|              | Rust    | **16.18** | **15.02** |

## 3. `/queries?queries=20`

N random `world` rows, one query each — all n sent together — as a json array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | **6 745** | 6 145 |
|              | Rust    | 6 392 | **6 324** |
| **p50 (ms)** | NURL    | **9.49** | 41.80 |
|              | Rust    | 10.02 | **40.61** |
| **p99 (ms)** | NURL    | **9.93** | 42.54 |
|              | Rust    | 10.26 | **41.18** |
| **CPU us/req** | NURL    | **134.95** | 215.81 |
|              | Rust    | 146.50 | **152.01** |

## 4. `/fortunes`

Every `fortune` row plus one added at request time, sorted by message, as an escaped html table.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 102 244 | 100 120 |
|              | Rust    | **104 140** | **104 290** |
| **p50 (ms)** | NURL    | 0.62 | 2.53 |
|              | Rust    | **0.61** | **2.43** |
| **p99 (ms)** | NURL    | **0.83** | **3.66** |
|              | Rust    | 0.92 | 4.36 |
| **CPU us/req** | NURL    | 19.23 | 19.63 |
|              | Rust    | **18.68** | **18.58** |

## 5. `/updates?queries=20`

N random `world` rows read one query each, each given a new random number, written back by one `update … from unnest(…)`, as json.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 4 243 | 4 465 |
|              | Rust    | **4 633** | **4 686** |
| **p50 (ms)** | NURL    | 15.04 | 57.36 |
|              | Rust    | **13.81** | **54.81** |
| **p99 (ms)** | NURL    | 16.12 | 61.32 |
|              | Rust    | **15.02** | **58.59** |
| **CPU us/req** | NURL    | 181.10 | 218.90 |
|              | Rust    | **144.27** | **150.83** |

## 6. `/async-db?limit=50`

Up to `limit` `items` rows with `price between min and max` (no index: a scan), as `{"items":[…],"count":n}` with a nested `rating` and a jsonb `tags` array.

|              | Server  | C = 64 | C = 256 |
|--------------|---------|--------:|--------:|
| **req/s**    | NURL    | 13 931 | 14 006 |
|              | Rust    | **15 422** | **14 929** |
| **p50 (ms)** | NURL    | 4.59 | 18.29 |
|              | Rust    | **4.04** | **17.26** |
| **p99 (ms)** | NURL    | **4.72** | 18.65 |
|              | Rust    | 4.98 | **18.53** |
| **CPU us/req** | NURL    | 72.43 | 73.42 |
|              | Rust    | **51.56** | **56.54** |

(Best per row in **bold**; latency winners only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server failed its check or did not complete the cell.)

## Notes

- **One database connection per server**, pipelined — the shape both drivers are built for, and one PostgreSQL backend (one core) behind each server. A server that is cheaper per request than the database can keep up with shows it in `CPU us/req`, not in `req/s`.
- **`/updates`** reads its rows one query each (as TechEmpower requires) and writes them back in one statement, ids sorted so two requests touching the same rows lock them in the same order.
- **Against HttpArena's profiles.** `async-db` here has HttpArena's query, parameters, clamping and response shape over synthetic data of the same schema; HttpArena's `fortunes` has 200 rows where TechEmpower's (used here) has 12, so its pages are 15–30x larger.
- Loopback only, HTTP/1.1, plaintext to the database. Compare columns within one run, not across machines.
