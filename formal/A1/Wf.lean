import A1.Progress

/-! A1 — the rules keep contexts well-formed: live entries depend only on
roots the context has. -/

namespace A1

theorem CtxWF.setE {Γ : Ctx} (h : CtxWF Γ) {x : Var} {E : Entry} (hx : ∃ Ex, Γ x = some Ex ∧
    (Ex.mode.isRoot = true → E.mode.isRoot = true))
    (hE : E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → ∀ r ∈ roots E.vdeps,
      (r = x ∧ E.mode.isRoot = true) ∨ (r ≠ x ∧ ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true)) :
    CtxWF (A1.setE Γ x E) := by
  obtain ⟨Ex, hEx, hrt⟩ := hx
  have hroot : ∀ r, (∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) →
      ∃ Er, A1.setE Γ x E r = some Er ∧ Er.mode.isRoot = true := by
    intro r ⟨Er, hEr, hro⟩
    by_cases hrx : r = x
    · subst hrx; rw [hEx] at hEr; cases hEr; exact ⟨E, by simp [A1.setE], hrt hro⟩
    · exact ⟨Er, by simp [A1.setE, upd_ne _ _ hrx, hEr], hro⟩
  intro v E' hv hl hn r hr
  by_cases hvx : v = x
  · subst hvx
    simp only [A1.setE, upd_same, Option.some.injEq] at hv; subst hv
    rcases hE hl hn r hr with ⟨rfl, hro⟩ | ⟨_, hex⟩
    · exact ⟨_, by simp [A1.setE], hro⟩
    · exact hroot r hex
  · simp only [A1.setE, upd_ne _ _ hvx] at hv
    exact hroot r (h v E' hv hl hn r hr)

/-- A fresh binding. -/
theorem CtxWF.add {Γ : Ctx} (h : CtxWF Γ) {x : Var} (hx : Γ x = none) {E : Entry}
    (hE : E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → ∀ r ∈ roots E.vdeps,
      ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) : CtxWF (A1.setE Γ x E) := by
  have hroot : ∀ r, (∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) →
      ∃ Er, A1.setE Γ x E r = some Er ∧ Er.mode.isRoot = true := by
    intro r ⟨Er, hEr, hro⟩
    have hrx : r ≠ x := fun h => by subst h; rw [hx] at hEr; cases hEr
    exact ⟨Er, by simp [A1.setE, upd_ne _ _ hrx, hEr], hro⟩
  intro v E' hv hl hn r hr
  by_cases hvx : v = x
  · subst hvx
    simp only [A1.setE, upd_same, Option.some.injEq] at hv; subst hv
    exact hroot r (hE hl hn r hr)
  · simp only [A1.setE, upd_ne _ _ hvx] at hv
    exact hroot r (h v E' hv hl hn r hr)

theorem CtxWF.exitScope {Γ : Ctx} (h : CtxWF Γ) (x : Var) : CtxWF (exitScope x Γ) := by
  intro v E hv' hl hn r hr
  have hvx : v ≠ x := fun e => by subst e; simp [A1.exitScope] at hv'
  simp only [A1.exitScope, upd_ne _ _ hvx] at hv'
  obtain ⟨Er, hEr, hro⟩ := (h.kill .replace false x) v E hv' hl hn r hr
  have hrx : r ≠ x := by
    intro hrx; subst hrx
    obtain ⟨E0, hE0, _, _⟩ := kill_cmode hv'
    simp only [A1.kill, hE0, Option.map_some, Option.some.injEq] at hv'
    subst hv'
    rw [killE_live] at hl
    simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hl
    rw [killE_ty, killE_mode] at hn
    rw [killE_vdeps] at hr
    obtain ⟨dep, hd, hdr⟩ := List.mem_map.mp hr
    have : hits .replace false r E0 = true := by
      unfold hits
      simp only [Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, List.any_eq_true, beq_iff_eq]
      refine ⟨?_, dep, hd, hdr, by cases dep.kind <;> rfl⟩
      rcases hn with h | h
      · exact Or.inl h
      · exact Or.inr (by rw [h])
    rw [this] at hl; cases hl.2
  exact ⟨Er, by simp [A1.exitScope, upd_ne _ _ hrx, hEr], hro⟩

theorem CtxWF.exitRoot {Γ : Ctx} (h : CtxWF Γ) (p : Var) (D : List Dep)
    (hD : ∀ d ∈ D, d.root ≠ p ∧ ∃ Er, Γ d.root = some Er ∧ Er.mode.isRoot = true) :
    CtxWF (exitRoot p D Γ) := by
  have := (Weaker.refl h).exitRoot p D hD
  exact this.wf

/-- What a right-hand side produces depends on roots the context has. -/
theorem RhsT.wf {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1)
    (h : CtxWF Γ) : CtxWF Γ1 ∧ (∀ x, (Γ1 x).isSome = (Γ x).isSome) ∧
      (∀ x E1, Γ1 x = some E1 → ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode) ∧
      (E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → ∀ r ∈ roots E.vdeps,
        ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true) := by
  have same : ∀ x E1, Γ x = some E1 → ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode :=
    fun x E1 h => ⟨E1, h, rfl⟩
  have hderive : ∀ y Ey k, Γ y = some Ey → Ey.live = true → (Ey.ty ≠ .int ∨ Ey.mode = .rootb) →
      ∀ r ∈ roots (derive y Ey k), ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
    intro y Ey k hy hl hn r hr
    unfold derive at hr
    cases hrt : Ey.mode.isRoot with
    | true =>
      simp only [hrt, ↓reduceIte, roots, List.map_cons, List.map_nil, List.mem_singleton] at hr
      subst hr; exact ⟨Ey, hy, hrt⟩
    | false =>
      simp only [hrt, Bool.false_eq_true, ↓reduceIte, roots, List.map_map, List.mem_map,
        Function.comp] at hr
      obtain ⟨dep, hd, rfl⟩ := hr
      have hos : Ey.mode.ownSlot = false := by
        cases hm : Ey.mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
      exact h y Ey hy hl hn dep.root (by simp [roots, Entry.vdeps, hos, List.mem_map_of_mem hd])
  have hheld : ∀ y Ey, Γ y = some Ey → Ey.live = true → (Ey.ty ≠ .int ∨ Ey.mode = .rootb) →
      ∀ r ∈ roots Ey.held, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
    intro y Ey hy hl hn r hr
    have hr' : r ∈ roots Ey.vdeps := by
      simp only [roots, Entry.vdeps, List.map_append, List.mem_append] at hr ⊢
      exact Or.inr hr
    exact h y Ey hy hl hn r hr'
  have hpath : ∀ y Ey, Γ y = some Ey → Ey.live = true → (Ey.ty ≠ .int ∨ Ey.mode = .rootb) →
      Ey.mode.ownSlot = false → ∀ r ∈ roots Ey.path, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
    intro y Ey hy hl hn hos r hr
    have hr' : r ∈ roots Ey.vdeps := by
      simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.map_append,
        List.mem_append] at hr ⊢
      exact Or.inl hr
    exact h y Ey hy hl hn r hr'
  have app : ∀ a b : List Dep, (∀ r ∈ roots a, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) →
      (∀ r ∈ roots b, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) →
      ∀ r ∈ roots (a ++ b), ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := fun a b => wf_append
  cases hr with
  | expr _ => exact ⟨h, fun _ => rfl, same, fun _ hn => by simp [intE] at hn⟩
  | new _ => exact ⟨h, fun _ => rfl, same, fun _ _ r hr => by simp [roots, Entry.vdeps, Mode.ownSlot] at hr⟩
  | @moveOwn y Ey hy hl hm _ =>
    have hwf : CtxWF (A1.setE (kill .replace false y Γ) y { Ey with live := false }) :=
      (h.kill .replace false y).setE ⟨killE .replace false y Ey, by simp [A1.kill, hy],
        fun hr => by rw [killE_mode] at hr; exact hr⟩ (fun hl' => by simp at hl')
    refine ⟨hwf, fun x => ?_, fun x E1 h1 => ?_, fun _ hn r hr => ?_⟩
    · by_cases hxy : x = y
      · subst hxy; simp [A1.setE, hy]
      · simp only [A1.setE, upd_ne _ _ hxy]; exact kill_dom ..
    · by_cases hxy : x = y
      · subst hxy; simp only [A1.setE, upd_same, Option.some.injEq] at h1; subst h1; exact ⟨Ey, hy, rfl⟩
      · simp only [A1.setE, upd_ne _ _ hxy] at h1
        obtain ⟨E0, h0, hm0, _⟩ := kill_cmode h1; exact ⟨E0, h0, hm0⟩
    · have hr' : r ∈ roots Ey.held := by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr
      have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := by rcases hn with h' | h' <;> simp_all
      obtain ⟨Er, hEr, hro⟩ := hheld y Ey hy hl hn' r hr'
      by_cases hry : r = y
      · subst hry; exact ⟨{ Ey with live := false }, by simp [A1.setE], by rw [hm]; rfl⟩
      · obtain ⟨E', h', hro'⟩ := kill_root (e := .replace) (hv := false) (y := y) hEr hro
        exact ⟨E', by simp only [A1.setE, upd_ne _ _ hry]; exact h', hro'⟩
  | @copyRoot y Ey hy hl hm =>
    refine ⟨h, fun _ => rfl, same, fun _ hn => ?_⟩
    have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inr hm
    rw [bor_vdeps _ rfl]
    exact app _ _ (hderive y Ey .self hy hl hn') (hheld y Ey hy hl hn')
  | @copyBor y Ey hy hl hm =>
    exact ⟨h, fun _ => rfl, same, fun _ hn r hr => h y _ hy hl hn r hr⟩
  | @borrow y Ey t hy hl ht =>
    refine ⟨h, fun _ => rfl, same, fun _ _ => ?_⟩
    have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [ht]; simp)
    rw [bor_vdeps _ rfl]
    exact app _ _ (hderive y Ey .self hy hl hn') (hheld y Ey hy hl hn')
  | @«at» y i Ey t hy hl ht _ =>
    refine ⟨h, fun _ => rfl, same, fun _ hn => ?_⟩
    have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [ht]; simp)
    rw [bor_vdeps _ (elemE_mode ..)]
    cases t with
    | int => simp [elemE, intE] at hn
    | slice s => exact app _ _ (hheld y Ey hy hl hn') (hheld y Ey hy hl hn')
    | vec s => exact app _ _ (hderive y Ey .inner hy hl hn') (hheld y Ey hy hl hn')
  | @view y Ey t hy hl ht _ =>
    refine ⟨h, fun _ => rfl, same, fun _ _ => ?_⟩
    have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [ht]; simp)
    rw [bor_vdeps _ rfl]
    exact app _ _ (hderive y Ey .view hy hl hn') (hheld y Ey hy hl hn')
  | @sat y i Ey t hy hl ht _ =>
    refine ⟨h, fun _ => rfl, same, fun _ hn => ?_⟩
    have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [ht]; simp)
    rw [bor_vdeps _ (elemE_mode ..)]
    cases t with
    | int => simp [elemE, intE] at hn
    | slice s => exact app _ _ (hheld y Ey hy hl hn') (hheld y Ey hy hl hn')
    | vec s => exact app _ _ (hderive y Ey .inner hy hl hn') (hheld y Ey hy hl hn')
  | @pop y Ey t hy hl ht _ _ =>
    have hwf := h.kill .drop t.holdsView y
    refine ⟨hwf, fun x => kill_dom .., fun x E1 h1 => ?_, fun _ hn r hr => ?_⟩
    · obtain ⟨E0, h0, hm0, _⟩ := kill_cmode h1; exact ⟨E0, h0, hm0⟩
    · have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [ht]; simp)
      have hr' : r ∈ roots Ey.held := by
        cases t with
        | int => simp [popE, elemE, intE] at hn
        | slice s => simpa [popE, elemE, roots, Entry.vdeps, Mode.ownSlot] using hr
        | vec s => simpa [popE, roots, Entry.vdeps, Mode.ownSlot] using hr
      obtain ⟨Er, hEr, hro⟩ := hheld y Ey hy hl hn' r hr'
      exact kill_root hEr hro

end A1

namespace A1

/-- Bindings keep their domain and their mode. -/
def DomMode (Γ0 Γ : Ctx) : Prop :=
  (∀ x, (Γ x).isSome = (Γ0 x).isSome) ∧ ∀ x E, Γ x = some E → ∃ E0, Γ0 x = some E0 ∧ E.mode = E0.mode

theorem DomMode.root {Γ0 Γ : Ctx} (h : DomMode Γ0 Γ) {r : Var}
    (hr : ∃ Er, Γ0 r = some Er ∧ Er.mode.isRoot = true) : ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
  obtain ⟨Er, hEr, hro⟩ := hr
  have := h.1 r; rw [hEr] at this
  cases hE : Γ r with
  | none => rw [hE] at this; cases this
  | some E => obtain ⟨E0, h0, hm⟩ := h.2 r E hE; rw [hEr] at h0; cases h0; exact ⟨E, rfl, hm ▸ hro⟩

theorem DomMode.kill {Γ0 Γ : Ctx} (h : DomMode Γ0 Γ) (e : Eff) (hv : Bool) (x : Var) :
    DomMode Γ0 (A1.kill e hv x Γ) := by
  refine ⟨fun y => by rw [kill_dom]; exact h.1 y, fun y E hy => ?_⟩
  obtain ⟨E1, h1, hm1, _⟩ := kill_cmode hy
  obtain ⟨E0, h0, hm0⟩ := h.2 y E1 h1
  exact ⟨E0, h0, hm1.trans hm0⟩

theorem DomMode.setE {Γ0 Γ : Ctx} (h : DomMode Γ0 Γ) {x : Var} {E : Entry}
    (hx : ∃ E0, Γ0 x = some E0 ∧ E.mode = E0.mode) : DomMode Γ0 (A1.setE Γ x E) := by
  obtain ⟨E0, h0, hm⟩ := hx
  refine ⟨fun y => ?_, fun y E' hy => ?_⟩
  · by_cases hyx : y = x
    · subst hyx; simp [A1.setE, h0]
    · simp only [A1.setE, upd_ne _ _ hyx]; exact h.1 y
  · by_cases hyx : y = x
    · subst hyx; simp only [A1.setE, upd_same, Option.some.injEq] at hy; subst hy; exact ⟨E0, h0, hm⟩
    · simp only [A1.setE, upd_ne _ _ hyx] at hy; exact h.2 y E' hy

theorem DomMode.refl (Γ : Ctx) : DomMode Γ Γ := ⟨fun _ => rfl, fun _ E h => ⟨E, h, rfl⟩⟩

theorem callPostAux_wf {Γ0 : Ctx} {fn : Fn} {args : List Var}
    (hroots : ∀ r ∈ roots (heldOfArgs Γ0 args), ∃ Er, Γ0 r = some Er ∧ Er.mode.isRoot = true)
    (hout : ∀ i, ∀ r ∈ roots (outHeld Γ0 fn args i), ∃ Er, Γ0 r = some Er ∧ Er.mode.isRoot = true) :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ a ∈ as, ∃ E0, Γ0 a = some E0 ∧ ((E0.ty ≠ .int ∨ E0.mode = .rootb) → ∀ r ∈ roots E0.vdeps,
        ∃ Er, Γ0 r = some Er ∧ Er.mode.isRoot = true)) →
      (∀ (j : Nat) (b : Eff) (t : Ty) (a : Var), ps[j]? = some (PMode.inout b, t) → as[j]? = some a →
        (argE Γ0 a).mode.isRoot = true) →
      CtxWF Γ → DomMode Γ0 Γ →
      CtxWF (callPostAux Γ0 fn args ps as i Γ) ∧ DomMode Γ0 (callPostAux Γ0 fn args ps as i Γ) := by
  intro ps
  induction ps with
  | nil => intro as i Γ _ _ hw hd; cases as <;> exact ⟨hw, hd⟩
  | cons p ps ih =>
    intro as i Γ has hio hw hd
    obtain ⟨pm, t⟩ := p
    cases as with
    | nil => cases pm <;> exact ⟨hw, hd⟩
    | cons a as =>
      obtain ⟨E0, h0, hheld⟩ := has a (by simp)
      have has' : ∀ a' ∈ as, _ := fun a' h' => has a' (by simp [h'])
      have hio' : ∀ (j : Nat) (b : Eff) (t : Ty) (a' : Var), ps[j]? = some (PMode.inout b, t) →
          as[j]? = some a' → (argE Γ0 a').mode.isRoot = true :=
        fun j b t a' h1 h2 => hio (j + 1) b t a' (by simpa using h1) (by simpa using h2)
      have hargE : argE Γ0 a = E0 := by unfold argE; rw [h0]; rfl
      cases pm with
      | inp => exact ih as (i + 1) Γ has' hio' hw hd
      | sink =>
        refine ih as (i + 1) _ has' hio' ?_ ?_
        · have hdk := hd.kill .replace false a
          have hsome : ((A1.kill .replace false a Γ) a).isSome := by rw [hdk.1 a, h0]; rfl
          obtain ⟨Ex, hEx⟩ := Option.isSome_iff_exists.mp hsome
          obtain ⟨E0', h0', hm'⟩ := hdk.2 a Ex hEx
          rw [h0] at h0'; cases h0'
          refine (hw.kill .replace false a).setE ⟨Ex, hEx, fun h => ?_⟩ (fun hl => by simp at hl)
          show (argE Γ0 a).mode.isRoot = true
          rw [hargE, ← hm']; exact h
        · exact (hd.kill .replace false a).setE ⟨E0, h0, by rw [hargE]⟩
      | inout b =>
        have hroot : E0.mode.isRoot = true := by
          have := hio 0 b t a (by simp) (by simp); rwa [hargE] at this
        refine ih as (i + 1) _ has' hio' ?_ ?_
        · have hdk := hd.kill b t.elem.holdsView a
          obtain ⟨Ea, hEa, hra⟩ := hdk.root ⟨E0, h0, hroot⟩
          refine (hw.kill b t.elem.holdsView a).setE ⟨Ea, hEa, fun _ => by rw [hargE]; exact hroot⟩ ?_
          intro hl hn r hr
          by_cases hra' : r = a
          · exact Or.inl ⟨hra', by rw [hargE]; exact hroot⟩
          · refine Or.inr ⟨hra', hdk.root ?_⟩
            rw [hargE] at hr hn
            have hn0 : E0.ty ≠ .int ∨ E0.mode = .rootb := hn
            have key : r ∈ roots E0.vdeps ∨ r ∈ roots (outHeld Γ0 fn args i) ∨
                r ∈ roots (heldOfArgs Γ0 args) := by
              simp only [Entry.vdeps, roots, List.map_append, List.mem_append] at hr ⊢
              grind
            rcases key with h | h | h
            · exact hheld hn0 r h
            · exact hout i r h
            · exact hroots r h
        · exact (hd.kill b t.elem.holdsView a).setE ⟨E0, h0, by rw [hargE]⟩

end A1

namespace A1

theorem derive_roots {Γ : Ctx} (h : CtxWF Γ) {y : Var} {Ey : Entry} (hy : Γ y = some Ey)
    (hl : Ey.live = true) (hn : Ey.ty ≠ .int ∨ Ey.mode = .rootb) (k : Kind) :
    ∀ r ∈ roots (derive y Ey k), ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
  intro r hr
  unfold derive at hr
  cases hrt : Ey.mode.isRoot with
  | true =>
    simp only [hrt, ↓reduceIte, roots, List.map_cons, List.map_nil, List.mem_singleton] at hr
    subst hr; exact ⟨Ey, hy, hrt⟩
  | false =>
    simp only [hrt, Bool.false_eq_true, ↓reduceIte, roots, List.map_map, List.mem_map,
      Function.comp] at hr
    obtain ⟨dep, hd, rfl⟩ := hr
    have hos : Ey.mode.ownSlot = false := by
      cases hm : Ey.mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
    exact h y Ey hy hl hn dep.root (by simp [roots, Entry.vdeps, hos, List.mem_map_of_mem hd])

theorem roots_allKinds {rs : List Var} {r : Var} (h : r ∈ roots (allKinds rs)) : r ∈ rs := by
  simp only [roots, allKinds, List.mem_map, List.mem_flatMap, List.mem_cons,
    List.not_mem_nil, or_false] at h
  obtain ⟨d, ⟨r', hr', hd⟩, rfl⟩ := h
  rcases hd with rfl | rfl | rfl <;> exact hr'

theorem mem_args {args : List Var} {a : Var} (h : a ∈ args) : ∃ i < args.length, args.getD i 0 = a := by
  obtain ⟨i, hi, he⟩ := List.getElem_of_mem h
  exact ⟨i, hi, by simp [List.getD, hi, he]⟩

/-- What a call checked against a summary produces is well-formed. -/
theorem CallT.wf {P : Prog} (hP : ProgOK P) {Γ Γ1 : Ctx} {F : List Var} {f : Nat} {args : List Var}
    {E : Entry} (hc : CallT P Γ F f args E Γ1) (h : CtxWF Γ) :
    CtxWF Γ1 ∧ DomMode Γ Γ1 ∧ (∀ r ∈ roots E.vdeps, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true) := by
  obtain ⟨fn, hf, hlen, hargs, rfl, rfl⟩ := hc
  have hfn : FnOK P fn := hP fn (List.mem_of_getElem? hf)
  obtain ⟨_, _, _, _, _, _, hlends, hrholds, houts, _⟩ := hfn
  have hent : ∀ j < fn.params.length, ∃ Ea, Γ (args.getD j 0) = some Ea ∧ Ea.live = true := by
    intro j hj; obtain ⟨Ea, h1, h2, _⟩ := hargs j hj; exact ⟨Ea, h1, h2⟩
  have hargDeps : ∀ jk : Nat × Kind, jk.1 < fn.params.length →
      ∀ r ∈ roots (argDeps Γ args jk), ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
    intro jk hj r hr
    obtain ⟨Ea, hEa, hl⟩ := hent jk.1 hj
    unfold argDeps at hr
    have hae : argE Γ (args.getD jk.1 0) = Ea := by unfold argE; rw [hEa]; rfl
    rw [hae] at hr
    split at hr
    · simp [roots] at hr
    · rename_i hn; exact derive_roots h hEa hl (Or.inl hn) _ r hr
  have hheld : ∀ r ∈ roots (heldOfArgs Γ args), ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
    intro r hr
    have := roots_allKinds hr
    simp only [List.mem_flatMap] at this
    obtain ⟨a, ha, hra⟩ := this
    obtain ⟨i, hi, rfl⟩ := mem_args ha
    obtain ⟨Ea, hEa, hl⟩ := hent i (hlen ▸ hi)
    have hae : argE Γ (args.getD i 0) = Ea := by unfold argE; rw [hEa]; rfl
    rw [hae] at hra
    split at hra
    · simp at hra
    · rename_i hn
      exact h _ Ea hEa hl (Or.inl hn) r (by
        simp only [roots, Entry.vdeps, List.map_append, List.mem_append] at hra ⊢; exact Or.inr hra)
  have hout : ∀ i, ∀ r ∈ roots (outHeld Γ fn args i), ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
    intro i r hr
    simp only [outHeld, roots, List.mem_map, List.mem_flatMap, List.mem_filter] at hr
    obtain ⟨d, ⟨o, ⟨ho, _⟩, hd⟩, rfl⟩ := hr
    obtain ⟨hj, _⟩ := houts o ho
    exact hargDeps _ hj d.root (List.mem_map_of_mem hd)
  have hpost := callPostAux_wf (fn := fn) (args := args) hheld hout fn.params args 0 Γ
    (fun a ha => by
      obtain ⟨i, hi, rfl⟩ := mem_args ha
      obtain ⟨Ea, hEa, hl⟩ := hent i (hlen ▸ hi)
      exact ⟨Ea, hEa, fun hn => h _ Ea hEa hl hn⟩)
    (fun j b t a hp ha => by
      have hj : j < fn.params.length := (List.getElem?_eq_some_iff.mp hp).1
      obtain ⟨Ea, hEa, _, hok, _⟩ := hargs j hj
      have hgd : args.getD j 0 = a := by simp [List.getD, ha]
      have hpj : fn.params[j] = (.inout b, t) := (List.getElem?_eq_some_iff.mp hp).2
      rw [hgd] at hEa
      have hae : argE Γ a = Ea := by unfold argE; rw [hEa]; rfl
      rw [hae]
      simp only [hpj] at hok
      obtain ⟨_, hcan, _⟩ := hok
      rcases hcan with h' | ⟨b', h', _⟩ <;> rw [h'] <;> rfl)
    h (DomMode.refl Γ)
  refine ⟨hpost.1, hpost.2, fun r hr => hpost.2.root ?_⟩
  have hlist : ∀ (l : List (Nat × Kind)), (∀ jk ∈ l, lendable fn jk.1) →
      ∀ r ∈ roots (l.flatMap (argDeps Γ args)), ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
    intro l hl r hr
    simp only [roots, List.mem_map, List.mem_flatMap] at hr
    obtain ⟨d, ⟨jk, hjk, hd⟩, rfl⟩ := hr
    exact hargDeps jk (hl jk hjk).1 d.root (List.mem_map_of_mem hd)
  have key : r ∈ roots (fn.lends.flatMap (argDeps Γ args)) ∨ r ∈ roots (heldOfArgs Γ args) ∨
      r ∈ roots (fn.rholds.flatMap (argDeps Γ args)) := by
    unfold callRes Entry.vdeps at hr
    simp only [roots, List.map_append, List.mem_append] at hr ⊢
    split at hr <;> simp at hr <;> grind
  rcases key with h' | h' | h'
  · exact hlist _ hlends r h'
  · exact hheld r h'
  · exact hlist _ hrholds r h'

end A1

namespace A1

theorem exitScope_none {Γ : Ctx} {x : Var} : exitScope x Γ x = none := by simp [exitScope]

theorem DomMode.trans {Γ1 Γ2 Γ3 : Ctx} (h1 : DomMode Γ1 Γ2) (h2 : DomMode Γ2 Γ3) : DomMode Γ1 Γ3 := by
  refine ⟨fun x => (h2.1 x).trans (h1.1 x), fun x E h => ?_⟩
  obtain ⟨E2, h2', hm2⟩ := h2.2 x E h
  obtain ⟨E1, h1', hm1⟩ := h1.2 x E2 h2'
  exact ⟨E1, h1', hm2.trans hm1⟩

theorem DomMode.get {Γ0 Γ : Ctx} (h : DomMode Γ0 Γ) {r : Var} {E : Entry} (hr : Γ0 r = some E) :
    ∃ E', Γ r = some E' ∧ E'.mode = E.mode := by
  have := h.1 r; rw [hr] at this
  cases hE : Γ r with
  | none => rw [hE] at this; cases this
  | some E' => obtain ⟨E0, h0, hm⟩ := h.2 r E' hE; rw [hr] at h0; cases h0; exact ⟨E', rfl, hm⟩

theorem RhsT.domMode {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1) :
    DomMode Γ Γ1 := by
  cases hr with
  | @moveOwn y Ey hy _ _ _ =>
    exact (DomMode.refl Γ |>.kill .replace false y).setE ⟨Ey, hy, rfl⟩
  | pop _ _ _ _ _ => exact (DomMode.refl Γ).kill _ _ _
  | _ => exact DomMode.refl Γ

theorem callPostAux_domMode {Γ0 : Ctx} {fn : Fn} {args : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ a ∈ as, ∃ E0, Γ0 a = some E0) → DomMode Γ0 Γ →
      DomMode Γ0 (callPostAux Γ0 fn args ps as i Γ) := by
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
      | sink => exact ih as (i + 1) _ has' ((hd.kill _ _ _).setE ⟨E0, h0, by rw [hargE]⟩)
      | inout b => exact ih as (i + 1) _ has' ((hd.kill _ _ _).setE ⟨E0, h0, by rw [hargE]⟩)

theorem CallT.domMode {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {f : Nat} {args : List Var}
    {E : Entry} (hc : CallT P Γ F f args E Γ1) : DomMode Γ Γ1 := by
  obtain ⟨fn, _, hlen, hargs, _, rfl⟩ := hc
  refine callPostAux_domMode _ _ _ _ (fun a ha => ?_) (DomMode.refl Γ)
  obtain ⟨i, hi, rfl⟩ := mem_args ha
  obtain ⟨Ea, hEa, _⟩ := hargs i (hlen ▸ hi)
  exact ⟨Ea, hEa⟩

theorem PushArg.domMode {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hy : Γ y = some Ey) (hp : PushArg Γ F y Ey t D Γ1) : DomMode Γ Γ1 := by
  cases hp with
  | move _ _ => exact (DomMode.refl Γ |>.kill .replace false y).setE ⟨Ey, hy, rfl⟩
  | int => exact DomMode.refl Γ
  | slice _ => exact DomMode.refl Γ

theorem DomMode.exitScope {Γ0 Γ : Ctx} (h : DomMode Γ0 Γ) {x : Var} {r : Var} (hrx : r ≠ x)
    {E : Entry} (hr : Γ0 r = some E) : ∃ E', exitScope x Γ r = some E' ∧ E'.mode = E.mode := by
  obtain ⟨E', h', hm⟩ := h.get hr
  exact ⟨killE .replace false x E', by simp [A1.exitScope, upd_ne _ _ hrx, A1.kill, h'],
    by rw [killE_mode, hm]⟩

/-- A frozen binding stays bound, with its mode, through any derivation. -/
theorem StmtT.keepF {P : Prog} {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P Γ F s Δ) : ∀ r ∈ F, ∀ E, Γ r = some E → ∃ E', Δ r = some E' ∧ E'.mode = E.mode := by
  induction ht with
  | skip => exact fun r _ E h => ⟨E, h, rfl⟩
  | seq _ _ _ iha ihb =>
    intro r hr E h
    obtain ⟨E1, h1, hm1⟩ := iha r hr E h
    obtain ⟨E2, h2, hm2⟩ := ihb r hr E1 h1
    exact ⟨E2, h2, hm2.trans hm1⟩
  | @letv Γ Γ1 Δ F x r0 k E0 _ hx hxF hrh _ ih =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    obtain ⟨E1, h1, hm1⟩ := hrh.domMode.get h
    obtain ⟨E2, h2, hm2⟩ := ih r hr E1 (by simp [A1.setE, upd_ne _ _ hrx, h1])
    exact ⟨killE .replace false x E2, by simp [A1.exitScope, upd_ne _ _ hrx, A1.kill, h2],
      by rw [killE_mode, hm2, hm1]⟩
  | @letcall Γ Γ1 Δ F x f args k E0 _ hx hxF hc _ ih =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    obtain ⟨E1, h1, hm1⟩ := hc.domMode.get h
    obtain ⟨E2, h2, hm2⟩ := ih r hr E1 (by simp [A1.setE, upd_ne _ _ hrx, h1])
    exact ⟨killE .replace false x E2, by simp [A1.exitScope, upd_ne _ _ hrx, A1.kill, h2],
      by rw [killE_mode, hm2, hm1]⟩
  | @scope Γ Δ F x k _ hxF _ ih =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    obtain ⟨E2, h2, hm2⟩ := ih r hr E h
    exact ⟨killE .replace false x E2, by simp [A1.exitScope, upd_ne _ _ hrx, A1.kill, h2],
      by rw [killE_mode, hm2]⟩
  | @rbind Γ Δ F p k Ep _ _ _ _ hpF _ ih =>
    intro r hr E h
    have hrp : r ≠ p := fun e => hpF (e ▸ hr)
    obtain ⟨E2, h2, hm2⟩ := ih r hr E h
    exact ⟨rerootE p Ep.path E2, by simp [A1.exitRoot, upd_ne _ _ hrp, h2], by simp [rerootE, hm2]⟩
  | frozen _ ih => exact fun r hr E h => ih r (List.mem_append_left _ hr) E h
  | @assign Γ Γ1 F x r0 Ex E0 _ hxF _ hrh _ _ _ =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    obtain ⟨E1, h1, hm1⟩ := hrh.domMode.get h
    exact ⟨killE .replace false x E1, by simp [A1.setE, upd_ne _ _ hrx, A1.kill, h1],
      by rw [killE_mode, hm1]⟩
  | ite _ _ _ _ _ iha _ => exact iha
  | «while» _ _ _ _ => exact fun r _ E h => ⟨E, h, rfl⟩
  | @push Γ Γ1 F x y Ex Ey Ex1 t D _ _ _ _ hxF hy _ _ _ hpa _ _ _ =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    obtain ⟨E1, h1, hm1⟩ := (hpa.domMode hy).get h
    exact ⟨killE .realloc t.holdsView x E1, by simp [A1.setE, upd_ne _ _ hrx, A1.kill, h1],
      by rw [killE_mode, hm1]⟩
  | @free Γ F x E0 t _ _ _ _ hxF =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    exact ⟨killE .replace false x E, by simp [A1.setE, upd_ne _ _ hrx, A1.kill, h], by rw [killE_mode]⟩
  | sub hw _ ho ih =>
    intro r hr E h
    obtain ⟨E0, h0, hw0⟩ := hw.get h
    obtain ⟨E1, h1, hm1⟩ := ih r hr E0 h0
    rcases ho with rfl | ho
    · exact ⟨E1, h1, hm1.trans hw0.2.1⟩
    · obtain ⟨E2, h2, hw2⟩ := ho.get h1
      exact ⟨E2, h2, hw2.2.1.trans (hm1.trans hw0.2.1)⟩

/-- Every rule keeps a well-formed context well-formed. -/
theorem StmtT.wf {P : Prog} (hP : ProgOK P) {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P Γ F s Δ) : CtxWF Γ → CtxWF Δ := by
  induction ht with
  | skip => exact id
  | seq _ _ _ iha ihb => exact fun h => ihb (iha h)
  | @letv Γ Γ1 Δ F x r k E _ hx _ hr _ ih =>
    intro h
    obtain ⟨hw1, hdom, _, hE⟩ := hr.wf h
    have hx1 : Γ1 x = none := by have := hdom x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    exact (ih (hw1.add hx1 hE)).exitScope x
  | @letcall Γ Γ1 Δ F x f args k E _ hx _ hc _ ih =>
    intro h
    obtain ⟨hw1, hdm, hE⟩ := hc.wf hP h
    have hx1 : Γ1 x = none := by have := hdm.1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    exact (ih (hw1.add hx1 (fun _ _ => hE))).exitScope x
  | scope _ _ _ ih => exact fun h => (ih h).exitScope _
  | @rbind Γ Δ F p k E hp hm hl hroots hpF hk ih =>
    intro h
    have hos : E.mode.ownSlot = false := by rw [hm]; rfl
    refine (ih h).exitRoot p E.path fun d hd => ?_
    have hdv : d.root ∈ roots E.vdeps := by
      simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.map_append,
        List.mem_append, List.mem_map]
      exact Or.inl ⟨d, hd, rfl⟩
    have hF := hroots d.root hdv
    refine ⟨fun e => hpF (e ▸ hF), ?_⟩
    obtain ⟨Er, hEr, hro⟩ := h p E hp hl (Or.inr hm) d.root hdv
    obtain ⟨E', h', hm'⟩ := hk.keepF d.root hF Er hEr
    exact ⟨E', h', by rw [hm']; exact hro⟩
  | frozen _ ih => exact ih
  | @assign Γ Γ1 F x r Ex E hx _ hmodes hr _ hxd _ =>
    intro h
    obtain ⟨hw1, hdom, hmode, hE⟩ := hr.wf h
    have hos : Ex.mode.ownSlot = E.mode.ownSlot := by
      rcases hmodes with ⟨h1, h2⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rw [h1, h2] <;> rfl
    have hsome : (A1.kill .replace false x Γ1 x).isSome := by rw [kill_dom, hdom, hx]; rfl
    obtain ⟨Ex1, hEx1⟩ := Option.isSome_iff_exists.mp hsome
    refine (hw1.kill .replace false x).setE ⟨Ex1, hEx1, fun hro => ?_⟩ (fun hl hn r hr' => Or.inr ?_)
    · obtain ⟨E1, h1, hm1, _⟩ := kill_cmode hEx1
      obtain ⟨E0, h0, hm0⟩ := hmode x E1 h1
      rw [hx] at h0; cases h0
      show Ex.mode.isRoot = true
      rw [← hm0, ← hm1]; exact hro
    · have hvd : ({ E with mode := Ex.mode } : Entry).vdeps = E.vdeps := by simp [Entry.vdeps, hos]
      rw [hvd] at hr'
      have hn' : E.ty ≠ .int ∨ E.mode = .rootb := by
        rcases hn with h' | h'
        · exact Or.inl h'
        · simp at h'; rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩ <;> rw [h1] at h' <;> cases h'
      obtain ⟨Er, hEr, hro⟩ := hE hl hn' r hr'
      exact ⟨fun h => hxd (h ▸ hr'), kill_root hEr hro⟩
  | ite _ _ _ _ _ iha _ => exact iha
  | «while» _ _ _ _ => exact id
  | @push Γ Γ1 F x y Ex Ey Ex1 t D hx hl hty hcan hxF hy hly htyy hyx hpa hxD hx1 hl1 =>
    intro h
    have hdm := hpa.domMode hy
    -- the context after taking the value, the entry of `x` in it, and what `D` depends on
    have pre : CtxWF Γ1 ∧ Ex1.ty = Ex.ty ∧ ∀ r ∈ roots D, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true := by
      cases hpa with
      | @move s hm hyF =>
        have hxy : x ≠ y := fun e => hyx e.symm
        simp only [A1.setE, upd_ne _ _ hxy, A1.kill, hx, Option.map_some, Option.some.injEq] at hx1
        subst hx1
        refine ⟨(h.kill .replace false y).setE ⟨killE .replace false y Ey, by simp [A1.kill, hy],
          fun hr => by rw [killE_mode] at hr; exact hr⟩ (fun hl' => by simp at hl'), killE_ty .., ?_⟩
        intro r hr
        have hn : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [htyy]; simp)
        exact hdm.root (h y Ey hy hly hn r (by
          simp only [roots, Entry.vdeps, List.map_append, List.mem_append] at hr ⊢; exact Or.inr hr))
      | int => exact ⟨h, by rw [hx] at hx1; cases hx1; rfl, fun r hr => by simp [roots] at hr⟩
      | @slice s hm =>
        refine ⟨h, by rw [hx] at hx1; cases hx1; rfl, ?_⟩
        have hn : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [htyy]; simp)
        refine wf_append (derive_roots h hy hly hn _) ?_
        intro r hr
        exact h y Ey hy hly hn r (by
          simp only [roots, Entry.vdeps, List.map_append, List.mem_append] at hr ⊢; exact Or.inr hr)
    obtain ⟨hw1, hty1, hD⟩ := pre
    have hroot : Ex1.mode.isRoot = true := by
      obtain ⟨E0, h0, hm0⟩ := hdm.2 x Ex1 hx1
      rw [hx] at h0; cases h0
      rw [hm0]; rcases hcan with h' | ⟨b, h', _⟩ <;> rw [h'] <;> rfl
    have hos : Ex1.mode.ownSlot = true := by
      obtain ⟨E0, h0, hm0⟩ := hdm.2 x Ex1 hx1
      rw [hx] at h0; cases h0
      rw [hm0]; rcases hcan with h' | ⟨b, h', _⟩ <;> rw [h'] <;> rfl
    refine (hw1.kill .realloc t.holdsView x).setE ⟨killE .realloc t.holdsView x Ex1,
      by simp [A1.kill, hx1], fun _ => hroot⟩ (fun hl' hn r hr => ?_)
    by_cases hrx : r = x
    · exact Or.inl ⟨hrx, hroot⟩
    · refine Or.inr ⟨hrx, ?_⟩
      simp only [roots, Entry.vdeps, hos, ↓reduceIte, List.nil_append, List.map_append,
        List.mem_append] at hr
      have hnint : Ex1.ty ≠ .int := by rw [hty1, hty]; simp
      rcases hr with hr | hr
      · obtain ⟨Er, hEr, hro⟩ := hw1 x Ex1 hx1 hl1 (Or.inl hnint) r (by
          simp [roots, Entry.vdeps, hos, hr])
        exact kill_root hEr hro
      · obtain ⟨Er, hEr, hro⟩ := hD r hr
        exact kill_root hEr hro
  | @free Γ F x E t hx hl hm hty hxF =>
    intro h
    exact (h.kill .replace false x).setE ⟨killE .replace false x E, by simp [A1.kill, hx],
      fun hr => by rw [killE_mode] at hr; exact hr⟩ (fun hl' => by simp at hl')
  | sub hw _ ho _ =>
    intro _
    rcases ho with rfl | ho
    · exact ‹CtxWF _ → CtxWF _› hw.wf
    · exact ho.wf

end A1
