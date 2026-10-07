# Changelog

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
