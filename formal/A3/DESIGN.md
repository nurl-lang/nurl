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

A3.0 settled that A3 imports A2 and runs A2's step on each thread's view,
so a shared block has to live somewhere A2's step can read. For `Arc` the
block goes into A2 itself. Single-threaded, an `Arc` is a counted
reference (as `Rc` is in Rust), and nurlc's single-threaded code already
uses `Arc` widely.

**In A2.**
- `Mem.blk : Nat → Option Blk`, with `Blk := ⟨rc, pay⟩`. A block's payload
  tree is owned by the block: `HeapOK`'s one owner per allocation counts
  blocks next to slots, and `Covers` counts them too.
- `Val.arc k`, a leaf: a share of block `k`. `Ty.arc t` is owning, it
  holds a view exactly when `t` does, and it is never copied.
- `RhsT.arcNew y`: `y`'s tree moves into a fresh block with `rc = 1`. The
  share is owned and holds what `y` held, since the payload views what `y`
  viewed (nothing, in the first cut below).
- `RhsT.arcClone a`: a read of share `a` that adds a new share, `rc + 1`.
  It holds what `a` holds.
- `RhsT.arcGet a`: the payload, lent. Its entry is a borrow rooted at `a`
  (`derive a … .view`), holding `a`'s `held`, so it ends with `a` like any
  borrow.
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
