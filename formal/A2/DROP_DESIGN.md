# A2-drop — destructors as code: design

## Status

**A2-drop.1 is mechanized** (Agora #221): destructors of a type that holds
no views, on the normal path and the panic path. `formal/check.sh` passes,
and `memory_safe`, `no_leak_end` and `no_leak_panic` cover `letd` /
`scopeD` on the standard axioms. A2-drop.2 (types that hold views, the
`DtorSafe` rule of Agora #224) is the next step.

Before this, a user destructor was outside the calculus. A2's drops ran no
program code: `DropSlot` frees a tree and cannot fail. This note fixes the
semantics and the typing that bring `% Drop` bodies inside the calculus.
It also fixes the rule the typing needs, which nurlc lacks today: the hole
of Agora #224.

The mechanization puts the destructor on the binding rather than on a type
`Ty.dtor f t`: `letd x f r s` binds `x` with destructor `f`, and `DtorOK P
f t` checks that `f` takes one `in` parameter of `x`'s type `t`, returns an
integer, and lends, holds and stores nothing. What follows reads `Ty.dtor f
t` as that binding.

## What nurlc does

`% Drop T { @ drop T self → v { … } }`. Whenever an owned `T` reaches the
end of its scope, nurlc calls `drop__T(self)` with the receiver lent, and
then frees the fields it manages, the drop glue (docs/spec.md §8.3,
docs/MEMORY.md §7.6 *Drop glue*). On the panic path:

- the drain runs destructors;
- a value leaves the journal before its destructor runs, so a panicking
  destructor is not run again;
- while it runs, its receiver's slot stays journaled for the drop glue,
  so a panic inside it still frees the fields.

## Why A2 cannot have it as an encoding

On the normal path a destructor is a call: `drop__T x` with `x` lent, just
before the scope frees `x`. A2 types that already. The panic path is
different. In A2 a panic unwinds to the nearest `recover` frame in **one
step**: `Step.scopeP` frees each frame's binding inside a single
derivation, so no program code runs during an unwind. A destructor that
runs, and may panic, while a panic unwinds needs the unwind to stop at
the frame, run the body, and go on.

## The hole this exposes (Agora #224)

A2 kills a binding through what it depends on and still drops it at its
scope's end. That is sound only because the drop reads nothing. With a
destructor the drop **reads** the value:

    : W { s v }
    % Drop W { @ drop W self → v { ( nurl_println . self v ) } }
    : ~ String s ( … )  : W w @ W { ( string_data s ) }
    ( string_push_str s … )      // reallocates: w is dead, its view dangles
    ^ 0                          // drop__W(w) reads the dangling view

nurlc accepts this today, and ASan reports a heap-use-after-free. The same
happens when `s` is moved into a `sink`, or ends in an inner scope. **A
drop is a use** (Rust's dropck). The typing below refuses each of these
where the view ends.

## The extension

### Semantics

- **A destructor type.** `Ty.dtor (f : Nat) (t : Ty)`: values of `t` whose
  drop first runs the program's function `f`. That function has one `in`
  parameter of type `t`, returns an integer, and lends nothing. Its
  values are `t`'s; only the type differs.
- **`Stmt.scopeD x f s`**, a run-time form. A binding of a destructor type
  is bound in it instead of `scope`. Its steps:
  - `s = skip`, `x` owns its value (`⟨true, some v⟩`): becomes
    `scope x (callDrop f x)`. The destructor runs on `x` lent, then
    `scope x` frees the tree, which is the drop glue after the impl.
  - `s = skip`, `x` moved (`⟨true, none⟩`): plain `scopeSkip`.
  - `s` panics with `x` still owning: becomes
    `.ok m1 (seq (scope x (callDrop f x)) .panic)`. The unwind stops
    here, runs the destructor, frees `x`, and raises again. The frame is
    gone, so a panic inside the destructor is not run again, and
    `scope x` still frees the fields: the journal's two rules. A `recover`
    outside catches the raise as it catches any panic.
  - inside: `scopeDIn`, congruence as `scopeIn`.
- `free x` and `assign x …` of an owned destructor value run its
  destructor first in the same way (`callDrop`, then the old step).

### Typing

- `StmtT.letv`, `letcall`, `unpair`: a binding of a `Ty.dtor` type is
  scoped by `scopeD`. The destructor call at its end is a use whenever
  the binding's slot still owns its value. At run time that is decided by
  the drop flag, so the typing must keep the value valid on **every**
  path where it is not definitely moved, not only where it is live.
- **The rule (#224).** An effect may not end, through its dependencies,
  a destructor value that is not definitely moved. Three parts:
  - `DtorSafe Γ e hv r : ∀ v E, Γ v = some E → E.ty.hasDtor →
    E.held.any (fun d => d.root == r && e.kills hv d.kind) = false`.
    It asks *every* destructor entry, live or dead. Every rule that
    kills (`push`, `pop`, `assign`, `free`, `moveOwn`, `takel` /
    `taker`, `unpair`, `exitScope`, and a call's `callPost`) takes it as
    a side condition.
  - A destructor value that is definitely moved has nothing to protect,
    so its move (`moveOwn`, `PushArg.move`, a `sink`) drops the entry's
    dependencies: `{ E with live := false, held := [] }`.
  - At a join, `EntryWeaker` keeps a destructor entry's dependencies
    even when it is dead (`E.held ⊆ E'.held` regardless of `live`). A
    binding moved on some paths only keeps what it views on the others.

  This refuses the reallocation, the move into a `sink` and the inner
  scope's end above. It also refuses `? c { ( consume w ) } {}` followed
  by a change to what `w` views, where the destructor still runs on the
  path that kept `w`. An entry marked "live" would not refuse that: it is
  dead after the join, yet its slot may own. A destructor value whose
  type holds no views is never hit, so nothing changes for it.
- `FnOK` checks the destructor's body as any function's. A body that
  panics is allowed: the panic step above handles it.

### What the proof has to show

- **Preservation** of the four `scopeD` steps. The normal one is a call
  (`callStmt`) followed by a scope's drop, both proven. The panic one is
  a call inside `seq … .panic`. The invariant it needs is that the
  unwind has freed the inner frames exactly as `scopeP` does today.
- **Progress.** A `scopeD` always steps: on its body, on its end, or on
  its body's panic.
- **`no_leak_end` / `no_leak_panic`.** The destructor's own allocations
  are freed by its scopes (`FnOK`). `scope x` frees the receiver after
  it, and a panic inside the destructor unwinds through `scope x`.
- **`DtorSafe`** is what makes the destructor's read of `x` valid. For a
  destructor type, `SlotOK` asks `ViewsOK` over `held` whenever the slot
  owns a value, not only when the entry is live. `DtorSafe`, the moves
  that clear `held` and the join that keeps it make that invariant
  preserved, so at `x`'s scope end the value the destructor reads is
  valid however `x` died.

## Staging

The panic-path semantics is the hard part of the proof. `DtorSafe` is a
separate concern. Two steps keep them apart:

1. **A2-drop.1: destructor types that hold no views**
   (`Ty.dtor f t` with `t.holdsView = false`).
   - Such a value has no view inside it. `SlotOK` already guarantees an
     owned tree's `WFv` whether its binding is live or dead. So the
     destructor's read is valid however the binding died, and no
     `DtorSafe` is needed.
   - This step proves `scopeD`'s four steps, the unwind stopping at a
     destructor, and the double panic. It covers handle-like destructors:
     a file, a socket, a database connection, a struct of owned fields.
2. **A2-drop.2: destructor types that hold views.** `DtorSafe`, a move
   that clears `held`, the join that keeps it, and `SlotOK`'s
   `ViewsOK`-whenever-owned. This step covers #224's shape (a `% Drop`
   struct with a view field), which nurlc's rule refuses wherever the
   view would end.

## The panic step's proof (A2-drop.1, done)

`scopeDP` turns a panic into a normal step, so preservation must type what
follows it. That needed three things A2 did not have:

1. **The context after the unwind** (`unwindCtx`, `MInv.unwind`). The
   scopes the panic unwound are gone from the store. A binding that
   depended on one of them is dead, `x` is live again (it holds no views),
   and the rest is unchanged. For that to satisfy `MInv`, no borrowed
   parameter outside those scopes may depend on them. That is the new
   invariant `Inv.pinOut` / `PinOK`, which every step keeps:
   - a new scope binds what was unbound, while a borrowed parameter depends
     only on what is bound;
   - a call's frames are fresh, and a parameter depends only on what is
     older than it (`rootbLt`).

   With it, `rootKeep_frame_sp` shows that every surviving view reaches the
   same memory.
2. **The destructor's call** in that context (`dtorCall_typed`), as on the
   normal path. `NoPin` for `x` follows from `pinOut`, because `x` is in
   the frame's own spine.
3. **The re-raised panic.** `StmtT.panic` relates its input to its output:
   same bindings, modes and types, and fixed entries unchanged. Its output
   is the frame's original output `exitScope x Δ1`, so `Δ1` must agree with
   the context outside the body's spine. Nothing proved that for a run-time
   body, so the frame carries it, as `StmtT.catchR` already does:
   - `StmtT.scopeD` takes `KeepOut Γ Δ s.spine`, `CtxWF Δ` and `NameWF Δ`;
   - `StmtT.letd` takes the same for its source body;
   - a step inside the body keeps `KeepOut` (`KeepOut.step`, from `Keep`);
   - renaming keeps all three (`keepOut_canon`, `canon_wf`,
     `canon_names`).

   A fixed entry of the post-panic context is a borrowed parameter, since
   `MInv` has no `inout` entry. The unwind and the body's typing both left
   it as it was.

`letd`'s new premises restrict which programs the calculus types: a body
whose typing changed a binding's mode, or a borrowed parameter's entry,
would not be typed. Every typing rule keeps both, so this is no loss in
practice. Proving it once for every source derivation (`StmtT.domTy`,
`StmtT.wf`, `StmtT.names` cover all but the borrowed parameters) would let
the premises go.

## Done when

For A2-drop.1, the first two hold (Agora #221). The third is A2-drop.2's.

- `check.sh` passes, with `memory_safe`, `no_leak_end` and
  `no_leak_panic` over `Ty.dtor` / `scopeD`, standard axioms only;
- `CLAIM.md`'s *Destructors* section moves from "outside the calculus" to
  the proof;
- `RULES.md` records #224's rule, as an extension that rejects more,
  with the `DtorSafe` row.
