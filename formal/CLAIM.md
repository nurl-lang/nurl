# The claim

> **Status: A1, A2, A3.0, A3.1, A3.4, and the first cuts of A3.2, A3.3,
> A3.5 and A3.6 are proven** (`A1.memory_safe`, `A2.memory_safe`,
> `A2.no_leak_end`, `A3.claim`, [`README.md`](README.md)); the rest of
> A3.2, A3.3, A3.5 and A3.6, and B–D, are the statement the proof is
> working towards, not one it has reached.

## Statement

**Every program the NURL compiler accepts, outside the bodies of `unsafe`
functions and its `unsafe` assertions, is memory-safe and leak-free** —
*proven so far (A1, A2) for the ownership rules of the single-threaded
language as the calculus models them, (A3.0) for threads that share
nothing but what they move, (A3.1) for threads that also share `Arc`
payloads, (A3.2, first cut) `Locked` values, (A3.3, first cut)
`RwLocked` values read through frozen guards, (A3.4) `Atomic` words
and channels, and (A3.5, first cut) library handles whose copies are one
state, which cross a thread only with all their owners, and (A3.6, first
cut) module globals set at start; the data-race clause for the rest of
what threads share is the rest of A3.2, A3.3, A3.5 and A3.6, and the link
from the rules to nurlc and its code is B–D*
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
    thread has finished nothing is allocated but what the module globals
    reach (A3.6; nothing at all for a program without globals,
    `NoLeak.empty`) — on the standard axioms only. The proof gives each thread its own part of the address space,
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
      parameter of the function the body is in) and has the binding hold
      a value again at the end.
    - **Panics.** A panic through a lock scope gives the value back
      (`Step.scopeLP`), as `RwLocked`'s guard drop does on the drop
      journal. `locked_with` instead keeps the lock held, so its runs are
      among the model's: other threads wait. A thread that would wait may
      also panic (`Step.waitPanic`), which covers a runtime that detects
      a self-deadlock and panics (`RwLocked` does).
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
      The model's thread waits or panics, but the runtime's default
      pthread mutex leaves it undefined (Agora #455).
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
  - **A3.3, first cut** *(proven)* — `RwLocked`: a value many threads
    read at once, through frozen read guards, and one changes.
    - **The calculus.** An `RwLocked` is A3.2's lock block. `rw_new`,
      `RwLocked_share` and the write side (`rw_write` / `wguard_update` /
      `rw_update` / `rw_set`) are `locked_new`, `Locked_share` and
      `withLock`, with A3.2's faithfulness premises. A read (`rw_read`)
      makes a view of the lock block: a block that owns nothing and holds
      a share of the lock and its payload, frozen while it lives. The
      read guard is a share of the view, and `rguard_get` lends the
      payload as A3.1's `arc_get` does: its one dependency is the guard
      (`Kind.share`), so no write goes through it (`ThruOK.noShare`,
      `canDo`, an `inout` copy included), and the guard's end ends it.
      A writer waits while a view of the block lives. The reader count
      is ghost: the views still reached.
    - **Panics.** A panic releases a write guard by giving the value back
      (`Step.scopeLP`) and a read guard by dropping it, as the runtime's
      drop journal does. Blocks may change while a panic unwinds. A
      thread that asks for a lock it holds, which the runtime answers
      with a panic, may panic in the model too (`Step.waitPanic`).
    - **Threads.** Readers read the lock block's payload at once, and
      only read it. A writer has it in its own part only while no view
      lives. The reader count and the writer bit are the runtime's
      rwlock (trusted base).
    - **In Lean.** `A2.memory_safe`, `A2.no_leak_end`, `A2.no_leak_panic`
      and `A3.claim` hold with all of this, on the standard axioms only.
    - **Not typed yet:** `rw_try_read` / `rw_try_write`, `wguard_get`,
      `rw_get`'s copy and `wguard_apply`'s result; payloads holding a
      share, a view or a closure, or a library handle (A3.5: h317 h357).
      The model lets a guard cross a spawn, which nurlc refuses
      (`% NotSend`): the runtime's unlock must run on the locking thread.
    - **Not proven here (phase D):** a view lives until no slot reaches
      it, which may be after the guard's drop, where the runtime unlocks.
      As for `Arc`'s refcount, phase D must show that no live binding
      reaches the payload through the guard once it is dropped.
  - **A3.5, first cut** *(proven)* — a library handle whose copies are
    one state (`PNCounter`, a `TcpConn`, a `Cell`): Send, not Sync.
    - **The calculus.** A handle is a cell share (`Val.cell k`, type
      `Ty.cell t`) of an ordinary lock block. `Rhs.cellNew` makes one,
      `Rhs.cellClone` copies an owner's handle, and the library's in-place
      change is A3.2's check-out (`withCell` is `withLock`, with its
      faithfulness premises). A lent handle is no share (`lendOf`), so the
      slots that hold a cell share are its owners, which is what the
      runtime counts. An `Arc` payload holds no handle (`RhsT.arcNew`'s
      `hasCell`, h338), and lock, `RwLocked` and channel payloads hold no
      share at all (h358).
    - **The crossing check.** A spawn's run-time precondition
      (`SendCheck`) is that no slot left in the spawner reaches a cell the
      moved values reach. When it fails, the spawn panics in the spawner
      and no thread is made (`TStep.spawnFail`), as `mem_send_check` does.
    - **Threads.** A race now also counts two threads changing one cell's
      state at once (`Race := AddrRace ∨ CellRace`; `CellOp` is a cell
      check-out, or being inside one while holding a share). The model
      serializes check-outs as a lock's, but the runtime's handles have no
      mutex, so the guarantee is confinement: no two threads hold a share
      of one cell (`CellInv`, A3/Cell.lean), kept by every step and by a
      spawn through `SendCheck`.
    - **In Lean.** `A2.memory_safe`, `A2.no_leak_end`, `A2.no_leak_panic`
      and `A3.claim` hold with all of this, on the standard axioms only.
    - **Closures that cross (A3.5b, first cut).** A closure's type says
      where it may go: `Ty.fn ms q`, with `q` one of `any`, `send` (an
      owned environment that holds no view; a library handle in it is
      covered by the spawn's crossing check), `sync` (`send` and no
      library handle) and `bare` (no share at all). `Rhs.pack` gives the
      class from the captures. An `Arc` keeps a `sync` closure (h342: a
      handler that changes a by-name capture is `any`, h339: one that
      captures a library handle is not `sync`), a lock, `RwLocked` or
      channel a `bare` one (h340), and a spawn takes a `send` one. A call
      through a closure an `Arc` lends is typed (`StmtT.arcCall`): its
      code gets its environment read-only (`Implements`), so threads
      calling it at once only read the payload, A3.1's argument. A
      global `Arc` may keep a handler, so `GlobsOK` asks that every
      closure a block holds names the program's code (`BlkCodes`).
    - **Not typed yet:** a handle changed or copied through a borrow (the
      model takes a library's `in` handle as `inout`, and a store of a
      borrowed handle into an owner is not typed); `% Sync` / `% NotSend`
      assertions; a `send` closure that captures a share in a lock or a
      channel (refused where the runtime would move the handle along);
      no subsumption between closure classes; a closure that changes a
      capture it moved in. Phase C must give each closure the class
      nurlc's follow-the-value check proved, and `any` where it cannot
      follow the closure's origin.
    - **Trait objects (A3.5c).** A trait object is a package as a closure
      is (`Rhs.pack`), so A3.5b's class covers it: its class is the
      trait's bound (`TraitBound`: none, `: Send`, `: Send Sync` give
      `any`, `send`, `sync`; `TraitAt`, `StmtT.callc_bound`), every
      method's code reads the box lent (`CodeOK.env_lent`), the box faces
      the bound at every pack (`ImplOK`), and the spawn's crossing check
      walks the box (`Sub.pkg`; `sendCheck_box_kept`: a library handle
      boxed and kept fails it, the runtime's vtable walk). h344: an
      unbounded object crosses nothing, a `: Send Sync` one boxes no
      library handle (`dyn_cell_notSync`), and an `Arc` or a global's
      `Arc` takes only `: Send Sync` objects. Not typed: a `: Send` object
      in a lock or a channel (they take `bare` packages), an `inout`
      receiver, supertraits and `[T: Send]` bounds; an impl is checked
      where it is boxed, not where it is declared. Phase C must lower each
      `%Trait` to `fn ms` at its bound's class. A library that re-enters its own state waits
      or panics in the model, where the runtime goes on: that is the
      library's code (phase B).
    - **Not proven here:** that a thread inside a cell's check-out holds a
      share of it is argued from typing, not a lemma, and phase D must
      show the runtime's reference count of a handle's block equals the
      model's owners.
  - **A3.6, first cut** *(proven)* — module globals reached by several
    threads.
    - **The calculus.** A global set at start (`: ( Locked T ) g ( make )`)
      is a field of the configuration (`Cfg.gl`, `Mem.gl`) that every
      thread reads and no step writes (`Step.gl`). Its type synchronises
      itself (`Ty.sync`: a lock, `RwLocked`, `Atomic` or channel share, or
      an `Arc` of no library handle), so a `( Vec T )` global is refused
      (h263). A read (`Rhs.glob`) gives an owned clone of the global's
      share, so `withLock`, a read guard, a channel or an atomic operation
      on it are A3.2–A3.4's rules unchanged. A scalar global is an
      `Atomic` set at start: its read and write are `atomic_load` /
      `atomic_store` (h273, h202: nothing hands it anything to own).
    - **The start.** `A3.claim` takes the start's globals as a premise
      (`GlobsOK`: each fits a synchronising type, A2's invariant holds of
      them, and every block is reached from one). With no global it is
      the earlier statement. The sweep keeps what the globals reach, and
      `NoLeak` says only that is left once every thread has finished, as
      the runtime keeps globals until the process exits.
    - **In Lean.** `A2.memory_safe`, `A2.no_leak_end`, `A2.no_leak_panic`
      and `A3.claim` hold with all of this, on the standard axioms only.
    - **Assumed, not proven:** the runtime reads and writes a scalar
      global with relaxed atomics, where DRF-SC is cited for `seq_cst`.
      Every access is atomic, so there is no data race either way; the
      interleaving model is exact up to the integers a load returns, and
      no ownership fact reads them.
    - **Not typed yet:** the `make` phase (that running each `make` leaves
      a start satisfying `GlobsOK`); a read's type tied to its global's
      declared type (a read at another type panics in the model, and
      nurlc types each read by the declaration); `Cond` / `Semaphore`
      globals. Owning, struct and option globals are `unsafe`-only, the
      trusted base (h202 h272 h273).
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
  #396, #424, #428, #434, #460 and #461 (`Eff.kills`, `StmtT.editB`,
  `callPostAux`'s `kill`). A keyword argument is the same call, and a
  callee's summary carries a drop through an element of its parameter
  however the element was reached.
- A view a value comes to hold, not recorded where it goes: #338, #341,
  #346, #348, #362, #367, #368, #369, #370, #377, #380, #381, #383, #390,
  #393, #422 and #442. A2 records it in `Ty.holdsView`,
  `PushArg`, `pair`'s `Dy ++ Dz`, `callRes`'s `rholds` and `heldOfArgs`,
  `callPostAux`'s `outHeld` and `heldOfArgs`, and a package's interface
  summary; past a join, `ite` and `while` keep what either path holds.
- A move or take nurlc does not see: #280, #357, #446 and #458 (`unpair`,
  `takel`, a `sink` takes an owner only, `lendable`).
- A borrow ended by a binding's end, replacement or capture, missed:
  #242, #364, #382, #384, #406, #407, #408 and #445 (`exitScope`,
  `assign`'s `kill .replace`, `CapsOK`, `NamesFree`, `FnOK` at the body's
  one end, where a `^`, a `\` exit and the defers lead, `catchR`,
  `DtorSafe`).
- A struct built from an owner and a view of it: #294 (`pair`: the owned
  field is no root of the other's dependencies).
- A view stored through a borrow that nurlc does not follow to its owner:
  #395's call as the container and its option payload cursor, and #454's
  forms where the callee's root is an owner or an `inout` parameter
  (`StmtT.editBV`: the stored view's dependencies land on every
  view-holding root of the borrow's path, `holdThru`, as nurlc's
  `__bck_store_owners` does; `rules/t292.md`). That includes #454's
  plain parameter whose elements' elements the callee changes: it reads
  as `inout drop` (RULES.md's first reading), its summary holds the view
  (`outHolds`), and the caller's owner holds it after the call
  (`callPostAux`'s `outHeld`; A2/EditB.lean's note).
- A changed parameter handed an element of the caller's owner: #391
  (`( f 1 ( vec_at vv 0 ) src )`, and a local bound from the element).
  The call reads as handing the element over (`Stmt.withElem`: the
  element moves out into an owner the callee takes `inout`, and back at
  its index, so `vv` holds what the callee stored into it; borrows of
  `vv` end at the hand-over; A2/EditB.lean's note).

Outside A2:
- The hand-over of an old value to its borrower (above): #366, #373, #378,
  #387 and #459, plus #427 (a call that may hand back the owner's value
  where nurlc has no lend fact for it at the `=`: a wrapper, a generic
  or later-defined callee, a value block) and #450 (shapes the hand-over
  gate does not reach: a struct given a part of itself through a callee
  whose summary is not final, a scalar enum key, a struct cursor copy)
  and #456 (an `inout` Box, map, Rc or Arc given a lend; a `sink`
  argument handed back into an `inout`).
- An `Rc`'s shared state, which is the standard library's (B): #345 and
  #392.
- A view stored through a borrow inside closure code: #395's store
  through a borrow of a capture, and #454's `vec_each` form (`StmtT.editBV`
  types a store through a borrow outside closures).
- #391's other forms: a changed parameter handed an element of an
  `inout` or borrowed parameter, or a borrow that is not an element (a
  cursor of a whole `Vec`, a field viewer), or a call that also names the
  `Vec` in another argument. Inside a call, what a borrowed parameter
  reaches is frozen, so A2 has no change rooted at one, and
  `Stmt.withElem` takes an owner's element only.

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
