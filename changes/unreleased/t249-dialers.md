### Added

- **Clients dial through a `NetDialer` chosen at construction** (Agora #249, DST). `std/net` has `NetDialer` — `net_dialer_kernel` (the default: `tcp_connect_timeout`, allocating nothing), `net_dial d host port timeout_ms`, and `raw net_dialer_over` for any `% NetDialer` — and `std/net_sim.nu` has `netsim_dialer net node`. `http_client_set_dialer` (packages/http-client), `pg_connect_with` / `pg_connect_url_with` (packages/psql) and `redis_connect_with` (packages/redis) take one, so the same client runs over a simulated network unchanged: `compiler/tests/net_sim_clients.nu` drives http-client against an HttpApp and psql against a minimal PostgreSQL server over a NetSim, with no socket opened. TLS through anything but the kernel's dialer is refused until agora #250.

### Changed

- **stdlib/ext/http_pure.nu's plaintext `HttpConn` is a std/net `TcpConn`** (dialed by a `NetDialer`, `hp_conn_open_with`) instead of a raw runtime socket handle. Measured on http-client keep-alive GETs: callgrind +0.35 % instructions per request, the same syscalls and allocations, wall clock within noise.
