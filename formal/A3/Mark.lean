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

/-- A block the configuration's roots reach is kept by its marking sweep as
    it was (a global's among them: the sweep roots the globals). -/
theorem Cfg.sweepD_keeps {C : Cfg} {k : Nat} {bl : Blk} (hk : C.blk k = some bl)
    (hr : Reached C.roots C.blk k) : C.sweepD.blk k = some bl :=
  sweepBlkD_reached hk (hr.roots fun _ h => Or.inl (Or.inl h))

/-- **A global's block is never an orphan** (#755's review: the sweep must
    root the globals, since a global `Locked D` is admissible): a block a
    module global refers to is kept by the marking sweep as it was. -/
theorem Cfg.sweepD_glob {C : Cfg} {g : Nat} {v : Val} (hg : C.gl g = some v) {k : Nat} {bl : Blk}
    (hk : C.blk k = some bl) (hr : Refers C.blk v k) : C.sweepD.blk k = some bl :=
  Cfg.sweepD_keeps hk (.root (.inr ⟨g, hg⟩) hr)

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
    it: no thread's slot, no global and no block's payload refers to it. -/
theorem Cfg.sweepD_marks {C : Cfg} {k n f : Nat} {u : Ty} {p : Val} {kd : BKind} (hkd : kd = .arc ∨ kd = .lock)
    (hk : C.blk k = some ⟨Ty.nest n (.dtor f u), kd, some p⟩)
    (hv : ∀ v, C.roots v → ¬ Refers C.blk v k)
    (hb : ∀ k' bl', C.blk k' = some bl' → ¬ Refers C.blk bl'.keeps k) :
    C.sweepD.blk k = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩ := by
  have hroots : ∀ w, (Roots0 C.roots C.blk w ∨ CandPay C.roots C.blk w) → ¬ Refers C.blk w k := by
    rintro w ((hw | ⟨k', n', f', u', hk'⟩) | ⟨k', n', f', u', kd', _, hk'⟩) hr
    · exact hv w hw hr
    · exact hb k' _ hk' (by simpa [Blk.keeps] using hr)
    · exact hb k' _ hk' (by simpa [Blk.keeps] using hr)
  have hnr := Reached.none_refers hroots hb
  have htop : TopOrphan C.roots C.blk k :=
    ⟨⟨⟨n, f, u, p, kd, hkd, hk⟩, fun h => hnr (h.roots fun _ h => Or.inl h)⟩, hnr⟩
  exact sweepBlkD_pinned hk htop.not_reached (Or.inl htop)

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

/-- A3.6: the marking sweep keeps what a global's share fits: a global is a
    root. -/
theorem _root_.A2.GlobFits.sweepD {C : Cfg} {g : Nat} {t : Ty} {v : Val} (hg : C.gl g = some v)
    (h : GlobFits C.blk t v) : GlobFits C.sweepD.blk t v := by
  rcases h with ⟨u, k, o, rfl, rfl, hk⟩ | ⟨u, k, p, rfl, rfl, hk⟩
  · exact .inl ⟨u, k, o, rfl, rfl, Cfg.sweepD_glob hg hk (.inl (.inl ⟨none, Sub.refl _⟩))⟩
  · have hr : Refers C.blk (.arc k p) k := .inl (.inl ⟨some p, Sub.refl _⟩)
    rcases hk with hk | hk
    · exact .inr ⟨u, k, p, rfl, rfl, .inl (Cfg.sweepD_glob hg hk hr)⟩
    · exact .inr ⟨u, k, p, rfl, rfl, .inr (Cfg.sweepD_glob hg hk hr)⟩

end A3
