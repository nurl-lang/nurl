import A2.RegionMem

/-! AGORA-937, stage 3d groundwork (item 4): the kinds-composed lift of a
change through a region ends, at the caller, exactly what the callee ends.

A callee that changes through its lent parameter's region (item 3,
`RegionChangeWitness`) reaches the region `.inner`, through an element of a
slice the parameter holds. A callee binding depends on the region by a view
(`regionP`), an element (`.inner`) or a payload (`.share`). Where a call
passes an argument that views the caller's `w` (`⟨w, .view⟩`, or `.inner`
for something inside it), the region stands for `w`.

* **Verbatim** (`RSetup.subD`, today's lift): the caller's dependency is the
  argument's own, `⟨w, .view⟩`, so the change reaches `w` at `.view`. That
  is `.drop`, which ends every view of `w`, the argument's own included,
  though the callee keeps it (`verbatim_overkills`).
* **Kinds composed** (`subDc`): the change reaches `w` at
  `comp a .inner = .inner` (`comp_arg_inner`), so it is `.dropIn` on a `Vec`
  `w` (`inEff_comp_inner`). A callee binding that depends on the region at
  `k` depends on `w` at `comp a k`. For an argument that views `w`'s own
  buffer (`a = .view`), `.dropIn` ends that exactly when it ends `k`
  (`dropIn_comp_exact`). Over a whole entry, the caller's kill on `w` then
  hits exactly the entries the callee's kill on the region hits
  (`subDc_hits_exact`).
* For an argument that views something inside `w` (`a = .inner`), it does
  not (`dropIn_comp_inner_overkills`): A2's kinds have one level of depth.

So the call of a through-changing callee with views of real memory (3d) can
place the callee's change exactly once the call composes kinds, for
arguments that view the roots they reach at `.view`. Arguments at `.inner`
need the premise to refuse them, or another level of kinds. -/

namespace A2

/-- An argument that views `w` (`.view`) or something inside it
    (`.inner`): an element reached through it is inside `w`'s elements. -/
theorem comp_arg_inner {a : Kind} (ha : a = .view ∨ a = .inner) : comp a .inner = .inner := by
  rcases ha with rfl | rfl <;> rfl

/-- ... so the change reaches a `Vec` `w` strictly inside its elements. -/
theorem inEff_comp_inner {a : Kind} (ha : a = .view ∨ a = .inner) :
    Edit.inEff (comp a .inner) true = .dropIn := by
  rw [comp_arg_inner ha]; rfl

/-- **The composed kind is ended exactly when the callee's is**, for every
    kind a region is reached by, when the argument views `w`'s own buffer. -/
theorem dropIn_comp_exact {k : Kind} (hk : k = .view ∨ k = .inner ∨ k = .share) :
    Eff.dropIn.kills false (comp .view k) = Eff.dropIn.kills false k := by
  rcases hk with rfl | rfl | rfl <;> rfl

/-- ... and so when it reaches `w` by its handle (`.self`, what a call's
    setting adds for each root: `RSetup.OK.σ_self`), which composes to the
    callee's kind itself. -/
theorem dropIn_comp_exact' {a k : Kind} (ha : a = .view ∨ a = .self)
    (hk : k = .view ∨ k = .inner ∨ k = .share) :
    Eff.dropIn.kills false (comp a k) = Eff.dropIn.kills false k := by
  rcases ha with rfl | rfl
  · exact dropIn_comp_exact hk
  · rfl

/-- **... but not when it views something inside `w`** (`.inner`): A2's kinds
    have one level of depth, so a callee binding that views the region
    (what the argument's slices view, inside `w`'s elements) reaches `w` at
    `.inner`, which the caller's `.dropIn` ends though the callee keeps it.
    The 3d call premise must therefore ask that the arguments of a
    through-changing call view the roots they reach at `.view`, or the
    kinds need another level. -/
theorem dropIn_comp_inner_overkills :
    Eff.dropIn.kills false (comp .inner .view) = true ∧ Eff.dropIn.kills false .view = false := by
  decide

/-- The verbatim lift reaches `w` at the argument's own `.view`, where the
    change is a `.drop`, which ends the argument's view; `.dropIn` keeps it. -/
theorem verbatim_overkills :
    (Edit.inEff .view true).kills false .view = true ∧ Eff.dropIn.kills false .view = false := by
  decide

/-- **Over a whole entry**: what the caller's kill on `w` hits among a
    callee entry's dependencies on the region, composed, is what the
    callee's kill on the region hits. -/
theorem subDc_hits_exact {isPi : Var → Bool} {σ : Var → List Dep} {r w : Var}
    (hr : isPi r = true) (hσ : σ r ≠ [])
    (hσw : ∀ e ∈ σ r, e.root = w ∧ (e.kind = .view ∨ e.kind = .self)) :
    ∀ D : List Dep, (∀ d ∈ D, d.root = r ∧ (d.kind = .view ∨ d.kind = .inner ∨ d.kind = .share)) →
      (D.flatMap (subDc isPi σ)).any (fun d => d.root == w && Eff.dropIn.kills false d.kind) =
        D.any (fun d => d.root == r && Eff.dropIn.kills false d.kind)
  | [], _ => rfl
  | d :: D, hD => by
    obtain ⟨hdr, hdk⟩ := hD d (by simp)
    have ih := subDc_hits_exact hr hσ hσw D (fun d' hd' => hD d' (List.mem_cons_of_mem _ hd'))
    have hnm : d.kind.isName = false := by rcases hdk with h | h | h <;> rw [h] <;> rfl
    have hsub : subDc isPi σ d = (σ r).map fun e => (⟨e.root, comp e.kind d.kind⟩ : Dep) := by
      simp [subDc, hdr, hr, hnm]
    simp only [List.flatMap_cons, List.any_append, List.any_cons, hsub, ih, hdr, beq_self_eq_true,
      Bool.true_and]
    congr 1
    -- some element of σ r is ended exactly when `d` is: all are `w`'s, at a view or inside
    rw [List.any_map]
    obtain ⟨e0, he0⟩ := List.exists_mem_of_ne_nil _ hσ
    cases hk : Eff.dropIn.kills false d.kind with
    | true =>
      apply List.any_eq_true.mpr
      obtain ⟨hw0, ha0⟩ := hσw e0 he0
      exact ⟨e0, he0, by simp [Function.comp, hw0, dropIn_comp_exact' ha0 hdk, hk]⟩
    | false =>
      apply List.any_eq_false.mpr
      intro e he
      obtain ⟨_, ha⟩ := hσw e he
      simp [Function.comp, dropIn_comp_exact' ha hdk, hk]


/-- **For each of several roots** (AGORA-937 3d): when a region stands for
    views of several roots, each at a view or by its handle, the caller's
    kill on any one of them, `w`, hits among a callee entry's dependencies
    on the region, composed, exactly what the callee's kill on the region
    hits. σ's dependencies on the other roots are never `w`'s. -/
theorem subDc_hits_exact_root {isPi : Var → Bool} {σ : Var → List Dep} {r w : Var}
    (hr : isPi r = true) (hw : ∃ e ∈ σ r, e.root = w)
    (hσk : ∀ e ∈ σ r, e.kind = .view ∨ e.kind = .self) :
    ∀ D : List Dep, (∀ d ∈ D, d.root = r ∧ (d.kind = .view ∨ d.kind = .inner ∨ d.kind = .share)) →
      (D.flatMap (subDc isPi σ)).any (fun d => d.root == w && Eff.dropIn.kills false d.kind) =
        D.any (fun d => d.root == r && Eff.dropIn.kills false d.kind)
  | [], _ => rfl
  | d :: D, hD => by
    obtain ⟨hdr, hdk⟩ := hD d (by simp)
    have ih := subDc_hits_exact_root hr hw hσk D (fun d' hd' => hD d' (List.mem_cons_of_mem _ hd'))
    have hnm : d.kind.isName = false := by rcases hdk with h | h | h <;> rw [h] <;> rfl
    have hsub : subDc isPi σ d = (σ r).map fun e => (⟨e.root, comp e.kind d.kind⟩ : Dep) := by
      simp [subDc, hdr, hr, hnm]
    simp only [List.flatMap_cons, List.any_append, List.any_cons, hsub, ih, hdr, beq_self_eq_true,
      Bool.true_and]
    congr 1
    rw [List.any_map]
    obtain ⟨e0, he0, hw0⟩ := hw
    cases hk : Eff.dropIn.kills false d.kind with
    | true =>
      apply List.any_eq_true.mpr
      exact ⟨e0, he0, by simp [Function.comp, hw0, dropIn_comp_exact' (hσk e0 he0) hdk, hk]⟩
    | false =>
      apply List.any_eq_false.mpr
      intro e he
      simp [Function.comp, dropIn_comp_exact' (hσk e he) hdk, hk]

/-- ... and so the single-root form is its instance. -/
example {isPi : Var → Bool} {σ : Var → List Dep} {r w : Var}
    (hr : isPi r = true) (hσ : σ r ≠ [])
    (hσw : ∀ e ∈ σ r, e.root = w ∧ (e.kind = .view ∨ e.kind = .self)) (D : List Dep)
    (hD : ∀ d ∈ D, d.root = r ∧ (d.kind = .view ∨ d.kind = .inner ∨ d.kind = .share)) :
    (D.flatMap (subDc isPi σ)).any (fun d => d.root == w && Eff.dropIn.kills false d.kind) =
      D.any (fun d => d.root == r && Eff.dropIn.kills false d.kind) := by
  obtain ⟨e0, he0⟩ := List.exists_mem_of_ne_nil _ hσ
  exact subDc_hits_exact_root hr ⟨e0, he0, (hσw e0 he0).1⟩ (fun e he => (hσw e he).2) D hD


/-- **Another region is untouched** (AGORA-937 3d, the call-site premise):
    when no argument but the changed region's reaches `w`, so no other
    region `q` stands for anything of `w`'s, the caller's kill on `w` hits
    nothing a callee entry holds on `q`, composed. This is what makes the
    premise "no other argument reaches `w`" enough: the kill on `w` is the
    callee's kill on the changed region and nothing more. -/
theorem subDc_hits_none_root {isPi : Var → Bool} {σ : Var → List Dep} {q w : Var} {e : Eff} {hv : Bool}
    (hq : ∀ d ∈ σ q, d.root ≠ w) :
    ∀ D : List Dep, (∀ d ∈ D, d.root = q) → w ≠ q →
      (D.flatMap (subDc isPi σ)).any (fun d => d.root == w && e.kills hv d.kind) = false
  | [], _, _ => rfl
  | d :: D, hD, hwq => by
    have hdr := hD d (by simp)
    have ih := subDc_hits_none_root (isPi := isPi) (e := e) (hv := hv) hq D
      (fun d' hd' => hD d' (List.mem_cons_of_mem _ hd')) hwq
    simp only [List.flatMap_cons, List.any_append, ih, Bool.or_false]
    apply List.any_eq_false.mpr
    intro d' hd'
    unfold subDc at hd'
    split at hd'
    · split at hd'
      · cases hd'
      · obtain ⟨e0, he0, rfl⟩ := List.mem_map.mp hd'
        have := hq e0 (by rw [← hdr]; exact he0)
        simp [this]
    · rw [List.mem_singleton] at hd'; subst hd'
      simp [hdr, Ne.symm hwq]

end A2
