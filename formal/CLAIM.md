# The claim

> **Status: A1, A2 and A3 are proven** (`A1.memory_safe`, `A2.memory_safe`,
> `A2.no_leak_end`, `A2.no_leak_panic`, `A3.claim`, `A3.claim_made`;
> [`README.md`](README.md)). Each phase's section below names what its
> calculus leaves out. Phases B–D are the statement the proof is working
> towards, not one it has reached.

## Statement

**Every program the NURL compiler accepts, outside the bodies of `unsafe`
functions and its `unsafe` assertions, is memory-safe and leak-free** —
*proven (A1, A2) for the ownership rules of the single-threaded language
as the calculus models them, and (A3.0–A3.6) for programs whose threads
share: threads that move values (A3.0), `Arc`'s frozen payloads (A3.1),
`Locked` and `Mutex` values (A3.2), `RwLocked` values with their `% Frozen`
read guards, which are `% NotSend` (A3.3), `Atomic` words and channels
(A3.4), library handles whose copies are one state, under the crossing
check, and closures and trait objects that cross threads (A3.5, A3.5b,
A3.5c), and module globals set by their `make` before `main` (A3.6). What
each milestone's calculus leaves out is listed in its section below
(the phase-D obligations on the runtime among it; deadlock freedom is not
claimed). The link from the rules to nurlc and its code is B–D*
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
- **A3** *(proven)* — the theorem with threads: a well-typed program has no data
  race. Proven under sequential consistency, where a race is two threads'
  next steps touching one address, one of them writing, not both atomic.
  Carried to C11 / LLVM by the DRF-SC theorem (below). The statements are
  `A3.claim` (`A3/Claim.lean`) and `A3.claim_made` (`A3/Make.lean`), and `A3/DESIGN.md` gives the semantics
  and the milestones.
  - **A3.0** *(proven)* — threads that only move. A function the program
    marks is called on a new thread; its parameters are `sink` and of
    types that hold no views and no destructor value (`SpawnOK`), so what crosses is trees the
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
    - **Slices of shares.** A slice's elements may hold shares (`Ty.ok (slice t)` asks no view): a slice holds a view, so it never crosses a thread (`slice_not_send`).
    - **In Lean.** `A2.memory_safe`, `A2.no_leak_end`, `A2.no_leak_panic`
      and `A3.claim` hold with all of this, on the standard axioms only.
    - **Not proven here (phase D):** the runtime frees an `Arc` at
      refcount 0, which may be earlier than the sweep. Phase D must show
      that refcount 0 means no live binding reaches the block. That
      follows from typing, since every borrow of a payload depends on a
      share. An `Arc` of a value that holds views is not typed. An `Arc`
      of a closure is A3.5b's (a `sync` one, below), and the typing refuses
      an `Arc` of a library handle (`RhsT.arcNew` asks `t.hasCell = false`:
      a cell share is not Sync, A3.5).
  - **A3.2** *(proven)* — `Locked`: a value one thread at a
    time changes.
    - **The calculus.** A lock is a second kind of block. `locked_new`
      moves a value into a lock block, and `Locked_share` makes a new
      share. `locked_update l f` (and `locked_with`) checks the payload
      out to a binding of the body, owned, and gives it back at the
      body's end (`withLock`, `scopeL`). A thread whose lock is checked
      out waits (`Blocked`), which is not stuck. Deadlock freedom is not
      claimed.
    - **Faithful to the in-place runtime.** The runtime's lock is a
      check-out too (`stdlib/runtime_locked.c`): a lock word that is free,
      held in place by one holder, or taken out, and no OS mutex is held
      while `f` runs. It runs `f` on the value where it lies, where the
      model moves it out and back. The
      two agree because the typing keeps the lock alive through the body
      (the body does not name the share, which is an owner or a
      parameter of the function the body is in) and has the binding hold
      a value again at the end.
    - **Panics.** A panic through a lock scope gives the value back
      (`Step.scopeLP`), as `RwLocked`'s guard drop does on the drop
      journal. `locked_with` instead keeps the lock held, so its runs are
      among the model's: other threads wait. A thread that would wait may
      also panic (`Step.waitPanic`), which covers a runtime that detects
      a self-deadlock and panics: `RwLocked` does, and so do `Locked` (a
      holder asking for the lock it holds in place) and `Mutex` (an
      error-checking one: a relock, or an unlock by a thread that does not
      hold it), since Agora #455.
    - **Threads.** A checked-out payload is in its holder's part, and a
      payload in its block is read by no one. Taking and giving back a
      lock touch only the lock word, which the runtime changes with one
      atomic compare-and-swap (trusted base, beside DRF-SC).
    - **In Lean.** `A2.memory_safe`, `A2.no_leak_end`, `A2.no_leak_panic`
      and `A3.claim` hold with all of this, on the standard axioms only.
    - **Second cut: shares in payloads, `locked_take` / `locked_restore`.**
      A lock's payload and a channel's element may hold `Arc`, lock,
      `RwLocked`, `Atomic` and channel shares (`Ty.ok (lk t)` asks no view
      and no library handle), so a `Locked ( Arc T )`, a
      `Channel ( Arc T )` and a channel of `Atomic`s are typed, and a
      `sync` closure fits in a lock or a channel. The sweep reaches
      through a lock's payload (`Blk.keeps`). `locked_take` moves the
      payload out to the caller and `locked_restore` moves a value back
      (`Rhs.lockTake`, `Rhs.lockRestore`; restoring a value that is in
      panics, as the runtime does). The take leaves the block empty, so a
      restore drops nothing (h267). The runtime's `mem_take` moves the
      value out too, so the model's move is exact.
    - **Cycles.** The sweep frees a cycle of shares, where the runtime's
      counts never reach zero. A cycle through a block's payload can form
      only through a closure's environment (a closure kept in an `Arc` or
      a lock that captures a share of it): types are finite otherwise.
      nurlc refuses such stores (docs/MEMORY.md §7.7) and the model does
      not, so `no_leak` agrees with the runtime for the programs nurlc
      accepts: a phase C obligation, stated.
    - **The rest of the operations, as derived forms.** Each is a
      statement of A2's rules, typed whole by a lemma of its own, so the
      theorems cover it with no new case:
      - `locked_get` is a lock scope that copies the value out with
        `mem_dup` (`StmtT.lockedGet`; a library handle is refused, as the
        runtime's `locked_get` panics on one).
      - `locked_set` checks the new value before the lock is touched
        (`StmtT.lockedSet`, `lockedSet_check`), as `mem_send_check` runs
        before `mutex_lock`.
      - `locked_apply`'s and `wguard_apply`'s result holds no lend of the
        payload (`ApplyFn`, `StmtT.lockedApply`, `StmtT.wguardApply`).
      - `locked_await` is rounds of check-outs until one hands back a
        result (`StmtT.lockedAwait`; a waiting round is `Blocked`, and the
        rounds with nothing changed are the runtime's spurious wake-ups).
      - `Mutex` is a lock of an integer taken and restored
        (`StmtT.mutexLock` / `mutexUnlock` / `mutexWith`). It guards no
        memory (`mutex_owns_nothing`), so memory safety never rests on
        one: a race on the data beside it is refused by the data's own
        type (h319).
      - A lock reached through an element or a field is handed over
        first (`StmtT.withLockElem`, `StmtT.withLockField`), and one the
        function does not own is passed in as `locked_update` takes it
        (`LockFn`).
    - **Not typed yet:** that `locked_set`'s
      give-back check never fails in a reachable configuration (argued
      from `CellInv.one`); the closure the operations run called through
      a package (here a statement in place or a function of the
      program).
    - **Not proven here (phase D):** that the runtime's lock word is the
      model's block state. (Relocking a lock its holder has, a nested
      update, was undefined while the runtime held a default pthread mutex
      across `f`; another fiber on that thread stopped its worker. Since
      Agora #455 the first panics, as `Step.waitPanic` allows, and the
      second parks.)
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
    - **Not typed yet:** a channel of values that hold a view (shares,
      library handles under the crossing check, and `send` closures are
      typed since A3.2's and A3.5's second cuts); a channel of destructor
      values, or of values holding one at any depth (its queue is a `Vec`,
      whose element type `Ty.ok` asks to hold none since A2-drop.3b, and a
      lock's payload owns none since A2-drop.3d: see *Destructors*); `chan_len`,
      `chan_is_closed` and `select`. Deadlock freedom, and that
      a waiting `chan_recv` is woken, are not claimed.
  - **A3.3** *(proven)* — `RwLocked`: a value many threads
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
    - **Second cut.** `rw_try_read` / `rw_try_write` answer none where
      they would wait (`Rhs.rwTryRead`, `Rhs.rwTryWrite`; a try-read's
      `some` is `rw_read`'s guard). A try-write is the answer followed by
      the write check-out, two steps: another thread may take the lock
      between them, which only adds runs. `wguard_get` is a borrow of the
      write scope's binding (`wguard_get_path`, `StmtT.wguardGet`), and
      `rw_get` a read scope whose body copies the value out with
      `mem_dup` (`Stmt.rwGet`, `dup_call`, `copy_outlives`).
    - `rw_get` is typed as one statement with every scope's end
      (`StmtT.rwGet`), and `wguard_apply`'s result as `locked_apply`'s.
      `mem_dup` is typed by its summary (`DupFn`); that nurlc's intrinsic
      meets it is phase D's. A read guard refuses a
      payload that holds a library handle (`RhsT.rwRead`'s `hasCell`,
      h357): readers read it at once, so it faces Sync. An `RwLocked` of
      one is still made and written.
      A read guard is `% NotSend`: the crossing check refuses a value that
      holds a guard at any depth (`NoGuard`, part of `SendCheck`), so a
      spawn, a value going into a lock and a lock scope's give-back never
      carry one to another thread, and the runtime's unlock runs on the
      locking thread (`spawn_guard`, `lockNew_guard`, `chanSend_guard`).
      That no guard leaves its thread is argued over reachable
      configurations, not a lemma.
    - **Not proven here (phase D):** a view lives until no slot reaches
      it, which may be after the guard's drop, where the runtime unlocks.
      As for `Arc`'s refcount, phase D must show that no live binding
      reaches the payload through the guard once it is dropped.
  - **A3.5** *(proven)* — a library handle whose copies are
    one state (`PNCounter`, a `TcpConn`, a `Cell`): Send, not Sync.
    - **The calculus.** A handle is a cell share (`Val.cell k`, type
      `Ty.cell t`) of an ordinary lock block. `Rhs.cellNew` makes one,
      `Rhs.cellClone` copies an owner's handle, and the library's in-place
      change is A3.2's check-out (`withCell` is `withLock`, with its
      faithfulness premises). A lent handle is no share (`lendOf`), so the
      slots that hold a cell share are its owners, which is what the
      runtime counts. An `Arc` payload holds no handle (`RhsT.arcNew`'s
      `hasCell`, h338). A lock, `RwLocked` or channel holds one under the
      crossing check (the second cut, below; a lock is Sync whatever it
      holds, h358).
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
    - **Closures that cross (A3.5b).** A closure's type says
      where it may go: `Ty.fn ms q`, with `q` one of `any`, `send` (an
      owned environment that holds no view; a library handle in it is
      covered by the spawn's crossing check), `sync` (`send` and no
      library handle) and `bare` (no share at all). `Rhs.pack` gives the
      class from the captures. An `Arc` keeps a `sync` closure (h342: a
      handler that changes a by-name capture is `any`, h339: one that
      captures a library handle is not `sync`), a lock, `RwLocked` or
      channel a `send` one under the crossing check (h340: a kept handle
      fails it and the send panics), and a spawn takes a `send` one. A call
      through a closure an `Arc` lends is typed (`StmtT.arcCall`): its
      code gets its environment read-only (`Implements`), so threads
      calling it at once only read the payload, A3.1's argument. A
      global `Arc` may keep a handler, so `GlobsOK` asks that every
      closure a block holds names the program's code (`BlkCodes`).
    - **Second cut: handles in locks and channels.** A lock's payload, a
      channel's element and a cell's state may hold library handles, and
      a `send` closure or a `: Send` trait object fits there. The
      crossing check runs at every entry, as `mem_send_check` does:
      `locked_new`, a cell's constructor, `locked_restore` and `chan_send`
      ask `SendCheck` of the value against the thread's other slots and
      panic when it fails (`lockNewFail`, `cellNewFail`,
      `lockRestoreFail`, `chanSendFail`); the give-back at a lock scope's
      end asks it too (`GiveCheck`), and a failed one panics with the lock
      held (`Step.scopeLFail`), as `locked_with` does. A lock is Sync
      whatever it holds (`Ty.hasCell (lk _) = false`, h358).
      Confinement (`CellInv`) now places every cell's owners in one
      thread's slots or in one block's payload, never split
      (`Step.cellKeep`); a check-out, a take and a receive move them with
      the value. The model's receive also checks that the head shares no
      cell with an element left in the queue (`RecvCheck`): a channel is
      a lock block in the model, so a lock check-out could fill a queue
      the runtime's checked sends never do. `GlobsOK` asks the globals'
      blocks to keep each cell's shares in one block.
    - **Third cut: a handle used through a borrow.** A lent handle is the
      share itself (`lendOf`), so a library's `in` handle is changed in
      place (`withCell` through a borrowed root, `StmtT.withCellIn`) and
      copied from (`cellClone` of a borrow, as `PNCounter_share`). A lent
      share lands in an owner's tree (`CellLanded`): a live binding holding
      a cell share has an owner of it in the same store
      (`MInv.cell_owned`). So the crossing check counts owners only, as
      the runtime's count does (`sendCheck_owner_left`), and a dead borrow
      left in scope does not fail it (`sendCheck_dead_borrow_ok`).
      Confinement is over owners and live borrows (`CellInv`,
      `cellAt_of_live`), and a race on a cell is two threads with an
      owner's share at a check-out (`CellOp`).
    - **Not typed yet:** a store of a borrowed handle into an owner (the
      runtime's implicit copy); a handle changed through a borrow that is
      no root; `% Sync` / `% NotSend` assertions on a program's own types;
      that a thread inside a cell's check-out holds an owner's share is
      argued from typing, not a lemma; `locked_take` through a cell share; a failed give-back
      frees the value where the runtime keeps it in the held lock (no one
      reaches it either way);
      a closure that captures by name and also changes its environment;
      subsumption inside a container's element type (a `Vec` of `sync`
      closures is no `Vec` of `any` ones). Classes are ordered bare ≤
      sync ≤ send ≤ any, and a closure moved or copied up the order is
      typed (`RhsT.moveUp`, `RhsT.copyUp`, `Cross.Fits.mono`), as is a
      call through an interface declared at a higher class
      (`StmtT.callcUp`, `StmtT.arcCallUp`). Phase C must give each closure
      the class nurlc's follow-the-value check proved, and `any` where it
      cannot follow the closure's origin.
    - **The environment handed over (`callcE`).** A call through an owned
      closure or trait object may change its environment: the environment
      moves out of the package into a fresh owner, the code takes it
      `inout` (`Implements` with an `inout` receiver), and the package is
      rebuilt after (`StmtT.callcE`, A2/EnvHand.lean). A panic drops the
      environment, as the drop journal does with the closure's binding.
      Such a package is at most `send` (`callcE_not_sync`,
      `callcE_not_arc`), so threads sharing a closure never change its
      environment, and a borrow never hands it over (`callcE_not_bor`:
      what an `Arc` or a read guard lends is never an `inout` argument,
      h364). An accumulator is typed whole and `memory_safe` / `no_leak`
      apply to it (`accMain_safe`, `accMain_no_leak`), and h365's and
      h366's rules are named (`hand_ends`, `canDo_inout_replace`). Not
      typed yet: an interface with parameters beside the receiver, or
      whose result borrows from the receiver; a hand-over through a
      borrowed closure parameter.
    - **Trait objects (A3.5c).** A trait object is a package as a closure
      is (`Rhs.pack`), so A3.5b's class covers it: its class is the
      trait's bound (`TraitBound`: none, `: Send`, `: Send Sync` give
      `any`, `send`, `sync`; `TraitAt`, `StmtT.callc_bound`), every
      method's code reads the box lent (`CodeOK.env_lent`), the box faces
      the bound at every pack (`ImplOK`), and the spawn's crossing check
      walks the box (`Sub.pkg`; `sendCheck_box_kept`: a library handle
      boxed and kept fails it, the runtime's vtable walk). h344: an
      unbounded object crosses nothing (and, as every package, boxes no
      `% Drop` value: *Destructors*, A2-drop.3c), a `: Send Sync` one boxes no
      library handle (`dyn_cell_notSync`), and an `Arc` or a global's
      `Arc` takes only `: Send Sync` objects, and a lock or a channel a
      `: Send` one under the crossing check (A3.5's second cut). Not
      typed: an upcast to a supertrait's objects; an
      impl is checked where it is boxed, not where it is declared. A bound
      is answered by the class (`TraitBound.Holds`, `holds_fn`; a
      supertrait's bound is kept, `Holds.mono`), and A2 has no generics: a
      `[T: Send]` bound is checked on each monomorphised instance. Phase C must lower each
      `%Trait` to `fn ms` at its bound's class. A library that re-enters its own state waits
      or panics in the model, where the runtime goes on: that is the
      library's code (phase B).
    - **Not proven here:** that a thread inside a cell's check-out holds a
      share of it is argued from typing, not a lemma, and phase D must
      show the runtime's reference count of a handle's block equals the
      model's owners.
  - **A3.6** *(proven)* — module globals reached by several
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
    - **Second cut: the make phase.** `A3.claim_made` states the claim
      from the program's global declarations (`Decl`: a `make` of no
      parameters returning an owned value of a `Ty.sync` type, `DeclsOK`).
      Each `make` runs before `main`, single-threaded, from the empty
      store (`makeStmt`, `Made`), and is itself memory-safe and race-free
      (`made_safe`). What the makes leave satisfies `GlobsOK` (`make_ok`,
      `made_ok`), so the premise is derived, not assumed; a make that
      panics ends the program before `main` (`MakePanics`). A typed
      program reads each global at its declared type (`ProgGlobs`,
      `Stmt.globsAt`), so no read panics (`Reach.glob_typed`).
    - **Not typed yet:** that the make phase terminates (a make that loops
      or deadlocks never reaches `main`); a make that spawns a thread;
      `Cond` / `Semaphore` globals. Owning, struct and option globals are `unsafe`-only, the
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
The A2 rule that refuses each shape is named. The holes opened since
then (#464 and later, listed in `docs/LIMITATIONS.md`) are not classified
here yet.

Inside A2 (nurlc bugs):
- A change in place that ends a borrow, missed: #349, #350, #360,
  #396, #424, #428, #434, #460 and #461 (`Eff.kills`, `StmtT.editB`,
  `callPostAux`'s `kill`). A keyword argument is the same call, and a
  callee's summary carries a drop through an element of its parameter
  however the element was reached.
- A view a value comes to hold, not recorded where it goes: #348, #367,
  #381, #383, #390 and #393. A2 records it in `Ty.holdsView`,
  `PushArg`, `pair`'s `Dy ++ Dz`, `callRes`'s `rholds` and `heldOfArgs`,
  `callPostAux`'s `outHeld` and `heldOfArgs`, and a package's interface
  summary; past a join, `ite` and `while` keep what either path holds.
- A move or take nurlc does not see: #280, #357 and #462 (`unpair`,
  `takel`, a `sink` takes an owner only, `lendable`).
- A borrow ended by a binding's end, replacement or capture, missed:
  #242, #364, #382, #384, #406, #407, #408 and #445 (`exitScope`,
  `assign`'s `kill .replace`, `CapsOK`, `NamesFree`, `FnOK` at the body's
  one end, where a `^`, a `\` exit and the defers lead, `catchR`,
  `DtorSafe`).
- A struct built from an owner and a view of it: #294 (`pair`: the owned
  field is no root of the other's dependencies).
- A view stored through a borrow that nurlc does not follow to its owner:
  #395's call as the container and its option payload cursor
  (`StmtT.editBV`: the stored view's dependencies land on every
  view-holding root of the borrow's path, `holdThru`, as nurlc's
  `__bck_store_owners` does; `rules/t292.md`).
- A changed parameter handed an element of the caller's owner: #391
  (`( f 1 ( vec_at vv 0 ) src )`, and a local bound from the element).
  The call reads as handing the element over (`Stmt.withElem`: the
  element moves out into an owner the callee takes `inout`, and back at
  its index, so `vv` holds what the callee stored into it; borrows of
  `vv` end at the hand-over; A2/EditB.lean's note).

Outside A2:
- The hand-over of an old value to its borrower (above): #366, #373, #378
  and #387, plus #427 (a call that may hand back the owner's value
  where nurlc has no lend fact for it at the `=`: a wrapper, a generic
  or later-defined callee, a value block) and #450 (shapes the hand-over
  gate does not reach: a struct given a part of itself through a callee
  whose summary is not final, a struct cursor copy).
- An `Rc`'s shared state, which is the standard library's (B): #345 and
  #392.
- A view stored through a borrow inside closure code: #395's store
  through a borrow of a capture (`StmtT.editBV` types a store through a
  borrow outside closures).
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
  of the program's function on the binding (`Step.scopeDEnd`): lent to a
  destructor that takes it lent, after which the scope frees the tree; or
  moved into a struct's glue, which takes it apart (Agora #616, below).
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
- The destructor is on the type (`Ty.dtor f t`, of a struct or an enum,
  since A2-drop.3a). What is a **theorem** (`A2/DtorWitness.lean`, axioms
  printed by `check.sh`), for a type that holds a destructor value
  (`Ty.holdsDtor`: a destructor type, or a struct or an enum one field or
  payload of which holds one, at any depth since A2-drop.3b):
  - a typed `letv` binds no owned value of such a type
    (`A2.Dtor.letv_owned_no_dtor`): its owned value's type is free of
    destructor values at any depth (`A2.Dtor.letv_owned_dtor_free`);
  - a typed call's owned result of such a type, and an `unpair` field of
    one, is handed on first thing (`Stmt.movedFirst`: into a `letd`, by
    `assign y (.var w)` into another binding of the same type, whose own
    binder answers for it, or taken apart by `unpair`, whose fields are
    handed on in turn) and assigned nothing
    (`A2.Dtor.letcall_hands_over`, `A2.Dtor.unpair_hands_over`);
  - a typed function's `sink` parameter of such a type is handed on first
    thing in its body and assigned nothing, an `inout` one is assigned
    nothing, and an owned result of such a type is set at most once on any
    path, and is of a destructor type itself (no views, no closure), its
    function a `DtorOK` destructor (`A2.Dtor.fnOK_dtor_params`);
  - a call's owned result of a destructor type, or that is a `Vec` of
    destructor values, has a destructor frame from the start: the call's
    inside is `scopeD r g …` on the result slot, `g` the result type's
    destructor (`A2.Dtor.result_frame_is_scopeD`: the shape of the call's
    inside, no more). `memory_safe` and the leak theorems cover the frame
    (its typing is `CallH.typedIn_of`'s);
  - a typed `letd` binds a value of a destructor type `Ty.dtor f t`, or
    (A2-drop.3b) a `Vec` of such values whose elements hold no views
    (`A2.Dtor.letd_binds`); `f` is the destructor of `Ty.dtor f t`
    (`DropFnOK`: one that takes it lent, or a struct's glue, Agora #616),
    and the binding is assigned nothing in its scope (`A2.Dtor.letd_dtor`);
  - at the end of a typed `scopeD x f` frame whose `x` still owns its
    value, a struct or an enum, the frame's only step calls `f` on `x` (lent,
    the tree freed after; or moved into a struct's glue) (`A2.Dtor.scopeD_end_runs_dtor`); a panic out
    of its body with `x` owning runs it too
    (`A2.Dtor.scopeD_panic_runs_dtor`);
  - A2-drop.3b, the drain, step by step. In a state the invariant holds
    of, what a typed frame's `x` owns says which step its end takes: a
    value that is no node is of the destructor type, and a node is a `Vec`
    of such values, each element a struct or an enum of that type
    (`A2.Dtor.scopeD_frame_value`, over `A2.Dtor.scopeD_typed`). At the end
    of a `scopeD x f` frame whose `x` owns a `Vec` with an element, the
    frame's only step hands element 0 to a fresh destructor binding under
    the same frame (`A2.Dtor.scopeD_end_drains`); the step after it leaves
    that binding's own frame, the element in it and the `Vec` one element
    shorter (`A2.Dtor.scopeD_drain_binds`); with no element left the
    frame's only step frees the empty `Vec` (`A2.Dtor.scopeD_end_empty`). A
    panic out of the frame's body with `x` owning a `Vec` stops at the
    frame and leaves it at its end again, followed by the panic
    (`A2.Dtor.scopeD_panic_drains`);
  - what drops a `Vec`'s elements with no code takes no `Vec` of
    destructor values: in the context it is typed in, the `Vec` of a typed
    `vec_free` (`A2.Dtor.free_dtor_free`), of a typed change that drops
    elements, `vec_truncate`, `vec_clear` and `vec_set`
    (`A2.Dtor.edit_drops_dtor_free`), and of a typed `withElem`
    (`A2.Dtor.withElem_dtor_free`) has an element type that owns no
    destructor value;
  - the premises are satisfiable: a typed program with a destructor type,
    its destructor, a function returning an owned value of it, a `letd` of
    a struct literal and of a call's result, with `memory_safe` applied
    (`A2.DtorWitness.main_safe`, `main2_safe`); an option of a destructor
    value: the value moved into `Some`, the option bound by `letd` at its
    own destructor type, its glue (`A2.DtorWitness.main3_safe`; a further
    witness, not a new capability: A2-drop.3a's rules typed it too); and
    what the deep `Ty.holdsDtor` adds (A2-drop.3b), an enum of type
    `sum (prod DT int) int`, whose destructor value is two levels down
    under a struct of no destructor type: `letv` refuses it
    (`A2.DtorWitness.main4_letv_refused`; A2-drop.3a's one-level rule did
    not see it), and `letd` binds it at its own destructor type with its
    glue (`A2.DtorWitness.main4_safe`); and a `Vec` of destructor values, a
    destructor value pushed into it, bound by `letd` at `vec DT`
    (`A2.DtorWitness.main5_safe`: the binder's premises are satisfiable and
    the program is memory safe; the theorem does not trace its run), which
    `letv` refuses (`A2.DtorWitness.main5_letv_refused`).

  What follows from **reading the rules**, not from a theorem: that these
  binders are all the places an owned destructor value comes to rest in a
  binding, so its destructor runs where the binding ends, as nurlc runs it
  (a check-out binding holds none, A2-drop.3d below). And what a call's
  result frame does: a panic in the callee after it has set its result
  (in nurlc, where `^ v` returns at once, the destructor of one of the
  callee's own bindings) stops at the frame with the slot owning, and the
  frame's panic step runs the result's destructor and frees it, or drains
  a `Vec` result, before the panic goes on (`scopeD_panic_runs_dtor`,
  `scopeD_panic_drains`); on the normal path the result has moved to the
  caller's binding by the frame's end, which runs nothing
  (`Step.scopeDMoved`). The runtime does not do this yet (Agora #612,
  below). And, for the drain, the run
  the steps above compose to: each element's frame runs its destructor at
  its end (`scopeD_end_runs_dtor`, of a value that is no node) before the
  `Vec`'s frame is at its end again, so the elements go in index order,
  each destructor once; a panic in an element's destructor frees that
  element (its frame is a plain `scope` by then) and comes back to the
  `Vec`'s frame through `scopeD_panic_drains`, so the elements after it
  still run theirs, and then the panic goes on. `memory_safe` and the
  leak theorems cover every such run; that it is this run is read off the
  steps, not a theorem of its own.
- A struct holding a destructor value is itself of a destructor type, and
  its destructor is its drop glue (Agora #616): a function of the program
  that takes the struct OWNED (`sink`) and takes it apart first thing, so
  each field is a binding of its own (`GlueOK`). A destructor that takes
  such a struct lent is refused for it (`A2.Dtor.struct_dtor_is_glue`):
  it could only free the fields with no code. In a typed program the
  glue's body is an `unpair` of its parameter whose every field of a type
  that holds a destructor value is handed to a `letd` first thing and
  assigned nothing (`A2.Dtor.glue_takes_apart`, from `unpair_typed`); the
  hand-overs come before anything that can panic, so each such field is
  in a destructor frame of its own, whose end runs its destructor and
  whose unwind runs it too (`scopeD_end_runs_dtor`,
  `scopeD_panic_runs_dtor`): a field's destructor that panics does not
  skip another field's. At the struct's frame's end the frame's step calls
  the glue, and the call moves the struct into it (the same step as for a
  lent destructor: the callee's parameter mode decides);
  `A2.DtorWitness.main7_safe` is a typed program with such a struct, its
  glue a function of the program checked by `FnOK`. That the fields'
  destructors run, each once, is read off these steps and theorems; it is
  no single theorem about a run. Taking such a struct apart anywhere else
  (`unpair`) is typed too, and is what its drop does: the fields go to
  their `letd`s. In this cut a struct with glue holds no views.
  A struct with a `% Drop` OF ITS OWN beside a field that holds a
  destructor value has two functions: its impl `i`, which takes it lent,
  and its glue, which takes it owned, rebinds it first thing under the
  fields' glue `h` (a `letd` at `Ty.dtor h t`), runs `i` on it lent, and
  sets its result (`ImplGlueOK`, `A2.Dtor.impl_glue_body`). Nothing can
  panic before the rebinding, and from there the struct is in `h`'s
  frame: the impl runs, then the frame's end takes the struct apart, a
  frame per destructor field; a panic in the impl unwinds to that frame,
  which does the same. That is nurlc's order, the impl and then the
  fields, and the journal's on a panic. A value changes its destructor
  type nowhere else: a `letd` that binds a value of another destructor
  type is of that shape, its scope starting with the impl's call
  (`A2.Dtor.letd_retype`, from `letd_binds`; that no other rule changes a
  whole value's destructor type is read off the rules). Code that writes
  it by hand runs the impl first, the value then in the fields' frame.
  What is NOT shown is "the impl exactly once": the impl is a function of
  the program, which code may call on a value of the fields' type as
  often as it likes, and a struct taken apart and built again is a new
  value of whichever destructor type it is bound at. `A2.DtorWitness.main8_safe` is a typed
  program with such a struct, its impl and its glue functions of the
  program checked by `FnOK`.
  An ENUM holding a destructor value is still a destructor type whose
  glue takes it lent: it matches on the tag and lends the payload to its
  destructor (`getl` / `getr` lend a payload through the type,
  `A2.DtorWitness.enum_lends`); the calculus checks it as it checks any
  destructor, and that it calls the payload's destructor is the
  elaboration's part (the open half of Agora #616).
- A field of a destructor value, or a payload of a destructor enum, is
  lent through the type, the destructor staying with the whole value.
  Taking one out is refused: `unpair` of a destructor value whose
  destructor takes it lent, or is the glue of a struct with a `% Drop` of
  its own (one whose destructor only takes it apart is taken apart,
  above), and `takel` /
  `taker` of a destructor enum (`A2.DtorWitness.enum_take_refused`), since
  the destructor would not run.
- A2-drop.3b: a `Vec` of destructor values is drained. `Ty.ok` admits
  `vec (dtor f u)` (`Ty.vecD`) as a binding's own type only, and refuses it
  as any part of another type: a field, a payload, an element, a view's
  element, a share's, a lock's or a cell's payload (each composite asks
  `!vecD` of its parts, and `RhsT.pair` / `inl` / `inr` of what moves in;
  a share's payload owns no destructor value at all, 3d below). Its binder
  is `letd x f r s`,
  with `f` the elements' destructor and `u` holding no views (`LetdTy`;
  `letv` refuses the type, it holds a destructor value), so a call's
  result and a `sink` parameter of that type are handed on first thing as
  a destructor value is (`movedFirst`: into a `letd`, by `assign y
  (.var w)` into another binding of the same type, whose own binder
  answers for it, or by `unpair`), and an `inout` parameter of it is assigned nothing. (No
  struct has a field of that type, so `unpair` yields none.) Its frame is `scopeD x f`, the same
  run-time form: what `x` owns at the frame's end says which frame it is,
  a struct or an enum (the destructor runs on it) or a `Vec`'s node (the
  drain, above). Elements go in by `vec_push` and out by `vec_pop` /
  `vec_remove x 0`, each popped one an owned destructor value, handed to a
  `letd` of its own. `memory_safe`, `no_leak_end` and `no_leak_panic` cover
  the drain's steps. Every other `Vec` has destructor-free elements at any
  depth (`A2.Dtor.vecs_dtor_free`; a top one's elements are destructor-free
  or of a destructor type, `A2.Dtor.vec_elems_dtor_free`,
  `A2.Dtor.new_dtor_free`), so `free`, a truncation, an element set and
  `withElem` release or check out no destructor value, except a share's
  payload, which owns none either (3d, below).
  (On an empty `Vec`, `vec_pop` and `vec_remove` return `None` in nurlc; the
  calculus's `pop` / `popFront` panic there instead, an unwrap: a program
  that matches the option is the same program with the `None` arm taken
  before the call. The drain pops only a `Vec` that has an element.)
- A2-drop.3c: no closure's or trait object's environment holds a
  destructor value. A typed literal's environment type holds none
  (`Cross.Fits`, of every class; `A2.Dtor.pack_env_dtor_free`), and in a
  running configuration no package does, however deep it lies: in an
  owner's tree (a field, an element, another package's environment:
  `A2.Dtor.pkgs_env_dtor_free`) or in a block's payload
  (`A2.Dtor.blk_pkgs_env_dtor_free`), both over
  `A2.WFv.pkg_env_dtor_free`. A share an environment holds is of a block
  whose payload owns none either (3d). This is a refusal, not the model
  of nurlc's environment drop glue (the stricter-than-nurlc list below;
  `A2/DROP_DESIGN.md` staging item 3 has the design that lifts it).
- `Ty.holdsDtor` is deep (A2-drop.3b): a struct or an enum one field or
  payload of which holds a destructor value holds one
  (`A2.Dtor.holdsDtor_deep`, the definition unfolded). So a typed `letv`
  binds no owned value whose type holds one at any depth
  (`A2.Dtor.letv_owned_dtor_free`), and a struct or an enum holding one
  two levels down is bound by `letd` with its glue
  (`A2.DtorWitness.main4_safe`).
- A2-drop.3d: no block's payload owns a destructor value. The invariant
  carries it for every block in memory, whatever holds its shares (a
  binding, a closure's environment, another block's payload):
  `A2.Dtor.blocks_dtor_free` (`MInv.blocks`; a start built by hand must
  satisfy it too, `GlobsOK`). So the sweep that frees a block when its
  last share goes, which runs no code, releases no destructor value. What
  keeps it: `Ty.ok` asks it of an `Arc`'s, a lock's and a cell's payload
  type (so of a channel's queue and a read guard's view), and `arc_new`, a
  lock's and a library handle's constructor ask it of what moves in
  (`A2.Dtor.share_new_dtor_free`). Of types: the payload type of every
  share in a binding's type owns none (`A2.Dtor.shares_dtor_free`, over
  `A2.Dtor.ok_payloads_free`), so a check-out binding (`withLock`,
  `withCell`), whose type is the lock's payload's, holds none, and an
  `assign` to it drops no destructor value. This is a refusal, not the
  model of nurlc's drop of a block's payload (the stricter-than-nurlc list
  below; `A2/DROP_DESIGN.md` staging item 4).
- So a binding's end, a drained `Vec`'s, and a call's result frame run
  the value's own, outermost destructor, and everywhere else that could
  hold a destructor value is refused (the list below). That these are all
  the places is read off the rules, not a single theorem (above). What the
  calculus does not show is the destructors inside an ENUM (Agora #616's
  open half; a struct's fields are shown, above):
  - an enum that holds destructor values is a destructor type whose
    destructor is its glue, which takes it lent, and that the glue runs
    the payload's destructor is the elaboration's part, not checked: a
    glue that calls none types (the witnesses' `ofn` and `gfn` are such),
    and the frame then frees the payload running nothing;
  - a panic in that glue ends it, and the frame frees the payload with no
    destructor.
  The model that shows it is the struct's: glue that takes the enum owned
  and takes the payload out (`takel` / `taker`, to a `letd`). See Agora
  #542–#544, #611, #616.

The rules are stricter than nurlc's in these places:
- for a binding of a type whose destructor may read a view:
  - nurlc lets it gain views of older bindings;
  - nurlc lets it be an `inout` argument, whose callee may give it views
    only of what the caller passed in: a view of the callee's own local is
    refused where it is given, even for a moment (#284). One shape is
    still open there: a callee that keeps a view parameter in a holder
    other than its first argument ties it to the first one (#370);
- for any binding that may own a value holding a destructor (A2-drop.3a),
  `= x v` is refused (`Stmt.assigns`), because the calculus's `assign`
  drops the old value without running code. A program moves the old value
  to a `letd`, whose scope runs the destructor at once, and binds the new
  one with `letd`. A function's owned result of such a type is set at
  most once on any path, and is of a destructor type itself that holds no
  views and no closure (its frame runs the destructor on a panic in the
  callee), or a `Vec` of such values: nurlc also returns a plain struct,
  enum or option that holds a `% Drop` value, and a `% Drop` value that
  holds views; here a struct or an enum holding one is its own destructor
  type, with its glue.
- for a struct whose drop takes it apart (Agora #616): its glue does
  nothing but hand its fields on (`Stmt.pureGlue`); it holds no views, so
  a struct with a destructor field and a view field is refused
  altogether; and a struct of three or more fields is nested pairs here,
  each inner pair that holds a destructor value with glue of its own. A
  struct with a `% Drop` of its own beside a destructor field is not
  taken apart by hand (`unpair`): that would skip its impl.
- for a `Vec` of destructor values (A2-drop.3b), which is typed as a
  binding's own type, drained at the binding's end (above). nurlc types the
  rest too, and drops a `Vec`'s elements wherever the `Vec` is dropped, in
  index order, each running its destructor. Refused here:
  - elements that hold views (a `Vec` of `% Drop` structs with a view
    field): a binding that runs a destructor gains no view (the first item
    of this list), so nothing could be pushed into it;
  - the `Vec` as a part of another type: a struct or an enum with a
    `Vec D` field or payload, a `Vec (Vec D)`, a channel of `D`
    (`Channel s` is a lock of its queue, a `Vec s`, and its closed flag),
    `Locked (Vec D)`, `Arc (Vec D)`, a cell of a `Vec D`. A struct's
    glue hands a field to a `letd`, which binds no `Vec` inside a struct
    yet (`RhsT.pair` refuses the field), and a block's payload is
    swept with no code;
  - `vec_set` over an element, and handing an element to a callee that
    changes it (`withElem`). (`vec_free`, `vec_clear` and `vec_truncate`
    of such a `Vec` are code the calculus types, each element's destructor
    running: `x` moved into a destructor binding that ends at once, whose
    frame drains it (`A2.Dtor.vecFreeD_typed`, leaving the context
    `vec_free`'s rule leaves); a loop moving element 0 out to a destructor
    binding (`vecClearD_typed`, in index order as nurlc's); a loop of
    `vec_pop`s into one (`vecTruncD_typed`: the elements go last first,
    where nurlc's `vec_truncate` drops them in index order, so the order
    of the destructors' effects differs). The loops are typed in a context
    with no live borrow of the `Vec`'s elements, which is what a
    truncation leaves; `A2.DtorWitness.main6_typed` types a program with
    all three. That each element's destructor runs is read off the steps
    of `letd`'s frame, as for the drain; it is no theorem about these
    forms. Two differences from nurlc's run, beside the order: nurlc cuts
    the length before it drops, so a destructor that reached the `Vec`
    would see it short (none does here: the `Vec` is not lent while it
    drops); and a panic in an element's destructor leaves the loop with
    the elements not yet dropped still in the `Vec`, which its binding's
    end drains, where nurlc, the length already cut, runs no destructor
    for them (the family of Agora #608).)
- for a closure or a trait object whose environment would hold a
  destructor value (A2-drop.3c): a closure that captures a `% Drop` value
  by value (or a struct, an enum, an option or a `Vec` holding one), and a
  trait object boxing a value of a `% Drop` type, are refused
  (`Cross.Fits`). nurlc types them, and its environment drop glue runs the
  captures' destructors when the package is dropped. A program keeps the
  `% Drop` value in a binding of its own and lets the closure borrow it
  (a capture by name: the closure is then of class `any`, and crosses to
  no thread and into no share); a trait object has no such route.
- for a share whose payload would own a destructor value (A2-drop.3d): an
  `Arc`, a `Locked` / `RwLocked` / `Mutex`, a channel or a library handle
  of a `% Drop` type (or of a struct, an enum, an option or a `Vec` holding
  one) is refused (`Ty.ok`). nurlc types them, and the thread that drops
  the last share runs the payload's destructor. A program that shares a
  resource keeps the `% Drop` value in one thread's binding and shares
  what the others need of it.
- for a spawned function's parameter of a type that holds a destructor
  value (`SpawnOK`, since A2-drop.3a): refused. nurlc moves a `% Drop`
  value to a new thread, which runs its destructor there.
- for a destructor value whose destructor takes it lent (A2-drop.3a),
  taking it apart is refused: a
  field written in place (`= . x f v`, which the calculus has as `unpair`
  and `assign`), `unpair`, and taking a payload out of a destructor enum.
  So an `inout` parameter of a destructor type is neither assigned nor
  taken apart in its callee (its fields and payloads are lent). A struct whose destructor is its glue is taken
  apart (Agora #616: `unpair`, its destructor fields going to their
  `letd`s), as Rust lets a program move out of a struct that has no
  `Drop` impl of its own; one with a destructor that takes it lent, or
  with an impl beside its glue, is not.

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

One place where the runtime does not yet do what the calculus says
(Agora #608): **a `Vec` element's destructor that panics.** The calculus
frees that element and goes on with the elements after it, each running
its destructor, then frees the `Vec` and raises again
(`Step.scopeDPDrain`). The runtime's element loop (`nurl__vec_drop_elems`)
is left by the panic: the elements after it run no destructor, and they,
the buffer and the `Vec` leak. On the normal path, and for a panic
anywhere but inside an element's destructor, the runtime drops the
elements in index order, each once, as the calculus does.

A second one (Agora #612): **a function's `% Drop` result, when one of
the function's own bindings' destructors panics at its exit.** The
calculus stops the panic at the result's frame, runs the result's
destructor, frees it, and goes on (`Step.scopeDP` on the call's result
frame). The runtime holds the result in no journal entry while the
callee's bindings are dropped: its destructor does not run and it leaks.

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
