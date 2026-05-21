# Changelog

All notable changes to NURL — Neural Unified Representation Language —
are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

* **Standard-library Clone story.** Owned containers can now be deep-copied
  without hand-rolling a per-type clone. NURL has no type-class dispatch,
  so — exactly like the existing `vec_free` / `vec_free_with` split — the
  clone is delivered as a per-call closure rather than a language-level
  `Clone` trait:

  * `string_clone String → String` (`stdlib/core/string.nu`) — independent
    deep copy of an owned String; embedded NUL bytes preserved verbatim.
    The stock element-clone for owned-String containers.
  * `vec_clone [A] v → ( Vec A )` — bitwise shallow copy, trivial element
    types only. `vec_clone_with [A] v ( @ A A ) clone → ( Vec A )` — deep
    copy that runs `clone` per element; use for `Vec[String]`, nested
    `Vec`, `Vec[HashMap]`.
  * `vec_filter_with [A] v ( @ b A ) pred ( @ A A ) clone → ( Vec A )` —
    owned-safe filter: kept elements are *cloned* into the result instead
    of bitwise-aliased, so source and result can both be freed with
    `vec_free_with` without a double-free. Plain `vec_filter` stays the
    fast path for trivial elements.
  * `map_clone [K V] m → ( HashMap K V )` — bitwise, trivial K/V.
    `map_clone_with [K V] m ( @ K K ) clone_k ( @ V V ) clone_v` — deep
    copy. Both preserve the source slot layout verbatim (same cap, probe
    positions, tombstones), so the clone needs no rehash.

  Before this, `vec_filter` / `vec_extend` / `map_keys` / `map_values`
  bitwise-copied elements — silent UB / double-free for any owned element
  type (`Vec[String]`, `HashMap[String _]`, nested containers), an unsafe
  copy the borrow checker cannot see because it happens inside a
  monomorphised generic. The `_with` variants close that hole. Regression
  `compiler/tests/clone_basic.nu` — verified independence (mutate source →
  clone unaffected) and ASan + UBSan + leak-detection clean.

* **`inout` field targets.** An argument of the form `. obj field` at
  an `inout` parameter now passes the *address of that struct field*,
  so the callee mutates exactly that field of the caller's struct in
  place — finer-grained than passing the whole struct `inout`:

  ```
  @ add100 inout i x → v { = x + x 100 }
  : ~ Game g @ Game { @ Counter { 1 99 } 0 }
  ( add100 . g turns )    // g.turns is mutated in place
  ```

  `obj` must be a mutable (`: ~`) struct binding — or an `inout`
  struct parameter, which carries the same backing-pointer shape. The
  field's address is a `getelementptr` resolved through the
  `<sname>__<field>__idx` roster, so plain and generic structs both
  work; the field may itself be a struct (`( bump . g score )`).
  Single-level access (`. obj field`) only. Regression test
  `compiler/tests/inout_field.nu` (+ `should_fail_inout_field_immut.nu`).
  See `BORROW.md` Phase 4.

* **`inout` / `sink` parameter conventions on generic functions.**
  A generic function may now mark a parameter `inout` (exclusive
  mutable borrow) or `sink` (the callee consumes it), exactly like an
  ordinary function:

  ```
  @ store_g [A] inout i slot  A item → v { = slot + slot 1 }
  ( store_g [i] n 7 )    // n is mutated in place
  ```

  A parameter convention is a property of parameter *position*, not of
  the type arguments, so the `inout` / `sink` index sets are computed
  once from the generic template (the new `compute_generic_inout_sink`,
  keyed by the generic name) and a call site resolves them by that
  name — the mangled-instantiation entry only appears once the
  deferred monomorphisation is compiled, which is too late for the
  call that triggered it. Previously a generic `inout` argument was
  passed by value into a `<T>*` parameter (an LLVM type mismatch). A
  forward call to a generic `inout` function is rejected with the same
  define-before-call diagnostic as the non-generic case. Regression
  tests `compiler/tests/inout_generic.nu` and
  `should_fail_inout_generic_forward.nu`. See `BORROW.md` Phase 4.

* **Forward references for enum-variant payload types.** An enum
  variant whose payload is a struct or enum declared *later* in the
  same file now parses correctly:

  ```
  : | Shape { Dot  Box Geom }   // Geom used before it is declared
  : Geom { i w  i h }
  ```

  Previously the compiler only recognised a payload type already
  registered in the symbol table, so a forward-referenced payload was
  misread as a phantom extra variant — and any `??` match over the
  enum then failed with a bogus non-exhaustive-match error. A new
  linear pre-pass (`scan_type_names`) registers every top-level
  struct / enum / generic-struct name before the main compile pass,
  following `$`-imports. Regression test
  `compiler/tests/forward_enum_payload.nu`.

### Fixed

* **Enum variant with a struct or enum payload now constructs and
  pattern-matches correctly.** Building `@ E { Variant structValue }`
  used to store the struct value straight into the variant's pointer
  slot (an LLVM type error: a multi-field struct is not a pointer),
  and the matching `??` arm mis-unboxed it. Both sites are fixed:
  construction heap-boxes the `%Name` payload (`nurl_alloc` + `store`)
  and the match arm `load`s it back through the slot pointer. Pointer
  payloads (`*Ast`) and single-pointer-handle structs (`String`,
  `Vec`) keep their existing direct-store path. This bug was
  independent of forward references — it affected backward-declared
  payload types too — but went unnoticed because no test constructed
  such a value.

* **`#`-cast from a named aggregate (enum or struct) to an integer
  now works.** `# i someEnumOrStruct` (or any sized integer
  destination) recovers field 0 — an enum's variant tag, or a
  struct's first field. Previously the cast emitted no instruction,
  so the i64-typed use site (a return, `nurl_print_int`, arithmetic)
  failed the LLVM verifier. `gen_cast` now has one unified branch:
  `extractvalue` field 0, normalise it to i64 (`sext` a narrow
  integer field, `ptrtoint` a pointer field, `fptosi` a float
  field), then `trunc` to a narrower destination. A struct whose
  field 0 is itself an aggregate is a hard error. Regression tests
  `compiler/tests/enum_to_int_cast.nu` and
  `compiler/tests/struct_to_int_cast.nu`.

* **Struct construction coerces narrow integer fields.** `@ S { v }`
  where `S`'s field is `i8` / `i16` / `i32` and `v` is a wider value
  (e.g. an i64 literal) used to emit `insertvalue ... i64 …` into the
  narrow field — an LLVM verifier error — forcing an explicit
  `# i8` / `# i16`-cast at every construction site. `gen_agg_lit`
  now coerces each named-struct field value to its declared field
  type: `trunc` into a narrower field, `sext` into a wider one.
  Regression test `compiler/tests/struct_narrow_field.nu`.

## [0.8.0] — 2026-05-20

### Added

* **Native `^^` XOR operator.** Two adjacent carets lex as a single
  `^^` token (the lexer pairs them only when adjacent — `^ ^` with a
  space is still two return tokens). `^^` is a strictly-binary
  operator lowered to LLVM `xor`: bitwise XOR on integer operands,
  logical XOR on `b` operands. Float operands are a compile error
  (LLVM has no float `xor`). Replaces the old `(a | b) - (a & b)`
  identity workaround. `^` alone remains the return operator.
  Grammar (`spec/grammar.ebnf`) and `nurlfmt` updated; regression
  tests `xor_op.nu` + `should_fail_xor_float.nu`.

* **`inout` and `sink` parameter conventions (BORROW.md Phase 4,
  Option B — mutable value semantics).** `in` / `inout` / `sink` are
  contextual keywords recognised only as a parameter's leading token
  (no lexer change); `in` is the default.
  A parameter marked **`inout`** is an exclusive mutable borrow: the
  callee mutates the caller's binding in place. `inout T` lowers to a
  by-address `<T>*` parameter — the body reads/writes the caller's
  storage with no local copy — replacing the `*T`-parameter and
  return-the-struct mutation idioms. The argument must be a mutable
  (`: ~`) binding; an `inout` function must be defined before it is
  called. Exclusive-access check (BORROW.md Phase 5): a binding
  passed `inout` must be the only argument path to its value at that
  call — passing it again, as a second `inout` or a plain by-value
  argument, is a `warning:`.
  A parameter marked **`sink`** consumes (takes ownership of) its
  argument: it lowers to an ordinary by-value parameter, and the
  borrow checker records the argument binding as moved so a later
  use is a use-after-move. `sink` v1 applies to `Vec` and other
  manually-managed handles; passing a compiler-auto-dropped value
  (owned string / slice / `Drop` value / struct with owned fields)
  to a `sink` parameter is rejected pending drop-ownership transfer.

* **Static borrow checker, on by default (BORROW.md Phases 0-3 + 6 +
  8-partial).** A diagnostic analysis pass (disable with
  `--no-borrowck`) that never changes generated code — a
  borrow-clean program compiles to byte-identical IR. Closes four
  bug classes with `warning:` diagnostics: use-after-move (a binding
  read after its ownership moved), alias double-free (`: T b a` of an
  owned heap value moves `a`), stack-reference escape (a closure
  capturing a `: ~`-mutable struct by pointer that is returned,
  pushed into a container, spawned onto a thread, or assigned into a
  longer-lived binding — a region-based check), and iterator
  invalidation (mutating a container — `vec_push`/`vec_free`/… — from
  inside a `~`-foreach that iterates it). Ownership + borrow rules
  documented in the new [`docs/MEMORY.md`](docs/MEMORY.md).

* **Tail-call optimisation in the @-fn dispatch path.** `gen_ret`
  now flags the upcoming return-value expression as
  tail-position; `gen_call` snapshots + clears the flag on entry,
  so only the outermost call in the return expression is treated
  as tail (argument-evaluation recursions stay non-tail). In the
  regular @-fn dispatch path the LLVM `call` becomes `tail call`
  when (a) the flag was set, (b) `rlt == fn_ret_ty` so LLVM
  accepts the marker, (c) the callee is not variadic, and (d)
  `gen_ret` saw no pending owned-string / owned-slice / owned-
  struct-field / user-drop / defer in scope at flag-set time
  (any of those would emit drop calls between the tail call and
  `ret`, which LLVM would silently demote).

  Deliberately chose `tail` over `musttail`: `tail` is a hint
  LLVM may drop when its safety analysis can't confirm the
  rewrite (alloca-escape through an arg, etc.), so a
  misclassification only costs an optimisation. `musttail` is
  verifier-enforced and would fail on NURL's owning ABI where
  the same source-level signature lowers to different LLVM
  types across call sites.

  Effect: tail-recursive functions no longer blow the stack —
  `compiler/tests/tco_deep_recursion.nu` runs a 5_000_000-deep
  countdown in O(1) stack (~7 ms wall-clock). Trait/impl,
  closure-loaded var, and fn-pointer-parameter dispatch paths
  intentionally still emit a plain `call` (different shapes; not
  the deep-recursion targets TCO exists for).

  Coexists with `--g` DWARF emission: `tools/dwarf_test.sh` still
  passes all five phases.

* **DWARF Phase 6 composite-type rendering.** User structs and
  generic-instantiation handles (`%Vec__u8`, `%String`, `%FmtTok`,
  user `% Point`, …) now resolve under `nurlc --g` to a
  `!DICompositeType(tag: DW_TAG_structure_type, …)` carrying one
  `!DIDerivedType(tag: DW_TAG_member, …)` per field — instead of
  the previous i64 placeholder. `gdb ptype Point` lists the fields
  with their NURL names + base types; `print p` renders the value
  as `{x = 3, y = 7}`; `print p.x` evaluates a single field.

  Field roster lives in the existing symbol table next to the
  per-field `__idx_N__type` entries — `gen_struct_decl` and the
  generic-instantiation emitter now also record
  `<sname>__field_count` and `<sname>__idx_N__name`. New helpers
  `dbg_size_bits` / `dbg_align_bits` / `dbg_align_up` compute
  LLVM-natural cumulative field offsets so the emitted
  `!DIDerivedType` member offsets match the actual layout
  clang/LLVM uses. Self-referential structs (a cell holding a
  pointer to itself, etc.) are safe — the composite id is interned
  in `g_dbg_type_syms` before the per-field recursion descends
  through `dbg_type_id_for`, so a back-edge returns the cached id
  instead of looping.

  Regression: `compiler/tests/dwarf_struct.nu` exercises the
  codegen path in the standard test corpus; `tools/dwarf_test.sh`
  picks up a fifth phase that drives gdb in batch mode to assert
  `ptype` + `print` + field-access over the new test. Bootstrap
  fixed point holds — non-debug IR is byte-identical.

  Closes the open Phase 6 follow-up in `DWARF.md`. Phase 7
  (per-instantiation source-line precision for generics) remains
  deferred.

## [0.7.2] — 2026-05-19

### Added

* **Serde-style `JsonSerialize` trait + decoder helpers
  (`stdlib/serde.nu`).** A NURL trait `JsonSerialize [T] { @ to_json
  T x → Json }` with first-arg dispatch and impls for `i` / `b` /
  `f` / `s` / `String`, paired with per-type `from_json_<T>` helpers
  (`from_json_i` / `_b` / `_f` / `_string` / `_str_borrow`) that
  return `!T ParseErr`. User types add their own `% JsonSerialize
  MyStruct { @ to_json MyStruct x → Json { ... } }` impl and a
  hand-written `mystruct_from_json`. The shape mirrors Serde:
  format-specific traits (JsonSerialize stands alone today; TOML /
  MsgPack get their own trait when those formats land) and a
  Deserialize-by-naming-convention because NURL's first-arg-dispatch
  cannot carry a trait whose receiver is `Json` — every impl would
  collide. Demo: `examples/serde_demo.nu` round-trips a `Point`
  through JSON text. Regression: `compiler/tests/serde_basic.nu`.

* **docs/GOTCHAS.md folded back into the compiler + grammar +
  README — empty stub now.** The historical "gotchas" list existed
  to compensate for compile errors that lacked enough context to
  fix the source. As of v0.7.1+ that gap is closed: every old item
  now surfaces as a `file:line:col:` `error:` / `warning:` with a
  pointing caret + concrete cure inline (see "Source-level compiler
  diagnostics" below for the seven new emit sites + the four shipped
  prior). The residual edges — prefix-arity strictness, `^` not
  being XOR — are grammar properties, not surprises; they live in
  README's Known Limitations → Grammar table next to the existing
  imports / FFI limitations, and grammar.ebnf's `bin_expr` /
  `ret_expr` productions now carry explanatory comments. The
  GOTCHAS.md file is preserved as a redirect stub so external
  links (and the MCP `nurl_read_gotchas` resource) keep working,
  but new code should not add items there — extend the compiler
  diagnostics or the grammar comments instead.

* **Two more compiler diagnostics on top of the prior five.**
  Bare `@-fn` used as a closure value (`error:` at the use site
  with the `\ args → R { ( fn args ) }` wrap), and the
  `? cond bare-then bare-else { … } { … }` shape (`warning:` —
  the n-ary `&`/`|` foot-gun where `&` only consumed 2 of the
  operands and the `{ … }` blocks became side-effect statements).
  Both ride on the same `die`/`warn` infrastructure; verified via
  the `bare '@-fn'` / `?-with-{` smoke programs.

* **Source-level compiler diagnostics for five language gotchas.**
  Previously each surfaced as either silent UB or a cryptic LLVM /
  arity error far from the source. Each now emits a
  `file:line:col` diagnostic with a caret + the concrete cure, and
  is mirrored in `docs/GOTCHAS.md` items 6-10 (the Quick-reference
  table gained an "Auto-diagnosed?" column).
    * `^ ?? value { ... }` with `^`-arms — `error:` augments the
      existing `return expression has no value` message with the
      `: ~ T rc init / ?? { … = rc v } / ^ rc` refactor (item 6).
    * `nurl_str_len` (libc, expects `s`) called on a `%String`,
      and `string_len` (stdlib, expects `%String`) called on a
      raw `i8*` — both `error:` at the call site (item 7).
    * Parameter named `entry` — `error:` at the param parse,
      naming the LLVM `entry:` block-label collision (item 8).
    * `# T { ... }` where T is a registered struct/enum — `error:`
      at the cast site suggesting `@ T { ... }` (item 9).
    * `: ~ *T` mutable pointer bindings — `warning:` at the decl
      pointing at the long-loop miscompile (item 10). Warn rather
      than die because trivial isolated cases work; the advisory
      catches the hoist patterns that crash deterministically
      ~tens of thousands of iterations in.

* **One-command developer install (`./install.sh`).** Bootstraps the
  compiler (skipped if `build/nurlc` already exists), builds
  `nurl-lsp`, symlinks it into `~/.local/bin/nurl-lsp` so VS Code /
  Cursor / Windsurf find it without any settings tweak, packages
  the VS Code extension (`vsce package`) and installs it via the
  editor's CLI when one is on PATH. Idempotent: re-run any time to
  pick up a newer checkout. Flags: `--no-vscode`, `--no-path`,
  `--force`, `--uninstall`, `--help`.

### Changed

* **`tooling/vscode-nurl` bumped 0.3.0 → 0.4.4** (matches the
  `nurl-lsp` server version it pairs with). README rewritten to
  document the actual feature set — go-to-definition (single +
  cross-file via `$ `path`` imports), hover, document outline,
  workspace-wide IDENT completion, `Ctrl-T` symbol search, folding
  ranges, and `nurlfmt`-backed formatting — replacing the stale
  "coming in later iterations" line that misrepresented an
  already-shipped server. New packaged extension:
  `tooling/vscode-nurl/nurl-0.4.4.vsix`.

## [0.7.1] — 2026-05-19

### Changed

* **MCP `protocolVersion` bumped from `2024-11-05` to `2025-11-25`
  (current stable revision)** + centralized + drift-check tooling.
  All seven hardcoded pinnings across `stdlib/ext/mcp.nu`,
  `mcp_registry.nu`, `mcp_client.nu`, `mcp_stdio.nu` now route
  through a single `mcp_protocol_version → s` helper. A companion
  `mcp_protocol_version_legacy → s` returns `2024-11-05` for
  callers that need to explicitly negotiate the older shape
  (server MAY agree to whatever the client requests as long as
  it's a revision the server supports).

  MCP revisions only bump on backwards-incompatible changes per
  the spec's versioning page, so a server advertising the latest
  revision serves earlier clients fine — pinning to an old date
  pushes negotiation the wrong way.

  New helper: `tools/mcp_spec_drift_check.sh` fetches the spec
  site's versioning page, parses the current revision, compares
  to NURL's pinned value, exits 1 on drift with a pointer at the
  changelog URL. Drop-in for CI or a weekly cron. Closes
  critic.md #4 ("MCP spec governance shifted ... continuous
  integration against the moving spec is not yet automated").

### Added

* **DWARF debug-info support (compiler + driver, phased per
  `DWARF.md`).** `nurlc --g foo.nu` now emits LLVM `!DICompileUnit` /
  `!DIFile` / per-fn `!DISubprogram` / per-stmt `!DILocation` /
  per-`:`-binding `!DILocalVariable` + `llvm.dbg.declare` metadata.
  `nurl.sh --debug foo.nu` forwards `--g`, drops `-flto` (which
  silently strips DWARF in the current LLVM/gcc-ld pipeline), and
  side-by-side rebuilds `stdlib/runtime_debug.o` with `-g` so the
  link preserves `.debug_info` end-to-end. `gdb` then resolves
  `break fizzbuzz`, `break foo.nu:42`, `print x`, `whatis x` (with
  NURL type names — `i`/`u8`/`b`/`f`/`s`/...), and `backtrace` with
  source file + line for every NURL frame. Closures and generic
  monomorphisations get their own subprograms with mangled names.
  `nurl_panic` now dumps a stack trace via libc's `backtrace_*` API
  before aborting; pipe each frame's offset through `addr2line -e
  <binary>` to recover `.nu:LINE`. End-to-end regression:
  `./tools/dwarf_test.sh` (gracefully skipped if `gdb` is absent).
  Composite-type rendering (`!DICompositeType` for `%Vec` /
  user structs) and per-instantiation source-line precision for
  generics are tracked in `DWARF.md` as Phase 6 / 7 follow-ups.

* **Compiler: closure-escape warnings for `vec_push` / `vec_insert` /
  `vec_set` / `thread_spawn`.** Extends the existing 2026-05-15
  `^`-return escape check (`gen_ret` reading `__last_closure_byref__`
  + `<name>__captures_byref`) to four more sites where a closure
  takes ownership across a scope boundary. `gen_call` snapshots
  `__last_ident_name__` per-argument; when the callee's `fname` is
  one of the four AND the argument names a binding tagged
  `__captures_byref = 1`, emits a soft `warning:` line consistent
  with the existing escape diagnostic. By-name only — struct-wrapping
  (`@ Slot { cb }` then push the slot) passes through silently, which
  is acceptable: we catch the obvious one-line foot-gun rather than
  every conceivable indirection. Closes gotcha #8 to the same scope
  as #5. Regression: `compiler/tests/should_warn_closure_escape_vec.nu`
  (positive `thread_spawn` + 2 negative controls).

  `docs/GOTCHAS.md` §5 updated to document the extended coverage;
  the `vec_push [(@ v)]` form remains untested because anonymous
  closure types aren't yet accepted as generic-arg type names — a
  separate `parse_type_paren` extension would unlock it.

* **MCP server framework with closure-based registry.**
  `stdlib/ext/mcp_registry.nu` (~550 LOC) replaces the previous
  "write your own JSON-RPC dispatch loop" workflow with a uniform
  `register-tool-with-handler` API. The Channel[A] generic-propagation
  fix (2026-05-17) unlocked closure-in-Vec storage, which is what
  makes this possible.

  Three first-class entity types:
    - `McpTool { name, description, input_schema, ( @ Json Json ) handler }`
    - `McpPrompt { name, description, arguments_schema, ( @ Json Json ) handler }`
    - `McpResource { uri, name, mime_type, description, ( @ Json ) handler }`

  Surface:
    - `mcp_registry_new name version → McpRegistry`
    - `mcp_registry_add_tool / _add_prompt / _add_resource` —
      register entities with closure handlers.
    - `mcp_registry_dispatch r method ?params → Json` — single entry
      point routing JSON-RPC method names through the per-method
      dispatchers. Covers `initialize`, `tools/list`, `tools/call`,
      `prompts/list`, `prompts/get`, `resources/list`,
      `resources/read`, `ping`. Unknown methods return an
      `{__error__: "method not found"}` envelope.
    - `mcp_registry_envelope r req → ?Json` — transport-agnostic
      single-request adapter. Notifications (no `id`) return None.

  Transports:
    - **stdio server** — `mcp_serve_stdio r → ! v McpServeErr`
      reads JSON-RPC frames off stdin (line-delimited per spec),
      dispatches via the registry, writes responses to stdout. NURL
      is now a complete bidirectional MCP party (server-side stdio
      pairs with the existing client-side stdio from `mcp_stdio.nu`).
    - **HTTP adapter** —
      `mcp_http_dispatch_for_registry r → ( @ ? Json Json )` returns
      a closure that plugs straight into the existing
      `mcp_http_handler` from `stdlib/ext/mcp_http.nu` (batch
      requests + CORS + session-id echo + SSE stub already covered
      there).
    - **Bearer-auth middleware** —
      `mcp_http_with_bearer_auth handler expected_token` decorates
      any HTTP handler with `Authorization: Bearer <token>`
      enforcement. Missing or mismatched → 401 with
      `WWW-Authenticate: Bearer realm="mcp"`.

  Spec out-of-scope for v1 (tracked):
    * `resources/subscribe` + change notifications (needs an SSE
      push channel from a custom accept loop).
    * `completion/complete` (rarely-used spec feature).
    * `sampling/createMessage` (server→client reverse RPC).

  Regression: `compiler/tests/mcp_registry.nu` exercises every
  dispatch path including 2 tool invocations (echo + add(17,25)=42),
  prompt rendering with arguments, resource read, unknown-method
  error envelope, and ping.

* **`json_as_str` / `json_as_int` / `json_as_bool` accessors** in
  `stdlib/ext/json.nu`. Convenience extractors for the leaf-typed
  variants of `Json`, returning the unwrapped value (or empty/zero
  for the wrong variant). `json_as_str` returns a BORROWED view
  into the underlying JStr's String backing buffer — copy via
  `string_from` for longer-lived references.

* **DoS connection caps for the HTTP server.** Two-axis protection
  against connection-exhaustion attacks:
    - `DosLimits { max_concurrent_conns, max_conns_per_ip }` declares
      the caps. `dos_default_limits → DosLimits { 1024 16 }` covers
      the typical single-VM-public-HTTPS shape; CG-NAT'd clients
      (10s of users behind one public IP) stay under 16 in real usage.
    - `server_new_with_dos listener handler limits` constructs an
      HttpServer with a runtime-side `NurlDosState` (mutex-protected
      counter + linear per-IP table, up to 256 distinct active IPs).
    - At accept time, `server_run_once` calls
      `nurl_dos_state_try_acquire`. Over-cap conns are closed
      immediately at the TCP layer (no canned 503 response — cheapest
      possible rejection, keeps the server's per-cap cost low).
    - Per-connection cleanup releases the counter on conn end;
      multi-worker pools (`server_run_pool`) share the same state via
      the shared HttpServer handle.
    - `server_active_conn_count` exposes the live counter for
      `/metrics`-style observability endpoints.

  Runtime additions in `runtime.c` §23: `NurlDosState` struct + four
  public entry points (`nurl_dos_state_new` / `_try_acquire` /
  `_release` / `_free`) + `_active` accessor. Cross-platform mutex
  (`pthread_mutex_t` POSIX, `CRITICAL_SECTION` Win32). Linear scan
  with O(1) last-element-swap eviction on count→0 keeps the IP
  table compact under steady churn.

  Verified live (NURL_NET_TESTS=1):
  `compiler/tests/http_server_dos.nu` opens 4 concurrent TCP conns
  from 127.0.0.1 against a server with `max_per_ip=2`; the first
  two complete the handshake + handler, the last two are rejected
  pre-handshake → 2 accepted + 2 rejected.

* **TLS extras: SNI + live cert reload + mTLS.** Three additions
  that close the critical-path tuotantopuutteet in the TLS stack
  identified by `critic.md` §10. All built on top of the existing
  `tcp_listen_tls` listener — the new operations attach to an
  already-created listener and take effect on subsequent handshakes.

    - `tcp_tls_add_sni listener hostname cert_path key_path → !v NetErr`
      Registers a per-virtual-host cert/key against the listener
      using OpenSSL's `SSL_CTX_set_tlsext_servername_callback`.
      Clients that offer no SNI extension OR offer an unknown
      hostname fall through to the default cert (set at listen
      time) — matches RFC 6066 §3 server semantics. Idempotent
      on re-add (replaces the stored pair for an existing host).
      Required for multi-tenant HTTPS where one listener serves
      multiple virtual hosts.

    - `tcp_tls_reload listener ?hostname cert_path key_path → !v NetErr`
      Atomically swaps the listener's default SSL_CTX (empty
      hostname) OR a matching SNI entry's SSL_CTX with one built
      from the new cert/key files. Per-listener mutex serialises
      the swap against the concurrent accept loop; OpenSSL refcounts
      the old SSL_CTX so in-flight conns that already wrapped an
      SSL handle from it stay valid until they close. Natural
      shape for Let's Encrypt cert rotation triggered from SIGHUP
      or a control endpoint.

    - `tcp_tls_require_client_cert listener ca_bundle_path b strict → !v NetErr`
      Sets `SSL_VERIFY_PEER` on the listener; when `strict` is true,
      adds `SSL_VERIFY_FAIL_IF_NO_PEER_CERT` so the handshake fails
      outright for unauthenticated clients (mTLS-mandatory).
      `tcp_peer_cert_subject TcpConn → String` reads the peer's
      X509 DN in OpenSSL one-line format (e.g.
      "/CN=test-client/O=NURL/C=FI") for the application's
      authorisation decisions.

  Verified live (NURL_NET_TESTS=1):
  `compiler/tests/http_server_tls_extras.nu` runs three sections —
  SNI hostname dispatch (api.example.com → CN=api cert,
  www.example.com → CN=www cert, unknown.example.com → fallback to
  CN=localhost default), live reload (CN=localhost → swap →
  CN=reloaded.example.com), and mTLS (no client cert → rejected,
  valid client cert → 200 OK). All probes driven via `openssl
  s_client` shell-outs.

  Runtime additions in `runtime.c` §18: `NurlTcp` grew
  `sni_entries` + `sni_count` + `sni_cap` + a per-listener
  cross-platform mutex (`pthread_mutex_t` on POSIX,
  `CRITICAL_SECTION` on Windows). Four new C entry points
  (`nurl_tcp_tls_add_sni`, `nurl_tcp_tls_reload`,
  `nurl_tcp_tls_require_client_cert`, `nurl_tcp_peer_cert_subject`).
  `tcp_close` extended to free the SNI registry + destroy the
  mutex; in-flight SSL_CTX refs are released via SSL_CTX_free's
  refcount decrement, so cleanup is safe under concurrent shutdown.

## [0.7.0] — 2026-05-18

Headline: **full HTTP/2 server stack (RFC 9113 + RFC 7541)** lands
alongside **WebSocket (RFC 6455)**, **gzip wire format (RFC 1952)**,
and an **AddressSanitizer + UndefinedBehaviorSanitizer quality gate**.
Three compiler fixes (single-pointer-handle Result coercion, `?u`
match-arm unsigned propagation, `gen_assign` last-type publishing) +
one new language feature (integer-literal match arms) round out the
release. Bootstrap fixed point holds; 0 SAN_FAIL across the 208-test
sanitized corpus.

### Added

* **HTTP/2 server-side (RFC 9113 + RFC 7541).** Four pure-NURL modules
  plus one runtime extension for ALPN. Same `( @ HttpResponse HttpRequest )`
  handler contract as HTTP/1.1 — application code unchanged.

  Modules:
    - `stdlib/ext/http2_frame.nu` (~360 LOC) — binary framing: 9-byte
      header + all 10 frame types + connection preface validation +
      pure round-trip helpers + socket I/O + one-shot senders for
      SETTINGS / PING / GOAWAY / WINDOW_UPDATE / RST_STREAM.
    - `stdlib/ext/http2_hpack.nu` (~900 LOC) — RFC 7541 header
      compression: 61-entry static table + dynamic table with FIFO +
      size-based eviction + N-bit prefix integer codec + string codec
      (literal or Huffman) + all 6 header-field representations +
      complete Huffman decoder covering all 257 Appendix B codes
      across 21 length buckets (5..30 bits).
    - `stdlib/ext/http2_conn.nu` (~770 LOC) — connection + stream
      state machine: SETTINGS exchange + apply, stream state diagram
      per RFC 9113 §5.1 (idle → open → half-closed → closed),
      HEADERS+CONTINUATION assembly with §6.10 interleaving check,
      DATA flow control with connection-level WINDOW_UPDATE
      replenishment, PING/GOAWAY/RST_STREAM dispatch, request
      assembly from HTTP/2 pseudo-headers (:method/:path/:scheme/:authority)
      to the existing HttpRequest shape, response emission with §8.2.2
      hop-by-hop header stripping.
    - `stdlib/ext/http2_server.nu` (~100 LOC) — `http2_serve` +
      `server_run_h2_capable`. The latter accepts a connection,
      checks ALPN selection via `tcp_alpn_protocol`, and routes to
      h2 OR the existing HTTP/1.1 keep-alive loop transparently.

  Runtime extension:
    - `nurl_tcp_listen_tls_alpn(host, port, backlog, cert, key,
      "h2 http/1.1")` — wraps `SSL_CTX_set_alpn_select_cb` over the
      existing TLS listener. Wire-format packing of the server's
      preference list happens C-side. NurlTcp handle gained
      `alpn_wire` + `alpn_wire_len` fields.
    - `nurl_tcp_alpn_selected(handle)` — reads
      `SSL_get0_alpn_selected` post-handshake, returns heap-owned
      NUL-terminated string ("h2" / "http/1.1" / "").
    - NURL surface: `tcp_listen_tls_with_alpn` + `tcp_alpn_protocol`
      in `std/net.nu`.

  v1 scope intentionally excludes:
    * Client-side h2 (symmetric to server; ship when a consumer asks).
    * h2c (HTTP/1.1 → h2 cleartext upgrade — TLS+ALPN is the
      universal modern shape).
    * PUSH_PROMISE / server push (deprecated by RFC 9113 §8.4).
    * PRIORITY frames (obsoleted by RFC 9218 — default ordering OK).

  Verified offline against RFC 9113 §4 framing vectors and
  RFC 7541 Appendix C / C.4.1 HPACK + Huffman vectors via
  `compiler/tests/http2_basic.nu`. Bootstrap fixed point holds.
  ASan + UBSan: 0 SAN_FAIL across the 208-test corpus.

  Usage:
  ```
  : !TcpListener NetErr ll
    ( tcp_listen_tls_with_alpn `127.0.0.1` 8443 16
                               `cert.pem` `key.pem`
                               `h2 http/1.1` )
  ?? ll {
      T listener → {
          : HttpServer s ( server_new listener my_handler )
          ( server_run_h2_capable s )
      }
      ...
  }
  ```

* **Compiler: integer-literal match arms.** `?? value { 1 → ... 42 → ... -1 → ... _ → ... }`
  is now valid wherever `value` has an integer LLVM type (i / i8/16/32/64,
  u/u16/u32/u64). Each arm emits a single `icmp eq <match_type>` and
  branches; the wildcard `_` arm catches the residual (required —
  exhaustiveness is not statically checked across the full integer
  domain). Skips the enum-variant lookup, payload-binding, and
  duplicate-arm tracking paths that named-variant arms exercise.
  `stdlib/ext/http2_hpack.nu`'s 280+ line `? == x N { ^ Y } {}`
  cascade for the HPACK static table + Huffman per-length lookup
  tables was rewritten on top of this and is significantly more
  readable. Regression: `compiler/tests/match_int_literal.nu`.

* **AddressSanitizer + UndefinedBehaviorSanitizer quality gate.** Two
  manual entry points:
    - `./build.sh --san` rebuilds the runtime + every bootstrap stage
      with `-fsanitize=address,undefined -fsanitize-address-use-after-scope
      -fno-omit-frame-pointer -fno-sanitize-recover=all`. LTO is
      dropped because clang's LTO+sanitizer combo produces opaque
      link-time errors on NURL's cross-module function pointers (the
      runtime/user-code inline win isn't the point of a san run).
      LeakSanitizer is disabled during the bootstrap itself
      (`ASAN_OPTIONS=detect_leaks=0`) because nurlc_py/nurlc_self
      intentionally don't free their process-lifetime str-pool /
      sym-arena globals at exit.
    - `compiler/tests/run_san_tests.sh` runs the full .nu corpus
      under the sanitized runtime, captures stdout / stderr per-test
      separately, scans stderr for ASan/UBSan/LeakSanitizer markers,
      and reports `PASS` / `SAN_FAIL` / `COMPILE_FAIL` / `LINK_FAIL`.
      Non-zero exit codes without sanitizer markers count as PASS
      (several tests in the corpus deliberately return computed values
      as exit codes — `native_sum` returns 55, `test_immutable_assign_error`
      aborts to prove the runtime check fires, etc.). Skips
      `should_fail_*` compile-negatives and helper modules without
      `main()`. Leak detection is opt-in via `LSAN_DETECT_LEAKS=1`.

  First sweep result: 188 PASS, 0 SAN_FAIL across 206 tests. The
  infrastructure stays manual — invoke when validating a release
  candidate or triaging a memory-shape bug, not on every build.

* **WebSocket server-side (RFC 6455).** `stdlib/ext/websocket.nu`
  (~570 LOC pure NURL). Composes on the HTTP/1.1 stack: client sends
  `Upgrade: websocket` + `Sec-WebSocket-Key` + `Sec-WebSocket-Version: 13`,
  server validates via `ws_perform_handshake[_with]` and writes the
  `101 Switching Protocols` response, both sides switch to the binary
  frame protocol over the SAME `TcpConn`. TLS works transparently —
  `wss://` routes through `tcp_listen_tls` + the polymorphic `TcpConn`
  SSL dispatch with zero additional code in this module.

  **Surface:**
    - Handshake: `ws_is_upgrade`, `ws_accept_key`,
      `ws_handshake_response_for`, `ws_perform_handshake[_with]`
      (`_with` accepts an optional subprotocol echo).
    - Low-level frame I/O: `ws_serialize_frame` (pure, testable builder),
      `ws_read_frame`, `ws_write_frame`.
    - Convenience writers (server-side, never masked per RFC §5.1):
      `ws_send_text`, `ws_send_binary`, `ws_send_ping`, `ws_send_pong`,
      `ws_send_close i code s reason`.
    - Message reader: `ws_read_message` assembles continuation frames
      per RFC §5.4, auto-pongs incoming pings, surfaces peer close as
      `WsClosedByPeer`. Text payloads validated UTF-8 before return.
    - Serve loop: `ws_serve_messages` reads messages, dispatches to a
      `( @ ! v WsErr WsMessage )` handler, performs the full close
      handshake on exit (mapping errors to RFC §7.4 close codes:
      `WsInvalidUtf8 → 1007`, `WsProtocol*  → 1002`, `WsMessageTooLarge → 1009`,
      everything else `→ 1011`).
    - `WsLimits { max_frame_bytes, max_message_bytes, read_timeout_ms,
      fragment_max_count }`; defaults are 16 MiB / 64 MiB / 60 s / 128.
    - `ws_validate_utf8` (RFC 3629 strict) is exposed publicly — useful
      outside the WebSocket context too.

  **Validation rigour:** RSV1–3 bits must be 0 → `WsProtocolReservedBit`;
  opcode must be in {0,1,2,8,9,10} → `WsProtocolBadOpcode`; control frames
  MUST have FIN=1 (`WsProtocolControlFragmented`) and payload ≤125 B
  (`WsProtocolControlTooLarge`); client→server frames MUST be masked
  (`WsProtocolUnmasked`); text payloads MUST be valid UTF-8 — overlongs,
  UTF-16 surrogates (U+D800-U+DFFF), and codepoints above U+10FFFF all
  rejected; close codes constrained to 1000–4999; the fragment-count
  cap defends against a ping-flood interleaved with continuation frames.

  **Verified against RFC 6455 vectors:**
    - §1.3 accept-key worked example
      (`dGhlIHNhbXBsZSBub25jZQ==` → `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`).
    - §5.7 unmasked text frame `"Hello"` round-trips to
      `81 05 48 65 6c 6c 6f`.
    - Length-encoding transitions: 126-byte payload triggers the 16-bit
      extended-length header; 65536-byte triggers the 64-bit form
      (with the spec-required MSB-clear check on the top byte).

  Regression: `compiler/tests/websocket_basic.nu` (6 sections, 30
  assertions). v1 scope is server-side only — a symmetric client-side
  API is tracked for follow-on work if a real consumer asks. No
  `permessage-deflate` extension; subprotocol header echo is the only
  negotiation surface.

* **SHA-1 in runtime §17** (RFC 3174 self-contained, ~80 LOC). Added to
  enable the WebSocket handshake's `Sec-WebSocket-Accept` derivation;
  exposed via new `sha1_bytes` (length-aware, binary-safe → 20 raw
  bytes) and `sha1_hex` (→ 40-char lowercase) in `stdlib/std/hash.nu`.
  SHA-1 is documented as protocol-compatibility-only — not recommended
  for new security-sensitive code; use `sha256_hex` for that.

* **`stdlib/ext/http_full.nu`** now imports `ext/websocket.nu` so one
  `$`-include brings the full HTTP stack including WebSockets in scope.

### Fixed

* **`signal_basic.nu` — F-arm pattern no longer binds the undef
  Option payload.** The previous `F e → { ( string_free e ) ... }`
  shape passed the F-tag's undef String handle to `string_free`,
  which deep-dispatched into `nurl_peek(NULL, 0)` and tripped UBSan's
  "applying zero offset to null pointer". Replaced with bare `F → ...`
  (Option's None arm carries no data). Surfaced by the first sanitized
  run of the corpus and was a silent crash even outside of ASan
  (`EXIT 139` / `dumped core` in the baseline — now `EXIT 0` cleanly).

* **`stdlib/runtime.c` `nurl_peek` / `nurl_poke` defensively handle
  NULL base.** `nurl_peek` returns 0 instead of dereferencing;
  `nurl_poke` silently no-ops. Safety net for the same caller-side
  mistake the `signal_basic` fix patched at source — a future stdlib
  binding that hands an Option-F-arm payload to a vec-style API will
  log a soft warning under ASan/UBSan but not crash the process.

* **Compiler: `?u → T b →` match-arm now propagates the unsigned flag
  to the payload binding.** `parse_type_opt` stashes the inner-T NURL
  token in `__last_opt_nurl_t__`; `gen_let_or_struct` copies it to
  `<name>__opt_nurl_T`; `gen_match`'s T-arm payload binding tags
  `<pv0>__unsigned = 1` when the inner T is `u` / `u16` / `u32` / `u64`.
  Without this fix the alloca dropped the unsigned-ness and a
  downstream `# i b` cast in the arm body emitted `sext` instead of
  `zext` for high-bit-set bytes, surfacing as wrong hex nibbles in
  `bytes_to_hex` over SHA-1 / SHA-256 digests. `bytes_to_hex` reverted
  from its temporary direct-pointer workaround back to the natural
  `vec_get [u]` + match-arm path.

* **Compiler: `! (Vec u) E` Ok-arm now coerces the i64 payload to the
  `{ ptr }`-shaped single-handle struct.** Two-part fix:
  `parse_type_res` stashes `__last_res_t_llvm__` (LLVM type of T) so
  `gen_let_or_struct` can store `<name>__res_t_llvm` for paren-compound
  T like `( Vec u )` whose NURL-source name is just `(`;
  `gen_match`'s reconstruction path uses it as a fallback after the
  NURL-name lookup fails. Additionally, `coerce_store_val` gained an
  `i64 → single-pointer-handle-struct` case (one-field struct whose
  field 0 is a pointer — covers `Vec[A]`, `String`, `Channel[A]`,
  `Thread`, `Arena`) that wraps via `inttoptr` + `insertvalue` at
  field 0. Without these, `?? r { T pb → @ Frame { … pb } }` over
  `! ( Vec u ) E` generated invalid IR (`insertvalue %Frame, i64`)
  forcing callers into `vec_with_cap + vec_extend` copy workarounds.
  `ws_read_frame` reverted from the copy workaround back to the
  direct payload pass-through.

* **Compiler: `gen_assign` now publishes the LHS type via
  `nurl_set_last_type`.** Without this, an `=`-assignment as the last
  expression of a match arm (`F e → { = err e }`) reported the
  RHS-expression's pre-coerce type to the surrounding `gen_match`,
  causing the phi to be typed for the RHS while the actual stored
  register held the coerced LHS type. LLVM verifier rejected the
  mismatch. Surfaced in `ws_read_frame`'s `?? hdr_r { T … F e → { = err e } }`
  which previously needed a trailing `( nurl_print `` )` to push the
  arm's last-expression type back to void; that workaround removed.

* **Gzip wire format (RFC 1952).** `stdlib/ext/compress.nu` gains
  `gzip_compress` / `gzip_compress_at level` / `gzip_decompress` —
  byte-identical interop with the `gzip` / `gunzip` CLI tools and HTTP
  `Content-Encoding: gzip`. Magic + 10-byte header, raw deflate body,
  CRC-32 + ISIZE trailer, all per RFC 1952. Decompress auto-detects
  gzip OR zlib wire format on the input side (libz's
  `inflateInit2_(windowBits=15+32)`), so a single helper handles both
  shapes coming back from heterogeneous peers. Decompress also reads
  the ISIZE trailer to pre-size the output buffer, avoiding the
  grow-and-retry loop on the common path (sub-4 GB inputs).
  Errors map to the existing `CompressErr` enum
  (`CompressData` / `CompressMemory` / `CompressBufTooSmall` /
  `CompressOther`). Empty input passes through to an empty `Vec[u]`
  with no magic-byte production, matching the zlib/zstd shape.
  Regression: `compiler/tests/compress_gzip.nu` (round-trip + magic
  bytes 0x1f 0x8b 0x08 + level-0 store-only + empty + auto-detect
  zlib + garbage rejection).

* **`runtime.c` §22 — gzip bridge.** `nurl_gzip_compress` /
  `nurl_gzip_decompress` wrap libz's streaming
  `deflateInit2_(windowBits=15+16)` / `inflateInit2_(windowBits=15+32)`
  + `deflate(Z_FINISH)` / `inflate(Z_FINISH)` + matching `End`. ABI
  mirrors `compress2` / `uncompress` (in/out `dst_len`, return 0 on
  success or libz error code on failure; sentinel `-98` when the build
  lacked zlib). The C-side bridge stays because `z_stream`'s sizeof
  and field layout are platform-specific (88 B on Win64 LLP64, 112 B
  on Linux/macOS x64 LP64), and `deflateInit2_` checks an exact-sizeof
  match — mirroring the struct from NURL would be brittle across
  toolchains. Same architectural pattern as the sqlite3 borrowed-view
  bridge: thin, ABI-faithful, no state caching beyond what libz needs.

### Changed

* **`stdlib/ext/compress.nu` header comment** updated: the
  zlib-vs-gzip wire-format gap section now documents the gzip helpers
  shipped alongside, with a pointer to `runtime.c` §22 for the bridge
  rationale.

* **`build.sh`** zlib detection now sets
  `ZLIB_CFLAGS="-DNURL_HAVE_ZLIB ..."` and threads it into the runtime
  compile step so the §22 bridge compiles in when zlib1g-dev is
  present. Without zlib, `nurl_gzip_*` short-circuit to the
  `NURL_GZIP_ERR_UNSUPPORTED` sentinel which the NURL surface maps to
  `CompressOther` — graceful runtime degradation rather than a link
  error.

### Fixed

* **Stale "Quoted CSV Support" roadmap entry closed.** `stdlib/ext/csv.nu`
  has implemented RFC 4180 quoting via the `CSVDialect { delimiter,
  crlf, quote_char }` struct (and the matching `CSVTable` arena's
  `escape_buf`) since the v2 arena rewrite. The roadmap line was a
  leftover from the pre-arena CSV prototype; surfaced and removed
  during the critic-cleanup sweep.

## [0.6.1] - 2025-10-19

### Added

* **Generic propagation through nested structs.** Two generic structs
  side-by-side compose freely: a generic function that returns
  `( Outer A )` while internally allocating `*( Inner A )` and writing
  its fields now compiles, and a generic struct whose field types
  reference another generic (e.g. `Wrap[A] { ( Vec A ) items, … }`)
  emits its inner instantiation before the outer typedef. Fix is in
  `compiler/nurlc.nu` — `emit_one_instantiation` re-scans the
  substituted generic-function body so concrete inner refs trigger
  `ensure_struct_instantiated`, and `ensure_struct_instantiated`
  itself re-scans the substituted generic-struct body for the same
  reason. Bootstrap fixed point holds (stage1 ≡ stage2 byte-identical
  IR at 1 187 843 B). Regression: `compiler/tests/generic_nested_struct.nu`
  (Inner/Outer + Wrap/Vec, both `[i]` and `[s]` instantiations).

* **`Channel[A]` — generic over the element type.** `stdlib/std/channel.nu`
  rewritten on top of the nested-generic fix. `Channel[A] { s ctl }`
  wraps `ChannelImpl[A] { Mutex m, Cond c, ( Vec A ) q, i closed }`;
  every call site supplies the element type via `[A]`
  (`chan_new [i]`, `chan_send [s] ch "hello"`, `chan_recv [i] ch → ?i`,
  etc.). Closes the long-standing v0.3.0 roadmap item that previously
  forced i64-only channels with `# i ptr` for handle payloads.
  `compiler/tests/channel_basic.nu` migrated to the new API (still
  exercises `[i]` so behaviour-equivalent); the regression test above
  exercises both `[i]` and `[s]`. Naming: uses `[A]` (the existing
  stdlib tparam convention) — `T` is the boolean true literal in NURL
  so cannot be a tparam name.

* **Bytes endianness primitives.** `stdlib/std/bytes.nu` gained six
  read helpers and six write helpers covering u16 / u32 / u64 in
  both big-endian (network) and little-endian byte orders:
  `bytes_read_uN_be/_le → ?T` (None when offset is negative or runs
  off the end of the buffer), and `bytes_push_uN_be/_le → v` for the
  symmetric appends. Unblocks binary protocol work (gzip CRC-32 +
  ISIZE trailers, MessagePack header bytes, BSON length prefixes,
  raw network packet headers). Regression:
  `compiler/tests/bytes_endian.nu` (round-trip + boundary values +
  byte-layout sanity + OOB + negative-offset rejection).

### Fixed

* **Nested `??` on a bare-enum value from an `F` arm of `! T E` now
  compiles.** `gen_match` was always emitting `extractvalue` to recover
  the discriminant tag, even when the matched value was already a bare
  scalar (e.g. an `IoErr` bound by `?? r { F e → ?? e { … } }`, where
  `e` is just i64). The pre-existing i1 short-circuit is generalised
  to cover both `i1` AND `i64` match types — `extractvalue` is only
  emitted on aggregate types now. Closes gotcha #6. Regression:
  `compiler/tests/nested_match_enum.nu` (direct `??` on Color, nested
  `??` per-variant on DbErr-from-`! i DbErr`, plus the wildcard arm).

* **Param name shadowing struct field name no longer miscompiles.**
  `gen_field_store`'s struct-pointer branch now routes `= . obj field
  val` to the field-store path when the IDENT after `.` is a
  function parameter AND a registered field of the destination
  struct. Pre-fix the int-width check ran first and treated the
  param as an array index, emitting `getelementptr %S, %S* %obj, i64
  %field` (value-as-index, no field offset). Local non-param int
  variables that coincide with field names — like vec.nu's
  `len`/`idx`/`i` array-store kernels — still route through the
  array path. Closes gotcha #10. Regression:
  `compiler/tests/param_field_shadow.nu` (Box param-shadow positive +
  Pt array-store negative control).

* **`i64` recognised as a type keyword.** The C and Python lexers'
  multi-char TYPE_KW whitelists already covered
  `i8`/`i16`/`i32`/`u16`/`u32`/`u64`/`f32` but not `i64`, so any
  source line writing `: i64 name …` silently took the inferred-type
  branch (`i64` as the binding name, the rest as the value) and
  produced IR with undefined SSA names. `llvm_type` was missing the
  `i64 → i64` row symmetrically — even after the lexer fix, the chain
  fell through to the `%i64` named-type fallback and LLVM rejected the
  resulting `alloca %i64` as unsized. Both ends fixed; closes gotcha
  #7. Regression: `compiler/tests/sized_int_binding.nu` covers
  literal + FFI-call RHS for every sized integer width.

* **Sign-extension when loading bytes from `*u` pointers.**
  `gen_member` now snapshots `__last_unsigned__` before parsing the
  index expression and restores it after the load, so a subsequent
  `# i ( . p k )` cast emits `zext i8 → i64` instead of `sext`. Prior
  to this, a byte with the high bit set (`0x89`, `0xFF`, …) would
  sign-extend to `0xFFFFFFFFFFFFFF89` and silently corrupt
  shift-and-add accumulators in the byte-decoding code that triggered
  the discovery. Covers both the literal-index and variable-index
  load paths; struct-field loads not affected.

### Changed

* **`Channel` is no longer a type alias for the i64 channel.** All
  callers must specify the element type at use site. The single
  in-tree caller (`compiler/tests/channel_basic.nu`) was updated.

## [0.6.0] — 2026-05-16

CSV stdlib consolidates around the arena layout, runtime link-time
optimization lands across the toolchain, and a couple of long-running
infrastructure papercuts get resolved.

### Added

* **`build.sh --no-tests` flag.** Bootstraps the compiler (with the
  byte-identical-IR fixed-point gate still enforced) and exits before
  the test suite. Replaces the older `verbosebuild.sh` script that
  Docker images relied on. `api/Dockerfile` and `nurlapi/Dockerfile`
  both updated to `./build.sh --no-tests`.

* **`nurl.sh` link line — full runtime-feature parity.** The user-
  facing wrapper now auto-links `-lssl -lcrypto` (when
  `stdlib/runtime.openssl` sentinel present), `-lsqlite3`
  (`stdlib/runtime.sqlite3`), and `-lpq` (`stdlib/runtime.pq`) in
  addition to the existing `-lcurl` auto-detection. Mirrors the
  central `build.sh` link line; closes the v0.4.3 follow-up to
  centralise the link-flag set across multiple build scripts.

### Changed

* **Runtime LTO** — `stdlib/runtime.o` is now compiled with `-O2
  -flto`, and every clang invocation that consumes it (`build.sh`,
  `nurl.sh`, `compiler/tests/run_tests.sh`,
  `tools/{nurlfmt,nurl-lsp,nurlpkg}/build.sh`) carries the matching
  `-flto` flag. The LTO link pipeline inlines Vec / String / IO FFI
  calls (`vec_push`, `vec_data`, `vec_reserve`, `nurl_peek/poke`,
  `nurl_parse_int_range`, `cmp_int`, …) across the runtime ↔ user-
  code boundary. Measured on the 1 M-row × 8-col CSV bench (Linux
  i7-5930K, 5 runs median):

  | Stage  | no LTO | LTO    | Δ       |
  |--------|-------:|-------:|--------:|
  | load   | 315 ms | 272 ms | **-14 %** |
  | filter | 146 ms | 139 ms |  -5 %   |
  | sort   |  65 ms |  40 ms | **-38 %** |
  | total  | 529 ms | 451 ms | **-15 %** |

  Sort wins the most because the indexed-permutation comparator was
  bottlenecked on un-inlinable `nurl_parse_int_range` / `cmp_int` /
  `vec_data`. Native binary size dropped 172 888 → 25 408 B (-85 %)
  as LTO drops unused runtime symbols. Bootstrap fixed-point IR
  unchanged (LTO runs at link time only — `nurlc`'s LLVM IR
  generation is invariant) — stage1 ≡ stage2 still at 1 185 386 B.

* **`stdlib/ext/csv.nu` API consolidation.** The legacy v1
  `CSVTable` / `CSVRow` per-cell-malloc layout is gone. The arena-
  backed `CSVTableA` is now THE `CSVTable` — every `csv_table_*`
  call reaches the (offset, length) arena parser directly, and
  RFC 4180 quoting is the default for every load/write. New
  accessor surface:

  - `csv_table_view t row col → s` — zero-copy borrowed pointer
    into the content / escape buffer. NOT NUL-terminated; pair with
    `csv_table_view_len`.
  - `csv_table_view_by_name`, `csv_table_view_len`.
  - `csv_table_get t row col → ?String` — owned-String fallback for
    callers that want an independent lifetime.
  - `csv_table_get_by_name`.

  All sort / filter / truncate / find / select_cols paths wired
  through the arena. Predicate signature for `csv_table_filter` is
  now `( @ b *CSVTable i ) → b` (table + row index) instead of the
  old CSVRow-based shape — match the closure-cached-pointer pattern
  used by `compare/nurl_analysis.nu`. `csv_table_a_*` functions and
  `CSVTableA` deleted outright (no deprecation cycle — NURL is not
  yet in wide enough use). Removed files:
  `stdlib/ext/csv_hoist_test.nu`, `compare/nurl_analysis_arena.nu`,
  `compiler/tests/csv_sort_indexed.nu`, `compare/csv_demo.nu`
  (latter two were duplicates of `csv_arena` / `examples/csv_demo.nu`).
  Callers updated: `examples/csv_demo.nu`, `compare/nurl_analysis.nu`,
  `compare/test_quoting.nu`, `compiler/tests/{csv_arena,
  repro_csv_table_quotes}.nu`. CSV bench at 451 ms (post-LTO) vs
  Polars 95 ms (~4.7×). RFC 4180 quoting verified across read +
  write round-trips.

* **Test framework: skip helper modules.** `compiler/tests/run_tests.sh`
  now skips files matching `*_mod.nu`, `*_helper.nu`, `*_lib.nu` —
  they are imported by other tests and have no `main` function, so
  the old framework recorded them as `COMPILE OK / LINK FAIL` in
  the baseline. Five stale entries removed from `correct.txt`:
  `alias_rewrite_types_mod`, `should_fail_alias_import_mod`,
  `should_fail_group_d_lib`, `should_fail_pub_helper`,
  `should_fail_pub_type_helper`.

### Removed

* **`verbosebuild.sh`** — duplicated `build.sh`'s logic without
  test execution. Folded into `build.sh --no-tests`.

* **`CSVTableA` + every `csv_table_a_*` function** in
  `stdlib/ext/csv.nu` (see "API consolidation" above).

* **`stdlib/ext/csv_hoist_test.nu`** — stranded Phase 2c hoist
  experiment, never imported by any caller.

## [0.5.0] — 2026-05-16

The package manager lands. `nurlpkg` is a Cargo-shaped CLI that
covers the full dependency lifecycle: scaffold a manifest, declare
dependencies, resolve them transitively, lock the resolution, and
verify the lockfile hasn't drifted. This release also ships the
TOML and Manifest stdlib modules that back the package manager,
plus a new `fs_symlink` primitive in `stdlib/std/fs.nu`.

### Added

* **`tools/nurlpkg/` — NURL package manager.** Single-binary CLI
  with ten subcommands:

  - `nurlpkg init <name>` — write a `nurl.toml` skeleton (refuses
    to overwrite an existing one).
  - `nurlpkg info` — pretty-print the typed manifest fields.
  - `nurlpkg deps` — list each `[dependencies]` entry, one per
    tab-separated line (pipe-friendly).
  - `nurlpkg add <name> [--path P] [--version V]` — append a
    dependency to `[dependencies]` via surgical text edit
    (preserves user comments and formatting; refuses duplicates).
  - `nurlpkg remove <name>` — delete a dependency entry the same
    way (errors if the name isn't declared).
  - `nurlpkg install` — BFS-resolve every path-based dependency
    transitively, create `deps/<name>` symlinks via libc's
    `symlink(2)`, regenerate `nurl.lock` as a side effect.
    Idempotent: rerunning on a fully-installed tree returns 0
    silently. Diamond dependencies dedupe.
  - `nurlpkg lock` — regenerate `nurl.lock` from the on-disk
    `deps/` tree without reinstalling.
  - `nurlpkg verify` — compare `deps/` against `nurl.lock` and
    exit 1 on any drift (missing entries OR unexpected entries).
    Intended for CI / pre-build gates.
  - `nurlpkg version` / `--version` — print the nurlpkg version.
  - `nurlpkg help` — usage.

* **`stdlib/ext/toml.nu` — TOML parser.** Recursive-descent parser
  producing a `TomlValue` tagged-union tree (`TStr` / `TInt` /
  `TBool` / `TArr` / `TTable`). Handles both `[section]` headers
  and `[[array.of.tables]]`, inline tables, dotted keys, and
  comments. Used internally by the package manager but also
  available to any stdlib consumer.

* **`stdlib/ext/manifest.nu` — typed manifest view.** Pulls the
  well-known `[package]` and `[dependencies]` fields out of a
  TomlValue tree into a typed `Manifest { name, version,
  description, license, Vec[Dep] dependencies }`. Single-table
  inline-table dep form and bare-string version form both
  supported. Returns `! Manifest ManifestErr` with a small set of
  named error variants (ReadFailed / ParseFailed / MissingName /
  MissingVersion / BadShape).

* **`fs_symlink s target s linkpath → !v IoErr` (stdlib/std/fs.nu).**
  Thin wrapper over libc's `symlink(2)` exposed via pure-NURL FFI
  (`& \`c\` @ symlink → i32`). POSIX-only; Windows callers should
  fall back to copying since `CreateSymbolicLinkW` needs a
  privilege most accounts lack.

* **Regression tests.** `compiler/tests/toml_basic.nu` covers the
  parser; `compiler/tests/manifest_basic.nu` covers the typed
  manifest extraction (well-formed + missing-required-field
  cases).

### Compiler quirks documented (workarounds in place)

Two codegen issues surfaced while writing the package manager and
remain as quirks until separately addressed:

* **Nested `??` on an enum value extracted from `! T E`** emits
  `extractvalue` on an `i64`, which is invalid LLVM. Workaround:
  flatten with `?` + `==`, or restructure to avoid needing the
  inner match (`__cmd_install` checks `file_exists` before
  `dir_create` to skip the `AlreadyExists` arm entirely).

* **Width-suffixed FFI return bindings** (`: i64 n ( ffi_call … )`)
  emit `store i64 %n, …` before the call defines `%n`, producing
  "use of undefined value." Workaround: bind FFI integer returns
  to `: i n (…)` (the default 64-bit type).

## [0.4.4] — 2026-05-16

LSP server gains the last three "quick win" features and the
Language Server protocol surface is now feature-complete enough
for daily editor use without falling back to other tooling.

### Added

* **`textDocument/formatting`** — pipes the active buffer through
  `build/nurlfmt --stdin` and returns a single TextEdit covering
  the entire document. `Shift+Alt+F` in VS Code triggers it. Uses
  `process_run`'s stdin_str parameter — no temp file needed.

* **`workspace/symbol`** — fuzzy-search across every indexed
  top-level symbol (functions, struct/enum types, enum variants,
  global constants, FFI symbols). Case-insensitive substring
  match, empty query returns the full set. `Ctrl+T` / `Cmd+T` in
  VS Code. Reuses the `g_all_names :list` TSV index built by the
  decl scanner.

* **`textDocument/foldingRange`** — emits FoldingRange for every
  multi-line `{ … }` block. Backtick strings and `//` comments are
  skipped so braces inside them don't confuse the matcher.
  Single-line blocks (e.g. `{ ^ 0 }`) are filtered out. Nested
  blocks each get their own range so the editor can fold any
  level independently.

## [0.4.3] — 2026-05-16

Tier D ecosystem advances on two axes: a working **Language Server**
(`nurl-lsp`) with the five most-used IDE features wired end-to-end,
and a small but generally-useful binary-stdin primitive in core/io.

### Added

* **NURL Language Server (`tools/nurl-lsp/`).** Stdio JSON-RPC server
  written in NURL itself, wired to VS Code / Windsurf through the
  refreshed `tooling/vscode-nurl` extension (v0.3.0). Features:
  - Live compile-driven **diagnostics** on `didOpen` / `didChange`
    (errors + warnings stream from `nurlc` stderr into LSP
    `publishDiagnostics`).
  - **Go-to-definition** across files. Transitive `$`-import index
    populated per workspace; jump works for `@`-functions,
    struct/enum types, enum variants, global `:` constants, and
    `& \`lib\`` FFI symbols.
  - **Document outline** (`textDocument/documentSymbol`) with the
    right `SymbolKind` per decl shape — visible in VS Code's
    Outline panel and via `Ctrl+Shift+O`.
  - **Hover** popups (`textDocument/hover`) showing the symbol's
    kind label, signature line (Markdown-formatted code block),
    and source location.
  - **Completion** (`textDocument/completion`) filtered by the
    IDENT-prefix immediately left of the cursor. `CompletionItemKind`
    mapping covers the same five decl shapes.

  Build: `./tools/nurl-lsp/build.sh` produces `build/nurl-lsp`.

* **`stdlib/core/io.nu read_n_bytes i n → ( Vec u )`.** Owned-Vec
  binary stdin reader. Used by the LSP server's `Content-Length`
  framing; useful for any framed-protocol consumer (DAP, raw
  JSON-RPC, length-prefixed RPC). Backed by `nurl_read_n_bytes` in
  `runtime.c §1` — single `fread` + side-channel byte count via
  the existing `nurl_last_bytes_len`.

* **`tooling/vscode-nurl` extension v0.3.0.** Spawns `nurl-lsp` over
  stdio via `vscode-languageclient`. Server-path fallback order:
  `nurl.server.path` setting → `<workspaceFolder>/build/nurl-lsp` →
  PATH lookup for `nurl-lsp`. Graceful syntax-only fallback when no
  binary resolves. New configuration knobs `nurl.server.path` and
  `nurl.server.trace`. Packaged as `nurl-0.3.0.vsix`.

### Fixed

* **`tools/nurlfmt/build.sh` linker line.** The formatter's build
  script was matching only the libcurl sentinel; missing
  openssl / sqlite3 / libpq linker flags led to `undefined reference
  to TLS_server_method` once OpenSSL was wired into the runtime.
  Now mirrors `tools/nurl-lsp/build.sh` and the central `build.sh`
  by checking all four runtime sentinels (`stdlib/runtime.{curl,
  openssl,sqlite3,pq}`) and appending the corresponding `pkg-config
  --libs` to the link line. Same pattern that breaks when a new
  runtime dependency is added across multiple build scripts —
  centralising into `tools/_link_flags.sh` is a follow-up.

## [0.4.1] — 2026-05-15

### Fixed

* **WASI build: gate setjmp/longjmp + clock() that wasi-sdk rejects.**
  The v0.4.0 panic model `#include <setjmp.h>` made `runtime.c`
  unbuildable under `--target=wasm32-wasi` (wasi-sdk's setjmp.h
  errors out unless `-mllvm -wasm-enable-sjlj` is set against the
  unfinalised Wasm Exception Handling proposal). Same for `clock()`,
  which is deprecated on wasi-sdk without `_WASI_EMULATED_PROCESS_CLOCKS`.
  Both are now `#ifndef __wasi__`-guarded. On WASI, `nurl_recover`
  degrades to "run-the-closure-inline, return 0"; `nurl_panic` prints
  the message and aborts (same shape as the no-frame path on native
  targets); `nurl_panic_last_msg` returns `""`. The degraded recover
  semantics line up with WASI's other single-threaded fallbacks
  (signals, processes, threads). Native builds unchanged — bootstrap
  fixed point still at 1 184 466 B.

## [0.4.0] — 2026-05-15

Tier A correctness/safety holes from the v0.3.0 external review all
closed; Tier B HTTP production-hardening complete end-to-end (TLS
1.2+, per-request timeout, configurable parser limits, handler panic
recovery); Tier C module-system extended (`pub` for types/enums/
consts, alias rewrite for everything); Tier D ecosystem advanced
(SQLite + PostgreSQL FFI, compile-time FFI library check).

The full per-feature breakdown follows; ROADMAP.md keeps an
engineering-narrative log per ship.

### Added

* **PostgreSQL FFI in `stdlib/ext/postgres.nu` (pure-NURL).** First
  example of the **runtime-less FFI model**: every libpq symbol is
  declared directly via `& `pq` @ ... → ...` — no `runtime.c` bridge.
  Surface: `pg_connect / _close / _err_msg / _exec / _exec_params /
  _result_status / _result_is_ok / _ntuples / _nfields / _get_value /
  _get_is_null / _field_name / _clear`. `pg_exec_params` accepts a
  `Vec[String]` and builds the parallel `char **` pointer array for
  libpq. v1 scope: text format only, no async, no LISTEN/NOTIFY, no
  COPY streaming. Build-time dep detected via `pkg-config --exists
  libpq`; missing → clear compile-time error from the new lib-check
  (below). Regression: `compiler/tests/postgres_basic.nu`
  (NURL_PG_TESTS=1 + PG_CONNINFO=... to enable).

* **Compile-time FFI library presence check
  (`__ffi_lib_check`).** Every `&`-FFI library name is normalised
  (strip `lib`-prefix, whitelist always-linked system libs `c` / `m` /
  `pthread` / `dl`) and checked against `stdlib/runtime.<lib>`
  sentinels written by `build.sh`. Missing sentinel → die at the
  `&`-decl site with `FFI library '<name>' is required but no
  build-time sentinel '...' found - install lib<name>-dev (or
  equivalent) and run build.sh again`. Replaces cryptic linker errors
  like `undefined reference to PQconnectdb`. Smoke-validated by moving
  `stdlib/runtime.pq` aside and recompiling a postgres-using program.

* **SQLite FFI in `stdlib/ext/sqlite.nu`.** Thin wrapper over
  libsqlite3 with idiomatic `! T SqliteErr` returns. Surface:
  `sqlite_open / _close / _exec / _prepare / _bind_int / _bind_text /
  _bind_null / _step / _column_count / _column_type / _column_int /
  _column_text / _reset / _finalize`. `: Database` / `: Statement`
  value handles, `: | SqliteErr` with 9 variants. `sqlite_step`
  returns `!b SqliteErr` (T=Row, F=Done). v1 scope: int64 + text
  binds/columns only (no BLOB / double), no transaction helpers, no
  statement cache, no ATTACH — those compose with raw SQL. Build-
  time dep detected via `pkg-config --exists sqlite3`; without it,
  every entry returns `SqliteUnsupported`. Runtime side at
  `stdlib/runtime.c §21`. Regression: `compiler/tests/sqlite_basic.nu`
  (in-memory CRUD round-trip with prepared statement reuse).

* **Import alias rewriting extended to types, enum variants, and
  global constants.** `$ `path` alias` now renames every top-level
  decl in the imported file to `alias__name`, not just `@`-functions.
  Use sites reach them with `alias::Name`, which the lexer merges into
  the single IDENT `alias__Name`. FFI declarations and trait/impl
  methods are NOT renamed — FFI is linker-level ABI, trait dispatch is
  type-mangled. `collect_alias_targets` grew handling for `:` /
  `: |` / `: TYPE_KW` / `pub` prefixes. Regression:
  `compiler/tests/alias_rewrite_types.nu` + helper module.

* **`pub` visibility for structs, enums, and global constants.**
  Extends the v2.0 `pub @ greet` rule that already covered `@`-fns to
  cover `pub :`, `pub : |`, and `pub : i FOO 7` declarations. Enum
  variants inherit the parent enum's visibility (no per-variant
  syntax). Enforcement at parse_type_base (cross-file `%Name`
  resolutions) and gen_ident (cross-file `__global` loads). FFI and
  trait/impl decls accept `pub` forward-compat but don't enforce
  (FFI is an ABI contract; trait dispatch is type-mangled, not name-
  routed). Diagnostic: `private type 'X' is not visible across files;
  defined in 'Y'` (and the `global` / `function` variants on the same
  template). Regressions: `pub_type_visibility.nu` (positive) +
  `should_fail_pub_type_neg` / `_const_neg` / `_variant_neg` +
  `should_fail_pub_type_helper.nu` (shared helper).

  **Strategic value:** package management now has the public API
  surface it requires.

### Changed

* **`parse_request_head` now returns `! ParsedHeadOk HttpReqErr`**
  (was `ParsedHead { head, consumed, ok, err }`). The v0.3.0-era
  tagged-struct workaround for the multi-field-Result-Ok-arm hole is
  gone — heap-boxing of multi-field Ok payloads shipped 2026-05-14
  unblocked the idiomatic shape. Callers in `stdlib/ext/http_server.nu`
  (`__read_request_head` + keep-alive loop), `stdlib/ext/http_proxy.nu`
  (`proxy_serve_run_with`), and `compiler/tests/http_request_parser.nu`
  migrated from `? . ph ok / .ph err` branching to `?? ph { T pho → ...
  F e → ... }`. `parsed_head_free` and `__parsed_head_err` removed —
  the new shape needs neither. Bundled cleanup: stale `vec_get [Header]`
  miscompile comments in `header_get` / `__parse_headers` updated to
  reflect current reality (the miscompile shipped a fix May 14;
  direct-pointer iteration is retained where it's still the right
  shape, not as a workaround).

### Added

* **Panic model + HTTP handler panic recovery.** New
  `stdlib/std/panic.nu` module: `panic s msg → v` for explicit aborts,
  `recover ( @ v ) closure → ! v PanicInfo` for setjmp/longjmp-based
  catch. Built on `nurl_recover` / `nurl_panic` / `nurl_panic_last_msg`
  runtime primitives (`stdlib/runtime.c` §20, thread-local jmp_buf
  stack). NOT Rust-style stack unwinding — owned allocations inside a
  recover scope that don't run their auto-drop **leak**. Signal faults
  (SIGSEGV / SIGFPE / SIGBUS) are NOT caught. Recover is crash-
  mitigation, not a routine error path. HttpServer's
  `__serve_keepalive_loop` wraps the handler call in `recover`: panic
  in the handler → server logs the message to stderr + substitutes
  a stock 500 response + keeps serving. Compiler fix bundled:
  `simple_capture_analysis` now captures assignment targets as well
  as read references — the recover-with-byref-capture pattern depended
  on it (pre-fix the closure body referenced the outer's alloca
  register directly, producing invalid IR). Regressions:
  `compiler/tests/recover_basic.nu` (offline; Ok / panic / typed-byref
  round-trip cases) and `compiler/tests/http_server_panic.nu`
  (NURL_NET_TESTS=1).

* **TLS (server-side) via libssl/OpenSSL.** `tcp_listen_tls host port
  cert_path key_path → !TcpListener NetErr` in `stdlib/std/net.nu` is a
  drop-in replacement for `tcp_listen`; `NurlTcp` runtime struct made
  polymorphic via `SSL *ssl` + `SSL_CTX *ssl_ctx` fields, so
  `nurl_tcp_read` / `_write` / `_close` dispatch via libssl when the
  handle was wrapped at listen time. **HttpServer integration is zero
  code changes** — callers just swap the listener constructor. TLS
  1.2 minimum. Build-time dependency detected via `pkg-config --exists
  openssl`; without it, calls return `NetTlsCtxInit`. v1 scope: no
  SNI, no ALPN, no client-cert auth, no live cert reload. New `NetErr`
  variants: `NetTlsCtxInit` / `NetTlsCertLoad` / `NetTlsKeyLoad` /
  `NetTlsHandshake`. Regression:
  `compiler/tests/http_server_tls.nu` (NURL_NET_TESTS=1; generates a
  self-signed cert at setup time).

* **HTTP server Phase 8 closed out.** Two production-hardening items
  shipped:
  - *Configurable parser limits* via new `HttpLimits { i head_max_bytes,
    i header_max_count, i body_default_max }` struct + `http_default_limits`
    ctor in `stdlib/ext/http_request.nu`. `parse_request_head_with` /
    `__parse_headers` / `__finish_body` plumbed; `HttpServer` extended
    with an `HttpLimits limits` field; new `server_new_complete`
    constructor exposes every knob. Existing `server_new` / `_with_timeout`
    / `_full` keep v0.3.0 defaults so every existing call site builds
    unchanged.
  - *Per-request total timeout* via new `HttpServer.request_total_timeout_ms`
    field (0 = disabled). `__serve_keepalive_loop` snapshots `now_ms`
    after each head parse; if the handler runs over budget, its response
    is dropped and a stock 504 sent instead with forced `Connection:
    close`. Enforcement is post-handler only (NURL has no thread-
    cancellation primitives) — per-conn idle timeout still covers slow
    reads.

  Acceptance: `compiler/tests/http_server_limits.nu` (NURL_NET_TESTS=1).
  Mirror call site in `stdlib/ext/http_proxy.nu` uses
  `http_default_limits`.

* **Compiler warnings for `docs/GOTCHAS.md` items 3 + 8.** Two
  non-fatal `warning:` diagnostics now surface the two soundness-
  adjacent foot-guns flagged by the v0.3.0 external review:
  - *Same-line parameter shadowing* (`: i z + z 7` where `z` is a
    function parameter): per-fn `__fn_param_names__` roster shadowed
    inside closure bodies so the check stays scoped. Zero false
    positives across the entire stdlib + compiler + test corpus.
  - *Closure-byref escape on `^`-return*: closures that take a
    `: ~`-mutable multi-field capture by pointer (via the existing
    `__is_capture_byref` predicate) get tagged with
    `__last_closure_byref__` at the closure-literal site; the tag is
    propagated onto the binding (`<name>__captures_byref`) by
    `gen_let_or_struct`; `gen_ret` reads either form and emits the
    warning. `vec_push` / `thread_spawn` escape sites are NOT yet
    checked (documented as follow-up).

  New `should_warn_*` test category in `compiler/tests/run_tests.sh`:
  compile stderr is captured into a `WARNINGS` block (absolute paths
  stripped via `sed $ROOT_DIR/`). Regressions:
  `compiler/tests/should_warn_param_shadow.nu` and
  `compiler/tests/should_warn_closure_escape.nu`. `docs/GOTCHAS.md`
  items 3 + 8 marked "Compiler-warned 2026-05-15" in the quick-ref
  table.

### Fixed

* **`$`-import dedup keys are now canonicalised.** Pre-existing dedup
  tables in three compiler passes (`scan_generic_structs`,
  `scan_fn_sigs`, `gen_import_decl`) keyed on the raw path string, so
  `$ \`stdlib/x.nu\`` and `$ \`./stdlib/x.nu\`` (same physical file,
  different strings) defeated the dedup and produced `redefinition of
  type` errors at link. New `__norm_import_path` helper strips leading
  `./` segments at every `$`-path read site. Symlink-equivalent paths
  still collide as separate imports (no realpath FFI yet —
  intentionally deferred). Acceptance:
  `compiler/tests/import_dedup.nu`. README "Known Limitations" updated
  to drop the stale "no duplicate-include guard" / "alias parsed but
  ignored" claims (alias DOES rewrite top-level `@`-fns; dedup HAS
  worked for exact-string matches since the original `$`-import
  implementation).

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

[Unreleased]: https://github.com/nurl-lang/nurl/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/nurl-lang/nurl/compare/v0.7.3...v0.8.0
[0.2.0]: https://github.com/nurl-lang/nurl/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nurl-lang/nurl/releases/tag/v0.1.0
