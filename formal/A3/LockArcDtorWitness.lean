import A3.LockDtorWitness

/-! A3 — Agora #803, `Locked D` where `D` holds a share: the give-back of a
destructor payload that fails its crossing check, and a witness.

Before Agora #803 a lock's (or a cell's) destructor payload held no share at
all (`Ty.lkPay` asked `!t.hasArc`): so the give-back's crossing check
(`GiveCheck`) could not fail on it (`A3.LockDtorWitness.sendCheck_noArc`),
and no unwinding dropped one with no code (`Release.drop`, `DropSlot`).  nurlc
accepts `Locked Conn` where `% Drop Conn` holds an `Arc Pool`.  Now the
payload may hold `arc` and lock shares (`Ty.lkPay` asks only that it holds no
cell share, which the reap's no-cell premise needs).

**When the check can fail.**  Holding no cell share, such a value meets the
cell half of `SendCheck` (`WFv.noCell_hasCell`), so `GiveCheck` fails only
through `NoGuard`: the value reaches a read guard.  nurlc refuses that
statically (`% NotSend RGuard`, `stdlib/std/rwlock.nu`), and its
`mem_send_check` counts only handle blocks, so nurlc's `locked_with` /
`locked_update` / `locked_apply` / `locked_await` never panic there on such
a payload.  Since Agora #837 the model refuses it statically too: a read
guard is of a type of its own (`Ty.rguard`), which no lock's payload type
holds (`Ty.hasGuard`), so a typed check-out's give-back passes the check
(`A3.LockDtorWitness.giveCheck_typed`) and `Step.scopeLPD` never fires from
a typed reachable configuration (`A3.reach_no_scopeLPD`).  The rule stays,
a total, defensive case of the semantics of an untyped store.

**The lemmas are conditional.**  `release_none`, `scopeL_fail_end`,
`scopeL_fail_frame` and `fail_end_runs_dtor` take `¬ GiveCheck` as a
hypothesis, which no typed reachable configuration meets (Agora #837,
above): they describe the defensive rule.  Under it:

* at the check-out's normal end, the end panics with the lock held
  (`Step.scopeLFail`), and the panic's one step turns the frame into `x`'s
  destructor frame, at its end, followed by the panic (`Step.scopeLPD`;
  `scopeL_fail_end`, `scopeL_fail_frame`);
* on a panic in the body, the same (`Step.scopeLPD`): the failing value is
  never released by `Release` (`release_none`), so never dropped with no
  code;
* the frame's end then calls the destructor on `x`
  (`fail_frame_runs_dtor`), on the panicking thread (`fail_end_runs_dtor`:
  the three steps from the end, each the only one).

That the block then stays checked out is not these lemmas' (the last
conjunct of `fail_end_runs_dtor` restates its hypothesis): it is
`A3/LockExcl.lean`'s.  After `scopeLPD` no `scopeL k` frame remains, a step
leaves a block whose payload is out as it was unless it is that block's
frame's (`A3.Step.stay`, `A3.LockInv`), and `withLock`, `lockTake` and
`rwRead` all need the payload in (`locked_restore` fills only a taken block).
Leaving it checked out mirrors the runtime's held lock word, should the case
arise.  No headline theorem says the destructor runs: `NoLeak` would hold of
a code-less drop too.  That a failing give-back runs it rests on
`release_none` and `fail_end_runs_dtor`.

The witness: `main` makes an `Arc` share, puts it in a destructor value (`DA`,
the struct `TA = prod (arc int) int` whose destructor `dfnA` takes it lent),
moves that into a `Locked` (`locked_new`), updates it through the lock
(`locked_apply`, A3.2's `withLock` with the update closure `ufnA` run on the
payload `inout`), and drops the lock's only share:

```
: a 1  : s ( arc_new a )  : b 2  :drop d ( pair s b )
: l ( locked_new d )  : z 0  = z ( locked_apply l ufnA )      -- l's scope ends
```

It is typed (`main_typed`, which `Ty.ok` refused before), every run of it is
safe (`main_safe`) and leaks nothing (`main_no_leak`, `main_no_leak_panic`);
the lock's last drop hands the payload, the `Arc` share in it, to a
destructor frame (`last_drop_reaps`); A3's claim covers it
(`A3.lockArcDtor_claim`).  Its give-back's check cannot fail (it holds no read
guard), so it does not reach the lemmas above; its give-back is not
traced, but since Agora #837 the give-back lemmas of `A3.LockDtorWitness`
(`giveable_of`, `scopeL_typed_end_gives_back`, `release_cases`,
`scopeL_typed_panic`; over a reached configuration
`A3.reach_scopeL_end_gives_back`, `A3.reach_scopeL_panic`) cover its payload
type, which holds an `arc` share and no cell share: a typed check-out of it
ends in `Release.put`, at its end and on a panic. -/

namespace A3.LockArcDtorWitness
open A2
open A2.DynCell (NoRootb noRootb_empty)
open A2.DtorWitness (NoDeps R0)

/-! ### A failing give-back of a destructor payload -/

/-- **A destructor payload that fails the give-back's check is never
    released** (`Release`): not given back (`Release.put` asks the check),
    and (Agora #803) not dropped with no code (`Release.drop` refuses it
    while the block is checked out). -/
theorem release_none {m m2 : Mem} {k : Nat} {t : Ty} {x : Var} {sl : Slot} {n f : Nat} {u : Ty}
    (hck : CheckedOut m k t) (ht : t = Ty.nest n (.dtor f u)) (hsl : m.st x = some sl)
    (hng : ¬ GiveCheck m x sl) : ¬ Release m k t x m2 := by
  intro h
  cases h with
  | put hx _ _ hgc => rw [hsl] at hx; cases hx; exact hng hgc
  | drop _ hgc hx _ => rw [hsl] at hx; cases hx; exact hng (hgc hck n f u ht)

/-- **At the check-out's end, a failing check panics**, with the lock held
    (`Step.scopeLFail`), the store as it was: the end's one step (with no
    orphan to reap first, as on every reached configuration). -/
theorem scopeL_fail_end {P : Prog} {m : Mem} {k : Nat} {t : Ty} {x : Var} {sl : Slot}
    (hsl : m.st x = some sl) (hng : ¬ GiveCheck m x sl) (hno : ¬ Orphan m) (r : Res) :
    Step P m (.scopeL k t x .skip) r ↔ r = .ok m (.scopeL k t x .panic) := by
  refine ⟨fun h => ?_, fun h => h ▸ Step.scopeLFail hsl hng⟩
  cases h with
  | reap hrs _ _ => cases hrs
  | scopeLSkip _ hck => exact absurd (hck sl hsl) hng
  | scopeLFail _ _ => rfl
  | scopeLIn hs => exact (A2.Dtor.skip_no_step hno hs).elim
  | scopeLP hs _ => exact (A2.ArcPanicWitness.skip_no_panic hs).elim
  | scopeLPD hs _ _ _ _ => exact (A2.ArcPanicWitness.skip_no_panic hs).elim
  | waitPanic hw => exact hw.elim

/-- **... and that panic turns the check-out's frame into `x`'s destructor
    frame** (Agora #803, `Step.scopeLPD`): with the block checked out and its
    payload a destructor value (`Ty.nest n (.dtor f u)`), the panic's one step
    leaves the store as it was, `x` in a frame `scopeD x f` at its end,
    followed by the panic raised again; never the code-less drop. -/
theorem scopeL_fail_frame {P : Prog} {m : Mem} {k : Nat} {t : Ty} {x : Var} {sl : Slot} {n f : Nat}
    {u : Ty} (hck : CheckedOut m k t) (ht : t = Ty.nest n (.dtor f u)) (hsl : m.st x = some sl)
    (hng : ¬ GiveCheck m x sl) (hno : ¬ Orphan m) (r : Res) :
    Step P m (.scopeL k t x .panic) r ↔ r = .ok m (.seq (.scopeD x f .skip) .panic) := by
  refine ⟨fun h => ?_, fun h => h ▸ Step.scopeLPD Step.panic hck ht hsl hng⟩
  cases h with
  | reap hrs _ _ => cases hrs
  | scopeLIn hs =>
    cases hs with
    | reap _ hk _ => exact absurd ⟨_, _, _, _, _, hk⟩ hno
  | scopeLP hs hrl =>
    have hm : ∀ m1, Step P m .panic (.panic m1) → m1 = m := fun m1 h => by
      cases h with
      | panic => rfl
      | waitPanic hw => exact hw.elim
    obtain rfl := hm _ hs
    exact (release_none hck ht hsl hng hrl).elim
  | scopeLPD hs _ ht' _ _ =>
    cases hs with
    | panic =>
      rw [ht] at ht'
      obtain ⟨-, rfl, -⟩ := Ty.nest_dtor_inj ht'
      rfl
    | waitPanic hw => exact hw.elim
  | waitPanic hw => exact hw.elim

/-- **The destructor frame's end calls the destructor**: with `x` owning a
    value that is no `Vec`'s node (a destructor payload at its top,
    `Ty.dtor f u`), the one step of `scopeD x f skip; panic` calls `f` on `x`
    (`Step.scopeDEnd`, its result in a fresh variable), the panic after it. -/
theorem fail_frame_runs_dtor {P : Prog} {m : Mem} {x : Var} {f : Nat} {v : Val}
    (hx : m.st x = some ⟨true, some v⟩) (hv : v.isNode = false) (hno : ¬ Orphan m) (r : Res) :
    Step P m (.seq (.scopeD x f .skip) .panic) r ↔
      r = .ok { m with nv := m.nv + 1 } (.seq (.scope x (.letcall m.nv f [x] .skip)) .panic) := by
  refine ⟨fun h => ?_, fun h => h ▸ Step.seqL (Step.scopeDEnd hx hv)⟩
  cases h with
  | reap hrs _ _ => cases hrs
  | waitPanic hw => exact hw.elim
  | seqL hs =>
    cases hs with
    | reap hrs _ _ => cases hrs
    | scopeDIn hs => exact (A2.Dtor.skip_no_step hno hs).elim
    | scopeDEnd _ _ => rfl
    | scopeDMoved hm => rw [hx] at hm; cases hm
    | scopeDDrain hm => rw [hx] at hm; cases hm; cases hv
    | scopeDEmpty hm => rw [hx] at hm; cases hm; cases hv
    | scopeDP hs _ _ | scopeDPDrain hs _ => exact (A2.ArcPanicWitness.skip_no_panic hs).elim
  | seqP hs =>
    cases hs with
    | scopeDPMoved hs _ => exact (A2.ArcPanicWitness.skip_no_panic hs).elim
    | waitPanic hw => exact hw.elim

/-- **Agora #803: a failing give-back runs the destructor.**  At the end of
    the check-out of a block of a destructor payload `Ty.dtor f u` (checked
    out), with `x` owning a value (no `Vec`'s node) that fails the crossing
    check and no orphan to reap, the next three steps are each the only one:
    the end panics with the lock held (`scopeL_fail_end`), the panic turns the
    frame into `x`'s destructor frame (`scopeL_fail_frame`), and its end calls
    `f` on `x` (`fail_frame_runs_dtor`).  Conditional: `¬ GiveCheck` is a
    hypothesis, which needs a read guard in the payload, and no typed
    reachable configuration is shown to meet it (Agora #837).  The last
    conjunct restates `hck`; that the block stays checked out afterwards is
    `A3/LockExcl.lean`'s (`A3.Step.stay`: no `scopeL k` frame remains, and
    `withLock`, `lockTake` and `rwRead` need the payload in). -/
theorem fail_end_runs_dtor {P : Prog} {m : Mem} {k : Nat} {f : Nat} {u : Ty} {x : Var} {v : Val}
    (hck : CheckedOut m k (.dtor f u)) (hx : m.st x = some ⟨true, some v⟩) (hv : v.isNode = false)
    (hng : ¬ GiveCheck m x ⟨true, some v⟩) (hno : ¬ Orphan m) :
    (∀ r, Step P m (.scopeL k (.dtor f u) x .skip) r ↔ r = .ok m (.scopeL k (.dtor f u) x .panic)) ∧
      (∀ r, Step P m (.scopeL k (.dtor f u) x .panic) r ↔ r = .ok m (.seq (.scopeD x f .skip) .panic)) ∧
      (∀ r, Step P m (.seq (.scopeD x f .skip) .panic) r ↔
        r = .ok { m with nv := m.nv + 1 } (.seq (.scope x (.letcall m.nv f [x] .skip)) .panic)) ∧
      m.blk k = some ⟨.dtor f u, .lock, none⟩ :=
  ⟨scopeL_fail_end hx hng hno, scopeL_fail_frame (n := 0) hck rfl hx hng hno,
    fail_frame_runs_dtor hx hv hno, hck.1⟩

/-! ### The program -/

/-- The struct: an `Arc` share of an integer and an integer. -/
def TA : Ty := .prod (.arc .int) .int
/-- Its destructor type (`% Drop`, destructor `0`). -/
def DA : Ty := .dtor 0 TA

/-- destructor: `@ drop in self → i { = r 0 }` -/
def dfnA : Fn where
  params := [(.inp, DA)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .assign 1 (.expr (.lit 0))
  nvars := 2

/-- The update closure: `@ upd inout self → i { = r 0 }`, the payload taken
    `inout`. -/
def ufnA : Fn where
  params := [(.inout .replace, DA)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .assign 1 (.expr (.lit 0))
  nvars := 2

def P : Prog := [dfnA, ufnA]

/-- Agora #803: the payload type holds a share and no cell share, so a lock
    of it is well formed (`Ty.lkPay`), as it was not before. -/
theorem lk_ok : (Ty.lk DA).ok = true := by decide
theorem DA_hasArc : DA.hasArc = true := rfl

theorem dfnA_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [dfnA, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [dfnA, Stmt.calls] at hg

theorem drop0_ok : DropFnOK P 0 TA :=
  Or.inl ⟨⟨dfnA, rfl, rfl, rfl, rfl, rfl, rfl, rfl, dfnA_not_thru⟩, by decide⟩

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

theorem sig_dfnA_flags : ∀ v E, sigCtx dfnA v = some E → E.dtor = false ∧ E.dbind = false := by
  intro v E h
  rcases v with _ | _ | v <;> simp [sigCtx, dfnA, paramE, resMode] at h <;> subst h <;> exact ⟨rfl, rfl⟩

theorem dfnA_ok : FnOK P dfnA := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [dfnA], ?_, by simp [dfnA], by simp [dfnA], by simp [dfnA],
    by simp [dfnA], by simp [dfnA], ?_, _,
    assign_res (by simp [sigCtx, dfnA, R0, resMode]) ?_ sig_dfnA_flags, ?_, ?_, ?_⟩
  · intro pt hpt; simp [dfnA] at hpt; subst hpt
    simp [DA, TA, Ty.ok, Ty.isStruct, Ty.holdsView, Ty.dtorFree, Ty.hasGuard]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [dfnA] at h⟩
    · simp [dfnA] at hi; subst hi; simp [dfnA] at hs
    · simp [dfnA] at hi; subst hi; simp [dfnA] at hb
  · intro p E hp _
    rcases p with _ | _ | p <;> simp [sigCtx, dfnA, paramE, resMode, DA, TA, Ty.hasFn] at hp <;> subst hp <;>
      simp [Entry.vdeps]
  · intro v E h
    rcases v with _ | _ | v <;> simp [setE, upd, kill, killE, sigCtx, dfnA, paramE, intE] at h <;>
      subst h <;> exact ⟨rfl, rfl⟩
  · exact ⟨{ intE with mode := R0.mode }, by simp [setE, upd, dfnA], rfl, rfl, by simp [R0, resMode, dfnA],
      by simp [intE], by simp [intE], by simp [dfnA]⟩
  · intro i hi b hb; simp [dfnA] at hi; subst hi; simp [dfnA] at hb

theorem sig_ufnA_flags : ∀ v E, sigCtx ufnA v = some E → E.dtor = false ∧ E.dbind = false := by
  intro v E h
  rcases v with _ | _ | v <;> simp [sigCtx, ufnA, paramE, resMode] at h <;> subst h <;> exact ⟨rfl, rfl⟩

theorem ufnA_ok : FnOK P ufnA := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [ufnA], ?_, by simp [ufnA], by simp [ufnA], by simp [ufnA],
    by simp [ufnA], by simp [ufnA], ?_, _,
    assign_res (by simp [sigCtx, ufnA, R0, resMode]) ?_ sig_ufnA_flags, ?_, ?_, ?_⟩
  · intro pt hpt; simp [ufnA] at hpt; subst hpt
    simp [DA, TA, Ty.ok, Ty.isStruct, Ty.owning, Ty.holdsView, Ty.dtorFree, Ty.hasGuard]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [ufnA] at h⟩
    · simp [ufnA] at hi; subst hi; simp [ufnA] at hs
    · simp [ufnA] at hi; subst hi; simp [ufnA, Stmt.assigns]
  · intro p E hp hm
    rcases p with _ | _ | p <;> simp [sigCtx, ufnA, paramE, resMode] at hp <;> subst hp <;> simp at hm
  · intro v E h
    rcases v with _ | _ | v <;> simp [setE, upd, kill, killE, sigCtx, ufnA, paramE, intE] at h <;>
      subst h <;> exact ⟨rfl, rfl⟩
  · exact ⟨{ intE with mode := R0.mode }, by simp [setE, upd, ufnA], rfl, rfl, by simp [R0, resMode, ufnA],
      by simp [intE], by simp [intE], by simp [ufnA]⟩
  · intro i hi b hb
    simp [ufnA] at hi; subst hi
    refine ⟨paramE ufnA.params (.inout .replace, DA), ?_, rfl, ?_, ?_⟩
    · simp [setE, upd, kill, killE, sigCtx, ufnA, paramE, Entry.vdeps, hits, Mode.ownSlot, DA, TA, Ty.hasFn]
    · simp [paramE, DA, TA, Ty.hasFn]
    · intro _; simp [paramE, DA, TA, Ty.hasFn]

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl
  · exact dfnA_ok
  · exact ufnA_ok

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl
  · simp [dfnA, Stmt.codesOK, Rhs.codeOK]
  · simp [ufnA, Stmt.codesOK, Rhs.codeOK]

/-- `: a 1  : s ( arc_new a )  : b 2  :drop d ( pair s b )
     : l ( locked_new d )  : z 0  = z ( locked_apply l ufnA )` (the payload
    checked out to `x = 6`, the closure's result `c = 7` moved out to `z`). -/
def main : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.arcNew .int 0) (.letv 2 (.expr (.lit 2)) (.letd 3 0 (.pair 1 2)
    (.letv 4 (.lockNew DA 3) (.letv 5 (.expr (.lit 0)) (Stmt.lockedApply 4 6 7 5 1))))))

/-- The `Arc` share's entry: owned, holding nothing. -/
def EA : Entry := ⟨.arc .int, .own, true, [], [], false, false⟩
/-- The struct's entry, as `pair` makes it. -/
def EP : Entry := ⟨TA, .own, true, [], [] ++ [], false, false⟩
/-- The lock share's entry: owned, holding nothing. -/
def EL : Entry := ⟨.lk DA, .own, true, [], [], false, false⟩

/-- **A `Locked` of a destructor value that holds an `Arc` share is typed**
    (Agora #803: `Ty.ok` admits `lk (dtor f u)` when `u` holds no cell share,
    `RhsT.lockNew` takes the value), and so is its update through
    `locked_apply` (`StmtT.lockedApply`). -/
theorem main_typed : ∃ Δ, StmtT P (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hD0 : NoDeps (fun _ => none) := fun _ _ h => by cases h
  have hD1 : NoDeps K1 := hD0.setE rfl
  -- `arc_new a`: the integer is copied into the block
  have harc : RhsT K1 [] (.arcNew .int 0) EA K1 :=
    RhsT.arcNew (Ey := intE) (by simp [K1, A2.setE]) rfl rfl (Or.inl rfl) ⟨rfl, rfl⟩ rfl rfl PushArg.int
  let K2 : Ctx := A2.setE K1 1 EA
  have hK2 : NoRootb K2 := hK1.setE (by simp [EA])
  have hD2 : NoDeps K2 := hD1.setE rfl
  let K3 : Ctx := A2.setE K2 2 intE
  have hK3 : NoRootb K3 := hK2.setE (by simp [intE])
  have hD3 : NoDeps K3 := hD2.setE rfl
  -- `pair s b`: the share moves into the struct
  let EA' : Entry := { EA with live := false, dtor := false }
  let K3' : Ctx := A2.setE K3 1 EA'
  have hkill1 : A2.kill .replace false 1 K3 = K3 := hD3.kill_eq _ _ _
  have hpair : RhsT K3 [] (.pair 1 2) EP K3' := by
    have h := RhsT.pair (Γ := K3) (F := []) (y := 1) (z := 2) (Ey := EA) (Ez := intE)
      (by simp [K3, K2, A2.setE, upd]) rfl
      (PushArg.move (by simp [EA, Ty.owning]) rfl (by simp) (hK3.noPin 1)
        (DtorSafe.of_none (fun v E h => (hK3 v E h).2.1) _ _ _))
      (by rw [hkill1]; simp [K3, K2, A2.setE, upd]) rfl PushArg.int (by simp [EA, roots])
    rw [hkill1] at h; exact h
  have hK3' : NoRootb K3' := hK3.setE (by simp [EA', EA])
  have hD3' : NoDeps K3' := hD3.setE rfl
  let ED : Entry := Entry.arm { EP with ty := DA, held := [] }
  have hED : ED.mode ≠ .rootb ∧ ED.dtor = false ∧ ED.dbind = false := by
    simp [ED, EP, Entry.arm, DA, TA, Ty.dtorViews, Ty.holdsView]
  let K4 : Ctx := A2.setE K3' 3 ED
  have hK4 : NoRootb K4 := hK3'.setE hED
  have hD4 : NoDeps K4 := hD3'.setE (by simp [ED, EP, Entry.arm, Entry.vdeps])
  have hK4d : K4 3 = some ED := by simp [K4, A2.setE]
  -- `locked_new d`: `d` moves into the lock block
  let ED' : Entry := { ED with live := false, dtor := false }
  let K4' : Ctx := A2.setE K4 3 ED'
  have hkill : A2.kill .replace false 3 K4 = K4 := hD4.kill_eq _ _ _
  have hnew : RhsT K4 [] (.lockNew DA 3) EL K4' := by
    have h := RhsT.lockNew (Γ := K4) (F := []) (t := DA) (y := 3) (Ey := ED) hK4d
      (by simp [ED, Entry.arm, EP]) (by simp [ED, Entry.arm]) lk_ok
      ⟨by simp [DA, TA, Ty.holdsView], by simp [DA, TA, Ty.hasFn]⟩ (by simp [DA, TA, Ty.hasGuard])
      (PushArg.move (by simp [DA, Ty.owning]) (by simp [ED, Entry.arm, EP]) (by simp)
        (hK4.noPin 3) (DtorSafe.of_none (fun v E h => (hK4 v E h).2.1) _ _ _))
    rw [hkill] at h; exact h
  have hK4' : NoRootb K4' := hK4.setE (by simp [ED', ED, EP, Entry.arm, DA, TA, Ty.dtorViews, Ty.holdsView])
  have hD4' : NoDeps K4' := hD4.setE (by simp [ED', ED, EP, Entry.arm, Entry.vdeps])
  let K5 : Ctx := A2.setE K4' 4 EL
  have hK5 : NoRootb K5 := hK4'.setE (by simp [EL])
  have hD5 : NoDeps K5 := hD4'.setE rfl
  let K6 : Ctx := A2.setE K5 5 intE
  have hK6 : NoRootb K6 := hK5.setE (by simp [intE])
  have hD6 : NoDeps K6 := hD5.setE rfl
  have hun : ∀ v, Unnamed K6 v := fun v w E h d hd => by rw [hD6 w E h] at hd; cases hd
  -- the update, under the lock: `ufnA` on the payload `inout`, its result to `z`
  have hap : ApplyFn P 1 DA .int := ⟨ufnA, .replace, rfl, rfl, rfl, rfl, rfl⟩
  have hup := StmtT.lockedApply (P := P) (Γ := K6) (F := []) (a := 4) (x := 6) (c := 7) (z := 5) (f := 1)
    (fn := ufnA) (Ea := EL) (Ez := intE) (t := DA) (R := .int) hap rfl
    (by simp [K6, K5, A2.setE]) rfl (Or.inl rfl) rfl (by simp [DA, TA, Ty.holdsView]) (by simp [DA, Ty.owning])
    (by simp [K6, K5, K4', K4, K3', K3, K2, K1, A2.setE, upd])
    (by simp [K6, K5, K4', K4, K3', K3, K2, K1, A2.setE, upd])
    (by decide) (by simp) (by simp) (hun 6) (hun 7) (by decide) (by simp [K6, A2.setE]) (by simp) rfl
    (by simp [intE, resMode, ufnA]) rfl (hK6.noPin 5) (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _)
  have hKf : NoRootb (A2.setE (A2.kill .replace false 5 K6) 5 (outE .int intE.mode)) :=
    (hK6.kill _ _ _).setE (by simp [outE, intE])
  have hz := StmtT.letv (P := P) (x := 5) (r := .expr (.lit 0)) (E := intE) (F := []) (Γ := K5) (Γ1 := K5)
    rfl (by simp [K5, K4', K4, K3', K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hup
    (hKf.endOK _)
  have hl := StmtT.letv (P := P) (x := 4) (r := .lockNew DA 3) (E := EL) (F := []) (Γ := K4) (Γ1 := K4')
    rfl (by simp [K4, K3', K3, K2, K1, A2.setE, upd]) (by simp) hnew hz ((hKf.exitScope 5).endOK _)
    (fun _ => rfl)
  have hd := StmtT.letd (P := P) (Γ := K3) (Γ1 := K3') (F := []) (x := 3) (f := 0) (r := .pair 1 2)
    (E := EP) (t := TA) (H := []) rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) hpair rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop0_ok) (HeldUp.refl _ _) hl
    (((hKf.exitScope 5).exitScope 4).endOK _) (by simp [Stmt.lockedApply, Stmt.callOut, Stmt.assigns])
  have hb := StmtT.letv (P := P) (x := 2) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K2) (Γ1 := K2)
    rfl (by simp [K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd
    ((((hKf.exitScope 5).exitScope 4).exitScope 3).endOK _)
  have hs := StmtT.letv (P := P) (x := 1) (r := .arcNew .int 0) (E := EA) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) harc hb
    (((((hKf.exitScope 5).exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) hs
    ((((((hKf.exitScope 5).exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- `arc_new` of an integer names no destructor; `locked_new` of the
    destructor value names the one the program checked (`Rhs.codeOK`). -/
theorem main_codes : main.codesOK P := by
  simp only [main, Stmt.lockedApply, Stmt.callOut, Stmt.codesOK, Rhs.codeOK, DA]
  exact ⟨trivial, fun _ _ h => absurd h.dtorFree (by decide), trivial, trivial,
    arcNew_codeOK (n := 0) drop0_ok, trivial, trivial⟩

/-- **Every run of it is safe.** -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 8) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **... and leaks nothing**: when it finishes, every address is freed
    (`no_leak_end`). -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 8) main (.ok m' .skip)) : ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **... and leaks nothing on a panic either** (`no_leak_panic`). -/
theorem main_no_leak_panic {m' : Mem} (hr : Steps P (emptyMem 8) main (.panic m')) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_panic prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **The lock's last share's drop hands the payload, the `Arc` share in it,
    to a destructor frame of the same thread**: when no slot's value and no
    block's payload refers to the lock block, its payload in it, the marking
    sweep that ends the step marks it `dead` (`Mem.sweepD_marks`, at a lock
    block), so the thread's next step is a reap (`settle_reaps`), which moves
    the payload to a fresh binding in a frame `scopeD _ 0 skip` whose end
    calls `dfnA` on it; the `Arc` block, reached from that binding, stays
    until the frame frees it. -/
theorem last_drop_reaps {m : Mem} {k : Nat} {p : Val} (hk : m.blk k = some ⟨DA, .lock, some p⟩)
    (hv : ∀ x o v, m.st x = some ⟨o, some v⟩ → ¬ Refers m.blk v k)
    (hb : ∀ k' bl', m.blk k' = some bl' → ¬ Refers m.blk bl'.keeps k)
    {s s' : Stmt} {m' : Mem} (h : Settle P m.sweepD s m' s') :
    m.sweepD.blk k = some ⟨DA, .dead, some p⟩ ∧
      ∃ m1 s1, Step P m.sweepD s (.ok m1 s1) ∧ ReapMem m.sweepD m1 := by
  have hm := Mem.sweepD_marks (n := 0) (f := 0) (u := TA) (Or.inr rfl) hk hv hb
  exact ⟨hm, settle_reaps h ⟨k, 0, 0, TA, p, hm⟩⟩

end A3.LockArcDtorWitness

namespace A3

/-- Agora #803, the witness (`A3.LockArcDtorWitness.main`): a `Locked` of a
    destructor value that holds an `Arc` share, made, updated through
    `locked_apply`, its last share dropped, on one thread.  The claim covers
    it: safe, race-free and leak-free on every interleaving. -/
theorem lockArcDtor_claim :
    MemorySafe LockArcDtorWitness.P (fun _ => false) (Cfg.start Globs.empty LockArcDtorWitness.main 8) ∧
      RaceFree LockArcDtorWitness.P (fun _ => false) (Cfg.start Globs.empty LockArcDtorWitness.main 8) ∧
      NoLeak LockArcDtorWitness.P (fun _ => false) (Cfg.start Globs.empty LockArcDtorWitness.main 8) := by
  obtain ⟨Δ, ht⟩ := LockArcDtorWitness.main_typed
  exact claim _ _ Globs.empty _ Δ 8 LockArcDtorWitness.prog_ok LockArcDtorWitness.prog_codes
    (fun _ h => by cases h) GlobsOK.empty ht rfl LockArcDtorWitness.main_codes (by decide)

end A3
