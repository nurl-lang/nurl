# Borrow Checking — Preliminary Investigation & Phased Implementation Plan

> **Status (2026-05-20): investigation only — nothing implemented.**
> This document is the feasibility study + work-list for adding static
> aliasing / borrow analysis to NURL. No phase has landed. Phase 0 is
> the prerequisite refactor; Phases 1–3 are the high-value core that
> needs no new surface syntax; Phase 4 carries the one irreversible
> design decision (reference types vs. mutable value semantics) and
> should not start until that decision is explicitly made.
>
> The whole feature is designed as a **diagnostic-only analysis pass**:
> it emits `error:` / `warning:` and never changes emitted IR. A
> borrow-clean program compiles to byte-identical IR before and after,
> so the bootstrap fixed point is unaffected at every phase.

This is sized to be picked up across multiple sessions. Each phase is
independently testable, leaves the tree green, and documents what the
previous phase set up — same shape as `DWARF.md`.

---

## Part I — The Investigation: does NURL need this?

### I.1  What NURL enforces today

NURL's memory model is **single-owner + conservative compiler-inserted
auto-drop, no aliasing analysis**. Concretely, from `compiler/nurlc.nu`:

- **Default-immutable bindings.** `: i x 0` is immutable; `: ~ i x 0`
  opts into mutation. Assignment to an immutable binding is a compile
  error today. This is the *one* genuine static safety check NURL
  already has, and it is the seed a borrow checker grows from.
- **Conservative ownership tracking.** Four list-valued symbol-table
  keys accumulate owned resources per scope frame:
  `__owned_slices__` (Phase 1/2A), `__owned_strings__` (Phase 2B),
  `__owned_struct_fields__` (Phase 2C), `__user_drops__` (the `Drop`
  trait). At scope exit `mem_drop_*` emits `nurl_free` / `drop` for
  each. Reassignment frees the previous value; returning a fresh
  allocation transfers ownership and suppresses the drop.
- **Conservative by construction.** Only a value populated by a
  *fresh* allocation on the spot gets a drop registered. Copying an
  already-owned binding into a struct does **not** register a second
  drop. This is why the compiler never emits a double-free *of its
  own accord* — but it is also the whole extent of the safety story.
- **Shallow escape detection.** `gen_ret` + `gen_call` carry a
  `__last_closure_byref__` / `<name>__captures_byref` flag. A closure
  that captures a `: ~`-mutable multi-field struct *by pointer* and
  then escapes via one of five hard-coded shapes (`^`-return,
  `vec_push`, `vec_insert`, `vec_set`, `thread_spawn`) emits a
  `warning:`. It is a name+flag check, not a dataflow analysis.

### I.2  What NURL does NOT enforce — the open bug classes

Everything below compiles silently today. These are the bug classes a
borrow checker closes, ranked by how often real NURL code hits them:

1. **Use-after-move.** A binding whose ownership was transferred
   (returned, or passed to a consuming callee) is still in scope and
   can be read again. The second use sees freed or
   about-to-be-freed memory. No check exists.

2. **Manual double-free via aliasing.** `: ( Vec i ) a ( vec_new )`
   then `: ( Vec i ) b a` — `b` now aliases `a`'s heap buffer. If both
   are owned at scope exit (or one is `vec_free`'d explicitly and the
   other auto-dropped) the buffer is freed twice. The compiler's
   conservatism avoids *emitting* this itself, but cannot *detect* a
   user who writes it.

3. **Dangling closure capture beyond the 5 known shapes.** The
   `__captures_byref` check is a name match. Store the closure inside
   a struct first (`@ Slot { cb }`) then escape the struct, or pass
   it through a helper, and the warning never fires. The README and
   `docs/GOTCHAS.md` history both admit this is "vibes-based".

4. **Dangling `*T` raw pointer.** `*T` parameters and the address of
   an `alloca` can be stored, returned, or captured with zero checks.
   `*T` is FFI-shaped and entirely unchecked.

5. **Iterator invalidation.** `~ x : T xs { ( vec_push xs y ) }` —
   mutating a container while a foreach borrows its elements. The
   `vec_push` may `realloc` the backing buffer out from under the
   loop cursor. No check exists.

6. **Aliased mutation.** Two mutable paths to the same data; a write
   through one breaks an invariant the other relies on. NURL has no
   notion of exclusive access at all.

### I.3  Is this worth doing? — honest scoping

`critic.md` §4 is blunt: NURL's model is "approximately C-with-RAII",
the marketing phrase "no borrow checker" is "a resource-cleanup story,
not a memory-safety story". That is a fair hit. But it does **not**
follow that NURL should clone Rust.

The case **for**:
- NURL positions itself as a systems language an LLM can write
  *reliably*. Silent use-after-free is exactly the failure mode that
  erodes that claim — and an LLM cannot "feel" a lifetime bug the way
  the current "rule of thumb" model assumes a human reviewer will.
- Bug classes 1, 2, 3 above are reachable in *ordinary* NURL code, not
  exotic code. They deserve to be `error:`s.

The case **against full Rust**:
- Rust's borrow checker is the single hardest part of Rust to learn
  and the single hardest part of Rust to *generate* — lifetime
  annotations, variance, reborrow, NLL. Importing all of it would
  fight NURL's "easy to generate" thesis.
- NURL has deterministic single-owner drop already. It does not need
  borrowck to know *when* to free — only to reject *unsafe aliasing*.

**Recommended ambition: a "sound subset" borrow checker.** Target
exactly bug classes 1–5. Make moves, escapes, and iterator
invalidation hard `error:`s. Treat full aliased-mutation (class 6)
checking as the deep end (Phase 5) and gate it behind the reference-
type decision. Do **not** ship lifetime-annotation syntax unless
Phase 7 proves a real need. The result is closer to
Hylo/Val + Cyclone-regions than to Rust — which is the right
neighbourhood for this language.

### I.4  The non-negotiable constraint: bootstrap safety

The borrow checker analyses; it does not lower. Every phase emits
diagnostics and nothing else. A program with zero borrow errors
produces **byte-identical IR** to a build with the checker disabled.
This means:
- The bootstrap fixed point (stage1 ≡ stage2 IR) is preserved for
  free at every phase, *provided the NURL stdlib + compiler sources
  themselves are borrow-clean*. Making them clean is itself a phase
  deliverable (see Phase 1 / 2 acceptance criteria).
- The checker can be developed behind a `--borrowck` flag (off by
  default) until it is trusted, then flipped on.
- The test harness already has a `should_warn_*` category that
  captures compile stderr into the baseline. Borrow diagnostics slot
  straight into it; add a `should_fail_borrow_*` sibling for the hard
  errors.

---

## Part II — Why this is bigger than it looks

The current `mem_*` ownership tracking is a set of **space-separated
string lists in the symbol table**, pushed/popped per block scope. It
answers exactly one question — "what must I free at this scope exit?"
— and it answers it conservatively.

A borrow checker needs to answer a different and harder question:
**"at this program point, what is the ownership/borrow state of every
live binding, on every path that reaches here?"** That is a
control-flow-sensitive dataflow analysis. The current per-scope list
cannot express:

- *path-sensitivity* — a binding moved in one `?`-arm but not the
  other is conditionally-moved at the join;
- *per-binding state* beyond "owned / not owned" — we need
  `Owned | Moved | Borrowed(shared) | Borrowed(mut) | Invalid`;
- *the provenance graph* — which binding does this reference point
  into, and is that binding still alive?

So the first real prerequisite is an analysis substrate: a per-function
control-flow graph and an ownership-state lattice threaded through it.
That is Phase 0, and like DWARF's Phase 0 it is a refactor, not a
feature. **Phase 0 must land first.**

A second structural issue: NURL's compiler is **single-pass** — it
emits IR as it parses. A borrow checker is most naturally a *separate
pass over a fully-built representation*. Phase 0 therefore also has to
decide how the analysis observes the program: either (a) build a
lightweight per-function IR/AST that the checker walks after the
function is fully parsed, or (b) thread the lattice through the
existing single-pass `gen_*` walk. Option (b) is less code but cannot
see forward (a use *before* its move in source order is fine; a use
*after* needs the move already recorded). The recommendation is a
**hybrid**: a minimal per-function statement list captured during the
existing walk, then a second walk over that list for the analysis.
This keeps codegen single-pass and untouched.

---

## Part III — The one irreversible decision: how to spell a borrow

Bug classes 1–3 and 5 can be checked **with no new surface syntax** —
they are about *owned* values and their moves/escapes, which NURL
already expresses. Class 6 (aliased mutation) cannot: enforcing
"N readers XOR 1 writer" requires the language to *name* a borrow.
Three options, to be decided before Phase 4:

**Option A — Rust-style reference types `&T` / `&!T`.**
Add two type constructors: `&T` shared/immutable borrow, `&!T`
exclusive/mutable borrow. Explicit, familiar, maximally precise.
Cost: a real syntax surface expansion (`&` is currently only the FFI
marker and bitwise-and — a parser disambiguation job), and it pushes
lifetime questions toward the surface.

**Option B — Mutable value semantics (Hylo / Val style).**
No reference types in the surface at all. Function parameters gain a
*passing convention*: `in` (borrow, immutable — the default),
`inout` (exclusive mutable borrow), `sink` (consume/move). The
compiler infers everything else. This fits NURL's "terse, regular,
LLM-friendly" thesis best — the borrow is a property of the
*parameter*, not a type the generator has to thread everywhere — and
NURL *already* has the `*T`-parameter / return-the-struct idioms that
`inout` would cleanly replace.

**Option C — Keep `*T`, add a checked pointer.**
Minimal syntax change, but `*T` is FFI ABI and overloading it with
safety semantics is a trap. Not recommended.

**Recommendation: Option B.** It is the smallest surface change, it
subsumes the existing three awkward mutation idioms (`*T` param /
return-the-struct / single-handle wrapper) into one concept, and
"convention on the parameter" is far easier for an LLM to emit
correctly than threaded `&'a mut` lifetimes. Phases 1–3 are
deliberately independent of this choice so the decision can be
deferred without blocking the high-value work.

---

## Phase 0 — Analysis substrate: per-function CFG + ownership lattice

**Goal:** a reusable per-function representation the checker walks,
and the lattice it threads — without changing a single byte of emitted
IR.

**Scope:**
- During the existing `gen_fn_decl` walk, capture a flat
  **statement list**: one entry per `:` binding, `=` assignment, `^`
  return, call in statement position, `?`/`~`/`??` block boundary.
  Each entry records: kind, the binding name(s) touched, the
  binding(s) read, source line, and the enclosing block id.
- Build a minimal **CFG** over those entries — `?` forks two
  successors and a join; `~` is a back-edge; `??` arms fork/join.
  NURL's control flow is small (no `goto`, no early `break` past one
  level) so the CFG is cheap.
- Define the **ownership lattice** per binding:
  `Uninit < Owned < {Moved, BorrowedShared, BorrowedMut} < Invalid`,
  with a defined join (e.g. `Owned` joined with `Moved` = `MaybeMoved`,
  which any subsequent use rejects).
- A `borrowck_state` symbol-handle map, the analysis analogue of the
  `mem_*` lists, but per-binding and per-program-point.
- Everything gated behind `--borrowck` (off by default, no-op when
  off).

**Verification:** with `--borrowck` on, the checker runs over the
whole stdlib + compiler + test corpus and emits *nothing* (it has no
rules yet). Bootstrap fixed point holds; IR byte-identical.

**Acceptance:** the CFG + lattice exist and are walked; zero
diagnostics; zero IR change.

**Estimated effort:** ~500 LOC, 6–8h. Largest single phase — it is the
foundation everything else stands on.

---

## Phase 1 — Move checking (use-after-move)

**Goal:** reading a binding after its ownership has moved is an
`error:`.

**Scope:**
- A *move* occurs when an owned binding is: returned (`^ x`), passed
  to a callee parameter that consumes it (initially: the existing
  `__ret_owned__` / consuming-call set — `vec_push`, `thread_spawn`,
  etc.), or assigned into a longer-lived binding / struct field.
- On a move, transition the binding `Owned -> Moved` in the lattice.
- Any subsequent *read* of a `Moved` (or `MaybeMoved`, from a
  conditional move at a CFG join) binding is `error: use of moved
  value 'x' (moved at line N)`.
- Re-assigning a `Moved` binding a fresh value transitions it back to
  `Owned` (revival) — important so loops that move-then-rebuild work.
- Non-owned scalars (`i`, `b`, `f`, plain `*T` from FFI) are `Copy`:
  they never move. Only heap-backed types (`String`, slices, `Vec`,
  user structs with owned fields, `Drop`-trait types) participate.

**Verification:** new `should_fail_borrow_use_after_move.nu` (expected
COMPILE FAIL with the diagnostic captured). The whole stdlib +
compiler must pass clean — any genuine move bug found there is fixed
as part of the phase; any false positive is a Phase 1 bug.

**Acceptance:** use-after-move is rejected; stdlib/compiler are
move-clean; bootstrap holds.

**Estimated effort:** ~350 LOC, 4–5h. Highest value-to-cost ratio of
any phase — no new syntax, closes bug class 1.

---

## Phase 2 — Alias & double-free detection

**Goal:** detect when two live bindings own the same heap resource;
reject the explicit-alias double-free.

**Scope:**
- Track a *provenance* tag per owned binding: a fresh allocation gets
  a unique resource id; `: T b a` (binding-to-binding copy of an
  owned, non-`Copy` type) makes `b` *alias* `a`'s resource id rather
  than getting its own.
- Two bindings sharing a resource id that are both still `Owned` at a
  drop point is `error: 'a' and 'b' both own the same value; the
  drop at end of scope would free it twice`.
- This naturally subsumes the existing "conservative — only fresh
  allocs get a drop" rule and makes it *checked* rather than merely
  *avoided*: copying an owned binding is now either an error or
  (post-Phase 1) recognised as a move.
- Interaction with Phase 1: a binding-to-binding copy of an owned
  value is *either* a move (source becomes `Moved`) *or* a borrow
  (Phase 3+) — never a silent alias. Phase 2's job is to make the
  silent-alias case impossible.

**Verification:** `should_fail_borrow_double_free.nu`. Stdlib +
compiler must be alias-clean.

**Acceptance:** explicit aliasing of owned values is rejected or
classified as a move; bug class 2 closed.

**Estimated effort:** ~300 LOC, 4h.

---

## Phase 3 — Escape analysis (sound replacement for the `__captures_byref` hack)

**Goal:** replace the five-shape name-match `warning:` with a sound
region check, and promote provable escapes to `error:`.

**Scope:**
- Assign every binding a **region** = the scope frame it is declared
  in. Outer scopes outlive inner scopes; the function's own frame
  outlives every block in it; the caller outlives the function.
- A *reference into* a binding (a closure capturing it by pointer, a
  `*T` taken of its alloca, a slice viewing it) carries the
  *referent's* region.
- A reference that flows to a binding / return value / container with
  a **longer-lived** region than its referent is an escape:
  `error: value referencing 'x' (scoped to line N) escapes that
  scope`.
- This subsumes the current closure-byref check completely — and
  catches the shapes it misses (struct-wrapped closures, helper
  indirection, `*T` of a local). The `__captures_byref` /
  `__last_closure_byref__` flags can then be deleted.
- Closures capturing by *value* (the snapshot case) never escape —
  unaffected.

**Verification:** every existing `should_warn_closure_escape*.nu`
test is upgraded: the warnings that were genuine become
`should_fail_borrow_escape_*` errors; the negative controls must stay
clean. `recover`-scope leaks (README known issue) are documented as a
related but separate concern (they leak, they don't dangle).

**Acceptance:** bug class 3 closed soundly; the five-shape hack is
deleted; no false positives across stdlib/compiler.

**Estimated effort:** ~400 LOC, 5–6h.

---

## Phase 4 — Reference / borrow surface (the Part III decision)

**Goal:** give the language a way to *name* a non-owning borrow, so
Phase 5 can enforce exclusivity. **Do not start until Part III is
decided.** Scope below assumes the recommended **Option B (mutable
value semantics)**.

**Scope (Option B):**
- Parameter passing conventions: `in` (default, immutable borrow —
  callee may read, not mutate, not move), `inout` (exclusive mutable
  borrow — callee may mutate, caller's value updated on return),
  `sink` (move — callee consumes). Surface syntax: a marker token on
  the parameter, e.g. `@ f inout Counter c -> v { ... }`.
- `inout` *replaces* the three current mutation idioms: it deprecates
  `*T`-params-for-mutation and the "return the modified struct"
  dance. `*T` stays, but only for genuine FFI.
- The checker enforces, at every call site, that an `inout` argument
  is a mutable place (`: ~` binding or `inout` re-pass) and is not
  simultaneously borrowed elsewhere in the same call.
- Codegen: `inout` lowers to exactly today's `*T`-by-address
  mechanism — so for a borrow-clean program **the emitted IR is
  unchanged from the equivalent `*T` code**. (`in` lowers to today's
  by-value/by-handle; `sink` lowers to today's ownership transfer.)
  This is what keeps Phase 4 bootstrap-safe.

**Verification:** a new `borrow_inout_basic.nu` positive test;
`should_fail_borrow_inout_*` negatives (passing an immutable binding
as `inout`, aliasing an `inout` arg). Grammar snapshot bumped.

**Acceptance:** the surface exists, lowers to known-good IR, round-
trips through `nurlfmt`.

**Estimated effort:** ~450 LOC, 6–8h. Carries the syntax/grammar
risk — `nurlfmt`, the Python stage-0 lexer, and the grammar EBNF all
need the new token.

---

## Phase 5 — Borrow rules: N-readers-XOR-1-writer

**Goal:** the actual borrow checker — at any program point, a value
has either any number of shared borrows or exactly one mutable
borrow, never both.

**Scope:**
- Track, per resource, the set of *live borrows* and their kind
  (shared / mut), threaded through the Phase 0 CFG.
- A new shared borrow while a mut borrow is live, or a mut borrow
  while any borrow is live: `error: cannot borrow 'x' as mutable
  because it is also borrowed (here: line N)`.
- A *use of the owner* while it is borrowed is likewise rejected
  (the owner can't mutate/move out from under a live borrow).
- Borrows end at last-use (non-lexical-lifetime style) — computed
  from the CFG, so `: borrow ...; ( read borrow ); ( mutate owner )`
  on disjoint live-ranges is accepted. Lexical-only borrows would
  reject far too much idiomatic code.

**Verification:** `should_fail_borrow_aliased_mut.nu` +
`borrow_nll_disjoint_ok.nu` (the NLL accept case). This phase will
find real violations in stdlib hot paths — budget time to fix them.

**Acceptance:** bug class 6 closed; NLL-style disjoint borrows
accepted; stdlib/compiler clean.

**Estimated effort:** ~500 LOC, 6–8h. The conceptual core; depends on
0 and 4.

---

## Phase 6 — Iterator invalidation

**Goal:** mutating a container while a `~`-foreach borrows its
elements is an `error:`.

**Scope:**
- `~ x : T xs { ... }` takes a shared borrow of `xs` for the loop
  body's duration (it already "borrows" per the README — Phase 6
  makes that borrow *checked*).
- Any call inside the body that takes `xs` as `inout` / mutates it
  (`vec_push`, `vec_insert`, `vec_set`, `vec_free`, ...) while the
  loop's borrow is live: `error: cannot mutate 'xs' while iterating
  over it`.
- Index-based mutation loops (`~ i k 0 ... ( vec_set xs k v )`) are
  *not* foreach-borrows and stay legal — only the element-borrowing
  `~ x : T xs` form is guarded.

**Verification:** `should_fail_borrow_iter_invalidation.nu`.

**Acceptance:** bug class 5 closed.

**Estimated effort:** ~200 LOC, 2–3h. Mostly a special-case of
Phase 5's machinery applied to the `~`-foreach desugaring.

---

## Phase 7 — Returned borrows + lifetime inference (deferred-by-default)

**Goal:** allow a function to return a borrow into one of its
parameters (`@ first in (Vec T) v -> &T`), checked.

**Scope:** only undertake this if real stdlib code wants it. It needs
the function *signature* to relate the returned borrow's region to a
parameter's region. Keep it **inference-only** — no surface lifetime
syntax. If the single-parameter-source case (the overwhelmingly
common one) can be inferred and the multi-source case is simply
rejected with "return a `sink`/owned value instead", that is an
acceptable v1.

**Verification:** `borrow_return_ref.nu` if pursued.

**Acceptance:** decided per need; may stay deferred indefinitely like
DWARF Phase 7.

**Estimated effort:** ~300 LOC, 4h — *if* pursued.

---

## Phase 8 — Diagnostics polish, docs, flip the default

**Goal:** make `--borrowck` the default; production-quality messages;
documentation.

**Scope:**
- Every diagnostic: ASCII-only (the Python stage-0 lexer mishandles
  multi-byte UTF-8 in string literals — em-dash and `§` are the only
  known-safe ones), a pointing caret, the move/borrow *origin* line,
  and a concrete cure ("pass it as `sink` if the callee should
  consume it", "take a `: ~` copy", ...).
- Flip `--borrowck` on by default; keep `--no-borrowck` as the
  escape hatch for one release.
- `docs/MEMORY.md` (currently a ROADMAP TODO) written *here* — the
  ownership + borrow rules belong in one place.
- `README` "Memory model" section rewritten: the "no borrow checker /
  vibes-based" language goes away.
- `critic.md` §4's central complaint is now answerable.

**Verification:** full `run_tests.sh` + `run_san_tests.sh` green with
borrowck on by default; `should_fail_borrow_*` baselines locked.

**Acceptance:** borrowck on by default, tree green, docs shipped.

**Estimated effort:** ~250 LOC + docs, 3–4h.

---

## Total effort budget

| Phase | What | Hours | LOC | Risk |
|---|---|---|---|---|
| 0 | CFG + lattice substrate | 6–8 | ~500 | med — foundation |
| 1 | Move checking | 4–5 | ~350 | low — high value |
| 2 | Alias / double-free | 4 | ~300 | low |
| 3 | Escape analysis | 5–6 | ~400 | med — replaces a hack |
| 4 | Borrow surface (Option B) | 6–8 | ~450 | **high — grammar** |
| 5 | N-readers-XOR-1-writer | 6–8 | ~500 | high — the core |
| 6 | Iterator invalidation | 2–3 | ~200 | low |
| 7 | Returned borrows | 4 | ~300 | deferred |
| 8 | Polish + docs + default | 3–4 | ~250 | low |
| | **Total (0–6, 8)** | **36–46h** | **~2950** | |

Phases **0–3 + 8-partial** form a shippable milestone on their own:
no new syntax, closes bug classes 1, 2, 3, 5-partial, and lets the
README drop the "no memory-safety story" admission. That is the
recommended first deliverable — roughly 20–25h — before committing to
the Phase 4 grammar change.

---

## Things to watch

1. **Bootstrap fixed point.** The checker must never change IR. After
   every phase: `./build.sh` (stage1 ≡ stage2 byte-identical) and a
   diff of emitted `.ll` for a borrow-clean sample with/without
   `--borrowck`. Any divergence is a bug in the phase.

2. **The stdlib + compiler must pass clean.** Each of Phases 1, 2, 3,
   5, 6 will find genuine issues in NURL's own ~50 stdlib modules and
   the compiler itself. Budget fix-time inside each phase. A phase is
   not done until `nurlc.nu` checks clean against its own new rule —
   that is the proof the rule is both sound and not over-strict.

3. **False positives are worse than false negatives here.** A borrow
   checker that rejects correct code teaches LLMs (and humans) to
   reach for `--no-borrowck`. When a rule is uncertain, `warning:`
   first, promote to `error:` only once it is false-positive-free
   across the whole corpus — exactly how the closure-escape check
   was introduced in 2026-05.

4. **NLL from the start.** Lexical borrows reject too much. Phase 5
   must compute borrow live-ranges from the CFG. This is why Phase 0
   builds a real CFG rather than reusing the scope-frame stack.

5. **`*T` stays unchecked.** `*T` is the FFI ABI escape hatch. The
   borrow checker covers `String` / slices / `Vec` / structs /
   closures. Trying to also check `*T` would break FFI. Document the
   boundary loudly: `*T` is NURL's `unsafe`.

6. **Generics + monomorphisation.** A generic `@ f [T] ...` is checked
   once at the template, not per instantiation — borrow rules are
   type-agnostic (they care about owned-ness, not the concrete type).
   Confirm this holds; if a rule turns out to need the concrete type,
   it belongs in the per-instantiation path and bootstrap cost rises.

7. **`recover` / panic interaction.** Owned values in a `recover`
   scope already leak on panic (documented). The borrow checker
   should *not* try to model panic edges in v1 — treat `recover` as a
   normal call. Note the limitation; don't scope-creep into it.

8. **Interaction with `Drop`-trait types.** A `Drop` type's `drop`
   method runs at scope exit. Move/borrow rules treat it like any
   other owned resource — but verify the `__user_drops__` list and
   the new lattice agree on *when* the drop point is, or a moved
   `Drop` value could be double-dropped or not dropped.

---

## Quick-start when starting an implementation session

1. Re-read this file, `critic.md` §4, and the `mem_*` functions in
   `compiler/nurlc.nu` (`mem_own_add` / `mem_drop_owned` /
   `mem_drop_owned_strings` / `mem_drop_owned_struct_fields` /
   `mem_drop_user_drops` and friends) — the borrow checker lives
   next to them and reuses their notion of "owned".
2. Confirm the current phase against the Status banner at the top.
3. Work behind `--borrowck` until Phase 8.
4. After every change: `./build.sh` (fixed point), then
   `./compiler/tests/run_tests.sh`.
5. Add the phase's `should_fail_borrow_*` / `borrow_*` regression
   tests *first* — they document the rule's shape.
6. End of session: commit with a clear `Borrow Phase N: ...` message,
   update this file's Status banner.

---

*Status: investigation complete 2026-05-20; no phase implemented.
Recommended first deliverable: Phases 0–3 (+ Phase 8 partial) — the
no-new-syntax core. Phase 4 gated on the Part III reference-surface
decision (recommendation on file: Option B, mutable value semantics).
Last updated 2026-05-20.*
