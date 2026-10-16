# formal — a mechanized proof of NURL's memory model

> **Status: A1 is proven** (Lean 4, no `sorry`, only Lean's standard
> axioms — `./check.sh`). The later phases are not. Until a phase below is
> marked done, the part of the guarantee in
> [`docs/MEMORY.md` §6.2](../docs/MEMORY.md) it covers rests on the
> compiler's tests (§6.6), not on a proof; and until phase C, the proof is
> about the rules, not about nurlc's implementation of them.

The goal is the statement in [`CLAIM.md`](CLAIM.md): every program the
compiler accepts outside the bodies of `unsafe` functions is memory-safe
and leak-free, data races and the panic path included — proven as a
theorem about the ownership rules, with the compiler's verdicts tied to
that theorem.

## Phases

The first round proves the rules themselves (A1–A3). The trusted base and
the implementation (B–D) follow once the rules have stopped moving.

| Phase | Scope | Status |
|---|---|---|
| **A1** | Core calculus: owned values, moves and drop flags, borrows and views, a `Vec` that reallocates (§2.10), `inout`, `sink`. Single-threaded, no panics. Soundness: progress and preservation. | **done** |
| **A2** | A1 plus structs and their fields, closures, generics, traits and `dyn`, enum and option payloads, panics and the drop journal — and **leak freedom**. | planned |
| **A3** | A2 plus threads: `Send` / `Sync`, `Arc`, `Mutex`, `Locked`, channels, M:N fibers. Data-race freedom against the LLVM / C11 memory model. | planned |
| **B** | The standard library's `unsafe` base proven to meet the semantic types it is given: `Vec`, `String`, `HashMap`, `Rc` and the cycle collector, `Arc`, channels. | later |
| **C** | nurlc implements the rules: the compiler emits a certificate for each accepted program and a small verified checker validates it. | later |
| **D** | Code generation preserves the semantics: drop insertion, drop flags and the panic journal, by translation validation. | later |

## Layout

```
formal/
  README.md        this file
  CLAIM.md         the theorem in words, its scope per phase, and the trusted base
  RULES.md         every ownership rule of docs/MEMORY.md → its formal rule and status
  corpus/map.tsv   every hole probe → the formal rule that rejects it, or its phase
  check.sh         builds the proof and checks it has no sorry and no new axiom
  lean-toolchain, lakefile.toml, A1.lean, Check.lean
  A1/              the A1 proof (Lean 4, core library only)
```

### A1 — the modules

| Module | Contents |
|---|---|
| `Syntax` | types, effects (`Eff`: none ≤ realloc ≤ drop ≤ replace) and what each ends (`Eff.kills`), statements, functions and their summaries |
| `Semantics` | the store (owned trees, borrowed handles `href`, views), every step, the call (`callStmt`: parameters bound, the body renamed apart and run in their scopes); a step that would touch freed or out-of-bounds memory has no rule, so it is *stuck* |
| `Typing` | flow-sensitive contexts: each binding's mode, liveness, what it borrows from (`path`) and what its value holds (`held`); `kill` ends what an effect on a root ends; the call checked against the callee's summary (`CallT`); `FnOK` checks a body against its summary |
| `Invariant` | what a well-typed configuration guarantees of memory (`MInv`, `Inv`) |
| `Basic`, `Ctx`, `Stability`, `Heap`, `Values`, `Frame`, `Rhs`, `Steps`, `TypingFacts`, `Wf` | the invariant through each kind of step |
| `Preservation`, `Progress` | the two halves of soundness, every rule |
| `Rename` | a callee's body, typed once against its own view of its parameters, is typed where a call places it |
| `Call`, `Bind`, `CallMem`, `CallInv` | the call step: typing of the expansion, the store after binding the parameters, the invariant |
| `Soundness` | `soundness`, `memory_safe` |

The theorem, `A1.memory_safe`: for a program whose functions all check
against their summaries (`ProgOK`), a source statement well-typed in the
empty context, run from the empty store, never reaches a stuck
configuration — every reachable one has finished or can step (a failed
bounds check steps to a panic, a safe stop).

## How it relates to the rest of the repository

- [`docs/MEMORY.md`](../docs/MEMORY.md) stays the readable specification.
  Each rule in §2 gets a pointer to its formal counterpart in `RULES.md`
  as it is formalized.
- [`tools/fuzz/holes/`](../tools/fuzz/holes/) is the corpus the rules are
  checked against: every probe must be rejected by a named formal rule
  (`corpus/map.tsv`).
- Nothing here is compiled into nurlc or the standard library. Changes
  that touch only `formal/` do not run the compiler CI jobs (see
  `.github/workflows/ci.yml`, `macos-tests.yml`, `windows-tests.yml`).
