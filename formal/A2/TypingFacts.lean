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
      fun h hos hn d hnm => by
        rw [killE_dbind] at h; rw [killE_mode] at hos; rw [killE_ty, killE_mode] at hn
        rw [killE_held, killE_held]; exact hk h hos hn d hnm⟩
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
  refine ⟨?live, fun v E' hv' hd hos hn d hdd hnm => ?_, ?armc, ?viewc⟩
  case armc =>
    intro v E' hv' hd
    obtain ⟨E, hE, _, _⟩ := kill_cmode hv'
    simp only [A2.kill, hE, Option.map_some, Option.some.injEq] at hv'
    subst hv'
    rw [killE_dtor] at hd; rw [killE_dbind]; exact h.arm v E hE hd
  case viewc =>
    intro v E' hv' hd
    obtain ⟨E, hE, _, _⟩ := kill_cmode hv'
    simp only [A2.kill, hE, Option.map_some, Option.some.injEq] at hv'
    subst hv'
    rw [killE_dbind] at hd; rw [killE_ty]; exact h.view v E hE hd
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
  refine ⟨?live, ?dtorc, ?armc, ?viewc⟩
  case armc =>
    intro v E hv' hd
    have hvx : v ≠ x := fun h => by subst h; simp [A2.exitScope] at hv'
    simp only [A2.exitScope, upd_ne _ _ hvx] at hv'
    exact hk.2.1.arm v E hv' hd
  case viewc =>
    intro v E hv' hd
    have hvx : v ≠ x := fun h => by subst h; simp [A2.exitScope] at hv'
    simp only [A2.exitScope, upd_ne _ _ hvx] at hv'
    exact hk.2.1.view v E hv' hd
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

/-- Rerooting lists with the same memory views gives the same memory views:
    a memory view after it comes from one before it (a name stays a name). -/
theorem reroot_mem_congr {p : Var} {D L L' : List Dep}
    (h : ∀ d, d.kind.isName = false → (d ∈ L' ↔ d ∈ L)) {d : Dep} (hnm : d.kind.isName = false) :
    d ∈ reroot p D L' ↔ d ∈ reroot p D L := by
  have hcn : ∀ a b : Kind, b.isName = true → (comp a b).isName = true := by
    intro a b; cases a <;> cases b <;> simp [comp, Kind.isName]
  have key : ∀ {L1 L2 : List Dep}, (∀ d, d.kind.isName = false → d ∈ L1 → d ∈ L2) →
      d ∈ reroot p D L1 → d ∈ reroot p D L2 := by
    intro L1 L2 hs hd
    rcases mem_reroot hd with ⟨hin, hne⟩ | ⟨k, d', hk, hd', rfl⟩
    · exact mem_reroot_of_ne (hs d hnm hin) hne
    · cases hkn : k.isName with
      | true => rw [hcn _ _ hkn] at hnm; cases hnm
      | false => exact mem_reroot_of_eq (hs ⟨p, k⟩ hkn hk) hd'
  exact ⟨key fun d hn hd => (h d hn).mp hd, key fun d hn hd => (h d hn).mpr hd⟩

theorem rerootE_weaker {p : Var} {D : List Dep} {E E' : Entry} (hw : EntryWeaker E E') :
    EntryWeaker (rerootE p D E) (rerootE p D E') := by
  obtain ⟨ht, hm, hr, hlv, hd, hb, ha, hk⟩ := hw
  refine ⟨ht, hm, fun h => by rw [hr h], fun hl => ?_,
      fun h => ⟨(hd h).1, reroot_subset (hd h).2⟩, hb, ha,
      fun h hos hn d hnm => reroot_mem_congr (hk h hos hn) hnm⟩
  obtain ⟨hl', hp, hh⟩ := hlv hl
  exact ⟨hl', fun ho => reroot_subset (hp ho), reroot_subset hh⟩

theorem CtxWF.exitRoot {Γ' : Ctx} (h : CtxWF Γ') (p : Var) (D : List Dep)
    (hD : ∀ d ∈ D, d.root ≠ p ∧ ∃ Er, Γ' d.root = some Er ∧ Er.mode.isRoot = true) :
    CtxWF (exitRoot p D Γ') := by
  have hroot : ∀ r, (∃ Er, Γ' r = some Er ∧ Er.mode.isRoot = true) → r ≠ p →
      ∃ Er, A2.exitRoot p D Γ' r = some Er ∧ Er.mode.isRoot = true := by
    intro r ⟨Er, hEr, hro⟩ hrp
    exact ⟨rerootE p D Er, by simp [A2.exitRoot, upd_ne _ _ hrp, hEr], hro⟩
  refine ⟨?live, ?dtorc, ?armc, ?viewc⟩
  case armc =>
    intro v E hv' hd
    have hvp : v ≠ p := fun h => by subst h; simp [A2.exitRoot] at hv'
    simp only [A2.exitRoot, upd_ne _ _ hvp] at hv'
    obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hv'
    exact h.arm v E0 h0 hd
  case viewc =>
    intro v E hv' hd
    have hvp : v ≠ p := fun h => by subst h; simp [A2.exitRoot] at hv'
    simp only [A2.exitRoot, upd_ne _ _ hvp] at hv'
    obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hv'
    exact h.view v E0 h0 hd
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
    pinIn := hi.pinIn
    dtorOut := hi.dtorOut
    dtorIn := hi.dtorIn }

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
    pinIn := hi.pinIn
    dtorOut := fun v E hv hd hos hn hvs d hdd hnm hdk => by
      by_cases hvx : v = x
      · subst hvx; exact hi.dtorIn.1 E hv hd hos hn d hdd hnm hdk
      · exact hi.dtorOut v E hv hd hos hn (by simp [Stmt.spine, hvx, hvs]) d hdd hnm
          (by simp [Stmt.spine, hdk])
    dtorIn := hi.dtorIn.2 }

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
      pinIn := hi.pinIn
      dtorOut := fun v E hv hd hos hn hvs d hdd hnm => by
        have := hi.dtorOut v E hv hd hos hn (by simpa [Stmt.spine] using hvs) d hdd hnm
        simpa [Stmt.spine] using this
      dtorIn := hi.dtorIn }

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
    pinIn := hi.pinIn.2
    dtorOut := fun v E hv hd hos hn hvs d hdd hnm hdk => by
      by_cases hvp : v = p
      · subst hvp; exact hi.dtorIn.1 E hv hd hos hn d hdd hnm hdk
      · exact hi.dtorOut v E hv hd hos hn (by simp [Stmt.spine, hvp, hvs]) d hdd hnm
          (by simp [Stmt.spine, hdk])
    dtorIn := hi.dtorIn.2 }

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
    pinIn := hi.pinIn
    dtorOut := hi.dtorOut
    dtorIn := hi.dtorIn }


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
  | catchR _ _ _ _ _ _ ih => exact fun v hv hF => ih v hv (List.mem_append_left _ hF)
  | scopeD _ hxF _ _ _ _ _ _ ih =>
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
    catchOK := hi.catchOK.2.2.2.2
    cover := hi.cover
    pinOut := hi.pinOut
    pinIn := hi.pinIn
    dtorOut := hi.dtorOut
    dtorIn := hi.dtorIn }

/-! ### A2-drop.2: typing gives no `letd` binding a new view

What a panic's unwind and a `recover` frame need of the context a body's
typing ends in: every binding `letd` made outside the running scopes views,
in memory, no more there than it does now (`StmtT.dkeep`). -/

/-- What `Inv.dtorOut` says: no binding `letd` made outside the scopes `sp`
    views one of their bindings in memory. -/
def DtorOut (Γ : Ctx) (sp : List Var) : Prop :=
  ∀ v E, Γ v = some E → E.dbind = true → E.mode.ownSlot = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
    v ∉ sp → ∀ d ∈ E.vdeps, d.kind.isName = false → d.root ∉ sp

/-- Inside the scope of `x`: `x` itself, by `DtorIn`. -/
theorem DtorOut.inner {Γ : Ctx} {x : Var} {k : Stmt} (ho : DtorOut Γ (x :: k.spine))
    (hin : DtorIn Γ x k) : DtorOut Γ k.spine := fun v E hv hd hos hn hvs d hdd hnm hr => by
  by_cases hvx : v = x
  · subst hvx; exact hin E hv hd hos hn d hdd hnm hr
  · exact ho v E hv hd hos hn (by simp [hvx, hvs]) d hdd hnm (List.mem_cons_of_mem _ hr)

/-- A weaker context keeps what a binding `letd` made views (`dheld`). -/
theorem Weaker.dbind_back {Γ Γ' : Ctx} (hw : Weaker Γ Γ') {v : Var} {E' : Entry} (hv : Γ' v = some E')
    (hd : E'.dbind = true) (hos : E'.mode.ownSlot = true) (hn : E'.ty ≠ .int ∨ E'.mode = .rootb) :
    ∃ E, Γ v = some E ∧ E.dbind = true ∧ E.mode.ownSlot = true ∧ (E.ty ≠ .int ∨ E.mode = .rootb) ∧
      ∀ d ∈ E'.vdeps, d.kind.isName = false → d ∈ E.vdeps := by
  obtain ⟨E, hE, hwe⟩ := hw.get' hv
  have hd0 : E.dbind = true := by rw [← hwe.dbind]; exact hd
  have hos0 : E.mode.ownSlot = true := by rw [← hwe.mode]; exact hos
  have hn0 : E.ty ≠ .int ∨ E.mode = .rootb := by rw [← hwe.ty, ← hwe.mode]; exact hn
  refine ⟨E, hE, hd0, hos0, hn0, fun d hdd hnm => ?_⟩
  simp only [Entry.vdeps, hos, hos0, ↓reduceIte, List.nil_append] at hdd ⊢
  exact (hwe.dheld hd0 hos0 hn0 d hnm).mp hdd

theorem DtorOut.weaker {Γ Γ' : Ctx} {sp : List Var} (hw : Weaker Γ Γ') (h : DtorOut Γ sp) :
    DtorOut Γ' sp := by
  intro v E' hv hd hos hn hvs d hdd hnm
  obtain ⟨E, hE, hd0, hos0, hn0, heq⟩ := hw.dbind_back hv hd hos hn
  exact h v E hE hd0 hos0 hn0 hvs d (heq d hdd hnm) hnm

theorem DtorPinOK.weaker {Γ Γ' : Ctx} {s : Stmt} (hw : Weaker Γ Γ') (h : DtorPinOK Γ s) :
    DtorPinOK Γ' s :=
  h.of_dbind fun _ _ hv hd hos hn => by
    obtain ⟨E, hE, hd0, hos0, hn0, heq⟩ := hw.dbind_back hv hd hos hn
    exact ⟨E, hE, hd0, hos0, hn0, heq⟩

/-- A weaker context keeps a `letd` binding's views as they are, so what
    it does not gain from the weaker, it does not gain from the stronger. -/
theorem DKeep.weaker_left {Γ Γ0 Γ' : Ctx} {sp : List Var} (hw : Weaker Γ Γ0) (h : DKeep Γ0 Γ' sp) :
    DKeep Γ Γ' sp := by
  intro v E' hv hd hos hn hvs
  obtain ⟨E0, h0, hd0, hos0, hn0, hs0⟩ := h v E' hv hd hos hn hvs
  obtain ⟨E, hE, hdE, hosE, hnE, heq⟩ := hw.dbind_back h0 hd0 hos0 hn0
  exact ⟨E, hE, hdE, hosE, hnE, fun d hdd hnm => heq d (hs0 d hdd hnm) hnm⟩

theorem DKeep.weaker_right {Γ Δ0 Δ : Ctx} {sp : List Var} (hw : Weaker Δ0 Δ) (h : DKeep Γ Δ0 sp) :
    DKeep Γ Δ sp := by
  intro v E' hv hd hos hn hvs
  obtain ⟨E1, h1, hd1, hos1, hn1, heq⟩ := hw.dbind_back hv hd hos hn
  obtain ⟨E0, h0, hd0, hos0, hn0, hs0⟩ := h v E1 h1 hd1 hos1 hn1 hvs
  exact ⟨E0, h0, hd0, hos0, hn0, fun d hdd hnm => hs0 d (heq d hdd hnm) hnm⟩

theorem DKeep.exitScope_cons {Γ Γ' : Ctx} {sp : List Var} {x : Var} (h : DKeep Γ Γ' (x :: sp)) :
    DKeep Γ (A2.exitScope x Γ') sp := by
  intro v E hv hd hos hn hvs
  have hvx : v ≠ x := fun e => by subst e; simp [A2.exitScope] at hv
  exact (h.exitScope x) v E hv hd hos hn (by simp [hvx, hvs])

/-- A binding a statement opens and ends: outside it, the statement keeps
    what its parts keep. -/
theorem DKeep.bind {Γ Γ1 Δ : Ctx} {x : Var} {E : Entry} (h1 : DKeep Γ Γ1 [])
    (h2 : DKeep (A2.setE Γ1 x E) Δ []) : DKeep Γ (A2.exitScope x Δ) [] :=
  (((h1.mono fun _ _ h => by cases h).setE (y := x) (E := E)
    fun _ _ _ h => absurd (List.mem_singleton_self x) h).trans
    (h2.mono fun _ _ h => by cases h) fun _ h => h).exitScope_cons

/-- Moving `y` out leaves its entry, dead and disarmed, with what it views. -/
theorem DKeep.moveOut {Γ : Ctx} {y : Var} {E : Entry} (hy : Γ y = some E) (e : Eff) (hv : Bool) :
    DKeep Γ (A2.setE (A2.kill e hv y Γ) y { E with live := false, dtor := false }) [] :=
  ((DKeep.refl Γ []).kill e hv y).setE fun hd hos hn _ => ⟨E, hy, hd, hos, hn, fun _ h _ => h⟩

theorem PushArg.dkeep {Γ : Ctx} {F : List Var} {y : Var} {E : Entry} {t : Ty} {D : List Dep}
    {Γ1 : Ctx} (hy : Γ y = some E) (h : PushArg Γ F y E t D Γ1) : DKeep Γ Γ1 [] := by
  cases h with
  | move => exact DKeep.moveOut hy _ _
  | int => exact DKeep.refl Γ []
  | slice => exact DKeep.refl Γ []

/-- A right-hand side gives no `letd` binding a new view: it only kills, and
    moves a binding out as it is. -/
theorem RhsT.dkeep {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (h : RhsT Γ F r E Γ1) :
    DKeep Γ Γ1 [] := by
  cases h with
  | moveOwn hy => exact DKeep.moveOut hy _ _
  | pop => exact (DKeep.refl Γ []).kill _ _ _
  | pair hy _ hp1 hz _ hp2 _ => exact (hp1.dkeep hy).trans (hp2.dkeep hz) fun _ h => h
  | inl hy _ hp _ => exact hp.dkeep hy
  | inr hy _ hp _ => exact hp.dkeep hy
  | takel hy => exact DKeep.moveOut hy _ _
  | taker hy => exact DKeep.moveOut hy _ _
  | pack hy _ _ hp _ => exact hp.dkeep hy
  | _ => exact DKeep.refl Γ []

theorem DKeep.killNames {Γ Γ' : Ctx} {sp : List Var} (h : DKeep Γ Γ' sp) :
    ∀ ds, DKeep Γ (A2.killNames ds Γ') sp
  | [] => h
  | d :: ds => show DKeep Γ (A2.kill d.kind.bound false d.root (A2.killNames ds Γ')) sp from
      (DKeep.killNames h ds).kill _ _ _

/-- A call moves a `sink` argument as it is, and changes an `inout` one that
    `letd` made only if it holds no views (`CallDtorSafe`): what it views
    stays. -/
theorem DKeep.callPostAux {Γ0 : Ctx} {fn : Fn} {args : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx), DKeep Γ0 Γ [] →
      (∀ j (hj : j < ps.length) b, ps[j].1 = .inout b → ∀ Ea, Γ0 (as.getD j 0) = some Ea →
        Ea.dbind = true → ps[j].2.holdsView = false) →
      DKeep Γ0 (A2.callPostAux Γ0 fn args ps as i Γ) [] := by
  intro ps
  induction ps with
  | nil => intro as i Γ h _; cases as <;> simpa [A2.callPostAux] using h
  | cons p ps ih =>
    intro as i Γ h hv
    obtain ⟨pm, t⟩ := p
    cases as with
    | nil => cases pm <;> simpa [A2.callPostAux] using h
    | cons a as =>
      have hv' : ∀ j (hj : j < ps.length) b, ps[j].1 = .inout b → ∀ Ea, Γ0 (as.getD j 0) = some Ea →
          Ea.dbind = true → ps[j].2.holdsView = false := fun j hj b hb Ea ha hd => by
        have := hv (j + 1) (by simp; omega) b (by simpa using hb) Ea (by simpa using ha) hd
        simpa using this
      cases pm with
      | inp => simpa [A2.callPostAux] using ih as (i + 1) Γ h hv'
      | sink =>
        simp only [A2.callPostAux]
        refine ih as (i + 1) _ ((h.kill _ _ _).setE fun hd hos hn _ => ?_) hv'
        cases ha : Γ0 a with
        | none => simp [argE, ha, intE] at hd
        | some Ea =>
          simp only [argE, ha, Option.getD_some] at hd hos hn
          exact ⟨Ea, rfl, hd, hos, hn, fun d hdd _ => by simpa [Entry.vdeps, argE, ha] using hdd⟩
      | inout b =>
        simp only [A2.callPostAux]
        refine ih as (i + 1) _ ((h.kill _ _ _).setE fun hd hos hn _ => ?_) hv'
        cases ha : Γ0 a with
        | none => simp [argE, ha, intE] at hd
        | some Ea =>
          simp only [argE, ha, Option.getD_some] at hd hos hn
          have ht : t.holdsView = false := hv 0 (by simp) b rfl Ea (by simpa using ha) hd
          exact ⟨Ea, rfl, hd, hos, hn, fun d hdd _ => by simpa [Entry.vdeps, argE, ha, ht] using hdd⟩

theorem CallT.dkeep {P : Prog} {Γ : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    {Γ' : Ctx} (h : CallT P Γ F f args E Γ') : DKeep Γ Γ' [] := by
  obtain ⟨fn, _, _, _, _, hds, _, rfl⟩ := h
  exact (DKeep.callPostAux (fn := fn) (args := args) fn.params args 0 Γ (DKeep.refl Γ [])
    fun j hj b hb Ea ha hd => absurd hd (by rw [hds.2.2 j hj b hb Ea ha]; simp)).killNames _

/-- At a borrowed parameter's end, what depended on it depends on what it
    borrowed (`reroot`). A binding `letd` made gains no view by it: a
    dependency by name stays one, and none depends on the parameter in
    memory. -/
theorem DKeep.exitRoot {Γ Δ : Ctx} {p : Var} {sp : List Var} (D : List Dep) (h : DKeep Γ Δ sp)
    (hno : ∀ v E, Γ v = some E → E.dbind = true → E.mode.ownSlot = true →
      (E.ty ≠ .int ∨ E.mode = .rootb) → v ≠ p → v ∉ sp → ∀ d ∈ E.vdeps, d.kind.isName = false →
        d.root ≠ p) :
    DKeep Γ (A2.exitRoot p D Δ) sp := by
  intro v E' hv hd hos hn hvs
  have hvp : v ≠ p := fun e => by subst e; simp [A2.exitRoot] at hv
  simp only [A2.exitRoot, upd_ne _ _ hvp] at hv
  obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hv
  have hos1 : E1.mode.ownSlot = true := hos
  obtain ⟨E0, h0, hd0, hos0, hn0, hs0⟩ := h v E1 h1 hd hos1 hn hvs
  refine ⟨E0, h0, hd0, hos0, hn0, fun d hdd hnm => ?_⟩
  simp only [Entry.vdeps, rerootE, hos1, ↓reduceIte, List.nil_append] at hdd
  have hin1 : ∀ d', d' ∈ E1.held → d' ∈ E1.vdeps := fun d' h => by
    simp only [Entry.vdeps, hos1, ↓reduceIte, List.nil_append]; exact h
  have hcn : ∀ a b : Kind, b.isName = true → (comp a b).isName = true := by
    intro a b; cases a <;> cases b <;> simp [comp, Kind.isName]
  rcases mem_reroot hdd with ⟨h1', _⟩ | ⟨k, d', hk, _, rfl⟩
  · exact hs0 d (hin1 d h1') hnm
  · exfalso
    cases hkn : k.isName with
    | true => rw [hcn _ _ hkn] at hnm; cases hnm
    | false => exact hno v E0 h0 hd0 hos0 hn0 hvp hvs ⟨p, k⟩ (hs0 ⟨p, k⟩ (hin1 _ hk) hkn) hkn rfl

theorem DKeep.of_src {Γ Δ : Ctx} {s : Stmt} (hs : s.src = true)
    (ih : DtorOut Γ s.spine → DtorPinOK Γ s → DKeep Γ Δ s.spine) : DKeep Γ Δ [] := by
  have h := ih (fun _ _ _ _ _ _ _ _ _ _ hr => by rw [src_spine hs] at hr; cases hr)
    (DtorPinOK.of_spine_nil (src_spine hs))
  rwa [src_spine hs] at h

/-- A2-drop.2: a statement's typing gives no binding `letd` made, outside the
    running scopes, a new view. The one rule that could, a borrowed
    parameter's end (`reroot`), meets none that views the parameter in
    memory (`DtorOut`, which every frame passes inward by `DtorIn`). -/
theorem StmtT.dkeep {P : Prog} {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx} (h : StmtT P Γ F s Δ) :
    DtorOut Γ s.spine → DtorPinOK Γ s → DKeep Γ Δ s.spine := by
  induction h with
  | skip => exact fun _ _ => DKeep.refl _ _
  | seq hb _ _ iha ihb =>
    intro ho hp
    exact (iha ho hp).trans ((DKeep.of_src hb ihb).mono fun _ _ h => by cases h) fun _ h => h
  | letv hs _ _ hr _ _ ih => exact fun _ _ => DKeep.bind hr.dkeep (DKeep.of_src hs ih)
  | letcall hs _ _ hc _ _ ih => exact fun _ _ => DKeep.bind hc.dkeep (DKeep.of_src hs ih)
  | @scope Γ Δ F x k _ _ _ _ ih =>
    intro ho hp
    exact ((ih (DtorOut.inner ho hp.1) hp.2).mono fun v hv h => hv (List.mem_cons_of_mem _ h)).exitScope x
  | @rbind Γ Δ F p k E _ _ _ _ _ _ _ ih =>
    intro ho hp
    refine ((ih (DtorOut.inner ho hp.1) hp.2).mono fun v hv h => hv (List.mem_cons_of_mem _ h)).exitRoot _
      fun v E hv hd hos hn _ hvs d hdd hnm h => ?_
    exact ho v E hv hd hos hn hvs d hdd hnm (by simp [Stmt.spine, h])
  | frozen _ _ ih => exact ih
  | assign _ _ _ hr =>
    intro _ _
    exact (hr.dkeep.kill _ _ _).setE fun hd => absurd hd (by simp [hr.dtor_false.2])
  | ite ha _ _ _ _ iha _ => exact fun _ _ => DKeep.of_src ha iha
  | «while» => exact fun _ _ => DKeep.refl _ _
  | push hx _ _ _ _ hy _ _ _ hpa _ hx1 _ _ hdb =>
    intro _ _
    refine ((hpa.dkeep hy).kill _ _ _).setE fun hd hos hn _ => ?_
    obtain ⟨E0, h0, hd0, hos0, hn0, hs0⟩ := (hpa.dkeep hy) _ _ hx1 hd hos hn (by simp)
    rw [hx] at h0; cases h0
    have ht := hdb hd0
    exact ⟨_, hx, hd0, hos0, hn0, fun d hdd hnm => hs0 d (by simpa [Entry.vdeps, ownHeld, ht] using hdd) hnm⟩
  | free hx => exact fun _ _ => DKeep.moveOut hx _ _
  | sub hw _ hw' ih =>
    intro ho hp
    have h0 := ih (ho.weaker hw) (hp.weaker hw)
    rcases hw' with rfl | hw'
    · exact h0.weaker_left hw
    · exact (h0.weaker_right hw').weaker_left hw
  | panic _ _ _ _ hdk => exact fun _ _ => hdk
  | letrec hs _ _ _ _ _ _ hc _ _ ih => exact fun _ _ => DKeep.bind hc.dkeep (DKeep.of_src hs ih)
  | unpair hs hy _ _ _ _ _ _ _ _ _ _ _ _ _ _ ih =>
    exact fun _ _ => DKeep.bind (DKeep.moveOut hy _ _) (DKeep.bind (DKeep.refl _ []) (DKeep.of_src hs ih))
  | callc hk _ _ _ _ _ _ _ _ hc _ _ _ ih => exact fun _ _ => DKeep.bind hc.dkeep (DKeep.of_src hk ih)
  | catchR _ _ _ _ _ _ ih => exact ih
  | letd hs _ _ hr _ _ _ _ _ _ ih => exact fun _ _ => DKeep.bind hr.dkeep (DKeep.of_src hs ih)
  | @scopeD Γ Δ F x f k _ _ _ _ _ _ _ _ ih =>
    intro ho hp
    exact ((ih (DtorOut.inner ho hp.1) hp.2).mono fun v hv h => hv (List.mem_cons_of_mem _ h)).exitScope x

/-! ### A2-drop.2: a binding `letd` made stays one -/

theorem DStay.weaker_left {Γ Γ0 Γ' : Ctx} {sp : List Var} (hw : Weaker Γ Γ0) (h : DStay Γ0 Γ' sp) :
    DStay Γ Γ' sp := by
  intro v E hv hd hos hvs
  cases h0 : Γ0 v with
  | none => exact absurd ((hw.1 v).1.mpr h0) (by rw [hv]; simp)
  | some E0 =>
    have hwe := (hw.1 v).2 E E0 hv h0
    exact h v E0 h0 (by rw [hwe.dbind]; exact hd) (by rw [hwe.mode]; exact hos) hvs

theorem DStay.weaker_right {Γ Δ0 Δ : Ctx} {sp : List Var} (hw : Weaker Δ0 Δ) (h : DStay Γ Δ0 sp) :
    DStay Γ Δ sp := by
  intro v E hv hd hos hvs
  obtain ⟨E0, h0, hd0, hos0⟩ := h v E hv hd hos hvs
  cases h1 : Δ v with
  | none => exact absurd ((hw.1 v).1.mpr h1) (by rw [h0]; simp)
  | some E1 =>
    have hwe := (hw.1 v).2 E0 E1 h0 h1
    exact ⟨E1, rfl, by rw [hwe.dbind]; exact hd0, by rw [hwe.mode]; exact hos0⟩

theorem DStay.exitRoot {Γ Δ : Ctx} {p : Var} {sp : List Var} (D : List Dep) (h : DStay Γ Δ sp) :
    DStay Γ (A2.exitRoot p D Δ) (p :: sp) := fun v E hv hd hos hvs => by
  have hvp : v ≠ p := fun e => hvs (by simp [e])
  obtain ⟨E', h', hd', hos'⟩ := h v E hv hd hos (fun hm => hvs (List.mem_cons_of_mem _ hm))
  exact ⟨rerootE p D E', by simp [A2.exitRoot, upd_ne _ _ hvp, h'], hd', hos'⟩

/-- A binding the statement opens and ends: outside it, what its parts keep. -/
theorem DStay.bind {Γ Γ1 Δ : Ctx} {x : Var} {E : Entry} (hx : Γ x = none) (h1 : DStay Γ Γ1 [])
    (h2 : DStay (A2.setE Γ1 x E) Δ []) : DStay Γ (A2.exitScope x Δ) [] := by
  intro v E0 hv hd hos _
  have hvx : v ≠ x := fun e => by rw [e, hx] at hv; cases hv
  have h12 : DStay Γ (A2.setE Γ1 x E) [] := h1.setE fun E0 h0 _ _ _ => by rw [hx] at h0; cases h0
  exact ((h12.trans h2 fun _ h => h).exitScope (x := x)) v E0 hv hd hos (by simp [hvx])

theorem DStay.moveOut {Γ : Ctx} {y : Var} {E : Entry} (hy : Γ y = some E) (e : Eff) (hv : Bool) :
    DStay Γ (A2.setE (A2.kill e hv y Γ) y { E with live := false, dtor := false }) [] :=
  ((DStay.refl Γ []).kill e hv y).setE fun E0 h0 hd hos _ => by
    rw [hy] at h0; cases h0; exact ⟨hd, hos⟩

theorem PushArg.dstay {Γ : Ctx} {F : List Var} {y : Var} {E : Entry} {t : Ty} {D : List Dep}
    {Γ1 : Ctx} (hy : Γ y = some E) (h : PushArg Γ F y E t D Γ1) : DStay Γ Γ1 [] := by
  cases h with
  | move => exact DStay.moveOut hy _ _
  | int => exact DStay.refl Γ []
  | slice => exact DStay.refl Γ []

theorem RhsT.dstay {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (h : RhsT Γ F r E Γ1) :
    DStay Γ Γ1 [] := by
  cases h with
  | moveOwn hy => exact DStay.moveOut hy _ _
  | pop => exact (DStay.refl Γ []).kill _ _ _
  | pair hy _ hp1 hz _ hp2 _ => exact (hp1.dstay hy).trans (hp2.dstay hz) fun _ h => h
  | inl hy _ hp _ => exact hp.dstay hy
  | inr hy _ hp _ => exact hp.dstay hy
  | takel hy => exact DStay.moveOut hy _ _
  | taker hy => exact DStay.moveOut hy _ _
  | pack hy _ _ hp _ => exact hp.dstay hy
  | _ => exact DStay.refl Γ []

theorem DStay.killNames {Γ Γ' : Ctx} {sp : List Var} (h : DStay Γ Γ' sp) :
    ∀ ds, DStay Γ (A2.killNames ds Γ') sp
  | [] => h
  | d :: ds => show DStay Γ (A2.kill d.kind.bound false d.root (A2.killNames ds Γ')) sp from
      (DStay.killNames h ds).kill _ _ _

/-- A call moves a `sink` argument and changes an `inout` one as it is. -/
theorem DStay.callPostAux {Γ0 : Ctx} {fn : Fn} {args : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx), DStay Γ0 Γ [] →
      DStay Γ0 (A2.callPostAux Γ0 fn args ps as i Γ) [] := by
  intro ps
  induction ps with
  | nil => intro as i Γ h; cases as <;> simpa [A2.callPostAux] using h
  | cons p ps ih =>
    intro as i Γ h
    obtain ⟨pm, t⟩ := p
    cases as with
    | nil => cases pm <;> simpa [A2.callPostAux] using h
    | cons a as =>
      cases pm with
      | inp => simpa [A2.callPostAux] using ih as (i + 1) Γ h
      | sink =>
        simp only [A2.callPostAux]
        refine ih as (i + 1) _ ((h.kill _ _ _).setE fun E0 h0 hd hos _ => ?_)
        simp only [argE, h0, Option.getD_some]; exact ⟨hd, hos⟩
      | inout b =>
        simp only [A2.callPostAux]
        refine ih as (i + 1) _ ((h.kill _ _ _).setE fun E0 h0 hd hos _ => ?_)
        simp only [argE, h0, Option.getD_some]; exact ⟨hd, hos⟩

theorem CallT.dstay {P : Prog} {Γ : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    {Γ' : Ctx} (h : CallT P Γ F f args E Γ') : DStay Γ Γ' [] := by
  obtain ⟨fn, _, _, _, _, _, _, rfl⟩ := h
  exact (DStay.callPostAux (fn := fn) (args := args) fn.params args 0 Γ (DStay.refl Γ [])).killNames _

/-- A2-drop.2: a statement's typing keeps every binding `letd` made outside
    the running scopes: its flag never changes. -/
theorem StmtT.dstay {P : Prog} {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx} (h : StmtT P Γ F s Δ) :
    DStay Γ Δ s.spine := by
  have src0 : ∀ {Γ Δ : Ctx} {s : Stmt}, s.src = true → DStay Γ Δ s.spine → DStay Γ Δ [] :=
    fun hs h => by rwa [src_spine hs] at h
  induction h with
  | skip => exact DStay.refl _ _
  | seq hb _ _ iha ihb => exact iha.trans (src0 hb ihb) fun _ _ h => by cases h
  | letv hs hx _ hr _ _ ih => exact DStay.bind hx hr.dstay (src0 hs ih)
  | letcall hs hx _ hc _ _ ih => exact DStay.bind hx hc.dstay (src0 hs ih)
  | scope _ _ _ _ ih => exact ih.exitScope
  | rbind _ _ _ _ _ _ _ ih => exact ih.exitRoot _
  | frozen _ _ ih => exact ih
  | assign hx _ _ hr _ _ _ _ _ hdb =>
    exact (hr.dstay.kill _ _ _).setE fun E0 h0 hd _ _ => by rw [hx] at h0; cases h0; rw [hdb] at hd; cases hd
  | ite ha _ _ _ _ iha _ => exact src0 ha iha
  | «while» => exact DStay.refl _ _
  | push hx _ _ _ _ hy _ _ _ hpa _ hx1 _ _ _ =>
    refine ((hpa.dstay hy).kill _ _ _).setE fun E0 h0 hd hos _ => ?_
    obtain ⟨E1, h1, hd1, hos1⟩ := (hpa.dstay hy) _ E0 h0 hd hos (by simp)
    rw [hx1] at h1; cases h1
    exact ⟨hd1, hos1⟩
  | free hx => exact DStay.moveOut hx _ _
  | sub hw _ hw' ih =>
    rcases hw' with rfl | hw'
    · exact ih.weaker_left hw
    · exact (ih.weaker_right hw').weaker_left hw
  | panic _ _ _ _ _ hst => exact hst
  | letrec hs hx _ _ _ _ _ hc _ _ ih => exact DStay.bind hx hc.dstay (src0 hs ih)
  | @unpair Γ Δ F y x z k E a b hks hy _ _ _ _ hx hz hxz _ _ _ _ _ _ _ ih =>
    have hzy : z ≠ y := fun e => by rw [e, hy] at hz; cases hz
    have hz1 : (A2.setE (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) x
        (compE E a)) z = none := by
      simp [A2.setE, upd_ne _ _ (Ne.symm hxz), upd_ne _ _ hzy, A2.kill, hz]
    exact DStay.bind hx (DStay.moveOut hy _ _) (DStay.bind hz1 (DStay.refl _ []) (src0 hks ih))
  | callc hk hx _ _ _ _ _ _ _ hc _ _ _ ih => exact DStay.bind hx hc.dstay (src0 hk ih)
  | catchR _ _ _ _ _ hst _ => exact hst
  | letd hs hx _ hr _ _ _ _ _ _ ih => exact DStay.bind hx hr.dstay (src0 hs ih)
  | scopeD _ _ _ _ _ _ _ _ ih => exact ih.exitScope

theorem HeapOK.set_bor {m : Mem} (hh : HeapOK m) (x : Var) (w : Option Val) :
    HeapOK (m.set x ⟨false, w⟩) := by
  have hown : ∀ o U, OwnedAt (m.set x ⟨false, w⟩) o U → OwnedAt m o U := fun o U h => by
    rcases ownedAt_set.mp h with ⟨_, h⟩ | ⟨_, h⟩
    · cases h
    · exact h
  exact ⟨fun o U h => hh.nodup o U (hown o U h),
    fun o1 o2 U1 U2 hne h1 h2 => hh.disj o1 o2 U1 U2 hne (hown o1 U1 h1) (hown o2 U2 h2),
    fun o U h => hh.alloc o U (hown o U h), fun o U h => hh.self o U (hown o U h), hh.bpay⟩

end A2
