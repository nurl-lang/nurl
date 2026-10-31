import A1.CallMem

/-! A1 — the call step preserves the invariant and is typed: the call case
of preservation, and the call case of progress. -/

namespace A1

theorem Expr.vars_rename (ρ : Var → Var) (e : Expr) : (e.rename ρ).vars = e.vars.map ρ := by
  induction e <;> simp_all [Expr.rename, Expr.vars]

theorem Rhs.vars_rename (ρ : Var → Var) (r : Rhs) : (r.rename ρ).vars = r.vars.map ρ := by
  cases r <;> simp [Rhs.rename, Rhs.vars, Expr.vars_rename]

theorem Stmt.vars_rename (ρ : Var → Var) (s : Stmt) : (s.rename ρ).vars = s.vars.map ρ := by
  induction s <;> simp_all [Stmt.rename, Stmt.vars, Rhs.vars_rename, Expr.vars_rename]

/-- The scopes the parameters open, outermost first. -/
def wrapSpine : List (PMode × Ty) → Nat → Nat → List Var
  | [], _, _ => []
  | (.inout _, _) :: ps, base, i => wrapSpine ps base (i + 1)
  | _ :: ps, base, i => (base + i) :: wrapSpine ps base (i + 1)

theorem spine_wrap (s : Stmt) : ∀ (ps : List (PMode × Ty)) (base i : Nat),
    (wrapParams ps base i s).spine = wrapSpine ps base i ++ s.spine := by
  intro ps
  induction ps with
  | nil => intro base i; rfl
  | cons p ps ih =>
    intro base i
    obtain ⟨pm, t⟩ := p
    cases pm <;> simp [wrapParams, wrapSpine, Stmt.spine, ih]

theorem vars_wrap (s : Stmt) : ∀ (ps : List (PMode × Ty)) (base i : Nat),
    (wrapParams ps base i s).vars = wrapSpine ps base i ++ s.vars := by
  intro ps
  induction ps with
  | nil => intro base i; rfl
  | cons p ps ih =>
    intro base i
    obtain ⟨pm, t⟩ := p
    cases pm <;> simp [wrapParams, wrapSpine, Stmt.vars, ih]

theorem mem_wrapSpine : ∀ {ps : List (PMode × Ty)} {base i : Nat} {v : Var}, v ∈ wrapSpine ps base i →
    ∃ k p, ps[k]? = some p ∧ (∀ b, p.1 ≠ .inout b) ∧ v = base + i + k := by
  intro ps
  induction ps with
  | nil => intro base i v h; simp [wrapSpine] at h
  | cons p ps ih =>
    intro base i v h
    obtain ⟨pm, t⟩ := p
    have shift : ∀ {v}, v ∈ wrapSpine ps base (i + 1) →
        ∃ k p, ((pm, t) :: ps)[k]? = some p ∧ (∀ b, p.1 ≠ .inout b) ∧ v = base + i + k := by
      intro v hv
      obtain ⟨k, p, hk, hp, rfl⟩ := ih hv
      refine ⟨k + 1, p, by simpa using hk, hp, ?_⟩
      show base + (i + 1) + k = base + i + (k + 1); omega
    cases pm with
    | inout b => exact shift h
    | inp =>
      simp only [wrapSpine, List.mem_cons] at h
      rcases h with rfl | h
      · exact ⟨0, (.inp, t), by simp, fun b h => (by cases h), rfl⟩
      · exact shift h
    | sink =>
      simp only [wrapSpine, List.mem_cons] at h
      rcases h with rfl | h
      · exact ⟨0, (.sink, t), by simp, fun b h => (by cases h), rfl⟩
      · exact shift h

theorem wrapSpine_nodup : ∀ (ps : List (PMode × Ty)) (base i : Nat), (wrapSpine ps base i).Nodup := by
  intro ps
  induction ps with
  | nil => intro base i; simp [wrapSpine]
  | cons p ps ih =>
    intro base i
    obtain ⟨pm, t⟩ := p
    have hnot : base + i ∉ wrapSpine ps base (i + 1) := by
      intro hm
      obtain ⟨k, _, _, _, he⟩ := mem_wrapSpine hm
      have := veq he; omega
    cases pm with
    | inout b => exact ih base (i + 1)
    | inp => exact List.nodup_cons.mpr ⟨hnot, ih base (i + 1)⟩
    | sink => exact List.nodup_cons.mpr ⟨hnot, ih base (i + 1)⟩

theorem callStmt_spine (fn : Fn) (args : List Var) (base : Nat) (x : Var) (k : Stmt) :
    (callStmt fn args base x k).spine =
      x :: (base + fn.params.length) :: (wrapSpine fn.params base 0 ++
        (fn.body.rename (callRen fn.params args base)).spine) := by
  simp [callStmt, Stmt.spine, spine_wrap]

theorem callStmt_vars (fn : Fn) (args : List Var) (base : Nat) (x : Var) (k : Stmt) :
    (callStmt fn args base x k).vars =
      x :: ((base + fn.params.length) :: (zOf fn args base ++ (wrapSpine fn.params base 0 ++
        fn.body.vars.map (callRen fn.params args base))) ++ [x, base + fn.params.length]) ++ k.vars := by
  simp [callStmt, Stmt.vars, Rhs.vars, vars_wrap, Stmt.vars_rename, zOf]

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

namespace CallH
variable {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {fn : Fn} {args : List Var} {m : Mem}

theorem body_spine (h : CallH P Γ F x fn args m.nv) :
    (fn.body.rename (callRen fn.params args m.nv)).spine = [] := by
  obtain ⟨hsrc, _⟩ := h.fnok
  exact src_spine (by rw [RSetup.src_rename]; exact hsrc)

theorem inv (h : CallH P Γ F x fn args m.nv) {f : Nat} {k : Stmt} (hi : Inv m Γ F (.letcall x f args k))
    {m1 : Mem} (hb : BindParams m fn.params args m.nv 0 m1) :
    Inv (callMem m m1 fn x) ((callS Γ F fn args m.nv x).canon (sigCtx fn)) F (callStmt fn args m.nv x k) where
  toMInv := h.minv hi.toMInv hb
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
      rw [clean_id (Or.inr hrb) (h.post_live_rootb h1' hrb)] at hr
      exact h.anch p E1' h0 (hm ▸ hrb) r hr
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
          (ren_res fn args m.nv).symm, RSetup.canon_ρ h.sOK, sigCtx_res]
        exact ⟨_, rfl⟩
    · obtain ⟨k', p, hk', hp, rfl⟩ := mem_wrapSpine hv
      have hρ : callRen fn.params args m.nv k' = m.nv + 0 + k' := by
        unfold callRen; rw [hk']
        obtain ⟨pm, t⟩ := p
        cases pm with
        | inout b => exact absurd rfl (hp b)
        | _ => simp
      rw [← hρ]
      show ∃ E, (callS Γ F fn args m.nv x).canon (sigCtx fn) ((callS Γ F fn args m.nv x).ρ k') = some E
      rw [RSetup.canon_ρ h.sOK, sigCtx_of hk']
      exact ⟨_, rfl⟩

theorem keep (h : CallH P Γ F x fn args m.nv) {f : Nat} {k : Stmt} :
    Keep Γ ((callS Γ F fn args m.nv x).canon (sigCtx fn)) (.letcall x f args k) (callStmt fn args m.nv x k) := by
  have hdt : DomTy Γ (callPost Γ fn args) := callPostAux_domTy _ _ _ _ (fun a ha => by
    obtain ⟨i, hi, rfl⟩ := mem_args ha
    obtain ⟨Ea, hEa, _⟩ := h.arg i (h.len ▸ hi)
    exact ⟨Ea, hEa⟩) (DomTy.refl Γ)
  have hspine : ∀ v, v ∈ (callStmt fn args m.nv x k).spine → v = x ∨ m.nv ≤ v := by
    intro v hv
    rw [callStmt_spine, h.body_spine, List.append_nil] at hv
    rcases List.mem_cons.mp hv with rfl | hv
    · exact Or.inl rfl
    rcases List.mem_cons.mp hv with rfl | hv
    · exact Or.inr (Nat.le_add_right _ _)
    · obtain ⟨_, _, _, _, rfl⟩ := mem_wrapSpine hv
      exact Or.inr (by omega)
  refine ⟨fun v E hv _ => ⟨fun hs => ?_, ?_⟩, fun v E' hv hs => ⟨by simp [Stmt.spine], ?_⟩⟩
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
      · rcases hi.mode_cases hEa with hmo | hmo | hmo
        · obtain ⟨T, hT, hw, _⟩ := hi.own_val hEa hl (by rw [hmo]; rfl)
          obtain ⟨sl, hsl, _, _, hown, _⟩ := hi.slot _ Ea hEa
          obtain ⟨⟨t', ht'⟩, _⟩ := hown (by rw [hmo]; rfl)
          rw [ht'] at hw
          cases hw with
          | node _ => exact ⟨_, by rw [hT]; rfl⟩
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
      obtain ⟨_, _, _, _, hmv⟩ := hargs k hkl
      have hp := (List.getElem?_eq_some_iff.mp hk).2
      have := ((hmv (by rw [hp]; rfl)).2.2 k' (hlen ▸ hk'l) (by omega)).1
      exact this (by simp [List.getD, ha, ha']))
    (fun _ _ => rfl)
  exact ⟨_, Step.letcall hf hmx hb⟩

/-- What a well-typed call in a configuration satisfying the invariant gives. -/
theorem callH_of {P : Prog} (hP : ProgOK P) {Γ : Ctx} {F : List Var} {x : Var} {f : Nat} {args : List Var}
    {k : Stmt} {m : Mem} {fn : Fn} (hf : P[f]? = some fn) (hx : Γ x = none) (hxF : x ∉ F)
    (hc : CallT P Γ F f args (callRes Γ fn args) (callPost Γ fn args)) (hi : Inv m Γ F (.letcall x f args k)) :
    CallH P Γ F x fn args m.nv := by
  obtain ⟨hw1, hdm, hE⟩ := CallT.wf hP hc hi.wf
  obtain ⟨fn', hf', hlen, hargs, _, _⟩ := hc
  rw [hf] at hf'; cases hf'
  exact {
    prog := hP
    fnok := hP fn (List.mem_of_getElem? hf)
    len := hlen
    arg := hargs
    fresh := hx
    xF := hxF
    xlt := hi.nvS x (by simp [Stmt.vars])
    domlt := fun v E hv => hi.nvSt v (by rw [← hi.dom, hv]; rfl)
    Flt := hi.nvF
    wf := hi.wf
    noInout := hi.noInout
    rbLive := hi.rootbLive
    anch := fun p E hp hm => hi.anch p E hp hm (by simp [Stmt.spine])
    postwf := hw1
    postdm := hdm
    reswf := hE }

/-- The call case of preservation. -/
theorem callCase {P : Prog} (hP : ProgOK P) : CallCase P := by
  intro Γ F x f args k E Γ1 Δ m m' s' hk hx hxF hc hkT hi hst
  cases hst with
  | letcall hf hmx hb =>
    rename_i m1 fn
    obtain ⟨fn', hf', hlen, hargs, rfl, rfl⟩ := hc
    rw [hf] at hf'; cases hf'
    have hc' : CallT P Γ F f args (callRes Γ fn args) (callPost Γ fn args) :=
      ⟨fn, hf, hlen, hargs, rfl, rfl⟩
    have h := callH_of hP hf hx hxF hc' hi
    exact ⟨_, h.typed hk hkT, h.inv hi hb, Nat.le_add_right _ _, h.keep⟩

end A1
