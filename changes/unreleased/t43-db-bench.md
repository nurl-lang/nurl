### Added

- **The HTTP peer benchmark measures the database endpoints** (Agora #43). `bench/run_http.sh --suite db` runs TechEmpower's five tests (`/json`, `/db`, `/queries`, `/fortunes`, `/updates`) and HttpArena's `async-db` profile against PostgreSQL — `bench/http_server.nu` over `packages/psql` against hyper + `tokio-postgres`, every endpoint checked on both before a request is timed, with the plaintext suite's lock, pinning and CPU-per-request method — and writes `bench/HTTP_DB_RESULTS.md`. Without `DATABASE_URL` it starts a throwaway cluster of its own, pinned to cores the server and the generator do not use.
- **psql `pg_connect_url`** — a connection from a `postgres://` URI (`DATABASE_URL`), anything it cannot honour refused as `PgBadUrl` — and **`pg_query_many`**: one statement, N parameter sets, every run in one write and one round trip.

### Performance

- **psql hands over every answer a read brought, and allocates about seven times less per query** (Agora #43). On the bench's `/db` (two workers, loopback PostgreSQL 16) 55k → 86k requests/s and 30.5 → 19.8 µs of server CPU per request, against hyper + tokio-postgres' 19.1; `/queries?queries=20` 315 → 218 µs (Rust: 215) with `pg_query_many`. One connection shared by fibers on two workers: 39–44k → 69–118k queries/s. (On a single worker the server becomes the bottleneck and the one-connection bench reads 93–110k where it read 117–145k: the server spends more per query when its client idles between batches — see packages/psql/CHANGELOG.md.)
