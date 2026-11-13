import A3.Reap
import A3.Keys

/-! A3 — Agora #755, a channel of destructor values, and a witness.

nurlc's `Channel A` is a share of a counted block holding a `ChImpl A`: a
struct of the queue (`Vec A`), the closed flag and the waiters, whose drop
glue drops the queue, element 0 first, when the last share goes
(`stdlib/std/channel.nu`: `Channel_drop` is the `Shared` field's drop).  The
model's channel is a lock block whose payload is the queue and the flag; for
a channel of destructor values that payload is under its glue, the
destructor type `GVD = Ty.dtor 7 (prod (vec DT) int)` whose destructor is
`glueV` (`A2/DtorWitness.lean`: it takes the struct apart and hands the
queue to a `letd` at its own type, whose frame drains it): `Ty.ChanOf`.
So the channel is a `Locked D` of that struct (`Ty.lkPay`), and its last
share's drop is `Locked D`'s: the marking sweep marks the block, the same
thread reaps it into a frame of `glueV`.

`main` makes the channel's state from an empty queue and a 0, moves it into
a lock (the model's `chan_new`), makes a destructor value and sends it, and
drops the channel's only share with the value never received:

```
: a 1  : b 2  :drop q ( vec_new DT )  : c 0  :drop h ( pair q c )   -- glueV's struct
: ch ( locked_new h )                                               -- chan_new
:drop x ( pair a b )  : r ( chan_send ch x )                        -- ch's scope ends
```

It is typed (`main_typed`), safe (`main_safe`) and leak-free (`main_no_leak`,
`main_no_leak_panic`); A3's claim covers it (`A3.chanDtor_claim`).  When
nothing refers to the channel's block any more the marking sweep marks it
`dead`, its payload in it, and the thread's next step is the reap
(`last_drop_reaps`, and on A3's threads `A3.chanDtor_reaps`), which binds
the payload in a frame `scopeD _ 7 skip` whose end calls `glueV` on it
(`reap_runs_glue`, over `A2.Dtor.scopeD_end_runs_dtor`); the glue's body
takes it apart and drains the queue (Agora #805, `A3.chanGlue_drains`,
`glueV_drains`: the queue goes to a `letd` frame of `dfn`, the elements'
destructor, whose end with the queue non-empty is one drain step, element 0
to a `letd` frame of `dfn` of its own; index order is that step taken again
on the shorter queue, which no theorem iterates), as
nurlc's last `Channel_drop` drops the queued elements in order on the
dropping thread.  As for the other witnesses, no theorem traces the run.

A `chan_send` to a closed channel does not queue the value: it moves it
into a fresh lock block of the element type that no share names
(`EvalR.chanSendClosed`; `closed_send_parks` proves that much), which the
marking sweep that ends the step is to mark `dead` for the sending thread
to reap, as nurlc's `chan_send` drops the value before it returns.  Agora
#805 proves it: every share in a configuration a typed start reaches names
a key below `nid` (`A3.reach_keys`), so nothing refers to the fresh block,
which the sweep marks and the sender's reaps bind
(`A3.TStep.closed_send_reaps`); `mainC` closes the channel, then sends a
destructor value (`mainC_typed`, `A3.chanClosed_claim`,
`A3.chanClosed_reaps`).  The receiver's binding of a `chan_recv` of destructor
values is an `Option D`, which only a `letd` with the option's glue binds
(`letv` refuses a type that holds a destructor value): Agora #805's
`mainR` is that witness (its glue `A2.DtorWitness.ofnR`). -/

namespace A3.ChanDtorWitness
open A2
open A2.DynCell (NoRootb noRootb_empty)
open A2.DtorWitness (NoDeps T DT GV GVD EP P prog_ok prog_codes drop_ok gvdrop_ok)

/-- `: a 1  : b 2  :drop q ( vec_new DT )  : c 0  :drop h ( pair q c )
     : ch ( locked_new h )  :drop x ( pair a b )  : r ( chan_send ch x )` -/
def main : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2)) (.letd 2 0 (.new DT)
    (.letv 3 (.expr (.lit 0)) (.letd 4 7 (.pair 2 3)
      (.letv 5 (.lockNew GVD 4) (.letd 6 0 (.pair 0 1) (.letv 7 (.chanSend 5 6) .skip)))))))

/-- The channel share's entry: owned, holding nothing. -/
def EC : Entry := ⟨.lk GVD, .own, true, [], [], false, false⟩

/-- A channel of destructor values is a lock share of the queue's glue struct. -/
theorem chan_of : (Ty.lk GVD).ChanOf DT := ⟨GVD, rfl, rfl⟩

/-- **A channel of destructor values is typed** (Agora #755): its state is a
    struct holding a drained `Vec`, bound by `letd` under its glue (`GVD`),
    moved into a lock (`Ty.lkPay`: a destructor type holding no cell share), and
    `chan_send` sends a destructor value into it (`RhsT.chanSend` over
    `Ty.ChanOf`). -/
theorem main_typed : ∃ Δ, StmtT P (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  -- the queue
  let EN : Entry := ⟨.vec DT, .own, true, [], [], false, false⟩
  have hnew : RhsT K2 [] (.new DT) EN K2 := RhsT.new (by decide)
  let EV : Entry := Entry.arm { EN with ty := .vec DT, held := [] }
  have hEVe : EV = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [EV, EN, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 EV
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEVe]; simp)
  -- the flag
  let K4 : Ctx := A2.setE K3 3 intE
  have hK4 : NoRootb K4 := hK3.setE (by simp [intE])
  -- the struct of the queue and the flag, under its glue
  let K5 : Ctx := A2.setE (kill .replace false 2 K4) 2 { EV with live := false, dtor := false }
  have hK5 : NoRootb K5 := (hK4.kill _ _ _).setE (by rw [hEVe]; simp)
  have h42 : K4 2 = some EV := by simp [K4, K3, A2.setE, upd]
  have hmv : PushArg K4 [] 2 EV EV.ty EV.held K5 :=
    PushArg.move (Γ := K4) (F := []) (y := 2) (E := EV) (t := EV.ty) rfl (by rw [hEVe]) (by simp)
      (hK4.noPin _) (DtorSafe.of_none (fun v E h => (hK4 v E h).2.1) _ _ _)
  have h53 : K5 3 = some intE := by
    simp [K5, K4, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps, Mode.ownSlot]
  let EG0 : Entry := ⟨.prod EV.ty intE.ty, .own, true, [], EV.held ++ [], false, false⟩
  have hgp : RhsT K4 [] (.pair 2 3) EG0 K5 :=
    RhsT.pair (Ey := EV) (Ez := intE) h42 (by rw [hEVe]) hmv h53 rfl PushArg.int
      (by simp [intE, Mode.ownSlot])
  have hEG0 : EG0 = ⟨GV, .own, true, [], [], false, false⟩ := by simp [EG0, hEVe, intE, GV]
  let EGa : Entry := Entry.arm { EG0 with ty := GVD, held := EG0.held }
  have hEGa : EGa = ⟨GVD, .own, true, [], [], false, false⟩ := by
    simp [EGa, hEG0, Entry.arm, GVD, GV, DT, T, Ty.dtorViews, Ty.holdsView]
  let K6 : Ctx := A2.setE K5 4 EGa
  have hK6 : NoRootb K6 := hK5.setE (by rw [hEGa]; simp)
  -- `chan_new`: the struct moves into the lock block
  let K6' : Ctx := A2.setE (kill .replace false 4 K6) 4 { EGa with live := false, dtor := false }
  have hK6' : NoRootb K6' := (hK6.kill _ _ _).setE (by rw [hEGa]; simp)
  have hmv4 : PushArg K6 [] 4 EGa GVD EGa.held K6' :=
    PushArg.move (Γ := K6) (F := []) (y := 4) (E := EGa) (t := GVD) rfl (by rw [hEGa]) (by simp)
      (hK6.noPin _) (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _)
  have hlnew : RhsT K6 [] (.lockNew GVD 4) EC K6' :=
    RhsT.lockNew (by simp [K6, A2.setE]) (by rw [hEGa]) (by rw [hEGa]) (by decide)
      ⟨by simp [GVD, GV, DT, T, Ty.holdsView], by simp [GVD, GV, DT, T, Ty.hasFn]⟩ hmv4
  let K7 : Ctx := A2.setE K6' 5 EC
  have hK7 : NoRootb K7 := hK6'.setE (by simp [EC])
  -- `:drop x ( pair a b )`
  have hpair : RhsT K7 [] (.pair 0 1) EP K7 :=
    RhsT.pair (Ey := intE) (Ez := intE)
      (by simp [K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps,
        Mode.ownSlot])
      rfl PushArg.int
      (by simp [K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps,
        Mode.ownSlot])
      rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K8 : Ctx := A2.setE K7 6 ED
  have hK8 : NoRootb K8 := hK7.setE (by rw [hEDe]; simp)
  -- `chan_send ch x`: `x` moves into the queue
  let K8' : Ctx := A2.setE (kill .replace false 6 K8) 6 { ED with live := false, dtor := false }
  have hK8' : NoRootb K8' := (hK8.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmv6 : PushArg K8 [] 6 ED DT ED.held K8' :=
    PushArg.move (Γ := K8) (F := []) (y := 6) (E := ED) (t := DT) rfl (by rw [hEDe]) (by simp)
      (hK8.noPin _) (DtorSafe.of_none (fun v E h => (hK8 v E h).2.1) _ _ _)
  have hsend : RhsT K8 [] (.chanSend 5 6) intE K8' :=
    RhsT.chanSend (Ea := EC) (s := DT)
      (by simp [K8, K7, A2.setE, upd]) rfl chan_of (by simp [K8, A2.setE]) (by rw [hEDe]) (by rw [hEDe])
      hmv6
  let K9 : Ctx := A2.setE K8' 7 intE
  have hK9 : NoRootb K9 := hK8'.setE (by simp [intE])
  have hr := StmtT.letv (P := P) (x := 7) (r := .chanSend 5 6) (E := intE) (F := []) (Γ := K8) (Γ1 := K8')
    (s := .skip) rfl (by simp [K8, K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp)
    hsend StmtT.skip (hK9.endOK _)
  have hx := StmtT.letd (P := P) (Γ := K7) (Γ1 := K7) (F := []) (x := 6) (f := 0) (r := .pair 0 1)
    (s := .letv 7 (.chanSend 5 6) .skip) (E := EP) (t := T) (H := []) rfl
    (by simp [K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hpair rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hr
    ((hK9.exitScope 7).endOK _)
  have hc := StmtT.letv (P := P) (x := 5) (r := .lockNew GVD 4) (E := EC) (F := []) (Γ := K6) (Γ1 := K6')
    rfl (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hlnew hx
    (((hK9.exitScope 7).exitScope 6).endOK _) (fun _ => rfl)
  have hg := StmtT.letd (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 4) (f := 7) (r := .pair 2 3)
    (s := .letv 5 (.lockNew GVD 4) (.letd 6 0 (.pair 0 1) (.letv 7 (.chanSend 5 6) .skip)))
    (E := EG0) (t := GV) (H := EG0.held) (τ := GVD) rfl
    (by simp [K4, K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by rw [hEG0])⟩) rfl rfl (letd_fn gvdrop_ok) (HeldUp.refl _ _) hc
    ((((hK9.exitScope 7).exitScope 6).exitScope 5).endOK _)
  have h3 := StmtT.letv (P := P) (x := 3) (r := .expr (.lit 0)) (E := intE) (F := []) (Γ := K3) (Γ1 := K3)
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hg
    (((((hK9.exitScope 7).exitScope 6).exitScope 5).exitScope 4).endOK _)
  have hdv := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .new DT)
    (E := EN) (t := T) (H := []) (τ := .vec DT) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) h3
    ((((((hK9.exitScope 7).exitScope 6).exitScope 5).exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hdv
    (((((((hK9.exitScope 7).exitScope 6).exitScope 5).exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    ((((((((hK9.exitScope 7).exitScope 6).exitScope 5).exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- `chan_new` of the struct names the glue's check and the elements'
    destructor's (`Rhs.codeOK`, `chanNew_codeOK`). -/
theorem main_codes : main.codesOK P := by
  simp only [main, Stmt.codesOK, Rhs.codeOK]
  exact ⟨trivial, trivial, trivial, trivial, trivial, chanNew_codeOK (n := 0) gvdrop_ok drop_ok, trivial,
    trivial, trivial⟩

/-- **Every run of it is safe.** -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 8) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **... and leaks nothing** (`no_leak_end`; that the queued value's
    destructor ran on the way is read off the steps, `last_drop_reaps` /
    `reap_runs_glue`, not stated here). -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 8) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **... and on a panic either** (`no_leak_panic`). -/
theorem main_no_leak_panic {m' : Mem} (hr : Steps P (emptyMem 8) main (.panic m')) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_panic prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **The channel's last share's drop hands its state to a destructor frame
    of the same thread**: when no slot's value and no block's payload refers
    to the channel's lock block, its payload in it, the marking sweep marks
    it `dead` (`Mem.sweepD_marks`, at a lock block of `GVD`), and the
    thread's next step is a reap (`settle_reaps`). -/
theorem last_drop_reaps {m : Mem} {k : Nat} {p : Val} (hk : m.blk k = some ⟨GVD, .lock, some p⟩)
    (hv : ∀ x o v, m.st x = some ⟨o, some v⟩ → ¬ Refers m.blk v k)
    (hb : ∀ k' bl', m.blk k' = some bl' → ¬ Refers m.blk bl'.keeps k)
    {s s' : Stmt} {m' : Mem} (h : Settle P m.sweepD s m' s') :
    m.sweepD.blk k = some ⟨GVD, .dead, some p⟩ ∧
      ∃ m1 s1, Step P m.sweepD s (.ok m1 s1) ∧ ReapMem m.sweepD m1 := by
  have hm := Mem.sweepD_marks (n := 0) (f := 7) (u := GV) (Or.inr rfl) hk hv hb
  exact ⟨hm, settle_reaps h ⟨k, 0, 7, GV, p, hm⟩⟩

/-- **The reap's frame runs the queue's glue**: `Step.reap` of the `dead`
    block moves the channel's state to the fresh slot `m.nv` and puts
    `scopeD m.nv 7 skip` before the redex; from a store where that slot
    still holds it (no node: a struct) and no orphan awaits, that frame's end
    is the call of `glueV` on it (`A2.Dtor.scopeD_end_runs_dtor`), whose body
    takes it apart and drains the queue (`A3.chanGlue_drains`, `glueV_drains`). -/
theorem reap_runs_glue {m : Mem} {k : Nat} {q f : Val}
    (hk : m.blk k = some ⟨GVD, .dead, some (.pair q f)⟩)
    (hnc : ∀ c', ¬ Sub (.cell c') (.pair q f)) {r : Stmt} (hr : r.src = true) :
    ∃ m1, Step P m r (.ok m1 (.seq (.scopeD m.nv 7 .skip) r)) ∧
      m1.st m.nv = some ⟨true, some (.pair q f)⟩ ∧
      ∀ m2 : Mem, m2.st m.nv = some ⟨true, some (.pair q f)⟩ → ¬ Orphan m2 →
        Step P m2 (.scopeD m.nv 7 .skip) (.ok { m2 with nv := m2.nv + 1 }
          (.scope m.nv (.letcall m2.nv 7 [m.nv] .skip))) := by
  refine ⟨_, Step.reap (n := 0) (f := 7) (u := GV) hr hk hnc, by simp [Mem.set, upd], fun m2 hx _ => ?_⟩
  exact Step.scopeDEnd hx rfl

/-- **A send to a closed channel parks the value in a lock block of its own**:
    the value `chan_send` takes from `y` is not queued; the store after the
    send holds it in a fresh lock block of the queue's element type, at the
    key `m1.nid` (no share names it), and the answer is 0.  The marking
    sweep that ends the step then marks it `dead`, for the sending thread to
    reap (Agora #805: `A3.TStep.closed_send_reaps`, over every share's key
    being below `nid`): the destructor runs on the sender, as nurlc's
    `chan_send` drops the value it did not queue before it returns. -/
theorem closed_send_parks {m m' : Mem} {a y : Var} {r : Val} {o : Bool}
    (h : EvalR m (.chanSend a y) (.ok r o m')) {o' : Bool} {k : Nat} {t : Ty} {q : Val} {f : Nat}
    (ha : m.st a = some ⟨o', some (.lk k)⟩) (hk : m.blk k = some ⟨t, .lock, some (.pair q (.int (f + 1)))⟩) :
    r = .int 0 ∧ ∃ v m1 s, TakeVal m y v m1 ∧ t.undtor = .prod (.vec s) .int ∧
      m'.blk m1.nid = some ⟨s, .lock, some v⟩ ∧ m1.blk m1.nid = none := by
  cases h with
  | chanSend hv ht hk' _ _ _ _ =>
    rw [ha] at hv; cases hv
    rw [TakeVal.blk ht, hk] at hk'; cases hk'
  | chanSendClosed hv ht hk' hs hfr _ =>
    rw [ha] at hv; cases hv
    rw [TakeVal.blk ht, hk] at hk'; cases hk'
    exact ⟨rfl, _, _, _, ht, hs, by simp [upd], hfr⟩

end A3.ChanDtorWitness

namespace A3
open A2

/-- Agora #755, the witness (`A3.ChanDtorWitness.main`): a channel of
    destructor values, a value sent and never received, the channel's only
    share dropped.  The claim covers it: safe, race-free and leak-free on
    every interleaving. -/
theorem chanDtor_claim :
    MemorySafe A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty ChanDtorWitness.main 8) ∧
      RaceFree A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty ChanDtorWitness.main 8) ∧
      NoLeak A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty ChanDtorWitness.main 8) := by
  obtain ⟨Δ, ht⟩ := ChanDtorWitness.main_typed
  exact claim _ _ Globs.empty _ Δ 8 A2.DtorWitness.prog_ok A2.DtorWitness.prog_codes
    (fun _ h => by cases h) GlobsOK.empty ht rfl ChanDtorWitness.main_codes (by decide)

/-- ... and on A3's threads (Agora #755 item 1): the thread whose step drops
    the channel's last share, its payload in its block, reaps it in that
    configuration step, binding the channel's state in a frame of its glue
    (`A3.ChanDtorWitness.reap_runs_glue`), which drains the queue: as
    nurlc's last `Channel_drop` drops the queued elements on the thread that
    runs it. -/
theorem chanDtor_reaps {C : Cfg} {i : Nat} {m' : Mem} {s' : Stmt} {C' : Cfg} (hlen : i < C.ths.length)
    (hse : CSettle A2.DtorWitness.P i (C.put i m' s').sweepD C') {k : Nat} {p : Val}
    (hk : m'.blk k = some ⟨A2.DtorWitness.GVD, .lock, some p⟩)
    (hv : ∀ v, (C.put i m' s').roots v → ¬ Refers m'.blk v k)
    (hb : ∀ k' bl', m'.blk k' = some bl' → ¬ Refers m'.blk bl'.keeps k) :
    (C.put i m' s').sweepD.blk k = some ⟨A2.DtorWitness.GVD, .dead, some p⟩ ∧
      ∃ (t' : Thread) (x : Var), C'.ths[i]? = some t' ∧ t'.st x = some ⟨true, some p⟩ ∧ m'.nv ≤ x ∧
        Emptied C'.blk k A2.DtorWitness.GVD :=
  TStep.last_drop_reaps (n := 0) (f := 7) (u := A2.DtorWitness.GV) hlen hse (Or.inr rfl) hk hv hb

end A3

/-! ### Agora #805: a closed channel, then a send

`mainC` makes the channel as `main` does, closes it, then sends a destructor
value: the send does not queue it but parks it in a fresh lock block, which
the marking sweep that ends the step marks for the sending thread to reap
(`A3.TStep.closed_send_reaps`, here `A3.chanClosed_reaps`):

```
: a 1  : b 2  :drop q ( vec_new DT )  : c 0  :drop h ( pair q c )
: ch ( locked_new h )  : z ( chan_close ch )
:drop x ( pair a b )  : r ( chan_send ch x )
``` -/

namespace A3.ChanDtorWitness
open A2
open A2.DynCell (NoRootb noRootb_empty)
open A2.DtorWitness (NoDeps T DT GV GVD EP P prog_ok prog_codes drop_ok gvdrop_ok)

/-- `... : ch ( locked_new h )  : z ( chan_close ch )  :drop x ( pair a b )  : r ( chan_send ch x )` -/
def mainC : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2)) (.letd 2 0 (.new DT)
    (.letv 3 (.expr (.lit 0)) (.letd 4 7 (.pair 2 3)
      (.letv 5 (.lockNew GVD 4) (.letv 6 (.chanClose 5)
        (.letd 7 0 (.pair 0 1) (.letv 8 (.chanSend 5 7) .skip))))))))

/-- **Closing a channel of destructor values, then sending one, is typed**
    (`RhsT.chanClose`, `RhsT.chanSend` over `Ty.ChanOf`). -/
theorem mainC_typed : ∃ Δ, StmtT P (fun _ => none) [] mainC Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  let EN : Entry := ⟨.vec DT, .own, true, [], [], false, false⟩
  have hnew : RhsT K2 [] (.new DT) EN K2 := RhsT.new (by decide)
  let EV : Entry := Entry.arm { EN with ty := .vec DT, held := [] }
  have hEVe : EV = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [EV, EN, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 EV
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEVe]; simp)
  let K4 : Ctx := A2.setE K3 3 intE
  have hK4 : NoRootb K4 := hK3.setE (by simp [intE])
  let K5 : Ctx := A2.setE (kill .replace false 2 K4) 2 { EV with live := false, dtor := false }
  have hK5 : NoRootb K5 := (hK4.kill _ _ _).setE (by rw [hEVe]; simp)
  have h42 : K4 2 = some EV := by simp [K4, K3, A2.setE, upd]
  have hmv : PushArg K4 [] 2 EV EV.ty EV.held K5 :=
    PushArg.move (Γ := K4) (F := []) (y := 2) (E := EV) (t := EV.ty) rfl (by rw [hEVe]) (by simp)
      (hK4.noPin _) (DtorSafe.of_none (fun v E h => (hK4 v E h).2.1) _ _ _)
  have h53 : K5 3 = some intE := by
    simp [K5, K4, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps, Mode.ownSlot]
  let EG0 : Entry := ⟨.prod EV.ty intE.ty, .own, true, [], EV.held ++ [], false, false⟩
  have hgp : RhsT K4 [] (.pair 2 3) EG0 K5 :=
    RhsT.pair (Ey := EV) (Ez := intE) h42 (by rw [hEVe]) hmv h53 rfl PushArg.int
      (by simp [intE, Mode.ownSlot])
  have hEG0 : EG0 = ⟨GV, .own, true, [], [], false, false⟩ := by simp [EG0, hEVe, intE, GV]
  let EGa : Entry := Entry.arm { EG0 with ty := GVD, held := EG0.held }
  have hEGa : EGa = ⟨GVD, .own, true, [], [], false, false⟩ := by
    simp [EGa, hEG0, Entry.arm, GVD, GV, DT, T, Ty.dtorViews, Ty.holdsView]
  let K6 : Ctx := A2.setE K5 4 EGa
  have hK6 : NoRootb K6 := hK5.setE (by rw [hEGa]; simp)
  let K6' : Ctx := A2.setE (kill .replace false 4 K6) 4 { EGa with live := false, dtor := false }
  have hK6' : NoRootb K6' := (hK6.kill _ _ _).setE (by rw [hEGa]; simp)
  have hmv4 : PushArg K6 [] 4 EGa GVD EGa.held K6' :=
    PushArg.move (Γ := K6) (F := []) (y := 4) (E := EGa) (t := GVD) rfl (by rw [hEGa]) (by simp)
      (hK6.noPin _) (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _)
  have hlnew : RhsT K6 [] (.lockNew GVD 4) EC K6' :=
    RhsT.lockNew (by simp [K6, A2.setE]) (by rw [hEGa]) (by rw [hEGa]) (by decide)
      ⟨by simp [GVD, GV, DT, T, Ty.holdsView], by simp [GVD, GV, DT, T, Ty.hasFn]⟩ hmv4
  let K7 : Ctx := A2.setE K6' 5 EC
  have hK7 : NoRootb K7 := hK6'.setE (by simp [EC])
  -- `chan_close ch`
  have hclose : RhsT K7 [] (.chanClose 5) intE K7 :=
    RhsT.chanClose (E := EC) (s := DT) (by simp [K7, A2.setE]) rfl chan_of
  let K7c : Ctx := A2.setE K7 6 intE
  have hK7c : NoRootb K7c := hK7.setE (by simp [intE])
  -- `:drop x ( pair a b )`
  have hpair : RhsT K7c [] (.pair 0 1) EP K7c :=
    RhsT.pair (Ey := intE) (Ez := intE)
      (by simp [K7c, K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps,
        Mode.ownSlot])
      rfl PushArg.int
      (by simp [K7c, K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps,
        Mode.ownSlot])
      rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K8 : Ctx := A2.setE K7c 7 ED
  have hK8 : NoRootb K8 := hK7c.setE (by rw [hEDe]; simp)
  let K8' : Ctx := A2.setE (kill .replace false 7 K8) 7 { ED with live := false, dtor := false }
  have hK8' : NoRootb K8' := (hK8.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmv7 : PushArg K8 [] 7 ED DT ED.held K8' :=
    PushArg.move (Γ := K8) (F := []) (y := 7) (E := ED) (t := DT) rfl (by rw [hEDe]) (by simp)
      (hK8.noPin _) (DtorSafe.of_none (fun v E h => (hK8 v E h).2.1) _ _ _)
  have hsend : RhsT K8 [] (.chanSend 5 7) intE K8' :=
    RhsT.chanSend (Ea := EC) (s := DT)
      (by simp [K8, K7c, K7, A2.setE, upd]) rfl chan_of (by simp [K8, A2.setE]) (by rw [hEDe]) (by rw [hEDe])
      hmv7
  let K9 : Ctx := A2.setE K8' 8 intE
  have hK9 : NoRootb K9 := hK8'.setE (by simp [intE])
  have hr := StmtT.letv (P := P) (x := 8) (r := .chanSend 5 7) (E := intE) (F := []) (Γ := K8) (Γ1 := K8')
    (s := .skip) rfl (by simp [K8, K7c, K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp)
    hsend StmtT.skip (hK9.endOK _)
  have hx := StmtT.letd (P := P) (Γ := K7c) (Γ1 := K7c) (F := []) (x := 7) (f := 0) (r := .pair 0 1)
    (s := .letv 8 (.chanSend 5 7) .skip) (E := EP) (t := T) (H := []) rfl
    (by simp [K7c, K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hpair rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hr
    ((hK9.exitScope 8).endOK _)
  have hz := StmtT.letv (P := P) (x := 6) (r := .chanClose 5) (E := intE) (F := []) (Γ := K7) (Γ1 := K7)
    rfl (by simp [K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hclose hx
    (((hK9.exitScope 8).exitScope 7).endOK _) (fun _ => rfl)
  have hc := StmtT.letv (P := P) (x := 5) (r := .lockNew GVD 4) (E := EC) (F := []) (Γ := K6) (Γ1 := K6')
    rfl (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hlnew hz
    ((((hK9.exitScope 8).exitScope 7).exitScope 6).endOK _) (fun _ => rfl)
  have hg := StmtT.letd (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 4) (f := 7) (r := .pair 2 3)
    (s := .letv 5 (.lockNew GVD 4) (.letv 6 (.chanClose 5)
      (.letd 7 0 (.pair 0 1) (.letv 8 (.chanSend 5 7) .skip))))
    (E := EG0) (t := GV) (H := EG0.held) (τ := GVD) rfl
    (by simp [K4, K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by rw [hEG0])⟩) rfl rfl (letd_fn gvdrop_ok) (HeldUp.refl _ _) hc
    (((((hK9.exitScope 8).exitScope 7).exitScope 6).exitScope 5).endOK _)
  have h3 := StmtT.letv (P := P) (x := 3) (r := .expr (.lit 0)) (E := intE) (F := []) (Γ := K3) (Γ1 := K3)
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hg
    ((((((hK9.exitScope 8).exitScope 7).exitScope 6).exitScope 5).exitScope 4).endOK _)
  have hdv := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .new DT)
    (E := EN) (t := T) (H := []) (τ := .vec DT) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) h3
    (((((((hK9.exitScope 8).exitScope 7).exitScope 6).exitScope 5).exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hdv
    ((((((((hK9.exitScope 8).exitScope 7).exitScope 6).exitScope 5).exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    (((((((((hK9.exitScope 8).exitScope 7).exitScope 6).exitScope 5).exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

theorem mainC_codes : mainC.codesOK P := by
  simp only [mainC, Stmt.codesOK, Rhs.codeOK]
  exact ⟨trivial, trivial, trivial, trivial, trivial, chanNew_codeOK (n := 0) gvdrop_ok drop_ok, trivial,
    trivial, trivial, trivial⟩

/-- **Every run of it is safe** ... -/
theorem mainC_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 9) mainC (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := mainC_typed
  exact memory_safe prog_ok prog_codes ht rfl mainC_codes (by decide) hr

/-- **... and leaks nothing**, the parked value's block too ... -/
theorem mainC_no_leak {m' : Mem} (hr : Steps P (emptyMem 9) mainC (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := mainC_typed
  exact no_leak_end prog_ok prog_codes ht rfl mainC_codes (by decide) hr

/-- **... and on a panic either.** -/
theorem mainC_no_leak_panic {m' : Mem} (hr : Steps P (emptyMem 9) mainC (.panic m')) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := mainC_typed
  exact no_leak_panic prog_ok prog_codes ht rfl mainC_codes (by decide) hr

end A3.ChanDtorWitness

namespace A3
open A2

/-- Agora #805, the closed channel's witness (`A3.ChanDtorWitness.mainC`):
    safe, race-free and leak-free on every interleaving. -/
theorem chanClosed_claim :
    MemorySafe A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty ChanDtorWitness.mainC 9) ∧
      RaceFree A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty ChanDtorWitness.mainC 9) ∧
      NoLeak A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty ChanDtorWitness.mainC 9) := by
  obtain ⟨Δ, ht⟩ := ChanDtorWitness.mainC_typed
  exact claim _ _ Globs.empty _ Δ 9 A2.DtorWitness.prog_ok A2.DtorWitness.prog_codes
    (fun _ h => by cases h) GlobsOK.empty ht rfl ChanDtorWitness.mainC_codes (by decide)

/-- ... and its send to the closed channel (`A3.TStep.closed_send_reaps` at
    the witness's channel, a channel of `DT` under `glueV`'s struct): on
    every configuration the run reaches, when a thread's next step is a
    `letv` of `chan_send` whose channel is closed, the value goes into a
    fresh lock block at `C.nid`, the marking sweep that ends the step marks
    it `dead`, and in that configuration step's result a slot `w` of the
    sending thread at or above its `nv` before the step owns it, the block
    emptied or gone.  (That the reap's frame around it, `scopeD _ 0`, runs
    `dfn` at its end is `Step.reap`'s and `A2.Dtor.scopeD_end_runs_dtor`'s;
    this statement does not trace it.) -/
theorem chanClosed_reaps {C : Cfg} (hr : Reach A2.DtorWitness.P (fun _ => false)
      (Cfg.start Globs.empty ChanDtorWitness.mainC 9) C) {i : Nat}
    {t : Thread} {K : Stmt → Stmt} {x a y : Var} {k : Stmt} (hi : C.ths[i]? = some t)
    (hR : Redex t.s K (.letv x (.chanSend a y) k)) (hx : t.st x = none)
    {r : Val} {o : Bool} {m1 : Mem} (he : EvalR (C.view t) (.chanSend a y) (.ok r o m1))
    {o' : Bool} {kc : Nat} {q : Val} {f : Nat} (ha : t.st a = some ⟨o', some (.lk kc)⟩)
    (hc : C.blk kc = some ⟨A2.DtorWitness.GVD, .lock, some (.pair q (.int (f + 1)))⟩)
    {C' : Cfg} (hse : CSettle A2.DtorWitness.P i (C.put i (m1.set x ⟨o, some r⟩) (K (.scope x k))).sweepD C') :
    TStep A2.DtorWitness.P (fun _ => false) C C' ∧ r = .int 0 ∧ ∃ v m0, TakeVal (C.view t) y v m0 ∧
      (C.put i (m1.set x ⟨o, some r⟩) (K (.scope x k))).sweepD.blk C.nid =
        some ⟨A2.DtorWitness.DT, .dead, some v⟩ ∧
      ∃ (t' : Thread) (z : Var), C'.ths[i]? = some t' ∧ t'.st z = some ⟨true, some v⟩ ∧ t.nv ≤ z ∧
        Emptied C'.blk C.nid A2.DtorWitness.DT :=
  reach_closed_send_reaps (n := 0) (g := 0) (u := A2.DtorWitness.T) GlobsOK.empty hr hi hR
    (fun ⟨_, _, _, _, _, _, h⟩ => by cases h) hx he ha hc rfl hse

end A3

/-! ### Agora #805: a channel's glue drains the queue in index order

A channel's state under its glue is `Ty.dtor g (prod (vec s) int)`, `g` a
`GlueOK` function: its body takes the struct apart (`unpair 0 x z s'`), and
the queue's field `x`, of a type holding a destructor value, is handed on
first thing (`Stmt.movedFirst`).  Read through the typing, that hand-over is
a `letd` of the queue at its own type, `vec s`, in the chain of hand-overs
`s'` starts with (`LetdChain`: an `unpair` of `x` is refused, `x` being no
struct, and the glue's tail does nothing else, `Stmt.pureGlue`); its frame is
`scopeD w f`, whose end, with the queue non-empty, is the drain's step and
nothing else: element 0 to a `letd` of its own (`chanGlue_drains`; at the
witness's `glueV`, `glueV_drains`).  Not traced: the run from the reap's
call of the glue into its body (the call binds the struct to the renamed
parameter, `BindParams`), and the destructor of each element run to its
end. -/

namespace A3
open A2

/-- `t` is reached from `s` through hand-overs to `letd` (`letd w f (.var y) _`). -/
inductive LetdChain : Stmt → Stmt → Prop
  | refl {s : Stmt} : LetdChain s s
  | letd {w f y : Nat} {k t : Stmt} : LetdChain k t → LetdChain (.letd w f (.var y) k) t

/-- What `movedFirst` lists is moved by a `letd` of the chain, the chain's
    `assign`, or taken apart by its `unpair`. -/
theorem LetdChain.of_movedFirst {x : Var} : ∀ {s : Stmt}, x ∈ s.movedFirst →
    (∃ w f k, LetdChain s (.letd w f (.var x) k)) ∨ (∃ y, LetdChain s (.assign y (.var x))) ∨
      (∃ a b k, LetdChain s (.unpair x a b k))
  | .letd w f r k, h => by
    cases r with
    | var y =>
      simp only [Stmt.movedFirst, List.mem_cons] at h
      rcases h with rfl | h
      · exact .inl ⟨w, f, k, .refl⟩
      · rcases LetdChain.of_movedFirst h with ⟨w', f', k', hc⟩ | ⟨y', hc⟩ | ⟨a, b, k', hc⟩
        · exact .inl ⟨w', f', k', .letd hc⟩
        · exact .inr (.inl ⟨y', .letd hc⟩)
        · exact .inr (.inr ⟨a, b, k', .letd hc⟩)
    | _ => simp [Stmt.movedFirst] at h
  | .assign y r, h => by
    cases r with
    | var w => simp only [Stmt.movedFirst, List.mem_singleton] at h; subst h; exact .inr (.inl ⟨y, .refl⟩)
    | _ => simp [Stmt.movedFirst] at h
  | .unpair y a b k, h => by
    simp only [Stmt.movedFirst, List.mem_singleton] at h; subst h; exact .inr (.inr ⟨a, b, k, .refl⟩)
  | .skip, h | .seq _ _, h | .letv _ _ _, h | .letcall _ _ _ _, h | .ite _ _ _, h | .while _ _, h
  | .push _ _, h | .free _, h | .scope _ _, h | .rbind _ _, h | .frozen _ _, h | .panic, h
  | .letrec _ _ _, h | .catchR _ _ _, h | .callc _ _ _ _ _, h | .scopeD _ _ _, h | .edit _ _ _, h
  | .withLock _ _ _, h | .scopeL _ _ _ _, h | .insert _ _ _, h | .withElem _ _ _ _, h
  | .callcE _ _ _ _ _, h => by simp [Stmt.movedFirst] at h

theorem LetdChain.pureGlue {s t : Stmt} (h : LetdChain s t) (hp : s.pureGlue = true) : t.pureGlue = true := by
  induction h with
  | refl => exact hp
  | letd _ ih => exact ih (by simpa [Stmt.pureGlue] using hp)

/-- A renaming (a call's, `callRen`) keeps the chain. -/
theorem LetdChain.rename {s t : Stmt} (h : LetdChain s t) (ρ : Var → Var) : LetdChain (s.rename ρ) (t.rename ρ) := by
  induction h with
  | refl => exact .refl
  | letd _ ih => exact .letd ih

/-- A hand-over of `y` keeps the type of every other binding (and `y`'s). -/
theorem RhsT.var_ty {Γ Γ1 : Ctx} {F : List Var} {y : Var} {E : Entry} (h : RhsT Γ F (.var y) E Γ1)
    {v : Var} {E0 : Entry} (hv : Γ v = some E0) : ∃ E1, Γ1 v = some E1 ∧ E1.ty = E0.ty := by
  have key : ∀ E', Γ y = some E' →
      ∃ E1, setE (kill .replace false y Γ) y { E' with live := false, dtor := false } v = some E1 ∧
        E1.ty = E0.ty := by
    intro E' hy
    by_cases he : v = y
    · subst he; rw [hv] at hy; cases hy; exact ⟨{ E0 with live := false, dtor := false }, by simp [setE, upd], rfl⟩
    · refine ⟨killE .replace false y E0, by simp [setE, upd, he, kill, hv], ?_⟩
      unfold killE; split <;> rfl
  cases h <;> first | exact ⟨E0, hv, rfl⟩ | exact key _ (by assumption)

/-- Through a chain of hand-overs a binding stays, at its type. -/
theorem LetdChain.typed {P : Prog} {s t : Stmt} (hc : LetdChain s t) :
    ∀ {Γ : Ctx} {F : List Var} {Δ : Ctx} {x : Var} {E : Entry}, StmtT P Γ F s Δ → Γ x = some E →
      ∃ Γ' F' Δ' E', StmtT P Γ' F' t Δ' ∧ Γ' x = some E' ∧ E'.ty = E.ty := by
  induction hc with
  | refl => intro Γ F Δ x E h hx; exact ⟨Γ, F, Δ, E, h, hx, rfl⟩
  | @letd w f y k t _ ih =>
    intro Γ F Δ x E h hx
    generalize hst : Stmt.letd w f (.var y) k = st at h
    induction h generalizing E with
    | letd _ hw _ hr _ _ _ _ _ _ hb _ _ =>
      cases hst
      have hne : x ≠ w := fun he => by rw [he, hw] at hx; cases hx
      obtain ⟨E1, h1, h1t⟩ := RhsT.var_ty hr hx
      obtain ⟨Γ', F', Δ', E', h', hx', ht'⟩ := ih hb (x := x) (E := E1) (by simp [setE, upd, hne, h1])
      exact ⟨Γ', F', Δ', E', h', hx', ht'.trans h1t⟩
    | @sub Γa Γ0 _ _ _ _ hw _ _ ih2 =>
      obtain ⟨hn, hE⟩ := hw.1 x
      cases hg : Γ0 x with
      | none => exact absurd (hn.mpr hg) (by rw [hx]; simp)
      | some E' =>
        obtain ⟨Γ', F', Δ', E'', h', hx', ht'⟩ := ih2 hg hst
        exact ⟨Γ', F', Δ', E'', h', hx', ht'.trans (hE E E' hx hg).ty⟩
    | _ => cases hst

theorem compE_ty (E : Entry) (a : Ty) : (compE E a).ty = a := by cases a <;> rfl

/-- What a typed `unpair`'s body is typed in: `y` a struct `prod a b` (under
    its destructor type if it has one), `x` bound at `a`, and `x ≠ z`. -/
theorem unpair_body {P : Prog} {Γ Δ : Ctx} {F : List Var} {y x z : Var} {s : Stmt}
    (h : StmtT P Γ F (.unpair y x z s) Δ) :
    ∃ (E : Entry) (a b : Ty), Γ y = some E ∧ E.ty.undtor = .prod a b ∧ x ≠ z ∧
      ∃ Γ' F' Δ' Ex, StmtT P Γ' F' s Δ' ∧ Γ' x = some Ex ∧ Ex.ty = a := by
  generalize hst : Stmt.unpair y x z s = st at h
  induction h with
  | unpair _ hy _ _ hty _ _ _ h9 _ _ hb =>
    cases hst
    exact ⟨_, _, _, hy, unpair_undtor hty, h9, _, _, _, _, hb, by simp [setE, upd, h9]; rfl, compE_ty _ _⟩
  | @sub Γa Γ0 _ _ _ _ hw _ _ ih =>
    obtain ⟨E', a, b, hy', hty, hxz, rest⟩ := ih hst
    obtain ⟨hn, hE⟩ := hw.1 y
    cases hg : Γa y with
    | none => rw [hn.mp hg] at hy'; cases hy'
    | some E =>
      have hw' := hE E E' hg hy'
      exact ⟨E, a, b, rfl, by rw [hw'.ty] at hty; exact hty, hxz, rest⟩
  | _ => cases hst

/-- A hand-over of `y` binds a value of `y`'s type (or, `moveUp` / `copyUp`,
    of a closure type over `y`'s). -/
theorem RhsT.var_out_ty {Γ Γ1 : Ctx} {F : List Var} {y : Var} {E : Entry} (h : RhsT Γ F (.var y) E Γ1)
    {Ey : Entry} (hy : Γ y = some Ey) : E.ty = Ey.ty ∨ ∃ ms q, Ey.ty = .fn ms q := by
  cases h <;> simp_all

/-- **A `letd` that a `Vec` is handed to drains it with its elements'
    destructor**: a typed `letd w f (.var x) k` whose `x` is a `vec s` has
    `s = Ty.nest n (.dtor f u)` (`LetdTy`: a `Vec` is bound at its own type,
    a nest around `f`'s destructor type), so `f` is the destructor of the
    queue's elements. -/
theorem letd_vec_nest {P : Prog} {Γ Δ : Ctx} {F : List Var} {w f x : Var} {k : Stmt}
    (h : StmtT P Γ F (.letd w f (.var x) k) Δ) {E0 : Entry} (hx : Γ x = some E0) {s : Ty}
    (hE : E0.ty = .vec s) : ∃ n u, s = Ty.nest n (.dtor f u) := by
  generalize hst : Stmt.letd w f (.var x) k = st at h
  induction h generalizing E0 with
  | @letd _ _ _ _ _ _ _ _ E t _ _ _ _ _ hr _ hlt hstr _ _ _ _ _ _ =>
    cases hst
    rcases RhsT.var_out_ty hr hx with he | ⟨ms, q, hq⟩
    · rw [hE] at he
      rcases hlt with ⟨_, ht | ⟨g, hg⟩⟩ | ⟨n, hτ, ha⟩
      · rw [he] at ht; subst ht; simp [Ty.isStruct] at hstr
      · rw [he] at hg; cases hg
      · rw [he, hτ] at ha; cases ha; exact ⟨n, t, rfl⟩
    · rw [hE] at hq; cases hq
  | @sub Γa Γ0 _ _ _ _ hw _ _ ih =>
    obtain ⟨hn, hEw⟩ := hw.1 x
    cases hg : Γ0 x with
    | none => exact absurd (hn.mpr hg) (by rw [hx]; simp)
    | some E' => exact ih hg (by rw [(hEw E0 E' hx hg).ty]; exact hE) hst
  | _ => cases hst

/-- **Agora #805: a channel's glue drains the queue in index order.**  The
    glue `g` of a channel's state, `prod (vec s) int` with `s` holding a
    destructor value (`GlueOK`, typed: `ProgOK`), takes the struct apart
    (`unpair 0 x z s'`) and hands the queue `x` to a `letd w f` of the chain
    `s'` starts with (`LetdChain`; not to an `assign` nor an `unpair`, which
    the glue's typing refuses), `f` the elements' destructor (`s = Ty.nest n
    (.dtor f u)`: `letd_vec_nest`), and the steps of that hand-over, under any
    renaming `ρ` of the body's variables (a call runs the body renamed,
    `callIn`'s `callRen`), are:

    1. the `unpair`: from a store where the parameter `0` owns the state
       `pair q fl`, `x` owns the queue `q` and `z` the flag;
    2. the `letd`: from a store where `x` owns `q`, `q` moves to `w`, in the
       frame `scopeD w f k`;
    3. that frame's end, with `w` owning a non-empty `Vec`: the drain's step
       and nothing else (no orphan to reap first), element 0 to a `letd` of
       its own (`Step.scopeDDrain`), which binds it, the queue one shorter,
       in a frame `scopeD _ f` of its own.  The frame then stands at its end
       again with the queue one shorter, so iterating this step drops the
       elements in index order, FIFO, as nurlc's last `Channel_drop` drops
       `ChImpl`'s queue; the iteration, and each element's destructor run
       to its end, are not traced here. -/
theorem chanGlue_drains {P : Prog} (hP : ProgOK P) {g : Nat} {s : Ty} (h : GlueOK P g (.prod (.vec s) .int))
    (hs : s.holdsDtor = true) :
    ∃ fn x z s' w f k, P[g]? = some fn ∧ fn.params = [(.sink, .dtor g (.prod (.vec s) .int))] ∧
      fn.body = .unpair 0 x z s' ∧ x ≠ z ∧ x ∈ s'.movedFirst ∧ LetdChain s' (.letd w f (.var x) k) ∧
      (∃ n u, s = Ty.nest n (.dtor f u)) ∧
      ∀ ρ : Var → Var,
      LetdChain (s'.rename ρ) (.letd (ρ w) f (.var (ρ x)) (k.rename ρ)) ∧
      (∀ (m : Mem) (q fl : Val), ρ x ≠ ρ z → m.st (ρ 0) = some ⟨true, some (.pair q fl)⟩ →
        m.st (ρ x) = none → m.st (ρ z) = none →
        Step P m (fn.body.rename ρ)
          (.ok (((m.set (ρ 0) ⟨true, none⟩).set (ρ x) ⟨q.owns, some q⟩).set (ρ z) ⟨fl.owns, some fl⟩)
            (.scope (ρ x) (.scope (ρ z) (s'.rename ρ))))) ∧
      (∀ (m : Mem) (q : Val), m.st (ρ x) = some ⟨true, some q⟩ → m.st (ρ w) = none →
        Step P m (.letd (ρ w) f (.var (ρ x)) (k.rename ρ))
          (.ok ((m.set (ρ x) ⟨true, none⟩).set (ρ w) ⟨true, some q⟩) (.scopeD (ρ w) f (k.rename ρ)))) ∧
      (∀ (m : Mem) (t : Ty) (c d : Nat) (e : Val) (es : List Val),
        m.st (ρ w) = some ⟨true, some (.node t c d (e :: es))⟩ → ¬ Orphan m →
        (∀ r, Step P m (.scopeD (ρ w) f .skip) r ↔
          r = .ok { m with nv := m.nv + 1 } (.scopeD (ρ w) f (.letd m.nv f (.remove (ρ w) (.lit 0)) .skip))) ∧
        ∀ (m2 : Mem) (y : Var), m2.st (ρ w) = some ⟨true, some (.node t c d (e :: es))⟩ → m2.st y = none →
          m2.alloc c = true → m2.alloc d = true →
          Step P m2 (.scopeD (ρ w) f (.letd y f (.remove (ρ w) (.lit 0)) .skip))
            (.ok ((m2.set (ρ w) ⟨true, some (.node t c d es)⟩).set y ⟨e.owns, some e⟩)
              (.scopeD (ρ w) f (.scopeD y f .skip)))) := by
  obtain ⟨fn, x, z, s', hfn, hps, hbody, hpure, hdx, _⟩ := A2.Dtor.glue_takes_apart hP h
  have hmf := (hdx (by simpa [Ty.holdsDtor] using hs)).1
  obtain ⟨Δ, hb, _⟩ := (hP fn (List.mem_of_getElem? hfn)).2.2.2.2.2.2.2.2.2.2.2.2
  rw [hbody] at hb
  obtain ⟨E0, a, b, h0, hty, hxz, Γ', F', Δ', Ex, hb', hx', hxt⟩ := unpair_body hb
  have hE0 : E0.ty = .dtor g (.prod (.vec s) .int) := by
    simp [sigCtx, hps, paramE] at h0
    rw [← h0]
  rw [hE0] at hty
  simp [Ty.undtor] at hty
  obtain ⟨rfl, rfl⟩ := hty
  rcases LetdChain.of_movedFirst hmf with ⟨w, f, k, hc⟩ | ⟨y, hc⟩ | ⟨a', b', k, hc⟩
  · have hnest : ∃ n u, s = Ty.nest n (.dtor f u) := by
      obtain ⟨Γ'', F'', Δ'', E'', hu, hx'', ht''⟩ := LetdChain.typed hc hb' hx'
      exact letd_vec_nest hu hx'' (by rw [ht'', hxt])
    refine ⟨fn, x, z, s', w, f, k, hfn, hps, hbody, hxz, hmf, hc, hnest, fun ρ => ⟨hc.rename ρ,
      fun m q fl hρ h0 hx hz => ?_, fun m q hx hw => Step.letd hw (EvalR.moveOwn hx),
      fun m t c d e es hw hno => ⟨?_, ?_⟩⟩⟩
    · rw [hbody]; exact Step.unpair h0 hx hz hρ
    · obtain ⟨h1, h2⟩ := A2.Dtor.scopeD_end_drains (P := P) (f := f) hw hno
      exact fun r => ⟨h2 r, fun h => h ▸ h1⟩
    · exact fun m2 y hw2 hy hc2 hd2 => A2.Dtor.scopeD_drain_binds hw2 hy hc2 hd2
  · have := LetdChain.pureGlue hc hpure
    simp [Stmt.pureGlue] at this
  · exfalso
    obtain ⟨Γ'', F'', Δ'', E'', hu, hx'', ht''⟩ := LetdChain.typed hc hb' hx'
    obtain ⟨E3, a1, b1, h3, h3t, _⟩ := unpair_body hu
    rw [hx''] at h3; cases h3
    rw [ht'', hxt] at h3t
    simp [Ty.undtor] at h3t

end A3

namespace A3.ChanDtorWitness
open A2
open A2.DtorWitness (DT P prog_ok)

/-- ... at the witness's channel: `glueV`, the glue of `prod (vec DT) int`,
    hands the queue to a `letd` of `dfn` (function 0, `DT`'s destructor:
    the element type is `Ty.dtor 0 T`), whose frame's end, the queue
    non-empty, is one drain step, element 0 to a `letd` frame of `dfn` of its
    own (`A3.chanGlue_drains`); index order is that step taken again on the
    shorter queue. -/
theorem glueV_drains : ∃ fn x z s' w k, P[7]? = some fn ∧ fn.body = .unpair 0 x z s' ∧
    LetdChain s' (.letd w 0 (.var x) k) ∧
    ∀ (m : Mem) (t : Ty) (c d : Nat) (e : Val) (es : List Val),
      m.st w = some ⟨true, some (.node t c d (e :: es))⟩ → ¬ Orphan m →
      ∀ r, Step P m (.scopeD w 0 .skip) r ↔
        r = .ok { m with nv := m.nv + 1 } (.scopeD w 0 (.letd m.nv 0 (.remove w (.lit 0)) .skip)) := by
  obtain ⟨fn, x, z, s', w, f, k, h1, _, h3, _, _, h5, ⟨n, u, hn⟩, h6⟩ :=
    chanGlue_drains (P := P) prog_ok A2.DtorWitness.glueV_glueOK (s := DT) rfl
  have hf : f = 0 := by
    cases n with
    | zero => simp only [Ty.nest_zero, DT] at hn; exact ((Ty.dtor.inj hn).1).symm
    | succ n => simp [DT] at hn
  subst hf
  exact ⟨fn, x, z, s', w, k, h1, h3, h5, fun m t c d e es hw hno => ((h6 id).2.2.2 m t c d e es hw hno).1⟩

end A3.ChanDtorWitness

/-! ### Agora #805: a receive of a destructor value

`mainR` makes the channel as `main` does, sends a destructor value, and
receives it: `chan_recv` hands the head out as an owned `Option DT`
(`sum int DT`), which a `letd` binds under the option's glue `ofnR`
(`A2.DtorWitness.ofnR`, `EnumGlueOK`, at index 12 of the witnesses'
program), whose frame's end calls the glue; the glue moves the payload out
to a `letd` frame of `dfn` (`ofnR_takes_payload`):

```
: a 1  : b 2  :drop q ( vec_new DT )  : c 0  :drop h ( pair q c )
: ch ( locked_new h )  :drop x ( pair a b )  : r ( chan_send ch x )
:drop o ( chan_recv ch )
``` -/

namespace A3.ChanDtorWitness
open A2
open A2.DynCell (NoRootb noRootb_empty)
open A2.DtorWitness (NoDeps T DT GV GVD EP P prog_ok prog_codes drop_ok gvdrop_ok RT RDT rdrop_ok ofnR)

/-- `... : r ( chan_send ch x )  :drop o ( chan_recv ch )` -/
def mainR : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2)) (.letd 2 0 (.new DT)
    (.letv 3 (.expr (.lit 0)) (.letd 4 7 (.pair 2 3)
      (.letv 5 (.lockNew GVD 4) (.letd 6 0 (.pair 0 1) (.letv 7 (.chanSend 5 6)
        (.letd 8 12 (.chanRecv true 5) .skip))))))))

/-- **A receive of a destructor value is typed**: `chan_recv`'s owned
    `Option DT` is bound by `letd` under the option's glue (`RhsT.chanRecv`,
    `LetdTy` at `RDT`). -/
theorem mainR_typed : ∃ Δ, StmtT P (fun _ => none) [] mainR Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  let EN : Entry := ⟨.vec DT, .own, true, [], [], false, false⟩
  have hnew : RhsT K2 [] (.new DT) EN K2 := RhsT.new (by decide)
  let EV : Entry := Entry.arm { EN with ty := .vec DT, held := [] }
  have hEVe : EV = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [EV, EN, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 EV
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEVe]; simp)
  let K4 : Ctx := A2.setE K3 3 intE
  have hK4 : NoRootb K4 := hK3.setE (by simp [intE])
  let K5 : Ctx := A2.setE (kill .replace false 2 K4) 2 { EV with live := false, dtor := false }
  have hK5 : NoRootb K5 := (hK4.kill _ _ _).setE (by rw [hEVe]; simp)
  have h42 : K4 2 = some EV := by simp [K4, K3, A2.setE, upd]
  have hmv : PushArg K4 [] 2 EV EV.ty EV.held K5 :=
    PushArg.move (Γ := K4) (F := []) (y := 2) (E := EV) (t := EV.ty) rfl (by rw [hEVe]) (by simp)
      (hK4.noPin _) (DtorSafe.of_none (fun v E h => (hK4 v E h).2.1) _ _ _)
  have h53 : K5 3 = some intE := by
    simp [K5, K4, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps, Mode.ownSlot]
  let EG0 : Entry := ⟨.prod EV.ty intE.ty, .own, true, [], EV.held ++ [], false, false⟩
  have hgp : RhsT K4 [] (.pair 2 3) EG0 K5 :=
    RhsT.pair (Ey := EV) (Ez := intE) h42 (by rw [hEVe]) hmv h53 rfl PushArg.int
      (by simp [intE, Mode.ownSlot])
  have hEG0 : EG0 = ⟨GV, .own, true, [], [], false, false⟩ := by simp [EG0, hEVe, intE, GV]
  let EGa : Entry := Entry.arm { EG0 with ty := GVD, held := EG0.held }
  have hEGa : EGa = ⟨GVD, .own, true, [], [], false, false⟩ := by
    simp [EGa, hEG0, Entry.arm, GVD, GV, DT, T, Ty.dtorViews, Ty.holdsView]
  let K6 : Ctx := A2.setE K5 4 EGa
  have hK6 : NoRootb K6 := hK5.setE (by rw [hEGa]; simp)
  let K6' : Ctx := A2.setE (kill .replace false 4 K6) 4 { EGa with live := false, dtor := false }
  have hK6' : NoRootb K6' := (hK6.kill _ _ _).setE (by rw [hEGa]; simp)
  have hmv4 : PushArg K6 [] 4 EGa GVD EGa.held K6' :=
    PushArg.move (Γ := K6) (F := []) (y := 4) (E := EGa) (t := GVD) rfl (by rw [hEGa]) (by simp)
      (hK6.noPin _) (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _)
  have hlnew : RhsT K6 [] (.lockNew GVD 4) EC K6' :=
    RhsT.lockNew (by simp [K6, A2.setE]) (by rw [hEGa]) (by rw [hEGa]) (by decide)
      ⟨by simp [GVD, GV, DT, T, Ty.holdsView], by simp [GVD, GV, DT, T, Ty.hasFn]⟩ hmv4
  let K7 : Ctx := A2.setE K6' 5 EC
  have hK7 : NoRootb K7 := hK6'.setE (by simp [EC])
  have hpair : RhsT K7 [] (.pair 0 1) EP K7 :=
    RhsT.pair (Ey := intE) (Ez := intE)
      (by simp [K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps,
        Mode.ownSlot])
      rfl PushArg.int
      (by simp [K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps,
        Mode.ownSlot])
      rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K8 : Ctx := A2.setE K7 6 ED
  have hK8 : NoRootb K8 := hK7.setE (by rw [hEDe]; simp)
  let K8' : Ctx := A2.setE (kill .replace false 6 K8) 6 { ED with live := false, dtor := false }
  have hK8' : NoRootb K8' := (hK8.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmv6 : PushArg K8 [] 6 ED DT ED.held K8' :=
    PushArg.move (Γ := K8) (F := []) (y := 6) (E := ED) (t := DT) rfl (by rw [hEDe]) (by simp)
      (hK8.noPin _) (DtorSafe.of_none (fun v E h => (hK8 v E h).2.1) _ _ _)
  have hsend : RhsT K8 [] (.chanSend 5 6) intE K8' :=
    RhsT.chanSend (Ea := EC) (s := DT)
      (by simp [K8, K7, A2.setE, upd]) rfl chan_of (by simp [K8, A2.setE]) (by rw [hEDe]) (by rw [hEDe])
      hmv6
  let K9 : Ctx := A2.setE K8' 7 intE
  have hK9 : NoRootb K9 := hK8'.setE (by simp [intE])
  -- `:drop o ( chan_recv ch )`: an owned `Option DT`, bound under its glue
  let ER : Entry := ⟨.sum .int DT, .own, true, [], [], false, false⟩
  have hrecv : RhsT K9 [] (.chanRecv true 5) ER K9 :=
    RhsT.chanRecv (E := EC) (s := DT)
      (by simp [K9, K8', K8, K7, A2.setE, upd, A2.kill, killE, hits, EC, Entry.vdeps, Mode.ownSlot]) rfl chan_of
  let EOd : Entry := Entry.arm { ER with ty := RDT, held := [] }
  have hEOd : EOd.mode ≠ .rootb ∧ EOd.dtor = false ∧ EOd.dbind = false := by
    simp [EOd, ER, Entry.arm, RDT, RT, DT, T, Ty.dtorViews, Ty.holdsView]
  have hK10 : NoRootb (A2.setE K9 8 EOd) := hK9.setE hEOd
  have ho := StmtT.letd (P := P) (Γ := K9) (Γ1 := K9) (F := []) (x := 8) (f := 12) (r := .chanRecv true 5)
    (s := .skip) (E := ER) (t := RT) (H := []) (τ := RDT) rfl
    (by simp [K9, K8', K8, K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hrecv rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn rdrop_ok) (HeldUp.refl _ _) StmtT.skip (hK10.endOK _)
  have hr := StmtT.letv (P := P) (x := 7) (r := .chanSend 5 6) (E := intE) (F := []) (Γ := K8) (Γ1 := K8')
    (s := .letd 8 12 (.chanRecv true 5) .skip) rfl
    (by simp [K8, K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp)
    hsend ho ((hK10.exitScope 8).endOK _)
  have hx := StmtT.letd (P := P) (Γ := K7) (Γ1 := K7) (F := []) (x := 6) (f := 0) (r := .pair 0 1)
    (s := .letv 7 (.chanSend 5 6) (.letd 8 12 (.chanRecv true 5) .skip)) (E := EP) (t := T) (H := []) rfl
    (by simp [K7, K6', K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hpair rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hr
    (((hK10.exitScope 8).exitScope 7).endOK _)
  have hc := StmtT.letv (P := P) (x := 5) (r := .lockNew GVD 4) (E := EC) (F := []) (Γ := K6) (Γ1 := K6')
    rfl (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hlnew hx
    ((((hK10.exitScope 8).exitScope 7).exitScope 6).endOK _) (fun _ => rfl)
  have hg := StmtT.letd (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 4) (f := 7) (r := .pair 2 3)
    (s := .letv 5 (.lockNew GVD 4) (.letd 6 0 (.pair 0 1) (.letv 7 (.chanSend 5 6)
      (.letd 8 12 (.chanRecv true 5) .skip))))
    (E := EG0) (t := GV) (H := EG0.held) (τ := GVD) rfl
    (by simp [K4, K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by rw [hEG0])⟩) rfl rfl (letd_fn gvdrop_ok) (HeldUp.refl _ _) hc
    (((((hK10.exitScope 8).exitScope 7).exitScope 6).exitScope 5).endOK _)
  have h3 := StmtT.letv (P := P) (x := 3) (r := .expr (.lit 0)) (E := intE) (F := []) (Γ := K3) (Γ1 := K3)
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hg
    ((((((hK10.exitScope 8).exitScope 7).exitScope 6).exitScope 5).exitScope 4).endOK _)
  have hdv := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .new DT)
    (E := EN) (t := T) (H := []) (τ := .vec DT) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) h3
    (((((((hK10.exitScope 8).exitScope 7).exitScope 6).exitScope 5).exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hdv
    ((((((((hK10.exitScope 8).exitScope 7).exitScope 6).exitScope 5).exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    (((((((((hK10.exitScope 8).exitScope 7).exitScope 6).exitScope 5).exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

theorem mainR_codes : mainR.codesOK P := by
  simp only [mainR, Stmt.codesOK, Rhs.codeOK]
  exact ⟨trivial, trivial, trivial, trivial, trivial, chanNew_codeOK (n := 0) gvdrop_ok drop_ok, trivial,
    trivial, trivial, trivial⟩

theorem mainR_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 9) mainR (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := mainR_typed
  exact memory_safe prog_ok prog_codes ht rfl mainR_codes (by decide) hr

theorem mainR_no_leak {m' : Mem} (hr : Steps P (emptyMem 9) mainR (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := mainR_typed
  exact no_leak_end prog_ok prog_codes ht rfl mainR_codes (by decide) hr

theorem mainR_no_leak_panic {m' : Mem} (hr : Steps P (emptyMem 9) mainR (.panic m')) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := mainR_typed
  exact no_leak_panic prog_ok prog_codes ht rfl mainR_codes (by decide) hr

/-- **The receive hands the head out, owned, to a frame of the option's
    glue**: `chan_recv` on a channel `a` shares whose queue's head is `v`
    answers `inr v`, owned; the `letd` binds it in the frame `scopeD x 12`,
    and that frame's end, the value still in it, calls the glue `ofnR` on it
    (`Step.scopeDEnd`: an option is no node). -/
theorem recv_runs_glue {m m1 : Mem} {x a : Var} {r : Val} {o : Bool} {k : Stmt} (hx : m.st x = none)
    (he : EvalR m (.chanRecv true a) (.ok r o m1)) {o' : Bool} {kc : Nat} {t u : Ty} {c d f : Nat} {v : Val}
    {es : List Val} (ha : m.st a = some ⟨o', some (.lk kc)⟩)
    (hk : m.blk kc = some ⟨t, .lock, some (.pair (.node u c d (v :: es)) (.int f))⟩) :
    r = .inr v ∧ o = true ∧
      Step P m (.letd x 12 (.chanRecv true a) k) (.ok (m1.set x ⟨true, some (.inr v)⟩) (.scopeD x 12 k)) ∧
      ∀ m2 : Mem, m2.st x = some ⟨true, some (.inr v)⟩ →
        Step P m2 (.scopeD x 12 .skip) (.ok { m2 with nv := m2.nv + 1 } (.scope x (.letcall m2.nv 12 [x] .skip))) := by
  have hst := Step.letd (P := P) (f := 12) (s := k) hx he
  cases he with
  | chanRecv hv hk' _ _ _ _ =>
    rw [ha] at hv; cases hv; rw [hk] at hk'; cases hk'
    exact ⟨rfl, rfl, hst, fun m2 h2 => Step.scopeDEnd h2 rfl⟩
  | chanRecvNone hv hk' _ _ => rw [ha] at hv; cases hv; rw [hk] at hk'; cases hk'

/-- **... and the glue moves the payload out to a `letd` frame of `dfn`**
    (under any renaming `ρ`, as a call runs it): with the parameter owning
    `inr v`, `ofnR`'s body takes its second arm, whose `letd` binds `v` in a
    frame `scopeD _ 0` (the `letd`'s frame runs `dfn` at its end and on a
    panic). -/
theorem ofnR_takes_payload (ρ : Var → Var) {m : Mem} {v : Val} (h0 : m.st (ρ 0) = some ⟨true, some (.inr v)⟩)
    (h2 : m.st (ρ 2) = none) :
    Step P m (ofnR.body.rename ρ) (.ok m ((Stmt.letd 2 0 (.taker 0) (.assign 1 (.expr (.lit 0)))).rename ρ)) ∧
      Step P m ((Stmt.letd 2 0 (.taker 0) (.assign 1 (.expr (.lit 0)))).rename ρ)
        (.ok ((m.set (ρ 0) ⟨true, none⟩).set (ρ 2) ⟨v.owns, some v⟩)
          (.scopeD (ρ 2) 0 ((Stmt.assign 1 (.expr (.lit 0))).rename ρ))) :=
  ⟨Step.iteF (Eval.isr h0), Step.letd h2 (EvalR.taker h0)⟩

end A3.ChanDtorWitness

namespace A3
open A2

/-- Agora #805, the receive's witness (`A3.ChanDtorWitness.mainR`): a
    destructor value sent and received, bound under the option's glue: safe,
    race-free and leak-free on every interleaving. -/
theorem chanRecv_claim :
    MemorySafe A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty ChanDtorWitness.mainR 9) ∧
      RaceFree A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty ChanDtorWitness.mainR 9) ∧
      NoLeak A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty ChanDtorWitness.mainR 9) := by
  obtain ⟨Δ, ht⟩ := ChanDtorWitness.mainR_typed
  exact claim _ _ Globs.empty _ Δ 9 A2.DtorWitness.prog_ok A2.DtorWitness.prog_codes
    (fun _ h => by cases h) GlobsOK.empty ht rfl ChanDtorWitness.mainR_codes (by decide)

end A3
