module

public import C.A2Prog

@[expose] public section

/-! A result `!T E` as the translator writes it (AGORA-1044): `sum E T`,
its error (`F`) the first variant, a match `.ite (.isl r)` whose arms take
the payloads with `.getl` / `.getr` (`docs/dev/TRANSLATION_TRUST.md`, the
encodings). The verified checker types such a function, and a view of a
result's payload ends when the result moves: it is refused when read after
the move, accepted when read before. Witnesses only: no certificate imports
this file. -/

namespace C.ResultWitness

open A2

/-- `@ code !v IoErr r → i { ?? r { T _ → { ^ 0 } F _ → { ^ 1 } } }`, as the
    translator writes it: the result lent (`.inp`), `IoErr` (an enum of
    numbers) an integer, `v` an integer. -/
def code : Fn :=
  { params := [(.inp, (.sum .int .int))], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := (.block (.letv 2 (.expr .any) (.ite (.isl 0)
      (.seq (.letv 4 (.getl 0) (.assign 1 (.expr .any))) (.exit 0))
      (.seq (.letv 3 (.getr 0) (.assign 1 (.expr .any))) (.exit 0))))), nvars := 6 }

theorem code_ok : fnOK2B [code] 0 code = true := by decide +kernel

/-- The match on a result is well typed (A2's `FnOK`). -/
theorem code_typed : FnOK [code] code := fnOK2B_sound rfl code_ok

/-- A result owned (`.sink`) whose value is a `Vec`: its payload lent
    (`.getr`), a view of that read, and only then the result moved. -/
def viewThenMove : Fn :=
  { params := [(.sink, (.sum .int (.vec .int)))], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := (.block (.ite (.isl 0) (.assign 1 (.expr .any))
      (.letv 2 (.getr 0) (.letv 4 (.view 2) (.letv 3 (.var 0) (.assign 1 (.expr .any))))))), nvars := 6 }

/-- ... and the same with the result moved before the view is taken: the
    payload lent out of it is gone. -/
def moveThenView : Fn :=
  { params := [(.sink, (.sum .int (.vec .int)))], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := (.block (.ite (.isl 0) (.assign 1 (.expr .any))
      (.letv 2 (.getr 0) (.letv 3 (.var 0) (.letv 4 (.view 2) (.assign 1 (.expr .any))))))), nvars := 6 }

theorem viewThenMove_ok : fnOK2B [viewThenMove] 0 viewThenMove = true := by decide +kernel

theorem viewThenMove_typed : FnOK [viewThenMove] viewThenMove := fnOK2B_sound rfl viewThenMove_ok

/-- The checker refuses a read of a result's payload after the result moved. -/
theorem moveThenView_refused : fnOK2B [moveThenView] 0 moveThenView = false := by decide +kernel

end C.ResultWitness
