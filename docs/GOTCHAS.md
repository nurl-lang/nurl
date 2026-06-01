> [!NOTE]
> **The historical "language gotchas" list is empty as of v0.7.1+.**
> Every trap that previously needed memorisation now surfaces as a
> compiler `error:` / `warning:` with a pointing caret and the
> concrete cure inline. The remaining edge — prefix-arity strictness
> — is documented in [`docs/LIMITATIONS.md`](LIMITATIONS.md) **→ Grammar**,
> since it is a grammar property (no closing token, every
> operator has fixed arity), not a surprise the model can't predict
> from the spec. (`^` is the return operator; XOR is the distinct
> `^^` operator — see `spec/grammar.ebnf`.)
>
> Diagnostics shipped (see `compiler/nurlc.nu` for the emit sites):
>
> | Symptom                                                    | Compiler now says |
> |------------------------------------------------------------|-------------------|
> | `^ ?? v { … ^ in arms }`                                   | `error:` + `: ~ T rc … / ?? { … = rc v } / ^ rc` cure |
> | `nurl_str_len s_String` / `string_len i8*`                 | `error:` + which helper to use |
> | param named `entry`                                        | `error:` + rename suggestion |
> | `# T { ... }` where T is a struct/enum                     | `error:` + "use `@ T { ... }`" |
> | `: ~ *T` (long-loop miscompile)                            | `warning:` at decl |
> | bare `@-fn` used as a closure value                        | `error:` + `\ args → R { ( fn args ) }` wrap |
> | `?` with bare then/else followed by `{ ... }` block        | `warning:` (the n-ary `&`/`|` trap) |
> | `:`-binding shadowing a parameter                          | `warning:` |
> | closure capturing `: ~`-multi-field struct, escaping       | `warning:` (borrow-checker region escape analysis, on by default; `--no-borrowck` disables) on `^`-return / `vec_push`/`vec_insert`/`vec_set`/`thread_spawn` / assignment into a longer-lived binding |
> | `( f a )` for an `@`-fn `f` declared with a different arity | `error:` + `call to 'f' has the wrong number of arguments: expected N, got M` |
> | a prefix operator short an operand, over-reading the next line | `error:` + names the token and points back at the line whose statement is short an argument |
>
> If you are an LLM and hit a NURL compile error not listed above,
> the diagnostic itself is the source of truth — quote it verbatim
> rather than guessing. For grammar-level questions (operator arity,
> prefix notation, prefix-cascade debugging) consult
> [`../spec/grammar.ebnf`](../spec/grammar.ebnf) — it carries the
> definitive grammar including the binary-operator comment.

---

## 12. Async runtime — fiber traps (Phase 1–8, 2026-05-23)

The stackful M:N fiber runtime in `stdlib/std/async.nu` is designed
to look and feel like ordinary code (no `async`/`await` colouring),
but a handful of platform realities still leak through:

- **TLS through LTO** — any runtime function in `stdlib/runtime.c §24`
  that reads `nurl__tls_worker` carries
  `__attribute__((noinline))`. Cross-translation-unit inlining of
  `__thread` accesses (the NURL-emitted IR is a separate TU) lowers
  the segment-register-relative load incorrectly under
  `clang -O2 -flto`, returning a stale or NULL value for what
  should be a valid worker pointer. Symptom: `nurl_fiber_current`
  silently returns 0 inside a freshly-resumed fiber, the fiber-aware
  `tcp_accept` dispatch then falls through to the blocking path on
  a non-blocking listener, and accept immediately surfaces
  `NetTimeout`. Symptom-debugged via raw writes; eliminated by
  `noinline` on every TLS-reading entry point (`nurl_fiber_current`
  / `_yield` / `_worker_id` / `_park_with_mutex` / `_reactor_wait`).
  Adding a new TLS-reading runtime function? Annotate it the same way.
- **Reactor park-vs-unpark race** — `nurl__reactor_wait` registers
  the wait entry with `active = 0`; the worker loop, after the
  parking fiber's `swapcontext` completes, calls
  `nurl__reactor_activate` to flip the flag. The reactor only
  considers active entries, so an unpark cannot fire before the
  fiber's context is fully saved. Channel-coordinated parks
  (`Channel[A]`) use the symmetric `pending_unlock` deferral.
- **Same-handle async + sync mixing** — once any of
  `tcp_accept_async` / `tcp_read_chunk_async` / `tcp_write_all_async`
  runs on a `TcpListener` / `TcpConn`, the underlying socket has
  `O_NONBLOCK` set. A subsequent SYNC call on the same handle from
  a non-fiber context will then surface EAGAIN as `NetTimeout`.
  Either stay in async mode for that handle or call
  `tcp_set_nonblock_*` to flip it back.
- **Capturing a stack-borrowed pointer in a spawned closure** is
  the same hazard as `thread_spawn` — borrow-checker phase 3 catches
  the documented shapes (`vec_push`/`vec_insert`/`vec_set`/`spawn`/
  `thread_spawn` of an escaping mutable-struct capture), but a
  closure that captures a `: ~ T x` then survives `x`'s scope is on
  you. Use a heap-backed handle (`Mutex` + `Vec[i]` etc.) for shared
  mutable state across fibers.
- **`runtime_run` blocks until `pending = 0`** — every `spawn` that
  isn't reaped (the fire-and-forget shape) bumps the pending count;
  every fiber that runs to completion decrements it. A long-running
  accept fiber that never returns keeps `runtime_run` blocked
  forever, which is exactly what HTTP servers want. Call
  `server_stop` / `runtime_shutdown` to drain on demand.
