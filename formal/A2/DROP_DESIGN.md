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
  runs the destructor at its end and on a panic's unwind. (A check-out
  binding is of no such type: `withLock` and `withCell` check out a
  payload, which owns no destructor value since A2-drop.3d, and
  `withElem` asks an element type that owns none, A2-drop.3b.) `letv` refuses
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
  …)`, and `f` is its glue. **Agora #616: the glue is a function that
  takes the struct owned and takes it apart** (`GlueOK`: one `sink`
  parameter of the type `Ty.dtor f (prod a b)`, the body an `unpair` of
  it), and no destructor that takes such a struct lent is accepted
  (`DropFnOK`). No new step and no new run-time form: the frame's end
  calls `f` on `x` as before (`Step.scopeDEnd` / `scopeDP`), and the call
  moves `x` in because the parameter is `sink` (`glueCall_typed`); in the
  glue, `unpair`'s own rule hands every field that holds a destructor
  value to a `letd` first thing (`hdx` / `hdz`, `A2.Dtor.glue_takes_apart`),
  so each has a frame of its own before anything can panic, and a panic
  in one field's destructor unwinds through the others' frames. `unpair`
  takes a value of such a type apart anywhere (its rule's `h5`): that is
  what its drop does. Nesting the `letd`s as `letd z' (var z) (letd y'
  (var x) skip)` runs the fields' destructors in field order, nurlc's.
  In this cut the struct holds no views (the moved-in value must hold
  nothing). **A struct (or an enum, Agora #632) with a `% Drop` of its own
  beside a destructor field or payload** (`ImplGlueOK P f t h i`, `h` the
  struct's `GlueOK` or the enum's `EnumGlueOK` function) needs no new step either: its glue `f`
  takes it owned and its body is `letd w h (var 0) (letcall r i [w]
  (assign res …))`: the struct rebound under the fields' glue `h`, then
  the impl `i` (a `DtorOK` function on `Ty.dtor h t`) on it lent. The
  impl's panic unwinds to `w`'s frame, which takes the struct apart; so
  does the frame's end. `LetdTy` lets a `letd` bind a value of another
  destructor type, and `LetdFn` (the `letd` rule's premise in `DropFnOK`'s
  place) allows it only in this shape: from `Ty.dtor g t` to `Ty.dtor f t`
  where `ImplGlueOK P g t f i` and the scope starts with `i`'s call on
  the new binding. The shape is checked wherever it is written, so it
  needs no knowledge of which function's body it is in, and it survives a
  call's renaming (`StmtT.rename`'s `letd` case). `unpair` refuses such a
  struct (read off its `h5`, which asks `GlueOK`; no witness of the
  refusal): taking it apart by hand would skip the impl.
  Deeper nesting: a struct or an enum holding such a struct, with no
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
  only a struct, an enum or (Agora #609) a closure of the dropping class. Since A2-drop.3b `free` asks elements that own
  no destructor value (`t.dtorFree`), so what it releases runs no
  destructor (no share's payload and no environment of a closure that
  does not drop holds a destructor value since A2-drop.3c and 3d).
- **A `Vec` of destructor values is drained** (A2-drop.3b). `letd x f r s`
  binds one too (`LetdTy`: `r`'s type is `vec (dtor f u)`, `u` holding no
  views), and its `scopeD x f` frame's end takes the elements out in index
  order, each to a `letd` binding of its own, whose frame runs its
  destructor (`Step.scopeDDrain`, `scopeDEmpty`); a panic drains what is
  left and goes on (`Step.scopeDPDrain`). The rules that drop or check out
  elements with no code (`vec_truncate`, `vec_clear`, `vec_set`,
  `vec_free`, `withElem`) refuse one; `vec_free`, `vec_clear` and
  `vec_truncate` of one are written as code the calculus types
  (`A2/DropCode.lean`).
- **Taking a destructor value apart is refused**, unless its destructor is
  a struct's glue (Agora #616): `unpair` asks `E.ty = .prod a b`, or
  `.dtor f (.prod a b)` with `GlueOK P f`, and `takel` / `taker` `E.ty =
  .sum a b`; so is a field
  written in place (`unpair` and `assign`). Taking it apart would bypass the
  destructor. Its fields and payloads are lent through the type instead,
  and an `inout` parameter of such a type is neither assigned nor taken
  apart. As Rust, which refuses a move out of a type
  with a `Drop` impl of its own but lets a program take apart a struct
  whose fields alone have one: a struct whose destructor is its glue
  (`GlueOK`, Agora #616) is taken apart by `unpair`.

- **A call's owned result of a destructor type is a destructor frame's from
  the start** (Agora #611). The call's inside is `resFrame fn r …`:
  `scopeD r g …` when the function's owned result type is `dtor g t` or
  `vec (dtor g t)` (drained on a panic, `Step.scopeDPDrain`), a plain
  `scope r …` otherwise. The frame is never armed: such a result holds no
  views, so the frame's `dbind` premise is vacuous. A panic in the callee after it has set its
  result stops at the frame, which runs `g` on it (`Step.scopeDP`); on the
  normal path the result has moved to the caller's binding
  (`Step.scopeDMoved`). `FnOK` asks an owned result that holds a destructor
  value to be of a destructor type itself, or a `Vec` of such values, with
  no views and no closure, whose function is a `DtorOK` destructor. The frame's typing
  (`CallH.typedIn_of`) types the call's inside against the call's final
  context with the moved-out result slot added, whose well-formedness is
  the final context's, and gets what the frame keeps of the bindings
  outside it (`KeepOut`) from source typing for the body (`SrcRel`) and
  from the parameters' frames (`exitsP_keepOut`).

Refused rather than released since A2-drop.3b (stricter than nurlc, which
types them and drops a `Vec`'s elements in index order, each running its
destructor): a `Vec` of destructor values as an element or a shared payload
(`Ty.ok`): a `Vec (Vec D)`, a channel of `D` (its queue is a `Vec`),
`Locked (Vec D)`, `Arc (Vec D)`, a cell of a `Vec D` (a struct's field or
an enum's payload is typed since Agora #607: glue hands it to a `letd`,
which drains it); one whose elements hold views
(`LetdTy`); and `vec_set` over an element and `withElem` (`vec_free`,
`vec_clear` and `vec_truncate` are typed code, `A2/DropCode.lean`). And, since A2-drop.3c and 3d: a share whose payload owns a destructor
value (`Ty.ok`), and a trait object whose box holds one (a closure whose
environment holds one is of the class `dropd`, dropped by its glue, Agora #609). The result moved from its slot into a local
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
and `assign` of a destructor value refused instead of `dropCode`. Of
A2-drop.3b, a `Vec` of destructor values is mechanized as a binding's own
type and as a field or a payload (the drain, Agora #542, #607; *Staging* below says what is left). Of 3c, the refusal
(Agora #543) and the environment's drop as code (Agora #609) are
mechanized; a block's payload's drop as code is designed here; not mechanized. Until they are, `CLAIM.md`'s
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
| a struct field, at the struct's drop | the field's destructor, inside the struct's glue | the glue takes the struct apart, the field in a `letd` frame (Agora #616) |
| a `Vec` element: `vec_pop` dropped, `truncate`, `clear`, `vec_set` over it, the Vec freed | each element's destructor | the drain at the end of a binding's own `Vec` (A2-drop.3b); free, clear and truncate as code (`A2/DropCode.lean`), `vec_set` refused; a popped element is a `letd`'s |
| an enum or option payload | the payload's destructor | the enum's glue moves the payload out to a `letd` frame (Agora #632) |
| a closure's or a trait object's environment | the captures' destructors | the closure's glue calls its drop method, whose code takes the environment owned and binds it under `letd`s (Agora #609, `ClosureGlueOK`, `Step.callcD`); it is called lent, through its binding or a borrow of the destructor type (Agora #651); a method that changes the environment is refused for the class |
| a panic's unwind through any of these | the journal runs each, once | `scopeP` frees in one step, except at `scopeD` |
| an `Arc` / lock block's payload when its last share goes (A3) | on the thread that drops the last share | refused: no payload owns a destructor value (A2-drop.3d, `Ty.ok`) |

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
   `free` takes only a `Vec`. Not yet then: elements, payloads inside
   containers, environments, blocks, check-out bindings (each settled by
   the cuts below), and a result set before a panic in its callee (the
   result's frame, Agora #611).
2. **A2-drop.3b: containers** (done for a binding's own `Vec`, Agora #542,
   and for one in a struct's field or an enum's payload, Agora #607).
   - Done: `Ty.holdsDtor` is deep, so a struct, an enum or an option
     holding a destructor value at any depth is bound by `letd` with its
     glue: a typed `letv`'s owned value is free of one
     (`A2.Dtor.letv_owned_dtor_free`; `A2.Dtor.holdsDtor_deep` unfolds the
     definition). What the deepening adds is a destructor value two levels
     down, under a struct of no destructor type: `sum (prod DT int) int`,
     refused by `letv` (`A2.DtorWitness.main4_letv_refused`) and bound by
     `letd` with its glue (`A2.DtorWitness.main4_safe`). An option of a
     destructor value (`A2.DtorWitness.main3_safe`) is a further witness,
     not a new capability: 3a's one-level rule sent it to `letd` too. In
     that first milestone a `Vec` of destructor values was refused
     outright (`Ty.ok` asked a `Vec`'s element type to hold none); since
     milestones 2a and 2b it is a binding's own type, drained (below), since
     Agora #607 also a struct's field or an enum's payload (handed to a
     `letd` by the glue), and the rules that release elements with no code
     ask `dtorFree` of their own `Vec`. A share's payload and a view are free of
     one by definition (3d; a view owns nothing).
   - **Built (Agora #542, part 2's first milestone): the drain's step.**
     `vec_remove y 0` is `Rhs.remove y (.lit 0)` (`Rhs.popFront` until Agora #607): element 0 moves out, typed as
     `vec_pop` (`RhsT.remove`), `EvalR.remove` / `removeOOB`.
     Its preservation is a `vec_pop` of element 0 moved to the end
     (`A2.rhs_remove`, from `MInv.perm` and `rhs_pop`; the permutation
     lemmas moved from `A2/Elem.lean` into `A2/Rhs.lean` so that
     `rhs_pres` can use them). nurlc drops a `Vec`'s elements in index
     order (`nurl__vec_drop_elems`, `i = 0 .. len`), so the drain takes
     element 0 each round, not the last one.
   - **Built (milestone 2b): the drain itself.** How the four open
     questions were settled:
     1. *Where a `Vec D` is ok.* At first only as a binding's own type
        (milestone 2a; a field and a payload since Agora #607, below): rather than a separate `Ty.okB` threaded through `tyok`'s 63
        uses, `Ty.ok` itself admits `vec D` (`D.hasDtor`, `Ty.vecD`) and
        every composite constructor asks `!vecD` of its parts, so a field,
        a payload, a view's element, a channel, a lock, an `Arc`, a cell or
        a `Vec` of a `Vec D` stays refused; `RhsT.pair` / `inl` / `inr` /
        `arcNew` / `lockNew` / `cellNew` and `StmtT.lockedSet` ask it of
        what moves in. **Agora #607:** a struct's field and an enum's
        payload are lifted (`Ty.ok`'s `prod` / `sum` cases and `RhsT.pair`
        / `inl` / `inr` no longer ask `!vecD`): the struct holds a
        destructor value, so its destructor is its glue (#616, #632),
        which hands the field to a `letd` at the `Vec`'s own type
        (`LetdTy`'s second case), and that frame drains it;
        and a channel's queue is swept with its block, running no code (3d).
     2. *`withElem` of a `Vec D`'s element.* Refused: the check-out is an
        owned binding of a destructor type that is no `letd`'s, so
        `StmtT.withElem` asks its element type `dtorFree`
        (`A2.Dtor.withElem_dtor_free`). Lifting it needs `x ∉ s.assigns`
        (as `letd`'s `hna`) and a `scopeD`-style end for the check-out.
     3. *The binder and the frame.* `letd x f r s`, where `r`'s type is
        `.vec (.dtor f u)` and `f` is the element's destructor: `StmtT.letd`
        takes `LetdTy f u E.ty τ` (the destructor type as before, or the
        `Vec`, its elements holding no views) and binds at `τ`;
        `StmtT.scopeD` takes `ScopeDTy f u E.ty`. One run-time form serves
        both: `scopeD x f .skip` steps by the value `x` owns (`Val.isNode`),
        - a non-empty node: `Step.scopeDDrain`, to `scopeD x f (letd m.nv f
          (.remove x (.lit 0)) .skip)` with `nv + 1`. This is a statement rewrite:
          the memory moves in `letd`'s step (`EvalR.remove`,
          `rhs_remove`), and the element's own `scopeD` runs its
          destructor (`scopeD_end_runs_dtor`);
        - an empty node: `Step.scopeDEmpty`, to `scope x .skip`;
        - `scopeDEnd` and `scopeDP` take only a value that is no node;
        - a panic with `x` owning a node: `Step.scopeDPDrain`, to `.ok m1
          (.seq (.scopeD x f .skip) .panic)`, which drains, then raises
          again. A panic inside an element's destructor reaches the same
          step through the drain's own frame, so the rest still drains.
          (nurlc's runtime does not do this yet: its element loop is left
          by the panic, Agora #608.)
        Preservation of the drain step is a typing lemma (`preserve`'s
        `scopeDDrain` case): the binding is revived as at `scopeDEnd`
        (`MInv.revive`), `RhsT.remove`'s premises for `x` follow from the
        frame's `EndOK`, and the frame's exit context is unchanged
        (`exitScope_kill`). The panic step's proof is `scopeDP`'s, the
        re-raised panic's typing shared by both (hoisted in `preserve`).
        Which step a typed frame takes follows from its binding's type
        (`ScopeDTy.shape`): a `dtor f u` value is a struct's or an enum's,
        never a node. Each new step has its case in Progress, StepFrame,
        Codes and A3's lifting files (Lift, Fresh, BorFree, Keep, Restrict,
        Owned, Cell).
     4. *A `Vec D` as a `sink` or `inout` parameter, or a result.* Typed
        as a destructor value is: `Ty.holdsDtor` is true of it, so a `sink`
        one or a result is handed to a `letd` first thing (`movedFirst`,
        `DtorParamsOK`), which now binds it at its own type, and an `inout`
        one is assigned nothing; its callee may push to it and pop from it
        (each popped element to a `letd`), and may not drop elements in
        place.
     The rules for `truncate`, `clear`, `set`, `free` refuse a `Vec D`
     (`StmtT.free` and `StmtT.editB` / `editBV` ask `dtorFree` of the
     elements they drop, `Edit.drops`; `A2.Dtor.free_dtor_free`,
     `edit_drops_dtor_free`). A program pops the elements into `letd`s
     (`pop` and `remove` give an owned `.dtor f u`, which `movedFirst`
     hands to a `letd`), or lets the binding end; `vec_free`,
     `vec_clear` and `vec_truncate` are such code (`A2/DropCode.lean`).
   - **Left** (stricter than nurlc; `CLAIM.md` lists them):
     - *elements that hold views.* A2-drop.2's rule (a binding that runs a
       destructor gains no view) would let nothing be pushed into such a
       `Vec`; it needs the age order nurlc's finer rule has.
     - *a `Vec D` as an element or a block's payload* (a `Vec` of them, a
       channel, a lock, an `Arc`, a cell). A field or a payload is built
       (Agora #607, above); a `Vec` of `Vec D`s needs the drain to bind an
       element at a `Vec` type; a block's payload is 3d's.
     - **Built** (Agora #607, `A2/DropCode.lean`): the in-place drops
       need no new step, they are code the calculus types: `withElem v i
       x s` of a destructor element is `letd x f (vec_remove v i) (s ;
       insert v i x)` (`withElemD_typed`, witness `mainElem_safe`): the
       check-out's frame is a `letd`'s, so a panic in `s` runs the
       element's destructor, and the give-back leaves it moved out
       (`scopeDMoved`);
       `vec_free` is the `Vec` moved into a `letd` that ends at once
       (`vecFreeD_typed`), `vec_clear` a loop of `vec_remove x 0`s into a
       `letd` (`vecClearD_typed`), `vec_truncate x n` a loop of
       `vec_remove x n`s (`vecTruncD_typed`, in index order as nurlc's),
       and `vec_set x i z` a `vec_remove x i` into a `letd` that ends at
       once followed by `insert x i z` (`vecSetD_typed`; witness
       `mainSet_safe`). The drain's `popFront` was generalised for it to
       `Rhs.remove y i` (`vec_remove`, bounds-checked: `EvalR.remove` /
       `removeOOB`), whose preservation is a `vec_pop` of element `i`
       moved to the end (`A2.rhs_remove`, `perm_eraseIdx_append`).
3. **A2-drop.3c: environments** (the refusal, Agora #543; the drop as code, Agora #609).
   - **Built: the refusal.** `Cross.Fits` asks an environment type to hold
     no destructor value, of every class but `dropd` (Agora #609: the
     class of a closure that is a destructor value itself), so
     `RhsT.pack` types no such
     literal (`A2.Dtor.pack_env_dtor_free`) and `WFv.pkg` carries it for
     every package in memory: in an owner's tree
     (`A2.Dtor.pkgs_env_dtor_free`) and in a block's payload
     (`A2.Dtor.blk_pkgs_env_dtor_free`). As 3b's first
     milestone refused a `Vec` of destructor values before the drain was
     built, this closes the gap (a destructor silently not run) at the
     price of an item in `CLAIM.md`'s stricter-than-nurlc list.
   - **Built: the environment's drop as code** (Agora #609). Not the plan
     this section had (a package unwrapped at the frame's end: `Ty.fn`
     does not name its environment's type, so the frame cannot type what
     it unwraps); the drop is a METHOD of the package:
     - *The type.* A closure whose environment holds destructor values is
       of the class `dropd` (`Cross.Fits`), a destructor value itself
       (`Ty.holdsDtor`), bound by `letd` at `Ty.dtor f (.fn ms dropd)`.
     - *The glue.* `f` (`ClosureGlueOK`) takes the closure owned and calls
       its drop method, `callcE r 0 j []`, whose interface takes the
       receiver owned (`StmtT.callcE`'s second case: a consuming call,
       typed for any owned, live closure of the class that holds nothing;
       the glue's parameter is one).
     - *The step.* `Step.callcD`: the environment moves out of the package
       into a fresh binding, which the method's code takes as its `sink`
       receiver in an ordinary call (`handStmtD`); nothing goes back. The
       code hands what it took on first thing, to a `letd` or taken apart,
       or is the glue of the environment's type (`A2.Dtor.drop_method_code`,
       from `DtorParamsOK`): a frame per destructor value.
     - *The proof.* `handD_typed`, `handCaseD` (`A2/EnvHand.lean`); the
       frame's end is `glueCall_typed` unchanged. Witness:
       `A2/ClosureDropWitness.lean`.
     - *Calling it* (Agora #651): `StmtT.callc` reads the closure type
       through the binding's destructor type and the interface takes the
       receiver at the binding's type; nothing else changes (the code is
       lent the environment). Witness `main2`.
     - *Left:* a method that changes the environment (an `inout`
       receiver: the package rebuilt after the hand-over would be assigned
       over a destructor binding), a trait object of the class
       (`TraitAt` refuses a `sink` receiver), a run theorem for the witness, a
       closure of the class that holds views or captures by name, one that
       crosses to a thread, and a witness with such a package inside a
       container and a method that reads or lends its environment.
4. **A2-drop.3d: shared blocks (A3)** (first cut done, Agora #544).
   - **Built: the refusal.** `Ty.ok` asks an `Arc`'s, a lock's and a
     cell's payload type to own no destructor value (`dtorFree`), and
     `RhsT.arcNew` / `lockNew` / `cellNew` (and `StmtT.lockedSet`) ask it
     of what moves in. The invariant carries it for every block
     (`MInv.blocks`, `A2.Dtor.blocks_dtor_free`), so the sweep releases no
     destructor value, and a check-out binding (`withLock`, `withCell`) is
     of a type that holds none (`A2.Dtor.shares_dtor_free`): 3a's
     check-out gap is closed with it. Stricter than nurlc (`CLAIM.md`).
   - **Built: the step, with nothing to fire it yet** (Agora #610, a
     preparation that changes no typed run). A block kind `dead` (`BKind`:
     an orphan whose payload awaits its destructor; no one reads it, it
     owns its payload and keeps what the payload reaches, as a lock block
     does) and the step `Step.reap`: from any source statement `r` (the
     thread's redex, under any frames by the congruence rules), a `dead`
     block's payload moves to a fresh binding in a destructor frame put
     before `r`, `seq (scopeD z f skip) r`, and the block stays, empty,
     for the sweep to remove. The invariant says what the step needs of
     a `dead` block (`MInv.blocks`: of a destructor type that holds no
     closure, the payload a well-formed value of it that holds no views;
     `MemCodes`' `DeadCodes`: the destructor is one the program checked,
     `DropFnOK`), and nothing refers to one (`Refers.not_dead`, read off
     the shares' typing: a share names an `arc` block, a view or a lock
     block). Its case of preservation is `pres_reap` (the payload is
     handed over as a lock's is checked out, `reap_pres`; the frame is
     typed as a `letd`'s at its end). **Nothing makes a block `dead`
     yet** (`Step.noDead`, `A2.no_orphan`): the sweep still removes an
     orphan, whose payload owns no destructor value (`Ty.ok`).
   - **Left: the payload's drop as code.** The thread whose step drops
     the last share runs the payload's destructor: the sweep becomes a
     step of that thread that moves the payload out to a `letd` binding
     of its own (as the drain moves an element out), whose frame runs the
     destructor; the race clause covers the destructor's reads (the
     payload is in no other thread's part once its block is unreachable).
     A check-out binding of a destructor type needs `x ∉ s.assigns` and a
     `scopeD`-style end that hands the value back instead of dropping it.
     `A3.claim` and `A3.claim_made` are re-proven over the new step.

With the result's frame (Agora #611) every value's own, outermost
destructor runs where the value is dropped. A struct's fields run theirs
in the struct's glue, a frame per field (Agora #616, above), and an
enum's payload in the enum's glue (Agora #632): `EnumGlueOK`, a function
that takes the enum owned, `ite (isl 0) sa sb`, an arm of a variant whose
payload holds a destructor value being `letd y g (takel 0) k`. `takel` /
`taker` are right-hand sides and `RhsT` has no program, so the rule
(`RhsT.takel`) takes a payload that holds a destructor value out of an
enum under any destructor type, and the statements that can bind such
an owned value ask the gate (`TakeOK`): `letd` (beside `LetdFn`) and
`assign` (a function's result slot may be assigned such a value once);
`letv` refuses an owned value that holds a destructor value. The gate:
the enum's destructor is its glue. `ExprT.isl` reads the tag through the type. The
arm that takes nothing leaves the parameter live; the two arms are joined
by `StmtT.sub` (a moved entry is weaker than a live one). And the stricter-than-nurlc list (a spawned
function's parameter that holds a destructor value among it, `SpawnOK`).


## Done when

All three hold: the first two since A2-drop.1 (Agora #221), the third
since A2-drop.2 (Agora #241).

- `check.sh` passes, with `memory_safe`, `no_leak_end` and
  `no_leak_panic` over `Ty.dtor` / `scopeD`, standard axioms only;
- `CLAIM.md`'s *Destructors* section moves from "outside the calculus" to
  the proof;
- `RULES.md` records #224's rule, as an extension that rejects more,
  with the `DtorSafe` row.
