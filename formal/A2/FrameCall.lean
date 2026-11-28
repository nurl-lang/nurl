module

public import A2.FrameClause
public import A2.CallMem

@[expose] public section

namespace A2

/-! ### The call opens a frame meeting the clause -/

/-- What an argument holds by a name that may change its binding is among
    the call's `mutNames`. -/
theorem mutNames_of_held {Γ : Ctx} {args : List Var} {a : Var} {d0 : Dep} (ha : a ∈ args)
    (hat : (argE Γ a).ty ≠ .int) (hd0 : d0 ∈ (argE Γ a).held) (hb : d0.kind.bound ≠ .none) :
    d0 ∈ mutNames Γ args := by
  have hname : d0.kind.isName = true := by
    cases hk : d0.kind <;> simp_all [Kind.bound, Kind.isName]
  simp only [mutNames, List.mem_filter]
  refine ⟨?_, by simpa using hb⟩
  simp only [argNames, List.mem_flatMap]
  refine ⟨a, ha, ?_⟩
  simp only [hat, ↓reduceIte, nameDeps, List.mem_filter]
  exact ⟨by simp [Entry.vdeps, hd0], hname⟩

/-- **No argument holds a mutating name on a root another argument
    depends on with no bound** (`NamesFree`): a mutating name on it would be
    a root of `mutNames`, whose every argument dependency on it has its bound. -/
theorem NamesFree.noMut {Γ : Ctx} {F : List Var} {ps : List (PMode × Ty)} {args : List Var}
    (hnf : NamesFree Γ F ps args) {a vv : Var} (ha : a ∈ args) (hat : (argE Γ a).ty ≠ .int)
    (hvv : vv ∈ args) (hvt : (argE Γ vv).ty ≠ .int) {d : Dep} (hd : d ∈ (argE Γ vv).vdeps)
    (hdk : d.kind.bound = .none) :
    ∀ d0 ∈ (argE Γ a).held, d0.root = d.root → d0.kind.bound = .none := by
  intro d0 hd0 hr
  cases hb : d0.kind.bound with
  | none => rfl
  | _ =>
    exfalso
    have hmem : d0 ∈ mutNames Γ args := mutNames_of_held ha hat hd0 (by rw [hb]; simp)
    obtain ⟨_, _, _, _, hsame, _⟩ := hnf d0 hmem
    have := hsame vv hvv (Or.inl hvt) d hd (hr ▸ rfl)
    rw [hdk, hb] at this; cases this


/-- ... what a clean slot lends is clean too, its handles reaching clean
    nodes. -/
theorem LiveGood.lend {m : Mem} {Γ : Ctx} {w y : Var} {E : Entry} {V : Val} (hg : LiveGood m w V)
    (hM : MInv m Γ) (hy : Γ y = some E) (hl : E.live = true) (hs : m.st y = some ⟨true, some V⟩) :
    LiveGood m w (lendOf V) :=
  ⟨hg.1.lend, fun _ hc => hg.partTgt hM hy hl hs (Sub.refl _) hc⟩

/-- **A call's frame meets the frame clause at a domain `D`** where every
    argument's value, and every old slot outside `D`, does: each slot of the
    frame is an old one, an argument's value or what it lends
    (`BindParams.src`), and its owned slots hold old owned trees
    (`BindParams.ownedBack`). -/
theorem BindParams.frameCaps {Γ : Ctx} {m m1 : Mem} {fn : Fn} {args : List Var} {x : Var}
    (hb : BindParams m fn.params args m.nv 0 m1) (hM : MInv m Γ) (hlt : ∀ a ∈ args, a < m.nv)
    (hlive : ∀ a ∈ args, ∃ E, Γ a = some E ∧ E.live = true) {D : List Var} {w : Var}
    (hA : ∀ a ∈ args, ∀ o V, m.st a = some ⟨o, some V⟩ → LiveGood m w V)
    (hD : ∀ v o V, v ∉ D → m.st v = some ⟨o, some V⟩ → LiveGood m w V) :
    FrameCaps (callMem m m1 fn x) D w := by
  have hst : ∀ y o V, (callMem m m1 fn x).st y = some ⟨o, some V⟩ → m1.st y = some ⟨o, some V⟩ := by
    intro y o V hy
    unfold callMem at hy
    by_cases h1 : y = m.nv + fn.params.length
    · subst h1; simp [Mem.set, upd] at hy
    · by_cases h2 : y = x
      · subst h2; simp [Mem.set, upd, h1] at hy
      · simpa [Mem.set, upd, h1, h2] using hy
  have hob : ∀ y t, (callMem m m1 fn x).st y = some ⟨true, some t⟩ → ∃ z, m.st z = some ⟨true, some t⟩ :=
    fun y t hy => hb.ownedBack y t (hst y true t hy)
  intro v o V hvD hs
  refine LiveGood.mono (m := m) ?_ hob
  rcases hb.src hlt v o V (hst v o V hs) with h0 | ⟨a, ha, o', V0, hsa, hV⟩
  · exact hD v o V hvD h0
  · obtain ⟨Ea, hEa, hla⟩ := hlive a ha
    have hg := hA a ha o' V0 hsa
    rcases hV with rfl | ⟨rfl, rfl⟩
    · exact hg
    · exact hg.lend hM hEa hla hsa



/-- An integer binding's value meets the clause: it holds no package and no
    handle. -/
theorem MInv.goodInt {m : Mem} {Γ : Ctx} (hM : MInv m Γ) {a : Var} {E : Entry} {o : Bool} {V : Val} {w : Var}
    (hE : Γ a = some E) (hl : E.live = true) (ht : E.ty = .int) (hs : m.st a = some ⟨o, some V⟩) :
    LiveGood m w V := by
  obtain ⟨sl, hsl, _, hown, howning, hbor⟩ := hM.slot a E hE
  rw [hs] at hsl; cases hsl
  cases hos : E.mode.ownSlot
  · obtain ⟨V', hV', hvok⟩ := hbor hos hl
    cases hV'
    rw [ht] at hvok
    have hn := hvok.names_nil_fn (by rfl)
    refine ⟨valCapsInp_of_names hn w, fun c hc => ?_⟩
    cases hvok <;> cases hc
  · have hw := (howning hos).2.1 V rfl
    rw [ht] at hw
    exact ⟨valCapsInp_of_names (hw.names_nil_fn rfl) w, fun c hc => (hw.href_sub_false hc).elim⟩

/-- A type with no view holds no closure that holds names. -/
theorem Ty.hasFn_of_holdsView : ∀ {t : Ty}, t.holdsView = false → t.hasFn = false := by
  intro t
  induction t <;> simp_all [Ty.holdsView, Ty.hasFn]

/-- AGORA-937 B4: **a call's frame list**: the caller's bindings, but the
    `inout` arguments and the roots of the arguments' names that may change
    their binding (`mutNames`): what the frame may change. -/
def callZ (Γ : Ctx) (fn : Fn) (args : List Var) (base : Nat) : List Var :=
  (List.range base).filter (fun v =>
    !(inoutArgs fn.params args).contains v && !((mutNames Γ args).map (·.root)).contains v)

theorem not_mem_callZ {Γ : Ctx} {fn : Fn} {args : List Var} {base : Nat} {v : Var}
    (hv : v ∉ callZ Γ fn args base) :
    base ≤ v ∨ v ∈ inoutArgs fn.params args ∨ v ∈ (mutNames Γ args).map (·.root) := by
  by_cases hvl : v < base
  · right
    rcases Decidable.em (v ∈ inoutArgs fn.params args) with hio | hn
    · exact Or.inl hio
    rcases Decidable.em (v ∈ (mutNames Γ args).map (·.root)) with hmn | hn'
    · exact Or.inr hmn
    exact absurd (List.mem_filter.mpr ⟨List.mem_range.mpr hvl, by simp_all⟩) hv
  · exact Or.inl (Nat.le_of_not_lt hvl)

theorem mem_callZ {Γ : Ctx} {fn : Fn} {args : List Var} {base : Nat} {v : Var}
    (hv : v ∈ callZ Γ fn args base) :
    v < base ∧ v ∉ inoutArgs fn.params args ∧ v ∉ (mutNames Γ args).map (·.root) := by
  obtain ⟨h1, h2⟩ := List.mem_filter.mp hv
  refine ⟨List.mem_range.mp h1, fun h => ?_, fun h => ?_⟩ <;> simp_all

/-- **An argument's value meets the clause at a root outside the call's
    `mutNames`**: it holds it by no name that may change it. -/
theorem MInv.goodArg {m : Mem} {Γ : Ctx} (hM : MInv m Γ) {args : List Var} {a : Var} {E : Entry}
    {o : Bool} {V : Val} {w : Var} (ha : a ∈ args) (hE : Γ a = some E) (hl : E.live = true)
    (hs : m.st a = some ⟨o, some V⟩) (hw : w ∉ (mutNames Γ args).map (·.root)) : LiveGood m w V := by
  by_cases hat : E.ty = .int
  · exact hM.goodInt hE hl hat hs
  · refine hM.goodOf hE hl hs fun d0 hd0 hr => ?_
    rcases Decidable.em (d0.kind.bound = .none) with h | h
    · exact h
    · exact absurd (List.mem_map.mpr ⟨d0, mutNames_of_held ha (by simp [argE, hE, hat])
        (by simp [argE, hE, hd0]) h, hr⟩) hw

/-- **A root of the call's `mutNames` holds clean data**: an owned `Vec`
    of a type with no view (`NamesFree`), which holds no package and no
    handle. -/
theorem MInv.goodMut {m : Mem} {Γ : Ctx} (hM : MInv m Γ) {F : List Var} {ps : List (PMode × Ty)}
    {args : List Var} (hnf : NamesFree Γ F ps args) {v : Var} (hv : v ∈ (mutNames Γ args).map (·.root))
    {o : Bool} {V : Val} (hs : m.st v = some ⟨o, some V⟩) (w : Var) : LiveGood m w V := by
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hv
  obtain ⟨hcan, ⟨sv, hty, hsv⟩, _⟩ := hnf d hd
  cases hE : Γ d.root with
  | none => simp [argE, hE, intE] at hty
  | some E =>
    simp only [argE, hE, Option.getD_some] at hcan hty
    have hf : E.ty.hasFn = false := by rw [hty]; exact Ty.hasFn_of_holdsView (t := .vec sv) hsv
    obtain ⟨hn, hh⟩ := hM.own_noFn hE hcan.ownSlot hf hs
    exact ⟨valCapsInp_of_names hn w, fun c hc => (hh c hc).elim⟩


end A2
