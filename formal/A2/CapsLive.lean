import A2.CapsEval

namespace A2

/-! AGORA-937 B4 (route U): the closure-capture clause over the live
bindings (`CapsLive`, formal/A2/THRU_STAGE3_DESIGN.md). A live binding's
value names its packages' captures in what the binding holds (`MInv.held`,
`NamesIn`), so where no live binding holds a mutating name on `w`, no
package in a live slot captures `w` but read-only. A dead slot is never read
by a typed statement, so it needs no such fact. -/

/-- No live binding holds a name dependency on `w` that may change it. -/
def NoMutLive (Γ : Ctx) (w : Var) : Prop :=
  ∀ v E, Γ v = some E → E.live = true → ∀ d ∈ E.held, d.root = w → d.kind.bound = .none

/-- A value whose captures by name are among `H`, which holds no mutating
    name on `w`, captures `w` only read-only (a capture `inout` has a bound,
    `PkgsOK`). -/
theorem ValCapsInp.of_namesIn {V : Val} {H : List Dep} {w : Var} (hn : NamesIn V H) (hp : PkgsOK V)
    (hH : ∀ d ∈ H, d.root = w → d.kind.bound = .none) : ValCapsInp V w := by
  intro fs te ms e cs hs q hq hqw
  have hqn : q ∈ V.names := names_sub hs q (by simp [Val.names, hq])
  have hd := hn q hqn
  have hb := hH _ hd (by simpa using hqw)
  obtain ⟨_, hmode, _⟩ := hp fs te ms e cs hs
  rcases hmode q hq with h | ⟨b, h, hbn, _⟩
  · exact h
  · simp [Kind.bound, h, PMode.bound] at hb
    exact absurd hb hbn

/-- **The live slots hold no package capturing `w` but read-only**, where no
    live binding may change `w` by name. -/
theorem MInv.liveCaps {m : Mem} {Γ : Ctx} {w : Var} (hM : MInv m Γ) (hnm : NoMutLive Γ w) :
    ∀ v E o V, Γ v = some E → E.live = true → m.st v = some ⟨o, some V⟩ → ValCapsInp V w :=
  fun v E o V hv hl hs =>
    ValCapsInp.of_namesIn (hM.held v E _ V hv hl hs rfl) (hM.pkgs v _ V hs rfl) (hnm v E hv hl)


namespace A2

end A2
