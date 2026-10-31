import A1.Rhs

/-! A1 — the memory side of each step. -/

namespace A1

/-- A slot that was there before keeps its contents: every root reaches the
    same memory. -/
theorem rootKeep_ext {m m' : Mem} (h : ∀ o, m.st o ≠ none → m'.st o = m.st o) (r : Var) :
    RootKeep m m' r := by
  intro n hn
  have hown : ∀ o T, OwnedAt m o T → OwnedAt m' o T := fun o T hT => by
    unfold OwnedAt at *; rw [h o (by rw [hT]; simp)]; exact hT
  rcases hn with hn | ⟨c, hc, o, T, hT, hs, hnode⟩ | ⟨d, o', l, hc, o, T, hT, hs, hdata⟩
  · exact Or.inl (by rw [h r (by rw [hn]; simp)]; exact hn)
  · exact Or.inr (Or.inl ⟨c, by rw [h r (by rw [hc]; simp)]; exact hc, o, T, hown o T hT, hs, hnode⟩)
  · exact Or.inr (Or.inr ⟨d, o', l, by rw [h r (by rw [hc]; simp)]; exact hc, o, T, hown o T hT, hs,
      hdata⟩)

theorem SlotOK.ext {m m' : Mem} (h : ∀ o, m.st o ≠ none → m'.st o = m.st o) {E : Entry} {sl : Slot}
    (hs : SlotOK m E sl) : SlotOK m' E sl :=
  hs.keep fun dep _ => ⟨(rootKeep_ext h dep.root).vkeep, (rootKeep_ext h dep.root).hkeep⟩

/-- Binding a fresh variable to what a right-hand side produced. -/
theorem MInv.add {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} (hx : Γ x = none) (hxn : x < m.nv)
    {E : Entry} {v : Val} {o : Bool} (hout : RhsOut m Γ E v o) :
    MInv (m.set x ⟨o, some v⟩) (setE Γ x E) := by
  have hmx : m.st x = none := by
    have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
  have hext : ∀ o', m.st o' ≠ none → (m.set x ⟨o, some v⟩).st o' = m.st o' := by
    intro o' ho'
    have : o' ≠ x := fun h => ho' (h ▸ hmx)
    simp [upd_ne _ _ this]
  have hroot : ∀ r Er, Γ r = some Er → r ≠ x := fun r Er h hr => by rw [hr, hx] at h; cases h
  constructor
  · intro w
    by_cases hw : w = x
    · subst hw; simp [setE]
    · simp only [setE, upd_ne _ _ hw, Mem.set_st]; exact hi.dom w
  · intro w Ew hw
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw
      refine ⟨⟨o, some v⟩, by simp, hout.tyok, ?_⟩
      have hos : o = E.mode.ownSlot := hout.own
      refine ⟨hos, fun hm => ?_, fun hm hl => ?_⟩
      · have hown : E.mode = .own := by
          rcases hout.mode with h | h
          · exact h
          · rw [h] at hm; cases hm
        obtain ⟨hvec, hwf, hvs, _⟩ := hout.valOwn hown
        exact ⟨hvec, fun T hT => by cases hT; exact hwf, fun _ => ⟨v, rfl, hvs.keep fun dep _ =>
          (rootKeep_ext hext dep.root).vkeep⟩⟩
      · have hbor : E.mode = .bor := by
          rcases hout.mode with h | h
          · rw [h] at hm; cases hm
          · exact h
        refine ⟨v, rfl, (hout.valBor hbor).keep (fun dep _ => ?_) (fun dep _ => ?_)⟩
        · exact ⟨(rootKeep_ext hext dep.root).vkeep, (rootKeep_ext hext dep.root).hkeep⟩
        · exact (rootKeep_ext hext dep.root).vkeep
    · simp only [setE, upd_ne _ _ hwx] at hw
      obtain ⟨sl, hsl, hok, hslot⟩ := hi.slot w Ew hw
      exact ⟨sl, by simp [upd_ne _ _ hwx, hsl], hok, hslot.ext hext⟩
  · cases o with
    | false =>
      exact { nodup := fun o' T hT => hi.heap.nodup o' T (by
                rcases ownedAt_set.mp hT with ⟨_, h⟩ | ⟨_, h⟩
                · cases h
                · exact h)
              disj := fun o1 o2 T U hne h1 h2 => by
                rcases ownedAt_set.mp h1 with ⟨_, h⟩ | ⟨_, h1⟩
                · cases h
                rcases ownedAt_set.mp h2 with ⟨_, h⟩ | ⟨_, h2⟩
                · cases h
                exact hi.heap.disj o1 o2 T U hne h1 h2
              alloc := fun o' T hT => hi.heap.alloc o' T (by
                rcases ownedAt_set.mp hT with ⟨_, h⟩ | ⟨_, h⟩
                · cases h
                · exact h) }
    | true =>
      have hown : E.mode = .own := by
        rcases hout.mode with h | h
        · exact h
        · have := hout.own; rw [h] at this; cases this
      obtain ⟨_, _, _, hnd, hal, hdis⟩ := hout.valOwn hown
      refine hi.heap.put (x := x) (T := v) _ (fun o' U hU => ?_) (fun U hU => by
          unfold OwnedAt at hU; rw [hmx] at hU; cases hU) hnd hal hdis (fun _ _ _ _ _ => rfl)
        (Nat.le_refl _)
      rcases ownedAt_set.mp hU with ⟨h1, h2⟩ | h
      · cases h2; exact Or.inl ⟨h1, rfl⟩
      · exact Or.inr h
  · intro w hw
    by_cases hwx : w = x
    · subst hwx; exact hxn
    · simp only [Mem.set_st, upd_ne _ _ hwx] at hw; exact hi.nvSt w hw
  · intro w Ew b hw
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw
      rcases hout.mode with h | h <;> rw [h] <;> simp
    · simp only [setE, upd_ne _ _ hwx] at hw; exact hi.noInout w Ew b hw
  · intro w Ew hw hl hn r hr
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw
      have hn' : E.ty ≠ .int := by
        rcases hn with h | h
        · exact h
        · rcases hout.mode with h' | h' <;> rw [h'] at h <;> cases h
      obtain ⟨Er, hEr, hro⟩ := hout.wf hn' r hr
      exact ⟨Er, by simp [setE, upd_ne _ _ (hroot r Er hEr), hEr], hro⟩
    · simp only [setE, upd_ne _ _ hwx] at hw
      obtain ⟨Er, hEr, hro⟩ := hi.wf w Ew hw hl hn r hr
      exact ⟨Er, by simp [setE, upd_ne _ _ (hroot r Er hEr), hEr], hro⟩
  · intro p Ep hp hm
    by_cases hpx : p = x
    · subst hpx
      simp only [setE, upd_same, Option.some.injEq] at hp
      subst hp
      rcases hout.mode with h | h <;> rw [h] at hm <;> cases hm
    · simp only [setE, upd_ne _ _ hpx] at hp; exact hi.rootbLive p Ep hp hm
  · intro p Ep hp hm
    by_cases hpx : p = x
    · subst hpx
      simp only [setE, upd_same, Option.some.injEq] at hp
      subst hp
      rcases hout.mode with h | h <;> rw [h] at hm <;> cases hm
    · simp only [setE, upd_ne _ _ hpx] at hp; exact hi.rootbLt p Ep hp hm

theorem hanch_of {Γ Γ1 : Ctx} {F : List Var}
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    (hcm : ∀ x E1, Γ1 x = some E1 → ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode ∧ E1.ty = E0.ty)
    (hrb : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → Γ1 p = some Ep) :
    ∀ p E, Γ1 p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F := by
  intro p E hp hm
  obtain ⟨E0, h0, hm0, _⟩ := hcm p E hp
  have h1 := hrb p E0 h0 (hm0 ▸ hm)
  rw [hp] at h1
  cases h1
  exact hanch p _ h0 hm

/-- Releasing the tree a slot held (a drop, `vec_free`) and putting `ov` in
    its place. -/
theorem HeapOK.release {m : Mem} (hh : HeapOK m) {x : Var} {sl : Slot} (hx : m.st x = some sl)
    {a' : Nat → Bool} (hd : DropSlot m.alloc sl a') (ov : Slot)
    (hput : ov.own = true → ∀ T, ov.val = some T →
      T.ids.Nodup ∧ (∀ i ∈ T.ids, m.alloc i = true ∧ i < m.nid) ∧
      ∀ o U, OwnedAt m o U → ∀ i ∈ T.ids, i ∉ U.ids) :
    HeapOK ({ m with alloc := a' }.set x ov) := by
  -- the addresses the drop changed are those of the tree it released
  have hfr : ∀ i, (∀ T, sl = ⟨true, some T⟩ → i ∉ T.ids) → a' i = m.alloc i := by
    intro i hi
    cases hd with
    | owned hf => exact hf.other (hi _ rfl)
    | moved => rfl
    | borrowed => rfl
  have hown : ∀ o U, OwnedAt ({ m with alloc := a' }.set x ov) o U →
      (o = x ∧ ov = ⟨true, some U⟩) ∨ (o ≠ x ∧ OwnedAt m o U) := fun o U h => ownedAt_set.mp h
  have hsep : ∀ o U, o ≠ x → OwnedAt m o U → ∀ i ∈ U.ids, a' i = m.alloc i := by
    intro o U hox hU i hi
    refine hfr i fun T hT => ?_
    subst hT
    exact fun h => hh.disj o x U T hox hU hx i hi h
  refine ⟨fun o U hU => ?_, fun o1 o2 U1 U2 hne h1 h2 => ?_, fun o U hU => ?_⟩
  · rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
    · exact (hput rfl U rfl).1
    · exact hh.nodup o U h
  · rcases hown o1 U1 h1 with ⟨rfl, rfl⟩ | ⟨ho1, h1'⟩ <;> rcases hown o2 U2 h2 with ⟨rfl, h2e⟩ | ⟨ho2, h2'⟩
    · exact absurd rfl hne
    · exact (hput rfl U1 rfl).2.2 o2 U2 h2'
    · cases h2e; exact fun i hi hi' => (hput rfl U2 rfl).2.2 o1 U1 h1' i hi' hi
    · exact hh.disj o1 o2 U1 U2 hne h1' h2'
  · intro i hi
    rcases hown o U hU with ⟨rfl, rfl⟩ | ⟨ho, h⟩
    · obtain ⟨_, hal, hdis⟩ := hput rfl U rfl
      refine ⟨?_, (hal i hi).2⟩
      show a' i = true
      rw [hfr i fun T hT => ?_]
      · exact (hal i hi).1
      · subst hT; exact hdis o T hx i hi
    · obtain ⟨ha, hlt⟩ := hh.alloc o U h i hi
      exact ⟨by show a' i = true; rw [hsep o U ho h i hi]; exact ha, hlt⟩

theorem keep_notx {m m' : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    {x : Var} (hxF : x ∉ F) (hst : ∀ o, o ≠ x → m'.st o = m.st o) {dep : Dep}
    (hr : ∃ Er, Γ dep.root = some Er ∧ Er.mode.isRoot = true) (hne : dep.root ≠ x) :
    VKeep m m' dep ∧ HKeep m m' dep := by
  obtain ⟨Er, hEr, hroot⟩ := hr
  have hk := rootKeep_frame hi hanch (fun o ho => hst o (fun h => hxF (h ▸ ho))) hEr hroot (hst _ hne)
  exact ⟨hk.vkeep, hk.hkeep⟩

theorem vdeps_mode {E : Entry} {md : Mode} (h : md.ownSlot = E.mode.ownSlot) :
    ({ E with mode := md } : Entry).vdeps = E.vdeps := by
  simp [Entry.vdeps, h]

/-- `= x r`: the right-hand side runs, `x`'s old value is dropped, and `x`
    takes the new one. -/
theorem step_assign {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    {x : Var} {r : Rhs} {Ex E : Entry} (hx : Γ x = some Ex) (hxF : x ∉ F)
    (hmodes : Ex.mode = .own ∧ E.mode = .own ∨ Ex.mode = .inout .replace ∧ E.mode = .own ∨
      Ex.mode = .bor ∧ E.mode = .bor)
    (hr : RhsT Γ F r E Γ1) (hty : E.ty = Ex.ty) (hxd : x ∉ roots E.vdeps)
    {v : Val} {o : Bool} (he : EvalR m r (.ok v o m1)) {sl : Slot} (hsl : m1.st x = some sl)
    {a' : Nat → Bool} (hd : DropSlot m1.alloc sl a') :
    RhsPost m ({ m1 with alloc := a' }.set x ⟨o, some v⟩) Γ
      (setE (kill .replace false x Γ1) x { E with mode := Ex.mode }) F := by
  obtain ⟨post, out⟩ := rhs_pres hi hanch hr he
  have hanch1 := hanch_of hanch post.cmode post.rootb
  obtain ⟨Ex1, hx1, hm1, _⟩ : ∃ Ex1, Γ1 x = some Ex1 ∧ Ex1.mode = Ex.mode ∧ Ex1.ty = Ex.ty := by
    have := post.cdom x; rw [hx] at this
    cases h : Γ1 x with
    | none => rw [h] at this; cases this
    | some Ex1 =>
      obtain ⟨E0, h0, hm, ht⟩ := post.cmode x Ex1 h
      rw [hx] at h0; cases h0
      exact ⟨Ex1, rfl, hm, ht⟩
  have hos : Ex.mode.ownSlot = E.mode.ownSlot := by
    rcases hmodes with ⟨h1, h2⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rw [h1, h2] <;> rfl
  have hnrb : Ex1.mode ≠ .rootb := by
    rw [hm1]; rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩ <;> rw [h1] <;> simp
  let m' := { m1 with alloc := a' }.set x ⟨o, some v⟩
  have hst : ∀ o', o' ≠ x → m'.st o' = m1.st o' := fun o' ho => by simp [m', upd_ne _ _ ho]
  have hheap : HeapOK m' := post.inv.heap.release hsl hd ⟨o, some v⟩ (fun ho T hT => by
    cases hT
    have hown : E.mode = .own := by
      rcases out.mode with h | h
      · exact h
      · have := out.own; rw [h] at this; simp at ho; rw [ho] at this; cases this
    obtain ⟨_, _, _, hnd, hal, hdis⟩ := out.valOwn hown
    exact ⟨hnd, hal, hdis⟩)
  have hkeepE : E.ty ≠ .int → ∀ dep ∈ E.vdeps, VKeep m1 m' dep ∧ HKeep m1 m' dep := by
    intro hint dep hd'
    have hne : dep.root ≠ x := fun h => hxd (h ▸ List.mem_map_of_mem hd')
    exact keep_notx post.inv hanch1 hxF hst (out.wf hint dep.root (List.mem_map_of_mem hd')) hne
  have hslot : SlotOK m' { E with mode := Ex.mode } ⟨o, some v⟩ := by
    refine ⟨by show o = Ex.mode.ownSlot; rw [hos]; exact out.own, fun hown => ?_, fun hbor hl => ?_⟩
    · have hE : E.mode = .own := by
        rcases out.mode with h | h
        · exact h
        · show E.mode = .own; simp only at hown; rw [hos, h] at hown; cases hown
      obtain ⟨⟨t, ht⟩, hwf, hvs, _⟩ := out.valOwn hE
      refine ⟨⟨t, ht⟩, fun T hT => by cases hT; exact hwf, fun _ => ⟨v, rfl, hvs.keep fun dep hd' => ?_⟩⟩
      refine (hkeepE (by rw [ht]; simp) dep ?_).1
      simp [Entry.vdeps, hE, Mode.ownSlot, hd']
    · have hE : E.mode = .bor := by
        rcases out.mode with h | h
        · simp only at hbor; rw [hos, h] at hbor; cases hbor
        · exact h
      refine ⟨v, rfl, ?_⟩
      show ValOK m' E.ty v E.path E.held
      by_cases hint : E.ty = .int
      · have := out.valBor hE; rw [hint] at this ⊢; exact this
      · refine (out.valBor hE).keep (fun dep hd' => hkeepE hint dep ?_) (fun dep hd' => (hkeepE hint dep ?_).1)
        · simp [Entry.vdeps, hE, Mode.ownSlot, hd']
        · simp [Entry.vdeps, hE, Mode.ownSlot, hd']
  have hinv : MInv m' (setE (kill .replace false x Γ1) x { E with mode := Ex.mode }) := by
    refine post.inv.change hanch1 hx1 hxF hnrb hst hheap rfl
      (fun k hk => by cases k <;> simp [Eff.kills] at hk) ?_ (by simp)
    refine ⟨⟨o, some v⟩, by simp [m'], out.tyok, hslot, hm1.symm, fun hl hn r hr' => Or.inr ?_⟩
    rw [vdeps_mode hos] at hr'
    refine ⟨fun h => hxd (h ▸ hr'), kill_root (out.wf hn r hr').choose_spec.1
      (out.wf hn r hr').choose_spec.2⟩
  refine ⟨hinv, post.nv, post.nid, fun y => ?_, fun y hy => ?_, fun p Ep hp hpm => ?_, fun y => ?_,
    fun y E1 h => ?_⟩
  · by_cases hyx : y = x
    · subst hyx; simp; rw [← post.dom y, hsl]; rfl
    · rw [hst y hyx]; exact post.dom y
  · rw [hst y (fun h => hxF (h ▸ hy))]; exact post.frz y hy
  · have hpx : p ≠ x := fun h => by
      subst h; rw [hx] at hp; cases hp
      rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩ <;> rw [h1] at hpm <;> cases hpm
    simp only [setE, upd_ne _ _ hpx, kill, post.rootb p Ep hp hpm, Option.map_some]
    rw [killE_rootb hanch1 hxF _ _ (post.rootb p Ep hp hpm) hpm]
  · by_cases hyx : y = x
    · subst hyx; simp [setE, hx]
    · simp only [setE, upd_ne _ _ hyx]; rw [kill_dom, post.cdom]
  · by_cases hyx : y = x
    · subst hyx
      simp only [setE, upd_same, Option.some.injEq] at h
      subst h
      exact ⟨Ex, hx, rfl, hty⟩
    · simp only [setE, upd_ne _ _ hyx] at h
      obtain ⟨E0, h0, hm0, ht0⟩ := kill_cmode h
      obtain ⟨E00, h00, hm00, ht00⟩ := post.cmode y E0 h0
      exact ⟨E00, h00, hm0.trans hm00, ht0.trans ht00⟩

/-- `vec_free x`: the tree is released, the slot's flag cleared. -/
theorem step_free {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    {x : Var} {E : Entry} (hx : Γ x = some E) (hm : E.mode = .own) (hxF : x ∉ F)
    {t : Val} (ht : m.st x = some ⟨true, some t⟩) {a' : Nat → Bool} (hf : Frees m.alloc t a') :
    MInv ({ m with alloc := a' }.set x ⟨true, none⟩)
      (setE (kill .replace false x Γ) x { E with live := false }) := by
  obtain ⟨sl, hsl, hok, hslot⟩ := hi.slot x E hx
  rw [ht] at hsl; cases hsl
  have hos : E.mode.ownSlot = true := by rw [hm]; rfl
  obtain ⟨_, hown, _⟩ := hslot
  obtain ⟨hvec, _, _⟩ := hown hos
  refine hi.change hanch hx hxF (by rw [hm]; simp) (fun o ho => by simp [upd_ne _ _ ho])
    (hi.heap.release ht (DropSlot.owned hf) ⟨true, none⟩ (fun _ T hT => by cases hT)) rfl
    (fun k hk => by cases k <;> simp [Eff.kills] at hk) ?_ (by simp)
  have hs : SlotOK ({ m with alloc := a' }.set x ⟨true, none⟩) { E with live := false } ⟨true, none⟩ :=
    ⟨by simp [hos], fun _ => ⟨hvec, fun T h => (by cases h), fun h => (by simp at h)⟩,
      fun h => (by simp [hos] at h)⟩
  exact ⟨⟨true, none⟩, by simp, hok, hs, rfl, fun h => (by simp at h)⟩

theorem HeapOK.remove {m : Mem} (hh : HeapOK m) {x : Var} {sl : Slot} (hx : m.st x = some sl)
    {a' : Nat → Bool} (hd : DropSlot m.alloc sl a') : HeapOK ({ m with alloc := a' }.remove x) := by
  have hown : ∀ o U, OwnedAt ({ m with alloc := a' }.remove x) o U → o ≠ x ∧ OwnedAt m o U :=
    fun o U h => ownedAt_remove.mp h
  cases hd with
  | owned hf => exact hh.without hx _ hown (fun i hi => hf.other hi) (Nat.le_refl _)
  | moved =>
    exact ⟨fun o U h => hh.nodup o U (hown o U h).2,
      fun o1 o2 U1 U2 hne h1 h2 => hh.disj o1 o2 U1 U2 hne (hown o1 U1 h1).2 (hown o2 U2 h2).2,
      fun o U h => hh.alloc o U (hown o U h).2⟩
  | borrowed =>
    exact ⟨fun o U h => hh.nodup o U (hown o U h).2,
      fun o1 o2 U1 U2 hne h1 h2 => hh.disj o1 o2 U1 U2 hne (hown o1 U1 h1).2 (hown o2 U2 h2).2,
      fun o U h => hh.alloc o U (hown o U h).2⟩

/-- The end of `x`'s scope: its value, if it owns one, is dropped. -/
theorem step_scopeExit {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    {x : Var} {E : Entry} (hx : Γ x = some E) (hnrb : E.mode ≠ .rootb) (hxF : x ∉ F)
    {sl : Slot} (hsl : m.st x = some sl) {a' : Nat → Bool} (hd : DropSlot m.alloc sl a') :
    MInv ({ m with alloc := a' }.remove x) (exitScope x Γ) :=
  hi.change hanch hx hxF hnrb (fun o ho => by simp [upd_ne _ _ ho]) (hi.heap.remove hsl hd) rfl
    (fun k hk => by cases k <;> simp [Eff.kills] at hk) (show _ = none by simp) (fun _ => rfl)

/-- The pushed element: valid where it is going, and not part of any tree
    an owner still has. -/
structure Pushed (m1 : Mem) (Γ1 : Ctx) (t : Ty) (v : Val) (D : List Dep) : Prop where
  wf   : WFv t v
  vs   : ViewsOK m1 t v D
  nd   : v.ids.Nodup
  al   : ∀ i ∈ v.ids, m1.alloc i = true ∧ i < m1.nid
  dis  : ∀ o U, OwnedAt m1 o U → ∀ i ∈ v.ids, i ∉ U.ids
  root : ∀ r ∈ roots D, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true

/-- Taking the value `vec_push` stores: an element `Vec` moves out of its
    binding, anything else is copied. -/
theorem push_take {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    {y : Var} {Ey : Entry} {t : Ty} {D : List Dep} (hy : Γ y = some Ey) (hl : Ey.live = true)
    (hty : Ey.ty = t) (hpa : PushArg Γ F y Ey t D Γ1) {v : Val} (htk : TakeVal m y v m1) :
    RhsPost m m1 Γ Γ1 F ∧ Pushed m1 Γ1 t v D := by
  cases hpa with
  | move hm hyF =>
    cases htk with
    | own hv =>
      obtain ⟨post, out⟩ := rhs_move hi hanch hy hl hm hyF hv
      obtain ⟨_, hwf, hvs, hnd, hal, hdis⟩ := out.valOwn rfl
      refine ⟨post, Pushed.mk (hty ▸ hwf) (hty ▸ hvs) hnd hal hdis (fun r hr => ?_)⟩
      exact out.wf (by rw [hty]; simp) r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)
    | bor hv =>
      obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
      rw [hT] at hv; cases hv
  | int =>
    have hnown : Ey.mode.ownSlot = false := by
      cases h : Ey.mode.ownSlot with
      | false => rfl
      | true =>
        obtain ⟨_, _, _, _, hown, _⟩ := hi.slot y Ey hy
        obtain ⟨⟨t', ht'⟩, _⟩ := hown h
        rw [hty] at ht'; cases ht'
    obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl hnown
    cases htk with
    | own hv => rw [hw] at hv; cases hv
    | bor hv =>
      rw [hw] at hv; cases hv
      rw [hty] at hok
      obtain ⟨n, rfl⟩ := hok
      exact ⟨RhsPost.same hi, Pushed.mk WFv.int (fun _ _ h => (by cases h)) (by simp) (by simp)
        (by simp) (by simp [roots])⟩
  | slice hm =>
    rename_i s
    have hnown : Ey.mode.ownSlot = false := by rcases hm with h | h <;> rw [h] <;> rfl
    obtain ⟨w, hw, _⟩ := hi.bor_val hy hl hnown
    cases htk with
    | own hv => rw [hw] at hv; cases hv
    | bor hv =>
      have hok : ValOK m (.slice s) v (derive y Ey .self) Ey.held := by
        rcases hm with h | h
        · have hder : derive y Ey .self = Ey.path := by
            unfold derive
            simp only [h, Mode.isRoot, Bool.false_eq_true, ↓reduceIte]
            conv => rhs; rw [← List.map_id Ey.path]
            congr; funext dep; cases dep with | mk r k => cases k <;> rfl
          rw [hder, ← hty]; exact (out_copyBor hi hy hl h hv).valBor h
        · rw [← hty]
          exact (out_borrowWhole hi hy hl (Or.inl hnown) (Or.inl hv) (Or.inl h)).valBor rfl
      obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := hok
      have hnint : Ey.ty ≠ .int := by rw [hty]; simp
      refine ⟨RhsPost.same hi, Pushed.mk WFv.view (fun s' v' hin => ?_) (by simp) (by simp)
        (by simp) ?_⟩
      · cases hin
        exact ⟨d, o, l, rfl, dep, List.mem_append_left _ hd, ha⟩
      · exact wf_append (wf_derive hi hy hl hnint _) (wf_held hi hy hl hnint)

/-- Growing a tree by one element, its buffer moving or not. -/
theorem HeapOK.grow {m : Mem} (hh : HeapOK m) {x : Var} {t : Ty} {c d : Nat} {es : List Val}
    (hT : m.st x = some ⟨true, some (.node t c d es)⟩) {v : Val} (hnd : v.ids.Nodup)
    (hal : ∀ i ∈ v.ids, m.alloc i = true ∧ i < m.nid)
    (hdis : ∀ o U, OwnedAt m o U → ∀ i ∈ v.ids, i ∉ U.ids)
    {d' : Nat} {A' : Nat → Bool} {N' : Nat}
    (hre : (d' = d ∧ A' = m.alloc ∧ N' = m.nid) ∨
      (d' = m.nid ∧ A' = upd (upd m.alloc d false) m.nid true ∧ N' = m.nid + 1)) :
    HeapOK ({ m with alloc := A', nid := N' }.set x ⟨true, some (.node t c d' (es ++ [v]))⟩) := by
  have hnT := hh.nodup x _ hT
  have halT := hh.alloc x _ hT
  have hvT : ∀ i ∈ v.ids, i ∉ (Val.node t c d es).ids := hdis x _ hT
  simp only [ids_node, List.nodup_cons, List.mem_cons, not_or] at hnT
  have hNle : m.nid ≤ N' := by rcases hre with ⟨_, _, rfl⟩ | ⟨_, _, rfl⟩ <;> omega
  -- addresses other than the moved buffer keep their liveness
  have hA : ∀ i, i ≠ d → i ≠ m.nid → A' i = m.alloc i := by
    intro i h1 h2
    rcases hre with ⟨_, rfl, _⟩ | ⟨_, rfl, _⟩
    · rfl
    · rw [upd_ne _ _ h2, upd_ne _ _ h1]
  have hown : ∀ o U, OwnedAt ({ m with alloc := A', nid := N' }.set x
      ⟨true, some (.node t c d' (es ++ [v]))⟩) o U →
      (o = x ∧ U = .node t c d' (es ++ [v])) ∨ (o ≠ x ∧ OwnedAt m o U) := by
    intro o U hU
    rcases ownedAt_set.mp hU with ⟨h1, h2⟩ | h
    · cases h2; exact Or.inl ⟨h1, rfl⟩
    · exact Or.inr h
  -- the new tree's addresses
  have hmem : ∀ i, i ∈ (Val.node t c d' (es ++ [v])).ids →
      i = c ∨ i = d' ∨ i ∈ idsL es ∨ i ∈ v.ids := by
    intro i hi
    simp only [ids_node, idsL_append, idsL_cons, idsL_nil, List.append_nil, List.mem_cons,
      List.mem_append] at hi
    rcases hi with h | h | h | h
    · exact Or.inl h
    · exact Or.inr (Or.inl h)
    · exact Or.inr (Or.inr (Or.inl h))
    · exact Or.inr (Or.inr (Or.inr h))
  have hTids : ∀ i, (i = c ∨ i = d ∨ i ∈ idsL es) → i ∈ (Val.node t c d es).ids := by
    intro i h; simp only [ids_node, List.mem_cons]; exact h
  have hlt : ∀ i, (i = c ∨ i = d ∨ i ∈ idsL es) → i < m.nid := fun i h => (halT i (hTids i h)).2
  have hd'cases : d' = d ∨ d' = m.nid := by rcases hre with ⟨h, _⟩ | ⟨h, _⟩ <;> simp [h]
  refine ⟨fun o U hU => ?_, fun o1 o2 U1 U2 hne h1 h2 => ?_, fun o U hU i hi => ?_⟩
  · rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
    · simp only [ids_node, idsL_append, idsL_cons, idsL_nil, List.append_nil, List.nodup_cons,
        List.mem_cons, List.mem_append, not_or, List.nodup_append]
      have hc_lt := hlt c (Or.inl rfl)
      refine ⟨⟨?_, ?_, ?_⟩, ⟨?_, ?_⟩, hnT.2.2, hnd, fun a ha b hb => ?_⟩
      · rcases hd'cases with rfl | rfl
        · exact hnT.1.1
        · omega
      · exact hnT.1.2
      · exact fun h => hvT c h (hTids c (Or.inl rfl))
      · rcases hd'cases with rfl | rfl
        · exact hnT.2.1
        · exact fun h => by have := hlt _ (Or.inr (Or.inr h)); omega
      · rcases hd'cases with rfl | rfl
        · exact fun h => hvT d' h (hTids d' (Or.inr (Or.inl rfl)))
        · exact fun h => by have := (hal _ h).2; omega
      · intro hab; subst hab; exact hvT a hb (hTids a (Or.inr (Or.inr ha)))
    · exact hh.nodup o U h
  · have key : ∀ o U, o ≠ x → OwnedAt m o U → ∀ i ∈ (Val.node t c d' (es ++ [v])).ids, i ∉ U.ids := by
      intro o U hox hU i hi hiU
      rcases hmem i hi with rfl | rfl | h | h
      · exact hh.disj x o _ U (Ne.symm hox) hT hU _ (hTids _ (Or.inl rfl)) hiU
      · rcases hd'cases with rfl | rfl
        · exact hh.disj x o _ U (Ne.symm hox) hT hU _ (hTids _ (Or.inr (Or.inl rfl))) hiU
        · have := (hh.alloc o U hU _ hiU).2; omega
      · exact hh.disj x o _ U (Ne.symm hox) hT hU _ (hTids _ (Or.inr (Or.inr h))) hiU
      · exact hdis o U hU i h hiU
    rcases hown o1 U1 h1 with ⟨rfl, rfl⟩ | ⟨ho1, h1'⟩ <;> rcases hown o2 U2 h2 with ⟨rfl, rfl⟩ | ⟨ho2, h2'⟩
    · exact absurd rfl hne
    · exact key o2 U2 ho2 h2'
    · exact fun i hi hi' => key o1 U1 ho1 h1' i hi' hi
    · exact hh.disj o1 o2 U1 U2 hne h1' h2'
  · rcases hown o U hU with ⟨_, rfl⟩ | ⟨hox, h⟩
    · show A' i = true ∧ i < N'
      rcases hmem i hi with rfl | rfl | h | h
      · have hcd : i ≠ d := hnT.1.1
        have hcn := hlt i (Or.inl rfl)
        exact ⟨by rw [hA i hcd (by omega)]; exact (halT i (hTids i (Or.inl rfl))).1, by omega⟩
      · rcases hre with ⟨rfl, rfl, rfl⟩ | ⟨rfl, rfl, rfl⟩
        · exact halT i (hTids i (Or.inr (Or.inl rfl)))
        · exact ⟨by simp, by omega⟩
      · have hid : i ≠ d := fun h' => hnT.2.1 (h' ▸ h)
        have hin := hlt i (Or.inr (Or.inr h))
        exact ⟨by rw [hA i hid (by omega)]; exact (halT i (hTids i (Or.inr (Or.inr h)))).1, by omega⟩
      · have hid : i ≠ d := fun h' => hvT i h (hTids i (Or.inr (Or.inl h')))
        have hin := (hal i h).2
        exact ⟨by rw [hA i hid (by omega)]; exact (hal i h).1, by omega⟩
    · obtain ⟨ha, hl'⟩ := hh.alloc o U h i hi
      have hid : i ≠ d := fun h' => hh.disj x o _ U (Ne.symm hox) hT h d
        (hTids d (Or.inr (Or.inl rfl))) (h' ▸ hi)
      exact ⟨by show A' i = true; rw [hA i hid (by omega)]; exact ha, by show i < N'; omega⟩

theorem push_grow {m1 : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : ∀ p E, Γ1 p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    {x : Var} {Ex : Entry} (hx : Γ1 x = some Ex) (hl : Ex.live = true) (hcan : canDo Ex.mode .realloc)
    (hxF : x ∉ F) {t : Ty} (hty : Ex.ty = .vec t)
    {t' : Ty} {c d : Nat} {es : List Val} (hT : m1.st x = some ⟨true, some (.node t' c d es)⟩)
    {v : Val} {D : List Dep} (hp : Pushed m1 Γ1 t v D) (hxD : x ∉ roots D)
    {d' : Nat} {A' : Nat → Bool} {N' : Nat}
    (hre : (d' = d ∧ A' = m1.alloc ∧ N' = m1.nid) ∨
      (d' = m1.nid ∧ A' = upd (upd m1.alloc d false) m1.nid true ∧ N' = m1.nid + 1)) :
    MInv ({ m1 with alloc := A', nid := N' }.set x ⟨true, some (.node t' c d' (es ++ [v]))⟩)
      (setE (kill .realloc t.holdsView x Γ1) x { Ex with held := Ex.held ++ D }) := by
  have hm : Ex.mode = .own := by
    rcases hcan with h | ⟨b, h, _⟩
    · exact h
    · exact absurd h (hi.noInout x Ex b hx)
  have hos : Ex.mode.ownSlot = true := by rw [hm]; rfl
  obtain ⟨T, hT', hwT, hvsT⟩ := hi.own_val hx hl hos
  rw [hT] at hT'; cases hT'
  rw [hty] at hwT hvsT
  have htt : t' = t := by cases hwT; rfl
  subst htt
  let m' := { m1 with alloc := A', nid := N' }.set x ⟨true, some (.node t' c d' (es ++ [v]))⟩
  have hst : ∀ o, o ≠ x → m'.st o = m1.st o := fun o ho => by simp [m', upd_ne _ _ ho]
  have hwT' : WFv (.vec t') (.node t' c d' (es ++ [v])) := by
    refine WFv.node fun e he => ?_
    rcases List.mem_append.mp he with h | h
    · exact hwT.elem rfl h
    · simp at h; subst h; exact hp.wf
  have hnint : Ex.ty ≠ .int := by rw [hty]; simp
  have hrootH : ∀ dep ∈ Ex.held, ∃ Er, Γ1 dep.root = some Er ∧ Er.mode.isRoot = true :=
    fun dep hd => wf_held hi hx hl hnint dep.root (List.mem_map_of_mem hd)
  refine hi.change hanch hx hxF (by rw [hm]; simp) hst
    (hi.heap.grow hT hp.nd hp.al hp.dis hre) rfl ?_ ?_ (by simp)
  · intro k hk
    have hev : Evolve m1 m' x t' c d d' es (es ++ [v]) := ⟨hT, by simp [m'], hwT'⟩
    have hpre : ∀ e ∈ es, e ∈ es ++ [v] := fun e he => List.mem_append_left _ he
    have hkv : k ≠ .view := by intro h; subst h; simp [Eff.kills] at hk
    exact ⟨hev.grow_vkeep hpre hkv, hev.grow_hkeep hpre (fun h => by subst h; simpa [Eff.kills] using hk)
      hkv⟩
  · refine ⟨⟨true, some (.node t' c d' (es ++ [v]))⟩, by simp [m'], by rw [hty]; exact hi.tyok hx ▸ (by
        rw [hty]), ⟨by simp [hos], fun _ => ⟨⟨t', hty⟩, fun U hU => by cases hU; rw [hty]; exact hwT',
        fun _ => ⟨_, rfl, ?_⟩⟩, fun h => by simp [hos] at h⟩, rfl, fun hl' hn r hr => ?_⟩
    · rw [hty]
      intro s w hin
      cases hin with
      | child he hin =>
        rename_i e
        rcases List.mem_append.mp he with h | h
        · obtain ⟨d0, o0, l0, rfl, dep, hd, ha⟩ := hvsT s _ (ViewIn.child h hin)
          refine ⟨d0, o0, l0, rfl, dep, List.mem_append_left _ hd, ?_⟩
          have hne : dep.root ≠ x := by
            intro heq; obtain ⟨r, k⟩ := dep; simp only at heq; subst heq
            exact viewAt_not_self hT hwT (ViewIn.child h hin) ha
          exact (keep_notx hi hanch hxF hst (hrootH dep hd) hne).1 d0 o0 l0 s ha
        · simp at h; subst h
          obtain ⟨d0, o0, l0, rfl, dep, hd, ha⟩ := hp.vs s _ hin
          refine ⟨d0, o0, l0, rfl, dep, List.mem_append_right _ hd, ?_⟩
          have hne : dep.root ≠ x := fun heq => hxD (heq ▸ List.mem_map_of_mem hd)
          exact (keep_notx hi hanch hxF hst (hp.root dep.root (List.mem_map_of_mem hd)) hne).1
            d0 o0 l0 s ha
    · simp only [Entry.vdeps, hos, ↓reduceIte, List.nil_append, roots, List.map_append,
        List.mem_append] at hr
      by_cases hrx : r = x
      · exact Or.inl ⟨hrx, by rw [hm]; rfl⟩
      · refine Or.inr ⟨hrx, ?_⟩
        rcases hr with hr | hr
        · obtain ⟨dep, hd, rfl⟩ := List.mem_map.mp hr
          obtain ⟨Er, hEr, hro⟩ := hrootH dep hd
          exact kill_root hEr hro
        · obtain ⟨Er, hEr, hro⟩ := hp.root r hr
          exact kill_root hEr hro

/-- Removing a borrowed slot leaves every other root's memory as it was. -/
theorem rootKeep_rmbor {m : Mem} {p : Var} {w : Option Val} (hp : m.st p = some ⟨false, w⟩)
    {r : Var} (hr : r ≠ p) : RootKeep m (m.remove p) r := by
  have hown : ∀ o T, OwnedAt m o T → OwnedAt (m.remove p) o T := fun o T hT => by
    refine ownedAt_remove.mpr ⟨fun h => ?_, hT⟩
    subst h; unfold OwnedAt at hT; rw [hp] at hT; cases hT
  intro n hn
  rcases hn with hn | ⟨c, hc, o, T, hT, hs, hnode⟩ | ⟨d, o', l, hc, o, T, hT, hs, hdata⟩
  · exact Or.inl (by simp [upd_ne _ _ hr, hn])
  · exact Or.inr (Or.inl ⟨c, by simp [upd_ne _ _ hr, hc], o, T, hown o T hT, hs, hnode⟩)
  · exact Or.inr (Or.inr ⟨d, o', l, by simp [upd_ne _ _ hr, hc], o, T, hown o T hT, hs, hdata⟩)

theorem mem_reroot_of_ne {p : Var} {D ds : List Dep} {dep : Dep} (hd : dep ∈ ds) (hne : dep.root ≠ p) :
    dep ∈ reroot p D ds := by
  unfold reroot
  exact List.mem_flatMap.mpr ⟨dep, hd, by simp [hne]⟩

theorem mem_reroot_of_eq {p : Var} {D ds : List Dep} {k : Kind} (hd : ⟨p, k⟩ ∈ ds) {d' : Dep}
    (hd' : d' ∈ D) : ⟨d'.root, comp d'.kind k⟩ ∈ reroot p D ds := by
  unfold reroot
  exact List.mem_flatMap.mpr ⟨⟨p, k⟩, hd, by simp; exact ⟨d', hd', rfl, rfl⟩⟩

theorem mem_reroot {p : Var} {D ds : List Dep} {dep : Dep} (h : dep ∈ reroot p D ds) :
    (dep ∈ ds ∧ dep.root ≠ p) ∨ ∃ k d', ⟨p, k⟩ ∈ ds ∧ d' ∈ D ∧ dep = ⟨d'.root, comp d'.kind k⟩ := by
  unfold reroot at h
  obtain ⟨d0, hd0, hin⟩ := List.mem_flatMap.mp h
  by_cases hr : d0.root = p
  · simp only [hr, ↓reduceIte, List.mem_map] at hin
    obtain ⟨d', hd', rfl⟩ := hin
    obtain ⟨r, k⟩ := d0; simp only at hr; subst hr
    exact Or.inr ⟨k, d', hd0, hd', rfl⟩
  · simp only [hr, ↓reduceIte, List.mem_singleton] at hin
    subst hin; exact Or.inl ⟨hd0, hr⟩

/-- What `p`'s slot reaches is reached through `p`'s own path. -/
theorem rootb_lands {m : Mem} (hh : HeapOK m) {p : Var} {E : Entry} {w : Val}
    (hp : m.st p = some ⟨false, some w⟩) (hok : ValOK m E.ty w E.path E.held) {n0 : Val}
    (hr : RootNode m p n0) : ∃ d' ∈ E.path, ∃ n1, RootNode m d'.root n1 ∧ Lands d'.kind n0 n1 := by
  rcases hr with h | ⟨c, hc, hn⟩ | ⟨d, o, l, hc, hn⟩
  · rw [hp] at h; cases h
  · rw [hp] at hc; cases hc
    cases hty : E.ty with
    | int => rw [hty] at hok; obtain ⟨_, h⟩ := hok; cases h
    | slice t => rw [hty] at hok; obtain ⟨_, _, _, h, _⟩ := hok; cases h
    | vec t =>
      rw [hty] at hok
      obtain ⟨c', hc', dep, hd, n1, d, es, hr1, hl, _, _⟩ := hok
      injection hc' with hcc; subst hcc
      obtain ⟨o, T, hoT, hsT⟩ := hr1.owned
      have := nodeAt_unique hh hn ⟨o, T, hoT, hl.sub.trans hsT, t, d, es, rfl⟩
      subst this
      exact ⟨dep, hd, n1, hr1, hl⟩
  · rw [hp] at hc; cases hc
    cases hty : E.ty with
    | int => rw [hty] at hok; obtain ⟨_, h⟩ := hok; cases h
    | vec t => rw [hty] at hok; obtain ⟨_, h, _⟩ := hok; cases h
    | slice t =>
      rw [hty] at hok
      obtain ⟨d', o', l', hv', dep, hd, ha⟩ := hok
      injection hv' with hdd; subst hdd
      obtain ⟨n1, c, es, hr1, hl, _, _⟩ := ha
      have hl' : Lands dep.kind (.node t c d es) n1 := by
        rcases hl with ⟨h1, h2⟩ | ⟨h1, h2⟩
        · exact Or.inr (Or.inl ⟨h1, h2⟩)
        · exact Or.inr (Or.inr ⟨h1, h2⟩)
      obtain ⟨o2, T, hoT, hsT⟩ := hr1.owned
      have := dataAt_unique hh hn ⟨o2, T, hoT, hl'.sub.trans hsT, t, c, es, rfl⟩
      subst this
      exact ⟨dep, hd, n1, hr1, hl'⟩

section rbind
variable {m : Mem} {p : Var} {Ep : Entry} {w : Val}

/-- What depended on `p` in way `k` now depends on what `p` borrowed. -/
theorem reroot_vkeep (hh : HeapOK m) (hp : m.st p = some ⟨false, some w⟩)
    (hok : ValOK m Ep.ty w Ep.path Ep.held) (hlt : ∀ d' ∈ Ep.path, d'.root ≠ p)
    {ds : List Dep} {dep : Dep} (hd : dep ∈ ds) {d o l : Nat} {s : Ty}
    (ha : ViewAt m dep d o l s) : ∃ dep' ∈ reroot p Ep.path ds, ViewAt (m.remove p) dep' d o l s := by
  obtain ⟨n0, c, es, hr, hk, hl, hlen, hw⟩ := viewAt_iff.mp ha
  by_cases hrp : dep.root = p
  · obtain ⟨r, k⟩ := dep
    simp only at hrp hr hk hl; subst hrp
    obtain ⟨d', hd', n1, hr1, hl1⟩ := rootb_lands hh hp hok hr
    refine ⟨⟨d'.root, comp d'.kind k⟩, mem_reroot_of_eq hd hd', viewAt_iff.mpr ⟨n1, c, es,
      rootKeep_rmbor hp (hlt d' hd') n1 hr1, comp_ne_self hk, lands_comp' hl1 hl, hlen, hw⟩⟩
  · exact ⟨dep, mem_reroot_of_ne hd hrp, viewAt_iff.mpr ⟨n0, c, es, rootKeep_rmbor hp hrp n0 hr, hk,
      hl, hlen, hw⟩⟩

theorem reroot_views (hh : HeapOK m) (hp : m.st p = some ⟨false, some w⟩)
    (hok : ValOK m Ep.ty w Ep.path Ep.held) (hlt : ∀ d' ∈ Ep.path, d'.root ≠ p)
    {τ : Ty} {T : Val} {H : List Dep} (hv : ViewsOK m τ T H) :
    ViewsOK (m.remove p) τ T (reroot p Ep.path H) := by
  intro s v hin
  obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := hv s v hin
  obtain ⟨dep', hd', ha'⟩ := reroot_vkeep hh hp hok hlt hd ha
  exact ⟨d, o, l, rfl, dep', hd', ha'⟩

theorem reroot_valOK (hh : HeapOK m) (hp : m.st p = some ⟨false, some w⟩)
    (hok : ValOK m Ep.ty w Ep.path Ep.held) (hlt : ∀ d' ∈ Ep.path, d'.root ≠ p)
    {τ : Ty} {v : Val} {P H : List Dep} (hv : ValOK m τ v P H) :
    ValOK (m.remove p) τ v (reroot p Ep.path P) (reroot p Ep.path H) := by
  cases τ with
  | int => exact hv
  | slice t =>
    obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := hv
    obtain ⟨dep', hd', ha'⟩ := reroot_vkeep hh hp hok hlt hd ha
    exact ⟨d, o, l, rfl, dep', hd', ha'⟩
  | vec t =>
    obtain ⟨c, rfl, dep, hd, n0, d, es, hr, hl, hw, hvs⟩ := hv
    have hvs' := reroot_views hh hp hok hlt hvs
    by_cases hrp : dep.root = p
    · obtain ⟨r, k⟩ := dep
      simp only at hrp hr hl; subst hrp
      obtain ⟨d', hd', n1, hr1, hl1⟩ := rootb_lands hh hp hok hr
      exact ⟨c, rfl, ⟨d'.root, comp d'.kind k⟩, mem_reroot_of_eq hd hd', n1, d, es,
        rootKeep_rmbor hp (hlt d' hd') n1 hr1, lands_comp' hl1 hl, hw, hvs'⟩
    · exact ⟨c, rfl, dep, mem_reroot_of_ne hd hrp, n0, d, es, rootKeep_rmbor hp hrp n0 hr, hl, hw, hvs'⟩

end rbind

theorem reroot_id {p : Var} {D ds : List Dep} (h : ∀ d ∈ ds, d.root ≠ p) : reroot p D ds = ds := by
  induction ds with
  | nil => rfl
  | cons d ds ih =>
    unfold reroot at ih ⊢
    simp only [List.flatMap_cons, h d (by simp), ↓reduceIte, List.singleton_append]
    rw [ih (fun d' hd' => h d' (by simp [hd']))]

theorem vdeps_reroot {p : Var} {D : List Dep} {E : Entry} :
    (rerootE p D E).vdeps = reroot p D E.vdeps := by
  unfold Entry.vdeps rerootE reroot
  simp only
  split <;> simp [List.flatMap_append]

/-- A borrowed parameter that does not depend on `p` is untouched by `p`'s
    rerooting. -/
theorem rerootE_rootb {Γ : Ctx} {F : List Var}
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    {p : Var} (hpF : p ∉ F) (D : List Dep) {v : Var} {E : Entry} (hE : Γ v = some E)
    (hmE : E.mode = .rootb) : rerootE p D E = E := by
  have : ∀ d ∈ E.vdeps, d.root ≠ p := fun d hd h => hpF (h ▸ hanch v E hE hmE d.root
    (List.mem_map_of_mem hd))
  have hos' : E.mode.ownSlot = false := by rw [hmE]; rfl
  have h1 : ∀ d ∈ E.path, d.root ≠ p := fun d hd => this d (by simp [Entry.vdeps, hos', hd])
  have h2 : ∀ d ∈ E.held, d.root ≠ p := fun d hd => this d (by simp [Entry.vdeps, hd])
  unfold rerootE
  rw [reroot_id h1, reroot_id h2]

/-- The end of a borrowed parameter's scope. -/
theorem step_rbindExit {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    {p : Var} {Ep : Entry} (hp : Γ p = some Ep) (hm : Ep.mode = .rootb) (hpF : p ∉ F) :
    MInv (m.remove p) (exitRoot p Ep.path Γ) := by
  have hlive := hi.rootbLive p Ep hp hm
  have hos : Ep.mode.ownSlot = false := by rw [hm]; rfl
  obtain ⟨w, hw, hok⟩ := hi.bor_val hp hlive hos
  have hlt : ∀ d' ∈ Ep.path, d'.root ≠ p := by
    intro d' hd' h
    have := hi.rootbLt p Ep hp hm d'.root (by
      simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.map_append,
        List.mem_append, List.mem_map]
      exact Or.inl ⟨d', hd', rfl⟩)
    rw [h] at this; exact Nat.lt_irrefl _ this
  have hpath_vd : ∀ d' ∈ Ep.path, d'.root ∈ roots Ep.vdeps := by
    intro d' hd'
    simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.map_append,
      List.mem_append, List.mem_map]
    exact Or.inl ⟨d', hd', rfl⟩
  have getE : ∀ v E', exitRoot p Ep.path Γ v = some E' → v ≠ p →
      ∃ E, Γ v = some E ∧ E' = rerootE p Ep.path E := by
    intro v E' h hvp
    simp only [exitRoot, upd_ne _ _ hvp] at h
    cases hE : Γ v with
    | none => rw [hE] at h; cases h
    | some E => rw [hE] at h; cases h; exact ⟨E, rfl, rfl⟩
  have hnorb : ∀ v E, Γ v = some E → E.mode = .rootb → rerootE p Ep.path E = E := by
    intro v E hE hmE
    have : ∀ d ∈ E.vdeps, d.root ≠ p := fun d hd h => hpF (h ▸ hanch v E hE hmE d.root
      (List.mem_map_of_mem hd))
    have hos' : E.mode.ownSlot = false := by rw [hmE]; rfl
    have h1 : ∀ d ∈ E.path, d.root ≠ p := fun d hd => this d (by simp [Entry.vdeps, hos', hd])
    have h2 : ∀ d ∈ E.held, d.root ≠ p := fun d hd => this d (by simp [Entry.vdeps, hd])
    unfold rerootE
    rw [reroot_id h1, reroot_id h2]
  constructor
  · intro v
    by_cases hvp : v = p
    · subst hvp; simp [exitRoot]
    · simp only [exitRoot, upd_ne _ _ hvp, Mem.remove_st]
      rw [← hi.dom v]; cases Γ v <;> rfl
  · intro v E' hv'
    have hvp : v ≠ p := fun h => by subst h; simp [exitRoot] at hv'
    obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvp
    obtain ⟨sl, hsl, hok', hslot⟩ := hi.slot v E hE
    refine ⟨sl, by simp [upd_ne _ _ hvp, hsl], hok', ?_⟩
    obtain ⟨ho, hown, hbor⟩ := hslot
    refine ⟨ho, fun hos' => ?_, fun hos' hl => ?_⟩
    · obtain ⟨h1, h2, h3⟩ := hown hos'
      exact ⟨h1, h2, fun hl => by
        obtain ⟨T, hT, hv⟩ := h3 hl
        exact ⟨T, hT, reroot_views hi.heap hw hok hlt hv⟩⟩
    · obtain ⟨u, hu, hv⟩ := hbor hos' hl
      exact ⟨u, hu, reroot_valOK hi.heap hw hok hlt hv⟩
  · exact hi.heap.remove hw DropSlot.borrowed
  · intro v hv
    by_cases hvp : v = p
    · subst hvp; simp at hv
    · simp only [Mem.remove_st, upd_ne _ _ hvp] at hv; exact hi.nvSt v hv
  · intro v E' b hv'
    have hvp : v ≠ p := fun h => by subst h; simp [exitRoot] at hv'
    obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvp
    exact hi.noInout v E b hE
  · intro v E' hv' hl hn r hr
    have hvp : v ≠ p := fun h => by subst h; simp [exitRoot] at hv'
    obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvp
    rw [vdeps_reroot] at hr
    obtain ⟨dep, hd, rfl⟩ := List.mem_map.mp hr
    have hroot' : ∀ r, (∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) → r ≠ p →
        ∃ Er, exitRoot p Ep.path Γ r = some Er ∧ Er.mode.isRoot = true := by
      intro r ⟨Er, hEr, hro⟩ hrp
      exact ⟨rerootE p Ep.path Er, by simp [exitRoot, upd_ne _ _ hrp, hEr], hro⟩
    rcases mem_reroot hd with ⟨hd0, hne⟩ | ⟨k, d', hpk, hd', rfl⟩
    · exact hroot' _ (hi.wf v E hE hl hn _ (List.mem_map_of_mem hd0)) hne
    · exact hroot' _ (hi.wf p Ep hp hlive (Or.inr hm) _ (hpath_vd d' hd')) (hlt d' hd')
  · intro q E' hq hmq
    have hqp : q ≠ p := fun h => by subst h; simp [exitRoot] at hq
    obtain ⟨E, hE, rfl⟩ := getE q E' hq hqp
    rw [hnorb q E hE hmq]
    exact hi.rootbLive q E hE hmq
  · intro q E' hq hmq
    have hqp : q ≠ p := fun h => by subst h; simp [exitRoot] at hq
    obtain ⟨E, hE, rfl⟩ := getE q E' hq hqp
    rw [hnorb q E hE hmq]
    exact hi.rootbLt q E hE hmq

end A1