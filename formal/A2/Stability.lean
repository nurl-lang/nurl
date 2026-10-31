import A2.Ctx

/-! A2 — what a change of memory leaves valid.

A borrow is valid through one of its dependencies.  If the memory that
dependency's root reaches is unchanged (`RootKeep`) — or changed only in a way
that does not end borrows of that kind (`push`/`pop` on the root) — the borrow
stays valid. -/

namespace A2

def RootKeep (m m' : Mem) (r : Var) : Prop := ∀ n, RootNode m r n → RootNode m' r n

def VKeep (m m' : Mem) (dep : Dep) : Prop :=
  ∀ d o l s, ViewAt m dep d o l s → ViewAt m' dep d o l s

def HKeep (m m' : Mem) (dep : Dep) : Prop :=
  ∀ c t H, (∀ h ∈ H, VKeep m m' h) → m'.blk = m.blk → HrefAt m dep c t H → HrefAt m' dep c t H

/-- A dependency by name reaches no memory: nothing changes what it keeps. -/
theorem vkeep_name (m m' : Mem) (r : Var) (b : Eff) (t : Ty) : VKeep m m' ⟨r, .name b t⟩ := by
  intro d o l s ⟨_, _, _, _, hk, _⟩
  rcases hk with ⟨h, _⟩ | ⟨h, _⟩ <;> cases h

theorem hkeep_name (m m' : Mem) (r : Var) (b : Eff) (t : Ty) : HKeep m m' ⟨r, .name b t⟩ := by
  intro c t H _ _ ⟨_, _, _, _, hl, _⟩
  rcases hl with ⟨h, _⟩ | ⟨h, _⟩ | ⟨h, _⟩ <;> cases h

theorem RootKeep.vkeep {m m' : Mem} {dep : Dep} (h : RootKeep m m' dep.root) : VKeep m m' dep := by
  intro d o l s ⟨n0, c, es, hr, hk, hl, hw⟩
  exact ⟨n0, c, es, h n0 hr, hk, hl, hw⟩

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
  intro c t H hH hb ⟨n0, d, es, hr, hk, hw, hv, hn, hsh⟩
  exact ⟨n0, d, es, h n0 hr, hk, hw, hv.keep hH, hn, hsh.of_blk hb⟩

theorem ValOK.keep {m m' : Mem} {τ : Ty} {v : Val} {P H : List Dep}
    (hp : ∀ dep ∈ P, VKeep m m' dep ∧ HKeep m m' dep) (hh : ∀ dep ∈ H, VKeep m m' dep ∧ HKeep m m' dep)
    (h : ValOK m τ v P H) (hb : m'.blk = m.blk := by rfl) : ValOK m' τ v P H := by
  induction h with
  | int => exact .int
  | arc h hw hv => exact .arc (by rw [hb]; exact h) hw hv
  | href h =>
    obtain ⟨dep, hd, ha⟩ := h
    exact .href ⟨dep, hd, (hp dep hd).2 _ _ _ (fun h hh' => (hh h hh').1) hb ha⟩
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
  ⟨T, Or.inl ⟨o, ho⟩, hs, t, d, es, hn⟩

theorem dataAt_of_owned {m : Mem} {o : Var} {T n : Val} (ho : OwnedAt m o T) (hs : Sub n T)
    {t : Ty} {c d : Nat} {es : List Val} (hn : n = .node t c d es) : DataAt m d n :=
  ⟨T, Or.inl ⟨o, ho⟩, hs, t, c, es, hn⟩

theorem nodeAt_of_tree {m : Mem} {T n : Val} (ho : TreeAt m T) (hs : Sub n T)
    {t : Ty} {c d : Nat} {es : List Val} (hn : n = .node t c d es) : NodeAt m c n :=
  ⟨T, ho, hs, t, d, es, hn⟩

theorem dataAt_of_tree {m : Mem} {T n : Val} (ho : TreeAt m T) (hs : Sub n T)
    {t : Ty} {c d : Nat} {es : List Val} (hn : n = .node t c d es) : DataAt m d n :=
  ⟨T, ho, hs, t, c, es, hn⟩

theorem Lands.subS {k : Kind} {n n0 : Val} (h : Lands k n n0) : SubS n n0 := by
  rcases h with ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, e, hc, hs⟩
  · exact .sub (Sub.refl _)
  · exact .sub (Sub.refl _)
  · exact hs.trans_sub (hc.sub (Sub.refl _))

theorem Top.subS {n v : Val} (h : Top n v) : SubS n v := by
  induction h with
  | refl => exact .sub (Sub.refl _)
  | fst _ ih => exact ih.trans_sub (Sub.fst (Sub.refl _))
  | snd _ ih => exact ih.trans_sub (Sub.snd (Sub.refl _))
  | inl _ ih => exact ih.trans_sub (Sub.inl (Sub.refl _))
  | inr _ ih => exact ih.trans_sub (Sub.inr (Sub.refl _))
  | pkg _ ih => exact ih.trans_sub (Sub.pkg (Sub.refl _))
  | arc _ ih => exact .arc (Sub.refl _) ih

theorem Top.trans {a b c : Val} (h1 : Top a b) (h2 : Top b c) : Top a c := by
  induction h2 with
  | refl => exact h1
  | fst _ ih => exact Top.fst ih
  | snd _ ih => exact Top.snd ih
  | inl _ ih => exact Top.inl ih
  | inr _ ih => exact Top.inr ih
  | pkg _ ih => exact Top.pkg ih
  | arc _ ih => exact Top.arc ih

theorem Top.node {n : Val} {t : Ty} {c d : Nat} {es : List Val} (h : Top n (.node t c d es)) :
    n = .node t c d es := by
  cases h; rfl

/-- Every node a root reaches is inside some owned tree, or (A3.1) in the
    payload of a share one holds. -/
theorem RootNode.owned {m : Mem} {r : Var} {n : Val} (h : RootNode m r n) :
    ∃ T, TreeAt m T ∧ SubS n T := by
  rcases h with ⟨T, h, ht⟩ | ⟨_, c, _, _, T, hT, hs, _⟩ | ⟨_, d, _, _, _, _, T, hT, hs, _⟩
  · exact ⟨T, Or.inl ⟨r, h⟩, ht.subS⟩
  · exact ⟨T, hT, .sub hs⟩
  · exact ⟨T, hT, .sub hs⟩

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
theorem valOK_href {m : Mem} (hh : HeapOK m) (hs : SharesHeld m) {c : Nat} {n : Val} (hn : NodeAt m c n)
    {τ : Ty} {w : Val} {P H : List Dep} (hok : ValOK m τ w P H) (ht : Top (.href c) w) :
    ∃ dep ∈ P ++ H, ∃ n0, RootNode m dep.root n0 ∧ Lands dep.kind n n0 := by
  induction hok with
  | int => cases ht
  | arc _ hw _ => cases ht with | arc h => exact (hw.not_top_href h).elim
  | view _ => cases ht
  | @href t c' P H h =>
    obtain ⟨dep, hd, n1, d, es, hr1, hl, _, _⟩ := h
    cases ht
    obtain ⟨T, hT, hsT⟩ := hr1.owned
    obtain ⟨T', hT', hs'⟩ := SubS.tree hs hT (hl.subS.trans hsT)
    have := nodeAt_unique hh hn ⟨T', hT', hs', t, d, es, rfl⟩
    subst this
    exact ⟨dep, List.mem_append_left _ hd, n1, hr1, hl⟩
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
theorem valOK_view {m : Mem} (hh : HeapOK m) (hs : SharesHeld m) {d o l : Nat} {n : Val} (hn : DataAt m d n)
    {τ : Ty} {w : Val} {P H : List Dep} (hok : ValOK m τ w P H) (ht : Top (.view d o l) w) :
    ∃ dep ∈ P ++ H, ∃ n0, RootNode m dep.root n0 ∧ dep.kind ≠ .self ∧ Lands dep.kind n n0 := by
  induction hok with
  | int => cases ht
  | arc _ hw hv => cases ht with | arc h => exact (hw.not_top_view hv h).elim
  | href _ => cases ht
  | @view t d' o' l' P H h =>
    obtain ⟨dep, hd, n1, c, es, hr1, hk, _, _⟩ := h
    cases ht
    have hl' : Lands dep.kind (.node t c d es) n1 := by
      rcases hk with ⟨h1, h2⟩ | ⟨h1, h2⟩
      · exact Or.inr (Or.inl ⟨h1, h2⟩)
      · exact Or.inr (Or.inr ⟨h1, h2⟩)
    have hks : dep.kind ≠ .self := by rcases hk with ⟨h1, _⟩ | ⟨h1, _⟩ <;> rw [h1] <;> decide
    obtain ⟨T, hT, hsT⟩ := hr1.owned
    obtain ⟨T', hT', hs'⟩ := SubS.tree hs hT (hl'.subS.trans hsT)
    have := dataAt_unique hh hn ⟨T', hT', hs', t, c, es, rfl⟩
    subst this
    exact ⟨dep, List.mem_append_left _ hd, n1, hr1, hks, hl'⟩
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
theorem valOK_via {m : Mem} (hs : SharesHeld m) {y : Var} {T : Val} (hy : m.st y = some ⟨false, some T⟩)
    {τ : Ty} {w : Val} {P H : List Dep} (hok : ValOK m τ w P H) :
    ∀ {Q : List Dep}, Top w T → ⟨y, .view⟩ ∈ Q → ValOK m τ w Q H := by
  induction hok with
  | int => intro _ _ _; exact .int
  | arc h hw hv => intro _ _ _; exact .arc h hw hv
  | @href t c P H h =>
    intro Q ht hq
    obtain ⟨dep, hd, n1, d, es, hr1, hl, hw, hv⟩ := h
    obtain ⟨T', hoT, hsT⟩ := hr1.owned
    obtain ⟨T'', hT'', hs''⟩ := SubS.tree hs hoT (hl.subS.trans hsT)
    exact .href ⟨_, hq, _, d, es,
      Or.inr (Or.inl ⟨T, c, hy, ht, T'', hT'', hs'', t, d, es, rfl⟩),
      Or.inr (Or.inl ⟨rfl, rfl⟩), hw, hv⟩
  | @view t d o l P H h =>
    intro Q ht hq
    obtain ⟨dep, hd, n1, c, es, hr1, hk, hlen, hw⟩ := h
    have hsub : SubS (.node t c d es) n1 := by
      rcases hk with ⟨_, h⟩ | ⟨_, h⟩
      · rw [h]; exact .sub (Sub.refl _)
      · exact h.subS
    obtain ⟨T', hoT, hsT⟩ := hr1.owned
    obtain ⟨T'', hT'', hs''⟩ := SubS.tree hs hoT (hsub.trans hsT)
    exact .view ⟨_, hq, _, c, es,
      Or.inr (Or.inr ⟨T, d, o, l, hy, ht, T'', hT'', hs'', t, c, es, rfl⟩),
      Or.inl ⟨rfl, rfl⟩, hlen, hw⟩
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

/-- What a borrowed slot reaches, it reaches through the dependencies of the
    value it holds. -/
theorem bor_lands {m : Mem} (hh : HeapOK m) (hs : SharesHeld m) {p : Var} {τ : Ty} {w : Val} {P H : List Dep}
    (hp : m.st p = some ⟨false, some w⟩) (hok : ValOK m τ w P H) {n0 : Val}
    (hr : RootNode m p n0) : ∃ d' ∈ P ++ H, ∃ n1, RootNode m d'.root n1 ∧ Lands d'.kind n0 n1 := by
  rcases hr with ⟨T, h, _⟩ | ⟨v, c, hc, ht, hn⟩ | ⟨v, d, o, l, hc, ht, hn⟩
  · rw [hp] at h; cases h
  · rw [hp] at hc; cases hc
    exact valOK_href hh hs hn hok ht
  · rw [hp] at hc; cases hc
    obtain ⟨dep, hd, n1, hr1, _, hl⟩ := valOK_view hh hs hn hok ht
    exact ⟨dep, hd, n1, hr1, hl⟩

/-- What a dependency reaches in memory is reached through one of the
    three kinds that reach memory. -/
theorem lands_bound {k : Kind} {n n0 : Val} (h : Lands k n n0) : k.bound = .none := by
  rcases h with ⟨rfl, _⟩ | ⟨rfl, _⟩ | ⟨rfl, _⟩ <;> rfl

/-- Every borrowed parameter reaches memory inside a frozen owner's tree. -/

theorem rootb_anchor {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F) :
    ∀ p E n, Γ p = some E → E.mode = .rootb → RootNode m p n →
      ∃ o T, o ∈ F ∧ OwnedAt m o T ∧ SubS n T := by
  intro p
  induction p using Nat.strongRecOn with
  | _ p ih =>
  intro E n hp hm hrn
  have hlive := hi.rootbLive p E hp hm
  obtain ⟨sl, hsl, _, hso, _, hbor⟩ := hi.slot p E hp
  have hos : E.mode.ownSlot = false := by rw [hm]; rfl
  obtain ⟨v, hv, hok⟩ := hbor hos hlive
  have hsl' : sl = ⟨false, some v⟩ := by
    obtain ⟨own, val⟩ := sl
    simp only at hv hso; subst hv; rw [hso, hos]
  rw [hsl'] at hsl
  obtain ⟨dep, hd, n0, hr, hl⟩ := bor_lands hi.heap hi.sharesHeld hsl hok hrn
  have hdv : dep.root ∈ roots E.vdeps := by
    simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.mem_map]
    exact ⟨dep, hd, rfl⟩
  have hF : dep.root ∈ F := by
    refine hanch p E hp hm dep ?_ (lands_bound hl)
    simp only [Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte]
    exact hd
  have hnint : E.ty ≠ .int := by
    intro h; rw [h] at hok; obtain ⟨k, rfl⟩ := hok
    rcases hrn with ⟨_, h1, _⟩ | ⟨_, c, h1, ht, _⟩ | ⟨_, d, o, l, h1, ht, _⟩ <;> rw [hsl] at h1 <;>
      cases h1 <;> cases ht
  obtain ⟨Er, hEr, hroot⟩ := hi.wf p E hp hlive (Or.inl hnint) dep.root hdv
  rcases hr with ⟨T, hown, ht⟩ | ⟨w, c, hc, ht, hn⟩ | ⟨w, d, o, l, hc, ht, hn⟩
  · exact ⟨dep.root, T, hF, hown, hl.subS.trans ht.subS⟩
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
  · obtain ⟨o', T', hF', ho', hs'⟩ := ih dep.root hlt Er n0 hEr hrb (Or.inr (Or.inl ⟨w, c, hc, ht, hn⟩))
    exact ⟨o', T', hF', ho', hl.subS.trans hs'⟩
  · obtain ⟨o', T', hF', ho', hs'⟩ := ih dep.root hlt Er n0 hEr hrb (Or.inr (Or.inr ⟨w, d, o, l, hc, ht, hn⟩))
    exact ⟨o', T', hF', ho', hl.subS.trans hs'⟩

/-- A root whose slot is unchanged, at a point where every slot that changes
    is outside the frozen owners, reaches the same memory. -/
theorem rootKeep_frame {m m' : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    (hF : ∀ o ∈ F, m'.st o = m.st o) {r : Var} {Er : Entry} (hr : Γ r = some Er)
    (hroot : Er.mode.isRoot = true) (hsame : m'.st r = m.st r) (hb : m'.blk = m.blk := by rfl) :
    RootKeep m m' r := by
  intro n hn
  rcases hn with ⟨T, hown, ht⟩ | ⟨w, c, hc, ht, hnode⟩ | ⟨w, d, o, l, hc, ht, hdata⟩
  · exact Or.inl ⟨T, by rw [hsame]; exact hown, ht⟩
  all_goals
    obtain ⟨sl, hsl, _, hso, _, _⟩ := hi.slot r Er hr
    have hrb : Er.mode = .rootb := by
      rw [hc] at hsl; cases hsl
      cases hme : Er.mode with
      | own => rw [hme] at hso; simp [Mode.ownSlot] at hso
      | inout b => exact absurd hme (hi.noInout _ Er b hr)
      | rootb => rfl
      | bor => rw [hme] at hroot; simp [Mode.isRoot] at hroot
  · obtain ⟨o', T, hoF, hoT, hsT⟩ :=
      rootb_anchor hi hanch r Er n hr hrb (Or.inr (Or.inl ⟨w, c, hc, ht, hnode⟩))
    obtain ⟨_, _, _, ty, d, es, hneq⟩ := hnode
    refine Or.inr (Or.inl ⟨w, c, by rw [hsame]; exact hc, ht, ?_⟩)
    rcases hsT.loc hi.sharesHeld (Or.inl ⟨o', hoT⟩) with h | ⟨k, u, p, hk, h⟩
    · exact nodeAt_of_owned (by unfold OwnedAt; rw [hF o' hoF]; exact hoT) h hneq
    · exact nodeAt_of_tree (Or.inr ⟨k, u, by rw [hb]; exact hk⟩) h hneq
  · obtain ⟨o', T, hoF, hoT, hsT⟩ :=
      rootb_anchor hi hanch r Er n hr hrb (Or.inr (Or.inr ⟨w, d, o, l, hc, ht, hdata⟩))
    obtain ⟨_, _, _, ty, c, es, hneq⟩ := hdata
    refine Or.inr (Or.inr ⟨w, d, o, l, by rw [hsame]; exact hc, ht, ?_⟩)
    rcases hsT.loc hi.sharesHeld (Or.inl ⟨o', hoT⟩) with h | ⟨k, u, p, hk, h⟩
    · exact dataAt_of_owned (by unfold OwnedAt; rw [hF o' hoF]; exact hoT) h hneq
    · exact dataAt_of_tree (Or.inr ⟨k, u, by rw [hb]; exact hk⟩) h hneq

/-- `rootb_anchor` for the borrowed parameters outside the bindings `sp`. -/
theorem rootb_anchor_sp {m : Mem} {Γ : Ctx} {F sp : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ sp → Anchored E F)
    (hpin : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ sp → ∀ r ∈ roots E.vdeps, r ∉ sp) :
    ∀ p E n, Γ p = some E → E.mode = .rootb → p ∉ sp → RootNode m p n →
      ∃ o T, o ∈ F ∧ OwnedAt m o T ∧ SubS n T := by
  intro p
  induction p using Nat.strongRecOn with
  | _ p ih =>
  intro E n hp hm hps hrn
  have hlive := hi.rootbLive p E hp hm
  obtain ⟨sl, hsl, _, hso, _, hbor⟩ := hi.slot p E hp
  have hos : E.mode.ownSlot = false := by rw [hm]; rfl
  obtain ⟨v, hv, hok⟩ := hbor hos hlive
  have hsl' : sl = ⟨false, some v⟩ := by
    obtain ⟨own, val⟩ := sl
    simp only at hv hso; subst hv; rw [hso, hos]
  rw [hsl'] at hsl
  obtain ⟨dep, hd, n0, hr, hl⟩ := bor_lands hi.heap hi.sharesHeld hsl hok hrn
  have hdv : dep.root ∈ roots E.vdeps := by
    simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.mem_map]
    exact ⟨dep, hd, rfl⟩
  have hF : dep.root ∈ F := by
    refine hanch p E hp hm hps dep ?_ (lands_bound hl)
    simp only [Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte]
    exact hd
  have hnint : E.ty ≠ .int := by
    intro h; rw [h] at hok; obtain ⟨k, rfl⟩ := hok
    rcases hrn with ⟨_, h1, _⟩ | ⟨_, c, h1, ht, _⟩ | ⟨_, d, o, l, h1, ht, _⟩ <;> rw [hsl] at h1 <;>
      cases h1 <;> cases ht
  obtain ⟨Er, hEr, hroot⟩ := hi.wf p E hp hlive (Or.inl hnint) dep.root hdv
  rcases hr with ⟨T, hown, ht⟩ | ⟨w, c, hc, ht, hn⟩ | ⟨w, d, o, l, hc, ht, hn⟩
  · exact ⟨dep.root, T, hF, hown, hl.subS.trans ht.subS⟩
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
  · obtain ⟨o', T', hF', ho', hs'⟩ := ih dep.root hlt Er n0 hEr hrb (hpin p E hp hm hps dep.root hdv) (Or.inr (Or.inl ⟨w, c, hc, ht, hn⟩))
    exact ⟨o', T', hF', ho', hl.subS.trans hs'⟩
  · obtain ⟨o', T', hF', ho', hs'⟩ := ih dep.root hlt Er n0 hEr hrb (hpin p E hp hm hps dep.root hdv) (Or.inr (Or.inr ⟨w, d, o, l, hc, ht, hn⟩))
    exact ⟨o', T', hF', ho', hl.subS.trans hs'⟩

/-- `rootKeep_frame` where only the borrowed parameters outside the bindings
    `sp` are anchored in `F`, and none of them depends on those bindings: what
    a panic leaves while it unwinds the scopes `sp`. -/
theorem rootKeep_frame_sp {m m' : Mem} {Γ : Ctx} {F sp : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ sp → Anchored E F)
    (hpin : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ sp → ∀ r ∈ roots E.vdeps, r ∉ sp)
    (hF : ∀ o ∈ F, m'.st o = m.st o) {r : Var} {Er : Entry} (hr : Γ r = some Er) (hrs : r ∉ sp)
    (hroot : Er.mode.isRoot = true) (hsame : m'.st r = m.st r) (hb : m'.blk = m.blk := by rfl) :
    RootKeep m m' r := by
  intro n hn
  rcases hn with ⟨T, hown, ht⟩ | ⟨w, c, hc, ht, hnode⟩ | ⟨w, d, o, l, hc, ht, hdata⟩
  · exact Or.inl ⟨T, by rw [hsame]; exact hown, ht⟩
  all_goals
    obtain ⟨sl, hsl, _, hso, _, _⟩ := hi.slot r Er hr
    have hrb : Er.mode = .rootb := by
      rw [hc] at hsl; cases hsl
      cases hme : Er.mode with
      | own => rw [hme] at hso; simp [Mode.ownSlot] at hso
      | inout b => exact absurd hme (hi.noInout _ Er b hr)
      | rootb => rfl
      | bor => rw [hme] at hroot; simp [Mode.isRoot] at hroot
  · obtain ⟨o', T, hoF, hoT, hsT⟩ :=
      rootb_anchor_sp hi hanch hpin r Er n hr hrb hrs (Or.inr (Or.inl ⟨w, c, hc, ht, hnode⟩))
    obtain ⟨_, _, _, ty, d, es, hneq⟩ := hnode
    refine Or.inr (Or.inl ⟨w, c, by rw [hsame]; exact hc, ht, ?_⟩)
    rcases hsT.loc hi.sharesHeld (Or.inl ⟨o', hoT⟩) with h | ⟨k, u, p, hk, h⟩
    · exact nodeAt_of_owned (by unfold OwnedAt; rw [hF o' hoF]; exact hoT) h hneq
    · exact nodeAt_of_tree (Or.inr ⟨k, u, by rw [hb]; exact hk⟩) h hneq
  · obtain ⟨o', T, hoF, hoT, hsT⟩ :=
      rootb_anchor_sp hi hanch hpin r Er n hr hrb hrs (Or.inr (Or.inr ⟨w, d, o, l, hc, ht, hdata⟩))
    obtain ⟨_, _, _, ty, c, es, hneq⟩ := hdata
    refine Or.inr (Or.inr ⟨w, d, o, l, by rw [hsame]; exact hc, ht, ?_⟩)
    rcases hsT.loc hi.sharesHeld (Or.inl ⟨o', hoT⟩) with h | ⟨k, u, p, hk, h⟩
    · exact dataAt_of_owned (by unfold OwnedAt; rw [hF o' hoF]; exact hoT) h hneq
    · exact dataAt_of_tree (Or.inr ⟨k, u, by rw [hb]; exact hk⟩) h hneq

/-! ### A root that grows or shrinks in place -/

/-- `x`'s tree went from `node t c d es` to `node t c d' es'`. -/
structure Evolve (m m' : Mem) (x : Var) (t : Ty) (c d d' : Nat) (es es' : List Val) : Prop where
  before : m.st x = some ⟨true, some (.node t c d es)⟩
  after  : m'.st x = some ⟨true, some (.node t c d' es')⟩
  wf     : WFv (.vec t) (.node t c d' es')

theorem rootNode_own {m : Mem} {x : Var} {T n : Val} (h : m.st x = some ⟨true, some T⟩)
    (hn : RootNode m x n) : Top n T := by
  rcases hn with ⟨_, h', ht⟩ | ⟨_, c, h', _⟩ | ⟨_, d, o, l, h', _⟩ <;> rw [h] at h' <;> cases h'
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
  | arc h hw hv => exact .arc h hw hv
  | @href t c P H h =>
    obtain ⟨dep, hd, n0, d, es, hr, hk, hw', hv, hn, hsh⟩ := h
    have hkm : (!dep.kind.isName) = true := by
      rcases hk with ⟨hk, _⟩ | ⟨hk, _⟩ | ⟨hk, _⟩ <;> rw [hk] <;> rfl
    refine .href ⟨dep, List.mem_filter.mpr ⟨hd, hkm⟩, n0, d, es, hr, hk, hw', hv.memDeps, ?_, hsh⟩
    intro c' hc'
    rw [hw'.names_nil_fn hf] at hc'; cases hc'
  | view h =>
    obtain ⟨dep, hd, n0, c', es', hr, hk, hol, hw''⟩ := h
    refine .view ⟨dep, List.mem_filter.mpr ⟨hd, ?_⟩, n0, c', es', hr, hk, hol, hw''⟩
    rcases hk with ⟨hk, _⟩ | ⟨hk, _⟩ <;> rw [hk] <;> rfl
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
  intro dd o l s ⟨n0, c', es2, hr, hkk, hl, hw⟩
  have := rootNode_node hev.before hr
  subst this
  rcases hkk with ⟨hv, _⟩ | ⟨hki, hb⟩
  · exact absurd hv hk
  · obtain ⟨e, hc, hs⟩ := hb
    cases hc with
    | elem he =>
      exact ⟨_, c', es2, Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inr ⟨hki, e, Child.elem (hpre e he), hs⟩, hl, hw⟩

theorem Evolve.grow_hkeep {m m' : Mem} {x : Var} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hev : Evolve m m' x t c d d' es es') (hpre : ∀ e ∈ es, e ∈ es') {k : Kind}
    (hk : k = .self → t.holdsView = false) (hkv : k ≠ .view)
    (hsh' : SharesOK m' (.vec t) (.node t c d' es')) : HKeep m m' ⟨x, k⟩ := by
  intro c2 t2 H hH hb ⟨n0, d2, es2, hr, hkk, hw, hv, hn, hsh⟩
  have := rootNode_node hev.before hr
  subst this
  rcases hkk with ⟨hs, heq⟩ | ⟨hvw, _⟩ | ⟨hin, hb⟩
  · cases heq
    exact ⟨_, d', es', Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inl ⟨hs, rfl⟩, hev.wf, no_views (hk hs) _ _ _,
      no_names hev.wf (hk hs) _, hsh'⟩
  · exact absurd hvw hkv
  · obtain ⟨e, hc, hs⟩ := hb
    cases hc with
    | elem he =>
      exact ⟨_, d2, es2, Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inr (Or.inr ⟨hin, e, Child.elem (hpre e he), hs⟩),
        hw, hv.keep hH, hn, hsh.of_blk hb⟩

/-- Shrinking (`vec_pop`): only a borrow of the whole handle survives, and
    only of a container that holds no views. -/
theorem Evolve.self_hkeep {m m' : Mem} {x : Var} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hev : Evolve m m' x t c d d' es es') (ht : t.holdsView = false)
    (hsh' : SharesOK m' (.vec t) (.node t c d' es')) : HKeep m m' ⟨x, .self⟩ := by
  intro c2 t2 H hH _ ⟨n0, d2, es2, hr, hkk, hw, hv, _⟩
  have := rootNode_node hev.before hr
  subst this
  rcases hkk with ⟨_, heq⟩ | ⟨hin, _⟩ | ⟨hin, _⟩
  · cases heq
    exact ⟨_, d', es', Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inl ⟨rfl, rfl⟩, hev.wf, no_views ht _ _ _,
      no_names hev.wf ht _, hsh'⟩
  · cases hin
  · cases hin

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
    | exact Or.inr (Or.inr ⟨rfl, Below.of_subS_below hb'.subS hb⟩)

end A2
