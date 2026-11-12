import A2.Typing

/-
  A2 — what a well-typed configuration guarantees about memory.

  * Every owned tree is well-formed at its binding's type, its addresses are
    allocated, appear once in it and in no other owner's tree (one owner per
    allocation).
  * Every live borrow reaches, through one of its dependencies, a node of
    its type inside memory that dependency's root holds; every live view
    lies inside the buffer it names.  The views stored inside a value are
    valid through what it holds (`held`).
  * A borrowed parameter's dependencies are frozen at the point of
    execution, so nothing that runs can change what it reaches.
-/

namespace A2

-- `WFv`, an owned tree of a given type, is in `Semantics.lean` (A3.3: a lock
-- scope gives back only a well-formed payload, `Giveable`).

/-- `v`, a view of element type `s`, is stored in tree `T` of type `τ`. -/
inductive ViewIn : Ty → Val → Ty → Val → Prop
  | here {s : Ty} {d o l : Nat} : ViewIn (.slice s) (.view d o l) s (.view d o l)
  | child {t t' : Ty} {c d : Nat} {es : List Val} {e : Val} {s : Ty} {v : Val} :
      e ∈ es → ViewIn t e s v → ViewIn (.vec t) (.node t' c d es) s v
  | fst {a b : Ty} {x y : Val} {s : Ty} {v : Val} : ViewIn a x s v → ViewIn (.prod a b) (.pair x y) s v
  | snd {a b : Ty} {x y : Val} {s : Ty} {v : Val} : ViewIn b y s v → ViewIn (.prod a b) (.pair x y) s v
  | inl {a b : Ty} {x : Val} {s : Ty} {v : Val} : ViewIn a x s v → ViewIn (.sum a b) (.inl x) s v
  | inr {a b : Ty} {x : Val} {s : Ty} {v : Val} : ViewIn b x s v → ViewIn (.sum a b) (.inr x) s v
  /-- (A3.5b: only a closure whose type may hold views has one in its
      environment; another's holds none, `WFv.pkg`.) -/
  | pkg {fs : List Nat} {te : Ty} {ms : List Nat} {x : Val} {cs : List (Var × PMode × Ty)} {s : Ty}
      {v : Val} : ViewIn te x s v → ViewIn (.fn ms .any) (.pkg fs te ms x cs) s v
  /-- A2-drop.3: a destructor type's values are its inner type's. -/
  | dtor {f : Nat} {t : Ty} {x : Val} {s : Ty} {v : Val} : ViewIn t x s v → ViewIn (.dtor f t) x s v

-- `ArcIn`, `ArcBlk`, `ShareFits` and `SharesIn` are in `Semantics.lean` (A3.2's
-- second cut: a lock scope gives back only a payload whose shares fit, `Giveable`).

/-- `SharesIn` over a memory's blocks. -/
def SharesOK (m : Mem) (τ : Ty) (T : Val) : Prop := SharesIn m.blk τ T

/-- A3.2: what a later store keeps of a block, as its holders see it: an
    `arc` block as it was, a `lock` block as a lock block of the same type
    (its payload, which no one reads, may have been checked out or back in).
    Agora #610: a `dead` block as a dead block of the same type (its
    payload, which no one reads either, may have been moved out to its
    destructor's frame, `Step.reap`). -/
def BlkKeep (bl bl' : Blk) : Prop :=
  bl'.ty = bl.ty ∧ bl'.kind = bl.kind ∧ (bl.kind ≠ .lock → bl.kind ≠ .dead → bl' = bl)

theorem BlkKeep.refl (bl : Blk) : BlkKeep bl bl := ⟨rfl, rfl, fun _ _ => rfl⟩

theorem BlkKeep.trans {b1 b2 b3 : Blk} (h1 : BlkKeep b1 b2) (h2 : BlkKeep b2 b3) : BlkKeep b1 b3 :=
  ⟨h2.1.trans h1.1, h2.2.1.trans h1.2.1, fun h h' =>
    (h2.2.2 (by rw [h1.2.1]; exact h) (by rw [h1.2.1]; exact h')).trans (h1.2.2 h h')⟩

/-- What a kept block's holders read is what they read before. -/
theorem BlkKeep.rd {bl bl' : Blk} (h : BlkKeep bl bl') : bl'.rd = bl.rd := by
  obtain ⟨_, hk, ha⟩ := h
  cases hkd : bl.kind with
  | arc => rw [ha (by rw [hkd]; simp) (by rw [hkd]; simp)]
  | view => rw [ha (by rw [hkd]; simp) (by rw [hkd]; simp)]
  | lock =>
    rw [hkd] at hk
    obtain ⟨t, k, p⟩ := bl; obtain ⟨t', k', p'⟩ := bl'
    simp only at hk hkd; subst hk; subst hkd; rfl
  | dead =>
    rw [hkd] at hk
    obtain ⟨t, k, p⟩ := bl; obtain ⟨t', k', p'⟩ := bl'
    simp only at hk hkd; subst hk; subst hkd; rfl

/-- A3.1: the blocks `B'` keep every block of `B`: a step's blocks only grow
    (`arcNew` adds one); only the sweep at its end removes one.  (A3.2: a
    lock block is kept as a lock block of its type, `BlkKeep`: acquiring
    and releasing it change its payload.) -/
def BlkLe (B B' : Nat → Option Blk) : Prop := ∀ k bl, B k = some bl → ∃ bl', B' k = some bl' ∧ BlkKeep bl bl'

/-- Blocks kept exactly are kept. -/
theorem BlkLe.of_le {B B' : Nat → Option Blk} (h : ∀ k bl, B k = some bl → B' k = some bl) : BlkLe B B' :=
  fun k bl hk => ⟨bl, h k bl hk, BlkKeep.refl bl⟩

theorem BlkLe.refl (B : Nat → Option Blk) : BlkLe B B := BlkLe.of_le fun _ _ h => h

theorem BlkLe.trans {B1 B2 B3 : Nat → Option Blk} (h1 : BlkLe B1 B2) (h2 : BlkLe B2 B3) : BlkLe B1 B3 :=
  fun k bl h => by
    obtain ⟨b2, h2', hk2⟩ := h1 k bl h
    obtain ⟨b3, h3', hk3⟩ := h2 k b2 h2'
    exact ⟨b3, h3', hk2.trans hk3⟩

theorem BlkLe.of_eq {B B' : Nat → Option Blk} (h : B' = B) : BlkLe B B' :=
  BlkLe.of_le fun _ _ hk => by rw [h]; exact hk

/-- A new block at a fresh key keeps every other. -/
theorem BlkLe.fresh {B : Nat → Option Blk} {n : Nat} (h : B n = none) (b : Blk) : BlkLe B (upd B n (some b)) :=
  BlkLe.of_le fun k bl hk => by
    have hne : k ≠ n := fun e => by rw [e, h] at hk; cases hk
    simpa [upd, hne] using hk

/-- An `arc` block is kept as it was ... -/
theorem BlkLe.arc {B B' : Nat → Option Blk} (hb : BlkLe B B') {k : Nat} {t : Ty} {p : Option Val}
    (h : B k = some ⟨t, .arc, p⟩) : B' k = some ⟨t, .arc, p⟩ := by
  obtain ⟨bl', h', hk⟩ := hb k _ h
  rw [h', hk.2.2 (by simp) (by simp)]

/-- ... (A3.3) and so is a view ... -/
theorem BlkLe.view {B B' : Nat → Option Blk} (hb : BlkLe B B') {k : Nat} {t : Ty} {p : Option Val}
    (h : B k = some ⟨t, .view, p⟩) : B' k = some ⟨t, .view, p⟩ := by
  obtain ⟨bl', h', hk⟩ := hb k _ h
  rw [h', hk.2.2 (by simp) (by simp)]

theorem ArcBlk.grow {B B' : Nat → Option Blk} (hb : BlkLe B B') {k : Nat} {t : Ty} {p : Val}
    (h : ArcBlk (B k) t p) : ArcBlk (B' k) t p := by
  rcases h with h | h
  · exact Or.inl (hb.arc h)
  · exact Or.inr (hb.view h)

/-- What the holders of a share read of its block is the payload it carries. -/
theorem ArcBlk.rd {b : Option Blk} {t : Ty} {p : Val} (h : ArcBlk b t p) : ∃ bl, b = some bl ∧ bl.rd = p := by
  rcases h with h | h
  · exact ⟨_, h, rfl⟩
  · exact ⟨_, h, rfl⟩

/-- ... a lock block as a lock block of its type ... -/
theorem BlkLe.lock {B B' : Nat → Option Blk} (hb : BlkLe B B') {k : Nat} {t : Ty} {o : Option Val}
    (h : B k = some ⟨t, .lock, o⟩) : ∃ o', B' k = some ⟨t, .lock, o'⟩ := by
  obtain ⟨⟨t', k', o'⟩, h', hty, hkd, _⟩ := hb k _ h
  simp only at hty hkd; subst hty; subst hkd
  exact ⟨o', h'⟩

/-- ... and what holders read of a block is kept. -/
theorem BlkLe.rd {B B' : Nat → Option Blk} (hb : BlkLe B B') {k : Nat} {bl : Blk} (h : B k = some bl) :
    ∃ bl', B' k = some bl' ∧ bl'.rd = bl.rd := by
  obtain ⟨bl', h', hk⟩ := hb k bl h
  exact ⟨bl', h', hk.rd⟩

theorem ShareFits.grow {B B' : Nat → Option Blk} (hb : BlkLe B B') {k : Nat} {u : Ty} {p : Option Val}
    (h : ShareFits (B k) u p) : ShareFits (B' k) u p := by
  cases p with
  | some p => exact ArcBlk.grow hb h
  | none => obtain ⟨o, h⟩ := h; exact hb.lock h

theorem SharesIn.grow {B B' : Nat → Option Blk} {τ : Ty} {T : Val} (h : SharesIn B τ T) (hb : BlkLe B B') :
    SharesIn B' τ T := fun u k p ha => (h u k p ha).grow hb

theorem SharesOK.grow {m m' : Mem} {τ : Ty} {T : Val} (h : SharesOK m τ T) (hb : BlkLe m.blk m'.blk) :
    SharesOK m' τ T := SharesIn.grow h hb

theorem SharesOK.of_blk {m m' : Mem} {τ : Ty} {T : Val} (h : SharesOK m τ T) (hb : m'.blk = m.blk) :
    SharesOK m' τ T := fun u k p ha => by rw [hb]; exact h u k p ha

theorem SharesOK.fst {m : Mem} {a b : Ty} {x y : Val} (h : SharesOK m (.prod a b) (.pair x y)) :
    SharesOK m a x := fun u k p ha => h u k p (.fst ha)
theorem SharesOK.snd {m : Mem} {a b : Ty} {x y : Val} (h : SharesOK m (.prod a b) (.pair x y)) :
    SharesOK m b y := fun u k p ha => h u k p (.snd ha)
theorem SharesOK.inl {m : Mem} {a b : Ty} {x : Val} (h : SharesOK m (.sum a b) (.inl x)) :
    SharesOK m a x := fun u k p ha => h u k p (.inl ha)
theorem SharesOK.inr {m : Mem} {a b : Ty} {x : Val} (h : SharesOK m (.sum a b) (.inr x)) :
    SharesOK m b x := fun u k p ha => h u k p (.inr ha)
theorem SharesOK.elem {m : Mem} {t t' : Ty} {c d : Nat} {es : List Val} {e : Val}
    (h : SharesOK m (.vec t) (.node t' c d es)) (he : e ∈ es) : SharesOK m t e :=
  fun u k p ha => h u k p (.child he ha)
theorem SharesOK.pkg {m : Mem} {fs : List Nat} {te : Ty} {ms : List Nat} {q : Cross} {x : Val}
    {cs : List (Var × PMode × Ty)} (h : SharesOK m (.fn ms q) (.pkg fs te ms x cs)) (hq : q.shares = true) :
    SharesOK m te x :=
  fun u k p ha => h u k p (.pkg ha hq)
theorem SharesOK.here {m : Mem} {t : Ty} {k : Nat} {p : Val} (h : SharesOK m (.arc t) (.arc k p)) :
    ArcBlk (m.blk k) t p := h t k (some p) .here
/-- A3.2: a lock share names a lock block of its type. -/
theorem SharesOK.lk {m : Mem} {t : Ty} {k : Nat} (h : SharesOK m (.lk t) (.lk k)) :
    ∃ o, m.blk k = some ⟨t, .lock, o⟩ := h t k none .lk
/-- A3.5: so does a cell share. -/
theorem SharesOK.cell {m : Mem} {t : Ty} {k : Nat} (h : SharesOK m (.cell t) (.cell k)) :
    ∃ o, m.blk k = some ⟨t, .lock, o⟩ := h t k none .cell

theorem ArcIn.hasArc {τ : Ty} {T : Val} {u : Ty} {k : Nat} {p : Option Val} (h : ArcIn τ T u k p) :
    τ.hasArc = true := by
  induction h with
  | here => rfl
  | lk => rfl
  | cell => rfl
  | child _ _ ih => exact ih
  | fst _ ih => simp [Ty.hasArc, ih]
  | snd _ ih => simp [Ty.hasArc, ih]
  | inl _ ih => simp [Ty.hasArc, ih]
  | inr _ ih => simp [Ty.hasArc, ih]
  | pkg _ hq _ => exact hq
  | dtor _ ih => exact ih

/-- A node whose elements are among another's, where the blocks are as
    they were (a `Vec` that shrank, or that was copied). -/
theorem SharesOK.node_sub {m m' : Mem} {t t1 t2 : Ty} {c d c' d' : Nat} {es es' : List Val}
    (h : SharesOK m (.vec t) (.node t1 c d es)) (hsub : ∀ e ∈ es', e ∈ es) (hb : m'.blk = m.blk) :
    SharesOK m' (.vec t) (.node t2 c' d' es') := fun u k p ha => by
  cases ha with
  | child he ha' => rw [hb]; exact h u k p (.child (hsub _ he) ha')

/-- ... and a `Vec` with one element more (`vec_push`). -/
theorem SharesOK.node_push {m m' : Mem} {t t1 t2 : Ty} {c d c' d' : Nat} {es : List Val} {v : Val}
    (h : SharesOK m (.vec t) (.node t1 c d es)) (hv : SharesOK m t v) (hb : m'.blk = m.blk) :
    SharesOK m' (.vec t) (.node t2 c' d' (es ++ [v])) := fun u k p ha => by
  cases ha with
  | child he ha' =>
    rw [hb]
    rcases List.mem_append.mp he with he | he
    · exact h u k p (.child he ha')
    · rw [List.mem_singleton] at he; subst he; exact hv u k p ha'

theorem SharesOK.mk_pair {m : Mem} {a b : Ty} {x y : Val} (hx : SharesOK m a x) (hy : SharesOK m b y) :
    SharesOK m (.prod a b) (.pair x y) := fun u k p ha => by
  cases ha with
  | fst h => exact hx u k p h
  | snd h => exact hy u k p h
theorem SharesOK.mk_inl {m : Mem} {a b : Ty} {x : Val} (hx : SharesOK m a x) :
    SharesOK m (.sum a b) (.inl x) := fun u k p ha => by cases ha with | inl h => exact hx u k p h
theorem SharesOK.mk_inr {m : Mem} {a b : Ty} {x : Val} (hx : SharesOK m b x) :
    SharesOK m (.sum a b) (.inr x) := fun u k p ha => by cases ha with | inr h => exact hx u k p h
theorem SharesOK.mk_pkg {m : Mem} {fs : List Nat} {te : Ty} {ms : List Nat} {q : Cross} {x : Val}
    {cs : List (Var × PMode × Ty)} (hx : SharesOK m te x) : SharesOK m (.fn ms q) (.pkg fs te ms x cs) :=
  fun u k p ha => by cases ha with | pkg h => exact hx u k p h
theorem SharesOK.nil_node {m : Mem} {t t1 : Ty} {c d : Nat} : SharesOK m (.vec t) (.node t1 c d []) :=
  fun u k p ha => by cases ha with | child he _ => cases he

/-- A tree of a type that holds no share holds none to check. -/
theorem SharesOK.of_noArc {m : Mem} {τ : Ty} {T : Val} (h : τ.hasArc = false) : SharesOK m τ T :=
  fun _ _ _ ha => by rw [ha.hasArc] at h; cases h

/-- A3.5b: the shares a package's environment holds are the package's (a bare
    one's holds none). -/
theorem SharesOK.pkg' {m : Mem} {fs : List Nat} {te : Ty} {ms : List Nat} {q : Cross} {x : Val}
    {cs : List (Var × PMode × Ty)} (h : SharesOK m (.fn ms q) (.pkg fs te ms x cs)) (hq : q.Fits te cs) :
    SharesOK m te x := by
  cases hs : q.shares
  · exact SharesOK.of_noArc (hq.2.2.1 hs)
  · exact h.pkg hs

/-- A3.1's slices of shares: a part of a well-formed tree holds, at its own
    type, the shares the tree holds (a share is a leaf, typed where it lies). -/
theorem SharesIn.sub {B : Nat → Option Blk} {n T : Val} (hs : Sub n T) :
    ∀ {τ : Ty}, WFv τ T → SharesIn B τ T → ∃ σ, WFv σ n ∧ SharesIn B σ n := by
  induction hs with
  | refl => exact fun hw hsh => ⟨_, hw, hsh⟩
  | child he _ ih =>
    intro τ hw hsh
    peel_dtor τ τ' hnd hw
    cases hw with
    | node hes => exact ih (hes _ he) (fun u k p ha => hsh u k p (.child he ha))
    | dtor => exact absurd rfl (hnd _ _)
  | fst _ ih =>
    intro τ hw hsh
    peel_dtor τ τ' hnd hw
    cases hw with
    | pair ha _ => exact ih ha (fun u k p h => hsh u k p (.fst h))
    | dtor => exact absurd rfl (hnd _ _)
  | snd _ ih =>
    intro τ hw hsh
    peel_dtor τ τ' hnd hw
    cases hw with
    | pair _ hb => exact ih hb (fun u k p h => hsh u k p (.snd h))
    | dtor => exact absurd rfl (hnd _ _)
  | inl _ ih =>
    intro τ hw hsh
    peel_dtor τ τ' hnd hw
    cases hw with
    | inl ha => exact ih ha (fun u k p h => hsh u k p (.inl h))
    | dtor => exact absurd rfl (hnd _ _)
  | inr _ ih =>
    intro τ hw hsh
    peel_dtor τ τ' hnd hw
    cases hw with
    | inr hb => exact ih hb (fun u k p h => hsh u k p (.inr h))
    | dtor => exact absurd rfl (hnd _ _)
  | pkg _ ih =>
    intro τ hw hsh
    peel_dtor τ τ' hnd hw
    cases hw with
    | @pkg _ _ _ q _ _ hwe hq =>
      cases hqs : q.shares
      · exact ih hwe (fun _ _ _ ha => by have h := ha.hasArc; rw [hq.2.2.1 hqs] at h; cases h)
      · exact ih hwe (fun u k p h => hsh u k p (.pkg h hqs))
    | dtor => exact absurd rfl (hnd _ _)

/-- A tree of a type that holds no cell share holds none. -/
theorem WFv.noCell_hasCell {τ : Ty} {v : Val} (hw : WFv τ v) (hnc : τ.hasCell = false) {k : Nat} :
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
  | dtor _ _ ih => exact ih hnc

/-- ... so a node found in a well-formed tree holds the shares the tree's type
    says, at its own type `vec t`. -/
theorem SharesOK.sub_node {m : Mem} {τ : Ty} {T : Val} (hw : WFv τ T) (hsh : SharesOK m τ T)
    {t : Ty} {c d : Nat} {es : List Val} (hs : Sub (.node t c d es) T) :
    SharesOK m (.vec t) (.node t c d es) := by
  obtain ⟨σ, hwσ, hshσ⟩ := SharesIn.sub hs hw hsh
  peel_dtor σ σ' hnd hwσ
  cases hwσ
  · exact hshσ
  · exact absurd rfl (hnd _ _)

/-- A3.1 (with #295): a node whose elements are the old node's or hold
    shares that name blocks, where the blocks are as they were. -/
theorem SharesOK.node_mem {m m' : Mem} {t t1 t2 : Ty} {c d c' d' : Nat} {es es' : List Val}
    (h : SharesOK m (.vec t) (.node t1 c d es)) (hes : ∀ e ∈ es', e ∈ es ∨ SharesOK m t e)
    (hb : m'.blk = m.blk) : SharesOK m' (.vec t) (.node t2 c' d' es') := fun u k p ha => by
  cases ha with
  | child he ha' =>
    rw [hb]
    rcases hes _ he with he | he
    · exact h u k p (.child he ha')
    · exact he u k p ha'

/-- `e` is a part of `t` one level down: an element of a `Vec`, or a field
    of a struct. -/
inductive Child : Val → Val → Prop
  | elem {e : Val} {ty : Ty} {c d : Nat} {es : List Val} : e ∈ es → Child e (.node ty c d es)
  | fst {v w : Val} : Child v (.pair v w)
  | snd {v w : Val} : Child w (.pair v w)
  | inl {v : Val} : Child v (.inl v)
  | inr {v : Val} : Child v (.inr v)
  | pkg {v : Val} {fs : List Nat} {te : Ty} {ms : List Nat} {cs : List (Var × PMode × Ty)} :
      Child v (.pkg fs te ms v cs)

/-- `n` lies strictly inside `t`. -/
def Below (n t : Val) : Prop := ∃ e, Child e t ∧ Sub n e

/-- `n` is `v` or one of its parts through struct fields and enum payloads
    (never through a `Vec`'s elements): what a binding holds directly. -/
inductive Top : Val → Val → Prop
  | refl (v : Val) : Top v v
  | fst {n a b : Val} : Top n a → Top n (.pair a b)
  | snd {n a b : Val} : Top n b → Top n (.pair a b)
  | inl {n a : Val} : Top n a → Top n (.inl a)
  | inr {n a : Val} : Top n a → Top n (.inr a)
  | pkg {n a : Val} {fs : List Nat} {te : Ty} {ms : List Nat} {cs : List (Var × PMode × Ty)} :
      Top n a → Top n (.pkg fs te ms a cs)

/-- A node a root's slot reaches directly: one at the top of its own tree, or
    one a handle it holds names (a borrowed struct is a bundle of handles),
    or (A3.1) a share at the top of a borrowed slot's value: through it the
    slot reaches its block's payload.  A3.5's third cut: or a cell share at
    the top of a borrowed slot's value (a library's `in` handle), which a
    copy of the slot, or a field read out of it, lands on. -/
def RootNode (m : Mem) (r : Var) (n : Val) : Prop :=
  (∃ T, m.st r = some ⟨true, some T⟩ ∧ Top n T) ∨
  (∃ v c, m.st r = some ⟨false, some v⟩ ∧ Top (.href c) v ∧ NodeAt m c n) ∨
  (∃ v d o l, m.st r = some ⟨false, some v⟩ ∧ Top (.view d o l) v ∧ DataAt m d n) ∨
  (∃ v k q, m.st r = some ⟨false, some v⟩ ∧ Top (.arc k q) v ∧ n = .arc k q) ∨
  (∃ v k, m.st r = some ⟨false, some v⟩ ∧ Top (.cell k) v ∧ n = .cell k)

/-- A3.1: a root that reaches memory: an owned slot (its tree, if it still
    has one), or a borrowed one whose value holds a handle or a share at its
    top. A borrowed integer reaches none. -/
def RootMem (m : Mem) (r : Var) : Prop :=
  (∃ o, m.st r = some ⟨true, o⟩) ∨ ∃ n0, RootNode m r n0

/-- Where a value reached through a dependency of a given kind lies: the
    root's node itself, or strictly inside it. -/
def Lands (k : Kind) (n n0 : Val) : Prop :=
  k = .self ∧ n = n0 ∨ k = .view ∧ n = n0 ∨ k = .inner ∧ Below n n0

/-- A3.1: a value inside a live block's payload. -/
def InPay (m : Mem) (n : Val) : Prop := ∃ k bl, m.blk k = some bl ∧ Sub n bl.rd

/-- What lies in a payload holders read stays there while the blocks are
    kept (A3.2: a lock block's payload is read by no one). -/
theorem InPay.grow {m m' : Mem} (hb : BlkLe m.blk m'.blk) {n : Val} (h : InPay m n) : InPay m' n := by
  obtain ⟨k, bl, hk, hs⟩ := h
  obtain ⟨bl', hk', hrd⟩ := hb.rd hk
  exact ⟨k, bl', hk', hrd ▸ hs⟩

/-- Where a value reached through `dep` lies: where the node its root
    reaches puts it (`Lands`), or (A3.1), through a share, anywhere in a
    live block's payload, which nothing writes: valid while the block
    lives (the sweep keeps a block a handle reaches), whatever its root
    holds, as long as the root reaches memory (`RootMem`): a borrowed
    parameter's share dependency then has one of the parameter's own to
    pass on to when its scope ends. -/
def Landed (m : Mem) (dep : Dep) (n : Val) : Prop :=
  (∃ n0, RootNode m dep.root n0 ∧ Lands dep.kind n n0) ∨
    (dep.kind = .share ∧ RootMem m dep.root ∧ InPay m n)

/-- A3.1: where a share reached through `dep` lies: where the node its root
    reaches puts it, or, through a share, anywhere, as long as the root
    reaches memory. A share carries its block, which lives while the share
    does (the sweep reaches it from the share), so where the share itself
    lies does not matter: only the dependency does, which a borrowed
    parameter's end passes on (`reroot`). -/
def ArcLanded (m : Mem) (dep : Dep) (n : Val) : Prop :=
  (∃ n0, RootNode m dep.root n0 ∧ Lands dep.kind n n0) ∨ (dep.kind = .share ∧ RootMem m dep.root)

/-- A3.5's third cut: where a cell share reached through `dep` lies: where
    the node its root reaches puts it, never in a payload (no payload its
    holders read holds one).  So a borrow of a library handle has, through
    its dependencies, an owner of the handle in the store
    (`MInv.cell_owned`). -/
def CellLanded (m : Mem) (dep : Dep) (k : Nat) : Prop :=
  ∃ n0, RootNode m dep.root n0 ∧ Lands dep.kind (.cell k) n0

theorem CellLanded.landed {m : Mem} {dep : Dep} {k : Nat} (h : CellLanded m dep k) : Landed m dep (.cell k) :=
  Or.inl h

theorem CellLanded.bound {m : Mem} {dep : Dep} {k : Nat} (h : CellLanded m dep k) : dep.kind.bound = .none := by
  obtain ⟨_, _, hk⟩ := h
  rcases hk with ⟨hk, _⟩ | ⟨hk, _⟩ | ⟨hk, _⟩ <;> rw [hk] <;> rfl

theorem CellLanded.notName {m : Mem} {dep : Dep} {k : Nat} (h : CellLanded m dep k) :
    dep.kind.isName = false := by
  obtain ⟨_, _, hk⟩ := h
  rcases hk with ⟨hk, _⟩ | ⟨hk, _⟩ | ⟨hk, _⟩ <;> rw [hk] <;> rfl

/-- A cell share that lands off a payload lands where its root's node puts it. -/
theorem CellLanded.of_landed {m : Mem} {dep : Dep} {k : Nat} (h : Landed m dep (.cell k))
    (hp : ¬ InPay m (.cell k)) : CellLanded m dep k := by
  rcases h with h | ⟨_, _, hin⟩
  · exact h
  · exact absurd hin hp

theorem Landed.arc {m : Mem} {dep : Dep} {n : Val} (h : Landed m dep n) : ArcLanded m dep n := by
  rcases h with h | ⟨hk, hro, _⟩
  · exact Or.inl h
  · exact Or.inr ⟨hk, hro⟩

/-- The view `(d, o, l)` of element type `t` is valid through `dep` (a
    dependency on a whole handle is no view's: a `push` moves the buffer
    and keeps the handle). -/
def ViewAt (m : Mem) (dep : Dep) (d o l : Nat) (t : Ty) : Prop :=
  ∃ c es, dep.kind ≠ .self ∧ Landed m dep (.node t c d es) ∧
    o + l ≤ es.length ∧ WFv (.vec t) (.node t c d es)

/-- Every view stored in `T` is valid through some dependency in `H`. -/
def ViewsOK (m : Mem) (τ : Ty) (T : Val) (H : List Dep) : Prop :=
  ∀ s v, ViewIn τ T s v → ∃ d o l, v = .view d o l ∧ ∃ dep ∈ H, ViewAt m dep d o l s

/-- What a value captured by name (the closures in it) is held, by name,
    in `H`. -/
def NamesIn (T : Val) (H : List Dep) : Prop :=
  ∀ c ∈ T.names, (⟨c.1, .name c.2.1.bound c.2.2⟩ : Dep) ∈ H

/-- A closure's captures by name are distinct, each read or changed, and
    one captured again inside its environment is only read, by both. -/
def PkgsOK (T : Val) : Prop :=
  ∀ fs te ms e cs, Sub (.pkg fs te ms e cs) T →
    (cs.map (·.1)).Nodup ∧ (∀ c ∈ cs, c.2.1 = .inp ∨ ∃ b, c.2.1 = .inout b ∧ b ≠ .none) ∧
    (∀ c ∈ cs, ∀ c' ∈ e.names, c.1 = c'.1 → c.2.1 = .inp ∧ c'.2.1 = .inp)

/-- The borrowed `Vec` `c` of element type `t` is valid through `dep`. -/
def HrefAt (m : Mem) (dep : Dep) (c : Nat) (t : Ty) (H : List Dep) : Prop :=
  ∃ d es, Landed m dep (.node t c d es) ∧
    WFv (.vec t) (.node t c d es) ∧ ViewsOK m (.vec t) (.node t c d es) H ∧
    NamesIn (.node t c d es) H ∧ SharesOK m (.vec t) (.node t c d es)

/-- A borrowed value of type `τ`, depending on `P` and holding `H`.  The parts
    of a borrowed struct are valid through what it depends on or holds. -/
inductive ValOK (m : Mem) : Ty → Val → List Dep → List Dep → Prop
  | int {n : Nat} {P H : List Dep} : ValOK m .int (.int n) P H
  | href {t : Ty} {c : Nat} {P H : List Dep} :
      (∃ dep ∈ P, HrefAt m dep c t H) → ValOK m (.vec t) (.href c) P H
  | view {t : Ty} {d o l : Nat} {P H : List Dep} :
      (∃ dep ∈ P, ViewAt m dep d o l t) → ValOK m (.slice t) (.view d o l) P H
  | pair {a b : Ty} {x y : Val} {P H : List Dep} :
      ValOK m a x (P ++ H) H → ValOK m b y (P ++ H) H → ValOK m (.prod a b) (.pair x y) P H
  | inl {a b : Ty} {x : Val} {P H : List Dep} : ValOK m a x (P ++ H) H → ValOK m (.sum a b) (.inl x) P H
  | inr {a b : Ty} {x : Val} {P H : List Dep} : ValOK m b x (P ++ H) H → ValOK m (.sum a b) (.inr x) P H
  -- a package's environment is valid through what the package depends on and
  -- holds but its own writer captures, which are no part of it (they are its
  -- arguments of their own when it is called); a closure it holds that may
  -- change some other binding by name is part of it
  -- (A3.5b: and holds no more than the closure's type says, `Cross.Fits`)
  | pkg {fs : List Nat} {te : Ty} {ms : List Nat} {q : Cross} {x : Val} {cs : List (Var × PMode × Ty)}
      {P H : List Dep} :
      ValOK m te x (P ++ envDeps cs H) (envDeps cs H) → q.Fits te cs →
      ValOK m (.fn ms q) (.pkg fs te ms x cs) P H
  /-- A3.1: a share lent: its block holds the payload it carries, of its
      type (one that holds no view), and the share lands through a
      dependency, as a `Vec` handle does. -/
  | arc {t : Ty} {k : Nat} {p : Val} {P H : List Dep} :
      ArcBlk (m.blk k) t p → WFv t p → t.holdsView = false →
      (∃ dep ∈ P, ArcLanded m dep (.arc k p)) →
      ValOK m (.arc t) (.arc k p) P H
  /-- A3.2: a lock share lent: its block is a lock block of its type.  No
      one borrows into a lock's payload, so it lands through nothing; the
      sweep keeps the block while a slot holds the share. -/
  | lk {t : Ty} {k : Nat} {P H : List Dep} :
      (∃ o, m.blk k = some ⟨t, .lock, o⟩) → ValOK m (.lk t) (.lk k) P H
  /-- A3.5: a cell share lent: as a lock share, its block is a lock block of
      its type (A3.5's third cut: a lent cell share is the share, `lendOf`;
      the sweep keeps the block while a slot holds it), and it lands through
      a dependency, as a `Vec` handle does: in a tree its root reaches, so a
      live borrow of a library handle has an owner of it in the store
      (`MInv.cell_owned`). -/
  | cell {t : Ty} {k : Nat} {P H : List Dep} :
      (∃ o, m.blk k = some ⟨t, .lock, o⟩) → (∃ dep ∈ P, CellLanded m dep k) →
      ValOK m (.cell t) (.cell k) P H
  /-- A2-drop.3: a destructor type's values are its inner type's. -/
  | dtor {f : Nat} {t : Ty} {v : Val} {P H : List Dep} : ValOK m t v P H → ValOK m (.dtor f t) v P H

section ValOK
variable {m : Mem} {v : Val} {P H : List Dep}

/-! A2-drop.3: a destructor type's values are its inner type's. -/
theorem ViewIn.dtor_iff {f : Nat} {t : Ty} {x : Val} {s : Ty} {w : Val} :
    ViewIn (.dtor f t) x s w ↔ ViewIn t x s w :=
  ⟨fun h => by cases h; assumption, .dtor⟩
theorem ViewIn.undtor_iff {τ : Ty} {x : Val} {s : Ty} {w : Val} :
    ViewIn τ.undtor x s w ↔ ViewIn τ x s w := by
  induction τ with
  | dtor _ _ ih => rw [Ty.undtor_dtor, ih, ViewIn.dtor_iff]
  | _ => exact Iff.rfl
theorem ViewsOK.dtor_iff {f : Nat} {t : Ty} {T : Val} :
    ViewsOK m (.dtor f t) T H ↔ ViewsOK m t T H := by
  simp only [ViewsOK, ViewIn.dtor_iff]
theorem ViewsOK.undtor_iff {τ : Ty} {T : Val} : ViewsOK m τ.undtor T H ↔ ViewsOK m τ T H := by
  simp only [ViewsOK, ViewIn.undtor_iff]
theorem SharesOK.dtor_iff {f : Nat} {t : Ty} {T : Val} : SharesOK m (.dtor f t) T ↔ SharesOK m t T :=
  SharesIn.dtor_iff
theorem SharesOK.undtor_iff {τ : Ty} {T : Val} : SharesOK m τ.undtor T ↔ SharesOK m τ T :=
  SharesIn.undtor_iff
theorem valOK_dtor {f : Nat} {t : Ty} : ValOK m (.dtor f t) v P H ↔ ValOK m t v P H :=
  ⟨fun h => by cases h; assumption, .dtor⟩
theorem valOK_undtor {τ : Ty} : ValOK m τ.undtor v P H ↔ ValOK m τ v P H := by
  induction τ with
  | dtor _ _ ih => rw [Ty.undtor_dtor, ih, valOK_dtor]
  | _ => exact Iff.rfl

theorem valOK_int : ValOK m .int v P H ↔ ∃ n, v = .int n := by
  constructor
  · intro h; cases h; exact ⟨_, rfl⟩
  · rintro ⟨n, rfl⟩; exact .int

theorem valOK_vec {t : Ty} : ValOK m (.vec t) v P H ↔ ∃ c, v = .href c ∧ ∃ dep ∈ P, HrefAt m dep c t H := by
  constructor
  · intro h; cases h with | href h => exact ⟨_, rfl, h⟩
  · rintro ⟨c, rfl, h⟩; exact .href h

theorem valOK_slice {t : Ty} :
    ValOK m (.slice t) v P H ↔ ∃ d o l, v = .view d o l ∧ ∃ dep ∈ P, ViewAt m dep d o l t := by
  constructor
  · intro h; cases h with | view h => exact ⟨_, _, _, rfl, h⟩
  · rintro ⟨d, o, l, rfl, h⟩; exact .view h

theorem valOK_prod {a b : Ty} :
    ValOK m (.prod a b) v P H ↔ ∃ x y, v = .pair x y ∧ ValOK m a x (P ++ H) H ∧ ValOK m b y (P ++ H) H := by
  constructor
  · intro h; cases h with | pair hx hy => exact ⟨_, _, rfl, hx, hy⟩
  · rintro ⟨x, y, rfl, hx, hy⟩; exact .pair hx hy

theorem valOK_sum {a b : Ty} :
    ValOK m (.sum a b) v P H ↔
      (∃ x, v = .inl x ∧ ValOK m a x (P ++ H) H) ∨ (∃ x, v = .inr x ∧ ValOK m b x (P ++ H) H) := by
  constructor
  · intro h
    cases h with
    | inl hx => exact Or.inl ⟨_, rfl, hx⟩
    | inr hx => exact Or.inr ⟨_, rfl, hx⟩
  · rintro (⟨x, rfl, hx⟩ | ⟨x, rfl, hx⟩)
    · exact .inl hx
    · exact .inr hx

theorem valOK_fn {ms : List Nat} {q : Cross} :
    ValOK m (.fn ms q) v P H ↔
      ∃ fs te x cs, v = .pkg fs te ms x cs ∧ ValOK m te x (P ++ envDeps cs H) (envDeps cs H) ∧
        q.Fits te cs := by
  constructor
  · intro h; cases h with | pkg hx hq => exact ⟨_, _, _, _, rfl, hx, hq⟩
  · rintro ⟨f, te, x, cs, rfl, hx, hq⟩; exact .pkg hx hq

/-- An integer depends on nothing. -/
theorem ValOK.int_any {m' : Mem} {P' H' : List Dep} (h : ValOK m .int v P H) : ValOK m' .int v P' H' := by
  cases h; exact .int

end ValOK

/-- A2-drop.3: `peel_dtor` (`Semantics.lean`), now over the validity
    predicates too.  (Its names resolve where the rule is written.) -/
macro_rules
  | `(tactic| peel_dtor $τ $σ $hnd $hw) => `(tactic| (
      have $hnd := Ty.undtor_ne $τ
      replace $hw := WFv.undtor $hw
      try simp only [← ArcIn.undtor_iff (τ := $τ)] at *
      try simp only [← SharesIn.undtor_iff (τ := $τ)] at *
      try simp only [← SharesOK.undtor_iff (τ := $τ)] at *
      try simp only [← ViewIn.undtor_iff (τ := $τ)] at *
      try simp only [← ViewsOK.undtor_iff (τ := $τ)] at *
      try simp only [← valOK_undtor (τ := $τ)] at *
      generalize ($τ).undtor = $σ at *))


def OwnedAt (m : Mem) (x : Var) (t : Val) : Prop := m.st x = some ⟨true, some t⟩

/-- No view stored in a tree points into that same tree's buffers (a struct
    never views its own field). -/
def SelfFree (T : Val) : Prop :=
  ∀ d o l, Sub (.view d o l) T → ∀ u c es, ¬ Sub (.node u c d es) T

/-- A3.1: every block owns its payload tree, as a slot owns its tree: the
    tree's addresses appear once in it, in no owned tree and in no other
    block's payload, and are live and below `nid`.  The block's key was taken
    from `nid` too (a key is never an address), so a new one is fresh. -/
def BlkOwn (m : Mem) : Prop :=
  ∀ k bl, m.blk k = some bl → k < m.nid ∧ bl.tree.ids.Nodup ∧
    ∀ i ∈ bl.tree.ids, m.alloc i = true ∧ i < m.nid ∧ (∀ x T, OwnedAt m x T → i ∉ T.ids) ∧
      ∀ k' bl', k' ≠ k → m.blk k' = some bl' → i ∉ bl'.tree.ids

/-- A3.3: every view of a lock block (`rw_read`'s guard) reads the payload
    its lock block holds now: its payload is a share of that block and the
    block's payload, at the type `prod (lk t) t`.  (So the block's payload
    is in, and no writer has it checked out, while a view of it lives.) -/
def ViewsAt (B : Nat → Option Blk) : Prop :=
  ∀ k' bl, B k' = some bl → bl.kind = .view →
    ∃ k t p, bl = ⟨.prod (.lk t) t, .view, some (.pair (.lk k) p)⟩ ∧ B k = some ⟨t, .lock, some p⟩

/-- No view is left of the blocks of a store with no view. -/
theorem ViewsAt.of_none {B : Nat → Option Blk} (h : ∀ k bl, B k = some bl → bl.kind ≠ .view) : ViewsAt B :=
  fun k bl hk hv => absurd hv (h k bl hk)

/-- One owner per allocation, every owned address is live, and no owned tree
    views itself. -/
structure HeapOK (m : Mem) : Prop where
  nodup : ∀ x t, OwnedAt m x t → t.ids.Nodup
  disj  : ∀ x y t u, x ≠ y → OwnedAt m x t → OwnedAt m y u → ∀ i ∈ t.ids, i ∉ u.ids
  alloc : ∀ x t, OwnedAt m x t → ∀ i ∈ t.ids, m.alloc i = true ∧ i < m.nid
  self  : ∀ x t, OwnedAt m x t → SelfFree t
  /-- A3.1: the blocks own their payloads (`BlkOwn`). -/
  blk   : BlkOwn m
  /-- A3.3: every view reads its lock block's payload (`ViewsAt`). -/
  views : ViewsAt m.blk

/-- A3.1: a block's key was taken from `nid`, so a new one is fresh. -/
theorem HeapOK.bkey {m : Mem} (hh : HeapOK m) : ∀ k bl, m.blk k = some bl → k < m.nid :=
  fun k bl hk => (hh.blk k bl hk).1

/-- A3.1: an address a block's payload owns. -/
def PayAddr (m : Mem) (i : Nat) : Prop := ∃ k bl, m.blk k = some bl ∧ i ∈ bl.tree.ids

/-- No owned tree holds a payload's address. -/
theorem HeapOK.notPay {m : Mem} (hh : HeapOK m) {x : Var} {T : Val} (hT : OwnedAt m x T) {i : Nat}
    (hi : i ∈ T.ids) : ¬ PayAddr m i := fun ⟨k, bl, hk, hik⟩ =>
  ((hh.blk k bl hk).2.2 i hik).2.2.1 x T hT hi

/-- A payload's address is live and below `nid`. -/
theorem HeapOK.payAlloc {m : Mem} (hh : HeapOK m) {i : Nat} (hi : PayAddr m i) :
    m.alloc i = true ∧ i < m.nid := by
  obtain ⟨k, bl, hk, hik⟩ := hi
  exact ⟨((hh.blk k bl hk).2.2 i hik).1, ((hh.blk k bl hk).2.2 i hik).2.1⟩

/-- Blocks whose payloads own no address own them trivially. -/
theorem BlkOwn.of_none {m : Mem} (h : ∀ k bl, m.blk k = some bl → bl.tree.ids = [] ∧ k < m.nid) :
    BlkOwn m := fun k bl hk => by
  obtain ⟨h1, h2⟩ := h k bl hk
  rw [h1]; exact ⟨h2, List.nodup_nil, fun _ h => nomatch h⟩

/-- **The blocks' frame**: blocks as they were, `nid` later, their payloads'
    addresses as live as they were, and every owned tree holding no payload's
    address keep `BlkOwn`. -/
theorem BlkOwn.frame {m m' : Mem} (h : BlkOwn m) (hb : m'.blk = m.blk) (hn : m.nid ≤ m'.nid)
    (ha : ∀ i, PayAddr m i → m'.alloc i = m.alloc i)
    (hown : ∀ x T, OwnedAt m' x T → ∀ i ∈ T.ids, ¬ PayAddr m i) : BlkOwn m' := by
  intro k bl hk
  rw [hb] at hk
  obtain ⟨hkey, hnd, hall⟩ := h k bl hk
  refine ⟨Nat.lt_of_lt_of_le hkey hn, hnd, fun i hi => ?_⟩
  obtain ⟨ha1, hlt, _, hoth⟩ := hall i hi
  refine ⟨by rw [ha i ⟨k, bl, hk, hi⟩]; exact ha1, Nat.lt_of_lt_of_le hlt hn,
    fun x T hT hiT => hown x T hT i hiT ⟨k, bl, hk, hi⟩, fun k' bl' hk' hk'' => ?_⟩
  rw [hb] at hk''; exact hoth k' bl' hk' hk''

/-- A binding's slot agrees with its entry. -/
def SlotOK (m : Mem) (E : Entry) (sl : Slot) : Prop :=
  sl.own = E.mode.ownSlot ∧
  (E.mode.ownSlot = true →
    E.ty.owning = true ∧ (∀ T, sl.val = some T → WFv E.ty T) ∧
    (E.live = true → ∃ T, sl.val = some T ∧ ViewsOK m E.ty T E.held)) ∧
  (E.mode.ownSlot = false →
    (E.live = true → ∃ v, sl.val = some v ∧ ValOK m E.ty v E.path E.held))

/-- A2-drop.2: a binding `letd` made whose slot owns a value is armed, and
    the value's views are valid, whether its entry is live or not: the
    destructor reads them where the scope ends (after a join on which one
    path moved it, the entry is dead but the slot may own). -/
def ArmOK (m : Mem) (E : Entry) (sl : Slot) : Prop :=
  E.dbind = true → E.mode.ownSlot = true → ∀ T, sl.val = some T → E.dtor = true ∧ ViewsOK m E.ty T E.held

/-- The bindings of the run-time scopes a statement is inside of, innermost
    last: they are bound for as long as the statement runs. -/
def Stmt.spine : Stmt → List Var
  | .seq a _ => a.spine
  | .scope x s => x :: s.spine
  | .scopeD x _ s => x :: s.spine
  | .rbind p s => p :: s.spine
  | .frozen _ s => s.spine
  | .catchR _ _ s => s.spine
  | .scopeL _ _ x s => x :: s.spine
  | _ => []

/-- An address is covered: a tree some binding owns holds it, or (A3.1) a
    live block's payload owns it. -/
def Covered (m : Mem) (i : Nat) : Prop := (∃ x t, OwnedAt m x t ∧ i ∈ t.ids) ∨ PayAddr m i

/-- Nothing leaks: every live address is covered. -/
def Covers (m : Mem) : Prop := ∀ i, m.alloc i = true → Covered m i

/-- A3.1: the values a `recover` frame's store `m0` holds outside the scopes
    `sp` the frame has opened, and its result `x`. -/
def OutVals (m0 : Mem) (x : Var) (sp : List Var) (v : Val) : Prop :=
  ∃ y o, y ∉ sp ∧ y ≠ x ∧ m0.st y = some ⟨o, some v⟩

/-- A `recover` frame returns to its caller's store: every binding outside
    the frames it has opened (and its result `x`) is as the caller left it,
    and (A3.1) so is every block those bindings reach (the sweep keeps
    them).  A3.2's second cut: reach through payloads that are read
    (`rdBlk`), which is what the bindings' facts read; a lock's payload, and
    so what it reaches, may change inside the frame. -/
def CatchOK (m : Mem) : Stmt → Prop
  | .seq a _ => CatchOK m a
  | .scope _ s => CatchOK m s
  | .scopeD _ _ s => CatchOK m s
  | .rbind _ s => CatchOK m s
  | .frozen _ s => CatchOK m s
  | .catchR x m0 s => (∀ v, v ∉ s.spine → v ≠ x → m.st v = m0.st v) ∧
      x ∉ s.spine ∧ m0.nv ≤ m.nv ∧
      (∀ k bl, m0.blk k = some bl → Reached (OutVals m0 x s.spine) (rdBlk m0.blk) k →
        ∃ bl', m.blk k = some bl' ∧ BlkKeep bl bl') ∧
      CatchOK m s
  | .scopeL _ _ _ s => CatchOK m s
  | _ => True

/-- A borrowed parameter depends only on what was bound before its call: on
    no binding of a run-time scope the call's body has opened. A panic that
    unwinds those scopes therefore leaves its dependencies bound. -/
def PinOK (Γ : Ctx) : Stmt → Prop
  | .seq a _ => PinOK Γ a
  | .scope _ s => PinOK Γ s
  | .scopeD _ _ s => PinOK Γ s
  | .rbind p s => (∀ E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∉ s.spine) ∧ PinOK Γ s
  | .frozen _ s => PinOK Γ s
  | .catchR _ _ s => PinOK Γ s
  | .scopeL _ _ _ s => PinOK Γ s
  | _ => True

/-- A2-drop.2: a binding `letd` made depends, in memory, on no binding of
    a run-time scope opened inside its own frame, so a panic that unwinds
    those scopes leaves its views bound (nurlc #254). -/
def DtorIn (Γ : Ctx) (x : Var) (s : Stmt) : Prop :=
  ∀ E, Γ x = some E → E.dbind = true → E.mode.ownSlot = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
    ∀ d ∈ E.vdeps, d.kind.isName = false → d.root ∉ s.spine

def DtorPinOK (Γ : Ctx) : Stmt → Prop
  | .seq a _ => DtorPinOK Γ a
  | .scope x s => DtorIn Γ x s ∧ DtorPinOK Γ s
  | .scopeD x _ s => DtorIn Γ x s ∧ DtorPinOK Γ s
  | .rbind p s => DtorIn Γ p s ∧ DtorPinOK Γ s
  | .frozen _ s => DtorPinOK Γ s
  | .catchR _ _ s => DtorPinOK Γ s
  | .scopeL _ _ x s => DtorIn Γ x s ∧ DtorPinOK Γ s
  | _ => True

/-- A statement inside no run-time scope pins nothing. -/
theorem DtorPinOK.of_spine_nil {Γ : Ctx} {s : Stmt} (h : s.spine = []) : DtorPinOK Γ s := by
  induction s with
  | seq a _ iha _ => exact iha h
  | frozen _ k ih => exact ih h
  | catchR _ _ k ih => exact ih h
  | scope _ _ _ => simp [Stmt.spine] at h
  | scopeD _ _ _ _ => simp [Stmt.spine] at h
  | rbind _ _ _ => simp [Stmt.spine] at h
  | scopeL _ _ _ _ _ => simp [Stmt.spine] at h
  | _ => trivial

/-- `DtorPinOK` reads only what the `letd` bindings view: a context that
    keeps them, or views less, keeps it. -/
theorem DtorPinOK.of_dbind {Γ Γ' : Ctx}
    (h : ∀ v E', Γ' v = some E' → E'.dbind = true → E'.mode.ownSlot = true →
      (E'.ty ≠ .int ∨ E'.mode = .rootb) → ∃ E, Γ v = some E ∧ E.dbind = true ∧ E.mode.ownSlot = true ∧
        (E.ty ≠ .int ∨ E.mode = .rootb) ∧ ∀ d ∈ E'.vdeps, d.kind.isName = false → d ∈ E.vdeps)
    {s : Stmt} (hp : DtorPinOK Γ s) : DtorPinOK Γ' s := by
  have hin : ∀ x k, DtorIn Γ x k → DtorIn Γ' x k := by
    intro x k hx E' hE' hd hos hn d hdd hnm
    obtain ⟨E, hE, hd0, hos0, hn0, hsub⟩ := h x E' hE' hd hos hn
    exact hx E hE hd0 hos0 hn0 d (hsub d hdd hnm) hnm
  induction s with
  | seq a _ iha _ => exact iha hp
  | scope x k ih => exact ⟨hin x k hp.1, ih hp.2⟩
  | scopeD x _ k ih => exact ⟨hin x k hp.1, ih hp.2⟩
  | rbind p k ih => exact ⟨hin p k hp.1, ih hp.2⟩
  | frozen _ k ih => exact ih hp
  | catchR _ _ k ih => exact ih hp
  | scopeL _ _ x k ih => exact ⟨hin x k hp.1, ih hp.2⟩
  | _ => trivial

theorem dtorOut_nil {Γ : Ctx} {s : Stmt} (h : s.spine = []) :
    ∀ v E, Γ v = some E → E.dbind = true → E.mode.ownSlot = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
      v ∉ s.spine → ∀ d ∈ E.vdeps, d.kind.isName = false → d.root ∉ s.spine :=
  fun _ _ _ _ _ _ _ _ _ _ hr => by rw [h] at hr; cases hr

/-- `PinOK` reads only borrowed parameters: a context that keeps them keeps it. -/
theorem PinOK.of_rootb {Γ Γ' : Ctx} (h : ∀ p E, Γ' p = some E → E.mode = .rootb → Γ p = some E)
    {s : Stmt} (hp : PinOK Γ s) : PinOK Γ' s := by
  induction s with
  | seq a _ iha _ => exact iha hp
  | scope _ k ih => exact ih hp
  | scopeD _ _ k ih => exact ih hp
  | rbind p k ih => exact ⟨fun E hE hm => hp.1 E (h p E hE hm) hm, ih hp.2⟩
  | frozen _ k ih => exact ih hp
  | catchR _ _ k ih => exact ih hp
  | scopeL _ _ _ k ih => exact ih hp
  | _ => trivial

/-- A statement inside no run-time scope is inside no call either. -/
theorem PinOK.of_spine_nil {Γ : Ctx} {s : Stmt} (h : s.spine = []) : PinOK Γ s := by
  induction s with
  | seq a _ iha _ => exact iha h
  | frozen _ k ih => exact ih h
  | catchR _ _ k ih => exact ih h
  | scope _ _ _ => simp [Stmt.spine] at h
  | scopeD _ _ _ _ => simp [Stmt.spine] at h
  | rbind _ _ _ => simp [Stmt.spine] at h
  | scopeL _ _ _ _ _ => simp [Stmt.spine] at h
  | _ => trivial

theorem pinOut_nil {Γ : Ctx} {s : Stmt} (h : s.spine = []) :
    ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ s.spine → ∀ r ∈ roots E.vdeps, r ∉ s.spine :=
  fun _ _ _ _ _ _ _ hr => by rw [h] at hr; cases hr

/-- A borrowed parameter is anchored: what it borrows from, and what the
    closures it holds only read, are lent out (`F`) for as long as it is
    bound.  (What those closures may change is pinned: no rule replaces it,
    `NoPin`.) -/
def Anchored (E : Entry) (F : List Var) : Prop :=
  ∀ d ∈ E.vdeps, d.kind.bound = .none → d.root ∈ F

/-- The borrowed parameters' anchors. -/
def RootbAnch (Γ : Ctx) (F : List Var) : Prop :=
  ∀ p E, Γ p = some E → E.mode = .rootb → Anchored E F

theorem Anchored.mono {E : Entry} {F F' : List Var} (h : Anchored E F) (hF : ∀ v ∈ F, v ∈ F') :
    Anchored E F' :=
  fun d hd hb => hF _ (h d hd hb)


/-- A2-drop.3d, Agora #610: what the invariant asks of a block's destructor
    values.  A lock block's and a view's payload owns none (a check-out
    binding is no `letd`'s).  An `arc` block's may be a destructor value at
    its top (`Ty.ok`'s `arc` case, `RhsT.arcNew`), and a `dead` block's (an
    orphan whose payload awaits its destructor, which the sweep marks from
    such an `arc` block, `Mem.sweepD`) is one.  A block of a type that owns
    one is of a destructor type that holds no closure, or (Agora #755) a
    drained `Vec` of such values at any depth: what a destructor frame's
    binding may be (`StmtT.scopeD`, `ScopeDTy`), so `Step.reap` can hand its
    payload to one.  (That its destructor is one the program checked is
    `MemCodes`'s, which knows the program: `DeadCodes`.) -/
def Blk.DtorOK (bl : Blk) : Prop :=
  (bl.kind ≠ .dead → bl.kind ≠ .arc → bl.ty.dtorFree = true) ∧
  (bl.kind = .dead → bl.ty.dtorFree = false) ∧
  (bl.ty.dtorFree = false → ∃ n f u, bl.ty = Ty.nest n (.dtor f u) ∧ u.hasFn = false)

/-- A `dead` block is of a destructor type that holds no closure, or (Agora
    #755) of a drained `Vec` of such values, at any depth. -/
theorem Blk.DtorOK.dead {bl : Blk} (h : bl.DtorOK) (hd : bl.kind = .dead) :
    ∃ n f u, bl.ty = Ty.nest n (.dtor f u) ∧ u.hasFn = false :=
  h.2.2 (h.2.1 hd)

/-- The facts are of the block's type and kind: a block of the same type and
    kind has them. -/
theorem Blk.DtorOK.of_eq {bl bl' : Blk} (h : bl.DtorOK) (ht : bl'.ty = bl.ty) (hk : bl'.kind = bl.kind) :
    bl'.DtorOK := by
  obtain ⟨h1, h2, h3⟩ := h
  refine ⟨fun a b => ?_, fun a => ?_, fun a => ?_⟩
  · rw [ht]; exact h1 (hk ▸ a) (hk ▸ b)
  · rw [ht]; exact h2 (hk ▸ a)
  · rw [ht] at a ⊢; exact h3 a

/-- What memory and context guarantee, whatever is running. -/
structure MInv (m : Mem) (Γ : Ctx) : Prop where
  dom       : ∀ v, (Γ v).isSome = (m.st v).isSome
  slot      : ∀ v E, Γ v = some E → ∃ sl, m.st v = some sl ∧ E.ty.ok = true ∧ SlotOK m E sl
  heap      : HeapOK m
  nvSt      : ∀ v, (m.st v).isSome → v < m.nv
  noInout   : ∀ v E b, Γ v = some E → E.mode ≠ .inout b
  wf        : CtxWF Γ
  rootbLive : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true
  rootbLt   : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r < p
  names     : NameWF Γ
  held      : ∀ v E sl T, Γ v = some E → E.live = true → m.st v = some sl → sl.val = some T →
                NamesIn T E.held
  pkgs      : ∀ v sl T, m.st v = some sl → sl.val = some T → PkgsOK T
  armed     : ∀ v E sl, Γ v = some E → m.st v = some sl → ArmOK m E sl
  /-- A3.1: every share an owned tree holds names a live block of its type. -/
  shares    : ∀ v E sl T, Γ v = some E → m.st v = some sl → sl.own = true → sl.val = some T →
                SharesOK m E.ty T
  /-- A3.1: a block's payload is a well-formed tree of a type that holds no
      views, and the shares it holds name blocks too (A3.2: while it is in
      the block).  A3.2's second cut: a lock block's may hold `arc` and lock
      shares, which keep their blocks alive (`Blk.keeps`); A3.5's second cut:
      and cell shares, whose owners are then the payload (A3's `CellInv`).
      A3.5's third cut: a block that is no lock block (an `arc` block, a
      view) is of a type that holds no cell share (`RhsT.arcNew`'s and
      `RhsT.rwRead`'s premise, the Sync question): what its holders are lent
      (a lent cell share being the share) brings no library handle. -/
  blocks    : ∀ k bl, m.blk k = some bl → bl.ty.ok = true ∧ bl.ty.holdsView = false ∧
                (∀ p, bl.pay = some p → WFv bl.ty p ∧ SharesOK m bl.ty p) ∧
                (bl.kind = .lock ∨ bl.ty.hasCell = false) ∧
                -- A2-drop.3d, Agora #610: a lock's or a view's payload owns
                -- no destructor value; an `arc` block's may be one at its
                -- top, and a `dead` block's is (`Blk.DtorOK`)
                bl.DtorOK

/-- The invariant of a configuration running `s` in context `Γ`, with `F`
    lent out. -/
structure Inv (m : Mem) (Γ : Ctx) (F : List Var) (s : Stmt) : Prop extends MInv m Γ where
  nvS       : ∀ v ∈ s.vars, v < m.nv
  nvF       : ∀ v ∈ F, v < m.nv
  anch      : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ s.spine → Anchored E F
  spineNd   : s.spine.Nodup
  spineDom  : ∀ v ∈ s.spine, ∃ E, Γ v = some E
  catchOK   : CatchOK m s
  cover     : Covers m
  /-- A borrowed parameter bound outside the running scopes depends on none
      of their bindings, and each one bound inside depends on none of the
      scopes opened inside its call (`PinOK`). -/
  pinOut    : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ s.spine → ∀ r ∈ roots E.vdeps, r ∉ s.spine
  pinIn     : PinOK Γ s
  /-- A2-drop.2: so for a binding `letd` made, in memory (the panic path,
      nurlc #254). -/
  dtorOut   : ∀ v E, Γ v = some E → E.dbind = true → E.mode.ownSlot = true →
                (E.ty ≠ .int ∨ E.mode = .rootb) → v ∉ s.spine → ∀ d ∈ E.vdeps,
                d.kind.isName = false → d.root ∉ s.spine
  dtorIn    : DtorPinOK Γ s

/-! ### Typing of statements

Here, after the invariant, because the run-time form of a `recover` frame
is typed by the store it will return to. -/

/-- The bindings outside `sp` are those of `Δ`, with their modes and types,
    and a borrowed parameter's entry unchanged. -/
def KeepOut (Γ Δ : Ctx) (sp : List Var) : Prop :=
  (∀ v E, Γ v = some E → v ∉ sp →
    ∃ E', Δ v = some E' ∧ E'.mode = E.mode ∧ E'.ty = E.ty ∧ (E.mode = .rootb → E' = E)) ∧
  (∀ v E', Δ v = some E' → v ∉ sp ∧ ∃ E, Γ v = some E)

/-! ### The call's result frame (`resFrame`): a scope's, or a destructor frame's -/

/-- Agora #607: the shapes a call's owned result of a destructor frame has:
    a destructor type, or a nest of `Vec`s around one. -/
def ResDTy (g : Nat) (t τ : Ty) : Prop :=
  τ = .dtor g t ∨ ∃ n, τ = .vec (Ty.nest n (.dtor g t))

theorem ResDTy.of_dhead {τ : Ty} {g : Nat} (h : τ.dhead = some g) : ∃ t, ResDTy g t τ := by
  obtain ⟨n, t, rfl⟩ := Ty.dhead_some h
  cases n with
  | zero => exact ⟨t, Or.inl rfl⟩
  | succ n => exact ⟨t, Or.inr ⟨n, rfl⟩⟩

theorem ResDTy.dhead {τ : Ty} {g : Nat} {t : Ty} (h : ResDTy g t τ) : τ.dhead = some g := by
  rcases h with rfl | ⟨n, rfl⟩
  · rfl
  · simp [Ty.dhead]

theorem ResDTy.holdsDtor {τ : Ty} {g : Nat} {t : Ty} (h : ResDTy g t τ) : τ.holdsDtor = true := by
  rcases h with rfl | ⟨n, rfl⟩ <;> simp [Ty.holdsDtor]

theorem ResDTy.inj {τ : Ty} {g g' : Nat} {t t' : Ty} (h : ResDTy g t τ) (h' : ResDTy g' t' τ) :
    g = g' ∧ t = t' := by
  have key : ∀ n n' : Nat, Ty.nest n (.dtor g t) = Ty.nest n' (.dtor g' t') → g = g' ∧ t = t' := by
    intro n; induction n with
    | zero => intro n' e; cases n' with
      | zero => cases e; exact ⟨rfl, rfl⟩
      | succ n' => cases e
    | succ n ih => intro n' e; cases n' with
      | zero => cases e
      | succ n' => exact ih n' (by simpa using e)
  rcases h with rfl | ⟨n, rfl⟩ <;> rcases h' with e | ⟨n', e⟩
  · cases e; exact ⟨rfl, rfl⟩
  · cases e
  · cases e
  · exact key n n' (Ty.vec.inj e)

theorem resFrame_cases (fn : Fn) (r : Var) (s : Stmt) :
    resFrame fn r s = .scope r s ∨
      ∃ g t, fn.resOwn = true ∧ ResDTy g t fn.resTy ∧
        resFrame fn r s = .scopeD r g s := by
  unfold resFrame; split
  · rename_i g ho hg
    obtain ⟨t, ht⟩ := ResDTy.of_dhead hg
    exact Or.inr ⟨g, t, ho, ht, rfl⟩
  · exact Or.inl rfl

@[simp] theorem resFrame_spine (fn : Fn) (r : Var) (s : Stmt) : (resFrame fn r s).spine = r :: s.spine := by
  unfold resFrame; split <;> rfl

@[simp] theorem resFrame_vars (fn : Fn) (r : Var) (s : Stmt) : (resFrame fn r s).vars = r :: s.vars := by
  unfold resFrame; split <;> rfl

@[simp] theorem resFrame_hasThru (fn : Fn) (r : Var) (s : Stmt) : (resFrame fn r s).hasThru = s.hasThru := by
  unfold resFrame; split <;> rfl

@[simp] theorem resFrame_assigns (fn : Fn) (r : Var) (s : Stmt) : (resFrame fn r s).assigns = s.assigns := by
  unfold resFrame; split <;> rfl

@[simp] theorem resFrame_catchOK (m : Mem) (fn : Fn) (r : Var) (s : Stmt) :
    CatchOK m (resFrame fn r s) = CatchOK m s := by
  unfold resFrame; split <;> rfl

@[simp] theorem resFrame_pinOK (Γ : Ctx) (fn : Fn) (r : Var) (s : Stmt) :
    PinOK Γ (resFrame fn r s) = PinOK Γ s := by
  unfold resFrame; split <;> rfl

@[simp] theorem resFrame_dtorPinOK (Γ : Ctx) (fn : Fn) (r : Var) (s : Stmt) :
    DtorPinOK Γ (resFrame fn r s) = (DtorIn Γ r s ∧ DtorPinOK Γ s) := by
  unfold resFrame; split <;> rfl

/-- A2-drop.3b: the type of a destructor frame's binding (`scopeD x f`):
    the destructor type `Ty.dtor f t` itself, or a `Vec` of such values,
    which the frame's end drains (`Step.scopeDDrain`), or (Agora #607) a
    `Vec` of such `Vec`s at any depth (`Ty.nest`), whose drain binds each
    inner `Vec` by a `letd` frame of the same `f`, which drains it in turn.
    (Agora #782: the drained `Vec`'s elements may hold views, of bindings
    older than the `Vec`'s: its binding is armed, `Ty.dtorViews`, and each
    element moved out to its own `letd` is armed with them.) -/
def ScopeDTy (f : Nat) (t τ : Ty) : Prop :=
  τ = .dtor f t ∨ (∃ n, τ = .vec (Ty.nest n (.dtor f t)))

/-- What `letd x f r s` binds, at the type `τ`, from a value of type `a`: a
    destructor value (a `t` made here, or one of a destructor type over `t`
    moved in: that type, or another where `LetdFn` allows), or a `Vec` of
    destructor values, or of such `Vec`s (Agora #607). -/
def LetdTy (f : Nat) (t a τ : Ty) : Prop :=
  (τ = .dtor f t ∧ (a = t ∨ ∃ g, a = .dtor g t)) ∨
    (∃ n, τ = .vec (Ty.nest n (.dtor f t)) ∧ a = τ)

theorem LetdTy.scopeD {f : Nat} {t a τ : Ty} (h : LetdTy f t a τ) : ScopeDTy f t τ := by
  rcases h with ⟨h, _⟩ | ⟨n, h, _⟩
  · exact Or.inl h
  · exact Or.inr ⟨n, h⟩

/-- Agora #607: an element of a drained `Vec`, moved out to a `letd` of its
    own frame, is bound at its own type: a destructor value, or a drained
    `Vec` in turn. -/
theorem LetdTy.elem {f n : Nat} {t : Ty} :
    LetdTy f t (Ty.nest n (.dtor f t)) (Ty.nest n (.dtor f t)) := by
  cases n with
  | zero => exact Or.inl ⟨rfl, Or.inr ⟨f, rfl⟩⟩
  | succ n => exact Or.inr ⟨n, rfl, rfl⟩

/-- What `letd` binds is no integer: a struct or an enum, or its destructor
    type, or a `Vec`. -/
theorem LetdTy.ne_int {f : Nat} {t a τ : Ty} (h : LetdTy f t a τ) (hst : t.isStruct = true) :
    a ≠ .int := by
  rcases h with ⟨_, h' | ⟨g, h'⟩⟩ | ⟨_, h1, h'⟩
  · rw [h']; cases t <;> simp_all [Ty.isStruct]
  · rw [h']; simp
  · rw [h', h1]; simp

theorem ScopeDTy.hasFn {f : Nat} {t τ : Ty} (h : ScopeDTy f t τ) (hf : t.hasFn = false) :
    τ.hasFn = false := by
  rcases h with rfl | ⟨_, rfl⟩ <;> simpa [Ty.hasFn] using hf

theorem ScopeDTy.holdsView {f : Nat} {t τ : Ty} (h : ScopeDTy f t τ) : τ.holdsView = t.holdsView := by
  rcases h with rfl | ⟨n, rfl⟩
  · simp [Ty.holdsView]
  · simp [Ty.holdsView]

/-- The binding is armed exactly when its type holds views. -/
theorem ScopeDTy.dtorViews {f : Nat} {t τ : Ty} (h : ScopeDTy f t τ) : τ.dtorViews = τ.holdsView := by
  rcases h with rfl | ⟨n, rfl⟩
  · simp [Ty.dtorViews, Ty.holdsView]
  · simp [Ty.holdsView]

theorem ScopeDTy.ne_int {f : Nat} {t τ : Ty} (h : ScopeDTy f t τ) : τ ≠ .int := by
  rcases h with rfl | ⟨_, rfl⟩ <;> simp

/-- Agora #755: a nest of `Vec`s around a destructor type, at any depth, is
    a destructor frame's binding's type (what `Step.reap` binds an orphan's
    payload at). -/
theorem ScopeDTy.nest (n f : Nat) (t : Ty) : ScopeDTy f t (Ty.nest n (.dtor f t)) := by
  cases n with
  | zero => exact Or.inl rfl
  | succ n => exact Or.inr ⟨n, rfl⟩

/-- `f` is a destructor for values of type `t`: it takes one borrowed `t`,
    returns an integer and lends, holds and stores nothing. -/
def DtorOK (P : Prog) (f : Nat) (t : Ty) : Prop :=
  ∃ fn, P[f]? = some fn ∧ fn.params = [(.inp, t)] ∧ fn.resTy = .int ∧ fn.resOwn = false ∧
    fn.lends = [] ∧ fn.rholds = [] ∧ fn.outHolds = [] ∧
    -- a destructor changes no elements through a borrow (Agora #295)
    ¬ ThruFn P f

/-- Agora #616: `f` is the drop glue of the struct `t`: a function that
    takes one value of the destructor type `Ty.dtor f t` *owned* (`sink`)
    and takes it apart first thing (`unpair`), so each field is a binding of
    its own: a field that holds a destructor value goes to its `letd`
    (`StmtT.unpair`'s `hdx` / `hdz`), whose frame runs its destructor, on a
    panic in another field's too.  Its tail does nothing else (`Stmt.pureGlue`),
    so `unpair` of such a struct anywhere does what its drop does.  (Agora
    #633: the struct may hold views, of the caller's bindings: the frame's end
    moves it into the glue as any `sink` argument, `glueCall_typed`.) -/
def GlueOK (P : Prog) (f : Nat) (t : Ty) : Prop :=
  ∃ fn a b, P[f]? = some fn ∧ t = .prod a b ∧ fn.params = [(.sink, .dtor f t)] ∧ fn.resTy = .int ∧
    fn.resOwn = false ∧ fn.lends = [] ∧ fn.rholds = [] ∧ fn.outHolds = [] ∧ ¬ ThruFn P f ∧
    ∃ x z s, fn.body = .unpair 0 x z s ∧ s.pureGlue = true

/-- Agora #632: `f` is the drop glue of the enum `t`: a function that takes
    one value of the destructor type `Ty.dtor f t` owned and matches on its
    tag; in the arm of a variant whose payload holds a destructor value the
    payload moves out to a `letd` first thing (`takel` / `taker`), whose
    frame runs its destructor; the arms do nothing else (`Stmt.pureGlue`).
    (Agora #750: the enum may hold views, a payload of its own, as a
    struct's field may since #633: the frame's end moves it into the glue
    as any `sink` argument; witness `A2.DtorWitness.main12_safe`.) -/
def EnumGlueOK (P : Prog) (f : Nat) (t : Ty) : Prop :=
  ∃ fn a b sa sb, P[f]? = some fn ∧ t = .sum a b ∧
    fn.params = [(.sink, .dtor f t)] ∧ fn.resTy = .int ∧
    fn.resOwn = false ∧ fn.lends = [] ∧ fn.rholds = [] ∧ fn.outHolds = [] ∧ ¬ ThruFn P f ∧
    fn.body = .ite (.isl 0) sa sb ∧ sa.pureGlue = true ∧ sb.pureGlue = true ∧
    (a.holdsDtor = true → ∃ y g k, sa = .letd y g (.takel 0) k) ∧
    (b.holdsDtor = true → ∃ z g k, sb = .letd z g (.taker 0) k)

/-- Agora #616, #632: `f` is the drop glue of a struct or an enum `t` that
    has a `% Drop` of its own (`i`, which takes the value lent) beside fields
    or a payload that hold destructor values: `f` takes the value owned,
    rebinds it under the fields' (or the payload's) glue `h` (a `letd` at
    `Ty.dtor h t`: from there on a panic takes it apart, a frame per part),
    runs the impl on it lent, and sets its result.  nurlc's order: the impl,
    then the parts.  (Agora #633, #750: a struct's or an enum's may hold views;
    witness `A2.DtorWitness.main13_safe`.) -/
def ImplGlueOK (P : Prog) (f : Nat) (t : Ty) (h i : Nat) : Prop :=
  ∃ fn w r e, P[f]? = some fn ∧ t.isStruct = true ∧
    fn.params = [(.sink, .dtor f t)] ∧ fn.resTy = .int ∧
    fn.resOwn = false ∧ fn.lends = [] ∧ fn.rholds = [] ∧ fn.outHolds = [] ∧ ¬ ThruFn P f ∧
    (GlueOK P h t ∨ EnumGlueOK P h t) ∧ DtorOK P i (.dtor h t) ∧
    fn.body = .letd w h (.var 0) (.letcall r i [w] (.assign 1 (.expr e)))

/-- Agora #609: `f` is the drop glue of the closure type `t` (class
    `dropd`: its environment holds destructor values): `f` takes the closure
    owned and calls its drop method `j` first thing, whose interface takes
    the receiver owned too (`StmtT.callcE`'s second case): the environment
    is handed to the method's code for good (`Step.callcD`), which binds what
    it holds under `letd`s (`DtorParamsOK`), so each destructor runs, on a
    panic in another's too.  Then the integer result is set and nothing else
    runs. -/
def ClosureGlueOK (P : Prog) (f : Nat) (t : Ty) : Prop :=
  ∃ fn ms j σ sig r e, P[f]? = some fn ∧ t = .fn ms .dropd ∧
    fn.params = [(.sink, .dtor f t)] ∧ fn.resTy = .int ∧
    fn.resOwn = false ∧ fn.lends = [] ∧ fn.rholds = [] ∧ fn.outHolds = [] ∧ ¬ ThruFn P f ∧
    ms[j]? = some σ ∧ P[σ]? = some sig ∧ sig.params = [(.sink, .dtor f t)] ∧
    fn.body = .callcE r 0 j [] (.assign 1 (.expr e))

/-- What `unpair` takes apart is a struct under its destructor type, if any. -/
theorem unpair_undtor {τ a b : Ty} {G : Nat → Prop} (h : τ = .prod a b ∨ ∃ f, τ = .dtor f (.prod a b) ∧ G f) :
    τ.undtor = .prod a b := by
  rcases h with h | ⟨f, h, _⟩ <;> subst h <;> rfl

theorem unpair_ne_int {τ a b : Ty} {G : Nat → Prop} (h : τ = .prod a b ∨ ∃ f, τ = .dtor f (.prod a b) ∧ G f) :
    τ ≠ .int := by
  rcases h with h | ⟨f, h, _⟩ <;> subst h <;> simp

/-- What runs when a value of the destructor type `Ty.dtor f t` is dropped:
    a destructor that takes it lent (`DtorOK`; then the tree is freed with
    no code, so a struct `t` holds no destructor value), or a struct's
    glue, which takes it apart (`GlueOK`), or first runs the value's own
    impl on it (`ImplGlueOK`), or an enum's glue (`EnumGlueOK`), or (Agora
    #609) a closure's, which calls its drop method (`ClosureGlueOK`). -/
def DropFnOK (P : Prog) (f : Nat) (t : Ty) : Prop :=
  (DtorOK P f (.dtor f t) ∧ t.holdsDtor = false) ∨ GlueOK P f t ∨
    (∃ h i, ImplGlueOK P f t h i) ∨ EnumGlueOK P f t ∨ ClosureGlueOK P f t

/-- A glue of any kind takes its value owned. -/
theorem sinkOf {P : Prog} {f : Nat} {t : Ty}
    (hg : GlueOK P f t ∨ (∃ h i, ImplGlueOK P f t h i) ∨ EnumGlueOK P f t ∨ ClosureGlueOK P f t) :
    ∃ fn, P[f]? = some fn ∧ fn.params = [(.sink, .dtor f t)] ∧
      fn.resOwn = false ∧ ¬ ThruFn P f := by
  rcases hg with ⟨fn, _, _, hfn, _, hps, _, hro, _, _, _, hnt, _⟩ |
    ⟨_, _, fn, _, _, _, hfn, _, hps, _, hro, _, _, _, hnt, _⟩ |
    ⟨fn, _, _, _, _, hfn, _, hps, _, hro, _, _, _, hnt, _⟩ |
    ⟨fn, _, _, _, _, _, _, hfn, _, hps, _, hro, _, _, _, hnt, _⟩
  · exact ⟨fn, hfn, hps, hro, hnt⟩
  · exact ⟨fn, hfn, hps, hro, hnt⟩
  · exact ⟨fn, hfn, hps, hro, hnt⟩
  · exact ⟨fn, hfn, hps, hro, hnt⟩

/-- What `letd x f r s` asks of `f`, binding a value of type `a`: `f` is the
    destructor of `Ty.dtor f t` (`DropFnOK`); and a value of ANOTHER
    destructor type `Ty.dtor g t` moves in only where that is `g`'s drop
    (Agora #616): `g` is a struct's glue with an impl, `f` its fields' glue,
    and the scope starts with the impl's call on the new binding. -/
def LetdFn (P : Prog) (f : Nat) (t a : Ty) (x : Var) (s : Stmt) : Prop :=
  DropFnOK P f t ∧ ∀ g, a = .dtor g t → g ≠ f → ∃ i r k, ImplGlueOK P g t f i ∧ s = .letcall r i [x] k

theorem LetdFn.of {P : Prog} {f : Nat} {t a : Ty} {x : Var} {s : Stmt} (h : DropFnOK P f t)
    (hn : ∀ g, a = .dtor g t → g = f) : LetdFn P f t a x s :=
  ⟨h, fun g hg hne => absurd (hn g hg) hne⟩

/-- Agora #632: a payload is taken out of an enum under a destructor type
    (`RhsT.takel` / `taker`) only where the enum's destructor is its glue:
    taking the payload out is then what its drop does. -/
def TakeOK (P : Prog) (Γ : Ctx) (r : Rhs) : Prop :=
  ∀ y Ey g u, (r = .takel y ∨ r = .taker y) → Γ y = some Ey → Ey.ty = .dtor g u → EnumGlueOK P g u

theorem TakeOK.triv {P : Prog} {Γ : Ctx} {r : Rhs} (h : ∀ y, r ≠ .takel y ∧ r ≠ .taker y) : TakeOK P Γ r :=
  fun y _ _ _ hr _ _ => by
    rcases hr with hr | hr
    · exact absurd hr (h y).1
    · exact absurd hr (h y).2

/-- `TakeOK` for a right-hand side that is no `takel` / `taker`. -/
syntax "take_triv" : tactic
macro_rules
  | `(tactic| take_triv) =>
    `(tactic| exact TakeOK.triv (fun y => ⟨(by intro h; cases h), (by intro h; cases h)⟩))

/-- `LetdFn` where the value bound is of no other destructor type, and is
    no payload taken out. -/
macro "letd_fn" h:term : term =>
  `(And.intro (LetdFn.of $h (fun g hg => by
      first
        | exact (Ty.dtor.inj hg).1.symm
        | exact Ty.noConfusion hg
        | (cases hg; rfl)
        | (injection hg with h1 _; exact h1.symm)
        | (simp_all; done)
        | (exfalso; revert hg; simp_all [popE, compE]; done)))
      (TakeOK.triv (fun y => ⟨(by intro h; cases h), (by intro h; cases h)⟩)))

/-- A2-drop.3a: `letv`'s side condition, that the value it binds owned is of
    no destructor type, for an entry the rules build (none but `letd`'s is of
    one): its type is no destructor type, or its mode no owner. -/
syntax "no_dtor" : tactic
macro_rules
  | `(tactic| no_dtor) => `(tactic| first
      | (intro _; rfl)
      | (intro h; simp_all [Ty.hasDtor, Ty.holdsDtor]; done)
      | (intro h; exfalso; revert h; simp_all; done)
      | (intro h; exfalso; revert h; simp_all [getE, projE, intE]; done))

/-- ... and that an owned value of a destructor type is handed to its
    `letd` first thing (`Stmt.movedFirst`), where a type is concrete: it is no
    destructor type, or the value is not owned. -/
syntax "dtor_head" : tactic
macro_rules
  | `(tactic| dtor_head) => `(tactic| first
      | (intro _ h; simp_all [Ty.hasDtor, Ty.holdsDtor])
      | (intro h; exfalso; revert h; simp_all)
      | (intro _ h; exfalso; revert h; simp_all [Ty.hasDtor, Ty.holdsDtor])
      | (intro _ _ _ h; simp_all [Ty.hasDtor, Ty.holdsDtor])
      | (intro fn hf ho; simp_all [Ty.hasDtor, Ty.holdsDtor]))

inductive StmtT (P : Prog) : Ctx → List Var → Stmt → Ctx → Prop
  | skip {Γ : Ctx} {F : List Var} : StmtT P Γ F .skip Γ
  | seq {Γ Γ1 Δ : Ctx} {F : List Var} {a b : Stmt} :
      b.src = true → StmtT P Γ F a Γ1 → StmtT P Γ1 F b Δ → StmtT P Γ F (.seq a b) Δ
  | letv {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {r : Rhs} {s : Stmt} {E : Entry}
      (hs : s.src = true) (hx : Γ x = none) (hxF : x ∉ F) (hr : RhsT Γ F r E Γ1)
      (hb : StmtT P (setE Γ1 x E) F s Δ) (he : EndOK Δ x)
      -- A2-drop.3a: an owned value of a destructor type, or of a struct or
      -- an enum holding one, is bound by `letd` (its scope runs the
      -- destructor, a struct's glue), wherever it came from
      (hnd : E.mode = .own → E.ty.holdsDtor = false := by no_dtor) :
      StmtT P Γ F (.letv x r s) (exitScope x Δ)
  | letcall {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {args : List Var} {s : Stmt}
      {E : Entry}
      (h1 : s.src = true) (h2 : Γ x = none) (h3 : x ∉ F) (h4 : CallT P Γ F f args E Γ1)
      (h5 : StmtT P (setE Γ1 x E) F s Δ) (h6 : EndOK Δ x)
      -- A2-drop.3a: an owned result of a destructor type goes to its `letd`
      -- first thing, whose scope runs the destructor where `x`'s ends
      -- (and is given no other value in it: its drop would run none, `Stmt.assigns`)
      (hdk : ∀ fn, P[f]? = some fn → fn.resOwn = true → fn.resTy.holdsDtor = true →
        x ∈ s.movedFirst ∧ x ∉ s.assigns := by dtor_head) :
      StmtT P Γ F (.letcall x f args s) (exitScope x Δ)
  | scope {Γ Δ : Ctx} {F : List Var} {x : Var} {s : Stmt} :
      (∃ E, Γ x = some E ∧ E.mode ≠ .rootb) → x ∉ F → StmtT P Γ F s Δ → EndOK Δ x →
      StmtT P Γ F (.scope x s) (exitScope x Δ)
  | rbind {Γ Δ : Ctx} {F : List Var} {p : Var} {s : Stmt} {E : Entry} :
      Γ p = some E → E.mode = .rootb → E.live = true → Anchored E F → p ∉ F →
      StmtT P Γ F s Δ →
      -- what the borrowed binding may change by name is not lent, but stays
      -- bound for its scope: it is the caller's
      (∀ d ∈ E.vdeps, d.kind.bound ≠ .none → d.root ≠ p ∧ ∃ Er, Δ d.root = some Er ∧ Er.mode.isRoot = true) →
      StmtT P Γ F (.rbind p s) (exitRoot p (E.path ++ E.held) Δ)
  | frozen {Γ Δ : Ctx} {F z z' : List Var} {s : Stmt} :
      -- `z` bounds what is lent: the typing lends a part of it
      StmtT P Γ (F ++ z') s Δ → (∀ v ∈ z', v ∈ z) → StmtT P Γ F (.frozen z s) Δ
  | assign {Γ Γ1 : Ctx} {F : List Var} {x : Var} {r : Rhs} {Ex E : Entry} :
      Γ x = some Ex → x ∉ F →
      (Ex.mode = .own ∧ E.mode = .own ∨ Ex.mode = .inout .replace ∧ E.mode = .own ∨
        Ex.mode = .bor ∧ E.mode = .bor) →
      RhsT Γ F r E Γ1 → E.ty = Ex.ty → x ∉ roots E.vdeps → (Γ1 x).isSome → NoPin Γ x →
      DtorSafe Γ1 .replace false x →
      -- A2-drop.2: a binding `letd` made gains no view (nurlc #254; its rule,
      -- views of older bindings only, needs an age the calculus lacks)
      Ex.dbind = false →
      -- (Agora #632: a payload taken out of an enum of a destructor type, as `letd`'s)
      (htk : TakeOK P Γ r := by take_triv) →
      StmtT P Γ F (.assign x r) (setE (kill .replace false x Γ1) x { E with mode := Ex.mode })
  | ite {Γ Δ : Ctx} {F : List Var} {c : Expr} {a b : Stmt} :
      a.src = true → b.src = true → ExprT Γ c → StmtT P Γ F a Δ → StmtT P Γ F b Δ →
      StmtT P Γ F (.ite c a b) Δ
  | while {Γ : Ctx} {F : List Var} {c : Expr} {s : Stmt} :
      s.src = true → ExprT Γ c → StmtT P Γ F s Γ → StmtT P Γ F (.while c s) Γ
  | push {Γ Γ1 : Ctx} {F : List Var} {x y : Var} {Ex Ey Ex1 : Entry} {t : Ty} {D : List Dep} :
      Γ x = some Ex → Ex.live = true → Ex.ty = .vec t → canDo Ex.mode .realloc → x ∉ F →
      Γ y = some Ey → Ey.live = true → Ey.ty = t → y ≠ x →
      PushArg Γ F y Ey t D Γ1 → x ∉ roots D →
      Γ1 x = some Ex1 → Ex1.live = true → DtorSafe Γ1 .realloc t.holdsView x →
      -- A2-drop.2: a destructor binding gains no view: (Agora #782) what the
      -- value pushed into one holds, it records as viewing already (`letd`
      -- may record views of older bindings up front, `HeldUp`)
      (Ex1.dbind = true → ownHeld true t D ⊆ Ex1.held) →
      StmtT P Γ F (.push x y)
        (setE (kill .realloc t.holdsView x Γ1) x { Ex1 with held := Ex1.held ++ ownHeld true t D })
  | free {Γ : Ctx} {F : List Var} {x : Var} {E : Entry} {t : Ty} :
      Γ x = some E → E.live = true → E.mode = .own → E.ty = .vec t → x ∉ F → EndOK Γ x →
      -- (A2-drop.3b: the elements it releases own no destructor value: a `Vec`
      -- of destructor values is drained at its binding's end, not freed)
      t.dtorFree = true →
      StmtT P Γ F (.free x) (setE (kill .replace false x Γ) x { E with live := false, dtor := false })
  | sub {Γ Γ0 Δ0 Δ : Ctx} {F : List Var} {s : Stmt} :
      Weaker Γ Γ0 → StmtT P Γ0 F s Δ0 → (Δ0 = Δ ∨ Weaker Δ0 Δ) → StmtT P Γ F s Δ
  | panic {Γ Δ : Ctx} {F : List Var} :
      -- a panic never ends normally: what follows it may assume any context
      -- with the same bindings, modes and types, fixed entries as they were
      CtxWF Δ → NameWF Δ → (∀ v, (Γ v).isSome = (Δ v).isSome) →
      (∀ v E, Δ v = some E → ∃ E0, Γ v = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty ∧
        (E0.fixed → E = E0)) →
      -- A2-drop.2: ... and no binding `letd` made viewing more than it did,
      -- nor any no longer `letd`'s
      DKeep Γ Δ [] → DStay Γ Δ [] →
      StmtT P Γ F .panic Δ
  | letrec {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {s : Stmt} {E : Entry} {fn : Fn} :
      s.src = true → Γ x = none → x ∉ F → P[f]? = some fn → fn.params = [] → fn.resTy = .int →
      fn.resOwn = false → CallT P Γ F f [] E Γ1 → StmtT P (setE Γ1 x E) F s Δ →
      EndOK Δ x → StmtT P Γ F (.letrec x f s) (exitScope x Δ)
  | unpair {Γ Δ : Ctx} {F : List Var} {y x z : Var} {s : Stmt} {E : Entry} {a b : Ty}
      -- (an `inout` struct that may be replaced is taken apart too: a field
      -- replaced in place is the struct taken apart and assigned again)
      (h1 : s.src = true) (h2 : Γ y = some E) (h3 : E.live = true) (h4 : canDo E.mode .replace)
      -- (Agora #616: a struct, or a destructor type whose destructor is the
      -- struct's glue: taking it apart is what its drop does)
      (h5 : E.ty = .prod a b ∨ ∃ f, E.ty = .dtor f (.prod a b) ∧ GlueOK P f (.prod a b)) (h6 : y ∉ F)
      (h7 : Γ x = none) (h8 : Γ z = none) (h9 : x ≠ z) (h10 : x ∉ F) (h11 : z ∉ F)
      (h12 : StmtT P (setE (setE (setE (kill .replace false y Γ) y { E with live := false, dtor := false }) x (compE E a)) z
        (compE E b)) F s Δ)
      -- `y` is replaced, not ended: what borrows it by name, and a destructor
      -- that views it, are what replacing it ends
      (h13 : NoPin Γ y) (h14 : DtorSafe Γ .replace false y) (h15 : EndOK Δ z) (h16 : EndOK (exitScope z Δ) x)
      -- A2-drop.3a: a field of a destructor type goes to its `letd` first
      -- thing, whose scope runs the destructor where the field's binding ends
      (hdx : a.holdsDtor = true → x ∈ s.movedFirst ∧ x ∉ s.assigns := by dtor_head)
      (hdz : b.holdsDtor = true → z ∈ s.movedFirst ∧ z ∉ s.assigns := by dtor_head) :
      StmtT P Γ F (.unpair y x z s) (exitScope x (exitScope z Δ))
  | callc {Γ Γ1 Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var} {k : Stmt}
      {Ec E : Entry} {ms : List Nat} {q : Cross} {σ : Nat} {sig : Fn}
      (h1 : k.src = true) (h2 : Γ x = none) (h3 : x ∉ F) (h4 : Γ c = some Ec)
      -- (Agora #651: the receiver may be of a destructor type over the
      -- closure type; a well-formed such type is over a closure of the
      -- dropping class, `ok_undtor_fn`; the interface takes the receiver at
      -- the binding's type)
      (h5 : Ec.ty.undtor = .fn ms q)
      (h6 : ms[j]? = some σ) (h7 : P[σ]? = some sig) (h8 : sig.params.head? = some (.inp, Ec.ty))
      (h9 : ∀ o ∈ sig.outHolds, o.2.1 ≠ 0)
      (h10 : CallT P Γ F σ (c :: zs) E Γ1)
      -- no argument is a binding the package may change by name (it is
      -- handed to the code as an `inout` argument of its own)
      (h11 : ∀ z ∈ zs, ∀ d ∈ Ec.vdeps, d.kind.bound ≠ .none → d.root ≠ z)
      (h12 : StmtT P (setE Γ1 x (recvRes c Ec E)) F k Δ)
      (h13 : EndOK Δ x)
      -- the interface is not code that changes elements through a borrow
      -- (Agora #295; nor is the code that runs: `Implements`)
      (h14 : ¬ ThruFn P σ)
      -- (A2-drop.3a: as `letcall`'s)
      (hdk : sig.resOwn = true → sig.resTy.holdsDtor = true → x ∈ k.movedFirst ∧ x ∉ k.assigns :=
        by dtor_head) :
      StmtT P Γ F (.callc x c j zs k) (exitScope x Δ)
  | catchR {Γ Δ : Ctx} {F : List Var} {x : Var} {m0 : Mem} {s : Stmt} :
      x ∉ F → StmtT P Γ (F ++ (List.range m0.nv).filter (· ≠ x)) s Δ →
      MInv (m0.set x ⟨false, some (.int 1)⟩) Δ →
      (RootbAnch Δ F) →
      KeepOut Γ Δ s.spine → DStay Γ Δ s.spine →
      StmtT P Γ F (.catchR x m0 s) Δ
  /-- A2-drop: a binding that runs a destructor at its end: of a destructor
      type (armed when the type holds views, A2-drop.2), or of a `Vec` of
      destructor values, drained there (A2-drop.3b). -/
  | letd {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {r : Rhs} {s : Stmt} {E : Entry}
      {t : Ty} {H : List Dep} {τ : Ty} :
      s.src = true → Γ x = none → x ∉ F → RhsT Γ F r E Γ1 → E.mode = .own →
      -- A2-drop.3a: the binding is of the destructor type `Ty.dtor f t`, of a
      -- struct or an enum `t`: the value is a `t` made here, or a value of that
      -- destructor type moved in (whose old binding's scope then runs nothing),
      -- or (Agora #616, `LetdFn`) of the type of a struct's glue with an impl,
      -- rebound under its fields' glue with the impl's call next.
      -- A2-drop.3b: or it is a `Vec` of such values, drained at its end (Agora
      -- #782: whose elements may hold views, of roots bound before it: armed,
      -- `Ty.dtorViews`, it may record them up front, `HeldUp`, and takes no
      -- element that views more, `StmtT.push`)
      LetdTy f t E.ty τ → t.isStruct = true →
      t.hasFn = false → LetdFn P f t E.ty x s ∧ TakeOK P Γ r →
      -- A2-drop.2: the binding, armed, views what the value does, or more
      HeldUp Γ1 E H → StmtT P (setE Γ1 x (Entry.arm { E with ty := τ, held := H })) F s Δ →
      EndOK Δ x →
      -- A2-drop.3a: and is given no other value in its scope (`Stmt.assigns`):
      -- the old value's drop would run no destructor
      (hna : x ∉ s.assigns := by simp [Stmt.assigns]) →
      StmtT P Γ F (.letd x f r s) (exitScope x Δ)
  /-- A3.2: `locked_update a f`: the lock `a` (a live lock share) shares is
      taken, and its payload, a `t`, is checked out to `x` for the body:
      owned (an integer is a plain integer binding), holding nothing (the
      payload views nothing). `x`'s scope ends as a `letv`'s does; its value
      goes back into the block (`scopeL`).  The runtime runs the update in
      place, in the lock's own memory, so two more premises keep the model
      faithful to it: the body leaves `a`'s slot alone (it does not name
      `a`, and `a` is an owner or a borrowed parameter, whose share outlives
      the body; no closure changes a lock share by name, `NamesFree`), so the
      lock outlives the body; and `x` holds a `t` again at its end (it may
      be replaced, not left moved out), so it is what goes back.  A3.5: the
      same rule is a library's in-place change of its state (`withCell`), on
      a cell share a root holds (`Entry.lockOf`): an owner, or (A3.5's third
      cut) a borrowed parameter, a library's `in` handle. -/
  | withLock {Γ Δ : Ctx} {F : List Var} {a x : Var} {s : Stmt} {Ea : Entry} {t : Ty} :
      s.src = true → Γ x = none → x ∉ F → Γ a = some Ea → Ea.live = true → Ea.lockOf t →
      StmtT P (setE Γ x (lockE t)) F s Δ → EndOK Δ x →
      Ea.mode.isRoot = true → a ∉ s.vars → (∃ E, Δ x = some E ∧ E.live = true) →
      StmtT P Γ F (.withLock a x s) (exitScope x Δ)
  /-- A3.2: run time: `x`'s lock scope, typed as a `scope`. -/
  | scopeL {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var} {s : Stmt} :
      (∃ E, Γ x = some E ∧ E.mode ≠ .rootb ∧ E.ty = t) → x ∉ F → StmtT P Γ F s Δ → EndOK Δ x →
      StmtT P Γ F (.scopeL k t x s) (exitScope x Δ)
  /-- A2-elem (Agora #391): `y`'s value moves into `x` at index `i`: a push
      whose element then moves to index `i`.  The invariant does not see the
      order of an owner's elements (`MInv.perm`), so it is typed as the push
      `vec_push x y` is.  It is the give-back of an element handed over
      (`withElem`). -/
  | insert {Γ Δ : Ctx} {F : List Var} {x y : Var} {i : Expr} :
      ExprT Γ i → x ∉ F → StmtT P Γ F (.push x y) Δ → StmtT P Γ F (.insert x i y) Δ
  /-- A2-elem (Agora #391): element `i` of `v` handed over, as a call hands
      an element to a parameter it changes (`( f ( vec_at v i ) )`, read as
      `withElem v i x (call f x)`).  Element `i` moves out to `x`, which
      takes it as `vec_pop v` hands it over (`popE`: owned, holding what `v`
      holds); the body runs in `x`'s scope; then `x`'s value goes back in at
      index `i`, typed as `vec_push v x`, so `v` holds what was stored into
      the element (`ownHeld`).  The runtime passes a pointer to the element
      in place; the premises keep the model faithful to it:
      * `v` is an owner, not lent out (`RhsT.pop`), and what depends on it
        ends first (`kill .replace false v`): a borrow of `v`, its buffer or
        an element could read the element the body changes through `x`, and
        a closure that holds `v` by name could reach it; so no borrowed
        parameter may change it by name (`NoPin`), no destructor views it
        (`DtorSafe`), and `v` itself stays live (it depends on itself in no
        way).  (An `inout` parameter is no such root: its caller's frame may
        hold its argument by name, which `kill .replace` would end too.);
      * the body does not name `v` (`v ∉ s.vars`), so nothing in it reaches
        `v`, and the element goes back where it was;
      * `x` holds a `t` at the body's end (the push's premises). -/
  | withElem {Γ Γ1 Δ1 Δ : Ctx} {F : List Var} {v x : Var} {i : Expr} {s : Stmt} {Ev E : Entry} :
      s.src = true → Γ x = none → x ∉ F → Γ v = some Ev → Ev.mode = .own → ExprT Γ i →
      NoPin Γ v → DtorSafe Γ .replace false v →
      RhsT (kill .replace false v Γ) F (.pop v) E Γ1 → StmtT P (setE Γ1 x E) F s Δ1 →
      StmtT P Δ1 F (.push v x) Δ → EndOK Δ x → v ∉ s.vars →
      -- (A2-drop.3b: the element checked out owns no destructor value: its
      -- binding is no `letd`'s)
      E.ty.dtorFree = true →
      StmtT P Γ F (.withElem v i x s) (exitScope x Δ)
  /-- A2-envhand: a call through the package `c` of a method whose interface
      `σ` takes the receiver `inout` (at the bound `b`, and nothing else): the
      environment is handed over to the code (`Step.callcE`), which may change
      it as `σ` says (`Implements`).  It is typed as a call of the interface
      with `c` its `inout` argument, after what depends on `c` has ended, and
      with it ended again after (the environment moves out of `c` and back,
      as `withElem` takes an element: `kill .replace`).  The runtime passes
      the code a pointer to the environment in place; the premises keep the
      model faithful to it: `c` is an owner that may be replaced (`canDo`: an
      owner, or an `inout` parameter of that bound — never a borrow, so never
      what an `Arc` or a read guard lends), not lent out (`CallT`), changed by
      name by no borrowed parameter (`NoPin`) and viewed by no destructor
      (`DtorSafe`).  The receiver's class is at least `send`: a closure whose
      code changes its environment is not Sync, so no `Arc` holds one
      (`RhsT.arcNew`), and the one thread that owns it calls it.  First cut:
      the interface takes only the receiver, and its result borrows and holds
      nothing of it.
      Agora #609, the second case (`h10`): the interface takes the receiver
      OWNED, and the environment is handed over for good (`Step.callcD`): a
      consuming call, on an owned, live closure of the dropping class
      (`q.drops`; so of no class a share or a thread takes, which keeps
      `callcE_not_sync`) that holds nothing (`Ec.vdeps = []`).  It is what a
      closure's glue runs on its parameter (`ClosureGlueOK`), and any owner of
      such a closure may: the binding is moved out after (`CallT`'s `sink`
      argument), so its frame runs nothing.  The method returns no owned value
      (a choice of this cut, not a need of the proof). -/
  | callcE {Γ Γ1 Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {k : Stmt}
      {Ec E : Entry} {ms : List Nat} {q : Cross} {σ : Nat} {sig : Fn} {b : Eff}
      (h1 : k.src = true) (h2 : Γ x = none) (h3 : x ∉ F) (h4 : Γ c = some Ec)
      (h5 : Ec.ty.undtor = .fn ms q)
      (h6 : canDo Ec.mode .replace) (h7 : Cross.send.Le q ∨ q.drops = true) (h8 : ms[j]? = some σ)
      (h9 : P[σ]? = some sig)
      -- the interface takes the receiver `inout` (A2-envhand: the environment
      -- is handed over, and back), or (Agora #609) OWNED: the drop method of a
      -- closure whose environment holds destructor values, called on a closure
      -- that holds nothing the code cannot see (its glue's own parameter); the
      -- environment goes to the code for good
      (h10 : (sig.params = [(.inout b, .fn ms q)] ∧ Ec.ty = .fn ms q ∧ Cross.send.Le q) ∨
        (sig.params = [(.sink, Ec.ty)] ∧ Ec.vdeps = [] ∧ Ec.mode = .own ∧ Ec.live = true ∧
          q.drops = true ∧ sig.resOwn = false))
      (h11 : sig.lends = []) (h12 : sig.rholds = [])
      (h13 : sig.outHolds = []) (h14 : NoPin Γ c) (h15 : DtorSafe Γ .replace false c)
      (h16 : CallT P (kill .replace false c Γ) F σ [c] E Γ1)
      (h17 : StmtT P (kill .replace false c (setE Γ1 x E)) F k Δ)
      (h18 : EndOK Δ x) (h19 : ¬ ThruFn P σ)
      -- (A2-drop.3a: as `letcall`'s)
      (hdk : sig.resOwn = true → sig.resTy.holdsDtor = true → x ∈ k.movedFirst ∧ x ∉ k.assigns :=
        by dtor_head) :
      StmtT P Γ F (.callcE x c j [] k) (exitScope x Δ)
  | scopeD {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {s : Stmt} :
      -- (A2-drop.3a: of the destructor type `Ty.dtor f t`, whose destructor `f` is)
      -- (A2-drop.3b: or a `Vec` of such values; Agora #782: whose elements may
      -- hold views, the binding then `letd`'s and armed with them)
      (∃ E t, Γ x = some E ∧ E.mode = .own ∧ ScopeDTy f t E.ty ∧ E.ty.hasFn = false ∧
        DropFnOK P f t ∧ t.isStruct = true) → x ∉ F →
      StmtT P Γ F s Δ → EndOK Δ x →
      KeepOut Γ Δ s.spine → CtxWF Δ → NameWF Δ →
      -- A2-drop.2: the binding is `letd`'s when its type holds views (its
      -- destructor reads them)
      (∀ E, Δ x = some E → E.ty.holdsView = true → E.dbind = true) →
      -- Agora #633: ... and views nothing of its own (a panic's unwind moves
      -- it into its glue, a `sink` argument)
      DSelf Γ x →
      StmtT P Γ F (.scopeD x f s) (exitScope x Δ)
  /-- Agora #295: a change of a `Vec`'s elements through a borrow `x` (a
      push, a truncation or an element set), of an element type that holds
      no views. The change lands in the tree of one of the roots `x` reaches
      in memory, which the typing cannot tell apart: each of them undergoes
      `Edit.effAt` of its dependency (`.drop`, or `.realloc` for a push
      through a copy of a same-typed root's handle), and must allow it, not
      be lent out, not be what is stored, and end no view a destructor will
      read (`killThru`). `x` itself stays live: its node is changed in
      place. -/
  | editB {Γ Γ1 : Ctx} {F : List Var} {x : Var} {op : Edit} {Ex Ex1 : Entry} {t : Ty}
      {D : List Dep} :
      Γ x = some Ex → Ex.mode = .bor → Ex.live = true → Ex.ty = .vec t → t.holdsView = false →
      x ∉ F → EditArg Γ F op t D Γ1 → (∀ y, op.stored = some y → y ≠ x) →
      Γ1 x = some Ex1 → Ex1.live = true → memDeps Ex1.path ≠ [] →
      ThruOK Γ1 F op Ex.ty Ex1.path →
      -- (A2-drop.3b: a change that drops elements drops no destructor value)
      (op.drops = true → t.dtorFree = true) →
      StmtT P Γ F (.edit true x op) (setE (killThru op Ex.ty Ex1.path Γ1) x Ex1)
  /-- Agora #295: the same change through a borrow `x`, of an element type
      that holds views (and no closure): a push or an element set may store
      a view, valid through what the stored value depends on in memory
      (`memDeps D`, as `PushArg` takes it). The value lands in the tree of
      one of the memory roots of `x`'s path, which the typing cannot tell
      apart, so each of them holds that too, if its type holds views, as
      the owner of a `push` does (`holdThru`), and so does `x`, whose node
      holds the value. Each root ends what its effect ends, with views
      among its elements if its type holds views (`killThruV`: also the
      borrows of its whole handle, which do not hold what was stored), and
      must allow it as for `editB` (`ThruOK`), end no view a destructor
      will read by it, not be made by `letd` (a destructor binding gains no
      view), and not be a root of what is stored (`ThruV`). -/
  | editBV {Γ Γ1 : Ctx} {F : List Var} {x : Var} {op : Edit} {Ex Ex1 : Entry} {t : Ty}
      {D : List Dep} :
      Γ x = some Ex → Ex.mode = .bor → Ex.live = true → Ex.ty = .vec t → t.holdsView = true →
      t.hasFn = false → x ∉ F → EditArg Γ F op t D Γ1 → (∀ y, op.stored = some y → y ≠ x) →
      Γ1 x = some Ex1 → Ex1.live = true → memDeps Ex1.path ≠ [] →
      ThruOK Γ1 F op Ex.ty Ex1.path → ThruV Γ1 op Ex.ty Ex1.path (memDeps D) →
      (op.drops = true → t.dtorFree = true) →
      StmtT P Γ F (.edit true x op)
        (setE (holdThru (memDeps D) Ex1.path (killThruV op Ex.ty Ex1.path Γ1)) x
          { Ex1 with held := Ex1.held ++ memDeps D })

/-- A2-drop.3a: a function's parameters and result of a type that holds a
    destructor value (`Ty.holdsDtor`).  A `sink` one goes to its `letd`
    first thing, whose scope runs the destructor where the parameter's
    ends; neither it nor an `inout` one (its caller's value) is given
    another value (`Stmt.assigns`), whose drop would run none; and an owned
    result is set at most once on any path (`Stmt.asgMax`), so no earlier
    result is dropped.   A2-drop (Agora #611): an owned result of
    such a type is of a destructor type itself, or a `Vec` of such values,
    or (Agora #607) of such `Vec`s at any depth, with no views and no closure: the call's result frame (`resFrame`) runs
    its destructor, or drains it, on a panic in the callee. -/
def DtorParamsOK (P : Prog) (fn : Fn) : Prop :=
  (∀ i (h : i < fn.params.length), fn.params[i].1 = .sink → fn.params[i].2.holdsDtor = true →
    -- (Agora #632: or the function is an enum's glue, which matches on it)
    -- (Agora #609: or a closure's, which hands it to its drop method)
    (i ∈ fn.body.movedFirst ∨ ∃ f u, P[f]? = some fn ∧ (EnumGlueOK P f u ∨ ClosureGlueOK P f u)) ∧
      i ∉ fn.body.assigns) ∧
  (∀ i (h : i < fn.params.length) b, fn.params[i].1 = .inout b → fn.params[i].2.holdsDtor = true →
    i ∉ fn.body.assigns) ∧
  (fn.resOwn = true → fn.resTy.holdsDtor = true → fn.body.asgMax fn.params.length ≤ 1 ∧
    -- (the result's frame runs its destructor on a panic in the callee,
    -- `resFrame`: the result is of a destructor type itself, a struct holding
    -- one being one with its glue, or a `Vec` of such values, which the frame
    -- drains; it holds no views and no closure, so the frame is never armed)
    -- (Agora #607: or a `Vec` of such `Vec`s, at any depth)
    ∃ g t, ResDTy g t fn.resTy ∧ t.holdsView = false ∧
      t.hasFn = false ∧ DropFnOK P g t)

/-- A function is well-typed when its body is, from its own view of the
    parameters, and ends as its summary says: the result is set and borrows
    and holds only what `lends` and `rholds` name, every `inout` parameter
    is set again and holds only what `outHolds` names (an owned result or
    an `inout` parameter whose type holds no views holds nothing). -/
def FnOK (P : Prog) (fn : Fn) : Prop :=
  fn.body.src = true ∧ fn.params.length < fn.nvars ∧ (∀ v ∈ fn.body.vars, v < fn.nvars) ∧
  fn.resTy.ok = true ∧ (fn.resOwn = true → fn.resTy.owning = true) ∧
  (∀ pt ∈ fn.params, pt.2.ok = true ∧
    (pt.1 = .sink → pt.2.owning = true) ∧ (∀ b, pt.1 = .inout b → pt.2.owning = true)) ∧
  (∀ jk ∈ fn.lends, lendable fn jk.1 ∧ jk.2.isName = false) ∧
  (∀ jk ∈ fn.rholds, lendable fn jk.1 ∧ jk.2.isName = false) ∧
  (∀ o ∈ fn.outHolds, lendable fn o.2.1 ∧ o.2.2.isName = false) ∧
  (∀ jk ∈ fn.lends ++ fn.rholds, kindFits fn jk.1 jk.2) ∧ (∀ o ∈ fn.outHolds, kindFits fn o.2.1 o.2.2) ∧
  -- A2-drop.3a: parameters and a result of a type holding a destructor
  DtorParamsOK P fn ∧
  ∃ Δ, StmtT P (sigCtx fn) [] fn.body Δ ∧
    -- A2-drop.2: the body's own destructor bindings have ended, and no
    -- parameter or result runs a destructor
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    (∃ Er, Δ fn.params.length = some Er ∧ Er.live = true ∧ Er.ty = fn.resTy ∧
      Er.mode = resMode fn ∧
      (∀ d ∈ Er.path, (d.root, d.kind) ∈ fn.lends) ∧
      (∀ d ∈ Er.held, (d.root, d.kind) ∈ fn.rholds) ∧
      (fn.resOwn = true → fn.resTy.holdsView = false → Er.held = [])) ∧
    (∀ i (h : i < fn.params.length) b, fn.params[i].1 = .inout b →
      ∃ Ei, Δ i = some Ei ∧ Ei.live = true ∧ (∀ d ∈ Ei.held, (i, d.root, d.kind) ∈ fn.outHolds) ∧
        (fn.params[i].2.holdsView = false → Ei.held = []))

def ProgOK (P : Prog) : Prop := ∀ fn ∈ P, FnOK P fn

/-- A2-drop.3a: `FnOK`'s clause for a signature none of whose `sink` or
    `inout` parameters, nor its owned result, holds a destructor value. -/
theorem dtorParamsOK_of {P : Prog} {fn : Fn} (h : ∀ pt ∈ fn.params, pt.2.holdsDtor = false)
    (hr : fn.resOwn = true → fn.resTy.holdsDtor = false) : DtorParamsOK P fn := by
  refine ⟨fun i hi _ hd => ?_, fun i hi _ _ hd => ?_, fun ho hd => ?_⟩
  · rw [h _ (List.getElem_mem hi)] at hd; cases hd
  · rw [h _ (List.getElem_mem hi)] at hd; cases hd
  · rw [hr ho] at hd; cases hd

/-! ### Packages name code of their signature -/

/-- The mode an interface takes its receiver in: `inout` (A2-envhand: a call
    of it hands the environment over, `StmtT.callcE`), owned (Agora #609: a
    dropping closure's drop method, the environment handed over for good), or
    lent (any other first parameter: `StmtT.callc` asks `inp`). -/
def Fn.recvMode (sig : Fn) : PMode :=
  match sig.params.head? with
  | some (.inout b, _) => .inout b
  | some (.sink, _) => .sink   -- Agora #609: a drop method takes the environment owned
  | _ => .inp

theorem Fn.recvMode_of_head {sig : Fn} {pm : PMode} {t : Ty} (h : sig.params.head? = some (pm, t))
    (_hs : pm ≠ .sink := by simp) : sig.recvMode = pm := by
  unfold Fn.recvMode; rw [h]; cases pm <;> simp_all

/-- Code `f`, on an environment of type `te`, implements the interface `σ`:
    it takes the environment where the interface takes the receiver, in the
    interface's mode (lent, or, A2-envhand, `inout` at the interface's
    bound: the environment handed over, which the code may change as the
    interface says, and hold afterwards what its `outHolds` says the
    receiver holds), and the interface's other parameters as the interface
    does; it returns what the interface returns, and lends, holds and stores
    no more than the interface says.  A package with a method that changes
    its environment captures nothing by name.  (Agora #609: an interface that
    takes the receiver OWNED is implemented by code that takes the
    environment owned, `Fn.recvMode`; `StmtT.callcE`'s second case types a
    call of one, in the closure's glue.) -/
def Implements (P : Prog) (f : Nat) (te : Ty) (cs : List (Var × PMode × Ty)) (σ : Nat) : Prop :=
  ∃ fn sig, P[f]? = some fn ∧ P[σ]? = some sig ∧
    fn.params = (sig.recvMode, te) :: sig.params.tail ++ cs.map (·.2) ∧
    (sig.recvMode ≠ .inp → cs = []) ∧
    fn.resTy = sig.resTy ∧ fn.resOwn = sig.resOwn ∧ fn.lends ⊆ sig.lends ∧ fn.rholds ⊆ sig.rholds ∧
    fn.outHolds ⊆ sig.outHolds ∧
    -- a closure's code changes no elements through a borrow (Agora #295)
    ¬ ThruFn P f

/-- A package's code implements its interfaces, method by method. -/
def CodeOK (P : Prog) (fs : List Nat) (te : Ty) (ms : List Nat) (cs : List (Var × PMode × Ty)) : Prop :=
  fs.length = ms.length ∧ ∀ (j f σ : Nat), fs[j]? = some f → ms[j]? = some σ → Implements P f te cs σ

/-- Agora #610: the destructor of an `arc` or a `dead` block's destructor
    type is one the program checked: a destructor that takes the value lent,
    or a glue (`DropFnOK`).  The sweep marks such an `arc` block `dead`
    (`Mem.sweepD`), and `Step.reap` hands a `dead` block's payload to a frame
    that runs it.  `arc_new` of such a value asks it of its type
    (`Rhs.codeOK`).  (A lock's and a view's payload owns no destructor
    value, `Blk.DtorOK`.) -/
def DeadCodes (P : Prog) (B : Nat → Option Blk) : Prop :=
  ∀ k n f u kd o, B k = some ⟨Ty.nest n (.dtor f u), kd, o⟩ → (kd = .arc ∨ kd = .dead) → DropFnOK P f u

/-- No `arc` or `dead` block of a destructor type: nothing to check. -/
theorem DeadCodes.of_none {P : Prog} {B : Nat → Option Blk}
    (h : ∀ k bl, B k = some bl → (bl.kind = .arc ∨ bl.kind = .dead) → bl.ty.dtorFree = true) :
    DeadCodes P B := fun k _ _ _ _ _ hk hkd => absurd (h k _ hk hkd) (by simp)

/-- The check reads the blocks' types and kinds only. -/
theorem DeadCodes.of_types {P : Prog} {B B' : Nat → Option Blk} (h : DeadCodes P B)
    (hb : ∀ k bl', B' k = some bl' → (bl'.kind = .arc ∨ bl'.kind = .dead) → bl'.ty.dtorFree = false →
      ∃ bl, B k = some bl ∧ bl.ty = bl'.ty ∧ (bl.kind = .arc ∨ bl.kind = .dead)) :
    DeadCodes P B' := fun k n f u kd o hk hkd => by
  obtain ⟨⟨t, kd', o'⟩, h1, h2, h3⟩ := hb k _ hk hkd (by simp)
  simp only at h2 h3; subst h2
  exact h k n f u kd' o' h1 h3

/-- Every package in memory names code that implements its interfaces: the
    ones the slots hold, and (A3.5b) the ones the blocks hold, which may be
    closures (a Sync one in an `Arc`'s payload, a Send one in a lock's or a
    channel's), in what a block owns and in what its holders read. -/
def MemCodes (P : Prog) (m : Mem) : Prop :=
  (∀ x o V fs te ms e cs, m.st x = some ⟨o, some V⟩ → Sub (.pkg fs te ms e cs) V → CodeOK P fs te ms cs) ∧
  (∀ k bl fs te ms e cs, m.blk k = some bl →
    (Sub (.pkg fs te ms e cs) bl.tree ∨ Sub (.pkg fs te ms e cs) bl.rd) → CodeOK P fs te ms cs) ∧
  -- Agora #610: and the destructor of every block's destructor type is one
  -- the program checked (`DropFnOK`, what `StmtT.scopeD` asks of a
  -- destructor frame's): the sweep marks such an `arc` block `dead`, and
  -- `Step.reap` hands the payload to a frame that runs it.
  DeadCodes P m.blk

theorem MemCodes.dead {P : Prog} {m : Mem} (h : MemCodes P m) : DeadCodes P m.blk := h.2.2

def Rhs.codeOK (P : Prog) : Rhs → Prop
  | .pack fs te ms _ cs => CodeOK P fs te ms cs
  -- Agora #610: an `Arc` of a destructor value names a destructor the program
  -- checked; Agora #755: so does one of a drained `Vec` of them
  | .arcNew t _ => ∀ n f u, t = Ty.nest n (.dtor f u) → DropFnOK P f u
  | _ => True

/-- Agora #755: `arc_new` of a destructor value, or of a drained `Vec` of
    them, names the destructor the program checked. -/
theorem arcNew_codeOK {P : Prog} {n f : Nat} {u : Ty} (h : DropFnOK P f u) :
    ∀ n' f' u', Ty.nest n (.dtor f u) = Ty.nest n' (.dtor f' u') → DropFnOK P f' u' := by
  intro n' f' u' he
  obtain ⟨-, rfl, rfl⟩ := Ty.nest_dtor_inj he
  exact h

/-- Every package a statement makes names code of its signature (a closure
    literal's body is its code, checked with it). -/
def Stmt.codesOK (P : Prog) : Stmt → Prop
  | .seq a b => a.codesOK P ∧ b.codesOK P
  | .letv _ r s => r.codeOK P ∧ s.codesOK P
  | .letcall _ _ _ s => s.codesOK P
  | .assign _ r => r.codeOK P
  | .ite _ a b => a.codesOK P ∧ b.codesOK P
  | .while _ s => s.codesOK P
  | .scope _ s => s.codesOK P
  | .rbind _ s => s.codesOK P
  | .frozen _ s => s.codesOK P
  | .letrec _ _ s => s.codesOK P
  | .catchR _ _ s => s.codesOK P
  | .unpair _ _ _ s => s.codesOK P
  | .callc _ _ _ _ s => s.codesOK P
  | .letd _ _ r s => r.codeOK P ∧ s.codesOK P
  | .scopeD _ _ s => s.codesOK P
  | .withLock _ _ s => s.codesOK P
  | .scopeL _ _ _ s => s.codesOK P
  | .withElem _ _ _ s => s.codesOK P
  | .callcE _ _ _ _ s => s.codesOK P
  | _ => True

def ProgCodes (P : Prog) : Prop := ∀ fn ∈ P, fn.body.codesOK P

end A2
