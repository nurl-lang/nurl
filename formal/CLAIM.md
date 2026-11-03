# The claim

> **Status: A1, A2, A3.0, A3.1, A3.2's first cut and A3.4 are proven**
> (`A1.memory_safe`, `A2.memory_safe`, `A2.no_leak_end`, `A3.claim`,
> [`README.md`](README.md)); the rest of A3.2, A3.3, A3.5, A3.6 and B–D are
> the statement the proof is working towards, not one it has reached.

## Statement

**Every program the NURL compiler accepts, outside the bodies of `unsafe`
functions and its `unsafe` assertions, is memory-safe and leak-free** —
*proven so far (A1, A2) for the ownership rules of the single-threaded
language as the calculus models them, (A3.0) for threads that share
nothing but what they move, (A3.1) for threads that also share `Arc`
payloads, (A3.2, first cut) `Locked` values and (A3.4) `Atomic` words
and channels; the data-race clause for the rest of what threads share is
the rest of A3.2, A3.3, A3.5 and A3.6, and the link from the rules to
nurlc and its code is B–D*
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
  Elements change through their owner, an `inout` binding, or any borrow
  of them (Agora #295). A push, a truncation or an element set through a
  borrow — an element of a Vec of Vecs, a field viewer, a join of
  borrows, a call's lent result — is typed as the strongest change on
  every owner the borrow's path may reach (`StmtT.editB`): every borrow
  of those owners' elements ends, and on a push only copies of a
  same-typed owner's whole handle survive. Two of nurlc's forms read as
  forms the calculus has (`RULES.md`, phase C): a function that changes a
  Vec or String it takes as a plain parameter reads as an `inout`
  parameter, and a change through a copy of one owner's whole handle
  (`( id vs )`, a cursor) as that owner's own change. Outside the claim
  still:
  - a change through a borrow of a Vec whose elements hold views;
  - a pop or a remove through a borrow (the steps are push, truncate and
    set);
  - what nurlc keeps beside such a change that the calculus ends: two
    parts of one value, copies of the changing borrow, a whole copy beside
    a field viewer (Agora #118, github#1426);
  - a callee that changes a plain parameter's elements when its caller
    hands it an element, a field viewer or a call's result rather than an
    owner;
  - a closure or a destructor that changes elements through a borrow,
    directly or through a callee, and a call into a function that does so
    which passes an argument holding views (`ThruFn`).

  One more form nurlc accepts that A2 does not type: an owner given a new
  value while something still reads its old one, where nurlc hands the
  old value over instead of dropping it — to a field's reader when the
  field is replaced (Agora #265, #354), or kept where a call may give the
  owner its own value back (`= o ( f … o … )`, #342, #375). A2's `assign`
  gives an owner only an owned value, and never one that depends on the
  binding itself (`x ∉ roots E.vdeps`). DynCell's encoding
  (`A2/DYN_DESIGN.md`) covers a per-call result bound to a fresh binding,
  and an owner given a lend that cannot come out of its old value
  (`rules/t375.md`); it does not cover the hand-over. Those programs are
  outside the claim until an A2 rule (or phase C/D) covers the hand-over.
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
  - **A3.1** *(proven)* — `Arc`: a frozen payload shared by threads.
    - **The calculus.** `arc_new` moves a value into a shared block,
      `arc_clone` makes a new share, and `arc_get` lends the payload as a
      borrow that depends on its share (`Kind.share`) and ends with it.
      The payload may allocate (`Arc ( Vec … )`). It holds no view and no
      closure.
    - **What a block owns.** A block owns its payload tree (`BlkOwn`),
      and no step writes a payload while its block lives (`BlkLe`). A
      change through a borrow never reaches one (`ThruOK.noShare`).
    - **Freeing.** A block lives while some thread's slot, or a live
      payload, holds a share of it or a handle into it. A sweep at the end
      of every step frees the rest, over all threads.
    - **Threads.** The address space is each thread's part plus a
      shared, read-only payload part. Two threads meet on a payload only
      by reading it. The sweep's frees are writes to a block no thread
      reaches.
    - **In Lean.** `A2.memory_safe`, `A2.no_leak_end`, `A2.no_leak_panic`
      and `A3.claim` hold with all of this, on the standard axioms only.
    - **Not proven here (phase D):** the runtime frees an `Arc` at
      refcount 0, which may be earlier than the sweep. Phase D must show
      that refcount 0 means no live binding reaches the block. That
      follows from typing, since every borrow of a payload depends on a
      share. An `Arc` of a value that holds views or closures is not
      typed yet, and neither is an `Arc` of a library handle whose copies
      are one state (A3.5).
  - **A3.2, first cut** *(proven)* — `Locked`: a value one thread at a
    time changes.
    - **The calculus.** A lock is a second kind of block. `locked_new`
      moves a value into a lock block, and `Locked_share` makes a new
      share. `locked_update l f` (and `locked_with`) checks the payload
      out to a binding of the body, owned, and gives it back at the
      body's end (`withLock`, `scopeL`). A thread whose lock is checked
      out waits (`Blocked`), which is not stuck. Deadlock freedom is not
      claimed.
    - **Faithful to the in-place runtime.** The runtime runs `f` on the
      value inside the lock, where the model checks it out and back. The
      two agree because the typing keeps the lock alive through the body
      (the body does not name the share, which is an owner or a
      parameter of the function the body is in) and has the binding hold a value again at the end. On a
      panic, `locked_with` keeps the lock held, as the model does: other
      threads wait, and nothing reaches the value until the last share's
      drop frees it.
    - **Threads.** A checked-out payload is in its holder's part, and a
      payload in its block is read by no one. Taking and giving back a
      lock touch only the lock word, which the runtime's mutex changes
      atomically (trusted base, beside DRF-SC).
    - **In Lean.** `A2.memory_safe`, `A2.no_leak_end`, `A2.no_leak_panic`
      and `A3.claim` hold with all of this, on the standard axioms only.
    - **Not typed yet:** a lock's payload that holds a share, a view or a
      closure (a `Locked` of an `Arc`); a lock reached through a local
      borrow (a field or an element); `locked_take` / `locked_restore`
      (h267); and `Mutex` beside the data it guards.
    - **Not proven here (phase D):** relocking a lock on the OS thread
      that holds it (a nested update, or another fiber on that thread).
      The model's thread waits, but the runtime's default pthread mutex
      leaves it undefined (Agora #455).
  - **A3.4, `Atomic` and channels** *(proven)* — an integer every thread
    reads and changes, and a queue values move through.
    - **The calculus.** An `Atomic` is a lock block of an integer that is
      never checked out: `atomic_new`, `Atomic_share` and its drop are
      A3.2's `locked_new`, `Locked_share` and a share's drop.
      `atomic_load`, `store`, `add`, `sub`, `swap`, `max` and `cas` are one
      step each on the block's word (`Rhs.atomic`), with the answers
      `stdlib/std/atomic.nu` gives.
    - **Threads.** The word is no address of the calculus, as a lock's
      word and an `Arc`'s count are not, so it races with nothing. That
      each operation is one step is the runtime's: every `nurl_atomic_i64_*`
      is one `__ATOMIC_SEQ_CST` operation, and DRF-SC (trusted base,
      below) makes such a program behave as its interleavings.
    - **In Lean.** `A2.memory_safe`, `A2.no_leak_end`, `A2.no_leak_panic`
      and `A3.claim` hold with it, on the standard axioms only. The
      model's integers are naturals, so `atomic_sub` saturates where the
      runtime's wraps; no memory fact reads the number.
    - **Channels.** A channel is a lock block whose payload is its queue
      and its closed flag, as the runtime's `ChImpl` holds a `Vec` and a
      flag behind its mutex. `chan_new` and `Channel_share` are a lock's.
      `chan_send` moves the value to the back of the queue, out of the
      sender's part, or drops it when the channel is closed (answer 0).
      `chan_recv` moves the front out to the receiver, owned (an option:
      none when closed and empty), and waits while the queue is empty and
      open (`RBlocked`). `chan_try_recv` answers none at once, and
      `chan_close` sets the flag. Each is one step: the queue's ends are
      the runtime mutex's (trusted base). Values in a queue are the
      block's tree, in no thread's part, so they race with nothing, and
      the sweep frees what is left in a queue with its block (`no_leak`).
    - **Not typed yet:** a channel of values that hold a share, a view or
      a closure (a `Channel` of `Arc`s, of closures: A3.5's crossing),
      `chan_len`, `chan_is_closed` and `select`. Deadlock freedom, and that
      a waiting `chan_recv` is woken, are not claimed.
  - **A3.3, A3.5, A3.6** — the rest of what threads share: `RwLocked` and
    `% Frozen` read guards, library handles whose copies are one state,
    module globals. Not proven (`A3/DESIGN.md` gives the design: they use
    A3.1's blocks).
- **B** — the `unsafe` base of the standard library is semantically
  well-typed, so safe code built on it inherits the theorem.
- **C** — every program nurlc accepts is well-typed in the formal rules.
- **D** — the code nurlc generates behaves as the formal semantics says.

Until B, C and D are done, the theorem is about the rules; the standard
library, the compiler and the code generator are part of the trusted base.

## The known exceptions: the open holes

Each soundness hole known open (`tools/fuzz/holes/open/t<N>.md`, listed
in `docs/LIMITATIONS.md` at each release) is a program nurlc accepts that
faults. Every one is an exception to the statement above. Nearly all are
one of two kinds:

- **Inside A2.** The calculus expresses the program and refuses it, so
  the hole is a nurlc bug: nurlc must be brought into line with A2. The
  proof is unaffected, and phase C would catch the disagreement.
- **Outside A2.** The calculus does not type the program's form yet, so
  the claim says nothing about it until the form is added (or nurlc
  refuses it).

Classified by claude-formal after v0.85.0 and github#1549 (2026-11-03).
The A2 rule that refuses each shape is named.

Inside A2 (nurlc bugs):
- A change in place that ends a borrow, missed: #333, #349, #350, #360,
  #396, #424, #428, #434 and #447 (`Eff.kills`, `StmtT.editB`,
  `callPostAux`'s `kill`). A keyword argument is the same call, and a
  callee's summary carries a drop through an element of its parameter
  however the element was reached. Also a closure that changes elements,
  called where nurlc reads it by its interface only: #433, #435, #436
  and #449. Its code is no `ThruFn` of an interface whose plain
  parameters are unchanged (`Implements`).
- A view a value comes to hold, not recorded where it goes: #338, #341,
  #346, #348, #362, #367, #368, #369, #370, #377, #380, #381, #383, #390,
  #393, #422, #442, #448 and #452. A2 records it in `Ty.holdsView`,
  `PushArg`, `pair`'s `Dy ++ Dz`, `callRes`'s `rholds` and `heldOfArgs`,
  `callPostAux`'s `outHeld` and `heldOfArgs`, and a package's interface
  summary; past a join, `ite` and `while` keep what either path holds.
- A move or take nurlc does not see: #280, #357, #446 and #451 (`unpair`,
  `takel`, a `sink` takes an owner only, `lendable`).
- A borrow ended by a binding's end, replacement or capture, missed:
  #242, #364, #382, #384, #406, #407, #408, #444 and #445 (`exitScope`,
  `assign`'s `kill .replace`, `CapsOK`, `NamesFree`, `FnOK` at the body's
  one end, where a `^`, a `\` exit and the defers lead, `catchR`,
  `DtorSafe`).
- A struct built from an owner and a view of it: #294 (`pair`: the owned
  field is no root of the other's dependencies).
- An `inout` option given a lend: #343 (`assign` gives an `inout` binding
  only an owned value).

Outside A2:
- The hand-over of an old value to its borrower (above): #366, #373, #378,
  #387 and #388, plus #427 (a call that may hand back the owner's value
  where nurlc has no lend fact for it at the `=`: a wrapper, a generic
  or later-defined callee, a value block) and #450 (shapes the hand-over
  gate does not reach: a struct given a part of itself through a callee
  whose summary is not final, a scalar enum key, a struct cursor copy)
  and #456 (an `inout` given a lend by name, or of a Box, map, Rc or Arc).
- An `Rc`'s shared state, which is the standard library's (B): #345 and
  #392.
- A view stored through a borrow: #395 and #454 (`StmtT.editB` takes
  element types that hold no views; `rules/t292.md`).
- A changed plain parameter handed an element rather than an owner: #391
  (above).

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
  open there: a callee that keeps a view parameter in a holder other
  than its first argument ties it to the first one (#370).

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
