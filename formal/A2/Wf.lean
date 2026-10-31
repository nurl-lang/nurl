import A2.Progress

/-! A2 — the rules keep contexts well-formed: live entries depend only on
roots the context has. -/

namespace A2

theorem CtxWF.setE {Γ : Ctx} (h : CtxWF Γ) {x : Var} {E : Entry} (hx : ∃ Ex, Γ x = some Ex ∧
    (Ex.mode.isRoot = true → E.mode.isRoot = true))
    (hE : E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → ∀ r ∈ roots E.vdeps,
      (r = x ∧ E.mode.isRoot = true) ∨ (r ≠ x ∧ ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true)) :
    CtxWF (A2.setE Γ x E) := by
  obtain ⟨Ex, hEx, hrt⟩ := hx
  have hroot : ∀ r, (∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) →
      ∃ Er, A2.setE Γ x E r = some Er ∧ Er.mode.isRoot = true := by
    intro r ⟨Er, hEr, hro⟩
    by_cases hrx : r = x
    · subst hrx; rw [hEx] at hEr; cases hEr; exact ⟨E, by simp [A2.setE], hrt hro⟩
    · exact ⟨Er, by simp [A2.setE, upd_ne _ _ hrx, hEr], hro⟩
  intro v E' hv hl hn r hr
  by_cases hvx : v = x
  · subst hvx
    simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv
    rcases hE hl hn r hr with ⟨rfl, hro⟩ | ⟨_, hex⟩
    · exact ⟨_, by simp [A2.setE], hro⟩
    · exact hroot r hex
  · simp only [A2.setE, upd_ne _ _ hvx] at hv
    exact hroot r (h v E' hv hl hn r hr)

/-- A fresh binding. -/
theorem CtxWF.add {Γ : Ctx} (h : CtxWF Γ) {x : Var} (hx : Γ x = none) {E : Entry}
    (hE : E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → ∀ r ∈ roots E.vdeps,
      ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) : CtxWF (A2.setE Γ x E) := by
  have hroot : ∀ r, (∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) →
      ∃ Er, A2.setE Γ x E r = some Er ∧ Er.mode.isRoot = true := by
    intro r ⟨Er, hEr, hro⟩
    have hrx : r ≠ x := fun h => by subst h; rw [hx] at hEr; cases hEr
    exact ⟨Er, by simp [A2.setE, upd_ne _ _ hrx, hEr], hro⟩
  intro v E' hv hl hn r hr
  by_cases hvx : v = x
  · subst hvx
    simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv
    exact hroot r (hE hl hn r hr)
  · simp only [A2.setE, upd_ne _ _ hvx] at hv
    exact hroot r (h v E' hv hl hn r hr)

theorem CtxWF.exitScope {Γ : Ctx} (h : CtxWF Γ) (x : Var) : CtxWF (exitScope x Γ) := by
  intro v E hv' hl hn r hr
  have hvx : v ≠ x := fun e => by subst e; simp [A2.exitScope] at hv'
  simp only [A2.exitScope, upd_ne _ _ hvx] at hv'
  obtain ⟨Er, hEr, hro⟩ := (h.kill .replace false x) v E hv' hl hn r hr
  have hrx : r ≠ x := by
    intro hrx; subst hrx
    obtain ⟨E0, hE0, _, _⟩ := kill_cmode hv'
    simp only [A2.kill, hE0, Option.map_some, Option.some.injEq] at hv'
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
  exact ⟨Er, by simp [A2.exitScope, upd_ne _ _ hrx, hEr], hro⟩

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

/-- What `vec_push` or a struct literal takes from `y`, and what the value
    then holds, depend on roots the context has. -/
theorem PushArg.wf {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hpa : PushArg Γ F y Ey t D Γ1) (h : CtxWF Γ) (hy : Γ y = some Ey) (hl : Ey.live = true)
    (hty : Ey.ty = t) : CtxWF Γ1 ∧ (∀ x, (Γ1 x).isSome = (Γ x).isSome) ∧
      (∀ x E1, Γ1 x = some E1 → ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode) ∧
      ∀ r ∈ roots D, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true := by
  have same : ∀ x E1, Γ x = some E1 → ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode :=
    fun x E1 h => ⟨E1, h, rfl⟩
  cases hpa with
  | move ho hm _ _ =>
    have hn : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (fun h' => by rw [hty] at h'; rw [h'] at ho; cases ho)
    refine ⟨(h.kill .replace false y).setE ⟨killE .replace false y Ey, by simp [A2.kill, hy],
      fun hr => by rw [killE_mode] at hr; exact hr⟩ (fun hl' => by simp at hl'), fun x => ?_,
      fun x E1 h1 => ?_, fun r hr => ?_⟩
    · by_cases hxy : x = y
      · subst hxy; simp [A2.setE, hy]
      · simp only [A2.setE, upd_ne _ _ hxy]; exact kill_dom ..
    · by_cases hxy : x = y
      · subst hxy; simp only [A2.setE, upd_same, Option.some.injEq] at h1; subst h1; exact ⟨Ey, hy, rfl⟩
      · simp only [A2.setE, upd_ne _ _ hxy] at h1
        obtain ⟨E0, h0, hm0, _⟩ := kill_cmode h1; exact ⟨E0, h0, hm0⟩
    · obtain ⟨Er, hEr, hro⟩ := h y Ey hy hl hn r (by
        simp only [roots, Entry.vdeps, List.map_append, List.mem_append] at hr ⊢; exact Or.inr hr)
      by_cases hry : r = y
      · subst hry; exact ⟨{ Ey with live := false }, by simp [A2.setE], by rw [hm]; rfl⟩
      · obtain ⟨E', h', hro'⟩ := kill_root (e := .replace) (hv := false) (y := y) hEr hro
        exact ⟨E', by simp only [A2.setE, upd_ne _ _ hry]; exact h', hro'⟩
  | int => exact ⟨h, fun _ => rfl, same, fun r hr => by simp [roots] at hr⟩
  | slice hm =>
    refine ⟨h, fun _ => rfl, same, ?_⟩
    have hn : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [hty]; simp)
    refine wf_append (derive_roots h hy hl hn _) ?_
    intro r hr
    exact h y Ey hy hl hn r (by
      simp only [roots, Entry.vdeps, List.map_append, List.mem_append] at hr ⊢; exact Or.inr hr)

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
  | @moveOwn y Ey hy hl hm _ _ =>
    have hwf : CtxWF (A2.setE (kill .replace false y Γ) y { Ey with live := false }) :=
      (h.kill .replace false y).setE ⟨killE .replace false y Ey, by simp [A2.kill, hy],
        fun hr => by rw [killE_mode] at hr; exact hr⟩ (fun hl' => by simp at hl')
    refine ⟨hwf, fun x => ?_, fun x E1 h1 => ?_, fun _ hn r hr => ?_⟩
    · by_cases hxy : x = y
      · subst hxy; simp [A2.setE, hy]
      · simp only [A2.setE, upd_ne _ _ hxy]; exact kill_dom ..
    · by_cases hxy : x = y
      · subst hxy; simp only [A2.setE, upd_same, Option.some.injEq] at h1; subst h1; exact ⟨Ey, hy, rfl⟩
      · simp only [A2.setE, upd_ne _ _ hxy] at h1
        obtain ⟨E0, h0, hm0, _⟩ := kill_cmode h1; exact ⟨E0, h0, hm0⟩
    · have hr' : r ∈ roots Ey.held := by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr
      have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := by rcases hn with h' | h' <;> simp_all
      obtain ⟨Er, hEr, hro⟩ := hheld y Ey hy hl hn' r hr'
      by_cases hry : r = y
      · subst hry; exact ⟨{ Ey with live := false }, by simp [A2.setE], by rw [hm]; rfl⟩
      · obtain ⟨E', h', hro'⟩ := kill_root (e := .replace) (hv := false) (y := y) hEr hro
        exact ⟨E', by simp only [A2.setE, upd_ne _ _ hry]; exact h', hro'⟩
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
    | prod a b => exact app _ _ (hderive y Ey .inner hy hl hn') (hheld y Ey hy hl hn')
    | sum a b => exact app _ _ (hderive y Ey .inner hy hl hn') (hheld y Ey hy hl hn')
    | fn ms => exact app _ _ (hderive y Ey .inner hy hl hn') (hheld y Ey hy hl hn')
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
    | prod a b => exact app _ _ (hderive y Ey .inner hy hl hn') (hheld y Ey hy hl hn')
    | sum a b => exact app _ _ (hderive y Ey .inner hy hl hn') (hheld y Ey hy hl hn')
    | fn ms => exact app _ _ (hderive y Ey .inner hy hl hn') (hheld y Ey hy hl hn')
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
        | prod a b => simpa [popE, roots, Entry.vdeps, Mode.ownSlot] using hr
        | sum a b => simpa [popE, roots, Entry.vdeps, Mode.ownSlot] using hr
        | fn ms => simpa [popE, roots, Entry.vdeps, Mode.ownSlot] using hr
      obtain ⟨Er, hEr, hro⟩ := hheld y Ey hy hl hn' r hr'
      exact kill_root hEr hro
  | @pair y z Ey Ez Γ1 Γ2 Dy Dz hy hly hpa1 hz hlz hpa2 _ =>
    obtain ⟨hw1, hd1, hm1, hr1⟩ := hpa1.wf h hy hly rfl
    obtain ⟨hw2, hd2, hm2, hr2⟩ := hpa2.wf hw1 hz hlz rfl
    refine ⟨hw2, fun x => (hd2 x).trans (hd1 x), fun x E1 h1 => ?_, fun _ _ r hr => ?_⟩
    · obtain ⟨E2, h2', hm2'⟩ := hm2 x E1 h1
      obtain ⟨E0, h0, hm0⟩ := hm1 x E2 h2'
      exact ⟨E0, h0, hm2'.trans hm0⟩
    · simp only [roots, Entry.vdeps, Mode.ownSlot, ↓reduceIte, List.nil_append, List.map_append,
        List.mem_append] at hr
      rcases hr with hr | hr
      · obtain ⟨Er, hEr, hro⟩ := hr1 r hr
        have hdr := hd2 r; rw [hEr] at hdr
        obtain ⟨E2, h2'⟩ := Option.isSome_iff_exists.mp hdr
        obtain ⟨E0, h0, hm0⟩ := hm2 r E2 h2'
        rw [hEr] at h0; cases h0
        exact ⟨E2, h2', by rw [hm0]; exact hro⟩
      · exact hr2 r hr
  | @fst y Ey a b hy hl ht =>
    refine ⟨h, fun _ => rfl, same, fun _ hn => ?_⟩
    have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [ht]; simp)
    have hpe : projE y Ey a = ⟨a, .bor, true, projDeps y Ey ++ Ey.held, Ey.held, false⟩ := by
      cases a with
      | int => simp [projE, intE] at hn
      | _ => rfl
    rw [hpe]
    show ∀ r ∈ roots ((projDeps y Ey ++ Ey.held) ++ Ey.held), _
    refine app _ _ (app _ _ ?_ (hheld y Ey hy hl hn')) (hheld y Ey hy hl hn')
    unfold projDeps; split
    · rename_i hos; intro r hr; simp [roots] at hr; subst hr
      exact ⟨Ey, hy, by cases hm : Ey.mode <;> simp_all [Mode.ownSlot, Mode.isRoot]⟩
    · split
      · rename_i hrb; intro r hr; simp [roots] at hr; subst hr
        exact ⟨Ey, hy, by simp_all [Mode.isRoot]⟩
      · rename_i hos _; exact hpath y Ey hy hl hn' (by simpa using hos)
  | @snd y Ey a b hy hl ht =>
    refine ⟨h, fun _ => rfl, same, fun _ hn => ?_⟩
    have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [ht]; simp)
    have hpe : projE y Ey b = ⟨b, .bor, true, projDeps y Ey ++ Ey.held, Ey.held, false⟩ := by
      cases b with
      | int => simp [projE, intE] at hn
      | _ => rfl
    rw [hpe]
    show ∀ r ∈ roots ((projDeps y Ey ++ Ey.held) ++ Ey.held), _
    refine app _ _ (app _ _ ?_ (hheld y Ey hy hl hn')) (hheld y Ey hy hl hn')
    unfold projDeps; split
    · rename_i hos; intro r hr; simp [roots] at hr; subst hr
      exact ⟨Ey, hy, by cases hm : Ey.mode <;> simp_all [Mode.ownSlot, Mode.isRoot]⟩
    · split
      · rename_i hrb; intro r hr; simp [roots] at hr; subst hr
        exact ⟨Ey, hy, by simp_all [Mode.isRoot]⟩
      · rename_i hos _; exact hpath y Ey hy hl hn' (by simpa using hos)

  | @inl y b Ey Γ1 D hy hly hpa _ =>
    obtain ⟨hw1, hd1, hm1, hr1⟩ := hpa.wf h hy hly rfl
    exact ⟨hw1, hd1, hm1, fun _ _ r hr => hr1 r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)⟩
  | @inr a y Ey Γ1 D hy hly hpa _ =>
    obtain ⟨hw1, hd1, hm1, hr1⟩ := hpa.wf h hy hly rfl
    exact ⟨hw1, hd1, hm1, fun _ _ r hr => hr1 r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)⟩
  | @pack fs te ms y cs Ey Γ1 D hy hly hte hpa hcaps =>
    obtain ⟨hw1, hd1, hm1, hr1⟩ := hpa.wf h hy hly hte
    refine ⟨hw1, hd1, hm1, fun _ _ r hr => ?_⟩
    have : r ∈ roots D ∨ r ∈ roots (capDeps cs) := by
      simpa [roots, Entry.vdeps, Mode.ownSlot, List.map_append] using hr
    rcases this with hr | hr
    · exact hr1 r hr
    · obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
      obtain ⟨c, hc, rfl⟩ := capDeps_mem hd
      obtain ⟨Ev, hEv, _, _, ho, _⟩ := hcaps.2 c hc
      exact ⟨Ev, hEv, by cases hm : Ev.mode <;> simp_all [Mode.ownSlot, Mode.isRoot]⟩
  | @getl y Ey a b hy hl ht =>
    refine ⟨h, fun _ => rfl, same, fun _ hn => ?_⟩
    have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [ht]; simp)
    have hpe : projE y Ey a = ⟨a, .bor, true, projDeps y Ey ++ Ey.held, Ey.held, false⟩ := by
      cases a with
      | int => simp [projE, intE] at hn
      | _ => rfl
    rw [hpe]
    show ∀ r ∈ roots ((projDeps y Ey ++ Ey.held) ++ Ey.held), _
    refine app _ _ (app _ _ ?_ (hheld y Ey hy hl hn')) (hheld y Ey hy hl hn')
    unfold projDeps; split
    · rename_i hos; intro r hr; simp [roots] at hr; subst hr
      exact ⟨Ey, hy, by cases hm : Ey.mode <;> simp_all [Mode.ownSlot, Mode.isRoot]⟩
    · split
      · rename_i hrb; intro r hr; simp [roots] at hr; subst hr
        exact ⟨Ey, hy, by simp_all [Mode.isRoot]⟩
      · rename_i hos _; exact hpath y Ey hy hl hn' (by simpa using hos)
  | @getr y Ey a b hy hl ht =>
    refine ⟨h, fun _ => rfl, same, fun _ hn => ?_⟩
    have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [ht]; simp)
    have hpe : projE y Ey b = ⟨b, .bor, true, projDeps y Ey ++ Ey.held, Ey.held, false⟩ := by
      cases b with
      | int => simp [projE, intE] at hn
      | _ => rfl
    rw [hpe]
    show ∀ r ∈ roots ((projDeps y Ey ++ Ey.held) ++ Ey.held), _
    refine app _ _ (app _ _ ?_ (hheld y Ey hy hl hn')) (hheld y Ey hy hl hn')
    unfold projDeps; split
    · rename_i hos; intro r hr; simp [roots] at hr; subst hr
      exact ⟨Ey, hy, by cases hm : Ey.mode <;> simp_all [Mode.ownSlot, Mode.isRoot]⟩
    · split
      · rename_i hrb; intro r hr; simp [roots] at hr; subst hr
        exact ⟨Ey, hy, by simp_all [Mode.isRoot]⟩
      · rename_i hos _; exact hpath y Ey hy hl hn' (by simpa using hos)
  | @takel y Ey a b hy hl hm hty _ _ =>
    have hwf : CtxWF (A2.setE (kill .replace false y Γ) y { Ey with live := false }) :=
      (h.kill .replace false y).setE ⟨killE .replace false y Ey, by simp [A2.kill, hy],
        fun hr => by rw [killE_mode] at hr; exact hr⟩ (fun hl' => by simp at hl')
    refine ⟨hwf, fun x => ?_, fun x E1 h1 => ?_, fun _ hn r hr => ?_⟩
    · by_cases hxy : x = y
      · subst hxy; simp [A2.setE, hy]
      · simp only [A2.setE, upd_ne _ _ hxy]; exact kill_dom ..
    · by_cases hxy : x = y
      · subst hxy; simp only [A2.setE, upd_same, Option.some.injEq] at h1; subst h1; exact ⟨Ey, hy, rfl⟩
      · simp only [A2.setE, upd_ne _ _ hxy] at h1
        obtain ⟨E0, h0, hm0, _⟩ := kill_cmode h1; exact ⟨E0, h0, hm0⟩
    · have hr' : r ∈ roots Ey.held := by
        cases a with
        | int => simp [compE, intE] at hn
        | slice s =>
          simp only [compE, roots, Entry.vdeps, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte,
            List.map_append, List.mem_append] at hr
          rcases hr with hr | hr <;> exact hr
        | vec s => exact ownHeld_roots (by simpa [compE, Entry.vdeps, Mode.ownSlot] using hr)
        | prod c d => exact ownHeld_roots (by simpa [compE, Entry.vdeps, Mode.ownSlot] using hr)
        | sum c d => exact ownHeld_roots (by simpa [compE, Entry.vdeps, Mode.ownSlot] using hr)
        | fn c => exact ownHeld_roots (by simpa [compE, Entry.vdeps, Mode.ownSlot] using hr)
      have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [hty]; simp)
      obtain ⟨Er, hEr, hro⟩ := hheld y Ey hy hl hn' r hr'
      by_cases hry : r = y
      · subst hry; exact ⟨{ Ey with live := false }, by simp [A2.setE], by rw [hm]; rfl⟩
      · obtain ⟨E', h', hro'⟩ := kill_root (e := .replace) (hv := false) (y := y) hEr hro
        exact ⟨E', by simp only [A2.setE, upd_ne _ _ hry]; exact h', hro'⟩
  | @taker y Ey a b hy hl hm hty _ _ =>
    have hwf : CtxWF (A2.setE (kill .replace false y Γ) y { Ey with live := false }) :=
      (h.kill .replace false y).setE ⟨killE .replace false y Ey, by simp [A2.kill, hy],
        fun hr => by rw [killE_mode] at hr; exact hr⟩ (fun hl' => by simp at hl')
    refine ⟨hwf, fun x => ?_, fun x E1 h1 => ?_, fun _ hn r hr => ?_⟩
    · by_cases hxy : x = y
      · subst hxy; simp [A2.setE, hy]
      · simp only [A2.setE, upd_ne _ _ hxy]; exact kill_dom ..
    · by_cases hxy : x = y
      · subst hxy; simp only [A2.setE, upd_same, Option.some.injEq] at h1; subst h1; exact ⟨Ey, hy, rfl⟩
      · simp only [A2.setE, upd_ne _ _ hxy] at h1
        obtain ⟨E0, h0, hm0, _⟩ := kill_cmode h1; exact ⟨E0, h0, hm0⟩
    · have hr' : r ∈ roots Ey.held := by
        cases b with
        | int => simp [compE, intE] at hn
        | slice s =>
          simp only [compE, roots, Entry.vdeps, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte,
            List.map_append, List.mem_append] at hr
          rcases hr with hr | hr <;> exact hr
        | vec s => exact ownHeld_roots (by simpa [compE, Entry.vdeps, Mode.ownSlot] using hr)
        | prod c d => exact ownHeld_roots (by simpa [compE, Entry.vdeps, Mode.ownSlot] using hr)
        | sum c d => exact ownHeld_roots (by simpa [compE, Entry.vdeps, Mode.ownSlot] using hr)
        | fn c => exact ownHeld_roots (by simpa [compE, Entry.vdeps, Mode.ownSlot] using hr)
      have hn' : Ey.ty ≠ .int ∨ Ey.mode = .rootb := Or.inl (by rw [hty]; simp)
      obtain ⟨Er, hEr, hro⟩ := hheld y Ey hy hl hn' r hr'
      by_cases hry : r = y
      · subst hry; exact ⟨{ Ey with live := false }, by simp [A2.setE], by rw [hm]; rfl⟩
      · obtain ⟨E', h', hro'⟩ := kill_root (e := .replace) (hv := false) (y := y) hEr hro
        exact ⟨E', by simp only [A2.setE, upd_ne _ _ hry]; exact h', hro'⟩

end A2

namespace A2

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
    DomMode Γ0 (A2.kill e hv x Γ) := by
  refine ⟨fun y => by rw [kill_dom]; exact h.1 y, fun y E hy => ?_⟩
  obtain ⟨E1, h1, hm1, _⟩ := kill_cmode hy
  obtain ⟨E0, h0, hm0⟩ := h.2 y E1 h1
  exact ⟨E0, h0, hm1.trans hm0⟩

theorem DomMode.setE {Γ0 Γ : Ctx} (h : DomMode Γ0 Γ) {x : Var} {E : Entry}
    (hx : ∃ E0, Γ0 x = some E0 ∧ E.mode = E0.mode) : DomMode Γ0 (A2.setE Γ x E) := by
  obtain ⟨E0, h0, hm⟩ := hx
  refine ⟨fun y => ?_, fun y E' hy => ?_⟩
  · by_cases hyx : y = x
    · subst hyx; simp [A2.setE, h0]
    · simp only [A2.setE, upd_ne _ _ hyx]; exact h.1 y
  · by_cases hyx : y = x
    · subst hyx; simp only [A2.setE, upd_same, Option.some.injEq] at hy; subst hy; exact ⟨E0, h0, hm⟩
    · simp only [A2.setE, upd_ne _ _ hyx] at hy; exact h.2 y E' hy

theorem DomMode.refl (Γ : Ctx) : DomMode Γ Γ := ⟨fun _ => rfl, fun _ E h => ⟨E, h, rfl⟩⟩

theorem CtxWF.killNames {Γ : Ctx} (h : CtxWF Γ) : ∀ ds, CtxWF (killNames ds Γ)
  | [] => h
  | _ :: ds => show CtxWF (A2.kill _ _ _ (A2.killNames ds Γ)) from (CtxWF.killNames h ds).kill _ _ _

theorem DomMode.killNames {Γ0 Γ : Ctx} (h : DomMode Γ0 Γ) : ∀ ds, DomMode Γ0 (killNames ds Γ)
  | [] => h
  | _ :: ds => show DomMode Γ0 (A2.kill _ _ _ (A2.killNames ds Γ)) from (DomMode.killNames h ds).kill _ _ _

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
          have hsome : ((A2.kill .replace false a Γ) a).isSome := by rw [hdk.1 a, h0]; rfl
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

end A2

namespace A2

theorem roots_allKinds {rs : List Var} {r : Var} (h : r ∈ roots (allKinds rs)) : r ∈ rs := by
  simp only [roots, allKinds, List.mem_map, List.mem_flatMap, List.mem_cons,
    List.not_mem_nil, or_false] at h
  obtain ⟨d, ⟨r', hr', hd⟩, rfl⟩ := h
  rcases hd with rfl | rfl | rfl <;> exact hr'

theorem mem_args {args : List Var} {a : Var} (h : a ∈ args) : ∃ i < args.length, args.getD i 0 = a := by
  obtain ⟨i, hi, he⟩ := List.getElem_of_mem h
  exact ⟨i, hi, by simp [List.getD, hi, he]⟩

theorem roots_memDeps {ds : List Dep} {r : Var} (h : r ∈ roots (memDeps ds)) : r ∈ roots ds := by
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp h
  exact List.mem_map_of_mem (List.mem_filter.mp hd).1

/-- What a call checked against a summary produces is well-formed. -/
theorem CallT.wf {P : Prog} (hP : ProgOK P) {Γ Γ1 : Ctx} {F : List Var} {f : Nat} {args : List Var}
    {E : Entry} (hc : CallT P Γ F f args E Γ1) (h : CtxWF Γ) :
    CtxWF Γ1 ∧ DomMode Γ Γ1 ∧ (∀ r ∈ roots E.vdeps, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true) := by
  obtain ⟨fn, hf, hlen, hargs, _, rfl, rfl⟩ := hc
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
    simp only [heldOfArgs, roots, List.map_append, List.mem_append] at hr
    rcases hr with hr | hr
    · have := roots_allKinds hr
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
          have hra := roots_memDeps hra
          simp only [roots, Entry.vdeps, List.map_append, List.mem_append] at hra ⊢; exact Or.inr hra)
    · obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
      simp only [argNames, List.mem_flatMap] at hd
      obtain ⟨a, ha, hda⟩ := hd
      obtain ⟨i, hi, rfl⟩ := mem_args ha
      obtain ⟨Ea, hEa, hl⟩ := hent i (hlen ▸ hi)
      have hae : argE Γ (args.getD i 0) = Ea := by unfold argE; rw [hEa]; rfl
      rw [hae] at hda
      split at hda
      · simp at hda
      · rename_i hn
        exact h _ Ea hEa hl (Or.inl hn) d.root (List.mem_map_of_mem (List.mem_filter.mp hda).1)
  have hout : ∀ i, ∀ r ∈ roots (outHeld Γ fn args i), ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
    intro i r hr
    simp only [outHeld, roots, List.mem_map, List.mem_flatMap, List.mem_filter] at hr
    obtain ⟨d, ⟨o, ⟨ho, _⟩, hd⟩, rfl⟩ := hr
    obtain ⟨⟨hj, _⟩, _⟩ := houts o ho
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
  refine ⟨hpost.1.killNames _, hpost.2.killNames _, fun r hr => (hpost.2.killNames _).root ?_⟩
  have hlist : ∀ (l : List (Nat × Kind)), (∀ jk ∈ l, lendable fn jk.1) →
      ∀ r ∈ roots (l.flatMap (argDeps Γ args)), ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
    intro l hl r hr
    simp only [roots, List.mem_map, List.mem_flatMap] at hr
    obtain ⟨d, ⟨jk, hjk, hd⟩, rfl⟩ := hr
    exact hargDeps jk (hl jk hjk).1 d.root (List.mem_map_of_mem hd)
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
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
  rcases hsub d hd with h' | h' | h'
  · exact hlist _ (fun jk h => (hlends jk h).1) _ (List.mem_map_of_mem h')
  · exact hheld _ (List.mem_map_of_mem h')
  · exact hlist _ (fun jk h => (hrholds jk h).1) _ (List.mem_map_of_mem h')

end A2

namespace A2

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
  obtain ⟨fn, _, hlen, hargs, _, _, rfl⟩ := hc
  refine DomMode.killNames (callPostAux_domMode _ _ _ _ (fun a ha => ?_) (DomMode.refl Γ)) _
  obtain ⟨i, hi, rfl⟩ := mem_args ha
  obtain ⟨Ea, hEa, _⟩ := hargs i (hlen ▸ hi)
  exact ⟨Ea, hEa⟩

theorem PushArg.domMode {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hy : Γ y = some Ey) (hp : PushArg Γ F y Ey t D Γ1) : DomMode Γ Γ1 := by
  cases hp with
  | move _ _ _ => exact (DomMode.refl Γ |>.kill .replace false y).setE ⟨Ey, hy, rfl⟩
  | int => exact DomMode.refl Γ
  | slice _ => exact DomMode.refl Γ

theorem RhsT.domMode {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1) :
    DomMode Γ Γ1 := by
  cases hr with
  | @moveOwn y Ey hy _ _ _ _ =>
    exact (DomMode.refl Γ |>.kill .replace false y).setE ⟨Ey, hy, rfl⟩
  | pop _ _ _ _ _ => exact (DomMode.refl Γ).kill _ _ _
  | pair hy _ hpa1 hz _ hpa2 _ => exact (hpa1.domMode hy).trans (hpa2.domMode hz)
  | inl hy _ hpa _ => exact PushArg.domMode hy hpa
  | inr hy _ hpa _ => exact PushArg.domMode hy hpa
  | pack hy _ _ hpa => exact PushArg.domMode hy hpa
  | @takel y Ey _ _ hy _ _ _ _ _ => exact (DomMode.refl Γ |>.kill .replace false y).setE ⟨Ey, hy, rfl⟩
  | @taker y Ey _ _ hy _ _ _ _ _ => exact (DomMode.refl Γ |>.kill .replace false y).setE ⟨Ey, hy, rfl⟩
  | _ => exact DomMode.refl Γ

theorem DomMode.exitScope {Γ0 Γ : Ctx} (h : DomMode Γ0 Γ) {x : Var} {r : Var} (hrx : r ≠ x)
    {E : Entry} (hr : Γ0 r = some E) : ∃ E', exitScope x Γ r = some E' ∧ E'.mode = E.mode := by
  obtain ⟨E', h', hm⟩ := h.get hr
  exact ⟨killE .replace false x E', by simp [A2.exitScope, upd_ne _ _ hrx, A2.kill, h'],
    by rw [killE_mode, hm]⟩

/-- Taking a struct apart keeps the context well-formed. -/
theorem CtxWF.unpair {Γ : Ctx} (h : CtxWF Γ) {y x z : Var} {E : Entry} {a b : Ty} (hy : Γ y = some E)
    (hl : E.live = true) (hm : E.mode.ownSlot = true) (hty : E.ty = .prod a b) (hx : Γ x = none) (hz : Γ z = none)
    (hxz : x ≠ z) :
    CtxWF (A2.setE (A2.setE (A2.setE (A2.kill .replace false y Γ) y { E with live := false }) x (compE E a))
      z (compE E b)) := by
  have hxy : x ≠ y := fun e => by rw [e, hy] at hx; cases hx
  have hzy : z ≠ y := fun e => by rw [e, hy] at hz; cases hz
  have hw1 : CtxWF (A2.setE (A2.kill .replace false y Γ) y { E with live := false }) :=
    (h.kill .replace false y).setE ⟨killE .replace false y E, by simp [A2.kill, hy],
      fun hr => by rw [killE_mode] at hr; exact hr⟩ (fun hl' => by simp at hl')
  have hheld : ∀ r ∈ roots E.held, ∃ Er, A2.setE (A2.kill .replace false y Γ) y
      { E with live := false } r = some Er ∧ Er.mode.isRoot = true := by
    intro r hr
    have hn : E.ty ≠ .int ∨ E.mode = .rootb := Or.inl (by rw [hty]; simp)
    obtain ⟨Er, hEr, hro⟩ := h y E hy hl hn r (by
      simpa [roots, Entry.vdeps, hm] using hr)
    by_cases hry : r = y
    · subst hry; exact ⟨{ E with live := false }, by simp [A2.setE], Mode.isRoot_of_ownSlot hm⟩
    · obtain ⟨E', h', hro'⟩ := kill_root (e := .replace) (hv := false) (y := y) hEr hro
      exact ⟨E', by simp only [A2.setE, upd_ne _ _ hry]; exact h', hro'⟩
  have hcomp : ∀ (Γ' : Ctx) (t : Ty), (∀ r ∈ roots E.held, ∃ Er, Γ' r = some Er ∧ Er.mode.isRoot = true) →
      (compE E t).live = true → ((compE E t).ty ≠ .int ∨ (compE E t).mode = .rootb) →
      ∀ r ∈ roots (compE E t).vdeps, ∃ Er, Γ' r = some Er ∧ Er.mode.isRoot = true := by
    intro Γ' t hH _ hn r hr
    cases t with
    | int => simp [compE, intE] at hn
    | slice s =>
      simp only [compE, Entry.vdeps, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte, roots,
        List.map_append, List.mem_append] at hr
      rcases hr with hr | hr <;> exact hH r hr
    | vec s => exact hH r (ownHeld_roots (by simpa [compE, Entry.vdeps, Mode.ownSlot] using hr))
    | prod a b => exact hH r (ownHeld_roots (by simpa [compE, Entry.vdeps, Mode.ownSlot] using hr))
    | sum a b => exact hH r (ownHeld_roots (by simpa [compE, Entry.vdeps, Mode.ownSlot] using hr))
    | fn a => exact hH r (ownHeld_roots (by simpa [compE, Entry.vdeps, Mode.ownSlot] using hr))
  have hx1 : A2.setE (A2.kill .replace false y Γ) y { E with live := false } x = none := by
    simp [A2.setE, upd_ne _ _ hxy, A2.kill, hx]
  have hw2 := hw1.add hx1 (hcomp _ a hheld)
  have hz2 : A2.setE (A2.setE (A2.kill .replace false y Γ) y { E with live := false }) x (compE E a) z
      = none := by simp [A2.setE, upd_ne _ _ (Ne.symm hxz), upd_ne _ _ hzy, A2.kill, hz]
  have hheld2 : ∀ r ∈ roots E.held, ∃ Er, A2.setE (A2.setE (A2.kill .replace false y Γ) y
      { E with live := false }) x (compE E a) r = some Er ∧ Er.mode.isRoot = true := by
    intro r hr
    obtain ⟨Er, hEr, hro⟩ := hheld r hr
    have hrx : r ≠ x := fun e => by rw [e, hx1] at hEr; cases hEr
    exact ⟨Er, by simp [A2.setE, upd_ne _ _ hrx]; exact hEr, hro⟩
  have hw3 := hw2.add hz2 (hcomp _ b hheld2)
  exact hw3

theorem held_vdeps' {E : Entry} {r : Var} (h : r ∈ roots E.held) : r ∈ roots E.vdeps := by
  simp only [roots, Entry.vdeps, List.map_append, List.mem_append]; exact Or.inr h

theorem allKinds_root {rs : List Var} {d : Dep} (h : d ∈ allKinds rs) : d.root ∈ rs := by
  simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil, or_false] at h
  obtain ⟨r, hr, hd⟩ := h
  rcases hd with rfl | rfl | rfl <;> exact hr

/-- What a call through a package returns depends only on roots the
    context after it has. -/
theorem recvRes_roots {Γ Γ1 : Ctx} (h : CtxWF Γ) (hdm : DomMode Γ Γ1) {c : Var} {Ec E : Entry}
    (hc : Γ c = some Ec) (hlc : Ec.live = true) (htc : Ec.ty ≠ .int)
    (hE : ∀ r ∈ roots E.vdeps, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true) :
    ∀ r ∈ roots (recvRes c Ec E).vdeps, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true := by
  have hA : ∀ d ∈ allKinds (recvRoots c Ec), ∃ Er, Γ1 d.root = some Er ∧ Er.mode.isRoot = true := by
    intro d hd
    have hr := allKinds_root hd
    rcases List.mem_append.mp hr with hr | hr
    · exact hdm.root (derive_roots h hc hlc (Or.inl htc) .self _ (roots_memDeps hr))
    · exact hdm.root (h c Ec hc hlc (Or.inl htc) _ (held_vdeps' (roots_memDeps hr)))
  intro r hr
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
  unfold Entry.vdeps at hd
  rcases List.mem_append.mp hd with hd | hd
  · split at hd
    · simp at hd
    · rename_i hos
      have hos' : E.mode.ownSlot = false := by simpa [recvRes] using hos
      simp only [recvRes] at hd
      rcases List.mem_append.mp hd with hd | hd
      · exact hE _ (List.mem_map_of_mem (f := Dep.root) (by
          simp only [Entry.vdeps, hos', Bool.false_eq_true, ↓reduceIte]
          exact List.mem_append_left _ hd))
      · exact hA d hd
  · simp only [recvRes] at hd
    rcases List.mem_append.mp (ownHeld_sub _ _ _ hd) with hd | hd
    · exact hE _ (List.mem_map_of_mem (f := Dep.root) (by unfold Entry.vdeps; exact List.mem_append_right _ hd))
    · exact hA d hd

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
  | @letv Γ Γ1 Δ F x r0 k E0 _ hx hxF hrh _ _ ih =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    obtain ⟨E1, h1, hm1⟩ := hrh.domMode.get h
    obtain ⟨E2, h2, hm2⟩ := ih r hr E1 (by simp [A2.setE, upd_ne _ _ hrx, h1])
    exact ⟨killE .replace false x E2, by simp [A2.exitScope, upd_ne _ _ hrx, A2.kill, h2],
      by rw [killE_mode, hm2, hm1]⟩
  | @letcall Γ Γ1 Δ F x f args k E0 _ hx hxF hc _ _ ih =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    obtain ⟨E1, h1, hm1⟩ := hc.domMode.get h
    obtain ⟨E2, h2, hm2⟩ := ih r hr E1 (by simp [A2.setE, upd_ne _ _ hrx, h1])
    exact ⟨killE .replace false x E2, by simp [A2.exitScope, upd_ne _ _ hrx, A2.kill, h2],
      by rw [killE_mode, hm2, hm1]⟩
  | @scope Γ Δ F x k _ hxF _ _ ih | @scopeD Γ Δ F x _ k _ hxF _ _ _ _ _ ih =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    obtain ⟨E2, h2, hm2⟩ := ih r hr E h
    exact ⟨killE .replace false x E2, by simp [A2.exitScope, upd_ne _ _ hrx, A2.kill, h2],
      by rw [killE_mode, hm2]⟩
  | @letd Γ Γ1 Δ F x _ r0 k E0 _ hx hxF hrh _ _ _ _ _ ih =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    obtain ⟨E1, h1, hm1⟩ := hrh.domMode.get h
    obtain ⟨E2, h2, hm2⟩ := ih r hr E1 (by simp [A2.setE, upd_ne _ _ hrx, h1])
    exact ⟨killE .replace false x E2, by simp [A2.exitScope, upd_ne _ _ hrx, A2.kill, h2],
      by rw [killE_mode, hm2, hm1]⟩
  | @callc Γ Γ1 Δ F x c j zs k Ec E0 ms σ sig _ hx hxF _ _ _ _ _ _ hcT _ _ _ ih =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    obtain ⟨E1, h1, hm1⟩ := hcT.domMode.get h
    obtain ⟨E2, h2, hm2⟩ := ih r hr E1 (by simp [A2.setE, upd_ne _ _ hrx, h1])
    exact ⟨killE .replace false x E2, by simp [A2.exitScope, upd_ne _ _ hrx, A2.kill, h2],
      by rw [killE_mode, hm2, hm1]⟩
  | @rbind Γ Δ F p k Ep _ _ _ _ hpF _ _ ih =>
    intro r hr E h
    have hrp : r ≠ p := fun e => hpF (e ▸ hr)
    obtain ⟨E2, h2, hm2⟩ := ih r hr E h
    exact ⟨rerootE p (Ep.path ++ Ep.held) E2, by simp [A2.exitRoot, upd_ne _ _ hrp, h2], by simp [rerootE, hm2]⟩
  | frozen _ _ ih => exact fun r hr E h => ih r (List.mem_append_left _ hr) E h
  | @assign Γ Γ1 F x r0 Ex E0 _ hxF _ hrh _ _ _ _ =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    obtain ⟨E1, h1, hm1⟩ := hrh.domMode.get h
    exact ⟨killE .replace false x E1, by simp [A2.setE, upd_ne _ _ hrx, A2.kill, h1],
      by rw [killE_mode, hm1]⟩
  | ite _ _ _ _ _ iha _ => exact iha
  | «while» _ _ _ _ => exact fun r _ E h => ⟨E, h, rfl⟩
  | @push Γ Γ1 F x y Ex Ey Ex1 t D _ _ _ _ hxF hy _ _ _ hpa _ _ _ =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    obtain ⟨E1, h1, hm1⟩ := (hpa.domMode hy).get h
    exact ⟨killE .realloc t.holdsView x E1, by simp [A2.setE, upd_ne _ _ hrx, A2.kill, h1],
      by rw [killE_mode, hm1]⟩
  | @free Γ F x E0 t _ _ _ _ hxF _ =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    exact ⟨killE .replace false x E, by simp [A2.setE, upd_ne _ _ hrx, A2.kill, h], by rw [killE_mode]⟩
  | @panic Γ Δ F _ _ hdom hmode =>
    intro r _ E h
    have hs := hdom r; rw [h] at hs
    obtain ⟨E', hE'⟩ := Option.isSome_iff_exists.mp hs.symm
    obtain ⟨E0, h0, hm, _⟩ := hmode r E' hE'
    rw [h] at h0; cases h0
    exact ⟨E', hE', hm⟩
  | @letrec Γ Γ1 Δ F x f k E0 fn _ hx hxF _ _ _ _ hc _ _ ih =>
    intro r hr E h
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    obtain ⟨E1, h1, hm1⟩ := hc.domMode.get h
    obtain ⟨E2, h2, hm2⟩ := ih r hr E1 (by simp [A2.setE, upd_ne _ _ hrx, h1])
    exact ⟨killE .replace false x E2, by simp [A2.exitScope, upd_ne _ _ hrx, A2.kill, h2],
      by rw [killE_mode, hm2, hm1]⟩
  | catchR _ hs _ _ hKO _ =>
    intro r hr E h
    obtain ⟨E', h', hm', _⟩ := hKO.1 r E h (fun hsp => hs.spine_F r hsp (List.mem_append_left _ hr))
    exact ⟨E', h', hm'⟩
  | @unpair Γ Δ F y x z k E0 a b _ hy _ _ _ hyF _ _ _ hxF hzF _ _ _ _ ih =>
    intro r hr E h
    have hry : r ≠ y := fun e => hyF (e ▸ hr)
    have hrx : r ≠ x := fun e => hxF (e ▸ hr)
    have hrz : r ≠ z := fun e => hzF (e ▸ hr)
    obtain ⟨E2, h2, hm2⟩ := ih r hr (killE .replace false y E)
      (by simp [A2.setE, upd_ne _ _ hrz, upd_ne _ _ hrx, upd_ne _ _ hry, A2.kill, h])
    exact ⟨killE .replace false x (killE .replace false z E2),
      by simp [A2.exitScope, upd_ne _ _ hrx, upd_ne _ _ hrz, A2.kill, h2],
      by rw [killE_mode, killE_mode, hm2, killE_mode]⟩
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
  | @letv Γ Γ1 Δ F x r k E _ hx _ hr _ _ ih =>
    intro h
    obtain ⟨hw1, hdom, _, hE⟩ := hr.wf h
    have hx1 : Γ1 x = none := by have := hdom x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    exact (ih (hw1.add hx1 hE)).exitScope x
  | @letcall Γ Γ1 Δ F x f args k E _ hx _ hc _ _ ih =>
    intro h
    obtain ⟨hw1, hdm, hE⟩ := hc.wf hP h
    have hx1 : Γ1 x = none := by have := hdm.1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    exact (ih (hw1.add hx1 (fun _ _ => hE))).exitScope x
  | scope _ _ _ _ ih => exact fun h => (ih h).exitScope _
  | scopeD _ _ _ _ _ _ _ ih => exact fun h => (ih h).exitScope _
  | @letd Γ Γ1 Δ F x _ r k E _ hx _ hr _ _ _ _ _ ih =>
    intro h
    obtain ⟨hw1, hdom, _, hE⟩ := hr.wf h
    have hx1 : Γ1 x = none := by have := hdom x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    exact (ih (hw1.add hx1 hE)).exitScope x
  | @callc Γ Γ1 Δ F x c j zs k Ec E0 ms σ sig _ hx _ hc htc _ _ _ _ hcT _ _ _ ih =>
    intro h
    obtain ⟨hw1, hdm, hE⟩ := hcT.wf hP h
    have hx1 : Γ1 x = none := by have := hdm.1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    have hlc : Ec.live = true := by
      obtain ⟨fn, _, hlen, hargs, _⟩ := hcT
      obtain ⟨Ea, hEa, hl, _⟩ := hargs 0 (by rw [← hlen]; simp)
      simp only [List.getD_cons_zero] at hEa; rw [hc] at hEa; cases hEa; exact hl
    exact (ih (hw1.add hx1 (fun _ _ => recvRes_roots h hdm hc hlc (by rw [htc]; simp) hE))).exitScope x
  | @rbind Γ Δ F p k E hp hm hl hroots hpF hk hrr ih =>
    intro h
    have hos : E.mode.ownSlot = false := by rw [hm]; rfl
    refine (ih h).exitRoot p (E.path ++ E.held) fun d hd => ?_
    have hdv : d.root ∈ roots E.vdeps := by
      simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.mem_map]
      exact ⟨d, hd, rfl⟩
    have hdv' : d ∈ E.vdeps := by simp only [Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte]; exact hd
    by_cases hb : d.kind.bound = .none
    · have hF := hroots d hdv' hb
      refine ⟨fun e => hpF (e ▸ hF), ?_⟩
      obtain ⟨Er, hEr, hro⟩ := h p E hp hl (Or.inr hm) d.root hdv
      obtain ⟨E', h', hm'⟩ := hk.keepF d.root hF Er hEr
      exact ⟨E', h', by rw [hm']; exact hro⟩
    · exact hrr d hdv' hb
  | frozen _ _ ih => exact ih
  | @assign Γ Γ1 F x r Ex E hx _ hmodes hr _ hxd _ _ =>
    intro h
    obtain ⟨hw1, hdom, hmode, hE⟩ := hr.wf h
    have hos : Ex.mode.ownSlot = E.mode.ownSlot := by
      rcases hmodes with ⟨h1, h2⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rw [h1, h2] <;> rfl
    have hsome : (A2.kill .replace false x Γ1 x).isSome := by rw [kill_dom, hdom, hx]; rfl
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
      | @move s ho hm hyF _ =>
        have hxy : x ≠ y := fun e => hyx e.symm
        simp only [A2.setE, upd_ne _ _ hxy, A2.kill, hx, Option.map_some, Option.some.injEq] at hx1
        subst hx1
        refine ⟨(h.kill .replace false y).setE ⟨killE .replace false y Ey, by simp [A2.kill, hy],
          fun hr => by rw [killE_mode] at hr; exact hr⟩ (fun hl' => by simp at hl'), killE_ty .., ?_⟩
        intro r hr
        have hn : Ey.ty ≠ .int ∨ Ey.mode = .rootb :=
          Or.inl (fun h' => by rw [htyy] at h'; rw [h'] at ho; cases ho)
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
      by simp [A2.kill, hx1], fun _ => hroot⟩ (fun hl' hn r hr => ?_)
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
      · obtain ⟨Er, hEr, hro⟩ := hD r (ownHeld_roots hr)
        exact kill_root hEr hro
  | @free Γ F x E t hx hl hm hty hxF _ =>
    intro h
    exact (h.kill .replace false x).setE ⟨killE .replace false x E, by simp [A2.kill, hx],
      fun hr => by rw [killE_mode] at hr; exact hr⟩ (fun hl' => by simp at hl')
  | panic hwf _ _ => exact fun _ => hwf
  | @letrec Γ Γ1 Δ F x f k E fn _ hx _ _ _ _ _ hc _ _ ih =>
    intro h
    obtain ⟨hw1, hdm, hE⟩ := hc.wf hP h
    have hx1 : Γ1 x = none := by have := hdm.1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    exact (ih (hw1.add hx1 (fun _ _ => hE))).exitScope x
  | catchR _ _ hM _ _ _ => exact fun _ => hM.wf
  | @unpair Γ Δ F y x z k E a b _ hy hl hm hty _ hx hz hxz _ _ _ _ _ _ ih =>
    exact fun h => ((ih (h.unpair hy hl hm.ownSlot hty hx hz hxz)).exitScope z).exitScope x
  | sub hw _ ho _ =>
    intro _
    rcases ho with rfl | ho
    · exact ‹CtxWF _ → CtxWF _› hw.wf
    · exact ho.wf

end A2
