# NURL v1.0 release-readiness worklist

Audit snapshot: **2026-10-03**, repository commit `fcae65b2`, latest recorded
release `0.69.1`.

This is the release-blocking worklist for the first stable NURL release. It is
not a feature wishlist. An unchecked item must be completed, or the affected
surface must be explicitly removed from the supported v1 scope everywhere it
is documented, packaged, advertised, and tested.

Status and priority:

- `[ ]` — open; release evidence is not yet sufficient.
- `[x]` — implemented foundation; it must remain green through the v1 release
  candidate.
- **P0** — safety, security, data-integrity, or release-integrity blocker.
- **P1** — required stability, compatibility, supportability, or usability
  work for the supported v1 surface.
- **P2** — release polish already named as a v1 project goal.

For an item to be checked, the repository should contain the implementation or
scope decision, focused regression tests, CI enforcement where practical, and
accurate user-facing documentation. A local one-off pass is not sufficient.

## 1. Freeze what v1 means

- [ ] **P0 — Define the supported v1 product surface.** Separate the stable
  language/compiler/runtime/stdlib/toolchain contract from experimental
  packages, cross targets, playground features, hosted services, and MCP
  integrations.
  - Publish one support manifest naming every included component, its owner,
    platform tier, stability level, and required release evidence.
  - A component may be excluded, but all documentation, installers, APIs, and
    marketing must then label it experimental or unsupported consistently.
  - Use this manifest as the source for the package/service test matrix and the
    final release gate. Existing starting points: `ROADMAP.md`,
    `docs/PLATFORMS.md`, and `docs/dev/V1_HARDENING.md` A01-A17.

- [ ] **P1 — Publish the v1 compatibility and deprecation policy.** The current
  project uses SemVer but does not define which interfaces become stable.
  - Cover source syntax and semantics, grammar editions, public stdlib APIs,
    CLI flags/exit codes/diagnostic formats, package manifests and lockfiles,
    registry protocol, generated modules, runtime objects, and NURL/FFI ABI.
  - Explicitly name interfaces that remain unstable. Define the 1.x support
    window, deprecation period, removal process, and security-fix exceptions.
  - Add compatibility fixtures made with older v1 compilers/packages/locks and
    gate accidental breaking changes. `nurl-version` also needs a maximum,
    range, or edition mechanism if future majors are not forward compatible.

- [ ] **P1 — Publish the security, support, and governance contract.** There is
  no `SECURITY.md`, maintainer/governance file, or CODEOWNERS policy, and the
  roadmap still lists bus factor as open.
  - Document supported versions, a real private vulnerability contact, response
    targets, advisory/CVE handling, embargoes, release-key custody, and incident
    roles.
  - Document maintainer, reviewer, merge, release, and emergency authority;
    encode mandatory branch checks and ownership for security-critical paths.
  - Satisfy or deliberately revise the roadmap requirement for an additional
    reviewer/maintainer before v1.

## 2. Language and runtime safety

- [ ] **P0 — Close the remaining safe-looking ownership holes.** *(0.71.0,
  #1165–#1167: maybe-moved reads, conditional double-frees, owner state
  through aggregates and containers, and closures kept by a callee are
  rejected; hole probes h01–h31 are all rejected and safe programs carry a
  stated guarantee, docs/MEMORY.md §6. Open: h32, a `Slice` of a `Vec`.)*
  Code using no
  raw pointer or FFI can still read a maybe-moved value in both modes, and can
  conditionally double-free under the default checker. Reads through a released
  aggregate owner and escaped closures also cross the current analysis boundary
  (`docs/MEMORY.md` sections 2.9, 2.11, 3, and 6.5).
  - Reject maybe-moved reads and definite conditional double-frees in the
    stable default, or require an explicit unsafe construct for unresolved
    paths; an opt-in flag is not a safe default.
  - Track owner state through aggregate/container conduits and closures stored,
    returned, or retained by a callee. Preserve the existing forward/generic
    coverage; require effect annotations, conservative rejection, or an explicit
    unsafe boundary when an indirect/unknown callee cannot be summarized.
  - Add minimal positive and negative witnesses for default,
    `--strict-borrowck`, `--no-borrowck`, raw-pointer/FFI, closure, aggregate,
    loop, and interprocedural paths, plus ASan/LSan runs.
  - Keep the claim in `docs/MEMORY.md` exactly as strong as the checks: since
    0.71.0 it is a guarantee for programs without `unsafe`, with the known
    exceptions listed beside it.

- [ ] **P0 — Make drop and generic ownership complete and machine-checkable.**
  Current documented gaps include option parameters whose untouched payload can
  leak and structs with enum or trait-object fields that are not wholly dropped
  (`docs/LIMITATIONS.md`). Several generic collection APIs rely only on prose
  saying that element types must be trivial.
  - Complete the drop graph for options/results, enums, trait objects, nested
    owning fields, reassignment, and all supported `sink` transfers, or reject
    unsupported owning shapes at compile time.
  - Add a `Copy`/`Clone`-equivalent bound, deep-cloning behavior, or separate
    borrowed/owned APIs for `vec_filter`/`vec_map`, HashMap views/iteration, set
    algebra, iterator repeat/zip/collect, and equivalent generic APIs.
  - Reject alias-producing instantiations with `String`, nested `Vec`, HashMap,
    owning pairs, library handles, and user `Drop` values while retaining safe
    APIs whose callback returns a fresh clone; sanitizer tests must cover both
    accepted cloning and rejected aliasing forms.

- [ ] **P0 — Resolve reproducible compiler-owned leak seams and correct the
  blanket leak claim.** Current open evidence includes direct slice returns,
  mismatched owning-struct reassignment, while `docs/MEMORY.md` says there are
  no known compiler-owned leaks. (The pre-defer path-dependent return leak
  is closed in 0.71.0.)
  - First turn each suspected current seam into a focused witness; do not reopen
    historical source comments whose guarded/binding form is already fixed.
    Then fix, reject, or narrow the guarantee for every reproducer. Include
    long-running service paths such as request logging in `nurlapi/main.nu`.
  - Keep the complete supported corpus leak-clean under LSan in default,
    `--strict-borrowck`, `--no-borrowck`, panic/recover, split-module, and
    optimized modes.
  - Reserve manual ownership only for an explicitly unsafe/raw surface; normal
    language constructs must not silently leak to preserve safety.

- [ ] **P0 — Make fiber handles lifetime-safe.** A detached `Fiber` can be
  reclaimed by a worker while `fiber_join` still dereferences the handle; the
  wasm-threads path can also free it again (`stdlib/std/async.nu`,
  `stdlib/runtime_ffi.c`). *(0.71.0, #1166: `fiber_join` now waits until the
  worker is through with a finished fiber; the detached-handle case is not
  re-verified.)*
  - Use distinct `DetachedFiber` and `JoinHandle` types, or a refcounted/registered
    control block whose state remains valid through join.
  - Make wrong-kind joins unrepresentable at compile time where possible;
    otherwise wrong-kind, repeated, and concurrent joins must return a typed
    error without dereferencing stale memory.
  - Add completion-before-join, completion-during-join, double-join, concurrent
    join, detach, cancellation, and shutdown tests for every runtime backend
    under ASan and a race-detection/stress gate.

- [ ] **P0 — Never silently discard spawned work.** Windows, non-threaded WASI,
  and OpenBSD currently expose async calls for which `spawn` can return null and
  `runtime_run` does nothing (`docs/ASYNC.md`, `stdlib/runtime_ffi.c`).
  - Unsupported async must fail at compile/link time, return a typed failure,
    panic clearly, or use a documented synchronous fallback.
  - Platform conformance tests must prove that submitted work either runs or
    fails observably; successful execution with missing work is forbidden.
  - Freeze and test the remaining async invariants from `docs/ASYNC.md`: whether
    async calls leave sockets nonblocking for later synchronous calls, the
    noinline/LTO-sensitive TLS-read boundary, and the rule that edge-triggered
    wrappers attempt I/O before waiting.

- [ ] **P0 — Check all allocation and capacity arithmetic before allocation.**
  Vec, HashMap, and Set growth contain unchecked addition, multiplication, and
  doubling; runtime entry points can cast negative signed lengths to `size_t`
  (`stdlib/core/vec.nu`, `stdlib/std/hashmap.nu`, `stdlib/std/set.nu`, and
  `stdlib/runtime_core.c`).
  - Centralize checked add/multiply/doubling and signed-to-size conversion.
  - Reject negative or unrepresentable sizes with a deterministic `TooLarge`
    error or defined panic before wraparound or allocation.
  - Test boundaries around `I64_MAX`, `SIZE_MAX`, element-size multiplication,
    growth thresholds, and wasm32 address-space limits.

- [ ] **P0 — Finish the concurrency safety contract.** Structural Send/Sync
  derivation cannot recognize opaque `s`-backed FFI handles, and the shared-Arc
  mutation check counts lock/unlock calls instead of proving the same lock is
  held on every path (`docs/MEMORY.md` section 6.5 and `docs/LIMITATIONS.md`).
  - Audit every stdlib/package wrapper for files, sockets, TLS, processes,
    watchers, regex state, database handles, and other opaque resources; require
    explicit reviewed Send/Sync or NotSend/NotSync markers.
  - Treat positive Send/Sync assertions as explicit unsafe declarations, and
    prevent unknown opaque wrappers from silently defaulting to thread-safe.
  - Make shared mutation checking path- and lock-identity-aware, including the
    parent thread, or narrow the guarantee and require an explicit unsafe path.
  - Add ThreadSanitizer where compatible and targeted high-contention/model
    tests where it is not.

- [x] **P1 — Freeze the raw-pointer boundary as an explicit unsafe contract.**
  *(0.71.0: `unsafe @` functions, spec §3.3d, and `nurlc --unsafe-report`.)*
  `*T` is intentionally the unchecked FFI escape hatch; that design need not be
  replaced with Rust lifetimes, but v1 must make the boundary impossible to
  mistake for safe code.
  - Specify which operations enter unsafe territory, how strict borrow checking
    interacts with them, and which obligations belong to callers and FFI
    authors.
  - Audit examples, generated docs, diagnostics, and marketing so none imply
    that arbitrary raw-pointer lifetimes are checked.
  - Add an explicit `unsafe` surface if documentation and naming alone cannot
    make the boundary reliable.

## 3. Compiler correctness, specification, and robustness

- [ ] **P0 — Finish the declared v1 compiler-hardening sweep.** The project
  ledger still leaves portions of A10, A13, A14, A16, and A17 open.
  - Complete the grammar-surface audit for trait declaration bodies
    (supertraits, associated types, defaults), `simd`/`inline`, compound
    `sizeof`, string/character escapes, and default/strict/raw-pointer/FFI
    boundaries.
  - Implement visibility for FFI and trait/impl declarations, or reject/remove
    the currently accepted but unenforced `pub` syntax before freezing it.
  - Finish opaque-wrapper, indirect-call, generic, embedded-origin, and
    borrowed-initial mutable-binding ownership review with retained witnesses.
  - Record compiler-architecture acceptance criteria for the global writer/state
    model and add interacting-feature differential tests; redesign is required
    only if the invariants cannot be made reviewable and testable.

- [ ] **P0 — Reject malformed source bytes and unterminated literals in the
  compiler itself.** The source reader retains bytes but the lexer relies on
  `strlen`, so embedded NUL truncates input; an unterminated backtick literal can
  reach EOF and still become a string token (`stdlib/runtime_core.c`,
  `compiler/nurlc.nu`).
  - Carry an explicit byte length through lexing, reject NUL with an anchored
    diagnostic, and diagnose an unclosed literal at its opening delimiter.
  - Require exponent digits after `e`/`E` and an optional sign, so malformed
    forms such as `1.0e` and `1.0e+` receive a source diagnostic instead of
    reaching LLVM as invalid IR.
  - Cover regular files, pipes, `--stdin`, imported files, non-UTF-8 bytes, and
    large inputs without reading past buffers or accepting a prefix silently.

- [ ] **P0 — Resolve target-size semantics before freezing `Z`.** The compiler
  and spec currently make `Z s`/`Z *T` equal 8 while wasm32 pointers are four
  bytes.
  - Decide whether `Z` means target storage size or a fixed language-level
    logical slot and make compiler, runtime, optimizer, spec, and examples agree.
  - Add wasm32 conformance for raw-pointer collections, memory copies, layout,
    FFI, and observable `Z` results; reject layouts that cannot be represented.

- [ ] **P1 — Make the normative grammar, specification, and implementation
  agree.** The v2.7 spec/import prose and snapshots have already drifted.
  - Correct importer-relative/cwd/`NURL_STDLIB`/realpath behavior in
    `docs/spec.md`; align hexadecimal/binary literal grammar with the compiler.
  - Add missing `spec/grammar_v2.3.ebnf` through `grammar_v2.7.ebnf`, or replace
    the claimed snapshot policy with a truthful versioned mechanism.
  - Freeze the v1 grammar identifier and add a spec-driven conformance suite
    independent of compiler goldens, mapping positive and negative tests to
    grammar and semantic clauses.

- [ ] **P1 — Complete and improve diagnostic coverage.** The gate currently
  permits 18 never-fired compiler diagnostics (`tools/diag_coverage_baseline.txt`),
  and anchor checking covers committed source goldens rather than every
  synthetic reparse buffer.
  - Exercise every reachable diagnostic; remove or individually justify
    unreachable sites instead of treating 84% as a stable target.
  - Extend anchoring to generic, trait, dynamic-signature, select, and other
    synthetic buffers, preserving original file/range and instantiation context.
  - Resolve the compiler-internal collision for parameter names such as `r0`, or
    normatively reserve and reject that identifier class with an anchored
    diagnostic. Improve fixed-arity recovery so a missing operand does not
    primarily blame the next line or declaration.
  - Define a stable machine-readable diagnostic form in addition to human text
    if editor/tool integrations are in the v1 contract.

- [ ] **P1 — Run a fresh, broader v1 fuzz and differential campaign.** The last
  retained clean report in `FUZZRESULTS.md` is for a 0.66-era compiler, before
  the 0.69 ownership rewrite.
  - Complete the remaining token-deletion seeds with `llvm-as` or
    `clang -c -x ir` as the IR-validity oracle, and add a runtime semantic oracle
    for mutants that still compile. Do not use `clang -fsyntax-only -x ir`, which
    does not validate the module.
  - Re-run differential-int, structural, inverse-ownership, parser, sanitizer,
    and wasm legs on the v1 candidate with a recorded stopping criterion and
    non-repeating seed ranges.
  - Add targeted coverage for regex, archives, compiler source parsing, CBOR
    boundary values, protocol state machines, and every security-sensitive
    parser that joins the supported surface.
  - Retain minimized reproducers and fail release on any untriaged crash, hang,
    sanitizer finding, invalid IR, miscompile, or must-reject acceptance.

- [ ] **P1 — Define compiler resource and determinism budgets.** Source/stdin,
  nesting, imports, generic instantiation, buffered IR, and compile time have no
  complete documented ceiling.
  - Add configurable limits and named diagnostics for source bytes, tokens,
    nesting, imports, monomorphs, generated functions/IR, diagnostics, wall
    time, memory, and output size.
  - Test deep nesting, cycles, generic explosion, huge literals, short reads,
    EINTR, OOM, disk full, locale/timezone/path differences, and concurrent
    builds. Within declared internal budgets, rejection must be deterministic;
    CI/services must additionally enforce external wall-time, RSS, and process
    limits for cases no structural budget can predict.
  - Establish regression budgets for compiler time and peak RSS on realistic and
    adversarial sources, with justified changes reviewed rather than silently
    rebasing the threshold.

- [ ] **P1 — Make bootstrap trust and supported LLVM versions reproducible.**
  Stage 1 equals stage 2, but the committed `nurlc_lastgood.ll` is refreshed by
  an existing local compiler and has no independent provenance gate.
  - Record source/IR/compiler/toolchain hashes and reproduce the seed using the
    previous official compiler or an independently built path before it is
    accepted. Call this provenance/reproducibility, not proof of trust; use
    diverse double compilation if the project claims resistance to a
    trusting-trust compiler attack.
  - Gate the documented minimum upstream LLVM 15 and a current supported LLVM,
    plus the bundled Zig backend; distinguish Apple Clang explicitly.
  - Require reproducible bytes for the same target/source/configuration under a
    pinned environment, and semantic/golden equivalence across supported hosts.
    Document target- and toolchain-specific byte differences and ABI effects.

## 4. Standard-library and protocol security

- [ ] **P0 — Fix CBOR unsigned-value and length overflow.** Eight-byte CBOR
  arguments are accumulated into signed `i`, so values above `I64_MAX` can wrap
  negative and be accepted as integers or collection/string lengths
  (`stdlib/ext/cbor.nu`).
  - Represent the value as `u64` or return a distinct overflow error before
    conversion, allocation, or iteration.
  - Add exact high-bit vectors for unsigned/negative integers and byte, text,
    array, and map lengths, including truncated forms and wasm32 behavior.

- [ ] **P0 — Complete independent cryptographic and X.509 assurance.** Current
  constant-time claims are by construction/review rather than measurement;
  RSA retains value-dependent bigint timing; name constraints and revocation
  are not enforced (`docs/CRYPTO.md`).
  - Vendor or content-address authoritative ACVP/KAT/negative vectors so the
    mandatory release gate runs offline and cannot `SKIP`; use a separate
    networked refresh/integrity job to update the corpus.
  - Run retained dudect/ctgrind-style timing measurements per supported
    primitive/backend/architecture, fuzz certificate/key parsers, and obtain an
    independent cryptographic review with findings tracked to closure.
  - Implement RFC 5280 name constraints for a general system-PKI claim. Define
    a realistic OCSP/CRL/stapling policy or explicitly document and mitigate the
    absence of revocation checking.
  - Provide real Windows and macOS trust-store integration, or ship and securely
    update a bundle; the current verifier only searches Unix bundle paths unless
    `SSL_CERT_FILE` is set.
  - Either harden/validate fixed-limb RSA private operations or mark that path
    experimental and prefer the reviewed EC path.

- [ ] **P1 — Apply consistent hostile-input limits to parsers and serializers.**
  TOML recursive arrays/tables, YAML block collections, regex groups/state
  closure, and JSON serialization do not share complete depth/node/output
  limits.
  - Bound input bytes, recursion, collection/node/state count, allocation, CPU,
    and serialized output; calibrate recursion below the 64 KiB fiber stack.
  - Return typed limit errors and add deliberately deep/wide inputs in addition
    to random mutations.
  - Add decoded-size/member/count limits to ZIP, and byte/time limits to the HTTP
    CLI client's complete-response buffering; cover truncation and decompression
    bombs in the same hostile-input suite.
  - Protect HashMap-backed parsers/services from attacker-chosen collision DoS
    with keyed per-map hashing; keep an explicit deterministic variant for
    reproducible tools and state that ordinary iteration order is unspecified.

- [ ] **P1 — Add backpressure and ownership-safe overload behavior.** `Channel`
  is unbounded, and MCP session notification/request/result/subscription state
  can grow without a byte/count/age limit.
  - Provide bounded channels, `try_send`, cancellation/close semantics, and an
    unambiguous failed-send ownership contract.
  - Cap MCP queued items and bytes, pending requests, subscriptions, and result
    retention; add TTLs and overload responses instead of process-wide memory
    growth.
  - Test blocked producers, slow/abandoned consumers, disconnects, failed sends,
    and exact one-time destruction of owned payloads.

- [ ] **P1 — Make secure network behavior the default.** The psql package
  defaults to `sslmode=prefer`, allowing plaintext downgrade and no certificate
  verification, and the default HTTP-server facade does not enable its DoS
  state/limits.
  - Default credential-bearing PostgreSQL connections to `verify-full`; require
    explicit, noisy selection of downgrade/insecure modes and test MITM and
    downgrade behavior.
  - Enable safe global/per-IP connection limits and request deadlines in normal
    HTTP constructors; define trusted-proxy identity and make handler deadlines
    cancel or isolate work rather than only checking after return.
  - Retain TLS interoperability and negative-policy tests against independent
    implementations for every supported protocol/version/cipher path.

## 5. Package manager, registry, and ecosystem

- [ ] **P0 — Make installs frozen, transactional, concurrent-safe, and
  symlink-safe.** `docs/TOOLING.md` explicitly leaves frozen installation and a
  whole-tree atomic transaction open; registry packages currently extract one
  by one into final `deps/<name>` locations.
  - `--locked`/`--frozen` must perform no resolution or lock mutation and must
    install the exact normalized origin, version, checksum, and signature from
    the lock; verification must hash installed content, not only manifests.
  - Validate the entire graph first, extract into an exclusive mode-0700 stage
    using no-follow/dirfd semantics, and publish graph plus lock under an install
    lock through one immutable-generation pointer/rename or a crash-recoverable
    journal, with complete rollback.
  - Apply the same transaction to installed tool binaries and assets so a new
    binary can never coexist with partial or old assets.
  - Freeze the current safe rejection of equal package names from different
    registries, or redesign the install layout to represent both; do not leave
    resolution and on-disk identity with different contracts. Preserve typed
    transport failures through every CLI path.
  - Add network/signature/corruption/copy/rename/disk-full/interruption,
    pre-existing-symlink, cross-device, and concurrent-install fault tests.

- [ ] **P0 — Bound and strictly validate package archives end to end.** Client
  package fetch uses unlimited gzip decompression and tar extraction lacks
  aggregate/member/count limits; registry read paths also decompress complete
  objects.
  - Enforce streaming limits for compressed and decoded bytes, expansion ratio,
    CPU, entry count, individual file, total extracted bytes, path length/depth,
    and duplicate normalized paths.
  - Validate tar magic/checksum/bounds and reject links, devices, traversal,
    truncation, overlapping entries, and malformed numeric fields before any
    allocation, signing, or write.
  - Share limits between publisher, registry, and client; add archive-bomb,
    malformed-header, race, and boundary tests.

- [ ] **P0 — Make registry publication serialized, atomic, validated, and
  obligatorily signed.** Ownership checks, object/signature/index writes, and D1
  updates are currently separate operations; the signing key is optional.
  - Production must refuse startup/publication without a valid signing key.
    Reserve owner/version under a uniqueness constraint, make object writes
    immutable/idempotent, and expose a version only after every object and index
    step is complete.
  - Derive the public key/key ID from the configured seed and require it to match
    the client trust root. Serialize every package's metadata updates, or use
    CAS/ETag retry, so concurrent different-version publishes cannot lose an
    index entry.
  - Parse the archive before signing: require exactly one root manifest matching
    authenticated name/version/dependencies; reject malformed dependency JSON,
    invalid ranges, duplicates, links/devices, and identity mismatches.
  - Use an authoritative pending/committed state that all readers honor. Extend
    atomicity and reconciliation to yank/unyank as well as publish, and test
    concurrent first publishers, different versions, duplicate versions, and
    failure after every D1/R2/signing boundary.

- [ ] **P0 — Separate registry signing from administration and design key
  lifecycle.** The signing seed is currently sent as the remote backfill admin
  credential (`X-Reg-Sign-Key`).
  - The private signing seed must never cross HTTP, proxy, or log boundaries;
    use separate least-privilege admin authentication and an isolated/KMS or
    offline signer.
  - Add key identifiers, overlapping trust roots, rotation, emergency
    revocation, rollback/freeze protection, and a documented recovery drill.
  - Redact secrets from all logs and prove rotation with old/new client
    compatibility tests.

- [ ] **P0 — Make registry access-token delegation and revocation safe.** A
  long-lived unscoped token can currently mint another token with broader
  effective lifetime/scope, and revocation requires possession of the token
  being revoked.
  - Require a nonempty least-privilege package scope for CI/delegated tokens;
    child scope and expiry must never exceed the parent, and parent/account
    revocation must invalidate the whole token family.
  - Provide an account-visible token inventory, stable token IDs, revoke-by-ID,
    revoke-all, rotation, and stolen-parent/child compromise tests.
  - Mark token-bearing responses `Cache-Control: no-store` and apply restrictive
    CSP, referrer, and frame policies to token/account pages.

- [ ] **P1 — Protect package credentials and publication contents.** The curl
  backend can place bearer headers in process arguments, follows redirects, and
  permits `http://`; credential files are plaintext-before-chmod, symlink
  following, unlocked, and non-atomic. Packaging can include sensitive dotfiles
  by default.
  - Keep secrets out of argv/environment; reject credentialed redirects or
    require same-origin HTTPS validation, and forbid non-loopback plaintext
    registry authentication.
  - Store credentials only under a trusted owner-only home using no-follow
    checks, exclusive 0600 temp files, fsync, locking, and atomic rename; fail
    closed if no trusted home exists.
  - Block `.env*`, private keys, credential stores, and high-confidence secret
    material by default, with an explicit override; always present the exact
    package inventory/digest for review.

- [ ] **P1 — Establish the complete first-party package and service matrix.**
  There are currently 58 package directories and 463 package `.nu` sources;
  ordinary CI directly exercises only a small subset, and seven package
  directories have no test-shaped file.
  - Check in a manifest of every package/service, supported platforms,
    prerequisites, test commands, public entry points, external/hardware needs,
    and legitimate skip reasons.
  - On PRs, run changed-package and reverse-dependency tests. Run the complete
    matrix on a schedule and before the v1 candidate; distinguish unsupported,
    skipped, and passed rather than treating missing prerequisites as success.
  - Test clean checkouts, packed archives, signed registry installs, public
    imports, and independent consumer projects on each supported host.
  - Define compatibility/support tiers for official packages; do not let `^0`
    ranges and a lockfile substitute for an API policy.

- [ ] **P1 — Prove registry operational readiness.** Public cutover needs more
  than unit tests and a successful deploy.
  - Define SLOs, monitoring/alerts, capacity/rate limits, abuse response,
    immutable-object retention, backups, restore objectives, and disaster
    recovery.
  - Make schema migration forward/backward compatible, back up before applying,
    and add post-deploy signed publish/install/yank/read canaries plus rollback.
  - Perform and retain a restore, key-rotation, partial-publication repair, and
    regional/provider-outage drill before v1.

## 6. Public playground, compiler API, and MCP service

- [ ] **P0 — Contain every public file-read API under its declared root.**
  Several unauthenticated HTTP and MCP readers reject `..` but then use
  `path_join`, whose absolute right-hand operand discards the trusted root. This
  can expose host files such as `/proc/self/environ` independently of compiler
  job sandboxing.
  - Cover `/examples`, `/static`, `/stdlib`, `/tests`, `/stdlib-docs`, every
    duplicate direct/router handler, and all `nurl_read_*` MCP tools/resources.
  - Reject absolute, drive-letter, UNC, NUL/control, mixed-separator, and
    ambiguous encoded forms; normalize once and prove canonical containment
    before opening. Use no-follow/descriptor-relative opens where a writable
    root or symlink race is possible.
  - Test `/etc`, `/proc/self/environ`, `//`, backslashes, percent encoding,
    symlinks, aliases, and both router and direct-dispatch paths without leaking
    content in errors.

- [ ] **P0 — Contain every untrusted compile job.** Caller filenames are joined
  into job paths without canonical containment, `opt` reaches Clang, imports can
  address parent/absolute host paths, and subprocesses inherit a shared working
  directory/cache/environment (`nurlapi/main.nu`).
  - Generate server-side names or accept strict basenames only; canonicalize and
    contain every input/output/import, reject symlink escapes, and make `opt` a
    fixed enum.
  - Give each job a private workspace/cache and an allowlisted environment;
    expose only its source and a read-only stdlib/toolchain.
  - Run compiler/linker/emulator processes with no network, no secrets, no new
    privileges, read-only root, seccomp/namespace isolation, and hard cgroup or
    equivalent CPU, wall-time, memory, PID, file, disk, and captured-output
    limits. Missing timeout/isolation support must fail closed, not fall back to
    an unbounded `process_run`.
  - Test absolute/`..`/symlink/import/cross-job/cache attacks, hostile options,
    fork/output bombs, cancellation, and orphan cleanup. Keep the existing
    non-root container as defense in depth, not the isolation boundary.

- [ ] **P0 — Implement real authorization or remove the OAuth claim.** The
  service advertises OAuth metadata, registration, authorization, and token
  endpoints that issue synthetic credentials, accept arbitrary redirects/grants,
  and are never enforced by `/mcp` (`nurlapi/main.nu`).
  - Either implement a standards-conformant authorization-code/PKCE flow with
    validated clients, redirect URIs, scopes, token verification, expiry, and
    revocation, or delete the endpoints and advertise an intentionally public,
    unauthenticated resource.
  - Add negative tests for open redirects, forged/replayed/expired tokens,
    scope bypass, CSRF/state failure, and unauthenticated protected calls.
    Token responses must be non-cacheable and authorization pages need
    restrictive CSP, referrer, and frame policies.

- [ ] **P0 — Make artifact links unguessable, private by contract, and truly
  expiring.** Build IDs are timestamps plus a small monotonic suffix; the edge
  mirrors artifacts to durable R2 without an application deletion path.
  - Use at least 128 bits from a CSPRNG. Treat the URL as an authenticated
    identity-bound resource or explicitly as an unguessable bearer capability.
  - Enforce documented TTL deletion in origin and R2, prevent cache/log leakage,
    and test enumeration resistance, authorization, expiry, deletion, and replay.

- [ ] **P0 — Bound edge buffering and trust only verified client identity.**
  The Worker buffers request bodies before the origin's limit, and the origin
  accepts forwarded IP headers without an explicit trusted-proxy boundary.
  - Apply route/method-specific streaming limits before `arrayBuffer()` and
    before retry/replay; cap response and diagnostic buffering as well.
  - Derive identity from the peer or a configured trusted proxy that overwrites
    forwarding headers. Use durable/distributed rate limits where horizontal
    scaling would otherwise reset per-process state.
  - Add chunked/oversize/slow-body, spoofed-header, retry amplification,
    many-IP, and overload tests with bounded memory evidence.

- [ ] **P0 — Remove or harden the hosted voice-relay WebSocket.** If
  `/pptws/<channel>` remains in the v1 hosted surface, it must not accept
  unauthenticated cross-origin peers into unbounded channels or perform socket
  writes while holding the global registry lock.
  - Enforce an allowed-Origin policy and authenticated or cryptographically
    unguessable channel membership. Bound channel-ID size, members, connection
    rate, bandwidth, queued bytes, and lifetime.
  - Use per-peer bounded queues/backpressure and never hold the global registry
    lock during network I/O; isolate slow/disconnected clients.
  - Test origin/auth bypass, channel enumeration, connection floods, slow peers,
    global-lock starvation, cleanup, and the relay's privacy/retention contract.
    Otherwise disable/remove the endpoint from hosted v1.

- [ ] **P1 — Publish the service privacy, abuse, and recovery contract.**
  - State source/artifact/log retention, data locations, access controls,
    acceptable use, deletion, and whether submitted code may contain secrets.
  - Add structured security metrics and audit logs without source, tokens, or
    credentials; alert on sandbox failures, resource abuse, and anomalous
    downloads.
  - Add readiness/liveness, build-SHA/version reporting, compile canaries, deploy
    by immutable image digest, and documented automatic/manual rollback.

## 7. Release engineering and software supply chain

- [ ] **P0 — Make official release authenticity mandatory and usable by
  default.** The release workflow silently skips minisign when its secret is
  absent; installers authenticate only when an external `minisign` happens to
  be installed and otherwise trust a co-hosted checksum.
  - An official v1 job must fail unless every required archive is signed and
    the signature is verified before publication.
  - Installers need a pinned, built-in, or bootstrapped verification path that
    authenticates by default; a bootstrapped verifier must itself chain to an
    embedded/pinned root. Any insecure bypass must be explicit and noisy.
  - Document/test release-key generation, protected custody, offline backup,
    rotation, revocation, compromise response, and verification without network
    access.

- [ ] **P0 — Pin and verify the complete build/release supply chain.** Windows
  workflows download and unpack Zig without a digest, while
  `tools/check_pinned_downloads.py` only recognizes curl/wget and currently
  reports success. Dockerfiles also download toolchains without checksums, and
  Actions use mutable major tags.
  - Verify the publisher SHA-256/signature before every extraction, including
    PowerShell downloads in `windows-tests.yml` and `release.yml`, and extend the
    policy checker plus tests to PowerShell, Dockerfiles, and all executable
    download forms.
  - Pin GitHub Actions by commit SHA, base/CI/production images by digest, package
    manager inputs by version/content, and all release-relevant oracles.
  - Add repository secret scanning and an advisory/update policy for downloaded
    binaries, C/system libraries, Python/Rust helpers, and other dependencies not
    covered by the existing JavaScript audit.
  - Isolate write permissions to the final publish job. Replace direct-to-main
    benchmark/fuzz pushes and broad bypass tokens with least-privilege bot PRs or
    immutable evidence artifacts.

- [ ] **P0 — Gate release and deployment on one verified identity.** Any `v*`
  tag can trigger release; the current gate checks only a successful `ci.yml`
  run for the SHA, not reachability from protected main or Windows/macOS/security
  workflows. Hosted deploys are independent.
  - Require exact `vMAJOR.MINOR.PATCH`, matching changelog/site/compiler/package
    versions, and a signed/annotated tag (or documented equivalent) whose SHA is
    reachable from protected main.
  - Aggregate mandatory Linux, Windows, macOS, dependency/security, package,
    fuzz/release-candidate, and artifact jobs for that exact SHA. Do not rely on
    unrelated historical success or branch-protection assumptions.
  - Publish artifacts first; deploy API/site/registry only from their immutable
    digest/version, then verify health, SHA, compile, install, and rollback
    canaries.

- [ ] **P0 — Make install, upgrade, downgrade, rollback, and uninstall safe on
  every distributed host.** PowerShell currently deletes the active install
  before extraction/copy, and neither the release installer nor `nurlpkg`
  provides a complete manifest-owned uninstall path.
  - Stage and fully validate a same-filesystem generation, atomically switch it,
    and restore the prior generation after checksum, signature, archive, copy,
    rename, disk-full, interruption, or locked-binary failure.
  - Preserve registry credentials, models, installed tools, and other user state;
    delete it only by an explicit separate choice.
  - Ship safe uninstall for the toolchain and installed tools/assets, reject
    broad/non-NURL prefixes, and clean PATH/environment integration without
    removing unrelated data.
  - Run native install -> upgrade -> downgrade -> interrupted upgrade -> rollback
    -> uninstall tests on every binary-distribution platform.

- [ ] **P1 — Make release artifacts complete, legal, relocatable, and
  reproducible.** Current assembly omits root license/NOTICE files; `nurlfmt` is
  best-effort despite being promised; LSP/nurldoc distribution is undecided.
  - Define the exact required archive manifest per target and fail when any
    promised tool, stdlib/docs file, license, third-party notice, runtime object,
    or backend is absent.
  - Emit dependency/license inventory, SBOM, signed provenance/attestation, and
    source correspondence. Normalize archive order, timestamps, ownership, and
    permissions; compare independent rebuilds or document exact exceptions.
  - Test every shipped executable from the unpacked archive under a relocated
    prefix, spaces/non-ASCII paths, read-only installation, offline operation,
    and least-supported OS/libc (including the advertised glibc 2.28 floor).

- [ ] **P1 — Align platform and distribution guarantees without conflating
  them.** FreeBSD and macOS ARM64 are legitimately Tier 1 source hosts under the
  current CI-based definition, while binary availability differs: FreeBSD is
  best-effort, macOS has no artifact, and Linux ARM64 releases without its full
  corpus.
  - Distinguish source-host support, binary distribution, and codegen-target
    support as three independent axes. Do not downgrade tested source-host
    support merely because no binary is distributed; state each binary promise
    separately and back it with installed lifecycle tests.
  - Decide v1 policy for macOS ARM64 packaging/signing/notarization, FreeBSD
    artifact availability, Linux ARM64 corpus coverage, Intel macOS, musl, wasm,
    and cross targets.
  - Ensure installers refuse unsupported OS/arch combinations with an accurate
    alternative rather than implying an untested path is supported.

## 8. Tooling, documentation, and usability

- [ ] **P1 — Make the editor path a supported installed experience.** The LSP is
  not bundled by the current release installer, has no per-request compiler
  timeout, and its lightweight declaration index still needs invalidation and
  duplicate/name-resolution coverage (`docs/TOOLING.md`).
  - Decide the shipped tools (`nurl-lsp`, extension, `nurldoc`, REPL), version
    their compatibility with `nurlc`, and include or clearly scope them out.
  - Add cancellable deadlines, debounce/coalescing, stale-result suppression,
    process-tree cleanup, import/watcher invalidation, multi-root behavior, and
    bounded large-workspace tests.
  - Test the actual installed artifact on native Windows, macOS, and Linux,
    including spaces/Unicode paths, extension install/upgrade/uninstall, and a
    reproducible current VSIX/marketplace channel. Remove stale `0.4.4` setup
    instructions from the current `0.5.1` extension documentation.

- [ ] **P1 — Freeze usable command-line and formatting behavior.**
  - Document stable command names, help, exit-status classes, stdout/stderr
    contracts, color/TTY behavior, offline/proxy/custom-CA behavior, and
    machine-readable output for compiler/package automation.
  - Make `nurlfmt` mandatory if advertised; it must either format a valid file
    atomically or leave malformed/failed input unchanged, across the complete v1
    grammar and line-ending/Unicode cases.
  - Provide a `doctor`-style environment check and current shell completions or
    an explicit decision not to ship them; every error should name the failing
    path/tool/registry and a concrete recovery action without leaking secrets.

- [ ] **P1 — Reconcile and continuously validate all user-facing documentation.**
  Current concrete drift includes `ROADMAP.md` reporting 0.68.0 instead of
  0.69.1, web docs using obsolete platform tiers/build prerequisites, stale
  import resolution in `docs/spec.md`, and links to a gitignored missing
  `TODO.md` from crypto/fuzz documentation.
  - Correct those claims and generate release/platform/tool facts from one
    source rather than maintaining contradictory tables by hand.
  - Replace the site's cross-platform “byte-identical output” statement with the
    exact fixed-point/determinism guarantee, and reconcile “clang is the only
    dependency” with the canonical build prerequisites.
  - Retire the disproved lower-token-use claim everywhere and separate the
    language thesis from “an agent can drive the tools through MCP.”
  - Check internal/external links, anchors, code fences, CLI-help snapshots,
    version references, security claims, and all examples in CI.
  - Publish a v1 migration guide from 0.x and an indexed limitation/unsafe/FFI
    guide that says what the compiler proves and what the programmer must prove.

- [ ] **P1 — Publish a versioned public API reference.** The repository contains
  233 stdlib modules, while `docs/stdlib/` has only a README and two focused
  guides.
  - Generate browsable documentation for every supported public module/symbol,
    including ownership, errors, complexity/resource limits, thread safety,
    platform availability, examples, stability, and unsafe requirements.
  - Enforce public-doc coverage, symbol/link validity, example compilation, and
    correspondence to the exact released source; bundle or host the reference
    according to the v1 support contract.

- [ ] **P1 — Complete accessibility and browser supply-chain review.** Playground
  controls/status/canvas/focus behavior are not fully accessible, and Monaco,
  the WASI shim, and Swagger assets load from external CDNs without a complete
  integrity/CSP story.
  - Pass keyboard, visible-focus, screen-reader/live-region, contrast,
    reduced-motion, zoom/mobile, and canvas-alternative review; add an automated
    accessibility gate for durable regressions.
  - Self-host or content-pin browser dependencies, apply SRI where applicable,
    and enforce restrictive CSP and security headers without breaking the editor
    or WASM runner.
  - Run the web project's configured lint in CI in addition to typecheck/build.

- [ ] **P2 — Finish truthful v1 presentation and brand work.** Complete the
  roadmap's human-designed imagery requirement, make language and MCP claims
  distinct, and review the whole site/README/package metadata for precise,
  evidenced claims rather than pre-release superlatives.

## 9. Final v1.0 go/no-go evidence

- [ ] **P0 — Complete independent review of the supported v1 attack surface.**
  At minimum this includes the compiler's safe-default contract, runtime
  concurrency/allocation paths, cryptography/X.509, package trust chain, and
  release pipeline; include registry and public-compile services only if the
  frozen support manifest puts them in v1 scope. No critical/high finding may be
  open; lower-severity accepted risk needs an owner, rationale, user-visible
  scope, and target release.

- [ ] **P0 — Produce a clean release-candidate evidence bundle for one immutable
  SHA.** It must contain all mandatory platform results, fixed-point/reproducible
  build evidence, full corpus and package matrix, sanitizer/race/fuzz reports,
  diagnostic/conformance results, dependency/license/SBOM/provenance reports,
  signed artifacts, and installed lifecycle tests. Hosted registry/service
  evidence is required only for hosted surfaces in the support manifest. `SKIP`
  must be justified by that manifest, never silently counted as a pass.

- [ ] **P0 — Rehearse release and recovery before tagging v1.0.0.** Perform a
  release dry run from protected main, signature and offline verification,
  install/upgrade/downgrade/uninstall on supported hosts, key-compromise
  response, rollback, and incident communications. If hosted registry/services
  are in v1 scope, also rehearse publish/install, deploy/canary, and backup
  restore. Capture owners, commands, timings, and outcomes in the release
  runbook; then make the changelog, migration guide, support matrix, and known
  limitations match the candidate exactly.

## 10. Verified foundations to preserve

These controls are already represented in the repository. They do not close the
open work above, and all of them must pass again for the release-candidate SHA.

- [x] The compiler performs a deterministic stage-1/stage-2 fixed-point check,
  and the main corpus has Linux/FreeBSD, native Windows, and Apple Silicon macOS
  CI paths.
- [x] Default borrow checking, compiler-inserted auto-drop, drop flags, panic
  allocation journaling, and focused move/escape/container checks are implemented
  and documented as a guarantee for programs without `unsafe` (MEMORY.md §6).
- [x] Whole-corpus ASan/UBSan/LSan gates, compiler cleanup controls, peak-RSS,
  DCE, symbol-collision, arithmetic-domain, and source-I/O checks exist.
- [x] Differential, structural, inverse-ownership, parser-mutational,
  metamorphic, trait-order, token-deletion, and minimization infrastructure
  exists and has found real compiler defects.
- [x] Compiler diagnostic identity and source-anchor gates exist; new silent
  diagnostics and obviously delimiter-anchored goldens are prevented from
  entering unnoticed.
- [x] Registry package fetch binds normalized origin, checksum, mandatory
  minisign signature, manifest identity, and toolchain compatibility before
  accepting an archive; tar parsing already rejects absolute/parent paths,
  links/devices, and bad checksums.
- [x] POSIX release installation stages extraction and checks that `bin/nurl`
  exists and is executable before beginning replacement, and preserves known
  user state; release artifact presence/checksum controls have a dedicated
  regression suite. Full manifest validation and an atomic multi-path swap
  remain open above.
- [x] The public API container runs as an unprivileged UID, native execution is
  off by default, and origin-side body, rate, concurrency, timeout, and output
  retention controls provide an initial defense layer.
- [x] LSP diagnostics use compiler stdin instead of shared source temp files,
  preserve logical source locations, and have a substantial relocated-project,
  UTF-16, import, and concurrency control suite on Linux.
- [x] Recurring JavaScript dependency audits cover registry, Cloudflare,
  extension, and web projects; HTTP/2 and HTTP/3 conformance/interoperability
  gates and several independent protocol oracles already exist.
- [x] Project licensing is explicitly MIT OR Apache-2.0, contribution terms are
  documented, and the repository includes a third-party notice inventory to use
  as the basis of release artifacts.
