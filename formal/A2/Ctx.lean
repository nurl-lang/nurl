import A2.Basic

/-! A2 — facts about contexts and about validity. -/

namespace A2

theorem EntryWeaker.refl (E : Entry) : EntryWeaker E E := by
  refine ⟨rfl, rfl, fun _ => rfl, fun h => ⟨h, fun _ => List.Subset.refl _, List.Subset.refl _⟩,
    fun h => ⟨h, List.Subset.refl _⟩, (by simp_all), (fun _ => by simp_all), (fun _ => by simp_all)⟩

theorem EntryWeaker.trans {E1 E2 E3 : Entry} (h1 : EntryWeaker E1 E2) (h2 : EntryWeaker E2 E3) :
    EntryWeaker E1 E3 := by
  obtain ⟨t1, m1, r1, l1, d1, b1, a1, k1⟩ := h1
  obtain ⟨t2, m2, r2, l2, d2, b2, a2, k2⟩ := h2
  refine ⟨t2.trans t1, m2.trans m1, fun h => ?_, fun h => ?_, fun h => ?_, b2.trans b1, fun h => ?_,
    fun h => (k2 (b1 ▸ h)).trans (k1 h)⟩
  rotate_right
  · rcases a2 h with h2 | h2
    · exact a1 h2
    · exact Or.inr (b1 ▸ h2)
  · have e12 := r1 h; subst e12; exact r2 h
  · obtain ⟨a2, p2, h2'⟩ := l2 h
    obtain ⟨a1, p1, h1'⟩ := l1 a2
    refine ⟨a1, fun ho => ?_, h1'.trans h2'⟩
    have ho2 : E2.mode.ownSlot = false := by rw [m1]; exact ho
    exact (p1 ho).trans (p2 ho2)
  · obtain ⟨h2d, h12⟩ := d1 h
    obtain ⟨h3d, h23⟩ := d2 h2d
    exact ⟨h3d, h12.trans h23⟩

theorem Weaker.refl {Γ : Ctx} (h : CtxWF Γ) (hn : NameWF Γ) : Weaker Γ Γ := by
  refine ⟨fun v => ⟨Iff.rfl, fun E E' h1 h2 => ?_⟩, h, hn⟩
  rw [h1] at h2; cases h2; exact EntryWeaker.refl E

theorem Weaker.trans {Γ1 Γ2 Γ3 : Ctx} (h1 : Weaker Γ1 Γ2) (h2 : Weaker Γ2 Γ3) : Weaker Γ1 Γ3 := by
  refine ⟨fun v => ⟨(h1.1 v).1.trans (h2.1 v).1, fun E E' e1 e3 => ?_⟩, h2.2⟩
  cases e2 : Γ2 v with
  | none => exact absurd e2 (by rw [← (h1.1 v).1, e1]; simp)
  | some E2 => exact ((h1.1 v).2 E E2 e1 e2).trans ((h2.1 v).2 E2 E' e2 e3)

theorem Weaker.wf {Γ Γ' : Ctx} (h : Weaker Γ Γ') : CtxWF Γ' := h.2.1

theorem Weaker.names {Γ Γ' : Ctx} (h : Weaker Γ Γ') : NameWF Γ' := h.2.2

theorem Weaker.get {Γ Γ' : Ctx} (h : Weaker Γ Γ') {v : Var} {E : Entry} (hv : Γ v = some E) :
    ∃ E', Γ' v = some E' ∧ EntryWeaker E E' := by
  cases e : Γ' v with
  | none => exact absurd ((h.1 v).1.mpr e) (by rw [hv]; simp)
  | some E' => exact ⟨E', rfl, (h.1 v).2 E E' hv e⟩

theorem Weaker.get' {Γ Γ' : Ctx} (h : Weaker Γ Γ') {v : Var} {E' : Entry} (hv : Γ' v = some E') :
    ∃ E, Γ v = some E ∧ EntryWeaker E E' := by
  cases e : Γ v with
  | none => exact absurd ((h.1 v).1.mp e) (by rw [hv]; simp)
  | some E => exact ⟨E, rfl, (h.1 v).2 E E' e hv⟩

theorem Weaker.isSome {Γ Γ' : Ctx} (h : Weaker Γ Γ') (v : Var) : (Γ v).isSome = (Γ' v).isSome := by
  have := (h.1 v).1
  cases e : Γ v <;> cases e' : Γ' v <;> simp_all

/-! ### Validity is monotone in what a value may depend on. -/

theorem ViewsOK.mono {m : Mem} {τ : Ty} {T : Val} {H H' : List Dep} (hs : H ⊆ H')
    (h : ViewsOK m τ T H) : ViewsOK m τ T H' := by
  intro s v hv
  obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := h s v hv
  exact ⟨d, o, l, rfl, dep, hs hd, ha⟩

/-- A view is valid through a dependency on memory. -/
theorem ViewsOK.memDeps {m : Mem} {τ : Ty} {T : Val} {H : List Dep} (h : ViewsOK m τ T H) :
    ViewsOK m τ T (A2.memDeps H) := by
  intro s v hv
  obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := h s v hv
  refine ⟨d, o, l, rfl, dep, List.mem_filter.mpr ⟨hd, ?_⟩, ha⟩
  obtain ⟨_, _, _, _, hk, _⟩ := ha
  rcases hk with ⟨hk, _⟩ | ⟨hk, _⟩ <;> rw [hk] <;> rfl

/-- A view is valid only through a dependency that ends views, never through
    a name: what a value's views need, it needs of `readers`. -/
theorem ViewsOK.readers {m : Mem} {τ : Ty} {T : Val} {H : List Dep} (h : ViewsOK m τ T H) :
    ViewsOK m τ T (readers H) := by
  intro s v hv
  obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := h s v hv
  refine ⟨d, o, l, rfl, dep, mem_readers.mpr ⟨hd, ?_⟩, ha⟩
  obtain ⟨n0, c, es, _, hk, _⟩ := ha
  rcases hk with ⟨hk, _⟩ | ⟨hk, _⟩ <;> simp [hk, Kind.bound]

theorem NamesIn.mono {T : Val} {H H' : List Dep} (h : NamesIn T H) (hs : H ⊆ H') : NamesIn T H' :=
  fun c hc => hs (h c hc)

theorem HrefAt.mono {m : Mem} {dep : Dep} {c : Nat} {t : Ty} {H H' : List Dep} (hs : H ⊆ H')
    (h : HrefAt m dep c t H) : HrefAt m dep c t H' := by
  obtain ⟨n0, d, es, hr, hk, hw, hv, hn⟩ := h
  exact ⟨n0, d, es, hr, hk, hw, hv.mono hs, hn.mono hs⟩

theorem ValOK.mono' {m : Mem} {τ : Ty} {v : Val} {P H : List Dep} (h : ValOK m τ v P H) :
    ∀ {P' H' : List Dep}, P ⊆ P' → H ⊆ H' → ValOK m τ v P' H' := by
  have app : ∀ {P H P' H' : List Dep}, P ⊆ P' → H ⊆ H' → P ++ H ⊆ P' ++ H' := fun hp hs =>
    List.append_subset.mpr ⟨fun _ h => List.mem_append_left _ (hp h), fun _ h => List.mem_append_right _ (hs h)⟩
  induction h with
  | int => intro _ _ _ _; exact .int
  | href h =>
    intro P' H' hp hs; obtain ⟨dep, hd, ha⟩ := h; exact .href ⟨dep, hp hd, ha.mono hs⟩
  | view h =>
    intro P' H' hp hs; obtain ⟨dep, hd, ha⟩ := h; exact .view ⟨dep, hp hd, ha⟩
  | pair _ _ ihx ihy => intro P' H' hp hs; exact .pair (ihx (app hp hs) hs) (ihy (app hp hs) hs)
  | inl _ ih => intro P' H' hp hs; exact .inl (ih (app hp hs) hs)
  | inr _ ih => intro P' H' hp hs; exact .inr (ih (app hp hs) hs)
  | pkg _ ih =>
    intro P' H' hp hs; exact .pkg (ih (app hp (envDeps_mono hs)) (envDeps_mono hs))

theorem ValOK.mono {m : Mem} {τ : Ty} {v : Val} {P P' H H' : List Dep} (hp : P ⊆ P')
    (hs : H ⊆ H') (h : ValOK m τ v P H) : ValOK m τ v P' H' := h.mono' hp hs

/-- What a value's handles need of what it depends on is views, never names:
    keeping only what changes nothing by name keeps it valid. -/
theorem ValOK.onlyReaders {m : Mem} {τ : Ty} {v : Val} {P H : List Dep} (h : ValOK m τ v P H) :
    ∀ {P' : List Dep}, (∀ d ∈ P, d.kind.bound = .none → d ∈ P') → ValOK m τ v P' H := by
  have app : ∀ {P P' X : List Dep}, (∀ d ∈ P, d.kind.bound = .none → d ∈ P') →
      ∀ d ∈ P ++ X, d.kind.bound = .none → d ∈ P' ++ X := fun hp d hd hb => by
    rcases List.mem_append.mp hd with hd | hd
    · exact List.mem_append_left _ (hp d hd hb)
    · exact List.mem_append_right _ hd
  induction h with
  | int => intro _ _; exact .int
  | href h =>
    intro P' hp
    obtain ⟨dep, hd, n0, d, es, hr, hk, hrest⟩ := h
    refine .href ⟨dep, hp dep hd ?_, n0, d, es, hr, hk, hrest⟩
    rcases hk with ⟨hk, _⟩ | ⟨hk, _⟩ | ⟨hk, _⟩ <;> simp [hk, Kind.bound]
  | view h =>
    intro P' hp
    obtain ⟨dep, hd, ha⟩ := h
    refine .view ⟨dep, hp dep hd ?_, ha⟩
    obtain ⟨_, _, _, _, hk, _⟩ := ha
    rcases hk with ⟨hk, _⟩ | ⟨hk, _⟩ <;> simp [hk, Kind.bound]
  | pair _ _ ihx ihy => intro P' hp; exact .pair (ihx (app hp)) (ihy (app hp))
  | inl _ ih => intro P' hp; exact .inl (ih (app hp))
  | inr _ ih => intro P' hp; exact .inr (ih (app hp))
  | pkg _ ih => intro P' hp; exact .pkg (ih (app hp))

theorem SlotOK.weaker' {m : Mem} {E E' : Entry} {sl : Slot} (ht : E'.ty = E.ty) (hm : E'.mode = E.mode)
    (hl : E'.live = true → E.live = true ∧ (E.mode.ownSlot = false → E.path ⊆ E'.path) ∧ E.held ⊆ E'.held)
    (h : SlotOK m E sl) : SlotOK m E' sl := by
  obtain ⟨ho, hown, hbor⟩ := h
  refine ⟨by rw [hm]; exact ho, fun hos => ?_, fun hos => ?_⟩
  · rw [hm] at hos
    obtain ⟨hvec, hwf, hlive⟩ := hown hos
    refine ⟨by rw [ht]; exact hvec, fun T hT => by rw [ht]; exact hwf T hT, fun hl' => ?_⟩
    obtain ⟨a, _, hh⟩ := hl hl'
    obtain ⟨T, hT, hv⟩ := hlive a
    exact ⟨T, hT, by rw [ht]; exact hv.mono hh⟩
  · rw [hm] at hos
    intro hl'
    obtain ⟨a, hp, hh⟩ := hl hl'
    obtain ⟨v, hv, hok⟩ := hbor hos a
    exact ⟨v, hv, by rw [ht]; exact hok.mono (hp hos) hh⟩


theorem SlotOK.weaker {m : Mem} {E E' : Entry} {sl : Slot} (hw : EntryWeaker E E')
    (h : SlotOK m E sl) : SlotOK m E' sl := h.weaker' hw.1 hw.mode hw.live

theorem MInv.weaker {m : Mem} {Γ Γ' : Ctx} (hi : MInv m Γ) (hw : Weaker Γ Γ') : MInv m Γ' where
  dom v := by rw [← hw.isSome v]; exact hi.dom v
  slot v E' hv := by
    obtain ⟨E, hE, hwe⟩ := hw.get' hv
    obtain ⟨sl, hsl, hok, hslot⟩ := hi.slot v E hE
    exact ⟨sl, hsl, by rw [hwe.1]; exact hok, hslot.weaker hwe⟩
  heap := hi.heap
  nvSt := hi.nvSt
  noInout v E' b hv := by
    obtain ⟨E, hE, hwe⟩ := hw.get' hv
    rw [hwe.mode]; exact hi.noInout v E b hE
  wf := hw.wf
  rootbLive p E' hp hm := by
    obtain ⟨E, hE, hwe⟩ := hw.get' hp
    have hm' : E.mode = .rootb := by rw [← hwe.mode]; exact hm
    rw [hwe.fixed (Or.inl hm')]; exact hi.rootbLive p E hE hm'
  rootbLt p E' hp hm := by
    obtain ⟨E, hE, hwe⟩ := hw.get' hp
    have hm' : E.mode = .rootb := by rw [← hwe.mode]; exact hm
    rw [hwe.fixed (Or.inl hm')]; exact hi.rootbLt p E hE hm'
  names := hw.names
  held v E' sl T hv hl hsl hT := by
    obtain ⟨E, hE, hwe⟩ := hw.get' hv
    obtain ⟨hl0, _, hh⟩ := hwe.live hl
    exact (hi.held v E sl T hE hl0 hsl hT).mono hh
  pkgs := hi.pkgs

theorem Inv.weaker {m : Mem} {Γ Γ' : Ctx} {F : List Var} {s : Stmt} (hi : Inv m Γ F s)
    (hw : Weaker Γ Γ') : Inv m Γ' F s where
  toMInv := hi.toMInv.weaker hw
  nvS := hi.nvS
  nvF := hi.nvF
  anch p E' hp hm := by
    obtain ⟨E, hE, hwe⟩ := hw.get' hp
    have hm' : E.mode = .rootb := by rw [← hwe.mode]; exact hm
    rw [hwe.fixed (Or.inl hm')]; exact hi.anch p E hE hm'
  spineNd := hi.spineNd
  spineDom v hv := by
    obtain ⟨E, hE⟩ := hi.spineDom v hv
    obtain ⟨E', hE', _⟩ := hw.get hE
    exact ⟨E', hE'⟩
  catchOK := hi.catchOK
  cover := hi.cover
  pinOut p E' hp hm hps := by
    obtain ⟨E, hE, hwe⟩ := hw.get' hp
    have hm' : E.mode = .rootb := by rw [← hwe.mode]; exact hm
    rw [hwe.fixed (Or.inl hm')]; exact hi.pinOut p E hE hm' hps
  pinIn := hi.pinIn.of_rootb fun p E' hp hm => by
    obtain ⟨E, hE, hwe⟩ := hw.get' hp
    have hm' : E.mode = .rootb := by rw [← hwe.mode]; exact hm
    rw [hwe.fixed (Or.inl hm')]; exact hE

theorem Inv.weaker_iff_wf {m : Mem} {Γ : Ctx} {F : List Var} {s : Stmt} (hi : Inv m Γ F s) :
    Weaker Γ Γ := Weaker.refl hi.wf hi.names

end A2
