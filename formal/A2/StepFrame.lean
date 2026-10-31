import A2.Panic

/-! A2 — what a step can change in the store, read off the semantics alone:
it binds only what the scopes it opens bind, and the scopes it leaves are
unbound.  A panic only unbinds. -/

namespace A2

/-- `omega` reads facts about `Nat`; these restate facts about variables. -/
theorem vlt {a b : Var} (h : a < b) : @LT.lt Nat _ a b := h
theorem veq {a b : Var} (h : a = b) : @Eq Nat a b := h

/-- The scopes the parameters open, outermost first. -/
def wrapSpine : List (PMode × Ty) → Nat → Nat → List Var
  | [], _, _ => []
  | (.inout _, _) :: ps, base, i => wrapSpine ps base (i + 1)
  | _ :: ps, base, i => (base + i) :: wrapSpine ps base (i + 1)

theorem spine_wrap (s : Stmt) : ∀ (ps : List (PMode × Ty)) (base i : Nat),
    (wrapParams ps base i s).spine = wrapSpine ps base i ++ s.spine := by
  intro ps
  induction ps with
  | nil => intro base i; rfl
  | cons p ps ih =>
    intro base i
    obtain ⟨pm, t⟩ := p
    cases pm <;> simp [wrapParams, wrapSpine, Stmt.spine, ih]

theorem vars_wrap (s : Stmt) : ∀ (ps : List (PMode × Ty)) (base i : Nat),
    (wrapParams ps base i s).vars = wrapSpine ps base i ++ s.vars := by
  intro ps
  induction ps with
  | nil => intro base i; rfl
  | cons p ps ih =>
    intro base i
    obtain ⟨pm, t⟩ := p
    cases pm <;> simp [wrapParams, wrapSpine, Stmt.vars, ih]

theorem mem_wrapSpine : ∀ {ps : List (PMode × Ty)} {base i : Nat} {v : Var}, v ∈ wrapSpine ps base i →
    ∃ k p, ps[k]? = some p ∧ (∀ b, p.1 ≠ .inout b) ∧ v = base + i + k := by
  intro ps
  induction ps with
  | nil => intro base i v h; simp [wrapSpine] at h
  | cons p ps ih =>
    intro base i v h
    obtain ⟨pm, t⟩ := p
    have shift : ∀ {v}, v ∈ wrapSpine ps base (i + 1) →
        ∃ k p, ((pm, t) :: ps)[k]? = some p ∧ (∀ b, p.1 ≠ .inout b) ∧ v = base + i + k := by
      intro v hv
      obtain ⟨k, p, hk, hp, rfl⟩ := ih hv
      refine ⟨k + 1, p, by simpa using hk, hp, ?_⟩
      show base + (i + 1) + k = base + i + (k + 1); omega
    cases pm with
    | inout b => exact shift h
    | inp =>
      simp only [wrapSpine, List.mem_cons] at h
      rcases h with rfl | h
      · exact ⟨0, (.inp, t), by simp, fun b h => (by cases h), rfl⟩
      · exact shift h
    | sink =>
      simp only [wrapSpine, List.mem_cons] at h
      rcases h with rfl | h
      · exact ⟨0, (.sink, t), by simp, fun b h => (by cases h), rfl⟩
      · exact shift h

theorem wrapSpine_nodup : ∀ (ps : List (PMode × Ty)) (base i : Nat), (wrapSpine ps base i).Nodup := by
  intro ps
  induction ps with
  | nil => intro base i; simp [wrapSpine]
  | cons p ps ih =>
    intro base i
    obtain ⟨pm, t⟩ := p
    have hnot : base + i ∉ wrapSpine ps base (i + 1) := by
      intro hm
      obtain ⟨k, _, _, _, he⟩ := mem_wrapSpine hm
      have := veq he; omega
    cases pm with
    | inout b => exact ih base (i + 1)
    | inp => exact List.nodup_cons.mpr ⟨hnot, ih base (i + 1)⟩
    | sink => exact List.nodup_cons.mpr ⟨hnot, ih base (i + 1)⟩


theorem callIn_spine (fn : Fn) (args : List Var) (base : Nat) (x : Var) :
    (callIn fn args base x).spine =
      (base + fn.params.length) :: (wrapSpine fn.params base 0 ++
        (fn.body.rename (callRen fn.params args base)).spine) := by
  simp [callIn, Stmt.spine, spine_wrap]

/-- A panic only unbinds. -/
theorem panic_none {P : Prog} {m m1 : Mem} {s : Stmt} (hst : Step P m s (.panic m1)) :
    ∀ v, m.st v = none → m1.st v = none := by
  generalize hr : Res.panic m1 = r at hst
  induction hst generalizing m1 with
  | letvP _ | assignP _ | panic => cases hr; exact fun _ h => h
  | seqP _ ih | frozenP _ ih => cases hr; exact ih rfl
  | @scopeP _ y _ _ _ _ _ _ ih | @rbindP _ y _ _ _ _ ih | @scopeDPMoved _ y _ _ _ _ ih =>
    cases hr; intro v hv
    simp only [Mem.remove_st]
    by_cases h : v = y
    · subst h; simp
    · rw [upd_ne _ _ h]; exact ih rfl v hv
  | letdP _ => cases hr; exact fun _ h => h
  | _ => cases hr

/-- A panic unbinds the scopes it leaves. -/
theorem panic_spine {P : Prog} {m m1 : Mem} {s : Stmt} (hst : Step P m s (.panic m1)) :
    ∀ v ∈ s.spine, m1.st v = none := by
  generalize hr : Res.panic m1 = r at hst
  induction hst generalizing m1 with
  | letvP _ | assignP _ | panic => cases hr; intro v hv; simp [Stmt.spine] at hv
  | seqP _ ih | frozenP _ ih => cases hr; exact ih rfl
  | @scopeP _ y _ _ _ _ _ _ ih | @rbindP _ y _ _ _ _ ih | @scopeDPMoved _ y _ _ _ _ ih =>
    cases hr; intro v hv
    simp only [Mem.remove_st]
    by_cases h : v = y
    · subst h; simp
    · rw [upd_ne _ _ h]
      simp only [Stmt.spine, List.mem_cons] at hv
      exact ih rfl v (hv.resolve_left h)
  | letdP _ => cases hr; intro v hv; simp [Stmt.spine] at hv
  | _ => cases hr

theorem takeVal_none {m m1 : Mem} {y : Var} {v : Val} (ht : TakeVal m y v m1) {x : Var}
    (hx : m.st x = none) : m1.st x = none := by
  cases ht with
  | own hy =>
    have : x ≠ y := fun e => by subst e; rw [hx] at hy; cases hy
    simp [upd_ne _ _ this, hx]
  | bor _ => exact hx

/-- Binding parameters binds only their slots. -/
theorem bind_new : ∀ {m m1 : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat},
    BindParams m ps as base i m1 → ∀ v, m.st v = none → m1.st v ≠ none → v ∈ wrapSpine ps base i := by
  intro m m1 ps as base i hb
  induction hb with
  | nil => intro v h h'; exact absurd h h'
  | @inp m m' t ps a as base i sl w _ _ _ ih =>
    intro v hv hv'
    by_cases h : v = base + i
    · subst h; simp [wrapSpine]
    · exact List.mem_cons_of_mem _ (ih v (by simp [upd_ne _ _ h, hv]) hv')
  | @sink m m' t ps a as base i w ha _ ih =>
    intro v hv hv'
    by_cases h : v = base + i
    · subst h; simp [wrapSpine]
    · have hva : v ≠ a := fun e => by subst e; rw [hv] at ha; cases ha
      exact List.mem_cons_of_mem _ (ih v (by simp [upd_ne _ _ h, upd_ne _ _ hva, hv]) hv')
  | inout _ ih =>
    intro v hv hv'; simp only [wrapSpine]; exact ih v hv hv'

theorem evalR_none {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (he : EvalR m r (.ok v o m1))
    {x : Var} (hx : m.st x = none) : m1.st x = none := by
  cases he with
  | new => exact hx
  | @moveOwn y _ hy =>
    have : x ≠ y := fun e => by subst e; rw [hx] at hy; cases hy
    simp [Mem.set, upd_ne _ _ this, hx]
  | @pop y _ _ _ _ _ hy _ _ =>
    have : x ≠ y := fun e => by subst e; rw [hx] at hy; cases hy
    simp [Mem.set, upd_ne _ _ this, hx]
  | pair h1 h2 => exact takeVal_none h2 (takeVal_none h1 hx)
  | inl h1 | inr h1 | pack h1 => exact takeVal_none h1 hx
  | @takel y _ hy | @taker y _ hy =>
    have : x ≠ y := fun e => by subst e; rw [hx] at hy; cases hy
    simp [Mem.set, upd_ne _ _ this, hx]
  | _ => exact hx

/-- A step binds only what the scopes it opens bind. -/
theorem step_new {P : Prog} {m m' : Mem} {s s' : Stmt} (hst : Step P m s (.ok m' s')) :
    ∀ v, m.st v = none → m'.st v ≠ none → v ∈ s'.spine := by
  generalize hr : Res.ok m' s' = r at hst
  induction hst generalizing m' s' with
  | seqSkip | iteT _ _ | iteF _ | «while» | frozenSkip | catchSkip =>
    cases hr; intro v h h'; exact absurd h h'
  | seqL _ ih | scopeIn _ ih | rbindIn _ ih | frozenIn _ ih | catchIn _ ih | scopeDIn _ ih =>
    cases hr; intro v h h'
    have := ih rfl v h h'
    simp only [Stmt.spine, List.mem_cons]; first | exact this | exact Or.inr this
  | @letd _ x _ _ _ _ _ _ he =>
    cases hr; intro v h h'
    by_cases hvx : v = x
    · subst hvx; simp [Stmt.spine]
    · simp [upd_ne _ _ hvx, evalR_none he h] at h'
  | scopeDEnd _ => cases hr; intro v h h'; exact absurd h h'
  | @scopeDMoved y _ _ =>
    cases hr; intro v h h'
    simp only [Mem.remove_st] at h'
    by_cases hvx : v = y
    · subst hvx; simp at h'
    · rw [upd_ne _ _ hvx] at h'; exact absurd h h'
  | scopeDP hp _ => cases hr; intro v h h'; exact absurd (panic_none hp v h) h'
  | @letv _ x _ _ _ _ _ he =>
    cases hr; intro v h h'
    by_cases hvx : v = x
    · subst hvx; simp [Stmt.spine]
    · simp [upd_ne _ _ hvx, evalR_none he h] at h'
  | @letcall _ x _ _ _ fn _ _ hb =>
    cases hr; intro v h h'
    rw [callStmt, Stmt.spine, Stmt.spine, callIn_spine]
    by_cases hvx : v = x
    · subst hvx; simp
    by_cases hvr : v = m.nv + fn.params.length
    · subst hvr; simp
    simp only [Mem.set_st, upd_ne _ _ hvr, upd_ne _ _ hvx] at h'
    exact List.mem_cons_of_mem _ (List.mem_cons_of_mem _ (List.mem_append_left _ (bind_new hb v h h')))
  | @letrec x _ _ fn _ _ _ =>
    cases hr; intro v h h'
    rw [recStmt, Stmt.spine, Stmt.spine, Stmt.spine, callIn_spine]
    by_cases hvx : v = x
    · subst hvx; simp
    by_cases hvr : v = m.nv + fn.params.length
    · subst hvr; simp
    simp only [Mem.set_st, upd_ne _ _ hvr, upd_ne _ _ hvx] at h'
    exact absurd h h'
  | @scopeSkip y _ _ _ _ | @rbindSkip y _ _ =>
    cases hr; intro v h h'
    simp only [Mem.remove_st] at h'
    by_cases hvx : v = y
    · subst hvx; simp at h'
    · rw [upd_ne _ _ hvx] at h'; exact absurd h h'
  | @assign _ x _ _ _ _ _ hx he _ _ =>
    cases hr; intro v h h'
    by_cases hvx : v = x
    · subst hvx; rw [h] at hx; cases hx
    · simp [upd_ne _ _ hvx, evalR_none he h] at h'
  | @push _ x _ _ _ _ _ _ ht hx _ _ | @pushRealloc _ x _ _ _ _ _ _ ht hx _ _ =>
    cases hr; intro v h h'
    by_cases hvx : v = x
    · subst hvx; rw [takeVal_none ht h] at hx; cases hx
    · simp [upd_ne _ _ hvx, takeVal_none ht h] at h'
  | @free x _ _ hx _ =>
    cases hr; intro v h h'
    by_cases hvx : v = x
    · subst hvx; rw [h] at hx; cases hx
    · simp [upd_ne _ _ hvx, h] at h'
  | @unpair y x z _ _ _ hy _ _ _ =>
    cases hr; intro v h h'
    by_cases hvx : v = x
    · subst hvx; simp [Stmt.spine]
    by_cases hvz : v = z
    · subst hvz; simp [Stmt.spine]
    have hvy : v ≠ y := fun e => by subst e; rw [h] at hy; cases hy
    simp [upd_ne _ _ hvx, upd_ne _ _ hvz, upd_ne _ _ hvy, h] at h'
  | @catchP _ x _ _ hp hx =>
    cases hr; intro v h h'
    by_cases hvx : v = x
    · subst hvx; rw [panic_none hp v h] at hx; cases hx
    · simp [upd_ne _ _ hvx, panic_none hp v h] at h'
  | @callc _ x _ _ _ _ _ _ _ _ env _ _ fn _ _ _ _ hb =>
    cases hr; intro v h h'
    simp only [Stmt.spine, callIn_spine]
    by_cases hvx : v = x
    · subst hvx; simp
    by_cases hve : v = m.nv
    · subst hve; simp
    by_cases hvr : v = m.nv + 1 + fn.params.length
    · subst hvr; simp
    simp only [Mem.set_st, upd_ne _ _ hvr, upd_ne _ _ hvx] at h'
    have h0 : (envMem m env).st v = none := by simp [envMem, Mem.set, upd_ne _ _ hve, h]
    exact List.mem_cons_of_mem _ (List.mem_cons_of_mem _ (List.mem_cons_of_mem _
      (List.mem_append_left _ (bind_new hb v h0 h'))))
  | _ => cases hr

/-- A step unbinds the scopes it leaves. -/
theorem step_gone {P : Prog} {m m' : Mem} {s s' : Stmt} (hst : Step P m s (.ok m' s'))
    (hck : CatchOK m s) : ∀ v ∈ s.spine, v ∉ s'.spine → m'.st v = none := by
  generalize hr : Res.ok m' s' = r at hst
  induction hst generalizing m' s' with
  | seqL _ ih | frozenIn _ ih =>
    cases hr; intro v h h'; exact ih hck rfl v h h'
  | catchIn _ ih =>
    cases hr; intro v h h'; exact ih hck.2.2.2 rfl v h h'
  | scopeIn _ ih | rbindIn _ ih | scopeDIn _ ih =>
    cases hr; intro v h h'
    simp only [Stmt.spine, List.mem_cons, not_or] at h h'
    exact ih hck rfl v (h.resolve_left h'.1) h'.2
  | scopeSkip _ _ | rbindSkip _ | scopeDMoved _ =>
    cases hr; intro v h _
    simp only [Stmt.spine, List.mem_cons, List.not_mem_nil, or_false] at h
    subst h; simp
  | scopeDEnd _ =>
    cases hr; intro v h h'
    simp only [Stmt.spine, List.mem_cons, List.not_mem_nil, or_false] at h h'
    exact absurd h h'
  | @scopeDP _ x _ _ _ hp _ _ =>
    cases hr; intro v h h'
    simp only [Stmt.spine, List.mem_cons, List.not_mem_nil, or_false] at h h'
    exact panic_spine hp v (h.resolve_left h')
  | @catchP _ x _ _ hp _ =>
    cases hr; intro v h _
    have hvx : v ≠ x := fun e => hck.2.1 (e ▸ h)
    simp [upd_ne _ _ hvx, panic_spine hp v h]
  | _ => cases hr <;> (intro v h _; simp [Stmt.spine] at h)

end A2
