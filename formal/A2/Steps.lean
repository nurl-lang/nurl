import A2.Rhs

/-! A2 — the memory side of each step. -/

namespace A2

/-- A slot that was there before keeps its contents: every root reaches the
    same memory. -/
theorem rootKeep_ext {m m' : Mem} (h : ∀ o, m.st o ≠ none → m'.st o = m.st o) (r : Var) :
    RootKeep m m' r := by
  intro n hn
  have hown : ∀ o T, OwnedAt m o T → OwnedAt m' o T := fun o T hT => by
    unfold OwnedAt at *; rw [h o (by rw [hT]; simp)]; exact hT
  rcases hn with ⟨T0, hn, ht⟩ | ⟨v, c, hc, ht, o, T, hT, hs, hnode⟩ |
      ⟨v, d, o', l, hc, ht, o, T, hT, hs, hdata⟩
  · exact Or.inl ⟨T0, by rw [h r (by rw [hn]; simp)]; exact hn, ht⟩
  · exact Or.inr (Or.inl ⟨v, c, by rw [h r (by rw [hc]; simp)]; exact hc, ht, o, T, hown o T hT, hs, hnode⟩)
  · exact Or.inr (Or.inr ⟨v, d, o', l, by rw [h r (by rw [hc]; simp)]; exact hc, ht, o, T, hown o T hT, hs,
      hdata⟩)

theorem SlotOK.ext {m m' : Mem} (h : ∀ o, m.st o ≠ none → m'.st o = m.st o) {E : Entry} {sl : Slot}
    (hs : SlotOK m E sl) (hb : m'.blk = m.blk := by rfl) : SlotOK m' E sl :=
  hs.keep (fun dep _ => ⟨(rootKeep_ext h dep.root).vkeep, (rootKeep_ext h dep.root).hkeep⟩) hb

/-- Binding a fresh variable to what a right-hand side produced. -/
theorem MInv.add {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} (hx : Γ x = none) (hxn : x < m.nv)
    {E : Entry} {v : Val} {o : Bool} (hout : RhsOut m Γ E v o)
    (harm : E.dtor = true → E.dbind = true := by intro h; simp_all)
    (hview : E.dbind = true → E.ty.holdsView = true := by intro h; simp_all)
    (hfl : E.dbind = true → E.dtor = true := by intro h; simp_all) :
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
        · exact ⟨(rootKeep_ext hext dep.root).vkeep, (rootKeep_ext hext dep.root).hkeep⟩
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
                · exact h)
              self := fun o' T hT => hi.heap.self o' T (by
                rcases ownedAt_set.mp hT with ⟨_, h⟩ | ⟨_, h⟩
                · cases h
                · exact h) }
    | true =>
      have hown : E.mode = .own := by
        rcases hout.mode with h | h
        · exact h
        · have := hout.own; rw [h] at this; cases this
      obtain ⟨_, _, _, hnd, hal, hdis, hsf⟩ := hout.valOwn hown
      refine hi.heap.put (x := x) (T := v) _ (fun o' U hU => ?_) (fun U hU => by
          unfold OwnedAt at hU; rw [hmx] at hU; cases hU) hnd hsf hal hdis (fun _ _ _ _ _ => rfl)
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
  · refine ⟨?live, ?dtorc, ?armc, ?viewc⟩
    case armc =>
      intro w Ew hw hd
      by_cases hwx : w = x
      · subst hwx; simp only [setE, upd_same, Option.some.injEq] at hw; subst hw; exact harm hd
      · simp only [setE, upd_ne _ _ hwx] at hw; exact hi.wf.arm w Ew hw hd
    case viewc =>
      intro w Ew hw hd
      by_cases hwx : w = x
      · subst hwx; simp only [setE, upd_same, Option.some.injEq] at hw; subst hw; exact hview hd
      · simp only [setE, upd_ne _ _ hwx] at hw; exact hi.wf.view w Ew hw hd
    case dtorc =>
      intro w Ew hw hd hos hn d hdd hnm
      by_cases hwx : w = x
      · subst hwx
        simp only [setE, upd_same, Option.some.injEq] at hw
        subst hw
        have hn' : E.ty ≠ .int := by
          rcases hn with h | h
          · exact h
          · rcases hout.mode with h' | h' <;> rw [h'] at h <;> cases h
        obtain ⟨Er, hEr, hro⟩ := hout.wf hn' d.root (List.mem_map_of_mem hdd)
        exact ⟨Er, by simp [setE, upd_ne _ _ (hroot d.root Er hEr), hEr], hro⟩
      · simp only [setE, upd_ne _ _ hwx] at hw
        obtain ⟨Er, hEr, hro⟩ := hi.wf.dtor w Ew hw hd hos hn d hdd hnm
        exact ⟨Er, by simp [setE, upd_ne _ _ (hroot d.root Er hEr), hEr], hro⟩
    intro w Ew hw hl hn r hr
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
  · have hΓ : ∀ r Er, Γ r = some Er → Er.live = true → Er.held = [] → Er.mode.ownSlot = true →
        ∃ Er', setE Γ x E r = some Er' ∧ Er'.live = true ∧ Er'.held = [] ∧ Er'.ty = Er.ty ∧ Er'.mode = Er.mode :=
      fun r Er hEr hl hh _ => ⟨Er, by simp [setE, upd_ne _ _ (hroot r Er hEr), hEr], hl, hh, rfl, rfl⟩
    intro w Ew hw hl hn
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw
      exact (hout.names hn).transport (fun r Er _ => hΓ r Er) (List.Subset.refl _)
    · simp only [setE, upd_ne _ _ hwx] at hw
      exact (hi.names w Ew hw hl hn).transport (fun r Er _ => hΓ r Er) (List.Subset.refl _)
  · intro w Ew sl T hw hl hsl hT
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw
      simp only [Mem.set_st, upd_same, Option.some.injEq] at hsl
      subst hsl; cases hT; exact hout.held
    · simp only [setE, upd_ne _ _ hwx] at hw
      simp only [Mem.set_st, upd_ne _ _ hwx] at hsl
      exact hi.held w Ew sl T hw hl hsl hT
  · intro w sl T hsl hT
    by_cases hwx : w = x
    · subst hwx
      simp only [Mem.set_st, upd_same, Option.some.injEq] at hsl
      subst hsl; cases hT; exact hout.pkgs
    · simp only [Mem.set_st, upd_ne _ _ hwx] at hsl
      exact hi.pkgs w sl T hsl hT
  · -- A2-drop.2: an armed binding's value, the new one's from the right-hand side
    intro w Ew sl hw hsl
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw
      simp only [Mem.set_st, upd_same, Option.some.injEq] at hsl
      subst hsl
      intro hd hos T hT
      cases hT
      have hown : E.mode = .own := by
        rcases hout.mode with h | h
        · exact h
        · rw [h] at hos; cases hos
      obtain ⟨_, _, hvs, _⟩ := hout.valOwn hown
      exact ⟨hfl hd, hvs.keep fun dep _ => (rootKeep_ext hext dep.root).vkeep⟩
    · simp only [setE, upd_ne _ _ hwx] at hw
      have hsl0 : m.st w = some sl := by simpa [Mem.set_st, upd_ne _ _ hwx] using hsl
      exact (hi.armed w Ew sl hw hsl0).keep fun _ _ _ dep _ => (rootKeep_ext hext dep.root).vkeep

theorem hanch_of {Γ Γ1 : Ctx} {F : List Var}
    (hanch : RootbAnch Γ F)
    (hcm : ∀ x E1, Γ1 x = some E1 → ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode ∧ E1.ty = E0.ty)
    (hrb : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → Γ1 p = some Ep) :
    RootbAnch Γ1 F := by
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
      (∀ o U, OwnedAt m o U → ∀ i ∈ T.ids, i ∉ U.ids) ∧ SelfFree T) :
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
  refine ⟨fun o U hU => ?_, fun o1 o2 U1 U2 hne h1 h2 => ?_, fun o U hU => ?_, fun o U hU => ?_⟩
  · rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
    · exact (hput rfl U rfl).1
    · exact hh.nodup o U h
  · rcases hown o1 U1 h1 with ⟨rfl, rfl⟩ | ⟨ho1, h1'⟩ <;> rcases hown o2 U2 h2 with ⟨rfl, h2e⟩ | ⟨ho2, h2'⟩
    · exact absurd rfl hne
    · exact (hput rfl U1 rfl).2.2.1 o2 U2 h2'
    · cases h2e; exact fun i hi hi' => (hput rfl U2 rfl).2.2.1 o1 U1 h1' i hi' hi
    · exact hh.disj o1 o2 U1 U2 hne h1' h2'
  · intro i hi
    rcases hown o U hU with ⟨rfl, rfl⟩ | ⟨ho, h⟩
    · obtain ⟨_, hal, hdis, _⟩ := hput rfl U rfl
      refine ⟨?_, (hal i hi).2⟩
      show a' i = true
      rw [hfr i fun T hT => ?_]
      · exact (hal i hi).1
      · subst hT; exact hdis o T hx i hi
    · obtain ⟨ha, hlt⟩ := hh.alloc o U h i hi
      exact ⟨by show a' i = true; rw [hsep o U ho h i hi]; exact ha, hlt⟩
  · rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
    · exact (hput rfl U rfl).2.2.2
    · exact hh.self o U h

theorem keep_notx {m m' : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    {x : Var} (hxF : x ∉ F) (hst : ∀ o, o ≠ x → m'.st o = m.st o) {dep : Dep}
    (hr : ∃ Er, Γ dep.root = some Er ∧ Er.mode.isRoot = true) (hne : dep.root ≠ x) :
    VKeep m m' dep ∧ HKeep m m' dep := by
  obtain ⟨Er, hEr, hroot⟩ := hr
  have hk := rootKeep_frame hi hanch (fun o ho => hst o (fun h => hxF (h ▸ ho))) hEr hroot (hst _ hne)
  exact ⟨hk.vkeep, hk.hkeep⟩

theorem vdeps_mode {E : Entry} {md : Mode} (h : md.ownSlot = E.mode.ownSlot) :
    ({ E with mode := md } : Entry).vdeps = E.vdeps := by
  simp [Entry.vdeps, h]

/-- The pushed element: valid where it is going, and not part of any tree
    an owner still has. -/
structure Pushed (m1 : Mem) (Γ1 : Ctx) (t : Ty) (v : Val) (D : List Dep) : Prop where
  wf   : WFv t v
  vs   : ViewsOK m1 t v D
  nd   : v.ids.Nodup
  al   : ∀ i ∈ v.ids, m1.alloc i = true ∧ i < m1.nid
  dis  : ∀ o U, OwnedAt m1 o U → ∀ i ∈ v.ids, i ∉ U.ids
  root : ∀ r ∈ roots D, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true
  sf   : SelfFree v
  nin  : NamesIn v D
  pk   : PkgsOK v
  nok  : DepsNamed Γ1 D

/-- What an element of a type that holds no views holds is nothing. -/
theorem Pushed.ownHeld {m1 : Mem} {Γ1 : Ctx} {t : Ty} {v : Val} {D : List Dep} (h : Pushed m1 Γ1 t v D) :
    Pushed m1 Γ1 t v (ownHeld true t D) :=
  ⟨h.wf, h.vs.ownHeld true, h.nd, h.al, h.dis, fun r hr => h.root r (ownHeld_roots hr), h.sf,
    h.nin.ownHeld h.wf true, h.pk, fun d hd => h.nok d (ownHeld_sub _ _ _ hd)⟩

/-- Taking the value `vec_push` stores: an element `Vec` moves out of its
    binding, anything else is copied. -/
theorem push_take {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    {y : Var} {Ey : Entry} {t : Ty} {D : List Dep} (hy : Γ y = some Ey) (hl : Ey.live = true)
    (hty : Ey.ty = t) (hpa : PushArg Γ F y Ey t D Γ1) {v : Val} (htk : TakeVal m y v m1) :
    RhsPost m m1 Γ Γ1 F ∧ Pushed m1 Γ1 t v D := by
  cases hpa with
  | move ho hm hyF hpin hds =>
    cases htk with
    | own hv =>
      obtain ⟨post, out⟩ := rhs_move hi hanch hy hl hm hyF hpin hv hds
      obtain ⟨_, hwf, hvs, hnd, hal, hdis, hsf⟩ := out.valOwn rfl
      have hnint : Ey.ty ≠ .int := fun h => by rw [hty] at h; rw [h] at ho; cases ho
      refine ⟨post, Pushed.mk (hty ▸ hwf) (hty ▸ hvs) hnd hal hdis (fun r hr => ?_) hsf out.held out.pkgs
        (by have := out.names (Or.inl hnint); simpa [NameOK, Entry.vdeps, Mode.ownSlot] using this)⟩
      exact out.wf hnint r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)
    | bor hv =>
      obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
      rw [hT] at hv; cases hv
  | int =>
    have hnown : Ey.mode.ownSlot = false := by
      cases h : Ey.mode.ownSlot with
      | false => rfl
      | true =>
        obtain ⟨_, _, _, _, hown, _⟩ := hi.slot y Ey hy
        obtain ⟨ht', _⟩ := hown h
        rw [hty] at ht'; cases ht'
    obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl hnown
    cases htk with
    | own hv => rw [hw] at hv; cases hv
    | bor hv =>
      rw [hw] at hv; cases hv
      rw [hty] at hok
      obtain ⟨n, rfl⟩ := valOK_int.mp hok
      exact ⟨RhsPost.same hi, Pushed.mk WFv.int (fun _ _ h => (by cases h)) (by simp) (by simp)
        (by simp) (by simp [roots]) (selfFree_int n) (NamesIn.nil _ rfl)
        (PkgsOK.leaf (fun _ h => by cases h) (fun _ _ _ _ _ h => by cases h)) (DepsNamed.nil _)⟩
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
      obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := valOK_slice.mp hok
      have hnint : Ey.ty ≠ .int := by rw [hty]; simp
      have hN := hi.names y Ey hy hl (Or.inl hnint)
      refine ⟨RhsPost.same hi, Pushed.mk WFv.view (fun s' v' hin => ?_) (by simp) (by simp)
        (by simp) ?_ (selfFree_view d o l) (NamesIn.nil _ rfl)
        (PkgsOK.leaf (fun _ h => by cases h) (fun _ _ _ _ _ h => by cases h))
        ((derive_named hN rfl).append hN.held)⟩
      · cases hin
        exact ⟨d, o, l, rfl, dep, List.mem_append_left _ hd, ha⟩
      · exact wf_append (wf_derive hi hy hl hnint _) (wf_held hi hy hl hnint)

theorem RhsPost.trans {m m1 m2 : Mem} {Γ Γ1 Γ2 : Ctx} {F : List Var} (h1 : RhsPost m m1 Γ Γ1 F)
    (h2 : RhsPost m1 m2 Γ1 Γ2 F) : RhsPost m m2 Γ Γ2 F where
  inv := h2.inv
  nv := h2.nv.trans h1.nv
  nid := Nat.le_trans h1.nid h2.nid
  dom x := (h2.dom x).trans (h1.dom x)
  frz x hx := (h2.frz x hx).trans (h1.frz x hx)
  rootb p Ep hp hm := h2.rootb p Ep (h1.rootb p Ep hp hm) hm
  cdom x := (h2.cdom x).trans (h1.cdom x)
  cmode x E2 h := by
    obtain ⟨E1, h1', hm1, ht1⟩ := h2.cmode x E2 h
    obtain ⟨E0, h0, hm0, ht0⟩ := h1.cmode x E1 h1'
    exact ⟨E0, h0, hm1.trans hm0, ht1.trans ht0⟩
  dkeep := h1.dkeep.trans h2.dkeep (fun _ h => h)

theorem RhsPost.root {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} (h : RhsPost m m1 Γ Γ1 F) {r : Var}
    (hr : ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) : ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true := by
  obtain ⟨Er, hEr, hro⟩ := hr
  have hd := h.cdom r; rw [hEr] at hd
  obtain ⟨E1, h1⟩ := Option.isSome_iff_exists.mp hd
  obtain ⟨E0, h0, hm, _⟩ := h.cmode r E1 h1
  rw [hEr] at h0; cases h0
  exact ⟨E1, h1, by rw [hm]; exact hro⟩

theorem RhsPost.fwd {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} (h : RhsPost m m1 Γ Γ1 F) {r : Var}
    {Er : Entry} (hr : Γ r = some Er) : ∃ E1, Γ1 r = some E1 ∧ E1.ty = Er.ty ∧ E1.mode = Er.mode := by
  have hd := h.cdom r; rw [hr] at hd
  obtain ⟨E1, h1⟩ := Option.isSome_iff_exists.mp hd
  obtain ⟨E0, h0, hm, ht⟩ := h.cmode r E1 h1
  rw [hr] at h0; cases h0
  exact ⟨E1, h1, ht, hm⟩

/-- What `D` holds by name stays so past an argument taken from `z`, when it
    names no `z` that moves. -/
theorem DepsNamed.pushArg {Γ Γ1 : Ctx} {F : List Var} {D : List Dep} (hd : DepsNamed Γ D)
    {z : Var} {Ez : Entry} {b : Ty} {Dz : List Dep} (hpa : PushArg Γ F z Ez b Dz Γ1)
    (hzd : Ez.mode.ownSlot = true → z ∉ roots D) : DepsNamed Γ1 D := by
  cases hpa with
  | int => exact hd
  | slice => exact hd
  | move _ hm _ _ =>
    intro d hdD b t hk
    obtain ⟨Er, hEr, hl, hh, ht, ho, hc⟩ := hd d hdD b t hk
    have hne : d.root ≠ z := fun h => hzd (by rw [hm]; rfl) (h ▸ List.mem_map_of_mem hdD)
    exact ⟨Er, by simp [setE, upd_ne _ _ hne, kill, hEr, killE_nil (root_vdeps ho hh)], hl, hh, ht, ho, hc⟩

/-- A stored view is a `ViewIn` of its tree. -/
theorem WFv.sub_view {τ : Ty} {T : Val} (hw : WFv τ T) {d o l : Nat} (hs : Sub (.view d o l) T) :
    ∃ s, ViewIn τ T s (.view d o l) := by
  induction hw with
  | int => cases hs
  | @view t d' o' l' => cases hs; exact ⟨t, ViewIn.here⟩
  | node hes ih =>
    rcases hs.cases' with h | ⟨e, hc, hs'⟩
    · cases h
    · cases hc with
      | elem he => obtain ⟨s, h⟩ := ih e he hs'; exact ⟨s, ViewIn.child he h⟩
  | pair _ _ iha ihb =>
    rcases hs.cases' with h | ⟨e, hc, hs'⟩
    · cases h
    · cases hc with
      | fst => obtain ⟨s, h⟩ := iha hs'; exact ⟨s, ViewIn.fst h⟩
      | snd => obtain ⟨s, h⟩ := ihb hs'; exact ⟨s, ViewIn.snd h⟩
  | inl _ ih =>
    rcases hs.cases' with h | ⟨e, hc, hs'⟩
    · cases h
    · cases hc with
      | inl => obtain ⟨s, h⟩ := ih hs'; exact ⟨s, ViewIn.inl h⟩
  | inr _ ih =>
    rcases hs.cases' with h | ⟨e, hc, hs'⟩
    · cases h
    · cases hc with
      | inr => obtain ⟨s, h⟩ := ih hs'; exact ⟨s, ViewIn.inr h⟩
  | pkg _ ih =>
    rcases hs.cases' with h | ⟨e, hc, hs'⟩
    · cases h
    · cases hc with
      | pkg => obtain ⟨s, h⟩ := ih hs'; exact ⟨s, ViewIn.pkg h⟩

/-- A valid view points into a buffer some owner holds. -/
theorem ViewAt.owned {m : Mem} {dep : Dep} {d o l : Nat} {s : Ty} (h : ViewAt m dep d o l s) :
    ∃ x T, OwnedAt m x T ∧ d ∈ T.ids := by
  obtain ⟨n0, c, es, hr, hk, _, _⟩ := h
  obtain ⟨x, T, hT, hs⟩ := hr.owned
  have hsub : Sub (.node s c d es) n0 := by
    rcases hk with ⟨_, h⟩ | ⟨_, h⟩
    · rw [h]; exact Sub.refl _
    · exact h.sub
  exact ⟨x, T, hT, (hsub.trans hs).ids d (by simp)⟩

/-- A tree whose views all point into memory owners hold, put together with
    one whose addresses no owner holds, does not view itself across them. -/
theorem selfFree_apart {m : Mem} {τ : Ty} {v w : Val} (hw : WFv τ v) {H : List Dep}
    (hvs : ViewsOK m τ v H) (hdis : ∀ o U, OwnedAt m o U → ∀ i ∈ w.ids, i ∉ U.ids) :
    ∀ d o l, Sub (.view d o l) v → ∀ u c es, ¬ Sub (.node u c d es) w := by
  intro d o l hv u c es hn
  obtain ⟨s, hin⟩ := hw.sub_view hv
  obtain ⟨d', o', l', hvv, dep, _, ha⟩ := hvs s _ hin
  cases hvv
  obtain ⟨x, T, hT, hd⟩ := ha.owned
  exact hdis x T hT d (hn.ids d (by simp)) hd

/-- A struct literal: its fields, taken from their bindings, owned by the
    struct. -/
theorem out_pair {m1 m2 : Mem} {Γ1 Γ2 : Ctx} {F : List Var} (hi1 : MInv m1 Γ1)
    (hanch1 : RootbAnch Γ1 F)
    {z : Var} {Ez : Entry} {a b : Ty} {Dy Dz : List Dep} {v w : Val}
    (pu1 : Pushed m1 Γ1 a v Dy) (post2 : RhsPost m1 m2 Γ1 Γ2 F) (pu2 : Pushed m2 Γ2 b w Dz)
    (hz : Γ1 z = some Ez) (hlz : Ez.live = true) (hbz : Ez.ty = b)
    (hpa2 : PushArg Γ1 F z Ez b Dz Γ2) (htk2 : TakeVal m1 z w m2)
    (hzd : Ez.mode.ownSlot = true → z ∉ roots Dy) (hok : a.ok = true ∧ b.ok = true) :
    RhsOut m2 Γ2 ⟨.prod a b, .own, true, [], Dy ++ Dz, false, false⟩ (.pair v w) true := by
  -- an owned slot holds a value of an owning type
  have own_ty : ∀ {x : Val}, m1.st z = some ⟨true, some x⟩ → b.owning = true := by
    intro x hx
    obtain ⟨sl, hsl, _, hso, hown, _⟩ := hi1.slot z Ez hz
    rw [hx] at hsl; cases hsl
    rw [← hbz]; exact (hown hso.symm).1
  -- the second field moved out of its owner, or was copied and owns nothing
  have hcase : (z ∉ F ∧ Ez.mode = .own ∧ OwnedAt m1 z w ∧ m2 = m1.set z ⟨true, none⟩) ∨
      (w.ids = [] ∧ m2 = m1) := by
    cases hpa2 with
    | move _ hm hzF =>
      cases htk2 with
      | own hv => exact Or.inl ⟨hzF, hm, hv, rfl⟩
      | bor hv =>
        obtain ⟨T, hT, _⟩ := hi1.own_val hz hlz (by rw [hm]; rfl)
        rw [hT] at hv; cases hv
    | int =>
      cases htk2 with
      | own hv => exact absurd (own_ty hv) (by simp [Ty.owning])
      | bor _ => cases pu2.wf; exact Or.inr ⟨by simp, rfl⟩
    | slice _ =>
      cases htk2 with
      | own hv => exact absurd (own_ty hv) (by simp [Ty.owning])
      | bor _ => cases pu2.wf; exact Or.inr ⟨by simp, rfl⟩
  have hown21 : ∀ o U, OwnedAt m2 o U → OwnedAt m1 o U := by
    intro o U hU
    rcases hcase with ⟨_, _, _, rfl⟩ | ⟨_, rfl⟩
    · rcases ownedAt_set.mp hU with ⟨_, h⟩ | ⟨_, h⟩
      · cases h
      · exact h
    · exact hU
  have hal21 : m2.alloc = m1.alloc ∧ m2.nid = m1.nid := by
    rcases hcase with ⟨_, _, _, rfl⟩ | ⟨_, rfl⟩ <;> exact ⟨rfl, rfl⟩
  have hvkeep : ∀ dep ∈ Dy, VKeep m1 m2 dep := by
    intro dep hd
    rcases hcase with ⟨hzF, hm, _, rfl⟩ | ⟨_, rfl⟩
    · have hne : dep.root ≠ z := fun h => hzd (by rw [hm]; rfl) (h ▸ List.mem_map_of_mem hd)
      exact (keep_notx hi1 hanch1 hzF (fun o ho => by simp [upd_ne _ _ ho])
        (pu1.root dep.root (List.mem_map_of_mem hd)) hne).1
    · exact fun _ _ _ _ h => h
  have hvs1 : ViewsOK m2 a v Dy := by
    intro s x hin
    obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := pu1.vs s x hin
    exact ⟨d, o, l, rfl, dep, hd, hvkeep dep hd d o l s ha⟩
  refine ⟨rfl, Or.inl rfl, rfl, by simp [Ty.ok, hok.1, hok.2], fun _ r hr => ?_, fun _ => ⟨rfl,
    WFv.pair pu1.wf pu2.wf, ?_, ?_, ?_, ?_, ?_⟩, (fun h => by cases h),
    fun _ => own_named ((pu1.nok.pushArg hpa2 hzd).append pu2.nok), ?_, ?_⟩
  · simp only [Entry.vdeps, Mode.ownSlot, ↓reduceIte, List.nil_append] at hr
    exact wf_append (fun r hr => post2.root (pu1.root r hr)) pu2.root r hr
  · intro s x hin
    cases hin with
    | fst h =>
      obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := hvs1 s x h
      exact ⟨d, o, l, rfl, dep, List.mem_append_left _ hd, ha⟩
    | snd h =>
      obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := pu2.vs s x h
      exact ⟨d, o, l, rfl, dep, List.mem_append_right _ hd, ha⟩
  · simp only [ids_pair, List.nodup_append]
    refine ⟨pu1.nd, pu2.nd, fun i hi j hj hij => ?_⟩
    subst hij
    rcases hcase with ⟨_, _, hzw, _⟩ | ⟨hw, _⟩
    · exact pu1.dis z w hzw i hi hj
    · rw [hw] at hj; cases hj
  · intro i hi
    simp only [ids_pair, List.mem_append] at hi
    rcases hi with hi | hi
    · rw [hal21.1, hal21.2]; exact pu1.al i hi
    · exact pu2.al i hi
  · intro o U hU i hi
    simp only [ids_pair, List.mem_append] at hi
    rcases hi with hi | hi
    · exact pu1.dis o U (hown21 o U hU) i hi
    · exact pu2.dis o U hU i hi
  · intro d o l hv u c es hn
    rcases hv.cases' with h | ⟨e1, hc1, hs1⟩
    · cases h
    rcases hn.cases' with h | ⟨e2, hc2, hs2⟩
    · cases h
    cases hc1 <;> cases hc2
    · exact pu1.sf d o l hs1 u c es hs2
    · exact selfFree_apart pu1.wf hvs1 pu2.dis d o l hs1 u c es hs2
    · exact selfFree_apart pu2.wf pu2.vs (fun o U hU i hi => pu1.dis o U (hown21 o U hU) i hi)
        d o l hs1 u c es hs2
    · exact pu2.sf d o l hs1 u c es hs2
  · intro c hc
    simp only [Val.names, List.mem_append] at hc
    rcases hc with h | h
    · exact List.mem_append_left _ (pu1.nin c h)
    · exact List.mem_append_right _ (pu2.nin c h)
  · intro fs te ms e cs hs
    rcases hs.cases' with h | ⟨e', hc, hs'⟩
    · cases h
    · cases hc with
      | fst => exact pu1.pk _ _ _ _ _ hs'
      | snd => exact pu2.pk _ _ _ _ _ hs'

/-- A field of a struct in flight, handed to the binding that takes it. -/
theorem out_part {m : Mem} {Γ : Ctx} {E : Entry} {τ t : Ty} {T x : Val}
    (hout : RhsOut m Γ ⟨τ, .own, true, [], E.held, false, false⟩ T true) (hτ : τ ≠ .int) (hwx : WFv t x)
    (hsub : Sub x T) (hvin : ∀ s v, ViewIn t x s v → ViewIn τ T s v) (hids : List.Sublist x.ids T.ids)
    (htok : t.ok = true) : RhsOut m Γ (compE E t) x x.owns := by
  obtain ⟨_, _, hvsT, hnd, hal, hdis, hsf⟩ := hout.valOwn rfl
  have hwfH : ∀ r ∈ roots E.held, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := fun r hr =>
    hout.wf hτ r (by simpa [Entry.vdeps, Mode.ownSlot] using hr)
  have hH : DepsNamed Γ E.held := by
    have := hout.names (Or.inl hτ); simpa [NameOK, Entry.vdeps, Mode.ownSlot] using this
  have hnx : NamesIn x E.held := hout.held.sub (names_sub hsub)
  have hpx : PkgsOK x := hout.pkgs.sub hsub
  have hnx' : NamesIn x (ownHeld true t E.held) := NamesIn.ownHeld hwx true hnx
  have hH' : DepsNamed Γ (ownHeld true t E.held) := hH.sub (ownHeld_sub true t E.held)
  have hwfH' : ∀ r ∈ roots (ownHeld true t E.held), ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true :=
    fun r hr => hwfH r (ownHeld_roots hr)
  cases hwx with
  | int => exact intE_out _
  | @view s d o l =>
    refine ⟨rfl, Or.inr rfl, rfl, htok, fun _ => wf_append hwfH hwfH, fun h => (by cases h), fun _ => ?_,
      fun _ => hH.append hH, hnx, hpx⟩
    obtain ⟨d', o', l', hv, dep, hd, ha⟩ := hvsT s _ (hvin s _ ViewIn.here)
    cases hv
    exact .view ⟨dep, hd, ha⟩
  | @node u c d es hes =>
    refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => hwfH' r (by simpa [Entry.vdeps, Mode.ownSlot,
      compE] using hr), fun _ => ⟨rfl, WFv.node hes, ViewsOK.ownHeld true (fun s v h => hvsT s v (hvin s v h)),
      hnd.sublist hids, fun i hi => hal i (hids.subset hi), fun o U hU i hi => hdis o U hU i (hids.subset hi),
      hsf.sub hsub⟩, (fun h => by cases h), fun _ => own_named hH', hnx', hpx⟩
  | @pair a b v w hwa hwb =>
    refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => hwfH' r (by simpa [Entry.vdeps, Mode.ownSlot,
      compE] using hr), fun _ => ⟨rfl, WFv.pair hwa hwb, ViewsOK.ownHeld true (fun s v h => hvsT s v (hvin s v h)),
      hnd.sublist hids, fun i hi => hal i (hids.subset hi), fun o U hU i hi => hdis o U hU i (hids.subset hi),
      hsf.sub hsub⟩, (fun h => by cases h), fun _ => own_named hH', hnx', hpx⟩
  | @inl a b v hwa =>
    refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => hwfH' r (by simpa [Entry.vdeps, Mode.ownSlot,
      compE] using hr), fun _ => ⟨rfl, WFv.inl hwa, ViewsOK.ownHeld true (fun s v h => hvsT s v (hvin s v h)),
      hnd.sublist hids, fun i hi => hal i (hids.subset hi), fun o U hU i hi => hdis o U hU i (hids.subset hi),
      hsf.sub hsub⟩, (fun h => by cases h), fun _ => own_named hH', hnx', hpx⟩
  | @inr a b v hwb =>
    refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => hwfH' r (by simpa [Entry.vdeps, Mode.ownSlot,
      compE] using hr), fun _ => ⟨rfl, WFv.inr hwb, ViewsOK.ownHeld true (fun s v h => hvsT s v (hvin s v h)),
      hnd.sublist hids, fun i hi => hal i (hids.subset hi), fun o U hU i hi => hdis o U hU i (hids.subset hi),
      hsf.sub hsub⟩, (fun h => by cases h), fun _ => own_named hH', hnx', hpx⟩
  | pkg hwb =>
    refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => hwfH' r (by simpa [Entry.vdeps, Mode.ownSlot,
      compE] using hr), fun _ => ⟨rfl, WFv.pkg hwb, ViewsOK.ownHeld true (fun s v h => hvsT s v (hvin s v h)),
      hnd.sublist hids, fun i hi => hal i (hids.subset hi), fun o U hU i hi => hdis o U hU i (hids.subset hi),
      hsf.sub hsub⟩, (fun h => by cases h), fun _ => own_named hH', hnx', hpx⟩

/-- An enum value: its payload, taken from its binding, owned by the enum. -/
theorem ViewIn.inl_inv {a b s : Ty} {v x : Val} (h : ViewIn (.sum a b) (.inl v) s x) : ViewIn a v s x := by
  cases h with | inl h => exact h

theorem ViewIn.inr_inv {a b s : Ty} {v x : Val} (h : ViewIn (.sum a b) (.inr v) s x) : ViewIn b v s x := by
  cases h with | inr h => exact h

/-- A value wrapped around one taken from its binding (an enum's payload, a
    package's environment), owned by what wraps it. -/
theorem out_wrap {m1 : Mem} {Γ1 : Ctx} {a : Ty} {D : List Dep} {v : Val} (pu : Pushed m1 Γ1 a v D)
    {w : Val} {τ : Ty} (htok : τ.ok = true) (hown : τ.owning = true) (hwτ : WFv τ w)
    (hvin' : ∀ s x, ViewIn τ w s x → ViewIn a v s x) (hchild : ∀ e, Child e w → e = v)
    (hids : w.ids = v.ids) (hnv : ∀ d o l, w ≠ .view d o l) (hnn : ∀ u c d es, w ≠ .node u c d es)
    {D' : List Dep} (hDD : D ⊆ D')
    (hroot : ∀ r ∈ roots D', ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true)
    (hnok : DepsNamed Γ1 D') (hnin : NamesIn w D') (hpk : PkgsOK w) :
    RhsOut m1 Γ1 ⟨τ, .own, true, [], D', false, false⟩ w true := by
  have hsub : ∀ {n : Val}, Sub n w → n = w ∨ Sub n v := by
    intro n hn
    rcases hn.cases' with h | ⟨e, hc, hs⟩
    · exact Or.inl h
    · rw [hchild e hc] at hs; exact Or.inr hs
  refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => ?_,
    fun _ => ⟨hown, hwτ, ViewsOK.mono hDD fun s x hin => pu.vs s x (hvin' s x hin), by
      rw [hids]; exact pu.nd, fun i hi => pu.al i (hids ▸ hi), fun o U hU i hi => pu.dis o U hU i (hids ▸ hi),
      fun d o l hv u c es hn => ?_⟩, (fun h => by cases h), fun _ => own_named hnok, hnin, hpk⟩
  · simp only [Entry.vdeps, Mode.ownSlot, ↓reduceIte, List.nil_append] at hr
    exact hroot r hr
  · rcases hsub hv with h | hv'
    · exact absurd h.symm (hnv d o l)
    rcases hsub hn with h | hn'
    · exact absurd h.symm (hnn u c d es)
    exact pu.sf d o l hv' u c es hn'

theorem out_inj {m1 : Mem} {Γ1 : Ctx} {a t : Ty} {D : List Dep} {v : Val} (pu : Pushed m1 Γ1 a v D)
    (ht : t.ok = true) {w : Val} (hwv : w = .inl v ∨ w = .inr v) {τ : Ty} (hτ : τ = .sum a t ∨ τ = .sum t a)
    (hwτ : WFv τ w) (hvin : ∀ s x, ViewIn a v s x → ViewIn τ w s x)
    (hvin' : ∀ s x, ViewIn τ w s x → ViewIn a v s x) (hok : a.ok = true) :
    RhsOut m1 Γ1 ⟨τ, .own, true, [], D, false, false⟩ w true := by
  have hsub : ∀ {n : Val}, Sub n w → n = w ∨ Sub n v := by
    intro n hn
    rcases hn.cases' with h | ⟨e, hc, hs⟩
    · exact Or.inl h
    · rcases hwv with rfl | rfl <;> cases hc <;> exact Or.inr hs
  have hids : w.ids = v.ids := by rcases hwv with rfl | rfl <;> simp
  refine ⟨rfl, Or.inl rfl, rfl, by rcases hτ with rfl | rfl <;> simp [Ty.ok, hok, ht], fun _ r hr => ?_,
    fun _ => ⟨by rcases hτ with rfl | rfl <;> rfl, hwτ, fun s x hin => pu.vs s x (hvin' s x hin), by
      rw [hids]; exact pu.nd, fun i hi => pu.al i (hids ▸ hi), fun o U hU i hi => pu.dis o U hU i (hids ▸ hi),
      fun d o l hv u c es hn => ?_⟩, (fun h => by cases h), fun _ => own_named pu.nok,
      fun c hc => pu.nin c (by rcases hwv with rfl | rfl <;> simpa [Val.names] using hc), ?_⟩
  · simp only [Entry.vdeps, Mode.ownSlot, ↓reduceIte, List.nil_append] at hr
    exact pu.root r hr
  · rcases hsub hv with h | hv'
    · rcases hwv with rfl | rfl <;> cases h
    rcases hsub hn with h | hn'
    · rcases hwv with rfl | rfl <;> cases h
    exact pu.sf d o l hv' u c es hn'
  · intro fs te ms e cs hs
    rcases hsub hs with h | hs'
    · rcases hwv with rfl | rfl <;> cases h
    · exact pu.pk _ _ _ _ _ hs'

theorem NoPin.of {Γ Γ1 : Ctx} {x : Var} (h : NoPin Γ x)
    (hcm : ∀ x E1, Γ1 x = some E1 → ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode ∧ E1.ty = E0.ty)
    (hrb : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → Γ1 p = some Ep) : NoPin Γ1 x := by
  intro p E hp hm
  obtain ⟨E0, h0, hm0, _⟩ := hcm p E hp
  have h1 := hrb p E0 h0 (hm0 ▸ hm)
  rw [hp] at h1; cases h1
  exact h p _ h0 hm

theorem capDeps_mem {cs : List (Var × PMode × Ty)} {d : Dep} (h : d ∈ capDeps cs) :
    ∃ c ∈ cs, d = ⟨c.1, .name c.2.1.bound c.2.2⟩ := by
  obtain ⟨c, hc, rfl⟩ := List.mem_map.mp h
  exact ⟨c, hc, rfl⟩

theorem CapsOK.named {Γ : Ctx} {F : List Var} {D : List Dep} {cs : List (Var × PMode × Ty)}
    (h : CapsOK Γ F D cs) : DepsNamed Γ (capDeps cs) := by
  intro d hd b t hk
  obtain ⟨c, hc, rfl⟩ := capDeps_mem hd
  simp only [Kind.name.injEq] at hk
  obtain ⟨rfl, rfl⟩ := hk
  obtain ⟨Ev, hEv, hl, hh, ht, ho, hhv, hmode⟩ := h.2 c hc
  refine ⟨Ev, hEv, hl, hh, ht, ho, ?_, hhv⟩
  rcases hmode with ⟨hinp, _⟩ | ⟨b, s, hb, _, hbr, hcan, _⟩
  · exact Or.inl (by rw [hinp]; rfl)
  · exact Or.inr (by rw [hb]; exact ⟨hbr, hcan⟩)

theorem rhs_pres {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} {v : Val} {o : Bool}
    (hi : MInv m Γ) (hanch : RootbAnch Γ F)
    (hr : RhsT Γ F r E Γ1) (he : EvalR m r (.ok v o m1)) :
    RhsPost m m1 Γ Γ1 F ∧ RhsOut m1 Γ1 E v o := by
  cases hr with
  | expr hx =>
    cases he with
    | expr _ => exact ⟨RhsPost.same hi, intE_out _⟩
  | new ht =>
    cases he with
    | new => exact rhs_new hi ht
  | moveOwn hy hl hm hyF hpin hds =>
    cases he with
    | moveOwn hv => exact rhs_move hi hanch hy hl hm hyF hpin hv hds
    | copy hv =>
      obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
      rw [hT] at hv; cases hv
  | copyRoot hy hl hm =>
    cases he with
    | moveOwn hv =>
      obtain ⟨w, hw, _⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
      rw [hw] at hv; cases hv
    | copy hv =>
      exact ⟨RhsPost.same hi, out_borrowWhole hi hy hl (Or.inl (by rw [hm]; rfl)) (Or.inl hv)
        (Or.inl hm)⟩
  | copyBor hy hl hm =>
    cases he with
    | moveOwn hv =>
      obtain ⟨w, hw, _⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
      rw [hw] at hv; cases hv
    | copy hv => exact ⟨RhsPost.same hi, (out_copyBor hi hy hl hm hv).setDtor false false⟩
  | borrow hy hl ht =>
    rename_i y E t
    cases he with
    | borrowOwn hv =>
      refine ⟨RhsPost.same hi, out_borrowWhole hi hy hl (Or.inr ⟨t, ht⟩) (Or.inr ⟨_, _, _, _, hv, rfl⟩) ?_⟩
      rcases hi.mode_cases hy with h | h | h
      · exact Or.inr ⟨h, t, ht⟩
      · exact Or.inl h
      · obtain ⟨w, hw, _⟩ := hi.bor_val hy hl (by rw [h]; rfl)
        rw [hw] at hv; cases hv
    | borrowBor hv =>
      rcases hi.mode_cases hy with h | h | h
      · obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rw [h]; rfl)
        rw [hT] at hv; cases hv
      · exact ⟨RhsPost.same hi, out_borrowWhole hi hy hl (Or.inl (by rw [h]; rfl)) (Or.inl hv)
          (Or.inl h)⟩
      · -- a borrow of a borrow passes on what it borrows from
        have hder : derive y E .self = E.path := by
          unfold derive
          simp only [h, Mode.isRoot, Bool.false_eq_true, ↓reduceIte]
          conv => rhs; rw [← List.map_id E.path]
          congr; funext dep; cases dep with | mk r k => cases k <;> rfl
        refine ⟨RhsPost.same hi, ?_⟩
        have hE : (⟨E.ty, .bor, true, derive y E .self, E.held, false, false⟩ : Entry) =
            { E with dtor := false, dbind := false } := by
          rw [hder]; cases E; simp_all
        rw [hE]; exact (out_copyBor hi hy hl h hv).setDtor false false
  | «at» hy hl ht hx =>
    cases he with
    | «at» hn hvec _ => exact ⟨RhsPost.same hi, out_at hi hy hl ht hn hvec⟩
  | view hy hl ht hhv =>
    cases he with
    | view hvec => exact ⟨RhsPost.same hi, out_view hi hy hl ht hhv hvec⟩
  | sat hy hl ht hx =>
    cases he with
    | sat hn hv _ _ _ hda => exact ⟨RhsPost.same hi, out_sat hi hy hl ht hn hv hda⟩
  | pop hy hl ht hcan hyF hds =>
    cases he with
    | pop hT _ _ => exact rhs_pop hi hanch hy hl ht hcan hyF hT hds

  | @pair y z Ey Ez Γ1 Γ2 Dy Dz hy hly hpa1 hz hlz hpa2 hzd =>
    cases he with
    | pair htk1 htk2 =>
      obtain ⟨post1, pu1⟩ := push_take hi hanch hy hly rfl hpa1 htk1
      have hanch1 := hanch_of hanch post1.cmode post1.rootb
      obtain ⟨post2, pu2⟩ := push_take post1.inv hanch1 hz hlz rfl hpa2 htk2
      exact ⟨post1.trans post2, out_pair post1.inv hanch1 pu1 post2 pu2 hz hlz rfl hpa2 htk2 hzd
        ⟨hi.tyok hy, post1.inv.tyok hz⟩⟩
  | fst hy hl hty =>
    cases he with
    | fst hv => exact ⟨RhsPost.same hi, out_fst hi hy hl hty hv⟩
  | snd hy hl hty =>
    cases he with
    | snd hv => exact ⟨RhsPost.same hi, out_snd hi hy hl hty hv⟩
  | @inl y b Ey Γ1 D hy hly hpa hb =>
    cases he with
    | inl htk =>
      obtain ⟨post, pu⟩ := push_take hi hanch hy hly rfl hpa htk 
      exact ⟨post, out_inj pu hb (Or.inl rfl) (Or.inl rfl) (WFv.inl pu.wf) (fun s x h => ViewIn.inl h)
        (fun s x h => ViewIn.inl_inv h) (hi.tyok hy)⟩
  | @inr a y Ey Γ1 D hy hly hpa ha =>
    cases he with
    | inr htk =>
      obtain ⟨post, pu⟩ := push_take hi hanch hy hly rfl hpa htk 
      exact ⟨post, out_inj pu ha (Or.inr rfl) (Or.inr rfl) (WFv.inr pu.wf) (fun s x h => ViewIn.inr h)
        (fun s x h => ViewIn.inr_inv h) (hi.tyok hy)⟩
  | @pack fs te ms y cs Ey Γ1 D hy hly hte hpa hcaps =>
    cases he with
    | pack htk =>
      obtain ⟨post, pu⟩ := push_take hi hanch hy hly hte hpa htk 
      refine ⟨post, out_wrap pu rfl rfl (WFv.pkg pu.wf)
        (fun s x h => by cases h with | pkg h => exact h) (fun e h => by cases h; rfl) (by simp)
        (fun _ _ _ h => by cases h) (fun _ _ _ _ h => by cases h) (List.subset_append_left _ _)
        ?_ (pu.nok.append hcaps.named) ?_ ?_⟩
      · intro r hr
        simp only [roots, List.map_append, List.mem_append] at hr
        rcases hr with hr | hr
        · exact pu.root r hr
        · obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
          obtain ⟨c, hc, rfl⟩ := capDeps_mem hd
          obtain ⟨Ev, hEv, _, _, _, ho, _⟩ := hcaps.2 c hc
          exact ⟨Ev, hEv, by cases hm : Ev.mode <;> simp_all [Mode.ownSlot, Mode.isRoot]⟩
      · intro c hc
        simp only [Val.names, List.mem_append] at hc
        rcases hc with hc | hc
        · exact List.mem_append_right _ (List.mem_map_of_mem hc)
        · exact List.mem_append_left _ (pu.nin c hc)
      · intro fs' te' ms' e' cs' hs
        rcases hs.cases' with h | ⟨e0, hc, hs'⟩
        · cases h
          refine ⟨hcaps.1, fun c hc => ?_, fun c hc c' hc' hcc => ?_⟩
          · obtain ⟨_, _, _, _, _, _, _, hmode⟩ := hcaps.2 c hc
            rcases hmode with ⟨hinp, _⟩ | ⟨b, s, hb, hbn, _⟩
            · exact Or.inl hinp
            · exact Or.inr ⟨b, hb, hbn⟩
          · obtain ⟨_, _, _, _, _, _, _, hmode⟩ := hcaps.2 c hc
            have hd : (⟨c'.1, .name c'.2.1.bound c'.2.2⟩ : Dep) ∈ D := pu.nin c' hc'
            rcases hmode with ⟨hinp, hrd⟩ | ⟨b, s, _, _, _, _, _, _, _, hnD, _⟩
            · have hb := hrd _ hd hcc.symm rfl
              refine ⟨hinp, ?_⟩
              rcases pu.pk.mode hc' with h | ⟨b', hb', hbn'⟩
              · exact h
              · simp only [Kind.bound] at hb; rw [hb'] at hb; exact absurd hb hbn'
            · exact absurd hcc.symm (hnD _ hd)
        · cases hc with
          | pkg => exact pu.pk _ _ _ _ _ hs'
  | getl hy hl hty =>
    cases he with
    | getl hv =>
      have hok := hi.tyok hy; rw [hty] at hok
      simp only [Ty.ok, Bool.and_eq_true] at hok
      refine ⟨RhsPost.same hi, out_comp hi hy hl (by rw [hty]; simp) hv Child.inl (Top.inl (Top.refl _)) hok.1
        (fun hw hvs hsh => ?_) (fun h => ?_)⟩
      · rw [hty] at hw hvs hsh; cases hw with
        | inl ha => exact ⟨ha, fun s x hin => hvs s x (ViewIn.inl hin), hsh.inl⟩
      · rw [hty] at h
        rcases valOK_sum.mp h with ⟨x, hx, h⟩ | ⟨x, hx, _⟩ <;> cases hx
        exact h
  | getr hy hl hty =>
    cases he with
    | getr hv =>
      have hok := hi.tyok hy; rw [hty] at hok
      simp only [Ty.ok, Bool.and_eq_true] at hok
      refine ⟨RhsPost.same hi, out_comp hi hy hl (by rw [hty]; simp) hv Child.inr (Top.inr (Top.refl _)) hok.2
        (fun hw hvs hsh => ?_) (fun h => ?_)⟩
      · rw [hty] at hw hvs hsh; cases hw with
        | inr hb => exact ⟨hb, fun s x hin => hvs s x (ViewIn.inr hin), hsh.inr⟩
      · rw [hty] at h
        rcases valOK_sum.mp h with ⟨x, hx, _⟩ | ⟨x, hx, h⟩ <;> cases hx
        exact h
  | takel hy hl hm hty hyF hpin hds =>
    cases he with
    | takel hv =>
      obtain ⟨post, out⟩ := rhs_move hi hanch hy hl hm hyF hpin hv hds
      have hok := hi.tyok hy; rw [hty] at hok
      simp only [Ty.ok, Bool.and_eq_true] at hok
      obtain ⟨_, hw, _⟩ := out.valOwn rfl
      rw [hty] at hw
      cases hw with
      | inl hwa =>
        exact ⟨post, out_part out (by rw [hty]; simp) hwa (Sub.inl (Sub.refl _))
          (fun s x h => by rw [hty]; exact ViewIn.inl h) (by simp) hok.1⟩
  | taker hy hl hm hty hyF hpin hds =>
    cases he with
    | taker hv =>
      obtain ⟨post, out⟩ := rhs_move hi hanch hy hl hm hyF hpin hv hds
      have hok := hi.tyok hy; rw [hty] at hok
      simp only [Ty.ok, Bool.and_eq_true] at hok
      obtain ⟨_, hw, _⟩ := out.valOwn rfl
      rw [hty] at hw
      cases hw with
      | inr hwb =>
        exact ⟨post, out_part out (by rw [hty]; simp) hwb (Sub.inr (Sub.refl _))
          (fun s x h => by rw [hty]; exact ViewIn.inr h) (by simp) hok.2⟩

/-- `= x r`: the right-hand side runs, `x`'s old value is dropped, and `x`
    takes the new one. -/
theorem step_assign {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    {x : Var} {r : Rhs} {Ex E : Entry} (hx : Γ x = some Ex) (hxF : x ∉ F)
    (hmodes : Ex.mode = .own ∧ E.mode = .own ∨ Ex.mode = .inout .replace ∧ E.mode = .own ∨
      Ex.mode = .bor ∧ E.mode = .bor)
    (hr : RhsT Γ F r E Γ1) (hty : E.ty = Ex.ty) (hxd : x ∉ roots E.vdeps)
    {v : Val} {o : Bool} (he : EvalR m r (.ok v o m1)) {sl : Slot} (hsl : m1.st x = some sl)
    {a' : Nat → Bool} (hd : DropSlot m1.alloc sl a') (hpin : NoPin Γ x)
    (hds1 : DtorSafe Γ1 .replace false x) :
    RhsPost m ({ m1 with alloc := a' }.set x ⟨o, some v⟩) Γ
      (setE (kill .replace false x Γ1) x { E with mode := Ex.mode }) F := by
  obtain ⟨post, out⟩ := rhs_pres hi hanch hr he
  have hanch1 := hanch_of hanch post.cmode post.rootb
  have hpin1 := hpin.of post.cmode post.rootb
  obtain ⟨Ex1, hx1, hm1, ht1⟩ : ∃ Ex1, Γ1 x = some Ex1 ∧ Ex1.mode = Ex.mode ∧ Ex1.ty = Ex.ty := by
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
    obtain ⟨_, _, _, hnd, hal, hdis, hsf⟩ := out.valOwn hown
    exact ⟨hnd, hal, hdis, hsf⟩)
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
      obtain ⟨ht, hwf, hvs, _⟩ := out.valOwn hE
      refine ⟨ht, fun T hT => by cases hT; exact hwf, fun _ => ⟨v, rfl, hvs.keep fun dep hd' => ?_⟩⟩
      refine (hkeepE (fun h => by rw [h] at ht; cases ht) dep ?_).1
      simp [Entry.vdeps, hE, Mode.ownSlot, hd']
    · have hE : E.mode = .bor := by
        rcases out.mode with h | h
        · simp only at hbor; rw [hos, h] at hbor; cases hbor
        · exact h
      refine ⟨v, rfl, ?_⟩
      show ValOK m' E.ty v E.path E.held
      by_cases hint : E.ty = .int
      · have := out.valBor hE; rw [hint] at this ⊢; obtain ⟨n, rfl⟩ := valOK_int.mp this; exact .int
      · refine (out.valBor hE).keep (fun dep hd' => hkeepE hint dep ?_) (fun dep hd' => hkeepE hint dep ?_)
        · simp [Entry.vdeps, hE, Mode.ownSlot, hd']
        · simp [Entry.vdeps, hE, Mode.ownSlot, hd']
  have hinv : MInv m' (setE (kill .replace false x Γ1) x { E with mode := Ex.mode }) := by
    refine post.inv.change hanch1 hx1 hxF
      (hpin1.kills _ _) hnrb hst hheap rfl
      (fun k hk => by cases k <;> simp [Eff.kills] at hk) ?_ hds1 (fun h => by cases h) (by simp)
      (fun h => absurd rfl h)
    refine ⟨⟨o, some v⟩, by simp [m'], out.tyok, hslot, hm1.symm, fun hl hn r hr' => Or.inr ?_,
      by rw [ht1]; exact hty, fun _ hn => ?_, fun _ T hT => ?_, fun T hT => ?_,
      fun _ _ hn d hdd _ => Or.inr ?_, fun hd => absurd hd (by simp [(RhsT.dtor_false hr).1]),
      fun hd => absurd hd (by simp [(RhsT.dtor_false hr).2]),
      ArmOK.of_dbind (by simp [(RhsT.dtor_false hr).2])⟩
    rotate_right
    · rw [vdeps_mode hos] at hdd
      have hr' := List.mem_map_of_mem (f := Dep.root) hdd
      exact ⟨fun h => hxd (h ▸ hr'), kill_root (out.wf hn d.root hr').choose_spec.1
        (out.wf hn d.root hr').choose_spec.2⟩
    · rw [vdeps_mode hos] at hr'
      exact ⟨fun h => hxd (h ▸ hr'), kill_root (out.wf hn r hr').choose_spec.1
        (out.wf hn r hr').choose_spec.2⟩
    · have hnint : E.ty ≠ .int := by
        rcases hn with h | h
        · exact h
        · exact absurd (hm1.trans h) hnrb
      refine (out.names (Or.inl hnint)).transport (fun r Er hrE hr hl' hh' ho' => ?_)
        (by rw [vdeps_mode hos]; exact List.Subset.refl _)
      by_cases hrx : r = x
      · rw [vdeps_mode hos] at hrE; exact absurd (hrx ▸ hrE) hxd
      · exact ⟨Er, by simp [upd_ne _ _ hrx, kill, hr, killE_nil (root_vdeps ho' hh')], hl', hh', rfl, rfl⟩
    · cases hT; exact out.held
    · cases hT; exact out.pkgs
  refine ⟨hinv, post.nv, post.nid, fun y => ?_, fun y hy => ?_, fun p Ep hp hpm => ?_, fun y => ?_,
    fun y E1 h => ?_, (post.dkeep.kill .replace false x).setE
      (fun hd => absurd hd (by simp [(RhsT.dtor_false hr).2]))⟩
  · by_cases hyx : y = x
    · subst hyx; simp; rw [← post.dom y, hsl]; rfl
    · rw [hst y hyx]; exact post.dom y
  · rw [hst y (fun h => hxF (h ▸ hy))]; exact post.frz y hy
  · have hpx : p ≠ x := fun h => by
      subst h; rw [hx] at hp; cases hp
      rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩ <;> rw [h1] at hpm <;> cases hpm
    simp only [setE, upd_ne _ _ hpx, kill, post.rootb p Ep hp hpm, Option.map_some]
    rw [killE_rootb hanch1 hxF _ _ (hpin1.kills _ _)
      (post.rootb p Ep hp hpm) hpm]
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
    (hanch : RootbAnch Γ F)
    {x : Var} {E : Entry} (hx : Γ x = some E) (hm : E.mode = .own) (hxF : x ∉ F)
    {t : Val} (ht : m.st x = some ⟨true, some t⟩) {a' : Nat → Bool} (hf : Frees m.alloc t a')
    (hpin : EndOK Γ x) :
    MInv ({ m with alloc := a' }.set x ⟨true, none⟩)
      (setE (kill .replace false x Γ) x { E with live := false, dtor := false }) := by
  obtain ⟨sl, hsl, hok, hslot⟩ := hi.slot x E hx
  rw [ht] at hsl; cases hsl
  have hos : E.mode.ownSlot = true := by rw [hm]; rfl
  obtain ⟨_, hown, _⟩ := hslot
  obtain ⟨hvec, _, _⟩ := hown hos
  refine hi.change hanch hx hxF (hpin.1.kills _ _)
    (by rw [hm]; simp) (fun o ho => by simp [upd_ne _ _ ho])
    (hi.heap.release ht (DropSlot.owned hf) ⟨true, none⟩ (fun _ T hT => by cases hT)) rfl
    (fun k hk => by cases k <;> simp [Eff.kills] at hk) ?_ hpin.2.1 (fun h => by cases h) (by simp)
    (fun h => absurd rfl h)
  have hs : SlotOK ({ m with alloc := a' }.set x ⟨true, none⟩) { E with live := false, dtor := false } ⟨true, none⟩ :=
    ⟨by simp [hos], fun _ => ⟨hvec, fun T h => (by cases h), fun h => (by simp at h)⟩,
      fun h => (by simp [hos] at h)⟩
  refine ⟨⟨true, none⟩, by simp, hok, hs, rfl, (fun h => by simp at h), rfl, (fun h => by simp at h),
    (fun h => by simp at h), (fun T h => by simp at h), fun hd _ hn dep hdd hnm => ?_, fun h => by simp at h,
    fun hd => hi.wf.view x E hx hd, ArmOK.of_none rfl, fun _ T h => by simp at h⟩
  obtain ⟨Er, hEr, hroot⟩ := hi.wf.dtor x E hx hd hos (Or.inl hn) dep hdd hnm
  by_cases hrx : dep.root = x
  · exact Or.inl ⟨hrx, Mode.isRoot_of_ownSlot hos⟩
  · exact Or.inr ⟨hrx, killE .replace false x Er, by simp [A2.kill, hEr], by rw [killE_mode]; exact hroot⟩

theorem HeapOK.remove {m : Mem} (hh : HeapOK m) {x : Var} {sl : Slot} (hx : m.st x = some sl)
    {a' : Nat → Bool} (hd : DropSlot m.alloc sl a') : HeapOK ({ m with alloc := a' }.remove x) := by
  have hown : ∀ o U, OwnedAt ({ m with alloc := a' }.remove x) o U → o ≠ x ∧ OwnedAt m o U :=
    fun o U h => ownedAt_remove.mp h
  cases hd with
  | owned hf => exact hh.without hx _ hown (fun i hi => hf.other hi) (Nat.le_refl _)
  | moved =>
    exact ⟨fun o U h => hh.nodup o U (hown o U h).2,
      fun o1 o2 U1 U2 hne h1 h2 => hh.disj o1 o2 U1 U2 hne (hown o1 U1 h1).2 (hown o2 U2 h2).2,
      fun o U h => hh.alloc o U (hown o U h).2, fun o U h => hh.self o U (hown o U h).2⟩
  | borrowed =>
    exact ⟨fun o U h => hh.nodup o U (hown o U h).2,
      fun o1 o2 U1 U2 hne h1 h2 => hh.disj o1 o2 U1 U2 hne (hown o1 U1 h1).2 (hown o2 U2 h2).2,
      fun o U h => hh.alloc o U (hown o U h).2, fun o U h => hh.self o U (hown o U h).2⟩

/-- The end of `x`'s scope: its value, if it owns one, is dropped. -/
theorem step_scopeExit {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    {x : Var} {E : Entry} (hx : Γ x = some E) (hnrb : E.mode ≠ .rootb) (hxF : x ∉ F)
    {sl : Slot} (hsl : m.st x = some sl) {a' : Nat → Bool} (hd : DropSlot m.alloc sl a')
    (hpin : EndOK Γ x) :
    MInv ({ m with alloc := a' }.remove x) (exitScope x Γ) :=
  hi.change hanch hx hxF (hpin.1.kills _ _) hnrb (fun o ho => by simp [upd_ne _ _ ho])
    (hi.heap.remove hsl hd) rfl
    (fun k hk => by cases k <;> simp [Eff.kills] at hk) (show _ = none by simp) hpin.2.1 (fun _ => hpin.2.2)
    (fun _ => rfl) (fun _ _ h => by cases h)

/-- Growing a tree by one element, its buffer moving or not. -/
theorem HeapOK.grow {m : Mem} (hh : HeapOK m) {x : Var} {t : Ty} {c d : Nat} {es : List Val}
    (hT : m.st x = some ⟨true, some (.node t c d es)⟩) {v : Val} (hnd : v.ids.Nodup)
    (hal : ∀ i ∈ v.ids, m.alloc i = true ∧ i < m.nid)
    (hdis : ∀ o U, OwnedAt m o U → ∀ i ∈ v.ids, i ∉ U.ids)
    {d' : Nat} {A' : Nat → Bool} {N' : Nat}
    (hre : (d' = d ∧ A' = m.alloc ∧ N' = m.nid) ∨
      (d' = m.nid ∧ A' = upd (upd m.alloc d false) m.nid true ∧ N' = m.nid + 1))
    (hsfn : SelfFree (.node t c d' (es ++ [v]))) :
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
  refine ⟨fun o U hU => ?_, fun o1 o2 U1 U2 hne h1 h2 => ?_, fun o U hU i hi => ?_, fun o U hU => ?_⟩
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
  · rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
    · exact hsfn
    · exact hh.self o U h

/-- A view valid through a root other than an owner `x` that is not lent
    out does not point into `x`'s tree. -/
theorem viewAt_not_in {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    {x : Var} (hxF : x ∉ F) {T : Val} (hT : m.st x = some ⟨true, some T⟩) {dep : Dep}
    (hr : ∃ Er, Γ dep.root = some Er ∧ Er.mode.isRoot = true) (hne : dep.root ≠ x)
    {d o l : Nat} {s : Ty} (ha : ViewAt m dep d o l s) : ∀ u c es, ¬ Sub (.node u c d es) T := by
  intro u c es hsub
  obtain ⟨n0, c', es', hrn, hk, _, _⟩ := ha
  have hN : Sub (.node s c' d es') n0 := by
    rcases hk with ⟨_, h⟩ | ⟨_, h⟩
    · rw [h]; exact Sub.refl _
    · exact h.sub
  obtain ⟨Er, hEr, hroot⟩ := hr
  rcases hrn with ⟨T0, hown, htop⟩ | ⟨w1, c1, hc, ht1, hnode⟩ | ⟨w1, d1, o1, l1, hc, ht1, hdata⟩
  · exact hne (owned_unique hi.heap hown hT (hN.trans htop.sub) hsub (i := d) (by simp [Val.head])
      (by simp [Val.head])).1
  all_goals
    obtain ⟨sl, hsl, _, hso, _, _⟩ := hi.slot dep.root Er hEr
    have hrb : Er.mode = .rootb := by
      rw [hc] at hsl; cases hsl
      cases hme : Er.mode with
      | own => rw [hme] at hso; simp [Mode.ownSlot] at hso
      | inout b => exact absurd hme (hi.noInout _ Er b hEr)
      | rootb => rfl
      | bor => rw [hme] at hroot; simp [Mode.isRoot] at hroot
  · obtain ⟨o', T', hoF, hoT, hsT⟩ := rootb_anchor hi hanch dep.root Er n0 hEr hrb
      (Or.inr (Or.inl ⟨w1, c1, hc, ht1, hnode⟩))
    have := (owned_unique hi.heap hoT hT (hN.trans hsT) hsub (i := d) (by simp [Val.head])
      (by simp [Val.head])).1
    subst this; exact hxF hoF
  · obtain ⟨o', T', hoF, hoT, hsT⟩ := rootb_anchor hi hanch dep.root Er n0 hEr hrb
      (Or.inr (Or.inr ⟨w1, d1, o1, l1, hc, ht1, hdata⟩))
    have := (owned_unique hi.heap hoT hT (hN.trans hsT) hsub (i := d) (by simp [Val.head])
      (by simp [Val.head])).1
    subst this; exact hxF hoF

theorem push_grow {m1 : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F)
    {x : Var} {Ex : Entry} (hx : Γ1 x = some Ex) (hl : Ex.live = true) (hcan : canDo Ex.mode .realloc)
    (hxF : x ∉ F) {t : Ty} (hty : Ex.ty = .vec t)
    {t' : Ty} {c d : Nat} {es : List Val} (hT : m1.st x = some ⟨true, some (.node t' c d es)⟩)
    {v : Val} {D : List Dep} (hp : Pushed m1 Γ1 t v D) (hxD : x ∉ roots D)
    (hD : t.holdsView = false → D = []) {d' : Nat} {A' : Nat → Bool} {N' : Nat}
    (hre : (d' = d ∧ A' = m1.alloc ∧ N' = m1.nid) ∨
      (d' = m1.nid ∧ A' = upd (upd m1.alloc d false) m1.nid true ∧ N' = m1.nid + 1))
    (hds : DtorSafe Γ1 .realloc t.holdsView x) (hdbv : Ex.dbind = true → t.holdsView = false) :
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
  have hsfT := hi.heap.self x _ hT
  -- the grown tree views none of itself
  have hsfn : SelfFree (.node t' c d' (es ++ [v])) := by
    intro d0 o0 l0 hv u c0 es0 hn
    have split : ∀ {w : Val}, Sub w (.node t' c d' (es ++ [v])) →
        w = .node t' c d' (es ++ [v]) ∨ Sub w (.node t' c d es) ∨ Sub w v := by
      intro w hw
      rcases hw.cases' with h | ⟨e, hc, hs⟩
      · exact Or.inl h
      · cases hc with
        | elem he =>
          rcases List.mem_append.mp he with h | h
          · exact Or.inr (Or.inl (Sub.child h hs))
          · simp at h; subst h; exact Or.inr (Or.inr hs)
    -- a node of the new tree with buffer `d0` lies in the old tree, or in `v`, or is fresh
    have hnode : (d0 = m1.nid ∧ d' = m1.nid) ∨ (∃ u1 c1 es1, Sub (.node u1 c1 d0 es1) (.node t' c d es)) ∨
        Sub (.node u c0 d0 es0) v := by
      rcases split hn with h | h | h
      · cases h
        rcases hre with ⟨rfl, _⟩ | ⟨rfl, _⟩
        · exact Or.inr (Or.inl ⟨t', c, es, Sub.refl _⟩)
        · exact Or.inl ⟨rfl, rfl⟩
      · exact Or.inr (Or.inl ⟨_, _, _, h⟩)
      · exact Or.inr (Or.inr h)
    have hfresh : ∀ (U : Val) (ox : Var), OwnedAt m1 ox U → d0 ∈ U.ids → d0 ≠ m1.nid := by
      intro U ox hU hd heq
      have := (hi.heap.alloc ox U hU d0 hd).2; omega
    rcases split hv with h | h | h
    · cases h
    · obtain ⟨s, hin⟩ := hwT.sub_view h
      obtain ⟨d1, o1, l1, hv1, dep, hd, ha⟩ := hvsT s _ hin
      cases hv1
      obtain ⟨ox, U, hU, hdU⟩ := ha.owned
      rcases hnode with ⟨rfl, _⟩ | ⟨u', c', es', hs'⟩ | hs'
      · exact hfresh U ox hU hdU rfl
      · exact hsfT _ o0 l0 h u' c' es' hs'
      · exact hp.dis ox U hU _ (hs'.ids _ (by simp)) hdU
    · obtain ⟨s, hin⟩ := hp.wf.sub_view h
      obtain ⟨d1, o1, l1, hv1, dep, hd, ha⟩ := hp.vs s _ hin
      cases hv1
      have hne : dep.root ≠ x := fun heq => hxD (heq ▸ List.mem_map_of_mem hd)
      rcases hnode with ⟨rfl, _⟩ | ⟨u', c', es', hs'⟩ | hs'
      · obtain ⟨ox, U, hU, hdU⟩ := ha.owned
        exact hfresh U ox hU hdU rfl
      · exact viewAt_not_in hi hanch hxF hT (hp.root dep.root (List.mem_map_of_mem hd)) hne ha
          u' c' es' hs'
      · exact hp.sf _ o0 l0 h u c0 es0 hs'
  refine hi.change hanch hx hxF (fun _ _ _ _ ⟨r, k⟩ _ hb hk => by cases k <;> simp_all [Kind.bound, Eff.kills])
    (by rw [hm]; simp) hst (hi.heap.grow hT hp.nd hp.al hp.dis hre hsfn) rfl ?_ ?_ hds (fun h => by cases h) (by simp)
    (fun _ Ex' hx' hl0 hh0 hhv => by
      simp only [Option.some.injEq] at hx'; subst hx'
      rw [hty] at hhv
      exact ⟨hl0, by simp [hh0, hD hhv]⟩)
  · intro k hk
    have hev : Evolve m1 m' x t' c d d' es (es ++ [v]) := ⟨hT, by simp [m'], hwT'⟩
    have hpre : ∀ e ∈ es, e ∈ es ++ [v] := fun e he => List.mem_append_left _ he
    have hkv : k ≠ .view := by intro h; subst h; simp [Eff.kills] at hk
    exact ⟨hev.grow_vkeep hpre hkv, hev.grow_hkeep hpre (fun h => by subst h; simpa [Eff.kills] using hk)
      hkv⟩
  · refine ⟨⟨true, some (.node t' c d' (es ++ [v]))⟩, by simp [m'], by rw [hty]; exact hi.tyok hx ▸ (by
        rw [hty]), ⟨by simp [hos], fun _ => ⟨by rw [hty]; rfl, fun U hU => by cases hU; rw [hty]; exact hwT',
        fun _ => ⟨_, rfl, ?_⟩⟩, fun h => by simp [hos] at h⟩, rfl, fun hl' hn r hr => ?_, rfl,
        fun _ _ => ?_, fun _ T hT => ?_, fun T hT => ?_, fun _ _ _ dep hdd _ => ?_,
        fun hd => hi.wf.arm x Ex hx hd, fun hd => hi.wf.view x Ex hx hd,
        -- (a binding `letd` made gains no view: none is pushed into)
        fun hd => absurd (hdbv hd) (by
          have h := hi.wf.view x Ex hx hd
          rw [hty] at h; simp only [Ty.holdsView] at h; rw [h]; simp)⟩
    rotate_right
    · simp only [Entry.vdeps, hos, ↓reduceIte, List.nil_append, List.mem_append] at hdd
      by_cases hrx : dep.root = x
      · exact Or.inl ⟨hrx, by rw [hm]; rfl⟩
      · refine Or.inr ⟨hrx, ?_⟩
        rcases hdd with hd | hd
        · obtain ⟨Er, hEr, hro⟩ := hrootH dep hd
          exact kill_root hEr hro
        · obtain ⟨Er, hEr, hro⟩ := hp.root dep.root (List.mem_map_of_mem hd)
          exact kill_root hEr hro
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
            exact viewAt_not_self hT hsfT (ViewIn.child h hin) ha
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
    · have hN := hi.names x Ex hx hl (Or.inl (by rw [hty]; simp))
      refine NameOK.transport (Γ := Γ1) (E := { Ex with held := Ex.held ++ D }) ?_
        (fun r Er hrE hr hl' hh' ho' => ?_)
        (List.Subset.refl _)
      · intro d hd
        simp only [Entry.vdeps, hos, ↓reduceIte, List.nil_append, List.mem_append] at hd
        rcases hd with hd | hd
        · exact hN d (List.mem_append_right _ hd)
        · exact hp.nok d hd
      · by_cases hrx : r = x
        · subst hrx; rw [hx] at hr; cases hr
          simp only [Entry.vdeps, hos, ↓reduceIte, List.nil_append, hh', roots] at hrE
          exact absurd hrE hxD
        · exact ⟨Er, by simp [upd_ne _ _ hrx, kill, hr, killE_nil (root_vdeps ho' hh')], hl', hh', rfl, rfl⟩
    · simp only [Option.some.injEq] at hT; subst hT
      intro c hc
      simp only [Val.names, namesL_append, List.mem_append] at hc
      rcases hc with hc | hc
      · exact List.mem_append_left _ (hi.held x Ex _ _ hx hl hT rfl c (by simpa [Val.names] using hc))
      · simp only [namesL, List.append_nil] at hc
        exact List.mem_append_right _ (hp.nin c hc)
    · simp only [Option.some.injEq] at hT; subst hT
      intro fs te ms e cs hs
      rcases hs.cases' with h | ⟨e', hc, hs'⟩
      · cases h
      · cases hc with
        | elem he =>
          rcases List.mem_append.mp he with he | he
          · exact (hi.pkgs x _ _ hT rfl) fs te ms e cs (Sub.child he hs')
          · simp only [List.mem_singleton] at he; subst he; exact hp.pk fs te ms e cs hs'

/-- Removing a borrowed slot leaves every other root's memory as it was. -/
theorem rootKeep_rmbor {m : Mem} {p : Var} {w : Option Val} (hp : m.st p = some ⟨false, w⟩)
    {r : Var} (hr : r ≠ p) : RootKeep m (m.remove p) r := by
  have hown : ∀ o T, OwnedAt m o T → OwnedAt (m.remove p) o T := fun o T hT => by
    refine ownedAt_remove.mpr ⟨fun h => ?_, hT⟩
    subst h; unfold OwnedAt at hT; rw [hp] at hT; cases hT
  intro n hn
  rcases hn with ⟨T0, hn, ht⟩ | ⟨v, c, hc, ht, o, T, hT, hs, hnode⟩ | ⟨v, d, o', l, hc, ht, o, T, hT, hs, hdata⟩
  · exact Or.inl ⟨T0, by simp [upd_ne _ _ hr, hn], ht⟩
  · exact Or.inr (Or.inl ⟨v, c, by simp [upd_ne _ _ hr, hc], ht, o, T, hown o T hT, hs, hnode⟩)
  · exact Or.inr (Or.inr ⟨v, d, o', l, by simp [upd_ne _ _ hr, hc], ht, o, T, hown o T hT, hs, hdata⟩)

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

/-- What `p`'s slot reaches is reached through `p`'s own dependencies. -/
theorem rootb_lands {m : Mem} (hh : HeapOK m) {p : Var} {E : Entry} {w : Val}
    (hp : m.st p = some ⟨false, some w⟩) (hok : ValOK m E.ty w E.path E.held) {n0 : Val}
    (hr : RootNode m p n0) : ∃ d' ∈ E.path ++ E.held, ∃ n1, RootNode m d'.root n1 ∧ Lands d'.kind n0 n1 :=
  bor_lands hh hp hok hr

theorem NamesIn.reroot {T : Val} {H : List Dep} (h : NamesIn T H) {p : Var} (D : List Dep)
    (hnp : ∀ d ∈ H, d.kind.isName = true → d.root ≠ p) : NamesIn T (reroot p D H) :=
  fun c hc => mem_reroot_of_ne (h c hc) (hnp _ (h c hc) rfl)

/-- Nothing holds by name a binding that does not own its slot. -/
theorem DepsNamed.not_root {Γ : Ctx} {D : List Dep} (h : DepsNamed Γ D) {p : Var}
    (hp : ∀ Ep, Γ p = some Ep → Ep.mode.ownSlot = false) :
    ∀ d ∈ D, d.kind.isName = true → d.root ≠ p := by
  intro d hd hk e
  obtain ⟨b, t, hkd⟩ : ∃ b t, d.kind = .name b t := by
    cases hdk : d.kind <;> simp_all [Kind.isName]
  obtain ⟨Er, hEr, _, _, _, ho, _⟩ := h d hd b t hkd
  rw [e] at hEr; rw [hp _ hEr] at ho; cases ho

section rbind
variable {m : Mem} {p : Var} {Ep : Entry} {w : Val}

theorem reroot_sub {D D' ds : List Dep} (h : D ⊆ D') : reroot p D ds ⊆ reroot p D' ds := by
  intro d hd
  rcases mem_reroot hd with ⟨hd0, hne⟩ | ⟨k, d', hk, hd', rfl⟩
  · exact mem_reroot_of_ne hd0 hne
  · exact mem_reroot_of_eq hk (h hd')

theorem lands_notName {k : Kind} {n n0 : Val} (h : Lands k n n0) : k.isName = false := by
  rcases h with ⟨rfl, _⟩ | ⟨rfl, _⟩ | ⟨rfl, _⟩ <;> rfl

/-- What depended on `p` in way `k` now depends on what `p` borrowed: of it,
    what `p` reaches in memory (`D`) is enough. -/
theorem reroot_vkeep (hh : HeapOK m) (hp : m.st p = some ⟨false, some w⟩)
    (hok : ValOK m Ep.ty w Ep.path Ep.held) {D : List Dep} (_hDs : D ⊆ Ep.path ++ Ep.held)
    (hDm : ∀ d ∈ Ep.path ++ Ep.held, d.kind.isName = false → d ∈ D) (hlt : ∀ d' ∈ D, d'.root ≠ p)
    {ds : List Dep} {dep : Dep} (hd : dep ∈ ds) {d o l : Nat} {s : Ty}
    (ha : ViewAt m dep d o l s) : ∃ dep' ∈ reroot p D ds, ViewAt (m.remove p) dep' d o l s := by
  obtain ⟨n0, c, es, hr, hk, hl, hlen, hw⟩ := viewAt_iff.mp ha
  by_cases hrp : dep.root = p
  · obtain ⟨r, k⟩ := dep
    simp only at hrp hr hk hl; subst hrp
    obtain ⟨d', hd', n1, hr1, hl1⟩ := rootb_lands hh hp hok hr
    have hdD := hDm d' hd' (lands_notName hl1)
    refine ⟨⟨d'.root, comp d'.kind k⟩, mem_reroot_of_eq hd hdD, viewAt_iff.mpr ⟨n1, c, es,
      rootKeep_rmbor hp (hlt d' hdD) n1 hr1, comp_ne_self hk, lands_comp' hl1 hl, hlen, hw⟩⟩
  · exact ⟨dep, mem_reroot_of_ne hd hrp, viewAt_iff.mpr ⟨n0, c, es, rootKeep_rmbor hp hrp n0 hr, hk,
      hl, hlen, hw⟩⟩

theorem reroot_views (hh : HeapOK m) (hp : m.st p = some ⟨false, some w⟩)
    (hok : ValOK m Ep.ty w Ep.path Ep.held) {D : List Dep} (hDs : D ⊆ Ep.path ++ Ep.held)
    (hDm : ∀ d ∈ Ep.path ++ Ep.held, d.kind.isName = false → d ∈ D) (hlt : ∀ d' ∈ D, d'.root ≠ p)
    {τ : Ty} {T : Val} {H : List Dep} (hv : ViewsOK m τ T H) :
    ViewsOK (m.remove p) τ T (reroot p D H) := by
  intro s v hin
  obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := hv s v hin
  obtain ⟨dep', hd', ha'⟩ := reroot_vkeep hh hp hok hDs hDm hlt hd ha
  exact ⟨d, o, l, rfl, dep', hd', ha'⟩

/-- A value valid before `p`'s scope ends is valid after, through what `p`
    borrowed.  A closure's environment, valid through what only reads, stays
    so: it is rerooted through what `p` reaches only reading, which keeps
    everything `p` reaches in memory. -/
theorem reroot_valOK_gen (hh : HeapOK m) (hp : m.st p = some ⟨false, some w⟩)
    (hok : ValOK m Ep.ty w Ep.path Ep.held) {τ : Ty} {v : Val} {P H : List Dep} (hv : ValOK m τ v P H) :
    ∀ {D : List Dep}, D ⊆ Ep.path ++ Ep.held → (∀ d ∈ Ep.path ++ Ep.held, d.kind.isName = false → d ∈ D) →
      (∀ d' ∈ D, d'.root ≠ p) → (∀ d ∈ H, d.kind.isName = true → d.root ≠ p) →
      ValOK (m.remove p) τ v (reroot p D P) (reroot p D H) := by
  have happ : ∀ (D P H : List Dep), reroot p D (P ++ H) = reroot p D P ++ reroot p D H := by
    intro D P H; simp [reroot, List.flatMap_append]
  induction hv with
  | int => intro _ _ _ _ _; exact .int
  | pair _ _ ihx ihy =>
    intro D hDs hDm hlt hnp
    have hx := ihx hDs hDm hlt hnp; have hy := ihy hDs hDm hlt hnp
    rw [happ] at hx hy; exact .pair hx hy
  | inl _ ih => intro D hDs hDm hlt hnp; have hx := ih hDs hDm hlt hnp; rw [happ] at hx; exact .inl hx
  | inr _ ih => intro D hDs hDm hlt hnp; have hx := ih hDs hDm hlt hnp; rw [happ] at hx; exact .inr hx
  | @pkg fs te ms x cs P0 H0 _ ih =>
    intro D hDs hDm hlt hnp
    -- the environment is rerooted through what the parameter held but a
    -- change of one of this package's own captures; the parameter was not
    -- held by name, so what it held keeps its bound
    have hDr : envDeps cs D ⊆ Ep.path ++ Ep.held := fun d hd => hDs (envDeps_sub _ _ hd)
    have hDrm : ∀ d ∈ Ep.path ++ Ep.held, d.kind.isName = false → d ∈ envDeps cs D := by
      intro d hd hn
      refine mem_envDeps_of_mem (hDm d hd hn) ?_
      obtain ⟨r, k⟩ := d; cases k <;> simp_all [Kind.isName, Kind.bound]
    have hx := ih hDr hDrm (fun d hd => hlt d (envDeps_sub _ _ hd))
      (fun d hd hn => hnp d (envDeps_sub _ _ hd) hn)
    rw [happ] at hx
    have hH0 : ∀ d ∈ H0, d.root = p → d.kind.bound = .none := by
      intro d hd hdp
      have := hnp d hd
      obtain ⟨r, k⟩ := d; cases k <;> simp_all [Kind.isName, Kind.bound]
    have hr : reroot p (envDeps cs D) (envDeps cs H0) ⊆ envDeps cs (reroot p D H0) :=
      (reroot_envDeps (p := p) (H := H0) (fun d hd => (mem_envDeps.mp hd).2) hH0).trans
        (envDeps_mono (reroot_sub (envDeps_sub _ _)))
    exact .pkg (hx.mono (List.append_subset.mpr ⟨fun _ h => List.mem_append_left _
      (reroot_sub (envDeps_sub _ _) h), fun _ h => List.mem_append_right _ (hr h)⟩) hr)
  | view h =>
    intro D hDs hDm hlt _
    obtain ⟨dep, hd, ha⟩ := h
    obtain ⟨dep', hd', ha'⟩ := reroot_vkeep hh hp hok hDs hDm hlt hd ha
    exact .view ⟨dep', hd', ha'⟩
  | @href t c P H h =>
    intro D hDs hDm hlt hnp
    obtain ⟨dep, hd, n0, d, es, hr, hl, hw, hvs, hns⟩ := h
    have hvs' := reroot_views hh hp hok hDs hDm hlt hvs
    have hns' := hns.reroot D hnp
    by_cases hrp : dep.root = p
    · obtain ⟨r, k⟩ := dep
      simp only at hrp hr hl; subst hrp
      obtain ⟨d', hd', n1, hr1, hl1⟩ := rootb_lands hh hp hok hr
      have hdD := hDm d' hd' (lands_notName hl1)
      exact .href ⟨⟨d'.root, comp d'.kind k⟩, mem_reroot_of_eq hd hdD, n1, d, es,
        rootKeep_rmbor hp (hlt d' hdD) n1 hr1, lands_comp' hl1 hl, hw, hvs', hns'⟩
    · exact .href ⟨dep, mem_reroot_of_ne hd hrp, n0, d, es, rootKeep_rmbor hp hrp n0 hr, hl, hw, hvs',
        hns'⟩

theorem reroot_valOK (hh : HeapOK m) (hp : m.st p = some ⟨false, some w⟩)
    (hok : ValOK m Ep.ty w Ep.path Ep.held) (hlt : ∀ d' ∈ Ep.path ++ Ep.held, d'.root ≠ p)
    {τ : Ty} {v : Val} {P H : List Dep} (hv : ValOK m τ v P H)
    (hnp : ∀ d ∈ H, d.kind.isName = true → d.root ≠ p) :
    ValOK (m.remove p) τ v (reroot p (Ep.path ++ Ep.held) P) (reroot p (Ep.path ++ Ep.held) H) :=
  reroot_valOK_gen hh hp hok hv (List.Subset.refl _) (fun _ hd _ => hd) hlt hnp

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

/-- At the end of a borrowed parameter's scope: nothing held it by name (it
    does not own its slot), and what it held by name is held instead. -/
theorem NameWF.exitRoot {Γ : Ctx} (h : NameWF Γ) (p : Var) (D : List Dep)
    (hp : ∀ Ep, Γ p = some Ep → Ep.mode.ownSlot = false)
    (hD : ∀ d ∈ D, d.root ≠ p) (hDn : DepsNamed Γ D) :
    NameWF (exitRoot p D Γ) := by
  intro v E' hv' hl hn
  have hvp : v ≠ p := fun e => by subst e; simp [A2.exitRoot] at hv'
  simp only [A2.exitRoot, upd_ne _ _ hvp] at hv'
  cases hE : Γ v with
  | none => rw [hE] at hv'; cases hv'
  | some E =>
    rw [hE] at hv'; simp only [Option.map_some, Option.some.injEq] at hv'; subst hv'
    have hNE := h v E hE hl hn
    have lift : ∀ r Er, Γ r = some Er → r ≠ p → A2.exitRoot p D Γ r = some (rerootE p D Er) :=
      fun r Er hEr hrp => by simp [A2.exitRoot, upd_ne _ _ hrp, hEr]
    intro d hd b t hk
    rw [vdeps_reroot] at hd
    rcases mem_reroot hd with ⟨hd0, hne⟩ | ⟨k, d', hk0, hd', rfl⟩
    · obtain ⟨Er, hEr, hl, hh, ht, ho, hc⟩ := hNE d hd0 b t hk
      exact ⟨_, lift _ _ hEr hne, hl, by simp [rerootE, hh, reroot], ht, ho, hc⟩
    · cases hkn : k.isName
      · obtain ⟨Er, hEr, hl, hh, ht, ho, hc⟩ := hDn d' hd' b t (comp_name hk hkn)
        exact ⟨_, lift _ _ hEr (hD d' hd'), hl, by simp [rerootE, hh, reroot], ht, ho, hc⟩
      · exact absurd rfl (hNE.not_root hp _ hk0 hkn)

/-- A borrowed parameter that does not depend on `p` is untouched by `p`'s
    rerooting. -/
theorem rerootE_rootb {Γ : Ctx} {F : List Var}
    (hanch : RootbAnch Γ F)
    {p : Var} (hpF : p ∉ F) (D : List Dep) {v : Var} {E : Entry} (hE : Γ v = some E)
    (hmE : E.mode = .rootb) (hpn : ∀ d ∈ E.vdeps, d.kind.isName = true → d.root ≠ p) :
    rerootE p D E = E := by
  have : ∀ d ∈ E.vdeps, d.root ≠ p := by
    intro d hd h
    by_cases hb : d.kind.bound = .none
    · exact hpF (h ▸ hanch v E hE hmE d hd hb)
    · exact hpn d hd (by cases hk : d.kind <;> simp_all [Kind.bound, Kind.isName]) h
  have hos' : E.mode.ownSlot = false := by rw [hmE]; rfl
  have h1 : ∀ d ∈ E.path, d.root ≠ p := fun d hd => this d (by simp [Entry.vdeps, hos', hd])
  have h2 : ∀ d ∈ E.held, d.root ≠ p := fun d hd => this d (by simp [Entry.vdeps, hd])
  unfold rerootE
  rw [reroot_id h1, reroot_id h2]

/-- The end of a borrowed parameter's scope. -/
theorem step_rbindExit {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    {p : Var} {Ep : Entry} (hp : Γ p = some Ep) (hm : Ep.mode = .rootb) (hpF : p ∉ F) :
    MInv (m.remove p) (exitRoot p (Ep.path ++ Ep.held) Γ) := by
  have hlive := hi.rootbLive p Ep hp hm
  have hos : Ep.mode.ownSlot = false := by rw [hm]; rfl
  obtain ⟨w, hw, hok⟩ := hi.bor_val hp hlive hos
  have hpath_vd : ∀ d' ∈ Ep.path ++ Ep.held, d'.root ∈ roots Ep.vdeps := by
    intro d' hd'
    simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.mem_map]
    exact ⟨d', hd', rfl⟩
  have hlt : ∀ d' ∈ Ep.path ++ Ep.held, d'.root ≠ p := by
    intro d' hd' h
    have := hi.rootbLt p Ep hp hm d'.root (hpath_vd d' hd')
    rw [h] at this; exact Nat.lt_irrefl _ this
  have getE : ∀ v E', exitRoot p (Ep.path ++ Ep.held) Γ v = some E' → v ≠ p →
      ∃ E, Γ v = some E ∧ E' = rerootE p (Ep.path ++ Ep.held) E := by
    intro v E' h hvp
    simp only [exitRoot, upd_ne _ _ hvp] at h
    cases hE : Γ v with
    | none => rw [hE] at h; cases h
    | some E => rw [hE] at h; cases h; exact ⟨E, rfl, rfl⟩
  have hpo : ∀ Ep', Γ p = some Ep' → Ep'.mode.ownSlot = false := fun Ep' h => by
    rw [hp] at h; cases h; exact hos
  have hnpE : ∀ v E, Γ v = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
      ∀ d ∈ E.vdeps, d.kind.isName = true → d.root ≠ p :=
    fun v E hE hl hn => (hi.names v E hE hl hn).not_root hpo
  have hnorb : ∀ v E, Γ v = some E → E.mode = .rootb → rerootE p (Ep.path ++ Ep.held) E = E :=
    fun v E hE hmE => rerootE_rootb hanch hpF _ hE hmE
      (hnpE v E hE (hi.rootbLive v E hE hmE) (Or.inr hmE))
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
        exact ⟨T, hT, reroot_views hi.heap hw hok (List.Subset.refl _) (fun d hd _ => hd) hlt hv⟩⟩
    · obtain ⟨u, hu, hv⟩ := hbor hos' hl
      refine ⟨u, hu, ?_⟩
      by_cases hint : E.ty = .int ∧ E.mode ≠ .rootb
      · show ValOK _ E.ty u _ _
        rw [hint.1] at hv ⊢; obtain ⟨n, rfl⟩ := valOK_int.mp hv; exact .int
      · have hn : E.ty ≠ .int ∨ E.mode = .rootb := by
          by_cases h : E.ty = .int
          · by_cases h' : E.mode = .rootb
            · exact Or.inr h'
            · exact absurd ⟨h, h'⟩ hint
          · exact Or.inl h
        exact reroot_valOK hi.heap hw hok hlt hv fun d hd => hnpE v E hE hl hn d
          (List.mem_append_right _ hd)
  · exact hi.heap.remove hw DropSlot.borrowed
  · intro v hv
    by_cases hvp : v = p
    · subst hvp; simp at hv
    · simp only [Mem.remove_st, upd_ne _ _ hvp] at hv; exact hi.nvSt v hv
  · intro v E' b hv'
    have hvp : v ≠ p := fun h => by subst h; simp [exitRoot] at hv'
    obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvp
    exact hi.noInout v E b hE
  · have hroot' : ∀ r, (∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) → r ≠ p →
        ∃ Er, exitRoot p (Ep.path ++ Ep.held) Γ r = some Er ∧ Er.mode.isRoot = true := by
      intro r ⟨Er, hEr, hro⟩ hrp
      exact ⟨rerootE p (Ep.path ++ Ep.held) Er, by simp [exitRoot, upd_ne _ _ hrp, hEr], hro⟩
    refine ⟨?live, ?dtorc, ?armc, ?viewc⟩
    case armc =>
      intro v E' hv' hd
      have hvp : v ≠ p := fun h => by subst h; simp [exitRoot] at hv'
      obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvp
      exact hi.wf.arm v E hE hd
    case viewc =>
      intro v E' hv' hd
      have hvp : v ≠ p := fun h => by subst h; simp [exitRoot] at hv'
      obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvp
      exact hi.wf.view v E hE hd
    case dtorc =>
      -- A2-drop.2: what depended on `p` depends on what `p` borrowed
      intro v E' hv' hd hos hn dep hdd hnm
      have hvp : v ≠ p := fun h => by subst h; simp [exitRoot] at hv'
      obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvp
      rw [vdeps_reroot] at hdd
      rcases mem_reroot hdd with ⟨hd0, hne⟩ | ⟨k, d', hpk, hd', rfl⟩
      · exact hroot' _ (hi.wf.dtor v E hE hd hos hn dep hd0 hnm) hne
      · exact hroot' _ (hi.wf p Ep hp hlive (Or.inr hm) _ (hpath_vd d' hd')) (hlt d' hd')
    intro v E' hv' hl hn r hr
    have hvp : v ≠ p := fun h => by subst h; simp [exitRoot] at hv'
    obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvp
    rw [vdeps_reroot] at hr
    obtain ⟨dep, hd, rfl⟩ := List.mem_map.mp hr
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
  · exact hi.names.exitRoot p _ hpo hlt (by
      have := hi.names p Ep hp hlive (Or.inr hm)
      simpa [NameOK, Entry.vdeps, hos] using this)
  · intro v E' sl T hv' hl hsl hT
    have hvp : v ≠ p := fun h => by subst h; simp [exitRoot] at hv'
    obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvp
    simp only [Mem.remove_st, upd_ne _ _ hvp] at hsl
    have hN := hi.held v E sl T hE hl hsl hT
    by_cases hint : E.ty = .int ∧ E.mode ≠ .rootb
    · obtain ⟨sl0, hsl0, _, hslot⟩ := hi.slot v E hE
      rw [hsl0] at hsl; cases hsl
      exact NamesIn.nil _ (names_nil_of_int hslot hint.1 hl hT)
    · have hn : E.ty ≠ .int ∨ E.mode = .rootb := by
        by_cases h : E.ty = .int
        · by_cases h' : E.mode = .rootb
          · exact Or.inr h'
          · exact absurd ⟨h, h'⟩ hint
        · exact Or.inl h
      exact hN.reroot _ fun d hd => hnpE v E hE hl hn d (List.mem_append_right _ hd)
  · intro v sl T hsl hT
    have hvp : v ≠ p := fun h => by subst h; simp at hsl
    simp only [Mem.remove_st, upd_ne _ _ hvp] at hsl
    exact hi.pkgs v sl T hsl hT
  · -- A2-drop.2: what an armed binding viewed through `p` it views through what `p` borrowed
    intro v E' sl hv' hsl
    have hvp : v ≠ p := fun h => by subst h; simp [exitRoot] at hv'
    obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvp
    have hsl0 : m.st v = some sl := by simpa [Mem.remove_st, upd_ne _ _ hvp] using hsl
    intro hd hos' T hT
    obtain ⟨hdt, hvs⟩ := hi.armed v E sl hE hsl0 hd hos' T hT
    exact ⟨hdt, reroot_views hi.heap hw hok (List.Subset.refl _) (fun d hd _ => hd) hlt hvs⟩

end A2