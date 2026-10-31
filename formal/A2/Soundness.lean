import A2.Codes
import A2.SrcKeep

/-! A2 — soundness: a well-typed program never reaches a configuration that
is about to touch memory it may not.  Every step checks allocation and
bounds, so a stuck configuration is exactly a memory error (use after free,
a dangling borrow or view, a double free); a failed bounds check or an
explicit `panic` unwinds, dropping what every scope it leaves owns, and a
`recover` frame catches it.  A call through a closure or a trait object runs
the code the package names, which is code of the package's signature: every
package is made from a closure literal or a `dyn` the program checked
(`ProgCodes`, `Stmt.codesOK`).

And nothing leaks: when the program ends, normally or by a panic no frame
caught, every allocation has been freed. -/

namespace A2

/-- Preservation, with the call and `recover` cases discharged. -/
theorem preservation {P : Prog} (hP : ProgOK P) {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P Γ F s Δ) {m m' : Mem} {s' : Stmt} (hcd : MemCodes P m) (hi : Inv m Γ F s)
    (hst : Step P m s (.ok m' s')) : ∃ Γ', StmtT P Γ' F s' Δ ∧ Inv m' Γ' F s' ∧ Keep Γ Γ' s s' := by
  obtain ⟨Γ', ht', hi', _, hk, _⟩ := preserve (callCase hP) (recCase hP) (cloCase hP) (srcCase hP) ht hcd hi hst
  exact ⟨Γ', ht', hi', hk⟩

/-- Progress, with the call cases discharged. -/
theorem progress' {P : Prog} (hP : ProgOK P) {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P Γ F s Δ) {m : Mem} (hcd : MemCodes P m) (hi : Inv m Γ F s) :
    s = .skip ∨ ∃ r, Step P m s r :=
  progress (fun hx hc hi => callProgress hx hc hi)
    (fun hx _ hc htc hj hσ hhd hcT hnz hcd hi => cloProgress hP hx hc htc hj hσ hhd hcT hnz hcd hi) ht hcd hi

/-- Every binding is bound by a run-time scope the statement is inside of:
    the program's own top level binds nothing else. -/
def Closed (Γ : Ctx) (s : Stmt) : Prop := ∀ v, (Γ v).isSome → v ∈ s.spine

theorem Closed.step {Γ Γ' : Ctx} {s s' : Stmt} (hc : Closed Γ s) (hk : Keep Γ Γ' s s') : Closed Γ' s' := by
  intro v hv
  by_cases hns : v ∈ s'.spine
  · exact hns
  · obtain ⟨E', hE'⟩ := Option.isSome_iff_exists.mp hv
    obtain ⟨hns0, E, hE⟩ := hk.2.1 v E' hE' hns
    exact absurd (hc v (by rw [hE]; rfl)) hns0

/-- Every configuration a well-typed one reaches is well-typed. -/
theorem reach_ok {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {Γ : Ctx} {F : List Var} {s : Stmt}
    {Δ : Ctx} (ht : StmtT P Γ F s Δ) {m : Mem} (hcd : MemCodes P m) (hsc : s.codesOK P)
    (hi : Inv m Γ F s) (hc : Closed Γ s) {m' : Mem} {s' : Stmt} (hs : Steps P m s (.ok m' s')) :
    ∃ Γ', StmtT P Γ' F s' Δ ∧ Inv m' Γ' F s' ∧ Closed Γ' s' ∧ MemCodes P m' ∧ s'.codesOK P := by
  generalize hr : (Res.ok m' s') = r at hs
  induction hs generalizing Γ with
  | refl => cases hr; exact ⟨Γ, ht, hi, hc, hcd, hsc⟩
  | step hst _ ih =>
    obtain ⟨Γ', ht', hi', hk⟩ := preservation hP ht hcd hi hst
    obtain ⟨hcd', hsc'⟩ := (codes_step hPc hst hcd hsc).1 _ _ rfl
    exact ih ht' hcd' hsc' hi' (hc.step hk) hr
  | panic _ => cases hr

/-- A panic no frame catches leaves an empty store with nothing allocated
    that nobody owns. -/
theorem reach_panic {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {Γ : Ctx} {F : List Var} {s : Stmt}
    {Δ : Ctx} (ht : StmtT P Γ F s Δ) {m : Mem} (hcd : MemCodes P m) (hsc : s.codesOK P)
    (hi : Inv m Γ F s) (hc : Closed Γ s) {m' : Mem}
    (hs : Steps P m s (.panic m')) : (∀ v, m'.st v = none) ∧ Covers m' := by
  generalize hr : Res.panic m' = r at hs
  induction hs generalizing Γ with
  | refl => cases hr
  | step hst _ ih =>
    obtain ⟨Γ', ht', hi', hk⟩ := preservation hP ht hcd hi hst
    obtain ⟨hcd', hsc'⟩ := (codes_step hPc hst hcd hsc).1 _ _ rfl
    exact ih ht' hcd' hsc' hi' (hc.step hk) hr
  | @panic m0 m1 s0 hst =>
    cases hr
    obtain ⟨hout, hin, _, hcov, _⟩ := panic_unwind hst hi.heap hi.cover hi.spineNd
    refine ⟨fun v => ?_, hcov⟩
    by_cases hv : v ∈ s0.spine
    · exact hin v hv
    · rw [hout v hv]
      cases h : m0.st v with
      | none => rfl
      | some _ =>
        have := hi.dom v; rw [h] at this
        exact absurd (hc v (by rw [this]; rfl)) hv

/-- Type soundness: from a well-typed configuration, every reachable
    configuration is finished or can step. -/
theorem soundness {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {Γ : Ctx} {F : List Var} {s : Stmt}
    {Δ : Ctx} (ht : StmtT P Γ F s Δ) {m : Mem} (hcd : MemCodes P m) (hsc : s.codesOK P)
    (hi : Inv m Γ F s) (hc : Closed Γ s) {m' : Mem} {s' : Stmt}
    (hs : Steps P m s (.ok m' s')) : ¬ Stuck P m' s' := by
  obtain ⟨Γ', ht', hi', _, hcd', _⟩ := reach_ok hP hPc ht hcd hsc hi hc hs
  rintro ⟨hne, hno⟩
  rcases progress' hP ht' hcd' hi' with h | ⟨r, hr'⟩
  · exact hne h
  · exact hno r hr'

/-- The empty store, with variables numbered from `nv` still fresh. -/
def emptyMem (nv : Nat) : Mem := ⟨fun _ => false, 0, nv, fun _ => none⟩

theorem inv_empty {s : Stmt} {nv : Nat} (hs : s.src = true) (hv : ∀ v ∈ s.vars, v < nv) :
    Inv (emptyMem nv) (fun _ => none) [] s where
  dom _ := rfl
  slot _ _ h := by cases h
  heap := ⟨fun _ _ h => (by cases h), fun _ _ _ _ _ h => (by cases h), fun _ _ h => (by cases h),
    fun _ _ h => (by cases h)⟩
  nvSt _ h := by cases h
  noInout _ _ _ h := by cases h
  wf := ⟨fun _ _ h => (by cases h), fun _ _ h => (by cases h), fun _ _ h => (by cases h),
    fun _ _ h => (by cases h)⟩
  rootbLive _ _ h := by cases h
  rootbLt _ _ h := by cases h
  names _ _ h := by cases h
  held _ _ _ _ h := by cases h
  pkgs _ _ _ h := by cases h
  nvS := hv
  nvF _ h := by cases h
  anch _ _ h := by cases h
  spineNd := by rw [src_spine hs]; exact List.nodup_nil
  spineDom v h := by rw [src_spine hs] at h; cases h
  catchOK := catchOK_src hs
  cover _ h := by cases h
  pinOut _ _ h := by cases h
  pinIn := PinOK.of_spine_nil (src_spine hs)
  dtorOut _ _ h := by cases h
  dtorIn := DtorPinOK.of_spine_nil (src_spine hs)

theorem closed_empty (s : Stmt) : Closed (fun _ => none) s := fun _ h => by cases h

theorem codes_empty (P : Prog) (nv : Nat) : MemCodes P (emptyMem nv) := fun _ _ _ _ _ _ _ _ h => by
  cases h

/-- The memory model of stage A2 is sound: a well-typed program, run from
    the empty store, never gets stuck — it finishes, panics, or runs on. -/
theorem memory_safe {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv)
    {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem nv) s (.ok m' s')) : ¬ Stuck P m' s' :=
  soundness hP hPc ht (codes_empty P nv) hsc (inv_empty hs hv) (closed_empty s) hr

/-- Nothing leaks: when a well-typed program finishes, every allocation it
    made has been freed. -/
theorem no_leak_end {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv)
    {m' : Mem} (hr : Steps P (emptyMem nv) s (.ok m' .skip)) : ∀ i, m'.alloc i = false := by
  obtain ⟨Γ', _, hi', hc', _⟩ :=
    reach_ok hP hPc ht (codes_empty P nv) hsc (inv_empty hs hv) (closed_empty s) hr
  intro i
  cases ha : m'.alloc i with
  | false => rfl
  | true =>
    obtain ⟨o, T, hT, _⟩ := hi'.cover i ha
    have hd := hi'.dom o
    unfold OwnedAt at hT
    rw [hT] at hd
    exact absurd (hc' o hd) (by simp [Stmt.spine])

/-- ... and when a panic no `recover` frame catches ends it, the unwinding
    has freed every allocation too. -/
theorem no_leak_panic {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv)
    {m' : Mem} (hr : Steps P (emptyMem nv) s (.panic m')) : ∀ i, m'.alloc i = false := by
  obtain ⟨hnone, hcov⟩ :=
    reach_panic hP hPc ht (codes_empty P nv) hsc (inv_empty hs hv) (closed_empty s) hr
  intro i
  cases ha : m'.alloc i with
  | false => rfl
  | true =>
    obtain ⟨o, T, hT, _⟩ := hcov i ha
    unfold OwnedAt at hT
    rw [hnone o] at hT; cases hT

end A2
