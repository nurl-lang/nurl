import A2.Wf

/-! A2 — the rules keep what contexts hold by name valid (`NameWF`): a
binding a live entry holds by name is still bound, with the type its closure
expects, owns its slot and allows the change.  The source rules are what a
callee's body is checked with; `Rename` places that check at a call. -/

namespace A2

/-- Every binding of `Γ0` is still bound in `Γ`, with its type and mode. -/
def Keeps (Γ0 Γ : Ctx) : Prop :=
  ∀ x E0, Γ0 x = some E0 → ∃ E, Γ x = some E ∧ E.ty = E0.ty ∧ E.mode = E0.mode

theorem Keeps.refl (Γ : Ctx) : Keeps Γ Γ := fun _ E h => ⟨E, h, rfl, rfl⟩

theorem Keeps.trans {Γ1 Γ2 Γ3 : Ctx} (h1 : Keeps Γ1 Γ2) (h2 : Keeps Γ2 Γ3) : Keeps Γ1 Γ3 := by
  intro x E1 hx
  obtain ⟨E2, hx2, ht2, hm2⟩ := h1 x E1 hx
  obtain ⟨E3, hx3, ht3, hm3⟩ := h2 x E2 hx2
  exact ⟨E3, hx3, ht3.trans ht2, hm3.trans hm2⟩

theorem Keeps.kill {Γ0 Γ : Ctx} (h : Keeps Γ0 Γ) (e : Eff) (hv : Bool) (x : Var) :
    Keeps Γ0 (kill e hv x Γ) := by
  intro y E0 hy
  obtain ⟨E, hE, ht, hm⟩ := h y E0 hy
  exact ⟨killE e hv x E, by simp [A2.kill, hE], by rw [killE_ty, ht], by rw [killE_mode, hm]⟩

theorem Keeps.setE {Γ0 Γ : Ctx} (h : Keeps Γ0 Γ) {x : Var} {E : Entry}
    (hx : ∀ E0, Γ0 x = some E0 → E.ty = E0.ty ∧ E.mode = E0.mode) : Keeps Γ0 (setE Γ x E) := by
  intro y E0 hy
  by_cases hyx : y = x
  · subst hyx; exact ⟨E, by simp [A2.setE], (hx E0 hy).1, (hx E0 hy).2⟩
  · obtain ⟨E1, h1, ht, hm⟩ := h y E0 hy
    exact ⟨E1, by simp [A2.setE, upd_ne _ _ hyx, h1], ht, hm⟩

theorem Keeps.killNames {Γ0 Γ : Ctx} (h : Keeps Γ0 Γ) : ∀ ds, Keeps Γ0 (killNames ds Γ)
  | [] => h
  | _ :: ds => show Keeps Γ0 (A2.kill _ _ _ (A2.killNames ds Γ)) from (Keeps.killNames h ds).kill _ _ _

theorem DepsNamed.keeps {Γ0 Γ : Ctx} {D : List Dep} (h : DepsNamed Γ0 D) (hk : Keeps Γ0 Γ) :
    DepsNamed Γ D := by
  intro d hd b t hkd
  obtain ⟨Er, hEr, ht, ho, hc⟩ := h d hd b t hkd
  obtain ⟨E, hE, ht', hm'⟩ := hk _ _ hEr
  exact ⟨E, hE, by rw [ht', ht], by rw [hm']; exact ho, by rw [hm']; exact hc⟩

theorem NameOK.keeps {Γ0 Γ : Ctx} {E : Entry} (h : NameOK Γ0 E) (hk : Keeps Γ0 Γ) : NameOK Γ E :=
  DepsNamed.keeps h hk

/-- A binding takes an entry of its type and mode (or a fresh one is bound):
    what is held by name stays valid, if the new entry's is. -/
theorem NameWF.setE {Γ : Ctx} (h : NameWF Γ) {x : Var} {E : Entry}
    (hx : ∀ Ex, Γ x = some Ex → E.ty = Ex.ty ∧ E.mode = Ex.mode)
    (hE : E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → NameOK Γ E) : NameWF (A2.setE Γ x E) := by
  have hk : Keeps Γ (A2.setE Γ x E) := Keeps.setE (Keeps.refl Γ) hx
  intro v Ev hv hl hn
  by_cases hvx : v = x
  · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv
    exact (hE hl hn).keeps hk
  · simp only [A2.setE, upd_ne _ _ hvx] at hv
    exact (h v Ev hv hl hn).keeps hk

theorem NameWF.killNames {Γ : Ctx} (h : NameWF Γ) : ∀ ds, NameWF (killNames ds Γ)
  | [] => h
  | _ :: ds => show NameWF (A2.kill _ _ _ (A2.killNames ds Γ)) from (NameWF.killNames h ds).kill _ _ _

theorem DepsNamed.of_held {Γ : Ctx} {E : Entry} (h : NameOK Γ E) : DepsNamed Γ E.held := h.held

/-- What a value moved out of `y` holds by name, in the context after. -/
theorem moved_named {Γ : Ctx} (hn : NameWF Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) (hnint : E.ty ≠ .int) :
    DepsNamed (setE (kill .replace false y Γ) y { E with live := false }) E.held :=
  ((hn y E hy hl (Or.inl hnint)).held).keeps
    (((Keeps.refl Γ).kill _ _ _).setE fun E0 h0 => by rw [hy] at h0; cases h0; exact ⟨rfl, rfl⟩)

theorem NameWF.moved {Γ : Ctx} (hn : NameWF Γ) {y : Var} {E : Entry} (hy : Γ y = some E) :
    NameWF (A2.setE (A2.kill .replace false y Γ) y { E with live := false }) :=
  NameWF.setE (hn.kill .replace false y) (fun Ex h0 => by
      simp only [A2.kill, hy, Option.map_some, Option.some.injEq] at h0; subst h0
      exact ⟨by rw [killE_ty], by rw [killE_mode]⟩)
    (fun hl => by simp at hl)

theorem PushArg.names {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hp : PushArg Γ F y Ey t D Γ1) (hy : Γ y = some Ey) (hly : Ey.live = true) (hty : Ey.ty = t)
    (hn : NameWF Γ) : NameWF Γ1 ∧ DepsNamed Γ1 D ∧ Keeps Γ Γ1 := by
  cases hp with
  | move ho _ _ _ =>
    have hnint : Ey.ty ≠ .int := fun h => by rw [hty] at h; rw [h] at ho; cases ho
    exact ⟨hn.moved hy, moved_named hn hy hly hnint,
      ((Keeps.refl Γ).kill _ _ _).setE fun E0 h0 => by rw [hy] at h0; cases h0; exact ⟨rfl, rfl⟩⟩
  | int => exact ⟨hn, DepsNamed.nil _, Keeps.refl Γ⟩
  | slice _ =>
    have hN := hn y Ey hy hly (Or.inl (by rw [hty]; simp))
    exact ⟨hn, (derive_named hN rfl).append hN.held, Keeps.refl Γ⟩

theorem popE_named {Γ : Ctx} {y : Var} {E : Entry} (h : DepsNamed Γ E.held) (t : Ty) :
    NameOK Γ (popE y E t) := by
  cases t <;> first
    | (show DepsNamed Γ ([] ++ []); exact DepsNamed.nil _)
    | (show DepsNamed Γ (E.held ++ E.held); exact h.append h)
    | exact own_named h

theorem projE_named {Γ : Ctx} {y : Var} {E : Entry} (hN : NameOK Γ E) (t : Ty) :
    NameOK Γ (projE y E t) := by
  cases t <;> first
    | (show DepsNamed Γ ([] ++ []); exact DepsNamed.nil _)
    | (show DepsNamed Γ ((projDeps y E ++ E.held) ++ E.held)
       exact ((projDeps_named hN).append hN.held).append hN.held)

/-- A right-hand side keeps what contexts hold by name valid, and so is what
    it hands over. -/
theorem RhsT.names {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1)
    (hn : NameWF Γ) :
    NameWF Γ1 ∧ (E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → NameOK Γ1 E) ∧ Keeps Γ Γ1 := by
  have nonint : ∀ {E : Entry}, (E.ty ≠ .int ∨ E.mode = .rootb) → E.mode = .bor ∨ E.mode = .own →
      E.ty ≠ .int := fun h hm => by
    rcases h with h | h
    · exact h
    · rcases hm with hm | hm <;> rw [hm] at h <;> cases h
  cases hr with
  | expr _ => exact ⟨hn, fun _ _ => DepsNamed.nil _, Keeps.refl Γ⟩
  | new _ => exact ⟨hn, fun _ _ => DepsNamed.nil _, Keeps.refl Γ⟩
  | moveOwn hy hl _ _ _ =>
    refine ⟨hn.moved hy, fun _ h => own_named (moved_named hn hy hl (h.resolve_right (by intro e; cases e))),
      ((Keeps.refl Γ).kill _ _ _).setE fun E0 h0 => by rw [hy] at h0; cases h0; exact ⟨rfl, rfl⟩⟩
  | copyRoot hy hl hm =>
    have hN := hn _ _ hy hl (Or.inr hm)
    exact ⟨hn, fun _ _ => by
      show DepsNamed Γ (derive _ _ .self ++ _); exact (derive_named hN rfl).append hN.held,
      Keeps.refl Γ⟩
  | copyBor hy hl hm =>
    exact ⟨hn, fun _ h => hn _ _ hy hl (Or.inl (nonint h (Or.inl hm))), Keeps.refl Γ⟩
  | borrow hy hl ht =>
    have hN := hn _ _ hy hl (Or.inl (by rw [ht]; simp))
    exact ⟨hn, fun _ _ => by
      show DepsNamed Γ (derive _ _ .self ++ _); exact (derive_named hN rfl).append hN.held,
      Keeps.refl Γ⟩
  | «at» hy hl ht _ =>
    exact ⟨hn, fun _ _ => elemE_named (hn _ _ hy hl (Or.inl (by rw [ht]; simp))) _, Keeps.refl Γ⟩
  | view hy hl ht _ =>
    have hN := hn _ _ hy hl (Or.inl (by rw [ht]; simp))
    exact ⟨hn, fun _ _ => by
      show DepsNamed Γ (derive _ _ .view ++ _); exact (derive_named hN rfl).append hN.held,
      Keeps.refl Γ⟩
  | sat hy hl ht _ =>
    exact ⟨hn, fun _ _ => elemE_named (hn _ _ hy hl (Or.inl (by rw [ht]; simp))) _, Keeps.refl Γ⟩
  | @pop y E t hy hl ht _ _ =>
    have hN := hn _ _ hy hl (Or.inl (by rw [ht]; simp))
    have hk : Keeps Γ (kill .drop t.holdsView y Γ) := (Keeps.refl Γ).kill _ _ _
    refine ⟨hn.kill _ _ _, fun _ _ => ?_, hk⟩
    have hH : DepsNamed (kill .drop t.holdsView y Γ) E.held := hN.held.keeps hk
    exact popE_named hH t
  | @pair y z Ey Ez Γ1 Γ2 Dy Dz hy hly hpa1 hz hlz hpa2 _ =>
    obtain ⟨hn1, hD1, hk1⟩ := hpa1.names hy hly rfl hn
    obtain ⟨hn2, hD2, hk2⟩ := hpa2.names hz hlz rfl hn1
    exact ⟨hn2, fun _ _ => own_named ((hD1.keeps hk2).append hD2), hk1.trans hk2⟩
  | fst hy hl ht =>
    exact ⟨hn, fun _ _ => projE_named (hn _ _ hy hl (Or.inl (by rw [ht]; simp))) _, Keeps.refl Γ⟩
  | snd hy hl ht =>
    exact ⟨hn, fun _ _ => projE_named (hn _ _ hy hl (Or.inl (by rw [ht]; simp))) _, Keeps.refl Γ⟩
  | getl hy hl ht =>
    exact ⟨hn, fun _ _ => projE_named (hn _ _ hy hl (Or.inl (by rw [ht]; simp))) _, Keeps.refl Γ⟩
  | getr hy hl ht =>
    exact ⟨hn, fun _ _ => projE_named (hn _ _ hy hl (Or.inl (by rw [ht]; simp))) _, Keeps.refl Γ⟩
  | inl hy hly hpa _ =>
    obtain ⟨hn1, hD, hk⟩ := hpa.names hy hly rfl hn
    exact ⟨hn1, fun _ _ => own_named hD, hk⟩
  | inr hy hly hpa _ =>
    obtain ⟨hn1, hD, hk⟩ := hpa.names hy hly rfl hn
    exact ⟨hn1, fun _ _ => own_named hD, hk⟩
  | @takel y E a b hy hl _ hty _ _ =>
    have hH := moved_named hn hy hl (by rw [hty]; simp)
    refine ⟨hn.moved hy, fun _ _ => ?_,
      ((Keeps.refl Γ).kill _ _ _).setE fun E0 h0 => by rw [hy] at h0; cases h0; exact ⟨rfl, rfl⟩⟩
    cases a <;> first
      | exact fun _ h => by cases h
      | exact own_named hH
      | exact own_named (hH.sub (ownHeld_sub _ _ _))
      | (show DepsNamed _ (E.held ++ E.held); exact hH.append hH)
  | @taker y E a b hy hl _ hty _ _ =>
    have hH := moved_named hn hy hl (by rw [hty]; simp)
    refine ⟨hn.moved hy, fun _ _ => ?_,
      ((Keeps.refl Γ).kill _ _ _).setE fun E0 h0 => by rw [hy] at h0; cases h0; exact ⟨rfl, rfl⟩⟩
    cases b <;> first
      | exact fun _ h => by cases h
      | exact own_named hH
      | exact own_named (hH.sub (ownHeld_sub _ _ _))
      | (show DepsNamed _ (E.held ++ E.held); exact hH.append hH)
  | pack hy hly hte hpa hcaps =>
    obtain ⟨hn1, hD, hk⟩ := hpa.names hy hly hte hn
    exact ⟨hn1, fun _ _ => own_named (hD.append hcaps.named), hk⟩

/-! ### Calls -/

theorem allKinds_named (Γ : Ctx) (rs : List Var) : DepsNamed Γ (allKinds rs) := by
  intro d hd b t hk
  simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil, or_false] at hd
  obtain ⟨r, _, hd⟩ := hd
  rcases hd with rfl | rfl | rfl <;> cases hk

theorem DepsNamed.flatMap {Γ : Ctx} {α : Type} {l : List α} {f : α → List Dep}
    (h : ∀ a ∈ l, DepsNamed Γ (f a)) : DepsNamed Γ (l.flatMap f) := by
  intro d hd
  obtain ⟨a, ha, hd'⟩ := List.mem_flatMap.mp hd
  exact h a ha d hd'

theorem callPostAux_names {Γ0 : Ctx} {fn : Fn} {args : List Var}
    (hD : ∀ i, DepsNamed Γ0 (outHeld Γ0 fn args i)) (hH : DepsNamed Γ0 (heldOfArgs Γ0 args)) :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ a ∈ as, ∃ E0, Γ0 a = some E0 ∧
        (E0.live = true → (E0.ty ≠ .int ∨ E0.mode = .rootb) → NameOK Γ0 E0)) →
      NameWF Γ → Keeps Γ0 Γ →
      NameWF (callPostAux Γ0 fn args ps as i Γ) ∧ Keeps Γ0 (callPostAux Γ0 fn args ps as i Γ) := by
  intro ps
  induction ps with
  | nil => intro as i Γ _ hn hk; cases as <;> exact ⟨hn, hk⟩
  | cons p ps ih =>
    intro as i Γ has hn hk
    obtain ⟨pm, t⟩ := p
    cases as with
    | nil => cases pm <;> exact ⟨hn, hk⟩
    | cons a as =>
      obtain ⟨E0, h0, hN0⟩ := has a (by simp)
      have has' := fun a' (h' : a' ∈ as) => has a' (by simp [h'])
      have hargE : argE Γ0 a = E0 := by unfold argE; rw [h0]; rfl
      obtain ⟨E1, h1, ht1, hm1⟩ := hk a E0 h0
      have hx : ∀ {E : Entry}, E.ty = E0.ty → E.mode = E0.mode → ∀ e hv,
          ∀ Ex, A2.kill e hv a Γ a = some Ex → E.ty = Ex.ty ∧ E.mode = Ex.mode := by
        intro E ht hm e hv Ex hEx
        simp only [A2.kill, h1, Option.map_some, Option.some.injEq] at hEx; subst hEx
        exact ⟨by rw [killE_ty, ht1, ht], by rw [killE_mode, hm1, hm]⟩
      cases pm with
      | inp => exact ih as (i + 1) Γ has' hn hk
      | sink =>
        simp only [callPostAux]
        refine ih as (i + 1) _ has' (NameWF.setE (hn.kill _ _ _) (hx (by rw [hargE]) (by rw [hargE]) _ _)
          (fun hl => by simp at hl)) ((hk.kill _ _ _).setE fun E0' h0' => ?_)
        rw [h0] at h0'; cases h0'; exact ⟨by rw [hargE], by rw [hargE]⟩
      | inout b =>
        simp only [callPostAux]
        refine ih as (i + 1) _ has' (NameWF.setE (hn.kill _ _ _) (hx (by rw [hargE]) (by rw [hargE]) _ _)
          (fun hl hnn => ?_)) ((hk.kill _ _ _).setE fun E0' h0' => ?_)
        · have hN := hN0 (by rw [← hargE]; exact hl) (by rw [← hargE]; exact hnn)
          have hk' : Keeps Γ0 (A2.kill b t.elem.holdsView a Γ) := hk.kill _ _ _
          rw [hargE]
          intro d hd
          simp only [Entry.vdeps, List.mem_append] at hd
          rcases hd with hd | hd
          · exact (hN.keeps hk') d (List.mem_append_left _ hd)
          · split at hd
            · simp only [List.mem_append] at hd
              rcases hd with (hd | hd) | hd
              · exact (hN.keeps hk') d (List.mem_append_right _ hd)
              · exact ((hD i).keeps hk') d hd
              · exact (hH.keeps hk') d hd
            · exact (hN.keeps hk') d (List.mem_append_right _ hd)
        · rw [h0] at h0'; cases h0'; exact ⟨by rw [hargE], by rw [hargE]⟩

/-- A call keeps what contexts hold by name valid, and so is its result. -/
theorem CallT.names {P : Prog} (hP : ProgOK P) {Γ Γ1 : Ctx} {F : List Var} {f : Nat}
    {args : List Var} {E : Entry} (hc : CallT P Γ F f args E Γ1) (hn : NameWF Γ) :
    NameWF Γ1 ∧ (E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → NameOK Γ1 E) ∧ Keeps Γ Γ1 := by
  obtain ⟨fn, hf, hlen, hargs, _, rfl, rfl⟩ := hc
  have hfn : FnOK P fn := hP fn (List.mem_of_getElem? hf)
  obtain ⟨_, _, _, _, _, _, hlends, hrholds, houts, _⟩ := hfn
  have hargN : ∀ j < fn.params.length, (argE Γ (args.getD j 0)).ty ≠ .int →
      NameOK Γ (argE Γ (args.getD j 0)) := by
    intro j hj hni
    obtain ⟨Ea, hEa, hl, _⟩ := hargs j hj
    have hae : argE Γ (args.getD j 0) = Ea := by unfold argE; rw [hEa]; rfl
    rw [hae] at hni ⊢; exact hn _ Ea hEa hl (Or.inl hni)
  have hdeps : ∀ jk : Nat × Kind, jk.1 < fn.params.length → jk.2.isName = false →
      DepsNamed Γ (argDeps Γ args jk) := by
    intro jk hj hk
    unfold argDeps
    split
    · exact DepsNamed.nil _
    · rename_i hni; exact derive_named (hargN jk.1 hj hni) hk
  have hheld : DepsNamed Γ (heldOfArgs Γ args) := by
    unfold heldOfArgs
    refine (allKinds_named _ _).append (DepsNamed.flatMap fun a ha => ?_)
    obtain ⟨j, hj, rfl⟩ := mem_args ha
    split
    · exact DepsNamed.nil _
    · rename_i hni
      exact DepsNamed.sub (hargN j (hlen ▸ hj) hni) (fun d hd => (List.mem_filter.mp hd).1)
  have hout : ∀ i, DepsNamed Γ (outHeld Γ fn args i) := by
    intro i
    refine DepsNamed.flatMap fun o ho => ?_
    obtain ⟨⟨hj, _⟩, hk⟩ := houts o (List.mem_filter.mp ho).1
    exact hdeps _ hj hk
  have hpost := callPostAux_names (fn := fn) (args := args) hout hheld fn.params args 0 Γ
    (fun a ha => by
      obtain ⟨j, hj, rfl⟩ := mem_args ha
      obtain ⟨Ea, hEa, hl, _⟩ := hargs j (hlen ▸ hj)
      exact ⟨Ea, hEa, fun hl' hn' => hn _ Ea hEa hl' hn'⟩) hn (Keeps.refl Γ)
  have hk : Keeps Γ (callPost Γ fn args) := hpost.2.killNames _
  refine ⟨hpost.1.killNames _, fun _ _ => ?_, hk⟩
  have hl : DepsNamed Γ (fn.lends.flatMap (argDeps Γ args)) :=
    DepsNamed.flatMap fun jk hjk => by
      obtain ⟨⟨hj, _⟩, hk⟩ := hlends jk hjk; exact hdeps jk hj hk
  have hr : DepsNamed Γ (fn.rholds.flatMap (argDeps Γ args)) :=
    DepsNamed.flatMap fun jk hjk => by
      obtain ⟨⟨hj, _⟩, hk⟩ := hrholds jk hjk; exact hdeps jk hj hk
  refine NameOK.keeps (Γ0 := Γ) ?_ hk
  intro d hd
  unfold Entry.vdeps at hd
  rcases List.mem_append.mp hd with hd | hd
  · split at hd
    · cases hd
    · simp only [callRes] at hd
      rcases List.mem_append.mp hd with hd | hd
      · exact hl d hd
      · exact hheld d hd
  · simp only [callRes] at hd
    rcases List.mem_append.mp (ownHeld_sub _ _ _ hd) with hd | hd
    · exact hr d hd
    · exact hheld d hd

theorem recvRes_named {Γ : Ctx} {c : Var} {Ec E : Entry}
    (hE : E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → NameOK Γ E) :
    (recvRes c Ec E).live = true → ((recvRes c Ec E).ty ≠ .int ∨ (recvRes c Ec E).mode = .rootb) →
      NameOK Γ (recvRes c Ec E) := by
  intro hl hni
  have hE' := hE hl hni
  intro d hd
  unfold Entry.vdeps at hd
  rcases List.mem_append.mp hd with hd | hd
  · split at hd
    · cases hd
    · rename_i hos
      have hos' : E.mode.ownSlot = false := by simpa [recvRes] using hos
      simp only [recvRes] at hd
      rcases List.mem_append.mp hd with hd | hd
      · exact hE' d (by simp only [Entry.vdeps, hos']; exact List.mem_append_left _ hd)
      · exact allKinds_named _ _ d hd
  · simp only [recvRes] at hd
    rcases List.mem_append.mp (ownHeld_sub _ _ _ hd) with hd | hd
    · exact hE' d (by unfold Entry.vdeps; exact List.mem_append_right _ hd)
    · exact allKinds_named _ _ d hd

/-! ### Statements -/

/-- What `unpair` binds holds by name only what the pair did. -/
theorem NameWF.unpair {Γ : Ctx} (hn : NameWF Γ) {y x z : Var} {E : Entry} {a b : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (hty : E.ty = .prod a b) (hx : Γ x = none)
    (hz : Γ z = none) (hxz : x ≠ z) :
    NameWF (A2.setE (A2.setE (A2.setE (A2.kill .replace false y Γ) y { E with live := false }) x
      (compE E a)) z (compE E b)) := by
    have hn1 := hn.moved hy
    have hH := moved_named hn hy hl (by rw [hty]; simp)
    have hxy : x ≠ y := fun e => by rw [e, hy] at hx; cases hx
    have hzy : z ≠ y := fun e => by rw [e, hy] at hz; cases hz
    have hcomp : ∀ (Γ' : Ctx) (t : Ty), DepsNamed Γ' E.held → NameOK Γ' (compE E t) := by
      intro Γ' t h
      cases t <;> first
        | (show DepsNamed Γ' ([] ++ []); exact DepsNamed.nil _)
        | (show DepsNamed Γ' (E.held ++ E.held); exact h.append h)
        | exact own_named h
        | exact own_named (h.sub (ownHeld_sub _ _ _))
    have hx1 : A2.setE (A2.kill .replace false y Γ) y { E with live := false } x = none := by
      simp [A2.setE, upd_ne _ _ hxy, A2.kill, hx]
    have hn2 := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun _ _ => hcomp _ a hH)
    have hz2 : A2.setE (A2.setE (A2.kill .replace false y Γ) y { E with live := false }) x (compE E a) z
        = none := by
      simp [A2.setE, upd_ne _ _ (Ne.symm hxz), upd_ne _ _ hzy, A2.kill, hz]
    have hk2 : Keeps (A2.setE (A2.kill .replace false y Γ) y { E with live := false })
        (A2.setE (A2.setE (A2.kill .replace false y Γ) y { E with live := false }) x (compE E a)) :=
      (Keeps.refl _).setE fun E0 h => by rw [hx1] at h; cases h
    have hn3 := NameWF.setE hn2 (fun Ex h => by rw [hz2] at h; cases h)
      (fun _ _ => hcomp _ b (hH.keeps hk2))
    exact hn3


/-- Source code keeps what contexts hold by name valid. -/
theorem StmtT.names {P : Prog} (hP : ProgOK P) {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P Γ F s Δ) : s.src = true → NameWF Γ → NameWF Δ := by
  induction ht with
  | skip => exact fun _ h => h
  | seq _ _ _ iha ihb =>
    intro hs hn; simp only [Stmt.src, Bool.and_eq_true] at hs; exact ihb hs.2 (iha hs.1 hn)
  | sub hw _ ho ih =>
    intro hs hn
    rcases ho with rfl | ho
    · exact ih hs hw.names
    · exact ho.names
  | @letv Γ Γ1 Δ F x r k E hks hx _ hr _ _ ih =>
    intro _ hn
    obtain ⟨hn1, hE, _⟩ := hr.names hn
    have hx1 : Γ1 x = none := by
      have := (hr.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    exact (ih hks (NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) hE)).exitScope x
  | @letcall Γ Γ1 Δ F x f args k E hks hx _ hc _ _ ih =>
    intro _ hn
    obtain ⟨hn1, hE, _⟩ := hc.names hP hn
    have hx1 : Γ1 x = none := by
      have := (hc.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    exact (ih hks (NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) hE)).exitScope x
  | @letrec Γ Γ1 Δ F x f k E fn hks hx _ _ _ _ _ hc _ _ ih =>
    intro _ hn
    obtain ⟨hn1, hE, _⟩ := hc.names hP hn
    have hx1 : Γ1 x = none := by
      have := (hc.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    exact (ih hks (NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) hE)).exitScope x
  | @callc Γ Γ1 Δ F x c j zs k Ec E ms σ sig hks hx _ hc htc _ _ _ _ hcT _ _ ih =>
    intro _ hn
    obtain ⟨hn1, hE, hk⟩ := hcT.names hP hn
    have hx1 : Γ1 x = none := by
      have := (hcT.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    exact (ih hks (NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h)
      (recvRes_named hE))).exitScope x
  | @unpair Γ Δ F y x z k E a b hks hy hl _ hty _ hx hz hxz _ _ _ _ _ _ ih =>
    intro _ hn
    exact ((ih hks (hn.unpair hy hl hty hx hz hxz)).exitScope z).exitScope x
  | @assign Γ Γ1 F x r Ex E hx _ hmodes hr hty _ _ _ =>
    intro _ hn
    obtain ⟨hn1, hE, hk⟩ := hr.names hn
    obtain ⟨Ex1, hx1, ht1, hm1⟩ := hk x Ex hx
    have hos : Ex.mode.ownSlot = E.mode.ownSlot := by
      rcases hmodes with ⟨h1, h2⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rw [h1, h2] <;> rfl
    refine NameWF.setE (hn1.kill _ _ _) (fun Ex' h => ?_) (fun hl hni => ?_)
    · simp only [A2.kill, hx1, Option.map_some, Option.some.injEq] at h; subst h
      exact ⟨by rw [killE_ty, ht1, hty], by rw [killE_mode, hm1]⟩
    · have hti : E.ty ≠ .int := by
        rcases hni with h | h
        · exact h
        · exfalso; simp only at h
          rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩ <;> rw [h1] at h <;> cases h
      have hN := hE hl (Or.inl hti)
      refine NameOK.keeps (Γ0 := Γ1) ?_ ((Keeps.refl _).kill _ _ _)
      show DepsNamed Γ1 ({ E with mode := Ex.mode } : Entry).vdeps
      rw [vdeps_mode hos]; exact hN
  | ite _ _ _ _ _ iha _ => intro hs hn; simp only [Stmt.src, Bool.and_eq_true] at hs; exact iha hs.1 hn
  | «while» => exact fun _ h => h
  | @push Γ Γ1 F x y Ex Ey Ex1 t D hx hlx htx _ _ hy hly htyy _ hpa _ hx1 hl1 =>
    intro _ hn
    obtain ⟨hn1, hD, _⟩ := hpa.names hy hly htyy hn
    refine NameWF.setE (hn1.kill _ _ _) (fun Ex' h => ?_) (fun hl hni => ?_)
    · simp only [A2.kill, hx1, Option.map_some, Option.some.injEq] at h; subst h
      exact ⟨by rw [killE_ty], by rw [killE_mode]⟩
    · have hN := hn1 x Ex1 hx1 hl1 (by
        rcases hni with h | h
        · exact Or.inl h
        · exact Or.inr h)
      refine NameOK.keeps (Γ0 := Γ1) ?_ ((Keeps.refl _).kill _ _ _)
      intro d hd
      simp only [Entry.vdeps, List.mem_append] at hd
      rcases hd with hd | hd | hd
      · exact hN d (List.mem_append_left _ hd)
      · exact hN d (List.mem_append_right _ hd)
      · exact hD d hd
  | @free Γ F x E t hx _ _ _ _ _ =>
    intro _ hn
    exact NameWF.setE (hn.kill _ _ _) (fun Ex h => by
        simp only [A2.kill, hx, Option.map_some, Option.some.injEq] at h; subst h
        exact ⟨by rw [killE_ty], by rw [killE_mode]⟩) (fun hl => by simp at hl)
  | panic _ hnΔ _ _ => exact fun _ _ => hnΔ
  | catchR => intro hs; simp [Stmt.src] at hs
  | scope => intro hs; simp [Stmt.src] at hs
  | rbind => intro hs; simp [Stmt.src] at hs
  | frozen => intro hs; simp [Stmt.src] at hs

end A2
