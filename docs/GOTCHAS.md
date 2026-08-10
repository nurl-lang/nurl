# Gotchas

> **No gotchas outside the documented ownership contract.** The known
> deliberately-undiagnosed cases (e.g. the conditional double-free, closed
> under `--strict-borrowck`) are enumerated in
> [`MEMORY.md` §6.2/§6.5](MEMORY.md).

Every other source-level trap that once needed memorisation is reported by
the compiler itself: `nurlc` emits an `error:` / `warning:` with a pointing caret
and the concrete cure inline, so a wrong program tells you what to fix at the
point you wrote it. If you hit a NURL compile error, the diagnostic is the
source of truth — read it rather than guessing.

One trap deserves naming because the compiler's report is a **warning**
by default, and the program it describes still builds: every operator has
a **fixed arity**, and `&` / `|` take exactly two operands. So

```nurl
? & a b c d { then } { else }        // NOT a four-way AND
```

reads as `? (& a b) c d`, leaving `c` and `d` consumed as the bare
then/else values and the two blocks running as ordinary statements — the
conditional logic is wrong and the binary works, which is why nothing
downstream notices. Write n-1 operators for n conditions:

```nurl
? & & & a b c d { then } { else }    // (((a & b) & c) & d)
```

`nurlc` points its caret at the `?` and names the cure. The trap is a
hard **error by default**; `--no-strict-arity` demotes it to a warning
for trees that need to keep building. This repo additionally runs
`tools/check_strict_arity.sh` over its whole first-party tree in CI, and
that gate's first run found a shipped example culling every particle on
every frame for exactly this reason.

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
