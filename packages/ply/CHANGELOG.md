# Changelog

## [0.3.5] — 2026-10-14

Requires NURL 0.73.0 (grammar v2.9 `raw`, `slice_window`, `file_is_open`).

### Changed

- The writer keeps its state in a `Locked`, closes its file once (`file_is_open`, NURL 0.73.0) instead of replacing it with a made-up null `File`, and the viewer reads its page through `arc_get`. No function is `unsafe` any more.
- 12 fewer functions are `unsafe` than in 0.3.4 (0 left).

## [0.3.4] — 2026-10-12

Requires NURL 0.73.0, in which a field written through a raw pointer
drops what it held, a mutable module global may own a `String`, a `Vec`
or a handle, and a foreign function may take an `inout` parameter.
The published 0.3.3 does not compile under it.

### Changed

- The zero `File` handle a writer keeps until one is opened is built
  with the cast `# File # s 0`: a standard-library handle now holds its
  state in a `( Shared T )`.
- A replaced field is dropped by the store; the `mem_take` before it is
  gone.

## [0.3.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.3.2 does not compile under it.

### Changed

- `PlyW` and `VwState` keep their state in an `Arc` (stdlib/std/arc.nu)
  instead of an `rcbox`. The share and drop hooks are ordinary safe
  functions — the Arc does the counting — and so are the constructors that
  build one from a whole value; every copy is still the same state, and
  its last owner releases it.
- 2 fewer functions are `unsafe` than in 0.3.2.
- Its `--version` (or the version it reports) is read from `nurl.toml`
  with `( pkg_version )` instead of being written by hand, so it can no
  longer drift from the manifest.

## [0.3.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.3.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. Bytes of a string are read through a bounds-checked
`Slice` of it (`slice_of_str`, `slice_byte`), where `nurl_str_at`
trusted the length its caller passed. No change in behaviour.

## [0.3.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.3.0 does
not compile under 0.71.0.

## [0.3.0] — 2026-10-03

Requires NURL 0.69.0 and http ^0.7 (the viewer builds on the `HttpApp` handle).

Nothing is released by hand any more.

- `PlyW` is a handle over an rcbox instead of a `*PlyW` pointer:
  `ply_create` returns `!PlyW String`, and `ply_vertex` / `ply_count` /
  `ply_flush` / `ply_finish` take the handle. Every copy is the same
  writer; `ply_finish` still flushes, patches the count and closes, and a
  writer whose last owner lets go of it unfinished is finished then, the
  way a buffered writer flushes when dropped (it used to leak, file open
  and count unpatched).
- The viewer's state is a handle each route holds a share of, instead of
  a raw block behind a global that was never released.
- The ascii buffer is cleared in place on a flush instead of freed and
  re-made: instructions:u for 2 M binary + 300 k ascii vertices −1.2 %,
  byte-identical files.

## 0.2.3

- Requires `http ^0` instead of `^0.3`. http has been 0.4.0 since #1014
  and 0.4.0 is what this package is built and tested against in the
  repo, but the manifest still asked for `^0.3` — so an install from the
  registry resolved http 0.3.2 and compiled against different code than
  anything here was tested on. `nurlpkg publish` refuses on exactly that
  mismatch, which is how it surfaced. The caret sits on the major so a
  0.x minor release of http cannot silently re-open the same gap in
  every consumer.
- `--version` reports the manifest version.

## 0.2.2 — 2026-07-29

- Viewer: a 4-thread worker pool instead of a single-threaded accept
  loop — a second browser (or a second machine, with --host) no longer
  queues behind the first client's download.
- Rides on the stdlib ChaCha20-Poly1305 rewrite in the same change:
  a TLS cloud download went from ~27 MB/s to ~170 MB/s served, past
  gigabit wire speed. (Ships to installed toolchains with the next
  release; the pool applies immediately.)

## 0.2.0 — 2026-07-29

- **`--host` / `--addr`** on `ply view`: the bind address. The default
  stays 127.0.0.1 (private to the machine); `--host 0.0.0.0` serves
  every interface, a specific address serves exactly that adapter.
- **`--tls`**: HTTPS with a fresh self-signed P-256 certificate
  generated at startup (std/x509_gen, CN ply.local, 30 days) — the
  browser warns once, but the cloud crosses the LAN encrypted. The PEMs
  are staged through unpredictable temp paths and unlinked after the
  listener exits.
- `vw_serve` grew `tls` as its sixth parameter (breaking for callers;
  lingbot-map ≥ 0.9.0 and map-anything ≥ 0.4.0 carry the new flags
  through their own `view` / `--view`).

## 0.1.1 — 2026-07-28

- Viewer: horizontal drag was inverted, in both orbit and pan — dragging
  left rotated (and walked) the scene right. World up is -Y (OpenCV
  axes), which mirrors the screen's horizontal axis relative to a +Y-up
  orbit: the vertical signs come out right on their own, the horizontal
  ones had to be flipped. Vertical behaviour is unchanged.

## 0.1.0 — 2026-07-28

Extracted from `lingbot-map` 0.7.0 (the PLY section of `src/main.nu`,
`src/viewer.nu` and `views/viewer.html`); the history of the code before
this point is that package's.

- Streaming writer: `ply_create` / `ply_vertex` / `ply_finish`, binary
  and ascii, fixed-width count placeholder patched in place at the end,
  ~4 KB write buffering, caller-provided comment line.
- The WebGL2 viewer page, embedded: orbit/pan/zoom, point size, density
  (seeded-shuffle uniform sampling), percentile far-trim, rgb / height /
  depth colouring, `?probe=N` headless render check.
- `vw_serve`: page + cloud on localhost over the http package.
- CLI: `ply view <cloud.ply> [--port n] [--page f]`, `ply info`, and
  `ply <cloud.ply>` as shorthand.
