import A2.CallInv

/-! A2 — a call through a package (a closure or a trait object).

The package's code is not known where the call is typed; what is known is
its signature, and that every package names code of its signature
(`MemCodes`).  The call opens the package: its environment, lent, is bound
to a fresh binding `e` for the duration of the call, and the code is called
on `e` and the argument as an ordinary call.  So the call case is the
ordinary call case, inside the scope of `e`. -/

namespace A2

/-- A live package binding holds a package of its signature. -/
theorem pkg_slot {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {c : Var} {E : Entry} (hc : Γ c = some E)
    (hl : E.live = true) {a r : Ty} (ht : E.ty = .fn a r) :
    ∃ o f te env, m.st c = some ⟨o, some (.pkg f te a r env)⟩ := by
  rcases hi.mode_cases hc with hm | hm | hm
  · obtain ⟨T, hT, hw, _⟩ := hi.own_val hc hl (by rw [hm]; rfl)
    rw [ht] at hw; cases hw
    exact ⟨_, _, _, _, hT⟩
  all_goals
    obtain ⟨v, hv, hok⟩ := hi.bor_val hc hl (by rw [hm]; rfl)
    rw [ht] at hok; obtain ⟨f, te, x, rfl, _⟩ := valOK_fn.mp hok
    exact ⟨_, _, _, _, hv⟩

/-- A live binding can be lent. -/
theorem lend_exists {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) : ∃ sl v, m.st y = some sl ∧ lendSlot sl = some v := by
  rcases hi.mode_cases hy with hm | hm | hm
  · obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
    exact ⟨_, _, hT, rfl⟩
  all_goals
    obtain ⟨v, hv, _⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
    exact ⟨_, _, hv, rfl⟩

/-- The code a package names, and what its signature says. -/
theorem code_of {P : Prog} (hP : ProgOK P) {f : Nat} {te a r : Ty} (hc : CodeOK P f te a r) :
    ∃ fn, P[f]? = some fn ∧ fn.params = [(.inp, te), (.inp, a)] ∧ fn.resTy = r ∧
      fn.resOwn = r.owning ∧ (∀ jk ∈ fn.lends, jk.1 = 1) ∧ (∀ jk ∈ fn.rholds, jk.1 = 1) ∧
      te.ok = true ∧ FnOK P fn := by
  obtain ⟨fn, hf, hps, hrt, hro, hl, hr⟩ := hc
  obtain ⟨_, _, _, _, _, hpar, _⟩ := hP fn (List.mem_of_getElem? hf)
  exact ⟨fn, hf, hps, hrt, hro, hl, hr, (hpar (.inp, te) (by rw [hps]; simp)).1,
    hP fn (List.mem_of_getElem? hf)⟩

/-- The progress case of a call through a package. -/
theorem cloProgress {P : Prog} (hP : ProgOK P) {Γ : Ctx} {x c z : Var} {k : Stmt} {Ec Ez : Entry}
    {a r : Ty} {m : Mem} (hx : Γ x = none) (hc : Γ c = some Ec) (hlc : Ec.live = true)
    (htc : Ec.ty = .fn a r) (hz : Γ z = some Ez) (hlz : Ez.live = true) (_ : Ez.ty = a)
    (hcd : MemCodes P m) (hi : MInv m Γ) : ∃ s, Step P m (.callc x c z k) s := by
  obtain ⟨o, f, te, env, hslot⟩ := pkg_slot hi hc hlc htc
  obtain ⟨fn, hf, hps, _⟩ := code_of hP (hcd c o _ f te a r env hslot (Sub.refl _))
  have hmx : m.st x = none := by
    have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
  obtain ⟨sl, w, hzs, hzl⟩ := lend_exists hi hz hlz
  have hzlt : z < m.nv := hi.nvSt z (by rw [hzs]; rfl)
  have hz1 : z ≠ m.nv := fun e => by have := vlt hzlt; have := veq e; omega
  have hz2 : z ≠ m.nv + 1 + 0 := fun e => by have := vlt hzlt; have := veq e; omega
  have hb : BindParams (envMem m env) fn.params [m.nv, z] (m.nv + 1) 0
      (((envMem m env).set (m.nv + 1 + 0) ⟨false, some (lendOf env)⟩).set (m.nv + 1 + (0 + 1))
        ⟨false, some w⟩) := by
    rw [hps]
    refine BindParams.inp (sl := ⟨false, some (lendOf env)⟩) (by simp [envMem, Mem.set]) rfl
      (BindParams.inp ?_ hzl BindParams.nil)
    simp [envMem, Mem.set, upd_ne _ _ hz1, upd_ne _ _ hz2, hzs]
  exact ⟨_, Step.callc hslot hf hmx hb⟩

/-! ### Preservation -/

theorem RhsOut.of_st {m m' : Mem} {Γ : Ctx} {E : Entry} {v : Val} {o : Bool} (h : RhsOut m Γ E v o)
    (hst : m'.st = m.st) (ha : m'.alloc = m.alloc) (hn : m'.nid = m.nid) : RhsOut m' Γ E v o := by
  have hk : ∀ dep : Dep, VKeep m m' dep ∧ HKeep m m' dep := fun dep => by
    have hr : RootKeep m m' dep.root := fun n hn => rootNode_st hst hn
    exact ⟨hr.vkeep, hr.hkeep⟩
  refine ⟨h.own, h.mode, h.live, h.tyok, h.wf, fun hm => ?_,
    fun hm => (h.valBor hm).keep (fun d _ => hk d) (fun d _ => hk d)⟩
  obtain ⟨h1, h2, h3, h4, h5, h6, h7⟩ := h.valOwn hm
  refine ⟨h1, h2, h3.keep (fun d _ => (hk d).1), h4, fun i hi => by rw [ha, hn]; exact h5 i hi,
    fun x U hU => h6 x U (by unfold OwnedAt at hU ⊢; rw [hst] at hU; exact hU), h7⟩

theorem projE_ty (y : Var) (E : Entry) (t : Ty) : (projE y E t).ty = t := by cases t <;> rfl
theorem projE_live (y : Var) (E : Entry) (t : Ty) : (projE y E t).live = true := by cases t <;> rfl
theorem projE_mode (y : Var) (E : Entry) (t : Ty) : (projE y E t).mode = .bor := by cases t <;> rfl
theorem projE_held (y : Var) (E : Entry) {t : Ty} (ht : t ≠ .int) : (projE y E t).held = E.held := by
  cases t <;> first | rfl | exact absurd rfl ht

/-- An effect on a binding nothing depends on ends nothing. -/
theorem killE_fresh {Γ : Ctx} (hw : CtxWF Γ) {e : Var} (he : Γ e = none) {v : Var} {E : Entry}
    (hv : Γ v = some E) (eff : Eff) (b : Bool) : killE eff b e E = E := by
  unfold killE
  split
  · rename_i hh
    cases hl : E.live with
    | false => cases E; simp_all
    | true =>
      exfalso
      unfold hits at hh
      simp only [Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, List.any_eq_true] at hh
      obtain ⟨hn, d, hd, hde, _⟩ := hh
      have hn' : E.ty ≠ .int ∨ E.mode = .rootb := by
        rcases hn with h | h
        · exact Or.inl h
        · exact Or.inr h
      obtain ⟨Er, hEr, _⟩ := hw v E hv hl hn' d.root (List.mem_map_of_mem hd)
      rw [hde, he] at hEr; cases hEr
  · rfl

/-- Leaving the scope of a fresh binding nothing depends on leaves the
    context as it was. -/
theorem weaker_drop {Γ : Ctx} (hw : CtxWF Γ) {e x : Var} (he : Γ e = none) (hxe : x ≠ e) {Ee E E' : Entry}
    (hE : ∀ d ∈ E.vdeps, d.root ≠ e) (hEw : EntryWeaker E E') (hw' : CtxWF (setE Γ x E')) :
    Weaker (exitScope e (setE (setE Γ e Ee) x E)) (setE Γ x E') := by
  have hkE : killE .replace false e E = E := by
    unfold killE
    rw [if_neg]
    unfold hits
    simp only [Bool.and_eq_true, List.any_eq_true, beq_iff_eq, not_and, not_exists]
    intro _ d hd hde
    exact absurd hde (hE d hd)
  refine ⟨fun v => ⟨?_, fun E1 E2 h1 h2 => ?_⟩, hw'⟩
  · by_cases hve : v = e
    · subst hve; simp [exitScope, setE, upd_ne _ _ hxe.symm, he]
    · by_cases hvx : v = x
      · subst hvx; simp [exitScope, setE, upd_ne _ _ hve, kill]
      · simp [exitScope, setE, upd_ne _ _ hve, upd_ne _ _ hvx, kill]
  · by_cases hve : v = e
    · subst hve; simp [exitScope] at h1
    · by_cases hvx : v = x
      · subst hvx
        simp only [exitScope, setE, upd_ne _ _ hve, kill, upd_same, Option.map_some, Option.some.injEq] at h1
        simp only [setE, upd_same, Option.some.injEq] at h2
        rw [← h1, ← h2, hkE]; exact hEw
      · simp only [exitScope, setE, upd_ne _ _ hve, kill, upd_ne _ _ hvx] at h1
        simp only [setE, upd_ne _ _ hvx] at h2
        rw [h2] at h1
        simp only [Option.map_some, Option.some.injEq] at h1
        rw [← h1, killE_fresh hw he h2]
        exact ⟨rfl, rfl, fun _ => rfl, fun hl => ⟨hl, fun _ => List.Subset.refl _, List.Subset.refl _⟩⟩

/-- What the code of a package lends and holds, at the call: what the
    argument lends, and what the package and the argument hold. -/
theorem clo_deps {Γ : Ctx} {e z : Var} {Ee Ec Ez : Entry} (hze : z ≠ e) (hz : Γ z = some Ez)
    (hEe : Ee.ty = .int ∨ Ee.held = Ec.held) {L : List (Nat × Kind)} (hL : ∀ jk ∈ L, jk.1 = 1) :
    L.flatMap (argDeps (setE Γ e Ee) [e, z]) ++ heldOfArgs (setE Γ e Ee) [e, z] ⊆
      (if Ez.ty = .int then [] else deriveAll z Ez) ++
        allKinds (roots Ec.held ++ (if Ez.ty = .int then [] else roots Ez.held)) := by
  have hae : argE (setE Γ e Ee) e = Ee := by simp [argE, setE]
  have haz : argE (setE Γ e Ee) z = Ez := by simp [argE, setE, upd_ne _ _ hze, hz]
  intro d hd
  rcases List.mem_append.mp hd with hd | hd
  · obtain ⟨jk, hjk, hdj⟩ := List.mem_flatMap.mp hd
    obtain ⟨j, k⟩ := jk
    have hj : j = 1 := hL _ hjk
    subst hj
    unfold argDeps at hdj
    have hg : [e, z].getD 1 0 = z := rfl
    simp only [hg, haz] at hdj
    split at hdj
    · simp at hdj
    · rename_i hn
      refine List.mem_append_left _ ?_
      rw [if_neg hn]
      cases k <;> simp [deriveAll, hdj]
  · unfold heldOfArgs at hd
    have hr := RSetup.mem_allKinds_iff.mp hd
    simp only [List.flatMap_cons, List.flatMap_nil, hae, haz, List.append_nil, List.mem_append] at hr
    refine List.mem_append_right _ (RSetup.mem_allKinds_iff.mpr ?_)
    rcases hr with hr | hr
    · split at hr
      · simp at hr
      · rename_i hn
        rcases hEe with h | h
        · exact absurd h hn
        · rw [h] at hr; exact List.mem_append_left _ hr
    · exact List.mem_append_right _ hr

/-- The case of a call through a package. -/
theorem cloCase {P : Prog} (hP : ProgOK P) : CloCase P := by
  intro Γ F x c z k Ec Ez a r Δ m m' s' hk hx hxF hc hlc htc hz hlz htz hkT hcd hi hst
  cases hst with
  | @callc m1 _ _ _ _ o f te a' r' env fn hslot hf hmx hb =>
  -- the package's signature is the binding's
  have hsig : a' = a ∧ r' = r := by
    rcases hi.mode_cases hc with hm | hm | hm
    · obtain ⟨T, hT, hw, _⟩ := hi.own_val hc hlc (by rw [hm]; rfl)
      rw [hT] at hslot; cases hslot
      rw [htc] at hw; cases hw; exact ⟨rfl, rfl⟩
    all_goals
      obtain ⟨v, hv, hok⟩ := hi.bor_val hc hlc (by rw [hm]; rfl)
      rw [hv] at hslot; cases hslot
      rw [htc] at hok; cases hok; exact ⟨rfl, rfl⟩
  obtain ⟨rfl, rfl⟩ := hsig
  obtain ⟨fn', hf', hps, hrt, hro, hlends, hrholds, hteok, _⟩ :=
    code_of hP (hcd c o _ f te a' r' env hslot (Sub.refl _))
  rw [hf] at hf'; cases hf'
  -- where things are
  have hxlt : x < m.nv := hi.nvS x (by simp [Stmt.vars])
  have hzlt : z < m.nv := hi.nvS z (by simp [Stmt.vars])
  have hΓe : Γ m.nv = none := by
    cases h : Γ m.nv with
    | none => rfl
    | some E =>
      have := hi.nvSt m.nv (by rw [← hi.dom, h]; rfl)
      exact absurd this (Nat.lt_irrefl _)
  have hxe : x ≠ m.nv := fun e => by have := vlt hxlt; have := veq e; omega
  have hze : z ≠ m.nv := fun e => by have := vlt hzlt; have := veq e; omega
  have hFe : m.nv ∉ F := fun h => by have := vlt (hi.nvF _ h); omega
  -- the environment, lent, bound to `e = m.nv`
  let Ee := projE c Ec te
  have hout : RhsOut m Γ Ee (lendOf env) false := by
    refine out_comp hi.toMInv hc hlc (by rw [htc]; simp) hslot Child.pkg (Top.pkg (Top.refl _)) hteok
      (fun hw hvs => ?_) (fun h => ?_)
    · rw [htc] at hw hvs
      cases hw with
      | pkg hwe => exact ⟨hwe, fun s v hin => hvs s v (ViewIn.pkg hin)⟩
    · rw [htc] at h
      cases h with
      | pkg h => exact h
  let mn : Mem := { m with nv := m.nv + 1 }
  have hin : MInv mn Γ :=
    hi.toMInv.of_st rfl ⟨hi.heap.nodup, hi.heap.disj, hi.heap.alloc, hi.heap.self⟩ (Nat.le_succ _)
  have hie : MInv (envMem m env) (setE Γ m.nv Ee) :=
    hin.add hΓe (Nat.lt_succ_self _) (hout.of_st rfl rfl rfl)
  let Γe := setE Γ m.nv Ee
  have hEe : Γe m.nv = some Ee := by simp [Γe, setE]
  have hzE : Γe z = some Ez := by simp [Γe, setE, upd_ne _ _ hze, hz]
  have hIe : Inv (envMem m env) Γe F (.letcall x f [m.nv, z] k) :=
    { toMInv := hie
      nvS := by
        intro v hv
        show v < m.nv + 1
        simp only [Stmt.vars, List.mem_cons, List.cons_append, List.mem_append] at hv
        rcases hv with rfl | rfl | rfl | hv | hv
        · exact Nat.lt_succ_of_lt hxlt
        · exact Nat.lt_succ_self _
        · exact Nat.lt_succ_of_lt hzlt
        · simp at hv
        · exact Nat.lt_succ_of_lt (hi.nvS v (by simp [Stmt.vars, hv]))
      nvF := fun v hv => Nat.lt_succ_of_lt (hi.nvF v hv)
      anch := fun p E hp hm _ => by
        by_cases hpe : p = m.nv
        · subst hpe; simp only [Γe, setE, upd_same, Option.some.injEq] at hp; subst hp
          rw [projE_mode] at hm; cases hm
        · simp only [Γe, setE, upd_ne _ _ hpe] at hp
          exact hi.anch p E hp hm (by simp [Stmt.spine])
      spineNd := by simp [Stmt.spine]
      spineDom := by simp [Stmt.spine]
      catchOK := catchOK_src (by simp [Stmt.src, hk])
      cover := fun i hia => by
        obtain ⟨o', T, hT, hiT⟩ := hi.cover i hia
        have ho : o' ≠ m.nv := fun e => by
          subst e; unfold OwnedAt at hT
          have := hi.dom m.nv; rw [hΓe, hT] at this; cases this
        exact ⟨o', T, by unfold OwnedAt at hT ⊢; simp [envMem, Mem.set, upd_ne _ _ ho, hT], hiT⟩ }
  -- the call, as an ordinary call of the code
  have hlen : fn.params.length = 2 := by rw [hps]; rfl
  have hcT : CallT P Γe F f [m.nv, z] (callRes Γe fn [m.nv, z]) (callPost Γe fn [m.nv, z]) := by
    refine ⟨fn, hf, by rw [hlen]; rfl, fun i hi' => ?_, rfl, rfl⟩
    have hi2 : i < 2 := hlen ▸ hi'
    rcases (show i = 0 ∨ i = 1 by omega) with rfl | rfl
    · have hp0 : fn.params[0] = (.inp, te) := by simp [hps]
      refine ⟨Ee, hEe, projE_live _ _ _, ?_, fun hmv => ?_⟩
      · rw [hp0]; exact projE_ty _ _ _
      · rw [hp0] at hmv; cases hmv
    · have hp1 : fn.params[1] = (.inp, a') := by simp [hps]
      refine ⟨Ez, hzE, hlz, ?_, fun hmv => ?_⟩
      · rw [hp1]; exact htz
      · rw [hp1] at hmv; cases hmv
  have hxe' : Γe x = none := by simp [Γe, setE, upd_ne _ _ hxe, hx]
  have h := callH_of hP hf hxe' hxF hcT hIe
  have hI := h.inv hIe hb
  -- the call's inside, typed
  have hpost : callPost Γe fn [m.nv, z] = Γe := by simp [callPost, hps, callPostAux]
  have hIn := h.typedIn
  rw [hpost] at hIn
  have hρ : ∀ v, callRen fn.params [m.nv, z] (envMem m env).nv v ≠ m.nv := by
    intro v hv
    have hr : callRen fn.params [m.nv, z] (envMem m env).nv v = m.nv + 1 + v := by
      unfold callRen; rw [hps]; rcases v with _ | _ | v <;> simp [envMem]
    rw [hr] at hv; have := veq hv; omega
  have hΓ'e : (callS Γe F fn [m.nv, z] (envMem m env).nv x).canon (sigCtx fn) m.nv = some Ee.clean := by
    rw [RSetup.canon_frame _ hρ, h.frame_of hρ hxe.symm, hpost, hEe]; rfl
  have hse := StmtT.scope (P := P) ⟨Ee.clean, hΓ'e, by rw [clean_mode, projE_mode]; simp⟩ hFe hIn
  -- the continuation, in the context the call leaves
  have hEeheld : Ee.ty = .int ∨ Ee.held = Ec.held := by
    by_cases ht : te = .int
    · left; rw [projE_ty]; exact ht
    · right; exact projE_held _ _ ht
  have hRw : EntryWeaker (callRes Γe fn [m.nv, z]) (cloRes Ec z Ez r') := by
    refine RSetup.EntryWeaker.mk' (by simp [cloRes, callRes, hrt]) (by simp [cloRes, callRes, resMode, hro])
      (resMode_ne' fn) rfl (fun _ => ?_) ?_
    · exact clo_deps hze hz hEeheld hlends
    · exact clo_deps hze hz hEeheld hrholds
  have hRe : ∀ d ∈ (callRes Γe fn [m.nv, z]).vdeps, d.root ≠ m.nv := by
    intro d hd he
    have hdD : d ∈ (cloRes Ec z Ez r').held := by
      unfold Entry.vdeps at hd
      rcases List.mem_append.mp hd with hd | hd
      · split at hd
        · simp at hd
        · exact clo_deps hze hz hEeheld hlends hd
      · exact clo_deps hze hz hEeheld hrholds hd
    obtain ⟨Er, hEr, _⟩ := cloRes_roots hi.wf hc hlc htc hz hlz r' d.root
      (List.mem_map_of_mem (List.mem_append_right _ hdD))
    rw [he, hΓe] at hEr; cases hEr
  have hW : Weaker (exitScope m.nv (setE Γe x (callRes Γe fn [m.nv, z]))) (setE Γ x (cloRes Ec z Ez r')) :=
    weaker_drop hi.wf hΓe hxe hRe hRw (hi.wf.add hx (fun _ _ => cloRes_roots hi.wf hc hlc htc hz hlz r'))
  have hT := StmtT.scope (P := P) ⟨callX fn, h.canon_x _, by simp [callX, resMode_ne' fn]⟩ h.xF
    (StmtT.seq hk hse (hkT.weakenIn hW))
  -- where the call's scopes are
  have hbs := h.body_spine (m := envMem m env)
  have hcin : ∀ v ∈ (callIn fn [m.nv, z] (m.nv + 1) x).spine, m.nv < v := by
    intro v hv
    rw [callIn_spine] at hv
    simp only [envMem] at hbs
    rw [hbs, List.append_nil] at hv
    rcases List.mem_cons.mp hv with rfl | hv
    · omega
    · obtain ⟨k', _, _, _, rfl⟩ := mem_wrapSpine hv; omega
  have hcsp : (callStmt fn [m.nv, z] (m.nv + 1) x k).spine = x :: (callIn fn [m.nv, z] (m.nv + 1) x).spine := by
    simp [callStmt, Stmt.spine]
  refine ⟨_, hT, ?_, by show m.nv ≤ m.nv + 1 + fn.nvars; omega, ⟨fun v E hv _ => ?_, fun v E' hv hvs => ?_⟩,
    fun v hv => ?_⟩
  · have hnd : (callStmt fn [m.nv, z] (m.nv + 1) x k).spine.Nodup := hI.spineNd
    have hdom : ∀ v ∈ (callStmt fn [m.nv, z] (m.nv + 1) x k).spine, ∃ E,
        (callS Γe F fn [m.nv, z] (envMem m env).nv x).canon (sigCtx fn) v = some E := hI.spineDom
    have hnv : ∀ v ∈ (callStmt fn [m.nv, z] (m.nv + 1) x k).vars, v < m.nv + 1 + fn.nvars := hI.nvS
    rw [hcsp] at hnd hdom
    exact { toMInv := hI.toMInv
            nvS := fun v hv => by
              simp only [Stmt.vars, List.mem_cons, List.mem_append] at hv
              rcases hv with rfl | (rfl | hv) | hv
              · exact hnv _ (by simp [callStmt, Stmt.vars])
              · show m.nv < m.nv + 1 + fn.nvars; omega
              · exact hnv _ (by simp [callStmt, Stmt.vars, hv])
              · exact hnv _ (by simp [callStmt, Stmt.vars, hv])
            nvF := hI.nvF
            anch := fun p E hp hm hs => hI.anch p E hp hm (fun h' => hs (by
              change p ∈ (callStmt fn [m.nv, z] (m.nv + 1) x k).spine at h'
              rw [hcsp] at h'
              simp only [Stmt.spine, List.mem_cons] at h' ⊢
              rcases h' with h' | h'
              · exact Or.inl h'
              · exact Or.inr (Or.inr h')))
            spineNd := by
              simp only [Stmt.spine, List.nodup_cons, List.mem_cons, not_or] at hnd ⊢
              exact ⟨⟨hxe, hnd.1⟩, fun h' => Nat.lt_irrefl _ (hcin _ h'), hnd.2⟩
            spineDom := fun v hv => by
              simp only [Stmt.spine, List.mem_cons] at hv
              rcases hv with rfl | rfl | hv
              · exact hdom _ (List.mem_cons_self)
              · exact ⟨_, hΓ'e⟩
              · exact hdom _ (List.mem_cons_of_mem _ hv)
            catchOK := hI.catchOK
            cover := hI.cover }
  · have hve : v ≠ m.nv := fun e => by rw [e, hΓe] at hv; cases hv
    have hv' : Γe v = some E := by simp [Γe, setE, upd_ne _ _ hve, hv]
    obtain ⟨hns, rest⟩ := (h.keep (f := f) (k := k)).1 v E hv' (by simp [Stmt.spine])
    refine ⟨fun h' => ?_, rest⟩
    change v ∉ (callStmt fn [m.nv, z] (m.nv + 1) x k).spine at hns
    rw [hcsp] at hns
    simp only [Stmt.spine, List.mem_cons] at h' hns
    rcases h' with h' | h' | h'
    · exact hns (Or.inl h')
    · exact hve h'
    · exact hns (Or.inr h')
  · have hve : v ≠ m.nv := fun e => hvs (by simp [Stmt.spine, e])
    have hns : v ∉ (callStmt fn [m.nv, z] (m.nv + 1) x k).spine := by
      rw [hcsp]; simp only [Stmt.spine, List.mem_cons, not_or] at hvs ⊢
      exact ⟨hvs.1, hvs.2.2⟩
    obtain ⟨_, E0, h0⟩ := (h.keep (f := f) (k := k)).2 v E' hv hns
    exact ⟨by simp [Stmt.spine], E0, by simpa [Γe, setE, upd_ne _ _ hve] using h0⟩
  · have hve : v ≠ m.nv := fun e => hFe (e ▸ hv)
    refine Eq.trans (h.frz hIe.toMInv hb v hv) ?_
    simp [envMem, Mem.set, upd_ne _ _ hve]

end A2
