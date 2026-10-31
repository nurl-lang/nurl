import A2.StepFrame

/-! A2 — facts about the typing rules themselves. -/

namespace A2

theorem src_spine {s : Stmt} (h : s.src = true) : s.spine = [] := by
  induction s with
  | seq a b iha _ => simp only [Stmt.src, Bool.and_eq_true] at h; simp [Stmt.spine, iha h.1]
  | _ => simp_all [Stmt.src, Stmt.spine]

theorem StmtT.weakenIn {P : Prog} {Γ Γ0 Δ : Ctx} {F : List Var} {s : Stmt} (hw : Weaker Γ Γ0)
    (h : StmtT P Γ0 F s Δ) : StmtT P Γ F s Δ := StmtT.sub hw h (Or.inl rfl)

theorem StmtT.weakenOut {P : Prog} {Γ Δ0 Δ : Ctx} {F : List Var} {s : Stmt} (hwf : CtxWF Γ)
    (hnw : NameWF Γ) (h : StmtT P Γ F s Δ0) (hw : Δ0 = Δ ∨ Weaker Δ0 Δ) : StmtT P Γ F s Δ :=
  StmtT.sub (Weaker.refl hwf hnw) h hw

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
  obtain ⟨ht, hm, hr, hlv, hd, hb, ha, hk⟩ := hw
  refine ⟨by rw [killE_ty, killE_ty, ht], by rw [killE_mode, killE_mode, hm], fun h => ?_, fun h => ?_,
      fun h => by rw [killE_dtor] at h ⊢; rw [killE_held, killE_held]; exact hd h,
      by rw [killE_dbind, killE_dbind, hb], fun h => by rw [killE_dtor] at h; rw [killE_dtor, killE_dbind]; exact ha h,
      fun h => by rw [killE_dbind] at h; rw [killE_held, killE_held]; exact hk h⟩
  · unfold Entry.fixed at h; rw [killE_mode, killE_ty] at h; rw [hr h]
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
  refine ⟨?live, fun v E' hv' hd hos hn d hdd hnm => ?_, ?armc⟩
  case armc =>
    intro v E' hv' hd
    obtain ⟨E, hE, _, _⟩ := kill_cmode hv'
    simp only [A2.kill, hE, Option.map_some, Option.some.injEq] at hv'
    subst hv'
    rw [killE_dtor] at hd; rw [killE_dbind]; exact h.arm v E hE hd
  case live =>
    intro v E' hv' hl hn r hr
    obtain ⟨E, hE, hm, _⟩ := kill_cmode hv'
    simp only [A2.kill, hE, Option.map_some, Option.some.injEq] at hv'
    subst hv'
    rw [killE_live] at hl; simp only [Bool.and_eq_true] at hl
    rw [killE_ty, killE_mode] at hn
    rw [killE_vdeps] at hr
    obtain ⟨Er, hEr, hro⟩ := h v E hE hl.1 hn r hr
    exact kill_root hEr hro
  obtain ⟨E, hE, hm, _⟩ := kill_cmode hv'
  simp only [A2.kill, hE, Option.map_some, Option.some.injEq] at hv'
  subst hv'
  rw [killE_dbind] at hd; rw [killE_mode] at hos; rw [killE_ty, killE_mode] at hn; rw [killE_vdeps] at hdd
  obtain ⟨Er, hEr, hro⟩ := h.dtor v E hE hd hos hn d hdd hnm
  exact kill_root hEr hro

theorem Weaker.kill {Γ Γ' : Ctx} (hw : Weaker Γ Γ') (e : Eff) (hv : Bool) (x : Var) :
    Weaker (kill e hv x Γ) (kill e hv x Γ') := by
  refine ⟨fun v => ⟨?_, fun E E' h1 h2 => ?_⟩, hw.wf.kill e hv x, hw.names.kill e hv x⟩
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

/-- At the end of `x`'s scope, what held `x` by name has ended. -/
theorem NameWF.exitScope {Γ : Ctx} (h : NameWF Γ) (x : Var) : NameWF (exitScope x Γ) := by
  intro v E' hv' hl hn
  have hvx : v ≠ x := fun e => by subst e; simp [A2.exitScope] at hv'
  simp only [A2.exitScope, upd_ne _ _ hvx, A2.kill] at hv'
  cases hE : Γ v with
  | none => rw [hE] at hv'; cases hv'
  | some E =>
    rw [hE] at hv'; cases hv'
    have hn' : E.ty ≠ .int ∨ E.mode = .rootb := by rw [killE_ty, killE_mode] at hn; exact hn
    have hl' := killE_live_dep hl hn'
    intro d hd b t hk
    rw [killE_vdeps] at hd
    obtain ⟨Er, hEr, hlr, hh, ht, ho, hc⟩ := h v E hE hl'.1 hn' d hd b t hk
    have hdx : d.root ≠ x := fun e => by
      have := hl'.2 d hd e
      rw [hk] at this; cases this
    exact ⟨Er, by simp [A2.exitScope, upd_ne _ _ hdx, A2.kill, hEr, killE_nil (root_vdeps ho hh)],
      hlr, hh, ht, ho, hc⟩

theorem Weaker.exitScope {Γ Γ' : Ctx} (hw : Weaker Γ Γ') (x : Var) (hdb : DbindSafe Γ' x) :
    Weaker (exitScope x Γ) (exitScope x Γ') := by
  have hk := hw.kill .replace false x
  refine ⟨fun v => ?_, ?_, hw.names.exitScope x⟩
  · by_cases hvx : v = x
    · subst hvx; simp [A2.exitScope]
    · simp only [A2.exitScope, upd_ne _ _ hvx]; exact hk.1 v
  refine ⟨?live, ?dtorc, ?armc⟩
  case armc =>
    intro v E hv' hd
    have hvx : v ≠ x := fun h => by subst h; simp [A2.exitScope] at hv'
    simp only [A2.exitScope, upd_ne _ _ hvx] at hv'
    exact hk.2.1.arm v E hv' hd
  case dtorc =>
    intro v E hv' hd hos hn d hdd hnm
    have hvx : v ≠ x := fun h => by subst h; simp [A2.exitScope] at hv'
    simp only [A2.exitScope, upd_ne _ _ hvx] at hv'
    obtain ⟨Er, hEr, hro⟩ := hk.2.1.dtor v E hv' hd hos hn d hdd hnm
    have hrx : d.root ≠ x := by
      obtain ⟨E0, hE0, _, _⟩ := kill_cmode hv'
      simp only [A2.kill, hE0, Option.map_some, Option.some.injEq] at hv'
      subst hv'
      rw [killE_dbind] at hd; rw [killE_mode] at hos; rw [killE_ty, killE_mode] at hn
      rw [killE_vdeps] at hdd
      exact hdb v E0 hE0 hd hos hn d hdd hnm
    exact ⟨Er, by simp [A2.exitScope, upd_ne _ _ hrx, hEr], hro⟩
  · intro v E hv' hl hn r hr
    have hvx : v ≠ x := fun h => by subst h; simp [A2.exitScope] at hv'
    simp only [A2.exitScope, upd_ne _ _ hvx] at hv'
    obtain ⟨Er, hEr, hro⟩ := hk.2.1 v E hv' hl hn r hr
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
  obtain ⟨ht, hm, hr, hlv, hd, hb, ha, hk⟩ := hw
  refine ⟨ht, hm, fun h => by rw [hr h], fun hl => ?_,
      fun h => ⟨(hd h).1, reroot_subset (hd h).2⟩, hb, ha, fun h => by simp only [rerootE]; rw [hk h]⟩
  obtain ⟨hl', hp, hh⟩ := hlv hl
  exact ⟨hl', fun ho => reroot_subset (hp ho), reroot_subset hh⟩

theorem CtxWF.exitRoot {Γ' : Ctx} (h : CtxWF Γ') (p : Var) (D : List Dep)
    (hD : ∀ d ∈ D, d.root ≠ p ∧ ∃ Er, Γ' d.root = some Er ∧ Er.mode.isRoot = true) :
    CtxWF (exitRoot p D Γ') := by
  have hroot : ∀ r, (∃ Er, Γ' r = some Er ∧ Er.mode.isRoot = true) → r ≠ p →
      ∃ Er, A2.exitRoot p D Γ' r = some Er ∧ Er.mode.isRoot = true := by
    intro r ⟨Er, hEr, hro⟩ hrp
    exact ⟨rerootE p D Er, by simp [A2.exitRoot, upd_ne _ _ hrp, hEr], hro⟩
  refine ⟨?live, ?dtorc, ?armc⟩
  case armc =>
    intro v E hv' hd
    have hvp : v ≠ p := fun h => by subst h; simp [A2.exitRoot] at hv'
    simp only [A2.exitRoot, upd_ne _ _ hvp] at hv'
    obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hv'
    exact h.arm v E0 h0 hd
  case dtorc =>
    intro v E hv' hd hos hn dep hdd hnm
    have hvp : v ≠ p := fun h => by subst h; simp [A2.exitRoot] at hv'
    simp only [A2.exitRoot, upd_ne _ _ hvp] at hv'
    cases hE : Γ' v with
    | none => rw [hE] at hv'; cases hv'
    | some E0 =>
      rw [hE] at hv'; simp only [Option.map_some, Option.some.injEq] at hv'; subst hv'
      rw [vdeps_reroot] at hdd
      rcases mem_reroot hdd with ⟨hd0, hne⟩ | ⟨k, d', _, hd', rfl⟩
      · exact hroot _ (h.dtor v E0 hE hd hos hn dep hd0 hnm) hne
      · obtain ⟨hne, hex⟩ := hD d' hd'
        exact hroot _ hex hne
  intro v E hv' hl hn r hr
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
    · exact hroot _ (h v E0 hE hl hn _ (List.mem_map_of_mem hd0)) hne
    · obtain ⟨hne, hex⟩ := hD d' hd'
      exact hroot _ hex hne

theorem Weaker.exitRoot {Γ Γ' : Ctx} (hw : Weaker Γ Γ') (p : Var) (D : List Dep)
    (hD : ∀ d ∈ D, d.root ≠ p ∧ ∃ Er, Γ' d.root = some Er ∧ Er.mode.isRoot = true)
    (hp : ∀ Ep, Γ' p = some Ep → Ep.mode.ownSlot = false)
    (hDn : DepsNamed Γ' D) :
    Weaker (exitRoot p D Γ) (exitRoot p D Γ') := by
  refine ⟨fun v => ⟨?_, fun E E' h1 h2 => ?_⟩, hw.wf.exitRoot p D hD,
    hw.names.exitRoot p D hp (fun d hd => (hD d hd).1) hDn⟩
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
    cover := hi.cover
    pinOut := hi.pinOut
    pinIn := hi.pinIn }

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
    cover := hi.cover
    pinOut := fun p E hp hm hps r hr hrk => by
      have hpx : p ≠ x := fun h => by subst h; rw [hx] at hp; cases hp; exact hnrb hm
      exact hi.pinOut p E hp hm (by simp [Stmt.spine, hpx, hps]) r hr (by simp [Stmt.spine, hrk])
    pinIn := hi.pinIn }

/-- A destructor scope binds, names and catches as a plain scope does, and
    the invariant reads a statement only through those. -/
theorem Inv.scopeD_iff {m : Mem} {Γ : Ctx} {F : List Var} {x : Var} {f : Nat} {k : Stmt} :
    Inv m Γ F (.scopeD x f k) ↔ Inv m Γ F (.scope x k) := by
  constructor <;> intro hi <;> exact
    { toMInv := hi.toMInv
      nvS := fun v hv => hi.nvS v (by simpa [Stmt.vars] using hv)
      nvF := hi.nvF
      anch := fun p E hp hm hps => hi.anch p E hp hm (by simpa [Stmt.spine] using hps)
      spineNd := by simpa [Stmt.spine] using hi.spineNd
      spineDom := fun v hv => hi.spineDom v (by simpa [Stmt.spine] using hv)
      catchOK := by simpa [CatchOK] using hi.catchOK
      cover := hi.cover
      pinOut := fun p E hp hm hps r hr => by
        have := hi.pinOut p E hp hm (by simpa [Stmt.spine] using hps) r hr
        simpa [Stmt.spine] using this
      pinIn := hi.pinIn }

theorem Inv.rbindIn {m : Mem} {Γ : Ctx} {F : List Var} {p : Var} {k : Stmt} {Ep : Entry}
    (hi : Inv m Γ F (.rbind p k)) (hp : Γ p = some Ep) (hroots : Anchored Ep F) :
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
    cover := hi.cover
    pinOut := fun q E hq hmq hqs r hr hrk => by
      by_cases hqp : q = p
      · subst hqp; exact hi.pinIn.1 E hq hmq r hr hrk
      · exact hi.pinOut q E hq hmq (by simp [Stmt.spine, hqp, hqs]) r hr (by simp [Stmt.spine, hrk])
    pinIn := hi.pinIn.2 }

theorem Inv.frozenIn {m : Mem} {Γ : Ctx} {F z z' : List Var} {k : Stmt} (hi : Inv m Γ F (.frozen z k))
    (hz : ∀ v ∈ z', v ∈ z) : Inv m Γ (F ++ z') k :=
  { toMInv := hi.toMInv
    nvS := fun v hv => hi.nvS v (by simp [Stmt.vars, hv])
    nvF := fun v hv => by
      rcases List.mem_append.mp hv with hv | hv
      · exact hi.nvF v hv
      · exact hi.nvS v (by simp [Stmt.vars, hz v hv])
    anch := fun p E hp hm hps => (hi.anch p E hp hm hps).mono (fun _ h => List.mem_append_left _ h)
    spineNd := hi.spineNd
    spineDom := hi.spineDom
    catchOK := hi.catchOK
    cover := hi.cover
    pinOut := hi.pinOut
    pinIn := hi.pinIn }


/-- A run-time scope never binds what is lent out. -/
theorem StmtT.spine_F {P : Prog} {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx} (ht : StmtT P Γ F s Δ) :
    ∀ v ∈ s.spine, v ∉ F := by
  induction ht with
  | seq _ _ _ iha _ => exact iha
  | sub _ _ _ ih => exact ih
  | scope _ hxF _ _ ih =>
    intro v hv
    simp only [Stmt.spine, List.mem_cons] at hv
    rcases hv with rfl | hv
    · exact hxF
    · exact ih v hv
  | rbind _ _ _ _ hpF _ _ ih =>
    intro v hv
    simp only [Stmt.spine, List.mem_cons] at hv
    rcases hv with rfl | hv
    · exact hpF
    · exact ih v hv
  | frozen _ _ ih => exact fun v hv hF => ih v hv (List.mem_append_left _ hF)
  | catchR _ _ _ _ _ ih => exact fun v hv hF => ih v hv (List.mem_append_left _ hF)
  | scopeD _ hxF _ _ _ _ _ ih =>
    intro v hv
    simp only [Stmt.spine, List.mem_cons] at hv
    rcases hv with rfl | hv
    · exact hxF
    · exact ih v hv
  | _ => intro v hv; simp [Stmt.spine] at hv


theorem Inv.catchIn {m : Mem} {Γ : Ctx} {F : List Var} {x : Var} {m0 : Mem} {k : Stmt}
    (hi : Inv m Γ F (.catchR x m0 k)) : Inv m Γ (F ++ (List.range m0.nv).filter (· ≠ x)) k :=
  { toMInv := hi.toMInv
    nvS := fun v hv => hi.nvS v (by simp [Stmt.vars, hv])
    nvF := fun v hv => by
      rcases List.mem_append.mp hv with hv | hv
      · exact hi.nvF v hv
      · simp only [List.mem_filter, List.mem_range] at hv
        exact Nat.lt_of_lt_of_le hv.1 hi.catchOK.2.2.1
    anch := fun p E hp hm hps => (hi.anch p E hp hm hps).mono (fun _ h => List.mem_append_left _ h)
    spineNd := hi.spineNd
    spineDom := hi.spineDom
    catchOK := hi.catchOK.2.2.2
    cover := hi.cover
    pinOut := hi.pinOut
    pinIn := hi.pinIn }

theorem HeapOK.set_bor {m : Mem} (hh : HeapOK m) (x : Var) (w : Option Val) :
    HeapOK (m.set x ⟨false, w⟩) := by
  have hown : ∀ o U, OwnedAt (m.set x ⟨false, w⟩) o U → OwnedAt m o U := fun o U h => by
    rcases ownedAt_set.mp h with ⟨_, h⟩ | ⟨_, h⟩
    · cases h
    · exact h
  exact ⟨fun o U h => hh.nodup o U (hown o U h),
    fun o1 o2 U1 U2 hne h1 h2 => hh.disj o1 o2 U1 U2 hne (hown o1 U1 h1) (hown o2 U2 h2),
    fun o U h => hh.alloc o U (hown o U h), fun o U h => hh.self o U (hown o U h)⟩

end A2
