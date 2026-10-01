# Changelog

## Unreleased

`HttpApp` releases itself: `http_app_new` returns an `HttpApp` handle (its state in an rcbox) instead of a `*HttpApp` the caller had to free. Every copy of the handle is the same app, and its last owner drops the router, the strings and the middleware — the servers that never called `http_app_free` (embed, f5tts, whisper) no longer leak the app at exit. `http_app_free` stays as an optional early release. Callers change `*HttpApp` to `HttpApp`; nothing else in the API moved.

## 0.6.2

Closures are no longer freed by hand: the router's handlers and the HTTP/3 thread body are owned by whatever holds them (NURL 0.67.0 closure ownership, #1141).

