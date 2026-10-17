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
  ∀ c t H, (∀ h ∈ H, VKeep m m' h) → HrefAt m dep c t H → HrefAt m' dep c t H

theorem RootKeep.vkeep {m m' : Mem} {dep : Dep} (h : RootKeep m m' dep.root) : VKeep m m' dep := by
  intro d o l s ⟨n0, c, es, hr, hk, hl, hw⟩
  exact ⟨n0, c, es, h n0 hr, hk, hl, hw⟩

theorem ViewsOK.keep {m m' : Mem} {τ : Ty} {T : Val} {H : List Dep} (hk : ∀ h ∈ H, VKeep m m' h)
    (hv : ViewsOK m τ T H) : ViewsOK m' τ T H := by
  intro s v hin
  obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := hv s v hin
  exact ⟨d, o, l, rfl, dep, hd, hk dep hd d o l s ha⟩

theorem RootKeep.hkeep {m m' : Mem} {dep : Dep} (h : RootKeep m m' dep.root) : HKeep m m' dep := by
  intro c t H hH ⟨n0, d, es, hr, hk, hw, hv⟩
  exact ⟨n0, d, es, h n0 hr, hk, hw, hv.keep hH⟩

theorem ValOK.keep {m m' : Mem} {τ : Ty} {v : Val} {P H : List Dep}
    (hp : ∀ dep ∈ P, VKeep m m' dep ∧ HKeep m m' dep) (hh : ∀ dep ∈ H, VKeep m m' dep ∧ HKeep m m' dep)
    (h : ValOK m τ v P H) : ValOK m' τ v P H := by
  induction τ generalizing v P with
  | int => exact h
  | vec t =>
    obtain ⟨c, rfl, dep, hd, ha⟩ := h
    exact ⟨c, rfl, dep, hd, (hp dep hd).2 c t H (fun h hh' => (hh h hh').1) ha⟩
  | slice t =>
    obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := h
    exact ⟨d, o, l, rfl, dep, hd, (hp dep hd).1 d o l t ha⟩
  | prod a b iha ihb =>
    obtain ⟨x, y, rfl, hx, hy⟩ := h
    have hph : ∀ dep ∈ P ++ H, VKeep m m' dep ∧ HKeep m m' dep := fun dep hd => by
      rcases List.mem_append.mp hd with hd | hd
      · exact hp dep hd
      · exact hh dep hd
    exact ⟨x, y, rfl, iha hph hx, ihb hph hy⟩
  | sum a b iha ihb =>
    have hph : ∀ dep ∈ P ++ H, VKeep m m' dep ∧ HKeep m m' dep := fun dep hd => by
      rcases List.mem_append.mp hd with hd | hd
      · exact hp dep hd
      · exact hh dep hd
    rcases h with ⟨x, rfl, hx⟩ | ⟨x, rfl, hx⟩
    · exact Or.inl ⟨x, rfl, iha hph hx⟩
    · exact Or.inr ⟨x, rfl, ihb hph hx⟩

/-! ### Borrowed parameters reach only frozen owners -/

theorem ViewIn.holdsView {τ T s v} (h : ViewIn τ T s v) : τ.holdsView = true := by
  induction h with
  | here => rfl
  | child _ _ ih => simpa [Ty.holdsView] using ih
  | fst _ ih => simp [Ty.holdsView, ih]
  | snd _ ih => simp [Ty.holdsView, ih]
  | inl _ ih => simp [Ty.holdsView, ih]
  | inr _ ih => simp [Ty.holdsView, ih]

theorem no_views {t : Ty} (ht : t.holdsView = false) (m : Mem) (T : Val) (H : List Dep) :
    ViewsOK m (.vec t) T H := by
  intro s v hin
  have := hin.holdsView
  simp [Ty.holdsView, ht] at this

theorem nodeAt_of_owned {m : Mem} {o : Var} {T n : Val} (ho : OwnedAt m o T) (hs : Sub n T)
    {t : Ty} {c d : Nat} {es : List Val} (hn : n = .node t c d es) : NodeAt m c n :=
  ⟨o, T, ho, hs, t, d, es, hn⟩

theorem dataAt_of_owned {m : Mem} {o : Var} {T n : Val} (ho : OwnedAt m o T) (hs : Sub n T)
    {t : Ty} {c d : Nat} {es : List Val} (hn : n = .node t c d es) : DataAt m d n :=
  ⟨o, T, ho, hs, t, c, es, hn⟩

/-- Every borrowed parameter reaches memory inside a frozen owner's tree. -/
theorem rootb_anchor {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F) :
    ∀ p E n, Γ p = some E → E.mode = .rootb → RootNode m p n →
      ∃ o T, o ∈ F ∧ OwnedAt m o T ∧ Sub n T := by
  intro p
  induction p using Nat.strongRecOn with
  | _ p ih =>
  intro E n hp hm hrn
  have hlive := hi.rootbLive p E hp hm
  obtain ⟨sl, hsl, _, hso, _, hbor⟩ := hi.slot p E hp
  have hos : E.mode.ownSlot = false := by rw [hm]; rfl
  obtain ⟨v, hv, hok⟩ := hbor hos hlive
  have hsl' : sl.own = false := by rw [hso, hos]
  -- The dependency the borrow is valid through.
  have key : ∀ (dep : Dep) (N : Val), dep ∈ E.path → (∃ n0, RootNode m dep.root n0 ∧ Sub N n0) →
      ∃ o T, o ∈ F ∧ OwnedAt m o T ∧ Sub N T := by
    intro dep N hd ⟨n0, hr, hs⟩
    have hdv : dep.root ∈ roots E.vdeps := by
      simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.map_append, List.mem_append, List.mem_map]
      exact Or.inl ⟨dep, hd, rfl⟩
    have hF := hanch p E hp hm dep.root hdv
    have hnint : E.ty ≠ .int := by
      intro h; rw [h] at hok; obtain ⟨k, hk⟩ := hok; subst hk
      obtain ⟨own, val⟩ := sl
      simp only at hv hsl'
      subst hv; subst hsl'
      rcases hrn with h1 | ⟨c, h1, _⟩ | ⟨d, o, l, h1, _⟩ <;> rw [hsl] at h1 <;> simp at h1
    obtain ⟨Er, hEr, hroot⟩ := hi.wf p E hp hlive (Or.inl hnint) dep.root hdv
    rcases hr with hown | ⟨c, hc, hn⟩ | ⟨d, o, l, hc, hn⟩
    · exact ⟨dep.root, n0, hF, hown, hs⟩
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
      obtain ⟨o', T', hF', ho', hs'⟩ := ih dep.root hlt Er n0 hEr hrb
        (Or.inr (by first | exact Or.inl ⟨c, hc, hn⟩ | exact Or.inr ⟨d, o, l, hc, hn⟩))
      exact ⟨o', T', hF', ho', hs.trans hs'⟩
  rcases hrn with hown | ⟨c, hc, hn⟩ | ⟨d, o, l, hc, hn⟩
  · rw [hsl] at hown; cases hown; simp at hsl'
  · rw [hsl] at hc; cases hc; cases hv
    cases hty : E.ty with
    | int => rw [hty] at hok; simp [ValOK] at hok
    | slice t => rw [hty] at hok; simp [ValOK] at hok
    | prod a b => rw [hty] at hok; simp [ValOK] at hok
    | sum a b => rw [hty] at hok; simp [ValOK] at hok
    | vec t =>
      rw [hty] at hok
      obtain ⟨c', hc', dep, hd, n0, d, es, hr, hk, _, _⟩ := hok
      injection hc' with hcc; subst hcc
      have hsub : Sub (.node t c d es) n0 := by
        rcases hk with ⟨_, h⟩ | ⟨_, h⟩ | ⟨_, h⟩
        · rw [h]; exact Sub.refl _
        · rw [h]; exact Sub.refl _
        · exact h.sub
      obtain ⟨o, T, hF, hoT, hsT⟩ := key dep _ hd ⟨n0, hr, hsub⟩
      have := nodeAt_unique hi.heap hn (nodeAt_of_owned hoT hsT rfl)
      subst this
      exact ⟨o, T, hF, hoT, hsT⟩
  · rw [hsl] at hc; cases hc; cases hv
    cases hty : E.ty with
    | int => rw [hty] at hok; simp [ValOK] at hok
    | vec t => rw [hty] at hok; simp [ValOK] at hok
    | prod a b => rw [hty] at hok; simp [ValOK] at hok
    | sum a b => rw [hty] at hok; simp [ValOK] at hok
    | slice t =>
      rw [hty] at hok
      obtain ⟨d', o', l', hv', dep, hd, n0, c, es, hr, hk, _, _⟩ := hok
      injection hv' with hdd; subst hdd
      have hsub : Sub (.node t c d es) n0 := by
        rcases hk with ⟨_, h⟩ | ⟨_, h⟩
        · rw [h]; exact Sub.refl _
        · exact h.sub
      obtain ⟨o2, T, hF, hoT, hsT⟩ := key dep _ hd ⟨n0, hr, hsub⟩
      have := dataAt_unique hi.heap hn (dataAt_of_owned hoT hsT rfl)
      subst this
      exact ⟨o2, T, hF, hoT, hsT⟩

/-- A root whose slot is unchanged, at a point where every slot that changes
    is outside the frozen owners, reaches the same memory. -/
theorem rootKeep_frame {m m' : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    (hF : ∀ o ∈ F, m'.st o = m.st o) {r : Var} {Er : Entry} (hr : Γ r = some Er)
    (hroot : Er.mode.isRoot = true) (hsame : m'.st r = m.st r) : RootKeep m m' r := by
  intro n hn
  rcases hn with hown | ⟨c, hc, hnode⟩ | ⟨d, o, l, hc, hdata⟩
  · exact Or.inl (by rw [hsame]; exact hown)
  all_goals
    obtain ⟨sl, hsl, _, hso, _, _⟩ := hi.slot r Er hr
    have hrb : Er.mode = .rootb := by
      rw [hc] at hsl; cases hsl
      cases hme : Er.mode with
      | own => rw [hme] at hso; simp [Mode.ownSlot] at hso
      | inout b => exact absurd hme (hi.noInout _ Er b hr)
      | rootb => rfl
      | bor => rw [hme] at hroot; simp [Mode.isRoot] at hroot
  · obtain ⟨o', T, hoF, hoT, hsT⟩ := rootb_anchor hi hanch r Er n hr hrb (Or.inr (Or.inl ⟨c, hc, hnode⟩))
    obtain ⟨_, _, _, _, ty, d, es, hneq⟩ := hnode
    refine Or.inr (Or.inl ⟨c, by rw [hsame]; exact hc, ?_⟩)
    exact nodeAt_of_owned (by unfold OwnedAt; rw [hF o' hoF]; exact hoT) hsT hneq
  · obtain ⟨o', T, hoF, hoT, hsT⟩ := rootb_anchor hi hanch r Er n hr hrb (Or.inr (Or.inr ⟨d, o, l, hc, hdata⟩))
    obtain ⟨_, _, _, _, ty, c, es, hneq⟩ := hdata
    refine Or.inr (Or.inr ⟨d, o, l, by rw [hsame]; exact hc, ?_⟩)
    exact dataAt_of_owned (by unfold OwnedAt; rw [hF o' hoF]; exact hoT) hsT hneq

/-! ### A root that grows or shrinks in place -/

/-- `x`'s tree went from `node t c d es` to `node t c d' es'`. -/
structure Evolve (m m' : Mem) (x : Var) (t : Ty) (c d d' : Nat) (es es' : List Val) : Prop where
  before : m.st x = some ⟨true, some (.node t c d es)⟩
  after  : m'.st x = some ⟨true, some (.node t c d' es')⟩
  wf     : WFv (.vec t) (.node t c d' es')

theorem rootNode_own {m : Mem} {x : Var} {T n : Val} (h : m.st x = some ⟨true, some T⟩)
    (hn : RootNode m x n) : n = T := by
  rcases hn with h' | ⟨c, h', _⟩ | ⟨d, o, l, h', _⟩ <;> rw [h] at h' <;> cases h'
  rfl

/-- Growing (`vec_push`): what is below the root stays below it. -/
theorem Evolve.grow_vkeep {m m' : Mem} {x : Var} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hev : Evolve m m' x t c d d' es es') (hpre : ∀ e ∈ es, e ∈ es') {k : Kind} (hk : k ≠ .view) :
    VKeep m m' ⟨x, k⟩ := by
  intro dd o l s ⟨n0, c', es2, hr, hkk, hl, hw⟩
  have := rootNode_own hev.before hr
  subst this
  rcases hkk with ⟨hv, _⟩ | ⟨hki, hb⟩
  · exact absurd hv hk
  · obtain ⟨e, hc, hs⟩ := hb
    cases hc with
    | elem he =>
      exact ⟨_, c', es2, Or.inl hev.after, Or.inr ⟨hki, e, Child.elem (hpre e he), hs⟩, hl, hw⟩

theorem Evolve.grow_hkeep {m m' : Mem} {x : Var} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hev : Evolve m m' x t c d d' es es') (hpre : ∀ e ∈ es, e ∈ es') {k : Kind}
    (hk : k = .self → t.holdsView = false) (hkv : k ≠ .view) : HKeep m m' ⟨x, k⟩ := by
  intro c2 t2 H hH ⟨n0, d2, es2, hr, hkk, hw, hv⟩
  have := rootNode_own hev.before hr
  subst this
  rcases hkk with ⟨hs, heq⟩ | ⟨hvw, _⟩ | ⟨hin, hb⟩
  · cases heq
    exact ⟨_, d', es', Or.inl hev.after, Or.inl ⟨hs, rfl⟩, hev.wf, no_views (hk hs) _ _ _⟩
  · exact absurd hvw hkv
  · obtain ⟨e, hc, hs⟩ := hb
    cases hc with
    | elem he =>
      exact ⟨_, d2, es2, Or.inl hev.after, Or.inr (Or.inr ⟨hin, e, Child.elem (hpre e he), hs⟩),
        hw, hv.keep hH⟩

/-- Shrinking (`vec_pop`): only a borrow of the whole handle survives, and
    only of a container that holds no views. -/
theorem Evolve.self_hkeep {m m' : Mem} {x : Var} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hev : Evolve m m' x t c d d' es es') (ht : t.holdsView = false) : HKeep m m' ⟨x, .self⟩ := by
  intro c2 t2 H hH ⟨n0, d2, es2, hr, hkk, hw, hv⟩
  have := rootNode_own hev.before hr
  subst this
  rcases hkk with ⟨_, heq⟩ | ⟨hin, _⟩ | ⟨hin, _⟩
  · cases heq
    exact ⟨_, d', es', Or.inl hev.after, Or.inl ⟨rfl, rfl⟩, hev.wf, no_views ht _ _ _⟩
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
    | exact Or.inr (Or.inr ⟨rfl, Below.of_sub_below hb'.sub hb⟩)

end A2
