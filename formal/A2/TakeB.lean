import A2.Elem

/-! A2 — an element moved out through a borrow (AGORA-889, `Stmt.takeB`).

`: y ( vec_remove x i )` (a `vec_pop` is its last index) where `x` is a
borrow: element `n` of the node `x` names leaves its owner's tree where it
lies (`NodeOf`, `Repl`), the ones after it close up, and it becomes the new
owner `y`'s.  It is `editSet`'s reverse: that step moves a value into a node
in place, this one moves one out.

* The owner's change is a truncation's (`.drop`: the borrows of its elements
  end, `killThru`), typed as `editB`'s truncation is (`ThruOK`).  Its memory
  is `MInv.edit_drop`'s, with `HeapOK.editTake`: the owner's tree loses the
  element's addresses, which no owner has until `y` takes them.
* The element is what `vec_pop` hands over (`popE`), and `y` takes it as a
  `letv` binding takes a right-hand side's value: `takeB_pres` gives the
  memory after the change (`RhsPost`), the value (`RhsOut`) and what the
  value covers (`CoversBut`), as `elem_pres` does for `withElem`. -/

namespace A2

/-! ### The owner's tree without the element -/

/-- The addresses of a tree whose node lost its `n`-th element: those it
    kept, then the element's, are the old tree's (`Repl.ids_split`). -/
theorem HT_ids_perm_erase {T T' : Val} {t : Ty} {c d n : Nat} {es : List Val} (hn : n < es.length)
    (hr : Repl (.node t c d es) (.node t c d (es.eraseIdx n)) T T') :
    List.Perm T.ids (T'.ids ++ es[n].ids) := by
  obtain ⟨A, B, h1, h2⟩ := hr.ids_split
  have hes : (idsL es).Perm (idsL (es.eraseIdx n) ++ es[n].ids) := by
    have := idsL_perm (perm_eraseIdx_append es n hn)
    rwa [idsL_append, idsL_cons, idsL_nil, List.append_nil] at this
  rw [h1, h2]
  simp only [ids_node, List.append_assoc, List.cons_append]
  refine List.Perm.append_left A (List.Perm.cons c (List.Perm.cons d ?_))
  have h3 := hes.append_right B
  rw [List.append_assoc] at h3
  exact h3.trans (List.Perm.append_left _ List.perm_append_comm)

/-- **The owner's tree without the element**: its node's `n`-th element is
    taken out, and nothing is freed; the element's addresses are no owner's
    until the new owner takes them. -/
theorem HeapOK.editTake {m : Mem} (hh : HeapOK m) {o : Var} {T T' : Val} {t : Ty} {c d n : Nat}
    {es : List Val} (hT : m.st o = some ⟨true, some T⟩) (hn : n < es.length)
    (hr : Repl (.node t c d es) (.node t c d (es.eraseIdx n)) T T') :
    HeapOK (m.set o ⟨true, some T'⟩) := by
  have hperm := HT_ids_perm_erase hn hr
  have hnT' : T'.ids.Nodup := (List.nodup_append.mp (hperm.nodup_iff.mp (hh.nodup o T hT))).1
  have hsub : ∀ i ∈ T'.ids, i ∈ T.ids := fun i hi => hperm.symm.subset (List.mem_append_left _ hi)
  have hown : ∀ x U, OwnedAt (m.set o ⟨true, some T'⟩) x U →
      (x = o ∧ U = T') ∨ (x ≠ o ∧ OwnedAt m x U) := by
    intro x U hU
    rcases ownedAt_set.mp hU with ⟨h1, h2⟩ | h
    · cases h2; exact Or.inl ⟨h1, rfl⟩
    · exact Or.inr h
  have hblk : BlkOwn (m.set o ⟨true, some T'⟩) :=
    hh.blk.frame rfl (Nat.le_refl _) (fun _ _ => rfl)
      (fun x U hU i hi hp => by
        rcases hown x U hU with ⟨_, rfl⟩ | ⟨_, h⟩
        · exact hh.notPay hT (hsub i hi) hp
        · exact hh.notPay h hi hp)
  refine ⟨fun x U hU => ?_, fun x y U V hne hx hy => ?_, fun x U hU i hi => ?_, fun x U hU => ?_,
    hblk, hh.views⟩
  · rcases hown x U hU with ⟨_, rfl⟩ | ⟨_, h⟩
    · exact hnT'
    · exact hh.nodup x U h
  · rcases hown x U hx with ⟨hxo, hU⟩ | ⟨hxo, hx'⟩ <;>
      rcases hown y V hy with ⟨hyo, hV⟩ | ⟨hyo, hy'⟩
    · exact absurd (hxo.trans hyo.symm) hne
    · subst hxo hU
      exact fun i hi => hh.disj _ y T V hne hT hy' i (hsub i hi)
    · subst hyo hV
      exact fun i hi hi' => hh.disj _ x T U (Ne.symm hne) hT hx' i (hsub i hi') hi
    · exact hh.disj x y U V hne hx' hy'
  · rcases hown x U hU with ⟨_, rfl⟩ | ⟨_, h⟩
    · exact hh.alloc o T hT i (hsub i hi)
    · exact hh.alloc x U h i hi
  · rcases hown x U hU with ⟨_, rfl⟩ | ⟨_, h⟩
    · exact HT_selfFree (fun e he => List.mem_of_mem_eraseIdx he) hr (hh.self o T hT)
    · exact hh.self x U h

/-- **The owner's change** (`MInv.editB_trunc`'s, its node's `n`-th
    element taken out instead of a tail freed): every memory root of `x`'s
    path ends what a truncation there ends, and `x` stays live. -/
theorem MInv.editB_take {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F) {x : Var} {i : Expr} {Ex : Entry} {t : Ty} (hx : Γ x = some Ex)
    (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t) (hhv : t.holdsView = false)
    (hthru : ThruOK Γ F (.trunc i) Ex.ty Ex.path)
    {o : Var} {T T' : Val} {t' : Ty} {c d n : Nat} {es : List Val} (hn : n < es.length)
    (hno : NodeOf m x o T t' c d es)
    (hr : Repl (.node t' c d es) (.node t' c d (es.eraseIdx n)) T T') :
    MInv (m.set o ⟨true, some T'⟩) (A2.setE (killThru (.trunc i) Ex.ty Ex.path Γ) x Ex) := by
  have hro : ∀ d ∈ memDeps Ex.path, ∃ Er, Γ d.root = some Er ∧ Er.mode.ownSlot = true :=
    fun d hd => by
      obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d hd
      exact ⟨Er, hEr, hcan.ownSlot⟩
  obtain ⟨dep, hdm, T0, n0, c0, d0, es0, hxs, hT0, htop, hla, _, hw0, _, huniq, hsh0⟩ :=
    hi.thru_owner hx hmx hl hty hro hthru.noShare
  obtain ⟨rfl, rfl, ht', rfl, rfl, rfl⟩ := huniq _ _ _ _ _ _ hno
  subst t'
  obtain ⟨hoF, _, Eo, hEo, hlo, hcan, hds, _⟩ := hthru dep hdm
  have hargE : argE Γ dep.root = Eo := by unfold argE; rw [hEo]; rfl
  have hxo : x ≠ dep.root := fun e => by rw [e, hT0] at hxs; cases hxs
  have hst : ∀ w, w ≠ dep.root → (m.set dep.root ⟨true, some T'⟩).st w = m.st w :=
    fun w hw => by simp [upd_ne _ _ hw]
  have hT' : (m.set dep.root ⟨true, some T'⟩).st dep.root = some ⟨true, some T'⟩ := by simp
  have hw' : WFv (.vec t) (.node t c d (es.eraseIdx n)) := by
    cases hw0 with
    | node hes => exact WFv.node fun e he => hes e (List.mem_of_mem_eraseIdx he)
  have hsh' : SharesOK (m.set dep.root ⟨true, some T'⟩) (.vec t) (.node t c d (es.eraseIdx n)) :=
    hsh0.node_sub (fun e he => List.mem_of_mem_eraseIdx he) rfl
  have hhref := editB_hrefAt (H := Ex.held) hT' (hi.heap.nodup _ _ hT0) htop hla hr hw' hhv hsh'
  have hown : MInv (m.set dep.root ⟨true, some T'⟩)
      (A2.kill ((Edit.trunc i).effAt dep.kind (decide (Eo.ty = Ex.ty))) false dep.root Γ) := by
    have hdrop : (Edit.trunc i).effAt dep.kind (decide (Eo.ty = Ex.ty)) = .drop := rfl
    rw [hdrop] at hcan hds ⊢
    exact MInv.edit_drop hi hanch hEo hoF hcan hds hT0 hT' hst (HeapOK.editTake hi.heap hT0 hn hr)
      (by simp) hhv hr hw' rfl hsh'
  exact MInv.editB_rest hi.wf hi.names hanch hx hmx hl hty hthru hdm (by rw [hargE]; exact hown)
    (by rw [hst x hxo]; exact hxs) hhref

/-! ### The element moved out -/

/-- `vec_pop`'s entry for an element that owns memory. -/
theorem popE_owning {x : Var} {E : Entry} {t : Ty} (ho : t.owning = true) :
    popE x E t = ⟨t, .own, true, [], E.held, false, false⟩ := by
  cases t <;> simp_all [popE, Ty.owning]

/-- **What moves out is an owned value**, for an element type that owns
    memory and holds no views: the facts a binding's owner needs of it, read
    off where it lay. -/
theorem takeB_outOwn {m1 : Mem} {Γ1 : Ctx} {t : Ty} {e : Val} {H : List Dep}
    (ho : t.owning = true) (htok : t.ok = true) (hw : WFv t e) (hhv : t.holdsView = false)
    (hnd : e.ids.Nodup) (hal : ∀ i ∈ e.ids, m1.alloc i = true ∧ i < m1.nid)
    (hdisj : ∀ x U, OwnedAt m1 x U → ∀ i ∈ e.ids, i ∉ U.ids) (hsf : SelfFree e)
    (hpay : ∀ i ∈ e.ids, ¬ PayAddr m1 i)
    (hwf : ∀ r ∈ roots H, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true)
    (hnk : NameOK Γ1 ⟨t, .own, true, [], H, false, false⟩) (hpk : PkgsOK e)
    (hsh : SharesOK m1 t e) :
    RhsOut m1 Γ1 ⟨t, .own, true, [], H, false, false⟩ e e.owns := by
  rw [hw.owns ho]
  exact ⟨rfl, Or.inl rfl, rfl, htok,
    fun _ r hr => hwf r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr),
    fun _ => ⟨ho, hw, ViewsOK.none hhv _ _, hnd, hal, hdisj, hsf, hpay⟩, (fun h => by cases h),
    fun _ => hnk, (fun x hx => by rw [hw.names_nil hhv] at hx; cases hx), hpk, fun _ => hsh⟩

/-- **What the store covers after the move-out**: what the owner's tree
    covered, but for the element's addresses, which the moved-out value
    covers (`covers_editTrunc`'s, with nothing freed). -/
theorem covers_takeB {m : Mem} (hc : Covers m) {o : Var} {T T' : Val} {t : Ty} {c d n : Nat}
    {es : List Val} (hT : m.st o = some ⟨true, some T⟩) (hn : n < es.length)
    (hr : Repl (.node t c d es) (.node t c d (es.eraseIdx n)) T T') :
    CoversBut (m.set o ⟨true, some T'⟩) es[n] es[n].owns := by
  have hmine : OwnedAt (m.set o ⟨true, some T'⟩) o T' := ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩)
  have hperm := HT_ids_perm_erase hn hr
  intro i hi
  simp only [Mem.set_alloc] at hi
  rcases hc i hi with ⟨o', U, hU, hiU⟩ | hp
  · by_cases hoo : o' = o
    · subst hoo; unfold OwnedAt at hU; rw [hT] at hU; cases hU
      rcases List.mem_append.mp (hperm.subset hiU) with h | h
      · exact Or.inl (Or.inl ⟨o', T', hmine, h⟩)
      · exact Or.inr ⟨Val.owns_of_mem_ids h, h⟩
    · exact Or.inl (Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hoo, hU⟩), hiU⟩)
  · exact Or.inl (Or.inr hp)

/-- What `vec_pop`'s entry depends on is what the `Vec`'s entry holds. -/
theorem popE_vdeps_sub (x : Var) (E : Entry) (t : Ty) : ∀ d ∈ (popE x E t).vdeps, d ∈ E.held := by
  intro d hd
  cases t <;> simp_all [popE, elemE, intE, Entry.vdeps, Mode.ownSlot]

/-- `killNames` binds nothing new. -/
theorem killNames_none {Γ : Ctx} {v : Var} (hv : Γ v = none) : ∀ ds : List Dep, A2.killNames ds Γ v = none
  | [] => hv
  | d :: ds => by
    show (A2.killNames ds Γ v).map _ = none
    rw [killNames_none hv ds]; rfl

/-- A field-like owner's entry (`compE`) for an element type that owns memory
    and holds no views: owned, holding nothing. -/
theorem compE_ownNoView {E : Entry} {t : Ty} (ho : t.owning = true) (hhv : t.holdsView = false) :
    compE E t = ⟨t, .own, true, [], [], false, false⟩ := by
  cases t <;> simp_all [compE, Ty.owning, ownHeld]

/-- What a `compE` entry depends on, the entry it came from holds. -/
theorem compE_vdeps_sub (E : Entry) (t : Ty) : ∀ d ∈ (compE E t).vdeps, d ∈ E.held := by
  intro d hd
  cases t <;> simp only [compE, intE, Entry.vdeps, Mode.ownSlot, ownHeld] at hd <;>
    (try split at hd) <;> simp_all

end A2
