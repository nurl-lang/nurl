# A2-drop — destructors as code: design

## Status

**A2-drop.1 and A2-drop.2 are mechanized** (Agora #221, #241): destructors
of every type a destructor can have, views included, on the normal path and
the panic path. `formal/check.sh` passes, and `memory_safe`, `no_leak_end`
and `no_leak_panic` cover `letd` / `scopeD` on the standard axioms, with
the `DtorSafe` rule of Agora #224. A2-drop.3 (the destructor on the type,
Agora #253) is designed below (*A2-drop.3*), in four cuts.

Before this, a user destructor was outside the calculus. A2's drops ran no
program code: `DropSlot` frees a tree and cannot fail. This note fixes the
semantics and the typing that bring `% Drop` bodies inside the calculus.
It also fixes the rule the typing needs, which nurlc lacks today: the hole
of Agora #224.

Until A2-drop.3a the mechanization put the destructor on the binding
(`letd x f r s`) rather than on a type. Since A2-drop.3a it is on the type:
`Ty.dtor f t`, of a struct or an enum `t` (`WFv.dtor` asks `t.isStruct`, as
nurlc's `% Drop` is on a struct or an enum), whose values are `t`'s. `DtorOK
P f (Ty.dtor f t)` checks that `f` takes one `in` parameter of that type,
returns an integer, and lends, holds and stores nothing.

What runs the destructor, since A2-drop.3a. The typing's guarantee for
each binder below, and the `scopeD` frame's end running the destructor,
are theorems (`A2/DtorWitness.lean`: `A2.Dtor.*`, with a typed witness
program, `A2.DtorWitness`); that these binders are all the places an
owned destructor value comes to rest is read off the rules. Below, a type *holds a
destructor* (`Ty.holdsDtor`) when it is a destructor type, or a struct or
an enum one field or payload of which holds one, at any depth (since
A2-drop.3b; A2-drop.3a's rule looked one level down only).
- Every owned binding of such a type is `letd`'s, whose scope (`scopeD`)
  runs the destructor at its end and on a panic's unwind, except the
  check-out bindings of `withLock` and `withCell` (not yet, below;
  `withElem` checks out none, since a `Vec`'s element type holds no
  destructor value, A2-drop.3b). `letv` refuses
  one (`StmtT.letv`'s `hnd`). A binder that may receive one without running
  `scopeD` itself hands it to its `letd` first thing (`Stmt.movedFirst`):
  a call's result (`letcall`, `callc`, `callcE`, asked of the callee's
  signature), a field `unpair` moves out (`hdx` / `hdz`), and a `sink`
  parameter in its callee's body (`FnOK`'s `DtorParamsOK`). Nothing runs in
  between, so nothing can panic or end the value first, and that `letd`'s
  scope ends where the binder's does: the destructor runs where nurlc runs
  it. (The head may end in a move into another binding of the same type,
  `assign y (.var w)`, whose own binder answers for it: a function's
  result, or the call's result binding the package hand-over's run-time
  form moves the code's result into.)
- **A struct holding a destructor value is a destructor type itself, its
  drop glue its destructor.** `letv` refuses an owned `prod (dtor g s) b`,
  so such a struct is bound by `letd x f (pair y z)`, at `Ty.dtor f (prod
  …)`, and `f` is its glue: the elaboration's function that lends each
  destructor field to its destructor (`fst` / `snd` read a field through
  the type, `E.ty.undtor = .prod a b`), after any `% Drop` of the
  struct's own: nurlc runs the impl first, then the fields' glue. The calculus
  checks `f` as it checks any destructor (`DtorOK`, `FnOK`); that it calls
  the fields' destructors is the elaboration's part, as nurlc generates the
  glue. Deeper nesting: a struct or an enum holding such a struct, with no
  destructor type of its own between them, holds a destructor value too,
  since `Ty.holdsDtor` is deep (A2-drop.3b), so it is bound by `letd` with
  its glue as well (`A2.DtorWitness.main4_safe`, a `sum (prod DT int)
  int`); under A2-drop.3a's one-level rule `letv` bound it with no glue.
  The same holds for an enum holding one in a payload: its glue matches on the tag and lends the payload to its
  destructor (`getl` / `getr` lend a payload through the type, `E.ty.undtor
  = .sum a b`); no such glue is mechanized as an example.
- **`assign` replaces no owned value that holds a destructor.** Its drop
  of the old value is `DropSlot`, which runs no code. So the bindings that
  may own one say so of their scope (`Stmt.assigns`): `letd` (`hna`), a
  call's result and `unpair`'s fields (with `movedFirst`), and a `sink` or
  `inout` parameter (`DtorParamsOK`; an `inout` one holds the caller's
  value). A function's owned result of such a type is set at most once on
  any path (`Stmt.asgMax ≤ 1`), so no earlier result is dropped. A program
  replaces such a value as nurlc's `= x v` does in effect: it moves the old
  value to a `letd` (`letd y f (.var x) .skip`), whose scope runs the
  destructor at once, and binds the new one with `letd`. This is stricter
  than nurlc, which assigns in place.
- **`free` takes only a `Vec`** (`E.ty = .vec t`), and a destructor wraps
  only a struct or an enum. Since A2-drop.3b a `Vec`'s element type holds
  no destructor value (`Ty.ok`), so what `free` releases runs no
  destructor, except a share's payload or a closure's environment (3c, 3d).
- **Taking a destructor value apart is refused**: `unpair` asks `E.ty =
  .prod a b` exactly, and `takel` / `taker` `E.ty = .sum a b`; so is a field
  written in place (`unpair` and `assign`). Taking it apart would bypass the
  destructor. Its fields and payloads are lent through the type instead,
  and an `inout` parameter of such a type is neither assigned nor taken
  apart. This is stricter than Rust, which refuses a move out of a type
  with a `Drop` impl of its own but lets a program take apart a struct
  whose fields alone have one; here a struct whose destructor is only its
  glue is a destructor type too.

Not yet (DropSlot / `Frees` release the value, running no code; nurlc runs
the destructor there):
- closure and trait-object environments (3c), a `Vec` element's included;
- `Arc`, lock and cell payloads (3d), a `Vec` element's included.
  `SpawnOK` refuses a spawned function's parameter whose type holds a
  destructor value at any depth (`Ty.holdsDtor`); a lock of one (`lk DT`)
  still crosses, as does an `Arc` or a cell of one.
- check-out bindings (`withLock`, `withCell`) of a destructor type: owned,
  no `letd`'s; the value goes back at the scope's end, but an `assign` to
  the binding drops the old value with no destructor (3d;
  `A2.DtorWitness.lock_checkout_assign` types it).
- A function's result that holds a destructor value, set before a panic
  in that function (another binding's destructor included): the unwind
  releases it with the call's result scope, without its destructor.
  nurlc's `^ v` returns at once, so only the destructors of the callee's
  own locals run after it.

Refused rather than released since A2-drop.3b (`Ty.ok`; stricter than
nurlc, which types them and drops a `Vec`'s elements in index order, each
running its destructor): a `Vec` whose element type holds a destructor
value, at any depth, so a `Vec D` and a `Vec` of an enum or an option
holding one, and every type with one inside: a channel of `D` (its queue
is a `Vec`), `Locked (Vec D)`, `Arc (Vec D)`, a cell of a `Vec D`, and a
struct or an enum with a `Vec D` field or payload. So `withElem` checks
out no destructor value, and the result moved from its slot into a local
before a panic (`pair res w`, a destructor value two levels down) is a
`letd`'s, since `Ty.holdsDtor` is deep: `letv` refuses it, and the
`letd`'s scope runs its glue on the unwind.

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

## A2-drop.2's mechanization (Agora #241)

What the design above leaves open, settled against A2's code and against
github#1380, nurlc's side of #224.

**Which bindings run a destructor: two flags.** `Entry.dtor` says the
binding may own a value whose destructor will run (it is *armed*).
`Entry.dbind` says the binding was made by `letd`, and never changes. Both
are needed. A move disarms a binding (`dtor := false`), while `dbind`
remembers that an assignment would re-arm it. `letd` sets both when its
type holds views (`Entry.arm`): a destructor of a type that holds no views
reads only what its binding owns, so such a binding needs no care. Every
other rule makes entries with both false.

**A move ends the protection.** A binding moved out owns nothing, so it
runs no destructor (`scopeDMoved`). The moved-from entry becomes
`{ E with live := false, dtor := false }`, and from then on its sources
may change. That is the unconditional move nurlc accepts.

**The join keeps it** (the hole github#1380 had, dev #820, fixed in nurlc
by #252). `EntryWeaker` may raise `dtor` from false to true on a `dbind`
binding only, never lower it, and keeps a `dbind` binding's `held` as it
is. A binding moved on one path only is, after the join, dead but armed,
with the other path's `held`. Its slot may still own a value, so its
sources stay protected.

**`DtorSafe Γ e hv x`**: no armed owner has a dependency in memory
(`hitsMem`: views, not closure names) that effect `e` on `x` ends, live or
dead. It is a premise of every rule whose context change kills through
dependencies:
- the moves: `moveOwn`, `PushArg.move`, `takel` / `taker`;
- `pop`, `assign`, `push`, `free`, `unpair`;
- every call, for its moved and changed arguments and `killNames`
  (`CallDtorSafe`);
- every scope's end (`EndOK` = `NoPin` ∧ `DtorSafe .replace`, in place of
  `NoPin` in `letv`, `letcall`, `letrec`, `callc`, `scope`, `letd`,
  `scopeD`, `unpair`, `free`).

Names are left out because a destructor reads views, and a destructor
binding's type holds no closure (`letd` asks `hasFn = false`). Renaming
needs that: a callee's binding may additionally hold the arguments'
closures' names (`A`), though it holds none of them.

**A destructor binding gains no view** (the panic path, nurlc #254). An
unwind ends the scopes inside a frame early. So a binding that may run a
destructor must view nothing those scopes bound, at any point, not only
at their normal end. In A2-drop.2 a `dbind` binding of a view-holding type
gains no view at all:
- `assign` to it is refused;
- `push` into it needs elements that hold no views;
- it is no `inout` argument.

Its `held` is then the one `letd` gave it, made from what was already
bound. nurlc's rule is finer: a holder may gain views of older bindings
only. Covering that needs an age order the calculus does not have, so it
stays a documented gap.

The third point is a rule, not a convenience. A callee may point an
`inout` parameter at a view of its own local and back again before it
returns. A panic in between unwinds the callee's local first, and then the
caller's destructor reads it. nurlc checks the parameter only at the
callee's end, so this shape is open there (public #1030).

**A scope's end asks every `letd` binding** (`DbindSafe`, part of
`EndOK`): no `dbind` owner, armed or not, views the binding that ends.
A moved-out `letd` binding still lists its old views. If one of their
scopes ended, a later join could re-arm it with a view of whatever binding
takes that name next. The check costs nothing: a `letd` binding's views
are of older bindings, whose scopes enclose its own.

**The invariants.**
- `CtxWF.dtor`: a `dbind` owner's dependencies in memory are on bound
  roots, live or dead; `CtxWF.arm`: only a `dbind` binding is armed. Both
  are part of `CtxWF`, so a weaker context (`Weaker`) keeps them too.
- `Inv.dtorOut` / `dtorIn` (as `pinOut` / `PinOK` for borrowed parameters):
  a `dbind` owner depends in memory on no binding of a scope opened after
  it. `MInv.unwind` needs it. It holds when `letd` binds, and stays because
  a `dbind` binding's `held` never grows and the join keeps it.
- The frame's: for every `scopeD x` frame, whenever `x`'s slot owns a
  value, `x`'s entry is armed and that value's views are valid (`ViewsOK`
  over `held`), live entry or not. `DtorSafe` keeps it across every kill.
  A move empties the slot (`scopeDMoved` then runs nothing). So at
  `scopeDEnd` the destructor reads valid views however the binding died,
  and an armed dead entry whose slot owns is revived for the call
  (`MInv.revive`, now with views).

**Calls.** `liftE` keeps both flags. A borrowed parameter's entry is
neither (`pe_dtor`). A function's typing ends with no flag set (`FnOK`):
its own destructor bindings have ended, and a parameter or the result runs
none. So inside a call, every armed binding is the caller's (`canon_dtq`),
and the result's move back is safe.

**What the proof needed beyond the design.**
- `CtxWF.view`: only a binding of a type that holds views is `letd`'s. A
  closure's capture is then never one (`letd` asks `hasFn = false`).
- `MInv.armed` (`ArmOK`): whenever a `letd` binding's slot owns a value,
  the binding is armed and the value's views are valid (`ViewsOK` over
  `held`), live entry or not. `DtorSafe` keeps it across every kill, and
  a move empties the slot.
- `DStay`: a binding `letd` made stays one through every rule. It is a
  premise of `panic` and `catchR`, as `DKeep` is, so the unwind finds every
  destructor binding still marked.
- `scopeD` asks the same of its body's output: the binding is `letd`'s
  there when its type holds views. That is how re-typing a `scopeD` frame
  keeps the flag.
- `Entry.revive`: at `scopeDEnd` and in the unwind, an armed dead binding
  whose slot owns is revived for the destructor's call. It keeps its views
  in memory, minus any of itself, which `SelfFree` rules out
  (`ViewsOK.dropSelf`).
- `HeldUp`: `letd` may record its binding as viewing more memory than the
  value does, of bound roots. Where a call places a callee's body, the
  callee's binding is read as viewing anything the arguments held (`A`),
  while the renamed value views exactly its own. Recording the larger set
  keeps the binding's views exact under `EntryWeaker.dheld`. nurlc
  records exactly the value's views.

**Mechanization status.** Done (Agora #241), with no `sorry` and the
standard axioms only:
- the flags and `Entry.arm`;
- `EntryWeaker` (`dtor` / `dbind` / `raise` / `dheld`);
- `hitsMem`, `DtorSafe`, `DbindSafe`, `EndOK`, `CallDtorSafe` on every rule above;
- `CtxWF` (`live` / `dtor` / `arm` / `view`);
- `Inv.dtorOut` / `DtorPinOK`, `MInv.armed`, `DKeep` / `DStay`;
- `MInv.revive` and `MInv.unwind` with views, and `dtorCall_typed` with views;
- the call, closure and A3 modules.

**What stays for A2-drop.3.** The destructor on the type, run wherever
the value is dropped: a field (drop glue), a `Vec` element, a `sink`
parameter in its callee, the old value of an assignment. Until then
`CLAIM.md` says where the calculus runs a destructor.

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
   - `StmtT.letd` takes nothing for them: its body is source code, and
     source typing keeps every binding with its mode and type, and an
     anchored borrowed parameter with its entry (`StmtT.ctxRel`,
     `A2/SrcKeep.lean`), so the step to `scopeD` derives all three
     (`srcCase`, the `SrcCase` hypothesis of `preserve`);
   - a step inside the body keeps `KeepOut` (`KeepOut.step`, from `Keep`).

   A fixed entry of the post-panic context is a borrowed parameter, since
   `MInv` has no `inout` entry. The unwind and the body's typing both left
   it as it was.

So `letd` types every body the other rules type (Agora #243): no premise
on the body's typing restricts which programs the calculus covers.

## A2-drop.3: the destructor on the type (Agora #253)

**Status.** A2-drop.3a is mechanized (Agora #541, *What runs the
destructor* above), with the struct glue as the struct's own destructor
and `assign` of a destructor value refused instead of `dropCode`. 3b–3d
are designed here; not mechanized. Until they are, `CLAIM.md`'s
*Destructors* section lists where the calculus releases a destructor value
without running it.

### What nurlc does that A2 does not model yet

A `% Drop` type's destructor runs wherever a value of it is dropped
(MEMORY.md §7.6, *Drop glue*), not only at the end of the binding that
made it:

| Where the value ends | nurlc | A2 today |
|---|---|---|
| a binding's scope (a local, a `sink` parameter, a call's result, `unpair`'s fields) | the destructor, then the glue | only for `letd`'s binding (`scopeD`) |
| `= x …` over an owned value, `vec_free x` | the destructor of the old value first | `DropSlot` / `Frees` |
| a struct field, at the struct's drop | the field's destructor, inside the struct's glue | `Frees` of the tree |
| a `Vec` element: `vec_pop` dropped, `truncate`, `clear`, `vec_set` over it, the Vec freed | each element's destructor | `Frees` |
| an enum or option payload | the payload's destructor | `Frees` |
| a closure's or a trait object's environment | the captures' destructors | `Frees` of the env tree |
| a panic's unwind through any of these | the journal runs each, once | `scopeP` frees in one step, except at `scopeD` |
| an `Arc` / lock block's payload when its last share goes (A3) | on the thread that drops the last share | the sweep, which runs no code |

### Semantics

- **The type carries it.** `Ty.dtor f t` becomes a type constructor:
  values of `t` whose drop first runs the program's function `f` (`DtorOK
  P f t`, as now). `letd` becomes a derived form: `letv` of a `Ty.dtor`
  type. `Entry.dtor` / `Entry.dbind` are then read off the type (two
  new functions, `Ty.hasDtor` and `Ty.dtorViews`), not set by the binding
  form.
- **Drop glue as code.** `dropCode t x : Stmt`, by recursion on `t`,
  is the statement that drops the tree in `x`'s slot:
  - `Ty.dtor f u`: the destructor's call on `x` lent (`callDrop f x`
    below: the `letcall _ f [x] .skip` that `Step.scopeDEnd` runs now),
    then `dropCode u x`;
  - `prod a b` holding a destructor: `unpair y x z (seq (dropCode a y)
    (dropCode b z))`: the fields move to bindings of their own, dropped
    in field order, as nurlc's glue does;
  - `sum a b` holding one: an `ite` on the tag, each arm taking the
    payload out and dropping it;
  - `vec u` with `u` holding one: `while (len x > 0) (pop-into y
    (dropCode u y))`, then `free x` of the empty Vec;
  - a type holding no destructor: `free x` (today's `Frees`), so nothing
    changes for programs without `% Drop`, and the old proofs carry over
    for them unchanged.

  Every drop site becomes `dropCode` of the type it drops, where the
  type holds a destructor: `scope x` at its end (with `scopeD`'s four
  steps generalized from `letd`'s binding to any binding whose type holds
  one), `assign` over an owned value (the old value moved to a fresh
  binding first, then `dropCode`), `free`, and `edit`'s drops (`pop`,
  `truncate`, `clear`, `set`: each dropped element taken out to a fresh
  binding and dropped in index order).
- **The unwind** stops at every frame whose binding's type holds a
  destructor, not only `scopeD`: `Step.scopeDP` generalized. A panic
  inside a destructor is not run again (the frame is gone), and the glue
  after it still frees the fields: the journal's two rules, as now.

### Typing

- `DtorSafe` and `EntryWeaker`'s rule for `dtor` entries already ask
  every entry whose binding may run a destructor; they now ask every
  entry whose type holds one with views (`t.dtorViews`), wherever the
  value came from. A move disarms the source, as now. What is new is
  where a destructor value can land: a field, an element, a payload, an
  environment. The holder then runs it, so the holder's entry inherits
  the obligation (`held` keeps what the destructor reads).
- `dropCode` is typed by a lemma, not a rule (as A3.2's derived lock
  forms are): `dropCode_typed : DtorsOK P → Γ x = some E → E.ty = t →
  StmtT P F Γ (dropCode t x) (Γ.kill x)`, by induction on `t`. Each drop
  site's typing then reuses the existing rules for `callDrop`, `unpair`,
  `ite`, `while`, `pop` and `free`.

### What the proof has to show

- **Preservation** of each drop site's step into `dropCode`: the derived
  typing above, and that the invariant before the step gives the
  `dropCode` statement's precondition (the value in `x`'s slot is the
  tree `t` describes; the destructor's views are valid, by `DtorSafe`).
- **Progress**: `dropCode` is built from forms that step; its `while`
  terminates, since each round pops one element (a measure on the Vec's
  length, which `dropCode u y` cannot grow: `y` is a fresh binding).
- **`no_leak_end` / `no_leak_panic`**: `dropCode t x` frees every
  address of `x`'s tree. By induction on `t`: each case frees what it
  takes apart, and the last step is `free` of a destructor-free rest.
- **The double panic**: a panic inside `dropCode` unwinds through the
  frames `dropCode` opened (each `unpair` / pop binding's scope), so the
  rest of the tree is still freed.

### Staging

Each cut is mechanized and checked by `check.sh` before the next, and
each one shrinks `CLAIM.md`'s exception:

1. **A2-drop.3a: bindings and fields** (done, Agora #541). `Ty.dtor` as a
   type, and every owned binding of a type holding one is `letd`'s or
   handed to one first thing (a local, a `sink` parameter, a call's
   result, `unpair`'s fields). The cut was mechanized differently from the
   plan above in three places:
   - a struct holding a destructor value is a destructor type, its glue
     its destructor; there is no `dropCode` statement;
   - `assign` of a destructor value is refused, and the program moves the
     old value to a `letd`;
   - `unpair` of one is refused, and `takel` / `taker` of a destructor
     enum (its payloads are lent through the type, `getl` / `getr`).
   `free` takes only a `Vec`. Not yet: elements, payloads inside
   containers, environments, blocks, check-out bindings, and a result set before a panic in
   its callee.
2. **A2-drop.3b: containers** (first milestone done, Agora #542).
   - Done: `Ty.holdsDtor` is deep, so a struct, an enum or an option
     holding a destructor value at any depth is bound by `letd` with its
     glue: a typed `letv`'s owned value is free of one
     (`A2.Dtor.letv_owned_dtor_free`; `A2.Dtor.holdsDtor_deep` unfolds the
     definition). What the deepening adds is a destructor value two levels
     down, under a struct of no destructor type: `sum (prod DT int) int`,
     refused by `letv` (`A2.DtorWitness.main4_letv_refused`) and bound by
     `letd` with its glue (`A2.DtorWitness.main4_safe`). An option of a
     destructor value (`A2.DtorWitness.main3_safe`) is a further witness,
     not a new capability: 3a's one-level rule sent it to `letd` too. A
     `Vec` of destructor values is refused: `Ty.ok` asks a `Vec`'s element
     type to hold none (`Ty.dtorFree`), and `RhsT.new` asks it. So no
     binding holds one (`A2.Dtor.vec_elems_dtor_free` at a binding's top,
     `A2.Dtor.vecs_dtor_free` anywhere in its type, through `Ty.ok`'s
     recursion), and `pop`, `truncate`, `clear`, `set`, `free`, `withElem`
     and `edit` through a borrow release or check out no destructor value,
     except a share's payload or a closure's environment (3c, 3d). A
     share's payload and a view are free of one by definition (3d; a view
     owns nothing). The refusal reaches every type with such a `Vec`
     inside: a channel of `D`, `Locked (Vec D)`, `Arc (Vec D)`, a cell of
     one, a struct or an enum with a `Vec D` field or payload
     (`CLAIM.md`'s list of where the rules are stricter than nurlc).
   - **Built (Agora #542, part 2's first milestone): the drain's step.**
     `vec_remove y 0` is `Rhs.popFront`: element 0 moves out, typed as
     `vec_pop` (`RhsT.popFront`), `EvalR.popFront` / `popFrontEmpty`.
     Its preservation is a `vec_pop` of element 0 moved to the end
     (`A2.rhs_popFront`, from `MInv.perm` and `rhs_pop`; the permutation
     lemmas moved from `A2/Elem.lean` into `A2/Rhs.lean` so that
     `rhs_pres` can use them). nurlc drops a `Vec`'s elements in index
     order (`nurl__vec_drop_elems`, `i = 0 .. len`), so the drain takes
     element 0 each round, not the last one.
   - **Built (milestone 2b, part 1): the steps, the refusals and the
     binder's shape.** `Step.scopeDDrain` / `scopeDEmpty` / `scopeDPDrain`
     are in the semantics, and `scopeDEnd` / `scopeDP` take a value that is
     no node (`Val.isNode`). Every case site has them (Progress, StepFrame,
     Codes, Steps, and A3's Lift, Fresh, BorFree, Keep, Restrict, Owned,
     Cell). `StmtT.free`, `editB`, `editBV` and `withElem` ask `dtorFree`
     of the element type (an auto-param `decide` discharges for every
     concrete type). `Ty.dtorViews` counts a `Vec D`, so `Entry.arm` arms
     its binding when the elements hold views. `StmtT.letd` binds at a type
     `T` given by `DtorBind f t E.ty T` (`made`, `moved`; `RhsOut.retypeB`).
     Preservation of `scopeDEmpty` is proved; that of the two drain steps
     is by contradiction, since no frame binds a `Vec D` yet.
   - **Left: the drain's typing.** Add `DtorBind.vec : DtorBind f t (.vec
     (.dtor f t)) (.vec (.dtor f t))` and let `StmtT.scopeD` take `E.ty =
     .dtor f t ∨ E.ty = .vec (.dtor f t)`; then the two drain cases of
     preservation are real proofs. Two obligations found while writing
     them:
     - *Live at its end.* `RhsT.popFront` asks `x` live, and a `Vec D`
       binding killed by an ended source of what its elements view is
       exactly what its destructors must not read (a drop is a use). So the
       vec case of `StmtT.letd` and of `StmtT.scopeD` needs `∃ E, Δ x =
       some E ∧ E.live = true` of the frame's output (as `withLock`'s
       `hlive`); a weaker context at the end (`skip_inv`, `Weaker`) then
       gives it at the drain step. Reviving `x` instead (`Entry.revive`,
       as `scopeDEnd` does) drops `dbind`, which the frame's typing needs
       to stay a `scopeD`.
     - *Armed at a panic.* `unwindCtx` revives the frame's binding with
       `dbind := false`; the panic drain types `.scopeD x f .skip` in the
       unwound context, whose premise asks `dbind` when the elements hold
       views. The unwind must keep the binding armed for a `Vec D` frame
       (a variant of `unwindCtx_x` and `MInv.unwind`).
     The drain step's preservation then: `Γ' = Γ`; the body `letd m.nv f
     (.popFront x) .skip` typed by `StmtT.letd` (`DtorBind.moved`: `popE`
     of a `.dtor f t` element has that type; `HeldUp.refl`); its output
     `exitScope m.nv (setE Γ1 m.nv _)` is `Γ1 = kill .drop hv x Γ`
     (`exitScope_setE_fresh`), and `exitScope x (kill .drop hv x Γ) =
     exitScope x Γ` since `.replace` kills every kind `.drop` does; the
     rest as `scopeDEnd`'s case.
   - **The plan, with the four open questions answered:**
     1. *Where a `Vec D` is ok.* Only as a binding's own type. **Built
        (milestone 2a):** rather than a separate `Ty.okB` threaded through
        `tyok`'s 63 uses, `Ty.ok` itself admits `vec D` (`D.hasDtor`, `Ty.vecD`)
        and every composite constructor asks `!vecD` of its parts, so a
        field, a payload, a view's element, a channel, a lock, an `Arc`, a
        cell or a `Vec` of a `Vec D` stays refused; `RhsT.pair` / `inl` /
        `inr` / `arcNew` / `lockNew` / `cellNew` and `StmtT.lockedSet` ask it
        of what moves in. A struct's glue lends `self` and cannot pop a
        field, and a channel's queue is swept with its block, running no
        code (3d). No binder binds a `Vec D` until item 3 lands.
     2. *`withElem` of a `Vec D`'s element.* Refused in this cut: the
        check-out is an owned binding of a destructor type that is no
        `letd`'s, so `withElem` asks its element type `dtorFree`. Lifting
        it needs `x ∉ s.assigns` (as `letd`'s `hna`) and a `scopeD`-style
        end for the check-out.
     3. *The binder and the frame.* `letd x f r s`, where `r`'s type is
        `.vec (.dtor f u)` and `f` is the element's destructor.
        `StmtT.letd` and `StmtT.scopeD` take `E.ty = .dtor f t ∨ E.ty =
        .vec (.dtor f t)`. `scopeD x f .skip` steps by the value:
        - a non-empty node becomes `scopeD x f (letd m.nv f (.popFront x)
          .skip)`, with `nv + 1`. This is a statement rewrite: the memory
          moves in `letd`'s step (`EvalR.popFront`, `rhs_popFront`), and
          the element's own `scopeD` runs its destructor
          (`scopeD_end_runs_dtor`);
        - an empty node becomes `scope x .skip`;
        - `scopeDEnd` and `scopeDP` take only a value that is no node;
        - a panic with `x` owning a node becomes `.ok m1 (.seq (.scopeD x f
          .skip) .panic)`, which drains, then raises again.
        Preservation of the drain step is a typing lemma: `StmtT` of the
        rewritten body, from `MInv`, which gives `RhsT.popFront`'s
        premises for `x`. The panic step's proof is `scopeDP`'s. Each of
        the three new steps needs its case in Progress, StepFrame and A3's
        lifting files (Lift, Fresh, BorFree, Keep, Restrict, Owned, Cell),
        where `scopeDEnd` has one.
     4. *A `Vec D` as a `sink` or `inout` parameter, or a result.*
        Since milestone 2a `Ty.ok` admits the type, so `FnOK` alone no
        longer refuses it: a `sink` one or a result is still handed to a
        `letd` (`movedFirst`, `DtorParamsOK`), which item 3 must keep
        refusing at a `Vec D` type, and an `inout` one is reachable only
        from a caller binding of that type. Item 3 must refuse `inout`
        `Vec D` parameters explicitly (or give them the drain's
        obligations), so a `Vec D` lives and drains in one frame.
     `truncate`, `clear`, `set`, `free` and `edit` of a `Vec D` must stay
     refused when item 3 lands: they need a `dtorFree` premise on their
     element type then (today no binding of a `Vec D` exists, so none is
     needed yet), since they drop elements with no code. A program pops them into `letd`s (`pop` and
     `popFront` give an owned `.dtor f u`, which `movedFirst` hands to a
     `letd`), or lets the binding end.
3. **A2-drop.3c: environments.** A closure's or a trait object's
   environment holding a destructor value: `Ty.fn ms q` gains what the
   environment's drop runs (as `q` records where it may cross), and a
   package's drop is `dropCode` of its environment's type.
4. **A2-drop.3d: shared blocks (A3).** An `Arc`, lock or channel payload
   with a destructor: the thread whose step drops the last share runs it
   (the sweep becomes a step of that thread that runs `dropCode` on the
   payload), and the race clause covers the destructor's reads.

After 3d, `CLAIM.md` lists no destructor exception.

## Done when

All three hold: the first two since A2-drop.1 (Agora #221), the third
since A2-drop.2 (Agora #241).

- `check.sh` passes, with `memory_safe`, `no_leak_end` and
  `no_leak_panic` over `Ty.dtor` / `scopeD`, standard axioms only;
- `CLAIM.md`'s *Destructors* section moves from "outside the calculus" to
  the proof;
- `RULES.md` records #224's rule, as an extension that rejects more,
  with the `DtorSafe` row.
