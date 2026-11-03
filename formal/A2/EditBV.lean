import A2.EditB

/-! A2 — a view stored through a borrow (Agora #295, `StmtT.editBV`).

`StmtT.editB` changes a `Vec`'s elements through a borrow `x` when the
elements hold no views. `StmtT.editBV` takes elements that do (a slice, a
struct holding one; not a closure, `t.hasFn = false`): a push or an element
set may store a view, so the tree it lands in comes to hold a view of what
the stored value depends on (`D`, its memory dependencies). The typing cannot
tell which memory root of `x`'s path owns that tree (`MInv.thru_owner`), so
each of them holds `D` (`holdThru`, as the owner of a `push` holds what it
was handed, `StmtT.push`), and so does `x` itself, whose node now holds the
view. The kills are those of `editB`, with views among a root's elements when
its type holds them (`killThruV`): a root that may hold the view also ends
the borrows of its whole handle (`Eff.kills _ true .self`), which do not hold
`D`. The proof here follows `EditB.lean`:

* the owner's change of memory: `.realloc` for a push through a copy of a
  same-typed root's handle, the root's own push (`MInv.edit_growV`, from
  `push_grow`, which takes view-holding elements), `.drop` otherwise
  (`MInv.edit_dropV`: `MInv.change` with `NewSlot.editV`; every view of the
  rewritten tree is one of the old tree's or one of the stored value's,
  `NSE_viewIn'`, valid through `D`, none of whose roots is the owner, so it
  stays valid, `keepV`);
* every other root only ends what depends on it (`MInv.killHv_more`) and
  holds `D` too (`MInv.holdOn`: its tree is as it was, and what it holds
  only grows);
* `x` itself is set back live, holding `D` too: its node keeps its cell
  where it was (`editB_hrefAt'`), and the views of the new node are the old
  node's, valid through what `x` held, or the stored value's
  (`MInv.editBV_rest`). -/

namespace A2

/-! ### Kills with views, in any order, once -/

/-- An entry that depends on nothing no kill ends. -/
theorem killHv_nil' {Γ : Ctx} {v : Var} {E : Entry} (hv : Γ v = some E) (h : E.vdeps = []) :
    ∀ ks, A2.killHv ks Γ v = some E
  | [] => hv
  | (e, b, r) :: ks => by
    show (A2.killHv ks Γ v).map _ = _
    rw [killHv_nil' hv h ks]; simp [killE_nil h]

theorem killHv_kill (e : Eff) (hv : Bool) (r : Var) (Γ : Ctx) :
    ∀ ks, A2.killHv ks (A2.kill e hv r Γ) = A2.kill e hv r (A2.killHv ks Γ)
  | [] => rfl
  | (e', b, r') :: ks => by
    show A2.kill _ _ _ (A2.killHv ks (A2.kill e hv r Γ)) = A2.kill e hv r (A2.kill _ _ _ (A2.killHv ks Γ))
    rw [killHv_kill e hv r Γ ks, kill_comm]

/-- A kill among `killHv`'s, done again, changes nothing. -/
theorem kill_killHv_mem {Γ : Ctx} : ∀ {ks : List (Eff × Bool × Var)} {k : Eff × Bool × Var}, k ∈ ks →
    A2.kill k.1 k.2.1 k.2.2 (A2.killHv ks Γ) = A2.killHv ks Γ
  | (e, b, r) :: ks, k, hk => by
    show A2.kill _ _ _ (A2.kill e b r (A2.killHv ks Γ)) = A2.kill e b r (A2.killHv ks Γ)
    rcases List.mem_cons.mp hk with rfl | hk
    · exact kill_idem _ _ _ _
    · rw [kill_comm, kill_killHv_mem hk]

/-- ... so a kill already done is absorbed by `killHv`. -/
theorem killHv_absorb {Γ : Ctx} {ks : List (Eff × Bool × Var)} {k : Eff × Bool × Var} (hk : k ∈ ks) :
    A2.killHv ks (A2.kill k.1 k.2.1 k.2.2 Γ) = A2.killHv ks Γ := by
  rw [killHv_kill, kill_killHv_mem hk]

theorem RootbAnch.killHv {Γ : Ctx} {F : List Var} (h : RootbAnch Γ F) :
    ∀ ks, RootbAnch (A2.killHv ks Γ) F
  | [] => h
  | (_, _, _) :: ks => show RootbAnch (A2.kill _ _ _ (A2.killHv ks Γ)) F from (RootbAnch.killHv h ks).kill _ _ _

/-- Ending entries at roots not lent out, by effects below `replace`, with
    views or not, changes no memory and keeps the invariant. -/
theorem MInv.killHv_more {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hanch : RootbAnch Γ F) :
    ∀ ks : List (Eff × Bool × Var), (∀ k ∈ ks, k.2.2 ∉ F ∧ k.1 ≠ .replace) → MInv m (A2.killHv ks Γ)
  | [], _ => hi
  | (e, b, r) :: ks, h => by
    have ih := MInv.killHv_more hi hanch ks (fun k hk => h k (List.mem_cons_of_mem _ hk))
    exact ih.kill_more (hanch.killHv ks) (h _ List.mem_cons_self).1 (h _ List.mem_cons_self).2 b

/-- The kills of a change through a borrow are below `.replace`, on roots
    the change allows (`ThruOK`), so none is lent out. -/
theorem thruKills_ok {Γ1 : Ctx} {F : List Var} {op : Edit} {tx : Ty} {P : List Dep}
    (hthru : ThruOK Γ1 F op tx P) : ∀ k ∈ thruKills op Γ1 tx P, k.2.2 ∉ F ∧ k.1 ≠ .replace := by
  intro k hk
  obtain ⟨d, hd, rfl⟩ := mem_thruKills.mp hk
  exact ⟨(hthru d hd).1, Edit.effAt_ne_replace _ _ _⟩

/-! ### Holding more, and kills -/

/-- A kill on a root that `D` does not depend on decides alike whether the
    binding holds `D` too or not. -/
theorem hits_hold {e : Eff} {hv : Bool} {r : Var} {D : List Dep} (hD : r ∉ roots D) (E : Entry) :
    hits e hv r (E.hold D) = hits e hv r E := by
  unfold hits
  rw [Entry.hold_vdeps, List.any_append]
  have : (ownHeld true E.ty D).any (fun d => d.root == r && e.kills hv d.kind) = false := by
    rw [List.any_eq_false]
    intro d hd hh
    simp only [Bool.and_eq_true, beq_iff_eq] at hh
    exact hD (hh.1 ▸ List.mem_map_of_mem (ownHeld_sub _ _ _ hd))
  rw [this, Bool.or_false]; rfl

theorem killE_hold {e : Eff} {hv : Bool} {r : Var} {D : List Dep} (hD : r ∉ roots D) (E : Entry) :
    killE e hv r (E.hold D) = (killE e hv r E).hold D := by
  unfold killE; rw [hits_hold hD]; split <;> rfl

theorem kill_holdOn {e : Eff} {hv : Bool} {r : Var} {D : List Dep} (hD : r ∉ roots D) (rs : List Var)
    (Γ : Ctx) : A2.kill e hv r (A2.holdOn rs D Γ) = A2.holdOn rs D (A2.kill e hv r Γ) := by
  funext v
  cases hE : Γ v with
  | none => simp [A2.kill, A2.holdOn, hE]
  | some E =>
    by_cases hv' : v ∈ rs
    · simp [A2.kill, A2.holdOn, hE, hv', killE_hold hD]
    · simp [A2.kill, A2.holdOn, hE, hv']

theorem killHv_holdOn {D : List Dep} (rs : List Var) (Γ : Ctx) :
    ∀ ks : List (Eff × Bool × Var), (∀ k ∈ ks, k.2.2 ∉ roots D) →
      A2.killHv ks (A2.holdOn rs D Γ) = A2.holdOn rs D (A2.killHv ks Γ)
  | [], _ => rfl
  | (e, b, r) :: ks, h => by
    show A2.kill e b r (A2.killHv ks (A2.holdOn rs D Γ)) = A2.holdOn rs D (A2.kill e b r (A2.killHv ks Γ))
    rw [killHv_holdOn rs Γ ks (fun k hk => h k (List.mem_cons_of_mem _ hk)),
      kill_holdOn (h _ List.mem_cons_self)]

/-- The owner holds `D` first, the other roots after: as all at once. -/
theorem holdOn_merge {o : Var} {rs : List Var} (ho : o ∈ rs) (D : List Dep) (Γ : Ctx) :
    A2.holdOn (rs.filter (· != o)) D (A2.holdOn [o] D Γ) = A2.holdOn rs D Γ := by
  funext v
  cases hE : Γ v with
  | none => simp [A2.holdOn, hE]
  | some E =>
    by_cases hvo : v = o
    · subst hvo; simp [A2.holdOn, hE, ho]
    · simp [A2.holdOn, hE, hvo]

theorem RootbAnch.holdOn {Γ : Ctx} {F : List Var} (h : RootbAnch Γ F) {rs : List Var} {D : List Dep}
    (hrs : ∀ v ∈ rs, ∀ E, Γ v = some E → E.mode ≠ .rootb) : RootbAnch (A2.holdOn rs D Γ) F := by
  intro p E' hp hm
  obtain ⟨E, hE, rfl⟩ := holdOn_get hp
  by_cases hpr : p ∈ rs
  · rw [ite_eq_left hpr] at hm; exact absurd hm (hrs p hpr E hE)
  · rw [ite_eq_right hpr] at hm ⊢; exact h p E hE hm

/-! ### Holding more keeps a context well-formed -/

theorem CtxWF.holdOn {Γ : Ctx} (h : CtxWF Γ) {rs : List Var} {D : List Dep}
    (hroot : ∀ r ∈ roots D, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) : CtxWF (A2.holdOn rs D Γ) := by
  have hr : ∀ r, (∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) →
      ∃ Er, A2.holdOn rs D Γ r = some Er ∧ Er.mode.isRoot = true := by
    rintro r ⟨Er, hEr, hro⟩
    exact ⟨_, holdOn_some hEr, by split <;> exact hro⟩
  refine ⟨fun v E' hv hl hn r hrr => ?_, fun v E' hv hd hos hn d hdd hnm => ?_, fun v E' hv ha => ?_,
    fun v E' hv hd => ?_⟩
  · obtain ⟨E, hE, rfl⟩ := holdOn_get hv
    by_cases hvr : v ∈ rs
    · rw [ite_eq_left hvr] at hl hn hrr
      rw [Entry.hold_vdeps] at hrr
      simp only [roots, List.map_append, List.mem_append] at hrr
      rcases hrr with hrr | hrr
      · exact hr r (h v E hE hl hn r hrr)
      · exact hr r (hroot r (ownHeld_roots hrr))
    · rw [ite_eq_right hvr] at hl hn hrr
      exact hr r (h v E hE hl hn r hrr)
  · obtain ⟨E, hE, rfl⟩ := holdOn_get hv
    by_cases hvr : v ∈ rs
    · rw [ite_eq_left hvr] at hd hos hn hdd
      rw [Entry.hold_vdeps] at hdd
      rcases List.mem_append.mp hdd with hdd | hdd
      · exact hr d.root (h.dtor v E hE hd hos hn d hdd hnm)
      · exact hr d.root (hroot d.root (List.mem_map_of_mem (ownHeld_sub _ _ _ hdd)))
    · rw [ite_eq_right hvr] at hd hos hn hdd
      exact hr d.root (h.dtor v E hE hd hos hn d hdd hnm)
  · obtain ⟨E, hE, rfl⟩ := holdOn_get hv
    by_cases hvr : v ∈ rs
    · rw [ite_eq_left hvr] at ha ⊢; exact h.arm v E hE ha
    · rw [ite_eq_right hvr] at ha ⊢; exact h.arm v E hE ha
  · obtain ⟨E, hE, rfl⟩ := holdOn_get hv
    by_cases hvr : v ∈ rs
    · rw [ite_eq_left hvr] at hd ⊢; exact h.view v E hE hd
    · rw [ite_eq_right hvr] at hd ⊢; exact h.view v E hE hd

/-- Holding more memory keeps what is held by name named: a binding held by
    name has a type that holds no views, so it holds nothing more. -/
theorem DepsNamed.holdOn {Γ : Ctx} {D' : List Dep} (h : DepsNamed Γ D') (rs : List Var) (D : List Dep) :
    DepsNamed (A2.holdOn rs D Γ) D' := by
  intro d hd b t hk
  obtain ⟨Er, hEr, hl, hh, ht, ho, hc, hv⟩ := h d hd b t hk
  have hEq : (if d.root ∈ rs then Er.hold D else Er) = Er := by
    split
    · exact Er.hold_noView (by rw [ht]; exact hv) D
    · rfl
  refine ⟨Er, by rw [holdOn_some hEr, hEq], hl, hh, ht, ho, hc, hv⟩

theorem NameWF.holdOn {Γ : Ctx} (h : NameWF Γ) {rs : List Var} {D : List Dep}
    (hnm : ∀ d ∈ D, d.kind.isName = false) : NameWF (A2.holdOn rs D Γ) := by
  intro v E' hv hl hn
  obtain ⟨E, hE, rfl⟩ := holdOn_get hv
  by_cases hvr : v ∈ rs
  · rw [ite_eq_left hvr] at hl hn ⊢
    intro d hd b t hk
    rw [Entry.hold_vdeps] at hd
    rcases List.mem_append.mp hd with hd | hd
    · exact (h v E hE hl hn).holdOn rs D d hd b t hk
    · have := hnm d (ownHeld_sub _ _ _ hd); rw [hk] at this; cases this
  · rw [ite_eq_right hvr] at hl hn ⊢
    exact (h v E hE hl hn).holdOn rs D

/-! ### What the change finds and stores -/

/-- A tree holding a node whose elements may hold views is of a type that
    holds views. -/
theorem WFv.node_holdsView {τ : Ty} {T : Val} (hw : WFv τ T) {u : Ty} {c d : Nat} {es : List Val}
    (hs : Sub (.node u c d es) T) (hu : u.holdsView = true) : τ.holdsView = true := by
  induction hw with
  | int => cases hs
  | view => cases hs
  | arc => cases hs
  | lk => cases hs
  | cell => cases hs
  | node hes ih =>
    rcases hs.cases' with h | ⟨x, hc, hsx⟩
    · cases h; simpa [Ty.holdsView] using hu
    · cases hc with
      | elem hx => simpa [Ty.holdsView] using ih x hx hsx
  | pair _ _ iha ihb =>
    rcases hs.cases' with h | ⟨x, hc, hsx⟩
    · cases h
    · cases hc with
      | fst => simp [Ty.holdsView, iha hsx]
      | snd => simp [Ty.holdsView, ihb hsx]
  | inl _ ih =>
    rcases hs.cases' with h | ⟨x, hc, hsx⟩
    · cases h
    · cases hc with
      | inl => simp [Ty.holdsView, ih hsx]
  | inr _ ih =>
    rcases hs.cases' with h | ⟨x, hc, hsx⟩
    · cases h
    · cases hc with
      | inr => simp [Ty.holdsView, ih hsx]
  | pkg _ _ => rfl

/-- A value of a type that holds no closure holds no package. -/
theorem WFv.no_pkg {τ : Ty} {v : Val} (hw : WFv τ v) (hf : τ.hasFn = false) {fs : List Nat} {te : Ty}
    {ms : List Nat} {e : Val} {cs : List (Var × PMode × Ty)} (hs : Sub (.pkg fs te ms e cs) v) : False := by
  induction hw with
  | int => cases hs
  | view => cases hs
  | arc => cases hs
  | lk => cases hs
  | cell => cases hs
  | node hes ih =>
    rcases hs.cases' with h | ⟨x, hc, hsx⟩
    · cases h
    · cases hc with
      | elem hx => exact ih x hx (by simpa [Ty.hasFn] using hf) hsx
  | pair _ _ iha ihb =>
    simp only [Ty.hasFn, Bool.or_eq_false_iff] at hf
    rcases hs.cases' with h | ⟨x, hc, hsx⟩
    · cases h
    · cases hc with
      | fst => exact iha hf.1 hsx
      | snd => exact ihb hf.2 hsx
  | inl _ ih =>
    simp only [Ty.hasFn, Bool.or_eq_false_iff] at hf
    rcases hs.cases' with h | ⟨x, hc, hsx⟩
    · cases h
    · cases hc with
      | inl => exact ih hf.1 hsx
  | inr _ ih =>
    simp only [Ty.hasFn, Bool.or_eq_false_iff] at hf
    rcases hs.cases' with h | ⟨x, hc, hsx⟩
    · cases h
    · cases hc with
      | inr => exact ih hf.2 hsx
  | pkg _ _ => cases hf

/-- A view the rewritten tree stores is one the old tree stored, or one that
    the replacement stores and the hole did not (`Q`). -/
theorem NSE_viewIn' {n n' T T' : Val} (hr : Repl n n' T T') {Q : Ty → Val → Prop} :
    ∀ {τ s : Ty} {v : Val}, WFv τ T →
      (∀ τ0, WFv τ0 n → ∀ s v, ViewIn τ0 n' s v → ViewIn τ0 n s v ∨ Q s v) →
      ViewIn τ T' s v → ViewIn τ T s v ∨ Q s v := by
  induction hr with
  | here => intro τ s v hw h hin; exact h τ hw s v hin
  | @elem t c d pre post e e' _ ih =>
    intro τ s v hw h hin
    cases hw with
    | node hes =>
      cases hin with
      | child hx hin' =>
        rcases List.mem_append.mp hx with hx | hx
        · exact Or.inl (ViewIn.child (List.mem_append_left _ hx) hin')
        · rcases List.mem_cons.mp hx with rfl | hx
          · rcases ih (hes e (List.mem_append_right _ (List.mem_cons_self ..))) h hin' with h1 | h1
            · exact Or.inl (ViewIn.child (List.mem_append_right _ (List.mem_cons_self ..)) h1)
            · exact Or.inr h1
          · exact Or.inl (ViewIn.child (List.mem_append_right _ (List.mem_cons_of_mem _ hx)) hin')
  | fst _ ih =>
    intro τ s v hw h hin
    cases hw with
    | pair ha hb =>
      cases hin with
      | fst hin' => exact (ih ha h hin').imp ViewIn.fst id
      | snd hin' => exact Or.inl (ViewIn.snd hin')
  | snd _ ih =>
    intro τ s v hw h hin
    cases hw with
    | pair ha hb =>
      cases hin with
      | fst hin' => exact Or.inl (ViewIn.fst hin')
      | snd hin' => exact (ih hb h hin').imp ViewIn.snd id
  | inl _ ih =>
    intro τ s v hw h hin
    cases hw with
    | inl ha => cases hin with | inl hin' => exact (ih ha h hin').imp ViewIn.inl id
  | inr _ ih =>
    intro τ s v hw h hin
    cases hw with
    | inr ha => cases hin with | inr hin' => exact (ih ha h hin').imp ViewIn.inr id
  | pkg _ ih =>
    intro τ s v hw h hin
    cases hw with
    | pkg ha => cases hin with | pkg hin' => exact (ih ha h hin').imp ViewIn.pkg id

/-- A view lying in an owned tree is not valid through that tree's owner
    but through a share of it (`viewAt_not_self`, of a part). -/
theorem viewAt_not_self' {m : Mem} {x : Var} {T : Val} (hT : m.st x = some ⟨true, some T⟩)
    (hsf : SelfFree T) {s : Ty} {d o l : Nat} (hs : Sub (.view d o l) T) {k : Kind}
    (hks : k ≠ .share) (ha : ViewAt m ⟨x, k⟩ d o l s) : False := by
  obtain ⟨c, es, _, hla, _, _⟩ := ha
  obtain ⟨n0, hr, hk⟩ := hla.root hks
  have ht := rootNode_own hT hr
  exact hsf d o l hs s c es (hk.sub.trans ht.sub)

/-- A view valid through a bound root stays valid when only the owner `o`'s
    tree changes, staying owned, the blocks as they were: through a root
    other than `o` (`keep_notx`), or through a share of `o`; a view that
    lies in `o`'s old tree is valid through `o` only so (`SelfFree`). -/
theorem keepV {m1 m' : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1) (hanch : RootbAnch Γ1 F)
    {o : Var} (hoF : o ∉ F) {T : Val} (hT : m1.st o = some ⟨true, some T⟩)
    (hst : ∀ v, v ≠ o → m'.st v = m1.st v) {T' : Val} (hT' : m'.st o = some ⟨true, some T'⟩)
    (hblk : m'.blk = m1.blk) {dep : Dep} (hr : ∃ Er, Γ1 dep.root = some Er ∧ Er.mode.isRoot = true)
    {s : Ty} {d0 o0 l0 : Nat} (ha : ViewAt m1 dep d0 o0 l0 s)
    (hin : dep.root = o → dep.kind ≠ .share → Sub (.view d0 o0 l0) T) : ViewAt m' dep d0 o0 l0 s := by
  obtain ⟨r, k⟩ := dep
  by_cases hro : r = o
  · subst hro
    by_cases hks : k = .share
    · subst hks
      exact vkeep_share (BlkLe.of_eq hblk) (RootMem.own hT') d0 o0 l0 s ha
    · exact (viewAt_not_self' hT (hi.heap.self _ T hT) (hin rfl hks) hks ha).elim
  · exact (keep_notx hi hanch hoF hst hr hro (BlkLe.of_eq hblk)).1 d0 o0 l0 s ha

/-- What a value of a type that holds no closure is valid through: its
    memory dependencies alone. -/
theorem Pushed.mem {m1 : Mem} {Γ1 : Ctx} {t : Ty} {v : Val} {D : List Dep} (h : Pushed m1 Γ1 t v D)
    (hf : t.hasFn = false) : Pushed m1 Γ1 t v (memDeps D) :=
  ⟨h.wf, h.vs.memDeps, h.nd, h.al, h.dis, fun r hr => h.root r (by
      obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr; exact List.mem_map_of_mem (List.mem_filter.mp hd).1), h.sf,
    NamesIn.nil _ (h.wf.names_nil_fn hf), h.pk, fun d hd => h.nok d (List.mem_filter.mp hd).1, h.sh,
    h.np⟩

/-! ### The owner's change -/

/-- The owner's new slot, when the change lands in its tree by `.drop` and
    may store views: the tree is well-formed at its type, its views are the
    old tree's, valid through what the owner held, or the stored values',
    valid through `D` (`NSE_viewIn'`, `keepV`), what it captures by name and
    its packages are as before or fewer (the new node holds none: its
    elements hold no closure), and the owner, made by no `letd`, holds `D`
    too. -/
theorem NewSlot.editV {m1 m' : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F) {o : Var} {Eo : Entry} (ho : Γ1 o = some Eo) (hoF : o ∉ F)
    (hmo : Eo.mode = .own) (hdb : Eo.dbind = false) (hEv : Eo.ty.holdsView = true)
    {T T' : Val} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hT : m1.st o = some ⟨true, some T⟩) (hT' : m'.st o = some ⟨true, some T'⟩)
    (hst : ∀ v, v ≠ o → m'.st v = m1.st v) (hfn : t.hasFn = false)
    {D : List Dep} (hoD : o ∉ roots D) (hDn : ∀ d ∈ D, d.kind.isName = false)
    (hDr : ∀ r ∈ roots D, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true)
    (hr : Repl (.node t c d es) (.node t c d' es') T T') (hw' : WFv (.vec t) (.node t c d' es'))
    (hnew : ∀ s w, ViewIn (.vec t) (.node t c d' es') s w → ViewIn (.vec t) (.node t c d es) s w ∨
      ∃ d0 o0 l0, w = .view d0 o0 l0 ∧ ∃ dep ∈ D, ViewAt m1 dep d0 o0 l0 s)
    (hblk : m'.blk = m1.blk) (hsh' : SharesOK m' (.vec t) (.node t c d' es')) :
    NewSlot m' (A2.kill .drop true o Γ1) o Eo (some ((killE .drop true o Eo).hold D)) := by
  have hos : Eo.mode.ownSlot = true := by rw [hmo]; rfl
  obtain ⟨sl0, hsl0, hok0, hs0⟩ := hi.slot o Eo ho
  rw [hT] at hsl0; cases hsl0
  obtain ⟨_, hown0, _⟩ := hs0
  obtain ⟨howning, hwf0, hlv0⟩ := hown0 hos
  have hwT : WFv Eo.ty T := hwf0 T rfl
  have hnint : Eo.ty ≠ .int := fun h => by rw [h] at howning; cases howning
  have hvd : Eo.vdeps = Eo.held := by simp [Entry.vdeps, hos]
  have hoh : ownHeld true Eo.ty D = D := ownHeld_views true hEv D
  -- the rewritten tree: well-formed, and its views are the old tree's or the stored values'
  have hwT' : WFv Eo.ty T' := NSE_wf hr hwT (fun τ0 h0 => by cases h0; exact hw')
  have hvin : ∀ s w, ViewIn Eo.ty T' s w → ViewIn Eo.ty T s w ∨
      ∃ d0 o0 l0, w = .view d0 o0 l0 ∧ ∃ dep ∈ D, ViewAt m1 dep d0 o0 l0 s := fun s w hin =>
    NSE_viewIn' hr hwT (fun τ0 h0 s w hin => by cases h0; exact hnew s w hin) hin
  have hn' : (Val.node t c d' es').names = [] := hw'.names_nil_fn (by simpa [Ty.hasFn] using hfn)
  have hlive : (killE .drop true o Eo).live = true → Eo.live = true := fun h => by
    rw [killE_live] at h; simp only [Bool.and_eq_true] at h; exact h.1
  -- the views of the live owner stay valid (`keepV`)
  have hviews : Eo.live = true → ViewsOK m' Eo.ty T' (Eo.held ++ D) := by
    intro hl
    obtain ⟨T1, hT1, hv1⟩ := hlv0 hl
    cases hT1
    intro s w hin
    rcases hvin s w hin with hin0 | ⟨d0, o0, l0, rfl, dep, hd, ha⟩
    · obtain ⟨d0, o0, l0, rfl, dep, hd, ha⟩ := hv1 s w hin0
      exact ⟨d0, o0, l0, rfl, dep, List.mem_append_left _ hd,
        keepV hi hanch hoF hT hst hT' hblk (wf_held hi ho hl hnint dep.root (List.mem_map_of_mem hd)) ha
          (fun _ _ => hin0.sub)⟩
    · refine ⟨d0, o0, l0, rfl, dep, List.mem_append_right _ hd,
        keepV hi hanch hoF hT hst hT' hblk (hDr dep.root (List.mem_map_of_mem hd)) ha (fun h => ?_)⟩
      exact absurd (by rw [← h]; exact List.mem_map_of_mem hd) hoD
  have hdb' : ((killE .drop true o Eo).hold D).dbind = false := by rw [Entry.hold_dbind, killE_dbind, hdb]
  have hm' : ((killE .drop true o Eo).hold D).mode = .own := by rw [Entry.hold_mode, killE_mode, hmo]
  have ht' : ((killE .drop true o Eo).hold D).ty = Eo.ty := by rw [Entry.hold_ty, killE_ty]
  refine ⟨⟨true, some T'⟩, hT', by rw [ht']; exact hok0,
    ⟨by rw [hm']; rfl, fun _ => ⟨by rw [ht']; exact howning, fun U hU => ?_, fun hl' => ⟨T', rfl, ?_⟩⟩,
      fun h => by rw [hm'] at h; cases h⟩,
    by rw [Entry.hold_mode, killE_mode], fun hl' _ r hr' => ?_, ht', fun hl' _ => ?_, fun hl' U hU => ?_,
    fun U hU => ?_, fun h => absurd (h.symm.trans hdb') (by decide), fun h => ?_,
    fun h => absurd (h.symm.trans hdb') (by decide), fun h => absurd (h.symm.trans hdb') (by decide), ?_⟩
  · cases hU; rw [ht']; exact hwT'
  · -- the views of the live owner
    rw [Entry.hold_live] at hl'
    rw [ht', Entry.hold_held, killE_held, killE_ty, hoh]
    exact hviews (hlive hl')
  · -- its roots are bound
    simp only [Entry.hold_live] at hl'
    rw [Entry.hold_vdeps, killE_vdeps, killE_ty, hoh] at hr'
    simp only [roots, List.map_append, List.mem_append] at hr'
    obtain ⟨Er, hEr, hro⟩ : ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true := by
      rcases hr' with hr' | hr'
      · exact hi.wf o Eo ho (hlive hl') (Or.inl hnint) r hr'
      · exact hDr r hr'
    by_cases hrx : r = o
    · exact Or.inl ⟨hrx, by simp only [Entry.hold_mode, killE_mode, hmo]; rfl⟩
    · exact Or.inr ⟨hrx, kill_root hEr hro⟩
  · -- what it holds by name: what it held, not itself, which would then hold nothing
    simp only [Entry.hold_live] at hl'
    have hl := hlive hl'
    have hN := hi.names o Eo ho hl (Or.inl hnint)
    intro dd hdd b t0 hk
    rw [Entry.hold_vdeps, killE_vdeps] at hdd
    rcases List.mem_append.mp hdd with hdd | hdd
    · obtain ⟨Er, hEr, hlr, hhr, htr, hor, hcr⟩ := hN dd hdd b t0 hk
      by_cases hro : dd.root = o
      · rw [hro, ho] at hEr; cases hEr
        rw [hvd, hhr] at hdd; cases hdd
      · exact ⟨Er, by rw [upd_ne _ _ hro]; simp [A2.kill, hEr, killE_nil (root_vdeps hor hhr)],
          hlr, hhr, htr, hor, hcr⟩
    · have := hDn dd (ownHeld_sub _ _ _ hdd); rw [hk] at this; cases this
  · -- what the new tree captures by name, the old one did (`Repl.names_split`)
    cases hU
    simp only [Entry.hold_live] at hl'
    have hN0 := hi.held o Eo ⟨true, some T⟩ T ho (hlive hl') hT rfl
    obtain ⟨A, B, h1, h2⟩ := hr.names_split
    simp only [Entry.hold_held, killE_held]
    intro cc hcc
    rw [h2, hn'] at hcc
    apply List.mem_append_left
    apply hN0 cc
    rw [h1]
    simp only [List.append_nil, List.mem_append] at hcc ⊢
    rcases hcc with h | h
    · exact Or.inl (Or.inl h)
    · exact Or.inr h
  · -- its packages: the old tree's, or an ancestor of the hole, capturing fewer names
    cases hU
    have hpk := hi.pkgs o ⟨true, some T⟩ T hT rfl
    intro fs te ms e cs hs
    rcases NSE_sub hr hs with h | h | ⟨P0, h0, h1⟩
    · exact (hw'.no_pkg (by simpa [Ty.hasFn] using hfn) h).elim
    · exact hpk fs te ms e cs h
    · cases h1 with
      | pkg hr1 =>
        rename_i a
        obtain ⟨hnd, hmd, hcap⟩ := hpk fs te ms a cs h0
        refine ⟨hnd, hmd, fun cc hcc c' hc' heq => hcap cc hcc c' ?_ heq⟩
        obtain ⟨A, B, h1, h2⟩ := hr1.names_split
        rw [h2, hn'] at hc'
        rw [h1]
        simp only [List.append_nil, List.mem_append] at hc' ⊢
        rcases hc' with h | h
        · exact Or.inl (Or.inl h)
        · exact Or.inr h
  · -- only a binding `letd` made may run a destructor
    rw [Entry.hold_dtor, killE_dtor] at h; rw [Entry.hold_dbind, killE_dbind]; exact hi.wf.arm o Eo ho h
  · -- A3.1: its shares are the old tree's or the new node's, and the blocks are as they were
    intro _ U hU
    cases hU
    rw [ht']
    exact SharesOK.repl hsh' hr hwT ((hi.shares o Eo ⟨true, some T⟩ T ho hT rfl rfl).of_blk hblk)

/-- The owner's change by `.drop`, storing views: one node of its tree
    rewritten in place (`MInv.change`, with `NewSlot.editV`); its elements
    hold views, so the `.drop` ends the borrows of its handle too, and spares
    only what holds it by name. -/
theorem MInv.edit_dropV {m1 m' : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F) {o : Var} {Eo : Entry} (ho : Γ1 o = some Eo) (hoF : o ∉ F)
    (hcan : canDo Eo.mode .drop) (hds : DtorSafe Γ1 .drop true o) (hdb : Eo.dbind = false)
    (hEv : Eo.ty.holdsView = true) {T T' : Val} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hT : m1.st o = some ⟨true, some T⟩) (hT' : m'.st o = some ⟨true, some T'⟩)
    (hst : ∀ v, v ≠ o → m'.st v = m1.st v) (hheap : HeapOK m') (hnv : m'.nv = m1.nv)
    (hfn : t.hasFn = false) {D : List Dep} (hoD : o ∉ roots D) (hDn : ∀ d ∈ D, d.kind.isName = false)
    (hDr : ∀ r ∈ roots D, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true)
    (hr : Repl (.node t c d es) (.node t c d' es') T T') (hw' : WFv (.vec t) (.node t c d' es'))
    (hnew : ∀ s w, ViewIn (.vec t) (.node t c d' es') s w → ViewIn (.vec t) (.node t c d es) s w ∨
      ∃ d0 o0 l0, w = .view d0 o0 l0 ∧ ∃ dep ∈ D, ViewAt m1 dep d0 o0 l0 s)
    (hblk : m'.blk = m1.blk) (hsh' : SharesOK m' (.vec t) (.node t c d' es')) :
    MInv m' (A2.holdOn [o] D (A2.kill .drop true o Γ1)) := by
  have hmo : Eo.mode = .own := by
    rcases hcan with h | ⟨b, h, _⟩
    · exact h
    · exact absurd h (hi.noInout o Eo b ho)
  have hkeep : ∀ k, Eff.kills .drop true k = false → VKeep m1 m' ⟨o, k⟩ ∧ HKeep m1 m' ⟨o, k⟩ := by
    intro k hk
    cases k with
    | name b t => exact ⟨vkeep_name _ _ _ _ _, hkeep_name _ _ _ _ _⟩
    | _ => simp [Eff.kills] at hk
  have h := hi.change hanch ho hoF (hmn_of_ne_replace true (by decide) o) (by rw [hmo]; simp) hst hheap
    hnv hkeep (NewSlot.editV hi hanch ho hoF hmo hdb hEv hT hT' hst hfn hoD hDn hDr hr hw' hnew hblk hsh')
    hds (fun h => by cases h) (fun h => by cases h)
    (fun _ _ _ _ _ hhv => absurd hEv (by rw [hhv]; decide)) hblk
  have heq : upd (A2.kill .drop true o Γ1) o (some ((killE .drop true o Eo).hold D)) =
      A2.holdOn [o] D (A2.kill .drop true o Γ1) := by
    funext v
    by_cases hv : v = o
    · subst hv; simp [upd, A2.holdOn, A2.kill, ho]
    · rw [upd_ne _ _ hv]
      cases hE : A2.kill .drop true o Γ1 v with
      | none => rw [holdOn_none hE]
      | some E => rw [holdOn_some hE, ite_eq_right (by simpa using hv)]
  rw [heq] at h; exact h

/-- The owner's change by `.realloc`, storing views: a push through a copy
    of the handle of a root of the borrow's own type is the root's own push
    (`push_grow`), and the root holds what was pushed. -/
theorem MInv.edit_growV {m1 : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F) {o : Var} {Eo : Entry} (ho : Γ1 o = some Eo) (hl : Eo.live = true)
    (hoF : o ∉ F) (hcan : canDo Eo.mode .realloc) {t : Ty} (hty : Eo.ty = .vec t)
    (hhv : t.holdsView = true) (hds : DtorSafe Γ1 .realloc true o) (hdb : Eo.dbind = false)
    {t' : Ty} {c d : Nat} {es : List Val} (hT : m1.st o = some ⟨true, some (.node t' c d es)⟩)
    {v : Val} {D : List Dep} (hp : Pushed m1 Γ1 t v D) (hoD : o ∉ roots D) {d' : Nat} {A' : Nat → Bool}
    {N' : Nat} (hre : (d' = d ∧ A' = m1.alloc ∧ N' = m1.nid) ∨
      (d' = m1.nid ∧ A' = upd (upd m1.alloc d false) m1.nid true ∧ N' = m1.nid + 1)) :
    MInv ({ m1 with alloc := A', nid := N' }.set o ⟨true, some (.node t' c d' (es ++ [v]))⟩)
      (A2.holdOn [o] D (A2.kill .realloc true o Γ1)) := by
  have hmo : Eo.mode = .own := by
    rcases hcan with h | ⟨b, h, _⟩
    · exact h
    · exact absurd h (hi.noInout o Eo b ho)
  have h := push_grow hi hanch ho hl hcan hoF hty hT hp hoD (fun h => by rw [hhv] at h; cases h) hre
    (by rw [hhv]; exact hds) (fun h => by rw [hdb] at h; cases h)
  rw [hhv] at h
  have hanch2 : RootbAnch (A2.setE (A2.kill .realloc true o Γ1) o { Eo with held := Eo.held ++ D }) F :=
    fun p Ep hp hm => by
      by_cases hpo : p = o
      · subst hpo; simp only [A2.setE, upd_same, Option.some.injEq] at hp; subst hp
        rw [hmo] at hm; cases hm
      · simp only [A2.setE, upd_ne _ _ hpo] at hp; exact hanch.kill _ _ _ p Ep hp hm
  have h2 := h.kill_more hanch2 hoF (by decide : Eff.realloc ≠ .replace) true
  have hEv : Eo.ty.holdsView = true := by rw [hty]; exact hhv
  have hhold : ({ Eo with held := Eo.held ++ D } : Entry) = Eo.hold D := by
    simp [Entry.hold, ownHeld_views true hEv D]
  have heq : A2.kill .realloc true o (A2.setE (A2.kill .realloc true o Γ1) o { Eo with held := Eo.held ++ D }) =
      A2.holdOn [o] D (A2.kill .realloc true o Γ1) := by
    funext w
    by_cases hw : w = o
    · subst hw; simp [A2.setE, A2.kill, A2.holdOn, ho, hhold, killE_hold hoD]
    · rw [A2.kill, A2.setE, upd_ne _ _ hw]
      cases hE : Γ1 w with
      | none => simp [A2.kill, A2.holdOn, hE]
      | some E => simp [A2.kill, A2.holdOn, hE, hw, killE_idem]
  rw [heq] at h2; exact h2

/-! ### The other roots, and the borrow -/

/-- Holding more memory, at owners not made by `letd`, keeps the invariant:
    what each one's tree views stays valid through what it held, and more;
    nothing it holds is by name. -/
theorem MInv.holdOn {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {rs : List Var} {D : List Dep}
    (hrs : ∀ v ∈ rs, ∀ E, Γ v = some E → E.mode.ownSlot = true ∧ E.dbind = false)
    (hnm : ∀ d ∈ D, d.kind.isName = false)
    (hroot : ∀ r ∈ roots D, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) :
    MInv m (A2.holdOn rs D Γ) where
  dom v := by rw [holdOn_isSome]; exact hi.dom v
  slot v E' h := by
    obtain ⟨E, hE, rfl⟩ := holdOn_get h
    obtain ⟨sl, hsl, hok, hs⟩ := hi.slot v E hE
    by_cases hvr : v ∈ rs
    · rw [ite_eq_left hvr]
      obtain ⟨hos, _⟩ := hrs v hvr E hE
      obtain ⟨h1, h2, _⟩ := hs
      obtain ⟨how, hwf, hlv⟩ := h2 hos
      refine ⟨sl, hsl, hok, h1, fun _ => ⟨how, hwf, fun hl => ?_⟩,
        fun h => by rw [Entry.hold_mode, hos] at h; cases h⟩
      obtain ⟨T, hT, hv⟩ := hlv hl
      exact ⟨T, hT, hv.mono (List.subset_append_left _ _)⟩
    · rw [ite_eq_right hvr]; exact ⟨sl, hsl, hok, hs⟩
  heap := hi.heap
  nvSt := hi.nvSt
  noInout v E' b h := by
    obtain ⟨E, hE, rfl⟩ := holdOn_get h
    split <;> exact hi.noInout v E b hE
  wf := hi.wf.holdOn hroot
  rootbLive p E' h hm := by
    obtain ⟨E, hE, rfl⟩ := holdOn_get h
    by_cases hpr : p ∈ rs
    · rw [ite_eq_left hpr, Entry.hold_mode] at hm
      have := (hrs p hpr E hE).1; rw [hm] at this; cases this
    · rw [ite_eq_right hpr] at hm ⊢; exact hi.rootbLive p E hE hm
  rootbLt p E' h hm := by
    obtain ⟨E, hE, rfl⟩ := holdOn_get h
    by_cases hpr : p ∈ rs
    · rw [ite_eq_left hpr, Entry.hold_mode] at hm
      have := (hrs p hpr E hE).1; rw [hm] at this; cases this
    · rw [ite_eq_right hpr] at hm ⊢; exact hi.rootbLt p E hE hm
  names := hi.names.holdOn hnm
  held v E' sl T h hl hsl hT := by
    obtain ⟨E, hE, rfl⟩ := holdOn_get h
    by_cases hvr : v ∈ rs
    · rw [ite_eq_left hvr] at hl ⊢
      exact (hi.held v E sl T hE hl hsl hT).mono (List.subset_append_left _ _)
    · rw [ite_eq_right hvr] at hl ⊢; exact hi.held v E sl T hE hl hsl hT
  pkgs := hi.pkgs
  armed v E' sl h hsl := by
    obtain ⟨E, hE, rfl⟩ := holdOn_get h
    by_cases hvr : v ∈ rs
    · rw [ite_eq_left hvr]; intro hd; rw [Entry.hold_dbind, (hrs v hvr E hE).2] at hd; cases hd
    · rw [ite_eq_right hvr]; exact hi.armed v E sl hE hsl
  shares v E' sl T h hsl hown hT := by
    obtain ⟨E, hE, rfl⟩ := holdOn_get h
    have := hi.shares v E sl T hE hsl hown hT
    split <;> exact this
  blocks := hi.blocks

/-- The rest of a change through a borrow that may store a view, once its
    owner's tree is changed and the owner holds what was stored (`hown`):
    every memory root of `x`'s path ends what its effect ends
    (`MInv.killHv_more`; the owner's own kill is absorbed), the others hold
    `D` too (`MInv.holdOn`), and `x` is live again, holding `D` too, valid
    through the dependency that reached the changed node. -/
theorem MInv.editBV_rest {m' : Mem} {Γ1 : Ctx} {F : List Var} (hw : CtxWF Γ1) (hn : NameWF Γ1)
    (hanch : RootbAnch Γ1 F) {x : Var} {op : Edit} {Ex : Entry} {t : Ty}
    (hx : Γ1 x = some Ex) (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t)
    (hthru : ThruOK Γ1 F op Ex.ty Ex.path) {D : List Dep} (hV : ThruV Γ1 op Ex.ty Ex.path D)
    (hDn : ∀ d ∈ D, d.kind.isName = false)
    (hDr : ∀ r ∈ roots D, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true)
    {dep : Dep} (hdep : dep ∈ memDeps Ex.path)
    (hown : MInv m' (A2.holdOn [dep.root] D (A2.kill (op.effAt dep.kind (decide ((argE Γ1 dep.root).ty = Ex.ty)))
      (argE Γ1 dep.root).ty.holdsView dep.root Γ1)))
    {c : Nat} (hxs : m'.st x = some ⟨false, some (.href c)⟩) (hhref : HrefAt m' dep c t (Ex.held ++ D)) :
    MInv m' (A2.setE (holdThru D Ex.path (killThruV op Ex.ty Ex.path Γ1)) x
      { Ex with held := Ex.held ++ D }) := by
  have hk0 : (op.effAt dep.kind (decide ((argE Γ1 dep.root).ty = Ex.ty)), (argE Γ1 dep.root).ty.holdsView,
      dep.root) ∈ thruKills op Γ1 Ex.ty Ex.path := mem_thruKills.mpr ⟨dep, hdep, rfl⟩
  have hdr : dep.root ∈ roots (memDeps Ex.path) := List.mem_map_of_mem hdep
  -- the roots own their slots, were made by no `letd`, and are none of `D`'s
  have hroot : ∀ r ∈ roots (memDeps Ex.path), ∃ Er, Γ1 r = some Er ∧ Er.mode.ownSlot = true ∧
      Er.dbind = false ∧ r ∉ roots D := by
    intro r hr
    obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
    obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d hd
    obtain ⟨_, hdb, hrD⟩ := hV d hd
    have hae : argE Γ1 d.root = Er := by unfold argE; rw [hEr]; rfl
    exact ⟨Er, hEr, hcan.ownSlot, by rw [← hae]; exact hdb, hrD⟩
  have hLD : ∀ k ∈ thruKills op Γ1 Ex.ty Ex.path, k.2.2 ∉ roots D := by
    intro k hk
    obtain ⟨d, hd, rfl⟩ := mem_thruKills.mp hk
    exact (hV d hd).2.2
  -- what is bound and a root stays so
  have hbound : ∀ Γ' : Ctx, (∀ v, (∃ E, Γ1 v = some E ∧ E.mode.isRoot = true) →
      ∃ E', Γ' v = some E' ∧ E'.mode.isRoot = true) → True := fun _ _ => trivial
  clear hbound
  have hbK : ∀ r, (∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true) →
      ∃ Er, A2.killHv (thruKills op Γ1 Ex.ty Ex.path) Γ1 r = some Er ∧ Er.mode.isRoot = true := by
    rintro r ⟨Er, hEr, hro⟩
    obtain ⟨E', hE', hc⟩ := killHv_entry (thruKills op Γ1 Ex.ty Ex.path) hEr
    exact ⟨E', hE', by rcases hc with rfl | rfl <;> exact hro⟩
  have hbH : ∀ (rs : List Var) (Γ' : Ctx) (r : Var), (∃ Er, Γ' r = some Er ∧ Er.mode.isRoot = true) →
      ∃ Er, A2.holdOn rs D Γ' r = some Er ∧ Er.mode.isRoot = true := by
    rintro rs Γ' r ⟨Er, hEr, hro⟩
    exact ⟨_, holdOn_some hEr, by split <;> exact hro⟩
  have hanch1 : RootbAnch (A2.holdOn [dep.root] D (A2.kill (op.effAt dep.kind
      (decide ((argE Γ1 dep.root).ty = Ex.ty))) (argE Γ1 dep.root).ty.holdsView dep.root Γ1)) F :=
    (hanch.kill _ _ _).holdOn (fun v hv E hE => by
      simp only [List.mem_singleton] at hv; subst hv
      obtain ⟨E0, h0, hm0, _⟩ := kill_cmode hE
      obtain ⟨Er, hEr, hos, _⟩ := hroot dep.root hdr
      rw [hEr] at h0; cases h0; rw [hm0]; intro h; rw [h] at hos; cases hos)
  have h1 := hown.killHv_more hanch1 _ (thruKills_ok hthru)
  rw [killHv_holdOn _ _ _ hLD, killHv_absorb hk0] at h1
  -- the other roots hold `D` too
  have hrs : ∀ v ∈ (roots (memDeps Ex.path)).filter (· != dep.root), ∀ E,
      A2.holdOn [dep.root] D (A2.killHv (thruKills op Γ1 Ex.ty Ex.path) Γ1) v = some E →
        E.mode.ownSlot = true ∧ E.dbind = false := by
    intro v hv E hE
    have hv' := List.mem_filter.mp hv
    have hvo : v ≠ dep.root := by simpa using hv'.2
    obtain ⟨E1, hE1, rfl⟩ := holdOn_get hE
    rw [ite_eq_right (by simpa using hvo)]
    obtain ⟨E0, h0, hm0, _, _, _, _, hb0, _⟩ := killHv_same hE1
    obtain ⟨Er, hEr, hos, hdb, _⟩ := hroot v hv'.1
    rw [hEr] at h0; cases h0
    exact ⟨by rw [hm0]; exact hos, by rw [hb0]; exact hdb⟩
  have h2 := h1.holdOn hrs hDn (fun r hr => hbH _ _ r (hbK r (hDr r hr)))
  rw [holdOn_merge hdr] at h2
  -- `x`, live again, holding `D` too
  have hxr : x ∉ roots (memDeps Ex.path) := fun h => by
    obtain ⟨Er, hEr, hos, _⟩ := hroot x h; rw [hx] at hEr; cases hEr; rw [hmx] at hos; cases hos
  obtain ⟨E', hE', hE'c⟩ := killHv_entry (thruKills op Γ1 Ex.ty Ex.path) hx
  have hxE : A2.holdThru D Ex.path (A2.killThruV op Ex.ty Ex.path Γ1) x = some E' := by
    show A2.holdOn _ D (A2.killHv _ Γ1) x = some E'
    rw [holdOn_some hE', ite_eq_right hxr]
  have hnint : Ex.ty ≠ .int := by rw [hty]; simp
  have hos : Ex.mode.ownSlot = false := by rw [hmx]; rfl
  refine MInv.reset (Ex := { Ex with held := Ex.held ++ D }) (show MInv m' (A2.holdThru D Ex.path
      (A2.killThruV op Ex.ty Ex.path Γ1)) from h2) hxE
    (by rcases hE'c with rfl | rfl <;> rfl) (by rcases hE'c with rfl | rfl <;> rfl)
    (by rcases hE'c with rfl | rfl <;> rfl) (by rcases hE'c with rfl | rfl <;> rfl) hmx hxs
    (by show ValOK m' Ex.ty (.href c) Ex.path (Ex.held ++ D); rw [hty]
        exact .href ⟨dep, (List.mem_filter.mp hdep).1, hhref⟩) (fun _ r hr => ?_) (fun _ _ => ?_)
    (fun c' hc' => by simp [Val.names] at hc')
  · -- its roots are bound: what it depended on, and what was stored
    have hr' : r ∈ roots Ex.vdeps ∨ r ∈ roots D := by
      simp only [Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, roots, List.map_append,
        List.mem_append] at hr ⊢
      rcases hr with hr | hr | hr
      · exact Or.inl (Or.inl hr)
      · exact Or.inl (Or.inr hr)
      · exact Or.inr hr
    rcases hr' with hr' | hr'
    · exact hbH _ _ r (hbK r (hw x Ex hx hl (Or.inl hnint) r hr'))
    · exact hbH _ _ r (hbK r (hDr r hr'))
  · -- what it holds by name, it held: bindings that hold nothing, untouched
    intro d hd b t' hk
    have hd' : d ∈ Ex.vdeps := by
      simp only [Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.mem_append] at hd ⊢
      rcases hd with hd | hd | hd
      · exact Or.inl hd
      · exact Or.inr hd
      · have := hDn d hd; rw [hk] at this; cases this
    obtain ⟨Er, hEr, hlr, hh, ht, ho, hc, hvw⟩ := hn x Ex hx hl (Or.inl hnint) d hd' b t' hk
    refine ⟨Er, ?_, hlr, hh, ht, ho, hc, hvw⟩
    show A2.holdOn _ D (A2.killHv _ Γ1) d.root = some Er
    rw [holdOn_some (killHv_nil' hEr (root_vdeps ho hh) _), Er.hold_noView (by rw [ht]; exact hvw)]
    simp

/-! ### The steps -/

/-- What is left once the owner's tree is changed (`hown`): `x`'s node, at
    its cell, holds the old node's views, valid through what `x` held, and
    the stored values', valid through `D` (`keepV`). -/
theorem MInv.editBV_fin {m1 m' : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F) {x : Var} {op : Edit} {Ex : Entry} {t : Ty} (hx : Γ1 x = some Ex)
    (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t) (hfn : t.hasFn = false)
    (hthru : ThruOK Γ1 F op Ex.ty Ex.path) {D : List Dep} (hV : ThruV Γ1 op Ex.ty Ex.path D)
    (hDn : ∀ d ∈ D, d.kind.isName = false)
    (hDr : ∀ r ∈ roots D, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true)
    {dep : Dep} (hdep : dep ∈ memDeps Ex.path) {T n0 : Val} {c d : Nat} {es : List Val}
    (hxs : m1.st x = some ⟨false, some (.href c)⟩) (hT0 : m1.st dep.root = some ⟨true, some T⟩)
    (htop : Top n0 T) (hla : Lands dep.kind (.node t c d es) n0) (hhref0 : HrefAt m1 dep c t Ex.held)
    (hsub : Sub (.node t c d es) T)
    (hst : ∀ w, w ≠ dep.root → m'.st w = m1.st w) {T' : Val} (hT' : m'.st dep.root = some ⟨true, some T'⟩)
    (hblk : m'.blk = m1.blk) {d' : Nat} {es' : List Val}
    (hr : Repl (.node t c d es) (.node t c d' es') T T') (hw' : WFv (.vec t) (.node t c d' es'))
    (hsh' : SharesOK m' (.vec t) (.node t c d' es'))
    (hnew : ∀ s w, ViewIn (.vec t) (.node t c d' es') s w → ViewIn (.vec t) (.node t c d es) s w ∨
      ∃ d0 o0 l0, w = .view d0 o0 l0 ∧ ∃ dep ∈ D, ViewAt m1 dep d0 o0 l0 s)
    (hown : MInv m' (A2.holdOn [dep.root] D (A2.kill (op.effAt dep.kind (decide ((argE Γ1 dep.root).ty = Ex.ty)))
      (argE Γ1 dep.root).ty.holdsView dep.root Γ1))) :
    MInv m' (A2.setE (holdThru D Ex.path (killThruV op Ex.ty Ex.path Γ1)) x
      { Ex with held := Ex.held ++ D }) := by
  have hoF := (hthru dep hdep).1
  have hoD := (hV dep hdep).2.2
  have hxo : x ≠ dep.root := fun e => by rw [e, hT0] at hxs; cases hxs
  have hnint : Ex.ty ≠ .int := by rw [hty]; simp
  -- the node `x` was valid through is the one found
  obtain ⟨d1, es1, hla1, _, hvs0, _, _⟩ := hhref0
  have hsame : (Val.node t c d1 es1) = .node t c d es := by
    obtain ⟨n1, hrn, hk⟩ := hla1.root (hthru.noShare dep hdep)
    exact (owned_unique hi.heap hT0 hT0 (hk.sub.trans (rootNode_own hT0 hrn).sub) hsub (i := c)
      (by simp [Val.head]) (by simp [Val.head])).2
  cases hsame
  have hV' : ViewsOK m' (.vec t) (.node t c d' es') (Ex.held ++ D) := by
    intro s w hin
    rcases hnew s w hin with hin0 | ⟨d0, o0, l0, rfl, dp, hdp, ha⟩
    · obtain ⟨d0, o0, l0, rfl, dp, hdp, ha⟩ := hvs0 s w hin0
      exact ⟨d0, o0, l0, rfl, dp, List.mem_append_left _ hdp,
        keepV hi hanch hoF hT0 hst hT' hblk (wf_held hi hx hl hnint dp.root (List.mem_map_of_mem hdp)) ha
          (fun _ _ => hin0.sub.trans hsub)⟩
    · refine ⟨d0, o0, l0, rfl, dp, List.mem_append_right _ hdp,
        keepV hi hanch hoF hT0 hst hT' hblk (hDr dp.root (List.mem_map_of_mem hdp)) ha (fun h => ?_)⟩
      exact absurd (by rw [← h]; exact List.mem_map_of_mem hdp) hoD
  have hN' : NamesIn (.node t c d' es') (Ex.held ++ D) :=
    NamesIn.nil _ (hw'.names_nil_fn (by simpa [Ty.hasFn] using hfn))
  exact MInv.editBV_rest hi.wf hi.names hanch hx hmx hl hty hthru hV hDn hDr hdep hown
    (by rw [hst x hxo]; exact hxs)
    (editB_hrefAt' hT' (hi.heap.nodup _ _ hT0) htop hla hr hw' hV' hN' hsh')

/-- A view the pushed value stores is valid through `D`, none of whose roots
    is the owner `o`: so it points into no node of `o`'s tree, and into
    memory below `nid`. -/
theorem Pushed.views_out {m1 : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1) (hanch : RootbAnch Γ1 F)
    {t : Ty} {v : Val} {D : List Dep} (hp : Pushed m1 Γ1 t v D) {o : Var} (hoF : o ∉ F)
    (hoD : o ∉ roots D) {T : Val} (hT : m1.st o = some ⟨true, some T⟩) :
    ∀ d0 o0 l0, Sub (.view d0 o0 l0) v → (∀ u c es, ¬ Sub (.node u c d0 es) T) ∧ d0 < m1.nid := by
  intro d0 o0 l0 hs
  obtain ⟨s, hin⟩ := hp.wf.sub_view hs
  obtain ⟨d1, o1, l1, hv1, dep, hd, ha⟩ := hp.vs s _ hin
  cases hv1
  refine ⟨viewAt_not_in hi hanch hoF hT (hp.root dep.root (List.mem_map_of_mem hd))
    (fun e => hoD (by rw [← e]; exact List.mem_map_of_mem hd)) ha, ?_⟩
  rcases ha.owned hi.heap with ⟨ox, U, hU, hdU⟩ | hpa
  · exact (hi.heap.alloc ox U hU _ hdU).2
  · exact (hi.heap.payAlloc hpa).2

/-- What a tree owned in `m` views lies in memory an owner or a block holds. -/
theorem MInv.views_owned {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {o : Var} {Eo : Entry} (ho : Γ o = some Eo)
    (hl : Eo.live = true) (hos : Eo.mode.ownSlot = true) {T : Val} (hT : m.st o = some ⟨true, some T⟩) :
    ∀ d0 o0 l0, Sub (.view d0 o0 l0) T → (∃ o' U, OwnedAt m o' U ∧ d0 ∈ U.ids) ∨ PayAddr m d0 := by
  intro d0 o0 l0 hs
  obtain ⟨T1, h1, hwT, hvsT⟩ := hi.own_val ho hl hos
  rw [hT] at h1; cases h1
  obtain ⟨s, hin⟩ := hwT.sub_view hs
  obtain ⟨_, _, _, hv1, _, _, ha⟩ := hvsT s _ hin
  cases hv1
  exact ha.owned hi.heap

/-- A push through a borrow, of a value that may hold views, its buffer
    kept or moved to a fresh one: through a copy of a same-typed root's
    handle it is that root's own push (`MInv.edit_growV`), otherwise one
    node of the root's tree rewritten (`MInv.edit_dropV`). -/
theorem MInv.editBV_push {m1 : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F) {x y : Var} {Ex : Entry} {t : Ty} (hx : Γ1 x = some Ex)
    (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t) (hhv : t.holdsView = true)
    (hfn : t.hasFn = false) (hthru : ThruOK Γ1 F (.push y) Ex.ty Ex.path)
    {D : List Dep} (hV : ThruV Γ1 (.push y) Ex.ty Ex.path D) (hDn : ∀ d ∈ D, d.kind.isName = false)
    {v : Val} (hp : Pushed m1 Γ1 t v D)
    {o : Var} {T T' : Val} {t' : Ty} {c d : Nat} {es : List Val} (hno : NodeOf m1 x o T t' c d es)
    {d' : Nat} {A' : Nat → Bool} {N' : Nat}
    (hre : (d' = d ∧ A' = m1.alloc ∧ N' = m1.nid) ∨
      (d' = m1.nid ∧ A' = upd (upd m1.alloc d false) m1.nid true ∧ N' = m1.nid + 1))
    (hr : Repl (.node t' c d es) (.node t' c d' (es ++ [v])) T T') :
    MInv ({ m1 with alloc := A', nid := N' }.set o ⟨true, some T'⟩)
      (A2.setE (holdThru D Ex.path (killThruV (.push y) Ex.ty Ex.path Γ1)) x
        { Ex with held := Ex.held ++ D }) := by
  have hro : ∀ d ∈ memDeps Ex.path, ∃ Er, Γ1 d.root = some Er ∧ Er.mode.ownSlot = true :=
    fun d hd => by
      obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d hd
      exact ⟨Er, hEr, hcan.ownSlot⟩
  obtain ⟨dep, hdm, T0, n0, c0, d0, es0, hxs, hT0, htop, hla, hhref0, hw0, _, huniq, hsh0⟩ :=
    hi.thru_owner hx hmx hl hty hro hthru.noShare
  obtain ⟨rfl, rfl, ht', rfl, rfl, rfl⟩ := huniq _ _ _ _ _ _ hno
  subst t'
  obtain ⟨hoF, _, Eo, hEo, hlo, hcan, _, _⟩ := hthru dep hdm
  obtain ⟨hdsV, hdbV, hoD⟩ := hV dep hdm
  have hargE : argE Γ1 dep.root = Eo := by unfold argE; rw [hEo]; rfl
  rw [hargE] at hdsV hdbV
  obtain ⟨T1, hT1, hwT, _⟩ := hi.own_val hEo hlo hcan.ownSlot
  rw [hT0] at hT1; cases hT1
  have hEv : Eo.ty.holdsView = true := hwT.node_holdsView hno.sub hhv
  rw [hEv] at hdsV
  let m' := { m1 with alloc := A', nid := N' }.set dep.root ⟨true, some T'⟩
  have hst : ∀ w, w ≠ dep.root → m'.st w = m1.st w := fun w hw => by simp [m', upd_ne _ _ hw]
  have hT' : m'.st dep.root = some ⟨true, some T'⟩ := by simp [m']
  have hw' : WFv (.vec t) (.node t c d' (es ++ [v])) := by
    cases hw0 with
    | node hes =>
      refine WFv.node fun e he => ?_
      rcases List.mem_append.mp he with h | h
      · exact hes e h
      · simp only [List.mem_singleton] at h; subst h; exact hp.wf
  have hsh' : SharesOK m' (.vec t) (.node t c d' (es ++ [v])) := hsh0.node_push hp.sh rfl
  have hnew : ∀ s w, ViewIn (.vec t) (.node t c d' (es ++ [v])) s w → ViewIn (.vec t) (.node t c d es) s w ∨
      ∃ d0 o0 l0, w = .view d0 o0 l0 ∧ ∃ dep ∈ D, ViewAt m1 dep d0 o0 l0 s := by
    intro s w hin
    cases hin with
    | child he hin' =>
      rcases List.mem_append.mp he with h | h
      · exact Or.inl (ViewIn.child h hin')
      · simp only [List.mem_singleton] at h; subst h; exact Or.inr (hp.vs s w hin')
  have hown : MInv m' (A2.holdOn [dep.root] D (A2.kill ((Edit.push y).effAt dep.kind
      (decide ((argE Γ1 dep.root).ty = Ex.ty))) (argE Γ1 dep.root).ty.holdsView dep.root Γ1)) := by
    rw [hargE, hEv]
    by_cases hre' : (Edit.push y).effAt dep.kind (decide (Eo.ty = Ex.ty)) = .realloc
    · -- through a copy of the owner's handle, of its type: the owner's whole tree
      obtain ⟨_, hk, hs⟩ := Edit.effAt_realloc hre'
      have htyo : Eo.ty = .vec t := by rw [of_decide_eq_true hs, hty]
      rw [htyo] at hwT
      obtain ⟨cT, dT, esT, hTe⟩ : ∃ cT dT esT, T = .node t cT dT esT := by
        cases hwT with | node _ => exact ⟨_, _, _, rfl⟩
      have hTn : T = .node t c d es := by
        rcases hla with ⟨_, hnn⟩ | ⟨hkv, _⟩ | ⟨hki, _⟩
        · rw [hnn]; rw [hTe] at htop ⊢; exact htop.node.symm
        · rw [hk] at hkv; cases hkv
        · rw [hk] at hki; cases hki
      subst hTn
      have hT'n : T' = .node t c d' (es ++ [v]) := hr.here_inv
      subst hT'n
      have hcan' := hcan
      rw [hre'] at hcan' hdsV ⊢
      exact MInv.edit_growV hi hanch hEo hlo hoF hcan' htyo hhv hdsV hdbV hT0 hp hoD hre
    · have hdrop : (Edit.push y).effAt dep.kind (decide (Eo.ty = Ex.ty)) = .drop := by
        revert hre'; simp only [Edit.effAt]; split <;> simp
      have hcan' := hcan
      rw [hdrop] at hdsV hcan' ⊢
      exact MInv.edit_dropV hi hanch hEo hoF hcan' hdsV hdbV hEv hT0 hT' hst
        (HeapOK.editPush hi.heap hT0 hp.nd hp.al hp.dis hp.np (hp.views_out hi hanch hoF hoD hT0) hp.sf
          (hi.views_owned hEo hlo hcan.ownSlot hT0) hre hr)
        (by simp [m']) hfn hoD hDn hp.root hr hw' hnew rfl hsh'
  exact MInv.editBV_fin hi hanch hx hmx hl hty hfn hthru hV hDn hp.root hdm hxs hT0 htop hla hhref0
    hno.sub hst hT' rfl hr hw' hsh' hnew hown

/-- A change whose effect on every root is `.drop` (a truncation, an element
    set), its node rewritten in place to one of the same cell and buffer,
    its elements the old ones or values that may hold views, valid through
    `D` (`hes`), in a store whose heap stays valid (`hheap`, given what the
    owner is): as `MInv.editB_drops`, the owner and the other roots holding
    `D` too. -/
theorem MInv.editBV_drops {m1 : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F) {x : Var} {op : Edit} {Ex : Entry} {t : Ty} (hx : Γ1 x = some Ex)
    (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t) (hhv : t.holdsView = true)
    (hfn : t.hasFn = false) (hdrop : ∀ k s, op.effAt k s = .drop) (hthru : ThruOK Γ1 F op Ex.ty Ex.path)
    {D : List Dep} (hV : ThruV Γ1 op Ex.ty Ex.path D) (hDn : ∀ d ∈ D, d.kind.isName = false)
    (hDr : ∀ r ∈ roots D, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true)
    {o : Var} {T T' : Val} {t' : Ty} {c d : Nat} {es es' : List Val} {a' : Nat → Bool}
    (hno : NodeOf m1 x o T t' c d es)
    (hheap : ∀ Eo, Γ1 o = some Eo → Eo.live = true → Eo.mode.ownSlot = true → o ∉ F → o ∉ roots D →
      HeapOK ({ m1 with alloc := a' }.set o ⟨true, some T'⟩))
    (hes : ∀ e ∈ es', e ∈ es ∨ Pushed m1 Γ1 t' e D)
    (hr : Repl (.node t' c d es) (.node t' c d es') T T') :
    MInv ({ m1 with alloc := a' }.set o ⟨true, some T'⟩)
      (A2.setE (holdThru D Ex.path (killThruV op Ex.ty Ex.path Γ1)) x { Ex with held := Ex.held ++ D }) := by
  have hro : ∀ d ∈ memDeps Ex.path, ∃ Er, Γ1 d.root = some Er ∧ Er.mode.ownSlot = true :=
    fun d hd => by
      obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d hd
      exact ⟨Er, hEr, hcan.ownSlot⟩
  obtain ⟨dep, hdm, T0, n0, c0, d0, es0, hxs, hT0, htop, hla, hhref0, hw0, _, huniq, hsh0⟩ :=
    hi.thru_owner hx hmx hl hty hro hthru.noShare
  obtain ⟨rfl, rfl, ht', rfl, rfl, rfl⟩ := huniq _ _ _ _ _ _ hno
  subst t'
  obtain ⟨hoF, _, Eo, hEo, hlo, hcan, _, _⟩ := hthru dep hdm
  obtain ⟨hdsV, hdbV, hoD⟩ := hV dep hdm
  have hargE : argE Γ1 dep.root = Eo := by unfold argE; rw [hEo]; rfl
  rw [hargE] at hdsV hdbV
  have hos := hcan.ownSlot
  obtain ⟨T1, hT1, hwT, _⟩ := hi.own_val hEo hlo hos
  rw [hT0] at hT1; cases hT1
  have hEv : Eo.ty.holdsView = true := hwT.node_holdsView hno.sub hhv
  rw [hEv] at hdsV
  let m' := { m1 with alloc := a' }.set dep.root ⟨true, some T'⟩
  have hst : ∀ w, w ≠ dep.root → m'.st w = m1.st w := fun w hw => by simp [m', upd_ne _ _ hw]
  have hT' : m'.st dep.root = some ⟨true, some T'⟩ := by simp [m']
  have hw' : WFv (.vec t) (.node t c d es') := by
    cases hw0 with
    | node hes0 => exact WFv.node fun e he => (hes e he).elim (hes0 e) (fun h => h.wf)
  have hsh' : SharesOK m' (.vec t) (.node t c d es') :=
    hsh0.node_mem (fun e he => (hes e he).imp id (fun h => h.sh)) rfl
  have hnew : ∀ s w, ViewIn (.vec t) (.node t c d es') s w → ViewIn (.vec t) (.node t c d es) s w ∨
      ∃ d0 o0 l0, w = .view d0 o0 l0 ∧ ∃ dep ∈ D, ViewAt m1 dep d0 o0 l0 s := by
    intro s w hin
    cases hin with
    | child he hin' =>
      rcases hes _ he with h | h
      · exact Or.inl (ViewIn.child h hin')
      · exact Or.inr (h.vs s w hin')
  have hown : MInv m' (A2.holdOn [dep.root] D (A2.kill (op.effAt dep.kind
      (decide ((argE Γ1 dep.root).ty = Ex.ty))) (argE Γ1 dep.root).ty.holdsView dep.root Γ1)) := by
    rw [hargE, hEv, hdrop]
    rw [hdrop] at hcan hdsV
    exact MInv.edit_dropV hi hanch hEo hoF hcan hdsV hdbV hEv hT0 hT' hst
      (hheap Eo hEo hlo hos hoF hoD) (by simp [m']) hfn hoD hDn hDr hr hw' hnew rfl hsh'
  exact MInv.editBV_fin hi hanch hx hmx hl hty hfn hthru hV hDn hDr hdm hxs hT0 htop hla hhref0
    hno.sub hst hT' rfl hr hw' hsh' hnew hown

/-- `editTrunc` through a borrow of elements that hold views: the node's
    elements from the `n`-th on are freed; nothing is stored. -/
theorem MInv.editBV_trunc {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F) {x : Var} {i : Expr} {Ex : Entry} {t : Ty} (hx : Γ x = some Ex)
    (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t) (hhv : t.holdsView = true)
    (hfn : t.hasFn = false) (hthru : ThruOK Γ F (.trunc i) Ex.ty Ex.path)
    (hV : ThruV Γ (.trunc i) Ex.ty Ex.path [])
    {o : Var} {T T' : Val} {t' : Ty} {c d n : Nat} {es : List Val} {a' : Nat → Bool}
    (hno : NodeOf m x o T t' c d es) (hf : FreesL m.alloc (es.drop n) a')
    (hr : Repl (.node t' c d es) (.node t' c d (es.take n)) T T') :
    MInv ({ m with alloc := a' }.set o ⟨true, some T'⟩)
      (A2.setE (holdThru [] Ex.path (killThruV (.trunc i) Ex.ty Ex.path Γ)) x { Ex with held := Ex.held ++ [] }) :=
  MInv.editBV_drops hi hanch hx hmx hl hty hhv hfn (fun _ _ => rfl) hthru hV (fun _ h => by cases h)
    (fun _ h => by cases h) hno (fun _ _ _ _ _ _ => HeapOK.editTrunc hi.heap hno.2.2.1 hf hr)
    (fun e he => Or.inl (List.mem_of_mem_take he)) hr

/-- `editSet` through a borrow: the node's `n`-th element is replaced by the
    value taken in, which may hold views, the old one freed. -/
theorem MInv.editBV_set {m1 : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F) {x y : Var} {i : Expr} {Ex : Entry} {t : Ty} (hx : Γ1 x = some Ex)
    (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t) (hhv : t.holdsView = true)
    (hfn : t.hasFn = false) (hthru : ThruOK Γ1 F (.set i y) Ex.ty Ex.path)
    {D : List Dep} (hV : ThruV Γ1 (.set i y) Ex.ty Ex.path D) (hDn : ∀ d ∈ D, d.kind.isName = false)
    {v : Val} (hp : Pushed m1 Γ1 t v D)
    {o : Var} {T T' : Val} {t' : Ty} {c d n : Nat} {es : List Val} {a' : Nat → Bool}
    (hn : n < es.length) (hno : NodeOf m1 x o T t' c d es) (hf : Frees m1.alloc es[n] a')
    (hr : Repl (.node t' c d es) (.node t' c d (es.set n v)) T T') :
    MInv ({ m1 with alloc := a' }.set o ⟨true, some T'⟩)
      (A2.setE (holdThru D Ex.path (killThruV (.set i y) Ex.ty Ex.path Γ1)) x
        { Ex with held := Ex.held ++ D }) := by
  have ht' : t' = t := by
    have hro : ∀ d ∈ memDeps Ex.path, ∃ Er, Γ1 d.root = some Er ∧ Er.mode.ownSlot = true :=
      fun d hd => by
        obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d hd
        exact ⟨Er, hEr, hcan.ownSlot⟩
    obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, huniq, _⟩ :=
      hi.thru_owner hx hmx hl hty hro hthru.noShare
    exact (huniq _ _ _ _ _ _ hno).2.2.1
  subst ht'
  exact MInv.editBV_drops hi hanch hx hmx hl hty hhv hfn (fun _ _ => rfl) hthru hV hDn hp.root hno
    (fun Eo hEo hlo hos hoF hoD => HeapOK.editSet hi.heap hno.2.2.1 hp.nd hp.al hp.dis hp.np
      (fun a b c h => (hp.views_out hi hanch hoF hoD hno.2.2.1 a b c h).1) hp.sf
      (hi.views_owned hEo hlo hos hno.2.2.1) hn hf hr)
    (fun e he => (List.mem_or_eq_of_mem_set he).elim Or.inl fun h => Or.inr (h ▸ hp)) hr

/-- `editSetOOB` through a borrow: out of range nothing is stored, and the
    value taken in, which no owner holds, is freed; the node is as it was
    (the roots and `x` hold `D` all the same: more than they need). -/
theorem MInv.editBV_setOOB {m1 : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F) {x y : Var} {i : Expr} {Ex : Entry} {t : Ty} (hx : Γ1 x = some Ex)
    (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t) (hhv : t.holdsView = true)
    (hfn : t.hasFn = false) (hthru : ThruOK Γ1 F (.set i y) Ex.ty Ex.path)
    {D : List Dep} (hV : ThruV Γ1 (.set i y) Ex.ty Ex.path D) (hDn : ∀ d ∈ D, d.kind.isName = false)
    {v : Val} (hp : Pushed m1 Γ1 t v D)
    {o : Var} {T : Val} {t' : Ty} {c d : Nat} {es : List Val} {a' : Nat → Bool}
    (hno : NodeOf m1 x o T t' c d es) (hf : Frees m1.alloc v a') :
    MInv { m1 with alloc := a' } (A2.setE (holdThru D Ex.path (killThruV (.set i y) Ex.ty Ex.path Γ1)) x
      { Ex with held := Ex.held ++ D }) := by
  have heq : ({ m1 with alloc := a' } : Mem).set o ⟨true, some T⟩ = { m1 with alloc := a' } :=
    Mem.set_same (m := { m1 with alloc := a' }) hno.2.2.1
  have hh : HeapOK (({ m1 with alloc := a' } : Mem).set o ⟨true, some T⟩) := by
    rw [heq]; exact HeapOK.freeV hi.heap hp.dis hp.np hf
  rw [← heq]
  exact MInv.editBV_drops hi hanch hx hmx hl hty hhv hfn (fun _ _ => rfl) hthru hV hDn hp.root hno
    (fun _ _ _ _ _ _ => hh) (fun e he => Or.inl he) (Repl.self hno.sub)

end A2
