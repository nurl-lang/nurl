import A2.Frame

/-! A2 — evaluating a right-hand side keeps the invariant and yields a value
valid as its entry says. -/

namespace A2

theorem VecOf.unique {m : Mem} (hh : HeapOK m) {y : Var} {t t' : Ty} {c c' d d' : Nat}
    {es es' : List Val} (h1 : VecOf m y t c d es) (h2 : VecOf m y t' c' d' es') :
    Val.node t c d es = Val.node t' c' d' es' := by
  obtain ⟨_, _, h1⟩ := h1
  obtain ⟨_, _, h2⟩ := h2
  rcases h1 with h1 | ⟨h1, n1⟩ <;> rcases h2 with h2 | ⟨h2, n2⟩
  · rw [h1] at h2; cases h2; rfl
  · rw [h1] at h2; cases h2
  · rw [h1] at h2; cases h2
  · rw [h1] at h2; cases h2; exact nodeAt_unique hh n1 n2

theorem comp_ne_view {a b : Kind} (ha : a ≠ .view) (hb : b ≠ .view) : comp a b ≠ .view := by
  cases a <;> cases b <;> simp_all [comp]

theorem comp_ne_self {a b : Kind} (hb : b ≠ .self) : comp a b ≠ .self := by
  cases a <;> cases b <;> simp_all [comp]

/-- A borrowed `Vec` taken from `y` in way `k`. -/
theorem derive_hrefAt {m : Mem} {y : Var} {E : Entry} {N : Val}
    (hroot : E.mode.isRoot = true → RootNode m y N)
    {k : Kind}
    (hbor : E.mode = .bor → ∃ dep ∈ E.path, Landed m dep N)
    (hrk : rootKind E.ty k = k)
    {t : Ty} {c d : Nat} {es : List Val} (hl : Lands k (.node t c d es) N)
    (hw : WFv (.vec t) (.node t c d es)) {H : List Dep} (hv : ViewsOK m (.vec t) (.node t c d es) H)
    (hn : NamesIn (.node t c d es) H) (hsh : SharesOK m (.vec t) (.node t c d es)) :
    ∃ dep ∈ derive y E k, HrefAt m dep c t H := by
  unfold derive
  cases h : E.mode.isRoot with
  | true =>
    simp only [↓reduceIte, List.mem_singleton, exists_eq_left]
    exact ⟨d, es, Or.inl ⟨N, hroot h, by rw [hrk]; exact hl⟩, hw, hv, hn, hsh⟩
  | false =>
    simp only [Bool.false_eq_true, ↓reduceIte, List.mem_map]
    have hb : E.mode = .bor := by cases hm : E.mode <;> simp_all [Mode.isRoot]
    obtain ⟨dep, hd, hld⟩ := hbor hb
    exact ⟨_, ⟨dep, hd, rfl⟩, d, es, hld.comp hl, hw, hv, hn, hsh⟩

/-- A view taken from `y` in way `k`. -/
theorem derive_viewAt {m : Mem} {y : Var} {E : Entry} {N : Val}
    (hroot : E.mode.isRoot = true → RootNode m y N)
    (hbor : E.mode = .bor → ∃ dep ∈ E.path, Landed m dep N)
    {k : Kind} (hk : k ≠ .self) (hrk : rootKind E.ty k = k)
    {t : Ty} {c d : Nat} {es : List Val} (hl : Lands k (.node t c d es) N)
    {o l : Nat} (hlen : o + l ≤ es.length) (hw : WFv (.vec t) (.node t c d es)) :
    ∃ dep ∈ derive y E k, ViewAt m dep d o l t := by
  unfold derive
  cases h : E.mode.isRoot with
  | true =>
    simp only [↓reduceIte, List.mem_singleton, exists_eq_left]
    exact ⟨c, es, by rw [hrk]; exact hk, Or.inl ⟨N, hroot h, by rw [hrk]; exact hl⟩, hlen, hw⟩
  | false =>
    simp only [Bool.false_eq_true, ↓reduceIte, List.mem_map]
    have hb : E.mode = .bor := by cases hm : E.mode <;> simp_all [Mode.isRoot]
    obtain ⟨dep, hd, hld⟩ := hbor hb
    exact ⟨_, ⟨dep, hd, rfl⟩, c, es, comp_ne_self hk, hld.comp hl, hlen, hw⟩

theorem Lands.elem {t : Ty} {c d : Nat} {es : List Val} {e : Val} (he : e ∈ es) :
    Lands .inner e (.node t c d es) :=
  Or.inr (Or.inr ⟨rfl, e, Child.elem he, Sub.refl _⟩)

theorem WFv.elem {t : Ty} {T : Val} (hw : WFv (.vec t) T) {c d : Nat} {es : List Val}
    {u : Ty} (hT : T = .node u c d es) {e : Val} (he : e ∈ es) : WFv t e := by
  subst hT; cases hw with | node h => exact h e he

theorem ViewsOK.elem {m : Mem} {t u : Ty} {c d : Nat} {es : List Val} {H : List Dep}
    (hv : ViewsOK m (.vec t) (.node u c d es) H) {e : Val} (he : e ∈ es) : ViewsOK m t e H :=
  fun s v hin => hv s v (ViewIn.child he hin)

/-- Values that hold no views: nothing inside them can dangle. -/
theorem ViewsOK.none {m : Mem} {t : Ty} (ht : t.holdsView = false) (T : Val) (H : List Dep) :
    ViewsOK m t T H := by
  intro s v hin
  have := hin.holdsView
  rw [ht] at this; cases this

/-- A3.5b: the views a package's environment holds are the package's (a Send
    one's holds none). -/
theorem ViewsOK.pkg {m : Mem} {fs : List Nat} {te : Ty} {ms : List Nat} {q : Cross} {x : Val}
    {cs : List (Var × PMode × Ty)} {H : List Dep} (h : ViewsOK m (.fn ms q) (.pkg fs te ms x cs) H)
    (hq : q.Fits te cs) : ViewsOK m te x H := by
  cases q with
  | any => exact fun s v hin => h s v (ViewIn.pkg hin)
  | send => exact ViewsOK.none (hq.send rfl).1 _ _
  | sync => exact ViewsOK.none (hq.send rfl).1 _ _
  | bare => exact ViewsOK.none (hq.send rfl).1 _ _

theorem rootNode_st {m m' : Mem} (h : m'.st = m.st) {r : Var} {n : Val} (hn : RootNode m r n)
    (hb : BlkLe m.blk m'.blk := by exact BlkLe.of_le fun _ _ h => h) : RootNode m' r n := by
  have hown : ∀ o T, OwnedAt m o T → OwnedAt m' o T := fun o T hT => by
    unfold OwnedAt at *; rw [h]; exact hT
  have hnode : ∀ c n, NodeAt m c n → NodeAt m' c n := fun c n hn => by
    rcases hn with ⟨x, T, hT, hs, hn⟩ | ⟨k, bl, hk, hs, hn⟩
    · exact Or.inl ⟨x, T, hown x T hT, hs, hn⟩
    · obtain ⟨bl', hk', hrd⟩ := hb.rd hk
      exact Or.inr ⟨k, bl', hk', hrd ▸ hs, hn⟩
  have hdata : ∀ d n, DataAt m d n → DataAt m' d n := fun d n hn => by
    rcases hn with ⟨x, T, hT, hs, hn⟩ | ⟨k, bl, hk, hs, hn⟩
    · exact Or.inl ⟨x, T, hown x T hT, hs, hn⟩
    · obtain ⟨bl', hk', hrd⟩ := hb.rd hk
      exact Or.inr ⟨k, bl', hk', hrd ▸ hs, hn⟩
  rcases hn with ⟨T, h1, ht⟩ | ⟨v, c, h1, ht, hn⟩ | ⟨v, d, o, l, h1, ht, hn⟩ | ⟨v, k, q, h1, ht, hn⟩ |
    ⟨v, k, h1, ht, hn⟩
  · exact Or.inl ⟨T, by rw [h]; exact h1, ht⟩
  · exact Or.inr (Or.inl ⟨v, c, by rw [h]; exact h1, ht, hnode c _ hn⟩)
  · exact Or.inr (Or.inr (Or.inl ⟨v, d, o, l, by rw [h]; exact h1, ht, hdata d _ hn⟩))
  · exact Or.inr (Or.inr (Or.inr (Or.inl ⟨v, k, q, by rw [h]; exact h1, ht, hn⟩)))
  · exact Or.inr (Or.inr (Or.inr (Or.inr ⟨v, k, by rw [h]; exact h1, ht, hn⟩)))

/-- The same slots, more blocks: every root reaches what it did. -/
theorem RootKeep.of_st {m m' : Mem} (h : m'.st = m.st) (hb : BlkLe m.blk m'.blk := by exact BlkLe.of_le fun _ _ h => h)
    {r : Var} : RootKeep m m' r :=
  RootKeep.of_slot (by rw [h]) fun _ hn => rootNode_st h hn hb

theorem MInv.of_st {m m' : Mem} {Γ : Ctx} (hi : MInv m Γ) (h : m'.st = m.st) (hh : HeapOK m')
    (hnv : m.nv ≤ m'.nv) (hb : m'.blk = m.blk := by rfl) : MInv m' Γ where
  dom v := by rw [h]; exact hi.dom v
  slot v E hv := by
    obtain ⟨sl, hsl, hok, hslot⟩ := hi.slot v E hv
    refine ⟨sl, by rw [h]; exact hsl, hok, hslot.keep (fun dep _ => ?_) hb⟩
    have hk : RootKeep m m' dep.root := RootKeep.of_st h (BlkLe.of_eq hb)
    exact ⟨hk.vkeep (BlkLe.of_eq hb), hk.hkeep⟩
  heap := hh
  nvSt v hv := by rw [h] at hv; exact Nat.lt_of_lt_of_le (hi.nvSt v hv) hnv
  noInout := hi.noInout
  wf := hi.wf
  rootbLive := hi.rootbLive
  rootbLt := hi.rootbLt
  names := hi.names
  held v E sl T hE hl hsl hT := hi.held v E sl T hE hl (by rw [h] at hsl; exact hsl) hT
  pkgs v sl T hsl hT := hi.pkgs v sl T (by rw [h] at hsl; exact hsl) hT
  armed v E sl hE hsl := (hi.armed v E sl hE (by rw [h] at hsl; exact hsl)).keep fun _ _ _ dep _ =>
    (RootKeep.of_st (r := dep.root) h (BlkLe.of_eq hb)).vkeep (BlkLe.of_eq hb)
  shares v E sl T hE hsl hown hT := (hi.shares v E sl T hE (by rw [h] at hsl; exact hsl) hown hT).of_blk hb
  blocks k bl hk := by
    rw [hb] at hk
    obtain ⟨h1, h2, h3, h4⟩ := hi.blocks k bl hk
    exact ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, (h3 p hp).2.of_blk hb⟩, h4⟩

/-! ### A3.1: more blocks

The counted blocks only grow (`arcNew`), and nothing but a share reads
them: what was valid stays valid over more blocks. -/

theorem HrefAt.grow {m m' : Mem} (hst : m'.st = m.st) (hb : BlkLe m.blk m'.blk) {dep : Dep} {c : Nat}
    {t : Ty} {H : List Dep} (h : HrefAt m dep c t H) : HrefAt m' dep c t H := by
  obtain ⟨d, es, hla, hw, hv, hn, hsh⟩ := h
  exact ⟨d, es, hla.keep (RootKeep.of_st hst hb) hb, hw,
    hv.keep (fun dep _ => (RootKeep.of_st (r := dep.root) hst hb).vkeep hb), hn,
    hsh.grow hb⟩

theorem ValOK.grow {m m' : Mem} (hst : m'.st = m.st) (hb : BlkLe m.blk m'.blk) {τ : Ty} {v : Val}
    {P H : List Dep} (h : ValOK m τ v P H) : ValOK m' τ v P H := by
  induction h with
  | arc h hw hv hl =>
    obtain ⟨dep, hd, hla⟩ := hl
    exact .arc (ArcBlk.grow hb h) hw hv ⟨dep, hd, hla.keep (RootKeep.of_st hst hb)⟩
  | lk h => obtain ⟨o, ho⟩ := h; exact .lk (hb.lock ho)
  | cell h hl =>
    obtain ⟨o, ho⟩ := h
    obtain ⟨dep, hd, hla⟩ := hl
    exact .cell (hb.lock ho) ⟨dep, hd, hla.keep (RootKeep.of_st hst hb)⟩
  | int => exact .int
  | href h =>
    obtain ⟨dep, hd, ha⟩ := h
    exact .href ⟨dep, hd, ha.grow hst hb⟩
  | view h =>
    obtain ⟨dep, hd, ha⟩ := h
    exact .view ⟨dep, hd, (RootKeep.of_st (r := dep.root) hst hb).vkeep hb
      _ _ _ _ ha⟩
  | pair _ _ ihx ihy => exact .pair ihx ihy
  | inl _ ih => exact .inl ih
  | inr _ ih => exact .inr ih
  | pkg _ hq ih => exact .pkg ih hq
  | dtor _ ih => exact .dtor ih

theorem SlotOK.grow {m m' : Mem} (hst : m'.st = m.st) (hb : BlkLe m.blk m'.blk) {E : Entry} {sl : Slot}
    (hs : SlotOK m E sl) : SlotOK m' E sl := by
  have hvk : ∀ dep, VKeep m m' dep := fun dep =>
    (RootKeep.of_st (r := dep.root) hst hb).vkeep hb
  obtain ⟨h1, h2, h3⟩ := hs
  refine ⟨h1, fun ho => ?_, fun ho hl => ?_⟩
  · obtain ⟨a, b, c⟩ := h2 ho
    exact ⟨a, b, fun hl => by obtain ⟨T, hT, hv⟩ := c hl; exact ⟨T, hT, hv.keep (fun dep _ => hvk dep)⟩⟩
  · obtain ⟨v, hv, hok⟩ := h3 ho hl
    exact ⟨v, hv, hok.grow hst hb⟩

/-- What the invariant asks of the blocks. -/
def BlocksIn (m : Mem) : Prop :=
  ∀ k bl, m.blk k = some bl → bl.ty.ok = true ∧ bl.ty.holdsView = false ∧
    (∀ p, bl.pay = some p → WFv bl.ty p ∧ SharesOK m bl.ty p) ∧ (bl.kind = .lock ∨ bl.ty.hasCell = false)

/-- **More blocks**: the invariant holds over a store with the same slots and
    more blocks, each as the invariant asks. -/
theorem MInv.grow {m m' : Mem} {Γ : Ctx} (hi : MInv m Γ) (h : m'.st = m.st) (hh : HeapOK m')
    (hnv : m.nv ≤ m'.nv) (hb : BlkLe m.blk m'.blk) (hB : BlocksIn m') : MInv m' Γ where
  dom v := by rw [h]; exact hi.dom v
  slot v E hv := by
    obtain ⟨sl, hsl, hok, hslot⟩ := hi.slot v E hv
    exact ⟨sl, by rw [h]; exact hsl, hok, hslot.grow h hb⟩
  heap := hh
  nvSt v hv := by rw [h] at hv; exact Nat.lt_of_lt_of_le (hi.nvSt v hv) hnv
  noInout := hi.noInout
  wf := hi.wf
  rootbLive := hi.rootbLive
  rootbLt := hi.rootbLt
  names := hi.names
  held v E sl T hE hl hsl hT := hi.held v E sl T hE hl (by rw [h] at hsl; exact hsl) hT
  pkgs v sl T hsl hT := hi.pkgs v sl T (by rw [h] at hsl; exact hsl) hT
  armed v E sl hE hsl := (hi.armed v E sl hE (by rw [h] at hsl; exact hsl)).keep fun _ _ _ dep _ =>
    (RootKeep.of_st (r := dep.root) h hb).vkeep hb
  shares v E sl T hE hsl hown hT := (hi.shares v E sl T hE (by rw [h] at hsl; exact hsl) hown hT).grow hb
  blocks := hB

/-- A3.2's second cut: **the invariant of the slots over another store that
    keeps only the blocks the slots reach through payloads that are read**
    (`rdBlk`; what a lock's payload reaches may be gone).  The slots' facts
    read only those: they are carried to the store with every lock's payload
    left out, swept from the slots there, and grown to `m'`.  (`m` itself
    with the locks' payloads left out need not be a heap: a view reads its
    lock's payload.) -/
theorem MInv.regrow {m m' : Mem} {Γ : Ctx} (hi : MInv m Γ) (h : m'.st = m.st) (hh : HeapOK m')
    (hnv : m.nv ≤ m'.nv)
    (hb : ∀ k bl, m.blk k = some bl → Reached m.vals (rdBlk m.blk) k → ∃ bl', m'.blk k = some bl' ∧ BlkKeep bl bl')
    (hB : BlocksIn m') : MInv m' Γ := by
  let mb : Mem := { m with blk := rdBlk m.blk }
  let ms : Mem := mb.sweep
  have hb1 : BlkLe m.blk mb.blk := BlkLe.rdBlk m.blk
  have hst2 : m'.st = ms.st := h
  have hb2 : BlkLe ms.blk m'.blk := by
    intro k bl hk
    obtain ⟨hk1, hr⟩ := Mem.sweep_blk.mp hk
    obtain ⟨bl0, hk0, rfl⟩ := rdBlk_some.mp hk1
    obtain ⟨bl', h1, h2⟩ := hb k bl0 hk0 hr
    refine ⟨bl', h1, ?_⟩
    obtain ⟨hty, hkd, ha⟩ := h2
    refine ⟨by rw [hty, Blk.rdOnly_ty], by rw [hkd, Blk.rdOnly_kind], fun hl => ?_⟩
    rw [Blk.rdOnly_kind] at hl
    rw [ha hl]
    obtain ⟨t, kd, p⟩ := bl0
    cases kd with
    | lock => exact absurd rfl hl
    | arc => rfl
    | view => rfl
  have hR : ∀ v, mb.vals v → mb.vals v := fun _ h => h
  have hslot : ∀ x sl, m.st x = some sl → mb.st x = some sl := fun _ _ h => h
  exact {
    dom := fun v => by rw [h]; exact hi.dom v
    slot := fun v E hv => by
      obtain ⟨sl, hsl, hok, hs⟩ := hi.slot v E hv
      exact ⟨sl, by rw [h]; exact hsl, hok,
        ((hs.grow (m := m) (m' := mb) rfl hb1).sweep hR (Kept.of_slot hR (hslot v sl hsl))).grow hst2 hb2⟩
    heap := hh
    nvSt := fun v hv => by rw [h] at hv; exact Nat.lt_of_lt_of_le (hi.nvSt v hv) hnv
    noInout := hi.noInout
    wf := hi.wf
    rootbLive := hi.rootbLive
    rootbLt := hi.rootbLt
    names := hi.names
    held := fun v E sl T hE hl hsl hT => hi.held v E sl T hE hl (by rw [h] at hsl; exact hsl) hT
    pkgs := fun v sl T hsl hT => hi.pkgs v sl T (by rw [h] at hsl; exact hsl) hT
    armed := fun v E sl hE hsl => by
      have hsl0 : m.st v = some sl := by rw [h] at hsl; exact hsl
      have h1 : ArmOK mb E sl := (hi.armed v E sl hE hsl0).keep fun _ _ _ dep _ =>
        (RootKeep.of_st (m := m) (m' := mb) (r := dep.root) rfl hb1).vkeep hb1
      exact (h1.sweep hR (Kept.of_slot hR (hslot v sl hsl0))).keep fun _ _ _ dep _ =>
        (RootKeep.of_st (r := dep.root) hst2 hb2).vkeep hb2
    shares := fun v E sl T hE hsl hown hT => by
      have hsl0 : m.st v = some sl := by rw [h] at hsl; exact hsl
      exact (((hi.shares v E sl T hE hsl0 hown hT).grow (m' := mb) hb1).sweep
        (Kept.of_slot hR (hslot v sl hsl0) T hT)).grow hb2
    blocks := hB }

/-- What a right-hand side hands to the binding that takes it. -/
structure RhsOut (m1 : Mem) (Γ1 : Ctx) (E : Entry) (v : Val) (o : Bool) : Prop where
  own    : o = E.mode.ownSlot
  mode   : E.mode = .own ∨ E.mode = .bor
  live   : E.live = true
  tyok   : E.ty.ok = true
  wf     : E.ty ≠ .int → ∀ r ∈ roots E.vdeps, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true
  valOwn : E.mode = .own → E.ty.owning = true ∧ WFv E.ty v ∧ ViewsOK m1 E.ty v E.held ∧
             v.ids.Nodup ∧ (∀ i ∈ v.ids, m1.alloc i = true ∧ i < m1.nid) ∧
             (∀ x U, OwnedAt m1 x U → ∀ i ∈ v.ids, i ∉ U.ids) ∧ SelfFree v ∧
             -- A3.1: ... and no block's payload holds its addresses
             (∀ i ∈ v.ids, ¬ PayAddr m1 i)
  valBor : E.mode = .bor → ValOK m1 E.ty v E.path E.held
  names  : (E.ty ≠ .int ∨ E.mode = .rootb) → NameOK Γ1 E
  held   : NamesIn v E.held
  pkgs   : PkgsOK v
  /-- A3.1: an owned value's shares name live blocks. -/
  shares : E.mode.ownSlot = true → SharesOK m1 E.ty v

/-- The context and memory after a right-hand side, and how they relate to
    before. -/
structure RhsPost (m m1 : Mem) (Γ Γ1 : Ctx) (F : List Var) : Prop where
  inv   : MInv m1 Γ1
  nv    : m1.nv = m.nv
  nid   : m.nid ≤ m1.nid
  dom   : ∀ x, (m1.st x).isSome = (m.st x).isSome
  frz   : ∀ x ∈ F, m1.st x = m.st x
  rootb : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → Γ1 p = some Ep
  cdom  : ∀ x, (Γ1 x).isSome = (Γ x).isSome
  cmode : ∀ x E1, Γ1 x = some E1 → ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode ∧ E1.ty = E0.ty
  /-- A2-drop.2: a right-hand side gives no `letd` binding a new view. -/
  dkeep : DKeep Γ Γ1 []
  /-- A3.1: a right-hand side keeps every block (`arcNew` adds one). -/
  blk   : BlkLe m.blk m1.blk

/-- What a right-hand side hands over does not depend on whether its
    entry runs a destructor (A2-drop.2). -/
theorem RhsOut.setDtor {m1 : Mem} {Γ1 : Ctx} {E : Entry} {v : Val} {o : Bool}
    (h : RhsOut m1 Γ1 E v o) (b c : Bool) : RhsOut m1 Γ1 { E with dtor := b, dbind := c } v o :=
  ⟨h.own, h.mode, h.live, h.tyok, h.wf, h.valOwn, h.valBor, h.names, h.held, h.pkgs, h.shares⟩

/-- ... nor on whether it records an owned value as viewing more memory, of
    bound roots, than the value does (`HeldUp`). -/
theorem RhsOut.widen {m1 : Mem} {Γ1 : Ctx} {E : Entry} {v : Val} {o : Bool}
    (h : RhsOut m1 Γ1 E v o) (hmo : E.mode = .own) {H : List Dep} (hH : HeldUp Γ1 E H) :
    RhsOut m1 Γ1 { E with held := H } v o := by
  have hos : E.mode.ownSlot = true := by rw [hmo]; rfl
  have hv1 : ({ E with held := H } : Entry).vdeps = H := by simp [Entry.vdeps, hos]
  refine ⟨h.own, h.mode, h.live, h.tyok, fun ht r hr => ?_, fun hm => ?_, fun hb => ?_,
    fun hn => (h.names hn).widen hmo hH, h.held.mono hH.1, h.pkgs, h.shares⟩
  · rw [hv1] at hr
    obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
    exact hH.root hmo (h.wf ht) d hd
  · obtain ⟨a, b, c, d, e, f, g⟩ := h.valOwn hm
    exact ⟨a, b, c.mono hH.1, d, e, f, g⟩
  · have hb' : E.mode = .bor := hb
    rw [hmo] at hb'; cases hb'

/-! #### A3.5b: subsumption between closure classes

A closure taken at a class above its own (`RhsT.moveUp`, `RhsT.copyUp`) is the
value it was: what the invariant asks of it at the new class it had at the old
one.  The class is read only by `Cross.Fits` (monotone, `Cross.Fits.mono`) and
by where an environment may hold views (`ViewIn.pkg`: at `any` only) or shares
(`ArcIn.pkg`: where `q.shares`), and an environment that fits a class below holds
none of what that class excludes. -/

theorem WFv.up {ms : List Nat} {q q' : Cross} {v : Val} (h : WFv (.fn ms q) v) (hle : q.Le q') :
    WFv (.fn ms q') v := by
  cases h with | pkg hw hq => exact .pkg hw (hq.mono hle)

theorem ValOK.up {m : Mem} {ms : List Nat} {q q' : Cross} {v : Val} {P H : List Dep}
    (h : ValOK m (.fn ms q) v P H) (hle : q.Le q') : ValOK m (.fn ms q') v P H := by
  cases h with | pkg hx hq => exact .pkg hx (hq.mono hle)

theorem ViewsOK.up {m : Mem} {ms : List Nat} {q q' : Cross} {v : Val} {H : List Dep}
    (hw : WFv (.fn ms q) v) (h : ViewsOK m (.fn ms q) v H) : ViewsOK m (.fn ms q') v H := by
  intro s w hin
  cases hin with
  | pkg hin' =>
    cases q with
    | any => exact h s w (.pkg hin')
    | _ =>
      cases hw with
      | pkg _ hq => exact absurd hin'.holdsView (by rw [(hq.1 rfl).1]; simp)

theorem SharesOK.up {m : Mem} {ms : List Nat} {q q' : Cross} {v : Val}
    (hw : WFv (.fn ms q) v) (h : SharesOK m (.fn ms q) v) : SharesOK m (.fn ms q') v := by
  cases hw with
  | pkg _ hq => exact SharesOK.mk_pkg (h.pkg' hq)

/-- What a right-hand side makes, taken at a class above its own. -/
theorem RhsOut.up {m1 : Mem} {Γ1 : Ctx} {E : Entry} {v : Val} {o : Bool} {ms : List Nat} {q q' : Cross}
    (h : RhsOut m1 Γ1 E v o) (hty : E.ty = .fn ms q) (hle : q.Le q') :
    RhsOut m1 Γ1 { E with ty := .fn ms q' } v o := by
  have hni : E.ty ≠ .int := by rw [hty]; simp
  refine ⟨h.own, h.mode, h.live, rfl, fun _ => h.wf hni, fun hm => ?_, fun hb => ?_,
    fun _ => h.names (Or.inl hni), h.held, h.pkgs, fun hos => ?_⟩
  · obtain ⟨_, hw, hv, h1, h2, h3, h4, h5⟩ := h.valOwn hm
    rw [hty] at hw hv
    exact ⟨rfl, hw.up hle, hv.up hw, h1, h2, h3, h4, h5⟩
  · have := h.valBor hb
    rw [hty] at this
    exact this.up hle
  · have hm : E.mode = .own := by
      rcases h.mode with hm | hm
      · exact hm
      · have : E.mode.ownSlot = true := hos
        rw [hm] at this; cases this
    have hw := (h.valOwn hm).2.1
    have hs := h.shares hos
    rw [hty] at hw hs
    exact hs.up hw

theorem RhsPost.same {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) : RhsPost m m Γ Γ F :=
  ⟨hi, rfl, Nat.le_refl _, fun _ => rfl, fun _ _ => rfl, fun _ _ h _ => h, fun _ => rfl,
    fun _ E1 h => ⟨E1, h, rfl, rfl⟩, DKeep.refl Γ [], BlkLe.refl _⟩

/-! ### What values capture by name -/

theorem namesL_append (es fs : List Val) : namesL (es ++ fs) = namesL es ++ namesL fs := by
  induction es with
  | nil => simp [namesL]
  | cons e es ih => simp [namesL, ih, List.append_assoc]

theorem names_elem {t : Ty} {c d : Nat} {es : List Val} {e : Val} (he : e ∈ es) :
    ∀ x ∈ e.names, x ∈ (Val.node t c d es).names := by
  intro x hx
  simp only [Val.names]
  induction es with
  | nil => cases he
  | cons a as ih =>
    simp only [namesL, List.mem_append]
    rcases List.mem_cons.mp he with rfl | h
    · exact Or.inl hx
    · exact Or.inr (ih h)

theorem names_lendOf : (v : Val) → ∀ x ∈ (lendOf v).names, x ∈ v.names
  | .int _ => fun _ h => h
  | .node .. => fun _ h => by simp [lendOf, Val.names] at h
  | .href _ => fun _ h => h
  | .view .. => fun _ h => h
  | .pair a b => fun x h => by
    simp only [lendOf, Val.names, List.mem_append] at h ⊢
    exact h.imp (names_lendOf a x) (names_lendOf b x)
  | .inl a => fun x h => by simp only [lendOf, Val.names] at h ⊢; exact names_lendOf a x h
  | .inr a => fun x h => by simp only [lendOf, Val.names] at h ⊢; exact names_lendOf a x h
  | .pkg fs te ms a cs => fun x h => by
    simp only [lendOf, Val.names, List.mem_append] at h ⊢
    exact h.imp id (names_lendOf a x)
  | .arc _ _ => fun _ h => h
  | .lk _ => fun _ h => h
  | .cell _ => fun _ h => by simp [lendOf, Val.names] at h

theorem sub_lendOf : (v : Val) → ∀ {w}, Sub w (lendOf v) → ∃ w0, Sub w0 v ∧ lendOf w0 = w
  | .int _, _, h => by
    rcases h.cases' with h | ⟨e, hc, _⟩
    · exact ⟨_, Sub.refl _, h.symm⟩
    · simp only [lendOf] at hc; cases hc
  | .node .., w, h => by
    rcases h.cases' with h | ⟨e, hc, _⟩
    · exact ⟨_, Sub.refl _, h.symm⟩
    · simp only [lendOf] at hc; cases hc
  | .href _, _, h => by
    rcases h.cases' with h | ⟨e, hc, _⟩
    · exact ⟨_, Sub.refl _, h.symm⟩
    · simp only [lendOf] at hc; cases hc
  | .view .., _, h => by
    rcases h.cases' with h | ⟨e, hc, _⟩
    · exact ⟨_, Sub.refl _, h.symm⟩
    · simp only [lendOf] at hc; cases hc
  | .arc _ _, _, h => by
    rcases h.cases' with h | ⟨e, hc, _⟩
    · exact ⟨_, Sub.refl _, h.symm⟩
    · simp only [lendOf] at hc; cases hc
  | .lk _, _, h => by
    rcases h.cases' with h | ⟨e, hc, _⟩
    · exact ⟨_, Sub.refl _, h.symm⟩
    · simp only [lendOf] at hc; cases hc
  | .cell _, _, h => by
    rcases h.cases' with h | ⟨e, hc, _⟩
    · exact ⟨_, Sub.refl _, h.symm⟩
    · simp only [lendOf] at hc; cases hc
  | .pair a b, w, h => by
    rcases h.cases' with h | ⟨e, hc, hs⟩
    · exact ⟨_, Sub.refl _, h.symm⟩
    · simp only [lendOf] at hc
      cases hc with
      | fst => obtain ⟨w0, h0, rfl⟩ := sub_lendOf a hs; exact ⟨w0, Sub.fst h0, rfl⟩
      | snd => obtain ⟨w0, h0, rfl⟩ := sub_lendOf b hs; exact ⟨w0, Sub.snd h0, rfl⟩
  | .inl a, w, h => by
    rcases h.cases' with h | ⟨e, hc, hs⟩
    · exact ⟨_, Sub.refl _, h.symm⟩
    · simp only [lendOf] at hc
      cases hc with
      | inl => obtain ⟨w0, h0, rfl⟩ := sub_lendOf a hs; exact ⟨w0, Sub.inl h0, rfl⟩
  | .inr a, w, h => by
    rcases h.cases' with h | ⟨e, hc, hs⟩
    · exact ⟨_, Sub.refl _, h.symm⟩
    · simp only [lendOf] at hc
      cases hc with
      | inr => obtain ⟨w0, h0, rfl⟩ := sub_lendOf a hs; exact ⟨w0, Sub.inr h0, rfl⟩
  | .pkg fs te ms a cs, w, h => by
    rcases h.cases' with h | ⟨e, hc, hs⟩
    · exact ⟨_, Sub.refl _, h.symm⟩
    · simp only [lendOf] at hc
      cases hc with
      | pkg => obtain ⟨w0, h0, rfl⟩ := sub_lendOf a hs; exact ⟨w0, Sub.pkg h0, rfl⟩

theorem NamesIn.sub {T T' : Val} {H : List Dep} (h : NamesIn T H)
    (hn : ∀ c ∈ T'.names, c ∈ T.names) : NamesIn T' H := fun c hc => h c (hn c hc)

theorem NamesIn.lendOf {T : Val} {H : List Dep} (h : NamesIn T H) : NamesIn (lendOf T) H :=
  h.sub (names_lendOf T)

theorem NamesIn.nil {T : Val} (H : List Dep) (hn : T.names = []) : NamesIn T H := by
  intro c hc; rw [hn] at hc; cases hc

theorem PkgsOK.sub {T T' : Val} (h : PkgsOK T) (hs : Sub T' T) : PkgsOK T' :=
  fun fs te ms e cs h' => h fs te ms e cs (h'.trans hs)

theorem PkgsOK.lendOf {T : Val} (h : PkgsOK T) : PkgsOK (lendOf T) := by
  intro fs te ms e cs hs
  obtain ⟨w0, h0, hw⟩ := sub_lendOf T hs
  cases w0 with
  | pkg fs0 te0 ms0 e0 cs0 =>
    simp only [A2.lendOf, Val.pkg.injEq] at hw
    obtain ⟨rfl, rfl, rfl, rfl, rfl⟩ := hw
    obtain ⟨hnd, hmd, hdis⟩ := h _ _ _ _ _ h0
    exact ⟨hnd, hmd, fun c hc c' hc' => hdis c hc c' (names_lendOf e0 c' hc')⟩
  | _ => simp [A2.lendOf] at hw

/-- A value with no closure inside. -/
theorem PkgsOK.leaf {T : Val} (hT : ∀ e, ¬ Child e T) (hp : ∀ fs te ms e cs, T ≠ .pkg fs te ms e cs) :
    PkgsOK T := by
  intro fs te ms e cs hs
  rcases hs.cases' with h | ⟨e', hc, _⟩
  · exact absurd h.symm (hp _ _ _ _ _)
  · exact absurd hc (hT e')

theorem DepsNamed.sub {Γ : Ctx} {a b : List Dep} (h : DepsNamed Γ a) (hs : b ⊆ a) : DepsNamed Γ b :=
  fun d hd => h d (hs hd)

theorem DepsNamed.append {Γ : Ctx} {a b : List Dep} (h1 : DepsNamed Γ a) (h2 : DepsNamed Γ b) :
    DepsNamed Γ (a ++ b) := by
  intro d hd
  rcases List.mem_append.mp hd with h | h
  · exact h1 d h
  · exact h2 d h

theorem DepsNamed.nil (Γ : Ctx) : DepsNamed Γ [] := fun _ h => by cases h

theorem NameOK.mono {Γ : Ctx} {E E' : Entry} (h : NameOK Γ E) (hs : E'.vdeps ⊆ E.vdeps) : NameOK Γ E' :=
  fun d hd => h d (hs hd)

theorem NameOK.held {Γ : Ctx} {E : Entry} (h : NameOK Γ E) : DepsNamed Γ E.held :=
  h.sub fun _ hd => List.mem_append_right _ hd

theorem NameOK.path {Γ : Ctx} {E : Entry} (h : NameOK Γ E) (ho : E.mode.ownSlot = false) :
    DepsNamed Γ E.path :=
  h.sub fun _ hd => by simp only [Entry.vdeps, ho]; exact List.mem_append_left _ hd

/-- A borrow of `y` (other than by name) depends by name on what `y`'s own
    path does. -/
theorem derive_named {Γ : Ctx} {y : Var} {E : Entry} (h : NameOK Γ E) {k : Kind}
    (hk : k.isName = false) : DepsNamed Γ (derive y E k) := by
  unfold derive
  split
  · intro d hd b t hkd
    simp only [List.mem_singleton] at hd; subst hd
    exfalso
    rcases rootKind_cases E.ty k with h' | ⟨rfl, h'⟩ <;> simp_all [Kind.isName]
  · rename_i hr
    have ho : E.mode.ownSlot = false := by cases hm : E.mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
    intro d hd b t hkd
    obtain ⟨d0, hd0, rfl⟩ := List.mem_map.mp hd
    exact h.path ho d0 hd0 b t (comp_name hkd hk)

theorem elemE_named {Γ : Ctx} {y : Var} {E : Entry} (h : NameOK Γ E) (t : Ty) :
    NameOK Γ (elemE y E t) := by
  cases t with
  | int => show DepsNamed Γ ([] ++ []); exact DepsNamed.nil Γ
  | slice s => show DepsNamed Γ (E.held ++ E.held); exact h.held.append h.held
  | vec s => show DepsNamed Γ (derive y E .inner ++ E.held); exact (derive_named h rfl).append h.held
  | prod a b => show DepsNamed Γ (derive y E .inner ++ E.held); exact (derive_named h rfl).append h.held
  | sum a b => show DepsNamed Γ (derive y E .inner ++ E.held); exact (derive_named h rfl).append h.held
  | fn ms => show DepsNamed Γ (derive y E .inner ++ E.held); exact (derive_named h rfl).append h.held
  | arc a => show DepsNamed Γ (derive y E .inner ++ E.held); exact (derive_named h rfl).append h.held
  | lk a => show DepsNamed Γ (derive y E .inner ++ E.held); exact (derive_named h rfl).append h.held
  | cell a => show DepsNamed Γ (derive y E .inner ++ E.held); exact (derive_named h rfl).append h.held
  | dtor f a => show DepsNamed Γ (derive y E .inner ++ E.held); exact (derive_named h rfl).append h.held

theorem projDeps_named {Γ : Ctx} {y : Var} {E : Entry} (h : NameOK Γ E) : DepsNamed Γ (projDeps y E) := by
  unfold projDeps
  split
  · intro d hd b t hkd; simp only [List.mem_singleton] at hd; subst hd; cases hkd
  · split
    · intro d hd b t hkd; simp only [List.mem_singleton] at hd; subst hd; cases hkd
    · rename_i ho _; exact h.path (by simpa using ho)

/-- What an entry holds by name stays so in a context whose bindings keep
    their types and modes, and those that are live and hold nothing stay so. -/
theorem NameOK.transport {Γ Γ' : Ctx} {E E' : Entry} (h : NameOK Γ E)
    (hΓ : ∀ r Er, r ∈ roots E'.vdeps → Γ r = some Er → Er.live = true → Er.held = [] →
      Er.mode.ownSlot = true → ∃ Er', Γ' r = some Er' ∧ Er'.live = true ∧ Er'.held = [] ∧ Er'.ty = Er.ty ∧ Er'.mode = Er.mode)
    (hs : E'.vdeps ⊆ E.vdeps) : NameOK Γ' E' := by
  intro d hd b t hk
  obtain ⟨Er, hEr, hl, hh, ht, ho, hc⟩ := h d (hs hd) b t hk
  obtain ⟨Er', hEr', hl', hh', ht', hm'⟩ := hΓ _ _ (List.mem_map_of_mem hd) hEr hl hh ho
  exact ⟨Er', hEr', hl', hh', by rw [ht', ht], by rw [hm']; exact ho, by rw [hm']; exact hc⟩

theorem names_child {x T : Val} (h : Child x T) : ∀ c ∈ x.names, c ∈ T.names := by
  intro c hc
  cases h with
  | elem he => exact names_elem he c hc
  | fst => simp only [Val.names]; exact List.mem_append_left _ hc
  | snd => simp only [Val.names]; exact List.mem_append_right _ hc
  | inl => simp only [Val.names]; exact hc
  | inr => simp only [Val.names]; exact hc
  | pkg => simp only [Val.names]; exact List.mem_append_right _ hc

theorem names_sub {x T : Val} (h : Sub x T) : ∀ c ∈ x.names, c ∈ T.names := by
  induction h with
  | refl => exact fun c hc => hc
  | child he _ ih => exact fun c hc => names_elem he c (ih c hc)
  | fst _ ih => intro c hc; simp only [Val.names]; exact List.mem_append_left _ (ih c hc)
  | snd _ ih => intro c hc; simp only [Val.names]; exact List.mem_append_right _ (ih c hc)
  | inl _ ih => intro c hc; simp only [Val.names]; exact ih c hc
  | inr _ ih => intro c hc; simp only [Val.names]; exact ih c hc
  | pkg _ ih => intro c hc; simp only [Val.names]; exact List.mem_append_right _ (ih c hc)

theorem namesL_mem {es : List Val} {c : Var × PMode × Ty} (h : c ∈ namesL es) : ∃ e ∈ es, c ∈ e.names := by
  induction es with
  | nil => cases h
  | cons a as ih =>
    simp only [namesL, List.mem_append] at h
    rcases h with h | h
    · exact ⟨a, List.mem_cons_self .., h⟩
    · obtain ⟨e, he, hc⟩ := ih h; exact ⟨e, List.mem_cons_of_mem _ he, hc⟩

/-- A binding captured by name is captured by some closure in the value. -/
theorem names_pkg : (T : Val) → ∀ c ∈ T.names, ∃ fs te ms e cs, Sub (.pkg fs te ms e cs) T ∧ c ∈ cs
  | .int _, c, h => by simp [Val.names] at h
  | .href _, c, h => by simp [Val.names] at h
  | .view .., c, h => by simp [Val.names] at h
  | .node t c0 d es, c, h => by
    simp only [Val.names] at h
    obtain ⟨e, he, hc⟩ := namesL_mem h
    obtain ⟨fs, te, ms, e', cs, hs, hcs⟩ := names_pkg e c hc
    exact ⟨fs, te, ms, e', cs, Sub.child he hs, hcs⟩
  | .pair a b, c, h => by
    simp only [Val.names, List.mem_append] at h
    rcases h with h | h
    · obtain ⟨fs, te, ms, e', cs, hs, hcs⟩ := names_pkg a c h; exact ⟨fs, te, ms, e', cs, Sub.fst hs, hcs⟩
    · obtain ⟨fs, te, ms, e', cs, hs, hcs⟩ := names_pkg b c h; exact ⟨fs, te, ms, e', cs, Sub.snd hs, hcs⟩
  | .inl a, c, h => by
    simp only [Val.names] at h
    obtain ⟨fs, te, ms, e', cs, hs, hcs⟩ := names_pkg a c h; exact ⟨fs, te, ms, e', cs, Sub.inl hs, hcs⟩
  | .inr a, c, h => by
    simp only [Val.names] at h
    obtain ⟨fs, te, ms, e', cs, hs, hcs⟩ := names_pkg a c h; exact ⟨fs, te, ms, e', cs, Sub.inr hs, hcs⟩
  | .pkg fs te ms a cs, c, h => by
    simp only [Val.names, List.mem_append] at h
    rcases h with h | h
    · exact ⟨fs, te, ms, a, cs, Sub.refl _, h⟩
    · obtain ⟨fs', te', ms', e', cs', hs, hcs⟩ := names_pkg a c h
      exact ⟨fs', te', ms', e', cs', Sub.pkg hs, hcs⟩

/-- How a value's closures capture by name: each binding is read or changed. -/
theorem PkgsOK.mode {T : Val} (h : PkgsOK T) {c : Var × PMode × Ty} (hc : c ∈ T.names) :
    c.2.1 = .inp ∨ ∃ b, c.2.1 = .inout b ∧ b ≠ .none := by
  obtain ⟨fs, te, ms, e, cs, hs, hcs⟩ := names_pkg T c hc
  exact (h fs te ms e cs hs).2.1 c hcs

theorem own_named {Γ : Ctx} {t : Ty} {D : List Dep} (h : DepsNamed Γ D) :
    NameOK Γ ⟨t, .own, true, [], D, false, false⟩ :=
  fun d hd => h d (by simpa [Entry.vdeps, Mode.ownSlot] using hd)

theorem PkgsOK.elem {t : Ty} {c d : Nat} {es : List Val} {e : Val} (h : PkgsOK (.node t c d es))
    (he : e ∈ es) : PkgsOK e :=
  h.sub (Sub.child he (Sub.refl _))

/-- A3.5b: a value of a type that holds no view holds only Send packages,
    each capturing nothing by name (it used to hold none). -/
theorem WFv.noView_pkg {τ : Ty} {v : Val} (hw : WFv τ v) (hhv : τ.holdsView = false) {fs : List Nat}
    {te : Ty} {ms : List Nat} {e : Val} {cs : List (Var × PMode × Ty)} (hs : Sub (.pkg fs te ms e cs) v) :
    cs = [] := by
  induction hw with
  | int => cases hs
  | view => cases hs
  | node _ ih =>
    cases hs with
    | child he h => exact ih _ he (by simpa [Ty.holdsView] using hhv) h
  | pair _ _ iha ihb =>
    simp only [Ty.holdsView, Bool.or_eq_false_iff] at hhv
    cases hs with
    | fst h => exact iha hhv.1 h
    | snd h => exact ihb hhv.2 h
  | inl _ ih => simp only [Ty.holdsView, Bool.or_eq_false_iff] at hhv; cases hs with | inl h => exact ih hhv.1 h
  | inr _ ih => simp only [Ty.holdsView, Bool.or_eq_false_iff] at hhv; cases hs with | inr h => exact ih hhv.2 h
  | pkg _ hq ih =>
    obtain ⟨hv, _, hcs⟩ := hq.send hhv
    cases hs with
    | refl => exact hcs
    | pkg h => exact ih hv h
  | arc _ _ => cases hs
  | lk => cases hs
  | cell => cases hs
  | dtor _ _ ih => exact ih hhv hs

/-- ... so its packages are well formed (`PkgsOK`): none captures anything. -/
theorem WFv.pkgsOK_noView {τ : Ty} {v : Val} (hw : WFv τ v) (hhv : τ.holdsView = false) : PkgsOK v := by
  intro fs te ms e cs hs
  rw [hw.noView_pkg hhv hs]
  simp

/-- A3.1: a payload's packages are well formed (A3.5b: it holds Sync ones). -/
theorem MInv.pay_pkgs {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {k : Nat} {bl : Blk} (hk : m.blk k = some bl)
    {n : Val} (hs : Sub n bl.rd) : PkgsOK n := by
  obtain ⟨_, hhv, hw, _⟩ := hi.blocks k bl hk
  intro fs te ms e cs hp
  rcases Blk.sub_rd hs with ⟨_, q, hq, hs'⟩ | rfl
  · exact (hw q hq).1.pkgsOK_noView hhv _ _ _ _ _ (hp.trans hs')
  · cases hp

/-- A3.5's third cut: no payload its holders read holds a cell share: a lock
    block's is read by no one, and an `arc` block's and a view's are of a type
    that holds none (`MInv.blocks`).  So a cell share lent out of memory is
    lent out of a slot's tree. -/
theorem MInv.noCellPay {m : Mem} {Γ : Ctx} (hi : MInv m Γ) (k : Nat) : ¬ InPay m (.cell k) := by
  rintro ⟨k', bl, hk, hs⟩
  obtain ⟨_, _, hpay, hkind⟩ := hi.blocks k' bl hk
  have hrd : bl.rd = .int 0 ∨ ∃ p, bl.pay = some p ∧ bl.rd = p ∧ bl.kind ≠ .lock := by
    obtain ⟨ty, kd, pay⟩ := bl
    cases kd <;> cases pay <;> simp [Blk.rd, Blk.tree]
  rcases hrd with h | ⟨p, hp, h, hnl⟩
  · rw [h] at hs; cases hs
  · rw [h] at hs
    rcases hkind with hl | hnc
    · exact hnl hl
    · exact (hpay p hp).1.noCell_hasCell hnc hs

/-- A3.5's third cut: a cell share a borrowed value holds lands through one of
    the value's dependencies (a borrowed value holds no node: its cell shares
    are at its top). -/
theorem valOK_cell_sub {m : Mem} {k : Nat} {τ : Ty} {w : Val} {P H : List Dep}
    (hok : ValOK m τ w P H) (hs : Sub (.cell k) w) : ∃ dep ∈ P ++ H, CellLanded m dep k := by
  induction hok with
  | int => cases hs
  | href _ => cases hs
  | view _ => cases hs
  | arc _ _ _ _ => cases hs
  | lk _ => cases hs
  | cell _ hl =>
    cases hs
    obtain ⟨dep, hd, hla⟩ := hl
    exact ⟨dep, List.mem_append_left _ hd, hla⟩
  | pair _ _ ihx ihy =>
    cases hs with
    | fst hs => obtain ⟨dep, hd, rest⟩ := ihx hs; exact ⟨dep, append_assoc_sub hd, rest⟩
    | snd hs => obtain ⟨dep, hd, rest⟩ := ihy hs; exact ⟨dep, append_assoc_sub hd, rest⟩
  | inl _ ih =>
    cases hs with
    | inl hs => obtain ⟨dep, hd, rest⟩ := ih hs; exact ⟨dep, append_assoc_sub hd, rest⟩
  | inr _ ih =>
    cases hs with
    | inr hs => obtain ⟨dep, hd, rest⟩ := ih hs; exact ⟨dep, append_assoc_sub hd, rest⟩
  | pkg _ _ ih =>
    cases hs with
    | pkg hs => obtain ⟨dep, hd, rest⟩ := ih hs; exact ⟨dep, append_envDeps_sub hd, rest⟩
  | dtor _ ih => exact ih hs

/-- One step back along a live borrow's dependencies: the cell share it holds
    is in an owned slot's tree, or at the top of a borrowed parameter it
    depends on. -/
theorem MInv.cell_step {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {v : Var} {E : Entry} {w : Val} {k : Nat}
    (hv : Γ v = some E) (hl : E.live = true) (hsl : m.st v = some ⟨false, some w⟩) (hs : Sub (.cell k) w) :
    OwnedCell m k ∨ ∃ r Er u, r ∈ roots E.vdeps ∧ Γ r = some Er ∧ Er.mode = .rootb ∧
      m.st r = some ⟨false, some u⟩ ∧ Sub (.cell k) u := by
  obtain ⟨sl, hsl', _, hso, _, hbor⟩ := hi.slot v E hv
  rw [hsl] at hsl'; cases hsl'
  have hos : E.mode.ownSlot = false := by simpa using hso.symm
  obtain ⟨w', hw', hok⟩ := hbor hos hl
  cases hw'
  obtain ⟨dep, hd, n0, hr, hlk⟩ := valOK_cell_sub hok hs
  have hnint : E.ty ≠ .int := by
    intro h; rw [h] at hok; obtain ⟨_, rfl⟩ := valOK_int.mp hok; cases hs
  have hdv : dep.root ∈ roots E.vdeps := by
    simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.mem_map]
    exact ⟨dep, hd, rfl⟩
  obtain ⟨Er, hEr, hroot⟩ := hi.wf.live v E hv hl (Or.inl hnint) dep.root hdv
  rcases hr with ⟨T, hT, ht⟩ | ⟨u, c, hu, ht, hn⟩ | ⟨u, d, o', l, hu, ht, hn⟩ | ⟨u, k', q, hu, ht, rfl⟩ |
    ⟨u, k', hu, ht, rfl⟩
  · exact .inl ⟨dep.root, T, hT, hlk.sub.trans ht.sub⟩
  · rcases hn with ⟨x, T, hx, hsx, _⟩ | ⟨kb, bl, hkb, hsb, _⟩
    · exact .inl ⟨x, T, hx, hlk.sub.trans hsx⟩
    · exact absurd ⟨kb, bl, hkb, hlk.sub.trans hsb⟩ (hi.noCellPay k)
  · rcases hn with ⟨x, T, hx, hsx, _⟩ | ⟨kb, bl, hkb, hsb, _⟩
    · exact .inl ⟨x, T, hx, hlk.sub.trans hsx⟩
    · exact absurd ⟨kb, bl, hkb, hlk.sub.trans hsb⟩ (hi.noCellPay k)
  · have := lands_arc hlk; cases this
  · have he := lands_cell hlk
    cases he
    obtain ⟨slr, hslr, _, hsor, _, _⟩ := hi.slot dep.root Er hEr
    have hrb : Er.mode = .rootb := by
      rw [hu] at hslr; cases hslr
      cases hme : Er.mode with
      | own => rw [hme] at hsor; simp [Mode.ownSlot] at hsor
      | inout b => exact absurd hme (hi.noInout _ Er b hEr)
      | rootb => rfl
      | bor => rw [hme] at hroot; simp [Mode.isRoot] at hroot
    exact .inr ⟨dep.root, Er, u, hdv, hEr, hrb, hu, ht.sub⟩

/-- A borrowed parameter that holds a cell share has an owner of it in the
    store: back along its dependencies, which are earlier bindings
    (`rootbLt`), to an owned tree. -/
theorem MInv.rootb_cell {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {k : Nat} :
    ∀ (r : Var) {Er : Entry} {u : Val}, Γ r = some Er → Er.mode = .rootb →
      m.st r = some ⟨false, some u⟩ → Sub (.cell k) u → OwnedCell m k := by
  intro r
  induction r using Nat.strongRecOn with
  | _ r ih =>
  intro Er u hr hrb hu hs
  rcases hi.cell_step hr (hi.rootbLive r Er hr hrb) hu hs with h | ⟨r', Er', u', hr'd, hr', hrb', hu', hs'⟩
  · exact h
  · exact ih r' (hi.rootbLt r Er hr hrb r' hr'd) hr' hrb' hu' hs'

/-- **A3.5's third cut: a live borrow of a library handle has an owner of it in
    the store.**  A borrow depends on its owner, and a move or a drop of the
    owner kills it, so while it is live its cell share lands, through its
    dependencies, in an owned slot's tree (`CellLanded`, the way `HrefAt`
    lands a lent `Vec`): the owner's, or the owner a borrowed parameter's
    argument is (frozen for the call).  So the crossing check counts owners
    only: a slot left behind that holds no owner holds no live borrow. -/
theorem MInv.cell_owned {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {v : Var} {E : Entry} {o : Bool} {w : Val}
    {k : Nat} (hv : Γ v = some E) (hl : E.live = true) (hsl : m.st v = some ⟨o, some w⟩)
    (hs : Sub (.cell k) w) : OwnedCell m k := by
  cases o with
  | true => exact ⟨v, w, hsl, hs⟩
  | false =>
    rcases hi.cell_step hv hl hsl hs with h | ⟨r, Er, u, _, hr, hrb, hu, hs'⟩
    · exact h
    · exact hi.rootb_cell r hr hrb hu hs'

theorem MInv.nodeAt_pkgs {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {c : Nat} {n : Val} (h : NodeAt m c n) :
    PkgsOK n := by
  rcases h with ⟨x, T, hx, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
  · exact (hi.pkgs x _ T hx rfl).sub hs
  · exact hi.pay_pkgs hk hs

theorem MInv.dataAt_pkgs {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {d : Nat} {n : Val} (h : DataAt m d n) :
    PkgsOK n := by
  rcases h with ⟨x, T, hx, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
  · exact (hi.pkgs x _ T hx rfl).sub hs
  · exact hi.pay_pkgs hk hs

theorem MInv.vecOf_pkgs {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {t : Ty} {c d : Nat}
    {es : List Val} (h : VecOf m y t c d es) : PkgsOK (.node t c d es) := by
  rcases h.2.2 with h | ⟨_, h⟩
  · exact hi.pkgs y _ _ h rfl
  · exact hi.nodeAt_pkgs h

theorem elemE_held_sub (y : Var) (E : Entry) (t : Ty) : (elemE y E t).held ⊆ E.held := by
  cases t <;> simp [elemE, intE]

theorem elemE_held (y : Var) (E : Entry) {t : Ty} (ht : t ≠ .int) : (elemE y E t).held = E.held := by
  cases t <;> simp_all [elemE]

/-- A value whose type holds no views captures nothing by name, lent or not. -/
theorem NamesIn.noView {t : Ty} {e : Val} (hw : WFv t e) (ht : t.holdsView = false) (H : List Dep) :
    NamesIn (A2.lendOf e) H := by
  intro x hx
  have := names_lendOf e x hx
  rw [hw.names_nil ht] at this; cases this

theorem intE_out {m : Mem} {Γ : Ctx} (n : Nat) : RhsOut m Γ intE (.int n) false where
  shares _ := SharesOK.of_noArc rfl
  own := rfl
  mode := Or.inr rfl
  live := rfl
  tyok := rfl
  wf h := absurd rfl h
  valOwn h := by simp [intE] at h
  valBor _ := .int
  names h := by
    rcases h with h | h
    · exact absurd rfl h
    · cases h
  held := NamesIn.nil _ rfl
  pkgs := PkgsOK.leaf (fun _ h => by cases h) (fun _ _ _ _ _ h => by cases h)

theorem wf_held {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) (hnint : E.ty ≠ .int) : ∀ r ∈ roots E.held,
    ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
  intro r hr
  refine hi.wf y E hy hl (Or.inl hnint) r ?_
  simp only [roots, Entry.vdeps, List.map_append, List.mem_append] at hr ⊢
  exact Or.inr hr

theorem wf_path {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) (hnint : E.ty ≠ .int) (hm : E.mode.ownSlot = false) : ∀ r ∈ roots E.path,
    ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
  intro r hr
  refine hi.wf y E hy hl (Or.inl hnint) r ?_
  simp only [roots, Entry.vdeps, hm, Bool.false_eq_true, ↓reduceIte, List.map_append,
    List.mem_append] at hr ⊢
  exact Or.inl hr

theorem wf_derive {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) (hnint : E.ty ≠ .int) (k : Kind) : ∀ r ∈ roots (derive y E k),
    ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
  intro r hr
  unfold derive at hr
  cases h : E.mode.isRoot with
  | true =>
    simp only [h, ↓reduceIte, roots, List.map_cons, List.map_nil, List.mem_singleton] at hr
    subst hr; exact ⟨E, hy, h⟩
  | false =>
    simp only [h, Bool.false_eq_true, ↓reduceIte, roots, List.map_map, List.mem_map,
      Function.comp] at hr
    obtain ⟨dep, hd, rfl⟩ := hr
    have hm : E.mode.ownSlot = false := by cases hm : E.mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
    exact wf_path hi hy hl hnint hm dep.root (List.mem_map_of_mem hd)

theorem wf_append {Γ : Ctx} {a b : List Dep}
    (ha : ∀ r ∈ roots a, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true)
    (hb : ∀ r ∈ roots b, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) :
    ∀ r ∈ roots (a ++ b), ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
  intro r hr
  simp only [roots, List.map_append, List.mem_append] at hr
  rcases hr with hr | hr
  · exact ha r hr
  · exact hb r hr

theorem bor_vdeps (E : Entry) (h : E.mode = .bor) : E.vdeps = E.path ++ E.held := by
  simp [Entry.vdeps, h, Mode.ownSlot]

theorem slot_val_eq {m : Mem} {y : Var} {o : Bool} {v w : Val}
    (h1 : m.st y = some ⟨o, some v⟩) (h2 : m.st y = some ⟨o, some w⟩) : v = w := by
  rw [h1] at h2; cases h2; rfl

theorem out_copyBor {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {v : Val}
    (hy : Γ y = some E) (hl : E.live = true) (hm : E.mode = .bor)
    (hv : m.st y = some ⟨false, some v⟩) : RhsOut m Γ E v false where
  shares h := by rw [hm] at h; cases h
  own := by rw [hm]; rfl
  mode := Or.inr hm
  live := hl
  tyok := hi.tyok hy
  wf hn := hi.wf y E hy hl (Or.inl hn)
  valOwn h := by rw [hm] at h; cases h
  valBor _ := by
    obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
    rw [slot_val_eq hv hw]; exact hok
  names hn := hi.names y E hy hl hn
  held := hi.held y E _ v hy hl hv rfl
  pkgs := hi.pkgs y _ v hv rfl

/-- A borrow of a whole binding `y` (`var` of a borrowed parameter, or
    `borrow`): its handle, or its view if it is a slice. -/
theorem out_borrowWhole {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {v : Val}
    (hy : Γ y = some E) (hl : E.live = true) (_hnown : E.mode.ownSlot = false ∨ ∃ t, E.ty = .vec t)
    (hv : m.st y = some ⟨false, some v⟩ ∨
      ∃ t c d es, m.st y = some ⟨true, some (.node t c d es)⟩ ∧ v = .href c)
    (hroot : E.mode = .rootb ∨ (E.mode = .own ∧ ∃ t, E.ty = .vec t)) :
    RhsOut m Γ ⟨E.ty, .bor, true, derive y E .self, E.held, false, false⟩ v false where
  shares h := nomatch h
  own := rfl
  mode := Or.inr rfl
  live := rfl
  tyok := hi.tyok (E := E) hy
  wf hn := by
    rw [bor_vdeps _ rfl]
    exact wf_append (wf_derive hi hy hl hn _) (wf_held (E := E) hi hy hl hn)
  valOwn h := by cases h
  valBor _ := by
    have hisroot : E.mode.isRoot = true := by
      rcases hroot with h | ⟨h, _⟩ <;> rw [h] <;> rfl
    show ValOK m E.ty v (derive y E .self) E.held
    cases hty : E.ty with
    | int =>
      rcases hroot with h | ⟨_, t, ht⟩
      · obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl (by rw [h]; rfl)
        rcases hv with hv | ⟨_, _, _, _, hv, _⟩
        · rw [slot_val_eq hv hw]; rw [hty] at hok; obtain ⟨n, rfl⟩ := valOK_int.mp hok; exact .int
        · rw [hv] at hw; cases hw
      · rw [ht] at hty; cases hty
    | vec t =>
      obtain ⟨c, d, es, hvec, hw, hvs, hroot', _, hns, hshv⟩ := hi.vec_node hy hl hty
      have hvc : v = .href c := by
        obtain ⟨_, _, hvec⟩ := hvec
        rcases hv with hv | ⟨_, _, _, _, hv, rfl⟩ <;> rcases hvec with h | ⟨h, _⟩ <;>
          rw [hv] at h <;> cases h <;> rfl
      refine valOK_vec.mpr ⟨c, hvc, ?_⟩
      exact derive_hrefAt (hroot' ·) (fun h => by rw [h] at hisroot; cases hisroot)
        (by rw [hty]; rfl) (Or.inl ⟨rfl, rfl⟩) hw hvs hns hshv
    | slice t =>
      obtain ⟨d, o, l, c, es, hs, _, _, hlen, hw, hroot', _⟩ := hi.slice_node hy hl hty
      have hvv : v = .view d o l := by
        rcases hv with hv | ⟨_, _, _, _, hv, _⟩ <;> rw [hv] at hs <;> cases hs; rfl
      refine valOK_slice.mpr ⟨d, o, l, hvv, ?_⟩
      have hder : derive y E .self = derive y E .view := by
        unfold derive; rw [hisroot, hty]; rfl
      rw [hder]
      exact derive_viewAt (hroot' ·) (fun h => by rw [h] at hisroot; cases hisroot)
        (by decide) (by rw [hty]; rfl) (Or.inr (Or.inl ⟨rfl, rfl⟩)) hlen hw
    | prod a b =>
      rcases hroot with h | ⟨_, t, ht⟩
      · obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl (by rw [h]; rfl)
        rcases hv with hv | ⟨_, _, _, _, hv, _⟩
        · rw [slot_val_eq hv hw]
          have hd : derive y E .self = [⟨y, .view⟩] := by simp [derive, hisroot, hty, rootKind]
          rw [hd, ← hty]; exact valOK_via hw hok (Top.refl _) (by simp)
        · rw [hv] at hw; cases hw
      · rw [ht] at hty; cases hty
    | sum a b =>
      rcases hroot with h | ⟨_, t, ht⟩
      · obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl (by rw [h]; rfl)
        rcases hv with hv | ⟨_, _, _, _, hv, _⟩
        · rw [slot_val_eq hv hw]
          have hd : derive y E .self = [⟨y, .view⟩] := by simp [derive, hisroot, hty, rootKind]
          rw [hd, ← hty]; exact valOK_via hw hok (Top.refl _) (by simp)
        · rw [hv] at hw; cases hw
      · rw [ht] at hty; cases hty
    | fn ms =>
      rcases hroot with h | ⟨_, t, ht⟩
      · obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl (by rw [h]; rfl)
        rcases hv with hv | ⟨_, _, _, _, hv, _⟩
        · rw [slot_val_eq hv hw]
          have hd : derive y E .self = [⟨y, .view⟩] := by simp [derive, hisroot, hty, rootKind]
          rw [hd, ← hty]; exact valOK_via hw hok (Top.refl _) (by simp)
        · rw [hv] at hw; cases hw
      · rw [ht] at hty; cases hty
    | arc a =>
      rcases hroot with h | ⟨_, t, ht⟩
      · obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl (by rw [h]; rfl)
        rcases hv with hv | ⟨_, _, _, _, hv, _⟩
        · rw [slot_val_eq hv hw]
          rw [hty] at hok
          cases hok with
          | arc h1 h2 h3 _ =>
            have hd : derive y E .self = [⟨y, .self⟩] := by simp [derive, hisroot, hty, rootKind]
            rw [hd]
            exact .arc h1 h2 h3 ⟨_, List.mem_singleton_self _,
              Or.inl ⟨_, Or.inr (Or.inr (Or.inr (Or.inl ⟨_, _, _, hw, Top.refl _, rfl⟩))), Or.inl ⟨rfl, rfl⟩⟩⟩
        · rw [hv] at hw; cases hw
      · rw [ht] at hty; cases hty
    | lk a =>
      rcases hroot with h | ⟨_, t, ht⟩
      · obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl (by rw [h]; rfl)
        rcases hv with hv | ⟨_, _, _, _, hv, _⟩
        · rw [slot_val_eq hv hw]; rw [hty] at hok
          cases hok with
          | lk h1 => exact .lk h1
        · rw [hv] at hw; cases hw
      · rw [ht] at hty; cases hty
    | cell a =>
      rcases hroot with h | ⟨_, t, ht⟩
      · obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl (by rw [h]; rfl)
        rcases hv with hv | ⟨_, _, _, _, hv, _⟩
        · rw [slot_val_eq hv hw]; rw [hty] at hok
          cases hok with
          | cell h1 _ =>
            have hd : derive y E .self = [⟨y, .self⟩] := by simp [derive, hisroot, hty, rootKind]
            rw [hd]
            exact .cell h1 ⟨_, List.mem_singleton_self _, _,
              Or.inr (Or.inr (Or.inr (Or.inr ⟨_, _, hw, Top.refl _, rfl⟩))), Or.inl ⟨rfl, rfl⟩⟩
        · rw [hv] at hw; cases hw
      · rw [ht] at hty; cases hty
    | dtor f a =>
      rcases hroot with h | ⟨_, t, ht⟩
      · obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl (by rw [h]; rfl)
        rcases hv with hv | ⟨_, _, _, _, hv, _⟩
        · rw [slot_val_eq hv hw]
          have hd : derive y E .self = [⟨y, .view⟩] := by simp [derive, hisroot, hty, rootKind]
          rw [hd, ← hty]; exact valOK_via hw hok (Top.refl _) (by simp)
        · rw [hv] at hw; cases hw
      · rw [ht] at hty; cases hty
  names hn := by
    have h := hi.names y E hy hl (hn.imp id fun h => by cases h)
    show DepsNamed Γ (derive y E .self ++ E.held); exact (derive_named h rfl).append h.held
  held := by
    rcases hv with hv | ⟨_, _, _, _, _, rfl⟩
    · exact hi.held y E _ v hy hl hv rfl
    · exact NamesIn.nil _ rfl
  pkgs := by
    rcases hv with hv | ⟨_, _, _, _, _, rfl⟩
    · exact hi.pkgs y _ v hv rfl
    · exact PkgsOK.leaf (fun _ h => by cases h) (fun _ _ _ _ _ h => by cases h)

/-- A value stored in memory, lent out: every node at its top (the ones
    lending hands out) is reached through `P`, every view it stores is valid
    through `H`. (A3.1: so is every share at its top.) -/
theorem lend_valOK' {m : Mem} {H : List Dep} {τ : Ty} {e : Val} (hw : WFv τ e) (hpk : PkgsOK e) :
    ∀ {P : List Dep},
    (∀ t c d es, Top (.node t c d es) e →
      ∃ dep ∈ P, Landed m dep (.node t c d es)) →
    (∀ k q, Top (.arc k q) e → ∃ dep ∈ P, ArcLanded m dep (.arc k q)) →
    (∀ k, Top (.cell k) e → ∃ dep ∈ P, CellLanded m dep k) →
    ViewsOK m τ e H → NamesIn e H → SharesOK m τ e → (∀ s, τ = .slice s → ViewsOK m τ e P) →
    ValOK m τ (lendOf e) P H := by
  revert hpk
  -- what is reached through `P` is reached through `P ++ X`
  have up : ∀ {P X : List Dep} {n : Val}, (∃ dep ∈ P, Landed m dep n) → ∃ dep ∈ P ++ X, Landed m dep n :=
    fun ⟨dep, hd, rest⟩ => ⟨dep, List.mem_append_left _ hd, rest⟩
  have upa : ∀ {P X : List Dep} {n : Val}, (∃ dep ∈ P, ArcLanded m dep n) →
      ∃ dep ∈ P ++ X, ArcLanded m dep n :=
    fun ⟨dep, hd, rest⟩ => ⟨dep, List.mem_append_left _ hd, rest⟩
  have upc : ∀ {P X : List Dep} {k : Nat}, (∃ dep ∈ P, CellLanded m dep k) →
      ∃ dep ∈ P ++ X, CellLanded m dep k :=
    fun ⟨dep, hd, rest⟩ => ⟨dep, List.mem_append_left _ hd, rest⟩
  induction hw generalizing H with
  | int => intro _ P _ _ _ _ _ _ _; exact .int
  | arc hwp hvf _ => intro _ P _ ha _ _ _ hsh _; exact .arc hsh.here hwp hvf (ha _ _ (Top.refl _))
  | lk => intro _ P _ ha _ _ _ hsh _; exact .lk hsh.lk
  | cell => intro _ P _ _ hc _ _ hsh _; exact .cell hsh.cell (hc _ (Top.refl _))
  | @view t d o l =>
    intro _ P _ _ _ _ _ _ hs
    obtain ⟨d', o', l', hv, dep, hd, ha⟩ := hs t rfl t _ ViewIn.here
    cases hv
    exact .view ⟨dep, hd, ha⟩
  | @node t c d es hes =>
    intro _ P hn _ _ hv hnm hsh _
    obtain ⟨dep, hd, hla⟩ := hn t c d es (Top.refl _)
    exact .href ⟨dep, hd, d, es, hla, WFv.node hes, hv, hnm, hsh⟩
  | @pair a b v w _ _ ihv ihw =>
    intro hpk P hn ha hc hvs hnm hsh _
    refine .pair (ihv (hpk.sub (Sub.fst (Sub.refl _))) (fun t c d es hs => up (hn t c d es (Top.fst hs)))
      (fun k q hs => upa (ha k q (Top.fst hs))) (fun k hs => upc (hc k (Top.fst hs))) (fun s x hin => hvs s x
      (ViewIn.fst hin)) ((hnm.sub fun x hx => by simp only [Val.names]; exact List.mem_append_left _ hx)) hsh.fst (fun s _ => ?_))
      (ihw (hpk.sub (Sub.snd (Sub.refl _))) (fun t c d es hs => up (hn t c d es (Top.snd hs)))
      (fun k q hs => upa (ha k q (Top.snd hs))) (fun k hs => upc (hc k (Top.snd hs)))
      (fun s x hin => hvs s x (ViewIn.snd hin))
      ((hnm.sub fun x hx => by simp only [Val.names]; exact List.mem_append_right _ hx)) hsh.snd (fun s _ => ?_))
    · exact ViewsOK.mono (List.subset_append_right _ _) (fun s x hin => hvs s x (ViewIn.fst hin))
    · exact ViewsOK.mono (List.subset_append_right _ _) (fun s x hin => hvs s x (ViewIn.snd hin))
  | @inl a b v _ ihv =>
    intro hpk P hn ha hc hvs hnm hsh _
    exact .inl (ihv (hpk.sub (Sub.inl (Sub.refl _))) (fun t c d es hs => up (hn t c d es (Top.inl hs)))
      (fun k q hs => upa (ha k q (Top.inl hs))) (fun k hs => upc (hc k (Top.inl hs))) (fun s x hin => hvs s x (ViewIn.inl hin))
      ((hnm.sub fun x hx => by simp only [Val.names]; exact hx)) hsh.inl
      (fun s _ => ViewsOK.mono (List.subset_append_right _ _) (fun s x hin => hvs s x (ViewIn.inl hin))))
  | @inr a b v _ ihv =>
    intro hpk P hn ha hc hvs hnm hsh _
    exact .inr (ihv (hpk.sub (Sub.inr (Sub.refl _))) (fun t c d es hs => up (hn t c d es (Top.inr hs)))
      (fun k q hs => upa (ha k q (Top.inr hs))) (fun k hs => upc (hc k (Top.inr hs))) (fun s x hin => hvs s x (ViewIn.inr hin))
      ((hnm.sub fun x hx => by simp only [Val.names]; exact hx)) hsh.inr
      (fun s _ => ViewsOK.mono (List.subset_append_right _ _) (fun s x hin => hvs s x (ViewIn.inr hin))))
  | @pkg fs te ms q v cs _ hq ihv =>
    intro hpk P hn ha hc hvs hnm hsh _
    -- what the environment holds by name is no change of one of this
    -- package's own captures (one captured again inside is only read)
    have hdis := (hpk fs te ms v cs (Sub.refl _)).2.2
    have hvr : ViewsOK m te v (envDeps cs H) :=
      ViewsOK.mono (readers_sub_envDeps cs H) (ViewsOK.readers (hvs.pkg hq))
    have hown : ∀ c' ∈ v.names, ownWriter cs (⟨c'.1, .name c'.2.1.bound c'.2.2⟩ : Dep) = false := by
      intro c' hc'
      simp only [ownWriter, Bool.and_eq_false_iff, bne_eq_false_iff_eq, Kind.bound]
      by_cases hin : c'.1 ∈ capRootsW cs
      · left
        simp only [capRootsW, List.mem_map, List.mem_filter, bne_iff_ne, ne_eq] at hin
        obtain ⟨c, ⟨hc, hcn⟩, hcc⟩ := hin
        rw [(hdis c hc c' hc' hcc).2]; rfl
      · right; simpa [List.contains_iff_mem] using hin
    exact .pkg (ihv (hpk.sub (Sub.pkg (Sub.refl _))) (fun t c d es hs => up (hn t c d es (Top.pkg hs)))
      (fun k q hs => upa (ha k q (Top.pkg hs))) (fun k hs => upc (hc k (Top.pkg hs))) hvr
      (fun c' hc' => mem_envDeps.mpr ⟨hnm c' (by simp only [Val.names]; exact List.mem_append_right _ hc'), hown c' hc'⟩)
      (hsh.pkg' hq) (fun s _ => ViewsOK.mono (List.subset_append_right _ _) hvr)) hq
  | @dtor f t v ho _ ih =>
    intro hpk P hn ha hc hvs hnm hsh _
    exact .dtor (ih hpk hn ha hc (ViewsOK.dtor_iff.mp hvs) hnm (SharesOK.dtor_iff.mp hsh)
      (fun s h => by subst h; simp [Ty.isStruct] at ho))

theorem lend_valOK {m : Mem} {H : List Dep} {τ : Ty} {e : Val} (hw : WFv τ e) (hpk : PkgsOK e) {P : List Dep}
    (hn : ∀ n, Sub n e → ∃ dep ∈ P, Landed m dep n)
    (hpc : ∀ k, ¬ InPay m (.cell k))
    (hv : ViewsOK m τ e H) (hnm : NamesIn e H) (hsh : SharesOK m τ e)
    (hs : ∀ s, τ = .slice s → ViewsOK m τ e P) :
    ValOK m τ (lendOf e) P H :=
  lend_valOK' hw hpk (fun _ _ _ _ ht => hn _ ht.sub)
    (fun _ _ ht => let ⟨d, hd, h⟩ := hn _ ht.sub; ⟨d, hd, h.arc⟩)
    (fun k ht => let ⟨d, hd, h⟩ := hn _ ht.sub; ⟨d, hd, CellLanded.of_landed h (hpc k)⟩) hv hnm hsh hs

theorem lands_rootKind_self (t : Ty) (n : Val) : Lands (rootKind t .self) n n := by
  rcases rootKind_cases t .self with h | ⟨_, h⟩ <;> rw [h]
  · exact Or.inl ⟨rfl, rfl⟩
  · exact Or.inr (Or.inl ⟨rfl, rfl⟩)

/-- What a borrowed struct holds is already lent: lending it again changes
    nothing. -/
theorem ValOK.lend {m : Mem} {τ : Ty} {v : Val} {P H : List Dep} (h : ValOK m τ v P H) : lendOf v = v := by
  induction h with
  | int => rfl
  | arc => rfl
  | lk => rfl
  | cell => rfl
  | href => rfl
  | view => rfl
  | pair _ _ ihx ihy => simp [lendOf, ihx, ihy]
  | inl _ ih => simp [lendOf, ih]
  | inr _ ih => simp [lendOf, ih]
  | pkg _ _ ih => simp [lendOf, ih]
  | dtor _ ih => exact ih

theorem elemE_mode (y : Var) (E : Entry) (t : Ty) : (elemE y E t).mode = .bor := by
  cases t <;> rfl

theorem out_at {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (hty : E.ty = .vec t)
    {t' : Ty} {c d n : Nat} {es : List Val} (hn : n < es.length) (hvec : VecOf m y t' c d es) :
    RhsOut m Γ (elemE y E t) (lendOf es[n]) false where
  shares h := by rw [elemE_mode] at h; cases h
  own := by rw [elemE_mode]; rfl
  mode := Or.inr (elemE_mode ..)
  live := by cases t <;> rfl
  tyok := by
    have := hi.tyok hy; rw [hty] at this
    cases t with
    | int => rfl
    | vec s => exact this
    | slice s => exact this
    | prod a b => exact this
    | sum a b => exact this
    | fn ms => exact this
    | arc a => exact this
    | lk a => exact this
    | cell a => exact this
    | dtor f a => exact this
  wf hn' := by
    rw [bor_vdeps _ (elemE_mode ..)]
    have hnint : E.ty ≠ .int := by rw [hty]; simp
    cases t with
    | int => exact absurd rfl hn'
    | slice s => exact wf_append (wf_held (E := E) hi hy hl hnint) (wf_held (E := E) hi hy hl hnint)
    | vec s => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | prod a b => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | sum a b => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | fn ms => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | arc a => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | lk a => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | cell a => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | dtor f a => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
  valOwn h := by rw [elemE_mode] at h; cases h
  valBor _ := by
    obtain ⟨c0, d0, es0, hvec0, hw, hvs, hroot, hbor, hns, hshv⟩ := hi.vec_node hy hl hty
    have heq := VecOf.unique hi.heap hvec0 hvec
    cases heq
    have hmem : es[n] ∈ es := List.getElem_mem hn
    have hwe : WFv t es[n] := hw.elem rfl hmem
    have hpke : PkgsOK es[n] := (hi.vecOf_pkgs hvec0).elem hmem
    generalize es[n] = e at hmem hwe hpke ⊢
    cases t with
    | int =>
      cases hwe with | int => exact .int
    | slice s =>
      cases hwe with
      | view =>
        obtain ⟨d', o', l', hv', dep, hd, ha⟩ := hvs s _ (ViewIn.child hmem ViewIn.here)
        cases hv'
        exact .view ⟨dep, hd, ha⟩
    | vec s =>
      cases hwe with
      | node hes =>
        rename_i c1 d1 es1
        exact .href (derive_hrefAt (hroot ·) hbor (by rw [hty]; rfl)
          (Lands.elem hmem) (WFv.node hes) (hvs.elem hmem) (hns.sub (names_elem hmem)) (hshv.elem hmem))
    | prod a b =>
      refine lend_valOK hwe hpke (fun n' hs => ?_) hi.noCellPay (hvs.elem hmem) (hns.sub (names_elem hmem))
        (hshv.elem hmem) (fun s h => by cases h)
      have hbor' : E.mode.isRoot = false → ∃ dep ∈ E.path, Landed m dep (.node (.prod a b) c d es) := fun h => hbor (by
        cases hm : E.mode <;> simp_all [Mode.isRoot])
      exact derive_lands (hroot ·) hbor' (Or.inr (Or.inr ⟨rfl, _, Child.elem hmem, hs⟩))
        (by rw [hty]; rfl)
    | sum a b =>
      refine lend_valOK hwe hpke (fun n' hs => ?_) hi.noCellPay (hvs.elem hmem) (hns.sub (names_elem hmem))
        (hshv.elem hmem) (fun s h => by cases h)
      have hbor' : E.mode.isRoot = false → ∃ dep ∈ E.path, Landed m dep (.node (.sum a b) c d es) := fun h => hbor (by
        cases hm : E.mode <;> simp_all [Mode.isRoot])
      exact derive_lands (hroot ·) hbor' (Or.inr (Or.inr ⟨rfl, _, Child.elem hmem, hs⟩))
        (by rw [hty]; rfl)
    | fn ms q =>
      refine lend_valOK hwe hpke (fun n' hs => ?_) hi.noCellPay (hvs.elem hmem) (hns.sub (names_elem hmem))
        (hshv.elem hmem) (fun s h => by cases h)
      have hbor' : E.mode.isRoot = false → ∃ dep ∈ E.path, Landed m dep (.node (.fn ms q) c d es) := fun h => hbor (by
        cases hm : E.mode <;> simp_all [Mode.isRoot])
      exact derive_lands (hroot ·) hbor' (Or.inr (Or.inr ⟨rfl, _, Child.elem hmem, hs⟩))
        (by rw [hty]; rfl)
    | arc a =>
      cases hwe with
      | arc hwp hvf =>
        have hbor' : E.mode.isRoot = false → ∃ dep ∈ E.path, Landed m dep (.node (.arc a) c d es) := fun h => hbor (by
          cases hm : E.mode <;> simp_all [Mode.isRoot])
        obtain ⟨d', hd', hla'⟩ := derive_lands (hroot ·) hbor' (Lands.elem hmem) (by rw [hty]; rfl)
        exact .arc (hshv.elem hmem).here hwp hvf ⟨d', hd', hla'.arc⟩
    | lk a =>
      cases hwe with
      | lk => exact .lk (hshv.elem hmem).lk
    | cell a =>
      cases hwe with
      | cell =>
        have hbor' : E.mode.isRoot = false → ∃ dep ∈ E.path, Landed m dep (.node (.cell a) c d es) := fun h => hbor (by
          cases hm : E.mode <;> simp_all [Mode.isRoot])
        obtain ⟨d', hd', hla'⟩ := derive_lands (hroot ·) hbor' (Lands.elem hmem) (by rw [hty]; rfl)
        exact .cell (hshv.elem hmem).cell ⟨d', hd', CellLanded.of_landed hla' (hi.noCellPay _)⟩
    | dtor f a =>
      refine lend_valOK hwe hpke (fun n' hs => ?_) hi.noCellPay (hvs.elem hmem) (hns.sub (names_elem hmem))
        (hshv.elem hmem) (fun s h => by cases h)
      have hbor' : E.mode.isRoot = false → ∃ dep ∈ E.path, Landed m dep (.node (.dtor f a) c d es) := fun h => hbor (by
        cases hm : E.mode <;> simp_all [Mode.isRoot])
      exact derive_lands (hroot ·) hbor' (Or.inr (Or.inr ⟨rfl, _, Child.elem hmem, hs⟩))
        (by rw [hty]; rfl)
  names hn := elemE_named (hi.names y E hy hl (Or.inl (by rw [hty]; simp))) t
  held := by
    obtain ⟨c0, d0, es0, hvec0, hw, _, _, _, hns, hshv⟩ := hi.vec_node hy hl hty
    have heq := VecOf.unique hi.heap hvec0 hvec
    cases heq
    have hmem : es[n] ∈ es := List.getElem_mem hn
    by_cases ht : t = .int
    · subst ht; exact NamesIn.noView (hw.elem rfl hmem) rfl _
    · rw [elemE_held _ _ ht]; exact (hns.sub (names_elem hmem)).lendOf
  pkgs := ((hi.vecOf_pkgs hvec).elem (List.getElem_mem hn)).lendOf

theorem out_view {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (hty : E.ty = .vec t) (hhv : t.holdsView = false)
    {t' : Ty} {c d : Nat} {es : List Val} (hvec : VecOf m y t' c d es) :
    RhsOut m Γ ⟨.slice t, .bor, true, derive y E .view, E.held, false, false⟩ (.view d 0 es.length) false where
  shares h := nomatch h
  own := rfl
  mode := Or.inr rfl
  live := rfl
  tyok := by
    have := hi.tyok hy; rw [hty] at this
    simpa [Ty.ok, hhv] using this
  wf hn' := by
    rw [bor_vdeps _ rfl]
    have hnint : E.ty ≠ .int := by rw [hty]; simp
    exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
  valOwn h := by cases h
  valBor _ := by
    obtain ⟨c0, d0, es0, hvec0, hw, _, hroot, hbor, hns, hshv⟩ := hi.vec_node hy hl hty
    have heq := VecOf.unique hi.heap hvec0 hvec
    cases heq
    refine .view (derive_viewAt (hroot ·) ?_ (by decide) (by rw [hty]; rfl)
      (Or.inr (Or.inl ⟨rfl, rfl⟩)) (by simp) hw)
    intro hb
    exact hbor hb
  names hn := by
    have h := hi.names y E hy hl (Or.inl (by rw [hty]; simp))
    show DepsNamed Γ (derive y E .view ++ E.held); exact (derive_named h rfl).append h.held
  held := NamesIn.nil _ rfl
  pkgs := PkgsOK.leaf (fun _ h => by cases h) (fun _ _ _ _ _ h => by cases h)

/-- A3.1's slices of shares: the node a slice views, found in memory, holds
    the shares its type says (an owned tree's, `MInv.shares`, or a frozen
    payload's, `MInv.blocks`). -/
theorem MInv.dataAt_shares {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {t : Ty} {c d : Nat} {es : List Val}
    (h : DataAt m d (.node t c d es)) : SharesOK m (.vec t) (.node t c d es) := by
  rcases h with ⟨x, T, hx, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
  · have hsome : (Γ x).isSome = true := by rw [hi.dom x, hx]; rfl
    obtain ⟨E, hE⟩ := Option.isSome_iff_exists.mp hsome
    obtain ⟨sl, hsl, _, hso⟩ := hi.slot x E hE
    rw [hx] at hsl; cases hsl
    obtain ⟨_, hwT, _⟩ := hso.2.1 hso.1.symm
    exact SharesOK.sub_node (hwT T rfl) (hi.shares x E _ T hE hx rfl rfl) hs
  · obtain ⟨_, _, hpay, _⟩ := hi.blocks k bl hk
    have hrd : bl.rd = .int 0 ∨ ∃ p, bl.pay = some p ∧ bl.rd = p := by
      obtain ⟨ty, kd, pay⟩ := bl
      cases kd <;> cases pay <;> simp [Blk.rd, Blk.tree]
    rcases hrd with h | ⟨p, hp, h⟩
    · rw [h] at hs; cases hs
    · rw [h] at hs
      exact SharesOK.sub_node (hpay p hp).1 (hpay p hp).2 hs

theorem out_sat {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (hty : E.ty = .slice t)
    {t' : Ty} {c d o l n : Nat} {es : List Val} (hn : o + n < es.length)
    (hv : m.st y = some ⟨false, some (.view d o l)⟩) (hda : DataAt m d (.node t' c d es)) :
    RhsOut m Γ (elemE y E t) (lendOf es[o + n]) false where
  shares h := by rw [elemE_mode] at h; cases h
  own := by rw [elemE_mode]; rfl
  mode := Or.inr (elemE_mode ..)
  live := by cases t <;> rfl
  tyok := by
    have := hi.tyok hy; rw [hty] at this
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at this
    cases t with
    | int => rfl
    | slice s => simp [Ty.holdsView] at this
    | _ => exact this.1
  wf hn' := by
    rw [bor_vdeps _ (elemE_mode ..)]
    have hnint : E.ty ≠ .int := by rw [hty]; simp
    cases t with
    | int => exact absurd rfl hn'
    | slice s => exact wf_append (wf_held (E := E) hi hy hl hnint) (wf_held (E := E) hi hy hl hnint)
    | vec s => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | prod a b => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | sum a b => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | fn ms => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | arc a => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | lk a => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | cell a => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | dtor f a => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
  valOwn h := by rw [elemE_mode] at h; cases h
  valBor _ := by
    obtain ⟨d0, o0, l0, c0, es0, hs0, hda0, _, _, hw, hroot, hbor⟩ := hi.slice_node hy hl hty
    rw [hv] at hs0; cases hs0
    have heq := dataAt_unique hi.heap hda0 hda
    cases heq
    have hshv : SharesOK m (.vec t) (.node t c d es) := hi.dataAt_shares hda0
    have hok := hi.tyok hy; rw [hty] at hok
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hok
    have hmem : es[o + n] ∈ es := List.getElem_mem hn
    have hwe : WFv t es[o + n] := hw.elem rfl hmem
    have hpke : PkgsOK es[o + n] := (hi.dataAt_pkgs hda).elem hmem
    generalize es[o + n] = e at hmem hwe hpke ⊢
    have hbor'' : E.mode.isRoot = false → ∃ dep ∈ E.path, Landed m dep (.node t c d es) := fun h => by
      have hb : E.mode = .bor := by cases hm : E.mode <;> simp_all [Mode.isRoot]
      obtain ⟨dep, hd, _, hla⟩ := hbor hb
      exact ⟨dep, hd, hla⟩
    cases t with
    | int =>
      cases hwe with | int => exact .int
    | slice s => simp [Ty.holdsView] at hok
    | vec s =>
      cases hwe with
      | node hes =>
        rename_i c1 d1 es1
        refine .href (derive_hrefAt (hroot ·) ?_ (by rw [hty]; rfl)
          (Lands.elem hmem) (WFv.node hes) (ViewsOK.none (by simpa [Ty.holdsView] using hok.2) _ _)
          (no_names (WFv.node hes) (by simpa [Ty.holdsView] using hok.2) _)
          (hshv.elem hmem))
        intro hb
        obtain ⟨dep, hd, _, hla⟩ := hbor hb
        exact ⟨dep, hd, hla⟩
    | prod a b =>
      refine lend_valOK hwe hpke (fun n' hs => ?_) hi.noCellPay
        (ViewsOK.none (by simpa [Ty.holdsView] using hok.2) _ _)
        (NamesIn.nil _ (hwe.names_nil (by simpa [Ty.holdsView] using hok.2)))
        (hshv.elem hmem) (fun s h => by cases h)
      exact derive_lands (hroot ·) hbor'' (Or.inr (Or.inr ⟨rfl, _, Child.elem hmem, hs⟩))
        (by rw [hty]; rfl)
    | sum a b =>
      refine lend_valOK hwe hpke (fun n' hs => ?_) hi.noCellPay
        (ViewsOK.none (by simpa [Ty.holdsView] using hok.2) _ _)
        (NamesIn.nil _ (hwe.names_nil (by simpa [Ty.holdsView] using hok.2)))
        (hshv.elem hmem) (fun s h => by cases h)
      exact derive_lands (hroot ·) hbor'' (Or.inr (Or.inr ⟨rfl, _, Child.elem hmem, hs⟩))
        (by rw [hty]; rfl)
    | fn ms q =>
      refine lend_valOK hwe hpke (fun n' hs => ?_) hi.noCellPay
        (ViewsOK.none (by simpa [Ty.holdsView] using hok.2) _ _)
        (NamesIn.nil _ (hwe.names_nil (by simpa [Ty.holdsView] using hok.2)))
        (hshv.elem hmem) (fun s h => by cases h)
      exact derive_lands (hroot ·) hbor'' (Or.inr (Or.inr ⟨rfl, _, Child.elem hmem, hs⟩))
        (by rw [hty]; rfl)
    | arc a =>
      cases hwe with
      | arc hwp hvf =>
        obtain ⟨d', hd', hla'⟩ := derive_lands (hroot ·) hbor'' (Lands.elem hmem) (by rw [hty]; rfl)
        exact .arc (hshv.elem hmem).here hwp hvf ⟨d', hd', hla'.arc⟩
    | lk a =>
      cases hwe with
      | lk => exact .lk (hshv.elem hmem).lk
    | cell a =>
      cases hwe with
      | cell =>
        obtain ⟨d', hd', hla'⟩ := derive_lands (hroot ·) hbor'' (Lands.elem hmem) (by rw [hty]; rfl)
        exact .cell (hshv.elem hmem).cell ⟨d', hd', CellLanded.of_landed hla' (hi.noCellPay _)⟩
    | dtor f a =>
      refine lend_valOK hwe hpke (fun n' hs => ?_) hi.noCellPay
        (ViewsOK.none (by simpa [Ty.holdsView] using hok.2) _ _)
        (NamesIn.nil _ (hwe.names_nil (by simpa [Ty.holdsView] using hok.2)))
        (hshv.elem hmem) (fun s h => by cases h)
      exact derive_lands (hroot ·) hbor'' (Or.inr (Or.inr ⟨rfl, _, Child.elem hmem, hs⟩))
        (by rw [hty]; rfl)
  names hn := elemE_named (hi.names y E hy hl (Or.inl (by rw [hty]; simp))) t
  held := by
    obtain ⟨d0, o0, l0, c0, es0, hs0, hda0, _, _, hw, _, _⟩ := hi.slice_node hy hl hty
    rw [hv] at hs0; cases hs0
    have heq := dataAt_unique hi.heap hda0 hda
    cases heq
    have hok := hi.tyok hy; rw [hty] at hok
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hok
    exact NamesIn.noView (hw.elem rfl (List.getElem_mem hn)) hok.2 _
  pkgs := ((hi.dataAt_pkgs hda).elem (List.getElem_mem hn)).lendOf

/-- A field read out of the struct `y`: what the field holds, lent. -/
theorem out_comp {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) (hnint : E.ty ≠ .int) {o : Bool} {T x : Val} (hv : m.st y = some ⟨o, some T⟩)
    (hc : Child x T) (htop : Top x T) {t : Ty} (htok : t.ok = true)
    (hown : WFv E.ty T → ViewsOK m E.ty T E.held → SharesOK m E.ty T →
      WFv t x ∧ ViewsOK m t x E.held ∧ SharesOK m t x)
    (hbor : ValOK m E.ty T E.path E.held → ValOK m t x (E.path ++ E.held) E.held) :
    RhsOut m Γ (projE y E t) (lendOf x) false := by
  have hint : t = .int ∨ projE y E t = ⟨t, .bor, true, projDeps y E ++ E.held, E.held, false, false⟩ := by
    cases t <;> simp [projE]
  -- what the field holds, valid as a borrow through `P`
  have key : ValOK m t (lendOf x) (projDeps y E ++ E.held) E.held := by
    rcases hi.mode_cases hy with hm | hm | hm
    · have hos : E.mode.ownSlot = true := by rw [hm]; rfl
      obtain ⟨T', hT', hwT, hvsT⟩ := hi.own_val hy hl hos
      rw [hT'] at hv; cases hv
      obtain ⟨hwx, hvx, hshx⟩ := hown hwT hvsT (hi.shares y E _ T hy hT' rfl rfl)
      have hpd : projDeps y E = [⟨y, .inner⟩] := by simp [projDeps, hos]
      refine lend_valOK hwx ((hi.pkgs y _ T hT' rfl).sub (hc.sub (Sub.refl _)))
        (fun n' hs => ⟨⟨y, .inner⟩, by simp [hpd], Or.inl ⟨T, Or.inl ⟨T, hT', Top.refl _⟩,
        Or.inr (Or.inr ⟨rfl, x, hc, hs⟩)⟩⟩) hi.noCellPay hvx ((hi.held y E _ T hy hl hT' rfl).sub (names_child hc))
        hshx (fun s _ => ?_)
      exact ViewsOK.mono (List.subset_append_right _ _) hvx
    · have hos : E.mode.ownSlot = false := by rw [hm]; rfl
      obtain ⟨T', hT', hok⟩ := hi.bor_val hy hl hos
      rw [hT'] at hv; cases hv
      have hpd : projDeps y E = [⟨y, .view⟩] := by simp [projDeps, hm, Mode.ownSlot]
      have hx := hbor hok
      rw [hpd, hx.lend]; exact valOK_via hT' hx htop (by simp)
    · have hos : E.mode.ownSlot = false := by rw [hm]; rfl
      obtain ⟨T', hT', hok⟩ := hi.bor_val hy hl hos
      rw [hT'] at hv; cases hv
      have hpd : projDeps y E = E.path := by simp [projDeps, hm, Mode.ownSlot]
      have hx := hbor hok
      rw [hpd, hx.lend]; exact hx
  rcases hint with rfl | heq
  · obtain ⟨n, hn⟩ := valOK_int.mp key
    simp only [projE]; rw [hn]; exact intE_out n
  · rw [heq]
    refine ⟨rfl, Or.inr rfl, rfl, htok, fun _ r hr => ?_, fun h => (by cases h), fun _ => key,
      fun _ => by
        have h := hi.names y E hy hl (Or.inl hnint)
        show DepsNamed Γ ((projDeps y E ++ E.held) ++ E.held)
        exact ((projDeps_named h).append h.held).append h.held,
      ((hi.held y E _ T hy hl hv rfl).sub (names_child hc)).lendOf,
      ((hi.pkgs y _ T hv rfl).sub (hc.sub (Sub.refl _))).lendOf, fun h => nomatch h⟩
    rw [bor_vdeps _ rfl] at hr
    refine wf_append (wf_append ?_ (wf_held hi hy hl hnint)) (wf_held hi hy hl hnint) r hr
    unfold projDeps
    split
    · intro r hr; simp [roots] at hr; subst hr
      exact ⟨E, hy, by cases hm : E.mode <;> simp_all [Mode.ownSlot, Mode.isRoot]⟩
    · split
      · intro r hr; simp [roots] at hr; subst hr
        exact ⟨E, hy, by simp_all [Mode.isRoot]⟩
      · rename_i hos _; exact wf_path hi hy hl hnint (by simpa using hos)

theorem out_fst {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) {a b : Ty} (hty : E.ty = .prod a b) {o : Bool} {v w : Val}
    (hv : m.st y = some ⟨o, some (.pair v w)⟩) : RhsOut m Γ (projE y E a) (lendOf v) false := by
  have hok := hi.tyok hy; rw [hty] at hok
  simp only [Ty.ok, Bool.and_eq_true] at hok
  refine out_comp hi hy hl (by rw [hty]; simp) hv Child.fst (Top.fst (Top.refl _)) hok.1 (fun hw hvs hsh => ?_) (fun h => ?_)
  · rw [hty] at hw hvs hsh; cases hw with
    | pair ha _ => exact ⟨ha, fun s x hin => hvs s x (ViewIn.fst hin), hsh.fst⟩
  · rw [hty] at h; obtain ⟨x, z, hxz, hx, _⟩ := valOK_prod.mp h; cases hxz; exact hx

theorem out_snd {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) {a b : Ty} (hty : E.ty = .prod a b) {o : Bool} {v w : Val}
    (hv : m.st y = some ⟨o, some (.pair v w)⟩) : RhsOut m Γ (projE y E b) (lendOf w) false := by
  have hok := hi.tyok hy; rw [hty] at hok
  simp only [Ty.ok, Bool.and_eq_true] at hok
  refine out_comp hi hy hl (by rw [hty]; simp) hv Child.snd (Top.snd (Top.refl _)) hok.2 (fun hw hvs hsh => ?_) (fun h => ?_)
  · rw [hty] at hw hvs hsh; cases hw with
    | pair _ hb => exact ⟨hb, fun s x hin => hvs s x (ViewIn.snd hin), hsh.snd⟩
  · rw [hty] at h; obtain ⟨x, z, hxz, _, hz⟩ := valOK_prod.mp h; cases hxz; exact hz

/-! ### A3.1: shares

A share owns nothing: its payload is the block's, which owns its addresses
(`BlkOwn`). -/

/-- A3.3: an `arc` share's block (an `arc` block or a view) holds the
    payload it carries, whose shares name blocks. -/
theorem MInv.arcBlk_shares {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {k : Nat} {t : Ty} {p : Val}
    (hk : ArcBlk (m.blk k) t p) : SharesOK m t p := by
  rcases hk with hk | hk <;> exact ((hi.blocks k _ hk).2.2.1 p rfl).2

/-- A share's block, through the binding that holds the share (an owner, or
    a borrow of it). -/
theorem MInv.arc_val {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {a : Var} {E : Entry} (ha : Γ a = some E)
    (hl : E.live = true) {t : Ty} (hty : E.ty = .arc t) {o : Bool} {k : Nat} {p : Val}
    (hv : m.st a = some ⟨o, some (.arc k p)⟩) :
    ArcBlk (m.blk k) t p ∧ WFv t p ∧ t.holdsView = false := by
  cases hos : E.mode.ownSlot with
  | true =>
    obtain ⟨T, hT, hwT, _⟩ := hi.own_val ha hl hos
    rw [hT] at hv; cases hv
    have hsh := hi.shares a E _ _ ha hT rfl rfl
    rw [hty] at hwT hsh
    cases hwT with
    | arc hwp hvf => exact ⟨hsh.here, hwp, hvf⟩
  | false =>
    obtain ⟨w, hw, hok⟩ := hi.bor_val ha hl hos
    rw [hw] at hv; cases hv
    rw [hty] at hok
    cases hok with
    | arc hk hwp hvf => exact ⟨hk, hwp, hvf⟩

/-- ... and the share itself: a live binding of type `arc t` holds one. -/
theorem MInv.arc_slot {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {a : Var} {E : Entry} (ha : Γ a = some E)
    (hl : E.live = true) {t : Ty} (hty : E.ty = .arc t) :
    ∃ o k p, m.st a = some ⟨o, some (.arc k p)⟩ := by
  cases hos : E.mode.ownSlot with
  | true =>
    obtain ⟨T, hT, hwT, _⟩ := hi.own_val ha hl hos
    rw [hty] at hwT
    cases hwT; exact ⟨_, _, _, hT⟩
  | false =>
    obtain ⟨w, hw, hok⟩ := hi.bor_val ha hl hos
    rw [hty] at hok
    cases hok; exact ⟨_, _, _, hw⟩

/-- A3.1: what lies in the payload of the share `a` holds lands through a
    share dependency of `a` (`derive a E .share`): `a`'s own if it is a
    root, which reaches memory (an owner, or a borrowed share, `RootNode`),
    or, for a borrow, one through what the share lands through. -/
theorem MInv.share_lands {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {a : Var} {E : Entry} (ha : Γ a = some E)
    (hl : E.live = true) {t : Ty} (hty : E.ty = .arc t) {o : Bool} {k : Nat} {p : Val}
    (hv : m.st a = some ⟨o, some (.arc k p)⟩) (hk : ArcBlk (m.blk k) t p) {n : Val}
    (hs : Sub n p) :
    ∃ dep ∈ derive a E .share, Landed m dep n := by
  have hin : InPay m n := by obtain ⟨bl, hbl, hrd⟩ := hk.rd; exact ⟨k, bl, hbl, hrd ▸ hs⟩
  unfold derive
  cases hr : E.mode.isRoot with
  | true =>
    simp only [↓reduceIte, List.mem_singleton, exists_eq_left]
    refine Or.inr ⟨by rw [hty]; rfl, ?_, hin⟩
    cases o with
    | true => exact RootMem.own hv
    | false => exact Or.inr ⟨_, Or.inr (Or.inr (Or.inr (Or.inl ⟨_, k, p, hv, Top.refl _, rfl⟩)))⟩
  | false =>
    simp only [Bool.false_eq_true, ↓reduceIte, List.mem_map]
    have hm : E.mode = .bor := by cases hm : E.mode <;> simp_all [Mode.isRoot]
    obtain ⟨w, hw, hok⟩ := hi.bor_val ha hl (by rw [hm]; rfl)
    rw [hv] at hw; cases hw
    rw [hty] at hok
    cases hok with
    | arc _ _ _ hla =>
      obtain ⟨dep, hd, hl'⟩ := hla
      refine ⟨_, ⟨dep, hd, rfl⟩, Or.inr ⟨?_, hl'.rootMem, hin⟩⟩
      show comp dep.kind .share = .share
      have := hl'.notName
      cases hk : dep.kind <;> simp_all [comp, Kind.isName]

/-- A share, owned: it holds nothing, and its block holds its payload. -/
theorem out_share {m : Mem} {Γ : Ctx} {t : Ty} {k : Nat} {p : Val} (htok : t.ok = true)
    (hvf : t.holdsView = false) (hwp : WFv t p) (hk : ArcBlk (m.blk k) t p) :
    RhsOut m Γ ⟨.arc t, .own, true, [], [], false, false⟩ (.arc k p) true where
  own := rfl
  mode := Or.inl rfl
  live := rfl
  tyok := by simp [Ty.ok, htok, hvf]
  wf _ r hr := by simp [roots, Entry.vdeps, Mode.ownSlot] at hr
  valOwn _ := ⟨rfl, .arc hwp hvf, ViewsOK.none (show (Ty.arc t).holdsView = false from hvf) _ _,
    List.nodup_nil, fun _ h => (nomatch h), fun _ _ _ _ h => (nomatch h), fun _ _ _ h => (by cases h),
    fun _ h => (nomatch h)⟩
  valBor h := nomatch h
  names _ := DepsNamed.nil _
  held := NamesIn.nil _ rfl
  pkgs := PkgsOK.leaf (fun _ h => by cases h) (fun _ _ _ _ _ h => by cases h)
  shares _ u k' p' ha := by cases ha; exact hk

/-- A3.2: a lock share, owned: it holds nothing, and its block is a lock
    block of its type. -/
theorem out_lkShare {m : Mem} {Γ : Ctx} {t : Ty} {k : Nat} (htok : t.ok = true)
    (hvf : t.holdsView = false) (hk : ∃ o, m.blk k = some ⟨t, .lock, o⟩) :
    RhsOut m Γ ⟨.lk t, .own, true, [], [], false, false⟩ (.lk k) true where
  own := rfl
  mode := Or.inl rfl
  live := rfl
  tyok := by simp [Ty.ok, htok, hvf]
  wf _ r hr := by simp [roots, Entry.vdeps, Mode.ownSlot] at hr
  valOwn _ := ⟨rfl, .lk, ViewsOK.none (show (Ty.lk t).holdsView = false from hvf) _ _,
    List.nodup_nil, fun _ h => (nomatch h), fun _ _ _ _ h => (nomatch h), fun _ _ _ h => (by cases h),
    fun _ h => (nomatch h)⟩
  valBor h := nomatch h
  names _ := DepsNamed.nil _
  held := NamesIn.nil _ rfl
  pkgs := PkgsOK.leaf (fun _ h => by cases h) (fun _ _ _ _ _ h => by cases h)
  shares _ u k' p' ha := by cases ha; exact hk

/-- A3.2: a lock share's block, through the binding that holds the share
    (an owner, or a borrow of it): a lock block of its type. -/
theorem MInv.lk_val {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {a : Var} {E : Entry} (ha : Γ a = some E)
    (hl : E.live = true) {t : Ty} (hty : E.ty = .lk t) {o : Bool} {k : Nat}
    (hv : m.st a = some ⟨o, some (.lk k)⟩) : ∃ ob, m.blk k = some ⟨t, .lock, ob⟩ := by
  cases hos : E.mode.ownSlot with
  | true =>
    obtain ⟨T, hT, _, _⟩ := hi.own_val ha hl hos
    rw [hT] at hv; cases hv
    have hsh := hi.shares a E _ _ ha hT rfl rfl
    rw [hty] at hsh
    exact hsh.lk
  | false =>
    obtain ⟨w, hw, hok⟩ := hi.bor_val ha hl hos
    rw [hw] at hv; cases hv
    rw [hty] at hok
    cases hok with
    | lk h => exact h

/-- ... and the share itself: a live binding of type `lk t` holds one. -/
theorem MInv.lk_slot {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {a : Var} {E : Entry} (ha : Γ a = some E)
    (hl : E.live = true) {t : Ty} (hty : E.ty = .lk t) :
    ∃ o k, m.st a = some ⟨o, some (.lk k)⟩ := by
  cases hos : E.mode.ownSlot with
  | true =>
    obtain ⟨T, hT, hwT, _⟩ := hi.own_val ha hl hos
    rw [hty] at hwT
    cases hwT; exact ⟨_, _, hT⟩
  | false =>
    obtain ⟨w, hw, hok⟩ := hi.bor_val ha hl hos
    rw [hty] at hok
    cases hok; exact ⟨_, _, hw⟩

/-- A3.2, `Locked_share a`: a new share of `a`'s lock block. -/
theorem out_lockClone {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {a : Var} {E : Entry} (ha : Γ a = some E)
    (hl : E.live = true) {t : Ty} (hty : E.ty = .lk t) {o : Bool} {k : Nat}
    (hv : m.st a = some ⟨o, some (.lk k)⟩) :
    RhsOut m Γ ⟨.lk t, .own, true, [], [], false, false⟩ (.lk k) true := by
  have hk := hi.lk_val ha hl hty hv
  have hok := hi.tyok ha; rw [hty] at hok
  simp only [Ty.ok, Bool.and_eq_true] at hok
  exact out_lkShare hok.1 (by simpa using hok.2) hk

/-- A3.5: a cell share, owned: it holds nothing, and names a lock block of
    its type. -/
theorem out_cellShare {m : Mem} {Γ : Ctx} {t : Ty} {k : Nat} (htok : t.ok = true)
    (hvf : t.holdsView = false) (hk : ∃ o, m.blk k = some ⟨t, .lock, o⟩) :
    RhsOut m Γ ⟨.cell t, .own, true, [], [], false, false⟩ (.cell k) true where
  own := rfl
  mode := Or.inl rfl
  live := rfl
  tyok := by simp [Ty.ok, htok, hvf]
  wf _ r hr := by simp [roots, Entry.vdeps, Mode.ownSlot] at hr
  valOwn _ := ⟨rfl, .cell, ViewsOK.none (show (Ty.cell t).holdsView = false from hvf) _ _,
    List.nodup_nil, fun _ h => (nomatch h), fun _ _ _ _ h => (nomatch h), fun _ _ _ h => (by cases h),
    fun _ h => (nomatch h)⟩
  valBor h := nomatch h
  names _ := DepsNamed.nil _
  held := NamesIn.nil _ rfl
  pkgs := PkgsOK.leaf (fun _ h => by cases h) (fun _ _ _ _ _ h => by cases h)
  shares _ u k' p' ha := by cases ha; exact hk

/-- A3.5: a cell share's block, through the binding that holds the share
    (A3.5's third cut: an owner, or a borrow of one, a lent cell share being
    the share): a lock block of its type. -/
theorem MInv.cell_val {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {a : Var} {E : Entry} (ha : Γ a = some E)
    (hl : E.live = true) {t : Ty} (hty : E.ty = .cell t) {o : Bool} {k : Nat}
    (hv : m.st a = some ⟨o, some (.cell k)⟩) : ∃ ob, m.blk k = some ⟨t, .lock, ob⟩ := by
  cases hos : E.mode.ownSlot with
  | true =>
    obtain ⟨T, hT, _, _⟩ := hi.own_val ha hl hos
    rw [hT] at hv; cases hv
    have hsh := hi.shares a E _ _ ha hT rfl rfl
    rw [hty] at hsh
    exact hsh.cell
  | false =>
    obtain ⟨w, hw, hok⟩ := hi.bor_val ha hl hos
    rw [hw] at hv; cases hv
    rw [hty] at hok
    cases hok with
    | cell h => exact h

/-- ... and the share itself: a live binding of type `cell t` holds one. -/
theorem MInv.cell_slot {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {a : Var} {E : Entry} (ha : Γ a = some E)
    (hl : E.live = true) {t : Ty} (hty : E.ty = .cell t) :
    ∃ o k, m.st a = some ⟨o, some (.cell k)⟩ := by
  cases hos : E.mode.ownSlot with
  | true =>
    obtain ⟨T, hT, hwT, _⟩ := hi.own_val ha hl hos
    rw [hty] at hwT
    cases hwT; exact ⟨_, _, hT⟩
  | false =>
    obtain ⟨w, hw, hok⟩ := hi.bor_val ha hl hos
    rw [hty] at hok
    cases hok; exact ⟨_, _, hw⟩

/-- A3.5, `PNCounter_share a`: a new share of `a`'s cell (A3.5's third cut:
    `a` an owner or a borrow, as the runtime copies a handle it was lent). -/
theorem out_cellClone {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {a : Var} {E : Entry} (ha : Γ a = some E)
    (hl : E.live = true) {t : Ty} (hty : E.ty = .cell t) {o : Bool} {k : Nat}
    (hv : m.st a = some ⟨o, some (.cell k)⟩) :
    RhsOut m Γ ⟨.cell t, .own, true, [], [], false, false⟩ (.cell k) true := by
  have hk := hi.cell_val ha hl hty hv
  have hok := hi.tyok ha; rw [hty] at hok
  simp only [Ty.ok, Bool.and_eq_true] at hok
  exact out_cellShare hok.1 (by simpa using hok.2) hk

/-- A3.6, a read of a module global: the share the store holds, of a block
    of the read's type (`GlobFits`); owned, it holds nothing. -/
theorem out_glob {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {t : Ty} (htok : t.ok = true) {v : Val}
    (hf : GlobFits m.blk t v) : RhsOut m Γ ⟨t, .own, true, [], [], false, false⟩ v true := by
  rcases hf with ⟨u, k, o, rfl, rfl, hk⟩ | ⟨u, k, p, rfl, rfl, hk⟩
  · simp only [Ty.ok, Bool.and_eq_true] at htok
    exact out_lkShare htok.1 (by simpa using htok.2) ⟨o, hk⟩
  · have hk' : ∃ kd, m.blk k = some ⟨u, kd, some p⟩ := by
      rcases hk with hk | hk
      · exact ⟨_, hk⟩
      · exact ⟨_, hk⟩
    obtain ⟨_, hk'⟩ := hk'
    obtain ⟨_, hvf, hpay, _⟩ := hi.blocks k _ hk'
    simp only [Ty.ok, Bool.and_eq_true] at htok
    exact out_share htok.1 hvf (hpay p rfl).1 hk

/-- A3.2/A3.5: the lock block a `withLock` checks out, through the share its
    binding holds (`Entry.lockOf`): a lock block of the payload's type. -/
theorem MInv.lockOf_val {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {a : Var} {E : Entry} (ha : Γ a = some E)
    (hl : E.live = true) {t : Ty} (hty : E.lockOf t) {k : Nat} (hv : LockAt m a k) :
    ∃ ob, m.blk k = some ⟨t, .lock, ob⟩ := by
  obtain ⟨o, hv | hv⟩ := hv
  · rcases hty with hty | hty
    · exact hi.lk_val ha hl hty hv
    · obtain ⟨o', k', hk'⟩ := hi.cell_slot ha hl hty
      rw [hk'] at hv; cases hv
  · rcases hty with hty | hty
    · obtain ⟨o', k', hk'⟩ := hi.lk_slot ha hl hty
      rw [hk'] at hv; cases hv
    · exact hi.cell_val ha hl hty hv

/-- ... and the share: a live binding `lockOf t` holds one. -/
theorem MInv.lockOf_slot {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {a : Var} {E : Entry} (ha : Γ a = some E)
    (hl : E.live = true) {t : Ty} (hty : E.lockOf t) : ∃ k, LockAt m a k := by
  rcases hty with hty | hty
  · obtain ⟨o, k, hv⟩ := hi.lk_slot ha hl hty
    exact ⟨k, o, Or.inl hv⟩
  · obtain ⟨o, k, hv⟩ := hi.cell_slot ha hl hty
    exact ⟨k, o, Or.inr hv⟩

/-- `arc_clone a`: a new share of `a`'s block. -/
theorem out_arcClone {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {a : Var} {E : Entry} (ha : Γ a = some E)
    (hl : E.live = true) {t : Ty} (hty : E.ty = .arc t) {o : Bool} {k : Nat} {p : Val}
    (hv : m.st a = some ⟨o, some (.arc k p)⟩) :
    RhsOut m Γ ⟨.arc t, .own, true, [], [], false, false⟩ (.arc k p) true := by
  obtain ⟨hk, hwp, hvf⟩ := hi.arc_val ha hl hty hv
  have hok := hi.tyok ha; rw [hty] at hok
  simp only [Ty.ok, Bool.and_eq_true] at hok
  exact out_share hok.1 hvf hwp hk

/-- `arc_get a`: the payload, lent through a share of `a` (`getE`). Every
    handle in it lands in the block's payload through that share
    (`MInv.share_lands`); it holds no view and no closure. -/
theorem out_arcGet {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {a : Var} {E : Entry} (ha : Γ a = some E)
    (hl : E.live = true) {t : Ty} (hty : E.ty = .arc t) (_hhv : t.holdsView = false) (_hfn : t.hasFn = false)
    {o : Bool} {k : Nat} {p : Val} (hv : m.st a = some ⟨o, some (.arc k p)⟩) :
    RhsOut m Γ (getE a E t) (lendOf p) false := by
  obtain ⟨hk, hwp, hvf⟩ := hi.arc_val ha hl hty hv
  have hsh : SharesOK m t p := hi.arcBlk_shares hk
  have hok := hi.tyok ha; rw [hty] at hok
  simp only [Ty.ok, Bool.and_eq_true] at hok
  have htok := hok.1
  have hnint : E.ty ≠ .int := by rw [hty]; simp
  have hpk : PkgsOK p := hwp.pkgsOK_noView hvf
  have key : ValOK m t (lendOf p) (derive a E .share) E.held :=
    lend_valOK hwp hpk (fun _ hs => hi.share_lands ha hl hty hv hk hs) hi.noCellPay
      (ViewsOK.none hvf _ _) (NamesIn.nil _ (hwp.names_nil hvf)) hsh
      (fun s hs => by rw [hs] at hvf; simp [Ty.holdsView] at hvf)
  have hint : t = .int ∨ getE a E t = ⟨t, .bor, true, derive a E .share, E.held, false, false⟩ := by
    cases t <;> simp [getE]
  rcases hint with rfl | heq
  · obtain ⟨n, hn⟩ := valOK_int.mp key
    simp only [getE]; rw [hn]; exact intE_out n
  · rw [heq]
    refine ⟨rfl, Or.inr rfl, rfl, htok, fun _ r hr => ?_, fun h => (by cases h), fun _ => key,
      fun _ => by
        have h := hi.names a E ha hl (Or.inl hnint)
        show DepsNamed Γ (derive a E .share ++ E.held)
        exact (derive_named h rfl).append h.held,
      NamesIn.noView hwp hvf _, hpk.lendOf, fun h => nomatch h⟩
    rw [bor_vdeps _ rfl] at hr
    exact wf_append (wf_derive hi ha hl hnint _) (wf_held hi ha hl hnint) r hr

theorem rhs_new {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) {t : Ty} (ht : t.ok = true) :
    let m1 : Mem := { m with alloc := upd (upd m.alloc m.nid true) (m.nid + 1) true, nid := m.nid + 2 }
    RhsPost m m1 Γ Γ F ∧ RhsOut m1 Γ ⟨.vec t, .own, true, [], [], false, false⟩ (.node t m.nid (m.nid + 1) []) true := by
  intro m1
  have hold : ∀ o U, OwnedAt m o U → ∀ i ∈ U.ids, m1.alloc i = m.alloc i := by
    intro o U hU i hi'
    have hlt := (hi.heap.alloc o U hU i hi').2
    show upd (upd m.alloc m.nid true) (m.nid + 1) true i = m.alloc i
    rw [upd_ne _ _ (by omega), upd_ne _ _ (by omega)]
  have hheap : HeapOK m1 :=
    { nodup := fun o U hU => hi.heap.nodup o U hU
      disj := fun o1 o2 U1 U2 hne h1 h2 => hi.heap.disj o1 o2 U1 U2 hne h1 h2
      alloc := fun o U hU i hi' => by
        obtain ⟨ha, hlt⟩ := hi.heap.alloc o U hU i hi'
        exact ⟨by rw [hold o U hU i hi']; exact ha, by show i < m.nid + 2; omega⟩
      self := fun o U hU => hi.heap.self o U hU
      blk := hi.heap.blk.frame rfl (by show m.nid ≤ m.nid + 2; omega) (fun i hi' => by
          have hlt := (hi.heap.payAlloc hi').2
          show upd (upd m.alloc m.nid true) (m.nid + 1) true i = m.alloc i
          rw [upd_ne _ _ (by omega), upd_ne _ _ (by omega)])
        (fun o U hU i hi' => hi.heap.notPay hU hi')
      views := hi.heap.views }
  refine ⟨⟨hi.of_st rfl hheap (Nat.le_refl _), rfl, by show m.nid ≤ m.nid + 2; omega, fun _ => rfl, fun _ _ => rfl,
    fun _ _ h _ => h, fun _ => rfl, fun x E1 h => ⟨E1, h, rfl, rfl⟩, DKeep.refl _ _, BlkLe.refl _⟩, ?_⟩
  refine ⟨rfl, Or.inl rfl, rfl, ht, fun _ r hr => by simp [roots, Entry.vdeps, Mode.ownSlot] at hr,
    fun _ => ⟨rfl, WFv.node (fun e he => by simp at he), fun s v hin => ?_, ?_, ?_, ?_, ?_, ?_⟩,
    (fun h => by cases h), (fun _ _ hd => by cases hd), NamesIn.nil _ rfl,
    PkgsOK.leaf (fun _ h => by cases h with | elem he => cases he) (fun _ _ _ _ _ h => by cases h),
    fun _ => SharesOK.nil_node⟩
  · cases hin with | child he _ => simp at he
  · simp
  · intro i hi'
    simp only [ids_node, idsL_nil, List.mem_cons, List.not_mem_nil, or_false] at hi'
    show upd (upd m.alloc m.nid true) (m.nid + 1) true i = true ∧ i < m.nid + 2
    rcases hi' with rfl | rfl
    · rw [upd_ne _ _ (by omega)]; simp
    · simp
  · intro x U hU i hi' hiU
    have hlt := (hi.heap.alloc x U hU i hiU).2
    simp only [ids_node, idsL_nil, List.mem_cons, List.not_mem_nil, or_false] at hi'
    rcases hi' with rfl | rfl <;> omega
  · intro d o l hs
    rcases hs.cases' with h | ⟨e, hc, _⟩
    · cases h
    · cases hc with | elem he => simp at he
  · intro i hi' hp
    have hlt := (hi.heap.payAlloc hp).2
    simp only [ids_node, idsL_nil, List.mem_cons, List.not_mem_nil, or_false] at hi'
    rcases hi' with rfl | rfl <;> omega

theorem rhs_move' {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    {y : Var} {E : Entry} {v : Val} (hy : Γ y = some E) (hl : E.live = true) (hos : E.mode.ownSlot = true)
    (hyF : y ∉ F)
    (hmn : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none → d.root ≠ y) (hv : m.st y = some ⟨true, some v⟩)
    (hds : DtorSafe Γ .replace false y) :
    RhsPost m (m.set y ⟨true, none⟩) Γ (setE (kill .replace false y Γ) y { E with live := false, dtor := false }) F ∧
    RhsOut (m.set y ⟨true, none⟩) (setE (kill .replace false y Γ) y { E with live := false, dtor := false })
      ⟨E.ty, .own, true, [], E.held, false, false⟩ v true := by
  have hrb : E.mode ≠ .rootb := fun h => by rw [h] at hos; cases hos
  obtain ⟨T, hT, hwT, hvsT⟩ := hi.own_val hy hl hos
  rw [hT] at hv; cases hv
  obtain ⟨sl, hsl, hok, hslot⟩ := hi.slot y E hy
  obtain ⟨_, hown, _⟩ := hslot
  obtain ⟨hvec, _, _⟩ := hown hos
  have hst : ∀ o, o ≠ y → (m.set y ⟨true, none⟩).st o = m.st o := fun o ho => by simp [upd_ne _ _ ho]
  have hheap : HeapOK (m.set y ⟨true, none⟩) := hi.heap.without hT (m.set y ⟨true, none⟩) (fun o U hU => by
      rcases ownedAt_set.mp hU with ⟨_, h⟩ | h
      · cases h
      · exact h) (fun _ _ => rfl) (Nat.le_refl _)
  have hinv : MInv (m.set y ⟨true, none⟩) (setE (kill .replace false y Γ) y { E with live := false, dtor := false }) := by
    refine hi.change hanch hy hyF (fun p E hp hpm d hd hb _ => hmn p E hp hpm d hd hb)
      hrb hst hheap rfl
      (fun k hk => by cases k <;> simp [Eff.kills] at hk) ?_ hds (fun h => by cases h) (by simp)
      (fun h => absurd rfl h)
    refine ⟨⟨true, none⟩, by simp, hok, ⟨by simp [hos], fun _ => ⟨hvec, fun T h => by simp at h,
      fun h => by simp at h⟩, fun h => by simp [hos] at h⟩, rfl, fun h => by simp at h, rfl,
      fun h => by simp at h, fun h => by simp at h, fun T h => by simp at h, fun hd _ hn dep hdd hnm => ?_,
      fun h => by simp at h, fun hd => hi.wf.view y E hy hd, ArmOK.of_none rfl, fun _ T h => by simp at h⟩
    obtain ⟨Er, hEr, hroot⟩ := hi.wf.dtor y E hy hd hos (Or.inl hn) dep hdd hnm
    by_cases hry : dep.root = y
    · exact Or.inl ⟨hry, Mode.isRoot_of_ownSlot hos⟩
    · exact Or.inr ⟨hry, killE .replace false y Er, by simp [A2.kill, hEr],
        by rw [killE_mode]; exact hroot⟩
  refine ⟨⟨hinv, rfl, Nat.le_refl _, fun x => ?_, fun x hx => hst x (fun h => hyF (h ▸ hx)), ?_, ?_, ?_,
    ((DKeep.refl Γ []).kill .replace false y).setE (fun hd hos hn _ => ⟨E, hy, hd, hos, hn, fun _ h _ => h⟩),
    BlkLe.refl _⟩, ?_⟩
  · by_cases hxy : x = y
    · subst hxy; simp [hT]
    · rw [hst x hxy]
  · intro p Ep hp hpm
    have hpy : p ≠ y := fun h => by subst h; rw [hy] at hp; cases hp; exact hrb hpm
    simp only [setE, upd_ne _ _ hpy, kill, hp, Option.map_some]
    rw [killE_rootb hanch hyF _ _ (fun p E hp hpm d hd hb _ => hmn p E hp hpm d hd hb) hp hpm]
  · intro x
    by_cases hxy : x = y
    · subst hxy; simp [setE, hy]
    · simp only [setE, upd_ne _ _ hxy, kill]; cases Γ x <;> rfl
  · intro x E1 h
    by_cases hxy : x = y
    · subst hxy; simp only [setE, upd_same, Option.some.injEq] at h; subst h
      exact ⟨E, hy, rfl, rfl⟩
    · simp only [setE, upd_ne _ _ hxy, kill] at h
      cases hE : Γ x with
      | none => rw [hE] at h; cases h
      | some E0 => rw [hE] at h; cases h; exact ⟨E0, rfl, killE_mode .., killE_ty ..⟩
  · have hnint' : E.ty ≠ .int := fun h => by rw [h] at hvec; cases hvec
    refine ⟨rfl, Or.inl rfl, rfl, hi.tyok (E := E) hy, fun hn r hr => ?_, fun _ => ⟨hvec, hwT, ?_, ?_, ?_, ?_,
      hi.heap.self y v hT, fun i hi' => hi.heap.notPay hT hi'⟩, (fun h => by cases h),
      fun _ => (hi.names y E hy hl (Or.inl hnint')).transport (fun r Er hrE hr hl' hh' ho' => ?_)
        (fun _ hd => List.mem_append_right _ hd),
      hi.held y E _ v hy hl hT rfl, hi.pkgs y _ v hT rfl, fun _ => (hi.shares y E _ v hy hT rfl rfl).of_blk rfl⟩
    rotate_left 5
    · by_cases hry : r = y
      · subst hry; rw [hy] at hr; cases hr
        simp [Entry.vdeps, roots, hh'] at hrE
      · exact ⟨Er, by simp [setE, upd_ne _ _ hry, kill, hr, killE_nil (root_vdeps ho' hh')], hl', hh', rfl, rfl⟩
    · have hr' : r ∈ roots E.held := by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr
      obtain ⟨Er, hEr, hroot⟩ := wf_held hi hy hl hn r hr'
      by_cases hry : r = y
      · subst hry; exact ⟨{ E with live := false, dtor := false }, by simp [setE], by
          show E.mode.isRoot = true; revert hos; cases E.mode <;> simp [Mode.isRoot, Mode.ownSlot]⟩
      · exact ⟨killE .replace false y Er, by simp [setE, upd_ne _ _ hry, kill, hEr],
          by rw [killE_mode]; exact hroot⟩
    · refine hvsT.keep_except hT (hi.heap.self y v hT) (fun s w h => h) (fun dep hd hne => ?_) ⟨none, by simp⟩
      obtain ⟨Er, hEr, hroot⟩ := wf_held hi hy hl hnint' dep.root (List.mem_map_of_mem hd)
      exact (rootKeep_frame hi hanch (fun o ho => hst o (fun h => hyF (h ▸ ho))) hEr hroot
        (hst _ hne)).vkeep
    · exact hi.heap.nodup y v hT
    · exact fun i hi' => hi.heap.alloc y v hT i hi'
    · intro x U hU i hi' hiU
      rcases ownedAt_set.mp hU with ⟨_, h⟩ | ⟨hxy, h⟩
      · cases h
      · exact hi.heap.disj y x v U (Ne.symm hxy) hT h i hi' hiU

theorem rhs_move {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    {y : Var} {E : Entry} {v : Val} (hy : Γ y = some E) (hl : E.live = true) (hm : E.mode = .own)
    (hyF : y ∉ F)
    (hmn : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none → d.root ≠ y) (hv : m.st y = some ⟨true, some v⟩)
    (hds : DtorSafe Γ .replace false y) :
    RhsPost m (m.set y ⟨true, none⟩) Γ (setE (kill .replace false y Γ) y { E with live := false, dtor := false }) F ∧
    RhsOut (m.set y ⟨true, none⟩) (setE (kill .replace false y Γ) y { E with live := false, dtor := false })
      ⟨E.ty, .own, true, [], E.held, false, false⟩ v true :=
  rhs_move' hi hanch hy hl (by rw [hm]; rfl) hyF hmn hv hds

theorem kill_eq_upd {Γ : Ctx} {y : Var} {E : Entry} (hy : Γ y = some E) (e : Eff) (hv : Bool) :
    kill e hv y Γ = upd (kill e hv y Γ) y (some (killE e hv y E)) := by
  funext v
  by_cases h : v = y
  · subst h; simp [kill, hy]
  · simp [upd_ne _ _ h]

theorem kill_dom {Γ : Ctx} (e : Eff) (hv : Bool) (y x : Var) :
    (kill e hv y Γ x).isSome = (Γ x).isSome := by
  simp only [kill]; cases Γ x <;> rfl

theorem kill_cmode {Γ : Ctx} {e : Eff} {hv : Bool} {y x : Var} {E1 : Entry}
    (h : kill e hv y Γ x = some E1) : ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode ∧ E1.ty = E0.ty := by
  simp only [kill] at h
  cases hE : Γ x with
  | none => rw [hE] at h; cases h
  | some E0 => rw [hE] at h; cases h; exact ⟨E0, rfl, killE_mode .., killE_ty ..⟩

theorem kill_root {Γ : Ctx} {e : Eff} {hv : Bool} {y r : Var} {Er : Entry} (h : Γ r = some Er)
    (hroot : Er.mode.isRoot = true) : ∃ E', kill e hv y Γ r = some E' ∧ E'.mode.isRoot = true :=
  ⟨killE e hv y Er, by simp [kill, h], by rw [killE_mode]; exact hroot⟩

/-- Dropping elements keeps a tree from viewing itself. -/
theorem SelfFree.shrink {t : Ty} {c d : Nat} {es es' : List Val} (hsf : SelfFree (.node t c d es'))
    (hsub : ∀ e ∈ es, e ∈ es') : SelfFree (.node t c d es) := by
  intro d0 o l hv u c0 es0 hn
  have lift : ∀ {w : Val}, Sub w (.node t c d es) → w = .node t c d es ∨ Sub w (.node t c d es') := by
    intro w hw
    rcases hw.cases' with h | ⟨e, hc, hs⟩
    · exact Or.inl h
    · cases hc with | elem he => exact Or.inr (Sub.child (hsub e he) hs)
  rcases lift hv with h | hv'
  · cases h
  rcases lift hn with h | hn'
  · cases h; exact hsf _ o l hv' t c es' (Sub.refl _)
  · exact hsf d0 o l hv' u c0 es0 hn'

theorem idsL_sub_append (es : List Val) (e : Val) : List.Sublist (idsL es) (idsL (es ++ [e])) := by
  rw [idsL_append]; exact List.sublist_append_left _ _

theorem rhs_pop {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    {y : Var} {E : Entry} {t : Ty} (hy : Γ y = some E) (hl : E.live = true) (hty : E.ty = .vec t)
    (hcan : canDo E.mode .drop) (hyF : y ∉ F)
    {t' : Ty} {c d : Nat} {es : List Val} {e : Val}
    (hT : m.st y = some ⟨true, some (.node t' c d (es ++ [e]))⟩) (hds : DtorSafe Γ .drop t.holdsView y) :
    RhsPost m (m.set y ⟨true, some (.node t' c d es)⟩) Γ (kill .drop t.holdsView y Γ) F ∧
    RhsOut (m.set y ⟨true, some (.node t' c d es)⟩) (kill .drop t.holdsView y Γ) (popE y E t) e
      e.owns := by
  have hm : E.mode = .own := by
    rcases hcan with h | ⟨b, h, _⟩
    · exact h
    · exact absurd h (hi.noInout y E b hy)
  have hos : E.mode.ownSlot = true := by rw [hm]; rfl
  have popMn : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none →
      Eff.drop.kills t.holdsView d.kind = true → d.root ≠ y := by
    intro _ _ _ _ ⟨r, k⟩ _ hb hk; cases k <;> simp_all [Kind.bound, Eff.kills]
  obtain ⟨T, hT', hwT, hvsT⟩ := hi.own_val hy hl hos
  rw [hT] at hT'; cases hT'
  rw [hty] at hwT hvsT
  have htt : t' = t := by cases hwT; rfl
  subst htt
  have hwes : ∀ x ∈ es ++ [e], WFv t' x := fun x hx => hwT.elem rfl hx
  have hwS : WFv (.vec t') (.node t' c d es) := WFv.node (fun x hx => hwes x (by simp [hx]))
  have hemem : e ∈ es ++ [e] := by simp
  have hnT := hi.heap.nodup y _ hT
  have hsubl : List.Sublist (Val.node t' c d es).ids (Val.node t' c d (es ++ [e])).ids := by
    simp only [ids_node]; exact ((idsL_sub_append es e).cons_cons d).cons_cons c
  have hsube : List.Sublist e.ids (Val.node t' c d (es ++ [e])).ids := by
    simp only [ids_node, idsL_append, idsL_cons, idsL_nil, List.append_nil]
    exact ((List.sublist_append_right _ _).cons d).cons c
  -- the shrunk tree and the popped element do not overlap
  have hsep : ∀ i ∈ e.ids, i ∉ (Val.node t' c d es).ids := by
    intro i hie hiS
    simp only [ids_node, idsL_append, idsL_cons, idsL_nil, List.append_nil, List.nodup_cons,
      List.mem_cons, List.mem_append, List.nodup_append] at hnT hiS
    rcases hiS with rfl | rfl | hiS
    · exact hnT.1 (Or.inr (Or.inr hie))
    · exact hnT.2.1 (Or.inr hie)
    · exact hnT.2.2.2.2 i hiS i hie rfl
  let m1 := m.set y ⟨true, some (.node t' c d es)⟩
  have hst : ∀ o, o ≠ y → m1.st o = m.st o := fun o ho => by simp [m1, upd_ne _ _ ho]
  have hm1y : m1.st y = some ⟨true, some (.node t' c d es)⟩ := by simp [m1]
  -- A3.1: the shrunk tree's shares, and the popped element's, are the old tree's
  have hshT : SharesOK m (.vec t') (.node t' c d (es ++ [e])) := by
    have := hi.shares y E _ _ hy hT rfl rfl; rwa [hty] at this
  have hshS : SharesOK m1 (.vec t') (.node t' c d es) :=
    hshT.node_sub (fun x hx => List.mem_append_left _ hx) rfl
  have hown1 : ∀ o U, OwnedAt m1 o U → (o = y ∧ U = .node t' c d es) ∨ (o ≠ y ∧ OwnedAt m o U) := by
    intro o U hU
    rcases ownedAt_set.mp hU with ⟨h1, h2⟩ | h
    · cases h2; exact Or.inl ⟨h1, rfl⟩
    · exact Or.inr h
  have hheap : HeapOK m1 :=
    { nodup := fun o U hU => by
        rcases hown1 o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
        · exact hnT.sublist hsubl
        · exact hi.heap.nodup o U h
      disj := fun o1 o2 U1 U2 hne h1 h2 => by
        rcases hown1 o1 U1 h1 with ⟨rfl, rfl⟩ | ⟨ho1, h1'⟩ <;>
          rcases hown1 o2 U2 h2 with ⟨rfl, rfl⟩ | ⟨ho2, h2'⟩
        · exact absurd rfl hne
        · exact fun i hi' => hi.heap.disj _ o2 _ U2 (Ne.symm ho2) hT h2' i (hsubl.subset hi')
        · exact fun i hi' hi'' => hi.heap.disj _ o1 _ U1 (Ne.symm ho1) hT h1' i (hsubl.subset hi'') hi'
        · exact hi.heap.disj o1 o2 U1 U2 hne h1' h2'
      alloc := fun o U hU i hi' => by
        rcases hown1 o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
        · exact hi.heap.alloc y _ hT i (hsubl.subset hi')
        · exact hi.heap.alloc o U h i hi'
      self := fun o U hU => by
        rcases hown1 o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
        · exact (hi.heap.self y _ hT).shrink (fun x hx => List.mem_append_left _ hx)
        · exact hi.heap.self o U h
      blk := hi.heap.blk.frame rfl (Nat.le_refl _) (fun _ _ => rfl) (fun o U hU i hi' => by
        rcases hown1 o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
        · exact hi.heap.notPay hT (hsubl.subset hi')
        · exact hi.heap.notPay h hi')
      views := hi.heap.views }
  have hsfT := hi.heap.self y _ hT
  have hkeepF : ∀ dep ∈ E.held, dep.root ≠ y → VKeep m m1 dep := by
    intro dep hd hne
    have hnint : E.ty ≠ .int := by rw [hty]; simp
    obtain ⟨Er, hEr, hroot⟩ := wf_held hi hy hl hnint dep.root (List.mem_map_of_mem hd)
    exact (rootKeep_frame hi hanch (fun o ho => hst o (fun h => hyF (h ▸ ho))) hEr hroot
      (hst _ hne)).vkeep
  have hinv : MInv m1 (kill .drop t'.holdsView y Γ) := by
    rw [kill_eq_upd hy]
    refine hi.change hanch hy hyF popMn (by rw [hm]; simp) hst hheap rfl ?_ ?_ hds (fun h => by cases h) (by simp)
      (fun _ Ex' hx' hl0 hh0 _ => by
        simp only [Option.some.injEq] at hx'; subst hx'
        rw [killE_nil (root_vdeps (by rw [hm]; rfl) hh0)]; exact ⟨hl0, hh0⟩)
    · intro k hk
      by_cases hn : ∃ b t, k = .name b t
      · obtain ⟨b, t, rfl⟩ := hn; exact ⟨vkeep_name _ _ _ _ _, hkeep_name _ _ _ _ _⟩
      have hk' : k = .self ∧ t'.holdsView = false := by
        cases k <;> cases hh : t'.holdsView <;> simp_all [Eff.kills]
      obtain ⟨rfl, hhv⟩ := hk'
      refine ⟨fun d' o l s ⟨_, _, hks, _⟩ => absurd rfl hks, ?_⟩
      exact Evolve.self_hkeep ⟨hT, by simp [m1], hwS, rfl⟩ hhv hshS
    · refine ⟨⟨true, some (.node t' c d es)⟩, by simp [m1], by rw [killE_ty, hty]; exact hi.tyok (E := E) hy ▸ (by rw [hty]),
        ⟨by rw [killE_mode, hm]; rfl, fun _ => ⟨by rw [killE_ty, hty]; rfl,
          fun U hU => by cases hU; rw [killE_ty, hty]; exact hwS,
          fun _ => ⟨_, rfl, by
            rw [killE_ty, killE_held, hty]
            exact hvsT.keep_except hT hsfT (fun s w h => by
              cases h with
              | child hm' hin => exact ViewIn.child (List.mem_append_left _ hm') hin) hkeepF ⟨_, hm1y⟩⟩⟩,
          fun h => by rw [killE_mode, hm] at h; cases h⟩,
        by rw [killE_mode], fun hl' hn r hr => ?_, killE_ty ..,
        (fun _ _ => by
          rw [← kill_eq_upd hy]; exact (hi.names y E hy hl (Or.inl (by rw [hty]; simp))).kill _ _ _),
        (fun _ T hT' => by
          simp only [Option.some.injEq] at hT'; subst hT'; rw [killE_held]
          exact (hi.held y E _ _ hy hl hT rfl).sub fun x hx => by
            simp only [Val.names, namesL_append] at hx ⊢; exact List.mem_append_left _ hx),
        (fun T hT' => by
          simp only [Option.some.injEq] at hT'; subst hT'
          intro fs te ms e0 cs hs
          rcases hs.cases' with h | ⟨e', hc, hs'⟩
          · cases h
          · cases hc with
            | elem he => exact (hi.pkgs y _ _ hT rfl) fs te ms e0 cs (Sub.child (List.mem_append_left _ he) hs')),
        (fun hd hos hn dep hdd hnm => by
          rw [killE_dbind] at hd; rw [killE_mode] at hos; rw [killE_ty] at hn; rw [killE_vdeps] at hdd
          obtain ⟨Er, hEr, hroot⟩ := hi.wf.dtor y E hy hd hos (Or.inl hn) dep hdd hnm
          by_cases hry : dep.root = y
          · exact Or.inl ⟨hry, by rw [killE_mode, hm]; rfl⟩
          · exact Or.inr ⟨hry, killE .drop t'.holdsView y Er, by simp [A2.kill, hEr],
              by rw [killE_mode]; exact hroot⟩),
        (fun hd => by rw [killE_dtor] at hd; rw [killE_dbind]; exact hi.wf.arm y E hy hd),
        (fun hd => by rw [killE_dbind] at hd; rw [killE_ty]; exact hi.wf.view y E hy hd),
        (fun hd hos' T hT' => by
          rw [killE_dbind] at hd; rw [killE_mode] at hos'
          simp only [Option.some.injEq] at hT'; subst hT'
          refine ⟨by rw [killE_dtor]; exact (hi.armed y E _ hy hT hd hos' _ rfl).1, ?_⟩
          rw [killE_ty, killE_held, hty]
          exact hvsT.keep_except hT hsfT (fun s w h => by
            cases h with
            | child hm' hin => exact ViewIn.child (List.mem_append_left _ hm') hin) hkeepF ⟨_, hm1y⟩),
        fun _ T hT' => by
          simp only [Option.some.injEq] at hT'; subst hT'; rw [killE_ty, hty]; exact hshS⟩
      rw [killE_vdeps] at hr
      rw [killE_ty] at hn
      obtain ⟨Er, hEr, hroot⟩ := hi.wf y E hy hl (Or.inl hn) r hr
      by_cases hry : r = y
      · exact Or.inl ⟨hry, by rw [killE_mode, hm]; rfl⟩
      · exact Or.inr ⟨hry, kill_root hEr hroot⟩
  have hnint : E.ty ≠ .int := by rw [hty]; simp
  have hNk : ∀ E' : Entry, E'.vdeps ⊆ E.vdeps → NameOK (kill .drop t'.holdsView y Γ) E' := fun E' hs =>
    ((hi.names y E hy hl (Or.inl hnint)).kill _ _ _).mono (by rw [killE_vdeps]; exact hs)
  have hHeld : ∀ D, D ⊆ E.held → D ⊆ E.vdeps := fun D hs _ hd => List.mem_append_right _ (hs hd)
  have hNi : NamesIn e E.held := (hi.held y E _ _ hy hl hT rfl).sub (names_elem hemem)
  have hPk : PkgsOK e := (hi.pkgs y _ _ hT rfl).elem hemem
  have hwfH : ∀ r ∈ roots E.held, ∃ Er, kill .drop t'.holdsView y Γ r = some Er ∧ Er.mode.isRoot = true :=
    fun r hr => by
      obtain ⟨Er, hEr, hroot⟩ := wf_held hi hy hl hnint r hr
      exact kill_root hEr hroot
  refine ⟨⟨hinv, rfl, Nat.le_refl _, fun x => ?_, fun x hx => hst x (fun h => hyF (h ▸ hx)), ?_,
    fun x => kill_dom .., fun x E1 h => kill_cmode h, (DKeep.refl Γ []).kill _ _ _, BlkLe.refl _⟩, ?_⟩
  · by_cases hxy : x = y
    · subst hxy; simp [hT]
    · rw [hst x hxy]
  · intro p Ep hp hpm
    simp only [kill, hp, Option.map_some]
    rw [killE_rootb hanch hyF _ _ popMn hp hpm]
  · have hwe : WFv t' e := hwes e hemem
    cases t' with
    | int =>
      cases hwe with | int => exact intE_out _
    | slice s =>
      cases hwe with
      | view =>
        rename_i dv ov lv
        have hok := hi.tyok hy; rw [hty] at hok
        show RhsOut _ _ ⟨.slice s, .bor, true, E.held, E.held, false, false⟩ _ false
        have htok : (Ty.slice s).ok = true := by simpa [Ty.ok] using hok
        refine RhsOut.mk rfl (Or.inr rfl) rfl htok (fun _ => ?_) (fun h => nomatch h) (fun _ => ?_)
          (fun _ => hNk _ (hHeld _ (List.append_subset.mpr ⟨List.Subset.refl _, List.Subset.refl _⟩))) hNi hPk
          (fun h => nomatch h)
        · show ∀ r ∈ roots (E.held ++ E.held), _
          exact wf_append hwfH hwfH
        · obtain ⟨d', o', l', hv', dep, hd, ha⟩ := hvsT s _ (ViewIn.child hemem ViewIn.here)
          cases hv'
          obtain ⟨r, k⟩ := dep
          by_cases hry : r = y
          · subst hry
            by_cases hks : k = .share
            · subst hks; exact .view ⟨_, hd, vkeep_share (m := m) (m' := m1) (BlkLe.refl _) (RootMem.own hm1y) _ _ _ s ha⟩
            · exact (viewAt_not_self hT hsfT (ViewIn.child hemem ViewIn.here) hks ha).elim
          exact .view ⟨_, hd, hkeepF _ hd hry _ _ _ s ha⟩
    | vec s =>
      cases hwe with
      | node hes =>
        rename_i c1 d1 es1
        have hok := hi.tyok hy; rw [hty] at hok
        show RhsOut _ _ ⟨.vec s, .own, true, [], E.held, false, false⟩ _ true
        refine ⟨rfl, Or.inl rfl, rfl, hok, fun _ r hr => ?_, fun _ => ⟨rfl, WFv.node hes, ?_, ?_,
          ?_, ?_, hsfT.sub (Sub.child hemem (Sub.refl _)),
          fun i hi' => hi.heap.notPay hT (hsube.subset hi')⟩, (fun h => by cases h),
          fun _ => hNk _ (hHeld _ (List.Subset.refl _)), hNi, hPk, fun _ => (hshT.elem hemem).of_blk rfl⟩
        · exact hwfH r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)
        · exact hvsT.keep_except hT hsfT (fun s' w h => ViewIn.child hemem h) hkeepF ⟨_, hm1y⟩
        · exact hnT.sublist hsube
        · exact fun i hi' => hi.heap.alloc y _ hT i (hsube.subset hi')
        · intro x U hU i hi' hiU
          rcases hown1 x U hU with ⟨_, rfl⟩ | ⟨hxy, h⟩
          · exact hsep i hi' hiU
          · exact hi.heap.disj y x _ U (Ne.symm hxy) hT h i (hsube.subset hi') hiU
    | prod a b =>
      cases hwe with
      | pair hwa hwb =>
        have hok := hi.tyok hy; rw [hty] at hok
        show RhsOut _ _ ⟨.prod a b, .own, true, [], E.held, false, false⟩ _ true
        refine ⟨rfl, Or.inl rfl, rfl, hok, fun _ r hr => ?_, fun _ => ⟨rfl, WFv.pair hwa hwb, ?_, ?_,
          ?_, ?_, hsfT.sub (Sub.child hemem (Sub.refl _)),
          fun i hi' => hi.heap.notPay hT (hsube.subset hi')⟩, (fun h => by cases h),
          fun _ => hNk _ (hHeld _ (List.Subset.refl _)), hNi, hPk, fun _ => (hshT.elem hemem).of_blk rfl⟩
        · exact hwfH r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)
        · exact hvsT.keep_except hT hsfT (fun s' w h => ViewIn.child hemem h) hkeepF ⟨_, hm1y⟩
        · exact hnT.sublist hsube
        · exact fun i hi' => hi.heap.alloc y _ hT i (hsube.subset hi')
        · intro x U hU i hi' hiU
          rcases hown1 x U hU with ⟨_, rfl⟩ | ⟨hxy, h⟩
          · exact hsep i hi' hiU
          · exact hi.heap.disj y x _ U (Ne.symm hxy) hT h i (hsube.subset hi') hiU
    | sum a b =>
      have hsumwf := hwe
      cases hwe with
      | inl _ | inr _ =>
        have hok := hi.tyok hy; rw [hty] at hok
        show RhsOut _ _ ⟨.sum a b, .own, true, [], E.held, false, false⟩ _ true
        refine ⟨rfl, Or.inl rfl, rfl, hok, fun _ r hr => ?_, fun _ => ⟨rfl, hsumwf, ?_, ?_,
          ?_, ?_, hsfT.sub (Sub.child hemem (Sub.refl _)),
          fun i hi' => hi.heap.notPay hT (hsube.subset hi')⟩, (fun h => by cases h),
          fun _ => hNk _ (hHeld _ (List.Subset.refl _)), hNi, hPk, fun _ => (hshT.elem hemem).of_blk rfl⟩
        · exact hwfH r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)
        · exact hvsT.keep_except hT hsfT (fun s' w h => ViewIn.child hemem h) hkeepF ⟨_, hm1y⟩
        · exact hnT.sublist hsube
        · exact fun i hi' => hi.heap.alloc y _ hT i (hsube.subset hi')
        · intro x U hU i hi' hiU
          rcases hown1 x U hU with ⟨_, rfl⟩ | ⟨hxy, h⟩
          · exact hsep i hi' hiU
          · exact hi.heap.disj y x _ U (Ne.symm hxy) hT h i (hsube.subset hi') hiU
    | fn ms q =>
      have hsumwf := hwe
      cases hwe with
      | pkg _ _ =>
        have hok := hi.tyok hy; rw [hty] at hok
        show RhsOut _ _ ⟨.fn ms q, .own, true, [], E.held, false, false⟩ _ true
        refine ⟨rfl, Or.inl rfl, rfl, hok, fun _ r hr => ?_, fun _ => ⟨rfl, hsumwf, ?_, ?_,
          ?_, ?_, hsfT.sub (Sub.child hemem (Sub.refl _)),
          fun i hi' => hi.heap.notPay hT (hsube.subset hi')⟩, (fun h => by cases h),
          fun _ => hNk _ (hHeld _ (List.Subset.refl _)), hNi, hPk, fun _ => (hshT.elem hemem).of_blk rfl⟩
        · exact hwfH r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)
        · exact hvsT.keep_except hT hsfT (fun s' w h => ViewIn.child hemem h) hkeepF ⟨_, hm1y⟩
        · exact hnT.sublist hsube
        · exact fun i hi' => hi.heap.alloc y _ hT i (hsube.subset hi')
        · intro x U hU i hi' hiU
          rcases hown1 x U hU with ⟨_, rfl⟩ | ⟨hxy, h⟩
          · exact hsep i hi' hiU
          · exact hi.heap.disj y x _ U (Ne.symm hxy) hT h i (hsube.subset hi') hiU
    | arc a =>
      have hsumwf := hwe
      cases hwe with
      | arc =>
        have hok := hi.tyok hy; rw [hty] at hok
        show RhsOut _ _ ⟨.arc a, .own, true, [], E.held, false, false⟩ _ true
        refine ⟨rfl, Or.inl rfl, rfl, hok, fun _ r hr => ?_, fun _ => ⟨rfl, hsumwf, ?_, ?_,
          ?_, ?_, hsfT.sub (Sub.child hemem (Sub.refl _)),
          fun i hi' => hi.heap.notPay hT (hsube.subset hi')⟩, (fun h => by cases h),
          fun _ => hNk _ (hHeld _ (List.Subset.refl _)), hNi, hPk, fun _ => (hshT.elem hemem).of_blk rfl⟩
        · exact hwfH r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)
        · exact hvsT.keep_except hT hsfT (fun s' w h => ViewIn.child hemem h) hkeepF ⟨_, hm1y⟩
        · exact List.nodup_nil
        · intro i hi'; nomatch hi'
        · intro x U hU i hi'; nomatch hi'
    | lk a =>
      have hsumwf := hwe
      cases hwe with
      | lk =>
        have hok := hi.tyok hy; rw [hty] at hok
        show RhsOut _ _ ⟨.lk a, .own, true, [], E.held, false, false⟩ _ true
        refine ⟨rfl, Or.inl rfl, rfl, hok, fun _ r hr => ?_, fun _ => ⟨rfl, hsumwf, ?_, ?_,
          ?_, ?_, hsfT.sub (Sub.child hemem (Sub.refl _)),
          fun i hi' => hi.heap.notPay hT (hsube.subset hi')⟩, (fun h => by cases h),
          fun _ => hNk _ (hHeld _ (List.Subset.refl _)), hNi, hPk, fun _ => (hshT.elem hemem).of_blk rfl⟩
        · exact hwfH r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)
        · exact hvsT.keep_except hT hsfT (fun s' w h => ViewIn.child hemem h) hkeepF ⟨_, hm1y⟩
        · exact List.nodup_nil
        · intro i hi'; nomatch hi'
        · intro x U hU i hi'; nomatch hi'
    | cell a =>
      have hsumwf := hwe
      cases hwe with
      | cell =>
        have hok := hi.tyok hy; rw [hty] at hok
        show RhsOut _ _ ⟨.cell a, .own, true, [], E.held, false, false⟩ _ true
        refine ⟨rfl, Or.inl rfl, rfl, hok, fun _ r hr => ?_, fun _ => ⟨rfl, hsumwf, ?_, ?_,
          ?_, ?_, hsfT.sub (Sub.child hemem (Sub.refl _)),
          fun i hi' => hi.heap.notPay hT (hsube.subset hi')⟩, (fun h => by cases h),
          fun _ => hNk _ (hHeld _ (List.Subset.refl _)), hNi, hPk, fun _ => (hshT.elem hemem).of_blk rfl⟩
        · exact hwfH r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)
        · exact hvsT.keep_except hT hsfT (fun s' w h => ViewIn.child hemem h) hkeepF ⟨_, hm1y⟩
        · exact List.nodup_nil
        · intro i hi'; nomatch hi'
        · intro x U hU i hi'; nomatch hi'
    | dtor f a =>
      cases hwe with
      | dtor ho hwi =>
        rw [WFv.owns hwi (Ty.owning_of_isStruct ho)]
        have hok := hi.tyok hy; rw [hty] at hok
        show RhsOut _ _ ⟨.dtor f a, .own, true, [], E.held, false, false⟩ _ true
        refine ⟨rfl, Or.inl rfl, rfl, hok, fun _ r hr => ?_, fun _ => ⟨rfl, WFv.dtor ho hwi, ?_, ?_,
          ?_, ?_, hsfT.sub (Sub.child hemem (Sub.refl _)),
          fun i hi' => hi.heap.notPay hT (hsube.subset hi')⟩, (fun h => by cases h),
          fun _ => hNk _ (hHeld _ (List.Subset.refl _)), hNi, hPk, fun _ => (hshT.elem hemem).of_blk rfl⟩
        · exact hwfH r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)
        · exact hvsT.keep_except hT hsfT (fun s' w h => ViewIn.child hemem h) hkeepF ⟨_, hm1y⟩
        · exact hnT.sublist hsube
        · exact fun i hi' => hi.heap.alloc y _ hT i (hsube.subset hi')
        · intro x U hU i hi' hiU
          rcases hown1 x U hU with ⟨_, rfl⟩ | ⟨hxy, h⟩
          · exact hsep i hi' hiU
          · exact hi.heap.disj y x _ U (Ne.symm hxy) hT h i (hsube.subset hi') hiU
end A2
