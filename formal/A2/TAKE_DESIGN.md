# A2-take — a take out of an `inout .replace` place (Agora #826)

## Status

**In A2, as a rule of its own** (`Rhs.take`, `RhsT.take`, `EvalR.take`),
proven in preservation, progress and no-leak on Lean's standard axioms
only (`../check.sh`). `A2/TakeWitness.lean` types a callee that takes its
`inout` parameter and a caller that reads its argument after the call,
and applies the crown theorems to the caller:

- `g_ok`: the callee meets its summary (`FnOK`);
- `main_safe`: a caller run from the empty store never gets stuck
  (`memory_safe`);
- `main_no_leak`: when the caller ends, the String the callee took and the
  empty one it left are both freed (`no_leak_end`).

## What nurlc does

A callee may hand its `inout` parameter `p` of a handle type (a String, a
Vec, a library handle) on to a taker, by name (`( eat p )`, Agora #778)
or as the arm of a join that selects it (`( eat ? c p ( mk ) )`). nurlc
empties the caller's slot to the type's empty value on those runs, and
summarises the callee as replacing the whole parameter
(`__replaces_note`, Agora #776): every borrow and view the caller holds of
its argument ends at the call. The caller drops its binding as ever, and
may read it after the call: `( vec_len w )` reads 0.

## The rule

    @ g inout(replace) String p → i { : q (take p)  ^ 0 }

`take y` is a right-hand side. Its step (`EvalR.take`), on a slot that
owns a `Vec` `⟨true, some (.node t c d es)⟩`:

- hands the `Vec` on, owned, to the binding that takes it (as `moveOwn`);
- writes a fresh empty `Vec` of the same element type into `y`'s slot,
  at two fresh addresses, as `new` allocates one
  (`⟨true, some (.node t nid (nid + 1) [])⟩`, `nid + 2`).

`y` stays live. Its typing (`RhsT.take`):

- `y` is live, a `Vec t` whose elements hold no view, and may be replaced
  (`canDo E.mode .replace`: an owner or an `inout .replace` parameter); it
  is not lent out (`y ∉ F`) and was not made by `letd` (`E.dbind = false`,
  which a type that holds no views gives anyway, `CtxWF.view`);
- it is killed as a replace kills it (`kill .replace false y`), with
  `moveOwn`'s `NoPin Γ y` and `DtorSafe Γ .replace false y`;
- the new binding is `own` and holds what `y` held (`E.held`);
- `y`'s entry stays live, of its type and mode, and holds nothing
  (`⟨E.ty, E.mode, true, [], [], false, false⟩`).

### Why the element type holds no view

A callee's `inout` parameter is its caller's binding where the call places
it (`Rename`): the parameter's entry is lifted with what the caller's
arguments hold (`liftE`: `ownHeld true τ S.A`). For a `Vec` whose elements
hold no view that is nothing, so the entry the take leaves (holding
nothing) is the same entry on both sides of the call (`RhsT.ren`), as the
renaming lemma needs. A String is a `Vec` of bytes, and nurlc's hand-over
is of handle types; a `Vec` of views is left out, and would need the
take's entry to hold what the lift adds.

### Why it is a rule, not an encoding

A move out of `y` needs `y` to be an owner (`RhsT.moveOwn`, `E.mode =
.own`), and an `inout` parameter's slot is the caller's: a move would
leave the caller a dead binding it then drops and reads. `= y ( vec_new )`
after a move is no help either: nothing moves out of an `inout`. The take
is the two in one step, on one slot, which the replace bound allows.

## The proof

- **Preservation** (`rhs_take`, `A2/Steps.lean`): the step is `moveOwn`'s
  (`rhs_move`), then `new`'s (`rhs_new`), then the fresh `Vec` put in the
  emptied slot as `= y ( vec_new )` puts it (`assign_post`, the core of
  `step_assign`, factored out for this). What moved out stays valid where
  the fresh `Vec` now is: its addresses are older than the fresh ones, it
  holds no view, and what it holds by name is no `y` (a dead entry is held
  by name by nothing). At run time no binding is `inout` (`MInv.noInout`),
  so `y` is an owner there.
- **Progress** (`evalR_exists`): an owned slot of a `Vec` type holds a
  `Vec` node.
- **No leak** (`covers_evalR`, `A2/Leak.lean`): the moved value's
  addresses go to the new binding, as `moveOwn`'s; the fresh `Vec` is one
  new owned tree, `y`'s.
- **Calls** (`RhsT.ren`, `RhsT.absOK`, `A2/Rename.lean`): an `inout
  .replace` parameter's take is, where the call places it, its caller's
  owner's take; the replace is allowed by the parameter's bound
  (`allowed_canDo'`), so the call's summary (a replace of the parameter)
  covers it, and the caller's borrows of the argument end at the call
  (`callPostAux`).
- **A3**: a take touches no address another thread may (no `RTouch`, as a
  move and `new`): `y`'s slot is the thread's own, and the fresh addresses
  are past `nid` (`EvalR.grows`, `EvalR.restrict`, `EvalR.keep`). Every
  exhaustive match on `Rhs` / `EvalR` / `RhsT` has the case.

## What phase C / D must show

That nurlc's lowering of the hand-over is this step: the callee's taker
gets the parameter's value, and the caller's slot holds the type's empty
value after the call, on exactly the runs the callee took it.
