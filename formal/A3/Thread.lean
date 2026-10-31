import A3.Ghost

/-! A3.0 — A2's theorems, as facts about one thread on its own part of the
address space (`ThreadOK`), and the algebra of the parts. -/

namespace A3
open A2

/-- The program's start: the one thread, on the empty store. -/
theorem ThreadOK.init {P : Prog} {s : Stmt} {Δ : Ctx} {nv : Nat}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P)
    (hv : ∀ v ∈ s.vars, v < nv) : ThreadOK P (emptyMem nv) s :=
  ⟨fun _ => none, [], Δ, ht, inv_empty hs hv, codes_empty P nv, hsc, closed_empty s⟩

/-- A2's preservation, one step. -/
theorem ThreadOK.step {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {m : Mem} {s : Stmt}
    (h : ThreadOK P m s) {m' : Mem} {s' : Stmt} (hst : Step P m s (.ok m' s')) : ThreadOK P m' s' := by
  obtain ⟨Γ, F, Δ, ht, hi, hcd, hsc, hc⟩ := h
  obtain ⟨Γ', ht', hi', hc', hcd', hsc'⟩ := reach_ok hP hPc ht hcd hsc hi hc (.step hst .refl)
  exact ⟨Γ', F, Δ, ht', hi', hcd', hsc', hc'⟩

/-- A2's progress: a thread is finished, or it can step. -/
theorem ThreadOK.progress {P : Prog} (hP : ProgOK P) {m : Mem} {s : Stmt} (h : ThreadOK P m s) :
    s = .skip ∨ ∃ r, Step P m s r := by
  obtain ⟨Γ, F, Δ, ht, hi, hcd, _, _⟩ := h
  exact progress' hP ht hcd hi

/-- A finished thread owns nothing: its part of the address space is empty. -/
theorem ThreadOK.no_leak {P : Prog} {m : Mem} (h : ThreadOK P m .skip) : ∀ i, m.alloc i = false := by
  obtain ⟨Γ, F, Δ, _, hi, _, _, hc⟩ := h
  intro i
  cases ha : m.alloc i with
  | false => rfl
  | true =>
    obtain ⟨o, T, hT, _⟩ := hi.cover i ha
    have hd := hi.dom o
    unfold OwnedAt at hT
    rw [hT] at hd
    exact absurd (hc o hd) (by simp [Stmt.spine])

/-- Every address live on a thread's part is below `nid`. -/
theorem ThreadOK.lt_nid {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) :
    ∀ i, m.alloc i = true → i < m.nid := by
  obtain ⟨Γ, F, Δ, _, hi, _, _, _⟩ := h
  intro i ha
  obtain ⟨o, T, hT, hiT⟩ := hi.cover i ha
  exact (hi.heap.alloc o T hT i hiT).2

/-- Every address of a thread's owned trees is on its part. -/
theorem ThreadOK.owned {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) :
    ∀ i, OwnedId m i → m.alloc i = true := by
  obtain ⟨Γ, F, Δ, _, hi, _, _, _⟩ := h
  rintro i ⟨o, T, hT, hiT⟩
  exact (hi.heap.alloc o T hT i hiT).1

/-! ### Parts -/

theorem minus_minus {a b : Nat → Bool} (h : ∀ i, b i = true → a i = true) : minus a (minus a b) = b := by
  funext i
  simp only [minus]
  cases hb : b i <;> cases ha : a i <;> simp_all

theorem union_minus {a b : Nat → Bool} (h : ∀ i, b i = true → a i = true) : union b (minus a b) = a := by
  funext i
  simp only [union, minus]
  cases hb : b i <;> cases ha : a i <;> simp_all

theorem minus_disj {a b : Nat → Bool} : ∀ i, b i = true → minus a b i = false := by
  intro i h; simp [minus, h]

theorem minus_le {a b : Nat → Bool} : ∀ i, minus a b i = true → a i = true := by
  intro i h; simp only [minus, Bool.and_eq_true] at h; exact h.1

end A3
