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
        · exact (((h _ _ _ _ (by assumption) (by assumption) hhr).2.1 _ rfl x t' _ hx hs hnd).child
            (Child.elem (List.getElem_mem hn))).lend
        · exact (((hM.rdCapsInp w hk).1.sub hs).child (Child.elem (List.getElem_mem hn))).lend
  case sat =>
    cases he with
    | sat hn hv _ _ _ hda =>
      rcases hda with ⟨x, t', hx, hs, hnd⟩ | ⟨k, bl, hk, hs, _⟩
      · exact (((h _ _ _ _ (by assumption) (by assumption) hv).2.2 _ _ _ rfl x t' _ hx hs hnd).child
          (Child.elem (List.getElem_mem hn))).lend
      · exact (((hM.rdCapsInp w hk).1.sub hs).child (Child.elem (List.getElem_mem hn))).lend
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


/-- Ending bindings keeps the clause: it speaks of the live ones only. -/
theorem LiveCaps.of_back {m : Mem} {Γ Γ' : Ctx} {w : Var} (h : LiveCaps m Γ w) (hb : LiveBack Γ Γ') :
    LiveCaps m Γ' w := fun v E o V hv hl hs => by
  obtain ⟨E0, h0, hl0⟩ := hb v E hv hl
  exact h v E0 o V h0 hl0 hs

/-- ... and so does a store with the same slots. -/
theorem LiveCaps.of_st {m m' : Mem} {Γ : Ctx} {w : Var} (h : LiveCaps m Γ w) (hst : m'.st = m.st) :
    LiveCaps m' Γ w := fun v E o V hv hl hs => by
  rw [hst] at hs
  obtain ⟨h1, h2, h3⟩ := h v E o V hv hl hs
  exact ⟨h1, fun c hc x t n hx => h2 c hc x t n (hst ▸ hx), fun d o' l hd x t n hx => h3 d o' l hd x t n (hst ▸ hx)⟩


/-- Setting a slot to a value no part of which captures `w` but read-only,
    and which is no handle or view, keeps the clause: the live values and the
    targets in the other slots are as they were, and every node in the new
    value is clean. -/
theorem LiveCaps.set {m : Mem} {Γ : Ctx} {w : Var} (h : LiveCaps m Γ w) {y : Var} {o : Bool}
    {v : Option Val} (hv : ∀ V, v = some V → (∀ n, Sub n V → ValCapsInp n w) ∧
      (∀ c, V ≠ .href c) ∧ (∀ d o' l, V ≠ .view d o' l)) :
    LiveCaps (m.set y ⟨o, v⟩) Γ w := by
  intro x E o1 V hx hl hs
  -- a target in the slots after the set: in `y`'s new value, or where it was
  have htgt : ∀ x' t n, (m.set y ⟨o, v⟩).st x' = some ⟨true, some t⟩ → Sub n t →
      (m.st x' = some ⟨true, some t⟩) ∨ ValCapsInp n w := by
    intro x' t n hx' hsn
    by_cases hxy : x' = y
    · subst hxy; simp at hx'; obtain ⟨_, rfl⟩ := hx'; exact Or.inr ((hv t rfl).1 n hsn)
    · simp [upd_ne _ _ hxy] at hx'; exact Or.inl hx'
  by_cases hxy : x = y
  · subst hxy
    simp at hs; obtain ⟨_, rfl⟩ := hs
    obtain ⟨hsub, hnh, hnv⟩ := hv V rfl
    exact ⟨hsub V (Sub.refl _), fun c hc => absurd hc (hnh c), fun d o' l hd => absurd hd (hnv d o' l)⟩
  · simp [upd_ne _ _ hxy] at hs
    obtain ⟨h1, h2, h3⟩ := h x E o1 V hx hl hs
    refine ⟨h1, fun c hc x' t n hx' hsn hnd => ?_, fun d o' l hd x' t n hx' hsn hnd => ?_⟩
    · rcases htgt x' t n hx' hsn with hx'' | hn
      · exact h2 c hc x' t n hx'' hsn hnd
      · exact hn
    · rcases htgt x' t n hx' hsn with hx'' | hn
      · exact h3 d o' l hd x' t n hx'' hsn hnd
      · exact hn

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
      refine ⟨hT.shrink (fun e he => List.mem_append_left _ he), fun c hc => ?_, fun d o l hd => ?_⟩
      · cases hc
      · cases hd
  case remove =>
    obtain hv : m.st _ = some ⟨true, some (.node _ _ _ _)⟩ := by assumption
    cases hr with
    | remove hy hl _ _ _ _ _ =>
      have hT := h.val hy hl hv
      refine LiveCaps.set h' (fun V e => ?_)
      cases e
      refine ⟨hT.shrink (fun e he => List.mem_of_mem_eraseIdx he), fun c hc => ?_, fun d o l hd => ?_⟩
      · cases hc
      · cases hd
  case take =>
    refine LiveCaps.set (h'.of_st rfl) (fun V e => ?_)
    cases e
    refine ⟨fun n hn => ?_, fun c hc => ?_, fun d o l hd => ?_⟩
    rotate_left
    · cases hc
    · cases hd
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

end A2
