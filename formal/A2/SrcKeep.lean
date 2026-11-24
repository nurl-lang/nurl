import A2.Call
import A2.Fresh

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

/-! ### AGORA-937 (B2): source typing on the relaxed anchors

A borrowed parameter may hold a `Vec` whose held views are anchored by an
unfrozen root (`HeldAnch`). Source typing still keeps every borrowed
parameter's entry where such a root is none of the statement's killable
names (`Stmt.killVars`): every name a source statement kills directly is
one, so it is no held root (`RootbAnchRS.noHeld`), which is what the kills
ask (`HeldSpared`). A call kills more: a root a closure argument changes by
name, which need not be an argument. That one is no killable name; the
call's own typing covers it, its anchors restricted to the explicit
arguments (`CallT.ctxRelS`, `RootbAnchRS Γ F args`) and `NamesFree`'s last
conjunct saying the change spares every held view (`CallA.post_rootb`). -/

theorem RootbAnchRS.toRH {Γ : Ctx} {F V : List Var} (h : RootbAnchRS Γ F V) : RootbAnchRH Γ F :=
  fun p E hp hm d hd hb => (h p E hp hm d hd hb).imp id (Or.imp id fun h' => h'.1)

theorem canDo.not_region {m : Mode} {e : Eff} (h : canDo m e) : m ≠ .region := fun h' => by
  have := h.ownSlot; rw [h'] at this; cases this

theorem HeldAnch.bound_none {E : Entry} {d : Dep} (h : HeldAnch E d) : d.kind.bound = .none := by
  rcases h.2.2.2 with h' | h' <;> rw [h'] <;> rfl

/-- A killable name that is no region is no held root. -/
theorem RootbAnchRS.noHeld {Γ : Ctx} {F V : List Var} (h : RootbAnchRS Γ F V) {x : Var} (hxV : x ∈ V)
    (hxF : x ∉ F) (hxr : ∀ Ex, Γ x = some Ex → Ex.mode ≠ .region) : NoHeld Γ x :=
  fun p E hp hm d hd hr ha => by
    rcases h p E hp hm d hd ha.bound_none with h1 | ⟨_, Er, hEr, hreg⟩ | ⟨_, h2, _⟩
    · exact hxF (hr ▸ h1)
    · rw [hr] at hEr; exact hxr Er hEr hreg
    · exact h2 (hr ▸ hxV)

/-- ... nor is a root that is no region and holds views. -/
theorem RootbAnchRS.noHeld_hv {Γ : Ctx} {F V : List Var} (h : RootbAnchRS Γ F V) {x : Var} {Ex : Entry}
    (hxe : Γ x = some Ex) (hv : Ex.ty.holdsView = true) (hxF : x ∉ F) (hxr : Ex.mode ≠ .region) :
    NoHeld Γ x :=
  fun p E hp hm d hd hr ha => by
    rcases h p E hp hm d hd ha.bound_none with h1 | ⟨_, Er, hEr, hreg⟩ | ⟨_, _, Er, hEr, hnv⟩
    · exact hxF (hr ▸ h1)
    · rw [hr, hxe] at hEr; cases hEr; exact hxr hreg
    · rw [hr, hxe] at hEr; cases hEr; rw [hv] at hnv; cases hnv

theorem NoHeldV.of_anchRS {Γ1 : Ctx} {F V : List Var} (h : RootbAnchRS Γ1 F V) {op : Edit} {tx : Ty}
    {P : List Dep} (hthru : ThruOK Γ1 F op tx P) : NoHeldV Γ1 P := fun d hd hv => by
  obtain ⟨hF, _, Er, hEr, _, hcan, _⟩ := hthru d hd
  have hae : argE Γ1 d.root = Er := by unfold argE; rw [hEr]; rfl
  rw [hae] at hv
  exact h.noHeld_hv hEr hv hF (fun e => by have := hcan.ownSlot; rw [e] at this; cases this)

theorem CtxRel.anchRS {Γ Γ' : Ctx} (h : CtxRel Γ Γ') {F V : List Var} (hanch : RootbAnchRS Γ F V) :
    RootbAnchRS Γ' F V := by
  intro p E hp hm
  obtain ⟨E0, h0, hm0, _⟩ := h.mode p E hp
  have h1 := h.rootb p E0 h0 (hm0 ▸ hm)
  rw [hp] at h1
  cases h1
  intro d hd hb
  rcases hanch p _ h0 hm d hd hb with h' | ⟨hk, Er, hEr, hr⟩ | ⟨ha, hn, Er, hEr, hv⟩
  · exact Or.inl h'
  · have hs := h.dom d.root
    rw [hEr] at hs
    obtain ⟨E1, h1⟩ := Option.isSome_iff_exists.mp hs
    obtain ⟨E0', h0', hm1, _⟩ := h.mode d.root E1 h1
    rw [hEr] at h0'; cases h0'
    exact Or.inr (Or.inl ⟨hk, E1, h1, hm1.trans hr⟩)
  · have hs := h.dom d.root
    rw [hEr] at hs
    obtain ⟨E1, h1⟩ := Option.isSome_iff_exists.mp hs
    obtain ⟨E0', h0', _, ht1⟩ := h.mode d.root E1 h1
    rw [hEr] at h0'; cases h0'
    exact Or.inr (Or.inr ⟨ha, hn, E1, h1, by rw [ht1]; exact hv⟩)

theorem CtxRel.exitScope_freshS {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {E : Entry}
    (hx : Γ x = none) (hxF : x ∉ F) (h1 : CtxRel Γ Γ1) (h2 : CtxRel (A2.setE Γ1 x E) Δ)
    (hanch : RootbAnchRH Δ F) (hpin : NoPin Δ x) (hxr : RegionSpared Δ .replace false x)
    (hxh : NoHeld Δ x) : CtxRel Γ (A2.exitScope x Δ) := by
  refine CtxRel.ofDomTy (DomTy.exitScope_fresh hx h1.domTy h2.domTy) (fun p Ep hp hrb => ?_)
    (DKeep.bind h1.dkeep h2.dkeep)
  have hpx : p ≠ x := fun e => by subst e; rw [hx] at hp; cases hp
  have h1p := h1.rootb p Ep hp hrb
  have h2p := h2.rootb p Ep (by simp [A2.setE, upd_ne _ _ hpx, h1p]) hrb
  simp only [A2.exitScope, upd_ne _ _ hpx, A2.kill, h2p, Option.map_some]
  rw [killE_rootbRH hanch hxF .replace false (hpin.kills .replace false) hxr (HeldSpared.of_none hxh _ _) h2p hrb]

/-- A binding the statement opens (a killable name of it), around a body
    that keeps the borrowed parameters. -/
theorem CtxRel.bindS {Γ Γ1 Δ : Ctx} {F V : List Var} {x : Var} {E : Entry}
    (hanch : RootbAnchRS Γ F V) (hxV : x ∈ V) (hx : Γ x = none) (hxF : x ∉ F) (h1 : CtxRel Γ Γ1)
    (hE : E.mode ≠ .rootb) (hEr : E.mode ≠ .region)
    (hk : RootbAnchRS (A2.setE Γ1 x E) F V → CtxRel (A2.setE Γ1 x E) Δ)
    (hpin : NoPin Δ x) : CtxRel Γ (A2.exitScope x Δ) := by
  have hx1 : Γ1 x = none := by
    have := h1.dom x; rw [hx] at this; cases h : Γ1 x <;> simp_all
  have hanch1 : RootbAnchRS (A2.setE Γ1 x E) F V := (h1.anchRS hanch).setE hE hx1
  have h2 := hk hanch1
  have hxm : ∀ Ex, Δ x = some Ex → Ex.mode ≠ .region := fun Ex hEx hr => by
    obtain ⟨E0, h0, hm0, _⟩ := h2.mode x Ex hEx
    simp only [A2.setE, upd_same, Option.some.injEq] at h0; subst h0
    exact hEr (hm0.symm.trans hr)
  have hxr : RegionSpared Δ .replace false x := fun ⟨Ex, hEx, hr⟩ => absurd hr (hxm Ex hEx)
  have hanchΔ := h2.anchRS hanch1
  exact CtxRel.exitScope_freshS hx hxF h1 h2 hanchΔ.toRH hpin hxr (hanchΔ.noHeld hxV hxF hxm)

theorem RhsT.ctxRelS {Γ Γ1 : Ctx} {F V : List Var} {r : Rhs} {E : Entry}
    (hr : RhsT Γ F r E Γ1) (hanch : RootbAnchRS Γ F V) (hV : ∀ y ∈ r.vars, y ∈ V) : CtxRel Γ Γ1 := by
  have hnh : ∀ y Ey, y ∈ r.vars → Γ y = some Ey → Ey.mode ≠ .region → y ∉ F → NoHeld Γ y :=
    fun y Ey hy hEy hr' hyF => hanch.noHeld (hV y hy) hyF (fun Ex h => by rw [hEy] at h; cases h; exact hr')
  have hrh := hanch.toRH
  cases hr with
  | moveOwn hy _ hm hyF hpin => exact CtxRel.movedH hrh hy (by rw [hm]; simp) hyF hpin (by rw [hm]; simp) (hnh _ _ (by simp [Rhs.vars]) hy (by rw [hm]; simp) hyF)
  | moveUp hy _ hm hyF hpin => exact CtxRel.movedH hrh hy (by rw [hm]; simp) hyF hpin (by rw [hm]; simp) (hnh _ _ (by simp [Rhs.vars]) hy (by rw [hm]; simp) hyF)
  | pop hy _ _ hcan hyF =>
    have hnr := hcan.not_region
    exact CtxRel.killH hrh hyF .drop _ (hmn_of_ne_replace _ (by simp) _) (RegionSpared.of_ne hy hnr _ _)
      (HeldSpared.of_none (hnh _ _ (by simp [Rhs.vars]) hy hnr hyF) _ _)
  | remove hy _ _ hcan hyF =>
    have hnr := hcan.not_region
    exact CtxRel.killH hrh hyF .drop _ (hmn_of_ne_replace _ (by simp) _) (RegionSpared.of_ne hy hnr _ _)
      (HeldSpared.of_none (hnh _ _ (by simp [Rhs.vars]) hy hnr hyF) _ _)
  | pair hy _ hp1 hz _ hp2 _ =>
    have h1 := hp1.ctxRelH hy hrh (fun hyF hr' => hnh _ _ (by simp [Rhs.vars]) hy hr' hyF)
    exact h1.trans (hp2.ctxRelH hz (h1.anchRH hrh) (fun hzF hr' =>
      (h1.anchRS hanch).noHeld (hV _ (by simp [Rhs.vars])) hzF (fun Ex h => by rw [hz] at h; cases h; exact hr')))
  | inl hy _ hp _ => exact hp.ctxRelH hy hrh (fun hyF hr' => hnh _ _ (by simp [Rhs.vars]) hy hr' hyF)
  | inr hy _ hp _ => exact hp.ctxRelH hy hrh (fun hyF hr' => hnh _ _ (by simp [Rhs.vars]) hy hr' hyF)
  | takel hy _ hm _ hyF hpin => exact CtxRel.movedH hrh hy (by rw [hm]; simp) hyF hpin (by rw [hm]; simp) (hnh _ _ (by simp [Rhs.vars]) hy (by rw [hm]; simp) hyF)
  | taker hy _ hm _ hyF hpin => exact CtxRel.movedH hrh hy (by rw [hm]; simp) hyF hpin (by rw [hm]; simp) (hnh _ _ (by simp [Rhs.vars]) hy (by rw [hm]; simp) hyF)
  | pack hy _ _ hp _ => exact hp.ctxRelH hy hrh (fun hyF hr' => hnh _ _ (by simp [Rhs.vars]) hy hr' hyF)
  | arcNew hy _ _ _ _ _ _ hp => exact hp.ctxRelH hy hrh (fun hyF hr' => hnh _ _ (by simp [Rhs.vars]) hy hr' hyF)
  | lockNew hy _ _ _ _ _ hp => exact hp.ctxRelH hy hrh (fun hyF hr' => hnh _ _ (by simp [Rhs.vars]) hy hr' hyF)
  | cellNew hy _ _ _ _ _ hp => exact hp.ctxRelH hy hrh (fun hyF hr' => hnh _ _ (by simp [Rhs.vars]) hy hr' hyF)
  | chanSend _ _ _ hy _ _ hp => exact hp.ctxRelH hy hrh (fun hyF hr' => hnh _ _ (by simp [Rhs.vars]) hy hr' hyF)
  | lockRestore _ _ _ hy _ _ hp => exact hp.ctxRelH hy hrh (fun hyF hr' => hnh _ _ (by simp [Rhs.vars]) hy hr' hyF)
  | @take y Ey _ hy _ _ _ hcan _ hyF hpin =>
    have hrb : Ey.mode ≠ .rootb := fun e => by have := hcan.ownSlot; rw [e] at this; cases this
    have hnr : Ey.mode ≠ .region := fun h => by have := hcan.ownSlot; rw [h] at this; cases this
    exact (CtxRel.killH hrh hyF .replace false (hpin.kills .replace false) (RegionSpared.of_ne hy hnr _ _)
      (HeldSpared.of_none (hnh _ _ (by simp [Rhs.vars]) hy hnr hyF) _ _)).trans
      (CtxRel.setE (Ex := killE .replace false y Ey) (by simp [A2.kill, hy]) (by simp [killE_mode])
        (by simp [killE_ty]) (by simp [killE_mode, hrb]) (fun h => by cases h))
  | lockTake _ _ _ => exact CtxRel.refl _
  | arcClone _ _ _ => exact CtxRel.refl _
  | lockClone _ _ _ => exact CtxRel.refl _
  | cellClone _ _ _ => exact CtxRel.refl _
  | glob _ _ => exact CtxRel.refl _
  | rwRead _ _ _ | rwTryRead _ _ _ | rwTryWrite _ _ _ => exact CtxRel.refl _
  | atomic _ _ _ _ _ => exact CtxRel.refl _
  | chanRecv _ _ _ => exact CtxRel.refl _
  | chanClose _ _ _ => exact CtxRel.refl _
  | arcGet _ _ _ _ _ => exact CtxRel.refl _
  | expr _ => exact CtxRel.refl _
  | new _ => exact CtxRel.refl _
  | copyRoot _ _ _ => exact CtxRel.refl _
  | copyBor _ _ _ => exact CtxRel.refl _
  | copyUp _ _ _ _ _ => exact CtxRel.refl _
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
    {Γ' : Ctx} (hc : CallT P Γ F f args E Γ') (hn : NameWF Γ) (hanch : RootbAnchRS Γ F args) :
    ∃ fn, P[f]? = some fn ∧ CallA Γ F fn args ∧ E = callRes Γ fn args ∧ Γ' = callPost Γ fn args := by
  obtain ⟨fn, hf, hlen, harg, hnf, _, hE, hΓ, _⟩ := hc
  exact ⟨fn, hf, ⟨hlen, harg, hnf, hn, hanch⟩, hE, hΓ⟩

/-- A weaker context keeps a fixed entry, so a borrowed parameter's. -/
theorem CtxRel.weaker {Γ Γ' : Ctx} (hw : Weaker Γ Γ') : CtxRel Γ Γ' := by
  refine CtxRel.ofDomTy (DomTy.weaker hw) (fun p Ep hp hrb => ?_) ((DKeep.refl Γ' []).weaker_left hw)
  cases hp' : Γ' p with
  | none => exact absurd ((hw.1 p).1.mpr hp') (by rw [hp]; simp)
  | some E' =>
    have := ((hw.1 p).2 Ep E' hp hp').fixed (Or.inl hrb)
    rw [this]

/-- AGORA-937: what is no region in `Γ` is none after a step that keeps
    every binding's mode. -/
theorem RegionSpared.of_rel {Γ Γ' : Ctx} {e : Eff} {hv : Bool} {x : Var} (h : CtxRel Γ Γ')
    (hs : RegionSpared Γ e hv x) : RegionSpared Γ' e hv x := fun ⟨Ex, hx, hr⟩ => by
  obtain ⟨E0, h0, hm, _⟩ := h.mode x Ex hx
  exact hs ⟨E0, h0, hm ▸ hr⟩

theorem RegionSpared.of_setE {Γ : Ctx} {e : Eff} {hv : Bool} {x y : Var} {E : Entry}
    (hs : RegionSpared Γ e hv x) (hE : E.mode ≠ .region) : RegionSpared (A2.setE Γ y E) e hv x :=
  fun ⟨Ex, hx, hr⟩ => by
    by_cases hxy : x = y
    · subst hxy; simp only [A2.setE, upd_same, Option.some.injEq] at hx; subst hx; exact absurd hr hE
    · simp only [A2.setE, upd_ne _ _ hxy] at hx; exact hs ⟨Ex, hx, hr⟩

/-- A call's typing, without the anchoring `CallA` asks: its callee, result
    and post-context. -/
theorem CallT.toRes {P : Prog} {Γ : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    {Γ' : Ctx} (hc : CallT P Γ F f args E Γ') :
    ∃ fn, P[f]? = some fn ∧ E = callRes Γ fn args ∧ Γ' = callPost Γ fn args := by
  obtain ⟨fn, hf, _, _, _, _, hE, hΓ, _⟩ := hc
  exact ⟨fn, hf, hE, hΓ⟩

/-- An `inout` argument of a call is not lent out. -/
theorem CallT.inout0_notF {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {σ : Nat} {sig : Fn} {c : Var} {E : Entry}
    {b : Eff} {t : Ty} {zs : List Var} {ps : List (PMode × Ty)} (hcT : CallT P Γ F σ (c :: zs) E Γ1)
    (hσ : P[σ]? = some sig) (hsp : sig.params = (.inout b, t) :: ps) : c ∉ F := by
  obtain ⟨sig', hσ', _, hargs, _⟩ := hcT
  rw [hσ] at hσ'; cases hσ'
  obtain ⟨_, _, _, _, hmv, _⟩ := hargs 0 (by simp [hsp])
  exact (hmv (by simp [hsp, PMode.moves])).1

/-- ... and so is one it takes owned (Agora #609). -/
theorem CallT.sink0_notF {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {σ : Nat} {sig : Fn} {c : Var} {E : Entry}
    {t : Ty} (hcT : CallT P Γ F σ [c] E Γ1) (hσ : P[σ]? = some sig)
    (hsp : sig.params = [(.sink, t)]) : c ∉ F := by
  obtain ⟨sig', hσ', _, hargs, _⟩ := hcT
  rw [hσ] at hσ'; cases hσ'
  obtain ⟨_, _, _, _, hmv, _⟩ := hargs 0 (by simp [hsp])
  exact (hmv (by simp [hsp, PMode.moves])).1

/-- ... with any arguments beside it (AGORA-909). -/
theorem CallT.sink0_notF' {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {σ : Nat} {sig : Fn} {c : Var} {E : Entry}
    {t : Ty} {zs : List Var} (hcT : CallT P Γ F σ (c :: zs) E Γ1) (hσ : P[σ]? = some sig)
    (hsp : sig.params = [(.sink, t)]) : c ∉ F := by
  obtain ⟨sig', hσ', _, hargs, _⟩ := hcT
  rw [hσ] at hσ'; cases hσ'
  obtain ⟨_, _, _, _, hmv, _⟩ := hargs 0 (by simp [hsp])
  exact (hmv (by simp [hsp, PMode.moves])).1

theorem CallT.ctxRelS {P : Prog} {Γ : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    {Γ' : Ctx} (hc : CallT P Γ F f args E Γ') (hn : NameWF Γ) (hanch : RootbAnchRS Γ F args) :
    CtxRel Γ Γ' := by
  have hdt := CallT.domTy hc
  have hdk := hc.dkeep
  obtain ⟨fn, _, ha, _, rfl⟩ := hc.toA hn hanch
  exact CtxRel.ofDomTy hdt (fun p Ep hp hrb => ha.post_rootb hp hrb) hdk

/-- **Source typing keeps the borrowed parameters**: every binding stays with
    its mode and type, nothing new is bound, and a borrowed parameter keeps
    its entry where what it borrows from is lent out, a region, or (AGORA-937
    B2) held of a root that is none of the statement's killable names. -/
theorem StmtT.ctxRelS {P : Prog} (hP : ProgOK P) {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P ξ Γ F s Δ) : s.src = true → RootbAnchRS Γ F s.killVars → NameWF Γ → CtxRel Γ Δ := by
  induction ht with
  | skip => exact fun _ _ _ => CtxRel.refl _
  | seq _ ha _ iha ihb =>
    intro hs hanch hn
    simp only [Stmt.src, Bool.and_eq_true] at hs
    have h1 := iha hs.1 (hanch.anti (fun v hv => by simp [Stmt.killVars, hv])) hn
    exact h1.trans (ihb hs.2 ((h1.anchRS hanch).anti (fun v hv => by simp [Stmt.killVars, hv])) (StmtT.names hP ha hs.1 hn))
  | @letv _ Γ Γ1 Δ F x r k E hks hx hxF hr _ hpin _ ih =>
    intro _ hanch hn
    obtain ⟨hn1, hE, _⟩ := hr.names hn
    have hx1 : Γ1 x = none := by
      have := (hr.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h)
      (fun Ex h => by rw [hx1] at h; cases h) hE
    have hnrb : E.mode ≠ .rootb := by rcases (RhsT.out hr).1 with h | h <;> rw [h] <;> simp
    exact CtxRel.bindS hanch (by simp [Stmt.killVars]) hx hxF (hr.ctxRelS hanch (fun v hv => by simp [Stmt.killVars, hv])) hnrb
      (by rcases (RhsT.out hr).1 with h | h <;> rw [h] <;> simp) (fun ha => ih hks (ha.anti (fun v hv => by simp [Stmt.killVars, hv])) hnx) hpin.1
  | @callcE _ Γ Γ1 Δ F x c j zs k Ec E ms q σ sig b hks hx hxF hc4 _ hc6 _ _ hσ hsp _ _ _ hny _ hcT _ hpin _ _ ih =>
    intro _ hanch hn
    have hcF : c ∉ F := hsp.elim (fun ⟨_, h, _⟩ => hcT.inout0_notF hσ h) (fun h => hcT.sink0_notF' hσ h.1)
    -- AGORA-937: the receiver may be replaced, so owns its slot: no region
    have hcn : Ec.mode ≠ .region := hc6.not_region
    have hcr : RegionSpared Γ .replace false c := RegionSpared.of_ne hc4 hcn _ _
    have hcV : c ∈ (Stmt.callcE x c j zs k).killVars := by simp [Stmt.killVars]
    have hk0 := CtxRel.killH hanch.toRH hcF .replace false (hny.kills .replace false) hcr
      (HeldSpared.of_none (hanch.noHeld hcV hcF (fun Ex h => by rw [hc4] at h; cases h; exact hcn)) _ _)
    have hanchk := hk0.anchRS hanch
    obtain ⟨hn1, hE, _⟩ := hcT.names hP (hn.kill .replace false c)
    have hx1 : Γ1 x = none := by
      have := (hcT.domMode).1 x; simp only [A2.kill, hx, Option.map_none, Option.isSome_none] at this
      cases h : Γ1 x <;> simp_all
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h)
      (fun Ex h => by rw [hx1] at h; cases h) hE
    have hnrb : E.mode ≠ .rootb := by
      obtain ⟨fn', _, hE', _⟩ := hcT.toRes; rw [hE']; exact resMode_ne' fn'
    have h1 : CtxRel Γ Γ1 := hk0.trans (hcT.ctxRelS (hn.kill .replace false c) (hanchk.anti (fun v hv => by rcases List.mem_cons.mp hv with rfl | hv <;> simp [Stmt.killVars, hv])))
    refine CtxRel.bindS hanch (by simp [Stmt.killVars]) hx hxF h1 hnrb (by
      obtain ⟨fn', _, hE', _⟩ := hcT.toRes; rw [hE']; exact resMode_region fn')
      (fun ha => ?_) hpin.1
    -- no borrowed parameter changes the package by name: they are the store's
    have hny1 : NoPin (A2.setE Γ1 x E) c := by
      intro p Ep hp hm d hd hb
      have hpx : p ≠ x := fun e => by
        subst e; simp only [A2.setE, upd_same, Option.some.injEq] at hp; subst hp; exact hnrb hm
      simp only [A2.setE, upd_ne _ _ hpx] at hp
      obtain ⟨E0, h0, hm0, _⟩ := h1.mode p Ep hp
      have := h1.rootb p E0 h0 (hm0 ▸ hm)
      rw [hp] at this; cases this
      exact hny p Ep h0 hm d hd hb
    have hcr1 : RegionSpared (A2.setE Γ1 x E) .replace false c :=
      (hcr.of_rel h1).of_setE (by obtain ⟨fn', _, hE', _⟩ := hcT.toRes; rw [hE']; exact resMode_region fn')
    have hcn1 : ∀ Ex, A2.setE Γ1 x E c = some Ex → Ex.mode ≠ .region := fun Ex h hr => by
      obtain ⟨E0, h0, hm0, _⟩ := (h1.trans (CtxRel.refl _)).mode c Ex (by
        have hcx : c ≠ x := fun e => by rw [e, hx] at hc4; cases hc4
        simpa [A2.setE, upd_ne _ _ hcx] using h)
      rw [hc4] at h0; cases h0; exact hcn (hm0 ▸ hr)
    have h2 := CtxRel.killH ha.toRH hcF .replace false (hny1.kills .replace false) hcr1
      (HeldSpared.of_none (ha.noHeld hcV hcF hcn1) _ _)
    exact h2.trans (ih hks ((h2.anchRS ha).anti (fun v hv => by simp [Stmt.killVars, hv])) (hnx.kill _ _ _))
  | @withElem _ Γ Γ1 Δ1 Δ F y x i k Ey E hks hx hxF hyv hym _ hpy _ hr hk _ hpin _ _ ihs ihp =>
    intro _ hanch hn
    have hyF : y ∉ F := by cases hr; assumption
    have hyn : Ey.mode ≠ .region := by rw [hym]; simp
    have hk0 := CtxRel.killH hanch.toRH hyF .replace false (hpy.kills .replace false)
      (RegionSpared.of_ne hyv hyn _ _)
      (HeldSpared.of_none (hanch.noHeld (by simp [Stmt.killVars]) hyF
        (fun Ex h => by rw [hyv] at h; cases h; exact hyn)) _ _)
    have hanchk := hk0.anchRS hanch
    obtain ⟨hn1, hE, _⟩ := hr.names (hn.kill .replace false y)
    have hx1 : Γ1 x = none := by
      have := (hr.domMode).1 x; simp only [A2.kill, hx, Option.map_none] at this
      cases h : Γ1 x <;> simp_all
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h)
      (fun Ex h => by rw [hx1] at h; cases h) hE
    have hnrb : E.mode ≠ .rootb := by rcases (RhsT.out hr).1 with h | h <;> rw [h] <;> simp
    exact CtxRel.bindS hanch (by simp [Stmt.killVars]) hx hxF (hk0.trans (hr.ctxRelS hanchk
      (fun v hv => by simp only [Rhs.vars, List.mem_singleton] at hv; simp [Stmt.killVars, hv]))) hnrb
      (by rcases (RhsT.out hr).1 with h | h <;> rw [h] <;> simp) (fun ha => by
      have h2 := ihs hks (ha.anti (fun v hv => by simp [Stmt.killVars, hv])) hnx
      exact h2.trans (ihp rfl ((h2.anchRS ha).anti fun v hv => by
        simp only [Stmt.killVars, List.mem_cons, List.not_mem_nil, or_false] at hv
        rcases hv with rfl | rfl <;> simp [Stmt.killVars]) (StmtT.names hP hk hks hnx))) hpin.1
  | @withLock _ Γ Δ F a x k Ea t hks hx hxF _ _ _ _ hpin _ _ _ _ ih =>
    intro _ hanch hn
    have hnx := NameWF.setE hn (E := lockE t) (fun Ex h => by rw [hx] at h; cases h)
      (fun Ex h => by rw [hx] at h; cases h) (fun _ _ => by unfold NameOK; rw [lockE_vdeps]; exact DepsNamed.nil _)
    have hnrb : (lockE t).mode ≠ .rootb := by unfold lockE; split <;> simp [intE]
    exact CtxRel.bindS hanch (by simp [Stmt.killVars]) hx hxF (CtxRel.refl _) hnrb
      (by unfold lockE; split <;> simp [intE]) (fun ha => ih hks (ha.anti (fun v hv => by simp [Stmt.killVars, hv])) hnx) hpin.1
  | @letd _ Γ Γ1 Δ F x f r k E t H τ hks hx hxF hr hmo hty hstr _ _ hH _ hpin _ ih =>
    intro _ hanch hn
    obtain ⟨hn1, hE, _⟩ := hr.names hn
    have hx1 : Γ1 x = none := by
      have := (hr.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    have hne : E.ty ≠ .int := hty.ne_int hstr
    have hnx := NameWF.setE hn1 (E := Entry.arm { E with ty := τ, held := H })
      (fun Ex h => by rw [hx1] at h; cases h)
      (fun Ex h => by rw [hx1] at h; cases h) (fun hl _ => (hE hl (Or.inl hne)).widen hmo hH)
    exact CtxRel.bindS (E := Entry.arm { E with ty := τ, held := H }) hanch (by simp [Stmt.killVars]) hx hxF
      (hr.ctxRelS hanch (fun v hv => by simp [Stmt.killVars, hv])) (show E.mode ≠ .rootb by rw [hmo]; simp) (show E.mode ≠ .region by rw [hmo]; simp)
      (fun ha => ih hks (ha.anti (fun v hv => by simp [Stmt.killVars, hv])) hnx) hpin.1
  | @letcall _ Γ Γ1 Δ F x f args k E hks hx hxF hc _ hpin _ ih =>
    intro _ hanch hn
    obtain ⟨hn1, hE, _⟩ := hc.names hP hn
    have hx1 : Γ1 x = none := by
      have := (hc.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h)
      (fun Ex h => by rw [hx1] at h; cases h) hE
    have hnrb : E.mode ≠ .rootb := by
      obtain ⟨fn, _, hE', _⟩ := hc.toRes; rw [hE']; exact resMode_ne' fn
    exact CtxRel.bindS hanch (by simp [Stmt.killVars]) hx hxF (hc.ctxRelS hn (hanch.anti (fun v hv => by simp [Stmt.killVars, hv]))) hnrb (by
      obtain ⟨fn', _, hE', _⟩ := hc.toRes; rw [hE']; exact resMode_region fn') (fun ha => ih hks (ha.anti (fun v hv => by simp [Stmt.killVars, hv])) hnx) hpin.1
  | @letrec _ Γ Γ1 Δ F x f k E fn hks hx hxF _ _ _ _ hc _ hpin ih =>
    intro _ hanch hn
    obtain ⟨hn1, hE, _⟩ := hc.names hP hn
    have hx1 : Γ1 x = none := by
      have := (hc.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h)
      (fun Ex h => by rw [hx1] at h; cases h) hE
    have hnrb : E.mode ≠ .rootb := by
      obtain ⟨fn', _, hE', _⟩ := hc.toRes; rw [hE']; exact resMode_ne' fn'
    exact CtxRel.bindS hanch (by simp [Stmt.killVars]) hx hxF (hc.ctxRelS hn (hanch.anti fun v hv => by cases hv)) hnrb (by
      obtain ⟨fn', _, hE', _⟩ := hc.toRes; rw [hE']; exact resMode_region fn') (fun ha => ih hks (ha.anti (fun v hv => by simp [Stmt.killVars, hv])) hnx) hpin.1
  | @callc _ Γ Γ1 Δ F x c j zs k Ec E ms q σ sig hks hx hxF _ _ _ _ _ _ hcT _ _ hpin _ ih =>
    intro _ hanch hn
    obtain ⟨hn1, hE, _⟩ := hcT.names hP hn
    have hx1 : Γ1 x = none := by
      have := (hcT.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    have hnx : NameWF (A2.setE Γ1 x (recvRes c Ec E)) := NameWF.setE hn1
      (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) (recvRes_named hE)
    have hnrb : (recvRes c Ec E).mode ≠ .rootb := by
      obtain ⟨fn, _, hE', _⟩ := hcT.toRes
      show E.mode ≠ .rootb; rw [hE']; exact resMode_ne' fn
    exact CtxRel.bindS hanch (by simp [Stmt.killVars]) hx hxF (hcT.ctxRelS hn (hanch.anti (fun v hv => by rcases List.mem_cons.mp hv with rfl | hv <;> simp [Stmt.killVars, hv]))) hnrb (by
      obtain ⟨fn', _, hE', _⟩ := hcT.toRes; show E.mode ≠ .region; rw [hE']; exact resMode_region fn')
      (fun ha => ih hks (ha.anti (fun v hv => by simp [Stmt.killVars, hv])) hnx) hpin.1
  | @unpair _ Γ Δ F y x z k E a b hks hy hl hcan hty hyF hx hz hxz hxF hzF _ hpy _ hpz hpx _ _ ih =>
    intro _ hanch hn
    have hnrbE : E.mode ≠ .rootb := by rcases hcan with h | ⟨b, h, _⟩ <;> rw [h] <;> simp
    have hyn : E.mode ≠ .region := by rcases hcan with h | ⟨b, h, _⟩ <;> rw [h] <;> simp
    have h0 : CtxRel Γ (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) :=
      CtxRel.movedH hanch.toRH hy hnrbE hyF hpy hyn
        (hanch.noHeld (by simp [Stmt.killVars]) hyF (fun Ex h => by rw [hy] at h; cases h; exact hyn))
    have hxy : x ≠ y := fun e => by rw [e, hy] at hx; cases hx
    have hzy : z ≠ y := fun e => by rw [e, hy] at hz; cases hz
    have hx0 : (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) x = none := by
      simp [A2.setE, upd_ne _ _ hxy, A2.kill, hx]
    have hz1 : (A2.setE (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) x (compE E a)) z = none := by
      simp [A2.setE, upd_ne _ _ (Ne.symm hxz), upd_ne _ _ hzy, A2.kill, hz]
    have hn2 := hn.unpair (a := a) (b := b) hy hl (unpair_ne_int hty) hx hz hxz
    exact h0.trans (CtxRel.bindS (h0.anchRS hanch) (by simp [Stmt.killVars]) hx0 hxF (CtxRel.refl _) (compE_mode_ne E a)
      (compE_mode_ne_region E a) (fun ha1 => CtxRel.bindS ha1 (by simp [Stmt.killVars]) hz1 hzF (CtxRel.refl _) (compE_mode_ne E b)
        (compE_mode_ne_region E b) (fun ha2 => ih hks (ha2.anti (fun v hv => by simp [Stmt.killVars, hv])) hn2) hpz.1) hpx.1)
  | @assign _ Γ Γ1 F x r Ex E hx hxF hmodes hr hty _ hx1s hpin _ =>
    intro _ hanch _
    have h1 := hr.ctxRelS hanch (fun v hv => by simp [Stmt.killVars, hv])
    obtain ⟨Ex1, hEx1⟩ := Option.isSome_iff_exists.mp hx1s
    obtain ⟨E0, h0, hm0, ht0⟩ := h1.mode x Ex1 hEx1
    rw [hx] at h0; cases h0
    have hnrbx : Ex.mode ≠ .rootb := by
      rcases hmodes with ⟨h, _⟩ | ⟨h, _⟩ | ⟨h, _⟩ <;> rw [h] <;> simp
    have hxn : Ex1.mode ≠ .region := by
      rw [hm0]; rcases hmodes with ⟨h, _⟩ | ⟨h, _⟩ | ⟨h, _⟩ <;> rw [h] <;> simp
    have hpin1 : NoPin Γ1 x := fun p Ep hp hm => hpin p Ep (h1.rootb_back hp hm) hm
    refine h1.trans ((CtxRel.killH (h1.anchRS hanch).toRH hxF .replace false (hpin1.kills .replace false)
      (RegionSpared.of_ne hEx1 hxn _ _)
      (HeldSpared.of_none ((h1.anchRS hanch).noHeld (by simp [Stmt.killVars]) hxF
        (fun Ex' h => by rw [hEx1] at h; cases h; exact hxn)) _ _)).trans
      (CtxRel.setE (Ex := killE .replace false x Ex1) (by simp [A2.kill, hEx1]) ?_ ?_ ?_
        fun hd => absurd hd (by simp [hr.dtor_false.2])))
    · simp [killE_mode, hm0]
    · simp [killE_ty, ht0, hty]
    · simp [killE_mode, hm0, hnrbx]
  | ite ha _ _ _ _ iha _ => exact fun _ hanch hn => iha ha (hanch.anti (fun v hv => by simp [Stmt.killVars, hv])) hn
  | «while» => exact fun _ _ _ => CtxRel.refl _
  | @push _ Γ Γ1 F x y Ex Ey Ex1 t D hx _ hxt hcan hxF hy _ _ _ hpa _ hx1 _ _ hdb =>
    intro _ hanch _
    have h1 := hpa.ctxRelH hy hanch.toRH (fun hyF hr => hanch.noHeld (by simp [Stmt.killVars]) hyF
      (fun Ex' h => by rw [hy] at h; cases h; exact hr))
    obtain ⟨E0, h0, hm0, ht0⟩ := h1.mode x Ex1 hx1
    rw [hx] at h0; cases h0
    have hnrb : Ex1.mode ≠ .rootb := by
      rw [hm0]; rcases hcan with h | ⟨b, h, _⟩ <;> rw [h] <;> simp
    have hxn : Ex1.mode ≠ .region := by rw [hm0]; exact hcan.not_region
    -- what a `letd` binding gains it views already (Agora #782)
    have hos1 : Ex1.mode.ownSlot = true := by rw [hm0]; exact hcan.ownSlot
    exact h1.trans ((CtxRel.killH (h1.anchRS hanch).toRH hxF .realloc _ (hmn_of_ne_replace _ (by simp) _)
      (RegionSpared.of_ne hx1 hxn _ _)
      (HeldSpared.of_none ((h1.anchRS hanch).noHeld (by simp [Stmt.killVars]) hxF
        (fun Ex' h => by rw [hx1] at h; cases h; exact hxn)) _ _)).trans
      (CtxRel.setE (Ex := killE .realloc t.holdsView x Ex1) (by simp [A2.kill, hx1]) (by simp [killE_mode]) (by simp [killE_ty])
        (by simp [killE_mode, hnrb])
        fun hd => ⟨by rw [killE_dbind]; exact hd, fun d hdd _ => by
          rw [killE_vdeps]
          simp only [Entry.vdeps, hos1, ↓reduceIte, List.nil_append, List.mem_append] at hdd ⊢
          rcases hdd with hdd | hdd
          · exact hdd
          · exact hdb hd hdd⟩))
  | editB hx hmx _ _ _ _ harg hyx hx1 hl1 hthru =>
    exact fun _ hanch _ => CtxRel.editBH hanch.toRH hx hmx harg hyx hx1 hl1 hthru
      (fun y hy hyF hr => hanch.noHeld (Edit.stored_vars hy) hyF hr)
  | editBV hx hmx _ _ _ _ _ harg hyx hx1 hl1 _ hthru hV =>
    intro _ hanch _
    exact CtxRel.editBVH hanch.toRH hx hmx harg hyx hx1 hl1 hthru hV
      (fun y hy hyF hr => hanch.noHeld (Edit.stored_vars hy) hyF hr)
      (NoHeldV.of_anchRS ((harg.ctxRelH hanch.toRH
        (fun y hy hyF hr => hanch.noHeld (Edit.stored_vars hy) hyF hr)).anchRS hanch) hthru)
  | @takeB _ Γ Δ F x y i k Ex t hks hy hyF hx hmx hl hty _ _ hie hthru _ _ hend ih =>
    intro _ hanch hn
    have hnrb : (compE Ex t).mode ≠ .rootb := by cases t <;> simp [compE, intE]
    exact CtxRel.bindS hanch (by simp [Stmt.killVars]) hy hyF
      (CtxRel.editBH hanch.toRH hx hmx (EditArg.trunc (t := t) hie) (fun _ h => by cases h) hx hl hthru
        (fun _ h => by cases h))
      hnrb (compE_mode_ne_region Ex t) (fun ha => ih hks (ha.anti (fun v hv => by simp [Stmt.killVars, hv])) (takeB_nameWF hn hy hx hmx hl hty)) hend.1
  | @takeBV _ Γ Δ F x y i k Ex t hks hy hyF hx hmx hl hty _ _ hie _ hthru hV _ _ hend ih =>
    intro _ hanch hn
    have hnrb : (compE Ex t).mode ≠ .rootb := by cases t <;> simp [compE, intE]
    exact CtxRel.bindS hanch (by simp [Stmt.killVars]) hy hyF
      (CtxRel.editBV_truncH (t := t) hanch.toRH hx hmx hl hie hthru hV (NoHeldV.of_anchRS hanch hthru))
      hnrb (compE_mode_ne_region Ex t) (fun ha => ih hks (ha.anti (fun v hv => by simp [Stmt.killVars, hv])) (takeBV_nameWF hn hy hx hmx hl hty)) hend.1
  | @free _ Γ F x E t hx _ hmo _ hxF hpin =>
    exact fun _ hanch _ => CtxRel.movedH hanch.toRH hx (by rw [hmo]; simp) hxF hpin.1 (by rw [hmo]; simp)
      (hanch.noHeld (by simp [Stmt.killVars]) hxF (fun Ex h => by rw [hx] at h; cases h; rw [hmo]; simp))
  | insert _ _ _ ih => exact fun _ hanch hn => ih rfl (hanch.anti (fun v hv => by
      simp only [Stmt.killVars, List.mem_cons, List.not_mem_nil, or_false] at hv
      rcases hv with rfl | rfl <;> simp [Stmt.killVars])) hn
  | sub hw _ ho ih =>
    intro hs hanch _
    have h0 := CtxRel.weaker hw
    have h1 := ih hs (h0.anchRS hanch) hw.2.2
    rcases ho with rfl | hwo
    · exact h0.trans h1
    · exact (h0.trans h1).trans (CtxRel.weaker hwo)
  | @panic _ Γ Δ F _ _ hdom hm hdk =>
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
  | scopeL => intro hs; simp [Stmt.src] at hs
  | scope => intro hs; simp [Stmt.src] at hs
  | rbind => intro hs; simp [Stmt.src] at hs
  | frozen => intro hs; simp [Stmt.src] at hs

  | @exit _ Γ Δ F _ _ _ _ hdom hm hdk =>
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
  | @loop _ Γ Δ F _ _ _ _ _ hdom hm hdk =>
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
  | block _ ih => exact ih

/-- ... on the strict anchors, as a callee's body has them. -/
theorem StmtT.ctxRel {P : Prog} (hP : ProgOK P) {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P ξ Γ F s Δ) (hs : s.src = true) (hanch : RootbAnchR Γ F) (hn : NameWF Γ) : CtxRel Γ Δ :=
  StmtT.ctxRelS hP ht hs (hanch.toRS _) hn

theorem CtxRel.keepOut {Γ Δ : Ctx} (h : CtxRel Γ Δ) : KeepOut Γ Δ [] := by
  have hk := h.keep (s := .skip) (s' := .skip) rfl rfl
  exact ⟨fun v E hv _ => (hk.1 v E hv (by simp [Stmt.spine])).2,
    fun v E' hv => ⟨by simp, (hk.2.1 v E' hv (by simp [Stmt.spine])).2⟩⟩

/-- **What a destructor's frame needs of its body**, from the body's typing
    alone: `letd` takes no premise for it. -/
theorem srcCase {P : Prog} (hP : ProgOK P) : SrcCase P :=
  fun ht hs hanch hw hn hf =>
    ⟨(StmtT.ctxRelS hP ht hs hanch hn).keepOut, StmtT.wf hP ht hw, StmtT.names hP ht hs hn,
      StmtT.freshOK hP ht hs hf⟩

end A2
