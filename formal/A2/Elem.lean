import A2.EditBV

/-! A2 — an element handed over (Agora #391): the elements of an owned `Vec`
in another order.

An owner's tree is read by membership: what a borrow, a view, a share or a
name finds in a node it finds among its elements, whatever their order, and
a view of the node's own buffer asks only for its length (`ViewAt`). So the
invariant does not see the order of an owned node's elements: permuting
them keeps `HeapOK`, `Covers` and `MInv` (`MInv.perm`). An element moved out
of the middle of a `Vec` is then a `vec_pop` of the element moved to the
end, and one put back at index `n` a `vec_push` whose element is then moved
to `n` (`withElem`, `insert`). -/

namespace A2

/-! ### Lists in another order -/

theorem idsL_perm {es es' : List Val} (h : es.Perm es') : (idsL es).Perm (idsL es') := by
  induction h with
  | nil => exact List.Perm.refl _
  | cons _ _ ih => simp only [idsL_cons]; exact ih.append_left _
  | swap a b l =>
    simp only [idsL_cons, ← List.append_assoc]
    exact List.perm_append_comm.append_right _
  | trans _ _ ih1 ih2 => exact ih1.trans ih2

theorem namesL_perm {es es' : List Val} (h : es.Perm es') : (namesL es).Perm (namesL es') := by
  induction h with
  | nil => exact List.Perm.refl _
  | cons _ _ ih => simp only [namesL]; exact ih.append_left _
  | swap a b l =>
    simp only [namesL, ← List.append_assoc]
    exact List.perm_append_comm.append_right _
  | trans _ _ ih1 ih2 => exact ih1.trans ih2

/-- What lies strictly inside a node lies inside it with its elements in any
    order. -/
theorem Sub.perm {t : Ty} {c d : Nat} {es es' : List Val} (h : es.Perm es') {w : Val}
    (hw : Sub w (.node t c d es')) : w = .node t c d es' ∨ Sub w (.node t c d es) := by
  rcases hw.cases' with h0 | ⟨e, hc, hs⟩
  · exact Or.inl h0
  · cases hc with | elem he => exact Or.inr (Sub.child (h.symm.subset he) hs)

theorem ViewIn.perm {τ t : Ty} {c d : Nat} {es es' : List Val} (h : es.Perm es') {s : Ty} {v : Val}
    (hv : ViewIn τ (.node t c d es') s v) : ViewIn τ (.node t c d es) s v := by
  cases hv with | child he hin => exact ViewIn.child (h.symm.subset he) hin

theorem ViewsOK.perm {m : Mem} {τ t : Ty} {c d : Nat} {es es' : List Val} {H : List Dep}
    (h : es.Perm es') (hv : ViewsOK m τ (.node t c d es) H) : ViewsOK m τ (.node t c d es') H :=
  fun s v hin => hv s v (hin.perm h)

theorem NamesIn.perm {t : Ty} {c d : Nat} {es es' : List Val} {H : List Dep} (h : es.Perm es')
    (hn : NamesIn (.node t c d es) H) : NamesIn (.node t c d es') H := fun c' hc => by
  simp only [Val.names] at hc
  exact hn c' (by simp only [Val.names]; exact (namesL_perm h).symm.subset hc)

theorem PkgsOK.perm {t : Ty} {c d : Nat} {es es' : List Val} (h : es.Perm es')
    (hp : PkgsOK (.node t c d es)) : PkgsOK (.node t c d es') := by
  intro fs te ms e cs hs
  rcases hs.perm h with h0 | h0
  · cases h0
  · exact hp fs te ms e cs h0

theorem SharesOK.perm {m m' : Mem} {τ t : Ty} {c d : Nat} {es es' : List Val} (h : es.Perm es')
    (hs : SharesOK m (.vec τ) (.node t c d es)) (hb : m'.blk = m.blk) :
    SharesOK m' (.vec τ) (.node t c d es') :=
  hs.node_mem (fun _ he => Or.inl (h.symm.subset he)) hb

theorem WFv.perm {τ t : Ty} {c d : Nat} {es es' : List Val} (h : es.Perm es')
    (hw : WFv τ (.node t c d es)) : WFv τ (.node t c d es') := by
  cases hw with | node hes => exact WFv.node fun e he => hes e (h.symm.subset he)

theorem SelfFree.perm {t : Ty} {c d : Nat} {es es' : List Val} (h : es.Perm es')
    (hs : SelfFree (.node t c d es)) : SelfFree (.node t c d es') := by
  intro d0 o l hv u c0 es0 hn
  rcases hv.perm h with h0 | hv'
  · cases h0
  rcases hn.perm h with h0 | hn'
  · cases h0; exact hs _ o l hv' t c es (Sub.refl _)
  · exact hs d0 o l hv' u c0 es0 hn'

theorem ids_perm {t : Ty} {c d : Nat} {es es' : List Val} (h : es.Perm es') :
    (Val.node t c d es').ids.Perm (Val.node t c d es).ids := by
  simp only [ids_node]; exact ((idsL_perm h).symm.cons d).cons c

/-! ### The heap and the cover -/

theorem HeapOK.perm {m : Mem} (hh : HeapOK m) {x : Var} {t : Ty} {c d : Nat} {es es' : List Val}
    (hT : m.st x = some ⟨true, some (.node t c d es)⟩) (h : es.Perm es') :
    HeapOK (m.set x ⟨true, some (.node t c d es')⟩) := by
  have hp := ids_perm (t := t) (c := c) (d := d) h
  have hown : ∀ o U, OwnedAt (m.set x ⟨true, some (.node t c d es')⟩) o U →
      (o = x ∧ U = .node t c d es') ∨ (o ≠ x ∧ OwnedAt m o U) := by
    intro o U hU
    rcases ownedAt_set.mp hU with ⟨h1, h2⟩ | h'
    · cases h2; exact Or.inl ⟨h1, rfl⟩
    · exact Or.inr h'
  refine ⟨fun o U hU => ?_, fun o1 o2 U1 U2 hne h1 h2 => ?_, fun o U hU i hi => ?_, fun o U hU => ?_,
    hh.blk.frame rfl (Nat.le_refl _) (fun _ _ => rfl) (fun o U hU i hi => ?_), hh.views⟩
  · rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h'⟩
    · exact hp.nodup_iff.mpr (hh.nodup x _ hT)
    · exact hh.nodup o U h'
  · rcases hown o1 U1 h1 with ⟨rfl, rfl⟩ | ⟨ho1, h1'⟩ <;> rcases hown o2 U2 h2 with ⟨rfl, rfl⟩ | ⟨ho2, h2'⟩
    · exact absurd rfl hne
    · exact fun i hi => hh.disj _ o2 _ U2 (Ne.symm ho2) hT h2' i (hp.subset hi)
    · exact fun i hi hi' => hh.disj _ o1 _ U1 (Ne.symm ho1) hT h1' i (hp.subset hi') hi
    · exact hh.disj o1 o2 U1 U2 hne h1' h2'
  · rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h'⟩
    · exact hh.alloc x _ hT i (hp.subset hi)
    · exact hh.alloc o U h' i hi
  · rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h'⟩
    · exact (hh.self x _ hT).perm h
    · exact hh.self o U h'
  · rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h'⟩
    · exact hh.notPay hT (hp.subset hi)
    · exact hh.notPay h' hi

theorem Covers.perm {m : Mem} (hc : Covers m) {x : Var} {t : Ty} {c d : Nat} {es es' : List Val}
    (hT : m.st x = some ⟨true, some (.node t c d es)⟩) (h : es.Perm es') :
    Covers (m.set x ⟨true, some (.node t c d es')⟩) := by
  intro i hi
  rcases hc i hi with ⟨y, U, hU, hiU⟩ | hpa
  · by_cases hyx : y = x
    · subst hyx; unfold OwnedAt at hU; rw [hT] at hU; cases hU
      exact Or.inl ⟨y, _, by simp [OwnedAt], (ids_perm h).symm.subset hiU⟩
    · exact Or.inl ⟨y, U, ownedAt_set.mpr (Or.inr ⟨hyx, hU⟩), hiU⟩
  · exact Or.inr hpa

/-! ### What depends on the owner -/

theorem Evolve.perm_vkeep {m m' : Mem} {x : Var} {t : Ty} {c d : Nat} {es es' : List Val}
    (hev : Evolve m m' x t c d d es es') (hp : es.Perm es') (k : Kind) : VKeep m m' ⟨x, k⟩ := by
  intro dd o l s ⟨c', es2, hks, hla, hl, hw⟩
  rcases hla with ⟨n0, hr, hkk⟩ | ⟨hsk, _, k0, bl, hk0, hs⟩
  · have := rootNode_node hev.before hr
    subst this
    rcases hkk with ⟨hv, _⟩ | ⟨hv, heq⟩ | ⟨hki, hb⟩
    · exact absurd hv hks
    · cases heq
      exact ⟨c, es', hks, Or.inl ⟨_, Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inr (Or.inl ⟨hv, rfl⟩)⟩,
        by rw [← hp.length_eq]; exact hl, hev.wf⟩
    · obtain ⟨e, hc, hs⟩ := hb
      cases hc with
      | elem he =>
        exact ⟨c', es2, hks, Or.inl ⟨_, Or.inl ⟨_, hev.after, Top.refl _⟩,
          Or.inr (Or.inr ⟨hki, e, Child.elem (hp.subset he), hs⟩)⟩, hl, hw⟩
  · exact ⟨c', es2, hks, Or.inr ⟨hsk, RootMem.own hev.after, k0, bl, by rw [hev.blk]; exact hk0, hs⟩, hl, hw⟩

theorem Evolve.perm_hkeep {m m' : Mem} {x : Var} {t : Ty} {c d : Nat} {es es' : List Val}
    (hev : Evolve m m' x t c d d es es') (hp : es.Perm es') (k : Kind)
    (hsh' : SharesOK m' (.vec t) (.node t c d es')) : HKeep m m' ⟨x, k⟩ := by
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
          exact Or.inl ⟨_, Or.inl ⟨_, hev.after, Top.refl _⟩,
            Or.inr (Or.inr ⟨hin, e, Child.elem (hp.subset he), hs⟩)⟩
    · exact Or.inr ⟨hsk, RootMem.own hev.after⟩
  rcases hla with ⟨n0, hr, hkk⟩ | ⟨hsk, _, k0, bl, hk0, hs⟩
  · have := rootNode_node hev.before hr
    subst this
    rcases hkk with ⟨hs, heq⟩ | ⟨hvw, heq⟩ | ⟨hin, hbl⟩
    · cases heq
      exact ⟨d, es', Or.inl ⟨_, Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inl ⟨hs, rfl⟩⟩, hw.perm hp,
        (hv.keep hH).perm hp, hn.perm hp, hsh'⟩
    · cases heq
      exact ⟨d, es', Or.inl ⟨_, Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inr (Or.inl ⟨hvw, rfl⟩)⟩, hw.perm hp,
        (hv.keep hH).perm hp, hn.perm hp, hsh'⟩
    · obtain ⟨e, hc, hs⟩ := hbl
      cases hc with
      | elem he =>
        exact ⟨d2, es2, Or.inl ⟨_, Or.inl ⟨_, hev.after, Top.refl _⟩,
          Or.inr (Or.inr ⟨hin, e, Child.elem (hp.subset he), hs⟩)⟩, hw, hv.keep hH, hn, hsh.of_blk hb⟩
  · exact ⟨d2, es2, Or.inr ⟨hsk, RootMem.own hev.after, k0, bl, by rw [hb]; exact hk0, hs⟩, hw, hv.keep hH, hn,
      hsh.of_blk hb⟩

theorem killE_none (hv : Bool) (x : Var) (E : Entry) : killE .none hv x E = E := by
  unfold killE hits; simp [Eff.kills]

theorem kill_none (hv : Bool) (x : Var) (Γ : Ctx) : kill .none hv x Γ = Γ := by
  funext v; simp only [kill]; cases Γ v <;> simp [killE_none]

theorem DtorSafe.none (Γ : Ctx) (hv : Bool) (x : Var) : DtorSafe Γ .none hv x :=
  fun _ _ _ _ _ => by unfold hitsMem; simp [Eff.kills]

/-- **The elements of an owned `Vec` in another order**: the invariant holds
    as it did. Every other binding keeps what it reaches; one that reaches
    into the owner's node reaches the same elements, and a view of its buffer
    the same length. -/
theorem MInv.perm {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hanch : RootbAnch Γ F)
    {x : Var} (hxF : x ∉ F) {t : Ty} {c d : Nat} {es es' : List Val}
    (hT : m.st x = some ⟨true, some (.node t c d es)⟩) (hp : es.Perm es') :
    MInv (m.set x ⟨true, some (.node t c d es')⟩) Γ := by
  obtain ⟨Ex, hx⟩ : ∃ Ex, Γ x = some Ex := by
    have := hi.dom x; rw [hT] at this
    cases h : Γ x with
    | none => rw [h] at this; cases this
    | some E => exact ⟨E, rfl⟩
  obtain ⟨sl, hsl, htok, hown, hownF, _⟩ := hi.slot x Ex hx
  rw [hT] at hsl; cases hsl
  have hos : Ex.mode.ownSlot = true := hown.symm
  obtain ⟨_, hwf, hlv⟩ := hownF hos
  have hwT := hwf _ rfl
  obtain ⟨t0, hty⟩ : ∃ t0, Ex.ty = .vec t0 := by
    cases h : Ex.ty <;> rw [h] at hwT <;> cases hwT; exact ⟨_, rfl⟩
  rw [hty] at hwT
  have htt : t = t0 := by cases hwT; rfl
  subst htt
  have hnrb : Ex.mode ≠ .rootb := fun h => by rw [h] at hos; cases hos
  let m' := m.set x ⟨true, some (.node t c d es')⟩
  have hst : ∀ o, o ≠ x → m'.st o = m.st o := fun o ho => by simp [m', upd_ne _ _ ho]
  have hm'x : m'.st x = some ⟨true, some (.node t c d es')⟩ := by simp [m']
  have hwT' : WFv (.vec t) (.node t c d es') := hwT.perm hp
  have hev : Evolve m m' x t c d d es es' := ⟨hT, hm'x, hwT', rfl⟩
  have hshT : SharesOK m (.vec t) (.node t c d es) := by
    have := hi.shares x Ex _ _ hx hT rfl rfl; rwa [hty] at this
  have hshN : SharesOK m' (.vec t) (.node t c d es') := hshT.perm hp rfl
  have hsfT := hi.heap.self x _ hT
  -- a view the owner holds, valid through another root, stays valid
  have hkeepR : ∀ dep ∈ Ex.held, dep.root ≠ x → (dep.kind.isName = false →
      ∃ Er, Γ dep.root = some Er ∧ Er.mode.isRoot = true) → VKeep m m' dep := by
    intro dep hd hne hr
    cases hnm : dep.kind.isName
    · obtain ⟨Er, hEr, hroot⟩ := hr hnm
      exact (rootKeep_frame hi hanch (fun o ho => hst o (fun h => hxF (h ▸ ho))) hEr hroot
        (hst _ hne)).vkeep
    · obtain ⟨r, k⟩ := dep
      cases k <;> simp [Kind.isName] at hnm
      exact vkeep_name _ _ _ _ _
  have hnint : Ex.ty ≠ .int := by rw [hty]; simp
  have hviews : ∀ H : List Dep, H = Ex.held → (∀ dep ∈ H, dep.root ≠ x → VKeep m m' dep) →
      ViewsOK m (.vec t) (.node t c d es) H → ViewsOK m' (.vec t) (.node t c d es') H :=
    fun H _ hk hv => hv.keep_except hT hsfT (fun s w h => h.perm hp) hk ⟨_, hm'x⟩
  have h := hi.change (e := .none) (hv := false) (ox := some Ex) hanch hx hxF
    (fun _ _ _ _ _ _ _ hk => by simp [Eff.kills] at hk) hnrb hst (hi.heap.perm hT hp) rfl
    (fun k _ => ⟨hev.perm_vkeep hp k, hev.perm_hkeep hp k hshN⟩) ?_ (DtorSafe.none _ _ _)
    (fun h => by cases h) (fun h => by cases h)
    (fun _ Ex' hx' hl hh _ => by cases hx'; exact ⟨hl, hh⟩)
  · have heq : upd (kill .none false x Γ) x (some Ex) = Γ := by
      rw [kill_none]; funext v
      by_cases hvx : v = x
      · subst hvx; simp [hx]
      · simp [upd_ne _ _ hvx]
    rwa [heq] at h
  · have hupd : upd (kill .none false x Γ) x (some Ex) = Γ := by
      rw [kill_none]; funext v
      by_cases hvx : v = x
      · subst hvx; simp [hx]
      · simp [upd_ne _ _ hvx]
    refine ⟨⟨true, some (.node t c d es')⟩, hm'x, htok,
      ⟨by simp [hos], fun _ => ⟨by rw [hty]; rfl, fun U hU => by cases hU; rw [hty]; exact hwT',
        fun hl => ⟨_, rfl, ?_⟩⟩, fun h => by rw [hos] at h; cases h⟩, rfl,
      fun hl hn r hr => ?_, rfl, fun hl hn => by rw [hupd]; exact hi.names x Ex hx hl hn,
      fun hl T hT' => ?_, fun T hT' => ?_, fun hd hos' hn dep hdd hnm => ?_,
      fun hd => hi.wf.arm x Ex hx hd, fun hd => hi.wf.view x Ex hx hd, ?_,
      fun _ T hT' => by cases hT'; rw [hty]; exact hshN⟩
    · obtain ⟨T, hT0, hvs⟩ := hlv hl
      cases hT0; rw [hty] at hvs ⊢
      exact hviews _ rfl (fun dep hd hne => hkeepR dep hd hne fun _ =>
        wf_held hi hx hl hnint dep.root (List.mem_map_of_mem hd)) hvs
    · obtain ⟨Er, hEr, hroot⟩ := hi.wf x Ex hx hl (Or.inl hn) r hr
      by_cases hrx : r = x
      · exact Or.inl ⟨hrx, by rw [hrx, hx] at hEr; cases hEr; exact hroot⟩
      · exact Or.inr ⟨hrx, Er, by rw [kill_none]; exact hEr, hroot⟩
    · cases hT'; exact (hi.held x Ex _ _ hx hl hT rfl).perm hp
    · cases hT'; exact (hi.pkgs x _ _ hT rfl).perm hp
    · obtain ⟨Er, hEr, hroot⟩ := hi.wf.dtor x Ex hx hd hos' (Or.inl hn) dep hdd hnm
      by_cases hrx : dep.root = x
      · exact Or.inl ⟨hrx, by rw [hrx, hx] at hEr; cases hEr; exact hroot⟩
      · exact Or.inr ⟨hrx, Er, by rw [kill_none]; exact hEr, hroot⟩
    · intro hd hos' T hT'
      cases hT'
      obtain ⟨h1, h2⟩ := hi.armed x Ex _ hx hT hd hos' _ rfl
      refine ⟨h1, ?_⟩
      rw [hty] at h2 ⊢
      refine hviews _ rfl (fun dep hd' hne => hkeepR dep hd' hne fun hnm => ?_) h2
      exact hi.wf.dtor x Ex hx hd hos' (Or.inl hnint) dep
        (by simp only [Entry.vdeps, hos, ↓reduceIte, List.nil_append]; exact hd') hnm

end A2
