import A2.Rhs

/-! A2 — Agora #610: the marking sweep (`Mem.sweepD`) keeps the invariant.

It differs from the sweep of `A2/Sweep.lean` from the roots `RootsD` (the
slots' values, the orphans' payloads and the top orphans' to be) only in
the blocks it pins: a top orphan, which it marks `dead`, and an orphan
whose payload is still in it.  Every block the roots reach it keeps as it
was, so what the sweep's lemmas give of `m.sweepR (RootsD ..)` grows to it
(`BlkLe`); of the pinned blocks the invariant is read off the store before
the sweep: a pinned block's payload is a root, so the blocks it reaches are
kept. -/

namespace A2

/-- A store's blocks grow over a later `nv` with the same slots: what a
    `recover` frame returns to is kept.  (From `A3/Nid.lean`.) -/
theorem CatchOK.of_st {m m' : Mem} (hst : m'.st = m.st) (hnv : m.nv ≤ m'.nv) (hb : BlkLe m.blk m'.blk) :
    ∀ {s : Stmt}, CatchOK m s → CatchOK m' s
  | .seq a _, h => CatchOK.of_st hst hnv hb (s := a) h
  | .scope _ k, h => CatchOK.of_st hst hnv hb (s := k) h
  | .scopeD _ _ k, h => CatchOK.of_st hst hnv hb (s := k) h
  | .rbind _ k, h => CatchOK.of_st hst hnv hb (s := k) h
  | .frozen _ k, h => CatchOK.of_st hst hnv hb (s := k) h
  | .catchR x m0 k, h => by
    obtain ⟨h1, h2, h3, h4, h5⟩ := h
    exact ⟨fun v hv hx => by rw [hst]; exact h1 v hv hx, h2, Nat.le_trans h3 hnv,
      fun k' bl hk hr => by
        obtain ⟨bl', h1', h2'⟩ := h4 k' bl hk hr
        obtain ⟨bl'', h3', h4'⟩ := hb k' bl' h1'
        exact ⟨bl'', h3', h2'.trans h4'⟩, CatchOK.of_st hst hnv hb (s := k) h5⟩
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
  | .withLock .., _ => trivial
  | .scopeL _ _ _ k, h => CatchOK.of_st hst hnv hb (s := k) h
  | .insert .., _ => trivial
  | .withElem .., _ => trivial
  | .callcE .., _ => trivial

@[simp] theorem Mem.sweepD_st (m : Mem) : m.sweepD.st = m.st := rfl
@[simp] theorem Mem.sweepD_nv (m : Mem) : m.sweepD.nv = m.nv := rfl
@[simp] theorem Mem.sweepD_nid (m : Mem) : m.sweepD.nid = m.nid := rfl
@[simp] theorem Mem.sweepD_vals (m : Mem) : m.sweepD.vals = m.vals := rfl

@[simp] theorem Blk.mark_ty (bl : Blk) : bl.mark.ty = bl.ty := rfl
@[simp] theorem Blk.mark_kind (bl : Blk) : bl.mark.kind = .dead := rfl
@[simp] theorem Blk.mark_pay (bl : Blk) : bl.mark.pay = bl.pay := rfl
@[simp] theorem Blk.mark_rd (bl : Blk) : bl.mark.rd = .int 0 := rfl

/-- A pinned block is an `arc` block (a top orphan) or a `dead` one, of a
    destructor type, its payload in it. -/
theorem Pinned.shape {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} (h : Pinned R B k) {bl : Blk}
    (hk : B k = some bl) :
    ∃ n f u p kd, bl = ⟨Ty.nest n (.dtor f u), kd, some p⟩ ∧ (kd = .arc ∨ kd = .dead) := by
  rcases h with ⟨⟨⟨n, f, u, p, hp⟩, _⟩, _⟩ | ⟨n, f, u, p, hp⟩
  · rw [hk] at hp; cases hp; exact ⟨n, f, u, p, _, rfl, Or.inl rfl⟩
  · rw [hk] at hp; cases hp; exact ⟨n, f, u, p, _, rfl, Or.inr rfl⟩

theorem Pinned.kind {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} (h : Pinned R B k) {bl : Blk}
    (hk : B k = some bl) : bl.kind = .arc ∨ bl.kind = .dead := by
  obtain ⟨n, f, u, p, kd, rfl, hkd⟩ := h.shape hk; exact hkd

/-- ... marked, an orphan. -/
theorem Pinned.mark {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} (h : Pinned R B k) {bl : Blk}
    (hk : B k = some bl) : ∃ n f u p, bl.mark = ⟨Ty.nest n (.dtor f u), .dead, some p⟩ := by
  obtain ⟨n, f, u, p, kd, rfl, _⟩ := h.shape hk; exact ⟨n, f, u, p, rfl⟩

/-- ... whose payload is in it: a root of the marking sweep. -/
theorem Pinned.root {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} (h : Pinned R B k) {bl : Blk}
    (hk : B k = some bl) : ∃ p, bl.pay = some p ∧ RootsD R B p := by
  rcases h with ⟨hc, hnr⟩ | ⟨n, f, u, p, hp⟩
  · obtain ⟨n, f, u, p, hp⟩ := hc.1
    rw [hk] at hp; cases hp
    exact ⟨p, rfl, Or.inr ⟨k, n, f, u, ⟨hc, hnr⟩, hk⟩⟩
  · rw [hk] at hp; cases hp
    exact ⟨p, rfl, Or.inl (Or.inr ⟨k, n, f, u, hk⟩)⟩

/-- Marking leaves what a block owns. -/
theorem Pinned.tree {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} (h : Pinned R B k) {bl : Blk}
    (hk : B k = some bl) : bl.mark.tree = bl.tree := by
  obtain ⟨n, f, u, p, kd, rfl, hkd⟩ := h.shape hk
  rcases hkd with rfl | rfl <;> rfl

/-- The marking sweep's blocks: a reached one as it was, or a pinned one
    marked `dead`. -/
theorem sweepBlkD_some {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} {bl : Blk} :
    sweepBlkD R B k = some bl →
      (B k = some bl ∧ Reached (RootsD R B) B k) ∨
      (∃ bl0, B k = some bl0 ∧ ¬ Reached (RootsD R B) B k ∧ Pinned R B k ∧ bl = bl0.mark) := by
  unfold sweepBlkD
  split
  · next hr => exact fun h => Or.inl ⟨h, hr⟩
  · next hr =>
    split
    · next hp =>
      intro h
      cases hk : B k with
      | none => rw [hk] at h; cases h
      | some bl0 => rw [hk] at h; cases h; exact Or.inr ⟨bl0, rfl, hr, hp, rfl⟩
    · intro h; cases h

theorem sweepBlkD_reached {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} {bl : Blk}
    (hk : B k = some bl) (hr : Reached (RootsD R B) B k) : sweepBlkD R B k = some bl := by
  unfold sweepBlkD
  split
  · exact hk
  · next h => exact absurd hr h

theorem sweepBlkD_pinned {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} {bl : Blk}
    (hk : B k = some bl) (hr : ¬ Reached (RootsD R B) B k) (hp : Pinned R B k) :
    sweepBlkD R B k = some bl.mark := by
  unfold sweepBlkD; simp [hr, hp, hk]

theorem sweepAllocD_true {R : Val → Prop} {B : Nat → Option Blk} {a : Nat → Bool} {i : Nat} :
    sweepAllocD R B a i = true ↔ a i = true ∧ ¬ UnreachedD R B i := by
  unfold sweepAllocD
  by_cases h : UnreachedD R B i
  · simp [h]
  · simp [h]

section
variable {m : Mem}

/-- The slots' values are roots of the marking sweep. -/
theorem rootsD_vals : ∀ v, m.vals v → RootsD m.vals m.blk v := fun _ h => Or.inl (Or.inl h)

/-- The sweep from the marking sweep's roots keeps no block the marking
    sweep does not keep as it was. -/
theorem sweepD_blkLe (m : Mem) : BlkLe (m.sweepR (RootsD m.vals m.blk)).blk m.sweepD.blk :=
  BlkLe.of_le fun _ _ h => by
    obtain ⟨hk, hr⟩ := Mem.sweepR_blk.mp h
    exact sweepBlkD_reached hk hr

/-- What a pinned block's payload refers to, the marking sweep's roots
    reach. -/
theorem Pinned.kept {k : Nat} (h : Pinned m.vals m.blk k) {bl : Blk} (hk : m.blk k = some bl)
    {p : Val} (hp : bl.pay = some p) : Kept (RootsD m.vals m.blk) m p := by
  obtain ⟨p', hp', hroot⟩ := h.root hk
  rw [hp] at hp'; cases hp'
  exact fun _ hr => .root hroot hr

/-- A marked orphan holds what its block's invariant says. -/
theorem Blk.DtorOK.mark {bl : Blk} (h : bl.DtorOK) (hd : bl.kind = .arc ∨ bl.kind = .dead)
    (hfree : bl.kind = .arc → bl.ty.dtorFree = false) : bl.mark.DtorOK := by
  refine ⟨fun h1 => absurd rfl h1, fun _ => ?_, fun h1 => h.2.2 h1⟩
  rcases hd with hd | hd
  · exact hfree hd
  · exact h.2.1 hd

/-- A top orphan is not reached from the marking sweep's roots: they are
    the roots before marking and orphans' payloads. -/
theorem TopOrphan.not_reached {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} (h : TopOrphan R B k) :
    ¬ Reached (RootsD R B) B k := fun hr =>
  h.2 (hr.roots fun _ hv => hv.elim Or.inl fun ⟨k1, n1, f1, u1, ht1, hk1⟩ => Or.inr ⟨k1, n1, f1, u1, ht1.1, hk1⟩)

/-- A top orphan is of a destructor type. -/
theorem TopOrphan.ty {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} (h : TopOrphan R B k) {bl : Blk}
    (hk : B k = some bl) : bl.kind = .arc ∧ bl.ty.dtorFree = false := by
  obtain ⟨n, f, u, p, hp⟩ := h.1.1
  rw [hk] at hp; cases hp; exact ⟨rfl, by simp⟩

/-- A pinned block is of a destructor type. -/
theorem Pinned.arc_ty {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} (h : Pinned R B k) {bl : Blk}
    (hk : B k = some bl) (_ : bl.kind = .arc) : bl.ty.dtorFree = false := by
  obtain ⟨n, f, u, p, kd, rfl, _⟩ := h.shape hk; simp

/-- **The marking sweep keeps the heap's invariant**: it frees only what the
    payload of a block it removes owns. -/
theorem HeapOK.sweepD (hh : HeapOK m) : HeapOK m.sweepD where
  nodup x t h := hh.nodup x t h
  disj x y t u hne h1 h2 := hh.disj x y t u hne h1 h2
  alloc x t h i hi := by
    obtain ⟨ha, hlt⟩ := hh.alloc x t h i hi
    refine ⟨sweepAllocD_true.mpr ⟨ha, ?_⟩, hlt⟩
    rintro ⟨k, bl, hk, _, _, hik⟩
    exact hh.notPay h hi ⟨k, bl, hk, hik⟩
  self x t h := hh.self x t h
  blk k bl hk := by
    -- the block it comes from, which owns the same addresses
    have hsrc : ∃ bl0, m.blk k = some bl0 ∧ bl.tree = bl0.tree ∧
        (Reached (RootsD m.vals m.blk) m.blk k ∨ Pinned m.vals m.blk k) := by
      rcases sweepBlkD_some hk with ⟨h0, hr⟩ | ⟨bl0, h0, _, hp, rfl⟩
      · exact ⟨bl, h0, rfl, Or.inl hr⟩
      · exact ⟨bl0, h0, hp.tree h0, Or.inr hp⟩
    obtain ⟨bl0, hk0, htr, hkeep⟩ := hsrc
    obtain ⟨hkey, hnd, hall⟩ := hh.blk k bl0 hk0
    rw [htr]
    refine ⟨hkey, hnd, fun i hi => ?_⟩
    obtain ⟨ha, hlt, hsl, hoth⟩ := hall i hi
    refine ⟨sweepAllocD_true.mpr ⟨ha, ?_⟩, hlt, hsl, fun k' bl' hk' hk'' => ?_⟩
    · rintro ⟨k', bl', hk', hnr, hnp, hik'⟩
      by_cases he : k' = k
      · subst he; rw [hk0] at hk'; cases hk'
        rcases hkeep with h | h
        · exact hnr h
        · exact hnp h
      · exact hoth k' bl' he hk' hik'
    · rcases sweepBlkD_some hk'' with ⟨h0, _⟩ | ⟨bl1, h0, _, hp, rfl⟩
      · exact hoth k' bl' hk' h0
      · rw [hp.tree h0]; exact hoth k' bl1 hk' h0
  views k' bl hk hv := by
    rcases sweepBlkD_some hk with ⟨hk0, hreach⟩ | ⟨bl0, _, _, _, rfl⟩
    · obtain ⟨k, t, p, rfl, hkb⟩ := hh.views k' _ hk0 hv
      exact ⟨k, t, p, rfl, sweepBlkD_reached hkb
        (.pay hreach hk0 (Or.inl (Or.inl ⟨none, Sub.fst (Sub.refl _)⟩)))⟩
    · cases hv

/-- **The marking sweep keeps the memory invariant.** -/
theorem MInv.sweepD {Γ : Ctx} (hi : MInv m Γ) : MInv m.sweepD Γ := by
  have hi1 := hi.sweepR (R := RootsD m.vals m.blk) rootsD_vals
  have hle := sweepD_blkLe m
  refine hi1.grow rfl hi.heap.sweepD (Nat.le_refl _) hle fun k bl hk => ?_
  rcases sweepBlkD_some hk with ⟨hk0, hr⟩ | ⟨bl0, hk0, _, hp, rfl⟩
  · obtain ⟨h1, h2, h3, h4⟩ := hi1.blocks k bl (Mem.sweepR_blk.mpr ⟨hk0, hr⟩)
    exact ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, (h3 p hp).2.grow hle⟩, h4⟩
  · obtain ⟨h1, h2, h3, h4, h5⟩ := hi.blocks k bl0 hk0
    have hkd := hp.kind hk0
    refine ⟨h1, h2, fun p hpay => ⟨(h3 p hpay).1, ?_⟩, ?_, h5.mark hkd (hp.arc_ty hk0)⟩
    · exact (((h3 p hpay).2.sweep (hp.kept hk0 hpay))).grow hle
    · rcases h4 with h | h
      · rcases hkd with h' | h' <;> (rw [h'] at h; cases h)
      · exact Or.inr h

/-- **The marking sweep keeps `Covers`**: it frees exactly the payloads of
    the blocks it removes. -/
theorem Covers.sweepD (hc : Covers m) : Covers m.sweepD := by
  intro i hi
  obtain ⟨ha, hnu⟩ := sweepAllocD_true.mp hi
  rcases hc i ha with ⟨x, T, hT, hiT⟩ | ⟨k, bl, hk, hik⟩
  · exact Or.inl ⟨x, T, hT, hiT⟩
  · by_cases hr : Reached (RootsD m.vals m.blk) m.blk k
    · exact Or.inr ⟨k, bl, sweepBlkD_reached hk hr, hik⟩
    · by_cases hp : Pinned m.vals m.blk k
      · exact Or.inr ⟨k, bl.mark, sweepBlkD_pinned hk hr hp, by rw [hp.tree hk]; exact hik⟩
      · exact absurd ⟨k, bl, hk, hr, hp, hik⟩ hnu

/-- **The marking sweep keeps the invariant** of a running configuration. -/
theorem Inv.sweepD {Γ : Ctx} {F : List Var} {s : Stmt} (hi : Inv m Γ F s) : Inv m.sweepD Γ F s :=
  { toMInv := hi.toMInv.sweepD
    nvS := hi.nvS
    nvF := hi.nvF
    anch := hi.anch
    spineNd := hi.spineNd
    spineDom := hi.spineDom
    catchOK := CatchOK.of_st (m := m.sweepR (RootsD m.vals m.blk)) (m' := m.sweepD) rfl (Nat.le_refl _)
      (sweepD_blkLe m)
      (hi.catchOK.sweepR (R := RootsD m.vals m.blk) rootsD_vals)
    cover := hi.cover.sweepD
    pinOut := hi.pinOut
    pinIn := hi.pinIn
    dtorOut := hi.dtorOut
    dtorIn := hi.dtorIn }

/-- The packages in memory are the slots' and the blocks', which the marking
    sweep keeps or marks (a marked block owns what it owned and its holders
    read nothing of it); a marked block's destructor is its `arc` block's. -/
theorem MemCodes.sweepD {P : Prog} (h : MemCodes P m) : MemCodes P m.sweepD := by
  refine ⟨h.1, fun k bl fs te ms e cs hk hs => ?_, fun k n f u kd o hk hkd => ?_⟩
  · rcases sweepBlkD_some hk with ⟨hk0, _⟩ | ⟨bl0, hk0, _, hp, rfl⟩
    · exact h.2.1 k bl fs te ms e cs hk0 hs
    · rcases hs with hs | hs
      · rw [hp.tree hk0] at hs; exact h.2.1 k bl0 fs te ms e cs hk0 (.inl hs)
      · rw [Blk.mark_rd] at hs; cases hs
  · rcases sweepBlkD_some hk with ⟨hk0, _⟩ | ⟨bl0, hk0, _, hp, he⟩
    · exact h.2.2 k n f u kd o hk0 hkd
    · obtain ⟨t, kd0, p⟩ := bl0
      simp only [Blk.mark, Blk.mk.injEq] at he
      obtain ⟨rfl, rfl, rfl⟩ := he
      exact h.2.2 k n f u kd0 o hk0 (hp.kind hk0)

/-- **When no slot holds a value and the marking sweep leaves no orphan, it
    leaves no block**: every block it keeps is reached from a pinned
    payload, whose block it leaves an orphan. -/
theorem Mem.sweepD_empty (h : ∀ x o v, m.st x ≠ some ⟨o, some v⟩) (hn : ¬ Orphan m.sweepD) (k : Nat) :
    m.sweepD.blk k = none := by
  -- a root of the marking sweep is a pinned block's payload, and that block is left an orphan
  have hroot : ∀ v, RootsD m.vals m.blk v → False := by
    rintro v ((⟨x, o, hx⟩ | ⟨k0, n, f, u, hk0⟩) | ⟨k0, n, f, u, htop, hk0⟩)
    · exact h x o v hx
    · have hp : Pinned m.vals m.blk k0 := Or.inr ⟨n, f, u, v, hk0⟩
      by_cases hr : Reached (RootsD m.vals m.blk) m.blk k0
      · exact hn ⟨k0, n, f, u, v, sweepBlkD_reached hk0 hr⟩
      · exact hn ⟨k0, n, f, u, v, sweepBlkD_pinned hk0 hr hp⟩
    · have hp : Pinned m.vals m.blk k0 := Or.inl htop
      by_cases hr : Reached (RootsD m.vals m.blk) m.blk k0
      · exact htop.not_reached hr
      · exact hn ⟨k0, n, f, u, v, sweepBlkD_pinned hk0 hr hp⟩
  cases hk : m.sweepD.blk k with
  | none => rfl
  | some bl =>
    exfalso
    rcases sweepBlkD_some hk with ⟨_, hr⟩ | ⟨bl0, hk0, _, hp, rfl⟩
    · have : ∀ {k}, Reached (RootsD m.vals m.blk) m.blk k → False := by
        intro k hr
        induction hr with
        | root hv _ => exact hroot _ hv
        | pay _ _ _ ih => exact ih
      exact this hr
    · obtain ⟨n, f, u, p, he⟩ := hp.mark hk0
      exact hn ⟨k, n, f, u, p, by rw [← he]; exact hk⟩

/-- A block nothing refers to, from the roots nor from any block's payload,
    is reached from none. -/
theorem Reached.none_refers {R : Val → Prop} {B : Nat → Option Blk} {k : Nat}
    (hR : ∀ v, R v → ¬ Refers B v k) (hB : ∀ k' bl', B k' = some bl' → ¬ Refers B bl'.keeps k) :
    ¬ Reached R B k := by
  intro h
  cases h with
  | root hv hr => exact hR _ hv hr
  | pay _ hk hr => exact hB _ _ hk hr

/-- **A share a slot holds keeps its block as it was** (the witness's first
    drop: the clone's scope ends, the other share is still in a slot). -/
theorem Mem.sweepD_keeps {k : Nat} {bl : Blk} (hk : m.blk k = some bl) {x : Var} {o : Bool} {v : Val}
    (hx : m.st x = some ⟨o, some v⟩) (hr : Refers m.blk v k) : m.sweepD.blk k = some bl :=
  sweepBlkD_reached hk (.root (Or.inl (Or.inl ⟨x, o, hx⟩)) hr)

/-- **An `arc` block of a destructor value (Agora #755: or of a drained
    `Vec` of them) that nothing refers to any more is marked `dead`, its
    payload in it** (the witness's last drop): no
    slot's value and no block's payload refers to it, so it is a top orphan. -/
theorem Mem.sweepD_marks {k n f : Nat} {u : Ty} {p : Val}
    (hk : m.blk k = some ⟨Ty.nest n (.dtor f u), .arc, some p⟩)
    (hv : ∀ x o v, m.st x = some ⟨o, some v⟩ → ¬ Refers m.blk v k)
    (hb : ∀ k' bl', m.blk k' = some bl' → ¬ Refers m.blk bl'.keeps k) :
    m.sweepD.blk k = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩ := by
  have hroots : ∀ w, (Roots0 m.vals m.blk w ∨ CandPay m.vals m.blk w) → ¬ Refers m.blk w k := by
    rintro w ((⟨x, o, hx⟩ | ⟨k', n', f', u', hk'⟩) | ⟨k', n', f', u', _, hk'⟩) hr
    · exact hv x o w hx hr
    · exact hb k' _ hk' (by simpa [Blk.keeps] using hr)
    · exact hb k' _ hk' (by simpa [Blk.keeps] using hr)
  have hnr := Reached.none_refers hroots hb
  have htop : TopOrphan m.vals m.blk k :=
    ⟨⟨⟨n, f, u, p, hk⟩, fun h => hnr (h.roots fun _ h => Or.inl h)⟩, hnr⟩
  exact sweepBlkD_pinned hk htop.not_reached (Or.inl htop)

end

end A2
