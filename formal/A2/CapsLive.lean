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

theorem TakeVal.slot {m m1 : Mem} {y : Var} {v : Val} (ht : TakeVal m y v m1) :
    ∃ o, m.st y = some ⟨o, some v⟩ := by
  cases ht with
  | own hv => exact ⟨_, hv⟩
  | bor hv => exact ⟨_, hv⟩

theorem TakeVal.st_of {m m1 : Mem} {y : Var} {v : Val} (ht : TakeVal m y v m1) (x : Var) :
    m1.st x = m.st x ∨ m1.st x = some ⟨true, none⟩ := by
  cases ht with
  | own hv =>
    by_cases hxy : x = y
    · subst hxy; right; simp [Mem.set, upd]
    · left; simp [Mem.set, upd, hxy]
  | bor hv => exact Or.inl rfl

theorem ValOK.href_sub {m : Mem} {τ : Ty} {V : Val} {P H : List Dep} (h : ValOK m τ V P H) {c : Nat}
    (hs : Sub (.href c) V) : ∃ dep t H', HrefAt m dep c t H' ∧ ∀ d ∈ H', d ∈ H := by
  induction h with
  | href hex => cases hs; obtain ⟨dep, _, hh⟩ := hex; exact ⟨dep, _, _, hh, fun _ h => h⟩
  | pair _ _ ih1 ih2 =>
    cases hs with
    | fst hs => exact ih1 hs
    | snd hs => exact ih2 hs
  | inl _ ih => cases hs with | inl hs => exact ih hs
  | inr _ ih => cases hs with | inr hs => exact ih hs
  | pkg _ _ ih =>
    cases hs with
    | pkg hs =>
      obtain ⟨dep, t, H', hh, hsub⟩ := ih hs
      exact ⟨dep, t, H', hh, fun d hd => (mem_envDeps.mp (hsub d hd)).1⟩
  | dtor _ ih => exact ih hs
  | _ => cases hs

theorem WFv.href_sub_false {τ : Ty} {V : Val} (h : WFv τ V) {c : Nat} (hs : Sub (.href c) V) : False := by
  induction h with
  | node _ ih => cases hs with | child he hs => exact ih _ he hs
  | pair _ _ ih1 ih2 =>
    cases hs with
    | fst hs => exact ih1 hs
    | snd hs => exact ih2 hs
  | inl _ ih => cases hs with | inl hs => exact ih hs
  | inr _ ih => cases hs with | inr hs => exact ih hs
  | dtor _ _ ih => exact ih hs
  | _ => cases hs <;> simp_all

theorem ValOK.href_inv {m : Mem} {τ : Ty} {c : Nat} {P H : List Dep} (h : ValOK m τ (.href c) P H) :
    ∃ dep ∈ P, ∃ t, HrefAt m dep c t H := by
  generalize hv : Val.href c = v at h
  induction h with
  | href hex => cases hv; obtain ⟨dep, hd, hh⟩ := hex; exact ⟨dep, hd, _, hh⟩
  | dtor _ ih => exact ih hv
  | _ => cases hv

theorem ValOK.view_inv {m : Mem} {τ : Ty} {d o l : Nat} {P H : List Dep} (h : ValOK m τ (.view d o l) P H) :
    ∃ dep ∈ P, ∃ s, ViewAt m dep d o l s ∧ τ.undtor = .slice s := by
  generalize hv : Val.view d o l = v at h
  induction h with
  | view hex => cases hv; obtain ⟨dep, hd, hh⟩ := hex; exact ⟨dep, hd, _, hh, rfl⟩
  | dtor _ ih =>
    obtain ⟨dep, hd, s, hh, hu⟩ := ih hv
    exact ⟨dep, hd, s, hh, by simpa [Ty.undtor] using hu⟩
  | _ => cases hv

theorem WFv.view_slice {τ : Ty} {d o l : Nat} (h : WFv τ (.view d o l)) : ∃ s, τ = .slice s := by
  generalize hv : Val.view d o l = v at h
  induction h with
  | view => exact ⟨_, rfl⟩
  | dtor hs _ ih =>
    obtain ⟨s, rfl⟩ := ih hv
    simp [Ty.isStruct] at hs
  | _ => cases hv

/-- A well-formed type whose undecorated form is a slice: its elements hold
    no views. -/
theorem Ty.ok_slice_noView {τ s : Ty} (h : τ.ok = true) (hu : τ.undtor = .slice s) : s.holdsView = false := by
  induction τ with
  | slice s' => simp [Ty.undtor] at hu; subst hu; simp [Ty.ok] at h; exact h.2
  | dtor f t ih =>
    simp [Ty.ok] at h
    exact ih h.2 (by simpa [Ty.undtor] using hu)
  | _ => simp [Ty.undtor] at hu


/-- What a live view reaches holds no package that captures by name: the
    view's element type holds no views (`Ty.ok`), so no closure with names. -/
theorem MInv.viewTargetCaps {m : Mem} {Γ : Ctx} (hM : MInv m Γ) {y : Var} {E : Entry} {o : Bool}
    {d o' l : Nat} {n : Val} (hy : Γ y = some E) (hl : E.live = true)
    (hs : m.st y = some ⟨o, some (.view d o' l)⟩) (hda : DataAt m d n) (w : Var) : ValCapsInp n w := by
  obtain ⟨sl, hsl, hok, hown, howning, hbor⟩ := hM.slot y E hy
  rw [hs] at hsl; cases hsl
  have hvat : ∃ dep s, ViewAt m dep d o' l s ∧ s.holdsView = false := by
    cases hos : E.mode.ownSlot
    · obtain ⟨V', hV', hvok⟩ := hbor hos hl
      cases hV'
      obtain ⟨dep, _, s, hva, hu⟩ := hvok.view_inv
      exact ⟨dep, s, hva, Ty.ok_slice_noView hok hu⟩
    · obtain ⟨_, hwf, hvs⟩ := howning hos
      obtain ⟨s, hτ⟩ := (hwf _ rfl).view_slice
      obtain ⟨T, hT, hvo⟩ := hvs hl
      cases hT
      obtain ⟨d1, o1, l1, he, dep, _, hva⟩ := hvo s _ (by rw [hτ]; exact ViewIn.here)
      cases he
      exact ⟨dep, s, hva, Ty.ok_slice_noView hok (by rw [hτ]; rfl)⟩
  obtain ⟨dep, s, ⟨c', es', _, hland, _, hwf⟩, hsv⟩ := hvat
  have hfn : (Ty.vec s).hasFn = false := by
    cases hf : s.hasFn
    · simpa [Ty.hasFn] using hf
    · exact absurd (hasFn_holdsView hf) (by rw [hsv]; simp)
  have hnil := valCapsInp_of_names (hwf.names_nil_fn hfn) w
  have hL : DataAt m d (.node s c' d es') := by
    rcases hland.home with ⟨x', T', hx', hsL⟩ | ⟨k, bl, hk, hsb⟩
    · exact Or.inl ⟨x', T', hx', hsL, _, _, _, rfl⟩
    · exact Or.inr ⟨k, bl, hk, hsb, _, _, _, rfl⟩
  rw [dataAt_unique hM.heap hda hL]; exact hnil

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
  case borrow =>
    cases he
    · exact lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
    · exact h.val (by assumption) (by assumption) (by assumption)
  case view => cases he; exact lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
  case glob =>
    cases he with
    | glob _ hf =>
      rcases hf with ⟨_, _, _, _, rfl, _⟩ | ⟨_, _, _, _, rfl, _⟩ <;>
        exact lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
  case «at» =>
    cases he with
    | «at» hn hv _ =>
      obtain ⟨_, _, hv | ⟨hhr, hn'⟩⟩ := hv
      · exact ((h.val (by assumption) (by assumption) hv).child (Child.elem (List.getElem_mem hn))).lend
      · rcases hn' with ⟨x, t', hx, hs, hnd⟩ | ⟨k, bl, hk, hs, _⟩
        · exact (((h _ _ _ _ (by assumption) (by assumption) hhr).2 _ (Sub.refl _) x t' _ hx hs hnd).child
            (Child.elem (List.getElem_mem hn))).lend
        · exact (((hM.rdCapsInp w hk).1.sub hs).child (Child.elem (List.getElem_mem hn))).lend
  case sat =>
    cases he with
    | sat hn hv _ _ _ hda =>
      exact ((hM.viewTargetCaps (by assumption) (by assumption) hv hda w).child
        (Child.elem (List.getElem_mem hn))).lend
  case pair y z Ey Ez Γa Γb Dy Dz hy hl hpa1 hz hl2 hpa2 _ =>
    cases he with
    | @pair _ _ v1 v2 m1' m2' h1 h2 =>
      obtain ⟨_, hs1⟩ := h1.slot
      obtain ⟨_, hs2⟩ := h2.slot
      have hs2' : ∃ o, m.st z = some ⟨o, some v2⟩ := by
        rcases h1.st_of z with he | he
        · rw [he] at hs2; exact ⟨_, hs2⟩
        · rw [he] at hs2; cases hs2
      obtain ⟨_, hs2'⟩ := hs2'
      obtain ⟨Ez0, hz0, hl0⟩ := hpa1.liveBack _ _ hz hl2
      refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with
      | fst => exact h.val hy hl hs1
      | snd => exact h.val hz0 hl0 hs2'
  case inl hy hl _ _ =>
    cases he with
    | inl h1 =>
      obtain ⟨_, hs1⟩ := h1.slot
      refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with | inl => exact h.val hy hl hs1
  case inr hy hl _ _ =>
    cases he with
    | inr h1 =>
      obtain ⟨_, hs1⟩ := h1.slot
      refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with | inr => exact h.val hy hl hs1
  case pack hy hl _ _ _ _ =>
    cases he with
    | pack h1 =>
      obtain ⟨_, hs1⟩ := h1.slot
      refine ValCapsInp.of_children (fun fs te ms e cs he => ?_) (fun e hc => ?_)
      · cases he
        intro q hq hqw
        exact absurd (by simp only [Rhs.vars, List.mem_cons, List.mem_map]; exact Or.inr ⟨q, hq, hqw⟩) hw
      · cases hc with | pkg => exact h.val hy hl hs1
  case arcNew => cases he; exact lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
  case lockNew => cases he; exact lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
  case cellNew => cases he; exact lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
  case pop =>
    cases he with
    | pop hv _ _ => exact (h.val (by assumption) (by assumption) hv).child (Child.elem (by simp))
  case remove =>
    cases he with
    | remove hn hv _ _ _ => exact (h.val (by assumption) (by assumption) hv).child (Child.elem (List.getElem_mem hn))
  case rwRead => cases he; exact lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
  case rwTryRead =>
    cases he
    · refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with
      | inr => exact lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
    · refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with
      | inl => exact ValCapsInp.int _ w
  case rwTryWrite =>
    cases he
    · refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with
      | inr => exact ValCapsInp.int _ w
    · refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with
      | inl => exact ValCapsInp.int _ w
  case chanRecv =>
    cases he with
    | chanRecv _ hk _ _ =>
      have hp := (hM.rdCapsInp w hk).2
      refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with
      | inr => exact (hp.child Child.fst).child (Child.elem (List.mem_cons_self ..))
    | chanRecvNone _ _ _ _ =>
      refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with
      | inl => exact ValCapsInp.int _ w
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


/-- Setting a slot to a value no part of which captures `w` but read-only,
    and whose handles reach clean nodes, keeps the clause: the live values
    and the targets in the other slots are as they were, and every node in
    the new value is clean. -/
theorem LiveCaps.set {m : Mem} {Γ : Ctx} {w : Var} (h : LiveCaps m Γ w) {y : Var} {o : Bool}
    {v : Option Val} (hv : ∀ V, v = some V → (∀ n, Sub n V → ValCapsInp n w) ∧
      (∀ c, Sub (.href c) V → ∀ x t n, m.st x = some ⟨true, some t⟩ → Sub n t →
        (∃ ty d es, n = .node ty c d es) → ValCapsInp n w)) :
    LiveCaps (m.set y ⟨o, v⟩) Γ w := by
  intro x E o1 V hx hl hs
  -- a target in the slots after the set: in `y`'s new value, or where it was
  have htgt : ∀ x' t n, (m.set y ⟨o, v⟩).st x' = some ⟨true, some t⟩ → Sub n t →
      (m.st x' = some ⟨true, some t⟩) ∨ ValCapsInp n w := by
    intro x' t n hx' hsn
    by_cases hxy : x' = y
    · subst hxy; simp at hx'; obtain ⟨_, rfl⟩ := hx'; exact Or.inr ((hv t rfl).1 n hsn)
    · simp [upd_ne _ _ hxy] at hx'; exact Or.inl hx'
  have hcl : ∀ V', (∀ c, Sub (.href c) V' → ∀ x t n, m.st x = some ⟨true, some t⟩ → Sub n t →
      (∃ ty d es, n = .node ty c d es) → ValCapsInp n w) →
      ∀ c, Sub (.href c) V' → ∀ x t n, (m.set y ⟨o, v⟩).st x = some ⟨true, some t⟩ → Sub n t →
        (∃ ty d es, n = .node ty c d es) → ValCapsInp n w := by
    intro V' h2 c hc x' t n hx' hsn hnd
    rcases htgt x' t n hx' hsn with hx'' | hn
    · exact h2 c hc x' t n hx'' hsn hnd
    · exact hn
  by_cases hxy : x = y
  · subst hxy
    simp at hs; obtain ⟨_, rfl⟩ := hs
    obtain ⟨hsub, hnh⟩ := hv V rfl
    exact ⟨hsub V (Sub.refl _), hcl V hnh⟩
  · simp [upd_ne _ _ hxy] at hs
    obtain ⟨h1, h2⟩ := h x E o1 V hx hl hs
    exact ⟨h1, hcl V h2⟩

/-- ... and so does setting the slot of a binding the context changes:
    every other live binding was a live one before. -/
theorem LiveCaps.setG {m : Mem} {Γ Γ' : Ctx} {w : Var} (h : LiveCaps m Γ w) {y : Var} {o : Bool}
    {v : Option Val}
    (hb : ∀ x E1, x ≠ y → Γ' x = some E1 → E1.live = true → ∃ E0, Γ x = some E0 ∧ E0.live = true)
    (hv : ∀ V, v = some V → (∀ n, Sub n V → ValCapsInp n w) ∧
      (∀ c, Sub (.href c) V → ∀ x t n, m.st x = some ⟨true, some t⟩ → Sub n t →
        (∃ ty d es, n = .node ty c d es) → ValCapsInp n w)) :
    LiveCaps (m.set y ⟨o, v⟩) Γ' w := by
  intro x E o1 V hx hl hs
  have htgt : ∀ x' t n, (m.set y ⟨o, v⟩).st x' = some ⟨true, some t⟩ → Sub n t →
      (m.st x' = some ⟨true, some t⟩) ∨ ValCapsInp n w := by
    intro x' t n hx' hsn
    by_cases hxy : x' = y
    · subst hxy; simp at hx'; obtain ⟨_, rfl⟩ := hx'; exact Or.inr ((hv t rfl).1 n hsn)
    · simp [upd_ne _ _ hxy] at hx'; exact Or.inl hx'
  have hcl : ∀ V', (∀ c, Sub (.href c) V' → ∀ x t n, m.st x = some ⟨true, some t⟩ → Sub n t →
      (∃ ty d es, n = .node ty c d es) → ValCapsInp n w) →
      ∀ c, Sub (.href c) V' → ∀ x t n, (m.set y ⟨o, v⟩).st x = some ⟨true, some t⟩ → Sub n t →
        (∃ ty d es, n = .node ty c d es) → ValCapsInp n w := by
    intro V' h2 c hc x' t n hx' hsn hnd
    rcases htgt x' t n hx' hsn with hx'' | hn
    · exact h2 c hc x' t n hx'' hsn hnd
    · exact hn
  by_cases hxy : x = y
  · subst hxy
    simp at hs; obtain ⟨_, rfl⟩ := hs
    obtain ⟨hsub, hnh⟩ := hv V rfl
    exact ⟨hsub V (Sub.refl _), hcl V hnh⟩
  · simp [upd_ne _ _ hxy] at hs
    obtain ⟨E0, h0, hl0⟩ := hb x E hxy hx hl
    obtain ⟨h1, h2⟩ := h x E0 o1 V h0 hl0 hs
    exact ⟨h1, hcl V h2⟩

theorem LiveCaps.set_none {m : Mem} {Γ : Ctx} {w : Var} (h : LiveCaps m Γ w) (y : Var) (o : Bool) :
    LiveCaps (m.set y ⟨o, none⟩) Γ w :=
  h.set (fun _ e => by cases e)


/-- A node whose elements are among a clean node's is clean, every part. -/
theorem ValCapsInp.shrink {t : Ty} {c d : Nat} {es es' : List Val} {w : Var}
    (hT : ValCapsInp (.node t c d es) w) (hsub : ∀ e ∈ es', e ∈ es) :
    ∀ n, Sub n (.node t c d es') → ValCapsInp n w := by
  intro n hn
  cases hn with
  | refl =>
    refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with | elem he => exact hT.child (Child.elem (hsub _ he))
  | child he hs => exact hT.sub (Sub.child (hsub _ he) hs)

theorem TakeVal.liveCaps {m m1 : Mem} {Γ : Ctx} {y : Var} {v : Val} {w : Var} (ht : TakeVal m y v m1)
    (h : LiveCaps m Γ w) : LiveCaps m1 Γ w := by
  cases ht with
  | own _ => exact h.set_none _ _
  | bor _ => exact h

/-- **The store a typed right-hand side leaves keeps the clause**: it ends
    bindings at most (`RhsT.liveBack`), and changes only the slot it reads, to
    nothing or to part of what it held. -/
theorem RhsT.liveCapsSt {m m1 : Mem} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    {v : Val} {o : Bool} {w : Var}
    (hr : RhsT Γ F r E Γ1) (he : EvalR m r (.ok v o m1)) (h : LiveCaps m Γ w) : LiveCaps m1 Γ1 w := by
  have h' := h.of_back hr.liveBack
  cases he
  case pair => rename_i h1 h2; exact h2.liveCaps (h1.liveCaps h')
  case arcNew =>
    obtain ht : TakeVal _ _ _ _ := by assumption
    exact (ht.liveCaps h').of_st rfl
  case lockNew =>
    obtain ht : TakeVal _ _ _ _ := by assumption
    exact (ht.liveCaps h').of_st rfl
  case cellNew =>
    obtain ht : TakeVal _ _ _ _ := by assumption
    exact (ht.liveCaps h').of_st rfl
  case chanSend =>
    obtain ht : TakeVal _ _ _ _ := by assumption
    exact (ht.liveCaps h').of_st rfl
  case chanSendClosed =>
    obtain ht : TakeVal _ _ _ _ := by assumption
    exact (ht.liveCaps h').of_st rfl
  case lockRestore =>
    obtain ht : TakeVal _ _ _ _ := by assumption
    exact (ht.liveCaps h').of_st rfl
  case pop =>
    obtain hv : m.st _ = some ⟨true, some (.node _ _ _ (_ ++ [_]))⟩ := by assumption
    cases hr with
    | pop hy hl _ _ _ =>
      have hT := h.val hy hl hv
      refine LiveCaps.set h' (fun V e => ?_)
      cases e
      refine ⟨hT.shrink (fun e he => List.mem_append_left _ he), fun c hc => ?_⟩
      -- a handle in the shrunk node was in the old one
      cases hc with
      | child he hs =>
        exact (h _ _ _ _ hy hl hv).2 c (Sub.child (List.mem_append_left _ he) hs)
  case remove =>
    obtain hv : m.st _ = some ⟨true, some (.node _ _ _ _)⟩ := by assumption
    cases hr with
    | remove hy hl _ _ _ _ _ =>
      have hT := h.val hy hl hv
      refine LiveCaps.set h' (fun V e => ?_)
      cases e
      refine ⟨hT.shrink (fun e he => List.mem_of_mem_eraseIdx he), fun c hc => ?_⟩
      cases hc with
      | child he hs =>
        exact (h _ _ _ _ hy hl hv).2 c (Sub.child (List.mem_of_mem_eraseIdx he) hs)
  case take =>
    refine LiveCaps.set (h'.of_st rfl) (fun V e => ?_)
    cases e
    refine ⟨fun n hn => ?_, fun c hc => ?_⟩
    rotate_left
    · cases hc with | child he _ => simp at he
    cases hn with
    | refl =>
      refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with | elem he => simp at he
    | child he _ => simp at he
  all_goals first
    | exact h'
    | exact h'.set_none _ _
    | exact h'.of_st rfl
    | exact (‹TakeVal _ _ _ _›.liveCaps h')
    | exact (‹TakeVal _ _ _ _›.liveCaps h').of_st rfl


/-- **At the call: the clause holds** where no live binding may change `w`
    by name. A live value is clean (`MInv.liveCaps`). What its handle
    reaches is named by it (`HrefAt`), and what its view reaches is of a
    type that holds no closure with names (a slice's elements hold no views,
    `Ty.ok`). A node in a slot is the one the handle or view lands on
    (`nodeAt_unique`, `dataAt_unique`). -/
theorem MInv.liveCapsAll {m : Mem} {Γ : Ctx} {w : Var} (hM : MInv m Γ) (hnm : NoMutLive Γ w) :
    LiveCaps m Γ w := by
  intro v E o V hv hl hs
  obtain ⟨sl, hsl, hok, hown, howning, hbor⟩ := hM.slot v E hv
  rw [hs] at hsl; cases hsl
  refine ⟨hM.liveCaps hnm v E o V hv hl hs, ?_⟩
  rintro c hcs x t n hx hsn ⟨ty, d, es, rfl⟩
  have hnA : NodeAt m c (.node ty c d es) := Or.inl ⟨x, t, hx, hsn, ty, d, es, rfl⟩
  cases hos : E.mode.ownSlot
  · obtain ⟨V', hV', hvok⟩ := hbor hos hl
    cases hV'
    obtain ⟨dep, _, H', ⟨d', es', hland, _, _, hnames, _⟩, hH⟩ := hvok.href_sub hcs
    rcases hland.home with ⟨x', T', hx', hsL⟩ | ⟨k, bl, hk, hsb⟩
    · have heq := nodeAt_unique hM.heap hnA (Or.inl ⟨x', T', hx', hsL, _, _, _, rfl⟩)
      rw [heq]
      exact ValCapsInp.of_namesIn hnames ((hM.pkgs x' _ T' hx' rfl).sub hsL)
        (fun d hd => hnm v E hv hl d (hH d hd))
    · have heq := nodeAt_unique hM.heap hnA (Or.inr ⟨k, bl, hk, hsb, _, _, _, rfl⟩)
      rw [heq]; exact (hM.rdCapsInp w hk).1.sub hsb
  · exact ((howning hos).2.1 _ rfl).href_sub_false hcs |>.elim


/-- A handle in what lends a value is one the value holds, or one of a node
    inside it. -/
theorem sub_href_lendOf {c : Nat} : ∀ {u : Val}, Sub (.href c) (lendOf u) →
    Sub (.href c) u ∨ ∃ ty d es, Sub (.node ty c d es) u
  | .node t c' d es, h => by
    simp only [lendOf] at h; cases h; exact Or.inr ⟨t, d, es, Sub.refl _⟩
  | .pair a b, h => by
    simp only [lendOf] at h
    cases h with
    | fst h =>
      rcases sub_href_lendOf h with h | ⟨ty, d, es, h⟩
      · exact Or.inl (Sub.fst h)
      · exact Or.inr ⟨ty, d, es, Sub.fst h⟩
    | snd h =>
      rcases sub_href_lendOf h with h | ⟨ty, d, es, h⟩
      · exact Or.inl (Sub.snd h)
      · exact Or.inr ⟨ty, d, es, Sub.snd h⟩
  | .inl a, h => by
    simp only [lendOf] at h
    cases h with
    | inl h =>
      rcases sub_href_lendOf h with h | ⟨ty, d, es, h⟩
      · exact Or.inl (Sub.inl h)
      · exact Or.inr ⟨ty, d, es, Sub.inl h⟩
  | .inr a, h => by
    simp only [lendOf] at h
    cases h with
    | inr h =>
      rcases sub_href_lendOf h with h | ⟨ty, d, es, h⟩
      · exact Or.inl (Sub.inr h)
      · exact Or.inr ⟨ty, d, es, Sub.inr h⟩
  | .pkg fs te ms a cs, h => by
    simp only [lendOf] at h
    cases h with
    | pkg h =>
      rcases sub_href_lendOf h with h | ⟨ty, d, es, h⟩
      · exact Or.inl (Sub.pkg h)
      · exact Or.inr ⟨ty, d, es, Sub.pkg h⟩
  | .int _, h => Or.inl h
  | .view _ _ _, h => Or.inl h
  | .href _, h => Or.inl h
  | .arc _ _, h => Or.inl h
  | .lk _, h => Or.inl h
  | .cell _, h => Or.inl h


/-- An owned slot's tree holds no handle: it is well-formed (`WFv`). -/
theorem MInv.slot_no_href {m : Mem} {Γ : Ctx} (hM : MInv m Γ) {x : Var} {T : Val} {c : Nat}
    (hx : m.st x = some ⟨true, some T⟩) (hs : Sub (.href c) T) : False := by
  have hd := hM.dom x
  rw [hx] at hd
  obtain ⟨Ex, hEx⟩ := Option.isSome_iff_exists.mp (by simpa using hd)
  obtain ⟨sl, hsl, _, hown, howning, _⟩ := hM.slot x Ex hEx
  rw [hx] at hsl; cases hsl
  have hos : Ex.mode.ownSlot = true := by rw [← hown]
  exact ((howning hos).2.1 T rfl).href_sub_false hs

/-- ... nor does what a block's holders read. -/
theorem MInv.rd_no_href {m : Mem} {Γ : Ctx} (hM : MInv m Γ) {k : Nat} {bl : Blk} {c : Nat}
    (hk : m.blk k = some bl) (hs : Sub (.href c) bl.rd) : False := by
  obtain ⟨_, _, hpay, _⟩ := hM.blocks k bl hk
  obtain ⟨ty, kind, pay⟩ := bl
  cases kind <;> cases pay <;> simp only [Blk.rd, Blk.tree, Option.getD] at hs
  all_goals first
    | exact ((hpay _ rfl).1).href_sub_false hs
    | (cases hs; done)


/-- A node inside a clean tree that lies at a handle, in an owned slot or a
    block, is the one every slot-located node at that handle is
    (`nodeAt_unique`), so all of them are clean. -/
theorem MInv.tgt_of_node {m : Mem} {Γ : Ctx} {w : Var} (hM : MInv m Γ) {ty : Ty} {c d : Nat}
    {es : List Val} (hn : NodeAt m c (.node ty c d es)) (hc : ValCapsInp (.node ty c d es) w) :
    ∀ x t n, m.st x = some ⟨true, some t⟩ → Sub n t → (∃ ty d es, n = .node ty c d es) →
      ValCapsInp n w := by
  rintro x t n hx hsn ⟨ty', d', es', rfl⟩
  rw [nodeAt_unique hM.heap (Or.inl ⟨x, t, hx, hsn, ty', d', es', rfl⟩) hn]; exact hc


/-- A borrowed value holds no node: what it reaches it reaches by handle. -/
theorem ValOK.no_node {m : Mem} {τ : Ty} {V : Val} {P H : List Dep} (h : ValOK m τ V P H) {ty : Ty}
    {c d : Nat} {es : List Val} (hs : Sub (.node ty c d es) V) : False := by
  induction h with
  | pair _ _ ih1 ih2 =>
    cases hs with
    | fst hs => exact ih1 hs
    | snd hs => exact ih2 hs
  | inl _ ih => cases hs with | inl hs => exact ih hs
  | inr _ ih => cases hs with | inr hs => exact ih hs
  | pkg _ _ ih => cases hs with | pkg hs => exact ih hs
  | dtor _ ih => exact ih hs
  | _ => cases hs

/-- ... and what a block owns holds no handle either. -/
theorem MInv.tree_no_href {m : Mem} {Γ : Ctx} (hM : MInv m Γ) {k : Nat} {bl : Blk} {c : Nat}
    (hk : m.blk k = some bl) (hs : Sub (.href c) bl.tree) : False := by
  obtain ⟨_, _, hpay, _⟩ := hM.blocks k bl hk
  obtain ⟨ty, kind, pay⟩ := bl
  cases kind <;> cases pay <;> simp only [Blk.tree, Option.getD] at hs
  all_goals first
    | exact ((hpay _ rfl).1).href_sub_false hs
    | (cases hs; done)

/-- A live slot's value: an owned tree holds no handle, and a borrowed one's
    handles reach clean nodes (the clause). -/
theorem LiveCaps.tgt {m : Mem} {Γ : Ctx} {w : Var} (h : LiveCaps m Γ w) (hM : MInv m Γ) {y : Var}
    {E : Entry} {o : Bool} {V : Val} (hy : Γ y = some E) (hl : E.live = true)
    (hs : m.st y = some ⟨o, some V⟩) {c : Nat} (hc : Sub (.href c) V) :
    ∀ x t n, m.st x = some ⟨true, some t⟩ → Sub n t → (∃ ty d es, n = .node ty c d es) → ValCapsInp n w :=
  (h y E o V hy hl hs).2 c hc



/-- A part `u` of a clean tree `N` that lies in an owned slot or a block
    lends only clean nodes: its handles are of nodes inside `N` (a tree
    there holds no handle of its own). -/
theorem MInv.tgt_lendOf {m : Mem} {Γ : Ctx} {w : Var} (hM : MInv m Γ) {N : Val}
    (hloc : (∃ x T, m.st x = some ⟨true, some T⟩ ∧ Sub N T) ∨ (∃ k bl, m.blk k = some bl ∧ Sub N bl.rd))
    (hN : ValCapsInp N w) {u : Val} (hu : Sub u N) {c : Nat} (hc : Sub (.href c) (lendOf u)) :
    ∀ x t n, m.st x = some ⟨true, some t⟩ → Sub n t → (∃ ty d es, n = .node ty c d es) → ValCapsInp n w := by
  rcases sub_href_lendOf hc with hh | ⟨ty, d, es, hn⟩
  · rcases hloc with ⟨x, T, hx, hsT⟩ | ⟨k, bl, hk, hsb⟩
    · exact (hM.slot_no_href hx ((hh.trans hu).trans hsT)).elim
    · exact (hM.rd_no_href hk ((hh.trans hu).trans hsb)).elim
  · have hnN := hn.trans hu
    refine hM.tgt_of_node ?_ (hN.sub hnN)
    rcases hloc with ⟨x, T, hx, hsT⟩ | ⟨k, bl, hk, hsb⟩
    · exact Or.inl ⟨x, T, hx, hnN.trans hsT, ty, d, es, rfl⟩
    · exact Or.inr ⟨k, bl, hk, hnN.trans hsb, ty, d, es, rfl⟩


/-- A live slot's value lends only clean nodes through the handles it holds:
    an owned tree holds none, a borrowed value's reach clean nodes. -/
theorem LiveCaps.slotTgt {m : Mem} {Γ : Ctx} {w : Var} (h : LiveCaps m Γ w) (hM : MInv m Γ) {y : Var}
    {E : Entry} {o : Bool} {V : Val} (hy : Γ y = some E) (hl : E.live = true)
    (hs : m.st y = some ⟨o, some V⟩) {c : Nat} (hc : Sub (.href c) V) :
    ∀ x t n, m.st x = some ⟨true, some t⟩ → Sub n t → (∃ ty d es, n = .node ty c d es) → ValCapsInp n w := by
  cases o
  · exact h.tgt hM hy hl hs hc
  · exact (hM.slot_no_href hs hc).elim

/-- A borrowed slot's value holds no node. -/
theorem MInv.bor_no_node {m : Mem} {Γ : Ctx} (hM : MInv m Γ) {y : Var} {E : Entry} {V : Val}
    (hy : Γ y = some E) (hl : E.live = true) (hs : m.st y = some ⟨false, some V⟩) {ty : Ty} {c d : Nat}
    {es : List Val} (hn : Sub (.node ty c d es) V) : False := by
  obtain ⟨sl, hsl, _, hown, _, hbor⟩ := hM.slot y E hy
  rw [hs] at hsl; cases hsl
  obtain ⟨V', hV', hvok⟩ := hbor (by rw [← hown]) hl
  cases hV'
  exact hvok.no_node hn

/-- ... so a part of a live slot's value lends only clean nodes. -/
theorem LiveCaps.partTgt {m : Mem} {Γ : Ctx} {w : Var} (h : LiveCaps m Γ w) (hM : MInv m Γ) {y : Var}
    {E : Entry} {o : Bool} {V : Val} (hy : Γ y = some E) (hl : E.live = true)
    (hs : m.st y = some ⟨o, some V⟩) {u : Val} (hu : Sub u V) {c : Nat} (hc : Sub (.href c) (lendOf u)) :
    ∀ x t n, m.st x = some ⟨true, some t⟩ → Sub n t → (∃ ty d es, n = .node ty c d es) → ValCapsInp n w := by
  cases o
  · rcases sub_href_lendOf hc with hh | ⟨ty, d, es, hn⟩
    · exact h.tgt hM hy hl hs (hh.trans hu)
    · exact (hM.bor_no_node hy hl hs (hn.trans hu)).elim
  · exact hM.tgt_lendOf (Or.inl ⟨y, V, hs, Sub.refl _⟩) (h.val hy hl hs) hu hc

/-- **What a typed right-hand side yields lends only clean nodes**: its
    handles are a live borrow's (the clause), or of nodes inside a tree it
    read, which is clean (`RhsT.liveCapsVal`'s reasoning) and lies in an
    owned slot or a block. -/
theorem RhsT.liveCapsTgt {m m1 : Mem} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    {v : Val} {o : Bool} {w : Var}
    (hr : RhsT Γ F r E Γ1) (he : EvalR m r (.ok v o m1)) (hM : MInv m Γ) (h : LiveCaps m Γ w) :
    ∀ c, Sub (.href c) v → ∀ x t n, m.st x = some ⟨true, some t⟩ → Sub n t →
      (∃ ty d es, n = .node ty c d es) → ValCapsInp n w := by
  intro c hc
  -- (a payload a block holds: no handle, `WFv`)
  have hpayNo : ∀ k bl V, m.blk k = some bl → bl.pay = some V → Sub (.href c) V → False :=
    fun k bl V hk hp hs => ((hM.blocks k bl hk).2.2.1 V hp).1.href_sub_false hs
  cases hr
  case borrow =>
    cases he
    · rename_i hv
      cases hc
      exact hM.tgt_of_node (Or.inl ⟨_, _, hv, Sub.refl _, _, _, _, rfl⟩) (h.val (by assumption) (by assumption) hv)
    · exact h.tgt hM (by assumption) (by assumption) (by assumption) hc
  case «at» =>
    cases he with
    | «at» hn hv _ =>
      obtain ⟨_, _, hv | ⟨hhr, hn'⟩⟩ := hv
      · exact hM.tgt_lendOf (Or.inl ⟨_, _, hv, Sub.refl _⟩) (h.val (by assumption) (by assumption) hv)
          (Sub.child (List.getElem_mem hn) (Sub.refl _)) hc
      · rcases hn' with ⟨x, t', hx, hs, hnd⟩ | ⟨k, bl, hk, hs, _⟩
        · exact hM.tgt_lendOf (Or.inl ⟨x, t', hx, hs⟩)
            ((h _ _ _ _ (by assumption) (by assumption) hhr).2 _ (Sub.refl _) x t' _ hx hs hnd)
            (Sub.child (List.getElem_mem hn) (Sub.refl _)) hc
        · exact hM.tgt_lendOf (Or.inr ⟨k, bl, hk, hs⟩) ((hM.rdCapsInp w hk).1.sub hs)
            (Sub.child (List.getElem_mem hn) (Sub.refl _)) hc
  case sat =>
    cases he with
    | sat hn hv _ _ _ hda =>
      have hN := hM.viewTargetCaps (by assumption) (by assumption) hv hda w
      rcases hda with ⟨x, t', hx, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
      · exact hM.tgt_lendOf (Or.inl ⟨x, t', hx, hs⟩) hN (Sub.child (List.getElem_mem hn) (Sub.refl _)) hc
      · exact hM.tgt_lendOf (Or.inr ⟨k, bl, hk, hs⟩) hN (Sub.child (List.getElem_mem hn) (Sub.refl _)) hc
  case arcGet =>
    cases he with
    | arcGet _ hk => exact hM.tgt_lendOf (Or.inr ⟨_, _, hk, Sub.refl _⟩) (hM.rdCapsInp w hk).1 (Sub.refl _) hc
  case glob =>
    cases he with
    | glob _ hf => rcases hf with ⟨_, _, _, _, rfl, _⟩ | ⟨_, _, _, _, rfl, _⟩ <;> cases hc
  case lockTake =>
    cases he with
    | lockTake _ hk _ => exact (hpayNo _ _ _ hk rfl hc).elim
  case chanRecv =>
    cases he with
    | chanRecv _ hk _ _ _ _ =>
      cases hc with
      | inr hc => exact (hpayNo _ _ _ hk rfl (Sub.fst (Sub.child (List.mem_cons_self ..) hc))).elim
    | chanRecvNone _ _ _ _ => cases hc with | inl hc => cases hc
  case rwTryRead =>
    cases he
    · cases hc with | inr hc => cases hc
    · cases hc with | inl hc => cases hc
  case rwTryWrite =>
    cases he
    · cases hc with | inr hc => cases hc
    · cases hc with | inl hc => cases hc
  case fst =>
    cases he with
    | fst hv => exact h.partTgt hM (by assumption) (by assumption) hv (Sub.fst (Sub.refl _)) hc
  case snd =>
    cases he with
    | snd hv => exact h.partTgt hM (by assumption) (by assumption) hv (Sub.snd (Sub.refl _)) hc
  case getl =>
    cases he with
    | getl hv => exact h.partTgt hM (by assumption) (by assumption) hv (Sub.inl (Sub.refl _)) hc
  case getr =>
    cases he with
    | getr hv => exact h.partTgt hM (by assumption) (by assumption) hv (Sub.inr (Sub.refl _)) hc
  case pop =>
    cases he with
    | pop hv _ _ => exact (hM.slot_no_href hv (Sub.child (by simp) hc)).elim
  case remove =>
    cases he with
    | remove hn hv _ _ _ => exact (hM.slot_no_href hv (Sub.child (List.getElem_mem hn) hc)).elim
  case takel =>
    cases he with
    | takel hv => exact (hM.slot_no_href hv (Sub.inl hc)).elim
  case taker =>
    cases he with
    | taker hv => exact (hM.slot_no_href hv (Sub.inr hc)).elim
  case inl hy hl _ _ =>
    cases he with
    | inl h1 =>
      obtain ⟨_, hs1⟩ := h1.slot
      cases hc with | inl hc => exact h.slotTgt hM hy hl hs1 hc
  case inr hy hl _ _ =>
    cases he with
    | inr h1 =>
      obtain ⟨_, hs1⟩ := h1.slot
      cases hc with | inr hc => exact h.slotTgt hM hy hl hs1 hc
  case pack hy hl _ _ _ _ =>
    cases he with
    | pack h1 =>
      obtain ⟨_, hs1⟩ := h1.slot
      cases hc with | pkg hc => exact h.slotTgt hM hy hl hs1 hc
  case pair y z Ey Ez Γa Dy Dz hy hl hpa1 hz hl2 hpa2 _ =>
    cases he with
    | @pair _ _ v1 v2 m1' m2' h1 h2 =>
      obtain ⟨_, hs1⟩ := h1.slot
      obtain ⟨_, hs2⟩ := h2.slot
      have hs2' : ∃ o, m.st z = some ⟨o, some v2⟩ := by
        rcases h1.st_of z with he | he
        · rw [he] at hs2; exact ⟨_, hs2⟩
        · rw [he] at hs2; cases hs2
      obtain ⟨_, hs2'⟩ := hs2'
      obtain ⟨Ez0, hz0, hl0⟩ := hpa1.liveBack _ _ hz hl2
      cases hc with
      | fst hc => exact h.slotTgt hM hy hl hs1 hc
      | snd hc => exact h.slotTgt hM hz0 hl0 hs2' hc
  all_goals cases he
  all_goals first
    | (cases hc; done)
    | (cases hc with | child he _ => simp at he)
    | exact h.tgt hM (by assumption) (by assumption) (by assumption) hc
    | exact (hM.slot_no_href (by assumption) hc).elim

/-- A node in the slots a typed right-hand side leaves was in the slots
    before, or is clean (the read slot shrunk, or given an empty node). -/
theorem RhsT.st_back {m m1 : Mem} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    {v : Val} {o : Bool} {w : Var}
    (hr : RhsT Γ F r E Γ1) (he : EvalR m r (.ok v o m1)) (h : LiveCaps m Γ w) :
    ∀ x t n, m1.st x = some ⟨true, some t⟩ → Sub n t →
      (∃ t', m.st x = some ⟨true, some t'⟩ ∧ Sub n t') ∨ ValCapsInp n w := by
  -- a slot set to `none`, or a `TakeVal`'s, keeps every other slot
  have hnone : ∀ (m' : Mem) y o', ∀ x t n, (m'.set y ⟨o', none⟩).st x = some ⟨true, some t⟩ →
      Sub n t → (∃ t', m'.st x = some ⟨true, some t'⟩ ∧ Sub n t') := by
    intro m' y o' x t n hx hsn
    by_cases hxy : x = y
    · subst hxy; simp at hx
    · simp [upd_ne _ _ hxy] at hx; exact ⟨t, hx, hsn⟩
  have htv : ∀ {m' m'' : Mem} {y : Var} {u : Val}, TakeVal m' y u m'' → ∀ x t n,
      m''.st x = some ⟨true, some t⟩ → Sub n t → (∃ t', m'.st x = some ⟨true, some t'⟩ ∧ Sub n t') := by
    intro m' m'' y u ht x t n hx hsn
    cases ht with
    | own _ => exact hnone _ _ _ x t n hx hsn
    | bor _ => exact ⟨t, hx, hsn⟩
  have hset : ∀ (y : Var) (o' : Bool) (N : Val), (∀ n, Sub n N → ValCapsInp n w) → ∀ x t n,
      (m.set y ⟨o', some N⟩).st x = some ⟨true, some t⟩ → Sub n t →
      (∃ t', m.st x = some ⟨true, some t'⟩ ∧ Sub n t') ∨ ValCapsInp n w := by
    intro y o' N hN x t n hx hsn
    by_cases hxy : x = y
    · subst hxy; simp at hx; obtain ⟨_, rfl⟩ := hx; exact Or.inr (hN n hsn)
    · simp [upd_ne _ _ hxy] at hx; exact Or.inl ⟨t, hx, hsn⟩
  have hset' : ∀ (m0 : Mem) (y : Var) (N : Val), (∀ n, Sub n N → ValCapsInp n w) → m0.st = m.st → ∀ x t n,
      (m0.set y ⟨true, some N⟩).st x = some ⟨true, some t⟩ → Sub n t →
      (∃ t', m.st x = some ⟨true, some t'⟩ ∧ Sub n t') ∨ ValCapsInp n w := by
    intro m0 y N hN hst x t n hx hsn
    by_cases hxy : x = y
    · subst hxy; simp at hx; obtain ⟨_, rfl⟩ := hx; exact Or.inr (hN n hsn)
    · simp [upd_ne _ _ hxy] at hx; rw [hst] at hx; exact Or.inl ⟨t, hx, hsn⟩
  intro x t n hx hsn
  cases hr
  case pop =>
    cases he with
    | pop hv _ _ =>
      exact hset _ _ _ ((h.val (by assumption) (by assumption) hv).shrink (fun e he => List.mem_append_left _ he)) x t n hx hsn
  case remove =>
    cases he with
    | remove hn hv _ _ _ =>
      exact hset _ _ _ ((h.val (by assumption) (by assumption) hv).shrink (fun e he => List.mem_of_mem_eraseIdx he)) x t n hx hsn
  case take =>
    cases he with
    | take hv =>
      refine hset' _ _ _ (fun n hsn => ?_) rfl x t n hx hsn
      cases hsn with
      | refl =>
        refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
        cases hc with | elem he => simp at he
      | child he _ => simp at he
  case pair =>
    cases he with
    | pair h1 h2 =>
      obtain ⟨t', hx', hs'⟩ := htv h2 x t n hx hsn
      exact Or.inl (htv h1 x t' n hx' hs')
  case arcNew =>
    cases he
    obtain ht : TakeVal _ _ _ _ := by assumption
    exact Or.inl (htv ht x t n hx hsn)
  case lockNew =>
    cases he
    obtain ht : TakeVal _ _ _ _ := by assumption
    exact Or.inl (htv ht x t n hx hsn)
  case cellNew =>
    cases he
    obtain ht : TakeVal _ _ _ _ := by assumption
    exact Or.inl (htv ht x t n hx hsn)
  case lockRestore =>
    cases he
    obtain ht : TakeVal _ _ _ _ := by assumption
    exact Or.inl (htv ht x t n hx hsn)
  case chanSend =>
    cases he
    · obtain ht : TakeVal _ _ _ _ := by assumption
      exact Or.inl (htv ht x t n hx hsn)
    · obtain ht : TakeVal _ _ _ _ := by assumption
      exact Or.inl (htv ht x t n hx hsn)
  all_goals cases he
  all_goals first
    | exact Or.inl ⟨t, hx, hsn⟩
    | exact Or.inl (hnone _ _ _ x t n hx hsn)
    | exact Or.inl (htv ‹TakeVal _ _ _ _› x t n hx hsn)


/-- **A binding given the value of a typed right-hand side keeps the
    clause**: the value is clean (`liveCapsVal`), its handles reach clean
    nodes (`liveCapsTgt`, through `st_back`), and the store it left keeps
    the clause (`liveCapsSt`). -/
theorem RhsT.liveCapsSet {m m1 : Mem} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    {v : Val} {o : Bool} {w : Var}
    (hr : RhsT Γ F r E Γ1) (he : EvalR m r (.ok v o m1)) (hM : MInv m Γ) (h : LiveCaps m Γ w)
    (hw : w ∉ r.vars) {x : Var} {o' : Bool} {Γ' : Ctx}
    (hb : ∀ u E1, u ≠ x → Γ' u = some E1 → E1.live = true → ∃ E0, Γ1 u = some E0 ∧ E0.live = true) :
    LiveCaps (m1.set x ⟨o', some v⟩) Γ' w := by
  refine (hr.liveCapsSt he h).setG hb (fun V e => ?_)
  cases e
  refine ⟨fun n hn => (hr.liveCapsVal he hM h hw).sub hn, fun c hc x' t n hx' hsn hnd => ?_⟩
  rcases hr.st_back he h x' t n hx' hsn with ⟨t', hx'', hs''⟩ | hn
  · exact hr.liveCapsTgt he hM h c hc x' t' n hx'' hs'' hnd
  · exact hn


/-- **A step that changes slots only to clean values with no handle keeps
    the clause**, where the context ends bindings at most: an unchanged live
    value's handles reach a node in an unchanged slot (the clause) or in a
    changed one (clean), and a changed slot's value is clean. -/
theorem LiveCaps.of_change {m m' : Mem} {Γ Γ' : Ctx} {w : Var} (h : LiveCaps m Γ w) (hb : LiveBack Γ Γ')
    (hch : ∀ x o V', m'.st x = some ⟨o, some V'⟩ → m'.st x ≠ m.st x →
      (∀ n, Sub n V' → ValCapsInp n w) ∧ ∀ c, Sub (.href c) V' → False) :
    LiveCaps m' Γ' w := by
  intro v E o V hv hl hs
  -- a slot-located node after the step: in an unchanged slot, or clean
  have hloc : ∀ x t n, m'.st x = some ⟨true, some t⟩ → Sub n t →
      (m.st x = some ⟨true, some t⟩) ∨ ValCapsInp n w := by
    intro x t n hx hsn
    by_cases heq : m'.st x = m.st x
    · rw [heq] at hx; exact Or.inl hx
    · exact Or.inr ((hch x true t hx heq).1 n hsn)
  by_cases heq : m'.st v = m.st v
  · rw [heq] at hs
    obtain ⟨E0, h0, hl0⟩ := hb v E hv hl
    obtain ⟨h1, h2⟩ := h v E0 o V h0 hl0 hs
    refine ⟨h1, fun c hc x t n hx hsn hnd => ?_⟩
    rcases hloc x t n hx hsn with hx' | hn
    · exact h2 c hc x t n hx' hsn hnd
    · exact hn
  · obtain ⟨hsub, hnh⟩ := hch v o V hs heq
    exact ⟨hsub V (Sub.refl _), fun c hc => (hnh c hc).elim⟩


/-- ... in its precise form: a changed slot need not be clean throughout
    (its owner may be dead). It suffices that a live changed value is clean
    with no handle, and that each node in a changed slot is clean or is
    what an old node at the same handle became, clean if that one was. -/
theorem LiveCaps.of_changeR {m m' : Mem} {Γ Γ' : Ctx} {w : Var} (h : LiveCaps m Γ w)
    (hb : ∀ x E1, Γ' x = some E1 → E1.live = true → m'.st x = m.st x → ∃ E0, Γ x = some E0 ∧ E0.live = true)
    (hval : ∀ x E o V', Γ' x = some E → E.live = true → m'.st x = some ⟨o, some V'⟩ → m'.st x ≠ m.st x →
      ValCapsInp V' w ∧ ∀ c, Sub (.href c) V' → False)
    (hnode : ∀ x t' n', m'.st x = some ⟨true, some t'⟩ → m'.st x ≠ m.st x → Sub n' t' →
      ∀ ty c d es, n' = .node ty c d es → ValCapsInp n' w ∨
        ∃ x0 t n, m.st x0 = some ⟨true, some t⟩ ∧ Sub n t ∧ (∃ ty d es, n = .node ty c d es) ∧
          (ValCapsInp n w → ValCapsInp n' w)) :
    LiveCaps m' Γ' w := by
  intro v E o V hv hl hs
  by_cases heq : m'.st v = m.st v
  · obtain ⟨E0, h0, hl0⟩ := hb v E hv hl heq
    rw [heq] at hs
    obtain ⟨h1, h2⟩ := h v E0 o V h0 hl0 hs
    refine ⟨h1, fun c hc x t n hx hsn hnd => ?_⟩
    by_cases hxe : m'.st x = m.st x
    · rw [hxe] at hx; exact h2 c hc x t n hx hsn hnd
    · obtain ⟨ty, d, es, rfl⟩ := hnd
      rcases hnode x t _ hx hxe hsn ty c d es rfl with hn | ⟨x0, t0, n0, hx0, hs0, hnd0, himp⟩
      · exact hn
      · exact himp (h2 c hc x0 t0 n0 hx0 hs0 hnd0)
  · obtain ⟨hcl, hnh⟩ := hval v E o V hv hl hs heq
    exact ⟨hcl, fun c hc => (hnh c hc).elim⟩


/-- A node in a changed tree is clean, or is what a node of the old tree at
    the same handle became, clean if that one was. -/
def NodeBack (w : Var) (T x : Val) : Prop :=
  ∀ ty c d es, x = .node ty c d es → ValCapsInp x w ∨
    ∃ y, Sub y T ∧ (∃ ty d es, y = .node ty c d es) ∧ (ValCapsInp y w → ValCapsInp x w)

theorem NodeBack.of_sub {w : Var} {T x : Val} (hx : Sub x T) : NodeBack w T x :=
  fun ty c d es hxe => Or.inr ⟨x, hx, ⟨ty, d, es, hxe⟩, id⟩

theorem NodeBack.mono {w : Var} {T T' x : Val} (h : NodeBack w T x) (hT : ∀ y, Sub y T → Sub y T') :
    NodeBack w T' x := fun ty c d es hxe => by
  rcases h ty c d es hxe with h | ⟨y, hy, hnd, himp⟩
  · exact Or.inl h
  · exact Or.inr ⟨y, hT y hy, hnd, himp⟩

theorem Repl.old_sub {n n' T T' : Val} (hr : Repl n n' T T') : Sub n T := by
  induction hr with
  | here => exact Sub.refl _
  | elem _ ih => exact Sub.child (List.mem_append_right _ (List.mem_cons_self ..)) ih
  | fst _ ih => exact Sub.fst ih
  | snd _ ih => exact Sub.snd ih
  | inl _ ih => exact Sub.inl ih
  | inr _ ih => exact Sub.inr ih
  | pkg _ ih => exact Sub.pkg ih

/-- **The nodes of a tree after a replacement** are the new node's (as its
    own hypothesis says), the old tree's, or rebuilt ones on the way to it,
    each at its old handle and clean if the old one was (`Repl.capsInp`). -/
theorem Repl.nodesBack {n n' T T' : Val} {w : Var} (hr : Repl n n' T T')
    (hcl : ValCapsInp n w → ValCapsInp n' w) (hn' : ∀ x, Sub x n' → NodeBack w n x) :
    ∀ x, Sub x T' → NodeBack w T x := by
  induction hr with
  | here => exact hn'
  | @elem t c d pre post e e' he ih =>
    intro x hx
    cases hx with
    | refl =>
      intro ty c' d' es' hxe
      cases hxe
      refine Or.inr ⟨_, Sub.refl _, ⟨t, d, _, rfl⟩, fun hT => ?_⟩
      exact (Repl.elem he).capsInp hT (hcl (hT.sub (Repl.elem (pre := pre) (post := post) (t := t) (c := c) (d := d) he).old_sub))
    | child hm hs =>
      rcases List.mem_append.mp hm with hm | hm
      · exact NodeBack.of_sub (Sub.child (List.mem_append_left _ hm) hs)
      · rcases List.mem_cons.mp hm with rfl | hm
        · exact (ih x hs).mono fun y hy =>
            Sub.child (List.mem_append_right _ (List.mem_cons_self ..)) hy
        · exact NodeBack.of_sub (Sub.child (List.mem_append_right _ (List.mem_cons_of_mem _ hm)) hs)
  | fst _ ih =>
    intro x hx
    cases hx with
    | refl => intro _ _ _ _ h; cases h
    | fst hs => exact (ih x hs).mono fun y hy => Sub.fst hy
    | snd hs => exact NodeBack.of_sub (Sub.snd hs)
  | snd _ ih =>
    intro x hx
    cases hx with
    | refl => intro _ _ _ _ h; cases h
    | fst hs => exact NodeBack.of_sub (Sub.fst hs)
    | snd hs => exact (ih x hs).mono fun y hy => Sub.snd hy
  | inl _ ih =>
    intro x hx
    cases hx with
    | refl => intro _ _ _ _ h; cases h
    | inl hs => exact (ih x hs).mono fun y hy => Sub.inl hy
  | inr _ ih =>
    intro x hx
    cases hx with
    | refl => intro _ _ _ _ h; cases h
    | inr hs => exact (ih x hs).mono fun y hy => Sub.inr hy
  | pkg _ ih =>
    intro x hx
    cases hx with
    | refl => intro _ _ _ _ h; cases h
    | pkg hs => exact (ih x hs).mono fun y hy => Sub.pkg hy


theorem LiveBack.killNames (ds : List Dep) (Γ : Ctx) : LiveBack Γ (A2.killNames ds Γ) := by
  induction ds with
  | nil => exact LiveBack.refl _
  | cons d ds ih => exact ih.trans (LiveBack.kill _ _ _ _)

theorem LiveBack.killHv (ks : List (Eff × Bool × Var)) (Γ : Ctx) : LiveBack Γ (A2.killHv ks Γ) := by
  induction ks with
  | nil => exact LiveBack.refl _
  | cons k ks ih => obtain ⟨e, hv, r⟩ := k; exact ih.trans (LiveBack.kill _ _ _ _)

theorem LiveBack.killThru (op : Edit) (tx : Ty) (P : List Dep) (Γ : Ctx) : LiveBack Γ (A2.killThru op tx P Γ) :=
  LiveBack.killNames _ _

theorem LiveBack.killThruV (op : Edit) (tx : Ty) (P : List Dep) (Γ : Ctx) : LiveBack Γ (A2.killThruV op tx P Γ) :=
  LiveBack.killHv _ _

/-- **A change through a borrow keeps the clause**: the owner's tree `T`
    becomes `T'`, one node `n` in it replaced by `n'`. If the owner is live
    its tree was clean, and stays so; a live handle reaching a node of the
    new tree reaches it at an old node's address, clean if that one was. -/
theorem LiveCaps.repl {m m' : Mem} {Γ Γ' : Ctx} {w r : Var} {T T' n n' : Val}
    (h : LiveCaps m Γ w) (hb : LiveBack Γ Γ') (hT : m.st r = some ⟨true, some T⟩)
    (hrp : Repl n n' T T') (hr' : m'.st r = some ⟨true, some T'⟩) (hne : ∀ x, x ≠ r → m'.st x = m.st x)
    (hcl : ValCapsInp n w → ValCapsInp n' w) (hn' : ∀ x, Sub x n' → NodeBack w n x)
    (hnoh : ∀ c, Sub (.href c) T' → False) :
    LiveCaps m' Γ' w := by
  have hnb := hrp.nodesBack hcl hn'
  refine h.of_changeR (fun x E1 hx hl _ => hb x E1 hx hl) (fun x E o V' hx hl hs hch => ?_)
    (fun x t' n2 hx hch hs ty c d es hn2 => ?_)
  · have hxr : x = r := by
      by_cases e : x = r
      · exact e
      · exact absurd (hne x e) hch
    subst hxr
    rw [hr'] at hs; cases hs
    obtain ⟨E0, h0, hl0⟩ := hb x E hx hl
    have hTc := (h x E0 true T h0 hl0 hT).1
    exact ⟨hrp.capsInp hTc (hcl (hTc.sub hrp.old_sub)), hnoh⟩
  · have hxr : x = r := by
      by_cases e : x = r
      · exact e
      · exact absurd (hne x e) hch
    subst hxr
    rw [hr'] at hx; cases hx
    rcases hnb n2 hs ty c d es hn2 with hc | ⟨y, hy, hnd, himp⟩
    · exact Or.inl hc
    · exact Or.inr ⟨x, T, y, hT, hy, hnd, himp⟩


/-- **An edit of a `Vec` node through its owner** (`NodeOf`): the node
    `⟨t, c, d, es⟩` becomes `⟨t, c, d', es'⟩` at the same handle, each new
    element an old one or clean throughout, so the clause carries over. -/
theorem LiveCaps.editNodeH {m1 m' : Mem} {Γ1 Γ' : Ctx} {w x o : Var} {T T' : Val} {t : Ty}
    {c d d' : Nat} {es es' : List Val}
    (h : LiveCaps m1 Γ1 w) (hb : LiveBack Γ1 Γ') (hno : NodeOf m1 x o T t c d es)
    (hrp : Repl (.node t c d es) (.node t c d' es') T T')
    (hr' : m'.st o = some ⟨true, some T'⟩) (hne : ∀ z, z ≠ o → m'.st z = m1.st z)
    (hcl : ValCapsInp (.node t c d es) w → ValCapsInp (.node t c d' es') w)
    (hel : ∀ e ∈ es', e ∈ es ∨ ∀ z, Sub z e → ValCapsInp z w) (hnoh : ∀ c, Sub (.href c) T' → False) :
    LiveCaps m' Γ' w := by
  obtain ⟨_, _, ho, _⟩ := hno
  refine h.repl hb ho hrp hr' hne hcl (fun z hz => ?_) hnoh
  cases hz with
  | refl =>
    intro ty c2 d2 es2 heq
    cases heq
    exact Or.inr ⟨_, Sub.refl _, ⟨t, d, es, rfl⟩, hcl⟩
  | child hm hs =>
    rcases hel _ hm with he | hc
    · exact NodeBack.of_sub (Sub.child he hs)
    · exact fun _ _ _ _ _ => Or.inl (hc _ hs)


theorem LiveBack.holdThru (D P : List Dep) (Γ : Ctx) : LiveBack Γ (A2.holdThru D P Γ) := fun v E1 h hl => by
  simp only [A2.holdThru, A2.holdOn] at h
  obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp h
  refine ⟨E, hE, ?_⟩
  split at hl
  · simpa using hl
  · exact hl


/-- A slot given a clean value with no handle keeps the clause. -/
theorem LiveCaps.setClean {m : Mem} {Γ Γ' : Ctx} {w y : Var} {o : Bool} {V : Val} (h : LiveCaps m Γ w)
    (hb : ∀ x E1, x ≠ y → Γ' x = some E1 → E1.live = true → ∃ E0, Γ x = some E0 ∧ E0.live = true)
    (hv : ValCapsInp V w) (hnh : ∀ c, Sub (.href c) V → False) :
    LiveCaps (m.set y ⟨o, some V⟩) Γ' w :=
  h.setG hb fun V' e => by cases e; exact ⟨fun n hn => hv.sub hn, fun c hc => (hnh c hc).elim⟩


/-- **Splitting a live pair into two fresh slots keeps the clause**: the
    halves were the pair's, clean, and their handles reach what the pair's
    reached. -/
theorem LiveCaps.unpair {m : Mem} {Γ Γ' : Ctx} {w y x z : Var} {E : Entry} {o oa ob : Bool} {a b : Val}
    (h : LiveCaps m Γ w) (hy : Γ y = some E) (hl : E.live = true)
    (hvy : m.st y = some ⟨o, some (.pair a b)⟩) (hxy : x ≠ y) (hzy : z ≠ y) (hxz : x ≠ z)
    (hb : ∀ u E1, u ≠ x → u ≠ z → Γ' u = some E1 → E1.live = true → ∃ E0, Γ u = some E0 ∧ E0.live = true) :
    LiveCaps (((m.set y ⟨true, none⟩).set x ⟨oa, some a⟩).set z ⟨ob, some b⟩) Γ' w := by
  obtain ⟨hP, hPt⟩ := h y E o _ hy hl hvy
  have htg : ∀ x' t n, (((m.set y ⟨true, none⟩).set x ⟨oa, some a⟩).set z ⟨ob, some b⟩).st x' = some ⟨true, some t⟩ →
      Sub n t → m.st x' = some ⟨true, some t⟩ ∨ ValCapsInp n w := by
    intro x' t n hx' hsn
    by_cases e1 : x' = z
    · subst e1; simp [Mem.set, upd] at hx'; obtain ⟨-, rfl⟩ := hx'
      exact Or.inr (hP.sub (Sub.snd hsn))
    by_cases e2 : x' = x
    · subst e2; simp [Mem.set, upd, e1] at hx'; obtain ⟨-, rfl⟩ := hx'
      exact Or.inr (hP.sub (Sub.fst hsn))
    by_cases e3 : x' = y
    · subst e3; simp [Mem.set, upd, e1, e2] at hx'
    · simp [Mem.set, upd, e1, e2, e3] at hx'; exact Or.inl hx'
  have hfin : ∀ V, Sub V (.pair a b) → ∀ c, Sub (.href c) V → ∀ x' t n,
      (((m.set y ⟨true, none⟩).set x ⟨oa, some a⟩).set z ⟨ob, some b⟩).st x' = some ⟨true, some t⟩ →
      Sub n t → (∃ ty d es, n = .node ty c d es) → ValCapsInp n w := by
    intro V hV c hc x' t n hx' hsn hnd
    rcases htg x' t n hx' hsn with hx'' | hn
    · exact hPt c (Sub.trans hc hV) x' t n hx'' hsn hnd
    · exact hn
  intro v E1 o1 V hv hl1 hs
  by_cases e1 : v = z
  · subst e1; simp [Mem.set, upd] at hs; obtain ⟨-, rfl⟩ := hs
    exact ⟨hP.sub (Sub.snd (Sub.refl _)), hfin _ (Sub.snd (Sub.refl _))⟩
  by_cases e2 : v = x
  · subst e2; simp [Mem.set, upd, e1] at hs; obtain ⟨-, rfl⟩ := hs
    exact ⟨hP.sub (Sub.fst (Sub.refl _)), hfin _ (Sub.fst (Sub.refl _))⟩
  by_cases e3 : v = y
  · subst e3; simp [Mem.set, upd, e1, e2] at hs
  simp [Mem.set, upd, e1, e2, e3] at hs
  obtain ⟨E0, h0, hl0⟩ := hb v E1 e2 e1 hv hl1
  obtain ⟨h1, h2⟩ := h v E0 o1 V h0 hl0 hs
  refine ⟨h1, fun c hc x' t n hx' hsn hnd => ?_⟩
  rcases htg x' t n hx' hsn with hx'' | hn
  · exact h2 c hc x' t n hx'' hsn hnd
  · exact hn


/-- A block's payload holds no handle. -/
theorem MInv.pay_no_href {m : Mem} {Γ : Ctx} (hM : MInv m Γ) {k : Nat} {bl : Blk} {V : Val} {c : Nat}
    (hk : m.blk k = some bl) (hp : bl.pay = some V) (hs : Sub (.href c) V) : False := by
  obtain ⟨_, _, hpay, _⟩ := hM.blocks k bl hk
  exact ((hpay V hp).1).href_sub_false hs


/-- **A panicking step writes no slot**: it ends bindings (the running
    scopes' unwind) and frees, so each slot left is one it found. -/
theorem Step.panic_st {P : Prog} {m m' : Mem} {s : Stmt} (h : Step P m s (.panic m')) :
    ∀ x sl, m'.st x = some sl → m.st x = some sl := by
  generalize hr : Res.panic m' = r at h
  induction h generalizing m'
  all_goals first
    | (cases hr; done)
    | (cases hr; intro x sl h; exact h)
    | (cases hr; rename_i ih; intro x sl h; exact ih rfl x sl h)
    | skip
  case scopeLP ih =>
    cases hr
    intro x sl h
    rename_i hrl
    cases hrl <;>
    · simp only [Mem.remove, upd] at h; split at h
      · cases h
      · exact ih rfl x sl h
  all_goals
    cases hr
    rename_i ih
    intro x sl h
    simp only [Mem.remove, upd] at h; split at h
    · cases h
    · exact ih rfl x sl h


/-- An owning binding whose type holds no function holds a value with no
    package and no handle. -/
theorem MInv.own_noFn {m : Mem} {Γ : Ctx} (hM : MInv m Γ) {x : Var} {E : Entry} {o : Bool} {V : Val}
    (hE : Γ x = some E) (hos : E.mode.ownSlot = true) (hf : E.ty.hasFn = false)
    (hs : m.st x = some ⟨o, some V⟩) : V.names = [] ∧ ∀ c, Sub (.href c) V → False := by
  obtain ⟨sl, hsl, _, _, howning, _⟩ := hM.slot x E hE
  rw [hs] at hsl; cases hsl
  have hw := (howning hos).2.1 V rfl
  exact ⟨hw.names_nil_fn hf, fun c hc => hw.href_sub_false hc⟩

/-- **The clause across a step that only ends slots**, where the context
    ends bindings but one, `x`, whose live value is clean with no handle. -/
theorem LiveCaps.of_shrink {m m' : Mem} {Γ Γ' : Ctx} {w x : Var} (h : LiveCaps m Γ w)
    (hp : ∀ y sl, m'.st y = some sl → m.st y = some sl)
    (hb : ∀ u E1, u ≠ x → Γ' u = some E1 → E1.live = true → ∃ E0, Γ u = some E0 ∧ E0.live = true)
    (hx : ∀ E1 o V, Γ' x = some E1 → E1.live = true → m'.st x = some ⟨o, some V⟩ →
      ValCapsInp V w ∧ ∀ c, Sub (.href c) V → False) :
    LiveCaps m' Γ' w := by
  intro v E o V hv hl hs
  by_cases hvx : v = x
  · subst hvx
    obtain ⟨h1, h2⟩ := hx E o V hv hl hs
    exact ⟨h1, fun c hc => (h2 c hc).elim⟩
  · obtain ⟨E0, h0, hl0⟩ := hb v E hvx hv hl
    obtain ⟨h1, h2⟩ := h v E0 o V h0 hl0 (hp v _ hs)
    exact ⟨h1, fun c hc x' t n hx' hsn hnd => h2 c hc x' t n (hp x' _ hx') hsn hnd⟩


theorem LiveCaps.editNode {m1 m' : Mem} {Γ1 Γ' Γ'' : Ctx} {w x o : Var} {T T' : Val} {t : Ty}
    {c d d' : Nat} {es es' : List Val}
    (h : LiveCaps m1 Γ1 w) (hb : LiveBack Γ1 Γ') (hno : NodeOf m1 x o T t c d es)
    (hrp : Repl (.node t c d es) (.node t c d' es') T T')
    (hr' : m'.st o = some ⟨true, some T'⟩) (hne : ∀ z, z ≠ o → m'.st z = m1.st z)
    (hcl : ValCapsInp (.node t c d es) w → ValCapsInp (.node t c d' es') w)
    (hel : ∀ e ∈ es', e ∈ es ∨ ∀ z, Sub z e → ValCapsInp z w) (hM : MInv m' Γ'') :
    LiveCaps m' Γ' w :=
  h.editNodeH hb hno hrp hr' hne hcl hel fun _ hc => hM.slot_no_href hr' hc

/-- **The node a live binding reaches** (itself, or through its handle) is
    clean. -/
theorem LiveCaps.nodeOf {m : Mem} {Γ : Ctx} {w x o : Var} {E : Entry} {T : Val} {t : Ty} {c d : Nat}
    {es : List Val} (h : LiveCaps m Γ w) (hx : Γ x = some E) (hl : E.live = true)
    (hno : NodeOf m x o T t c d es) : ValCapsInp (.node t c d es) w := by
  obtain ⟨_, _, ho, hor⟩ := hno
  rcases hor with ⟨rfl, rfl⟩ | ⟨hsx, hs⟩
  · exact (h _ E true _ hx hl ho).1
  · exact (h x E false _ hx hl hsx).2 c (Sub.refl _) o T _ ho hs ⟨t, d, es, rfl⟩


theorem LiveBack.exitScope (x : Var) (Γ : Ctx) : LiveBack Γ (A2.exitScope x Γ) := fun v E1 h hl => by
  by_cases hvx : v = x
  · subst hvx; simp [A2.exitScope, upd] at h
  · simp only [A2.exitScope, upd_ne _ _ hvx] at h
    exact LiveBack.kill Γ _ _ _ v E1 h hl

end A2
