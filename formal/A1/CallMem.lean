import A1.Bind

/-! A1 — the memory side of the call step: the store after binding the
parameters satisfies the invariant in the context the call sets up. -/

namespace A1

/-- Owned trees that only change owner keep one owner per allocation. -/
theorem HeapOK.relabel {m m' : Mem} (hh : HeapOK m) (ha : m'.alloc = m.alloc) (hn : m'.nid = m.nid)
    (hsrc : ∀ o T, OwnedAt m' o T → ∃ p, OwnedAt m p T)
    (hinj : ∀ o1 o2 T1 T2, o1 ≠ o2 → OwnedAt m' o1 T1 → OwnedAt m' o2 T2 →
      ∃ p1 p2, p1 ≠ p2 ∧ OwnedAt m p1 T1 ∧ OwnedAt m p2 T2) : HeapOK m' where
  nodup o T hT := by obtain ⟨p, hp⟩ := hsrc o T hT; exact hh.nodup p T hp
  disj o1 o2 T1 T2 hne h1 h2 := by
    obtain ⟨p1, p2, hp, hp1, hp2⟩ := hinj o1 o2 T1 T2 hne h1 h2
    exact hh.disj p1 p2 T1 T2 hp hp1 hp2
  alloc o T hT i hi := by
    obtain ⟨p, hp⟩ := hsrc o T hT
    rw [ha, hn]; exact hh.alloc p T hp i hi

/-- A root whose slot is unchanged reaches the same memory, as long as every
    owned tree is still owned by someone. -/
theorem rootKeep_move {m m' : Mem} (hown : ∀ o T, OwnedAt m o T → ∃ o', OwnedAt m' o' T) {r : Var}
    (hr : m'.st r = m.st r) : RootKeep m m' r := by
  intro n hn
  rcases hn with hn | ⟨c, hc, o, T, hT, hs, hnode⟩ | ⟨d, o', l, hc, o, T, hT, hs, hdata⟩
  · exact Or.inl (by rw [hr]; exact hn)
  · obtain ⟨o2, h2⟩ := hown o T hT
    exact Or.inr (Or.inl ⟨c, by rw [hr]; exact hc, o2, T, h2, hs, hnode⟩)
  · obtain ⟨o2, h2⟩ := hown o T hT
    exact Or.inr (Or.inr ⟨d, o', l, by rw [hr]; exact hc, o2, T, h2, hs, hdata⟩)

theorem SlotOK.clean {m : Mem} {E : Entry} {sl : Slot} (h : SlotOK m E sl) : SlotOK m E.clean sl := by
  unfold Entry.clean
  split
  · rename_i hc
    obtain ⟨ho, hown, hbor⟩ := h
    refine ⟨ho, fun hos => ?_, fun hos hl => ?_⟩
    · obtain ⟨⟨t, ht⟩, hw, hv⟩ := hown hos
      refine ⟨⟨t, ht⟩, hw, fun hl => ?_⟩
      rcases hc.2 with hi | hd
      · rw [hi] at ht; cases ht
      · simp only at hl; rw [hd] at hl; cases hl
    · simp only at hl
      rcases hc.2 with hi | hd
      · obtain ⟨v, hv, hok⟩ := hbor hos hl
        refine ⟨v, hv, ?_⟩
        simp only
        rw [hi] at hok ⊢
        exact hok
      · rw [hd] at hl; cases hl
  · exact h

theorem SlotOK.weakLive {m : Mem} {E0 E1 : Entry} {sl : Slot} (h : SlotOK m E0 sl) (ht : E1.ty = E0.ty)
    (hm : E1.mode = E0.mode) (hp : E1.path = E0.path) (hh : E1.held = E0.held)
    (hl : E1.live = true → E0.live = true) : SlotOK m E1 sl := by
  obtain ⟨ho, hown, hbor⟩ := h
  refine ⟨by rw [hm]; exact ho, fun hos => ?_, fun hos hl1 => ?_⟩
  · rw [hm] at hos
    obtain ⟨h1, h2, h3⟩ := hown hos
    exact ⟨by rw [ht]; exact h1, by rw [ht]; exact h2, fun hl1 => by rw [ht, hh]; exact h3 (hl hl1)⟩
  · rw [hm] at hos
    obtain ⟨v, hv, hok⟩ := hbor hos (hl hl1)
    exact ⟨v, hv, by rw [ht, hp, hh]; exact hok⟩

/-- The store once the call step is taken. -/
def callMem (m m1 : Mem) (fn : Fn) (x : Var) : Mem :=
  { (m1.set x ⟨fn.resOwn, none⟩).set (m.nv + fn.params.length) ⟨fn.resOwn, none⟩ with nv := m.nv + fn.nvars }

namespace CallH
variable {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {fn : Fn} {args : List Var} {m : Mem} {base : Nat}

theorem args_lt (h : CallH P Γ F x fn args base) : ∀ a ∈ args, a < base := by
  intro a ha
  obtain ⟨i, hi, rfl⟩ := mem_args ha
  exact h.argLt (h.len ▸ hi)

theorem sink_distinct (h : CallH P Γ F x fn args base) :
    ∀ (k k' : Nat) (a : Var), k < k' → (∃ t, fn.params[k]? = some (PMode.sink, t)) → args[k]? = some a →
      args[k']? ≠ some a := by
  intro k k' a hkk ⟨t, hk⟩ ha ha'
  have hkl := lt_of_get hk
  have hk'l : k' < args.length := (List.getElem?_eq_some_iff.mp ha').1
  have he : args.getD k' 0 = args.getD k 0 := by simp [List.getD, ha, ha']
  have := h.moving hkl (h.len ▸ hk'l) (by rw [get_of hk]; rfl) he
  omega

theorem bind (h : CallH P Γ F x fn args m.nv) {m1 : Mem} (hb : BindParams m fn.params args m.nv 0 m1) :
    m1.alloc = m.alloc ∧ m1.nid = m.nid ∧ m1.nv = m.nv ∧ m1.st = bindSt m fn.params args m.nv 0 m.st :=
  bind_spec hb h.args_lt h.sink_distinct (fun _ _ => rfl)

theorem getD_of {k : Nat} (hk : k < args.length) : args[k]? = some (args.getD k 0) := by
  simp [List.getD, hk]

/-- The slots after the call step. -/
theorem st_x (h : CallH P Γ F x fn args m.nv) (m1 : Mem) :
    (callMem m m1 fn x).st x = some ⟨fn.resOwn, none⟩ := by
  have : x ≠ m.nv + fn.params.length := fun e => by have := vlt h.xlt; have := veq e; omega
  simp [callMem, upd_ne _ _ this]

theorem st_r (m1 : Mem) :
    (callMem m m1 fn x).st (m.nv + fn.params.length) = some ⟨fn.resOwn, none⟩ := by
  simp [callMem]

theorem st_bind (h : CallH P Γ F x fn args m.nv) {m1 : Mem} {y : Var} (hyx : y ≠ x)
    (hyr : y ≠ m.nv + fn.params.length) (hb : BindParams m fn.params args m.nv 0 m1) :
    (callMem m m1 fn x).st y = bindSt m fn.params args m.nv 0 m.st y := by
  simp [callMem, upd_ne _ _ hyx, upd_ne _ _ hyr, (h.bind hb).2.2.2]

theorem slot_ne (h : CallH P Γ F x fn args m.nv) {k : Nat} (hk : k < fn.params.length) :
    m.nv + 0 + k ≠ x ∧ m.nv + 0 + k ≠ m.nv + fn.params.length := by
  refine ⟨fun e => ?_, fun e => ?_⟩
  · have := vlt h.xlt; have := veq e; omega
  · have := veq e; omega

theorem arg_ne (h : CallH P Γ F x fn args m.nv) {k : Nat} (hk : k < fn.params.length) :
    args.getD k 0 ≠ x ∧ args.getD k 0 ≠ m.nv + fn.params.length := by
  obtain ⟨Ea, hEa, _⟩ := h.arg k hk
  refine ⟨fun e => (by rw [e, h.fresh] at hEa; cases hEa), fun e => ?_⟩
  have := vlt (h.argLt hk); have := veq e; omega

theorem st_inp (h : CallH P Γ F x fn args m.nv) {m1 : Mem} (hb : BindParams m fn.params args m.nv 0 m1)
    {k : Nat} {t : Ty} (hk : fn.params[k]? = some (.inp, t)) :
    (callMem m m1 fn x).st (m.nv + 0 + k) = some ⟨false, (m.st (args.getD k 0)).bind lendSlot⟩ := by
  have hkl := lt_of_get hk
  rw [h.st_bind (h.slot_ne hkl).1 (h.slot_ne hkl).2 hb]
  exact (bindSt_slot fn.params args m.nv 0 m.st h.args_lt k _ .inp t hk (getD_of (h.len ▸ hkl))).1 rfl

theorem st_sink (h : CallH P Γ F x fn args m.nv) {m1 : Mem} (hb : BindParams m fn.params args m.nv 0 m1)
    {k : Nat} {t : Ty} (hk : fn.params[k]? = some (.sink, t)) :
    (callMem m m1 fn x).st (m.nv + 0 + k) = some ⟨true, (m.st (args.getD k 0)).bind Slot.val⟩ := by
  have hkl := lt_of_get hk
  rw [h.st_bind (h.slot_ne hkl).1 (h.slot_ne hkl).2 hb]
  exact (bindSt_slot fn.params args m.nv 0 m.st h.args_lt k _ .sink t hk (getD_of (h.len ▸ hkl))).2 rfl

theorem st_sinkArg (h : CallH P Γ F x fn args m.nv) {m1 : Mem} (hb : BindParams m fn.params args m.nv 0 m1)
    {k : Nat} {t : Ty} (hk : fn.params[k]? = some (.sink, t)) :
    (callMem m m1 fn x).st (args.getD k 0) = some ⟨true, none⟩ := by
  have hkl := lt_of_get hk
  rw [h.st_bind (h.arg_ne hkl).1 (h.arg_ne hkl).2 hb]
  refine bindSt_arg fn.params args m.nv 0 m.st h.args_lt k _ t hk (getD_of (h.len ▸ hkl)) ?_
  intro k' t' hkk _ he
  exact h.sink_distinct k k' _ hkk ⟨t, hk⟩ (getD_of (h.len ▸ hkl)) he

/-- A binding the call step does not touch. -/
def Untouched (fn : Fn) (args : List Var) (base : Nat) (x y : Var) : Prop :=
  y ≠ x ∧ y ≠ base + fn.params.length ∧
  (∀ k (p : PMode × Ty), fn.params[k]? = some p → (∀ b, p.1 ≠ .inout b) → y ≠ base + 0 + k) ∧
  (∀ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) → args[k]? ≠ some y)

theorem st_other (h : CallH P Γ F x fn args m.nv) {m1 : Mem} (hb : BindParams m fn.params args m.nv 0 m1)
    {y : Var} (hu : Untouched fn args m.nv x y) : (callMem m m1 fn x).st y = m.st y := by
  obtain ⟨hyx, hyr, hs, ha⟩ := hu
  rw [h.st_bind hyx hyr hb]
  exact bindSt_other fn.params args m.nv 0 m.st y hs ha

theorem untouched_lt (h : CallH P Γ F x fn args m.nv) {y : Var} (hy : y < m.nv) (hyx : y ≠ x)
    (hs : ∀ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) → args.getD k 0 ≠ y) :
    Untouched fn args m.nv x y := by
  refine ⟨hyx, fun e => ?_, fun k p _ _ e => ?_, fun k t hk he => ?_⟩
  · have := vlt hy; have := veq e; omega
  · have := vlt hy; have := veq e; omega
  · have hkl := lt_of_get hk
    rw [getD_of (h.len ▸ hkl)] at he
    exact hs k t hk (Option.some.inj he)

theorem dom_lt (hi : MInv m Γ) {y : Var} {sl : Slot} (hy : m.st y = some sl) : y < m.nv :=
  hi.nvSt y (by rw [hy]; rfl)

theorem x_none (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) : m.st x = none := by
  have := hi.dom x; rw [h.fresh] at this; cases h' : m.st x <;> simp_all

/-- Every tree owned before the call is owned after it. -/
theorem own_dst (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) {o : Var} {T : Val} (hT : OwnedAt m o T) :
    ∃ o', OwnedAt (callMem m m1 fn x) o' T := by
  by_cases hs : ∃ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) ∧ args.getD k 0 = o
  · obtain ⟨k, t, hk, rfl⟩ := hs
    refine ⟨m.nv + 0 + k, ?_⟩
    unfold OwnedAt at hT ⊢
    rw [h.st_sink hb hk, hT]; rfl
  · have hox : o ≠ x := fun e => by unfold OwnedAt at hT; rw [e, h.x_none hi] at hT; cases hT
    refine ⟨o, ?_⟩
    unfold OwnedAt at hT ⊢
    rw [h.st_other hb (h.untouched_lt (dom_lt hi hT) hox (fun k t hk he => hs ⟨k, t, hk, he⟩)), hT]

/-- ... and every tree owned after it was owned before, by the argument a
    `sink` parameter took it from or by the same binding. -/
theorem own_src (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) {o : Var} {T : Val} (hT : OwnedAt (callMem m m1 fn x) o T) :
    (∃ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) ∧ o = m.nv + 0 + k ∧
      OwnedAt m (args.getD k 0) T) ∨
    (OwnedAt m o T ∧ ∀ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) → args.getD k 0 ≠ o) := by
  unfold OwnedAt at hT
  by_cases hox : o = x
  · subst hox; rw [h.st_x] at hT; simp at hT
  by_cases hor : o = m.nv + fn.params.length
  · subst hor; rw [st_r] at hT; simp at hT
  by_cases hsl : ∃ (k : Nat) (p : PMode × Ty), fn.params[k]? = some p ∧ (∀ b, p.1 ≠ .inout b) ∧ o = m.nv + 0 + k
  · obtain ⟨k, ⟨pm, t⟩, hk, hp, rfl⟩ := hsl
    cases pm with
    | inp => rw [h.st_inp hb hk] at hT; cases hT
    | sink =>
      rw [h.st_sink hb hk] at hT
      refine Or.inl ⟨k, t, hk, rfl, ?_⟩
      unfold OwnedAt
      cases hs : m.st (args.getD k 0) with
      | none => rw [hs] at hT; cases hT
      | some sl =>
        rw [hs] at hT
        obtain ⟨Ea, hEa, _, hok, _⟩ := h.arg k (lt_of_get hk)
        obtain ⟨sl', hsl', _, hso, _⟩ := hi.slot _ Ea hEa
        rw [hs] at hsl'; cases hsl'
        rw [get_of hk] at hok
        obtain ⟨own, val⟩ := sl
        simp only [Option.bind_some, Option.some.injEq, Slot.mk.injEq, true_and] at hT
        have hown : own = true := by
          simp only at hso; rw [hso, hok.2.1]; rfl
        subst hT hown; rfl
    | inout b => exact absurd rfl (hp b)
  by_cases hsa : ∃ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) ∧ args.getD k 0 = o
  · obtain ⟨k, t, hk, rfl⟩ := hsa
    rw [h.st_sinkArg hb hk] at hT; cases hT
  have hu : Untouched fn args m.nv x o := by
    refine ⟨hox, hor, fun k p hk hp he => hsl ⟨k, p, hk, hp, he⟩, fun k t hk he => ?_⟩
    have hkl := lt_of_get hk
    rw [getD_of (h.len ▸ hkl)] at he
    exact hsa ⟨k, t, hk, Option.some.inj he⟩
  rw [h.st_other hb hu] at hT
  exact Or.inr ⟨hT, fun k t hk he => hsa ⟨k, t, hk, he⟩⟩

theorem heap (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) : HeapOK (callMem m m1 fn x) := by
  obtain ⟨ha, hn, _, _⟩ := h.bind hb
  refine hi.heap.relabel (by simp [callMem, ha]) (by simp [callMem, hn]) (fun o T hT => ?_)
    (fun o1 o2 T1 T2 hne h1 h2 => ?_)
  · rcases h.own_src hi hb hT with ⟨k, t, _, _, hT'⟩ | ⟨hT', _⟩
    · exact ⟨_, hT'⟩
    · exact ⟨_, hT'⟩
  · rcases h.own_src hi hb h1 with ⟨k1, t1, hk1, rfl, hT1⟩ | ⟨hT1, hn1⟩ <;>
    rcases h.own_src hi hb h2 with ⟨k2, t2, hk2, rfl, hT2⟩ | ⟨hT2, hn2⟩
    · refine ⟨_, _, fun e => hne ?_, hT1, hT2⟩
      have := h.moving (lt_of_get hk2) (lt_of_get hk1) (by rw [get_of hk2]; rfl) e
      rw [this]
    · exact ⟨_, _, hn2 k1 t1 hk1, hT1, hT2⟩
    · exact ⟨_, _, fun e => hn1 k2 t2 hk2 e.symm, hT1, hT2⟩
    · exact ⟨_, _, hne, hT1, hT2⟩

theorem rootKeep (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) {r : Var} (hu : Untouched fn args m.nv x r) :
    RootKeep m (callMem m m1 fn x) r :=
  rootKeep_move (fun o T hT => h.own_dst hi hb hT) (h.st_other hb hu)

theorem callPe_live (Γ : Ctx) (ps : List (PMode × Ty)) (args : List Var) (v : Var) :
    (callPe Γ ps args v).live = true := by
  unfold callPe; split
  · split <;> rfl
  · rfl

theorem with_live_true (E : Entry) (h : E.live = true) : { E with live := true } = E := by
  cases E; simp_all

@[simp] theorem callS_R : (callS Γ F fn args base x).R = callR Γ args := rfl
@[simp] theorem callS_pe : (callS Γ F fn args base x).pe = callPe Γ fn.params args := rfl

/-- The bindings of the context the call sets up. -/
theorem ctx_cases (h : CallH P Γ F x fn args m.nv) (y : Var) :
    (y = x ∧ (callS Γ F fn args m.nv x).canon (sigCtx fn) y = some (callX fn)) ∨
    (y = m.nv + fn.params.length ∧ (callS Γ F fn args m.nv x).canon (sigCtx fn) y =
      some ⟨fn.resTy, resMode fn, false, if (resMode fn).ownSlot then [] else allKinds (callR Γ args),
        allKinds (callR Γ args)⟩) ∨
    (∃ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.inp, t) ∧ y = m.nv + 0 + k ∧
      (callS Γ F fn args m.nv x).canon (sigCtx fn) y = some (callPe Γ fn.params args k)) ∨
    (∃ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) ∧ y = m.nv + 0 + k ∧
      (callS Γ F fn args m.nv x).canon (sigCtx fn) y = some ⟨t, .own, true, [], allKinds (callR Γ args)⟩) ∨
    (∃ (k : Nat) (b : Eff) (t : Ty), fn.params[k]? = some (PMode.inout b, t) ∧ y = args.getD k 0 ∧
      (callS Γ F fn args m.nv x).canon (sigCtx fn) y = some ⟨t, .own, true, [], allKinds (callR Γ args)⟩) ∨
    ((∀ v, callRen fn.params args m.nv v ≠ y) ∧ y ≠ x ∧
      (callS Γ F fn args m.nv x).canon (sigCtx fn) y = (callPost Γ fn args y).map Entry.clean) ∨
    ((callS Γ F fn args m.nv x).canon (sigCtx fn) y = none ∧ ∃ v, fn.params.length < v ∧ y = m.nv + v) := by
  by_cases hyx : y = x
  · exact Or.inl ⟨hyx, by rw [hyx]; exact h.canon_x _⟩
  rcases RSetup.canon_cases h.sOK (sigCtx fn) y with ⟨v, hv, hc⟩ | ⟨hy, hc⟩
  · change callRen fn.params args m.nv v = y at hv
    rw [hc]
    rcases callRen_cases fn.params args m.nv v with ⟨b, t, hvp, hr⟩ | ⟨hnv, hr⟩
    · rw [hr] at hv; subst hv
      refine Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨v, b, t, hvp, rfl, ?_⟩))))
      rw [sigCtx_of hvp]; simp [RSetup.liftE, paramE, liftMode, rds, Mode.ownSlot]
    · rw [hr] at hv; subst hv
      rcases Nat.lt_trichotomy v fn.params.length with hlt | heq | hgt
      · have hget : fn.params[v]? = some fn.params[v] := List.getElem?_eq_getElem hlt
        rw [sigCtx_of hget]
        generalize hp : fn.params[v] = p at hget
        obtain ⟨pm, t⟩ := p
        cases pm with
        | inp =>
          refine Or.inr (Or.inr (Or.inl ⟨v, t, hget, by simp, ?_⟩))
          simp only [RSetup.liftE, paramE, ↓reduceIte, Option.map_some]
          congr 1
          show { callPe Γ fn.params args v with live := true } = _
          rw [with_live_true _ (callPe_live _ _ _ _)]
        | sink =>
          refine Or.inr (Or.inr (Or.inr (Or.inl ⟨v, t, hget, by simp, ?_⟩)))
          simp [RSetup.liftE, paramE, liftMode, rds, Mode.ownSlot]
        | inout b => exact absurd hget (hnv b t)
      · subst heq
        refine Or.inr (Or.inl ⟨rfl, ?_⟩)
        rw [sigCtx_res]
        simp [RSetup.liftE, resMode_ne' fn, RSetup.liftMode_resMode, rds]
      · refine Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr ⟨?_, v, hgt, rfl⟩)))))
        rw [sigCtx_none hgt]; rfl
  · exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨hy, hyx, by rw [hc, h.frame_of hy hyx]⟩)))))

theorem frame_untouched (h : CallH P Γ F x fn args m.nv) {y : Var} (hy : ∀ v, callRen fn.params args m.nv v ≠ y)
    (hyx : y ≠ x) (hs : ∀ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) → args.getD k 0 ≠ y) :
    Untouched fn args m.nv x y := by
  refine ⟨hyx, fun e => hy fn.params.length (by rw [ren_res, e]), fun k p hk hp e => ?_, fun k t hk he => ?_⟩
  · apply hy k
    unfold callRen; rw [hk]
    obtain ⟨pm, t⟩ := p
    cases pm with
    | inout b => exact absurd rfl (hp b)
    | _ => simpa using e.symm
  · have hkl := lt_of_get hk
    rw [getD_of (h.len ▸ hkl)] at he
    exact hs k t hk (Option.some.inj he)

theorem high_untouched (h : CallH P Γ F x fn args m.nv) {v : Nat} (hv : fn.params.length < v) :
    Untouched fn args m.nv x (m.nv + v) := by
  refine ⟨fun e => ?_, fun e => ?_, fun k p hk _ e => ?_, fun k t hk he => ?_⟩
  · have := vlt h.xlt; have := veq e; omega
  · have := veq e; omega
  · have := lt_of_get hk; have := veq e; omega
  · have := vlt (h.args_lt _ (List.mem_of_getElem? he)); omega

/-- A root reached from an argument, other than a moved argument, is untouched. -/
theorem argRoot_untouched (h : CallH P Γ F x fn args m.nv) {j : Nat} (hj : j < fn.params.length)
    {r : Var} {Er : Entry} (hEr : Γ r = some Er) (hr : r ∈ roots (argE Γ (args.getD j 0)).vdeps) :
    Untouched fn args m.nv x r := by
  refine h.untouched_lt (h.domlt _ _ hEr) (fun e => by rw [e, h.fresh] at hEr; cases hEr) ?_
  intro k t hk he
  exact h.moving_root (lt_of_get hk) hj (by rw [get_of hk]; rfl) (he ▸ hr)

theorem R_untouched (h : CallH P Γ F x fn args m.nv) {r : Var} (hr : r ∈ callR Γ args) :
    Untouched fn args m.nv x r := by
  obtain ⟨a, ha, _, hrh⟩ := mem_callR.mp hr
  obtain ⟨j, hj, rfl⟩ := mem_args ha
  obtain ⟨_, Er, hEr, _⟩ := h.R_facts hr
  exact h.argRoot_untouched (h.len ▸ hj) hEr (held_vdeps hrh)

theorem keep_R (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) :
    ∀ dep ∈ allKinds (callR Γ args), VKeep m (callMem m m1 fn x) dep ∧ HKeep m (callMem m m1 fn x) dep := by
  intro dep hd
  have hk := h.rootKeep hi hb (h.R_untouched (RSetup.mem_allKinds hd))
  exact ⟨hk.vkeep, hk.hkeep⟩

theorem held_R (h : CallH P Γ F x fn args m.nv) {j : Nat} (hj : j < fn.params.length) {Ea : Entry}
    (hEa : Γ (args.getD j 0) = some Ea) (hn : Ea.ty ≠ .int) : Ea.held ⊆ allKinds (callR Γ args) := by
  intro d hd
  have hae : argE Γ (args.getD j 0) = Ea := by unfold argE; rw [hEa]; rfl
  refine RSetup.mem_allKinds_iff.mpr (mem_callR.mpr ⟨_, ?_, by rw [hae]; exact hn, by
    rw [hae]; exact List.mem_map_of_mem hd⟩)
  simp [List.getD, show j < args.length from h.len ▸ hj]

/-- A moved or changed argument's tree, now holding what the call may hold. -/
theorem slot_ownArg (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) {j : Nat} (hj : j < fn.params.length)
    {Ea : Entry} (hEa : Γ (args.getD j 0) = some Ea) (hl : Ea.live = true) (hm : Ea.mode = .own) :
    ∃ T, m.st (args.getD j 0) = some ⟨true, some T⟩ ∧ WFv Ea.ty T ∧
      ViewsOK (callMem m m1 fn x) Ea.ty T (allKinds (callR Γ args)) := by
  obtain ⟨T, hT, hw, hv⟩ := hi.own_val hEa hl (by rw [hm]; rfl)
  have hn : Ea.ty ≠ .int := by
    obtain ⟨sl, hsl, _, _, hown, _⟩ := hi.slot _ Ea hEa
    obtain ⟨⟨t, ht⟩, _⟩ := hown (by rw [hm]; rfl)
    rw [ht]; simp
  refine ⟨T, hT, hw, ((hv.mono (h.held_R hj hEa hn)).keep fun dep hd => (h.keep_R hi hb dep hd).1)⟩

/-- The value an `in` parameter is bound to is valid through what its entry says. -/
theorem slot_inp (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) {k : Nat} {t : Ty} (hk : fn.params[k]? = some (.inp, t)) :
    ∃ v, (m.st (args.getD k 0)).bind lendSlot = some v ∧
      ValOK (callMem m m1 fn x) (callPe Γ fn.params args k).ty v
        (callPe Γ fn.params args k).path (callPe Γ fn.params args k).held := by
  have hkl := lt_of_get hk
  obtain ⟨Ea, hEa, hae⟩ := h.argE_eq hkl
  obtain ⟨_, h1, hl, hok, _⟩ := h.arg k hkl
  rw [hEa] at h1; cases h1
  -- the value, valid in the store before
  have hm0 : ∃ v, (m.st (args.getD k 0)).bind lendSlot = some v ∧
      ValOK m Ea.ty v (derive (args.getD k 0) Ea .self) Ea.held := by
    rcases hi.mode_cases hEa with hm | hm | hm
    · obtain ⟨T, hT, hw, _⟩ := hi.own_val hEa hl (by rw [hm]; rfl)
      obtain ⟨sl, hsl, _, _, hown, _⟩ := hi.slot _ Ea hEa
      obtain ⟨⟨t', ht'⟩, _⟩ := hown (by rw [hm]; rfl)
      rw [ht'] at hw
      cases hw with
      | @node _ c d es _ =>
        have hr := RhsT.borrow (F := F) hEa hl ht'
        have he := EvalR.borrowOwn hT
        obtain ⟨_, hout⟩ := rhs_pres hi h.anch hr he
        exact ⟨_, by rw [hT]; rfl, hout.valBor rfl⟩
    · obtain ⟨v, hv, _⟩ := hi.bor_val hEa hl (by rw [hm]; rfl)
      have hr := RhsT.copyRoot (F := F) hEa hl hm
      obtain ⟨_, hout⟩ := rhs_pres hi h.anch hr (EvalR.copy hv)
      exact ⟨v, by rw [hv]; rfl, hout.valBor rfl⟩
    · obtain ⟨v, hv, _⟩ := hi.bor_val hEa hl (by rw [hm]; rfl)
      have hr := RhsT.copyBor (F := F) hEa hl hm
      obtain ⟨_, hout⟩ := rhs_pres hi h.anch hr (EvalR.copy hv)
      have hd : derive (args.getD k 0) Ea .self = Ea.path := by
        simp [derive, hm, Mode.isRoot, comp_self_r]
      exact ⟨v, by rw [hv]; rfl, by rw [hd]; exact hout.valBor hm⟩
  obtain ⟨v, hv, hok0⟩ := hm0
  refine ⟨v, hv, ?_⟩
  unfold callPe; rw [hk]; simp only
  rw [hae]
  split
  · rename_i hn
    rw [hn] at hok0
    exact hok0
  · rename_i hn
    -- every root it is valid through is untouched by the call
    have hu : ∀ r, (r = args.getD k 0 ∧ Ea.mode.isRoot = true) ∨ r ∈ roots Ea.vdeps →
        Untouched fn args m.nv x r := by
      intro r hr
      rcases hr with ⟨rfl, _⟩ | hr
      · refine h.untouched_lt (h.argLt hkl) (h.arg_ne hkl).1 fun k' t' hk' he => ?_
        have := h.moving (lt_of_get hk') hkl (by rw [get_of hk']; rfl) he.symm
        subst this; rw [hk] at hk'; cases hk'
      · obtain ⟨Er, hEr, _⟩ := hi.wf _ Ea hEa hl (Or.inl hn) r hr
        exact h.argRoot_untouched hkl hEr (by rw [hae]; exact hr)
    refine hok0.keep (fun dep hd => ?_) (fun dep hd => ?_)
    · have hk' := h.rootKeep hi hb (hu _ (derive_roots_cases (List.mem_map_of_mem (f := Dep.root) hd)
        |>.imp id (fun h' => h'.2)))
      exact ⟨hk'.vkeep, hk'.hkeep⟩
    · exact (h.rootKeep hi hb (hu _ (Or.inr (held_vdeps (List.mem_map_of_mem hd))))).vkeep

end CallH

end A1
