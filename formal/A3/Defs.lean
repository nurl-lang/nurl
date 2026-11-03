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

/-- A closure's code reads its environment, lent: the first parameter of the
    code it names is the environment's, borrowed (`inp`). -/
theorem _root_.A2.Implements.env_lent {P : Prog} {f : Nat} {te : Ty} {cs : List (Var × PMode × Ty)}
    {σ : Nat} (h : Implements P f te cs σ) : ∃ fn, P[f]? = some fn ∧ fn.params.head? = some (.inp, te) ∧
      ¬ ThruFn P f := by
  obtain ⟨fn, _, hf, _, hps, _, _, _, _, _, hnt⟩ := h
  exact ⟨fn, hf, by rw [hps]; rfl, hnt⟩

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
`CodeOK` holds every method's code to its interface, on the box lent
(`CodeOK.env_lent`), as a closure's one method is. -/

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

/-- Every method's code of a package reads the environment, lent, and changes
    nothing through a borrow (`Implements.env_lent`, method by method): an
    impl's code reads its box, whichever method a call picks. -/
theorem _root_.A2.CodeOK.env_lent {P : Prog} {fs : List Nat} {te : Ty} {ms : List Nat}
    {cs : List (Var × PMode × Ty)} (h : CodeOK P fs te ms cs) {j f : Nat} (hf : fs[j]? = some f) :
    ∃ fn, P[f]? = some fn ∧ fn.params.head? = some (.inp, te) ∧ ¬ ThruFn P f := by
  have hj : j < ms.length := h.1 ▸ (List.getElem?_eq_some_iff.mp hf).1
  exact (h.2 j f ms[j] hf (List.getElem?_eq_getElem hj)).env_lent

/-- An impl's code fixes the type of the box it is packed with: its first
    method takes it, as its receiver. -/
theorem _root_.A2.CodeOK.recv_eq {P : Prog} {fs : List Nat} {te te' : Ty} {ms ms' : List Nat}
    {cs cs' : List (Var × PMode × Ty)} (h : CodeOK P fs te ms cs) (h' : CodeOK P fs te' ms' cs')
    (hne : fs ≠ []) : te = te' := by
  obtain ⟨f, hf⟩ : ∃ f, fs[0]? = some f := by
    cases fs with
    | nil => exact absurd rfl hne
    | cons f _ => exact ⟨f, rfl⟩
  obtain ⟨fn, hfn, hhd, _⟩ := h.env_lent hf
  obtain ⟨fn', hfn', hhd', _⟩ := h'.env_lent hf
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
