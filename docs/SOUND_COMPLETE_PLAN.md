# Sound and complete: every accepted program is memory-safe and leak-free

Goal (owner, 2026-10-06), reached in 0.71.0: retire the "sound, not
complete" contract [`MEMORY.md` §6.2](MEMORY.md) stated until 0.70.0, under
which every diagnostic was a real bug but a clean compile proved nothing and
AddressSanitizer was what actually kept the corpus safe. The target, now
stated in MEMORY.md §6 (since the pre-production hardening with no
exception: h32, a `Slice` of a `Vec`, is closed), is a guarantee:

> A program that compiles without an `unsafe` declaration is memory-safe
> (no use-after-free, double free, dangling reference, out-of-bounds
> access or data race) and leak-free.

## Decisions

1. **Trust boundary = `unsafe`.** Raw memory (`*T` reads/writes and
   casts, `nurl_alloc` / `nurl_free`, `mem_forget`, calls to `&` FFI
   declarations that are not vouched for) is allowed only in `unsafe`
   code. The stdlib is the vouched-for base. The compiler can list a
   program's whole unsafe surface.
2. **Rules, not only bugs.** The checker rejects what it cannot prove,
   not only what it can prove wrong. Every rejection is a named rule and
   its message gives the concrete fix (LLM usability). This replaces the
   "no false positive" property of §6.3.
3. **Data races are memory safety.** Safe code cannot share mutable state
   across threads except through the synchronised types.

4. **Static moves and borrows** (owner, 2026-10-06). The P0 probes show
   one root cause behind every hole: an owning handle (String, Vec, a
   capturing closure) copies freely — out of `vec_get`, a struct field,
   an Option literal, a closure capture, a channel, a thread, a generic
   identity — and the checker follows *names*, not values, so each rule
   recognises one shape of "a second name appears". The fix is the model,
   not more shapes:
   - an owned value is **move-only**: storing it (aggregate literal,
     Option, container push), sending it, returning it, passing it to a
     `sink` parameter, or capturing it in a closure that escapes moves it;
     any later use is an error, and a maybe-moved value is an error too;
   - a read that does not take ownership — `vec_get` of an owning element,
     a field read, `string_data` — yields a **borrow** tied to its source;
     the borrow can be read but never released, stored as an owner or sent
     (the fix the message gives: clone it), and it ends when its source is
     moved, released, reassigned or mutated in a way that may reallocate;
   - a function that returns a parameter hands it back as a borrow: the
     argument stays the owner and the result borrows from it (see
     "A call result borrows only…" below — the implementation chose this
     over an auto-`sink` move).
   `vec_get` and its kin are specified from the start as returning a
   borrow of the element, so their implementation can later become a
   projection into the slot without changing a line of user code.

### Refinements found by running the rules over the corpus

- **Two kinds of borrow.** A *handle borrow* (a Vec / String / struct
  handle copy: `vec_get`, a field read, a cursor `: ~ b a`) points at the
  owner's control block, so growing the container does not end it; it ends
  when an owner is released, moved, reassigned, has a field replaced, or is
  handed to a call that may drop its elements. A *view* (`string_data`,
  `vec_data`) also ends at any mutation that may reallocate.
- **Borrows flatten to owners.** A borrow of a borrow borrows from what
  that one borrows from: re-pointing a cursor frees nothing. Dropping
  elements or replacing a field *through* a borrow reaches its owners.
- **Assignment moves an owner, copies a borrow.** `= z a` / `: T z a`.
- **A call result borrows only from the arguments the callee lends or
  hands back** (its summaries; all arguments for a callee not yet
  compiled). A result the call consumed its argument into is owned.
- **Only values with something to release move**: a struct of scalars or
  an enum of unit variants (an error code) is copied.
- **Payloads of a borrowed parameter are borrows**: consuming one needs the
  parameter declared `sink`.
- **Closures.** A closure handed to a call that may keep it makes the
  call's other owners depend on its captures (C1). A closure run on
  another thread or fiber moves its captures (C2) — except handles whose
  copy is a share of one object (Channel, Mutex, Arc): the closure's env
  takes a share of its own (code generation, not only the checker), so
  the spawner keeps using its handle and either side may end first.

### Corpus work the rules surfaced

- Types shared across threads that are plain structs today must become
  library handles with `_share` (HttpServer).
- Containers that hold views of strings another container owns (the
  resolver's and lru's maps keyed by `string_data`) are sound only by an
  argument the checker cannot make: they become `unsafe` with that
  argument written down, or own their keys.

## Phases

- **P0 — the oracle.** `tools/fuzz/holes/` holds one probe per proven
  hole and `check.sh` counts them (12 on 2026-10-06, all in safe code). A must-reject fuzzer: mutate ownership-heavy
  programs into likely violations; any program the compiler ACCEPTS that
  ASan/LSan then faults on is a hole. The hole count over a fixed seed
  budget is the progress metric; the goal is zero, held by CI.
- **P1 — `unsafe`.** Grammar, the raw-operation classification, the
  vouched-for FFI set, propagation, the unsafe-surface report, and safe
  replacements for the common raw idioms (`vec_data` loops → checked
  indexing / slices the optimiser keeps fast).
- **P2 — close the safe-subset holes.** Every "not checked" / "partial" /
  `--strict-borrowck` row of §3, §5, §2.9 becomes a default rule with a fix
  hint: maybe-aliased consume, the aggregate-conduit boundary, returned
  borrows (`s` views of Strings), element-dropping wrappers, aliased
  mutation across statements.
- **P3 — races.** Shared mutable state only via `Mutex` / `Arc` /
  channels; lock held proved by path, not counted.
- **P4 — leaks.** Close the documented seams (the defer-return seam,
  §7.1), and state the leak argument for safe code (auto-drop, the panic
  journal, the Rc cycle collector).
- **P5 — the contract.** Rewrite MEMORY.md §6 as the guarantee and the
  argument for it; the ASan gate stays as a regression net, not as the
  guarantor.

## Status (2026-10-06)

- **P0** done: 19 probes in `tools/fuzz/holes/` (h01–h31), every one
  rejected by default; the inverse-oracle fuzzer has seven ownership cores.
  h32 (2026-10-07, found while preparing 0.71.0) was the open one: a
  `Slice` built from a `Vec` was not tracked as a view of it. Closed with
  h33–h127 by docs/HARDENING_PLAN.md (views are values).
- **P1** done: `unsafe` functions and methods (spec §3.3d), raw pointer
  reads/writes, pointer casts, raw-memory primitives and foreign functions
  outside the stdlib gated; `nurlc --unsafe-report`. The corpus marks its
  raw code `unsafe` (the compiler itself: 204 functions). The safe
  replacement for the commonest raw idiom (`vec_data` loops):
  `vec_at` / `vec_put` / `vec_get` run at raw-pointer cost (2026-10-06:
  the Vec control block is read without a branch around the load, and
  its accesses and the element accesses carry TBAA tags that keep them
  apart; `tools/vec_parity.sh` gates it in CI), so hot loops in packages
  can move from `vec_data` + `unsafe` to the safe API.
- **P2** done: moves, borrows, views, keeping containers and callees,
  closures (C1/C2) — the rules are the default; `NURL_SOUND=0` restores
  the old checker for A/B triage only.
- **P3** partly: a closure run on another thread moves its captures and
  only share handles cross threads (Channel, Mutex, Arc; HttpServer became
  one). Open: proving the lock is held by path (today a counted lint).
- **P4** done for the documented seam (defer/return, per-path transfer
  flag); the leak argument is MEMORY.md §6.2 + §7.
- **P5** done: MEMORY.md §6 states the guarantee; ASan/LSan stay as the
  compiler's regression net.
