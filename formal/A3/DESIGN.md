# A3 — threads and data-race freedom: design

## Status

**A3.0 is proven** (`A3.claim : A3.Claim`, `A3/Claim.lean`). `A3/Defs.lean`
defines A3.0's configuration (`Thread`, `Cfg`, `Cfg.view`), its steps
(`TStep`: a thread takes A2's own `Step`; `spawn`), what a step touches
(`Touch`), a race (`Race`), and the claim (`Claim`: `MemorySafe ∧ RaceFree ∧
NoLeak` for every program A2 types); `../README.md` lists the modules of
the proof. A3.1's `Arc` and A3.2's `Locked` are mechanized in the same
claim (A3.1's and A3.2's mechanization, below; A3.2's first cut: what it
leaves out is listed there), and so are A3.3's `RwLocked` (A3.3's
mechanization, below: a lock block read through views, its read guards
lending the value frozen) and A3.4's `Atomic` and channels (A3.4's
mechanization, below; channels are primitive rules on a lock block's
queue). A3.5's first cut, library handles whose copies are one state and
the crossing check, is mechanized too (A3.5's mechanization, below: a lock
block shared by cell shares, which are not Sync; a spawn panics when its
check fails; and a race includes two threads changing one handle's state).
A3.5b/c (closures in shared payloads, trait objects) and A3.6 are design.
This note fixes the
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
  h211 h212 h213 h288 h289 h338); `CLAIM.md` / `README.md`.

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
leaves out.

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
    the share) is refused: the body could change its owner.
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
  that keep blocks alive.
- `withLock` takes a root that the body does not name, so a lock reached
  through a local borrow (a field or an element) is refused.
- `locked_take` / `locked_restore` are not separate rules.
- The update's body is a statement in place, not a closure called through
  a package.

**Not proven here.**
- deadlock freedom;
- that a typed program's lock scope ends in a `put`, as a lemma (it would
  need an invariant tying each `scopeL k` frame to block `k`);
- shares in a lock's payload;
- the probes h267 h358;
- relocking a lock on the OS thread that holds it: the model's thread
  waits (`Blocked`) or, since A3.3, panics (`Step.waitPanic`), but the
  runtime's default pthread mutex leaves it undefined (Agora #455, phase
  D).

## A3.3's mechanization (`RwLocked`, `% Frozen`)

**Status.** `RwLocked` is mechanized. `check.sh` is green with its rules in
A2 and A3, and `A2.memory_safe`, `A2.soundness`, `A2.no_leak_end`,
`A2.no_leak_panic`, the `DynCell` theorems and `A3.claim` are re-proven with
them. An `RwLocked` is a lock block (A3.2's), and a reader reads it through
a *view*, a third kind of block that its read guard shares. A panic now
gives a lock scope's payload back, and a thread that waits may panic
instead. `CLAIM.md` / `README.md` are not updated here.

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
  cross (below).

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
  (more programs, all safe). `% Frozen` is the share dependency.

**Simplifications in this cut.** Each is a restriction, and sound as stated.
- A payload holds no share, no view and no closure, as a `Locked`'s
  (A3.2).
- `rw_try_read` / `rw_try_write`, `wguard_get` (a lend under the write
  lock), `rw_get` (a copy) and `wguard_apply`'s result are not separate
  rules; `rw_apply`'s result is an assignment in the body.
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
- `rw_try_*`, `wguard_get`, `rw_get`;
- a typed program over these rules (a probe's encoding, as
  `A2/DynCell.lean` types `pick`);
- `CLAIM.md` / `README.md`.

## A3.4's mechanization (`Atomic`, channels)

**Status.** `Atomic` and channels are mechanized. `check.sh` is green with
their operations in A2 and A3, and `A2.memory_safe`, `A2.soundness`,
`A2.no_leak_end`, `A2.no_leak_panic`, the `DynCell` theorems and
`A3.claim` are re-proven with them. A channel is a lock block whose payload
is its queue and its closed flag, and `chan_send`, `chan_recv`,
`chan_try_recv` and `chan_close` are primitive rules on it (Channels,
below). `CLAIM.md` / `README.md` are not updated here.

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
  that keep blocks alive.
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
- `CLAIM.md` / `README.md`.

## A3.5's mechanization (library handles, the crossing check)

**Status (first cut).** Library handles whose copies are one state are
mechanized, and so is the crossing check that lets one move to another
thread. `check.sh` is green with them in A2 and A3, and `A2.memory_safe`,
`A2.soundness`, `A2.no_leak_end`, `A2.no_leak_panic`, the `DynCell`
theorems and `A3.claim` are re-proven. A3's race now includes two threads
changing one handle's state, and the claim proves there is none. Closures
in shared payloads and trait objects (A3.5b/c) are not done. `CLAIM.md` /
`README.md` are not updated here.

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
  typing, and memory cannot tell a dead borrow from a live one.
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
  (`out_cellClone`).
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
  fields, payloads, elements, a package's environment). The model has no
  trait objects or containers beyond `Vec`.
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
  a handle read out of a borrowed struct is not changed through.
- *Copies are explicit*: `cellClone` of an owner. A store of a borrowed
  handle into an owner, which the runtime makes a copy, is not typed:
  `PushArg` moves owners only, as for every owning type.
- *A cell's state is a lock's payload*: it holds no view, no closure and no
  share.
- *A closure that captures a handle* holds the share in its environment,
  which a spawn moves and checks. But a call lends the environment
  (`envMem`), so the closure's own code does not change the state. That
  is A3.5b's.
- *The other crossings.* `chan_send`'s and `Locked`'s (`locked_new`,
  `locked_set`, `locked_restore`, after `locked_with`) need no run-time
  check here: their values hold no share at all, so the check has nothing
  to find. It is refused statically, which is more than the runtime
  refuses.
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
  (were it modeled) an `Rc` is a `Locked`'s value; `lk_noCell`.
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
- **A3.5b/c, not done**:
  - closures in shared payloads: h339
    `closure_in_an_arc_captures_a_library_handle`, h340
    `closure_sent_on_a_channel_captures_a_kept_handle`, h342
    `route_handler_changes_its_capture_on_two_threads` (a closure kept in
    an `Arc`, sent on a channel, or run by several threads, that captures
    a handle or changes what it captured);
  - trait objects: h344 `dyn_object_carries_an_rc_to_a_thread` (a `%Trait`
    box crosses only when its trait is `: Send`, and the vtable checks
    it).
- A library handle changed through a borrow (`in` parameters), implicit
  copies, handles in containers with `S_sendck` hooks, `% Sync` / `%
  NotSend` assertions.
- The probes as typed programs (a probe's encoding, as `A2/DynCell.lean`
  types `pick`).
- `CLAIM.md` / `README.md`.

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
