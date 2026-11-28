module

public import A2.Fresh

@[expose] public section

/-! A2 — what keeps a context's domain, modes and types (`DomTy`): kills,
    updates, a right-hand side, a call's post-context.  Before the renaming lemma,
    which reads a call's post-context through it (AGORA-937 B4). -/

namespace A2

/-! ### A source statement keeps the domain, modes and types -/

def DomTy (Γ0 Γ : Ctx) : Prop :=
  (∀ x, (Γ x).isSome = (Γ0 x).isSome) ∧
  ∀ x E, Γ x = some E → ∃ E0, Γ0 x = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty

theorem DomTy.refl (Γ : Ctx) : DomTy Γ Γ := ⟨fun _ => rfl, fun _ E h => ⟨E, h, rfl, rfl⟩⟩

theorem DomTy.trans {Γ1 Γ2 Γ3 : Ctx} (h1 : DomTy Γ1 Γ2) (h2 : DomTy Γ2 Γ3) : DomTy Γ1 Γ3 := by
  refine ⟨fun x => (h2.1 x).trans (h1.1 x), fun x E h => ?_⟩
  obtain ⟨E2, h2', hm2, ht2⟩ := h2.2 x E h
  obtain ⟨E1, h1', hm1, ht1⟩ := h1.2 x E2 h2'
  exact ⟨E1, h1', hm2.trans hm1, ht2.trans ht1⟩

theorem DomTy.kill {Γ0 Γ : Ctx} (h : DomTy Γ0 Γ) (e : Eff) (hv : Bool) (x : Var) :
    DomTy Γ0 (A2.kill e hv x Γ) := by
  refine ⟨fun y => by rw [kill_dom]; exact h.1 y, fun y E hy => ?_⟩
  obtain ⟨E1, h1, hm1, _⟩ := kill_cmode hy
  obtain ⟨E0, h0, hm0, ht0⟩ := h.2 y E1 h1
  simp only [A2.kill, h1, Option.map_some, Option.some.injEq] at hy; subst hy
  exact ⟨E0, h0, by rw [killE_mode, hm0], by rw [killE_ty, ht0]⟩

theorem DomTy.setE {Γ0 Γ : Ctx} (h : DomTy Γ0 Γ) {x : Var} {E : Entry}
    (hx : ∃ E0, Γ0 x = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty) : DomTy Γ0 (A2.setE Γ x E) := by
  obtain ⟨E0, h0, hm, ht⟩ := hx
  refine ⟨fun y => ?_, fun y E' hy => ?_⟩
  · by_cases hyx : y = x
    · subst hyx; simp [A2.setE, h0]
    · simp only [A2.setE, upd_ne _ _ hyx]; exact h.1 y
  · by_cases hyx : y = x
    · subst hyx; simp only [A2.setE, upd_same, Option.some.injEq] at hy; subst hy; exact ⟨E0, h0, hm, ht⟩
    · simp only [A2.setE, upd_ne _ _ hyx] at hy; exact h.2 y E' hy

theorem DomTy.killNames {Γ0 Γ : Ctx} (h : DomTy Γ0 Γ) : ∀ ds, DomTy Γ0 (A2.killNames ds Γ)
  | [] => h
  | _ :: ds => show DomTy Γ0 (A2.kill _ _ _ (A2.killNames ds Γ)) from (DomTy.killNames h ds).kill _ _ _

theorem DomTy.killHv {Γ0 Γ : Ctx} (h : DomTy Γ0 Γ) : ∀ ks, DomTy Γ0 (A2.killHv ks Γ)
  | [] => h
  | (_, _, _) :: ks => show DomTy Γ0 (A2.kill _ _ _ (A2.killHv ks Γ)) from (DomTy.killHv h ks).kill _ _ _

theorem DomTy.holdOn {Γ0 Γ : Ctx} (h : DomTy Γ0 Γ) (rs : List Var) (D : List Dep) :
    DomTy Γ0 (A2.holdOn rs D Γ) := by
  refine ⟨fun x => by rw [holdOn_isSome]; exact h.1 x, fun x E' hE' => ?_⟩
  obtain ⟨E, hE, rfl⟩ := holdOn_get hE'
  obtain ⟨E0, h0, hm, ht⟩ := h.2 x E hE
  exact ⟨E0, h0, by split <;> exact hm, by split <;> exact ht⟩

/-- What running the closures handed to a call leaves of a binding. -/
theorem killNames_get {Γ : Ctx} {y : Var} : ∀ (ds : List Dep) {E : Entry}, killNames ds Γ y = some E →
    ∃ E0, Γ y = some E0 ∧ E.ty = E0.ty ∧ E.mode = E0.mode ∧ E.path = E0.path ∧ E.held = E0.held ∧
      (E.live = true → E0.live = true ∧ ∀ d ∈ ds, hits d.kind.bound false d.root E0 = false)
  | [], E, h => ⟨E, h, rfl, rfl, rfl, rfl, fun hl => ⟨hl, fun _ hd => by cases hd⟩⟩
  | d :: ds, E, h => by
    change (A2.kill _ _ _ (A2.killNames ds Γ)) y = some E at h
    simp only [A2.kill] at h
    cases h1 : killNames ds Γ y with
    | none => rw [h1] at h; cases h
    | some E1 =>
      rw [h1] at h; simp only [Option.map_some, Option.some.injEq] at h; subst h
      obtain ⟨E0, h0, ht, hm, hp, hh, hl⟩ := killNames_get ds h1
      refine ⟨E0, h0, by rw [killE_ty, ht], by rw [killE_mode, hm], by rw [killE_path, hp],
        by rw [killE_held, hh], fun hl' => ?_⟩
      rw [killE_live] at hl'
      simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hl'
      obtain ⟨hl1, hs⟩ := hl hl'.1
      have hvd : E1.vdeps = E0.vdeps := by unfold Entry.vdeps; rw [hm, hp, hh]
      refine ⟨hl1, fun d' hd' => ?_⟩
      rcases List.mem_cons.mp hd' with rfl | hd'
      · have := hl'.2; unfold hits at this ⊢; rwa [ht, hm, hvd] at this
      · exact hs d' hd'

theorem DomTy.weaker {Γ Γ' : Ctx} (hw : Weaker Γ Γ') : DomTy Γ Γ' := by
  refine ⟨fun x => (hw.isSome x).symm, fun x E h => ?_⟩
  obtain ⟨E0, h0, hw0⟩ := hw.get' h
  exact ⟨E0, h0, hw0.mode, hw0.1⟩

theorem PushArg.domTy {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hy : Γ y = some Ey) (hp : PushArg Γ F y Ey t D Γ1) : DomTy Γ Γ1 := by
  cases hp with
  | move _ _ => exact ((DomTy.refl Γ).kill .replace false y).setE ⟨Ey, hy, rfl, rfl⟩
  | int => exact DomTy.refl Γ
  | slice _ => exact DomTy.refl Γ

theorem EditArg.domTy {Γ Γ1 : Ctx} {F : List Var} {op : Edit} {t : Ty} {D : List Dep}
    (h : EditArg Γ F op t D Γ1) : DomTy Γ Γ1 := by
  cases h with
  | push hy _ _ hpa => exact PushArg.domTy hy hpa
  | trunc _ => exact DomTy.refl Γ
  | set _ hy _ _ hpa => exact PushArg.domTy hy hpa

theorem RhsT.domTy {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1) :
    DomTy Γ Γ1 := by
  cases hr with
  | @moveOwn y Ey hy _ _ _ => exact ((DomTy.refl Γ).kill .replace false y).setE ⟨Ey, hy, rfl, rfl⟩
  | @moveUp y Ey _ _ _ hy => exact ((DomTy.refl Γ).kill .replace false y).setE ⟨Ey, hy, rfl, rfl⟩
  | pop _ _ _ _ _ => exact (DomTy.refl Γ).kill _ _ _
  | remove _ _ _ _ _ _ _ => exact (DomTy.refl Γ).kill _ _ _
  | pair hy _ hpa1 hz _ hpa2 _ => exact (PushArg.domTy hy hpa1).trans (PushArg.domTy hz hpa2)
  | inl hy _ hpa _ => exact PushArg.domTy hy hpa
  | inr hy _ hpa _ => exact PushArg.domTy hy hpa
  | pack hy _ _ hpa => exact PushArg.domTy hy hpa
  | arcNew hy _ _ _ _ _ _ hpa => exact PushArg.domTy hy hpa
  | lockNew hy _ _ _ _ _ hpa => exact PushArg.domTy hy hpa
  | cellNew hy _ _ _ _ _ hpa => exact PushArg.domTy hy hpa
  | chanSend _ _ _ hy _ _ hpa => exact PushArg.domTy hy hpa
  | lockRestore _ _ _ hy _ _ hpa => exact PushArg.domTy hy hpa
  | @takel y Ey _ _ hy _ _ _ _ => exact ((DomTy.refl Γ).kill .replace false y).setE ⟨Ey, hy, rfl, rfl⟩
  | @taker y Ey _ _ hy _ _ _ _ => exact ((DomTy.refl Γ).kill .replace false y).setE ⟨Ey, hy, rfl, rfl⟩
  | @take y Ey _ hy => exact ((DomTy.refl Γ).kill .replace false y).setE ⟨Ey, hy, rfl, rfl⟩
  | _ => exact DomTy.refl Γ

theorem callPostAux_domTy {Γ0 : Ctx} {fn : Fn} {args : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ a ∈ as, ∃ E0, Γ0 a = some E0) → DomTy Γ0 Γ →
      DomTy Γ0 (callPostAux Γ0 fn args ps as i Γ) := by
  intro ps
  induction ps with
  | nil => intro as i Γ _ hd; cases as <;> exact hd
  | cons p ps ih =>
    intro as i Γ has hd
    obtain ⟨pm, t⟩ := p
    cases as with
    | nil => cases pm <;> exact hd
    | cons a as =>
      obtain ⟨E0, h0⟩ := has a (by simp)
      have has' : ∀ a' ∈ as, ∃ E0, Γ0 a' = some E0 := fun a' h' => has a' (by simp [h'])
      have hargE : argE Γ0 a = E0 := by unfold argE; rw [h0]; rfl
      cases pm with
      | inp => exact ih as (i + 1) Γ has' hd
      | sink => exact ih as (i + 1) _ has' ((hd.kill _ _ _).setE ⟨E0, h0, by rw [hargE], by rw [hargE]⟩)
      | inout b => exact ih as (i + 1) _ has' ((hd.kill _ _ _).setE ⟨E0, h0, by rw [hargE], by rw [hargE]⟩)

theorem CallT.domTy {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {f : Nat} {args : List Var}
    {E : Entry} (hc : CallT P Γ F f args E Γ1) : DomTy Γ Γ1 := by
  obtain ⟨fn, _, hlen, hargs, _, _, _, rfl, _⟩ := hc
  refine DomTy.killNames (callPostAux_domTy _ _ _ _ (fun a ha => ?_) (DomTy.refl Γ)) _
  obtain ⟨i, hi, rfl⟩ := mem_args ha
  obtain ⟨Ea, hEa, _⟩ := hargs i (hlen ▸ hi)
  exact ⟨Ea, hEa⟩


end A2
