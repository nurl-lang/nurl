module

public import C.Caps

@[expose] public section

/-! C16's witnesses: the closure of a program's names computed in Lean
(`reachB`), and the check at a program with a call (`capsWitness`): its
closed list is accepted, a list that leaves out the callee is refused, and
`caps_runs` holds there.  Apart from `C/Caps.lean` so that a certificate,
whose Caps.lean imports `C.Caps`, loads no witness program (AGORA-1013). -/

namespace C
open A2

/-! ### The closure -/

/-- `L` with each of `xs` added once, in order (structural, so the kernel
    evaluates it). -/
def addNew : List Nat → List Nat → List Nat
  | L, [] => L
  | L, x :: xs => addNew (if x ∈ L then L else L ++ [x]) xs

/-- One round: `L` and every name of the functions of `L`. -/
def reachStep (P : Prog) (L : List Nat) : List Nat :=
  addNew L (L.flatMap fun f => match P[f]? with
    | some fn => fnNames fn
    | none => [])

/-- Insertion sort (structural, for the kernel): the list a certificate
    prints. -/
def insNat (x : Nat) : List Nat → List Nat
  | [] => [x]
  | y :: ys => if x ≤ y then x :: y :: ys else y :: insNat x ys

def sortNat : List Nat → List Nat
  | [] => []
  | x :: xs => insNat x (sortNat xs)

/-- `n` rounds from `L`. -/
def reachIter (P : Prog) : Nat → List Nat → List Nat
  | 0, L => L
  | n + 1, L => reachIter P n (reachStep P L)

/-- The closure of the entry's names: each round adds the names of the
    functions found so far, and a round that adds a function adds one of the
    program's, so `P.length + 1` rounds reach it. The certificate checks
    the result (`capsOKB`) rather than trusting this. -/
def reachB (P : Prog) (s : Stmt) : List Nat :=
  sortNat (reachIter P (P.length + 1) (addNew [] (stmtNames s)))

/-! ### A witness

The program of `C/Cert.lean`'s witness (`vec_push_len.nu`) calls nothing:
only `main` runs. And a program with a function no path calls: `main`
calls `used`, which calls nothing, and `unused` is never entered, whatever
it does. -/

theorem cert_witness_caps : capsOKB certWitness (.letcall 0 0 [] .skip) (reachB certWitness (.letcall 0 0 [] .skip)) = true := by
  decide +kernel

theorem cert_witness_reach : reachB certWitness (.letcall 0 0 [] .skip) = [0] := by decide +kernel

/-- `main` calls function 1 and stops; function 2 (say, a foreign call's
    stub) is in the program but nothing names it. -/
def capsWitness : Prog :=
  [ { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
      body := .block (.letcall 1 1 [] (.seq (.assign 0 (.expr .any)) (.exit 0))), nvars := 2 },
    { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
      body := .block (.seq (.assign 0 (.expr .any)) (.exit 0)), nvars := 1 },
    { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
      body := .block (.seq (.assign 0 (.expr .any)) (.exit 0)), nvars := 1 } ]

theorem caps_witness_reach : reachB capsWitness (.letcall 0 0 [] .skip) = [0, 1] := by decide +kernel

theorem caps_witness_ok : capsOKB capsWitness (.letcall 0 0 [] .skip) [0, 1] = true := by decide +kernel

/-- ... and a list that leaves out a function the entry's code calls is no
    claim: `main` calls function 1, so `[0]` is not closed. -/
theorem caps_witness_open : capsOKB capsWitness (.letcall 0 0 [] .skip) [0] = false := by decide +kernel

/-- Function 2 replaced by anything at all: the runs are the same. -/
theorem caps_witness_runs (fn : Fn) (nv : Nat) (r : Res) :
    Steps capsWitness (emptyMem nv) (.letcall 0 0 [] .skip) r ↔
      Steps (capsWitness.set 2 fn) (emptyMem nv) (.letcall 0 0 [] .skip) r :=
  caps_runs caps_witness_ok (fun f hf => by
    simp only [List.mem_cons, List.mem_nil_iff, or_false] at hf
    rcases hf with rfl | rfl <;> rfl) nv r

end C
