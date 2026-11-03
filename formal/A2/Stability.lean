import A2.Ctx

/-! A2 — what a change of memory leaves valid.

A borrow is valid through one of its dependencies.  If the memory that
dependency's root reaches is unchanged (`RootKeep`) — or changed only in a way
that does not end borrows of that kind (`push`/`pop` on the root) — the borrow
stays valid. -/

namespace A2

/-- `r` reaches in `m'` what it reached in `m`, and an owner stays one
    (A3.1: a share dependency on an owner lands in a payload while the
    owner's slot is there, `RootMem`). -/
def RootKeep (m m' : Mem) (r : Var) : Prop :=
  (∀ n, RootNode m r n → RootNode m' r n) ∧ (∀ o, m.st r = some ⟨true, o⟩ → ∃ o', m'.st r = some ⟨true, o'⟩)

/-- A slot that stays as it was keeps its owner. -/
theorem RootKeep.of_slot {m m' : Mem} {r : Var} (hs : m'.st r = m.st r)
    (hn : ∀ n, RootNode m r n → RootNode m' r n) : RootKeep m m' r :=
  ⟨hn, fun o ho => ⟨o, by rw [hs]; exact ho⟩⟩

theorem RootKeep.rootMem {m m' : Mem} {r : Var} (h : RootKeep m m' r) (hr : RootMem m r) : RootMem m' r := by
  rcases hr with ⟨o, ho⟩ | ⟨n0, hn⟩
  · exact Or.inl (h.2 o ho)
  · exact Or.inr ⟨n0, h.1 n0 hn⟩

def VKeep (m m' : Mem) (dep : Dep) : Prop :=
  ∀ d o l s, ViewAt m dep d o l s → ViewAt m' dep d o l s

/-- What a dependency of a borrowed value keeps: the `Vec` handles and (A3.1)
    the shares it lands. -/
def HKeep (m m' : Mem) (dep : Dep) : Prop :=
  (∀ c t H, (∀ h ∈ H, VKeep m m' h) → m'.blk = m.blk → HrefAt m dep c t H → HrefAt m' dep c t H) ∧
  ∀ k p, m'.blk = m.blk → ArcLanded m dep (.arc k p) → ArcLanded m' dep (.arc k p)

/-- A dependency by name reaches no memory: nothing changes what it keeps. -/
theorem vkeep_name (m m' : Mem) (r : Var) (b : Eff) (t : Ty) : VKeep m m' ⟨r, .name b t⟩ := by
  intro d o l s ⟨_, _, _, hla, _⟩
  have := hla.notName; simp [Kind.isName] at this

theorem hkeep_name (m m' : Mem) (r : Var) (b : Eff) (t : Ty) : HKeep m m' ⟨r, .name b t⟩ := by
  refine ⟨fun c t H _ _ ⟨_, _, hla, _⟩ => ?_, fun k p _ hla => ?_⟩ <;>
  · have := hla.notName; simp [Kind.isName] at this

/-- What lands through a dependency whose root reaches the same memory, the
    blocks only growing, still lands there. -/
theorem Landed.keep {m m' : Mem} {dep : Dep} {n : Val} (hr : RootKeep m m' dep.root)
    (hb : BlkLe m.blk m'.blk) (h : Landed m dep n) : Landed m' dep n := by
  rcases h with ⟨n0, h0, hl⟩ | ⟨hk, hro, k, bl, hkb, hs⟩
  · exact Or.inl ⟨n0, hr.1 n0 h0, hl⟩
  · exact Or.inr ⟨hk, hr.rootMem hro, InPay.grow hb ⟨k, bl, hkb, hs⟩⟩

theorem ArcLanded.keep {m m' : Mem} {dep : Dep} {n : Val} (hr : RootKeep m m' dep.root)
    (h : ArcLanded m dep n) : ArcLanded m' dep n := by
  rcases h with ⟨n0, h0, hl⟩ | ⟨hk, hro⟩
  · exact Or.inl ⟨n0, hr.1 n0 h0, hl⟩
  · exact Or.inr ⟨hk, hr.rootMem hro⟩

/-- A3.1: what lands in a payload stays while its block does and its root
    still reaches memory. -/
theorem Landed.pay {m m' : Mem} {dep : Dep} {n : Val} (hb : BlkLe m.blk m'.blk)
    (hk : dep.kind = .share) (hro : RootMem m' dep.root) (h : Landed m dep n) : Landed m' dep n := by
  rcases h with ⟨n0, _, hl⟩ | ⟨hk, _, k, bl, hkb, hs⟩
  · rcases hl with ⟨h, _⟩ | ⟨h, _⟩ | ⟨h, _⟩ <;> rw [hk] at h <;> cases h
  · exact Or.inr ⟨hk, hro, InPay.grow hb ⟨k, bl, hkb, hs⟩⟩

theorem RootKeep.vkeep {m m' : Mem} {dep : Dep} (h : RootKeep m m' dep.root)
    (hb : BlkLe m.blk m'.blk := by exact BlkLe.of_le fun _ _ h => h) : VKeep m m' dep := by
  intro d o l s ⟨c, es, hks, hla, hl, hw⟩
  exact ⟨c, es, hks, hla.keep h hb, hl, hw⟩

/-- A3.1: a dependency through a share keeps what it lands while the blocks
    only grow and its root still reaches memory (an owner whose slot stays
    owned). -/
theorem vkeep_share {m m' : Mem} (hb : BlkLe m.blk m'.blk) {r : Var} (hro : RootMem m' r) :
    VKeep m m' ⟨r, .share⟩ := by
  intro d o l s ⟨c, es, hks, hla, hl, hw⟩
  exact ⟨c, es, hks, hla.pay hb rfl hro, hl, hw⟩

theorem ViewsOK.keep {m m' : Mem} {τ : Ty} {T : Val} {H : List Dep} (hk : ∀ h ∈ H, VKeep m m' h)
    (hv : ViewsOK m τ T H) : ViewsOK m' τ T H := by
  intro s v hin
  obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := hv s v hin
  exact ⟨d, o, l, rfl, dep, hd, hk dep hd d o l s ha⟩

/-- An armed binding's value stays valid where what it views in memory
    stays. -/
theorem ArmOK.keep {m m' : Mem} {E : Entry} {sl : Slot}
    (hk : E.dtor = true → E.dbind = true → E.mode.ownSlot = true → ∀ dep ∈ memDeps E.held, VKeep m m' dep)
    (h : ArmOK m E sl) : ArmOK m' E sl := by
  intro hd hos T hT
  obtain ⟨h1, h2⟩ := h hd hos T hT
  exact ⟨h1, (h2.memDeps.keep (hk h1 hd hos)).mono (fun d hd => (List.mem_filter.mp hd).1)⟩

theorem RootKeep.hkeep {m m' : Mem} {dep : Dep} (h : RootKeep m m' dep.root) : HKeep m m' dep := by
  refine ⟨fun c t H hH hb ⟨d, es, hla, hw, hv, hn, hsh⟩ => ?_, fun k p _ hla => hla.keep h⟩
  exact ⟨d, es, hla.keep h (BlkLe.of_eq hb), hw, hv.keep hH, hn, hsh.of_blk hb⟩

theorem ValOK.keep {m m' : Mem} {τ : Ty} {v : Val} {P H : List Dep}
    (hp : ∀ dep ∈ P, VKeep m m' dep ∧ HKeep m m' dep) (hh : ∀ dep ∈ H, VKeep m m' dep ∧ HKeep m m' dep)
    (h : ValOK m τ v P H) (hb : m'.blk = m.blk := by rfl) : ValOK m' τ v P H := by
  induction h with
  | int => exact .int
  | arc h hw hv hl =>
    obtain ⟨dep, hd, hla⟩ := hl
    exact .arc (by rw [hb]; exact h) hw hv ⟨dep, hd, (hp dep hd).2.2 _ _ hb hla⟩
  | lk h => exact .lk (by rw [hb]; exact h)
  | cell => exact .cell
  | href h =>
    obtain ⟨dep, hd, ha⟩ := h
    exact .href ⟨dep, hd, (hp dep hd).2.1 _ _ _ (fun h hh' => (hh h hh').1) hb ha⟩
  | view h =>
    obtain ⟨dep, hd, ha⟩ := h
    exact .view ⟨dep, hd, (hp dep hd).1 _ _ _ _ ha⟩
  | pair _ _ ihx ihy =>
    have hph : ∀ dep ∈ _ ++ _, VKeep m m' dep ∧ HKeep m m' dep := fun dep hd => by
      rcases List.mem_append.mp hd with hd | hd
      · exact hp dep hd
      · exact hh dep hd
    exact .pair (ihx hph hh) (ihy hph hh)
  | inl _ ih =>
    have hph : ∀ dep ∈ _ ++ _, VKeep m m' dep ∧ HKeep m m' dep := fun dep hd => by
      rcases List.mem_append.mp hd with hd | hd
      · exact hp dep hd
      · exact hh dep hd
    exact .inl (ih hph hh)
  | inr _ ih =>
    have hph : ∀ dep ∈ _ ++ _, VKeep m m' dep ∧ HKeep m m' dep := fun dep hd => by
      rcases List.mem_append.mp hd with hd | hd
      · exact hp dep hd
      · exact hh dep hd
    exact .inr (ih hph hh)
  | @pkg fs te ms x cs P H _ ih =>
    have hr : ∀ dep ∈ envDeps cs H, VKeep m m' dep ∧ HKeep m m' dep := fun dep hd => hh dep (envDeps_sub _ _ hd)
    have hph : ∀ dep ∈ P ++ envDeps cs H, VKeep m m' dep ∧ HKeep m m' dep := fun dep hd => by
      rcases List.mem_append.mp hd with hd | hd
      · exact hp dep hd
      · exact hr dep hd
    exact .pkg (ih hph hr)

/-! ### Borrowed parameters reach only frozen owners -/

theorem ViewIn.holdsView {τ T s v} (h : ViewIn τ T s v) : τ.holdsView = true := by
  induction h with
  | here => rfl
  | child _ _ ih => simpa [Ty.holdsView] using ih
  | fst _ ih => simp [Ty.holdsView, ih]
  | snd _ ih => simp [Ty.holdsView, ih]
  | inl _ ih => simp [Ty.holdsView, ih]
  | inr _ ih => simp [Ty.holdsView, ih]
  | pkg _ ih => simp [Ty.holdsView]

theorem no_views {t : Ty} (ht : t.holdsView = false) (m : Mem) (T : Val) (H : List Dep) :
    ViewsOK m (.vec t) T H := by
  intro s v hin
  have := hin.holdsView
  simp [Ty.holdsView, ht] at this

theorem nodeAt_of_owned {m : Mem} {o : Var} {T n : Val} (ho : OwnedAt m o T) (hs : Sub n T)
    {t : Ty} {c d : Nat} {es : List Val} (hn : n = .node t c d es) : NodeAt m c n :=
  Or.inl ⟨o, T, ho, hs, t, d, es, hn⟩

theorem dataAt_of_owned {m : Mem} {o : Var} {T n : Val} (ho : OwnedAt m o T) (hs : Sub n T)
    {t : Ty} {c d : Nat} {es : List Val} (hn : n = .node t c d es) : DataAt m d n :=
  Or.inl ⟨o, T, ho, hs, t, c, es, hn⟩

/-- A3.1: a value lying in an owned tree, or in a live block's payload. -/
def InMem (m : Mem) (n : Val) : Prop :=
  (∃ o T, OwnedAt m o T ∧ Sub n T) ∨ ∃ k bl, m.blk k = some bl ∧ Sub n bl.rd

theorem InMem.sub {m : Mem} {n n' : Val} (h : InMem m n) (hs : Sub n' n) : InMem m n' := by
  rcases h with ⟨o, T, hT, h⟩ | ⟨k, bl, hk, h⟩
  · exact Or.inl ⟨o, T, hT, hs.trans h⟩
  · exact Or.inr ⟨k, bl, hk, hs.trans h⟩

theorem InMem.nodeAt {m : Mem} {n : Val} (h : InMem m n) {t : Ty} {c d : Nat} {es : List Val}
    (hn : n = .node t c d es) : NodeAt m c n := by
  rcases h with ⟨o, T, hT, h⟩ | ⟨k, bl, hk, h⟩
  · exact Or.inl ⟨o, T, hT, h, t, d, es, hn⟩
  · exact Or.inr ⟨k, bl, hk, h, t, d, es, hn⟩

theorem InMem.dataAt {m : Mem} {n : Val} (h : InMem m n) {t : Ty} {c d : Nat} {es : List Val}
    (hn : n = .node t c d es) : DataAt m d n := by
  rcases h with ⟨o, T, hT, h⟩ | ⟨k, bl, hk, h⟩
  · exact Or.inl ⟨o, T, hT, h, t, c, es, hn⟩
  · exact Or.inr ⟨k, bl, hk, h, t, c, es, hn⟩

theorem NodeAt.inMem {m : Mem} {c : Nat} {n : Val} (h : NodeAt m c n) : InMem m n := by
  rcases h with ⟨o, T, hT, h, _⟩ | ⟨k, bl, hk, h, _⟩
  · exact Or.inl ⟨o, T, hT, h⟩
  · exact Or.inr ⟨k, bl, hk, h⟩

theorem DataAt.inMem {m : Mem} {d : Nat} {n : Val} (h : DataAt m d n) : InMem m n := by
  rcases h with ⟨o, T, hT, h, _⟩ | ⟨k, bl, hk, h, _⟩
  · exact Or.inl ⟨o, T, hT, h⟩
  · exact Or.inr ⟨k, bl, hk, h⟩

theorem NodeAt.eq {m : Mem} {c : Nat} {n : Val} (h : NodeAt m c n) : ∃ ty d es, n = .node ty c d es := by
  rcases h with ⟨_, _, _, _, h⟩ | ⟨_, _, _, _, h⟩ <;> exact h

theorem DataAt.eq {m : Mem} {d : Nat} {n : Val} (h : DataAt m d n) : ∃ ty c es, n = .node ty c d es := by
  rcases h with ⟨_, _, _, _, h⟩ | ⟨_, _, _, _, h⟩ <;> exact h

/-- What lies in a live block's payload stays there while the block lives. -/
theorem InMem.grow_pay {m m' : Mem} (hb : BlkLe m.blk m'.blk) {n : Val} {k : Nat} {bl : Blk}
    (hk : m.blk k = some bl) (hs : Sub n bl.rd) : InMem m' n :=
  Or.inr (InPay.grow hb ⟨k, bl, hk, hs⟩)

theorem InMem.mono {m m' : Mem} (hown : ∀ o T, OwnedAt m o T → OwnedAt m' o T)
    (hb : BlkLe m.blk m'.blk) {n : Val} (h : InMem m n) : InMem m' n := by
  rcases h with ⟨o, T, hT, h⟩ | ⟨k, bl, hk, h⟩
  · exact Or.inl ⟨o, T, hown o T hT, h⟩
  · exact Or.inr (InPay.grow hb ⟨k, bl, hk, h⟩)

theorem NodeAt.mono {m m' : Mem} (hown : ∀ o T, OwnedAt m o T → OwnedAt m' o T)
    (hb : BlkLe m.blk m'.blk) {c : Nat} {n : Val} (h : NodeAt m c n) : NodeAt m' c n := by
  obtain ⟨t, d, es, rfl⟩ := h.eq
  exact (h.inMem.mono hown hb).nodeAt rfl

theorem DataAt.mono {m m' : Mem} (hown : ∀ o T, OwnedAt m o T → OwnedAt m' o T)
    (hb : BlkLe m.blk m'.blk) {d : Nat} {n : Val} (h : DataAt m d n) : DataAt m' d n := by
  obtain ⟨t, c, es, rfl⟩ := h.eq
  exact (h.inMem.mono hown hb).dataAt rfl

theorem Lands.sub {k : Kind} {n n0 : Val} (h : Lands k n n0) : Sub n n0 := by
  rcases h with ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, hb⟩
  · exact Sub.refl _
  · exact Sub.refl _
  · exact hb.sub

theorem Top.sub {n v : Val} (h : Top n v) : Sub n v := by
  induction h with
  | refl => exact Sub.refl _
  | fst _ ih => exact Sub.fst ih
  | snd _ ih => exact Sub.snd ih
  | inl _ ih => exact Sub.inl ih
  | inr _ ih => exact Sub.inr ih
  | pkg _ ih => exact Sub.pkg ih

theorem Top.trans {a b c : Val} (h1 : Top a b) (h2 : Top b c) : Top a c := by
  induction h2 with
  | refl => exact h1
  | fst _ ih => exact Top.fst ih
  | snd _ ih => exact Top.snd ih
  | inl _ ih => exact Top.inl ih
  | inr _ ih => exact Top.inr ih
  | pkg _ ih => exact Top.pkg ih

theorem Top.node {n : Val} {t : Ty} {c d : Nat} {es : List Val} (h : Top n (.node t c d es)) :
    n = .node t c d es := by
  cases h; rfl

/-- Every node a root reaches is inside some owned tree, or (A3.1) in a live
    block's payload; what else it reaches is a share at the top of a
    borrowed slot. -/
theorem RootNode.owned {m : Mem} {r : Var} {n : Val} (h : RootNode m r n) :
    InMem m n ∨ ∃ k q, n = .arc k q := by
  rcases h with ⟨T, h, ht⟩ | ⟨_, c, _, _, hn⟩ | ⟨_, d, _, _, _, _, hn⟩ | ⟨_, k, q, _, _, rfl⟩
  · exact Or.inl (Or.inl ⟨r, T, h, ht.sub⟩)
  · exact Or.inl hn.inMem
  · exact Or.inl hn.inMem
  · exact Or.inr ⟨k, q, rfl⟩

/-- Nothing lies below a share: a payload is the block's, not the share's. -/
theorem lands_arc {kd : Kind} {n : Val} {k : Nat} {q : Val} (h : Lands kd n (.arc k q)) : n = .arc k q := by
  rcases h with ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, e, hc, _⟩
  · rfl
  · rfl
  · cases hc

/-- What lands through a dependency is in an owned tree or a live payload,
    or is a share a borrowed root holds. -/
theorem Landed.inMem' {m : Mem} {dep : Dep} {n : Val} (h : Landed m dep n) :
    InMem m n ∨ ∃ k q, n = .arc k q := by
  rcases h with ⟨n0, hr, hl⟩ | ⟨_, _, k, bl, hk, hs⟩
  · rcases hr.owned with h | ⟨k, q, rfl⟩
    · exact Or.inl (h.sub hl.sub)
    · exact Or.inr ⟨k, q, lands_arc hl⟩
  · exact Or.inl (Or.inr ⟨k, bl, hk, hs⟩)

/-- A node that lands through a dependency is in an owned tree or a live
    payload. -/
theorem Landed.inMem {m : Mem} {dep : Dep} {t : Ty} {c d : Nat} {es : List Val}
    (h : Landed m dep (.node t c d es)) : InMem m (.node t c d es) := by
  rcases h.inMem' with h | ⟨_, _, h⟩
  · exact h
  · cases h

/-- What lands through a dependency, its root reaches memory. -/
theorem Landed.rootMem {m : Mem} {dep : Dep} {n : Val} (h : Landed m dep n) : RootMem m dep.root := by
  rcases h with ⟨n0, hr, _⟩ | ⟨_, hro, _⟩
  · exact Or.inr ⟨n0, hr⟩
  · exact hro

theorem ArcLanded.rootMem {m : Mem} {dep : Dep} {n : Val} (h : ArcLanded m dep n) : RootMem m dep.root := by
  rcases h with ⟨n0, hr, _⟩ | ⟨_, hro⟩
  · exact Or.inr ⟨n0, hr⟩
  · exact hro

theorem ArcLanded.root {m : Mem} {dep : Dep} {n : Val} (h : ArcLanded m dep n) (hk : dep.kind ≠ .share) :
    ∃ n0, RootNode m dep.root n0 ∧ Lands dep.kind n n0 := by
  rcases h with h | ⟨h, _⟩
  · exact h
  · exact absurd h hk

/-- An owner whose slot is there reaches memory. -/
theorem RootMem.own {m : Mem} {r : Var} {o : Option Val} (h : m.st r = some ⟨true, o⟩) : RootMem m r :=
  Or.inl ⟨o, h⟩

/-- Off a share, what lands does so through the root's node. -/
theorem Landed.root {m : Mem} {dep : Dep} {n : Val} (h : Landed m dep n) (hk : dep.kind ≠ .share) :
    ∃ n0, RootNode m dep.root n0 ∧ Lands dep.kind n n0 := by
  rcases h with h | ⟨h, _⟩
  · exact h
  · exact absurd h hk

theorem append_assoc_sub {P H : List Dep} : (P ++ H) ++ H ⊆ P ++ H := by
  intro d hd
  rcases List.mem_append.mp hd with hd | hd
  · exact hd
  · exact List.mem_append_right _ hd

theorem append_readers_sub {P H : List Dep} : (P ++ readers H) ++ readers H ⊆ P ++ H := by
  intro d hd
  simp only [List.mem_append] at hd ⊢
  rcases hd with (hd | hd) | hd
  · exact Or.inl hd
  · exact Or.inr (readers_sub _ hd)
  · exact Or.inr (readers_sub _ hd)

theorem append_envDeps_sub {cs : List (Var × PMode × Ty)} {P H : List Dep} :
    (P ++ envDeps cs H) ++ envDeps cs H ⊆ P ++ H := by
  intro d hd
  simp only [List.mem_append] at hd ⊢
  rcases hd with (hd | hd) | hd
  · exact Or.inl hd
  · exact Or.inr (envDeps_sub _ _ hd)
  · exact Or.inr (envDeps_sub _ _ hd)

/-- A `Vec` handle inside a borrowed value reaches its node through one of
    the value's dependencies. -/
theorem valOK_href {m : Mem} (hh : HeapOK m) {c : Nat} {n : Val} (hn : NodeAt m c n)
    {τ : Ty} {w : Val} {P H : List Dep} (hok : ValOK m τ w P H) (ht : Top (.href c) w) :
    ∃ dep ∈ P ++ H, Landed m dep n := by
  induction hok with
  | int => cases ht
  | arc _ _ _ _ => cases ht
  | lk => cases ht
  | cell => cases ht
  | view _ => cases ht
  | @href t c' P H h =>
    obtain ⟨dep, hd, d, es, hla, _⟩ := h
    cases ht
    have := nodeAt_unique hh hn (hla.inMem.nodeAt rfl)
    subst this
    exact ⟨dep, List.mem_append_left _ hd, hla⟩
  | pair _ _ ihx ihy =>
    cases ht with
    | fst ht => obtain ⟨dep, hd, rest⟩ := ihx ht; exact ⟨dep, append_assoc_sub hd, rest⟩
    | snd ht => obtain ⟨dep, hd, rest⟩ := ihy ht; exact ⟨dep, append_assoc_sub hd, rest⟩
  | inl _ ih =>
    cases ht with
    | inl ht => obtain ⟨dep, hd, rest⟩ := ih ht; exact ⟨dep, append_assoc_sub hd, rest⟩
  | inr _ ih =>
    cases ht with
    | inr ht => obtain ⟨dep, hd, rest⟩ := ih ht; exact ⟨dep, append_assoc_sub hd, rest⟩
  | pkg _ ih =>
    cases ht with
    | pkg ht => obtain ⟨dep, hd, rest⟩ := ih ht; exact ⟨dep, append_envDeps_sub hd, rest⟩

/-- A view inside a borrowed value reaches its buffer through one of the
    value's dependencies, of a kind that ends views. -/
theorem valOK_view {m : Mem} (hh : HeapOK m) {d o l : Nat} {n : Val} (hn : DataAt m d n)
    {τ : Ty} {w : Val} {P H : List Dep} (hok : ValOK m τ w P H) (ht : Top (.view d o l) w) :
    ∃ dep ∈ P ++ H, dep.kind ≠ .self ∧ Landed m dep n := by
  induction hok with
  | int => cases ht
  | arc _ _ _ _ => cases ht
  | lk => cases ht
  | cell => cases ht
  | href _ => cases ht
  | @view t d' o' l' P H h =>
    obtain ⟨dep, hd, c, es, hks, hla, _, _⟩ := h
    cases ht
    have := dataAt_unique hh hn (hla.inMem.dataAt rfl)
    subst this
    exact ⟨dep, List.mem_append_left _ hd, hks, hla⟩
  | pair _ _ ihx ihy =>
    cases ht with
    | fst ht => obtain ⟨dep, hd, rest⟩ := ihx ht; exact ⟨dep, append_assoc_sub hd, rest⟩
    | snd ht => obtain ⟨dep, hd, rest⟩ := ihy ht; exact ⟨dep, append_assoc_sub hd, rest⟩
  | inl _ ih =>
    cases ht with
    | inl ht => obtain ⟨dep, hd, rest⟩ := ih ht; exact ⟨dep, append_assoc_sub hd, rest⟩
  | inr _ ih =>
    cases ht with
    | inr ht => obtain ⟨dep, hd, rest⟩ := ih ht; exact ⟨dep, append_assoc_sub hd, rest⟩
  | pkg _ ih =>
    cases ht with
    | pkg ht => obtain ⟨dep, hd, rest⟩ := ih ht; exact ⟨dep, append_envDeps_sub hd, rest⟩

/-- A value held at the top of a borrowed slot `y` is valid through `y`
    itself: every handle in it is one `y` holds. -/
theorem valOK_via {m : Mem} {y : Var} {T : Val} (hy : m.st y = some ⟨false, some T⟩)
    {τ : Ty} {w : Val} {P H : List Dep} (hok : ValOK m τ w P H) :
    ∀ {Q : List Dep}, Top w T → ⟨y, .view⟩ ∈ Q → ValOK m τ w Q H := by
  induction hok with
  | int => intro _ _ _; exact .int
  | @arc t k p P H h hw hv _ =>
    intro Q ht hq
    exact .arc h hw hv ⟨_, hq, Or.inl ⟨_, Or.inr (Or.inr (Or.inr ⟨T, k, p, hy, ht, rfl⟩)), Or.inr (Or.inl ⟨rfl, rfl⟩)⟩⟩
  | lk h => intro _ _ _; exact .lk h
  | cell => intro _ _ _; exact .cell
  | @href t c P H h =>
    intro Q ht hq
    obtain ⟨dep, hd, d, es, hla, hw, hv⟩ := h
    exact .href ⟨_, hq, d, es,
      Or.inl ⟨_, Or.inr (Or.inl ⟨T, c, hy, ht, hla.inMem.nodeAt rfl⟩), Or.inr (Or.inl ⟨rfl, rfl⟩)⟩, hw, hv⟩
  | @view t d o l P H h =>
    intro Q ht hq
    obtain ⟨dep, hd, c, es, _, hla, hlen, hw⟩ := h
    exact .view ⟨_, hq, c, es, (by intro h; cases h),
      Or.inl ⟨_, Or.inr (Or.inr (Or.inl ⟨T, d, o, l, hy, ht, hla.inMem.dataAt rfl⟩)), Or.inr (Or.inl ⟨rfl, rfl⟩)⟩,
      hlen, hw⟩
  | pair _ _ ihx ihy =>
    intro Q ht hq
    exact .pair (ihx (Top.trans (Top.fst (Top.refl _)) ht) (List.mem_append_left _ hq))
      (ihy (Top.trans (Top.snd (Top.refl _)) ht) (List.mem_append_left _ hq))
  | inl _ ih =>
    intro Q ht hq
    exact .inl (ih (Top.trans (Top.inl (Top.refl _)) ht) (List.mem_append_left _ hq))
  | inr _ ih =>
    intro Q ht hq
    exact .inr (ih (Top.trans (Top.inr (Top.refl _)) ht) (List.mem_append_left _ hq))
  | pkg _ ih =>
    intro Q ht hq
    exact .pkg (ih (Top.trans (Top.pkg (Top.refl _)) ht) (List.mem_append_left _ hq))

/-- A3.1: a share at the top of a borrowed value lands through one of the
    value's dependencies. -/
theorem valOK_arc {m : Mem} {k : Nat} {q : Val} {τ : Ty} {w : Val} {P H : List Dep}
    (hok : ValOK m τ w P H) (ht : Top (.arc k q) w) : ∃ dep ∈ P ++ H, ArcLanded m dep (.arc k q) := by
  induction hok with
  | int => cases ht
  | href _ => cases ht
  | view _ => cases ht
  | arc _ _ _ hl =>
    cases ht
    obtain ⟨dep, hd, hla⟩ := hl
    exact ⟨dep, List.mem_append_left _ hd, hla⟩
  | lk _ => cases ht
  | cell => cases ht
  | pair _ _ ihx ihy =>
    cases ht with
    | fst ht => obtain ⟨dep, hd, rest⟩ := ihx ht; exact ⟨dep, append_assoc_sub hd, rest⟩
    | snd ht => obtain ⟨dep, hd, rest⟩ := ihy ht; exact ⟨dep, append_assoc_sub hd, rest⟩
  | inl _ ih =>
    cases ht with
    | inl ht => obtain ⟨dep, hd, rest⟩ := ih ht; exact ⟨dep, append_assoc_sub hd, rest⟩
  | inr _ ih =>
    cases ht with
    | inr ht => obtain ⟨dep, hd, rest⟩ := ih ht; exact ⟨dep, append_assoc_sub hd, rest⟩
  | pkg _ ih =>
    cases ht with
    | pkg ht => obtain ⟨dep, hd, rest⟩ := ih ht; exact ⟨dep, append_envDeps_sub hd, rest⟩

/-- What a borrowed slot reaches, it reaches through the dependencies of the
    value it holds (a node; a share it holds lands as a share does,
    `bor_arcLanded`). -/
theorem bor_lands {m : Mem} (hh : HeapOK m) {p : Var} {τ : Ty} {w : Val} {P H : List Dep}
    (hp : m.st p = some ⟨false, some w⟩) (hok : ValOK m τ w P H) {n0 : Val}
    (hr : RootNode m p n0) (hn0 : ∀ k q, n0 ≠ .arc k q) : ∃ d' ∈ P ++ H, Landed m d' n0 := by
  rcases hr with ⟨T, h, _⟩ | ⟨v, c, hc, ht, hn⟩ | ⟨v, d, o, l, hc, ht, hn⟩ | ⟨v, k, q, hc, ht, rfl⟩
  · rw [hp] at h; cases h
  · rw [hp] at hc; cases hc
    exact valOK_href hh hn hok ht
  · rw [hp] at hc; cases hc
    obtain ⟨dep, hd, _, hla⟩ := valOK_view hh hn hok ht
    exact ⟨dep, hd, hla⟩
  · exact absurd rfl (hn0 k q)

/-- A3.1: whatever a borrowed slot reaches, a node or a share at its top, it
    reaches through a dependency of the value it holds, whose root reaches
    memory. -/
theorem bor_arcLanded {m : Mem} (hh : HeapOK m) {p : Var} {τ : Ty} {w : Val} {P H : List Dep}
    (hp : m.st p = some ⟨false, some w⟩) (hok : ValOK m τ w P H) {n0 : Val}
    (hr : RootNode m p n0) : ∃ d' ∈ P ++ H, ArcLanded m d' n0 := by
  by_cases hn0 : ∃ k q, n0 = .arc k q
  · obtain ⟨k, q, rfl⟩ := hn0
    rcases hr with ⟨T, h, _⟩ | ⟨v, c, hc, ht, hn⟩ | ⟨v, d, o, l, hc, ht, hn⟩ | ⟨v, k', q', hc, ht, he⟩
    · rw [hp] at h; cases h
    · obtain ⟨_, _, _, h⟩ := hn.eq; cases h
    · obtain ⟨_, _, _, h⟩ := hn.eq; cases h
    · rw [hp] at hc; cases hc; cases he
      exact valOK_arc hok ht
  · obtain ⟨d', hd', hla⟩ := bor_lands hh hp hok hr (fun k q h => hn0 ⟨k, q, h⟩)
    exact ⟨d', hd', hla.arc⟩

/-- What a dependency reaches in memory is reached through one of the
    three kinds that reach memory. -/
theorem lands_bound {k : Kind} {n n0 : Val} (h : Lands k n n0) : k.bound = .none := by
  rcases h with ⟨rfl, _⟩ | ⟨rfl, _⟩ | ⟨rfl, _⟩ <;> rfl

/-- Every borrowed parameter reaches memory inside a frozen owner's tree. -/

theorem rootb_anchor {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F) :
    ∀ p E n, Γ p = some E → E.mode = .rootb → RootNode m p n → (∀ k q, n ≠ .arc k q) →
      (∃ o T, o ∈ F ∧ OwnedAt m o T ∧ Sub n T) ∨ ∃ k bl, m.blk k = some bl ∧ Sub n bl.rd := by
  intro p
  induction p using Nat.strongRecOn with
  | _ p ih =>
  intro E n hp hm hrn hnn
  have hlive := hi.rootbLive p E hp hm
  obtain ⟨sl, hsl, _, hso, _, hbor⟩ := hi.slot p E hp
  have hos : E.mode.ownSlot = false := by rw [hm]; rfl
  obtain ⟨v, hv, hok⟩ := hbor hos hlive
  have hsl' : sl = ⟨false, some v⟩ := by
    obtain ⟨own, val⟩ := sl
    simp only at hv hso; subst hv; rw [hso, hos]
  rw [hsl'] at hsl
  obtain ⟨dep, hd, hla⟩ := bor_lands hi.heap hsl hok hrn hnn
  rcases hla with ⟨n0, hr, hl⟩ | ⟨_, _, k, bl, hk, hs⟩
  case inr => exact Or.inr ⟨k, bl, hk, hs⟩
  have hdv : dep.root ∈ roots E.vdeps := by
    simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.mem_map]
    exact ⟨dep, hd, rfl⟩
  have hF : dep.root ∈ F := by
    refine hanch p E hp hm dep ?_ (lands_bound hl)
    simp only [Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte]
    exact hd
  have hnint : E.ty ≠ .int := by
    intro h; rw [h] at hok; obtain ⟨k, rfl⟩ := hok
    rcases hrn with ⟨_, h1, _⟩ | ⟨_, c, h1, ht, _⟩ | ⟨_, d, o, l, h1, ht, _⟩ | ⟨_, k, q, h1, ht, _⟩ <;>
      rw [hsl] at h1 <;> cases h1 <;> cases ht
  have hnn0 : ∀ k q, n0 ≠ .arc k q := fun k q h => hnn k q (lands_arc (h ▸ hl))
  obtain ⟨Er, hEr, hroot⟩ := hi.wf p E hp hlive (Or.inl hnint) dep.root hdv
  rcases hr with ⟨T, hown, ht⟩ | ⟨w, c, hc, ht, hn⟩ | ⟨w, d, o, l, hc, ht, hn⟩ | ⟨w, k, q, hc, ht, hn⟩
  · exact Or.inl ⟨dep.root, T, hF, hown, hl.sub.trans ht.sub⟩
  all_goals
    have hlt := hi.rootbLt p E hp hm dep.root hdv
    obtain ⟨slr, hslr, _, hsor, _, _⟩ := hi.slot dep.root Er hEr
    have hrb : Er.mode = .rootb := by
      rw [hc] at hslr; cases hslr
      cases hme : Er.mode with
      | own => rw [hme] at hsor; simp [Mode.ownSlot] at hsor
      | inout b => exact absurd hme (hi.noInout _ Er b hEr)
      | rootb => rfl
      | bor => rw [hme] at hroot; simp [Mode.isRoot] at hroot
  · rcases ih dep.root hlt Er n0 hEr hrb (Or.inr (Or.inl ⟨w, c, hc, ht, hn⟩)) hnn0 with
      ⟨o', T', hF', ho', hs'⟩ | ⟨k, bl, hk, hs'⟩
    · exact Or.inl ⟨o', T', hF', ho', hl.sub.trans hs'⟩
    · exact Or.inr ⟨k, bl, hk, hl.sub.trans hs'⟩
  · rcases ih dep.root hlt Er n0 hEr hrb (Or.inr (Or.inr (Or.inl ⟨w, d, o, l, hc, ht, hn⟩))) hnn0 with
      ⟨o', T', hF', ho', hs'⟩ | ⟨k, bl, hk, hs'⟩
    · exact Or.inl ⟨o', T', hF', ho', hl.sub.trans hs'⟩
    · exact Or.inr ⟨k, bl, hk, hl.sub.trans hs'⟩
  · exact absurd hn (hnn0 k q)

/-- A root whose slot is unchanged, at a point where every slot that changes
    is outside the frozen owners, reaches the same memory. -/
theorem rootKeep_frame {m m' : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    (hF : ∀ o ∈ F, m'.st o = m.st o) {r : Var} {Er : Entry} (hr : Γ r = some Er)
    (hroot : Er.mode.isRoot = true) (hsame : m'.st r = m.st r)
    (hb : BlkLe m.blk m'.blk := by exact BlkLe.of_le fun _ _ h => h) : RootKeep m m' r := by
  refine RootKeep.of_slot hsame fun n hn => ?_
  rcases hn with ⟨T, hown, ht⟩ | ⟨w, c, hc, ht, hnode⟩ | ⟨w, d, o, l, hc, ht, hdata⟩ | ⟨w, k, q, hc, ht, hn⟩
  · exact Or.inl ⟨T, by rw [hsame]; exact hown, ht⟩
  rotate_left 2
  · exact Or.inr (Or.inr (Or.inr ⟨w, k, q, by rw [hsame]; exact hc, ht, hn⟩))
  all_goals
    obtain ⟨sl, hsl, _, hso, _, _⟩ := hi.slot r Er hr
    have hrb : Er.mode = .rootb := by
      rw [hc] at hsl; cases hsl
      cases hme : Er.mode with
      | own => rw [hme] at hso; simp [Mode.ownSlot] at hso
      | inout b => exact absurd hme (hi.noInout _ Er b hr)
      | rootb => rfl
      | bor => rw [hme] at hroot; simp [Mode.isRoot] at hroot
  · obtain ⟨ty, d, es, hneq⟩ := hnode.eq
    refine Or.inr (Or.inl ⟨w, c, by rw [hsame]; exact hc, ht, ?_⟩)
    rcases rootb_anchor hi hanch r Er n hr hrb (Or.inr (Or.inl ⟨w, c, hc, ht, hnode⟩))
        (by rw [hneq]; intro _ _ h; cases h) with
      ⟨o', T, hoF, hoT, hsT⟩ | ⟨k, bl, hk, hs⟩
    · exact nodeAt_of_owned (by unfold OwnedAt; rw [hF o' hoF]; exact hoT) hsT hneq
    · exact (InMem.grow_pay hb hk hs).nodeAt hneq
  · obtain ⟨ty, c, es, hneq⟩ := hdata.eq
    refine Or.inr (Or.inr (Or.inl ⟨w, d, o, l, by rw [hsame]; exact hc, ht, ?_⟩))
    rcases rootb_anchor hi hanch r Er n hr hrb (Or.inr (Or.inr (Or.inl ⟨w, d, o, l, hc, ht, hdata⟩)))
        (by rw [hneq]; intro _ _ h; cases h) with
      ⟨o', T, hoF, hoT, hsT⟩ | ⟨k, bl, hk, hs⟩
    · exact dataAt_of_owned (by unfold OwnedAt; rw [hF o' hoF]; exact hoT) hsT hneq
    · exact (InMem.grow_pay hb hk hs).dataAt hneq

/-- `rootb_anchor` for the borrowed parameters outside the bindings `sp`. -/
theorem rootb_anchor_sp {m : Mem} {Γ : Ctx} {F sp : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ sp → Anchored E F)
    (hpin : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ sp → ∀ r ∈ roots E.vdeps, r ∉ sp) :
    ∀ p E n, Γ p = some E → E.mode = .rootb → p ∉ sp → RootNode m p n → (∀ k q, n ≠ .arc k q) →
      (∃ o T, o ∈ F ∧ OwnedAt m o T ∧ Sub n T) ∨ ∃ k bl, m.blk k = some bl ∧ Sub n bl.rd := by
  intro p
  induction p using Nat.strongRecOn with
  | _ p ih =>
  intro E n hp hm hps hrn hnn
  have hlive := hi.rootbLive p E hp hm
  obtain ⟨sl, hsl, _, hso, _, hbor⟩ := hi.slot p E hp
  have hos : E.mode.ownSlot = false := by rw [hm]; rfl
  obtain ⟨v, hv, hok⟩ := hbor hos hlive
  have hsl' : sl = ⟨false, some v⟩ := by
    obtain ⟨own, val⟩ := sl
    simp only at hv hso; subst hv; rw [hso, hos]
  rw [hsl'] at hsl
  obtain ⟨dep, hd, hla⟩ := bor_lands hi.heap hsl hok hrn hnn
  rcases hla with ⟨n0, hr, hl⟩ | ⟨_, _, k, bl, hk, hs⟩
  case inr => exact Or.inr ⟨k, bl, hk, hs⟩
  have hdv : dep.root ∈ roots E.vdeps := by
    simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.mem_map]
    exact ⟨dep, hd, rfl⟩
  have hF : dep.root ∈ F := by
    refine hanch p E hp hm hps dep ?_ (lands_bound hl)
    simp only [Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte]
    exact hd
  have hnint : E.ty ≠ .int := by
    intro h; rw [h] at hok; obtain ⟨k, rfl⟩ := hok
    rcases hrn with ⟨_, h1, _⟩ | ⟨_, c, h1, ht, _⟩ | ⟨_, d, o, l, h1, ht, _⟩ | ⟨_, k, q, h1, ht, _⟩ <;>
      rw [hsl] at h1 <;> cases h1 <;> cases ht
  have hnn0 : ∀ k q, n0 ≠ .arc k q := fun k q h => hnn k q (lands_arc (h ▸ hl))
  obtain ⟨Er, hEr, hroot⟩ := hi.wf p E hp hlive (Or.inl hnint) dep.root hdv
  rcases hr with ⟨T, hown, ht⟩ | ⟨w, c, hc, ht, hn⟩ | ⟨w, d, o, l, hc, ht, hn⟩ | ⟨w, k, q, hc, ht, hn⟩
  · exact Or.inl ⟨dep.root, T, hF, hown, hl.sub.trans ht.sub⟩
  all_goals
    have hlt := hi.rootbLt p E hp hm dep.root hdv
    obtain ⟨slr, hslr, _, hsor, _, _⟩ := hi.slot dep.root Er hEr
    have hrb : Er.mode = .rootb := by
      rw [hc] at hslr; cases hslr
      cases hme : Er.mode with
      | own => rw [hme] at hsor; simp [Mode.ownSlot] at hsor
      | inout b => exact absurd hme (hi.noInout _ Er b hEr)
      | rootb => rfl
      | bor => rw [hme] at hroot; simp [Mode.isRoot] at hroot
  · rcases ih dep.root hlt Er n0 hEr hrb (hpin p E hp hm hps dep.root hdv) (Or.inr (Or.inl ⟨w, c, hc, ht, hn⟩))
        hnn0 with
      ⟨o', T', hF', ho', hs'⟩ | ⟨k, bl, hk, hs'⟩
    · exact Or.inl ⟨o', T', hF', ho', hl.sub.trans hs'⟩
    · exact Or.inr ⟨k, bl, hk, hl.sub.trans hs'⟩
  · rcases ih dep.root hlt Er n0 hEr hrb (hpin p E hp hm hps dep.root hdv) (Or.inr (Or.inr (Or.inl ⟨w, d, o, l, hc, ht, hn⟩)))
        hnn0 with
      ⟨o', T', hF', ho', hs'⟩ | ⟨k, bl, hk, hs'⟩
    · exact Or.inl ⟨o', T', hF', ho', hl.sub.trans hs'⟩
    · exact Or.inr ⟨k, bl, hk, hl.sub.trans hs'⟩
  · exact absurd hn (hnn0 k q)

/-- `rootKeep_frame` where only the borrowed parameters outside the bindings
    `sp` are anchored in `F`, and none of them depends on those bindings: what
    a panic leaves while it unwinds the scopes `sp`. -/
theorem rootKeep_frame_sp {m m' : Mem} {Γ : Ctx} {F sp : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ sp → Anchored E F)
    (hpin : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ sp → ∀ r ∈ roots E.vdeps, r ∉ sp)
    (hF : ∀ o ∈ F, m'.st o = m.st o) {r : Var} {Er : Entry} (hr : Γ r = some Er) (hrs : r ∉ sp)
    (hroot : Er.mode.isRoot = true) (hsame : m'.st r = m.st r)
    (hb : BlkLe m.blk m'.blk := by exact BlkLe.of_le fun _ _ h => h) : RootKeep m m' r := by
  refine RootKeep.of_slot hsame fun n hn => ?_
  rcases hn with ⟨T, hown, ht⟩ | ⟨w, c, hc, ht, hnode⟩ | ⟨w, d, o, l, hc, ht, hdata⟩ | ⟨w, k, q, hc, ht, hn⟩
  · exact Or.inl ⟨T, by rw [hsame]; exact hown, ht⟩
  rotate_left 2
  · exact Or.inr (Or.inr (Or.inr ⟨w, k, q, by rw [hsame]; exact hc, ht, hn⟩))
  all_goals
    obtain ⟨sl, hsl, _, hso, _, _⟩ := hi.slot r Er hr
    have hrb : Er.mode = .rootb := by
      rw [hc] at hsl; cases hsl
      cases hme : Er.mode with
      | own => rw [hme] at hso; simp [Mode.ownSlot] at hso
      | inout b => exact absurd hme (hi.noInout _ Er b hr)
      | rootb => rfl
      | bor => rw [hme] at hroot; simp [Mode.isRoot] at hroot
  · obtain ⟨ty, d, es, hneq⟩ := hnode.eq
    refine Or.inr (Or.inl ⟨w, c, by rw [hsame]; exact hc, ht, ?_⟩)
    rcases rootb_anchor_sp hi hanch hpin r Er n hr hrb hrs (Or.inr (Or.inl ⟨w, c, hc, ht, hnode⟩))
        (by rw [hneq]; intro _ _ h; cases h) with
      ⟨o', T, hoF, hoT, hsT⟩ | ⟨k, bl, hk, hs⟩
    · exact nodeAt_of_owned (by unfold OwnedAt; rw [hF o' hoF]; exact hoT) hsT hneq
    · exact (InMem.grow_pay hb hk hs).nodeAt hneq
  · obtain ⟨ty, c, es, hneq⟩ := hdata.eq
    refine Or.inr (Or.inr (Or.inl ⟨w, d, o, l, by rw [hsame]; exact hc, ht, ?_⟩))
    rcases rootb_anchor_sp hi hanch hpin r Er n hr hrb hrs (Or.inr (Or.inr (Or.inl ⟨w, d, o, l, hc, ht, hdata⟩)))
        (by rw [hneq]; intro _ _ h; cases h) with
      ⟨o', T, hoF, hoT, hsT⟩ | ⟨k, bl, hk, hs⟩
    · exact dataAt_of_owned (by unfold OwnedAt; rw [hF o' hoF]; exact hoT) hsT hneq
    · exact (InMem.grow_pay hb hk hs).dataAt hneq

/-! ### A root that grows or shrinks in place -/

/-- `x`'s tree went from `node t c d es` to `node t c d' es'`. -/
structure Evolve (m m' : Mem) (x : Var) (t : Ty) (c d d' : Nat) (es es' : List Val) : Prop where
  before : m.st x = some ⟨true, some (.node t c d es)⟩
  after  : m'.st x = some ⟨true, some (.node t c d' es')⟩
  wf     : WFv (.vec t) (.node t c d' es')
  blk    : m'.blk = m.blk

theorem rootNode_own {m : Mem} {x : Var} {T n : Val} (h : m.st x = some ⟨true, some T⟩)
    (hn : RootNode m x n) : Top n T := by
  rcases hn with ⟨_, h', ht⟩ | ⟨_, c, h', _⟩ | ⟨_, d, o, l, h', _⟩ | ⟨_, k, q, h', _⟩ <;> rw [h] at h' <;>
    cases h'
  exact ht

theorem rootNode_node {m : Mem} {x : Var} {t : Ty} {c d : Nat} {es : List Val} {n : Val}
    (h : m.st x = some ⟨true, some (.node t c d es)⟩) (hn : RootNode m x n) : n = .node t c d es :=
  (rootNode_own h hn).node

theorem namesL_nil {es : List Val} (h : ∀ e ∈ es, e.names = []) : namesL es = [] := by
  induction es with
  | nil => rfl
  | cons e es ih =>
    simp only [namesL, h e (List.mem_cons_self ..), ih fun x hx => h x (List.mem_cons_of_mem _ hx),
      List.append_nil]

/-- A value of a type that holds no closure holds nothing by name. -/
theorem WFv.names_nil_fn {τ : Ty} {v : Val} (h : WFv τ v) (ht : τ.hasFn = false) : v.names = [] := by
  induction h with
  | int => rfl
  | view => rfl
  | arc => rfl
  | lk => rfl
  | cell => rfl
  | node _ ih => exact namesL_nil fun e he => ih e he ht
  | pair _ _ iha ihb =>
    simp only [Ty.hasFn, Bool.or_eq_false_iff] at ht
    simp [Val.names, iha ht.1, ihb ht.2]
  | inl _ ih => simp only [Ty.hasFn, Bool.or_eq_false_iff] at ht; exact ih ht.1
  | inr _ ih => simp only [Ty.hasFn, Bool.or_eq_false_iff] at ht; exact ih ht.2
  | pkg => cases ht

/-- A value of a type that holds no closure is valid through its
    dependencies on memory alone: it holds nothing by name, and its handles
    and views land through memory. -/
theorem ValOK.memDeps {m : Mem} {τ : Ty} {v : Val} {P H : List Dep} (h : ValOK m τ v P H)
    (hf : τ.hasFn = false) : ValOK m τ v (A2.memDeps P) (A2.memDeps H) := by
  have app : ∀ (P H : List Dep), A2.memDeps (P ++ H) = A2.memDeps P ++ A2.memDeps H := fun _ _ =>
    List.filter_append _ _
  induction h with
  | int => exact .int
  | arc h hw hv hl =>
    obtain ⟨dep, hd, hla⟩ := hl
    exact .arc h hw hv ⟨dep, List.mem_filter.mpr ⟨hd, by simp [hla.notName]⟩, hla⟩
  | lk h => exact .lk h
  | cell => exact .cell
  | @href t c P H h =>
    obtain ⟨dep, hd, d, es, hla, hw', hv, hn, hsh⟩ := h
    have hkm : (!dep.kind.isName) = true := by simp [hla.notName]
    refine .href ⟨dep, List.mem_filter.mpr ⟨hd, hkm⟩, d, es, hla, hw', hv.memDeps, ?_, hsh⟩
    intro c' hc'
    rw [hw'.names_nil_fn hf] at hc'; cases hc'
  | view h =>
    obtain ⟨dep, hd, c0, es0, hks, hla, hrest⟩ := h
    exact .view ⟨dep, List.mem_filter.mpr ⟨hd, by simp [hla.notName]⟩, c0, es0, hks, hla, hrest⟩
  | pair _ _ ihx ihy =>
    simp only [Ty.hasFn, Bool.or_eq_false_iff] at hf
    have hx := ihx hf.1; have hy := ihy hf.2
    rw [app] at hx hy; exact .pair hx hy
  | inl _ ih =>
    simp only [Ty.hasFn, Bool.or_eq_false_iff] at hf
    have hx := ih hf.1; rw [app] at hx; exact .inl hx
  | inr _ ih =>
    simp only [Ty.hasFn, Bool.or_eq_false_iff] at hf
    have hx := ih hf.2; rw [app] at hx; exact .inr hx
  | pkg => cases hf

/-- A borrowed value of a type that holds no closure holds nothing by name. -/
theorem ValOK.names_nil_fn {m : Mem} {τ : Ty} {v : Val} {P H : List Dep} (h : ValOK m τ v P H)
    (hf : τ.hasFn = false) : v.names = [] := by
  induction h with
  | int => rfl
  | arc => rfl
  | lk => rfl
  | cell => rfl
  | href => rfl
  | view => rfl
  | pair _ _ iha ihb =>
    simp only [Ty.hasFn, Bool.or_eq_false_iff] at hf
    simp [Val.names, iha hf.1, ihb hf.2]
  | inl _ ih => simp only [Ty.hasFn, Bool.or_eq_false_iff] at hf; exact ih hf.1
  | inr _ ih => simp only [Ty.hasFn, Bool.or_eq_false_iff] at hf; exact ih hf.2
  | pkg => cases hf

/-- A value whose type holds no views holds no closure, so captures nothing
    by name. -/
theorem WFv.names_nil {τ : Ty} {v : Val} (h : WFv τ v) (ht : τ.holdsView = false) : v.names = [] := by
  induction h with
  | int => rfl
  | view => rfl
  | arc => rfl
  | lk => rfl
  | cell => rfl
  | node _ ih => exact namesL_nil fun e he => ih e he ht
  | pair _ _ iha ihb =>
    simp only [Ty.holdsView, Bool.or_eq_false_iff] at ht
    simp [Val.names, iha ht.1, ihb ht.2]
  | inl _ ih => simp only [Ty.holdsView, Bool.or_eq_false_iff] at ht; exact ih ht.1
  | inr _ ih => simp only [Ty.holdsView, Bool.or_eq_false_iff] at ht; exact ih ht.2
  | pkg _ _ => simp [Ty.holdsView] at ht

theorem no_names {t : Ty} {T : Val} (hw : WFv (.vec t) T) (ht : t.holdsView = false) (H : List Dep) :
    NamesIn T H := by
  intro c hc
  rw [hw.names_nil (by simpa [Ty.holdsView] using ht)] at hc; cases hc

@[simp] theorem ownHeld_false (t : Ty) (H : List Dep) : ownHeld false t H = H := by simp [ownHeld]

theorem ownHeld_sub (o : Bool) (t : Ty) (H : List Dep) : ownHeld o t H ⊆ H := by
  unfold ownHeld; split
  · intro d hd; cases hd
  · exact List.Subset.refl _

theorem ownHeld_mono {t t' : Ty} (h : t.holdsView = true → t'.holdsView = true) (H : List Dep) :
    ownHeld true t H ⊆ ownHeld true t' H := by
  unfold ownHeld
  cases h1 : t.holdsView <;> cases h2 : t'.holdsView <;> simp_all

theorem ownHeld_roots {o : Bool} {t : Ty} {H : List Dep} {r : Var} (h : r ∈ roots (ownHeld o t H)) :
    r ∈ roots H := List.map_subset _ (ownHeld_sub o t H) h

theorem ownHeld_views (o : Bool) {t : Ty} (h : t.holdsView = true) (H : List Dep) : ownHeld o t H = H := by
  simp [ownHeld, h]

/-- Only a type that holds views has a view inside its values. -/
theorem viewIn_holds {t : Ty} {T : Val} {s : Ty} {v : Val} (h : ViewIn t T s v) : t.holdsView = true := by
  induction h <;> simp_all [Ty.holdsView]

theorem ViewsOK.ownHeld {m : Mem} {t : Ty} {T : Val} {H : List Dep} (o : Bool) (h : ViewsOK m t T H) :
    ViewsOK m t T (ownHeld o t H) := by
  unfold A2.ownHeld; split
  · rename_i hc
    intro s v hv
    have := viewIn_holds hv
    simp_all
  · exact h

theorem NamesIn.ownHeld {t : Ty} {T : Val} {H : List Dep} (hw : WFv t T) (o : Bool) (h : NamesIn T H) :
    NamesIn T (A2.ownHeld o t H) := by
  unfold A2.ownHeld; split
  · rename_i hc
    simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hc
    intro c hc'; rw [hw.names_nil hc.2] at hc'; cases hc'
  · exact h

/-- Growing (`vec_push`): what is below the root stays below it. -/
theorem Evolve.grow_vkeep {m m' : Mem} {x : Var} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hev : Evolve m m' x t c d d' es es') (hpre : ∀ e ∈ es, e ∈ es') {k : Kind} (hk : k ≠ .view) :
    VKeep m m' ⟨x, k⟩ := by
  intro dd o l s ⟨c', es2, hks, hla, hl, hw⟩
  rcases hla with ⟨n0, hr, hkk⟩ | ⟨hsk, _, k0, bl, hk0, hs⟩
  · have := rootNode_node hev.before hr
    subst this
    rcases hkk with ⟨hv, _⟩ | ⟨hv, _⟩ | ⟨hki, hb⟩
    · exact absurd hv hks
    · exact absurd hv hk
    · obtain ⟨e, hc, hs⟩ := hb
      cases hc with
      | elem he =>
        exact ⟨c', es2, hks, Or.inl ⟨_, Or.inl ⟨_, hev.after, Top.refl _⟩,
          Or.inr (Or.inr ⟨hki, e, Child.elem (hpre e he), hs⟩)⟩, hl, hw⟩
  · exact ⟨c', es2, hks, Or.inr ⟨hsk, RootMem.own hev.after, k0, bl, by rw [hev.blk]; exact hk0, hs⟩, hl, hw⟩

theorem Evolve.grow_hkeep {m m' : Mem} {x : Var} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hev : Evolve m m' x t c d d' es es') (hpre : ∀ e ∈ es, e ∈ es') {k : Kind}
    (hk : k = .self → t.holdsView = false) (hkv : k ≠ .view)
    (hsh' : SharesOK m' (.vec t) (.node t c d' es')) : HKeep m m' ⟨x, k⟩ := by
  refine ⟨fun c2 t2 H hH hb ⟨d2, es2, hla, hw, hv, hn, hsh⟩ => ?_, fun k2 p2 hb hla => ?_⟩
  rotate_left
  · rcases hla with ⟨n0, hr, hkk⟩ | ⟨hsk, _⟩
    · have := rootNode_node hev.before hr
      subst this
      rcases hkk with ⟨_, heq⟩ | ⟨_, heq⟩ | ⟨hin, hbl⟩
      · cases heq
      · cases heq
      · obtain ⟨e, hc, hs⟩ := hbl
        cases hc with
        | elem he =>
          exact Or.inl ⟨_, Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inr (Or.inr ⟨hin, e, Child.elem (hpre e he), hs⟩)⟩
    · exact Or.inr ⟨hsk, RootMem.own hev.after⟩
  rcases hla with ⟨n0, hr, hkk⟩ | ⟨hsk, _, k0, bl, hk0, hs⟩
  · have := rootNode_node hev.before hr
    subst this
    rcases hkk with ⟨hs, heq⟩ | ⟨hvw, _⟩ | ⟨hin, hbl⟩
    · cases heq
      exact ⟨d', es', Or.inl ⟨_, Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inl ⟨hs, rfl⟩⟩, hev.wf,
        no_views (hk hs) _ _ _, no_names hev.wf (hk hs) _, hsh'⟩
    · exact absurd hvw hkv
    · obtain ⟨e, hc, hs⟩ := hbl
      cases hc with
      | elem he =>
        exact ⟨d2, es2, Or.inl ⟨_, Or.inl ⟨_, hev.after, Top.refl _⟩,
          Or.inr (Or.inr ⟨hin, e, Child.elem (hpre e he), hs⟩)⟩, hw, hv.keep hH, hn, hsh.of_blk hb⟩
  · exact ⟨d2, es2, Or.inr ⟨hsk, RootMem.own hev.after, k0, bl, by rw [hb]; exact hk0, hs⟩, hw, hv.keep hH, hn,
      hsh.of_blk hb⟩

/-- Shrinking (`vec_pop`): only a borrow of the whole handle survives, and
    only of a container that holds no views. -/
theorem Evolve.self_hkeep {m m' : Mem} {x : Var} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hev : Evolve m m' x t c d d' es es') (ht : t.holdsView = false)
    (hsh' : SharesOK m' (.vec t) (.node t c d' es')) : HKeep m m' ⟨x, .self⟩ := by
  refine ⟨fun c2 t2 H hH _ ⟨d2, es2, hla, hw, hv, _⟩ => ?_, fun k2 p2 _ hla => ?_⟩
  rotate_left
  · rcases hla with ⟨n0, hr, hkk⟩ | ⟨hsk, _⟩
    · have := rootNode_node hev.before hr
      subst this
      rcases hkk with ⟨_, heq⟩ | ⟨hin, _⟩ | ⟨hin, _⟩
      · cases heq
      · cases hin
      · cases hin
    · cases hsk
  rcases hla with ⟨n0, hr, hkk⟩ | ⟨hsk, _⟩
  · have := rootNode_node hev.before hr
    subst this
    rcases hkk with ⟨_, heq⟩ | ⟨hin, _⟩ | ⟨hin, _⟩
    · cases heq
      exact ⟨d', es', Or.inl ⟨_, Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inl ⟨rfl, rfl⟩⟩, hev.wf,
        no_views ht _ _ _, no_names hev.wf ht _, hsh'⟩
    · cases hin
    · cases hin
  · cases hsk

/-! ### Rerooting at the end of a borrowed parameter's scope -/

theorem comp_self_left (k : Kind) : comp .self k = k := by cases k <;> rfl

/-- What lands in `p`'s node with kind `k` lands in the node `p` borrows
    from, with the composed kind. -/
theorem lands_comp {n0 n1 N : Val} {kp k : Kind}
    (hp : kp = .self ∧ n0 = n1 ∨ kp = .view ∧ n0 = n1 ∨ kp = .inner ∧ Below n0 n1)
    (hk : k = .self ∧ N = n0 ∨ k = .view ∧ N = n0 ∨ k = .inner ∧ Below N n0) :
    comp kp k = .self ∧ N = n1 ∨ comp kp k = .view ∧ N = n1 ∨ comp kp k = .inner ∧ Below N n1 := by
  rcases hp with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, hb⟩ <;>
    rcases hk with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, hb'⟩
  all_goals first
    | exact Or.inl ⟨rfl, rfl⟩
    | exact Or.inr (Or.inl ⟨rfl, rfl⟩)
    | exact Or.inr (Or.inr ⟨rfl, hb'⟩)
    | exact Or.inr (Or.inr ⟨rfl, hb⟩)
    | exact Or.inr (Or.inr ⟨rfl, Below.of_sub_below hb'.sub hb⟩)

end A2
