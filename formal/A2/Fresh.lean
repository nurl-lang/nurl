import A2.NameWf

/-! A2 — Agora #909: the rules keep fresh borrows fresh (`FreshOK`): a live
fresh borrow's path is structural and rooted at the frame's own bindings. -/

namespace A2
theorem KeepsFrame.of_domMode {Γ0 Γ : Ctx} (h : DomMode Γ0 Γ) : KeepsFrame Γ0 Γ := by
  intro r Er hr hm
  cases hE : Γ r with
  | none => have := h.1 r; rw [hE, hr] at this; cases this
  | some E => obtain ⟨E0, h0, hme⟩ := h.2 r E hE; rw [hr] at h0; cases h0; exact ⟨E, rfl, hme ▸ hm⟩

theorem DomMode.at {Γ0 Γ : Ctx} (h : DomMode Γ0 Γ) {x : Var} {E0 : Entry} (hx : Γ0 x = some E0) :
    ∃ E, Γ x = some E ∧ E.mode = E0.mode := by
  cases hE : Γ x with
  | none => have := h.1 x; rw [hE, hx] at this; cases this
  | some E => obtain ⟨E1, h1, hme⟩ := h.2 x E hE; rw [hx] at h1; cases h1; exact ⟨E, rfl, hme⟩

theorem StmtT.freshOK {P : Prog} (_hP : ProgOK P) {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P ξ Γ F s Δ) : s.src = true → FreshOK Γ → FreshOK Δ := by
  induction ht with
  | skip => exact fun _ h => h
  | seq _ _ _ iha ihb =>
    intro hs h; simp only [Stmt.src, Bool.and_eq_true] at hs; exact ihb hs.2 (iha hs.1 h)
  | sub hw _ ho ih =>
    intro hs h
    rcases ho with rfl | ho
    · exact ih hs (h.weaker hw)
    · exact (ih hs (h.weaker hw)).weaker ho
  | ite _ _ _ _ _ iha _ => intro hs h; simp only [Stmt.src, Bool.and_eq_true] at hs; exact iha hs.1 h
  | «while» => exact fun _ h => h
  | insert _ _ _ ih => exact fun _ h => ih rfl h
  | block _ ih => exact ih
  | catchR => intro hs; simp [Stmt.src] at hs
  | scope => intro hs; simp [Stmt.src] at hs
  | scopeD => intro hs; simp [Stmt.src] at hs
  | scopeL => intro hs; simp [Stmt.src] at hs
  | rbind => intro hs; simp [Stmt.src] at hs
  | frozen => intro hs; simp [Stmt.src] at hs
  | @letv _ Γ Γ1 Δ F x r k E hks hx _ hr _ _ _ ih =>
    intro _ h
    obtain ⟨h1, hE, _⟩ := hr.freshOK h
    have hx1 : Γ1 x = none := by
      have := (hr.domMode).1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    exact FreshOK.exitScope (ih hks (h1.bind hx1 hE)) x
  | @withElem _ Γ Γ1 Δ1 Δ F y x i k Ey E hks hx _ _ _ _ _ _ hr _ _ _ _ _ ihs ihp =>
    intro _ h
    obtain ⟨h1, hE, _⟩ := hr.freshOK (h.kill .replace false y)
    have hx1 : Γ1 x = none := by
      have := (hr.domMode).1 x; simp only [A2.kill, hx, Option.map_none] at this
      cases h' : Γ1 x <;> simp_all
    exact FreshOK.exitScope (ihp rfl (ihs hks (h1.bind hx1 hE))) x
  | @withLock _ Γ Δ F a x k Ea t hks hx _ _ _ _ _ _ _ _ _ _ ih =>
    intro _ h
    exact FreshOK.exitScope (ih hks (h.bind hx (FreshE.of_fresh (lockE_fresh t)))) x
  | @letd _ Γ Γ1 Δ F x f r k E t H τ hks hx _ hr hmo hty hstr _ _ hH _ _ _ ih =>
    intro _ h
    obtain ⟨h1, _, _⟩ := hr.freshOK h
    have hx1 : Γ1 x = none := by
      have := (hr.domMode).1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    exact FreshOK.exitScope (ih hks (h1.bind hx1 (fun _ _ hb _ => by simp [Entry.arm, hmo] at hb))) x
  | @letcall _ Γ Γ1 Δ F x f args k E hks hx _ hc _ _ _ ih =>
    intro _ h
    obtain ⟨h1, hE, _⟩ := hc.freshOK h
    have hx1 : Γ1 x = none := by
      have := (hc.domMode).1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    exact FreshOK.exitScope (ih hks (h1.bind hx1 hE)) x
  | @letrec _ Γ Γ1 Δ F x f k E fn hks hx _ _ _ _ _ hc _ _ ih =>
    intro _ h
    obtain ⟨h1, hE, _⟩ := hc.freshOK h
    have hx1 : Γ1 x = none := by
      have := (hc.domMode).1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    exact FreshOK.exitScope (ih hks (h1.bind hx1 hE)) x
  | @callc _ Γ Γ1 Δ F x c j zs k Ec E ms q σ sig hks hx _ hc htc _ _ _ _ hcT _ _ _ _ ih =>
    intro _ h
    obtain ⟨h1, _, _⟩ := hcT.freshOK h
    have hx1 : Γ1 x = none := by
      have := (hcT.domMode).1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    have hEf : E.fresh = false := by
      obtain ⟨_, _, _, _, _, _, hE, _, _⟩ := hcT; rw [hE]; rfl
    exact FreshOK.exitScope (ih hks (h1.bind hx1 (FreshE.of_fresh (by rw [recvRes_fresh]; exact hEf)))) x
  | @callcE _ Γ Γ1 Δ F x c j zs k Ec E ms q σ sig b hks hx _ _ _ _ _ _ _ _ _ _ _ _ _ hcT _ _ _ _ ih =>
    intro _ h
    obtain ⟨h1, hE, _⟩ := hcT.freshOK (h.kill _ _ _)
    have hx1 : Γ1 x = none := by
      have := (hcT.domMode).1 x; simp only [A2.kill, hx, Option.map_none, Option.isSome_none] at this
      cases h' : Γ1 x <;> simp_all
    exact FreshOK.exitScope (ih hks ((h1.bind hx1 hE).kill _ _ _)) x
  | @unpair _ Γ Δ F y x z k E a b hks hy hl _ hty _ hx hz hxz _ _ _ _ _ _ _ _ _ ih =>
    intro _ h
    obtain ⟨h1, _⟩ := h.moved hy
    have hxy : x ≠ y := fun e => by rw [e, hy] at hx; cases hx
    have hzy : z ≠ y := fun e => by rw [e, hy] at hz; cases hz
    have h2 := h1.bind (setE_none (kill_at_none hx _ _ _) hxy) (FreshE.of_fresh (compE_fresh E a))
    have h3 := h2.bind (setE_none (setE_none (kill_at_none hz _ _ _) hzy) (fun e => hxz e.symm))
      (FreshE.of_fresh (compE_fresh E b))
    exact FreshOK.exitScope (FreshOK.exitScope (ih hks h3) z) x
  | @assign _ Γ Γ1 F x r Ex E hx _ hmodes hr hty hxd _ _ =>
    intro _ h
    obtain ⟨h1, hE, _⟩ := hr.freshOK h
    obtain ⟨Ex1, hx1, hm1⟩ := (hr.domMode).at hx
    have hkx : ∀ Ek, A2.kill .replace false x Γ1 x = some Ek → Ek.mode = Ex.mode := by
      intro Ek hEk; simp [A2.kill, hx1] at hEk; rw [← hEk, killE_mode, hm1]
    have hkf : KeepsFrame Γ1 (A2.setE (A2.kill .replace false x Γ1) x { E with mode := Ex.mode }) :=
      (KeepsFrame.kill Γ1 _ _ _).trans (KeepsFrame.setE (fun Ek hEk hm => by
        show Ex.mode.frame; rw [← hkx Ek hEk]; exact hm))
    refine (h1.kill _ _ _).setE (fun hl hn hb hf => ?_) (fun Ek hEk hm => by
      show Ex.mode.frame; rw [← hkx Ek hEk]; exact hm)
    have hEb : E.mode = .bor := by
      rcases hmodes with ⟨h1', _⟩ | ⟨h1', _⟩ | ⟨_, h2'⟩
      · simp only at hb; rw [h1'] at hb; cases hb
      · simp only at hb; rw [h1'] at hb; cases hb
      · exact h2'
    exact (hE.mono hkf) hl hn hEb hf
  | @push _ Γ Γ1 F x y Ex Ey Ex1 t D hx hlx htx _ _ hy hly htyy _ hpa _ hx1 hl1 =>
    intro _ h
    obtain ⟨h1, _⟩ := hpa.freshOK hy h
    exact h1.reset ((FreshLe.refl Γ1).trans (FreshLe.kill _ _ _ _)) (KeepsFrame.kill _ _ _ _)
      hx1 rfl rfl rfl rfl rfl
  | @free _ Γ F x E t hx _ _ _ _ _ =>
    intro _ h
    exact (h.moved hx).1
  | @editB _ Γ Γ1 F x op Ex Ex1 t D _ hx hmx _ _ _ _ harg hyx hx1 hl1 _ _ =>
    intro _ h
    obtain ⟨h1, _⟩ := harg.freshOK h
    exact h1.reset ((FreshLe.refl Γ1).killNames _) ((KeepsFrame.refl Γ1).killNames _) hx1 rfl rfl rfl rfl rfl
  | @editBV _ Γ Γ1 F x op Ex Ex1 t D _ hx hmx _ _ _ _ _ harg hyx hx1 hl1 _ hthru _ =>
    intro _ h
    obtain ⟨h1, _⟩ := harg.freshOK h
    exact h1.reset (((FreshLe.refl Γ1).killHv _).trans (FreshLe.holdOn _ _ _))
      (((KeepsFrame.refl Γ1).killHv _).trans (KeepsFrame.holdOn _ _ _)) hx1 rfl rfl rfl rfl rfl
  | @takeB _ Γ Δ F x y i k Ex t hks hy _ hx hmx hl hty _ _ _ _ _ _ _ _ ih =>
    intro _ h
    have hyx : y ≠ x := fun e => by rw [e, hx] at hy; cases hy
    have h1 : FreshOK (A2.setE (killThru (.trunc i) Ex.ty Ex.path Γ) x Ex) :=
      h.reset ((FreshLe.refl Γ).killNames _) ((KeepsFrame.refl Γ).killNames _) hx rfl rfl rfl rfl rfl
    exact FreshOK.exitScope (ih hks (h1.bind (setE_none (killNames_none hy _) hyx)
      (FreshE.of_fresh (compE_fresh Ex t)))) y
  | @takeBV _ Γ Δ F x y i k Ex t hks hy _ hx hmx hl hty _ _ _ _ _ _ _ _ _ ih =>
    intro _ h
    have hyx : y ≠ x := fun e => by rw [e, hx] at hy; cases hy
    have h1 : FreshOK (A2.setE (killThruV (.trunc i) Ex.ty Ex.path Γ) x Ex) :=
      h.reset ((FreshLe.refl Γ).killHv _) ((KeepsFrame.refl Γ).killHv _) hx rfl rfl rfl rfl rfl
    exact FreshOK.exitScope (ih hks (h1.bind (setE_none (killHv_none hy _) hyx)
      (FreshE.of_fresh (compE_fresh Ex t)))) y
  | panic _ _ _ _ _ _ hfΔ => exact fun _ h => hfΔ h
  | exit _ _ _ _ _ _ _ hfΔ => exact fun _ h => hfΔ h
  | loop _ _ _ _ _ _ _ _ hfΔ => exact fun _ h => hfΔ h



end A2
