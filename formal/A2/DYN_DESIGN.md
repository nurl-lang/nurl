# A2-dyn — values owned or not per call

## Status

**Covered by A2, through an encoding.** No rule of the calculus changes.
A value nurlc owns or lends per call is, in the calculus, an **owner cell**
plus a **borrow**. `A2/DynCell.lean` types the encoding with A2's own rules
and applies the crown theorems to it, on Lean's standard axioms only
(`../check.sh`):

- `pick_ok`: the per-call function meets its summary (`FnOK`);
- `main_safe`: a caller run from the empty store never gets stuck
  (`memory_safe`);
- `main_no_leak`: when the caller ends, the fresh value, if there was one,
  is freed (`no_leak_end`).

What is left is the link from nurlc to the encoding (phase C and D): the
lowering must behave as the encoded program does. Rows in
`formal/RULES.md` that rest on per-call ownership (agora #184, #185, #186,
#203, #205, #206) refer here.

## What nurlc does

A function that hands back a borrowed parameter on one path and a fresh
value on another answers **per call** whether its result is owned
(docs/MEMORY.md §7.6, *Call results*):

    @ pick String p b c → String { ^ ? c p ( mk ) }

The callee stores an ownership bit beside the result (`mem_store_hown`;
`__nc_held_ty` / `__is_hown_ty` say which types carry one), and every
consumer goes by the bit.

- Where the result is bound, handed to a call, stored, discarded, picked
  by a join's arm or matched, a fresh value is dropped or moved in, and a
  lent one is copied or left to its owner (#185).
- A `% Drop` value that cannot be copied moves out on the path that owns
  it, and is refused where it would have to be copied (#186, #203, #205).
- A raw string handed back answers the same way (`__ret_unowned`, #206).

## Why A2 cannot type the bit directly

- `Fn.resOwn : Bool`, so `resMode fn` is `.own` or `.bor` for every call.
- `StmtT.assign` pairs an owner with an owned value and a borrow with a
  borrowed one. It never gives one binding both.
- `SlotOK` ties a slot's run-time flag to its binding's mode
  (`sl.own = E.mode.ownSlot`).

The semantics would allow more. `Step.assign` hands a moved-from slot's
flag on (`EvalR.moveOwn` / `EvalR.copy`), and `DropSlot` frees under the
flag. But a binding that may own or borrow per run would also break an
assumption the invariant's proofs make. Once its root's slot holds a
borrow, that root must be a borrowed parameter whose anchors are frozen
(`Stability.lean`'s root lemmas). A mode `.dyn` is therefore a deep change
to the invariant, not a new case. The encoding avoids that change.

## The encoding

The callee gets one more parameter: the cell. It is an `inout` option the
caller owns, `none` until the callee fills it. The result is a **borrow**:

    @ pick ( inout ?String ) cell  String p  b c → String {   // lends p, cell
        ? c { ^ p }                        // lent: the cell stays none
            { : String y ( mk )
              = cell @ ?String { T y }     // fresh: it moves into the cell
              ^ ( payload cell ) }         // and the result borrows it
    }

In the calculus (`A2/DynCell.lean`) that is `ite`, `assign`, `inr` (the
move into the cell), and `getr` (the borrow of the payload). `lends` names
both `p` and the cell, and the two paths' results meet by `StmtT.sub`.

| nurlc | the encoding |
|---|---|
| the result's ownership bit | "is the caller's cell `some`?" |
| the caller drops a fresh result at its scope's end | the cell drops its payload at its scope's end (`DropSlot`) |
| a lent result is the caller's argument's | the result borrows `p` (`lends`) |
| a fresh result read by the caller | the result borrows the cell's payload (`projE`: depends on the cell) |
| a consumer moves a fresh result | `taker` on the cell (the payload moves; the borrow, which depends on the cell, ends) |
| a consumer copies a lent result | a call of the type's clone (B), as for every copy |
| the result may lend the argument, so a change to it ends the result | the result depends on `p` *and* the cell, on every path |

The last row is the conservative point, and nurlc makes it too. A per-call
result may lend its argument, so nurlc ends it when the argument changes,
whichever path the call took. The encoding's join does the same: the
result depends on both, as `ite` requires one context for both arms.

## What phase C / D has to show

nurlc's lowering of a per-call result has to simulate the encoding:

- the bit is set exactly when the cell would be `some`;
- the value is the one the borrow reaches;
- the drop at the scope's end and the move into a consumer happen under
  the bit.

`tools/fuzz/holes/` probes that link today. Its rows for #184–#206 run
clean under ASan/LSan. Phase C's certificate would name the cell
explicitly, and a checker would type the encoded program.

## What stays out

- **The copies.** A clone of the lent value is a call whose body is the
  standard library's (B).
- **Destructors as code.** A `% Drop` that runs a function and may panic
  is the next refinement (`CLAIM.md`).
- **A direct mode `.dyn`.** It would let a certificate skip the cell, at
  the price of reproving the invariant's root lemmas. It is worth doing
  only if phase C needs it.
