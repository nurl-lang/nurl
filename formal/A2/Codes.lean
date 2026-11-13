import A2.Closure
import A2.Repl

/-! A2 — every package names code of its signature, at every step.

A package is made by `pack`, whose code the program checks (`Stmt.codesOK`);
everything else a step stores is, or is made from, what memory already held:
a value moved or copied, a part of one, one lent.  So the packages in memory
are the ones the program made. -/

namespace A2

/-- Every package inside `v` names code of its signature. -/
def PkgOK (P : Prog) (v : Val) : Prop :=
  ∀ fs te ms e cs, Sub (.pkg fs te ms e cs) v → CodeOK P fs te ms cs

/-- A3.5b: every package a block holds, in what it owns and in what its
    holders read, names code of its signature. -/
def BlkCodes (P : Prog) (B : Nat → Option Blk) : Prop :=
  (∀ k bl, B k = some bl → PkgOK P bl.tree ∧ PkgOK P bl.rd) ∧
  -- Agora #610: and the destructor of a `dead` block's type is one the
  -- program checked
  DeadCodes P B

theorem memCodes_iff {P : Prog} {m : Mem} :
    MemCodes P m ↔ (∀ x o V, m.st x = some ⟨o, some V⟩ → PkgOK P V) ∧ BlkCodes P m.blk :=
  ⟨fun h => ⟨fun x o V hx fs te ms e cs hs => h.1 x o V fs te ms e cs hx hs,
     fun k bl hk => ⟨fun fs te ms e cs hs => h.2.1 k bl fs te ms e cs hk (.inl hs),
       fun fs te ms e cs hs => h.2.1 k bl fs te ms e cs hk (.inr hs)⟩, h.2.2⟩,
   fun h => ⟨fun x o V fs te ms e cs hx hs => h.1 x o V hx fs te ms e cs hs,
     fun k bl fs te ms e cs hk hs => hs.elim (fun hs => (h.2.1 k bl hk).1 fs te ms e cs hs)
       (fun hs => (h.2.1 k bl hk).2 fs te ms e cs hs), h.2.2⟩⟩

/-- The blocks' packages name code of their signature. -/
theorem MemCodes.blk {P : Prog} {m : Mem} (h : MemCodes P m) : BlkCodes P m.blk := (memCodes_iff.mp h).2

theorem PkgOK.sub {P : Prog} {u v : Val} (h : PkgOK P v) (hs : Sub u v) : PkgOK P u :=
  fun fs te ms e cs hp => h fs te ms e cs (hp.trans hs)

theorem pkgOK_leaf {P : Prog} {v : Val} (hv : ∀ fs te ms e cs, v ≠ .pkg fs te ms e cs)
    (hc : ∀ e, ¬ Child e v) : PkgOK P v := by
  intro fs te ms e cs hs
  rcases hs.cases' with h | ⟨e', hc', _⟩
  · exact absurd h.symm (hv fs te ms e cs)
  · exact absurd hc' (hc e')

theorem pkgOK_int (P : Prog) (n : Nat) : PkgOK P (.int n) :=
  pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
theorem pkgOK_href (P : Prog) (c : Nat) : PkgOK P (.href c) :=
  pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
theorem pkgOK_view (P : Prog) (d o l : Nat) : PkgOK P (.view d o l) :=
  pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)

/-- A value built from parts: its packages are theirs, and its own. -/
theorem pkgOK_of_children {P : Prog} {v : Val}
    (hself : ∀ fs te ms e cs, v = .pkg fs te ms e cs → CodeOK P fs te ms cs)
    (hc : ∀ e, Child e v → PkgOK P e) : PkgOK P v := by
  intro fs te ms e cs hs
  rcases hs.cases' with h | ⟨e', hc', hs'⟩
  · exact hself fs te ms e cs h.symm
  · exact hc e' hc' fs te ms e cs hs'

theorem PkgOK.child {P : Prog} {e v : Val} (h : PkgOK P v) (hc : Child e v) : PkgOK P e :=
  h.sub (hc.sub (Sub.refl _))

/-- Lending a value keeps its packages' code. -/
theorem pkgOK_lend {P : Prog} : ∀ {v : Val}, PkgOK P v → PkgOK P (lendOf v)
  | .int _, h => h
  | .href _, h => h
  | .view _ _ _, h => h
  | .arc _ _, h => h
  | .lk _, h => h
  | .cell _, h => h
  | .node _ c _ _, _ => pkgOK_href P c
  | .pair v w, h => by
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | fst => exact pkgOK_lend (h.child Child.fst)
    | snd => exact pkgOK_lend (h.child Child.snd)
  | .inl v, h => by
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | inl => exact pkgOK_lend (h.child Child.inl)
  | .inr v, h => by
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | inr => exact pkgOK_lend (h.child Child.inr)
  | .pkg fs te ms v cs, h => by
    refine pkgOK_of_children (fun fs' te' ms' e cs' he => ?_) (fun e hc => ?_)
    · cases he; exact h fs te ms v cs (Sub.refl _)
    · cases hc with
      | pkg => exact pkgOK_lend (h.child Child.pkg)

theorem MemCodes.slot {P : Prog} {m : Mem} (h : MemCodes P m) {x : Var} {o : Bool} {V : Val}
    (hx : m.st x = some ⟨o, some V⟩) : PkgOK P V := (memCodes_iff.mp h).1 x o V hx

theorem MemCodes.set {P : Prog} {m : Mem} (h : MemCodes P m) {x : Var} {o : Bool} {v : Option Val}
    (hv : ∀ V, v = some V → PkgOK P V) : MemCodes P (m.set x ⟨o, v⟩) := by
  refine memCodes_iff.mpr ⟨fun y o' V hy => ?_, h.blk⟩
  by_cases hyx : y = x
  · subst hyx; simp at hy; obtain ⟨_, rfl⟩ := hy; exact hv V rfl
  · simp [upd_ne _ _ hyx] at hy; exact h.slot hy

theorem MemCodes.remove {P : Prog} {m : Mem} (h : MemCodes P m) (x : Var) : MemCodes P (m.remove x) := by
  refine memCodes_iff.mpr ⟨fun y o' V hy => ?_, h.blk⟩
  by_cases hyx : y = x
  · subst hyx; simp at hy
  · simp [upd_ne _ _ hyx] at hy; exact h.slot hy

/-- A3.5b: the slots of one store, the blocks of another. -/
theorem MemCodes.withBlk {P : Prog} {m m' : Mem} (h : MemCodes P m) (hst : m'.st = m.st)
    (hb : BlkCodes P m'.blk) : MemCodes P m' :=
  memCodes_iff.mpr ⟨fun y o V hy => h.slot (by rw [← hst]; exact hy), hb⟩

theorem MemCodes.of_st {P : Prog} {m m' : Mem} (h : MemCodes P m) (hst : m'.st = m.st)
    (hb : m'.blk = m.blk := by rfl) : MemCodes P m' :=
  h.withBlk hst (by rw [hb]; exact h.blk)

/-- A3.5b: a block whose payload's packages name code of their signature.
    (Agora #610, #755: and whose destructor, if its type is a destructor
    type or a drained `Vec` of them, the program checked; a block of no such
    type, an integer lock, a view, has nothing more to check.) -/
theorem BlkCodes.upd {P : Prog} {B : Nat → Option Blk} (h : BlkCodes P B) {k : Nat} {bl : Blk}
    (hbl : PkgOK P bl.tree ∧ PkgOK P bl.rd)
    (hd : ∀ f u, bl.ty.Reaps f u → DropFnOK P f u := by reaps_none) :
    BlkCodes P (upd B k (some bl)) := by
  refine ⟨fun k' bl' hk' => ?_, fun k' bl' hk' => ?_⟩
  · by_cases hkk : k' = k
    · subst hkk; rw [upd_same] at hk'; cases hk'; exact hbl
    · rw [upd_ne _ _ hkk] at hk'; exact h.1 k' bl' hk'
  · by_cases hkk : k' = k
    · subst hkk; rw [upd_same] at hk'; cases hk'; exact hd
    · rw [upd_ne _ _ hkk] at hk'; exact h.2 k' bl' hk'

/-- Agora #755: a block put where one of the same type was (a lock block
    whose payload is checked out, given back or changed) keeps its
    destructor's check. -/
theorem BlkCodes.updSame {P : Prog} {B : Nat → Option Blk} (h : BlkCodes P B) {k : Nat} {bl0 bl : Blk}
    (hbl : PkgOK P bl.tree ∧ PkgOK P bl.rd) (hk : B k = some bl0) (hty : bl.ty = bl0.ty := by rfl) :
    BlkCodes P (A2.upd B k (some bl)) :=
  BlkCodes.upd h hbl (h.2.upd_same hk hty)

/-- Agora #610: ... a `dead` block's: it owns its payload, and no one reads it. -/
theorem blkCodes_dead {P : Prog} {t : Ty} {p : Option Val} (hp : ∀ v, p = some v → PkgOK P v) :
    PkgOK P (Blk.tree ⟨t, .dead, p⟩) ∧ PkgOK P (Blk.rd ⟨t, .dead, p⟩) := by
  refine ⟨?_, pkgOK_int P 0⟩
  cases p with
  | none => exact pkgOK_int P 0
  | some v => exact hp v rfl

/-- ... a lock block's: it owns its payload, and its holders read nothing. -/
theorem blkCodes_lock {P : Prog} {t : Ty} {p : Option Val} (hp : ∀ v, p = some v → PkgOK P v) :
    PkgOK P (Blk.tree ⟨t, .lock, p⟩) ∧ PkgOK P (Blk.rd ⟨t, .lock, p⟩) := by
  refine ⟨?_, pkgOK_int P 0⟩
  cases p with
  | none => exact pkgOK_int P 0
  | some v => exact hp v rfl

/-- ... an `arc` block's: it owns its payload, which its holders read. -/
theorem blkCodes_arc {P : Prog} {t : Ty} {v : Val} (hv : PkgOK P v) :
    PkgOK P (Blk.tree ⟨t, .arc, some v⟩) ∧ PkgOK P (Blk.rd ⟨t, .arc, some v⟩) := ⟨hv, hv⟩

/-- ... a view's: it owns nothing, and its holders read its payload. -/
theorem blkCodes_view {P : Prog} {t : Ty} {v : Val} (hv : PkgOK P v) :
    PkgOK P (Blk.tree ⟨t, .view, some v⟩) ∧ PkgOK P (Blk.rd ⟨t, .view, some v⟩) := ⟨pkgOK_int P 0, hv⟩

/-- A node found in memory: its packages name code of their signature. -/
theorem MemCodes.nodeAt {P : Prog} {m : Mem} (h : MemCodes P m)
    (hB : ∀ k bl, m.blk k = some bl → PkgOK P bl.tree ∧ PkgOK P bl.rd) {c : Nat} {n : Val} (hn : NodeAt m c n) :
    PkgOK P n := by
  rcases hn with ⟨x, t, hx, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
  · exact (h.slot hx).sub hs
  · exact (hB k bl hk).2.sub hs

theorem MemCodes.dataAt {P : Prog} {m : Mem} (h : MemCodes P m)
    (hB : ∀ k bl, m.blk k = some bl → PkgOK P bl.tree ∧ PkgOK P bl.rd) {d : Nat} {n : Val} (hn : DataAt m d n) :
    PkgOK P n := by
  rcases hn with ⟨x, t, hx, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
  · exact (h.slot hx).sub hs
  · exact (hB k bl hk).2.sub hs

theorem MemCodes.vecOf {P : Prog} {m : Mem} (h : MemCodes P m)
    (hB : ∀ k bl, m.blk k = some bl → PkgOK P bl.tree ∧ PkgOK P bl.rd) {y : Var} {t : Ty} {c d : Nat}
    {es : List Val} (hv : VecOf m y t c d es) : PkgOK P (.node t c d es) := by
  obtain ⟨_, _, hv | ⟨_, hn⟩⟩ := hv
  · exact h.slot hv
  · exact h.nodeAt hB hn

theorem pkgOK_elem {P : Prog} {t : Ty} {c d : Nat} {es : List Val} (h : PkgOK P (.node t c d es))
    {e : Val} (he : e ∈ es) : PkgOK P e := h.child (Child.elem he)

/-- Rewriting a tree at one node keeps its packages' code, when the new
    node's packages are fine (#295). -/
theorem Repl.pkgOK_new {P : Prog} {n n' T T' : Val} (hr : Repl n n' T T') (hT : PkgOK P T)
    (hn' : PkgOK P n') : PkgOK P T' := by
  induction hr with
  | here => exact hn'
  | @elem t c d pre post e e' _ ih =>
    refine pkgOK_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | elem hx =>
      rcases List.mem_append.mp hx with hx | hx
      · exact hT.child (Child.elem (List.mem_append_left _ hx))
      · rcases List.mem_cons.mp hx with rfl | hx
        · exact ih (hT.child (Child.elem (List.mem_append_right _ (List.mem_cons_self ..))))
        · exact hT.child (Child.elem (List.mem_append_right _ (List.mem_cons_of_mem _ hx)))
  | fst _ ih =>
    refine pkgOK_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | fst => exact ih (hT.child Child.fst)
    | snd => exact hT.child Child.snd
  | snd _ ih =>
    refine pkgOK_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | fst => exact hT.child Child.fst
    | snd => exact ih (hT.child Child.snd)
  | inl _ ih =>
    refine pkgOK_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | inl => exact ih (hT.child Child.inl)
  | inr _ ih =>
    refine pkgOK_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | inr => exact ih (hT.child Child.inr)
  | pkg _ ih =>
    refine pkgOK_of_children (fun fs te ms e cs h => ?_) (fun x hc => ?_)
    · cases h; exact hT _ _ _ _ _ (Sub.refl _)
    · cases hc with
      | pkg => exact ih (hT.child Child.pkg)

theorem TakeVal.codes {P : Prog} {m m1 : Mem} {y : Var} {v : Val} (ht : TakeVal m y v m1)
    (h : MemCodes P m) : PkgOK P v ∧ MemCodes P m1 := by
  cases ht with
  | own hv => exact ⟨h.slot hv, h.set (fun _ e => by cases e)⟩
  | bor hv => exact ⟨h.slot hv, h⟩

theorem EvalR.codes {P : Prog} {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (he : EvalR m r (.ok v o m1))
    (h : MemCodes P m) (hB : ∀ k bl, m.blk k = some bl → PkgOK P bl.tree ∧ PkgOK P bl.rd) (hr : r.codeOK P) :
    PkgOK P v ∧ MemCodes P m1 := by
  cases he with
  | expr _ => exact ⟨pkgOK_int P _, h⟩
  | new =>
    refine ⟨pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h.of_st rfl⟩
    cases hc with | elem he => simp at he
  | moveOwn hv => exact ⟨h.slot hv, h.set (fun _ e => by cases e)⟩
  | copy hv => exact ⟨h.slot hv, h⟩
  | borrowOwn _ => exact ⟨pkgOK_href P _, h⟩
  | borrowBor hv => exact ⟨h.slot hv, h⟩
  | «at» hn hv _ => exact ⟨pkgOK_lend (pkgOK_elem (h.vecOf hB hv) (List.getElem_mem hn)), h⟩
  | view _ => exact ⟨pkgOK_view P _ _ _, h⟩
  | sat hn _ _ _ _ hda => exact ⟨pkgOK_lend (pkgOK_elem (h.dataAt hB hda) (List.getElem_mem hn)), h⟩
  | pop hv _ _ =>
    have hT := h.slot hv
    refine ⟨pkgOK_elem hT (by simp), h.set (fun V e => ?_)⟩
    cases e
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with | elem he => exact pkgOK_elem hT (by simp [he])
  | remove hn hv _ _ _ =>
    have hT := h.slot hv
    refine ⟨pkgOK_elem hT (List.getElem_mem hn), h.set (fun V e => ?_)⟩
    cases e
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with | elem he => exact pkgOK_elem hT (List.mem_of_mem_eraseIdx he)
  | pair h1 h2 =>
    obtain ⟨hv, hm1⟩ := h1.codes h
    obtain ⟨hw, hm2⟩ := h2.codes hm1
    refine ⟨pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), hm2⟩
    cases hc with
    | fst => exact hv
    | snd => exact hw
  | fst hv => exact ⟨pkgOK_lend ((h.slot hv).child Child.fst), h⟩
  | snd hv => exact ⟨pkgOK_lend ((h.slot hv).child Child.snd), h⟩
  | inl h1 =>
    obtain ⟨hv, hm1⟩ := h1.codes h
    refine ⟨pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), hm1⟩
    cases hc with | inl => exact hv
  | inr h1 =>
    obtain ⟨hv, hm1⟩ := h1.codes h
    refine ⟨pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), hm1⟩
    cases hc with | inr => exact hv
  | getl hv => exact ⟨pkgOK_lend ((h.slot hv).child Child.inl), h⟩
  | getr hv => exact ⟨pkgOK_lend ((h.slot hv).child Child.inr), h⟩
  | takel hv => exact ⟨(h.slot hv).child Child.inl, h.set (fun _ e => by cases e)⟩
  | taker hv => exact ⟨(h.slot hv).child Child.inr, h.set (fun _ e => by cases e)⟩
  | pack h1 =>
    obtain ⟨hv, hm1⟩ := h1.codes h
    refine ⟨pkgOK_of_children (fun fs te ms e cs he => ?_) (fun e hc => ?_), hm1⟩
    · cases he; exact hr
    · cases hc with | pkg => exact hv
  | arcNew h1 _ =>
    -- A3.5b: the payload may hold packages, the ones the value moved in held
    obtain ⟨hv, hm1⟩ := h1.codes h
    exact ⟨pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h),
      hm1.withBlk rfl (hm1.blk.upd (blkCodes_arc hv) hr)⟩
  | lockNew h1 _ =>
    obtain ⟨hv, hm1⟩ := h1.codes h
    exact ⟨pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h),
      hm1.withBlk rfl (hm1.blk.upd (blkCodes_lock fun _ e => by cases e; exact hv) hr)⟩
  | arcClone _ => exact ⟨pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | lockClone _ => exact ⟨pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | cellNew h1 _ =>
    obtain ⟨hv, hm1⟩ := h1.codes h
    exact ⟨pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h),
      hm1.withBlk rfl (hm1.blk.upd (blkCodes_lock fun _ e => by cases e; exact hv) hr)⟩
  | cellClone _ => exact ⟨pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | glob _ hf =>
    rcases hf with ⟨_, _, _, _, rfl, _⟩ | ⟨_, _, _, _, rfl, _⟩ <;>
      exact ⟨pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | rwRead _ hk _ =>
    -- A3.3: the view's payload is a share of the lock block and a copy of its payload
    have hp := (hB _ _ hk).1
    refine ⟨pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h),
      h.withBlk rfl (h.blk.upd (blkCodes_view ?_))⟩
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | fst => exact pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
    | snd => exact hp
  | rwTryRead _ hk _ =>
    -- A3.3: `rw_read`'s, the guard as `some`
    have hp := (hB _ _ hk).1
    refine ⟨pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_),
      h.withBlk rfl (h.blk.upd (blkCodes_view ?_))⟩
    · cases hc with
      | inr => exact pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | fst => exact pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
    | snd => exact hp
  | rwTryReadNone _ _ | rwTryWriteNone _ _ =>
    refine ⟨pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h⟩
    cases hc with
    | inl => exact pkgOK_int P _
  | rwTryWrite _ _ _ =>
    refine ⟨pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h⟩
    cases hc with
    | inr => exact pkgOK_int P _
  | atomic _ _ _ _ =>
    exact ⟨pkgOK_int P _, h.withBlk rfl (h.blk.upd (blkCodes_lock fun _ e => by cases e; exact pkgOK_int P _))⟩
  | @chanSend _ _ _ k _ u c d es _ _ _ h1 hk _ _ _ =>
    -- A3.4: the queue's elements, and the value sent
    obtain ⟨hv, hm1⟩ := h1.codes h
    have hp : PkgOK P (.pair (.node u c d es) (.int 0)) := (hm1.blk.1 _ _ hk).1
    refine ⟨pkgOK_int P _, hm1.withBlk rfl (hm1.blk.updSame (blkCodes_lock fun _ e => ?_) hk)⟩
    cases e
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | fst =>
      refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with
      | elem he =>
        rcases List.mem_append.mp he with he | he
        · exact pkgOK_elem (hp.child Child.fst) he
        · simp at he; subst he; exact hv
    | snd => exact pkgOK_int P _
  | @chanSendClosed _ _ _ k t s q f v m1 _ h1 hk ht _ _ =>
    -- Agora #755: the value goes into a lock block of the queue's element
    -- type, whose destructor is the channel's elements' (`Ty.Reaps.chan`)
    obtain ⟨hv, hm1⟩ := h1.codes h
    refine ⟨pkgOK_int P _, hm1.withBlk rfl (hm1.blk.upd (blkCodes_lock fun _ e => by cases e; exact hv)
      (fun f' u' hr => ?_))⟩
    exact hm1.blk.2 k _ hk f' u' (.chan ht hr)
  | @chanRecv _ _ _ _ _ u c d f v es _ hk _ _ =>
    -- A3.4: the queue's head was in the channel's payload
    have hp : PkgOK P (.pair (.node u c d (v :: es)) (.int f)) := (hB _ _ hk).1
    refine ⟨pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_),
      h.withBlk rfl (h.blk.updSame (blkCodes_lock fun _ e => ?_) hk)⟩
    · cases hc with
      | inr => exact pkgOK_elem (hp.child Child.fst) (List.mem_cons_self ..)
    · cases e
      refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with
      | fst =>
        refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
        cases hc with
        | elem he => exact pkgOK_elem (hp.child Child.fst) (List.mem_cons_of_mem _ he)
      | snd => exact pkgOK_int P _
  | chanRecvNone _ _ _ _ =>
    refine ⟨pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h⟩
    cases hc with
    | inl => exact pkgOK_int P _
  | lockTake _ hk _ =>
    -- A3.2's second cut: the taken payload's packages were the block's
    exact ⟨(hB _ _ hk).1, h.withBlk rfl (h.blk.updSame (blkCodes_lock fun _ e => by cases e) hk)⟩
  | lockRestore _ h1 hk =>
    obtain ⟨hv, hm1⟩ := h1.codes h
    exact ⟨pkgOK_int P _, hm1.withBlk rfl (hm1.blk.updSame (blkCodes_lock fun _ e => by cases e; exact hv) hk)⟩
  | @chanClose _ _ k _ q _ _ hk _ =>
    have hp : PkgOK P (.pair q (.int _)) := (hB _ _ hk).1
    refine ⟨pkgOK_int P _, h.withBlk rfl (h.blk.updSame (blkCodes_lock fun _ e => ?_) hk)⟩
    cases e
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | fst => exact hp.child Child.fst
    | snd => exact pkgOK_int P _
  | arcGet _ hk => exact ⟨pkgOK_lend (hB _ _ hk).2, h⟩

theorem BindParams.codes {P : Prog} {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (hb : BindParams m ps as base i m') (h : MemCodes P m) : MemCodes P m' := by
  induction hb with
  | nil => exact h
  | @inp m _ _ _ a _ _ _ sl v ha hl _ ih =>
    refine ih (h.set (fun V e => ?_))
    cases e
    obtain ⟨o, val⟩ := sl
    cases o <;> cases val <;> simp [lendSlot] at hl
    · subst hl; exact h.slot ha
    · subst hl; exact pkgOK_lend (h.slot ha)
  | sink ha _ ih => exact ih ((h.set (fun _ e => by cases e)).set (fun V e => by cases e; exact h.slot ha))
  | inout _ ih => exact ih h

/-! ### The program's packages -/

/-- A package's code is checked against the modes and types of its captures,
    not their names. -/
theorem codeOK_caps_rename {P : Prog} {fs : List Nat} {te : Ty} {ms : List Nat} (ρ : Var → Var)
    (cs : List (Var × PMode × Ty)) :
    CodeOK P fs te ms (cs.map (fun c => (ρ c.1, c.2))) ↔ CodeOK P fs te ms cs := by
  have h : (cs.map (fun c => (ρ c.1, c.2))).map (·.2) = cs.map (·.2) := by
    simp [List.map_map, Function.comp_def]
  unfold CodeOK Implements
  simp only [h, List.map_eq_nil_iff]

theorem Rhs.codeOK_rename {P : Prog} (ρ : Var → Var) (r : Rhs) : (r.rename ρ).codeOK P ↔ r.codeOK P := by
  cases r with
  | pack fs te ms y cs => exact codeOK_caps_rename ρ cs
  | arcNew t y => cases t <;> exact Iff.rfl
  | _ => exact Iff.rfl

theorem Stmt.codesOK_rename {P : Prog} (ρ : Var → Var) (s : Stmt) : (s.rename ρ).codesOK P ↔ s.codesOK P := by
  induction s with
  | seq a b iha ihb => simp only [Stmt.rename, Stmt.codesOK, iha, ihb]
  | letv x r s ih => simp only [Stmt.rename, Stmt.codesOK, ih, Rhs.codeOK_rename]
  | letd x f r s ih => simp only [Stmt.rename, Stmt.codesOK, ih, Rhs.codeOK_rename]
  | assign x r => simp only [Stmt.rename, Stmt.codesOK, Rhs.codeOK_rename]
  | ite c a b iha ihb => simp only [Stmt.rename, Stmt.codesOK, iha, ihb]
  | letcall _ _ _ _ ih | «while» _ _ ih | scope _ _ ih | rbind _ _ ih | frozen _ _ ih | letrec _ _ _ ih
  | catchR _ _ _ ih | unpair _ _ _ _ ih | callc _ _ _ _ _ ih | scopeD _ _ _ ih | withLock _ _ _ ih
  | scopeL _ _ _ _ ih | withElem _ _ _ _ ih | callcE _ _ _ _ _ ih =>
    simp only [Stmt.rename, Stmt.codesOK, ih]
  | _ => exact Iff.rfl

theorem wrapParams_codes {P : Prog} {s : Stmt} (hs : s.codesOK P) :
    ∀ (ps : List (PMode × Ty)) (base i : Nat), (wrapParams ps base i s).codesOK P := by
  intro ps
  induction ps with
  | nil => intro _ _; exact hs
  | cons p ps ih =>
    intro base i
    obtain ⟨pm, t⟩ := p
    cases pm <;> simp only [wrapParams, Stmt.codesOK] <;> exact ih base (i + 1)

theorem callIn_codes {P : Prog} (hPc : ProgCodes P) {f : Nat} {fn : Fn} (hf : P[f]? = some fn)
    (args : List Var) (base : Nat) (x : Var) : (callIn fn args base x).codesOK P := by
  have hb : (fn.body.rename (callRen fn.params args base)).codesOK P :=
    (Stmt.codesOK_rename _ _).mpr (hPc fn (List.mem_of_getElem? hf))
  have he : ∀ r s, (resFrame fn r s).codesOK P = s.codesOK P := fun r s => by
    unfold resFrame; split <;> rfl
  show (resFrame fn _ _).codesOK P
  rw [he]
  exact ⟨wrapParams_codes hb _ _ _, trivial⟩

/-- A3.2: a lock scope's end gives `x`'s value, with its packages, back to the
    block, or drops it. -/
theorem Release.codes {P : Prog} {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (hrl : Release m k t x m')
    (hm : MemCodes P m) : MemCodes P m' := by
  cases hrl with
  | put hx _ hk =>
    refine MemCodes.remove ?_ _
    exact hm.withBlk rfl (hm.blk.updSame (blkCodes_lock fun _ e => by cases e; exact hm.slot hx) hk.1)
  | drop _ _ _ => exact (hm.of_st rfl).remove _

/-- Every step keeps every package naming code of its signature. -/
theorem codes_step {P : Prog} (hPc : ProgCodes P) {m : Mem} {s : Stmt} {r : Res} (hst : Step P m s r) :
    MemCodes P m → (∀ k bl, m.blk k = some bl → PkgOK P bl.tree ∧ PkgOK P bl.rd) → s.codesOK P →
      (∀ m' s', r = .ok m' s' → MemCodes P m' ∧ s'.codesOK P) ∧ (∀ m', r = .panic m' → MemCodes P m') := by
  induction hst with
  | seqSkip =>
    intro hm _ hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, hs.2⟩
  | seqL _ ih =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨h1, h2⟩ := (ih hm hB hs.1).1 _ _ rfl; exact ⟨h1, h2, hs.2⟩
  | seqP _ ih =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact (ih hm hB hs.1).2 _ rfl
  | letv _ he =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := he.codes hm hB hs.1
    exact ⟨hm1.set (fun V e => by cases e; exact hv), hs.2⟩
  | letvP _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | letcall hf _ hb =>
    intro hm _ hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(((hb.codes hm).set (fun _ e => by cases e)).set (fun _ e => by cases e)).of_st rfl,
      callIn_codes hPc hf _ _ _, hs⟩
  | scopeSkip _ _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(hm.of_st rfl).remove _, trivial⟩
  | scopeIn _ ih | rbindIn _ ih | frozenIn _ ih | catchIn _ ih | scopeLIn _ ih =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨h1, h2⟩ := (ih hm hB hs).1 _ _ rfl; exact ⟨h1, h2⟩
  | scopeP _ _ _ ih =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact (((ih hm hB hs).2 _ rfl).of_st rfl).remove _
  | scopeLP _ hrl ih =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hrl.codes ((ih hm hB hs).2 _ rfl)
  | withLock _ hk _ =>
    -- A3.2: the payload checked out, with its packages, goes to `x`
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    refine ⟨MemCodes.set ?_ (fun V e => by cases e; exact (hB _ _ hk).1), hs⟩
    exact hm.withBlk rfl (hm.blk.updSame (blkCodes_lock fun _ e => by cases e) hk)
  | @reap r0 k0 n f u p _ hk _ =>
    -- Agora #610: the payload moved out, with its packages, goes to the fresh
    -- binding; the block stays a `dead` block of its type
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    refine ⟨MemCodes.withBlk (m := m.set m.nv ⟨true, some p⟩)
      (MemCodes.set hm (fun V e => by cases e; exact (hB _ _ hk).1)) rfl
      (hm.blk.upd (blkCodes_dead fun _ e => by cases e)
        (fun f' u' hr => hm.dead k0 _ hk f' u' hr)), trivial, hs⟩
  | scopeLSkip hrl _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hrl.codes hm, trivial⟩
  | scopeLFail _ _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, trivial⟩
  | rbindSkip _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm.remove _, trivial⟩
  | rbindP _ _ ih =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ((ih hm hB hs).2 _ rfl).remove _
  | frozenSkip | catchSkip =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, trivial⟩
  | frozenP _ ih =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact (ih hm hB hs).2 _ rfl
  | catchP _ _ ih =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨((ih hm hB hs).2 _ rfl).set (fun V e => by cases e; exact pkgOK_int P 1), trivial⟩
  | assign _ he _ _ =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := he.codes hm hB hs
    exact ⟨(hm1.of_st rfl).set (fun V e => by cases e; exact hv), trivial⟩
  | assignP _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | iteT _ _ =>
    intro hm _ hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, hs.1⟩
  | iteF _ =>
    intro hm _ hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, hs.2⟩
  | «while» =>
    intro hm _ hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, ⟨hs, hs⟩, trivial⟩
  | push ht hx _ _ | pushRealloc ht hx _ _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := ht.codes hm
    have hT := hm1.slot hx
    refine ⟨(hm1.of_st rfl).set (fun V e => ?_), trivial⟩
    cases e
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | elem he =>
      rcases List.mem_append.mp he with he | he
      · exact pkgOK_elem hT he
      · simp at he; subst he; exact hv
  | withElem hn hv _ _ _ _ =>
    intro hm _ hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hv
    refine ⟨(hm.set (fun V e => ?_)).set (fun V e => ?_), hs, trivial⟩
    · cases e
      refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with
      | elem he =>
        rcases List.mem_append.mp he with he | he
        · exact pkgOK_elem hT (List.mem_of_mem_take he)
        · exact pkgOK_elem hT (List.mem_of_mem_drop he)
    · cases e; exact pkgOK_elem hT (List.getElem_mem hn)
  | withElemOOB _ _ _ _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | insert _ ht hx _ _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := ht.codes hm
    have hT := hm1.slot hx
    refine ⟨(hm1.of_st rfl).set (fun V e => ?_), trivial⟩
    cases e
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | elem he =>
      rcases List.mem_append.mp he with he | he
      · exact pkgOK_elem hT (List.mem_of_mem_take he)
      · rcases List.mem_cons.mp he with he | he
        · subst he; exact hv
        · exact pkgOK_elem hT (List.mem_of_mem_drop he)
  | free _ _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(hm.of_st rfl).set (fun _ e => by cases e), trivial⟩
  | editPush ht hn hr | editPushRealloc ht hn hr =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := ht.codes hm
    have hT := hm1.slot hn.2.2.1
    have hn0 := hT.sub hr.sub
    refine ⟨(hm1.of_st rfl).set (fun V e => ?_), trivial⟩
    cases e
    refine hr.pkgOK_new hT ?_
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | elem he =>
      rcases List.mem_append.mp he with he | he
      · exact pkgOK_elem hn0 he
      · simp at he; subst he; exact hv
  | editTrunc _ hn _ hr =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hn.2.2.1
    have hn0 := hT.sub hr.sub
    refine ⟨(hm.of_st rfl).set (fun V e => ?_), trivial⟩
    cases e
    refine hr.pkgOK_new hT ?_
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | elem he => exact pkgOK_elem hn0 (List.mem_of_mem_take he)
  | editSet _ _ ht hn _ hr =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := ht.codes hm
    have hT := hm1.slot hn.2.2.1
    have hn0 := hT.sub hr.sub
    refine ⟨(hm1.of_st rfl).set (fun V e => ?_), trivial⟩
    cases e
    refine hr.pkgOK_new hT ?_
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | elem he =>
      rcases List.mem_or_eq_of_mem_set he with he | he
      · exact pkgOK_elem hn0 he
      · subst he; exact hv
  | editSetOOB _ ht _ _ _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(ht.codes hm).2.of_st rfl, trivial⟩
  | panic =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | waitPanic _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | letrec hf _ _ =>
    intro hm _ hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨((hm.set (fun _ e => by cases e)).set (fun _ e => by cases e)).of_st rfl,
      ⟨callIn_codes hPc hf _ _ _, hs⟩⟩
  | unpair hy _ _ _ =>
    intro hm _ hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hy
    exact ⟨((hm.set (fun _ e => by cases e)).set (fun V e => by cases e; exact hT.child Child.fst)).set
      (fun V e => by cases e; exact hT.child Child.snd), hs⟩
  | letd _ he =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := he.codes hm hB hs.1
    exact ⟨hm1.set (fun V e => by cases e; exact hv), hs.2⟩
  | letdP _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | scopeDIn _ ih =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨h1, h2⟩ := (ih hm hB hs).1 _ _ rfl; exact ⟨h1, h2⟩
  | scopeDEnd _ _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm.of_st rfl, trivial⟩
  | scopeDDrain _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm.of_st rfl, by simp [Stmt.codesOK, Rhs.codeOK]⟩
  | scopeDEmpty _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, trivial⟩
  | scopeDPDrain _ _ ih =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(ih hm hB hs).2 _ rfl, trivial, trivial⟩
  | scopeDMoved _ =>
    intro hm _ _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm.remove _, trivial⟩
  | scopeDP _ _ _ ih =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨((ih hm hB hs).2 _ rfl).of_st rfl, trivial, trivial⟩
  | scopeDPMoved _ _ ih =>
    intro hm hB hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ((ih hm hB hs).2 _ rfl).remove _
  | callc hslot _ hf _ hb =>
    intro hm _ hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hslot
    have hme : MemCodes P (envMem _ _) :=
      (hm.set (fun V e => by cases e; exact pkgOK_lend (hT.child Child.pkg))).of_st rfl
    exact ⟨(((hb.codes hme).set (fun _ e => by cases e)).set (fun _ e => by cases e)).of_st rfl,
      ⟨callIn_codes hPc hf _ _ _, hs⟩⟩

  | callcE hc _ _ _ =>
    -- A2-envhand: the environment, with its packages, moves to its binding;
    -- the package it goes back into names the code it came from
    intro hm _ hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hc
    exact ⟨(((hm.set (fun _ e => by cases e)).set (fun V e => by cases e; exact hT.child Child.pkg)).set
      (fun _ e => by cases e)).of_st rfl, ⟨trivial, hm.1 _ _ _ _ _ _ _ _ hc (Sub.refl _)⟩, hs⟩
  | callcD hc _ _ _ _ =>
    -- Agora #609: the environment moves to its binding, for good
    intro hm _ hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hc
    exact ⟨(((hm.set (fun _ e => by cases e)).set (fun V e => by cases e; exact hT.child Child.pkg)).set
      (fun _ e => by cases e)).of_st rfl, trivial, hs⟩

/-! ### A3.6: a program reads each module global at its declared type

The static link between a read `glob g t` and global `g`'s declaration.  A
program's global type environment `GT` gives each declared global its type
(A3/Make.lean: the declarations' types); a typed program reads every global
at it (`ProgGlobs`, `Stmt.globsAt`), a program-wide check beside the typing,
as `ProgCodes` is (`RhsT` takes no program).  No step makes a read the
statement did not have, but one of a function's body, renamed, which reads
what the body reads (`globs_step`). -/

/-- A3.6: a global type environment: global `g`'s declared type. -/
abbrev GTy := Nat → Option Ty

/-- A read of a global is at its declared type. -/
def Rhs.globAt (GT : GTy) : Rhs → Prop
  | .glob g t => GT g = some t
  | _ => True

/-- Every read of a global a statement makes is at its declared type. -/
def Stmt.globsAt (GT : GTy) : Stmt → Prop
  | .seq a b => a.globsAt GT ∧ b.globsAt GT
  | .letv _ r s => r.globAt GT ∧ s.globsAt GT
  | .letcall _ _ _ s => s.globsAt GT
  | .assign _ r => r.globAt GT
  | .ite _ a b => a.globsAt GT ∧ b.globsAt GT
  | .while _ s => s.globsAt GT
  | .scope _ s => s.globsAt GT
  | .rbind _ s => s.globsAt GT
  | .frozen _ s => s.globsAt GT
  | .letrec _ _ s => s.globsAt GT
  | .catchR _ _ s => s.globsAt GT
  | .unpair _ _ _ s => s.globsAt GT
  | .callc _ _ _ _ s => s.globsAt GT
  | .letd _ _ r s => r.globAt GT ∧ s.globsAt GT
  | .scopeD _ _ s => s.globsAt GT
  | .withLock _ _ s => s.globsAt GT
  | .scopeL _ _ _ s => s.globsAt GT
  | .withElem _ _ _ s => s.globsAt GT
  | .callcE _ _ _ _ s => s.globsAt GT
  | _ => True

/-- **A3.6: the program reads its globals at their declared types**: every
    function's body does. -/
def ProgGlobs (P : Prog) (GT : GTy) : Prop := ∀ fn ∈ P, fn.body.globsAt GT

/-- A read names no variable: renaming leaves it. -/
theorem Rhs.globAt_rename {GT : GTy} (ρ : Var → Var) (r : Rhs) : (r.rename ρ).globAt GT ↔ r.globAt GT := by
  cases r <;> exact Iff.rfl

theorem Stmt.globsAt_rename {GT : GTy} (ρ : Var → Var) (s : Stmt) : (s.rename ρ).globsAt GT ↔ s.globsAt GT := by
  induction s with
  | seq a b iha ihb => simp only [Stmt.rename, Stmt.globsAt, iha, ihb]
  | letv x r s ih => simp only [Stmt.rename, Stmt.globsAt, ih, Rhs.globAt_rename]
  | letd x f r s ih => simp only [Stmt.rename, Stmt.globsAt, ih, Rhs.globAt_rename]
  | assign x r => simp only [Stmt.rename, Stmt.globsAt, Rhs.globAt_rename]
  | ite c a b iha ihb => simp only [Stmt.rename, Stmt.globsAt, iha, ihb]
  | letcall _ _ _ _ ih | «while» _ _ ih | scope _ _ ih | rbind _ _ ih | frozen _ _ ih | letrec _ _ _ ih
  | catchR _ _ _ ih | unpair _ _ _ _ ih | callc _ _ _ _ _ ih | scopeD _ _ _ ih | withLock _ _ _ ih
  | scopeL _ _ _ _ ih | withElem _ _ _ _ ih | callcE _ _ _ _ _ ih =>
    simp only [Stmt.rename, Stmt.globsAt, ih]
  | _ => exact Iff.rfl

theorem wrapParams_globs {GT : GTy} {s : Stmt} (hs : s.globsAt GT) :
    ∀ (ps : List (PMode × Ty)) (base i : Nat), (wrapParams ps base i s).globsAt GT := by
  intro ps
  induction ps with
  | nil => intro _ _; exact hs
  | cons p ps ih =>
    intro base i
    obtain ⟨pm, t⟩ := p
    cases pm <;> simp only [wrapParams, Stmt.globsAt] <;> exact ih base (i + 1)

theorem callIn_globs {P : Prog} {GT : GTy} (hPG : ProgGlobs P GT) {f : Nat} {fn : Fn} (hf : P[f]? = some fn)
    (args : List Var) (base : Nat) (x : Var) : (callIn fn args base x).globsAt GT := by
  have hb : (fn.body.rename (callRen fn.params args base)).globsAt GT :=
    (Stmt.globsAt_rename _ _).mpr (hPG fn (List.mem_of_getElem? hf))
  have he : ∀ r s, (resFrame fn r s).globsAt GT = s.globsAt GT := fun r s => by
    unfold resFrame; split <;> rfl
  show (resFrame fn _ _).globsAt GT
  rw [he]
  exact ⟨wrapParams_globs hb _ _ _, trivial⟩

/-- **A3.6: a step reads globals only at their declared types**: what it
    leaves to run is a part of the statement, or a function's body. -/
theorem globs_step {P : Prog} {GT : GTy} (hPG : ProgGlobs P GT) {m : Mem} {s : Stmt} {r : Res}
    (hst : Step P m s r) : s.globsAt GT → ∀ m' s', r = .ok m' s' → s'.globsAt GT := by
  induction hst with
  | seqL _ ih => intro hs _ _ h; cases h; exact ⟨ih hs.1 _ _ rfl, hs.2⟩
  | scopeIn _ ih | rbindIn _ ih | frozenIn _ ih | catchIn _ ih | scopeDIn _ ih | scopeLIn _ ih =>
    intro hs _ _ h; cases h; simp only [Stmt.globsAt]; exact ih hs _ _ rfl
  | letcall hf _ _ => intro hs _ _ h; cases h; exact ⟨callIn_globs hPG hf _ _ _, hs⟩
  | letrec hf _ _ => intro hs _ _ h; cases h; exact ⟨callIn_globs hPG hf _ _ _, hs⟩
  | callc _ _ hf _ _ => intro hs _ _ h; cases h; exact ⟨callIn_globs hPG hf _ _ _, hs⟩
  | «while» => intro hs _ _ h; cases h; exact ⟨⟨hs, hs⟩, trivial⟩
  | withElem _ _ _ _ _ => intro hs _ _ h; cases h; exact ⟨hs, trivial⟩
  | callcE _ _ _ _ => intro hs _ _ h; cases h; exact ⟨⟨trivial, trivial⟩, hs⟩
  | callcD _ _ _ _ _ => intro hs _ _ h; cases h; exact ⟨trivial, hs⟩
  | _ => intro hs _ _ h; cases h <;> simp_all [Stmt.globsAt, Rhs.globAt]

end A2
