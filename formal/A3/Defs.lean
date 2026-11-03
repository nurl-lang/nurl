import A2.Soundness

/-!
  A3 — threads (`A3/DESIGN.md`): the configuration and its steps, what a
  step touches, a race, and the claims — stated over A2's own step.

  Statements only. Each claim is a `Prop` the milestones A3.0–A3.6 prove;
  nothing here is assumed, and nothing is used by A1 or A2.

  This is A3.0's language: A2 plus `spawn`. A function the program marks
  (`spawn f = true`) is called on a new thread. Its parameters are `sink`
  and of types that hold no views, so what moves to the new thread is a
  tree no binding of the spawner can reach any more (Send, as A3.0 has
  it). A3.1's `Arc` is A2's own (`Mem.blk`, `Val.arc`): its blocks are
  shared by every thread, and the configuration's sweep ends every
  thread's step. The other shared blocks (`Locked`, `RwLocked`, `Atomic`,
  channels) are added by A3.2–A3.5.  A3.6's module globals set at start
  are the configuration's (`Cfg.gl`): every thread reads them, no step
  writes them, and the sweep keeps what they reach.
-/

namespace A3
open A2

/-- What one thread has of its own: its bindings, its next fresh variable,
    and what it runs. -/
structure Thread where
  st : Var → Option Slot
  nv : Nat
  s  : Stmt

/-- A configuration: one address space and its fresh addresses, shared by
    every thread, and the threads. -/
structure Cfg where
  alloc : Nat → Bool
  nid   : Nat
  blk   : Nat → Option Blk   -- A3.1: the counted blocks, shared by every thread
  gl    : Nat → Option Val     -- A3.6: the module globals set at start, which every thread reads
  ths   : List Thread

/-- What A2's step runs on for thread `t`: the shared address space, the
    thread's own bindings. -/
def Cfg.view (C : Cfg) (t : Thread) : Mem :=
  { alloc := C.alloc, nid := C.nid, nv := t.nv, st := t.st, blk := C.blk, gl := C.gl }

/-- Thread `i`'s step written back: the address space to the configuration,
    the bindings and the statement to the thread. -/
def Cfg.put (C : Cfg) (i : Nat) (m : Mem) (s : Stmt) : Cfg :=
  { alloc := m.alloc, nid := m.nid, blk := m.blk, gl := m.gl, ths := C.ths.set i ⟨m.st, m.nv, s⟩ }

/-- A3.1: the values the threads' slots hold. -/
def Cfg.vals (C : Cfg) (v : Val) : Prop :=
  ∃ (j : Nat) (t : Thread), C.ths[j]? = some t ∧ ∃ x o, t.st x = some ⟨o, some v⟩

/-- A3.6: the values the module globals hold. -/
def Cfg.globVals (C : Cfg) (v : Val) : Prop := ∃ g, C.gl g = some v

/-- The roots of the configuration's sweep: what the threads' slots hold
    (A3.1), and (A3.6) what the module globals hold, which every thread may
    read for as long as the program runs. -/
def Cfg.roots (C : Cfg) (v : Val) : Prop := C.vals v ∨ C.globVals v

/-- A3.1: the configuration's sweep, which ends every thread's step: the
    blocks nothing reaches from a thread's slot or (A3.6) a global are
    removed and their payloads freed — A2's `Mem.sweep`, from every thread's
    slots at once (the count of a block's shares is over all threads) and
    the globals (which hold a share each until the process exits). -/
noncomputable def Cfg.sweep (C : Cfg) : Cfg :=
  { C with alloc := sweepAlloc C.roots C.blk C.alloc, blk := sweepBlk C.roots C.blk }

/-- A program run from the empty store, on one thread (A2's `emptyMem`). -/
def Cfg.init (s : Stmt) (nv : Nat) : Cfg :=
  { alloc := fun _ => false, nid := 0, blk := fun _ => none, gl := fun _ => none,
    ths := [⟨fun _ => none, nv, s⟩] }

/-- **A3.6: the module globals set at start**, as `main` finds them: the
    store their `make`s left — the blocks they built, the addresses those
    blocks' payloads own, the next fresh address — and each global's share.
    They are given with the start, not run before it: `GlobsOK` asks of them
    what A2's invariant says of the store a typed `make` leaves once its
    result is the global's. -/
structure Globs where
  alloc : Nat → Bool
  nid   : Nat
  blk   : Nat → Option Blk
  gl    : Nat → Option Val

/-- No global: A3.0–A3.5's start. -/
def Globs.empty : Globs := ⟨fun _ => false, 0, fun _ => none, fun _ => none⟩

/-- The store the globals' `make`s left, with no binding. -/
def Globs.mem (G : Globs) (nv : Nat) : Mem := ⟨G.alloc, G.nid, nv, fun _ => none, G.blk, G.gl⟩

/-- A3.6: a program run with its module globals set, on one thread, which
    (as every thread it spawns) reads them through the configuration
    (`Cfg.gl`, `Cfg.view`). -/
def Cfg.start (G : Globs) (s : Stmt) (nv : Nat) : Cfg :=
  { alloc := G.alloc, nid := G.nid, blk := G.blk, gl := G.gl, ths := [⟨fun _ => none, nv, s⟩] }

/-- With no global, the start is A3.0's. -/
theorem Cfg.init_start (s : Stmt) (nv : Nat) : Cfg.init s nv = Cfg.start Globs.empty s nv := rfl

/-- Where a statement takes its next step: `s` is `K` around `r`, through
    the forms A2's step goes into (`seqL`, `scopeIn`, `rbindIn`, `frozenIn`,
    `catchIn`). -/
inductive Redex : Stmt → (Stmt → Stmt) → Stmt → Prop
  | here {s : Stmt} : Redex s id s
  | seq {a b r : Stmt} {K : Stmt → Stmt} : Redex a K r → Redex (.seq a b) (fun y => .seq (K y) b) r
  | scope {x : Var} {s r : Stmt} {K : Stmt → Stmt} :
      Redex s K r → Redex (.scope x s) (fun y => .scope x (K y)) r
  | rbind {p : Var} {s r : Stmt} {K : Stmt → Stmt} :
      Redex s K r → Redex (.rbind p s) (fun y => .rbind p (K y)) r
  | frozen {z : List Var} {s r : Stmt} {K : Stmt → Stmt} :
      Redex s K r → Redex (.frozen z s) (fun y => .frozen z (K y)) r
  | catchR {x : Var} {m0 : Mem} {s r : Stmt} {K : Stmt → Stmt} :
      Redex s K r → Redex (.catchR x m0 s) (fun y => .catchR x m0 (K y)) r
  | scopeD {x : Var} {f : Nat} {s r : Stmt} {K : Stmt → Stmt} :
      Redex s K r → Redex (.scopeD x f s) (fun y => .scopeD x f (K y)) r
  | scopeL {k : Nat} {t : Ty} {x : Var} {s r : Stmt} {K : Stmt → Stmt} :
      Redex s K r → Redex (.scopeL k t x s) (fun y => .scopeL k t x (K y)) r

/-- A spawned function: every parameter is a `sink` of a type that holds no
    views, and it returns an integer. -/
def SpawnOK (P : Prog) (spawn : Nat → Bool) : Prop :=
  ∀ f, spawn f = true → ∃ fn, P[f]? = some fn ∧ fn.resTy = .int ∧
    ∀ pt ∈ fn.params, pt.1 = .sink ∧ pt.2.holdsView = false

/-- A3.1, Send: a share crosses to a new thread when its payload holds no
    views — `SpawnOK`'s question asked of `Ty.arc t`, unchanged.  Every A2
    type `arc t` meets it (`Ty.ok` asks it of the payload) ... -/
theorem arc_spawnOK {t : Ty} (h : (Ty.arc t).ok = true) : (Ty.arc t).holdsView = false := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at h
  exact h.2

/-- ... and so does every share `arc_new` makes: its payload's type holds no
    views (`RhsT.arcNew`), whatever trees it owns. -/
theorem arc_spawnOK_viewFree {t : Ty} (h : t.holdsView = false) : (Ty.arc t).holdsView = false := h

/-- A3.2, Send: a lock share crosses to a new thread when its payload holds
    no views, `SpawnOK`'s question again; every A2 type `lk t` meets it
    (`Ty.ok` asks it of the payload, `RhsT.lockNew` of what moves in). -/
theorem lk_spawnOK {t : Ty} (h : (Ty.lk t).ok = true) : (Ty.lk t).holdsView = false := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at h
  exact h.2

/-- A3.5, Send: a library handle (a cell share) crosses to a new thread as a
    lock share does, `SpawnOK`'s question unchanged; what it may not do is
    leave an owner behind, which the crossing check asks at run time
    (`SendCheck`). -/
theorem cell_spawnOK {t : Ty} (h : (Ty.cell t).ok = true) : (Ty.cell t).holdsView = false := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at h
  exact h.2

/-- A3.5, Sync: no payload several threads reach at once holds a library
    handle: an `Arc`'s (`RhsT.arcNew`'s own premise) and, A3.5's second cut,
    an `RwLocked`'s, which its read guards lend at once (`RhsT.rwRead`).  A
    lock's payload, a cell's state and a channel's element may hold one
    (A3.5's second cut): one thread at a time reaches them, and every value
    going in faces the crossing check (`EvalR.lockNew`, `cellNew`,
    `lockRestore`, `chanSend`, `Release.put`).  So a lock share is Sync
    whatever its payload holds ... -/
theorem lk_sync {t : Ty} : (Ty.lk t).hasCell = false := rfl

/-- ... and a lock's payload faces the Send question only (`Ty.ok`): a
    library handle is a `Locked`'s value (h358, h357: `Locked PNCounter`,
    `RwLocked PNCounter`). -/
theorem lk_cell_ok {t : Ty} (h : (Ty.cell t).ok = true) : (Ty.lk (.cell t)).ok = true := by
  show ((Ty.cell t).ok && !(Ty.cell t).holdsView) = true
  rw [h, cell_spawnOK h]; rfl

/-- ... and so may a cell's state, which is a lock's payload (a handle that
    keeps another handle in its state, A3.5's second cut). -/
theorem cell_cell_ok {t : Ty} (h : (Ty.cell t).ok = true) : (Ty.cell (.cell t)).ok = true := by
  show ((Ty.cell t).ok && !(Ty.cell t).holdsView) = true
  rw [h, cell_spawnOK h]; rfl

/-- ... which `locked_new` takes (a library handle is Send). -/
theorem lockNew_cell {Γ Γ1 : Ctx} {F : List Var} {t : Ty} {y : Var} {Ey : Entry} {D : List Dep}
    (hy : Γ y = some Ey) (hl : Ey.live = true) (hty : Ey.ty = .cell t) (hvf : t.holdsView = false)
    (hfn : t.hasFn = false) (hpa : PushArg Γ F y Ey (.cell t) D Γ1) :
    RhsT Γ F (.lockNew (.cell t) y) ⟨.lk (.cell t), .own, true, [], [], false, false⟩ Γ1 :=
  RhsT.lockNew hy hl hty ⟨hvf, hfn⟩ hpa

/-- ... but an `RwLocked`'s read guard asks the Sync question of its value
    (h357, `rwlocked_of_a_library_handle_on_two_threads`): readers would hold
    the handle at once. -/
theorem rwRead_not_cell {Γ Γ1 : Ctx} {F : List Var} {a : Var} {t : Ty} {E : Entry} {Ea : Entry}
    (ha : Γ a = some Ea) (hty : Ea.ty = .lk (.cell t)) : ¬ RhsT Γ F (.rwRead a) E Γ1 := fun h => by
  cases h with
  | rwRead ha' _ hty' hnc => rw [ha] at ha'; cases ha'; rw [hty] at hty'; cases hty'; cases hnc

/-! ### A3.2's second cut: `locked_take` / `locked_restore` (h267)

h267 (`option_taken_from_locked_stays_in_slot`): an option holding an `Arc`,
taken out of a `Locked` and restored in a loop, was left in the lock's slot
by `locked_take`, and the restore dropped what the slot held, which was the
value handed back.  In the model the take moves the payload out and the
block holds nothing (`EvalR.lockTake`: the runtime's zero bytes and its
`taken` flag), so the restore finds nothing to drop: it moves the value in,
freeing no address (`EvalR.lockRestore`).  The option's `Arc` is kept alive
by the lock's payload while it is in (`Blk.keeps`) and by the taker's slot
while it is out. -/

/-- A take leaves the block holding nothing, the payload handed out as it
    was, and frees nothing. -/
theorem lockTake_empties {m m' : Mem} {a : Var} {v : Val} {o : Bool}
    (h : EvalR m (.lockTake a) (.ok v o m')) :
    m'.alloc = m.alloc ∧ ∃ k t, m.blk k = some ⟨t, .lock, some v⟩ ∧ m'.blk k = some ⟨t, .lock, none⟩ := by
  cases h with
  | @lockTake _ _ k t _ _ hk _ => exact ⟨rfl, k, t, hk, by simp [upd]⟩

/-- ... and a restore, into a block that holds nothing, frees nothing either:
    no address is freed (what `y` owned becomes the payload). -/
theorem lockRestore_frees_nothing {m m' : Mem} {a y : Var} {v : Val} {o : Bool}
    (h : EvalR m (.lockRestore a y) (.ok v o m')) :
    m'.alloc = m.alloc ∧ ∃ k t w, m.blk k = some ⟨t, .lock, none⟩ ∧ m'.blk k = some ⟨t, .lock, some w⟩ := by
  cases h with
  | @lockRestore _ _ _ k t w m1 _ h1 hk =>
    have ha := TakeVal.alloc h1
    exact ⟨ha, k, t, w, by rw [← TakeVal.blk h1]; exact hk, by simp [upd]⟩

/-! ### A3.3's rest: `rw_try_read`, `rw_try_write`, `wguard_get`, `rw_get`

`rw_try_read` and `rw_try_write` answer an option where `rw_read` and the
write check-out would wait (`Rhs.rwTryRead`, `Rhs.rwTryWrite`).  `wguard_get`
is the write scope's `x` lent: A2's borrow, through which the payload's
containers change, as the borrow of an owner does.  `rw_get` is a read scope
whose body hands the payload to `mem_dup` (`DupFn`) and moves the copy out. -/

/-- A3.3: a read guard's entry, `rw_read`'s: an owned `arc` share of the view
    of a lock block of `t`, holding nothing. -/
def guardE (t : Ty) : Entry := ⟨.arc (.prod (.lk t) t), .own, true, [], [], false, false⟩

/-- A3.3: `rw_try_read`'s answer: an owned option of a read guard, holding
    nothing. -/
def tryReadE (t : Ty) : Entry := ⟨.sum .int (.arc (.prod (.lk t) t)), .own, true, [], [], false, false⟩

/-- `rw_try_read`'s `some`, matched by value, is `rw_read`'s guard: what
    `withRead` binds, so its read scope (`rguard_get_path`'s frozen lend,
    ended with the guard) is the same. -/
theorem tryRead_some {Γ : Ctx} {F : List Var} {o : Var} {t : Ty} (ho : Γ o = some (tryReadE t))
    (hoF : o ∉ F) (hpin : NoPin Γ o) (hds : DtorSafe Γ .replace false o) :
    RhsT Γ F (.taker o) (guardE t)
      (setE (kill .replace false o Γ) o { tryReadE t with live := false, dtor := false }) := by
  have h := RhsT.taker (F := F) (a := .int) (b := .arc (.prod (.lk t) t)) ho rfl rfl rfl hoF hpin hds
  have he : compE (tryReadE t) (.arc (.prod (.lk t) t)) = guardE t := by
    simp [compE, ownHeld, tryReadE, guardE]
  rw [he] at h
  exact h

/-- **`rw_try_read`, matched, is typed**: on `none` the other branch, on
    `some` `withRead`'s read scope under the guard moved out of the option
    (`tryRead_some`); the option's scope ends after both. -/
theorem _root_.A2.StmtT.withTryRead {P : Prog} {Γ Δs : Ctx} {F : List Var} {a o g y x : Var} {s e : Stmt}
    {Ea : Entry} {t : Ty} (hs : s.src = true) (he : e.src = true) (ho : Γ o = none) (hoF : o ∉ F)
    (ha : Γ a = some Ea) (hla : Ea.live = true) (hta : Ea.ty = .lk t) (hnc : t.hasCell = false)
    (hg : Γ g = none) (hgo : g ≠ o)
    (hgF : g ∉ F) (hpin : NoPin (setE Γ o (tryReadE t)) o)
    (hds : DtorSafe (setE Γ o (tryReadE t)) .replace false o)
    (hsome : StmtT P (setE (setE (kill .replace false o (setE Γ o (tryReadE t))) o
        { tryReadE t with live := false, dtor := false }) g (guardE t)) F (Stmt.readWith g y x s) Δs)
    (hendg : EndOK Δs g)
    (hnone : StmtT P (setE Γ o (tryReadE t)) F e (exitScope g Δs))
    (hendo : EndOK (exitScope g Δs) o) :
    StmtT P Γ F (Stmt.withTryRead a o g y x s e) (exitScope o (exitScope g Δs)) := by
  have hgo' : (setE Γ o (tryReadE t)) g = none := by simp [setE, upd_ne _ _ hgo, hg]
  refine StmtT.letv (by simp [Stmt.src, Stmt.readWith, hs, he]) ho hoF (RhsT.rwTryRead ha hla hta hnc) ?_ hendo
  refine StmtT.ite he (by simp [Stmt.src, Stmt.readWith, hs]) (ExprT.isl (upd_same _ _ _) rfl rfl) hnone ?_
  exact StmtT.letv (by simp [Stmt.readWith, Stmt.src, hs]) hgo' hgF
    (tryRead_some (upd_same _ _ _) hoF hpin hds) hsome hendg

/-- A3.3: `rw_try_write`'s answer: an owned option of an integer. -/
def tryWriteE : Entry := ⟨.sum .int .int, .own, true, [], [], false, false⟩

/-- **`rw_try_write`, matched, is typed**: on `none` the other branch, on
    `some` A3.2's `withLock`, with its faithfulness premises (the lock `a`, a
    root the body does not name, outlives the body; `x` holds a `t` at its
    end). -/
theorem _root_.A2.StmtT.withTryWrite {P : Prog} {Γ Δ : Ctx} {F : List Var} {a o x : Var} {s e : Stmt}
    {Ea : Entry} {t : Ty} (hs : s.src = true) (he : e.src = true) (ho : Γ o = none) (hoF : o ∉ F)
    (ha : Γ a = some Ea) (hla : Ea.live = true) (hta : Ea.ty = .lk t) (hroot : Ea.mode.isRoot = true)
    (hao : a ≠ o) (hx : Γ x = none) (hxo : x ≠ o) (hxF : x ∉ F) (has : a ∉ s.vars)
    (hb : StmtT P (setE (setE Γ o tryWriteE) x (lockE t)) F s Δ) (hend : EndOK Δ x)
    (hlive : ∃ E, Δ x = some E ∧ E.live = true)
    (hnone : StmtT P (setE Γ o tryWriteE) F e (exitScope x Δ)) (hendo : EndOK (exitScope x Δ) o) :
    StmtT P Γ F (Stmt.withTryWrite a o x s e) (exitScope o (exitScope x Δ)) := by
  refine StmtT.letv (by simp [Stmt.src, hs, he]) ho hoF (RhsT.rwTryWrite ha hla hta) ?_ hendo
  refine StmtT.ite he (by simp [Stmt.src, hs]) (ExprT.isl (upd_same _ _ _) rfl rfl) hnone ?_
  exact StmtT.withLock hs (by simp [setE, upd_ne _ _ hxo, hx]) hxF (by simp [setE, upd_ne _ _ hao, ha])
    hla (Or.inl hta) hb hend hroot has hlive

/-- **`wguard_get`**: in a write scope on a lock of a `Vec` (`withLock a x`,
    `x` the payload checked out: `lockE`), the value lent is a borrow of `x`
    (`: ~ y ( borrow x )`), whose one dependency is `x` itself, an owner —
    not a share, as `rguard_get`'s is (`rguard_get_path`). -/
theorem wguard_get_path {Γ : Ctx} {F : List Var} {x : Var} {u : Ty} (hx : Γ x = some (lockE (.vec u))) :
    RhsT Γ F (.borrow x) ⟨.vec u, .bor, true, [⟨x, .self⟩], [], false, false⟩ Γ := by
  have hl : lockE (.vec u) = ⟨.vec u, .own, true, [], [], false, false⟩ := by simp [lockE]
  rw [hl] at hx
  have h := RhsT.borrow (F := F) hx rfl rfl
  simpa [derive, Mode.isRoot, rootKind] using h

/-- ... so what is done to its containers changes the value: a change of the
    lent `Vec`'s elements (here `vec_truncate`) is typed (`StmtT.editB`), its
    effect on `x` the owner's own, which `x` allows.  A change through a
    read guard's lend is refused, its dependency being a share
    (`ThruOK.noShare`). -/
theorem _root_.A2.StmtT.wguardGet {P : Prog} {Γ : Ctx} {F : List Var} {x y : Var} {u : Ty} {i : Expr}
    (hx : Γ x = some (lockE (.vec u))) (hy : Γ y = some ⟨.vec u, .bor, true, [⟨x, .self⟩], [], false, false⟩)
    (huv : u.holdsView = false) (hyF : y ∉ F) (hxF : x ∉ F) (hi : ExprT Γ i)
    (hds : DtorSafe Γ .drop false x) :
    StmtT P Γ F (.edit true y (.trunc i))
      (setE (killThru (.trunc i) (.vec u) [⟨x, .self⟩] Γ) y ⟨.vec u, .bor, true, [⟨x, .self⟩], [], false, false⟩) := by
  have hl : lockE (.vec u) = ⟨.vec u, .own, true, [], [], false, false⟩ := by simp [lockE]
  rw [hl] at hx
  refine StmtT.editB (t := u) hy rfl rfl rfl huv hyF (EditArg.trunc hi) (fun _ h => by cases h) hy rfl
    (by simp [memDeps, Kind.isName]) ?_
  intro d hd
  simp only [memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  exact ⟨hxF, fun _ h => (by cases h), _, hx, rfl, Or.inl rfl, by simpa [Edit.effAt] using hds, by simp⟩

/-- ... where a read guard's lend refuses every change through it. -/
theorem rguard_no_change {Γ1 : Ctx} {F : List Var} {op : Edit} {tx : Ty} {g : Var} :
    ¬ ThruOK Γ1 F op tx [⟨g, .share⟩] := fun h =>
  h.noShare ⟨g, .share⟩ (by simp [memDeps, Kind.isName]) rfl

/-- **A3.3, `mem_dup` at `t`** (`rw_get`'s copy), as the calculus has it: a
    function of the program that takes a `t` lent (`in`) and hands back a `t`
    of its own: its result borrows from nothing (`lends = []`) and holds
    nothing (`rholds = []`).  A lock's payload holds no view (`Ty.ok (lk t)`),
    so a deep copy of it depends on nothing it was copied from; the program's
    typing checks the function's body against this summary (`ProgOK`). -/
def DupFn (P : Prog) (f : Nat) (t : Ty) : Prop :=
  ∃ fn, P[f]? = some fn ∧ fn.params = [(.inp, t)] ∧ fn.resTy = t ∧ fn.lends = [] ∧ fn.rholds = []

/-- **The copy depends on nothing**: `mem_dup` called on a lend `x` of the
    payload (`rguard_get`'s, which depends on the guard through a share and
    holds nothing) is a call whose result borrows from nothing and holds
    nothing, and which leaves the context as it was.  So `exitScope` of the
    guard leaves the copy (`copy_outlives`). -/
theorem dup_call {P : Prog} {Γ : Ctx} {F : List Var} {f : Nat} {t : Ty} {x : Var} {Ex : Entry}
    (hd : DupFn P f t) (hx : Γ x = some Ex) (hl : Ex.live = true) (ht : Ex.ty = t) (hh : Ex.held = [])
    (hn : ∀ d ∈ Ex.vdeps, d.kind.isName = false) :
    ∃ fn, P[f]? = some fn ∧ CallT P Γ F f [x] ⟨t, resMode fn, true, [], [], false, false⟩ Γ := by
  obtain ⟨fn, hf, hps, hrt, hle, hrh⟩ := hd
  have hargE : argE Γ x = Ex := by simp [argE, hx]
  have hnm : argNames Γ [x] = [] := by
    simp only [argNames, List.flatMap_cons, List.flatMap_nil, List.append_nil, hargE]
    split
    · rfl
    · simp only [nameDeps, List.filter_eq_nil_iff]
      intro d hd; simp [hn d hd]
  have hmut : mutNames Γ [x] = [] := by simp [mutNames, hnm]
  have hheld : heldOfArgs Γ [x] = [] := by
    simp only [heldOfArgs, hnm, List.append_nil, List.flatMap_cons, List.flatMap_nil, hargE, hh]
    split <;> simp [memDeps, roots, allKinds]
  refine ⟨fn, hf, fn, hf, by simp [hps], ?_, ?_, CallDtorSafe.of_inp (by simp [hps]) hmut, ?_, ?_, ?_⟩
  · intro i hi
    simp only [hps, List.length_singleton, Nat.lt_one_iff] at hi
    subst hi
    refine ⟨Ex, by simpa using hx, hl, by simp [hps, paramOK, ht], fun h => (by simp [hps, PMode.moves] at h),
      fun h => (by simp [hps] at h)⟩
  · intro d hd; rw [hmut] at hd; cases hd
  · simp [callRes, hle, hrh, hheld, hrt, ownHeld]
  · funext v
    simp [callPost, hmut, killNames, hps, callPostAux]
  · intro _
    simp only [callR, List.flatMap_cons, List.flatMap_nil, List.append_nil, hargE, hh]
    split <;> simp [memDeps, roots]

/-- ... and a binding that depends on nothing outlives the guard's scope's
    end: `exitScope g` ends only what depends on `g`. -/
theorem copy_outlives {Γ : Ctx} {g z : Var} {E : Entry} (hz : Γ z = some E) (hzg : z ≠ g)
    (hd : E.vdeps = []) : exitScope g Γ z = some E := by
  simp [exitScope, upd_ne _ _ hzg, kill, hz, killE, hits, hd]

/-! ### The lock operations as derived forms: what their scopes leave

The lock and `RwLocked` operations below (`rw_get`, `locked_get`,
`locked_set`, `locked_apply`'s and `wguard_apply`'s result, `locked_await`,
`Mutex`, a lock reached through a field or an element) are spelled with A2's
rules (`A2/Syntax.lean`), and each is typed as one statement here, with every
scope's end.  A variable a derived form binds is fresh: nothing in the context
depends on it (`Unnamed`), so its scope's end changes nothing else. -/

/-- No binding of `Γ` depends on `v` (a fresh variable, about to be bound). -/
def Unnamed (Γ : Ctx) (v : Var) : Prop := ∀ w E, Γ w = some E → ∀ d ∈ E.vdeps, d.root ≠ v

/-- Nothing depends on `v`, so an effect on `v` ends nothing ... -/
theorem Unnamed.kill {Γ : Ctx} {v : Var} (h : Unnamed Γ v) (e : Eff) (hv : Bool) : kill e hv v Γ = Γ := by
  funext w
  cases hw : Γ w with
  | none => simp [A2.kill, hw]
  | some E => simp [A2.kill, hw, killE_nohit (h w E hw)]

/-- ... and `v`'s scope may end. -/
theorem Unnamed.endOK {Γ : Ctx} {v : Var} (h : Unnamed Γ v) : EndOK Γ v := by
  refine ⟨fun p E hp _ d hd _ => h p E hp d hd, fun w E hw _ _ => ?_, fun w E hw _ _ _ d hd _ => h w E hw d hd⟩
  unfold hitsMem
  simp only [Bool.and_eq_false_iff, List.any_eq_false]
  right; intro d hdd hk
  simp only [Bool.and_eq_true, beq_iff_eq] at hk
  exact h w E hw d hdd hk.1.1

theorem Unnamed.setE {Γ : Ctx} {v : Var} (h : Unnamed Γ v) {x : Var} {E : Entry}
    (hE : ∀ d ∈ E.vdeps, d.root ≠ v) : Unnamed (A2.setE Γ x E) v := by
  intro w E' hw
  by_cases hwx : w = x
  · subst hwx; simp only [A2.setE, upd_same, Option.some.injEq] at hw; subst hw; exact hE
  · simp only [A2.setE, upd_ne _ _ hwx] at hw; exact h w E' hw

theorem Unnamed.setE_nil {Γ : Ctx} {v : Var} (h : Unnamed Γ v) {x : Var} {E : Entry}
    (hE : E.vdeps = []) : Unnamed (A2.setE Γ x E) v :=
  h.setE (by simp [hE])

theorem Unnamed.kill' {Γ : Ctx} {v : Var} (h : Unnamed Γ v) (e : Eff) (hv : Bool) (x : Var) :
    Unnamed (A2.kill e hv x Γ) v := by
  intro w E hw
  simp only [A2.kill] at hw
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hw
  rw [killE_vdeps]; exact h w E0 h0

/-- Binding an entry that depends on nothing pins nothing. -/
theorem _root_.A2.NoPin.setE_nil {Γ : Ctx} {x : Var} (h : NoPin Γ x) {v : Var} {E : Entry}
    (hE : E.vdeps = []) : NoPin (A2.setE Γ v E) x := by
  intro p E' hp hm d hd
  by_cases hpv : p = v
  · subst hpv; simp only [A2.setE, upd_same, Option.some.injEq] at hp; subst hp; rw [hE] at hd; cases hd
  · simp only [A2.setE, upd_ne _ _ hpv] at hp; exact h p E' hp hm d hd

/-- A binding that depends on nothing, in mode `mo`: a result handed back once
    the lock is let go. -/
def outE (R : Ty) (mo : Mode) : Entry := ⟨R, mo, true, [], [], false, false⟩

@[simp] theorem outE_vdeps (R : Ty) (mo : Mode) : (outE R mo).vdeps = [] := by
  cases mo <;> rfl

/-- A scope that ends around a result moved out leaves the result, and the
    context as it was. -/
theorem exitScope_out {Γ : Ctx} {v z : Var} {E Ez : Entry} (hv : Γ v = none) (hu : Unnamed Γ v)
    (hvz : v ≠ z) (hEz : ∀ d ∈ Ez.vdeps, d.root ≠ v) (e : Eff) (hb : Bool) :
    exitScope v (A2.setE (A2.kill e hb z (A2.setE Γ v E)) z Ez) = A2.setE (A2.kill e hb z Γ) z Ez := by
  funext w
  by_cases hwv : w = v
  · subst hwv; simp [exitScope, A2.setE, A2.kill, upd_ne _ _ hvz, hv]
  by_cases hwz : w = z
  · subst hwz; simp only [exitScope, A2.setE, A2.kill, upd_ne _ _ hwv, upd_same, Option.map_some]
    exact congrArg some (killE_nohit hEz)
  cases hw : Γ w with
  | none => simp [exitScope, A2.setE, A2.kill, upd_ne _ _ hwv, upd_ne _ _ hwz, hw]
  | some E' =>
    simp only [exitScope, A2.setE, A2.kill, upd_ne _ _ hwv, upd_ne _ _ hwz, hw, Option.map_some]
    rw [killE_nohit (x := v) (by rw [killE_vdeps]; exact hu w E' hw)]

/-- **The result moved out** (`Stmt.callOut`, the tail of `rw_get`,
    `locked_get`, `locked_apply` and `wguard_apply`): a call of `f` on `x`
    whose result depends on nothing, bound to the fresh `c`, and moved to the
    caller's `z` (an owner moves, an integer is copied: `z`'s mode is the
    result's).  The call leaves the context as it was.  After it, `z` holds the
    result, depending on nothing, so it outlives every scope around the call
    but its own, and every other binding is as it was but what borrowed `z`,
    which the assignment ends. -/
theorem _root_.A2.StmtT.callOut {P : Prog} {Γ : Ctx} {F : List Var} {x c z : Var} {f : Nat} {fn : Fn}
    {R : Ty} {Ez : Entry}
    (hcall : CallT P Γ F f [x] (outE R (resMode fn)) Γ)
    (hc : Γ c = none) (hcF : c ∉ F) (huc : Unnamed Γ c)
    (hz : Γ z = some Ez) (hzF : z ∉ F) (hzt : Ez.ty = R) (hzm : Ez.mode = resMode fn)
    (hzd : Ez.dbind = false) (hpin : NoPin Γ z) (hds : DtorSafe Γ .replace false z) :
    StmtT P Γ F (Stmt.callOut x c z f) (A2.setE (A2.kill .replace false z Γ) z (outE R Ez.mode)) := by
  have hzc : z ≠ c := fun h => by rw [h, hc] at hz; cases hz
  have h4c : A2.setE Γ c (outE R (resMode fn)) c = some (outE R (resMode fn)) := upd_same _ _ _
  have h4z : A2.setE Γ c (outE R (resMode fn)) z = some Ez := by simp [A2.setE, upd_ne _ _ hzc, hz]
  have hu4 : Unnamed (A2.setE Γ c (outE R (resMode fn))) c := huc.setE_nil (outE_vdeps _ _)
  have hpin4 : NoPin (A2.setE Γ c (outE R (resMode fn))) z := NoPin.setE_nil hpin (outE_vdeps _ _)
  have key : ∃ Δ4, StmtT P (A2.setE Γ c (outE R (resMode fn))) F (.assign z (.var c)) Δ4 ∧
      Unnamed Δ4 c ∧ exitScope c Δ4 = A2.setE (A2.kill .replace false z Γ) z (outE R Ez.mode) := by
    cases hro : fn.resOwn with
    | true =>
      -- an owned result moves, its binding dead
      have hmo : resMode fn = .own := by simp [resMode, hro]
      rw [hmo] at h4c h4z hu4 hpin4 hzm ⊢
      have hr := RhsT.moveOwn (F := F) h4c rfl rfl hcF hu4.endOK.1 hu4.endOK.2.1
      rw [hu4.kill] at hr
      refine ⟨_, StmtT.assign h4z hzF (Or.inl ⟨hzm, rfl⟩) hr (by simp [outE, hzt])
        (by simp [roots, Entry.vdeps, Mode.ownSlot, outE]) (by simp [A2.setE, upd_ne _ _ hzc, hz]) hpin4
        ((hds.setE_off rfl).setE_off rfl) hzd, ?_, ?_⟩
      · exact ((hu4.setE_nil (by simp [Entry.vdeps, outE, Mode.ownSlot])).kill' _ _ _).setE_nil
          (show (outE R Ez.mode).vdeps = [] from outE_vdeps _ _)
      · funext w
        by_cases hwc : w = c
        · subst hwc; simp [exitScope, A2.setE, A2.kill, upd_ne _ _ (Ne.symm hzc), hc]
        by_cases hwz : w = z
        · subst hwz; simp only [exitScope, A2.setE, A2.kill, upd_ne _ _ hwc, upd_same, Option.map_some]
          exact congrArg some (killE_nil (outE_vdeps R Ez.mode) _ _ _)
        cases hw : Γ w with
        | none => simp [exitScope, A2.setE, A2.kill, upd_ne _ _ hwc, upd_ne _ _ hwz, hw]
        | some E =>
          simp only [exitScope, A2.setE, A2.kill, upd_ne _ _ hwc, upd_ne _ _ hwz, hw, Option.map_some]
          rw [killE_nohit (x := c) (by rw [killE_vdeps]; exact huc w E hw)]
    | false =>
      -- an integer result is copied
      have hmo : resMode fn = .bor := by simp [resMode, hro]
      rw [hmo] at h4c h4z hu4 hpin4 hzm ⊢
      have hr := RhsT.copyBor (F := F) h4c rfl rfl
      refine ⟨_, StmtT.assign h4z hzF (Or.inr (Or.inr ⟨hzm, rfl⟩)) hr (by simp [outE, hzt])
        (by simp [roots, Entry.vdeps, outE, Mode.ownSlot]) (by simp [A2.setE, upd_ne _ _ hzc, hz]) hpin4
        (hds.setE_off rfl) hzd, ?_, ?_⟩
      · exact (hu4.kill' _ _ _).setE_nil (show (outE R Ez.mode).vdeps = [] from outE_vdeps _ _)
      · exact exitScope_out (Ez := outE R Ez.mode) hc huc hzc.symm (by simp) _ _
  obtain ⟨Δ4, h4, hu, heq⟩ := key
  rw [← heq]
  exact StmtT.letcall rfl hc hcF hcall h4 hu.endOK

/-- A3.3: what `arcGet` lends through a read guard: the pair of the lock's
    share and the payload, depending on the guard through a share. -/
def guardGetE (g : Var) (t : Ty) : Entry := ⟨.prod (.lk t) t, .bor, true, [⟨g, .share⟩], [], false, false⟩

theorem guardGet_eq (g : Var) (t : Ty) : getE g (guardE t) (.prod (.lk t) t) = guardGetE g t := by
  simp [getE, guardE, guardGetE, derive, Mode.isRoot, rootKind]

/-- ... and the payload, its second field, lent: it depends on the guard
    alone, through a share (`rguard_get_path`), holding nothing. -/
theorem guardSnd_deps (g y : Var) (t : Ty) :
    ∀ d ∈ (projE y (guardGetE g t) t).vdeps, d.root = g ∧ d.kind = .share := by
  intro d hd
  cases t <;> simp_all [projE, guardGetE, projDeps, Entry.vdeps, Mode.ownSlot, intE]

theorem guardSnd_held (g y : Var) (t : Ty) : (projE y (guardGetE g t) t).held = [] := by
  cases t <;> simp [projE, guardGetE, intE]

theorem guardSnd_ty (g y : Var) (t : Ty) : (projE y (guardGetE g t) t).ty = t := by
  cases t <;> simp [projE, guardGetE, intE]

theorem guardSnd_live (g y : Var) (t : Ty) : (projE y (guardGetE g t) t).live = true := by
  cases t <;> simp [projE, guardGetE, intE]

/-- **`rw_get` is typed, as one statement** (`Stmt.rwGet`), with every scope's
    end: the guard `g` (`rw_read`), what `arcGet` lends through it (`y`), the
    payload `x` lent frozen, the copy (`mem_dup`, a function with `DupFn`'s
    summary, on `x` lent), and the copy moved out to the caller's `z`.  The
    copy's scope, then `x`'s, `y`'s and the guard's end, and each leaves `z`,
    which holds the copy and depends on nothing (`copy_outlives`); every
    other binding is as it was, but what borrowed `z`, which the assignment
    ends.  The payload holds no view and (the read guard's premise, A3.5's
    second cut) no library handle. -/
theorem _root_.A2.StmtT.rwGet {P : Prog} {Γ : Ctx} {F : List Var} {a g y x c z : Var} {f : Nat} {fn : Fn}
    {Ea Ez : Entry} {t : Ty} (hd : DupFn P f t) (hf : P[f]? = some fn)
    (ha : Γ a = some Ea) (hla : Ea.live = true) (hta : Ea.ty = .lk t) (htv : t.holdsView = false)
    (hnc : t.hasCell = false)
    (hg : Γ g = none) (hy : Γ y = none) (hx : Γ x = none) (hc : Γ c = none)
    (hgy : g ≠ y) (hgx : g ≠ x) (hgc : g ≠ c) (hyx : y ≠ x) (hyc : y ≠ c) (hxc : x ≠ c)
    (hgF : g ∉ F) (hyF : y ∉ F) (hxF : x ∉ F) (hcF : c ∉ F)
    (hug : Unnamed Γ g) (huy : Unnamed Γ y) (hux : Unnamed Γ x) (huc : Unnamed Γ c)
    (hz : Γ z = some Ez) (hzF : z ∉ F) (hzt : Ez.ty = t) (hzm : Ez.mode = resMode fn)
    (hzd : Ez.dbind = false) (hpin : NoPin Γ z) (hds : DtorSafe Γ .replace false z) :
    StmtT P Γ F (Stmt.rwGet a g y x c z f) (A2.setE (A2.kill .replace false z Γ) z (outE t Ez.mode)) := by
  have hzg : z ≠ g := fun h => by rw [h, hg] at hz; cases hz
  have hzy : z ≠ y := fun h => by rw [h, hy] at hz; cases hz
  have hzx : z ≠ x := fun h => by rw [h, hx] at hz; cases hz
  let Γ1 := A2.setE Γ g (guardE t)
  let Γ2 := A2.setE Γ1 y (guardGetE g t)
  let Γ3 := A2.setE Γ2 x (projE y (guardGetE g t) t)
  have hfv : (Ty.prod (.lk t) t).holdsView = false := by simp [Ty.holdsView, htv]
  have hff : (Ty.prod (.lk t) t).hasFn = false := by
    cases h : (Ty.prod (.lk t) t).hasFn
    · rfl
    · rw [hasFn_holdsView h] at hfv; cases hfv
  have hgv : ∀ d ∈ (guardGetE g t).vdeps, d.root = g := by simp [guardGetE, Entry.vdeps, Mode.ownSlot]
  have hsv : ∀ d ∈ (projE y (guardGetE g t) t).vdeps, d.root = g := fun d hd' => (guardSnd_deps g y t d hd').1
  have hgE : (guardE t).vdeps = [] := by simp [guardE, Entry.vdeps, Mode.ownSlot]
  -- the copy, moved out
  obtain ⟨fn', hf', hcall⟩ := dup_call (F := F) hd
    (show Γ3 x = some (projE y (guardGetE g t) t) from upd_same _ _ _)
    (guardSnd_live g y t) (guardSnd_ty g y t) (guardSnd_held g y t)
    (fun d hd' => by rw [(guardSnd_deps g y t d hd').2]; rfl)
  rw [hf] at hf'; cases hf'
  have hu3c : Unnamed Γ3 c :=
    ((huc.setE_nil hgE).setE (fun d hd' => by rw [hgv d hd']; exact hgc)).setE
      (fun d hd' => by rw [hsv d hd']; exact hgc)
  have h3z : Γ3 z = some Ez := by
    simp [Γ3, Γ2, Γ1, A2.setE, upd_ne _ _ hzg, upd_ne _ _ hzy, upd_ne _ _ hzx, hz]
  have hpin3 : NoPin Γ3 z := by
    intro p E hp hm d hd'
    simp only [Γ3, Γ2, Γ1, A2.setE, upd_apply] at hp
    split at hp
    · cases hp; cases t <;> simp [projE, guardGetE, intE] at hm
    split at hp
    · cases hp; simp [guardGetE] at hm
    split at hp
    · cases hp; simp [guardE] at hm
    · exact hpin p E hp hm d hd'
  have hds3 : DtorSafe Γ3 .replace false z :=
    ((hds.setE_off rfl).setE_off rfl).setE_off (projE_dtor _ _ _)
  have h4 := StmtT.callOut (z := z) hcall (show Γ3 c = none by
      simp [Γ3, Γ2, Γ1, A2.setE, upd_ne _ _ (Ne.symm hxc), upd_ne _ _ (Ne.symm hyc), upd_ne _ _ (Ne.symm hgc), hc])
    hcF hu3c h3z hzF hzt hzm hzd hpin3 hds3
  -- the payload's scope
  have h2x : Γ2 x = none := by simp [Γ2, Γ1, A2.setE, upd_ne _ _ (Ne.symm hyx), upd_ne _ _ (Ne.symm hgx), hx]
  have hu2x : Unnamed Γ2 x := (hux.setE_nil hgE).setE (fun d hd' => by rw [hgv d hd']; exact hgx)
  have h3 : StmtT P Γ2 F (.letv x (.snd y) (Stmt.callOut x c z f))
      (A2.setE (A2.kill .replace false z Γ2) z (outE t Ez.mode)) := by
    rw [← exitScope_out h2x hu2x hzx.symm (by simp) .replace false]
    refine StmtT.letv rfl h2x hxF (RhsT.snd (show Γ2 y = some (guardGetE g t) from upd_same _ _ _) rfl rfl) h4
      (Unnamed.endOK ?_)
    exact ((hu2x.setE (fun d hd' => by rw [hsv d hd']; exact hgx)).kill' _ _ _).setE_nil (by simp)
  -- the lend's scope
  have h1y : Γ1 y = none := by simp [Γ1, A2.setE, upd_ne _ _ (Ne.symm hgy), hy]
  have hu1y : Unnamed Γ1 y := huy.setE_nil hgE
  have h2 : StmtT P Γ1 F (Stmt.readWith g y x (Stmt.callOut x c z f))
      (A2.setE (A2.kill .replace false z Γ1) z (outE t Ez.mode)) := by
    rw [← exitScope_out h1y hu1y hzy.symm (by simp) .replace false]
    refine StmtT.letv rfl h1y hyF
      (RhsT.arcGet (show Γ1 g = some (guardE t) from upd_same _ _ _) rfl rfl hfv hff) ?_ (Unnamed.endOK ?_)
    · rw [guardGet_eq]; exact h3
    · exact ((hu1y.setE (fun d hd' => by rw [hgv d hd']; exact hgy)).kill' _ _ _).setE_nil (by simp)
  -- the guard's scope
  show StmtT P Γ F (.letv g (.rwRead a) (Stmt.readWith g y x (Stmt.callOut x c z f))) _
  rw [← exitScope_out hg hug hzg.symm (by simp) .replace false]
  exact StmtT.letv rfl hg hgF (RhsT.rwRead ha hla hta hnc) h2
    (Unnamed.endOK (((hug.setE_nil hgE).kill' _ _ _).setE_nil (by simp)))

/-- A binding set to what it holds is as it was. -/
theorem setE_self {Γ : Ctx} {x : Var} {E : Entry} (h : Γ x = some E) : A2.setE Γ x E = Γ := by
  funext w; by_cases hw : w = x
  · subst hw; simp [A2.setE, h]
  · simp [A2.setE, upd_ne _ _ hw]

/-- **`locked_get` is typed** (`Stmt.lockedGet`): the payload checked out to `x`
    (A3.2's `withLock`, with its faithfulness premises: `a` a root the body
    does not name, `x` live at the end), copied by `mem_dup` (`DupFn`, on `x`
    lent), and the copy moved out to the caller's `z` before the lock is let
    go.  The copy depends on nothing, so the lock scope's end leaves it: the
    context after is the one before, `z` holding the copy.  A payload that
    holds a library handle is left out (`t.hasCell = false`), as `rw_get`'s
    read guard leaves it out: the runtime's `locked_get` panics on one (its
    copy is another owner of the state the lock's value holds, which
    `mem_send_check` counts), and a function that takes the payload lent
    cannot copy the handle (a lent cell share is no share, `lendOf`). -/
theorem _root_.A2.StmtT.lockedGet {P : Prog} {Γ : Ctx} {F : List Var} {a x c z : Var} {f : Nat} {fn : Fn}
    {Ea Ez : Entry} {t : Ty} (hd : DupFn P f t) (hf : P[f]? = some fn)
    (ha : Γ a = some Ea) (hla : Ea.live = true) (hta : Ea.ty = .lk t) (hroot : Ea.mode.isRoot = true)
    (_hnc : t.hasCell = false)
    (hx : Γ x = none) (hc : Γ c = none) (hxc : x ≠ c) (hxF : x ∉ F) (hcF : c ∉ F)
    (hux : Unnamed Γ x) (huc : Unnamed Γ c) (haz : a ≠ z)
    (hz : Γ z = some Ez) (hzF : z ∉ F) (hzt : Ez.ty = t) (hzm : Ez.mode = resMode fn)
    (hzd : Ez.dbind = false) (hpin : NoPin Γ z) (hds : DtorSafe Γ .replace false z) :
    StmtT P Γ F (Stmt.lockedGet a x c z f) (A2.setE (A2.kill .replace false z Γ) z (outE t Ez.mode)) := by
  have hzx : z ≠ x := fun h => by rw [h, hx] at hz; cases hz
  have hac : a ≠ c := fun h => by rw [h, hc] at ha; cases ha
  have hax : a ≠ x := fun h => by rw [h, hx] at ha; cases ha
  obtain ⟨fn', hf', hcall⟩ := dup_call (F := F) hd
    (show A2.setE Γ x (lockE t) x = some (lockE t) from upd_same _ _ _)
    (lockE_live t) (lockE_ty t) (lockE_held t) (by simp)
  rw [hf] at hf'; cases hf'
  have h4 := StmtT.callOut (z := z) hcall (by simp [A2.setE, upd_ne _ _ (Ne.symm hxc), hc]) hcF
    (huc.setE_nil (lockE_vdeps t)) (by simp [A2.setE, upd_ne _ _ hzx, hz]) hzF hzt hzm hzd
    (NoPin.setE_nil hpin (lockE_vdeps t)) (hds.setE_off (lockE_dtor t))
  rw [← exitScope_out hx hux hzx.symm (by simp) .replace false]
  refine StmtT.withLock rfl hx hxF ha hla (Or.inl hta) h4 ?_ hroot ?_ ?_
  · exact Unnamed.endOK (((hux.setE_nil (lockE_vdeps t)).kill' _ _ _).setE_nil (by simp))
  · simp [Stmt.callOut, Stmt.vars, Rhs.vars, hax, hac, haz]
  · refine ⟨lockE t, ?_, lockE_live t⟩
    simp [A2.setE, A2.kill, upd_ne _ _ (Ne.symm hzx), killE_nil (lockE_vdeps t)]

/-- A3.2: `locked_apply`'s closure (and `wguard_apply`'s, `rw_apply`'s), as the
    calculus has it: a function of the program that takes the payload `inout`
    and hands back a result that holds no lend of it: it borrows from no
    parameter (`lends = []`) and holds no view of one (`rholds = []`).  The
    result is handed back once the lock is let go, so nothing of the payload
    may be in it; its type holds no view of the payload. -/
def ApplyFn (P : Prog) (f : Nat) (t R : Ty) : Prop :=
  ∃ fn b, P[f]? = some fn ∧ fn.params = [(.inout b, t)] ∧ fn.resTy = R ∧ fn.lends = [] ∧ fn.rholds = []

/-- **The closure called on the payload**: `f`, with `ApplyFn`'s summary, on the
    checked-out `x` (`lockE t`, an owner holding nothing, of a type that holds
    no view; an owning type, as an `inout` argument's is), is a call whose
    result depends on nothing and which leaves the context as it was: `x` is
    changed in place, and holds nothing after. -/
theorem apply_call {P : Prog} {Γ : Ctx} {F : List Var} {f : Nat} {t R : Ty} {x : Var}
    (hd : ApplyFn P f t R) (hx : Γ x = some (lockE t)) (htv : t.holdsView = false)
    (hto : t.owning = true) (hxF : x ∉ F) (hux : Unnamed Γ x) :
    ∃ fn, P[f]? = some fn ∧ CallT P Γ F f [x] (outE R (resMode fn)) Γ := by
  obtain ⟨fn, b, hf, hps, hrt, hle, hrh⟩ := hd
  have hti : t ≠ .int := fun h => by subst h; cases hto
  have hlk : lockE t = ⟨t, .own, true, [], [], false, false⟩ := by simp [lockE, hti]
  have hargE : argE Γ x = lockE t := by simp [argE, hx]
  have hnm : argNames Γ [x] = [] := by
    simp only [argNames, List.flatMap_cons, List.flatMap_nil, List.append_nil, hargE, lockE_vdeps]
    split <;> rfl
  have hmut : mutNames Γ [x] = [] := by simp [mutNames, hnm]
  have hheld : heldOfArgs Γ [x] = [] := by
    simp only [heldOfArgs, hnm, List.append_nil, List.flatMap_cons, List.flatMap_nil, hargE, lockE_held]
    split <;> simp [memDeps, roots, allKinds]
  refine ⟨fn, hf, fn, hf, by simp [hps], ?_, ?_, ⟨fun i hi => ⟨fun hs => ?_, fun b' hb' => ?_⟩, ?_, ?_⟩, ?_, ?_, ?_⟩
  · intro i hi
    simp only [hps, List.length_singleton, Nat.lt_one_iff] at hi
    subst hi
    refine ⟨lockE t, by simpa using hx, lockE_live t, ?_, fun _ => ⟨by simpa using hxF, ?_, ?_, ?_, ?_⟩, ?_⟩
    · simp only [hps, List.getElem_cons_zero, paramOK]
      exact ⟨lockE_ty t, by rw [hlk]; exact Or.inl rfl, hto⟩
    · simp [lockE_vdeps, roots, memDeps]
    · intro h; simp [hps] at h
    · intro _ _ d hd; simp [lockE_vdeps] at hd
    · intro j hj hji; simp only [hps, List.length_singleton] at hj; omega
    · intro _; exact hux.endOK.1
  · intro d hd; rw [hmut] at hd; cases hd
  · simp only [hps, List.length_singleton, Nat.lt_one_iff] at hi; subst hi; simp [hps] at hs
  · simp only [hps, List.length_singleton, Nat.lt_one_iff] at hi; subst hi
    intro v E hv _ _
    unfold hitsMem
    simp only [Bool.and_eq_false_iff, List.any_eq_false]
    right; intro d hdd hk
    simp only [Bool.and_eq_true, beq_iff_eq] at hk
    exact hux v E hv d hdd (by simpa using hk.1.1)
  · intro d hd; rw [hmut] at hd; cases hd
  · intro i hi b' _ Ea hEa
    simp only [hps, List.length_singleton, Nat.lt_one_iff] at hi; subst hi
    simp at hEa; rw [hx] at hEa; cases hEa; exact lockE_dbind t
  · simp [callRes, outE, hle, hrh, hheld, hrt, ownHeld]
  · rw [callPost, hmut, hps]
    simp only [killNames, List.foldr_nil, callPostAux, hargE, htv, Bool.false_eq_true, ↓reduceIte, lockE_held]
    rw [hux.kill]
    have : ({ lockE t with held := [] } : Entry) = lockE t := by rw [hlk]
    rw [this, setE_self hx]
  · intro _
    simp only [callR, List.flatMap_cons, List.flatMap_nil, List.append_nil, hargE, lockE_held]
    split <;> simp [memDeps, roots]

/-- **`locked_apply`'s result is typed** (`Stmt.lockedApply`; `rw_apply`'s too,
    an `RwLocked`'s write scope being a `withLock`): the payload checked out to
    `x` (A3.2's `withLock`, with its faithfulness premises), the closure run on
    it `inout` (`ApplyFn`), and its result moved out to the caller's `z` before
    the lock is let go.  The result holds no lend of the payload, so the lock
    scope's end leaves it: the context after is the one before, `z` holding
    the result, depending on nothing.  (A3.5: a library's change of its state
    with a result, through a cell share an owner holds, is the same form:
    `Entry.lockOf`.) -/
theorem _root_.A2.StmtT.lockedApply {P : Prog} {Γ : Ctx} {F : List Var} {a x c z : Var} {f : Nat} {fn : Fn}
    {Ea Ez : Entry} {t R : Ty} (hd : ApplyFn P f t R) (hf : P[f]? = some fn)
    (ha : Γ a = some Ea) (hla : Ea.live = true) (hta : Ea.lockOf t) (hroot : Ea.mode.isRoot = true)
    (htv : t.holdsView = false) (hto : t.owning = true)
    (hx : Γ x = none) (hc : Γ c = none) (hxc : x ≠ c) (hxF : x ∉ F) (hcF : c ∉ F)
    (hux : Unnamed Γ x) (huc : Unnamed Γ c) (haz : a ≠ z)
    (hz : Γ z = some Ez) (hzF : z ∉ F) (hzt : Ez.ty = R) (hzm : Ez.mode = resMode fn)
    (hzd : Ez.dbind = false) (hpin : NoPin Γ z) (hds : DtorSafe Γ .replace false z) :
    StmtT P Γ F (Stmt.lockedApply a x c z f) (A2.setE (A2.kill .replace false z Γ) z (outE R Ez.mode)) := by
  have hzx : z ≠ x := fun h => by rw [h, hx] at hz; cases hz
  have hac : a ≠ c := fun h => by rw [h, hc] at ha; cases ha
  have hax : a ≠ x := fun h => by rw [h, hx] at ha; cases ha
  obtain ⟨fn', hf', hcall⟩ := apply_call (F := F) hd
    (show A2.setE Γ x (lockE t) x = some (lockE t) from upd_same _ _ _) htv hto hxF
    (hux.setE_nil (lockE_vdeps t))
  rw [hf] at hf'; cases hf'
  have h4 := StmtT.callOut (z := z) hcall (by simp [A2.setE, upd_ne _ _ (Ne.symm hxc), hc]) hcF
    (huc.setE_nil (lockE_vdeps t)) (by simp [A2.setE, upd_ne _ _ hzx, hz]) hzF hzt hzm hzd
    (NoPin.setE_nil hpin (lockE_vdeps t)) (hds.setE_off (lockE_dtor t))
  rw [← exitScope_out hx hux hzx.symm (by simp) .replace false]
  refine StmtT.withLock rfl hx hxF ha hla hta h4 ?_ hroot ?_ ?_
  · exact Unnamed.endOK (((hux.setE_nil (lockE_vdeps t)).kill' _ _ _).setE_nil (by simp))
  · simp [Stmt.callOut, Stmt.vars, Rhs.vars, hax, hac, haz]
  · refine ⟨lockE t, ?_, lockE_live t⟩
    simp [A2.setE, A2.kill, upd_ne _ _ (Ne.symm hzx), killE_nil (lockE_vdeps t)]

/-- **`wguard_apply`'s result is typed**: inside a write scope (`withLock a x`,
    `x` the payload checked out, `lockE t`), the closure run on `x` and its
    result moved out to `z`, a binding outside the scope (`Stmt.callOut`).  `x`
    is as it was, and `z` holds the result, depending on nothing, so the write
    scope's end (the guard's drop) leaves it (`copy_outlives`). -/
theorem _root_.A2.StmtT.wguardApply {P : Prog} {Γ : Ctx} {F : List Var} {x c z : Var} {f : Nat} {fn : Fn}
    {Ez : Entry} {t R : Ty} (hd : ApplyFn P f t R) (hf : P[f]? = some fn)
    (hxE : Γ x = some (lockE t)) (htv : t.holdsView = false) (hto : t.owning = true)
    (hc : Γ c = none) (hxF : x ∉ F) (hcF : c ∉ F) (hux : Unnamed Γ x) (huc : Unnamed Γ c)
    (hz : Γ z = some Ez) (hzF : z ∉ F) (hzt : Ez.ty = R) (hzm : Ez.mode = resMode fn)
    (hzd : Ez.dbind = false) (hpin : NoPin Γ z) (hds : DtorSafe Γ .replace false z) :
    StmtT P Γ F (Stmt.callOut x c z f) (A2.setE (A2.kill .replace false z Γ) z (outE R Ez.mode)) := by
  obtain ⟨fn', hf', hcall⟩ := apply_call (F := F) hd hxE htv hto hxF hux
  rw [hf] at hf'; cases hf'
  exact StmtT.callOut hcall hc hcF huc hz hzF hzt hzm hzd hpin hds

/-- A binding made and then ended, which no other binding names, leaves the
    context as it was. -/
theorem exitScope_setE {Γ : Ctx} {v : Var} {E : Entry} (hv : Γ v = none) (h : Unnamed Γ v) :
    exitScope v (A2.setE Γ v E) = Γ := by
  funext w
  by_cases hwv : w = v
  · subst hwv; simp [exitScope, hv]
  · cases hw : Γ w with
    | none => simp [exitScope, A2.kill, A2.setE, upd_ne _ _ hwv, hw]
    | some E' => simp [exitScope, A2.kill, A2.setE, upd_ne _ _ hwv, hw, killE_nohit (h w E' hw)]

/-- Handing `y` over (`PushArg`) makes no binding name a fresh variable ... -/
theorem _root_.A2.PushArg.unnamed {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (h : PushArg Γ F y Ey t D Γ1) (hy : Γ y = some Ey) {v : Var} (hu : Unnamed Γ v) : Unnamed Γ1 v := by
  cases h with
  | move => exact (hu.kill' _ _ _).setE (hu y Ey hy)
  | int => exact hu
  | slice => exact hu

/-- ... leaves a binding that does not depend on `y` as it was ... -/
theorem _root_.A2.PushArg.keep {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (h : PushArg Γ F y Ey t D Γ1) {w : Var} (hwy : w ≠ y) {Ew : Entry} (hw : Γ w = some Ew)
    (hd : ∀ d ∈ Ew.vdeps, d.root ≠ y) : Γ1 w = some Ew := by
  cases h with
  | move => simp [A2.setE, A2.kill, upd_ne _ _ hwy, hw, killE_nohit hd]
  | int => exact hw
  | slice => exact hw

/-- ... and binds nothing new. -/
theorem _root_.A2.PushArg.none {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (h : PushArg Γ F y Ey t D Γ1) (hy : Γ y = some Ey) {w : Var} (hw : Γ w = none) : Γ1 w = none := by
  have hwy : w ≠ y := fun e => by rw [e, hy] at hw; cases hw
  cases h with
  | move => simp [A2.setE, A2.kill, upd_ne _ _ hwy, hw]
  | int => exact hw
  | slice => exact hw

/-- **`locked_set` is typed** (`Stmt.lockedSet`): `y`'s value is handed over as
    `locked_new` takes it (`PushArg`: an owner moves and its entry dies, an
    integer is copied), into the box `b`; under the lock (A3.2's `withLock`,
    `a` a root the body does not name), the checked-out `x` is replaced by the
    box's value; and both scopes end.  The context after is the hand-over's:
    `locked_set` is typed exactly where `locked_new` of the same value is. -/
theorem _root_.A2.StmtT.lockedSet {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {a b x y : Var} {Ea Ey : Entry}
    {t : Ty} {D : List Dep}
    (ha : Γ a = some Ea) (hla : Ea.live = true) (hta : Ea.lockOf t) (hroot : Ea.mode.isRoot = true)
    (hay : ∀ d ∈ Ea.vdeps, d.root ≠ y)
    (hy : Γ y = some Ey) (hly : Ey.live = true) (hty : Ey.ty = t) (htv : t.holdsView = false ∧ t.hasFn = false)
    (hpush : PushArg Γ F y Ey t D Γ1)
    (hb : Γ b = none) (hx : Γ x = none) (hbx : b ≠ x) (hbF : b ∉ F) (hxF : x ∉ F)
    (hub : Unnamed Γ b) (hux : Unnamed Γ x) :
    StmtT P Γ F (Stmt.lockedSet t a b x y) Γ1 := by
  have hay' : a ≠ y := by
    intro h; subst h; rw [ha] at hy; cases hy
    rcases hta with h | ⟨h, _⟩ <;> rw [hty] at h <;> have := congrArg sizeOf h <;> simp at this
  have hab : a ≠ b := fun h => by rw [h, hb] at ha; cases ha
  have hax : a ≠ x := fun h => by rw [h, hx] at ha; cases ha
  have h1a : Γ1 a = some Ea := hpush.keep hay' ha hay
  have h1b : Γ1 b = none := hpush.none hy hb
  have h1x : Γ1 x = none := hpush.none hy hx
  have hu1b : Unnamed Γ1 b := hpush.unnamed hy hub
  have hu1x : Unnamed Γ1 x := hpush.unnamed hy hux
  let Eb : Entry := ⟨.lk t, .own, true, [], [], false, false⟩
  have hEb : Eb.vdeps = [] := rfl
  let Γb := A2.setE Γ1 b Eb
  have hbx' : Γb x = none := by simp [Γb, A2.setE, upd_ne _ _ (Ne.symm hbx), h1x]
  have hux' : Unnamed Γb x := hu1x.setE_nil hEb
  let Γbx := A2.setE Γb x (lockE t)
  have huxx : Unnamed Γbx x := hux'.setE_nil (lockE_vdeps t)
  -- the replacement, under the lock: the old value dropped, the box's moved in
  have hr : RhsT Γbx F (.lockTake b) (lockE t) Γbx :=
    RhsT.lockTake (show Γbx b = some Eb by simp [Γbx, Γb, A2.setE, upd_ne _ _ hbx]) rfl rfl
  have hmo : ((lockE t).mode = .own ∧ (lockE t).mode = .own) ∨
      ((lockE t).mode = .inout .replace ∧ (lockE t).mode = .own) ∨
      ((lockE t).mode = .bor ∧ (lockE t).mode = .bor) := by
    unfold lockE; split
    · exact Or.inr (Or.inr ⟨rfl, rfl⟩)
    · exact Or.inl ⟨rfl, rfl⟩
  have hasg := StmtT.assign (P := P) (show Γbx x = some (lockE t) from upd_same _ _ _) hxF hmo hr rfl
    (by simp [roots]) (by simp [Γbx, A2.setE]) huxx.endOK.1 huxx.endOK.2.1 (lockE_dbind t)
  have hset : A2.setE (A2.kill .replace false x Γbx) x { lockE t with mode := (lockE t).mode } = Γbx := by
    rw [huxx.kill]
    exact setE_self (upd_same _ _ _)
  rw [hset] at hasg
  -- the lock's scope, then the box's
  have hwl := StmtT.withLock (P := P) (a := a) rfl hbx' hxF (show Γb a = some Ea by
      simp [Γb, A2.setE, upd_ne _ _ hab, h1a]) hla hta hasg huxx.endOK hroot
    (by simp [Stmt.vars, Rhs.vars, hax, hab]) ⟨lockE t, upd_same _ _ _, lockE_live t⟩
  rw [exitScope_setE hbx' hux'] at hwl
  have hlet := StmtT.letv (P := P) (x := b) (s := .withLock a x (.assign x (.lockTake b))) rfl hb hbF
    (RhsT.lockNew hy hly hty htv hpush) hwl ((hu1b.setE_nil hEb).endOK)
  rw [exitScope_setE h1b hu1b] at hlet
  exact hlet

/-- **The check comes first**: a value that fails it (a slot left behind holds
    a share of a cell it holds) makes `locked_set` panic before the lock is
    touched, the store as it was (`locked_new`'s check), as the runtime's
    `mem_send_check` panics before `mutex_lock`. -/
theorem lockedSet_check {P : Prog} {m m1 : Mem} {t : Ty} {a b x y : Var} {v : Val}
    (ht : TakeVal m y v m1) (hfail : ¬ SendCheck [v] m1.st) :
    Step P m (Stmt.lockedSet t a b x y) (.panic m) :=
  Step.letvP (EvalR.lockNewFail ht hfail)

/-- `locked_await`'s answer binding: an owned option of the result, holding
    nothing. -/
def awaitE (R : Ty) : Entry := outE (.sum .int R) .own

/-- **`locked_await` is typed** (`Stmt.lockedAwait`): each round is
    `locked_apply`'s (the closure's answer, an owned option that holds no lend
    of the payload, `ApplyFn`, moved into `q`), so a round leaves the context
    as it found it: `q` an owned option holding nothing, which nothing
    borrows.  That is the loop's invariant, and the context after. -/
theorem _root_.A2.StmtT.lockedAwait {P : Prog} {Γ : Ctx} {F : List Var} {a x c q : Var} {f : Nat} {fn : Fn}
    {Ea : Entry} {t R : Ty} (hd : ApplyFn P f t (.sum .int R)) (hf : P[f]? = some fn)
    (hro : fn.resOwn = true)
    (ha : Γ a = some Ea) (hla : Ea.live = true) (hta : Ea.lockOf t) (hroot : Ea.mode.isRoot = true)
    (htv : t.holdsView = false) (hto : t.owning = true)
    (hx : Γ x = none) (hc : Γ c = none) (hxc : x ≠ c) (hxF : x ∉ F) (hcF : c ∉ F)
    (hux : Unnamed Γ x) (huc : Unnamed Γ c) (haq : a ≠ q)
    (hq : Γ q = some (awaitE R)) (hqF : q ∉ F) (huq : Unnamed Γ q) (hpin : NoPin Γ q) :
    StmtT P Γ F (Stmt.lockedAwait a x c q f) Γ := by
  have hmo : resMode fn = .own := by simp [resMode, hro]
  have hb := StmtT.lockedApply (P := P) (F := F) (c := c) hd hf ha hla hta hroot htv hto hx hc hxc hxF hcF
    hux huc haq hq hqF rfl (by rw [hmo]; rfl) rfl hpin (huq.endOK.2.1)
  rw [huq.kill] at hb
  have hq' : A2.setE Γ q (outE (.sum .int R) (awaitE R).mode) = Γ := setE_self hq
  rw [hq'] at hb
  exact StmtT.while rfl (ExprT.isl hq rfl rfl) hb

/-- The loop ends only on a `some`: its test reads `0` of an option only of an
    `inr`, so what `q` holds then is the result, which `taker` moves out with
    no panic. -/
theorem await_done {m : Mem} {q : Var} (h : Eval m (.isl q) 0) : ∃ o v, m.st q = some ⟨o, some (.inr v)⟩ := by
  cases h with
  | isr h => exact ⟨_, _, h⟩

/-- **Its waiting is `Blocked`**: a round, at its check-out (the loop unrolled,
    `Step.while` and `Step.iteT`), waits while another thread holds the lock
    (its payload out, or a view of it living), and a configuration that waits
    is not stuck. -/
theorem await_blocked {P : Prog} {m : Mem} {a x c q : Var} {f : Nat} {k : Nat} {t : Ty}
    (hk : LockAt m a k) (hout : m.blk k = some ⟨t, .lock, none⟩ ∨ HasView m.blk k) :
    Blocked m (.seq (Stmt.lockedApply a x c q f) (Stmt.lockedAwait a x c q f)) ∧
      ¬ Stuck P m (.seq (Stmt.lockedApply a x c q f) (Stmt.lockedAwait a x c q f)) := by
  have hb : Blocked m (.seq (Stmt.lockedApply a x c q f) (Stmt.lockedAwait a x c q f)) := ⟨k, t, hk, hout⟩
  exact ⟨hb, fun h => h.2.1 hb⟩

/-! #### `Mutex`: a lock of an integer, guarding nothing in memory

A `Mutex` is a lock block of an integer (`Rhs.mutexNew`, `Stmt.mutexLock`,
`Stmt.mutexUnlock`, `Stmt.mutexWith`).  Its rules hand the thread that takes
it an integer binding and nothing else (`mutex_hands_int`), and its block owns
no address (`mutex_owns_nothing`): no memory fact of the program comes from
a `Mutex`.  The data beside one is typed by its own rules, which refuse a race
on it whatever mutex calls surround it (A3/DESIGN.md, A3.2: h319's rule). -/

/-- What a `Mutex` hands the thread that takes it: an integer binding, which
    depends on nothing and holds nothing ... -/
theorem mutex_hands_int : lockE .int = intE := by simp [lockE]

/-- ... and what its block owns while the integer is in, or out: no address. -/
theorem mutex_owns_nothing {o : Option Val} (ho : o = none ∨ ∃ n, o = some (.int n)) :
    (Blk.mk .int .lock o).tree.ids = [] := by
  rcases ho with rfl | ⟨n, rfl⟩ <;> simp

/-- `mutex_new`: a lock block of an integer, its one share owned, holding
    nothing. -/
theorem _root_.A2.RhsT.mutexNew {Γ : Ctx} {F : List Var} {y : Var} {Ey : Entry}
    (hy : Γ y = some Ey) (hly : Ey.live = true) (hty : Ey.ty = .int) :
    RhsT Γ F (Rhs.mutexNew y) ⟨.lk .int, .own, true, [], [], false, false⟩ Γ :=
  RhsT.lockNew hy hly hty ⟨rfl, rfl⟩ PushArg.int

/-- **`mutex_lock` is typed**: the integer taken out of the lock (`lockTake`),
    an integer binding for what follows; every other `mutex_lock` waits until
    it is put back. -/
theorem _root_.A2.StmtT.mutexLock {P : Prog} {Γ Δ : Ctx} {F : List Var} {u m : Var} {s : Stmt} {Em : Entry}
    (hs : s.src = true) (hm : Γ m = some Em) (hlm : Em.live = true) (htm : Em.ty = .lk .int)
    (hu : Γ u = none) (huF : u ∉ F) (hb : StmtT P (A2.setE Γ u intE) F s Δ) (hend : EndOK Δ u) :
    StmtT P Γ F (Stmt.mutexLock u m s) (exitScope u Δ) := by
  have hr := RhsT.lockTake (F := F) hm hlm htm
  rw [mutex_hands_int] at hr
  exact StmtT.letv hs hu huF hr hb hend

/-- **`mutex_unlock` is typed**: an integer put back (`lockRestore`, the
    integer copied); its answer an integer. -/
theorem _root_.A2.StmtT.mutexUnlock {P : Prog} {Γ Δ : Ctx} {F : List Var} {r m u : Var} {s : Stmt}
    {Em Eu : Entry} (hs : s.src = true) (hm : Γ m = some Em) (hlm : Em.live = true) (htm : Em.ty = .lk .int)
    (hu : Γ u = some Eu) (hlu : Eu.live = true) (htu : Eu.ty = .int)
    (hr : Γ r = none) (hrF : r ∉ F) (hb : StmtT P (A2.setE Γ r intE) F s Δ) (hend : EndOK Δ r) :
    StmtT P Γ F (Stmt.mutexUnlock r m u s) (exitScope r Δ) :=
  StmtT.letv hs hr hrF (RhsT.lockRestore hm hlm htm hu hlu htu PushArg.int) hb hend

/-- **`mutex_with` is typed**: A3.2's `withLock` on the integer lock, with its
    faithfulness premises (the mutex outlives the body: the runtime unlocks it
    after), its body handed an integer binding and nothing else. -/
theorem _root_.A2.StmtT.mutexWith {P : Prog} {Γ Δ : Ctx} {F : List Var} {m x : Var} {s : Stmt} {Em : Entry}
    (hs : s.src = true) (hm : Γ m = some Em) (hlm : Em.live = true) (htm : Em.ty = .lk .int)
    (hroot : Em.mode.isRoot = true) (hms : m ∉ s.vars)
    (hx : Γ x = none) (hxF : x ∉ F) (hb : StmtT P (A2.setE Γ x intE) F s Δ) (hend : EndOK Δ x)
    (hlive : ∃ E, Δ x = some E ∧ E.live = true) :
    StmtT P Γ F (Stmt.mutexWith m x s) (exitScope x Δ) := by
  rw [← mutex_hands_int] at hb
  exact StmtT.withLock hs hx hxF hm hlm (Or.inl htm) hb hend hroot hms hlive

/-! #### A lock reached through a local borrow

A3.2's `withLock` takes a root the body does not name: the lock must outlive
the body, which the runtime runs in the lock's own memory.  A lock reached
through a field or an element of a local owner is a borrow, whose owner the
body could change.  It is handed over first, so that the body runs on an owner
of the share that nothing in it reaches: an element by A2-elem's `withElem`
(`Stmt.withLockElem`), a field by taking the struct apart
(`Stmt.withLockField`).  A lock reached through what the function does not own
(a borrowed parameter's field, an element lent) is handed to a function that
takes it `in`, as the runtime's `locked_update l f` takes `l` (`lock_call`):
inside, a borrowed parameter, the caller's share frozen for the call. -/

/-- The element handed over: an owned lock share, holding what the `Vec` held
    (`popE`). -/
def elemLockE (t : Ty) (Ev : Entry) : Entry := ⟨.lk t, .own, true, [], Ev.held, false, false⟩

/-- **A lock that is an element is typed** (`Stmt.withLockElem`): the element
    `e` handed over is an owner (`popE`), so a root; the body names neither it
    nor the `Vec` `v` (`withElem`'s premise: the element goes back where it
    was), so the lock outlives the body, as `withLock` asks.  The give-back is
    `vec_push v e`'s typing. -/
theorem _root_.A2.StmtT.withLockElem {P : Prog} {Γ Δs Δ : Ctx} {F : List Var} {v e x : Var} {i : Expr}
    {s : Stmt} {Ev : Entry} {t : Ty}
    (hs : s.src = true) (hv : Γ v = some Ev) (hlv : Ev.live = true) (hmv : Ev.mode = .own)
    (htv : Ev.ty = .vec (.lk t)) (hvF : v ∉ F) (hvv : ∀ d ∈ Ev.vdeps, d.root ≠ v) (hi : ExprT Γ i)
    (hpin : NoPin Γ v) (hds : DtorSafe Γ .replace false v)
    (hdd : DtorSafe (A2.kill .replace false v Γ) .drop t.holdsView v)
    (he : Γ e = none) (heF : e ∉ F) (hx : Γ x = none) (hxF : x ∉ F) (hxe : x ≠ e)
    (hb : StmtT P (A2.setE (A2.setE (A2.kill .drop t.holdsView v (A2.kill .replace false v Γ)) e
      (elemLockE t Ev)) x (lockE t)) F s Δs)
    (hend : EndOK Δs x) (hlive : ∃ E, Δs x = some E ∧ E.live = true) (hes : e ∉ s.vars) (hvs : v ∉ s.vars)
    (hvx : v ≠ x) (hve : v ≠ e)
    (hpush : StmtT P (exitScope x Δs) F (.push v e) Δ) (hende : EndOK Δ e) :
    StmtT P Γ F (Stmt.withLockElem v i e x s) (exitScope e Δ) := by
  have hkv : A2.kill .replace false v Γ v = some Ev := by simp [A2.kill, hv, killE_nohit hvv]
  have hpop := RhsT.pop (F := F) (t := .lk t) hkv hlv htv (Or.inl hmv) hvF hdd
  have hpe : popE v Ev (.lk t) = elemLockE t Ev := rfl
  rw [hpe] at hpop
  have hex : A2.setE (A2.kill .drop t.holdsView v (A2.kill .replace false v Γ)) e (elemLockE t Ev) x = none := by
    simp [A2.setE, A2.kill, upd_ne _ _ hxe, hx]
  refine StmtT.withElem (by simp [Stmt.src, hs]) he heF hv hmv hi hpin hds hpop ?_ hpush hende ?_
  · exact StmtT.withLock hs hex hxF (upd_same _ _ _) rfl (Or.inl rfl) hb hend rfl hes hlive
  · simp [Stmt.vars, hvs, hvx, hve]

/-- **A lock that is a field is typed** (`Stmt.withLockField`): the field `l`
    taken out of `y` is an owner (`compE`, holding nothing: a lock share views
    nothing), so a root; the body names neither it nor `y`, so the lock
    outlives the body, as `withLock` asks, and the struct is put back as it
    was.  The reassembly is the assignment's typing. -/
theorem _root_.A2.StmtT.withLockField {P : Prog} {Γ Δs Δ : Ctx} {F : List Var} {y l w x : Var} {s : Stmt}
    {Ey : Entry} {t b : Ty}
    (hs : s.src = true) (hy : Γ y = some Ey) (hly : Ey.live = true) (hcy : canDo Ey.mode .replace)
    (hty : Ey.ty = .prod (.lk t) b) (hyF : y ∉ F) (htv : t.holdsView = false)
    (hl : Γ l = none) (hw : Γ w = none) (hlw : l ≠ w) (hlF : l ∉ F) (hwF : w ∉ F)
    (hx : Γ x = none) (hxF : x ∉ F) (hxl : x ≠ l) (hxw : x ≠ w) (hxy : x ≠ y)
    (hpin : NoPin Γ y) (hds : DtorSafe Γ .replace false y)
    (hb : StmtT P (A2.setE (A2.setE (A2.setE (A2.setE (A2.kill .replace false y Γ) y
        { Ey with live := false, dtor := false }) l (outE (.lk t) .own)) w (compE Ey b)) x (lockE t)) F s Δs)
    (hend : EndOK Δs x) (hlive : ∃ E, Δs x = some E ∧ E.live = true) (hls : l ∉ s.vars) (_hys : y ∉ s.vars)
    (hput : StmtT P (exitScope x Δs) F (.assign y (.pair l w)) Δ)
    (hendw : EndOK Δ w) (hendl : EndOK (exitScope w Δ) l) :
    StmtT P Γ F (Stmt.withLockField y l w x s) (exitScope l (exitScope w Δ)) := by
  have hcl : compE Ey (.lk t) = outE (.lk t) .own := by
    simp [compE, ownHeld, Ty.holdsView, htv, outE]
  refine StmtT.unpair (a := .lk t) (b := b) (by simp [Stmt.src, hs]) hy hly hcy hty hyF hl hw hlw hlF hwF ?_
    hpin hds hendw hendl
  rw [hcl]
  refine StmtT.seq rfl ?_ hput
  refine StmtT.withLock hs (by simp [A2.setE, A2.kill, upd_ne _ _ hxw, upd_ne _ _ hxl, upd_ne _ _ hxy, hx]) hxF
    (show _ = some (outE (.lk t) .own) by simp [A2.setE, upd_ne _ _ hlw]) rfl (Or.inl rfl) hb hend
    rfl hls hlive

/-- A3.2: a function of the program that takes a lock `in` (as the runtime's
    `locked_update l f` takes `l`), and whose result borrows from and holds
    nothing of it. -/
def LockFn (P : Prog) (f : Nat) (t : Ty) : Prop :=
  ∃ fn, P[f]? = some fn ∧ fn.params = [(.inp, .lk t)] ∧ fn.lends = [] ∧ fn.rholds = []

/-- **A lock reached through any borrow is handed to a function that takes it
    `in`**: a field read out of a borrowed struct, an element lent — any live
    binding of the lock share that holds nothing — is the call's `in`
    argument, and the call leaves the context as it was. -/
theorem lock_call {P : Prog} {Γ : Ctx} {F : List Var} {f : Nat} {t : Ty} {x : Var} {Ex : Entry}
    (hd : LockFn P f t) (hx : Γ x = some Ex) (hl : Ex.live = true) (ht : Ex.ty = .lk t) (hh : Ex.held = [])
    (hn : ∀ d ∈ Ex.vdeps, d.kind.isName = false) :
    ∃ fn, P[f]? = some fn ∧ CallT P Γ F f [x] (outE fn.resTy (resMode fn)) Γ := by
  obtain ⟨fn, hf, hps, hle, hrh⟩ := hd
  have hargE : argE Γ x = Ex := by simp [argE, hx]
  have hnm : argNames Γ [x] = [] := by
    simp only [argNames, List.flatMap_cons, List.flatMap_nil, List.append_nil, hargE]
    split
    · rfl
    · simp only [nameDeps, List.filter_eq_nil_iff]
      intro d hd; simp [hn d hd]
  have hmut : mutNames Γ [x] = [] := by simp [mutNames, hnm]
  have hheld : heldOfArgs Γ [x] = [] := by
    simp only [heldOfArgs, hnm, List.append_nil, List.flatMap_cons, List.flatMap_nil, hargE, hh]
    split <;> simp [memDeps, roots, allKinds]
  refine ⟨fn, hf, fn, hf, by simp [hps], ?_, ?_, CallDtorSafe.of_inp (by simp [hps]) hmut, ?_, ?_, ?_⟩
  · intro i hi
    simp only [hps, List.length_singleton, Nat.lt_one_iff] at hi
    subst hi
    refine ⟨Ex, by simpa using hx, hl, by simp [hps, paramOK, ht], fun h => (by simp [hps, PMode.moves] at h),
      fun h => (by simp [hps] at h)⟩
  · intro d hd; rw [hmut] at hd; cases hd
  · simp [callRes, outE, hle, hrh, hheld, ownHeld]
  · funext v
    simp [callPost, hmut, killNames, hps, callPostAux]
  · intro _
    simp only [callR, List.flatMap_cons, List.flatMap_nil, List.append_nil, hargE, hh]
    split <;> simp [memDeps, roots]

/-- ... where, inside, the parameter is a borrowed one (`paramE`'s `rootb`): a
    root, whose share is the caller's, frozen for the call (`callIn`'s
    `frozen`), which A3.2's `withLock` takes. -/
theorem lockFn_param_root {fn : Fn} {t : Ty} (hps : fn.params = [(.inp, .lk t)]) :
    ∃ E, sigCtx fn 0 = some E ∧ E.ty = .lk t ∧ E.live = true ∧ E.mode.isRoot = true :=
  ⟨paramE fn.params (.inp, .lk t), by simp [sigCtx, hps], rfl, rfl, rfl⟩

/-! ### A3.6: module globals, as A2 types them

A global set at start is read at a type that synchronises itself
(`RhsT.glob`, `Ty.sync`), into an owner of a clone of its share; A3.2–A3.4's
rules then take that owner, a root, unchanged. -/

/-- A global is read only at a type that synchronises itself. -/
theorem _root_.A2.RhsT.glob_sync {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {t : Ty} {E : Entry}
    (h : RhsT Γ F (.glob g t) E Γ1) : t.sync = true := by
  cases h with | glob hs _ => exact hs

/-- h263 (`start_global_shared_unsynchronised`): no global is a `Vec`, which
    two threads would push through it with no lock ... -/
theorem glob_not_vec {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {t : Ty} {E : Entry} :
    ¬ RhsT Γ F (.glob g (.vec t)) E Γ1 := fun h => by cases h.glob_sync

/-- ... h272 (`struct_global_torn_between_threads`): nor a struct of plain
    values, more than one word, which no atomic access covers (it is
    `unsafe`-only, trusted base; safe code keeps one in a `Locked`) ... -/
theorem glob_not_prod {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {a b : Ty} {E : Entry} :
    ¬ RhsT Γ F (.glob g (.prod a b)) E Γ1 := fun h => by cases h.glob_sync

/-- ... nor a bare integer: a scalar global is an `Atomic` (`lk int`), read and
    written by atomic steps (`Stmt.loadGlobal`, `Stmt.storeGlobal`) ... -/
theorem glob_not_int {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {E : Entry} :
    ¬ RhsT Γ F (.glob g .int) E Γ1 := fun h => by cases h.glob_sync

/-- ... nor a library handle, which is not Sync (A3.5) ... -/
theorem glob_not_cell {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {t : Ty} {E : Entry} :
    ¬ RhsT Γ F (.glob g (.cell t)) E Γ1 := fun h => by cases h.glob_sync

/-- ... nor (h254, `symtab_shared_between_threads`) an `Arc` of one: a
    `SymTab` shared through an `Arc` reaches two threads, which change it with
    no lock (as `RhsT.arcNew` refuses making one, A3.5). -/
theorem glob_not_arc_cell {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {t : Ty} {E : Entry} :
    ¬ RhsT Γ F (.glob g (.arc (.cell t))) E Γ1 := fun h => by cases h.glob_sync

/-- An update of a `Locked` global (`locked_update g f`) is A3.2's `withLock`,
    unchanged, on the owner `h` of a clone of the global's share: a root that
    the body does not name, holding the share for the whole body. -/
theorem _root_.A2.StmtT.lockGlobal {P : Prog} {Γ Δ : Ctx} {F : List Var} {h x : Var} {g : Nat} {t : Ty}
    {s : Stmt} (hs : s.src = true) (hh : Γ h = none) (hhF : h ∉ F) (hx : Γ x = none) (hxF : x ∉ F)
    (hxh : x ≠ h) (htok : (Ty.lk t).ok = true) (hhs : h ∉ s.vars)
    (hb : StmtT P (setE (setE Γ h ⟨.lk t, .own, true, [], [], false, false⟩) x (lockE t)) F s Δ)
    (hend : EndOK Δ x) (hlive : ∃ E, Δ x = some E ∧ E.live = true) (hendh : EndOK (exitScope x Δ) h) :
    StmtT P Γ F (Stmt.lockGlobal h x g t s) (exitScope h (exitScope x Δ)) :=
  StmtT.letv hs hh hhF (RhsT.glob rfl htok)
    (StmtT.withLock hs (by simp [setE, upd_ne _ _ hxh, hx]) hxF (upd_same _ _ _) rfl (Or.inl rfl) hb hend
      rfl hhs hlive) hendh

/-- A read of a scalar global is an atomic load, A3.4's rule unchanged, on the
    owner `h` of a clone of its share. -/
theorem _root_.A2.StmtT.loadGlobal {P : Prog} {Γ Δ : Ctx} {F : List Var} {h x : Var} {g : Nat} {s : Stmt}
    (hs : s.src = true) (hh : Γ h = none) (hhF : h ∉ F) (hx : Γ x = none) (hxF : x ∉ F) (hxh : x ≠ h)
    (hb : StmtT P (setE (setE Γ h ⟨.lk .int, .own, true, [], [], false, false⟩) x intE) F s Δ)
    (hend : EndOK Δ x) (hendh : EndOK (exitScope x Δ) h) :
    StmtT P Γ F (Stmt.loadGlobal h x g s) (exitScope h (exitScope x Δ)) :=
  StmtT.letv hs hh hhF (RhsT.glob rfl rfl)
    (StmtT.letv hs (by simp [setE, upd_ne _ _ hxh, hx]) hxF
      (RhsT.atomic (upd_same _ _ _) rfl rfl ExprT.lit ExprT.lit) hb hend) hendh

/-- ... and a write an atomic store of an integer expression, which moves no
    owner: safe code hands a scalar global nothing to own (h273, h202). -/
theorem _root_.A2.StmtT.storeGlobal {P : Prog} {Γ Δ : Ctx} {F : List Var} {h x : Var} {g : Nat} {e : Expr}
    {s : Stmt} (hs : s.src = true) (hh : Γ h = none) (hhF : h ∉ F) (hx : Γ x = none) (hxF : x ∉ F)
    (hxh : x ≠ h) (he : ExprT (setE Γ h ⟨.lk .int, .own, true, [], [], false, false⟩) e)
    (hb : StmtT P (setE (setE Γ h ⟨.lk .int, .own, true, [], [], false, false⟩) x intE) F s Δ)
    (hend : EndOK Δ x) (hendh : EndOK (exitScope x Δ) h) :
    StmtT P Γ F (Stmt.storeGlobal h x g e s) (exitScope h (exitScope x Δ)) :=
  StmtT.letv hs hh hhF (RhsT.glob rfl rfl)
    (StmtT.letv hs (by simp [setE, upd_ne _ _ hxh, hx]) hxF
      (RhsT.atomic (upd_same _ _ _) rfl rfl he ExprT.lit) hb hend) hendh

/-- Moving the arguments out of the spawner: each owns its value, and its
    slot is left empty (its drop flag clear). -/
inductive MoveArgs : (Var → Option Slot) → List Var → List Val → (Var → Option Slot) → Prop
  | nil {st : Var → Option Slot} : MoveArgs st [] [] st
  | cons {st st' : Var → Option Slot} {a : Var} {as : List Var} {v : Val} {vs : List Val} :
      st a = some ⟨true, some v⟩ → MoveArgs (upd st a (some ⟨true, none⟩)) as vs st' →
      MoveArgs st (a :: as) (v :: vs) st'

/-- The new thread's bindings: parameter `i` owns the `i`-th value, and the
    result slot is bound, empty. -/
def spawnSt (fn : Fn) (vs : List Val) : Var → Option Slot := fun v =>
  if v = fn.params.length then some ⟨false, none⟩ else (vs[v]?).map fun w => ⟨true, some w⟩

/-- A spawn calls `f` on a new thread. -/
def SpawnRedex (spawn : Nat → Bool) (s : Stmt) : Prop :=
  ∃ K x f args k, Redex s K (.letcall x f args k) ∧ spawn f = true

/-! **A3.5, the crossing check** is A2's `SendCheck` (`A2/Semantics.lean`),
since A3.5's second cut runs it at every lock entry and `chan_send` too: a
spawn asks it of the moved values against the slots the spawner keeps
(`TStep.spawn`), and panics when it fails (`TStep.spawnFail`). -/

/-! ### A3.5b: closures across threads, as A2 types them

A closure's captures are not part of its type, so its type says what its
environment may hold (`Ty.fn ms q`, `Cross`): `pack` gives the class the
captures fit, and the crossing rules ask their questions of the type, as of
any type.  A spawn takes a Send closure (A3.0: a spawned function's
parameters hold no view), an `Arc` a Sync one (A3.1, A3.5: no view, no
closure that holds bindings by name, no library handle), and (A3.5's second
cut) a lock or a channel a Send one too, whose library handles face the
crossing check at every entry (`lockNew_fn`, `chan_fn`). -/

/-- What `pack` makes: a closure of the class its captures fit. -/
theorem _root_.A2.RhsT.pack_fits {Γ Γ1 : Ctx} {F : List Var} {fs : List Nat} {te : Ty} {ms : List Nat}
    {y : Var} {cs : List (Var × PMode × Ty)} {E : Entry} (h : RhsT Γ F (.pack fs te ms y cs) E Γ1) :
    ∃ q, E.ty = .fn ms q ∧ q.Fits te cs := by
  cases h with | pack _ _ _ _ _ hq => exact ⟨_, rfl, hq⟩

/-- h342 (`route_handler_changes_its_capture_on_two_threads`): a closure that
    captures a binding by name, to change it each time it runs (a handler
    pushing to a captured `Vec`), is not Send: `pack` types it `any` ... -/
theorem pack_names_any {Γ Γ1 : Ctx} {F : List Var} {fs : List Nat} {te : Ty} {ms : List Nat}
    {y : Var} {cs : List (Var × PMode × Ty)} {E : Entry} (h : RhsT Γ F (.pack fs te ms y cs) E Γ1)
    (hcs : cs ≠ []) : E.ty = .fn ms .any := by
  obtain ⟨q, hty, hq⟩ := h.pack_fits
  rw [hty]
  cases q with
  | any => rfl
  | _ => exact absurd (hq.send rfl).2.2 hcs

/-- ... which no `Arc` holds (it may change what it captured from every
    thread that reaches it) ... -/
theorem arcNew_not_any {Γ Γ1 : Ctx} {F : List Var} {ms : List Nat} {y : Var} {E : Entry} :
    ¬ RhsT Γ F (.arcNew (.fn ms .any) y) E Γ1 := fun h => by
  cases h with | arcNew _ _ _ hp _ _ => exact absurd hp.1 (by simp [Ty.holdsView])

/-- ... and no spawn takes: a thread's body may run it only on the thread
    that captured the binding.  (A closure's own code is handed its
    environment lent, `Implements`, so what it may change is a binding
    captured by name, never its environment: a Send closure changes nothing
    it captured.) -/
theorem spawn_not_any {P : Prog} {spawn : Nat → Bool} (hS : SpawnOK P spawn) {f : Nat} (hsp : spawn f = true)
    {fn : Fn} (hf : P[f]? = some fn) {pm : PMode} {ms : List Nat} : (pm, Ty.fn ms .any) ∉ fn.params := by
  intro hin
  obtain ⟨fn', hf', _, hpar⟩ := hS f hsp
  rw [hf] at hf'; cases hf'
  have := (hpar _ hin).2
  simp [Ty.holdsView] at this

/-- A closure's code takes its environment where its interface takes the
    receiver, in the interface's mode: the first parameter of the code it
    names is the environment's ... -/
theorem _root_.A2.Implements.env_recv {P : Prog} {f : Nat} {te : Ty} {cs : List (Var × PMode × Ty)}
    {σ : Nat} (h : Implements P f te cs σ) : ∃ fn sig, P[f]? = some fn ∧ P[σ]? = some sig ∧
      fn.params.head? = some (sig.recvMode, te) ∧ ¬ ThruFn P f := by
  obtain ⟨fn, sig, hf, hσ, hps, _, _, _, _, _, _, hnt⟩ := h
  exact ⟨fn, sig, hf, hσ, by rw [hps]; rfl, hnt⟩

/-- ... lent (`inp`) where the interface lends it: the code reads it.  (A2-envhand:
    only an interface that takes it `inout` has code that changes it, called with
    the environment handed over, `StmtT.callcE`.) -/
theorem _root_.A2.Implements.env_lent {P : Prog} {f : Nat} {te : Ty} {cs : List (Var × PMode × Ty)}
    {σ : Nat} (h : Implements P f te cs σ) {sig : Fn} (hσ : P[σ]? = some sig)
    (hr : sig.recvMode = .inp) : ∃ fn, P[f]? = some fn ∧ fn.params.head? = some (.inp, te) ∧
      ¬ ThruFn P f := by
  obtain ⟨fn, sig', hf, hσ', hhd, hnt⟩ := h.env_recv
  rw [hσ] at hσ'; cases hσ'
  exact ⟨fn, hf, by rw [hhd, hr], hnt⟩

/-- h339 (`closure_in_an_arc_captures_a_library_handle`): a closure whose
    environment may hold a library handle (a cell share, A3.5) is not Sync:
    `pack` types it `sync` or `bare` only when its environment's type holds
    none ... -/
theorem pack_sync_noCell {Γ Γ1 : Ctx} {F : List Var} {fs : List Nat} {te : Ty} {ms : List Nat}
    {y : Var} {cs : List (Var × PMode × Ty)} {E : Entry} (h : RhsT Γ F (.pack fs te ms y cs) E Γ1)
    (hc : E.ty.hasCell = false) : te.hasCell = false := by
  obtain ⟨q, hty, hq⟩ := h.pack_fits
  rw [hty] at hc
  exact hq.2.1 hc

/-- ... and an `Arc` holds no other closure: only a Sync or a bare one. -/
theorem arcNew_fn {Γ Γ1 : Ctx} {F : List Var} {ms : List Nat} {q : Cross} {y : Var} {E : Entry}
    (h : RhsT Γ F (.arcNew (.fn ms q) y) E Γ1) : q = .sync ∨ q = .bare := by
  cases h with
  | arcNew _ _ _ _ hc _ => cases q <;> simp_all [Ty.hasCell]

/-- h340 (`closure_sent_on_a_channel_captures_a_kept_handle`): a channel's
    element may hold a library handle (A3.5's second cut), so a closure sent on
    one is any but `any`: Send (`send`, which may capture a handle), Sync or
    bare.  The handle moves with the closure, and the send's crossing check
    panics if an owner of it is left behind (`chanSend_kept`) ... -/
theorem chan_fn {ms : List Nat} {q : Cross} :
    (Ty.lk (.prod (.vec (.fn ms q)) .int)).ok = true ↔ q = .send ∨ q = .sync ∨ q = .bare := by
  cases q <;> simp [Ty.ok, Ty.holdsView]

/-- ... and so is one a lock keeps (A3.2), which one thread at a time runs. -/
theorem lockNew_fn {Γ Γ1 : Ctx} {F : List Var} {ms : List Nat} {q : Cross} {y : Var} {E : Entry}
    (h : RhsT Γ F (.lockNew (.fn ms q) y) E Γ1) : q = .send ∨ q = .sync ∨ q = .bare := by
  cases h with
  | lockNew _ _ _ hp _ => cases q <;> simp_all [Ty.holdsView, Ty.hasFn]

/-- A Send closure, which may capture a library handle, is a lock's value:
    `locked_new` takes it (A3.5's second cut; A3.5b's gap) ... -/
theorem lockNew_send {Γ Γ1 : Ctx} {F : List Var} {ms : List Nat} {y : Var} {Ey : Entry} {D : List Dep}
    (hy : Γ y = some Ey) (hl : Ey.live = true) (hty : Ey.ty = .fn ms .send)
    (hpa : PushArg Γ F y Ey (.fn ms .send) D Γ1) :
    RhsT Γ F (.lockNew (.fn ms .send) y) ⟨.lk (.fn ms .send), .own, true, [], [], false, false⟩ Γ1 :=
  RhsT.lockNew hy hl hty ⟨rfl, rfl⟩ hpa

/-- ... and a channel's element: `chan_send` sends it. -/
theorem chanSend_send {Γ Γ1 : Ctx} {F : List Var} {ms : List Nat} {a y : Var} {Ea Ey : Entry} {D : List Dep}
    (ha : Γ a = some Ea) (hla : Ea.live = true) (htya : Ea.ty = .lk (.prod (.vec (.fn ms .send)) .int))
    (hy : Γ y = some Ey) (hl : Ey.live = true) (hty : Ey.ty = .fn ms .send)
    (hpa : PushArg Γ F y Ey (.fn ms .send) D Γ1) : RhsT Γ F (.chanSend a y) intE Γ1 :=
  RhsT.chanSend ha hla htya hy hl hty hpa

/-- A Send closure that captured a library handle crosses a spawn only with
    every other owner of the handle's state: the crossing check counts what
    the moved values hold, closures' environments included (`Sub.pkg`). -/
theorem sendCheck_env {vs : List Val} {st' : Var → Option Slot} (h : SendCheck vs st') {v : Val}
    (hv : v ∈ vs) {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val} {cs : List (Var × PMode × Ty)}
    (hs : Sub (.pkg fs te ms e cs) v) {k : Nat} (hk : Sub (.cell k) e) :
    ∀ x o w, st' x = some ⟨o, some w⟩ → ¬ Sub (.cell k) w :=
  h k ⟨v, hv, (Sub.pkg hk).trans hs⟩

/-- **A Sync closure in an `Arc`**: `arc_new` takes it (its type holds no
    view, no closure that holds bindings by name and no library handle) ... -/
theorem arcNew_sync {Γ Γ1 : Ctx} {F : List Var} {ms : List Nat} {y : Var} {Ey : Entry} {D : List Dep}
    (hy : Γ y = some Ey) (hl : Ey.live = true) (hty : Ey.ty = .fn ms .sync)
    (hpa : PushArg Γ F y Ey (.fn ms .sync) D Γ1) :
    RhsT Γ F (.arcNew (.fn ms .sync) y) ⟨.arc (.fn ms .sync), .own, true, [], [], false, false⟩ Γ1 :=
  RhsT.arcNew hy hl hty ⟨rfl, rfl⟩ rfl hpa

/-- ... `arc_get` lends it, through a share of the `Arc` (`getE`): a borrow
    every change through which is refused (`ThruOK.noShare`, `canDo`) ... -/
theorem arcGet_sync {Γ : Ctx} {F : List Var} {a : Var} {Ea : Entry} {ms : List Nat}
    (ha : Γ a = some Ea) (hl : Ea.live = true) (hty : Ea.ty = .arc (.fn ms .sync)) :
    RhsT Γ F (.arcGet a) (getE a Ea (.fn ms .sync)) Γ :=
  RhsT.arcGet ha hl hty rfl rfl

/-- ... and a call through what it lends is a call like any other: the
    receiver is handed to the method lent (`inp`), and its code reads its
    environment, lent again (`Implements`), so several threads calling it
    only read the payload (A3.1's argument). -/
theorem _root_.A2.callT_recv {P : Prog} {Γ : Ctx} {F : List Var} {σ : Nat} {sig : Fn} {c : Var}
    {Ec : Entry} (hσ : P[σ]? = some sig) (hps : sig.params = [(.inp, Ec.ty)]) (hc : Γ c = some Ec)
    (hl : Ec.live = true) (hn : ∀ d ∈ Ec.vdeps, d.kind.isName = false) (hnt : ¬ ThruFn P σ) :
    CallT P Γ F σ [c] (callRes Γ sig [c]) (callPost Γ sig [c]) := by
  have hmut : mutNames Γ [c] = [] := by
    have : nameDeps (argE Γ c).vdeps = [] := by
      simp only [nameDeps, argE, hc, Option.getD_some, List.filter_eq_nil_iff]
      intro d hd; simp [hn d hd]
    simp [mutNames, argNames, this]
  refine ⟨sig, hσ, by simp [hps], fun i hi => ?_, fun d hd => ?_, ?_, rfl, rfl, fun h => absurd h hnt⟩
  · have hi' : i = 0 := by rw [hps] at hi; simpa using hi
    subst hi'
    refine ⟨Ec, by simpa using hc, hl, ?_, fun h => ?_, fun h => ?_⟩
    · simp only [hps, List.getElem_cons_zero]; rfl
    · simp [hps, PMode.moves] at h
    · simp only [hps, List.getElem_cons_zero] at h; rcases h with h | h <;> cases h
  · rw [hmut] at hd; cases hd
  · exact CallDtorSafe.of_inp (fun p hp => by rw [hps] at hp; simp at hp; rw [hp]) hmut

/-- An `inp`-only call kills nothing. -/
theorem _root_.A2.callPost_recv {Γ : Ctx} {sig : Fn} {c : Var} {t : Ty} (hps : sig.params = [(.inp, t)])
    (hmut : mutNames Γ [c] = []) : callPost Γ sig [c] = Γ := by
  simp [callPost, hps, callPostAux, hmut, killNames]

/-- **The call through a closure an `Arc` lends** (h342's fix: a handler kept
    in an `Arc`, run by every worker), typed by A2's `callc`, unchanged: the
    borrow `c` (`arc_get`'s, or any) of a closure whose method `j` has the
    interface `σ`, which takes only the receiver. -/
theorem _root_.A2.StmtT.callc_recv {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {k : Stmt}
    {Ec : Entry} {ms : List Nat} {q : Cross} {σ : Nat} {sig : Fn}
    (hks : k.src = true) (hx : Γ x = none) (hxF : x ∉ F) (hc : Γ c = some Ec) (hl : Ec.live = true)
    (hty : Ec.ty = .fn ms q) (hj : ms[j]? = some σ) (hσ : P[σ]? = some sig)
    (hps : sig.params = [(.inp, .fn ms q)]) (hout : ∀ o ∈ sig.outHolds, o.2.1 ≠ 0) (hnt : ¬ ThruFn P σ)
    (hn : ∀ d ∈ Ec.vdeps, d.kind.isName = false)
    (hk : StmtT P (setE Γ x (recvRes c Ec (callRes Γ sig [c]))) F k Δ) (hend : EndOK Δ x) :
    StmtT P Γ F (.callc x c j [] k) (exitScope x Δ) := by
  have hcT := callT_recv (F := F) hσ (by rw [hps, hty]) hc hl hn hnt
  have hmut : mutNames Γ [c] = [] := by
    have : nameDeps (argE Γ c).vdeps = [] := by
      simp only [nameDeps, argE, hc, Option.getD_some, List.filter_eq_nil_iff]
      intro d hd; simp [hn d hd]
    simp [mutNames, argNames, this]
  have hpost := callPost_recv (Γ := Γ) (c := c) hps hmut
  rw [hpost] at hcT
  exact StmtT.callc hks hx hxF hc hty hj hσ (by rw [hps]; rfl) hout hcT (fun _ h => by cases h) hk hend hnt

/-- What `arc_get` lends of an owned share names nothing by name: a call
    through it is `callc_recv`'s. -/
theorem getE_own_noName {a : Var} {t u : Ty} :
    ∀ d ∈ (getE a ⟨.arc u, .own, true, [], [], false, false⟩ t).vdeps, d.kind.isName = false := by
  intro d hd
  cases t <;> simp_all [getE, Entry.vdeps, derive, Mode.isRoot, Mode.ownSlot, rootKind, intE, Kind.isName]

/-- **h342's fix, typed**: a Sync handler kept in an `Arc` (the owner `a` of
    a share), lent by `arc_get` and called by whichever thread holds the
    share: A2's `letv` and `callc`, unchanged. -/
theorem _root_.A2.StmtT.arcCall {P : Prog} {Γ Δ : Ctx} {F : List Var} {a g x : Var} {j : Nat} {k : Stmt}
    {ms : List Nat} {σ : Nat} {sig : Fn}
    (ha : Γ a = some ⟨.arc (.fn ms .sync), .own, true, [], [], false, false⟩) (hks : k.src = true)
    (hg : Γ g = none) (hgF : g ∉ F) (hx : Γ x = none) (hxF : x ∉ F) (hxg : x ≠ g)
    (hj : ms[j]? = some σ) (hσ : P[σ]? = some sig) (hps : sig.params = [(.inp, .fn ms .sync)])
    (hout : ∀ o ∈ sig.outHolds, o.2.1 ≠ 0) (hnt : ¬ ThruFn P σ)
    (hk : StmtT P (setE (setE Γ g (getE a ⟨.arc (.fn ms .sync), .own, true, [], [], false, false⟩ (.fn ms .sync))) x
      (recvRes g (getE a ⟨.arc (.fn ms .sync), .own, true, [], [], false, false⟩ (.fn ms .sync))
        (callRes (setE Γ g (getE a ⟨.arc (.fn ms .sync), .own, true, [], [], false, false⟩ (.fn ms .sync)))
          sig [g]))) F k Δ)
    (hend : EndOK Δ x) (hendg : EndOK (exitScope x Δ) g) :
    StmtT P Γ F (.letv g (.arcGet a) (.callc x g j [] k)) (exitScope g (exitScope x Δ)) :=
  StmtT.letv hks hg hgF (arcGet_sync ha rfl rfl)
    (StmtT.callc_recv hks (by simp [setE, upd_ne _ _ hxg, hx]) hxF (upd_same _ _ _) rfl rfl hj hσ hps hout
      hnt getE_own_noName hk hend) hendg

/-! ### A3.5b: subsumption between closure classes

A closure may be taken at a class above its own, `bare ≤ sync ≤ send ≤ any`
(`Cross.Le`): a move of an owner (`RhsT.moveUp`) or a copy of a borrow
(`RhsT.copyUp`).  The step is the move's or the copy's, and the value is what
it was: its environment fits the class above (`Cross.Fits.mono`), so A2's
invariant holds of it there (`WFv.up`, `ValOK.up`, `ViewsOK.up`, `SharesOK.up`,
`RhsOut.up`).  What changes is only where the closure may go: the crossing
rules read the type it is taken at.  A call through it is A2's `callc` at that
type, so its code is checked against the interface it is called at
(`Implements`, which reads only the interface's other parameters and result,
whatever the class of its receiver). -/

/-- **The class only forgets**: a closure moved or copied keeps its interfaces,
    at its class or one above, never below. -/
theorem _root_.A2.RhsT.var_up {Γ Γ1 : Ctx} {F : List Var} {y : Var} {E Ey : Entry} {ms ms' : List Nat}
    {q q' : Cross} (h : RhsT Γ F (.var y) E Γ1) (hy : Γ y = some Ey) (hty : Ey.ty = .fn ms q)
    (hE : E.ty = .fn ms' q') : ms' = ms ∧ q.Le q' := by
  cases h with
  | moveOwn hy' =>
    rw [hy] at hy'; cases hy'
    rw [hty] at hE; cases hE; exact ⟨rfl, .refl _⟩
  | copyRoot hy' =>
    rw [hy] at hy'; cases hy'
    rw [hty] at hE; cases hE; exact ⟨rfl, .refl _⟩
  | copyBor hy' =>
    rw [hy] at hy'; cases hy'
    have : Ey.ty = .fn ms' q' := hE
    rw [hty] at this; cases this; exact ⟨rfl, .refl _⟩
  | moveUp hy' _ _ _ _ _ hty' hle =>
    rw [hy] at hy'; cases hy'
    rw [hty] at hty'; cases hty'; cases hE; exact ⟨rfl, hle⟩
  | copyUp hy' _ _ hty' hle =>
    rw [hy] at hy'; cases hy'
    rw [hty] at hty'; cases hty'; cases hE; exact ⟨rfl, hle⟩

/-- So a closure `pack` typed `any` (h342's handler, which changes a binding it
    captured by name) is `any` wherever a move or a copy takes it: no `Arc`
    (`arcNew_not_any`), spawn (`spawn_not_any`), lock or channel (`lockNew_fn`,
    `chan_fn`) takes it, however it is passed on. -/
theorem _root_.A2.RhsT.var_any {Γ Γ1 : Ctx} {F : List Var} {y : Var} {E Ey : Entry} {ms : List Nat}
    (h : RhsT Γ F (.var y) E Γ1) (hy : Γ y = some Ey) (hty : Ey.ty = .fn ms .any) : E.ty = .fn ms .any := by
  cases h with
  | moveOwn hy' => rw [hy] at hy'; cases hy'; exact hty
  | copyRoot hy' => rw [hy] at hy'; cases hy'; exact hty
  | copyBor hy' => rw [hy] at hy'; cases hy'; exact hty
  | moveUp hy' _ _ _ _ _ hty' hle =>
    rw [hy] at hy'; cases hy'
    rw [hty] at hty'; cases hty'; rw [hle.any_eq]
  | copyUp hy' _ _ hty' hle =>
    rw [hy] at hy'; cases hy'
    rw [hty] at hty'; cases hty'; show Ty.fn _ _ = _; rw [hle.any_eq]

/-- A Sync handler (or a bare closure) where a Send one is declared: moved as
    `send`, it is a spawn's argument (`SpawnOK`: its type holds no view) ... -/
theorem moveUp_send {Γ : Ctx} {F : List Var} {y : Var} {Ey : Entry} {ms : List Nat} {q : Cross}
    (hy : Γ y = some Ey) (hl : Ey.live = true) (hm : Ey.mode = .own) (hyF : y ∉ F) (hp : NoPin Γ y)
    (hds : DtorSafe Γ .replace false y) (hty : Ey.ty = .fn ms q) (hq : q = .sync ∨ q = .bare) :
    RhsT Γ F (.var y) ⟨.fn ms .send, .own, true, [], Ey.held, false, false⟩
      (setE (kill .replace false y Γ) y { Ey with live := false, dtor := false }) ∧
    (Ty.fn ms .send).holdsView = false :=
  ⟨RhsT.moveUp hy hl hm hyF hp hds hty (by rcases hq with rfl | rfl <;> decide), rfl⟩

/-- ... and any closure may be moved as `any`, where it crosses nothing: the
    class a negative marker (`% NotSend`) gives a value is one subsumption
    reaches, so the marker only removes typings. -/
theorem moveUp_any {Γ : Ctx} {F : List Var} {y : Var} {Ey : Entry} {ms : List Nat} {q : Cross}
    (hy : Γ y = some Ey) (hl : Ey.live = true) (hm : Ey.mode = .own) (hyF : y ∉ F) (hp : NoPin Γ y)
    (hds : DtorSafe Γ .replace false y) (hty : Ey.ty = .fn ms q) :
    RhsT Γ F (.var y) ⟨.fn ms .any, .own, true, [], Ey.held, false, false⟩
      (setE (kill .replace false y Γ) y { Ey with live := false, dtor := false }) :=
  RhsT.moveUp hy hl hm hyF hp hds hty (Cross.le_any q)

/-- **A call through the weaker type**: a borrowed closure of class `q`, copied
    as one of class `q'` above it, is called through an interface declared at
    `q'` — A2's `callc` at the copy's type, so the code is checked against the
    interface it is called at (`Implements`). -/
theorem _root_.A2.StmtT.callcUp {P : Prog} {Γ Δ : Ctx} {F : List Var} {c c' x : Var} {j : Nat}
    {zs : List Var} {k : Stmt} {Ec : Entry} {ms : List Nat} {q q' : Cross}
    (hc : Γ c = some Ec) (hl : Ec.live = true) (hm : Ec.mode = .bor) (hty : Ec.ty = .fn ms q)
    (hle : q.Le q') (hks : k.src = true) (hc' : Γ c' = none) (hc'F : c' ∉ F)
    (hcall : StmtT P (setE Γ c' { Ec with ty := .fn ms q', dtor := false, dbind := false }) F
      (.callc x c' j zs k) Δ) (hend : EndOK Δ c') :
    StmtT P Γ F (.letv c' (.var c) (.callc x c' j zs k)) (exitScope c' Δ) :=
  StmtT.letv hks hc' hc'F (RhsT.copyUp hc hl hm hty hle) hcall hend

/-- **h342's fix through an interface declared at `any`**: the Sync handler an
    `Arc` keeps, lent by `arc_get` (`g`), copied as an `any` closure (`g'`) and
    called through an interface whose receiver is `(inp, fn ms any)`.  The
    handler is Sync in the `Arc`, and the interface need not say so. -/
theorem _root_.A2.StmtT.arcCallUp {P : Prog} {Γ Δ : Ctx} {F : List Var} {a g g' x : Var} {j : Nat}
    {k : Stmt} {ms : List Nat} {q : Cross} {σ : Nat} {sig : Fn}
    (ha : Γ a = some ⟨.arc (.fn ms .sync), .own, true, [], [], false, false⟩) (hks : k.src = true)
    (hg : Γ g = none) (hgF : g ∉ F) (hg' : Γ g' = none) (hg'F : g' ∉ F) (hgg : g' ≠ g)
    (hx : Γ x = none) (hxF : x ∉ F) (hxg : x ≠ g) (hxg' : x ≠ g') (hle : Cross.sync.Le q)
    (hj : ms[j]? = some σ) (hσ : P[σ]? = some sig) (hps : sig.params = [(.inp, .fn ms q)])
    (hout : ∀ o ∈ sig.outHolds, o.2.1 ≠ 0) (hnt : ¬ ThruFn P σ)
    (hk : StmtT P
      (setE (setE (setE Γ g (getE a ⟨.arc (.fn ms .sync), .own, true, [], [], false, false⟩ (.fn ms .sync))) g'
          { getE a ⟨.arc (.fn ms .sync), .own, true, [], [], false, false⟩ (.fn ms .sync) with
            ty := .fn ms q, dtor := false, dbind := false }) x
        (recvRes g' { getE a ⟨.arc (.fn ms .sync), .own, true, [], [], false, false⟩ (.fn ms .sync) with
            ty := .fn ms q, dtor := false, dbind := false }
          (callRes (setE (setE Γ g (getE a ⟨.arc (.fn ms .sync), .own, true, [], [], false, false⟩ (.fn ms .sync)))
            g' { getE a ⟨.arc (.fn ms .sync), .own, true, [], [], false, false⟩ (.fn ms .sync) with
              ty := .fn ms q, dtor := false, dbind := false }) sig [g']))) F k Δ)
    (hend : EndOK Δ x) (hendg' : EndOK (exitScope x Δ) g') (hendg : EndOK (exitScope g' (exitScope x Δ)) g) :
    StmtT P Γ F (.letv g (.arcGet a) (.letv g' (.var g) (.callc x g' j [] k)))
      (exitScope g (exitScope g' (exitScope x Δ))) := by
  refine StmtT.letv hks hg hgF (arcGet_sync ha rfl rfl) ?_ hendg
  refine StmtT.callcUp (upd_same _ _ _) rfl rfl rfl hle hks (by simp [setE, upd_ne _ _ hgg, hg'])
    hg'F ?_ hendg'
  refine StmtT.callc_recv hks (by simp [setE, upd_ne _ _ hxg', upd_ne _ _ hxg, hx]) hxF (upd_same _ _ _) rfl rfl
    hj hσ hps hout hnt ?_ hk hend
  exact getE_own_noName

/-! A3.5b: a closure that changes a capture it moved in (an accumulator).  The
moved-in capture is the environment's own state.  A2's call hands the code that
environment lent, a copy in a fresh slot (`envMem`), and its code changes
nothing through a borrow (`Implements.env_lent`), so the state cannot be
changed in place: an environment's plain value is read only.  What the model
types instead is the state in a share the environment holds, which synchronises
itself: an `Atomic` (or a `Locked`) moved in. -/

/-- The accumulator's environment, an `Atomic` (a lock share of an integer
    block), fits `sync`: a lock share is Sync, so an `Arc` keeps the closure
    and several threads call it ... -/
theorem accum_sync : Cross.sync.Fits (.lk .int) [] :=
  ⟨fun _ => ⟨rfl, rfl⟩, fun _ => rfl, fun h => absurd h (by decide)⟩

/-- ... and its code counts by one atomic step on the environment it is lent
    (any live `lk int`, a borrowed parameter's too): the change synchronises
    itself, where a change of a plain moved-in integer would race (h342's
    shape). -/
theorem accum_count {Γ : Ctx} {F : List Var} {e : Var} {E : Entry} (he : Γ e = some E)
    (hl : E.live = true) (hty : E.ty = .lk .int) : RhsT Γ F (.atomic .add e (.lit 1) (.lit 0)) intE Γ :=
  RhsT.atomic he hl hty .lit .lit

/-! ### A3.5c: trait objects across threads, as A2 types them

A trait object is a package as a closure is (`Ty.fn ms q`, A2): `dyn Trait v`
packs the code of `v`'s impl, `fs`, one function per method, with the box `v`,
of the impl's type `te`, under the trait's methods `ms`, and captures nothing
by name (`Rhs.dyn`).  Its type does not say what the box holds, so the trait
answers for it (docs/MEMORY.md §6.5): A3.5b's class is the trait's declared
bound, `any` with none, `send` for `: Send`, `sync` for `: Send Sync`
(`TraitBound.cross`).  The trait declares its methods' receivers at it
(`TraitAt`), and a call through a trait object types only there
(`StmtT.callc_bound`).  Packing an impl's value is A3.5b's `pack`: its
`Cross.Fits` is the per-impl check, which reads the bound and the impl's type
only (`ImplOK`), and the impl's code fixes that type (`CodeOK.recv_eq`); its
`CodeOK` holds every method's code to its interface, on the box in the
interface's receiver mode (`CodeOK.env_recv`), as a closure's one method is. -/

/-- A3.5c: what a trait declares its objects may cross as: nothing (no bound),
    `: Send`, or `: Send Sync`. -/
inductive TraitBound where
  | none
  | send
  | sendSync
deriving DecidableEq, Repr

/-- The class of a trait object whose trait has the bound `b` (A3.5b's
    `Cross`).  No bound is `bare`: that class (no share at all, a slice's
    element's) is the model's, not a trait's. -/
def TraitBound.cross : TraitBound → Cross
  | .none => .any
  | .send => .send
  | .sendSync => .sync

/-- A3.5c: `dyn Trait v`, a trait object: the impl's code `fs` (method `j`'s
    is `fs[j]`), the box `y` (of the impl's type `te`) moved in, the trait's
    methods `ms`; a box captures nothing by name. -/
def _root_.A2.Rhs.dyn (fs : List Nat) (te : Ty) (ms : List Nat) (y : Var) : Rhs := .pack fs te ms y []

/-- A3.5c: `ms` are the methods of a trait declared with the bound `b`: each
    is an interface, a function of the program, whose receiver is the trait's
    object at the bound, `(inp, fn ms b.cross)` (the receiver `StmtT.callc`
    asks of a call through a `fn ms q` is `(inp, fn ms q)`). -/
def TraitAt (P : Prog) (ms : List Nat) (b : TraitBound) : Prop :=
  ∀ (j σ : Nat), ms[j]? = some σ → ∃ sig : Fn, P[σ]? = some sig ∧
    sig.params.head? = some (.inp, .fn ms b.cross)

/-- What a bound promises of each impl's type `te` (a box captures nothing by
    name, `cs = []`): with no bound, nothing ... -/
theorem TraitBound.fits_none (te : Ty) (cs : List (Var × PMode × Ty)) : TraitBound.none.cross.Fits te cs :=
  Cross.fits_any te cs

/-- ... with `: Send`, that the box holds no view (nothing of the thread that
    made it) and nothing is captured by name ... -/
theorem TraitBound.fits_send {te : Ty} {cs : List (Var × PMode × Ty)} :
    TraitBound.send.cross.Fits te cs ↔ te.holdsView = false ∧ cs = [] :=
  ⟨fun h => h.1 rfl, fun h => ⟨fun _ => h, fun h' => absurd h' (by decide), fun h' => absurd h' (by decide)⟩⟩

/-- ... and with `: Send Sync`, also no library handle (a cell share, A3.5,
    is not Sync). -/
theorem TraitBound.fits_sendSync {te : Ty} {cs : List (Var × PMode × Ty)} :
    TraitBound.sendSync.cross.Fits te cs ↔ (te.holdsView = false ∧ cs = []) ∧ te.hasCell = false :=
  ⟨fun h => ⟨h.1 rfl, h.2.1 rfl⟩, fun h => ⟨fun _ => h.1, fun _ => h.2, fun h' => absurd h' (by decide)⟩⟩

/-- A call through a package asks its receiver to be a package, `fn ms q`,
    whose method `j` is an interface that takes it at `q`. -/
theorem _root_.A2.StmtT.callc_recv_at {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat}
    {zs : List Var} {k : Stmt} {Ec : Entry} (h : StmtT P Γ F (.callc x c j zs k) Δ) (hc : Γ c = some Ec) :
    ∃ ms q σ sig, Ec.ty = .fn ms q ∧ ms[j]? = some σ ∧ P[σ]? = some sig ∧
      sig.params.head? = some (.inp, .fn ms q) := by
  generalize hs : Stmt.callc x c j zs k = s at h
  induction h generalizing Ec with
  | callc _ _ _ hc' hty hj hσ hhd =>
    cases hs
    rw [hc] at hc'; cases hc'
    exact ⟨_, _, _, _, hty, hj, hσ, hhd⟩
  | sub hw _ _ ih =>
    obtain ⟨hn, hwe⟩ := hw.1 c
    obtain ⟨E0, hE0⟩ : ∃ E0, _ = some E0 :=
      Option.ne_none_iff_exists'.mp fun h0 => absurd (hn.mpr h0) (by rw [hc]; simp)
    rw [← (hwe Ec E0 hc hE0).ty]
    exact ih hE0 hs
  | _ => cases hs

/-- **A3.5b's class is the trait's bound**: a call through a trait object of
    a trait declared with the bound `b` types only where the object's class
    is `b.cross`. -/
theorem _root_.A2.StmtT.callc_bound {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat}
    {zs : List Var} {k : Stmt} {Ec : Entry} {ms : List Nat} {q : Cross} {b : TraitBound}
    (h : StmtT P Γ F (.callc x c j zs k) Δ) (hc : Γ c = some Ec) (hty : Ec.ty = .fn ms q)
    (hb : TraitAt P ms b) : q = b.cross := by
  obtain ⟨ms', q', σ, sig, hty', hj, hσ, hhd⟩ := h.callc_recv_at hc
  rw [hty] at hty'; cases hty'
  obtain ⟨sig', hσ', hhd'⟩ := hb j σ hj
  rw [hσ] at hσ'; cases hσ'
  rw [hhd] at hhd'
  simp only [Option.some.injEq, Prod.mk.injEq, Ty.fn.injEq, true_and] at hhd'
  exact hhd'

/-- So a trait object packed at another class than its trait's bound is inert:
    no method of it is called. -/
theorem callc_not_at {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var}
    {k : Stmt} {Ec : Entry} {ms : List Nat} {q : Cross} {b : TraitBound} (hb : TraitAt P ms b)
    (hc : Γ c = some Ec) (hty : Ec.ty = .fn ms q) (hq : q ≠ b.cross) : ¬ StmtT P Γ F (.callc x c j zs k) Δ :=
  fun h => hq (h.callc_bound hc hty hb)

/-- Every method's code of a package takes the environment as its receiver,
    and changes nothing through a borrow (`Implements.env_recv`, method by
    method): an impl's code takes its box, whichever method a call picks
    (lent, or, A2-envhand, handed over where its interface takes it `inout`). -/
theorem _root_.A2.CodeOK.env_recv {P : Prog} {fs : List Nat} {te : Ty} {ms : List Nat}
    {cs : List (Var × PMode × Ty)} (h : CodeOK P fs te ms cs) {j f : Nat} (hf : fs[j]? = some f) :
    ∃ fn pm, P[f]? = some fn ∧ fn.params.head? = some (pm, te) ∧ ¬ ThruFn P f := by
  have hj : j < ms.length := h.1 ▸ (List.getElem?_eq_some_iff.mp hf).1
  obtain ⟨fn, sig, hfn, _, hhd, hnt⟩ := (h.2 j f ms[j] hf (List.getElem?_eq_getElem hj)).env_recv
  exact ⟨fn, sig.recvMode, hfn, hhd, hnt⟩

/-- An impl's code fixes the type of the box it is packed with: its first
    method takes it, as its receiver. -/
theorem _root_.A2.CodeOK.recv_eq {P : Prog} {fs : List Nat} {te te' : Ty} {ms ms' : List Nat}
    {cs cs' : List (Var × PMode × Ty)} (h : CodeOK P fs te ms cs) (h' : CodeOK P fs te' ms' cs')
    (hne : fs ≠ []) : te = te' := by
  obtain ⟨f, hf⟩ : ∃ f, fs[0]? = some f := by
    cases fs with
    | nil => exact absurd rfl hne
    | cons f _ => exact ⟨f, rfl⟩
  obtain ⟨fn, pm, hfn, hhd, _⟩ := h.env_recv hf
  obtain ⟨fn', pm', hfn', hhd', _⟩ := h'.env_recv hf
  rw [hfn] at hfn'; cases hfn'
  rw [hhd] at hhd'; cases hhd'
  rfl

/-- A3.5c: `fs` is an impl, for the type `te`, of the trait whose methods are
    `ms`, held to the bound `b` (docs/MEMORY.md §6.5: "holds every type
    implementing `Job` to Send where its impl is"): its code implements every
    method on a box of type `te` (`CodeOK`), and `te` keeps the bound's promise
    (`Cross.Fits`). -/
def ImplOK (P : Prog) (b : TraitBound) (fs : List Nat) (te : Ty) (ms : List Nat) : Prop :=
  CodeOK P fs te ms [] ∧ b.cross.Fits te []

/-- **Packing an impl's value into a trait object is the per-impl check**: a
    `dyn` the program makes (`Stmt.codesOK`) at its trait's bound is an impl
    held to that bound. -/
theorem dyn_implOK {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {fs : List Nat} {te : Ty} {ms : List Nat}
    {y : Var} {E : Entry} {b : TraitBound} (h : RhsT Γ F (Rhs.dyn fs te ms y) E Γ1)
    (hty : E.ty = .fn ms b.cross) (hc : (Rhs.dyn fs te ms y).codeOK P) : ImplOK P b fs te ms := by
  obtain ⟨q, hq, hf⟩ := h.pack_fits
  rw [hty] at hq; cases hq
  exact ⟨hc, hf⟩

/-- The check is the impl's, not the pack's: it asks the bound's promise of
    the one type the impl's code takes, so every pack of the impl gets the
    answer one of them got (the runtime asks it once, where the impl is). -/
theorem ImplOK.of_code {P : Prog} {b : TraitBound} {fs : List Nat} {te te' : Ty} {ms ms' : List Nat}
    (h : ImplOK P b fs te ms) (h' : CodeOK P fs te' ms' []) (hne : fs ≠ []) : ImplOK P b fs te' ms' := by
  obtain rfl := h.1.recv_eq h' hne
  exact ⟨h', h.2⟩

/-! A3.5c: the crossing check walks a trait object's box, as the runtime's
`mem_send_check` walks it through the vtable (h360): the moved values are
trees, and `Sub` enters a package's environment (`Sub.pkg`), on the side that
moves and on the side that stays alike. -/

/-- Moving the arguments out of the spawner gives one answer. -/
theorem MoveArgs.det {st : Var → Option Slot} {as : List Var} {vs vs' : List Val}
    {st1 st2 : Var → Option Slot} (h : MoveArgs st as vs st1) (h' : MoveArgs st as vs' st2) :
    vs = vs' ∧ st1 = st2 := by
  induction h generalizing vs' st2 with
  | nil => cases h'; exact ⟨rfl, rfl⟩
  | cons ha _ ih =>
    cases h' with
    | cons ha' hm' =>
      rw [ha] at ha'; cases ha'
      obtain ⟨rfl, rfl⟩ := ih hm'
      exact ⟨rfl, rfl⟩

/-- **A library handle in a trait object's box is counted**: a spawn whose
    moved values hold a trait object (or a closure) whose box holds a share of
    a cell that a slot the spawner keeps holds too, in its own box or not,
    fails the crossing check, whatever it moves: it is no `TStep.spawn`, and
    `TStep.spawnFail` panics. -/
theorem sendCheck_box_kept {st st' : Var → Option Slot} {args : List Var} {vs : List Val}
    (hm : MoveArgs st args vs st') {v : Val} (hv : v ∈ vs) {fs : List Nat} {te : Ty} {ms : List Nat}
    {e : Val} {cs : List (Var × PMode × Ty)} (hs : Sub (.pkg fs te ms e cs) v) {k : Nat}
    (hk : Sub (.cell k) e) {y : Var} {o : Bool} {w : Val} (hy : st' y = some ⟨o, some w⟩)
    (hw : Sub (.cell k) w) {vs' : List Val} {st'' : Var → Option Slot} (hm' : MoveArgs st args vs' st'') :
    ¬ SendCheck vs' st'' := by
  obtain ⟨rfl, rfl⟩ := hm.det hm'
  exact fun h => sendCheck_env h hv hs hk y o w hy hw

/-- A tree of a type that holds no cell share holds none. -/
theorem _root_.A2.WFv.noCell_hasCell {τ : Ty} {v : Val} (hw : WFv τ v) (hnc : τ.hasCell = false) {k : Nat} :
    ¬ Sub (.cell k) v := by
  induction hw with
  | int => intro h; cases h
  | view => intro h; cases h
  | arc => intro h; cases h
  | lk => intro h; cases h
  | cell => simp [Ty.hasCell] at hnc
  | pkg _ hq ih => intro h; cases h with | pkg h => exact ih (hq.2.1 hnc) h
  | node _ ih =>
    intro h
    cases h with
    | child he hs => exact ih _ he (by simpa [Ty.hasCell] using hnc) hs
  | pair _ _ iha ihb =>
    simp only [Ty.hasCell, Bool.or_eq_false_iff] at hnc
    intro h
    cases h with
    | fst h => exact iha hnc.1 h
    | snd h => exact ihb hnc.2 h
  | inl _ ih =>
    simp only [Ty.hasCell, Bool.or_eq_false_iff] at hnc
    intro h; cases h with | inl h => exact ih hnc.1 h
  | inr _ ih =>
    simp only [Ty.hasCell, Bool.or_eq_false_iff] at hnc
    intro h; cases h with | inr h => exact ih hnc.2 h

/-- A `: Send Sync` trait object's box holds no library handle, at any depth:
    the crossing check has nothing to count in it (the runtime fills the
    vtable's check only for an impl of a `: Send` trait whose type reaches
    one). -/
theorem sendSync_box_noCell {ms : List Nat} {v : Val} (hw : WFv (.fn ms TraitBound.sendSync.cross) v)
    {k : Nat} : ¬ Sub (.cell k) v :=
  hw.noCell_hasCell rfl

/-- A value of a type that holds no view holds only packages that fit `send`,
    however deep they lie (a field, an element, another package's box): each
    box holds no view, and nothing is captured by name. -/
theorem _root_.A2.WFv.noView_fits {τ : Ty} {v : Val} (hw : WFv τ v) (hhv : τ.holdsView = false)
    {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val} {cs : List (Var × PMode × Ty)}
    (hs : Sub (.pkg fs te ms e cs) v) : Cross.send.Fits te cs := by
  induction hw with
  | int => cases hs
  | view => cases hs
  | node _ ih =>
    cases hs with
    | child he h => exact ih _ he (by simpa [Ty.holdsView] using hhv) h
  | pair _ _ iha ihb =>
    simp only [Ty.holdsView, Bool.or_eq_false_iff] at hhv
    cases hs with
    | fst h => exact iha hhv.1 h
    | snd h => exact ihb hhv.2 h
  | inl _ ih => simp only [Ty.holdsView, Bool.or_eq_false_iff] at hhv; cases hs with | inl h => exact ih hhv.1 h
  | inr _ ih => simp only [Ty.holdsView, Bool.or_eq_false_iff] at hhv; cases hs with | inr h => exact ih hhv.2 h
  | pkg _ hq ih =>
    obtain ⟨hv, _, hcs⟩ := hq.send hhv
    cases hs with
    | refl => exact TraitBound.fits_send.mpr ⟨hv, hcs⟩
    | pkg h => exact ih hv h
  | arc _ _ => cases hs
  | lk => cases hs
  | cell => cases hs

/-- So what a spawned function takes holds no trait object but one whose box
    `: Send` admits: none whose box holds a view, none of a trait the spawn's
    type checks could not see into. -/
theorem spawn_pkgs_send {P : Prog} {spawn : Nat → Bool} (hS : SpawnOK P spawn) {f : Nat}
    (hsp : spawn f = true) {fn : Fn} (hf : P[f]? = some fn) {pt : PMode × Ty} (hin : pt ∈ fn.params)
    {v : Val} (hw : WFv pt.2 v) {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val}
    {cs : List (Var × PMode × Ty)} (hs : Sub (.pkg fs te ms e cs) v) : Cross.send.Fits te cs := by
  obtain ⟨fn', hf', -, hpar⟩ := hS f hsp
  rw [hf] at hf'; cases hf'
  exact hw.noView_fits (hpar pt hin).2 hs

/-! A3.5c: h344 (`dyn_object_carries_an_rc_to_a_thread`), a `%Churn` of a trait
with no bound boxing a struct with an `Rc`, moved into a thread's closure
while the spawner kept a clone.  The model has no `Rc` (the standard
library's, phase B); what stands for a value that is not Send is a view (and
a binding captured by name), and for one whose copies are one state, changed
in place with no lock (an `Rc`'s count), a cell share (A3.5). -/

/-- h344: a trait object whose box reaches a value that is not Send (a view)
    is packed only at `any`: no impl of a `: Send` or `: Send Sync` trait
    boxes it, and a closure that captures an `any` object (`te = fn ms' any`,
    the thread's closure of h344) is `any` too ... -/
theorem dyn_view_any {Γ Γ1 : Ctx} {F : List Var} {fs : List Nat} {te : Ty} {ms : List Nat} {y : Var}
    {cs : List (Var × PMode × Ty)} {E : Entry} (h : RhsT Γ F (.pack fs te ms y cs) E Γ1)
    (hv : te.holdsView = true) : E.ty = .fn ms .any := by
  obtain ⟨q, hty, hq⟩ := h.pack_fits
  rw [hty]
  cases q with
  | any => rfl
  | _ => rw [(hq.1 rfl).1] at hv; cases hv

/-- ... one whose box holds a library handle (a cell share: Send, not Sync) is
    not packed at `: Send Sync` ... -/
theorem dyn_cell_notSync {Γ Γ1 : Ctx} {F : List Var} {fs : List Nat} {te : Ty} {ms : List Nat} {y : Var}
    {cs : List (Var × PMode × Ty)} {E : Entry} (h : RhsT Γ F (.pack fs te ms y cs) E Γ1)
    (hc : te.hasCell = true) : E.ty = .fn ms .any ∨ E.ty = .fn ms .send := by
  obtain ⟨q, hty, hq⟩ := h.pack_fits
  rw [hty]
  cases q with
  | any => exact .inl rfl
  | send => exact .inr rfl
  | _ => rw [hq.2.1 rfl] at hc; cases hc

/-- ... and an object of a trait with no bound (h344's `%Churn`) crosses no
    spawn: a spawned function takes no `any` object (`spawn_not_any`), and an
    object it takes at another class is no receiver of its trait's methods
    (`callc_not_at`), so the thread cannot call it. -/
theorem spawn_dyn_none {P : Prog} {spawn : Nat → Bool} (hS : SpawnOK P spawn) {f : Nat}
    (hsp : spawn f = true) {fn : Fn} (hf : P[f]? = some fn) {ms : List Nat} (hb : TraitAt P ms .none)
    {pm : PMode} {q : Cross} (hin : (pm, Ty.fn ms q) ∈ fn.params) {Γ Δ : Ctx} {F : List Var} {x c : Var}
    {j : Nat} {zs : List Var} {k : Stmt} {Ec : Entry} (hc : Γ c = some Ec) (hty : Ec.ty = .fn ms q) :
    ¬ StmtT P Γ F (.callc x c j zs k) Δ := by
  refine callc_not_at hb hc hty fun hq => ?_
  rw [hq] at hin
  exact spawn_not_any hS hsp hf hin

/-- A spawned function takes a trait object only of a trait with a bound
    (`: Send` or `: Send Sync`) ... -/
theorem spawn_dyn_bound {P : Prog} {spawn : Nat → Bool} (hS : SpawnOK P spawn) {f : Nat}
    (hsp : spawn f = true) {fn : Fn} (hf : P[f]? = some fn) {pm : PMode} {ms : List Nat} {b : TraitBound}
    (hin : (pm, Ty.fn ms b.cross) ∈ fn.params) : b ≠ .none := by
  rintro rfl
  exact spawn_not_any hS hsp hf hin

/-- ... an `Arc` holds one only of a `: Send Sync` trait (`Arc T` asks `T`
    Send and Sync) ... -/
theorem arcNew_dyn {Γ Γ1 : Ctx} {F : List Var} {ms : List Nat} {b : TraitBound} {y : Var} {E : Entry}
    (h : RhsT Γ F (.arcNew (.fn ms b.cross) y) E Γ1) : b = .sendSync := by
  rcases arcNew_fn h with hq | hq <;> cases b <;> first | rfl | cases hq

/-- ... and a module global holds none but in an `Arc`, of a `: Send Sync`
    trait (A3.6: `Ty.sync`). -/
theorem glob_dyn {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {ms : List Nat} {b : TraitBound} {E : Entry}
    (h : RhsT Γ F (.glob g (.arc (.fn ms b.cross))) E Γ1) : b = .sendSync := by
  have hs := h.glob_sync
  cases b with
  | sendSync => rfl
  | _ => cases hs

theorem glob_not_dyn {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {ms : List Nat} {q : Cross} {E : Entry} :
    ¬ RhsT Γ F (.glob g (.fn ms q)) E Γ1 := fun h => by cases h.glob_sync

/-! ### A3.5c: subsumption, bounds and receivers

* *Subsumption* is A3.5b's: an object packed at a class below its trait's
  bound (an impl of a `: Send` trait whose box holds no handle, packed `sync`)
  is taken up to the bound by a move or a copy (`dyn_up_bound`), and is then a
  receiver of the trait's methods; the pack kept the bound's promise
  (`ImplOK.of_le`).
* *Generic bounds and supertraits.*  A2 has no generics: a generic function is
  monomorphised, each instance a function of the program at concrete types, so
  a bound `[T: Send]` or `[T: Send Sync]` is a fact about the instance's type,
  the one the crossing rules ask (`TraitBound.Holds`).  For a closure or a
  trait object it is its class (`TraitBound.holds_fn`), as `pack` gave it.  A
  supertrait's bound is a bound the trait's objects keep (`Holds.mono`).
* *An `inout` receiver.*  A2's call through a package hands the code its
  environment lent, a copy in a fresh slot (`envMem`), so no call through an
  object changes its box: an interface with an `inout` receiver has no typed
  call (`callc_not_inout`).  A borrow of what an `Arc` or a read guard lends is
  no `inout` argument of any function either (`paramOK_inout_not_bor`, h364). -/

/-- An object packed at a class below its trait's bound is taken up to the bound
    by a move (A3.5b's subsumption), where its trait's methods take it. -/
theorem dyn_up_bound {Γ : Ctx} {F : List Var} {y : Var} {Ey : Entry} {ms : List Nat} {q : Cross}
    {b : TraitBound} (hy : Γ y = some Ey) (hl : Ey.live = true) (hm : Ey.mode = .own) (hyF : y ∉ F)
    (hp : NoPin Γ y) (hds : DtorSafe Γ .replace false y) (hty : Ey.ty = .fn ms q) (hq : q.Le b.cross) :
    RhsT Γ F (.var y) ⟨.fn ms b.cross, .own, true, [], Ey.held, false, false⟩
      (setE (kill .replace false y Γ) y { Ey with live := false, dtor := false }) :=
  RhsT.moveUp hy hl hm hyF hp hds hty hq

/-- ... and the pack at the class below kept the bound's promise: the impl is
    held to the bound. -/
theorem ImplOK.of_le {P : Prog} {b : TraitBound} {fs : List Nat} {te : Ty} {ms : List Nat} {q : Cross}
    (hc : CodeOK P fs te ms []) (hf : q.Fits te []) (hq : q.Le b.cross) : ImplOK P b fs te ms :=
  ⟨hc, hf.mono hq⟩

/-- A3.5c: what a bound asks of a type: nothing; Send (`: Send`, `[T: Send]`),
    the question a spawn, a lock and a channel ask (no view); or Send and Sync
    (`: Send Sync`, `[T: Send Sync]`), the question an `Arc` asks (also no
    library handle).  A generic function is monomorphised, so its bound is
    asked of each instance's concrete type. -/
def TraitBound.Holds : TraitBound → Ty → Prop
  | .none, _ => True
  | .send, t => t.holdsView = false
  | .sendSync, t => t.holdsView = false ∧ t.hasCell = false

/-- **A bound is answered by the class**: a closure or a trait object meets a
    bound exactly when its class is at most the bound's. -/
theorem TraitBound.holds_fn {b : TraitBound} {ms : List Nat} {q : Cross} :
    b.Holds (.fn ms q) ↔ q.Le b.cross := by
  cases b <;> cases q <;> simp [TraitBound.Holds, TraitBound.cross, Ty.holdsView, Ty.hasCell, Cross.Le,
    Cross.rank]

/-- A supertrait's bound is kept: what meets a bound meets every weaker one (a
    trait declared `: A` with `A : Send` is held to Send, and its objects meet
    `A`'s bound). -/
theorem TraitBound.Holds.mono {b b' : TraitBound} {t : Ty} (h : b.Holds t) (hle : b.cross.Le b'.cross) :
    b'.Holds t := by
  cases b <;> cases b' <;> simp_all [TraitBound.Holds, TraitBound.cross, Cross.Le, Cross.rank]

/-- An instance whose type meets `[T: Send]` is what a spawn's parameter, a
    lock's value and a channel's element ask: no view (A3.0's `SpawnOK`,
    `RhsT.lockNew`, `Ty.ok (lk _)`), and so no closure that holds names ... -/
theorem TraitBound.Holds.send {b : TraitBound} {t : Ty} (h : b.Holds t) (hb : b ≠ .none) :
    t.holdsView = false ∧ t.hasFn = false := by
  have hv : t.holdsView = false := by
    cases b with
    | none => exact absurd rfl hb
    | send => exact h
    | sendSync => exact h.1
  refine ⟨hv, ?_⟩
  cases hf : t.hasFn
  · rfl
  · rw [hasFn_holdsView hf] at hv; cases hv

/-- ... and one whose type meets `[T: Send Sync]` is what an `Arc`'s payload
    asks (`RhsT.arcNew`). -/
theorem TraitBound.Holds.arc {t : Ty} (h : TraitBound.sendSync.Holds t) :
    (t.holdsView = false ∧ t.hasFn = false) ∧ t.hasCell = false :=
  ⟨h.send (by decide), h.2⟩

/-- A call through a package hands its receiver to an interface that takes it
    `inp` ... -/
theorem _root_.A2.StmtT.callc_inp {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat}
    {zs : List Var} {k : Stmt} {Ec : Entry} (h : StmtT P Γ F (.callc x c j zs k) Δ) (hc : Γ c = some Ec) :
    ∃ ms q σ sig, Ec.ty = .fn ms q ∧ ms[j]? = some σ ∧ P[σ]? = some sig ∧
      ∃ t, sig.params.head? = some (.inp, t) := by
  obtain ⟨ms, q, σ, sig, hty, hj, hσ, hhd⟩ := h.callc_recv_at hc
  exact ⟨ms, q, σ, sig, hty, hj, hσ, _, hhd⟩

/-- ... so a method whose interface takes the receiver `inout` (h364–h366's
    `rename`, which changes the box) is called through no object: A2's call
    lends the code a copy of the environment (`envMem`), and has no step that
    would change the box in place. -/
theorem callc_not_inout {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var}
    {k : Stmt} {Ec : Entry} {ms : List Nat} {q : Cross} {σ : Nat} {sig : Fn} (hc : Γ c = some Ec)
    (hty : Ec.ty = .fn ms q) (hj : ms[j]? = some σ) (hσ : P[σ]? = some sig) {b : Eff} {t : Ty}
    (hio : sig.params.head? = some (.inout b, t)) : ¬ StmtT P Γ F (.callc x c j zs k) Δ := by
  intro h
  obtain ⟨ms', q', σ', sig', hty', hj', hσ', t', hhd⟩ := h.callc_inp hc
  rw [hty] at hty'; cases hty'
  rw [hj] at hj'; cases hj'
  rw [hσ] at hσ'; cases hσ'
  rw [hio] at hhd; cases hhd

/-- h364 (`dyn_inout_method_through_a_read_guard`): a trait object an `Arc` or
    a read guard lends (`getE`), and every copy of it (`copyBor`, `copyUp`), is
    a borrow, which is no `inout` argument of any function (`paramOK` asks
    `canDo`): the box every holder reads is changed by no call. -/
theorem paramOK_inout_not_bor {b : Eff} {t : Ty} {E : Entry} (h : paramOK (.inout b) t E) :
    E.mode ≠ .bor := by
  intro hm
  rcases (paramOK_inout h).1 with h' | ⟨_, h', _⟩ <;> rw [hm] at h' <;> cases h'

/-- What `arc_get` lends of anything but an integer is such a borrow. -/
theorem getE_bor {a : Var} {E : Entry} {t : Ty} (ht : t ≠ .int) : (getE a E t).mode = .bor := by
  cases t <;> first | exact absurd rfl ht | rfl

/-! ### A3.5's second cut: library handles in locks and channels

A lock's payload and a channel's element may hold cell shares (`Ty.ok (lk t)`
asks only that `t` hold no view), and so Send closures and `: Send` trait
objects, whose environments may.  Every value going into a lock block faces
the crossing check, as a spawn's arguments do: `locked_new` and a cell's
constructor, `locked_restore`, the give-back at a lock scope's end
(`locked_with`, `locked_update`) and `chan_send`.  A failed check panics.  A3's
`CellInv` then keeps a cell's shares in one place: one thread's slots, or one
lock block's payload. -/

/-- Handing a value on is deterministic. -/
theorem _root_.A2.TakeVal.det {m m1 m2 : Mem} {y : Var} {v w : Val} (h1 : TakeVal m y v m1)
    (h2 : TakeVal m y w m2) : v = w ∧ m1 = m2 := by
  cases h1 with
  | own hy => cases h2 with
    | own hy' => rw [hy] at hy'; cases hy'; exact ⟨rfl, rfl⟩
    | bor hy' => rw [hy] at hy'; cases hy'
  | bor hy => cases h2 with
    | own hy' => rw [hy] at hy'; cases hy'
    | bor hy' => rw [hy] at hy'; cases hy'; exact ⟨rfl, rfl⟩

/-- A value that holds a share of a cell a slot left behind holds one of fails
    the crossing check. -/
theorem not_sendCheck {st : Var → Option Slot} {v : Val} {k : Nat} (hv : Sub (.cell k) v) {z : Var} {o : Bool}
    {w : Val} (hz : st z = some ⟨o, some w⟩) (hw : Sub (.cell k) w) : ¬ SendCheck [v] st :=
  fun h => h k ⟨v, List.mem_singleton_self _, hv⟩ z o w hz hw

/-- **h340** (`closure_sent_on_a_channel_captures_a_kept_handle`): a closure
    that captured a library handle the sender still holds a share of (in any
    slot, inside any value) is not sent: `chan_send`'s crossing check fails,
    and the send panics (`EvalR.chanSendFail`), with no other outcome ... -/
theorem chanSend_kept {m m1 : Mem} {a y : Var} {v : Val} (ht : TakeVal m y v m1) {k : Nat}
    (hv : Sub (.cell k) v) {z : Var} {o : Bool} {w : Val} (hz : m1.st z = some ⟨o, some w⟩)
    (hw : Sub (.cell k) w) :
    EvalR m (.chanSend a y) .panic ∧ ∀ r o' m', ¬ EvalR m (.chanSend a y) (.ok r o' m') := by
  refine ⟨EvalR.chanSendFail ht (not_sendCheck hv hz hw), fun r o' m' h => ?_⟩
  cases h with
  | chanSend _ ht' _ _ _ _ hck =>
    obtain ⟨rfl, rfl⟩ := ht.det ht'
    exact not_sendCheck hv hz hw hck
  | chanSendClosed _ ht' _ _ hck =>
    obtain ⟨rfl, rfl⟩ := ht.det ht'
    exact not_sendCheck hv hz hw hck

/-- ... and one sent took every owner along: the send moves the closure's
    tree, the handle in its environment with it, into the queue (or drops it
    on a closed channel), and no slot left holds a share of a cell it holds. -/
theorem chanSend_moves {m m' : Mem} {a y : Var} {r : Val} {o : Bool} (h : EvalR m (.chanSend a y) (.ok r o m')) :
    ∃ v m1, TakeVal m y v m1 ∧ m'.st = m1.st ∧ SendCheck [v] m'.st := by
  cases h with
  | chanSend _ ht _ _ _ _ hck => exact ⟨_, _, ht, rfl, hck⟩
  | chanSendClosed _ ht _ _ hck => exact ⟨_, _, ht, rfl, hck⟩

/-- h358 (`rc_in_a_locked_in_an_arc_on_two_threads`) and h357
    (`rwlocked_of_a_library_handle_on_two_threads`): a value that holds a
    library handle the caller kept a share of goes into no lock: `locked_new`
    (and `rw_new`) panics (`EvalR.lockNewFail`) ... -/
theorem lockNew_kept {m m1 : Mem} {t : Ty} {y : Var} {v : Val} (ht : TakeVal m y v m1) {k : Nat}
    (hv : Sub (.cell k) v) {z : Var} {o : Bool} {w : Val} (hz : m1.st z = some ⟨o, some w⟩)
    (hw : Sub (.cell k) w) :
    EvalR m (.lockNew t y) .panic ∧ ∀ r o' m', ¬ EvalR m (.lockNew t y) (.ok r o' m') := by
  refine ⟨EvalR.lockNewFail ht (not_sendCheck hv hz hw), fun r o' m' h => ?_⟩
  cases h with
  | lockNew ht' _ hck =>
    obtain ⟨rfl, rfl⟩ := ht.det ht'
    exact not_sendCheck hv hz hw hck

/-- ... nor back into one: `locked_restore` panics (`EvalR.lockRestoreFail`;
    h358's thread restores the `Rc` after pushing clones of it) ... -/
theorem lockRestore_kept {m m1 : Mem} {a y : Var} {v : Val} (ht : TakeVal m y v m1) {k : Nat}
    (hv : Sub (.cell k) v) {z : Var} {o : Bool} {w : Val} (hz : m1.st z = some ⟨o, some w⟩)
    (hw : Sub (.cell k) w) :
    EvalR m (.lockRestore a y) .panic ∧ ∀ r o' m', ¬ EvalR m (.lockRestore a y) (.ok r o' m') := by
  refine ⟨EvalR.lockRestoreFail ht (not_sendCheck hv hz hw), fun r o' m' h => ?_⟩
  cases h with
  | lockRestore _ ht' _ hck =>
    obtain ⟨rfl, rfl⟩ := ht.det ht'
    exact not_sendCheck hv hz hw hck

/-- ... and **the give-back's check** (`locked_with`, `locked_update`,
    h354's `locked_update_stores_a_kept_handle_into_the_value`): a lock
    scope's end gives the value back only past the crossing check, and when
    the body kept an owner of a handle the value holds, or stored into it one
    kept outside, the end is a panic in the scope, the store as it was (the
    unwinding then drops `x`, the lock left held). -/
theorem scopeL_end {P : Prog} {m : Mem} {k : Nat} {t : Ty} {x : Var} {r : Res}
    (h : Step P m (.scopeL k t x .skip) r) :
    (∃ m', r = .ok m' .skip ∧ Release m k t x m' ∧ ∀ sl, m.st x = some sl → GiveCheck m x sl) ∨
      (r = .ok m (.scopeL k t x .panic) ∧ ∃ sl, m.st x = some sl ∧ ¬ GiveCheck m x sl) := by
  cases h with
  | scopeLSkip hrl hck => exact .inl ⟨_, rfl, hrl, hck⟩
  | scopeLFail hx hck => exact .inr ⟨rfl, _, hx, hck⟩
  | scopeLIn hs => cases hs
  | scopeLP hs _ => cases hs with | waitPanic hw => cases hw
  | waitPanic hw => cases hw

/-- **A `: Send` trait object fits in a lock** (A3.5c's gap, closed): its type,
    `fn ms send`, holds no view, so `locked_new` takes it; a library handle its
    box holds faces the crossing check at every entry ... -/
theorem lockNew_dyn_send {Γ Γ1 : Ctx} {F : List Var} {ms : List Nat} {y : Var} {Ey : Entry} {D : List Dep}
    (hy : Γ y = some Ey) (hl : Ey.live = true) (hty : Ey.ty = .fn ms TraitBound.send.cross)
    (hpa : PushArg Γ F y Ey (.fn ms TraitBound.send.cross) D Γ1) :
    RhsT Γ F (.lockNew (.fn ms TraitBound.send.cross) y)
      ⟨.lk (.fn ms TraitBound.send.cross), .own, true, [], [], false, false⟩ Γ1 :=
  lockNew_send hy hl hty hpa

/-- ... and in a channel: a channel's element may be an object of any trait
    with a bound (`: Send` or `: Send Sync`), none of one with no bound. -/
theorem chan_dyn {ms : List Nat} {b : TraitBound} :
    (Ty.lk (.prod (.vec (.fn ms b.cross)) .int)).ok = true ↔ b ≠ .none := by
  cases b <;> simp [TraitBound.cross, Ty.ok, Ty.holdsView]

/-- ... the same for a lock's: `locked_new` takes no object of a trait with no
    bound (h344's `%Churn`). -/
theorem lockNew_dyn {Γ Γ1 : Ctx} {F : List Var} {ms : List Nat} {b : TraitBound} {y : Var} {E : Entry}
    (h : RhsT Γ F (.lockNew (.fn ms b.cross) y) E Γ1) : b ≠ .none := by
  rintro rfl
  rcases lockNew_fn h with h' | h' | h' <;> cases h'

/-- One step of the configuration. -/
inductive TStep (P : Prog) (spawn : Nat → Bool) : Cfg → Cfg → Prop
  /-- A thread takes one of A2's steps, unless its next step is a spawn;
      (A3.1) the configuration's sweep ends it, as A2's `Steps` ends every
      step with the store's. -/
  | thread {C : Cfg} {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt} :
      C.ths[i]? = some t → ¬ SpawnRedex spawn t.s → Step P (C.view t) t.s (.ok m' s') →
      TStep P spawn C (C.put i m' s').sweep
  /-- A spawn: the arguments move to a new thread, which runs the body in
      its parameters' scopes and its result's (variable `n`, the number of
      parameters, as in the body's own numbering — so its end drops the
      result); the spawner's result is `0`. -/
  | spawn {C : Cfg} {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var}
      {k : Stmt} {fn : Fn} {vs : List Val} {st' : Var → Option Slot} :
      C.ths[i]? = some t → Redex t.s K (.letcall x f args k) → spawn f = true → P[f]? = some fn →
      t.st x = none → MoveArgs t.st args vs st' → SendCheck vs st' →
      TStep P spawn C
        { C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k)⟩ ++
                        [⟨spawnSt fn vs, fn.nvars,
                          wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] }
  /-- A3.5: a spawn whose crossing check fails panics in the spawner, as
      `mem_send_check` calls `nurl_panic`: no thread is made and nothing
      moves, and the spawner's next step is A2's panic, which unwinds its
      scopes (or a `recover` frame catches it). -/
  | spawnFail {C : Cfg} {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var}
      {k : Stmt} {fn : Fn} {vs : List Val} {st' : Var → Option Slot} :
      C.ths[i]? = some t → Redex t.s K (.letcall x f args k) → spawn f = true → P[f]? = some fn →
      t.st x = none → MoveArgs t.st args vs st' → ¬ SendCheck vs st' →
      TStep P spawn C { C with ths := C.ths.set i ⟨t.st, t.nv, K (.seq .panic (.letcall x f args k))⟩ }

inductive Reach (P : Prog) (spawn : Nat → Bool) : Cfg → Cfg → Prop
  | refl {C : Cfg} : Reach P spawn C C
  | step {C C' C'' : Cfg} : TStep P spawn C C' → Reach P spawn C' C'' → Reach P spawn C C''

/-! ### What a step touches

The addresses a thread's next step reads (`false`) or writes (`true`): the
ones A2's rule checks `alloc` for, changes or frees.  Slots are a thread's
own and are no address.  A fresh address is no touch: allocation is the
allocator's, which is thread-safe (the C runtime, trusted base), and two
threads that both allocate next never get one address, since `nid` moves
with each step.  Over-approximating is harmless otherwise: what a thread
may touch beyond its rule is its own.  (A3.1) A read may be of a live
block's payload, which a node `NodeAt` / `DataAt` finds, a view or an
`arc_get` points into; no step writes one while its block exists
(`Step.blk`). -/

/-- What evaluating an expression reads: a `Vec`'s length is in its control
    block. -/
inductive EReads (m : Mem) : Expr → Nat → Prop
  | len {x : Var} {t : Ty} {c d : Nat} {es : List Val} : VecOf m x t c d es → EReads m (.len x) c
  | addL {a b : Expr} {i : Nat} : EReads m a i → EReads m (.add a b) i
  | addR {a b : Expr} {i : Nat} : EReads m b i → EReads m (.add a b) i
  | ltL {a b : Expr} {i : Nat} : EReads m a i → EReads m (.lt a b) i
  | ltR {a b : Expr} {i : Nat} : EReads m b i → EReads m (.lt a b) i

/-- What a right-hand side touches. -/
inductive RTouch (m : Mem) : Rhs → Nat → Bool → Prop
  | expr {e : Expr} {i : Nat} : EReads m e i → RTouch m (.expr e) i false
  | atC {y : Var} {i : Expr} {t : Ty} {c d : Nat} {es : List Val} :
      VecOf m y t c d es → RTouch m (.at y i) c false
  | atD {y : Var} {i : Expr} {t : Ty} {c d : Nat} {es : List Val} :
      VecOf m y t c d es → RTouch m (.at y i) d false
  | atI {y : Var} {i : Expr} {a : Nat} : EReads m i a → RTouch m (.at y i) a false
  | view {y : Var} {t : Ty} {c d : Nat} {es : List Val} : VecOf m y t c d es → RTouch m (.view y) c false
  | sat {y : Var} {i : Expr} {d o l : Nat} :
      m.st y = some ⟨false, some (.view d o l)⟩ → RTouch m (.sat y i) d false
  | satI {y : Var} {i : Expr} {a : Nat} : EReads m i a → RTouch m (.sat y i) a false
  | popC {y : Var} {t : Ty} {c d : Nat} {es : List Val} :
      m.st y = some ⟨true, some (.node t c d es)⟩ → RTouch m (.pop y) c true
  | popD {y : Var} {t : Ty} {c d : Nat} {es : List Val} :
      m.st y = some ⟨true, some (.node t c d es)⟩ → RTouch m (.pop y) d true
  /-- A3.1: `arc_get` reads the payload of the block its share names (every
      address of it: an over-approximation). -/
  | arcGet {a : Var} {o : Bool} {k : Nat} {p : Val} {bl : Blk} {i : Nat} :
      m.st a = some ⟨o, some (.arc k p)⟩ → m.blk k = some bl → i ∈ bl.rd.ids →
      RTouch m (.arcGet a) i false
  /-- A3.4: `chan_send` hands over the tree `y` owns: into the queue, or, on
      a closed channel, dropped, which writes it (every address of it, either
      way: an over-approximation).  The queue's ends, which a send or a
      receive changes, are the runtime mutex's, as a lock's word is: no
      address. -/
  | chanSend {a y : Var} {v : Val} {i : Nat} :
      m.st y = some ⟨true, some v⟩ → i ∈ v.ids → RTouch m (.chanSend a y) i true

/-- What the next step of `s` touches. -/
inductive Touch (P : Prog) (m : Mem) : Stmt → Nat → Bool → Prop
  | seq {a b : Stmt} {i : Nat} {w : Bool} : Touch P m a i w → Touch P m (.seq a b) i w
  | letv {x : Var} {r : Rhs} {s : Stmt} {i : Nat} {w : Bool} :
      RTouch m r i w → Touch P m (.letv x r s) i w
  | letd {x : Var} {f : Nat} {r : Rhs} {s : Stmt} {i : Nat} {w : Bool} :
      RTouch m r i w → Touch P m (.letd x f r s) i w
  /-- A destructor's scope: its body's step. Its end runs the destructor's
      call first, and `scope x` frees the tree after it (`scopeEnd`). -/
  | scopeD {x : Var} {f : Nat} {s : Stmt} {i : Nat} {w : Bool} :
      Touch P m s i w → Touch P m (.scopeD x f s) i w
  | assign {x : Var} {r : Rhs} {i : Nat} {w : Bool} : RTouch m r i w → Touch P m (.assign x r) i w
  /-- An assignment releases the binding's old value. -/
  | assignDrop {x : Var} {r : Rhs} {t : Val} {i : Nat} :
      m.st x = some ⟨true, some t⟩ → i ∈ t.ids → Touch P m (.assign x r) i true
  | ite {c : Expr} {a b : Stmt} {i : Nat} : EReads m c i → Touch P m (.ite c a b) i false
  | pushC {x y : Var} {t : Ty} {c d : Nat} {es : List Val} :
      m.st x = some ⟨true, some (.node t c d es)⟩ → Touch P m (.push x y) c true
  | pushD {x y : Var} {t : Ty} {c d : Nat} {es : List Val} :
      m.st x = some ⟨true, some (.node t c d es)⟩ → Touch P m (.push x y) d true
  /-- A2-elem (#391): an element put back writes its `Vec`'s cell and buffer,
      as a push does, and reads what its index reads. -/
  | insertC {x y : Var} {i : Expr} {t : Ty} {c d : Nat} {es : List Val} :
      m.st x = some ⟨true, some (.node t c d es)⟩ → Touch P m (.insert x i y) c true
  | insertD {x y : Var} {i : Expr} {t : Ty} {c d : Nat} {es : List Val} :
      m.st x = some ⟨true, some (.node t c d es)⟩ → Touch P m (.insert x i y) d true
  | insertI {x y : Var} {i : Expr} {a : Nat} : EReads m i a → Touch P m (.insert x i y) a false
  /-- ... and one handed over (`withElem`) writes them as a pop does, and
      reads what its index reads.  (The element's own tree moves between the
      thread's slots: no address of it is touched.) -/
  | withElemC {v x : Var} {i : Expr} {s : Stmt} {t : Ty} {c d : Nat} {es : List Val} :
      m.st v = some ⟨true, some (.node t c d es)⟩ → Touch P m (.withElem v i x s) c true
  | withElemD {v x : Var} {i : Expr} {s : Stmt} {t : Ty} {c d : Nat} {es : List Val} :
      m.st v = some ⟨true, some (.node t c d es)⟩ → Touch P m (.withElem v i x s) d true
  | withElemI {v x : Var} {i : Expr} {s : Stmt} {a : Nat} :
      EReads m i a → Touch P m (.withElem v i x s) a false
  | free {x : Var} {t : Val} {i : Nat} :
      m.st x = some ⟨true, some t⟩ → i ∈ t.ids → Touch P m (.free x) i true
  /-- A change of a `Vec`'s elements (#295) writes its node's cell and
      buffer, wherever the node lies in its owner's tree ... -/
  | editC {b : Bool} {x o : Var} {op : Edit} {T : Val} {t : Ty} {c d : Nat} {es : List Val} :
      NodeOf m x o T t c d es → Touch P m (.edit b x op) c true
  | editD {b : Bool} {x o : Var} {op : Edit} {T : Val} {t : Ty} {c d : Nat} {es : List Val} :
      NodeOf m x o T t c d es → Touch P m (.edit b x op) d true
  /-- ... a truncation frees the elements it drops ... -/
  | editFree {b : Bool} {x o : Var} {i : Expr} {n : Nat} {T : Val} {t : Ty} {c d : Nat}
      {es : List Val} {a : Nat} :
      NodeOf m x o T t c d es → Eval m i n → a ∈ idsL (es.drop n) →
      Touch P m (.edit b x (.trunc i)) a true
  /-- ... and reads what its length expression reads. -/
  | editI {b : Bool} {x : Var} {i : Expr} {a : Nat} : EReads m i a → Touch P m (.edit b x (.trunc i)) a false
  /-- An element set frees the element it replaces ... -/
  | editSetFree {b : Bool} {x o y : Var} {i : Expr} {n : Nat} {T : Val} {t : Ty} {c d : Nat}
      {es : List Val} {a : Nat} (h : n < es.length) :
      NodeOf m x o T t c d es → Eval m i n → a ∈ es[n].ids → Touch P m (.edit b x (.set i y)) a true
  /-- ... or, out of range, the value it is handed ... -/
  | editSetDrop {b : Bool} {x o y : Var} {i : Expr} {n : Nat} {T : Val} {t : Ty} {c d : Nat}
      {es : List Val} {v : Val} {a : Nat} :
      NodeOf m x o T t c d es → Eval m i n → es.length ≤ n → m.st y = some ⟨true, some v⟩ →
      a ∈ v.ids → Touch P m (.edit b x (.set i y)) a true
  /-- ... and reads what its index expression reads. -/
  | editSetI {b : Bool} {x y : Var} {i : Expr} {a : Nat} :
      EReads m i a → Touch P m (.edit b x (.set i y)) a false
  | scope {x : Var} {s : Stmt} {i : Nat} {w : Bool} : Touch P m s i w → Touch P m (.scope x s) i w
  /-- A scope's end releases what its binding owns ... -/
  | scopeEnd {x : Var} {t : Val} {i : Nat} :
      m.st x = some ⟨true, some t⟩ → i ∈ t.ids → Touch P m (.scope x .skip) i true
  /-- ... and so does a panic unwinding through it. -/
  | scopeUnwind {x : Var} {s : Stmt} {m1 : Mem} {t : Val} {i : Nat} :
      Step P m s (.panic m1) → m1.st x = some ⟨true, some t⟩ → i ∈ t.ids →
      Touch P m (.scope x s) i true
  | rbind {p : Var} {s : Stmt} {i : Nat} {w : Bool} : Touch P m s i w → Touch P m (.rbind p s) i w
  | frozen {z : List Var} {s : Stmt} {i : Nat} {w : Bool} :
      Touch P m s i w → Touch P m (.frozen z s) i w
  | catchR {x : Var} {m0 : Mem} {s : Stmt} {i : Nat} {w : Bool} :
      Touch P m s i w → Touch P m (.catchR x m0 s) i w
  /-- A3.2: a lock scope: its body's step; its end drops what `x` owns, or
      gives it back to the block, which touches none of its addresses (an
      over-approximation: both are counted as writes of `x`'s tree); and so
      does a panic unwinding through it.  Taking a lock (`withLock`) and
      giving it back change only the lock's word, which the runtime's mutex
      changes atomically (the trusted base): no address. -/
  | scopeL {k : Nat} {t : Ty} {x : Var} {s : Stmt} {i : Nat} {w : Bool} :
      Touch P m s i w → Touch P m (.scopeL k t x s) i w
  | scopeLEnd {k : Nat} {t : Ty} {x : Var} {T : Val} {i : Nat} :
      m.st x = some ⟨true, some T⟩ → i ∈ T.ids → Touch P m (.scopeL k t x .skip) i true
  | scopeLUnwind {k : Nat} {t : Ty} {x : Var} {s : Stmt} {m1 : Mem} {T : Val} {i : Nat} :
      Step P m s (.panic m1) → m1.st x = some ⟨true, some T⟩ → i ∈ T.ids →
      Touch P m (.scopeL k t x s) i true

/-- A3.1: what the sweep that ends thread `i`'s next step frees: an address
    live before the step and after it, which the sweep frees — the payload
    of a block no thread reaches any more.  (A fresh address is no touch, as
    above.) -/
def SweepFrees (P : Prog) (C : Cfg) (i : Nat) (t : Thread) (a : Nat) : Prop :=
  ∃ m' s', Step P (C.view t) t.s (.ok m' s') ∧ C.alloc a = true ∧ m'.alloc a = true ∧
    (C.put i m' s').sweep.alloc a = false

/-- What thread `t` (the `i`-th) touches next in the configuration: what its
    rule touches, and (A3.1) what the sweep that ends its step frees, a
    write. -/
inductive CTouch (P : Prog) (C : Cfg) (i : Nat) (t : Thread) : Nat → Bool → Prop
  | step {a : Nat} {w : Bool} : Touch P (C.view t) t.s a w → CTouch P C i t a w
  | sweep {a : Nat} : SweepFrees P C i t a → CTouch P C i t a true

/-- Two threads whose next steps touch one address, one of them writing it.
    (A3.4's `Atomic` steps are atomic and are no race; so is a share's
    count, which is ghost here.) -/
def AddrRace (P : Prog) (C : Cfg) : Prop :=
  ∃ (i j : Nat) (ti tj : Thread) (a : Nat) (w : Bool), i ≠ j ∧ C.ths[i]? = some ti ∧
    C.ths[j]? = some tj ∧ CTouch P C i ti a true ∧ CTouch P C j tj a w

/-- A3.5: the keys of the lock scopes a statement is inside of (its spine's
    `scopeL` frames, innermost last). -/
def _root_.A2.Stmt.lkeys : Stmt → List Nat
  | .seq a _ => a.lkeys
  | .scope _ s => s.lkeys
  | .scopeD _ _ s => s.lkeys
  | .rbind _ s => s.lkeys
  | .frozen _ s => s.lkeys
  | .catchR _ _ s => s.lkeys
  | .scopeL k _ _ s => k :: s.lkeys
  | _ => []

/-- A3.5: thread `t`'s next step changes the state of cell `k` (a library
    handle's, which the library changes in place with no lock): it checks the
    state out through a share of it (`withCell`), or it runs inside a
    check-out of it, holding a share of it (the one the check-out is
    through, which `withLock`'s premises keep in its binding for the whole
    body).  Such a step writes the state wherever it is: the model checks it
    out as a lock's payload, so two threads at once would be serialized
    there, where the runtime's copies write one memory with no lock; so a
    step on a cell is not an address's touch, but a race of its own. -/
def CellOp (t : Thread) (k : Nat) : Prop :=
  (∃ K a x s o, Redex t.s K (.withLock a x s) ∧ t.st a = some ⟨o, some (.cell k)⟩) ∨
  (k ∈ t.s.lkeys ∧ ∃ y o v, t.st y = some ⟨o, some v⟩ ∧ Sub (.cell k) v)

/-- A3.5: two threads whose next steps change one cell's state. -/
def CellRace (C : Cfg) : Prop :=
  ∃ (i j : Nat) (ti tj : Thread) (k : Nat), i ≠ j ∧ C.ths[i]? = some ti ∧ C.ths[j]? = some tj ∧
    CellOp ti k ∧ CellOp tj k

/-- A race: two threads whose next steps touch one address, one of them
    writing it (`AddrRace`), or (A3.5) change one cell's state (`CellRace`). -/
def Race (P : Prog) (C : Cfg) : Prop := AddrRace P C ∨ CellRace C

/-! ### The claims -/

/-- No thread of a configuration reachable from `C0` is stuck: A2's
    `memory_safe`, on every thread. -/
def MemorySafe (P : Prog) (spawn : Nat → Bool) (C0 : Cfg) : Prop :=
  ∀ C, Reach P spawn C0 C → ∀ (i : Nat) (t : Thread), C.ths[i]? = some t →
    ¬ Stuck P (C.view t) t.s

/-- No configuration reachable from `C0` has a race. -/
def RaceFree (P : Prog) (spawn : Nat → Bool) (C0 : Cfg) : Prop :=
  ∀ C, Reach P spawn C0 C → ¬ Race P C

/-- When every thread has finished, nothing is allocated but (A3.6) what the
    module globals reach: A2's `no_leak_end`, over the threads.  Every live
    address is owned by the payload of a block a global reaches, which lives
    until the process exits, as the runtime's globals do.  With no global,
    nothing is allocated (`NoLeak.empty`). -/
def NoLeak (P : Prog) (spawn : Nat → Bool) (C0 : Cfg) : Prop :=
  ∀ C, Reach P spawn C0 C → (∀ t ∈ C.ths, t.s = .skip) → ∀ i, C.alloc i = true →
    ∃ k bl, C.blk k = some bl ∧ i ∈ bl.tree.ids ∧ Reached C0.globVals C.blk k

/-- With no global (A3.0–A3.5's start), nothing is allocated once every
    thread has finished: no block is reached from no root. -/
theorem NoLeak.empty {P : Prog} {spawn : Nat → Bool} {s : Stmt} {nv : Nat}
    (h : NoLeak P spawn (Cfg.start Globs.empty s nv)) :
    ∀ C, Reach P spawn (Cfg.init s nv) C → (∀ t ∈ C.ths, t.s = .skip) → ∀ i, C.alloc i = false := by
  intro C hr hend i
  cases hi : C.alloc i with
  | false => rfl
  | true =>
    obtain ⟨k, -, -, -, hk⟩ := h C hr hend i hi
    exfalso
    induction hk with
    | root hv _ => obtain ⟨g, hg⟩ := hv; cases hg
    | pay _ _ _ ih => exact ih

/-- A3.5's second cut: lock block `k'` of `B` holds a share of cell `k` in its
    payload, while the payload is in the block (a lock's, a cell's state, a
    channel's queue).  A3's confinement counts it as a place a cell's shares
    are, beside the threads' slots (`CellInv`, `A3/Cell.lean`). -/
def LockHolds (B : Nat → Option Blk) (k' k : Nat) : Prop :=
  ∃ t p, B k' = some ⟨t, .lock, some p⟩ ∧ Sub (.cell k) p

/-- **A3.6, what a start-set global may be**, as the claim asks it of the
    start:
    - each global holds a share of a block that synchronises itself, at a
      type `Ty.sync` admits (`GlobFits`): a lock share (`Locked`, `RwLocked`,
      `Mutex`, `Atomic`, `Channel`) or an `Arc` of no library handle — never a
      `Vec` (h263), a cell share or any other owned tree;
    - the store the globals' `make`s left is one A2's invariant holds of with
      no binding (`MInv`: every block a well-formed tree of its type that owns
      its payload's addresses once; `Covers`: nothing else is allocated);
    - every block is reached from a global (the sweep that ended the last
      `make` left no other);
    - (A3.5b) every package a block holds (a Sync closure an `Arc` global
      keeps) names code of its signature, as A2's `MemCodes` says of the
      store a typed `make` leaves;
    - (A3.5's second cut) a library handle the blocks hold (a `Locked
      PNCounter` global) has all its shares in one block's payload, at a key
      taken from `nid`: the `make`s ran the crossing check at every value
      going into a lock, as every thread does (A3's `CellInv`). -/
structure GlobsOK (P : Prog) (G : Globs) : Prop where
  sync  : ∀ g v, G.gl g = some v → ∃ t, t.sync = true ∧ t.ok = true ∧ GlobFits G.blk t v
  inv   : MInv (G.mem 0) (fun _ => none)
  cover : Covers (G.mem 0)
  reach : ∀ k bl, G.blk k = some bl → Reached (fun v => ∃ g, G.gl g = some v) G.blk k
  codes : BlkCodes P G.blk
  cells : ∀ k k1 k2, LockHolds G.blk k1 k → LockHolds G.blk k2 k → k1 = k2 ∧ k < G.nid

/-- **The A3.0 claim**, for A2 plus `spawn`: a program A2 types, whose
    spawned functions take only view-free `sink` parameters, is memory-safe,
    race-free and leak-free on every interleaving.  Milestone A3.0 proves it,
    and A3.1 for A2 with `Arc` (shares of view-free payloads, collected by
    reachability); A3.2–A3.6 extend the language and restate it (A3.5: a
    spawn runs the crossing check, `SendCheck`, and a race includes two
    threads changing one library handle's state, `CellRace`; A3.6: the start
    holds the module globals, `GlobsOK`, and what they reach is left at the
    end). -/
def Claim : Prop :=
  ∀ (P : Prog) (spawn : Nat → Bool) (G : Globs) (s : Stmt) (Δ : Ctx) (nv : Nat),
    ProgOK P → ProgCodes P → SpawnOK P spawn → GlobsOK P G →
    StmtT P (fun _ => none) [] s Δ → s.src = true → s.codesOK P → (∀ v ∈ s.vars, v < nv) →
    MemorySafe P spawn (Cfg.start G s nv) ∧ RaceFree P spawn (Cfg.start G s nv) ∧
      NoLeak P spawn (Cfg.start G s nv)

/-- The view of the initial configuration is A2's empty store. -/
theorem init_view (s : Stmt) (nv : Nat) :
    (Cfg.init s nv).view ⟨fun _ => none, nv, s⟩ = emptyMem nv := rfl

end A3
