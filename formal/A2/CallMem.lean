import A2.Bind

/-! A2 — the memory side of the call step: the store after binding the
parameters satisfies the invariant in the context the call sets up. -/

namespace A2

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
  self o T hT := by obtain ⟨p, hp⟩ := hsrc o T hT; exact hh.self p T hp

/-- A root whose slot is unchanged reaches the same memory, as long as every
    owned tree is still owned by someone. -/
theorem rootKeep_move {m m' : Mem} (hown : ∀ o T, OwnedAt m o T → ∃ o', OwnedAt m' o' T) {r : Var}
    (hr : m'.st r = m.st r) : RootKeep m m' r := by
  intro n hn
  rcases hn with ⟨T0, hn, ht⟩ | ⟨v, c, hc, ht, o, T, hT, hs, hnode⟩ |
      ⟨v, d, o', l, hc, ht, o, T, hT, hs, hdata⟩
  · exact Or.inl ⟨T0, by rw [hr]; exact hn, ht⟩
  · obtain ⟨o2, h2⟩ := hown o T hT
    exact Or.inr (Or.inl ⟨v, c, by rw [hr]; exact hc, ht, o2, T, h2, hs, hnode⟩)
  · obtain ⟨o2, h2⟩ := hown o T hT
    exact Or.inr (Or.inr ⟨v, d, o', l, by rw [hr]; exact hc, ht, o2, T, h2, hs, hdata⟩)

theorem SlotOK.clean {m : Mem} {E : Entry} {sl : Slot} (h : SlotOK m E sl) : SlotOK m E.clean sl := by
  unfold Entry.clean
  split
  · rename_i hc
    obtain ⟨ho, hown, hbor⟩ := h
    refine ⟨ho, fun hos => ?_, fun hos hl => ?_⟩
    · obtain ⟨ht, hw, hv⟩ := hown hos
      refine ⟨ht, hw, fun hl => ?_⟩
      rcases hc.2 with hi | hd
      · rw [hi] at ht; cases ht
      · simp only at hl; rw [hd] at hl; cases hl
    · simp only at hl
      rcases hc.2 with hi | hd
      · obtain ⟨v, hv, hok⟩ := hbor hos hl
        refine ⟨v, hv, ?_⟩
        simp only
        rw [hi] at hok ⊢
        exact hok.int_any
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
  rootKeep_move (fun _ _ hT => h.own_dst hi hb hT) (h.st_other hb hu)

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
      some ⟨fn.resTy, resMode fn, false, if (resMode fn).ownSlot then [] else (callS Γ F fn args m.nv x).A,
        ownHeld (resMode fn).ownSlot fn.resTy (callS Γ F fn args m.nv x).A, false, false⟩) ∨
    (∃ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.inp, t) ∧ y = m.nv + 0 + k ∧
      (callS Γ F fn args m.nv x).canon (sigCtx fn) y = some (callPe Γ fn.params args k)) ∨
    (∃ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) ∧ y = m.nv + 0 + k ∧
      (callS Γ F fn args m.nv x).canon (sigCtx fn) y =
        some ⟨t, .own, true, [], rds (callRen fn.params args m.nv) (if t.hasFn then symNames fn.params else []) ++
          ownHeld true t (callS Γ F fn args m.nv x).A, false, false⟩) ∨
    (∃ (k : Nat) (b : Eff) (t : Ty), fn.params[k]? = some (PMode.inout b, t) ∧ y = args.getD k 0 ∧
      (callS Γ F fn args m.nv x).canon (sigCtx fn) y =
        some ⟨t, .own, true, [], rds (callRen fn.params args m.nv) (if t.hasFn then symNames fn.params else []) ++
          ownHeld true t (callS Γ F fn args m.nv x).A, false, false⟩) ∨
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
      rw [sigCtx_of hvp]; simp [RSetup.liftE, paramE, liftMode, Mode.ownSlot, callS, rds]
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
          simp [RSetup.liftE, paramE, liftMode, Mode.ownSlot, callS, rds]
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

/-- A root reached from an argument in memory, other than a moved argument,
    is untouched. -/
theorem argRoot_untouched (h : CallH P Γ F x fn args m.nv) {j : Nat} (hj : j < fn.params.length)
    {r : Var} {Er : Entry} (hEr : Γ r = some Er) (hr : r ∈ roots (memDeps (argE Γ (args.getD j 0)).vdeps)) :
    Untouched fn args m.nv x r := by
  refine h.untouched_lt (h.domlt _ _ hEr) (fun e => by rw [e, h.fresh] at hEr; cases hEr) ?_
  intro k t hk he
  exact h.moving_root (lt_of_get hk) hj (by rw [get_of hk]; rfl) (he ▸ hr)

theorem R_untouched (h : CallH P Γ F x fn args m.nv) {r : Var} (hr : r ∈ callR Γ args) :
    Untouched fn args m.nv x r := by
  obtain ⟨a, ha, _, hrh⟩ := mem_callR.mp hr
  obtain ⟨j, hj, rfl⟩ := mem_args ha
  obtain ⟨_, Er, hEr, _⟩ := h.R_facts hr
  exact h.argRoot_untouched (h.len ▸ hj) hEr (held_memDeps_vdeps hrh)

theorem keep_R (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) :
    ∀ dep ∈ allKinds (callR Γ args), VKeep m (callMem m m1 fn x) dep ∧ HKeep m (callMem m m1 fn x) dep := by
  intro dep hd
  have hk := h.rootKeep hi hb (h.R_untouched (RSetup.mem_allKinds hd))
  exact ⟨hk.vkeep, hk.hkeep⟩

/-- What the arguments hold is lent out for the call (views), or held by name. -/
theorem keep_A (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) :
    ∀ dep ∈ (callS Γ F fn args m.nv x).A, VKeep m (callMem m m1 fn x) dep ∧ HKeep m (callMem m m1 fn x) dep := by
  intro dep hd
  rcases RSetup.mem_A.mp hd with hd | hd
  · exact h.keep_R hi hb dep hd
  · have hn := h.sOK.N_name dep hd
    obtain ⟨r, k⟩ := dep
    cases k with
    | name b t => exact ⟨vkeep_name _ _ r b t, hkeep_name _ _ r b t⟩
    | _ => simp [Kind.isName] at hn

/-- What an argument holds: views the call holds still, or names — of the
    frame, or of `inout` arguments by the callee's symbolic names. -/
theorem held_cases (h : CallH P Γ F x fn args m.nv) {j : Nat} (hj : j < fn.params.length) {Ea : Entry}
    (hEa : Γ (args.getD j 0) = some Ea) (hn : Ea.ty ≠ .int) :
    ∀ d ∈ Ea.held, d ∈ (callS Γ F fn args m.nv x).A ∨
      d ∈ rds (callRen fn.params args m.nv) (symNames fn.params) := by
  intro d hd
  have hae : argE Γ (args.getD j 0) = Ea := by unfold argE; rw [hEa]; rfl
  have hmem : args.getD j 0 ∈ args := by simp [List.getD, show j < args.length from h.len ▸ hj]
  cases hk : d.kind.isName with
  | false =>
    exact Or.inl (List.mem_append_left _ (RSetup.mem_allKinds_iff.mpr ⟨mem_callR.mpr ⟨_, hmem,
      by rw [hae]; exact hn, by rw [hae]; exact List.mem_map_of_mem (List.mem_filter.mpr ⟨hd, by simp [hk]⟩)⟩,
      hk⟩))
  | true =>
    rcases h.argName_cases hj hEa hn (by unfold Entry.vdeps; exact List.mem_append_right _ hd) hk with hN | hs
    · exact Or.inl (List.mem_append_right _ hN)
    · exact Or.inr hs

/-- A moved or changed argument's tree, now holding what the call may hold. -/
theorem slot_ownArg (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) {j : Nat} (hj : j < fn.params.length)
    {Ea : Entry} (hEa : Γ (args.getD j 0) = some Ea) (hl : Ea.live = true) (hm : Ea.mode = .own) :
    ∃ T, m.st (args.getD j 0) = some ⟨true, some T⟩ ∧ WFv Ea.ty T ∧
      ViewsOK (callMem m m1 fn x) Ea.ty T (ownHeld true Ea.ty (callS Γ F fn args m.nv x).A) ∧
      NamesIn T (rds (callRen fn.params args m.nv) (if Ea.ty.hasFn then symNames fn.params else []) ++
        ownHeld true Ea.ty (callS Γ F fn args m.nv x).A) := by
  obtain ⟨T, hT, hw, hv⟩ := hi.own_val hEa hl (by rw [hm]; rfl)
  have hn : Ea.ty ≠ .int := by
    obtain ⟨sl, hsl, _, _, hown, _⟩ := hi.slot _ Ea hEa
    obtain ⟨ht, _⟩ := hown (by rw [hm]; rfl)
    intro h0; rw [h0] at ht; cases ht
  have hA : ∀ d ∈ Ea.held, (!d.kind.isName) = true → d ∈ (callS Γ F fn args m.nv x).A := by
    intro d hd hk
    rcases h.held_cases hj hEa hn d hd with hA | hs
    · exact hA
    · obtain ⟨_, b, t, rfl, _⟩ := RSetup.sym_ren h.sOK hs
      simp [Kind.isName] at hk
  refine ⟨T, hT, hw, ViewsOK.ownHeld true (((hv.memDeps).mono (fun d hd => hA d (List.mem_filter.mp hd).1
    (List.mem_filter.mp hd).2)).keep fun dep hd => (h.keep_A hi hb dep hd).1), ?_⟩
  cases hhv : Ea.ty.holdsView
  · exact NamesIn.nil _ (hw.names_nil hhv)
  · intro c hc
    have hd := hi.held _ Ea _ T hEa hl hT rfl c hc
    -- it holds a closure, so its type may: it carries the symbolic names
    have hf : Ea.ty.hasFn = true := by
      cases hf : Ea.ty.hasFn
      · rw [hw.names_nil_fn hf] at hc; cases hc
      · rfl
    have hoh : ownHeld true Ea.ty (callS Γ F fn args m.nv x).A = (callS Γ F fn args m.nv x).A := by
      simp [ownHeld, hhv]
    rw [hf, hoh]; simp only [↓reduceIte]
    rcases h.held_cases hj hEa hn _ hd with hA | hs
    · exact List.mem_append_right _ hA
    · exact List.mem_append_left _ hs

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
  rw [get_of hk] at hok
  -- the value, valid in the store before
  have hm0 : ∃ v, (m.st (args.getD k 0)).bind lendSlot = some v ∧
      ValOK m Ea.ty v (derive (args.getD k 0) Ea .self) Ea.held := by
    rcases hi.mode_cases hEa with hm | hm | hm
    · obtain ⟨T, hT, hw, hvs⟩ := hi.own_val hEa hl (by rw [hm]; rfl)
      obtain ⟨sl, hsl, _, _, hown, _⟩ := hi.slot _ Ea hEa
      obtain ⟨hown', _⟩ := hown (by rw [hm]; rfl)
      refine ⟨lendOf T, by rw [hT]; rfl, ?_⟩
      have hd : derive (args.getD k 0) Ea .self = [⟨args.getD k 0, rootKind Ea.ty .self⟩] := by
        simp [derive, hm, Mode.isRoot]
      rw [hd]
      refine lend_valOK' hw (hi.pkgs _ _ T hT rfl) (fun t c d es ht => ⟨_, List.mem_singleton_self _, _,
        Or.inl ⟨T, hT, ht⟩, lands_rootKind_self _ _⟩) hvs (hi.held _ Ea _ T hEa hl hT rfl) (fun s hs => ?_)
      rw [hs] at hown'; cases hown'
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
    exact hok0.int_any
  · rename_i hn
    -- every root it is valid through in memory is untouched by the call;
    -- what it holds by name needs nothing kept
    have hu : ∀ r, (r = args.getD k 0 ∧ Ea.mode.isRoot = true) ∨ r ∈ roots (memDeps Ea.vdeps) →
        Untouched fn args m.nv x r := by
      intro r hr
      rcases hr with ⟨rfl, _⟩ | hr
      · refine h.untouched_lt (h.argLt hkl) (h.arg_ne hkl).1 fun k' t' hk' he => ?_
        have := h.moving (lt_of_get hk') hkl (by rw [get_of hk']; rfl) he.symm
        subst this; rw [hk] at hk'; cases hk'
      · obtain ⟨Er, hEr, _⟩ := hi.wf _ Ea hEa hl (Or.inl hn) r (roots_memDeps hr)
        exact h.argRoot_untouched hkl hEr (by rw [hae]; exact hr)
    have hkeep : ∀ dep, (dep.kind.isName = false → (dep.root = args.getD k 0 ∧ Ea.mode.isRoot = true) ∨
        dep.root ∈ roots (memDeps Ea.vdeps)) →
        VKeep m (callMem m m1 fn x) dep ∧ HKeep m (callMem m m1 fn x) dep := by
      intro dep hdep
      obtain ⟨r, kd⟩ := dep
      cases kd with
      | name b t => exact ⟨vkeep_name _ _ r b t, hkeep_name _ _ r b t⟩
      | _ =>
        have hk' := h.rootKeep hi hb (hu _ (hdep rfl))
        exact ⟨hk'.vkeep, hk'.hkeep⟩
    have hok1 := hok0.keep (fun dep hd => hkeep dep fun hdn => ?_) (fun dep hd => hkeep dep fun hdn => ?_)
    · cases hf : Ea.ty.hasFn
      · rw [typedDeps_noFn hf, typedDeps_noFn hf]; exact hok1.memDeps hf
      · rw [typedDeps_hasFn hf, typedDeps_hasFn hf]; exact hok1
    · rcases derive_roots_cases (List.mem_map_of_mem (f := Dep.root) hd) with h' | ⟨hnr, _⟩
      · exact Or.inl h'
      · -- a borrow: the handle passes on what it borrows from, kind for kind
        right
        unfold derive at hd
        rw [hnr] at hd; simp only [Bool.false_eq_true, ↓reduceIte, List.mem_map] at hd
        obtain ⟨d0, hd0, rfl⟩ := hd
        have hos : Ea.mode.ownSlot = false := by cases hm : Ea.mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
        have hc : (⟨d0.root, comp d0.kind .self⟩ : Dep) = d0 := by obtain ⟨r0, k0⟩ := d0; cases k0 <;> rfl
        rw [hc] at hdn ⊢
        have hd0' : d0 ∈ Ea.vdeps := by
          simp only [Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte]
          exact List.mem_append_left _ hd0
        exact List.mem_map_of_mem (List.mem_filter.mpr ⟨hd0', by simp [hdn]⟩)
    · have hd' : dep ∈ Ea.vdeps := by unfold Entry.vdeps; exact List.mem_append_right _ hd
      exact Or.inr (List.mem_map_of_mem (List.mem_filter.mpr ⟨hd', by simp [hdn]⟩))

end CallH

theorem slot_empty {m : Mem} {E : Entry} {o : Bool} (ho : o = E.mode.ownSlot) (hl : E.live = false)
    (hv : E.mode.ownSlot = true → E.ty.owning = true) : SlotOK m E ⟨o, none⟩ := by
  refine ⟨ho, fun hos => ⟨hv hos, fun T hT => ?_, fun hl' => ?_⟩, fun _ hl' => ?_⟩
  · cases hT
  · rw [hl] at hl'; cases hl'
  · rw [hl] at hl'; cases hl'

theorem resMode_ownSlot (fn : Fn) : (resMode fn).ownSlot = fn.resOwn := by
  unfold resMode; cases fn.resOwn <;> rfl

namespace CallH
variable {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {fn : Fn} {args : List Var} {m : Mem}

/-- A frame binding's slot agrees with its entry after the call step. -/
theorem slot_frame (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) {y : Var} (hy : ∀ v, callRen fn.params args m.nv v ≠ y)
    (hyx : y ≠ x) {E1 : Entry} (h1 : callPost Γ fn args y = some E1) :
    ∃ sl, (callMem m m1 fn x).st y = some sl ∧ E1.clean.ty.ok = true ∧ SlotOK (callMem m m1 fn x) E1.clean sl := by
  by_cases hs : ∃ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) ∧ args.getD k 0 = y
  · obtain ⟨k, t, hk, rfl⟩ := hs
    have hkl := lt_of_get hk
    obtain ⟨Ea, hEa, hae⟩ := h.argE_eq hkl
    obtain ⟨_, h1', _, hok, _⟩ := h.arg k hkl
    rw [hEa] at h1'; cases h1'
    rw [get_of hk] at hok
    obtain ⟨hty, hm, hs⟩ := hok
    obtain ⟨E2, h2, ht2, hm2, _, _, hl2⟩ := killNames_get _ h1
    have hpost := callPostAux_at fn.params args 0 k Γ (getD_of (h.len ▸ hkl)) (fun k' hk' he => by
      have hk'l : k' < args.length := (List.getElem?_eq_some_iff.mp he).1
      have hge : args.getD k' 0 = args.getD k 0 := by simp [List.getD, he]
      exact hk' (h.moving hkl (h.len ▸ hk'l) (by rw [get_of hk]; rfl) hge)) hk rfl E2 h2
    simp only [postEnt, hae] at hpost
    obtain ⟨ht1, hm1, _, _, hl1⟩ := hpost
    rw [← ht2] at ht1; rw [← hm2] at hm1
    have hl : E1.live = false := by cases h' : E1.live; rfl; exact absurd (hl1 (hl2 h').1) (by simp)
    refine ⟨_, h.st_sinkArg hb hk, by rw [clean_ty, ht1]; exact hi.tyok hEa, slot_empty ?_ ?_ ?_⟩
    · rw [clean_mode, hm1, hm]; rfl
    · rw [clean_live]; exact hl
    · intro _; rw [clean_ty, ht1, hty]; exact hs
  · have hu := h.frame_untouched hy hyx (fun k t hk he => hs ⟨k, t, hk, he⟩)
    have hmv : ∀ pa ∈ fn.params.zip args, pa.1.1.moves = true → pa.2 ≠ y := by
      intro pa hpa hm he
      obtain ⟨k, hk, hka, rfl⟩ := RSetup.mem_zip_getD hpa
      simp only at hm he
      have hget : fn.params[k]? = some fn.params[k] := List.getElem?_eq_getElem hk
      generalize hp : fn.params[k] = p at hm hget
      obtain ⟨pm, t⟩ := p
      cases pm with
      | inp => cases hm
      | sink => exact hs ⟨k, t, hget, he⟩
      | inout b => exact hy k (by unfold callRen; rw [hget]; exact he)
    obtain ⟨E2, h2, ht2, hm2, hp2, hh2, hl2⟩ := killNames_get _ h1
    obtain ⟨E0, h0, ht0, hm0, hp0, hh0, hsv⟩ := callPostAux_frame fn.params args 0 Γ hmv E2 h2
    rw [← ht2] at ht0; rw [← hm2] at hm0; rw [← hp2] at hp0; rw [← hh2] at hh0
    obtain ⟨sl, hsl, hok, hslot⟩ := hi.slot y E0 h0
    refine ⟨sl, by rw [h.st_other hb hu, hsl], by rw [clean_ty, ht0]; exact hok, ?_⟩
    have hs1 := (hslot.weakLive ht0 hm0 hp0 hh0 (fun hl => (hsv (hl2 hl).1).1)).clean
    refine hs1.keepLive fun hlv dep hd => ?_
    -- what it depends on is untouched: a dependency on a moved argument ended it
    -- (a dead binding `letd` made keeps its views, but reads no memory)
    unfold Entry.clean at hd hlv
    split at hd
    · simp [Entry.vdeps] at hd
      rename_i hcl
      rw [ite_eq_left hcl] at hlv
      rcases hcl.2 with ht | hl0
      · exact absurd ht hd.1.2.2
      · simp [hl0] at hlv
    · rename_i hcl
      have hrootb : E1.fixed → E1.mode = .rootb := by
        rintro hf
        rcases hf with hf | ⟨b, hb, _⟩
        · exact hf
        · obtain ⟨E0', h0', hm0', _⟩ := h.postdt.2 y E1 h1
          exact absurd (hm0' ▸ hb : E0'.mode = .inout b) (h.noio y E0' b h0')
      have hl : E1.live = true := by
        by_cases hrb : E1.fixed
        · exact h.post_live_rootb h1 (hrootb hrb)
        · cases hlv : E1.live
          · exact absurd ⟨hrb, Or.inr hlv⟩ hcl
          · rfl
      have hn : E0.ty ≠ .int ∨ E0.mode = .rootb := by
        by_cases hrb : E1.mode = .rootb
        · exact Or.inr (by rw [← hm0]; exact hrb)
        · exact Or.inl fun ht => hcl ⟨fun hf => hrb (hrootb hf), Or.inl (by rw [ht0]; exact ht)⟩
      have hd0 : dep ∈ E0.vdeps := by unfold Entry.vdeps at hd ⊢; rwa [← hm0, ← hp0, ← hh0]
      obtain ⟨Er, hEr, _⟩ := hi.wf y E0 h0 (hsv (hl2 hl).1).1 hn dep.root (List.mem_map_of_mem hd0)
      refine (fun hk => ⟨hk.vkeep, hk.hkeep⟩) (h.rootKeep hi hb ?_)
      refine h.untouched_lt (h.domlt _ _ hEr) (fun e => by rw [e, h.fresh] at hEr; cases hEr) ?_
      intro k t hk he
      have hsk := ((hsv (hl2 hl).1).2 ((.sink, t), args.getD k 0)
        (mem_zip_of hk (h.len ▸ lt_of_get hk))).1 rfl
      have := hits_false_dep hsk hn dep hd0 he.symm
      cases dep.kind <;> simp [Eff.kills] at this

/-- A live integer binding's value captures nothing. -/
theorem int_names (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E) (hl : E.live = true)
    (ht : E.ty = .int) {sl : Slot} (hst : m.st y = some sl) {T : Val} (hT : sl.val = some T) : T.names = [] := by
  rcases hi.mode_cases hy with hm | hm | hm
  · obtain ⟨_, _, _, _, hown, _⟩ := hi.slot y E hy
    obtain ⟨ho, _⟩ := hown (by rw [hm]; rfl)
    rw [ht] at ho; cases ho
  all_goals
    obtain ⟨v, hv, hok⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
    rw [hst] at hv; cases hv
    simp only [Option.some.injEq] at hT; subst hT
    rw [ht] at hok
    cases hok; rfl

theorem resTy_vec (h : CallH P Γ F x fn args m.nv) (ho : (resMode fn).ownSlot = true) : fn.resTy.owning = true := by
  obtain ⟨_, _, _, _, hv, _⟩ := h.fnok
  exact hv (by rw [← resMode_ownSlot]; exact ho)

theorem param_ok (h : CallH P Γ F x fn args m.nv) {k : Nat} {p : PMode × Ty} (hk : fn.params[k]? = some p) :
    p.2.ok = true ∧ (p.1 ≠ .inp → p.2.owning = true) := by
  obtain ⟨_, _, _, _, _, hpar, _⟩ := h.fnok
  obtain ⟨hok, hsink, hio⟩ := hpar p (List.mem_of_getElem? hk)
  refine ⟨hok, fun hne => ?_⟩
  obtain ⟨pm, t⟩ := p
  cases pm with
  | inp => exact absurd rfl hne
  | sink => exact hsink rfl
  | inout b => exact hio b rfl

theorem callPe_dbind (Γ : Ctx) (ps : List (PMode × Ty)) (args : List Var) (v : Var) :
    (callPe Γ ps args v).dbind = false := by
  unfold callPe; split
  · split <;> rfl
  · rfl

/-- A2-drop.2: the call's own bindings are none `letd` made: only a caller
    binding the call does not rename may be one. -/
theorem dbind_frame (h : CallH P Γ F x fn args m.nv) {y : Var} {E : Entry}
    (hy : (callS Γ F fn args m.nv x).canon (sigCtx fn) y = some E) (hd : E.dbind = true) :
    (∀ v, callRen fn.params args m.nv v ≠ y) ∧ y ≠ x ∧
      ∃ E1, callPost Γ fn args y = some E1 ∧ E = E1.clean := by
  rcases h.ctx_cases y with ⟨rfl, hc⟩ | ⟨rfl, hc⟩ | ⟨k', t, hk', rfl, hc⟩ | ⟨k', t, hk', rfl, hc⟩ |
      ⟨k', b', t, hk', rfl, hc⟩ | ⟨hy', hyx, hc⟩ | ⟨hc, v, hv, rfl⟩ <;> rw [hc] at hy <;> (try cases hy)
  · simp [callX] at hd
  · simp at hd
  · rw [callPe_dbind] at hd; cases hd
  · simp at hd
  · simp at hd
  · obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hy
    exact ⟨hy', hyx, E1, h1, rfl⟩

/-- A2-drop.2: an armed caller binding keeps its value's views: it views no
    moved argument in memory (`CallDtorSafe`), and the call leaves the rest. -/
theorem armed_frame (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) {y : Var} (hy : ∀ v, callRen fn.params args m.nv v ≠ y)
    (hyx : y ≠ x) {E1 : Entry} (h1 : callPost Γ fn args y = some E1) {sl : Slot}
    (hsl : (callMem m m1 fn x).st y = some sl) : ArmOK (callMem m m1 fn x) E1.clean sl := by
  by_cases hs : ∃ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) ∧ args.getD k 0 = y
  · obtain ⟨k, t, hk, rfl⟩ := hs
    rw [h.st_sinkArg hb hk] at hsl; cases hsl
    exact ArmOK.of_none rfl
  have hu := h.frame_untouched hy hyx (fun k t hk he => hs ⟨k, t, hk, he⟩)
  rw [h.st_other hb hu] at hsl
  have hmv : ∀ pa ∈ fn.params.zip args, pa.1.1.moves = true → pa.2 ≠ y := by
    intro pa hpa hm he
    obtain ⟨k, hk, hka, rfl⟩ := RSetup.mem_zip_getD hpa
    simp only at hm he
    have hget : fn.params[k]? = some fn.params[k] := List.getElem?_eq_getElem hk
    generalize hp : fn.params[k] = p at hm hget
    obtain ⟨pm, t⟩ := p
    cases pm with
    | inp => cases hm
    | sink => exact hs ⟨k, t, hget, he⟩
    | inout b => exact hy k (by unfold callRen; rw [hget]; exact he)
  obtain ⟨E0, h0, hdt0, hdb0⟩ := h.post_frame_flags hmv h1
  obtain ⟨E2, h2, ht2, hm2, _, hh2, _⟩ := killNames_get _ h1
  obtain ⟨E0', h0', ht0, hm0, _, hh0, _⟩ := callPostAux_frame fn.params args 0 Γ hmv E2 h2
  rw [h0] at h0'; cases h0'
  intro hd hos T hT
  rw [Entry.clean_dbind, hdb0] at hd; rw [clean_mode, hm2, hm0] at hos
  obtain ⟨hdt, hvs⟩ := hi.armed y E0 sl h0 hsl hd hos T hT
  have hnint : E0.ty ≠ .int := fun h' => by have := hi.wf.view y E0 h0 hd; rw [h'] at this; cases this
  -- what it views in memory is untouched: no moved argument
  have hk : ∀ dep ∈ memDeps E0.held, VKeep m (callMem m m1 fn x) dep := by
    intro dep hdm
    have hdm' := List.mem_filter.mp hdm
    have hnm : dep.kind.isName = false := by simpa using hdm'.2
    have hdv : dep ∈ E0.vdeps := by unfold Entry.vdeps; exact List.mem_append_right _ hdm'.1
    obtain ⟨Er, hEr, _⟩ := hi.wf.dtor y E0 h0 hd hos (Or.inl hnint) dep hdv hnm
    refine (h.rootKeep hi hb ?_).vkeep
    refine h.untouched_lt (h.domlt _ _ hEr) (fun e => by rw [e, h.fresh] at hEr; cases hEr) ?_
    intro k t hk he
    have hds := (h.dsafe.1 k (lt_of_get hk)).1 (by rw [get_of hk])
    exact DtorSafe.root_ne hds h0 hdt hos (Or.inl hnint) hdv hnm he.symm
  refine ⟨by rw [Entry.clean_dtor, hdt0]; exact hdt, ?_⟩
  have hdb1 : E1.dbind = true := by rw [hdb0]; exact hd
  have hos1 : E1.mode.ownSlot = true := by rw [hm2, hm0]; exact hos
  have hty1 : E1.ty = E0.ty := by rw [ht2, ht0]
  have hn1 : E1.ty ≠ .int ∨ E1.mode = .rootb := Or.inl (by rw [hty1]; exact hnint)
  rw [clean_ty, hty1]
  refine (hvs.memDeps.keep hk).mono fun d hd' => ?_
  have hd'' := List.mem_filter.mp hd'
  have hnm : d.kind.isName = false := by simpa using hd''.2
  refine (Entry.clean_vdeps_mem hdb1 hos1 hn1 hnm).mpr ?_
  rw [hh2, hh0]; exact hd''.1

/-- The invariant of memory, in the context the call sets up. -/
theorem minv (h : CallH P Γ F x fn args m.nv) (hi : MInv m Γ) {m1 : Mem}
    (hb : BindParams m fn.params args m.nv 0 m1) :
    MInv (callMem m m1 fn x) ((callS Γ F fn args m.nv x).canon (sigCtx fn)) where
  dom y := by
    rcases h.ctx_cases y with ⟨rfl, hc⟩ | ⟨rfl, hc⟩ | ⟨k, t, hk, rfl, hc⟩ | ⟨k, t, hk, rfl, hc⟩ |
        ⟨k, b, t, hk, rfl, hc⟩ | ⟨hy, hyx, hc⟩ | ⟨hc, v, hv, rfl⟩ <;> rw [hc]
    · rw [h.st_x]; rfl
    · rw [st_r]; rfl
    · rw [h.st_inp hb hk]; rfl
    · rw [h.st_sink hb hk]; rfl
    · have hkl := lt_of_get hk
      obtain ⟨Ea, hEa, _⟩ := h.arg k hkl
      have hu := h.untouched_lt (h.argLt hkl) (h.arg_ne hkl).1 (fun k' t' hk' he => by
        have := h.moving (lt_of_get hk') hkl (by rw [get_of hk']; rfl) he.symm
        subst this; rw [hk] at hk'; cases hk')
      rw [h.st_other hb hu, ← hi.dom, hEa]; rfl
    · by_cases hs : ∃ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) ∧ args.getD k 0 = y
      · obtain ⟨k, t, hk, rfl⟩ := hs
        obtain ⟨Ea, hEa, _⟩ := h.arg k (lt_of_get hk)
        obtain ⟨E1, h1, _⟩ := h.postdm.get hEa
        rw [h.st_sinkArg hb hk, h1]; rfl
      · rw [h.st_other hb (h.frame_untouched hy hyx (fun k t hk he => hs ⟨k, t, hk, he⟩)), ← hi.dom,
          ← h.postdm.1]
        cases callPost Γ fn args y <;> rfl
    · rw [h.st_other hb (h.high_untouched hv)]
      cases h' : m.st (m.nv + v) with
      | none => rfl
      | some sl => exact absurd (dom_lt hi h') (Nat.not_lt.mpr (Nat.le_add_right _ _))
  slot y E hy := by
    rcases h.ctx_cases y with ⟨rfl, hc⟩ | ⟨rfl, hc⟩ | ⟨k, t, hk, rfl, hc⟩ | ⟨k, t, hk, rfl, hc⟩ |
        ⟨k, b, t, hk, rfl, hc⟩ | ⟨hy', hyx, hc⟩ | ⟨hc, v, hv, rfl⟩ <;> rw [hc] at hy <;> (try cases hy)
    · obtain ⟨_, _, _, hok, _⟩ := h.fnok
      exact ⟨_, h.st_x m1, hok, slot_empty (by simp [callX, resMode_ownSlot]) rfl
        (fun ho => h.resTy_vec ho)⟩
    · obtain ⟨_, _, _, hok, _⟩ := h.fnok
      exact ⟨_, st_r m1, hok, slot_empty (by simp [resMode_ownSlot]) rfl (fun ho => h.resTy_vec ho)⟩
    · obtain ⟨v, hv, hok⟩ := h.slot_inp hi hb hk
      have hpm : (callPe Γ fn.params args k).mode = .rootb := h.sOK.pe_rb k
      refine ⟨_, h.st_inp hb hk, ?_, ⟨by rw [hpm]; rfl, fun hos => ?_, fun _ _ => ⟨v, hv, hok⟩⟩⟩
      · have hkl := lt_of_get hk
        obtain ⟨Ea, hEa, hae⟩ := h.argE_eq hkl
        unfold callPe; rw [hk]; simp only; rw [hae]
        split
        · rfl
        · show Ea.ty.ok = true; exact hi.tyok hEa
      · rw [hpm] at hos; cases hos
    · have hkl := lt_of_get hk
      obtain ⟨Ea, hEa, hl, hok, _⟩ := h.arg k hkl
      rw [get_of hk] at hok
      obtain ⟨hty, hm, _⟩ := hok
      simp only at hty
      obtain ⟨T, hT, hw, hv, _⟩ := h.slot_ownArg hi hb hkl hEa hl hm
      refine ⟨_, h.st_sink hb hk, by show t.ok = true; rw [← hty]; exact hi.tyok hEa,
        ⟨rfl, fun _ => ⟨?_, ?_, ?_⟩, ?_⟩⟩
      · obtain ⟨_, hs⟩ := h.param_ok hk; exact hs (by simp)
      · intro T' hT'; rw [hT] at hT'; cases hT'; show WFv t _; rw [← hty]; exact hw
      · intro _; exact ⟨T, by rw [hT]; rfl, by show ViewsOK _ t T _; rw [← hty]; exact hv.mono (List.subset_append_right _ _)⟩
      · intro hos; cases hos
    · have hkl := lt_of_get hk
      obtain ⟨Ea, hEa, hl, hok, _⟩ := h.arg k hkl
      rw [get_of hk] at hok
      obtain ⟨hty, hcan, _⟩ := hok
      simp only at hty
      have hm : Ea.mode = .own := by
        rcases hcan with hm | ⟨b', hm, _⟩
        · exact hm
        · exact absurd hm (h.noInout _ Ea b' hEa)
      obtain ⟨T, hT, hw, hv, _⟩ := h.slot_ownArg hi hb hkl hEa hl hm
      have hu := h.untouched_lt (h.argLt hkl) (h.arg_ne hkl).1 (fun k' t' hk' he => by
        have := h.moving (lt_of_get hk') hkl (by rw [get_of hk']; rfl) he.symm
        subst this; rw [hk] at hk'; cases hk')
      refine ⟨_, by rw [h.st_other hb hu, hT], by show t.ok = true; rw [← hty]; exact hi.tyok hEa,
        ⟨rfl, fun _ => ⟨?_, ?_, ?_⟩, ?_⟩⟩
      · obtain ⟨_, hs⟩ := h.param_ok hk; exact hs (by simp)
      · intro T' hT'; cases hT'; show WFv t _; rw [← hty]; exact hw
      · intro _; exact ⟨T, rfl, by show ViewsOK _ t T _; rw [← hty]; exact hv.mono (List.subset_append_right _ _)⟩
      · intro hos; cases hos
    · obtain ⟨E1', h1', rfl⟩ := Option.map_eq_some_iff.mp hy
      exact h.slot_frame hi hb hy' hyx h1'
  heap := h.heap hi hb
  nvSt y hy := by
    obtain ⟨_, hnv, _⟩ := h.fnok
    show y < m.nv + fn.nvars
    by_cases hyx : y = x
    · rw [hyx]; exact Nat.lt_of_lt_of_le h.xlt (Nat.le_add_right _ _)
    by_cases hyr : y = m.nv + fn.params.length
    · rw [hyr]; exact Nat.add_lt_add_left hnv _
    by_cases hsl : ∃ (k : Nat) (p : PMode × Ty), fn.params[k]? = some p ∧ (∀ b, p.1 ≠ .inout b) ∧
        y = m.nv + 0 + k
    · obtain ⟨k, p, hk, _, rfl⟩ := hsl
      rw [Nat.add_zero]; exact Nat.add_lt_add_left (Nat.lt_trans (lt_of_get hk) hnv) _
    by_cases hsa : ∃ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) ∧ args.getD k 0 = y
    · obtain ⟨k, t, hk, rfl⟩ := hsa
      exact Nat.lt_of_lt_of_le (h.argLt (lt_of_get hk)) (Nat.le_add_right _ _)
    have hu : Untouched fn args m.nv x y := by
      refine ⟨hyx, hyr, fun k p hk hp he => hsl ⟨k, p, hk, hp, he⟩, fun k t hk he => ?_⟩
      have hkl := lt_of_get hk
      rw [getD_of (h.len ▸ hkl)] at he
      exact hsa ⟨k, t, hk, Option.some.inj he⟩
    rw [h.st_other hb hu] at hy
    exact Nat.lt_of_lt_of_le (hi.nvSt y hy) (Nat.le_add_right _ _)
  noInout y E b hy := by
    rcases h.ctx_cases y with ⟨rfl, hc⟩ | ⟨rfl, hc⟩ | ⟨k, t, hk, rfl, hc⟩ | ⟨k, t, hk, rfl, hc⟩ |
        ⟨k, b', t, hk, rfl, hc⟩ | ⟨hy', hyx, hc⟩ | ⟨hc, v, hv, rfl⟩ <;> rw [hc] at hy <;> (try cases hy)
    · exact resMode_inout fn b
    · exact resMode_inout fn b
    · have := (h.sOK.pe_rb k); simp only [callS] at this; rw [this]; simp
    · simp
    · simp
    · obtain ⟨E1', h1', rfl⟩ := Option.map_eq_some_iff.mp hy
      obtain ⟨E0, h0, hm⟩ := h.postdm.2 y E1' h1'
      rw [clean_mode, hm]; exact hi.noInout y E0 b h0
  wf := RSetup.canon_wf h.sOK h.sig_abs (sigCtx_wf fn)
  names := RSetup.canon_names h.sOK h.sig_abs (sigCtx_names fn)
  held y E sl T hy hl hst hT := by
    rcases h.ctx_cases y with ⟨rfl, hc⟩ | ⟨rfl, hc⟩ | ⟨k, t, hk, rfl, hc⟩ | ⟨k, t, hk, rfl, hc⟩ |
        ⟨k, b', t, hk, rfl, hc⟩ | ⟨hy', hyx, hc⟩ | ⟨hc, v, hv, rfl⟩ <;> rw [hc] at hy <;> (try cases hy)
    · simp [callX] at hl
    · simp at hl
    · -- an `in` parameter: the argument's value, lent
      rw [h.st_inp hb hk] at hst; cases hst
      have hkl := lt_of_get hk
      obtain ⟨Ea, hEa, hae⟩ := h.argE_eq hkl
      obtain ⟨_, h1, hla, _⟩ := h.arg k hkl
      rw [hEa] at h1; cases h1
      cases hsa : m.st (args.getD k 0) with
      | none => rw [hsa] at hT; cases hT
      | some sa =>
        rw [hsa] at hT
        obtain ⟨o, val⟩ := sa
        cases val with
        | none => cases o <;> cases hT
        | some V =>
          have hV := hi.held _ Ea _ V hEa hla hsa rfl
          have hTV : NamesIn T Ea.held := by
            cases o
            · simp only [Option.bind, lendSlot, Option.some.injEq] at hT; subst hT; exact hV
            · simp only [Option.bind, lendSlot, Option.some.injEq] at hT; subst hT; exact hV.lendOf
          have hcp : (callPe Γ fn.params args k).held =
              if Ea.ty = .int then [] else typedDeps Ea.ty Ea.held := by
            unfold callPe; rw [hk]; simp only; rw [hae]; split <;> rfl
          rw [hcp]
          split
          · rename_i hn
            have hVn := int_names hi hEa hla hn hsa rfl
            refine NamesIn.nil _ ?_
            cases o
            · simp only [Option.bind, lendSlot, Option.some.injEq] at hT; subst hT; exact hVn
            · simp only [Option.bind, lendSlot, Option.some.injEq] at hT; subst hT
              exact List.eq_nil_iff_forall_not_mem.mpr fun c hc => by
                have := names_lendOf V c hc; rw [hVn] at this; cases this
          · cases hf : Ea.ty.hasFn
            · -- its type holds no closure: nothing held by name
              rw [typedDeps_noFn hf]
              have hVn : V.names = [] := by
                obtain ⟨sl, hsl, _, hso, hown, hbor⟩ := hi.slot _ Ea hEa
                rw [hsa] at hsl; cases hsl
                cases o
                · obtain ⟨v, hv, hok⟩ := hbor (by simpa using hso.symm) hla
                  simp only [Option.some.injEq] at hv; subst hv
                  exact hok.names_nil_fn hf
                · exact ((hown (by simpa using hso.symm)).2.1 V rfl).names_nil_fn hf
              refine NamesIn.nil _ ?_
              cases o
              · simp only [Option.bind, lendSlot, Option.some.injEq] at hT; subst hT; exact hVn
              · simp only [Option.bind, lendSlot, Option.some.injEq] at hT; subst hT
                exact List.eq_nil_iff_forall_not_mem.mpr fun c hc => by
                  have := names_lendOf V c hc; rw [hVn] at this; cases this
            · rw [typedDeps_hasFn hf]; exact hTV
    · -- a `sink` parameter: the argument's value, moved
      rw [h.st_sink hb hk] at hst; cases hst
      have hkl := lt_of_get hk
      obtain ⟨Ea, hEa, hla, hok, _⟩ := h.arg k hkl
      rw [get_of hk] at hok
      obtain ⟨hty, hm, _⟩ := hok
      simp only at hty
      obtain ⟨T', hT', _, _, hn⟩ := h.slot_ownArg hi hb hkl hEa hla hm
      have hTT : T' = T := by rw [hT'] at hT; simpa using hT
      subst hTT
      show NamesIn T' (rds _ (if t.hasFn then _ else []) ++ ownHeld true t _); rw [← hty]; exact hn
    · -- an `inout` parameter: the argument itself
      have hkl := lt_of_get hk
      obtain ⟨Ea, hEa, hla, hok, _⟩ := h.arg k hkl
      rw [get_of hk] at hok
      obtain ⟨hty, hcan, _⟩ := hok
      simp only at hty
      have hm : Ea.mode = .own := by
        rcases hcan with hm | ⟨b', hm, _⟩
        · exact hm
        · exact absurd hm (h.noInout _ Ea b' hEa)
      obtain ⟨T', hT', _, _, hn⟩ := h.slot_ownArg hi hb hkl hEa hla hm
      have hu := h.untouched_lt (h.argLt hkl) (h.arg_ne hkl).1 (fun k' t' hk' he => by
        have := h.moving (lt_of_get hk') hkl (by rw [get_of hk']; rfl) he.symm
        subst this; rw [hk] at hk'; cases hk')
      rw [h.st_other hb hu, hT'] at hst; cases hst
      simp only [Option.some.injEq] at hT; subst hT
      show NamesIn T' (rds _ (if t.hasFn then _ else []) ++ ownHeld true t _); rw [← hty]; exact hn
    · -- the frame: a live binding of the caller's, as it was
      obtain ⟨E1', h1', rfl⟩ := Option.map_eq_some_iff.mp hy
      obtain ⟨E0, h0, hl0, ht0, _, hvd0⟩ :=
        h.frame_src (y := y) (E := E1'.clean) (by rw [h.frame_of hy' hyx, h1']; rfl) hl
      by_cases hs : ∃ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) ∧ args.getD k 0 = y
      · obtain ⟨k, t, hk, rfl⟩ := hs
        rw [h.st_sinkArg hb hk] at hst; cases hst; cases hT
      · rw [h.st_other hb (h.frame_untouched hy' hyx (fun k t hk he => hs ⟨k, t, hk, he⟩))] at hst
        have hN := hi.held y E0 sl T h0 hl0 hst hT
        by_cases hn : E1'.clean.ty ≠ .int ∨ E1'.clean.mode = .rootb
        · rw [(hvd0 hn).2]; exact hN
        · -- an integer: it captures nothing
          have hti : E0.ty = .int := by
            rw [← ht0]
            by_cases h' : E1'.clean.ty = .int
            · exact h'
            · exact absurd (Or.inl h') hn
          exact NamesIn.nil _ (int_names hi h0 hl0 hti hst hT)
  pkgs y sl T hst hT := by
    by_cases hyx : y = x
    · rw [hyx, h.st_x] at hst; cases hst; cases hT
    by_cases hyr : y = m.nv + fn.params.length
    · rw [hyr, st_r] at hst; cases hst; cases hT
    by_cases hsl : ∃ (k : Nat) (p : PMode × Ty), fn.params[k]? = some p ∧ (∀ b, p.1 ≠ .inout b) ∧
        y = m.nv + 0 + k
    · obtain ⟨k, ⟨pm, t⟩, hk, hp, rfl⟩ := hsl
      cases pm with
      | inp =>
        rw [h.st_inp hb hk] at hst; cases hst
        cases hsa : m.st (args.getD k 0) with
        | none => rw [hsa] at hT; cases hT
        | some sa =>
          rw [hsa] at hT
          obtain ⟨o, val⟩ := sa
          cases val with
          | none => cases o <;> cases hT
          | some V =>
            have hV := hi.pkgs _ _ V hsa rfl
            cases o
            · simp only [Option.bind, lendSlot, Option.some.injEq] at hT; subst hT; exact hV
            · simp only [Option.bind, lendSlot, Option.some.injEq] at hT; subst hT; exact hV.lendOf
      | sink =>
        rw [h.st_sink hb hk] at hst; cases hst
        cases hsa : m.st (args.getD k 0) with
        | none => rw [hsa] at hT; cases hT
        | some sa =>
          rw [hsa] at hT
          exact hi.pkgs _ sa T hsa hT
      | inout b => exact absurd rfl (hp b)
    by_cases hsa : ∃ (k : Nat) (t : Ty), fn.params[k]? = some (PMode.sink, t) ∧ args.getD k 0 = y
    · obtain ⟨k, t, hk, rfl⟩ := hsa
      rw [h.st_sinkArg hb hk] at hst; cases hst; cases hT
    have hu : Untouched fn args m.nv x y := by
      refine ⟨hyx, hyr, fun k p hk hp he => hsl ⟨k, p, hk, hp, he⟩, fun k t hk he => ?_⟩
      have hkl := lt_of_get hk
      rw [getD_of (h.len ▸ hkl)] at he
      exact hsa ⟨k, t, hk, Option.some.inj he⟩
    rw [h.st_other hb hu] at hst
    exact hi.pkgs y sl T hst hT
  armed y E sl hy hsl := by
    -- only a caller binding is one `letd` made
    cases hdb : E.dbind with
    | false => exact ArmOK.of_dbind hdb
    | true =>
      obtain ⟨hren, hyx, E1, h1, rfl⟩ := h.dbind_frame hy hdb
      exact h.armed_frame hi hb hren hyx h1 hsl
  rootbLive p E hp hrb := by
    rcases h.ctx_cases p with ⟨rfl, hc⟩ | ⟨rfl, hc⟩ | ⟨k, t, hk, rfl, hc⟩ | ⟨k, t, hk, rfl, hc⟩ |
        ⟨k, b', t, hk, rfl, hc⟩ | ⟨hy', hyx, hc⟩ | ⟨hc, v, hv, rfl⟩ <;> rw [hc] at hp <;> (try cases hp)
    · exact absurd hrb (resMode_ne' fn)
    · exact absurd hrb (resMode_ne' fn)
    · exact callPe_live _ _ _ _
    · cases hrb
    · cases hrb
    · obtain ⟨E1', h1', rfl⟩ := Option.map_eq_some_iff.mp hp
      rw [clean_mode] at hrb
      rw [clean_live]; exact h.post_live_rootb h1' hrb
  rootbLt p E hp hrb r hr := by
    rcases h.ctx_cases p with ⟨rfl, hc⟩ | ⟨rfl, hc⟩ | ⟨k, t, hk, rfl, hc⟩ | ⟨k, t, hk, rfl, hc⟩ |
        ⟨k, b', t, hk, rfl, hc⟩ | ⟨hy', hyx, hc⟩ | ⟨hc, v, hv, rfl⟩ <;> rw [hc] at hp <;> (try cases hp)
    · exact absurd hrb (resMode_ne' fn)
    · exact absurd hrb (resMode_ne' fn)
    · obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
      rcases RSetup.pe_dep h.sOK hd with ⟨_, Er, hEr, _⟩ | ⟨hs, _⟩
      · exact Nat.lt_of_lt_of_le (h.frame_lt hEr) (Nat.le_add_right _ _)
      · obtain ⟨w, b, t, rfl, hbw, _⟩ := RSetup.sym_ren h.sOK hs
        simp only [callS, bndOf] at hbw
        split at hbw
        · rename_i b' t' hwp
          show callRen fn.params args m.nv w < _
          simp only [callRen, hwp]
          exact Nat.lt_of_lt_of_le (h.argLt (lt_of_get hwp)) (Nat.le_add_right _ _)
        · cases hbw
    · cases hrb
    · cases hrb
    · obtain ⟨E1', h1', rfl⟩ := Option.map_eq_some_iff.mp hp
      rw [clean_mode] at hrb
      obtain ⟨E0, h0, hm⟩ := h.postdm.2 p E1' h1'
      have := h.post_rootb h0 (hm ▸ hrb)
      rw [h1'] at this; cases this
      rw [clean_id (Or.inr hrb) (h.post_live_rootb h1' hrb)] at hr
      exact hi.rootbLt p E1' h0 (hm ▸ hrb) r hr

end CallH

end A2
