# formal — a mechanized proof of NURL's memory model

> **Status: under construction.** The work has started; nothing in this
> directory is proven yet. Until a phase below is marked done, the
> guarantee in [`docs/MEMORY.md` §6.2](../docs/MEMORY.md) rests on the
> compiler's tests (§6.6), not on a proof.

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
| **A1** | Core calculus: owned values, moves and drop flags, borrows and views, a `Vec` that reallocates (§2.10), `inout`, `sink`. Single-threaded, no panics. Soundness: progress and preservation. | started |
| **A2** | A1 plus closures, generics, traits and `dyn`, enum and option payloads, panics and the drop journal — and **leak freedom**. | planned |
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
  corpus/map.tsv   every hole probe → the formal rule that rejects it
```

Proof sources are added when the proof assistant is chosen (the first A1
task). The intended shape is one module each for syntax, operational
semantics, typing, one file per ownership rule, the soundness theorems and
an executable reference checker that `check.sh` runs differentially
against nurlc over `tools/fuzz/holes/` and the fuzzers.

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
