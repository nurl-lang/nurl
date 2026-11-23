import A2.TakeB
import A2.CapsStore

/-! A2 — AGORA-963 step 3: **what a right-hand side yields keeps the
closure-capture clause.** A step's value is, or is made from, what the store
held: a value moved or copied, a part of one, one lent; or a block's payload,
which holds no names (`MInv.blkCapsInp`); or a package a closure literal
makes, whose captures are the right-hand side's variables (`Rhs.vars`), so
none is a held root. As `EvalR.codes` (Codes.lean) does for `MemCodes`. -/

namespace A2

/-- AGORA-937 B2 (AGORA-963): a value that holds no names holds no package
    that captures anything. -/
theorem valCapsInp_of_names {V : Val} (h : V.names = []) (w : Var) : ValCapsInp V w :=
  fun fs te ms e cs hs q hq _ => by
    have := names_sub hs q (by simp [Val.names, hq])
    rw [h] at this; cases this

/-- ... so every block's payload is clean: it is of a type holding no views
    (`MInv.blocks`), so holds no names. -/
theorem MInv.blkCapsInp {m : Mem} {Γ : Ctx} (hi : MInv m Γ) (w : Var) :
    ∀ k bl V, m.blk k = some bl → bl.pay = some V → ValCapsInp V w := fun k bl V hk hp => by
  obtain ⟨_, hhv, hpay, _⟩ := hi.blocks k bl hk
  exact valCapsInp_of_names ((hpay V hp).1.names_nil hhv) w

/-- The slot half of `CapsInpAt`. -/
def SlotsCaps (m : Mem) (w : Var) : Prop := ∀ x o V, m.st x = some ⟨o, some V⟩ → ValCapsInp V w

theorem CapsInpAt.of_slots {m : Mem} {Γ : Ctx} {w : Var} (h : SlotsCaps m w) (hM : MInv m Γ) : CapsInpAt m w :=
  ⟨h, hM.blkCapsInp w⟩

theorem ValCapsInp.sub {u V : Val} {w : Var} (h : ValCapsInp V w) (hs : Sub u V) : ValCapsInp u w :=
  fun fs te ms e cs hp => h fs te ms e cs (hp.trans hs)

theorem ValCapsInp.leaf {v : Val} {w : Var} (hv : ∀ fs te ms e cs, v ≠ .pkg fs te ms e cs)
    (hc : ∀ e, ¬ Child e v) : ValCapsInp v w := by
  intro fs te ms e cs hs
  rcases hs.cases' with h | ⟨e', hc', _⟩
  · exact absurd h.symm (hv fs te ms e cs)
  · exact absurd hc' (hc e')

theorem ValCapsInp.int (n : Nat) (w : Var) : ValCapsInp (.int n) w :=
  ValCapsInp.leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)

theorem ValCapsInp.of_children {v : Val} {w : Var}
    (hself : ∀ fs te ms e cs, v = .pkg fs te ms e cs → ∀ q ∈ cs, q.1 = w → q.2.1 = .inp)
    (hc : ∀ e, Child e v → ValCapsInp e w) : ValCapsInp v w := by
  intro fs te ms e cs hs
  rcases hs.cases' with h | ⟨e', hc', hs'⟩
  · exact hself fs te ms e cs h.symm
  · exact hc e' hc' fs te ms e cs hs'

theorem ValCapsInp.child {e v : Val} {w : Var} (h : ValCapsInp v w) (hc : Child e v) : ValCapsInp e w :=
  h.sub (hc.sub (Sub.refl _))

theorem SlotsCaps.slot {m : Mem} {w : Var} (h : SlotsCaps m w) {x : Var} {o : Bool} {V : Val}
    (hx : m.st x = some ⟨o, some V⟩) : ValCapsInp V w := h x o V hx

theorem SlotsCaps.set {m : Mem} {w : Var} (h : SlotsCaps m w) {x : Var} {o : Bool} {v : Option Val}
    (hv : ∀ V, v = some V → ValCapsInp V w) : SlotsCaps (m.set x ⟨o, v⟩) w := by
  intro y o' V hy
  by_cases hyx : y = x
  · subst hyx; simp at hy; obtain ⟨_, rfl⟩ := hy; exact hv V rfl
  · simp [upd_ne _ _ hyx] at hy; exact h.slot hy

theorem SlotsCaps.of_st {m m' : Mem} {w : Var} (h : SlotsCaps m w) (hst : m'.st = m.st) : SlotsCaps m' w :=
  fun x o V hx => h.slot (hst ▸ hx)

/-- ... a store whose slots are those, one set to a clean value. -/
theorem SlotsCaps.set_of {m m' : Mem} {w x : Var} {o : Bool} {v : Val} (h : SlotsCaps m w)
    (hv : ValCapsInp v w) (hst : m'.st = (m.set x ⟨o, some v⟩).st) : SlotsCaps m' w :=
  (h.set (fun V e => by cases e; exact hv)).of_st hst

/-- A `Vec` with a clean value pushed. -/
theorem ValCapsInp.push {t : Ty} {c d c' d' : Nat} {es : List Val} {v : Val} {w : Var}
    (hn : ValCapsInp (.node t c d es) w) (hv : ValCapsInp v w) : ValCapsInp (.node t c' d' (es ++ [v])) w := by
  refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
  cases hc with
  | elem he =>
    rcases List.mem_append.mp he with he | he
    · exact hn.child (Child.elem he)
    · simp at he; subst he; exact hv

/-- A `Vec` whose elements are among a clean one's. -/
theorem ValCapsInp.node_sub {t : Ty} {c d c' d' : Nat} {es es' : List Val} {w : Var}
    (hn : ValCapsInp (.node t c d es) w) (hs : ∀ e ∈ es', e ∈ es) : ValCapsInp (.node t c' d' es') w := by
  refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
  cases hc with
  | elem he => exact hn.child (Child.elem (hs _ he))

/-- A block's payload, what its holders read and what it owns hold no
    package that captures anything. -/
theorem MInv.rdCapsInp {m : Mem} {Γ : Ctx} (hM : MInv m Γ) (w : Var) {k : Nat} {bl : Blk}
    (hk : m.blk k = some bl) : ValCapsInp bl.rd w ∧ ValCapsInp bl.tree w := by
  have hp := fun V (h : bl.pay = some V) => hM.blkCapsInp w k bl V hk h
  obtain ⟨ty, kind, pay⟩ := bl
  constructor <;> (simp only [Blk.rd, Blk.tree]; cases kind <;> cases pay <;> simp only [Option.getD] <;>
    first | exact ValCapsInp.int 0 w | exact hp _ rfl)

theorem SlotsCaps.nodeAt {m : Mem} {Γ : Ctx} {w : Var} (h : SlotsCaps m w) (hM : MInv m Γ)
    {c : Nat} {n : Val} (hn : NodeAt m c n) : ValCapsInp n w := by
  rcases hn with ⟨x, t, hx, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
  · exact (h.slot hx).sub hs
  · exact (hM.rdCapsInp w hk).1.sub hs

theorem SlotsCaps.dataAt {m : Mem} {Γ : Ctx} {w : Var} (h : SlotsCaps m w) (hM : MInv m Γ)
    {d : Nat} {n : Val} (hn : DataAt m d n) : ValCapsInp n w := by
  rcases hn with ⟨x, t, hx, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
  · exact (h.slot hx).sub hs
  · exact (hM.rdCapsInp w hk).1.sub hs

theorem SlotsCaps.vecOf {m : Mem} {Γ : Ctx} {w : Var} (h : SlotsCaps m w) (hM : MInv m Γ)
    {y : Var} {t : Ty} {c d : Nat} {es : List Val} (hv : VecOf m y t c d es) : ValCapsInp (.node t c d es) w := by
  obtain ⟨_, _, hv | ⟨_, hn⟩⟩ := hv
  · exact h.slot hv
  · exact h.nodeAt hM hn

theorem TakeVal.capsInp {m m1 : Mem} {y : Var} {v : Val} {w : Var} (ht : TakeVal m y v m1)
    (h : SlotsCaps m w) : ValCapsInp v w ∧ SlotsCaps m1 w := by
  cases ht with
  | own hv => exact ⟨h.slot hv, h.set (fun _ e => by cases e)⟩
  | bor hv => exact ⟨h.slot hv, h⟩

/-- **What a right-hand side yields, and the store it leaves, keep the
    clause at a root that is none of its variables.** -/
theorem EvalR.capsInp {m m1 : Mem} {Γ : Ctx} {r : Rhs} {v : Val} {o : Bool} {w : Var}
    (he : EvalR m r (.ok v o m1)) (hM : MInv m Γ) (h : SlotsCaps m w) (hw : w ∉ r.vars) :
    ValCapsInp v w ∧ SlotsCaps m1 w := by
  have lf : ∀ {u : Val}, (∀ fs te ms e cs, u ≠ .pkg fs te ms e cs) → (∀ e, ¬ Child e u) → ValCapsInp u w :=
    fun a b => ValCapsInp.leaf a b
  cases he with
  | expr _ => exact ⟨ValCapsInp.int _ w, h⟩
  | new =>
    refine ⟨ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h.of_st rfl⟩
    cases hc with | elem he => simp at he
  | moveOwn hv => exact ⟨h.slot hv, h.set (fun _ e => by cases e)⟩
  | take hv =>
    refine ⟨h.slot hv, (h.of_st rfl).set (fun V e => ?_)⟩
    cases e
    refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with | elem he => simp at he
  | copy hv => exact ⟨h.slot hv, h⟩
  | borrowOwn _ => exact ⟨lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | borrowBor hv => exact ⟨h.slot hv, h⟩
  | «at» hn hv _ => exact ⟨((h.vecOf hM hv).child (Child.elem (List.getElem_mem hn))).lend, h⟩
  | view _ => exact ⟨lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | sat hn _ _ _ _ hda => exact ⟨((h.dataAt hM hda).child (Child.elem (List.getElem_mem hn))).lend, h⟩
  | pop hv _ _ =>
    have hT := h.slot hv
    refine ⟨hT.child (Child.elem (by simp)), h.set (fun V e => ?_)⟩
    cases e
    refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with | elem he => exact hT.child (Child.elem (by simp [he]))
  | remove hn hv _ _ _ =>
    have hT := h.slot hv
    refine ⟨hT.child (Child.elem (List.getElem_mem hn)), h.set (fun V e => ?_)⟩
    cases e
    refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with | elem he => exact hT.child (Child.elem (List.mem_of_mem_eraseIdx he))
  | pair h1 h2 =>
    obtain ⟨hv, hm1⟩ := h1.capsInp h
    obtain ⟨hw', hm2⟩ := h2.capsInp hm1
    refine ⟨ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), hm2⟩
    cases hc with
    | fst => exact hv
    | snd => exact hw'
  | fst hv => exact ⟨((h.slot hv).child Child.fst).lend, h⟩
  | snd hv => exact ⟨((h.slot hv).child Child.snd).lend, h⟩
  | inl h1 =>
    obtain ⟨hv, hm1⟩ := h1.capsInp h
    refine ⟨ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), hm1⟩
    cases hc with | inl => exact hv
  | inr h1 =>
    obtain ⟨hv, hm1⟩ := h1.capsInp h
    refine ⟨ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), hm1⟩
    cases hc with | inr => exact hv
  | getl hv => exact ⟨((h.slot hv).child Child.inl).lend, h⟩
  | getr hv => exact ⟨((h.slot hv).child Child.inr).lend, h⟩
  | takel hv => exact ⟨(h.slot hv).child Child.inl, h.set (fun _ e => by cases e)⟩
  | taker hv => exact ⟨(h.slot hv).child Child.inr, h.set (fun _ e => by cases e)⟩
  | pack h1 =>
    -- a closure literal's captures are the right-hand side's variables
    obtain ⟨hv, hm1⟩ := h1.capsInp h
    refine ⟨ValCapsInp.of_children (fun fs te ms e cs he => ?_) (fun e hc => ?_), hm1⟩
    · cases he
      intro q hq hqw
      exact absurd (by simp only [Rhs.vars, List.mem_cons, List.mem_map]; exact Or.inr ⟨q, hq, hqw⟩) hw
    · cases hc with | pkg => exact hv
  | arcNew h1 _ =>
    obtain ⟨_, hm1⟩ := h1.capsInp h
    exact ⟨lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), hm1.of_st rfl⟩
  | lockNew h1 _ =>
    obtain ⟨_, hm1⟩ := h1.capsInp h
    exact ⟨lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), hm1.of_st rfl⟩
  | arcClone _ => exact ⟨lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | lockClone _ => exact ⟨lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | cellNew h1 _ =>
    obtain ⟨_, hm1⟩ := h1.capsInp h
    exact ⟨lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), hm1.of_st rfl⟩
  | cellClone _ => exact ⟨lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | glob _ hf =>
    rcases hf with ⟨_, _, _, _, rfl, _⟩ | ⟨_, _, _, _, rfl, _⟩ <;>
      exact ⟨lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | rwRead _ _ _ => exact ⟨lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h.of_st rfl⟩
  | rwTryRead _ _ _ =>
    refine ⟨ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h.of_st rfl⟩
    cases hc with
    | inr => exact lf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
  | rwTryReadNone _ _ | rwTryWriteNone _ _ =>
    refine ⟨ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h⟩
    cases hc with
    | inl => exact ValCapsInp.int _ w
  | rwTryWrite _ _ _ =>
    refine ⟨ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h⟩
    cases hc with
    | inr => exact ValCapsInp.int _ w
  | atomic _ _ _ _ => exact ⟨ValCapsInp.int _ w, h.of_st rfl⟩
  | @chanSend _ _ _ k _ u c d es _ _ _ h1 hk _ _ _ =>
    obtain ⟨_, hm1⟩ := h1.capsInp h
    exact ⟨ValCapsInp.int _ w, hm1.of_st rfl⟩
  | @chanSendClosed _ _ _ k t s q f v m1 _ h1 hk ht _ _ =>
    obtain ⟨_, hm1⟩ := h1.capsInp h
    exact ⟨ValCapsInp.int _ w, hm1.of_st rfl⟩
  | @chanRecv _ _ _ _ _ u c d f v es _ hk _ _ =>
    -- the queue's head was in the channel's payload, which holds no names
    have hp := (hM.rdCapsInp w hk).2
    refine ⟨ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h.of_st rfl⟩
    cases hc with
    | inr => exact (hp.child Child.fst).child (Child.elem (List.mem_cons_self ..))
  | chanRecvNone _ _ _ _ =>
    refine ⟨ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h⟩
    cases hc with
    | inl => exact ValCapsInp.int _ w
  | lockTake _ hk _ => exact ⟨(hM.rdCapsInp w hk).2, h.of_st rfl⟩
  | lockRestore _ h1 _ =>
    obtain ⟨_, hm1⟩ := h1.capsInp h
    exact ⟨ValCapsInp.int _ w, hm1.of_st rfl⟩
  | chanClose _ _ _ => exact ⟨ValCapsInp.int _ w, h.of_st rfl⟩
  | arcGet _ hk => exact ⟨(hM.rdCapsInp w hk).1.lend, h⟩

end A2
