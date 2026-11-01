import A2.Call

/-! A2 — what source typing keeps, for the frame a destructor's binding opens.

A source statement's typing keeps every binding with its mode and type, and
binds nothing new (`StmtT.domTy`). It keeps a well-formed context
well-formed (`StmtT.wf`) and what is held by name valid (`StmtT.names`).
Here it also leaves every borrowed parameter's entry as it was, when what the
parameter borrows from is lent out (`RootbAnch`): no rule that changes a
binding reaches a borrowed parameter. Together these are what `scopeD` asks
of its body (`KeepOut Γ Δ []`, `CtxWF Δ`, `NameWF Δ`), so `letd` needs no
premise for them (`srcCase`). -/

namespace A2

theorem CtxRel.ofDomTy {Γ Γ' : Ctx} (hd : DomTy Γ Γ')
    (hr : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → Γ' p = some Ep) (hk : DKeep Γ Γ' []) :
    CtxRel Γ Γ' :=
  ⟨hd.1, hd.2, hr, hk⟩

theorem CtxRel.domTy {Γ Γ' : Ctx} (h : CtxRel Γ Γ') : DomTy Γ Γ' := ⟨h.dom, h.mode⟩

/-- The end of a scope that the statement opened, around a body whose typing
    keeps the borrowed parameters. -/
theorem CtxRel.exitScope_fresh {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {E : Entry}
    (hx : Γ x = none) (hxF : x ∉ F) (h1 : CtxRel Γ Γ1) (h2 : CtxRel (A2.setE Γ1 x E) Δ)
    (hanch : RootbAnch Δ F) (hpin : NoPin Δ x) : CtxRel Γ (A2.exitScope x Δ) := by
  refine CtxRel.ofDomTy (DomTy.exitScope_fresh hx h1.domTy h2.domTy) (fun p Ep hp hrb => ?_)
    (DKeep.bind h1.dkeep h2.dkeep)
  have hpx : p ≠ x := fun e => by subst e; rw [hx] at hp; cases hp
  have h1p := h1.rootb p Ep hp hrb
  have h2p := h2.rootb p Ep (by simp [A2.setE, upd_ne _ _ hpx, h1p]) hrb
  simp only [A2.exitScope, upd_ne _ _ hpx, A2.kill, h2p, Option.map_some]
  rw [killE_rootb hanch hxF .replace false (hpin.kills .replace false) h2p hrb]

theorem RhsT.ctxRel {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry}
    (hr : RhsT Γ F r E Γ1) (hanch : RootbAnch Γ F) : CtxRel Γ Γ1 := by
  cases hr with
  | moveOwn hy _ hm hyF hpin => exact CtxRel.moved hanch hy (by rw [hm]; simp) hyF hpin
  | pop _ _ _ _ hyF => exact CtxRel.kill hanch hyF .drop _ (hmn_of_ne_replace _ (by simp) _)
  | pair hy _ hp1 hz _ hp2 _ =>
    have h1 := hp1.ctxRel hy hanch
    exact h1.trans (hp2.ctxRel hz (h1.anch hanch))
  | inl hy _ hp _ => exact hp.ctxRel hy hanch
  | inr hy _ hp _ => exact hp.ctxRel hy hanch
  | takel hy _ hm _ hyF hpin => exact CtxRel.moved hanch hy (by rw [hm]; simp) hyF hpin
  | taker hy _ hm _ hyF hpin => exact CtxRel.moved hanch hy (by rw [hm]; simp) hyF hpin
  | pack hy _ _ hp _ => exact hp.ctxRel hy hanch
  | expr _ => exact CtxRel.refl _
  | new _ => exact CtxRel.refl _
  | copyRoot _ _ _ => exact CtxRel.refl _
  | copyBor _ _ _ => exact CtxRel.refl _
  | borrow _ _ _ => exact CtxRel.refl _
  | «at» _ _ _ _ => exact CtxRel.refl _
  | view _ _ _ _ => exact CtxRel.refl _
  | sat _ _ _ _ => exact CtxRel.refl _
  | fst _ _ _ => exact CtxRel.refl _
  | snd _ _ _ => exact CtxRel.refl _
  | getl _ _ _ => exact CtxRel.refl _
  | getr _ _ _ => exact CtxRel.refl _

/-- A call's typing gives what `CallH` needs of the arguments. -/
theorem CallT.toA {P : Prog} {Γ : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    {Γ' : Ctx} (hc : CallT P Γ F f args E Γ') (hn : NameWF Γ) (hanch : RootbAnch Γ F) :
    ∃ fn, P[f]? = some fn ∧ CallA Γ F fn args ∧ E = callRes Γ fn args ∧ Γ' = callPost Γ fn args := by
  obtain ⟨fn, hf, hlen, harg, hnf, _, hE, hΓ, _⟩ := hc
  exact ⟨fn, hf, ⟨hlen, harg, hnf, hn, hanch⟩, hE, hΓ⟩

theorem CallT.ctxRel {P : Prog} {Γ : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    {Γ' : Ctx} (hc : CallT P Γ F f args E Γ') (hn : NameWF Γ) (hanch : RootbAnch Γ F) :
    CtxRel Γ Γ' := by
  have hdt := CallT.domTy hc
  have hdk := hc.dkeep
  obtain ⟨fn, _, ha, _, rfl⟩ := hc.toA hn hanch
  exact CtxRel.ofDomTy hdt (fun p Ep hp hrb => ha.post_rootb hp hrb) hdk

/-- A weaker context keeps a fixed entry, so a borrowed parameter's. -/
theorem CtxRel.weaker {Γ Γ' : Ctx} (hw : Weaker Γ Γ') : CtxRel Γ Γ' := by
  refine CtxRel.ofDomTy (DomTy.weaker hw) (fun p Ep hp hrb => ?_) ((DKeep.refl Γ' []).weaker_left hw)
  cases hp' : Γ' p with
  | none => exact absurd ((hw.1 p).1.mpr hp') (by rw [hp]; simp)
  | some E' =>
    have := ((hw.1 p).2 Ep E' hp hp').fixed (Or.inl hrb)
    rw [this]

/-- A binding with an entry other than a borrowed parameter's keeps every
    borrowed parameter anchored. -/
theorem RootbAnch.setE {Γ : Ctx} {F : List Var} (h : RootbAnch Γ F) {x : Var} {E : Entry}
    (hE : E.mode ≠ .rootb) : RootbAnch (A2.setE Γ x E) F := fun p Ep hp hm => by
  by_cases hpx : p = x
  · subst hpx; simp only [A2.setE, upd_same, Option.some.injEq] at hp; subst hp; exact absurd hm hE
  · simp only [A2.setE, upd_ne _ _ hpx] at hp; exact h p Ep hp hm

/-- A binding the statement opens, around a body that keeps the borrowed
    parameters. -/
theorem CtxRel.bind {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {E : Entry}
    (hanch : RootbAnch Γ F) (hx : Γ x = none) (hxF : x ∉ F) (h1 : CtxRel Γ Γ1)
    (hE : E.mode ≠ .rootb) (hk : RootbAnch (A2.setE Γ1 x E) F → CtxRel (A2.setE Γ1 x E) Δ)
    (hpin : NoPin Δ x) : CtxRel Γ (A2.exitScope x Δ) := by
  have hanch1 : RootbAnch (A2.setE Γ1 x E) F := (h1.anch hanch).setE hE
  have h2 := hk hanch1
  exact CtxRel.exitScope_fresh hx hxF h1 h2 (h2.anch hanch1) hpin

/-- **Source typing keeps the borrowed parameters**: every binding stays with
    its mode and type, nothing new is bound, and a borrowed parameter whose
    sources are lent out keeps its entry. -/
theorem StmtT.ctxRel {P : Prog} (hP : ProgOK P) {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P Γ F s Δ) : s.src = true → RootbAnch Γ F → NameWF Γ → CtxRel Γ Δ := by
  induction ht with
  | skip => exact fun _ _ _ => CtxRel.refl _
  | seq _ ha _ iha ihb =>
    intro hs hanch hn
    simp only [Stmt.src, Bool.and_eq_true] at hs
    have h1 := iha hs.1 hanch hn
    exact h1.trans (ihb hs.2 (h1.anch hanch) (StmtT.names hP ha hs.1 hn))
  | @letv Γ Γ1 Δ F x r k E hks hx hxF hr _ hpin ih =>
    intro _ hanch hn
    obtain ⟨hn1, hE, _⟩ := hr.names hn
    have hx1 : Γ1 x = none := by
      have := (hr.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h)
      (fun Ex h => by rw [hx1] at h; cases h) hE
    have hnrb : E.mode ≠ .rootb := by rcases (RhsT.out hr).1 with h | h <;> rw [h] <;> simp
    exact CtxRel.bind hanch hx hxF (hr.ctxRel hanch) hnrb (fun ha => ih hks ha hnx) hpin.1
  | @letd Γ Γ1 Δ F x f r k E H hks hx hxF hr hmo _ _ hH _ hpin ih =>
    intro _ hanch hn
    obtain ⟨hn1, hE, _⟩ := hr.names hn
    have hx1 : Γ1 x = none := by
      have := (hr.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    have hnx := NameWF.setE hn1 (E := Entry.arm { E with held := H }) (fun Ex h => by rw [hx1] at h; cases h)
      (fun Ex h => by rw [hx1] at h; cases h) (fun hl ht => (hE hl ht).widen hmo hH)
    exact CtxRel.bind (E := Entry.arm { E with held := H }) hanch hx hxF (hr.ctxRel hanch)
      (show E.mode ≠ .rootb by rw [hmo]; simp) (fun ha => ih hks ha hnx) hpin.1
  | @letcall Γ Γ1 Δ F x f args k E hks hx hxF hc _ hpin ih =>
    intro _ hanch hn
    obtain ⟨hn1, hE, _⟩ := hc.names hP hn
    have hx1 : Γ1 x = none := by
      have := (hc.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h)
      (fun Ex h => by rw [hx1] at h; cases h) hE
    have hnrb : E.mode ≠ .rootb := by
      obtain ⟨fn, _, _, hE', _⟩ := hc.toA hn hanch; rw [hE']; exact resMode_ne' fn
    exact CtxRel.bind hanch hx hxF (hc.ctxRel hn hanch) hnrb (fun ha => ih hks ha hnx) hpin.1
  | @letrec Γ Γ1 Δ F x f k E fn hks hx hxF _ _ _ _ hc _ hpin ih =>
    intro _ hanch hn
    obtain ⟨hn1, hE, _⟩ := hc.names hP hn
    have hx1 : Γ1 x = none := by
      have := (hc.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h)
      (fun Ex h => by rw [hx1] at h; cases h) hE
    have hnrb : E.mode ≠ .rootb := by
      obtain ⟨fn', _, _, hE', _⟩ := hc.toA hn hanch; rw [hE']; exact resMode_ne' fn'
    exact CtxRel.bind hanch hx hxF (hc.ctxRel hn hanch) hnrb (fun ha => ih hks ha hnx) hpin.1
  | @callc Γ Γ1 Δ F x c j zs k Ec E ms σ sig hks hx hxF _ _ _ _ _ _ hcT _ _ hpin _ ih =>
    intro _ hanch hn
    obtain ⟨hn1, hE, _⟩ := hcT.names hP hn
    have hx1 : Γ1 x = none := by
      have := (hcT.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    have hnx : NameWF (A2.setE Γ1 x (recvRes c Ec E)) := NameWF.setE hn1
      (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) (recvRes_named hE)
    have hnrb : (recvRes c Ec E).mode ≠ .rootb := by
      obtain ⟨fn, _, _, hE', _⟩ := hcT.toA hn hanch
      show E.mode ≠ .rootb; rw [hE']; exact resMode_ne' fn
    exact CtxRel.bind hanch hx hxF (hcT.ctxRel hn hanch) hnrb (fun ha => ih hks ha hnx) hpin.1
  | @unpair Γ Δ F y x z k E a b hks hy hl hcan hty hyF hx hz hxz hxF hzF _ hpy _ hpz hpx ih =>
    intro _ hanch hn
    have hnrbE : E.mode ≠ .rootb := by rcases hcan with h | ⟨b, h, _⟩ <;> rw [h] <;> simp
    have h0 : CtxRel Γ (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) :=
      CtxRel.moved hanch hy hnrbE hyF hpy
    have hxy : x ≠ y := fun e => by rw [e, hy] at hx; cases hx
    have hzy : z ≠ y := fun e => by rw [e, hy] at hz; cases hz
    have hx0 : (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) x = none := by
      simp [A2.setE, upd_ne _ _ hxy, A2.kill, hx]
    have hz1 : (A2.setE (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) x (compE E a)) z = none := by
      simp [A2.setE, upd_ne _ _ (Ne.symm hxz), upd_ne _ _ hzy, A2.kill, hz]
    have hn2 := hn.unpair hy hl hty hx hz hxz
    exact h0.trans (CtxRel.bind (h0.anch hanch) hx0 hxF (CtxRel.refl _) (compE_mode_ne E a)
      (fun ha1 => CtxRel.bind ha1 hz1 hzF (CtxRel.refl _) (compE_mode_ne E b)
        (fun ha2 => ih hks ha2 hn2) hpz.1) hpx.1)
  | @assign Γ Γ1 F x r Ex E hx hxF hmodes hr hty _ hx1s hpin _ =>
    intro _ hanch _
    have h1 := hr.ctxRel hanch
    obtain ⟨Ex1, hEx1⟩ := Option.isSome_iff_exists.mp hx1s
    obtain ⟨E0, h0, hm0, ht0⟩ := h1.mode x Ex1 hEx1
    rw [hx] at h0; cases h0
    have hnrbx : Ex.mode ≠ .rootb := by
      rcases hmodes with ⟨h, _⟩ | ⟨h, _⟩ | ⟨h, _⟩ <;> rw [h] <;> simp
    have hpin1 : NoPin Γ1 x := fun p Ep hp hm => hpin p Ep (h1.rootb_back hp hm) hm
    refine h1.trans ((CtxRel.kill (h1.anch hanch) hxF .replace false (hpin1.kills .replace false)).trans
      (CtxRel.setE (Ex := killE .replace false x Ex1) (by simp [A2.kill, hEx1]) ?_ ?_ ?_
        fun hd => absurd hd (by simp [hr.dtor_false.2])))
    · simp [killE_mode, hm0]
    · simp [killE_ty, ht0, hty]
    · simp [killE_mode, hm0, hnrbx]
  | ite ha _ _ _ _ iha _ => exact fun _ hanch hn => iha ha hanch hn
  | «while» => exact fun _ _ _ => CtxRel.refl _
  | @push Γ Γ1 F x y Ex Ey Ex1 t D hx _ hxt hcan hxF hy _ _ _ hpa _ hx1 _ _ hdb =>
    intro _ hanch _
    have h1 := hpa.ctxRel hy hanch
    obtain ⟨E0, h0, hm0, ht0⟩ := h1.mode x Ex1 hx1
    rw [hx] at h0; cases h0
    have hnrb : Ex1.mode ≠ .rootb := by
      rw [hm0]; rcases hcan with h | ⟨b, h, _⟩ <;> rw [h] <;> simp
    -- what the vector gains it holds by name only: a `letd` binding gains no view
    have hnv : Ex1.dbind = true → t.holdsView = false := fun hd => by
      obtain ⟨E0, h0, hd0, _⟩ := (hpa.dkeep hy) x Ex1 hx1 hd (by rw [hm0]; exact hcan.ownSlot)
        (Or.inl (by rw [ht0, hxt]; simp)) (by simp)
      rw [hx] at h0; cases h0
      exact hdb hd0
    exact h1.trans ((CtxRel.kill (h1.anch hanch) hxF .realloc _ (hmn_of_ne_replace _ (by simp) _)).trans
      (CtxRel.setE (Ex := killE .realloc t.holdsView x Ex1) (by simp [A2.kill, hx1]) (by simp [killE_mode]) (by simp [killE_ty])
        (by simp [killE_mode, hnrb])
        fun hd => ⟨by rw [killE_dbind]; exact hd, fun d hdd _ => by
          rw [killE_vdeps]; simpa [Entry.vdeps, ownHeld, hnv hd] using hdd⟩))
  | editB hx hmx _ _ _ _ harg hyx hx1 hl1 _ hthru =>
    exact fun _ hanch _ => CtxRel.editB hanch hx hmx harg hyx hx1 hl1 hthru
  | @free Γ F x E t hx _ hmo _ hxF hpin =>
    exact fun _ hanch _ => CtxRel.moved hanch hx (by rw [hmo]; simp) hxF hpin.1
  | sub hw _ ho ih =>
    intro hs hanch _
    have h0 := CtxRel.weaker hw
    have h1 := ih hs (h0.anch hanch) hw.2.2
    rcases ho with rfl | hwo
    · exact h0.trans h1
    · exact (h0.trans h1).trans (CtxRel.weaker hwo)
  | @panic Γ Δ F _ _ hdom hm hdk =>
    intro _ _ _
    refine CtxRel.ofDomTy ⟨fun v => (hdom v).symm, fun v E hv => by
      obtain ⟨E0, h0, hm0, ht0, _⟩ := hm v E hv; exact ⟨E0, h0, hm0, ht0⟩⟩ (fun p Ep hp hrb => ?_) hdk
    have hd := hdom p
    rw [hp] at hd
    cases hq : Δ p with
    | none => rw [hq] at hd; cases hd
    | some E =>
      obtain ⟨E0, h0, _, _, hfx⟩ := hm p E hq
      rw [hp] at h0; cases h0
      rw [hfx (Or.inl hrb)]
  | catchR => intro hs; simp [Stmt.src] at hs
  | scopeD => intro hs; simp [Stmt.src] at hs
  | scope => intro hs; simp [Stmt.src] at hs
  | rbind => intro hs; simp [Stmt.src] at hs
  | frozen => intro hs; simp [Stmt.src] at hs

theorem CtxRel.keepOut {Γ Δ : Ctx} (h : CtxRel Γ Δ) : KeepOut Γ Δ [] := by
  have hk := h.keep (s := .skip) (s' := .skip) rfl rfl
  exact ⟨fun v E hv _ => (hk.1 v E hv (by simp [Stmt.spine])).2,
    fun v E' hv => ⟨by simp, (hk.2.1 v E' hv (by simp [Stmt.spine])).2⟩⟩

/-- **What a destructor's frame needs of its body**, from the body's typing
    alone: `letd` takes no premise for it. -/
theorem srcCase {P : Prog} (hP : ProgOK P) : SrcCase P :=
  fun ht hs hanch hw hn =>
    ⟨(StmtT.ctxRel hP ht hs hanch hn).keepOut, StmtT.wf hP ht hw, StmtT.names hP ht hs hn⟩

end A2
