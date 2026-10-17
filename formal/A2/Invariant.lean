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

/-- An owned tree of the given type: integers, views and owned element
    `Vec`s, never a bare borrow. -/
inductive WFv : Ty → Val → Prop
  | int {n : Nat} : WFv .int (.int n)
  | view {t : Ty} {d o l : Nat} : WFv (.slice t) (.view d o l)
  | node {t : Ty} {c d : Nat} {es : List Val} :
      (∀ e ∈ es, WFv t e) → WFv (.vec t) (.node t c d es)
  | pair {a b : Ty} {v w : Val} : WFv a v → WFv b w → WFv (.prod a b) (.pair v w)
  | inl {a b : Ty} {v : Val} : WFv a v → WFv (.sum a b) (.inl v)
  | inr {a b : Ty} {v : Val} : WFv b v → WFv (.sum a b) (.inr v)
  | pkg {f : Nat} {te a r : Ty} {v : Val} : WFv te v → WFv (.fn a r) (.pkg f te a r v)

/-- `v`, a view of element type `s`, is stored in tree `T` of type `τ`. -/
inductive ViewIn : Ty → Val → Ty → Val → Prop
  | here {s : Ty} {d o l : Nat} : ViewIn (.slice s) (.view d o l) s (.view d o l)
  | child {t t' : Ty} {c d : Nat} {es : List Val} {e : Val} {s : Ty} {v : Val} :
      e ∈ es → ViewIn t e s v → ViewIn (.vec t) (.node t' c d es) s v
  | fst {a b : Ty} {x y : Val} {s : Ty} {v : Val} : ViewIn a x s v → ViewIn (.prod a b) (.pair x y) s v
  | snd {a b : Ty} {x y : Val} {s : Ty} {v : Val} : ViewIn b y s v → ViewIn (.prod a b) (.pair x y) s v
  | inl {a b : Ty} {x : Val} {s : Ty} {v : Val} : ViewIn a x s v → ViewIn (.sum a b) (.inl x) s v
  | inr {a b : Ty} {x : Val} {s : Ty} {v : Val} : ViewIn b x s v → ViewIn (.sum a b) (.inr x) s v
  | pkg {f : Nat} {te a r : Ty} {x : Val} {s : Ty} {v : Val} :
      ViewIn te x s v → ViewIn (.fn a r) (.pkg f te a r x) s v

/-- `e` is a part of `t` one level down: an element of a `Vec`, or a field
    of a struct. -/
inductive Child : Val → Val → Prop
  | elem {e : Val} {ty : Ty} {c d : Nat} {es : List Val} : e ∈ es → Child e (.node ty c d es)
  | fst {v w : Val} : Child v (.pair v w)
  | snd {v w : Val} : Child w (.pair v w)
  | inl {v : Val} : Child v (.inl v)
  | inr {v : Val} : Child v (.inr v)
  | pkg {v : Val} {f : Nat} {te a r : Ty} : Child v (.pkg f te a r v)

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
  | pkg {n a : Val} {f : Nat} {te s r : Ty} : Top n a → Top n (.pkg f te s r a)

/-- A node a root's slot reaches directly: one at the top of its own tree, or
    one a handle it holds names (a borrowed struct is a bundle of handles). -/
def RootNode (m : Mem) (r : Var) (n : Val) : Prop :=
  (∃ T, m.st r = some ⟨true, some T⟩ ∧ Top n T) ∨
  (∃ v c, m.st r = some ⟨false, some v⟩ ∧ Top (.href c) v ∧ NodeAt m c n) ∨
  (∃ v d o l, m.st r = some ⟨false, some v⟩ ∧ Top (.view d o l) v ∧ DataAt m d n)

/-- The view `(d, o, l)` of element type `t` is valid through `dep`. -/
def ViewAt (m : Mem) (dep : Dep) (d o l : Nat) (t : Ty) : Prop :=
  ∃ n0 c es, RootNode m dep.root n0 ∧
    (dep.kind = .view ∧ Val.node t c d es = n0 ∨ dep.kind = .inner ∧ Below (.node t c d es) n0) ∧
    o + l ≤ es.length ∧ WFv (.vec t) (.node t c d es)

/-- Every view stored in `T` is valid through some dependency in `H`. -/
def ViewsOK (m : Mem) (τ : Ty) (T : Val) (H : List Dep) : Prop :=
  ∀ s v, ViewIn τ T s v → ∃ d o l, v = .view d o l ∧ ∃ dep ∈ H, ViewAt m dep d o l s

/-- Where a value reached through a dependency of a given kind lies: the
    root's node itself, or strictly inside it. -/
def Lands (k : Kind) (n n0 : Val) : Prop :=
  k = .self ∧ n = n0 ∨ k = .view ∧ n = n0 ∨ k = .inner ∧ Below n n0

/-- The borrowed `Vec` `c` of element type `t` is valid through `dep`. -/
def HrefAt (m : Mem) (dep : Dep) (c : Nat) (t : Ty) (H : List Dep) : Prop :=
  ∃ n0 d es, RootNode m dep.root n0 ∧ Lands dep.kind (.node t c d es) n0 ∧
    WFv (.vec t) (.node t c d es) ∧ ViewsOK m (.vec t) (.node t c d es) H

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
  | pkg {f : Nat} {te a r : Ty} {x : Val} {P H : List Dep} :
      ValOK m te x (P ++ H) H → ValOK m (.fn a r) (.pkg f te a r x) P H

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

theorem valOK_fn {a r : Ty} :
    ValOK m (.fn a r) v P H ↔ ∃ f te x, v = .pkg f te a r x ∧ ValOK m te x (P ++ H) H := by
  constructor
  · intro h; cases h with | pkg hx => exact ⟨_, _, _, rfl, hx⟩
  · rintro ⟨f, te, x, rfl, hx⟩; exact .pkg hx

/-- An integer depends on nothing. -/
theorem ValOK.int_any {m' : Mem} {P' H' : List Dep} (h : ValOK m .int v P H) : ValOK m' .int v P' H' := by
  cases h; exact .int

end ValOK

mutual
def Val.ids : Val → List Nat
  | .node _ c d es => c :: d :: idsL es
  | .pair v w => v.ids ++ w.ids
  | .inl v => v.ids
  | .inr v => v.ids
  | .pkg _ _ _ _ v => v.ids
  | _ => []
def idsL : List Val → List Nat
  | [] => []
  | e :: es => e.ids ++ idsL es
end

def OwnedAt (m : Mem) (x : Var) (t : Val) : Prop := m.st x = some ⟨true, some t⟩

/-- No view stored in a tree points into that same tree's buffers (a struct
    never views its own field). -/
def SelfFree (T : Val) : Prop :=
  ∀ d o l, Sub (.view d o l) T → ∀ u c es, ¬ Sub (.node u c d es) T

/-- One owner per allocation, every owned address is live, and no owned tree
    views itself. -/
structure HeapOK (m : Mem) : Prop where
  nodup : ∀ x t, OwnedAt m x t → t.ids.Nodup
  disj  : ∀ x y t u, x ≠ y → OwnedAt m x t → OwnedAt m y u → ∀ i ∈ t.ids, i ∉ u.ids
  alloc : ∀ x t, OwnedAt m x t → ∀ i ∈ t.ids, m.alloc i = true ∧ i < m.nid
  self  : ∀ x t, OwnedAt m x t → SelfFree t

/-- A binding's slot agrees with its entry. -/
def SlotOK (m : Mem) (E : Entry) (sl : Slot) : Prop :=
  sl.own = E.mode.ownSlot ∧
  (E.mode.ownSlot = true →
    E.ty.owning = true ∧ (∀ T, sl.val = some T → WFv E.ty T) ∧
    (E.live = true → ∃ T, sl.val = some T ∧ ViewsOK m E.ty T E.held)) ∧
  (E.mode.ownSlot = false →
    (E.live = true → ∃ v, sl.val = some v ∧ ValOK m E.ty v E.path E.held))

/-- The bindings of the run-time scopes a statement is inside of, innermost
    last: they are bound for as long as the statement runs. -/
def Stmt.spine : Stmt → List Var
  | .seq a _ => a.spine
  | .scope x s => x :: s.spine
  | .rbind p s => p :: s.spine
  | .frozen _ s => s.spine
  | .catchR _ _ s => s.spine
  | _ => []

/-- Nothing leaks: every live address is in a tree some binding owns. -/
def Covers (m : Mem) : Prop := ∀ i, m.alloc i = true → ∃ x t, OwnedAt m x t ∧ i ∈ t.ids

/-- A `recover` frame returns to its caller's store: every binding outside
    the frames it has opened (and its result `x`) is as the caller left it. -/
def CatchOK (m : Mem) : Stmt → Prop
  | .seq a _ => CatchOK m a
  | .scope _ s => CatchOK m s
  | .rbind _ s => CatchOK m s
  | .frozen _ s => CatchOK m s
  | .catchR x m0 s => (∀ v, v ∉ s.spine → v ≠ x → m.st v = m0.st v) ∧
      x ∉ s.spine ∧ m0.nv ≤ m.nv ∧ CatchOK m s
  | _ => True

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

/-- The invariant of a configuration running `s` in context `Γ`, with `F`
    lent out. -/
structure Inv (m : Mem) (Γ : Ctx) (F : List Var) (s : Stmt) : Prop extends MInv m Γ where
  nvS       : ∀ v ∈ s.vars, v < m.nv
  nvF       : ∀ v ∈ F, v < m.nv
  anch      : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ s.spine → ∀ r ∈ roots E.vdeps, r ∈ F
  spineNd   : s.spine.Nodup
  spineDom  : ∀ v ∈ s.spine, ∃ E, Γ v = some E
  catchOK   : CatchOK m s
  cover     : Covers m

/-! ### Typing of statements

Here, after the invariant, because the run-time form of a `recover` frame
is typed by the store it will return to. -/

/-- The bindings outside `sp` are those of `Δ`, with their modes and types,
    and a borrowed parameter's entry unchanged. -/
def KeepOut (Γ Δ : Ctx) (sp : List Var) : Prop :=
  (∀ v E, Γ v = some E → v ∉ sp →
    ∃ E', Δ v = some E' ∧ E'.mode = E.mode ∧ E'.ty = E.ty ∧ (E.mode = .rootb → E' = E)) ∧
  (∀ v E', Δ v = some E' → v ∉ sp ∧ ∃ E, Γ v = some E)

inductive StmtT (P : Prog) : Ctx → List Var → Stmt → Ctx → Prop
  | skip {Γ : Ctx} {F : List Var} : StmtT P Γ F .skip Γ
  | seq {Γ Γ1 Δ : Ctx} {F : List Var} {a b : Stmt} :
      b.src = true → StmtT P Γ F a Γ1 → StmtT P Γ1 F b Δ → StmtT P Γ F (.seq a b) Δ
  | letv {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {r : Rhs} {s : Stmt} {E : Entry} :
      s.src = true → Γ x = none → x ∉ F → RhsT Γ F r E Γ1 → StmtT P (setE Γ1 x E) F s Δ →
      StmtT P Γ F (.letv x r s) (exitScope x Δ)
  | letcall {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {args : List Var} {s : Stmt}
      {E : Entry} :
      s.src = true → Γ x = none → x ∉ F → CallT P Γ F f args E Γ1 → StmtT P (setE Γ1 x E) F s Δ →
      StmtT P Γ F (.letcall x f args s) (exitScope x Δ)
  | scope {Γ Δ : Ctx} {F : List Var} {x : Var} {s : Stmt} :
      (∃ E, Γ x = some E ∧ E.mode ≠ .rootb) → x ∉ F → StmtT P Γ F s Δ →
      StmtT P Γ F (.scope x s) (exitScope x Δ)
  | rbind {Γ Δ : Ctx} {F : List Var} {p : Var} {s : Stmt} {E : Entry} :
      Γ p = some E → E.mode = .rootb → E.live = true → (∀ r ∈ roots E.vdeps, r ∈ F) → p ∉ F →
      StmtT P Γ F s Δ → StmtT P Γ F (.rbind p s) (exitRoot p (E.path ++ E.held) Δ)
  | frozen {Γ Δ : Ctx} {F z : List Var} {s : Stmt} :
      StmtT P Γ (F ++ z) s Δ → StmtT P Γ F (.frozen z s) Δ
  | assign {Γ Γ1 : Ctx} {F : List Var} {x : Var} {r : Rhs} {Ex E : Entry} :
      Γ x = some Ex → x ∉ F →
      (Ex.mode = .own ∧ E.mode = .own ∨ Ex.mode = .inout .replace ∧ E.mode = .own ∨
        Ex.mode = .bor ∧ E.mode = .bor) →
      RhsT Γ F r E Γ1 → E.ty = Ex.ty → x ∉ roots E.vdeps → (Γ1 x).isSome →
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
      Γ1 x = some Ex1 → Ex1.live = true →
      StmtT P Γ F (.push x y)
        (setE (kill .realloc t.holdsView x Γ1) x { Ex1 with held := Ex1.held ++ D })
  | free {Γ : Ctx} {F : List Var} {x : Var} {E : Entry} {t : Ty} :
      Γ x = some E → E.live = true → E.mode = .own → E.ty = .vec t → x ∉ F →
      StmtT P Γ F (.free x) (setE (kill .replace false x Γ) x { E with live := false })
  | sub {Γ Γ0 Δ0 Δ : Ctx} {F : List Var} {s : Stmt} :
      Weaker Γ Γ0 → StmtT P Γ0 F s Δ0 → (Δ0 = Δ ∨ Weaker Δ0 Δ) → StmtT P Γ F s Δ
  | panic {Γ : Ctx} {F : List Var} : StmtT P Γ F .panic Γ
  | letrec {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {s : Stmt} {E : Entry} {fn : Fn} :
      s.src = true → Γ x = none → x ∉ F → P[f]? = some fn → fn.params = [] → fn.resTy = .int →
      fn.resOwn = false → CallT P Γ F f [] E Γ1 → StmtT P (setE Γ1 x E) F s Δ →
      StmtT P Γ F (.letrec x f s) (exitScope x Δ)
  | unpair {Γ Δ : Ctx} {F : List Var} {y x z : Var} {s : Stmt} {E : Entry} {a b : Ty} :
      s.src = true → Γ y = some E → E.live = true → E.mode = .own → E.ty = .prod a b → y ∉ F →
      Γ x = none → Γ z = none → x ≠ z → x ∉ F → z ∉ F →
      StmtT P (setE (setE (setE (kill .replace false y Γ) y { E with live := false }) x (compE E a)) z
        (compE E b)) F s Δ →
      StmtT P Γ F (.unpair y x z s) (exitScope x (exitScope z Δ))
  | catchR {Γ Δ : Ctx} {F : List Var} {x : Var} {m0 : Mem} {s : Stmt} :
      x ∉ F → StmtT P Γ (F ++ (List.range m0.nv).filter (· ≠ x)) s Δ →
      MInv (m0.set x ⟨false, some (.int 1)⟩) Δ →
      (∀ p E, Δ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F) →
      KeepOut Γ Δ s.spine →
      StmtT P Γ F (.catchR x m0 s) Δ

/-- A function is well-typed when its body is, from its own view of the
    parameters, and ends as its summary says: the result is set and borrows
    and holds only what `lends` and `rholds` name, every `inout` parameter
    is set again and holds only what `outHolds` names. -/
def FnOK (P : Prog) (fn : Fn) : Prop :=
  fn.body.src = true ∧ fn.params.length < fn.nvars ∧ (∀ v ∈ fn.body.vars, v < fn.nvars) ∧
  fn.resTy.ok = true ∧ (fn.resOwn = true → fn.resTy.owning = true) ∧
  (∀ pt ∈ fn.params, pt.2.ok = true ∧
    (pt.1 = .sink → pt.2.owning = true) ∧ (∀ b, pt.1 = .inout b → ∃ s, pt.2 = .vec s)) ∧
  (∀ jk ∈ fn.lends, lendable fn jk.1) ∧ (∀ jk ∈ fn.rholds, lendable fn jk.1) ∧
  (∀ o ∈ fn.outHolds, lendable fn o.2.1) ∧
  ∃ Δ, StmtT P (sigCtx fn) [] fn.body Δ ∧
    (∃ Er, Δ fn.params.length = some Er ∧ Er.live = true ∧ Er.ty = fn.resTy ∧
      Er.mode = resMode fn ∧
      (∀ d ∈ Er.path, (d.root, d.kind) ∈ fn.lends) ∧
      (∀ d ∈ Er.held, (d.root, d.kind) ∈ fn.rholds)) ∧
    (∀ i (h : i < fn.params.length) b, fn.params[i].1 = .inout b →
      ∃ Ei, Δ i = some Ei ∧ Ei.live = true ∧ ∀ d ∈ Ei.held, (i, d.root, d.kind) ∈ fn.outHolds)

def ProgOK (P : Prog) : Prop := ∀ fn ∈ P, FnOK P fn

end A2
