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




/-- `Γ1` ends bindings of `Γ` at most: a live binding of `Γ1` is a live one
    of `Γ`. -/
def LiveBack (Γ Γ1 : Ctx) : Prop :=
  ∀ v E1, Γ1 v = some E1 → E1.live = true → ∃ E, Γ v = some E ∧ E.live = true

theorem LiveBack.refl (Γ : Ctx) : LiveBack Γ Γ := fun _ E h hl => ⟨E, h, hl⟩

theorem LiveBack.trans {Γ1 Γ2 Γ3 : Ctx} (h1 : LiveBack Γ1 Γ2) (h2 : LiveBack Γ2 Γ3) : LiveBack Γ1 Γ3 :=
  fun v E3 h3 hl3 => by
    obtain ⟨E2, h2', hl2⟩ := h2 v E3 h3 hl3
    exact h1 v E2 h2' hl2

theorem LiveBack.kill (Γ : Ctx) (e : Eff) (hv : Bool) (x : Var) : LiveBack Γ (A2.kill e hv x Γ) :=
  fun v E1 h hl => by
    simp only [A2.kill] at h
    obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp h
    refine ⟨E, hE, ?_⟩
    unfold killE at hl; split at hl
    · simp at hl
    · exact hl

theorem LiveBack.setDead {Γ Γ1 : Ctx} (h : LiveBack Γ Γ1) (y : Var) (E : Entry) (hd : E.live = false) :
    LiveBack Γ (setE Γ1 y E) := fun v E1 hv hl => by
  by_cases hvy : v = y
  · subst hvy; simp [setE] at hv; subst hv; rw [hd] at hl; cases hl
  · simp only [setE, upd_ne _ _ hvy] at hv; exact h v E1 hv hl

theorem LiveBack.setLive {Γ Γ1 : Ctx} (h : LiveBack Γ Γ1) {y : Var} {Ey : Entry} (hy : Γ y = some Ey)
    (hl : Ey.live = true) (E : Entry) : LiveBack Γ (setE Γ1 y E) := fun v E1 hv hl1 => by
  by_cases hvy : v = y
  · subst hvy; exact ⟨Ey, hy, hl⟩
  · simp only [setE, upd_ne _ _ hvy] at hv; exact h v E1 hv hl1

theorem PushArg.liveBack {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hp : PushArg Γ F y Ey t D Γ1) : LiveBack Γ Γ1 := by
  cases hp with
  | move _ _ _ => exact (LiveBack.kill Γ .replace false y).setDead y _ rfl
  | int => exact LiveBack.refl Γ
  | slice _ => exact LiveBack.refl Γ

/-- A typed right-hand side ends bindings at most. -/
theorem RhsT.liveBack {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1) :
    LiveBack Γ Γ1 := by
  cases hr with
  | @moveOwn y Ey hy _ _ _ _ => exact (LiveBack.kill Γ .replace false _).setDead _ _ rfl
  | @moveUp y Ey _ _ _ hy => exact (LiveBack.kill Γ .replace false _).setDead _ _ rfl
  | pop _ _ _ _ _ => exact LiveBack.kill Γ _ _ _
  | remove _ _ _ _ _ _ _ => exact LiveBack.kill Γ _ _ _
  | pair hy _ hpa1 hz _ hpa2 _ => exact hpa1.liveBack.trans hpa2.liveBack
  | inl hy _ hpa _ => exact hpa.liveBack
  | inr hy _ hpa _ => exact hpa.liveBack
  | pack hy _ _ hpa => exact hpa.liveBack
  | arcNew hy _ _ _ _ _ _ hpa => exact hpa.liveBack
  | lockNew hy _ _ _ _ _ hpa => exact hpa.liveBack
  | cellNew hy _ _ _ _ _ hpa => exact hpa.liveBack
  | chanSend _ _ _ hy _ _ hpa => exact hpa.liveBack
  | lockRestore _ _ _ hy _ _ hpa => exact hpa.liveBack
  | @takel y Ey _ _ hy _ _ _ _ _ => exact (LiveBack.kill Γ .replace false _).setDead _ _ rfl
  | @take y Ey hl hy => exact (LiveBack.kill Γ .replace false _).setLive hy (by assumption) _
  | @taker y Ey _ _ hy _ _ _ _ _ => exact (LiveBack.kill Γ .replace false _).setDead _ _ rfl
  | _ => exact LiveBack.refl Γ

/-- The clause over the live bindings: a live slot's value, and the nodes
    its handle or view reaches in the slots, hold no package that captures
    `w` but read-only. (A node in a block holds none anyway,
    `MInv.rdCapsInp`.) -/
def LiveCaps (m : Mem) (Γ : Ctx) (w : Var) : Prop :=
  ∀ v E o V, Γ v = some E → E.live = true → m.st v = some ⟨o, some V⟩ →
    ValCapsInp V w ∧
    (∀ c, V = .href c → ∀ x t n, m.st x = some ⟨true, some t⟩ → Sub n t →
      (∃ ty d es, n = .node ty c d es) → ValCapsInp n w) ∧
    (∀ d o' l, V = .view d o' l → ∀ x t n, m.st x = some ⟨true, some t⟩ → Sub n t →
      (∃ ty c es, n = .node ty c d es) → ValCapsInp n w)

theorem LiveCaps.val {m : Mem} {Γ : Ctx} {w : Var} (h : LiveCaps m Γ w) {v : Var} {E : Entry}
    {o : Bool} {V : Val} (hv : Γ v = some E) (hl : E.live = true) (hs : m.st v = some ⟨o, some V⟩) :
    ValCapsInp V w := (h v E o V hv hl hs).1

/-- What a typed right-hand side yields holds no package capturing `w` but
    read-only, where the live bindings it reads hold none. -/
theorem RhsT.liveCapsVal {m m1 : Mem} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    {v : Val} {o : Bool} {w : Var}
    (hr : RhsT Γ F r E Γ1) (he : EvalR m r (.ok v o m1)) (hM : MInv m Γ) (h : LiveCaps m Γ w)
    (hw : w ∉ r.vars) : ValCapsInp v w := by
  have lf : ∀ {u : Val}, (∀ fs te ms e cs, u ≠ .pkg fs te ms e cs) → (∀ e, ¬ Child e u) → ValCapsInp u w :=
    fun a b => ValCapsInp.leaf a b
  induction hr generalizing v o m1
  case expr => cases he; exact ValCapsInp.int _ w
  case new =>
    cases he
    refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with | elem he => simp at he
  case moveOwn y E0 hy hl _ _ _ _ => cases he <;> exact h.val hy hl (by assumption)
  all_goals first
    | (cases he <;> first
        | exact h.val (by assumption) (by assumption) (by assumption)
        | exact ValCapsInp.int _ w
        | exact ((h.val (by assumption) (by assumption) (by assumption)).child Child.fst).lend
        | exact ((h.val (by assumption) (by assumption) (by assumption)).child Child.snd).lend
        | exact ((h.val (by assumption) (by assumption) (by assumption)).child Child.inl).lend
        | exact ((h.val (by assumption) (by assumption) (by assumption)).child Child.inr).lend
        | exact (h.val (by assumption) (by assumption) (by assumption)).child Child.inl
        | exact (h.val (by assumption) (by assumption) (by assumption)).child Child.inr
        | exact (hM.rdCapsInp w (by assumption)).2
        | exact (hM.rdCapsInp w (by assumption)).1.lend)
    | sorry -- WIP scaffold (AGORA-937 B4, never merged): RhsT.liveCapsVal, the remaining cases

end A2
