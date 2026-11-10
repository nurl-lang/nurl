# A3 — threads and data-race freedom: design

## Status

**A3 is proven** (`A3.claim : A3.Claim` in `A3/Claim.lean`, `A3.claim_made` in `A3/Make.lean`). `A3/Defs.lean`
defines A3.0's configuration (`Thread`, `Cfg`, `Cfg.view`), its steps
(`TStep`: a thread takes A2's own `Step`; `spawn`), what a step touches
(`Touch`), a race (`Race`), and the claim (`Claim`: `MemorySafe ∧ RaceFree ∧
NoLeak` for every program A2 types); `../README.md` lists the modules of
the proof. A3.1's `Arc` and A3.2's `Locked` are mechanized in the same
claim (A3.1's and A3.2's mechanization, below; A3.2's second cut adds
shares in lock payloads and `locked_take` / `locked_restore`, and what it
leaves out is listed there), and so are A3.3's `RwLocked` (A3.3's
mechanization, below: a lock block read through views, its read guards
lending the value frozen; its rest, the try forms, `wguard_get` and
`rw_get`, too) and A3.4's `Atomic` and channels (A3.4's
mechanization, below; channels are primitive rules on a lock block's
queue). A3.5's first cut, library handles whose copies are one state and
the crossing check, is mechanized too (A3.5's mechanization, below: a lock
block shared by cell shares, which are not Sync; a spawn panics when its
check fails; and a race includes two threads changing one handle's state).
A3.6's module globals set at start are mechanized as well (A3.6's
mechanization, below: the start holds them, every thread reads them
through the configuration, no step writes them, and what they reach is
left at the end; its rest runs the `make`s before `main`, which leave such
a start, and ties each read to its global's declared type,
`A3.claim_made`). A3.5b's first cut, closures that cross threads or that
several threads share, is mechanized too (A3.5b's mechanization, below: a
closure's type says where it may cross, an `Arc` holds a Sync one, a lock
or a channel a bare one, a spawn a Send one). A3.5c's trait objects are
covered by A3.5b's rules, with no new one (A3.5c's mechanization, below: a
trait's bound is its objects' class, and the crossing check walks the
box). Their rest types subsumption between classes, answers a generic bound
by the class, and decides what A2's closure model leaves out: a closure that
changes a capture it moved in, and an `inout` receiver (A3.5b's and A3.5c's
rest, below). A3.5's second cut puts library handles in lock payloads, cells' states
and channel elements, and so Send closures and `: Send` trait objects, with
the crossing check at every value going in (A3.5's second cut, below: a
failed check panics, and a cell's shares are in one thread's slots or one
lock block's payload). The rest of A3.2's and A3.3's operations
(`locked_get`, `locked_set`, `locked_apply`'s and `wguard_apply`'s result,
`locked_await`, `rw_get` as one statement, `Mutex`, and a lock reached
through a field or an element) are derived forms of these rules, each typed
as one statement by a lemma of its own (A3.2's and A3.3's rest, below); with
no new rule, the claim covers them unchanged. Three typing gaps are closed
after them (A3.5's third cut, `% NotSend` guards, shares in a slice, below):
a library handle is changed and copied through a borrow (a lent cell share
is the share), a read guard faces the crossing check and does not cross,
and a slice's elements may be shares. This note fixes the
semantics, the theorem statements and the order of work, so the
mechanization can be cut into tasks (Agora: formal track, F4–F8). The guarantee it targets is the
"no data race" clause of `CLAIM.md` and `docs/MEMORY.md` §6.2. The rules
are §6.5's.

## The theorem

For a program whose functions all check (`ProgOK`), with a source
statement well-typed in the empty context, run from the empty
configuration (A3.6: from a start that holds the module globals set at
start, `Cfg.start`, which the make phase leaves, `A3.claim_made`):

- **`A3.memory_safe`**: no reachable configuration is stuck. A2's
  statement, now for every thread.
- **`A3.no_leak`**: when every thread has ended, nothing is allocated (A3.6:
  but what the module globals reach, which lives until the process exits).
- **`A3.race_free`**: no reachable configuration has a **race**. A race
  is two different threads whose next steps touch one address, at least
  one of them writing it, and not both through `Atomic` operations.

Race freedom is proven for an interleaving semantics, that is, under
sequential consistency (SC). The step to the hardware is the **DRF-SC
theorem** of the C11 / LLVM memory model: a program none of whose SC runs
has a data race behaves under C11 as under SC. That theorem holds for
programs whose atomics are all `seq_cst` and whose locks are the model's.
This is what safe NURL can reach:

- `stdlib/std/atomic.nu` goes to `nurl_atomic_i64_*` in
  `stdlib/runtime_core.c`, and those are all `__ATOMIC_SEQ_CST`;
- `Locked`, `Mutex` and `RwLocked` are the runtime's locks.

The runtime's own relaxed and acquire/release atomics (the scheduler,
the rwlock bookkeeping, allocation counters) are C code, and part of the
trusted base, as `CLAIM.md` lists it. DRF-SC is cited, not mechanized
(Boehm & Adve, PLDI 2008; Batty et al., POPL 2011). It goes into
`CLAIM.md`'s trusted base beside LLVM.

## Semantics

### A thread steps A2's own `Step`

```
structure Thread where      -- what one thread has of its own
  st : Var → Option Slot
  nv : Nat
  s  : Stmt

structure Cfg where         -- what threads share
  alloc : Nat → Bool        -- one address space
  nid   : Nat               -- fresh addresses, never reused
  sh    : Nat → Option Shared
  ths   : List Thread

def Cfg.view (C : Cfg) (t : Thread) : Mem :=
  { alloc := C.alloc, nid := C.nid, nv := t.nv, st := t.st }
```

A thread step is A2's `Step P (C.view t) t.s r`, written back:
- the address space and `nid` go back to the configuration;
- `st`, `nv` and the statement go back to the thread.

Threads' variables never clash, because each thread has its own `st`.
Addresses never clash either: `nid` is shared and never reused, as in
A2. So every A2 lemma about one step is a lemma about one thread's step.

A3 is A2 copied and extended, as A2 was A1. The new statements below are
`Stmt` constructors, so a loop may spawn and a closure may lock.

### Shared blocks

```
inductive Shared where
  | arc (rc : Nat) (payload : Val)               -- frozen: read by every holder
  | lock (held : Option Nat) (payload : Option Val)  -- checked out to the holder
  | rw (readers : Nat) (writer : Option Nat) (payload : Option Val)
  | atomic (n : Nat)
  | chan (q : List Val)
```

A handle to one is a new value, `Val.sh a`, and a binding holding one
owns a *share* of the block:
- an `Arc` share is counted;
- a `Locked` or `RwLocked` share is counted;
- an `Atomic` or `Channel` share is counted.

The block's payload is in no thread's tree. It belongs to the block.

### The new statements

| Statement | Step | `docs/MEMORY.md` |
|---|---|---|
| `spawn f args` | a new thread runs `callStmt f args` in a fresh `st`. Every argument is a `sink`: it moves out of the spawner's slot into the new thread's | §6.5 crossings |
| `join h` | waits for the thread to end; its result moves into the joiner | `fiber_join` takes the handle (§3.3d) |
| `arc_new x y` / `arc_clone` / drop | `y`'s tree moves into a new `arc` block / `rc + 1` / `rc − 1`, and the last share frees the payload tree (`Frees`) | §6.5 *An `Arc`'s payload is frozen once made* |
| `arc_get x a` | `x` is lent the payload, as a borrow whose root is the share's binding | same |
| `lock_with l f` | blocks until `held = none`; then `held := self`, and the payload moves into a fresh slot of this thread for `f`, an `inout` argument of its own; back at the end, then `held := none` | `Locked`: one thread at a time |
| `rw_read` / `rw_write` | readers XOR writer. A read guard lends the payload frozen (`% Frozen`). A write moves it out to the writer, as `lock_with` does | `RwLocked`, `% Frozen` |
| `atomic_*` | one step on the word | `Atomic` |
| `chan_send c y` / `chan_recv x c` | `y` moves into the queue / out of it into `x` | `chan_send`: the value must be Send |

A fiber is a thread here. M:N scheduling decides which thread runs, never
what a step does.

### Footprints and races

`Step.reads` and `Step.writes` are the addresses a thread's next step
touches. They are read off the step's rule, which already names every
address it checks `alloc` for (`VecOf`, `NodeAt`, `DataAt`, `Frees`).
`Atomic` operations are marked atomic. **A race** is a pair `t ≠ t'` and
an address `i` with `i ∈ writes t ∩ (reads t' ∪ writes t')`, not both
atomic.

## Typing

The context grows no new kinds. A shared block's handle is a value like
any other (an owner of its share), so A2's rules move it, borrow it and
drop it. The thread rules add:

- **Send** (a value may move to another thread) is an owned value with no
  dependency on the sender's bindings: `E.mode = .own ∧ E.held = []`, or
  only `Arc` / `Atomic` / `Locked` / `Channel` shares. A closure's
  captures are its environment's (`RhsT.pack`), so a closure is Send when
  its environment is. This is the "question asked of the value"
  (§6.5).
- **Sync** (may be reached from two threads at once) belongs to the shared
  block's kind:
  - an `arc` payload is frozen: only read, by anyone;
  - a `lock` payload is reached only by its holder;
  - an `rw` payload is reached by readers (frozen) or by the one writer;
  - `atomic` and `chan` are reached only by their atomic steps.
- **The markers.** A positive `% Send` / `% Sync` outside the standard
  library is `unsafe` (§3), a hypothesis of the theorem, as an `unsafe`
  body is for B. A negative one (`% NotSend`, `% NotSync`, `% Frozen`)
  only removes typings. (How the classes reflect both: A3.5b's and A3.5c's
  rest, below.)
- **The crossing check** (`mem_send_check`, §6.5). A library handle whose
  copies are one state may cross only with every other owner of that
  state. The calculus takes this as the crossing's run-time
  precondition: the step panics when it fails, as `nurl_panic` does.
  So a successful crossing leaves no owner behind.

`spawn` is typed as a call whose every parameter is `sink` and Send.
`lock_with` is a call through a package (`callc`) with the payload as an
`inout` argument of its own, which A2 already types.

## The invariant

A2's `Inv`, for every thread, plus:

- **Global `HeapOK`**:
  - every allocation is in at most one thread's owned trees, or in one
    shared block's payload, never both;
  - a `lock` payload checked out to a holder is in that holder's slot,
    and the block holds `none`.
- **Frozen payloads stay frozen.** No thread's typing lets it write an
  `arc` payload, or an `rw` payload while readers hold it. Every borrow
  of one is a read: it depends on a share's binding, never on a root
  that may change it.
- **Shares are counted.** `rc` equals the number of slots holding a
  share, the same `Covers` argument as A2's `no_leak`.

**Race freedom then follows from the invariant.** A non-atomic write by
`t` is to an address in `t`'s own trees, or in a payload it holds the lock
for. Nothing else reaches such an address. Two threads can touch one
address at once only by reading a frozen payload, which is not a race.

## Order of work

Each milestone is a coherent unit, mechanized and checked by `check.sh`
before the next starts:

| | Scope | Probes it covers (`corpus/map.tsv`, phase A3) |
|---|---|---|
| **A3.0** | `Cfg`, thread views, `spawn` / `join` with moves only, footprints, `race_free` for move-only sharing | h09 h18 h21 h44 h92 h241 h244 h204 |
| **A3.1** | `Arc`: frozen payload, counted shares | h211 h212 h213 h288 h289 h338 |
| **A3.2** | `Locked` / `Mutex` | h267 h358 |
| **A3.3** | `RwLocked`, `% Frozen` read guards | h317 h357 h364 |
| **A3.4** | `Atomic`, channels | h340 |
| **A3.5** | library handles whose copies are one state, and the crossing check as a precondition | h319 h333 h336 h337 h339 h342 h356 h344 |
| **A3.6** | module globals reached by several threads | h202 h263 h272 h273 h254 |

A3.0 carries the architecture: views, write-back, global `HeapOK` and the
race definition. Each later step adds one kind of shared block and its
rules.

## A3.1's mechanization (Agora #285)

**Status (first cut, on main with #295's edits).** `check.sh` is green with
the blocks, the shares and the three rules in A2 and A3 (steps 1–3 below,
first cut). `Mem.blk`, `Blk`, `Val.arc`, `Ty.arc`, `ArcIn` / `SharesOK`,
`MInv.shares`, `MInv.blocks`, `HeapOK.bpay` and `HeapOK.bkey` (a block's
key is below `nid`) hold through every step, the edit steps and
`StmtT.editB` included. `A2.memory_safe`, `A2.soundness`,
`A2.no_leak_end`, `A2.no_leak_panic` and `A3.claim` are re-proven with:
- `RhsT.arcNew t y` / `EvalR.arcNew`: `y`'s value, of a plain type
  (`Ty.plain`: integers, and structs, enums and shares of them), moves in
  as `PushArg` hands it (an owner moves, an integer is copied). It goes
  into a fresh block at key `nid`, and `nid` moves past it, so a key is
  never an address. The result is an owned `arc t` share that holds
  nothing (`out_share`, `rhs_arcNew`).
- `RhsT.arcClone a` / `EvalR.arcClone`: a read of the share in `a`, owned
  or lent, gives a new owned share of the same block (`out_arcClone`).
- `RhsT.arcGet a` / `EvalR.arcGet`: the payload of `a`'s block, lent
  (`lendOf`, the identity on a plain value, `WFv.plain_lend`). Its entry
  was `projE a E t`, a field's; the second cut makes it `getE a E t`, a
  borrow through a share of `a` (below). Either way it ends with `a` like
  any borrow. A plain payload has no
  handle, so it is valid through any dependency and no borrow lands in a
  block (`out_arcGet`). The value is read from the block (`m.blk k`),
  which `SharesOK` says the share carries, so the packages in memory stay
  the ones the program made (`MInv.blkCodes`).
- Dropping a share frees nothing (`Frees.arc`). The count is ghost and is
  not stored. There is no sweep in this cut: a first-cut payload owns no
  address, so a block no share reaches frees nothing, and keeping it is
  unobservable (only a share reads a block). The blocks only grow
  (`BlkLe`: `Step.blk`, `RhsPost.blk`, `CatchOK`, A3's `Grows.blk`).
  `Covers` counts no payload, and `covers_evalR` reads `HeapOK.bpay`, so
  `no_leak` is unchanged.
- In A3, no `Touch` is added. A block's key is no address (`bkey`), every
  step keeps every block as it was (`Step.blk`: no step writes a payload;
  `arcNew` writes only at a fresh key), and the count's word is the
  runtime's, changed atomically. So a clone, a drop or a payload read is
  no race. Another thread's facts survive a new block (`ThreadOK.grow`,
  `MInv.grow`). Send: `Ty.arc t` meets `SpawnOK`'s `holdsView = false`
  (`arc_spawnOK`, `arc_spawnOK_plain`).

Not yet mechanized: the count as a stated invariant, the sweep (needed
once a payload owns addresses: step 2's second cut, a `Vec` payload), and
the probes (step 4).

**Status (second cut, started).** The settled design is option 1 below: a
payload's memory is its block's, `Sub` / `Top` / `Below` do not enter a
share's payload, and a borrow may land in a payload when its entry depends
on a root whose value holds a share of the block. What `check.sh` proves:
- `HeapOK.blk : BlkOwn m`: every block owns its payload tree. Its addresses
  appear once in it, in no owned tree and in no other block's payload, and
  are live and below `nid`; the key is below `nid`. Every construction of
  `HeapOK` proves it (`BlkOwn.frame` for a step that keeps the blocks,
  `rhs_arcNew` for a new one), so an owned value a right-hand side hands on,
  and a pushed or stored element, carry that they hold no payload address
  (`RhsOut.valOwn`, `Pushed.np`, the `hnp` premises of `HeapOK.grow`,
  `editPush`, `editSet`, `freeV`).
- The first cut's "a payload owns no address" stays as `HeapOK.bpay` until
  the sweep exists: `covers_evalR` (an `arc_new` keeps every address
  covered by a slot) and `no_leak_end` still read it, and `arcNew` still
  asks `Ty.plain`. `Covers` does not count payloads yet.

What stops the borrows into a payload (the second cut's step 2) as it was
specified: a view *stored in an owned tree* (`ViewsOK`) that is valid
through a share-kind dependency breaks `viewAt_not_self` (`Frame.lean`).
That lemma is what lets `ViewsOK.keep_except` (`rhs_move`, `pop`,
`takel` / `taker`, `editB`'s `MInv.edit_drop`) and `ViewsOK.dropSelf`
(`MInv.revive`) ignore the dependencies on the tree's own owner, and it
holds only because no tree views itself (`SelfFree`). With a share
dependency it fails in memory: a struct may hold a share `a` and a view of
the same block taken through another share `b` (the typing allows it, and
it is safe), and memory cannot tell `a`'s copy of the payload from `b`'s,
so the view is valid through the struct's own owner as well. Once such a
view is valid only that way (`liftE`, a weakening or a reroot can leave the
owner in its own `held`), a move (`rhs_move`) or a split (`unpair`, `pop`)
leaves a live view whose witness is gone. The typing never makes such a
view (`pair`, `push` and `assign` ask `x ∉ roots D`, and `CallT` keeps an
`inout` argument out of the other arguments' dependencies), but the
invariant does not say so. The ways out:
- **Option Two's invariant** (above): every view stored in `x`'s tree is
  valid through a dependency whose root does not reach `x`, through
  borrowed parameters' dependencies (a reroot of `p` keeps it because `p`'s
  anchors are frozen while `x` changes). This is the general fix. It is an
  `MInv` fact kept through every step, the call machinery included.
- **No stored payload view.** A share dependency never enters `held`, so
  `ViewsOK` needs no payload case. This means a check at `PushArg.slice`,
  and no payload borrow passed to a call, since a callee may store a view
  of its `in` parameter and the reroot then turns it into a share view.
  Both checks are anti-monotone in dependencies. They survive `liftE` only
  if `allKinds` has no `share`. But then `derive_lift` fails for an
  `arc_get` inside a callee, because `S.A`'s dependencies composed with
  `share` are not in `S.A`. So this needs its own handling in `Rename`.
- **A scoped `arc_get`**: `letv x (.arcGet a) s` steps to
  `frozen [a] (rbind x s)`. `x` is a borrowed root anchored on `a`, its
  exit kills what depends on it instead of rerooting, and a share
  dependency appears only as `x`'s own path. `NodeAt` / `DataAt` then find
  payload nodes, and `rootbLt` asks `a < x`. A payload borrow cannot be
  returned from the function that took it (h288's helper).
- **A conservative sweep** that keeps a block while any slot holds a share
  of it or a handle into it. A payload borrow is then valid while its block
  exists, with no tie. It is sound and simple, but it frees later than the
  runtime does.

Steps 3–6 (the real `arc_get` handle, `editB`'s exclusion, the count and
the sweep, A3) wait on this choice.

**Chosen: the conservative sweep (the fourth way), made precise.** The
model collects blocks by *reachability*. A block lives while some slot's
value, or the payload of a live block, holds a share of it or a handle
(`href c`, `view d …`) whose address lies in its payload. A payload view or
href is then valid by its own existence, because its slot keeps its block.
The runtime frees at refcount 0, which can be earlier than this sweep: a
dead borrow's slot may still hold a handle into the block. **Phase D
obligation (not proven here):** the two agree on every live binding. That
is, refcount 0 implies that no *live* binding reaches the block. It
follows from the typing, because `arc_get`'s borrow depends on its share
binding and dies with it.

Proven so far:
- `Refers`, `Reached` (a least fixpoint, so no removal order is needed),
  `Unreached` and `Mem.sweep` (`Semantics.lean`). The sweep removes every
  block nothing reaches and frees exactly its payload's addresses.
- `A2/Sweep.lean`:
  - the sweep keeps the slots, `nid` and every reached block
    (`Mem.sweep_blk`, `sweep_blkLe`);
  - it frees only unreached payloads (`Mem.sweep_alloc`);
  - reachability survives it (`Reached.sweep`);
  - it keeps `HeapOK` (`HeapOK.sweep`).
- `Kind.share`: a dependency through a share's payload. It ends as `inner`
  does, `comp` absorbs it, and `allKinds` covers it. No rule makes one yet.

The sweep is not yet run by `Steps`, and `Covers` and `no_leak` are
unchanged.

What stops step (b) for now is `StmtT.editB`'s progress. A payload `href`
valid "by its own existence" is valid whatever its dependencies are. So
`MInv.thru_owner` (a live borrow whose memory roots all own their slots
names a node of one of their trees) can no longer be proven, and `editB`
through a borrow that lies in a payload has no step: `NodeOf` searches
owned trees only, as it must, since a payload is frozen. Typing excludes
such a borrow only if the invariant links the payload handle to a mark
that `editB` refuses. A trial (its patch is outside the tree) marked it by
a share dependency or a borrowed root (`PayGate`), kept the mark through
`RootKeep` / `HKeep`, and made payload Vecs hold no Vec (`Ty.flat`), so an
element read out of a payload lends no handle. The mark does not survive a
borrowed parameter's exit (`exitRoot`). When the mark is the parameter
itself, the reroot onto what the parameter borrowed needs memory to tie the
handle to the parameter's own value, and a dependency-free payload handle
has no such tie. Ways on:
- `NodeAt` / `DataAt` also find payload nodes. A borrowed root's payload
  handle then lands positionally, through `RootNode`, as an owned node
  does, and the standard reroot lemmas carry it. `RootNode.owned` becomes
  "in an owned tree or a payload".
- Or `derive` from a borrowed root adds a share mark. `editB` already
  refuses borrowed roots, but a summary's `lends` then carries `share` to
  callers, so `editB` through a borrow returned by a function is refused.

**Taken: the first way, with a share mark from `arc_get` (proven).**
`check.sh` is green with:
- `NodeAt` / `DataAt` also find a node in a live block's payload.
  `RootNode.owned` gives `InMem` (in an owned tree or a live payload), and
  `ViewAt.owned` gives an owned buffer or a payload address (`PayAddr`).
  A node is still unique across trees and payloads (`BlkOwn`: `pay_unique`,
  `owned_pay_head`). The keep lemmas (`rootKeep_frame`, `rootKeep_ext`,
  `rootKeep_move`, `rootNode_st`, `RootKeep.vkeep`) take `BlkLe` on the
  blocks.
- `arc_get a`'s entry is `getE`. Its path is `derive a E .share`: an owned
  or rooted share gives `⟨a, .share⟩`, and a borrowed share passes its own
  path on, as `share`. Drop and replace kill it.
- `Landed`: an `HrefAt` / `ViewAt` lands where its root's node puts it
  (`RootNode`, `Lands`), or, through a `.share` dependency, anywhere in a
  live payload (`InPay`), whatever the root does. It stays while the
  blocks only grow (`Landed.keep`, `vkeep_share`, `hkeep_share`).
  `viewAt_not_self` asks a kind other than `share`.
- `ThruOK` asks that no dependency on the path has kind `.share`
  (`ThruOK.noShare`). `MInv.thru_owner` takes that and lands the borrow's
  node in an owned tree (`Landed.root`). This is the lemma "no `.share` in
  `memDeps P` ⇒ the node is found by `NodeOf`", so `editB` never meets a
  payload node.
- Still the first cut's: `HeapOK.bpay` holds, so no payload holds a node
  and the share alternative is uninhabited. Two places dismiss it with
  `bpay` (`Landed.root_of_heap`, `viewAt_not_self_heap`): a borrowed
  parameter's reroot (`reroot_vkeep`, `reroot_valOK_gen`) and a
  destructor's revive (`ViewsOK.dropSelf`). A3 passes `PayFree` (from
  `ThreadOK.blocksAt`) where `Touch` and the downward frame lemma may find
  a payload node. `arcNew` / `arcGet` still ask `Ty.plain`.

**What stops lifting `bpay` (step d).** Those two places need real proofs:
- *Reroot.* A dependency `⟨p, .share⟩` on a borrowed parameter `p` comes
  from `arc_get p` inside a callee, or from `allKinds`' `⟨r, .share⟩` in
  `S.A`. It is rerooted onto `p`'s path and held. When `p`'s value is a
  share, `ValOK.arc` names no dependency, so that list may hold no memory
  dependency. The mark then vanishes, and the payload handle is left with
  no landing dependency. Two ways out:
  1. `ValOK.arc` asks that the share itself lands through a dependency, so
     the reroot has one to compose with (`comp _ .share = .share`).
     `RootNode` must then reach a share that a borrowed slot holds.
  2. `arc_get` takes only an owned share (a borrowed share is cloned
     first), and `allKinds` drops `share`. Then `derive_lift` must be
     checked for a `getE` inside a callee.
- *Revive.* `Entry.revive` drops the destructor binding's own
  dependencies. A stored payload view valid only through `⟨x, .share⟩`
  then loses its mark, and `SelfFree` does not cover a share. The fix is
  the same as (1), or `revive` keeps share dependencies.

**Taken: way 1, and `revive` keeps share dependencies (proven).** The
design: payload memory is its block's, never a slot's tree; a block lives
while a slot or a live payload holds a share of it or a handle into its
payload (the sweep); a borrow may land in a live payload through a `.share`
dependency, which `arc_get` creates, `comp` keeps and `editB` refuses
(`ThruOK.noShare`). The runtime frees at refcount 0, and the agreement
with the sweep is the phase-D obligation above. `check.sh` is green with:
- (A) `RootNode` reaches a share at the top of a borrowed slot's value
  (`∃ v k q, m.st r = some ⟨false, some v⟩ ∧ Top (.arc k q) v ∧ n = .arc k q`),
  so `⟨y, .self⟩` or `⟨p, .share⟩` on a borrowed share reaches its value.
  `RootNode.owned` and `Landed.inMem'` say what else a root reaches is such
  a share; `Landed.inMem` is for nodes.
- (B) `ValOK.arc` asks `∃ dep ∈ P, ArcLanded m dep (.arc k p)` (first
  `Landed`; `ArcLanded` since e2, below): a lent share lands through a
  dependency, as an `href` does. `valOK_arc` finds it in a borrowed value,
  `bor_arcLanded` uses it for (A)'s disjunct. `lend_valOK'`
  takes a landing premise for the shares at the top, `lend_valOK` one for
  every value inside (its callers prove it by `Lands` / `derive_lands`,
  `MInv.share_lands` for a payload). `HKeep` keeps a share's landing too.
- (C) `Landed`'s share alternative asks that the dependency's root reaches
  memory: `dep.kind = .share ∧ RootMem m dep.root ∧ InPay m n`. `RootMem`
  is an owner's slot (with a value or not) or a `RootNode`. This excludes a
  handle-free borrowed root (an `int` parameter `allKinds` gave a
  `.share`). An owner whose slot was emptied counts: a move (`rhs_move`,
  `takel` / `taker`, `unpair`) hands the value on with its holder's own
  share dependencies, and their witness is the block, not the tree.
  `RootKeep` keeps an owner an owner (`RootKeep.of_slot`, `.of_st`);
  `vkeep_share` asks `RootMem` after, which its users on a changing owner
  (`keep_except`, push in `Steps`, pop in `Rhs`) have from the owner's
  slot. `reroot_landed` reroots a landing through `⟨p, k⟩`: `p` reaches
  memory, `bor_lands` gives a non-name `d'` in `Ep.path ++ Ep.held`, and
  `⟨d'.root, comp d'.kind .share⟩ = ⟨d'.root, .share⟩` lands with
  `d'.root` reaching memory.
- (D) `Entry.revive` keeps the binding's own `.share` dependencies
  (`revive_dep`: `d.root ≠ x ∨ d.kind = .share`), and `ViewsOK.dropSelf`
  keeps them, as `viewAt_not_self` does; with (C) they stay valid while
  `x` holds its value. The revived binding runs no other destructor and
  is no longer `letd`'s (`dtor`, `dbind` false), so ending its scope after
  the call asks nothing of its own dependencies (`EndOK`, `DbindSafe`).
- `Landed.root_of_heap` and `viewAt_not_self_heap` are gone: the reroot
  (`reroot_vkeep`, `reroot_valOK_gen`) and the revive no longer read
  `HeapOK.bpay`. It is still read by `covers_evalR`, `no_leak_end` and A3
  (`PayFree`).
- (d1) `arcGet` asks `t.holdsView = false ∧ t.hasFn = false` (`Ty.hasFn`
  moved to `Syntax.lean`), not `Ty.plain`: it lends `lendOf bl.pay`, whose
  every handle lands in the payload through the share dependency
  (`out_arcGet` by `MInv.share_lands`), whatever the payload holds. While
  `bpay` holds, a payload still owns no address, so no such handle exists
  yet. `arcNew` still asks `Ty.plain`: moving a tree into a block needs
  `Covers` to count payloads, and so `no_leak` the sweep (step e), in the
  same change as `bpay`'s removal.
- (e1) `Covers` counts payload addresses: every live address is
  `Covered`, in an owned tree or a live payload (`PayAddr`). Every
  `covers_*` lemma carries the payload case (no step that keeps the blocks
  frees a payload address), and `covers_evalR` no longer reads `bpay`:
  what `arc_new` takes from `y` is the new block's payload. `bpay` is now
  read only where the first cut needs it: `rhs_arcNew` (a plain payload
  owns no address, `BlkOwn.of_none`), `no_leak_end` / `no_leak_panic` (a
  block that is left at the end owns no address, until `Steps` sweeps), and
  A3 (`PayFree`, `BlocksAt`, `ThreadOK.no_leak`).
- (e2) **The sweep keeps the memory invariant** (`A2/Sweep.lean`):
  `MInv.sweep : MInv m Γ → MInv m.sweep Γ`, `Covers.sweep`, and
  `Mem.sweep_empty` (no slot holds a value: every block is swept). A
  slot's value, and a reached block's payload, refer only to reached
  blocks (`Kept`); a node a borrow lands in holds the address of the
  handle that reaches it (`KeptAddr`, `Landed.kept`), so a payload it lies
  in is reached; `RootNode`, `Landed`, `ViewAt`, `HrefAt`, `ValOK`,
  `SlotOK`, `ArmOK` and `SharesOK` all carry over (`*.sweep`). For this,
  (B) is `ArcLanded`, not `Landed`: a lent share lands where its root's
  node puts it, or, through a share dependency, wherever, as long as the
  root reaches memory. A share has no address, so the slot that holds a
  copy of it need not refer to the block whose payload the original lies
  in (an `Arc (Arc i)`'s inner share, lent by `arc_get`); `InPay` would not
  survive the sweep, and the reroot needs only `RootMem` of the share's
  dependency (`bor_arcLanded`, `reroot_arcLanded`). The node landings
  keep `InPay` (`bor_lands`, `reroot_landed` and `rootb_anchor` are for
  nodes).
- (e3) **`Steps` runs the sweep at the end of every step** (the cleaner of
  the two: one place, at a step boundary, where every value is in a slot
  and `MInv.sweep` applies; a sweep inside the rules would meet values in
  flight). `Steps.step` continues from `m'.sweep`, `Steps.panic` ends at
  `m'.sweep`. `Step` itself does not sweep, and `Step.blk` (every step
  keeps every block) stands. `Steps0` is the sweep-free run, which A3's
  thread-local runs use (`reach_ok0`; A3's sweep will be the
  configuration's, over every thread's slots).
  - `CatchOK`'s `BlkLe m0.blk m.blk` weakens to "the blocks the caller's
    store reaches outside the frame are kept" (`OutVals`,
    `Reached.catch`, `CatchOK.sweep`); `catchP` sweeps the typing's
    `MInv (m0.set x _) Δ` before growing it to the store it returns to.
  - `Inv.sweep`, and `reach_ok` / `reach_panic` sweep after every step.
  - `no_leak_end` / `no_leak_panic` no longer read `bpay`: when every slot
    is gone, nothing reaches any block, so the last sweep left none
    (`Steps.ok_swept`, `Mem.sweep_empty`), and `Covers` leaves nothing
    allocated.
  `bpay` is now read only by `rhs_arcNew` (`arc_new` still asks
  `Ty.plain`) and by A3 (`PayFree`, `BlocksAt`, `ThreadOK.no_leak`).

- (f) **A3 with payload addresses** (`check.sh` green, while `bpay` still
  held, then without it):
  - *The address space is cut three ways*: one part per thread, disjoint,
    and the shared, read-only part of the live blocks' payloads
    (`payPart`, `PayIn`), apart from every part (`CParts.pay`); one payload
    owns each payload address (`CParts.uniq`). A thread sees its part and
    the payloads (`ownView`), and there has A2's facts. `PayFree` is gone:
    the restrict lemma takes `PayOff` (the other threads' parts hold no
    payload address), a new block's payload comes from the stepping
    thread's own part (`CParts.down_pay`), and the other threads' facts
    survive a view that gains it (`ThreadOK.grow`, `BlocksAt` /
    `BlockOK`). A spawn splits the spawner's part; the payloads stay
    shared.
  - *`Touch` reads payloads*: `arc_get` reads its block's payload
    (`RTouch.arcGet`), and `NodeAt` / `DataAt` / a live view may find a
    payload node. Every touch is of an owned address, or a read of a
    payload the thread's own slots reach through a handle or a share
    (`touch_seen`, `PaySeen`); every write is to an owned tree. No step
    writes a payload while its block exists (`Step.blk`).
  - *The configuration-level sweep is part of `TStep.thread`*, not a rule
    of its own: a thread's A2 step, then `Cfg.sweep`, A2's sweep with every
    thread's slot values as roots (`Cfg.vals`; `A2/Sweep.lean` is generic
    over the roots, `Mem.sweepR`, `ThreadOK.sweepR`). So no reachable
    configuration keeps a block nothing reaches (`CInv`'s second half),
    which `no_leak` needs. Thread-local runs keep `Steps0` (`reach_ok0`).
  - *`Race` counts the sweep's frees as the stepping thread's writes*
    (`SweepFrees`, `CTouch`): an address live before the step and after
    it, which the sweep then frees. `race_free` (`CInv.raceFree`): a write
    is to the writer's own part, or a payload no other thread reaches
    (`CParts.ctouch`); two threads meeting on a payload address are both
    reading; and two threads' sweeps never free one block, since some
    thread reaches it (`Reached.or`).
  - *`no_leak`*: when every thread has ended no slot holds a value, so no
    block is reached and the last sweep left none; a finished thread owns
    no tree (`ThreadOK.no_leak`, `CInv.noLeak`).
- (d2) **`arc_new` moves an allocating tree into its block**: `RhsT.arcNew`
  asks `t.holdsView = false ∧ t.hasFn = false` (`Ty.plain` and its lemmas
  are gone). `y`'s tree leaves its slot and becomes the block's payload;
  `rhs_arcNew` proves `BlkOwn` for the new block from what `Pushed` says
  of the moved tree (in no other owned tree, in no payload), and
  `covers_evalR` counts it. `HeapOK.bpay` is gone with every use. Send: an
  `arc t` with `t` view-free crosses a spawn as before (`arc_spawnOK`,
  `arc_spawnOK_viewFree`).

**What A3.1 proves now.** `A3.claim` for A2 with `Arc`: shares whose
payload is any tree of a type that holds no view and no closure (a `Vec`,
a struct of `Vec`s, a share of one), made by `arc_new`, cloned, lent by
`arc_get` (a borrow that may land in the payload through the share), and
dropped; blocks collected by reachability at the end of every step, in A2
(`Steps`) and in A3 (`TStep.thread`, over every thread's slots). On every
interleaving: no thread is stuck, no race (a payload is only read, and the
sweep frees only what no other thread reaches), and nothing is left
allocated once every thread has ended. `A2.memory_safe`, `A2.soundness`,
`A2.no_leak_end` and `A2.no_leak_panic` hold for the same language.

**Not proven here.**
- *Phase D*: the runtime frees a block at refcount 0, the model by
  reachability at the step's end. They must agree on every live binding:
  refcount 0 implies that no *live* binding reaches the block (a dead
  borrow's slot may still hold a handle into it, which the model's sweep
  counts and the runtime's count does not). This follows from the typing,
  since `arc_get`'s borrow depends on its share binding and dies with it;
  it is stated above, as the conservative sweep's obligation, and not
  mechanized.
- The count itself stays ghost: no stored `rc`, no theorem that it equals
  the number of shares (the sweep makes it unnecessary for the claim).
- A view-holding or closure-holding payload; the probes (step 4 below:
  h211 h212 h213 h288 h289 h338).

A3.0 settled that A3 imports A2 and runs A2's step on each thread's view,
so a shared block has to live somewhere A2's step can read. For `Arc` the
block goes into A2 itself. Single-threaded, an `Arc` is a counted
reference (as `Rc` is in Rust), and nurlc's single-threaded code already
uses `Arc` widely.

**In A2.**
- `Mem.blk : Nat → Option Blk`, with `Blk := ⟨ty, pay⟩` (the count is
  ghost, below). A block's payload
  tree is owned by the block: `HeapOK`'s one owner per allocation counts
  blocks next to slots, and `Covers` counts them too.
- `Val.arc k p`: a share of block `k`. It carries the block's payload `p`
  as ghost data, so a borrow can reach the payload through the share. The
  share can sit anywhere in a tree: a field (h288), an element, or another
  payload (h211's `Arc (Arc i)`). A share owns none of its payload's
  addresses (`ids (arc k p) = []`), and neither `Sub` nor `Top` / `Below`
  enters `p`. So ownership stays with the block, and the structural
  argument that no tree views itself (`SelfFree`) is untouched.
  `SharesOK` ties the copy to the block: `m.blk k = some ⟨u, p⟩`. A
  payload is frozen, so the copy never goes stale. `Ty.arc t` is
  owning, it holds a view exactly when `t` does, and it is never copied.
- **The first cut's payload holds no allocation** (`Ty.plain`): integers,
  structs and enums of them, and shares (`Arc (Arc i)`, h211). `arcGet`
  lends the payload as it is (`lendOf p = p`), with no handle into it, so
  no borrow ever lands inside a block. `Top`, `Below` and `Lands` stay
  exactly A2's, and a block owns only its own address. What this cut
  proves is what is new about `Arc`: counted shares, clone and drop, the
  sweep, the count across threads.
- **Why a `Vec` payload is the second cut.** A borrow into a payload has
  to reach it through a share that can sit anywhere in its root's tree.
  Two ways to model that were tried, and each runs into the same problem.
  - *A share-transparent `Top` / `Below`.* A struct may hold a share `a`
    and a view of the same block taken through another share `b`. Typing
    allows it, and it is safe, since `b` keeps the block alive. But the
    struct then views memory its own share reaches, so `SelfFree` fails.
    A2 needs `SelfFree` (`ViewsOK.dropSelf`, `keep_except`), because
    `liftE` can put a binding's own root into what it holds.
  - *A kind of its own (`Kind.share`) that alone looks through shares.*
    Banning views of a payload is then not local. A callee that returns a
    view of a borrowed parameter, called with a payload borrow, comes back
    with a `.share` view after the reroot.
  The second cut needs one of two fixes. One: a view of a payload is valid
  while its block exists, and the sweep keeps every block a live view
  reaches. Two: an invariant that a stored view never depends on its
  holder's own share.
- `RhsT.arcNew y`: `y`'s tree moves into a fresh block with `rc = 1`. The
  share is owned and holds what `y` held, since the payload views what `y`
  viewed (nothing, in the first cut below).
- `RhsT.arcClone a`: a read of share `a` that adds a new share, `rc + 1`.
  It holds what `a` holds.
- `RhsT.arcGet a`: the payload, lent: `lendOf p`, read from the share
  itself. Its entry is a borrow rooted where `a` is (`derive a … .share`),
  holding `a`'s `held`, so it ends with `a` like any borrow.
- **Dropping a share is part of freeing a tree.** Every `DropSlot` / `Frees`
  that meets `Val.arc k` does `rc − 1`, and at 0 drops the payload tree in
  turn. A share is then released correctly wherever it lands (a field, a
  `Vec` element, a `sink` parameter, an assignment's old value) with no
  drop glue, so A3.1 does not wait for A2-drop.3 (#253).
- **Frozen is typing.** No rule writes through an `arc t`: it is no
  `push` / `assign` / take-out target, and `arcGet` lends a borrow, which
  `canDo` refuses every write.
- **Counted is an invariant.** `rc k` is the number of `Val.arc k` leaves in
  slot trees and payloads. A payload holds only shares made before it, so
  shares form no cycle, and when every share has been dropped every block
  has been freed (`no_leak`).

**The first cut** asks the payload's type to hold no views and no
closure (`t.holdsView = false`, `t.hasFn = false`). A payload is then
valid as long as it is owned (`WFv`, no `ViewsOK`), and a share holds
nothing (`held = []`). All six probes are of this shape: Vecs, structs and
a library handle. A view-holding payload (`Arc` of a struct of views)
needs every share to keep the payload's sources alive, which is a later
step.

**In A3.**
- `Cfg` gets the blocks next to `alloc` and `nid`, shared by every thread.
  A thread's part is its own trees. The payloads are in no part.
- Every holder reads them: the frame lemma runs a step on a thread's part
  plus the blocks.
- A payload address is only read (frozen), so two threads meeting there
  is no race.
- `rc` is a word that `arcClone` and a share's drop change atomically.
  They are marked atomic in `Touch`, as nurl's runtime's refcount is.
- Send: `Ty.arc t` crosses when `t` holds no views. That is A3.0's
  `SpawnOK` question asked of the parameter's type, unchanged.

**Order.**
1. A2: `Blk`, `Val.arc`, `Ty.arc` through every function on values and
   types (mechanical, but it touches every module).
2. A2: the three rules and the drop, with `memory_safe` / `no_leak_end` /
   `no_leak_panic` re-proven.
   - The count is ghost: `rc k` is the number of `Val.arc k` leaves in
     the store (slot trees and live payloads). A share frees nothing by
     itself (`Frees.arc`), so `Frees` keeps its footprint (`other` / `le`
     / `freed`, and A3's `lift` / `restrict`) unchanged.
   - Every step ends with a `Sweep`: a block that no share reaches is
     removed and its payload tree freed. That repeats, since a payload's
     own shares may have been the last of theirs; a payload holds only
     older shares, so this terminates.
   - The runtime frees at the last drop, inside the same step, and no
     read follows a drop within one step, so the two agree at every step
     boundary.
   - In A3 the sweep is a configuration step over all threads, since the
     count is over all of them. The refcount word that a clone and a drop
     change is marked atomic in `Touch`.
3. A3: the blocks in `Cfg`, the frame lemma with payload reads,
   `Touch` / `Race` with atomic `rc`, and `A3.claim` again.
4. Probes h211 h212 h213 h288 h289 h338 to A3.1; CLAIM.md and README.md.

## A3.2's mechanization (`Locked`)

**Status.** `check.sh` is green with lock blocks, lock shares and the
three rules in A2 and A3. `A2.memory_safe`, `A2.soundness`,
`A2.no_leak_end`, `A2.no_leak_panic` and `A3.claim` are re-proven for A2
with `Locked`, and `CLAIM.md`, `README.md` and `check.sh` say A3.2's
first cut is proven. The probes h267 (`locked_take` / `locked_restore`)
and h358 (an `Rc` in a `Locked`, the Send question) wait for what this cut
leaves out. A3.2's second cut (below, after A3.6's) adds `arc` and lock
shares in a lock's payload, and `locked_take` / `locked_restore` with
h267's rule.

**Where a lock lives.** In A2, as an `Arc` does: a lock is a second kind
of block. This answers the open question below. Single-threaded, a lock is
a cell whose payload one scope at a time checks out.
- `Blk := ⟨ty, kind, pay : Option Val⟩`, `BKind := arc | lock`.
  - `Blk.tree` is what a block owns: its payload, or nothing while a lock's
    payload is checked out. `BlkOwn`, `PayAddr`, `PayIn` and `Unreached`
    use it.
  - `Blk.rd` is what holders read: an arc block's payload, and nothing of a
    lock block's. `NodeAt`, `DataAt`, `InPay`, `Refers` and A3's payload
    reads use it.
- The design's `held : Option Nat` is not stored. The holder is the thread
  whose lock scope (`scopeL k t x s`) has the payload in slot `x`.
  Meanwhile the block holds `none`.
- `Ty.lk t` / `Val.lk k` is a share of lock block `k`. It carries nothing,
  since the payload changes and no one reads it through the share. It owns
  no address and frees nothing (`Frees.lk`). It keeps its block alive for
  the sweep (`Refers` through `Val.share k none`).
- `ArcIn`'s payload index is an `Option`, `none` for a lock share.
  `SharesIn` asks `ShareFits`: an arc share fits its arc block, and a lock
  share fits a lock block of its type.
- `Ty.ok (lk t)` asks that `t` hold no view and no share
  (`!t.holdsView && !t.hasArc`). So a lock's payload keeps no block alive
  (`MInv.blocks`' fourth conjunct).

**The rules.**
- `Rhs.lockNew t y` (`locked_new`): `y`'s tree moves into a fresh lock block
  at `nid` (`EvalR.lockNew`, `rhs_lockNew`, `out_lkShare`). The tree holds
  no view, no closure and no share.
- `Rhs.lockClone a` (`Locked_share`): a new owned share (`out_lockClone`).
- `Stmt.withLock a x s` (`locked_update a f`, with `f`'s body as `s` and
  its argument as `x`). This refines the design's `lock_with` as a `callc`
  with an `inout` argument.
  - When `a`'s block has its payload, the payload is checked out
    (`pay := none`) into `x`, owned. An integer payload is a plain integer
    binding.
  - `s` then runs in `x`'s lock scope `scopeL k t x s` (`Step.withLock`).
    The scope carries the payload's type `t` as ghost data.
  - Typing: `StmtT.withLock` gives `x` the entry `lockE t` (owned, holding
    nothing; `intE` for an integer) and ends `x` as a `letv` does. Two
    premises keep the model faithful to the runtime (below): `a` is a root
    (`Ea.mode.isRoot`) that the body does not name (`a ∉ s.vars`), and `x`
    is live in the body's output context. `StmtT.scopeL` types the run-time
    scope as a `scope` and needs neither, since `Release` is total.
- The scope's end gives `x`'s value back (`Step.scopeLSkip`, `Release`).
  - `Release.put` applies when the block is there with its payload checked
    out and `x`'s slot can give it back (`Giveable`: an owned tree, since
    A3.3 one of the payload's type, or an integer for an `int` lock).
  - Otherwise `Release.drop` drops `x`'s slot as a scope's end does. With
    `StmtT.withLock`'s premises a typed program's normal-path end is always
    a `put` (the block outlives the body, and `x` holds a `t` there); `drop`
    keeps the rule total. That the end is a `put` is argued below, not
    proven as a lemma.
  - `Release` is total by construction, so no invariant has to say that the
    frame's `x` holds what was checked out of block `k`. Such an invariant
    (`LockOK`) was tried and dropped: keeping it at `scopeLIn` needs facts
    from the typing.
- A `withLock` on a block whose payload is out has no step, so the thread
  waits (`Blocked m s`, through the evaluation contexts).
  - `Stuck` excludes `Blocked`. `memory_safe` therefore says that no thread
    is stuck on memory, and a thread waiting on a lock is not stuck.
    Deadlock freedom is not claimed, as before.
  - Progress (`progress'`, `ThreadOK.progress`) has three cases: done,
    blocked, or a step.

**Faithful to the in-place runtime.** `stdlib/std/thread.nu`'s
`locked_with` / `locked_update` run `f` on the payload in place, inside the
lock's own memory. The model checks the payload out into `x` and back. The
two agree when the lock outlives the body and `x` holds the payload again
at the body's end. Without that, a program the model accepts is a
use-after-free (the lock freed under `f`, then unlocked) or a double free
(a moved-out payload freed where it went and again with the lock) at run
time. `StmtT.withLock` asks for both:
- *The lock outlives the body.* `a`'s slot holds a share of the block, and
  nothing in the body changes that slot.
  - The body does not name `a` (`a ∉ s.vars`), so no move, drop, assignment
    or `sink` argument of the body touches it. A call's callee runs in
    fresh variables, and an `inout` argument is one the body names.
  - No closure changes `a` either: a closure changes a binding by name only
    if it is a `Vec` (`CapsOK`, `NamesFree`), and `a` is a lock share.
  - `a` is a root (`Ea.mode.isRoot`): an owner, whose slot holds the share,
    or a borrowed parameter, whose share is the caller's, frozen for the
    call. A local borrow (a field or element of a struct or `Vec` that holds
    the share) is refused: the body could change its owner. (Since A3.2's
    rest, below, such a lock is handed over first, so the body runs on an
    owner of the share: `Stmt.withLockElem`, `Stmt.withLockField`.)
  - The suggested form, typing the body with `F ++ [a]` and stepping to
    `scopeL k t x (frozen [a] s)`, does not get through the renaming
    lemma (`StmtT.ren`). It types a callee's body under the call's frozen set
    `S.Fc` whatever the callee froze, and `RSetup.OK.Fcout` keeps every
    callee binding out of `S.Fc`. A frozen `a` would mean generalizing every
    renamed rule's frozen set. Not naming `a` is invariant under renaming
    (`Stmt.vars_rename`, `RSetup.OK.inj`) and gives the same guarantee for
    a lock share.
- *`x` holds a `t` at the body's end* (`∃ E, Δ x = some E ∧ E.live`). An
  assignment that replaces it is fine: `assign` keeps an owned binding
  owned, and an integer an integer. The body may not leave it moved out.
- *The panic path over-approximates the runtime* (since A3.3).
  `locked_with` has no unlock on the panic path, so the lock stays held and
  other threads wait; the value stays in the lock until the last share's
  drop frees it. A3.2's `scopeLP` freed `x` at the panic and left the block
  checked out. A3.3 makes `scopeLP` give the payload back (`Release`), as
  `RwLocked`'s write guard's drop does (A3.3's mechanization, below). For
  `Locked` this is more behaviours than the runtime has: other threads may
  take the lock again, where the runtime's wait. The value stays in the
  block, as the runtime's stays in the lock.

**A2's proof.**
- `acquire_pres`: taking the payload out of a lock block is a move out of
  an owned tree (`RhsPost` / `RhsOut` for `lockE t`). `covers_acquire`
  hands the payload's addresses from the block's `tree` to `x`'s.
- `step_release`: the way back (`HeapOK.release_put`,
  `covers_release_put`, `MInv.change` and `MInv.grow`).
- `BlkLe` is weakened to `BlkKeep`: an arc block is kept exactly, and a lock
  block is kept as a lock block of its type (`BlkLe.arc` / `.lock` /
  `.rd`). `Reached.mono`, `CatchOK` and `InPay.grow` follow it.
  `MemCodes` reads a block's `tree` and (A3.3) what its holders read
  (`MInv.blkCodes`).

**A3's proof.**
- *No touch for the lock word.* Taking a lock and giving it back change
  only the lock's word. The runtime's mutex changes that word atomically,
  which is trusted base, beside DRF-SC.
  - `Touch.scopeL` passes through to the body.
  - `scopeLEnd` / `scopeLUnwind` count `x`'s tree as written. That
    over-approximates both the give-back and the drop.
- *The partition moves with the payload.* A checked-out payload leaves
  `payPart` for the holder's part, and a given-back one goes the other way.
  - `CParts` gets no new field, since `CParts.thread_of` computes the
    stepping thread's new part from its view.
  - The other threads' facts survive the move by `ThreadOK.move` /
    `inv_move`. Their address space is their owned trees and the live
    payloads, and their blocks are kept up to `BlkLe`.
  - `ThreadOK.move` / `inv_move` are the general form of A3.1's
    `ThreadOK.grow` / `inv_grow`. Those are gone, with `BlkGrow`.
- *Where a payload's address comes from* (`Step.payAt`, `EvalR.payAt`).
  After a step, an address in block `k`'s payload was in the same block's
  payload before, or in the stepping thread's own trees (a new block's
  payload, or a lock's given back).
  - This replaces A3.1's `CParts.down_pay` in `race_free`'s sweep case
    (`CParts.ctouch`).
  - `CParts.ctouch` and `CInv.raceFree` no longer take the frame lemmas.
- `Step.ownedId` gains a third case: a checked-out payload's addresses
  were a payload's (`PayAddr`). `Step.avoids` takes `PayOff`, which says
  the other parts hold no payload address (`Avoids.mono3`).
- Send: `(Ty.lk t).holdsView = t.holdsView`, which `Ty.ok` makes `false`
  (`lk_spawnOK`). So a lock share crosses a spawn by `SpawnOK`, unchanged.
  Sync holds because a lock's payload is read by no one while it is in the
  block, and is in its holder's part while it is checked out.

**Simplifications in this cut.** Each is a restriction, and sound as
stated.
- A lock's payload holds no share (`hasArc = false`). It also holds no view
  and no closure, so it is Send. A `Locked` of an `Arc` waits for payloads
  that keep blocks alive. (A3.2's second cut lifts this for `arc` and lock
  shares.)
- `withLock` takes a root that the body does not name, so a lock reached
  through a local borrow (a field or an element) is refused. (A3.2's rest
  hands it over first: an element by `withElem`, a field by taking the
  struct apart, and a borrow of what the function does not own to a
  function that takes it `in`.)
- `locked_take` / `locked_restore` are not separate rules. (They are since
  A3.2's second cut.)
- The update's body is a statement in place, not a closure called through
  a package. (A3.2's rest: or a function of the program, `ApplyFn`.)

**Not proven here.**
- deadlock freedom;
- that a typed program's lock scope ends in a `put`, as a lemma (it would
  need an invariant tying each `scopeL k` frame to block `k`);
- shares in a lock's payload (A3.2's second cut: `arc` and lock shares, not
  cell shares);
- the probes h267 h358;
- that the runtime's lock word (`stdlib/runtime_locked.c`) is the lock
  block's state (phase D). A relock by its holder, which the model's thread
  waits for (`Blocked`) or, since A3.3, panics at (`Step.waitPanic`),
  panics in the runtime since Agora #455; it was undefined while a default
  pthread mutex was held across the closure.

## A3.3's mechanization (`RwLocked`, `% Frozen`)

**Status.** `RwLocked` is mechanized. `check.sh` is green with its rules in
A2 and A3, and `A2.memory_safe`, `A2.soundness`, `A2.no_leak_end`,
`A2.no_leak_panic`, the `DynCell` theorems and `A3.claim` are re-proven with
them. An `RwLocked` is a lock block (A3.2's), and a reader reads it through
a *view*, a third kind of block that its read guard shares. A panic now
gives a lock scope's payload back, and a thread that waits may panic
instead.

The rest of A3.3 is mechanized too (*The rest*, below): `rw_try_read` and
`rw_try_write` are right-hand sides that answer `none` where `rw_read` and
the write check-out would wait, and `wguard_get` and `rw_get` are forms of
the rules there are, with no new rule. `check.sh` is green and the same
theorems are re-proven.

**Where an `RwLocked` lives: a lock block, read through views.** The draft
(the `rw` block above) stored a reader count in the block and lent the
payload to readers straight from it. That needs
an invariant the proof does not have: when the count goes back to 0 and a
writer takes the payload, no binding may still land a borrow in it. A
borrow lands in a payload through a share dependency anywhere in a live
block's payload (`Landed`'s share case, `InPay`), and through a borrowed
root's handles (`NodeAt`), neither of which says which reader it came
from. The typing ends every such borrow with its reader (`exitScope`), but
the invariant cannot tell a live borrow from the reader's from one that
outlived it, so the step where the count reaches 0 would have to show that
no live entry anywhere lands in the payload. Instead:
- A view is a block of kind `BKind.view`. Its payload is a share of the
  lock block and a copy of the lock block's payload,
  `pair (lk k) p`, at type `prod (lk t) t`. It owns nothing
  (`Blk.tree` is `.int 0`), and its holders read its payload (`Blk.rd`).
- `HeapOK.views` (`ViewsAt`): every view reads its lock block's payload as
  the block holds it now. So a view lives only while the payload is in,
  and no step changes the payload while a view of it lives.
- A view is frozen while it lives, as an `arc` block (`BlkKeep`: a block
  that is not a lock block is kept exactly). An `arc` share may name one
  (`ArcBlk`, `ShareFits`, `ValOK.arc`). So a reader's borrows are A3.1's
  `arc_get` borrows into a frozen payload, with all of A3.1's machinery.
- A view is collected as an `arc` block is: by the sweep, once no slot
  reaches it. A reached view reaches its lock block, through the share in
  its payload (`Reached.pay`), so the sweep never frees a payload a view
  reads (`HeapOK.sweepR`'s `views`).
- The reader count is ghost: it is the number of views of the block that
  are still reached, as A3.1's reference count is the number of shares.
  The writer bit is the payload being checked out (`pay = none`).
- `RwLocked A` is `Ty.lk A`, a `Locked A`. A second type would add a case
  to every function on types and values for no difference in memory, as
  A3.4 found for `Atomic`.

**The rules.**
- `rw_new` is `Rhs.lockNew`, `RwLocked_share` is `Rhs.lockClone`, and
  `RwLocked_drop` drops a share (`Frees.lk`), as for `Locked`.
- `Rhs.rwRead a` (`rw_read`), typed by `RhsT.rwRead`: `a` is a live share
  `lk t`; the result is an owned `arc (prod (lk t) t)` share that holds
  nothing, the read guard.
  - `EvalR.rwRead`: the block's payload `p` is in. A new view
    `⟨prod (lk t) t, view, some (pair (lk k) p)⟩` is made at the key `nid`,
    and the guard is its share `arc nid (pair (lk k) p)`.
  - `RBlocked`: while a writer has the payload checked out, `rw_read` has
    no step and the reader waits.
- `rguard_get g` is `arcGet g` and then the second field (`Rhs.snd`).
  `Stmt.withRead a g y x s` spells the whole read scope: the guard `g`,
  what `arcGet` lends through it (`y`), and the payload, lent frozen
  (`x`). `rguard_get_path`: what `x` depends on is `⟨g, share⟩` and nothing
  else (`getE`'s `derive g E .share`, then `projE`).
  - `ThruOK.noShare` refuses every change through it (`StmtT.editB`), and
    the other changes need an owner or an `inout` binding (`canDo`,
    `paramOK`: a `push`, a `free`, a `sink` or `inout` argument). A copy of
    it (`.var x`, `: ~`) is a borrow with the same dependency, which
    `paramOK` refuses as an `inout` argument.
  - `exitScope g` ends it with the guard: no live borrow of the payload
    outlives the guard's scope.
- `rw_write` + `wguard_update`, `rw_update`, `rw_apply` and `rw_set` are
  `Stmt.withLock` (A3.2's, with its faithfulness premises: the body does not
  name `a`, `a` is a root, `x` is live at the end). `Step.withLock` now
  also asks that no view of the block lives (`¬ HasView`); `Blocked` says
  the writer waits while the payload is out or a view lives.
- The atomic and channel steps that change a lock block's payload
  (`EvalR.atomic`, `chanSend`, `chanRecv`, `chanClose`) ask the same, and
  `RBlocked` waits likewise. A source `Atomic` or `Channel` has no reader,
  so for them nothing changes; for a model program that reads one, the
  wait keeps `ViewsAt` and race freedom.
- **The panic path releases.** `Step.scopeLP` ends a lock scope that a
  panic unwinds through with `Release`, as its normal end does: the
  payload goes back to the block (or the slot is dropped, if `x` holds
  nothing to give). A read guard's release on a panic is `scope g`'s drop
  of the guard on the way out, after which the view is swept. `Giveable`
  asks for a tree of the payload's type (`WFv`, moved to `Semantics.lean`), so
  a give-back keeps the block well formed with no typing at hand.
- **A thread that waits may panic instead** (`Step.waitPanic`): a
  statement that waits (`Waits`: a `withLock` of a lock that is checked out
  or viewed, or a binding or an assignment whose right-hand side waits)
  steps to a panic and leaves the store as it was. The panic unwinds through
  the scopes around it as any other.

**A2's proof.**
- *The kinds.* `Blk.rd` of a view lies in its lock block's tree
  (`ViewsAt.rd_ids`, `HeapOK.rd_ids`, `HeapOK.rd_sub`; `Blk.rd_ids` is
  gone). This keeps the uniqueness of nodes found in memory (`pay_unique`,
  `owned_pay_head`: two views of one block read the same nodes) and their
  liveness (`HeapOK.inMem_alloc`).
  `ViewsAt` holds through every step:
  - a new block that is no view (`ViewsAt.fresh`);
  - a lock block's payload changed, checked out or given back while no
    view of it lives (`ViewsAt.setLock`);
  - a checked-out block has no view (`ViewsAt.noView`);
  - the sweep (above).
- `rhs_rwRead`: the new view owns nothing (`BlkOwn`), reads the block's
  payload (`ViewsAt`), and its payload is well formed with its share named
  (`BlocksIn`). The guard is `out_share` of an `ArcBlk`. `covers_evalR`'s
  case moves no address.
- `arc_get` of a guard is A3.1's `out_arcGet`, through `ArcBlk` (`arc_val`,
  `share_lands`, `arcBlk_shares`).
- `atomic_pres`, `setPay_pres` (and so the channel steps) and
  `acquire_pres` take the step's `¬ HasView`.
- *The panic path.* A panic's unwinding may now change blocks:
  `panic_unwind` gives `BlkBack` (each block as it was, or a lock block given
  back a payload of its type; `Release.back`).
  - `MInv.unwind` (a destructor's frame) is the invariant over the unwound
    slots with the blocks as they were (`MInv.unwind0`, over
    `HeapOK.unback`), grown to the blocks given back (`MInv.grow`,
    `MInv.blocks_back`).
  - `catchP` composes `CatchOK`'s blocks with `BlkBack`, and takes the
    blocks' invariant from `MInv.blocks_back`.
  - `Release.exists` gives the step on both paths (progress).
- *Waiting panics.* A statement that waits opens no scope (`Waits.spine`),
  so `panic_unwind`, `no_leak_panic` and the frame lemmas take
  `waitPanic` as they take `letvP`.

**A3's proof.**
- *Readers read the shared part.* A view owns nothing, so the payload part
  (`payPart`, by `Blk.tree`) and the parts are unchanged by a read. What a
  reader reads (`RTouch.arcGet`, and the nodes `NodeAt` / `DataAt` find
  through a view) are addresses of the lock block's tree, in the shared
  read-only part. `PayOff` now covers what holders read, and
  `ViewsAt.rd_reached` gives the lock block, reached from the reader's
  slots, for `race_free` (`CParts.ctouch`).
- *A writer is alone.* The payload is checked out only when no view lives,
  so no reader reaches it; once it is out it is in the writer's part (A3.2's
  check-out), and no view can be made of it (`RBlocked`).
- *Readers only read.* No step writes a view's payload, and none changes
  the lock block's while a view lives (`¬ HasView`), so readers on two
  threads meeting at an address are both reading.
- *The other threads' facts.* Their views are kept exactly (`BlkKeep`),
  and a new view is a fresh block (`ThreadOK.move` unchanged).
  `BlockOK.view` carries `ViewsAt` to the other threads' heaps
  (`BlocksAt.views`). A new view's payload is the lock block's
  (`EvalR.payAt`: a view owns no address), and a guard owns none
  (`EvalR.ownedId`).
- *The panic path.* A give-back on the way out is of the thread's own tree,
  as on the normal path (`Release.payAt`, `Release.ownedId`, `Release.grows`;
  `Touch.scopeLUnwind` already counted it as written). A waiting panic
  touches nothing (`Waits.of_eq`, `RBlocked.of_eq`, moved to
  `A2/Panic.lean`).
- *The count and the writer bit* are the runtime's rwlock, trusted base
  beside the lock word (A3.2) and DRF-SC. The model has no address for
  them.
- Send: a guard is an `arc` of a view-free type, so `arc_spawnOK` lets it
  cross (below). (Since `% NotSend` guards, below, the type still lets it,
  and the crossing check refuses it.)

**Faithful to the runtime** (`stdlib/std/rwlock.nu`).
- *In place.* A reader's borrows are the lock's own payload addresses,
  read in place, as `rguard_get` lends `. ( shared_ptr … ) val`. A writer's
  `withLock` checks the payload out to `x` and back, which A3.2's
  premises make agree with `wguard_update`'s in-place `inout` (A3.2,
  *Faithful to the in-place runtime*).
- *The release on a panic.* A guard's drop runs on the drop journal
  (docs/MEMORY.md §7.2): a write guard's gives the payload back
  (`scopeLP`'s `Release`), a read guard's drops the guard (`scope g`'s
  `scopeP`), after which other threads read and write the value.
- *The self-deadlock panic.* Writing a lock its holder reads, or reading or
  writing one it writes, panics at run time. The model's thread waits for
  itself (a writer for its own view, a reader for its own check-out), and
  `Step.waitPanic` lets it panic.
- *A second read by the same holder is counted*, not taken again: each
  `rw_read` makes its own view, and the writer waits for all of them.
- *When the read ends.* The runtime unlocks at the guard's drop; the model's
  view lives until no slot reaches it, which may be later, when a dead
  borrow's slot still holds a handle into the payload. The two agree on
  every live binding: no live borrow of the payload outlives the guard
  (`rguard_get_path`, `exitScope`). This is A3.1's phase-D obligation for
  `Arc`, unchanged, and it is not proven here. Until it is, a writer the
  runtime lets in may wait in the model.
- `% NotSend` on guards is not modeled: a model guard may cross a spawn
  (more programs, all safe). `% Frozen` is the share dependency. (Closed
  by `% NotSend` guards, below: the crossing check refuses a value that
  reaches a guard, `NoGuard`, so no guard crosses.)

**The rest: `rw_try_read`, `rw_try_write`, `wguard_get`, `rw_get`**
(`A2/Semantics.lean`, `A2/Typing.lean`; the derived forms in
`A2/Syntax.lean`, their typing in `A3/Defs.lean`).
- `Rhs.rwTryRead a` (`rw_try_read`): `rw_read`, answering an option (A2's
  `Option` is `sum int _`) and never waiting.
  - `EvalR.rwTryRead`: with the payload in, `rw_read`'s new view, and its
    share handed back as an owned `some` (`inr`).
  - `EvalR.rwTryReadNone`: with the payload checked out, where `rw_read`
    waits, `none` (`inl 0`), the store as it was. It has no `RBlocked`
    case, so it never waits.
  - `RhsT.rwTryRead`: `a` a live `lk t`, `t.hasCell = false` (a read guard
    lends to every reader at once: no library handle, as A3.5's second cut
    asks of `rw_read`); the result is `tryReadE t`, an owned option of a
    guard, holding nothing.
  - `Stmt.withTryRead a o g y x s e` spells the match: on `none`, `e`; on
    `some`, the guard moves out of the option into `g` (`taker`), and
    `withRead`'s read scope runs under it (`Stmt.readWith`, which
    `Stmt.withRead` is now built on). `tryRead_some`: the guard moved out
    is `rw_read`'s entry (`guardE t`), so `rguard_get_path` and `exitScope g`
    hold as for `rw_read`. `StmtT.withTryRead` types the whole.
- `Rhs.rwTryWrite a` (`rw_try_write`'s answer): `some` (`inr 0`) where a
  write's check-out would not wait (the payload in and no view of it,
  `EvalR.rwTryWrite`), `none` (`inl 0`) where it would
  (`EvalR.rwTryWriteNone`); the store as it was either way, and no wait.
  `RhsT.rwTryWrite`: an owned `sum int int` (`tryWriteE`).
  - `Stmt.withTryWrite a o x s e`: on `none`, `e`; on `some`, A3.2's
    `withLock a x s`, with its faithfulness premises (`StmtT.withTryWrite`).
  - **Why two steps.** A write guard is no value in the model: it is the
    lock scope `scopeL`, which only `withLock`'s step makes, and which gives
    the payload back on both paths. An atomic try would be a statement of
    its own, a `withLock` with an else branch, which every lemma over
    statements would get a case for. A try that took the payload out as a
    value (`lockTake`) would leave the block empty on a panic, where the
    runtime's write guard gives it back. So the answer and the check-out
    are two steps. Another thread may take the lock between them, and the
    check-out then waits (or panics, `Step.waitPanic`) where
    `pthread_rwlock_trywrlock` takes it at once. These are more runs than
    the runtime has, and every one of the runtime's is a run of the model
    (the two steps back to back), so the claim covers it.
- `wguard_get` needs no rule. It is the write scope's `x` lent: `: ~ y (
  borrow x )`, a borrow whose one dependency is `x` itself, an owner
  (`wguard_get_path`). What is done to its containers changes the value: a
  change of the lent `Vec`'s elements is typed (`StmtT.wguardGet`, a
  truncation through `editB`), its effect on `x` the owner's own. A read
  guard's lend, whose dependency is a share, refuses every change
  (`rguard_no_change`). A scalar field changes in place by an assignment
  to `x` in the body (`wguard_update`).
- `rw_get` is a read scope whose body copies out:
  `Stmt.rwGet a g y x c z f` is `withRead a g y x` around a call of `f` on
  the lend `x`, whose result `c` moves to the caller's `z`.
  - **The copy is `mem_dup`**, a deep copy of a view-free value. The calculus
    has no deep-copy step, so `mem_dup` at the payload's type is a function
    of the program with `mem_dup`'s summary (`DupFn`): it takes a `t` lent
    (`in`) and hands back a `t` of its own, lending (`lends = []`) and
    holding (`rholds = []`) nothing. A lock's payload holds no view, so a
    deep copy of it depends on nothing it was copied from; `ProgOK` checks
    the function's body against the summary.
  - `dup_call`: the call on the payload's lend (which depends on the guard
    through a share and holds nothing) is typed, and its result's entry
    borrows from and holds nothing, so `exitScope g` leaves the copy
    (`copy_outlives`).
  - `StmtT.rwGet` (A3.2's and A3.3's rest, below) types the whole as one
    statement, with every scope's end: the context after is the one before,
    `z` holding the copy.
- `wguard_apply`'s result is the write scope's call of the closure on `x`,
  its result moved out (`Stmt.callOut`, `StmtT.wguardApply`), and
  `rw_apply` is `locked_apply`'s form (`Stmt.lockedApply`): A3.2's and
  A3.3's rest, below.

**A2's and A3's proof of the rest.** The cases of `Rhs.rwTryRead` are
`rw_read`'s, with the guard wrapped (`rhs_pres` through `out_ownNoView`,
`guardTy_ok`); its `none` and both of `Rhs.rwTryWrite`'s are
`chan_try_recv`'s `none`: an owned option of an integer, the store as it
was. `covers_evalR`, `evalR_exists`, `EvalR.codes`, `EvalR.blk`,
`EvalR.leafKeep`, `Rename`, `Wf`, `NameWf`, `SrcKeep`, and A3's
`EvalR.restrict`, `EvalR.lift`, `EvalR.borFree`, `EvalR.grows`,
`EvalR.ownedId`, `EvalR.payAt` and `EvalR.cellKeep` get them. A try touches
what `rw_read` does: nothing (a view owns no address; the count and the
writer bit are the runtime's rwlock, trusted base).

**Simplifications in this cut.** Each is a restriction, and sound as stated.
- A payload holds no share, no view and no closure, as a `Locked`'s
  (A3.2).
- `wguard_apply`'s result, as `rw_apply`'s, is an assignment in the body,
  not a rule of its own. (Since A3.2's and A3.3's rest, a form with its own
  typing lemma: `StmtT.wguardApply`, `StmtT.lockedApply`.)
- The guards are scoped bindings; a guard moved into a struct or a
  `Vec` keeps its view as long as it lives, as the runtime's keeps the lock.

**Probes.**
- h364 `dyn_inout_method_through_a_read_guard`: a trait object lent
  through a read guard, copied into a `: ~` binding and handed to a method
  with an `inout` receiver. The rule is the lend's share dependency
  (`rguard_get_path`): the copy is a borrow, and `paramOK` (`canDo`)
  refuses a borrow as an `inout` argument, as `ThruOK.noShare` refuses a
  change through it. The probe's payload, a trait object, is a closure,
  which this cut's payloads exclude; the rule does not depend on it.
- h317 `frozen_asserted_over_a_cell`: a program's own `% Frozen` struct of
  a `Cell`, in an `RwLocked`, written through read guards on two threads.
  The write through either guard is a change through the frozen lend,
  refused by the same rule. The `Cell` is a library handle whose copies
  are one state, and its Sync question is A3.5's.
- h357 `rwlocked_of_a_library_handle_on_two_threads`: an `RwLocked` of a
  `PNCounter` crossed to a thread while the spawner kept a share of the
  counter. A writer under the lock and the spawner with no lock changed it
  together. This is the crossing check for library handles (A3.5:
  `mem_send_check`, an `RwLocked`'s value facing the Sync question where
  it crosses). This cut's payloads hold no share, so a library handle is
  not a payload here.

**Not proven here.**
- deadlock freedom, and that a waiting reader or writer is ever let in;
- A3.1's phase-D obligation, which here is that the runtime's unlock at the
  guard's drop agrees with the model's sweep of the view on every live
  binding;
- payloads that hold shares, views or closures, and library handles in a
  payload (A3.5);
- that `rw_try_write`'s check-out after a `some` never waits (the model's
  two steps let another thread in between, above), and that a `none` is
  answered only where the runtime's would be: a view lives until the sweep,
  so a try may answer `none` after the runtime's guard is dropped (A3.1's
  phase-D obligation again);
- `rw_get` as one typed statement, and `mem_dup` as a step of its own.
  (Closed by A3.2's and A3.3's rest, below: `StmtT.rwGet` types the whole,
  and `mem_dup` needs no step, its call being typed by its summary,
  `DupFn`.)
- a typed program over these rules (a probe's encoding, as
  `A2/DynCell.lean` types `pick`);

## A3.4's mechanization (`Atomic`, channels)

**Status.** `Atomic` and channels are mechanized. `check.sh` is green with
their operations in A2 and A3, and `A2.memory_safe`, `A2.soundness`,
`A2.no_leak_end`, `A2.no_leak_panic`, the `DynCell` theorems and
`A3.claim` are re-proven with them. A channel is a lock block whose payload
is its queue and its closed flag, and `chan_send`, `chan_recv`,
`chan_try_recv` and `chan_close` are primitive rules on it (Channels,
below).

**Where an `Atomic` lives: in an integer lock block.** The draft gave it a
third block kind. The cut uses A3.2's lock block of type `int` instead.
- An `Atomic` holds one integer, which owns no address. Its shares, its
  creation and its drop are exactly a lock's:
  - `atomic_new i x` is `Rhs.lockNew .int x`;
  - `Atomic_share` is `Rhs.lockClone`;
  - `Atomic_drop` drops a share, which frees nothing (`Frees.lk`);
  - the sweep frees the block once no thread's slot reaches it.
- A kind of its own would add a `Ty` and a `Val` case to every function on
  types and values, and a `ShareFits` case, for no difference in memory.
  The type `Atomic` is `Ty.lk .int`.
- The cost: a model program may also `withLock` an `lk int`. An operation
  on a word that is checked out then waits (`RBlocked`, below). A source
  `Atomic` has no `locked_update`, so it is never checked out.

**The rules.**
- `AOp` (`load`, `store`, `add`, `sub`, `swap`, `max`, `cas`) and
  `AOp.run op n x y`. It gives the answer and the new word from the word `n`
  and the arguments, as `atomic.nu` does:
  - `add`, `sub`, `swap` and `max` answer the old value;
  - `store` answers 0;
  - `cas` answers 1 when the word was `expect`, else 0.
- `Rhs.atomic op a e1 e2`, typed by `RhsT.atomic`: `a` is a live share of
  type `lk int`, `e1` and `e2` are integer expressions, and the answer is an
  integer (`intE`).
- `EvalR.atomic`: one step. It reads the word `n` of `a`'s block (a lock
  block of `int` with its payload in), writes `(op.run n n1 n2).2` and
  answers `(op.run n n1 n2).1`.
- `RBlocked m r`: an atomic operation whose block has its payload checked
  out. `Blocked` reads it at `letv`, `assign` and `letd`, the statements
  that run a right-hand side. `evalR_exists` takes `¬ RBlocked`, and
  progress answers `Blocked` otherwise.

**A2's proof.**
- `atomic_pres`: the block is kept (`BlkLe.setLock`, moved before
  `rhs_pres`). Its tree owns no address before or after (`BlkOwn`), and
  `BlocksIn` holds for the new word (`WFv.int`).
- The answer is a plain integer (`intE_out`).
- `covers_evalR`'s case: no payload address moves.
- `Codes`: an integer is a leaf.
- `Rename`, `Wf`, `NameWf`, `SrcKeep`: the expression cases.

**A3's proof.**
- *The word is no address*, as the lock word and `Arc`'s count are not.
  An atomic operation touches nothing (`Touch` and `Race` are unchanged),
  so no "both atomic" mark is needed: no address is ever touched
  atomically.
- The operation changes one block's word: `Grows` (`BlkLe.setLock`),
  `EvalR.payAt` (the word owns no address), `BorFree`, `Restrict`, `Lift`.
- `RBlocked.of_eq` gives `Blocked.of_eq`'s new cases.
- Send: a share is an `lk int`, so `lk_spawnOK` covers it.
- Sync: only the atomic steps reach the word.

**Faithful to the runtime.**
- `atomic.nu`'s `Atomic` is a `shared_new` cell (`AtomicCell`):
  - `Atomic_share` is `shared_clone`;
  - each operation is one `nurl_atomic_i64_*` on the cell's word, all
    `__ATOMIC_SEQ_CST`;
  - so the model's one step on the block's word is the runtime's one
    instruction.
- The word is never a data race: every access to it is a `seq_cst` atomic
  (DRF-SC, as above).
- The cell is freed at the last share's drop. The model's sweep frees the
  block when no slot reaches it.
- The numbers differ: the calculus's integers are `Nat`s, so `sub`
  saturates where the runtime's `i64` wraps. No memory fact reads the
  number.

**Probes.**
- `thread_consumes_one_capture_frees_shared_atomic` and
  `fiber_consumes_one_capture_frees_shared_atomic`: a thread consumed one
  capture and freed the spawner's `Atomic`. In the model a share's drop
  frees nothing (`Frees.lk`), and a block lives while some thread's slot
  reaches it (`Cfg.sweep`, `Reached`, `CInv`'s second half). The spawner's
  `atomic_load` after the join is `EvalR.atomic` on a block its own slot
  reaches.
- `chan_send_then_use` (h21) maps to `RhsT.chanSend` (the channels'
  probes, below).

**Channels.** Mechanized as primitive rules: `chan_send`, `chan_recv`,
`chan_try_recv` and `chan_close` are right-hand sides, each one step on a
lock block's payload.

**Where a channel lives: in a lock block of its queue and its flag.** The
runtime's `ChImpl` is a mutex, a condition variable, a queue `Vec A`, a
`closed` flag and the waiters' lists. The model keeps the queue and the
flag, as the payload of A3.2's lock block: `Channel s` is
`Ty.lk (.prod (.vec s) .int)`, and its payload is
`pair (node s c d es) (int f)`, with `es` the queue from the front and `f`
the flag (0 is open).
- The flag is a pair's second field, not a field of `Blk` or a third
  `BKind`. Either of those would add a case to every function on blocks
  (`BlkOwn`, `BlkKeep`, `Refers`, the sweep, `ShareFits`) and on types and
  values, for no difference in memory. The pair is a lock payload as A3.2
  has it, and it is `ChImpl`'s two fields. So creation, sharing, the drop,
  the sweep and Send are a lock's, unchanged:
  - `chan_new` is `lockNew (prod (vec s) int)` of a pair of a `new s` and a
    `0` (`letv`, `pair`, `lockNew`);
  - `Channel_share` is `lockClone`;
  - `Channel_drop` and `chan_free` drop a share, which frees nothing
    (`Frees.lk`);
  - the sweep frees the block, the queue and every value still in it, once
    no thread's slot reaches it.
- The cost, as for `Atomic`: a model program may also `withLock` a channel
  (an operation on it then waits, `RBlocked`), or make one by `lockNew` of a
  non-empty queue or a set flag. The rules read the payload as it is, so
  neither is unsound. A source channel is made by `chan_new` and has no
  `locked_update`.

**The rules.**
- `Rhs.chanSend a y` (`chan_send a y`), typed by `RhsT.chanSend`:
  - `a` is a live share of type `lk (prod (vec s) int)`, and `y` a live `s`,
    handed over by `PushArg` as `vec_push` takes it (an owner moves and its
    entry dies, an integer is copied). The answer is an integer (`intE`).
  - `s` holds no view, no closure and no share: `Ty.ok (lk _)`'s condition,
    as for a lock's payload (`chan_tyok` reads it).
  - `EvalR.chanSend`: the flag is 0. `y`'s value (`TakeVal`) goes to the
    back of the queue (`es ++ [v]`), and the answer is 1. The step checks
    that the queue's two addresses are live, as `push` does.
  - `EvalR.chanSendClosed`: the flag is not 0. The value is freed (`Frees`),
    and the answer is 0.
- `Rhs.chanRecv w a` (`chan_recv a` for `w = true`, `chan_try_recv a` for
  `w = false`), typed by `RhsT.chanRecv`: through the same share, an owned
  `sum int s` (A2's `Option s`, `inl` being `none`) that holds nothing.
  - `EvalR.chanRecv`: the queue is `v :: es`. `v` moves out of the payload,
    from the front as `vec_remove q 0` takes it, and the answer is `inr v`.
  - `EvalR.chanRecvNone`: the queue is empty, and the flag is set or `w` is
    false. The answer is `inl (int 0)`, the runtime's `@ ?A { F # A 0 }`.
- `Rhs.chanClose a` (`chan_close a`), typed by `RhsT.chanClose`:
  `EvalR.chanClose` sets the flag to 1. The queue stays, for receivers to
  drain. The answer is 0.
- `RBlocked` (A3.4's, for atomics) gains the channels. Each of the three
  waits while a `withLock` has the payload checked out, and `chan_recv`
  (`w = true`) waits while the queue is empty and the flag is 0. `Blocked`
  reads `RBlocked` at `letv`, `assign` and `letd` as before, and
  `evalR_exists` gives a step in every other case.

**A2's proof.**
- `setPay_pres`: a lock block's payload is changed in place to `p'`, a tree
  of its type. Each of `p'`'s addresses was the payload's, or is taken in
  from no owned tree and no payload. Then the block is kept
  (`BlkLe.setLock`), `BlkOwn` and `BlocksIn` hold, and so does `MInv`
  (`MInv.grow`). The three rules below are its instances.
- `chanSend_pres`: `rhs_lockNew`'s argument, into a block that exists. The
  tree taken from `y` (`push_take`'s `Pushed`: in no other owned tree and in
  no payload) joins the payload, which owns it, and `y`'s slot is empty.
- `chanSendClosed_pres`: `HeapOK.freeV`'s argument (an element set out of
  range). A tree that no owner holds and no payload owns is freed, and no
  owned or payload address is.
- `chanRecv_pres`: `acquire_pres`'s argument, for a part of the payload.
  The head's addresses leave the block's tree, which keeps the rest. They
  are in no owned tree and in no other payload (`BlkOwn`), and apart from
  the rest of their payload (`Nodup`), so the head is handed over owned
  (`out_ownNoView`).
- `chanClose_pres`: the flag owns no address, so the tree's addresses stay
  as they were.
- `covers_evalR`: a sent tree's addresses become the payload's, a dropped
  tree's are not live, and a received head's are the value in flight's.
- `evalR_exists`: the block is a lock block of the share's type
  (`MInv.lk_val`). So its payload is checked out (`RBlocked`), or it is a
  pair of a `Vec` and an integer, whose addresses are live (`BlkOwn`). A
  closed send's `Frees` exists (`frees_exists`).
- `Codes`: the head's packages are the payload's (`MInv.blkCodes`).
  `Rename`, `Wf`, `NameWf`, `SrcKeep`, `TypingFacts`, `Call`: a send is
  `lockNew`'s case, a receive `lockClone`'s and a close `atomic`'s.

**A3's proof.**
- *No touch for the queue's ends.* A send, a receive and a close change
  only the payload of a lock block. No thread reads that payload while it
  is in the block (`Blk.rd` of a lock block is nothing), and it is in no
  thread's part. The runtime's mutex (`ChImpl.m`) orders the operations on
  one channel, and it is trusted base, as a lock's word is (A3.2).
  - `RTouch.chanSend` is the one new touch. It counts `y`'s tree as
    written. A closed channel's drop frees that tree, and for a move into
    the queue the touch over-approximates. The tree is the sender's own
    (`rTouch_seen`).
- *The values in the queue are in the block's payload*, in `payPart` and in
  no thread's part (`CParts.pay`).
- *The partition moves with each value.* `CParts.thread_of` computes the
  stepping thread's new part from its view, so `CParts` gets no new field.
  - Sender's part to the block: `EvalR.payAt` says a payload's address
    after the step was the same block's, or in the sender's own trees.
  - Block to the receiver's part: `EvalR.ownedId` now lets the value a
    right-hand side hands back hold a payload's addresses (`PayAddr`).
    `Step.ownedId` already had that case, for a lock's checked-out payload,
    and `Step.avoids` takes it through `PayOff`.
  - The other threads' facts survive by `ThreadOK.move`, unchanged: the
    block is kept as a lock block of its type.
- *The frame lemmas.* The queue's two addresses are a payload's, so
  `EvalR.restrict` keeps their checks through `PayOff`, as for `VecOf`.
  A closed channel's drop is of the sender's own tree. For it,
  `EvalR.restrict` takes `BorFree`, `EvalR.keep` takes `BorFree` and
  `Avoids`, and `EvalR.lift` takes the part's disjointness, as `Step`'s
  versions already did. `Frees.lift` and `Frees.restrict` move before them.
  `Grows`, `BorFree` and `RBlocked.of_eq` get the new cases.
- *`no_leak` covers values left in a queue.* They are the block's tree, and
  the configuration's sweep frees them with the block once no thread
  reaches it, so `CInv.noLeak` is unchanged.
- Send: a channel share is an `lk t` with a view-free `t`, so `lk_spawnOK`
  covers it.
- Sync: only the channel's steps reach the queue.

**Faithful to the runtime** (`stdlib/std/channel.nu`).
- `chan_send ch v` takes `ch`'s mutex.
  - On a closed channel it unlocks and answers `F`, and the value it took
    is dropped ("drops the value: nothing leaks"): `chanSendClosed`.
  - Otherwise it pushes `v` at the back of `q`, wakes a receiver and
    answers `T`: `chanSend`.
  - Either way it is one critical section, and the model's one step.
- `chan_recv ch` takes the mutex and waits, by `cond_wait` or by parking
  the fiber, while `q` is empty and the channel is open. The model's thread
  is `RBlocked` meanwhile, which is not stuck. A wake-up is scheduling: the
  model simply does not step the thread. Then an empty queue answers `None`
  (`chanRecvNone`), and otherwise `vec_remove q 0` takes the front
  (`chanRecv`).
- `chan_try_recv` answers `None` on an empty queue, whatever the flag:
  `chanRecv false`.
- `chan_close` sets `closed` to 1 and wakes the waiters: `chanClose`.
- `Channel` is a `Shared ChImpl`. `Channel_share` is `shared_clone`, and the
  last share's drop frees the `ChImpl` with whatever is still queued. The
  model's sweep frees the block, and the queue's values with it, when no
  slot reaches it (A3.1's phase-D obligation, unchanged).
- `b` is 1 or 0, and `?A` is `sum int A`, as A2 reads `Option`.

**Simplifications in this cut.** Each is a restriction, and sound as stated.
- An element holds no view, no closure and no share, as a lock's payload
  does not (A3.2). A `Channel` of `Arc`s or of `Channel`s waits for payloads
  that keep blocks alive. (A3.2's second cut types them: an element may
  hold `arc` and lock shares, not a cell share.)
- The queue's buffer never moves. Nothing views it, so `vec_push`'s
  reallocation is not observable.
- `chan_send`'s `mem_send_check` (the crossing check) is A3.5's. With no
  share in the element, there is nothing for it to refuse.
- The waiters' lists, the condition variable and `select` (`?? {}`) are not
  modeled. Neither are `chan_len` and `chan_is_closed`, each one read of the
  payload, as `chanRecvNone`'s.

**Probes.** `chan_send_then_use` (h21) maps to `RhsT.chanSend`. The send
moves `s` into the queue: `PushArg.move` kills `s`'s entry, and
`EvalR.chanSend` empties its slot. So the sender's later `string_data s` is
refused, because `s`'s entry is dead. At run time that read is a use after
the receiver's free.

**Not proven here.**
- deadlock freedom, and that a waiting `chan_recv` is ever woken;
- channels whose elements hold shares or views, and `select`;
- a typed program over the channel rules (a probe's encoding, as
  `A2/DynCell.lean` types `pick`);

## A3.5's mechanization (library handles, the crossing check)

**Status (first cut).** Library handles whose copies are one state are
mechanized, and so is the crossing check that lets one move to another
thread. `check.sh` is green with them in A2 and A3, and `A2.memory_safe`,
`A2.soundness`, `A2.no_leak_end`, `A2.no_leak_panic`, the `DynCell`
theorems and `A3.claim` are re-proven. A3's race now includes two threads
changing one handle's state, and the claim proves there is none. Closures
in shared payloads are A3.5b's (below), and trait objects A3.5c's.

The runtime it models is docs/MEMORY.md §6.5. A library handle (`PNCounter
{ ( Shared PNCounterImpl ) ctl }`, a `TcpConn`, a `Cell`) is a counted
shared block whose state the library changes in place through any copy,
with no lock. It is Send but not Sync: it may move to another thread only
with every other owner of its state. The crossing checks that at run time:
`mem_send_check [T] x what` counts the places in `x` that hold each such
block and panics if the block has more owners than that.

**Where a library handle lives: a lock block, shared by cell shares.** The
handle's state is A3.2's lock block: a payload the block owns (`BlkOwn`),
possibly allocating, checked out by one scope at a time. What differs from
a `Locked` is not the block. It is who may hold a share, so that is what
carries the difference: a share of the block is a *cell share*,
`Val.cell k`, of type `Ty.cell t`, where a lock's is `Val.lk k` / `Ty.lk t`.
- *Why not `BKind.cell` or a sync flag on lock blocks* (the draft's two
  options). Every fact about the block is A3.2's: the check-out and the
  give-back (`Release`), `BlkKeep`, `ViewsAt`, `MInv.blocks`, the sweep,
  A3's partition and frame lemmas. A kind of its own, or a flag on `.lock`,
  would have made each of them case on two kinds for no difference in
  memory, and every lock rule would have had to say which of the two it
  takes. A new value constructor touches only the functions on values,
  each in one line.
- *A lent cell share is no share*: `lendOf (.cell k) = .int 0`
  (`ValOK.cell`). So a borrowed slot never holds a cell share, and the
  slots that hold one are its owners. This makes the model's check count
  what the runtime's counts, owners and not borrows (*The crossing check*,
  below). It is also what lets the invariant be about the slots alone: a
  borrow of a handle that outlives the move it depends on is dead by
  typing, and memory cannot tell a dead borrow from a live one. (A3.5's
  third cut, below, makes a lent cell share the share, so a library
  changes and copies a handle it was lent. The check still counts owners
  only, and the invariant is still over owned slots: a live borrow is tied
  to an owner of the same thread by typing, `MInv.cell_owned`, and a dead
  one is ignored.)
- *A cell's race is its own.* A cell is a lock block with no mutex. The
  model checks its state out as a lock's payload (A3.2's `withLock`), so in
  the model two threads would be serialized there, where the runtime's
  copies write one memory with no lock. So a cell's race is not an
  address's touch, and the draft's "a write through `withCell` is to the
  home thread's own part, so there is no race" holds of addresses with or
  without the crossing check.
  `Race` gets a disjunct of its own (`CellRace`, below), and the invariant
  says no two threads hold a share of one cell.

**The rules (A2).**
- `Rhs.cellNew t y` (the handle's constructor, `pncounter_new`):
  `EvalR.cellNew` moves `y`'s value into a fresh lock block at the key
  `nid`, whose one share is the cell share `.cell nid`. `RhsT.cellNew`
  asks what `lockNew` asks of the payload (no view, no closure, no share)
  and gives an owned `cell t` that holds nothing (`rhs_cellNew`,
  `out_cellShare`).
- `Rhs.cellClone a` (`PNCounter_share`, and every copy the library
  makes): a new cell share of the block `a` holds (`EvalR.cellClone`).
  `RhsT.cellClone` asks that `a` own its slot (an owner or an `inout`
  parameter, `E.mode.ownSlot`), since a lent cell share is no share
  (`out_cellClone`). (A3.5's third cut, below: any live binding.)
- **The in-place change** is `Stmt.withCell a x s := withLock a x s`.
  `Step.withLock` checks out the payload of the lock block `a`'s share
  names, through a lock share or a cell share (`LockAt`), and A3.2's scope
  and `Release` give it back. `StmtT.withLock` asks `Entry.lockOf t`: `a`
  is a lock share, or a cell share an owner holds. It keeps A3.2's
  faithfulness premises: `a` is a root the body does not name, and `x` is
  live at the end.
- **A second check-out** of a cell that is out (a library re-entering its
  own state) waits (`Blocked`: `LockAt` and the payload out) or panics
  (`Step.waitPanic`), as `RefCell`'s borrow error would (the runtime goes
  on in place: *Faithful to the runtime*, below).
- **The Sync question** (h338, h358, h357). A cell share may not be in a
  payload several threads reach:
  - `RhsT.arcNew` refuses a payload type that may hold one (`Ty.hasCell`,
    which a closure type answers `true`);
  - a lock's payload, an `RwLocked`'s and a channel's element hold no share
    at all (`Ty.ok (lk t)`, `RhsT.lockNew`, `RhsT.chanSend`), so none
    holds a cell share (`Ty.hasCell_of_hasArc`, `lk_noCell`);
  - a cell's own payload is a lock's, so it holds none either.
- **Send.** A cell share crosses a spawn (`cell_spawnOK`: `SpawnOK`'s
  question unchanged), subject to the crossing check.
- The sweep keeps a cell's block while a slot holds a cell share of it
  (`ShareIn`, `Refers`, `Kept.cell`).

**A2's proof.** A cell share is a lock share for every memory fact:
`WFv.cell`, `ArcIn.cell` (it fits a lock block of its payload's type,
`SharesOK.cell`), `Frees.cell`, `Val.owns`, `ValOK.cell` (a lent one is
`.int 0`, valid through anything), and a case in each function on types
(`Ty.cell`: `holdsView`, `hasFn`, `hasArc`, `ok`, `owning`, `elemE`,
`popE`). `MInv.lockOf_val` / `lockOf_slot` give the block `withLock`
checks out from `Entry.lockOf`, through either share. `cellNew` is
`locked_new`'s store with another share (`rhs_lockNew_post`), and
`cellClone` is `lockClone`'s case for an owner (`MInv.cell_val`). The
renaming lemma keeps `lockOf` (`Entry.lockOf.lift`: an owner stays one
where the call places it).

**A3's proof.**
- **The crossing check** (`SendCheck vs st'`), a premise of `TStep.spawn`:
  for every cell `k` a moved value holds a share of (`Sub (.cell k) v`), no
  slot the spawner keeps holds one. It is stated on what the values hold.
  For a cell that is what they reach, since no payload holds a cell share
  (the Sync question, above).
- **A failed check panics** (`TStep.spawnFail`): nothing moves and no
  thread is made. The spawner's statement becomes the call with a panic
  put before it (`K (.seq .panic (.letcall …))`), so its next step is A2's
  panic, which unwinds its scopes or is caught by a `recover` frame.
  `spawnFail_ok` types it where the call was, over the same store
  (`Redex.plug`, the panic keeping the context as it is), and
  `CInv.setStmt` / `CellInv.setStmt` keep both invariants.
- **Confinement** (`CellInv`, `A3/Cell.lean`): no two threads' slots hold
  a share of one cell (`home`), and every cell share names a key below
  `nid` (`below`).
  - *A thread's step hands on only what its slots held* (`Step.cell`). A
    cell share in its slots afterwards was in its slots before, or in a
    lock block's payload, or it is a new cell's, at a key taken from `nid`
    in this step. A lent value holds none (`not_sub_cell_lendOf`), so
    nothing read out of an `Arc`'s or a view's payload brings one. No lock
    payload holds one (`ThreadOK.noCellPay`, from `Ty.ok`). A new cell's
    key is no other thread's share's (`below`). So the stepping thread
    never gains a share of another thread's cell (`CellInv.thread_of`).
    The other threads' slots do not change, and the sweep removes blocks
    only.
  - *A spawn moves the home with the values* (`CellInv.spawn_of`): a cell
    a moved value holds a share of keeps none in the spawner
    (`SendCheck`), so the new thread is its only holder; every other cell
    stays where it was, since the new thread holds only what moved.
- **No cell race** (`CellInv.cellRaceFree`). `CellOp t k` is a thread whose
  next step changes cell `k`'s state: a `withCell` through a share of it,
  or a step inside a check-out of it (`k ∈ t.s.lkeys`) while holding a share
  of it. Either way the thread holds a share (`CellOp.cellAt`), and only
  one thread does. `Race` is `AddrRace ∨ CellRace`. `AddrRace` is A3's
  race as it was, which A3.2's argument still proves: a checked-out
  payload, a cell's too, is in its holder's part, and an in-block one is
  read by no one.
- *memory_safe* and *no_leak* are unchanged. A cell share frees nothing,
  and the configuration's sweep frees a cell's block, with its state, once
  no thread's slot holds a share of it.

**Faithful to the runtime** (`stdlib/runtime_core.c`'s `mem_send_check`,
`stdlib/dist/crdt.nu`).
- *The count.* The runtime counts, for each handle's block that `x`
  reaches, the places in `x` that hold it, and compares that with the
  block's reference count. The check passes iff every owner goes along.
  The model's owners are the slots that hold a cell share: a lent one is
  `.int 0`, and a copy is an explicit `cellClone` (`PNCounter_share`,
  `shared_clone`). The model asks, over what the moved values hold, that
  no slot left behind holds one, which is "every owner goes along".
  **Phase D obligation (stated, not proven):** the runtime's count of a
  library handle's block equals the number of cell shares the model's
  slots hold. Its copies are the model's `cellClone`s (a store of a
  borrowed handle into an owner, a push, a capture), and its drops are
  the model's slots ending. Given that, the runtime's walk passes exactly
  when `SendCheck` holds.
- *What the walk follows.* It follows fields, enum payloads, `Vec`
  elements, containers' contents (`S_sendck`), closures' environments and
  trait objects' boxes. The model's moved values are trees (`Sub`:
  fields, payloads, elements, a package's environment). A trait object's
  box is a package's environment (A3.5c, below). The model has no
  containers beyond `Vec`.
- *The panic.* `mem_send_check` calls `nurl_panic` naming the crossing,
  before the thread copies its environment. So no thread is made and
  nothing has moved, as in `TStep.spawnFail`.
- *The in-place change* is A3.2's: the runtime's `pncounter_inc` runs on
  the state through the handle, and the model checks it out into `x` and
  back. The two agree under `withLock`'s premises (A3.2, *Faithful to the
  in-place runtime*).
- *Re-entrance.* A library that reaches its own state again while it
  changes it (`pncounter_merge a a`) runs on at run time, in place, on one
  thread. The model's second check-out waits for the first (`Blocked`) or
  panics (`waitPanic`), as `RefCell`'s borrow error would. A run past that
  point is not modeled (*Simplifications*, below).
- *The static rules come first.* The checker's own rules (h336, h337,
  h333, h356: a moved handle's binding, a parameter of one and a binding
  read out of a field of one are dead past the crossing) are A2's: a
  `sink` move kills the binding and every borrow of it. What is left for
  the run-time check is a copy, which the model makes with `cellClone`.

**Simplifications in this cut.** Each is a restriction, and sound as stated.
- *A library handle is changed only through an owner.* `withCell` and
  `cellClone` take a cell share an owner holds (an owned binding or an
  `inout` parameter, which is the caller's owner). A lent handle is no
  share. So a library function that takes its handle `in`, as
  `pncounter_inc PNCounter c__h …` does, is modeled taking it `inout`, and
  a handle read out of a borrowed struct is not changed through. (Closed
  by A3.5's third cut, below, for a borrowed root: an `in` parameter.)
- *Copies are explicit*: `cellClone` of an owner. A store of a borrowed
  handle into an owner, which the runtime makes a copy, is not typed:
  `PushArg` moves owners only, as for every owning type.
- *A cell's state is a lock's payload*: it holds no view, no closure and no
  share.
- *A closure that captures a handle* holds the share in its environment,
  which a spawn moves and checks. But a call lends the environment
  (`envMem`), so the closure's own code does not change the state (since
  A3.5's third cut, below, it does: the lent environment is the share). A3.5b
  keeps such a closure out of an `Arc` (it is not Sync) and out of a
  channel (it holds a share).
- *The other crossings.* `chan_send`'s and `Locked`'s (`locked_new`,
  `locked_set`, `locked_restore`, after `locked_with`) need no run-time
  check here: their values hold no share at all, so the check has nothing
  to find. It is refused statically, which is more than the runtime
  refuses. (A3.5's second cut runs the check at each, below.)
- *`% Sync` and `% NotSend` assertions* are not modeled: an `Arc` of a
  handle is refused whatever the handle asserts, and `PkMemberTable`
  (h319) is a cell, Send, where the runtime makes it `% NotSend`.
- *Re-entrance* waits or panics where the runtime goes on (above): a
  program that re-enters a handle's state is covered only up to that
  point.
- *`CellOp`'s second case* asks the thread inside a check-out to hold a
  share of the cell. In a typed program it always does (the share the
  check-out is through stays in `a` for the whole body, by `withLock`'s
  premises). That is argued, not proven as a lemma (as A3.2's "a typed
  lock scope ends in a `put`").

**Probes** (`tools/fuzz/holes/*.nu`). In the model, a thread's closure is
the spawned function, and its captures are `sink` arguments.
- h336 `library_handle_captured_by_a_thread_and_kept`: the spawn moves the
  handle (`MoveArgs`; `CallT` moves a `sink` argument), which kills its
  binding, so the spawner's later `withCell a …` is refused (`a` is dead).
  A copy the spawner kept (`cellClone`) is an owner left behind:
  `SendCheck` fails and the spawn panics (`TStep.spawnFail`).
- h337 `library_handle_parameter_captured_by_a_thread`: a parameter of the
  handle is no `sink` argument (`paramOK`: a `sink` argument is an owner).
  Taken `in`, it is a lent handle, no share, which `cellClone` refuses.
  (Since A3.5's third cut, below, the copy is typed, and its spawn fails
  the check.)
  Taken `inout`, a copy of it leaves the caller's owner behind:
  `SendCheck`. Taken `sink`, the handle moves.
- h333 `library_handle_field_copy_on_two_threads`: `. h c` is a borrow of
  `h` (`projE`, a dependency on `h`), and a lent handle is no share. The
  spawn moves `h`, which kills the borrow, so `withCell mine …` after it
  is refused, as is any change through a borrow.
- h356 `library_handle_field_read_taken_by_a_thread`: a binding read out of
  a field is a borrow, which is no `sink` argument (`paramOK`). The thread
  takes the struct, or the field taken apart (`unpair`), and with it the
  owner.
- h338 `arc_of_a_library_handle_on_two_threads`: `RhsT.arcNew` refuses a
  payload type that may hold a cell share (`Ty.hasCell`).
- h358 `rc_in_a_locked_in_an_arc_on_two_threads`: a lock's payload holds no
  share (`RhsT.lockNew`, `Ty.ok (lk t)`), so neither a library handle nor
  (were it modeled) an `Rc` is a `Locked`'s value; `lk_noCell`. (A3.5's
  second cut replaces this rule with the crossing check at `locked_new`,
  below.)
- h319 `member_table_copy_on_two_threads`: as h333. `a` is a borrow of the
  struct's field, dead once the struct moves, and a kept copy fails the
  crossing check.

**Not proven here.**
- *Phase D*: that the runtime's reference count of a handle's block is the
  number of cell shares the model's slots hold, so its walk passes exactly
  when `SendCheck` holds (above).
- That a thread inside a check-out of a cell holds a share of it, as a
  lemma (`CellOp`'s second case). It would need an invariant tying each
  `scopeL k` frame to its binding `a`, which A3.2 also leaves out.
- That a cell's checked-out state is in its home thread's part. It is in
  the part of the thread whose frame holds it (A3.2's partition), and that
  thread is the home by the argument above.
- Deadlock freedom: a library re-entering its own state waits or panics.
- Trait objects, h344 `dyn_object_carries_an_rc_to_a_thread` (a `%Trait`
  box crosses only when its trait is `: Send`, and the vtable checks it),
  are A3.5c's (below), and closures in shared payloads (h339, h340, h342)
  A3.5b's.
- A library handle changed through a borrow (`in` parameters), implicit
  copies, handles in containers with `S_sendck` hooks, `% Sync` / `%
  NotSend` assertions. (A3.5's third cut, below, closes the first.)
- The probes as typed programs (a probe's encoding, as `A2/DynCell.lean`
  types `pick`).

## A3.5b's mechanization (closures across threads)

**Status (first cut).** Closures that cross threads, or that several
threads reach at once, are mechanized. A closure's type says where it may
cross; an `Arc` holds a Sync closure, a lock or a channel a bare one, and a
spawn takes a Send one; a call through a closure an `Arc` lends is typed.
`check.sh` is green with them in A2 and A3, and `A2.memory_safe`,
`A2.soundness`, `A2.no_leak_end`, `A2.no_leak_panic`, the `DynCell`
theorems and `A3.claim` are re-proven. Trait objects' statements (h344)
are A3.5c's (below).

The runtime it models is docs/MEMORY.md §6.5:
- a closure's captures are not part of its type, so nurlc asks the Send
  and Sync question of the value, followed from where the closure is built
  to where it crosses;
- a closure run on another thread moves its captures (A3.0's spawn does
  this for a thread's body: its captures are `sink` arguments);
- a closure kept in an `Arc`, or in a `% Sync` handle (a server's handler),
  is reached by several threads at once. What it captures must be Sync, so
  no library handle (h339), and its code may not change what it captured
  (h342: a handler pushing to a captured `Vec` from every worker). It
  counts in an `Atomic` or keeps the list in a `Locked` instead;
- a closure sent on a channel, or kept beside a handle another thread takes
  it from, moves its captures that are not Sync (h340).

The gap before this cut: an `Arc`'s payload, a lock's payload and a
channel's element all asked `hasFn = false`, and every closure type
answered `true`, so no closure could be shared or sent.

**Where the fact lives: a flag on `Ty.fn`.** The design offered three
places: a flag on `Ty.fn`, a sibling type constructor, or a predicate on
the packed value that typing tracks. The flag is taken:
`Ty.fn ms q`, with `q : Cross`.
- *Why not a predicate on the value.* The fact must survive everywhere a
  closure goes after `pack`: a move, a field, a `Vec` element, an `Arc`'s
  payload that `arc_clone` shares and `arc_get` lends, a channel's queue.
  Each of these carries only a type. An entry's `held = []` says Send of
  one binding, but the share `arc_new` makes holds nothing whatever its
  payload holds, and the payload's type is all that `arc_get` has to go
  on. So the fact has to be in the type.
- *Why not a sibling constructor* (a `Ty.sfn ms`). Every function on types,
  and every `cases` or `induction` on them, would get a case that repeats
  `fn`'s. With the flag, `fn`'s one case reads `q`, and nothing on values
  changes: the flag is the type's, never the package's (`Val.pkg` is as it
  was).
- *Why four classes, not a Bool.* An `Arc`'s payload may hold shares
  (`Arc (Arc i)`, or an `Atomic` a handler counts in). A lock's payload and
  a channel's element hold none: that is A3.2's and A3.4's simplification,
  since the sweep reaches no block through a lock's payload. So Sync
  (`sync`, which may hold `arc` and lock shares) and fit for a lock
  (`bare`, no share at all) differ, and Send (`send`, which may hold a cell
  share that a spawn's crossing check covers) is a third. They are
  ordered, each holding less: `any`, `send`, `sync`, `bare`.

**The rules** (A2, `Syntax.lean`, `Typing.lean`, `Invariant.lean`).
- `Cross` is `any | send | sync | bare`, with `Cross.views` (`any`),
  `Cross.cells` (`any`, `send`) and `Cross.shares` (all but `bare`).
  - `Ty.holdsView (fn ms q) = q.views` and `Ty.hasFn (fn ms q) = q.views`.
    `hasFn` now means "may hold a closure that holds bindings by name or
    views". A Send closure holds neither, so a type that answers `false`
    may still hold one.
  - `Ty.hasCell (fn ms q) = q.cells` and `Ty.hasArc (fn ms q) = q.shares`.
- `Cross.Fits q te cs`: the environment, of type `te`, with the captures by
  name `cs`, holds no more than `q` says.
  - `q.views = false → te.holdsView = false ∧ cs = []`;
  - `q.cells = false → te.hasCell = false`;
  - `q.shares = false → te.hasArc = false`.
- `RhsT.pack` gains `q.Fits te cs`, and its result is a `fn ms q`. The rest
  is A2's rule as it was: `PushArg` moves the environment in, and `CapsOK`
  checks the captures by name. `pack` may give a closure any class its
  environment fits (`RhsT.pack_fits`). The strongest is the one nurlc's
  walk finds (*Faithful*, below).
- `WFv.pkg` and `ValOK.pkg` ask `q.Fits te cs` of a package in memory, owned
  or lent. `ViewIn.pkg` looks into an environment only at `any` (no other
  holds a view), and `ArcIn.pkg` only where `q.shares` (a bare one holds no
  share).
- `StmtT.callc` reads `q` only to match the interface: the receiver is a
  `fn ms q`, and the interface's first parameter is `(inp, fn ms q)`. A
  call through a closure is otherwise unchanged.
- The crossing rules are unchanged. Their premises read the flag through
  the functions on types:
  - A3.0's spawn (`SpawnOK`: a parameter whose type holds no view) takes a
    `send`, `sync` or `bare` closure;
  - A3.1's `arc_new` (`RhsT.arcNew`: no view, no closure that holds names,
    no cell share) takes a `sync` or `bare` one (`arcNew_fn`,
    `arcNew_sync`), and `arc_get` (no view, no such closure) lends it
    (`arcGet_sync`);
  - A3.2's `locked_new`, A3.5's cell constructor and A3.4's `chan_send`
    (`Ty.ok (lk _)`: no view, no share) take a `bare` one (`lockNew_fn`,
    `chan_fn`);
  - A3.6: `Ty.sync (arc t)` is `!t.hasCell`, so an `Arc` global may keep a
    Sync closure (a server's handler). `GlobsOK P G` asks that its code be
    the program's (`codes`).
- **A call through a closure an `Arc` lends** is A2's `callc`, unchanged
  (`callT_recv`, `StmtT.callc_recv`, and `StmtT.arcCall` for `arc_get`
  then the call).
  - `arc_get`'s borrow (`getE a E t`) depends on `a` through a share
    (`Kind.share`), and holds nothing by name.
  - The call hands the borrow to the interface `inp`, and the code is handed
    the environment lent again (`envMem`).
  - `ThruOK.noShare` and `canDo` refuse every change through the borrow,
    as through any payload borrow. A call needs no rule of its own: no
    call changes its receiver.

**What "its code changes no capture" is in the model.** A closure's code
takes its environment as its first parameter, `inp`, and changes nothing
through a borrow (`Implements`, `Implements.env_lent`: `¬ ThruFn`). So
what a closure's code may change is a binding it captured by name (an
`inout` capture, `CapsOK`), never its environment. A capture by name is a
binding of the thread that built the closure, so `send` already excludes
it (`cs = []`).
- Every Send closure's code therefore reads its environment only. It
  changes state only through the locks, atomics and channels the
  environment holds, which synchronise themselves.
- Sync is then Send with no cell share.
- This refines the design's "Sync: additionally, its code changes no
  capture, as `Implements` / `ThruFn` can say". `Implements` says it of
  every closure, and the captures that can change are the ones by name.
- What a lent cell share in an environment gives the code is no share
  (`lendOf`, A3.5), so the code never changes a library handle's state.
  The Sync question still refuses one (h339), to be faithful to the
  runtime, whose code does change it. (Since A3.5's third cut, below, the
  code does change it, through its lent environment, as the runtime's
  does; the Sync question is what keeps it out of an `Arc`.)

**A2's proof.**
- *Every package a block holds names code of its signature* (`MemCodes`'
  block half, `BlkCodes`, `MemCodes.blk`). This replaces `MInv.blkCodes`
  ("a payload holds no package").
  - Every step that changes a block keeps it: `arc_new`, `locked_new`, the
    cell constructor, `rw_read`, an atomic or channel step, a lock's
    check-out and its give-back (`EvalR.codes`, `Release.codes`).
  - The sweep only removes blocks (`MemCodes.sweepR`).
- *A value whose type holds no view holds only Send packages*, each
  capturing nothing by name. Where the proof said such a value holds no
  package, it now says this:
  - `WFv.noView_pkg`, `WFv.pkgsOK_noView` (a payload's `PkgsOK`,
    `MInv.pay_pkgs`) and `WFv.no_pkg` (for `hasFn = false`);
  - `WFv.names_nil`, `WFv.names_nil_fn`, `ValOK.names_nil_fn` and
    `ValOK.memDeps`, by `Cross.Fits.send`.
- *The lemmas that walk a value read the class*: `WFv.sub_view`,
  `WFv.node_holdsView`, `ViewsOK.pkg`, `SharesOK.pkg'`, `WFv.noCell`,
  `lend_valOK'`.
- `pkg_fits`: a live closure binding holds a package that fits its type.
  `pkg_cap_mut` reads it (a closure that captured itself by name holds
  views, so it is `any`).
- *The renaming lemma*: `Cross.Fits.map` (fits reads only whether there are
  captures, not their names) and `Cross.Fits.holdsView` (an environment
  that may hold views lies in an `any` closure).

**A3's proof.** A3's statements read nothing new. `Touch`, `Race`,
`CellRace`, the partition and the frame lemmas are over values, and a
closure's environment is a tree inside its value (`Sub.pkg`, `Val.ids`).
- *race_free.* A Sync closure in an `Arc` is part of its payload.
  - Its environment's addresses are the block's (`BlkOwn`): in `payPart`,
    in no thread's part.
  - A call through it (`Step.callc`) touches nothing: it binds the lent
    environment, handles into the payload, to a fresh slot.
  - What the code reads of the environment is a payload read (`touch_seen`,
    `PaySeen`), which A3.1 proves is no race. What it writes is the
    thread's own (its arguments, its result), or a lock's payload it has
    checked out (A3.2).
  - So two threads calling one Sync closure only read its environment.
- *Send through a channel.* `chan_send` of a bare closure moves its tree,
  environment and all, into the queue (`RTouch.chanSend` counts it as the
  sender's write), and `chan_recv` hands it to the receiver's part: A3.4's
  argument, for any value.
- *A spawn* moves a Send closure as a `sink` argument. The crossing check
  counts the cell shares its environment holds (`sendCheck_env`: `Sub`
  enters packages), so `CellInv`'s confinement holds as for any moved
  value.
- *The blocks' codes across threads.* Every thread's view has the
  configuration's blocks, so every `ThreadOK`'s `MemCodes` covers them.
  - A thread's step gives the other threads the new blocks' codes
    (`ThreadOK.blkCodes`, a premise of `ThreadOK.move`).
  - A new thread gets the spawner's (`NewThreadLemma`).
  - The start gets the globals' (`GlobsOK.codes`).

**Faithful to the runtime.** nurlc follows the value; the model types it.
- *How they relate.* nurlc asks the Send and Sync question of a closure
  value, followed from its literal to where it crosses: through bindings,
  fields, returns, captures and the parameters of functions that spawn or
  keep it. It rejects a closure whose origin it cannot follow. The model
  asks the question of the type.
  - At the literal, both read the captures. `Cross.Fits` reads the
    environment's type and whether anything is captured by name, so the
    strongest class `pack` can give is the one nurlc's walk finds.
  - From the literal on, nurlc follows the value and the model its type. A
    move, a field, an element or a payload keeps the type, so it keeps the
    class.
  - **Phase C obligation (stated, not proven):** the lowering gives every
    closure type the class nurlc's walk proved of the values it holds, and
    `any` to a closure whose origin nurlc cannot follow.
- *Where the model refuses more.*
  - A parameter or field of closure type carries one class, and the model
    has no subsumption (a `sync` closure where an `any` one is declared).
    nurlc follows the value through. (Closed for a closure's own type by
    A3.5b's and A3.5c's rest, below: a move or a copy takes it at a class
    above its own. A container's element type keeps one class.)
  - The runtime's closure moves its captures into its environment, and its
    code may change them (an accumulator). The model's code reads its
    environment, and changes only captures by name, which are not Send.
    So a closure that changes what it captured is not Send in the model,
    even one that the runtime lets cross because it moves. (Decided in
    A3.5b's and A3.5c's rest, below: out of A2's closure model. The model's
    accumulator keeps its state in an `Atomic` or a `Locked`.)
  - A channel's element and a lock's payload hold no share (A3.2, A3.4).
    So a closure sent on a channel captures no handle at all, where the
    runtime moves a non-Sync capture with it (h340).
- *Where the model is the runtime.* h342's fix: a handler that counts in an
  `Atomic`, or keeps its list in a `Locked`, captures a lock share, which
  `sync` admits. Its code changes the state by `atomic` on the lent share,
  or by `withLock` when the environment is the share itself (A3.2's
  `withLock` takes a root, and a borrowed parameter is one; a share read
  out of a field is not). Both synchronise themselves.

**Probes** (`tools/fuzz/holes/*.nu`). The rules each probe maps to are in
`A3/Defs.lean`, with A3.6's.
- h339 `closure_in_an_arc_captures_a_library_handle`: `pack` types a
  closure Sync only when its environment holds no cell share
  (`pack_sync_noCell`), and an `Arc` holds only Sync or bare closures
  (`arcNew_fn`). So a closure that captures a library handle is `send` at
  best, and `RhsT.arcNew` refuses it (`hasCell`).
- h340 `closure_sent_on_a_channel_captures_a_kept_handle`: a channel's
  element and a lock's payload hold only bare closures (`chan_fn`,
  `lockNew_fn`), which capture no handle. On a spawn, the crossing check
  counts the handles a closure's environment holds (`sendCheck_env`), so
  a handle kept behind fails it and the spawn panics (`TStep.spawnFail`).
  (A3.5's second cut: a channel takes a Send closure, and the send's
  crossing check panics on a kept handle, below.)
- h342 `route_handler_changes_its_capture_on_two_threads`: a handler that
  changes a capture captures it by name, so `pack` types it `any`
  (`pack_names_any`). No `Arc` holds it (`arcNew_not_any`) and no spawn
  takes it (`spawn_not_any`). A closure's code reads its environment, lent
  (`Implements.env_lent`). The fix, a Sync handler in an `Arc` called by
  any thread, is typed (`StmtT.arcCall`).

**Simplifications in this cut.** Each is a restriction, and sound as stated.
- *No subsumption.* A `sync` closure is not an `any` one, so a function
  declares the class of each closure it takes. Forgetting a class would be
  sound (it only weakens the type) but is not a rule. (Closed: `RhsT.moveUp`
  and `RhsT.copyUp`, A3.5b's and A3.5c's rest, below.)
- *One class per interface.* An interface's receiver is `(inp, fn ms q)`,
  so an interface is declared at one class, and a method's code is checked
  once for it. (Kept: a borrowed receiver is copied up to the interface's
  class, `StmtT.callcUp`, below.)
- *A lock or a channel takes only a bare closure* (no share), as A3.2 and
  A3.4 take no share.
- *A closure changes only what it captured by name* (A2's closure model).
  A Send closure's code changes nothing it owns. (Kept, and decided:
  A3.5b's and A3.5c's rest, below.)
- *A `% Sync` handle* other than an `Arc` (a server's `Route`) does not keep
  a closure in the model: its handler is an `Arc` of a Sync closure.
- *Trait objects.* A `dyn` is a `pack` too, so a trait object gets a class
  the same way, and the interface's receiver type carries it, as a trait's
  `: Send` / `: Send Sync` bound does (A3.5c, below).

**Not proven here.**
- *Phase C*: that the lowering gives each closure type the class nurlc's
  walk proved (above).
- Subsumption between classes; a closure that changes what it moved in.
  (Closed: subsumption is typed, and the second is decided out of A2's
  closure model, in A3.5b's and A3.5c's rest, below.)
- A share in a lock's payload or a channel's element (A3.2, A3.4), so a
  closure that captures one and is sent or locked. (Closed: A3.2's second
  cut for `arc` and lock shares, A3.5's second cut for cell shares, below.)
- Trait objects' own statements are A3.5c's (below).
- The probes as whole typed programs: `StmtT.arcCall` types the call
  through the `Arc`, not a program that `memory_safe` is applied to (as
  `A2/DynCell.lean` types `pick`).

## A3.5c's mechanization (trait objects)

**Status (first cut).** Trait objects that cross threads are covered, and
A3.5b already held all of it: **no rule, invariant or claim changes**. A
trait object is A2's package, as a closure is, so A3.5b's class is what
its trait's bound says, and the crossing check already walks its box. What
this cut adds is the trait, which A2 has no word for, and the statements
that tie the class to the bound and the box to the check (`A3/Defs.lean`,
and `spawn_moves_send` in `A3/SpawnOld.lean`). `check.sh` is green, and
`A2.memory_safe`, `A2.soundness`, `A2.no_leak_end`, `A2.no_leak_panic`, the
`DynCell` theorems and `A3.claim` hold as they were. `CLAIM.md` /
`README.md` are not updated here.

The runtime it models is docs/MEMORY.md §6.5, the Send/Sync table and the
paragraph after it, and `formal/RULES.md`'s h344 row:
- a trait object `%Trait` is Send only when its trait declares `: Send`,
  and Sync only with `: Send Sync`;
- the bound is a promise each impl is held to: the derivation checks the
  impl's type where the impl is, and rejects it there if it reaches an
  `Rc` or another value that is not Send;
- the crossing check walks a trait object's box through its vtable
  (`mem_send_check`): an impl of a `: Send` trait whose type reaches a
  library handle puts that type's check in the vtable's last slot, so a
  handle in the box is counted (h360).

**What A3.5b already had.** A2 makes a closure and a trait object by one
rule, and nothing in it tells them apart. Nothing has to:
- *The package.* `dyn Trait v` is `Rhs.pack fs te ms y []`: the impl's
  code `fs` (method `j`'s is `fs[j]`), the box `y`, of the impl's type
  `te`, moved in (`PushArg`), and the trait's methods `ms`. A box captures
  nothing by name. `Rhs.dyn` names this `pack`; a closure is the case of
  one method that may capture by name.
- *The box faces `Cross.Fits`.* `RhsT.pack` asks `q.Fits te cs` and gives
  `fn ms q`; `WFv.pkg` and `ValOK.pkg` keep it in memory.
- *Every method's code is checked.* `CodeOK P fs te ms cs` asks
  `fs.length = ms.length` and `Implements` of each method: its code takes
  the box lent where the interface takes the receiver (`inp`), and changes
  nothing through a borrow (`CodeOK.env_lent`, method by method). A
  closure's one method is the case `ms = [σ]`. `MemCodes` holds it of
  every package in memory, blocks included.
- *A call reads the class only to match the interface.* `StmtT.callc` asks
  method `j`'s interface to take the receiver as `(inp, fn ms q)`.
- *The crossing check enters packages.* `SendCheck` and `CellInv` ask
  `Sub (.cell k) v`, and `Sub.pkg` enters a package's environment
  (`sendCheck_env`). So no `Sub` or `SendCheck` case is new.

**Where the bound lives: in the methods' receivers.** A trait, in the
model, is its methods' interfaces `ms`, and its bound is the class at
which it declares their receivers.
- `TraitBound` is `none | send | sendSync`. `TraitBound.cross` maps it to
  A3.5b's class: `any`, `send`, `sync`.
- `TraitAt P ms b`: every interface `ms[j]` is a function of the program
  whose first parameter is `(inp, fn ms b.cross)`.
- *Why not a premise of `pack`.* `RhsT` has no program, so it cannot see
  the interfaces. And the class is the type's, never the package's
  (`Val.pkg` has no class). Neither change is needed either:
  - a call through a trait object types only at its trait's bound
    (`StmtT.callc_bound`);
  - an object packed at another class is inert: no method of it is called
    (`callc_not_at`). (A3.5b's and A3.5c's rest, below: one packed below the
    bound is moved up to it, `dyn_up_bound`.)
- *Why no `bare` bound.* `bare` (no share at all) is the class a lock's
  payload and a channel's element take (A3.2, A3.4). No NURL bound says
  it.

**The statements** (`A3/Defs.lean`, after A3.5b's).
- What each bound promises of an impl's type, with no capture by name:
  - `TraitBound.fits_none`: only that it holds no destructor value
    (A2-drop.3c, asked of every package's environment);
  - `TraitBound.fits_send`: also that the box's type holds no view;
  - `TraitBound.fits_sendSync`: it also holds no cell share.
- The class is the bound: `StmtT.callc_recv_at` (a call's receiver is a
  `fn ms q` whose interface takes it at `q`, through `StmtT.sub` too),
  `StmtT.callc_bound` and `callc_not_at`.
- The per-impl check:
  - `ImplOK P b fs te ms`: `CodeOK P fs te ms []` and `b.cross.Fits te []`;
  - `dyn_implOK`: a `dyn` the program makes (`Stmt.codesOK`) at its trait's
    bound is an impl held to it;
  - `CodeOK.recv_eq`: the impl's code fixes the box's type, since its first
    method takes it as its receiver;
  - `ImplOK.of_code`: so the check is the impl's. Every pack of an impl
    gets the answer one of them got.
- The crossing check walks the box:
  - `sendCheck_box_kept`: a moved box that holds a share of a cell a kept
    slot also holds (in its own box or not) fails the check, whatever the
    spawn moves (`MoveArgs.det`). So the spawn is `TStep.spawnFail`'s
    panic;
  - `WFv.noCell_hasCell`, `sendSync_box_noCell`: a `: Send Sync` object's
    box holds no handle at any depth. There is nothing to count;
  - `WFv.noView_fits`, `spawn_pkgs_send`, and for a typed thread
    `spawn_moves_send` (`A3/SpawnOld.lean`, from `spawn_args`): every
    package a spawn moves, however deep (a field, an element, another
    box), fits `send`.

**A2's and A3's proofs.** No proof changes: the rules are A3.5b's, and
`check.sh` re-checks every theorem as it was. The statements above are
corollaries of A2's typing and of `SendCheck`; `spawn_moves_send` reads
A3.0's `spawn_args`.

**Faithful to the runtime.**
- *The bound.* The runtime's bound is the trait's. The model's is in the
  methods' receivers (`TraitAt`), and an object whose methods are called
  has it as its class (`StmtT.callc_bound`).
  **Phase C obligation (stated, not proven):** the lowering gives every
  `%Trait` the type `fn ms b.cross`, `b` its trait's bound, and declares
  its methods' receivers at it, so `TraitAt` holds of every trait.
- *Where the impl is checked.* The runtime asks once, where the impl is.
  The model asks at each pack, but the answer is the impl's. `Fits` reads
  the bound and the box's type only, and the impl's code fixes the box's
  type (`ImplOK.of_code`). An impl that is never boxed is not checked: the
  model accepts it where the runtime rejects it, and nothing of it
  crosses.
- *The vtable's walk.* The runtime walks a box through the vtable's last
  slot, the boxed type's own check. The model's `Sub` enters the box.
  **Phase D obligation (stated, not proven):** A3.5's, for boxes. The
  vtable's check of an impl whose type reaches a handle counts the places
  in the box that `Sub` finds. A `: Send Sync` box holds none
  (`sendSync_box_noCell`), and a trait with no bound has no object that
  crosses.

**Probes** (`tools/fuzz/holes/*.nu`).
- h344 `dyn_object_carries_an_rc_to_a_thread`. A `%Churn`, whose trait
  `Churn` has no bound, boxes a `Holder` of an `Rc`. It moves into a
  thread's closure while the spawner keeps a clone in `h2`.
  - *The model's stand-in for the `Rc`.* The model has no `Rc`: it is the
    standard library's (phase B). An `Rc` is not Send because its clones
    are one count, changed in place with no lock. The model has two
    stand-ins. A value that is never Send is a view, or a binding captured
    by name. A value whose copies are one state is a cell share (A3.5),
    which crosses only with every owner.
  - *As written* (no bound): `Churn`'s objects are `any`. No spawn takes
    one (`spawn_not_any`, `spawn_dyn_none`), and an object taken at
    another class is no receiver of `churn`, so the thread cannot call
    it. A closure that captures it is `any` too (`dyn_view_any`, since
    `(fn ms any).holdsView`), so it crosses nothing either. Nor do an
    `Arc` (`arcNew_dyn`, `arcNew_not_any`), a lock or a channel
    (`lockNew_fn`, `chan_fn`) or a global (`glob_dyn`, `glob_not_dyn`)
    take it.
  - *With `: Send`*. The impl for `Holder` keeps the promise only if its
    box holds no view (`TraitBound.fits_send`). With a view for the `Rc`,
    the box is packed at `any` only (`dyn_view_any`), never at the trait's
    bound, and an object at `any` is inert (`callc_not_at`): the model
    refuses where the runtime refuses the impl. With a cell share for the
    `Rc`, the object is `send`, and the spawn's check counts the box:
    `h2`'s kept clone fails it, and the spawn panics
    (`sendCheck_box_kept`). The runtime refuses the `Rc` statically, so
    here the model refuses less, and soundly: a crossing that takes every
    clone along leaves no count behind.
  - *With `: Send Sync`*. A box that holds a cell share is not packed at
    `sync` (`dyn_cell_notSync`, `TraitBound.fits_sendSync`).
- h360 `dyn_object_carries_a_kept_share_to_a_thread` (phase B's probe,
  which runs clean). A `: Send` trait's object boxes a `PNCounter`, and the
  spawner keeps a share. The box is counted (`Sub.pkg`), and the kept share
  fails the check: `sendCheck_box_kept`, `TStep.spawnFail`.

**Simplifications in this cut.** Each is a restriction, and sound as stated.
- *A trait is its methods' interfaces.* There is no trait declaration,
  supertrait or `[T: Send]` bound. `TraitAt` is a fact about the program's
  interfaces, not a premise of the claim: no rule needs it, and the claim
  holds for any class. (Decided: a generic bound is monomorphised and
  answered by the class, A3.5b's and A3.5c's rest, below.)
- *One class per trait, no subsumption* (A3.5b's). A parameter of a trait
  object's type is declared at its trait's bound. (Subsumption: closed,
  below.)
- *A `: Send` trait's objects cross a spawn only.* A lock and a channel
  take only a bare package (A3.2 and A3.4 take no share), and no bound is
  bare. The runtime's `chan_send` and `locked_new` take any Send value.
- *A method takes its receiver `inp`* (A2's `callc`). A method with an
  `inout` receiver that changes the box (h364–h366's) is not a call
  through the object in the model. (Decided: out of A2's closure model, and
  h364's rule holds, below.)
- *An impl is checked where it is boxed*, not where it is declared
  (above).

**Not proven here.**
- *Phase C*: that the lowering gives each `%Trait` its trait's class and
  declares its methods there (`TraitAt`).
- *Phase D*: that the vtable's check counts what `Sub` finds in a box
  (A3.5's count, for boxes).
- `Rc` itself (phase B): not Send, not Sync, and so with no crossing check.
- Trait objects in a lock or a channel (closed: `: Send Sync` ones by A3.2's
  second cut, `: Send` ones by A3.5's second cut, below); `inout` receivers;
  supertraits and generic bounds; `% Send` / `% Sync` assertions on an impl's
  type (decided in A3.5b's and A3.5c's rest, below).
- The probes as typed programs (as `A2/DynCell.lean` types `pick`).

## A3.6's mechanization (module globals)

**Status.** Module globals reached by several threads are mechanized.
`check.sh` is green with them in A2 and A3, and `A2.memory_safe`,
`A2.soundness`, `A2.no_leak_end`, `A2.no_leak_panic`, the `DynCell`
theorems and `A3.claim` are re-proven. `A3.claim` now runs from a start
that holds the globals (`Cfg.start G s nv`, under `GlobsOK G`; since
A3.5b `GlobsOK P G`), and its
leak clause leaves what they reach. With no global it is A3.0–A3.5's
claim (`Cfg.init_start`, `A3.no_leak_init`).

The rest of A3.6 is mechanized too (*The rest*, below, `A3/Make.lean`): the
`make`s run before `main` and leave a start `GlobsOK` holds of (`Made`,
`made_ok`), and each read is tied to its global's declared type, so that
`EvalR.globP` is never taken in a typed program (`ProgGlobs`,
`Reach.glob_typed`). `A3.claim_made` is `A3.claim` from the program's
declarations, with `GlobsOK` derived from the make phase; `A3.claim` keeps
`GlobsOK` as a premise. `check.sh` is green, and the same theorems are
re-proven.

The runtime it models is docs/MEMORY.md §1, *Module globals*:
- *A global set at start*, `: ( Locked T ) g ( make )`. `make` (no
  arguments) runs once before `main`, and nothing writes `g` afterwards.
  - Its type must synchronise itself: `Locked`, `Arc`, `Channel`, `Mutex`,
    `RwLocked`, `Atomic`. A `( Vec T )` is refused (h263).
  - A read borrows the handle. `: ( Locked T ) h g`, a struct field or a
    `^ g` clones it, so the global is never moved or dropped.
- *A scalar global* (an integer, bool, float or `s`) needs no `unsafe`. It
  is read and written with relaxed atomics, so threads racing on it see
  whole values.
- *An owning global* (a `String`, a `Vec`, a struct of them, an option, a
  closure, a library handle), and a struct or option global of plain
  values (more than one word), are read and written only in `unsafe`
  functions (h202 h272 h273). They are trusted base, hypotheses of the
  theorem: there is nothing to type.

**Where a global lives: in the configuration, read through a right-hand
side.** The design offered two places: slots copied into each thread's
`st` at a spawn, or a `Cfg` field read through a new `Rhs`. The second is
taken:
- `Mem.gl : Nat → Option Val` (A2) and `Cfg.gl` (A3): global `g`'s share.
  `Cfg.view` gives every thread's view the configuration's globals, so the
  first thread and each spawned one reads them, and a spawn copies nothing.
- `Rhs.glob g t`, a read of global `g` at type `t`: a new owned share of its
  block (`EvalR.glob`), as `lockClone` / `arcClone` make one from a
  binding's. It names no variable, so a call's renaming leaves it as it is
  (`Rhs.rename`, `RhsT.ren`).

*Why not slots, with the global a borrowed root (`.rootb`).*
- A function's variables are renamed apart at a call (`callRen`). A global
  bound to a variable would have to be a parameter of every function that
  reads it, passed down every call and to every spawn (whose parameters are
  `sink`, `SpawnOK`). Otherwise the renaming would have to fix the
  globals' variables, which is `Rename`'s whole lemma again.
- A borrowed `arc` share is valid only through a dependency it lands
  through (`ValOK.arc`, `ArcLanded`). A thread-level borrowed root has none:
  `rootbLt` asks that a borrowed parameter's roots be older than it, so it
  cannot depend on itself. A lock share would do (`ValOK.lk` asks only for
  its block), but an `Arc` global would not.

*What the clone keeps of the `.rootb` design.*
- The reader's binding `h` is an owner, so a root. A3.2–A3.4's rules take
  it unchanged: `withLock h x s` (`h` is a root the body does not name),
  `rwRead h`, `chanSend h y`, `atomic op h …` (`Stmt.lockGlobal`,
  `Stmt.loadGlobal`, `Stmt.storeGlobal`, typed by `StmtT.lockGlobal`,
  `StmtT.loadGlobal`, `StmtT.storeGlobal`).
- A thread can neither move, drop nor assign a global. It holds only
  clones, and no rule writes `gl` (`Step.gl`, `TStep.gl`, `Reach.gl`).

*Given with the start, and made before it.* `A3.claim` takes the start as
the `make`s left it (`Globs`: the blocks, the addresses their payloads own,
`nid`, each global's share), under `GlobsOK`, which asks of it what A2's
invariant says of the store a typed `make` leaves once its result is the
global's. The make phase (*The rest*, below) runs the `make`s and shows
that the store they leave is such a start, without a phase in `TStep`.

**The rules.**
- `Ty.sync` (A2, `Syntax.lean`): a type that synchronises itself. It holds
  for `lk _` (`Locked`, `RwLocked`, `Atomic` and `Channel` are all lock
  blocks, A3.2–A3.4) and for `arc t` with `t.hasCell = false` (an `Arc` of no
  library handle, A3.5). It holds for nothing else: no `Vec`, struct, enum,
  closure or cell share.
- `RhsT.glob`: `t.sync = true → t.ok = true →
  RhsT Γ F (.glob g t) ⟨t, .own, true, [], [], false, false⟩ Γ`. The read is
  an owned share that holds nothing, and the context is unchanged.
- `EvalR.glob`: `m.gl g = some v → GlobFits m.blk t v →
  EvalR m (.glob g t) (.ok v true m)`. `GlobFits B t v`: `t = lk u` and `v`
  is a lock share of a lock block of type `u`, or `t = arc u` and
  `v = arc k p` with block `k` an `arc` block of type `u` holding `p` (since
  A3.6's rest, `ArcBlk`: an `arc` block or a view, a read guard a `make`
  may hand back, whose type the model does not tell from an `Arc`'s).
- `EvalR.globP`: a read the store cannot answer at that type panics. A2's
  one thread, run from the empty store, holds no global, so every read
  panics there. In A3 a read of a start-set global, at the type the start
  holds it at, never panics (`Reach.glob_noPanic`, below).
- `GlobsOK G`, a premise of `A3.claim`:
  - `sync`: each global holds a share of a block of a type `Ty.sync`
    admits (`GlobFits`);
  - `inv`, `cover`: the store the `make`s left is one A2's invariant holds
    of with no binding (`MInv (G.mem 0) ∅`: every block a well-formed tree
    of its type, owning its payload's addresses once; `Covers`: nothing
    else is allocated);
  - `reach`: every block is reached from a global, since the sweep that
    ended the last `make` left no other;
  - (A3.5b) `codes`: every package a block holds names code of the
    program (`BlkCodes`), as `MemCodes` says of the store a typed `make`
    leaves. So `GlobsOK` takes the program: `GlobsOK P G`.
- `Cfg.roots`: the configuration's sweep counts the globals' shares as
  roots, beside every thread's slots (`Cfg.sweep`). So a global's block,
  and every block its payload reaches, lives as long as the program runs.
- `NoLeak`, restated: when every thread has ended, every live address is
  owned by the payload of a block the start's globals reach.
- Scalar globals: `Stmt.loadGlobal h x g s` (`: i x g`) is an `Atomic` load
  through a clone `h` of the global's share, and `Stmt.storeGlobal h x g e
  s` (`= g e`) an `Atomic` store of the integer expression `e`. A scalar
  global is an `Atomic` set at start, a global of type `lk int`, A3.4's
  integer lock block.

**A2's proof.**
- `rhs_pres`: a read keeps the store (`RhsPost.same`), and its share is
  `out_glob`. That is `out_lkShare` or `out_share`, with the payload's
  well-formedness from `MInv.blocks`.
- `evalR_exists`: `EvalR.glob` when the store holds the global at that
  type, `EvalR.globP` otherwise, so progress never fails on a read.
- `covers_evalR`: a share owns no address. `EvalR.codes`: it holds no
  package. `Rename`, `Wf`, `NameWf` and `SrcKeep` take `new`'s case, since
  the read names no variable.
- No part of A2's invariant reads `gl`. A2's sweep (`Steps`) is still over
  the slots: A2 runs one thread from the empty store, which holds no global.

**A3's proof.**
- *A read touches no address.* A share is no address, and its count is
  ghost; the runtime's count is an atomic word, as for `arcClone` (A3.1).
  `Touch` and `Race` are unchanged.
- *The frame lemmas.* The read looks at `m.gl` and `m.blk`, which a thread's
  own view and the configuration's share (`EvalR.restrict`, `EvalR.lift`,
  `EvalR.borFree`, `EvalR.ownedId`). A global's share is a lock share or
  an `arc` share, never a cell share, so CellInv is unchanged
  (`EvalR.cellVal`).
- *No step writes a global* (`Step.gl`, A3/Fresh.lean): every rule rebuilds
  the store with `gl` as it was. `Cfg.put` writes back the step's `gl`,
  which is the view's (`CParts.thread_of`), and a spawn and the sweep keep
  it (`TStep.gl`, `Reach.gl`).
- *The sweep keeps what the globals reach.* `CInv`'s second half: every
  block is reached from a root, a thread's slot or a global. Race
  freedom's sweep case counts the globals among the roots that no step of
  the stepping thread changes (`Cfg.rootsBut`). So no sweep frees a
  global's block, and two threads' sweeps never free one block.
- *A global stays readable.* What a global's share fits at the start it
  fits in every configuration the start reaches (`Reach.globFits`). A step
  keeps a lock block as a lock block of its type and an `arc` block as it
  was (`GlobFits.grow`), and the sweep keeps every block a global reaches
  (`GlobFits.sweep`). So no thread's read at the start's type panics
  (`Reach.glob_noPanic`).
- *The start.* `CInv.start` and `ThreadOK.start`: one thread with no
  binding, on the globals' payloads. That is A2's empty store with the
  globals set (`inv_emptyGl`), grown to their blocks by `ThreadOK.move`
  (`GlobsOK.blocksAt`, `GlobsOK.alloc`). `CellInv.start`: no thread holds a
  cell share, and a global is no thread's binding.
- *no_leak* (`CInv.noLeak`): a finished thread owns no tree and no slot is
  left. So every live address is a payload's, of a block reached from a
  root, and the only roots left are the globals.

**no_leak: what the globals reach is left.** There were two choices:
- the globals are roots only while some thread runs, and the sweep after
  the last thread's last step frees them, so nothing is left;
- the globals are roots for good, and the end leaves exactly what they
  reach.

The second is taken. It is the runtime's: a global set at start is never
dropped, and the process's exit returns its memory, with no destructor
run. The first would not even hold at a start that has already finished:
with `s = skip` and allocating globals, no step runs, so no sweep does.
`NoLeak` says every live address left is owned by a block the start's
globals reach (`Reached C0.globVals`). With no global, nothing is left
(`NoLeak.empty`, `A3.no_leak_init`: A3.0's statement).

**Faithful to the runtime.**
- *Set at start.* The start holds what `main` finds once the `make`s have
  run: each global's share and the blocks they built (`GlobsOK`).
- *Nothing writes `g` afterwards.* No step writes `gl` (`Step.gl`), so the
  share a thread reads is the one the start holds (`Reach.gl`).
- *A read borrows the handle.* The model reads a clone, a share the
  reader's binding owns for the read's scope. Its drop frees nothing
  (`Frees.lk`, `Frees.arc`), and the global keeps its block, a root. A
  borrow of the handle and a clone reach the same block and the same
  payload, so every step after the read is the same. The clone's count is
  ghost, and the runtime's is never touched by a borrow; neither is
  observable.
- *`: ( Locked T ) h g`, a struct field, `^ g`.* They clone, and so does the
  model: the clone moves into the binding, the field or the result.
- *The global outlives every reader.* The runtime's global lives until the
  process exits. The model's block is a root of every sweep. So A3.2's
  faithfulness premise, that the lock outlives the body, holds of a
  `Locked` global by construction (`Stmt.lockGlobal`: `h`, the clone, is
  an owner the body does not name).
- *Phase D* (A3.1's obligation) is trivial for a global's own share. The
  runtime's count of a global's block never reaches 0 while the global
  holds it, and the model never sweeps it. The clones are A3.1's case,
  unchanged.
- *`unsafe` globals.* An owning global, and a struct or option global of
  plain values, are reached only in `unsafe` functions, which vouch that no
  other thread replaces the value while it is in use. They are trusted
  base, as an `unsafe` body is; the model has no rule for them.

**Scalar globals: relaxed atomics (a stated assumption, not a proof).**
- *The model.* A scalar global is an `Atomic` set at start (`lk int`). A
  read is A3.4's `atomic load`, and a write `atomic store`, each one step on
  the block's word.
- *The runtime.* The compiler reads and writes a scalar global with relaxed
  (LLVM `monotonic`) atomic loads and stores
  (`compiler/tests/global_atomic_ir.sh`), where `stdlib/std/atomic.nu`'s
  `Atomic` is `seq_cst`. A3's DRF-SC citation (*The theorem*, above) is for
  programs whose atomics are all `seq_cst`.
- *What holds either way: race freedom.* A C11 data race is two
  conflicting accesses, unordered by happens-before, not both atomic.
  Every access to a scalar global is atomic, a relaxed one included. So no
  access to a scalar global takes part in a data race, under any ordering.
  The model's word is no address, and the model's race freedom is about
  every other address, which no scalar access touches.
- *What the interleaving model may miss.* With relaxed accesses, C11 admits
  executions that no interleaving has. A load may answer a store older than
  an interleaving allows, and two threads may see stores to two globals in
  different orders, since a relaxed store does not happen before the load
  that reads it. DRF-SC, as cited, does not reduce such a program to the
  model's interleavings.
- **Assumption (A3.6).** A C11 execution of a program whose scalar globals
  are relaxed agrees, on every fact the claim states (what is allocated,
  which binding or block owns it, which non-atomic accesses happen in which
  order), with an interleaving of the model in which each scalar load
  answers some integer, possibly one no interleaving would give. Why this
  is expected:
  - a scalar's value decides no ownership: the word owns no address, and
    an integer moves, lends and frees nothing;
  - no non-atomic data is published through a scalar global, since in safe
    NURL a thread reaches another's memory only through a spawn, a lock, a
    channel or a frozen `Arc` payload, which are the runtime's
    `seq_cst` / lock synchronisation, so DRF-SC as cited covers them.
- *What would prove it.* A model whose scalar loads answer any integer. A3's
  proof would carry over, since no lemma of it reads the integer an atomic
  step answers (`atomic_pres`: an `intE` answer, `AOp.run` only computes
  it). That model, and the relaxed-to-havoc reduction, are not mechanized.
  The assumption joins DRF-SC in the trusted base.
- *Scalars that are not integers.* A bool is 0 or 1. A float is a word whose
  bits decide no ownership. An `s` global holds a literal's address: static
  text, never freed (h273: safe code cannot store an owned string in it).
  The calculus's `Nat` word stands for all of them, as A3.4 notes for
  `sub`.

**The rest: the make phase, and the read's type tied to the declaration**
(`A3/Make.lean`; `Stmt.globsAt` in `A2/Codes.lean`).
- *The declarations.* A program's globals are a list of `Decl`s, global `g`
  the `g`-th: its `make`, a function of the program, and its declared type.
  `declTy D` is the program's global type environment (`GTy`). `DeclsOK P D`:
  each `make` takes no parameter and hands back an owned value of a type
  `Ty.sync` admits.
- *The read's type.* `Rhs.globAt GT` asks `GT g = some t` of a read
  `glob g t`, `Stmt.globsAt GT` of every read in a statement, and
  `ProgGlobs P GT` of every function's body. It is a program-wide check
  beside the typing, as `ProgCodes` is: `RhsT` takes no program, and giving
  it one would touch every rule and lemma over right-hand sides. `RhsT.glob`
  is unchanged; a read typed by it and checked by `globsAt` is at its
  global's declared type.
  - `globs_step` (A2): a step leaves a part of its statement or a function's
    body, renamed (`Stmt.globsAt_rename`, `callIn_globs`), which reads what
    it read.
  - `Reach.globsAt`: a spawn leaves the spawner's statement with its call
    replaced and the spawned body (`Redex.globsAt`, `Redex.globs_hole`).
  - `Reach.glob_typed`: from a start that holds each declared global at its
    declared type (`GlobsAt`), no thread's next read of a global
    (`NextRhs`) is `EvalR.globP`: the read is at the declared type
    (`NextRhs.globAt`), and A3.6's `Reach.glob_noPanic` does the rest.
- *The make phase.* `Made P spawn D i G`: the first `i` globals are
  made, leaving `G`.
  - Global `i`'s `make` runs on a thread of its own from the store the
    earlier ones left (`Cfg.start G (makeStmt i d) 1`), by the program's own
    steps and sweeps (`Reach`), so a `make` may read an earlier global; a read
    of a later one is `EvalR.globP`, a panic before `main`.
  - `makeStmt i d` calls the `make` into variable 0, then reaches the
    hand-over point, `= 0 ( glob i t )`, which never runs. The phase takes
    the configuration of one thread at the hand-over point, moves 0's value
    into global `i` (`upd C.gl i`) and drops the binding, and the next `make`
    starts there.
  - The hand-over point is typed only if 0 is an owner of a `t`
    (`assignGlob_inv`, `handOver_inv`), so the thread's typing there, which
    A3's invariant holds (`ThreadOK`), says what 0 holds: a share of the
    declared type, whose block `MInv.shares` names (`globFits_of`).
  - `make_ok`: from a start `GlobsOK` holds of, the store one `make` leaves,
    its result handed over, is one again, with global `i` fitting its type.
    `reach_inv` is A3's invariant at the hand-over point (`CInv`, as
    `A3.claim` draws it, and `CellInv`). 0 is the thread's one binding
    (`Closed`), and it owns no address, so the store with no binding is a
    heap (`MInv.unbind`), every live address is a payload's (`Covers`), and
    every block is reached from a global: the result's or an earlier one's
    (the sweep's `CInv` half). Each cell's shares are in one block, below
    `nid` (`GlobsOK.cells`, A3.5's second cut): `CellInv`'s `one` and
    `blkBelow`.
  - `made_ok`, `made_globsAt`: the phase leaves `GlobsOK`, each global made
    so far at its declared type, the later ones unset; once all are made,
    `GlobsAt G (declTy D)`.
  - `made_safe`: every `make`'s run is memory-safe and race-free (`A3.claim`
    on its start). The other way a `make` ends is a panic no frame catches,
    before `main` (`MakePanics`). A `make` may also run forever, or wait
    forever on a lock, and the phase never ends.
- `A3.claim_made`: for a program A2 types whose globals are declared
  (`DeclsOK`) and read at their declared types (`ProgGlobs`, and the main
  statement's `globsAt`): every `make`'s run is safe, and once every global
  is made, the run from that start is memory-safe, race-free and leaves
  only what the globals reach, and no thread's read of a global panics.

**Faithful to the runtime** (the rest).
- *`make` runs once before `main`*, in declaration order, each on the store
  the earlier ones left. The model runs each on a thread of its own, with
  the program's steps, and starts `main` from the store the last one left.
- *The result is stored as the global* and the `make`'s frame is gone: the
  phase moves the result out of variable 0 and drops the binding, which
  owns no address (a share): the global keeps the block.
- *The read's type* is the declaration's in nurlc, which types each read by
  it; `ProgGlobs` is that check.

**Simplifications in this cut.** Each is a restriction, and sound as stated.
- *A `make` is single-threaded.* A `make` that spawns a thread never
  reaches a configuration of one thread at the hand-over point, so it never
  completes the phase in the model.
- *A `make` hands back an owned share* (`resOwn`).
- *A read is a clone, not a borrow.* The two agree on every step (above).
- *A global's payload is what a lock's or an `Arc`'s may hold* (A3.1–A3.4's
  restrictions: no view or closure; a lock's, no share).
- *`Mutex` is a `Locked`* (a lock block). `Cond` and `Semaphore` have no rule
  in the calculus: they hold no payload a thread reaches. A global of one is
  not modeled.
- *Scalar globals are `Atomic`s*: integers, with A3.4's `Nat` arithmetic.

**Probes** (`tools/fuzz/holes/*.nu`).
- h263 `start_global_shared_unsynchronised`: a `( Vec i )` set at start and
  pushed from two threads. `Ty.sync (vec _)` is false, so `RhsT.glob`
  refuses any read of it (`glob_not_vec`), and `GlobsOK.sync` refuses the
  start: a start-set global holds a share of a synchronising block only.
- h272 `struct_global_torn_between_threads`: a struct global of plain values
  (`Pair`), written and read by two threads. It is no scalar, so not an
  `Atomic`, and `Ty.sync (prod _ _)` is false (`glob_not_prod`): safe code
  cannot read it. At run time it is `unsafe`-only (trusted base); safe code
  keeps it in a `Locked` set at start, or as two scalar globals.
- h273 `string_global_freed_under_reader`: safe code assigned an `s` global a
  fresh string, and the next assignment freed it under a reader on another
  thread. No rule writes a global (`Step.gl`). A scalar global's write is an
  atomic store of an integer expression (`Stmt.storeGlobal`, `RhsT.atomic`),
  and an expression moves no owner, so safe code cannot hand a global
  anything to own. Text that changes at run time lives in a
  `( Locked String )` set at start, whose update is A3.2's `withLock`
  (`Stmt.lockGlobal`), and a reader takes the lock too. An `unsafe` store
  is trusted base.
- h202 `global_string_from_per_call_owner_leaks`: a string global given the
  result of a call whose ownership is decided per call. It is rejected since
  h273, by the same rule: safe code hands a global nothing to own. The
  owning codegen it exercised is `unsafe` code's, trusted base.
- h254 `symtab_shared_between_threads`: a `SymTab` in an `Arc`, changed from
  two threads with no lock. This is A3.5's rule. A `SymTab` is a library
  handle whose table the library changes in place with no lock (`% NotSync`):
  a cell. `RhsT.arcNew` refuses an `Arc` of one (`Ty.hasCell`), and a
  start-set `( Arc SymTab )` is refused likewise (`Ty.sync (arc t)` asks
  `t.hasCell = false`, `glob_not_arc_cell`).

**Not proven here.**
- that the make phase ends: a `make` may loop or wait forever (deadlock
  freedom, as before); and a `make` that spawns a thread;
- the hand-over point as a statement of the calculus: the phase's move of
  the result into `gl` is the phase's, not a step's, so no rule writes a
  global still (`Step.gl`);
- *The relaxed-atomics assumption* above.
- *`unsafe` globals* (owning, struct and option globals): trusted base.
- *`Cond` and `Semaphore` globals.*
- *The probes as typed programs* (a probe's encoding, as `A2/DynCell.lean`
  types `pick`).

## A3.2's second cut (shares in lock payloads, `locked_take` / `locked_restore`)

**Status.** Mechanized. `check.sh` is green, and `A2.memory_safe`,
`A2.soundness`, `A2.no_leak_end`, `A2.no_leak_panic`, the `DynCell`
theorems and `A3.claim` are re-proven. The cut has two parts:
- (A) a lock's payload and a channel's element may hold `arc` and lock
  shares, and so Sync closures;
- (B) `locked_take` and `locked_restore` are rules of their own
  (`Rhs.lockTake`, `Rhs.lockRestore`).

h267 is part (B)'s probe, and it needs (A): its payload holds an `Arc`.

### (A) Shares in a lock's payload and a channel's element

The first cuts asked `!t.hasArc` of a `Locked`'s payload (A3.2), of an
`RwLocked`'s (A3.3), of an `Atomic`'s word and of a channel's element
(A3.4). The lock block's payload then kept no block alive, which
`MInv.blocks`' fourth conjunct said. Lifting it has three pieces: the
types, what the sweep follows, and a recover frame's blocks.

**The types.**
- `Ty.ok (lk t)` asks `t.ok && !t.holdsView && !t.hasCell`.
  `RhsT.lockNew` asks `t.holdsView = false ∧ t.hasFn = false ∧
  t.hasCell = false`. `RhsT.chanSend` reads `Ty.ok` of the channel's type
  (`chan_tyok`).
- So a `Locked (Arc T)`, a `Locked (Locked T)`, a `Channel (Arc T)`, a
  channel of `Atomic`s and a channel of channels are typed.
- A cell share stays out (`hasCell = false`). A3.5's confinement
  (`CellInv`) counts the slots of each thread. A cell share parked in a lock
  would be owned by no slot, and every lock entry would need the crossing
  check. That is not done (*Not proven*, below).
- A cell's own payload (`Ty.ok (cell t)`, `RhsT.cellNew`) still holds no
  share at all: a library handle's state is unchanged by this cut.
- `MInv.blocks`' fourth conjunct is now `bl.kind = .lock →
  bl.ty.hasCell = false`. A3.5 reads it to show that no lock payload holds
  a cell share (`ThreadOK.noCellPay`, `WFv.noCell`, now stated for
  `hasCell`; `Ty.hasCell_of_hasArc` moved to `Syntax.lean`).

**A lock's payload keeps what it holds alive.**
- `Blk.keeps bl` is a block's payload, `bl.pay.getD (.int 0)`, whatever
  its kind. `Reached.pay` follows it where it followed `Blk.rd` (what
  holders read: an `arc` block's and a view's payload, nothing of a lock
  block's).
  - A lock block's payload counts while it is in the block.
  - A checked-out payload is in its holder's slot, a root of its own. So
    is a received element, and a taken payload (part B).
  - So a share counts wherever it is, as A3.1's `Arc` payloads already
    did. No root is added.
- `MInv.sweepR` keeps a lock block's `SharesOK` the way it keeps an `arc`
  block's (`Kept.pay`): the case that read the fourth conjunct is gone.
- **What other threads reach survives a thread's step.** A lock's payload
  changes under a step, and `BlkKeep` lets it. So reachability no longer
  survives `BlkLe` alone (`Reached.mono` now asks for the blocks kept
  exactly; `Reached.roots` for the roots only).
  - `Step.leafKeep` (A2): a share or a handle (`Val.leaf`) in a block's
    payload is, after a step, in that block's payload still, or, for a step
    that does not panic, in one of the stepping thread's slots. That is a
    check-out (`withLock`), a received head (`chanRecv`) or a taken payload
    (`lockTake`).
  - A panic's unwinding only gives payloads back, so it moves none out.
    `EvalR.leafKeep` and `Release.leafKeep` are the parts.
  - `Reached.step` (A3/Pres.lean): what the other threads' slots and the
    globals reach before a thread's step, the configuration's roots reach
    after it.
  - Race freedom's sweep case (`CParts.ctouch`) used `Reached.mono` with
    `Step.grows`. It now uses `Reached.step`, so the sweep's frees are still
    of payloads no other thread reaches. The partition is unchanged.
- **A recover frame's store** (`CatchOK`). The frame's typing of the
  caller's bindings, `MInv (m0.set x _) Δ`, is grown to the store the
  panic returns to (`catchP`). Before this cut that went through
  `m0.sweep`, whose blocks the frame keeps.
  - With lock payloads followed, `m0`'s sweep keeps what a lock's payload
    held at the frame's entry. The body may have taken that out of the lock
    and dropped it, through a lock share it reached as a clone of a global's
    (A3.6).
  - So `CatchOK` now asks to keep what `m0`'s bindings reach through
    payloads that are read: `Reached (OutVals m0 x sp) (rdBlk m0.blk)`.
    `Blk.rdOnly` leaves a lock block's payload out, and a view's payload,
    being read, is followed.
  - That is exactly what the bindings' facts read (`ValOK`, `SharesOK`, and
    `NodeAt` / `DataAt` through `Blk.rd`).
  - `MInv.regrow` carries the slots' facts there. It goes to the store with
    every lock's payload left out, sweeps from the slots, and grows to the
    store returned to. The store with the payloads left out need not be a
    heap (a view reads its lock's payload), so the lemma is over the slot
    facts, not `MInv` of the store in between.
  - `Reached.catch` and `Reached.of_rdBlk` keep `CatchOK` through the sweep.
- **Payloads in and out carry their shares' facts.**
  - A checked-out or taken payload: `acquire_pres`'s `RhsOut.shares`, from
    the block's `SharesOK`.
  - A received head: `chanRecv_pres`, `out_ownNoView` (which now takes
    `SharesOK` in place of `hasArc = false`).
  - A payload changed in place: `setPay_pres` takes the new payload's
    `SharesOK` (`chanSend_pres`, `chanRecv_pres`, `chanClose_pres`).
  - A view's copy of the payload: `rhs_rwRead`.
  - A give-back on the normal path: `step_release`, from `x`'s typing.
- **A give-back with no typing at hand** (a panic's unwinding, `scopeLP`)
  must still leave the block's shares naming blocks of its type.
  - `Giveable B t` now asks `SharesIn B t v` beside `WFv t v`, over the
    store's blocks (`Release` passes `m.blk`).
  - `ArcIn`, `ArcBlk`, `ShareFits` and `SharesIn` moved from
    `Invariant.lean` to `Semantics.lean` for this, as `WFv` did in A3.3.
  - `BlkBack` carries it (`Giveable.shares`, `MInv.blocks_back`).
  - A typed program's `x` holds a `t` whose shares fit (`MInv.shares`), so
    its end is still a `put`. When they do not fit, the slot is dropped
    (`Release.drop`), as for a payload of the wrong type.

**Closure classes** (A3.5b). `Ty.hasCell (fn ms q) = q.cells`, so a lock or
a channel now takes a `sync` closure as well as a `bare` one (`lockNew_fn`,
`chan_fn`: `q = .sync ∨ q = .bare`). A `sync` closure's environment holds no
view, nothing by name and no cell share, but may hold `arc` and lock shares.
- `Cross` and `Cross.Fits` are unchanged, only their documentation. The
  payload condition "no view, no cell" is the type's (`Ty.ok (lk t)`), and
  it reads a closure's class through `holdsView` and `hasCell`.
- `bare` stays. A slice's element still holds no share
  (`Ty.ok (slice t)`, `RhsT.view`: A3.1's first cut), and a slice of
  closures needs `bare`. Nothing else needs it now. (Since shares in a
  slice, below, no rule asks for it.)
- *Trait objects* (A3.5c). An object of a `: Send Sync` trait is a `sync`
  package (`TraitBound.cross`), so it now fits in a lock and a channel. An
  object of a `: Send` trait is a `send` package. Its type says it may hold
  a library handle, so it still fits in neither, even when its box holds no
  cell share: the class is the type's, and the type does not say what the
  box holds. Packing it at `sync` would fit, but its trait's methods take
  it at `send` (`TraitAt`), so it could not be called. Closing that gap
  needs a cell share in a lock's payload, with the crossing check at every
  lock entry, or a subsumption from `sync` to `send` at a call. Neither is
  done.

**A3: the partition and race freedom.** A share is a word that names a
block. It owns no address (`Val.ids`), so moving one with a payload is what
A3.2's check-out already moves.
- `CParts`, `PayIn` and `payPart` are by `Blk.tree`'s addresses, and are
  unchanged.
- The sweep's frees are of payloads no other thread reaches
  (`Reached.step`, above). `CInv`'s second half, that every block is
  reached, is the sweep's, from every thread's slots and the globals.
- `CellInv` is unchanged: a lock's payload holds no cell share
  (`ThreadOK.noCellPay`).

### (B) `locked_take` / `locked_restore`

**The rules.**
- `Rhs.lockTake a` (`locked_take a`), typed by `RhsT.lockTake`: `a` is a
  live lock share `lk t`, and the result is `lockE t`. That is the
  payload, owned, of its type, holding nothing (an integer is a plain
  integer binding), as `withLock` checks one out.
  - `EvalR.lockTake`: the payload is in and no view of it lives. It moves
    out as the value handed back, and the block holds `none`.
  - With the payload out, or a view of it living, there is no step:
    `RBlocked`'s new case. So the thread waits (`Blocked`) or panics
    (`Step.waitPanic`, through `Waits`).
- `Rhs.lockRestore a y` (`locked_restore a y`), typed by
  `RhsT.lockRestore`: `a` a live `lk t`, `y` a live `t` handed over by
  `PushArg`, as `chan_send` takes its value (an owner moves and its entry
  dies, an integer is copied). The answer is an integer (`intE`). It is a
  right-hand side, as `chanSend` is, so every rule and lemma on right-hand
  sides covers it.
  - `EvalR.lockRestore`: the block's payload is out. `y`'s value
    (`TakeVal`) goes in, and the answer is 0.
  - `EvalR.lockRestoreP`: the payload is in, so the restore panics, the
    store as it was. `y` keeps its value, and the unwinding drops it.
  - A restore never waits.

**A2's proof.**
- The take is `acquire_pres` (moved before `rhs_pres`).
- The restore is `lockRestore_pres`. That is `setPay_pres`, generalised to
  a block whose payload is out (`o : Option Val`), with `push_take`'s
  `Pushed`. No view of an empty block lives (`ViewsAt.noView`).
- `covers_evalR`: a taken payload is the value in flight
  (`Val.owns_of_mem_ids`, moved before it), and a restored one the block's.
- `evalR_exists`: a take steps unless it waits. A restore steps either way
  (`takeVal_exists`).
- `EvalR.codes`, `EvalR.blk`, `EvalR.leafKeep`, `RBlocked.of_eq`,
  `evalR_none`, and the cases in `Rename`, `Wf`, `NameWf`, `SrcKeep`,
  `TypingFacts` and `Call` are `chanSend`'s for the restore, and
  `chanRecv`'s or `withLock`'s for the take.

**A3's proof.**
- No touch, as for a check-out: the payload's tree moves between the block
  and the thread's part. `EvalR.ownedId` says a taken payload's addresses
  were a payload's (`PayAddr`). `EvalR.payAt` says a restored one's were
  the thread's own.
- `EvalR.cellVal` and `EvalR.cellSt` cover the cells: a taken payload was a
  lock's, which holds no cell share.
- `EvalR.restrict`, `EvalR.lift`, `EvalR.borFree`, `EvalR.grows`,
  `EvalR.gl` and `EvalR.keep` get the new cases.

**h267** (`option_taken_from_locked_stays_in_slot`). A `( Locked ?K )`
whose `K` holds an `( Arc String )`, taken and restored in a loop. The
runtime's `locked_take` left the option in the lock's slot (`mem_take`
misparsed its type), and the restore, which dropped what the slot held,
dropped the value being handed back. The next take read freed memory.
- The rule is `EvalR.lockTake`: the take moves the payload out and the
  block holds `none` (`lockTake_empties`).
- The restore then finds nothing to drop. `EvalR.lockRestore` moves the
  value in and frees no address (`lockRestore_frees_nothing`), and it
  applies only to a block whose payload is out.
- The payload is an `Option` (`sum int _`) of a struct that holds an
  `arc (vec int)` (the `Arc String`), which part (A) types. The `Arc` is
  kept alive by the lock's payload while it is in
  (`Blk.keeps`), and by the taker's slot while it is out.
- So the model has no state in which the lock still holds what the taker
  owns.

**Faithful to the runtime** (`stdlib/std/thread.nu`, docs/MEMORY.md
§7.6's *A value claimed out of a place leaves a zero behind*).
- *The take moves.* `locked_take` copies `. p val` into `x`, and
  `mem_take x` leaves zero bytes in the slot, which own nothing. It sets
  `taken` and unlocks. So the value moves out to the caller and the lock's
  slot holds nothing, as `EvalR.lockTake` has it.
  - The value's heap memory is the same memory before and after. Only its
    owner changes, from the lock to the caller, as the model's tree keeps
    its addresses and changes owner.
- *The restore moves back.* `locked_restore` swaps `x` into the slot
  (`mem_replace`) and forgets the zero bytes, with no drop glue. It then
  clears `taken`. That is `EvalR.lockRestore`. "The value was not taken"
  panics, which is `EvalR.lockRestoreP`.
- **No faithfulness premise is needed** (unlike `withLock`'s "the lock
  outlives the body"). `withLock` models an in-place update as a move out
  and back, so the two agree only while the lock lives. The take really is
  a move.
  - If the last share is dropped while the value is out, the runtime frees
    the `LockedImpl` and its zero bytes, which drops nothing. The model's
    sweep frees the block, whose tree is `.int 0`, which frees nothing.
  - The taker owns its value either way, and drops it or moves it on.
  - A restore needs a live share (`a`), so it never meets a freed lock in
    the model.
  - So the share need not outlive the taken value, and the sweep needs no
    premise for it.
- *Waiting.* Every operation on a taken `Locked` waits on `cv` until the
  restore. In the model, `withLock`, `lockTake`, `rw_read` and the atomic
  and channel steps wait while the payload is out (`Blocked`, `RBlocked`). A second
  take by the same thread waits forever at run time, and in the model it
  waits or panics.
- *A restore while another thread has the payload checked out by
  `locked_update`.* The runtime's restore waits for the mutex, then panics,
  since `taken` is false. The model's restore finds the payload out and
  puts its value in. The updater's end then finds the block full and drops
  its `x` (`Release.drop`).
  - That is a behaviour the runtime does not have, and it is memory-safe in
    the model.
  - The runtime's behaviour is a model run too: the restorer steps after
    the updater's end, and panics (`lockRestoreP`).
  - The model tells a take from a check-out by nothing (the design's
    `held` is not stored, A3.2), so it over-approximates here.
- *The crossing check.* `locked_restore`, `locked_new` and `chan_send` run
  `mem_send_check` on what goes in. A lock's payload and a channel's
  element hold no cell share (part A), so there is nothing for it to find.
  The model refuses statically what the check would count.
- *Phase D* (A3.1's obligation) now covers lock payloads. The runtime
  counts a share in a `LockedImpl`'s value as it counts any other, and the
  model's sweep follows it (`Blk.keeps`).
  - **Cycles.** A share in a lock's payload can lead back to the lock, but
    only through a closure's or a trait object's environment, whose type
    the package's type does not show. Without a package the lock's type
    would be infinite. A `Locked` of a `sync` closure that captured a clone
    of its own lock's share is one.
  - The model's sweep collects such a cycle once no root reaches it. The
    runtime's counts never would, but nurlc rejects the store that would
    close it (docs/MEMORY.md §7.7: a store into an existing thread-shared
    handle may not lead back to it).
  - So phase D's agreement is stated of the programs nurlc accepts. The
    store rule is not modeled, so the model types more programs, all of
    them safe.

**Simplifications in this cut.** Each is a restriction, and sound as stated.
- A lock's payload and a channel's element hold no cell share, and a cell's
  own payload holds no share.
- A `send` closure or trait object fits no lock or channel (above).
- `locked_take` takes only through a lock share (`lk`), not a cell share.
- `locked_set` (a restore after a take), `locked_get` (a copy),
  `locked_with` (a closure called through a package), `locked_apply`'s
  result and `locked_await` are not rules of their own. (Since A3.2's and
  A3.3's rest, below, `locked_set`, `locked_get`, `locked_apply`'s result
  and `locked_await` are derived forms, each with its typing lemma; the
  closure `locked_with` and `locked_update` run is a statement in place or a
  function of the program, not a closure called through a package.)
- A slice's element holds no share. (Lifted by shares in a slice, below.)

**Not proven here.**
- *Cell shares in a lock's payload or a channel's element*, with the
  crossing check at every entry, and so `: Send` trait objects (class
  `send`) in a lock or a channel. (Closed by A3.5's second cut, below.)
- *Shares in a cell's state.* (Closed by A3.5's second cut, below.)
- *§7.7's store rule*, which keeps cycles out of thread-shared handles, and
  so phase D's agreement for programs that would close one (above).
- The probe h267 as a whole typed program (a probe's encoding, as
  `A2/DynCell.lean` types `pick`). `lockTake_empties` and
  `lockRestore_frees_nothing` state its rule on one step each.
- *The rest of the lock operations*: `locked_get`, `locked_set`,
  `locked_apply`'s result, `locked_await`, `Mutex` beside the data it
  guards, and a lock reached through a local borrow. (Closed by A3.2's and
  A3.3's rest, below.)
- Deadlock freedom, and that a waiting take is ever let in.

## A3.5's second cut (library handles in locks and channels)

**Status.** Mechanized. `check.sh` is green, and `A2.memory_safe`,
`A2.soundness`, `A2.no_leak_end`, `A2.no_leak_panic`, the `DynCell`
theorems and `A3.claim` are re-proven. A lock's payload, a cell's state and a
channel's element may now hold library handles (cell shares), and so Send
closures and `: Send` trait objects. Every value going into a lock block
faces the crossing check, as a spawn's arguments do, and a failed check
panics. A3's confinement keeps a cell's shares in one place: one thread's
slots, or one lock block's payload. This closes the gaps A3.2's second cut,
A3.5b and A3.5c listed (*Not proven here*, there).

The runtime it models is docs/MEMORY.md §6.5, *The crossing check*:
`mem_send_check` runs at `chan_send` and at every value going into a
`Locked` — `locked_new`, `locked_set`, `locked_restore`, and the value
after a closure ran on it under the lock (`locked_with`, `locked_update`),
checked before the lock is let go, a failure panicking with the lock held
(`stdlib/std/thread.nu`, `stdlib/std/channel.nu`).

### The check at every entry

**Where it lives: A2's semantics.** `SendCheck vs st'` moves from A3 to
`A2/Semantics.lean`, unchanged: for every cell a crossing value holds a share
of (`Sub (.cell k) v`), no slot left behind (`st'`) holds one. A2's store is
one thread's view, so its slots are the thread's slots, and the check reads
nothing else. It is the run-time precondition A3.5 used for a spawn, now
asked at each entry:
- `EvalR.lockNew` and `EvalR.cellNew` (`locked_new`, a library handle's
  constructor) ask `SendCheck [v] m1.st` of the value taken from `y`, over
  the slots `TakeVal` left;
- `EvalR.lockRestore` (`locked_restore`) asks it the same way;
- `EvalR.chanSend` and `EvalR.chanSendClosed` (`chan_send`) ask it before
  anything else: the runtime checks before it looks at the channel;
- a lock scope's give-back asks `GiveCheck m x sl`: `x`'s value against
  every other slot, `SendCheck [v] (m.remove x).st` (`Release.put`,
  `Step.scopeLSkip`).

**A failed check panics**, the store as it was, as `mem_send_check` calls
`nurl_panic` before the crossing does anything:
- `EvalR.lockNewFail`, `cellNewFail`, `lockRestoreFail` and
  `chanSendFail`. A right-hand side's panic is A2's (`Step.letvP`), so the
  unwinding drops `y` with its scope;
- `Step.scopeLFail` for the give-back (below).

**The give-back's check is a panic.** Neither of the other two choices fits:
- *A premise* (no step when it fails) would make a typed program stuck,
  and `memory_safe` false: the check does fail in typed programs.
- *Typing* cannot rule it out. The body of a `withLock` may `cellClone` a
  handle the value holds and move the copy to a binding outside the scope,
  push it into an outer `Vec`, send it on a channel; or (h354) move a copy
  of one kept outside into the value. A2's types do not say which owner a
  cell share came from, so ruling these out would need an escape analysis
  of cell owners across the body, which nurlc does not make either: it
  checks at run time.
- So it is the runtime's own: the check runs after the body, before the
  lock is let go. `Step.scopeLFail` steps `.scopeL k t x .skip`, whose `x`
  fails `GiveCheck`, to `.scopeL k t x .panic`, the store as it was: a
  panic put in the scope, as `TStep.spawnFail` puts one before its call.
  The panic then unwinds through the scope (`Step.scopeLP`), whose
  `Release` drops `x` (`Release.drop`'s condition gains `¬ GiveCheck`), and
  the block stays checked out: the lock is held, as the runtime's is.
- `Step.scopeLSkip` asks the check, so a scope's normal end gives back or
  panics, never drops silently (`scopeL_end`). On a panic's unwinding the
  give-back is `Release.put` only past the check, and otherwise drops `x`.

**A receive's check** (`RecvCheck v es`, `EvalR.chanRecv`,
`EvalR.chanRecvFail`). The head `v` shares no cell with an element `es`
left in the queue, or the receive panics.
- The runtime has no such check and needs none: a `Channel`'s queue is
  filled by `chan_send` alone, one checked value at a time, and a value
  that passed the check holds every owner of each cell it holds. So no two
  elements share a cell.
- The model's channel is a lock block, and `Locked (Vec T, i)` and
  `Channel T` are one type (`lk (prod (vec t) int)`). A `withLock` on it
  may fill the queue with two elements that share a cell, which a receive
  would then split between the receiver and the queue. The check keeps
  the receive from splitting them; on the runtime's channels it never
  fails.

**Check-outs and takes need no check.** `withLock` and `lockTake` move the
whole payload out, and the block holds none of it after. What the receiver
gets is every owner the block held.

### The types

- `Ty.ok (lk t)` is `t.ok && !t.holdsView`: a `Locked`'s value, an
  `RwLocked`'s and a channel's element face the Send question only.
  `RhsT.lockNew` asks `t.holdsView = false ∧ t.hasFn = false`. `RhsT.chanSend`
  reads `Ty.ok` of the channel's type (`chan_tyok`, now two conjuncts).
- `Ty.ok (cell t)` is the same, and `RhsT.cellNew` asks what `lockNew` asks:
  a cell's state is a lock block's payload, and may hold shares now
  (A3.2's second cut left them out), the constructor checking it
  (`cell_cell_ok`).
- `Ty.hasCell (lk _)` is `false`. The Sync question asks whether several
  threads may reach a value at once. A lock share is Sync whatever its
  payload holds: the payload is reached by one thread at a time, and every
  value going in is checked. This is docs/MEMORY.md's "a Sync marker
  vouches for the container, never for its value, which faces the Send
  question" (h358). So an `Arc (Locked PNCounter)`, a Sync closure that
  captures a `Locked PNCounter`, and an `Arc` global of one are typed
  (`lk_sync`).
- `RhsT.rwRead` asks `t.hasCell = false`. An `RwLocked`'s read guards lend
  its value to several threads at once, so its value faces the Sync
  question, as an `Arc`'s payload does (h357, `rwRead_not_cell`).
  - The model's `RwLocked` is a `lk t`, made by `lockNew`, so an
    `RwLocked PNCounter` is made and written (`withLock`). It cannot be
    read.
  - A lent cell share is no share (`lendOf`), so a reader could not
    change the handle even without the premise. The premise is there to
    be faithful to the runtime, which asks the question. (Since A3.5's
    third cut, below, a lent cell share is the share, and the premise is
    what keeps a view's payload free of one: `MInv.blocks`.)
- `MInv.blocks` (and `BlocksIn`, `BlockOK.ok`) lose their fourth conjunct,
  `bl.kind = .lock → bl.ty.hasCell = false`. Only A3's `ThreadOK.noCellPay`
  read it, and it is gone (below).
- So a Send closure and a `: Send` trait object fit in a lock and a channel:
  - `lockNew_fn` and `chan_fn` say `q = .send ∨ q = .sync ∨ q = .bare`.
    `chan_fn` is an iff;
  - `lockNew_send`, `chanSend_send` and `lockNew_dyn_send` type them;
  - `chan_dyn` and `lockNew_dyn`: an object of any trait with a bound fits,
    none of a trait with no bound.

**A2's proof.** The checks are premises of steps A2 already had, and the
failures are panics with the store as it was, so A2's lemmas need no new
argument. The new cases are:
- `Release.exists` cases on the check, and A2's progress steps a scope's
  end to `scopeLSkip` or `scopeLFail`, and a right-hand side to the
  success or the failure (`evalR_exists`);
- `scopeLFail`'s preservation types `.scopeL k t x .panic` where
  `.scopeL k t x .skip` was, over the same store and context. A panic
  types into any context (`StmtT.panic`), and `skip_inv` weakens it to the
  scope's;
- `scopeLFail` in `step_new`, `step_gone`, `codes_step`;
- the lift and restrict lemmas: the checks read the slots only, which
  neither lemma changes.

With the fourth conjunct gone:
- `out_lkShare` and `out_cellShare` lose their `hasCell` / `hasArc`
  premise;
- `rhs_lockNew_post`, `rhs_rwRead`, `setPay_pres`, `acquire_pres`,
  `atomic_pres` and `step_release` no longer carry it.

### A3: confinement over slots and lock payloads

**Where a cell's shares are** (`A3/Cell.lean`).
- `LockHolds B k' k` (in `A3/Defs.lean`, for `GlobsOK`): lock block `k'`'s
  payload, while it is in the block, holds a share of cell `k`. That is a
  lock's payload, a cell's state, or a channel's queue.
- Two kinds of block are no place:
  - an `arc` block's payload holds no cell share (`RhsT.arcNew`'s premise),
    and nothing comes out of one but lent (`arcGet`);
  - a view's payload is a copy its holders are lent.
- `Holds m k`: a slot or a lock block holds one.
- `OnePlace m k`: no lock block holds one, or no slot holds one and only
  one lock block does.
- `CellsBelow m`: every cell share held names a key below `nid`.

**What a step does** (`CellKeep m m'`, `Step.cellKeep`). Every share the step
leaves was held before, or is a new cell's, at a key taken from `nid` in the
step (`holds`). And each cell's shares stay in one place (`one`, given
`CellsBelow`). Each case is one of four combinators:
- `CellKeep.shrink` / `slots` / `setVal`: shares move between slots or are
  dropped, and the lock blocks hold no more. This is every step but those
  below, including `arcNew` and `rwRead`, whose new blocks are no place.
- `CellKeep.moveIn k0 v`: `v` goes into lock block `k0` from a slot, and no
  slot left holds a share of a cell it holds. A cell's constructor's own
  new share is allowed, at a fresh key. Used for `lockNew`, `cellNew`,
  `chanSend`, `lockRestore` and `Release.put`. Before, the thread held the
  cell, so no block did; after, only `k0` does.
- `CellKeep.moveOut k0 v`: `v` comes out of block `k0` into a slot, and the
  block keeps no share of a cell `v` holds. Used for `withLock` and
  `lockTake` (the block is left empty) and `chanRecv` (`RecvCheck`).
  Before, `k0` was the cell's one place; after, the receiving thread's
  slots are.
- Compound steps compose by `CellKeep.trans`: an unwinding through nested
  lock scopes gives back to several blocks in one step, each give-back
  checked against the slots still left. `EvalR.cellKeep` and
  `Release.cellKeep` are the parts.

**The invariant** (`CellInv`):
- `home`: no two threads' slots hold a share of one cell (A3.5's);
- `apart`: no thread's slot holds a share of a cell a lock block's payload
  holds one of;
- `one`: no two lock blocks' payloads do;
- `below` and `blkBelow`: every cell share names a key below `nid`.

It is kept by every step of the configuration:
- *A thread's step* (`CellInv.thread_of`, which no longer reads `CInv`).
  - A cell another thread holds was in no block and not the stepping
    thread's, so it is neither after (`CellKeep.holds`).
  - Any other cell was in one place in the thread's view
    (`CellInv.onePlace`), and stays so (`CellKeep.one`).
  - The sweep only removes blocks (`LockHolds.of_sweep`).
- *A spawn* (`CellInv.spawn_of`) as before, by `SendCheck`. The blocks do
  not change, so `apart` for the new thread is the spawner's.
- *The start* (`CellInv.start`) holds no binding. Its blocks are the
  globals'. `GlobsOK.cells` asks that a cell their payloads hold have all
  its shares in one block, at a key below `nid`: the globals' `make`s ran
  the crossing check, as every thread does. A `Locked PNCounter` global is
  now typed (`Ty.sync (lk _)`), so the claim's hypothesis says it.
  `GlobsOK.empty` meets it.

**No cell race** (`CellInv.cellRaceFree`). `CellOp` still asks the thread to
hold a share in a slot (`CellOp.cellAt`), and `home` says only one thread
does. A share in a block's payload is reached by no thread's slot (`apart`)
until a check-out, a take or a receive moves it out, and then the cell's
shares are all in the receiving thread. `ThreadOK.noCellPay`, `CellPay`,
`EvalR.cellVal`, `Step.cell` and `WFv.noCell` (a duplicate of
`WFv.noCell_hasCell`) are gone.

**The address race** (`AddrRace`) is A3.2's argument, unchanged. A cell share
is a word that names a block and owns no address (`Val.ids`), so moving one
with a payload is what a check-out already moves.

### Faithful to the runtime

- *The check counts what the runtime's does.* The model's check asks that
  no slot left behind hold a share of a cell the value holds. The runtime's
  asks that the value hold every owner. In a reachable configuration a cell
  a thread's slot holds a share of has all its shares in that thread's
  slots (`CellInv.apart`, `home`), so the two agree. The phase D
  obligation is A3.5's, now for lock entries too: the runtime's count of a
  handle's block equals the cell shares the model holds.
- *What the walk follows.* `Sub` enters no share. A lock share in the value
  moves no cell: the lock's payload is the lock block's place, and it stays
  there. A cell whose state holds another cell's shares moves its shares,
  and the inner cell stays in the outer one's state. The runtime walks a
  handle's state and, where it does, counts there every owner of the inner
  cells, which `CellInv` puts in that state. So it passes when the model's
  check does.
- *The give-back.* The runtime checks after the closure ran and panics with
  the lock held, the value left in the `LockedImpl`. The model drops `x`
  and leaves the block checked out, so every operation on it waits, as on
  the runtime's held mutex. The value is freed sooner in the model, and
  nothing reaches it either way. A `locked_restore` from another thread
  could put a value into the held block: A3.2's over-approximation, which
  the model tells from the runtime by nothing.
- *A panic in the body* gives the payload back in the model when it passes
  the check (`scopeLP`, `Release.put`), and drops it otherwise. The
  runtime holds the lock (A3.3's over-approximation, unchanged).
- *The receive's check* is the model's own (above): on a channel the
  runtime fills it never fails.
- *`locked_set`, `locked_get`, `locked_apply`, `locked_await`* are derived
  forms (A3.2's and A3.3's rest, below). `locked_set`'s value faces
  `locked_new`'s check before the lock is touched, as the runtime's faces
  `mem_send_check` before `mutex_lock`; the value after each closure run
  (`locked_apply`, each round of `locked_await`) faces the give-back's
  (`GiveCheck`), as the runtime's is checked before the lock is let go.

### Probes (`tools/fuzz/holes/*.nu`)

- **h340** `closure_sent_on_a_channel_captures_a_kept_handle`. The closure
  captures the `PNCounter`: `pack` moves the handle into its environment
  (`PushArg`), which is `send` (`Cross.Fits`: no view, nothing by name). A
  channel's element may be a Send closure now (`chan_fn`, `chanSend_send`).
  - The rule changes from "a channel takes no closure that captures a
    handle" (`chan_fn` admitted only `sync` and `bare`) to the crossing
    check at `chan_send`.
  - A sender that kept an owner of the handle (a `cellClone` before the
    capture) fails it, and the send panics, with no other outcome
    (`chanSend_kept`, `EvalR.chanSendFail`).
  - A send that took every owner along moves the closure, the handle with
    it, into the queue (`chanSend_moves`). The receiver then holds the
    cell's every share (`CellInv`), and the sender none.
  - The runtime moves the captures statically, so the sender's later use is
    rejected. In the model the capture moves too (the binding is dead past
    `pack`), and a copy kept behind is caught at the send.
- **h358** `rc_in_a_locked_in_an_arc_on_two_threads`. The model's stand-ins
  for the `Rc` (A3.5c's h344) give two readings.
  - As a view, it is refused statically, as before: `Ty.ok (lk t)` and
    `RhsT.lockNew` ask `!t.holdsView`.
  - As a cell share, `Locked` of it is typed (`lk_cell_ok`), and so is the
    `Arc` of the `Locked` (`lk_sync`). The `locked_new r` while `r2` is
    kept panics (`lockNew_kept`, `EvalR.lockNewFail`), and so does the
    thread's `locked_restore` of `c` while `keep` holds clones
    (`lockRestore_kept`).
  - The rule changes from `lk_noCell` (`Ty.ok (lk t)`'s `!hasCell`) to the
    crossing check at `locked_new` and `locked_restore`. The runtime
    refuses the `Rc` statically, so here the model refuses less, and
    soundly: a crossing that takes every clone along leaves no count
    behind.
- **h357** `rwlocked_of_a_library_handle_on_two_threads`. The rule changes
  from `Ty.ok (lk t)` to two:
  - `RhsT.rwRead` asks the Sync question of the value (`rwRead_not_cell`),
    so no read guard of an `RwLocked PNCounter` is typed;
  - the probe's `rw_new [PNCounter] ( PNCounter_share b )`, with `b` kept,
    is `locked_new`'s check, which panics (`lockNew_kept`).
- **h354** `locked_update_stores_a_kept_handle_into_the_value` (phase B's
  probe, which runs clean). The give-back's check: a scope's end whose `x`
  holds a share of a cell another slot holds panics, the lock held
  (`scopeL_end`, `Step.scopeLFail`).

### Simplifications in this cut

Each is a restriction, and sound as stated.
- *The receive's check* panics where the runtime's channels need none
  (above).
- *An `RwLocked` of a library handle* is made and written but not read.
  The runtime refuses it where it crosses.
- *A failed give-back drops the value* where the runtime keeps it in the
  held lock. Nothing reaches it either way.
- *`locked_take` takes only through a lock share*, not a cell share (A3.2's
  second cut).

### Not proven here

- *Phase D*, now for lock entries: that the runtime's reference count of a
  handle's block is the number of cell shares the model's slots and lock
  payloads hold, so its walk passes exactly when `SendCheck` holds.
- *§7.7's store rule*, and so phase D's agreement for a cycle through a
  lock's payload (A3.2's second cut). A cell share in a lock's payload can
  now close one too. The give-back's check refuses a cell's state holding
  a share of the cell itself, but not one through a lock.
- *Deadlock freedom*: a lock held after a failed give-back is held forever,
  as the runtime's is.
- The probes as whole typed programs (as `A2/DynCell.lean` types `pick`).
  `chanSend_kept`, `lockNew_kept`, `lockRestore_kept` and `scopeL_end`
  state their rules on one step each.

## A3.5b's and A3.5c's rest (subsumption, bounds, what A2's closures leave out)

**Status.** Mechanized. Subsumption between closure classes is typed (A2:
two typing rules, A3: the crossing facts). A generic bound and a supertrait's
bound are answered by the class. A closure that changes a capture it moved in,
and an `inout` receiver through a trait object, were out of A2's closure model
(a call through a package lends its code a copy of the environment); they are
now typed by the environment's hand-over, an A2 call of its own
(`StmtT.callcE`, the section "A2-envhand" below), in a first cut: an interface
whose only parameter is the receiver. h364's rule holds. The markers are the
classes' subsumption one way and the trusted base the other. `check.sh` is
green, and `A2.memory_safe`, `A2.soundness`, `A2.no_leak_end`,
`A2.no_leak_panic`, the `DynCell` theorems, `A3.claim` and `A3.claim_made` are
re-proven.

### Subsumption between closure classes

**The order.** `Cross.rank` puts the classes in a line by what an environment
may hold: `bare` 0, `sync` 1, `send` 2, `any` 3. `Cross.Le q q'` (`q ≤ q'`)
says that a closure of class `q` may be taken as one of class `q'`.

**Every order is sound** (`Cross.Fits.mono`). `Cross.Fits` has three
conjuncts, each guarded by one flag of the class: `views`, `cells` and
`shares`. A flag that is false at a class is false at every class below it
(`Cross.Le.views`, `.cells`, `.shares`). So an environment that fits a class
fits every class above it. A2's soundness reads the class only through
`Cross.Fits` and through where an environment may hold views (`ViewIn.pkg`, at
`any`) or shares (`ArcIn.pkg`, where `q.shares`). The class only restricts
where a value may go.

**Where it lives: a typing of `Rhs.var`.** Three places were open.
- *A subtyping step on values.* Taken, as two typing rules of the
  right-hand side `Rhs.var`, not as a new right-hand side (`Rhs.coerce`).
  - `RhsT.moveUp` moves an owned closure at a class above its own. Its
    premises are `moveOwn`'s, with `E.ty = fn ms q` and `q ≤ q'`, and its
    result is `⟨fn ms q', own, true, [], E.held, false, false⟩`.
  - `RhsT.copyUp` copies a borrowed closure at a class above its own:
    `copyBor`'s result, of type `fn ms q'`.
  - The step is `moveOwn`'s or `copy`'s: the value moves or is copied as it
    is. So no step, renaming, frame, sweep or touch lemma gets a case. Only
    the lemmas on `RhsT` do.
  - A new right-hand side would have needed all of those, for a step that
    does what `.var`'s already does.
- *A premise on argument passing* (`paramOK` taking an argument at a class
  below its parameter's). Not taken.
  - A call's renaming places the callee's parameter entry where the caller's
    argument is: the parameter's type is the argument's (`CallH.sig_abs`,
    `callPe`).
  - Two types for one binding would reach the renaming, `CallT`'s
    post-context and the callee's frame.
  - A move or a copy before the call does the same: `: h2 h`, then
    `( f h2 )`.
- *Interfaces at several classes.* Not a rule, for the same reason: a call's
  receiver is `CallT`'s first argument, so its class is the interface's.
  - With `copyUp`, a borrowed receiver reaches every interface declared at a
    class above its own (`StmtT.callcUp`).
  - So an interface is declared once, at the weakest class its callers have.
    A `sync` handler an `Arc` lends is called through an interface declared
    at `any` (`StmtT.arcCallUp`), and the interface need not say the
    handler is Sync.
  - An owned receiver is moved up first, so its class is then forgotten.
- *A call through the weaker type* checks the code against the interface it
  is called at. It is A2's `callc` at the weaker type, and `Implements`
  holds each method's code to its interface's other parameters and result,
  whatever the class of the interface's receiver.

**A2's proof.**
- What the invariant asks of a value at the new class it had at the old one:
  - `WFv.up` and `ValOK.up` (by `Cross.Fits.mono`);
  - `ViewsOK.up`: at `any`, a view in an environment whose closure was below
    `any` is none, since that environment's type holds no view
    (`ViewIn.holdsView`);
  - `SharesOK.up`: the shares are the environment's (`SharesOK.pkg'`,
    `SharesOK.mk_pkg`);
  - `RhsOut.up`, for what a right-hand side makes.
- `rhs_pres`: the move's case (`rhs_move`) or the copy's (`out_copyBor`),
  then `RhsOut.up`. `evalR_exists`: the move's or the copy's step.
- The context lemmas on `RhsT` (`RhsT.out`, `dkeep`, `dstay`, `domMode`,
  `domTy`, `wf`, `names`, `ctxRel`, `absOK`) take the move's or the copy's
  argument.
- The renaming (`RhsT.ren`) is the only one with more to it. Lifted into the
  caller, the moved-up entry holds at least what the moved entry holds,
  because `ownHeld` holds more at a type that holds views.

**The crossing facts** (`A3/Defs.lean`).
- *The class only forgets* (`RhsT.var_up`). A closure moved or copied keeps
  its interfaces, at its class or above it. So an `any` closure stays `any`
  (`RhsT.var_any`).
  - h342's handler captures by name, so it is `any` (`pack_names_any`).
  - However it is passed on, no `Arc`, spawn, lock or channel takes it.
- *A Sync handler where a Send one is declared.* A `sync` or `bare` closure
  moved as `send` is a spawn's argument (`moveUp_send`: its type holds no
  view, `SpawnOK`).
- *Any closure may be moved as `any`* (`moveUp_any`), where it crosses
  nothing.
- A3's statements read the type a value is taken at, and A3's invariants are
  over values (`Touch`, `CellInv`, the partition), so A3's proof is
  unchanged.

**Subsumption is at the top of a closure's type only.** A `Vec` of `sync`
closures is not a `Vec` of `any` ones: a node carries its element type
(`Val.node t`, `WFv.node`), and a `push` asks the element's type to be the
`Vec`'s. A closure taken out (`pop`, a field) is moved up on its own.

### A closure that changes a capture it moved in

An example is the accumulator `\ → i { = n + n 1 ^ n }`, with `n` moved in.

**The decision.**
- *The moved-in capture is the environment's own state.* The package owns
  it, and only a call through the package reaches it.
- *A `send` closure may own it.* The state moves with the closure, and only
  the thread that holds the closure calls it.
- *A `sync` one must not change it.* Threads calling it at once through an
  `Arc` would race on it: this is h342's shape, with the state inside the
  closure instead of captured by name.
- So the change needs an owner of the package. Its class stays about what
  the environment holds.
  - An environment that holds only a plain integer fits `sync`. Such a
    closure may be put in an `Arc`.
  - A call through the `Arc`'s borrow (`getE`, `Kind.share`) is not an
    owner's, so it cannot change the state.

**Typed: the environment handed over** (A2-envhand, the section below).
- A2's call that lends the code a copy of the environment (`callc`: `envMem`,
  `lendOf`) still changes nothing of it (`Implements.env_lent`).
- A method whose interface takes the receiver `inout` is called with the
  environment handed over (`StmtT.callcE`): it moves out of the package into a
  binding the code takes `inout`, and back into the package after, as
  `withElem` hands over an element.
- The decision above is its rule. The hand-over asks for an owner
  (`canDo Ec.mode .replace`, `c ∉ F`, as `CallT` asks of an `inout`
  argument); a borrow, an `Arc`'s or anyone's, is never one
  (`callcE_not_bor`, h364).
- *Refined*: the call also asks the receiver's class to be at least `send`
  (`callcE_send`). The owner rule alone keeps one thread to a hand-over (an
  `Arc` only lends), but the type is the promise the crossing rules read: a
  closure whose environment is handed over is Send and not Sync, so no `Arc`
  holds it at that type (`callcE_not_arc`). A closure whose environment fits
  `sync` (a plain integer) may still be packed `sync` and put in an `Arc`; its
  `inout` method is then called through no copy (`callcE_not_sync`), and its
  owner moves it up to `send` (`RhsT.moveUp`) to call it.
- The accumulator, typed: `accum_impl`, `accum_codes` and `accum_hand`, and
  whole, its code and a caller (`accP_ok`, `accMain_typed`, `accMain_safe`;
  `A3/Defs.lean`). Its environment is a struct of the count: A2 has no
  `inout` integer (an integer binding is copied, not owned), so the
  one-capture environment is the count beside a field the code keeps.

**What several threads may change at once** (`A3/Defs.lean`). This is h342's
fix: the state lives in a share the environment holds, which synchronises
itself.
- Take `\ → i { atomic_add n 1 }`, with `n` an `Atomic` moved in. The
  environment is a lock share, which `sync` admits (`accum_sync`: a lock
  share is Sync, A3.5's second cut).
- The code changes the state by one atomic step on the lent share
  (`accum_count`: `RhsT.atomic` takes any live `lk int`, a borrowed
  parameter's too).
- With a `Locked` share as the environment, the code changes the state by
  `withLock`, since a borrowed parameter is a root.
- In both cases several threads may call the closure.

### Trait objects: subsumption, bounds, receivers

**Subsumption** is A3.5b's.
- An object packed at a class below its trait's bound is taken up to the
  bound by a move or a copy (`dyn_up_bound`). An example is an impl of a
  `: Send` trait whose box holds no handle, packed `sync`.
- The object is then a receiver of the trait's methods, and the pack kept the
  bound's promise (`ImplOK.of_le`).
- `callc_not_at` is still true of the call itself. An object is inert only
  above its bound, since no rule lowers a class.

**Generic bounds and supertraits: monomorphised.** A2 has no generics, no
type variable and no instantiation.
- A generic function `f [T: Send]` is a family of functions of the program,
  one for each type it is called at.
- Each instance is at concrete types. A closure's or a trait object's class
  is the one `Rhs.pack` gave it (`RhsT.pack_fits`) and subsumption kept
  (`RhsT.var_up`). Any other type's Send and Sync are read off the type
  (`holdsView`, `hasCell`).
- So a bound is a fact about the instance's type, the one the crossing
  rules ask of it (`TraitBound.Holds`):
  - no bound asks nothing;
  - `[T: Send]` asks no view (`Holds.send`: what A3.0's spawn, a lock and a
    channel ask, so no closure that holds names either);
  - `[T: Send Sync]` also asks no library handle (`Holds.arc`: what
    `RhsT.arcNew` asks).
- *A bound is answered by the class* (`TraitBound.holds_fn`). A closure or a
  trait object meets a bound exactly when its class is at most the bound's:
  - `[T: Send]` holds of `fn ms q` iff `q ≤ send`;
  - `[T: Send Sync]` holds iff `q ≤ sync`.
- *A supertrait's bound is kept* (`Holds.mono`). What meets a bound meets
  every weaker one.
  - So a trait declared `: A`, with `A : Send`, is held to Send. Its bound
    is the strongest of its own and its supertraits'.
  - Its objects meet `A`'s bound.
  - An upcast of an object from a trait to its supertrait is not typed: it
    changes the interfaces `ms`, which a package's type fixes.
- **Phase C obligation (stated, not proven):** the lowering instantiates
  each generic function at the types it is called with. nurlc's bound check
  at an instance is `TraitBound.Holds` of the instance's type.

**An `inout` receiver** (h364–h366: a method that changes the box).
- *`Implements` holds impls to it.* The code's first parameter takes the box
  in the interface's receiver mode (`Fn.recvMode`): lent, or `inout` at the
  interface's bound. What the receiver holds afterwards is the interface's
  `outHolds` for it (`fn.outHolds ⊆ sig.outHolds`, the code's `FnOK` holding
  its parameter to its own).
- *A trait declares it* (`TraitAt`: a method's receiver is the object at the
  bound, taken `inp` or `inout`).
- *A2 calls it with the box handed over* (`StmtT.callcE`). `callc` still takes
  its receiver `inp` only (`StmtT.callc_inp`, `callc_not_inout`).
- *A borrow never hands it over.* What an `Arc` or a read guard lends is a
  borrow (`getE_bor`), and so is each copy of it: no `inout` argument of any
  function (`paramOK_inout_not_bor`), no hand-over's receiver
  (`callcE_not_bor`).
- *A `: Send Sync` trait's `inout` methods are called through no object*
  (`callcE_bound`, `callcE_not_sendSync`): its objects are `sync`, which
  several threads read at once.
- *h364* `dyn_inout_method_through_a_read_guard`. `( rename k )`, on `k` (a
  `: ~` copy of `rguard_get`), is refused: `k` is a borrow, not an owner
  (`callcE_not_bor`; `rename`'s trait is `: Send Sync`, so
  `callcE_not_sendSync` refuses it too). That is h364's rule: the box every
  reader sees is frozen.
- *h365* `dyn_inout_method_replaces_what_a_view_reads` (A2). `( rename k )` on
  the owned object `k` is typed by `StmtT.callcE`, and its `kill .replace`
  ends everything that depended on `k` (`hand_ends`): the `String` `n` read
  out of the box by `( name k )` is dead, so `( string_data n )` after it is
  refused. That is h365's rule.
- *h366* `helper_hands_its_parameter_to_a_dyn_method` (A2). The helper's
  parameter `o` is `inout` of bound `replace`, an owner for the hand-over
  (`canDo_inout_replace`): `( rename o )` is `StmtT.callcE` in the helper's
  body, and the helper's summary says it replaces `o`. Its caller's
  `( relabel k )` is an ordinary call with `k` an `inout .replace` argument,
  whose `callPost` ends `n` as h365's does. That is h366's rule: a function
  that hands its parameter to a `dyn` method does to it what the method
  does.

### The markers (`% Send`, `% Sync`, `% NotSend`, `% NotSync`)

- *A positive marker* outside the standard library is `unsafe` (§3), so it
  is trusted base: a hypothesis of the theorem, as an `unsafe` body is.
  - The model has no rule that raises a class. `pack` gives only the classes
    the captures fit (`RhsT.pack_fits`), and a move or a copy only forgets
    (`RhsT.var_up`).
  - A false positive marker would let a value cross where its type says it
    may not. The claim does not cover it.
- *A negative marker only removes typings.*
  - On a closure or a trait object's type, it can only lower the class:
    - `% NotSend` takes the closure at `any` (`moveUp_any`);
    - `% NotSync` takes a `sync` or `bare` closure at `send` (`moveUp_send`).
    Each is a class subsumption reaches, and sound by `Cross.Fits.mono`.
  - On any other type it is a refusal nurlc adds and the model needs not. The
    model computes Send and Sync from the type (`holdsView`, `hasCell`), and
    the theorem covers every program the model types. These include those
    nurlc accepts with the marker.
  - `% Frozen` is A3.3's read guard.

### Not proven here

- *Phase C*: the lowering gives each closure type the class nurlc's walk
  proved (A3.5b), and instantiates each generic function at its call types,
  its bound checked there (above).
- The hand-over's second cut: an interface with parameters beside the
  receiver, or whose result borrows or holds views of the receiver; a package
  that captures by name with a method that changes its environment (section
  "A2-envhand" below).
- Subsumption inside a container's element type, or at argument passing.
  A move or a copy up before the call is typed instead (above).
- An upcast from a trait's objects to a supertrait's.
- The probes as whole typed programs (as `A2/DynCell.lean` types `pick`).
  `StmtT.callcUp` and `StmtT.arcCallUp` type the call, not a program.

## A3.2's and A3.3's rest (the lock operations)

**Status.** Mechanized. `check.sh` is green. Each operation below is a
*derived form*: a statement of A2's rules (`A2/Syntax.lean`), typed as one
statement, every scope's end included, by a lemma of its own
(`A3/Defs.lean`). No rule is new, so `A2.memory_safe`, `A2.soundness`,
`A2.no_leak_end`, `A2.no_leak_panic`, the `DynCell` theorems, `A3.claim` and
`A3.claim_made` cover the forms with no new case, and `check.sh` re-proves
them. This types every lock and `RwLocked` operation on A3.2's and A3.3's
"not typed" lists. What those lists keep is deadlock freedom, which the
claim excludes by design, and shares in a slice's elements, which is no
lock operation (*Not proven here*, below; typed since shares in a slice,
below).

For each form, *faithful* says whether the model has exactly the runtime's
runs, or more. A form that only adds runs is fine: the claim covers every
run of the model.

### What the lemmas share

- A binding a form makes is fresh: no entry of the context depends on it
  (`Unnamed`). Its scope's end then ends nothing else (`Unnamed.kill`,
  `Unnamed.endOK`, `exitScope_setE`, `exitScope_out`).
- A result handed back once the lock is let go depends on nothing (`outE`).
  It is a call's result moved to a caller's binding `z` (`Stmt.callOut`,
  typed by `StmtT.callOut`; an owner moves, an integer is copied). So `z`
  outlives every scope around the call.
- Each lemma states the context after, computed. For a result, it is the
  context before with `z` holding the result, and what borrowed `z` ended
  by the assignment: `setE (kill .replace false z Γ) z (outE R _)`. For
  `locked_set` it is the value's hand-over (`PushArg`). For `locked_await`
  it is the context before.

### The forms

**`locked_get`** (`Stmt.lockedGet a x c z f`, `StmtT.lockedGet`).
- The form is `withLock a x (callOut x c z f)`, with `f` of `mem_dup`'s
  summary (`DupFn`: the payload lent in, an owned copy out). The payload is
  checked out for the copy, as the runtime holds the mutex for it.
- The lemma takes `t.hasCell = false`, as `rw_get`'s read guard does
  (`RhsT.rwRead`). The runtime's `locked_get` panics on a library handle:
  its copy is another owner of the state the lock's value holds, which
  `mem_send_check` counts. (Before A3.5's third cut, below, a function
  that takes the payload lent could not copy the handle either; now it
  can, and the copy is another owner.)
- *Faithful, no runs added.* The check-out waits while the lock is held, as
  the runtime waits on its mutex and `taken`. A3.2's premises make the
  check-out agree with the runtime's in-place copy. With no library handle
  in the value, the runtime's check of the copy and the model's give-back
  check (`GiveCheck`) have nothing to find.

**`locked_set`** (`Stmt.lockedSet t a b x y`, `StmtT.lockedSet`,
`lockedSet_check`).
- The form is `letv b (lockNew t y) (withLock a x (assign x (lockTake b)))`.
  The new value goes into a fresh lock block `b`, a box no other binding
  reaches. Then `a`'s payload is checked out to `x` and replaced by the box's
  value: `assign` drops the old one, as `= . p val x` does. The scope's end
  gives the new value back, and the empty box is swept.
- `StmtT.lockedSet`: the context after is `y`'s hand-over, as for
  `locked_new` of the same value (an owner moves and its entry dies, an
  integer is copied).
- **The check comes first** (`lockedSet_check`). A value that fails the
  crossing check makes `locked_new`'s step panic, the store as it was
  (`EvalR.lockNewFail`), before the lock is touched. The runtime's
  `mem_send_check` likewise runs before `mutex_lock`, and its lock keeps the
  old value.
- *Why not a take and a restore, or a check at the give-back.* A take
  empties the lock before the restore's check. A body `assign x (var y)`
  checks only at the give-back, after the old value is dropped. Either way a
  failed check leaves the lock empty and held, and other threads wait
  forever. The runtime's lock keeps its old value, and other threads go on.
  Those runs of the runtime would be missing from the model.
- *Faithful, no runs added.* The box's steps are the runtime's check. In
  both, another thread may step between the check and the lock. The
  give-back's own check passes in every reachable configuration. The value
  passed `locked_new`'s check, and since then the thread's slots took only
  the box's share and the lock's old value, whose cells are in no other
  place (`CellInv.one`). This is argued, as A3.2 argues that a lock scope
  ends in a `put`, not proven as a lemma.
- `rw_set` is the same form. The runtime's `rw_set` checks nothing, and
  the model's `RwLocked` checks every value going in (A3.5's second cut).
  The check finds nothing on a payload that holds no library handle, which
  is every payload a read guard may read (`RhsT.rwRead`).

**`locked_apply`'s, `rw_apply`'s and `wguard_apply`'s result**
(`Stmt.lockedApply a x c z f`, `StmtT.lockedApply`, `StmtT.wguardApply`,
`apply_call`).
- `locked_apply` and `rw_apply` are `withLock a x (callOut x c z f)`, an
  `RwLocked`'s write scope being a `withLock`. `wguard_apply` is the tail
  alone, `callOut x c z f`, inside a write scope already open
  (`StmtT.wguardApply`).
- `f` has `ApplyFn`'s summary: it takes the payload `inout`, and lends
  (`lends = []`) and holds (`rholds = []`) nothing of it. `apply_call`: the
  call on the checked-out `x` leaves the context as it was, and its result
  depends on nothing.
- **The result holds no lend of the payload.** The payload is the closure's
  only parameter, and the summary says the result borrows from no parameter
  and holds no view of one. So its type holds no view of the payload, and
  the lock scope's end (the guard's drop) leaves it. A result that borrowed
  the payload would be ended by that end (`exitScope x`), and could not be
  handed back.
- The payload is of an owning type, as an `inout` argument's is
  (`paramOK`). The apply of an integer payload is a body in place:
  `withLock a x s`, with `s` assigning `z` from what holds nothing, which
  `withLock` types and whose end leaves `z` (`copy_outlives`).
- *Faithful, no runs added.* The runtime runs `f` in place with the mutex
  held, checks the value, unlocks, and returns the result. In the model the
  check-out and the give-back are A3.2's (its premises make them agree with
  the in-place run), and the give-back's check is the runtime's. The result
  reaches `z` before the lock is let go, where the runtime returns it after.
  But `z` is the caller's, which no other thread reaches.
- A3.5: a library's change of its state with a result, through a cell share
  an owner holds, is the same form (`Entry.lockOf`).

**`locked_await`** (`Stmt.lockedAwait a x c q f`, `StmtT.lockedAwait`,
`await_done`, `await_blocked`).
- The form is `while (isl q) (lockedApply a x c q f)`: rounds of check-outs.
  Each round is `locked_apply`'s, with `f`'s answer, an `Option`, moved into
  the caller's `q` (an owned `none` to start, `awaitE`).
- `StmtT.lockedAwait`: a round leaves the context as it found it, which is
  the loop's invariant.
- `await_done`: the loop ends only on a `some`, so the caller's `taker q`
  moves the result out without a panic.
- **Its waiting is `Blocked`, not stuck** (`await_blocked`). A round waits at
  its check-out while another thread holds the lock. That configuration is
  `Blocked`, which `Stuck` excludes.
- *Faithful, only adds runs.* Each round is the runtime's run of `f` with
  the mutex held, and its give-back check is `mem_send_check`. Each round
  lets the lock go, as `cond_wait` lets the mutex go between runs.
  - Between rounds the runtime sleeps until another thread changes the value
    (`waiters`, `cond_broadcast`). The model's next round waits only at its
    check-out, so the model adds runs: a round with nothing changed since
    the last.
  - The runtime has such runs too, since `cond_wait` may wake spuriously
    (`stdlib/std/thread.nu`: callers loop on the predicate).
  - Every run of the runtime is a run of the model: its sleep is a schedule
    that runs the other threads first.
  - That a waiting thread is ever let in, and that the loop ends, are
    deadlock freedom and fairness, which are not claimed.

**`rw_get` as one statement** (`Stmt.rwGet`, `StmtT.rwGet`).
- The guard `g` (`rw_read`), what `arcGet` lends through it (`y`), the
  payload `x` lent frozen, the copy, and the copy moved out to `z`, are
  typed with every scope's end. The context after is the one before, `z`
  holding the copy.
- **`mem_dup` needs no step of its own.** The copy is a call of a function
  with `mem_dup`'s summary (`DupFn`), which `ProgOK` checks against that
  summary. For a payload that holds no closure, such a function is written
  in the calculus: elements read with `at` and pushed, a struct taken field
  by field, recursively. A step would be a deep copy with fresh addresses: a
  case in every lemma over right-hand sides, for no fact the summary does
  not give (the copy is owned and depends on nothing). That nurlc's
  intrinsic (`gen_mem_dup`) meets the summary is phase D's, as for every
  call typed by its summary.

**`Mutex`** (`Rhs.mutexNew`, `Stmt.mutexLock`, `Stmt.mutexUnlock`,
`Stmt.mutexWith`; `RhsT.mutexNew`, `StmtT.mutexLock`, `StmtT.mutexUnlock`,
`StmtT.mutexWith`).
- A `Mutex` is a lock of an integer, `lk int` (A3.6: `Mutex` is a
  `Locked`).
  - `mutex_new` is `locked_new` of an integer.
  - `mutex_lock m` takes the integer out (`lockTake`), and every other
    `mutex_lock` waits until it is back.
  - `mutex_unlock m` puts an integer back (`lockRestore`).
  - `mutex_with` is `withLock`, with A3.2's premises (the mutex outlives the
    body, which the runtime unlocks after).
  - `Mutex_share` is `lockClone`, and its drop a share's.
- **Memory safety never depends on a `Mutex`.** The thread that takes one
  gets an integer binding, which depends on nothing and holds nothing
  (`mutex_hands_int`). The mutex's block owns no address
  (`mutex_owns_nothing`). So no memory fact of a program comes from a
  `Mutex`, and no lemma of the claim reads one.
- **A lock beside the data is not a lock on it** (docs/MEMORY.md §6.5,
  h319 `member_table_copy_on_two_threads`). A race on the data a `Mutex` is
  meant to guard is refused by the data's own type, whatever mutex calls
  surround it:
  - an owned tree is in one thread's part: a spawn moves it (A3.0's
    `SpawnOK`, `MoveArgs`), and data two threads change is a `Locked`, whose
    lock its type names;
  - an `Arc`'s payload is frozen (A3.1, `ThruOK.noShare`);
  - a library handle crosses a spawn only with every owner of its state.
    That is h319's rule: the crossing check `SendCheck`, whose failure
    panics (`TStep.spawnFail`). So a handle's shares are in one thread's
    slots or one lock's payload (`CellInv.home`, `CellInv.apart`), and no two
    threads change its state (`CellInv.cellRaceFree`).
- *Faithful, only adds runs.* `pthread_mutex_lock` waits while another
  thread holds the mutex, as the take waits while the integer is out.
  - A `mutex_unlock` of a mutex the thread does not hold panics in the
    runtime (an error-checking mutex, Agora #455; undefined before), and so
    does a relock by the holder. The model's unlock panics (the integer in,
    `lockRestoreP`) or puts an integer back, which may let another thread
    in. Neither touches memory, since the mutex guards none.
  - The runtime's `mutex_with` does not unlock on a panic. The model's
    releases (A3.3's `scopeLP`): more runs, as for `locked_with` (A3.2).
  - `Cond` and `Semaphore` have no rule, as in A3.6.

**A lock reached through a local borrow** (`Stmt.withLockElem`,
`StmtT.withLockElem`; `Stmt.withLockField`, `StmtT.withLockField`;
`LockFn`, `lock_call`, `lockFn_param_root`). `withLock` asks a root the body
does not name (A3.2). A field or an element of a local owner is a borrow,
whose owner the body could change. So the lock is handed over first, and
the body runs on an owner of the share that nothing in it reaches.
- *An element*: `withElem v i e (withLock e x s)`. A2-elem's hand-over moves
  the element out to `e`, an owner (`popE`), and back at index `i` after.
  The body names neither `e` nor `v` (`withElem`'s premise), so the lock
  outlives the body.
- *A field*: `unpair y l w (seq (withLock l x s) (assign y (pair l w)))`.
  The struct is taken apart, as A2 replaces a field in place. The lock `l`
  is an owner (`compE`: a lock share views nothing). The body names neither
  `l` nor `y`, and the struct is put back together.
- *A borrow of what the function does not own* (a borrowed parameter's
  field, an element of a lent `Vec`): `withElem` and `unpair` ask an owner,
  so it cannot be handed over. It is handed to a function that takes it
  `in`, as the runtime's `locked_update l f` takes `l` (`LockFn`,
  `lock_call`). Inside, the parameter is a borrowed one
  (`lockFn_param_root`): a root whose share is the caller's, frozen for the
  call (`callIn`'s `frozen`), which `withLock` takes.
- *Faithful, no runs added.* The runtime locks the field or element in
  place. The model moves it out and back, which agrees because the body
  reaches neither the owner nor the share.

### Not proven here

- Deadlock freedom: that a waiting check-out, take or round is ever let in,
  and that `locked_await`'s loop ends.
- That `locked_set`'s give-back never fails its check in a reachable
  configuration, as a lemma (argued above).
- The closure that `locked_with`, `locked_update`, `locked_apply` and
  `locked_await` run, called through a package (`callc`, whose `inout`
  receiver is other work). Here it is a statement in place or a function of
  the program.
- Shares in a slice's elements (A3.1's first cut: `Ty.ok (slice t)`,
  `RhsT.view`), which `CLAIM.md` lists with A3.2. It is no lock operation,
  and is not lifted here. (Lifted by shares in a slice, below.)
- Programs typed over these forms, as `A2/DynCell.lean` types `pick` (the
  probes' encodings).

## A2-envhand: the environment handed over (`callcE`)

**Status.** Mechanized in A2 (`A2/EnvHand.lean`, the rule `StmtT.callcE`) and
A3 (`A3/Defs.lean`: the classes, the probes' rules, the accumulator), in a
first cut: a method whose interface takes only the receiver, `inout`, and
whose result borrows and holds nothing of it. `check.sh` is green;
`A2.memory_safe`, `A2.soundness`, `A2.no_leak_end`, `A2.no_leak_panic`, the
`DynCell` theorems, `A3.claim` and `A3.claim_made` are re-proven with the new
statement and rule. Probes: h365 and h366 (A2), h364 (A3).

### Why

A call through a package (`callc`) lends its code a copy of the environment
(`envMem`): a change would land in the copy. An accumulator that changes the
count it moved in, and a trait object's method with an `inout` receiver,
change the environment itself. The runtime passes the code a pointer to the
environment, in the closure's heap block (`NurlCenvVt`'s env,
`stdlib/runtime_core.c`).

### The statement and its step

- `Stmt.callcE x c j zs k`: `: x ( m c zs… )`, through the package `c`, of
  method `j`. (The syntax and the step take `zs`; the first cut types
  `zs = []`.)
- `Step.callcE` (`c` owns `pkg fs te ms env []`, `fs[j] = f`): the store
  becomes `handMem` — `c`'s slot owns nothing, the environment is owned by the
  first fresh variable `y`, the result binding `x` is bound unset — and the
  statement `handStmt`:

      scope x ( seq ( scope y ( seq ( letcall r f [y] ( = x r ) )
                                    ( = c ( pack fs te ms y [] ) ) ) )
                    k )

  with `r = y + 1`: an ordinary call of the code with `y` its `inout`
  receiver, its result moved to `x`, then the environment back into `c` as a
  package of the same code and interfaces. Every form it leaves is one A2
  already types and runs; only the hand-over step itself is new.
- *The design said "a new run-time form"; refined:* none is needed. Moving
  the environment back is `= c ( pack … )`, an assignment of a pack, which A2
  types (`c` is moved out, so its old value drops nothing); the place it goes
  back to is `c`'s slot, as `withElem`'s give-back is its index.

**A panic drops the environment, as `withElem` drops an element.** The
unwinding drops `y`'s value with `y`'s scope; `c`'s slot owns nothing, so its
scope drops nothing. That is the runtime's release, at another slot:
docs/MEMORY.md §7.2 — a panic jumps to the nearest `recover` frame, and the
allocation journal drops each closure binding's environment through its owner
slot (h375, h376). The frame that binds `c` is unwound before the `recover`
frame catches the panic: `recover f` calls a function of no parameters, so a
`c` the code was handed lies in a frame the panic leaves (an `inout`
parameter's argument is in a caller's frame inside the `recover` too). So the
environment is released once either way, and `c` is never read after; the
model need not put it back.

### The rule (`StmtT.callcE`)

    k.src   Γ x = none   x ∉ F   Γ c = Ec   Ec.ty = fn ms q
    canDo Ec.mode replace   send ≤ q   ms[j] = σ   σ.params = [(inout b, fn ms q)]
    σ.lends = σ.rholds = σ.outHolds = []   NoPin Γ c   DtorSafe Γ replace c
    CallT P (kill replace c Γ) F σ [c] E Γ1
    StmtT P (kill replace c (setE Γ1 x E)) F k Δ   EndOK Δ x   ¬ ThruFn P σ
    ───────────────────────────────────────────────────────────────────────
    StmtT P Γ F (callcE x c j [] k) (exitScope x Δ)

- The call is the interface's, with `c` its `inout` argument, after what
  depends on `c` has ended and with it ended again after: the environment
  moves out of `c` and back (`kill .replace`, as `withElem` takes an
  element). So a view of the box (h365's `n`) does not survive the call.
- The faithfulness premises (the runtime changes the environment in place):
  `c` is an owner that may be replaced — an owner, or an `inout` parameter of
  bound `replace` (h366's helper) — never a borrow; not lent out; changed by
  name by no borrowed parameter; viewed by no destructor.
- The receiver's class is at least `send`: the package is Send, not Sync.

**`Implements` with an `inout` receiver.** `Fn.recvMode σ` is the mode the
interface takes its receiver in. The code's first parameter is the
environment in that mode: `inout` at the interface's bound, so `FnOK` holds
the code to that effect on its environment, and what the environment holds
afterwards to the code's `outHolds`, which are among the interface's
(`fn.outHolds ⊆ sig.outHolds`). A package with such a method captures
nothing by name (`cs = []`).

### The proof

- *The store* (`hand_minv`): the package's tree moved from `c` to `y`, as a
  field of a struct taken apart (`rhs_move'`, `out_part`), and `x` bound unset
  (`MInv.addUnset`).
- *The code's call* (`callT_hand`): typed from the interface's; `y` is fresh
  and holds what `c` held, so it is reached by no other binding, what its
  closures may change the interface's call may change, and no destructor
  views it.
- *The run-time form* (`hand_typed`): typed by A2's own rules, and the context
  it leaves is `Weaker` than the one the source's continuation is typed in.
  `HandRel` compares the two binding by binding outside `x`, `y`, `r`, `c`
  (each step: a kill of a fresh binding, one both make, the closures' kills
  by name, sets of the excluded bindings); `FrameOK` keeps the borrowed
  parameters and destructor bindings the store's; `recv_keep`: the call's
  changes by name do not end `y`.
- *Preservation* (`handCase`, a case of `preserve` as `CloCase` is),
  *progress* (`handProgress`: the package's code takes the environment
  `inout`, and it captures nothing by name), and the inductions over typing
  (well-formedness, names, frozen and `letd` bindings, the callee renaming —
  `callcE`'s kill is `Allowed` where a call places it — and source typing's
  context relation).
- A3: the step touches no address (the tree moves between the thread's
  slots); its frame, ownership, cell, lift and restrict cases are the moves'.

### Classes (A3)

- `callcE_send`: a package whose environment is handed over is at most Send
  (its class is `send` or `any`), or (Agora #609, the consuming hand-over)
  of the dropping class, which crosses nowhere; `callcE_not_sync`: a `sync` or `bare` one
  has no such call; `callcE_not_arc`: no `Arc` holds it at that type. Two
  threads never call it at once: h342's shape, with the state inside the
  closure, is refused by the type.
- `callcE_not_bor`: a borrow — an `Arc`'s, a read guard's, a copy of either —
  is no hand-over's receiver (h364).
- `callcE_bound`, `callcE_not_sendSync`: through a trait object, a hand-over
  types only at the trait's bound, so a `: Send Sync` trait's `inout` methods
  are called through no object.

### The rules for the probes

- *h365* (`dyn_inout_method_replaces_what_a_view_reads`, A2): the hand-over's
  `kill .replace` on the object (`StmtT.callcE`, `hand_ends`) ends the view
  read out of its box before the call.
- *h366* (`helper_hands_its_parameter_to_a_dyn_method`, A2): the helper's
  `inout .replace` parameter is an owner for the hand-over
  (`canDo_inout_replace`); its caller's argument is an `inout` one, whose
  `callPost` ends the view.
- *h364* (`dyn_inout_method_through_a_read_guard`, A3): `callcE_not_bor`.

### The accumulator

The accumulator, `n` moved in, `= n + n 1 ^ n` (`A3/Defs.lean`): its
interface `accSig` takes the closure `inout` at `send`; its code `accCode`
takes the environment, a struct of the count (`accEnv`, a pair: A2 has no
`inout` integer), `inout`, adds one, and returns it (`accum_impl`,
`accum_codes`); its environment fits every class (`accum_fits`); its owner's
call is `StmtT.callcE` (`accum_hand`, through `StmtT.callcE_recv`); a `sync`
one has no such call (`accum_not_sync`).

The program is typed whole, as `A2/DynCell.lean` types `pick`'s:
- its code and its interface meet their summaries (`accCode_ok`,
  `accSig_ok`, so `accP_ok : ProgOK accP`; `accP_codes`). The code's
  contexts hold only plain bindings (`PlainCtx`: none borrowed, none a
  destructor's, none depending on anything), so no change ends anything
  and every `EndOK` holds;
- its caller `accMain` (`: i n 0  : i p 0  : e { n p }`, the closure moving
  `e` in at `send`, `: i r ( acc )`) is typed from nothing
  (`accMain_typed`), so `A2.memory_safe`, `A2.no_leak_end` and
  `A2.no_leak_panic` hold of it (`accMain_safe`, `accMain_no_leak`,
  `accMain_no_leak_panic`).

### Still not typed

- An interface with parameters beside the receiver, or whose result borrows
  from or holds views of the receiver (the second cut: the tail of the
  call's post-context, as `post_rel` does for `callc`).
- A package that captures by name and has a method that changes its
  environment (`Implements` asks `cs = []`).
- A hand-over through a borrowed parameter (an `in` closure parameter): it is
  no owner.
- The probes h365 and h366 as whole programs: their rules are named above,
  and the accumulator is the one program typed whole.

## A3.5's third cut, `% NotSend` guards, shares in a slice (three typing gaps)

**Status.** Mechanized. `check.sh` is green, and `A2.memory_safe`,
`A2.soundness`, `A2.no_leak_end`, `A2.no_leak_panic`, the `DynCell`
theorems, `A3.claim` and `A3.claim_made` are re-proven. The cut closes three
gaps the earlier sections list as not typed:
- (A) a library handle used through a borrow (A3.5: "A library handle
  changed through a borrow (`in` parameters)");
- (B) read guards are `% NotSend` (A3.3: "`% NotSend` on guards is not
  modeled: a model guard may cross a spawn");
- (C) shares in a slice's elements (A3.1's first cut, which A3.2's and
  A3.3's rest leaves out).

A3.5's race (`CellOp`) asks, inside a
check-out, an owner's share rather than any share (below).

### (A) A library handle used through a borrow

The runtime's `pncounter_inc PNCounter c__h …` takes the counter `in`, and
changes the shared state through it; `PNCounter_share` copies a handle it
was lent. A3.5's first cut modeled a lent handle as no share
(`lendOf (.cell k) = .int 0`), so a library's `in` handle parameter was
taken `inout`.

**The fork: what a lent cell share is.**
- *Keep `lendOf` and give only a borrowed parameter the share.* Ruled out by
  the closures. A package's code is a function of the program whose first
  parameter is its environment, taken `in` (`Implements`), so a function's
  body cannot tell an `in` parameter from an environment. A call through a
  package lends the environment with `lendOf` (`envMem`). So whatever lets a
  `withCell` through an `in` parameter step must hold of a lent environment
  too, or a typed code is stuck. Changing `envMem` is a change of
  `callc`'s step, which other work is changing (the environment's
  hand-over), so it is not done here.
- *A lent cell share is the share.* `lendOf (.cell k) = .cell k`, as a lent
  lock share is the lock share. Chosen: it is the runtime's pointer copy,
  one function on values changes, and every lend agrees (a parameter, an
  environment, a field, an element).

**The rules.**
- `lendOf` keeps a cell share (`A2/Semantics.lean`). `ValOK.cell` asks of a
  lent one what `ValOK.lk` asks of a lent lock share: its block is a lock
  block of its type, which the sweep keeps while a slot holds the share.
- `Entry.lockOf t` is `E.ty = .lk t ∨ E.ty = .cell t`: a cell share any
  binding holds. `StmtT.withLock` still asks a root (`Ea.mode.isRoot`), so a
  `withCell` goes through an owner, an `inout` parameter or a borrowed
  parameter (`rootb`), never a local borrow. `StmtT.withCellIn` types the
  in-place change on an `in` handle parameter (`paramE_cell_lockOf`).
- `RhsT.cellClone` asks a live binding of type `cell t`, owner or borrow
  (`cellClone_in`): the copy is a new owner.
- A store of a borrowed handle into an owner, which the runtime makes a
  copy, is still not typed: `PushArg` moves owners only. The copy is an
  explicit `cellClone`.

**A2's proof.** A lent cell share is valid as a lent lock share is (its
block is a lock block of its type), and it also *lands*, as a lent `Vec`
does (`HrefAt`):
- `ValOK.cell` asks `∃ dep ∈ P, CellLanded m dep k`: the share is where the
  node its dependency's root reaches puts it (`RootNode`, `Lands`), never in
  a payload. No payload its holders read holds one (`MInv.noCellPay`): a
  lock block's is read by no one, an `arc` block and a view are of a type
  that holds none. That is `MInv.blocks`' new fourth conjunct,
  `bl.kind = .lock ∨ bl.ty.hasCell = false`, which `RhsT.arcNew` and
  `RhsT.rwRead` give (the Sync question they ask), and `BlockOK` carries to
  the other threads.
- `RootNode` gains a fifth case, a cell share at the top of a borrowed slot's
  value (A3.1's fourth is an `arc` share there): a copy of a library's `in`
  handle, or a field read out of a borrowed struct, lands on it.
- `HKeep` gains a third component, so every A2 step that keeps a borrow's
  dependency keeps its cell landing: `RootKeep.hkeep`, a root that grows or
  shrinks in place (`Evolve.grow_hkeep`, `self_hkeep`, `perm_hkeep`), a rewrite
  through a borrow (`deep_self_hkeep`, `Repl.top_cell`), a borrowed
  parameter's end (`reroot_cellLanded`), the sweep, the frame and the lifts.
  The lends give it (`lend_valOK'`, `out_at`, `out_sat`, the copy of a
  borrowed root, `valOK_via`, a call's `in` argument, a package's lent
  environment).
- **The lemma** (`MInv.cell_owned`): a live binding whose slot holds a cell
  share has an owner of that cell in the store. Back along its dependencies
  (`valOK_cell_sub`, `MInv.cell_step`): to an owned tree, or to a node found
  in one, or to a borrowed parameter holding the share at its top, whose own
  dependencies are earlier bindings (`rootbLt`), by induction
  (`MInv.rootb_cell`). This is "a borrow depends on its owner, and a move or
  a drop of the owner kills it", as a statement about memory.
- `MInv.cell_val` and `MInv.cell_slot` give the share and its block through
  any live binding, and `out_cellClone` and `MInv.lockOf_val` read them.

**Two run-time premises**, which no typed program fails, keep what a step
gives an owner an owner's (so confinement needs no typing of the step):
- `TakeVal.bor`: a borrowed value handed on holds no cell share. A typed
  program hands on a borrowed integer or slice only (`PushArg`,
  `PushArg.bor_noCell`); a copy of a borrowed handle is a `cellClone`.
- `EvalR.cellClone`: the copy is made where an owner of the cell is
  (`OwnedCell`). For a live borrow, `MInv.cell_owned` gives it, so a typed
  `cellClone` always steps (`evalR_exists`).

**The crossing check counts owners**, as the runtime's does. `SendCheck`'s
cell half asks that no *owned* slot left behind hold a share of a crossing
cell.
- An owner left behind fails it (`sendCheck_owner_left`), as the runtime's
  count does: a library function that clones its `in` handle and sends the
  copy leaves the caller's owner behind (the caller's argument, frozen for
  the call).
- A live borrow left behind has its owner left behind with it
  (`MInv.cell_owned`, on the same thread), so it adds nothing to count.
- A dead borrow left behind is not counted: `: PNCounter c …  : f c  …
  spawn (sink c)`, where the move kills `f` but its slot is still bound,
  passes the check (`sendCheck_dead_borrow_ok`), as it passes the runtime's.
- *Why not every slot.* Counting borrows too keeps confinement over the
  slots alone, with no typing, but then a dead borrow still bound makes the
  model panic where the runtime goes on, a common pattern the first cut
  covered. Counting owners needs the landing above, which ties every live
  borrow to an owner of its thread; with it, the dead ones are simply not
  counted.
- **Phase D's statement**: the runtime's reference count of a handle's
  block is the number of cell shares the model's owned slots and lock
  payloads hold. Given it, the runtime's walk passes exactly when the
  model's check does.

**Confinement** (A3's `CellInv`) is over owners: owned slots
(`CellAt`, `Thread.cellAt`) and lock payloads.
- *A step keeps it with no typing* (`Step.cellKeep`). A value set in a
  slot is counted only if it is an owner's (`CellKeep.setVal` reads the
  right-hand side's own flag: a lend is a borrow); what an owner gains was
  an owner's (`TakeVal.cell`, by `TakeVal.bor`'s premise) or a copy where an
  owner is (`EvalR.cellClone`'s); a call's `in` parameter and a package's
  lent environment are borrows (`BindParams.cellSt`, `CellAt.envMem`).
- *A spawn keeps it* by the check: a cell the moved values hold a share of
  keeps no owner in the spawner (`CellInv.spawn_of`).
- *Owners and live borrows* (`CellInv.live_home`): two threads that each
  hold a share of one cell, in an owned slot or in a borrowed slot live in
  their typing context, are one thread (`cellAt_of_live`, from
  `MInv.cell_owned`). Dead borrowed slots are ignored: no rule reads a dead
  entry.
- *No cell race* (`CellInv.cellRaceFree`) now reads the configuration's
  typing (`CInv`). `CellOp`'s first case, a `withCell` through a borrowed
  root, is typed at the redex (`Redex.typed`, `withLock_live`), so the root
  is live and its owner is on the thread (`CellOp.cellAt`). `CellOp`'s second
  case, a step inside a check-out, asks an owner's share: the check-out goes
  through an owner, or through a borrowed parameter whose caller's argument
  is one, on the same thread (argued, as A3.5 argued it of any share).

**Faithful to the runtime.**
- *The in-place change* through a borrowed parameter is A3.2's check-out,
  with its premises: the parameter is a root the body does not name, frozen
  for the call, so the state is checked out and back where the runtime
  changes it in place.
- *A closure's code* changes a library handle in its environment (its
  environment is lent, and a lent cell share is the share), as the runtime's
  does. A3.5b's "the code never changes a library handle's state" no longer
  holds; the Sync question still keeps such a closure out of an `Arc`
  (h339), and a Send one is called by the thread that holds it.

**Probes.**
- h337 `library_handle_parameter_captured_by_a_thread`: taken `in`, the
  parameter is a borrowed root. `cellClone` of it is typed, and a spawn of
  the copy leaves the parameter and the caller's owner behind: the check
  fails and the spawn panics (`TStep.spawnFail`), as the runtime's count
  does.
- h333, h356, h319: a field read out of a handle-holding struct is a borrow
  (`projE`), which now holds the share. A `withCell` through it is refused
  (`StmtT.withLock` asks a root), and the spawn that moves the struct kills
  it, and passes the check, the borrow being dead; a copy of it (`cellClone`)
  is an owner the crossing check counts.

### (B) Read guards are `% NotSend`

A read guard is released by the thread that took it: `RGuard_drop` calls
`nurl_rwlock_rdunlock` on that thread, and nurlc marks `RGuard` and
`WGuard` `% NotSend` (`stdlib/std/rwlock.nu`). A3.3 let a model guard cross
a spawn: its type, `arc (prod (lk t) t)`, holds no view.

**The fork: a type-level mark or a run-time precondition.**
- *A type-level mark.* A guard's type is an `Arc`'s of a lock share and its
  payload. The model has one type for both (A3.3, as A3.6's `GlobFits` says
  of a `make` that hands one back), so a mark would be a new type
  constructor, with a case in every function on types and values. And a
  closure's type hides what it captured (its class, `Ty.fn ms q`), so a
  spawn could not see a guard a `send` closure captured without a new class.
- *A run-time precondition, with the crossing check.* Chosen. The check
  already walks what crosses, into closures' environments (`Sub`), at every
  crossing, and panics when it fails. It asks one more thing.

**The rule** (`A2/Semantics.lean`).
- `NoGuard B vs`: no view is reached from the crossing values
  (`Reached (· ∈ vs) B`, through the payloads of the blocks their shares
  name).
- `SendCheck B vs st'` is the cell count and `NoGuard B vs`. It takes the
  store's blocks; every site passes its own (`m1.blk`, `m.blk` in
  `GiveCheck`, `C.blk` at a spawn).
- So a spawn, `locked_new`, a cell's constructor, `locked_restore`,
  `chan_send` and a lock scope's give-back each refuse a value that reaches
  a read guard, and panic: `TStep.spawnFail`, `EvalR.lockNewFail`,
  `cellNewFail`, `lockRestoreFail`, `chanSendFail`, `Step.scopeLFail`. There
  is no new step.

**What it refuses**, as the task of `% NotSend` is given to a crossing:
- *A share of a view block*, held at any depth (a field, an element, a
  closure's environment) or kept in a block the value reaches: an `Arc`'s
  payload, a lock's (`guard_not_noGuard`, `guard_pay_not_noGuard`,
  `spawn_guard`, `lockNew_guard`, `chanSend_guard`). `arc_new` is no
  crossing, so an `Arc` may keep a guard on its thread, but the `Arc`'s
  share then crosses nothing.
- *A library handle in a view's payload*: there is none. `RhsT.rwRead` asks
  the payload's type to hold no cell share, and a view's payload is reached
  only through its guard, which does not cross.
- *A write scope*: no value. A write guard is the lock scope `scopeL`, which
  no step moves, and `wguard_get` lends a borrow, which no crossing takes
  (a spawn's and a lock's value is owned).
- A lock share of an `RwLocked` someone reads is no guard: the lock's
  block reaches its payload, not its views, so the handle crosses.

**A2's and A3's proof.** The failures are the checks' existing panics, and
progress decides the check by cases, so A2 needs no new argument. A3's
`CellKeep.moveIn` and `CellInv.spawn_of` read the cell count
(`SendCheck`'s first half).

**Faithful to the runtime.** nurlc refuses such a program statically; the
model panics at the crossing, so it covers more programs (those nurlc
refuses), never fewer. For the programs nurlc accepts no guard crosses, so
the guard half of the check always passes. A guard is then made by
`rw_read` on one thread, cloned there (`arc_clone`) and lent there, and
none crosses: the runtime's unlock runs on the locking thread. The phase-D
note on a guard crossing a spawn (A3.3, `CLAIM.md`) is closed; the one on
the view's sweep (a view lives until no slot reaches it, after the guard's
drop) stays.

### (C) Shares in a slice's elements

A3.1's first cut asked a slice's element type to hold no share
(`Ty.ok (slice t)`, `RhsT.view`). It is lifted, as A3.2's second cut lifted
it for a lock's payload: `Ty.ok (slice t)` is `t.ok && !t.holdsView`, and
`RhsT.view` asks no more. So a slice of `Arc`s, of locks, of library
handles, of `send` and `sync` closures is typed (`slice_share_ok`,
`view_share`).

**Is it sound?** The worry is that a view of shares lets two threads reach
one block through a slice. It does not:
- a slice is a view, which no crossing takes (`slice_not_send`): no spawn's
  argument (`SpawnOK`), no lock's, channel's or `Arc`'s value
  (`Ty.ok (lk _)`, `RhsT.arcNew`), no global (`Ty.sync`). It and what it
  lends stay on the thread that took it;
- what `sat` lends is what `vec_at` lends of the same `Vec`: an `arc` share
  or a lock share, which are Sync, or a cell share, a borrow whose owner is
  on the thread (A, `MInv.cell_owned`): the node a slice views is in one of
  the thread's owned trees, or in a frozen payload, which holds no cell share
  (`MInv.noCellPay`).
  Two threads that view one `Arc`'s payload, each through its own slice,
  read Sync shares only (`RhsT.arcNew`'s `hasCell`).

**A2's proof.** `out_sat` types an element read through a slice as `out_at`
types one read through a `Vec`. For a share it needs the viewed node's
shares to name blocks of their types. `ViewAt` does not carry that
(`HrefAt` does), and need not: the node is found in memory (`DataAt`), in
an owned tree, whose shares `MInv.shares` gives, or in a frozen payload,
whose shares `MInv.blocks` gives. `SharesIn.sub` (a part of a well-formed
tree holds, at its own type, the tree's shares) and `SharesOK.sub_node`
give them at the node (`MInv.dataAt_shares`).

**Closure classes.** `bare` (no share at all) was what a slice of closures
needed. No rule asks for it now; it stays as the bottom of the order.

### Not proven here

- *Phase D*, as above: the runtime's count of a handle's block is the cell
  shares the model's owned slots and lock payloads hold.
- That a thread inside a check-out of a cell holds an owner's share of it,
  as a lemma (`CellOp`'s second case; A3.5 argued it of any share).
- A store of a borrowed handle into an owner (an implicit copy), and
  `% Sync` / `% NotSend` assertions on a program's own types (A3.5b's and
  A3.5c's rest: a negative marker only removes typings).
- That no read guard leaves its thread, as a lemma over reachable
  configurations. It is argued above from the check at every crossing, as
  A3.5's first cut argued `CellOp`'s second case.
- The probes as whole typed programs (as `A2/DynCell.lean` types `pick`).

## Open questions

- **How much of A2 to copy** (decided in A3.0): none. A3 imports A2 and
  runs its step on each thread's view; a frame lemma moves the step
  between the shared address space and the thread's own part, where A2's
  invariant holds. A3.1–A3.6 add the shared blocks. For `Arc` they go into
  A2 (above). `Locked`, `RwLocked`, `Atomic` and channels have no
  single-threaded meaning beyond A2's, so for them a step beside A2's may
  fit better; A3.2 decides. (Decided: `Locked` goes into A2 too, as a
  second kind of block; A3.2's mechanization, above.)
- **Scoped threads.** A thread that borrows its spawner's data and is
  joined before the frame ends (`par_map_index`) needs the borrow to
  outlive the spawn while the spawner is suspended. That would be A3.7,
  after A3.0–A3.6.
- **Fairness and progress.** `memory_safe` says no thread is stuck on
  memory. A thread waiting on a lock forever (a deadlock) is not stuck in
  that sense. Deadlock freedom is not claimed.
