# Changelog

All notable changes to NURL — Neural Unified Representation Language —
are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.9.5] — 2026-06-04

### Added

- **Playground shows its deployed version, and the API auto-deploys on
  release tags.** The playground header now carries a version pill — a
  `__NURL_VERSION__` placeholder in `index.html` is stamped at image-build
  time from the `NURL_VERSION` build-arg (`dev` for local builds). A new
  `.github/workflows/api-deploy.yml` builds the API image on a `v*` tag (or
  manual dispatch), pushes it to Docker Hub under the exact semver
  (`nurllang/nurl:vX.Y.Z` — no `:latest`), pins `cloudflare/Dockerfile`'s
  `FROM` to that tag and runs `wrangler deploy`, so a git tag is now a
  reproducible playground release. The Docker image was renamed
  `hindurable/nurl` → `nurllang/nurl`; `registry-deploy.yml` is now
  manual-only (the registry changes rarely).

- **MQTT-over-WebSocket transport — `mqtt_connect_ws`.** Adds a WebSocket
  transport alongside the raw TCP/TLS path so a client can reach a broker's
  MQTT-over-WS endpoint (e.g. `wss://host:8084/mqtt`) — handy when a firewall
  only permits the WS port inbound. `wss://` enables TLS with certificate
  verification and negotiates the `mqtt` subprotocol automatically; the codec
  and framed packet reader stay transport-blind behind two chokepoints. New
  entrypoints `mqtt_connect_ws` / `mqtt_connect_ws_cfg`; `mqtt_disconnect`
  also sends a WS Close frame, and `mqtt_reconnect` rejects WS clients (no URL
  to redo the upgrade). `stdlib/ext/mqtt.nu`.

- **Package manager → MLP: login/search/info, yank, token-revoke, catalog UI
  (ROADMAP §4).** Rounds the registry out into a minimum *lovable* product.
  - **CLI ergonomics.** `nurlpkg login` stores a per-registry publish token
    in `~/.nurl/credentials` (chmod 600) — `publish`/`yank` resolve the token
    `$NURL_TOKEN` → credentials, so it no longer has to live in the
    environment. `nurlpkg logout [--revoke]` forgets it (and optionally
    revokes it server-side). `nurlpkg search <q>` and `nurlpkg info <name>`
    query the registry (`info` with no arg still prints the local manifest).
    New `stdlib/ext/credentials.nu`.
  - **Registry hygiene.** `nurlpkg yank|unyank <name> <version>` flips a
    version's yanked flag (owner-only, via `POST /api/v1/{yank,unyank}`); the
    resolver already skips yanked versions, so a yanked release disappears
    from resolution. `nurlpkg logout --revoke` (`POST /api/v1/revoke`) deletes
    the presented token from D1.
  - **Catalog UI.** The Worker's `/` is now a searchable package list and
    `/packages/<name>` a detail page (versions with yank state, latest
    dependencies, an install snippet); `GET /api/v1/search?q=` backs the CLI.
  - Client helpers: `pkg_search` (`pkg_fetch.nu`), `pkg_yank` / `pkg_revoke`
    (`pkg_publish.nu`). Regression `compiler/tests/credentials_basic.nu`
    (set/get/upsert/multi-registry/remove; gated `NURL_CREDS_TESTS=1`, clean
    under ASan/UBSan). Whole feature set verified end-to-end against the
    Worker under `wrangler dev`: login → creds-based publish → search → info
    → yank (install then fails ResolveNoMatch) → unyank → catalog → logout
    --revoke → publish rejected (PubAuth).

- **Transitive registry dependencies — `nurlpkg publish` sends `X-Nurl-Deps`.**
  Publishing now includes the manifest's registry dependencies (a JSON
  `[{name, req}]` built by `__deps_json`) as the `X-Nurl-Deps` header, which
  the registry records in the package index. `pkg_publish` gained a
  `deps_json` parameter. With the deps in the index, `resolve_registry`
  pulls **sub-dependencies transitively** — previously the index always
  recorded `deps: []`, so only leaf registry packages installed correctly.
  Verified end-to-end against the local Cloudflare Worker: publish `tdep-b`,
  publish `tdep-a` (depends on `tdep-b ^1.0`), then `install` a consumer of
  only `tdep-a` → both land in `deps/` and the lock. Registry now supports
  real dependency graphs. `stdlib/ext/pkg_publish.nu`, `tools/nurlpkg/main.nu`.

- **Package registry service — Cloudflare Worker + R2 + D1 (`registry/`,
  ROADMAP §4 phase 6).** The deployable server side of the ecosystem, in
  TypeScript. The read path serves the static `index/<name>.json` +
  content-addressed `pkgs/<name>/<name>-<v>.tar.gz` from R2 (cacheable, no
  compute); the write path `POST /api/v1/publish` authenticates a Bearer
  token (peppered SHA-256 looked up in D1), enforces **first-publisher name
  ownership** + **version immutability**, **recomputes the tarball SHA-256
  server-side** (never trusts a client digest), and writes the tarball +
  updated index to R2. Identity bootstraps via **GitHub OAuth** (`/login` →
  `/auth/callback` mints a one-time CLI token). D1 schema in
  `migrations/0001_init.sql` (users / tokens / packages / versions).
  Implements exactly the wire contract the NURL client already drives.
  **Validated end-to-end locally** (no Cloudflare account): under
  `wrangler dev` (miniflare R2 + D1), the real `nurlpkg` binary completes a
  full publish → install round-trip plus immutability (409) and bad-token
  (401) rejections — `registry/test-local.sh`. Ships with
  `registry/DEPLOY.md`, a `registry-deploy.yml` GitHub Actions workflow
  (guarded so a placeholder token can't trigger a broken deploy), and
  secrets kept out of the repo (`wrangler secret put` for
  `GITHUB_CLIENT_SECRET` / `TOKEN_PEPPER`; GH Actions secrets for the
  Cloudflare deploy token). This completes the registry-backed package
  manager: `nurlpkg publish` + `nurlpkg install` against a deployable
  registry, all pure-NURL on the client and standing up locally today.

- **Package publishing — `stdlib/ext/pkg_publish.nu` + `nurlpkg publish`
  (ROADMAP §4 phase 5).** The write side. `pkg_pack` walks a project tree
  into a `.tar.gz` (excluding `deps`, `.git`/dotfiles, `nurl.lock`,
  `target`, `build`); `pkg_publish` uploads it with `POST
  <registry>/api/v1/publish`, `Authorization: Bearer <token>`, and
  `X-Nurl-Package` / `X-Nurl-Version` headers (binary body via
  `http_request_bytes`), mapping status to PubAuth (401/403) / PubConflict
  (409, version immutability) / PubRejected. `nurlpkg publish` packs the
  current project, prints its size + SHA-256, and uploads using the token
  from `$NURL_TOKEN` and the registry from `$NURL_REGISTRY` →
  `[package].registry` → default; a missing token or any non-2xx exits
  non-zero. The registry recomputes the checksum server-side — no
  client-supplied digest is trusted. Regression
  `compiler/tests/pkg_pack_basic.nu` (offline pack + gunzip + tar_parse
  membership: nested source included, deps/ + dotfiles excluded), clean
  under ASan/UBSan + leak-free. Verified end-to-end against a static
  `python` registry: a full **publish → install round-trip** (a library
  packed, uploaded with a Bearer token, then resolved + installed into a
  consumer's `deps/`), plus immutability (409), bad-token (401), and
  no-token rejections. This is the exact contract the Cloudflare
  Worker + R2 write endpoint (phase 6) will implement.

- **Verified registry install — `stdlib/ext/pkg_fetch.nu` (ROADMAP §4
  phase 4b).** The I/O side that turns a resolved `LockPkg` into files on
  disk against a static-HTTP registry (R2 + CDN shape). `pkg_fetch_index`
  GETs `<registry>/index/<name>.json`; `pkg_install_one` downloads
  `<registry>/pkgs/<name>/<name>-<v>.tar.gz`, **verifies its SHA-256
  against the recorded checksum**, gunzips, and path-safe `tar_unpack`s it
  into `<dest>/<name>` — composing the whole pure-NURL package stack (http
  binary body + sha256 + gzip + tar). Capstone regression
  `compiler/tests/pkg_install_e2e.nu` stands up a **loopback NURL registry
  server** (serves a real `tar_create`+`gzip` tarball + an index carrying
  its true checksum) and drives the full pipeline resolve → download →
  verify → unpack end-to-end, plus a wrong-checksum rejection
  (PkgChecksumMismatch); `NURL_NET_TESTS=1`. Clean under ASan/UBSan.

  **`nurlpkg install` is now registry-aware.** It resolves the manifest's
  registry deps (`foo = "^1.2"` or `{ version, registry }`), downloads +
  verifies + unpacks each into `deps/<name>`, and writes a `nurl.lock`
  whose registry entries carry `source = "registry+<url>"` + the tarball
  `checksum` (path deps keep their local source). The registry URL comes
  from `$NURL_REGISTRY` → `[package].registry` → a built-in default. A
  failed download or checksum mismatch makes `install` exit non-zero.
  Verified end-to-end against a static `python -m http.server` registry
  serving a GNU-`tar --format=ustar | gzip` package (differential interop):
  the happy path installs + locks with the `sha256sum`-computed checksum,
  and a tampered index checksum is rejected with the package left
  uninstalled.

- **Binary-safe HTTP response body — `http_body_bytes` / `http_body_len`.**
  `http_body_str` reads the response body through a NUL-terminated carrier
  (truncates at the first embedded NUL). The new `http_body_bytes` returns
  an owned, length-accurate `( Vec u )` copy, and `http_body_len` exposes
  the byte count — required for binary downloads (package tarballs, images,
  compressed payloads). Completes the binary HTTP story alongside the
  earlier binary-safe request body. Regression:
  `compiler/tests/http_response_binary.nu` (loopback server replies a
  5-byte `A B \0 C D` body; client confirms full length + the NUL via
  `http_body_bytes`; `NURL_NET_TESTS=1`). Clean under ASan/UBSan.
  `stdlib/ext/http.nu`.

- **Registry resolution core — `stdlib/ext/registry_index.nu` +
  `stdlib/ext/resolver.nu` (ROADMAP §4 phase 4).** The read side of the
  package registry. A registry serves a static JSON index per package at
  `<registry>/index/<name>.json` (versions, each with a tarball SHA-256
  `checksum`, `yanked` flag, and `deps`); tarballs live at the
  content-addressed `<registry>/pkgs/<name>/<name>-<ver>.tar.gz`, so the
  whole read path is a cacheable CDN with no compute.
  `registry_index.nu` parses an index and `regindex_select` picks the
  highest non-yanked version satisfying a semver requirement.
  `resolver.nu`'s `resolve_registry` walks the transitive dependency graph
  (BFS) and emits a `Vec[LockPkg]` ready for `lock_serialize` — the index
  fetcher is injected as a closure (`name → index-JSON`), so resolution is
  pure and offline-testable; nurlpkg will wire it to an HTTP GET. v1 policy:
  one version per name (first requirement wins; a later one must share that
  version or it's ResolveConflict), sub-deps from the parent's registry,
  path deps left to the existing symlink installer. Regressions:
  `compiler/tests/registry_index_basic.nu` (parse + select + yanked
  exclusion + tarball URL) and `compiler/tests/resolver_basic.nu`
  (transitive resolve with a mock index, ResolveNoMatch, ResolveNotFound).
  Both clean under ASan/UBSan and leak-free.

### Changed

- **Signedness is now coupled to the value's type instead of a free-floating
  side-channel — the structural fix for the whole `u`-vs-signed-`i8` bug
  class.** The LLVM type (`i8`/`i16`/`i32`) can't distinguish NURL's unsigned
  `u`/`u16`/`u32` from the signed types, so signedness travelled in a
  separate `__last_unsigned__` syms entry that each of ~83 value-producing
  sites had to remember to update — and ~67 didn't, leaving a stale flag
  that silently sign- or zero-extended the next widen (the source of a long
  run of miscompiles). Now signedness lives in `g_last_unsigned_p` right
  next to `g_last_type_ptr`, and **`nurl_set_last_type` always resets it**
  (signed default): every value-producing site already calls the type-setter
  (IR needs the type), so a stale "unsigned" can no longer leak. The handful
  of unsigned-PRODUCING sites assert it atomically with the type via
  `nurl_set_last_type_u` / `nurl_mark_unsigned`, and widen/op-selection
  readers consult `nurl_last_unsigned`. This eliminated the stale-leak
  subclass structurally; the migration also surfaced and fixed a latent gap
  the old leaky channel had masked by accident — bitwise `&`/`|`
  (`gen_bitwise_binary`) never set its result's signedness, relying on the
  last operand's flag happening to survive. Net: fewer, simpler, faster
  (a global vs a string-keyed map) and no longer forgettable. Bootstrap
  fixed point holds; full suite + ASan/UBSan green; 500 fuzzer seeds clean
  across every dimension.

### Fixed

- **Two more silent unsigned-widening miscompiles** (same `__last_unsigned__`
  side-channel hazard; fixed in `compiler/nurlc.nu`). Regression
  `compiler/tests/const_ternary_signedness.nu` (7 known-answer checks).
  1. **An unsigned global const load sign-extended.** `# i GU` over
     `: u GU 200` gave −56. `gen_const_decl` now records `<const>__unsigned`
     (which `gen_ident` already turns into `__last_unsigned__` on load).
  2. **A `?` (ternary) result didn't carry its arms' signedness.**
     `# i ? c (# u 200) (# u 100)` sign-extended the selected value.
     `gen_cond` now snapshots each arm's `__last_unsigned__` and sets the
     result flag (the arms share a type, so either suffices).

- **A call to an unsigned-returning function sign-extended at the call
  site.** `# i ( f )` where `f → u` returns 200 gave −56 (and likewise for
  `u16`/`u32`): the call site never carried the callee's return signedness
  onto the `__last_unsigned__` side-channel the enclosing widening cast
  reads (the LLVM return type i8/i16/i32 can't distinguish `u` from `i8`).
  `scan_fn_sigs` now records `<fn>__ret_unsigned` in the persistent pre-pass
  symbol table (the per-function `gen_fn_decl` scope doesn't reach call
  sites), and `gen_call` re-asserts it on `__last_unsigned__` after the
  call. Regression `compiler/tests/fn_return_signedness.nu` (5 known-answer
  checks). Bootstrap fixed point holds; full suite + ASan/UBSan green.

- **Narrow sized-int enum payloads now compile and round-trip correctly.**
  An enum variant carrying a `u`/`i8`/`u16`/`i16`/`u32`/`i32` payload (e.g.
  `: | E { None Val u }`) was accepted by the front-end but emitted invalid
  IR: `gen_agg_lit` only converted i64/i32 payloads into the enum's pointer
  slot (so an i8 payload hit `insertvalue …, i8 …` against a `ptr` field —
  clang reject), and `gen_match` only un-converted i1/i64 (storing a `ptr`
  into an `i8` binding). Now construction widens a narrow payload to i64
  (zext for an unsigned payload, sext for signed — from the payload
  signedness `gen_enum_decl` now records) before `inttoptr`, and the match
  `ptrtoint`s back and truncs to the payload width, carrying the payload's
  signedness onto the binding so a later widen zero-extends an unsigned
  payload. Found by hand-probing the fuzzer's struct dimension outward.
  Bootstrap fixed point holds; full suite + ASan/UBSan green. Regression
  `compiler/tests/enum_payload_signedness.nu` (5 known-answer checks).

- **Two silent struct-field signedness miscompiles** (same fuzzer, extended
  with a struct dimension; same root cause — the LLVM field type can't carry
  NURL's signedness). Both fixed in `compiler/nurlc.nu`; regression
  `compiler/tests/struct_field_signedness.nu` (8 known-answer checks);
  validated by 600 fuzzer seeds with the struct dimension.
  1. **Reading an unsigned field sign-extended.** `# i . rec u8field` over a
     `u`/`u16`/`u32` field holding e.g. 200 read back −56: `gen_member` never
     surfaced the field's declared signedness onto `__last_unsigned__`.
     `gen_struct_decl` now records `<S>__<field>__unsigned`, and both the
     value (extractvalue) and pointer (GEP+load) field-load paths set the
     flag from it.
  2. **Constructing a wider field from a narrower unsigned value
     sign-extended.** `@ Wide { # u 130 }` into an `i64` field stored −126
     instead of 130 — `gen_agg_lit`'s field-store widening hardcoded `sext`.
     It now picks `zext` when the field value is unsigned (the
     `__last_unsigned__` snapshot it already takes), `sext` otherwise.

- **Two silent integer miscompiles, found by a new differential fuzzer
  (`tools/fuzz`) and fixed at the root in `compiler/nurlc.nu`.** Both
  produced wrong values with no error — the worst class of bug.
  1. **Unsigned-byte cast widening sign-extended.** `# i64 # u 217` gave
     −39 instead of 217: a nested cast-to-unsigned never set the
     `__last_unsigned__` side-channel the enclosing widening cast consults,
     so it defaulted to `sext`. `gen_cast` now records the cast target's
     signedness for an enclosing widen / binop / shift. (Previously only
     casts whose subject was a typed *binding* — where `gen_ident` sets the
     flag — widened correctly.)
  2. **Signed `i8` arithmetic treated as unsigned.** `gen_binary` inferred
     unsignedness from the LLVM type `i8`, but both the unsigned NURL `u`
     and the *signed* `i8` lower to LLVM i8 — so signed i8 `/ % >> <`
     selected `udiv`/`urem`/`lshr`/`icmp u*` and the result was marked
     unsigned, silently zero-extending a negative value at the next widen.
     Signedness now comes solely from the `__last_unsigned__` flag (set by
     `gen_ident` from a binding's `__unsigned` and by `gen_cast` from an
     unsigned cast target), never from the ambiguous LLVM type.
  Bootstrap fixed point holds; full suite + ASan/UBSan green. Regression
  `compiler/tests/cast_signedness.nu` (12 known-answer checks). Validated
  by 340 fuzzer seeds (0 divergences).

- **Three silent int↔float conversion miscompiles** (same fuzzer, extended
  with float round-trip + comparison + store-coercion probes; fixed in
  `gen_cast`). Same root cause — the LLVM integer type can't carry
  signedness, so it must ride the `__last_unsigned__` side-channel.
  1. **Unsigned int → float used `sitofp`.** `# f # u32 0x80000001` became a
     *negative* float (≈ −2.1e9 instead of +2.1e9); `# f # u 200` became
     −56. Now `uitofp` when the source is unsigned.
  2. **Float → int ignored target signedness.** Now `fptoui` for an unsigned
     target (a value above the signed max no longer becomes poison), else
     `fptosi`.
  3. **A float result leaked its source int's stale unsigned flag.** After
     `# i64 # f # u …`, the still-set `__last_unsigned__` made a surrounding
     `*`/`/` pick `udiv` on a negative product (e.g. `−65 / 7` computed as
     an unsigned divide → garbage). Float-producing casts now clear the
     flag; float→int casts set it from the target. Regression
     `compiler/tests/cast_int_float.nu` (9 known-answer checks). Validated by
     600 fuzzer seeds with the new float dimension (0 divergences).

### Added

- **Differential fuzzer for `nurlc` integer codegen (`tools/fuzz`).**
  `gen.py` generates random sized-integer expression trees and, from the
  same tree, both a self-checking NURL program (prints each result's exact
  64-bit pattern) and a Python reference oracle with explicit
  two's-complement / width / signedness semantics. `fuzz.sh` compiles each
  at `-O0` and `-O2` and requires `stdout(-O0) == stdout(-O2) == oracle`,
  catching miscompiles that are wrong at every optimisation level. Biased
  toward the historically fragile surface (width coercions, unsigned
  arithmetic, mixed signed/unsigned); generates no UB. Found and fixed two
  silent miscompiles on its first run (see Fixed, above). See
  `tools/fuzz/README.md`. Subsequently extended with `let`-binding store
  coercion, variable reuse, comparison operators, and int→float→int
  round-trips — which surfaced three more (see Fixed).

- **USTAR tar reader + writer — `stdlib/ext/tar.nu`.** Pure-NURL POSIX.1-1988
  tar: `tar_create` (entries → archive bytes), `tar_parse` (bytes → entries,
  in-memory), and `tar_unpack` (path-safe extract to disk). Composes with
  `gzip_compress`/`_decompress` to make the `.tar.gz` package format the
  registry will use. The reader treats archives as untrusted input:
  `tar_unpack` rejects absolute paths and `..` components (TarUnsafePath) and
  refuses symlink/hardlink/device members (TarUnsupported) so nothing can
  escape the destination; every header checksum is verified (TarBadChecksum)
  and an over-long declared size is TarTruncated. v1 supports the 100-byte
  `name` field on write (TarPathTooLong otherwise) and honours the `prefix`
  field on read. Bidirectionally interop-tested against GNU tar (NURL→`tar
  xf` and `tar cf`→NURL both round-trip). Regression:
  `compiler/tests/tar_basic.nu` (round-trip incl. embedded NUL in file data,
  gzip composition, checksum tamper, `../` rejection, unpack + binary
  read-back); verified clean under ASan/UBSan. First building block of the
  registry-backed package manager (ROADMAP §4).

- **Semantic Versioning 2.0.0 — `stdlib/ext/semver.nu`.** Pure-NURL semver
  parse / compare / render with full precedence ordering, including the
  prerelease rules (§11: numeric < alphanumeric identifiers, fewer < more
  identifiers, prerelease < release; build metadata ignored). Plus
  **version requirements**: `semver_req_parse` turns a constraint (`^1.2.3`,
  `~1.2`, `>=1.0`, `<2.0.0`, `=1.2.3`, `1.*`, `*`, or a bare `1.2.3`) into a
  half-open range, `semver_req_matches` tests a version, and
  `semver_req_max_satisfying` picks the highest matching version — the
  resolution primitive the registry-backed package manager needs (ROADMAP
  §4). Constraint dialect is **Cargo-shaped**: a bare `1.2.3` means `^1.2.3`,
  use `=1.2.3` to pin. v1 matches prereleases by pure range containment (no
  Cargo-style prerelease comparator special-casing yet). Regression:
  `compiler/tests/semver_basic.nu` (round-trip, the canonical §11 precedence
  chain, every constraint operator, `max_satisfying`, parse errors); clean
  under ASan/UBSan and leak-free.

- **Registry-ready manifest + typed lockfile.** `stdlib/ext/manifest.nu`'s
  `Dep` gained a `registry` field and `Manifest` gained a default
  `[package].registry`, so a dependency can now be expressed as a path dep
  (`{ path = "…" }`), a bare registry dep (`foo = "^1.2"`, default
  registry), or an explicit registry dep
  (`{ version = "1.0", registry = "…" }`); `dep_is_path` / `dep_is_registry`
  discriminate. New `stdlib/ext/lockfile.nu` is a typed view over
  `nurl.lock`: a `LockPkg { name, version, source, checksum }` with
  `lock_serialize` (deterministic, name-sorted, Cargo-shaped `[[package]]`
  blocks; `source`/`checksum` omitted for path/local packages) and
  `lock_parse` / `lock_load` (round-trips through `toml.nu`'s
  array-of-tables). `checksum` is the hex SHA-256 of the package tarball —
  the integrity pin a registry install verifies. Regressions:
  `compiler/tests/manifest_registry.nu`, `compiler/tests/lockfile_basic.nu`;
  clean under ASan/UBSan, leak-free. ROADMAP §4 phase 3 (data model for
  registry deps). `nurlpkg`'s two `Dep` construction sites updated for the
  new field.

- **WebSocket client (RFC 6455 §4.1 + §5.3).** `stdlib/ext/websocket.nu`
  gained the full client side to match the existing server. `ws_connect`
  / `ws_connect_with` parse a `ws://…` / `wss://…` URL, dial out (plain or
  TLS-with-cert-verification via the runtime client-connect primitives),
  send the HTTP Upgrade request with a fresh random `Sec-WebSocket-Key`,
  and validate the `101` response's `Sec-WebSocket-Accept`. Outbound frames
  are masked with a CSPRNG-drawn 4-byte key (`ws_client_send_text` /
  `_binary` / `_ping` / `_pong` / `_close`, `ws_client_write_frame`,
  `ws_serialize_frame_masked`); inbound server frames are read and required
  to be unmasked (`ws_client_read_frame` / `_read_message` /
  `_serve_messages`, which auto-pong masked). The frame reader/assembler is
  now shared between both directions via an internal `__ws_read_frame_ex` /
  `__ws_read_message_ex` parameterised on direction — no duplicated framing
  logic. Regression: `compiler/tests/websocket_client.nu` (RFC 6455 §5.7
  masked-frame byte vector, URL parsing, and a live `NURL_NET_TESTS=1`
  client↔server echo round-trip proving interop with the server stack).
  Example: `examples/ws_client.nu` (pairs with `examples/ws_echo.nu`).

- **Binary-safe HTTP request bodies — `http_*_bytes` family.** The s-body
  `http_request` / `http_post` / `http_put` family recovers the body length
  via `strlen`, so a request body with embedded NUL bytes (binary file
  uploads, MessagePack, protobuf) truncated at the first NUL. New
  length-carrying variants take the body as a `( Vec u )` and ship it via
  `CURLOPT_COPYPOSTFIELDS` + an explicit `POSTFIELDSIZE`, so the exact byte
  count is sent: `http_request_bytes` / `http_request_bytes_to`,
  `http_post_bytes`, `http_put_bytes`, and the streaming
  `http_stream_open_bytes_to`. The `body` argument is borrowed (the caller
  still owns it). Binary fidelity requires the libcurl backend; the
  WinHTTP/stub fallback round-trips through a NUL-terminated `s` and
  degrades to the old truncation. `stdlib/ext/http.nu`.

### Fixed

- **Reverse-proxy request body is now binary-safe + a latent use-after-free
  is closed.** `proxy_stream_to_conn_with` forwarded the upstream request
  body by converting the request's `( Vec u )` body to a NUL-terminated `s`
  and shipping it through `CURLOPT_POSTFIELDS` (strlen-sized), truncating
  binary uploads at the first NUL. Worse, the streaming opener set
  non-copying `CURLOPT_POSTFIELDS` and the proxy freed the body buffer
  *before* the first `multi_perform` read it — a dangling-pointer read that
  only escaped notice on small JSON bodies. Both are fixed by routing the
  length-tracked body through `http_stream_open_bytes_to`, which uses
  `CURLOPT_COPYPOSTFIELDS` (libcurl snapshots the bytes at open time, so the
  caller may free immediately and embedded NULs survive). Regression:
  `compiler/tests/http_binary_body.nu` (NURL client `http_post_bytes` of a
  5-byte `A B \0 C D` body to a loopback NURL server, asserting the server
  parsed all 5 bytes; `NURL_NET_TESTS=1`). Verified clean under ASan/UBSan.
  `stdlib/ext/http.nu`, `stdlib/ext/http_proxy.nu`.


## [0.9.4] — 2026-06-02

### Added

- **Keyword arguments — default parameter values + named call arguments.**
  A trailing parameter may carry a default: `@ f s a s b = `x` i n = 3 → R`
  (the default is a single source token — literal / const / atom). A call
  may then omit defaulted trailing arguments — `( f val )` — and/or pass
  arguments by name in any order, mixed with leading positional ones:
  `( f a: 1 b: 2 )`, `( f val n: 5 )`, `( greet greeting: `Hi` name: `Bob` )`.
  Implemented as a call-site desugaring to an ordinary positional call:
  `scan_fn_sigs` records each function's parameter names + default sources;
  `gen_call` fills omitted trailing defaults inline, and routes a call that
  uses `name:` labels through `gen_call_kwargs`, which evaluates arguments
  in source order and assembles them in parameter order. Existing positional
  calls take the unchanged path (byte-identical IR — bootstrap fixed point
  holds). Regression: `compiler/tests/kwargs.nu`. Current limits (documented
  in the grammar): not on generic functions, FFI/variadic, or parameters
  with the `inout`/`sink` convention; `**kwargs`-style collection is not
  provided (pass a `Json`/struct).

- **BLAKE3 hash (pure NURL) — completes the hash family.** New
  `stdlib/std/hash_blake3.nu` implements full BLAKE3 (the ChaCha-derived
  compression function, 1024-byte chunks split into 64-byte blocks with
  CHUNK_START/CHUNK_END flags, the binary Merkle tree of chaining values,
  and the ROOT-flagged final node), exposed via `blake3_bytes` /
  `blake3_hex` in `stdlib/std/hash.nu` (unkeyed, 32-byte output). All-NURL
  u32 wrapping arithmetic, little-endian, binary-clean over `( Vec u )` —
  **no C at all** (compiler and runtime untouched). Verified
  digest-for-digest against the official BLAKE3 reference across every
  structural path (empty, sub-block, the 1024-byte single chunk, the
  1025-byte two-chunk boundary, balanced multi-chunk trees up to 5000
  bytes); regression `compiler/tests/blake3.nu`; clean under ASan/UBSan/LSan.
  Closes the ROADMAP "Extended Hash Family" item — SHA-1/256/512, MD5,
  HMAC, and BLAKE3 are all shipped.

- **`volatile_load` / `volatile_store` compiler intrinsics for MMIO.** Emit
  `load volatile` / `store volatile` as pure IR (no runtime call, so they
  work on a freestanding target). The optimizer can no longer hoist an MMIO
  read out of a polling loop (LICM), reorder accesses, or coalesce repeated
  reads/writes — the missing piece for spinning on a device status register
  at `-O2`. The access width comes from the typed pointer argument (`*T`),
  so one pair covers i8/i16/i32/i64. `stdlib/hal/mmio.nu`
  (`mmio_read32`/`write32`/`set32`/`clear32`) now uses them, so the ESP32
  UART/GPIO drivers no longer need the `-O0` workaround. Regression:
  `compiler/tests/volatile_mmio.nu`; verified at `-O2` the volatile load
  stays inside the loop body.

- **ESP32 bare-metal register HAL (`stdlib/hal/esp32.nu`).** Pure-NURL GPIO
  and UART0 over the chip's memory-mapped registers (built on
  `stdlib/hal/mmio.nu`) — no ESP-IDF, no FFI. GPIO output enable / set /
  clear, and a blocking UART console (`esp32_uart_putc` / `getc` / `puts`
  with FIFO-count helpers), with register addresses taken from the ESP32 TRM
  and cross-checked against ESP-IDF's `soc/*_reg.h`. Demonstrated by the new
  fully-NURL UART echo example (`examples/esp32/idf-uart`).

- **C64 emulator example (`examples/c64`).** A MOS 6510 / Commodore 64
  emulator in pure NURL — a single `core.nu` engine shared by a native CLI
  and a WebAssembly browser front-end. The CPU core passes Klaus Dormann's
  `6502_functional_test` (the canonical 6502 correctness oracle, validated
  headlessly), and with stock KERNAL/BASIC/CHARGEN ROMs the machine boots
  through the full power-on sequence — PLA banking, CIA1 jiffy IRQ — to the
  BASIC `READY.` prompt.

### Fixed

- **nurlfmt split hex/binary/octal integer literals.** The tokenizer's
  numeric scanner stopped at the first non-decimal digit, so `0x3FF44008`
  became two tokens (`0` + identifier `x3FF44008`) and the reformatted
  source miscompiled — silently, because `--check` is idempotent on its own
  broken output. `tools/nurlfmt/tokenize.nu` now scans a `0x`/`0b`/`0o`
  prefix and its body as one token. Verified by the
  `nurlfmt_idempotent.sh` gate (450 files, IR-transparent) and by restoring
  the hex literals in the `examples/esp32/*` register maps that had been
  worked around with decimal constants.

- **SQLite production hardening (Tier 1 + Tier 2).** `stdlib/ext/sqlite.nu`
  is now binary-safe and resource-safe:
  - **NUL-safe text I/O.** `sqlite_column_text` reads the column's exact
    byte length via `sqlite3_column_bytes` (was `strlen`, which truncated
    at the first embedded NUL), and `sqlite_bind_text` now takes a `String`
    and passes an explicit byte length to `sqlite3_bind_text` instead of
    `-1` — strings with embedded NULs round-trip intact.
  - **BLOB support.** New `sqlite_bind_blob` (`Vec u` → `sqlite3_bind_blob`
    + `SQLITE_TRANSIENT`) and `sqlite_column_blob` (`sqlite3_column_blob` +
    `_bytes` → owned `Vec u`) — the binary-safe write/read path.
  - **`sqlite_open_v2` with open flags.** `SQLITE_OPEN_READONLY` /
    `READWRITE` / `CREATE` / `URI` / `NOMUTEX` / `FULLMUTEX` / `NOFOLLOW`
    constants exposed; `sqlite_open` is now `READWRITE|CREATE` over
    `open_v2`. A read-only connection refuses writes (new `SqliteReadOnly`
    error variant) instead of silently creating a file.
  - **`sqlite_busy_timeout`** wraps `sqlite3_busy_timeout` so `SQLITE_BUSY`
    blocks-and-retries under concurrent access rather than failing
    immediately.
  - **`% Drop` auto-close.** `Database` and `Statement` implement the Drop
    trait; a scope-local handle — including one unwrapped from a
    `! Database E` / `! Statement E` result in a match arm — closes itself
    on every path (Ok, Err, early return) with no manual
    `sqlite_close`/`sqlite_finalize`. Teardown zeroes the handle slot after
    closing, so a stale internal re-entry is a no-op. Verified leak-free
    and double-free-free under ASan + UBSan (`compiler/tests/sqlite_hardening.nu`).
  - **Tier 3 — datatypes & transactions.** `sqlite_bind_double` /
    `sqlite_column_double` (REAL columns), `sqlite_column_is_null`,
    `sqlite_begin` / `commit` / `rollback`, and a closure-based
    `with_transaction` that COMMITs on `Ok` and ROLLBACKs on `Err`
    (propagating the original error).
  - **Tier 4 — hardening for untrusted SQL/DB.** Extended result codes are
    enabled on every open, so constraint failures now map to distinct
    variants (`SqliteConstraintUnique` / `…ForeignKey` / `…NotNull` /
    `…PrimaryKey` / `…Check`). Added `sqlite_last_insert_rowid`;
    `sqlite_set_defensive` / `sqlite_enable_load_extension` /
    `sqlite_harden` (DEFENSIVE on + extension-loading off — blocks
    corruption/RCE from a hostile DB); `sqlite_limit` (bound query
    complexity); a closure-based `sqlite_set_authorizer` /
    `sqlite_clear_authorizer` that installs a sandbox callback with the
    exact C ABI libsqlite expects (the closure's compiled function +
    captured env are passed as `xAuth` + `pUserData`, the same mechanism
    `thread_spawn` uses for `pthread_create` — no C bridge); and PRAGMA
    helpers `sqlite_journal_wal` / `sqlite_foreign_keys` /
    `sqlite_synchronous`. Verified under ASan + UBSan
    (`compiler/tests/sqlite_tier34.nu`).

### Changed

- **Match-arm payload bindings now participate in auto-drop.** A `% Drop`
  type bound as a `??` match-arm payload (e.g. `?? r { T db → … }`) — or a
  `:` let inside a match arm — is now dropped at arm scope exit, on the same
  void-arm-only rule used for owned strings/structs. Previously such
  bindings were never dropped (a latent leak); this is what lets the SQLite
  handles above close automatically in the idiomatic result-unwrap flow.

### Documentation

- **ROADMAP brought up to date.** The Status header now reads **Grammar v2.1**
  (was v2.0) and points at `spec/grammar.ebnf`. Items that were marked pending
  but are in fact shipped are now `[x]`: the **async runtime** (stackful M:N
  fibers — the Coroutines-vs-async/await decision is settled), **HTTP server
  Phase 8** (production hardening) and **Phase 9** server-side (TLS+SNI+ALPN+
  mTLS+reload, HTTP/2, WebSocket — client-side remains), the **optional
  `-lcurl`** sentinel-gated linking, and the **`nurlc_lastgood.nu` refresh**
  lifecycle (documented via `--refresh-bootstrap`). Added an explicit
  "What's actually left" summary to the Status section (HTTP/2+WebSocket
  client-side; mobile/`no_std` targets; SQLite BLOB/double; reverse-proxy
  binary bodies; blake3; MCP SSE/sessions/auth; the `runtime.c` file-split;
  a compiler-embedded LLM; bench peers). Stale build-size figures left only
  in dated historical "shipped" entries (records, not current claims).

- **Removed hard-coded build-artifact sizes from the reference docs.** The
  `~480 KB nurlc.wasm` (`docs/PLAYGROUND.md`) and `~1.6 MB`
  `nurlc_lastgood.ll` (`docs/BUILDING.md`) figures drift every build and
  mislead when the real artifact differs. Build sizes belong in the
  changelog/release notes (tied to a specific version), not in
  instructional docs.

- **Cleaned stale `GOTCHAS.md item N` / `§N` references out of code comments.**
  After `docs/GOTCHAS.md` lost its numbered list, ~44 source comments (in
  `compiler/nurlc.nu`, the `nurlc_lastgood.nu` snapshot mirror, nine
  `compiler/tests/*.nu`, and `stdlib/ext/{http_middleware}.nu`) still pointed
  at item/section numbers that no longer exist. Each now points at the real
  home (escape/lifetime → `docs/MEMORY.md` §2.3, grammar → `docs/LIMITATIONS.md`)
  or simply describes the behaviour inline. The `nurlc_lastgood.nu` edits are
  comment-only — verified to produce byte-identical IR, so the committed
  bootstrap `nurlc_lastgood.ll` is unchanged; the build still reaches its
  fixed point and the full test suite passes.

- **`docs/GOTCHAS.md` reduced to "Currently no known gotchas."** Every
  source-level trap is now a compiler diagnostic (`error:`/`warning:` with a
  caret + cure), so the page no longer lists a museum of resolved issues.
  The real content that lived there was relocated to its proper home: the
  fiber-runtime operational caveats (non-blocking handle flipping,
  `runtime_run` blocking, stack-borrow capture, plus runtime-maintainer
  notes on TLS-under-LTO and the reactor park/unpark ordering) moved to
  [`docs/ASYNC.md`](docs/ASYNC.md) → Operational caveats, and the
  `: ~`-capture lifetime rule now points at [`docs/MEMORY.md`](docs/MEMORY.md)
  §2.3. Updated every back-reference (`docs/spec.md`, `docs/LIMITATIONS.md`,
  `ROADMAP.md`'s "5 active quirks" status line, the VS Code extension
  README, and stale `GOTCHAS.md item N` comments in `stdlib/ext/toml.nu`,
  `mcp_http.nu`, `http_multipart.nu`). All internal links verified.
- **`docs/LIMITATIONS.md` scoped to actual language/compiler limitations.**
  Removed the standard-library capability tables (PostgreSQL, SQLite,
  panic/recover) that were never language limitations — that information
  lives with each module (stdlib headers, `ROADMAP.md`, `TODO.md`). Moved
  the HTTPS/TLS table to [`docs/NETWORKING.md`](docs/NETWORKING.md) where it
  belongs. Removed two entries that were **stale** (the behaviour already
  works, verified empirically): "no tail-call optimisation" (self-recursive
  tail calls emit `tail call` → LLVM sibcall-opt; 50M-deep tail recursion
  runs without overflow) and "enum forward references unsupported"
  (`scan_type_names` registers type names before codegen, so a struct
  payload can be declared after its enum). The page now lists only
  language/compiler constraints (Type system, Functions/calls, Enums,
  Imports, Grammar).
- **Playground now renders linked docs instead of 404ing.** Clicking a
  relative link inside a rendered doc (e.g. `docs/LIMITATIONS.md` from the
  README, or `../spec/grammar.ebnf` from a `docs/` page) used to hit "not
  found". `nurlapi` now serves the repo doc tree by its natural path —
  `/docs/*`, `/spec/*`, `/bench/*`, and the capitalised top-level
  `/README.md` · `/ROADMAP.md` · `/CHANGELOG.md` · `/CONTRIBUTING.md` —
  rendering `.md` to HTML (`__serve_repo_doc`, path-traversal-guarded) and
  serving other files as text; `examples/*.md` renders too (`.nu` stays
  JSON for the editor). Because the route hierarchy mirrors the repo, the
  browser's own relative-link resolution chains correctly between docs. The
  container image now copies the **whole `docs/` tree** (was only
  `GOTCHAS.md`) plus `CHANGELOG.md`, `CONTRIBUTING.md`, and `bench/`.
- **README refactored into a slim overview + topic docs.** The 991-line
  kitchen-sink README is now a ~230-line overview (why/principles,
  architecture, quick start, syntax-at-a-glance, a documentation index, and
  project layout) that links out to focused pages under `docs/`. New:
  `docs/BUILDING.md`, `docs/TOOLING.md`, `docs/PLATFORMS.md`,
  `docs/PLAYGROUND.md` (HTTP API + playground + MCP), `docs/NETWORKING.md`
  (sockets + MQTT), `docs/LIMITATIONS.md`. Syntax/type/memory sections now
  point to the existing authoritative homes (`spec/grammar.ebnf`,
  `docs/spec.md`, `docs/MEMORY.md`) instead of duplicating them.
- **Removed stale / frequently-changing content.** The README no longer
  hard-codes a grammar version, benchmark tables (point to `bench/`), the
  example file list, the MCP tool count, or the `.vsix` version. The
  PostgreSQL "Known Limitations" (claimed no binary protocol / async /
  LISTEN-NOTIFY / COPY — all shipped) and the MQTT section (TLS-only +
  verify-on-by-default + exactly-once QoS 2 + `subscribe_many`) are now
  accurate. Dropped references to non-existent `spec/types.md` / `ir.md` /
  `bootstrapping.md`, fixed `CONTRIBUTING.md`'s `api/` → `nurlapi/`, a dead
  `HTTP_SERVER_PLAN.md` link in `ROADMAP.md`, the compiler's prefix-arity
  diagnostic (pointed at the moved README section → `docs/LIMITATIONS.md`),
  and `docs/GOTCHAS.md`'s cross-reference. All internal doc links verified.

### Added

- **MQTT: multi-topic SUBSCRIBE** (`mqtt_subscribe_many`) sends one
  SUBSCRIBE for N filters at a shared max QoS and validates every
  per-filter SUBACK reason code (a new `__mqtt_check_suback` that parses
  the property block instead of assuming a single trailing byte —
  `mqtt_subscribe_qos` now uses it too).
- **PostgreSQL advanced protocol features — binary, async, LISTEN/NOTIFY,
  COPY** (`stdlib/ext/postgres.nu`). Closes the last Tier-5 Postgres gap;
  all four are pure-NURL libpq FFI (no `runtime.c` bridge) and are
  exercised end to end by the new `examples/pg_advanced.nu`, live-verified
  against PostgreSQL 16.14.
  - *Binary result protocol*: `pg_exec_params_binary` requests
    `resultFormat = 1`; `pg_get_i16_bin` / `_i32_bin` / `_i64_bin` /
    `_bool_bin` / `_f64_bin` decode network-byte-order cells (`float8`
    reinterpreted from its IEEE-754 bit pattern, not a numeric cast), with
    `pg_get_length` / `pg_field_format` / `pg_binary_tuples`.
  - *Asynchronous queries*: `pg_send` / `pg_send_params` dispatch without
    blocking; `pg_get_result` (→ `?PgResult`, `None` when finished) and the
    blocking convenience `pg_await` collect results; `pg_consume_input` /
    `pg_is_busy` / `pg_socket` / `pg_flush` / `pg_set_nonblocking` hook into
    an event loop.
  - *LISTEN/NOTIFY*: `pg_listen`, `pg_notify_send`, `pg_notifies`
    (→ `?PgNotify { relname, be_pid, extra }`, read after
    `pg_consume_input`) and `pg_notify_free`.
  - *COPY*: `pg_copy_start` (accepts the `PGRES_COPY_IN` / `COPY_OUT`
    handshake that plain `pg_exec` rejects), `pg_put_copy_data` /
    `pg_put_copy_str` / `pg_put_copy_end` for `COPY … FROM STDIN`, and
    `pg_get_copy_data` (→ `?String`) for `COPY … TO STDOUT`.

### Fixed

- **Compiler: `??`-match on a result/option-typed *parameter* dropped its
  payload.** `@ f !S E r → S { ?? r { T x → ^ x } }` emitted `ret i64`
  against the `%S` return type (an LLVM "value doesn't match function
  result type" error), and the same gap mishandled a `( Vec u )` handle
  payload and dropped the unsigned flag on a `?u` parameter (sign-extending
  a byte ≥ `0x80`). `gen_fn_param` now records the
  `<param>__res_nurl_T` / `__res_t_llvm` / `__res_e_llvm` / `__opt_nurl_T`
  metadata that `gen_let_or_struct` already records for let-bound result
  vars, so `gen_match` reconstructs struct / pointer / unsigned payloads
  for a parameter scrutinee exactly as it does for a let binding. Bootstrap
  fixed point held; regression `compiler/tests/match_param_payload.nu`.
- **Compiler: an empty block `{}` returned from a void function emitted
  invalid IR.** An empty block is the unit/void value, but `gen_block` left
  the "last type" at whatever preceded it (i64 by default, i1 inside a
  conditional), so `^ {}` in a void function produced `ret i64 undef` —
  rejected by LLVM. The block now types as `void` when it has no trailing
  statement.
- **Compiler: undefined identifier in value position no longer emits an
  undefined SSA value with exit status 0** (PR #25 / `Fixes`). `gen_ident`'s
  bare `%<name>` fallback fired for *any* name lacking a `__ptr` / `__global`
  binding — so `: i x ^ a b c` emitted `ret i64 %a` that nurlc accepted and
  only clang rejected. The fallback now requires a by-value parameter and
  otherwise dies with "use of undefined identifier". This was critic.md §4's
  headline contradiction of "every trap is a compiler diagnostic".
  Regression `compiler/tests/should_fail_undef_ident.nu`.
- **Compiler: a within-statement prefix-arity cascade that swallowed the
  next `^` silently returned early** (PR #25 / `Fixes`). `: i x + 1` /
  `^ a` parsed as `+ 1 (^ a)` → `ret %a` plus a dead `add`, exiting 0. A new
  `g_ret_forbidden` flag (armed by a `gen_operand` wrapper around every
  value-operand parse, reset by `gen_stmt` and the `?` / `??` arm bodies)
  makes `gen_ret` refuse to emit a `ret` in operand position. Regression
  `compiler/tests/should_fail_cascade_caret.nu`.
- **Compiler: `??`-match on a direct-call scrutinee dropped pointer/handle
  payloads and option signedness** (PR #25 / `Fixes`). `: ( Vec u ) x ?? ( f
  … ) { … }` / `: s x ?? ( f … ) { … }` left the binding `undef` (no T-arm
  reconstruction, no result phi) for handle/pointer payloads, and `?? (
  vec_get [u] … ) { T b → # i b }` sign-extended an unsigned byte. The
  callee's Ok/Err-payload LLVM types and option-inner token are now recorded
  per function and surfaced to `gen_match`'s direct-call synthesis (with a
  bare-`i8*` inttoptr path for both arms). Regressions
  `compiler/tests/match_bind_call_handle.nu`, `match_call_opt_unsigned.nu`.
- **Compiler: option/result construction from a sized-int literal didn't
  truncate** (PR #25 / `Fixes`). `@ ?u { T 0x86 }` emitted `insertvalue {
  i1, i8 } …, i64 134, 1`, which clang rejected. `gen_agg_lit`'s opt/res
  payload coercion now truncs/sexts/zexts the literal to the payload width
  (option = T's real width, result = i64). Regression
  `compiler/tests/opt_lit_payload_width.nu`.
- **MQTT inbound QoS 2 is now exactly-once.** A retransmitted (DUP)
  QoS 2 PUBLISH was acknowledged but re-delivered to the application. The
  client now tracks inbound packet ids across their PUBREC…PUBCOMP window
  (`MqttClient.qos2_rx`, bounded, oldest evicted past 256), acknowledges a
  duplicate but delivers it only once. `__mqtt_parse_publish` returns
  `?MqttMessage` (None on a de-duplicated retransmit) and the dedup policy
  is unit-tested in `compiler/tests/mqtt_qos2_dedup.nu`. The doc-drift
  comment on `__mqtt_do_publish` (claimed a fixed packet id) was corrected.

### Security

- **MQTT TLS certificate verification is now configurable and on by
  default.** `mqtt_connect_cfg` / `mqtt_reconnect` previously hard-coded
  `verify = F`, so every TLS connection was effectively `--insecure`
  (MITM-able). `MqttConfig` gained a `tls_verify` field, threaded through to
  `tcp_connect_tls`; `mqtt_config` defaults it to T (peer-cert chain + host
  name verified against the system trust store). Set it F only for a
  self-signed broker in a trusted environment.
- **`pg_listen` SQL injection (critical) — fixed.** A channel name is a SQL
  *identifier* and cannot be a bound parameter, so it now goes through
  `pg_escape_identifier` (PQescapeIdentifier) before interpolation; raw
  concatenation previously let `pg_listen c "x; DROP TABLE …; --"` execute
  the injected statement. (`pg_notify_send` was already safe — it binds the
  channel as a value to `pg_notify($1, $2)`.)
- **Out-of-bounds read in the binary accessors (medium) — fixed.** A new
  `PQgetlength`-checked `__pg_bin_ptr` guards every `pg_get_*_bin`:
  reading an `int4` cell with the 8-byte `pg_get_i64_bin`, or any accessor
  on a binary SQL `NULL` (0 bytes), now returns `0` instead of reading past
  the cell into adjacent libpq buffer memory.
- **TLS is not verified by default — documented.** `pg_connect` and the
  file header now carry a prominent warning that libpq's default
  `sslmode=prefer` neither prevents a silent plaintext fallback nor
  verifies the server certificate (MITM-able), recommending
  `sslmode=verify-full sslrootcert=…` for non-local connections. Not
  force-defaulted, as that would break legitimate unix-socket / trusted-LAN
  connections. Minor: `pg_get_bool` gained a NULL-pointer guard, and the
  empty-on-NULL behaviour of `pg_escape_literal` / `pg_escape_identifier`
  is now documented.

## [0.9.3] — 2026-05-31

### Summary

A full **Game Boy (DMG) emulator written in NURL** now plays commercial
games with sound. `examples/gameboy/` passes Blargg `cpu_instrs` 11/11,
`instr_timing` and `02-interrupts`, is 100 %/pixel-perfect on dmg-acid2,
and runs *Tobu Tobu Girl* end to end — full gameplay plus a complete
4-channel APU mixed to stereo — in the browser at `/gameboydemo` via the
WebAssembly target. Building it drove three new language/compiler
features (**hex/binary integer literals**, pointer/aggregate global
initialisers, hex literals in `match`) and turned one
silently-accepted bare-literal statement into a hard compile error.

**Generics now range over option and pointer element types** — `Vec ?T`,
`vec_get [?T] → ??T`, `??T` parameters/returns and nested `??` matching
all compile (five front-end root-cause fixes). The PostgreSQL client is
**production-grade** (`stdlib/ext/postgres.nu` + `examples/psql.nu`),
including option-typed nullable params and getters
(`pg_exec_params_opt`, `pg_get_opt`), verified live against
PostgreSQL 16 under AddressSanitizer.

HTTP/2 + HPACK + WebSocket conformance suites remain green: h2spec 2.6.0
reports 146/146 cases against `examples/h2c_server.nu`; the
autobahn-testsuite fuzzing client reports 294 OK / 4 NON-STRICT /
3 INFORMATIONAL / 0 FAILED across all 301 RFC 6455 cases against
`examples/ws_echo.nu`. Both binaries run under ASan + UBSan
without findings.

Bootstrap fixed point at 1 772 342 B (stage1 ≡ stage2 byte-identical
IR).

### Added

- **Game Boy (DMG) emulator — `examples/gameboy/`.** A cycle-aware Sharp
  LR35902 core (every opcode + CB-prefix, exact Z/N/H/C flags + DAA,
  EI/DI IME enable-delay, HALT + HALT-bug, DIV/TIMA timer, interrupt
  dispatch) passing **Blargg `cpu_instrs` 11/11, `instr_timing` and
  `02-interrupts`**; a BG/window/sprite PPU that is **100 %/pixel-perfect
  on dmg-acid2** (0/23040 diff — LYC raster + window internal line
  counter); MBC1/3/5 mappers, joypad and OAM DMA; and a complete
  **4-channel APU** (2 square w/ sweep, 4-bit wave RAM, 15-bit-LFSR
  noise, 512 Hz frame sequencer, NR50/51 mix, DMG high-pass) mixed to
  stereo. The engine is split into a shared `core.nu` with `gb.nu` (CLI)
  and `gb_wasm*.nu` (wasm32-wasi → canvas) front-ends; the browser demo
  at **`/gameboydemo`** auto-starts *Tobu Tobu Girl* and plays it with
  sound through the playground audio shim. Two sub-instruction timing
  fixes (TIMA increments on the DIV falling edge; the fetch M-cycle is
  clocked before the instruction body) took it from a title-screen crash
  to full gameplay. Build the wasm at `-O2` (lower `-O` leaks the C
  shadow-stack pointer on the interrupt-dispatch path).
- **Generics over option / pointer element types.** Option (and pointer)
  element types are now first-class generic type arguments:
  `vec_get [?String] → ??String`, `Vec ?T` / `vec_push` / `vec_set` /
  `vec_free_with`, `??T` as a parameter and return type, and nested
  `?? o { T inner → ?? inner { … } }` matching all compile — every one of
  these previously failed at compile time. Five front-end root-cause
  fixes, each verified by a full bootstrap + test-suite run and an
  ASan-clean probe: (1) `parse_type_optopt` for the fused `??T` token;
  (2) `capture_type_arg_src` + `nurl_src_to_llvm` + an `opt_`
  mangle/demangle round-trip so compound type args like `[?String]` are
  one substitutable word; (3) `;`-separated closure parameter types so an
  aggregate type (`{ i1, %String }`) no longer truncates at its first
  space; (4) slice-vs-pointer store discrimination; (5) `int → aggregate`
  zeroinit. Test corpus on branch `feature/generic-option-types` (PR #21).
- **Hex / binary integer literals — `0xFF`, `0b1010`.** Added to the
  number lexer; the token carries the parsed value and keeps its spelling
  for diagnostics. Two companion compiler fixes: pointer- and
  aggregate-typed global initialisers (`: s g 0` → `global i8* null`,
  `: String g 0` → `zeroinitializer`, `inttoptr` for a nonzero address),
  and hex-literal normalisation in `match` (int-patterns `?? op { 0xCB →
  … }` and enum field-constraints `Code 0xFF → …` are rewritten to
  decimal before the `icmp`, since LLVM reads `0x…` as a hex float).
  Regression test `compiler/tests/hex_literals.nu`.
- **Production-grade PostgreSQL client + `psql` CLI.**
  `stdlib/ext/postgres.nu` reaches production grade: a `PgParams` builder
  (`pg_bind_text/str/int/bool/null`) for typed + NULL parameter binds the
  libpq/pgx way, `pg_prepare` / `pg_exec_prepared`, `pg_run`,
  `pg_begin/commit/rollback`, typed getters (`pg_get_int/f64/bool`),
  `pg_reset` / `pg_err_msg` / `pg_server_version` / `pg_escape_literal` /
  `pg_escape_identifier`, and — now that generics range over option types
  — option-typed nullable params/getters `pg_exec_params_opt
  ( Vec ?String )`, `pg_get_opt → ?String`, `pg_get_opt_int → ?i`. New
  `examples/psql.nu` (aligned-table renderer, command tags, multi-line
  `;` accumulation, `\dt \d \l \du \conninfo` meta-commands, `-c "SQL"`
  one-shot) and `examples/pg_optional.nu`. Verified live against
  PostgreSQL 16 under ASan (PRs #20 / #22).
- **Audio output in the WASM playground.** An `env.audio_out_push` host
  shim streams packed-stereo `i64` samples to 48 kHz Web Audio, letting
  WASM programs emit sound; demonstrated by `examples/audio_tone.nu` and
  used by the Game Boy demo's APU output.
- **Trait bounds on generic functions — `[A: Trait]`.** A generic type
  parameter may now carry one or more trait bounds: `@ my_max [A: Ord] A
  x A y → A { … }`. Trait-method dispatch inside a generic body already
  resolved to the concrete `impl` through monomorphisation (dispatch is
  keyed on the first argument's LLVM type, which becomes concrete at
  instantiation); the bound adds the up-front guarantee. `scan_impl_decl`
  now registers each `% Trait Type {}` as `Trait##<llvm>` in
  `g_trait_syms`; `gen_generic_fn_store` records per-tparam bounds; and
  `check_generic_bounds` (called from `gen_call` at every generic call
  site) verifies each bounded tparam's concrete type has the impl —
  turning a missing impl from a cryptic unresolved-call link error into a
  clear "type 'X' does not implement trait 'Y' required by bound A: Y"
  diagnostic. Generic detection in `gen_fn_decl` extended to recognise a
  colon anywhere in the `[…]` (a slice param's type never contains one).
  This removes the need to pass `Ord`/`Hash`/`eq` closures into generic
  helpers when an `impl` exists. Tests `compiler/tests/trait_bounds.nu`
  (positive, i + String) and `should_fail_trait_bound.nu` (bound
  violation → COMPILE FAIL). Bootstrap fixed point holds (stage1 ≡ stage2
  byte-identical at 1 730 148 B).
- **`??` match guards + or-patterns.** Two additions to `gen_match`:
  - **Guards** — `Pattern payloads ? <cond> → body`. The guard is
    evaluated *after* payload binding (so it can read the bound
    payloads); a false guard falls through to the next arm. Implemented
    by recording the guard's source span during arm parse and replaying
    it via `nurl_lex_set_pos` at the arm body, branching to the body or
    the next arm. A guarded arm does NOT satisfy exhaustiveness for its
    variant — a catch-all (unguarded or `_`) is still required. Not
    allowed on a `_` wildcard arm or combined with an or-pattern.
  - **Or-patterns** — `A | B | C → body`: several tag-only named
    variants share one body (`emit_or_chain` lowers the alternatives to
    a tag-compare chain). No payload binding or literal constraints; all
    listed variants count toward exhaustiveness.

  Test `compiler/tests/match_guards_or.nu`. Bootstrap fixed point holds
  (stage1 ≡ stage2 byte-identical at 1 720 428 B).
- **Compile-time const folding for integer globals.** A top-level
  integer const (`: i NAME …`, or u / sized ints — not `b`) may now take
  a prefix expression over integer literals instead of a single literal:
  `+ - * / << >> & | ^^` (not `%`, which collides with the trait/impl
  decl sigil at scan time). `const_eval_int` in `gen_const_decl` folds it
  to one value. Fixes the long-standing wart where e.g. the
  two's-complement minimum needed a niladic helper — `stdlib/std/int.nu`
  now exposes `: i INT_MIN - -9223372036854775807 1` directly
  (`int_min_val` retained, delegating to it). Transparent (computes a
  value, hides no control flow); fits the parse-directed architecture.
  Test `compiler/tests/const_eval.nu`. Bootstrap fixed point holds.
- **`select` over channels — `?? { … }`** — Go-style select. A `??`
  whose scrutinee is immediately `{` (no value to match) is a channel
  select; each arm `[T] ch → bind { body }` receives from one channel
  and the construct proceeds with the first ready arm. With no `_`
  default it BLOCKS until some channel is ready (value sent or channel
  closed); a `_ → { … }` default makes it non-blocking. `bind` is the
  `?T` the receive yields (None ⇒ closed). Arms are heterogeneous (each
  channel may carry a different element type) and tried in source order.
  Implemented in `gen_select` (compiler/nurlc.nu) as a desugaring that
  synthesises NURL source from the verbatim user channel-exprs + bodies
  and compiles it through a sub-lexer — no raw IR, no new lexer token.
  The blocking rendezvous (a shared `SelectWaiter` armed on every
  channel, fired by senders/closers under the channel mutex) lives in
  `stdlib/std/channel.nu` via the type-erased `chan_raw_poll` /
  `chan_raw_arm` / `chan_raw_disarm` / `select_waiter_*` helpers — the
  element type drops out of the orchestration, so one non-generic code
  path serves channels of any type. Test
  `compiler/tests/select_basic.nu` (deterministic default / value /
  closed / priority cases always-on; concurrent blocking path gated on
  `NURL_NET_TESTS=1`). Bootstrap fixed point holds (stage1 ≡ stage2
  byte-identical at 1 691 603 B).
- **Stdlib numeric + text utility round-out** — four pure-NURL
  additions (no compiler changes, each with an offline test):
  - `stdlib/std/int.nu`: `int_gcd`, `int_lcm`, `int_isqrt` (Newton-method
    exact floor sqrt). Test `compiler/tests/int_extra.nu`.
  - `stdlib/std/float.nu`: `float_trunc`, `float_cbrt`, `float_hypot`,
    `float_log2`, `float_log10` (direct libm FFI) + pure-NURL
    `float_sign`. Test `compiler/tests/float_extra.nu`.
  - `stdlib/core/string.nu`: `string_join` (complement of `string_split`)
    and `string_count` (non-overlapping occurrence count). Test
    `compiler/tests/string_join_count.nu`.
  - `stdlib/core/char.nu`: `is_upper`, `is_lower`, `is_hexdigit`,
    `to_upper_ascii`, `to_lower_ascii`, `hex_val`. Predicates use the
    same `# i <bool-expr>` shape as the existing `is_alpha` / `is_digit`
    family — now returning a canonical 1/0 thanks to the cast fix below.
    Test `compiler/tests/char_extra.nu`.

### Fixed

- **Pointer-vs-integer comparison emitted invalid IR.** `gen_binary`
  produced `icmp eq i8* %p, 0`; comparison operators now `ptrtoint` any
  pointer operand to `i64` and compare in `i64`, so `== raw 0`
  null-checks compile. Found bringing `postgres.nu` to production grade.
- **`^ <void-call>` (returning a `→ v` call) emitted a value return.**
  Returning the result of a void function now lowers to `ret void`
  instead of attempting to return a non-existent value. Found in the
  postgres work.
- **A bare numeric/string literal as a statement is now a hard compile
  error.** Previously `& m 255 0x40` (single `&`) silently discarded the
  trailing `0x40` — a bare-literal discard statement the compiler
  accepted — which masked a real masking bug in the Game Boy PPU's
  STAT-bit-6 handling. `gen_block_stmts` / `gen_block_ret` now reject a
  bare literal whose value is unused. (The no-workarounds dividend from
  debugging dmg-acid2.)
- **`# i <bool>` now zero-extends (was -1 for true).** Casting a boolean
  (an `i1` from a comparison / `&` / `|` / `!`) to a wider integer
  emitted `sext i1`, so `# i true` was -1 instead of 1. Harmless for the
  ubiquitous `!= 0` callers, but it silently broke every predicate
  documented as "→ 1": `is_alpha` / `is_digit` / `is_space` /
  `is_alnum_us` all returned -1 for true. NURL has no signed 1-bit type,
  so a boolean true is canonically 1 — `gen_cast` now forces `zext` for
  any `i1` source (comparisons never set the `__last_unsigned__`
  side-channel that the unsigned-widen path relies on, hence the explicit
  guard). Latent fix across the whole stdlib; no existing test output
  changed (nothing depended on the -1). Regression
  `compiler/tests/cast_bool_int.nu`. Bootstrap fixed point holds
  (stage1 ≡ stage2 byte-identical at 1 660 838 B).
- **`HttpOptions` struct (HTTP client)** — `stdlib/ext/http.nu` gained
  `HttpOptions { i timeout_ms, i connect_timeout_ms, i follow_redirects,
  i max_redirects, i verify_tls, s user_agent }` bundling the per-request
  transport overrides that were previously hardcoded in the libcurl
  orchestrator. New entry points: `http_options_default → HttpOptions`,
  `http_request_with_opts`, and `http_get_opts` / `http_post_opts`
  conveniences. The orchestrator body moved into
  `__libcurl_perform_full_opts` (wires `CURLOPT_FOLLOWLOCATION` /
  `MAXREDIRS` / `SSL_VERIFYPEER` / `SSL_VERIFYHOST` / `USERAGENT` from the
  struct); the legacy timeout-only `__libcurl_perform_full_to` is now a
  thin shim over it, so `http_request` / `http_request_to` are
  behaviour-preserving. `user_agent` is borrowed `s` so HttpOptions owns
  nothing (no free fn, safe by-value). WinHTTP / stub backends honour
  only the two timeouts (redirect / TLS / UA ignored — documented).
  Stdlib-only; compiler IR unperturbed. Tests: offline
  `compiler/tests/http_options.nu` (always-on) + a live `GET_OPTS` case
  in `compiler/tests/http_basic.nu`.
- **`examples/h2c_server.nu`** — minimal cleartext-HTTP/2 ("h2c,
  prior-knowledge") echo server (~135 LOC). Async accept loop via
  `stdlib/std/async.nu` so h2spec's probe + test connections can be
  served concurrently; per-conn read timeout of 1 s keeps the
  sequential accept queue draining when a test deliberately leaves
  a connection half-open; response body sized ≥ 5 bytes so the
  `dataLen >= 5` gate in h2spec §6.9.2/2 runs the test instead of
  skipping. Verified green under both `./nurl.sh` and
  `NURL_SAN=1 ./nurl.sh`.
- **`examples/ws_echo.nu`** — minimal WebSocket echo server (~110
  LOC). Uses the stdlib `ws_perform_handshake` + `ws_serve_messages`
  pair against the same TCP accept loop. Per-server `WsLimits`
  raises `fragment_max_count` to 131 072 so autobahn §9.x's 4-MiB
  message split into 65 536 frames assembles successfully; per-
  frame and per-message byte caps stay at the stdlib defaults.
- **`NURL_SAN=1` support in `nurl.sh`** — drops `-flto`, adds
  `-fsanitize=address,undefined -fsanitize-address-use-after-scope
   -fno-omit-frame-pointer -fno-sanitize-recover=all` at the link,
  and builds a side-by-side `stdlib/runtime_san.o` (non-LTO,
  matching flags) if `stdlib/runtime.c` is newer than the cached
  artefact. Matches the toolchain `./build.sh --san` already uses
  for its own corpus.
- **HPACK lowercase-header-name encoder** (`stdlib/ext/http2_hpack.nu`
  `__hpack_lower_name_dup`) — RFC 9113 §8.2.2 mandates lowercase
  header field names on the wire; `hpack_encode_headers` now
  lowercases every name before encoding. Previously curl's HTTP/2
  parser rejected our `Content-Type` response header.
- **Inline WINDOW_UPDATE pump in `__h2_send_response`** — when the
  stream OR connection send-window is exhausted mid-response, the
  writer reads frames off the peer and applies WINDOW_UPDATE /
  SETTINGS / PRIORITY semantics in place (RFC 9113 §5.2.1, §6.9.1).
  HEADERS for a new stream during the pump is refused with
  RST_STREAM(REFUSED_STREAM) per §5.1.2. Empty `DATA(END_STREAM)`
  fallback (§6.9.1 permits zero-length DATA + END_STREAM regardless
  of window state) closes the stream cleanly when the pump bails.
- **HTTP/2 request HEADERS validation pass** (`__h2_validate_request_
  headers` in `stdlib/ext/http2_conn.nu`) — RFC 9113 §8.3 / §8.2.1 /
  §8.2.2: lowercase names, pseudo-headers precede regular ones,
  exactly one `:method` / `:scheme` / `:path` (non-empty), no
  duplicate or response-only or unknown pseudo-headers, no
  connection-specific headers (`Connection`, `Proxy-Connection`,
  `Keep-Alive`, `Transfer-Encoding`), and `TE` — if present — holds
  exactly `"trailers"`. Runs immediately after HPACK decode succeeds
  on both the HEADERS+END_HEADERS and HEADERS+CONTINUATION+
  END_HEADERS paths.
- **HTTP/2 frame-validation pass** — SETTINGS / GOAWAY / RST_STREAM
  / PRIORITY / DATA stream-ID + length + ACK rules per §6.5 / §6.4
  / §6.3 / §6.1 / §6.8.
- **HEADERS-on-existing-open-stream = trailers** (§8.1) — accepting
  a HEADERS frame on a stream already in `open` / `half-closed-
  local` state as the trailers section. Trailers MUST carry
  END_STREAM; decoded fields are discarded but `end_stream_received`
  is marked and the handler is dispatched.
- **PUSH_PROMISE rejection** (§6.6) — client→server PUSH_PROMISE is
  now PROTOCOL_ERROR (we advertise SETTINGS_ENABLE_PUSH=0).
- **§5.3.1 self-dependency check** for PRIORITY and HEADERS-with-
  PRIORITY-flag — a stream MUST NOT depend on itself; rejected as
  PROTOCOL_ERROR.
- **§6.9.1 flow-control overflow detection** — WINDOW_UPDATE that
  carries a stream's or connection's send-window above 2^31-1 is
  now FLOW_CONTROL_ERROR (stream-level → RST_STREAM, conn-level →
  GOAWAY).
- **§5.1 idle-stream WINDOW_UPDATE** — WINDOW_UPDATE on a stream
  with sid > last_peer_stream_id (never opened) is PROTOCOL_ERROR;
  on a closed stream silently no-ops.
- **HPACK §4.2 dynamic-table-size-update placement check** — size
  updates after any indexed/literal field in the block are
  COMPRESSION_ERROR (new `seen_field` flag in `hpack_decode_block`),
  and the new size is bounded by `h2_default_header_table_size`
  (4 096) — our advertised SETTINGS_HEADER_TABLE_SIZE — rather than
  the table's current `max_size`, which may have been lowered by a
  previous update in the same connection.
- **§8.1.1 content-length consistency check** (`__h2_content_length
  _mismatch`) — when a request carries `content-length`, the sum of
  DATA-payload lengths MUST equal that value. Mismatched (or
  unparseable, or duplicated and disagreeing) content-length becomes
  PROTOCOL_ERROR before handler dispatch.
- **RFC 6455 §5.5.1 / §7.4.2 WebSocket close-frame validation** —
  payload length 1 → `WsInvalidCloseCode` (close code 1002, not
  1000); status code outside 1000–2999 OR 1004 / 1005 / 1006 /
  1015 / 1016+ → close 1002; close-reason bytes validated as UTF-8.
  Previously a close frame's payload was discarded outright and the
  server replied with `WsClosedByPeer` → 1000 regardless of what the
  peer sent.
- **TCP_NODELAY on accepted sockets** (`stdlib/runtime.c`,
  `nurl_tcp_accept`) — disables Nagle's algorithm on every accepted
  TCP connection. Small framing-level ACKs (SETTINGS-ACK, PING-ACK,
  WINDOW_UPDATE) were otherwise pinned behind the previous write
  for up to 40 ms, which is exactly the window h2spec's per-test
  short timeouts can't tolerate.
- **`h2_default_header_table_size` constant** in
  `stdlib/ext/http2_frame.nu` — value `4 096`, used as the upper
  bound for HPACK dynamic-table-size updates and matches the
  RFC 9113 §6.5.2 default for SETTINGS_HEADER_TABLE_SIZE.

### Changed

- **`scan_fn_sigs` is now brace-depth-tracked** — only TT_AT / TT_AMP
  / TT_DOLLAR / TT_PERCENT openers at depth 0 trigger their
  respective dispatch branches; everything inside `{ ... }` advances
  silently. Matches the pattern `scan_type_names` already used (see
  the docstring there). Closes the family of param-walk-desync bugs.
- **HTTP/2 GOAWAY-receive no longer triggers immediate shutdown** —
  per RFC 9113 §6.8 the receiver of GOAWAY MUST keep processing in-
  flight frames (PING, RST_STREAM, in-progress streams) until the
  peer closes the socket; only NEW stream creation is forbidden.
  Previously we hard-exited the serve loop on the first GOAWAY,
  which broke the h2spec GOAWAY-then-PING sequence.
- **HTTP/2 invalid-preface error path** sends GOAWAY only when the
  preface was structurally invalid (`H2FrameBadPreface`); on a read
  error (timeout / EOF / IO) we tear down silently. GOAWAY-on-
  every-preface-error was being seen by h2spec's per-test probe
  connections and counted as the test response.

### Fixed

- **`scan_fn_sigs` brace-depth desync** — the `@` inside a closure-
  shaped struct field type (`( @ HttpResponse HttpRequest ) handler`)
  was treated as the start of a function declaration; the param
  walker then read `HttpResponse` as the phantom `fname` and the
  NEXT type-name-shaped token (in `stdlib/ext/http_server.nu`,
  `DosLimits`, declared 5 lines later) as that phantom function's
  `ret_ty`, silently writing `syms["HttpResponse"] = "%DosLimits"`.
  `gen_match`'s wide-payload reconstruction for a
  `: ! HttpResponse WsErr rr (...)` binding then looked up
  `syms["HttpResponse"]` to size the heap-box load and emitted
  `inttoptr i64 ... to %DosLimits*` + `load %DosLimits` + `bitcast
   %DosLimits* ... to i8*` against the real HttpResponse pointer.
  Under -O1+ this manifested as a runtime nurl_peek of a misaligned
  sub-page address (the HttpResponse i64 status field read as a Vec
  ctl). Under -O0 the extra reload of the alloca round-tripped the
  bits exactly so the struct's field accesses happened to land at
  the right offsets, hiding the bug.
- **`__h2_stream_to_request` double-freed `req.query`** when the
  request had no `?` in the path — the field was freed
  unconditionally but only reassigned inside the `qi >= 0` branch.
  `request_free` then freed the dangling pointer again. Clear ASan
  use-after-free on the very first h2c request through h2spec.
- **`__h2_decode_stream_headers` freed the old `cur.dec_dyn` before
  assigning the new `dd.dyn`** — but `HpackDynTable.entries` is
  aliased through the by-value pass into `hpack_decode_block`, so
  the two wrappers shared one Vec ctl. The free turned the new
  assignment into a dangling pointer; subsequent reads on
  connection close tripped nurl_peek.
- **`hpack_decode_block` failure path freed `cur`** — but `cur` was
  initialised from the input `dyn` (struct copy, entries Vec
  pointer-aliased), so freeing in the error path left the caller's
  `dec_dyn` pointing at a freed Vec entries pointer. The next
  h2_conn_free vec_free_with double-freed.
- **`__h2_frame_err_to_conn` returned bare enum tags from `??`-arm
  bodies** when the function return type wrapped them as a struct;
  follow the established `__net_err_of` convention with explicit
  `# H2ConnErr Tag` casts so the IR's `ret %H2ConnErr` matches the
  function signature.
- **`nurl_str_slice_unsafe` did pointer-load instead of pointer
  arithmetic** — `. rp from` lowers to "load the byte at rp+from",
  not "compute address rp+from". The code intended an unsafe
  substring view (rp + from interpreted as a string pointer); now
  spelled `# s + # i raw from` (cast-add-cast).
- **Two latent parenthesised-operator compile errors** in
  `stdlib/ext/http2_conn.nu` — `( % n 6 )` and `( . rp from )`. The
  diagnostic that rejects these landed 2026-05-22 but
  `http2_conn.nu` was never on the build/test path, so they sat
  silently until `examples/h2c_server.nu` pulled the file in.
- **`__pow2` defined in two translation units** — once in
  `stdlib/ext/http_response.nu` (used for hex-format expansion) and
  once in `stdlib/ext/http2_hpack.nu` (used for HPACK integer
  width). Linker rejected the redefinition the first time both
  modules were used together; the HPACK helper is now
  `__hpack_pow2`.
- **`__h2_apply_settings` sign-extension** — byte-shift-and-OR
  assembly of the 24-bit length / 32-bit value fields used `# i u`
  to widen each payload byte without masking, so any byte ≥ 0x80
  propagated as a negative i64 into the next shift, corrupting
  `value`. Fixed with explicit `& 255` masks at every byte read; the
  same fix applied to the WINDOW_UPDATE increment decode in the
  main serve loop and in `__h2_pump_one_frame`.
- **`autobahn-testsuite §6.4.1-4` UTF-8 fail-fast** — accepted as
  NON-STRICT (the spec permits either streaming UTF-8 rejection or
  whole-message validation; we do the latter). Documented for
  follow-up work.

### Tooling / dev experience

- **`./build.sh --san` ASan/UBSan corpus runs WebSocket close
  validation** end-to-end through autobahn-testsuite's first seven
  case sections (92/92 OK; 0 sanitizer findings).
- **`docs/GOTCHAS.md` remains empty** — every gotcha surfaced
  during the interop push (parenthesised-operator calls, sign-
  extension, `__pow2` collision, enum-tag-cast-on-return) is
  diagnosed by the compiler at compile time.
- **`.github/workflows/bench.yml`** — reproducible CI bench runner.
  Triggers on push-to-main (paths-filtered to bench/, compiler/,
  stdlib/, bench.yml itself), `workflow_dispatch`, and a weekly
  Monday 06:00 UTC cron. Installs clang + rustup stable + the FFI
  libs the regular `ci.yml` uses, bootstraps nurlc, runs
  `bench/run.sh 5` on a fixed `ubuntu-latest` 2-vCPU runner, and
  uploads the results as a workflow artifact. Manual / scheduled
  runs additionally commit a refreshed `bench/RESULTS_CI.md` back
  to main. The README's headline numbers (captured on a 12-core Intel
  @ 3.5 GHz) stay in `RESULTS.md` as the hand-captured figures;
  `RESULTS_CI.md` is the reproducible baseline.

### Tokeniser-aware token-efficiency baseline

- **`bench/token_efficiency.py` + `bench/TOKEN_EFFICIENCY.md`** —
  BPE-aware token counts using `tiktoken`'s `cl100k_base`
  (GPT-3.5 / GPT-4 / Claude legacy), `o200k_base` (GPT-4o /
  o-series), and `gpt2` (proxy for Llama-3, which is HF-gated)
  against every cross-language benchmark in `bench/`. NURL/Python
  BPE-aware token-count ratios on these three benchmarks are
  0.82–0.95× (LCG, all encoders) / 1.88–2.06× (sieve) /
  1.60–1.77× (json_parse).
- **`bench/{lcg,sieve,json_parse}.nu` cleanup** — dropped the
  redundant `$ "stdlib/core/io.nu"` import (the `puts` and
  `nurl_str_int` calls resolve through the compiler's libc/runtime
  prelude) and switched the trailing print from
  `( puts ( nurl_str_int x ) )` to the one-call
  `( nurl_print_int x )`. `sieve.nu` also drops the redundant FFI
  decls for `malloc` and `free` (both pre-registered by
  `init_syms`). Net result: −29 to −80 source bytes per file, NURL
  token counts down ~6–10 % across every encoder, and `@main` LLVM
  IR is byte-identical for both compute benchmarks.

### Borrow checker

- **`--strict-borrowck` (off by default)** — opt-in mode that
  extends two existing on-by-default checks:
    - **Aliased mutation through `. obj field` arguments.** The
      default N-readers-XOR-1-writer check fires only when both
      aliasing arguments at a call site are bare identifiers.
      Strict mode also recognises `. obj field` as an access of the
      root binding `obj`, so `( swap c . c n )` is now flagged when
      one of the arguments is `inout`. The iterator-invalidation
      check is widened in the same shape.
    - **`# *T <owned-binding>` raw-pointer escape.** When a `*T`
      cast's source binding sits on any of the auto-drop
      side-tables (`__owned_strings__` / `__owned_slices__` /
      `__owned_struct_fields__`) OR is a non-parameter heap binding
      (%Struct / enum / aggregate, mirroring the move-tracker's
      `bck_let_alias` heuristic), strict mode flags the cast: the
      binding's auto-drop at scope exit invalidates the pointer.
- Regression tests `compiler/tests/borrow_strict_field_alias.nu`
  and `compiler/tests/borrow_strict_raw_ptr_escape.nu` — both
  compile cleanly under the default checker and error out under
  `--strict-borrowck`. `compiler/tests/run_tests.sh` recognises any
  `borrow_strict_*` filename and adds the flag automatically.
- Bootstrap fixed point unchanged: strict mode is purely a
  diagnostic-only analysis pass.



## [0.9.2] — 2026-05-28

### Summary

`play.nurl-lang.org` no longer runs Python at runtime. `nurlapi/` is
a 3 000+-LOC NURL HTTP server with a full Model Context Protocol
server over `/mcp` (15 tools, 7 resources, 1 prompt), serving five
cross-compile build targets (native ELF, wasm32-wasi, mingw-w64
PE32+, macOS Intel, macOS Apple Silicon + the rest of the
`/build_target` registry). One static NURL binary is PID 1 inside
the runtime image.

A `nurl_poke` / `nurl_peek` byte-vs-slot index overrun in
`server_run_pool` (and three other call sites) that scribbled 7×N
bytes past a worker-handles buffer is fixed. The overrun had
manifested as random route / closure corruption under thread load.

Full test corpus + sanitiser corpus (ASan + UBSan + LSan, 281 tests)
green. Bootstrap fixed point at 1 620 300 B (stage1 ≡ stage2
byte-identical IR).

### Added — pure-NURL playground server (`nurlapi/`)

Replaces the Python FastAPI playground end-to-end. One static NURL
binary as PID 1; the runtime image is a slim Debian-bookworm stage
that only needs clang-16 + the cross-compile toolchains baked in.

**Route surface** (POST unless noted):

- `/build` → native Linux x86_64 ELF
- `/build_wasm` → wasm32-wasi (uses `prepare_ir_for_wasi` IR shim;
  wasm32 ABI rename + libc shims for `malloc` / `puts` / `write` etc.)
- `/build_windows` → mingw-w64 PE32+ via two-stage `clang -c` then
  `x86_64-w64-mingw32-gcc` link (static libcurl chain when the
  `runtime.win.curl` marker is present)
- `/build_macos` → Mach-O via zig cc
- `/build_target` → multi-target dispatch (linux-x64-musl,
  linux-arm64-musl/-gnu, linux-riscv64-musl, macos-x64, macos-arm64,
  windows-x64) over a single shared `_build_zig_cross` helper
- `GET /examples`, `GET /examples/*name` — bundled example listing +
  individual source
- `GET /stdlib`, `GET /stdlib/*path` — recursive .nu listing (84
  entries) + per-file `{name, source, bytes}` JSON
- `GET /tests`, `GET /tests/*path` — same shape for the compiler
  test corpus (281 entries)
- `GET /targets` — target registry (the dropdown the UI builds from)
- `GET /readme` / `/readme.md`, `/roadmap` / `/roadmap.md`,
  `/gotchas` / `/gotchas.md`, `/grammar.ebnf` — doc passthroughs +
  HTML-rendered alternates (pure-NURL Markdown→HTML renderer:
  headings, fenced code, bold/em, code spans, links, autolinks,
  images, ul/ol, blockquote, hr; tables + nested lists deferred)
- `GET /LICENSE-MIT`, `/LICENSE-APACHE`, `/NOTICE`, `/license`,
  `/license/{mit,apache}` — license endpoints (raw + HTML-wrapped)
- `GET /openapi.json` — minimal but valid OpenAPI 3.1 doc enumerating
  every public route
- `GET /health` → toolchain status (60+ stdlib modules + per-tool
  liveness)
- `GET /mcp-info` → MCP server probe (tools / resources / prompts
  catalogue + a `client_config_example` built from the request's
  Host header or `NURL_PUBLIC_URL`)
- `GET /download/:id/:file` → built artifact download
- OAuth 2.0 / OIDC rubber-stamp stubs so Claude-Desktop-class MCP
  clients that probe `.well-known/*` succeed: `oauth-protected-
  resource` (+`/mcp`), `oauth-authorization-server`, `openid-
  configuration`, `POST /register`, `GET /authorize` (instant 302),
  `POST /token`
- Static UI at `/`, `/favicon.{ico,svg}`, `/static/*`, `/*path`

**Build response shape** mirrors `api/` (Python) exactly: combined
`stdout` / `stderr`, parsed `nurlc_errors[]` (`{file, line, col,
message}`), `ll_artifact` + `binary_artifact` with `{name, bytes,
download_url, token}`, `nurlc_returncode` / `clang_returncode`,
`uses_canvas` / `uses_audio`. New shared helpers:
`parse_nurlc_diagnostics`, `combine_stderr`, `make_artifact_json`,
`stamp_build_response`, `nurlc_failure_response`,
`push_native_runtime_libs`.

`nurlapi/Dockerfile` — two-stage Debian bookworm image. Stage 1
bootstraps nurlc, downloads WASI SDK 24 + Zig 0.13, builds a static
libcurl-mingw for the Windows target, pre-builds the six zig-target
runtime objects + warms the zig per-target libc cache so the first
`/build_target` per target is a fast cache hit rather than a cold
multi-second libc compile, compiles the nurlapi binary itself.
Stage 2 is a slim runtime image (clang-16 + cross-compile toolchains
only, no Python).

`nurlapi.sh` — bring-up wrapper. `./nurlapi.sh` builds + runs on
port 8000; `./nurlapi.sh bind` skips the Docker rebuild and bind-
mounts the freshly-built local binary + stdlib + examples + tests
+ root docs into the running container (inner dev loop: edit `.nu`
→ `./nurlapi.sh bind` → hit endpoint, ~30 s vs ~10 min). Flags:
`--no-cache` / `--port=N` / `--rm` / `--detach` / `--build-only` /
`--name=NAME` / `--help`.

`nurlapi/e2e_test.{py,sh}` — end-to-end test driver covering every
endpoint.

### Added — full MCP server over `/mcp`

`stdlib/ext/mcp_http.nu` + `nurlapi/main.nu`. Streamable HTTP
transport (POST /mcp), FastMCP handshake parity:

- `initialize` (protocolVersion `2025-03-26`, FastMCP capabilities
  shape, `instructions` blurb verbatim, serverInfo `nurl-playground
  0.9.2`)
- `ping`, `tools/list` (15 tools), `tools/call` (dispatch by name)
- `resources/list` (7 `nurl://` URIs), `resources/read`
- `prompts/list` (1 prompt: `nurl_coding_assistant`), `prompts/get`
- `notifications/*` (no reply, 202 Accepted)
- JSON-RPC 2.0 batches (top-level array → array reply,
  notifications dropped per spec)

**Tools (full Python parity):**

- Build (5) — `nurl_build_native`, `nurl_build_wasm`,
  `nurl_build_windows`, `nurl_build_macos`, `nurl_build_target`
  (enum-typed target id)
- Browse (3) — `nurl_list_examples`, `nurl_list_stdlib`,
  `nurl_list_tests`
- Read (7) — `nurl_read_example`, `nurl_read_stdlib`,
  `nurl_read_test`, `nurl_read_grammar`, `nurl_read_readme`,
  `nurl_read_roadmap`, `nurl_read_gotchas`

Build tools dispatch via loopback HTTP to the server's own `/build`
endpoints (`NURL_MCP_LOOPBACK_URL`, default `http://127.0.0.1:8000`):
zero duplication of the canonical handler logic.

**Reliability fixes vs Python reference:**

1. **Session persistence across container restarts.** Python
   validated `Mcp-Session-Id` against a per-process in-memory
   whitelist — fresh pod = fresh whitelist = previously-issued sids
   rejected. NURL approach: session ID is opaque to the server.
   First request (no sid) → server generates 16-hex-char sid, echoed
   in `Mcp-Session-Id` response header; subsequent requests with sid
   → echoed verbatim, no validation. Pod restart → client sid still
   accepted, no reconnect required.
2. **Burst handling.** Python's asyncio event loop serialised
   request handling. NURL piggybacks on `server_run_pool`'s
   16-pthread worker pool — every POST /mcp gets its own worker
   thread, no serialisation. Measured: 50 concurrent `tools/list`
   in 65 ms wall on a single host (~770 req/s peak).

**Streamable HTTP content-negotiation** in `stdlib/ext/mcp_http.nu`:
when the client sends `Accept: text/event-stream` (every official
SDK does), the JSON-RPC reply is wrapped as `event: message\r\ndata:
<json>\r\n\r\n` with `Content-Type: text/event-stream` +
`Cache-Control: no-cache`. Legacy clients without the Accept header
still get plain `application/json`.

### Added — `http_router` HEAD + OPTIONS

`router_handle` now answers HEAD and OPTIONS requests without each
handler having to know about them — same shape FastAPI / Express /
most modern HTTP frameworks ship by default.

- **HEAD** (RFC 7231 §4.3.2): treated as a GET for the purpose of
  route matching — falls through to the GET handler, then pins
  `Content-Length` to the GET body's would-have-been length and
  clears the body Vec so the wire-level serialisation emits headers
  + blank line + zero bytes.
- **OPTIONS** (RFC 7231 §4.3.7): the router answers directly, no
  handler involved. Walks every registered route, collects distinct
  methods whose pattern matches the request path, auto-adds HEAD
  (when GET is among them) and OPTIONS (always), returns 204 No
  Content with the assembled `Allow:` header. Root-level catch-alls
  (patterns starting with `/*`) are excluded from OPTIONS
  enumeration so they don't pollute the advertised method list.

Two new helpers: `__strip_body_for_head`, `__router_options`.

Verified live against nurlapi: `OPTIONS /health` → 204 `GET, HEAD,
OPTIONS`; `OPTIONS /build` → 204 `POST, OPTIONS`; `OPTIONS
/nonexistent` → 404 (catch-all filter working); `HEAD /health` →
200 `Content-Length: 1570`, body 0 bytes.

### Fixed — `nurl_poke` / `nurl_peek` byte-vs-slot heap overrun (critical)

`server_run_pool` in `stdlib/ext/http_server.nu` allocated an N×8-byte
buffer for N worker thread handles and then wrote into it with
`nurl_poke thandles (* j 8) traw` — passing a **byte offset** where
`nurl_poke` expects a **slot index**. `nurl_poke` scales by 8
internally, so each "write at byte offset j*8" actually landed at
byte offset j*64 — scribbling 7×N bytes past the buffer end.

The overrun survived for years because it consistently hit the
malloc arena's slack-padding zone, which on glibc was unallocated
"redzone-shaped" space between the worker-handles block and the
next live allocation. The behaviour only collapsed once enough other
heap traffic crowded the arena and a real load-bearing allocation
landed in the spillover window — at which point one of the routes,
or its `RouteImpl` pointer, or its closure environment, would get
clobbered and the next request through that route would crash.

This was previously misdiagnosed as a `Vec[Route]` multi-field-struct
stride hazard under pthread + clang -O2 (the boxed-handle pattern in
`stdlib/ext/http_router.nu` was added as a workaround for the
symptom). Route storage was always sound; routes just happened to
share the arena page that got smashed. The `http_router.nu` comment
block has been rewritten to credit the real cause.

ASan caught the real root cause when `nurlapi/main.nu` grew from 14
to 22 routes — the bigger router-build allocation budget shifted
what landed in the spillover. Same anti-pattern was present in three
other call sites, fixed atomically:

- `stdlib/ext/http_server.nu` `server_run_pool` (3 sites: 2 poke + 1 peek)
- `stdlib/ext/postgres.nu` `pg_exec_params` (2 sites)
- `compiler/tests/thread_basic.nu` (2 sites — masked by malloc slack)

Each: `(nurl_poke buf (* j 8) v)` → `(nurl_poke buf j v)`.

Regression test `compiler/tests/nurl_poke_slot_index.nu` allocates
an N×8 buffer (N=32, well past any malloc-slack forgiveness zone),
writes N distinct markers, reads them back, verifies bit-for-bit.
Under ASan in `run_san_tests.sh` it fails-fast as
`heap-buffer-overflow` on the first overrun if anyone reintroduces
the byte-as-slot mistake.

### Fixed — playground init no longer blocks on a CDN

`<script type="module">` in `api/static/index.html` and
`nurlapi/static/index.html` started with a top-level
`import { … } from "https://esm.sh/@bjorn3/browser_wasi_shim@0.3.0"`.
ES-module top-level imports are awaited before any statement in the
module body runs — if esm.sh is slow, blocked, or rejected by the
browser (ad-blocker, CSP, offline cache, transient DNS), the module
never reached its first statement, so `refreshHealth()`,
`loadExamples()` and `loadTargets()` never fired. The health pill
stayed "checking…", dropdowns stayed empty, and the page looked
like the server's `/health` was down even though the server was fine.

Fix: replace the static import with a lazy `import(WASI_SHIM_URL)`
inside a `loadWasiShim()` helper, called only from inside `run()` —
the one place that actually needs the shim. The module body now has
zero top-level awaitable imports and initialises synchronously. A
CDN failure surfaces in `run()`'s `logLine` path and aborts only
that one Run-click, not the whole page.

### Changed — `/build_windows` two-step compile (clang) + link (mingw-gcc)

Mirrors Python `api/`'s approach: `clang --target=x86_64-w64-mingw32`
is great at parsing IR but its mingw linker driver can't resolve
mingw-w64's installed support libraries (`-lgcc`, `-lwinpthread`,
`crtbeginS.o`, etc.). Single-step `clang ... runtime.win.o -o
out.exe` therefore fails with `/usr/bin/x86_64-w64-mingw32-ld:
cannot find -lgcc`. Two steps fix it:

1. `clang --target=x86_64-w64-mingw32 -c file.ll -o file.o` — clang
   compiles IR to a mingw-flavoured object.
2. `x86_64-w64-mingw32-gcc file.o runtime.win.o -lpthread …
   [optional libcurl] -o file.exe` — mingw's own gcc owns its
   libgcc / libwinpthread / CRT search paths and finishes the link
   cleanly.

The optional libcurl chain (`-L<curl-mingw>/lib -lcurl -lws2_32
-lcrypt32 -lbcrypt -lncrypt -lsecur32 -ladvapi32`) is added only
when the `stdlib/runtime.win.curl` marker is present — same gate
Python uses. Combined stderr now layers all three stages
(`nurlc` → `clang -c` → mingw-gcc link) so the playground's "BUILD
FAILED" panel surfaces whichever stage actually errored;
`final_rc` prefers the compile return code over the link return
code (a failing compile produces the more actionable diagnostic).

Five compile targets now produce real binaries end-to-end:

- `/build` → 78 KB Linux ELF
- `/build_wasm` → 232 KB wasm32-wasi
- `/build_windows` → 1.18 MB PE32+ EXE
- `/build_macos` → 19 KB Mach-O (Intel)
- `/build_target macos-arm64` → 52 KB Mach-O (Apple Silicon)

### Changed — small fixes & perf polish

- `stdlib/std/bytes.nu` — speed-up to the byte-walk helpers used on
  parser hot paths (direct `*u` pointer reads where the bounds check
  is already proven by the loop invariant).
- `stdlib/ext/http_response.nu` — minor allocation-count reduction
  on the response-build path.
- `bench/http_server.nu`, `bench/run.sh`, `bench/run_http.sh` —
  small harness tweaks for the local bench host.
- `README.md` — updated headline benchmark numbers;
  `nurlapi/README.md` added (96-line operator manual for the
  pure-NURL playground + inner-loop dev workflow).
- `examples/{enigma,fizzbuzz,msgpack_demo,wordcount}.nu` — minor
  polish picked up while testing playground rendering.
- `nurlapi/static/viewer.html` — new stdlib / tests source viewer
  (linked from the playground UI).
- `cloudflare/Dockerfile`, `dockerpush.sh`, `startdev.sh` — incidental
  updates so the prod image build & local dev port (8001 vs api/'s
  8000) coexist cleanly.

## [0.9.1] — 2026-05-26

### Summary

- Borrow checker promoted to hard errors by default. Five bug
  classes are compile errors: use-after-move, alias double-free,
  closure escape, aliased mutable-borrow at call sites, iterator
  invalidation. `--no-borrowck` is the escape hatch.
- UDP datagrams (dual-stack IPv4/IPv6 with multicast) + standalone
  DNS resolver (`getaddrinfo` / `getnameinfo`).
- JSON parser ~34× faster — pure-NURL `stdlib/ext/json.nu` rewritten
  around a single-pass scanner; 479 ms → 14 ms on the
  `bench/json_parse` micro-benchmark.
- Peer benchmarks in `bench/` compare NURL with Python / Rust / Node
  on three reproducible micro-benches plus an HTTP-server-vs-Rust-
  hyper / Node-http sweep.
- GitHub Actions workflow with parallel build-test + sanitizer
  (ASan + UBSan) jobs.
- `docs/spec.md` (~1 000 lines) covers the semantic side the grammar
  EBNF does not.
- Generic signal handling, structured logging, silent-miscompile
  diagnostics.

Bootstrap fixed point: stage1 ≡ stage2 byte-identical IR at
1 620 300 B. Full test corpus + sanitizers green.

### Added — UDP datagram sockets + full DNS resolver

Three new public surfaces:

1. **`stdlib/std/udp.nu`** — pure-NURL wrapper over runtime §18b. Dual-
   stack IPv4/IPv6 by default (wildcard `udp_bind("", 0)` creates an
   `AF_INET6` socket with `IPV6_V6ONLY=0` so a single fd serves both
   v4 and v6 peers; literal `udp_bind("127.0.0.1", 0)` stays IPv4-only
   on purpose). Sync + fiber-aware async on every send/recv: inside a
   fiber, `udp_recv_from` / `udp_send_to` park on the reactor on
   EAGAIN; outside any fiber, they fall back to blocking I/O
   transparently. Exposed surface:
   - lifecycle: `udp_bind`, `udp_bind_any`, `udp_connect`, `udp_close`
   - send/recv: `udp_send_to`, `udp_send_str_to`, `udp_recv_from`,
     `udp_send`, `udp_recv` (last two for connected-mode UDP)
   - address: `udp_peer_addr` (borrowed), `udp_local_addr` (owned
     String — how the caller discovers the kernel-assigned ephemeral
     port after `udp_bind("", 0)`)
   - options: `udp_set_timeout`, `udp_set_nonblock`, `udp_set_broadcast`
   - multicast: `udp_join_group`, `udp_leave_group`,
     `udp_set_multicast_ttl`, `udp_set_multicast_loop`. `iface` arg is
     intentionally minimal (IPv4 IP literal or numeric ifindex; no
     `if_nametoindex` so Win32 doesn't need `-liphlpapi`).

2. **`stdlib/std/dns.nu`** — pure-NURL wrapper over runtime §18c.
   System-resolver-based (`getaddrinfo` / `getnameinfo`), no c-ares
   dep. Three entry points:
   - `dns_resolve host` → `! ( Vec String ) NetErr` of A/AAAA literals
     in the kernel's preferred order, dedup'd.
   - `dns_resolve_port host port` → same, but each entry is formatted
     as `"ip:port"` (IPv4) or `"[ip]:port"` (IPv6, RFC 3986 §3.2.2)
     ready for direct `tcp_connect` / `udp_connect`.
   - `dns_reverse ip` → `? String` (Some only when there's a real PTR
     record — `NI_NAMEREQD`).

3. **Runtime §18b / §18c (`stdlib/runtime.c`)** — implementation:
   - `NurlUdp { fd, err_kind, family, peer }` opaque handle (~16 % the
     size of `NurlTcp` — UDP has no TLS state to track).
   - 22 new `nurl_udp_*` and 3 new `nurl_dns_*` exports; WASI stub
     row at the bottom degrades every call to `NetOther` /
     `strdup("")` so `wasm32-wasi` builds still link.
   - Reuses §18's `NURL_NET_ERR_*` error space + `nurl__net_map_errno
     / _wsa` mapping helpers; multicast group-family branching uses a
     new `nurl__parse_numeric_addr` (`AI_NUMERICHOST`) so callers
     don't have to thread family flags through the NURL API.
   - DNS results come back as newline-separated heap strings; NURL
     splits and dedupes are deferred to the wrapper (`__dns_split_lines`).

Acceptance:

- `compiler/tests/udp_basic.nu` — always-on (loopback only, no live
  network). Covers send_to/recv_from roundtrip, peer-addr capture,
  connected-mode send/recv on a separate pair, zero-length datagram,
  wildcard dual-stack bind, broadcast + multicast TTL / loop
  setsockopt smoke. Exit 0, output matches `correct.txt` baseline.
- `compiler/tests/dns_basic.nu` — always-on (uses literals + the
  `/etc/hosts` `localhost` mapping that every Linux/macOS/Win box
  has, no external DNS). Covers resolve + resolve_port for both IPv4
  and IPv6, IPv6 bracketed-port formatting, reverse lookup, empty-
  input → `Err NetOther`.

Runtime LOC delta: `stdlib/runtime.c` 4 790 → 5 606 (+816, +17 %)
including the WASI stub row. Bootstrap fixed point unchanged at
**1 620 300 B** (stage1 ≡ stage2 byte-identical IR) — the runtime
extension is pure stdlib, no compiler IR perturbation.

### Added — HTTP peer-bench (Tier D #3, 2026-05-25)

`bench/run_http.sh` + `bench/http_server.{nu,js}` +
`bench/rust_http_server/` (Cargo + hyper 1.9 + tokio multi-thread)
close the long-standing "no Rust hyper / Node http peer comparison"
gap that critic v0.9.0 §10 flagged. Drives `oha` 1.8.0 against three
hello-world servers at four concurrency levels (1, 10, 50, 200),
median of 3 × 10 s per cell. Captured numbers + commentary in
`bench/HTTP_RESULTS.md`:

| Server  | C = 1    | C = 10   | C = 50   | C = 200  |
|---------|---------:|---------:|---------:|---------:|
| NURL    | 14 451   | **68 960** |  60 897  |  59 044  |
| Rust    | 14 507   |  47 703  | **86 699** | **114 694** |
| Node    |  8 708   |  16 726  |  17 108  |  15 555  |

(req/s, higher is better, best in bold per column.)

Highlights:

- NURL is parity with Rust hyper at C=1 (within < 1 %), and is **1.45× ahead**
  of hyper at C=10 — NURL's 8-worker pool fits the workload while tokio's
  12-worker default is over-provisioned at that concurrency.
- Rust hyper pulls ahead at C ≥ 50, peaking at 115 k/s vs NURL's 59 k/s
  (1.94×) at C=200.
- NURL has **the lowest tail latency across the whole sweep**: p99 0.62 ms
  at C=200 vs Rust's 6.19 ms and Node's 20.95 ms.
- Node http plateaus at ~16 k/s — textbook single-event-loop signature.

The Go `net/http` half of the originally-asked-for comparison is
deferred: Go was not installed on the bench host at capture time.
`bench/run_http.sh` has the lane reserved and `bench/README.md`
documents the gap — a PR adding `bench/http_server.go` would re-publish
a four-column table.

### Added — More examples + refreshed catalogue (Tier D #4, 2026-05-25)

Two-part deliverable closing ROADMAP §6 "More Examples":

1. **`examples/find_clone.nu`** — grep-style recursive search over
   files / directories with three modes:

   ```
   find_clone PATTERN [PATH ...]                  # literal substring
   find_clone --list PAT[,PAT...] [PATH ...]      # comma-separated alternatives
   find_clone --regex PAT [PATH ...]              # POSIX-extended regex
   ```

   PATH is one or more files or directories — directories recurse,
   dotfiles are skipped, and with no PATH the tool reads stdin. Output
   is `path:line:contents` per match; exit 0 on any match, 1 on no
   match, 2 on usage / I/O error. Closure-shaped matchers
   (`make_literal_test`, `make_list_test`, `make_regex_test`) so
   `scan_lines` is mode-agnostic; `walk_dir` returns -1 on
   not-a-directory so the dispatcher falls back to the file scanner
   cleanly. Built on top of `stdlib/std/fs.nu` (`read_file`,
   `dir_list`), `stdlib/ext/regex.nu` (`regex_compile` / `_test`), and
   the existing `nurl_str_*` helpers. Pure CLI I/O — runs on the
   public playground.

2. **`examples/README.md` refresh** — from a 3-of-36 catalogue to all
   36 rows, organised by category (CLI tools / Algorithms / Data
   formats / Language showcase / HTTP & RPC / LLM API / SDL canvas).
   Each row carries a one-line description plus a **playground** or
   **local** tag describing where it can run. *playground* = pure
   compute + stdin / argv / file I/O (runs on `play.nurl-lang.org`
   as-is); *local* = needs network, a server listening port, an
   `ANTHROPIC_API_KEY`, SDL2, or microphone access.

The critic-suggested agent-loop variants and MCP-client demo were
deliberately omitted: `examples/claude_agent.nu` already covers the
agent shape, and an MCP-client-from-the-public-playground would need
either secret injection (API keys) or WASM outbound sockets,
neither of which the playground exposes today.

### Added — GitHub Actions CI (critic v0.9.0 Tier D #2, 2026-05-25)

`.github/workflows/ci.yml` lifts the previously-local build + test +
sanitiser gate to PR-level. Two parallel jobs on `ubuntu-latest`:

- **`build-test`** — installs clang + optional FFI dev libs
  (`libcurl4-openssl-dev`, `libssl-dev`, `libsqlite3-dev`,
  `libpq-dev`, `zlib1g-dev`, `libzstd-dev`) so every
  `stdlib/runtime.<lib>` sentinel lights up, then runs `./build.sh`
  (bootstrap stage1 ≡ stage2 fixed point + the full `run_tests.sh`
  corpus). 15-min timeout.
- **`sanitizers`** — same setup, runs `./build.sh --san --no-tests`
  to build an ASan + UBSan-instrumented stack, then
  `compiler/tests/run_san_tests.sh` over the corpus. 25-min timeout.

Triggers on push to `main` / `Improvements`, PR-to-`main`, and
`workflow_dispatch` (manual rerun). `concurrency.cancel-in-progress`
cancels older runs when a new commit lands on the same ref so the
queue can't fill up on a fast-typing day.

`nurlfmt --check` is deliberately NOT yet wired up — ~100 .nu files
in the current stdlib / tests / examples corpus (and
`compiler/nurlc.nu` itself) are not in canonical form, so adding the
check today would fail every PR with an unrelated 100-line diff.
The follow-up path is documented inline in the workflow comments:
either a single repo-wide `nurlfmt --write` pass first, or grow the
check scope file-by-file as canonicalisation lands.

### Added — Structured logging (critic v0.9.0 Tier D #1, 2026-05-25)

`stdlib/std/log.nu` gains two structured-logging features that the
critic flagged as missing-for-v1.0 (ROADMAP §2):

1. **Key/value variants** — `log_debug_kv1` / `_kv2` / `_kv3`,
   `log_info_kv1..3`, `log_warn_kv1..3`, `log_error_kv1..3`. Twelve
   fixed-arity helpers that accept 1..3 `s` key / `s` value pairs
   alongside a message. Same below-threshold suppression as the raw
   and `fN` variants.

2. **JSON output mode** — `log_set_json T` / `log_set_json F`,
   `log_get_json`. When JSON is on, every `log_*` call emits a single
   `{"level":"info","msg":"…","key":"value",…}` line instead of the
   `[INFO]  msg key=value` text form. Compatible with `jq`, Logstash,
   Loki, CloudWatch, etc. — values are RFC 8259-compliant (named
   escapes for `"` `\` `\n` `\r` `\t`; remaining control bytes
   0x00..0x1F emit `\u00XX`).

The existing raw `log_<level>` and `log_<level>fN` calls route
through the new shared `__log_dispatch` so JSON mode applies
uniformly to every call site. The per-byte JSON-escape walker uses
a `*u` pointer instead of `nurl_str_get` to avoid the O(strlen)
per-character cost. Compiler / bootstrap untouched; regression
`compiler/tests/log_structured.nu` exercises text mode, JSON mode,
escape coverage and below-threshold suppression. `jq -c .`
round-trips every JSON line emitted by the test.

### Added — Tier A diagnostics for the v0.9.0 critic (2026-05-25)

Closes the four "grammar-legal but semantically dead" cases the
external review flagged as silent compiles. Each is a small, local
compiler change; bootstrap fixed point holds (stage1 ≡ stage2
byte-identical IR at **1 620 300 B**); full test corpus green.

1. **`^` vs `^^` XOR confusion `warning:`** — `gen_ret` peeks the
   token after the returned expression. If it is on the same source
   line as the `^` AND is value-producing (not `:` / `=` / `;` / `}`
   / `)` / `]` / `{` / EOF), the user almost certainly wrote `^ X Y`
   intending XOR. Emits a soft `warning:` naming `^^` (two adjacent
   carets, no space) as the cure. Test: `should_warn_caret_xor.nu`.
2. **Bare-callable-as-statement `error:`** — `gen_stmt` checks for
   `name args` (no parens) at statement position. If `name` is a
   known callable (registered in syms with no `__ptr` / `__global`
   / `__param`), dies with `( name args )`-cure pointer. The
   companion `gen_ffi_decl` now stamps `<name>__ffi = 1` so FFI
   builtins like `nurl_print` are detected alongside @-fns. Test:
   `should_fail_bare_ident_stmt.nu` (PoC: `nurl_print \`oops\``).
3. **Use-after-`_free` via wrapper `error:`** — auto-infer `sink`
   convention on parameters that a function passes to a destructor
   (`*_free`) or to another fn's existing `sink` slot. New helper
   `bck_record_inferred_sink` accumulates into
   `__fn_inferred_sink__` per fn body; `gen_fn_decl_concrete`
   merges into `g_fn_sink[fname]` after body parses, deduping
   against the explicit `sink` marker. Closes the indirect
   `( take s ) ( read s )` use-after-free the critic exhibited.
   Test: `should_fail_uaf_indirect.nu`. Also added
   `str_word_index` helper next to `str_contains_word`.
4. **Per-instantiation source line for generics** — replaces the
   opaque `<generic>:1:21:` synthetic filename with
   `<generic vec_as_slice__i64 from user.nu:42>:1:21:` so a parse
   error during the substituted-body re-parse names the call site
   in the user's own code. `defer_instantiation` now captures the
   call-site file + line; `flush_deferred_instantiations` passes
   them to `emit_one_instantiation`, which builds the synthetic
   filename. (Diagnostic-only — IR unchanged.)

### Changed — `stdlib/ext/json.nu` parser ~34× faster (2026-05-25)

`json_parse` of the `bench/json_parse` payload (5 × 64 KB) dropped
from **479 ms** to **14 ms** — now faster than Python's C-extension
`json` (~34 ms) and within ~3× of a hand-written zero-copy Rust
parser (~5 ms). Two landed changes:

1. **Direct `*u` pointer reads instead of `nurl_str_get`.** Every
   `__jp_peek` was paying a full `strlen` of the whole input (the
   `core/string.nu` helper does an `strlen` for the bounds check) —
   a 64 KB parse spent gigabytes of memory bandwidth in `strlen`
   alone, classic O(n²). Replaced with a cached `*u`-based byte read
   against `. p src`, plus a `memchr`-driven fast path in
   `__jp_parse_string` that slices the literal byte range when the
   string contains no `\` escape (the common case).

2. **Packed-layout `String` constructor.** New
   `core/string.nu::string_from_bytes_packed` allocates the 24-byte
   `Vec` control block and the data buffer in a single
   `nurl_alloc(24 + n + 1)`. `vec_free` / `vec_free_with` /
   `__vec_grow` in `core/vec.nu` detect the layout by `data ==
   ctl + 24`; the lifecycle is byte-identical to a normal String
   (it can still grow — the first growth pays for an unpacking copy
   out into a separate buffer). For JSON parsing every `JNum` /
   `JStr` is read-only after construction, so this exact case halves
   the per-string allocation count.

Bench runner (`bench/run.sh`) also stopped forking `date` twice per
measurement by switching to `$EPOCHREALTIME` arithmetic (bash 5+),
shaving ~3 ms of measurement overhead per cell.

`bench/RESULTS.md` and `README.md` updated with the new headline
numbers. Bootstrap fixed point holds; full test corpus green;
no API or grammar changes.

### Added — `bench/` peer-comparison benchmark suite (2026-05-25)

Three reproducible micro-benchmarks with one source file per language
(NURL, Python 3, Rust, Node.js):

* `bench/lcg.{nu,py,rs,js}` — 100M-step MMIX linear congruential
  generator. Tight i64 multiply + add with a single-stream data
  dependency that defeats LLVM's closed-form folding.
* `bench/sieve.{nu,py,rs,js}` — Sieve of Eratosthenes computing
  π(10 000 000) = 664 579. Memory bandwidth + branch prediction.
* `bench/json_parse.{nu,py,rs,js}` — 5 parses of a deterministic
  ~64 KB JSON file. Each language uses **what ships in its standard
  distribution** (Python `json`, Node `JSON.parse`, NURL
  `stdlib/ext/json.nu`; Rust links a small hand-written
  recursive-descent parser since it has no JSON in stdlib).

`bench/run.sh` compiles each NURL + Rust target, runs every present
language N times (default 5) with a per-run `timeout`, and prints a
median-wall-clock-ms table. Missing tools render as `n/a`; a cell that
hits the timeout renders as `>30s` instead of hanging the suite.

`bench/RESULTS.md` captures the numbers from one specific machine:

* On `lcg` and `sieve` NURL lands within measurement noise of Rust —
  same LLVM `-O2 -flto` codegen on both sides.
* On `json_parse` NURL's pure-NURL parser is ~12× slower than Python's
  C `json` and ~50× slower than a hand-written Rust parser. The
  module's allocator-and-Vec-growth path through recursive descent is
  the explanation, and a zero-copy slice-based rewrite would close
  most of the gap — tracked as a follow-up.

An HTTP-server-vs-`net/http` peer benchmark is not included; that
would need a Go install and a `wrk`-shaped harness.

### Changed — borrow-checker diagnostics are now hard errors

* `bck_diag` (use-after-move) and `bck_esc_warn` (escape analysis +
  aliased-mut + iterator invalidation) emit `: error: ` instead of
  `: warning: ` and bump a new `g_bck_errors` counter. `main()` exits
  non-zero after `parse_program` if any violation was recorded —
  every error surfaces in one run (same shape as a C compiler).
* The test harness now treats `borrow_*` tests as expected compile
  failures with an `ERRORS` baseline blob rather than "compile OK +
  WARNINGS". The exact error text remains regression-protected.
* `--no-borrowck` remains the escape hatch; the abort message points
  at it so a user hitting a false positive is never wedged.
* Bootstrap fixed point holds (the checker is diagnostic-only — IR is
  byte-identical with or without `--no-borrowck`): stage1 ≡ stage2 at
  **1 602 394 B**.

Five bug classes are now compile errors by default: use-after-move,
alias double-free, closure escape, call-site aliased mutation, and
iterator invalidation. `*T` raw pointers and aliased mutation through
nested-argument reads remain unchecked; see
[`docs/MEMORY.md`](docs/MEMORY.md).

## [0.9.0] — 2026-05-24

### Changed — `refactor/nurlify` branch

Picks up where `refactor/pure-nurl` left off and drives `stdlib/runtime.c`
the rest of the way down:

* **`stdlib/runtime.c`: 6 265 → 4 540 LOC (−1 725, −27.5 %).** Combined
  with the prior branch the total reduction since v0.8.0 is **8 879 →
  4 540 LOC (−4 339, −48.9 %)** — over half of the C runtime is gone.
  Bootstrap fixed point held on every shipped phase; full test corpus
  green.
* **PURIFY §17 random.** `rand_u64` / `rand_hex_str` ported to pure
  NURL in `stdlib/std/random.nu`. Only `nurl_rand_fill` stays C —
  the `getrandom` / `arc4random_buf` / `BCryptGenRandom` platform
  branching is genuinely syscall-shaped FFI.
* **PURIFY §4 file ops batch.** `nurl_read_file_bytes` /
  `_write_file_bytes` / `_file_read_chunk` / `_read_n_bytes` /
  `_errno_kind` moved to pure NURL. The `g_last_bytes_len` sideband is
  gone — `fread` / `fwrite` write directly into the `Vec[u]` data
  buffer and `vec_set_len` records the count. `EACCES` / `EPERM` /
  `EEXIST` added to `nurl_native_constant`; `errno_kind` now lives in
  `stdlib/core/posix.nu`.
* **PURIFY §22 gzip.** `nurl_gzip_compress` / `_decompress` moved to
  pure-NURL FFI in `stdlib/ext/compress.nu` over `deflateInit2_` /
  `deflate` / `deflateEnd` + `inflateInit2_` / `inflate` /
  `inflateEnd`. Two tiny C accessors (`nurl_z_setup` /
  `nurl_z_total_out`) bridge the platform-varying `z_stream` field
  layout (LP64 vs LLP64 `uLong` width).
* **PURIFY §14 HTTP response accessors.** The 7 accessor C functions
  (`status` / `err_kind` / `body` / `body_len` / `header_count` /
  `header_name` / `header_value`) deleted from `runtime.c`. Pure-NURL
  equivalents in `stdlib/ext/http.nu` read the `NurlHttpResponse`
  heap struct via `nurl_peek(p, slot)` over its 6-i64 slot layout.
  Static asserts in `runtime.c` pin the layout at compile time so a
  future field reorder breaks the native build instead of silently
  miscompiling NURL reads. `nurl_http_response_free` stays C because
  it walks `headers[]` deallocating each name / value pair plus the
  body.
* **PURIFY §14b HTTP libcurl backend** + multi-stream orchestration
  driven from pure NURL. Sync `nurl_http_perform_full_to` and
  multi-stream `_open_to` / `_next` / `_pump_headers` plus the 5
  stream accessors live in `stdlib/ext/http.nu`; 22 monomorphic
  trampolines stay C (`nurl_curl_*` `setopt` / `multi` /
  stream-state) because libcurl's variadic `curl_easy_setopt` and the
  raw-fn-pointer callbacks (`nurl__http_write_body` /
  `_write_header`) can't cross the FFI directly. `NurlHttpStream`'s
  three historical `int` fields widened to `long long` for a clean
  14×i64 slot layout; `static_assert` pins it. Live verified
  against httpbin.
* **PURIFY §2 SIMD CSV scanner** ported to pure NURL
  (`stdlib/ext/csv.nu`, −508 C). The vectorised newline / delimiter
  scanner is now NURL @-fns over `nurl_peek` of a heap-side byte
  window.
* **`runtime.c` prose cleanup** (commits `d558844`, `f88d7bb`):
  trimmed verbose multi-paragraph explanations, phase-by-phase
  migration history and prose that just restated what the code does
  — kept one-line function-purpose intros and the non-obvious "why"
  notes (TLS / SNI race discipline, fiber park-unlock ordering,
  wasm32 layout caveats, libz LP64 / LLP64 differences). Net −913
  comment-only LOC.

### Changed — `JSON-to-production` branch

* **`json` ext goes production-ready.** `stdlib/ext/json.nu`:
  - **Typed `JsonError`** replaces the bare `ParseErr` — carries
    `kind` (`BadFormat` / `Empty` / `TrailingGarbage` / `Overflow`),
    `pos` (0-based byte offset), `line` (1-based) and `col`
    (1-based). Location is computed once per failure and travels
    with the error value — no global state, so nested
    `json_parse` calls and multi-threaded use are both safe.
    `json_format_error` renders the standard message; build your
    own from the fields if you need a custom shape.
  - **RFC 8259 strict mode.** Non-conforming numbers (leading zeros
    like `01`, `+5`, lone `.5`, `1.`) are now `BadFormat` instead of
    parsing to the prefix — `json_stringify ∘ json_parse` is
    guaranteed-valid JSON.
  - **New constructors** — `json_int n` / `json_float x` from
    primitives (no `i8*` roundtrip), `json_arr_new` / `json_obj_new`
    for empty containers.
  - **Duplicate-key behavior documented.** Parser preserves
    duplicate keys as-is; `json_obj_get` returns the first match in
    source order; `json_obj_set` replaces the first match in source
    order.
  - Call sites updated across `stdlib/ext/anthropic.nu`,
    `stdlib/ext/mcp{,_client,_http,_stdio}.nu`, `nurlapi/main.nu`,
    `examples/serde_demo.nu`, `tools/nurl-lsp/jsonrpc.nu`.

### Changed — `refactor/pure-nurl` branch

The `refactor/pure-nurl` branch took the bulk of `stdlib/runtime.c`
out of C and into pure NURL — either as pure-NURL @-fns or as direct
`& \`c\`` / `& \`pthread\`` / `& \`sqlite3\`` FFI declarations.

* **`stdlib/runtime.c`: 8 879 → 6 265 LOC (−2 614, −29.4 %).** The
  bootstrap fixed point held on every shipped phase and the full
  test corpus stayed green.
* **Python removed from the bootstrap.** `compiler/nurlc.py` and
  `compiler/src/*.py` are gone. Stage 0 now links the committed
  `compiler/nurlc_lastgood.ll` snapshot directly via clang. The
  only build-time dependency is clang/LLVM 14+. Refresh the
  snapshot with `./build.sh --refresh-bootstrap` when a
  grammar/runtime-ABI change leaves the current snapshot unable
  to compile current `nurlc.nu`.
* **`Box[T]` / `Cell[T]` / `Rc[T]` / `Arc[T]`** heap-stable
  allocator surface — `stdlib/core/box.nu`, `stdlib/core/cell.nu`,
  `stdlib/std/rc.nu`, `stdlib/std/arc.nu`. `% Drop` auto-fires;
  `nurl_native_sizeof` + `nurl_atomic_i64_*` runtime primitives
  added. This unblocked Phases 6 / 8 / 11 / 12 of the purification.
* **Per-phase migration:**
  - Phase 1 §3 char classification (`stdlib/core/char.nu`, −11 C)
  - Phase 2 §15 logging level (`stdlib/std/log.nu`, −7 C)
  - Phase 3 §11 libm + integer helpers (`& \`m\`` / `& \`c\`` FFI, −17 C)
  - Phase 4 §17 crypto MD5/SHA-1/256/512 + HMAC
    (`stdlib/std/hash_*.nu`, **−541 C**)
  - Phase 5 §2 string ops over libc (strlen/strcmp/strncmp/strstr/
    memcmp/memmem/atoll/atof/memcpy/strdup via preamble, **−682 C**)
  - Phase 6 §19 threads / mutex / cond (pthread `& \`pthread\``
    FFI in `stdlib/std/thread.nu`, −162 C; mingw-w64 winpthreads
    linked via `-lpthread`)
  - Phase 7 §4 + §13 file & dir syscalls — incremental over many
    batches (realpath / write_file_safe / file_size / mmap / fread
    fallback / dir_list POSIX, −158 C combined)
  - Phase 8 §16 + §16b process spawn (fork/exec/poll, `||` and
    `&&` added as language tokens for the spawn-error sideband,
    **−245 C**)
  - Phase 9a §7 + §8 codegen counters + last-type sideband
    (pure-NURL @-fns in `nurlc.nu`, −71 C)
  - Phase 9b §6b symbol table (3 parallel grow-by-2× arrays,
    inner loops via direct `*s` / `*i` pointer arithmetic, −72 C;
    ~0.95× of C runtime — LTO inlines everything and the parallel
    layout is cache-friendlier than the C interleaved struct)
  - Phase 9c §5 HashMap deleted entirely (the canonical
    `stdlib/std/hashmap.nu` HashMap[s i] is the one-true map for
    every consumer; the migration also fixed `hash_string` from
    O(n²) → O(n) by switching from per-byte `nurl_str_get` to a
    direct `*u` byte walk, −101 C)
  - **Phase 10 §6a Lexer (the big one, −592 C).** Full state
    machine + 4-deep lookahead ported to pure-NURL @-fns over a
    280-byte heap handle. Uncovered + fixed a subtle escape-handling
    bug: only `\n \t \r \\` are real escapes; any other `\X`
    (including `` \` ``) writes the lone `\` and advances one byte.
  - Phase 11 §23 DoS protection (`stdlib/std/dos.nu`, −180 C)
  - Phase 12 §21 SQLite bridge — pure-NURL FFI over 18 libsqlite3
    symbols (`stdlib/ext/sqlite.nu`, **−330 C**)
  - §12 Time — `clock_gettime` + `nanosleep` FFI (`stdlib/std/time.nu`,
    −38 C; macOS uses `CLOCK_MONOTONIC = 6` vs `1` elsewhere, read
    at runtime via `nurl_native_constant`)
  - §13 batch 2/3 — stdin + dir_list POSIX FFI (−80 C)
  - §11 strtod sideband eliminated with an endptr buffer (−20 C)
* **`||` and `&&` operators** added as language tokens — strict
  binary, bool-only short-circuit. Alternative to the chainable
  `|` / `&` for cases that are more readable as a `||` / `&&`
  chain. Grammar v2.0 documents them. Same LLVM IR as `|` / `&`
  on i1 left operands.
* **`./check.sh <file.nu>`** — per-file syntax/type check tool;
  runs `nurlc` against a single source file in ~0.2 s vs build.sh
  ~60 s. Use in iterate-fix loops before kicking the full build.
* **Test runner output split** into `success.txt` + `failures.txt`
  so a failed test is greppable without scrolling through the
  green output.
* **Parenthesised-operator diagnostic.** A `(` begins a call, so
  `( . obj field )` / `( | a b )` / `( + x y )` etc. now produce
  a precise call-site `error:` instead of a far-away LLVM-verifier
  complaint. (Listed earlier in this section under the original
  feature work; reiterated here as it landed in this branch.)
* **Call-arity diagnostics.** Every call's argument count is
  checked against the callee's declared parameter count; a
  mismatch points at the call site (same listing remark).
* **Prefix arity-cascade diagnostic.** Short-an-argument prefix
  operator over-reads now name the offending token and point back
  at the line where the cascade started.
* **`mcp_response_get_result`** — `mcp_client`'s 1-arg result
  extractor renamed for consistency with the rest of the surface.

### Fixed — `refactor/pure-nurl` branch

* **WASM FFI width mismatches** uncovered by uuidgen wasm build
  (2026-05-24). `nurl_errno_get` / `nurl_errno_set` /
  `nurl_wait_is_exited` / `_exit_status` / `_is_signaled` /
  `_term_sig` paluut + parametrit widened `int` → `long long`
  in `stdlib/runtime.c`. On x86_64 SysV the `int` return's upper
  32 bits were undefined and accidentally zero; wasm-ld validates
  signatures strictly and refused to link until the C side
  agreed with the NURL FFI's `→ i` (i64) declaration. `memmem`
  added to `api/app/main.py:LIBC_WASM32_ABI` (the playground's
  wasm-build IR rewriter), since wasm32 `size_t` is i32 but
  `nurlc.nu`'s preamble emits `memmem(i8*, i64, i8*, i64)`.
* **macOS `WIFEXITED` lvalue requirement.** The widened
  `nurl_wait_*` functions originally passed `(int)status` as an
  rvalue to the W*-macros; macOS's `<sys/wait.h>` expands them
  to `*(int*)&(x)` which needs an lvalue. Fixed by binding
  `int s = (int)status;` first inside each wrapper. Restores the
  zig macOS-arm64 / macOS-x64 cross-build.

### Added

* **MsgPack serde.** `stdlib/ext/serde.nu` gained `from_msgpack_i` /
  `from_msgpack_f` / `from_msgpack_b` / `from_msgpack_string` —
  decoding MessagePack bytes straight to a built-in value. There is no
  `% MsgpackSerialize` trait: MessagePack and JSON share a data model,
  so a value is encoded by composing the existing `to_json` with
  `msgpack_encode`. The decoders return `!T MsgpackErr` (not
  `ParseErr` — `MsgpackErr` is the richer error type and represents
  every failure losslessly); `MsgpackErr` gained a
  `MsgpackTypeMismatch` variant for a value that decoded cleanly but
  is the wrong shape. Demo `examples/msgpack_demo.nu`; regression
  `compiler/tests/msgpack_serde.nu`. With this the serde story covers
  JSON, TOML and MessagePack — all reusing one `JsonSerialize` impl
  per type.

* **TOML serde.** `stdlib/ext/serde.nu` gained its TOML side: a
  `% TomlSerialize [T] { @ to_toml T x → TomlValue }` trait with impls
  for `i` / `b` / `s` / `String`, and `from_toml_i` / `from_toml_b` /
  `from_toml_string` decoders returning `!T ParseErr` — the same shape
  and error type as the JSON helpers. There is no `f` impl: the
  `TomlValue` AST has no float variant. `stdlib/ext/toml.nu` gained
  `toml_stringify`, the inverse of `toml_parse`: a `TomlValue` is
  rendered as TOML text — top-level `key = value` lines, nested tables
  and arrays inline, strings escaped with the `\\ \" \n \r \t` set the
  parser accepts, so `toml_parse ∘ toml_stringify` round-trips.
  Regression `compiler/tests/toml_serde.nu`; verified leak-free under
  ASan/UBSan/LSan.

* **MessagePack codec.** `stdlib/ext/msgpack.nu` is a faithful binary
  codec between the `Json` value and the MessagePack wire format:
  `msgpack_encode Json → ! ( Vec u ) MsgpackErr` and `msgpack_decode
  ( Vec u ) → ! Json MsgpackErr`. The encoder emits the smallest
  signed integer format, float64 for reals, and length-appropriate
  str / array / map headers; the decoder accepts every integer and
  float format plus all str / array / map sizes. `bin` / `ext` and
  non-string map keys are reported as `MsgpackUnsupported`; truncation
  and malformed input have their own `MsgpackErr` variants; a
  recursion cap guards both directions. Three runtime helpers —
  `nurl_f64_bits`, `nurl_f64_from_bits`, `nurl_f32_from_bits` — provide
  the IEEE-754 bit access needed for the float wire format. Regression
  `compiler/tests/msgpack_basic.nu` (37 assertions: round-trips,
  msgpack.org encode vectors, non-canonical-format decoding, malformed
  inputs); verified leak-free under ASan/UBSan/LSan. First of the
  three Serde-completion ships (codec, then TOML serde, then MsgPack
  serde).
* **Runtime float-bits helpers** — `nurl_f64_bits`,
  `nurl_f64_from_bits`, `nurl_f32_from_bits` in `stdlib/runtime.c`.
* **Parenthesised-operator diagnostic.** A `(` begins a function call,
  so the token after it must be a function name. An operator token
  there — `( . obj field )`, `( | a b )`, `( + x y )` — meant an
  operator expression was wrongly wrapped in parentheses. nurlc used
  to take the operator's lexeme as the callee, emit a call to a
  function literally named `.` / `|` / `+`, and let the build fail far
  from the source at link time with `use of undefined value`.
  `gen_call` now rejects a binary operator, member access `.`, the
  cast `#` or the caret `^` immediately after `(` with a precise
  `error:` at the call site — `operator '.' cannot be a call target:
  '(' begins a function call, but operator expressions are written
  without parentheses` — and a caret on the operator. Regression
  `compiler/tests/should_fail_paren_operator.nu`.

* **Typed Path.** `stdlib/std/path.nu` gained a `Path { String inner }`
  typed, owning wrapper over a path string, with a concise
  Rust-PathBuf-style verb API — `path_new`, `path_str` (borrow the
  inner buffer), `path_len`, `path_is_empty`, `path_clone`,
  `path_free`, `path_eq`, `path_push` (join one component),
  `path_parent`, `path_name`, `path_is_abs` — and the two operations
  the existing string-level layer lacked: `path_canonical` (realpath:
  absolute, symbolic links resolved) and `path_relative_to` (a purely
  lexical relative path between two paths). Both return `? Path` —
  None for a missing / inaccessible path or a not-comparable pair. The
  string-`s`-based `path_*` functions stay the raw layer underneath;
  the typed functions never consume their arguments. One runtime
  helper, `nurl_realpath`, is reached through the pure-NURL `& \`c\``
  FFI model, so the compiler is unchanged and the bootstrap fixed
  point is byte-identical. Regression `compiler/tests/path_typed.nu`;
  verified leak-free under ASan/UBSan/LSan.
* **Runtime helper** — `nurl_realpath` (realpath on POSIX, `_fullpath`
  on Windows) in `stdlib/runtime.c`.
* **Extended hash family — SHA-512, MD5, HMAC-SHA-512.**
  `stdlib/std/hash.nu` gained `sha512_bytes` / `sha512_hex` (FIPS 180-4
  SHA-512, 64-byte digest), `md5_bytes` / `md5_hex` (RFC 1321 MD5,
  16-byte digest) and `hmac_sha512_bytes` / `hmac_sha512_hex` (RFC 2104
  HMAC over SHA-512). All are binary-clean — they take `( Vec u )` and
  are length-aware, so NUL bytes are preserved — mirroring the existing
  `sha1_bytes`. The three algorithms are self-contained in
  `runtime.c` §17 (no libsodium / OpenSSL dependency) and are reached
  through the pure-NURL `& \`c\`` FFI model, so the compiler is
  unchanged and the bootstrap fixed point is byte-identical. MD5 and
  SHA-1 are documented as compatibility-only — both are collision-broken
  and must not authenticate data or hash secrets. Regression
  `compiler/tests/hash_extended.nu` checks every algorithm against
  published vectors (RFC 1321 §A.5, FIPS 180-4, RFC 4231 HMAC cases
  1/2/6); verified leak-free under ASan/UBSan/LSan.
* **Runtime hash primitives** — `nurl_md5_bytes`, `nurl_sha512_bytes`,
  `nurl_hmac_sha512_bytes` in `stdlib/runtime.c`.
* **Advanced filesystem operations.** `stdlib/std/fs.nu` gained
  recursive directory operations and a streaming file reader:
  `dir_create_all` is mkdir -p — it creates every missing parent
  directory and treats an already-existing directory as success;
  `dir_remove_all` is recursive rm -rf — it walks the tree removing
  every entry before removing the directory itself, and unlinks a
  symlink rather than descending through it. `file_open` /
  `file_read_chunk` / `file_eof` / `file_close` read a file in
  fixed-size byte chunks over a new `File` handle, so a binary input
  far larger than RAM can be processed without ever being fully
  resident (line-oriented streaming stays with `stdlib/std/bufio.nu`).
  Three new `runtime.c` filesystem helpers back this — `nurl_path_type`
  (an lstat-based entry classifier), `nurl_file_read_chunk` and
  `nurl_file_eof` — all reached through the pure-NURL `& \`c\`` FFI
  model, so the compiler is unchanged and the bootstrap fixed point is
  byte-identical. Regression `compiler/tests/fs_advanced.nu`; the new
  paths are verified leak-free under ASan/UBSan/LSan.
* **Runtime filesystem helpers** — `nurl_path_type`,
  `nurl_file_read_chunk`, `nurl_file_eof` in `stdlib/runtime.c`.
* **Call-arity diagnostics.** `gen_call` now checks every call against
  the callee's declared parameter count and rejects a mismatch with a
  precise `error:` at the call site — e.g. `call to 'add' has the
  wrong number of arguments: expected 2, got 1`. Previously a
  wrong-arity call to a known function either miscompiled silently
  (too few arguments) or emitted a malformed `call` the LLVM verifier
  complained about far from the source (too many). `scan_fn_sigs`
  records each non-generic `@`-function's parameter count through a
  new pure-lexical type skipper (`scan_skip_type` — no `parse_type`
  call, which would desync the scan); a name carrying two definitions
  of differing arity is marked ambiguous and skipped rather than
  mis-blamed. Generic and variadic-FFI callees are out of scope for
  v1.
* **Prefix arity-cascade diagnostic.** When a prefix operator runs out
  of operands and over-reads into the following statement — the
  classic NURL cascade, since operators have fixed arity and no
  closing bracket — the resulting "unexpected token" error now names
  the offending token and points back at the line where the
  short-an-argument statement began, instead of blaming the innocent
  next line.
* **Compiler regressions** — `compiler/tests/{call_arity_ok,`
  `should_fail_call_arity_few,should_fail_call_arity_many,`
  `should_fail_prefix_cascade}.nu`.
* **MQTT client — topic-filter wildcard matching.** `mqtt_topic_matches`
  in `stdlib/ext/mqtt.nu` implements the MQTT 5.0 §4.7 `+` / `#`
  wildcard rules — `+` matches one topic level, `#` matches the
  remainder (zero levels included, so `sport/#` also matches the parent
  `sport`) — including the §4.7.2 guard that a filter beginning with a
  wildcard never matches a `$SYS/...` topic. The intended use is
  client-side dispatch when one connection carries several
  subscriptions.
* **MQTT offline codec regression** — `compiler/tests/mqtt_codec.nu`
  exercises the Variable Byte Integer round-trip, the unsigned byte
  reader, MQTT UTF-8 string framing, the CONNECT byte layout, CONNACK
  reason extraction, MQTT 5 user-property parsing, the typed `MqttErr`
  names, and topic matching — no network, CI-safe.

## [0.8.1] — 2026-05-21

### Added

* **Playground multi-target cross-compilation.** The `api/` browser
  playground replaces its four fixed build buttons (WASM / native /
  Windows / macOS) with a grouped **Target** dropdown + one **Build**
  button. New compile targets, all driven by the `zig cc` pipeline
  already shipped for macOS:

  * `linux-x64-musl`, `linux-arm64-musl`, `linux-riscv64-musl` —
    fully-static ELF (runs on any Linux of that arch, no libc pin).
  * `linux-arm64-gnu` — dynamic glibc 2.31+ ELF.
  * `macos-x64`, `macos-arm64` — Mach-O; Apple Silicon was previously
    unreachable (the only macOS target was Intel).

  Backed by `POST /build_target` (target id in the body) and
  `GET /targets` (the registry the UI builds its dropdown from); the
  three near-duplicate build endpoints now share one `_build_zig_cross`
  helper. `POST /build_macos` is kept as a thin wrapper for MCP / older
  clients. The MCP server (both `/mcp` and the REST companion) gains a
  `nurl_build_target` tool — valid target ids are inlined as a schema
  enum so clients need no separate lookup; the existing per-OS build
  tools are unchanged. canvas/audio FFI is rejected on the cross
  targets and HTTP falls back to the runtime's no-op stubs — same
  contract macOS had.

  Image cost is ~negligible: zig already bundles musl / glibc /
  libSystem for every arch, so each target adds only one ≈125 KB
  `runtime.<id>.o`. The Dockerfile cross-compiles those at build time
  and **pre-warms** each target's libc/compiler-rt into a baked
  `ZIG_GLOBAL_CACHE_DIR`, so the first build per target is a fast
  cache hit rather than a cold multi-second libc compile; the warm
  link doubles as a build-time smoke test. No `riscv64` glibc target —
  zig 0.13's bundled glibc for RISC-V is incomplete; `riscv64-musl`
  covers RISC-V until the image moves to zig ≥ 0.14.

* **`stdlib/std/time.nu` calendar completion.** On top of the existing
  `Time` struct and Hinnant `civil_from_days` conversions:

  * `is_leap_year`, `days_in_month` (leap-aware), `time_yday` (1..366).
  * `time_make Y Mo D H Mi S` — range-checked civil-time constructor
    (rejects e.g. 2023-02-29 and month 13).
  * `time_cmp` / `time_eq` / `time_before` / `time_after` — order
    timestamps (by Unix-second value).
  * `time_add_seconds` / `time_add_days` (negative subtracts; rolls
    month/year/leap-day over) / `time_diff_seconds`.
  * `time_format t fmt` — strftime subset (`%Y %y %m %d %H %M %S %j
    %a %A %b %B %%`), alongside the fixed `time_format_iso` /
    `time_format_http`.

  Regression `compiler/tests/time_calendar.nu`; `calendar_time.nu`
  updated. All pure NURL arithmetic, ASan/UBSan/leak-clean.

* **Buffered streaming reader — `stdlib/std/bufio.nu`.** `BufReader` pulls
  a file (or stdin) through a 64 KiB buffer one `fread` at a time, so an
  input far larger than RAM is processed without ever being fully
  resident — the streaming counterpart to `read_file` / `csv_reader_new`,
  which load the whole file first. Built for fast ETL over logs / CSV /
  JSONL:

  * `bufreader_open path → ! BufReader IoErr`, `bufreader_stdin → BufReader`.
  * `bufreader_read_line br → ? String` — a fresh owned line each call,
    `\n` / `\r\n` stripped; `None` at EOF.
  * `bufreader_read_line_into br dst → b` — refills the *caller's* String
    with the next line, so a steady-state read loop allocates nothing
    after warm-up (one `memcpy` per line, no `malloc`). The recommended
    ETL hot path.
  * `bufreader_eof`, `bufreader_close`.

  Line terminators are found with `memchr` (glibc SIMD), not a byte loop.
  Lines longer than the buffer grow it; lines straddling a refill
  boundary are compacted with `memmove`. Neither read entry point hands
  back a pointer into the internal buffer, so there is no
  invalidated-view foot-gun. Implemented as pure-NURL `& \`c\`` FFI
  (`fread` / `memchr` / `memmove` / `fdopen`) — no `runtime.c` change.
  New supporting primitive `string_push_bytes` (`stdlib/core/string.nu`)
  appends a known-length raw byte range to a String. Regressions
  `compiler/tests/bufio_basic.nu` (mixed terminators, empty + trailing
  unterminated line, missing-file error) and `bufio_stream.nu` (50 001
  lines across ~17 refills + a 200 000-byte line forcing buffer growth);
  both ASan + UBSan + leak-detection clean.

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
  `should_fail_inout_generic_forward.nu`.

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

### Changed

* **`time_parse_iso` now returns `! i ParseErr`** (Unix seconds), not
  `! Time ParseErr`. A Unix timestamp is the more composable parse
  result — directly sortable, comparable and storable — and
  `time_from_unix` reconstructs the broken-down `Time` when its fields
  are needed. The new `time_make` constructor uses the same
  `! i ParseErr` shape for consistency.

### Fixed

* **A side-effecting `~` while-loop condition no longer drops an
  iteration.** `gen_loop` speculatively parsed the condition (to tell a
  while loop from a complement expression used as a statement) and left
  that speculative IR in the output — so the condition was evaluated
  one extra time up front. For a pure condition this was harmless dead
  code; for a side-effecting condition (`~ ( read_next x ) { … }`) the
  first evaluation's side effects happened with no matching body run,
  silently dropping one iteration's work. `gen_loop` now emits the
  condition straight into the loop-check block and only then looks for
  the `{` — the condition is parsed exactly once and evaluated exactly
  (bodies + 1) times; no speculative IR. Regression
  `compiler/tests/loop_cond_sideeffect.nu`.

* **`?? ( call )` on a wide-payload `! T E` result no longer truncates.**
  Matching directly on a function-call expression whose Result payload
  is a wide value struct (a multi-field `Time`-like type) silently
  produced garbage fields: `gen_match`'s heap-box-unboxing
  reconstruction was keyed on `<name>__res_nurl_T`, which only exists
  when the scrutinee is a named binding — so `?? ( f … )` skipped it and
  the `T`-arm binding received the raw heap-box pointer reinterpreted as
  the struct. `gen_match` now synthesises the binding metadata from the
  callee's NURL return type (`__last_nurl_call__`, cleared before the
  scrutinee is evaluated), so the direct-call form reconstructs exactly
  like `?? r`. Narrow payloads (`i`, pointers, handle structs) were
  always fine. Regression `compiler/tests/match_call_wide.nu`.

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

### Fixed

* **`mcp_stdio_call` write-failure classification was racy.** Pinging a
  server that had already exited surfaced either `McpStdioEof` or
  `McpStdioIo` depending on whether the write hit `EPIPE` before the
  child's exit was observed — a non-deterministic result (and a flaky
  `mcp_stdio_basic` test). On a failed write `mcp_stdio_call` now
  consults `proc_eof`: if the child's stdout is also at EOF the server
  is simply gone (`McpStdioEof`, matching the write-lands-then-reads-EOF
  path), otherwise it is a genuine transient pipe fault (`McpStdioIo`).
  The dead-server outcome is now deterministic.

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

* **`inout` and `sink` parameter conventions.** `in` / `inout` /
  `sink` are contextual keywords recognised only as a parameter's
  leading token (no lexer change); `in` is the default.
  A parameter marked **`inout`** is an exclusive mutable borrow: the
  callee mutates the caller's binding in place. `inout T` lowers to a
  by-address `<T>*` parameter — the body reads/writes the caller's
  storage with no local copy — replacing the `*T`-parameter and
  return-the-struct mutation idioms. The argument must be a mutable
  (`: ~`) binding; an `inout` function must be defined before it is
  called. Exclusive-access check: a binding passed `inout` must be
  the only argument path to its value at that call — passing it
  again, as a second `inout` or a plain by-value argument, is a
  `warning:`.
  A parameter marked **`sink`** consumes (takes ownership of) its
  argument: it lowers to an ordinary by-value parameter, and the
  borrow checker records the argument binding as moved so a later
  use is a use-after-move. `sink` v1 applies to `Vec` and other
  manually-managed handles; passing a compiler-auto-dropped value
  (owned string / slice / `Drop` value / struct with owned fields)
  to a `sink` parameter is rejected pending drop-ownership transfer.

* **Static borrow checker, on by default.** A diagnostic analysis
  pass (disable with `--no-borrowck`) that never changes generated
  code — a
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

  Per-instantiation source-line precision for generics remains
  deferred.

## [0.7.2] — 2026-05-19

### Added

* **Serde-style `JsonSerialize` trait + decoder helpers
  (`stdlib/ext/serde.nu`).** A NURL trait `JsonSerialize [T] { @ to_json
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
  changelog URL. Drop-in for CI or a weekly cron.

### Added

* **DWARF debug-info support (compiler + driver).** `nurlc --g
  foo.nu` now emits LLVM `!DICompileUnit` /
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
  generics are not currently implemented.

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
  built on top of the existing `tcp_listen_tls` listener — the new
  operations attach to an
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

Full HTTP/2 server stack (RFC 9113 + RFC 7541) alongside WebSocket
(RFC 6455), gzip wire format (RFC 1952), and an AddressSanitizer +
UndefinedBehaviorSanitizer quality gate.
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

## [0.6.1] - 2026-05-17

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

The full per-feature breakdown follows.

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
* Documentation: `README.md` (project overview),
  `docs/GOTCHAS.md` (compiler quirks),
  `spec/grammar.ebnf` (v1.7 grammar).
* Tooling: VS Code extension (`tooling/vscode-nurl/`), Dockerised
  compile-server (`api/`), browser playground (`nurlweb/`).
* Dual license: MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE).

[Unreleased]: https://github.com/nurl-lang/nurl/compare/v0.9.4...HEAD
[0.9.4]: https://github.com/nurl-lang/nurl/compare/v0.9.3...v0.9.4
[0.9.3]: https://github.com/nurl-lang/nurl/compare/v0.9.2...v0.9.3
[0.9.2]: https://github.com/nurl-lang/nurl/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/nurl-lang/nurl/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/nurl-lang/nurl/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/nurl-lang/nurl/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/nurl-lang/nurl/compare/v0.7.3...v0.8.0
[0.2.0]: https://github.com/nurl-lang/nurl/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nurl-lang/nurl/releases/tag/v0.1.0
