# A2-dyn — values owned or not per call: design

## Status

Design only. Nothing below is in the sources yet, and A2's theorems
(`memory_safe`, `soundness`, `no_leak_end`, `no_leak_panic`) do not cover
the shapes it describes. `formal/RULES.md` marks each of them *outside the
calculus* (agora #184, #185, #186, #203, #205, #206). This note is the
specification the mechanization follows. It is the refinement `README.md`
lists as "values owned or not per call".

## What nurlc does

A function that hands back a borrowed parameter on one path and a fresh
value on another answers **per call** whether its result is owned
(docs/MEMORY.md §7.6, *Call results*):

    @ pick String p b c → String { ^ ? c p ( mk ) }

The callee stores an ownership bit beside the result (`mem_store_hown`;
`__nc_held_ty` / `__is_hown_ty` say which types carry one). Every consumer
goes by the bit. Where the result is bound, handed to a call, stored,
discarded, picked by a join's arm or matched, the fresh value is dropped
or moved in, and the lent one is copied or left to its owner (#185). A
`% Drop` value that cannot be copied is moved out on the path that owns it
and refused where it would have to be copied (#186, #203, #205). A raw
string handed back answers the same way (`__ret_unowned`, #206).

## Why A2 cannot type it

- `Fn.resOwn : Bool`, so `resMode fn` is `.own` or `.bor` for every call,
  and `FnOK` requires the result slot's entry to have that one mode.
- `StmtT.assign` pairs an owner with an owned value and a borrow with a
  borrowed one, never one binding with both.
- `StmtT.ite` ends both arms in one context. The arm that assigns
  `( mk )` and the arm that assigns `p` cannot agree on the result's mode.
- `SlotOK` ties a slot's run-time flag to its binding's mode:
  `sl.own = E.mode.ownSlot`.

## The semantics already decides it

No step changes:

- `Step.assign` evaluates `.var r` by `EvalR.moveOwn` when `r`'s slot is
  `⟨true, some v⟩` and by `EvalR.copy` when it is `⟨false, some v⟩`, and
  stores `⟨o, some v⟩`. The target's flag is the source's, per run.
- `callIn` ends with `assign x (.var r)`, so a call's result takes the
  flag its body left in the result slot.
- `DropSlot` frees `⟨true, some t⟩` and leaves `⟨false, v⟩` alone.
- `OwnedAt`, `HeapOK` and `Covers` are stated over the flag, not the
  mode, so an owned per-call value is in the heap invariant and the leak
  invariant already.

What is missing is the typing, and one expression to test the bit.

## The extension

### Syntax and semantics

- `Expr.owned (x : Var)`: 1 when `x`'s slot owns its value, 0 when not.
  `Eval.ownedT : m.st x = some ⟨true, some v⟩ → Eval m (.owned x) 1`, and
  `Eval.ownedF` for `⟨false, some v⟩`. This is the bit nurlc reads at a
  consumer.
- `Fn.resOwn : Bool` becomes `Fn.res : RMode` with
  `RMode := own | bor | dyn`, and `letcall` / `callc` bind the result
  slot as `⟨res = own, none⟩`. The initial flag says nothing: the value
  is `none` until the body assigns it.

### Typing

- **`Mode.dyn`**: a binding owned or borrowed per run.
  `isRoot = true`, `ownSlot = false`.
- **Its entry**: `path` is what it may lend, as for a borrow. `held` is
  what its value holds. `vdeps = path ++ held`.
- **`derive y E k` for a dyn `y`**: `⟨y, rootKind E.ty k⟩ :: E.path.map
  (comp · k)`. A borrow taken from it ends when `y` is replaced, as from
  an owner, *and* when what `y` may lend is replaced, as from a borrow.
- **`SlotOK` for `.dyn`**:
  `(sl.own = true → the owner's conditions) ∧ (sl.own = false → the
  borrow's conditions)`. The owner's conditions are `WFv` and `ViewsOK`
  over `held`. The borrow's are `ValOK` over `path` and `held`.
- **`RhsT.moveDyn`**: `.var y` with `y` dyn and live gives a dyn entry with
  `y`'s `path` and `held`, and kills `y` (`kill .replace y`, `y` dead).
  At run time this is `moveOwn` when the flag is set and `copy` when not.
  Either way `y` is unusable after it, and its drop flag decides whether
  its scope's end frees anything.
- **`StmtT.assign`** gains `Ex.mode = .dyn ∧ (E.mode = .own ∨ E.mode = .bor
  ∨ E.mode = .dyn)`. The old value is released under its flag
  (`DropSlot`, as now), and the entry becomes `{ E with mode := .dyn }`.
- **`StmtT.iteOwn x a b`**: `x` dyn and live; `a` typed with `x` refined
  to `.own` (path dropped: an owner is reached through its own slot);
  `b` typed with `x` refined to `.bor`. Both end in one context. Sound
  because `SlotOK` for `.dyn` under a known flag is exactly `SlotOK` for
  `.own` or `.bor`. This is how "moved in when fresh, copied when lent"
  is written: the owning arm moves `x`, the lending arm calls a clone.
- **`resMode`** maps `dyn ↦ .dyn`. `FnOK` checks the result slot's entry
  against it, and `callRes` gives the caller a dyn entry depending on
  what `lends` names.

### Where a dyn binding may go

It may be read (`ExprT`), borrowed from (`borrow`, `view`, `at`, `fst`,
`snd`, `getl`, `getr`, all through `derive`), and passed as an `in`
argument (`lendSlot` handles either flag). It may be moved into another
dyn binding (`moveDyn`) or assigned to one.

Everything that needs an owner refuses it until `iteOwn` has refined it:
a `sink` or `inout` argument, `PushArg.move`, a literal's field, a
package's environment, `takel` / `taker`, `unpair`, `free`. This is
nurlc's rule too: a per-call value reaches a consumer only through the
bit.

## What the proof has to show

- **Invariant.** `SlotOK` as above. `MInv`, `HeapOK` and `Covers` are
  unchanged.
- **New lemmas.**
  - `SlotOK` refinement under a known flag (`slotOK_dyn_own`,
    `slotOK_dyn_bor`).
  - `moveDyn` preservation. The set flag is the `moveOwn` case: the tree
    moves, `HeapOK` keeps one owner. The clear flag is the `copyBor`
    case.
  - Assignment to a dyn binding.
  - `iteOwn` preservation and progress (`Eval.owned` always steps on a
    bound slot with a value).
- **The case splits.** Every case split on `Mode` gains a `.dyn` case,
  about 400 sites over 28 modules. Most are absurd, because a dyn
  binding is never an `inout` or `sink` argument, never `rootb`, and
  never `canDo`. The rest copy the `.bor` case, adding the root dependency
  that `derive` adds.
- **Calls and renaming.** `Call.lean`, `CallMem.lean`, `CallInv.lean` and
  `Rename.lean` take `RMode` for `Bool` in `resOwn`. `Implements` asks
  `fn.res = sig.res`.
- **Done when.** `check.sh` passes, with the crown theorems over the
  extended calculus and standard axioms only. The six `RULES.md` rows move
  from *outside the calculus* to *done (A2-dyn)*, and `README.md` drops
  the line from "does not model yet".

## What stays out

- The copies themselves. A clone of the lent value is a call whose body
  is the standard library's (B).
- Destructors as code: a `% Drop` that runs a function and may panic
  (the next refinement).
