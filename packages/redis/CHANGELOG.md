# Changelog

## [0.3.7] — unreleased

Requires the NURL with std/net's `NetDialer`.

### Added

- `redis_connect_with dialer host port` — plaintext, dialed through a std/net `NetDialer`: the kernel's, or a node of a simulated network (`netsim_dialer`), so the same client runs over it unchanged (agora #249). TLS needs the kernel's dialer until it can run over a dialed connection (agora #250).

## [0.3.6] — 2026-10-29

### Changed

- The `SUBSCRIBE` / `PSUBSCRIBE` loop and the command dispatch bind the token they view (`: String … ?? ( vec_get … )`) before taking `string_data` of it. NURL now refuses a view of a `?` / `??` join kept past its statement: on the path that made a fresh `String`, nothing could release it (agora #181).

## [0.3.5] — 2026-10-14

Requires NURL 0.73.0 (`slice_at`, `slice_put`, `rc_take`, `locked_take`).

### Changed

- The connection is a `TcpConn` (`tcp_connect` / `tcp_connect_tls`) in a `Locked`, instead of a raw socket handle, a zeroed `TlsConn` and an `Arc` changed through a raw pointer. No function is `unsafe` any more.
- 47 fewer functions are `unsafe` than in 0.3.4 (0 left).

## [0.3.4] — 2026-10-12

Requires NURL 0.73.0, in which a field written through a raw pointer
drops what it held, a mutable module global may own a `String`, a `Vec`
or a handle, and a foreign function may take an `inout` parameter.
The published 0.3.3 does not compile under it.

### Changed

- The `TcpConn` over the connection's socket is a view (`tcp_conn_view`): NURL 0.73.0's `TcpConn` closes its socket when its last owner goes, and this one belongs to the connection record, whose drop closes it.
- The zero `TlsConn` a plaintext connection keeps is built with the
  cast `# TlsConn # s 0`: a standard-library handle now holds its state
  in a `( Shared T )`.
- A parsed reply leaves the parse result by the return that moves it;
  the `mem_take` before it is gone.

## [0.3.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.3.2 does not compile under it.

### Changed

- `RedisConn` keeps its state in an `Arc` (stdlib/std/arc.nu) instead of
  an `rcbox`. The share and drop hooks are ordinary safe functions — the
  Arc does the counting — and so are the constructors that build one from
  a whole value; every copy is still the same state, and its last owner
  releases it.
- One fewer function is `unsafe` than in 0.3.2.
- Its `--version` (or the version it reports) is read from `nurl.toml`
  with `( pkg_version )` instead of being written by hand, so it can no
  longer drift from the manifest.
- `resp_parse` moves the node arena out of its builder in the reply
  literal — no `mem_take`, so it is safe code again.

## [0.3.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.3.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.3.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.3.0 does
not compile under 0.71.0.

## [0.3.0] — 2026-10-03

Requires NURL 0.69.0 and cli ^0.4 (the `Cli` handle).

Nothing is released by hand any more.

- `RedisConn` is a handle instead of a `*RedisConn` pointer: every copy is
  the same connection, and the last owner closes the TLS session or the
  socket, as `redis_close` did. `redis_connect` / `redis_connect_tls` →
  `!RedisConn RedisErr`; every command takes the handle.
- `RedisReply`, `RedisStr`, `RedisMessage` and argument vectors are plain
  values; `resp_reply_free`, `redis_str_free`, `redis_message_free`,
  `redis_args_free` and `redis_close` are optional early releases.
- The RESP parser keeps its state in an `inout` local instead of a heap
  block, and a parsed reply moves out of the parse result instead of being
  copied. Fixed: the parser's node arena leaked once per reply (the reply
  held a copy of it), so every command leaked under LSan. A 4 503-command
  REPL session runs 12.8 % fewer instructions.
- Fixed: `redis --version` reported 0.2.1; it now matches the manifest.

## 0.2.2

`redis_args_free`, `redis_message_free`, `redis_str_free`, `resp_reply_free` now take a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.2.1 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
