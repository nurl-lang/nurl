# A3 — threads and data-race freedom: design

## Status

**A3.0 is proven** (`A3.claim : A3.Claim`, `A3/Claim.lean`). `A3/Defs.lean`
defines A3.0's configuration (`Thread`, `Cfg`, `Cfg.view`), its steps
(`TStep`: a thread takes A2's own `Step`; `spawn`), what a step touches
(`Touch`), a race (`Race`), and the claim (`Claim`: `MemorySafe ∧ RaceFree ∧
NoLeak` for every program A2 types); `../README.md` lists the modules of
the proof. A3.1–A3.6 below are design. This note fixes the
semantics, the theorem statements and the order of work, so the
mechanization can be cut into tasks (Agora: formal track, F4–F8). The guarantee it targets is the
"no data race" clause of `CLAIM.md` and `docs/MEMORY.md` §6.2. The rules
are §6.5's.

## The theorem

For a program whose functions all check (`ProgOK`), with a source
statement well-typed in the empty context, run from the empty
configuration:

- **`A3.memory_safe`**: no reachable configuration is stuck. A2's
  statement, now for every thread.
- **`A3.no_leak`**: when every thread has ended, nothing is allocated.
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
  only removes typings.
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
- (B) `ValOK.arc` asks `∃ dep ∈ P, Landed m dep (.arc k p)`: a lent share
  lands through a dependency, as an `href` does. `valOK_arc` finds it in a
  borrowed value, `bor_lands` uses it for (A)'s disjunct. `lend_valOK'`
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
  (`PayFree`), and `arcNew` / `arcGet` still ask `Ty.plain`.

After that, step (d) is: `Ty.plain` lifted to `holdsView = false ∧
hasFn = false`, `arcNew` moving a tree into a new block (`BlkOwn` for it),
`arcGet` lending the `href` through the share landing, and `bpay` removed.
Step (e) is `Covers` counting payloads and `Steps` running the sweep
(`CatchOK`'s `BlkLe` must weaken to blocks that are reached). Step (f) is
A3 with payload addresses: they are read only, so `Touch`, `Avoids` and
the partition need a shared, read-only part.

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

## Open questions

- **How much of A2 to copy** (decided in A3.0): none. A3 imports A2 and
  runs its step on each thread's view; a frame lemma moves the step
  between the shared address space and the thread's own part, where A2's
  invariant holds. A3.1–A3.6 add the shared blocks. For `Arc` they go into
  A2 (above). `Locked`, `RwLocked`, `Atomic` and channels have no
  single-threaded meaning beyond A2's, so for them a step beside A2's may
  fit better; A3.2 decides.
- **Scoped threads.** A thread that borrows its spawner's data and is
  joined before the frame ends (`par_map_index`) needs the borrow to
  outlive the spawn while the spawner is suspended. That would be A3.7,
  after A3.0–A3.6.
- **Fairness and progress.** `memory_safe` says no thread is stuck on
  memory. A thread waiting on a lock forever (a deadlock) is not stuck in
  that sense. Deadlock freedom is not claimed.
