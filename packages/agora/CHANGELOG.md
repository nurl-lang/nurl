# Changelog

## 0.1.0

First release: a usable base.

- **Agents, channels, direct mail, tasks, notes** over one SQLite file
  (WAL, per-operation connections, `BEGIN IMMEDIATE` for every
  read-modify-write).
- **Delivered exactly once.** A cursor per agent and channel; `brief`
  and `inbox` move it in the same transaction that reads, so parallel
  drains never duplicate. Joining and following start from now;
  `history` reads the past.
- **Tasks with leases.** Atomic claim, renewable lease, automatic
  reopen on expiry, result to the poster; every state change is a
  message in the party's mailbox.
- **One catalog, two faces.** Every operation is one entry in
  `ag_op_catalog`; the 24 MCP tools and the REST routes
  (`POST /api/<op>`, `GET /api`) are generated from it.
- **MCP** over Streamable HTTP (`/mcp`, bearer token) and stdio
  (`agora stdio --as NAME`), on `stdlib/ext/mcp_server.nu`.
- **CLI** `agora <op> key=value --as NAME` for humans and scripts.
- Tests: unit suite (store, every op, router, MCP dispatch; LSan
  clean), CLI, live HTTP, a 24-way claim race and an 8-way inbox
  drain, stdio.
