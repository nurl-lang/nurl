import A2.TypingFacts

/-! A2 — a change of elements through a borrow (Agora #295, `StmtT.editB`).

The step rewrites the node a borrow `x` names in place, at any depth of its
owner's tree (`NodeOf`, `Repl`). The owner is the root of one of `x`'s memory
dependencies (`MInv.thru_owner`); the typing cannot tell which, so it changes
every memory root of `x`'s path (`killThru`). The proof here follows that:

* the owner's change of memory, by its effect: `.realloc` for a push through a
  copy of a same-typed root's handle, which is the root's own push
  (`MInv.edit_grow`, from `push_grow`), `.drop` otherwise (`MInv.edit_drop`,
  from `MInv.change` with `HeapOK.editPush` / `HeapOK.editTrunc`,
  `NewSlot.edit` and `deep_self_hkeep`);
* every other root of the path only ends what depends on it
  (`MInv.kill_more`), and kills are absorbed (`killNames_absorb`);
* `x` itself is set back live: its node keeps its cell where it was
  (`editB_hrefAt`, `MInv.reset`; `MInv.editB_rest` puts these together). -/

namespace A2

/-! ### Kills only end entries, in any order, once -/

/-- `killNames` only ends entries. -/
theorem killNames_entry {Γ : Ctx} : ∀ (ds : List Dep) {v : Var} {E : Entry}, Γ v = some E →
    ∃ E', A2.killNames ds Γ v = some E' ∧ (E' = E ∨ E' = { E with live := false })
  | [], _, E, hv => ⟨E, hv, Or.inl rfl⟩
  | d :: ds, v, E, hv => by
    obtain ⟨E1, h1, hE1⟩ := killNames_entry ds hv
    refine ⟨killE d.kind.bound false d.root E1, by
      show (A2.killNames ds Γ v).map _ = _; rw [h1]; rfl, ?_⟩
    unfold killE
    split
    · rcases hE1 with rfl | rfl <;> exact Or.inr rfl
    · exact hE1

/-- An entry that depends on nothing no kill ends. -/
theorem killNames_nil' {Γ : Ctx} {v : Var} {E : Entry} (hv : Γ v = some E) (h : E.vdeps = []) :
    ∀ ds, A2.killNames ds Γ v = some E
  | [] => hv
  | d :: ds => by
    show (A2.killNames ds Γ v).map _ = _
    rw [killNames_nil' hv h ds]; simp [killE_nil h]

theorem killE_comm (a : Eff) (ha : Bool) (x : Var) (b : Eff) (hb : Bool) (y : Var) (E : Entry) :
    killE a ha x (killE b hb y E) = killE b hb y (killE a ha x E) := by
  have h1 : ∀ (E : Entry) (l : Bool), hits a ha x { E with live := l } = hits a ha x E := fun _ _ => rfl
  have h2 : ∀ (E : Entry) (l : Bool), hits b hb y { E with live := l } = hits b hb y E := fun _ _ => rfl
  unfold killE
  by_cases hA : hits a ha x E = true <;> by_cases hB : hits b hb y E = true <;> simp [hA, hB, h1, h2]

theorem killE_idem (a : Eff) (ha : Bool) (x : Var) (E : Entry) :
    killE a ha x (killE a ha x E) = killE a ha x E := by
  have h1 : ∀ (E : Entry) (l : Bool), hits a ha x { E with live := l } = hits a ha x E := fun _ _ => rfl
  unfold killE
  by_cases hA : hits a ha x E = true <;> simp [hA, h1]

theorem kill_comm (a : Eff) (ha : Bool) (x : Var) (b : Eff) (hb : Bool) (y : Var) (Γ : Ctx) :
    A2.kill a ha x (A2.kill b hb y Γ) = A2.kill b hb y (A2.kill a ha x Γ) := by
  funext v
  simp only [A2.kill, Option.map_map, Function.comp_def, killE_comm]

theorem kill_idem (a : Eff) (ha : Bool) (x : Var) (Γ : Ctx) :
    A2.kill a ha x (A2.kill a ha x Γ) = A2.kill a ha x Γ := by
  funext v
  simp only [A2.kill, Option.map_map, Function.comp_def, killE_idem]

theorem killNames_kill (e : Eff) (hv : Bool) (r : Var) (Γ : Ctx) :
    ∀ ds, A2.killNames ds (A2.kill e hv r Γ) = A2.kill e hv r (A2.killNames ds Γ)
  | [] => rfl
  | d :: ds => by
    show A2.kill _ _ _ (A2.killNames ds (A2.kill e hv r Γ)) = A2.kill e hv r (A2.kill _ _ _ (A2.killNames ds Γ))
    rw [killNames_kill e hv r Γ ds, kill_comm]

/-- A kill among `killNames`'s, done again, changes nothing. -/
theorem kill_killNames_mem {Γ : Ctx} : ∀ {ds : List Dep} {d : Dep}, d ∈ ds →
    A2.kill d.kind.bound false d.root (A2.killNames ds Γ) = A2.killNames ds Γ
  | d' :: ds, d, hd => by
    show A2.kill _ _ _ (A2.kill _ _ _ (A2.killNames ds Γ)) = A2.kill _ _ _ (A2.killNames ds Γ)
    rcases List.mem_cons.mp hd with rfl | hd
    · exact kill_idem _ _ _ _
    · rw [kill_comm, kill_killNames_mem hd]

/-- ... so a kill already done is absorbed by `killNames`. -/
theorem killNames_absorb {Γ : Ctx} {ds : List Dep} {d : Dep} (hd : d ∈ ds) :
    A2.killNames ds (A2.kill d.kind.bound false d.root Γ) = A2.killNames ds Γ := by
  rw [killNames_kill, kill_killNames_mem hd]

/-! ### Kills that change no memory -/

theorem RootbAnch.kill {Γ : Ctx} {F : List Var} (h : RootbAnch Γ F) (e : Eff) (hv : Bool) (x : Var) :
    RootbAnch (A2.kill e hv x Γ) F := fun p E hp hm => by
  simp only [A2.kill] at hp
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hp
  rw [killE_mode] at hm
  intro d hd hb
  rw [killE_vdeps] at hd
  exact h p E0 h0 hm d hd hb

theorem RootbAnch.killNames {Γ : Ctx} {F : List Var} (h : RootbAnch Γ F) :
    ∀ ds, RootbAnch (A2.killNames ds Γ) F
  | [] => h
  | _ :: ds => show RootbAnch (A2.kill _ _ _ (A2.killNames ds Γ)) F from (RootbAnch.killNames h ds).kill _ _ _

theorem SlotOK.killE {m : Mem} {E : Entry} {sl : Slot} (h : SlotOK m E sl) (e : Eff) (hv : Bool)
    (x : Var) : SlotOK m (A2.killE e hv x E) sl := by
  unfold A2.killE; split
  · exact ⟨h.1, fun hos => ⟨(h.2.1 hos).1, (h.2.1 hos).2.1, fun hl => by cases hl⟩, fun _ hl => by cases hl⟩
  · exact h

/-- Ending entries at a root that is not lent out, by an effect below
    `replace`, changes no memory and keeps the invariant: no borrowed
    parameter ends (`killE_rootb`). -/
theorem MInv.kill_more {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hanch : RootbAnch Γ F)
    {r : Var} (hrF : r ∉ F) {e : Eff} (he : e ≠ .replace) (hv : Bool) : MInv m (A2.kill e hv r Γ) where
  dom v := by rw [kill_dom]; exact hi.dom v
  slot v E' h := by
    simp only [A2.kill] at h
    obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp h
    obtain ⟨sl, hsl, hok, hs⟩ := hi.slot v E hE
    exact ⟨sl, hsl, by rw [killE_ty]; exact hok, hs.killE e hv r⟩
  heap := hi.heap
  nvSt := hi.nvSt
  noInout v E' b h := by
    simp only [A2.kill] at h
    obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp h
    rw [killE_mode]; exact hi.noInout v E b hE
  wf := hi.wf.kill e hv r
  rootbLive p E' h hm := by
    simp only [A2.kill] at h
    obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp h
    rw [killE_mode] at hm
    rw [killE_rootb hanch hrF e hv (hmn_of_ne_replace hv he r) hE hm]
    exact hi.rootbLive p E hE hm
  rootbLt p E' h hm := by
    simp only [A2.kill] at h
    obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp h
    rw [killE_mode] at hm; rw [killE_vdeps]
    exact hi.rootbLt p E hE hm
  names := hi.names.kill e hv r
  held v E' sl T h hl hsl hT := by
    simp only [A2.kill] at h
    obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp h
    rw [killE_live] at hl; rw [killE_held]
    exact hi.held v E sl T hE (by simp only [Bool.and_eq_true] at hl; exact hl.1) hsl hT
  pkgs := hi.pkgs
  armed v E' sl h hsl := by
    simp only [A2.kill] at h
    obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp h
    intro hd hos T hT
    rw [killE_dbind] at hd; rw [killE_mode] at hos
    obtain ⟨h1, h2⟩ := hi.armed v E sl hE hsl hd hos T hT
    exact ⟨by rw [killE_dtor]; exact h1, by rw [killE_ty, killE_held]; exact h2⟩

theorem MInv.killNames_more {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hanch : RootbAnch Γ F) :
    ∀ ds : List Dep, (∀ d ∈ ds, d.root ∉ F ∧ d.kind.bound ≠ .replace) → MInv m (A2.killNames ds Γ)
  | [], _ => hi
  | d :: ds, h => by
    have ih := MInv.killNames_more hi hanch ds (fun d' hd' => h d' (List.mem_cons_of_mem _ hd'))
    exact ih.kill_more (hanch.killNames ds) (h d (by simp)).1 (h d (by simp)).2 false

/-- ... and so is one written out as such. -/
theorem killNames_absorb' {Γ : Ctx} {ds : List Dep} {r : Var} {e : Eff} {k : Ty}
    (hd : (⟨r, .name e k⟩ : Dep) ∈ ds) : A2.killNames ds (A2.kill e false r Γ) = A2.killNames ds Γ :=
  killNames_absorb hd

/-! ### A borrow made live again -/

/-- A borrow made live again, with the entry it had: only its liveness
    changed, and it holds no binding anything depends on. -/
theorem CtxWF.reset {Γ : Ctx} (h : CtxWF Γ) {x : Var} {Ex : Entry}
    (hx : Γ x = some Ex ∨ Γ x = some { Ex with live := false }) (hos : Ex.mode.ownSlot = false)
    (hroots : (Ex.ty ≠ .int ∨ Ex.mode = .rootb) → ∀ r ∈ roots Ex.vdeps,
      ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) : CtxWF (A2.setE Γ x Ex) := by
  obtain ⟨E0, hE0, hm0, ht0, hv0, hd0, hb0⟩ : ∃ E0, Γ x = some E0 ∧ E0.mode = Ex.mode ∧
      E0.ty = Ex.ty ∧ E0.vdeps = Ex.vdeps ∧ E0.dtor = Ex.dtor ∧ E0.dbind = Ex.dbind := by
    rcases hx with hx | hx
    · exact ⟨_, hx, rfl, rfl, rfl, rfl, rfl⟩
    · exact ⟨_, hx, rfl, rfl, rfl, rfl, rfl⟩
  have hroot : ∀ r, (∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) →
      ∃ Er, A2.setE Γ x Ex r = some Er ∧ Er.mode.isRoot = true := by
    intro r ⟨Er, hEr, hro⟩
    by_cases hrx : r = x
    · subst hrx; rw [hE0] at hEr; cases hEr; exact ⟨Ex, by simp [A2.setE], by rw [← hm0]; exact hro⟩
    · exact ⟨Er, by simp [A2.setE, upd_ne _ _ hrx, hEr], hro⟩
  refine ⟨fun v E' hv hl hn r hr => ?_, fun v E' hv hd hos' hn d hdd hnm => ?_, fun v E' hv ha => ?_,
    fun v E' hv hd => ?_⟩
  · by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv
      exact hroot r (hroots hn r hr)
    · simp only [A2.setE, upd_ne _ _ hvx] at hv; exact hroot r (h v E' hv hl hn r hr)
  · by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv
      rw [hos] at hos'; cases hos'
    · simp only [A2.setE, upd_ne _ _ hvx] at hv; exact hroot d.root (h.dtor v E' hv hd hos' hn d hdd hnm)
  · by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv
      rw [← hb0]; exact h.arm v E0 hE0 (by rw [hd0]; exact ha)
    · simp only [A2.setE, upd_ne _ _ hvx] at hv; exact h.arm v E' hv ha
  · by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv
      rw [← ht0]; exact h.view v E0 hE0 (by rw [hb0]; exact hd)
    · simp only [A2.setE, upd_ne _ _ hvx] at hv; exact h.view v E' hv hd

theorem NameWF.reset {Γ : Ctx} (h : NameWF Γ) {x : Var} {Ex : Entry}
    (hx : Γ x = some Ex ∨ Γ x = some { Ex with live := false }) (hos : Ex.mode.ownSlot = false)
    (hN : Ex.live = true → (Ex.ty ≠ .int ∨ Ex.mode = .rootb) → NameOK Γ Ex) : NameWF (A2.setE Γ x Ex) := by
  -- a binding held by name owns its slot, so it is not `x`
  have tr : ∀ D, DepsNamed Γ D → DepsNamed (A2.setE Γ x Ex) D := by
    intro D hD d hd b t hk
    obtain ⟨Er, hEr, hl, hh, ht, ho, hc⟩ := hD d hd b t hk
    have hrx : d.root ≠ x := by
      intro e; rw [e] at hEr
      rcases hx with hx | hx <;> rw [hx] at hEr <;> cases hEr <;> simp_all
    exact ⟨Er, by simp [A2.setE, upd_ne _ _ hrx, hEr], hl, hh, ht, ho, hc⟩
  intro v Ev hv hl hn
  by_cases hvx : v = x
  · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv
    exact tr _ (hN hl hn)
  · simp only [A2.setE, upd_ne _ _ hvx] at hv; exact tr _ (h v Ev hv hl hn)

/-- A borrow whose slot is valid for its entry may be made live again with
    it (Agora #295: a change through `x` leaves `x`'s node in place). -/
theorem MInv.reset {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {Ex : Entry}
    (hx : Γ x = some Ex ∨ Γ x = some { Ex with live := false }) (hmx : Ex.mode = .bor)
    {w : Val} (hw : m.st x = some ⟨false, some w⟩) (hok : ValOK m Ex.ty w Ex.path Ex.held)
    (hroots : (Ex.ty ≠ .int ∨ Ex.mode = .rootb) → ∀ r ∈ roots Ex.vdeps,
      ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true)
    (hN : Ex.live = true → (Ex.ty ≠ .int ∨ Ex.mode = .rootb) → NameOK Γ Ex)
    (hnm : NamesIn w Ex.held) : MInv m (A2.setE Γ x Ex) where
  dom v := by
    by_cases hvx : v = x
    · subst hvx; simp [A2.setE, hw]
    · simp only [A2.setE, upd_ne _ _ hvx]; exact hi.dom v
  slot v E' h := by
    by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at h; subst h
      have hok0 : Ex.ty.ok = true := by
        rcases hx with hx | hx
        · obtain ⟨_, _, h0, _⟩ := hi.slot v _ hx; exact h0
        · obtain ⟨_, _, h0, _⟩ := hi.slot v _ hx; exact h0
      refine ⟨_, hw, hok0, ?_⟩
      show SlotOK m Ex ⟨false, some w⟩
      exact ⟨by rw [hmx]; rfl, fun hos => (by rw [hmx] at hos; cases hos), fun _ _ => ⟨w, rfl, hok⟩⟩
    · simp only [A2.setE, upd_ne _ _ hvx] at h; exact hi.slot v E' h
  heap := hi.heap
  nvSt := hi.nvSt
  noInout v E' b h := by
    by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at h; subst h; rw [hmx]; simp
    · simp only [A2.setE, upd_ne _ _ hvx] at h; exact hi.noInout v E' b h
  wf := hi.wf.reset hx (by rw [hmx]; rfl) hroots
  rootbLive p E' h hm := by
    by_cases hpx : p = x
    · subst hpx; simp only [A2.setE, upd_same, Option.some.injEq] at h; subst h; rw [hmx] at hm; cases hm
    · simp only [A2.setE, upd_ne _ _ hpx] at h; exact hi.rootbLive p E' h hm
  rootbLt p E' h hm := by
    by_cases hpx : p = x
    · subst hpx; simp only [A2.setE, upd_same, Option.some.injEq] at h; subst h; rw [hmx] at hm; cases hm
    · simp only [A2.setE, upd_ne _ _ hpx] at h; exact hi.rootbLt p E' h hm
  names := hi.names.reset hx (by rw [hmx]; rfl) hN
  held v E' sl T h hl hsl hT := by
    by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at h; subst h
      rw [hw] at hsl; cases hsl; cases hT; exact hnm
    · simp only [A2.setE, upd_ne _ _ hvx] at h; exact hi.held v E' sl T h hl hsl hT
  pkgs := hi.pkgs
  armed v E' sl h hsl := by
    by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at h; subst h
      intro _ hos; rw [hmx] at hos; cases hos
    · simp only [A2.setE, upd_ne _ _ hvx] at h; exact hi.armed v E' sl h hsl

/-- The rest of a change through a borrow, once its owner's tree is changed
    (`hown`): every memory root of `x`'s path ends what its effect ends
    (`MInv.kill_more`; the owner's own kill is absorbed), and `x` is live
    again, valid through the dependency that reached the changed node. -/
theorem MInv.editB_rest {m' : Mem} {Γ1 : Ctx} {F : List Var} (hw : CtxWF Γ1) (hn : NameWF Γ1)
    (hanch : RootbAnch Γ1 F) {x : Var} {op : Edit} {Ex : Entry} {t : Ty}
    (hx : Γ1 x = some Ex) (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t)
    (hthru : ThruOK Γ1 F op Ex.ty Ex.path) {dep : Dep} (hdep : dep ∈ memDeps Ex.path)
    (hown : MInv m' (A2.kill (op.effAt dep.kind (decide ((argE Γ1 dep.root).ty = Ex.ty))) false
      dep.root Γ1))
    {c : Nat} (hxs : m'.st x = some ⟨false, some (.href c)⟩) (hhref : HrefAt m' dep c t Ex.held) :
    MInv m' (A2.setE (killThru op Ex.ty Ex.path Γ1) x Ex) := by
  have hd0 : (⟨dep.root, .name (op.effAt dep.kind (decide ((argE Γ1 dep.root).ty = Ex.ty))) .int⟩ : Dep) ∈
      thruDeps op Γ1 Ex.ty Ex.path := mem_thruDeps.mpr ⟨dep, hdep, rfl⟩
  have hall : ∀ d ∈ thruDeps op Γ1 Ex.ty Ex.path, d.root ∉ F ∧ d.kind.bound ≠ .replace := by
    intro d hd
    refine ⟨?_, (thruDeps_bound hd).1⟩
    obtain ⟨d0, hd0', rfl⟩ := mem_thruDeps.mp hd
    exact (hthru d0 hd0').1
  have h1 := hown.killNames_more (hanch.kill _ _ _) _ hall
  rw [killNames_absorb' hd0] at h1
  obtain ⟨E', hE', hE'c⟩ := killNames_entry (thruDeps op Γ1 Ex.ty Ex.path) hx
  refine h1.reset (x := x) (Ex := Ex) (by rcases hE'c with rfl | rfl; exact Or.inl hE'; exact Or.inr hE')
    hmx hxs (by rw [hty]; exact .href ⟨dep, (List.mem_filter.mp hdep).1, hhref⟩) (fun hn' r hr => ?_)
    (fun _ hn' => ?_) (fun c' hc' => by simp [Val.names] at hc')
  · obtain ⟨Er, hEr, hro⟩ := hw x Ex hx hl hn' r hr
    obtain ⟨Er', hEr', hEr'c⟩ := killNames_entry (thruDeps op Γ1 Ex.ty Ex.path) hEr
    exact ⟨Er', hEr', by rcases hEr'c with rfl | rfl <;> exact hro⟩
  · intro d hd b t' hk
    obtain ⟨Er, hEr, hlr, hh, ht, ho, hc⟩ := hn x Ex hx hl hn' d hd b t' hk
    exact ⟨Er, killNames_nil' hEr (root_vdeps ho hh) _, hlr, hh, ht, ho, hc⟩

/-! ### The owner's tree, rewritten in place: the proof obligations

`n = node t c d es` is the node the change finds, `n'` what it becomes: of
the same type and cell, with elements that hold no views (`t.holdsView =
false`), so it holds no view, captures nothing by name and has no package. -/

/-- A list of distinct addresses keeps them distinct when its middle is
    replaced by distinct addresses, each of the old middle or new to the
    list. -/
theorem HP_nodup_mid {A X X' B : List Nat} (h : (A ++ X ++ B).Nodup) (h' : X'.Nodup)
    (hX : ∀ i ∈ X', i ∈ X ∨ i ∉ A ++ X ++ B) : (A ++ X' ++ B).Nodup := by
  rw [List.nodup_append, List.nodup_append] at h ⊢
  obtain ⟨⟨hA, _, hAX⟩, hB, hAXB⟩ := h
  refine ⟨⟨hA, h', fun a ha b hb => ?_⟩, hB, fun a ha b hb => ?_⟩
  · rcases hX b hb with hbX | hbn
    · exact hAX a ha b hbX
    · intro hab; subst hab; exact hbn (List.mem_append_left _ (List.mem_append_left _ ha))
  · rcases List.mem_append.mp ha with haA | haX'
    · exact hAXB a (List.mem_append_left _ haA) b hb
    · rcases hX a haX' with haX | han
      · exact hAXB a (List.mem_append_right _ haX) b hb
      · intro hab; subst hab; exact han (List.mem_append_right _ hb)

/-- The hole of a tree with distinct addresses has distinct addresses. -/
theorem HP_nodup_hole {n n' T T' : Val} (hr : Repl n n' T T') (hnd : T.ids.Nodup) : n.ids.Nodup := by
  obtain ⟨A, B, h1, _⟩ := hr.ids_split
  rw [h1, List.nodup_append, List.nodup_append] at hnd
  exact hnd.1.2.1

/-- An address of the rewritten tree is the replacement's, or one of the
    old tree's outside the hole (`Repl.mem_ids`, sharpened by `Nodup`). -/
theorem HP_mem_ids {n n' T T' : Val} (hr : Repl n n' T T') (hnd : T.ids.Nodup) {i : Nat}
    (hi : i ∈ T'.ids) : i ∈ n'.ids ∨ (i ∈ T.ids ∧ i ∉ n.ids) := by
  obtain ⟨A, B, h1, h2⟩ := hr.ids_split
  rw [h1] at hnd ⊢
  rw [h2] at hi
  rw [List.nodup_append, List.nodup_append] at hnd
  obtain ⟨⟨_, _, hAX⟩, _, hAXB⟩ := hnd
  rcases List.mem_append.mp hi with hi | hiB
  · rcases List.mem_append.mp hi with hiA | hiX
    · exact Or.inr ⟨List.mem_append_left _ (List.mem_append_left _ hiA), fun hX => hAX i hiA i hX rfl⟩
    · exact Or.inl hiX
  · exact Or.inr ⟨List.mem_append_right _ hiB, fun hX => hAXB i (List.mem_append_right _ hX) i hiB rfl⟩

/-- A part of the rewritten tree lies in the replacement, lies in the old
    tree, or holds the hole: it is the rewrite of a part of the old tree. -/
theorem HP_sub_repl {n n' T T' w : Val} (hr : Repl n n' T T') (hw : Sub w T') :
    Sub w n' ∨ Sub w T ∨ ∃ w0, Sub w0 T ∧ Repl n n' w0 w := by
  induction hr with
  | here => exact Or.inl hw
  | @elem t c d pre post e e' hr' ih =>
    rcases hw.cases' with rfl | ⟨e2, hc, hs⟩
    · exact Or.inr (Or.inr ⟨_, Sub.refl _, Repl.elem hr'⟩)
    · cases hc with
      | elem he =>
        rcases List.mem_append.mp he with h | h
        · exact Or.inr (Or.inl (Sub.child (List.mem_append_left _ h) hs))
        · rcases List.mem_cons.mp h with rfl | h
          · rcases ih hs with h1 | h1 | ⟨w0, h0, hw0⟩
            · exact Or.inl h1
            · exact Or.inr (Or.inl (Sub.child (List.mem_append_right _ List.mem_cons_self) h1))
            · exact Or.inr (Or.inr ⟨w0, Sub.child (List.mem_append_right _ List.mem_cons_self) h0, hw0⟩)
          · exact Or.inr (Or.inl (Sub.child (List.mem_append_right _ (List.mem_cons_of_mem _ h)) hs))
  | @fst a a' b hr' ih =>
    rcases hw.cases' with rfl | ⟨e2, hc, hs⟩
    · exact Or.inr (Or.inr ⟨_, Sub.refl _, Repl.fst hr'⟩)
    · cases hc with
      | fst =>
        rcases ih hs with h1 | h1 | ⟨w0, h0, hw0⟩
        · exact Or.inl h1
        · exact Or.inr (Or.inl (Sub.fst h1))
        · exact Or.inr (Or.inr ⟨w0, Sub.fst h0, hw0⟩)
      | snd => exact Or.inr (Or.inl (Sub.snd hs))
  | @snd a b b' hr' ih =>
    rcases hw.cases' with rfl | ⟨e2, hc, hs⟩
    · exact Or.inr (Or.inr ⟨_, Sub.refl _, Repl.snd hr'⟩)
    · cases hc with
      | fst => exact Or.inr (Or.inl (Sub.fst hs))
      | snd =>
        rcases ih hs with h1 | h1 | ⟨w0, h0, hw0⟩
        · exact Or.inl h1
        · exact Or.inr (Or.inl (Sub.snd h1))
        · exact Or.inr (Or.inr ⟨w0, Sub.snd h0, hw0⟩)
  | @inl a a' hr' ih =>
    rcases hw.cases' with rfl | ⟨e2, hc, hs⟩
    · exact Or.inr (Or.inr ⟨_, Sub.refl _, Repl.inl hr'⟩)
    · cases hc with
      | inl =>
        rcases ih hs with h1 | h1 | ⟨w0, h0, hw0⟩
        · exact Or.inl h1
        · exact Or.inr (Or.inl (Sub.inl h1))
        · exact Or.inr (Or.inr ⟨w0, Sub.inl h0, hw0⟩)
  | @inr a a' hr' ih =>
    rcases hw.cases' with rfl | ⟨e2, hc, hs⟩
    · exact Or.inr (Or.inr ⟨_, Sub.refl _, Repl.inr hr'⟩)
    · cases hc with
      | inr =>
        rcases ih hs with h1 | h1 | ⟨w0, h0, hw0⟩
        · exact Or.inl h1
        · exact Or.inr (Or.inl (Sub.inr h1))
        · exact Or.inr (Or.inr ⟨w0, Sub.inr h0, hw0⟩)
  | @pkg fs te ms cs a a' hr' ih =>
    rcases hw.cases' with rfl | ⟨e2, hc, hs⟩
    · exact Or.inr (Or.inr ⟨_, Sub.refl _, Repl.pkg hr'⟩)
    · cases hc with
      | pkg =>
        rcases ih hs with h1 | h1 | ⟨w0, h0, hw0⟩
        · exact Or.inl h1
        · exact Or.inr (Or.inl (Sub.pkg h1))
        · exact Or.inr (Or.inr ⟨w0, Sub.pkg h0, hw0⟩)

/-- A view of the rewritten tree lies in the replacement or in the old
    tree: no part that holds the hole is a view. -/
theorem HP_view_repl {n n' T T' : Val} {d0 o0 l0 : Nat} (hr : Repl n n' T T')
    (hv : Sub (.view d0 o0 l0) T') : Sub (.view d0 o0 l0) n' ∨ Sub (.view d0 o0 l0) T := by
  rcases HP_sub_repl hr hv with h | h | ⟨w0, _, hw0⟩
  · exact Or.inl h
  · exact Or.inr h
  · cases hw0 with
    | here => exact Or.inl (Sub.refl _)

/-- A node of the rewritten tree lies in the replacement, or the old tree
    has a node of the same type, cell and buffer (a node that holds the
    hole keeps them, `Repl.node_shape`). -/
theorem HP_node_repl {n n' T T' : Val} {u : Ty} {c0 d0 : Nat} {es0 : List Val}
    (hr : Repl n n' T T') (hn : Sub (.node u c0 d0 es0) T') :
    Sub (.node u c0 d0 es0) n' ∨ ∃ es1, Sub (.node u c0 d0 es1) T := by
  rcases HP_sub_repl hr hn with h | h | ⟨w0, h0, hw0⟩
  · exact Or.inl h
  · exact Or.inr ⟨_, h⟩
  · cases hw0 with
    | here => exact Or.inl (Sub.refl _)
    | elem _ => exact Or.inr ⟨_, h0⟩

/-- A part of a node grown by `v` is the node itself, a part of the node
    before (whatever its buffer was), or a part of `v`. -/
theorem HP_sub_push {w v : Val} {t : Ty} {c d d' : Nat} {es : List Val}
    (h : Sub w (.node t c d' (es ++ [v]))) :
    w = .node t c d' (es ++ [v]) ∨ Sub w (.node t c d es) ∨ Sub w v := by
  rcases h.cases' with h | ⟨e, hc, hs⟩
  · exact Or.inl h
  · cases hc with
    | elem he =>
      rcases List.mem_append.mp he with h | h
      · exact Or.inr (Or.inl (Sub.child h hs))
      · rw [List.mem_singleton] at h; subst h; exact Or.inr (Or.inr hs)

/-- A push into a node of an owned tree, its buffer kept or moved to a
    fresh one: addresses stay distinct, owned once, live and below `nid`, and
    no owned tree views itself (what `T` views is owned in `m`, so it is
    neither `v`, which no owner holds, nor a fresh buffer). -/
theorem HeapOK.editPush {m : Mem} (hh : HeapOK m) {o : Var} {T T' : Val} {t : Ty} {c d : Nat}
    {es : List Val} (hT : m.st o = some ⟨true, some T⟩) {v : Val} (hnd : v.ids.Nodup)
    (hal : ∀ i ∈ v.ids, m.alloc i = true ∧ i < m.nid)
    (hdis : ∀ o' U, OwnedAt m o' U → ∀ i ∈ v.ids, i ∉ U.ids)
    (hvv : ∀ d0 o0 l0, ¬ Sub (.view d0 o0 l0) v)
    (hvT : ∀ d0 o0 l0, Sub (.view d0 o0 l0) T → ∃ o' U, OwnedAt m o' U ∧ d0 ∈ U.ids)
    {d' : Nat} {A' : Nat → Bool} {N' : Nat}
    (hre : (d' = d ∧ A' = m.alloc ∧ N' = m.nid) ∨
      (d' = m.nid ∧ A' = upd (upd m.alloc d false) m.nid true ∧ N' = m.nid + 1))
    (hr : Repl (.node t c d es) (.node t c d' (es ++ [v])) T T') :
    HeapOK ({ m with alloc := A', nid := N' }.set o ⟨true, some T'⟩) := by
  have hnT := hh.nodup o T hT
  have halT := hh.alloc o T hT
  have hvT' : ∀ i ∈ v.ids, i ∉ T.ids := hdis o T hT
  have hsT : Sub (.node t c d es) T := hr.sub
  have hdT : d ∈ T.ids := hsT.ids d (by simp)
  have hcT : c ∈ T.ids := hsT.ids c (by simp)
  have hesT : ∀ i ∈ idsL es, i ∈ T.ids := fun i hi => hsT.ids i (by simp [hi])
  have hNle : m.nid ≤ N' := by rcases hre with ⟨_, _, rfl⟩ | ⟨_, _, rfl⟩ <;> omega
  -- addresses other than the moved buffer keep their liveness
  have hA : ∀ i, i ≠ d → i ≠ m.nid → A' i = m.alloc i := by
    intro i h1 h2
    rcases hre with ⟨_, rfl, _⟩ | ⟨_, rfl, _⟩
    · rfl
    · rw [upd_ne _ _ h2, upd_ne _ _ h1]
  have hd'c : d' = d ∨ d' = m.nid := by
    rcases hre with ⟨h, _⟩ | ⟨h, _⟩
    · exact Or.inl h
    · exact Or.inr h
  have hfresh : ∀ o1 U, OwnedAt m o1 U → m.nid ∉ U.ids := fun o1 U hU hi => by
    have := (hh.alloc o1 U hU _ hi).2; omega
  -- the hole's addresses are distinct
  have hnn := HP_nodup_hole hr hnT
  simp only [ids_node, List.nodup_cons, List.mem_cons, not_or] at hnn
  -- an address of the new tree is one of the old tree's other than the
  -- hole's buffer, the new buffer, or one of `v`'s
  have hmem : ∀ i ∈ T'.ids, (i ∈ T.ids ∧ i ≠ d) ∨ i = d' ∨ i ∈ v.ids := by
    intro i hi
    rcases HP_mem_ids hr hnT hi with hi | ⟨hiT, hin⟩
    · simp only [ids_node, idsL_append, idsL_cons, idsL_nil, List.append_nil, List.mem_cons,
        List.mem_append] at hi
      rcases hi with rfl | rfl | hi | hi
      · exact Or.inl ⟨hcT, hnn.1.1⟩
      · exact Or.inr (Or.inl rfl)
      · exact Or.inl ⟨hesT i hi, fun h => hnn.2.1 (h ▸ hi)⟩
      · exact Or.inr (Or.inr hi)
    · exact Or.inl ⟨hiT, fun h => hin (by rw [h]; simp)⟩
  have hown : ∀ o1 U, OwnedAt ({ m with alloc := A', nid := N' }.set o ⟨true, some T'⟩) o1 U →
      (o1 = o ∧ U = T') ∨ (o1 ≠ o ∧ OwnedAt m o1 U) := by
    intro o1 U hU
    rcases ownedAt_set.mp hU with ⟨h1, h2⟩ | h
    · cases h2; exact Or.inl ⟨h1, rfl⟩
    · exact Or.inr h
  refine ⟨fun o1 U hU => ?_, fun o1 o2 U1 U2 hne h1 h2 => ?_, fun o1 U hU i hi => ?_, fun o1 U hU => ?_⟩
  · -- nodup: the hole's addresses give way to the new node's
    rcases hown o1 U hU with ⟨_, hUT⟩ | ⟨_, h⟩
    · rw [hUT]
      obtain ⟨A, B, h1, h2⟩ := hr.ids_split
      rw [h2]
      have hnT1 := hnT
      rw [h1] at hnT1
      refine HP_nodup_mid hnT1 ?_ ?_
      · -- the new node's addresses are distinct (`HeapOK.grow`)
        simp only [ids_node, idsL_append, idsL_cons, idsL_nil, List.append_nil, List.nodup_cons,
          List.mem_cons, List.mem_append, not_or, List.nodup_append]
        refine ⟨⟨?_, hnn.1.2, fun h => hvT' c h hcT⟩, ⟨?_, ?_⟩, hnn.2.2, hnd, fun a ha b hb hab => ?_⟩
        · rcases hd'c with h | h
          · rw [h]; exact hnn.1.1
          · have := (halT c hcT).2; omega
        · rcases hd'c with h | h
          · rw [h]; exact hnn.2.1
          · exact fun h' => by have := (halT _ (hesT _ h')).2; omega
        · rcases hd'c with h | h
          · rw [h]; exact fun h' => hvT' d h' hdT
          · exact fun h' => by have := (hal _ h').2; omega
        · subst hab; exact hvT' a hb (hesT a ha)
      · -- each is the hole's, or new to the old tree
        intro i hi
        rw [← h1]
        simp only [ids_node, idsL_append, idsL_cons, idsL_nil, List.append_nil, List.mem_cons,
          List.mem_append] at hi ⊢
        rcases hi with hi | hi | hi | hi
        · exact Or.inl (Or.inl hi)
        · rcases hd'c with h | h
          · exact Or.inl (Or.inr (Or.inl (hi.trans h)))
          · exact Or.inr (fun hT0 => by have := (halT _ hT0).2; omega)
        · exact Or.inl (Or.inr (Or.inr hi))
        · exact Or.inr (hvT' i hi)
    · exact hh.nodup o1 U h
  · -- disj: the new tree's addresses are the old tree's, a fresh one, or `v`'s
    have key : ∀ o2 U, o2 ≠ o → OwnedAt m o2 U → ∀ i ∈ T'.ids, i ∉ U.ids := by
      intro o2 U ho2 hU i hi hiU
      rcases hmem i hi with ⟨hiT, _⟩ | hid' | hiv
      · exact hh.disj o o2 T U (Ne.symm ho2) hT hU i hiT hiU
      · rcases hd'c with h | h
        · exact hh.disj o o2 T U (Ne.symm ho2) hT hU i (by rw [hid', h]; exact hdT) hiU
        · exact hfresh o2 U hU (by rw [← h, ← hid']; exact hiU)
      · exact hdis o2 U hU i hiv hiU
    rcases hown o1 U1 h1 with ⟨ho1, hU1⟩ | ⟨ho1, h1'⟩ <;>
      rcases hown o2 U2 h2 with ⟨ho2, hU2⟩ | ⟨ho2, h2'⟩
    · exact absurd (ho1.trans ho2.symm) hne
    · rw [hU1]; exact key o2 U2 ho2 h2'
    · rw [hU2]; exact fun i hi hi' => key o1 U1 ho1 h1' i hi' hi
    · exact hh.disj o1 o2 U1 U2 hne h1' h2'
  · -- alloc: only the hole's buffer may be freed, and it occurs only there
    show A' i = true ∧ i < N'
    rcases hown o1 U hU with ⟨_, hUT⟩ | ⟨ho1, h⟩
    · rw [hUT] at hi
      rcases hmem i hi with ⟨hiT, hid⟩ | hid' | hiv
      · obtain ⟨ha, hlt⟩ := halT i hiT
        exact ⟨by rw [hA i hid (by omega)]; exact ha, by omega⟩
      · rw [hid']
        rcases hre with ⟨rfl, rfl, rfl⟩ | ⟨rfl, rfl, rfl⟩
        · exact halT _ hdT
        · exact ⟨by simp, by omega⟩
      · obtain ⟨ha, hlt⟩ := hal i hiv
        have hid : i ≠ d := fun h' => hvT' i hiv (h' ▸ hdT)
        exact ⟨by rw [hA i hid (by omega)]; exact ha, by omega⟩
    · obtain ⟨ha, hlt⟩ := hh.alloc o1 U h i hi
      have hid : i ≠ d := fun h' => hh.disj o o1 T U (Ne.symm ho1) hT h d hdT (h' ▸ hi)
      exact ⟨by rw [hA i hid (by omega)]; exact ha, by omega⟩
  · -- self: every view of the new tree is one of `T`'s, so its buffer is owned in `m`
    rcases hown o1 U hU with ⟨_, hUT⟩ | ⟨_, h⟩
    · rw [hUT]
      intro d0 o0 l0 hv u c0 es0 hn
      -- the view lies in the old tree: `v` holds none
      have hvT0 : Sub (.view d0 o0 l0) T := by
        rcases HP_view_repl hr hv with h | h
        · rcases HP_sub_push (d := d) h with h | h | h
          · cases h
          · exact h.trans hsT
          · exact absurd h (hvv _ _ _)
        · exact h
      obtain ⟨o', U', hU', hdU⟩ := hvT d0 o0 l0 hvT0
      have hsf := hh.self o T hT d0 o0 l0 hvT0
      -- so its buffer is no node's of `T`, not a fresh one and none of `v`'s
      rcases HP_node_repl hr hn with h | ⟨es1, h⟩
      · rcases HP_sub_push (d := d) h with h | h | h
        · injection h with _ _ hd0
          rcases hd'c with h' | h'
          · exact hsf t c es (by rw [hd0, h']; exact hsT)
          · exact hfresh o' U' hU' (by rw [← h', ← hd0]; exact hdU)
        · exact hsf u c0 es0 (h.trans hsT)
        · exact hdis o' U' hU' d0 (h.ids d0 (by simp)) hdU
      · exact hsf u c0 es1 h
    · exact hh.self o1 U h

/-- A view in a tree whose hole kept some of its elements (and its type,
    cell and buffer) was in the old tree. -/
theorem HT_view_sub {t : Ty} {c d : Nat} {es es' : List Val} (hes : ∀ e ∈ es', e ∈ es)
    {T T' : Val} (hr : Repl (.node t c d es) (.node t c d es') T T') {d0 o0 l0 : Nat}
    (hv : Sub (.view d0 o0 l0) T') : Sub (.view d0 o0 l0) T := by
  induction hr with
  | here =>
    rcases hv.cases' with h | ⟨e, hc, hs⟩
    · cases h
    · cases hc with | elem he => exact Sub.child (hes _ he) hs
  | elem _ ih =>
    rcases hv.cases' with h | ⟨e, hc, hs⟩
    · cases h
    · cases hc with
      | elem he =>
        rcases List.mem_append.mp he with h | h
        · exact Sub.child (List.mem_append_left _ h) hs
        · rcases List.mem_cons.mp h with rfl | h
          · exact Sub.child (List.mem_append_right _ List.mem_cons_self) (ih hs)
          · exact Sub.child (List.mem_append_right _ (List.mem_cons_of_mem _ h)) hs
  | fst _ ih =>
    rcases hv.cases' with h | ⟨e, hc, hs⟩
    · cases h
    · cases hc with
      | fst => exact Sub.fst (ih hs)
      | snd => exact Sub.snd hs
  | snd _ ih =>
    rcases hv.cases' with h | ⟨e, hc, hs⟩
    · cases h
    · cases hc with
      | fst => exact Sub.fst hs
      | snd => exact Sub.snd (ih hs)
  | inl _ ih =>
    rcases hv.cases' with h | ⟨e, hc, hs⟩
    · cases h
    · cases hc with | inl => exact Sub.inl (ih hs)
  | inr _ ih =>
    rcases hv.cases' with h | ⟨e, hc, hs⟩
    · cases h
    · cases hc with | inr => exact Sub.inr (ih hs)
  | pkg _ ih =>
    rcases hv.cases' with h | ⟨e, hc, hs⟩
    · cases h
    · cases hc with | pkg => exact Sub.pkg (ih hs)

/-- ... and so was a node with the same buffer: a node of the new tree is
    one of the old tree, or the old one at its place with the hole changed in
    it (which keeps its buffer). -/
theorem HT_node_sub {t : Ty} {c d : Nat} {es es' : List Val} (hes : ∀ e ∈ es', e ∈ es)
    {T T' : Val} (hr : Repl (.node t c d es) (.node t c d es') T T') {u : Ty} {c0 d0 : Nat}
    {es0 : List Val} (hn : Sub (.node u c0 d0 es0) T') :
    ∃ u' c0' es0', Sub (.node u' c0' d0 es0') T := by
  induction hr with
  | here =>
    rcases hn.cases' with h | ⟨e, hc, hs⟩
    · cases h; exact ⟨_, _, _, Sub.refl _⟩
    · cases hc with | elem he => exact ⟨_, _, _, Sub.child (hes _ he) hs⟩
  | elem _ ih =>
    rcases hn.cases' with h | ⟨e, hc, hs⟩
    · cases h; exact ⟨_, _, _, Sub.refl _⟩
    · cases hc with
      | elem he =>
        rcases List.mem_append.mp he with h | h
        · exact ⟨_, _, _, Sub.child (List.mem_append_left _ h) hs⟩
        · rcases List.mem_cons.mp h with rfl | h
          · obtain ⟨u', c0', es0', h'⟩ := ih hs
            exact ⟨u', c0', es0', Sub.child (List.mem_append_right _ List.mem_cons_self) h'⟩
          · exact ⟨_, _, _, Sub.child (List.mem_append_right _ (List.mem_cons_of_mem _ h)) hs⟩
  | fst _ ih =>
    rcases hn.cases' with h | ⟨e, hc, hs⟩
    · cases h
    · cases hc with
      | fst => obtain ⟨u', c0', es0', h'⟩ := ih hs; exact ⟨u', c0', es0', Sub.fst h'⟩
      | snd => exact ⟨_, _, _, Sub.snd hs⟩
  | snd _ ih =>
    rcases hn.cases' with h | ⟨e, hc, hs⟩
    · cases h
    · cases hc with
      | fst => exact ⟨_, _, _, Sub.fst hs⟩
      | snd => obtain ⟨u', c0', es0', h'⟩ := ih hs; exact ⟨u', c0', es0', Sub.snd h'⟩
  | inl _ ih =>
    rcases hn.cases' with h | ⟨e, hc, hs⟩
    · cases h
    · cases hc with
      | inl => obtain ⟨u', c0', es0', h'⟩ := ih hs; exact ⟨u', c0', es0', Sub.inl h'⟩
  | inr _ ih =>
    rcases hn.cases' with h | ⟨e, hc, hs⟩
    · cases h
    · cases hc with
      | inr => obtain ⟨u', c0', es0', h'⟩ := ih hs; exact ⟨u', c0', es0', Sub.inr h'⟩
  | pkg _ ih =>
    rcases hn.cases' with h | ⟨e, hc, hs⟩
    · cases h
    · cases hc with
      | pkg => obtain ⟨u', c0', es0', h'⟩ := ih hs; exact ⟨u', c0', es0', Sub.pkg h'⟩

/-- A tree whose hole kept some of its elements views itself no more than
    the old tree did (as `SelfFree.shrink`, at any depth). -/
theorem HT_selfFree {t : Ty} {c d : Nat} {es es' : List Val} (hes : ∀ e ∈ es', e ∈ es)
    {T T' : Val} (hr : Repl (.node t c d es) (.node t c d es') T T') (hs : SelfFree T) :
    SelfFree T' := fun d0 o0 l0 hv u c0 es0 hn => by
  obtain ⟨u', c0', es0', h⟩ := HT_node_sub hes hr hn
  exact hs d0 o0 l0 (HT_view_sub hes hr hv) u' c0' es0' h

/-- The addresses of a truncated tree: those it kept, then those it dropped,
    are the old tree's (`Repl.ids_split`). -/
theorem HT_ids_perm {T T' : Val} {t : Ty} {c d n : Nat} {es : List Val}
    (hr : Repl (.node t c d es) (.node t c d (es.take n)) T T') :
    List.Perm T.ids (T'.ids ++ idsL (es.drop n)) := by
  obtain ⟨A, B, h1, h2⟩ := hr.ids_split
  have hes : idsL es = idsL (es.take n) ++ idsL (es.drop n) := by
    rw [← idsL_append, List.take_append_drop]
  rw [h1, h2]
  simp only [ids_node, hes, List.append_assoc, List.cons_append]
  exact List.Perm.append_left A (List.Perm.cons c (List.Perm.cons d
    (List.Perm.append_left _ List.perm_append_comm)))

/-- A truncation of a node of an owned tree, what it drops freed. -/
theorem HeapOK.editTrunc {m : Mem} (hh : HeapOK m) {o : Var} {T T' : Val} {t : Ty} {c d n : Nat}
    {es : List Val} (hT : m.st o = some ⟨true, some T⟩) {a' : Nat → Bool}
    (hf : FreesL m.alloc (es.drop n) a')
    (hr : Repl (.node t c d es) (.node t c d (es.take n)) T T') :
    HeapOK ({ m with alloc := a' }.set o ⟨true, some T'⟩) := by
  have hperm := HT_ids_perm hr
  -- the new tree's addresses are distinct, the old tree's, and none dropped
  obtain ⟨hnT', -, hdisj⟩ := List.nodup_append.mp (hperm.nodup_iff.mp (hh.nodup o T hT))
  have hsub : ∀ i ∈ T'.ids, i ∈ T.ids := fun i hi => hperm.symm.subset (List.mem_append_left _ hi)
  -- what is dropped is the old tree's, so no other owner's
  have hdrop : ∀ i ∈ idsL (es.drop n), i ∈ T.ids := fun i hi => hr.sub.ids i (ids_drop_sub hi)
  have hown : ∀ x U, OwnedAt ({ m with alloc := a' }.set o ⟨true, some T'⟩) x U →
      (x = o ∧ U = T') ∨ (x ≠ o ∧ OwnedAt m x U) := by
    intro x U hU
    rcases ownedAt_set.mp hU with ⟨h1, h2⟩ | h
    · cases h2; exact Or.inl ⟨h1, rfl⟩
    · exact Or.inr h
  refine ⟨fun x U hU => ?_, fun x y U V hne hx hy => ?_, fun x U hU i hi => ?_, fun x U hU => ?_⟩
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
  · show a' i = true ∧ i < m.nid
    rcases hown x U hU with ⟨_, rfl⟩ | ⟨hxo, h⟩
    · have hni : i ∉ idsL (es.drop n) := fun h => hdisj i hi i h rfl
      obtain ⟨ha, hlt⟩ := hh.alloc o T hT i (hsub i hi)
      exact ⟨by rw [hf.other hni]; exact ha, hlt⟩
    · have hni : i ∉ idsL (es.drop n) := fun h' =>
        hh.disj o x T U (Ne.symm hxo) hT h i (hdrop i h') hi
      obtain ⟨ha, hlt⟩ := hh.alloc x U h i hi
      exact ⟨by rw [hf.other hni]; exact ha, hlt⟩
  · rcases hown x U hU with ⟨_, rfl⟩ | ⟨_, h⟩
    · exact HT_selfFree (fun e he => List.mem_of_mem_take he) hr (hh.self o T hT)
    · exact hh.self x U h

/-- Two values, each a part of the other, are the same. -/
theorem DSH_sub_antisymm {a b : Val} (h1 : Sub a b) (h2 : Sub b a) : a = b := by
  rcases h1.cases' with h | ⟨e, hc, hs⟩
  · exact h
  · exact (Below.not_self (Sub.of_below_sub ⟨e, hc, hs⟩ h2)).elim

/-- A node at the top of a tree with distinct addresses that lies in the
    hole of a rewrite is the hole itself, and the replacement is at the top
    of the new tree: the rewrite goes down the node's own path (a hole in a
    sibling part would hold a second copy of the node's address `i`) to the
    node, which holds the hole and lies in it. -/
theorem DSH_top_hole {t : Ty} {c d : Nat} {es : List Val} {n' N : Val} {i : Nat} (hi : i ∈ N.ids) :
    ∀ {T T' : Val}, Top N T → Repl (.node t c d es) n' T T' → T.ids.Nodup →
      Sub N (.node t c d es) → N = .node t c d es ∧ Top n' T' := by
  intro T T' htop
  induction htop generalizing T' with
  | refl =>
    intro hr _ hs
    have heq := DSH_sub_antisymm hs hr.sub
    subst heq
    exact ⟨rfl, by rw [hr.here_inv]; exact Top.refl _⟩
  | @fst a b h ih =>
    intro hr hnd hs
    simp only [ids_pair, List.nodup_append] at hnd
    cases hr with
    | fst hr' =>
      obtain ⟨h1, h2⟩ := ih hr' hnd.1 hs
      exact ⟨h1, Top.fst h2⟩
    | snd hr' => exact (hnd.2.2 i (h.sub.ids i hi) i ((hs.trans hr'.sub).ids i hi) rfl).elim
  | @snd a b h ih =>
    intro hr hnd hs
    simp only [ids_pair, List.nodup_append] at hnd
    cases hr with
    | fst hr' => exact (hnd.2.2 i ((hs.trans hr'.sub).ids i hi) i (h.sub.ids i hi) rfl).elim
    | snd hr' =>
      obtain ⟨h1, h2⟩ := ih hr' hnd.2.1 hs
      exact ⟨h1, Top.snd h2⟩
  | inl _ ih =>
    intro hr hnd hs
    cases hr with
    | inl hr' =>
      obtain ⟨h1, h2⟩ := ih hr' (by simpa using hnd) hs
      exact ⟨h1, Top.inl h2⟩
  | inr _ ih =>
    intro hr hnd hs
    cases hr with
    | inr hr' =>
      obtain ⟨h1, h2⟩ := ih hr' (by simpa using hnd) hs
      exact ⟨h1, Top.inr h2⟩
  | pkg _ ih =>
    intro hr hnd hs
    cases hr with
    | pkg hr' =>
      obtain ⟨h1, h2⟩ := ih hr' (by simpa using hnd) hs
      exact ⟨h1, Top.pkg h2⟩

/-- A rewrite keeps a tree well-formed at its type when the replacement is
    well-formed at every type the hole is. -/
theorem DSH_repl_wf {n n' : Val} (hn : ∀ σ, WFv σ n → WFv σ n') {T T' : Val} (hr : Repl n n' T T') :
    ∀ {τ : Ty}, WFv τ T → WFv τ T' := by
  induction hr with
  | here => exact fun h => hn _ h
  | @elem t c d pre post e e' _ ih =>
    intro τ h
    cases h with
    | node hes =>
      refine WFv.node fun x hx => ?_
      rcases List.mem_append.mp hx with hx | hx
      · exact hes x (List.mem_append_left _ hx)
      · rcases List.mem_cons.mp hx with rfl | hx
        · exact ih (hes e (List.mem_append_right _ (List.mem_cons_self ..)))
        · exact hes x (List.mem_append_right _ (List.mem_cons_of_mem _ hx))
  | fst _ ih => intro τ h; cases h with | pair ha hb => exact WFv.pair (ih ha) hb
  | snd _ ih => intro τ h; cases h with | pair ha hb => exact WFv.pair ha (ih hb)
  | inl _ ih => intro τ h; cases h with | inl ha => exact WFv.inl (ih ha)
  | inr _ ih => intro τ h; cases h with | inr ha => exact WFv.inr (ih ha)
  | pkg _ ih => intro τ h; cases h with | pkg ha => exact WFv.pkg (ih ha)

/-- A view stored in the new tree is stored in the old one, when the
    replacement stores it at no type the hole is well-formed at. -/
theorem DSH_viewIn {n n' : Val} {s : Ty} {v : Val} (hn : ∀ σ, WFv σ n → ¬ ViewIn σ n' s v)
    {T T' : Val} (hr : Repl n n' T T') : ∀ {τ : Ty}, WFv τ T → ViewIn τ T' s v → ViewIn τ T s v := by
  induction hr with
  | here => exact fun hw hv => (hn _ hw hv).elim
  | @elem t c d pre post e e' _ ih =>
    intro τ hw hv
    cases hw with
    | node hes =>
      cases hv with
      | child hx hv' =>
        rcases List.mem_append.mp hx with hx | hx
        · exact ViewIn.child (List.mem_append_left _ hx) hv'
        · rcases List.mem_cons.mp hx with rfl | hx
          · exact ViewIn.child (List.mem_append_right _ (List.mem_cons_self ..))
              (ih (hes e (List.mem_append_right _ (List.mem_cons_self ..))) hv')
          · exact ViewIn.child (List.mem_append_right _ (List.mem_cons_of_mem _ hx)) hv'
  | fst _ ih =>
    intro τ hw hv
    cases hw with
    | pair ha _ =>
      cases hv with
      | fst hv' => exact ViewIn.fst (ih ha hv')
      | snd hv' => exact ViewIn.snd hv'
  | snd _ ih =>
    intro τ hw hv
    cases hw with
    | pair _ hb =>
      cases hv with
      | fst hv' => exact ViewIn.fst hv'
      | snd hv' => exact ViewIn.snd (ih hb hv')
  | inl _ ih =>
    intro τ hw hv
    cases hw with
    | inl ha => cases hv with | inl hv' => exact ViewIn.inl (ih ha hv')
  | inr _ ih =>
    intro τ hw hv
    cases hw with
    | inr ha => cases hv with | inr hv' => exact ViewIn.inr (ih ha hv')
  | pkg _ ih =>
    intro τ hw hv
    cases hw with
    | pkg ha => cases hv with | pkg hv' => exact ViewIn.pkg (ih ha hv')

/-- A replacement that captures nothing by name adds nothing to what the
    tree captures by name (`Repl.names_split`). -/
theorem DSH_namesIn {n n' T T' : Val} (hr : Repl n n' T T') (hn' : n'.names = []) {H : List Dep}
    (h : NamesIn T H) : NamesIn T' H := by
  obtain ⟨A, B, h1, h2⟩ := hr.names_split
  intro c hc
  apply h c
  rw [h2, hn'] at hc
  rw [h1]
  simp only [List.append_nil, List.mem_append] at hc ⊢
  rcases hc with hc | hc
  · exact Or.inl (Or.inl hc)
  · exact Or.inr hc

/-- A borrow of a node at the top of `o`'s tree (`⟨o, .self⟩`) stays valid:
    the borrowed node is the rewritten one (now `n'`, which holds no view),
    holds it (it keeps its cell and type, and holds fewer views), or is apart
    from it. Distinct addresses (`hnd`) make the hole the only occurrence. -/
theorem deep_self_hkeep {m m' : Mem} {o : Var} {T T' : Val} {t : Ty} {c d d' : Nat}
    {es es' : List Val} (hT : m.st o = some ⟨true, some T⟩) (hT' : m'.st o = some ⟨true, some T'⟩)
    (hnd : T.ids.Nodup) (hr : Repl (.node t c d es) (.node t c d' es') T T')
    (hw' : WFv (.vec t) (.node t c d' es')) (hhv : t.holdsView = false) : HKeep m m' ⟨o, .self⟩ := by
  intro c2 t2 H hH ⟨n0, d2, es2, hrn, hla, hw, hv, hnm⟩
  have htop := rootNode_own hT hrn
  have hN : Val.node t2 c2 d2 es2 = n0 := by
    rcases hla with ⟨_, h⟩ | ⟨h, _⟩ | ⟨h, _⟩
    · exact h
    · cases h
    · cases h
  subst hN
  -- the rewritten node itself: now `n'`, where the hole was, holding no view
  have hself : Top (.node t c d' es') T' → HrefAt m' ⟨o, .self⟩ c t H := fun ht' =>
    ⟨_, d', es', Or.inl ⟨T', hT', ht'⟩, Or.inl ⟨rfl, rfl⟩, hw', no_views hhv _ _ _, no_names hw' hhv _⟩
  rcases hr.top htop with hs | ⟨N', ht', rfl | hr'⟩
  · -- inside the hole: the hole itself, its addresses being distinct
    obtain ⟨heq, ht'⟩ := DSH_top_hole (i := c2) (by simp) htop hr hnd hs
    cases heq
    exact hself ht'
  · -- apart from the hole: unchanged, its views valid as before
    exact ⟨_, d2, es2, Or.inl ⟨T', hT', ht'⟩, Or.inl ⟨rfl, rfl⟩, hw, hv.keep hH, hnm⟩
  · rcases hr'.node_shape with ⟨heq, rfl⟩ | ⟨es2', rfl⟩
    · cases heq
      exact hself ht'
    · -- holding the hole: same type and cell, the hole's views gone
      refine ⟨_, d2, es2', Or.inl ⟨T', hT', ht'⟩, Or.inl ⟨rfl, rfl⟩, ?_, ?_, ?_⟩
      · exact DSH_repl_wf (fun σ h => by cases h; exact hw') hr' hw
      · intro s v hin
        have hin0 := DSH_viewIn (fun σ h hin' => by
          cases h
          have := hin'.holdsView
          simp [Ty.holdsView, hhv] at this) hr' hw hin
        obtain ⟨d0, o0, l0, rfl, dep, hd, ha⟩ := hv s v hin0
        exact ⟨d0, o0, l0, rfl, dep, hd, hH dep hd _ _ _ _ ha⟩
      · exact DSH_namesIn hr' (hw'.names_nil (by simpa [Ty.holdsView] using hhv)) hnm

/-- A hole strictly inside a tree is rewritten strictly inside it: the
    rewrite is not at the top (`Below.not_self`), so it is in a part. -/
theorem EHA_repl_below {n n' T T' : Val} (hr : Repl n n' T T') (hb : Below n T) : Below n' T' := by
  cases hr with
  | here => exact (Below.not_self hb).elim
  | elem hr' => exact ⟨_, Child.elem (List.mem_append_right _ (List.mem_cons_self ..)), hr'.sub'⟩
  | fst hr' => exact ⟨_, Child.fst, hr'.sub'⟩
  | snd hr' => exact ⟨_, Child.snd, hr'.sub'⟩
  | inl hr' => exact ⟨_, Child.inl, hr'.sub'⟩
  | inr hr' => exact ⟨_, Child.inr, hr'.sub'⟩
  | pkg hr' => exact ⟨_, Child.pkg, hr'.sub'⟩

/-- A hole at the top of a tree whose addresses are distinct is rewritten
    at the top of the new one: a hole that holds an address (`hi`) occurs
    once, so the rewrite follows the same fields and payloads. -/
theorem EHA_top_hole {n n' T T' : Val} (ht : Top n T) (hr : Repl n n' T T') (hnd : T.ids.Nodup)
    {i : Nat} (hi : i ∈ n.ids) : Top n' T' := by
  induction ht generalizing T' with
  | refl => rw [hr.here_inv]; exact Top.refl _
  | @fst a b h ih =>
    cases hr with
    | here => exact (Below.not_self ⟨a, Child.fst, h.sub⟩).elim
    | fst hr' =>
      simp only [ids_pair, List.nodup_append] at hnd
      exact Top.fst (ih hr' hnd.1)
    | snd hr' =>
      simp only [ids_pair, List.nodup_append] at hnd
      exact (hnd.2.2 i (h.sub.ids i hi) i (hr'.sub.ids i hi) rfl).elim
  | @snd a b h ih =>
    cases hr with
    | here => exact (Below.not_self ⟨b, Child.snd, h.sub⟩).elim
    | fst hr' =>
      simp only [ids_pair, List.nodup_append] at hnd
      exact (hnd.2.2 i (hr'.sub.ids i hi) i (h.sub.ids i hi) rfl).elim
    | snd hr' =>
      simp only [ids_pair, List.nodup_append] at hnd
      exact Top.snd (ih hr' hnd.2.1)
  | @inl a h ih =>
    cases hr with
    | here => exact (Below.not_self ⟨a, Child.inl, h.sub⟩).elim
    | inl hr' => exact Top.inl (ih hr' (by simpa using hnd))
  | @inr a h ih =>
    cases hr with
    | here => exact (Below.not_self ⟨a, Child.inr, h.sub⟩).elim
    | inr hr' => exact Top.inr (ih hr' (by simpa using hnd))
  | @pkg a fs te ms cs h ih =>
    cases hr with
    | here => exact (Below.not_self ⟨a, Child.pkg, h.sub⟩).elim
    | pkg hr' => exact Top.pkg (ih hr' (by simpa using hnd))

/-- A hole strictly inside a node `n0` at the top of a tree whose addresses
    are distinct is rewritten strictly inside `n0`'s counterpart, at the top
    of the new tree: the rewrite cannot go past `n0` into another field, where
    the hole would occur a second time. -/
theorem EHA_below_hole {n n' n0 T T' : Val} (ht : Top n0 T) (hb : Below n n0) (hr : Repl n n' T T')
    (hnd : T.ids.Nodup) {i : Nat} (hi : i ∈ n.ids) : ∃ n0', Top n0' T' ∧ Below n' n0' := by
  induction ht generalizing T' with
  | refl => exact ⟨T', Top.refl _, EHA_repl_below hr hb⟩
  | @fst a b h ih =>
    cases hr with
    | here => exact (Below.not_self (Sub.of_below_sub hb (Sub.fst h.sub))).elim
    | fst hr' =>
      simp only [ids_pair, List.nodup_append] at hnd
      obtain ⟨n0', h1, h2⟩ := ih hr' hnd.1
      exact ⟨n0', Top.fst h1, h2⟩
    | snd hr' =>
      simp only [ids_pair, List.nodup_append] at hnd
      exact (hnd.2.2 i ((hb.sub.trans h.sub).ids i hi) i (hr'.sub.ids i hi) rfl).elim
  | @snd a b h ih =>
    cases hr with
    | here => exact (Below.not_self (Sub.of_below_sub hb (Sub.snd h.sub))).elim
    | fst hr' =>
      simp only [ids_pair, List.nodup_append] at hnd
      exact (hnd.2.2 i (hr'.sub.ids i hi) i ((hb.sub.trans h.sub).ids i hi) rfl).elim
    | snd hr' =>
      simp only [ids_pair, List.nodup_append] at hnd
      obtain ⟨n0', h1, h2⟩ := ih hr' hnd.2.1
      exact ⟨n0', Top.snd h1, h2⟩
  | @inl a h ih =>
    cases hr with
    | here => exact (Below.not_self (Sub.of_below_sub hb (Sub.inl h.sub))).elim
    | inl hr' =>
      obtain ⟨n0', h1, h2⟩ := ih hr' (by simpa using hnd)
      exact ⟨n0', Top.inl h1, h2⟩
  | @inr a h ih =>
    cases hr with
    | here => exact (Below.not_self (Sub.of_below_sub hb (Sub.inr h.sub))).elim
    | inr hr' =>
      obtain ⟨n0', h1, h2⟩ := ih hr' (by simpa using hnd)
      exact ⟨n0', Top.inr h1, h2⟩
  | @pkg a fs te ms cs h ih =>
    cases hr with
    | here => exact (Below.not_self (Sub.of_below_sub hb (Sub.pkg h.sub))).elim
    | pkg hr' =>
      obtain ⟨n0', h1, h2⟩ := ih hr' (by simpa using hnd)
      exact ⟨n0', Top.pkg h1, h2⟩

/-- Where the change lands: a borrow that reached the node in `o`'s tree
    through a dependency of kind `k` (`Lands`, from a node at the top of the
    tree) reaches the rewritten one at the same cell. -/
theorem editB_hrefAt {m' : Mem} {o : Var} {T T' n0 : Val} {t : Ty} {c d d' : Nat}
    {es es' : List Val} {k : Kind} {H : List Dep} (hT' : m'.st o = some ⟨true, some T'⟩)
    (hnd : T.ids.Nodup) (htop : Top n0 T) (hla : Lands k (.node t c d es) n0)
    (hr : Repl (.node t c d es) (.node t c d' es') T T') (hw' : WFv (.vec t) (.node t c d' es'))
    (hhv : t.holdsView = false) : HrefAt m' ⟨o, k⟩ c t H := by
  -- the new node holds no view and captures nothing by name
  have hV : ViewsOK m' (.vec t) (.node t c d' es') H := no_views hhv m' _ H
  have hN : NamesIn (.node t c d' es') H := no_names hw' hhv H
  have hc : c ∈ (Val.node t c d es).ids := by simp
  rcases hla with ⟨rfl, hn⟩ | ⟨rfl, hn⟩ | ⟨rfl, hb⟩
  · -- the borrowed node is at the top: so is the new one
    subst hn
    exact ⟨.node t c d' es', d', es', Or.inl ⟨T', hT', EHA_top_hole htop hr hnd hc⟩,
      Or.inl ⟨rfl, rfl⟩, hw', hV, hN⟩
  · subst hn
    exact ⟨.node t c d' es', d', es', Or.inl ⟨T', hT', EHA_top_hole htop hr hnd hc⟩,
      Or.inr (Or.inl ⟨rfl, rfl⟩), hw', hV, hN⟩
  · -- strictly inside a node at the top: strictly inside its counterpart
    obtain ⟨n0', ht', hb'⟩ := EHA_below_hole htop hb hr hnd hc
    exact ⟨n0', d', es', Or.inl ⟨T', hT', ht'⟩, Or.inr (Or.inr ⟨rfl, hb'⟩), hw', hV, hN⟩

/-- `Repl` keeps a tree well-formed, when the replacement is well-formed at
    every type the hole is. -/
theorem NSE_wf {n n' T T' : Val} (hr : Repl n n' T T') :
    ∀ {τ : Ty}, WFv τ T → (∀ τ0, WFv τ0 n → WFv τ0 n') → WFv τ T' := by
  induction hr with
  | here => intro τ hw h; exact h τ hw
  | @elem t c d pre post e e' _ ih =>
    intro τ hw h
    cases hw with
    | node hes =>
      refine WFv.node fun x hx => ?_
      rcases List.mem_append.mp hx with hx | hx
      · exact hes x (List.mem_append_left _ hx)
      · rcases List.mem_cons.mp hx with rfl | hx
        · exact ih (hes e (List.mem_append_right _ (List.mem_cons_self ..))) h
        · exact hes x (List.mem_append_right _ (List.mem_cons_of_mem _ hx))
  | fst _ ih => intro τ hw h; cases hw with | pair ha hb => exact WFv.pair (ih ha h) hb
  | snd _ ih => intro τ hw h; cases hw with | pair ha hb => exact WFv.pair ha (ih hb h)
  | inl _ ih => intro τ hw h; cases hw with | inl ha => exact WFv.inl (ih ha h)
  | inr _ ih => intro τ hw h; cases hw with | inr ha => exact WFv.inr (ih ha h)
  | pkg _ ih => intro τ hw h; cases hw with | pkg ha => exact WFv.pkg (ih ha h)

/-- A view the rewritten tree stores is one the old tree stored, when the
    replacement stores none at the hole's type. -/
theorem NSE_viewIn {n n' T T' : Val} (hr : Repl n n' T T') :
    ∀ {τ s : Ty} {v : Val}, WFv τ T → (∀ τ0, WFv τ0 n → ∀ s v, ¬ ViewIn τ0 n' s v) →
      ViewIn τ T' s v → ViewIn τ T s v := by
  induction hr with
  | here => intro τ s v hw h hin; exact absurd hin (h τ hw s v)
  | @elem t c d pre post e e' _ ih =>
    intro τ s v hw h hin
    cases hw with
    | node hes =>
      cases hin with
      | child hx hin' =>
        rcases List.mem_append.mp hx with hx | hx
        · exact ViewIn.child (List.mem_append_left _ hx) hin'
        · rcases List.mem_cons.mp hx with rfl | hx
          · exact ViewIn.child (List.mem_append_right _ (List.mem_cons_self ..))
              (ih (hes e (List.mem_append_right _ (List.mem_cons_self ..))) h hin')
          · exact ViewIn.child (List.mem_append_right _ (List.mem_cons_of_mem _ hx)) hin'
  | fst _ ih =>
    intro τ s v hw h hin
    cases hw with
    | pair ha hb =>
      cases hin with
      | fst hin' => exact ViewIn.fst (ih ha h hin')
      | snd hin' => exact ViewIn.snd hin'
  | snd _ ih =>
    intro τ s v hw h hin
    cases hw with
    | pair ha hb =>
      cases hin with
      | fst hin' => exact ViewIn.fst hin'
      | snd hin' => exact ViewIn.snd (ih hb h hin')
  | inl _ ih =>
    intro τ s v hw h hin
    cases hw with
    | inl ha => cases hin with | inl hin' => exact ViewIn.inl (ih ha h hin')
  | inr _ ih =>
    intro τ s v hw h hin
    cases hw with
    | inr ha => cases hin with | inr hin' => exact ViewIn.inr (ih ha h hin')
  | pkg _ ih =>
    intro τ s v hw h hin
    cases hw with
    | pkg ha => cases hin with | pkg hin' => exact ViewIn.pkg (ih ha h hin')

/-- A part of the rewritten tree lies in the replacement, or is a part of
    the old tree, or is the counterpart of a part of the old tree with the
    hole rewritten in it (an ancestor of the hole). -/
theorem NSE_sub {n n' T T' : Val} (hr : Repl n n' T T') :
    ∀ {P : Val}, Sub P T' → Sub P n' ∨ Sub P T ∨ ∃ P0, Sub P0 T ∧ Repl n n' P0 P := by
  induction hr with
  | here => intro P hs; exact Or.inl hs
  | @elem t c d pre post e e' hr' ih =>
    intro P hs
    rcases hs.cases' with rfl | ⟨x, hc, hsx⟩
    · exact Or.inr (Or.inr ⟨_, Sub.refl _, Repl.elem hr'⟩)
    · cases hc with
      | elem hx =>
        rcases List.mem_append.mp hx with hx | hx
        · exact Or.inr (Or.inl (Sub.child (List.mem_append_left _ hx) hsx))
        · rcases List.mem_cons.mp hx with rfl | hx
          · have hme : e ∈ pre ++ e :: post := List.mem_append_right _ (List.mem_cons_self ..)
            rcases ih hsx with h | h | ⟨P0, h0, h1⟩
            · exact Or.inl h
            · exact Or.inr (Or.inl (Sub.child hme h))
            · exact Or.inr (Or.inr ⟨P0, Sub.child hme h0, h1⟩)
          · exact Or.inr (Or.inl (Sub.child (List.mem_append_right _ (List.mem_cons_of_mem _ hx)) hsx))
  | fst hr' ih =>
    intro P hs
    rcases hs.cases' with rfl | ⟨x, hc, hsx⟩
    · exact Or.inr (Or.inr ⟨_, Sub.refl _, Repl.fst hr'⟩)
    · cases hc with
      | fst =>
        rcases ih hsx with h | h | ⟨P0, h0, h1⟩
        · exact Or.inl h
        · exact Or.inr (Or.inl (Sub.fst h))
        · exact Or.inr (Or.inr ⟨P0, Sub.fst h0, h1⟩)
      | snd => exact Or.inr (Or.inl (Sub.snd hsx))
  | snd hr' ih =>
    intro P hs
    rcases hs.cases' with rfl | ⟨x, hc, hsx⟩
    · exact Or.inr (Or.inr ⟨_, Sub.refl _, Repl.snd hr'⟩)
    · cases hc with
      | fst => exact Or.inr (Or.inl (Sub.fst hsx))
      | snd =>
        rcases ih hsx with h | h | ⟨P0, h0, h1⟩
        · exact Or.inl h
        · exact Or.inr (Or.inl (Sub.snd h))
        · exact Or.inr (Or.inr ⟨P0, Sub.snd h0, h1⟩)
  | inl hr' ih =>
    intro P hs
    rcases hs.cases' with rfl | ⟨x, hc, hsx⟩
    · exact Or.inr (Or.inr ⟨_, Sub.refl _, Repl.inl hr'⟩)
    · cases hc with
      | inl =>
        rcases ih hsx with h | h | ⟨P0, h0, h1⟩
        · exact Or.inl h
        · exact Or.inr (Or.inl (Sub.inl h))
        · exact Or.inr (Or.inr ⟨P0, Sub.inl h0, h1⟩)
  | inr hr' ih =>
    intro P hs
    rcases hs.cases' with rfl | ⟨x, hc, hsx⟩
    · exact Or.inr (Or.inr ⟨_, Sub.refl _, Repl.inr hr'⟩)
    · cases hc with
      | inr =>
        rcases ih hsx with h | h | ⟨P0, h0, h1⟩
        · exact Or.inl h
        · exact Or.inr (Or.inl (Sub.inr h))
        · exact Or.inr (Or.inr ⟨P0, Sub.inr h0, h1⟩)
  | pkg hr' ih =>
    intro P hs
    rcases hs.cases' with rfl | ⟨x, hc, hsx⟩
    · exact Or.inr (Or.inr ⟨_, Sub.refl _, Repl.pkg hr'⟩)
    · cases hc with
      | pkg =>
        rcases ih hsx with h | h | ⟨P0, h0, h1⟩
        · exact Or.inl h
        · exact Or.inr (Or.inl (Sub.pkg h))
        · exact Or.inr (Or.inr ⟨P0, Sub.pkg h0, h1⟩)

/-- A package lies only in a value of a type that holds views. -/
theorem NSE_pkg_hv {τ : Ty} {v : Val} (hw : WFv τ v) {fs : List Nat} {te : Ty} {ms : List Nat}
    {e : Val} {cs : List (Var × PMode × Ty)} (hs : Sub (.pkg fs te ms e cs) v) :
    τ.holdsView = true := by
  induction hw with
  | int => cases hs
  | view => cases hs
  | node hes ih =>
    rcases hs.cases' with h | ⟨x, hc, hsx⟩
    · cases h
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

/-- The owner's new slot, when the change lands in its tree by `.drop`: the
    tree is well-formed at its type (`Repl` keeps the hole's type), its views
    are valid (the rewritten node holds none; every other view points out of
    the tree, `SelfFree`, into memory no slot but `o`'s changed:
    `keep_notx`), what it captures by name are as before or fewer
    (`Repl.names_split`), so are its packages, and an armed owner's views
    stay valid. -/
theorem NewSlot.edit {m1 m' : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F) {o : Var} {Eo : Entry} (ho : Γ1 o = some Eo) (hoF : o ∉ F)
    (hmo : Eo.mode = .own) {T T' : Val} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hT : m1.st o = some ⟨true, some T⟩) (hT' : m'.st o = some ⟨true, some T'⟩)
    (hst : ∀ v, v ≠ o → m'.st v = m1.st v) (hhv : t.holdsView = false)
    (hr : Repl (.node t c d es) (.node t c d' es') T T') (hw' : WFv (.vec t) (.node t c d' es')) :
    NewSlot m' (A2.kill .drop false o Γ1) o Eo (some (killE .drop false o Eo)) := by
  have hos : Eo.mode.ownSlot = true := by rw [hmo]; rfl
  obtain ⟨sl0, hsl0, hok0, hs0⟩ := hi.slot o Eo ho
  rw [hT] at hsl0; cases hsl0
  obtain ⟨_, hown0, _⟩ := hs0
  obtain ⟨howning, hwf0, hlv0⟩ := hown0 hos
  have hwT : WFv Eo.ty T := hwf0 T rfl
  have hnint : Eo.ty ≠ .int := fun h => by rw [h] at howning; cases howning
  have hsf : SelfFree T := hi.heap.self o T hT
  have hvd : Eo.vdeps = Eo.held := by simp [Entry.vdeps, hos]
  -- the rewritten tree: well-formed, and its views are the old tree's
  have hwT' : WFv Eo.ty T' := NSE_wf hr hwT (fun τ0 h0 => by cases h0; exact hw')
  have hvin : ∀ s v, ViewIn Eo.ty T' s v → ViewIn Eo.ty T s v := fun s v hin =>
    NSE_viewIn hr hwT (fun τ0 h0 s v hin => by
      cases h0
      have := hin.holdsView
      simp [Ty.holdsView, hhv] at this) hin
  have hn' : (Val.node t c d' es').names = [] := hw'.names_nil (by simpa [Ty.holdsView] using hhv)
  -- a view valid through a bound root other than `o` stays valid (`keep_notx`)
  have hkeep : (∀ dep ∈ Eo.held, dep.kind.isName = false →
      ∃ Er, Γ1 dep.root = some Er ∧ Er.mode.isRoot = true) →
      ∀ dep ∈ Eo.held, dep.root ≠ o → VKeep m1 m' dep := by
    intro h dep hd hne
    obtain ⟨r, k⟩ := dep
    cases k with
    | name b t0 => exact vkeep_name _ _ _ _ _
    | self => exact (keep_notx hi hanch hoF hst (h _ hd rfl) hne).1
    | inner => exact (keep_notx hi hanch hoF hst (h _ hd rfl) hne).1
    | view => exact (keep_notx hi hanch hoF hst (h _ hd rfl) hne).1
  -- ... and none is valid through `o` (`SelfFree`, `ViewsOK.keep_except`)
  have hviews : ViewsOK m1 Eo.ty T Eo.held → (∀ dep ∈ Eo.held, dep.kind.isName = false →
      ∃ Er, Γ1 dep.root = some Er ∧ Er.mode.isRoot = true) → ViewsOK m' Eo.ty T' Eo.held :=
    fun hv h => ViewsOK.keep_except hT hsf hvin (hkeep h) hv
  have hlive : (killE .drop false o Eo).live = true → Eo.live = true := fun h => by
    rw [killE_live] at h; simp only [Bool.and_eq_true] at h; exact h.1
  refine ⟨⟨true, some T'⟩, hT', by rw [killE_ty]; exact hok0,
    ⟨by rw [killE_mode, hmo]; rfl, fun _ => ⟨by rw [killE_ty]; exact howning,
      fun U hU => by cases hU; rw [killE_ty]; exact hwT', fun hl' => ⟨T', rfl, ?_⟩⟩,
      fun h => by rw [killE_mode, hmo] at h; cases h⟩,
    killE_mode .., fun hl' _ r hr' => ?_, killE_ty .., fun hl' _ => ?_, fun hl' U hU => ?_,
    fun U hU => ?_, fun hdb _ _ dd hdd hnm => ?_,
    fun h => by rw [killE_dtor] at h; rw [killE_dbind]; exact hi.wf.arm o Eo ho h,
    fun h => by rw [killE_dbind] at h; rw [killE_ty]; exact hi.wf.view o Eo ho h, ?_⟩
  · -- the views of the live owner
    have hl := hlive hl'
    obtain ⟨T1, hT1, hv1⟩ := hlv0 hl
    cases hT1
    rw [killE_ty, killE_held]
    exact hviews hv1 fun dep hd _ => wf_held hi ho hl hnint dep.root (List.mem_map_of_mem hd)
  · -- its roots are bound
    rw [killE_vdeps] at hr'
    obtain ⟨Er, hEr, hro⟩ := hi.wf o Eo ho (hlive hl') (Or.inl hnint) r hr'
    by_cases hrx : r = o
    · exact Or.inl ⟨hrx, by rw [killE_mode, hmo]; rfl⟩
    · exact Or.inr ⟨hrx, kill_root hEr hro⟩
  · -- what it holds by name: not itself, which would then hold nothing
    have hl := hlive hl'
    have hN := hi.names o Eo ho hl (Or.inl hnint)
    intro dd hdd b t0 hk
    rw [killE_vdeps] at hdd
    obtain ⟨Er, hEr, hlr, hhr, htr, hor, hcr⟩ := hN dd hdd b t0 hk
    by_cases hro : dd.root = o
    · rw [hro, ho] at hEr; cases hEr
      rw [hvd, hhr] at hdd; cases hdd
    · exact ⟨Er, by rw [upd_ne _ _ hro]; simp [A2.kill, hEr, killE_nil (root_vdeps hor hhr)],
        hlr, hhr, htr, hor, hcr⟩
  · -- what the new tree captures by name, the old one did (`Repl.names_split`)
    cases hU
    have hN0 := hi.held o Eo ⟨true, some T⟩ T ho (hlive hl') hT rfl
    obtain ⟨A, B, h1, h2⟩ := hr.names_split
    rw [killE_held]
    intro cc hcc
    rw [h2, hn'] at hcc
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
    · have := NSE_pkg_hv hw' h
      simp [Ty.holdsView, hhv] at this
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
  · -- an armed owner's views are bound
    rw [killE_dbind] at hdb; rw [killE_vdeps] at hdd
    obtain ⟨Er, hEr, hro⟩ := hi.wf.dtor o Eo ho hdb hos (Or.inl hnint) dd hdd hnm
    by_cases hrx : dd.root = o
    · exact Or.inl ⟨hrx, by rw [killE_mode, hmo]; rfl⟩
    · exact Or.inr ⟨hrx, kill_root hEr hro⟩
  · -- ... and stay valid, live or not
    intro hdb _ U hU
    cases hU
    rw [killE_dbind] at hdb
    obtain ⟨hdt, hv⟩ := hi.armed o Eo ⟨true, some T⟩ ho hT hdb hos T rfl
    refine ⟨by rw [killE_dtor]; exact hdt, ?_⟩
    rw [killE_ty, killE_held]
    exact hviews hv fun dep hd hnm =>
      hi.wf.dtor o Eo ho hdb hos (Or.inl hnint) dep (by rw [hvd]; exact hd) hnm

/-! ### The owner's change -/

/-- The owner's change by `.drop`: one node of its tree rewritten in place
    (`MInv.change`, with `NewSlot.edit` and `deep_self_hkeep`; a `.drop`
    spares only borrows of the root's handle, when its elements hold no
    views, and what holds it by name). -/
theorem MInv.edit_drop {m1 m' : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F) {o : Var} {Eo : Entry} (ho : Γ1 o = some Eo) (hoF : o ∉ F)
    (hcan : canDo Eo.mode .drop) (hds : DtorSafe Γ1 .drop false o)
    {T T' : Val} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hT : m1.st o = some ⟨true, some T⟩) (hT' : m'.st o = some ⟨true, some T'⟩)
    (hst : ∀ v, v ≠ o → m'.st v = m1.st v) (hheap : HeapOK m') (hnv : m'.nv = m1.nv)
    (hhv : t.holdsView = false) (hr : Repl (.node t c d es) (.node t c d' es') T T')
    (hw' : WFv (.vec t) (.node t c d' es')) : MInv m' (A2.kill .drop false o Γ1) := by
  have hmo : Eo.mode = .own := by
    rcases hcan with h | ⟨b, h, _⟩
    · exact h
    · exact absurd h (hi.noInout o Eo b ho)
  have hkeep : ∀ k, Eff.kills .drop false k = false → VKeep m1 m' ⟨o, k⟩ ∧ HKeep m1 m' ⟨o, k⟩ := by
    intro k hk
    cases k with
    | self =>
      refine ⟨?_, deep_self_hkeep hT hT' (hi.heap.nodup o T hT) hr hw' hhv⟩
      intro _ _ _ _ hva
      obtain ⟨_, _, _, _, hk', _⟩ := hva
      rcases hk' with ⟨h, _⟩ | ⟨h, _⟩ <;> cases h
    | inner => simp [Eff.kills] at hk
    | view => simp [Eff.kills] at hk
    | name b t => exact ⟨vkeep_name _ _ _ _ _, hkeep_name _ _ _ _ _⟩
  have hnew : Eff.drop ≠ .replace → ∀ Ex', some (killE .drop false o Eo) = some Ex' → Eo.live = true →
      Eo.held = [] → Eo.ty.holdsView = false → Ex'.live = true ∧ Ex'.held = [] := by
    intro _ Ex' hx' hl0 hh0 _
    simp only [Option.some.injEq] at hx'; subst hx'
    rw [killE_nil (root_vdeps (by rw [hmo]; rfl) hh0)]; exact ⟨hl0, hh0⟩
  have h := hi.change hanch ho hoF (hmn_of_ne_replace false (by decide) o) (by rw [hmo]; simp) hst hheap
    hnv hkeep (NewSlot.edit hi hanch ho hoF hmo hT hT' hst hhv hr hw') hds (fun h => by cases h)
    (fun h => by cases h) hnew
  have heq : upd (A2.kill .drop false o Γ1) o (some (killE .drop false o Eo)) = A2.kill .drop false o Γ1 := by
    funext v
    by_cases hv : v = o
    · subst hv; simp [upd, A2.kill, ho]
    · rw [upd_ne _ _ hv]
  rw [heq] at h; exact h

/-- The owner's change by `.realloc`: a push through a copy of the handle of
    a root of the borrow's own type is the root's own push (`push_grow`). -/
theorem MInv.edit_grow {m1 : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F) {o : Var} {Eo : Entry} (ho : Γ1 o = some Eo) (hl : Eo.live = true)
    (hoF : o ∉ F) (hcan : canDo Eo.mode .realloc) (hds : DtorSafe Γ1 .realloc false o)
    {t : Ty} (hty : Eo.ty = .vec t) (hhv : t.holdsView = false)
    {t' : Ty} {c d : Nat} {es : List Val} (hT : m1.st o = some ⟨true, some (.node t' c d es)⟩)
    {v : Val} {D : List Dep} (hp : Pushed m1 Γ1 t v D) {d' : Nat} {A' : Nat → Bool} {N' : Nat}
    (hre : (d' = d ∧ A' = m1.alloc ∧ N' = m1.nid) ∨
      (d' = m1.nid ∧ A' = upd (upd m1.alloc d false) m1.nid true ∧ N' = m1.nid + 1)) :
    MInv ({ m1 with alloc := A', nid := N' }.set o ⟨true, some (.node t' c d' (es ++ [v]))⟩)
      (A2.kill .realloc false o Γ1) := by
  have hmo : Eo.mode = .own := by
    rcases hcan with h | ⟨b, h, _⟩
    · exact h
    · exact absurd h (hi.noInout o Eo b ho)
  have hD : ownHeld true t D = [] := by simp [ownHeld, hhv]
  have h := push_grow hi hanch ho hl hcan hoF hty hT hp.ownHeld (by rw [hD]; simp [roots])
    (fun _ => hD) hre (by rw [hhv]; exact hds) (fun _ => hhv)
  rw [hD, hhv] at h
  have hanch2 : RootbAnch (A2.setE (A2.kill .realloc false o Γ1) o { Eo with held := Eo.held ++ [] }) F :=
    fun p Ep hp hm => by
      by_cases hpo : p = o
      · subst hpo; simp only [A2.setE, upd_same, Option.some.injEq] at hp; subst hp
        rw [hmo] at hm; cases hm
      · simp only [A2.setE, upd_ne _ _ hpo] at hp; exact hanch.kill _ _ _ p Ep hp hm
  have h2 := h.kill_more hanch2 hoF (by decide : Eff.realloc ≠ .replace) false
  have heq : A2.kill .realloc false o (A2.setE (A2.kill .realloc false o Γ1) o { Eo with held := Eo.held ++ [] }) =
      A2.kill .realloc false o Γ1 := by
    funext w
    by_cases hw : w = o
    · subst hw; simp [A2.setE, A2.kill, ho]
    · simp only [A2.kill, A2.setE, upd_ne _ _ hw, Option.map_map, Function.comp_def, killE_idem]
  rw [heq] at h2; exact h2

/-! ### The steps -/

/-- `editPush`: a value moves in at the end of the node, its buffer kept. -/
theorem MInv.editB_push {m1 : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F) {x y : Var} {Ex : Entry} {t : Ty} (hx : Γ1 x = some Ex)
    (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t) (hhv : t.holdsView = false)
    (_hxF : x ∉ F) (_hyx : y ≠ x) (hthru : ThruOK Γ1 F (.push y) Ex.ty Ex.path)
    {v : Val} {D : List Dep} (hp : Pushed m1 Γ1 t v D)
    {o : Var} {T T' : Val} {t' : Ty} {c d : Nat} {es : List Val}
    (hno : NodeOf m1 x o T t' c d es)
    (hr : Repl (.node t' c d es) (.node t' c d (es ++ [v])) T T') :
    MInv (m1.set o ⟨true, some T'⟩) (A2.setE (killThru (.push y) Ex.ty Ex.path Γ1) x Ex) := by
  have hro : ∀ d ∈ memDeps Ex.path, ∃ Er, Γ1 d.root = some Er ∧ Er.mode.ownSlot = true :=
    fun d hd => by
      obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d hd
      exact ⟨Er, hEr, hcan.ownSlot⟩
  obtain ⟨dep, hdm, T0, n0, c0, d0, es0, hxs, hT0, htop, hla, _, hw0, _, huniq⟩ :=
    hi.thru_owner hx hmx hl hty hro
  obtain ⟨rfl, rfl, ht', rfl, rfl, rfl⟩ := huniq _ _ _ _ _ _ hno
  subst t'
  obtain ⟨hoF, _, Eo, hEo, hlo, hcan, hds⟩ := hthru dep hdm
  have hargE : argE Γ1 dep.root = Eo := by unfold argE; rw [hEo]; rfl
  have hxo : x ≠ dep.root := fun e => by rw [e, hT0] at hxs; cases hxs
  have hst : ∀ w, w ≠ dep.root → (m1.set dep.root ⟨true, some T'⟩).st w = m1.st w :=
    fun w hw => by simp [upd_ne _ _ hw]
  have hT' : (m1.set dep.root ⟨true, some T'⟩).st dep.root = some ⟨true, some T'⟩ := by simp
  have hw' : WFv (.vec t) (.node t c d (es ++ [v])) := by
    cases hw0 with
    | node hes =>
      refine WFv.node fun e he => ?_
      rcases List.mem_append.mp he with h | h
      · exact hes e h
      · simp only [List.mem_singleton] at h; subst h; exact hp.wf
  have hhref := editB_hrefAt (H := Ex.held) hT' (hi.heap.nodup _ _ hT0) htop hla hr hw' hhv
  have hown : MInv (m1.set dep.root ⟨true, some T'⟩)
      (A2.kill ((Edit.push y).effAt dep.kind (decide (Eo.ty = Ex.ty))) false dep.root Γ1) := by
    by_cases hre : (Edit.push y).effAt dep.kind (decide (Eo.ty = Ex.ty)) = .realloc
    · -- through a copy of the owner's handle, of its type: the owner's whole tree
      obtain ⟨_, hk, hs⟩ := Edit.effAt_realloc hre
      have htyo : Eo.ty = .vec t := by rw [of_decide_eq_true hs, hty]
      have hwT : WFv (.vec t) T := by
        obtain ⟨T1, h1, h2, _⟩ := hi.own_val hEo hlo hcan.ownSlot
        rw [hT0] at h1; cases h1; rw [htyo] at h2; exact h2
      obtain ⟨cT, dT, esT, hTe⟩ : ∃ cT dT esT, T = .node t cT dT esT := by
        cases hwT with | node _ => exact ⟨_, _, _, rfl⟩
      have hTn : T = .node t c d es := by
        rcases hla with ⟨_, hnn⟩ | ⟨hkv, _⟩ | ⟨hki, _⟩
        · rw [hnn]; rw [hTe] at htop ⊢; exact htop.node.symm
        · rw [hk] at hkv; cases hkv
        · rw [hk] at hki; cases hki
      subst hTn
      have hT'n : T' = .node t c d (es ++ [v]) := hr.here_inv
      subst hT'n
      rw [hre]; rw [hre] at hcan hds
      exact MInv.edit_grow hi hanch hEo hlo hoF hcan hds htyo hhv hT0 hp (Or.inl ⟨rfl, rfl, rfl⟩)
    · have hdrop : (Edit.push y).effAt dep.kind (decide (Eo.ty = Ex.ty)) = .drop := by
        revert hre; simp only [Edit.effAt]; split <;> simp
      rw [hdrop] at hcan hds ⊢
      have hvv : ∀ d0 o0 l0, ¬ Sub (.view d0 o0 l0) v := fun d0 o0 l0 hs => by
        obtain ⟨s, hin⟩ := hp.wf.sub_view hs
        have := hin.holdsView; rw [hhv] at this; cases this
      have hvT : ∀ d0 o0 l0, Sub (.view d0 o0 l0) T → ∃ o' U, OwnedAt m1 o' U ∧ d0 ∈ U.ids := by
        intro d0 o0 l0 hs
        obtain ⟨T1, h1, hwT, hvsT⟩ := hi.own_val hEo hlo hcan.ownSlot
        rw [hT0] at h1; cases h1
        obtain ⟨s, hin⟩ := hwT.sub_view hs
        obtain ⟨_, _, _, hv1, _, _, ha⟩ := hvsT s _ hin
        cases hv1
        exact ha.owned
      exact MInv.edit_drop hi hanch hEo hoF hcan hds hT0 hT' hst
        (HeapOK.editPush hi.heap hT0 hp.nd hp.al hp.dis hvv hvT (Or.inl ⟨rfl, rfl, rfl⟩) hr) (by simp)
        hhv hr hw'
  exact MInv.editB_rest hi.wf hi.names hanch hx hmx hl hty hthru hdm (by rw [hargE]; exact hown)
    (by rw [hst x hxo]; exact hxs) hhref

/-- `editPushRealloc`: the same, the node's buffer moving to a fresh one. -/
theorem MInv.editB_pushRealloc {m1 : Mem} {Γ1 : Ctx} {F : List Var} (hi : MInv m1 Γ1)
    (hanch : RootbAnch Γ1 F) {x y : Var} {Ex : Entry} {t : Ty} (hx : Γ1 x = some Ex)
    (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t) (hhv : t.holdsView = false)
    (_hxF : x ∉ F) (_hyx : y ≠ x) (hthru : ThruOK Γ1 F (.push y) Ex.ty Ex.path)
    {v : Val} {D : List Dep} (hp : Pushed m1 Γ1 t v D)
    {o : Var} {T T' : Val} {t' : Ty} {c d : Nat} {es : List Val}
    (hno : NodeOf m1 x o T t' c d es)
    (hr : Repl (.node t' c d es) (.node t' c m1.nid (es ++ [v])) T T') :
    MInv ({ m1 with alloc := upd (upd m1.alloc d false) m1.nid true, nid := m1.nid + 1 }.set o
      ⟨true, some T'⟩) (A2.setE (killThru (.push y) Ex.ty Ex.path Γ1) x Ex) := by
  have hro : ∀ d ∈ memDeps Ex.path, ∃ Er, Γ1 d.root = some Er ∧ Er.mode.ownSlot = true :=
    fun d hd => by
      obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d hd
      exact ⟨Er, hEr, hcan.ownSlot⟩
  obtain ⟨dep, hdm, T0, n0, c0, d0, es0, hxs, hT0, htop, hla, _, hw0, _, huniq⟩ :=
    hi.thru_owner hx hmx hl hty hro
  obtain ⟨rfl, rfl, ht', rfl, rfl, rfl⟩ := huniq _ _ _ _ _ _ hno
  subst t'
  obtain ⟨hoF, _, Eo, hEo, hlo, hcan, hds⟩ := hthru dep hdm
  have hargE : argE Γ1 dep.root = Eo := by unfold argE; rw [hEo]; rfl
  have hxo : x ≠ dep.root := fun e => by rw [e, hT0] at hxs; cases hxs
  have hst : ∀ w, w ≠ dep.root →
      ({ m1 with alloc := upd (upd m1.alloc d false) m1.nid true, nid := m1.nid + 1 }.set dep.root ⟨true, some T'⟩).st w = m1.st w :=
    fun w hw => by simp [upd_ne _ _ hw]
  have hT' :
      ({ m1 with alloc := upd (upd m1.alloc d false) m1.nid true, nid := m1.nid + 1 }.set dep.root ⟨true, some T'⟩).st dep.root = some ⟨true, some T'⟩ := by
    simp
  have hw' : WFv (.vec t) (.node t c m1.nid (es ++ [v])) := by
    cases hw0 with
    | node hes =>
      refine WFv.node fun e he => ?_
      rcases List.mem_append.mp he with h | h
      · exact hes e h
      · simp only [List.mem_singleton] at h; subst h; exact hp.wf
  have hhref := editB_hrefAt (H := Ex.held) hT' (hi.heap.nodup _ _ hT0) htop hla hr hw' hhv
  have hown :
      MInv ({ m1 with alloc := upd (upd m1.alloc d false) m1.nid true, nid := m1.nid + 1 }.set dep.root ⟨true, some T'⟩)
        (A2.kill ((Edit.push y).effAt dep.kind (decide (Eo.ty = Ex.ty))) false dep.root Γ1) := by
    by_cases hre : (Edit.push y).effAt dep.kind (decide (Eo.ty = Ex.ty)) = .realloc
    · obtain ⟨_, hk, hs⟩ := Edit.effAt_realloc hre
      have htyo : Eo.ty = .vec t := by rw [of_decide_eq_true hs, hty]
      have hwT : WFv (.vec t) T := by
        obtain ⟨T1, h1, h2, _⟩ := hi.own_val hEo hlo hcan.ownSlot
        rw [hT0] at h1; cases h1; rw [htyo] at h2; exact h2
      obtain ⟨cT, dT, esT, hTe⟩ : ∃ cT dT esT, T = .node t cT dT esT := by
        cases hwT with | node _ => exact ⟨_, _, _, rfl⟩
      have hTn : T = .node t c d es := by
        rcases hla with ⟨_, hnn⟩ | ⟨hkv, _⟩ | ⟨hki, _⟩
        · rw [hnn]; rw [hTe] at htop ⊢; exact htop.node.symm
        · rw [hk] at hkv; cases hkv
        · rw [hk] at hki; cases hki
      subst hTn
      have hT'n : T' = .node t c m1.nid (es ++ [v]) := hr.here_inv
      subst hT'n
      rw [hre]; rw [hre] at hcan hds
      exact MInv.edit_grow hi hanch hEo hlo hoF hcan hds htyo hhv hT0 hp (Or.inr ⟨rfl, rfl, rfl⟩)
    · have hdrop : (Edit.push y).effAt dep.kind (decide (Eo.ty = Ex.ty)) = .drop := by
        revert hre; simp only [Edit.effAt]; split <;> simp
      rw [hdrop] at hcan hds ⊢
      have hvv : ∀ d0 o0 l0, ¬ Sub (.view d0 o0 l0) v := fun d0 o0 l0 hs => by
        obtain ⟨s, hin⟩ := hp.wf.sub_view hs
        have := hin.holdsView; rw [hhv] at this; cases this
      have hvT : ∀ d0 o0 l0, Sub (.view d0 o0 l0) T → ∃ o' U, OwnedAt m1 o' U ∧ d0 ∈ U.ids := by
        intro d0 o0 l0 hs
        obtain ⟨T1, h1, hwT, hvsT⟩ := hi.own_val hEo hlo hcan.ownSlot
        rw [hT0] at h1; cases h1
        obtain ⟨s, hin⟩ := hwT.sub_view hs
        obtain ⟨_, _, _, hv1, _, _, ha⟩ := hvsT s _ hin
        cases hv1
        exact ha.owned
      exact MInv.edit_drop hi hanch hEo hoF hcan hds hT0 hT' hst
        (HeapOK.editPush hi.heap hT0 hp.nd hp.al hp.dis hvv hvT (Or.inr ⟨rfl, rfl, rfl⟩) hr) (by simp)
        hhv hr hw'
  exact MInv.editB_rest hi.wf hi.names hanch hx hmx hl hty hthru hdm (by rw [hargE]; exact hown)
    (by rw [hst x hxo]; exact hxs) hhref

/-- `editTrunc`: the node's elements from the `n`-th on are freed. -/
theorem MInv.editB_trunc {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F) {x : Var} {i : Expr} {Ex : Entry} {t : Ty} (hx : Γ x = some Ex)
    (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t) (hhv : t.holdsView = false)
    (_hxF : x ∉ F) (hthru : ThruOK Γ F (.trunc i) Ex.ty Ex.path)
    {o : Var} {T T' : Val} {t' : Ty} {c d n : Nat} {es : List Val} {a' : Nat → Bool}
    (hno : NodeOf m x o T t' c d es) (hf : FreesL m.alloc (es.drop n) a')
    (hr : Repl (.node t' c d es) (.node t' c d (es.take n)) T T') :
    MInv ({ m with alloc := a' }.set o ⟨true, some T'⟩) (A2.setE (killThru (.trunc i) Ex.ty Ex.path Γ) x Ex) := by
  have hro : ∀ d ∈ memDeps Ex.path, ∃ Er, Γ d.root = some Er ∧ Er.mode.ownSlot = true :=
    fun d hd => by
      obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d hd
      exact ⟨Er, hEr, hcan.ownSlot⟩
  obtain ⟨dep, hdm, T0, n0, c0, d0, es0, hxs, hT0, htop, hla, _, hw0, _, huniq⟩ :=
    hi.thru_owner hx hmx hl hty hro
  obtain ⟨rfl, rfl, ht', rfl, rfl, rfl⟩ := huniq _ _ _ _ _ _ hno
  subst t'
  obtain ⟨hoF, _, Eo, hEo, hlo, hcan, hds⟩ := hthru dep hdm
  have hargE : argE Γ dep.root = Eo := by unfold argE; rw [hEo]; rfl
  have hxo : x ≠ dep.root := fun e => by rw [e, hT0] at hxs; cases hxs
  have hst : ∀ w, w ≠ dep.root → ({ m with alloc := a' }.set dep.root ⟨true, some T'⟩).st w = m.st w :=
    fun w hw => by simp [upd_ne _ _ hw]
  have hT' : ({ m with alloc := a' }.set dep.root ⟨true, some T'⟩).st dep.root = some ⟨true, some T'⟩ := by
    simp
  have hw' : WFv (.vec t) (.node t c d (es.take n)) := by
    cases hw0 with
    | node hes => exact WFv.node fun e he => hes e (List.mem_of_mem_take he)
  have hhref := editB_hrefAt (H := Ex.held) hT' (hi.heap.nodup _ _ hT0) htop hla hr hw' hhv
  have hown : MInv ({ m with alloc := a' }.set dep.root ⟨true, some T'⟩)
      (A2.kill ((Edit.trunc i).effAt dep.kind (decide (Eo.ty = Ex.ty))) false dep.root Γ) := by
    have hdrop : (Edit.trunc i).effAt dep.kind (decide (Eo.ty = Ex.ty)) = .drop := rfl
    rw [hdrop] at hcan hds ⊢
    exact MInv.edit_drop hi hanch hEo hoF hcan hds hT0 hT' hst (HeapOK.editTrunc hi.heap hT0 hf hr)
      (by simp) hhv hr hw'
  exact MInv.editB_rest hi.wf hi.names hanch hx hmx hl hty hthru hdm (by rw [hargE]; exact hown)
    (by rw [hst x hxo]; exact hxs) hhref

end A2
