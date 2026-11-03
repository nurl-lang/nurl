### Changed

- **wasmbuilder 0.3.8** and **nurl-mcp 0.14.2** are published.
  wasmbuilder's WASI lowering already replaced the `nurl_cpu_x86_v4()`
  probe (Agora #227), but that change had no version bump, so nurl-mcp,
  which depends on wasmbuilder by path, could not be published with
  v0.86.0. Published with v0.86.0 too: http 0.7.10, http-client 0.3.7,
  nurldb 0.2.0, psql 0.6.0 and redis 0.3.7, which were in earlier
  releases' trees but never uploaded.
