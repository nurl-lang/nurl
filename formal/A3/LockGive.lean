import A3.Claim
import A2.Dtor

/-! The give-back of a check-out (Agora #805, #825, #837), and `locked_restore`
of a destructor value (Agora #810): lemmas about every typed program, which
A3's claim uses (`A3.LockExcl`).  Apart from `A3/LockDtorWitness.lean`, whose
witness programs they were first proved for, so that a certificate loads no
witness program (AGORA-1013); the names stay in `A3.LockDtorWitness`. -/

namespace A3.LockDtorWitness
open A2
open A2.DynCell (NoRootb noRootb_empty)

/-! ### The give-back of a payload that holds no share (before Agora #803) -/

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
  | rguard => simp [Ty.hasArc] at h
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

/-! ### Agora #837: the give-back's crossing check passes on a typed payload

A read guard is `% NotSend` (nurlc's `RGuard`): no lock's or cell's payload
type holds one (`Ty.ok`'s `lk` and `cell` cases ask `!hasGuard`), nor does any
block's type (`MInv.blocks`).  Only a guard's share names a view (`ArcBlk`),
so a value of a type that holds no guard and no view reaches no view, through
the payloads of the blocks it reaches either (`noGuard_of_free`).  With no
cell share as well (every destructor payload, `Ty.lkPay`), the crossing check
(`SendCheck`) cannot fail on it (`sendCheck_free`): a typed check-out's
give-back passes it (`giveCheck_typed`), whatever shares it holds. -/

/-- A closure's type may hold a read guard when its environment holds one:
    only the class `any`, which crosses nowhere, admits one (`Cross.Fits`). -/
theorem _root_.A2.Cross.Fits.fn_hasGuard {q : Cross} {te : Ty} {cs : List (Var × PMode × Ty)}
    (hq : q.Fits te cs) (h : te.hasGuard = true) (ms : List Nat) : (Ty.fn ms q).hasGuard = true := by
  cases q with
  | any => rfl
  | _ => rw [hq.guard rfl] at h; cases h

/-- A share of a read guard lies only in a tree of a type that holds a
    guard (a closure's environment that holds one is of a class that may,
    `Cross.Fits`). -/
theorem _root_.A2.ArcIn.guard_hasGuard {σ : Ty} {T : Val} {u : Ty} {k : Nat} {p : Option Val}
    (ha : ArcIn σ T u k p) (hw : WFv σ T) (hu : u.isGuard = true) : σ.hasGuard = true := by
  induction ha with
  | here => rename_i u' _ _; cases u' <;> simp_all [Ty.isGuard, Ty.hasGuard]
  | rguard => rfl
  | lk => rename_i u' _; cases u' <;> simp_all [Ty.isGuard, Ty.hasGuard]
  | cell => rename_i u' _; cases u' <;> simp_all [Ty.isGuard, Ty.hasGuard]
  | child he _ ih =>
    cases hw with
    | node hes => simpa [Ty.hasGuard] using ih (hes _ he) hu
  | fst _ ih => cases hw with | pair ha _ => simp [Ty.hasGuard, ih ha hu]
  | snd _ ih => cases hw with | pair _ hb => simp [Ty.hasGuard, ih hb hu]
  | inl _ ih => cases hw with | inl ha => simp [Ty.hasGuard, ih ha hu]
  | inr _ ih => cases hw with | inr hb => simp [Ty.hasGuard, ih hb hu]
  | pkg _ _ ih =>
    cases hw with
    | pkg hwe hq => exact hq.fn_hasGuard (ih hwe hu) _
  | dtor _ ih => cases hw with | dtor _ hw' => exact ih hw' hu

/-- A well-formed tree holds no handle into a payload (`Val.href` is no
    tree of any type). -/
theorem _root_.A2.WFv.not_href {τ : Ty} {v : Val} (hw : WFv τ v) {c : Nat} : ¬ Sub (.href c) v := by
  induction hw with
  | node _ ih => intro h; cases h with | child he hs => exact ih _ he hs
  | pair _ _ iha ihb =>
    intro h
    cases h with
    | fst h => exact iha h
    | snd h => exact ihb h
  | inl _ ih => intro h; cases h with | inl h => exact ih h
  | inr _ ih => intro h; cases h with | inr h => exact ih h
  | pkg _ _ ih => intro h; cases h with | pkg h => exact ih h
  | dtor _ _ ih => exact ih
  | _ => intro h; cases h

/-- **Agora #837: a tree of a type that holds no read guard and no view
    refers to no view**: its shares name `arc` blocks and lock blocks (only
    a guard's share names a view, `ArcBlk`), and it holds no handle into a
    payload and no view (`Refers`). -/
theorem _root_.A2.WFv.refers_noView {B : Nat → Option Blk} {σ : Ty} {v : Val} (hw : WFv σ v)
    (hsh : SharesIn B σ v) (hg : σ.hasGuard = false) (hvf : σ.holdsView = false) {k : Nat}
    (hr : Refers B v k) {bl : Blk} (hk : B k = some bl) : bl.kind ≠ .view := by
  rcases hr with hs | ⟨bl', _, ⟨c, hs, _⟩ | ⟨d, o, l, hs, _⟩⟩
  · obtain ⟨u, p, ha⟩ : ∃ u p, ArcIn σ v u k p := by
      rcases hs with ⟨p, hs⟩ | hs
      · exact hw.sub_share (Or.inl ⟨p, rfl⟩) hs
      · exact hw.sub_share (Or.inr rfl) hs
    have hf := hsh u k p ha
    rw [hk] at hf
    cases p with
    | none => obtain ⟨o, h⟩ := hf; cases h; simp
    | some p =>
      rcases hf with ⟨_, h⟩ | ⟨w, _, _, rfl, _, _⟩
      · cases h; simp
      · rw [ha.guard_hasGuard hw rfl] at hg; cases hg
  · exact absurd hs hw.not_href
  · obtain ⟨s, hin⟩ := hw.sub_view hs
    have := hin.holdsView; rw [hvf] at this; cases this

/-- What the invariant says of every block's payload (`MInv.blocks`,
    `BlocksIn`): a well-formed tree of the block's type, whose shares name
    blocks, of a type that holds no read guard (Agora #837) and no view. -/
def BlksFree (B : Nat → Option Blk) : Prop :=
  ∀ k bl p, B k = some bl → bl.pay = some p →
    WFv bl.ty p ∧ SharesIn B bl.ty p ∧ bl.ty.hasGuard = false ∧ bl.ty.holdsView = false

theorem _root_.A2.BlocksIn.free {m : Mem} (h : BlocksIn m) : BlksFree m.blk := fun k bl p hk hp => by
  obtain ⟨_, hvf, hpay, _, _, hg⟩ := h k bl hk
  exact ⟨(hpay p hp).1, (hpay p hp).2, hg, hvf⟩

/-- **Agora #837: a value of a type that holds no read guard and no view
    reaches no view** (`NoGuard`): not through its own shares
    (`WFv.refers_noView`), nor through the payloads of the blocks it reaches,
    whose types hold none either (`BlksFree`). -/
theorem noGuard_of_free {B : Nat → Option Blk} (hB : BlksFree B) {τ : Ty} {v : Val} (hw : WFv τ v)
    (hsh : SharesIn B τ v) (hg : τ.hasGuard = false) (hvf : τ.holdsView = false) : NoGuard B [v] := by
  intro k hr bl hk
  cases hr with
  | root hv hr =>
    simp only [List.mem_singleton] at hv; subst hv
    exact hw.refers_noView hsh hg hvf hr hk
  | @pay _ k' bl' _ hk' hr =>
    cases hp : bl'.pay with
    | none =>
      simp only [Blk.keeps, hp, Option.getD_none] at hr
      exact WFv.int.refers_noView (fun _ _ _ ha => ha.not_int.elim) rfl rfl hr hk
    | some p =>
      simp only [Blk.keeps, hp, Option.getD_some] at hr
      obtain ⟨hw', hsh', hg', hvf'⟩ := hB k' bl' p hk' hp
      exact hw'.refers_noView hsh' hg' hvf' hr hk

/-- **The crossing check cannot fail on a value of a type that holds no cell
    share, no read guard and no view** (`SendCheck`): it holds no cell share
    (`WFv.noCell_hasCell`) and reaches no view (`noGuard_of_free`).  It may
    hold `arc` and lock shares (Agora #803's `Locked Conn`). -/
theorem sendCheck_free {B : Nat → Option Blk} (hB : BlksFree B) {τ : Ty} {v : Val} (hw : WFv τ v)
    (hsh : SharesIn B τ v) (hg : τ.hasGuard = false) (hvf : τ.holdsView = false)
    (hnc : τ.hasCell = false) (st : Var → Option Slot) : SendCheck B [v] st := by
  refine ⟨fun k ⟨w, hw', hs⟩ => ?_, noGuard_of_free hB hw hsh hg hvf⟩
  simp only [List.mem_singleton] at hw'; subst hw'
  exact (hw.noCell_hasCell hnc hs).elim

/-- ... so the give-back's check (`GiveCheck`) passes on what a check-out's
    binding can give back (`Giveable`) of such a type. -/
theorem giveCheck_of {m : Mem} (hB : BlocksIn m) {x : Var} {t : Ty} {o : Bool} {v : Val}
    (hg : Giveable m.blk t ⟨o, some v⟩) (hng : t.hasGuard = false) (hvf : t.holdsView = false)
    (hnc : t.hasCell = false) : GiveCheck m x ⟨o, some v⟩ := fun w hw => by
  cases hw
  exact sendCheck_free hB.free hg.wfv hg.shares hng hvf hnc _

/-- A checked-out lock block's payload type holds no read guard and no view
    (`MInv.blocks`, Agora #837), and, if it owns a destructor value, no cell
    share (`Ty.lkPay`, Agora #803). -/
theorem checkedOut_free {m : Mem} (hB : BlocksIn m) {k : Nat} {t : Ty} (hk : CheckedOut m k t) :
    t.hasGuard = false ∧ t.holdsView = false ∧ (t.dtorFree = false → t.hasCell = false) := by
  obtain ⟨_, hvf, _, _, hdk, hg⟩ := hB k _ hk.1
  refine ⟨hg, hvf, fun hd => ?_⟩
  rcases hdk.1 (by simp) (by simp) with h | ⟨_, h⟩ | ⟨h, _⟩
  · simp only at h; rw [hd] at h; cases h
  · exact (Ty.lkPay_dtor h hd).2
  · cases h

/-- What a check-out's binding can give back to a block of a `t`
    (`Giveable`): a tree of the payload's type it owns, whose shares name
    blocks (`MInv.shares`; Agora #837: of every payload type, shares
    included, where Agora #825 asked `hasArc = false`), or, for an integer
    payload, the integer a plain integer binding holds. -/
theorem giveable_of {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry} {t : Ty}
    (hx : Γ x = some E) (hty : E.ty = t) {o : Bool} {v : Val} (hsl : m.st x = some ⟨o, some v⟩)
    (hw : WFv t v) (ho : o = true ∨ t = .int) : Giveable m.blk t ⟨o, some v⟩ := by
  cases o with
  | true =>
    have hsh := hi.shares x E _ v hx hsl rfl rfl
    rw [hty] at hsh
    exact ⟨hw, hsh⟩
  | false =>
    rcases ho with h | rfl
    · cases h
    · cases hw; rfl

/-- What can be given back to a block can be over blocks that grew. -/
theorem Giveable.grow {B B' : Nat → Option Blk} (hb : BlkLe B B') {t : Ty} {o : Bool} {v : Val}
    (h : Giveable B t ⟨o, some v⟩) : Giveable B' t ⟨o, some v⟩ := by
  cases o with
  | true => exact ⟨h.1, h.2.grow hb⟩
  | false => cases v <;> exact h

/-- **Agora #837, `giveCheck_typed`: a typed check-out's value passes the
    give-back's crossing check**: in a typed store (`MInv`), what the
    binding of a check-out of block `k` holds (a `t`, owned, or an integer
    payload's plain integer) can be given back (`Giveable`) and passes
    `GiveCheck`, when the payload type holds no cell share: no cell and no
    read guard (the block's type holds none, `checkedOut_free`).  Every
    destructor payload qualifies (`giveCheck_typed_dtor`); a payload that
    owns no destructor value and holds a cell share may fail the cell half,
    as nurlc's `locked_with` panics when a handle's other owner is kept
    (h340). -/
theorem giveCheck_typed {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry} {t : Ty} {k : Nat}
    (hx : Γ x = some E) (hty : E.ty = t) {o : Bool} {v : Val} (hsl : m.st x = some ⟨o, some v⟩)
    (hw : WFv t v) (ho : o = true ∨ t = .int) (hk : CheckedOut m k t) (hnc : t.hasCell = false) :
    Giveable m.blk t ⟨o, some v⟩ ∧ GiveCheck m x ⟨o, some v⟩ := by
  have hg := giveable_of hi hx hty hsl hw ho
  obtain ⟨hng, hvf, _⟩ := checkedOut_free hi.blocks hk
  exact ⟨hg, giveCheck_of hi.blocks hg hng hvf hnc⟩

/-- ... for every destructor payload (`Ty.lkPay`'s: no cell share). -/
theorem giveCheck_typed_dtor {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry} {t : Ty} {k : Nat}
    (hx : Γ x = some E) (hty : E.ty = t) {o : Bool} {v : Val} (hsl : m.st x = some ⟨o, some v⟩)
    (hw : WFv t v) (ho : o = true ∨ t = .int) (hk : CheckedOut m k t) (hd : t.dtorFree = false) :
    Giveable m.blk t ⟨o, some v⟩ ∧ GiveCheck m x ⟨o, some v⟩ :=
  giveCheck_typed hi hx hty hsl hw ho hk ((checkedOut_free hi.blocks hk).2.2 hd)

/-- **The lock scope's release puts the value back**: from a store where `x`
    holds what it can give back (`Giveable`), passing the crossing check
    (`GiveCheck`), and the block has its payload checked out, every release
    (`Release`) is the give-back `Release.put`, never the code-less drop. -/
theorem release_puts {m m' : Mem} {k : Nat} {t : Ty} {x : Var} {o : Bool} {v : Val}
    (hx : m.st x = some ⟨o, some v⟩) (hg : Giveable m.blk t ⟨o, some v⟩) (hgc : GiveCheck m x ⟨o, some v⟩)
    (hk : CheckedOut m k t) (hr : Release m k t x m') :
    m' = ({ m with blk := upd m.blk k (some ⟨t, .lock, some v⟩) }.remove x) := by
  cases hr with
  | put hx' _ _ _ => rw [hx] at hx'; cases hx'; rfl
  | drop hno _ hx' _ =>
    rw [hx] at hx'; cases hx'
    rcases hno with h | h | h
    · exact absurd hk h
    · exact absurd hg h
    · exact absurd hgc h

/-- **Agora #755: the check-out's end gives the value back, and nothing
    else**: at `scopeL k t x skip`, with `x` holding what it can give back,
    passing the crossing check, the block checked out and no orphan to reap
    first, the one step is the give-back (`Step.scopeLSkip` with
    `Release.put`): `Step.scopeLFail` is not taken and the value is not
    dropped. -/
theorem scopeL_end_gives_back {P : Prog} {m : Mem} {k : Nat} {t : Ty} {x : Var} {o : Bool} {v : Val}
    (hx : m.st x = some ⟨o, some v⟩) (hg : Giveable m.blk t ⟨o, some v⟩) (hgc : GiveCheck m x ⟨o, some v⟩)
    (hk : CheckedOut m k t) (hno : ¬ Orphan m) {r : Res}
    (h : Step P m (.scopeL k t x .skip) r) :
    r = .ok ({ m with blk := upd m.blk k (some ⟨t, .lock, some v⟩) }.remove x) .skip := by
  cases h with
  | scopeLIn hs => exact (A2.Dtor.skip_no_step hno hs).elim
  | scopeLSkip hrl _ => rw [release_puts hx hg hgc hk hrl]
  | scopeLFail hx' hng =>
    rw [hx] at hx'; cases hx'
    exact absurd hgc hng
  | scopeLP hs _ => exact (A2.Dtor.skip_no_step hno hs).elim
  | scopeLPD hs _ _ _ _ => exact (A2.Dtor.skip_no_step hno hs).elim
  | waitPanic hw' => exact hw'.elim
  | reap hrs _ _ => cases hrs

/-- **Agora #755: a panic in the body gives the value back**: a panic that
    unwinds through the check-out (`Step.scopeLP`) leaves the store whose
    block holds again what `x` held, when `x` still holds what it can give
    back, passing the crossing check, and the block is checked out (nurlc's
    `locked_update` runs in place: the value stays in the lock's memory). -/
theorem scopeL_panic_gives_back {P : Prog} {m m2 : Mem} {k : Nat} {t : Ty} {x : Var} {s : Stmt}
    (h : Step P m (.scopeL k t x s) (.panic m2)) :
    ∃ m1, Step P m s (.panic m1) ∧
      ∀ o v, m1.st x = some ⟨o, some v⟩ → Giveable m1.blk t ⟨o, some v⟩ → GiveCheck m1 x ⟨o, some v⟩ →
        CheckedOut m1 k t →
        m2 = ({ m1 with blk := upd m1.blk k (some ⟨t, .lock, some v⟩) }.remove x) := by
  cases h with
  | scopeLP hs hrl =>
    exact ⟨_, hs, fun o v hx hg hgc hk => release_puts hx hg hgc hk hrl⟩
  | waitPanic hw => exact hw.elim

/-- Agora #825: **the typing of a check-out frame names its binding as
    `withLock` bound it**: of the payload's type, no root borrow, and an
    owner unless the payload is an integer (`lockE`: then a plain integer
    binding), for every payload type (`StmtT.scopeL`, through `sub`). -/
theorem scopeL_entry {P : Prog} {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var} {s : Stmt}
    (ht : StmtT P ξ Γ F (.scopeL k t x s) Δ) :
    ∃ E, Γ x = some E ∧ E.mode ≠ .rootb ∧ (t ≠ .int → E.mode = .own) ∧ E.ty = t := by
  generalize hs : Stmt.scopeL k t x s = st at ht
  induction ht with
  | scopeL hxE _ _ _ =>
    cases hs
    obtain ⟨E, hx, hrb, hty, hmo, _⟩ := hxE
    exact ⟨E, hx, hrb, hmo, hty⟩
  | @sub _ Γa Γ0 _ _ _ _ hw _ _ ih =>
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
    (ht : StmtT P ξ Γ F (.scopeL k t x .skip) Δ) :
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
  | @sub _ Γa Γ0 _ _ _ _ hw _ _ ih =>
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
      | region => exact absurd hE (hi.noRegion x E hx)
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
    (ht : StmtT P ξ Γ F (.scopeL k t x .skip) Δ) (hi : MInv m Γ) :
    ∃ o v, m.st x = some ⟨o, some v⟩ ∧ WFv t v ∧ (o = true ∨ t = .int) := by
  obtain ⟨E, hx, hl, hrb, hmo, hty⟩ := scopeL_end_entry ht
  exact frame_slot_live hi hx hl hrb hmo hty

/-- **The check-out's end gives the value back, for a typed frame**, of
    every payload type that holds no cell share (Agora #837; every
    destructor payload, `Ty.lkPay`; Agora #825 asked no share and no view):
    with `x`'s value discharged by the typing (`scopeL_end_owns`) and its
    crossing check by `giveCheck_typed`, what is left of
    `scopeL_end_gives_back`'s hypotheses is the block's: that it has its
    payload checked out (`CheckedOut m k t`: `m.blk k = some ⟨t, .lock, none⟩`,
    not taken), which
    Agora #808 proves of every reached configuration's frame
    (`A3.reach_scopeL_end_gives_back`). -/
theorem scopeL_typed_end_gives_back {P : Prog} {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var}
    {m : Mem} (ht : StmtT P ξ Γ F (.scopeL k t x .skip) Δ) (hi : MInv m Γ)
    (hnc : t.hasCell = false) (hk : CheckedOut m k t)
    (hno : ¬ Orphan m) {r : Res} (h : Step P m (.scopeL k t x .skip) r) :
    ∃ o v, m.st x = some ⟨o, some v⟩ ∧
      r = .ok ({ m with blk := upd m.blk k (some ⟨t, .lock, some v⟩) }.remove x) .skip := by
  obtain ⟨E, hx, hl, hrb, hmo, hty⟩ := scopeL_end_entry ht
  obtain ⟨o, v, hxs, hw, ho⟩ := frame_slot_live hi hx hl hrb hmo hty
  obtain ⟨hg, hgc⟩ := giveCheck_typed hi hx hty hxs hw ho hk hnc
  exact ⟨o, v, hxs, scopeL_end_gives_back hxs hg hgc hk hno h⟩

/-- **Agora #837: at a typed check-out's end the crossing check passes**, of
    every payload type that holds no cell share: `Step.scopeLFail` never
    fires there. -/
theorem scopeL_typed_end_giveCheck {P : Prog} {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var}
    {m : Mem} (ht : StmtT P ξ Γ F (.scopeL k t x .skip) Δ) (hi : MInv m Γ)
    (hnc : t.hasCell = false) (hk : CheckedOut m k t) {sl : Slot} (hsl : m.st x = some sl) :
    GiveCheck m x sl := by
  obtain ⟨E, hx, hl, hrb, hmo, hty⟩ := scopeL_end_entry ht
  obtain ⟨o, v, hxs, hw, ho⟩ := frame_slot_live hi hx hl hrb hmo hty
  rw [hxs] at hsl; cases hsl
  exact (giveCheck_typed hi hx hty hxs hw ho hk hnc).2

/-- A panic's unwinding changes no slot but the frames' it unwinds (the
    statement's spine). -/
theorem Step.panic_st {P : Prog} {m m1 : Mem} {s : Stmt} (h : Step P m s (.panic m1)) :
    ∀ y, y ∉ s.spine → m1.st y = m.st y := by
  generalize hr : Res.panic m1 = r at h
  induction h generalizing m1 with
  | seqP _ ih => cases hr; exact fun y hy => ih rfl y (by simpa [Stmt.spine] using hy)
  | letvP _ | assignP _ | letdP _ | panic | waitPanic _ | withElemOOB _ _ _ _ | takeBOOB _ _ _ =>
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
  | blockP _ ih => cases hr; exact fun y hy => ih rfl y (by simpa [Stmt.spine] using hy)
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

/-- A3.3: a panic's unwinding leaves the blocks as they were, or lock blocks
    given back a payload of their type (`BlkBack`), whatever the store's
    addresses (the part of `panic_unwind` that reads no `HeapOK`). -/
theorem Step.panic_blkBack {P : Prog} {m m1 : Mem} {s : Stmt} (h : Step P m s (.panic m1)) :
    BlkBack m.blk m1.blk := by
  generalize hr : Res.panic m1 = r at h
  induction h generalizing m1 with
  | seqP _ ih => cases hr; exact ih rfl
  | letvP _ | assignP _ | letdP _ | panic | waitPanic _ | withElemOOB _ _ _ _ | takeBOOB _ _ _ =>
    cases hr; exact BlkBack.refl _
  | scopeP _ _ _ ih => cases hr; have h := ih rfl; exact h
  | rbindP _ _ ih => cases hr; have h := ih rfl; exact h
  | frozenP _ ih | blockP _ ih => cases hr; exact ih rfl
  | scopeDPMoved _ _ ih => cases hr; have h := ih rfl; exact h
  | scopeLP _ hrl ih => cases hr; exact (ih rfl).trans hrl.back
  | _ => cases hr

/-- Agora #825: **a release from a check-out binding's slot**: holding a `t`
    (owned, or an integer payload's plain integer), it gives the value back
    when the block has its payload checked out and the value can be given
    back, passing the crossing check (`hgive`; Agora #837: for a typed frame
    of a payload that holds no cell share, `scopeL_typed_panic`), by
    `release_puts`; owning nothing (moved out), or an integer binding's
    holding no integer, it frees nothing, the block left as it was.  A drop
    of a plain integer binding that holds an integer is the first case:
    with the block checked out it is the give-back (`release_puts`), so the
    second case holds of no slot that holds a `t`. -/
theorem release_cases {m1 m2 : Mem} {k : Nat} {t : Ty} {x : Var}
    (hgive : ∀ o v, m1.st x = some ⟨o, some v⟩ → WFv t v → (o = true ∨ t = .int) → CheckedOut m1 k t →
      Giveable m1.blk t ⟨o, some v⟩ ∧ GiveCheck m1 x ⟨o, some v⟩)
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
    | some v =>
      refine .inl ⟨true, v, hx1, hw v rfl, .inl rfl, fun hk => ?_⟩
      obtain ⟨hg, hgc⟩ := hgive true v hx1 (hw v rfl) (.inl rfl) hk
      exact release_puts hx1 hg hgc hk hrl
    | none =>
      refine .inr ⟨.inl hx1, ?_⟩
      cases hrl with
      | put hx' _ _ _ => rw [hx1] at hx'; cases hx'
      | drop _ _ hx' hdr => rw [hx1] at hx'; cases hx'; cases hdr; rfl
  · by_cases hwi : ∃ n, w = some (.int n)
    · obtain ⟨n, rfl⟩ := hwi
      refine .inl ⟨false, .int n, hx1, .int, .inr rfl, fun hk => ?_⟩
      obtain ⟨hg, hgc⟩ := hgive false (.int n) hx1 .int (.inr rfl) hk
      exact release_puts hx1 hg hgc hk hrl
    · have hni : ∀ n, w ≠ some (.int n) := fun n he => hwi ⟨n, he⟩
      cases hrl with
      | @put _ v hx' hg _ _ =>
        rw [hx1] at hx'; cases hx'
        obtain ⟨n, rfl⟩ : ∃ n, v = .int n := by cases v <;> simp_all [Giveable]
        exact absurd rfl (hni n)
      | drop _ _ hx' hdr =>
        rw [hx1] at hx'; cases hx'
        exact .inr ⟨.inr ⟨rfl, w, hx1, hni⟩, by cases hdr; rfl⟩

/-- Agora #837: **at a typed check-out's panic point, what `x` holds can be
    given back and passes the crossing check**, of a payload type that holds
    no cell share: the frame's binding holds what its typing says
    (`frame_slot`, over a store `mo` of the same slots and blocks as `m`, the
    one the step runs on), the body's unwinding leaves `x`'s slot as it was
    (`Step.panic_st`) and the blocks as the invariant asks
    (`Step.panic_blkBack`, `MInv.blocks_back`), so the shares the value holds
    still name blocks, and the checked-out block's type holds no guard
    (`giveCheck_of`). -/
theorem scopeL_typed_panic_give {P : Prog} {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var}
    {s : Stmt} {mo m m1 : Mem} (ht : StmtT P ξ Γ F (.scopeL k t x s) Δ) (hi : Inv mo Γ F (.scopeL k t x s))
    (hst0 : mo.st = m.st) (hb0 : mo.blk = m.blk) (hs : Step P m s (.panic m1)) (hnc : t.hasCell = false) :
    ∀ o v, m1.st x = some ⟨o, some v⟩ → WFv t v → (o = true ∨ t = .int) → CheckedOut m1 k t →
      Giveable m1.blk t ⟨o, some v⟩ ∧ GiveCheck m1 x ⟨o, some v⟩ := by
  intro o v hx1 hw ho hk1
  have hxsp : x ∉ s.spine := by
    have := hi.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.1
  have hxm : mo.st x = some ⟨o, some v⟩ := by rw [hst0, ← Step.panic_st hs x hxsp]; exact hx1
  obtain ⟨E, hx, _, _, hty⟩ := scopeL_entry ht
  have hback : BlkBack mo.blk m1.blk := by rw [hb0]; exact Step.panic_blkBack hs
  have hg := Giveable.grow hback.1 (giveable_of hi.toMInv hx hty hxm hw ho)
  have hB1 : BlocksIn m1 := MInv.blocks_back hi.toMInv hback
  obtain ⟨hng, hvf, _⟩ := checkedOut_free hB1 hk1
  exact ⟨hg, giveCheck_of hB1 hg hng hvf hnc⟩

/-- Agora #805, #825, #837: **at every panic point of a typed check-out, `x`
    holds a `t` or nothing**, for every payload type that holds no cell share
    (every destructor payload, shares included; Agora #825 asked no share and
    no view): a panic that unwinds through `scopeL k t x s` (`Step.scopeLP`)
    leaves `x`'s slot as the body's unwinding found it, as `withLock` bound
    it (the frame's typing, `scopeL_entry`, and `frame_slot`): an owner's,
    holding a `t` or moved out, or an integer payload's plain integer
    binding's.  Holding a `t` (an owner's tree, or an integer binding's
    integer), the release gives it back when the block has its payload
    checked out (`scopeL_typed_panic_give`, `release_puts`); holding nothing
    (an owner moved out, or an integer binding holding no integer), the
    release frees nothing (a moved-out value went to an owner that runs its
    destructor: A2-drop's binders), the block left as it was
    (`release_cases`).  Over a store `mo` of the same slots and blocks as the
    one the step runs on (a thread's view, A3). -/
theorem scopeL_typed_panic_at {P : Prog} {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var} {s : Stmt}
    {mo m m2 : Mem} (ht : StmtT P ξ Γ F (.scopeL k t x s) Δ) (hi : Inv mo Γ F (.scopeL k t x s))
    (hst0 : mo.st = m.st) (hb0 : mo.blk = m.blk) (hnc : t.hasCell = false)
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
    refine release_cases (scopeL_typed_panic_give ht hi hst0 hb0 hs hnc) ?_ hrl
    rw [hst, ← hst0]
    rcases frame_slot hi.toMInv hx hrb hmo hty with ⟨w, hsl, hw, _⟩ | ⟨hti, w, hsl, _⟩
    · exact .inl ⟨w, hsl, hw⟩
    · exact .inr ⟨hti, w, hsl⟩

/-- ... over the store the step runs on. -/
theorem scopeL_typed_panic {P : Prog} {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var} {s : Stmt}
    {m m2 : Mem} (ht : StmtT P ξ Γ F (.scopeL k t x s) Δ) (hi : Inv m Γ F (.scopeL k t x s))
    (hnc : t.hasCell = false)
    (h : Step P m (.scopeL k t x s) (.panic m2)) :
    ∃ m1, Step P m s (.panic m1) ∧
      ((∃ o v, m1.st x = some ⟨o, some v⟩ ∧ WFv t v ∧ (o = true ∨ t = .int) ∧
          (CheckedOut m1 k t →
            m2 = ({ m1 with blk := upd m1.blk k (some ⟨t, .lock, some v⟩) }.remove x))) ∨
        ((m1.st x = some ⟨true, none⟩ ∨
            (t = .int ∧ ∃ w, m1.st x = some ⟨false, w⟩ ∧ ∀ n, w ≠ some (.int n))) ∧
          m2 = m1.remove x)) :=
  scopeL_typed_panic_at ht hi rfl rfl hnc h

/-- **Agora #837: a destructor payload's check-out, typed, passes the
    give-back's check at every panic point**: whatever `x`'s slot holds
    there (a `t`, or nothing: an owner's moved-out slot, whose check is
    vacuous), `GiveCheck` holds once the block is checked out, the payload a
    destructor value (no cell share, `Ty.lkPay`; no read guard, `Ty.ok`).
    So `Step.scopeLPD`'s premise `¬ GiveCheck` never holds of a typed frame
    (`scopeL_typed_no_scopeLPD`). -/
theorem scopeL_typed_panic_giveCheck {P : Prog} {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var}
    {s : Stmt} {mo m m1 : Mem} (ht : StmtT P ξ Γ F (.scopeL k t x s) Δ) (hi : Inv mo Γ F (.scopeL k t x s))
    (hst0 : mo.st = m.st) (hb0 : mo.blk = m.blk) (hs : Step P m s (.panic m1)) (hk1 : CheckedOut m1 k t)
    (hd : t.dtorFree = false) {sl : Slot} (hsl : m1.st x = some sl) : GiveCheck m1 x sl := by
  have hB1 : BlocksIn m1 := MInv.blocks_back hi.toMInv (by rw [hb0]; exact Step.panic_blkBack hs)
  have hnc := (checkedOut_free hB1 hk1).2.2 hd
  have hxsp : x ∉ s.spine := by
    have := hi.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.1
  have hst := Step.panic_st hs x hxsp
  obtain ⟨E, hx, hrb, hmo, hty⟩ := scopeL_entry ht
  rcases frame_slot hi.toMInv hx hrb hmo hty with ⟨w, hsl0, hw, _⟩ | ⟨hti, _, _, _⟩
  · rw [hst, ← hst0, hsl0] at hsl; cases hsl
    cases w with
    | none => exact fun v hv => by cases hv
    | some v =>
      exact (scopeL_typed_panic_give ht hi hst0 hb0 hs hnc true v (by rw [hst, ← hst0]; exact hsl0)
        (hw v rfl) (.inl rfl) hk1).2
  · subst hti; cases hd

/-- **Agora #837: `Step.scopeLPD` never fires from a typed check-out**: no
    step of a typed frame `scopeL k t x s` hands `x` to a destructor frame
    after a failing give-back (`.seq (.scopeD x f .skip) .panic`): the step
    that would, `Step.scopeLPD`, asks `¬ GiveCheck` of a destructor payload,
    which the typing refutes (`scopeL_typed_panic_giveCheck`), and no other
    rule's result is of that form.  The rule stays as a total, defensive
    case of the semantics (the model's runs of an untyped program). -/
theorem scopeL_typed_no_scopeLPD {P : Prog} {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var}
    {s : Stmt} {mo m : Mem} (ht : StmtT P ξ Γ F (.scopeL k t x s) Δ) (hi : Inv mo Γ F (.scopeL k t x s))
    (hst0 : mo.st = m.st) (hb0 : mo.blk = m.blk) {r : Res} (h : Step P m (.scopeL k t x s) r)
    (m1 : Mem) (f : Nat) : r ≠ .ok m1 (.seq (.scopeD x f .skip) .panic) := by
  intro hr
  cases h with
  | scopeLPD hs hk1 ht' hsl hng =>
    exact hng (scopeL_typed_panic_giveCheck ht hi hst0 hb0 hs hk1 (by rw [ht']; simp) hsl)
  | scopeLIn _ => cases hr
  | scopeLSkip _ _ => cases hr
  | scopeLFail _ _ => cases hr
  | scopeLP _ _ => cases hr
  | waitPanic _ => cases hr
  | reap hrs _ _ => cases hrs

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

end A3.LockDtorWitness
