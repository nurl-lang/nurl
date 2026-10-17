import A2.CallInv

/-! A2 — soundness: a well-typed program never reaches a configuration that
is about to touch memory it may not.  Every step checks allocation and
bounds, so a stuck configuration is exactly a memory error (use after free,
a dangling borrow or view, a double free); a failed bounds check panics,
which is a safe stop. -/

namespace A2

/-- Preservation, with the call case discharged. -/
theorem preservation {P : Prog} (hP : ProgOK P) {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P Γ F s Δ) {m m' : Mem} {s' : Stmt} (hi : Inv m Γ F s) (hst : Step P m s (.ok m' s')) :
    ∃ Γ', StmtT P Γ' F s' Δ ∧ Inv m' Γ' F s' := by
  obtain ⟨Γ', ht', hi', _⟩ := preserve (callCase hP) ht hi hst
  exact ⟨Γ', ht', hi'⟩

/-- Progress, with the call case discharged. -/
theorem progress' {P : Prog} {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx} (ht : StmtT P Γ F s Δ)
    {m : Mem} (hi : Inv m Γ F s) : s = .skip ∨ ∃ r, Step P m s r :=
  progress (fun hx hc hi => callProgress hx hc hi) ht hi

/-- Type soundness: from a well-typed configuration, every reachable
    configuration is finished or can step. -/
theorem soundness {P : Prog} (hP : ProgOK P) {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P Γ F s Δ) {m : Mem} (hi : Inv m Γ F s) {m' : Mem} {s' : Stmt}
    (hs : Steps P m s (.ok m' s')) : ¬ Stuck P m' s' := by
  generalize hr : (Res.ok m' s') = r at hs
  induction hs generalizing Γ with
  | refl =>
    cases hr
    rintro ⟨hne, hno⟩
    rcases progress' ht hi with h | ⟨r, hr'⟩
    · exact hne h
    · exact hno r hr'
  | step hst _ ih =>
    obtain ⟨Γ', ht', hi'⟩ := preservation hP ht hi hst
    exact ih ht' hi' hr
  | panic _ => cases hr

/-- The empty store, with variables numbered from `nv` still fresh. -/
def emptyMem (nv : Nat) : Mem := ⟨fun _ => false, 0, nv, fun _ => none⟩

theorem inv_empty {s : Stmt} {nv : Nat} (hs : s.src = true) (hv : ∀ v ∈ s.vars, v < nv) :
    Inv (emptyMem nv) (fun _ => none) [] s where
  dom _ := rfl
  slot _ _ h := by cases h
  heap := ⟨fun _ _ h => (by cases h), fun _ _ _ _ _ h => (by cases h), fun _ _ h => (by cases h)⟩
  nvSt _ h := by cases h
  noInout _ _ _ h := by cases h
  wf _ _ h := by cases h
  rootbLive _ _ h := by cases h
  rootbLt _ _ h := by cases h
  nvS := hv
  nvF _ h := by cases h
  anch _ _ h := by cases h
  spineNd := by rw [src_spine hs]; exact List.nodup_nil
  spineDom v h := by rw [src_spine hs] at h; cases h

/-- The memory model of stage A2 is sound: a well-typed program, run from
    the empty store, never gets stuck — it finishes, panics on a failed
    bounds check, or runs on. -/
theorem memory_safe {P : Prog} (hP : ProgOK P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) {nv : Nat} (hv : ∀ v ∈ s.vars, v < nv)
    {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem nv) s (.ok m' s')) : ¬ Stuck P m' s' :=
  soundness hP ht (inv_empty hs hv) hr

end A2
