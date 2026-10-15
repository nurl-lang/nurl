# Changelog

## [0.7.6] — 2026-10-14

Requires the NURL with `rc_take` / `rc_restore` and `http3_creds_ok`.

### Changed

- No function is `unsafe` any more (30 were): an `HttpApp`'s setters check its state out of the `Rc` and back in, the request dispatcher reads a frozen `Arc` of the router, the static flag and the web root, and `http_app_router` hands out a copy of the router.
- The HTTP/3 side of `listen` holds its server, socket and thread as options instead of handles made from zero, and asks `http3_creds_ok` whether the credentials loaded.

## [0.7.5] — 2026-10-12

Requires the NURL in which `Thread` holds its state in a `( Shared T )`:
the empty handle is `( thread_null )`, no longer `@ Thread { # s 0 }`.

### Changed

- The HTTP/3 server thread slot starts as `( thread_null )`.

## [0.7.4] — 2026-10-12

Requires NURL 0.73.0, in which a standard-library handle holds its
state in a `( Shared T )` (stdlib/core/rcbox.nu): a zero handle is the
cast `# File # s 0`, no longer the literal `@ File { # s 0 }`. The
published 0.7.3 does not compile under it.

### Changed

- The zero `H3Server`, `QuicCreds` and `QuicTp` handles this package keeps until one
  is made are built with the cast. No change in behaviour.

## [0.7.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.7.2 does not compile under it.

### Changed

- `HttpApp` keeps its state in an `Rc` (stdlib/std/rc.nu) instead of an
  `rcbox`: the hooks are ordinary safe functions, and the state, which
  holds closures that may capture the handle, is collected when such a
  cycle is left unreachable.
- One fewer function is `unsafe` than in 0.7.2.

### Fixed

- A route handler that captures its own `HttpApp` no longer keeps it alive
  for the rest of the process: the `Rc` cycle collector releases the pair.

## [0.7.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.7.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

## [0.7.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.7.0 does
not compile under 0.71.0.

## [0.7.0] — 2026-10-03

### Changed (breaking)

- `HttpApp` releases itself: `( http_app_new )` returns an `HttpApp` handle
  instead of a `*HttpApp` the caller had to free (`: *HttpApp a ( http_app_new )`
  → `: HttpApp a ( http_app_new )`). Every function that took `* HttpApp`
  takes `HttpApp`. Every copy of the handle (a struct field, a `Vec` element,
  a closure capture) is the same app; its last owner drops the router, the
  strings and the middleware — servers that never called `http_app_free`
  no longer leak the app at exit. `http_app_free` stays as an optional early
  release. Nothing else in the API moved.
- `http_app_use`: the app keeps its own copy of the middleware wrapper, so the
  wrapper no longer has to outlive `http_app_listen` or be freed by the caller.

Requires NURL 0.69.0.

## 0.6.2

Closures are no longer freed by hand: the router's handlers and the HTTP/3 thread body are owned by whatever holds them (NURL 0.67.0 closure ownership, #1141).

