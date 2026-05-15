# Changelog

All notable changes to NURL — Neural Unified Representation Language —
are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

* **HTTP server pipelining correctness.** The keep-alive request loop
  previously copied all bytes past a parsed head wholesale into
  `req.body`, which silently corrupted req1 and dropped req2 entirely
  when a peer pipelined two requests in one `send()`. The fix
  introduces a connection-level `Vec[u] carry` buffer that survives
  across keep-alive iterations: `__read_request_head` drops only the
  `.consumed` bytes off the front after a successful parse;
  `__finish_body` drains exactly Content-Length bytes off carry's
  front before topping up from the socket; any remaining bytes feed
  the next iteration. Mirror call site in `stdlib/ext/http_proxy.nu`
  also updated. Acceptance:
  `compiler/tests/http_server_pipelined.nu` (NURL_NET_TESTS=1).

## [0.3.0] — 2026-05-15

Grammar moved from v1.9 → **v2.0**: visibility control with `pub` is
the headline feature. `printf`-family direct-call (variadic FFI)
shipped in the same window. `nurlfmt` learned the canonical layout
and ships as `build/nurlfmt`. Bootstrap fixed point holds with
byte-identical LLVM IR across stages 1 and 2.

### Added

* **Visibility control with `pub`** (grammar v2.0). A top-level decl
  may carry a leading `pub` keyword to mark it public:

  ```nurl
  pub @ greet → v { ( nurl_print `hello\n` ) }
  @ __priv   → v { ( nurl_print `internal\n` ) }
  ```

  Per-file strict-vis mode is OPT-IN: a source file enters strict
  mode the first time any of its decls carries `pub`. In strict
  mode, every unmarked `@`-function is private to that file; calls
  from another file are rejected with
  `private function 'X' is not visible across files; defined in 'Y'`.
  Files without any `pub` decl stay in legacy mode — the entire
  existing stdlib + test corpus continues to build unchanged.

  Implementation: `LTT_PUB = 44` in `stdlib/runtime.c` (the lexer
  recognises the bare identifier `pub`); `compiler/nurlc.nu` tracks
  per-fn origin + per-file strict-mode in a new `g_vis_syms` map,
  the current source file is saved/restored across nested
  `$`-imports, and `gen_call` enforces the rule at @-fn dispatch
  sites. Forward-compat parse paths for `pub` on `:` / `&` / `%`
  decls accept the prefix but do not yet enforce — wider
  enforcement is on the roadmap. `nurlfmt` learned to glue `pub`
  onto the following decl-starter so `pub @ greet` stays on one
  line through the formatter. Regression tests:
  `compiler/tests/pub_visibility.nu` (positive, runs `hello from pub`
  + `hello from priv`) and `compiler/tests/should_fail_pub_visibility_neg.nu`
  (negative, expected `COMPILE FAIL`). Bootstrap fixed point holds
  with byte-identical IR across stages 1 and 2.

* **Variadic FFI + automatic argument promotion** (grammar v1.9).
  FFI declarations may end the param list with the literal `...`
  token to mark the C function variadic. New `LTT_ELLIPSIS = 43`
  in `stdlib/runtime.c`; `gen_ffi_decl` records `<fname>__variadic`
  + `<fname>__variadic_fixed` side-channels; `gen_call` applies the
  C default argument promotions (ISO C §6.5.2.2) to every argument
  beyond the fixed count — `float → double` via `fpext`, narrow
  ints (`i1` / `i8` / `i16`, signedness from the binding's
  `__unsigned` flag) → `i32` via `sext` / `zext`. `i32` / `i64`
  / `double` / pointers pass through unchanged. Unlocks direct
  `printf` / `snprintf` / `fprintf` / `scanf` from NURL without
  per-call hand-widening. Closes `docs/GOTCHAS.md` §9 — every
  remaining §1-10 entry is now an intentional design choice rather
  than a real bug. Canonical example:

  ```nurl
  & `libc` @ printf s fmt ... → i32

  : i32 a 42
  : f32 c # f32 3.5
  ( printf `i32=%d f32=%g\n` a c )   // both args auto-promoted
  ```

  Regression: `compiler/tests/variadic_ffi.nu` (every promotion
  rule in one exit-0 program). Bootstrap fixed point holds at
  1 125 285 B (stage1 ≡ stage2 byte-identical, +11 426 B vs Phase
  1B). `nurlfmt` round-trips `...` as a single OP token (added
  6b branch in `tools/nurlfmt/tokenize.nu`). Snapshot:
  [`spec/grammar_v1.9.ebnf`](spec/grammar_v1.9.ebnf).
* **`nurlfmt` — canonical source formatter.** First-class tooling
  for deterministic NURL source layout. Written in NURL itself
  (eats its own dogfood) and built automatically by `./build.sh`
  to `build/nurlfmt`. Specification lives in
  [`docs/FORMAT.md`](docs/FORMAT.md). CLI mirrors gofmt/rustfmt:
  `nurlfmt` (stdin→stdout), `--stdin` (explicit), `--check`
  (CI-friendly idempotence gate), `--write` (in-place), plus
  multi-file fan-out and the conventional 0/1/2 exit-code
  semantics.

  Architecture: token-stream walker — `tools/nurlfmt/tokenize.nu`
  rebuilds a comment-and-newline-preserving token vector from
  source, `tools/nurlfmt/pretty.nu` emits the canonical layout by
  tracking brace depth, top-level decl boundaries, and type-
  prefix sigil tightness (`*Expr`, `?i`, `[T]`). No CST is
  built; NURL's regular prefix grammar lets a token walker do
  the work that `gofmt` needs an AST for.

  Acceptance:
  `compiler/tests/nurlfmt_idempotent.sh` enforces two invariants
  on every `.nu` file under `stdlib/`, `examples/`,
  `compiler/tests/`, `tools/nurlfmt/`, and `compiler/nurlc.nu`:
  `fmt(fmt(x)) == fmt(x)` (formatter is a fixed point on its own
  output) AND `nurlc(fmt(x)) == nurlc(x)` byte-for-byte (the
  reformat changes zero bytes of emitted LLVM IR). 263 files
  pass idempotence; 251 are IR-equivalence covered (12 are
  include fragments that don't compile standalone and are
  skipped for the IR pass).

  v1 deliberate scope: no automatic line wrapping, no
  cascading-construct extra-indent (a user-written newline
  inside a ternary cascade gets re-indented to the surrounding
  block, not bumped by one level — see FORMAT.md §7), no comment
  reflow, no range formatting.

## [0.2.0] — 2026-05-14

First post-bootstrap release. The grammar moved from v1.7 → **v1.8**,
adding fixed-size integer and float types. Six long-standing compiler
quirks closed; the standard library no longer carries workarounds for
them. Bootstrap fixed point holds at 1 113 859 B (stage1 ≡ stage2
byte-identical LLVM IR).

### Added

* **Fixed-size integer and float types** (grammar v1.8). New TYPE_KW
  tokens `i8`, `i16`, `i32`, `u16`, `u32`, `u64`, `f32` recognised by
  the lexer. LLVM mappings: `i8` / `i16` / `i32` → `iN`; `u16` / `u32`
  → `i16` / `i32` with signedness carried in a per-binding side-
  channel (LLVM IR has no unsigned types); `u64` → `i64`; `f32` →
  `float`. Cast (`#`), let-binding store, and function-parameter
  store all consult the binding's signedness to pick `sext` (signed)
  vs `zext` (unsigned) on widening, `trunc` on narrowing. Float ↔
  double conversions use `fpext` / `fptrunc`; mixed integer/float
  paths use `fptosi` / `sitofp`.
* **Unsigned arithmetic for sized u-types.** `gen_binary` now picks
  `udiv` / `urem` / `lshr` / `icmp u*` when either operand is
  declared `u16` / `u32` / `u64` (matching the existing 8-bit `u`
  behaviour). Bitwise `&` / `|` are sign-agnostic at the LLVM level
  and previously rejected `i8` / `i16` operands; that gate was
  broadened to all integer widths.
* `CONTRIBUTING.md` with contribution guidelines and the byte-
  identical-IR bootstrap acceptance criterion.
* Google Colab notebook badge in `README.md` for one-click try-out.
* Regression tests: `compiler/tests/fixed_size_types.nu`,
  `compiler/tests/unsigned_arith.nu`,
  `compiler/tests/result_multifield.nu`,
  `compiler/tests/result_multifield_try.nu`,
  `compiler/tests/option_multifield.nu`,
  `compiler/tests/option_multifield_try.nu`,
  `compiler/tests/mutable_enum_binding.nu`,
  `compiler/tests/multifield_struct_mut.nu`,
  `compiler/tests/function_param_mut.nu`.

### Changed

* **Grammar v1.7 → v1.8.** Multi-char TYPE_KW tokens added (see
  Added). Per-binding `__nurl_type` + `__unsigned` side-channels
  drive cast / store / binop selection. No breaking changes to
  existing v1.7 programs.
* `stdlib/ext/http_server.nu` `server_run` rewritten to carry the
  failing `NetErr` variant directly through a `: ~ NetErr last_err`
  mutable binding. The previous `had_err: b` sentinel-flag dance
  plus cheap-re-issue trick is gone.
* `docs/GOTCHAS.md` rewritten for the v0.2.0 surface: historical
  bug-fix entries removed, current quirks and design notes only.

### Fixed

* **Multi-field structs on the `! T E` Ok arm.** Previously
  multi-field T couldn't fit through the i64 payload slot, forcing
  callers to wrap state in a single-pointer-handle struct or carry a
  parallel tagged-struct. The compiler now heap-boxes multi-field T
  transparently at construction (`gen_agg_lit`), unboxes at `??`
  match destructure (`gen_match`), and unboxes at `\` try-propagate
  (`gen_try_expr`). Single-pointer-handle T continues to use the
  cheaper `ptrtoint` path — no allocation.
* **Multi-field structs in `? T` Option Some arm.** Option's natural
  `{ i1, %T }` layout already handles multi-field T inline, but the
  standard `@ ? T { F # T 0 }` None-payload idiom in `vec_get` /
  `hashmap_get` / iter combinators emitted invalid IR when T's first
  field was a non-pointer named type (e.g. `%String` inside
  `Header`). `gen_cast`'s `i64 → struct` branch now returns
  `zeroinitializer` for that shape, so the None idiom works
  uniformly across stdlib.
* **Mutable enum bindings.** `: ~ NetErr e NetOther` and the
  symmetric immutable case `: NetErr e NetOther` no longer produce
  type-mismatched IR. `coerce_store_val` wraps `i64 → %Enum` with an
  `insertvalue` before the store, detected via the
  `<name>__variants` side-table. Bare-variant reassignment
  (`= last_err NetTimeout`) works for narrow and wide enums.
* **Multi-field struct mutation through closures.** When a `: ~`-bound
  multi-field struct is captured by a closure, the closure's env
  block now stores the caller's alloca *pointer* instead of
  snapshotting the value. Writes through the closure reach the
  caller's memory; immutable captures still snapshot. Lifetime
  caveat: captures are borrows — the closure must not outlive the
  binding's scope.
* **Function-parameter struct field mutation.** `= . p field val`
  on a struct parameter previously emitted invalid IR (empty GEP
  base). `gen_fn_decl_concrete` now calls `__alloca_struct_params`
  right after the function's `entry:` label; it backs each multi-
  field-struct parameter with an `alloca + store` and registers the
  pointer as the binding's `__ptr`. Value semantics are preserved
  — the function mutates a local copy; callers thread mutation
  back through the return value.

### Removed

* Obsolete test fixture removed from `compiler/tests/`.

---

## [0.1.0] — 2026-05-12

Initial public commit. Self-hosted NURL compiler targeting LLVM,
grammar v1.7. Establishes the baseline against which subsequent
releases are measured.

* Self-hosted compiler (`compiler/nurlc.nu`) with Python bootstrap
  (`compiler/nurlc.py`) and byte-identical-IR fixed-point bootstrap
  acceptance.
* Native cross-compilation targets: Linux x86_64, Windows x86_64
  (mingw-w64 + libcurl + Schannel TLS), macOS x86_64 (`zig cc` +
  libSystem only), wasm32-wasi.
* Self-hosted compiler compiles to ~390 KB of wasm and runs in a
  browser via `@bjorn3/browser_wasi_shim`.
* Single-owner memory model with compiler-inserted auto-drop
  (phases 1, 2A, 2B, 2C, 2D), user `Drop` trait, foreach-borrow
  semantics, scope-exit cleanup.
* **Standard library** under `stdlib/`:
  * `core/`: `option`, `result`, `vec`, `pair`, `string`, `errors`,
    `mem`, `io`.
  * `std/`: `fmt`, `fs`, `path`, `time` (Howard Hinnant civil-time
    algorithms, ISO-8601 + RFC 7231), `random`, `sort`, `iter`,
    `hash`, `hashmap`, `set`, `cmp`, `encode`, `channel`, `thread`,
    `signal`, `process`, `log`, `net`, `bytes`, `int`, `float`.
  * `ext/`: JSON, CSV, regex, UUID v4 + v7 (RFC 9562), env, the
    full HTTP server stack (`http`, `http_json`, `http_request`,
    `http_response`, `http_server`, `http_router`, `http_static`,
    `http_auth`, `http_middleware`, `http_multipart`, `http_proxy`,
    `http_full` aggregator), Anthropic Claude client (streaming
    SSE, prompt caching, extended thinking, tool-use loops), MCP
    client over HTTP and stdio transports.
* HTTP server: Phases 1–6 + 5.3 thread pool + 5.4 HTTP/1.1
  keep-alive (~38× speedup) + 7 (static / auth / cookies / form)
  + 8 mostly (access log, Prometheus metrics, idle timeout,
  graceful shutdown) + 9 partial (multipart/form-data, reverse-
  proxy streaming pass-through).
* 80+ snapshot tests with `compiler/tests/run_tests.sh` runner.
* Documentation: `README.md` (project overview), `ROADMAP.md`
  (development plan), `docs/GOTCHAS.md` (compiler quirks),
  `HTTP_SERVER_PLAN.md` (multi-phase server design), `spec/grammar.ebnf`
  (v1.7 grammar).
* Tooling: VS Code extension (`tooling/vscode-nurl/`), Dockerised
  compile-server (`api/`), browser playground (`nurlweb/`).
* Dual license: MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE).

[Unreleased]: https://github.com/nurl-lang/nurl/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/nurl-lang/nurl/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nurl-lang/nurl/releases/tag/v0.1.0
