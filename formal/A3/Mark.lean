import A3.Pres
import A2.Settle

/-! A3 — Agora #755 item 1: the configuration's marking sweep (`Cfg.sweepD`)
keeps the configuration's parts.

It is A2's marking sweep (`Mem.sweepD`, `A2/SweepD.lean`) from the
configuration's roots, every thread's slots and the module globals
(`Cfg.roots`): every thread's view is swept from those roots
(`Mem.sweepDR`), which include its own slots, so A2's facts of it survive
the sweep (`ThreadOK.sweepDR`).  A marked block keeps what it owns, so it
stays in the shared part (`payPart`) until its thread reaps it.  When the
sweep leaves no orphan, every block it leaves is reached from the roots
(`Cfg.sweepD_reached`): what `CInv` asks. -/

namespace A3
open A2

@[simp] theorem Cfg.sweepD_ths (C : Cfg) : C.sweepD.ths = C.ths := rfl
@[simp] theorem Cfg.sweepD_gl (C : Cfg) : C.sweepD.gl = C.gl := rfl
@[simp] theorem Cfg.sweepD_nid (C : Cfg) : C.sweepD.nid = C.nid := rfl
theorem Cfg.sweepD_roots (C : Cfg) : C.sweepD.roots = C.roots := rfl
theorem Cfg.sweepD_rootsBut (C : Cfg) (i : Nat) : C.sweepD.rootsBut i = C.rootsBut i := rfl

/-- A thread's view of the configuration is an A2 store whose blocks are the
    configuration's: an orphan of one is an orphan of the other. -/
theorem Cfg.orphan_view {C : Cfg} {t : Thread} : A2.Orphan (C.view t) ↔ C.Orphan := Iff.rfl

/-! ### Chains through the marked blocks -/

/-- What a value refers to among the marking sweep's blocks, it referred to
    before: a kept block is as it was, and a marked one is read by no one. -/
theorem Refers.of_sweepBlkD {R : Val → Prop} {B : Nat → Option Blk} {v : Val} {k : Nat}
    (h : Refers (sweepBlkD R B) v k) : Refers B v k := by
  rcases h with h | ⟨bl, hk, h⟩
  · exact .inl h
  · rcases sweepBlkD_some hk with ⟨hk0, _⟩ | ⟨bl0, _, _, _, rfl⟩
    · exact .inr ⟨bl, hk0, h⟩
    · rw [Blk.mark_rd] at h
      rcases h with ⟨c, _, hc⟩ | ⟨d, o, l, _, hc⟩ <;> simp [Val.ids] at hc

/-- ... so what a set of roots reaches among them, it reached before. -/
theorem Reached.of_sweepBlkD {R' R : Val → Prop} {B : Nat → Option Blk} {k : Nat}
    (h : Reached R' (sweepBlkD R B) k) : Reached R' B k := by
  induction h with
  | root hv hr => exact .root hv (Refers.of_sweepBlkD hr)
  | pay _ hk hr ih =>
    rcases sweepBlkD_some hk with ⟨hk0, _⟩ | ⟨bl0, hk0, _, _, rfl⟩
    · exact .pay ih hk0 (Refers.of_sweepBlkD hr)
    · exact .pay ih hk0 (by simpa [Blk.keeps] using Refers.of_sweepBlkD hr)

/-- What roots among the marking sweep's reach, they reach among its blocks:
    the chains run through blocks it keeps as they were. -/
theorem Reached.sweepBlkD {R' R : Val → Prop} {B : Nat → Option Blk} (hR : ∀ v, R' v → RootsD R B v)
    {k : Nat} (h : Reached R' B k) : Reached R' (sweepBlkD R B) k := by
  induction h with
  | root hv hr =>
    rename_i v k
    refine .root hv ?_
    rcases hr with h | ⟨bl, hk, h⟩
    · exact Or.inl h
    · exact Or.inr ⟨bl, sweepBlkD_reached hk (.root (hR _ hv) (Or.inr ⟨bl, hk, h⟩)), h⟩
  | pay hr' hk hr ih =>
    rename_i k k' bl
    refine .pay ih (sweepBlkD_reached hk (hr'.roots hR)) ?_
    rcases hr with h | ⟨bl', hk', h⟩
    · exact Or.inl h
    · exact Or.inr ⟨bl', sweepBlkD_reached hk' (.pay (hr'.roots hR) hk (Or.inr ⟨bl', hk', h⟩)), h⟩

/-- **When the marking sweep leaves no orphan, every block it leaves is
    reached from the roots**: one reached from the marking sweep's roots was
    reached from the configuration's (an orphan's payload as a root would
    leave an orphan), and a pinned one is left an orphan. -/
theorem Cfg.sweepD_reached {C : Cfg} (hn : ¬ C.sweepD.Orphan) {k : Nat} {bl : Blk}
    (hk : C.sweepD.blk k = some bl) : Reached C.sweepD.roots C.sweepD.blk k := by
  -- a root of the marking sweep that is not the configuration's leaves an orphan
  have hroot : ∀ v, RootsD C.roots C.blk v → C.roots v := by
    rintro v ((hv | ⟨k0, n, f, u, hk0⟩) | ⟨k0, n, f, u, kd, htop, hk0⟩)
    · exact hv
    · exfalso
      have hp : Pinned C.roots C.blk k0 := Or.inr ⟨n, f, u, v, hk0⟩
      by_cases hr : Reached (RootsD C.roots C.blk) C.blk k0
      · exact hn ⟨k0, n, f, u, v, sweepBlkD_reached hk0 hr⟩
      · exact hn ⟨k0, n, f, u, v, sweepBlkD_pinned hk0 hr hp⟩
    · exfalso
      exact hn ⟨k0, n, f, u, v, sweepBlkD_pinned hk0 htop.not_reached (Or.inl htop)⟩
  rcases sweepBlkD_some hk with ⟨_, hr⟩ | ⟨bl0, hk0, _, hp, rfl⟩
  · have hr' : Reached C.roots C.blk k := hr.of_roots fun v hv _ _ => hroot v hv
    exact Reached.sweepBlkD (fun _ h => Or.inl (Or.inl h)) hr'
  · obtain ⟨n, f, u, p, he⟩ := hp.mark hk0
    exact absurd ⟨k, n, f, u, p, by rw [← he]; exact hk⟩ hn

/-- **An `arc` block of a destructor value (or of a drained `Vec` of them),
    or a lock block of one, its payload in, that nothing refers to any more
    is marked `dead` by the configuration's marking sweep**, its payload in
    it: no thread's slot, no global and no block's payload refers to it.
    (Agora #831: the case `U = {k}` of `Cfg.sweepD_marks_cut`.) -/
theorem Cfg.sweepD_marks {C : Cfg} {k n f : Nat} {u : Ty} {p : Val} {kd : BKind} (hkd : kd = .arc ∨ kd = .lock)
    (hk : C.blk k = some ⟨Ty.nest n (.dtor f u), kd, some p⟩)
    (hv : ∀ v, C.roots v → ¬ Refers C.blk v k)
    (hb : ∀ k' bl', C.blk k' = some bl' → ¬ Refers C.blk bl'.keeps k) :
    C.sweepD.blk k = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩ :=
  sweepBlkD_marks (CutOff.one hv hb) hkd hk rfl

/-- **Agora #831: ... and so is one cut off from the configuration's roots
    together with blocks that still refer to it** (`A2.CutOff`): blocks no
    root refers to, each block whose payload refers to one of them among
    them and pinning nothing (a view, `Blk.Pins`).  So a lock block whose
    last share went while a read guard lived is marked by the sweep that
    ends the guard's drop, though the guard's view, unreached, is still in
    the store and refers to it. -/
theorem Cfg.sweepD_marks_cut {C : Cfg} {U : Nat → Prop} (hc : CutOff C.roots C.blk U) {k n f : Nat} {u : Ty}
    {p : Val} {kd : BKind} (hkd : kd = .arc ∨ kd = .lock)
    (hk : C.blk k = some ⟨Ty.nest n (.dtor f u), kd, some p⟩) (hU : U k) :
    C.sweepD.blk k = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩ :=
  sweepBlkD_marks hc hkd hk hU

/-! ### The parts survive the marking sweep -/

/-- A3.1: a thread's facts survive a marking sweep whose roots include its
    slots (the configuration's, from every thread's and the globals). -/
theorem ThreadOK.sweepDR {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) {R : Val → Prop}
    (hR : ∀ v, m.vals v → R v) : ThreadOK P (m.sweepDR R) s := by
  obtain ⟨Γ, F, Δ, ht, hi, hcd, hsc, hc⟩ := h
  exact ⟨Γ, F, Δ, ht, hi.sweepDR hR, hcd.sweepDR, hsc, hc⟩

/-- The marking sweep's addresses: a live one stays unless the payload of a
    block it removes owns it. -/
theorem Cfg.sweepD_alloc {C : Cfg} {i : Nat} :
    C.sweepD.alloc i = true ↔ C.alloc i = true ∧ ¬ UnreachedD C.roots C.blk i := sweepAllocD_true

/-- An address a block of the marking sweep owns, the same block owned
    before (a marked block owns what it owned). -/
theorem Cfg.sweepD_payIn {C : Cfg} {i : Nat} :
    PayIn C.sweepD.blk i ↔ ∃ k bl, C.blk k = some bl ∧ i ∈ bl.tree.ids ∧
      (Reached (RootsD C.roots C.blk) C.blk k ∨ Pinned C.roots C.blk k) := by
  constructor
  · rintro ⟨k, bl, hk, hik⟩
    rcases sweepBlkD_some hk with ⟨hk0, hr⟩ | ⟨bl0, hk0, _, hp, rfl⟩
    · exact ⟨k, bl, hk0, hik, .inl hr⟩
    · exact ⟨k, bl0, hk0, by rw [← hp.tree hk0]; exact hik, .inr hp⟩
  · rintro ⟨k, bl, hk, hik, hr | hp⟩
    · exact ⟨k, bl, sweepBlkD_reached hk hr, hik⟩
    · by_cases hr : Reached (RootsD C.roots C.blk) C.blk k
      · exact ⟨k, bl, sweepBlkD_reached hk hr, hik⟩
      · exact ⟨k, bl.mark, sweepBlkD_pinned hk hr hp, by rw [hp.tree hk]; exact hik⟩

/-- **The configuration's marking sweep keeps its parts.**  Every thread's
    view loses exactly the payloads of the blocks it removes, none of which
    its own trees hold, and its facts survive that (`ThreadOK.sweepDR`: the
    roots include its slots); a marked block stays in the shared part. -/
theorem CParts.sweepD {P : Prog} {C : Cfg} {ps : List (Nat → Bool)} (hc : CParts P C ps) :
    CParts P C.sweepD ps := by
  -- a kept payload's address is in no removed one
  have hnu : ∀ i k bl, C.blk k = some bl →
      (Reached (RootsD C.roots C.blk) C.blk k ∨ Pinned C.roots C.blk k) → i ∈ bl.tree.ids →
      ¬ UnreachedD C.roots C.blk i := by
    rintro i k bl hk hkeep hi ⟨k', bl', hk', hnr, hnp, hi'⟩
    have := hc.uniq k k' bl bl' i hk hk' hi hi'; subst this
    rcases hkeep with h | h
    · exact hnr h
    · exact hnp h
  have hnu' : ∀ i, PayIn C.sweepD.blk i → ¬ UnreachedD C.roots C.blk i := by
    intro i hp
    obtain ⟨k, bl, hk, hik, hkeep⟩ := Cfg.sweepD_payIn.mp hp
    exact hnu i k bl hk hkeep hik
  have hpay : ∀ i, PayIn C.sweepD.blk i → PayIn C.blk i := by
    intro i hp
    obtain ⟨k, bl, hk, hik, _⟩ := Cfg.sweepD_payIn.mp hp
    exact ⟨k, bl, hk, hik⟩
  -- a payload's address the sweep does not free stays a payload's
  have hstay : ∀ i, PayIn C.blk i → ¬ UnreachedD C.roots C.blk i → PayIn C.sweepD.blk i := by
    rintro i ⟨k, bl, hk, hik⟩ hu
    refine Cfg.sweepD_payIn.mpr ⟨k, bl, hk, hik, ?_⟩
    by_cases hr : Reached (RootsD C.roots C.blk) C.blk k
    · exact .inl hr
    · by_cases hp : Pinned C.roots C.blk k
      · exact .inr hp
      · exact absurd ⟨k, bl, hk, hr, hp, hik⟩ hu
  refine ⟨hc.len, fun i => ?_, hc.disj, fun j a ha i hai hp => hc.pay j a ha i hai (hpay i hp),
    fun k k' bl bl' i hk hk' hi hi' => ?_, fun j t a ht ha => ?_⟩
  · -- every live address is on a part, or a kept payload's
    rw [Cfg.sweepD_alloc]
    constructor
    · rintro ⟨hCi, hu⟩
      rcases (hc.all i).mp hCi with h | h
      · exact .inl h
      · exact .inr (hstay i h hu)
    · rintro (⟨a, ha, hai⟩ | hp)
      · obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp ha
        refine ⟨(hc.all i).mpr (.inl ⟨a, ha, hai⟩), ?_⟩
        rintro ⟨k, bl, hk, _, _, hik⟩
        exact hc.pay j a hj i hai ⟨k, bl, hk, hik⟩
      · exact ⟨(hc.all i).mpr (.inr (hpay i hp)), hnu' i hp⟩
  · -- one payload owns each payload address
    have h1 : ∀ k bl, C.sweepD.blk k = some bl → i ∈ bl.tree.ids → ∃ bl0, C.blk k = some bl0 ∧ i ∈ bl0.tree.ids := by
      intro k bl hk hi
      rcases sweepBlkD_some hk with ⟨hk0, _⟩ | ⟨bl0, hk0, _, hp, rfl⟩
      · exact ⟨bl, hk0, hi⟩
      · exact ⟨bl0, hk0, by rw [← hp.tree hk0]; exact hi⟩
    obtain ⟨b1, h1k, h1i⟩ := h1 k bl hk hi
    obtain ⟨b2, h2k, h2i⟩ := h1 k' bl' hk' hi'
    exact hc.uniq k k' b1 b2 i h1k h2k h1i h2i
  · -- every thread keeps its facts: its view is swept from every thread's slots and the globals
    obtain ⟨hto, hbo⟩ := hc.ok j t a ht ha
    have heq : ownView C.sweepD t a = (ownView C t a).sweepDR C.roots := by
      simp only [ownView, Mem.sweepDR, Cfg.sweepD]
      congr 1
      funext i
      apply Bool.eq_iff_iff.mpr
      rw [sweepAllocD_true]
      simp only [union, Bool.or_eq_true, payPart_iff]
      constructor
      · rintro (hai | hp)
        · refine ⟨.inl hai, ?_⟩
          rintro ⟨k, bl, hk, _, _, hik⟩
          exact hc.pay j a ha i hai ⟨k, bl, hk, hik⟩
        · exact ⟨.inr (hpay i hp), hnu' i hp⟩
      · rintro ⟨hai | hp, hu⟩
        · exact .inl hai
        · exact .inr (hstay i hp hu)
    rw [heq]
    exact ⟨hto.sweepDR fun v ⟨x, o, hx⟩ => .inl ⟨j, t, ht, x, o, hx⟩, hbo.of_st rfl⟩

/-- A3.5's second cut: the marking sweep keeps a lock block holding its
    payload only as it was (a marked one is `dead`). -/
theorem LockHolds.of_sweepD {R : Val → Prop} {B : Nat → Option Blk} {k' k : Nat}
    (h : LockHolds (sweepBlkD R B) k' k) : LockHolds B k' k := by
  obtain ⟨t, p, hk, hs⟩ := h
  rcases sweepBlkD_some hk with ⟨hk0, _⟩ | ⟨bl0, _, _, _, he⟩
  · exact ⟨t, p, hk0, hs⟩
  · exact absurd (congrArg Blk.kind he) (by simp)

/-! ### Agora #755 item 1: the reaps after a thread's step

Thread `i`'s step is followed by its reaps (`CSettle`): each is a step of
thread `i` (`Step.reap`, on its view), which moves an orphan's payload to a
fresh slot of thread `i`, so its addresses leave the shared part for thread
`i`'s (`CParts.thread_of`, whose other threads' facts survive the payload
leaving the shared part by `ThreadOK.move`, as a lock's check-out), and each
is ended by the marking sweep (`CParts.sweepD`).  So the parts survive the
whole configuration step, and since it ends with the marking sweep leaving
no orphan, every block it leaves is reached from the roots. -/

/-- A thread's step written back, and the marking sweep after it, keep the
    parts. -/
theorem CParts.putD {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) (hR : RestrictLemma P)
    {C : Cfg} {ps : List (Nat → Bool)} (hc : CParts P C ps) {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt}
    (hi : C.ths[i]? = some t) (hst : Step P (C.view t) t.s (.ok m' s')) :
    ∃ ps', CParts P (C.put i m' s').sweepD ps' := by
  obtain ⟨ps', h⟩ := hc.thread_of hP hPc hR hi hst
  exact ⟨ps', h.sweepD⟩

/-- **The reaps keep the parts.** -/
theorem CSettle.parts {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) (hR : RestrictLemma P)
    {i : Nat} {C C' : Cfg} (h : CSettle P i C C') (hc : ∃ ps, CParts P C ps) : ∃ ps, CParts P C' ps := by
  induction h with
  | done _ => exact hc
  | reap hi hs _ _ ih =>
    obtain ⟨ps, hc⟩ := hc
    exact ih (hc.putD hP hPc hR hi hs)

/-- The reaps end at a marking sweep's configuration. -/
theorem CSettle.swept {P : Prog} {i : Nat} {C C' : Cfg} (h : CSettle P i C C') (hC : ∃ W : Cfg, C = W.sweepD) :
    ∃ W : Cfg, C' = W.sweepD := by
  induction h with
  | done _ => exact hC
  | reap _ _ _ _ ih => exact ih ⟨_, rfl⟩

/-- **A thread's step, the marking sweep after it and its reaps keep the
    configuration invariant** (Agora #755 item 1). -/
theorem CInv.thread_of {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) (hR : RestrictLemma P)
    {C : Cfg} (h : CInv P C) {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt} {C' : Cfg}
    (hi : C.ths[i]? = some t) (hst : Step P (C.view t) t.s (.ok m' s'))
    (hse : CSettle P i (C.put i m' s').sweepD C') : CInv P C' := by
  obtain ⟨ps, hc, _⟩ := h
  obtain ⟨ps', hc'⟩ := hse.parts hP hPc hR (hc.putD hP hPc hR hi hst)
  have hno := hse.noOrphan
  obtain ⟨W, rfl⟩ := hse.swept ⟨_, rfl⟩
  exact ⟨ps', hc', fun k bl hk => Cfg.sweepD_reached hno hk⟩

/-! ### No race, with the reaps

The sweeps that end a thread's step free only payloads no other thread
reaches: what the roots after the step reach stays reached through the reaps
(each adds a slot of thread `i` holding what the orphan's payload held, and
no root reaches an orphan, so no chain runs through the block it empties)
and through the marking sweeps (which keep every block the roots reach). -/

theorem upd_at {α : Type} (f : Nat → α) (k : Nat) (v : α) : upd f k v k = v := by simp [upd]

/-- Block `d` of `B` is an orphan: `dead`, its payload in it. -/
def OrphanAt (B : Nat → Option Blk) (d : Nat) : Prop :=
  ∃ n f u p, B d = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩

/-- What a set of roots reaches once a reap emptied its orphan, it reached
    before: the emptied block holds nothing and is read by no one. -/
theorem Reached.of_reaped {R : Val → Prop} {B : Nat → Option Blk} {kr : Nat} {ty : Ty} {k : Nat}
    (h : Reached R (upd B kr (some ⟨ty, .dead, none⟩)) k) : Reached R B k := by
  have href : ∀ {v : Val} {k : Nat}, Refers (upd B kr (some ⟨ty, .dead, none⟩)) v k → Refers B v k := by
    intro v k hr
    rcases hr with h | ⟨bl, hk, h⟩
    · exact .inl h
    · by_cases he : k = kr
      · rw [he, upd_at] at hk
        cases hk
        rcases h with ⟨c, _, hc⟩ | ⟨d, o, l, _, hc⟩ <;> simp [Blk.rd, Val.ids] at hc
      · exact .inr ⟨bl, by rw [upd_ne _ _ he] at hk; exact hk, h⟩
  induction h with
  | root hv hr => exact .root hv (href hr)
  | @pay k k' bl _ hk hr ih =>
    by_cases he : k' = kr
    · rw [he, upd_at] at hk
      cases hk
      exact absurd (href hr) (by simpa [Blk.keeps] using (Refers.not_int (B := B) (n := 0) (k := k)))
    · exact .pay ih (by rw [upd_ne _ _ he] at hk; exact hk) (href hr)

/-- ... and what it reached before, it reaches after, when it did not reach
    the emptied block: no chain ran through it. -/
theorem Reached.to_reaped {R : Val → Prop} {B : Nat → Option Blk} {kr : Nat} {b : Option Blk}
    (hkr : ¬ Reached R B kr) {k : Nat} (h : Reached R B k) : Reached R (upd B kr b) k := by
  induction h with
  | @root v k hv hr =>
    have hne : k ≠ kr := fun he => hkr (he ▸ .root hv hr)
    refine .root hv ?_
    rcases hr with h | ⟨bl, hk, h⟩
    · exact .inl h
    · exact .inr ⟨bl, by rw [upd_ne _ _ hne]; exact hk, h⟩
  | @pay k k' bl hr' hk hr ih =>
    have hne' : k' ≠ kr := fun he => hkr (he ▸ hr')
    have hne : k ≠ kr := fun he => hkr (he ▸ .pay hr' hk hr)
    refine .pay ih (by rw [upd_ne _ _ hne']; exact hk) ?_
    rcases hr with h | ⟨bl', hk', h⟩
    · exact .inl h
    · exact .inr ⟨bl', by rw [upd_ne _ _ hne]; exact hk', h⟩

/-- What keeps address `a` live through thread `q`'s reaps and the marking
    sweeps after them: the parts; roots that include `R`; no orphan that `R`
    reaches; and `a` live, owned by no payload or by one `R` reaches. -/
structure LiveThru (P : Prog) (R : Val → Prop) (a : Nat) (Y : Cfg) : Prop where
  parts : ∃ ps, CParts P Y ps
  roots : ∀ v, R v → Y.roots v
  orph  : ∀ d, OrphanAt Y.blk d → ¬ Reached R Y.blk d
  live  : Y.alloc a = true
  held  : ¬ PayIn Y.blk a ∨ ∃ k bl, Y.blk k = some bl ∧ a ∈ bl.tree.ids ∧ Reached R Y.blk k

/-- The marking sweep keeps it: it keeps every block the roots reach, and an
    orphan it leaves was one, or one it marked, which no root reached. -/
theorem LiveThru.sweepD {P : Prog} {R : Val → Prop} {a : Nat} {Y : Cfg} (h : LiveThru P R a Y) :
    LiveThru P R a Y.sweepD := by
  obtain ⟨ps, hc⟩ := h.parts
  have hRD : ∀ v, R v → RootsD Y.roots Y.blk v := fun v hv => Or.inl (Or.inl (h.roots v hv))
  refine ⟨⟨ps, hc.sweepD⟩, h.roots, fun d ⟨n, f, u, p, hd⟩ hr => ?_, ?_, ?_⟩
  · have hr0 : Reached R Y.blk d := Reached.of_sweepBlkD hr
    rcases sweepBlkD_some hd with ⟨hd0, _⟩ | ⟨bl0, _, hnr, _, _⟩
    · exact h.orph d ⟨n, f, u, p, hd0⟩ hr0
    · exact hnr (hr0.roots hRD)
  · refine Cfg.sweepD_alloc.mpr ⟨h.live, ?_⟩
    rintro ⟨k', bl', hk', hnr, _, hik'⟩
    rcases h.held with hnp | ⟨k, bl, hk, hik, hr⟩
    · exact hnp ⟨k', bl', hk', hik'⟩
    · have := hc.uniq k k' bl bl' a hk hk' hik hik'; subst this
      exact hnr (hr.roots hRD)
  · rcases h.held with hnp | ⟨k, bl, hk, hik, hr⟩
    · refine .inl fun hp => hnp ?_
      obtain ⟨k, bl, hk, hik, _⟩ := Cfg.sweepD_payIn.mp hp
      exact ⟨k, bl, hk, hik⟩
    · exact .inr ⟨k, bl, sweepBlkD_reached hk (hr.roots hRD), hik, Reached.sweepBlkD hRD hr⟩

/-- A reap of thread `q` keeps it: the payload goes to a fresh slot of `q`
    (every slot of `q` stays), the emptied block was an orphan, which `R`
    did not reach, and the addresses stay live. -/
theorem LiveThru.reap {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) (hR : RestrictLemma P)
    {R : Val → Prop} {a : Nat} {Z : Cfg} (h : LiveThru P R a Z) {q : Nat} {t : Thread} {m1 : Mem} {s1 : Stmt}
    (hq : Z.ths[q]? = some t) (hst : Step P (Z.view t) t.s (.ok m1 s1)) (hrm : ReapMem (Z.view t) m1) :
    LiveThru P R a (Z.put q m1 s1) := by
  obtain ⟨ps, hc⟩ := h.parts
  obtain ⟨aq, haq⟩ := part_of hc.len hq
  obtain ⟨hto, _⟩ := hc.ok q t aq hq haq
  obtain ⟨Γ, F, Δ, _, hinv, _, _, _⟩ := hto
  have hlt : q < Z.ths.length := (List.getElem?_eq_some_iff.mp hq).1
  obtain ⟨kr, n, f, u, p, hkr, rfl⟩ := hrm
  have hkrR : ¬ Reached R Z.blk kr := h.orph kr ⟨n, f, u, p, hkr⟩
  have hnv : ∀ x, (t.st x).isSome = true → x < t.nv := fun x hx => hinv.nvSt x hx
  have hblk : ∀ k, (Z.put q {(Mem.set (Z.view t) (Z.view t).nv ⟨true, some p⟩) with
      nv := (Z.view t).nv + 1, blk := upd (Z.view t).blk kr (some ⟨Ty.nest n (.dtor f u), .dead, none⟩)} s1).blk k =
      upd Z.blk kr (some ⟨Ty.nest n (.dtor f u), .dead, none⟩) k := fun _ => rfl
  refine ⟨hc.thread_of hP hPc hR hq hst, fun v hv => ?_, fun d ⟨n', f', u', p', hd⟩ hr => ?_, h.live, ?_⟩
  · -- every root stays: another thread's slots and the globals as they were, `q`'s and a new one
    rcases h.roots v hv with ⟨j, tj, hj, x, o, hx⟩ | hg
    · by_cases hjq : j = q
      · rw [hjq, hq] at hj; cases hj
        have hxn : x ≠ t.nv := fun he => by
          have := hnv x (by rw [hx]; rfl)
          rw [he] at this; exact Nat.lt_irrefl _ this
        refine .inl ⟨q, ⟨upd t.st t.nv (some ⟨true, some p⟩), t.nv + 1, s1⟩, ?_, x, o, ?_⟩
        · simp [Cfg.put, hlt, Cfg.view, Mem.set]
        · show upd t.st t.nv _ x = _
          rw [upd_ne _ _ hxn]; exact hx
      · exact .inl ⟨j, tj, by simp only [Cfg.put]; rw [List.getElem?_set_ne (Ne.symm hjq)]; exact hj, x, o, hx⟩
    · exact .inr hg
  · -- an orphan after the reap was one before
    rw [hblk] at hd
    have hne : d ≠ kr := fun he => by rw [he, upd_at] at hd; simp at hd
    rw [upd_ne _ _ hne] at hd
    exact h.orph d ⟨n', f', u', p', hd⟩ (Reached.of_reaped (ty := Ty.nest n (.dtor f u)) hr)
  · rcases h.held with hnp | ⟨k, bl, hk, hik, hr⟩
    · refine .inl fun ⟨k, bl, hk, hik⟩ => hnp ⟨k, bl, ?_, hik⟩
      rw [hblk] at hk
      by_cases he : k = kr
      · rw [he, upd_at] at hk
        cases hk; simp [Blk.tree] at hik
      · rw [upd_ne _ _ he] at hk; exact hk
    · have hne : k ≠ kr := fun he => hkrR (he ▸ hr)
      exact .inr ⟨k, bl, by rw [hblk, upd_ne _ _ hne]; exact hk, hik, Reached.to_reaped hkrR hr⟩

/-- **What the roots after thread `q`'s step reach stays live through its
    reaps.** -/
theorem LiveThru.settle {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) (hR : RestrictLemma P)
    {R : Val → Prop} {a : Nat} {q : Nat} {Z C' : Cfg} (hse : CSettle P q Z C') (h : LiveThru P R a Z) :
    C'.alloc a = true := by
  induction hse with
  | done _ => exact h.live
  | reap hi hs hrm _ ih => exact ih ((h.reap hP hPc hR hi hs hrm).sweepD)

/-- **What a thread's next step touches**: an address of its own part; a
    read of a payload its own slots reach; or (what the sweeps that end it
    free) a payload no other thread's slots, nor (A3.6) a global, reach. -/
theorem CParts.ctouch {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) (hR : RestrictLemma P) {C : Cfg}
    {ps : List (Nat → Bool)} (hc : CParts P C ps) (hno : ¬ C.Orphan) {q : Nat} {tq : Thread}
    {aq : Nat → Bool} (hq : C.ths[q]? = some tq) (haq : ps[q]? = some aq) {a : Nat} {b : Bool}
    (h : CTouch P C q tq a b) :
    aq a = true ∨ ∃ k bl, C.blk k = some bl ∧ a ∈ bl.tree.ids ∧
      ((b = false ∧ Reached (C.view tq).vals C.blk k) ∨ ¬ Reached (C.rootsBut q) C.blk k) := by
  obtain ⟨hto, hbo⟩ := hc.ok q tq aq hq haq
  cases h with
  | step ht =>
    rcases touch_seen ht (m1 := ownView C tq aq) rfl rfl (TypedAt.of_threadOK hto) with
      h1 | ⟨hb, h1 | ⟨k, bl, hk, hak, hr⟩⟩
    · exact .inl (owned_part hto h1)
    · exact .inl (owned_part hto h1)
    · obtain ⟨k0, bl0, hk0, hak0, hr0⟩ := hto.blocksAt.views.rd_reached hk hak hr
      exact .inr ⟨k0, bl0, hk0, hak0, .inl ⟨hb, hr0⟩⟩
  | sweep hs =>
    obtain ⟨m', s', C', hst, hse, _, hma, hsw⟩ := hs
    obtain ⟨ps0, hc0⟩ := hc.thread_of hP hPc hR hq hst
    have hno' : ∀ d, ¬ OrphanAt m'.blk d := fun d ⟨n, f, u, p, hd⟩ =>
      Step.noOrphan hst (fun ⟨k, n, f, u, p, hk⟩ => hno ⟨k, n, f, u, p, hk⟩) ⟨d, n, f, u, p, hd⟩
    -- were `a` owned by no payload, or by one the roots after the step reach, it would stay live
    have hlive : (¬ PayIn m'.blk a ∨ ∃ k bl, m'.blk k = some bl ∧ a ∈ bl.tree.ids ∧
        Reached (C.put q m' s').roots m'.blk k) → False := fun hh => by
      have hl : LiveThru P (C.put q m' s').roots a (C.put q m' s') :=
        ⟨⟨ps0, hc0⟩, fun _ h => h, fun d hd _ => hno' d hd, hma, hh⟩
      have := LiveThru.settle hP hPc hR hse hl.sweepD
      rw [hsw] at this; cases this
    by_cases hp : PayIn m'.blk a
    · obtain ⟨k, bl, hk, hak⟩ := hp
      have hnr : ¬ Reached (C.put q m' s').roots m'.blk k := fun hr => hlive (.inr ⟨k, bl, hk, hak, hr⟩)
      -- A3.2: the same block's payload owned it before the step, or the
      -- thread did (a new block's, or a lock's given back)
      rcases Step.payAt hst (hbo.of_st rfl) k a ⟨bl, hk, hak⟩ with ⟨bl0, hk0, hak0⟩ | h1
      · exact .inr ⟨k, bl0, hk0, hak0, .inr fun hr =>
          hnr (hr.step hst (fun v hv => Cfg.rootsBut_put (Step.gl hst) hv) (fun v hv => Cfg.put_vals hq hv))⟩
      · exact .inl (owned_part hto h1)
    · exact (hlive (.inl hp)).elim

/-- **No race**: two threads never touch one address, one of them writing.
    A write is to the writer's own part, or (the sweeps' frees) to a payload
    no other thread reaches; what another thread touches is on its own part,
    or a payload its own slots reach, or one the sweeps after its own step
    would free — and a block is reached from some thread or (A3.6) a global
    (`CInv`), so not two threads' sweeps free it.  (Agora #755 item 1: a
    reaped payload is on the reaping thread's part from then on, so the
    destructor's reads and writes, its later steps', are of its own part.) -/
theorem CInv.raceFree {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) (hR : RestrictLemma P) {C : Cfg}
    (h : CInv P C) (hno : ¬ C.Orphan) : ¬ AddrRace P C := by
  rintro ⟨i, j, ti, tj, a, w, hij, hi, hj, hti, htj⟩
  obtain ⟨ps, hc, hreach⟩ := h
  obtain ⟨ai, hai⟩ := part_of hc.len hi
  obtain ⟨aj, haj⟩ := part_of hc.len hj
  rcases hc.ctouch hP hPc hR hno hi hai hti with h1 | ⟨k, bl, hk, hak, ⟨hf, _⟩ | hnr⟩
  · -- `i` writes its own part
    have hnp : ¬ PayIn C.blk a := hc.pay i ai hai a h1
    rcases hc.ctouch hP hPc hR hno hj haj htj with h2 | ⟨k', bl', hk', hak', _⟩
    · rw [hc.disj i j ai aj hij hai haj a h1] at h2; cases h2
    · exact hnp ⟨k', bl', hk', hak'⟩
  · cases hf
  · -- `i`'s sweeps free a payload no other thread reaches
    rcases hc.ctouch hP hPc hR hno hj haj htj with h2 | ⟨k', bl', hk', hak', ⟨_, hr'⟩ | hnr'⟩
    · exact hc.pay j aj haj a h2 ⟨k, bl, hk, hak⟩
    · have := hc.uniq k k' bl bl' a hk hk' hak hak'; subst this
      exact hnr (hr'.roots (fun v ⟨x, o, hx⟩ => .inl ⟨j, tj, Ne.symm hij, hj, x, o, hx⟩))
    · have := hc.uniq k k' bl bl' a hk hk' hak hak'; subst this
      have hr0 : Reached (fun v => (C.view ti).vals v ∨ C.rootsBut i v) C.blk k :=
        (hreach k bl hk).roots (fun v hv => Cfg.roots_split hi hv)
      rcases Reached.or hr0 with h3 | h3
      · exact hnr' (h3.roots (fun v ⟨x, o, hx⟩ => .inl ⟨i, ti, hij, hi, x, o, hx⟩))
      · exact hnr h3

/-! ### The reaps can always be taken, and end

So that `TStep.thread` asks nothing of a run it cannot give, every A2 step
of a thread extends to a configuration step: the reaps can always be taken
(a typed thread's statement has a source redex, `StmtT.reapable`, and an
orphan's payload holds no cell share, `MInv.blocks`), and they end (each
empties an orphan, and the marking sweep makes no block that holds a
destructor value at its top: A2's count, `dtorCount`, falls). -/

/-- The marking sweep makes no block that holds a destructor value at its
    top: it keeps or marks them. -/
theorem DtorBlk.of_sweepBlkD {R : Val → Prop} {B : Nat → Option Blk} {k : Nat}
    (h : DtorBlk (sweepBlkD R B) k) : DtorBlk B k := by
  obtain ⟨n, f, u, kd, p, hk, hkd⟩ := h
  rcases sweepBlkD_some hk with ⟨h0, _⟩ | ⟨bl0, h0, _, hp, _⟩
  · exact ⟨n, f, u, kd, p, h0, hkd⟩
  · obtain ⟨n', f', u', p', kd', rfl, hkd'⟩ := hp.shape h0
    exact ⟨n', f', u', kd', p', h0, hkd'⟩

theorem dtorCount_sweepBlkD (R : Val → Prop) (B : Nat → Option Blk) (n : Nat) :
    dtorCount (sweepBlkD R B) n ≤ dtorCount B n := by
  unfold dtorCount
  exact countP_le_of fun k _ h => by simp only [decide_eq_true_eq] at h ⊢; exact DtorBlk.of_sweepBlkD h

/-- **A thread of a configuration with an orphan can reap it**, and the reap
    lowers the count of blocks holding a destructor value. -/
theorem CParts.reaps {P : Prog} {Z : Cfg} {ps : List (Nat → Bool)} (hc : CParts P Z ps) {i : Nat}
    {t : Thread} (hi : Z.ths[i]? = some t) (ho : Z.Orphan) :
    ∃ m1 s1, Step P (Z.view t) t.s (.ok m1 s1) ∧ ReapMem (Z.view t) m1 ∧
      dtorCount m1.blk Z.nid < dtorCount Z.blk Z.nid := by
  obtain ⟨a, ha⟩ := part_of hc.len hi
  obtain ⟨hto, _⟩ := hc.ok i t a hi ha
  obtain ⟨Γ, F, Δ, ht, hinv, _, _, _⟩ := hto
  obtain ⟨k, n, f, u, p, hk⟩ := ho
  obtain ⟨_, _, hpay, hcell, _⟩ := hinv.blocks k _ hk
  have hnc : (Ty.nest n (.dtor f u)).hasCell = false := by
    rcases hcell with h | h
    · cases h
    · exact h
  obtain ⟨m1, s1, hs, hrm⟩ := ht.reapable.reap (m := Z.view t) hk fun c => (hpay p rfl).1.noCell_hasCell hnc
  refine ⟨m1, s1, hs, hrm, ?_⟩
  obtain ⟨k', n', f', u', p', hk', rfl⟩ := hrm
  have hrmo : ReapMem (ownView Z t a) { ((ownView Z t a).set (ownView Z t a).nv ⟨true, some p'⟩) with
      nv := (ownView Z t a).nv + 1,
      blk := upd (ownView Z t a).blk k' (some ⟨Ty.nest n' (.dtor f' u'), .dead, none⟩) } :=
    ⟨k', n', f', u', p', hk', rfl⟩
  have := dtorCount_reap hinv.heap hrmo
  exact this

/-- **The reaps after a thread's step can always be taken, and end**: from a
    configuration with its parts, thread `i` reaches one with no orphan. -/
theorem CSettle.total {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) (hR : RestrictLemma P)
    {Z : Cfg} {ps : List (Nat → Bool)} (hc : CParts P Z ps) {i : Nat} {t : Thread} (hi : Z.ths[i]? = some t) :
    ∃ C', CSettle P i Z C' := by
  suffices h : ∀ N (Z : Cfg) (ps : List (Nat → Bool)) (t : Thread), dtorCount Z.blk Z.nid < N →
      CParts P Z ps → Z.ths[i]? = some t → ∃ C', CSettle P i Z C' from
    h _ Z ps t (Nat.lt_succ_self _) hc hi
  intro N
  induction N with
  | zero => intro _ _ _ h; cases h
  | succ N ih =>
    intro Z ps t hN hc hi
    by_cases ho : Z.Orphan
    · obtain ⟨m1, s1, hs, hrm, hlt⟩ := hc.reaps hi ho
      obtain ⟨ps', hc'⟩ := hc.putD hP hPc hR hi hs
      have hnid : m1.nid = Z.nid := by obtain ⟨_, _, _, _, _, _, rfl⟩ := hrm; rfl
      have hlen : i < Z.ths.length := (List.getElem?_eq_some_iff.mp hi).1
      have hi' : ((Z.put i m1 s1).sweepD).ths[i]? = some ⟨m1.st, m1.nv, s1⟩ := by
        simp [Cfg.sweepD, Cfg.put, hlen]
      have hN' : dtorCount (Z.put i m1 s1).sweepD.blk (Z.put i m1 s1).sweepD.nid < N := by
        have h1 := dtorCount_sweepBlkD (Z.put i m1 s1).roots m1.blk m1.nid
        show dtorCount (sweepBlkD (Z.put i m1 s1).roots m1.blk) m1.nid < N
        rw [hnid] at h1 ⊢
        omega
      obtain ⟨C', hC'⟩ := ih _ ps' _ hN' hc' hi'
      exact ⟨C', .reap hi hs hrm hC'⟩
    · exact ⟨Z, .done ho⟩

/-- **Every A2 step of a thread is one of the configuration's** (when it is
    no spawn's): the reaps after it can be taken (`CSettle.total`), so the
    eager reaping of `TStep.thread` blocks no thread. -/
theorem TStep.thread_total {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) (hR : RestrictLemma P)
    {spawn : Nat → Bool} {C : Cfg} (h : CInv P C) {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt}
    (hi : C.ths[i]? = some t) (hsp : ¬ SpawnRedex spawn t.s) (hst : Step P (C.view t) t.s (.ok m' s')) :
    ∃ C', TStep P spawn C C' := by
  obtain ⟨ps, hc, _⟩ := h
  obtain ⟨ps', hc'⟩ := hc.putD hP hPc hR hi hst
  have hlen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  have hi' : ((C.put i m' s').sweepD).ths[i]? = some ⟨m'.st, m'.nv, s'⟩ := by
    simp [Cfg.sweepD, Cfg.put, hlen]
  obtain ⟨C', hse⟩ := CSettle.total hP hPc hR hc' hi'
  exact ⟨C', .thread hi hsp hst hse⟩

/-! ### The thread that drops the last share runs the destructor -/

/-- A block emptied by a reap, or gone. -/
def Emptied (B : Nat → Option Blk) (k : Nat) (ty : Ty) : Prop :=
  B k = none ∨ B k = some ⟨ty, .dead, none⟩

/-- The marking sweep keeps an emptied block emptied (or removes it). -/
theorem Emptied.sweepD {C : Cfg} {k : Nat} {ty : Ty} (h : Emptied C.blk k ty) : Emptied C.sweepD.blk k ty := by
  unfold Emptied at h ⊢
  cases hk : C.sweepD.blk k with
  | none => exact .inl rfl
  | some bl =>
    right
    rcases sweepBlkD_some hk with ⟨hk0, _⟩ | ⟨bl0, hk0, _, _, rfl⟩
    · rcases h with h | h <;> rw [h] at hk0 <;> cases hk0; rfl
    · rcases h with h | h <;> rw [h] at hk0 <;> cases hk0; rfl

/-- **What a reap of the run left, the run's end keeps**: a later reap of
    thread `i` binds its payload in a slot above every slot it had, and
    empties another block; the marking sweep changes no slot.  So a slot of
    thread `i` below its next fresh variable keeps its value, and an emptied
    block stays emptied or is gone. -/
theorem CSettle.keeps_slot {P : Prog} {i : Nat} {Z C' : Cfg} (h : CSettle P i Z C') {t : Thread} {x : Var}
    {sl : Slot} {k : Nat} {ty : Ty} (hi : Z.ths[i]? = some t) (hx : t.st x = some sl) (hxn : x < t.nv)
    (hk : Emptied Z.blk k ty) :
    ∃ t', C'.ths[i]? = some t' ∧ t'.st x = some sl ∧ t.nv ≤ t'.nv ∧ Emptied C'.blk k ty := by
  induction h generalizing t with
  | done _ => exact ⟨t, hi, hx, Nat.le_refl _, hk⟩
  | @reap Z C'' t2 m1 s1 hi2 _ hrm _ ih =>
    have he := Option.some.inj (hi.symm.trans hi2)
    subst he
    obtain ⟨kr, n', f', u', p', hkr, hm1⟩ := hrm
    have hlen : i < Z.ths.length := (List.getElem?_eq_some_iff.mp hi).1
    have hne : kr ≠ k := by
      rintro rfl
      rcases hk with h | h <;> (have hkr' : Z.blk kr = _ := hkr; rw [h] at hkr'; simp at hkr')
    have hk1 : Emptied (Z.put i m1 s1).blk k ty := by
      unfold Emptied
      show m1.blk k = none ∨ m1.blk k = _
      rw [hm1]
      show upd Z.blk kr _ k = none ∨ upd Z.blk kr _ k = _
      rw [upd_ne _ _ (Ne.symm hne)]; exact hk
    have hxn' : x ≠ t.nv := Nat.ne_of_lt hxn
    have hnv : m1.nv = t.nv + 1 := by rw [hm1]; rfl
    obtain ⟨t', h1, h2, h3, h4⟩ := ih (t := ⟨m1.st, m1.nv, s1⟩)
      (by simp [Cfg.sweepD, Cfg.put, hlen])
      (by show m1.st x = _; rw [hm1]; show upd t.st t.nv _ x = _; rw [upd_ne _ _ hxn']; exact hx)
      (by show x < m1.nv; rw [hnv]; exact Nat.lt_succ_of_lt hxn) hk1.sweepD
    exact ⟨t', h1, h2, by simp only at h3; omega, h4⟩

/-- **An orphan the reaps start from is reaped by thread `i`, in this run of
    reaps**: at the run's end `C'` (the configuration step's result), a slot
    of thread `i` at or above its next fresh variable where the run began
    (so one this run made) holds the orphan's payload, owned, and its block
    is emptied or gone.  (Until its reap it stays an orphan, its payload in
    it: no other step runs, and the marking sweep keeps it; after it, the
    later reaps add slots above it and touch no emptied block.) -/
theorem CSettle.reaps_block {P : Prog} {i : Nat} {Z C' : Cfg} (h : CSettle P i Z C') {k n f : Nat}
    {u : Ty} {p : Val} (hk : Z.blk k = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩) {t0 : Thread}
    (hi0 : Z.ths[i]? = some t0) :
    ∃ (t' : Thread) (x : Var), C'.ths[i]? = some t' ∧ t'.st x = some ⟨true, some p⟩ ∧ t0.nv ≤ x ∧
      Emptied C'.blk k (Ty.nest n (.dtor f u)) := by
  induction h generalizing t0 with
  | done hn => exact absurd ⟨k, n, f, u, p, hk⟩ hn
  | @reap Z C'' t m1 s1 hi hs hrm hrest ih =>
    have he0 := Option.some.inj (hi0.symm.trans hi)
    subst he0
    obtain ⟨kr, n', f', u', p', hkr, hm1⟩ := hrm
    have hlen : i < Z.ths.length := (List.getElem?_eq_some_iff.mp hi0).1
    have hi1 : ((Z.put i m1 s1).sweepD).ths[i]? = some ⟨m1.st, m1.nv, s1⟩ := by
      simp [Cfg.sweepD, Cfg.put, hlen]
    by_cases he : kr = k
    · subst he
      have hkr' : Z.blk kr = _ := hkr
      have he2 := hkr'.symm.trans hk
      simp only [Option.some.injEq, Blk.mk.injEq] at he2
      obtain ⟨hty, -, rfl⟩ := he2
      have hE : Emptied (Z.put i m1 s1).blk kr (Ty.nest n (.dtor f u)) := by
        right; show m1.blk kr = _; rw [hm1]; show upd Z.blk kr _ kr = _; rw [upd_at, hty]
      have hnv : m1.nv = t0.nv + 1 := by rw [hm1]; rfl
      obtain ⟨t', h1, h2, h3, h4⟩ := hrest.keeps_slot (x := t0.nv) (sl := ⟨true, some p'⟩) hi1
        (by show m1.st t0.nv = _; rw [hm1]; simp [Mem.set, upd, Cfg.view]) (by show t0.nv < m1.nv; omega)
        hE.sweepD
      exact ⟨t', t0.nv, h1, h2, Nat.le_refl _, h4⟩
    · -- another orphan was reaped: this one is as it was, and the marking sweep keeps it
      have hk1 : (Z.put i m1 s1).blk k = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩ := by
        show m1.blk k = _
        rw [hm1]
        show upd Z.blk kr _ k = _
        rw [upd_ne _ _ (Ne.symm he)]; exact hk
      have hp : Pinned (Z.put i m1 s1).roots (Z.put i m1 s1).blk k := Or.inr ⟨n, f, u, p, hk1⟩
      have hk2 : (Z.put i m1 s1).sweepD.blk k = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩ := by
        by_cases hr : Reached (RootsD (Z.put i m1 s1).roots (Z.put i m1 s1).blk) (Z.put i m1 s1).blk k
        · exact sweepBlkD_reached hk1 hr
        · exact sweepBlkD_pinned hk1 hr hp
      obtain ⟨t', x, h1, h2, h3, h4⟩ := ih hk2 hi1
      have hnv : m1.nv = t0.nv + 1 := by rw [hm1]; rfl
      exact ⟨t', x, h1, h2, by simp only at h3; omega, h4⟩

/-- **Agora #755 item 1: the thread whose step drops the last share runs the
    destructor.**  Thread `i`'s step (to `m'`, `s'`) leaves an `arc` block of
    a destructor value (or of a drained `Vec` of them), or a lock block of
    one, its payload in it, cut off from the roots (`A2.CutOff`, a set `U`
    of blocks holding `k`): no thread's slot and no module global refers to
    a block of `U`, and a block whose payload refers to one is in `U` and
    pins nothing (it is no orphan to be and no `dead` block).  Then the
    configuration's marking sweep that ends the step marks it `dead`, its
    payload in it, and in the result `C'` of this configuration step
    (`TStep.thread`'s, whose reaps, `CSettle`, are all thread `i`'s, before
    any other thread runs) a fresh slot of thread `i` (at or above `m'.nv`,
    so made by its reaps) owns the payload and the block is emptied or
    gone: a reap of thread `i` bound it there, in a destructor frame of `f`
    at its redex (`Step.reap`).  Agora #831: before, the lemma asked that no
    block of `m'` at all refer to `k` (`U = {k}`, `CutOff.one`); a block
    that refers to it but is itself cut off, such as the view a read guard
    dropped after the lock's last share leaves, unreached and not yet
    swept (`A3.RwDtorWitness.guard_drop_reaps`), is covered now. -/
theorem TStep.last_drop_reaps {P : Prog} {C : Cfg} {i : Nat} {m' : Mem} {s' : Stmt} {C' : Cfg}
    (hlen : i < C.ths.length)
    (hse : CSettle P i (C.put i m' s').sweepD C') {k n f : Nat} {u : Ty} {p : Val} {kd : BKind}
    (hkd : kd = .arc ∨ kd = .lock) (hk : m'.blk k = some ⟨Ty.nest n (.dtor f u), kd, some p⟩)
    {U : Nat → Prop} (hc : CutOff (C.put i m' s').roots m'.blk U) (hU : U k) :
    (C.put i m' s').sweepD.blk k = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩ ∧
      ∃ (t' : Thread) (x : Var), C'.ths[i]? = some t' ∧ t'.st x = some ⟨true, some p⟩ ∧ m'.nv ≤ x ∧
        Emptied C'.blk k (Ty.nest n (.dtor f u)) := by
  have hm := Cfg.sweepD_marks_cut (C := C.put i m' s') hc hkd hk hU
  have hi : ((C.put i m' s').sweepD).ths[i]? = some ⟨m'.st, m'.nv, s'⟩ := by
    simp [Cfg.sweepD, Cfg.put, hlen]
  exact ⟨hm, hse.reaps_block hm hi⟩

end A3
