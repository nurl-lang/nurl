# Sound and complete: every accepted program is memory-safe and leak-free

Goal (owner, 2026-10-06): retire the "sound, not complete" contract of
[`MEMORY.md` §6.2](MEMORY.md). Today every diagnostic is a real bug, but a
clean compile proves nothing, and AddressSanitizer is what actually keeps
the corpus safe. The target is a guarantee:

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
   - a function that returns a parameter takes it by move (auto-`sink`),
     so the caller's binding is gone, never aliased.
   `vec_get` and its kin are specified from the start as returning a
   borrow of the element, so their implementation can later become a
   projection into the slot without changing a line of user code.

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
