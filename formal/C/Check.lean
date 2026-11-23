import A1.Soundness

/-!
# C0: an executable checker for A1, proven sound (AGORA-970)

Phase C's goal is a small verified checker that validates the programs
nurlc accepts. (Today nurlc's core IR is translated into A2 and decided by
A2's checker, `tools/ncore/certify.sh`; a certificate nurlc emits itself is
the plan, not yet the workflow.) This file is the A1 statement checker, the
first piece, over A1's calculus. These are functions that run (`#eval`, compiled
code), not relations:

* `checkExpr Γ e` decides `ExprT`;
* `inferRhs Γ F r` computes the entry and context `RhsT` gives a
  right-hand side, or refuses;
* `checkStmt Γ F s` computes the context after a straight-line statement:
  `skip`, `seq`, `letv`, `assign`, `push`, `free` and `frozen`.

Each is proven sound. When it answers, the A1 typing judgement holds
(`checkExpr_sound`, `inferRhs_sound`, `checkStmt_sound`), so A1's
`memory_safe` applies to a program the checker accepts that also meets the
theorem's other premises (`checked_memory_safe`): the statement is source
syntax (`s.src`, which the checker's acceptance alone does not give: it
also accepts run-time forms such as `frozen`), the program is valid, and its
variables fit the initial store.

The rest of A1's statements need what a certificate adds. An `ite` or a
`while` asks for one context after both arms or around the loop, and
subsumption (`sub`) asks for a weakening. With contexts as functions, the
checker cannot compare them. The next step (C1) gives contexts a finite
form and has the certificate name the joins and the weakenings, which the
checker then compares. Calls and the run-time forms come with it.
-/

namespace C

open A1

/-- `ExprT`, decided. -/
def checkExpr (Γ : Ctx) : Expr → Bool
  | .lit _ => true
  | .var x => match Γ x with
    | some E => E.live && E.ty == .int
    | none => false
  | .add a b => checkExpr Γ a && checkExpr Γ b
  | .lt a b => checkExpr Γ a && checkExpr Γ b
  | .len x => match Γ x with
    | some E => E.live && (match E.ty with | .vec _ => true | _ => false)
    | none => false
  | .slen x => match Γ x with
    | some E => E.live && (match E.ty with | .slice _ => true | _ => false)
    | none => false

theorem checkExpr_sound {Γ : Ctx} : ∀ {e : Expr}, checkExpr Γ e = true → ExprT Γ e := by
  intro e
  induction e with
  | lit n => intro _; exact .lit
  | var x =>
    intro h
    simp only [checkExpr] at h
    split at h
    · rename_i E hE
      simp only [Bool.and_eq_true, beq_iff_eq] at h
      exact .var hE h.1 h.2
    · cases h
  | add a b iha ihb =>
    intro h; simp only [checkExpr, Bool.and_eq_true] at h; exact .add (iha h.1) (ihb h.2)
  | lt a b iha ihb =>
    intro h; simp only [checkExpr, Bool.and_eq_true] at h; exact .lt (iha h.1) (ihb h.2)
  | len x =>
    intro h
    simp only [checkExpr] at h
    split at h
    · rename_i E hE
      simp only [Bool.and_eq_true] at h
      obtain ⟨hl, ht⟩ := h
      split at ht
      · rename_i t hty; exact .len hE hl hty
      · cases ht
    · cases h
  | slen x =>
    intro h
    simp only [checkExpr] at h
    split at h
    · rename_i E hE
      simp only [Bool.and_eq_true] at h
      obtain ⟨hl, ht⟩ := h
      split at ht
      · rename_i t hty; exact .slen hE hl hty
      · cases ht
    · cases h

/-- `canDo`, decided. -/
def canDoB (m : Mode) (e : Eff) : Bool :=
  match m with
  | .own => true
  | .inout b => decide (e.le b)
  | _ => false

theorem canDoB_sound {m : Mode} {e : Eff} (h : canDoB m e = true) : canDo m e := by
  unfold canDoB at h
  split at h
  · exact Or.inl rfl
  · rename_i b; exact Or.inr ⟨b, rfl, of_decide_eq_true h⟩
  · cases h

/-- A live binding's entry. -/
def liveE (Γ : Ctx) (y : Var) : Option Entry :=
  match Γ y with
  | some E => if E.live then some E else none
  | none => none

theorem liveE_some {Γ : Ctx} {y : Var} {E : Entry} (h : liveE Γ y = some E) : Γ y = some E ∧ E.live = true := by
  unfold liveE at h
  split at h
  · rename_i E' hE
    split at h
    · rename_i hl; cases h; exact ⟨hE, hl⟩
    · cases h
  · cases h

/-- The element type of a `Vec` type, if it is one. -/
def vecElem : Ty → Option Ty
  | .vec t => some t
  | _ => none

/-- The element type of a slice type, if it is one. -/
def sliceElem : Ty → Option Ty
  | .slice t => some t
  | _ => none

theorem vecElem_some {ty t : Ty} (h : vecElem ty = some t) : ty = .vec t := by
  cases ty <;> simp [vecElem] at h; subst h; rfl

theorem sliceElem_some {ty t : Ty} (h : sliceElem ty = some t) : ty = .slice t := by
  cases ty <;> simp [sliceElem] at h; subst h; rfl

/-- `RhsT`, computed: the entry and the context after, or a refusal. -/
def inferRhs (Γ : Ctx) (F : List Var) : Rhs → Option (Entry × Ctx)
  | .expr e => if checkExpr Γ e then some (intE, Γ) else none
  | .new t => if t.ok then some (⟨.vec t, .own, true, [], []⟩, Γ) else none
  | .var y => match liveE Γ y with
    | some E => match E.mode with
      | .own => if y ∈ F then none
          else some (⟨E.ty, .own, true, [], E.held⟩, setE (kill .replace false y Γ) y { E with live := false })
      | .rootb => some (⟨E.ty, .bor, true, derive y E .self, E.held⟩, Γ)
      | .bor => some (E, Γ)
      | .inout _ => none
    | none => none
  | .borrow y => match liveE Γ y with
    | some E => match vecElem E.ty with
      | some _ => some (⟨E.ty, .bor, true, derive y E .self, E.held⟩, Γ)
      | none => none
    | none => none
  | .at y i => match liveE Γ y with
    | some E => match vecElem E.ty with
      | some t => if checkExpr Γ i then some (elemE y E t, Γ) else none
      | none => none
    | none => none
  | .view y => match liveE Γ y with
    | some E => match vecElem E.ty with
      | some t => if t.holdsView then none else some (⟨.slice t, .bor, true, derive y E .view, E.held⟩, Γ)
      | none => none
    | none => none
  | .sat y i => match liveE Γ y with
    | some E => match sliceElem E.ty with
      | some t => if checkExpr Γ i then some (elemE y E t, Γ) else none
      | none => none
    | none => none
  | .pop y => match liveE Γ y with
    | some E => match vecElem E.ty with
      | some t => if canDoB E.mode .drop && !(decide (y ∈ F)) then some (popE y E t, kill .drop t.holdsView y Γ)
          else none
      | none => none
    | none => none

theorem inferRhs_sound {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (h : inferRhs Γ F r = some (E, Γ1)) : RhsT Γ F r E Γ1 := by
  cases r with
  | expr e =>
    simp only [inferRhs] at h; split at h
    · rename_i he; cases h; exact .expr (checkExpr_sound he)
    · cases h
  | new t =>
    simp only [inferRhs] at h; split at h
    · rename_i ht; cases h; exact .new ht
    · cases h
  | var y =>
    simp only [inferRhs] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE_some hE0
      split at h
      · rename_i hm
        split at h
        · cases h
        · rename_i hF; cases h; exact .moveOwn hy hl hm hF
      · rename_i hm; cases h; exact .copyRoot hy hl hm
      · rename_i hm; cases h; exact .copyBor hy hl hm
      · cases h
    · cases h
  | borrow y =>
    simp only [inferRhs] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE_some hE0
      split at h
      · rename_i t ht; cases h; exact .borrow hy hl (vecElem_some ht)
      · cases h
    · cases h
  | «at» y i =>
    simp only [inferRhs] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE_some hE0
      split at h
      · rename_i t ht
        split at h
        · rename_i hi; cases h; exact .at hy hl (vecElem_some ht) (checkExpr_sound hi)
        · cases h
      · cases h
    · cases h
  | view y =>
    simp only [inferRhs] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE_some hE0
      split at h
      · rename_i t ht
        split at h
        · cases h
        · rename_i hv; cases h; exact .view hy hl (vecElem_some ht) (by simpa using hv)
      · cases h
    · cases h
  | sat y i =>
    simp only [inferRhs] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE_some hE0
      split at h
      · rename_i t ht
        split at h
        · rename_i hi; cases h; exact .sat hy hl (sliceElem_some ht) (checkExpr_sound hi)
        · cases h
      · cases h
    · cases h
  | pop y =>
    simp only [inferRhs] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE_some hE0
      split at h
      · rename_i t ht
        split at h
        · rename_i hc
          simp only [Bool.and_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at hc
          cases h; exact .pop hy hl (vecElem_some ht) (canDoB_sound hc.1) hc.2
        · cases h
      · cases h
    · cases h

/-- `PushArg`, computed: what the container holds of `y` afterwards, and the
    context. -/
def pushArg (Γ : Ctx) (F : List Var) (y : Var) (E : Entry) : Ty → Option (List Dep × Ctx)
  | .vec _ => if E.mode = .own ∧ y ∉ F then some (E.held, setE (kill .replace false y Γ) y { E with live := false })
      else none
  | .int => some ([], Γ)
  | .slice _ => if E.mode = .bor ∨ E.mode = .rootb then some (derive y E .self ++ E.held, Γ) else none

theorem pushArg_sound {Γ : Ctx} {F : List Var} {y : Var} {E : Entry} {t : Ty} {D : List Dep} {Γ1 : Ctx}
    (h : pushArg Γ F y E t = some (D, Γ1)) : PushArg Γ F y E t D Γ1 := by
  cases t with
  | vec s =>
    simp only [pushArg] at h; split at h
    · rename_i hc; cases h; exact .move hc.1 hc.2
    · cases h
  | int => simp only [pushArg] at h; cases h; exact .int
  | slice s =>
    simp only [pushArg] at h; split at h
    · rename_i hc; cases h; exact .slice hc
    · cases h

/-- The modes an assignment may join (`StmtT.assign`). -/
def assignModes (Ex E : Entry) : Bool :=
  decide (Ex.mode = .own ∧ E.mode = .own ∨ Ex.mode = .inout .replace ∧ E.mode = .own ∨
    Ex.mode = .bor ∧ E.mode = .bor)

/-- `StmtT` on straight-line statements, computed: the context after, or a
    refusal. -/
def checkStmt : Ctx → List Var → Stmt → Option Ctx
  | Γ, _, .skip => some Γ
  | Γ, F, .seq a b =>
    if b.src then (match checkStmt Γ F a with
      | some Γ1 => checkStmt Γ1 F b
      | none => none) else none
  | Γ, F, .letv x r s =>
    if s.src ∧ Γ x = none ∧ x ∉ F then
      match inferRhs Γ F r with
      | some (E, Γ1) => (checkStmt (setE Γ1 x E) F s).map (exitScope x)
      | none => none
    else none
  | Γ, F, .assign x r =>
    match Γ x with
    | some Ex =>
      if x ∈ F then none else
      match inferRhs Γ F r with
      | some (E, Γ1) =>
        if assignModes Ex E ∧ E.ty = Ex.ty ∧ x ∉ roots E.vdeps ∧ (Γ1 x).isSome then
          some (setE (kill .replace false x Γ1) x { E with mode := Ex.mode })
        else none
      | none => none
    | none => none
  | Γ, F, .push x y =>
    match liveE Γ x, liveE Γ y with
    | some Ex, some Ey =>
      match vecElem Ex.ty with
      | some t =>
        if canDoB Ex.mode .realloc ∧ x ∉ F ∧ Ey.ty = t ∧ y ≠ x then
          match pushArg Γ F y Ey t with
          | some (D, Γ1) =>
            if x ∈ roots D then none else
            match liveE Γ1 x with
            | some Ex1 => some (setE (kill .realloc t.holdsView x Γ1) x { Ex1 with held := Ex1.held ++ D })
            | none => none
          | none => none
        else none
      | none => none
    | _, _ => none
  | Γ, F, .free x =>
    match liveE Γ x with
    | some E =>
      match vecElem E.ty with
      | some _ => if E.mode = .own ∧ x ∉ F then some (setE (kill .replace false x Γ) x { E with live := false })
          else none
      | none => none
    | none => none
  | Γ, F, .frozen z s => checkStmt Γ (F ++ z) s
  -- (the forms decided elsewhere, C1, or not at all: one arm each, so the
  -- match does not overlap)
  | _, _, .letcall _ _ _ _ => none
  | _, _, .ite _ _ _ => none
  | _, _, .while _ _ => none
  | _, _, .scope _ _ => none
  | _, _, .rbind _ _ => none

theorem checkStmt_sound {P : Prog} : ∀ {s : Stmt} {Γ : Ctx} {F : List Var} {Δ : Ctx},
    checkStmt Γ F s = some Δ → StmtT P Γ F s Δ := by
  intro s
  induction s with
  | skip => intro Γ F Δ h; simp [checkStmt] at h; subst h; exact .skip
  | seq a b iha ihb =>
    intro Γ F Δ h
    unfold checkStmt at h
    split at h
    · rename_i hb
      split at h
      · rename_i Γ1 ha; exact .seq hb (iha ha) (ihb h)
      · cases h
    · cases h
  | letv x r s ih =>
    intro Γ F Δ h
    unfold checkStmt at h
    split at h
    · rename_i hc
      obtain ⟨hs, hx, hF⟩ := hc
      split at h
      · rename_i E Γ1 hr
        obtain ⟨Δ0, h0, rfl⟩ := Option.map_eq_some_iff.mp h
        exact .letv hs hx hF (inferRhs_sound hr) (ih h0)
      · cases h
    · cases h
  | letcall x f args s ih => intro Γ F Δ h; simp [checkStmt] at h
  | assign x r =>
    intro Γ F Δ h
    unfold checkStmt at h
    split at h
    · rename_i Ex hx
      split at h
      · cases h
      · rename_i hF
        split at h
        · rename_i E Γ1 hr
          split at h
          · rename_i hc
            obtain ⟨hm, hty, hroot, hsome⟩ := hc
            cases h
            exact .assign hx hF (of_decide_eq_true hm) (inferRhs_sound hr) hty hroot hsome
          · cases h
        · cases h
    · cases h
  | ite c a b _ _ => intro Γ F Δ h; simp [checkStmt] at h
  | «while» c s _ => intro Γ F Δ h; simp [checkStmt] at h
  | push x y =>
    intro Γ F Δ h
    unfold checkStmt at h
    split at h
    · rename_i Ex Ey hEx hEy
      obtain ⟨hx, hxl⟩ := liveE_some hEx
      obtain ⟨hy, hyl⟩ := liveE_some hEy
      split at h
      · rename_i t ht
        split at h
        · rename_i hc
          obtain ⟨hcd, hF, hty, hne⟩ := hc
          split at h
          · rename_i D Γ1 hpa
            split at h
            · cases h
            · rename_i hroot
              split at h
              · rename_i Ex1 hEx1
                obtain ⟨hx1, hx1l⟩ := liveE_some hEx1
                cases h
                exact .push hx hxl (vecElem_some ht) (canDoB_sound hcd) hF hy hyl hty hne (pushArg_sound hpa)
                  hroot hx1 hx1l
              · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | free x =>
    intro Γ F Δ h
    unfold checkStmt at h
    split at h
    · rename_i E hE
      obtain ⟨hx, hl⟩ := liveE_some hE
      split at h
      · rename_i t ht
        split at h
        · rename_i hc; cases h; exact .free hx hl hc.1 (vecElem_some ht) hc.2
        · cases h
      · cases h
    · cases h
  | scope x s _ => intro Γ F Δ h; simp [checkStmt] at h
  | rbind p s _ => intro Γ F Δ h; simp [checkStmt] at h
  | frozen z s ih => intro Γ F Δ h; simp only [checkStmt] at h; exact .frozen (ih h)

/-- A program the checker accepts, run from the empty store, never gets
    stuck: `A1.memory_safe` through `checkStmt_sound`. The checker's answer
    is a computation, so a nurlc certificate for such a program is checked
    by running it. -/
theorem checked_memory_safe {P : Prog} (hP : ProgOK P) {s : Stmt} {Δ : Ctx}
    (hc : checkStmt (fun _ => none) [] s = some Δ) (hs : s.src = true) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv) {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem nv) s (.ok m' s')) :
    ¬ Stuck P m' s' :=
  memory_safe hP (checkStmt_sound hc) hs hv hr

/-! ### The checker runs -/

/-- `: v ( vec_new [int] )  ( vec_push v 1 … )` as A1: a push of an integer
    into a fresh owned `Vec`, then its free. -/
def ex1 : Stmt := .letv 0 (.new .int) (.letv 1 (.expr (.lit 7)) (.seq (.push 0 1) (.free 0)))

example : (checkStmt (fun _ => none) [] ex1).isSome = true := by decide

/-- A view of `v`, taken once `v` holds an element, read at index 0:
    accepted (the positive control for `ex2`). -/
def ex2ok : Stmt :=
  .letv 0 (.new .int) (.letv 2 (.expr (.lit 1)) (.seq (.push 0 2)
    (.letv 1 (.view 0) (.letv 3 (.sat 1 (.lit 0)) .skip))))

example : (checkStmt (fun _ => none) [] ex2ok).isSome = true := by decide

/-- The same view kept across a second push into `v` (a use after the
    realloc ends it): refused. The read itself is in bounds, so the
    refusal is the push's. -/
def ex2 : Stmt :=
  .letv 0 (.new .int) (.letv 2 (.expr (.lit 1)) (.seq (.push 0 2)
    (.letv 1 (.view 0) (.seq (.push 0 2) (.letv 3 (.sat 1 (.lit 0)) .skip)))))

example : (checkStmt (fun _ => none) [] ex2).isSome = false := by decide

end C
