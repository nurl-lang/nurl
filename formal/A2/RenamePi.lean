import A2.Rename

/-! A2 — AGORA-937: the lift of a callee's dependencies, with regions.

Where a call places the body, a dependency on a callee binding is renamed
(`rds`). A dependency on a parameter's region `π p` is not a binding of the
caller's: it stands for what the argument's views point into, so it becomes
those dependencies (`σ (π p)`). With no region among them, the lift is
`rds` itself (`rdsπ_nopi`), so every lemma of `rds` holds of it there. -/

namespace A2

/-- The lift of dependencies: a region's are what it stands for (`σ`),
    every other one is renamed. -/
def rdsπ (ρ : Var → Var) (isPi : Var → Bool) (σ : Var → List Dep) (ds : List Dep) : List Dep :=
  ds.flatMap fun d => if isPi d.root then σ d.root else [Dep.ren ρ d]

/-- With no region among them, the lift renames (AGORA-937, condition 4). -/
theorem rdsπ_nopi {ρ : Var → Var} {isPi : Var → Bool} {σ : Var → List Dep} {ds : List Dep}
    (h : ∀ d ∈ ds, isPi d.root = false) : rdsπ ρ isPi σ ds = rds ρ ds := by
  unfold rdsπ rds
  induction ds with
  | nil => rfl
  | cons d ds ih =>
    simp only [List.flatMap_cons, List.map_cons, h d List.mem_cons_self, Bool.false_eq_true, ↓reduceIte,
      List.singleton_append]
    rw [ih (fun e he => h e (List.mem_cons_of_mem _ he))]

theorem mem_rdsπ {ρ : Var → Var} {isPi : Var → Bool} {σ : Var → List Dep} {ds : List Dep} {e : Dep} :
    e ∈ rdsπ ρ isPi σ ds ↔
      ∃ d ∈ ds, (isPi d.root = true ∧ e ∈ σ d.root) ∨ (isPi d.root = false ∧ e = Dep.ren ρ d) := by
  unfold rdsπ
  simp only [List.mem_flatMap]
  constructor
  · rintro ⟨d, hd, he⟩
    refine ⟨d, hd, ?_⟩
    cases hp : isPi d.root
    · rw [hp] at he; simp at he; exact Or.inr ⟨rfl, he⟩
    · rw [hp] at he; simp at he; exact Or.inl ⟨rfl, he⟩
  · rintro ⟨d, hd, ⟨hp, he⟩ | ⟨hp, rfl⟩⟩
    · exact ⟨d, hd, by rw [hp]; simpa using he⟩
    · exact ⟨d, hd, by rw [hp]; simp⟩

end A2
