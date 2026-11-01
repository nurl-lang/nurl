# The claim

> **Status: A1, A2 and A3.0 are proven** (`A1.memory_safe`,
> `A2.memory_safe`, `A2.no_leak_end`, `A3.claim`, [`README.md`](README.md));
> A3.1–A3.6 and B–D are the statement the proof is working towards, not one
> it has reached.

## Statement

**Every program the NURL compiler accepts, outside the bodies of `unsafe`
functions and its `unsafe` assertions, is memory-safe and leak-free** —
*proven so far (A1, A2) for the ownership rules of the single-threaded
language as the calculus models them, and (A3.0) for threads that share
nothing but what they move; the data-race clause for what threads share is
A3.1–A3.6, and the link from the rules to nurlc and its code is B–D*
(below): no use after free, no double free, no read through a dangling
view, no out-of-bounds access, no data race, and everything it allocated
is released — on the panic path as much as the normal one.

This is the guarantee of [`docs/MEMORY.md` §6.2](../docs/MEMORY.md),
stated as a theorem. "Memory model" here means NURL's ownership model:
who owns an allocation, when it is released and which programs the rules
reject. Concurrency enters through data-race freedom (A3), proven against
the LLVM / C11 memory model rather than redefining it.

## What each phase proves

- **A1** *(proven)* — the theorem for the core calculus: a well-typed core
  program never gets stuck on a freed or out-of-bounds access, and typing
  is preserved by every step. In Lean: `A1.soundness` (from any
  configuration satisfying the invariant) and `A1.memory_safe` (from the
  empty store), resting on `propext`, `Classical.choice` and `Quot.sound`
  only. The calculus has owned `Vec` trees, moves and drop flags, `sink`,
  `inout` with a bound on what the callee may do, borrows and views,
  reallocation, element drop, reassignment and release, and calls checked
  against function summaries; a `String` is a `Vec` of bytes. Structs,
  closures, enums and the rest of the language are A2.
- **A2** *(proven)* — the theorem for the single-threaded language as the
  calculus models it, including panics, and leak freedom: when a program
  ends, normally or by panic, nothing it allocated is still live. In Lean:
  `A2.soundness`, `A2.memory_safe` and `A2.no_leak_end`, on the standard
  axioms only. The calculus adds to A1 structs and enums with field-precise
  paths, closures and trait objects as packages with captures by handle
  and by name, `inout` of every owning type and a field replaced in place,
  panics with unwinding and `recover`, and the drop journal.
  A capture by name holds no views. nurlc refuses a closure that gives a
  capture, or its own `inout` parameter, a view (Agora #312, #331), except
  by two routes: the view bound to a local of the closure's body first, and
  a push into a plain Vec parameter of the closure. Programs that take one
  are outside the claim until Agora #332 lands.
  `Rc` cycles are the standard library's (B); see `README.md` for the
  refinements of the calculus still planned.
  Elements change only through their owner or an `inout` binding. nurlc
  also changes them through other copies of a handle. Two of those read
  as forms the calculus has (`RULES.md`, phase C): a function that
  changes a Vec or String it takes as a plain parameter, as the standard
  library's own mutators take theirs, reads as an `inout` parameter, and
  a change through a copy of one owner's whole handle (`( id vs )`, a
  cursor) as that owner's own change. A change through any other borrow
  (an element of a Vec of Vecs, a field viewer, a join of borrows, a
  call's lent result) is outside the claim until Agora #295 lands.
- **A3** — the theorem with threads: a well-typed program has no data
  race. Proven under sequential consistency, where a race is two threads'
  next steps touching one address, one of them writing, not both atomic.
  Carried to C11 / LLVM by the DRF-SC theorem (below). The statement is
  `A3.Claim` in `A3/Defs.lean`, and `A3/DESIGN.md` gives the semantics
  and the milestones.
  - **A3.0** *(proven)* — threads that only move. A function the program
    marks is called on a new thread; its parameters are `sink` and of
    types that hold no views (`SpawnOK`), so what crosses is trees the
    spawner gives up. Every thread runs A2's own step on the shared
    address space. In Lean: `A3.claim : A3.Claim` — no thread of a
    reachable configuration is stuck, no two threads race, and when every
    thread has finished nothing is allocated — on the standard axioms
    only. The proof gives each thread its own part of the address space,
    on which A2's invariant holds: a step on the shared space is a step on
    the part and leaves the other parts as they were, and a spawn cuts the
    spawner's part in two.
  - **A3.1–A3.6** — what threads share: `Arc`, `Locked` / `Mutex`,
    `RwLocked` and `% Frozen` read guards, `Atomic` and channels, library
    handles whose copies are one state, module globals. Not proven.
- **B** — the `unsafe` base of the standard library is semantically
  well-typed, so safe code built on it inherits the theorem.
- **C** — every program nurlc accepts is well-typed in the formal rules.
- **D** — the code nurlc generates behaves as the formal semantics says.

Until B, C and D are done, the theorem is about the rules; the standard
library, the compiler and the code generator are part of the trusted base.

## Destructors, and a panic while a panic unwinds

A destructor written by the program (`% Drop T { @ drop … }`,
docs/MEMORY.md §7.6) is inside the calculus for every type, views included
(A2-drop.1 and A2-drop.2, `A2/DROP_DESIGN.md`).
- A binding with a destructor (`StmtT.letd`) is scoped by `scopeD`.
- At its end, while it still owns its value, the destructor runs as a call
  of the program's function, on the binding lent (`Step.scopeDEnd`). Then
  the scope frees the tree: the drop glue after the impl.
- A panic that unwinds to the frame stops there. It runs the destructor,
  frees the binding, and raises again (`Step.scopeDP`). The frame is gone,
  so a panic inside the destructor does not run it again, and `scope x`
  still frees the fields.
- A destructor of a type that holds views reads them, so what they point
  into outlives the binding while it may own its value (#224's rule,
  `DtorSafe`). No rule ends such a view on any path, the panic path
  included. A binding `letd` made gains no view: it is assigned nothing,
  pushed no view, and is no `inout` argument.
- `memory_safe`, `no_leak_end` and `no_leak_panic` cover all of this, on
  the standard axioms. That includes a *double panic*: a destructor that
  panics while a panic unwinds.
- The calculus puts the destructor on the binding `letd` makes, not on
  the type. A value moved out of that binding, into a `sink` parameter,
  another binding or a field, is released by `DropSlot` where it ends,
  which runs no code. nurlc runs the destructor there too. Putting the
  destructor on the type is A2-drop.3 (Agora #253).

The rules are stricter than nurlc's in two places, both for a binding of
a type whose destructor may read a view:
- nurlc lets it gain views of older bindings;
- nurlc lets it be an `inout` argument, whose callee may give it views
  only of what the caller passed in: a view of the callee's own local is
  refused where it is given, even for a moment (#284). One shape is still
  open there: a callee that stores into it a view of a String
  parameter's buffer (`string_data src`) is not tracked at the call
  (#301).

How the runtime carries this out (`stdlib/runtime_core.c`, `nurl_panic`)
is stated here so the claim does not hide it:

- the second panic is caught by the same `recover` frame as the first;
  the drain it starts releases what the journal still holds (each entry
  leaves the journal before its drop runs, so nothing is dropped twice),
  and the `recover` reports the first panic's message — the cause;
- the drain the second panic interrupted is ended by the frame that
  catches it (`nurl__drain_unwind`): the thread's drain state is reset,
  so later frees are ordinary;
- with no `recover` frame, any panic ends the process (`abort`) before a
  drain starts, so nothing is released twice and the process's memory goes
  with it.

Test: `compiler/tests/panic_in_drop_while_unwinding.nu` (clean under
AddressSanitizer and LeakSanitizer). That the journal's drain does what
`Step.scopeDP` does is phase C / D.

## Trusted base

Even when every phase is done, these remain trusted rather than proven
(the same list as `docs/MEMORY.md` §6.4, minus what B–D remove):

- the proof assistant's kernel;
- `unsafe` functions outside the standard library — each vouches for
  itself;
- `unsafe % Send` / `unsafe % Sync` assertions outside the standard
  library, on types whose safety the compiler cannot see (a positive
  marker stops the derivation; every other marker only adds checks, so a
  safe module may write it — `docs/MEMORY.md` §3);
- the `in`, `sync` and `nocapture` claims of foreign declarations outside
  the standard library (`sync` is a data-race claim about C code);
- `nurlc --unsafe-report` lists all three, one `file:line` each;
- until B: the standard library's own marker assertions and foreign
  claims, in both directions — each `% Send` / `% Sync` it writes, and each
  `% NotSend`, `% NotSync` and `% Frozen` it must not leave out
  (`% Frozen RGuard {}` in `stdlib/std/rwlock.nu`: what a read guard lends
  is read-only);
- the DRF-SC theorem of the C11 / LLVM memory model: a program none of
  whose sequentially consistent runs has a data race behaves as under
  sequential consistency (Boehm & Adve, PLDI 2008; Batty et al., POPL
  2011). It is cited, not mechanized. It applies because safe NURL's
  atomics are all `seq_cst` (`nurl_atomic_i64_*`) and its locks are the
  runtime's;
- the C runtime, LLVM, the linker and the operating system.
