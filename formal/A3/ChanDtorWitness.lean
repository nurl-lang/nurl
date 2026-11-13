import A3.Reap

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
takes it apart and drains the queue (`A2.DtorWitness.glueV_body`'s typing:
the queue to a `letd` at `vec DT`), each element's `dfn` in index order,
as nurlc's last `Channel_drop` drops the queued elements in order on the
dropping thread.  As for the other witnesses, no theorem traces the run.

A `chan_send` to a closed channel does not queue the value: it moves it
into a fresh lock block of the element type that no share names
(`EvalR.chanSendClosed`; `closed_send_parks` proves that much), which the
marking sweep that ends the step is to mark `dead` for the sending thread
to reap, as nurlc's `chan_send` drops the value before it returns.  That
it is marked and reaped is read off the steps (`Mem.sweepD_marks` at a
lock block, whose no-reference premises are not discharged here for the
fresh block), not proved, and no typed witness closes a channel.  The receiver's binding of a `chan_recv` of destructor
values is an `Option D`, which only a `letd` with the option's glue binds
(`letv` refuses a type that holds a destructor value): no witness of a
receive is given here. -/

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
    moved into a lock (`Ty.lkPay`: a destructor type holding no share), and
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
    takes it apart and drains the queue. -/
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
    sweep that ends the step then marks it `dead` when nothing refers to it
    (`Mem.sweepD_marks` at a lock block, as `last_drop_reaps`), for the
    sending thread to reap: the destructor runs on the sender, as nurlc's
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
