# Changelog

## [0.4.4] — 2026-10-03

Nothing is released by hand any more. No change to the routes, the wire
format or the CLI.

### Changed

- The registry holds no pointer state — its records are plain values
  (Strings, Vecs, Json, SQLite handles) the compiler drops — so every
  `string_free` / `vec_free` / `json_free` / `args_free` / `semver_free` in
  the server, the CLI and the wire test is removed (393 calls). A reassigned
  binding drops what it held, so `( string_free x ) = x …` became `= x …`.
  Same status codes and bodies for every route; instructions:u for the wire
  test and a served workload (publish, every page, yank/unyank, error paths)
  +0.03 to +0.05 %.
- Serves through http 0.7's self-releasing `HttpApp` handle and renders
  through template's self-releasing `TplSet` handle (requires http ^0.7 and
  the matching template release).

Requires NURL 0.69.0.

## 0.4.3

`reg_name_valid` moved to the standard library.

The package name rule — `^[a-z0-9][a-z0-9_-]{0,63}$` — is now
`stdlib/ext/registry_id.nu`, so the registry service and `nurlpkg` apply one
copy of it rather than two that can drift. The check itself is unchanged.
This landed with the toolchain's ownership hardening (#1107) and the package
was never republished, so the registry has been serving 0.4.2 with different
source ever since.
