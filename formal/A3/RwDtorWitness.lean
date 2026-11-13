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
payload refers to the lock block (`A3.LockDtorWitness.last_drop_reaps`'
hypotheses, of a lock block of `DT`), the marking sweep marks it `dead` and
the same thread reaps it, the reap's frame running the payload's
destructor.  The other order, a guard dropped after the lock's last share
(its view still refers to the lock block, so `last_drop_reaps` does not
apply; the sweep that ends the guard's drop marks the lock block), is not
yet a lemma (Agora #831).

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
refuse the guard where nurlc does (`% NotSend RGuard`) without refusing that
`Arc` too.  A read guard is now a type of its own, `Ty.rguard u`; its value is
still a share of a view (`WFv.rguard`), and only a guard's share names a view
(`ArcBlk`).  `Ty.hasGuard` is true exactly where an `rguard` occurs, and
`Ty.ok` refuses it in a lock's, a cell's (so a channel's) and an `Arc`'s
payload, `Ty.sync` in a global, and `Cross.Fits` in a closure of a class
that crosses (`guard_refused`); a local binding, a struct or a `Vec` may hold
one, and the genuine `Arc` of a pair is admitted as before (`arc_pair_ok`).
So a lock's payload reaches no view, and its give-back's crossing check
passes (`A3.LockDtorWitness.giveCheck_typed`).

`main` makes a destructor value (`DT`, `A2/DtorWitness.lean`), moves it into
an `RwLocked` (`rw_new` is `locked_new`), reads it through a guard
(`Stmt.withRead`: the guard `g`, the lend `y` of the lock's share and the
payload, the payload `x` lent), and drops the guard, then the lock's only
share:

```
: a 1  : b 2  :drop d ( pair a b )  : l ( rw_new d )
: g ( rw_read l )  : y ( rguard_get g )  : x ( snd y )      -- g's, then l's scope ends
```

It is typed (`main_typed`), every run of it is safe (`main_safe`) and,
finished or panicked, leaks nothing (`main_no_leak`, `main_no_leak_panic`);
A3's claim covers it, race freedom included (`A3.rwDtor_claim`). -/

namespace A3.RwDtorWitness
open A2
open A2.DynCell (NoRootb noRootb_empty)
open A2.DtorWitness (NoDeps T DT dfn EP R0)
open A3.LockDtorWitness (P prog_ok prog_codes drop0_ok EL)

/-! ### Agora #837: the guard's own type, refused where it would cross -/

/-- **A read guard is `% NotSend` in the types** (Agora #837, as nurlc's
    `RGuard`): no lock's or cell's payload holds one, at any depth (here a
    `Locked` of a destructor value holding a guard in a field, the case
    `Step.scopeLPD` was made total for), nor a channel's queue, nor an
    `Arc`'s payload, nor a global (`Ty.sync`), nor a `send` closure's
    environment (`Cross.Fits`); a local binding may hold one, and so may a
    struct or a `Vec` that stays on its thread. -/
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
  have := h.guard rfl rfl
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

/-! ### The witness -/

/-- `: a 1  : b 2  :drop d ( pair a b )  : l ( rw_new d )
     : g ( rw_read l )  : y ( rguard_get g )  : x ( snd y )`. -/
def main : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2)) (.letd 2 0 (.pair 0 1)
    (.letv 3 (.lockNew DT 2) (Stmt.withRead 3 4 5 6 .skip))))

/-- **An `RwLocked` of a destructor value, read through a guard, is typed**
    (Agora #804): `rw_new` is `locked_new` of the value (Agora #755), the read
    guard is `rw_read`'s (`rwRead_dtor_typed`), and what it lends is the
    pair of the lock's share and the payload, then the payload, each a
    borrow through the guard. -/
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
  -- `rw_new d`: `d` moves into the lock block
  let ED' : Entry := { ED with live := false, dtor := false }
  let K3' : Ctx := A2.setE K3 2 ED'
  have hkill : A2.kill .replace false 2 K3 = K3 := hD3.kill_eq _ _ _
  have hnew : RhsT K3 [] (.lockNew DT 2) EL K3' := by
    have h := RhsT.lockNew (Γ := K3) (F := []) (t := DT) (y := 2) (Ey := ED) hK3d
      (by simp [ED, Entry.arm, EP]) (by simp [ED, Entry.arm]) (by decide)
      ⟨by simp [DT, T, Ty.holdsView], by simp [DT, T, Ty.hasFn]⟩ (by simp [DT, T, Ty.hasGuard])
      (PushArg.move (by simp [DT, T, Ty.owning]) (by simp [ED, Entry.arm, EP]) (by simp)
        (hK3.noPin 2) (DtorSafe.of_none (fun v E h => (hK3 v E h).2.1) _ _ _))
    rw [hkill] at h; exact h
  have hK3' : NoRootb K3' := hK3.setE (by simp [ED', ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView])
  let K4 : Ctx := A2.setE K3' 3 EL
  have hK4 : NoRootb K4 := hK3'.setE (by simp [EL])
  have hK4l : K4 3 = some EL := by simp [K4, A2.setE]
  -- the read guard: an owned share of a view of the lock block
  let K5 : Ctx := A2.setE K4 4 (guardE DT)
  have hK5 : NoRootb K5 := hK4.setE (by simp [guardE])
  have hrd : RhsT K4 [] (.rwRead 3) (guardE DT) K4 :=
    rwRead_dtor_typed (f := 0) (u := T) hK4l rfl rfl (by simp [T, Ty.hasCell])
  -- `rguard_get g`: the pair, lent through the guard
  let K6 : Ctx := A2.setE K5 5 (guardGetE 4 DT)
  have hK6 : NoRootb K6 := hK5.setE (by simp [guardGetE])
  have hget : RhsT K5 [] (.arcGet 4) (guardGetE 4 DT) K5 := by
    have h := RhsT.arcGet (Γ := K5) (F := []) (a := 4) (E := guardE DT) (t := .prod (.lk DT) DT)
      (by simp [K5, A2.setE]) rfl (Or.inr ⟨_, rfl, rfl⟩) (by simp [DT, T, Ty.holdsView]) (by simp [DT, T, Ty.hasFn])
    rw [guardGet_eq] at h; exact h
  -- `snd y`: the payload, lent
  let EX : Entry := projE 5 (guardGetE 4 DT) DT
  let K7 : Ctx := A2.setE K6 6 EX
  have hK7 : NoRootb K7 := hK6.setE (by simp [EX, projE, DT])
  have hsnd : RhsT K6 [] (.snd 5) EX K6 :=
    RhsT.snd (a := .lk DT) (by simp [K6, A2.setE]) rfl rfl
  have hx := StmtT.letv (P := P) (x := 6) (r := .snd 5) (E := EX) (F := []) (Γ := K6) (Γ1 := K6)
    rfl (by simp [K6, K5, K4, K3', K3, K2, K1, A2.setE, upd]) (by simp) hsnd StmtT.skip (hK7.endOK _)
    (by simp [EX])
  have hy := StmtT.letv (P := P) (x := 5) (r := .arcGet 4) (E := guardGetE 4 DT) (F := []) (Γ := K5) (Γ1 := K5)
    rfl (by simp [K5, K4, K3', K3, K2, K1, A2.setE, upd]) (by simp) hget hx ((hK7.exitScope 6).endOK _)
    (by simp [guardGetE])
  have hg := StmtT.letv (P := P) (x := 4) (r := .rwRead 3) (E := guardE DT) (F := []) (Γ := K4) (Γ1 := K4)
    rfl (by simp [K4, K3', K3, K2, K1, A2.setE, upd]) (by simp) hrd hy (((hK7.exitScope 6).exitScope 5).endOK _)
    (fun _ => by simp [guardE, Ty.holdsDtor])
  have hKf := ((hK7.exitScope 6).exitScope 5).exitScope 4
  have hl := StmtT.letv (P := P) (x := 3) (r := .lockNew DT 2) (E := EL) (F := []) (Γ := K3) (Γ1 := K3')
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) hnew hg (hKf.endOK _) (fun _ => rfl)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE]) rfl PushArg.int
      (by simp [K2, K1, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE]) (by simp) hpair rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop0_ok) (HeldUp.refl _ _) hl
    ((hKf.exitScope 3).endOK _) (by simp [Stmt.assigns])
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd
    (((hKf.exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    ((((hKf.exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- `rw_new` of the destructor value names the destructor the program
    checked (`Rhs.codeOK`). -/
theorem main_codes : main.codesOK P := by
  simp only [main, Stmt.withRead, Stmt.readWith, Stmt.codesOK, Rhs.codeOK, DT]
  exact ⟨trivial, trivial, trivial, arcNew_codeOK (n := 0) drop0_ok, trivial, trivial, trivial, trivial⟩

/-- **Every run of it is safe.** -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 7) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **... and leaks nothing**: when it finishes, every address is freed
    (`no_leak_end`): the payload, owned by the lock block alone, is reaped
    once its last share and the guard's view are gone. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 7) main (.ok m' .skip)) : ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **... and leaks nothing on a panic either** (`no_leak_panic`). -/
theorem main_no_leak_panic {m' : Mem} (hr : Steps P (emptyMem 7) main (.panic m')) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_panic prog_ok prog_codes ht rfl main_codes (by decide) hr

end A3.RwDtorWitness

namespace A3

/-- Agora #804, the witness (`A3.RwDtorWitness.main`): an `RwLocked` of a
    destructor value, made, read through a guard that lends its payload, the
    guard and then the lock's last share dropped, on one thread.  The claim
    covers it: safe, race-free and leak-free on every interleaving. -/
theorem rwDtor_claim :
    MemorySafe LockDtorWitness.P (fun _ => false) (Cfg.start Globs.empty RwDtorWitness.main 7) ∧
      RaceFree LockDtorWitness.P (fun _ => false) (Cfg.start Globs.empty RwDtorWitness.main 7) ∧
      NoLeak LockDtorWitness.P (fun _ => false) (Cfg.start Globs.empty RwDtorWitness.main 7) := by
  obtain ⟨Δ, ht⟩ := RwDtorWitness.main_typed
  exact claim _ _ Globs.empty _ Δ 7 LockDtorWitness.prog_ok LockDtorWitness.prog_codes
    (fun _ h => by cases h) GlobsOK.empty ht rfl RwDtorWitness.main_codes (by decide)

end A3
