# IMPROVEMENTS — v0.9.0 critic follow-ups

Actionable items distilled from `critic.md` (24 May 2026 external peer review).
Items ordered by impact-vs-cost, not by section in critic.md. Each item names
the critic anchor in parentheses so a reader can jump back to the source.

Convention: `[ ]` open, `[~]` partial, `[x]` shipped (kept here briefly for
context, then graduates to ROADMAP / CHANGELOG and is removed).

---

## Tier A — Concrete diagnostic gaps (close the "GOTCHAS by policy" promise)

**ALL FOUR CLOSED 2026-05-25** (see CHANGELOG `[Unreleased]` for ship notes).
Bootstrap fixed point holds; full test corpus green. Items kept here briefly
so the original PoC and rationale stay readable.

- [x] **`^ a b` silent miscompile when `^^ a b` (XOR) was intended.**
  PoC (critic §1):
  ```
  @ main → i {
    : i a 5
    : i b 3
    : i x ^ a b    // intended XOR; actually "return a"
    ^ 0
  }
  ```
  Emit a `note:` along the lines of *"`^` is the return operator; for XOR use
  `^^` (no space between the carets)"* when an `^`-returned expression is a
  binary expression on the function's declared return type AND there are
  unreachable statements after it. Heuristic — false positives are tolerable
  here because the cure text is the right answer in every case.
  *Recommendation #1.*

- [x] **Use-after-explicit-free compiles silently.**
  PoC (critic §2):
  ```
  @ take String s → v { ( string_free s ) }
  @ main → i {
    : String s ( string_from `hello` )
    ( take s )
    ( nurl_print ( string_data s ) )   // use after free
    ^ 0
  }
  ```
  Borrow checker already has a destructor-name list (`bck_is_destructor_name`,
  added during Phase 1). Extend the dataflow so a call to any
  `<type>_free` / `*_close` / `*_destroy` family helper marks the receiver
  binding as moved, so subsequent loads through the same binding fire the
  existing use-after-move diagnostic. Start at `warning:`, promote to `error:`
  after one release of soak (same pattern as BORROW Phase 8 final).
  *Recommendation #2.*

- [x] **Bare-identifier-as-statement compiles to dead expression.**
  PoC (critic §1):
  ```
  @ main → i {
    nurl_print `oops, forgot parens\n`   // name lookup, not a call
    ^ 0
  }
  ```
  When an expression statement's value is discarded AND the leading identifier
  resolves to a known `@`-function name, emit
  *"statement has no effect; did you mean `( nurl_print … )`?"* Critic calls
  this whole class — *grammar-legal but semantically dead* — the natural next
  frontier for the diagnostic suite.

- [x] **`<generic>:1` synthetic source line in generic-instantiation errors.**
  PoC (critic §2): `( vec_as_slice [i] v )` against a multi-field generic
  struct dies with `<generic>:1:21: unexpected token`. Tracked on ROADMAP §6
  as DWARF Phase 7 follow-up; raise priority — this is by far the largest
  contributor to confusing errors the critic encountered.
  *Recommendation #3.*

## Tier B — Borrow-checker depth (Recommendation #5)

**BOTH ITEMS CLOSED 2026-05-25 — by prior decision, not by code change.**
Tier A #2 already addressed the critic's substantive use-after-free PoC; the
remaining Tier B asks turn out to be already-decided non-work once you read
them against the BORROW.md / docs/MEMORY.md semantics. The critic's
`--strict-borrowck` recommendation is satisfied by BORROW Phase 8 final
(warnings → errors on by default).

- [x] **Aliased-mutation: catch nested-subexpression reads.** *Decided against.*
  Phase 5-partial (commit `127f73f`) flags `( f inout c c )` at the call site.
  The "remainder" framed as a gap in `BORROW.md` Phase 5 and
  `docs/MEMORY.md` §3 — `( f inout c (g c) )` and `. c n` — is **not a
  hazard under Option B**, the language's chosen borrow model. An `inout`
  borrow lives exactly for the duration of its call (Option B; documented
  in `docs/MEMORY.md` §2.4 line 207). Argument evaluation is sequential
  left-to-right, so a nested `(g c)` reads `c` *before* the outer `inout`
  borrow goes live; there is no overlap, no data race, no UB. Flagging it
  would be a false positive against the language's own semantics. (The
  `docs/MEMORY.md` "known gap, not yet" wording predates the Option B
  decision and should be tightened in a future doc pass to "deliberately
  not checked — call-scoped borrows make nested reads safe".)

- [x] **`inout` / `sink` on impl methods.** *Deferred pending real consumer.*
  Per `project-critic-cleanup` memory: impl dispatch resolves *after* args
  are built in `gen_call`, so the per-arg `inout` handler can't see
  `callee_inout` yet. A clean fix needs a receiver-type peek before the
  arg loop; keying conventions by bare method name would collide with
  same-named plain functions and risks miscompile. Today: trait/impl has
  1 stdlib user (`serde.nu`) and 0 `inout` / `sink` users. Land it
  properly the first time real consumer code in `ext/` wants it.

## Tier C — Release / docs hygiene (Recommendations #4, #6, #7)

Cheap, but each closes a small public-claim gap the critic flagged by name.
**All five closed 2026-05-25.**

- [x] **Restore fixed-point IR byte count in tagged-release notes.**
  The CHANGELOG `[Unreleased]` block now quotes the current fixed point
  (`stage1 ≡ stage2 byte-identical IR at 1 620 300 B` as of the Tier A ship).
  Going forward, every release-note entry that touches the compiler should
  carry the same line. *Recommendation #4.*

- [x] **Publish & verify the `~390 kB nurlc.wasm` claim.**
  Verified 2026-05-25 against the current `compiler/nurlc.nu` via
  `./startdev.sh && ./buildwasm.sh`: **315 708 bytes** — slightly *smaller*
  than the README's headline ~390 kB. README updated to quote the verified
  number and the build date. The recipe was already documented inline
  (`./buildwasm.sh` over a running `./startdev.sh` API container); no new
  branch artefact needed since the build is reproducible from the repo in
  under a minute. *Recommendation #6.*

- [x] **README VSIX install path.**
  Audited 2026-05-25: README:117 already points at the current
  `tooling/vscode-nurl/nurl-0.4.4.vsix`. The critic's snapshot was stale —
  the README had been updated since. No action needed. *Recommendation #7a.*

- [x] **v0.6.1 release-notes body internal date.**
  Was `2025-10-19`; corrected to `2026-05-17` (the actual git-tag date for
  `v0.6.1`, verified via `git log v0.6.1`). *Recommendation #7b.*

- [x] **Formal `docs/spec.md` shipped 2026-05-25.** ~1000-line normative
  reference covering the semantic side the grammar EBNF doesn't: lexical
  structure, modules / visibility, types (base + composite + generics),
  statements, expressions (prefix arities, evaluation order, `^` vs `^^`),
  functions (parameter conventions, return ownership, tail calls, generics),
  memory model, borrow-checker rules, diagnostics philosophy, conformance.
  Pulls together rules from `spec/grammar.ebnf` (referenced, not duplicated),
  `docs/MEMORY.md`, `BORROW.md`, and README "Known Limitations" into a single
  document a programmer can read end-to-end. ROADMAP §6 entry promoted from
  partial to done.

## Tier D — Ecosystem gaps the critic enumerated as missing-for-v1.0

These are roadmap items the critic listed in §8 *"What is missing for v1.0,
by the roadmap's own admission."* Reproduced here for visibility so the
critic-driven backlog is in one place; the canonical home is ROADMAP.md.

- [ ] **UDP + full DNS resolution (`getaddrinfo`).** ROADMAP §3.
- [ ] **Generic signal handling.** Beyond `nurl_signal_install_shutdown` —
      arbitrary signal numbers, NURL closure handlers, async-signal-safety
      caveats documented. ROADMAP §3.
- [x] **Structured logging — shipped 2026-05-25.** `stdlib/std/log.nu` now
      has `log_<level>_kv1` / `_kv2` / `_kv3` (12 fixed-arity kv helpers)
      and a `log_set_json` / `log_get_json` toggle. JSON output is RFC 8259
      compliant and applies uniformly to every `log_*` call. Test:
      `log_structured.nu` (jq round-trips every JSON line). ROADMAP §2.
- [ ] **Mobile / embedded targets.** Android, iOS, `no_std` embedded
      profiles. ROADMAP §6. (Milk-V Duo already validated as a NURL target
      via cross-compile; that's the prior-art shape.)
- [x] **GitHub Actions CI — shipped 2026-05-25.**
      `.github/workflows/ci.yml` with two parallel jobs on
      `ubuntu-latest`: `build-test` (`./build.sh`) + `sanitizers`
      (`./build.sh --san --no-tests` then `run_san_tests.sh`). Triggers
      on push to `main` / `Improvements` + PR-to-`main` +
      `workflow_dispatch`. Optional FFI dev libs (libcurl / libssl /
      libsqlite3 / libpq / zlib / libzstd) installed in each job so
      sentinel checks light up. `nurlfmt --check` deferred — corpus
      has ~100 non-canonical files (incl. `compiler/nurlc.nu`); wire
      it after a separate repo-wide `nurlfmt --write` pass. ROADMAP §6.
- [x] **More `examples/` — shipped 2026-05-25.** Two-part:
      (1) `examples/find_clone.nu` — grep-style recursive search with
      literal / `--list` / `--regex` modes + stdin + dotfile skip;
      covers the `wc`+`grep`+`cat` clones the critic listed alongside
      the pre-existing `wordcount.nu`. (2) `examples/README.md`
      refreshed from a 3-of-36 catalogue to all 36 rows tagged
      **playground** (runs on play.nurl-lang.org) vs **local**
      (network / SDL / API key required). Agent-loop variants and
      MCP-client demo deliberately not added — `claude_agent.nu`
      already covers the agent shape; an MCP-client-from-the-public-
      playground would need either secret injection or WASM outbound
      sockets, neither of which the playground exposes. ROADMAP §6.
- [x] **HTTP-server peer benchmark — shipped 2026-05-25** (Rust hyper +
      Node http halves). `bench/http_server.{nu,js}` +
      `bench/rust_http_server/` hello-world peers; `bench/run_http.sh`
      drives them via `oha`. Median-of-3 × 10 s per cell at C=1, 10,
      50, 200. Headline: NURL parity with Rust hyper at low concurrency
      (14.5 k/s at C=1); NURL **ahead** of Rust at C=10 (69k vs 48k,
      1.45× — NURL's 8-worker pool happens to fit the workload); Rust
      pulls ahead at higher C (87k at C=50, 115k at C=200, ~1.9×).
      NURL holds the **lowest p99 latency across the whole sweep**
      (0.62 ms at C=200 vs Rust's 6.19 ms). Go peer deferred — not
      installed on the bench host; runner has the lane, README
      documents the gap. See `bench/HTTP_RESULTS.md`.

## Tier E — Already addressed; verify external framing matches

The critic's snapshot is dated 24 May 2026; some items have moved since.
No code work here — just make sure the README / spec / response materials
reflect the current state, so the next external reviewer doesn't repeat
the same finding.

- [x] **Borrow-checker promoted to hard errors** (BORROW Phase 8 final,
      2026-05-25). Critic Recommendation #5's `--strict-borrowck` ask is
      satisfied by the default behaviour; `--no-borrowck` is the escape
      hatch. Mention this explicitly in any critic-response material.
- [x] **Async runtime shipped** (project_async_runtime memory: 9 phases,
      stackful M:N work-stealing, 1500 LOC). Critic §6 describes async as
      *"Phases 1-8 with `noinline` workarounds."* Update README so the
      async story is no longer worded as in-progress.
- [x] **Top-level `CHANGELOG.md`** already exists at repo root. Critic
      Recommendation #7 asked for "a top-level CHANGELOG.md … to make the
      release history searchable" — already done; verify the file is linked
      from README.

---

## Notes on ordering

Tier A is the highest-priority block because it directly attacks the
critic's central technical complaint — that the project's headline promise
(*"every historical pitfall is a compiler diagnostic"*) has three counter-
examples that compile silently. Each of the four Tier A items is a local
compiler change, none touches the IR shape, all are exercisable with a
single regression test of the same shape the critic's PoCs used.

Tier B and C are cheap and the critic listed them by name; pick them off
opportunistically between larger ships.

Tier D is the v1.0 roadmap restated through the critic's eyes. The
canonical home stays in ROADMAP.md — this file just keeps the critic-driven
items co-located for the v0.9.0 → v1.0 push.
