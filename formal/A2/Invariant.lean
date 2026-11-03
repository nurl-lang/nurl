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

-- `ArcIn`, `ArcBlk`, `ShareFits` and `SharesIn` are in `Semantics.lean` (A3.2's
-- second cut: a lock scope gives back only a payload whose shares fit, `Giveable`).

/-- `SharesIn` over a memory's blocks. -/
def SharesOK (m : Mem) (τ : Ty) (T : Val) : Prop := SharesIn m.blk τ T

/-- A3.2: what a later store keeps of a block, as its holders see it: an
    `arc` block as it was, a `lock` block as a lock block of the same type
    (its payload, which no one reads, may have been checked out or back in). -/
def BlkKeep (bl bl' : Blk) : Prop := bl'.ty = bl.ty ∧ bl'.kind = bl.kind ∧ (bl.kind ≠ .lock → bl' = bl)

theorem BlkKeep.refl (bl : Blk) : BlkKeep bl bl := ⟨rfl, rfl, fun _ => rfl⟩

theorem BlkKeep.trans {b1 b2 b3 : Blk} (h1 : BlkKeep b1 b2) (h2 : BlkKeep b2 b3) : BlkKeep b1 b3 :=
  ⟨h2.1.trans h1.1, h2.2.1.trans h1.2.1, fun h => (h2.2.2 (by rw [h1.2.1]; exact h)).trans (h1.2.2 h)⟩

/-- What a kept block's holders read is what they read before. -/
theorem BlkKeep.rd {bl bl' : Blk} (h : BlkKeep bl bl') : bl'.rd = bl.rd := by
  obtain ⟨_, hk, ha⟩ := h
  cases hkd : bl.kind with
  | arc => rw [ha (by rw [hkd]; simp)]
  | view => rw [ha (by rw [hkd]; simp)]
  | lock =>
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
  rw [h', hk.2.2 (by simp)]

/-- ... (A3.3) and so is a view ... -/
theorem BlkLe.view {B B' : Nat → Option Blk} (hb : BlkLe B B') {k : Nat} {t : Ty} {p : Option Val}
    (h : B k = some ⟨t, .view, p⟩) : B' k = some ⟨t, .view, p⟩ := by
  obtain ⟨bl', h', hk⟩ := hb k _ h
  rw [h', hk.2.2 (by simp)]

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
  · exact SharesOK.of_noArc (hq.2.2 hs)
  · exact h.pkg hs

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
    slot reaches its block's payload. -/
def RootNode (m : Mem) (r : Var) (n : Val) : Prop :=
  (∃ T, m.st r = some ⟨true, some T⟩ ∧ Top n T) ∨
  (∃ v c, m.st r = some ⟨false, some v⟩ ∧ Top (.href c) v ∧ NodeAt m c n) ∨
  (∃ v d o l, m.st r = some ⟨false, some v⟩ ∧ Top (.view d o l) v ∧ DataAt m d n) ∨
  (∃ v k q, m.st r = some ⟨false, some v⟩ ∧ Top (.arc k q) v ∧ n = .arc k q)

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
  /-- A3.5: a cell share lent is no share (`lendOf`): a borrow of a library
      handle holds nothing of its state. -/
  | cell {t : Ty} {P H : List Dep} : ValOK m (.cell t) (.int 0) P H

section ValOK
variable {m : Mem} {v : Val} {P H : List Dep}

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
      and cell shares, whose owners are then the payload (A3's `CellInv`). -/
  blocks    : ∀ k bl, m.blk k = some bl → bl.ty.ok = true ∧ bl.ty.holdsView = false ∧
                (∀ p, bl.pay = some p → WFv bl.ty p ∧ SharesOK m bl.ty p)

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

/-- `f` is a destructor for values of type `t`: it takes one borrowed `t`,
    returns an integer and lends, holds and stores nothing. -/
def DtorOK (P : Prog) (f : Nat) (t : Ty) : Prop :=
  ∃ fn, P[f]? = some fn ∧ fn.params = [(.inp, t)] ∧ fn.resTy = .int ∧ fn.resOwn = false ∧
    fn.lends = [] ∧ fn.rholds = [] ∧ fn.outHolds = [] ∧
    -- a destructor changes no elements through a borrow (Agora #295)
    ¬ ThruFn P f

inductive StmtT (P : Prog) : Ctx → List Var → Stmt → Ctx → Prop
  | skip {Γ : Ctx} {F : List Var} : StmtT P Γ F .skip Γ
  | seq {Γ Γ1 Δ : Ctx} {F : List Var} {a b : Stmt} :
      b.src = true → StmtT P Γ F a Γ1 → StmtT P Γ1 F b Δ → StmtT P Γ F (.seq a b) Δ
  | letv {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {r : Rhs} {s : Stmt} {E : Entry} :
      s.src = true → Γ x = none → x ∉ F → RhsT Γ F r E Γ1 → StmtT P (setE Γ1 x E) F s Δ →
      EndOK Δ x → StmtT P Γ F (.letv x r s) (exitScope x Δ)
  | letcall {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {args : List Var} {s : Stmt}
      {E : Entry} :
      s.src = true → Γ x = none → x ∉ F → CallT P Γ F f args E Γ1 → StmtT P (setE Γ1 x E) F s Δ →
      EndOK Δ x → StmtT P Γ F (.letcall x f args s) (exitScope x Δ)
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
      -- A2-drop.2: a destructor binding gains no view
      (Ex.dbind = true → t.holdsView = false) →
      StmtT P Γ F (.push x y)
        (setE (kill .realloc t.holdsView x Γ1) x { Ex1 with held := Ex1.held ++ ownHeld true t D })
  | free {Γ : Ctx} {F : List Var} {x : Var} {E : Entry} {t : Ty} :
      Γ x = some E → E.live = true → E.mode = .own → E.ty = .vec t → x ∉ F → EndOK Γ x →
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
  | unpair {Γ Δ : Ctx} {F : List Var} {y x z : Var} {s : Stmt} {E : Entry} {a b : Ty} :
      -- (an `inout` struct that may be replaced is taken apart too: a field
      -- replaced in place is the struct taken apart and assigned again)
      s.src = true → Γ y = some E → E.live = true → canDo E.mode .replace → E.ty = .prod a b → y ∉ F →
      Γ x = none → Γ z = none → x ≠ z → x ∉ F → z ∉ F →
      StmtT P (setE (setE (setE (kill .replace false y Γ) y { E with live := false, dtor := false }) x (compE E a)) z
        (compE E b)) F s Δ →
      -- `y` is replaced, not ended: what borrows it by name, and a destructor
      -- that views it, are what replacing it ends
      NoPin Γ y → DtorSafe Γ .replace false y → EndOK Δ z → EndOK (exitScope z Δ) x →
      StmtT P Γ F (.unpair y x z s) (exitScope x (exitScope z Δ))
  | callc {Γ Γ1 Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var} {k : Stmt}
      {Ec E : Entry} {ms : List Nat} {q : Cross} {σ : Nat} {sig : Fn} :
      k.src = true → Γ x = none → x ∉ F → Γ c = some Ec → Ec.ty = .fn ms q → ms[j]? = some σ →
      P[σ]? = some sig → sig.params.head? = some (.inp, .fn ms q) → (∀ o ∈ sig.outHolds, o.2.1 ≠ 0) →
      CallT P Γ F σ (c :: zs) E Γ1 →
      -- no argument is a binding the package may change by name (it is
      -- handed to the code as an `inout` argument of its own)
      (∀ z ∈ zs, ∀ d ∈ Ec.vdeps, d.kind.bound ≠ .none → d.root ≠ z) →
      StmtT P (setE Γ1 x (recvRes c Ec E)) F k Δ →
      EndOK Δ x →
      -- the interface is not code that changes elements through a borrow
      -- (Agora #295; nor is the code that runs: `Implements`)
      ¬ ThruFn P σ → StmtT P Γ F (.callc x c j zs k) (exitScope x Δ)
  | catchR {Γ Δ : Ctx} {F : List Var} {x : Var} {m0 : Mem} {s : Stmt} :
      x ∉ F → StmtT P Γ (F ++ (List.range m0.nv).filter (· ≠ x)) s Δ →
      MInv (m0.set x ⟨false, some (.int 1)⟩) Δ →
      (RootbAnch Δ F) →
      KeepOut Γ Δ s.spine → DStay Γ Δ s.spine →
      StmtT P Γ F (.catchR x m0 s) Δ
  /-- A2-drop.1: a binding with a destructor, of a type that holds no views
      (its value is valid however the binding died). -/
  | letd {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {r : Rhs} {s : Stmt} {E : Entry}
      {H : List Dep} :
      s.src = true → Γ x = none → x ∉ F → RhsT Γ F r E Γ1 → E.mode = .own →
      E.ty.hasFn = false → DtorOK P f E.ty →
      -- A2-drop.2: the binding, armed, views what the value does, or more
      HeldUp Γ1 E H → StmtT P (setE Γ1 x (Entry.arm { E with held := H })) F s Δ →
      EndOK Δ x → StmtT P Γ F (.letd x f r s) (exitScope x Δ)
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
      a cell share an owner holds (`Entry.lockOf`). -/
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
      StmtT P Γ F (.withElem v i x s) (exitScope x Δ)
  | scopeD {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {s : Stmt} :
      (∃ E, Γ x = some E ∧ E.mode = .own ∧ E.ty.hasFn = false ∧ DtorOK P f E.ty) → x ∉ F →
      StmtT P Γ F s Δ → EndOK Δ x →
      KeepOut Γ Δ s.spine → CtxWF Δ → NameWF Δ →
      -- A2-drop.2: the binding is `letd`'s when its type holds views (its
      -- destructor reads them)
      (∀ E, Δ x = some E → E.ty.holdsView = true → E.dbind = true) →
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
      StmtT P Γ F (.edit true x op)
        (setE (holdThru (memDeps D) Ex1.path (killThruV op Ex.ty Ex1.path Γ1)) x
          { Ex1 with held := Ex1.held ++ memDeps D })

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

/-! ### Packages name code of their signature -/

/-- Code `f`, on an environment of type `te`, implements the interface `σ`:
    it takes the environment where the interface takes the receiver, and
    the interface's other parameters as the interface does; it returns what
    the interface returns, and lends, holds and stores no more than the
    interface says. -/
def Implements (P : Prog) (f : Nat) (te : Ty) (cs : List (Var × PMode × Ty)) (σ : Nat) : Prop :=
  ∃ fn sig, P[f]? = some fn ∧ P[σ]? = some sig ∧
    fn.params = (.inp, te) :: sig.params.tail ++ cs.map (·.2) ∧
    fn.resTy = sig.resTy ∧ fn.resOwn = sig.resOwn ∧ fn.lends ⊆ sig.lends ∧ fn.rholds ⊆ sig.rholds ∧
    fn.outHolds ⊆ sig.outHolds ∧
    -- a closure's code changes no elements through a borrow (Agora #295)
    ¬ ThruFn P f

/-- A package's code implements its interfaces, method by method. -/
def CodeOK (P : Prog) (fs : List Nat) (te : Ty) (ms : List Nat) (cs : List (Var × PMode × Ty)) : Prop :=
  fs.length = ms.length ∧ ∀ (j f σ : Nat), fs[j]? = some f → ms[j]? = some σ → Implements P f te cs σ

/-- Every package in memory names code that implements its interfaces: the
    ones the slots hold, and (A3.5b) the ones the blocks hold, which may be
    closures (a Sync one in an `Arc`'s payload, a Send one in a lock's or a
    channel's), in what a block owns and in what its holders read. -/
def MemCodes (P : Prog) (m : Mem) : Prop :=
  (∀ x o V fs te ms e cs, m.st x = some ⟨o, some V⟩ → Sub (.pkg fs te ms e cs) V → CodeOK P fs te ms cs) ∧
  ∀ k bl fs te ms e cs, m.blk k = some bl →
    (Sub (.pkg fs te ms e cs) bl.tree ∨ Sub (.pkg fs te ms e cs) bl.rd) → CodeOK P fs te ms cs

def Rhs.codeOK (P : Prog) : Rhs → Prop
  | .pack fs te ms _ cs => CodeOK P fs te ms cs
  | _ => True

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
  | _ => True

def ProgCodes (P : Prog) : Prop := ∀ fn ∈ P, fn.body.codesOK P

end A2
