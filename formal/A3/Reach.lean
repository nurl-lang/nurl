module

public import A3.Defs
public import A2.Reach

@[expose] public section

/-! A3 — the functions a threaded run can name (AGORA-1013).

`A2/Reach.lean`'s invariant over a configuration of threads: every thread's
statement and slots, and the shared blocks, name only functions of a set
`A` closed under the program's names (`CfgFns`).  A thread's step is A2's
step on its view (`A2.fns_step`), the reaps after it A2's too, and a spawn
runs on the new thread the body of the function the statement's call names
(`Redex.fns`).  So no interleaving reaches a configuration naming a function
outside `A` (`Reach.fns`), and a program that agrees with `P` on `A` has the
same interleavings (`reach_agree_iff`): a function outside `A` runs on no
thread. -/

namespace A3
open A2

variable {A : Nat → Prop}

/-- Every thread names only functions of `A`, in what it runs and in what its
    slots hold, and so do the shared blocks. -/
def CfgFns (A : Nat → Prop) (C : Cfg) : Prop :=
  (∀ t ∈ C.ths, (∀ x o V, t.st x = some ⟨o, some V⟩ → PkgFns A V) ∧ t.s.fnsIn A) ∧ BlkFns A C.blk

theorem CfgFns.view {C : Cfg} (h : CfgFns A C) {i : Nat} {t : Thread} (ht : C.ths[i]? = some t) :
    MemFns A (C.view t) ∧ t.s.fnsIn A := by
  have := h.1 t (List.mem_of_getElem? ht)
  exact ⟨⟨this.1, h.2⟩, this.2⟩

theorem CfgFns.put {C : Cfg} (h : CfgFns A C) {i : Nat} {m : Mem} {s : Stmt} (hm : MemFns A m)
    (hs : s.fnsIn A) : CfgFns A (C.put i m s) := by
  refine ⟨fun t ht => ?_, hm.blk⟩
  rcases List.mem_or_eq_of_mem_set ht with ht | rfl
  · exact h.1 t ht
  · exact ⟨hm.1, hs⟩

/-- The sweep of the shared blocks is A2's (`A2.BlkFns.sweepBlkD`); no thread's
    slots change. -/
theorem CfgFns.sweepD {C : Cfg} (h : CfgFns A C) : CfgFns A C.sweepD := ⟨h.1, BlkFns.sweepBlkD h.2⟩

theorem CSettle.fns {P : Prog} (hP : ProgFns A P) {i : Nat} {C C' : Cfg} (h : CSettle P i C C')
    (hc : CfgFns A C) : CfgFns A C' := by
  induction h with
  | done _ => exact hc
  | reap ht hst _ _ ih =>
    obtain ⟨hm, hs⟩ := hc.view ht
    obtain ⟨hm1, hs1⟩ := (fns_step hP hst hm hs).1 _ _ rfl
    exact ih (hc.put hm1 hs1).sweepD

theorem CSettle.agree {P P' : Prog} (hP : ProgFns A P) (hag : Agree A P P') {i : Nat} {C C' : Cfg}
    (h : CSettle P i C C') (hc : CfgFns A C) : CSettle P' i C C' := by
  induction h with
  | done ho => exact .done ho
  | reap ht hst hr _ ih =>
    obtain ⟨hm, hs⟩ := hc.view ht
    obtain ⟨hm1, hs1⟩ := (fns_step hP hst hm hs).1 _ _ rfl
    exact .reap ht (step_agree hag hst hm hs) hr (ih (hc.put hm1 hs1).sweepD)

/-- The redex of a statement that names only `A` names only `A`, and so does
    the statement with any such redex put back. -/
theorem Redex.fns {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) (hs : s.fnsIn A) :
    r.fnsIn A ∧ ∀ y, y.fnsIn A → (K y).fnsIn A := by
  induction h with
  | here => exact ⟨hs, fun y hy => hy⟩
  | seq _ ih =>
    obtain ⟨h1, h2⟩ := ih hs.1; exact ⟨h1, fun y hy => ⟨h2 y hy, hs.2⟩⟩
  | scope _ ih | rbind _ ih | frozen _ ih | catchR _ ih | block _ ih =>
    obtain ⟨h1, h2⟩ := ih hs; exact ⟨h1, fun y hy => h2 y hy⟩
  | scopeD _ ih =>
    obtain ⟨h1, h2⟩ := ih hs.2; exact ⟨h1, fun y hy => ⟨hs.1, h2 y hy⟩⟩
  | scopeL _ ih =>
    obtain ⟨h1, h2⟩ := ih hs.2; exact ⟨h1, fun y hy => ⟨hs.1, h2 y hy⟩⟩

/-- The arguments a spawn moves were in the spawner's slots, and so is
    everything its slots still hold. -/
theorem MoveArgs.fns {st st' : Var → Option Slot} {as : List Var} {vs : List Val}
    (h : MoveArgs st as vs st') (hst : ∀ x o V, st x = some ⟨o, some V⟩ → PkgFns A V) :
    (∀ v ∈ vs, PkgFns A v) ∧ ∀ x o V, st' x = some ⟨o, some V⟩ → PkgFns A V := by
  induction h with
  | nil => exact ⟨fun _ h => (by cases h), hst⟩
  | @cons st _ a _ v _ ha _ ih =>
    have hst' : ∀ x o V, upd st a (some ⟨true, none⟩) x = some ⟨o, some V⟩ → PkgFns A V := by
      intro x o V hx
      by_cases hxa : x = a
      · subst hxa; simp at hx
      · rw [upd_ne _ _ hxa] at hx; exact hst x o V hx
    obtain ⟨h1, h2⟩ := ih hst'
    refine ⟨fun w hw => ?_, h2⟩
    rcases List.mem_cons.mp hw with rfl | hw
    · exact hst a true w ha
    · exact h1 w hw

/-- **Every interleaving step keeps the names in `A`.** -/
theorem TStep.fns {P : Prog} (hP : ProgFns A P) {spawn : Nat → Bool} {C C' : Cfg}
    (h : TStep P spawn C C') (hc : CfgFns A C) : CfgFns A C' := by
  cases h with
  | thread ht _ hst hse =>
    obtain ⟨hm, hs⟩ := hc.view ht
    obtain ⟨hm1, hs1⟩ := (fns_step hP hst hm hs).1 _ _ rfl
    exact hse.fns hP (hc.put hm1 hs1).sweepD
  | @spawn i t K x f args k fn vs st' ht hr _ hf _ hmv _ =>
    obtain ⟨hm, hs⟩ := hc.view ht
    obtain ⟨⟨hAf, hk⟩, hK⟩ := hr.fns hs
    obtain ⟨hvs, hst'⟩ := hmv.fns hm.1
    have hfn := hP _ _ hf hAf
    refine ⟨fun t' ht' => ?_, hc.2⟩
    rcases List.mem_append.mp ht' with ht' | ht'
    · rcases List.mem_or_eq_of_mem_set ht' with ht' | rfl
      · exact hc.1 t' ht'
      · refine ⟨fun y o V hy => ?_, hK _ hk⟩
        simp only at hy
        by_cases hyx : y = x
        · subst hyx; simp at hy; obtain ⟨_, rfl⟩ := hy; exact pkgFns_int A 0
        · rw [upd_ne _ _ hyx] at hy; exact hst' y o V hy
    · simp only [List.mem_singleton] at ht'
      subst ht'
      refine ⟨fun y o V hy => ?_, wrapParams_fns (s := .scope fn.params.length fn.body) hfn.1 _ _ _⟩
      simp only [spawnSt] at hy
      split at hy
      · simp at hy
      · cases hw : vs[y]? with
        | none => rw [hw] at hy; simp at hy
        | some w =>
          rw [hw] at hy; simp at hy; obtain ⟨_, rfl⟩ := hy
          exact hvs w (List.mem_of_getElem? hw)
  | @spawnFail i t K x f args k fn vs st' ht hr _ hf _ hmv _ =>
    obtain ⟨hm, hs⟩ := hc.view ht
    obtain ⟨⟨hAf, hk⟩, hK⟩ := hr.fns hs
    refine ⟨fun t' ht' => ?_, hc.2⟩
    rcases List.mem_or_eq_of_mem_set ht' with ht' | rfl
    · exact hc.1 t' ht'
    · exact ⟨hm.1, hK _ ⟨trivial, hAf, hk⟩⟩

/-- **An interleaving step reads the program only at indices in `A`.** -/
theorem TStep.agree {P P' : Prog} (hP : ProgFns A P) (hag : Agree A P P') {spawn : Nat → Bool}
    {C C' : Cfg} (h : TStep P spawn C C') (hc : CfgFns A C) : TStep P' spawn C C' := by
  cases h with
  | thread ht hns hst hse =>
    obtain ⟨hm, hs⟩ := hc.view ht
    obtain ⟨hm1, hs1⟩ := (fns_step hP hst hm hs).1 _ _ rfl
    exact .thread ht hns (step_agree hag hst hm hs) (hse.agree hP hag (hc.put hm1 hs1).sweepD)
  | spawn ht hr hsp hf h1 h2 h3 =>
    obtain ⟨hm, hs⟩ := hc.view ht
    obtain ⟨⟨hAf, _⟩, _⟩ := hr.fns hs
    exact .spawn ht hr hsp ((hag _ hAf).trans hf) h1 h2 h3
  | spawnFail ht hr hsp hf h1 h2 h3 =>
    obtain ⟨hm, hs⟩ := hc.view ht
    obtain ⟨⟨hAf, _⟩, _⟩ := hr.fns hs
    exact .spawnFail ht hr hsp ((hag _ hAf).trans hf) h1 h2 h3

/-- **No interleaving reaches a configuration naming a function outside `A`.** -/
theorem Reach.fns {P : Prog} (hP : ProgFns A P) {spawn : Nat → Bool} {C C' : Cfg}
    (h : Reach P spawn C C') (hc : CfgFns A C) : CfgFns A C' := by
  induction h with
  | refl => exact hc
  | step hst _ ih => exact ih (hst.fns hP hc)

theorem Reach.agree {P P' : Prog} (hP : ProgFns A P) (hag : Agree A P P') {spawn : Nat → Bool}
    {C C' : Cfg} (h : Reach P spawn C C') (hc : CfgFns A C) : Reach P' spawn C C' := by
  induction h with
  | refl => exact .refl
  | step hst _ ih => exact .step (hst.agree hP hag hc) (ih (hst.fns hP hc))

/-- **The same interleavings**: a program that agrees with `P` on `A` reaches
    exactly the configurations `P` does, so a function outside `A` runs on no
    thread. -/
theorem reach_agree_iff {P P' : Prog} (hP : ProgFns A P) (hag : Agree A P P') {spawn : Nat → Bool}
    {C C' : Cfg} (hc : CfgFns A C) : Reach P spawn C C' ↔ Reach P' spawn C C' :=
  ⟨fun h => h.agree hP hag hc, fun h => h.agree (hP.of_agree hag) hag.symm hc⟩

/-- The start of a program run on one thread names what its statement names. -/
theorem cfgFns_init {s : Stmt} (hs : s.fnsIn A) (nv : Nat) : CfgFns A (Cfg.init s nv) := by
  refine ⟨fun t ht => ?_, fun _ _ h => (by cases h), fun _ _ h => (by cases h)⟩
  simp only [Cfg.init, List.mem_singleton] at ht
  subst ht
  exact ⟨fun _ _ _ h => (by cases h), hs⟩

end A3
