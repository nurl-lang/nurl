import C.Check

/-!
# C1: joins (`ite`, `while`) over finite contexts (AGORA-970)

`StmtT`'s `ite` asks for one context after both arms, and `while` for a
context its body gives back. With contexts as functions, C0 could not
compare them. Here the checker keeps every context inside a finite domain
`D`: the program's variables, which it gets from the program (`Stmt.vars`).
`Supported Γ D` says `Γ` names nothing outside `D`. Every step keeps that,
so two contexts are equal exactly when they agree on `D`, which a loop over
`D` decides. The checker `checkS` covers all of C0 plus `ite` and `while`,
and is proven sound (`checkS_sound`, `checkedS_memory_safe`).
-/

namespace C

open A1

/-- `Γ` names nothing outside `D`. -/
def Supported (Γ : Ctx) (D : List Var) : Prop := ∀ v, v ∉ D → Γ v = none

theorem supported_kill {Γ : Ctx} {D : List Var} (h : Supported Γ D) (e : Eff) (hv : Bool) (x : Var) :
    Supported (kill e hv x Γ) D := fun v hv' => by simp [kill, h v hv']

theorem supported_setE {Γ : Ctx} {D : List Var} (h : Supported Γ D) {x : Var} (hx : x ∈ D) (E : Entry) :
    Supported (setE Γ x E) D := fun v hv => by
  have : v ≠ x := fun e => hv (e ▸ hx)
  simp [setE, upd, this, h v hv]

theorem supported_exitScope {Γ : Ctx} {D : List Var} (h : Supported Γ D) (x : Var) :
    Supported (exitScope x Γ) D := fun v hv => by
  unfold exitScope; simp only [upd]; split
  · rfl
  · exact supported_kill h .replace false x v hv

/-- Two supported contexts that agree on `D` are equal. -/
theorem eq_of_agree {Γ Δ : Ctx} {D : List Var} (h1 : Supported Γ D) (h2 : Supported Δ D)
    (h : D.all (fun v => Γ v == Δ v) = true) : Γ = Δ := by
  funext v
  by_cases hv : v ∈ D
  · have := List.all_eq_true.mp h v hv; simpa using this
  · rw [h1 v hv, h2 v hv]

theorem inferRhs_supported {Γ : Ctx} {F : List Var} {D : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (hs : Supported Γ D) (hD : ∀ v ∈ r.vars, v ∈ D) (h : inferRhs Γ F r = some (E, Γ1)) : Supported Γ1 D := by
  cases r with
  | expr e => simp only [inferRhs] at h; split at h <;> cases h; exact hs
  | new t => simp only [inferRhs] at h; split at h <;> cases h; exact hs
  | var y =>
    simp only [inferRhs] at h
    split at h
    · split at h
      · split at h
        · cases h
        · cases h; exact supported_setE (supported_kill hs _ _ _) (hD y (by simp [Rhs.vars])) _
      · cases h; exact hs
      · cases h; exact hs
      · cases h
    · cases h
  | borrow y => simp only [inferRhs] at h; split at h <;> (try split at h) <;> cases h; exact hs
  | «at» y i =>
    simp only [inferRhs] at h; split at h <;> (try split at h) <;> (try split at h) <;> cases h; exact hs
  | view y =>
    simp only [inferRhs] at h; split at h <;> (try split at h) <;> (try split at h) <;> cases h; exact hs
  | sat y i =>
    simp only [inferRhs] at h; split at h <;> (try split at h) <;> (try split at h) <;> cases h; exact hs
  | pop y =>
    simp only [inferRhs] at h; split at h <;> (try split at h) <;> (try split at h) <;> cases h
    exact supported_kill hs _ _ _

/-- The checker with joins. Straight-line leaves go to C0's `checkStmt`. -/
def checkS (D : List Var) : Ctx → List Var → Stmt → Option Ctx
  | Γ, F, .seq a b =>
    if b.src then (match checkS D Γ F a with
      | some Γ1 => checkS D Γ1 F b
      | none => none) else none
  | Γ, F, .letv x r s =>
    if s.src ∧ Γ x = none ∧ x ∉ F then
      match inferRhs Γ F r with
      | some (E, Γ1) => (checkS D (setE Γ1 x E) F s).map (exitScope x)
      | none => none
    else none
  | Γ, F, .frozen z s => checkS D Γ (F ++ z) s
  | Γ, F, .ite c a b =>
    if a.src ∧ b.src ∧ checkExpr Γ c then
      match checkS D Γ F a, checkS D Γ F b with
      | some Δa, some Δb => if D.all (fun v => Δa v == Δb v) then some Δa else none
      | _, _ => none
    else none
  | Γ, F, .while c s =>
    if s.src ∧ checkExpr Γ c then
      match checkS D Γ F s with
      | some Δ => if D.all (fun v => Δ v == Γ v) then some Γ else none
      | none => none
    else none
  | Γ, F, s => checkStmt Γ F s

/-- C0's leaves keep the support. -/
theorem checkStmt_leaf_supported {Γ : Ctx} {F D : List Var} {s : Stmt} {Δ : Ctx} (hs : Supported Γ D)
    (hD : ∀ v ∈ s.vars, v ∈ D) (h : checkStmt Γ F s = some Δ)
    (hleaf : s = .skip ∨ (∃ x r, s = .assign x r) ∨ (∃ x y, s = .push x y) ∨ (∃ x, s = .free x)) :
    Supported Δ D := by
  rcases hleaf with rfl | ⟨x, r, rfl⟩ | ⟨x, y, rfl⟩ | ⟨x, rfl⟩
  · simp [checkStmt] at h; subst h; exact hs
  · simp only [checkStmt] at h
    split at h
    · split at h
      · cases h
      · split at h
        · rename_i E Γ1 hr
          split at h
          · cases h
            exact supported_setE (supported_kill (inferRhs_supported hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr) _ _ _)
              (hD x (by simp [Stmt.vars])) _
          · cases h
        · cases h
    · cases h
  · simp only [checkStmt] at h
    split at h
    · split at h
      · split at h
        · split at h
          · rename_i D' Γ1 hpa
            have hs1 : Supported Γ1 D := by
              unfold pushArg at hpa
              split at hpa
              · split at hpa
                · cases hpa; exact supported_setE (supported_kill hs _ _ _) (hD y (by simp [Stmt.vars])) _
                · cases hpa
              · cases hpa; exact hs
              · split at hpa
                · cases hpa; exact hs
                · cases hpa
            split at h
            · cases h
            · split at h
              · cases h; exact supported_setE (supported_kill hs1 _ _ _) (hD x (by simp [Stmt.vars])) _
              · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  · simp only [checkStmt] at h
    split at h
    · split at h
      · split at h
        · cases h; exact supported_setE (supported_kill hs _ _ _) (hD x (by simp [Stmt.vars])) _
        · cases h
      · cases h
    · cases h

theorem checkS_sound {P : Prog} {D : List Var} : ∀ {s : Stmt} {Γ : Ctx} {F : List Var} {Δ : Ctx},
    Supported Γ D → (∀ v ∈ s.vars, v ∈ D) → checkS D Γ F s = some Δ → StmtT P Γ F s Δ ∧ Supported Δ D := by
  intro s
  induction s with
  | skip => intro Γ F Δ hs hD h; simp [checkS, checkStmt] at h; subst h; exact ⟨.skip, hs⟩
  | seq a b iha ihb =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    split at h
    · rename_i hb
      split at h
      · rename_i Γ1 ha
        obtain ⟨ta, sa⟩ := iha hs (fun v hv => hD v (by simp [Stmt.vars, hv])) ha
        obtain ⟨tb, sb⟩ := ihb sa (fun v hv => hD v (by simp [Stmt.vars, hv])) h
        exact ⟨.seq hb ta tb, sb⟩
      · cases h
    · cases h
  | letv x r s ih =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    split at h
    · rename_i hc
      obtain ⟨hsrc, hx, hF⟩ := hc
      split at h
      · rename_i E Γ1 hr
        obtain ⟨Δ0, h0, rfl⟩ := Option.map_eq_some_iff.mp h
        have hs1 := inferRhs_supported hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr
        obtain ⟨t0, s0⟩ := ih (supported_setE hs1 (hD x (by simp [Stmt.vars])) E)
          (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
        exact ⟨.letv hsrc hx hF (inferRhs_sound hr) t0, supported_exitScope s0 x⟩
      · cases h
    · cases h
  | letcall x f args s ih => intro Γ F Δ hs hD h; simp [checkS, checkStmt] at h
  | assign x r =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    exact ⟨checkStmt_sound h, checkStmt_leaf_supported hs hD h (Or.inr (Or.inl ⟨x, r, rfl⟩))⟩
  | ite c a b iha ihb =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    split at h
    · rename_i hc
      obtain ⟨ha, hb, hce⟩ := hc
      split at h
      · rename_i Δa Δb hca hcb
        split at h
        · rename_i hag
          simp only [Option.some.injEq] at h; subst h
          obtain ⟨ta, sa⟩ := iha hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hca
          obtain ⟨tb, sb⟩ := ihb hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hcb
          have heq : Δa = Δb := eq_of_agree sa sb hag
          subst heq
          exact ⟨.ite ha hb (checkExpr_sound hce) ta tb, sa⟩
        · cases h
      · cases h
    · cases h
  | «while» c s ih =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    split at h
    · rename_i hc
      obtain ⟨hsrc, hce⟩ := hc
      split at h
      · rename_i Δ0 h0
        split at h
        · rename_i hag
          simp only [Option.some.injEq] at h; subst h
          obtain ⟨t0, s0⟩ := ih hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
          have heq : Δ0 = Γ := eq_of_agree s0 hs hag
          subst heq
          exact ⟨.while hsrc (checkExpr_sound hce) t0, hs⟩
        · cases h
      · cases h
    · cases h
  | push x y =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    exact ⟨checkStmt_sound h, checkStmt_leaf_supported hs hD h (Or.inr (Or.inr (Or.inl ⟨x, y, rfl⟩)))⟩
  | free x =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    exact ⟨checkStmt_sound h, checkStmt_leaf_supported hs hD h (Or.inr (Or.inr (Or.inr ⟨x, rfl⟩)))⟩
  | scope x s _ => intro Γ F Δ hs hD h; simp [checkS, checkStmt] at h
  | rbind p s _ => intro Γ F Δ hs hD h; simp [checkS, checkStmt] at h
  | frozen z s ih =>
    intro Γ F Δ hs hD h
    simp only [checkS] at h
    obtain ⟨t0, s0⟩ := ih hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h
    exact ⟨.frozen t0, s0⟩

/-- A program the joining checker accepts, run from the empty store, never
    gets stuck. The domain is the program's own variables. -/
theorem checkedS_memory_safe {P : Prog} (hP : ProgOK P) {s : Stmt} {Δ : Ctx}
    (hc : checkS s.vars (fun _ => none) [] s = some Δ) (hs : s.src = true) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv) {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem nv) s (.ok m' s')) :
    ¬ Stuck P m' s' :=
  memory_safe hP (checkS_sound (P := P) (fun _ _ => rfl) (fun _ h => h) hc).1 hs hv hr

/-- A loop that pushes into a `Vec` it owns, then frees it: accepted. -/
def ex3 : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.expr (.lit 3)) (.seq (.while (.lt (.lit 0) (.len 0)) (.push 0 1)) (.free 0)))

example : (checkS ex3.vars (fun _ => none) [] ex3).isSome = true := by decide

/-- One arm frees the `Vec`, the other does not: the arms disagree, refused. -/
def ex4 : Stmt :=
  .letv 0 (.new .int) (.ite (.lit 1) (.free 0) .skip)

example : (checkS ex4.vars (fun _ => none) [] ex4).isSome = false := by decide

end C
