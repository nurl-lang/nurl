import C.A2Call
import C.Join

/-!
# AGORA-988 witness: re-pushing a slice keeps one dependency

github#2242's review: `base : Vec int` (slot 0) and `w : Vec (Slice int)`
(slot 1), a view of `base` pushed into `w`, then `w[0]` read and pushed back
into `w`, round after round. `elemE` puts what `w` holds into both the
element's path and its held, the push appends both to what `w` holds, so
the exact context triples the list every round: 3¹⁵ = 14,348,907 entries
after 15 rounds, all `⟨0, .view⟩`. The checker drops the duplicates where a
push makes them (`C.settleOutL2`, one `sub` step), so `w` holds that one
dependency once after every round. A1's checker with joins (`checkS`,
`C.settleOutL1`) does the same.
-/

namespace C

open A2

/-- One round: `w[0]` read, then pushed back into `w`. -/
def repush : Stmt := .letv 2 (.at 1 (.lit 0)) (.push 1 2)

/-- A view of `base` pushed into `w`, then `n` rounds. -/
def repushN : Nat → Stmt
  | 0 => .letv 2 (.view 0) (.push 1 2)
  | n + 1 => .seq (repushN n) repush

/-- `base` and `w`, owned and live. -/
def repushΓ : Ctx :=
  setE (setE (fun _ => none) 0 ⟨.vec .int, .own, true, [], [], false, false, false, false⟩)
    1 ⟨.vec (.slice .int), .own, true, [], [], false, false, false, false⟩

/-- After 15 rounds `w` holds one dependency: the view of `base`. -/
example : ((checkA2 [] [0, 1, 2] repushΓ [] (repushN 15)).map fun Δ => (Δ 1).map (·.held)) =
    some (some [⟨0, .view⟩]) := by decide

/-- The same in A1: the rounds, and `base` and `w` owned and live. -/
def repushN1 : Nat → A1.Stmt
  | 0 => .letv 2 (.view 0) (.push 1 2)
  | n + 1 => .seq (repushN1 n) (.letv 2 (.at 1 (.lit 0)) (.push 1 2))

def repushΓ1 : A1.Ctx :=
  A1.setE (A1.setE (fun _ => none) 0 ⟨.vec .int, .own, true, [], []⟩) 1 ⟨.vec (.slice .int), .own, true, [], []⟩

example : ((checkS [0, 1, 2] repushΓ1 [] (repushN1 15)).map fun Δ => (Δ 1).map (·.held)) =
    some (some [⟨0, .view⟩]) := by decide

end C
