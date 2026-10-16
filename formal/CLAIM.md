# The claim

> **Status: under construction.** This is the statement the proof is
> working towards, not one it has reached.

## Statement

**Every program the NURL compiler accepts, outside the bodies of `unsafe`
functions, is memory-safe and leak-free:** no use after free, no double
free, no read through a dangling view, no out-of-bounds access, no data
race, and everything it allocated is released — on the panic path as much
as the normal one.

This is the guarantee of [`docs/MEMORY.md` §6.2](../docs/MEMORY.md),
stated as a theorem. "Memory model" here means NURL's ownership model:
who owns an allocation, when it is released and which programs the rules
reject. Concurrency enters through data-race freedom (A3), proven against
the LLVM / C11 memory model rather than redefining it.

## What each phase proves

- **A1** — the theorem for the core calculus: a well-typed core program
  never gets stuck on a freed or out-of-bounds access, and typing is
  preserved by every step.
- **A2** — the theorem for the full single-threaded language, including
  panics, and leak freedom: when a program ends, normally or by panic,
  nothing it allocated is still live, `Rc` cycles included.
- **A3** — the theorem with threads: a well-typed program has no data
  race.
- **B** — the `unsafe` base of the standard library is semantically
  well-typed, so safe code built on it inherits the theorem.
- **C** — every program nurlc accepts is well-typed in the formal rules.
- **D** — the code nurlc generates behaves as the formal semantics says.

Until B, C and D are done, the theorem is about the rules; the standard
library, the compiler and the code generator are part of the trusted base.

## Trusted base

Even when every phase is done, these remain trusted rather than proven
(the same list as `docs/MEMORY.md` §6.4, minus what B–D remove):

- the proof assistant's kernel;
- `unsafe` functions outside the standard library — each vouches for
  itself, and `nurlc --unsafe-report` lists them;
- marker assertions (`% Send`, `% Sync`, `% NotSend`, `% NotSync`,
  `% Resource`) on types whose safety the compiler cannot see;
- the C runtime, LLVM, the linker and the operating system.
