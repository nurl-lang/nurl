import A2.Wf

/-! A2 — the rules keep what contexts hold by name valid (`NameWF`): a
binding a live entry holds by name is still bound, with the type its closure
expects, owns its slot and allows the change.  The source rules are what a
callee's body is checked with; `Rename` places that check at a call. -/

namespace A2

/-- A binding something may hold by name: live, owning its slot, of a type
    that holds no views, holding nothing. -/
def Entry.named (E : Entry) : Prop :=
  E.live = true ∧ E.held = [] ∧ E.mode.ownSlot = true ∧ E.ty.holdsView = false

theorem Entry.named.vdeps {E : Entry} (h : E.named) : E.vdeps = [] := root_vdeps h.2.2.1 h.2.1

/-- Every binding of `Γ0` is still bound in `Γ`, with its type and mode, and
    one that may be held by name still may be, but for those of `X` (moved
    or replaced: what held them by name has ended). -/
def Keeps (Γ0 Γ : Ctx) (X : List Var) : Prop :=
  ∀ x E0, Γ0 x = some E0 → ∃ E, Γ x = some E ∧ E.ty = E0.ty ∧ E.mode = E0.mode ∧
    (x ∉ X → E0.named → E.named)

theorem Keeps.refl (Γ : Ctx) (X : List Var) : Keeps Γ Γ X := fun _ E h => ⟨E, h, rfl, rfl, fun _ h => h⟩

theorem Keeps.mono {Γ0 Γ : Ctx} {X Y : List Var} (h : Keeps Γ0 Γ X) (hXY : X ⊆ Y) : Keeps Γ0 Γ Y := by
  intro x E0 hx
  obtain ⟨E, hE, ht, hm, hn⟩ := h x E0 hx
  exact ⟨E, hE, ht, hm, fun hxY => hn (fun hX => hxY (hXY hX))⟩

theorem Keeps.trans {Γ1 Γ2 Γ3 : Ctx} {X Y : List Var} (h1 : Keeps Γ1 Γ2 X) (h2 : Keeps Γ2 Γ3 Y) :
    Keeps Γ1 Γ3 (X ++ Y) := by
  intro x E1 hx
  obtain ⟨E2, hx2, ht2, hm2, hn2⟩ := h1 x E1 hx
  obtain ⟨E3, hx3, ht3, hm3, hn3⟩ := h2 x E2 hx2
  exact ⟨E3, hx3, ht3.trans ht2, hm3.trans hm2, fun hX hn =>
    hn3 (fun h => hX (List.mem_append_right _ h)) (hn2 (fun h => hX (List.mem_append_left _ h)) hn)⟩

theorem killE_named {E : Entry} (h : E.named) (e : Eff) (hv : Bool) (x : Var) : killE e hv x E = E :=
  killE_nil h.vdeps e hv x

theorem Keeps.kill {Γ0 Γ : Ctx} {X : List Var} (h : Keeps Γ0 Γ X) (e : Eff) (hv : Bool) (x : Var) :
    Keeps Γ0 (kill e hv x Γ) X := by
  intro y E0 hy
  obtain ⟨E, hE, ht, hm, hn⟩ := h y E0 hy
  refine ⟨killE e hv x E, by simp [A2.kill, hE], by rw [killE_ty, ht], by rw [killE_mode, hm],
    fun hX h0 => ?_⟩
  have := hn hX h0
  rw [killE_named this]; exact this

theorem Keeps.setE {Γ0 Γ : Ctx} {X : List Var} (h : Keeps Γ0 Γ X) {x : Var} {E : Entry}
    (hx : ∀ E0, Γ0 x = some E0 → E.ty = E0.ty ∧ E.mode = E0.mode ∧ (x ∉ X → E0.named → E.named)) :
    Keeps Γ0 (setE Γ x E) X := by
  intro y E0 hy
  by_cases hyx : y = x
  · subst hyx; exact ⟨E, by simp [A2.setE], (hx E0 hy).1, (hx E0 hy).2.1, (hx E0 hy).2.2⟩
  · obtain ⟨E1, h1, ht, hm, hn⟩ := h y E0 hy
    exact ⟨E1, by simp [A2.setE, upd_ne _ _ hyx, h1], ht, hm, hn⟩

/-- A binding moved or replaced: exempt. -/
theorem Keeps.setX {Γ0 Γ : Ctx} {X : List Var} (h : Keeps Γ0 Γ X) {x : Var} {E : Entry}
    (hx : ∀ E0, Γ0 x = some E0 → E.ty = E0.ty ∧ E.mode = E0.mode) :
    Keeps Γ0 (A2.setE Γ x E) (x :: X) :=
  (h.mono (fun _ h => List.mem_cons_of_mem _ h)).setE fun E0 h0 =>
    ⟨(hx E0 h0).1, (hx E0 h0).2, fun hX => absurd List.mem_cons_self hX⟩

theorem Keeps.killNames {Γ0 Γ : Ctx} {X : List Var} (h : Keeps Γ0 Γ X) : ∀ ds, Keeps Γ0 (killNames ds Γ) X
  | [] => h
  | _ :: ds => show Keeps Γ0 (A2.kill _ _ _ (A2.killNames ds Γ)) X from (Keeps.killNames h ds).kill _ _ _

/-- What a binding of a type that holds no views is held by name as, it is. -/
theorem DepsNamed.root {Γ : Ctx} {D : List Dep} (h : DepsNamed Γ D) {d : Dep} (hd : d ∈ D)
    (hk : d.kind.isName = true) : ∃ Er, Γ d.root = some Er ∧ Er.named := by
  obtain ⟨b, t, hkd⟩ : ∃ b t, d.kind = .name b t := by
    cases hdk : d.kind <;> simp_all [Kind.isName]
  obtain ⟨Er, hEr, hl, hh, ht, ho, _, hv⟩ := h d hd b t hkd
  exact ⟨Er, hEr, hl, hh, ho, by rw [ht]; exact hv⟩

theorem DepsNamed.keeps {Γ0 Γ : Ctx} {D : List Dep} {X : List Var} (h : DepsNamed Γ0 D) (hk : Keeps Γ0 Γ X)
    (hX : ∀ d ∈ D, d.kind.isName = true → d.root ∉ X) : DepsNamed Γ D := by
  intro d hd b t hkd
  have hkn : d.kind.isName = true := by rw [hkd]; rfl
  obtain ⟨Er, hEr, hl, hh, ht, ho, hc, hv⟩ := h d hd b t hkd
  obtain ⟨E, hE, ht', hm', hn⟩ := hk _ _ hEr
  obtain ⟨hl', hh', _, _⟩ := hn (hX d hd hkn) ⟨hl, hh, ho, by rw [ht]; exact hv⟩
  exact ⟨E, hE, hl', hh', by rw [ht', ht], by rw [hm']; exact ho, by rw [hm']; exact hc, hv⟩

theorem NameOK.keeps {Γ0 Γ : Ctx} {E : Entry} {X : List Var} (h : NameOK Γ0 E) (hk : Keeps Γ0 Γ X)
    (hX : ∀ d ∈ E.vdeps, d.kind.isName = true → d.root ∉ X) : NameOK Γ E :=
  DepsNamed.keeps h hk hX

/-- With nothing exempt. -/
theorem DepsNamed.keeps' {Γ0 Γ : Ctx} {D : List Dep} (h : DepsNamed Γ0 D) (hk : Keeps Γ0 Γ []) :
    DepsNamed Γ D := h.keeps hk (fun _ _ _ h => by cases h)

/-- `x` takes the entry `E` of its type and mode (or a fresh one is bound):
    what is held by name stays valid, if the new entry's is, and `x`, if it
    may be held by name, still may be, or nothing holds it by name. -/
theorem NameWF.setE {Γ : Ctx} (h : NameWF Γ) {x : Var} {E : Entry}
    (hx : ∀ Ex, Γ x = some Ex → E.ty = Ex.ty ∧ E.mode = Ex.mode)
    (hkx : ∀ Ex, Γ x = some Ex → Ex.named → E.named ∨
      ((∀ v Ev, v ≠ x → Γ v = some Ev → Ev.live = true → (Ev.ty ≠ .int ∨ Ev.mode = .rootb) →
        ∀ d ∈ Ev.vdeps, d.kind.isName = true → d.root ≠ x) ∧
       (E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → ∀ d ∈ E.vdeps, d.kind.isName = true → d.root ≠ x)))
    (hE : E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → NameOK Γ E) : NameWF (A2.setE Γ x E) := by
  -- whether `x` stays held by name
  by_cases hstay : ∀ Ex, Γ x = some Ex → Ex.named → E.named
  · have hk : Keeps Γ (A2.setE Γ x E) [] := (Keeps.refl Γ []).setE fun E0 h0 =>
      ⟨(hx E0 h0).1, (hx E0 h0).2, fun _ => hstay E0 h0⟩
    intro v Ev hv hl hn
    by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv
      exact (hE hl hn).keeps hk (fun _ _ _ h => by cases h)
    · simp only [A2.setE, upd_ne _ _ hvx] at hv
      exact (h v Ev hv hl hn).keeps hk (fun _ _ _ h => by cases h)
  · obtain ⟨Ex, hEx, hxn⟩ : ∃ Ex, Γ x = some Ex ∧ Ex.named ∧ ¬ E.named :=
      Classical.byContradiction fun hc => hstay fun Ex h1 h2 =>
        Classical.byContradiction fun h3 => hc ⟨Ex, h1, h2, h3⟩
    obtain ⟨hother, hself⟩ := (hkx Ex hEx hxn.1).resolve_left hxn.2
    have hk : Keeps Γ (A2.setE Γ x E) [x] := (Keeps.refl Γ []).setX fun E0 h0 => hx E0 h0
    intro v Ev hv hl hn
    by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv
      exact (hE hl hn).keeps hk (fun d hd hk' h => by
        simp only [List.mem_singleton] at h; exact hself hl hn d hd hk' h)
    · simp only [A2.setE, upd_ne _ _ hvx] at hv
      exact (h v Ev hv hl hn).keeps hk (fun d hd hk' h => by
        simp only [List.mem_singleton] at h; exact hother v Ev hvx hv hl hn d hd hk' h)

theorem NameWF.killNames {Γ : Ctx} (h : NameWF Γ) : ∀ ds, NameWF (killNames ds Γ)
  | [] => h
  | _ :: ds => show NameWF (A2.kill _ _ _ (A2.killNames ds Γ)) from (NameWF.killNames h ds).kill _ _ _

theorem DepsNamed.of_held {Γ : Ctx} {E : Entry} (h : NameOK Γ E) : DepsNamed Γ E.held := h.held

/-- What a value moved out of `y` holds by name, in the context after. -/
theorem moved_named {Γ : Ctx} (hn : NameWF Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) (hnint : E.ty ≠ .int) :
    DepsNamed (setE (kill .replace false y Γ) y { E with live := false, dtor := false }) E.held := by
  have hN := (hn y E hy hl (Or.inl hnint)).held
  refine hN.keeps (((Keeps.refl Γ []).kill _ _ _).setX fun E0 h0 => by rw [hy] at h0; cases h0; exact ⟨rfl, rfl⟩)
    fun d hd hk h => ?_
  -- what holds nothing is held by nothing it holds
  simp only [List.mem_singleton] at h
  obtain ⟨Er, hEr, hn'⟩ := hN.root hd hk
  rw [h, hy] at hEr; cases hEr
  rw [hn'.2.1] at hd; cases hd

/-- After `.replace` of `y`, nothing live depends on `y`. -/
theorem kill_ends {Γ : Ctx} {y v : Var} {Ev : Entry} (h : A2.kill .replace false y Γ v = some Ev)
    (hl : Ev.live = true) (hn : Ev.ty ≠ .int ∨ Ev.mode = .rootb) : ∀ d ∈ Ev.vdeps, d.root ≠ y := by
  simp only [A2.kill] at h
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp h
  rw [killE_ty, killE_mode] at hn
  obtain ⟨_, hk⟩ := killE_live_dep hl hn
  intro d hd hdy
  rw [killE_vdeps] at hd
  have := hk d hd hdy
  cases hdk : d.kind <;> rw [hdk] at this <;> simp [Eff.kills] at this

/-- `y`, replaced: what held it by name has ended. -/
theorem NameWF.replaced {Γ : Ctx} (hn : NameWF Γ) {y : Var} {E : Entry}
    (hx : ∀ Ex, Γ y = some Ex → E.ty = Ex.ty ∧ E.mode = Ex.mode)
    (hself : E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
      ∀ d ∈ E.vdeps, d.kind.isName = true → d.root ≠ y)
    (hE : E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → NameOK (A2.kill .replace false y Γ) E) :
    NameWF (A2.setE (A2.kill .replace false y Γ) y E) :=
  NameWF.setE (hn.kill .replace false y) (fun Ex h0 => by
      cases hy : Γ y with
      | none => simp [A2.kill, hy] at h0
      | some E0 =>
        simp only [A2.kill, hy, Option.map_some, Option.some.injEq] at h0; subst h0
        rw [killE_ty, killE_mode]; exact hx E0 hy)
    (fun _ _ _ => Or.inr ⟨fun _ _ _ hv hl hn' d hd _ => kill_ends hv hl hn' d hd, hself⟩) hE

theorem NameWF.moved {Γ : Ctx} (hn : NameWF Γ) {y : Var} {E : Entry} (hy : Γ y = some E) :
    NameWF (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) :=
  hn.replaced (fun Ex h => by rw [hy] at h; cases h; exact ⟨rfl, rfl⟩) (fun hl => by simp at hl)
    (fun hl => by simp at hl)

theorem Keeps.moved (Γ : Ctx) {y : Var} {E : Entry} (hy : Γ y = some E) :
    Keeps Γ (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) [y] :=
  ((Keeps.refl Γ []).kill _ _ _).setX fun E0 h0 => by rw [hy] at h0; cases h0; exact ⟨rfl, rfl⟩

theorem PushArg.names {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hp : PushArg Γ F y Ey t D Γ1) (hy : Γ y = some Ey) (hly : Ey.live = true) (hty : Ey.ty = t)
    (hn : NameWF Γ) : NameWF Γ1 ∧ DepsNamed Γ1 D ∧ Keeps Γ Γ1 [y] := by
  cases hp with
  | move ho _ _ _ =>
    have hnint : Ey.ty ≠ .int := fun h => by rw [hty] at h; rw [h] at ho; cases ho
    exact ⟨hn.moved hy, moved_named hn hy hly hnint, Keeps.moved Γ hy⟩
  | int => exact ⟨hn, DepsNamed.nil _, Keeps.refl Γ _⟩
  | slice _ =>
    have hN := hn y Ey hy hly (Or.inl (by rw [hty]; simp))
    exact ⟨hn, (derive_named hN rfl).append hN.held, Keeps.refl Γ _⟩

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
    NameWF Γ1 ∧ (E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → NameOK Γ1 E) ∧ ∃ X, Keeps Γ Γ1 X := by
  have nonint : ∀ {E : Entry}, (E.ty ≠ .int ∨ E.mode = .rootb) → E.mode = .bor ∨ E.mode = .own →
      E.ty ≠ .int := fun h hm => by
    rcases h with h | h
    · exact h
    · rcases hm with hm | hm <;> rw [hm] at h <;> cases h
  cases hr with
  | expr _ => exact ⟨hn, fun _ _ => DepsNamed.nil _, ⟨[], Keeps.refl Γ []⟩⟩
  | new _ => exact ⟨hn, fun _ _ => DepsNamed.nil _, ⟨[], Keeps.refl Γ []⟩⟩
  | moveOwn hy hl _ _ _ =>
    refine ⟨hn.moved hy, fun _ h => own_named (moved_named hn hy hl (h.resolve_right (by intro e; cases e))),
      ⟨_, Keeps.moved Γ hy⟩⟩
  | copyRoot hy hl hm =>
    have hN := hn _ _ hy hl (Or.inr hm)
    exact ⟨hn, fun _ _ => by
      show DepsNamed Γ (derive _ _ .self ++ _); exact (derive_named hN rfl).append hN.held,
      ⟨[], Keeps.refl Γ []⟩⟩
  | copyBor hy hl hm =>
    exact ⟨hn, fun _ h => (hn _ _ hy hl (Or.inl (nonint h (Or.inl hm))) :), ⟨[], Keeps.refl Γ []⟩⟩
  | borrow hy hl ht =>
    have hN := hn _ _ hy hl (Or.inl (by rw [ht]; simp))
    exact ⟨hn, fun _ _ => by
      show DepsNamed Γ (derive _ _ .self ++ _); exact (derive_named hN rfl).append hN.held,
      ⟨[], Keeps.refl Γ []⟩⟩
  | «at» hy hl ht _ =>
    exact ⟨hn, fun _ _ => elemE_named (hn _ _ hy hl (Or.inl (by rw [ht]; simp))) _, ⟨[], Keeps.refl Γ []⟩⟩
  | view hy hl ht _ =>
    have hN := hn _ _ hy hl (Or.inl (by rw [ht]; simp))
    exact ⟨hn, fun _ _ => by
      show DepsNamed Γ (derive _ _ .view ++ _); exact (derive_named hN rfl).append hN.held,
      ⟨[], Keeps.refl Γ []⟩⟩
  | sat hy hl ht _ =>
    exact ⟨hn, fun _ _ => elemE_named (hn _ _ hy hl (Or.inl (by rw [ht]; simp))) _, ⟨[], Keeps.refl Γ []⟩⟩
  | @pop y E t hy hl ht _ _ =>
    have hN := hn _ _ hy hl (Or.inl (by rw [ht]; simp))
    have hk : Keeps Γ (kill .drop t.holdsView y Γ) [] := (Keeps.refl Γ []).kill _ _ _
    refine ⟨hn.kill _ _ _, fun _ _ => ?_, ⟨_, hk⟩⟩
    have hH : DepsNamed (kill .drop t.holdsView y Γ) E.held := hN.held.keeps' hk
    exact popE_named hH t
  | @pair y z Ey Ez Γ1 Γ2 Dy Dz hy hly hpa1 hz hlz hpa2 hzd =>
    obtain ⟨hn1, hD1, hk1⟩ := hpa1.names hy hly rfl hn
    obtain ⟨hn2, hD2, hk2⟩ := hpa2.names hz hlz rfl hn1
    -- what the first field holds by name is not the second, if it moves
    have hX : ∀ d ∈ Dy, d.kind.isName = true → d.root ∉ [z] := by
      intro d hd hk h
      simp only [List.mem_singleton] at h
      obtain ⟨Er, hEr, hnm⟩ := hD1.root hd hk
      rw [h, hz] at hEr; cases hEr
      exact hzd hnm.2.2.1 (h ▸ List.mem_map_of_mem hd)
    exact ⟨hn2, fun _ _ => own_named ((hD1.keeps hk2 hX).append hD2), ⟨_, hk1.trans hk2⟩⟩
  | fst hy hl ht =>
    exact ⟨hn, fun _ _ => projE_named (hn _ _ hy hl (Or.inl (by rw [ht]; simp))) _, ⟨[], Keeps.refl Γ []⟩⟩
  | snd hy hl ht =>
    exact ⟨hn, fun _ _ => projE_named (hn _ _ hy hl (Or.inl (by rw [ht]; simp))) _, ⟨[], Keeps.refl Γ []⟩⟩
  | getl hy hl ht =>
    exact ⟨hn, fun _ _ => projE_named (hn _ _ hy hl (Or.inl (by rw [ht]; simp))) _, ⟨[], Keeps.refl Γ []⟩⟩
  | getr hy hl ht =>
    exact ⟨hn, fun _ _ => projE_named (hn _ _ hy hl (Or.inl (by rw [ht]; simp))) _, ⟨[], Keeps.refl Γ []⟩⟩
  | inl hy hly hpa _ =>
    obtain ⟨hn1, hD, hk⟩ := hpa.names hy hly rfl hn
    exact ⟨hn1, fun _ _ => own_named hD, ⟨_, hk⟩⟩
  | inr hy hly hpa _ =>
    obtain ⟨hn1, hD, hk⟩ := hpa.names hy hly rfl hn
    exact ⟨hn1, fun _ _ => own_named hD, ⟨_, hk⟩⟩
  | @takel y E a b hy hl _ hty _ _ =>
    have hH := moved_named hn hy hl (by rw [hty]; simp)
    refine ⟨hn.moved hy, fun _ _ => ?_,
      ⟨_, Keeps.moved Γ hy⟩⟩
    cases a <;> first
      | exact fun _ h => by cases h
      | exact own_named hH
      | exact own_named (hH.sub (ownHeld_sub _ _ _))
      | (show DepsNamed _ (E.held ++ E.held); exact hH.append hH)
  | @taker y E a b hy hl _ hty _ _ =>
    have hH := moved_named hn hy hl (by rw [hty]; simp)
    refine ⟨hn.moved hy, fun _ _ => ?_,
      ⟨_, Keeps.moved Γ hy⟩⟩
    cases b <;> first
      | exact fun _ h => by cases h
      | exact own_named hH
      | exact own_named (hH.sub (ownHeld_sub _ _ _))
      | (show DepsNamed _ (E.held ++ E.held); exact hH.append hH)
  | pack hy hly hte hpa hcaps =>
    obtain ⟨hn1, hD, hk⟩ := hpa.names hy hly hte hn
    exact ⟨hn1, fun _ _ => own_named (hD.append hcaps.named), ⟨_, hk⟩⟩

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

theorem mem_movedArgs {ps : List (PMode × Ty)} {args : List Var} {a : Var} (h : a ∈ movedArgs ps args) :
    ∃ i p, ps[i]? = some p ∧ p.1 ≠ .inp ∧ a = args.getD i 0 := by
  unfold movedArgs at h
  obtain ⟨i, hi, rfl⟩ := List.mem_map.mp h
  obtain ⟨hir, hm⟩ := List.mem_filter.mp hi
  have hil := List.mem_range.mp hir
  refine ⟨i, ps[i], List.getElem?_eq_getElem hil, fun he => ?_, rfl⟩
  rw [List.getElem?_eq_getElem hil] at hm
  revert hm he
  generalize ps[i] = p
  obtain ⟨pm, t⟩ := p
  intro hm he
  simp only at he; subst he; simp at hm

/-- The arguments a call ends (its `sink` ones): a binding handed over
    `inout` is live again after the call, so a name on it stays valid. -/
def sunkArgs (ps : List (PMode × Ty)) (args : List Var) : List Var :=
  ((List.range ps.length).filter (fun i => match ps[i]? with
      | some (.sink, _) => true
      | _ => false)).map (fun i => args.getD i 0)

theorem mem_sunkArgs {ps : List (PMode × Ty)} {args : List Var} {a : Var} (h : a ∈ sunkArgs ps args) :
    ∃ i p, ps[i]? = some p ∧ p.1 = .sink ∧ a = args.getD i 0 := by
  unfold sunkArgs at h
  obtain ⟨i, hi, rfl⟩ := List.mem_map.mp h
  obtain ⟨hir, hm⟩ := List.mem_filter.mp hi
  have hil := List.mem_range.mp hir
  refine ⟨i, ps[i], List.getElem?_eq_getElem hil, ?_, rfl⟩
  rw [List.getElem?_eq_getElem hil] at hm
  revert hm
  generalize ps[i] = p
  obtain ⟨pm, t⟩ := p
  intro hm
  cases pm <;> simp_all

theorem mem_sunkArgs_of {ps : List (PMode × Ty)} {args : List Var} {i : Nat} {p : PMode × Ty}
    (hp : ps[i]? = some p) (hm : p.1 = .sink) : args.getD i 0 ∈ sunkArgs ps args := by
  unfold sunkArgs
  have hil := (List.getElem?_eq_some_iff.mp hp).1
  refine List.mem_map.mpr ⟨i, List.mem_filter.mpr ⟨List.mem_range.mpr hil, ?_⟩, rfl⟩
  rw [hp]
  obtain ⟨pm, t⟩ := p
  simp only at hm; subst hm; rfl

theorem mem_movedArgs_of {ps : List (PMode × Ty)} {args : List Var} {i : Nat} {p : PMode × Ty}
    (hp : ps[i]? = some p) (hm : p.1 ≠ .inp) : args.getD i 0 ∈ movedArgs ps args := by
  unfold movedArgs
  have hil := (List.getElem?_eq_some_iff.mp hp).1
  refine List.mem_map.mpr ⟨i, List.mem_filter.mpr ⟨List.mem_range.mpr hil, ?_⟩, rfl⟩
  rw [hp]
  obtain ⟨pm, t⟩ := p
  cases pm with
  | inp => exact absurd rfl hm
  | _ => rfl

theorem mem_zip_idx {α β : Type} {ps : List α} {as : List β} {p : α} {a : β} (h : (p, a) ∈ ps.zip as) :
    ∃ k, ∃ (h1 : k < ps.length) (h2 : k < as.length), ps[k] = p ∧ as[k] = a := by
  obtain ⟨k, hk, he⟩ := List.getElem_of_mem h
  simp only [List.getElem_zip, Prod.mk.injEq, List.length_zip] at he hk
  exact ⟨k, by omega, by omega, he.1, he.2⟩

theorem rootKind_isName (t : Ty) (k : Kind) : (rootKind t k).isName = k.isName := by
  cases t <;> cases k <;> rfl

/-- What a summary pair of a kind other than by name lends by name, the
    argument depends on. -/
theorem argDeps_name {Γ : Ctx} {args : List Var} {jk : Nat × Kind} (hk : jk.2.isName = false)
    {d : Dep} (hd : d ∈ argDeps Γ args jk) (hn : d.kind.isName = true) :
    d.root ∈ roots (argE Γ (args.getD jk.1 0)).vdeps := by
  unfold argDeps at hd
  split at hd
  · cases hd
  unfold derive at hd
  split at hd
  · simp only [List.mem_singleton] at hd; subst hd
    simp only [rootKind_isName] at hn; rw [hk] at hn; cases hn
  · rename_i hr
    obtain ⟨d', hd', rfl⟩ := List.mem_map.mp hd
    have ho : (argE Γ (args.getD jk.1 0)).mode.ownSlot = false := by
      cases h : (argE Γ (args.getD jk.1 0)).mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
    exact List.mem_map_of_mem (f := Dep.root) (a := d')
      (by unfold Entry.vdeps; rw [ho]; exact List.mem_append_left _ hd')

/-- What the arguments hold by name, an argument depends on. -/
theorem heldOfArgs_name {Γ : Ctx} {args : List Var} {d : Dep} (hd : d ∈ heldOfArgs Γ args)
    (hn : d.kind.isName = true) : ∃ a ∈ args, d.root ∈ roots (argE Γ a).vdeps := by
  unfold heldOfArgs at hd
  rcases List.mem_append.mp hd with hd | hd
  · simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil, or_false] at hd
    obtain ⟨r, _, hd⟩ := hd
    rcases hd with rfl | rfl | rfl <;> cases hn
  · obtain ⟨a, ha, hd⟩ := List.mem_flatMap.mp hd
    split at hd
    · cases hd
    · exact ⟨a, ha, List.mem_map_of_mem (List.mem_filter.mp hd).1⟩

theorem killNames_some {Γ : Ctx} {v : Var} {E : Entry} :
    ∀ {ds : List Dep}, killNames ds Γ v = some E → ∃ E1, Γ v = some E1 ∧ E.vdeps = E1.vdeps ∧
      (E.live = true → E1.live = true) ∧ E.ty = E1.ty ∧ E.mode = E1.mode
  | [], h => ⟨E, h, rfl, id, rfl, rfl⟩
  | d :: ds, h => by
    simp only [killNames, List.foldr_cons] at h
    change A2.kill _ _ _ (killNames ds Γ) v = some E at h
    simp only [A2.kill] at h
    obtain ⟨E2, h2, rfl⟩ := Option.map_eq_some_iff.mp h
    obtain ⟨E1, h1, hv, hl, ht, hm⟩ := killNames_some h2
    exact ⟨E1, h1, by rw [killE_vdeps, hv], fun h' => hl (by rw [killE_live] at h'; simp at h'; exact h'.1),
      by rw [killE_ty, ht], by rw [killE_mode, hm]⟩

/-- What the call leaves of each binding.  Every live entry depends, by
    name, only on what it did before the call (`Γ0`), and on no binding
    `X` the call moved; bindings that may be held by name still may be,
    but for those moved. -/
theorem callPostAux_names {Γ0 : Ctx} {fn : Fn} {args : List Var} (S : List Var)
    (hD : ∀ i, DepsNamed Γ0 (outHeld Γ0 fn args i)) (hH : DepsNamed Γ0 (heldOfArgs Γ0 args))
    (hDS : ∀ i, ∀ d ∈ outHeld Γ0 fn args i, d.kind.isName = true → d.root ∉ S)
    (hHS : ∀ d ∈ heldOfArgs Γ0 args, d.kind.isName = true → d.root ∉ S) :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx) (X : List Var),
      (∀ p a, (p, a) ∈ ps.zip as → ∃ E0, Γ0 a = some E0 ∧ E0.ty = p.2 ∧
        (E0.live = true → (E0.ty ≠ .int ∨ E0.mode = .rootb) →
          NameOK Γ0 E0 ∧ ∀ d ∈ E0.vdeps, d.kind.isName = true → d.root ∉ S) ∧
        (p.1 = .sink → a ∈ S)) →
      X ⊆ S → Keeps Γ0 Γ X →
      (∀ v E, Γ v = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
        DepsNamed Γ0 E.vdeps ∧ ∀ d ∈ E.vdeps, d.kind.isName = true → d.root ∉ X) →
      ∃ Y, Y ⊆ S ∧ Keeps Γ0 (callPostAux Γ0 fn args ps as i Γ) Y ∧
        ∀ v E, callPostAux Γ0 fn args ps as i Γ v = some E → E.live = true →
          (E.ty ≠ .int ∨ E.mode = .rootb) →
          DepsNamed Γ0 E.vdeps ∧ ∀ d ∈ E.vdeps, d.kind.isName = true → d.root ∉ Y := by
  intro ps
  induction ps with
  | nil => intro as i Γ X _ hX hk hI; cases as <;> exact ⟨X, hX, hk, hI⟩
  | cons p ps ih =>
    intro as i Γ X has hX hk hI
    obtain ⟨pm, t⟩ := p
    cases as with
    | nil => cases pm <;> exact ⟨X, hX, hk, hI⟩
    | cons a as =>
      obtain ⟨E0, h0, hty0, hN0, hsink⟩ := has (pm, t) a (by simp)
      have has' : ∀ p a', (p, a') ∈ ps.zip as → _ := fun p a' h' => has p a' (by simp [h'])
      have hargE : argE Γ0 a = E0 := by unfold argE; rw [h0]; rfl
      -- killing keeps the invariant
      have hIk : ∀ e hv, ∀ v E, A2.kill e hv a Γ v = some E → E.live = true →
          (E.ty ≠ .int ∨ E.mode = .rootb) →
          DepsNamed Γ0 E.vdeps ∧ ∀ d ∈ E.vdeps, d.kind.isName = true → d.root ∉ X := by
        intro e hv v E hv' hl hn
        simp only [A2.kill] at hv'
        obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hv'
        rw [killE_ty, killE_mode] at hn
        rw [killE_vdeps]; exact hI v E1 h1 (killE_live_dep hl hn).1 hn
      cases pm with
      | inp => exact ih as (i + 1) Γ X has' hX hk hI
      | sink =>
        simp only [callPostAux]
        refine ih as (i + 1) _ (a :: X) has'
          (fun v hv => (List.mem_cons.mp hv).elim (fun h => h ▸ hsink rfl) (fun h => hX h))
          ((hk.kill _ _ _).setX fun E0' h0' => by rw [h0] at h0'; cases h0'; rw [hargE]; exact ⟨rfl, rfl⟩)
          (fun v E hv hl hn => ?_)
        by_cases hva : v = a
        · subst hva; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv; simp at hl
        · simp only [A2.setE, upd_ne _ _ hva] at hv
          obtain ⟨hd, hnX⟩ := hIk _ _ v E hv hl hn
          refine ⟨hd, fun d hd' hk' hm => ?_⟩
          rcases List.mem_cons.mp hm with h | h
          · exact kill_ends hv hl hn d hd' h
          · exact hnX d hd' hk' h
      | inout b =>
        simp only [callPostAux]
        refine ih as (i + 1) _ X has' hX
          ((hk.kill _ _ _).setE fun E0' h0' => ?_) (fun v E hv hl hn => ?_)
        · rw [h0] at h0'; cases h0'; rw [hargE]
          refine ⟨rfl, rfl, fun _ hnm => ⟨hnm.1, ?_, hnm.2.2.1, hnm.2.2.2⟩⟩
          have : t.holdsView = false := by have h' := hnm.2.2.2; rw [hty0] at h'; exact h'
          simp only [this, Bool.false_eq_true, ↓reduceIte]; exact hnm.2.1
        · by_cases hva : v = a
          · subst hva; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv
            rw [hargE] at hl hn ⊢
            obtain ⟨hN, hNS⟩ := hN0 hl hn
            refine ⟨fun d hd => ?_, fun d hd hk' hm => ?_⟩
            · simp only [Entry.vdeps, List.mem_append] at hd
              rcases hd with hd | hd
              · exact hN d (List.mem_append_left _ hd)
              · split at hd
                · simp only [List.mem_append] at hd
                  rcases hd with (hd | hd) | hd
                  · exact hN d (List.mem_append_right _ hd)
                  · exact hD i d hd
                  · exact hH d hd
                · exact hN d (List.mem_append_right _ hd)
            · have hS : d.root ∉ S := by
                simp only [Entry.vdeps, List.mem_append] at hd
                rcases hd with hd | hd
                · exact hNS d (List.mem_append_left _ hd) hk'
                · split at hd
                  · simp only [List.mem_append] at hd
                    rcases hd with (hd | hd) | hd
                    · exact hNS d (List.mem_append_right _ hd) hk'
                    · exact hDS i d hd hk'
                    · exact hHS d hd hk'
                  · exact hNS d (List.mem_append_right _ hd) hk'
              exact hS (hX hm)
          · simp only [A2.setE, upd_ne _ _ hva] at hv
            exact hIk _ _ v E hv hl hn

/-- A call keeps what contexts hold by name valid, and so is its result. -/
theorem CallT.names {P : Prog} (hP : ProgOK P) {Γ Γ1 : Ctx} {F : List Var} {f : Nat}
    {args : List Var} {E : Entry} (hc : CallT P Γ F f args E Γ1) (hn : NameWF Γ) :
    NameWF Γ1 ∧ (E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → NameOK Γ1 E) ∧
      ∃ X, Keeps Γ Γ1 X := by
  obtain ⟨fn, hf, hlen, hargs, _, _, rfl, rfl⟩ := hc
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
  -- what the call ends, no argument depends on
  let S := sunkArgs fn.params args
  have hfree : ∀ j < fn.params.length, ∀ r ∈ roots (argE Γ (args.getD j 0)).vdeps, r ∉ S := by
    intro j hj r hr hS
    obtain ⟨i, p, hp, hpm, rfl⟩ := mem_sunkArgs hS
    have hil := (List.getElem?_eq_some_iff.mp hp).1
    have hget := (List.getElem?_eq_some_iff.mp hp).2
    obtain ⟨Ea, hEa, _, _, hmv, _⟩ := hargs i hil
    have hsink : fn.params[i].1 = .sink := by rw [hget]; exact hpm
    have hmoves : fn.params[i].1.moves = true := by rw [hsink]; rfl
    obtain ⟨_, _, hns, _, hdist⟩ := hmv hmoves
    by_cases hji : j = i
    · subst hji; unfold argE at hr; rw [hEa] at hr; exact hns hsink hr
    · exact (hdist j hj hji).2.2.1 hsink hr
  have hfreeA : ∀ a ∈ args, ∀ r ∈ roots (argE Γ a).vdeps, r ∉ S := by
    intro a ha r hr
    obtain ⟨j, hj, rfl⟩ := mem_args ha
    exact hfree j (hlen ▸ hj) r hr
  have hdS : ∀ jk : Nat × Kind, jk.1 < fn.params.length → jk.2.isName = false →
      ∀ d ∈ argDeps Γ args jk, d.kind.isName = true → d.root ∉ S :=
    fun jk hj hk d hd hn => hfree jk.1 hj _ (argDeps_name hk hd hn)
  have hHS : ∀ d ∈ heldOfArgs Γ args, d.kind.isName = true → d.root ∉ S := by
    intro d hd hn
    obtain ⟨a, ha, hr⟩ := heldOfArgs_name hd hn
    exact hfreeA a ha _ hr
  have hDS : ∀ i, ∀ d ∈ outHeld Γ fn args i, d.kind.isName = true → d.root ∉ S := by
    intro i d hd hn
    obtain ⟨o, ho, hdo⟩ := List.mem_flatMap.mp hd
    obtain ⟨⟨hj, _⟩, hk⟩ := houts o (List.mem_filter.mp ho).1
    exact hdS _ hj hk d hdo hn
  obtain ⟨Y, hYS, hkY, hIY⟩ := callPostAux_names (fn := fn) (args := args) S hout hheld hDS hHS
    fn.params args 0 Γ []
    (fun p a hpa => by
      obtain ⟨k, hk1, hk2, hpk, hak⟩ := mem_zip_idx hpa
      have hak' : args.getD k 0 = a := by simp [List.getD, hk2, hak]
      obtain ⟨Ea, hEa, hl, hok, _⟩ := hargs k hk1
      rw [hak'] at hEa
      have hae : argE Γ a = Ea := by unfold argE; rw [hEa]; rfl
      refine ⟨Ea, hEa, ?_, fun hl' hn' => ⟨hn _ Ea hEa hl' hn', fun d hd _ hS =>
        hfreeA a (hak ▸ List.getElem_mem hk2) d.root (hae ▸ List.mem_map_of_mem hd) hS⟩, fun hs => ?_⟩
      · rw [← hpk]; revert hok; generalize fn.params[k] = q; obtain ⟨pm, t⟩ := q
        cases pm <;> simp only [paramOK] <;> intro h
        · exact h
        · exact h.1
        · exact h.1
      · rw [← hak']
        exact mem_sunkArgs_of (List.getElem?_eq_getElem hk1) (by rw [hpk, hs]))
    (fun _ h => by cases h) (Keeps.refl Γ [])
    (fun v E hv hl hn' => ⟨hn v E hv hl hn', fun _ _ _ h => by cases h⟩)
  have hk : Keeps Γ (callPost Γ fn args) Y := hkY.killNames _
  refine ⟨fun v E hv hl hn' => ?_, fun _ _ => ?_, ⟨Y, hk⟩⟩
  · -- what the closures handed over change ends nothing held by name
    obtain ⟨E1, h1, hvd, hl1, ht1, hm1⟩ := killNames_some hv
    rw [ht1, hm1] at hn'
    obtain ⟨hD1, hY1⟩ := hIY v E1 h1 (hl1 hl) hn'
    show DepsNamed _ E.vdeps
    rw [hvd]; exact hD1.keeps hk hY1
  · have hl : DepsNamed Γ (fn.lends.flatMap (argDeps Γ args)) :=
      DepsNamed.flatMap fun jk hjk => by
        obtain ⟨⟨hj, _⟩, hk⟩ := hlends jk hjk; exact hdeps jk hj hk
    have hr : DepsNamed Γ (fn.rholds.flatMap (argDeps Γ args)) :=
      DepsNamed.flatMap fun jk hjk => by
        obtain ⟨⟨hj, _⟩, hk⟩ := hrholds jk hjk; exact hdeps jk hj hk
    have hsub : ∀ d ∈ (callRes Γ fn args).vdeps, d ∈ fn.lends.flatMap (argDeps Γ args) ∨
        d ∈ heldOfArgs Γ args ∨ d ∈ fn.rholds.flatMap (argDeps Γ args) := by
      intro d hd
      unfold Entry.vdeps at hd
      rcases List.mem_append.mp hd with hd | hd
      · split at hd
        · cases hd
        · simp only [callRes] at hd
          rcases List.mem_append.mp hd with hd | hd
          · exact Or.inl hd
          · exact Or.inr (Or.inl hd)
      · simp only [callRes] at hd
        rcases List.mem_append.mp (ownHeld_sub _ _ _ hd) with hd | hd
        · exact Or.inr (Or.inr hd)
        · exact Or.inr (Or.inl hd)
    refine NameOK.keeps (Γ0 := Γ) (fun d hd => ?_) hk (fun d hd hn' hY => ?_)
    · rcases hsub d hd with hd | hd | hd
      · exact hl d hd
      · exact hheld d hd
      · exact hr d hd
    · have : d.root ∉ S := by
        rcases hsub d hd with hd | hd | hd
        · obtain ⟨jk, hjk, hdj⟩ := List.mem_flatMap.mp hd
          obtain ⟨⟨hj, _⟩, hk⟩ := hlends jk hjk
          exact hdS jk hj hk d hdj hn'
        · exact hHS d hd hn'
        · obtain ⟨jk, hjk, hdj⟩ := List.mem_flatMap.mp hd
          obtain ⟨⟨hj, _⟩, hk⟩ := hrholds jk hjk
          exact hdS jk hj hk d hdj hn'
      exact this (hYS hY)

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
    NameWF (A2.setE (A2.setE (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) x
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
    have hx1 : A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false } x = none := by
      simp [A2.setE, upd_ne _ _ hxy, A2.kill, hx]
    have hn2 := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) (fun _ _ => hcomp _ a hH)
    have hz2 : A2.setE (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) x (compE E a) z
        = none := by
      simp [A2.setE, upd_ne _ _ (Ne.symm hxz), upd_ne _ _ hzy, A2.kill, hz]
    have hk2 : Keeps (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false })
        (A2.setE (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) x (compE E a)) [] :=
      (Keeps.refl _ []).setE fun E0 h => by rw [hx1] at h; cases h
    have hn3 := NameWF.setE hn2 (fun Ex h => by rw [hz2] at h; cases h) (fun Ex h => by rw [hz2] at h; cases h)
      (fun _ _ => hcomp _ b (hH.keeps' hk2))
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
    exact (ih hks (NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) hE)).exitScope x
  | @letd Γ Γ1 Δ F x _ r k E H hks hx _ hr hmo _ _ hH _ _ ih =>
    intro _ hn
    obtain ⟨hn1, hE, _⟩ := hr.names hn
    have hx1 : Γ1 x = none := by
      have := (hr.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    exact (ih hks (NameWF.setE hn1 (E := Entry.arm { E with held := H }) (fun Ex h => by rw [hx1] at h; cases h)
      (fun Ex h => by rw [hx1] at h; cases h) (fun hl ht => (hE hl ht).widen hmo hH))).exitScope x
  | @letcall Γ Γ1 Δ F x f args k E hks hx _ hc _ _ ih =>
    intro _ hn
    obtain ⟨hn1, hE, _⟩ := hc.names hP hn
    have hx1 : Γ1 x = none := by
      have := (hc.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    exact (ih hks (NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) hE)).exitScope x
  | @letrec Γ Γ1 Δ F x f k E fn hks hx _ _ _ _ _ hc _ _ ih =>
    intro _ hn
    obtain ⟨hn1, hE, _⟩ := hc.names hP hn
    have hx1 : Γ1 x = none := by
      have := (hc.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    exact (ih hks (NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) hE)).exitScope x
  | @callc Γ Γ1 Δ F x c j zs k Ec E ms σ sig hks hx _ hc htc _ _ _ _ hcT _ _ _ ih =>
    intro _ hn
    obtain ⟨hn1, hE, hk⟩ := hcT.names hP hn
    have hx1 : Γ1 x = none := by
      have := (hcT.domMode).1 x; rw [hx] at this; cases h : Γ1 x <;> simp_all
    exact (ih hks (NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h)
      (recvRes_named hE))).exitScope x
  | @unpair Γ Δ F y x z k E a b hks hy hl _ hty _ hx hz hxz _ _ _ _ _ _ _ ih =>
    intro _ hn
    exact ((ih hks (hn.unpair hy hl hty hx hz hxz)).exitScope z).exitScope x
  | @assign Γ Γ1 F x r Ex E hx _ hmodes hr hty hxd _ _ =>
    intro _ hn
    obtain ⟨hn1, hE, X, hk⟩ := hr.names hn
    obtain ⟨Ex1, hx1, ht1, hm1, _⟩ := hk x Ex hx
    have hos : Ex.mode.ownSlot = E.mode.ownSlot := by
      rcases hmodes with ⟨h1, h2⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rw [h1, h2] <;> rfl
    have hti : ∀ (hni : ({ E with mode := Ex.mode } : Entry).ty ≠ .int ∨
        ({ E with mode := Ex.mode } : Entry).mode = .rootb), E.ty ≠ .int := by
      intro hni
      rcases hni with h | h
      · exact h
      · exfalso; simp only at h
        rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩ <;> rw [h1] at h <;> cases h
    refine hn1.replaced (fun Ex' h => ?_) (fun _ _ d hd _ h => ?_) (fun hl hni => ?_)
    · rw [hx1] at h; cases h
      exact ⟨by rw [ht1, hty], by rw [hm1]⟩
    · rw [vdeps_mode hos] at hd; exact hxd (h ▸ List.mem_map_of_mem hd)
    · have hN := hE hl (Or.inl (hti hni))
      refine NameOK.keeps (Γ0 := Γ1) ?_ ((Keeps.refl _ []).kill _ _ _) (fun _ _ _ h => by cases h)
      show DepsNamed Γ1 ({ E with mode := Ex.mode } : Entry).vdeps
      rw [vdeps_mode hos]; exact hN
  | ite _ _ _ _ _ iha _ => intro hs hn; simp only [Stmt.src, Bool.and_eq_true] at hs; exact iha hs.1 hn
  | «while» => exact fun _ h => h
  | @push Γ Γ1 F x y Ex Ey Ex1 t D hx hlx htx _ _ hy hly htyy _ hpa _ hx1 hl1 =>
    intro _ hn
    obtain ⟨hn1, hD, hky⟩ := hpa.names hy hly htyy hn
    obtain ⟨Ex2, hx2, ht2, _⟩ := hky x Ex hx
    rw [hx1] at hx2; cases hx2
    refine NameWF.setE (hn1.kill _ _ _) (fun Ex' h => ?_) (fun Ex' h hnm => Or.inl ?_) (fun hl hni => ?_)
    · simp only [A2.kill, hx1, Option.map_some, Option.some.injEq] at h; subst h
      exact ⟨by rw [killE_ty], by rw [killE_mode]⟩
    · simp only [A2.kill, hx1, Option.map_some, Option.some.injEq] at h; subst h
      replace hnm : Ex1.named := by
        unfold killE at hnm; split at hnm
        · simp [Entry.named] at hnm
        · exact hnm
      have hv : t.holdsView = false := by have h' := hnm.2.2.2; rw [ht2, htx] at h'; exact h'
      exact ⟨hnm.1, by simp [hnm.2.1, ownHeld, hv], hnm.2.2.1, hnm.2.2.2⟩
    · have hN := hn1 x Ex1 hx1 hl1 (by
        rcases hni with h | h
        · exact Or.inl h
        · exact Or.inr h)
      refine NameOK.keeps (Γ0 := Γ1) ?_ ((Keeps.refl _ []).kill _ _ _) (fun _ _ _ h => by cases h)
      intro d hd
      simp only [Entry.vdeps, List.mem_append] at hd
      rcases hd with hd | hd | hd
      · exact hN d (List.mem_append_left _ hd)
      · exact hN d (List.mem_append_right _ hd)
      · exact hD d (ownHeld_sub _ _ _ hd)
  | @free Γ F x E t hx _ _ _ _ _ =>
    intro _ hn
    exact hn.moved hx
  | panic _ hnΔ _ _ => exact fun _ _ => hnΔ
  | catchR => intro hs; simp [Stmt.src] at hs
  | scope => intro hs; simp [Stmt.src] at hs
  | scopeD => intro hs; simp [Stmt.src] at hs
  | rbind => intro hs; simp [Stmt.src] at hs
  | frozen => intro hs; simp [Stmt.src] at hs

end A2
