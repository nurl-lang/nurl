# The claim

> **Status: A1, A2 and A3 are proven** (`A1.memory_safe`, `A2.memory_safe`,
> `A2.no_leak_end`, `A2.no_leak_panic`, `A3.claim_full`, `A3.claim_made_full`;
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
  `A3.claim_full : A3.ClaimFull` and `A3.claim_made_full` (`A3/ClaimFull.lean`):
  `A3.claim` (`A3/Claim.lean`) and `A3.claim_made` (`A3/Make.lean`) — memory
  safety, race freedom and no leak — together with the adequacy of that race
  freedom for cells (`A3.CellAdequate`, A3.5 below: every check-out of a
  cell's block is a step on the cell, so every cell race is a `Race`), on the
  same premises. `A3/DESIGN.md` gives the semantics and the milestones.
  In Lean:

  ```lean
  def ClaimFull : Prop :=
    ∀ (P : Prog) (spawn : Nat → Bool) (G : Globs) (s : Stmt) (Δ : Ctx) (nv : Nat),
      ProgOK P → ProgCodes P → SpawnOK P spawn → GlobsOK P G →
      StmtT P (fun _ => none) [] s Δ → s.src = true → s.codesOK P → (∀ v ∈ s.vars, v < nv) →
      MemorySafe P spawn (Cfg.start G s nv) ∧ RaceFree P spawn (Cfg.start G s nv) ∧
        NoLeak P spawn (Cfg.start G s nv) ∧ CellAdequate P spawn (Cfg.start G s nv)

  def CellAdequate (P : Prog) (spawn : Nat → Bool) (C0 : Cfg) : Prop :=
    ∀ C, Reach P spawn C0 C → ∀ (i : Nat) (t : Thread) (K : Stmt → Stmt) (k : Nat) (u : Ty) (x : Var) (b : Stmt),
      C.ths[i]? = some t → Redex t.s K (.scopeL k u x b) → C.Holds (.cell k) → CellOp t k
  ```
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
      of every step frees the rest, over all threads (Agora #610 / #755:
      but an orphan whose payload awaits its destructor, which it marks
      for the stepping thread to reap, *Destructors* below).
    - **Threads.** The address space is each thread's part plus a
      shared, read-only payload part. Two threads meet on a payload only
      by reading it. The sweep's frees are writes to a block no thread
      reaches; a reaped payload moves to the reaping thread's part.
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
    time changes. (Mutual exclusion as a theorem, `A3.reach_lock_excl`,
    Agora #808, for every payload type: at most one check-out frame of a
    lock block is out at a time. Agora #810: a lock block whose payload is
    out is either *checked out* by a `withLock` or *taken* by
    `locked_take` (`Mem.taken`, the runtime's lock word `HELD` or
    `TAKEN`), and `locked_restore` fills only a taken block; on a
    checked-out one it panics, as nurlc's does — "the value was not
    taken".)
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
      (`Rhs.lockTake`, `Rhs.lockRestore`; restoring into a block whose
      value is in, or is checked out by a `withLock`, panics, as the
      runtime does: Agora #810, `A3.lockRestore_present`,
      `A3.lockRestore_checked_out`). The take leaves the block empty and
      marks it taken (`Mem.taken`), so a restore drops nothing (h267). The runtime's `mem_take` moves the
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
      sender's part, or drops it when the channel is closed (answer 0):
      since Agora #755 it moves it into a fresh lock block of the element
      type that no share names (`EvalR.chanSendClosed`;
      `A3.ChanDtorWitness.closed_send_parks` proves the value lands
      there). The marking sweep that ends the step is then to free it (a
      value that owns no destructor value) or mark it `dead` for the
      sending thread to reap (a destructor value: its destructor runs on
      the sender, as nurlc's `chan_send` drops its unqueued
      inferred-`sink` parameter before it returns). Since Agora #805 that
      is proved for a destructor element: every share in a configuration
      a typed start reaches names a key below `nid` (`A3.reach_keys`,
      kept by every step: `A3.Step.keys`, `A3.TStep.keys`), so nothing
      refers to the fresh block, and the step's marking sweep marks it and
      the sending thread's reaps bind the value in a fresh slot of its own,
      in that configuration step, whether a `letv` or an `assign` binds the
      answer (`A3.TStep.closed_send_reaps`, `closed_send_reaps_assign`,
      `A3.reach_closed_send_reaps`, `reach_closed_send_reaps_assign`). A typed witness closes a channel, then
      sends a destructor value (`A3.ChanDtorWitness.mainC`,
      `A3.chanClosed_claim`, `A3.chanClosed_reaps`).
      `chan_recv` moves the front out to the receiver, owned (an option:
      none when closed and empty), and waits while the queue is empty and
      open (`RBlocked`). `chan_try_recv` answers none at once, and
      `chan_close` sets the flag. Each is one step: the queue's ends are
      the runtime mutex's (trusted base). Values in a queue are the
      block's tree, in no thread's part, so they race with nothing, and
      the sweep frees what is left in a queue with its block (`no_leak`),
      or (Agora #755, a channel of destructor values) the thread that drops
      the last share reaps the block and drains the queue (*Destructors*).
    - **Not typed yet:** a channel of values that hold a view (shares,
      library handles under the crossing check, and `send` closures are
      typed since A3.2's and A3.5's second cuts); a channel of destructor
      values that hold a share, or of values holding one in a field of a
      type of no destructor of its own (a channel of destructor values, or
      of drained `Vec`s of them, is typed since Agora #755: its state is
      under its glue, see *Destructors*); `chan_len`,
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
    - **Agora #804: `RwLocked D`.** A read guard of a payload that is a
      destructor value (or holds one) is typed (`RhsT.rwRead` /
      `rwTryRead` ask only `hasCell = false`;
      `A3.RwDtorWitness.rwRead_dtor_typed`), as nurlc lends the payload in
      place under the shared lock. The view owns nothing (`Blk.tree_view`)
      and its payload is its lock block's (`ViewsAt`): no sweep frees and
      no reap drops anything of a view, which is never an orphan to be nor
      marked `dead` (`A2.Dtor.blocks_dtor_free`,
      `A3.RwDtorWitness.view_no_dtor`). While a guard lives, its view keeps
      the lock block reached (`view_keeps_lock`), so the lock block is not
      an orphan to be (`view_lock_not_cand`). When the lock's last share
      goes after every guard, and every guard's view is gone with it (the
      sweep that ends a guard's drop removes an unreached view), so that no
      slot's value and no block's payload refers to the lock block, the
      sweep marks the lock block `dead` and the dropping thread's next step
      is the reap, whose frame runs the destructor
      (`A3.LockDtorWitness.last_drop_reaps`, for a lock block of `DT`; it
      takes the absence of a view as a hypothesis). The other order, a
      guard dropped after the lock's last share and the lock block reaped
      by that guard's thread, follows from the marking sweep but is not yet
      a lemma (Agora #831). The
      guard's type `arc (prod (lk D) D)` is admitted by `Ty.ok` through
      `Ty.rview` (exactly `prod (lk u) u` with `u.lkPay` and no cell
      share); no `arc` block is of that type (`A2.Dtor.arc_blocks_dtor`).
      Witness: `A3.RwDtorWitness.main` (an `RwLocked` of a destructor
      value, made, read through a guard, dropped: `main_typed`,
      `main_safe`, `main_no_leak`, `main_no_leak_panic`;
      `A3.rwDtor_claim`: `A3.claim` over it).
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
      held (`Step.scopeLFail`), as `locked_with` does (Agora #803: a
      destructor payload that fails it goes to a destructor frame on the
      unwinding, `Step.scopeLPD`, not the code-less drop: a case nurlc
      refuses statically, the check failing there only through a read
      guard, Agora #837). A lock is Sync
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
      owner's share at a check-out (`CellOp`). A thread inside a check-out
      of a cell's block does hold one, and the claim says so
      (`A3.CellAdequate`, a conjunct of `A3.ClaimFull`; Agora #808 / #815 /
      #818, `A3.reach_frame_cell_owner`, `A3.reach_frame_cellOp`): the
      check-out's root share stays in its slot for the whole body, and a
      borrowed root is a borrowed parameter, live, whose caller's owner is
      in the store, `MInv.cell_owned`; and the root is a cell share, since
      no block is named by both lock and cell shares (Agora #815,
      `A3.reach_shareKind`: cells and locks are both lock blocks, but a
      kind per key agrees with every share of the configuration,
      `A3.CKinds`, in every slot, payload and global, kept by every step:
      `cellNew` and `lockNew` take a fresh key above every share,
      `A3.CKeys`, and every other share is a copy of one of the same
      kind). That holds from a start whose globals keep the kinds apart,
      which `GlobsOK` asks (`GlobsOK.kinds`, A3.6 below) and the make
      phase leaves (`make_ok`, `A3.reach_shareKind_made`).
    - **Not typed yet:** a store of a borrowed handle into an owner (the
      runtime's implicit copy); a handle changed through a borrow that is
      no root; `% Sync` / `% NotSend` assertions on a program's own types;
      `locked_take` through a cell share; a failed give-back
      frees the value where the runtime keeps it in the held lock (no one
      reaches it either way; Agora #803: a destructor value's goes to a
      destructor frame, `Step.scopeLPD`, on a case nurlc refuses
      statically);
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
      Such a package is at most `send`, or of the dropping class, which
      crosses nowhere (Agora #609) (`callcE_not_sync`,
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
    - **Not proven here:** phase D must show the runtime's reference
      count of a handle's block equals the model's owners. (That a thread
      inside a check-out of a cell's block holds an owner's share of the
      cell is proved, Agora #808 / #815: `A3.reach_frame_cell_owner`.)
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
      the earlier statement. Since Agora #815 the premise also asks that
      the start keep lock and cell shares apart (`GlobsOK.kinds`,
      `GlobsKinds`: a kind per key that every share in a block's payload
      or a global agrees with, so no key is named by both a lock share and
      a cell share). The typing cannot see it, since both shares name a
      lock block of their payload type, and without it the premise admitted
      a start that names block 0 by a global `Locked int` and by a cell
      share in another global lock's payload (`A3.mixG`: it satisfies
      `GlobsTyped`, every condition `GlobsOK` asked before, but not
      `ShareKind`, `A3.mix_globsTyped`, `A3.mix_not_shareKind`; `GlobsOK`
      refuses it, `A3.mix_not_globsOK`). There a check-out through the lock
      share changes the cell's state as no `CellOp`, so a race with a
      `withCell`, which the runtime runs with no lock, was not a `Race`.
      `A3.claim`'s text is unchanged; only `GlobsOK` asks more. The claim
      includes the cell adequacy (Agora #818): `A3.ClaimFull`, which
      `A3.claim_full` proves on the same premises, concludes, beside
      `MemorySafe`, `RaceFree` and `NoLeak`, `A3.CellAdequate` — in every
      reached configuration every check-out of a cell's block on a thread
      is a `CellOp` of that thread, so the `RaceFree` it concludes sees
      every race on a cell (from `A3.reach_frame_cellOp`, with
      `A3.reach_shareKind`). ("A cell's block" is a definition: a block
      some value of the configuration names by a cell share,
      `Cfg.Holds (.cell k)`; blocks carry no mark of their own.)
      The sweep keeps what the globals reach, and
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
      `made_ok`), the kinds field too (each make's run keeps a kind per
      key, `A3.reach_kinds`, and its result is one of its values), so the
      premise is derived, not assumed, and `A3.claim_made`'s statement is
      unchanged by Agora #815. `A3.claim_made_full` (Agora #818) adds the
      cell adequacy (`A3.CellAdequate`) on every make's run
      (`A3.made_safe_full`) and on the program's; a make that
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
- A view of an owner kept across the owner's move into a struct field or
  literal, where nurlc hands the view to the field path (Agora #799); A2's
  move ends the owner's views (`RhsT.moveOwn`).

## Destructors, and a panic while a panic unwinds

A destructor written by the program (`% Drop T { @ drop … }`,
docs/MEMORY.md §7.6) is inside the calculus for every type, views included
(A2-drop.1 and A2-drop.2, `A2/DROP_DESIGN.md`).
- A binding with a destructor (`StmtT.letd`) is scoped by `scopeD`.
- At its end, while it still owns its value, the destructor runs as a call
  of the program's function on the binding (`Step.scopeDEnd`): lent to a
  destructor that takes it lent, after which the scope frees the tree; or
  moved into a struct's glue, which takes it apart (Agora #616, below).
- A panic that unwinds to the frame stops there. The frame is left at its
  end, followed by the panic raised again (`Step.scopeDP`); its end runs
  the destructor and frees the binding (`Step.scopeDEnd`). The frame is
  gone once its end is taken, so a panic inside the destructor does not
  run it again, and `scope x` still frees the fields. (Agora #790: what
  the unwinding orphaned is reaped at that end, inside the frame, first;
  `A2/DROP_DESIGN.md`, 3d.)
- A destructor of a type that holds views reads them, so what they point
  into outlives the binding while it may own its value (#224's rule,
  `DtorSafe`). No rule ends such a view on any path, the panic path
  included. A binding `letd` made gains no view: it is assigned nothing,
  pushed no view it does not record already (Agora #782: its `letd` may
  record views of older bindings up front, `HeldUp`, so a drained `Vec`
  of such values may take elements that view them), and is no `inout`
  argument.
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
    (A2-drop.3b) a `Vec` of such values, whose elements may hold views
    (Agora #782; the binding is then armed with them) (`A2.Dtor.letd_binds`); `f` is the destructor of `Ty.dtor f t`
    (`DropFnOK`: one that takes it lent, or a struct's glue, Agora #616),
    and the binding is assigned nothing in its scope (`A2.Dtor.letd_dtor`);
  - at the end of a typed `scopeD x f` frame whose `x` still owns its
    value, a struct or an enum, in a store with no orphan (every store a run
    reaches between its steps, `A2.no_orphan`; with one, `Step.reap` is a
    step too), the frame's only step calls `f` on `x` (lent,
    the tree freed after; or moved into a struct's glue) (`A2.Dtor.scopeD_end_runs_dtor`); a panic out
    of its body with `x` owning runs it too: the frame is left at its end,
    the panic after it, and from the store the marking sweep leaves after
    that step, with no orphan, the only step is that end's call
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
  frame, left at its end by its panic step, runs the result's destructor
  and frees it, or drains
  a `Vec` result, before the panic goes on (`scopeD_panic_runs_dtor`,
  `scopeD_panic_drains`); on the normal path the result has moved to the
  caller's binding by the frame's end, which runs nothing
  (`Step.scopeDMoved`). The runtime does this since Agora #612 (below,
  with the one difference, the order). And, for the drain, the run
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
  their `letd`s. Such a struct may hold views (Agora #633): its `letd`
  arms it with what it views, of older bindings. At its frame's end it
  moves into the glue as any `sink` argument does, holding them; the
  call's rule asks that it reach nothing of itself, which holds because
  a `letd` binding views nothing of its own (`DSelf`: its scope's end asks
  it, its frame keeps it, `StmtT.scopeD`; `A2.glueCall_typed`). The glue
  sees its parameter as viewing nothing, as any callee sees a parameter.
  `A2.DtorWitness.main10_safe` is a typed program with a struct of a
  destructor field and a view field of an older binding (nurlc's
  `: P { Conn c s name }`), its glue checked by `FnOK`. A struct with an
  impl beside its glue may hold views too (`ImplGlueOK`); no witness
  program is mechanized for that case.
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
  An ENUM holding a destructor value (an option of a `% Drop` value) is a
  destructor type too, and its destructor is its glue (Agora #632,
  `EnumGlueOK`, or after an impl of its own `ImplGlueOK`, below; a
  destructor that takes it lent is refused for it,
  `A2.Dtor.enum_dtor_is_glue`): a function that takes the enum owned and
  matches on its tag; in the arm of a variant whose payload type holds a
  destructor value the payload moves out to a `letd` first thing
  (`takel` / `taker`), whose frame runs its destructor at its end and on
  a panic, and the arms do nothing else (`A2.Dtor.enum_glue_body`). The
  other variant's payload holds no destructor value; its arm takes
  nothing and the enum is freed where the glue's parameter ends. The
  witnesses' options (`main3_safe`, `main4_safe`) are dropped by such
  glue, functions of the program checked by `FnOK`. As for a struct, that
  the payload's destructor runs is read off these steps and theorems.
  Which arm runs is the tag's test at run time: the typing does not tie
  the arm to the variant (an `ite` on `isl`), so "the arm that takes is
  the arm of the variant that is there" is the step's, not a theorem.
  An enum with a `% Drop` of its own beside such a payload has the
  struct's two functions (`ImplGlueOK` is over a struct or an enum): its
  glue rebinds it under the payload's glue and runs the impl on it lent;
  no witness program is mechanized for the enum case. In this cut an enum
  with glue holds no views.
  nurlc writes that glue since Agora #641: `drop__<E>` is the impl and
  `drop_glue__<E>` the payloads of the variant that is there, run after
  it, wherever the enum lives. Before, a binding of such an enum ran the
  impl and never dropped the payloads, and a `Vec` element, a struct
  field or a temporary a `??` matched never ran the impl.
- A field of a destructor value, or a payload of a destructor enum, is
  lent through the type, the destructor staying with the whole value.
  Taking one out is refused: `unpair` of a destructor value whose
  destructor takes it lent, or is the glue of a struct with a `% Drop` of
  its own (one whose destructor only takes it apart is taken apart,
  above), and `takel` /
  `taker` of a payload that holds no destructor value out of a destructor
  enum (`A2.DtorWitness.enum_take_refused`), since the destructor would
  not run. A payload that holds one is taken out only where the enum's
  destructor is its glue: the statements that can bind it, `letd` and
  `assign` (`letv` refuses an owned value that holds a destructor value),
  ask it of the enum in the context they are typed in
  (`A2.Dtor.take_is_glue`, `assign_take_is_glue`). That is then what the
  enum's drop does.
  nurlc (Agora #641): a `??` arm takes a payload out of an enum the
  function owns only where the enum's destructor is its glue
  (`mem_enum_take`: a binding that owns on every path, a `sink`
  parameter, the match's temporary). An enum with a `% Drop` of its own,
  any enum held in a field of a local struct, and an enum bound from a
  call that answers per call keep their payloads: the arm is lent them,
  and one handed back out of the function that drops the enum is a copy
  the caller owns where its type can be copied, and refused where it
  cannot (`__payload_lent_of_frame`).
- A2-drop.3b: a `Vec` of destructor values is drained. `Ty.ok` admits
  `vec (dtor f u)` (`Ty.vecD`) as a binding's own type, and (Agora #607)
  as a struct's field or an enum's payload: the struct's or the enum's
  glue hands the field to a `letd` at the `Vec`'s own type, whose frame
  drains it (`A2.DtorWitness.main9_safe`: a `Vec` of destructor values
  moved into a struct, the struct's glue a function of the program
  checked by `FnOK`), and (Agora #607) as another such `Vec`'s element, at
  any depth (`Ty.nest`, `Ty.dnest`; witness `A2.DtorWitness.main11_safe`),
  and a view's element (a view owns nothing), and (Agora #755) an `Arc`'s
  payload, which the reap of the orphaned block binds at its own type in a
  destructor frame that drains it (3d below), and (Agora #755's last cut)
  a lock's or a cell's payload (`Ty.lkPay`: one that holds no cell share,
  Agora #803; before, no share at all; the check-out binds it at its own type and gives it back, and the reap of the
  orphaned block drains it, `Locked (Vec D)` below); every `Vec` in a binding's type
  has elements that own no destructor value or are of a destructor type or
  such `Vec`s in turn (`A2.Dtor.vecs_dtor_free`). Its binder
  is `letd x f r s`,
  with `f` the elements' destructor (`LetdTy`; Agora #782: `u` may hold
  views, of bindings older than the `Vec`'s, which its `letd` records up
  front, `HeldUp`: the binding is armed, `Ty.dtorViews`, a push into it
  adds no view it does not record, `StmtT.push`, and the drain revives it
  still armed, `Entry.reviveD`, each element moved out to a `letd` armed
  with those views; witness `A2.DtorWitness.main14_safe` /
  `main14_no_leak`;
  `letv` refuses the type, it holds a destructor value), so a call's
  result and a `sink` parameter of that type are handed on first thing as
  a destructor value is (`movedFirst`: into a `letd`, by `assign y
  (.var w)` into another binding of the same type, whose own binder
  answers for it, or by `unpair`), and an `inout` parameter of it is assigned nothing. (A
  struct's field of that type, which `unpair` yields in the struct's glue,
  is handed to a `letd` in the same way.) Its frame is `scopeD x f`, the same
  run-time form: what `x` owns at the frame's end says which frame it is,
  a struct or an enum (the destructor runs on it) or a `Vec`'s node (the
  drain, above). Elements go in by `vec_push` and out by `vec_pop` /
  `vec_remove x 0`, each popped one an owned destructor value (or, Agora
  #607, an owned `Vec` of them in a `Vec (Vec D)`), handed to a
  `letd` of its own. `memory_safe`, `no_leak_end` and `no_leak_panic` cover
  the drain's steps. Every `Vec` in a binding's type has elements that
  own no destructor value or are of a destructor type or drained `Vec`s
  in turn (`Ty.dnest`; `A2.Dtor.vecs_dtor_free`, `vec_elems_dtor_free`, `new_dtor_free`), and
  the rules that release elements with no code ask the first of their
  own `Vec` (`free`, a truncation, an element set and `withElem` ask
  `dtorFree`), so they release or check out no destructor value; a
  lock's or a cell's payload owns none or (Agora #755) is a destructor
  value given back by its check-out and reaped with its block, and an
  `Arc`'s destructor value, or (Agora #755) its drained `Vec` of them, is
  handed to a frame of its own (3d, below).
  (On an empty `Vec`, `vec_pop` and `vec_remove` return `None` in nurlc; the
  calculus's `pop` / `remove` panic there instead, an unwrap: a program
  that matches the option is the same program with the `None` arm taken
  before the call. The drain pops only a `Vec` that has an element.)
- A2-drop.3c: the environment of a closure or a trait object of a class
  that does not drop (every class but `dropd`, next item) holds no
  destructor value. A typed literal's environment type holds none
  (`Cross.Fits`, of every class that crosses or views;
  `A2.Dtor.pack_env_dtor_free`), and in a running configuration no
  package does, however deep it lies in a tree whose type has no closure
  of the dropping class in it (`Ty.noDropd`): in an owner's tree (a field, an element, another
  package's environment: `A2.Dtor.pkgs_env_dtor_free`) or in a block's
  payload (`A2.Dtor.blk_pkgs_env_dtor_free`), both over
  `A2.WFv.pkg_env_dtor_free`. A share an environment holds is of a block
  whose payload owns none either (3d).
- Agora #609: a closure whose environment holds destructor values is of
  the class `dropd`, and is a destructor value itself (`Ty.holdsDtor`): no
  rule that releases with no code takes it, `letv` binds none, and `letd`
  binds it at `Ty.dtor f (fn ms dropd)` where `f` is its glue
  (`ClosureGlueOK`; a destructor that takes it lent is refused,
  `A2.Dtor.closure_dtor_is_glue`). The glue takes the closure owned and
  calls its drop method first thing, a method whose interface takes the
  receiver owned (`StmtT.callcE`'s second case). That call hands the
  environment to the method's code for good (`Step.callcD`; which of the
  two hand-overs a call takes is the code's first parameter's mode, so a
  typed configuration takes the one its rule typed: `handCaseD`). The
  code takes the environment as its own `sink` parameter, and where the
  environment holds a destructor value it hands it on first thing (to a
  `letd`, or taken apart) or is itself the glue of the environment's
  type (`A2.Dtor.drop_method_code`, from `FnOK`'s `DtorParamsOK`). As
  for a struct's and an enum's glue this is a shape the typing forces
  plus the frames' steps, not a theorem about a run. (Between the
  hand-over's step and the code's first statement the environment sits
  in a plain binding and then in the code's parameter; no step there
  can panic: a call's entry has no panic rule and the code moves it
  first.) A whole program with such a closure, made and bound, is typed
  and safe (`A2.ClosureDropWitness.main_safe`; there the drop method's
  interface is the glue's own signature); `letv` of the literal is
  refused (`main_letv_refused`). The rule's second case is not the
  glue's alone: any owner of a live closure of this class that holds
  nothing may call such a method, a consuming call, after which the
  binding is moved out and its frame runs nothing. Limits of this cut:
  the class holds no views and no cell shares and crosses nowhere (no
  subsumption reaches it, `Cross.Le` asks the same `drops`; what crosses
  asks a type that owns no destructor value); no trait's object is of it
  (`TraitAt` asks receivers that are not `sink`, at a bound's class).
  Such a closure is CALLED by the lending rule (Agora #651), through its
  `letd` binding or any borrow of the destructor type: `StmtT.callc`
  reads the closure type through the receiver's destructor type
  (`Ec.ty.undtor = .fn ms q`; well-formed, that is one destructor type
  over a closure of this class, `A2.ok_undtor_fn`), and the
  method's interface takes the receiver at the binding's type; the code
  is lent the environment as any closure's is, and the binding's frame
  drops it after. A program that makes, calls and drops one is typed
  and safe (`A2.ClosureDropWitness.main2_typed`, `main2_safe`; its
  method reads nothing, and there is no run theorem). No trait's method
  is called through such a receiver (`StmtT.callc_bound`). A method that CHANGES the environment (an `inout` receiver,
  the hand-over and back) is not typed for this class yet: the package
  rebuilt after the call would be assigned over a destructor binding.
- `Ty.holdsDtor` is deep (A2-drop.3b): a struct or an enum one field or
  payload of which holds a destructor value holds one
  (`A2.Dtor.holdsDtor_deep`, the definition unfolded). So a typed `letv`
  binds no owned value whose type holds one at any depth
  (`A2.Dtor.letv_owned_dtor_free`), and a struct or an enum holding one
  two levels down is bound by `letd` with its glue
  (`A2.DtorWitness.main4_safe`).
- A2-drop.3d: a view owns nothing; its payload is its lock block's (Agora
  #804: read in place, of a read guard's view type `prod (lk u) u`,
  `Ty.rview`, or owning no destructor value; a view is never an orphan to
  be nor marked `dead`, so no destructor runs from it); a lock block's
  owns none or (Agora #755, `Locked D`) is one at its top, or (`Locked
  (Vec D)`) a drained `Vec` of them, that holds no cell share (`Ty.lkPay`;
  Agora #803: it may hold `arc` and lock shares); an `Arc`'s may be one at its top (Agora #610), or (Agora #755) a
  drained `Vec` of them at any depth (`Ty.nest n (.dtor f u)`, `Ty.dnest`),
  and is then of such a type over a destructor type that holds no closure. The invariant carries it for every
  block in memory, whatever holds its shares (a binding, a closure's
  environment, another block's payload): `A2.Dtor.blocks_dtor_free`
  (`MInv.blocks`, `Blk.DtorOK`; a start built by hand must satisfy it too,
  `GlobsOK`, whose blocks of destructor values, of any kind, name
  destructors the program checked, `GlobsOK.dtors`). What keeps it: `Ty.ok` asks a lock's
  and a cell's payload type to own none or (Agora #755) be a destructor
  type, or a drained `Vec` of them, holding no cell share (`Ty.ok_lk_pay`; a
  channel's queue of destructor values is a field of a struct under its
  glue, a destructor type), and an `Arc`'s to own none or be a destructor
  type or a drained `Vec` of them, or (Agora #804, a read guard's) a view's
  type (`Ty.ok_arc_dtor`; of the blocks, an `arc` block is of the first
  kinds, never of a view's, `A2.Dtor.arc_blocks_dtor`); `arc_new`, a lock's
  and a library handle's constructor ask the same of what moves in
  (`A2.Dtor.share_new_dtor_free`), and each of them of a destructor value or
  of such a `Vec` names a destructor the program checked (`Rhs.codeOK`,
  `DeadCodes`). Of types: the payload type of every share in a binding's
  type owns none or is a destructor type or such a `Vec` (or, a read
  guard's, a view's type, Agora #804), a lock's and a
  cell's owns none or is a destructor type or such a `Vec` holding no cell share
  (`A2.Dtor.shares_dtor_free`, over `A2.Dtor.ok_payloads_free` and
  `ok_lockPayloads_free`), so a check-out binding (`withLock`,
  `withCell`), whose type is the lock's payload's, holds none, or is that
  destructor value, which the body gives no other value
  (`StmtT.withLock`'s `hna`: an `assign` to it would drop the old value
  with no code).
- Agora #755: **`Locked D`.** A lock's or a cell's payload may be a
  destructor value (`Ty.dtor f u`: a `% Drop` struct or enum, or one with
  glue) whose type holds no cell share (`Ty.lkPay`; Agora #803: before, no
  share at all; now `arc` and lock shares, as nurlc's `Locked Conn` whose
  `% Drop Conn` holds an `Arc Pool`). `locked_new` (and a
  cell's constructor) takes one (`RhsT.lockNew`, naming a destructor the
  program checked, `Rhs.codeOK`). `locked_update l f` checks it out to
  `x` (`withLock`) as before; the body gives `x` no other value (`hna`)
  and leaves it holding a `D` at its end (as before), and the scope's end
  gives it back, and nothing else, when its type holds no share: the
  give-back's crossing check cannot fail, so `Step.scopeLFail` and the
  code-less `Release.drop` are not taken
  (`A3.LockDtorWitness.scopeL_end_gives_back`, over `release_puts`,
  `sendCheck_noArc`; that `x` holds a `t` is proved for a typed frame,
  Agora #805, and that the block is there and checked out on every
  reached configuration, Agora #808 below). A panic in the body gives it back too
  (`scopeL_panic_gives_back`: `Step.scopeLP`'s release is the give-back
  whenever `x` still owns a `D`, the same hypotheses), where nurlc's `locked_update`, which runs
  `f` in place in the lock's memory, leaves the value there with the lock
  held (the model releases the lock: A3.2's over-approximation, above). A
  body that moves the value out (to a `letd`, a call's `sink` parameter)
  hands it to an owner that runs its destructor, by the rules above.
  Agora #805 proves the binding's half for a typed frame: the run-time
  check-out frame's typing (`StmtT.scopeL`) asks that `x` is an owner (or,
  since Agora #825, for an `int` payload a plain integer binding) and
  live where the body ends (as `withLock` already asked), so at the
  frame's end `x` holds a value of the payload's type
  (`A3.LockDtorWitness.scopeL_end_owns`, `scopeL_typed_end_gives_back`),
  and at every panic point `x` holds a `t` (owned, or an `int` payload's
  integer), given back when the block is checked out, or nothing (an
  owner whose value moved to an owner that runs its destructor, or an
  integer binding holding no integer), and the release frees nothing
  (`scopeL_typed_panic`, over `Step.panic_st`, `scopeL_entry`; an integer
  the binding holds is never dropped by the release when the block is
  checked out: `release_cases`). Agora #805 asked this for a payload
  that holds a destructor value only; since Agora #825 `StmtT.scopeL`
  carries `x`'s liveness for every payload type and binds `x` as
  `withLock` does (an owner, or, for an `int` payload, a plain integer
  binding: `frame_slot`, `release_cases`), so these lemmas, and the
  give-back over a reached configuration below, hold for every payload
  type that holds no share, with no `holdsDtor` premise. Agora
  #808 proves the block's half on every configuration a run reaches: an invariant (`A3.LockInv`, `A3.reach_lockInv`,
  kept by every `TStep`: a thread's step, its marking sweep and reaps, a
  spawn, a failed spawn) says each `scopeL k t x s` frame's block is a lock
  block of type `t` checked out (`⟨t, .lock, none⟩`, and since Agora #810
  not taken, `A2.CheckedOut`), or gone, at a key below `nid`, and the
  frame is its only one on any thread, once (A3.2's mutual exclusion,
  `A3.reach_lock_excl`, `A3.Redex.frame_unique`: every operation on the
  block waits on `none`, `locked_restore` fills only a taken block,
  `A3.Step.stay`, and only a take or a check-out of a block whose payload
  is in marks one, `A3.Step.taken_stay`), whatever the payload's type. And the block is never
  removed while its frame is out: the check-out's root share outlives the
  body (`A3.reach_frame_root`, `A3.reach_frame_live`, over a second
  invariant, `A3.RootInv`, `A3.reach_rootInv`, kept by every `TStep`):
  `withLock` asks its root `a` a root binding its body does not name, and
  a step leaves the slot of a binding its statement does not name that
  holds a share (`A3.Step.keepSlot`): what a step changes is a binding it
  names, a fresh one, or the owner of a `Vec` (a change through a borrow);
  a call's inside is named apart but for its `inout` arguments, which the
  call names (the `frozen` list it lends out is no name); a call through a
  package passes its by-name captures unnamed, but only `inp` ones or
  `Vec`s (`CapsOK`, kept in memory since Agora #808 by `PkgsOK`; `A3.CapShr`,
  `A3.TypedAt.capShr`). The sweep's roots are every thread's slots, so the
  block stays. So the give-back lemmas hold of every frame of a reached
  configuration with no hypothesis on the block
  (`A3.reach_scopeL_end_gives_back`, `A3.reach_scopeL_panic`). The same
  fact gives a cell check-out's "the thread holds an owner's share", for
  every check-out of a cell's block, which no lock share names (A3.5 below,
  `A3.reach_frame_cell_owner`, `A3.reach_shareKind`, Agora #815). When the lock's last share is
  gone the marking sweep marks the lock block `dead`, its payload in it
  (`Cand` admits a lock block whose payload is in it), and the same thread
  reaps it as an `Arc`'s (`A3.LockDtorWitness.last_drop_reaps`, over
  `A2.Mem.sweepD_marks`), as nurlc's last `Locked_drop` drops the value.
  The check-out keeps the lock's share alive through the body (`withLock`
  asks a root the body does not name), so the payload is in the block
  whenever its last share goes, unless `locked_take` moved it out to a
  binding of its own (a `letd`'s: `letv` takes no destructor value). That
  is the model's semantics, and the intended one: a taken block holds
  nothing (`⟨t, .lock, none⟩`), the sweep frees it with no code, and the
  destructor runs once, on the taker's binding. nurlc matches the model
  (Agora #795, fixed by github#1832): `locked_take` still leaves zero
  bytes in the slot, but the last `Locked_drop` asks the lock whether its
  value is out (`nurl_lk_taken`) and then releases only the latch, so the
  destructor runs once, on the taker's binding; `rc_take` / `rc_restore`,
  which share the design, are fixed alike (`Rc_drop` and the runtime's
  release paths skip a value whose `RC_TAKEN` bit is set). Before the fix
  the last `Locked_drop` ran the destructor a second time, on the zeros,
  and the claim did not cover a `Locked D` (or a `Locked (Vec D)` or a
  channel of `D`, whose `locked_take` the model treats the same way) taken
  and never restored before its last share goes; it now does. Witness: `A3.LockDtorWitness.main` (a
  `Locked` of a destructor value, updated through `locked_apply` with a
  closure that takes it `inout`, its share dropped: typed, `main_safe`,
  `main_no_leak`, `main_no_leak_panic`; `A3.lockDtor_claim`: `A3.claim`
  over it). As for the `Arc` witnesses, no theorem traces the run; on
  A3's threads, as on A2's, the thread that drops the last share reaps the
  lock block's payload and runs its destructor (Agora #755 item 1,
  `A3.lockDtor_reaps`, below). A cell's state of a destructor value is admitted by
  the same rules (`Ty.ok (cell t)` asks `lkPay`; a cell's block is a lock
  block, marked and reaped alike), with no witness program, and what it
  covers rests on an assumption about the library, not a result: the
  model's `withCell` gives the state back on a panic as `withLock` does
  (and, since Agora #803, hands a destructor state that fails the
  give-back's check to a destructor frame, the block left checked out, so
  a later `withCell` waits), but the real handles check their state out
  with `rc_take` / `rc_restore` (`stdlib/std/rc.nu`,
  `compiler/tests/handle_checkout.nu`), which run no crossing check and
  hold no lock: their give-back never fails, and on a panic the taken
  value is dropped by the local frame that holds it and the `Rc` stays
  empty for good, so later handle operations panic where the model's
  `withCell` has the state back or waits. The last handle's drop skips a
  taken state since Agora #795 (github#1832). That a library's handle with
  such a state behaves as the model's cell is part of the trusted base
  (phase B). `RwLocked D`'s read guard is
  typed since Agora #804 (A3.3 above, `A3.RwDtorWitness`: the view lends
  the payload in place). Still refused:
  `locked_set`
  of one is not typed (its body assigns the checked-out binding, `hna`);
  a `% Drop` value's fields cannot be written in place by the update
  (as anywhere: a field of a destructor value is lent through the type).
  `locked_restore` of a destructor value is typed since Agora #810
  (`lockRestore_dtor_typed`; refused before, while the model's restore
  could also fill a block a `withLock` had checked out, whose give-back
  would then have dropped its value with no code): it fills only a taken
  block (`Mem.taken`).
- Agora #803: **`Locked D` where `D` holds a share.** nurlc accepts
  `Locked Conn` where `% Drop Conn` holds an `Arc Pool`; the model now does
  too (`Ty.lkPay` asks a destructor payload to hold no cell share, where it
  asked no share; witness `A3.LockArcDtorWitness.main`, a `Locked` of a
  destructor value holding an `arc` share, made, updated through
  `locked_apply`, its last share dropped: `main_typed`, `main_safe`,
  `main_no_leak`, `main_no_leak_panic`, `last_drop_reaps`,
  `A3.lockArcDtor_claim`). Such a value holds no cell share, so the cell
  half of `SendCheck` holds of it (`A2.WFv.noCell_hasCell`), and its
  give-back's check (`GiveCheck`) can fail only through `NoGuard`: when
  the value reaches a read guard. nurlc refuses that statically (`%
  NotSend RGuard`, `stdlib/std/rwlock.nu`), and its `mem_send_check`
  (`stdlib/runtime_core.c`) counts only handle blocks, so nurlc's
  `locked_with` / `locked_update` / `locked_apply` / `locked_await`
  (`stdlib/std/thread.nu`) never panic in `mem_send_check` on such a
  payload. The model is looser than nurlc here: it admits a `Locked` of a
  `D` holding a read guard, which nurlc refuses (Agora #837 tracks
  refusing it in the model's types). `Step.scopeLPD` makes the model
  total on that case, which nurlc rules out at compile time: at the
  check-out's normal end the end panics with the lock held
  (`Step.scopeLFail`), and that panic, like one in the body, turns the
  check-out's frame into the value's destructor frame at its end, the
  panic after it (`Step.scopeLPD`, as the reap's frame of a `dead`
  block), never the code-less drop (`Release.drop` refuses a destructor
  payload that fails the check while its block is checked out:
  `A3.LockArcDtorWitness.release_none`); the frame's end runs the
  destructor on the panicking thread (`fail_end_runs_dtor`: from the end,
  three steps, each the only one, the third calling the destructor). The
  block is left checked out, mirroring the runtime's held lock word should
  the case arise; that it stays so is A3.2's lock invariant, not a lemma
  of this path (no `scopeL k` frame remains, `A3.Step.stay`, and
  `withLock`, `lockTake` and `rwRead` all need the payload in). What this
  rests on: no headline theorem says the destructor runs on a failed
  give-back (`NoLeak`, `no_leak_end` and `no_leak_panic` would have held
  with the old code-less drop too); that it runs is the local lemmas'
  (`release_none`, `fail_end_runs_dtor`), and those are conditional: they
  take `¬ GiveCheck` as a hypothesis, and no typed reachable configuration
  is shown to meet it (it needs a read guard in the payload; Agora #837
  aims to prove it unreachable, `giveCheck_typed`). Nor is the passing
  case a lemma for such a payload: the give-back lemmas of
  `A3.LockDtorWitness` (`giveable_of`, `scopeL_typed_end_gives_back`,
  `release_cases`, `scopeL_typed_panic`) still assume `hasArc = false`, so
  that a typed share-holding payload's check-out ends in `Release.put` is
  not yet a lemma (Agora #837 item 3). The same frame serves a `Locked
  (Vec D)` (it drains the `Vec`) and a cell's check-out (`withCell`); for
  a cell it has no runtime counterpart: real handles check their state
  out with `rc_take` / `rc_restore` (`stdlib/std/rc.nu`), which run no
  crossing check and hold no lock, so their give-back never fails; and on
  a panic the runtime's taken value is dropped by its local frame and the
  `Rc` stays empty, so later handle operations panic, where the model's
  `withCell` waits on the block left checked out (trusted base, above). A
  channel's send and a lock's or a cell's constructor that fail the check
  panic with the value in the sender's binding, whose own frame runs its
  destructor, so no failing check drops a destructor value with no code.
- Agora #755: **`Locked (Vec D)`.** `Ty.lkPay t` is `t.dtorFree || (t.dnest
  && !t.hasCell)` (Agora #803; before, `!t.hasArc`): a drained `Vec` of destructor values, at any depth,
  holding no cell share, which contains the destructor type itself (`Ty.ok`'s
  lock and cell cases no longer ask `!vecD`). The check-out binds the `Vec`
  at its own type; the body may push to it and pop from it (a popped
  element is an owned destructor value, which only a `letd` binds), and
  drops no element in place (the model's in-place drops, `free`, the
  edits `trunc` and `set` (`vec_truncate`, `vec_set`) and `withElem`, ask
  elements that own no destructor value, as for any `Vec`; `vec_clear` has
  no form of its own: it is a truncation to 0, or for a `Vec D` code the
  calculus types, `A2/DropCode.lean`); `hna` still refuses an `assign` to the binding; the
  give-back's crossing check cannot fail (`sendCheck_noArc` is of any type
  that holds no share; for one that holds `arc` or lock shares, Agora #803,
  a failing check hands the `Vec` to a destructor frame that drains it,
  `Step.scopeLPD`); `locked_restore` of the `Vec` is typed (Agora
  #810: it fills only a taken block). So the `Locked D` cut's three closed
  paths cover it unchanged. When the last share
  goes the marking sweep marks the lock block (`Cand` already reads a lock
  block's type as a nest) and the reap binds the `Vec` at its own type in
  a destructor frame that drains it, element 0 first, as nurlc's last
  `Locked_drop` drops the `Vec`'s elements in index order. Witness:
  `A3.LockDtorWitness.mainV` (an empty `Vec` of `DT` locked, a value made
  and pushed through the check-out, the share dropped: `mainV_typed`,
  `mainV_safe`, `mainV_no_leak`, `mainV_no_leak_panic`, `last_dropV_reaps`,
  `reapV_drains`; `A3.lockVecDtor_claim`, `A3.lockVecDtor_reaps`). The
  run is not traced; that the body leaves the binding holding a `Vec` at
  its end and where it panics is proved for a typed frame as for `Locked
  D` (Agora #805, `scopeL_end_owns`, `scopeL_typed_panic`), and that the
  block is then there and checked out is proved on every reached
  configuration, as for `Locked D` (Agora #808: `A3.reach_frame_checked_out`).
- Agora #755: **a channel of destructor values.** nurlc's `Channel A` is a
  counted `ChImpl A`, a struct holding the queue (`Vec A`), whose drop glue
  drops the queue's elements in index order when the last `Channel_drop`
  goes, on the thread that runs it (`stdlib/std/channel.nu`; `chan_close`
  only sets the flag: receivers drain the queue). The model's channel is
  a lock block of the queue and the flag; for an element type that holds
  a destructor value that payload is the struct under its glue,
  `Ty.dtor g (prod (vec s) int)`, `g` a `GlueOK` function that takes it
  apart and hands the queue to a `letd` at its own type (`Ty.ChanOf`:
  `chan_send` / `chan_recv` / `chan_close` take either form; the plain
  `prod (vec D) int` is refused as a lock's payload, being no destructor
  type and no `Vec`). So a channel of `D` is a `Locked` of a destructor
  type holding no cell share (`Ty.lkPay`), and its last share's drop is
  `Locked D`'s: the marking sweep marks the block, the same thread reaps
  the payload into a frame of `g`, whose end calls `g`, which drains the
  queue, each element's destructor in index order (FIFO). `chan_new` is
  `locked_new` of that struct (built from an empty `Vec` and a 0, bound by
  `letd` under `g`), naming `g`'s check and the elements' destructor's
  (`Rhs.codeOK`, `chanNew_codeOK`; `DeadCodes` is over `Ty.Reaps`: a
  block's own destructor and a channel's elements'). A `chan_recv` hands
  the head out as an owned `Option s`, which only a `letd` under the
  option's glue binds (`letv` refuses a type that holds a destructor
  value), so the receiver's binding runs its destructor. A `chan_send` to
  a closed channel parks the value in a fresh lock block of the element
  type (`EvalR.chanSendClosed`, `closed_send_parks`), which the marking
  sweep marks and the sender reaps (Agora #805, `A3.TStep.closed_send_reaps`,
  above). Witnesses:
  `A3.ChanDtorWitness.main` (a channel of `DT`, one value sent and never
  received, the only share dropped: `main_typed`, `main_safe`,
  `main_no_leak`, `main_no_leak_panic`, `last_drop_reaps`,
  `reap_runs_glue`, `closed_send_parks`; `A3.chanDtor_claim`,
  `A3.chanDtor_reaps`) and (Agora #805) `A3.ChanDtorWitness.mainC` (the
  channel closed, then a destructor value sent: `mainC_typed`,
  `mainC_safe`, `mainC_no_leak`, `mainC_no_leak_panic`;
  `A3.chanClosed_claim`, `A3.chanClosed_reaps`). Agora #805: a channel's
  glue starts the queue's drain (`A3.chanGlue_drains`, any `GlueOK` glue
  of `prod (vec s) int` with `s` holding a destructor value, and
  `A3.ChanDtorWitness.glueV_drains`): its body takes the struct apart and,
  through the typing, hands the queue to a `letd w f` at `vec s` (an
  `assign` or `unpair` of it is refused), `f` the elements' destructor
  (`s = Ty.nest n (.dtor f u)`; `dfn` at the witness), whose frame's end,
  under any renaming the call applies and the queue non-empty, is one drain
  step and nothing else, element 0 to a frame of `f` of its own. Index
  order is that step taken again on the shorter queue; no theorem iterates
  it. Read off the steps, not proved:
  the run from the reap's call of the glue into its body (the parameter's
  binding, `BindParams`); no theorem traces the run. Agora #805: a receive
  of a destructor value has a witness, `A3.ChanDtorWitness.mainR` (sent,
  then received and bound by `letd` under the option's glue `ofnR`, an
  `EnumGlueOK` glue of `sum int DT`: `mainR_typed`, `mainR_safe`,
  `mainR_no_leak`, `mainR_no_leak_panic`, `A3.chanRecv_claim`;
  `recv_runs_glue`: the head handed out, owned, in a frame whose end calls
  the glue; `ofnR_takes_payload`: the glue moves it to a `letd` frame of
  its destructor). Since Agora #803 a channel of destructor values that
  hold `arc` or lock shares is typed too (`Ty.lkPay` asks no cell share): a
  send that fails its crossing check panics with the value still in the
  sender's binding (`EvalR.chanSend`'s panic leaves the store), whose frame
  runs its destructor, and a receive's check is of cells only. Not typed: a
  channel of destructor values that hold a cell share (`Ty.lkPay`'s
  `!hasCell`, stricter than nurlc), or of values holding one in a field of
  a type with no destructor of its own.
- Agora #610: **the last share's drop runs an `Arc`'s destructor, on the
  thread that dropped it.** A2's step ends with the marking sweep
  (`Mem.sweepD`): an unreached `arc` block whose payload is a destructor
  value (Agora #755: or a drained `Vec` of them, at any depth), and that
  no other such block's payload reaches (a top orphan),
  is marked `dead`, its payload in it, and its payload, and a `dead`
  block's, are roots, so what they reach is kept; every other unreached
  block is removed and its payload freed, as before. The same thread then
  reaps every orphan before anything else runs (`Settle`, part of
  `Steps.step`): `Step.reap` moves the payload to a fresh binding in a
  destructor frame at the thread's redex, whose end runs the destructor
  as a `letd`'s does (Agora #755: a `Vec` is bound at its own type, and
  the frame's end drains it, each element's destructor in index order,
  `Step.scopeDDrain`, as nurlc's drop of an `Arc<Vec<D>>`'s last share
  drops the `Vec`'s elements). While a slot's value refers to the block (another
  share, a borrow of the payload) it is kept as it was
  (`A2.Mem.sweepD_keeps`); when nothing refers to it it is marked
  (`A2.Mem.sweepD_marks`). An inner `Arc` the payload holds is orphaned
  when the outer destructor drops its share: outer first, as the
  runtime's counts. The invariant holds through the marking sweep
  (`A2.Inv.sweepD`, `A2.MemCodes.sweepD`) and the reaps
  (`A2.settle_ok`, over `A2.pres_reap`). The reaps can always be taken
  and end (`A2.orphan_reaps`: from every typed statement, at its redex;
  `A2.settle_total`: each empties an orphan and the sweep after it makes
  no new block of a destructor value; `A2.steps_step`: every step of a
  typed configuration is one of a run), so the eager `Steps` drops no
  run `Step` has. No store a run reaches between its steps has an orphan
  (`A2.no_orphan`), so a reached configuration that is not finished
  steps by a step that is no reap (`A2.progress_no_reap`), and a finished
  run has none left (`A2.no_leak_end`, over `A2.Mem.sweepD_empty`).
  Witness: `A2.ArcDtorWitness` (an `Arc` of a destructor value, cloned,
  both shares dropped: typed, `main_safe`, `main_no_leak`;
  `last_drop_reaps`: in a store where nothing refers to the block any
  more, the marking sweep marks it and the thread's next step is a reap;
  the theorems do not trace the witness's run; `A3.arcDtor_claim`: `A3.claim` over it).
  Agora #755's witness: `A2.ArcDtorWitness.mainV` (an `Arc` of a `Vec`
  holding one destructor value, cloned, both shares dropped: typed,
  `mainV_safe`, `mainV_no_leak`; `last_dropV_reaps`: in a store where
  nothing refers to the block any more, the marking sweep marks it `dead`
  at `vec DT` and the thread's next step is a reap; `reapV_drains`: the
  reap binds the `Vec` in the frame `scopeD _ dfn skip`, whose end, while
  the slot still holds a non-empty `Vec` and no orphan awaits, is the
  drain step and nothing else; `A3.arcVecDtor_claim`: `A3.claim` over it).
  As for `main`, no theorem traces this program's run: that the drain
  runs `dfn` once per element is read off the steps
  (`A2.Dtor.scopeD_end_drains`, `scopeD_end_runs_dtor`), as for a
  binding's drained `Vec`. Left, each
  named in the stricter-than-nurlc list below or here: a panic no frame
  catches ends with the sweep that frees an orphaned payload with no code
  (`Steps.panic`: no frame is left to run it); orphans that reach each
  other in a cycle (no top one; arc payloads never do, a cycle needs a
  lock between them; since Agora #803 two `Locked D` payloads can form
  one directly, each holding a share of the other's lock, in a closure's
  environment, types being finite otherwise; nurlc refuses such a store,
  docs/MEMORY.md §7.7, so no program it accepts forms one), and the blocks reached only
  from their payloads, are freed with no code, where the runtime leaks
  them, running no destructor either; several orphans one step leaves
  are reaped in the order `Step.reap` picks, not nurlc's drop order; a
  slot that still holds a handle into the payload after its borrow is
  dead in the context keeps the block reached, so the destructor runs
  later than the runtime's count would (A3's *Phase D obligation* on
  handles that outlive their share, `A3/DESIGN.md`; on A3's threads such
  a slot may be another thread's, which then runs the destructor, below).
- Agora #755 item 1: **on A3's threads too, the thread that drops the last
  share runs the destructor.** A thread's step (`A3.TStep.thread`) ends
  with the configuration's marking sweep (`A3.Cfg.sweepD`: A2's
  `Mem.sweepD` from every thread's slots and the module globals, so a
  global's block, a global `Locked D`'s too, is never marked,
  `A3.glob_not_marked`) and that thread's reaps of the orphans it marked,
  each a `Step.reap` of that thread ended by the marking sweep, all inside
  that one configuration step, before any other thread runs (`A3.CSettle`,
  A2's `Settle` on the configuration).
  When a thread's step leaves an `Arc<D>`'s, an `Arc<Vec<D>>`'s or a
  `Locked D`'s block that no thread's slot, no global and no payload
  refers to, the sweep marks it, and in the result of that configuration
  step a fresh slot of that thread owns the payload (a reap of the thread
  bound it, in a destructor frame) and the block is emptied or gone
  (`A3.TStep.last_drop_reaps`; at the three witnesses `A3.arcDtor_reaps`,
  `A3.arcVecDtor_reaps`, `A3.lockDtor_reaps`; a block only a payload the
  same sweep removes refers to is outside the lemma, though the semantics
  marks it too). The reaped payload's
  addresses leave the shared part for that thread's part, the other
  threads' facts surviving it as a lock's check-out (`A3.CInv.thread_of`),
  so the destructor's reads and writes, its later steps', are of its own
  part, and race freedom is re-proven with every sweep of the step charged
  to the stepping thread (`A3.CInv.raceFree`). The reaps can always be
  taken and end (`A3.CSettle.total`, `A3.reach_thread_total`: every A2
  step of a thread a typed start reaches to an `.ok` result, at no spawn
  redex, starts one of the configuration's; a top-level step to `.panic`
  is none, as before, and no lemma shows a spawn redex always steps),
  and no configuration a run reaches has an orphan (`A3.Reach.noOrphan`).
  `A3.claim` and `A3.claim_made` are unchanged in statement, over the new
  step. As on A2, the theorems are of configurations and steps; none
  traces a witness's run. Exactness: a dead borrow's slot that still
  holds a handle into the payload keeps the block reached (as on A2,
  above); on A3 that slot may be another thread's, and then the
  destructor runs on the thread whose later step leaves the block
  unreached, or never if that thread never ends the slot, which nurlc's
  count would not wait for.
- So a binding's end, a drained `Vec`'s, a call's result frame and
  (Agora #610) an `Arc`'s last share's drop, through the reaped payload's
  frame (Agora #755: and a `Locked D`'s, its check-out giving the value
  back), run the value's own, outermost destructor (a drained `Vec`'s
  elements' destructors, Agora #607 / #755), and everywhere else
  that could hold a destructor value is refused (the list below), but for
  the `Arc` and lock payloads 3d names (an uncaught panic's end, a cycle of
  orphans), freed with no code. An `Arc` orphaned by a
  panic's UNWINDING (Agora #790) is reaped inside the frame that caught
  the unwinding: a destructor frame's catch (`Step.scopeDP`,
  `scopeDPDrain`) leaves the frame at its end, `seq (scopeD x f skip)
  panic`, and a `recover`'s (`Step.catchP`) leaves `catchR x m0 skip`, so
  the reap's only redex is that end's `skip`, inside the frame
  (`A2.ArcPanicWitness.frame_reap_inside`, `recover_reap_inside`). A
  panic in the reaped destructor (or in an element's, for an
  `Arc<Vec<D>>`) comes back to that frame: `x`'s frame then still runs
  `x`'s destructor (`reaped_panic_runs_dtor`), and the `recover` still
  catches (`recover_catches_reaped`; no step of a `recover` frame is a
  panic, `catchR_no_panic`), as nurlc's journal drain runs the drops
  after one that panics, inside the same frame (`stdlib/runtime_core.c`,
  `nurl_panic`). nurlc's `recover` then reports the first panic's
  message; the model's panics carry no identity, so that correspondence
  holds only trivially (the two panics cannot be told apart) and is not
  modelled. The order is nurlc's too: the share's binding is inside `x`'s
  scope, so its drop goes before `x`'s destructor in the drain, as the
  reap goes before `x`'s frame's end. The step lemmas are of any store and
  statement of their shape: the run's next step is taken from the store
  the marking sweep leaves (`m.sweepD`), and that `x` still owns its value
  when the reaped destructor's panic comes back is a premise. Witnesses
  (`A2/ArcPanicWitness.lean`, all typed, safe and leak-free on
  `no_leak_end` and `no_leak_panic`; `A3.arcPanic_claim` over all three):
  `main3`, the case nurlc runs: a `recover` of a function in which a
  destructor binding `x` scopes a panic while an `Arc` of a value whose
  destructor panics holds its last share (`main3_unwind`: `x`'s
  destructor still runs, the `recover` catches); `main2`, a `recover`
  whose function makes such an `Arc` and panics with no destructor frame
  between (`main2_unwind`); and `main1`, `main3`'s frame with no
  `recover` (`main1_unwind`), which shows the model's behaviour on an
  uncaught panic, not nurlc's: with no `recover` frame nurlc aborts before
  any drain (below), where the model runs the unwinding's frames (an
  over-approximation older than #790). The runs are not traced. That these are all
  the places is read off the rules, not a single theorem (above). The
  destructors INSIDE a value are shown for a struct's fields (Agora #616),
  an enum's payload (Agora #632) and a closure's environment (Agora
  #609), above, as shapes of the glue the typing forces plus the frames'
  steps; not as one theorem about a run.
  See Agora #542–#544, #609, #611, #616, #632.

The rules are stricter than nurlc's in these places:
- for a binding of a type whose destructor may read a view:
  - nurlc lets it gain views of older bindings; here it views, from its
    `letd` on, what the `letd` records (the value's views, and up front
    views of older bindings, `HeldUp`), and a push into a drained `Vec`
    adds only what that records (Agora #782). The cost of "up front":
    every root the binding may ever view is protected (`DtorSafe`) from
    the `letd` on, not from the push, so changing or ending such a root
    between the `letd` and the first push is refused here, where nurlc
    accepts it;
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
  callee), or a `Vec` of such values, or of such `Vec`s at any depth
  (Agora #607, `ResDTy`): nurlc also returns a plain struct,
  enum or option that holds a `% Drop` value, and a `% Drop` value that
  holds views; here a struct or an enum holding one is its own destructor
  type, with its glue.
- for a struct whose drop takes it apart (Agora #616): its glue does
  nothing but hand its fields on (`Stmt.pureGlue`); and a struct of three
  or more fields is nested pairs here,
  each inner pair that holds a destructor value with glue of its own. A
  struct with a `% Drop` of its own beside a destructor field is not
  taken apart by hand (`unpair`): that would skip its impl.
- for a `Vec` of destructor values (A2-drop.3b), which is typed as a
  binding's own type, drained at the binding's end, or as a struct's field
  or an enum's payload, drained by the `letd` the glue hands it to (above),
  or (Agora #607) as another such `Vec`'s element, at any depth (`Vec (Vec
  D)`, `Ty.nest`): the drain moves each inner `Vec` out to a `letd` of the
  same destructor, whose frame drains it in turn (read off the steps; the
  witness `A2.DtorWitness.main11_safe` / `main11_no_leak` types such a
  program and applies `memory_safe` and `no_leak_end`, it does not trace
  the run). nurlc types the
  rest too, and drops a `Vec`'s elements wherever the `Vec` is dropped, in
  index order, each running its destructor. Refused here:
  - the `Vec` as a lock's or a cell's payload when its elements hold a
    cell share (`Ty.lkPay`'s `!hasCell`; Agora #803: `arc` and lock shares
    are typed), and a channel's queue of `D` with no
    glue over the channel's state. (`Locked (Vec D)`, a cell of a `Vec D`
    and a channel of `D` under its glue are typed since Agora #755, above;
    `Arc (Vec D)` too: its orphaned payload is reaped and drained.)
  Not refused: the in-place drops (the lemmas below are stated for
    elements that hold no views; a `Vec` of view-holding destructor
    values, Agora #782, is typed by the same rules, with no lemma stated).
    (`vec_free`, `vec_clear`,
    `vec_truncate` and `vec_set` of such a `Vec` — the lemmas below are
    stated for a `Vec` of destructor values, `.vec (.dtor f t)`; for a
    `Vec (Vec D)` the same code is typed by the same rules, `letd` binding
    each moved-out inner `Vec` at its own type, with no lemma stated —
    and handing an element to
    a callee that changes it (`withElem`), are code the calculus types,
    each element's destructor running:
    `x` moved into a destructor binding that ends at once, whose frame
    drains it (`A2.Dtor.vecFreeD_typed`, leaving the context `vec_free`'s
    rule leaves); a loop moving element 0 out to a destructor binding
    (`vecClearD_typed`); a loop moving element `n` out while the `Vec` is
    longer than `n` (`vecTruncD_typed`), both in index order as nurlc's;
    element `i` moved out to a destructor binding that ends at once, then
    the new value inserted at `i` (`vecSetD_typed`, typed where `vec_push`
    of the new value is, and leaving the context the push leaves): the old
    element's destructor runs before the new one is stored, as nurlc's
    `vec_set` drops it. `vec_remove y i` is the calculus's `Rhs.remove`,
    bounds-checked; out of range it panics, where nurlc's `vec_set`
    answers `F`, and the new value is dropped, its destructor running,
    either way. The loops are typed in a context with no live borrow of
    the `Vec`'s elements, which is what a truncation leaves;
    `A2.DtorWitness.main6_typed` types a program with the three loops and
    `mainSet_typed` one with a `vec_set`. An element handed over is moved
    out to a destructor binding for the body and inserted back after it
    (`withElemD_typed`, witness `mainElem_typed`): a panic in the body
    reaches that binding's frame, which runs the element's destructor,
    where nurlc's element stays in the `Vec` in place and is dropped with
    it; each destructor runs once in both. The body names neither the
    `Vec` nor what the index reads, as `StmtT.withElem` asks, so the
    element goes back where nurlc's never left. That each element's destructor
    runs is read off the steps of `letd`'s frame, as for the drain; it is
    no theorem about these forms. Two differences from nurlc's run: nurlc
    cuts the length before it drops, so a destructor that reached the
    `Vec` would see it short (none does here: the `Vec` is not lent while
    it drops); and a panic in an element's destructor leaves the loop with
    the elements not yet dropped still in the `Vec`, which its binding's
    end drains, where nurlc, the length already cut, goes on with them
    through the journal before the panic goes on (Agora #608, #619;
    below): each destructor runs once in both, the `Vec` already short
    in nurlc's run.)
- for a closure or a trait object whose environment holds a destructor
  value (A2-drop.3c, Agora #609): a closure that captures a `% Drop` value
  by value (or a struct, an enum, an option or a `Vec` holding one) is
  typed only at the class `dropd`, bound by `letd` with its glue, whose
  drop method takes the captures to their frames (nurlc's environment
  drop glue). It crosses to no thread and into no share, holds no views,
  and its methods read the environment (a method that changes it is
  refused for this class); a trait
  object boxing a value of a `% Drop` type is refused as a trait object
  (no bound's class drops). A program whose closure changes what it
  captured keeps the `% Drop` value in a binding of its own and lets the
  closure borrow it (a capture by name: the closure is then of class
  `any`).
- for a share whose payload would own a destructor value (A2-drop.3d,
  Agora #610): an `Arc` of a destructor type (`Arc<D>`, `D` a `% Drop`
  struct or enum, or one with glue) is typed, and the thread that drops
  the last share runs `D`'s destructor (3d, above); so (Agora #755) is an
  `Arc` of a `Vec` of them, or of such `Vec`s at any depth
  (`Arc<Vec<D>>`), whose last share's drop drains the `Vec`. Still refused
  (`Ty.ok`): a `Locked` or a library handle of a `% Drop` type (or of a
  `Vec` of them) whose type holds a cell share (a library handle: the
  reap of the orphaned block asks its payload hold none), or of a type
  holding one in a field of a type of no destructor of its own (a `Locked
  D` or a `Locked (Vec D)` whose `D` holds no share is typed since Agora
  #755, 3d above: the check-out gives the value back, and the last share's
  drop reaps it; since Agora #803 one whose `D` holds `arc` or lock shares,
  above); a channel of one that holds a cell share (a channel of `D` is
  typed since Agora #755, its state under its glue, above; since Agora
  #803 of a `D` holding `arc` or lock shares); a `Mutex` guarding one (a `Mutex` guards no
  value in the model). Refused by a rule while `Ty.ok` admits the type:
  `locked_set` of a `Locked D` or an `RwLocked D` (its body assigns the checked-out binding,
  `StmtT.withLock`'s `hna`; `locked_restore` of one is typed since Agora
  #810, `RhsT.lockRestore`); an `Arc` whose
  payload holds a destructor value in a field of a type of no destructor
  of its own (a struct or an option with a `% Drop` field, or a `Vec` of
  such structs: `Step.reap` hands over a value of a destructor type or of
  a drained `Vec` of them only, `ScopeDTy`'s shapes); and an `Arc<D>` (or
  `Arc<Vec<D>>`) whose `D` holds a closure (a destructor frame's binding
  holds none). nurlc types them, and the thread that drops the last share
  runs the payload's destructor, as the model does for the typed ones, on
  A2's and (Agora #755 item 1) A3's threads (3d, above). A program that shares a
  locked resource keeps the `% Drop` value in one thread's binding and
  shares what the others need of it.
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
  with an impl beside its glue, is not (nor is a payload taken out of an
  enum with an impl beside its glue). An enum with glue holds
  no views; and a payload that holds no destructor value is not taken
  out of an enum of a destructor type by value (it is lent).

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
  with it;
- a `Vec` element's destructor that panics (`Step.scopeDPDrain`, Agora
  #608): inside a `recover` extent the release of a `Vec` whose elements
  may run a destructor is itself in the journal, as a record of the
  elements still to go (`nurl_vec_drop_dtor`). The record's cursor moves
  past an element before its destructor runs, so that element is the
  destructor's (its fields are freed by the entry the destructor's
  receiver has, as a binding's are), and the drain the panic starts finds
  the record and goes on from the cursor: the elements after it in index
  order, each destructor once, then the buffer and the `Vec`, and then
  the jump (`nurl__vec_drain_resume`; a later element's panic is caught
  there, by a frame of its own, and the release goes on with the element
  after it, so the stack is no deeper for it). `vec_truncate`,
  `vec_clear` and `vec_retain` (Agora #624: once it has judged every
  element and shortened the `Vec` to the kept ones) drop
  their elements through the same record (`nurl_vec_drop_range_dtor`),
  and where the element type's drop runs code of the program's own they
  move them out of the `Vec`'s storage first, into a buffer of the
  release's own (`nurl_vec_move_drop_dtor`, Agora #709; `deque_clear` the
  same): the runtime frame's stack where they fit, otherwise the heap,
  which the record owns and frees at its end (Agora #748). A destructor
  that pushes into the `Vec` shares no slot with the release.
  Which element types may run one is nurlc's answer (`__drop_runs_code`:
  a `% Drop` anywhere inside, a library handle, a closure, a trait
  object); the others are released by a loop no panic can start in;
- a function's result, when one of the function's own bindings'
  destructors panics at its exit (the call's result frame, Agora #612):
  the result is in the journal while the bindings are dropped — a
  binding handed back keeps its registration until the others are
  dropped, and a result that is no binding (a literal, a call's value, a
  join) has a slot of its own for that window, with the ownership that
  return answers (`mem_ret_guard_push`) — so the panic's drain runs the
  result's destructor, once, and frees it. Registered only where a
  binding the exit drops may run a destructor (`__drop_runs_code`). One
  difference from the calculus, in order and not in what runs: the drain
  goes newest first, so the result is dropped before the callee's
  bindings still to go; the calculus's result frame is the outermost and
  drops it after them.

Tests: `compiler/tests/panic_in_drop_while_unwinding.nu`,
`compiler/tests/panic_in_drop_of_vec_element.nu` and
`compiler/tests/panic_in_drop_at_function_exit.nu` (clean under
AddressSanitizer and LeakSanitizer). That the journal's drain does what
`Step.scopeDP` and `Step.scopeDPDrain` do is phase C / D.

Places where the runtime does not yet do what the calculus says, each
filed: a result when a `;` defer body panics after it is set, or of raw
`s` or closure type (Agora #620).

The later fields of a struct and payloads of an enum, when an earlier
one's destructor panics, are dropped by the runtime (Agora #617): the
drop glue nurlc writes registers the parts still to go before it drops a
part that may run a destructor, so the panic's drain runs their
destructors, in order and once each. That is the run Agora #616 gives the
calculus for a struct (above: its glue takes it apart, each destructor
field in a frame of its own) and Agora #632 for an enum (its glue takes
the payload out to a frame of its own).
Test: `compiler/tests/panic_in_drop_of_struct_field.nu`.

A closure's environment is released the same way (Agora #645): its drop
method registers the captures still to go, and the environment's block,
before it releases a capture that may run a destructor, and a trait
object's drop registers its box while the boxed value's destructor runs;
the journal's elision takes the release of an environment for a call
that may panic exactly when one of the module's drop methods may (Agora
#650). That is the run Agora #609 gives the calculus: the closure's
glue calls its drop method, each destructor capture in a frame of its
own. Test: `compiler/tests/panic_in_drop_of_closure_capture.nu`.

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
