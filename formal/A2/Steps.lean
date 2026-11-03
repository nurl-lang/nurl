import A2.Rhs

/-! A2 — the memory side of each step. -/

namespace A2

/-- A slot that was there before keeps its contents: every root reaches the
    same memory. -/
theorem rootKeep_ext {m m' : Mem} (h : ∀ o, m.st o ≠ none → m'.st o = m.st o) (r : Var)
    (hb : BlkLe m.blk m'.blk := by exact BlkLe.of_le fun _ _ h => h) : RootKeep m m' r := by
  refine ⟨fun n hn => ?_, fun o ho => ⟨o, by rw [h r (by rw [ho]; simp)]; exact ho⟩⟩
  have hown : ∀ o T, OwnedAt m o T → OwnedAt m' o T := fun o T hT => by
    unfold OwnedAt at *; rw [h o (by rw [hT]; simp)]; exact hT
  rcases hn with ⟨T0, hn, ht⟩ | ⟨v, c, hc, ht, hnode⟩ | ⟨v, d, o', l, hc, ht, hdata⟩ | ⟨v, k, q, hc, ht, hn⟩
  · exact Or.inl ⟨T0, by rw [h r (by rw [hn]; simp)]; exact hn, ht⟩
  · exact Or.inr (Or.inl ⟨v, c, by rw [h r (by rw [hc]; simp)]; exact hc, ht, hnode.mono hown hb⟩)
  · exact Or.inr (Or.inr (Or.inl ⟨v, d, o', l, by rw [h r (by rw [hc]; simp)]; exact hc, ht, hdata.mono hown hb⟩))
  · exact Or.inr (Or.inr (Or.inr ⟨v, k, q, by rw [h r (by rw [hc]; simp)]; exact hc, ht, hn⟩))

theorem SlotOK.ext {m m' : Mem} (h : ∀ o, m.st o ≠ none → m'.st o = m.st o) {E : Entry} {sl : Slot}
    (hs : SlotOK m E sl) (hb : m'.blk = m.blk := by rfl) : SlotOK m' E sl :=
  hs.keep (fun dep _ => ⟨(rootKeep_ext h dep.root (BlkLe.of_eq hb)).vkeep (BlkLe.of_eq hb),
    (rootKeep_ext h dep.root (BlkLe.of_eq hb)).hkeep⟩) hb

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
                · exact h)
              blk := hi.heap.blk.frame rfl (Nat.le_refl _) (fun _ _ => rfl) (fun o' T hT i hi' =>
                hi.heap.notPay (by
                  rcases ownedAt_set.mp hT with ⟨_, h⟩ | ⟨_, h⟩
                  · cases h
                  · exact h) hi')
              views := hi.heap.views }
    | true =>
      have hown : E.mode = .own := by
        rcases hout.mode with h | h
        · exact h
        · have := hout.own; rw [h] at this; cases this
      obtain ⟨_, _, _, hnd, hal, hdis, hsf, hnp⟩ := hout.valOwn hown
      refine hi.heap.put (x := x) (T := v) _ (fun o' U hU => ?_) (fun U hU => by
          unfold OwnedAt at hU; rw [hmx] at hU; cases hU) hnd hsf hal hdis (fun _ _ _ _ _ => rfl)
        (Nat.le_refl _) hnp (fun _ _ => rfl)
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
  · -- A3.1: the new binding's shares are the right-hand side's; the others' as they were
    intro w Ew sl T hw hsl hown hT
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw
      simp only [Mem.set_st, upd_same, Option.some.injEq] at hsl
      subst hsl
      cases hT
      exact (hout.shares (by rw [← hout.own]; exact hown)).of_blk rfl
    · simp only [setE, upd_ne _ _ hwx] at hw
      have hsl0 : m.st w = some sl := by simpa [Mem.set_st, upd_ne _ _ hwx] using hsl
      exact (hi.shares w Ew sl T hw hsl0 hown hT).of_blk rfl
  · intro k bl hk
    obtain ⟨h1, h2, h3, h4⟩ := hi.blocks k bl hk
    exact ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, (h3 p hp).2.of_blk rfl⟩, h4⟩

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
      (∀ o U, OwnedAt m o U → ∀ i ∈ T.ids, i ∉ U.ids) ∧ SelfFree T ∧ (∀ i ∈ T.ids, ¬ PayAddr m i)) :
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
  refine ⟨fun o U hU => ?_, fun o1 o2 U1 U2 hne h1 h2 => ?_, fun o U hU => ?_, fun o U hU => ?_,
    hh.blk.frame rfl (Nat.le_refl _) (fun i hi => hfr i fun T hT => by
        subst hT; obtain ⟨k, bl, hk, hik⟩ := hi
        exact fun hiT => ((hh.blk k bl hk).2.2 i hik).2.2.1 x T hx hiT)
      (fun o U hU i hi => by
        rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
        · exact (hput rfl U rfl).2.2.2.2 i hi
        · exact hh.notPay h hi), hh.views⟩
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
    · exact (hput rfl U rfl).2.2.2.1
    · exact hh.self o U h

theorem keep_notx {m m' : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    {x : Var} (hxF : x ∉ F) (hst : ∀ o, o ≠ x → m'.st o = m.st o) {dep : Dep}
    (hr : ∃ Er, Γ dep.root = some Er ∧ Er.mode.isRoot = true) (hne : dep.root ≠ x)
    (hb : BlkLe m.blk m'.blk := by exact BlkLe.of_le fun _ _ h => h) :
    VKeep m m' dep ∧ HKeep m m' dep := by
  obtain ⟨Er, hEr, hroot⟩ := hr
  have hk := rootKeep_frame hi hanch (fun o ho => hst o (fun h => hxF (h ▸ ho))) hEr hroot (hst _ hne) hb
  exact ⟨hk.vkeep hb, hk.hkeep⟩

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
  /-- A3.1: its shares name live blocks. -/
  sh   : SharesOK m1 t v
  /-- A3.1: no block's payload holds its addresses. -/
  np   : ∀ i ∈ v.ids, ¬ PayAddr m1 i

/-- What an element of a type that holds no views holds is nothing. -/
theorem Pushed.ownHeld {m1 : Mem} {Γ1 : Ctx} {t : Ty} {v : Val} {D : List Dep} (h : Pushed m1 Γ1 t v D) :
    Pushed m1 Γ1 t v (ownHeld true t D) :=
  ⟨h.wf, h.vs.ownHeld true, h.nd, h.al, h.dis, fun r hr => h.root r (ownHeld_roots hr), h.sf,
    h.nin.ownHeld h.wf true, h.pk, fun d hd => h.nok d (ownHeld_sub _ _ _ hd), h.sh, h.np⟩

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
      obtain ⟨_, hwf, hvs, hnd, hal, hdis, hsf, hnp⟩ := out.valOwn rfl
      have hnint : Ey.ty ≠ .int := fun h => by rw [hty] at h; rw [h] at ho; cases ho
      refine ⟨post, Pushed.mk (hty ▸ hwf) (hty ▸ hvs) hnd hal hdis (fun r hr => ?_) hsf out.held out.pkgs
        (by have := out.names (Or.inl hnint); simpa [NameOK, Entry.vdeps, Mode.ownSlot] using this)
        (hty ▸ out.shares rfl) hnp⟩
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
        (PkgsOK.leaf (fun _ h => by cases h) (fun _ _ _ _ _ h => by cases h)) (DepsNamed.nil _)
        (SharesOK.of_noArc rfl) (fun _ h => (by simp at h))⟩
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
        ((derive_named hN rfl).append hN.held) (fun _ _ _ h => by cases h) (fun _ h => (by simp at h))⟩
      · cases hin
        exact ⟨d, o, l, rfl, dep, List.mem_append_left _ hd, ha⟩
      · exact wf_append (wf_derive hi hy hl hnint _) (wf_held hi hy hl hnint)

/-- A3.1, `arc_new`: the tree taken from `y`, of a type that holds no view
    and no closure, moves into a fresh block, whose key no share names yet:
    its addresses leave the owned trees (`y`'s slot is empty) and become the
    block's payload, which owns them (`BlkOwn`: they were in no other owned
    tree and no payload, `Pushed`); every slot is as it was. -/
theorem rhs_arcNew {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} {t : Ty} {v : Val} {D : List Dep}
    (post : RhsPost m m1 Γ Γ1 F) (pu : Pushed m1 Γ1 t v D) (hpl : t.holdsView = false ∧ t.hasFn = false)
    (htok : t.ok = true) (hfr : m1.blk m1.nid = none) :
    RhsPost m { m1 with nid := m1.nid + 1, blk := upd m1.blk m1.nid (some ⟨t, .arc, some v⟩) } Γ Γ1 F ∧
    RhsOut { m1 with nid := m1.nid + 1, blk := upd m1.blk m1.nid (some ⟨t, .arc, some v⟩) } Γ1
      ⟨.arc t, .own, true, [], [], false, false⟩ (.arc m1.nid v) true := by
  let m2 : Mem := { m1 with nid := m1.nid + 1, blk := upd m1.blk m1.nid (some ⟨t, .arc, some v⟩) }
  have hvf := hpl.1
  have hb : BlkLe m1.blk m2.blk := by
    refine BlkLe.of_le fun k bl hk => ?_
    have hne : k ≠ m1.nid := fun h => by rw [h, hfr] at hk; cases hk
    show upd m1.blk m1.nid _ k = some bl
    rw [upd_ne _ _ hne]; exact hk
  have hnew : m2.blk m1.nid = some ⟨t, .arc, some v⟩ := by simp [m2]
  have hcases : ∀ k bl, m2.blk k = some bl →
      (k = m1.nid ∧ bl = ⟨t, .arc, some v⟩) ∨ (k ≠ m1.nid ∧ m1.blk k = some bl) := by
    intro k bl hk
    by_cases hkn : k = m1.nid
    · subst hkn; rw [hnew] at hk; cases hk; exact Or.inl ⟨rfl, rfl⟩
    · refine Or.inr ⟨hkn, ?_⟩
      have : m2.blk k = m1.blk k := by simp [m2, upd_ne _ _ hkn]
      rw [← this]; exact hk
  -- the new block owns the tree moved in: it was in no owned tree and in no payload
  have hbo : BlkOwn m2 := by
    intro k bl hk
    rcases hcases k bl hk with ⟨rfl, rfl⟩ | ⟨hkn, h⟩
    · refine ⟨Nat.lt_succ_self _, pu.nd, fun i hi => ⟨(pu.al i hi).1, Nat.lt_succ_of_lt (pu.al i hi).2,
        fun x T hT => pu.dis x T hT i hi, fun k' bl' hk' hk'' => ?_⟩⟩
      rcases hcases k' bl' hk'' with ⟨rfl, _⟩ | ⟨_, h'⟩
      · exact absurd rfl hk'
      · exact fun hi' => pu.np i hi ⟨k', bl', h', hi'⟩
    · obtain ⟨hkey, hnd, hall⟩ := post.inv.heap.blk k bl h
      refine ⟨Nat.lt_succ_of_lt hkey, hnd, fun i hi => ?_⟩
      obtain ⟨ha, hlt, hsl, hoth⟩ := hall i hi
      refine ⟨ha, Nat.lt_succ_of_lt hlt, hsl, fun k' bl' hk' hk'' => ?_⟩
      rcases hcases k' bl' hk'' with ⟨rfl, rfl⟩ | ⟨_, h'⟩
      · exact fun hi' => pu.np i hi' ⟨k, bl, h, hi⟩
      · exact hoth k' bl' hk' h'
  have hheap : HeapOK m2 := HeapOK.mono post.inv.heap rfl (fun _ h => h) (Nat.le_succ _) hbo (post.inv.heap.views.fresh hfr (by simp))
  have hB : BlocksIn m2 := fun k bl hk => by
    rcases hcases k bl hk with ⟨rfl, rfl⟩ | ⟨_, h⟩
    · refine ⟨htok, hvf, fun p hp => ?_, fun h => nomatch h⟩
      obtain rfl : v = p := Option.some.inj hp
      exact ⟨pu.wf, pu.sh.grow hb⟩
    · obtain ⟨h1, h2, h3, h4⟩ := post.inv.blocks k bl h
      exact ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, (h3 p hp).2.grow hb⟩, h4⟩
  refine ⟨⟨post.inv.grow rfl hheap (Nat.le_refl _) hb hB, post.nv, Nat.le_trans post.nid (Nat.le_succ _),
    post.dom, post.frz, post.rootb, post.cdom, post.cmode, post.dkeep, post.blk.trans hb⟩, ?_⟩
  exact out_share htok hvf pu.wf (Or.inl hnew)

/-- A3.2, `locked_new`: as `arc_new` (`rhs_arcNew`), into a lock block: the tree taken from `y`, of a type that holds no view
    and no closure, moves into a fresh block, whose key no share names yet:
    its addresses leave the owned trees (`y`'s slot is empty) and become the
    block's payload, which owns them (`BlkOwn`: they were in no other owned
    tree and no payload, `Pushed`); every slot is as it was. -/
theorem rhs_lockNew_post {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} {t : Ty} {v : Val} {D : List Dep}
    (post : RhsPost m m1 Γ Γ1 F) (pu : Pushed m1 Γ1 t v D)
    (hpl : t.holdsView = false ∧ t.hasFn = false ∧ t.hasArc = false)
    (htok : t.ok = true) (hfr : m1.blk m1.nid = none) :
    RhsPost m { m1 with nid := m1.nid + 1, blk := upd m1.blk m1.nid (some ⟨t, .lock, some v⟩) } Γ Γ1 F := by
  let m2 : Mem := { m1 with nid := m1.nid + 1, blk := upd m1.blk m1.nid (some ⟨t, .lock, some v⟩) }
  have hvf := hpl.1
  have hb : BlkLe m1.blk m2.blk := by
    refine BlkLe.of_le fun k bl hk => ?_
    have hne : k ≠ m1.nid := fun h => by rw [h, hfr] at hk; cases hk
    show upd m1.blk m1.nid _ k = some bl
    rw [upd_ne _ _ hne]; exact hk
  have hnew : m2.blk m1.nid = some ⟨t, .lock, some v⟩ := by simp [m2]
  have hcases : ∀ k bl, m2.blk k = some bl →
      (k = m1.nid ∧ bl = ⟨t, .lock, some v⟩) ∨ (k ≠ m1.nid ∧ m1.blk k = some bl) := by
    intro k bl hk
    by_cases hkn : k = m1.nid
    · subst hkn; rw [hnew] at hk; cases hk; exact Or.inl ⟨rfl, rfl⟩
    · refine Or.inr ⟨hkn, ?_⟩
      have : m2.blk k = m1.blk k := by simp [m2, upd_ne _ _ hkn]
      rw [← this]; exact hk
  -- the new block owns the tree moved in: it was in no owned tree and in no payload
  have hbo : BlkOwn m2 := by
    intro k bl hk
    rcases hcases k bl hk with ⟨rfl, rfl⟩ | ⟨hkn, h⟩
    · refine ⟨Nat.lt_succ_self _, pu.nd, fun i hi => ⟨(pu.al i hi).1, Nat.lt_succ_of_lt (pu.al i hi).2,
        fun x T hT => pu.dis x T hT i hi, fun k' bl' hk' hk'' => ?_⟩⟩
      rcases hcases k' bl' hk'' with ⟨rfl, _⟩ | ⟨_, h'⟩
      · exact absurd rfl hk'
      · exact fun hi' => pu.np i hi ⟨k', bl', h', hi'⟩
    · obtain ⟨hkey, hnd, hall⟩ := post.inv.heap.blk k bl h
      refine ⟨Nat.lt_succ_of_lt hkey, hnd, fun i hi => ?_⟩
      obtain ⟨ha, hlt, hsl, hoth⟩ := hall i hi
      refine ⟨ha, Nat.lt_succ_of_lt hlt, hsl, fun k' bl' hk' hk'' => ?_⟩
      rcases hcases k' bl' hk'' with ⟨rfl, rfl⟩ | ⟨_, h'⟩
      · exact fun hi' => pu.np i hi' ⟨k, bl, h, hi⟩
      · exact hoth k' bl' hk' h'
  have hheap : HeapOK m2 := HeapOK.mono post.inv.heap rfl (fun _ h => h) (Nat.le_succ _) hbo (post.inv.heap.views.fresh hfr (by simp))
  have hB : BlocksIn m2 := fun k bl hk => by
    rcases hcases k bl hk with ⟨rfl, rfl⟩ | ⟨_, h⟩
    · refine ⟨htok, hvf, fun p hp => ?_, fun _ => hpl.2.2⟩
      obtain rfl : v = p := Option.some.inj hp
      exact ⟨pu.wf, pu.sh.grow hb⟩
    · obtain ⟨h1, h2, h3, h4⟩ := post.inv.blocks k bl h
      exact ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, (h3 p hp).2.grow hb⟩, h4⟩
  exact ⟨post.inv.grow rfl hheap (Nat.le_refl _) hb hB, post.nv, Nat.le_trans post.nid (Nat.le_succ _),
    post.dom, post.frz, post.rootb, post.cdom, post.cmode, post.dkeep, post.blk.trans hb⟩

theorem rhs_lockNew {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} {t : Ty} {v : Val} {D : List Dep}
    (post : RhsPost m m1 Γ Γ1 F) (pu : Pushed m1 Γ1 t v D)
    (hpl : t.holdsView = false ∧ t.hasFn = false ∧ t.hasArc = false)
    (htok : t.ok = true) (hfr : m1.blk m1.nid = none) :
    RhsPost m { m1 with nid := m1.nid + 1, blk := upd m1.blk m1.nid (some ⟨t, .lock, some v⟩) } Γ Γ1 F ∧
    RhsOut { m1 with nid := m1.nid + 1, blk := upd m1.blk m1.nid (some ⟨t, .lock, some v⟩) } Γ1
      ⟨.lk t, .own, true, [], [], false, false⟩ (.lk m1.nid) true :=
  ⟨rhs_lockNew_post post pu hpl htok hfr, out_lkShare htok hpl.1 hpl.2.2 ⟨some v, by simp⟩⟩

/-- A3.5: a library handle's constructor: `locked_new`'s store, and its one
    share a cell share. -/
theorem rhs_cellNew {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} {t : Ty} {v : Val} {D : List Dep}
    (post : RhsPost m m1 Γ Γ1 F) (pu : Pushed m1 Γ1 t v D)
    (hpl : t.holdsView = false ∧ t.hasFn = false ∧ t.hasArc = false)
    (htok : t.ok = true) (hfr : m1.blk m1.nid = none) :
    RhsPost m { m1 with nid := m1.nid + 1, blk := upd m1.blk m1.nid (some ⟨t, .lock, some v⟩) } Γ Γ1 F ∧
    RhsOut { m1 with nid := m1.nid + 1, blk := upd m1.blk m1.nid (some ⟨t, .lock, some v⟩) } Γ1
      ⟨.cell t, .own, true, [], [], false, false⟩ (.cell m1.nid) true :=
  ⟨rhs_lockNew_post post pu hpl htok hfr, out_cellShare htok hpl.1 hpl.2.2 ⟨some v, by simp⟩⟩

/-- **A3.3, `rw_read`**: a new view of the lock block `k`, whose payload `p`
    is in, at the fresh key `nid`: it owns nothing, and reads the block's
    payload as the block holds it (`ViewsAt`); its payload, a share of the
    block and `p`, is well formed.  The result is the view's one share, the
    read guard, owned and holding nothing.  Every slot is as it was. -/
theorem rhs_rwRead {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) {k : Nat} {t : Ty} {p : Val}
    (hk : m.blk k = some ⟨t, .lock, some p⟩) (hfr : m.blk m.nid = none) :
    RhsPost m { m with nid := m.nid + 1, blk := upd m.blk m.nid (some ⟨.prod (.lk t) t, .view, some (.pair (.lk k) p)⟩) } Γ Γ F ∧
    RhsOut { m with nid := m.nid + 1, blk := upd m.blk m.nid (some ⟨.prod (.lk t) t, .view, some (.pair (.lk k) p)⟩) } Γ
      ⟨.arc (.prod (.lk t) t), .own, true, [], [], false, false⟩ (.arc m.nid (.pair (.lk k) p)) true := by
  let m2 : Mem := { m with nid := m.nid + 1, blk := upd m.blk m.nid (some ⟨.prod (.lk t) t, .view, some (.pair (.lk k) p)⟩) }
  have hb : BlkLe m.blk m2.blk := BlkLe.fresh hfr _
  have hnew : m2.blk m.nid = some ⟨.prod (.lk t) t, .view, some (.pair (.lk k) p)⟩ := by simp [m2]
  have hkn : k ≠ m.nid := fun e => by rw [e, hfr] at hk; cases hk
  have hk2 : m2.blk k = some ⟨t, .lock, some p⟩ := by simp [m2, upd_ne _ _ hkn, hk]
  have hcases : ∀ k' bl, m2.blk k' = some bl →
      (k' = m.nid ∧ bl = ⟨.prod (.lk t) t, .view, some (.pair (.lk k) p)⟩) ∨ (k' ≠ m.nid ∧ m.blk k' = some bl) := by
    intro k' bl h
    by_cases he : k' = m.nid
    · subst he; rw [hnew] at h; cases h; exact Or.inl ⟨rfl, rfl⟩
    · exact Or.inr ⟨he, by simpa [m2, upd_ne _ _ he] using h⟩
  -- the view owns nothing
  have hbo : BlkOwn m2 := by
    intro k' bl hk'
    rcases hcases k' bl hk' with ⟨rfl, rfl⟩ | ⟨_, h⟩
    · exact ⟨Nat.lt_succ_self _, by simp, fun i hi => by simp at hi⟩
    · obtain ⟨hkey, hnd, hall⟩ := hi.heap.blk k' bl h
      refine ⟨Nat.lt_succ_of_lt hkey, hnd, fun i hi' => ?_⟩
      obtain ⟨ha, hlt, hsl, hoth⟩ := hall i hi'
      refine ⟨ha, Nat.lt_succ_of_lt hlt, hsl, fun k'' bl'' hk'' h'' => ?_⟩
      rcases hcases k'' bl'' h'' with ⟨rfl, rfl⟩ | ⟨_, h2⟩
      · simp
      · exact hoth k'' bl'' hk'' h2
  -- the new view reads `k`'s payload; the old ones read what they did
  have hv : ViewsAt m2.blk := by
    intro k' bl hk' hvk
    rcases hcases k' bl hk' with ⟨rfl, rfl⟩ | ⟨_, h⟩
    · exact ⟨k, t, p, rfl, hk2⟩
    · obtain ⟨k0, t0, q, rfl, hk0⟩ := hi.heap.views k' _ h hvk
      have hkn0 : k0 ≠ m.nid := fun e => by rw [e, hfr] at hk0; cases hk0
      exact ⟨k0, t0, q, rfl, by simp [m2, upd_ne _ _ hkn0, hk0]⟩
  have hheap : HeapOK m2 := HeapOK.mono hi.heap rfl (fun _ h => h) (Nat.le_succ _) hbo hv
  obtain ⟨htok, hvf, hpay, hna⟩ := hi.blocks k _ hk
  obtain ⟨hwp, _⟩ := hpay p rfl
  have hna' : t.hasArc = false := hna rfl
  have hok : (Ty.prod (.lk t) t).ok = true := by simp [Ty.ok, htok, hvf, hna']
  have hvf' : (Ty.prod (.lk t) t).holdsView = false := by simp [Ty.holdsView, hvf]
  have hwv : WFv (.prod (.lk t) t) (.pair (.lk k) p) := .pair .lk hwp
  have hsh : SharesOK m2 (.prod (.lk t) t) (.pair (.lk k) p) := fun u k' q ha => by
    cases ha with
    | fst ha => cases ha; exact ⟨_, hk2⟩
    | snd ha => rw [ha.hasArc] at hna'; cases hna'
  have hB : BlocksIn m2 := fun k' bl hk' => by
    rcases hcases k' bl hk' with ⟨rfl, rfl⟩ | ⟨_, h⟩
    · exact ⟨hok, hvf', fun q hq => by cases hq; exact ⟨hwv, hsh⟩, fun h => nomatch h⟩
    · obtain ⟨h1, h2, h3, h4⟩ := hi.blocks k' bl h
      exact ⟨h1, h2, fun q hq => ⟨(h3 q hq).1, (h3 q hq).2.grow hb⟩, h4⟩
  refine ⟨⟨hi.grow rfl hheap (Nat.le_refl _) hb hB, rfl, Nat.le_succ _, fun _ => rfl, fun _ _ => rfl,
    fun _ _ h _ => h, fun _ => rfl, fun _ E1 h => ⟨E1, h, rfl, rfl⟩, DKeep.refl _ _, hb⟩, ?_⟩
  exact out_share hok hvf' hwv (Or.inr hnew)

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
  blk := h1.blk.trans h2.blk
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
  | arc => cases hs
  | lk => cases hs
  | cell => cases hs
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
  | @pkg fs te ms q _ cs _ hq ih =>
    rcases hs.cases' with h | ⟨e, hc, hs'⟩
    · cases h
    · cases hc with
      | pkg =>
        obtain ⟨s, h⟩ := ih hs'
        cases q with
        | any => exact ⟨s, ViewIn.pkg h⟩
        | _ => have := h.holdsView; rw [(hq.send rfl).1] at this; cases this

/-- A valid view points into a buffer some owner holds, or (A3.1) into a
    live block's payload, one its holders read (A3.2). -/
theorem ViewAt.owned_rd {m : Mem} {dep : Dep} {d o l : Nat} {s : Ty} (h : ViewAt m dep d o l s) :
    (∃ x T, OwnedAt m x T ∧ d ∈ T.ids) ∨ ∃ k bl, m.blk k = some bl ∧ d ∈ bl.rd.ids := by
  obtain ⟨c, es, _, hla, _, _⟩ := h
  rcases hla.inMem with ⟨x, T, hT, hs⟩ | ⟨k, bl, hk, hs⟩
  · exact Or.inl ⟨x, T, hT, hs.ids d (by simp)⟩
  · exact Or.inr ⟨k, bl, hk, hs.ids d (by simp)⟩

/-- ... so a payload owns it. -/
theorem ViewAt.owned {m : Mem} {dep : Dep} {d o l : Nat} {s : Ty} (hh : HeapOK m) (h : ViewAt m dep d o l s) :
    (∃ x T, OwnedAt m x T ∧ d ∈ T.ids) ∨ PayAddr m d :=
  h.owned_rd.imp id fun ⟨_, _, hk, hd⟩ => hh.rd_ids hk hd

/-- A tree whose views all point into memory owners or payloads hold, put
    together with one whose addresses neither holds, does not view itself
    across them. -/
theorem selfFree_apart {m : Mem} (hh : HeapOK m) {τ : Ty} {v w : Val} (hw : WFv τ v) {H : List Dep}
    (hvs : ViewsOK m τ v H) (hdis : ∀ o U, OwnedAt m o U → ∀ i ∈ w.ids, i ∉ U.ids)
    (hnp : ∀ i ∈ w.ids, ¬ PayAddr m i) :
    ∀ d o l, Sub (.view d o l) v → ∀ u c es, ¬ Sub (.node u c d es) w := by
  intro d o l hv u c es hn
  obtain ⟨s, hin⟩ := hw.sub_view hv
  obtain ⟨d', o', l', hvv, dep, _, ha⟩ := hvs s _ hin
  cases hvv
  rcases ha.owned hh with ⟨x, T, hT, hd⟩ | hp
  · exact hdis x T hT d (hn.ids d (by simp)) hd
  · exact hnp d (hn.ids d (by simp)) hp

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
    WFv.pair pu1.wf pu2.wf, ?_, ?_, ?_, ?_, ?_, ?_⟩, (fun h => by cases h),
    fun _ => own_named ((pu1.nok.pushArg hpa2 hzd).append pu2.nok), ?_, ?_,
    fun _ => SharesOK.mk_pair (pu1.sh.grow post2.blk) pu2.sh⟩
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
    · exact selfFree_apart post2.inv.heap pu1.wf hvs1 pu2.dis pu2.np d o l hs1 u c es hs2
    · have hb21 : m2.blk = m1.blk := by rcases hcase with ⟨_, _, _, rfl⟩ | ⟨_, rfl⟩ <;> rfl
      exact selfFree_apart post2.inv.heap pu2.wf pu2.vs (fun o U hU i hi => pu1.dis o U (hown21 o U hU) i hi)
        (fun i hi ⟨k, bl, hk, hik⟩ => pu1.np i hi ⟨k, bl, by rw [← hb21]; exact hk, hik⟩)
        d o l hs1 u c es hs2
    · exact pu2.sf d o l hs1 u c es hs2
  · intro i hi hp
    have hb21 : m2.blk = m1.blk := by rcases hcase with ⟨_, _, _, rfl⟩ | ⟨_, rfl⟩ <;> rfl
    simp only [ids_pair, List.mem_append] at hi
    rcases hi with hi | hi
    · obtain ⟨k, bl, hk, hik⟩ := hp; exact pu1.np i hi ⟨k, bl, by rw [← hb21]; exact hk, hik⟩
    · exact pu2.np i hi hp
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
    (htok : t.ok = true) (hain : ∀ u k p, ArcIn t x u k p → ArcIn τ T u k p) :
    RhsOut m Γ (compE E t) x x.owns := by
  obtain ⟨_, _, hvsT, hnd, hal, hdis, hsf, hnp⟩ := hout.valOwn rfl
  have hshx : SharesOK m t x := fun u k p ha => hout.shares rfl u k p (hain u k p ha)
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
      fun _ => hH.append hH, hnx, hpx, fun h => nomatch h⟩
    obtain ⟨d', o', l', hv, dep, hd, ha⟩ := hvsT s _ (hvin s _ ViewIn.here)
    cases hv
    exact .view ⟨dep, hd, ha⟩
  | @node u c d es hes =>
    refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => hwfH' r (by simpa [Entry.vdeps, Mode.ownSlot,
      compE] using hr), fun _ => ⟨rfl, WFv.node hes, ViewsOK.ownHeld true (fun s v h => hvsT s v (hvin s v h)),
      hnd.sublist hids, fun i hi => hal i (hids.subset hi), fun o U hU i hi => hdis o U hU i (hids.subset hi),
      hsf.sub hsub, fun i hi => hnp i (hids.subset hi)⟩, (fun h => by cases h), fun _ => own_named hH', hnx',
      hpx, fun _ => hshx⟩
  | @pair a b v w hwa hwb =>
    refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => hwfH' r (by simpa [Entry.vdeps, Mode.ownSlot,
      compE] using hr), fun _ => ⟨rfl, WFv.pair hwa hwb, ViewsOK.ownHeld true (fun s v h => hvsT s v (hvin s v h)),
      hnd.sublist hids, fun i hi => hal i (hids.subset hi), fun o U hU i hi => hdis o U hU i (hids.subset hi),
      hsf.sub hsub, fun i hi => hnp i (hids.subset hi)⟩, (fun h => by cases h), fun _ => own_named hH', hnx',
      hpx, fun _ => hshx⟩
  | @inl a b v hwa =>
    refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => hwfH' r (by simpa [Entry.vdeps, Mode.ownSlot,
      compE] using hr), fun _ => ⟨rfl, WFv.inl hwa, ViewsOK.ownHeld true (fun s v h => hvsT s v (hvin s v h)),
      hnd.sublist hids, fun i hi => hal i (hids.subset hi), fun o U hU i hi => hdis o U hU i (hids.subset hi),
      hsf.sub hsub, fun i hi => hnp i (hids.subset hi)⟩, (fun h => by cases h), fun _ => own_named hH', hnx',
      hpx, fun _ => hshx⟩
  | @inr a b v hwb =>
    refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => hwfH' r (by simpa [Entry.vdeps, Mode.ownSlot,
      compE] using hr), fun _ => ⟨rfl, WFv.inr hwb, ViewsOK.ownHeld true (fun s v h => hvsT s v (hvin s v h)),
      hnd.sublist hids, fun i hi => hal i (hids.subset hi), fun o U hU i hi => hdis o U hU i (hids.subset hi),
      hsf.sub hsub, fun i hi => hnp i (hids.subset hi)⟩, (fun h => by cases h), fun _ => own_named hH', hnx',
      hpx, fun _ => hshx⟩
  | pkg hwb hq =>
    refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => hwfH' r (by simpa [Entry.vdeps, Mode.ownSlot,
      compE] using hr), fun _ => ⟨rfl, WFv.pkg hwb hq, ViewsOK.ownHeld true (fun s v h => hvsT s v (hvin s v h)),
      hnd.sublist hids, fun i hi => hal i (hids.subset hi), fun o U hU i hi => hdis o U hU i (hids.subset hi),
      hsf.sub hsub, fun i hi => hnp i (hids.subset hi)⟩, (fun h => by cases h), fun _ => own_named hH', hnx',
      hpx, fun _ => hshx⟩
  | arc hwp hvf =>
    refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => hwfH' r (by simpa [Entry.vdeps, Mode.ownSlot,
      compE] using hr), fun _ => ⟨rfl, WFv.arc hwp hvf, ViewsOK.ownHeld true (fun s v h => hvsT s v (hvin s v h)),
      hnd.sublist hids, fun i hi => hal i (hids.subset hi), fun o U hU i hi => hdis o U hU i (hids.subset hi),
      hsf.sub hsub, fun i hi => hnp i (hids.subset hi)⟩, (fun h => by cases h), fun _ => own_named hH', hnx',
      hpx, fun _ => hshx⟩
  | lk =>
    refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => hwfH' r (by simpa [Entry.vdeps, Mode.ownSlot,
      compE] using hr), fun _ => ⟨rfl, WFv.lk, ViewsOK.ownHeld true (fun s v h => hvsT s v (hvin s v h)),
      hnd.sublist hids, fun i hi => hal i (hids.subset hi), fun o U hU i hi => hdis o U hU i (hids.subset hi),
      hsf.sub hsub, fun i hi => hnp i (hids.subset hi)⟩, (fun h => by cases h), fun _ => own_named hH', hnx',
      hpx, fun _ => hshx⟩
  | cell =>
    refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => hwfH' r (by simpa [Entry.vdeps, Mode.ownSlot,
      compE] using hr), fun _ => ⟨rfl, WFv.cell, ViewsOK.ownHeld true (fun s v h => hvsT s v (hvin s v h)),
      hnd.sublist hids, fun i hi => hal i (hids.subset hi), fun o U hU i hi => hdis o U hU i (hids.subset hi),
      hsf.sub hsub, fun i hi => hnp i (hids.subset hi)⟩, (fun h => by cases h), fun _ => own_named hH', hnx',
      hpx, fun _ => hshx⟩

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
    (hnok : DepsNamed Γ1 D') (hnin : NamesIn w D') (hpk : PkgsOK w)
    (hain' : ∀ u k p, ArcIn τ w u k p → ArcIn a v u k p) :
    RhsOut m1 Γ1 ⟨τ, .own, true, [], D', false, false⟩ w true := by
  have hsub : ∀ {n : Val}, Sub n w → n = w ∨ Sub n v := by
    intro n hn
    rcases hn.cases' with h | ⟨e, hc, hs⟩
    · exact Or.inl h
    · rw [hchild e hc] at hs; exact Or.inr hs
  refine ⟨rfl, Or.inl rfl, rfl, htok, fun _ r hr => ?_,
    fun _ => ⟨hown, hwτ, ViewsOK.mono hDD fun s x hin => pu.vs s x (hvin' s x hin), by
      rw [hids]; exact pu.nd, fun i hi => pu.al i (hids ▸ hi), fun o U hU i hi => pu.dis o U hU i (hids ▸ hi),
      fun d o l hv u c es hn => ?_, fun i hi => pu.np i (hids ▸ hi)⟩, (fun h => by cases h),
      fun _ => own_named hnok, hnin, hpk,
      fun _ u k p ha => pu.sh u k p (hain' u k p ha)⟩
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
    (hvin' : ∀ s x, ViewIn τ w s x → ViewIn a v s x) (hok : a.ok = true)
    (hain' : ∀ u k p, ArcIn τ w u k p → ArcIn a v u k p) :
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
      fun d o l hv u c es hn => ?_, fun i hi => pu.np i (hids ▸ hi)⟩, (fun h => by cases h),
      fun _ => own_named pu.nok,
      fun c hc => pu.nin c (by rcases hwv with rfl | rfl <;> simpa [Val.names] using hc), ?_,
      fun _ u k p ha => pu.sh u k p (hain' u k p ha)⟩
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

/-- A3.2: a lock block's payload checked out or back in: the block is kept
    as a lock block of its type. -/
theorem BlkLe.setLock {B : Nat → Option Blk} {k : Nat} {t : Ty} {o : Option Val} (h : B k = some ⟨t, .lock, o⟩)
    (o' : Option Val) : BlkLe B (upd B k (some ⟨t, .lock, o'⟩)) := by
  intro k' bl hk'
  by_cases he : k' = k
  · subst he; rw [h] at hk'; cases hk'
    exact ⟨⟨t, .lock, o'⟩, by simp [upd], rfl, rfl, fun h => nomatch h⟩
  · exact ⟨bl, by simp [upd, he, hk'], BlkKeep.refl _⟩

/-- A3.4: **an atomic operation**: the word of the integer lock block `k`
    changes, an integer that owns no address before or after; the answer
    is a plain integer. -/
theorem atomic_pres {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) {k n n' r : Nat}
    (hk : m.blk k = some ⟨.int, .lock, some (.int n)⟩) (hnv : ¬ HasView m.blk k) :
    RhsPost m { m with blk := upd m.blk k (some ⟨.int, .lock, some (.int n')⟩) } Γ Γ F ∧
    RhsOut { m with blk := upd m.blk k (some ⟨.int, .lock, some (.int n')⟩) } Γ intE (.int r) false := by
  obtain ⟨htok, hvf, _, hna⟩ := hi.blocks k _ hk
  have hb : BlkLe m.blk (upd m.blk k (some ⟨.int, .lock, some (.int n')⟩)) := BlkLe.setLock hk _
  obtain ⟨hkey, _, _⟩ := hi.heap.blk k _ hk
  have hcases : ∀ k' bl, upd m.blk k (some ⟨.int, .lock, some (.int n')⟩) k' = some bl →
      (k' = k ∧ bl = ⟨.int, .lock, some (.int n')⟩) ∨ (k' ≠ k ∧ m.blk k' = some bl) := by
    intro k' bl h
    by_cases he : k' = k
    · subst he; simp [upd] at h; exact Or.inl ⟨rfl, h.symm⟩
    · exact Or.inr ⟨he, by simpa [upd, he] using h⟩
  have hbo : BlkOwn { m with blk := upd m.blk k (some ⟨.int, .lock, some (.int n')⟩) } := by
    intro k' bl hk'
    rcases hcases k' bl hk' with ⟨rfl, rfl⟩ | ⟨hne, h⟩
    · exact ⟨hkey, by simp [Blk.tree], fun i hi => by simp [Blk.tree] at hi⟩
    · obtain ⟨hkey', hnd', hall'⟩ := hi.heap.blk k' bl h
      refine ⟨hkey', hnd', fun i hi' => ?_⟩
      obtain ⟨ha, hlt, hsl, hoth⟩ := hall' i hi'
      refine ⟨ha, hlt, hsl, fun k'' bl'' hk'' h'' => ?_⟩
      rcases hcases k'' bl'' h'' with ⟨rfl, rfl⟩ | ⟨_, h2⟩
      · simp [Blk.tree]
      · exact hoth k'' bl'' hk'' h2
  have hheap : HeapOK { m with blk := upd m.blk k (some ⟨.int, .lock, some (.int n')⟩) } :=
    HeapOK.mono hi.heap rfl (fun _ h => h) (Nat.le_refl _) hbo (hi.heap.views.setLock hk hnv _)
  have hB : BlocksIn { m with blk := upd m.blk k (some ⟨.int, .lock, some (.int n')⟩) } := fun k' bl hk' => by
    rcases hcases k' bl hk' with ⟨rfl, rfl⟩ | ⟨_, h⟩
    · exact ⟨htok, hvf, fun p hp => by cases hp; exact ⟨.int, SharesOK.of_noArc rfl⟩, fun _ => hna rfl⟩
    · obtain ⟨h1, h2, h3, h4⟩ := hi.blocks k' bl h
      exact ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, (h3 p hp).2.grow hb⟩, h4⟩
  have hinv : MInv { m with blk := upd m.blk k (some ⟨.int, .lock, some (.int n')⟩) } Γ :=
    hi.grow rfl hheap (Nat.le_refl _) hb hB
  exact ⟨⟨hinv, rfl, Nat.le_refl _, fun _ => rfl, fun _ _ => rfl, fun _ _ h _ => h, fun _ => rfl,
    fun _ E1 h => ⟨E1, h, rfl, rfl⟩, DKeep.refl _ _, hb⟩, intE_out _⟩

/-! ### A3.4: channels

A `Channel s` is a lock block of type `prod (vec s) int`: its payload is the
queue and the closed flag.  Each operation changes the payload in place, in
one step. -/

/-- A tree of a type that holds no view views nothing, itself least. -/
theorem WFv.selfFree_noView {t : Ty} {v : Val} (hw : WFv t v) (hvf : t.holdsView = false) : SelfFree v :=
  fun d o l hs => by
    obtain ⟨s, hin⟩ := hw.sub_view hs
    have := hin.holdsView; rw [hvf] at this; cases this

/-- A channel's type is a lock's of a type that holds no view and no share. -/
theorem chan_tyok {s : Ty} (h : (Ty.lk (.prod (.vec s) .int)).ok = true) :
    s.ok = true ∧ s.holdsView = false ∧ s.hasArc = false := by
  simp only [Ty.ok, Ty.holdsView, Ty.hasArc, Bool.and_true, Bool.or_false, Bool.and_eq_true,
    Bool.not_eq_eq_eq_not, Bool.not_true] at h
  exact ⟨h.1.1, h.1.2, h.2⟩

/-- An owned value of a type that holds no view and no share, whose
    addresses are live, distinct, in no owned tree and in no payload: what a
    right-hand side hands over holding nothing. -/
theorem out_ownNoView {m : Mem} {Γ : Ctx} {t : Ty} {v : Val} (htok : t.ok = true)
    (hvf : t.holdsView = false) (hna : t.hasArc = false) (ho : t.owning = true) (hw : WFv t v)
    (hnd : v.ids.Nodup) (hal : ∀ i ∈ v.ids, m.alloc i = true ∧ i < m.nid)
    (hdis : ∀ x U, OwnedAt m x U → ∀ i ∈ v.ids, i ∉ U.ids) (hnp : ∀ i ∈ v.ids, ¬ PayAddr m i) :
    RhsOut m Γ ⟨t, .own, true, [], [], false, false⟩ v true where
  own := rfl
  mode := Or.inl rfl
  live := rfl
  tyok := htok
  wf := fun _ r hr => by simp [roots, Entry.vdeps, Mode.ownSlot] at hr
  valOwn := fun _ => ⟨ho, hw, ViewsOK.none hvf _ _, hnd, hal, hdis, hw.selfFree_noView hvf, hnp⟩
  valBor := fun h => nomatch h
  names := fun _ => DepsNamed.nil _
  held := NamesIn.nil _ (hw.names_nil hvf)
  pkgs := hw.pkgsOK_noView hvf
  shares := fun _ => SharesOK.of_noArc hna

/-- A3.4: **a lock block's payload changed in place** to `p'`, a tree of its
    type whose every address was the payload's, or is taken in from no owned
    tree and no payload (`hin`): the block is kept as a lock block of its
    type (`BlkLe.setLock`), and the invariant holds over the new blocks. -/
theorem setPay_pres {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) {k : Nat} {t : Ty} {p p' : Val}
    (hk : m.blk k = some ⟨t, .lock, some p⟩) (hnv : ¬ HasView m.blk k) (hw : WFv t p') (hnd : p'.ids.Nodup)
    (hin : ∀ i ∈ p'.ids, i ∈ p.ids ∨
      (m.alloc i = true ∧ i < m.nid ∧ (∀ x T, OwnedAt m x T → i ∉ T.ids) ∧ ¬ PayAddr m i)) :
    RhsPost m { m with blk := upd m.blk k (some ⟨t, .lock, some p'⟩) } Γ Γ F := by
  obtain ⟨htok, hvf, _, hna⟩ := hi.blocks k _ hk
  have hna' : t.hasArc = false := hna rfl
  have hb : BlkLe m.blk (upd m.blk k (some ⟨t, .lock, some p'⟩)) := BlkLe.setLock hk _
  obtain ⟨hkey, _, hall⟩ := hi.heap.blk k _ hk
  have hcases : ∀ k' bl, upd m.blk k (some ⟨t, .lock, some p'⟩) k' = some bl →
      (k' = k ∧ bl = ⟨t, .lock, some p'⟩) ∨ (k' ≠ k ∧ m.blk k' = some bl) := by
    intro k' bl h
    by_cases he : k' = k
    · subst he; simp [upd] at h; exact Or.inl ⟨rfl, h.symm⟩
    · exact Or.inr ⟨he, by simpa [upd, he] using h⟩
  have hbo : BlkOwn { m with blk := upd m.blk k (some ⟨t, .lock, some p'⟩) } := by
    intro k' bl hk'
    rcases hcases k' bl hk' with ⟨hkk, hbl⟩ | ⟨hne, h⟩
    · subst hkk hbl
      refine ⟨hkey, hnd, fun i hi' => ?_⟩
      rcases hin i hi' with hip | ⟨ha, hlt, hown, hnp⟩
      · obtain ⟨ha, hlt, hown, hoth⟩ := hall i hip
        refine ⟨ha, hlt, hown, fun k'' bl'' hk'' h'' => ?_⟩
        rcases hcases k'' bl'' h'' with ⟨he, _⟩ | ⟨_, h2⟩
        · exact absurd he hk''
        · exact hoth k'' bl'' hk'' h2
      · refine ⟨ha, hlt, hown, fun k'' bl'' hk'' h'' => ?_⟩
        rcases hcases k'' bl'' h'' with ⟨he, _⟩ | ⟨_, h2⟩
        · exact absurd he hk''
        · exact fun hi2 => hnp ⟨k'', bl'', h2, hi2⟩
    · obtain ⟨hkey', hnd', hall'⟩ := hi.heap.blk k' bl h
      refine ⟨hkey', hnd', fun i hi' => ?_⟩
      obtain ⟨ha, hlt, hsl, hoth⟩ := hall' i hi'
      refine ⟨ha, hlt, hsl, fun k'' bl'' hk'' h'' => ?_⟩
      rcases hcases k'' bl'' h'' with ⟨he, hbl⟩ | ⟨_, h2⟩
      · subst he hbl
        intro hi2
        rcases hin i hi2 with hip | ⟨_, _, _, hnp⟩
        · exact hoth _ _ hk'' hk hip
        · exact hnp ⟨k', bl, h, hi'⟩
      · exact hoth k'' bl'' hk'' h2
  have hheap : HeapOK { m with blk := upd m.blk k (some ⟨t, .lock, some p'⟩) } :=
    HeapOK.mono hi.heap rfl (fun _ h => h) (Nat.le_refl _) hbo (hi.heap.views.setLock hk hnv _)
  have hB : BlocksIn { m with blk := upd m.blk k (some ⟨t, .lock, some p'⟩) } := fun k' bl hk' => by
    rcases hcases k' bl hk' with ⟨hkk, hbl⟩ | ⟨_, h⟩
    · subst hkk hbl
      exact ⟨htok, hvf, fun q hq => by cases hq; exact ⟨hw, SharesOK.of_noArc hna'⟩, fun _ => hna'⟩
    · obtain ⟨h1, h2, h3, h4⟩ := hi.blocks k' bl h
      exact ⟨h1, h2, fun q hq => ⟨(h3 q hq).1, (h3 q hq).2.grow hb⟩, h4⟩
  exact ⟨hi.grow rfl hheap (Nat.le_refl _) hb hB, rfl, Nat.le_refl _, fun _ => rfl, fun _ _ => rfl,
    fun _ _ h _ => h, fun _ => rfl, fun _ E1 h => ⟨E1, h, rfl, rfl⟩, DKeep.refl _ _, hb⟩

/-- A3.4, **`chan_send`** on an open channel: the tree taken from `y`, of
    the queue's element type, moves to the back of the queue, as `vec_push`
    stores it (`Pushed`): its addresses leave the owned trees (`y`'s slot is
    empty) and join the channel's payload, which owns them (`BlkOwn`: they
    were in no other owned tree and no payload), as `locked_new`'s do
    (`rhs_lockNew`). -/
theorem chanSend_pres {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} {k : Nat} {s u : Ty} {c d : Nat}
    {es : List Val} {v : Val} {D : List Dep} (post : RhsPost m m1 Γ Γ1 F) (pu : Pushed m1 Γ1 s v D)
    (hk : m1.blk k = some ⟨.prod (.vec s) .int, .lock, some (.pair (.node u c d es) (.int 0))⟩)
    (hnv : ¬ HasView m1.blk k) :
    RhsPost m { m1 with blk := upd m1.blk k (some ⟨.prod (.vec s) .int, .lock,
      some (.pair (.node u c d (es ++ [v])) (.int 0))⟩) } Γ Γ1 F := by
  obtain ⟨_, _, hpay, _⟩ := post.inv.blocks k _ hk
  obtain ⟨hwp, _⟩ := hpay _ rfl
  obtain ⟨_, hnd, _⟩ := post.inv.heap.blk k _ hk
  have hnd0 : (c :: d :: idsL es).Nodup := by
    have : (Val.pair (.node u c d es) (.int 0)).ids.Nodup := hnd
    simpa using this
  have hold : ∀ i ∈ c :: d :: idsL es, PayAddr m1 i :=
    fun i hi' => ⟨k, _, hk, by simpa [Blk.tree] using hi'⟩
  have hw : WFv (.prod (.vec s) .int) (.pair (.node u c d (es ++ [v])) (.int 0)) := by
    cases hwp with
    | pair hq hfl =>
      cases hq with
      | node hes =>
        refine .pair (.node fun e he => ?_) hfl
        rcases List.mem_append.mp he with he | he
        · exact hes e he
        · rw [List.mem_singleton.mp he]; exact pu.wf
  have hids : (Val.pair (.node u c d (es ++ [v])) (.int 0)).ids = (c :: d :: idsL es) ++ v.ids := by
    simp [idsL_append]
  have hnd' : (Val.pair (.node u c d (es ++ [v])) (.int 0)).ids.Nodup := by
    rw [hids]
    exact List.nodup_append.mpr ⟨hnd0, pu.nd, fun i hi' j hj he => by
      subst he; exact pu.np i hj (hold i hi')⟩
  refine post.trans (setPay_pres post.inv hk hnv hw hnd' fun i hi' => ?_)
  rw [hids] at hi'
  rcases List.mem_append.mp hi' with hi' | hi'
  · exact .inl (by simpa using hi')
  · exact .inr ⟨(pu.al i hi').1, (pu.al i hi').2, fun x T hT => pu.dis x T hT i hi', pu.np i hi'⟩

/-- A3.4, `chan_send` on a closed channel: the value taken from `y`, which
    no owner holds and no payload owns (`Pushed`), is freed; no owned or
    payload address is (as `HeapOK.freeV`, an element set out of range). -/
theorem chanSendClosed_pres {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} {s : Ty} {v : Val} {D : List Dep}
    {a' : Nat → Bool} (post : RhsPost m m1 Γ Γ1 F) (pu : Pushed m1 Γ1 s v D) (hf : Frees m1.alloc v a') :
    RhsPost m { m1 with alloc := a' } Γ Γ1 F := by
  have hh := post.inv.heap
  have hheap : HeapOK { m1 with alloc := a' } :=
    { nodup := fun o U hU => hh.nodup o U hU
      disj := fun o1 o2 U1 U2 hne h1 h2 => hh.disj o1 o2 U1 U2 hne h1 h2
      alloc := fun o U hU i hi => by
        obtain ⟨ha, hlt⟩ := hh.alloc o U hU i hi
        exact ⟨by show a' i = true; rw [hf.other (fun h => pu.dis o U hU i h hi)]; exact ha, hlt⟩
      self := fun o U hU => hh.self o U hU
      blk := hh.blk.frame rfl (Nat.le_refl _) (fun i hi => hf.other (fun h => pu.np i h hi))
        (fun o U hU i hi => hh.notPay hU hi)
      views := hh.views }
  exact post.trans ⟨post.inv.of_st rfl hheap (Nat.le_refl _), rfl, Nat.le_refl _, fun _ => rfl,
    fun _ _ => rfl, fun _ _ h _ => h, fun _ => rfl, fun _ E1 h => ⟨E1, h, rfl, rfl⟩, DKeep.refl _ _,
    BlkLe.refl _⟩

/-- A3.4, **`chan_recv`**: the queue's head `v` moves out of the channel's
    payload, which keeps the rest; `v` is handed over owned, as `some`,
    holding nothing: its addresses were the payload's, and are in no owned
    tree and in no payload any more (`BlkOwn`), as a lock's payload checked
    out is (`acquire_pres`). -/
theorem chanRecv_pres {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) {k : Nat} {s u : Ty}
    {c d f : Nat} {v : Val} {es : List Val}
    (hk : m.blk k = some ⟨.prod (.vec s) .int, .lock, some (.pair (.node u c d (v :: es)) (.int f))⟩)
    (hnv : ¬ HasView m.blk k) :
    RhsPost m { m with blk := upd m.blk k (some ⟨.prod (.vec s) .int, .lock,
        some (.pair (.node u c d es) (.int f))⟩) } Γ Γ F ∧
    RhsOut { m with blk := upd m.blk k (some ⟨.prod (.vec s) .int, .lock,
        some (.pair (.node u c d es) (.int f))⟩) } Γ ⟨.sum .int s, .own, true, [], [], false, false⟩
      (.inr v) true := by
  obtain ⟨htok, hvf, hpay, hna⟩ := hi.blocks k _ hk
  obtain ⟨hwp, _⟩ := hpay _ rfl
  have hna' : (Ty.prod (.vec s) .int).hasArc = false := hna rfl
  obtain ⟨_, hnd, hall⟩ := hi.heap.blk k _ hk
  have hnd0 : (c :: d :: (v.ids ++ idsL es)).Nodup := by
    have : (Val.pair (.node u c d (v :: es)) (.int f)).ids.Nodup := hnd
    simpa using this
  have hall0 : ∀ i ∈ c :: d :: (v.ids ++ idsL es), m.alloc i = true ∧ i < m.nid ∧
      (∀ x T, OwnedAt m x T → i ∉ T.ids) ∧
      ∀ k' bl', k' ≠ k → m.blk k' = some bl' → i ∉ bl'.tree.ids :=
    fun i hi' => hall i (by simpa [Blk.tree] using hi')
  have hwv : WFv s v ∧ WFv (.prod (.vec s) .int) (.pair (.node u c d es) (.int f)) := by
    cases hwp with
    | pair hq hfl =>
      cases hq with
      | node hes =>
        exact ⟨hes v (List.mem_cons_self ..), .pair (.node fun e he => hes e (List.mem_cons_of_mem _ he)) hfl⟩
  have hsub : (c :: d :: idsL es).Sublist (c :: d :: (v.ids ++ idsL es)) :=
    ((List.sublist_append_right v.ids (idsL es)).cons_cons d).cons_cons c
  have hpost := setPay_pres (F := F) hi hk hnv hwv.2 (by simpa using hnd0.sublist hsub)
    (fun i hi' => Or.inl (by simpa using hsub.subset (by simpa using hi')))
  refine ⟨hpost, ?_⟩
  have hso : s.ok = true := by simpa [Ty.ok] using htok
  have hsv : s.holdsView = false := by simpa [Ty.holdsView] using hvf
  have hsa : s.hasArc = false := by simpa [Ty.hasArc] using hna'
  have hdv : (v.ids ++ idsL es).Nodup := (List.nodup_cons.mp (List.nodup_cons.mp hnd0).2).2
  have hin0 : ∀ i ∈ v.ids, i ∈ c :: d :: (v.ids ++ idsL es) := fun i hi' => by simp [hi']
  refine out_ownNoView (by simp [Ty.ok, hso]) (by simp [Ty.holdsView, hsv]) (by simp [Ty.hasArc, hsa]) rfl
    (.inr hwv.1) (by simpa using (List.nodup_append.mp hdv).1)
    (fun i hi' => ⟨(hall0 i (hin0 i (by simpa using hi'))).1, (hall0 i (hin0 i (by simpa using hi'))).2.1⟩)
    (fun x U hU i hi' => (hall0 i (hin0 i (by simpa using hi'))).2.2.1 x U hU) ?_
  intro i hi' ⟨k', bl, hk', hik⟩
  have hiv : i ∈ v.ids := by simpa using hi'
  by_cases he : k' = k
  · subst he
    simp only [upd, ite_true, Option.some.injEq] at hk'
    subst hk'
    have hik' : i ∈ c :: d :: idsL es := by simpa [Blk.tree] using hik
    simp only [List.nodup_cons, List.mem_cons, List.mem_append, not_or] at hnd0
    rcases List.mem_cons.mp hik' with rfl | hik'
    · exact hnd0.1.2.1 hiv
    rcases List.mem_cons.mp hik' with rfl | hik'
    · exact hnd0.2.1.1 hiv
    · exact (List.nodup_append.mp hdv).2.2 i hiv i hik' rfl
  · have hk'' : m.blk k' = some bl := by simpa [upd, he] using hk'
    exact (hall0 i (hin0 i hiv)).2.2.2 k' bl he hk'' hik

/-- A3.4, `chan_close`: the flag is set; the payload's addresses stay as
    they were (the flag owns none). -/
theorem chanClose_pres {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) {k : Nat} {t : Ty} {q : Val}
    {f : Nat} (hk : m.blk k = some ⟨t, .lock, some (.pair q (.int f))⟩) (hnv : ¬ HasView m.blk k) :
    RhsPost m { m with blk := upd m.blk k (some ⟨t, .lock, some (.pair q (.int 1))⟩) } Γ Γ F ∧
    RhsOut { m with blk := upd m.blk k (some ⟨t, .lock, some (.pair q (.int 1))⟩) } Γ intE (.int 0) false := by
  obtain ⟨_, _, hpay, _⟩ := hi.blocks k _ hk
  obtain ⟨hwp, _⟩ := hpay _ rfl
  obtain ⟨_, hnd, _⟩ := hi.heap.blk k _ hk
  have hw : WFv t (.pair q (.int 1)) := by
    cases hwp with
    | pair hq hfl => cases hfl; exact .pair hq .int
  have hnd' : (Val.pair q (.int 1)).ids.Nodup := by
    have : (Val.pair q (.int f)).ids.Nodup := hnd
    simpa using this
  exact ⟨setPay_pres hi hk hnv hw hnd' (fun i hi' => Or.inl (by simpa using hi')), intE_out _⟩

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
  | view hy hl ht hhv hha =>
    cases he with
    | view hvec => exact ⟨RhsPost.same hi, out_view hi hy hl ht hhv hha hvec⟩
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
        (fun s x h => ViewIn.inl_inv h) (hi.tyok hy) (fun u k p h => by cases h with | inl h => exact h)⟩
  | @inr a y Ey Γ1 D hy hly hpa ha =>
    cases he with
    | inr htk =>
      obtain ⟨post, pu⟩ := push_take hi hanch hy hly rfl hpa htk 
      exact ⟨post, out_inj pu ha (Or.inr rfl) (Or.inr rfl) (WFv.inr pu.wf) (fun s x h => ViewIn.inr h)
        (fun s x h => ViewIn.inr_inv h) (hi.tyok hy) (fun u k p h => by cases h with | inr h => exact h)⟩
  | @pack fs te ms q y cs Ey Γ1 D hy hly hte hpa hcaps hq =>
    cases he with
    | pack htk =>
      obtain ⟨post, pu⟩ := push_take hi hanch hy hly hte hpa htk 
      refine ⟨post, out_wrap pu rfl rfl (WFv.pkg pu.wf hq)
        (fun s x h => by cases h with | pkg h => exact h) (fun e h => by cases h; rfl) (by simp)
        (fun _ _ _ h => by cases h) (fun _ _ _ _ h => by cases h) (List.subset_append_left _ _)
        ?_ (pu.nok.append hcaps.named) ?_ ?_ (fun u k p h => by cases h with | pkg h _ => exact h)⟩
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
          (fun s x h => by rw [hty]; exact ViewIn.inl h) (by simp) hok.1
          (fun u k p h => by rw [hty]; exact ArcIn.inl h)⟩
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
          (fun s x h => by rw [hty]; exact ViewIn.inr h) (by simp) hok.2
          (fun u k p h => by rw [hty]; exact ArcIn.inr h)⟩
  | arcNew hy hly hty hpl _ hpa =>
    cases he with
    | arcNew htk hfr =>
      obtain ⟨post, pu⟩ := push_take hi hanch hy hly hty hpa htk
      exact rhs_arcNew post pu hpl (hty ▸ hi.tyok hy) hfr
  | arcClone ha hl hty =>
    cases he with
    | arcClone hv => exact ⟨RhsPost.same hi, out_arcClone hi ha hl hty hv⟩
  | lockNew hy hly hty hpl hpa =>
    cases he with
    | lockNew htk hfr =>
      obtain ⟨post, pu⟩ := push_take hi hanch hy hly hty hpa htk
      exact rhs_lockNew post pu hpl (hty ▸ hi.tyok hy) hfr
  | lockClone ha hl hty =>
    cases he with
    | lockClone hv => exact ⟨RhsPost.same hi, out_lockClone hi ha hl hty hv⟩
  | cellNew hy hly hty hpl hpa =>
    cases he with
    | cellNew htk hfr =>
      obtain ⟨post, pu⟩ := push_take hi hanch hy hly hty hpa htk
      exact rhs_cellNew post pu hpl (hty ▸ hi.tyok hy) hfr
  | cellClone ha hl hty hos =>
    cases he with
    | cellClone hv => exact ⟨RhsPost.same hi, out_cellClone hi ha hl hty hos hv⟩
  | glob _ htok =>
    cases he with
    | glob _ hf => exact ⟨RhsPost.same hi, out_glob hi htok hf⟩
  | rwRead ha hl hty =>
    cases he with
    | rwRead hv hk hfr =>
      obtain ⟨_, hk'⟩ := hi.lk_val ha hl hty hv
      rw [hk] at hk'; cases hk'
      exact rhs_rwRead hi hk hfr
  | atomic _ _ _ _ _ =>
    cases he with
    | atomic _ hk _ _ hnv => exact atomic_pres hi hk hnv
  | chanSend ha hl hty hy hly htyy hpa =>
    cases he with
    | @chanSend _ _ _ _ _ _ _ _ _ _ mt hv htk hk _ _ hnv =>
      obtain ⟨post, pu⟩ := push_take hi hanch hy hly htyy hpa htk
      obtain ⟨_, hk'⟩ := hi.lk_val ha hl hty hv
      have hb1 : mt.blk = m.blk := by cases htk <;> rfl
      rw [← hb1, hk] at hk'; cases hk'
      exact ⟨chanSend_pres post pu hk hnv, intE_out _⟩
    | chanSendClosed _ htk _ hf =>
      obtain ⟨post, pu⟩ := push_take hi hanch hy hly htyy hpa htk
      exact ⟨chanSendClosed_pres post pu hf, intE_out _⟩
  | chanRecv ha hl hty =>
    cases he with
    | chanRecv hv hk _ _ hnv =>
      obtain ⟨_, hk'⟩ := hi.lk_val ha hl hty hv
      rw [hk] at hk'; cases hk'
      exact chanRecv_pres hi hk hnv
    | chanRecvNone _ _ _ _ =>
      obtain ⟨hso, hsv, hsa⟩ := chan_tyok (by rw [← hty]; exact hi.tyok ha)
      exact ⟨RhsPost.same hi, out_ownNoView (by simp [Ty.ok, hso]) (by simp [Ty.holdsView, hsv])
        (by simp [Ty.hasArc, hsa]) rfl (.inl .int) (by simp) (by simp) (by simp) (by simp)⟩
  | chanClose _ _ _ =>
    cases he with
    | chanClose _ hk hnv => exact chanClose_pres hi hk hnv
  | arcGet ha hl hty hhv hfn =>
    cases he with
    | arcGet hv hbk =>
      obtain ⟨hk, _, _⟩ := hi.arc_val ha hl hty hv
      obtain ⟨bl', hbl', hrd⟩ := hk.rd
      rw [hbl'] at hbk; cases hbk; rw [hrd]
      exact ⟨RhsPost.same hi, out_arcGet hi ha hl hty hhv hfn hv⟩

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
      ArmOK.of_dbind (by simp [(RhsT.dtor_false hr).2]),
      fun ho T hT => by cases hT; exact (out.shares (by rw [← out.own]; exact ho)).of_blk rfl⟩
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
      (fun hd => absurd hd (by simp [(RhsT.dtor_false hr).2])), post.blk⟩
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
      fun o U h => hh.alloc o U (hown o U h).2, fun o U h => hh.self o U (hown o U h).2,
      hh.blk.frame rfl (Nat.le_refl _) (fun _ _ => rfl) (fun o U h i hi => hh.notPay (hown o U h).2 hi),
      hh.views⟩
  | borrowed =>
    exact ⟨fun o U h => hh.nodup o U (hown o U h).2,
      fun o1 o2 U1 U2 hne h1 h2 => hh.disj o1 o2 U1 U2 hne (hown o1 U1 h1).2 (hown o2 U2 h2).2,
      fun o U h => hh.alloc o U (hown o U h).2, fun o U h => hh.self o U (hown o U h).2,
      hh.blk.frame rfl (Nat.le_refl _) (fun _ _ => rfl) (fun o U h i hi => hh.notPay (hown o U h).2 hi),
      hh.views⟩

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
    (hdis : ∀ o U, OwnedAt m o U → ∀ i ∈ v.ids, i ∉ U.ids) (hnp : ∀ i ∈ v.ids, ¬ PayAddr m i)
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
  have hblk : BlkOwn ({ m with alloc := A', nid := N' }.set x ⟨true, some (.node t c d' (es ++ [v]))⟩) :=
    hh.blk.frame rfl hNle
      (fun i hi => hA i (fun h => hh.notPay hT (by rw [h]; simp) hi)
        (fun h => by have := (hh.payAlloc hi).2; omega))
      (fun o U hU i hi hp => by
        rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
        · rcases hmem i hi with h | h | h | h
          · exact hh.notPay hT (by rw [h]; simp) hp
          · rcases hd'cases with h' | h' <;> rw [h'] at h
            · exact hh.notPay hT (by rw [h]; simp) hp
            · have := (hh.payAlloc hp).2; omega
          · exact hh.notPay hT (by simp [h]) hp
          · exact hnp i h hp
        · exact hh.notPay h hi hp)
  refine ⟨fun o U hU => ?_, fun o1 o2 U1 U2 hne h1 h2 => ?_, fun o U hU i hi => ?_, fun o U hU => ?_, hblk, hh.views⟩
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
  obtain ⟨c', es', _, hla, _, _⟩ := ha
  rcases hla with ⟨n0, hrn, hk⟩ | ⟨_, _, k, bl, hk, hsP⟩
  case inr =>
    exact owned_pay_head hi.heap hT hk hsub hsP (i := d) (by simp [Val.head]) (by simp [Val.head])
  have hN : Sub (.node s c' d es') n0 := hk.sub
  obtain ⟨Er, hEr, hroot⟩ := hr
  rcases hrn with ⟨T0, hown, htop⟩ | ⟨w1, c1, hc, ht1, hnode⟩ | ⟨w1, d1, o1, l1, hc, ht1, hdata⟩ |
    ⟨w1, k1, q1, hc, ht1, rfl⟩
  · exact hne (owned_unique hi.heap hown hT (hN.trans htop.sub) hsub (i := d) (by simp [Val.head])
      (by simp [Val.head])).1
  rotate_left 2
  · cases hN
  all_goals
    obtain ⟨sl, hsl, _, hso, _, _⟩ := hi.slot dep.root Er hEr
    have hrb : Er.mode = .rootb := by
      rw [hc] at hsl; cases hsl
      cases hme : Er.mode with
      | own => rw [hme] at hso; simp [Mode.ownSlot] at hso
      | inout b => exact absurd hme (hi.noInout _ Er b hEr)
      | rootb => rfl
      | bor => rw [hme] at hroot; simp [Mode.isRoot] at hroot
  · rcases rootb_anchor hi hanch dep.root Er n0 hEr hrb
      (Or.inr (Or.inl ⟨w1, c1, hc, ht1, hnode⟩))
      (by obtain ⟨_, _, _, h⟩ := hnode.eq; rw [h]; intro _ _ h'; cases h') with
      ⟨o', T', hoF, hoT, hsT⟩ | ⟨k, bl, hk, hsP⟩
    · have := (owned_unique hi.heap hoT hT (hN.trans hsT) hsub (i := d) (by simp [Val.head])
        (by simp [Val.head])).1
      subst this; exact hxF hoF
    · exact owned_pay_head hi.heap hT hk hsub (hN.trans hsP) (i := d) (by simp [Val.head])
        (by simp [Val.head])
  · rcases rootb_anchor hi hanch dep.root Er n0 hEr hrb
      (Or.inr (Or.inr (Or.inl ⟨w1, d1, o1, l1, hc, ht1, hdata⟩)))
      (by obtain ⟨_, _, _, h⟩ := hdata.eq; rw [h]; intro _ _ h'; cases h') with
      ⟨o', T', hoF, hoT, hsT⟩ | ⟨k, bl, hk, hsP⟩
    · have := (owned_unique hi.heap hoT hT (hN.trans hsT) hsub (i := d) (by simp [Val.head])
        (by simp [Val.head])).1
      subst this; exact hxF hoF
    · exact owned_pay_head hi.heap hT hk hsub (hN.trans hsP) (i := d) (by simp [Val.head])
        (by simp [Val.head])

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
      rcases hnode with ⟨rfl, _⟩ | ⟨u', c', es', hs'⟩ | hs'
      · rcases ha.owned hi.heap with ⟨ox, U, hU, hdU⟩ | hpa
        · exact hfresh U ox hU hdU rfl
        · have := (hi.heap.payAlloc hpa).2; omega
      · exact hsfT _ o0 l0 h u' c' es' hs'
      · rcases ha.owned hi.heap with ⟨ox, U, hU, hdU⟩ | hpa
        · exact hp.dis ox U hU _ (hs'.ids _ (by simp)) hdU
        · exact hp.np _ (hs'.ids _ (by simp)) hpa
    · obtain ⟨s, hin⟩ := hp.wf.sub_view h
      obtain ⟨d1, o1, l1, hv1, dep, hd, ha⟩ := hp.vs s _ hin
      cases hv1
      have hne : dep.root ≠ x := fun heq => hxD (heq ▸ List.mem_map_of_mem hd)
      rcases hnode with ⟨rfl, _⟩ | ⟨u', c', es', hs'⟩ | hs'
      · rcases ha.owned hi.heap with ⟨ox, U, hU, hdU⟩ | hpa
        · exact hfresh U ox hU hdU rfl
        · have := (hi.heap.payAlloc hpa).2; omega
      · exact viewAt_not_in hi hanch hxF hT (hp.root dep.root (List.mem_map_of_mem hd)) hne ha
          u' c' es' hs'
      · exact hp.sf _ o0 l0 h u c0 es0 hs'
  -- A3.1: the grown tree's shares are the old tree's and the pushed value's
  have hshN : SharesOK m' (.vec t') (.node t' c d' (es ++ [v])) := by
    have h0 := hi.shares x Ex _ _ hx hT rfl rfl
    rw [hty] at h0
    exact h0.node_push hp.sh rfl
  refine hi.change hanch hx hxF (fun _ _ _ _ ⟨r, k⟩ _ hb hk => by cases k <;> simp_all [Kind.bound, Eff.kills])
    (by rw [hm]; simp) hst (hi.heap.grow hT hp.nd hp.al hp.dis hp.np hre hsfn) rfl ?_ ?_ hds (fun h => by cases h) (by simp)
    (fun _ Ex' hx' hl0 hh0 hhv => by
      simp only [Option.some.injEq] at hx'; subst hx'
      rw [hty] at hhv
      exact ⟨hl0, by simp [hh0, hD hhv]⟩)
  · intro k hk
    have hev : Evolve m1 m' x t' c d d' es (es ++ [v]) := ⟨hT, by simp [m'], hwT', rfl⟩
    have hpre : ∀ e ∈ es, e ∈ es ++ [v] := fun e he => List.mem_append_left _ he
    have hkv : k ≠ .view := by intro h; subst h; simp [Eff.kills] at hk
    exact ⟨hev.grow_vkeep hpre hkv, hev.grow_hkeep hpre (fun h => by subst h; simpa [Eff.kills] using hk)
      hkv hshN⟩
  · refine ⟨⟨true, some (.node t' c d' (es ++ [v]))⟩, by simp [m'], by rw [hty]; exact hi.tyok hx ▸ (by
        rw [hty]), ⟨by simp [hos], fun _ => ⟨by rw [hty]; rfl, fun U hU => by cases hU; rw [hty]; exact hwT',
        fun _ => ⟨_, rfl, ?_⟩⟩, fun h => by simp [hos] at h⟩, rfl, fun hl' hn r hr => ?_, rfl,
        fun _ _ => ?_, fun _ T hT => ?_, fun T hT => ?_, fun _ _ _ dep hdd _ => ?_,
        fun hd => hi.wf.arm x Ex hx hd, fun hd => hi.wf.view x Ex hx hd,
        -- (a binding `letd` made gains no view: none is pushed into)
        fun hd => absurd (hdbv hd) (by
          have h := hi.wf.view x Ex hx hd
          rw [hty] at h; simp only [Ty.holdsView] at h; rw [h]; simp),
        fun _ T hT => by cases hT; rw [hty]; exact hshN⟩
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
          obtain ⟨r, k⟩ := dep
          by_cases hne : r = x
          · subst hne
            by_cases hks : k = .share
            · subst hks
              exact vkeep_share (m := m1) (m' := m') (BlkLe.refl _) (RootMem.own (o := some (.node t' c d' (es ++ [v]))) (by simp [m'])) d0 o0 l0 s ha
            · exact (viewAt_not_self hT hsfT (ViewIn.child h hin) hks ha).elim
          exact (keep_notx hi hanch hxF hst (hrootH _ hd) hne).1 d0 o0 l0 s ha
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
  refine ⟨fun n hn => ?_, fun o ho => ⟨o, by simp [upd_ne _ _ hr, ho]⟩⟩
  rcases hn with ⟨T0, hn, ht⟩ | ⟨v, c, hc, ht, hnode⟩ | ⟨v, d, o', l, hc, ht, hdata⟩ | ⟨v, k, q, hc, ht, hn⟩
  · exact Or.inl ⟨T0, by simp [upd_ne _ _ hr, hn], ht⟩
  · exact Or.inr (Or.inl ⟨v, c, by simp [upd_ne _ _ hr, hc], ht, hnode.mono hown (BlkLe.refl _)⟩)
  · exact Or.inr (Or.inr (Or.inl ⟨v, d, o', l, by simp [upd_ne _ _ hr, hc], ht, hdata.mono hown (BlkLe.refl _)⟩))
  · exact Or.inr (Or.inr (Or.inr ⟨v, k, q, by simp [upd_ne _ _ hr, hc], ht, hn⟩))

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
    (hr : RootNode m p n0) (hn0 : ∀ k q, n0 ≠ .arc k q) : ∃ d' ∈ E.path ++ E.held, Landed m d' n0 :=
  bor_lands hh hp hok hr hn0

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

/-- What lands through `p`, a borrowed slot, lands through one of `p`'s own
    dependencies, composed: `p` reaches memory only through them. A3.1: so
    does what lands through a share dependency on `p`, since `p` then
    reaches memory (`RootMem`: a handle or a share at the top of its value),
    and a share composed with anything is a share. -/
theorem reroot_landed (hh : HeapOK m) (hp : m.st p = some ⟨false, some w⟩)
    (hok : ValOK m Ep.ty w Ep.path Ep.held) {k : Kind} {n : Val} (hn : ∀ k q, n ≠ .arc k q)
    (hla : Landed m ⟨p, k⟩ n) :
    ∃ d' ∈ Ep.path ++ Ep.held, d'.kind.isName = false ∧ Landed m ⟨d'.root, comp d'.kind k⟩ n := by
  rcases hla with ⟨n0, hr, hl⟩ | ⟨hk, hro, hin⟩
  · have hn0 : ∀ k q, n0 ≠ .arc k q := fun k q h => hn k q (lands_arc (h ▸ hl))
    obtain ⟨d', hd', hla1⟩ := rootb_lands hh hp hok hr hn0
    exact ⟨d', hd', hla1.notName, hla1.comp hl⟩
  · simp only at hk; subst hk
    rcases hro with ⟨o, ho⟩ | ⟨n0, hr⟩
    · simp only at ho; rw [hp] at ho; cases ho
    obtain ⟨d', hd', hla1⟩ := bor_arcLanded hh hp hok hr
    refine ⟨d', hd', hla1.notName, Or.inr ⟨?_, hla1.rootMem, hin⟩⟩
    show comp d'.kind .share = .share
    have := hla1.notName
    cases hk : d'.kind <;> simp_all [comp, Kind.isName]

/-- ... and so does a share (`ArcLanded`). -/
theorem reroot_arcLanded (hh : HeapOK m) (hp : m.st p = some ⟨false, some w⟩)
    (hok : ValOK m Ep.ty w Ep.path Ep.held) {k : Kind} {n : Val} (hla : ArcLanded m ⟨p, k⟩ n) :
    ∃ d' ∈ Ep.path ++ Ep.held, d'.kind.isName = false ∧ ArcLanded m ⟨d'.root, comp d'.kind k⟩ n := by
  rcases hla with ⟨n0, hr, hl⟩ | ⟨hk, hro⟩
  · obtain ⟨d', hd', hla1⟩ := bor_arcLanded hh hp hok hr
    exact ⟨d', hd', hla1.notName, hla1.comp hl⟩
  · simp only at hk; subst hk
    rcases hro with ⟨o, ho⟩ | ⟨n0, hr⟩
    · simp only at ho; rw [hp] at ho; cases ho
    obtain ⟨d', hd', hla1⟩ := bor_arcLanded hh hp hok hr
    refine ⟨d', hd', hla1.notName, Or.inr ⟨?_, hla1.rootMem⟩⟩
    show comp d'.kind .share = .share
    have := hla1.notName
    cases hk : d'.kind <;> simp_all [comp, Kind.isName]

/-- What depended on `p` in way `k` now depends on what `p` borrowed: of it,
    what `p` reaches in memory (`D`) is enough. -/
theorem reroot_vkeep (hh : HeapOK m) (hp : m.st p = some ⟨false, some w⟩)
    (hok : ValOK m Ep.ty w Ep.path Ep.held) {D : List Dep} (_hDs : D ⊆ Ep.path ++ Ep.held)
    (hDm : ∀ d ∈ Ep.path ++ Ep.held, d.kind.isName = false → d ∈ D) (hlt : ∀ d' ∈ D, d'.root ≠ p)
    {ds : List Dep} {dep : Dep} (hd : dep ∈ ds) {d o l : Nat} {s : Ty}
    (ha : ViewAt m dep d o l s) : ∃ dep' ∈ reroot p D ds, ViewAt (m.remove p) dep' d o l s := by
  obtain ⟨c, es, hk, hla, hlen, hw⟩ := ha
  by_cases hrp : dep.root = p
  · obtain ⟨r, k⟩ := dep
    simp only at hrp hk; subst hrp
    obtain ⟨d', hd', hnm, hla1⟩ := reroot_landed hh hp hok (by intro _ _ h; cases h) hla
    have hdD := hDm d' hd' hnm
    exact ⟨⟨d'.root, comp d'.kind k⟩, mem_reroot_of_eq hd hdD, c, es, comp_ne_self hk,
      hla1.keep (rootKeep_rmbor hp (hlt d' hdD)) (BlkLe.refl _), hlen, hw⟩
  · exact ⟨dep, mem_reroot_of_ne hd hrp, c, es, hk, hla.keep (rootKeep_rmbor hp hrp) (BlkLe.refl _),
      hlen, hw⟩

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
  | arc h hw hv hl =>
    intro D hDs hDm hlt _
    obtain ⟨dep, hd, hla⟩ := hl
    by_cases hrp : dep.root = p
    · obtain ⟨r, k⟩ := dep
      simp only at hrp; subst hrp
      obtain ⟨d', hd', hnm, hla1⟩ := reroot_arcLanded hh hp hok hla
      have hdD := hDm d' hd' hnm
      exact .arc h hw hv ⟨_, mem_reroot_of_eq hd hdD, hla1.keep (rootKeep_rmbor hp (hlt d' hdD))⟩
    · exact .arc h hw hv ⟨dep, mem_reroot_of_ne hd hrp, hla.keep (rootKeep_rmbor hp hrp)⟩
  | lk h => intro _ _ _ _ _; exact .lk h
  | cell => intro _ _ _ _ _; exact .cell
  | pair _ _ ihx ihy =>
    intro D hDs hDm hlt hnp
    have hx := ihx hDs hDm hlt hnp; have hy := ihy hDs hDm hlt hnp
    rw [happ] at hx hy; exact .pair hx hy
  | inl _ ih => intro D hDs hDm hlt hnp; have hx := ih hDs hDm hlt hnp; rw [happ] at hx; exact .inl hx
  | inr _ ih => intro D hDs hDm hlt hnp; have hx := ih hDs hDm hlt hnp; rw [happ] at hx; exact .inr hx
  | @pkg fs te ms q x cs P0 H0 _ hq ih =>
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
      (reroot_sub (envDeps_sub _ _) h), fun _ h => List.mem_append_right _ (hr h)⟩) hr) hq
  | view h =>
    intro D hDs hDm hlt _
    obtain ⟨dep, hd, ha⟩ := h
    obtain ⟨dep', hd', ha'⟩ := reroot_vkeep hh hp hok hDs hDm hlt hd ha
    exact .view ⟨dep', hd', ha'⟩
  | @href t c P H h =>
    intro D hDs hDm hlt hnp
    obtain ⟨dep, hd, d, es, hla, hw, hvs, hns, hsh⟩ := h
    have hvs' := reroot_views hh hp hok hDs hDm hlt hvs
    have hns' := hns.reroot D hnp
    by_cases hrp : dep.root = p
    · obtain ⟨r, k⟩ := dep
      simp only at hrp; subst hrp
      obtain ⟨d', hd', hnm, hla1⟩ := reroot_landed hh hp hok (by intro _ _ h; cases h) hla
      have hdD := hDm d' hd' hnm
      exact .href ⟨⟨d'.root, comp d'.kind k⟩, mem_reroot_of_eq hd hdD, d, es,
        hla1.keep (rootKeep_rmbor hp (hlt d' hdD)) (BlkLe.refl _), hw, hvs', hns',
        hsh.of_blk rfl⟩
    · exact .href ⟨dep, mem_reroot_of_ne hd hrp, d, es, hla.keep (rootKeep_rmbor hp hrp) (BlkLe.refl _),
        hw, hvs', hns', hsh.of_blk rfl⟩

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
  · -- A3.1: the slots that own are as they were, and so are the blocks
    intro v E' sl T hv' hsl hown hT
    have hvp : v ≠ p := fun h => by subst h; simp [exitRoot] at hv'
    obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvp
    have hsl0 : m.st v = some sl := by simpa [Mem.remove_st, upd_ne _ _ hvp] using hsl
    exact (hi.shares v E sl T hE hsl0 hown hT).of_blk rfl
  · intro k bl hk
    obtain ⟨h1, h2, h3, h4⟩ := hi.blocks k bl hk
    exact ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, (h3 p hp).2.of_blk rfl⟩, h4⟩

/-! ### A3.1: the counted blocks only grow -/

theorem TakeVal.blk {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) : m1.blk = m.blk := by
  cases h <;> rfl

theorem EvalR.blk {m m' : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m')) :
    BlkLe m.blk m'.blk := by
  cases h with
  | pair h1 h2 => exact BlkLe.of_eq ((TakeVal.blk h2).trans (TakeVal.blk h1))
  | inl h1 => exact BlkLe.of_eq (TakeVal.blk h1)
  | inr h1 => exact BlkLe.of_eq (TakeVal.blk h1)
  | pack h1 => exact BlkLe.of_eq (TakeVal.blk h1)
  | @arcNew t y v m1 htk hfr =>
    refine BlkLe.of_le fun k bl hk => ?_
    have hk1 : m1.blk k = some bl := by rw [TakeVal.blk htk]; exact hk
    have hne : k ≠ m1.nid := fun h => by rw [h, hfr] at hk1; cases hk1
    show upd m1.blk m1.nid _ k = some bl
    rw [upd_ne _ _ hne]; exact hk1
  | @lockNew t y v m1 htk hfr =>
    refine BlkLe.of_le fun k bl hk => ?_
    have hk1 : m1.blk k = some bl := by rw [TakeVal.blk htk]; exact hk
    have hne : k ≠ m1.nid := fun h => by rw [h, hfr] at hk1; cases hk1
    show upd m1.blk m1.nid _ k = some bl
    rw [upd_ne _ _ hne]; exact hk1
  | @cellNew t y v m1 htk hfr =>
    refine BlkLe.of_le fun k bl hk => ?_
    have hk1 : m1.blk k = some bl := by rw [TakeVal.blk htk]; exact hk
    have hne : k ≠ m1.nid := fun h => by rw [h, hfr] at hk1; cases hk1
    show upd m1.blk m1.nid _ k = some bl
    rw [upd_ne _ _ hne]; exact hk1
  | atomic _ hk _ _ => exact BlkLe.setLock hk _
  | chanSend _ h1 hk _ _ => exact (BlkLe.of_eq (TakeVal.blk h1)).trans (BlkLe.setLock hk _)
  | chanSendClosed _ h1 _ _ => have := BlkLe.of_eq (TakeVal.blk h1); exact this
  | chanRecv _ hk _ _ => exact BlkLe.setLock hk _
  | chanClose _ hk => exact BlkLe.setLock hk _
  | rwRead _ _ hfr => exact BlkLe.fresh hfr _
  | _ => exact BlkLe.refl _

theorem BindParams.blk {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') : m'.blk = m.blk := by
  induction h with
  | nil => rfl
  | inp _ _ _ ih => exact ih
  | sink _ _ ih => exact ih
  | inout _ ih => exact ih

theorem Release.blk {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (h : Release m k t x m') : BlkLe m.blk m'.blk := by
  cases h with
  | put _ _ hk => exact BlkLe.setLock hk _
  | drop _ _ _ => exact BlkLe.refl _

theorem Step.blk {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) : BlkLe m.blk r.mem.blk := by
  induction h with
  | seqL _ ih | seqP _ ih | scopeIn _ ih | rbindIn _ ih | frozenIn _ ih | frozenP _ ih | catchIn _ ih
    | scopeDIn _ ih | scopeLIn _ ih => exact ih
  | withLock _ hk _ => exact BlkLe.setLock hk _
  | scopeLSkip hr => exact hr.blk
  | scopeLP _ hr ih => exact ih.trans hr.blk
  | scopeP _ _ _ ih | rbindP _ _ ih | catchP _ _ ih | scopeDP _ _ ih | scopeDPMoved _ _ ih => exact ih
  | letv _ he | letd _ he | assign _ he _ _ => have := EvalR.blk he; exact this
  | letcall _ _ hb => have := BlkLe.of_eq (BindParams.blk hb); exact this
  | callc _ _ _ _ hb => have := BlkLe.of_eq (BindParams.blk hb); exact this
  | push ht _ _ _ => have := BlkLe.of_eq (TakeVal.blk ht); exact this
  | pushRealloc ht _ _ _ => have := BlkLe.of_eq (TakeVal.blk ht); exact this
  | insert _ ht _ _ _ => have := BlkLe.of_eq (TakeVal.blk ht); exact this
  | editPush ht _ _ | editPushRealloc ht _ _ => have := BlkLe.of_eq (TakeVal.blk ht); exact this
  | editSet _ _ ht _ _ _ | editSetOOB _ ht _ _ _ => have := BlkLe.of_eq (TakeVal.blk ht); exact this
  | _ => exact BlkLe.refl _

/-! ### A3.2's second cut: where what a payload holds goes

A lock block's payload may hold shares, and keeps their blocks alive
(`Reached`).  A step changes a lock's payload only by taking a part of it
out to the stepping thread (a check-out, a received element), adding to it,
or changing what owns no address; so a share (or any handle: `Val.leaf`) a
payload held is still in it afterwards, or in one of the thread's slots
(`Step.leafKeep`).  A3 reads this to show that what another thread reached
through a lock it still reaches, or the stepping thread does. -/

/-- A value `Sub` does not look into and that is no tree: a handle or a
    share, what `Refers` looks for. -/
def Val.leaf : Val → Prop
  | .href _ => True
  | .view _ _ _ => True
  | .arc _ _ => True
  | .lk _ => True
  | .cell _ => True
  | _ => False

theorem Sub.leaf_int {w : Val} (hw : w.leaf) {n : Nat} (h : Sub w (.int n)) : False := by
  rw [h.int_eq] at hw; exact hw

theorem Sub.pair_inv {x a b : Val} (h : Sub x (.pair a b)) : x = .pair a b ∨ Sub x a ∨ Sub x b := by
  cases h with
  | refl => exact .inl rfl
  | fst h => exact .inr (.inl h)
  | snd h => exact .inr (.inr h)

theorem Sub.node_inv {x : Val} {t : Ty} {c d : Nat} {es : List Val} (h : Sub x (.node t c d es)) :
    x = .node t c d es ∨ ∃ e ∈ es, Sub x e := by
  cases h with
  | refl => exact .inl rfl
  | child he h => exact .inr ⟨_, he, h⟩

theorem Sub.leaf_pair {w a b : Val} (hw : w.leaf) (h : Sub w (.pair a b)) : Sub w a ∨ Sub w b := by
  rcases h.pair_inv with he | h | h
  · subst he; exact absurd hw id
  · exact .inl h
  · exact .inr h

theorem Sub.leaf_node {w : Val} (hw : w.leaf) {t : Ty} {c d : Nat} {es : List Val}
    (h : Sub w (.node t c d es)) : ∃ e ∈ es, Sub w e := by
  rcases h.node_inv with he | h
  · subst he; exact absurd hw id
  · exact h

/-- What refers to a block does so through one handle or share it holds. -/
theorem Refers.leaf {B : Nat → Option Blk} {v : Val} {k : Nat} (h : Refers B v k) :
    ∃ w, w.leaf ∧ Sub w v ∧ ∀ v', Sub w v' → Refers B v' k := by
  rcases h with (⟨p, hp⟩ | hp) | ⟨bl, hk, ⟨c, hc, hci⟩ | ⟨d, o, l, hd, hdi⟩⟩
  · refine ⟨Val.share k p, by cases p <;> trivial, hp, fun v' h => Or.inl (Or.inl ⟨p, h⟩)⟩
  · exact ⟨.cell k, trivial, hp, fun v' h => Or.inl (Or.inr h)⟩
  · exact ⟨.href c, trivial, hc, fun v' h => Or.inr ⟨bl, hk, Or.inl ⟨c, h, hci⟩⟩⟩
  · exact ⟨.view d o l, trivial, hd, fun v' h => Or.inr ⟨bl, hk, Or.inr ⟨d, o, l, h, hdi⟩⟩⟩

/-- A3.2's second cut: **a right-hand side keeps what a payload holds**: in
    the block's payload, or in the value it hands back (a received element,
    a taken payload). -/
theorem EvalR.leafKeep {m m' : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m'))
    {k : Nat} {bl : Blk} (hk : m.blk k = some bl) {w : Val} (hw : w.leaf) (hs : Sub w bl.keeps) :
    (∃ bl', m'.blk k = some bl' ∧ Sub w bl'.keeps) ∨ Sub w v := by
  have same : ∀ {m1 : Mem}, m1.blk = m.blk → ∃ bl', m1.blk k = some bl' ∧ Sub w bl'.keeps :=
    fun he => ⟨bl, by rw [he]; exact hk, hs⟩
  -- a new block at a fresh key keeps the others
  have fresh : ∀ {m1 : Mem} (b : Blk), m1.blk = m.blk → m1.blk m1.nid = none →
      ∃ bl', upd m1.blk m1.nid (some b) k = some bl' ∧ Sub w bl'.keeps := by
    intro m1 b he hfr
    have hne : k ≠ m1.nid := fun e => by rw [← he, e, hfr] at hk; cases hk
    exact ⟨bl, by rw [upd_ne _ _ hne, he]; exact hk, hs⟩
  -- a lock's payload changed at `k0`: another block is as it was
  have other : ∀ {k0 : Nat} (b : Blk), k ≠ k0 → ∃ bl', upd m.blk k0 (some b) k = some bl' ∧ Sub w bl'.keeps :=
    fun b hne => ⟨bl, by rw [upd_ne _ _ hne]; exact hk, hs⟩
  cases h with
  | pair h1 h2 => exact .inl (same ((TakeVal.blk h2).trans (TakeVal.blk h1)))
  | inl h1 => exact .inl (same (TakeVal.blk h1))
  | inr h1 => exact .inl (same (TakeVal.blk h1))
  | pack h1 => exact .inl (same (TakeVal.blk h1))
  | arcNew h1 hfr => exact .inl (fresh _ (TakeVal.blk h1) hfr)
  | lockNew h1 hfr => exact .inl (fresh _ (TakeVal.blk h1) hfr)
  | cellNew h1 hfr => exact .inl (fresh _ (TakeVal.blk h1) hfr)
  | rwRead _ _ hfr => exact .inl (fresh (m1 := m) _ rfl hfr)
  | @atomic op a e1 e2 o k0 n n1 n2 _ hk0 _ _ _ =>
    by_cases he : k = k0
    · subst he; rw [hk0] at hk; cases hk; exact absurd hs (Sub.leaf_int hw)
    · exact .inl (other _ he)
  | @chanSend a y o k0 t u c d es v1 m1 _ h1 hk0 _ _ _ =>
    have hk1 : m1.blk k = some bl := by rw [TakeVal.blk h1]; exact hk
    by_cases he : k = k0
    · subst he; rw [hk0] at hk1; cases hk1
      refine .inl ⟨⟨t, .lock, some (.pair (.node u c d (es ++ [v1])) (.int 0))⟩, by simp [upd], ?_⟩
      simp only [Blk.keeps_mk, Option.getD_some] at hs ⊢
      rcases Sub.leaf_pair hw hs with hs1 | hs1
      · obtain ⟨e, he, hs2⟩ := Sub.leaf_node hw hs1
        exact Sub.fst (Sub.child (List.mem_append_left _ he) hs2)
      · exact absurd hs1 (Sub.leaf_int hw)
    · exact .inl ⟨bl, by show upd m1.blk k0 _ k = some bl; rw [upd_ne _ _ he]; exact hk1, hs⟩
  | chanSendClosed _ h1 _ _ => have := TakeVal.blk h1; exact .inl (same this)
  | @chanRecv w' a o k0 t u c d f v1 es _ hk0 _ _ _ =>
    by_cases he : k = k0
    · subst he; rw [hk0] at hk; cases hk
      simp only [Blk.keeps_mk, Option.getD_some] at hs
      rcases Sub.leaf_pair hw hs with hs1 | hs1
      · obtain ⟨e, he, hs2⟩ := Sub.leaf_node hw hs1
        rcases List.mem_cons.mp he with he1 | he1
        · subst he1; exact .inr (Sub.inr hs2)
        · refine .inl ⟨⟨t, .lock, some (.pair (.node u c d es) (.int f))⟩, by simp [upd], ?_⟩
          simp only [Blk.keeps_mk, Option.getD_some]
          exact Sub.fst (Sub.child he1 hs2)
      · exact absurd hs1 (Sub.leaf_int hw)
    · exact .inl (other _ he)
  | @chanClose a o k0 t q f _ hk0 _ =>
    by_cases he : k = k0
    · subst he; rw [hk0] at hk; cases hk
      refine .inl ⟨⟨t, .lock, some (.pair q (.int 1))⟩, by simp [upd], ?_⟩
      simp only [Blk.keeps_mk, Option.getD_some] at hs ⊢
      rcases Sub.leaf_pair hw hs with hs1 | hs1
      · exact Sub.fst hs1
      · exact absurd hs1 (Sub.leaf_int hw)
    · exact .inl (other _ he)
  | _ => exact .inl (same rfl)

/-- A3.2's second cut: what a step's result says of what the stepping
    thread's slots hold afterwards (a panic's: nothing, its unwinding may drop
    it). -/
def Res.holds (r : Res) (w : Val) : Prop :=
  match r with
  | .ok m _ => ∃ v, m.vals v ∧ Sub w v
  | .panic _ => False

theorem Release.leafKeep {m m' : Mem} {k0 : Nat} {t : Ty} {x : Var} (h : Release m k0 t x m')
    {k : Nat} {bl : Blk} (hk : m.blk k = some bl) {w : Val} (hw : w.leaf) (hs : Sub w bl.keeps) :
    ∃ bl', m'.blk k = some bl' ∧ Sub w bl'.keeps := by
  cases h with
  | put _ _ hk0 =>
    by_cases he : k = k0
    · subst he; rw [hk0] at hk; cases hk; exact absurd hs (Sub.leaf_int hw)
    · exact ⟨bl, by show upd m.blk k0 _ k = some bl; rw [upd_ne _ _ he]; exact hk, hs⟩
  | drop _ _ _ => exact ⟨bl, hk, hs⟩

/-- A3.2's second cut: **a step keeps what a payload holds**: a share or a
    handle in a block's payload is in it afterwards, or (a step that does not
    panic) in one of the thread's slots — a checked-out payload, a received
    element, a taken one. -/
theorem Step.leafKeep {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) :
    ∀ {k : Nat} {bl : Blk}, m.blk k = some bl → ∀ {w : Val}, w.leaf → Sub w bl.keeps →
      (∃ bl', r.mem.blk k = some bl' ∧ Sub w bl'.keeps) ∨ r.holds w := by
  induction h with
  | seqL _ ih | seqP _ ih | scopeIn _ ih | rbindIn _ ih | frozenIn _ ih | frozenP _ ih | catchIn _ ih
    | scopeDIn _ ih | scopeLIn _ ih => exact ih
  | scopeP _ _ _ ih | rbindP _ _ ih | scopeDPMoved _ _ ih | catchP _ _ ih | scopeDP _ _ ih =>
    intro k bl hk w hw hs
    rcases ih hk hw hs with h | h
    · exact .inl h
    · exact absurd h id
  | scopeLP _ hr ih =>
    intro k bl hk w hw hs
    rcases ih hk hw hs with ⟨bl', hk', hs'⟩ | h
    · exact .inl (hr.leafKeep hk' hw hs')
    · exact absurd h id
  | scopeLSkip hr => intro k bl hk w hw hs; exact .inl (hr.leafKeep hk hw hs)
  | @letv m' x r s v o _ he =>
    intro k bl hk w hw hs
    rcases he.leafKeep hk hw hs with h | h
    · exact .inl h
    · exact .inr ⟨v, ⟨x, o, by simp [Mem.set, upd]⟩, h⟩
  | @letd m' x f r s v o _ he =>
    intro k bl hk w hw hs
    rcases he.leafKeep hk hw hs with h | h
    · exact .inl h
    · exact .inr ⟨v, ⟨x, o, by simp [Mem.set, upd]⟩, h⟩
  | @assign m1 x r v o sl a' _ he _ _ =>
    intro k bl hk w hw hs
    rcases he.leafKeep hk hw hs with h | h
    · exact .inl h
    · exact .inr ⟨v, ⟨x, o, by simp [Mem.set, upd]⟩, h⟩
  | @withLock a x s0 k0 t v _ hk0 _ _ =>
    intro k bl hk w hw hs
    by_cases he : k = k0
    · subst he; rw [hk0] at hk; cases hk
      exact .inr ⟨v, ⟨x, v.owns, by simp [Mem.set, upd]⟩, by simpa using hs⟩
    · exact .inl ⟨bl, by show upd m.blk k0 _ k = some bl; rw [upd_ne _ _ he]; exact hk, hs⟩
  | letcall _ _ hb =>
    intro k bl hk w hw hs
    exact .inl ⟨bl, by rw [← BindParams.blk hb] at hk; exact hk, hs⟩
  | callc _ _ _ _ hb =>
    intro k bl hk w hw hs
    exact .inl ⟨bl, (congrFun (BindParams.blk hb) k).trans hk, hs⟩
  | push ht _ _ _ | pushRealloc ht _ _ _ | editPush ht _ _ | editPushRealloc ht _ _
    | editSet _ _ ht _ _ _ | editSetOOB _ ht _ _ _ =>
    intro k bl hk w hw hs
    exact .inl ⟨bl, by rw [← TakeVal.blk ht] at hk; exact hk, hs⟩
  | _ => intro k bl hk w hw hs; exact .inl ⟨bl, hk, hs⟩

/-! ### A3.2: taking a lock -/

/-- A tree of a type that holds no view, other than an integer, is owned. -/
theorem WFv.owns_of {t : Ty} {v : Val} (hw : WFv t v) (ht : t ≠ .int) (hvf : t.holdsView = false) :
    v.owns = true := by
  cases hw <;> simp_all [Val.owns, Ty.holdsView]

theorem Ty.owning_of {t : Ty} (ht : t ≠ .int) (hvf : t.holdsView = false) : t.owning = true := by
  cases t <;> simp_all [Ty.owning, Ty.holdsView]

/-- **Taking a lock** (`withLock`): block `k`'s payload `v`, a `t`, is
    checked out.  The block keeps no payload (it stays a lock block of its
    type), and `v` is handed over as `lockE t`'s value: owned (an integer is
    a plain integer), holding nothing (it views nothing), its addresses in
    no owned tree and in no payload any more (`BlkOwn`). -/
theorem acquire_pres {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) {k : Nat} {t : Ty} {v : Val}
    (hk : m.blk k = some ⟨t, .lock, some v⟩) (hnv : ¬ HasView m.blk k) :
    RhsPost m { m with blk := upd m.blk k (some ⟨t, .lock, none⟩) } Γ Γ F ∧
    RhsOut { m with blk := upd m.blk k (some ⟨t, .lock, none⟩) } Γ (lockE t) v v.owns := by
  obtain ⟨htok, hvf, hpay, hna⟩ := hi.blocks k _ hk
  obtain ⟨hwv, _⟩ := hpay v rfl
  have hna' : t.hasArc = false := hna rfl
  have hb : BlkLe m.blk (upd m.blk k (some ⟨t, .lock, none⟩)) := BlkLe.setLock hk none
  obtain ⟨hkey, hnd, hall⟩ := hi.heap.blk k _ hk
  have hcases : ∀ k' bl, upd m.blk k (some ⟨t, .lock, none⟩) k' = some bl →
      (k' = k ∧ bl = ⟨t, .lock, none⟩) ∨ (k' ≠ k ∧ m.blk k' = some bl) := by
    intro k' bl h
    by_cases he : k' = k
    · subst he; simp [upd] at h; exact Or.inl ⟨rfl, h.symm⟩
    · exact Or.inr ⟨he, by simpa [upd, he] using h⟩
  have hbo : BlkOwn { m with blk := upd m.blk k (some ⟨t, .lock, none⟩) } := by
    intro k' bl hk'
    rcases hcases k' bl hk' with ⟨rfl, rfl⟩ | ⟨hne, h⟩
    · exact ⟨hkey, List.nodup_nil, fun i hi => by simp [Blk.tree] at hi⟩
    · obtain ⟨hkey', hnd', hall'⟩ := hi.heap.blk k' bl h
      refine ⟨hkey', hnd', fun i hi' => ?_⟩
      obtain ⟨ha, hlt, hsl, hoth⟩ := hall' i hi'
      refine ⟨ha, hlt, hsl, fun k'' bl'' hk'' h'' => ?_⟩
      rcases hcases k'' bl'' h'' with ⟨rfl, rfl⟩ | ⟨_, h2⟩
      · simp [Blk.tree]
      · exact hoth k'' bl'' hk'' h2
  have hheap : HeapOK { m with blk := upd m.blk k (some ⟨t, .lock, none⟩) } :=
    HeapOK.mono hi.heap rfl (fun _ h => h) (Nat.le_refl _) hbo (hi.heap.views.setLock hk hnv _)
  have hB : BlocksIn { m with blk := upd m.blk k (some ⟨t, .lock, none⟩) } := fun k' bl hk' => by
    rcases hcases k' bl hk' with ⟨rfl, rfl⟩ | ⟨_, h⟩
    · exact ⟨htok, hvf, fun p hp => (by cases hp), fun _ => hna'⟩
    · obtain ⟨h1, h2, h3, h4⟩ := hi.blocks k' bl h
      exact ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, (h3 p hp).2.grow hb⟩, h4⟩
  have hinv : MInv { m with blk := upd m.blk k (some ⟨t, .lock, none⟩) } Γ := hi.grow rfl hheap (Nat.le_refl _) hb hB
  refine ⟨⟨hinv, rfl, Nat.le_refl _, fun _ => rfl, fun _ _ => rfl, fun _ _ h _ => h, fun _ => rfl,
    fun _ E1 h => ⟨E1, h, rfl, rfl⟩, DKeep.refl _ _, hb⟩, ?_⟩
  by_cases hti : t = .int
  · subst hti
    cases hwv with
    | int =>
      have hE : lockE .int = intE := by simp [lockE]
      rw [hE]
      exact intE_out _
  · have hE : lockE t = ⟨t, .own, true, [], [], false, false⟩ := by simp [lockE, hti]
    rw [hE, WFv.owns_of hwv hti hvf]
    exact {
      own := rfl
      mode := Or.inl rfl
      live := rfl
      tyok := htok
      wf := fun _ r hr => by simp [roots, Entry.vdeps, Mode.ownSlot] at hr
      valOwn := fun _ => ⟨Ty.owning_of hti hvf, hwv, ViewsOK.none hvf _ _, hnd,
        fun i hi => ⟨(hall i hi).1, (hall i hi).2.1⟩, fun x U hU i hi => (hall i hi).2.2.1 x U hU,
        hwv.selfFree_noView hvf, fun i hi ⟨k', bl, hk', hik⟩ => by
          rcases hcases k' bl hk' with ⟨rfl, rfl⟩ | ⟨hne, h⟩
          · simp [Blk.tree] at hik
          · exact (hall i hi).2.2.2 k' bl hne h hik⟩
      valBor := fun h => nomatch h
      names := fun _ => DepsNamed.nil _
      held := NamesIn.nil _ (hwv.names_nil hvf)
      pkgs := hwv.pkgsOK_noView hvf
      shares := fun _ => SharesOK.of_noArc hna' }

end A2
