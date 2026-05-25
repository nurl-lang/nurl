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

The critic's PoC bypassed the borrow checker by going through an explicit
`_free` (covered above) and by reading through field/closure indirection.
The remaining `--strict-borrowck` ask was already delivered by BORROW Phase 8
final (warnings → errors on by default).

- [ ] **Aliased-mutation: catch nested-subexpression reads.**
  Phase 5-partial (commit `127f73f`) flags `( f inout c c )` at the call site.
  The known gap is nested-subexpression reads: `( f inout c (g c) )` and
  `. c n` of an `inout`'d struct. Extend the per-call-site walk to recurse
  into argument subexpressions and flag a bare-identifier read of any binding
  also passed as `inout` to the same call. Watch for false positives where
  arg evaluation order makes the read complete *before* the borrow goes live
  — the critic's "N readers XOR 1 writer" expectation only holds for
  overlapping borrows, so the diagnostic must match that semantics, not flag
  every co-occurrence.

- [ ] **`inout` / `sink` on impl methods.**
  Currently deferred (project_critic_cleanup memory): impl dispatch resolves
  after args are built in `gen_call`, so the per-arg inout handler can't see
  `callee_inout` yet. Needs a receiver-type peek before the arg loop.
  Niche today (trait/impl has 1 stdlib user `serde.nu`, 0 inout users); land
  it the first time real consumer code in `ext/` wants it.

## Tier C — Release / docs hygiene (Recommendations #4, #6, #7)

Cheap, but each closes a small public-claim gap the critic flagged by name.

- [ ] **Restore fixed-point IR byte count in tagged-release notes.**
  Convention was abandoned somewhere around v0.7.x; the v0.9.0 release notes
  only restate that *"the fixed point held on every shipped phase."* For each
  tagged release, quote the exact stage1 ≡ stage2 byte count — the value is
  already in `ROADMAP.md`'s "Last updated" line per ship, just plumb it into
  the release-notes template. *Recommendation #4.*

- [ ] **Publish & verify the `~390 kB nurlc.wasm` claim.**
  README asserts *"the same `POST /build_wasm` pipeline … produces a ~390 KB
  `nurlc.wasm` that **is** the NURL compiler."* Critic's MCP build exceeded
  its transport limit so the number is unverified externally. Action: add a
  reproducible recipe (`./build.sh --wasm-self` or equivalent) AND check the
  artefact into a `release-artifacts/` branch so the size is independently
  observable. Restate the same byte count in README. *Recommendation #6.*

- [ ] **README VSIX install path is out of date.**
  README references `nurl-0.1.0.vsix`; v0.7.3 release notes shipped
  `nurl-0.4.4.vsix`. Update the README install snippet and pin it to the
  release-notes value going forward. *Recommendation #7a.*

- [ ] **v0.6.1 release-notes body has internal date `2025-10-19`.**
  Mismatches the 17 May 2026 publication. Fix the typo. *Recommendation #7b.*

- [ ] **Formal `docs/spec.md`.**
  ROADMAP §6 still pending. The EBNF in `spec/grammar.ebnf` is the
  authoritative grammar; what's missing is the semantic side — operator
  arities, the type system, the ownership / borrow rules, the prefix-arity
  cascade rule, `^` vs `^^`. Pull from existing `docs/MEMORY.md`, `BORROW.md`,
  README "Known Limitations". Threshold: pre-v1.0.

## Tier D — Ecosystem gaps the critic enumerated as missing-for-v1.0

These are roadmap items the critic listed in §8 *"What is missing for v1.0,
by the roadmap's own admission."* Reproduced here for visibility so the
critic-driven backlog is in one place; the canonical home is ROADMAP.md.

- [ ] **UDP + full DNS resolution (`getaddrinfo`).** ROADMAP §3.
- [ ] **Generic signal handling.** Beyond `nurl_signal_install_shutdown` —
      arbitrary signal numbers, NURL closure handlers, async-signal-safety
      caveats documented. ROADMAP §3.
- [ ] **Structured logging.** `log_info_kv` for key-value pairs, JSON output
      mode for log lines. ROADMAP §2.
- [ ] **Mobile / embedded targets.** Android, iOS, `no_std` embedded
      profiles. ROADMAP §6. (Milk-V Duo already validated as a NURL target
      via cross-compile; that's the prior-art shape.)
- [ ] **GitHub Actions CI.** Sanitiser gate runs locally; wire to GHA so PRs
      are gated automatically. ROADMAP §6.
- [ ] **More `examples/`.** Small JSON pretty-printer, `wc` / `grep` / `cat`
      clones, MCP client demo, agent loop variants. ROADMAP §6.
- [ ] **HTTP-server peer benchmark vs Go `net/http` / Rust `hyper`.**
      `bench/RESULTS.md` covers compute + JSON parse against Python / Rust /
      Node, but the critic §10 specifically asked for the HTTP-server
      comparison the README's *"~38× keep-alive"* claim is currently
      NURL-vs-NURL only.

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
