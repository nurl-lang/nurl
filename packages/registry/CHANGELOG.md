# Changelog

## [0.5.0] — 2026-10-28

### Added

- Every accepted publish is signed by the registry before its database rows
  become visible, and the detached signature is stored beside the tarball.
  `registry serve` fails fast unless `REG_SIGNING_SEED_HEX` is a 32-byte
  Ed25519 seed and `REG_SIGNING_KEY_ID_HEX` is an 8-byte minisign key id; it
  prints the corresponding public trust payload at startup.

## [0.4.8] — 2026-10-28

### Added

- Detached minisign files can be stored beside immutable package tarballs and
  fetched from `GET /pkgs/<name>/<name>-<version>.tar.gz.minisig`. The route
  applies the same validated package/version path construction as tarballs,
  returns 404 for an absent sidecar, and is immutable-cacheable.

## [0.4.7] — 2026-10-21

### Fixed

- Installable as a dependency: the sources in `src/` imported their siblings as
  `src/<name>.nu`, which resolves only with the package root as the working
  directory, not under a consumer's `deps/registry/`. They are written relative to
  the importing file (`<name>.nu`) now, which resolves in both layouts.

## [0.4.6] — 2026-10-20

### Added

- **`GET /api/v1/catalog`** — every package as `/api/v1/search` returns
  them (name, latest version, description), in name order, unlimited. A
  client that holds it answers its own searches with no round trip per
  term (the production Worker serves the same route, with its symbol
  index).

## [0.4.5] — 2026-10-10

Requires NURL 0.72.0 (`slice_of_str`). Loops that walked a string with
`nurl_str_get` — which measures the string from its start on every call,
so a scan is quadratic in the string's length, and nurlc 0.72 warns
about the shape — read through a view measured once (`slice_of_str` +
`slice_byte`). No change in behaviour.

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
