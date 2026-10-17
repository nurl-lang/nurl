import A2.Panic

/-! A2 — facts about the typing rules themselves. -/

namespace A2

theorem src_spine {s : Stmt} (h : s.src = true) : s.spine = [] := by
  induction s with
  | seq a b iha _ => simp only [Stmt.src, Bool.and_eq_true] at h; simp [Stmt.spine, iha h.1]
  | _ => simp_all [Stmt.src, Stmt.spine]

theorem StmtT.weakenIn {P : Prog} {Γ Γ0 Δ : Ctx} {F : List Var} {s : Stmt} (hw : Weaker Γ Γ0)
    (h : StmtT P Γ0 F s Δ) : StmtT P Γ F s Δ := StmtT.sub hw h (Or.inl rfl)

theorem StmtT.weakenOut {P : Prog} {Γ Δ0 Δ : Ctx} {F : List Var} {s : Stmt} (hwf : CtxWF Γ)
    (h : StmtT P Γ F s Δ0) (hw : Δ0 = Δ ∨ Weaker Δ0 Δ) : StmtT P Γ F s Δ :=
  StmtT.sub (Weaker.refl hwf) h hw

theorem weakerEq_trans {Γ1 Γ2 Γ3 : Ctx} (h1 : Γ1 = Γ2 ∨ Weaker Γ1 Γ2) (h2 : Γ2 = Γ3 ∨ Weaker Γ2 Γ3) :
    Γ1 = Γ3 ∨ Weaker Γ1 Γ3 := by
  rcases h1 with rfl | h1 <;> rcases h2 with rfl | h2
  · exact Or.inl rfl
  · exact Or.inr h2
  · exact Or.inr h1
  · exact Or.inr (h1.trans h2)

/-- A `skip` only weakens. -/
theorem skip_inv {P : Prog} {Γ Δ : Ctx} {F : List Var} (h : StmtT P Γ F .skip Δ) :
    Γ = Δ ∨ Weaker Γ Δ := by
  generalize hs : Stmt.skip = s at h
  induction h with
  | skip => exact Or.inl rfl
  | sub hw _ ho ih => exact weakerEq_trans (Or.inr hw) (weakerEq_trans (ih hs) ho)
  | _ => cases hs

/-! ### Kills, scope ends and rerooting are monotone -/

theorem hits_mono {e : Eff} {hv : Bool} {x : Var} {E E' : Entry} (hw : EntryWeaker E E')
    (hl : E'.live = true) (h : hits e hv x E = true) : hits e hv x E' = true := by
  obtain ⟨ht, hm, _, hlv⟩ := hw
  obtain ⟨_, hp, hh⟩ := hlv hl
  unfold hits at h ⊢
  rw [ht, hm]
  simp only [Bool.and_eq_true, List.any_eq_true] at h ⊢
  obtain ⟨h1, d, hd, h2⟩ := h
  refine ⟨h1, d, ?_, h2⟩
  unfold Entry.vdeps at hd ⊢
  rw [hm]
  simp only [List.mem_append] at hd ⊢
  rcases hd with hd | hd
  · left
    cases ho : E.mode.ownSlot with
    | true => simp [ho] at hd
    | false => simp only [ho, Bool.false_eq_true, ↓reduceIte] at hd ⊢; exact hp ho hd
  · exact Or.inr (hh hd)

theorem killE_weaker {e : Eff} {hv : Bool} {x : Var} {E E' : Entry} (hw : EntryWeaker E E') :
    EntryWeaker (killE e hv x E) (killE e hv x E') := by
  have hw' := hw
  obtain ⟨ht, hm, hr, hlv⟩ := hw
  refine ⟨by rw [killE_ty, killE_ty, ht], by rw [killE_mode, killE_mode, hm], fun h => ?_, fun h => ?_⟩
  · rw [killE_mode] at h; rw [hr h]
  · rw [killE_live] at h
    simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at h
    obtain ⟨hl', hnh⟩ := h
    obtain ⟨hl, hp, hh⟩ := hlv hl'
    have hnh0 : hits e hv x E = false := by
      cases hh0 : hits e hv x E with
      | false => rfl
      | true => rw [hits_mono hw' hl' hh0] at hnh; cases hnh
    refine ⟨by rw [killE_live, hl, hnh0]; rfl, fun ho => ?_, ?_⟩
    · rw [killE_path, killE_path]; rw [killE_mode] at ho; exact hp ho
    · rw [killE_held, killE_held]; exact hh

theorem CtxWF.kill {Γ : Ctx} (h : CtxWF Γ) (e : Eff) (hv : Bool) (x : Var) : CtxWF (kill e hv x Γ) := by
  intro v E' hv' hl hn r hr
  obtain ⟨E, hE, hm, _⟩ := kill_cmode hv'
  simp only [A2.kill, hE, Option.map_some, Option.some.injEq] at hv'
  subst hv'
  rw [killE_live] at hl; simp only [Bool.and_eq_true] at hl
  rw [killE_ty, killE_mode] at hn
  rw [killE_vdeps] at hr
  obtain ⟨Er, hEr, hro⟩ := h v E hE hl.1 hn r hr
  exact kill_root hEr hro

theorem Weaker.kill {Γ Γ' : Ctx} (hw : Weaker Γ Γ') (e : Eff) (hv : Bool) (x : Var) :
    Weaker (kill e hv x Γ) (kill e hv x Γ') := by
  refine ⟨fun v => ⟨?_, fun E E' h1 h2 => ?_⟩, hw.wf.kill e hv x⟩
  · simp only [A2.kill, Option.map_eq_none_iff]; exact (hw.1 v).1
  · simp only [A2.kill] at h1 h2
    cases hE : Γ v with
    | none => rw [hE] at h1; cases h1
    | some E0 =>
      cases hE' : Γ' v with
      | none => rw [hE'] at h2; cases h2
      | some E0' =>
        rw [hE] at h1; rw [hE'] at h2; cases h1; cases h2
        exact killE_weaker ((hw.1 v).2 E0 E0' hE hE')

theorem Weaker.exitScope {Γ Γ' : Ctx} (hw : Weaker Γ Γ') (x : Var) :
    Weaker (exitScope x Γ) (exitScope x Γ') := by
  have hk := hw.kill .replace false x
  refine ⟨fun v => ?_, ?_⟩
  · by_cases hvx : v = x
    · subst hvx; simp [A2.exitScope]
    · simp only [A2.exitScope, upd_ne _ _ hvx]; exact hk.1 v
  · intro v E hv' hl hn r hr
    have hvx : v ≠ x := fun h => by subst h; simp [A2.exitScope] at hv'
    simp only [A2.exitScope, upd_ne _ _ hvx] at hv'
    obtain ⟨Er, hEr, hro⟩ := hk.2 v E hv' hl hn r hr
    have hrx : r ≠ x := by
      intro hrx; subst hrx
      obtain ⟨E0, hE0, _, _⟩ := kill_cmode hv'
      simp only [A2.kill, hE0, Option.map_some, Option.some.injEq] at hv'
      subst hv'
      rw [killE_live] at hl
      simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hl
      rw [killE_ty, killE_mode] at hn
      rw [killE_vdeps] at hr
      obtain ⟨dep, hd, hdr⟩ := List.mem_map.mp hr
      have : hits .replace false r E0 = true := by
        unfold hits
        simp only [Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, List.any_eq_true, beq_iff_eq]
        refine ⟨?_, dep, hd, hdr, by cases dep.kind <;> rfl⟩
        rcases hn with h | h
        · exact Or.inl h
        · exact Or.inr (by rw [h])
      rw [this] at hl; cases hl.2
    exact ⟨Er, by simp [A2.exitScope, upd_ne _ _ hrx, hEr], hro⟩

theorem reroot_subset {p : Var} {D a b : List Dep} (h : a ⊆ b) : reroot p D a ⊆ reroot p D b := by
  intro d hd
  unfold reroot at hd ⊢
  obtain ⟨d0, hd0, hin⟩ := List.mem_flatMap.mp hd
  exact List.mem_flatMap.mpr ⟨d0, h hd0, hin⟩

theorem rerootE_weaker {p : Var} {D : List Dep} {E E' : Entry} (hw : EntryWeaker E E') :
    EntryWeaker (rerootE p D E) (rerootE p D E') := by
  obtain ⟨ht, hm, hr, hlv⟩ := hw
  refine ⟨ht, hm, fun h => by rw [hr h], fun hl => ?_⟩
  obtain ⟨hl', hp, hh⟩ := hlv hl
  exact ⟨hl', fun ho => reroot_subset (hp ho), reroot_subset hh⟩

theorem Weaker.exitRoot {Γ Γ' : Ctx} (hw : Weaker Γ Γ') (p : Var) (D : List Dep)
    (hD : ∀ d ∈ D, d.root ≠ p ∧ ∃ Er, Γ' d.root = some Er ∧ Er.mode.isRoot = true) :
    Weaker (exitRoot p D Γ) (exitRoot p D Γ') := by
  refine ⟨fun v => ⟨?_, fun E E' h1 h2 => ?_⟩, ?_⟩
  · by_cases hvp : v = p
    · subst hvp; simp [A2.exitRoot]
    · simp only [A2.exitRoot, upd_ne _ _ hvp, Option.map_eq_none_iff]; exact (hw.1 v).1
  · have hvp : v ≠ p := fun h => by subst h; simp [A2.exitRoot] at h1
    simp only [A2.exitRoot, upd_ne _ _ hvp] at h1 h2
    cases hE : Γ v with
    | none => rw [hE] at h1; cases h1
    | some E0 =>
      cases hE' : Γ' v with
      | none => rw [hE'] at h2; cases h2
      | some E0' =>
        rw [hE] at h1; rw [hE'] at h2; cases h1; cases h2
        exact rerootE_weaker ((hw.1 v).2 E0 E0' hE hE')
  · intro v E hv' hl hn r hr
    have hvp : v ≠ p := fun h => by subst h; simp [A2.exitRoot] at hv'
    simp only [A2.exitRoot, upd_ne _ _ hvp] at hv'
    cases hE : Γ' v with
    | none => rw [hE] at hv'; cases hv'
    | some E0 =>
      rw [hE] at hv'; simp only [Option.map_some, Option.some.injEq] at hv'; subst hv'
      have hroot : ∀ r, (∃ Er, Γ' r = some Er ∧ Er.mode.isRoot = true) → r ≠ p →
          ∃ Er, A2.exitRoot p D Γ' r = some Er ∧ Er.mode.isRoot = true := by
        intro r ⟨Er, hEr, hro⟩ hrp
        exact ⟨rerootE p D Er, by simp [A2.exitRoot, upd_ne _ _ hrp, hEr], hro⟩
      rw [vdeps_reroot] at hr
      obtain ⟨dep, hd, rfl⟩ := List.mem_map.mp hr
      rcases mem_reroot hd with ⟨hd0, hne⟩ | ⟨k, d', _, hd', rfl⟩
      · exact hroot _ (hw.2 v E0 hE hl hn _ (List.mem_map_of_mem hd0)) hne
      · obtain ⟨hne, hex⟩ := hD d' hd'
        exact hroot _ hex hne


/-! ### The invariant of what runs inside a run-time form -/

theorem catchOK_src {m : Mem} {s : Stmt} (h : s.src = true) : CatchOK m s := by
  induction s with
  | seq a b iha _ => simp only [Stmt.src, Bool.and_eq_true] at h; exact iha h.1
  | _ => simp_all [Stmt.src, CatchOK]

theorem Inv.seqIn {m : Mem} {Γ : Ctx} {F : List Var} {a b : Stmt} (hi : Inv m Γ F (.seq a b)) :
    Inv m Γ F a :=
  { toMInv := hi.toMInv
    nvS := fun v hv => hi.nvS v (by simp [Stmt.vars, hv])
    nvF := hi.nvF
    anch := hi.anch
    spineNd := hi.spineNd
    spineDom := hi.spineDom
    catchOK := hi.catchOK
    cover := hi.cover }

theorem Inv.scopeIn {m : Mem} {Γ : Ctx} {F : List Var} {x : Var} {k : Stmt} {Ex : Entry}
    (hi : Inv m Γ F (.scope x k)) (hx : Γ x = some Ex) (hnrb : Ex.mode ≠ .rootb) : Inv m Γ F k :=
  { toMInv := hi.toMInv
    nvS := fun v hv => hi.nvS v (by simp [Stmt.vars, hv])
    nvF := hi.nvF
    anch := fun p E hp hm hps => hi.anch p E hp hm (by
      simp only [Stmt.spine, List.mem_cons, not_or]
      refine ⟨fun h => ?_, hps⟩
      subst h; rw [hx] at hp; cases hp; exact hnrb hm)
    spineNd := by
      have := hi.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.2
    spineDom := fun v hv => hi.spineDom v (by simp [Stmt.spine, hv])
    catchOK := hi.catchOK
    cover := hi.cover }

theorem Inv.rbindIn {m : Mem} {Γ : Ctx} {F : List Var} {p : Var} {k : Stmt} {Ep : Entry}
    (hi : Inv m Γ F (.rbind p k)) (hp : Γ p = some Ep) (hroots : ∀ r ∈ roots Ep.vdeps, r ∈ F) :
    Inv m Γ F k :=
  { toMInv := hi.toMInv
    nvS := fun v hv => hi.nvS v (by simp [Stmt.vars, hv])
    nvF := hi.nvF
    anch := fun q E hq hmq hqs => by
      by_cases hqp : q = p
      · subst hqp; rw [hp] at hq; cases hq; exact hroots
      · exact hi.anch q E hq hmq (by simp [Stmt.spine, hqp, hqs])
    spineNd := by
      have := hi.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.2
    spineDom := fun v hv => hi.spineDom v (by simp [Stmt.spine, hv])
    catchOK := hi.catchOK
    cover := hi.cover }

theorem Inv.frozenIn {m : Mem} {Γ : Ctx} {F z : List Var} {k : Stmt} (hi : Inv m Γ F (.frozen z k)) :
    Inv m Γ (F ++ z) k :=
  { toMInv := hi.toMInv
    nvS := fun v hv => hi.nvS v (by simp [Stmt.vars, hv])
    nvF := fun v hv => by
      rcases List.mem_append.mp hv with hv | hv
      · exact hi.nvF v hv
      · exact hi.nvS v (by simp [Stmt.vars, hv])
    anch := fun p E hp hm hps r hr => List.mem_append_left _ (hi.anch p E hp hm hps r hr)
    spineNd := hi.spineNd
    spineDom := hi.spineDom
    catchOK := hi.catchOK
    cover := hi.cover }

theorem evalR_none {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (he : EvalR m r (.ok v o m1))
    {x : Var} (hx : m.st x = none) : m1.st x = none := by
  cases he with
  | new => exact hx
  | @moveOwn y _ hy =>
    have : x ≠ y := fun e => by subst e; rw [hx] at hy; cases hy
    simp [Mem.set, upd_ne _ _ this, hx]
  | @pop y _ _ _ _ _ hy _ _ =>
    have : x ≠ y := fun e => by subst e; rw [hx] at hy; cases hy
    simp [Mem.set, upd_ne _ _ this, hx]
  | _ => exact hx

end A2
