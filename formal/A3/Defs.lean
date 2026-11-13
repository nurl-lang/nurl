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
  thread's step (Agora #755 item 1: the marking sweep, `Cfg.sweepD`, and
  the same thread's reaps of the orphans it marks, `CSettle`). The other shared blocks (`Locked`, `RwLocked`, `Atomic`,
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
  taken : Nat → Bool           -- Agora #810: which lock blocks `locked_take` emptied (`Mem.taken`)

/-- What A2's step runs on for thread `t`: the shared address space, the
    thread's own bindings. -/
def Cfg.view (C : Cfg) (t : Thread) : Mem :=
  { alloc := C.alloc, nid := C.nid, nv := t.nv, st := t.st, blk := C.blk, gl := C.gl, taken := C.taken }

/-- Thread `i`'s step written back: the address space to the configuration,
    the bindings and the statement to the thread. -/
def Cfg.put (C : Cfg) (i : Nat) (m : Mem) (s : Stmt) : Cfg :=
  { alloc := m.alloc, nid := m.nid, blk := m.blk, gl := m.gl, ths := C.ths.set i ⟨m.st, m.nv, s⟩,
    taken := m.taken }

/-- A3.1: the values the threads' slots hold. -/
def Cfg.vals (C : Cfg) (v : Val) : Prop :=
  ∃ (j : Nat) (t : Thread), C.ths[j]? = some t ∧ ∃ x o, t.st x = some ⟨o, some v⟩

/-- A3.6: the values the module globals hold. -/
def Cfg.globVals (C : Cfg) (v : Val) : Prop := ∃ g, C.gl g = some v

/-- The roots of the configuration's sweep: what the threads' slots hold
    (A3.1), and (A3.6) what the module globals hold, which every thread may
    read for as long as the program runs. -/
def Cfg.roots (C : Cfg) (v : Val) : Prop := C.vals v ∨ C.globVals v

/-- Agora #755 item 1: **the configuration's marking sweep**, A2's
    `Mem.sweepD` from the configuration's roots: every thread's slots and
    (A3.6) the module globals, which hold a share each until the process
    exits (so a global's block, a `Locked D` one too, is never an orphan).
    It ends every thread's step (`TStep.thread`; the count of a block's
    shares is over all threads).  A block nothing reaches is removed and its payload freed, but an
    orphan whose payload awaits its destructor (an `arc` block of a
    destructor value or of a drained `Vec` of them, or a lock block of a
    destructor value, its payload in it: `Cand`) is marked `dead`, its
    payload kept, for the thread whose step left it unreached to reap
    (`CSettle`). -/
noncomputable def Cfg.sweepD (C : Cfg) : Cfg :=
  { C with alloc := sweepAllocD C.roots C.blk C.alloc, blk := sweepBlkD C.roots C.blk }

/-- Agora #755 item 1: an orphan awaits its destructor in the configuration:
    some `dead` block still holds its payload (A2's `Orphan`, of the shared
    blocks every thread's view holds). -/
def Cfg.Orphan (C : Cfg) : Prop := ∃ k n f u p, C.blk k = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩

/-- Agora #755 item 1: **thread `i` reaps the orphans the marking sweep left**,
    each by a step of its own (`Step.reap`, on its view: the payload moves to
    a fresh slot of thread `i`, and a destructor frame of it goes to the
    thread's redex), each ended by the configuration's marking sweep, until
    no orphan is left; no other thread runs in between.  So the destructor
    runs on the thread whose step dropped the last share (A2's `Settle`, on
    a configuration), as nurlc's last share's drop does. -/
inductive CSettle (P : Prog) (i : Nat) : Cfg → Cfg → Prop
  | done {C : Cfg} : ¬ C.Orphan → CSettle P i C C
  | reap {C C'' : Cfg} {t : Thread} {m1 : Mem} {s1 : Stmt} :
      C.ths[i]? = some t → Step P (C.view t) t.s (.ok m1 s1) → ReapMem (C.view t) m1 →
      CSettle P i (C.put i m1 s1).sweepD C'' → CSettle P i C C''

/-- A program run from the empty store, on one thread (A2's `emptyMem`). -/
def Cfg.init (s : Stmt) (nv : Nat) : Cfg :=
  { alloc := fun _ => false, nid := 0, blk := fun _ => none, gl := fun _ => none,
    ths := [⟨fun _ => none, nv, s⟩], taken := fun _ => false }

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
  taken : Nat → Bool   -- Agora #810: which lock blocks the `make`s left taken (`Mem.taken`)

/-- No global: A3.0–A3.5's start. -/
def Globs.empty : Globs := ⟨fun _ => false, 0, fun _ => none, fun _ => none, fun _ => false⟩

/-- The store the globals' `make`s left, with no binding. -/
def Globs.mem (G : Globs) (nv : Nat) : Mem := ⟨G.alloc, G.nid, nv, fun _ => none, G.blk, G.gl, G.taken⟩

/-- A3.6: a program run with its module globals set, on one thread, which
    (as every thread it spawns) reads them through the configuration
    (`Cfg.gl`, `Cfg.view`). -/
def Cfg.start (G : Globs) (s : Stmt) (nv : Nat) : Cfg :=
  { alloc := G.alloc, nid := G.nid, blk := G.blk, gl := G.gl, ths := [⟨fun _ => none, nv, s⟩],
    taken := G.taken }

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
    -- (A2-drop.3a: and of no type that holds a destructor value: a `letd`
    -- of the spawned thread would run it there, which the race clause does
    -- not cover yet; stricter than nurlc, `CLAIM.md`)
    ∀ pt ∈ fn.params, pt.1 = .sink ∧ pt.2.holdsView = false ∧ pt.2.holdsDtor = false

/-- A3.1, Send: a share crosses to a new thread when its payload holds no
    views — `SpawnOK`'s question asked of `Ty.arc t`, unchanged.  Every A2
    type `arc t` meets it (`Ty.ok` asks it of the payload) ... (A3.3: a read
    guard, a share of a view, is of such a type too, and is `% NotSend`: the
    crossing check refuses it at run time, `NoGuard`, `spawn_guard`.) -/
theorem arc_spawnOK {t : Ty} (h : (Ty.arc t).ok = true) : (Ty.arc t).holdsView = false :=
  (Ty.ok_arc h).2

/-- ... and so does every share `arc_new` makes: its payload's type holds no
    views (`RhsT.arcNew`), whatever trees it owns. -/
theorem arc_spawnOK_viewFree {t : Ty} (h : t.holdsView = false) : (Ty.arc t).holdsView = false := h

/-- A3.2, Send: a lock share crosses to a new thread when its payload holds
    no views, `SpawnOK`'s question again; every A2 type `lk t` meets it
    (`Ty.ok` asks it of the payload, `RhsT.lockNew` of what moves in). -/
theorem lk_spawnOK {t : Ty} (h : (Ty.lk t).ok = true) : (Ty.lk t).holdsView = false :=
  (Ty.ok_lk h).2

/-- A3.5, Send: a library handle (a cell share) crosses to a new thread as a
    lock share does, `SpawnOK`'s question unchanged; what it may not do is
    leave an owner behind, which the crossing check asks at run time
    (`SendCheck`). -/
theorem cell_spawnOK {t : Ty} (h : (Ty.cell t).ok = true) : (Ty.cell t).holdsView = false :=
  (Ty.ok_cell h).2

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
  have hp := Ty.ok_cell_pay h
  simp only [Ty.lkPay] at hp
  simp [Ty.ok, (Ty.ok_cell h).1, (Ty.ok_cell h).2, Ty.lkPay, Ty.dtorFree, Ty.holdsView, hp]

/-- ... and so may a cell's state, which is a lock's payload (a handle that
    keeps another handle in its state, A3.5's second cut). -/
theorem cell_cell_ok {t : Ty} (h : (Ty.cell t).ok = true) : (Ty.cell (.cell t)).ok = true := by
  have hp := Ty.ok_cell_pay h
  simp only [Ty.lkPay] at hp
  simp [Ty.ok, (Ty.ok_cell h).1, (Ty.ok_cell h).2, Ty.lkPay, Ty.dtorFree, Ty.holdsView, hp]

/-- ... which `locked_new` takes (a library handle is Send). -/
theorem lockNew_cell {Γ Γ1 : Ctx} {F : List Var} {t : Ty} {y : Var} {Ey : Entry} {D : List Dep}
    (hy : Γ y = some Ey) (hl : Ey.live = true) (hty : Ey.ty = .cell t) (hvf : t.holdsView = false)
    (hfn : t.hasFn = false) (hpa : PushArg Γ F y Ey (.cell t) D Γ1) :
    RhsT Γ F (.lockNew (.cell t) y) ⟨.lk (.cell t), .own, true, [], [], false, false⟩ Γ1 :=
  RhsT.lockNew hy hl hty rfl ⟨hvf, hfn⟩ hpa

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
  have h := RhsT.taker (F := F) (a := .int) (b := .arc (.prod (.lk t) t)) ho rfl rfl (Or.inl rfl) hoF hpin hds
  have he : compE (tryReadE t) (.arc (.prod (.lk t) t)) = guardE t := by
    simp [compE, ownHeld, tryReadE, guardE]
  rw [he] at h
  exact h

/-- **`rw_try_read`, matched, is typed**: on `none` the other branch, on
    `some` `withRead`'s read scope under the guard moved out of the option
    (`tryRead_some`); the option's scope ends after both. -/
theorem _root_.A2.StmtT.withTryRead {P : Prog} {Γ Δs : Ctx} {F : List Var} {a o g y x : Var} {s e : Stmt}
    {Ea : Entry} {t : Ty} (hs : s.src = true) (he : e.src = true) (ho : Γ o = none) (hoF : o ∉ F)
    (ha : Γ a = some Ea) (hla : Ea.live = true) (hta : Ea.ty = .lk t) (hnc : t.hasCell = false) (hdf : t.dtorFree = true)
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
  refine StmtT.letv (by simp [Stmt.src, Stmt.readWith, hs, he]) ho hoF (RhsT.rwTryRead ha hla hta hnc hdf) ?_ hendo
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
    (hnone : StmtT P (setE Γ o tryWriteE) F e (exitScope x Δ)) (hendo : EndOK (exitScope x Δ) o)
    (hna : t.holdsDtor = true → x ∉ s.assigns := by lock_na) :
    StmtT P Γ F (Stmt.withTryWrite a o x s e) (exitScope o (exitScope x Δ)) := by
  refine StmtT.letv (by simp [Stmt.src, hs, he]) ho hoF (RhsT.rwTryWrite ha hla hta) ?_ hendo
  refine StmtT.ite he (by simp [Stmt.src, hs]) (ExprT.isl (upd_same _ _ _) rfl rfl) hnone ?_
  exact StmtT.withLock hs (by simp [setE, upd_ne _ _ hxo, hx]) hxF (by simp [setE, upd_ne _ _ hao, ha])
    hla (Or.inl hta) hb hend hroot has hlive hna

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
    (hds : DtorSafe Γ .drop false x) (hdf : u.dtorFree = true) :
    StmtT P Γ F (.edit true y (.trunc i))
      (setE (killThru (.trunc i) (.vec u) [⟨x, .self⟩] Γ) y ⟨.vec u, .bor, true, [⟨x, .self⟩], [], false, false⟩) := by
  have hl : lockE (.vec u) = ⟨.vec u, .own, true, [], [], false, false⟩ := by simp [lockE]
  rw [hl] at hx
  refine StmtT.editB (t := u) hy rfl rfl rfl huv hyF (EditArg.trunc hi) (fun _ h => by cases h) hy rfl
    (by simp [memDeps, Kind.isName]) ?_ (fun _ => hdf)
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
    (fun _ _ _ _ => ⟨by simp [Stmt.movedFirst], by simp [Stmt.assigns]; exact fun h => hzc h.symm⟩)

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
    (hnc : t.hasCell = false) (hdf : t.dtorFree = true)
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
  exact StmtT.letv rfl hg hgF (RhsT.rwRead ha hla hta hnc hdf) h2
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
    `mem_send_check` counts). -/
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
    (fun _ => by simp [Stmt.callOut, Stmt.assigns, hxc, Ne.symm hzx])
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
    with a result, through a cell share an owner or (A3.5's third cut) a
    borrowed root holds, is the same form: `Entry.lockOf`.) -/
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
    (fun _ => by simp [Stmt.callOut, Stmt.assigns, hxc, Ne.symm hzx])
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
    (hvd : t.dtorFree = true)
    (hpush : PushArg Γ F y Ey t D Γ1)
    (hb : Γ b = none) (hx : Γ x = none) (hbx : b ≠ x) (hbF : b ∉ F) (hxF : x ∉ F)
    (hub : Unnamed Γ b) (hux : Unnamed Γ x) :
    StmtT P Γ F (Stmt.lockedSet t a b x y) Γ1 := by
  have hay' : a ≠ y := by
    intro h; subst h; rw [ha] at hy; cases hy
    rcases hta with h | h <;> rw [hty] at h <;> have := congrArg sizeOf h <;> simp at this
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
    (fun hd => absurd hd (by rw [Ty.holdsDtor_eq_not_free, hvd]; simp))
  rw [exitScope_setE hbx' hux'] at hwl
  have hlet := StmtT.letv (P := P) (x := b) (s := .withLock a x (.assign x (.lockTake b))) rfl hb hbF
    (RhsT.lockNew hy hly hty (Ty.lkPay_of_free hvd) htv hpush) hwl ((hu1b.setE_nil hEb).endOK)
  rw [exitScope_setE h1b hu1b] at hlet
  exact hlet

/-- **The check comes first**: a value that fails it (a slot left behind holds
    a share of a cell it holds) makes `locked_set` panic before the lock is
    touched, the store as it was (`locked_new`'s check), as the runtime's
    `mem_send_check` panics before `mutex_lock`. -/
theorem lockedSet_check {P : Prog} {m m1 : Mem} {t : Ty} {a b x y : Var} {v : Val}
    (ht : TakeVal m y v m1) (hfail : ¬ SendCheck m1.blk [v] m1.st) :
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
  RhsT.lockNew hy hly hty rfl ⟨rfl, rfl⟩ PushArg.int

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
  StmtT.letv hs hr hrF (RhsT.lockRestore hm hlm htm hu hlu htu PushArg.int rfl) hb hend

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
    (hpush : StmtT P (exitScope x Δs) F (.push v e) Δ) (hende : EndOK Δ e)
    (hna : t.holdsDtor = true → x ∉ s.assigns := by lock_na) :
    StmtT P Γ F (Stmt.withLockElem v i e x s) (exitScope e Δ) := by
  have hkv : A2.kill .replace false v Γ v = some Ev := by simp [A2.kill, hv, killE_nohit hvv]
  have hpop := RhsT.pop (F := F) (t := .lk t) hkv hlv htv (Or.inl hmv) hvF hdd
  have hpe : popE v Ev (.lk t) = elemLockE t Ev := rfl
  rw [hpe] at hpop
  have hex : A2.setE (A2.kill .drop t.holdsView v (A2.kill .replace false v Γ)) e (elemLockE t Ev) x = none := by
    simp [A2.setE, A2.kill, upd_ne _ _ hxe, hx]
  refine StmtT.withElem (by simp [Stmt.src, hs]) he heF hv hmv hi hpin hds hpop ?_ hpush hende ?_ rfl
  · exact StmtT.withLock hs hex hxF (upd_same _ _ _) rfl (Or.inl rfl) hb hend rfl hes hlive hna
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
    (hendw : EndOK Δ w) (hendl : EndOK (exitScope w Δ) l)
    -- (A2-drop.3a: the struct's other field holds no destructor value: it is
    -- put back only after the body, so a panic there would drop it)
    (hbd : b.holdsDtor = false)
    (hna : t.holdsDtor = true → x ∉ s.assigns := by lock_na) :
    StmtT P Γ F (Stmt.withLockField y l w x s) (exitScope l (exitScope w Δ)) := by
  have hcl : compE Ey (.lk t) = outE (.lk t) .own := by
    simp [compE, ownHeld, Ty.holdsView, htv, outE]
  refine StmtT.unpair (a := .lk t) (b := b) (by simp [Stmt.src, hs]) hy hly hcy (Or.inl hty) hyF hl hw hlw hlF hwF ?_
    hpin hds hendw hendl (fun h => by simp [Ty.holdsDtor] at h) (fun h => by rw [hbd] at h; cases h)
  rw [hcl]
  refine StmtT.seq rfl ?_ hput
  refine StmtT.withLock hs (by simp [A2.setE, A2.kill, upd_ne _ _ hxw, upd_ne _ _ hxl, upd_ne _ _ hxy, hx]) hxF
    (show _ = some (outE (.lk t) .own) by simp [A2.setE, upd_ne _ _ hlw]) rfl (Or.inl rfl) hb hend
    rfl hls hlive hna

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
    (hend : EndOK Δ x) (hlive : ∃ E, Δ x = some E ∧ E.live = true) (hendh : EndOK (exitScope x Δ) h)
    (hna : t.holdsDtor = true → x ∉ s.assigns := by lock_na) :
    StmtT P Γ F (Stmt.lockGlobal h x g t s) (exitScope h (exitScope x Δ)) :=
  StmtT.letv hs hh hhF (RhsT.glob rfl htok)
    (StmtT.withLock hs (by simp [setE, upd_ne _ _ hxh, hx]) hxF (upd_same _ _ _) rfl (Or.inl rfl) hb hend
      rfl hhs hlive hna) hendh

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

/-! ### A3.5's third cut: a library handle used through a borrow

A lent cell share is the share (`lendOf`), as the runtime's pointer copy is.
So a library function that takes its handle `in` (`pncounter_inc PNCounter
c__h …`) changes the state through it — a `withCell` through the borrowed
root, `Entry.lockOf` — and copies it — `cellClone` of a borrow, as
`PNCounter_share` copies a handle it was lent.  A borrow never leaves its
thread: what a spawn moves is owned (`MoveArgs`) and holds no view
(`SpawnOK`), and what goes into a lock block is owned too (`PushArg`).  And
while a borrow is live its owner is in the store (A2's `MInv.cell_owned`: a
lent cell share lands, through its dependencies, in an owned tree,
`CellLanded`).  So the crossing check counts owners only, as the runtime's
does (`SendCheck`): where no owner is left behind no live borrow is, and a
dead borrow still bound is not counted (`sendCheck_dead_borrow_ok`).  A3's
`CellInv` counts owners, and a live borrow through its owner
(`CellInv.live_home`). -/

/-- A library's `in` handle parameter is a borrowed root (`rootb`), live for
    the call, whose cell share a `withCell` checks out (`Entry.lockOf`; the
    runtime's `pncounter_inc` changes the state through the handle it was
    lent). -/
theorem paramE_cell_lockOf (ps : List (PMode × Ty)) (t : Ty) :
    (paramE ps (.inp, .cell t)).lockOf t ∧ (paramE ps (.inp, .cell t)).mode.isRoot = true ∧
      (paramE ps (.inp, .cell t)).live = true :=
  ⟨Or.inr rfl, rfl, rfl⟩

/-- **The in-place change through a borrowed handle is typed**
    (`Stmt.withCell` on an `in` parameter): A3.2's `withLock`, whose
    faithfulness premises hold of a borrowed root the body does not name. -/
theorem _root_.A2.StmtT.withCellIn {P : Prog} {Γ Δ : Ctx} {F : List Var} {a x : Var} {s : Stmt}
    {ps : List (PMode × Ty)} {t : Ty} (ha : Γ a = some (paramE ps (.inp, .cell t)))
    (hsrc : s.src = true) (hx : Γ x = none) (hxF : x ∉ F)
    (hs : StmtT P (setE Γ x (lockE t)) F s Δ) (hend : EndOK Δ x) (has : a ∉ s.vars)
    (hxl : ∃ E, Δ x = some E ∧ E.live = true)
    (hna : t.holdsDtor = true → x ∉ s.assigns := by lock_na) :
    StmtT P Γ F (Stmt.withCell a x s) (exitScope x Δ) :=
  StmtT.withLock hsrc hx hxF ha (paramE_cell_lockOf ps t).2.2 (paramE_cell_lockOf ps t).1 hs hend
    (paramE_cell_lockOf ps t).2.1 has hxl hna

/-- ... and so is a copy of it (`PNCounter_share` of a handle the function was
    lent): a new owner, on the borrow's thread, which the crossing check then
    counts with the caller's. -/
theorem cellClone_in {Γ : Ctx} {F : List Var} {a : Var} {ps : List (PMode × Ty)} {t : Ty}
    (ha : Γ a = some (paramE ps (.inp, .cell t))) :
    RhsT Γ F (.cellClone a) ⟨.cell t, .own, true, [], [], false, false⟩ Γ :=
  .cellClone ha rfl rfl

/-- The crossing check counts owners, as the runtime's does: a slot left behind
    that is an owner of a crossing cell fails it ... -/
theorem sendCheck_owner_left {B : Nat → Option Blk} {vs : List Val} {st : Var → Option Slot} {k : Nat}
    {v : Val} (hv : v ∈ vs) (hs : Sub (.cell k) v) {y : Var} {w : Val} (hy : st y = some ⟨true, some w⟩)
    (hw : Sub (.cell k) w) : ¬ SendCheck B vs st :=
  fun h => h.1 k ⟨v, hv, hs⟩ y w hy hw

/-- ... and **a dead borrow left behind does not** (`: PNCounter c …  : f c  …
    spawn (sink c)`): the spawn moves the owner `c`, which kills the borrow
    `f`, whose slot still holds the share until its scope ends.  The model's
    check passes, as the runtime's does.  (A live borrow left behind has its
    owner left behind too, `MInv.cell_owned`, which fails the check.) -/
theorem sendCheck_dead_borrow_ok {B : Nat → Option Blk} {c f : Var} {k : Nat}
    (hng : NoGuard B [.cell k]) :
    let st : Var → Option Slot := fun y =>
      if y = c then some ⟨true, some (.cell k)⟩ else if y = f then some ⟨false, some (.cell k)⟩ else none
    MoveArgs st [c] [.cell k] (upd st c (some ⟨true, none⟩)) ∧
      SendCheck B [.cell k] (upd st c (some ⟨true, none⟩)) := by
  intro st
  refine ⟨MoveArgs.cons (by simp [st]) MoveArgs.nil, fun k' _ y w hy _ => ?_, hng⟩
  simp only [upd, st] at hy
  by_cases hyc : y = c
  · rw [ite_eq_left hyc] at hy; cases hy
  · rw [ite_eq_right hyc, ite_eq_right hyc] at hy
    by_cases hyf : y = f
    · rw [ite_eq_left hyf] at hy; cases hy
    · rw [ite_eq_right hyf] at hy; cases hy

/-! ### A3.1: shares in a slice's elements

A3.1's first cut asked a slice's element type to hold no share (`Ty.ok (slice
t)`, `RhsT.view`).  That is lifted, as A3.2's second cut lifted it for a lock's
payload: a slice of `Arc`s, of locks, of library handles, of `send` and `sync`
closures is typed, and `sat` lends its elements as `vec_at` lends a `Vec`'s
(`out_sat`: the viewed node holds the shares its type says, `MInv.dataAt_shares`).
It lets no two threads reach one block through a slice: a slice is a view,
which no crossing takes (`slice_not_send`), so it and what it lends stay on
the thread that took it.  What its elements are lent is what a `Vec`'s are:
an `Arc` share or a lock share, which are Sync, or (A3.5's third cut) a cell
share, a borrow whose owner is on the thread (`MInv.cell_owned`) — the node
it views is in that thread's owned tree, or a frozen payload's, which holds
no cell share (`MInv.noCellPay`). -/

/-- A slice of shares is an A2 type ... -/
theorem slice_share_ok {t : Ty} (h : t.ok = true) (hv : t.holdsView = false) (hvd : t.vecD = false) :
    (Ty.slice t).ok = true := by
  simp [Ty.ok, h, hv, hvd]

/-- ... so a view of a `Vec` of `Arc`s (or of locks, or of library handles) is
    typed (`slice_from_vec`) ... -/
theorem view_share {Γ : Ctx} {F : List Var} {y : Var} {E : Entry} {t : Ty} (hy : Γ y = some E)
    (hl : E.live = true) (hty : E.ty = .vec t) (hv : t.holdsView = false) :
    RhsT Γ F (.view y) ⟨.slice t, .bor, true, derive y E .view, E.held, false, false⟩ Γ :=
  RhsT.view hy hl hty hv

/-- ... and no crossing takes it: a slice holds a view, so it is no spawn's
    argument (`SpawnOK`), no lock's, channel's or `Arc`'s value
    (`Ty.ok (lk _)`, `RhsT.arcNew`), and no global (`Ty.sync`). -/
theorem slice_not_send (t : Ty) : (Ty.slice t).holdsView = true := rfl

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
  cases h with | arcNew _ _ _ _ hp _ _ => exact absurd hp.1 (by simp [Ty.holdsView])

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
  have := (hpar _ hin).2.1
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
  | arcNew _ _ _ _ hc _ => cases q <;> simp_all [Ty.hasCell, Ty.dtorFree, Ty.dnest, Cross.drops]

/-- h340 (`closure_sent_on_a_channel_captures_a_kept_handle`): a channel's
    element may hold a library handle (A3.5's second cut), so a closure sent on
    one is any but `any`: Send (`send`, which may capture a handle), Sync or
    bare.  The handle moves with the closure, and the send's crossing check
    panics if an owner of it is left behind (`chanSend_kept`) ... -/
theorem chan_fn {ms : List Nat} {q : Cross} :
    (Ty.lk (.prod (.vec (.fn ms q)) .int)).ok = true ↔ q = .send ∨ q = .sync ∨ q = .bare := by
  cases q <;> simp [Ty.ok, Ty.holdsView, Ty.dtorFree, Ty.hasDtor, Ty.lkPay, Ty.hasArc, Ty.dnest]

/-- ... and so is one a lock keeps (A3.2), which one thread at a time runs. -/
theorem lockNew_fn {Γ Γ1 : Ctx} {F : List Var} {ms : List Nat} {q : Cross} {y : Var} {E : Entry}
    (h : RhsT Γ F (.lockNew (.fn ms q) y) E Γ1) : q = .send ∨ q = .sync ∨ q = .bare := by
  cases h with
  | lockNew _ _ _ hp _ => cases q <;> simp_all [Ty.holdsView, Ty.hasFn, Ty.dtorFree, Ty.lkPay, Ty.hasDtor, Ty.dnest]

/-- A Send closure, which may capture a library handle, is a lock's value:
    `locked_new` takes it (A3.5's second cut; A3.5b's gap) ... -/
theorem lockNew_send {Γ Γ1 : Ctx} {F : List Var} {ms : List Nat} {y : Var} {Ey : Entry} {D : List Dep}
    (hy : Γ y = some Ey) (hl : Ey.live = true) (hty : Ey.ty = .fn ms .send)
    (hpa : PushArg Γ F y Ey (.fn ms .send) D Γ1) :
    RhsT Γ F (.lockNew (.fn ms .send) y) ⟨.lk (.fn ms .send), .own, true, [], [], false, false⟩ Γ1 :=
  RhsT.lockNew hy hl hty rfl ⟨rfl, rfl⟩ hpa

/-- ... and a channel's element: `chan_send` sends it. -/
theorem chanSend_send {Γ Γ1 : Ctx} {F : List Var} {ms : List Nat} {a y : Var} {Ea Ey : Entry} {D : List Dep}
    (ha : Γ a = some Ea) (hla : Ea.live = true) (htya : Ea.ty = .lk (.prod (.vec (.fn ms .send)) .int))
    (hy : Γ y = some Ey) (hl : Ey.live = true) (hty : Ey.ty = .fn ms .send)
    (hpa : PushArg Γ F y Ey (.fn ms .send) D Γ1) : RhsT Γ F (.chanSend a y) intE Γ1 :=
  RhsT.chanSend ha hla (htya ▸ Ty.chanOf_plain _) hy hl hty hpa

/-- A Send closure that captured a library handle crosses a spawn only with
    every other owner of the handle's state: the crossing check counts what
    the moved values hold, closures' environments included (`Sub.pkg`). -/
theorem sendCheck_env {B : Nat → Option Blk} {vs : List Val} {st' : Var → Option Slot} (h : SendCheck B vs st') {v : Val}
    (hv : v ∈ vs) {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val} {cs : List (Var × PMode × Ty)}
    (hs : Sub (.pkg fs te ms e cs) v) {k : Nat} (hk : Sub (.cell k) e) :
    ∀ x w, st' x = some ⟨true, some w⟩ → ¬ Sub (.cell k) w :=
  h.1 k ⟨v, hv, (Sub.pkg hk).trans hs⟩

/-- **A Sync closure in an `Arc`**: `arc_new` takes it (its type holds no
    view, no closure that holds bindings by name and no library handle) ... -/
theorem arcNew_sync {Γ Γ1 : Ctx} {F : List Var} {ms : List Nat} {y : Var} {Ey : Entry} {D : List Dep}
    (hy : Γ y = some Ey) (hl : Ey.live = true) (hty : Ey.ty = .fn ms .sync)
    (hpa : PushArg Γ F y Ey (.fn ms .sync) D Γ1) :
    RhsT Γ F (.arcNew (.fn ms .sync) y) ⟨.arc (.fn ms .sync), .own, true, [], [], false, false⟩ Γ1 :=
  RhsT.arcNew hy hl hty (Or.inl rfl) ⟨rfl, rfl⟩ rfl hpa

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
    (hk : StmtT P (setE Γ x (recvRes c Ec (callRes Γ sig [c]))) F k Δ) (hend : EndOK Δ x)
    (hdk : sig.resOwn = true → sig.resTy.holdsDtor = true → x ∈ k.movedFirst ∧ x ∉ k.assigns) :
    StmtT P Γ F (.callc x c j [] k) (exitScope x Δ) := by
  have hcT := callT_recv (F := F) hσ (by rw [hps, hty]) hc hl hn hnt
  have hmut : mutNames Γ [c] = [] := by
    have : nameDeps (argE Γ c).vdeps = [] := by
      simp only [nameDeps, argE, hc, Option.getD_some, List.filter_eq_nil_iff]
      intro d hd; simp [hn d hd]
    simp [mutNames, argNames, this]
  have hpost := callPost_recv (Γ := Γ) (c := c) hps hmut
  rw [hpost] at hcT
  exact StmtT.callc hks hx hxF hc (by rw [hty]; rfl) hj hσ (by rw [hps, hty]; rfl) hout hcT (fun _ h => by cases h) hk hend
    hnt hdk

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
    (hend : EndOK Δ x) (hendg : EndOK (exitScope x Δ) g)
    (hdk : sig.resOwn = true → sig.resTy.holdsDtor = true → x ∈ k.movedFirst ∧ x ∉ k.assigns) :
    StmtT P Γ F (.letv g (.arcGet a) (.callc x g j [] k)) (exitScope g (exitScope x Δ)) :=
  StmtT.letv hks hg hgF (arcGet_sync ha rfl rfl)
    (StmtT.callc_recv hks (by simp [setE, upd_ne _ _ hxg, hx]) hxF (upd_same _ _ _) rfl rfl hj hσ hps hout
      hnt getE_own_noName hk hend hdk) hendg

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
    (hds : DtorSafe Γ .replace false y) (hty : Ey.ty = .fn ms q) (hqd : q.drops = false) :
    RhsT Γ F (.var y) ⟨.fn ms .any, .own, true, [], Ey.held, false, false⟩
      (setE (kill .replace false y Γ) y { Ey with live := false, dtor := false }) :=
  RhsT.moveUp hy hl hm hyF hp hds hty (Cross.le_any q hqd)

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
    (hend : EndOK Δ x) (hendg' : EndOK (exitScope x Δ) g') (hendg : EndOK (exitScope g' (exitScope x Δ)) g)
    (hdk : sig.resOwn = true → sig.resTy.holdsDtor = true → x ∈ k.movedFirst ∧ x ∉ k.assigns) :
    StmtT P Γ F (.letv g (.arcGet a) (.letv g' (.var g) (.callc x g' j [] k)))
      (exitScope g (exitScope g' (exitScope x Δ))) := by
  refine StmtT.letv hks hg hgF (arcGet_sync ha rfl rfl) ?_ hendg
  refine StmtT.callcUp (upd_same _ _ _) rfl rfl rfl hle hks (by simp [setE, upd_ne _ _ hgg, hg'])
    hg'F ?_ hendg'
  refine StmtT.callc_recv hks (by simp [setE, upd_ne _ _ hxg', upd_ne _ _ hxg, hx]) hxF (upd_same _ _ _) rfl rfl
    hj hσ hps hout hnt ?_ hk hend hdk
  exact getE_own_noName

/-! A3.5b: a closure that changes a capture it moved in (an accumulator).  The
moved-in capture is the environment's own state.  A call that lends the code the
environment (`callc`: a copy in a fresh slot, `envMem`; the code changes nothing
through a borrow, `Implements.env_lent`) reads it only.  The owner of a `send`
closure changes it by handing the environment over (A2-envhand, `StmtT.callcE`,
below: `accum_hand`), which no `sync` closure allows (`callcE_not_sync`).  What
several threads may change at once is the state in a share the environment
holds, which synchronises itself: an `Atomic` (or a `Locked`) moved in. -/

/-- The accumulator's environment, an `Atomic` (a lock share of an integer
    block), fits `sync`: a lock share is Sync, so an `Arc` keeps the closure
    and several threads call it ... -/
theorem accum_sync : Cross.sync.Fits (.lk .int) [] :=
  ⟨fun _ => ⟨rfl, rfl⟩, fun _ => rfl, fun h => absurd h (by decide), fun _ => rfl⟩

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
    `Cross`).  No bound is `bare`: that class (no share at all) is the
    model's, not a trait's. -/
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
    object at the bound, `fn ms b.cross`, taken lent (`inp`: the receiver
    `StmtT.callc` asks of a call through a `fn ms q` is `(inp, fn ms q)`; of
    one through a destructor type over it, Agora #651, that type, so no
    trait's method is called through one: `callc_bound`) or,
    A2-envhand, `inout` (a method that changes the box, `StmtT.callcE`). -/
def TraitAt (P : Prog) (ms : List Nat) (b : TraitBound) : Prop :=
  ∀ (j σ : Nat), ms[j]? = some σ → ∃ sig : Fn, P[σ]? = some sig ∧
    ∃ pm, pm ≠ .sink ∧ sig.params.head? = some (pm, .fn ms b.cross)

/-- What a bound promises of each impl's type `te` (a box captures nothing by
    name, `cs = []`): with no bound, only what the environment of every
    package of a class that does not drop is asked, to hold no destructor
    value (A2-drop.3c; no trait's object is of the dropping class) ... -/
theorem TraitBound.fits_none (te : Ty) (cs : List (Var × PMode × Ty)) (hd : te.holdsDtor = false) :
    TraitBound.none.cross.Fits te cs :=
  Cross.fits_any te cs hd

/-- ... with `: Send`, also that the box holds no view (nothing of the thread
    that made it) and nothing is captured by name ... -/
theorem TraitBound.fits_send {te : Ty} {cs : List (Var × PMode × Ty)} :
    TraitBound.send.cross.Fits te cs ↔ (te.holdsView = false ∧ cs = []) ∧ te.holdsDtor = false :=
  ⟨fun h => ⟨h.1 rfl, h.2.2.2 rfl⟩,
    fun h => ⟨fun _ => h.1, fun h' => absurd h' (by decide), fun h' => absurd h' (by decide), fun _ => h.2⟩⟩

/-- ... and with `: Send Sync`, also no library handle (a cell share, A3.5,
    is not Sync). -/
theorem TraitBound.fits_sendSync {te : Ty} {cs : List (Var × PMode × Ty)} :
    TraitBound.sendSync.cross.Fits te cs ↔
      ((te.holdsView = false ∧ cs = []) ∧ te.hasCell = false) ∧ te.holdsDtor = false :=
  ⟨fun h => ⟨⟨h.1 rfl, h.2.1 rfl⟩, h.2.2.2 rfl⟩,
    fun h => ⟨fun _ => h.1.1, fun _ => h.1.2, fun h' => absurd h' (by decide), fun _ => h.2⟩⟩

/-- A call through a package asks its receiver to be a package, `fn ms q`
    (or, Agora #651, a destructor type over one: a closure of the dropping
    class), whose method `j` is an interface that takes it at its type. -/
theorem _root_.A2.StmtT.callc_recv_at {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat}
    {zs : List Var} {k : Stmt} {Ec : Entry} (h : StmtT P Γ F (.callc x c j zs k) Δ) (hc : Γ c = some Ec) :
    ∃ ms q σ sig, Ec.ty.undtor = .fn ms q ∧ ms[j]? = some σ ∧ P[σ]? = some sig ∧
      sig.params.head? = some (.inp, Ec.ty) := by
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
    (h : StmtT P Γ F (.callc x c j zs k) Δ) (hc : Γ c = some Ec) (hty : Ec.ty.undtor = .fn ms q)
    (hb : TraitAt P ms b) : Ec.ty = .fn ms q ∧ q = b.cross := by
  -- (Agora #651: a receiver bound at a destructor type over the trait's
  -- object type is no receiver of the trait's methods: the interface takes
  -- the object's type itself)
  obtain ⟨ms', q', σ, sig, hty', hj, hσ, hhd⟩ := h.callc_recv_at hc
  rw [hty] at hty'; cases hty'
  obtain ⟨sig', hσ', pm, _, hhd'⟩ := hb j σ hj
  rw [hσ] at hσ'; cases hσ'
  rw [hhd] at hhd'
  simp only [Option.some.injEq, Prod.mk.injEq] at hhd'
  have he : Ec.ty = .fn ms b.cross := hhd'.2
  rw [he] at hty
  have hq : b.cross = q := by cases hty; rfl
  exact ⟨by rw [he, hq], hq.symm⟩

/-- So a trait object packed at another class than its trait's bound is inert:
    no method of it is called. -/
theorem callc_not_at {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var}
    {k : Stmt} {Ec : Entry} {ms : List Nat} {q : Cross} {b : TraitBound} (hb : TraitAt P ms b)
    (hc : Γ c = some Ec) (hty : Ec.ty.undtor = .fn ms q) (hq : q ≠ b.cross) :
    ¬ StmtT P Γ F (.callc x c j zs k) Δ :=
  fun h => hq (h.callc_bound hc hty hb).2

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
    (hk : Sub (.cell k) e) {y : Var} {w : Val} (hy : st' y = some ⟨true, some w⟩)
    (hw : Sub (.cell k) w) {vs' : List Val} {st'' : Var → Option Slot} (hm' : MoveArgs st args vs' st'')
    {B : Nat → Option Blk} : ¬ SendCheck B vs' st'' := by
  obtain ⟨rfl, rfl⟩ := hm.det hm'
  exact fun h => sendCheck_env h hv hs hk y w hy hw

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
    (hdf : τ.dtorFree = true)
    {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val} {cs : List (Var × PMode × Ty)}
    (hs : Sub (.pkg fs te ms e cs) v) : Cross.send.Fits te cs := by
  induction hw with
  | int => cases hs
  | view => cases hs
  | node _ ih =>
    cases hs with
    | child he h => exact ih _ he (by simpa [Ty.holdsView] using hhv) (by simpa using hdf) h
  | pair _ _ iha ihb =>
    simp only [Ty.holdsView, Bool.or_eq_false_iff] at hhv
    simp only [Ty.dtorFree_prod, Bool.and_eq_true] at hdf
    cases hs with
    | fst h => exact iha hhv.1 hdf.1 h
    | snd h => exact ihb hhv.2 hdf.2 h
  | inl _ ih =>
    simp only [Ty.holdsView, Bool.or_eq_false_iff] at hhv
    simp only [Ty.dtorFree_sum, Bool.and_eq_true] at hdf
    cases hs with | inl h => exact ih hhv.1 hdf.1 h
  | inr _ ih =>
    simp only [Ty.holdsView, Bool.or_eq_false_iff] at hhv
    simp only [Ty.dtorFree_sum, Bool.and_eq_true] at hdf
    cases hs with | inr h => exact ih hhv.2 hdf.2 h
  | pkg _ hq ih =>
    obtain ⟨hv, _, hcs⟩ := hq.send hhv
    have hte := hq.2.2.2 (by simpa using hdf)
    cases hs with
    | refl => exact TraitBound.fits_send.mpr ⟨⟨hv, hcs⟩, hte⟩
    | pkg h => exact ih hv (by rw [Ty.holdsDtor_eq_not_free] at hte; simpa using hte) h
  | arc _ _ => cases hs
  | lk => cases hs
  | cell => cases hs
  | dtor _ _ ih => simp [Ty.dtorFree] at hdf

/-- So what a spawned function takes holds no trait object but one whose box
    `: Send` admits: none whose box holds a view, none of a trait the spawn's
    type checks could not see into. -/
theorem spawn_pkgs_send {P : Prog} {spawn : Nat → Bool} (hS : SpawnOK P spawn) {f : Nat}
    (hsp : spawn f = true) {fn : Fn} (hf : P[f]? = some fn) {pt : PMode × Ty} (hin : pt ∈ fn.params)
    {v : Val} (hw : WFv pt.2 v) {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val}
    {cs : List (Var × PMode × Ty)} (hs : Sub (.pkg fs te ms e cs) v) : Cross.send.Fits te cs := by
  obtain ⟨fn', hf', -, hpar⟩ := hS f hsp
  rw [hf] at hf'; cases hf'
  exact hw.noView_fits (hpar pt hin).2.1
    (by have := (hpar pt hin).2.2; rw [Ty.holdsDtor_eq_not_free] at this; simpa using this) hs

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
    {j : Nat} {zs : List Var} {k : Stmt} {Ec : Entry} (hc : Γ c = some Ec) (hty : Ec.ty.undtor = .fn ms q) :
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
* *An `inout` receiver.*  A2's call through a package that lends its code the
  environment (`callc`, a copy in a fresh slot, `envMem`) takes no interface
  with an `inout` receiver (`callc_not_inout`); a method that changes the box
  is called with the box handed over (A2-envhand, `StmtT.callcE`), through an
  owner only.  A borrow of what an `Arc` or a read guard lends is no `inout`
  argument of any function (`paramOK_inout_not_bor`), nor a hand-over's
  receiver (`callcE_not_bor`, h364). -/

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
theorem TraitBound.holds_fn {b : TraitBound} {ms : List Nat} {q : Cross}
    (hqd : q.drops = false) : b.Holds (.fn ms q) ↔ q.Le b.cross := by
  cases b <;> cases q <;> simp_all [TraitBound.Holds, TraitBound.cross, Ty.holdsView, Ty.hasCell, Cross.Le,
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
    ∃ ms q σ sig, Ec.ty.undtor = .fn ms q ∧ ms[j]? = some σ ∧ P[σ]? = some sig ∧
      ∃ t, sig.params.head? = some (.inp, t) := by
  obtain ⟨ms, q, σ, sig, hty, hj, hσ, hhd⟩ := h.callc_recv_at hc
  exact ⟨ms, q, σ, sig, hty, hj, hσ, _, hhd⟩

/-- ... so a method whose interface takes the receiver `inout` (h364–h366's
    `rename`, which changes the box) is called through no object by `callc`,
    which lends the code a copy of the environment (`envMem`): it is called
    with the box handed over (A2-envhand, `StmtT.callcE`). -/
theorem callc_not_inout {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var}
    {k : Stmt} {Ec : Entry} {ms : List Nat} {q : Cross} {σ : Nat} {sig : Fn} (hc : Γ c = some Ec)
    (hty : Ec.ty.undtor = .fn ms q) (hj : ms[j]? = some σ) (hσ : P[σ]? = some sig) {b : Eff} {t : Ty}
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

/-! ### A2-envhand: the environment handed over, across threads

A call whose code changes the package's environment (an accumulator's moved-in
count, a trait object's `inout` method) hands the environment over
(`StmtT.callcE`): it moves out of the package into a binding the code takes
`inout`, and back.  Two things keep such a call to the one thread that owns the
package:

* *an owner*: the package is an owner that may be replaced (`canDo .replace`),
  never a borrow, so never what an `Arc` or a read guard lends, nor a copy of
  that (h364's rule stays: `callcE_not_bor`);
* *the class*: the package's class is at least `send`, or (Agora #609, the
  consuming hand-over) the dropping class, which crosses nowhere (`callcE_send`): a
  `sync` or `bare` one has no such call (`callcE_not_sync`), so a package
  whose environment is handed over is no `Arc`'s payload (`callcE_not_arc`)
  and no object of a `: Send Sync` trait (`callcE_not_sendSync`).  Two threads
  never call it at once: h342's shape, with the state inside the closure, is
  refused by the type. -/

/-- A hand-over takes the package as an owner, at a class at least `send`,
    through an interface that takes it `inout` and nothing else; or (Agora
    #609) owned, a package of the dropping class that holds nothing, through
    an interface that takes it `sink` and nothing else. -/
theorem _root_.A2.StmtT.callcE_recv_at {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat}
    {zs : List Var} {k : Stmt} {Ec : Entry} (h : StmtT P Γ F (.callcE x c j zs k) Δ) (hc : Γ c = some Ec) :
    ∃ ms q σ sig, Ec.ty.undtor = .fn ms q ∧ canDo Ec.mode .replace ∧ ms[j]? = some σ ∧
      P[σ]? = some sig ∧
      ((∃ b, sig.params = [(.inout b, .fn ms q)] ∧ Ec.ty = .fn ms q ∧ Cross.send.Le q) ∨
        (sig.params = [(.sink, Ec.ty)] ∧ q.drops = true)) := by
  generalize hs : Stmt.callcE x c j zs k = s at h
  induction h generalizing Ec with
  | callcE _ _ _ hc' hty hcan hq hj hσ hsp =>
    cases hs
    rw [hc] at hc'; cases hc'
    exact ⟨_, _, _, _, hty, hcan, hj, hσ,
      hsp.imp (fun h => ⟨_, h⟩) (fun h => ⟨h.1, h.2.2.2.2.1⟩)⟩
  | sub hw _ _ ih =>
    obtain ⟨hn, hwe⟩ := hw.1 c
    obtain ⟨E0, hE0⟩ : ∃ E0, _ = some E0 :=
      Option.ne_none_iff_exists'.mp fun h0 => absurd (hn.mpr h0) (by rw [hc]; simp)
    have hw0 := hwe Ec E0 hc hE0
    rw [← hw0.ty, ← hw0.mode]
    exact ih hE0 hs
  | _ => cases hs

/-- **A package whose environment is handed over is at most Send** (Send, not
    Sync): the class of a hand-over's receiver is `send` or `any`, or (Agora
    #609) the dropping class, which is below neither and crosses nowhere. -/
theorem callcE_send {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var}
    {k : Stmt} {Ec : Entry} {ms : List Nat} {q : Cross} (h : StmtT P Γ F (.callcE x c j zs k) Δ)
    (hc : Γ c = some Ec) (hty : Ec.ty = .fn ms q) : Cross.send.Le q ∨ q.drops = true := by
  obtain ⟨ms', q', _, _, hty', _, _, _, hbr⟩ := h.callcE_recv_at hc
  rw [hty] at hty'; cases hty'
  rcases hbr with ⟨_, _, _, hq⟩ | ⟨_, hd⟩
  · exact Or.inl hq
  · exact Or.inr hd

/-- ... so a `sync` or `bare` package's environment is never handed over: what
    several threads may hold at once is changed by no call through it. -/
theorem callcE_not_sync {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var}
    {k : Stmt} {Ec : Entry} {ms : List Nat} {q : Cross} (hc : Γ c = some Ec) (hty : Ec.ty = .fn ms q)
    (hq : q = .sync ∨ q = .bare) : ¬ StmtT P Γ F (.callcE x c j zs k) Δ := fun h => by
  have := callcE_send h hc hty
  rcases hq with rfl | rfl <;> rcases this with h' | h' <;> exact absurd h' (by decide)

/-- ... nor an `Arc`'s payload: an `Arc` holds only a `sync` or `bare` closure
    (`arcNew_fn`). -/
theorem callcE_not_arc {P : Prog} {Γ Δ Γ' Γ1 : Ctx} {F F' : List Var} {x c y : Var} {j : Nat}
    {zs : List Var} {k : Stmt} {Ec E : Entry} {ms : List Nat} {q : Cross}
    (h : StmtT P Γ F (.callcE x c j zs k) Δ) (hc : Γ c = some Ec) (hty : Ec.ty = .fn ms q) :
    ¬ RhsT Γ' F' (.arcNew (.fn ms q) y) E Γ1 := fun ha =>
  callcE_not_sync hc hty (arcNew_fn ha) h

/-- **h364's rule stays**: a hand-over takes an owner, never a borrow, so never
    what an `Arc` or a read guard lends (`getE_bor`), nor a copy of it. -/
theorem callcE_not_bor {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var}
    {k : Stmt} {Ec : Entry} (hc : Γ c = some Ec) (hm : Ec.mode = .bor ∨ Ec.mode = .rootb) :
    ¬ StmtT P Γ F (.callcE x c j zs k) Δ := fun h => by
  obtain ⟨_, _, _, _, _, hcan, _⟩ := h.callcE_recv_at hc
  rcases hcan with h' | ⟨_, h', _⟩ <;> rcases hm with hm | hm <;> rw [hm] at h' <;> cases h'

/-- A3.5c: a hand-over through a trait object types only where the object's
    class is its trait's bound ... -/
theorem _root_.A2.StmtT.callcE_bound {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat}
    {zs : List Var} {k : Stmt} {Ec : Entry} {ms : List Nat} {q : Cross} {b : TraitBound}
    (h : StmtT P Γ F (.callcE x c j zs k) Δ) (hc : Γ c = some Ec) (hty : Ec.ty = .fn ms q)
    (hb : TraitAt P ms b) : q = b.cross := by
  obtain ⟨ms', q', σ, sig, hty', _, hj, hσ, hbr⟩ := h.callcE_recv_at hc
  rw [hty] at hty'; cases hty'
  obtain ⟨sig', hσ', pm, hpm, hhd'⟩ := hb j σ hj
  rw [hσ] at hσ'; cases hσ'
  rcases hbr with ⟨e, hsp, _, _⟩ | ⟨hsp, _⟩
  · rw [hsp] at hhd'
    simp only [List.head?_cons, Option.some.injEq, Prod.mk.injEq, Ty.fn.injEq, true_and] at hhd'
    exact hhd'.2
  · rw [hsp] at hhd'
    simp only [List.head?_cons, Option.some.injEq, Prod.mk.injEq] at hhd'
    exact absurd hhd'.1.symm hpm

/-- ... so the `inout` methods of a `: Send Sync` trait are called through no
    object: every reader of an `Arc` of one may call its other methods at once. -/
theorem callcE_not_sendSync {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var}
    {k : Stmt} {Ec : Entry} {ms : List Nat} {q : Cross} (hc : Γ c = some Ec) (hty : Ec.ty = .fn ms q)
    (hb : TraitAt P ms .sendSync) : ¬ StmtT P Γ F (.callcE x c j zs k) Δ := fun h => by
  have hq := h.callcE_bound hc hty hb
  exact callcE_not_sync hc hty (Or.inl hq) h

/-- h365 (`dyn_inout_method_replaces_what_a_view_reads`): after a hand-over,
    every binding that depended on the package — a `String` read out of the
    box, a borrow of the box, a closure that holds it by name — is ended
    (`StmtT.callcE`'s `kill .replace`): what the code replaced is read by no
    view. -/
theorem hand_ends {Γ : Ctx} {c n : Var} {En : Entry} (hn : Γ n = some En) (hd : ∃ d ∈ En.vdeps, d.root = c)
    (hτ : En.ty ≠ .int ∨ En.mode = .rootb) : ∃ E', kill .replace false c Γ n = some E' ∧ E'.live = false := by
  refine ⟨killE .replace false c En, by simp [kill, hn], ?_⟩
  obtain ⟨d, hdd, hdr⟩ := hd
  have hh : hits .replace false c En = true := by
    unfold hits
    simp only [Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, List.any_eq_true]
    exact ⟨hτ, d, hdd, hdr, by cases d.kind <;> rfl⟩
  unfold killE; simp [hh]

/-- h366 (`helper_hands_its_parameter_to_a_dyn_method`): a helper's `inout`
    parameter that may be replaced is an owner for the hand-over: the helper
    hands the object on to the method by `StmtT.callcE`, and its caller's
    argument is an ordinary `inout` one, which `callPost` ends what depends on
    (h365's view). -/
theorem canDo_inout_replace : canDo (.inout .replace) .replace := Or.inr ⟨.replace, rfl, Nat.le_refl _⟩

/-- What no destructor views at all, none views for any effect. -/
theorem _root_.A2.DtorSafe.of_replace {Γ : Ctx} {x : Var} (h : DtorSafe Γ .replace false x) (e : Eff)
    (hv : Bool) : DtorSafe Γ e hv x := by
  intro v E hE hd hos
  have h0 := h v E hE hd hos
  unfold hitsMem at h0 ⊢
  simp only [Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true, beq_iff_eq, Bool.not_eq_eq_eq_not,
    Bool.not_true] at h0 ⊢
  rcases h0 with h0 | h0
  · exact Or.inl h0
  · exact Or.inr fun d hd hc => absurd ⟨hc.1, by cases d.kind <;> rfl⟩ (h0 d hd)

/-- The interface's call on a receiver that holds nothing by name, where every
    dependency on it has ended: the receiver, an owner, is its `inout`
    argument. -/
theorem _root_.A2.callT_recv_inout {P : Prog} {Γ : Ctx} {F : List Var} {σ : Nat} {sig : Fn} {c : Var}
    {Ec : Entry} {b : Eff} (hσ : P[σ]? = some sig) (hps : sig.params = [(.inout b, Ec.ty)])
    (hc : Γ c = some Ec) (hl : Ec.live = true) (hm : Ec.mode = .own) (ho : Ec.ty.owning = true)
    (hcF : c ∉ F) (hself : ∀ d ∈ Ec.vdeps, d.root ≠ c) (hn : ∀ d ∈ Ec.vdeps, d.kind.isName = false)
    (hdb : Ec.dbind = false) (hny : NoPin Γ c) (hdc : DtorSafe Γ .replace false c) (hnt : ¬ ThruFn P σ) :
    CallT P (kill .replace false c Γ) F σ [c] (callRes (kill .replace false c Γ) sig [c])
      (callPost (kill .replace false c Γ) sig [c]) := by
  have hkc : killE .replace false c Ec = Ec := killE_nohit hself
  have hΓk : kill .replace false c Γ c = some Ec := by simp [kill, hc, hkc]
  have hmut : mutNames (kill .replace false c Γ) [c] = [] := by
    have : nameDeps (argE (kill .replace false c Γ) c).vdeps = [] := by
      simp only [nameDeps, argE, hΓk, Option.getD_some, List.filter_eq_nil_iff]
      intro d hd; simp [hn d hd]
    simp [mutNames, argNames, this]
  refine ⟨sig, hσ, by simp [hps], fun i hi => ?_, fun d hd => ?_, ?_, rfl, rfl, fun h => absurd h hnt⟩
  · have hi0 : i = 0 := by rw [hps] at hi; simpa using hi
    subst hi0
    have hp0 : sig.params[0]'hi = (.inout b, Ec.ty) := by simp [hps]
    refine ⟨Ec, by simpa using hΓk, hl, ?_, ?_, ?_⟩
    · rw [hp0]; exact ⟨rfl, Or.inl hm, ho⟩
    · intro _
      refine ⟨by simpa using hcF, ?_, ?_, ?_, ?_⟩
      · intro h
        simp only [List.getD_cons_zero, roots, List.mem_map] at h
        obtain ⟨d, hd, hdr⟩ := h
        exact hself d (List.mem_filter.mp hd).1 hdr
      · intro h; rw [hp0] at h; cases h
      · intro _ _ d hd hr; exact absurd hr (hself d hd)
      · intro j hj hj0; exact absurd (by simpa [hps] using hj) hj0
    · intro _ p E hp hpr d hd hb hdr
      simp only [kill] at hp
      obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hp
      rw [killE_mode] at hpr; rw [killE_vdeps] at hd
      exact hny p E0 h0 hpr d hd hb (by simpa using hdr)
  · rw [hmut] at hd; cases hd
  · refine ⟨fun i hi => ⟨fun hs => ?_, fun b' _ => ?_⟩, fun d hd => ?_, fun i hi b' _ Ea hEa => ?_⟩
    · have hi0 : i = 0 := by rw [hps] at hi; simpa using hi
      subst hi0; simp [hps] at hs
    · have hi0 : i = 0 := by rw [hps] at hi; simpa using hi
      subst hi0
      exact (hdc.of_replace _ _).kill _ _ _
    · rw [hmut] at hd; cases hd
    · have hi0 : i = 0 := by rw [hps] at hi; simpa using hi
      subst hi0
      simp only [List.getD_cons_zero, hΓk, Option.some.injEq] at hEa
      subst hEa; exact hdb

/-- **A hand-over through an owned receiver that holds nothing by name** (an
    owned closure, or a trait object, whose environment holds no closure that
    holds names): A2's `callcE`, its call the interface's (`callT_recv_inout`). -/
theorem _root_.A2.StmtT.callcE_recv {P : Prog} {Γ Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {k : Stmt}
    {Ec : Entry} {ms : List Nat} {q : Cross} {σ : Nat} {sig : Fn} {b : Eff}
    (hks : k.src = true) (hx : Γ x = none) (hxF : x ∉ F) (hc : Γ c = some Ec) (hl : Ec.live = true)
    (hm : Ec.mode = .own) (hty : Ec.ty = .fn ms q) (hq : Cross.send.Le q) (hj : ms[j]? = some σ)
    (hσ : P[σ]? = some sig) (hps : sig.params = [(.inout b, .fn ms q)]) (hsl : sig.lends = [])
    (hsr : sig.rholds = []) (hso : sig.outHolds = []) (hnt : ¬ ThruFn P σ) (hcF : c ∉ F)
    (hself : ∀ d ∈ Ec.vdeps, d.root ≠ c) (hn : ∀ d ∈ Ec.vdeps, d.kind.isName = false) (hdb : Ec.dbind = false)
    (hny : NoPin Γ c) (hdc : DtorSafe Γ .replace false c)
    (hk : StmtT P (kill .replace false c (setE (callPost (kill .replace false c Γ) sig [c]) x
      (callRes (kill .replace false c Γ) sig [c]))) F k Δ) (hend : EndOK Δ x)
    (hdk : sig.resOwn = true → sig.resTy.holdsDtor = true → x ∈ k.movedFirst ∧ x ∉ k.assigns) :
    StmtT P Γ F (.callcE x c j [] k) (exitScope x Δ) :=
  StmtT.callcE hks hx hxF hc (by rw [hty]; rfl) (Or.inl hm) (Or.inl hq) hj hσ (Or.inl ⟨hps, hty, hq⟩) hsl hsr hso hny hdc
    (callT_recv_inout hσ (by rw [hty]; exact hps) hc hl hm (by rw [hty]; rfl) hcF hself hn hdb hny hdc hnt)
    hk hend hnt hdk

/-! A3.5b: the accumulator `\ → i { = n + n 1 ^ n }`, with `n` moved in, as a
`send` closure whose one method changes its environment. -/

/-- Its environment: a struct of the count.  A2's structs are pairs, and A2 has
    no `inout` integer (an integer binding is copied, not owned), so the
    one-capture environment is the count beside a field the code keeps as it
    is. -/
def accEnv : Ty := .prod .int .int

/-- The closure's type: one method, the interface `accSig` (the program's
    function 0), at `send`. -/
def accTy : Ty := .fn [0] .send

/-- The interface: takes the closure `inout` (it may be replaced), returns an
    integer, and lends, holds and stores nothing.  (An interface is a function
    of the program; its body says what any implementation returns.) -/
def accSig : Fn where
  params := [(.inout .replace, accTy)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .assign 1 (.expr (.lit 0))
  nvars := 2

/-- The code (the program's function 1): the environment `e` (variable 0) taken
    `inout`; `: i n . e 0`, `: i p . e 1`, `: i n2 + n 1`, `= e { n2 p }`,
    `^ n2`. -/
def accCode : Fn where
  params := [(.inout .replace, accEnv)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .letv 2 (.fst 0) (.letv 3 (.snd 0) (.letv 4 (.expr (.add (.var 2) (.lit 1)))
    (.seq (.assign 0 (.pair 4 3)) (.assign 1 (.var 4)))))
  nvars := 5

def accP : Prog := [accSig, accCode]

theorem accP_noThru (f : Nat) : ¬ ThruFn accP f := by
  have hall : ∀ fn ∈ accP, fn.body.hasThru = false ∧ fn.body.calls = [] := by
    simp [accP, accSig, accCode, Stmt.hasThru, Stmt.calls]
  intro h
  cases h with
  | here hf hb => rw [(hall _ (List.mem_of_getElem? hf)).1] at hb; cases hb
  | call hf hg _ => rw [(hall _ (List.mem_of_getElem? hf)).2] at hg; cases hg

/-- **The accumulator's code implements its interface**: it takes the
    environment where the interface takes the closure, `inout` at the
    interface's bound — the environment handed over, which it changes. -/
theorem accum_impl : Implements accP 1 accEnv [] 0 :=
  ⟨accCode, accSig, rfl, rfl, by simp [Fn.recvMode, accCode, accSig], fun _ => rfl, rfl, rfl,
    List.Subset.refl _, List.Subset.refl _, List.Subset.refl _, accP_noThru 1⟩

theorem accum_codes : CodeOK accP [1] accEnv [0] [] := by
  refine ⟨rfl, fun j f σ hf hσ => ?_⟩
  rcases j with _ | j
  · simp at hf hσ; subst hf hσ; exact accum_impl
  · simp at hf

/-- Its environment, a plain pair of integers, fits every class: the closure
    could be packed `sync` or `bare`.  Its interface takes it at `send`, so the
    method that changes the count is called only at `send` (a `sync` one is
    moved up first, `RhsT.moveUp`, and is then no `Arc`'s payload). -/
theorem accum_fits (q : Cross) : q.Fits accEnv [] :=
  ⟨fun _ => ⟨rfl, rfl⟩, fun _ => rfl, fun _ => rfl, fun _ => rfl⟩

/-- **The accumulator, typed through `callcE` on the owned closure**: its owner
    calls it, the environment handed over to the code, which adds one to the
    count it moved in. -/
theorem accum_hand {Γ Δ : Ctx} {F : List Var} {x acc : Var} {k : Stmt} (hks : k.src = true)
    (hx : Γ x = none) (hxF : x ∉ F) (hacc : Γ acc = some ⟨accTy, .own, true, [], [], false, false⟩)
    (haccF : acc ∉ F) (hny : NoPin Γ acc) (hdc : DtorSafe Γ .replace false acc)
    (hk : StmtT accP (kill .replace false acc (setE (callPost (kill .replace false acc Γ) accSig [acc]) x
      (callRes (kill .replace false acc Γ) accSig [acc]))) F k Δ) (hend : EndOK Δ x) :
    StmtT accP Γ F (.callcE x acc 0 [] k) (exitScope x Δ) :=
  StmtT.callcE_recv (sig := accSig) (ms := [0]) (q := .send) hks hx hxF hacc rfl rfl rfl (by decide) rfl rfl rfl
    rfl rfl rfl (accP_noThru 0) haccF (fun _ h => by cases h) (fun _ h => by cases h) rfl hny hdc hk hend
    (fun ho _ => by simp [accSig] at ho)

/-- ... and a `sync` one has no such call: its count is changed by no thread
    while several may hold it. -/
theorem accum_not_sync {Γ Δ : Ctx} {F : List Var} {x acc : Var} {k : Stmt} {Ec : Entry}
    (hacc : Γ acc = some Ec) (hty : Ec.ty = .fn [0] .sync) : ¬ StmtT accP Γ F (.callcE x acc 0 [] k) Δ :=
  callcE_not_sync hacc hty (Or.inl rfl)

/-! The accumulator's interface and code, typed (`FnOK`): the code changes the
count in the environment it is handed `inout`.  Its contexts hold only plain
bindings, which no change ends and no rule pins. -/

/-- A context of plain bindings: none borrowed, none a destructor's, none
    depending on anything. -/
def PlainCtx (Γ : Ctx) : Prop :=
  ∀ v E, Γ v = some E → E.vdeps = [] ∧ E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false

namespace PlainCtx
variable {Γ : Ctx}

theorem kill (h : PlainCtx Γ) (e : Eff) (hv : Bool) (x : Var) : A2.kill e hv x Γ = Γ := funext fun v => by
  simp only [A2.kill]
  cases hv' : Γ v with
  | none => rfl
  | some E => simp [killE_nil (h v E hv').1]

theorem setE (h : PlainCtx Γ) {x : Var} {E : Entry}
    (hE : E.vdeps = [] ∧ E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) : PlainCtx (A2.setE Γ x E) := by
  intro v E' hv
  by_cases hvx : v = x
  · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv; exact hE
  · simp only [A2.setE, upd_ne _ _ hvx] at hv; exact h v E' hv

theorem upd_none (h : PlainCtx Γ) (x : Var) : PlainCtx (upd Γ x none) := by
  intro v E' hv
  by_cases hvx : v = x
  · subst hvx; simp at hv
  · simp only [upd_ne _ _ hvx] at hv; exact h v E' hv

theorem exitScope (h : PlainCtx Γ) (x : Var) : A2.exitScope x Γ = upd Γ x none := by
  unfold A2.exitScope; rw [h.kill]

theorem endOK (h : PlainCtx Γ) (x : Var) : EndOK Γ x :=
  ⟨fun p E hp hm => absurd hm (h p E hp).2.1, DtorSafe.of_none (fun v E hv => (h v E hv).2.2.1) _ _ _,
    DbindSafe.of_none (fun v E hv => (h v E hv).2.2.2) x⟩

end PlainCtx

theorem intE_plain : intE.vdeps = [] ∧ intE.mode ≠ .rootb ∧ intE.dtor = false ∧ intE.dbind = false :=
  ⟨by simp [intE, Entry.vdeps, Mode.ownSlot], by simp [intE], rfl, rfl⟩

/-- A function of `inout` parameters that hold nothing by name starts in a
    plain context. -/
theorem sigCtx_plain {fn : Fn} (hio : ∀ pt ∈ fn.params, ∃ b, pt.1 = .inout b)
    (hs : symNames fn.params = []) : PlainCtx (sigCtx fn) := by
  intro v E hv
  unfold sigCtx at hv
  split at hv
  · rename_i hvl
    cases hv
    obtain ⟨b, hb⟩ := hio _ (List.getElem_mem hvl)
    generalize fn.params[v] = pt at hb
    obtain ⟨pm, t⟩ := pt
    simp only at hb; subst hb
    simp [paramE, hs, Entry.vdeps, Mode.ownSlot]
  · split at hv
    · cases hv; simp [Entry.vdeps, resMode]; split <;> simp [Mode.ownSlot]
    · cases hv

/-- The accumulator's environment as its code changes it: the pair it
    replaces. -/
def accEp : Entry := ⟨accEnv, .inout .replace, true, [], [], false, false⟩

/-- The accumulator code's context after its three `let`s ... -/
def accCtx3 : Ctx := setE (setE (setE (sigCtx accCode) 2 intE) 3 intE) 4 intE

/-- ... and after it has replaced the environment and set its result. -/
def accCtx4 : Ctx := setE (setE accCtx3 0 accEp) 1 intE

/-- **The accumulator's code is typed**: `: i n . e 0`, `: i p . e 1`,
    `: i n2 + n 1`, `= e { n2 p }`, `^ n2` changes the environment it is handed
    `inout` (it replaces it: `inout .replace`) and returns an integer, lending
    and holding nothing. -/
theorem accCode_ok : FnOK accP accCode := by
  have h0 : PlainCtx (sigCtx accCode) := sigCtx_plain (fun pt hpt => by
    simp only [accCode, List.mem_singleton] at hpt; subst hpt; exact ⟨_, rfl⟩) rfl
  have hs0 : sigCtx accCode 0 = some accEp := by simp [sigCtx, accCode, paramE, accEnv, Ty.hasFn, accEp]
  have hs1 : sigCtx accCode 1 = some ⟨.int, .bor, false, [], [], false, false⟩ := by
    simp [sigCtx, accCode, resMode]
  have hEp : accEp.vdeps = [] ∧ accEp.mode ≠ .rootb ∧ accEp.dtor = false ∧ accEp.dbind = false :=
    ⟨by simp [accEp, Entry.vdeps, Mode.ownSlot], by simp [accEp], rfl, rfl⟩
  have hp3 : PlainCtx accCtx3 :=
    ((h0.setE (x := 2) intE_plain).setE (x := 3) intE_plain).setE (x := 4) intE_plain
  have hp3a : PlainCtx (setE accCtx3 0 accEp) := hp3.setE hEp
  have hp4 : PlainCtx accCtx4 := hp3a.setE (x := 1) intE_plain
  have hpair : RhsT accCtx3 [] (.pair 4 3) ⟨.prod .int .int, .own, true, [], [], false, false⟩ accCtx3 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [accCtx3, setE]) rfl PushArg.int (by simp [accCtx3, setE]) rfl
      PushArg.int (fun h => by simp [intE, Mode.ownSlot] at h)
  have hA0 : StmtT accP accCtx3 [] (.assign 0 (.pair 4 3)) (setE accCtx3 0 accEp) := by
    have h := StmtT.assign (P := accP) (F := []) (x := 0) (Ex := accEp)
      (E := ⟨.prod .int .int, .own, true, [], [], false, false⟩) (by simp [accCtx3, setE, hs0]) (by simp)
      (Or.inr (Or.inl ⟨rfl, rfl⟩)) hpair rfl (by simp [Entry.vdeps, Mode.ownSlot, roots])
      (by simp [accCtx3, setE, hs0]) (hp3.endOK 0).1 (hp3.endOK 0).2.1 rfl
    rw [hp3.kill] at h; exact h
  have hA1 : StmtT accP (setE accCtx3 0 accEp) [] (.assign 1 (.var 4)) accCtx4 := by
    have h := StmtT.assign (P := accP) (F := []) (x := 1) (Γ := setE accCtx3 0 accEp)
      (Ex := ⟨.int, .bor, false, [], [], false, false⟩) (E := { intE with dtor := false, dbind := false })
      (by simp [accCtx3, setE, hs1]) (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.copyBor (y := 4) (E := intE) (by simp [accCtx3, setE]) rfl rfl) rfl
      (by simp [intE, Entry.vdeps, Mode.ownSlot, roots]) (by simp [accCtx3, setE, hs1])
      (hp3a.endOK 1).1 (hp3a.endOK 1).2.1 rfl
    rw [hp3a.kill] at h; exact h
  have h4 : StmtT accP (setE (setE (sigCtx accCode) 2 intE) 3 intE) []
      (.letv 4 (.expr (.add (.var 2) (.lit 1))) (.seq (.assign 0 (.pair 4 3)) (.assign 1 (.var 4))))
      (A2.exitScope 4 accCtx4) :=
    StmtT.letv (E := intE) rfl (by simp [setE, sigCtx, accCode]) (by simp)
      (RhsT.expr (ExprT.add (ExprT.var (E := intE) (by simp [setE]) rfl rfl) ExprT.lit))
      (StmtT.seq rfl hA0 hA1) (hp4.endOK 4)
  have hp5 := hp4.upd_none 4
  have h3 : StmtT accP (setE (sigCtx accCode) 2 intE) []
      (.letv 3 (.snd 0) (.letv 4 (.expr (.add (.var 2) (.lit 1)))
        (.seq (.assign 0 (.pair 4 3)) (.assign 1 (.var 4)))))
      (A2.exitScope 3 (A2.exitScope 4 accCtx4)) :=
    StmtT.letv (E := projE 0 accEp .int) rfl (by simp [setE, sigCtx, accCode]) (by simp)
      (RhsT.snd (b := .int) (by simp [setE, hs0]) rfl rfl) h4 (by rw [hp4.exitScope]; exact hp5.endOK 3)
  have hp6 := hp5.upd_none 3
  have h2 : StmtT accP (sigCtx accCode) [] accCode.body
      (A2.exitScope 2 (A2.exitScope 3 (A2.exitScope 4 accCtx4))) :=
    StmtT.letv (E := projE 0 accEp .int) rfl (by simp [sigCtx, accCode]) (by simp)
      (RhsT.fst (b := .int) hs0 rfl rfl) h3 (by rw [hp4.exitScope, hp5.exitScope]; exact hp6.endOK 2)
  have hΔ : A2.exitScope 2 (A2.exitScope 3 (A2.exitScope 4 accCtx4)) =
      upd (upd (upd accCtx4 4 none) 3 none) 2 none := by
    rw [hp4.exitScope, hp5.exitScope, hp6.exitScope]
  have hp7 := hp6.upd_none 2
  refine ⟨rfl, by decide, by decide, rfl, by simp [accCode], ?_, by simp [accCode], by simp [accCode],
    by simp [accCode], by simp [accCode], by simp [accCode],
    dtorParamsOK_of (by simp [accCode] <;> decide) (by simp [accCode] <;> decide), _, h2, ?_, ?_, ?_⟩
  · intro pt hpt
    simp only [accCode, List.mem_singleton] at hpt; subst hpt
    simp [accEnv, Ty.ok, Ty.owning]
  · intro v E hv
    rw [hΔ] at hv
    exact ⟨(hp7 v E hv).2.2.1, (hp7 v E hv).2.2.2⟩
  · refine ⟨intE, by rw [hΔ]; simp [accCtx4, setE, accCode], rfl, rfl, rfl, by simp [intE], by simp [intE],
      fun h => by simp [accCode] at h⟩
  · intro i hi b _
    have hi0 : i = 0 := by simpa [accCode] using hi
    subst hi0
    exact ⟨accEp, by rw [hΔ]; simp [accCtx4, setE], rfl, by simp [accEp], fun _ => rfl⟩

/-- ... and so is its interface: it returns an integer, and changes nothing of
    the closure it takes `inout`. -/
theorem accSig_ok : FnOK accP accSig := by
  have hsym : symNames accSig.params = [] := by decide
  have h0 : PlainCtx (sigCtx accSig) := sigCtx_plain (fun pt hpt => by
    simp only [accSig, List.mem_singleton] at hpt; subst hpt; exact ⟨_, rfl⟩) hsym
  have hs0 : sigCtx accSig 0 = some ⟨accTy, .inout .replace, true, [], [], false, false⟩ := by
    simp only [sigCtx, accSig, List.length_singleton, Nat.zero_lt_one]
    simp [paramE, accTy, Ty.hasFn, ← hsym, accSig]
  have hs1 : sigCtx accSig 1 = some ⟨.int, .bor, false, [], [], false, false⟩ := by
    simp [sigCtx, accSig, resMode]
  have hA : StmtT accP (sigCtx accSig) [] accSig.body (setE (sigCtx accSig) 1 intE) := by
    have h := StmtT.assign (P := accP) (F := []) (x := 1) (r := .expr (.lit 0)) (Γ := sigCtx accSig)
      (Ex := ⟨.int, .bor, false, [], [], false, false⟩) hs1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, Entry.vdeps, Mode.ownSlot, roots]) (by simp [hs1])
      (h0.endOK 1).1 (h0.endOK 1).2.1 rfl
    rw [h0.kill] at h; exact h
  have hp := h0.setE (x := 1) intE_plain
  refine ⟨rfl, by decide, by decide, rfl, by simp [accSig], ?_, by simp [accSig], by simp [accSig],
    by simp [accSig], by simp [accSig], by simp [accSig],
    dtorParamsOK_of (by simp [accSig] <;> decide) (by simp [accSig] <;> decide), _, hA, ?_, ?_, ?_⟩
  · intro pt hpt
    simp only [accSig, List.mem_singleton] at hpt; subst hpt
    simp [accTy, Ty.ok, Ty.owning]
  · intro v E hv
    exact ⟨(hp v E hv).2.2.1, (hp v E hv).2.2.2⟩
  · exact ⟨intE, by simp [setE, accSig], rfl, rfl, rfl, by simp [intE], by simp [intE], fun h => by simp [accSig] at h⟩
  · intro i hi b _
    have hi0 : i = 0 := by simpa [accSig] using hi
    subst hi0
    exact ⟨⟨accTy, .inout .replace, true, [], [], false, false⟩, by simp [setE, hs0], rfl, by simp, fun _ => rfl⟩

/-- **The accumulator's program is typed**: its interface and code meet their
    summaries, and they make no package. -/
theorem accP_ok : ProgOK accP := by
  intro fn hfn
  simp only [accP, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl
  · exact accSig_ok
  · exact accCode_ok

theorem accP_codes : ProgCodes accP := by
  intro fn hfn
  simp only [accP, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl <;> simp [accSig, accCode, Stmt.codesOK, Rhs.codeOK]

/-! The accumulator's caller, a whole program:

        : i n 0  : i p 0  : e { n p }
        : acc \ → i { … }        -- moves e in: the closure owns its environment
        : i r ( acc )            -- hands the environment over to the code

typed from nothing, so `A2.memory_safe` and the two `no_leak`s hold of it. -/

/-- The accumulator's caller. -/
def accMain : Stmt :=
  .letv 0 (.expr (.lit 0)) (.letv 1 (.expr (.lit 0)) (.letv 2 (.pair 0 1)
    (.letv 3 (.pack [1] accEnv [0] 2 []) (.callcE 4 3 0 [] .skip))))

/-- The environment before it moves into the closure, ... -/
def accPairE : Entry := ⟨accEnv, .own, true, [], [], false, false⟩

/-- ... the closure that owns it, ... -/
def accCloE : Entry := ⟨accTy, .own, true, [], [], false, false⟩

/-- ... and the caller's context once the closure is made. -/
def accMainCtx : Ctx :=
  setE (setE (setE (setE (setE (fun _ => none) 0 intE) 1 intE) 2 accPairE) 2
    { accPairE with live := false, dtor := false }) 3 accCloE

/-- **The accumulator's caller is typed** from nothing: the pair moves into
    the closure (`RhsT.pack`, at `send`), and the closure's owner calls it,
    handing the environment over (`StmtT.callcE`, by `accum_hand`). -/
theorem accMain_typed : ∃ Δ, StmtT accP (fun _ => none) [] accMain Δ := by
  have he : PlainCtx (fun _ => none) := fun _ _ h => by cases h
  have hpE : accPairE.vdeps = [] ∧ accPairE.mode ≠ .rootb ∧ accPairE.dtor = false ∧ accPairE.dbind = false :=
    ⟨by simp [accPairE, Entry.vdeps, Mode.ownSlot], by simp [accPairE], rfl, rfl⟩
  have hdE : ({ accPairE with live := false, dtor := false } : Entry).vdeps = [] ∧
      ({ accPairE with live := false, dtor := false } : Entry).mode ≠ .rootb ∧
      ({ accPairE with live := false, dtor := false } : Entry).dtor = false ∧
      ({ accPairE with live := false, dtor := false } : Entry).dbind = false :=
    ⟨by simp [accPairE, Entry.vdeps, Mode.ownSlot], by simp [accPairE], rfl, rfl⟩
  have hcE : accCloE.vdeps = [] ∧ accCloE.mode ≠ .rootb ∧ accCloE.dtor = false ∧ accCloE.dbind = false :=
    ⟨by simp [accCloE, Entry.vdeps, Mode.ownSlot], by simp [accCloE], rfl, rfl⟩
  have hp2 : PlainCtx (setE (setE (fun _ => none) 0 intE) 1 intE) :=
    (he.setE (x := 0) intE_plain).setE (x := 1) intE_plain
  have hp3 : PlainCtx (setE (setE (setE (fun _ => none) 0 intE) 1 intE) 2 accPairE) := hp2.setE hpE
  have hp4 : PlainCtx accMainCtx := (hp3.setE (x := 2) hdE).setE (x := 3) hcE
  have hcp : callPost accMainCtx accSig [3] = setE accMainCtx 3 accCloE := by
    have h : callPost accMainCtx accSig [3] = setE (A2.kill .replace false 3 accMainCtx) 3 accCloE := by
      simp [callPost, callPostAux, accSig, mutNames, argNames, killNames, nameDeps, argE, accMainCtx, setE,
        accCloE, accTy, Ty.holdsView, Ty.elem, Entry.vdeps, Mode.ownSlot]
    rw [h, hp4.kill]
  have hcr : callRes accMainCtx accSig [3] = intE := by
    simp [callRes, accSig, heldOfArgs, argNames, allKinds, nameDeps, memDeps, roots, argE, accMainCtx, setE,
      accCloE, accTy, Entry.vdeps, Mode.ownSlot, ownHeld, resMode, intE]
  have hpc : PlainCtx (setE (setE accMainCtx 3 accCloE) 4 intE) := (hp4.setE hcE).setE (x := 4) intE_plain
  have hΔc : A2.kill .replace false 3 (setE (callPost (A2.kill .replace false 3 accMainCtx) accSig [3]) 4
      (callRes (A2.kill .replace false 3 accMainCtx) accSig [3])) = setE (setE accMainCtx 3 accCloE) 4 intE := by
    rw [hp4.kill, hcp, hcr]; exact hpc.kill _ _ _
  have hC : StmtT accP accMainCtx [] (.callcE 4 3 0 [] .skip)
      (A2.exitScope 4 (setE (setE accMainCtx 3 accCloE) 4 intE)) := by
    have h := accum_hand (F := []) (x := 4) (acc := 3) (k := .skip) rfl (by simp [accMainCtx, setE]) (by simp)
      (by simp [accMainCtx, setE, accCloE]) (by simp) (hp4.endOK 3).1 (hp4.endOK 3).2.1 StmtT.skip
      (by rw [hΔc]; exact hpc.endOK 4)
    rw [hΔc] at h; exact h
  have q4 := hpc.upd_none 4
  have q3 := q4.upd_none 3
  have q2 := q3.upd_none 2
  have q1 := q2.upd_none 1
  have hpack : RhsT (setE (setE (setE (fun _ => none) 0 intE) 1 intE) 2 accPairE) [] (.pack [1] accEnv [0] 2 [])
      accCloE (setE (setE (setE (setE (fun _ => none) 0 intE) 1 intE) 2 accPairE) 2
        { accPairE with live := false, dtor := false }) := by
    have h := RhsT.pack (Γ := setE (setE (setE (fun _ => none) 0 intE) 1 intE) 2 accPairE) (F := [])
      (fs := [1]) (te := accEnv) (ms := [0]) (q := .send) (y := 2) (cs := []) (Ey := accPairE)
      (by simp [setE]) rfl rfl
      (PushArg.move (by simp [accEnv, Ty.owning]) rfl (by simp) (hp3.endOK 2).1 (hp3.endOK 2).2.1)
      ⟨List.nodup_nil, fun _ h => by cases h⟩ (accum_fits .send)
    rw [hp3.kill] at h; exact h
  have h3 : StmtT accP (setE (setE (setE (fun _ => none) 0 intE) 1 intE) 2 accPairE) []
      (.letv 3 (.pack [1] accEnv [0] 2 []) (.callcE 4 3 0 [] .skip))
      (A2.exitScope 3 (A2.exitScope 4 (setE (setE accMainCtx 3 accCloE) 4 intE))) :=
    StmtT.letv rfl (by simp [setE]) (by simp) hpack hC (by rw [hpc.exitScope]; exact q4.endOK 3)
  have h2 : StmtT accP (setE (setE (fun _ => none) 0 intE) 1 intE) []
      (.letv 2 (.pair 0 1) (.letv 3 (.pack [1] accEnv [0] 2 []) (.callcE 4 3 0 [] .skip)))
      (A2.exitScope 2 (A2.exitScope 3 (A2.exitScope 4 (setE (setE accMainCtx 3 accCloE) 4 intE)))) :=
    StmtT.letv (E := accPairE) rfl (by simp [setE])
      (by simp) (RhsT.pair (Ey := intE) (Ez := intE) (by simp [setE]) rfl PushArg.int (by simp [setE]) rfl
        PushArg.int (fun h => by simp [intE, Mode.ownSlot] at h)) h3
      (by rw [hpc.exitScope, q4.exitScope]; exact q3.endOK 2)
  have h1 : StmtT accP (setE (fun _ => none) 0 intE) []
      (.letv 1 (.expr (.lit 0)) (.letv 2 (.pair 0 1) (.letv 3 (.pack [1] accEnv [0] 2 [])
        (.callcE 4 3 0 [] .skip))))
      (A2.exitScope 1 (A2.exitScope 2 (A2.exitScope 3 (A2.exitScope 4
        (setE (setE accMainCtx 3 accCloE) 4 intE))))) :=
    StmtT.letv rfl (by simp [setE]) (by simp) (RhsT.expr ExprT.lit) h2
      (by rw [hpc.exitScope, q4.exitScope, q3.exitScope]; exact q2.endOK 1)
  exact ⟨_, StmtT.letv rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    (by rw [hpc.exitScope, q4.exitScope, q3.exitScope, q2.exitScope]; exact q1.endOK 0)⟩

theorem accMain_codes : accMain.codesOK accP := by
  simp only [accMain, Stmt.codesOK, Rhs.codeOK, true_and, and_true]
  exact accum_codes

theorem accMain_vars : ∀ v ∈ accMain.vars, v < 5 := by decide

/-- **The accumulator's program is memory-safe**: no run of it from empty
    memory reaches a stuck state ... -/
theorem accMain_safe {m' : Mem} {s' : Stmt} (hr : Steps accP (emptyMem 5) accMain (.ok m' s')) :
    ¬ Stuck accP m' s' :=
  have ⟨_, ht⟩ := accMain_typed
  memory_safe accP_ok accP_codes ht rfl accMain_codes accMain_vars hr

/-- ... and frees everything it allocated, when it ends ... -/
theorem accMain_no_leak {m' : Mem} (hr : Steps accP (emptyMem 5) accMain (.ok m' .skip)) :
    ∀ i, m'.alloc i = false :=
  have ⟨_, ht⟩ := accMain_typed
  no_leak_end accP_ok accP_codes ht rfl accMain_codes accMain_vars hr

/-- ... and when it panics. -/
theorem accMain_no_leak_panic {m' : Mem} (hr : Steps accP (emptyMem 5) accMain (.panic m')) :
    ∀ i, m'.alloc i = false :=
  have ⟨_, ht⟩ := accMain_typed
  no_leak_panic accP_ok accP_codes ht rfl accMain_codes accMain_vars hr

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

/-- A value that holds a share of a cell an owner left behind holds one of
    fails the crossing check. -/
theorem not_sendCheck {B : Nat → Option Blk} {st : Var → Option Slot} {v : Val} {k : Nat} (hv : Sub (.cell k) v)
    {z : Var} {w : Val} (hz : st z = some ⟨true, some w⟩) (hw : Sub (.cell k) w) : ¬ SendCheck B [v] st :=
  fun h => h.1 k ⟨v, List.mem_singleton_self _, hv⟩ z w hz hw

/-- **h340** (`closure_sent_on_a_channel_captures_a_kept_handle`): a closure
    that captured a library handle the sender still holds a share of (in any
    slot, inside any value) is not sent: `chan_send`'s crossing check fails,
    and the send panics (`EvalR.chanSendFail`), with no other outcome ... -/
theorem chanSend_kept {m m1 : Mem} {a y : Var} {v : Val} (ht : TakeVal m y v m1) {k : Nat}
    (hv : Sub (.cell k) v) {z : Var} {w : Val} (hz : m1.st z = some ⟨true, some w⟩)
    (hw : Sub (.cell k) w) :
    EvalR m (.chanSend a y) .panic ∧ ∀ r o' m', ¬ EvalR m (.chanSend a y) (.ok r o' m') := by
  refine ⟨EvalR.chanSendFail ht (not_sendCheck hv hz hw), fun r o' m' h => ?_⟩
  cases h with
  | chanSend _ ht' _ _ _ _ hck =>
    obtain ⟨rfl, rfl⟩ := ht.det ht'
    exact not_sendCheck hv hz hw hck
  | chanSendClosed _ ht' _ _ _ hck =>
    obtain ⟨rfl, rfl⟩ := ht.det ht'
    exact not_sendCheck hv hz hw hck

/-- ... and one sent took every owner along: the send moves the closure's
    tree, the handle in its environment with it, into the queue (or drops it
    on a closed channel), and no slot left holds a share of a cell it holds. -/
theorem chanSend_moves {m m' : Mem} {a y : Var} {r : Val} {o : Bool} (h : EvalR m (.chanSend a y) (.ok r o m')) :
    ∃ v m1, TakeVal m y v m1 ∧ m'.st = m1.st ∧ SendCheck m1.blk [v] m'.st := by
  cases h with
  | chanSend _ ht _ _ _ _ hck => exact ⟨_, _, ht, rfl, hck⟩
  | chanSendClosed _ ht _ _ _ hck => exact ⟨_, _, ht, rfl, hck⟩

/-- h358 (`rc_in_a_locked_in_an_arc_on_two_threads`) and h357
    (`rwlocked_of_a_library_handle_on_two_threads`): a value that holds a
    library handle the caller kept a share of goes into no lock: `locked_new`
    (and `rw_new`) panics (`EvalR.lockNewFail`) ... -/
theorem lockNew_kept {m m1 : Mem} {t : Ty} {y : Var} {v : Val} (ht : TakeVal m y v m1) {k : Nat}
    (hv : Sub (.cell k) v) {z : Var} {w : Val} (hz : m1.st z = some ⟨true, some w⟩)
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
    (hv : Sub (.cell k) v) {z : Var} {w : Val} (hz : m1.st z = some ⟨true, some w⟩)
    (hw : Sub (.cell k) w) :
    EvalR m (.lockRestore a y) .panic ∧ ∀ r o' m', ¬ EvalR m (.lockRestore a y) (.ok r o' m') := by
  refine ⟨EvalR.lockRestoreFail ht (not_sendCheck hv hz hw), fun r o' m' h => ?_⟩
  cases h with
  | lockRestore _ ht' _ _ hck =>
    obtain ⟨rfl, rfl⟩ := ht.det ht'
    exact not_sendCheck hv hz hw hck

/-- ... and **the give-back's check** (`locked_with`, `locked_update`,
    h354's `locked_update_stores_a_kept_handle_into_the_value`): a lock
    scope's end gives the value back only past the crossing check, and when
    the body kept an owner of a handle the value holds, or stored into it one
    kept outside, the end is a panic in the scope, the store as it was (the
    unwinding then drops `x`, the lock left held). -/
theorem scopeL_end {P : Prog} {m : Mem} {k : Nat} {t : Ty} {x : Var} {r : Res}
    (h : Step P m (.scopeL k t x .skip) r)
    -- (Agora #610: with no orphan to reap first; no configuration a run reaches has one,
    -- `A3.Reach.noOrphan`)
    (hno : ¬ Orphan m) :
    (∃ m', r = .ok m' .skip ∧ Release m k t x m' ∧ ∀ sl, m.st x = some sl → GiveCheck m x sl) ∨
      (r = .ok m (.scopeL k t x .panic) ∧ ∃ sl, m.st x = some sl ∧ ¬ GiveCheck m x sl) := by
  cases h with
  | reap hrs _ _ => cases hrs
  | scopeLSkip hrl hck => exact .inl ⟨_, rfl, hrl, hck⟩
  | scopeLFail hx hck => exact .inr ⟨rfl, _, hx, hck⟩
  | scopeLIn hs => cases hs with | reap _ hk _ => exact absurd ⟨_, _, _, _, _, hk⟩ hno
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
  cases b <;> simp [TraitBound.cross, Ty.ok, Ty.holdsView, Ty.lkPay, Ty.dtorFree, Ty.hasDtor, Ty.dnest]

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
      step with the store's: (Agora #755 item 1) the marking sweep
      (`Cfg.sweepD`), whose orphans the same thread then reaps, each reap a
      step of its own ended by the marking sweep, before any other thread
      runs (`CSettle`, A2's `Settle`): the thread whose step dropped the
      last share runs the destructor. -/
  | thread {C : Cfg} {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt} {C' : Cfg} :
      C.ths[i]? = some t → ¬ SpawnRedex spawn t.s → Step P (C.view t) t.s (.ok m' s') →
      CSettle P i (C.put i m' s').sweepD C' → TStep P spawn C C'
  /-- A spawn: the arguments move to a new thread, which runs the body in
      its parameters' scopes and its result's (variable `n`, the number of
      parameters, as in the body's own numbering — so its end drops the
      result); the spawner's result is `0`. -/
  | spawn {C : Cfg} {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var}
      {k : Stmt} {fn : Fn} {vs : List Val} {st' : Var → Option Slot} :
      C.ths[i]? = some t → Redex t.s K (.letcall x f args k) → spawn f = true → P[f]? = some fn →
      t.st x = none → MoveArgs t.st args vs st' → SendCheck C.blk vs st' →
      TStep P spawn C
        { C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k)⟩ ++
                        [⟨spawnSt fn vs, fn.nvars,
                          wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] }
  /-- A3.5: a spawn whose crossing check fails panics in the spawner, as
      `mem_send_check` calls `nurl_panic`: no thread is made and nothing
      moves, and the spawner's next step is A2's panic, which unwinds its
      scopes (or a `recover` frame catches it).  (A3.3: a moved value that
      reaches a read guard fails it too, `NoGuard`, which nurlc asks
      statically.) -/
  | spawnFail {C : Cfg} {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var}
      {k : Stmt} {fn : Fn} {vs : List Val} {st' : Var → Option Slot} :
      C.ths[i]? = some t → Redex t.s K (.letcall x f args k) → spawn f = true → P[f]? = some fn →
      t.st x = none → MoveArgs t.st args vs st' → ¬ SendCheck C.blk vs st' →
      TStep P spawn C { C with ths := C.ths.set i ⟨t.st, t.nv, K (.seq .panic (.letcall x f args k))⟩ }

/-! ### A3.3: read guards are `% NotSend`

A read guard is a share of a view (`rw_read`'s), which the runtime's
`RGuard_drop` unlocks on the thread that took it.  So no guard crosses to
another thread: the crossing check asks it (`NoGuard`, part of `SendCheck`) of
what a spawn moves, of every value going into a lock block, and of a lock
scope's give-back.  It asks it of a guard a value holds at any depth (a
field, an element, a closure's environment, `Sub`) and of one in a block a
value's shares reach (an `Arc`'s payload, a lock's: `Reached`), so a guard
kept in an `Arc` or a `Locked` does not cross either.  nurlc refuses such a
crossing statically (`% NotSend RGuard`); the model's crossing panics
(`TStep.spawnFail`, `EvalR.lockNewFail`, `EvalR.chanSendFail`, ...).  A write
guard is no value (the lock scope `scopeL`), and what a guard lends is a
borrow, which no crossing takes (a spawn's and a lock's value is owned). -/

/-- A value that holds a read guard fails `NoGuard`. -/
theorem guard_not_noGuard {B : Nat → Option Blk} {vs : List Val} {v : Val} (hv : v ∈ vs) {k : Nat}
    {p : Val} (hs : Sub (.arc k p) v) {bl : Blk} (hk : B k = some bl) (hview : bl.kind = .view) :
    ¬ NoGuard B vs :=
  fun h => h k (.root hv (.inl (.inl ⟨some p, hs⟩))) bl hk hview

/-- ... and so does one whose shares reach a block holding one (a guard kept
    in an `Arc`'s payload, or in a lock's). -/
theorem guard_pay_not_noGuard {B : Nat → Option Blk} {vs : List Val} {k' : Nat} {bl' : Blk}
    (hr : Reached (· ∈ vs) B k') (hk' : B k' = some bl') {k : Nat} {p : Val} (hs : Sub (.arc k p) bl'.keeps)
    {bl : Blk} (hk : B k = some bl) (hview : bl.kind = .view) : ¬ NoGuard B vs :=
  fun h => h k (.pay hr hk' (.inl (.inl ⟨some p, hs⟩))) bl hk hview

/-- **A read guard does not cross a spawn**: a spawn whose moved values hold
    one, or reach one through a block, fails the crossing check, so it is no
    `TStep.spawn` and the spawner panics (`TStep.spawnFail`). -/
theorem spawn_guard {C : Cfg} {st' : Var → Option Slot} {vs : List Val} (hng : ¬ NoGuard C.blk vs) :
    ¬ SendCheck C.blk vs st' :=
  fun h => hng h.2

/-- **Nor into a lock or a channel**: `locked_new` (and `rw_new`) of a value
    that reaches a read guard panics (`EvalR.lockNewFail`), with no other
    outcome ... -/
theorem lockNew_guard {m m1 : Mem} {t : Ty} {y : Var} {v : Val} (ht : TakeVal m y v m1)
    (hng : ¬ NoGuard m1.blk [v]) :
    EvalR m (.lockNew t y) .panic ∧ ∀ r o' m', ¬ EvalR m (.lockNew t y) (.ok r o' m') := by
  refine ⟨EvalR.lockNewFail ht (fun h => hng h.2), fun r o' m' h => ?_⟩
  cases h with
  | lockNew ht' _ hck =>
    obtain ⟨rfl, rfl⟩ := ht.det ht'
    exact hng hck.2

/-- ... and `chan_send` of one panics (`EvalR.chanSendFail`). -/
theorem chanSend_guard {m m1 : Mem} {a y : Var} {v : Val} (ht : TakeVal m y v m1)
    (hng : ¬ NoGuard m1.blk [v]) :
    EvalR m (.chanSend a y) .panic ∧ ∀ r o' m', ¬ EvalR m (.chanSend a y) (.ok r o' m') := by
  refine ⟨EvalR.chanSendFail ht (fun h => hng h.2), fun r o' m' h => ?_⟩
  cases h with
  | chanSend _ ht' _ _ _ _ hck =>
    obtain ⟨rfl, rfl⟩ := ht.det ht'
    exact hng hck.2
  | chanSendClosed _ ht' _ _ _ hck =>
    obtain ⟨rfl, rfl⟩ := ht.det ht'
    exact hng hck.2

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
  | removeC {y : Var} {i : Expr} {t : Ty} {c d : Nat} {es : List Val} :
      m.st y = some ⟨true, some (.node t c d es)⟩ → RTouch m (.remove y i) c true
  | removeD {y : Var} {i : Expr} {t : Ty} {c d : Nat} {es : List Val} :
      m.st y = some ⟨true, some (.node t c d es)⟩ → RTouch m (.remove y i) d true
  | removeI {y : Var} {i : Expr} {a : Nat} : EReads m i a → RTouch m (.remove y i) a false
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

/-- A3.1: what the sweeps that end thread `i`'s next step free: an address
    live before the step and after it, which the configuration's step frees —
    the payload of a block no thread reaches any more, freed by the marking
    sweep after the step or (Agora #755 item 1) after one of the reaps that
    follow it.  (A fresh address is no touch, as above.  The reaps move a
    payload to the thread's slot and touch no address; the destructor's
    reads and writes are the thread's later steps', on its own part.) -/
def SweepFrees (P : Prog) (C : Cfg) (i : Nat) (t : Thread) (a : Nat) : Prop :=
  ∃ m' s' C', Step P (C.view t) t.s (.ok m' s') ∧ CSettle P i (C.put i m' s').sweepD C' ∧
    C.alloc a = true ∧ m'.alloc a = true ∧ C'.alloc a = false

/-- What thread `t` (the `i`-th) touches next in the configuration: what its
    rule touches, and (A3.1) what the sweeps that end its step free (the
    marking sweep's and, Agora #755 item 1, those after its reaps), a
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
    state out through a share of it (`withCell`, through an owner or, A3.5's
    third cut, a borrow), or it runs inside a check-out of it, holding an
    owner's share of it (the one the check-out is through, which `withLock`'s
    premises keep in its binding for the whole body, or, for a borrowed
    parameter, its caller's owner: `A3.reach_frame_cell_owner`, for every
    check-out of a cell's block, which no lock share names,
    `A3.reach_shareKind`).  Such a step writes the state wherever it is: the model checks it
    out as a lock's payload, so two threads at once would be serialized
    there, where the runtime's copies write one memory with no lock; so a
    step on a cell is not an address's touch, but a race of its own. -/
def CellOp (t : Thread) (k : Nat) : Prop :=
  (∃ K a x s o, Redex t.s K (.withLock a x s) ∧ t.st a = some ⟨o, some (.cell k)⟩) ∨
  (k ∈ t.s.lkeys ∧ ∃ y v, t.st y = some ⟨true, some v⟩ ∧ Sub (.cell k) v)

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

/-- Some value of the configuration holds `w`: a thread's slot (a live
    binding or a dead one), a block's payload or a module global.  A block
    `k` some value holds a cell share of (`C.Holds (.cell k)`) is a cell's
    block (a library handle's state). -/
def Cfg.Holds (C : Cfg) (w : Val) : Prop :=
  (∃ (j : Nat) (t : Thread) (x : Var) (o : Bool) (v : Val),
      C.ths[j]? = some t ∧ t.st x = some ⟨o, some v⟩ ∧ Sub w v) ∨
  (∃ (k : Nat) (t : Ty) (kd : BKind) (v : Val), C.blk k = some ⟨t, kd, some v⟩ ∧ Sub w v) ∨
  (∃ (g : Nat) (v : Val), C.gl g = some v ∧ Sub w v)

/-- **A3.5, Agora #818: race freedom is adequate for cells.**  In every
    configuration reachable from `C0`, a thread inside a check-out of a
    cell's block (a `scopeL k` frame on its spine, where some value of the
    configuration holds a cell share of `k`) is on a step on the cell
    (`CellOp`): it holds an owner's share of the cell.  `CellOp` asks that
    share of a step inside a check-out, so this is what makes `RaceFree` see
    every two threads changing one cell's state, which the runtime's
    `withCell` does with no lock: no check-out of a cell's block is outside
    `CellOp` (through a lock share of the block, say). -/
def CellAdequate (P : Prog) (spawn : Nat → Bool) (C0 : Cfg) : Prop :=
  ∀ C, Reach P spawn C0 C → ∀ (i : Nat) (t : Thread) (K : Stmt → Stmt) (k : Nat) (u : Ty) (x : Var) (b : Stmt),
    C.ths[i]? = some t → Redex t.s K (.scopeL k u x b) → C.Holds (.cell k) → CellOp t k

/-- A3.5's second cut: lock block `k'` of `B` holds a share of cell `k` in its
    payload, while the payload is in the block (a lock's, a cell's state, a
    channel's queue).  A3's confinement counts it as a place a cell's shares
    are, beside the threads' slots (`CellInv`, `A3/Cell.lean`). -/
def LockHolds (B : Nat → Option Blk) (k' k : Nat) : Prop :=
  ∃ t p, B k' = some ⟨t, .lock, some p⟩ ∧ Sub (.cell k) p

/-- **A3.6, what a start-set global may be**, as its typing sees the
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
      going into a lock, as every thread does (A3's `CellInv`).
    `GlobsOK` adds (Agora #815) that no key is named by both a lock share and
    a cell share (`GlobsKinds`). -/
structure GlobsTyped (P : Prog) (G : Globs) : Prop where
  sync  : ∀ g v, G.gl g = some v → ∃ t, t.sync = true ∧ t.ok = true ∧ GlobFits G.blk t v
  inv   : MInv (G.mem 0) (fun _ => none)
  cover : Covers (G.mem 0)
  reach : ∀ k bl, G.blk k = some bl → Reached (fun v => ∃ g, G.gl g = some v) G.blk k
  codes : ∀ k bl, G.blk k = some bl → PkgOK P bl.tree ∧ PkgOK P bl.rd
  /-- Agora #610: a block of a destructor value names a destructor the
      program checked (`DeadCodes`; since Agora #755 asked of every block of
      a destructor type, whatever its kind: an `Arc`'s or, `Locked D`, a
      lock's; vacuous when no block's payload owns one, which is all the
      invariant allowed before). -/
  dtors : DeadCodes P G.blk
  cells : ∀ k k1 k2, LockHolds G.blk k1 k → LockHolds G.blk k2 k → k1 = k2 ∧ k < G.nid

/-- Every lock share `v` holds names a key of kind `false` under `κ`, every
    cell share one of kind `true` (outside a carried `arc` payload, which is
    ghost data, as in `KB`, A3/Keys.lean).  Agora #815: what keeps lock and cell
    shares apart, which the typing does not (both name a lock block of their
    payload type): A3/Kinds.lean. -/
inductive KK (κ : Nat → Bool) : Val → Prop
  | int {j : Nat} : KK κ (.int j)
  | href {c : Nat} : KK κ (.href c)
  | view {d o l : Nat} : KK κ (.view d o l)
  | node {t : Ty} {c d : Nat} {es : List Val} : (∀ e ∈ es, KK κ e) → KK κ (.node t c d es)
  | pair {v w : Val} : KK κ v → KK κ w → KK κ (.pair v w)
  | inl {v : Val} : KK κ v → KK κ (.inl v)
  | inr {v : Val} : KK κ v → KK κ (.inr v)
  | pkg {fs : List Nat} {te : Ty} {ms : List Nat} {v : Val} {cs : List (Var × PMode × Ty)} :
      KK κ v → KK κ (.pkg fs te ms v cs)
  | arc {k : Nat} {p : Val} : KK κ (.arc k p)
  | lk {k : Nat} : κ k = false → KK κ (.lk k)
  | cell {k : Nat} : κ k = true → KK κ (.cell k)

/-- **A3.5, Agora #815: a start whose blocks and globals keep lock and cell
    shares apart**: a kind per key that every share in a block's payload or a
    global agrees with.  The make phase leaves one (`make_ok`), and so does no
    global (`GlobsOK.empty`); without it a start may name one key by a global
    lock share and by a cell share another global lock's payload holds
    (`A3.mixG`, which `GlobsTyped` admits: the typing sees a lock block of
    the payload type either way). -/
def GlobsKinds (G : Globs) : Prop :=
  ∃ κ : Nat → Bool, (∀ k t kd v, G.blk k = some ⟨t, kd, some v⟩ → KK κ v) ∧ ∀ g v, G.gl g = some v → KK κ v

/-- **A3.6, what the start may be** (`A3.Claim`'s premise): the globals as
    `GlobsTyped` asks them, and (A3.5, Agora #815) keeping lock and cell
    shares apart (`GlobsKinds`): no key is named by a lock share and by a cell
    share.  The typing cannot see that, both naming a lock block of their
    payload type, and on a start that breaks it (`A3.mixG`, `GlobsTyped` but
    not `GlobsOK`: `A3.mix_not_globsOK`) a check-out through the lock share
    changes a cell's state as no `CellOp`, a race the claim would not see.
    The make phase leaves it (`make_ok`), so `A3.claim_made` asks nothing
    more of the program. -/
structure GlobsOK (P : Prog) (G : Globs) : Prop extends GlobsTyped P G where
  kinds : GlobsKinds G

/-- **The A3.0 claim**, for A2 plus `spawn`: a program A2 types, whose
    spawned functions take only view-free `sink` parameters, is memory-safe,
    race-free and leak-free on every interleaving.  Milestone A3.0 proves it,
    and A3.1 for A2 with `Arc` (shares of view-free payloads, collected by
    reachability); A3.2–A3.6 extend the language and restate it (A3.5: a
    spawn runs the crossing check, `SendCheck`, and a race includes two
    threads changing one library handle's state, `CellRace`; A3.6: the start
    holds the module globals, `GlobsOK`, and what they reach is left at the
    end).  The stated claim is `ClaimFull`, which adds (Agora #818) that this
    race freedom is adequate for cells (`CellAdequate`). -/
def Claim : Prop :=
  ∀ (P : Prog) (spawn : Nat → Bool) (G : Globs) (s : Stmt) (Δ : Ctx) (nv : Nat),
    ProgOK P → ProgCodes P → SpawnOK P spawn → GlobsOK P G →
    StmtT P (fun _ => none) [] s Δ → s.src = true → s.codesOK P → (∀ v ∈ s.vars, v < nv) →
    MemorySafe P spawn (Cfg.start G s nv) ∧ RaceFree P spawn (Cfg.start G s nv) ∧
      NoLeak P spawn (Cfg.start G s nv)

/-- **The A3 claim, in full** (Agora #818): `Claim`'s premises and
    conclusions, and race freedom's adequacy for cells (`CellAdequate`):
    every check-out of a cell's block is a step on the cell, so `RaceFree`,
    which counts such steps through `CellOp`, sees every cell race.
    `A3.claim_full` proves it (A3/ClaimFull.lean), from `A3.claim` and
    `A3.reach_frame_cellOp`. -/
def ClaimFull : Prop :=
  ∀ (P : Prog) (spawn : Nat → Bool) (G : Globs) (s : Stmt) (Δ : Ctx) (nv : Nat),
    ProgOK P → ProgCodes P → SpawnOK P spawn → GlobsOK P G →
    StmtT P (fun _ => none) [] s Δ → s.src = true → s.codesOK P → (∀ v ∈ s.vars, v < nv) →
    MemorySafe P spawn (Cfg.start G s nv) ∧ RaceFree P spawn (Cfg.start G s nv) ∧
      NoLeak P spawn (Cfg.start G s nv) ∧ CellAdequate P spawn (Cfg.start G s nv)

/-- The view of the initial configuration is A2's empty store. -/
theorem init_view (s : Stmt) (nv : Nat) :
    (Cfg.init s nv).view ⟨fun _ => none, nv, s⟩ = emptyMem nv := rfl

end A3
