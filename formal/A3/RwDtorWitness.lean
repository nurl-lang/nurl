import A3.LockDtorWitness

/-! A3 — Agora #804, `RwLocked D`: a reader-writer lock whose payload is a
destructor value, read through a guard that lends its payload, and a
witness.

A read guard (`rw_read a`, `RhsT.rwRead`) is an owned share (`Val.arc`) of a new
*view* of the lock block (`EvalR.rwRead`), of type `Ty.rguard u` (Agora #837): a block of kind `.view` whose
payload is a share of the lock block and the lock block's payload, as the
lock block holds it (`ViewsAt`).  The view owns nothing: its tree is empty
(`Blk.tree_view`), so no sweep frees anything of it, and it is never an
orphan to be (`Cand` asks an `arc` or a lock block) nor marked `dead`
(`A2.Dtor.blocks_dtor_free`), so no reap ever hands a destructor frame
anything from it.  Its payload is read in place: what `rguard_get g`
(`arcGet g`, then `snd`) lends is the lock block's payload, frozen (`getE`'s
`share` dependency) while the guard lives, and the guard, through the
view's share of the lock block, keeps the lock block reached
(`view_keeps_lock`), so the payload is never an orphan while a reader lives.
The lock block alone owns the payload.  When the lock's last share goes
after every guard, its views swept, so that no slot's value and no block's
payload refers to the lock block, the marking sweep marks it `dead` and
the same thread reaps it, the reap's frame running the payload's
destructor (`A3.LockDtorWitness.last_drop_reaps`).  Agora #831: in the
other order, a guard dropped after the lock's last share, the sweep that
ends the guard's drop finds the guard's view unreached (it removes it: a
view is never pinned) and the lock block referred to by that view alone:
the two are cut off from the roots together (`A2.CutOff`, `view_cutOff`),
so the sweep marks the lock block `dead` all the same and the thread that
dropped the guard reaps it (`guard_drop_reaps`, over the generalised
`A3.TStep.last_drop_reaps`; on A2's `Steps`, `guard_drop_reaps_settle`).

Before Agora #804 the read guard asked a payload that owns no destructor
value (the type-level reading of the view as a copy of the payload;
`RwLocked D` was refused).  It is typed now (`rwRead_dtor_typed`,
`rwTryRead_dtor_typed`): `Ty.ok` admits the guard's type `rguard u` (its
payload a lock's, holding no cell share), and the invariant admits a view of
type `prod (lk u) u` (`Ty.rview`, `Blk.DtorOK`); an `arc` block is never of a
destructor type of that shape (`A2.Dtor.arc_blocks_dtor`).

Agora #837: until then the guard's type was `arc (prod (lk u) u)`, which a
genuine `Arc` of a pair of a lock and a value of its payload's type shares
(`arc_new (pair l v)`, nurlc's `Arc<(Locked U, U)>`), so the types could not
refuse the guard without refusing that `Arc` too.  A read guard is now a type
of its own, `Ty.rguard u`; its value is still a share of a view
(`WFv.rguard`), and only a guard's share names a view (`ArcBlk`).
`Ty.hasGuard` is true exactly where an `rguard` occurs (a closure's type
answers its class's `views`: only `any` may hold one), and `Ty.ok` refuses it
in a lock's, a cell's (so a channel's) and an `Arc`'s payload, so in a
global's type (`GlobsOK`), and `Cross.Fits` in a closure of every class but
`any` (`guard_refused`); a local binding, a struct or a `Vec` may hold one,
and the genuine `Arc` of a pair is admitted as before (`arc_pair_ok`), and so
is a lock, an `Arc` or a cell of a closure of the dropping class
(`dropd_closure_ok`).  nurlc refuses a guard only where it crosses (a spawn,
a channel's send), so the model is stricter for a guard kept on its thread
in a lock, an `Arc` or a cell, and for a closure holding both a guard and a
destructor value (`CLAIM.md`); a spawn's parameter of a guard's type is
refused at run time only (`SpawnOK` admits it, `spawn_guard`).  So a lock's
payload reaches no view, and its give-back's crossing check passes
(`A3.LockDtorWitness.giveCheck_typed`).

`main` (Agora #831) makes a `Vec` of destructor values (`vec DT`,
`A2/DtorWitness.lean`; the `Vec` owns heap, its buffer, and one element is
pushed), moves it into an `RwLocked` (`rw_new` is `locked_new`), reads it
through a guard (`Stmt.withRead`: the guard `g`, the lend `y` of the lock's
share and the payload, the payload `z` lent), and, the guard still bound,
moves the lock's only share out of `l` into `l2`, whose scope ends first:
the lock's last share is dropped before the guard.

```
: a 1  : b 2  :drop x ( pair a b )  :drop v ( vec_new DT )  ( vec_push v x )
: l ( rw_new v )  : g ( rw_read l )  : y ( rguard_get g )  : z ( snd y )
: l2 l                                  -- l2's scope ends, then z's, y's and g's
```

It is typed (`main_typed`), every run of it is safe (`main_safe`) and,
finished or panicked, leaks nothing (`main_no_leak`, `main_no_leak_panic`);
A3's claim covers it, race freedom included (`A3.rwDtor_claim`); and the
guard's drop, the last reference, reaps the `Vec` on the dropping thread,
whose frame drains it (`guard_drop_reaps`, `A3.LockDtorWitness.reapV_drains`).
(Until Agora #831 the witness held a `DT`, a pair of integers that owns no
heap, and dropped the guard first.) -/

namespace A3.RwDtorWitness
open A2
open A2.DynCell (NoRootb noRootb_empty)
open A2.DtorWitness (NoDeps T DT dfn EP R0)
open A3.LockDtorWitness (P prog_ok prog_codes drop0_ok EL ELV)

/-! ### Agora #837: the guard's own type, refused where it would cross -/

/-- **A read guard is `% NotSend` in the types** (Agora #837): no lock's or
    cell's payload holds one, at any depth (here a `Locked` of a destructor
    value holding a guard in a field, the case `Step.scopeLPD` was made
    total for), nor a channel's queue, nor an `Arc`'s payload (so no
    global's type, which `GlobsOK` asks `Ty.ok` of; a guard's own type is
    no `Ty.sync` one), nor the environment of a closure of any class but
    `any` (`Cross.Fits`); a local binding may hold one, and so may a struct
    or a `Vec` that stays on its thread.  (Stricter than nurlc, which
    refuses a guard only where it crosses; a spawn's parameter is refused
    at run time only.) -/
theorem guard_refused :
    (Ty.lk (.dtor 0 (.prod (.rguard .int) .int))).ok = false ∧
    (Ty.cell (.prod (.rguard .int) .int)).ok = false ∧
    (Ty.lk (.prod (.vec (.rguard .int)) .int)).ok = false ∧
    (Ty.arc (.rguard .int)).ok = false ∧
    (Ty.arc (.prod (.rguard .int) .int)).ok = false ∧
    (Ty.rguard .int).sync = false ∧
    (∀ cs, ¬ Cross.send.Fits (.prod (.rguard .int) .int) cs) ∧
    (Ty.rguard (.dtor 0 (.prod .int .int))).ok = true ∧
    (Ty.vec (.prod (.rguard .int) .int)).ok = true := by
  refine ⟨by decide, by decide, by decide, by decide, by decide, rfl, fun cs h => ?_, by decide, by decide⟩
  have := h.guard rfl
  simp [Ty.hasGuard] at this

/-- ... and only it: a genuine `Arc` of a pair of a lock and a value of its
    payload's type (nurlc's `Arc<(Locked U, U)>`), which until Agora #837 had
    the guard's type, is admitted in a lock's payload, an `Arc`'s and a
    global, as nurlc admits it. -/
theorem arc_pair_ok :
    (Ty.lk (.arc (.prod (.lk .int) .int))).ok = true ∧
    (Ty.arc (.arc (.prod (.lk .int) .int))).ok = true ∧
    (Ty.arc (.prod (.lk .int) .int)).sync = true ∧ (Ty.arc (.prod (.lk .int) .int)).ok = true := by
  decide

/-- ... nor a closure of the dropping class (`A2.ClosureDropWitness.CDT`,
    `dtor 2 (fn [2] dropd)`, a closure whose environment holds a `% Drop` value): a lock, an
    `Arc` and a cell of one are admitted, as nurlc admits `locked_new` and
    `arc_new` of such a closure (the #837 review: `Ty.hasGuard` of a closure
    is its class's `views`, and a `dropd` environment holds no guard,
    `Cross.Fits`). -/
theorem dropd_closure_ok :
    (Ty.lk (.dtor 2 (.fn [2] .dropd))).ok = true ∧ (Ty.arc (.dtor 2 (.fn [2] .dropd))).ok = true ∧
    (Ty.cell (.dtor 2 (.fn [2] .dropd))).ok = true := by
  decide

/-! ### The read guard of a destructor payload is typed -/

/-- **`RwLocked D`'s read guard is typed** (Agora #804, as nurlc's): `rw_read`
    of a lock share whose payload is a destructor value holding no cell
    share is the guard, an owned share of a view that lends the payload in
    place. -/
theorem rwRead_dtor_typed {Γ : Ctx} {F : List Var} {a : Var} {Ea : Entry} {f : Nat} {u : Ty}
    (ha : Γ a = some Ea) (hla : Ea.live = true) (hty : Ea.ty = .lk (.dtor f u)) (hnc : u.hasCell = false) :
    RhsT Γ F (.rwRead a) (guardE (.dtor f u)) Γ :=
  RhsT.rwRead ha hla hty (by simpa [Ty.hasCell] using hnc)

/-- ... and so is `rw_try_read`'s. -/
theorem rwTryRead_dtor_typed {Γ : Ctx} {F : List Var} {a : Var} {Ea : Entry} {f : Nat} {u : Ty}
    (ha : Γ a = some Ea) (hla : Ea.live = true) (hty : Ea.ty = .lk (.dtor f u)) (hnc : u.hasCell = false) :
    RhsT Γ F (.rwTryRead a) (tryReadE (.dtor f u)) Γ :=
  RhsT.rwTryRead ha hla hty (by simpa [Ty.hasCell] using hnc)

/-! ### The view lends: it owns nothing, and keeps its lock block -/

/-- **`rw_read`'s view lends the payload**: the step makes a view of the lock
    block `k`, at the fresh key `nid`, that owns nothing (its tree is empty),
    whose payload's second field is the lock block's payload, which stays in
    the lock block; the view is no orphan to be under any roots (`Cand`), and
    the lock now has a view (a writer waits, `HasView`). -/
theorem rwRead_view_lends {m : Mem} {a : Var} {o : Bool} {k : Nat} {t : Ty} {p : Val}
    (ha : m.st a = some ⟨o, some (.lk k)⟩) (hk : m.blk k = some ⟨t, .lock, some p⟩)
    (hfr : m.blk m.nid = none) :
    let B := upd m.blk m.nid (some ⟨.prod (.lk t) t, .view, some (.pair (.lk k) p)⟩)
    EvalR m (.rwRead a) (.ok (.arc m.nid (.pair (.lk k) p)) true { m with nid := m.nid + 1, blk := B }) ∧
      (B m.nid).map Blk.tree = some (.int 0) ∧ B k = some ⟨t, .lock, some p⟩ ∧
      (∀ R, ¬ Cand R B m.nid) ∧ HasView B k := by
  intro B
  have hkn : k ≠ m.nid := fun e => by rw [e, hfr] at hk; cases hk
  have hB : B m.nid = some ⟨.prod (.lk t) t, .view, some (.pair (.lk k) p)⟩ := by simp [B]
  refine ⟨EvalR.rwRead ha hk hfr, by rw [hB]; rfl, by simp [B, upd_ne _ _ hkn, hk], ?_, ⟨m.nid, _, p, hB⟩⟩
  rintro R ⟨⟨n, f, u, q, kd, hkd, hk'⟩, _⟩
  rw [hB] at hk'
  simp only [Option.some.injEq, Blk.mk.injEq] at hk'
  obtain ⟨_, rfl, _⟩ := hk'
  rcases hkd with h | h <;> cases h

/-- **A reached view keeps its lock block reached**: the view's payload holds
    a share of it.  So while a read guard lives (its share reaches the
    view), the lock block is no orphan to be (`Cand` asks it unreached), and
    its payload's destructor does not run. -/
theorem view_keeps_lock {R : Val → Prop} {B : Nat → Option Blk} {k' k : Nat} {t : Ty} {p : Val}
    (hk' : B k' = some ⟨.prod (.lk t) t, .view, some (.pair (.lk k) p)⟩) (hr : Reached R B k') :
    Reached R B k :=
  .pay hr hk' (Or.inl (Or.inl ⟨none, Sub.fst (Sub.refl _)⟩))

/-- ... so the lock block of a reached view is not an orphan to be. -/
theorem view_lock_not_cand {R : Val → Prop} {B : Nat → Option Blk} {k' k : Nat} {t : Ty} {p : Val}
    (hk' : B k' = some ⟨.prod (.lk t) t, .view, some (.pair (.lk k) p)⟩)
    (hr : Reached (Roots0 R B) B k') : ¬ Cand R B k :=
  fun h => h.2 (view_keeps_lock hk' hr)

/-- **In a running configuration no view runs a destructor**: a view block
    owns nothing, and the marking sweep keeps it as it is or removes it,
    never marking it `dead` (`A2.Dtor.blocks_dtor_free`). -/
theorem view_no_dtor {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {k : Nat} {bl : Blk}
    (hk : m.blk k = some bl) (hv : bl.kind = .view) :
    bl.tree = .int 0 ∧ ∀ R, ¬ Cand R m.blk k ∧ (sweepBlkD R m.blk k = some bl ∨ sweepBlkD R m.blk k = none) := by
  obtain ⟨h1, _, h2⟩ := (A2.Dtor.blocks_dtor_free hi hk).2.2.2 hv
  exact ⟨h1, h2⟩

/-! ### The witness: the lock's last share dropped while the guard lives -/

/-- `: a 1  : b 2  :drop x ( pair a b )  :drop v ( vec_new DT )  ( vec_push v x )
     : l ( rw_new v )  : g ( rw_read l )  : y ( rguard_get g )  : z ( snd y )  : l2 l`
    (`l2`'s scope ends first, dropping the lock's only share while `g`
    lives; then `z`'s, `y`'s and `g`'s). -/
def main : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letd 3 0 (.new DT)
      (.seq (.push 3 2) (.letv 4 (.lockNew (.vec DT) 3) (Stmt.withRead 4 5 6 7 (.letv 8 (.var 4) .skip)))))))

/-- The lock share moved to `l2`: owned, holding nothing (`ELV`'s). -/
def EL2 : Entry := ⟨.lk (.vec DT), .own, true, [], [], false, false⟩

/-- **An `RwLocked` of a `Vec` of destructor values, read through a guard,
    its last share moved away while the guard lives, is typed** (Agora #831):
    `rw_new` of the `Vec` is `locked_new`'s (`Ty.lkPay` admits a drained
    `Vec` holding no cell share), the read guard is `rw_read`'s
    (`Ty.rguard (vec DT)`, `Ty.ok`'s case: the payload a lock's, holding no
    cell share), and the guard borrows nothing of `l` (`RhsT.rwRead` leaves
    the context as it was: the guard holds a share of its own, through the
    view), so `l` moves out (`RhsT.moveOwn`) while `g`, `y` and `z` live. -/
theorem main_typed : ∃ Δ, StmtT P (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEDe]; simp)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  -- the `Vec`, and the push of `x` into it (`A2.ArcDtorWitness.mainV`'s)
  let EN : Entry := ⟨.vec DT, .own, true, [], [], false, false⟩
  have hnew : RhsT K3 [] (.new DT) EN K3 := RhsT.new (by decide)
  let EV : Entry := Entry.arm { EN with ty := .vec DT, held := [] }
  have hEVe : EV = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [EV, EN, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K4 : Ctx := A2.setE K3 3 EV
  have hK4 : NoRootb K4 := hK3.setE (by rw [hEVe]; simp)
  let K5 : Ctx := A2.setE (kill .replace false 2 K4) 2 { ED with live := false, dtor := false }
  have hK5 : NoRootb K5 := (hK4.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K4 [] 2 ED DT ED.held K5 :=
    PushArg.move (Γ := K4) (F := []) (y := 2) (E := ED) (t := DT) rfl (by rw [hEDe]) (by simp)
      (hK4.noPin _) (DtorSafe.of_none (fun v E h => (hK4 v E h).2.1) _ _ _)
  have hK53 : K5 3 = some EV := by
    simp [K5, K4, A2.setE, upd, A2.kill, killE, hits, hEVe, Entry.vdeps, Mode.ownSlot]
  have hpush := StmtT.push (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 3) (y := 2) (Ex := EV) (Ey := ED)
    (Ex1 := EV) (t := DT) (D := ED.held) (by simp [K4, A2.setE]) (by rw [hEVe]) (by rw [hEVe])
    (Or.inl (by rw [hEVe])) (by simp) (by simp [K4, K3, A2.setE, upd]) (by rw [hEDe]) (by rw [hEDe])
    (by decide) hmove (by rw [hEDe]; simp [roots]) hK53 (by rw [hEVe])
    (DtorSafe.of_none (fun v E h => (hK5 v E h).2.1) _ _ _) (by rw [hEVe]; simp)
  let E3 : Entry := { EV with held := EV.held ++ ownHeld true DT ED.held }
  have hE3e : E3 = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [E3, hEVe, hEDe, ownHeld]
  let K6 : Ctx := A2.setE (kill .realloc DT.holdsView 3 K5) 3 E3
  have hK6 : NoRootb K6 := (hK5.kill _ _ _).setE (by rw [hE3e]; simp)
  -- `rw_new v`: the `Vec` moves into the lock block
  let K7 : Ctx := A2.setE (kill .replace false 3 K6) 3 { E3 with live := false, dtor := false }
  have hK7 : NoRootb K7 := (hK6.kill _ _ _).setE (by rw [hE3e]; simp)
  have hmove2 : PushArg K6 [] 3 E3 (.vec DT) E3.held K7 :=
    PushArg.move (Γ := K6) (F := []) (y := 3) (E := E3) (t := .vec DT) rfl (by rw [hE3e]) (by simp)
      (hK6.noPin _) (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _)
  have hK63 : K6 3 = some E3 := by simp [K6, A2.setE]
  have hlnew : RhsT K6 [] (.lockNew (.vec DT) 3) ELV K7 :=
    RhsT.lockNew hK63 (by rw [hE3e]) (by rw [hE3e]) (by decide)
      ⟨by simp [DT, T, Ty.holdsView], by simp [DT, T, Ty.hasFn]⟩ (by simp [DT, T, Ty.hasGuard]) hmove2
  let K8 : Ctx := A2.setE K7 4 ELV
  have hK8 : NoRootb K8 := hK7.setE (by simp [ELV])
  have hK84 : K8 4 = some ELV := by simp [K8, A2.setE]
  -- the read guard: an owned share of a view of the lock block
  let K9 : Ctx := A2.setE K8 5 (guardE (.vec DT))
  have hK9 : NoRootb K9 := hK8.setE (by simp [guardE])
  have hrd : RhsT K8 [] (.rwRead 4) (guardE (.vec DT)) K8 :=
    RhsT.rwRead hK84 rfl rfl (by simp [DT, T, Ty.hasCell])
  -- `rguard_get g`: the pair, lent through the guard
  let K10 : Ctx := A2.setE K9 6 (guardGetE 5 (.vec DT))
  have hK10 : NoRootb K10 := hK9.setE (by simp [guardGetE])
  have hget : RhsT K9 [] (.arcGet 5) (guardGetE 5 (.vec DT)) K9 := by
    have h := RhsT.arcGet (Γ := K9) (F := []) (a := 5) (E := guardE (.vec DT))
      (t := .prod (.lk (.vec DT)) (.vec DT))
      (by simp [K9, A2.setE]) rfl (Or.inr ⟨_, rfl, rfl⟩) (by simp [DT, T, Ty.holdsView])
      (by simp [DT, T, Ty.hasFn])
    rw [guardGet_eq] at h; exact h
  -- `snd y`: the `Vec`, lent
  let EX : Entry := projE 6 (guardGetE 5 (.vec DT)) (.vec DT)
  let K11 : Ctx := A2.setE K10 7 EX
  have hK11 : NoRootb K11 := hK10.setE (by simp [EX, projE])
  have hsnd : RhsT K10 [] (.snd 6) EX K10 :=
    RhsT.snd (a := .lk (.vec DT)) (by simp [K10, A2.setE]) rfl rfl
  -- `: l2 l`: the lock's only share moves out of `l`, the guard still bound
  have hK114 : K11 4 = some ELV := by simp [K11, K10, K9, K8, A2.setE, upd]
  let K12 : Ctx := A2.setE (kill .replace false 4 K11) 4 { ELV with live := false, dtor := false }
  have hK12 : NoRootb K12 := (hK11.kill _ _ _).setE (by simp [ELV])
  have hmv : RhsT K11 [] (.var 4) EL2 K12 :=
    RhsT.moveOwn hK114 rfl rfl (by simp) (hK11.noPin _)
      (DtorSafe.of_none (fun v E h => (hK11 v E h).2.1) _ _ _)
  let K13 : Ctx := A2.setE K12 8 EL2
  have hK13 : NoRootb K13 := hK12.setE (by simp [EL2])
  have hl2 := StmtT.letv (P := P) (x := 8) (r := .var 4) (E := EL2) (F := []) (Γ := K11) (Γ1 := K12)
    (s := .skip) rfl (by simp [K11, K10, K9, K8, K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill])
    (by simp) hmv StmtT.skip (hK13.endOK _) (fun _ => rfl)
  have hKa := hK13.exitScope 8
  have hz := StmtT.letv (P := P) (x := 7) (r := .snd 6) (E := EX) (F := []) (Γ := K10) (Γ1 := K10)
    rfl (by simp [K10, K9, K8, K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hsnd hl2
    (hKa.endOK _) (by simp [EX])
  have hy := StmtT.letv (P := P) (x := 6) (r := .arcGet 5) (E := guardGetE 5 (.vec DT)) (F := [])
    (Γ := K9) (Γ1 := K9) rfl (by simp [K9, K8, K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill])
    (by simp) hget hz ((hKa.exitScope 7).endOK _) (by simp [guardGetE])
  have hg := StmtT.letv (P := P) (x := 5) (r := .rwRead 4) (E := guardE (.vec DT)) (F := []) (Γ := K8)
    (Γ1 := K8) rfl (by simp [K8, K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hrd hy
    (((hKa.exitScope 7).exitScope 6).endOK _) (fun _ => by simp [guardE, Ty.holdsDtor])
  have hKf := ((hKa.exitScope 7).exitScope 6).exitScope 5
  have hl := StmtT.letv (P := P) (x := 4) (r := .lockNew (.vec DT) 3) (E := ELV) (F := []) (Γ := K6)
    (Γ1 := K7) rfl (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hlnew hg
    (hKf.endOK _) (fun _ => rfl)
  have hseq := StmtT.seq (P := P) rfl hpush hl
  have hdv := StmtT.letd (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (f := 0) (r := .new DT)
    (E := EN) (t := T) (H := []) (τ := .vec DT) rfl (by simp [K3, K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop0_ok) (HeldUp.refl _ _) hseq
    ((hKf.exitScope 4).endOK _)
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop0_ok) (HeldUp.refl _ _) hdv
    (((hKf.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd
    ((((hKf.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    (((((hKf.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- `rw_new` of the `Vec` names the elements' destructor, one the program
    checked (`Rhs.codeOK`). -/
theorem main_codes : main.codesOK P := by
  simp only [main, Stmt.withRead, Stmt.readWith, Stmt.codesOK, Rhs.codeOK, DT]
  exact ⟨trivial, trivial, trivial, trivial, trivial, arcNew_codeOK (n := 1) drop0_ok, trivial, trivial,
    trivial, trivial, trivial⟩

/-- **Every run of it is safe.** -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 9) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **... and leaks nothing**: when it finishes, every address is freed
    (`no_leak_end`): the `Vec`, owned by the lock block alone, is reaped
    and drained once the lock's last share and the guard's view are gone
    (`guard_drop_reaps_settle`, `A3.LockDtorWitness.reapV_drains`). -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 9) main (.ok m' .skip)) : ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **... and leaks nothing on a panic either** (`no_leak_panic`). -/
theorem main_no_leak_panic {m' : Mem} (hr : Steps P (emptyMem 9) main (.panic m')) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_panic prog_ok prog_codes ht rfl main_codes (by decide) hr

/-! ### Agora #831: the guard dropped after the lock's last share

When `l2`'s scope ends, the lock block's last share goes, but the guard's
share still reaches the view, whose payload holds a share of the lock block
(`view_keeps_lock`): the sweep keeps both.  When `g`'s scope ends, no root
refers to the view nor to the lock block, and the only block whose payload
refers to the lock block is the view, unreached, of kind `.view` (no orphan
to be, never `dead`).  The two are cut off together (`A2.CutOff`), so the
marking sweep that ends the guard's drop removes the view and marks the lock
block `dead`, its payload in it, and the thread that dropped the guard reaps
it (`A3.TStep.last_drop_reaps`, generalised by Agora #831 from "no block
refers to it" to a cut-off set). -/

/-- A lock block of a `Vec` of destructor values and the view of it a read
    guard made (`ViewsAt`) are cut off from roots that refer to neither,
    when no other block's payload refers to the lock block and none at all
    to the view. -/
theorem view_cutOff {R : Val → Prop} {B : Nat → Option Blk} {k kv : Nat} {t : Ty} {p : Val}
    (hkv : B kv = some ⟨.prod (.lk t) t, .view, some (.pair (.lk k) p)⟩)
    (hv : ∀ v, R v → ¬ Refers B v k ∧ ¬ Refers B v kv)
    (hb : ∀ k' bl', B k' = some bl' → ¬ Refers B bl'.keeps kv ∧ (k' ≠ kv → ¬ Refers B bl'.keeps k)) :
    CutOff R B (fun j => j = k ∨ j = kv) := by
  refine ⟨fun v hR j hj hr => ?_, fun k' bl' j hk' hj hr => ?_⟩
  · rcases hj with rfl | rfl
    · exact (hv v hR).1 hr
    · exact (hv v hR).2 hr
  · rcases hj with rfl | rfl
    · by_cases he : k' = kv
      · subst he
        rw [hkv] at hk'; cases hk'
        refine ⟨Or.inr rfl, ?_⟩
        rintro ⟨n, f, u, q, kd, he, hkd⟩
        simp only [Blk.mk.injEq] at he
        obtain ⟨-, rfl, -⟩ := he
        rcases hkd with h | h | h <;> cases h
      · exact absurd hr ((hb k' bl' hk').2 he)
    · exact absurd hr (hb k' bl' hk').1

/-- **Agora #831: the guard's drop after the lock's last share runs the
    destructor, on the thread that drops the guard.**  Thread `i`'s step (to
    `m'`, `s'`; in `main`, the end of `g`'s scope, `l2`'s having ended
    before) leaves the lock block `k` of a `Vec` of destructor values, its
    payload `p` in it, and the guard's view `kv` of it (its payload `pair (lk
    k) p`, `rwRead_view_lends`), that no thread's slot and no global refers
    to; no other block's payload refers to the lock block, and none to the
    view.  Then the configuration's marking sweep that ends the step marks
    the lock block `dead`, its payload in it, though the view, unreached and
    not yet swept, still refers to it; and in the result `C'` of this
    configuration step (whose reaps are all thread `i`'s, before any other
    thread runs) a fresh slot of thread `i` owns the `Vec` and the block is
    emptied or gone: a reap of thread `i` bound it in a destructor frame
    (`Step.reap`) whose end drains it, element 0 first, each to a frame of
    `dfn` (`A3.LockDtorWitness.reapV_drains`), as in nurlc, where an
    `RGuard` holds a `Shared` clone of the lock's state
    (`stdlib/std/rwlock.nu`): the guard's drop releases the last reference,
    which drops the `Vec`'s elements on the thread that runs it. -/
theorem guard_drop_reaps {C : Cfg} {i : Nat} {m' : Mem} {s' : Stmt} {C' : Cfg} (hlen : i < C.ths.length)
    (hse : CSettle P i (C.put i m' s').sweepD C') {k kv : Nat} {p : Val}
    (hk : m'.blk k = some ⟨.vec DT, .lock, some p⟩)
    (hkv : m'.blk kv = some ⟨.prod (.lk (.vec DT)) (.vec DT), .view, some (.pair (.lk k) p)⟩)
    (hv : ∀ v, (C.put i m' s').roots v → ¬ Refers m'.blk v k ∧ ¬ Refers m'.blk v kv)
    (hb : ∀ k' bl', m'.blk k' = some bl' →
      ¬ Refers m'.blk bl'.keeps kv ∧ (k' ≠ kv → ¬ Refers m'.blk bl'.keeps k)) :
    (C.put i m' s').sweepD.blk k = some ⟨.vec DT, .dead, some p⟩ ∧
      ∃ (t' : Thread) (x : Var), C'.ths[i]? = some t' ∧ t'.st x = some ⟨true, some p⟩ ∧ m'.nv ≤ x ∧
        Emptied C'.blk k (.vec DT) :=
  TStep.last_drop_reaps (n := 1) (f := 0) (u := T) hlen hse (Or.inr rfl) hk (view_cutOff hkv hv hb)
    (Or.inl rfl)

/-- ... and on A2's `Steps` (one thread, `Mem.sweepD` and `Settle`): the
    marking sweep that ends the guard's drop marks the lock block `dead`,
    and the thread's next step is a reap (`A3.LockDtorWitness.last_dropV_reaps`). -/
theorem guard_drop_reaps_settle {m : Mem} {k kv : Nat} {p : Val}
    (hk : m.blk k = some ⟨.vec DT, .lock, some p⟩)
    (hkv : m.blk kv = some ⟨.prod (.lk (.vec DT)) (.vec DT), .view, some (.pair (.lk k) p)⟩)
    (hv : ∀ v, m.vals v → ¬ Refers m.blk v k ∧ ¬ Refers m.blk v kv)
    (hb : ∀ k' bl', m.blk k' = some bl' →
      ¬ Refers m.blk bl'.keeps kv ∧ (k' ≠ kv → ¬ Refers m.blk bl'.keeps k))
    {s s' : Stmt} {m' : Mem} (h : Settle P m.sweepD s m' s') :
    m.sweepD.blk k = some ⟨.vec DT, .dead, some p⟩ ∧
      ∃ m1 s1, Step P m.sweepD s (.ok m1 s1) ∧ ReapMem m.sweepD m1 :=
  A3.LockDtorWitness.last_dropV_reaps hk (view_cutOff hkv hv hb) (Or.inl rfl) h

end A3.RwDtorWitness

namespace A3

/-- Agora #804, #831, the witness (`A3.RwDtorWitness.main`): an `RwLocked` of
    a `Vec` of destructor values, made, read through a guard that lends its
    payload, the lock's last share dropped while the guard lives, then the
    guard, on one thread.  The claim covers it: safe, race-free and
    leak-free on every interleaving.  (The thread that drops the guard reaps
    the `Vec` and drains it, `A3.RwDtorWitness.guard_drop_reaps`.) -/
theorem rwDtor_claim :
    MemorySafe LockDtorWitness.P (fun _ => false) (Cfg.start Globs.empty RwDtorWitness.main 9) ∧
      RaceFree LockDtorWitness.P (fun _ => false) (Cfg.start Globs.empty RwDtorWitness.main 9) ∧
      NoLeak LockDtorWitness.P (fun _ => false) (Cfg.start Globs.empty RwDtorWitness.main 9) := by
  obtain ⟨Δ, ht⟩ := RwDtorWitness.main_typed
  exact claim _ _ Globs.empty _ Δ 9 LockDtorWitness.prog_ok LockDtorWitness.prog_codes
    (fun _ h => by cases h) GlobsOK.empty ht rfl RwDtorWitness.main_codes (by decide)

end A3
