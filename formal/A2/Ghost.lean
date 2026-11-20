import A2.Region

/-! A2 — AGORA-937: the instrumented semantics.

A ghost store sits beside the memory. It is written only where a call binds
its parameters: each parameter's region cell, at the callee frame's index
`m.nv + fn.nvars + i` (above every binding the body may name, FnOK), gets the
snapshot of what the argument's value points into (`Val.regionSnap`). The
memory steps exactly as `Step` says, and nothing in a step reads the ghost
store: an instrumented step is a step of `Step`, and every step of `Step`
has an instrumented twin (`stepI_of_step`, `step_of_stepI`, `stepI_fst`).
So a fact proved of instrumented runs is a fact of `Step`'s, and `Step`, `Mem`
and every theorem stated over them are as they were. -/

namespace A2

/-- The ghost store: a region cell per index. -/
abbrev Ghost := Var → Option Val

/-- The call a step of `s` makes, where `Step` finds its redex: through a
    sequence's first statement and the body of a scope, a borrow, a frozen
    frame, a recover frame, a destructor scope and a lock scope. -/
def Stmt.callRedex : Stmt → Option (Var × Nat × List Var)
  | .letcall x f args _ => some (x, f, args)
  | .seq a _ => a.callRedex
  | .scope _ s => s.callRedex
  | .rbind _ s => s.callRedex
  | .frozen _ s => s.callRedex
  | .catchR _ _ s => s.callRedex
  | .scopeD _ _ s => s.callRedex
  | .scopeL _ _ _ s => s.callRedex
  | _ => none

/-- The snapshot of argument `a`'s value: what it points into. -/
def argSnap (m : Mem) (a : Var) : Option Val :=
  (m.st a).bind fun sl => sl.val.map Val.regionSnap

/-- The region cells a call to `fn` with `args` writes, from frame base `b`. -/
def ghostCall (fn : Fn) (args : List Var) (b : Nat) (m : Mem) (g : Ghost) : Ghost := fun v =>
  if b + fn.nvars ≤ v ∧ v < b + fn.nvars + fn.params.length then argSnap m (args.getD (v - (b + fn.nvars)) 0)
  else g v

/-- What a step of `s` from `m` does to the ghost store: a call writes its
    region cells, from the frame base `m.nv` it binds the callee at; any
    other step leaves the store as it is. A function of the program, the
    memory, the statement and the store only. -/
def ghostUpd (P : Prog) (m : Mem) (s : Stmt) (g : Ghost) : Ghost :=
  match s.callRedex with
  | some (_, f, args) => match P[f]? with
    | some fn => ghostCall fn args m.nv m g
    | none => g
  | none => g

/-- An instrumented step: a step of `Step`, with the ghost store updated as
    the step's call says. -/
def StepI (P : Prog) (mg : Mem × Ghost) (s : Stmt) (r : Res) (g' : Ghost) : Prop :=
  Step P mg.1 s r ∧ g' = ghostUpd P mg.1 s mg.2

/-- Every step has an instrumented twin (AGORA-937, condition 1). -/
theorem stepI_of_step {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) (g : Ghost) :
    StepI P (m, g) s r (ghostUpd P m s g) := ⟨h, rfl⟩

/-- ... and every instrumented step is a step. -/
theorem step_of_stepI {P : Prog} {m : Mem} {g g' : Ghost} {s : Stmt} {r : Res}
    (h : StepI P (m, g) s r g') : Step P m s r := h.1

/-- The memory side of an instrumented step does not read the ghost store:
    the same step is taken from any store. -/
theorem stepI_fst {P : Prog} {m : Mem} {g g₁ g' : Ghost} {s : Stmt} {r : Res}
    (h : StepI P (m, g) s r g') : StepI P (m, g₁) s r (ghostUpd P m s g₁) := ⟨h.1, rfl⟩

/-- A call writes its region cells before the body runs: a cell of the new
    frame never holds what an earlier call at the same base left there
    (AGORA-937, condition 4). -/
theorem ghostUpd_call_cell {P : Prog} {m : Mem} {s : Stmt} {g : Ghost} {x : Var} {f : Nat}
    {args : List Var} {fn : Fn} (hr : s.callRedex = some (x, f, args)) (hf : P[f]? = some fn)
    {i : Nat} (hi : i < fn.params.length) :
    ghostUpd P m s g (m.nv + fn.nvars + i) = argSnap m (args.getD i 0) := by
  have hc : m.nv + fn.nvars ≤ m.nv + fn.nvars + i ∧ m.nv + fn.nvars + i < m.nv + fn.nvars + fn.params.length :=
    ⟨Nat.le_add_right _ _, Nat.add_lt_add_left hi _⟩
  simp only [ghostUpd, hr, hf, ghostCall, hc, and_self, ↓reduceIte, Nat.add_sub_cancel_left]

/-- A step that makes no call leaves the ghost store as it is. -/
theorem ghostUpd_none {P : Prog} {m : Mem} {s : Stmt} {g : Ghost} (hr : s.callRedex = none) :
    ghostUpd P m s g = g := by
  simp [ghostUpd, hr]

end A2
