### Added

- **A server can crash and restart inside one process** (Agora #262, DST 4/4 — the database half). `std/net_sim.nu`'s **`netsim_crash net node`** takes a node down and straight back up, empty, as a host that lost power and rebooted: every socket it had is gone at once with no FIN, so an operation through one finds it closed, its peers learn of it by a reset or their own timeouts, and the node can listen again at once. packages/nurldb's **`serve_on db listener`** serves a listener it is handed (a NetSim node's too) and returns once the listener stops accepting and its connections have ended; **`client_connect_with dialer host port`** dials through a std/net `NetDialer`; **`db_crash db`** drops a database as a killed process leaves it (no checkpoint, dirty pages lost), so reopening its directory recovers from the log. `compiler/tests/net_sim_nurldb_crash.nu`: committed rows survive a crash-restart, a transaction left open does not, the client's next statement fails instead of hanging, and the rebooted node serves on the same port.

### Changed

- packages/nurldb's checkpointer takes no last checkpoint when its server stops: what is committed is in the log, and recovery replays it.
