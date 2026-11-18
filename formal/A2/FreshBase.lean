import A2.Basic

/-! A2 — Agora #909: the context facts `FreshOK` needs, early enough for the
invariant (`MInv.fresh`) and every rule's proof to use. -/

namespace A2

theorem reroot_self {p : Var} {D ds : List Dep} (h : ∀ d ∈ ds, d.root ≠ p) : reroot p D ds = ds := by
  induction ds with
  | nil => rfl
  | cons d ds ih =>
    simp only [reroot, List.flatMap_cons] at ih ⊢
    rw [if_neg (h d (List.mem_cons_self ..)), ih (fun d' hd' => h d' (List.mem_cons_of_mem _ hd'))]
    rfl
/-- What a right-hand side changes keeps the frame's own bindings. -/
def KeepsFrame (Γ Γ1 : Ctx) : Prop :=
  ∀ r Er, Γ r = some Er → Er.mode.frame → ∃ Er', Γ1 r = some Er' ∧ Er'.mode.frame

theorem KeepsFrame.refl (Γ : Ctx) : KeepsFrame Γ Γ := fun _ Er h hm => ⟨Er, h, hm⟩

theorem KeepsFrame.trans {Γ1 Γ2 Γ3 : Ctx} (h1 : KeepsFrame Γ1 Γ2) (h2 : KeepsFrame Γ2 Γ3) :
    KeepsFrame Γ1 Γ3 := fun r Er h hm => by
  obtain ⟨E2, h2', hm2⟩ := h1 r Er h hm
  exact h2 r E2 h2' hm2

theorem KeepsFrame.kill (Γ : Ctx) (e : Eff) (hv : Bool) (x : Var) : KeepsFrame Γ (kill e hv x Γ) :=
  fun _ Er h hm => ⟨killE e hv x Er, by simp [A2.kill, h], by unfold killE; split <;> exact hm⟩

theorem KeepsFrame.setE {Γ : Ctx} {x : Var} {E : Entry}
    (hx : ∀ Ex, Γ x = some Ex → Ex.mode.frame → E.mode.frame) : KeepsFrame Γ (A2.setE Γ x E) := by
  intro r Er h hm
  by_cases hrx : r = x
  · subst hrx; exact ⟨E, by simp [A2.setE], hx Er h hm⟩
  · exact ⟨Er, by simp [A2.setE, upd_ne _ _ hrx, h], hm⟩

@[simp] theorem elemE_fresh (y : Var) (E : Entry) (t : Ty) : (elemE y E t).fresh = false := by
  cases t <;> rfl
@[simp] theorem popE_fresh (y : Var) (E : Entry) (t : Ty) : (popE y E t).fresh = false := by
  cases t <;> rfl
@[simp] theorem projE_fresh (y : Var) (E : Entry) (t : Ty) : (projE y E t).fresh = false := by
  cases t <;> rfl
@[simp] theorem getE_fresh (y : Var) (E : Entry) (t : Ty) : (getE y E t).fresh = false := by
  cases t <;> rfl
@[simp] theorem compE_fresh (E : Entry) (t : Ty) : (compE E t).fresh = false := by
  cases t <;> rfl
@[simp] theorem intE_fresh : intE.fresh = false := rfl
@[simp] theorem lockE_fresh (t : Ty) : (lockE t).fresh = false := by
  unfold lockE; split <;> rfl

/-- Moving `y` out: its entry is dead, of the same mode. -/
theorem FreshOK.moved {Γ : Ctx} (h : FreshOK Γ) {y : Var} {E : Entry} (hy : Γ y = some E) :
    FreshOK (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) ∧
    KeepsFrame Γ (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) := by
  have hk : ∀ Ex, A2.kill .replace false y Γ y = some Ex → Ex.mode = E.mode := by
    intro Ex hEx; simp [A2.kill, hy] at hEx; rw [← hEx]; unfold killE; split <;> rfl
  refine ⟨(h.kill _ _ _).setE_same (Or.inr rfl) (fun Ex hEx => hk Ex hEx), ?_⟩
  exact (KeepsFrame.kill Γ _ _ _).trans (KeepsFrame.setE (fun Ex hEx hm => by
    show E.mode.frame; rw [← hk Ex hEx]; exact hm))

/-- `Γ`'s live fresh borrows are `Γ0`'s, with the same path. -/
def FreshLe (Γ0 Γ : Ctx) : Prop :=
  ∀ v E, Γ v = some E → E.live = true → E.ty ≠ .int → E.mode = .bor → E.fresh = true →
    ∃ E0, Γ0 v = some E0 ∧ E0.live = true ∧ E0.ty ≠ .int ∧ E0.mode = .bor ∧ E0.fresh = true ∧
      E.path ⊆ E0.path ∧ E0.path ⊆ E.path

theorem FreshLe.refl (Γ : Ctx) : FreshLe Γ Γ := fun _ E h hl hn hb hf =>
  ⟨E, h, hl, hn, hb, hf, List.Subset.refl _, List.Subset.refl _⟩

theorem FreshOK.of_le {Γ0 Γ : Ctx} (h : FreshOK Γ0) (hl : FreshLe Γ0 Γ) (hk : KeepsFrame Γ0 Γ) :
    FreshOK Γ := by
  intro v E hv hlv hn hb hf
  obtain ⟨E0, h0, hl0, hn0, hb0, hf0, hs1, hs2⟩ := hl v E hv hlv hn hb hf
  obtain ⟨hne, hd⟩ := h v E0 h0 hl0 hn0 hb0 hf0
  refine ⟨fun he => hne (List.eq_nil_of_subset_nil (he ▸ hs2)), fun d hdd => ?_⟩
  obtain ⟨hkd, Er, hEr, hm⟩ := hd d (hs1 hdd)
  exact ⟨hkd, hk d.root Er hEr hm⟩

theorem FreshLe.trans {Γ1 Γ2 Γ3 : Ctx} (h1 : FreshLe Γ1 Γ2) (h2 : FreshLe Γ2 Γ3) : FreshLe Γ1 Γ3 := by
  intro v E h hl hn hb hf
  obtain ⟨E2, h2', hl2, hn2, hb2, hf2, a2, b2⟩ := h2 v E h hl hn hb hf
  obtain ⟨E1, h1', hl1, hn1, hb1, hf1, a1, b1⟩ := h1 v E2 h2' hl2 hn2 hb2 hf2
  exact ⟨E1, h1', hl1, hn1, hb1, hf1, a2.trans a1, b1.trans b2⟩

theorem FreshLe.kill (Γ : Ctx) (e : Eff) (hv : Bool) (x : Var) : FreshLe Γ (A2.kill e hv x Γ) := by
  intro v E' h hl hn hb hf
  simp only [A2.kill] at h
  obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp h
  have hk : (killE e hv x E).ty = E.ty ∧ (killE e hv x E).mode = E.mode ∧
      (killE e hv x E).fresh = E.fresh ∧ (killE e hv x E).path = E.path := by
    unfold killE; split <;> simp
  rw [hk.1] at hn; rw [hk.2.1] at hb; rw [hk.2.2.1] at hf; rw [hk.2.2.2]
  exact ⟨E, hE, killE_live_le hl, hn, hb, hf, List.Subset.refl _, List.Subset.refl _⟩

/-- Binding `x` to an entry made from `Γ0`'s own entry for `x` (or one that
    is no live fresh borrow). -/
theorem FreshLe.setE {Γ0 Γ : Ctx} (h : FreshLe Γ0 Γ) {x : Var} {E : Entry}
    (hE : E.live = true → E.ty ≠ .int → E.mode = .bor → E.fresh = true →
      ∃ E0, Γ0 x = some E0 ∧ E0.live = true ∧ E0.ty ≠ .int ∧ E0.mode = .bor ∧ E0.fresh = true ∧
        E.path ⊆ E0.path ∧ E0.path ⊆ E.path) :
    FreshLe Γ0 (A2.setE Γ x E) := by
  intro v E' hv hl hn hb hf
  by_cases hvx : v = x
  · subst hvx; simp [A2.setE] at hv; subst hv; exact hE hl hn hb hf
  · simp only [A2.setE, upd_ne _ _ hvx] at hv; exact h v E' hv hl hn hb hf

theorem KeepsFrame.of_src {Γ0 Γ : Ctx} (hk : KeepsFrame Γ0 Γ) {x : Var} {E : Entry}
    (hx : ∀ Ex, Γ0 x = some Ex → Ex.mode.frame → E.mode.frame) : KeepsFrame Γ0 (A2.setE Γ x E) := by
  intro r Er h hm
  by_cases hrx : r = x
  · subst hrx; exact ⟨E, by simp [A2.setE], hx Er h hm⟩
  · obtain ⟨E2, h2, hm2⟩ := hk r Er h hm
    exact ⟨E2, by simp [A2.setE, upd_ne _ _ hrx, h2], hm2⟩

@[simp] theorem callRes_fresh (Γ : Ctx) (fn : Fn) (args : List Var) : (callRes Γ fn args).fresh = false := rfl
@[simp] theorem recvRes_fresh (c : Var) (Ec E : Entry) : (recvRes c Ec E).fresh = E.fresh := rfl

theorem kill_at_none {Γ : Ctx} {v : Var} (h : Γ v = none) (e : Eff) (hv : Bool) (x : Var) :
    A2.kill e hv x Γ v = none := by simp [A2.kill, h]

theorem setE_none {Γ : Ctx} {v x : Var} {E : Entry} (h : Γ v = none) (hvx : v ≠ x) :
    A2.setE Γ x E v = none := by simp [A2.setE, upd_ne _ _ hvx, h]

/-- Binding a new name. -/
theorem FreshOK.bind {Γ : Ctx} (h : FreshOK Γ) {x : Var} {E : Entry} (hx : Γ x = none)
    (hE : FreshE Γ E) : FreshOK (A2.setE Γ x E) :=
  h.setE (hE.mono (KeepsFrame.setE (fun Ex h => by rw [hx] at h; cases h)))
    (fun Ex h => by rw [hx] at h; cases h)

/-- A weakening keeps fresh borrows fresh (`EntryWeaker.fresh`). -/
theorem FreshOK.weaker {Γ Γ' : Ctx} (h : FreshOK Γ) (hw : Weaker Γ Γ') : FreshOK Γ' := by
  refine h.of_le (fun v E' hv hl hn hb hf => ?_) (fun r Er hr hm => ?_)
  · cases hE : Γ v with
    | none => exact absurd ((hw.1 v).1.mp hE) (by rw [hv]; simp)
    | some E =>
      have hew := (hw.1 v).2 E E' hE hv
      obtain ⟨hfE, hsub⟩ := hew.fresh hl hn hb hf
      obtain ⟨hlE, hp, _⟩ := hew.live hl
      have hbE : E.mode = .bor := by rw [← hew.mode]; exact hb
      exact ⟨E, rfl, hlE, by rw [← hew.ty]; exact hn, hbE, hfE, hsub, hp (by rw [hbE]; rfl)⟩
  · cases hE' : Γ' r with
    | none => exact absurd ((hw.1 r).1.mpr hE') (by rw [hr]; simp)
    | some Er' => exact ⟨Er', rfl, by rw [((hw.1 r).2 Er Er' hr hE').mode]; exact hm⟩

/-- Leaving a borrowed parameter's scope: what depended on it now depends on
    what it borrowed (`reroot`). A fresh borrow is rooted at the frame's own
    bindings, never at `p`: it stays as it was. -/
theorem FreshOK.exitRoot {Γ : Ctx} (h : FreshOK Γ) {p : Var} (D : List Dep)
    (hp : ∀ Ep, Γ p = some Ep → ¬ Ep.mode.frame) : FreshOK (A2.exitRoot p D Γ) := by
  intro v E' hv hl hn hb hf
  by_cases hvp : v = p
  · subst hvp; simp [A2.exitRoot] at hv
  simp only [A2.exitRoot, upd_ne _ _ hvp] at hv
  obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp hv
  obtain ⟨hne, hd⟩ := h v E hE hl hn hb hf
  have hnp : ∀ d ∈ E.path, d.root ≠ p := by
    intro d hdd hdp
    obtain ⟨_, Er, hEr, hm⟩ := hd d hdd
    rw [hdp] at hEr; exact hp Er hEr hm
  show (reroot p D E.path) ≠ [] ∧ ∀ d ∈ reroot p D E.path, _
  rw [reroot_self hnp]
  refine ⟨hne, fun d hdd => ?_⟩
  obtain ⟨hk, Er, hEr, hm⟩ := hd d hdd
  exact ⟨hk, rerootE p D Er, by simp [A2.exitRoot, upd_ne _ _ (hnp d hdd), hEr], hm⟩

theorem PushArg.freshOK {Γ Γ1 : Ctx} {F : List Var} {y : Var} {E : Entry} {t : Ty} {D : List Dep}
    (hp : PushArg Γ F y E t D Γ1) (hy : Γ y = some E) (h : FreshOK Γ) : FreshOK Γ1 ∧ KeepsFrame Γ Γ1 := by
  cases hp with
  | move => exact h.moved hy
  | int => exact ⟨h, KeepsFrame.refl _⟩
  | slice => exact ⟨h, KeepsFrame.refl _⟩

/-- Agora #909: a structural borrow of a `Vec` taken from a fresh source
    reaches only the frame's own blocks. -/
theorem derive_freshE {Γ : Ctx} (h : FreshOK Γ) {y : Var} {E : Entry} {t : Ty} {k : Kind}
    (hy : Γ y = some E) (ht : E.ty = .vec t) (hk : k = .self ∨ k = .inner) (hs : FreshSrc Γ y) :
    derive y E k ≠ [] ∧ ∀ d ∈ derive y E k, (d.kind = .self ∨ d.kind = .inner) ∧
      ∃ Er, Γ d.root = some Er ∧ Er.mode.frame := by
  obtain ⟨E', hE', hc⟩ := hs
  rw [hy] at hE'; cases hE'
  rcases hc with hfr | ⟨hb, hf, hl, hn⟩
  · have hroot : E.mode.isRoot = true := by rcases hfr with h' | ⟨b, h'⟩ <;> rw [h'] <;> rfl
    have hd : derive y E k = [⟨y, k⟩] := by
      unfold derive; rw [if_pos hroot, ht]; rcases hk with rfl | rfl <;> rfl
    rw [hd]
    refine ⟨by simp, fun d hd' => ?_⟩
    simp only [List.mem_singleton] at hd'; subst hd'
    exact ⟨hk, E, hy, hfr⟩
  · have hroot : E.mode.isRoot = false := by rw [hb]; rfl
    have hd : derive y E k = E.path.map (fun d => ⟨d.root, comp d.kind k⟩) := by
      unfold derive; rw [if_neg (by rw [hroot]; simp)]
    obtain ⟨hne, hpd⟩ := h y E hy hl hn hb hf
    rw [hd]
    refine ⟨by simpa using hne, fun d hd' => ?_⟩
    obtain ⟨d0, hd0, rfl⟩ := List.mem_map.mp hd'
    obtain ⟨hk0, Er, hEr, hm⟩ := hpd d0 hd0
    refine ⟨?_, Er, hEr, hm⟩
    rcases hk0 with h0 | h0 <;> rcases hk with rfl | rfl <;> simp [h0, comp]

theorem RhsT.freshOK {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1)
    (h : FreshOK Γ) : FreshOK Γ1 ∧ FreshE Γ1 E ∧ KeepsFrame Γ Γ1 := by
  cases hr with
  | copyBor hy _ _ =>
    have hE := h _ _ hy
    exact ⟨h, fun hl hn hb hf => hE hl hn hb hf, KeepsFrame.refl _⟩
  | copyUp hy _ _ hty _ =>
    have hE := h _ _ hy
    exact ⟨h, fun hl _ hb hf => hE hl (by rw [hty]; simp) hb hf, KeepsFrame.refl _⟩
  | moveOwn hy => obtain ⟨h1, h2⟩ := h.moved hy; exact ⟨h1, FreshE.of_fresh rfl, h2⟩
  | moveUp hy => obtain ⟨h1, h2⟩ := h.moved hy; exact ⟨h1, FreshE.of_fresh rfl, h2⟩
  | takel hy => obtain ⟨h1, h2⟩ := h.moved hy; exact ⟨h1, FreshE.of_fresh (compE_fresh _ _), h2⟩
  | taker hy => obtain ⟨h1, h2⟩ := h.moved hy; exact ⟨h1, FreshE.of_fresh (compE_fresh _ _), h2⟩
  | pop => exact ⟨h.kill _ _ _, FreshE.of_fresh (popE_fresh _ _ _), KeepsFrame.kill _ _ _ _⟩
  | remove => exact ⟨h.kill _ _ _, FreshE.of_fresh (popE_fresh _ _ _), KeepsFrame.kill _ _ _ _⟩
  | pair hy _ hp1 hz _ hp2 _ =>
    obtain ⟨h1, k1⟩ := hp1.freshOK hy h
    obtain ⟨h2, k2⟩ := hp2.freshOK hz h1
    exact ⟨h2, FreshE.of_fresh rfl, k1.trans k2⟩
  | inl hy _ hp _ => obtain ⟨h1, k1⟩ := hp.freshOK hy h; exact ⟨h1, FreshE.of_fresh rfl, k1⟩
  | inr hy _ hp _ => obtain ⟨h1, k1⟩ := hp.freshOK hy h; exact ⟨h1, FreshE.of_fresh rfl, k1⟩
  | pack hy _ _ hp _ _ => obtain ⟨h1, k1⟩ := hp.freshOK hy h; exact ⟨h1, FreshE.of_fresh rfl, k1⟩
  | arcNew hy _ _ _ _ _ _ hp => obtain ⟨h1, k1⟩ := hp.freshOK hy h; exact ⟨h1, FreshE.of_fresh rfl, k1⟩
  | lockNew hy _ _ _ _ _ hp => obtain ⟨h1, k1⟩ := hp.freshOK hy h; exact ⟨h1, FreshE.of_fresh rfl, k1⟩
  | chanSend _ _ _ hy _ _ hp => obtain ⟨h1, k1⟩ := hp.freshOK hy h; exact ⟨h1, FreshE.of_fresh rfl, k1⟩
  | cellNew hy _ _ _ _ _ hp => obtain ⟨h1, k1⟩ := hp.freshOK hy h; exact ⟨h1, FreshE.of_fresh rfl, k1⟩
  | lockRestore _ _ _ hy _ _ hp => obtain ⟨h1, k1⟩ := hp.freshOK hy h; exact ⟨h1, FreshE.of_fresh rfl, k1⟩
  | @borrow y E t f hy hl ht hf =>
    exact ⟨h, fun _ _ _ hfr => derive_freshE h hy ht (Or.inl rfl) (hf hfr), KeepsFrame.refl _⟩
  | @«at» y i E t f hy hl ht _ hf =>
    refine ⟨h, fun _ hn _ hfr => ?_, KeepsFrame.refl _⟩
    obtain ⟨hs, hns⟩ := hf hfr
    cases t with
    | int => exact absurd rfl hn
    | slice s => exact absurd rfl (hns s)
    | _ => exact derive_freshE h hy ht (Or.inr rfl) hs
  | @take y E t hy =>
    have hk : ∀ Ex, A2.kill .replace false y Γ y = some Ex → Ex.mode = E.mode := by
      intro Ex hEx; simp [A2.kill, hy] at hEx; rw [← hEx]; unfold killE; split <;> rfl
    refine ⟨(h.kill _ _ _).setE_same (Or.inl rfl) (fun Ex hEx => hk Ex hEx), FreshE.of_fresh rfl, ?_⟩
    exact (KeepsFrame.kill Γ _ _ _).trans (KeepsFrame.setE (fun Ex hEx hm => by
      rw [hk Ex hEx] at hm; exact hm))
  | _ => first
    | exact ⟨h, FreshE.of_fresh rfl, KeepsFrame.refl _⟩
    | (refine ⟨h, FreshE.of_fresh ?_, KeepsFrame.refl _⟩; simp; done)
    | fail "OPEN"

theorem KeepsFrame.killNames {Γ0 Γ : Ctx} (hk : KeepsFrame Γ0 Γ) :
    ∀ ds, KeepsFrame Γ0 (A2.killNames ds Γ)
  | [] => hk
  | d :: ds => (hk.killNames ds).trans (KeepsFrame.kill _ _ _ _)

theorem FreshLe.killNames {Γ0 Γ : Ctx} (hk : FreshLe Γ0 Γ) :
    ∀ ds, FreshLe Γ0 (A2.killNames ds Γ)
  | [] => hk
  | d :: ds => (hk.killNames ds).trans (FreshLe.kill _ _ _ _)

theorem callPostAux_fresh {Γ0 : Ctx} {fn : Fn} {args : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      FreshLe Γ0 Γ → KeepsFrame Γ0 Γ →
      FreshLe Γ0 (callPostAux Γ0 fn args ps as i Γ) ∧ KeepsFrame Γ0 (callPostAux Γ0 fn args ps as i Γ)
  | (.sink, _) :: ps, a :: as, i, Γ, hl, hk => by
    apply callPostAux_fresh ps as (i + 1)
    · exact (hl.trans (FreshLe.kill _ _ _ _)).setE (fun h => by simp at h)
    · exact (hk.trans (KeepsFrame.kill _ _ _ _)).of_src (fun Ex hEx hm => by simp [argE, hEx, hm])
  | (.inout b, t) :: ps, a :: as, i, Γ, hl, hk => by
    apply callPostAux_fresh ps as (i + 1)
    · refine (hl.trans (FreshLe.kill _ _ _ _)).setE (fun hl' hn hb hf => ?_)
      cases h0 : Γ0 a with
      | none => simp [argE, h0, intE] at hn
      | some E0 =>
        simp only [argE, h0, Option.getD_some] at hl' hn hb hf ⊢
        exact ⟨E0, rfl, hl', hn, hb, hf, List.Subset.refl _, List.Subset.refl _⟩
    · exact (hk.trans (KeepsFrame.kill _ _ _ _)).of_src (fun Ex hEx hm => by simp [argE, hEx, hm])
  | (.inp, _) :: ps, _ :: as, i, Γ, hl, hk => callPostAux_fresh ps as (i + 1) Γ hl hk
  | [], _, _, _, hl, hk => ⟨hl, hk⟩
  | (.sink, _) :: _, [], _, _, hl, hk => ⟨hl, hk⟩
  | (.inout _, _) :: _, [], _, _, hl, hk => ⟨hl, hk⟩
  | (.inp, _) :: _, [], _, _, hl, hk => ⟨hl, hk⟩

theorem callPost_fresh {Γ : Ctx} (h : FreshOK Γ) (fn : Fn) (args : List Var) :
    FreshOK (callPost Γ fn args) ∧ KeepsFrame Γ (callPost Γ fn args) := by
  obtain ⟨hl, hk⟩ := callPostAux_fresh (Γ0 := Γ) (fn := fn) (args := args) fn.params args 0 Γ
    (FreshLe.refl Γ) (KeepsFrame.refl Γ)
  exact ⟨h.of_le (hl.killNames _) (hk.killNames _), hk.killNames _⟩

theorem CallT.freshOK {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    (hc : CallT P Γ F f args E Γ1) (h : FreshOK Γ) : FreshOK Γ1 ∧ FreshE Γ1 E ∧ KeepsFrame Γ Γ1 := by
  obtain ⟨fn, _, _, _, _, _, rfl, rfl, _⟩ := hc
  obtain ⟨h1, k1⟩ := callPost_fresh h fn args
  exact ⟨h1, FreshE.of_fresh rfl, k1⟩

theorem KeepsFrame.killHv {Γ0 Γ : Ctx} (hk : KeepsFrame Γ0 Γ) : ∀ ks, KeepsFrame Γ0 (killHv ks Γ)
  | [] => hk
  | (_, _, _) :: ks => (hk.killHv ks).trans (KeepsFrame.kill _ _ _ _)

theorem FreshLe.killHv {Γ0 Γ : Ctx} (hk : FreshLe Γ0 Γ) : ∀ ks, FreshLe Γ0 (killHv ks Γ)
  | [] => hk
  | (_, _, _) :: ks => (hk.killHv ks).trans (FreshLe.kill _ _ _ _)

theorem KeepsFrame.holdOn (Γ : Ctx) (rs : List Var) (D : List Dep) : KeepsFrame Γ (A2.holdOn rs D Γ) :=
  fun r Er h hm => ⟨if r ∈ rs then Er.hold D else Er, by simp [A2.holdOn, h],
    by split <;> simpa using hm⟩

theorem FreshLe.holdOn (Γ : Ctx) (rs : List Var) (D : List Dep) : FreshLe Γ (A2.holdOn rs D Γ) := by
  intro v E' h hl hn hb hf
  simp only [A2.holdOn] at h
  obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp h
  have hk : (if v ∈ rs then E.hold D else E).ty = E.ty ∧ (if v ∈ rs then E.hold D else E).mode = E.mode ∧
      (if v ∈ rs then E.hold D else E).fresh = E.fresh ∧ (if v ∈ rs then E.hold D else E).path = E.path ∧
      (if v ∈ rs then E.hold D else E).live = E.live := by
    split <;> simp [Entry.hold]
  rw [hk.1] at hn; rw [hk.2.1] at hb; rw [hk.2.2.1] at hf; rw [hk.2.2.2.2] at hl; rw [hk.2.2.2.1]
  exact ⟨E, hE, hl, hn, hb, hf, List.Subset.refl _, List.Subset.refl _⟩

theorem EditArg.freshOK {Γ Γ1 : Ctx} {F : List Var} {op : Edit} {t : Ty} {D : List Dep}
    (he : EditArg Γ F op t D Γ1) (h : FreshOK Γ) : FreshOK Γ1 ∧ KeepsFrame Γ Γ1 := by
  cases he with
  | push hy _ _ hp => exact hp.freshOK hy h
  | trunc => exact ⟨h, KeepsFrame.refl _⟩
  | set _ hy _ _ hp => exact hp.freshOK hy h

/-- An edit's result: `x` keeps an entry with its path, its context's roots
    their modes. -/
theorem FreshOK.reset {Γ1 Γ2 : Ctx} (h : FreshOK Γ1) (hl : FreshLe Γ1 Γ2) (hk : KeepsFrame Γ1 Γ2)
    {x : Var} {Ex1 E : Entry} (hx : Γ1 x = some Ex1) (hm : E.mode = Ex1.mode) (hp : E.path = Ex1.path)
    (hlv : E.live = Ex1.live) (hty : E.ty = Ex1.ty) (hf : E.fresh = Ex1.fresh) :
    FreshOK (A2.setE Γ2 x E) := by
  refine h.of_le (hl.setE (fun hl' hn hb hf' => ?_)) (hk.of_src (fun Ex hEx hm' => ?_))
  · rw [hlv] at hl'; rw [hty] at hn; rw [hm] at hb; rw [hf] at hf'; rw [hp]
    exact ⟨Ex1, hx, hl', hn, hb, hf', List.Subset.refl _, List.Subset.refl _⟩
  · rw [hx] at hEx; cases hEx; rw [hm]; exact hm'



/-- An owner's entry is no borrow, fresh or not. -/
theorem FreshE.of_ownSlot {Γ : Ctx} {E : Entry} (h : E.mode.ownSlot = true) : FreshE Γ E :=
  fun _ _ hb _ => by rw [hb] at h; cases h

/-- Closes `FreshE Γ E` for an entry that is not fresh or is an owner's. -/
syntax "fresh_e" : tactic
macro_rules
  | `(tactic| fresh_e) => `(tactic| first
      | exact FreshE.of_fresh rfl
      | exact FreshE.of_fresh (by simp)
      | exact FreshE.of_ownSlot rfl
      | exact FreshE.of_ownSlot (by simp)
      | exact FreshE.of_live rfl)
end A2
