import A2.FrameClause
import A2.CallMem

namespace A2

/-! ### The call opens a frame meeting the clause -/

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
    have hname : d0.kind.isName = true := by
      cases hk : d0.kind <;> simp_all [Kind.bound, Kind.isName]
    have hmem : d0 ∈ mutNames Γ args := by
      simp only [mutNames, List.mem_filter]
      refine ⟨?_, by simp [hb]⟩
      simp only [argNames, List.mem_flatMap]
      refine ⟨a, ha, ?_⟩
      simp only [hat, ↓reduceIte, nameDeps, List.mem_filter]
      exact ⟨by simp [Entry.vdeps, hd0], hname⟩
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

end A2
