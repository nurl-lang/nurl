import A2.CallMem
import A2.FrameCall
import A2.KillVarsStep
import A2.SrcKeep
import A2.CapsLive

/-! A2 — the call step preserves the invariant and is typed: the call case
of preservation, and the call case of progress. -/

namespace A2

theorem callStmt_spine (fn : Fn) (args : List Var) (base : Nat) (x : Var) (k : Stmt) :
    (callStmt fn args base x k).spine =
      x :: (base + fn.params.length) :: (wrapSpine fn.params base 0 ++
        (fn.body.rename (callRen fn.params args base)).spine) := by
  simp [callStmt, callIn, Stmt.spine, spine_wrap]

theorem callStmt_vars (fn : Fn) (args : List Var) (base : Nat) (x : Var) (k : Stmt) :
    (callStmt fn args base x k).vars =
      x :: ((base + fn.params.length) :: (zOf fn args base ++ (wrapSpine fn.params base 0 ++
        fn.body.vars.map (callRen fn.params args base))) ++ [x, base + fn.params.length]) ++ k.vars := by
  simp [callStmt, callIn, Stmt.vars, Rhs.vars, vars_wrap, Stmt.vars_rename, zOf]

/-- A call's parameter depends on nothing bound after it, and every frame
    opened inside it is bound after it. -/
theorem pinOK_wrap {Γ : Ctx} {s : Stmt}
    (hlt : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r < p)
    (hs : PinOK Γ s) (hsp : s.spine = []) :
    ∀ (ps : List (PMode × Ty)) (base i : Nat), PinOK Γ (wrapParams ps base i s) := by
  intro ps
  induction ps with
  | nil => intro base i; exact hs
  | cons p ps ih =>
    intro base i
    obtain ⟨pm, t⟩ := p
    cases pm with
    | inp =>
      refine ⟨fun E hE hm r hr hrs => ?_, ih base (i + 1)⟩
      have hl := hlt _ E hE hm r hr
      rw [spine_wrap, hsp, List.append_nil] at hrs
      obtain ⟨k, _, _, _, rfl⟩ := mem_wrapSpine hrs
      -- `omega` reads only facts typed at `Nat`, and `hl` is typed at `Var`.
      have hl' : base + (i + 1) + k < base + i := hl
      omega
    | sink => exact ih base (i + 1)
    | inout b => exact ih base (i + 1)

theorem mem_wrapSpine_of : ∀ {ps : List (PMode × Ty)} {base i k : Nat} {p : PMode × Ty},
    ps[k]? = some p → (∀ b, p.1 ≠ .inout b) → base + i + k ∈ wrapSpine ps base i := by
  intro ps
  induction ps with
  | nil => intro base i k p hk; simp at hk
  | cons q ps ih =>
    intro base i k p hk hp
    obtain ⟨pm, t⟩ := q
    cases k with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at hk
      subst hk
      cases pm with
      | inout b => exact absurd rfl (hp b)
      | inp => simp [wrapSpine]
      | sink => simp [wrapSpine]
    | succ k =>
      have := ih (base := base) (i := i + 1) (k := k) (by simpa using hk) hp
      rw [show base + (i + 1) + k = base + i + (k + 1) by omega] at this
      cases pm with
      | inout b => exact this
      | inp => exact List.mem_cons_of_mem _ this
      | sink => exact List.mem_cons_of_mem _ this

theorem catchOK_wrap {m : Mem} (s : Stmt) : ∀ (ps : List (PMode × Ty)) (base i : Nat),
    CatchOK m (wrapParams ps base i s) = CatchOK m s := by
  intro ps
  induction ps with
  | nil => intro base i; rfl
  | cons p ps ih =>
    intro base i
    obtain ⟨pm, t⟩ := p
    cases pm <;> simp [wrapParams, CatchOK, ih]

/-- A2-drop.2: a statement whose running scopes bind no `letd` binding
    keeps every frame's destructor views: there is none. -/
theorem DtorPinOK.of_spine_dbind {Γ : Ctx} {s : Stmt}
    (h : ∀ v ∈ s.spine, ∀ E, Γ v = some E → E.dbind = false) : DtorPinOK Γ s := by
  have hin : ∀ x k, (∀ E, Γ x = some E → E.dbind = false) → DtorIn Γ x k :=
    fun x k hx E hE hd => by rw [hx E hE] at hd; cases hd
  induction s with
  | seq a _ iha _ => exact iha h
  | frozen _ k ih => exact ih h
  | block k ih => exact ih h
  | catchR _ _ k ih => exact ih h
  | scope x k ih =>
    exact ⟨hin x k (h x (by simp [Stmt.spine])), ih fun v hv => h v (by simp [Stmt.spine, hv])⟩
  | scopeD x _ k ih =>
    exact ⟨hin x k (h x (by simp [Stmt.spine])), ih fun v hv => h v (by simp [Stmt.spine, hv])⟩
  | rbind p k ih =>
    exact ⟨hin p k (h p (by simp [Stmt.spine])), ih fun v hv => h v (by simp [Stmt.spine, hv])⟩
  | scopeL _ _ x k ih =>
    exact ⟨hin x k (h x (by simp [Stmt.spine])), ih fun v hv => h v (by simp [Stmt.spine, hv])⟩
  | _ => trivial

namespace CallH
variable {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {fn : Fn} {args : List Var} {m : Mem}

theorem body_spine (h : CallH P Γ F x fn args m.nv) :
    (fn.body.rename (callRen fn.params args m.nv)).spine = [] := by
  obtain ⟨hsrc, _⟩ := h.fnok
  exact src_spine (by rw [RSetup.src_rename]; exact hsrc)

/-- A caller binding other than `x` is none of the call's running scopes. -/
theorem not_spine (h : CallH P Γ F x fn args m.nv) {k : Stmt} {r : Var} (hrlt : r < m.nv) (hrx : r ≠ x) :
    r ∉ (callStmt fn args m.nv x k).spine := by
  intro hrs
  rw [callStmt_spine, h.body_spine, List.append_nil] at hrs
  rcases List.mem_cons.mp hrs with h1 | h1
  · exact hrx h1
  rcases List.mem_cons.mp h1 with h2 | h2
  · rw [h2] at hrlt; exact Nat.lt_irrefl _ (Nat.lt_of_le_of_lt (Nat.le_add_right _ _) hrlt)
  · obtain ⟨k', _, _, _, he⟩ := mem_wrapSpine h2
    rw [he] at hrlt
    exact Nat.lt_irrefl _
      (Nat.lt_of_le_of_lt (Nat.le_trans (Nat.le_add_right m.nv 0) (Nat.le_add_right _ k')) hrlt)

/-- The call's running scopes bind none that `letd` made. -/
theorem spine_dbind (h : CallH P Γ F x fn args m.nv) {k : Stmt} :
    ∀ v ∈ (callStmt fn args m.nv x k).spine, ∀ E,
      (callS Γ F fn args m.nv x).canon (sigCtx fn) v = some E → E.dbind = false := by
  intro v hv E hE
  cases hd : E.dbind with
  | false => rfl
  | true =>
    exfalso
    obtain ⟨hren, hvx, _⟩ := h.dbind_frame hE hd
    rw [callStmt_spine, h.body_spine, List.append_nil] at hv
    rcases List.mem_cons.mp hv with rfl | hv
    · exact hvx rfl
    rcases List.mem_cons.mp hv with rfl | hv
    · exact hren fn.params.length (ren_res fn args m.nv)
    · obtain ⟨k', p, hk', hp, rfl⟩ := mem_wrapSpine hv
      apply hren k'
      unfold callRen; rw [hk']
      obtain ⟨pm, t⟩ := p
      cases pm with
      | inout b => exact absurd rfl (hp b)
      | _ => simp

/-- A2-drop.2: the call gives no binding `letd` made a new view. -/
theorem post_dkeep (h : CallH P Γ F x fn args m.nv) : DKeep Γ (callPost Γ fn args) [] :=
  (DKeep.callPostAux (fn := fn) (args := args) fn.params args 0 Γ (DKeep.refl Γ [])
    fun j hj b hb Ea ha hd => absurd hd (by rw [h.dsafe.2.2 j hj b hb Ea ha]; simp)).killNames _

theorem covers (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) (hc : Covers m) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) : Covers (callMem m m1 fn x) := by
  intro i hia
  have hal : (callMem m m1 fn x).alloc = m.alloc := (h.bind hb).1
  rw [hal] at hia
  rcases hc i hia with ⟨o, T, hT, hiT⟩ | ⟨k, bl, hk, hik⟩
  · obtain ⟨o', hT'⟩ := h.own_dst hi hb hT
    exact Or.inl ⟨o', T, hT', hiT⟩
  · exact Or.inr ⟨k, bl, by show m1.blk k = some bl; rw [hb.blk]; exact hk, hik⟩

theorem catchOK (h : CallH P Γ F x fn args m.nv) (m' : Mem) (k : Stmt) :
    CatchOK m' (callStmt fn args m.nv x k) := by
  have he : CatchOK m' (callStmt fn args m.nv x k) =
      CatchOK m' (wrapParams fn.params m.nv 0 (fn.body.rename (callRen fn.params args m.nv))) :=
    resFrame_catchOK m' fn _ _
  rw [he, catchOK_wrap]
  exact catchOK_src (by rw [RSetup.src_rename]; exact h.fnok.1)

theorem frz (h : CallH P Γ F x fn args m.nv) (_hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) : Frz F m (callMem m m1 fn x) := by
  intro v hv
  refine h.st_other hb (h.untouched_lt (h.Flt v hv) (fun e => h.xF (e ▸ hv)) fun k t hk he => ?_)
  have hkl := lt_of_get hk
  obtain ⟨_, _, _, _, hmv, _⟩ := h.arg k hkl
  rw [get_of hk] at hmv
  exact (hmv rfl).1 (he ▸ hv)

/-- AGORA-937 B4: **the call's frame keeps the closure-capture clause**:
    each slot a live binding of the frame reads is a live caller binding's,
    or an argument's value or what it lends (`BindParams.src`), and the
    frame's owned slots hold trees the caller's did (`BindParams.ownedBack`). -/
theorem liveCaps (h : CallH P Γ F x fn args m.nv) (hM : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) {w : Var} (hc : LiveCaps m Γ w) :
    LiveCaps (callMem m m1 fn x) ((callS Γ F fn args m.nv x).canon (sigCtx fn)) w := by
  have hargs : ∀ a ∈ args, ∃ E, Γ a = some E ∧ E.live = true := fun a ha => by
    obtain ⟨i, hi, rfl⟩ := List.getElem_of_mem ha
    obtain ⟨Ea, hEa, hl, _⟩ := h.arg i (by rw [← h.len]; exact hi)
    exact ⟨Ea, by simpa [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi] using hEa, hl⟩
  have hlt : ∀ a ∈ args, a < m.nv := fun a ha => by
    obtain ⟨E, hE, _⟩ := hargs a ha
    exact h.domlt a E hE
  -- the frame's slots are the bound ones, with the result slots emptied
  have hst : ∀ y o V, (callMem m m1 fn x).st y = some ⟨o, some V⟩ → m1.st y = some ⟨o, some V⟩ := by
    intro y o V hy
    unfold callMem at hy
    by_cases h1 : y = m.nv + fn.params.length
    · subst h1; simp [Mem.set, upd] at hy
    · by_cases h2 : y = x
      · subst h2; simp [Mem.set, upd, h1] at hy
      · simpa [Mem.set, upd, h1, h2] using hy
  have hob : ∀ y t, (callMem m m1 fn x).st y = some ⟨true, some t⟩ → ∃ z, m.st z = some ⟨true, some t⟩ :=
    fun y t hy => hb.ownedBack y t (hst y true t hy)
  intro v E o V hv hl hs
  refine LiveGood.mono (m := m) ?_ hob
  rcases hb.src hlt v o V (hst v o V hs) with h0 | ⟨a, ha, o', V0, hsa, hV⟩
  · -- a slot of the caller's: a live caller binding (an `inout` argument
    -- or an untouched one)
    have hvlt : v < m.nv := hM.nvSt v (by rw [h0]; rfl)
    rcases h.ctx_cases v with ⟨rfl, _⟩ | ⟨rfl, _⟩ | ⟨k', t, _, rfl, _⟩ | ⟨k', t, _, rfl, _⟩ |
        ⟨k', b', t, hk', rfl, _⟩ | ⟨_, _, hc'⟩ | ⟨hc', _⟩
    · have := hM.dom v; rw [h.fresh, h0] at this; cases this
    · have := vlt hvlt; omega
    · have := vlt hvlt; omega
    · have := vlt hvlt; omega
    · obtain ⟨Ea, hEa, hla, _⟩ := h.arg k' (lt_of_get hk')
      exact hc _ Ea o V hEa hla h0
    · rw [hc'] at hv
      obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hv
      rw [clean_live] at hl
      obtain ⟨E0, h0', hl0⟩ := LiveBack.callPost hargs v E1 h1 hl
      exact hc _ E0 o V h0' hl0 h0
    · rw [hc'] at hv; cases hv
  · obtain ⟨Ea, hEa, hla⟩ := hargs a ha
    have hg := hc.good hM hEa hla hsa
    rcases hV with rfl | ⟨rfl, rfl⟩
    · exact hg.1
    · exact hg.2 rfl

theorem inv (h : CallH P Γ F x fn args m.nv) {f : Nat} {k : Stmt} (hi : Inv m Γ F (.letcall x f args k))
    {m1 : Mem} (hb : BindParams m fn.params args m.nv 0 m1) :
    Inv (callMem m m1 fn x) ((callS Γ F fn args m.nv x).canon (sigCtx fn)) F (callStmt fn args m.nv x k) where
  toMInv := h.minv hi.toMInv hb
  catchOK := h.catchOK _ k
  cover := h.covers hi.toMInv hi.cover hb
  pinIn := by
    have he : PinOK ((callS Γ F fn args m.nv x).canon (sigCtx fn)) (callStmt fn args m.nv x k) =
        PinOK ((callS Γ F fn args m.nv x).canon (sigCtx fn))
          (wrapParams fn.params m.nv 0 (fn.body.rename (callRen fn.params args m.nv))) :=
      resFrame_pinOK _ fn _ _
    rw [he]
    exact pinOK_wrap (h.minv hi.toMInv hb).rootbLt (PinOK.of_spine_nil h.body_spine) h.body_spine _ _ _
  dtorIn := DtorPinOK.of_spine_dbind h.spine_dbind
  dtorOut v E hv hd hos hn _ d hdd hnm := by
    -- a caller binding: what it views in memory is bound in the caller
    obtain ⟨_, _, E1, h1, rfl⟩ := h.dbind_frame hv hd
    rw [Entry.clean_dbind] at hd; rw [clean_mode] at hos
    have hn1 : E1.ty ≠ .int ∨ E1.mode = .rootb := by rwa [clean_ty, clean_mode] at hn
    obtain ⟨Er, hEr, _⟩ := h.postwf.dtor v E1 h1 hd hos hn1 d (Entry.clean_vdeps_sub hdd) hnm
    exact h.not_spine (h.post_lt hEr) (h.post_ne_x hEr)
  pinOut p E hp hrb hns r hr hrs := by
    rcases h.ctx_cases p with ⟨rfl, hc⟩ | ⟨rfl, hc⟩ | ⟨k', t, hk', rfl, hc⟩ | ⟨k', t, hk', rfl, hc⟩ |
        ⟨k', b', t, hk', rfl, hc⟩ | ⟨hy', hyx, hc⟩ | ⟨hc, v, hv, rfl⟩ <;> rw [hc] at hp <;> (try cases hp)
    · exact absurd hrb (resMode_ne' fn)
    · exact absurd hrb (resMode_ne' fn)
    · exfalso; apply hns
      rw [callStmt_spine]
      exact List.mem_cons_of_mem _ (List.mem_cons_of_mem _ (List.mem_append_left _
        (mem_wrapSpine_of hk' (fun b h => by cases h))))
    · cases hrb
    · cases hrb
    · obtain ⟨E1', h1', rfl⟩ := Option.map_eq_some_iff.mp hp
      rw [clean_mode] at hrb
      obtain ⟨E0, h0, hm⟩ := h.postdm.2 p E1' h1'
      have := h.post_rootb h0 (hm ▸ hrb)
      rw [h1'] at this; cases this
      rw [clean_id (Or.inr hrb) (h.post_live_rootb h1' hrb)] at hr
      -- What it depends on was bound before the call: none of the call's frames.
      obtain ⟨Er, hEr, _⟩ := h.wf p E1' h0 (hi.rootbLive p E1' h0 (hm ▸ hrb)) (Or.inr (hm ▸ hrb)) r hr
      have hrlt : r < m.nv := hi.nvSt r (by rw [← hi.dom r, hEr]; rfl)
      have hrx : r ≠ x := fun e => by subst e; rw [h.fresh] at hEr; cases hEr
      exact h.not_spine hrlt hrx hrs
  nvS v hv := by
    obtain ⟨_, hnv, hvars, _⟩ := h.fnok
    show v < m.nv + fn.nvars
    have hlt : ∀ w, w < m.nv → w < m.nv + fn.nvars := fun w hw => Nat.lt_of_lt_of_le hw (Nat.le_add_right _ _)
    rw [callStmt_vars] at hv
    simp only [List.mem_cons, List.mem_append, List.mem_map] at hv
    rcases hv with (rfl | (rfl | hz | hw | ⟨w, hw, rfl⟩) | rfl | rfl | hnil) | hk
    · exact hlt _ h.xlt
    · exact Nat.add_lt_add_left hnv _
    · simp only [zOf, List.mem_filter, List.mem_range] at hz; exact hlt _ hz.1
    · obtain ⟨k', p, hk', _, rfl⟩ := mem_wrapSpine hw
      rw [Nat.add_zero]; exact Nat.add_lt_add_left (Nat.lt_trans (lt_of_get hk') hnv) _
    · rcases callRen_cases fn.params args m.nv w with ⟨b, t, hwp, hr⟩ | ⟨_, hr⟩ <;> rw [hr]
      · exact hlt _ (h.argLt (lt_of_get hwp))
      · exact Nat.add_lt_add_left (hvars w hw) _
    · exact hlt _ h.xlt
    · exact Nat.add_lt_add_left hnv _
    · simp at hnil
    · exact hlt _ (hi.nvS v (by simp [Stmt.vars, hk]))
  nvF v hv := Nat.lt_of_lt_of_le (hi.nvF v hv) (Nat.le_add_right _ _)
  anch p E hp hrb hns r hr := by
    rcases h.ctx_cases p with ⟨rfl, hc⟩ | ⟨rfl, hc⟩ | ⟨k', t, hk', rfl, hc⟩ | ⟨k', t, hk', rfl, hc⟩ |
        ⟨k', b', t, hk', rfl, hc⟩ | ⟨hy', hyx, hc⟩ | ⟨hc, v, hv, rfl⟩ <;> rw [hc] at hp <;> (try cases hp)
    · exact absurd hrb (resMode_ne' fn)
    · exact absurd hrb (resMode_ne' fn)
    · exfalso; apply hns
      rw [callStmt_spine]
      exact List.mem_cons_of_mem _ (List.mem_cons_of_mem _ (List.mem_append_left _
        (mem_wrapSpine_of hk' (fun b h => by cases h))))
    · cases hrb
    · cases hrb
    · obtain ⟨E1', h1', rfl⟩ := Option.map_eq_some_iff.mp hp
      rw [clean_mode] at hrb
      obtain ⟨E0, h0, hm⟩ := h.postdm.2 p E1' h1'
      have := h.post_rootb h0 (hm ▸ hrb)
      rw [h1'] at this; cases this
      rw [clean_id (Or.inr hrb) (h.post_live_rootb h1' hrb)] at hr ⊢
      -- AGORA-937 (B2/B3): the outer anchors carry over: a held root is bound
      -- before the call (so below the frame), not `x`, and no argument, so
      -- none of the placed call's killable names (`killVars_callIn`), and
      -- a frame binding of the same type in the new context
      intro hb
      rcases hi.anch p E1' h0 (hm ▸ hrb) (by simp [Stmt.spine]) r hr hb with hF | ⟨hha, hnk, Er, hEr, hhv⟩
      · exact Or.inl hF
      have hlt : r.root < m.nv := hi.nvSt r.root (by rw [← hi.dom, hEr]; rfl)
      have hrx : r.root ≠ x := fun e => hnk (by simp [Stmt.killVars, e])
      have hra : r.root ∉ args := fun e => hnk (by simp [Stmt.killVars, e])
      refine Or.inr ⟨hha, fun hk => ?_, ?_⟩
      · simp only [callStmt, Stmt.killVars, List.mem_cons, List.mem_append] at hk
        rcases hk with hk | hk | hk
        · exact hrx hk
        · rcases killVars_callIn fn args m.nv x _ hk with hk | hk | hk
          · exact hrx hk
          · exact absurd hk (Nat.not_le.mpr hlt)
          · exact hra (inoutArgs_sub _ _ h.len _ hk)
        · exact hnk (by simp [Stmt.killVars, hk])
      · rcases h.ctx_cases r.root with ⟨e, _⟩ | ⟨e, _⟩ | ⟨_, _, _, e, _⟩ | ⟨_, _, _, e, _⟩ |
            ⟨k2, _, _, hk2, e, _⟩ | ⟨_, _, hc2⟩ | ⟨_, v, _, e⟩
        · exact absurd e hrx
        · exact absurd hlt (Nat.not_lt.mpr (by rw [e]; exact Nat.le_add_right _ _))
        · exact absurd hlt (Nat.not_lt.mpr (by rw [e, Nat.add_zero]; exact Nat.le_add_right _ _))
        · exact absurd hlt (Nat.not_lt.mpr (by rw [e, Nat.add_zero]; exact Nat.le_add_right _ _))
        · exact absurd (e ▸ RSetup.getD_mem' (h.len ▸ (List.getElem?_eq_some_iff.mp hk2).1)) hra
        · obtain ⟨E2, hE2⟩ : ∃ E2, callPost Γ fn args r.root = some E2 := by
            have := h.postdm.1 r.root; rw [hEr] at this
            cases h2 : callPost Γ fn args r.root with
            | none => rw [h2] at this; cases this
            | some E2 => exact ⟨E2, rfl⟩
          have hd3 := h.postdt.2 r.root E2 hE2
          obtain ⟨E3, h3, hd3⟩ := hd3
          have hE3 : E3 = Er := Option.some.inj (h3.symm.trans hEr)
          refine ⟨E2.clean, by rw [hc2, hE2]; rfl, ?_⟩
          rw [clean_ty, hd3.2, hE3]; exact hhv
        · exact absurd hlt (Nat.not_lt.mpr (by rw [e]; exact Nat.le_add_right _ _))
  spineNd := by
    rw [callStmt_spine, h.body_spine, List.append_nil]
    have hx : x ∉ (m.nv + fn.params.length) :: wrapSpine fn.params m.nv 0 := by
      intro hm
      rcases List.mem_cons.mp hm with he | hm
      · have := vlt h.xlt; have := veq he; omega
      · obtain ⟨k', _, _, _, he⟩ := mem_wrapSpine hm
        have := vlt h.xlt; have := veq he; omega
    have hr : m.nv + fn.params.length ∉ wrapSpine fn.params m.nv 0 := by
      intro hm
      obtain ⟨k', _, hk', _, he⟩ := mem_wrapSpine hm
      have := lt_of_get hk'; have := veq he; omega
    exact List.nodup_cons.mpr ⟨hx, List.nodup_cons.mpr ⟨hr, wrapSpine_nodup _ _ _⟩⟩
  spineDom v hv := by
    rw [callStmt_spine, h.body_spine, List.append_nil] at hv
    rcases List.mem_cons.mp hv with rfl | hv
    · exact ⟨_, h.canon_x _⟩
    rcases List.mem_cons.mp hv with rfl | hv
    · rcases h.ctx_cases (m.nv + fn.params.length) with ⟨he, _⟩ | ⟨_, hc⟩ | _
      · have := vlt h.xlt; have := veq he; omega
      · exact ⟨_, hc⟩
      · rw [show m.nv + fn.params.length = (callS Γ F fn args m.nv x).ρ fn.params.length from
          (ren_res fn args m.nv).symm]
        exact ⟨_, h.canon_sigR (sigCtx_res fn) (Nat.le_refl _)⟩
    · obtain ⟨k', p, hk', hp, rfl⟩ := mem_wrapSpine hv
      have hρ : callRen fn.params args m.nv k' = m.nv + 0 + k' := by
        unfold callRen; rw [hk']
        obtain ⟨pm, t⟩ := p
        cases pm with
        | inout b => exact absurd rfl (hp b)
        | _ => simp
      rw [← hρ]
      show ∃ E, (callS Γ F fn args m.nv x).canon (sigCtx fn) ((callS Γ F fn args m.nv x).ρ k') = some E
      exact ⟨_, h.canon_sigR (sigCtx_of hk') (Nat.le_of_lt (lt_of_get hk'))⟩
theorem keep (h : CallH P Γ F x fn args m.nv) {f : Nat} {k : Stmt} :
    Keep Γ ((callS Γ F fn args m.nv x).canon (sigCtx fn)) (.letcall x f args k) (callStmt fn args m.nv x k) := by
  have hdt : DomTy Γ (callPost Γ fn args) := h.postdt
  have hspine : ∀ v, v ∈ (callStmt fn args m.nv x k).spine → v = x ∨ m.nv ≤ v := by
    intro v hv
    rw [callStmt_spine, h.body_spine, List.append_nil] at hv
    rcases List.mem_cons.mp hv with rfl | hv
    · exact Or.inl rfl
    rcases List.mem_cons.mp hv with rfl | hv
    · exact Or.inr (Nat.le_add_right _ _)
    · obtain ⟨_, _, _, _, rfl⟩ := mem_wrapSpine hv
      exact Or.inr (by omega)
  refine ⟨fun v E hv _ => ⟨fun hs => ?_, ?_⟩, fun v E' hv hs => ⟨by simp [Stmt.spine], ?_⟩, ?_⟩
  · rcases hspine v hs with rfl | hle
    · rw [h.fresh] at hv; cases hv
    · exact absurd (h.domlt v E hv) (Nat.not_lt.mpr hle)
  · have hvx : v ≠ x := fun e => by rw [e, h.fresh] at hv; cases hv
    have hvlt := h.domlt v E hv
    rcases h.ctx_cases v with ⟨he, _⟩ | ⟨he, _⟩ | ⟨k', t, hk', he, _⟩ | ⟨k', t, hk', he, _⟩ |
        ⟨k', b, t, hk', rfl, hc⟩ | ⟨hy', _, hc⟩ | ⟨_, w, _, he⟩
    · exact absurd he hvx
    · rw [he] at hvlt; exact absurd hvlt (Nat.not_lt.mpr (Nat.le_add_right _ _))
    · rw [he] at hvlt; exact absurd hvlt (Nat.not_lt.mpr (Nat.le_trans (Nat.le_add_right _ 0) (Nat.le_add_right _ _)))
    · rw [he] at hvlt; exact absurd hvlt (Nat.not_lt.mpr (Nat.le_trans (Nat.le_add_right _ 0) (Nat.le_add_right _ _)))
    · have hkl := lt_of_get hk'
      obtain ⟨Ea, hEa, _, hok, _⟩ := h.arg k' hkl
      rw [hv] at hEa; cases hEa
      rw [get_of hk'] at hok
      obtain ⟨hty, hcan, _⟩ := hok
      have hm : E.mode = .own := by
        rcases hcan with hm | ⟨b', hm, _⟩
        · exact hm
        · exact absurd hm (h.noInout _ E b' hv)
      exact ⟨_, hc, by rw [hm], by simp only at hty; rw [hty], fun hrb => by rw [hm] at hrb; cases hrb⟩
    · obtain ⟨E1, h1, hm1⟩ := h.postdm.get hv
      obtain ⟨E0, h0, _, ht1⟩ := hdt.2 v E1 h1
      rw [hv] at h0; cases h0
      refine ⟨E1.clean, by rw [hc, h1]; rfl, by rw [clean_mode, hm1], by rw [clean_ty, ht1], fun hrb => ?_⟩
      have := h.post_rootb hv hrb
      rw [h1] at this; cases this
      exact clean_id (Or.inr hrb) (h.rbLive v _ hv hrb)
    · rw [he] at hvlt; exact absurd hvlt (Nat.not_lt.mpr (Nat.le_add_right _ _))
  · have hins : ∀ w, w ∈ (callStmt fn args m.nv x k).spine → v ≠ w := fun w hw e => hs (e ▸ hw)
    rw [callStmt_spine] at hins
    rcases h.ctx_cases v with ⟨rfl, _⟩ | ⟨rfl, _⟩ | ⟨k', t, hk', rfl, _⟩ | ⟨k', t, hk', rfl, _⟩ |
        ⟨k', b, t, hk', rfl, hc⟩ | ⟨hy', _, hc⟩ | ⟨hc, w, _, rfl⟩
    · exact absurd rfl (hins _ (List.mem_cons_self))
    · exact absurd rfl (hins _ (List.mem_cons_of_mem _ List.mem_cons_self))
    · exact absurd rfl (hins _ (List.mem_cons_of_mem _ (List.mem_cons_of_mem _
        (List.mem_append_left _ (mem_wrapSpine_of hk' (fun b h => by cases h))))))
    · exact absurd rfl (hins _ (List.mem_cons_of_mem _ (List.mem_cons_of_mem _
        (List.mem_append_left _ (mem_wrapSpine_of hk' (fun b h => by cases h))))))
    · obtain ⟨Ea, hEa, _⟩ := h.arg k' (lt_of_get hk'); exact ⟨Ea, hEa⟩
    · rw [hc] at hv
      obtain ⟨E1, h1, _⟩ := Option.map_eq_some_iff.mp hv
      have := h.postdm.1 v; rw [h1] at this
      exact Option.isSome_iff_exists.mp this.symm
    · rw [hc] at hv; cases hv
  · -- a binding `letd` made is a caller's, viewing no more than before the call
    intro v E' hv hd hos hn _
    obtain ⟨_, _, E1, h1, rfl⟩ := h.dbind_frame hv hd
    rw [Entry.clean_dbind] at hd; rw [clean_mode] at hos
    have hn1 : E1.ty ≠ .int ∨ E1.mode = .rootb := by rwa [clean_ty, clean_mode] at hn
    obtain ⟨E0, h0, hd0, hos0, hn0, hs0⟩ := h.post_dkeep v E1 h1 hd hos hn1 (by simp)
    exact ⟨E0, h0, hd0, hos0, hn0, fun d hdd hnm => hs0 d (Entry.clean_vdeps_sub hdd) hnm⟩

end CallH

/-! ### A well-typed call can bind its parameters -/

theorem bind_exists {m0 : Mem} {base : Nat} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (m : Mem), ps.length = as.length →
      (∀ (k : Nat) (p : PMode × Ty) (a : Var), ps[k]? = some p → as[k]? = some a →
        (p.1 = .inp → ∃ v, (m0.st a).bind lendSlot = some v) ∧
        (p.1 = .sink → ∃ v, m0.st a = some ⟨true, some v⟩)) →
      (∀ a ∈ as, a < base) →
      (∀ (k k' : Nat) (a : Var), k < k' → (∃ t, ps[k]? = some (PMode.sink, t)) → as[k]? = some a →
        as[k']? ≠ some a) →
      (∀ a ∈ as, m.st a = m0.st a) →
      ∃ m1, BindParams m ps as base i m1 := by
  intro ps
  induction ps with
  | nil =>
    intro as i m hl _ _ _ _
    cases as with
    | nil => exact ⟨m, BindParams.nil⟩
    | cons _ _ => simp at hl
  | cons p ps ih =>
    intro as i m hl hv hlt hd hsame
    cases as with
    | nil => simp at hl
    | cons a as =>
      obtain ⟨pm, t⟩ := p
      have hl' : ps.length = as.length := by simpa using hl
      have hv' : ∀ (k : Nat) (p : PMode × Ty) (a' : Var), ps[k]? = some p → as[k]? = some a' →
          (p.1 = .inp → ∃ v, (m0.st a').bind lendSlot = some v) ∧
          (p.1 = .sink → ∃ v, m0.st a' = some ⟨true, some v⟩) :=
        fun k p a' h1 h2 => hv (k + 1) p a' (by simpa using h1) (by simpa using h2)
      have hlt' : ∀ a' ∈ as, a' < base := fun a' h => hlt a' (by simp [h])
      have hd' : ∀ (k k' : Nat) (a' : Var), k < k' → (∃ t, ps[k]? = some (PMode.sink, t)) → as[k]? = some a' →
          as[k']? ≠ some a' := fun k k' a' hk h1 h2 => by
        have := hd (k + 1) (k' + 1) a' (by omega) (by simpa using h1) (by simpa using h2)
        simpa using this
      have h0 := hv 0 (pm, t) a (by simp) (by simp)
      cases pm with
      | inp =>
        obtain ⟨v, hv0⟩ := h0.1 rfl
        cases hs : m0.st a with
        | none => rw [hs] at hv0; cases hv0
        | some sl =>
          rw [hs] at hv0
          obtain ⟨m1, hb⟩ := ih as (i + 1) (m.set (base + i) ⟨false, some v⟩) hl' hv' hlt' hd' (by
            intro a' ha'
            have hne : a' ≠ base + i := fun he => by have h1 := vlt (hlt' a' ha'); have h2 := veq he; omega
            simp [upd_ne _ _ hne, hsame a' (by simp [ha'])])
          exact ⟨m1, BindParams.inp (by rw [hsame a (by simp), hs]) hv0 hb⟩
      | sink =>
        obtain ⟨v, hv0⟩ := h0.2 rfl
        obtain ⟨m1, hb⟩ := ih as (i + 1) ((m.set a ⟨true, none⟩).set (base + i) ⟨true, some v⟩) hl' hv'
          hlt' hd' (by
            intro a' ha'
            have hne : a' ≠ base + i := fun he => by have h1 := vlt (hlt' a' ha'); have h2 := veq he; omega
            have hna : a' ≠ a := by
              intro he; subst he
              obtain ⟨k', hk', hka⟩ := List.getElem_of_mem ha'
              exact hd 0 (k' + 1) a' (by omega) ⟨t, by simp⟩ (by simp)
                (by simp [List.getElem?_eq_getElem hk', hka])
            simp [upd_ne _ _ hne, upd_ne _ _ hna, hsame a' (by simp [ha'])])
        exact ⟨m1, BindParams.sink (by rw [hsame a (by simp), hv0]) hb⟩
      | inout b =>
        obtain ⟨m1, hb⟩ := ih as (i + 1) m hl' hv' hlt' hd' (fun a' ha' => hsame a' (by simp [ha']))
        exact ⟨m1, BindParams.inout hb⟩

/-- The call case of progress. -/
theorem callProgress {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {f : Nat} {args : List Var} {k : Stmt}
    {E : Entry} {Γ1 : Ctx} {m : Mem} (hx : Γ x = none) (hc : CallT P Γ F f args E Γ1) (hi : MInv m Γ) :
    ∃ r, Step P m (.letcall x f args k) r := by
  obtain ⟨fn, hf, hlen, hargs, _, _⟩ := hc
  have hmx : m.st x = none := by
    have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
  have hlt : ∀ a ∈ args, a < m.nv := by
    intro a ha
    obtain ⟨i, hi', rfl⟩ := mem_args ha
    obtain ⟨Ea, hEa, _⟩ := hargs i (hlen ▸ hi')
    exact hi.nvSt _ (by rw [← hi.dom, hEa]; rfl)
  obtain ⟨m1, hb⟩ := bind_exists (m0 := m) (base := m.nv) fn.params args 0 m hlen.symm
    (fun k p a hk ha => by
      have hkl := (List.getElem?_eq_some_iff.mp hk).1
      have hgd : args.getD k 0 = a := by simp [List.getD, ha]
      obtain ⟨Ea, hEa, hl, hok, _⟩ := hargs k hkl
      rw [hgd] at hEa
      have hp := (List.getElem?_eq_some_iff.mp hk).2
      rw [hp] at hok
      obtain ⟨pm, t⟩ := p
      refine ⟨fun hm => ?_, fun hm => ?_⟩
      · simp only at hm; subst hm
        rcases hi.mode_cases hEa with hmo | hmo | hmo
        · obtain ⟨T, hT, _, _⟩ := hi.own_val hEa hl (by rw [hmo]; rfl)
          exact ⟨_, by rw [hT]; rfl⟩
        · obtain ⟨v, hv, _⟩ := hi.bor_val hEa hl (by rw [hmo]; rfl)
          exact ⟨v, by rw [hv]; rfl⟩
        · obtain ⟨v, hv, _⟩ := hi.bor_val hEa hl (by rw [hmo]; rfl)
          exact ⟨v, by rw [hv]; rfl⟩
      · simp only at hm; subst hm
        obtain ⟨_, hmo, _⟩ := hok
        obtain ⟨T, hT, _⟩ := hi.own_val hEa hl (by rw [hmo]; rfl)
        exact ⟨T, hT⟩)
    hlt
    (fun k k' a hkk ⟨t, hk⟩ ha ha' => by
      have hkl := (List.getElem?_eq_some_iff.mp hk).1
      have hk'l : k' < args.length := (List.getElem?_eq_some_iff.mp ha').1
      obtain ⟨_, _, _, _, hmv, _⟩ := hargs k hkl
      have hp := (List.getElem?_eq_some_iff.mp hk).2
      have := ((hmv (by rw [hp]; rfl)).2.2.2.2 k' (hlen ▸ hk'l) (by omega)).1
      exact this (by simp [List.getD, ha, ha']))
    (fun _ _ => rfl)
  exact ⟨_, Step.letcall hf hmx hb⟩

/-- What a well-typed call in a configuration satisfying the invariant gives. -/
theorem callH_of {P : Prog} (hP : ProgOK P) {Γ : Ctx} {F : List Var} {x : Var} {f : Nat} {args : List Var}
    {k : Stmt} {m : Mem} {fn : Fn} (hf : P[f]? = some fn) (hx : Γ x = none) (hxF : x ∉ F)
    (hc : CallT P Γ F f args (callRes Γ fn args) (callPost Γ fn args))
    (hi : Inv m Γ F (.letcall x f args k)) :
    CallH P Γ F x fn args m.nv := by
  obtain ⟨hw1, hdm, hE⟩ := CallT.wf hP hc hi.wf
  have hdt := CallT.domTy hc
  obtain ⟨hn1, hEn, _⟩ := CallT.names hP hc hi.names
  have hx1 : callPost Γ fn args x = none := by
    have := hdm.1 x; rw [hx] at this; cases h' : callPost Γ fn args x <;> simp_all
  obtain ⟨fn', hf', hlen, hargs, hnf, hds, _, _, hg⟩ := hc
  rw [hf] at hf'; cases hf'
  exact {
    dsafe := hds
    thru := fun ht => (hg (ThruFn.of_body hf ht)).imp_left (callR_nil_of_regions hi.noRegion)
    prog := hP
    fnok := hP fn (List.mem_of_getElem? hf)
    len := hlen
    arg := hargs
    fresh := hx
    xF := hxF
    xlt := hi.nvS x (by simp [Stmt.vars])
    domlt := fun v E hv => hi.nvSt v (by rw [← hi.dom, hv]; rfl)
    noio := hi.noInout
    Flt := hi.nvF
    wf := hi.wf
    noInout := hi.noInout
    rbLive := hi.rootbLive
    -- AGORA-937 (B3): the arguments are killable names of the `letcall`
    anch := RootbAnchS.toRS fun p E hp hm =>
      (hi.anch p E hp hm (by simp [Stmt.spine])).anti fun v hv => by simp [Stmt.killVars, hv]
    postwf := hw1
    postdm := hdm
    reswf := hE
    nfree := hnf
    names := hi.names
    freshOK := hi.fresh
    postdt := hdt
    resnames := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) hEn }

/-- AGORA-937 B4: what runs under a new parameter's `rbind` is the callee's
    body: its killable names are fresh, or `inout` arguments. -/
theorem callStmt_under (fn : Fn) (args : List Var) (base : Nat) (x : Var) (k : Stmt) {p : Var}
    (hp : p ∈ wrapSpine fn.params base 0) :
    ∀ v ∈ ((callStmt fn args base x k).under p).killVars, base ≤ v ∨ v ∈ inoutArgs fn.params args := by
  intro v hv
  have hW : ∀ v ∈ ((wrapParams fn.params base 0 (fn.body.rename (callRen fn.params args base))).under p).killVars,
      base ≤ v ∨ v ∈ inoutArgs fn.params args := by
    intro v hv
    rcases killVars_wrap _ _ _ _ v (Stmt.under_kv_sub p _ v hv) with h | hv
    · exact Or.inl h
    rw [Stmt.killVars_rename] at hv
    obtain ⟨w, -, rfl⟩ := List.mem_map.mp hv
    exact callRen_mem fn.params args base w
  apply hW
  have hpW : p ∈ (wrapParams fn.params base 0 (fn.body.rename (callRen fn.params args base))).spine := by
    rw [spine_wrap]; exact List.mem_append_left _ hp
  have hpF : p ∈ (Stmt.frozen ((List.range base).filter (fun v => !(inoutArgs fn.params args).contains v))
      (wrapParams fn.params base 0 (fn.body.rename (callRen fn.params args base)))).spine := hpW
  unfold callStmt callIn resFrame at hv
  split at hv <;> simp only [Stmt.under, Stmt.spine, List.mem_cons, hpW, hpF, or_true, ↓reduceIte] at hv <;> exact hv

theorem catchFrames_wrap (s : Stmt) : ∀ (ps : List (PMode × Ty)) (base i : Nat),
    (wrapParams ps base i s).catchFrames = s.catchFrames
  | [], _, _ => rfl
  | (pm, _) :: ps, base, i => by
    cases pm <;> simp [wrapParams, Stmt.catchFrames, catchFrames_wrap s ps base (i + 1)]

theorem callStmt_catchFrames {base : Nat} (h : CallH P Γ F x fn args base) (k : Stmt) (hk : k.src = true) :
    (callStmt fn args base x k).catchFrames = [] := by
  obtain ⟨hsrc, _⟩ := h.fnok
  have hb : (fn.body.rename (callRen fn.params args base)).catchFrames = [] :=
    Stmt.catchFrames_src (by rw [RSetup.src_rename]; exact hsrc)
  unfold callStmt callIn resFrame
  split <;> simp [Stmt.catchFrames, catchFrames_wrap, hb]

/-- AGORA-937 B4: **the call's frame meets `HeldZ`**, each new parameter's
    frame list being the call's frozen one: the new frame's slots are the
    arguments' values or what they lend, clean for every anchor
    (`NamesFree.noMut`, `MInv.goodOf`), and the callee's body names nothing
    frozen (`callStmt_under`). -/
theorem CallH.heldZ (h : CallH P Γ F x fn args m.nv) {f : Nat} {k : Stmt} (hk : k.src = true)
    (hi : Inv m Γ F (.letcall x f args k)) {m1 : Mem} (hb : BindParams m fn.params args m.nv 0 m1)
    {Z : Var → List Var} (hz : HeldZ m Γ Z (.letcall x f args k)) :
    HeldZ (callMem m m1 fn x) ((callS Γ F fn args m.nv x).canon (sigCtx fn))
      (fun p => if m.nv ≤ p then (List.range m.nv).filter (fun v => !(inoutArgs fn.params args).contains v)
        else Z p) (callStmt fn args m.nv x k) := by
  have hargs : ∀ a ∈ args, ∃ E, Γ a = some E ∧ E.live = true := fun a ha => by
    obtain ⟨i, hi', rfl⟩ := List.getElem_of_mem ha
    obtain ⟨Ea, hEa, hl, _⟩ := h.arg i (by rw [← h.len]; exact hi')
    exact ⟨Ea, by simpa [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi'] using hEa, hl⟩
  have hlt : ∀ a ∈ args, a < m.nv := fun a ha => by
    obtain ⟨E, hE, _⟩ := hargs a ha
    exact h.domlt a E hE
  -- the borrowed parameters of the frame: old ones, or the new `in` parameters
  have hcases : ∀ p E, (callS Γ F fn args m.nv x).canon (sigCtx fn) p = some E → E.mode = .rootb →
      (p < m.nv ∧ Γ p = some E) ∨
      (∃ k' t, fn.params[k']? = some (PMode.inp, t) ∧ p = m.nv + 0 + k' ∧ E = callPe Γ fn.params args k') := by
    intro p E hp hrb
    rcases h.ctx_cases p with ⟨rfl, hc⟩ | ⟨rfl, hc⟩ | ⟨k', t, hk', rfl, hc⟩ | ⟨k', t, hk', rfl, hc⟩ |
        ⟨k', b', t, hk', rfl, hc⟩ | ⟨hy', hyx, hc⟩ | ⟨hc, v, hv, rfl⟩ <;> rw [hc] at hp <;> (try cases hp)
    · exact absurd hrb (resMode_ne' fn)
    · exact absurd hrb (resMode_ne' fn)
    · exact Or.inr ⟨k', t, hk', rfl, rfl⟩
    · cases hrb
    · cases hrb
    · obtain ⟨E1', h1', rfl⟩ := Option.map_eq_some_iff.mp hp
      rw [clean_mode] at hrb
      obtain ⟨E0, h0, hm⟩ := h.postdm.2 _ E1' h1'
      have := h.post_rootb h0 (hm ▸ hrb)
      rw [h1'] at this; cases this
      rw [clean_id (Or.inr hrb) (h.post_live_rootb h1' hrb)]
      exact Or.inl ⟨h.domlt _ _ h0, h0⟩
  have hzL : ∀ v, v ∉ (List.range m.nv).filter (fun v => !(inoutArgs fn.params args).contains v) →
      m.nv ≤ v ∨ v ∈ inoutArgs fn.params args := by
    intro v hv
    by_cases hvl : v < m.nv
    · right
      rcases Decidable.em (v ∈ inoutArgs fn.params args) with hio | hn
      · exact hio
      · exact absurd (List.mem_filter.mpr ⟨List.mem_range.mpr hvl, by simpa using hn⟩) hv
    · exact Or.inl (Nat.le_of_not_lt hvl)
  refine
    { caps := fun p E hp hm d hd hb' hh => ?_
      reach := fun p E hp hm v hv => ?_
      bound := fun p E hp hm v hv => ?_
      frames := fun x0 m0 b0 h0 => by rw [callStmt_catchFrames h k hk] at h0; cases h0 }
  · rcases hcases p E hp hm with ⟨hpl, h0⟩ | ⟨k', t, hk', rfl, rfl⟩
    · -- an old parameter: its frame's clause, kept (the arguments are its frame's)
      simp only [Nat.not_le.mpr hpl, ↓reduceIte]
      have hcw := hz.caps p E h0 hm d hd hb' hh
      have hreach : ∀ v ∈ (Stmt.letcall x f args k).killVars, v ∉ Z p := fun v hv =>
        hz.reach p E h0 hm v (by rw [Stmt.under_off (by simp [Stmt.spine])]; exact hv)
      exact hb.frameCaps hi.toMInv hlt hargs
        (fun a ha o V hs => hcw a o V (hreach a (by simp [Stmt.killVars, ha])) hs)
        (fun v o V hv hs => hcw v o V hv hs)
    · -- a new `in` parameter: every argument is clean for its anchor
      simp only [show m.nv ≤ m.nv + 0 + k' by omega, ↓reduceIte]
      have hkl : k' < fn.params.length := (List.getElem?_eq_some_iff.mp hk').1
      have hvvm : args.getD k' 0 ∈ args := by
        rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem (by rw [h.len]; exact hkl)]
        exact List.getElem_mem _
      -- the anchor is one the argument holds, of no integer
      have hheld := hh.2.1
      unfold callPe at hheld
      rw [hk'] at hheld
      simp only at hheld
      by_cases hvt : (argE Γ (args.getD k' 0)).ty = .int
      · rw [if_pos hvt] at hheld; simp at hheld
      rw [if_neg hvt] at hheld
      have hdv : d ∈ (argE Γ (args.getD k' 0)).vdeps := by
        have hsub : ∀ {t : Ty} {ds : List Dep}, d ∈ typedDeps t ds → d ∈ ds := by
          intro t ds hd'
          unfold typedDeps at hd'
          split at hd'
          · rcases List.mem_append.mp hd' with h1 | h1
            · exact (List.mem_filter.mp h1).1
            · exact (List.mem_filter.mp h1).1
          · exact (List.mem_filter.mp hd').1
        exact List.mem_append_right _ (hsub hheld)
      have hA : ∀ a ∈ args, ∀ o V, m.st a = some ⟨o, some V⟩ → LiveGood m d.root V := by
        intro a ha o V hs
        obtain ⟨Ea, hEa, hla⟩ := hargs a ha
        by_cases hat : Ea.ty = .int
        · exact hi.toMInv.goodInt hEa hla hat hs
        · have hat' : (argE Γ a).ty ≠ .int := by simp [argE, hEa, hat]
          have hnm := NamesFree.noMut h.nfree ha hat' hvvm hvt hdv hb'
          simp only [argE, hEa, Option.getD_some] at hnm
          exact hi.toMInv.goodOf hEa hla hs hnm
      exact hb.frameCaps hi.toMInv hlt hargs hA (fun v o V hv hs => by
        rcases hzL v hv with hge | hio
        · exact absurd (hi.toMInv.nvSt v (by rw [hs]; rfl)) (Nat.not_lt.mpr hge)
        · exact hA v (inoutArgs_sub _ _ h.len _ hio) o V hs)
  · rcases hcases p E hp hm with ⟨hpl, h0⟩ | ⟨k', t, hk', rfl, rfl⟩
    · simp only [Nat.not_le.mpr hpl, ↓reduceIte]
      -- an old parameter: off the frame's spine, so the whole statement; its
      -- names are the call's, fresh ones, or `inout` arguments
      have hps : p ∉ (callStmt fn args m.nv x k).spine := by
        rw [callStmt_spine, h.body_spine, List.append_nil]
        intro hm'
        rcases List.mem_cons.mp hm' with e | hm'
        · subst e; rw [h.fresh] at h0; cases h0
        rcases List.mem_cons.mp hm' with e | hm'
        · have := vlt hpl; have := veq e; omega
        · obtain ⟨_, _, _, _, e⟩ := mem_wrapSpine hm'; have := vlt hpl; have := veq e; omega
      rw [Stmt.under_off hps] at hv
      have hreach : ∀ v ∈ (Stmt.letcall x f args k).killVars, v ∉ Z p := fun v hv =>
        hz.reach p E h0 hm v (by rw [Stmt.under_off (by simp [Stmt.spine])]; exact hv)
      simp only [callStmt, Stmt.killVars, List.mem_cons, List.mem_append] at hv
      rcases hv with rfl | hv | hv
      · exact hreach _ (by simp [Stmt.killVars])
      · rcases killVars_callIn fn args m.nv x _ hv with rfl | hge | hio
        · exact hreach _ (by simp [Stmt.killVars])
        · exact fun hz' => Nat.lt_irrefl _ (Nat.lt_of_le_of_lt hge (hz.bound p E h0 hm _ hz'))
        · exact hreach _ (by simp [Stmt.killVars, inoutArgs_sub _ _ h.len _ hio])
      · exact hreach _ (by simp [Stmt.killVars, hv])
    · simp only [show m.nv ≤ m.nv + 0 + k' by omega, ↓reduceIte]
      have hpw : m.nv + 0 + k' ∈ wrapSpine fn.params m.nv 0 := mem_wrapSpine_of hk' (fun b h => by cases h)
      intro hvz
      rcases callStmt_under fn args m.nv x k hpw v hv with hge | hio
      · exact Nat.lt_irrefl _ (Nat.lt_of_le_of_lt hge (List.mem_range.mp (List.mem_filter.mp hvz).1))
      · have := (List.mem_filter.mp hvz).2
        simp [hio] at this
  · split at hv
    · exact Nat.lt_of_lt_of_le (List.mem_range.mp (List.mem_filter.mp hv).1) (by simp [callMem])
    · rename_i hpl
      rcases hcases p E hp hm with ⟨_, h0⟩ | ⟨k', _, _, rfl, _⟩
      · exact Nat.lt_of_lt_of_le (hz.bound p E h0 hm v hv) (by simp [callMem])
      · omega

/-- The call case of preservation. -/
theorem callCase {P : Prog} (hP : ProgOK P) : CallCase P := by
  intro ξ Γ F x f args k E Γ1 Δ m m' s' hk hx hxF hc hkT hpx hi hst hnr
  cases hst with
  | reap hrs hrk _ => exact absurd ⟨_, _, _, _, _, hrs, hrk, rfl, rfl⟩ hnr
  | letcall hf hmx hb =>
    rename_i m1 fn
    obtain ⟨fn', hf', hlen, hargs, hnf, hds, rfl, rfl, hg⟩ := hc
    rw [hf] at hf'; cases hf'
    have hc' : CallT P Γ F f args (callRes Γ fn args) (callPost Γ fn args) :=
      ⟨fn, hf, hlen, hargs, hnf, hds, rfl, rfl, hg⟩
    have h := callH_of hP hf hx hxF hc' hi
    exact ⟨_, h.typed (StmtT.ctxRel hP) hk hkT hpx, h.inv hi hb, Nat.le_add_right _ _, h.keep, h.frz hi.toMInv hb⟩


/-! ### `recover`: a call of a function without parameters, in a `recover` frame -/

theorem CallH.widen {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {fn : Fn} {base : Nat}
    (h : CallH P Γ F x fn [] base) (hp : fn.params = []) (G : List Var) (hG : ∀ v ∈ G, v < base)
    (hxG : x ∉ G) : CallH P Γ (F ++ G) x fn [] base :=
  { h with
    arg := fun i hi => absurd hi (by simp [hp])
    xF := fun hm => by
      rcases List.mem_append.mp hm with hm | hm
      · exact h.xF hm
      · exact hxG hm
    Flt := fun v hv => by
      rcases List.mem_append.mp hv with hv | hv
      · exact h.Flt v hv
      · exact hG v hv
    anch := h.anch.mono fun _ hv => List.mem_append_left _ hv
    nfree := fun d hd => by simp [mutNames, argNames] at hd
    thru := fun _ => Or.inl (by simp [callR]) }

/-- The `recover` case of preservation. -/
theorem recCase {P : Prog} (hP : ProgOK P) : RecCase P := by
  intro ξ Γ F x f k E fn Γ1 Δ m m' s' hk hx hxF hf hp hty ho hc hkT hpx hi hst hnr
  cases hst with
  | reap hrs hrk _ => exact absurd ⟨_, _, _, _, _, hrs, hrk, rfl, rfl⟩ hnr
  | letrec hf' _ hmx =>
    rename_i fn'
    rw [hf] at hf'; cases hf'
    obtain ⟨fn', hf'', hlen, hargs, hnf, hds, rfl, rfl, hg⟩ := hc
    rw [hf] at hf''; cases hf''
    have hc' : CallT P Γ F f [] (callRes Γ fn []) (callPost Γ fn []) :=
      ⟨fn, hf, hlen, hargs, hnf, hds, rfl, rfl, hg⟩
    have hi' : Inv m Γ F (.letcall x f [] k) :=
      hi.respine rfl (fun v hv => by simpa [Stmt.vars] using hv) trivial trivial trivial
    have h := callH_of hP hf hx hxF hc' hi'
    have hb : BindParams m fn.params [] m.nv 0 m := by rw [hp]; exact BindParams.nil
    have hI := h.inv hi' hb
    have hkeep := h.keep (f := f) (k := k)
    have hpost : callPost Γ fn [] = Γ := by unfold callPost; rw [hp]; simp [mutNames, argNames]; rfl
    -- what the frame returns to
    let m0 := m.set x ⟨fn.resOwn, none⟩
    let G := (List.range m0.nv).filter (· ≠ x)
    have h' := h.widen hp G (fun v hv => (List.mem_range.mp (List.mem_filter.mp hv).1))
      (fun hm => by simp [G] at hm)
    have hIn := h'.typedIn (ξ := .none) (StmtT.ctxRel hP)
    rw [hpost] at hIn hkT
    have hxlt : x < m.nv := h.xlt
    have hrne : x ≠ m.nv + fn.params.length := fun e => by have := vlt hxlt; have := veq e; omega
    have hEc : (callRes Γ fn []).mode = .bor := by simp [callRes, resMode, ho]
    have hEty : (callRes Γ fn []).ty = .int := by simp [callRes, hty]
    have hout : RhsOut m Γ (callRes Γ fn []) (.int 1) false :=
      { own := by rw [hEc]; rfl
        mode := Or.inr hEc
        live := rfl
        tyok := by rw [hEty]; rfl
        wf := fun h0 => absurd hEty h0
        valOwn := fun h0 => by rw [hEc] at h0; cases h0
        valBor := fun _ => by rw [hEty]; exact .int
        shares := fun h0 => by rw [hEc] at h0; cases h0
        names := fun hn => by rcases hn with hn | hn
                              · exact absurd hEty hn
                              · rw [hEc] at hn; cases hn
        held := NamesIn.nil _ rfl
        pkgs := PkgsOK.leaf (fun e hc => by cases hc) (fun _ _ _ _ _ he => by cases he)
        pkgFree := fun _ hn => absurd hn PkgNames.none_int }
    have hM1 := hi.toMInv.add hx hxlt hout
    have hM : MInv (m0.set x ⟨false, some (.int 1)⟩) (setE Γ x (callRes Γ fn [])) :=
      hM1.of_st (by funext v; by_cases hv : v = x <;> simp [m0, hv])
        (hi.heap.set_bor x _ |>.set_bor x _ |> fun hh => by
          have : (m0.set x ⟨false, some (.int 1)⟩) = ((m.set x ⟨false, none⟩).set x ⟨false, some (.int 1)⟩) := by
            simp [m0, ho]
          rw [this]; exact hh) (Nat.le_refl _)
    have hanchΔ : RootbAnchS (setE Γ x (callRes Γ fn [])) F [x] := by
      intro p Ep hp' hm
      by_cases hpx : p = x
      · subst hpx; simp [setE] at hp'; subst hp'; rw [hEc] at hm; cases hm
      · simp only [setE, upd_ne _ _ hpx] at hp'
        -- AGORA-937 (B2): `x` is a killable name of `letrec x f k`, so a held
        -- anchor's root is not `x`, which is all the call result's binding changes
        refine ((hi.anch p Ep hp' hm (by simp [Stmt.spine])).anti fun v hv => ?_).of_tyV
          fun r Er hr hrV => ⟨Er, ?_, rfl⟩
        · simp only [List.mem_singleton] at hv; simp [Stmt.killVars, hv]
        · have hrx : r ≠ x := fun e => hrV (by simp [e])
          simp [setE, upd_ne _ _ hrx, hr]
    have hsp : (callIn fn [] m.nv x).spine = [m.nv + fn.params.length] := by
      rw [callIn_spine, h.body_spine]; simp [hp, wrapSpine]
    have hKO : KeepOut ((callS Γ F fn [] m.nv x).canon (sigCtx fn)) (setE Γ x (callRes Γ fn []))
        (callIn fn [] m.nv x).spine := by
      refine ⟨fun v Ev hv hvs => ?_, fun v Ev hv => ?_⟩
      · by_cases hvx : v = x
        · subst hvx
          rw [h.canon_x] at hv; cases hv
          refine ⟨callRes Γ fn [], by simp [setE], by simp [callX, callRes], by simp [callX, callRes], fun hr => ?_⟩
          exact absurd hr (resMode_ne' fn)
        · have hvs' : v ∉ (callStmt fn [] m.nv x k).spine := by
            simp only [callStmt, Stmt.spine, List.mem_cons, not_or]; exact ⟨hvx, hvs⟩
          obtain ⟨_, E0, h0⟩ := hkeep.2.1 v Ev hv hvs'
          obtain ⟨_, E1, h1, hm1, ht1, hrb1⟩ := hkeep.1 v E0 h0 (by simp [Stmt.spine])
          rw [hv] at h1; cases h1
          refine ⟨E0, by simp [setE, upd_ne _ _ hvx, h0], hm1.symm, ht1.symm, fun hr => ?_⟩
          exact (hrb1 (hm1 ▸ hr)).symm
      · by_cases hvx : v = x
        · subst hvx
          refine ⟨by rw [hsp]; simp [hrne], _, h.canon_x _⟩
        · simp only [setE, upd_ne _ _ hvx] at hv
          obtain ⟨hvs, E1, h1, _⟩ := hkeep.1 v Ev hv (by simp [Stmt.spine])
          refine ⟨fun hm => hvs ?_, E1, h1⟩
          simp only [callStmt, Stmt.spine, List.mem_cons]; exact Or.inr hm
    -- A2-drop.2: a caller binding `letd` made is one where the frame returns
    have hDS : DStay ((callS Γ F fn [] m.nv x).canon (sigCtx fn)) (setE Γ x (callRes Γ fn []))
        (callIn fn [] m.nv x).spine := by
      intro v Ev hv hd hos _
      obtain ⟨_, hvx, E1, h1, rfl⟩ := h.dbind_frame hv hd
      rw [hpost] at h1
      exact ⟨E1, by simp [setE, upd_ne _ _ hvx, h1], by rwa [Entry.clean_dbind] at hd,
        by rwa [clean_mode] at hos⟩
    -- AGORA-937 B4: the frame's end, the caller's store with `x` an integer,
    -- keeps the clause the call starts with
    have hC : HeldCapsInp (m0.set x ⟨false, some (.int 1)⟩) (setE Γ x (callRes Γ fn [])) .skip := by
      intro p Ep hp hmp _ d hd hb' hh
      have hpx : p ≠ x := fun e => by
        subst e; simp [setE] at hp; subst hp; rw [hEc] at hmp; cases hmp
      simp only [setE, upd_ne _ _ hpx] at hp
      have hcw := hi.heldCaps p Ep hp hmp (by simp [Stmt.spine]) d hd hb' hh
      exact (hcw.setClean (o := false) (y := x)
        (fun u E1 hu h1 hl1 => by simp only [setE, upd_ne _ _ hu] at h1; exact ⟨E1, h1, hl1⟩)
        (ValCapsInp.int _ _) (fun c hc => by cases hc)).of_st (by show ((m.set x ⟨fn.resOwn, none⟩).set x _).st = _; rw [Mem.set_set])
    have hcatch : StmtT P (ξ.under x) ((callS Γ F fn [] m.nv x).canon (sigCtx fn)) F (.catchR x m0 (callIn fn [] m.nv x))
        (setE Γ x (callRes Γ fn [])) :=
      StmtT.catchR hxF hIn hM hanchΔ hKO hDS
    refine ⟨_, StmtT.scope ⟨callX fn, h.canon_x _, by simp [callX, resMode_ne' fn]⟩ h.xF
      (StmtT.seq hk hcatch hkT) hpx, ?_, Nat.le_add_right _ _, hkeep, h.frz hi.toMInv hb⟩
    refine hI.respine rfl (fun v hv => ?_) ⟨fun v hv hvx => ?_, ?_, Nat.le_add_right _ _, fun _ bl hk _ => ⟨bl, hk, BlkKeep.refl bl⟩,
      h.catchOK _ k⟩
      hI.pinIn hI.dtorIn (fun v hv => by
        simp only [recStmt, callStmt, Stmt.killVars, List.mem_cons, List.mem_append] at hv ⊢
        rcases hv with rfl | (rfl | hv) | hv <;> simp_all)
    · simp only [recStmt, Stmt.vars, List.mem_cons, List.mem_append] at hv
      rcases hv with rfl | (rfl | hv) | hv
      · simp [callStmt, Stmt.vars]
      · simp [callStmt, Stmt.vars]
      · simp [callStmt, Stmt.vars, hv]
      · simp [callStmt, Stmt.vars, hv]
    · have hvr : v ≠ m.nv + fn.params.length := fun e => hv (by rw [hsp]; simp [e])
      simp [callMem, upd_ne _ _ hvr]
    · rw [hsp]; simp [hrne]

end A2
