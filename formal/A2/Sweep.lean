import A2.Heap

/-! A2 — A3.1's sweep: the blocks nothing reaches are removed, and their
payloads freed (`Mem.sweep`).  It touches nothing else: the slots, `nid` and
`nv` stay, every reached block stays as it was, and only the addresses of
the unreached payloads are freed — none of which an owned tree or a reached
payload holds (`HeapOK.sweep`).

Every lemma is stated for the sweep from roots `R` that include the store's
slots (`Mem.sweepR`, `hR`): A3 sweeps from every thread's slots at once, and
a thread's facts survive that sweep as they survive its own. -/

namespace A2

@[simp] theorem Mem.sweep_st (m : Mem) : m.sweep.st = m.st := rfl
@[simp] theorem Mem.sweep_nv (m : Mem) : m.sweep.nv = m.nv := rfl
@[simp] theorem Mem.sweep_nid (m : Mem) : m.sweep.nid = m.nid := rfl
@[simp] theorem Mem.sweep_vals (m : Mem) : m.sweep.vals = m.vals := rfl

/-- A3.1: the sweep from the roots `R`: the blocks `R` does not reach are
    removed, and their payloads freed.  `Mem.sweep` is the sweep from the
    store's own slots (`Mem.sweep_eq`). -/
noncomputable def Mem.sweepR (R : Val → Prop) (m : Mem) : Mem :=
  { m with alloc := sweepAlloc R m.blk m.alloc, blk := sweepBlk R m.blk }

theorem Mem.sweep_eq (m : Mem) : m.sweep = m.sweepR m.vals := rfl

@[simp] theorem Mem.sweepR_st (R : Val → Prop) (m : Mem) : (m.sweepR R).st = m.st := rfl
@[simp] theorem Mem.sweepR_nv (R : Val → Prop) (m : Mem) : (m.sweepR R).nv = m.nv := rfl
@[simp] theorem Mem.sweepR_nid (R : Val → Prop) (m : Mem) : (m.sweepR R).nid = m.nid := rfl
@[simp] theorem Mem.sweepR_vals (R : Val → Prop) (m : Mem) : (m.sweepR R).vals = m.vals := rfl

theorem sweepBlk_some {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} {bl : Blk} :
    sweepBlk R B k = some bl ↔ B k = some bl ∧ Reached R B k := by
  unfold sweepBlk
  by_cases h : Reached R B k
  · simp [h]
  · simp [h]

theorem sweepAlloc_true {R : Val → Prop} {B : Nat → Option Blk} {a : Nat → Bool} {i : Nat} :
    sweepAlloc R B a i = true ↔ a i = true ∧ ¬ Unreached R B i := by
  unfold sweepAlloc
  by_cases h : Unreached R B i
  · simp [h]
  · simp [h]

/-- The swept store keeps exactly the reached blocks. -/
theorem Mem.sweepR_blk {R : Val → Prop} {m : Mem} {k : Nat} {bl : Blk} :
    (m.sweepR R).blk k = some bl ↔ m.blk k = some bl ∧ Reached R m.blk k :=
  sweepBlk_some

theorem Mem.sweep_blk {m : Mem} {k : Nat} {bl : Blk} :
    m.sweep.blk k = some bl ↔ m.blk k = some bl ∧ Reached m.vals m.blk k :=
  sweepBlk_some

/-- The swept store keeps every block it keeps as it was. -/
theorem Mem.sweepR_blkLe (R : Val → Prop) (m : Mem) : BlkLe (m.sweepR R).blk m.blk :=
  BlkLe.of_le fun _ _ h => (Mem.sweepR_blk.mp h).1

theorem Mem.sweep_blkLe (m : Mem) : BlkLe m.sweep.blk m.blk := Mem.sweepR_blkLe m.vals m

/-- An address stays live unless an unreached payload owns it. -/
theorem Mem.sweepR_alloc {R : Val → Prop} {m : Mem} {i : Nat} :
    (m.sweepR R).alloc i = true ↔ m.alloc i = true ∧ ¬ Unreached R m.blk i :=
  sweepAlloc_true

theorem Mem.sweep_alloc {m : Mem} {i : Nat} :
    m.sweep.alloc i = true ↔ m.alloc i = true ∧ ¬ Unreached m.vals m.blk i :=
  sweepAlloc_true

/-- What a block refers to through more blocks, it still refers to. -/
theorem Refers.grow {B B' : Nat → Option Blk} (hb : BlkLe B B') {v : Val} {k : Nat} (h : Refers B v k) :
    Refers B' v k := by
  rcases h with h | ⟨bl, hk, h⟩
  · exact Or.inl h
  · obtain ⟨bl', hk', hrd⟩ := hb.rd hk
    exact Or.inr ⟨bl', hk', hrd ▸ h⟩

/-- Reachability from more values, through more blocks. -/
theorem Reached.mono {R R' : Val → Prop} {B B' : Nat → Option Blk} (hR : ∀ v, R v → R' v)
    (hb : BlkLe B B') {k : Nat} (h : Reached R B k) : Reached R' B' k := by
  induction h with
  | root hv hr => exact .root (hR _ hv) (hr.grow hb)
  | pay _ hk hr ih =>
    obtain ⟨bl', hk', hrd⟩ := hb.rd hk
    exact .pay ih hk' (hrd ▸ hr.grow hb)

/-- A block a slot's value refers to is reached. -/
theorem Reached.of_slot {m : Mem} {x : Var} {o : Bool} {v : Val} (hx : m.st x = some ⟨o, some v⟩)
    {k : Nat} (h : Refers m.blk v k) : Reached m.vals m.blk k :=
  .root ⟨x, o, hx⟩ h

/-- Reachability through the swept blocks: the chains run through reached
    blocks only, which the sweep keeps. -/
theorem Reached.sweepBlk {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} (h : Reached R B k) :
    Reached R (sweepBlk R B) k := by
  induction h with
  | root hv hr =>
    rename_i v k
    refine .root hv ?_
    rcases hr with h | ⟨bl, hk, h⟩
    · exact Or.inl h
    · exact Or.inr ⟨bl, sweepBlk_some.mpr ⟨hk, .root hv (Or.inr ⟨bl, hk, h⟩)⟩, h⟩
  | pay hr' hk hr ih =>
    rename_i k k' bl
    refine .pay ih (sweepBlk_some.mpr ⟨hk, hr'⟩) ?_
    rcases hr with h | ⟨bl', hk', h⟩
    · exact Or.inl h
    · exact Or.inr ⟨bl', sweepBlk_some.mpr ⟨hk', .pay hr' hk (Or.inr ⟨bl', hk', h⟩)⟩, h⟩

/-- Reachability in the swept store. -/
theorem Reached.sweep {m : Mem} {k : Nat} (h : Reached m.vals m.blk k) :
    Reached m.sweep.vals m.sweep.blk k :=
  Reached.sweepBlk h

/-- **The sweep keeps the heap's invariant**: the owned trees are as they
    were, and their addresses, and the reached payloads', stay live — the
    sweep frees only what an unreached payload owns, which no owned tree and
    no other payload holds. -/
theorem HeapOK.sweepR {R : Val → Prop} {m : Mem} (hh : HeapOK m) : HeapOK (m.sweepR R) where
  nodup x t h := hh.nodup x t h
  disj x y t u hne h1 h2 := hh.disj x y t u hne h1 h2
  alloc x t h i hi := by
    obtain ⟨ha, hlt⟩ := hh.alloc x t h i hi
    refine ⟨Mem.sweepR_alloc.mpr ⟨ha, ?_⟩, hlt⟩
    rintro ⟨k, bl, hk, _, hik⟩
    exact hh.notPay h hi ⟨k, bl, hk, hik⟩
  self x t h := hh.self x t h
  blk k bl hk := by
    obtain ⟨hk0, hreach⟩ := Mem.sweepR_blk.mp hk
    obtain ⟨hkey, hnd, hall⟩ := hh.blk k bl hk0
    refine ⟨hkey, hnd, fun i hi => ?_⟩
    obtain ⟨ha, hlt, hsl, hoth⟩ := hall i hi
    refine ⟨Mem.sweepR_alloc.mpr ⟨ha, ?_⟩, hlt, hsl, fun k' bl' hk' hk'' => hoth k' bl' hk'
      (Mem.sweepR_blk.mp hk'').1⟩
    rintro ⟨k', bl', hk', hnr, hik'⟩
    by_cases he : k' = k
    · subst he; rw [hk0] at hk'; cases hk'; exact hnr hreach
    · exact hoth k' bl' he hk' hik'

theorem HeapOK.sweep {m : Mem} (hh : HeapOK m) : HeapOK m.sweep := hh.sweepR

/-! ### A3.1: the sweep keeps every borrow valid

A slot's value, and the payload of a reached block, refer only to reached
blocks (`Kept`). A node a borrow lands in holds the address of the handle
that reaches it, so if it lies in a payload, the handle's value refers to
that block, and the sweep keeps it. A share carries its block, which its
holder refers to. So everything the invariant says of a slot holds over
the swept store (`MInv.sweep`), and so does `Covers` (`Covers.sweep`). -/

section
variable {R : Val → Prop} {m : Mem}

/-- Every block `v` refers to is reached from `R`: the sweep keeps it. -/
def Kept (R : Val → Prop) (m : Mem) (v : Val) : Prop := ∀ k, Refers m.blk v k → Reached R m.blk k

/-- An address that, if a payload owns it, lies in a block `R` reaches. -/
def KeptAddr (R : Val → Prop) (m : Mem) (i : Nat) : Prop :=
  ∀ k bl, m.blk k = some bl → i ∈ bl.rd.ids → Reached R m.blk k

theorem Kept.sub {v w : Val} (h : Kept R m v) (hs : Sub w v) : Kept R m w := by
  intro k hr
  apply h k
  rcases hr with ⟨p, hp⟩ | ⟨bl, hk, ⟨c, hc, hci⟩ | ⟨d, o, l, hd, hdi⟩⟩
  · exact Or.inl ⟨p, hp.trans hs⟩
  · exact Or.inr ⟨bl, hk, Or.inl ⟨c, hc.trans hs, hci⟩⟩
  · exact Or.inr ⟨bl, hk, Or.inr ⟨d, o, l, hd.trans hs, hdi⟩⟩

theorem Kept.slot (hR : ∀ v, m.vals v → R v) {x : Var} {o : Bool} {v : Val}
    (hx : m.st x = some ⟨o, some v⟩) : Kept R m v :=
  fun _ h => .root (hR _ ⟨x, o, hx⟩) h

theorem Kept.pay {k : Nat} {bl : Blk} (hr : Reached R m.blk k) (hk : m.blk k = some bl) :
    Kept R m bl.rd := fun _ h => .pay hr hk h

/-- Nothing (`.int 0`) refers to no block. -/
theorem Kept.int (n : Nat) : Kept R m (.int n) := by
  intro k hr
  rcases hr with ⟨p, hp⟩ | ⟨bl, _, ⟨c, hc, _⟩ | ⟨d, o, l, hd, _⟩⟩
  · cases p <;> cases hp
  · cases hc
  · cases hd

/-- A3.2: what a reached block's holders read is kept. -/
theorem Kept.rd {k : Nat} {bl : Blk} (hr : Reached R m.blk k) (hk : m.blk k = some bl) :
    Kept R m bl.rd := Kept.pay hr hk

theorem Kept.href {v : Val} (h : Kept R m v) {c : Nat} (hs : Sub (.href c) v) : KeptAddr R m c :=
  fun k bl hk hc => h k (Or.inr ⟨bl, hk, Or.inl ⟨c, hs, hc⟩⟩)

theorem Kept.view {v : Val} (h : Kept R m v) {d o l : Nat} (hs : Sub (.view d o l) v) :
    KeptAddr R m d :=
  fun k bl hk hd => h k (Or.inr ⟨bl, hk, Or.inr ⟨d, o, l, hs, hd⟩⟩)

theorem Kept.share {v : Val} (h : Kept R m v) {k : Nat} {p : Option Val} (hs : Sub (Val.share k p) v) :
    Reached R m.blk k :=
  h k (Or.inl ⟨p, hs⟩)

theorem Kept.arc {v : Val} (h : Kept R m v) {k : Nat} {p : Val} (hs : Sub (.arc k p) v) :
    Reached R m.blk k :=
  h k (Or.inl ⟨some p, hs⟩)

theorem Kept.lk {v : Val} (h : Kept R m v) {k : Nat} (hs : Sub (.lk k) v) : Reached R m.blk k :=
  h k (Or.inl ⟨none, hs⟩)

/-- A node holding a kept address lies in a kept place. -/
theorem KeptAddr.node {i : Nat} (h : KeptAddr R m i) {n : Val} (hi : i ∈ n.ids) :
    ∀ k bl, m.blk k = some bl → Sub n bl.rd → Reached R m.blk k :=
  fun k bl hk hs => h k bl hk (hs.ids i hi)

end

theorem ArcIn.sub {τ : Ty} {T : Val} {u : Ty} {k : Nat} {p : Option Val} (h : ArcIn τ T u k p) :
    Sub (Val.share k p) T := by
  induction h with
  | here => exact Sub.refl _
  | lk => exact Sub.refl _
  | child he _ ih => exact Sub.child he ih
  | fst _ ih => exact Sub.fst ih
  | snd _ ih => exact Sub.snd ih
  | inl _ ih => exact Sub.inl ih
  | inr _ ih => exact Sub.inr ih
  | pkg _ ih => exact Sub.pkg ih

section
variable {R : Val → Prop} {m : Mem} (hR : ∀ v, m.vals v → R v)
include hR

omit hR in
theorem NodeAt.sweep {c : Nat} {n : Val} (h : NodeAt m c n) (hc : KeptAddr R m c) :
    NodeAt (m.sweepR R) c n := by
  rcases h with ⟨x, T, hT, hs, hn⟩ | ⟨k, bl, hk, hs, ty, d, es, rfl⟩
  · exact Or.inl ⟨x, T, hT, hs, hn⟩
  · exact Or.inr ⟨k, bl, Mem.sweepR_blk.mpr ⟨hk, hc k bl hk (hs.ids c (by simp))⟩, hs, ty, d, es, rfl⟩

omit hR in
theorem DataAt.sweep {d : Nat} {n : Val} (h : DataAt m d n) (hd : KeptAddr R m d) :
    DataAt (m.sweepR R) d n := by
  rcases h with ⟨x, T, hT, hs, hn⟩ | ⟨k, bl, hk, hs, ty, c, es, rfl⟩
  · exact Or.inl ⟨x, T, hT, hs, hn⟩
  · exact Or.inr ⟨k, bl, Mem.sweepR_blk.mpr ⟨hk, hd k bl hk (hs.ids d (by simp))⟩, hs, ty, c, es, rfl⟩

/-- What a root reaches, it reaches in the swept store: a handle it holds
    refers to the block it reaches into. -/
theorem RootNode.sweep {r : Var} {n : Val} (h : RootNode m r n) : RootNode (m.sweepR R) r n := by
  rcases h with ⟨T, hT, ht⟩ | ⟨v, c, hv, ht, hn⟩ | ⟨v, d, o, l, hv, ht, hn⟩ | h
  · exact Or.inl ⟨T, hT, ht⟩
  · exact Or.inr (Or.inl ⟨v, c, hv, ht, hn.sweep ((Kept.slot hR hv).href ht.sub)⟩)
  · exact Or.inr (Or.inr (Or.inl ⟨v, d, o, l, hv, ht, hn.sweep ((Kept.slot hR hv).view ht.sub)⟩))
  · exact Or.inr (Or.inr (Or.inr h))

theorem RootMem.sweep {r : Var} (h : RootMem m r) : RootMem (m.sweepR R) r := by
  rcases h with h | ⟨n0, hn⟩
  · exact Or.inl h
  · exact Or.inr ⟨n0, hn.sweep hR⟩

theorem Landed.sweep {dep : Dep} {n : Val} (h : Landed m dep n)
    (hk : ∀ k bl, m.blk k = some bl → Sub n bl.rd → Reached R m.blk k) : Landed (m.sweepR R) dep n := by
  rcases h with ⟨n0, hr, hl⟩ | ⟨hs, hro, k, bl, hkb, hsub⟩
  · exact Or.inl ⟨n0, hr.sweep hR, hl⟩
  · exact Or.inr ⟨hs, hro.sweep hR, k, bl, Mem.sweepR_blk.mpr ⟨hkb, hk k bl hkb hsub⟩, hsub⟩

theorem ArcLanded.sweep {dep : Dep} {n : Val} (h : ArcLanded m dep n) : ArcLanded (m.sweepR R) dep n := by
  rcases h with ⟨n0, hr, hl⟩ | ⟨hs, hro⟩
  · exact Or.inl ⟨n0, hr.sweep hR, hl⟩
  · exact Or.inr ⟨hs, hro.sweep hR⟩

/-- A landed node lies in an owned tree or in a payload; in a kept place if
    it holds a kept address. -/
theorem Landed.kept {dep : Dep} {t : Ty} {c d : Nat} {es : List Val}
    (h : Landed m dep (.node t c d es)) {i : Nat} (hi : i ∈ (Val.node t c d es).ids) (hk : KeptAddr R m i) :
    Kept R m (.node t c d es) := by
  rcases h.inMem with ⟨o, T, hT, hs⟩ | ⟨k, bl, hkb, hs⟩
  · exact (Kept.slot hR hT).sub hs
  · exact (Kept.rd (hk.node hi k bl hkb hs) hkb).sub hs

theorem ViewAt.sweep {dep : Dep} {d o l : Nat} {s : Ty} (h : ViewAt m dep d o l s)
    (hd : KeptAddr R m d) : ViewAt (m.sweepR R) dep d o l s := by
  obtain ⟨c, es, hk, hla, hl, hw⟩ := h
  exact ⟨c, es, hk, hla.sweep hR (hd.node (by simp)), hl, hw⟩

theorem ViewsOK.sweep {τ : Ty} {T : Val} {H : List Dep} (h : ViewsOK m τ T H) (hT : Kept R m T) :
    ViewsOK (m.sweepR R) τ T H := by
  intro s v hin
  obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := h s v hin
  exact ⟨d, o, l, rfl, dep, hd, ha.sweep hR (hT.view hin.sub)⟩

omit hR in
theorem SharesOK.sweep {τ : Ty} {T : Val} (h : SharesOK m τ T) (hT : Kept R m T) :
    SharesOK (m.sweepR R) τ T := fun u k p ha => by
  cases p with
  | some p => exact Mem.sweepR_blk.mpr ⟨h u k _ ha, hT.share ha.sub⟩
  | none =>
    obtain ⟨o, ho⟩ := h u k none ha
    exact ⟨o, Mem.sweepR_blk.mpr ⟨ho, hT.share ha.sub⟩⟩

theorem HrefAt.sweep {dep : Dep} {c : Nat} {t : Ty} {H : List Dep} (h : HrefAt m dep c t H)
    (hc : KeptAddr R m c) : HrefAt (m.sweepR R) dep c t H := by
  obtain ⟨d, es, hla, hw, hv, hn, hsh⟩ := h
  have hkn := hla.kept hR (i := c) (by simp) hc
  exact ⟨d, es, hla.sweep hR (hc.node (by simp)), hw, hv.sweep hR hkn, hn, hsh.sweep hkn⟩

theorem ValOK.sweep {τ : Ty} {v : Val} {P H : List Dep} (h : ValOK m τ v P H) (hv : Kept R m v) :
    ValOK (m.sweepR R) τ v P H := by
  induction h with
  | int => exact .int
  | href h =>
    obtain ⟨dep, hd, ha⟩ := h
    exact .href ⟨dep, hd, ha.sweep hR (hv.href (Sub.refl _))⟩
  | view h =>
    obtain ⟨dep, hd, ha⟩ := h
    exact .view ⟨dep, hd, ha.sweep hR (hv.view (Sub.refl _))⟩
  | pair _ _ ihx ihy => exact .pair (ihx (hv.sub (Sub.fst (Sub.refl _)))) (ihy (hv.sub (Sub.snd (Sub.refl _))))
  | inl _ ih => exact .inl (ih (hv.sub (Sub.inl (Sub.refl _))))
  | inr _ ih => exact .inr (ih (hv.sub (Sub.inr (Sub.refl _))))
  | pkg _ ih => exact .pkg (ih (hv.sub (Sub.pkg (Sub.refl _))))
  | arc hk hw hvf hl =>
    obtain ⟨dep, hd, hla⟩ := hl
    exact .arc (Mem.sweepR_blk.mpr ⟨hk, hv.arc (Sub.refl _)⟩) hw hvf ⟨dep, hd, hla.sweep hR⟩
  | lk h =>
    obtain ⟨o, ho⟩ := h
    exact .lk ⟨o, Mem.sweepR_blk.mpr ⟨ho, hv.lk (Sub.refl _)⟩⟩

theorem SlotOK.sweep {E : Entry} {sl : Slot} (h : SlotOK m E sl)
    (hk : ∀ v, sl.val = some v → Kept R m v) : SlotOK (m.sweepR R) E sl := by
  obtain ⟨h1, h2, h3⟩ := h
  refine ⟨h1, fun ho => ?_, fun ho hl => ?_⟩
  · obtain ⟨a, b, c⟩ := h2 ho
    exact ⟨a, b, fun hl => by obtain ⟨T, hT, hv⟩ := c hl; exact ⟨T, hT, hv.sweep hR (hk T hT)⟩⟩
  · obtain ⟨v, hv, hok⟩ := h3 ho hl
    exact ⟨v, hv, hok.sweep hR (hk v hv)⟩

theorem ArmOK.sweep {E : Entry} {sl : Slot} (h : ArmOK m E sl)
    (hk : ∀ v, sl.val = some v → Kept R m v) : ArmOK (m.sweepR R) E sl := by
  intro hd hos T hT
  obtain ⟨h1, h2⟩ := h hd hos T hT
  exact ⟨h1, h2.sweep hR (hk T hT)⟩

theorem Kept.of_slot {x : Var} {sl : Slot} (hsl : m.st x = some sl) :
    ∀ v, sl.val = some v → Kept R m v := by
  intro v hv
  obtain ⟨o, val⟩ := sl
  simp only at hv; subst hv
  exact Kept.slot hR hsl

/-- **The sweep keeps the memory invariant**: every slot's value refers to
    reached blocks only, which the sweep keeps. -/
theorem MInv.sweepR {Γ : Ctx} (hi : MInv m Γ) : MInv (m.sweepR R) Γ where
  dom := hi.dom
  slot v E hv := by
    obtain ⟨sl, hsl, hok, hs⟩ := hi.slot v E hv
    exact ⟨sl, hsl, hok, hs.sweep hR (Kept.of_slot hR hsl)⟩
  heap := hi.heap.sweepR
  nvSt := hi.nvSt
  noInout := hi.noInout
  wf := hi.wf
  rootbLive := hi.rootbLive
  rootbLt := hi.rootbLt
  names := hi.names
  held := hi.held
  pkgs := hi.pkgs
  armed v E sl hE hsl := (hi.armed v E sl hE hsl).sweep hR (Kept.of_slot hR hsl)
  shares v E sl T hE hsl hown hT := (hi.shares v E sl T hE hsl hown hT).sweep (Kept.of_slot hR hsl T hT)
  blocks k bl hk := by
    obtain ⟨hk0, hr⟩ := Mem.sweepR_blk.mp hk
    obtain ⟨h1, h2, h3, h4⟩ := hi.blocks k bl hk0
    refine ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, ?_⟩, h4⟩
    obtain ⟨t, kd, q⟩ := bl
    cases kd with
    | arc => simp only at hp; subst hp; exact (h3 _ rfl).2.sweep (Kept.pay hr hk0)
    | lock => exact SharesOK.of_noArc (h4 rfl)

end

theorem MInv.sweep {m : Mem} {Γ : Ctx} (hi : MInv m Γ) : MInv m.sweep Γ := hi.sweepR fun _ h => h

/-- **The sweep keeps `Covers`**: it frees exactly the unreached payloads,
    and keeps the reached ones. -/
theorem Covers.sweepR {R : Val → Prop} {m : Mem} (hc : Covers m) : Covers (m.sweepR R) := by
  intro i hi
  obtain ⟨ha, hnu⟩ := Mem.sweepR_alloc.mp hi
  rcases hc i ha with ⟨x, T, hT, hiT⟩ | ⟨k, bl, hk, hik⟩
  · exact Or.inl ⟨x, T, hT, hiT⟩
  · exact Or.inr ⟨k, bl, Mem.sweepR_blk.mpr ⟨hk, Classical.byContradiction fun hr => hnu ⟨k, bl, hk, hr, hik⟩⟩,
      hik⟩

theorem Covers.sweep {m : Mem} (hc : Covers m) : Covers m.sweep := hc.sweepR

/-- When no slot holds a value, nothing is reached: the sweep removes every
    block. -/
theorem Mem.sweep_empty {m : Mem} (h : ∀ x o v, m.st x ≠ some ⟨o, some v⟩) (k : Nat) :
    m.sweep.blk k = none := by
  have hnr : ∀ k, ¬ Reached m.vals m.blk k := by
    intro k hr
    induction hr with
    | root hv _ => obtain ⟨x, o, hx⟩ := hv; exact h x o _ hx
    | pay _ _ _ ih => exact ih
  cases hk : m.sweep.blk k with
  | none => rfl
  | some bl => exact absurd (Mem.sweep_blk.mp hk).2 (hnr k)

/-- Reachability from other roots, when every root that refers to a block
    is one of them. -/
theorem Reached.of_roots {R R' : Val → Prop} {B : Nat → Option Blk} {k : Nat} (h : Reached R B k)
    (hR : ∀ v, R v → ∀ k', Refers B v k' → R' v) : Reached R' B k := by
  induction h with
  | root hv hr => exact .root (hR _ hv _ hr) hr
  | pay _ hk hr ih => exact .pay ih hk hr

/-- What a `recover` frame's store reached outside the frame, the store
    reaches: its slots there are the frame's store's, and every block on the
    way is kept (`CatchOK`). -/
theorem Reached.catch {m m0 : Mem} {x : Var} {sp : List Var}
    (hst : ∀ v, v ∉ sp → v ≠ x → m.st v = m0.st v)
    (hb : ∀ k bl, m0.blk k = some bl → Reached (OutVals m0 x sp) m0.blk k →
      ∃ bl', m.blk k = some bl' ∧ BlkKeep bl bl')
    {k : Nat} (h : Reached (OutVals m0 x sp) m0.blk k) : Reached m.vals m.blk k := by
  have hrefers : ∀ {v k}, Reached (OutVals m0 x sp) m0.blk k → Refers m0.blk v k → Refers m.blk v k := by
    intro v k hk hr
    rcases hr with h | ⟨bl, hbl, h⟩
    · exact Or.inl h
    · obtain ⟨bl', h1, h2⟩ := hb k bl hbl hk
      exact Or.inr ⟨bl', h1, by rw [h2.rd]; exact h⟩
  induction h with
  | root hv hr =>
    obtain ⟨y, o, hy, hyx, h0⟩ := hv
    exact .root ⟨y, o, by rw [hst y hy hyx]; exact h0⟩ (hrefers (.root ⟨y, o, hy, hyx, h0⟩ hr) hr)
  | pay hr' hk hr ih =>
    obtain ⟨bl', h1, h2⟩ := hb _ _ hk hr'
    exact .pay ih h1 (by rw [h2.rd]; exact hrefers (.pay hr' hk hr) hr)

/-- The sweep keeps what a `recover` frame returns to. -/
theorem CatchOK.sweepR {R : Val → Prop} {m : Mem} (hR : ∀ v, m.vals v → R v) :
    ∀ {s : Stmt}, CatchOK m s → CatchOK (m.sweepR R) s
  | .seq a _, h => CatchOK.sweepR hR (s := a) h
  | .scope _ k, h => CatchOK.sweepR hR (s := k) h
  | .scopeD _ _ k, h => CatchOK.sweepR hR (s := k) h
  | .rbind _ k, h => CatchOK.sweepR hR (s := k) h
  | .frozen _ k, h => CatchOK.sweepR hR (s := k) h
  | .catchR x m0 k, h => by
    obtain ⟨h1, h2, h3, h4, h5⟩ := h
    exact ⟨h1, h2, h3, fun k' bl hk hr => by
        obtain ⟨bl', hk', hkp⟩ := h4 k' bl hk hr
        exact ⟨bl', Mem.sweepR_blk.mpr ⟨hk', (Reached.catch h1 h4 hr).mono hR (BlkLe.refl _)⟩, hkp⟩,
      CatchOK.sweepR hR (s := k) h5⟩
  | .skip, _ => trivial
  | .letv .., _ => trivial
  | .letcall .., _ => trivial
  | .assign .., _ => trivial
  | .ite .., _ => trivial
  | .while .., _ => trivial
  | .push .., _ => trivial
  | .free .., _ => trivial
  | .panic, _ => trivial
  | .letrec .., _ => trivial
  | .unpair .., _ => trivial
  | .callc .., _ => trivial
  | .letd .., _ => trivial
  | .edit .., _ => trivial

/-- **The sweep keeps the invariant** of a running configuration, from any
    roots that include the store's slots. -/
theorem Inv.sweepR {R : Val → Prop} {m : Mem} (hR : ∀ v, m.vals v → R v) {Γ : Ctx} {F : List Var}
    {s : Stmt} (hi : Inv m Γ F s) : Inv (m.sweepR R) Γ F s :=
  { toMInv := hi.toMInv.sweepR hR
    nvS := hi.nvS
    nvF := hi.nvF
    anch := hi.anch
    spineNd := hi.spineNd
    spineDom := hi.spineDom
    catchOK := hi.catchOK.sweepR hR
    cover := hi.cover.sweepR
    pinOut := hi.pinOut
    pinIn := hi.pinIn
    dtorOut := hi.dtorOut
    dtorIn := hi.dtorIn }

theorem Inv.sweep {m : Mem} {Γ : Ctx} {F : List Var} {s : Stmt} (hi : Inv m Γ F s) : Inv m.sweep Γ F s :=
  hi.sweepR fun _ h => h

/-- The packages in memory are the slots', which the sweep keeps. -/
theorem MemCodes.sweepR {P : Prog} {R : Val → Prop} {m : Mem} (h : MemCodes P m) : MemCodes P (m.sweepR R) := h

theorem MemCodes.sweep {P : Prog} {m : Mem} (h : MemCodes P m) : MemCodes P m.sweep := h

end A2
