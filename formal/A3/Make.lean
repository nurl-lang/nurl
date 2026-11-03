import A3.Claim

/-! A3.6's rest — module globals read at their declared types.

A program declares its globals' types (a global type environment `GT`); a
typed program reads each global at it (`ProgGlobs`, `Stmt.globsAt`,
A2/Codes.lean), every configuration a start reaches still does
(`Reach.globsAt`), and so, from a start that holds each declared global at
its type, no thread's read of a global panics (`Reach.glob_typed`):
`EvalR.globP` is never taken. -/

namespace A3
open A2

/-! ### Every configuration reads its globals at the declared types -/

theorem Redex.globs_hole {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {GT : GTy}
    (hs : (K r).globsAt GT) : r.globsAt GT := by
  induction h with
  | here => exact hs
  | seq _ ih => exact ih hs.1
  | scope _ ih => exact ih hs
  | rbind _ ih => exact ih hs
  | frozen _ ih => exact ih hs
  | catchR _ ih => exact ih hs
  | scopeD _ ih => exact ih hs
  | scopeL _ ih => exact ih hs

theorem Redex.globsAt {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {GT : GTy} {y y' : Stmt}
    (hy : y.globsAt GT) (hy' : (K y').globsAt GT) : (K y).globsAt GT := by
  induction h with
  | here => exact hy
  | seq _ ih => exact ⟨ih hy'.1, hy'.2⟩
  | scope _ ih => exact ih hy'
  | rbind _ ih => exact ih hy'
  | frozen _ ih => exact ih hy'
  | catchR _ ih => exact ih hy'
  | scopeD _ ih => exact ih hy'
  | scopeL _ ih => exact ih hy'

/-- Every thread of a configuration reads its globals at their declared types. -/
def Cfg.globsAt (C : Cfg) (GT : GTy) : Prop := ∀ t ∈ C.ths, t.s.globsAt GT

/-- **A step keeps it**: a thread's step leaves a part of its statement or a
    function's body (`globs_step`), a spawn the spawner's statement with its
    call replaced and the spawned function's body. -/
theorem TStep.globsAt {P : Prog} {spawn : Nat → Bool} {GT : GTy} (hPG : ProgGlobs P GT) {C C' : Cfg}
    (h : TStep P spawn C C') (hC : C.globsAt GT) : C'.globsAt GT := by
  cases h with
  | @thread i t m' s' hi _ hs =>
    intro t' ht'
    rcases List.mem_or_eq_of_mem_set ht' with ht' | rfl
    · exact hC t' ht'
    · exact globs_step hPG hs (hC t (List.mem_of_getElem? hi)) _ _ rfl
  | @spawn i t K x f args k fn vs st' hi hK _ hf _ _ _ =>
    have ht := hC t (List.mem_of_getElem? hi)
    rw [hK.eq] at ht
    have hk : (Stmt.letcall x f args k).globsAt GT := hK.globs_hole ht
    intro t' ht'
    rcases List.mem_append.mp ht' with ht' | ht'
    · rcases List.mem_or_eq_of_mem_set ht' with ht' | rfl
      · exact hC t' ht'
      · exact hK.globsAt (y := .scope x k) hk ht
    · simp only [List.mem_singleton] at ht'
      subst ht'
      exact wrapParams_globs (s := .scope fn.params.length fn.body) (hPG fn (List.mem_of_getElem? hf)) _ _ _
  | @spawnFail i t K x f args k fn vs st' hi hK _ _ _ _ _ =>
    have ht := hC t (List.mem_of_getElem? hi)
    rw [hK.eq] at ht
    intro t' ht'
    rcases List.mem_or_eq_of_mem_set ht' with ht' | rfl
    · exact hC t' ht'
    · exact hK.globsAt (y := .seq .panic (.letcall x f args k)) ⟨trivial, hK.globs_hole ht⟩ ht

theorem Reach.globsAt {P : Prog} {spawn : Nat → Bool} {GT : GTy} (hPG : ProgGlobs P GT) {C C' : Cfg}
    (h : Reach P spawn C C') (hC : C.globsAt GT) : C'.globsAt GT := by
  induction h with
  | refl => exact hC
  | step hst _ ih => exact ih (hst.globsAt hPG hC)

/-- A right-hand side a statement's next step evaluates: a binding's, an
    assignment's or a destructor binding's, at the redex. -/
def NextRhs (s : Stmt) (r : Rhs) : Prop :=
  ∃ K x k, Redex s K (.letv x r k) ∨ Redex s K (.assign x r) ∨ ∃ f, Redex s K (.letd x f r k)

theorem NextRhs.globAt {s : Stmt} {r : Rhs} {GT : GTy} (h : NextRhs s r) (hs : s.globsAt GT) :
    r.globAt GT := by
  obtain ⟨K, x, k, hK | hK | ⟨f, hK⟩⟩ := h
  · rw [hK.eq] at hs; exact (hK.globs_hole hs).1
  · rw [hK.eq] at hs; exact hK.globs_hole hs
  · rw [hK.eq] at hs; exact (hK.globs_hole hs).1

/-- The start holds every declared global at its declared type. -/
def GlobsAt (G : Globs) (GT : GTy) : Prop := ∀ g t, GT g = some t → ∃ v, G.gl g = some v ∧ GlobFits G.blk t v

/-- **A3.6, from typing alone: no read of a global panics.**  A program that
    reads each global at its declared type, run from a start that holds each
    declared global at that type, reaches no configuration where a thread's
    next read of a global is `EvalR.globP`. -/
theorem Reach.glob_typed {P : Prog} {spawn : Nat → Bool} {GT : GTy} {G : Globs} {s : Stmt} {nv : Nat}
    (hPG : ProgGlobs P GT) (hs : s.globsAt GT) (hG : GlobsAt G GT) {C : Cfg}
    (hr : Reach P spawn (Cfg.start G s nv) C) :
    ∀ th ∈ C.ths, ∀ g t, NextRhs th.s (.glob g t) → ¬ EvalR (C.view th) (.glob g t) .panic := by
  intro th hth g t hn
  have hC : C.globsAt GT := hr.globsAt hPG (fun t' ht' => by
    simp only [Cfg.start, List.mem_singleton] at ht'
    subst ht'; exact hs)
  have hgt : GT g = some t := hn.globAt (hC th hth)
  obtain ⟨v, hv, hf⟩ := hG g t hgt
  exact Reach.glob_noPanic hr hv hf th

end A3
