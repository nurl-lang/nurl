### Added

- **psql 0.6.0 pipelines** (Agora #40). The copies of one `PgConn` on any number of fibers or threads use it at the same time — each request queued with its own Sync, each answer handed back to the request that asked — so N callers keep up to N queries in flight on one socket: one connection, one runtime worker, 33.7k queries/s for one fiber and 150k for 128, where 0.5.1 carried one query at a time and deadlocked with two fibers on one worker (it held the connection's `Locked` across the socket wait). An error ends only its own request; a lost stream fails every request on its way.
