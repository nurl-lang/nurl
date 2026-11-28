module

public import A2.Invariant

@[expose] public section

namespace A2

/-! AGORA-937 (3d, route U, PR B2): a step's new killable names
(`Stmt.killVars`) are old ones, fresh ones (`≥ m.nv`), or the `inout`
captures of a closure the step calls (`CapInout`). By claude-expert
(AGORA-962). -/

theorem Stmt.killVars_rename (ρ : Var → Var) (s : Stmt) :
    (s.rename ρ).killVars = s.killVars.map ρ := by
  induction s <;> simp_all [Stmt.rename, Stmt.killVars, Rhs.vars_rename, Expr.vars_rename, Edit.vars_rename]

theorem ExitAt.killVars_sub {s e : Stmt} {n : Nat} (h : ExitAt s n e) :
    ∀ v ∈ e.killVars, v ∈ s.killVars := by
  induction h with
  | exit => simp [Stmt.killVars]
  | seq _ ih => intro v hv; simp only [Stmt.killVars, List.mem_append]; exact Or.inl (ih v hv)
  | scope _ ih => intro v hv; simp only [Stmt.killVars, List.mem_cons] at hv ⊢; rcases hv with h | h; exact Or.inl h; exact Or.inr (ih v h)
  | scopeD _ ih => intro v hv; simp only [Stmt.killVars, List.mem_cons] at hv ⊢; rcases hv with h | h; exact Or.inl h; exact Or.inr (ih v h)
  | block _ ih => intro v hv; simp only [Stmt.killVars]; exact ih v hv

theorem killVars_wrap (ps : List (PMode × Ty)) (base i : Nat) (s : Stmt) :
    ∀ v ∈ (wrapParams ps base i s).killVars, base ≤ v ∨ v ∈ s.killVars := by
  induction ps generalizing i with
  | nil => intro v hv; exact Or.inr hv
  | cons p ps ih =>
    obtain ⟨pm, t⟩ := p
    intro v hv
    cases pm with
    | inp =>
      simp only [wrapParams, Stmt.killVars, List.mem_cons] at hv
      rcases hv with rfl | hv
      · exact Or.inl (Nat.le_add_right _ _)
      · exact ih (i + 1) v hv
    | sink =>
      simp only [wrapParams, Stmt.killVars, List.mem_cons] at hv
      rcases hv with rfl | hv
      · exact Or.inl (Nat.le_add_right _ _)
      · exact ih (i + 1) v hv
    | inout b => exact ih (i + 1) v hv

theorem callRen_mem (ps : List (PMode × Ty)) (args : List Var) (base v : Var) :
    base ≤ callRen ps args base v ∨ callRen ps args base v ∈ inoutArgs ps args := by
  unfold callRen
  split
  · rename_i b t h
    right
    unfold inoutArgs
    refine List.mem_map.mpr ⟨v, ?_, rfl⟩
    have hlt : v < ps.length := by
      rcases Nat.lt_or_ge v ps.length with h' | h'
      · exact h'
      · rw [List.getElem?_eq_none h'] at h; cases h
    have he : ps[v] = (.inout b, t) := by simpa [List.getElem?_eq_getElem hlt] using h
    simp [List.mem_filter, List.mem_range, hlt, List.getElem?_eq_getElem hlt, he]
  · exact Or.inl (Nat.le_add_right _ _)

theorem killVars_resFrame (fn : Fn) (r : Var) (s : Stmt) :
    ∀ v ∈ (resFrame fn r s).killVars, v = r ∨ v ∈ s.killVars := by
  intro v hv
  unfold resFrame at hv
  split at hv <;> simpa [Stmt.killVars] using hv

theorem killVars_callIn (fn : Fn) (args : List Var) (base : Nat) (x : Var) :
    ∀ v ∈ (callIn fn args base x).killVars, v = x ∨ base ≤ v ∨ v ∈ inoutArgs fn.params args := by
  intro v hv
  unfold callIn at hv
  rcases killVars_resFrame _ _ _ v hv with rfl | hv
  · exact Or.inr (Or.inl (Nat.le_add_right _ _))
  simp only [Stmt.killVars, List.mem_append, List.mem_cons, Rhs.vars, List.not_mem_nil, or_false] at hv
  rcases hv with hv | rfl | rfl
  · rcases killVars_wrap _ _ _ _ v hv with h | hv
    · exact Or.inr (Or.inl h)
    rw [Stmt.killVars_rename] at hv
    obtain ⟨w, -, rfl⟩ := List.mem_map.mp hv
    rcases callRen_mem fn.params args base w with h | h
    · exact Or.inr (Or.inl h)
    · exact Or.inr (Or.inr h)
  · exact Or.inl rfl
  · exact Or.inr (Or.inl (Nat.le_add_right _ _))

theorem BindParams.length_eq {m m' : Mem} {ps : List (PMode × Ty)} {args : List Var} {base i : Nat}
    (h : BindParams m ps args base i m') : args.length = ps.length := by
  induction h <;> simp_all

theorem inoutArgs_sub (ps : List (PMode × Ty)) (args : List Var) (hl : args.length = ps.length) :
    ∀ v ∈ inoutArgs ps args, v ∈ args := by
  intro v hv
  unfold inoutArgs at hv
  obtain ⟨i, hi, rfl⟩ := List.mem_map.mp hv
  have hlt : i < args.length := by
    rw [hl]; exact List.mem_range.mp (List.mem_filter.mp hi).1
  simp [List.getD, List.getElem?_eq_getElem hlt]

/-- A step's new killable name that is a closure's capture handed to an
    `inout` parameter of its code (`callc`). -/
def CapInout (P : Prog) (m : Mem) (v : Var) : Prop :=
  ∃ (c : Var) (o : Bool) (fs : List Nat) (te : Ty) (ms : List Nat) (env : Val)
    (cs : List (Var × PMode × Ty)) (j f : Nat) (fn : Fn) (zs : List Var) (i : Nat) (b : Eff) (t : Ty),
    m.st c = some ⟨o, some (.pkg fs te ms env cs)⟩ ∧ fs[j]? = some f ∧ P[f]? = some fn ∧
    (m.nv :: zs ++ cs.map (·.1)).length = fn.params.length ∧
    zs.length + 1 ≤ i ∧ (m.nv :: zs ++ cs.map (·.1))[i]? = some v ∧
    fn.params[i]? = some (PMode.inout b, t)

/-- AGORA-937 B4: the package slot a statement calls first, if it calls one
    (`callc`, `callcE`), through the running scopes. -/
def Stmt.headCallc : Stmt → List Var
  | .seq a _ => a.headCallc
  | .scope _ s => s.headCallc
  | .rbind _ s => s.headCallc
  | .scopeD _ _ s => s.headCallc
  | .scopeL _ _ _ s => s.headCallc
  | .catchR _ _ s => s.headCallc
  | .frozen _ s => s.headCallc
  | .block s => s.headCallc
  | .callc _ c _ _ _ _ => [c]
  | .callcE _ c _ _ _ => [c]
  | _ => []

/-- `CapInout` at a given package slot `c`. -/
def CapInoutAt (P : Prog) (m : Mem) (c : Var) (v : Var) : Prop :=
  ∃ (o : Bool) (fs : List Nat) (te : Ty) (ms : List Nat) (env : Val)
    (cs : List (Var × PMode × Ty)) (j f : Nat) (fn : Fn) (zs : List Var) (i : Nat) (b : Eff) (t : Ty),
    m.st c = some ⟨o, some (.pkg fs te ms env cs)⟩ ∧ fs[j]? = some f ∧ P[f]? = some fn ∧
    (m.nv :: zs ++ cs.map (·.1)).length = fn.params.length ∧
    zs.length + 1 ≤ i ∧ (m.nv :: zs ++ cs.map (·.1))[i]? = some v ∧
    fn.params[i]? = some (PMode.inout b, t)

/-- ... at the slot the statement calls first. -/
def CapInoutH (P : Prog) (m : Mem) (s : Stmt) (v : Var) : Prop :=
  ∃ c ∈ s.headCallc, CapInoutAt P m c v

theorem inoutArgs_pos (ps : List (PMode × Ty)) (args : List Var) (hl : args.length = ps.length) :
    ∀ v ∈ inoutArgs ps args, ∃ (i : Nat) (b : Eff) (t : Ty), ps[i]? = some (PMode.inout b, t) ∧ args[i]? = some v := by
  intro v hv
  unfold inoutArgs at hv
  obtain ⟨i, hi, rfl⟩ := List.mem_map.mp hv
  obtain ⟨hir, hin⟩ := List.mem_filter.mp hi
  have hlt : i < ps.length := List.mem_range.mp hir
  have hla : i < args.length := by rw [hl]; exact hlt
  revert hin
  cases hpi : ps[i]? with
  | none => intro h; simp at h
  | some pe =>
    obtain ⟨pm, t⟩ := pe
    cases pm with
    | inout b => intro _; exact ⟨i, b, t, hpi, by simp [List.getD, List.getElem?_eq_getElem hla]⟩
    | inp => intro h; simp at h
    | sink => intro h; simp at h

/-- AGORA-937 B4: `Step.killVars_sub`, the captured name at the slot the
    statement calls first. -/
theorem Step.killVars_subH {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) :
    ∀ m' s', r = .ok m' s' → ∀ v ∈ s'.killVars, v ∈ s.killVars ∨ m.nv ≤ v ∨ CapInoutH P m s v := by
  induction h with
  | seqL _ ih =>
    intro m' s' hr v hv; cases hr
    simp only [Stmt.killVars, List.mem_append] at hv ⊢
    rcases hv with hv | hv
    · rcases ih _ _ rfl v hv with h | h | h
      · exact Or.inl (Or.inl h)
      · exact Or.inr (Or.inl h)
      · exact Or.inr (Or.inr h)
    · exact Or.inl (Or.inr hv)
  | @letcall m1 x f args k fn hf hx hb =>
    intro m' s' hr v hv; cases hr
    simp only [callStmt, Stmt.killVars, List.mem_cons, List.mem_append] at hv
    rcases hv with rfl | hv | hv
    · exact Or.inl (by simp [Stmt.killVars])
    · rcases killVars_callIn fn args m.nv x v hv with rfl | h | h
      · exact Or.inl (by simp [Stmt.killVars])
      · exact Or.inr (Or.inl h)
      · exact Or.inl (by simp [Stmt.killVars, inoutArgs_sub _ _ hb.length_eq v h])
    · exact Or.inl (by simp [Stmt.killVars, hv])
  | scopeIn _ ih =>
    intro m' s' hr v hv; cases hr
    simp only [Stmt.killVars, List.mem_cons] at hv ⊢
    rcases hv with h | hv
    · exact Or.inl (Or.inl h)
    · rcases ih _ _ rfl v hv with h | h | h
      · exact Or.inl (Or.inr h)
      · exact Or.inr (Or.inl h)
      · exact Or.inr (Or.inr h)
  | rbindIn _ ih =>
    intro m' s' hr v hv; cases hr
    simp only [Stmt.killVars, List.mem_cons] at hv ⊢
    rcases hv with h | hv
    · exact Or.inl (Or.inl h)
    · rcases ih _ _ rfl v hv with h | h | h
      · exact Or.inl (Or.inr h)
      · exact Or.inr (Or.inl h)
      · exact Or.inr (Or.inr h)
  | scopeDIn _ ih =>
    intro m' s' hr v hv; cases hr
    simp only [Stmt.killVars, List.mem_cons] at hv ⊢
    rcases hv with h | hv
    · exact Or.inl (Or.inl h)
    · rcases ih _ _ rfl v hv with h | h | h
      · exact Or.inl (Or.inr h)
      · exact Or.inr (Or.inl h)
      · exact Or.inr (Or.inr h)
  | scopeLIn _ ih =>
    intro m' s' hr v hv; cases hr
    simp only [Stmt.killVars, List.mem_cons] at hv ⊢
    rcases hv with h | hv
    · exact Or.inl (Or.inl h)
    · rcases ih _ _ rfl v hv with h | h | h
      · exact Or.inl (Or.inr h)
      · exact Or.inr (Or.inl h)
      · exact Or.inr (Or.inr h)
  | catchIn _ ih =>
    intro m' s' hr v hv; cases hr
    simp only [Stmt.killVars, List.mem_cons] at hv ⊢
    rcases hv with h | hv
    · exact Or.inl (Or.inl h)
    · rcases ih _ _ rfl v hv with h | h | h
      · exact Or.inl (Or.inr h)
      · exact Or.inr (Or.inl h)
      · exact Or.inr (Or.inr h)
  | frozenIn _ ih =>
    intro m' s' hr v hv; cases hr
    simp only [Stmt.killVars] at hv ⊢
    exact ih _ _ rfl v hv
  | blockIn _ ih =>
    intro m' s' hr v hv; cases hr
    simp only [Stmt.killVars] at hv ⊢
    exact ih _ _ rfl v hv
  | blockExit he =>
    intro m' s' hr v hv; cases hr
    exact Or.inl (he.killVars_sub v hv)
  | @letrec x f k fn hf hp hx =>
    intro m' s' hr v hv; cases hr
    simp only [recStmt, Stmt.killVars, List.mem_cons, List.mem_append] at hv
    rcases hv with rfl | (rfl | hv) | hv
    · exact Or.inl (by simp [Stmt.killVars])
    · exact Or.inl (by simp [Stmt.killVars])
    · rcases killVars_callIn fn [] m.nv x v hv with rfl | h | h
      · exact Or.inl (by simp [Stmt.killVars])
      · exact Or.inr (Or.inl h)
      · rw [hp] at h; simp [inoutArgs] at h
    · exact Or.inl (by simp [Stmt.killVars, hv])
  | @callc m1 x c j σ zs k o fs te ms env cs f fn hc hj hf hx hb =>
    intro m' s' hr v hv; cases hr
    simp only [Stmt.killVars, List.mem_cons, List.mem_append] at hv
    rcases hv with rfl | (rfl | hv) | hv
    · exact Or.inl (by simp [Stmt.killVars])
    · exact Or.inr (Or.inl (Nat.le_refl _))
    · rcases killVars_callIn fn _ (m.nv + 1) x v hv with rfl | h | h
      · exact Or.inl (by simp [Stmt.killVars])
      · exact Or.inr (Or.inl (by omega))
      · have hl := hb.length_eq
        obtain ⟨i, b, t, hpi, hai⟩ := inoutArgs_pos _ _ hl v h
        rcases Nat.lt_or_ge i (zs.length + 1) with hi | hi
        · cases i with
          | zero =>
            simp at hai; subst hai; exact Or.inr (Or.inl (Nat.le_refl _))
          | succ k =>
            have hk : k < zs.length := by omega
            have hz : zs[k]? = some v := by
              simpa [List.getElem?_cons_succ, List.getElem?_append_left hk] using hai
            exact Or.inl (by simp [Stmt.killVars, List.mem_of_getElem? hz])
        · exact Or.inr (Or.inr ⟨c, by simp [Stmt.headCallc], o, fs, te, ms, env, cs, j, f, fn, zs, i, b, t, hc, hj, hf, hl, hi, hai, hpi⟩)
    · exact Or.inl (by simp [Stmt.killVars, hv])
  | _ =>
    intro m' s' hr v hv
    cases hr
    all_goals (simp only [Stmt.killVars, Rhs.vars, Expr.vars, handStmt, handStmtD, List.mem_cons, List.mem_append, List.not_mem_nil] at hv ⊢ <;> grind)


/-- ... dropping which package slot the statement calls. -/
theorem Step.killVars_sub {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) :
    ∀ m' s', r = .ok m' s' → ∀ v ∈ s'.killVars, v ∈ s.killVars ∨ m.nv ≤ v ∨ CapInout P m v := by
  intro m' s' hr v hv
  rcases h.killVars_subH m' s' hr v hv with h1 | h1 | ⟨c, -, o, fs, te, ms, env, cs, j, f, fn, zs, i, b, t, hc⟩
  · exact Or.inl h1
  · exact Or.inr (Or.inl h1)
  · exact Or.inr (Or.inr ⟨c, o, fs, te, ms, env, cs, j, f, fn, zs, i, b, t, hc⟩)

end A2
