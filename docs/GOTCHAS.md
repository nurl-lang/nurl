# Gotchas

> **Currently no known gotchas.**

Every source-level trap that once needed memorisation is now reported by the
compiler itself: `nurlc` emits an `error:` / `warning:` with a pointing caret
and the concrete cure inline, so a wrong program tells you what to fix at the
point you wrote it. If you hit a NURL compile error, the diagnostic is the
source of truth — read it rather than guessing.

The few things that are *not* surprises but fixed properties of the language
or its runtime live in their proper homes, not here:

- **Grammar properties** — prefix notation, every operator's fixed arity,
  `^` being `return` (and `^^` being XOR): [`LIMITATIONS.md` → Grammar](LIMITATIONS.md)
  and the authoritative [`../spec/grammar.ebnf`](../spec/grammar.ebnf).
- **Ownership & lifetimes** — single-owner auto-drop, and the borrow
  checker's escape analysis for `: ~`-mutable closure captures:
  [`MEMORY.md`](MEMORY.md).
- **Async/fiber runtime** — non-blocking handle flipping, `runtime_run`
  blocking semantics, and runtime-maintainer notes:
  [`ASYNC.md` → Operational caveats](ASYNC.md#operational-caveats).

If a real source-level surprise turns up that the compiler does *not* yet
diagnose, that is a compiler bug: it belongs in a `compiler/tests/should_fail_*.nu`
regression and a new diagnostic, after which it stays out of this page.
