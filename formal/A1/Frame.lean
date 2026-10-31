import A1.Values

/-! A1 — one binding's slot changes; everything that did not depend on it in
an ending way stays valid. -/

namespace A1

def Ty.size : Ty → Nat
  | .int => 1
  | .vec t => t.size + 1
  | .slice t => t.size + 1

inductive ViewSpine : Ty → Ty → Prop
  | here {s : Ty} : ViewSpine (.slice s) s
  | vec {t s : Ty} : ViewSpine t s → ViewSpine (.vec t) s

inductive NodeSpine : Ty → Ty → Prop
  | here {u : Ty} : NodeSpine (.vec u) u
  | vec {t u : Ty} : NodeSpine t u → NodeSpine (.vec t) u

theorem ViewIn.spine {τ T s v} (h : ViewIn τ T s v) : ViewSpine τ s := by
  induction h with
  | here => exact ViewSpine.here
  | child _ _ ih => exact ViewSpine.vec ih

theorem ViewSpine.size_lt {τ s} (h : ViewSpine τ s) : s.size < τ.size := by
  induction h with
  | here => simp [Ty.size]
  | vec _ ih => simp [Ty.size]; omega

theorem sub_spine {τ : Ty} {T : Val} (hw : WFv τ T) {u : Ty} {c d : Nat} {es : List Val}
    (hs : Sub (.node u c d es) T) : NodeSpine τ u := by
  induction hw generalizing u c d es with
  | int => cases hs
  | view => cases hs
  | node hes ih =>
    rcases hs.cases' with h | ⟨ty, c', d', es', e, heq, he, hs'⟩
    · cases h; exact NodeSpine.here
    · cases heq; exact NodeSpine.vec (ih e he hs')

theorem spine_combine {τ u s : Ty} (hn : NodeSpine τ u) (hv : ViewSpine τ s) : ViewSpine u s := by
  induction hn with
  | here => cases hv with | vec h => exact h
  | vec _ ih => cases hv with | vec h => exact ih h

/-- A view stored in a tree never points into that same tree. -/
theorem view_not_inside {τ : Ty} {T : Val} (hw : WFv τ T) {s : Ty} {v : Val} (hin : ViewIn τ T s v)
    {u : Ty} {c d : Nat} {es : List Val} (hs : Sub (.node u c d es) T)
    (hwn : WFv (.vec s) (.node u c d es)) : False := by
  have hu : u = s := by cases hwn; rfl
  subst hu
  have := (spine_combine (sub_spine hw hs) hin.spine).size_lt
  omega

/-- So a view stored in an owned tree is not valid through that tree's
    owner. -/
theorem viewAt_not_self {m : Mem} {x : Var} {τ : Ty} {T : Val} (hT : m.st x = some ⟨true, some T⟩)
    (hw : WFv τ T) {s : Ty} {v : Val} (hin : ViewIn τ T s v) {k : Kind} {d o l : Nat}
    (ha : ViewAt m ⟨x, k⟩ d o l s) : False := by
  obtain ⟨n0, c, es, hr, hk, _, hwn⟩ := ha
  have := rootNode_own hT hr
  subst this
  have hs : Sub (.node s c d es) n0 := by
    rcases hk with ⟨_, h⟩ | ⟨_, h⟩
    · rw [h]; exact Sub.refl _
    · exact h.sub
  exact view_not_inside hw hin hs hwn

/-- The views stored in an owned tree stay valid when only that tree's owner
    changes, if the others they depend on keep their memory. -/
theorem ViewsOK.keep_except {m m' : Mem} {x : Var} {τ : Ty} {T U : Val}
    (hT : m.st x = some ⟨true, some T⟩) (hw : WFv τ T) {τ' : Ty} {H : List Dep}
    (hsub : ∀ s v, ViewIn τ' U s v → ViewIn τ T s v)
    (hk : ∀ dep ∈ H, dep.root ≠ x → VKeep m m' dep) (hv : ViewsOK m τ T H) :
    ViewsOK m' τ' U H := by
  intro s v hin
  obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := hv s v (hsub s v hin)
  refine ⟨d, o, l, rfl, dep, hd, hk dep hd ?_ d o l s ha⟩
  intro heq
  obtain ⟨r, k⟩ := dep
  simp only at heq; subst heq
  exact viewAt_not_self hT hw (hsub s _ hin) ha

/-! ### The general frame lemma -/

theorem killE_ty (e : Eff) (hv : Bool) (x : Var) (E : Entry) : (killE e hv x E).ty = E.ty := by
  unfold killE; split <;> rfl
theorem killE_mode (e : Eff) (hv : Bool) (x : Var) (E : Entry) : (killE e hv x E).mode = E.mode := by
  unfold killE; split <;> rfl
theorem killE_path (e : Eff) (hv : Bool) (x : Var) (E : Entry) : (killE e hv x E).path = E.path := by
  unfold killE; split <;> rfl
theorem killE_held (e : Eff) (hv : Bool) (x : Var) (E : Entry) : (killE e hv x E).held = E.held := by
  unfold killE; split <;> rfl
theorem killE_vdeps (e : Eff) (hv : Bool) (x : Var) (E : Entry) :
    (killE e hv x E).vdeps = E.vdeps := by
  simp [Entry.vdeps, killE_mode, killE_path, killE_held]
theorem killE_live (e : Eff) (hv : Bool) (x : Var) (E : Entry) :
    (killE e hv x E).live = (E.live && !hits e hv x E) := by
  unfold killE; split <;> simp_all

/-- A live entry after `kill` was not hit: each dependency on `x` is of a
    kind the effect does not end. -/
theorem killE_live_dep {e : Eff} {hv : Bool} {x : Var} {E : Entry}
    (hl : (killE e hv x E).live = true) (hnint : E.ty ≠ .int ∨ E.mode = .rootb) :
    E.live = true ∧ ∀ dep ∈ E.vdeps, dep.root = x → e.kills hv dep.kind = false := by
  rw [killE_live] at hl
  simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hl
  refine ⟨hl.1, fun dep hd hr => ?_⟩
  cases hb : e.kills hv dep.kind with
  | false => rfl
  | true =>
    exfalso
    have : hits e hv x E = true := by
      unfold hits
      simp only [Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, List.any_eq_true,
        beq_iff_eq]
      refine ⟨?_, dep, hd, hr, hb⟩
      rcases hnint with h | h
      · exact Or.inl h
      · exact Or.inr (by rw [h])
    rw [this] at hl; exact absurd hl.2 (by simp)

theorem SlotOK.dead {m m' : Mem} {E : Entry} {sl : Slot} (h : SlotOK m E sl) (hl : E.live = false) :
    SlotOK m' E sl := by
  obtain ⟨ho, hown, hbor⟩ := h
  refine ⟨ho, fun hos => ?_, fun _ hl' => by rw [hl] at hl'; cases hl'⟩
  obtain ⟨h1, h2, _⟩ := hown hos
  exact ⟨h1, h2, fun hl' => by rw [hl] at hl'; cases hl'⟩

theorem SlotOK.keep {m m' : Mem} {E : Entry} {sl : Slot} (h : SlotOK m E sl)
    (hk : ∀ dep ∈ E.vdeps, VKeep m m' dep ∧ HKeep m m' dep) : SlotOK m' E sl := by
  obtain ⟨ho, hown, hbor⟩ := h
  refine ⟨ho, fun hos => ?_, fun hos hl => ?_⟩
  · obtain ⟨h1, h2, h3⟩ := hown hos
    refine ⟨h1, h2, fun hl => ?_⟩
    obtain ⟨T, hT, hv⟩ := h3 hl
    refine ⟨T, hT, hv.keep fun dep hd => (hk dep ?_).1⟩
    simp [Entry.vdeps, hos, hd]
  · obtain ⟨v, hv, hok⟩ := hbor hos hl
    refine ⟨v, hv, hok.keep (fun dep hd => hk dep ?_) (fun dep hd => (hk dep ?_).1)⟩
    · simp [Entry.vdeps, hos, hd]
    · simp [Entry.vdeps, hos, hd]

/-- What the slot of the changed binding holds afterwards, if anything. -/
def NewSlot (m' : Mem) (Γ0 : Ctx) (x : Var) (Ex : Entry) : Option Entry → Prop
  | none => m'.st x = none
  | some Ex' => ∃ sl, m'.st x = some sl ∧ Ex'.ty.ok = true ∧ SlotOK m' Ex' sl ∧
      Ex'.mode = Ex.mode ∧
      (Ex'.live = true → Ex'.ty ≠ .int → ∀ r ∈ roots Ex'.vdeps,
        (r = x ∧ Ex'.mode.isRoot = true) ∨ (r ≠ x ∧ ∃ Er, Γ0 r = some Er ∧ Er.mode.isRoot = true))

theorem killE_rootb {Γ : Ctx} {F : List Var}
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    {x : Var} (hxF : x ∉ F) (e : Eff) (hv : Bool) {v : Var} {E : Entry} (hE : Γ v = some E)
    (hrb : E.mode = .rootb) : killE e hv x E = E := by
  unfold killE
  have : hits e hv x E = false := by
    unfold hits
    simp only [Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true,
      beq_iff_eq, not_and, Bool.not_eq_true]
    refine Or.inr fun dep hd hr => ?_
    exact absurd (hr ▸ hanch v E hE hrb dep.root (List.mem_map_of_mem hd)) hxF
  rw [this]; rfl

/-- One binding `x` changes (effect `e`), its slot becomes `ox`: every other
    binding stays valid, or is ended by `kill`. -/
theorem MInv.change {m m' : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    {x : Var} {Ex : Entry} (hx : Γ x = some Ex) (hxF : x ∉ F) (hxr : Ex.mode ≠ .rootb)
    {e : Eff} {hv : Bool}
    (hst : ∀ o, o ≠ x → m'.st o = m.st o) (hheap : HeapOK m') (hnv : m'.nv = m.nv)
    (hkeep : ∀ k, e.kills hv k = false → VKeep m m' ⟨x, k⟩ ∧ HKeep m m' ⟨x, k⟩)
    {ox : Option Entry} (hox : NewSlot m' (kill e hv x Γ) x Ex ox)
    (hrem : ox = none → e = .replace) :
    MInv m' (upd (kill e hv x Γ) x ox) := by
  have depKeep : ∀ v E, Γ v = some E → (killE e hv x E).live = true → E.ty ≠ .int →
      ∀ dep ∈ E.vdeps, VKeep m m' dep ∧ HKeep m m' dep := by
    intro v E hv' hl hnint dep hd
    obtain ⟨hlE, hnot⟩ := killE_live_dep hl (Or.inl hnint)
    by_cases hr : dep.root = x
    · obtain ⟨r, k⟩ := dep
      simp only at hr; subst hr
      exact hkeep k (hnot _ hd rfl)
    · obtain ⟨Er, hEr, hroot⟩ := hi.wf v E hv' hlE (Or.inl hnint) dep.root (List.mem_map_of_mem hd)
      have hk := rootKeep_frame hi hanch (fun o ho => hst o (fun h => hxF (h ▸ ho))) hEr hroot
        (hst _ hr)
      exact ⟨hk.vkeep, hk.hkeep⟩
  have getE : ∀ v E', upd (kill e hv x Γ) x ox v = some E' → v ≠ x →
      ∃ E, Γ v = some E ∧ E' = killE e hv x E := by
    intro v E' h hvx
    rw [upd_ne _ _ hvx] at h
    unfold kill at h
    cases hE : Γ v with
    | none => rw [hE] at h; cases h
    | some E => rw [hE] at h; cases h; exact ⟨E, rfl, rfl⟩
  have getX : ∀ E', upd (kill e hv x Γ) x ox x = some E' → ox = some E' := by
    intro E' h; simpa using h
  constructor
  · intro v
    by_cases hvx : v = x
    · subst hvx
      cases ox with
      | none => simp only [upd_same, Option.isSome_none]; rw [show m'.st v = none from hox]; rfl
      | some Ex' =>
        obtain ⟨sl, hsl, _⟩ := hox
        simp [hsl]
    · rw [upd_ne _ _ hvx, hst v hvx, ← hi.dom v]
      unfold kill; cases Γ v <;> rfl
  · intro v E' hv'
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨sl, hsl, hok, hslot, _⟩ := hox
      exact ⟨sl, hsl, hok, hslot⟩
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      obtain ⟨sl, hsl, hok, hslot⟩ := hi.slot v E hE
      refine ⟨sl, by rw [hst v hvx]; exact hsl, by rw [killE_ty]; exact hok, ?_⟩
      by_cases hl : (killE e hv x E).live = true
      · have hEq : killE e hv x E = E := by
          have := (killE_live_dep (e := e) (hv := hv) (x := x) (E := E))
          unfold killE at hl ⊢; split at hl
          · simp at hl
          · rename_i hh; simp [hh]
        rw [hEq] at hl ⊢
        by_cases hint : E.ty = .int
        · obtain ⟨ho, hown, hbor⟩ := hslot
          refine ⟨ho, fun hos => ?_, fun hos hl' => ?_⟩
          · obtain ⟨⟨t, ht⟩, _⟩ := hown hos
            rw [hint] at ht; cases ht
          · obtain ⟨w, hw, hok'⟩ := hbor hos hl'
            exact ⟨w, hw, by rw [hint] at hok' ⊢; exact hok'⟩
        · refine hslot.keep fun dep hd => depKeep v E hE (by rw [hEq]; exact hl) hint dep hd
      · have hdead : (killE e hv x E).live = false := by simpa using hl
        by_cases hrb : E.mode = .rootb
        · rw [killE_rootb hanch hxF e hv hE hrb] at hdead
          rw [hi.rootbLive v E hE hrb] at hdead; cases hdead
        · have hw : EntryWeaker E (killE e hv x E) :=
            ⟨killE_ty .., killE_mode .., fun h => absurd h hrb, fun h => by rw [hdead] at h; cases h⟩
          exact (hslot.weaker hw).dead hdead
  · exact hheap
  · intro v hv'
    rw [hnv]
    by_cases hvx : v = x
    · subst hvx; exact hi.nvSt v (by rw [← hi.dom v, hx]; rfl)
    · exact hi.nvSt v (by rw [← hst v hvx]; exact hv')
  · intro v E' b hv'
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨_, _, _, _, hm, _⟩ := hox
      rw [hm]; exact hi.noInout v Ex b hx
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [killE_mode]; exact hi.noInout v E b hE
  · intro v E' hv' hl hnint r hr
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨_, _, _, _, hm', hwf⟩ := hox
      have hnint' : E'.ty ≠ .int := by
        rcases hnint with h | h
        · exact h
        · exact absurd (hm' ▸ h) hxr
      rcases hwf hl hnint' r hr with ⟨rfl, hroot⟩ | ⟨hrx, Er, hEr, hroot⟩
      · exact ⟨E', by simp, hroot⟩
      · exact ⟨Er, by rw [upd_ne _ _ hrx]; exact hEr, hroot⟩
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [killE_ty, killE_mode] at hnint
      rw [killE_vdeps] at hr
      have hlE : E.live = true := by
        rw [killE_live] at hl; simp only [Bool.and_eq_true] at hl; exact hl.1
      obtain ⟨Er, hEr, hroot⟩ := hi.wf v E hE hlE hnint r hr
      by_cases hrx : r = x
      · subst hrx
        cases ox with
        | none =>
          exfalso
          obtain ⟨dep, hd, rfl⟩ := List.mem_map.mp hr
          rcases hnint with hnint | hrb
          · have := (killE_live_dep hl (Or.inl hnint)).2 dep hd rfl
            rw [hrem rfl] at this
            cases hk : dep.kind <;> rw [hk] at this <;> simp [Eff.kills] at this
          · exact hxF (hanch v E hE hrb _ (List.mem_map_of_mem hd))
        | some Ex' =>
          obtain ⟨_, _, _, _, hm, _⟩ := hox
          rw [hx] at hEr; cases hEr
          exact ⟨Ex', by simp, by rw [hm]; exact hroot⟩
      · refine ⟨killE e hv x Er, ?_, by rw [killE_mode]; exact hroot⟩
        rw [upd_ne _ _ hrx]; unfold kill; rw [hEr]; rfl
  · intro p E' hp' hm
    by_cases hpx : p = x
    · subst hpx
      have := getX E' hp'; subst this
      obtain ⟨_, _, _, _, hm', _⟩ := hox
      exact absurd (hm' ▸ hm) hxr
    · obtain ⟨E, hE, rfl⟩ := getE p E' hp' hpx
      rw [killE_mode] at hm
      rw [killE_rootb hanch hxF e hv hE hm]
      exact hi.rootbLive p E hE hm
  · intro p E' hp' hm
    by_cases hpx : p = x
    · subst hpx
      have := getX E' hp'; subst this
      obtain ⟨_, _, _, _, hm', _⟩ := hox
      exact absurd (hm' ▸ hm) hxr
    · obtain ⟨E, hE, rfl⟩ := getE p E' hp' hpx
      rw [killE_mode] at hm
      rw [killE_rootb hanch hxF e hv hE hm]
      exact hi.rootbLt p E hE hm

end A1
