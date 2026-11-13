import A3.Claim

/-! A3 — Agora #755, `Locked D`: a lock share whose payload is a destructor
value, and a witness.

`main` makes a destructor value (`DT`, the struct `T` whose destructor is
`dfn`, `A2/DtorWitness.lean`), moves it into a `Locked` (`locked_new`),
updates it through the lock (`locked_update l f`, here with a result:
`Stmt.lockedApply`, A3.2's `withLock` whose body calls `ufn` on the payload
`inout`, the calculus's form of the update closure), and drops the lock's
only share:

```
: a 1  : b 2  :drop d ( pair a b )
: l ( locked_new d )  : z 0  = z ( locked_apply l ufn )      -- l's scope ends
```

It is typed (`main_typed`, which `Ty.ok` refused before: a lock's payload
owned no destructor value), and every run of it is safe (`main_safe`) and,
finished, leaks nothing (`main_no_leak`); A3's claim covers it
(`lockDtor_claim`).  What the steps do with the payload is stated of
stores and steps, not of this program's run (which no theorem here traces):

* the check-out's end gives the value back, and nothing else
  (`scopeL_end_gives_back`): its crossing check cannot fail
  (`sendCheck_noArc`, the payload type holding no share, `Ty.lkPay`), so
  the scope's end never panics (`Step.scopeLFail`) or drops the value with
  no code (`Release.drop`);
* a panic in the body gives it back too (`scopeL_panic_gives_back`):
  `Step.scopeLP`'s release is a `Release.put` whenever the binding still
  holds a value of the payload's type, as nurlc's `locked_update` leaves
  the value in the lock's memory (a body that moved the value out handed it
  to an owner that runs its destructor, a `letd` or a call's, by A2-drop's
  rules; that the body gave it no other value is `StmtT.withLock`'s `hna`);
* (Agora #805, #825) for a typed frame, the binding's half of those
  hypotheses is proved, for every payload type: `StmtT.scopeL` asks that `x`
  is bound as `withLock` binds it (an owner, or, for an integer payload, a
  plain integer binding) and live where the body ends, so at the end `x`
  holds a `t` (`scopeL_end_owns`, `scopeL_typed_end_gives_back`) and at
  every panic point a `t` (given back once the block is checked out, an
  integer binding's integer included) or nothing (an owner's value moved
  to an owner that runs its destructor, or an integer binding holding no
  integer; the release then frees nothing): `scopeL_typed_panic`, over
  `release_cases`.  The
  block's half (its payload checked out there) is a hypothesis here;
  Agora #808 discharges it on every reached configuration
  (`A3/LockExcl.lean`, `A3/LockRoot.lean`: `reach_scopeL_end_gives_back`,
  `reach_scopeL_panic`);
* when the lock's last share is gone, the marking sweep marks its block
  `dead`, its payload in it, and the same thread's next step is the reap
  that hands the payload to a destructor frame of `dfn`
  (`last_drop_reaps`, over `Mem.sweepD_marks` at a lock block).

Since Agora #804 `RwLocked D`'s read guard is typed
(`A3/RwDtorWitness.lean`: the view lends the payload in place).  Still
refused (stricter than nurlc): a payload that holds a destructor value in a field of a type with
no destructor of its own, or a destructor value (or a drained `Vec` of them)
that holds a cell share (`Ty.lkPay`).  Since Agora #803 one that holds `arc`
or lock shares is typed (`A3/LockArcDtorWitness.lean`): its give-back's
check can fail, and the value then goes to a destructor frame
(`Step.scopeLPD`); the lemmas here are of a payload that holds no share.  Since Agora #810 `locked_restore` of a
destructor value is typed (`lockRestore_dtor_typed`: the restore fills only a
taken block, never a checked-out one).  Since Agora #755's last cut a `Locked (Vec D)` is typed
(`mainV`, below: a push through the check-out), and so is a channel of `D`
(`A3/ChanDtorWitness.lean`: its state under its glue). -/

namespace A3.LockDtorWitness
open A2
open A2.DynCell (NoRootb noRootb_empty)
open A2.DtorWitness (NoDeps T DT dfn EP R0)

/-! ### The give-back of a payload that holds no share -/

/-- A part of a tree of a type that holds no share is no share and no
    handle. -/
theorem _root_.A2.WFv.leaf_noArc {τ : Ty} {v : Val} (hw : WFv τ v) (h : τ.hasArc = false) {w : Val}
    (hs : Sub w v) :
    (∀ k p, w ≠ .arc k p) ∧ (∀ k, w ≠ .lk k) ∧ (∀ k, w ≠ .cell k) ∧ (∀ c, w ≠ .href c) := by
  induction hw generalizing w with
  | int => cases hs; exact ⟨fun _ _ e => (nomatch e), fun _ e => (nomatch e), fun _ e => (nomatch e),
      fun _ e => (nomatch e)⟩
  | view => cases hs; exact ⟨fun _ _ e => (nomatch e), fun _ e => (nomatch e), fun _ e => (nomatch e),
      fun _ e => (nomatch e)⟩
  | node _ ih =>
    cases hs with
    | refl => exact ⟨fun _ _ e => (nomatch e), fun _ e => (nomatch e), fun _ e => (nomatch e),
        fun _ e => (nomatch e)⟩
    | child he hs' => exact ih _ he (by simpa [Ty.hasArc] using h) hs'
  | pair _ _ iha ihb =>
    simp only [Ty.hasArc, Bool.or_eq_false_iff] at h
    cases hs with
    | refl => exact ⟨fun _ _ e => (nomatch e), fun _ e => (nomatch e), fun _ e => (nomatch e),
        fun _ e => (nomatch e)⟩
    | fst hs' => exact iha h.1 hs'
    | snd hs' => exact ihb h.2 hs'
  | inl _ ih =>
    simp only [Ty.hasArc, Bool.or_eq_false_iff] at h
    cases hs with
    | refl => exact ⟨fun _ _ e => (nomatch e), fun _ e => (nomatch e), fun _ e => (nomatch e),
        fun _ e => (nomatch e)⟩
    | inl hs' => exact ih h.1 hs'
  | inr _ ih =>
    simp only [Ty.hasArc, Bool.or_eq_false_iff] at h
    cases hs with
    | refl => exact ⟨fun _ _ e => (nomatch e), fun _ e => (nomatch e), fun _ e => (nomatch e),
        fun _ e => (nomatch e)⟩
    | inr hs' => exact ih h.2 hs'
  | pkg _ hq ih =>
    cases hs with
    | refl => exact ⟨fun _ _ e => (nomatch e), fun _ e => (nomatch e), fun _ e => (nomatch e),
        fun _ e => (nomatch e)⟩
    | pkg hs' => exact ih (hq.2.2.1 (by simpa [Ty.hasArc] using h)) hs'
  | arc => simp [Ty.hasArc] at h
  | lk => simp [Ty.hasArc] at h
  | cell => simp [Ty.hasArc] at h
  | dtor _ _ ih => exact ih h hs

/-- **A tree of a type that holds no share and no view refers to no block**:
    no share, no handle into a payload, no view (`Refers`). -/
theorem _root_.A2.WFv.noRefers {τ : Ty} {v : Val} (hw : WFv τ v) (h : τ.hasArc = false) (hvf : τ.holdsView = false)
    (B : Nat → Option Blk) (k : Nat) : ¬ Refers B v k := by
  rintro (⟨⟨p, hs⟩ | hs⟩ | ⟨bl, _, ⟨c, hs, _⟩ | ⟨d, o, l, hs, _⟩⟩)
  · cases p with
    | none => exact (hw.leaf_noArc h hs).2.1 k rfl
    | some p => exact (hw.leaf_noArc h hs).1 k p rfl
  · exact (hw.leaf_noArc h hs).2.2.1 k rfl
  · exact (hw.leaf_noArc h hs).2.2.2 c rfl
  · obtain ⟨s, hin⟩ := hw.sub_view hs
    have := hin.holdsView; rw [hvf] at this; cases this

/-- **The crossing check cannot fail on a value of a type that holds no
    share and no view** (`Ty.lkPay`'s destructor payload): it holds no cell
    share, and reaches no block, so no read guard (`SendCheck`). -/
theorem sendCheck_noArc {τ : Ty} {v : Val} (hw : WFv τ v) (h : τ.hasArc = false) (hvf : τ.holdsView = false)
    (B : Nat → Option Blk) (st : Var → Option Slot) : SendCheck B [v] st := by
  refine ⟨fun k ⟨w, hw', hs⟩ => ?_, fun k hr => ?_⟩
  · simp only [List.mem_singleton] at hw'; subst hw'
    exact ((hw.leaf_noArc h hs).2.2.1 k rfl).elim
  · exfalso
    induction hr with
    | root hv hr =>
      simp only [List.mem_singleton] at hv; subst hv
      exact hw.noRefers h hvf B _ hr
    | pay _ _ _ ih => exact ih

/-- A tree of a type that holds no share names no block to check. -/
theorem sharesIn_noArc {τ : Ty} {v : Val} (h : τ.hasArc = false) (B : Nat → Option Blk) : SharesIn B τ v :=
  fun _ _ _ ha => by rw [ha.hasArc] at h; cases h

/-- What a check-out's binding can give back to a block of a `t` that holds
    no share (`Giveable`): a tree of the payload's type it owns, or, for an
    integer payload, the integer a plain integer binding holds. -/
theorem giveable_of {B : Nat → Option Blk} {t : Ty} {o : Bool} {v : Val} (hw : WFv t v)
    (hna : t.hasArc = false) (ho : o = true ∨ t = .int) : Giveable B t ⟨o, some v⟩ := by
  cases o with
  | true => exact ⟨hw, sharesIn_noArc hna _⟩
  | false =>
    rcases ho with h | rfl
    · cases h
    · cases hw; rfl

/-- **The lock scope's release puts the value back**: from a store where `x`
    holds a `t` that holds no share and no view (owned, or, for an integer
    payload, a plain integer binding's) and the block has its payload
    checked out, every release (`Release`) is the give-back `Release.put`,
    never the code-less drop. -/
theorem release_puts {m m' : Mem} {k : Nat} {t : Ty} {x : Var} {o : Bool} {v : Val}
    (hx : m.st x = some ⟨o, some v⟩) (hw : WFv t v) (ho : o = true ∨ t = .int)
    (hna : t.hasArc = false) (hvf : t.holdsView = false)
    (hk : CheckedOut m k t) (hr : Release m k t x m') :
    m' = ({ m with blk := upd m.blk k (some ⟨t, .lock, some v⟩) }.remove x) := by
  have hg : Giveable m.blk t ⟨o, some v⟩ := giveable_of hw hna ho
  have hgc : GiveCheck m x ⟨o, some v⟩ := fun w hw' => by
    cases hw'; exact sendCheck_noArc hw hna hvf _ _
  cases hr with
  | put hx' _ _ _ => rw [hx] at hx'; cases hx'; rfl
  | drop hno _ hx' _ =>
    rw [hx] at hx'; cases hx'
    rcases hno with h | h | h
    · exact absurd hk h
    · exact absurd hg h
    · exact absurd hgc h

/-- **Agora #755: the check-out's end gives the value back, and nothing
    else**: at `scopeL k t x skip`, with `x` holding a `t` that holds no share
    and no view (owned, or, Agora #825, for an integer payload a plain
    integer binding's), the block checked out and no orphan to reap first,
    the one step is the give-back (`Step.scopeLSkip` with `Release.put`): the
    crossing check cannot fail (`Step.scopeLFail` is not taken) and the
    value is not dropped. -/
theorem scopeL_end_gives_back {P : Prog} {m : Mem} {k : Nat} {t : Ty} {x : Var} {o : Bool} {v : Val}
    (hx : m.st x = some ⟨o, some v⟩) (hw : WFv t v) (ho : o = true ∨ t = .int)
    (hna : t.hasArc = false) (hvf : t.holdsView = false)
    (hk : CheckedOut m k t) (hno : ¬ Orphan m) {r : Res}
    (h : Step P m (.scopeL k t x .skip) r) :
    r = .ok ({ m with blk := upd m.blk k (some ⟨t, .lock, some v⟩) }.remove x) .skip := by
  cases h with
  | scopeLIn hs => exact (A2.Dtor.skip_no_step hno hs).elim
  | scopeLSkip hrl _ => rw [release_puts hx hw ho hna hvf hk hrl]
  | scopeLFail hx' hng =>
    rw [hx] at hx'; cases hx'
    exact absurd (fun w hw' => by cases hw'; exact sendCheck_noArc hw hna hvf _ _) hng
  | scopeLP hs _ => exact (A2.Dtor.skip_no_step hno hs).elim
  | scopeLPD hs _ _ _ _ => exact (A2.Dtor.skip_no_step hno hs).elim
  | waitPanic hw' => exact hw'.elim
  | reap hrs _ _ => cases hrs

/-- **Agora #755: a panic in the body gives the value back**: a panic that
    unwinds through the check-out (`Step.scopeLP`) leaves the store whose
    block holds again what `x` held, when `x` still holds a `t` that holds no
    share and no view (owned, or an integer payload's plain integer) and the
    block is checked out (nurlc's `locked_update` runs in place: the value
    stays in the lock's memory). -/
theorem scopeL_panic_gives_back {P : Prog} {m m2 : Mem} {k : Nat} {t : Ty} {x : Var} {s : Stmt}
    (h : Step P m (.scopeL k t x s) (.panic m2)) :
    ∃ m1, Step P m s (.panic m1) ∧
      ∀ o v, m1.st x = some ⟨o, some v⟩ → WFv t v → (o = true ∨ t = .int) → t.hasArc = false →
        t.holdsView = false → CheckedOut m1 k t →
        m2 = ({ m1 with blk := upd m1.blk k (some ⟨t, .lock, some v⟩) }.remove x) := by
  cases h with
  | scopeLP hs hrl =>
    exact ⟨_, hs, fun o v hx hw ho hna hvf hk => release_puts hx hw ho hna hvf hk hrl⟩
  | waitPanic hw => exact hw.elim

/-- Agora #825: **the typing of a check-out frame names its binding as
    `withLock` bound it**: of the payload's type, no root borrow, and an
    owner unless the payload is an integer (`lockE`: then a plain integer
    binding), for every payload type (`StmtT.scopeL`, through `sub`). -/
theorem scopeL_entry {P : Prog} {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var} {s : Stmt}
    (ht : StmtT P Γ F (.scopeL k t x s) Δ) :
    ∃ E, Γ x = some E ∧ E.mode ≠ .rootb ∧ (t ≠ .int → E.mode = .own) ∧ E.ty = t := by
  generalize hs : Stmt.scopeL k t x s = st at ht
  induction ht with
  | scopeL hxE _ _ _ =>
    cases hs
    obtain ⟨E, hx, hrb, hty, hmo, _⟩ := hxE
    exact ⟨E, hx, hrb, hmo, hty⟩
  | @sub Γa Γ0 _ _ _ _ hw _ _ ih =>
    obtain ⟨E0, h0, hrb0, hm0, ht0⟩ := ih hs
    obtain ⟨hn, hE⟩ := hw.1 x
    cases hg : Γa x with
    | none => rw [hn.mp hg] at h0; cases h0
    | some E =>
      have hw' := hE E E0 hg h0
      exact ⟨E, rfl, by rw [← hw'.mode]; exact hrb0, fun hne => by rw [← hw'.mode]; exact hm0 hne,
        by rw [← hw'.ty]; exact ht0⟩
  | _ => cases hs

/-- Agora #805, #825: **a typed check-out ends with its binding live**, for
    every payload type: the typing of the run-time frame `scopeL k t x skip`
    (whose rule asks that `x` is live where the body ends, as `withLock`
    does; `StmtT.scopeL`) names `x` live, of type `t`, and an owner unless
    the payload is an integer. -/
theorem scopeL_end_entry {P : Prog} {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var}
    (ht : StmtT P Γ F (.scopeL k t x .skip) Δ) :
    ∃ E, Γ x = some E ∧ E.live = true ∧ E.mode ≠ .rootb ∧ (t ≠ .int → E.mode = .own) ∧ E.ty = t := by
  generalize hs : Stmt.scopeL k t x .skip = st at ht
  induction ht with
  | scopeL hxE _ hb _ =>
    cases hs
    obtain ⟨E, hx, hrb, hty, hmo, E', hΔ, hlv⟩ := hxE
    refine ⟨E, hx, ?_, hrb, hmo, hty⟩
    rcases skip_inv hb with rfl | hw
    · rw [hx] at hΔ; cases hΔ; exact hlv
    · exact (((hw.1 x).2 E E' hx hΔ).live hlv).1
  | @sub Γa Γ0 _ _ _ _ hw _ _ ih =>
    obtain ⟨E0, h0, hl0, hrb0, hm0, ht0⟩ := ih hs
    obtain ⟨hn, hE⟩ := hw.1 x
    cases hg : Γa x with
    | none => rw [hn.mp hg] at h0; cases h0
    | some E =>
      have hw' := hE E E0 hg h0
      exact ⟨E, rfl, (hw'.live hl0).1, by rw [← hw'.mode]; exact hrb0,
        fun hne => by rw [← hw'.mode]; exact hm0 hne, by rw [← hw'.ty]; exact ht0⟩
  | _ => cases hs

/-- Agora #825: **a check-out's binding in the store** (`MInv.slot`): an
    owner's slot, holding a `t` or moved out; or, for an integer payload, a
    plain integer binding's, holding an integer while the entry is live. -/
theorem frame_slot {m : Mem} {Γ : Ctx} {x : Var} {E : Entry} {t : Ty} (hi : MInv m Γ)
    (hx : Γ x = some E) (hrb : E.mode ≠ .rootb) (hmo : t ≠ .int → E.mode = .own) (hty : E.ty = t) :
    (∃ w, m.st x = some ⟨true, w⟩ ∧ (∀ v, w = some v → WFv t v) ∧ (E.live = true → ∃ v, w = some v)) ∨
      (t = .int ∧ ∃ w, m.st x = some ⟨false, w⟩ ∧ (E.live = true → ∃ n, w = some (.int n))) := by
  obtain ⟨⟨o, w⟩, hsl, _, hown, hok, hbor⟩ := hi.slot x E hx
  by_cases hm : E.mode = .own
  · rw [hm] at hown hok
    obtain ⟨_, hw, hlive⟩ := hok rfl
    simp only at hown; subst hown
    refine .inl ⟨w, hsl, fun v hv => hty ▸ hw v hv, fun hl => ?_⟩
    obtain ⟨T, hT, _⟩ := hlive hl
    exact ⟨T, hT⟩
  · have hti : t = .int := Classical.byContradiction fun hne => hm (hmo hne)
    subst hti
    have hb : E.mode = .bor := by
      cases hE : E.mode with
      | own => exact absurd hE hm
      | inout b => exact absurd hE (hi.noInout x E b hx)
      | rootb => exact absurd hE hrb
      | bor => rfl
    rw [hb] at hown hbor
    simp only [Mode.ownSlot] at hown; subst hown
    refine .inr ⟨rfl, w, hsl, fun hl => ?_⟩
    obtain ⟨v, hv, hvo⟩ := hbor rfl hl
    simp only at hv; subst hv
    rw [hty] at hvo
    cases hvo with
    | int => exact ⟨_, rfl⟩

/-- Agora #825: **the check-out's binding, live at the frame's end, holds a
    `t` it can give back**: an owner's tree of the payload's type, or, for an
    integer payload, a plain integer binding's integer. -/
theorem frame_slot_live {m : Mem} {Γ : Ctx} {x : Var} {E : Entry} {t : Ty} (hi : MInv m Γ)
    (hx : Γ x = some E) (hl : E.live = true) (hrb : E.mode ≠ .rootb) (hmo : t ≠ .int → E.mode = .own)
    (hty : E.ty = t) :
    ∃ o v, m.st x = some ⟨o, some v⟩ ∧ WFv t v ∧ (o = true ∨ t = .int) := by
  rcases frame_slot hi hx hrb hmo hty with ⟨w, hsl, hw, hlv⟩ | ⟨rfl, w, hsl, hlv⟩
  · obtain ⟨v, rfl⟩ := hlv hl
    exact ⟨true, v, hsl, hw v rfl, .inl rfl⟩
  · obtain ⟨n, rfl⟩ := hlv hl
    exact ⟨false, .int n, hsl, .int, .inr rfl⟩

/-- **... so in the store, `x` holds a `t` there** (`frame_slot_live`): the
    first hypotheses of `scopeL_end_gives_back`, discharged for a typed
    frame, for every payload type (Agora #825). -/
theorem scopeL_end_owns {P : Prog} {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var} {m : Mem}
    (ht : StmtT P Γ F (.scopeL k t x .skip) Δ) (hi : MInv m Γ) :
    ∃ o v, m.st x = some ⟨o, some v⟩ ∧ WFv t v ∧ (o = true ∨ t = .int) := by
  obtain ⟨E, hx, hl, hrb, hmo, hty⟩ := scopeL_end_entry ht
  exact frame_slot_live hi hx hl hrb hmo hty

/-- **The check-out's end gives the value back, for a typed frame**, of
    every payload type that holds no share and no view (Agora #825): with
    `x`'s value discharged by the typing (`scopeL_end_owns`), what is left of
    `scopeL_end_gives_back`'s hypotheses is the block's: that it has its
    payload checked out (`CheckedOut m k t`: `m.blk k = some ⟨t, .lock, none⟩`,
    not taken), which
    Agora #808 proves of every reached configuration's frame
    (`A3.reach_scopeL_end_gives_back`). -/
theorem scopeL_typed_end_gives_back {P : Prog} {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var}
    {m : Mem} (ht : StmtT P Γ F (.scopeL k t x .skip) Δ) (hi : MInv m Γ)
    (hna : t.hasArc = false) (hvf : t.holdsView = false) (hk : CheckedOut m k t)
    (hno : ¬ Orphan m) {r : Res} (h : Step P m (.scopeL k t x .skip) r) :
    ∃ o v, m.st x = some ⟨o, some v⟩ ∧
      r = .ok ({ m with blk := upd m.blk k (some ⟨t, .lock, some v⟩) }.remove x) .skip := by
  obtain ⟨o, v, hx, hw, ho⟩ := scopeL_end_owns ht hi
  exact ⟨o, v, hx, scopeL_end_gives_back hx hw ho hna hvf hk hno h⟩

/-- A panic's unwinding changes no slot but the frames' it unwinds (the
    statement's spine). -/
theorem Step.panic_st {P : Prog} {m m1 : Mem} {s : Stmt} (h : Step P m s (.panic m1)) :
    ∀ y, y ∉ s.spine → m1.st y = m.st y := by
  generalize hr : Res.panic m1 = r at h
  induction h generalizing m1 with
  | seqP _ ih => cases hr; exact fun y hy => ih rfl y (by simpa [Stmt.spine] using hy)
  | letvP _ | assignP _ | letdP _ | panic | waitPanic _ | withElemOOB _ _ _ _ =>
    cases hr; exact fun _ _ => rfl
  | @scopeP m1' x' _ _ _ _ _ _ ih =>
    cases hr
    intro y hy
    simp only [Stmt.spine, List.mem_cons, not_or] at hy
    show upd m1'.st x' none y = _
    rw [upd_ne _ _ hy.1]; exact ih rfl y hy.2
  | @rbindP m1' p _ _ _ _ ih =>
    cases hr
    intro y hy
    simp only [Stmt.spine, List.mem_cons, not_or] at hy
    show upd m1'.st p none y = _
    rw [upd_ne _ _ hy.1]; exact ih rfl y hy.2
  | frozenP _ ih => cases hr; exact fun y hy => ih rfl y (by simpa [Stmt.spine] using hy)
  | @scopeDPMoved m1' x' _ _ _ _ ih =>
    cases hr
    intro y hy
    simp only [Stmt.spine, List.mem_cons, not_or] at hy
    show upd m1'.st x' none y = _
    rw [upd_ne _ _ hy.1]; exact ih rfl y hy.2
  | @scopeLP m1' m2' _ _ x' _ _ hrl ih =>
    cases hr
    intro y hy
    simp only [Stmt.spine, List.mem_cons, not_or] at hy
    have : m2'.st y = m1'.st y := by
      cases hrl <;> (show upd m1'.st x' none y = _; rw [upd_ne _ _ hy.1])
    rw [this]; exact ih rfl y hy.2
  | _ => cases hr

/-- Agora #825: **a release from a check-out binding's slot**: holding a `t`
    (owned, or an integer payload's plain integer), it gives the value back
    when the block has its payload checked out (`release_puts`); owning
    nothing (moved out), or an integer binding's holding no integer, it frees
    nothing, the block left as it was.  A drop of a plain integer binding
    that holds an integer is the first case: with the block checked out it
    is the give-back (`release_puts`), so the second case holds of no slot
    that holds a `t`. -/
theorem release_cases {m1 m2 : Mem} {k : Nat} {t : Ty} {x : Var}
    (hna : t.hasArc = false) (hvf : t.holdsView = false)
    (hsl : (∃ w, m1.st x = some ⟨true, w⟩ ∧ ∀ v, w = some v → WFv t v) ∨
      (t = .int ∧ ∃ w, m1.st x = some ⟨false, w⟩))
    (hrl : Release m1 k t x m2) :
    (∃ o v, m1.st x = some ⟨o, some v⟩ ∧ WFv t v ∧ (o = true ∨ t = .int) ∧
        (CheckedOut m1 k t →
          m2 = ({ m1 with blk := upd m1.blk k (some ⟨t, .lock, some v⟩) }.remove x))) ∨
      ((m1.st x = some ⟨true, none⟩ ∨
          (t = .int ∧ ∃ w, m1.st x = some ⟨false, w⟩ ∧ ∀ n, w ≠ some (.int n))) ∧
        m2 = m1.remove x) := by
  rcases hsl with ⟨w, hx1, hw⟩ | ⟨rfl, w, hx1⟩
  · cases w with
    | some v => exact .inl ⟨true, v, hx1, hw v rfl, .inl rfl, fun hk => release_puts hx1 (hw v rfl) (.inl rfl) hna hvf hk hrl⟩
    | none =>
      refine .inr ⟨.inl hx1, ?_⟩
      cases hrl with
      | put hx' _ _ _ => rw [hx1] at hx'; cases hx'
      | drop _ _ hx' hdr => rw [hx1] at hx'; cases hx'; cases hdr; rfl
  · by_cases hwi : ∃ n, w = some (.int n)
    · obtain ⟨n, rfl⟩ := hwi
      exact .inl ⟨false, .int n, hx1, .int, .inr rfl,
        fun hk => release_puts hx1 .int (.inr rfl) hna hvf hk hrl⟩
    · have hni : ∀ n, w ≠ some (.int n) := fun n he => hwi ⟨n, he⟩
      cases hrl with
      | @put _ v hx' hg _ _ =>
        rw [hx1] at hx'; cases hx'
        obtain ⟨n, rfl⟩ : ∃ n, v = .int n := by cases v <;> simp_all [Giveable]
        exact absurd rfl (hni n)
      | drop _ _ hx' hdr =>
        rw [hx1] at hx'; cases hx'
        exact .inr ⟨.inr ⟨rfl, w, hx1, hni⟩, by cases hdr; rfl⟩

/-- Agora #805, #825: **at every panic point of a typed check-out, `x` holds
    a `t` or nothing**, for every payload type that holds no share and no
    view: a panic that unwinds through `scopeL k t x s` (`Step.scopeLP`)
    leaves `x`'s slot as the body's unwinding found it, as `withLock` bound
    it (the frame's typing, `scopeL_entry`, and `frame_slot`): an owner's,
    holding a `t` or moved out, or an integer payload's plain integer
    binding's.  Holding a `t` (an owner's tree, or an integer binding's
    integer), the release gives it back when the block has its payload
    checked out (`release_puts`); holding nothing (an owner moved out, or an
    integer binding holding no integer), the release frees nothing (a
    moved-out value went to an owner that runs its destructor: A2-drop's
    binders), the block left as it was (`release_cases`). -/
theorem scopeL_typed_panic {P : Prog} {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var} {s : Stmt}
    {m m2 : Mem} (ht : StmtT P Γ F (.scopeL k t x s) Δ) (hi : Inv m Γ F (.scopeL k t x s))
    (hna : t.hasArc = false) (hvf : t.holdsView = false)
    (h : Step P m (.scopeL k t x s) (.panic m2)) :
    ∃ m1, Step P m s (.panic m1) ∧
      ((∃ o v, m1.st x = some ⟨o, some v⟩ ∧ WFv t v ∧ (o = true ∨ t = .int) ∧
          (CheckedOut m1 k t →
            m2 = ({ m1 with blk := upd m1.blk k (some ⟨t, .lock, some v⟩) }.remove x))) ∨
        ((m1.st x = some ⟨true, none⟩ ∨
            (t = .int ∧ ∃ w, m1.st x = some ⟨false, w⟩ ∧ ∀ n, w ≠ some (.int n))) ∧
          m2 = m1.remove x)) := by
  cases h with
  | waitPanic hw => exact hw.elim
  | @scopeLP m1 _ _ _ _ _ hs hrl =>
    refine ⟨m1, hs, ?_⟩
    have hxsp : x ∉ s.spine := by
      have := hi.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.1
    have hst := Step.panic_st hs x hxsp
    obtain ⟨E, hx, hrb, hmo, hty⟩ := scopeL_entry ht
    refine release_cases hna hvf ?_ hrl
    rw [hst]
    rcases frame_slot hi.toMInv hx hrb hmo hty with ⟨w, hsl, hw, _⟩ | ⟨hti, w, hsl, _⟩
    · exact .inl ⟨w, hsl, hw⟩
    · exact .inr ⟨hti, w, hsl⟩

/-! ### `locked_restore` of a destructor value -/

/-- **`locked_restore` of a destructor value is typed** (Agora #810,
    as nurlc's): the restore fills only a block `locked_take` emptied
    (`EvalR.lockRestore` asks `Mem.taken`), never one a `withLock` has
    checked out, whose give-back would then drop its value with no code;
    until the model told the two apart the typing refused it (Agora #755). -/
theorem lockRestore_dtor_typed {Γ Γ1 : Ctx} {F : List Var} {a y : Var} {Ea Ey : Entry} {f : Nat} {u : Ty}
    {D : List Dep} (ha : Γ a = some Ea) (hla : Ea.live = true) (hty : Ea.ty = .lk (.dtor f u))
    (hy : Γ y = some Ey) (hly : Ey.live = true) (htyy : Ey.ty = .dtor f u)
    (hp : PushArg Γ F y Ey (.dtor f u) D Γ1) : RhsT Γ F (.lockRestore a y) intE Γ1 :=
  RhsT.lockRestore ha hla hty hy hly htyy hp

/-! ### The program -/

/-- The update closure: `@ upd inout self → i { = r 0 }`, the payload taken
    `inout` (`locked_update`'s `( @ v inout T ) f`). -/
def ufn : Fn where
  params := [(.inout .replace, DT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .assign 1 (.expr (.lit 0))
  nvars := 2

def P : Prog := [dfn, ufn]

theorem dfn_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [dfn, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [dfn, Stmt.calls] at hg

theorem drop0_ok : DropFnOK P 0 T :=
  Or.inl ⟨⟨dfn, rfl, rfl, rfl, rfl, rfl, rfl, rfl, dfn_not_thru⟩, by decide⟩

/-- `= r 0`, the result slot `r` of a function of an integer result. -/
theorem assign_res {fn : Fn} {r : Var} (hc : sigCtx fn r = some R0)
    (hp : ∀ p E, sigCtx fn p = some E → E.mode = .rootb → E.vdeps = [])
    (hflags : ∀ v E, sigCtx fn v = some E → E.dtor = false ∧ E.dbind = false) :
    StmtT P (sigCtx fn) [] (.assign r (.expr (.lit 0)))
      (setE (kill .replace false r (sigCtx fn)) r { intE with mode := R0.mode }) :=
  StmtT.assign (Ex := R0) (E := intE) hc (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc])
    (by intro p E hp' _ d hd _; rw [hp p E hp' (by assumption)] at hd; cases hd)
    (DtorSafe.of_none (fun v E h => (hflags v E h).1) _ _ _) rfl

theorem dfn_ok : FnOK P dfn := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [dfn], ?_, by simp [dfn], by simp [dfn], by simp [dfn],
    by simp [dfn], by simp [dfn], ?_, _,
    assign_res (by simp [sigCtx, dfn, R0, resMode]) ?_ A2.ArcPanicWitness.sig_dfn_flags, ?_, ?_, ?_⟩
  · intro pt hpt; simp [dfn] at hpt; subst hpt; simp [DT, T, Ty.ok, Ty.isStruct]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [dfn] at h⟩
    · simp [dfn] at hi; subst hi; simp [dfn] at hs
    · simp [dfn] at hi; subst hi; simp [dfn] at hb
  · intro p E hp _
    rcases p with _ | _ | p <;> simp [sigCtx, dfn, paramE, resMode, DT, T, Ty.hasFn] at hp <;> subst hp <;>
      simp [Entry.vdeps]
  · intro v E h
    rcases v with _ | _ | v <;> simp [setE, upd, kill, killE, sigCtx, dfn, paramE, intE] at h <;>
      subst h <;> exact ⟨rfl, rfl⟩
  · exact ⟨{ intE with mode := R0.mode }, by simp [setE, upd, dfn], rfl, rfl, by simp [R0, resMode, dfn],
      by simp [intE], by simp [intE], by simp [dfn]⟩
  · intro i hi b hb; simp [dfn] at hi; subst hi; simp [dfn] at hb

theorem sig_ufn_flags : ∀ v E, sigCtx ufn v = some E → E.dtor = false ∧ E.dbind = false := by
  intro v E h
  rcases v with _ | _ | v <;> simp [sigCtx, ufn, paramE, resMode] at h <;> subst h <;> exact ⟨rfl, rfl⟩

/-- The closure's `FnOK`: its `inout` parameter, of a destructor type, is
    given no other value (`DtorParamsOK`) and is live at its end. -/
theorem ufn_ok : FnOK P ufn := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [ufn], ?_, by simp [ufn], by simp [ufn], by simp [ufn],
    by simp [ufn], by simp [ufn], ?_, _,
    assign_res (by simp [sigCtx, ufn, R0, resMode]) ?_ sig_ufn_flags, ?_, ?_, ?_⟩
  · intro pt hpt; simp [ufn] at hpt; subst hpt
    simp [DT, T, Ty.ok, Ty.isStruct, Ty.owning]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [ufn] at h⟩
    · simp [ufn] at hi; subst hi; simp [ufn] at hs
    · simp [ufn] at hi; subst hi; simp [ufn, Stmt.assigns]
  · intro p E hp hm
    rcases p with _ | _ | p <;> simp [sigCtx, ufn, paramE, resMode] at hp <;> subst hp <;> simp at hm
  · intro v E h
    rcases v with _ | _ | v <;> simp [setE, upd, kill, killE, sigCtx, ufn, paramE, intE] at h <;>
      subst h <;> exact ⟨rfl, rfl⟩
  · exact ⟨{ intE with mode := R0.mode }, by simp [setE, upd, ufn], rfl, rfl, by simp [R0, resMode, ufn],
      by simp [intE], by simp [intE], by simp [ufn]⟩
  · intro i hi b hb
    simp [ufn] at hi; subst hi
    refine ⟨paramE ufn.params (.inout .replace, DT), ?_, rfl, ?_, ?_⟩
    · simp [setE, upd, kill, killE, sigCtx, ufn, paramE, Entry.vdeps, hits, Mode.ownSlot, DT, T, Ty.hasFn]
    · simp [paramE, DT, T, Ty.hasFn]
    · intro _; simp [paramE, DT, T, Ty.hasFn]

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl
  · exact dfn_ok
  · exact ufn_ok

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl
  · simp [dfn, Stmt.codesOK, Rhs.codeOK]
  · simp [ufn, Stmt.codesOK, Rhs.codeOK]

/-- `: a 1  : b 2  :drop d ( pair a b )  : l ( locked_new d )  : z 0
     = z ( locked_apply l ufn )` (the payload checked out to `x = 5`, the
    closure's result `c = 6` moved out to `z`). -/
def main : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2)) (.letd 2 0 (.pair 0 1)
    (.letv 3 (.lockNew DT 2) (.letv 4 (.expr (.lit 0)) (Stmt.lockedApply 3 5 6 4 1)))))

/-- The lock share's entry: owned, holding nothing. -/
def EL : Entry := ⟨.lk DT, .own, true, [], [], false, false⟩

/-- **A `Locked` of a destructor value is typed** (Agora #755: `Ty.ok` admits
    `lk (dtor f u)` when `u` holds no share, `RhsT.lockNew` takes the value),
    and so is its update through `locked_apply` (`StmtT.lockedApply`, A3.2's
    `withLock`: the body gives the checked-out binding no other value). -/
theorem main_typed : ∃ Δ, StmtT P (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  have hD0 : NoDeps (fun _ => none) := fun _ _ h => by cases h
  have hD2 : NoDeps K2 := (hD0.setE rfl).setE rfl
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hED : ED.mode ≠ .rootb ∧ ED.dtor = false ∧ ED.dbind = false := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE hED
  have hD3 : NoDeps K3 := hD2.setE (by simp [ED, EP, Entry.arm, Entry.vdeps])
  have hK3d : K3 2 = some ED := by simp [K3, A2.setE]
  -- `locked_new d`: `d` moves into the lock block
  let ED' : Entry := { ED with live := false, dtor := false }
  let K3' : Ctx := A2.setE K3 2 ED'
  have hkill : A2.kill .replace false 2 K3 = K3 := hD3.kill_eq _ _ _
  have hnew : RhsT K3 [] (.lockNew DT 2) EL K3' := by
    have h := RhsT.lockNew (Γ := K3) (F := []) (t := DT) (y := 2) (Ey := ED) hK3d
      (by simp [ED, Entry.arm, EP]) (by simp [ED, Entry.arm]) (by decide)
      ⟨by simp [DT, T, Ty.holdsView], by simp [DT, T, Ty.hasFn]⟩
      (PushArg.move (by simp [DT, T, Ty.owning]) (by simp [ED, Entry.arm, EP]) (by simp)
        (hK3.noPin 2) (DtorSafe.of_none (fun v E h => (hK3 v E h).2.1) _ _ _))
    rw [hkill] at h; exact h
  have hK3' : NoRootb K3' := hK3.setE (by simp [ED', ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView])
  have hD3' : NoDeps K3' := hD3.setE (by simp [ED', ED, EP, Entry.arm, Entry.vdeps])
  let K4 : Ctx := A2.setE K3' 3 EL
  have hK4 : NoRootb K4 := hK3'.setE (by simp [EL])
  have hD4 : NoDeps K4 := hD3'.setE rfl
  let K5 : Ctx := A2.setE K4 4 intE
  have hK5 : NoRootb K5 := hK4.setE (by simp [intE])
  have hD5 : NoDeps K5 := hD4.setE rfl
  have hun : ∀ v, Unnamed K5 v := fun v w E h d hd => by rw [hD5 w E h] at hd; cases hd
  -- the update, under the lock: `ufn` on the payload `inout`, its result to `z`
  have hap : ApplyFn P 1 DT .int := ⟨ufn, .replace, rfl, rfl, rfl, rfl, rfl⟩
  have hup := StmtT.lockedApply (P := P) (Γ := K5) (F := []) (a := 3) (x := 5) (c := 6) (z := 4) (f := 1)
    (fn := ufn) (Ea := EL) (Ez := intE) (t := DT) (R := .int) hap rfl
    (by simp [K5, K4, A2.setE]) rfl (Or.inl rfl) rfl (by simp [DT, T, Ty.holdsView]) (by simp [DT, Ty.owning])
    (by simp [K5, K4, K3', K3, K2, K1, A2.setE, upd]) (by simp [K5, K4, K3', K3, K2, K1, A2.setE, upd])
    (by decide) (by simp) (by simp) (hun 5) (hun 6) (by decide) (by simp [K5, A2.setE]) (by simp) rfl
    (by simp [intE, resMode, ufn]) rfl (hK5.noPin 4) (DtorSafe.of_none (fun v E h => (hK5 v E h).2.1) _ _ _)
  have hKf : NoRootb (A2.setE (A2.kill .replace false 4 K5) 4 (outE .int intE.mode)) :=
    (hK5.kill _ _ _).setE (by simp [outE, intE])
  have hz := StmtT.letv (P := P) (x := 4) (r := .expr (.lit 0)) (E := intE) (F := []) (Γ := K4) (Γ1 := K4)
    rfl (by simp [K4, K3', K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hup (hKf.endOK _)
  have hl := StmtT.letv (P := P) (x := 3) (r := .lockNew DT 2) (E := EL) (F := []) (Γ := K3) (Γ1 := K3')
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) hnew hz ((hKf.exitScope 4).endOK _) (fun _ => rfl)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE]) rfl PushArg.int
      (by simp [K2, K1, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE]) (by simp) hpair rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop0_ok) (HeldUp.refl _ _) hl
    (((hKf.exitScope 4).exitScope 3).endOK _) (by simp [Stmt.lockedApply, Stmt.callOut, Stmt.assigns])
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd
    ((((hKf.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    (((((hKf.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- `locked_new` of the destructor value names the destructor the program
    checked (`Rhs.codeOK`). -/
theorem main_codes : main.codesOK P := by
  simp only [main, Stmt.lockedApply, Stmt.callOut, Stmt.codesOK, Rhs.codeOK, DT]
  exact ⟨trivial, trivial, trivial, arcNew_codeOK (n := 0) drop0_ok, trivial, trivial⟩

/-- **Every run of it is safe.** -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 7) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **... and leaks nothing**: when it finishes, every address is freed
    (`no_leak_end`; that the payload was reaped on the way is read off the
    steps, `last_drop_reaps`, not stated here). -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 7) main (.ok m' .skip)) : ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **... and leaks nothing on a panic either** (`no_leak_panic`). -/
theorem main_no_leak_panic {m' : Mem} (hr : Steps P (emptyMem 7) main (.panic m')) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_panic prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **The lock's last share's drop hands the payload to a destructor frame of
    the same thread**: when no slot's value and no block's payload refers to
    the lock block, its payload in it (`l`'s scope has ended, the update's
    give-back long done), the marking sweep that ends the step marks it
    `dead`, its payload in it (`Mem.sweepD_marks`, at a lock block), so the
    thread's next step is a reap (`settle_reaps`), which moves the payload
    to a fresh binding in a frame `scopeD _ 0 skip` whose end calls `dfn` on
    it (`A2.Dtor.scopeD_end_runs_dtor`), as nurlc's last `Locked_drop` drops
    the value. -/
theorem last_drop_reaps {m : Mem} {k : Nat} {p : Val} (hk : m.blk k = some ⟨DT, .lock, some p⟩)
    (hv : ∀ x o v, m.st x = some ⟨o, some v⟩ → ¬ Refers m.blk v k)
    (hb : ∀ k' bl', m.blk k' = some bl' → ¬ Refers m.blk bl'.keeps k)
    {s s' : Stmt} {m' : Mem} (h : Settle P m.sweepD s m' s') :
    m.sweepD.blk k = some ⟨DT, .dead, some p⟩ ∧
      ∃ m1 s1, Step P m.sweepD s (.ok m1 s1) ∧ ReapMem m.sweepD m1 := by
  have hm := Mem.sweepD_marks (n := 0) (f := 0) (u := T) (Or.inr rfl) hk hv hb
  exact ⟨hm, settle_reaps h ⟨k, 0, 0, T, p, hm⟩⟩


/-! ### `Locked (Vec D)`: a lock of a drained `Vec`, pushed to through the check-out

`mainV` makes an empty `Vec` of destructor values (bound by `letd` at
`vec DT`), moves it into a `Locked` (`locked_new`), checks it out
(`locked_update`, A3.2's `withLock`), makes a destructor value inside the
check-out and pushes it into the checked-out `Vec`, gives it back, and drops
the lock's only share:

```
: a 1  : b 2  :drop v ( vec_new DT )  : l ( locked_new v )
( locked_update l @ w { :drop x ( pair a b )  ( vec_push w x ) } )   -- l's scope ends
```

It is typed (`mainV_typed`; before, `Ty.lkPay` refused `vec DT` as a lock's
payload), safe (`mainV_safe`) and leak-free (`mainV_no_leak`,
`mainV_no_leak_panic`).  When nothing refers to the lock block any more, the
marking sweep marks it `dead`, its payload in it, and the thread's next step
is the reap (`last_dropV_reaps`), which binds the `Vec` at its own type in a
destructor frame of `dfn` whose end drains it, element 0 first, each element
to a `letd` frame of its own (`reapV_drains`, as
`A2.ArcDtorWitness.reapV_drains`), as nurlc's last `Locked_drop` drops the
`Vec`'s elements in index order.  The check-out's end gives the `Vec` back
(`scopeL_end_gives_back` at `t = vec DT`: the type holds no share), and the
body gives the binding no other value (`StmtT.withLock`'s `hna`): a push is
no assignment, and the model's in-place drops (`free`, the edits `trunc`
and `set`, `withElem`; `vec_clear` is a truncation to 0, or code,
`A2/DropCode.lean`) ask elements that own no destructor value. -/

/-- `: a 1  : b 2  :drop v ( vec_new DT )  : l ( locked_new v )
     ( locked_update l @ w { :drop x ( pair a b )  ( vec_push w x ) } )`
    (the payload checked out to `w = 4`, the new element `x = 5`). -/
def mainV : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2)) (.letd 2 0 (.new DT)
    (.letv 3 (.lockNew (.vec DT) 2) (.withLock 3 4 (.letd 5 0 (.pair 0 1) (.push 4 5))))))

/-- The lock share's entry: owned, holding nothing. -/
def ELV : Entry := ⟨.lk (.vec DT), .own, true, [], [], false, false⟩

theorem lockE_vecDT : lockE (.vec DT) = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
  unfold lockE; simp

/-- **A `Locked` of a `Vec` of destructor values is typed** (Agora #755:
    `Ty.lkPay` admits a drained `Vec` that holds no share, `RhsT.lockNew`
    takes it), and so is a push into the checked-out `Vec` (`StmtT.withLock`:
    the body gives the binding no other value). -/
theorem mainV_typed : ∃ Δ, StmtT P (fun _ => none) [] mainV Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  -- the `Vec`
  let EN : Entry := ⟨.vec DT, .own, true, [], [], false, false⟩
  have hnew : RhsT K2 [] (.new DT) EN K2 := RhsT.new (by decide)
  let EV : Entry := Entry.arm { EN with ty := .vec DT, held := [] }
  have hEVe : EV = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [EV, EN, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 EV
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEVe]; simp)
  have hK3d : K3 2 = some EV := by simp [K3, A2.setE]
  -- `locked_new v`: the `Vec` moves into the lock block
  let K3' : Ctx := A2.setE (kill .replace false 2 K3) 2 { EV with live := false, dtor := false }
  have hK3' : NoRootb K3' := (hK3.kill _ _ _).setE (by rw [hEVe]; simp)
  have hmove : PushArg K3 [] 2 EV (.vec DT) EV.held K3' :=
    PushArg.move (Γ := K3) (F := []) (y := 2) (E := EV) (t := .vec DT) rfl (by rw [hEVe]) (by simp)
      (hK3.noPin _) (DtorSafe.of_none (fun v E h => (hK3 v E h).2.1) _ _ _)
  have hlnew : RhsT K3 [] (.lockNew (.vec DT) 2) ELV K3' :=
    RhsT.lockNew hK3d (by rw [hEVe]) (by rw [hEVe]) (by decide)
      ⟨by simp [DT, T, Ty.holdsView], by simp [DT, T, Ty.hasFn]⟩ hmove
  let K4 : Ctx := A2.setE K3' 3 ELV
  have hK4 : NoRootb K4 := hK3'.setE (by simp [ELV])
  have hK43 : K4 3 = some ELV := by simp [K4, A2.setE]
  -- the check-out: `w = 4`, a `vec DT`
  let K5 : Ctx := A2.setE K4 4 (lockE (.vec DT))
  have hK5 : NoRootb K5 := hK4.setE (by rw [lockE_vecDT]; simp)
  -- `:drop x ( pair a b )`
  have hpair : RhsT K5 [] (.pair 0 1) EP K5 :=
    RhsT.pair (Ey := intE) (Ez := intE)
      (by simp [K5, K4, K3', K3, K2, K1, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps, Mode.ownSlot])
      rfl PushArg.int
      (by simp [K5, K4, K3', K3, K2, K1, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps, Mode.ownSlot])
      rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K6 : Ctx := A2.setE K5 5 ED
  have hK6 : NoRootb K6 := hK5.setE (by rw [hEDe]; simp)
  -- `vec_push w x`: `x` moves into the checked-out `Vec`
  let K7 : Ctx := A2.setE (kill .replace false 5 K6) 5 { ED with live := false, dtor := false }
  have hK7 : NoRootb K7 := (hK6.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove2 : PushArg K6 [] 5 ED DT ED.held K7 :=
    PushArg.move (Γ := K6) (F := []) (y := 5) (E := ED) (t := DT) rfl (by rw [hEDe]) (by simp)
      (hK6.noPin _) (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _)
  let EW : Entry := lockE (.vec DT)
  have hK74 : K7 4 = some EW := by
    simp [K7, K6, K5, A2.setE, upd, A2.kill, killE, hits, EW, lockE_vecDT, Entry.vdeps, Mode.ownSlot]
  have hpush := StmtT.push (P := P) (Γ := K6) (Γ1 := K7) (F := []) (x := 4) (y := 5) (Ex := EW) (Ey := ED)
    (Ex1 := EW) (t := DT) (D := ED.held) (by simp [K6, K5, A2.setE, upd, EW]) (by simp [EW])
    (by simp [EW]) (Or.inl (by simp [EW, lockE_vecDT])) (by simp) (by simp [K6, A2.setE])
    (by rw [hEDe]) (by rw [hEDe]) (by decide) hmove2 (by rw [hEDe]; simp [roots]) hK74 (by simp [EW])
    (DtorSafe.of_none (fun v E h => (hK7 v E h).2.1) _ _ _) (by simp [EW])
  let E4 : Entry := { EW with held := EW.held ++ ownHeld true DT ED.held }
  have hE4e : E4 = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [E4, EW, lockE_vecDT, hEDe, ownHeld]
  let K8 : Ctx := A2.setE (kill .realloc DT.holdsView 4 K7) 4 E4
  have hK8 : NoRootb K8 := (hK7.kill _ _ _).setE (by rw [hE4e]; simp)
  have hd := StmtT.letd (P := P) (Γ := K5) (Γ1 := K5) (F := []) (x := 5) (f := 0) (r := .pair 0 1)
    (s := .push 4 5) (E := EP) (t := T) (H := []) rfl (by simp [K5, K4, K3', K3, K2, K1, A2.setE, upd, A2.kill])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop0_ok) (HeldUp.refl _ _) hpush
    (hK8.endOK _)
  -- the lock scope's body ends with `w` live, holding a `vec DT` again
  have hlk := StmtT.withLock (P := P) (Γ := K4) (F := []) (a := 3) (x := 4)
    (s := .letd 5 0 (.pair 0 1) (.push 4 5)) (Ea := ELV) (t := .vec DT) rfl
    (by simp [K4, K3', K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hK43 rfl (Or.inl rfl) hd
    ((hK8.exitScope 5).endOK _) rfl (by simp [Stmt.vars, Rhs.vars])
    ⟨E4, by simp [exitScope, A2.setE, upd, A2.kill, killE, hits, E4, EW, lockE_vecDT, ownHeld,
      DT, T, Ty.holdsView, Entry.vdeps, Mode.ownSlot],
      by rw [hE4e]⟩ (by intro _; simp [Stmt.assigns])
  have hl := StmtT.letv (P := P) (x := 3) (r := .lockNew (.vec DT) 2) (E := ELV) (F := []) (Γ := K3)
    (Γ1 := K3') rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) hlnew hlk
    (((hK8.exitScope 5).exitScope 4).endOK _) (fun _ => rfl)
  have hdv := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .new DT)
    (s := .letv 3 (.lockNew (.vec DT) 2) (.withLock 3 4 (.letd 5 0 (.pair 0 1) (.push 4 5)))) (E := EN)
    (t := T) (H := []) (τ := .vec DT) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop0_ok) (HeldUp.refl _ _) hl
    ((((hK8.exitScope 5).exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hdv
    (((((hK8.exitScope 5).exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    ((((((hK8.exitScope 5).exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- `locked_new` of the `Vec` names the elements' destructor, one the program
    checked (`Rhs.codeOK`). -/
theorem mainV_codes : mainV.codesOK P := by
  simp only [mainV, Stmt.codesOK, Rhs.codeOK]
  exact ⟨trivial, trivial, trivial, arcNew_codeOK (n := 1) drop0_ok, trivial, trivial⟩

/-- **Every run of it is safe.** -/
theorem mainV_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 6) mainV (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := mainV_typed
  exact memory_safe prog_ok prog_codes ht rfl mainV_codes (by decide) hr

/-- **... and leaks nothing** (`no_leak_end`; that the `Vec` was reaped and
    drained on the way is read off the steps, `last_dropV_reaps` /
    `reapV_drains`, not stated here). -/
theorem mainV_no_leak {m' : Mem} (hr : Steps P (emptyMem 6) mainV (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := mainV_typed
  exact no_leak_end prog_ok prog_codes ht rfl mainV_codes (by decide) hr

/-- **... and on a panic either** (`no_leak_panic`). -/
theorem mainV_no_leak_panic {m' : Mem} (hr : Steps P (emptyMem 6) mainV (.panic m')) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := mainV_typed
  exact no_leak_panic prog_ok prog_codes ht rfl mainV_codes (by decide) hr

/-- **The lock's last share's drop hands the `Vec` to a destructor frame of
    the same thread**: when no slot's value and no block's payload refers to
    the lock block, its payload in it, the marking sweep marks it `dead`
    (`Mem.sweepD_marks`, at a lock block of the nest `vec (dtor 0 T)`), and
    the thread's next step is a reap (`settle_reaps`). -/
theorem last_dropV_reaps {m : Mem} {k : Nat} {p : Val} (hk : m.blk k = some ⟨.vec DT, .lock, some p⟩)
    (hv : ∀ x o v, m.st x = some ⟨o, some v⟩ → ¬ Refers m.blk v k)
    (hb : ∀ k' bl', m.blk k' = some bl' → ¬ Refers m.blk bl'.keeps k)
    {s s' : Stmt} {m' : Mem} (h : Settle P m.sweepD s m' s') :
    m.sweepD.blk k = some ⟨.vec DT, .dead, some p⟩ ∧
      ∃ m1 s1, Step P m.sweepD s (.ok m1 s1) ∧ ReapMem m.sweepD m1 := by
  have hm := Mem.sweepD_marks (n := 1) (f := 0) (u := T) (Or.inr rfl) hk hv hb
  exact ⟨hm, settle_reaps h ⟨k, 1, 0, T, p, hm⟩⟩

/-- **The reap binds the `Vec` at its own type, and its frame drains it**
    (as `A2.ArcDtorWitness.reapV_drains`: the marked block is `dead`, of no
    kind left): `Step.reap` moves the `Vec` to the fresh slot `m.nv` and puts
    `scopeD m.nv 0 skip` before the redex; that frame's end is the drain and
    nothing else, element 0 to a `letd` frame of `dfn` of its own. -/
theorem reapV_drains {m : Mem} {k : Nat} {t : Ty} {c d : Nat} {e : Val} {es : List Val}
    (hk : m.blk k = some ⟨.vec DT, .dead, some (.node t c d (e :: es))⟩)
    (hnc : ∀ c', ¬ Sub (.cell c') (.node t c d (e :: es))) {r : Stmt} (hr : r.src = true) :
    ∃ m1, Step P m r (.ok m1 (.seq (.scopeD m.nv 0 .skip) r)) ∧
      m1.st m.nv = some ⟨true, some (.node t c d (e :: es))⟩ ∧
      ∀ m2 : Mem, m2.st m.nv = some ⟨true, some (.node t c d (e :: es))⟩ → ¬ Orphan m2 →
        ∀ r', Step P m2 (.scopeD m.nv 0 .skip) r' ↔
          r' = .ok { m2 with nv := m2.nv + 1 } (.scopeD m.nv 0 (.letd m2.nv 0 (.remove m.nv (.lit 0)) .skip)) := by
  refine ⟨_, Step.reap (n := 1) (f := 0) (u := T) hr hk hnc, by simp [Mem.set, upd], fun m2 hx hno r' => ?_⟩
  obtain ⟨h1, h2⟩ := A2.Dtor.scopeD_end_drains (P := P) (f := 0) hx hno
  exact ⟨h2 r', fun h => h ▸ h1⟩

end A3.LockDtorWitness

namespace A3

/-- Agora #755, the witness (`A3.LockDtorWitness.main`): a `Locked` of a
    destructor value, made, updated through `locked_apply`, its last share
    dropped, on one thread.  The claim covers it: safe, race-free and
    leak-free on every interleaving.  (As for `arcDtor_claim`, on A3's
    threads the thread that drops the last share reaps the lock block's
    payload and runs its destructor, `A3.lockDtor_reaps`; on A2's `Steps`,
    `A3.LockDtorWitness.last_drop_reaps`.) -/
theorem lockDtor_claim :
    MemorySafe LockDtorWitness.P (fun _ => false) (Cfg.start Globs.empty LockDtorWitness.main 7) ∧
      RaceFree LockDtorWitness.P (fun _ => false) (Cfg.start Globs.empty LockDtorWitness.main 7) ∧
      NoLeak LockDtorWitness.P (fun _ => false) (Cfg.start Globs.empty LockDtorWitness.main 7) := by
  obtain ⟨Δ, ht⟩ := LockDtorWitness.main_typed
  exact claim _ _ Globs.empty _ Δ 7 LockDtorWitness.prog_ok LockDtorWitness.prog_codes
    (fun _ h => by cases h) GlobsOK.empty ht rfl LockDtorWitness.main_codes (by decide)

/-- Agora #755, `Locked (Vec D)` (`A3.LockDtorWitness.mainV`): a `Locked` of
    a `Vec` of destructor values, pushed to through the check-out, its last
    share dropped.  The claim covers it. -/
theorem lockVecDtor_claim :
    MemorySafe LockDtorWitness.P (fun _ => false) (Cfg.start Globs.empty LockDtorWitness.mainV 6) ∧
      RaceFree LockDtorWitness.P (fun _ => false) (Cfg.start Globs.empty LockDtorWitness.mainV 6) ∧
      NoLeak LockDtorWitness.P (fun _ => false) (Cfg.start Globs.empty LockDtorWitness.mainV 6) := by
  obtain ⟨Δ, ht⟩ := LockDtorWitness.mainV_typed
  exact claim _ _ Globs.empty _ Δ 6 LockDtorWitness.prog_ok LockDtorWitness.prog_codes
    (fun _ h => by cases h) GlobsOK.empty ht rfl LockDtorWitness.mainV_codes (by decide)

end A3
