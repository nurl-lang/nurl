# Changelog

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

