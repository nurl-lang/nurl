import A2.Semantics

/-
  A2 — the ownership rules as a type system.

  A context gives each binding in scope an entry: its type, how it holds its
  value (`Mode`), whether it may be used (`live`), and what its value
  depends on.  `path` says how a borrow reaches memory another binding owns;
  `held` says what the views inside the value (a `Vec` of views, §2.10)
  depend on.  Every dependency names a *root*: an owner, an `inout`
  parameter, or a borrowed (`in`) parameter — a borrow of a borrow
  borrows from the original owner (§6.2).

  The rules are flow-sensitive: a statement takes a context to a context.
  An effect on a root ends (makes not live) every entry that depends on it
  in a way that effect ends (`kill`): a move ends everything borrowed from
  the value (§2.1), a reallocation ends views (§2.10), dropping elements
  ends borrows of them (§6.2).  A binding moved on only some paths is
  simply not live afterwards (§2.1, maybe-moved); its drop flag decides at
  run time whether its scope's end releases it (§7.6).

  The bindings an enclosing call lent to a borrowed parameter are `frozen`
  (the list `F`): nothing in the callee can change them.
-/

namespace A2

inductive Mode where
  | own
  | inout (b : Eff)
  | rootb
  | bor
deriving DecidableEq, Repr

/-- Owners, `inout` parameters and borrowed parameters are roots: what is
    borrowed from them depends on them directly. -/
def Mode.isRoot : Mode → Bool
  | .bor => false
  | _ => true

structure Entry where
  ty   : Ty
  mode : Mode
  live : Bool
  path : List Dep
  held : List Dep
  /-- A2-drop.2: the binding may own a value whose destructor will run (it
      is armed), so what it holds views of must outlive it. A move disarms
      it. -/
  dtor : Bool
  /-- A2-drop.2: the binding was made by `letd`: it runs a destructor
      whenever it owns a value. It never changes. -/
  dbind : Bool
deriving DecidableEq, Repr

abbrev Ctx := Var → Option Entry

def Entry.deps (E : Entry) : List Dep := E.path ++ E.held

def Mode.ownSlot : Mode → Bool
  | .own => true
  | .inout _ => true
  | _ => false

/-- The dependencies that matter: an owner is reached through its own slot,
    so only what it holds counts. -/
def Entry.vdeps (E : Entry) : List Dep := (if E.mode.ownSlot then [] else E.path) ++ E.held

def roots (ds : List Dep) : List Var := ds.map (·.root)

/-- Composing a dependency (how `p` reaches a root, `a`) with how a value
    reaches `p` (`b`). -/
def comp : Kind → Kind → Kind
  | .self, k => k
  | k, .self => k
  | .view, .view => .view
  | .name b t, _ => .name b t
  | _, .name b t => .name b t
  | _, _ => .inner

/-- The handle of a borrowed slice parameter is a view. -/
def rootKind (t : Ty) (k : Kind) : Kind :=
  match t, k with
  | .slice _, .self => .view
  | .prod _ _, .self => .view
  | .sum _ _, .self => .view
  | .fn _, .self => .view
  | _, k => k

/-- What a value borrowed from `y` (whose entry is `E`) in way `k` depends
    on: a root lends directly, a borrow passes on what it borrows from. -/
def derive (y : Var) (E : Entry) (k : Kind) : List Dep :=
  if E.mode.isRoot then [⟨y, rootKind E.ty k⟩] else E.path.map (fun d => ⟨d.root, comp d.kind k⟩)

def setE (Γ : Ctx) (x : Var) (E : Entry) : Ctx := upd Γ x (some E)

/-- Does effect `e` on `x` (element type holding views: `hv`) end `E`?  An
    integer binding holds no memory, so nothing ends it. -/
def hits (e : Eff) (hv : Bool) (x : Var) (E : Entry) : Bool :=
  (E.ty != .int || E.mode == .rootb) && E.vdeps.any (fun d => d.root == x && e.kills hv d.kind)

def killE (e : Eff) (hv : Bool) (x : Var) (E : Entry) : Entry :=
  if hits e hv x E then { E with live := false } else E

def kill (e : Eff) (hv : Bool) (x : Var) (Γ : Ctx) : Ctx :=
  fun v => (Γ v).map (killE e hv x)

/-- `hits`, of what an entry depends on in memory: its views, not the
    names of closures it holds. A destructor reads views; a binding that
    runs one holds no closure (A2-drop.2). -/
def hitsMem (e : Eff) (hv : Bool) (x : Var) (E : Entry) : Bool :=
  (E.ty != .int || E.mode == .rootb) &&
    E.vdeps.any (fun d => d.root == x && !d.kind.isName && e.kills hv d.kind)

theorem hitsMem_of_hits {e : Eff} {hv : Bool} {x : Var} {E : Entry} (h : hits e hv x E = false) :
    hitsMem e hv x E = false := by
  unfold hits at h; unfold hitsMem
  simp only [Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true, beq_iff_eq, not_and,
    Bool.not_eq_true'] at h ⊢
  rcases h with h | h
  · exact Or.inl h
  · exact Or.inr fun d hd hr => h d hd hr.1

/-- A2-drop.2: effect `e` on `x` ends no view a binding that may run a
    destructor holds, live or not. A rule that kills through dependencies
    takes it, so a destructor never reads a view whose source ended
    (github#1380's rule, with the maybe-moved join). -/
def DtorSafe (Γ : Ctx) (e : Eff) (hv : Bool) (x : Var) : Prop :=
  ∀ v E, Γ v = some E → E.dtor = true → E.mode.ownSlot = true → hitsMem e hv x E = false

/-- What `replace` asks: no owner that may run a destructor views `x` in
    memory at all. -/
theorem DtorSafe.root_ne {Γ : Ctx} {hv : Bool} {x : Var} (h : DtorSafe Γ .replace hv x) {v : Var}
    {E : Entry} (hE : Γ v = some E) (hd : E.dtor = true) (hos : E.mode.ownSlot = true)
    (hn : E.ty ≠ .int ∨ E.mode = .rootb) {d : Dep} (hdd : d ∈ E.vdeps) (hnm : d.kind.isName = false) :
    d.root ≠ x := by
  intro hrx
  have h1 := h v E hE hd hos
  unfold hitsMem at h1
  have hg : (E.ty != .int || E.mode == .rootb) = true := by
    rcases hn with h | h <;> simp [h]
  rw [hg, Bool.true_and, List.any_eq_false] at h1
  have := h1 d hdd
  rw [hrx, hnm] at this
  cases hk : d.kind <;> simp_all [Eff.kills]

/-- A2-drop.2: no binding `letd` made, armed or not, views `x` in memory:
    what a scope's end asks, so that a moved-out destructor binding keeps
    no view of a binding that is gone (a join may arm it again). -/
def DbindSafe (Γ : Ctx) (x : Var) : Prop :=
  ∀ v E, Γ v = some E → E.dbind = true → E.mode.ownSlot = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
    ∀ d ∈ E.vdeps, d.kind.isName = false → d.root ≠ x

theorem DbindSafe.of_none {Γ : Ctx} (h : ∀ v E, Γ v = some E → E.dbind = false) (x : Var) :
    DbindSafe Γ x :=
  fun v E hE hd => by rw [h v E hE] at hd; cases hd

/-- A2-drop.2: every binding `letd` made in `Γ'`, outside `sp`, was one in
    `Γ`, and views no more in memory: a destructor binding gains no view. -/
def DKeep (Γ Γ' : Ctx) (sp : List Var) : Prop :=
  ∀ v E', Γ' v = some E' → E'.dbind = true → E'.mode.ownSlot = true → (E'.ty ≠ .int ∨ E'.mode = .rootb) →
    v ∉ sp → ∃ E, Γ v = some E ∧ E.dbind = true ∧ E.mode.ownSlot = true ∧
      (E.ty ≠ .int ∨ E.mode = .rootb) ∧ ∀ d ∈ E'.vdeps, d.kind.isName = false → d ∈ E.vdeps

theorem DKeep.refl (Γ : Ctx) (sp : List Var) : DKeep Γ Γ sp :=
  fun v E hv hd hos hn _ => ⟨E, hv, hd, hos, hn, fun _ h _ => h⟩

theorem DKeep.trans {Γ1 Γ2 Γ3 : Ctx} {sp sp' : List Var} (h1 : DKeep Γ1 Γ2 sp) (h2 : DKeep Γ2 Γ3 sp')
    (hsp : ∀ v, v ∉ sp' → v ∉ sp) : DKeep Γ1 Γ3 sp' := by
  intro v E3 hv hd hos hn hvs
  obtain ⟨E2, h2', hd2, hos2, hn2, hs2⟩ := h2 v E3 hv hd hos hn hvs
  obtain ⟨E1, h1', hd1, hos1, hn1, hs1⟩ := h1 v E2 h2' hd2 hos2 hn2 (hsp v hvs)
  exact ⟨E1, h1', hd1, hos1, hn1, fun d hdd hnm => hs1 d (hs2 d hdd hnm) hnm⟩

theorem DKeep.mono {Γ Γ' : Ctx} {sp sp' : List Var} (h : DKeep Γ Γ' sp) (hsp : ∀ v, v ∉ sp' → v ∉ sp) :
    DKeep Γ Γ' sp' := fun v E hv hd hos hn hvs => h v E hv hd hos hn (hsp v hvs)

/-- With no binding that runs a destructor, every effect is safe. -/
theorem DtorSafe.of_none {Γ : Ctx} (h : ∀ v E, Γ v = some E → E.dtor = false)
    (e : Eff) (hv : Bool) (x : Var) : DtorSafe Γ e hv x :=
  fun v E hE hd _ => by rw [h v E hE] at hd; cases hd

/-- The end of `x`'s scope: what borrows from it ends, and it is gone. -/
def exitScope (x : Var) (Γ : Ctx) : Ctx := upd (kill .replace false x Γ) x none

/-- At the end of a borrowed parameter `p`'s scope, what depends on `p`
    depends on what `p` borrowed (`D`). -/
def reroot (p : Var) (D : List Dep) (ds : List Dep) : List Dep :=
  ds.flatMap (fun d => if d.root = p then D.map (fun d' => ⟨d'.root, comp d'.kind d.kind⟩) else [d])

def rerootE (p : Var) (D : List Dep) (E : Entry) : Entry :=
  { E with path := reroot p D E.path, held := reroot p D E.held }

@[simp] theorem rerootE_dtor (p : Var) (D : List Dep) (E : Entry) : (rerootE p D E).dtor = E.dtor := rfl
@[simp] theorem rerootE_dbind (p : Var) (D : List Dep) (E : Entry) : (rerootE p D E).dbind = E.dbind := rfl

def exitRoot (p : Var) (D : List Dep) (Γ : Ctx) : Ctx :=
  upd (fun v => (Γ v).map (rerootE p D)) p none

/-- An entry that stays as it is for the whole scope of its binding: a
    borrowed parameter, or an `inout` one that holds no views and is never
    replaced (nothing the body may do to it changes what it depends on, and
    it lives as long as the call). -/
def Entry.fixed (E : Entry) : Prop :=
  E.mode = .rootb ∨ ∃ b, E.mode = .inout b ∧ b ≠ .replace ∧ E.ty.holdsView = false

@[simp] theorem Entry.fixed_def (E : Entry) :
    E.fixed ↔ (E.mode = .rootb ∨ ∃ b, E.mode = .inout b ∧ b ≠ .replace ∧ E.ty.holdsView = false) := Iff.rfl

/-- `E'` says no more than `E`: it may be dead where `E` is live, and depend
    on more.  A fixed entry stays as it is; an owner's `path` says nothing
    (an owner is reached through its own slot). -/
structure EntryWeaker (E E' : Entry) : Prop where
  ty    : E'.ty = E.ty
  mode  : E'.mode = E.mode
  fixed : E.fixed → E' = E
  live  : E'.live = true → E.live = true ∧ (E.mode.ownSlot = false → E.path ⊆ E'.path) ∧
            E.held ⊆ E'.held
  /-- A2-drop.2: a binding that may run a destructor stays one and keeps
      what it views, live or not: after a join where one path moved it,
      its slot may still own its value on the other. -/
  dtor  : E.dtor = true → E'.dtor = true ∧ E.held ⊆ E'.held
  /-- ... it is the same binding, made by `letd` or not; only one made by
      `letd` may be armed again (the maybe-moved join), and what it views
      is the value `letd` gave it, so no weakening adds to it. -/
  dbind : E'.dbind = E.dbind
  raise : E'.dtor = true → E.dtor = true ∨ E.dbind = true
  dheld : E.dbind = true → E'.held = E.held

/-- A context's live entries depend only on roots it has.  (An integer's
    dependencies say nothing: it holds no memory.)  A2-drop.2: so does, in
    memory, an owner that may run a destructor, live or not: its views are
    what the destructor will read. -/
structure CtxWF (Γ : Ctx) : Prop where
  live : ∀ v E, Γ v = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → ∀ r ∈ roots E.vdeps,
    ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true
  dtor : ∀ v E, Γ v = some E → E.dbind = true → E.mode.ownSlot = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
    ∀ d ∈ E.vdeps, d.kind.isName = false → ∃ Er, Γ d.root = some Er ∧ Er.mode.isRoot = true
  /-- ... and only a binding `letd` made may run one. -/
  arm  : ∀ v E, Γ v = some E → E.dtor = true → E.dbind = true

instance {Γ : Ctx} : CoeFun (CtxWF Γ) (fun _ => ∀ v E, Γ v = some E → E.live = true →
    (E.ty ≠ .int ∨ E.mode = .rootb) → ∀ r ∈ roots E.vdeps, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) :=
  ⟨CtxWF.live⟩

/-- May a binding in this mode undergo effect `e`? -/
def canDo (m : Mode) (e : Eff) : Prop :=
  m = .own ∨ ∃ b, m = .inout b ∧ e.le b

/-- A binding that may undergo an effect owns its slot. -/
theorem canDo.ownSlot {m : Mode} {e : Eff} (h : canDo m e) : m.ownSlot = true := by
  rcases h with h | ⟨b, h, _⟩ <;> rw [h] <;> rfl

theorem canDo_replace_cases {m : Mode} (h : canDo m .replace) : m = .own ∨ m = .inout .replace := by
  rcases h with h | ⟨b, h, hle⟩
  · exact Or.inl h
  · right; rw [h]; cases b <;> simp_all [Eff.le, Eff.rank]

theorem Mode.isRoot_of_ownSlot {m : Mode} (h : m.ownSlot = true) : m.isRoot = true := by
  cases m <;> simp_all [Mode.ownSlot, Mode.isRoot]

/-- What `D` holds by name names bindings that are still bound and live
    (a binding replaced, moved or gone ends what holds it by name), of the
    type the capturing closure's code expects (one that holds no views: a
    binding that holds views is captured by handle), that own their slot,
    and that allow what the closure may do to them.  Such a binding holds
    nothing (its type holds no views), so no change to another binding
    ends it. -/
def DepsNamed (Γ : Ctx) (D : List Dep) : Prop :=
  ∀ d ∈ D, ∀ b t, d.kind = .name b t →
    ∃ Er, Γ d.root = some Er ∧ Er.live = true ∧ Er.held = [] ∧ Er.ty = t ∧ Er.mode.ownSlot = true ∧
      (b = .none ∨ b ≠ .replace ∧ canDo Er.mode b) ∧ t.holdsView = false

def NameOK (Γ : Ctx) (E : Entry) : Prop := DepsNamed Γ E.vdeps

def NameWF (Γ : Ctx) : Prop :=
  ∀ v E, Γ v = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → NameOK Γ E

def Weaker (Γ Γ' : Ctx) : Prop :=
  (∀ v, (Γ v = none ↔ Γ' v = none) ∧
    ∀ E E', Γ v = some E → Γ' v = some E' → EntryWeaker E E') ∧ CtxWF Γ' ∧ NameWF Γ'

/-- `x` is not pinned: no borrowed parameter holds a closure that may
    change `x` by name.  A rule that replaces `x` (moves it, assigns it,
    frees it, ends its scope) requires it: such a closure would otherwise
    keep changing a binding that is gone. -/
def NoPin (Γ : Ctx) (x : Var) : Prop :=
  ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none → d.root ≠ x

/-- What ending or replacing `x` asks of the context it happens in: no
    borrowed parameter changes `x` by name (`NoPin`), and no binding that
    may run a destructor views it (`DtorSafe`, A2-drop.2). -/
def EndOK (Γ : Ctx) (x : Var) : Prop := NoPin Γ x ∧ DtorSafe Γ .replace false x ∧ DbindSafe Γ x

def intE : Entry := ⟨.int, .bor, true, [], [], false, false⟩

inductive ExprT (Γ : Ctx) : Expr → Prop
  | lit {n : Nat} : ExprT Γ (.lit n)
  | var {x : Var} {E : Entry} : Γ x = some E → E.live = true → E.ty = .int → ExprT Γ (.var x)
  | add {a b : Expr} : ExprT Γ a → ExprT Γ b → ExprT Γ (.add a b)
  | lt {a b : Expr} : ExprT Γ a → ExprT Γ b → ExprT Γ (.lt a b)
  | len {x : Var} {E : Entry} {t : Ty} :
      Γ x = some E → E.live = true → E.ty = .vec t → ExprT Γ (.len x)
  | slen {x : Var} {E : Entry} {t : Ty} :
      Γ x = some E → E.live = true → E.ty = .slice t → ExprT Γ (.slen x)
  | isl {x : Var} {E : Entry} {a b : Ty} :
      Γ x = some E → E.live = true → E.ty = .sum a b → ExprT Γ (.isl x)

/-- An element read out of `y` (entry `E`), of type `t`: an integer is
    copied, a stored view is copied with what it depends on, an element
    `Vec` is lent. -/
def elemE (y : Var) (E : Entry) : Ty → Entry
  | .int => intE
  | .slice s => ⟨.slice s, .bor, true, E.held, E.held, false, false⟩
  | .vec s => ⟨.vec s, .bor, true, derive y E .inner, E.held, false, false⟩
  | .prod a b => ⟨.prod a b, .bor, true, derive y E .inner, E.held, false, false⟩
  | .sum a b => ⟨.sum a b, .bor, true, derive y E .inner, E.held, false, false⟩
  | .fn ms => ⟨.fn ms, .bor, true, derive y E .inner, E.held, false, false⟩

/-- An element moved out of `y` by `vec_pop`: an element `Vec` or struct is
    owned. -/
def popE (y : Var) (E : Entry) : Ty → Entry
  | .vec s => ⟨.vec s, .own, true, [], E.held, false, false⟩
  | .prod a b => ⟨.prod a b, .own, true, [], E.held, false, false⟩
  | .sum a b => ⟨.sum a b, .own, true, [], E.held, false, false⟩
  | .fn ms => ⟨.fn ms, .own, true, [], E.held, false, false⟩
  | t => elemE y E t

/-- What a field of the struct `y` (entry `E`) lends: what is inside an
    owned struct depends on its owner, what is inside a borrowed one on
    what that borrows. -/
def projDeps (y : Var) (E : Entry) : List Dep :=
  if E.mode.ownSlot then [⟨y, .inner⟩] else if E.mode = .rootb then [⟨y, .view⟩] else E.path

/-- A field read: an integer is copied, anything else is lent (a stored view
    is copied with what it depends on). -/
def projE (y : Var) (E : Entry) : Ty → Entry
  | .int => intE
  | t => ⟨t, .bor, true, projDeps y E ++ E.held, E.held, false, false⟩

/-- What an owned value holds: nothing, if its type holds no views (no view
    and no closure lies inside it, so what it was made from says nothing). -/
def ownHeld (o : Bool) (t : Ty) (H : List Dep) : List Dep := if o && !t.holdsView then [] else H

/-- A field moved out of a struct that is taken apart. -/
def compE (E : Entry) : Ty → Entry
  | .int => intE
  | .slice s => ⟨.slice s, .bor, true, E.held, E.held, false, false⟩
  | t => ⟨t, .own, true, [], ownHeld true t E.held, false, false⟩

/-! The entries the rules build run no destructor (A2-drop.2: only `letd`
    makes one that does). -/
@[simp] theorem intE_dtor : intE.dtor = false := rfl
@[simp] theorem elemE_dtor (y : Var) (E : Entry) (t : Ty) : (elemE y E t).dtor = false := by
  cases t <;> rfl
@[simp] theorem popE_dtor (y : Var) (E : Entry) (t : Ty) : (popE y E t).dtor = false := by
  cases t <;> simp [popE]
@[simp] theorem projE_dtor (y : Var) (E : Entry) (t : Ty) : (projE y E t).dtor = false := by
  cases t <;> rfl
@[simp] theorem compE_dtor (E : Entry) (t : Ty) : (compE E t).dtor = false := by
  cases t <;> rfl
@[simp] theorem intE_dbind : intE.dbind = false := rfl
@[simp] theorem elemE_dbind (y : Var) (E : Entry) (t : Ty) : (elemE y E t).dbind = false := by
  cases t <;> rfl
@[simp] theorem popE_dbind (y : Var) (E : Entry) (t : Ty) : (popE y E t).dbind = false := by
  cases t <;> simp [popE]
@[simp] theorem projE_dbind (y : Var) (E : Entry) (t : Ty) : (projE y E t).dbind = false := by
  cases t <;> rfl
@[simp] theorem compE_dbind (E : Entry) (t : Ty) : (compE E t).dbind = false := by
  cases t <;> rfl

/-- The element type of a `Vec`. -/
def Ty.elem : Ty → Ty
  | .vec t => t
  | t => t

/-- Handing `y` to `vec_push`: an element `Vec` moves, anything else is
    copied with what it depends on (`D`, which the container then holds). -/
inductive PushArg (Γ : Ctx) (F : List Var) (y : Var) (E : Entry) : Ty → List Dep → Ctx → Prop
  | move {t : Ty} :
      t.owning = true → E.mode = .own → y ∉ F → NoPin Γ y → DtorSafe Γ .replace false y →
      PushArg Γ F y E t E.held (setE (kill .replace false y Γ) y { E with live := false, dtor := false })
  | int : PushArg Γ F y E .int [] Γ
  | slice {s : Ty} :
      (E.mode = .bor ∨ E.mode = .rootb) →
      PushArg Γ F y E (.slice s) (derive y E .self ++ E.held) Γ

def argE (Γ : Ctx) (a : Var) : Entry := (Γ a).getD intE

/-- What a closure literal's captures by name add to what it holds: each
    binding, by name.  (What such a binding holds needs no tracking: it
    holds no views, and it is read only through its own slot.) -/
def capDeps (cs : List (Var × PMode × Ty)) : List Dep :=
  cs.map (fun c => ⟨c.1, .name c.2.1.bound c.2.2⟩)

/-- A closure literal's captures by name: distinct live bindings that own
    their slot (a borrowed parameter is captured by handle instead: it
    stays as it is for its whole scope), of the recorded types, each read
    (`inp`) or changed (`inout b`), of a type that holds no views.  One it
    only reads is at most read by name by what its environment holds.  One
    it may change is owned (or an `inout` parameter that allows `b`), not
    lent out, a `Vec` whose elements hold no views, changed at most by
    dropping elements, and reached from nothing else the closure holds
    (§2.11). -/
def CapsOK (Γ : Ctx) (F : List Var) (D : List Dep) (cs : List (Var × PMode × Ty)) : Prop :=
  (cs.map (·.1)).Nodup ∧
  ∀ c ∈ cs, ∃ Ev, Γ c.1 = some Ev ∧ Ev.live = true ∧ Ev.held = [] ∧ Ev.ty = c.2.2 ∧ Ev.mode.ownSlot = true ∧
    c.2.2.holdsView = false ∧
    (c.2.1 = .inp ∧ (∀ d ∈ D, d.root = c.1 → d.kind.isName = true → d.kind.bound = .none) ∨
      ∃ b s, c.2.1 = .inout b ∧ b ≠ .none ∧ b ≠ .replace ∧ canDo Ev.mode b ∧ c.1 ∉ F ∧
       c.2.2 = .vec s ∧ s.holdsView = false ∧ (∀ d ∈ D, d.root ≠ c.1) ∧
       ∀ c' ∈ cs, ∀ d ∈ (argE Γ c'.1).held, d.root ≠ c.1)

inductive RhsT (Γ : Ctx) (F : List Var) : Rhs → Entry → Ctx → Prop
  | expr {e : Expr} : ExprT Γ e → RhsT Γ F (.expr e) intE Γ
  | new {t : Ty} : t.ok = true → RhsT Γ F (.new t) ⟨.vec t, .own, true, [], [], false, false⟩ Γ
  | moveOwn {y : Var} {E : Entry} :
      Γ y = some E → E.live = true → E.mode = .own → y ∉ F → NoPin Γ y → DtorSafe Γ .replace false y →
      RhsT Γ F (.var y) ⟨E.ty, .own, true, [], E.held, false, false⟩
        (setE (kill .replace false y Γ) y { E with live := false, dtor := false })
  | copyRoot {y : Var} {E : Entry} :
      Γ y = some E → E.live = true → E.mode = .rootb →
      RhsT Γ F (.var y) ⟨E.ty, .bor, true, derive y E .self, E.held, false, false⟩ Γ
  | copyBor {y : Var} {E : Entry} :
      Γ y = some E → E.live = true → E.mode = .bor →
      RhsT Γ F (.var y) { E with dtor := false, dbind := false } Γ
  | borrow {y : Var} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .vec t →
      RhsT Γ F (.borrow y) ⟨E.ty, .bor, true, derive y E .self, E.held, false, false⟩ Γ
  | at {y : Var} {i : Expr} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .vec t → ExprT Γ i →
      RhsT Γ F (.at y i) (elemE y E t) Γ
  | view {y : Var} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .vec t → t.holdsView = false →
      RhsT Γ F (.view y) ⟨.slice t, .bor, true, derive y E .view, E.held, false, false⟩ Γ
  | sat {y : Var} {i : Expr} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .slice t → ExprT Γ i →
      RhsT Γ F (.sat y i) (elemE y E t) Γ
  | pop {y : Var} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .vec t → canDo E.mode .drop → y ∉ F →
      DtorSafe Γ .drop t.holdsView y →
      RhsT Γ F (.pop y) (popE y E t) (kill .drop t.holdsView y Γ)
  | pair {y z : Var} {Ey Ez : Entry} {Γ1 Γ2 : Ctx} {Dy Dz : List Dep} :
      Γ y = some Ey → Ey.live = true → PushArg Γ F y Ey Ey.ty Dy Γ1 →
      Γ1 z = some Ez → Ez.live = true → PushArg Γ1 F z Ez Ez.ty Dz Γ2 →
      (Ez.mode.ownSlot = true → z ∉ roots Dy) →
      RhsT Γ F (.pair y z) ⟨.prod Ey.ty Ez.ty, .own, true, [], Dy ++ Dz, false, false⟩ Γ2
  | fst {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.ty = .prod a b → RhsT Γ F (.fst y) (projE y E a) Γ
  | snd {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.ty = .prod a b → RhsT Γ F (.snd y) (projE y E b) Γ
  | inl {y : Var} {b : Ty} {Ey : Entry} {Γ1 : Ctx} {D : List Dep} :
      Γ y = some Ey → Ey.live = true → PushArg Γ F y Ey Ey.ty D Γ1 → b.ok = true →
      RhsT Γ F (.inl y b) ⟨.sum Ey.ty b, .own, true, [], D, false, false⟩ Γ1
  | inr {a : Ty} {y : Var} {Ey : Entry} {Γ1 : Ctx} {D : List Dep} :
      Γ y = some Ey → Ey.live = true → PushArg Γ F y Ey Ey.ty D Γ1 → a.ok = true →
      RhsT Γ F (.inr a y) ⟨.sum a Ey.ty, .own, true, [], D, false, false⟩ Γ1
  | getl {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.ty = .sum a b → RhsT Γ F (.getl y) (projE y E a) Γ
  | getr {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.ty = .sum a b → RhsT Γ F (.getr y) (projE y E b) Γ
  | takel {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.mode = .own → E.ty = .sum a b → y ∉ F → NoPin Γ y →
      DtorSafe Γ .replace false y →
      RhsT Γ F (.takel y) (compE E a) (setE (kill .replace false y Γ) y { E with live := false, dtor := false })
  | taker {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.mode = .own → E.ty = .sum a b → y ∉ F → NoPin Γ y →
      DtorSafe Γ .replace false y →
      RhsT Γ F (.taker y) (compE E b) (setE (kill .replace false y Γ) y { E with live := false, dtor := false })
  | pack {fs : List Nat} {te : Ty} {ms : List Nat} {y : Var} {cs : List (Var × PMode × Ty)} {Ey : Entry}
      {Γ1 : Ctx} {D : List Dep} :
      Γ y = some Ey → Ey.live = true → Ey.ty = te → PushArg Γ F y Ey te D Γ1 → CapsOK Γ1 F D cs →
      -- (a closure the environment holds that may change a binding by name:
      -- running this package changes it, its name is among what it holds)
      RhsT Γ F (.pack fs te ms y cs) ⟨.fn ms, .own, true, [], D ++ capDeps cs, false, false⟩ Γ1

/-! ### Calls -/

/-- A2-drop.2: a right-hand side makes a value no binding has made its own
    yet: it runs no destructor (only `letd` arms a binding). -/
theorem RhsT.dtor_false {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (h : RhsT Γ F r E Γ1) :
    E.dtor = false ∧ E.dbind = false := by
  cases h <;> simp

/-- What the summary pair `(j, k)` means at this call.  An integer argument
    lends nothing. -/
def argDeps (Γ : Ctx) (args : List Var) (jk : Nat × Kind) : List Dep :=
  if (argE Γ (args.getD jk.1 0)).ty = .int then []
  else derive (args.getD jk.1 0) (argE Γ (args.getD jk.1 0)) jk.2

/-- Every dependency of every kind on the given roots. -/
def allKinds (rs : List Var) : List Dep :=
  rs.flatMap (fun r => [⟨r, .self⟩, ⟨r, .inner⟩, ⟨r, .view⟩])


/-- The dependencies on memory among `ds`, and those by name. -/
def memDeps (ds : List Dep) : List Dep := ds.filter (fun d => !d.kind.isName)
def nameDeps (ds : List Dep) : List Dep := ds.filter (fun d => d.kind.isName)

/-- What the arguments hold by name: the bindings the closures among them
    (or inside them) read or change each time they run.  An integer holds
    nothing. -/
def argNames (Γ : Ctx) (args : List Var) : List Dep :=
  args.flatMap (fun a => if (argE Γ a).ty = .int then [] else nameDeps (argE Γ a).vdeps)

/-- ... those a closure may change. -/
def mutNames (Γ : Ctx) (args : List Var) : List Dep :=
  (argNames Γ args).filter (fun d => d.kind.bound != .none)

/-- What a list of dependencies holds but by a name that may change its
    binding: views, and names that only read. -/
def readers (H : List Dep) : List Dep := H.filter (fun d => d.kind.bound == .none)

theorem mem_readers {H : List Dep} {d : Dep} : d ∈ readers H ↔ d ∈ H ∧ d.kind.bound = .none := by
  simp [readers]

theorem readers_sub (H : List Dep) : readers H ⊆ H := fun _ hd => (mem_readers.mp hd).1

theorem readers_mono {H H' : List Dep} (h : H ⊆ H') : readers H ⊆ readers H' := fun _ hd =>
  mem_readers.mpr ⟨h (mem_readers.mp hd).1, (mem_readers.mp hd).2⟩

theorem comp_bound_none {k k' : Kind} (h1 : k.bound = .none) (h2 : k'.bound = .none) :
    (comp k k').bound = .none := by
  cases k <;> cases k' <;> simp_all [comp, Kind.bound]

/-- Dropping a borrowed binding that changes nothing by name keeps what only
    reads among what only reads. -/
theorem reroot_readers {p : Var} {D H : List Dep} (hD : ∀ d ∈ D, d.kind.bound = .none) :
    reroot p D (readers H) ⊆ readers (reroot p D H) := by
  intro d hd
  unfold reroot at hd
  obtain ⟨d0, hd0, hdd⟩ := List.mem_flatMap.mp hd
  obtain ⟨hd0H, hb0⟩ := mem_readers.mp hd0
  refine mem_readers.mpr ⟨List.mem_flatMap.mpr ⟨d0, hd0H, hdd⟩, ?_⟩
  split at hdd
  · obtain ⟨d', hd', rfl⟩ := List.mem_map.mp hdd
    exact comp_bound_none (hD d' hd') hb0
  · simp only [List.mem_singleton] at hdd; rw [hdd]; exact hb0

/-- A package's own writer captures: what its code may change by name, and
    what it is handed as `inout` arguments of their own when it is called. -/
def capRootsW (cs : List (Var × PMode × Ty)) : List Var :=
  (cs.filter (fun c => c.2.1 != .inp)).map (·.1)

/-- The package's own change of a capture, by name. -/
def ownWriter (cs : List (Var × PMode × Ty)) (d : Dep) : Bool :=
  d.kind.bound != .none && (capRootsW cs).contains d.root

/-- What a package's environment is valid through: everything the package
    holds but its own writer captures' names (those are its arguments of
    their own when it is called).  A closure the environment holds that may
    change some other binding by name stays: running the package changes it
    (A2-6a (I)).  Memory it reaches at one of its own captures stays too, as
    in (II) for `readers`: such a package ends when it runs. -/
def envDeps (cs : List (Var × PMode × Ty)) (H : List Dep) : List Dep :=
  H.filter (fun d => !ownWriter cs d)

theorem mem_envDeps {cs : List (Var × PMode × Ty)} {H : List Dep} {d : Dep} :
    d ∈ envDeps cs H ↔ d ∈ H ∧ ownWriter cs d = false := by
  simp [envDeps]

theorem envDeps_sub (cs : List (Var × PMode × Ty)) (H : List Dep) : envDeps cs H ⊆ H :=
  fun _ hd => (mem_envDeps.mp hd).1

theorem envDeps_mono {cs : List (Var × PMode × Ty)} {H H' : List Dep} (h : H ⊆ H') :
    envDeps cs H ⊆ envDeps cs H' := fun _ hd =>
  mem_envDeps.mpr ⟨h (mem_envDeps.mp hd).1, (mem_envDeps.mp hd).2⟩

theorem ownWriter_of_bound {cs : List (Var × PMode × Ty)} {d : Dep} (hb : d.kind.bound = .none) :
    ownWriter cs d = false := by simp [ownWriter, hb]

/-- What only reads is among what the environment is valid through. -/
theorem readers_sub_envDeps (cs : List (Var × PMode × Ty)) (H : List Dep) : readers H ⊆ envDeps cs H :=
  fun _ hd => mem_envDeps.mpr ⟨(mem_readers.mp hd).1, ownWriter_of_bound (mem_readers.mp hd).2⟩

theorem mem_envDeps_of_mem {cs : List (Var × PMode × Ty)} {H : List Dep} {d : Dep} (hd : d ∈ H)
    (hb : d.kind.bound = .none) : d ∈ envDeps cs H :=
  mem_envDeps.mpr ⟨hd, ownWriter_of_bound hb⟩

/-- Rerooting keeps what the environment is valid through: what the exiting
    parameter held by name is no change of one of the package's own
    captures, and the package reached the parameter not by name. -/
theorem reroot_envDeps {p : Var} {D H : List Dep} {cs : List (Var × PMode × Ty)}
    (hD : ∀ d ∈ D, ownWriter cs d = false) (hH : ∀ d ∈ H, d.root = p → d.kind.bound = .none) :
    reroot p D (envDeps cs H) ⊆ envDeps cs (reroot p D H) := by
  intro d hd
  unfold reroot at hd
  obtain ⟨d0, hd0, hdd⟩ := List.mem_flatMap.mp hd
  obtain ⟨hd0H, hb0⟩ := mem_envDeps.mp hd0
  refine mem_envDeps.mpr ⟨List.mem_flatMap.mpr ⟨d0, hd0H, hdd⟩, ?_⟩
  split at hdd
  · rename_i hp0
    obtain ⟨d', hd', rfl⟩ := List.mem_map.mp hdd
    have hb' := hD d' hd'
    have h0 := hH d0 hd0H hp0
    simp only [ownWriter, Bool.and_eq_false_iff, bne_eq_false_iff_eq] at hb' ⊢
    rcases hb' with hb' | hb'
    · left; exact comp_bound_none hb' h0
    · right; exact hb'
  · simp only [List.mem_singleton] at hdd; rw [hdd]; exact hb0

/-- The arguments hold no closure that may change a binding by name.  (Kept
    for the closure call's own arguments, A2-6a (I): nurlc's route rule.) -/
def NoWriters (Γ : Ctx) (args : List Var) : Prop :=
  ∀ a ∈ args, ((argE Γ a).ty ≠ .int ∨ (argE Γ a).mode = .rootb) →
    ∀ d ∈ (argE Γ a).vdeps, d.kind.bound = .none

theorem NoWriters.names {Γ : Ctx} {args : List Var} (h : NoWriters Γ args) :
    ∀ d ∈ argNames Γ args, d.kind.bound = .none := by
  intro d hd
  simp only [argNames, List.mem_flatMap] at hd
  obtain ⟨a, ha, hda⟩ := hd
  split at hda
  · simp at hda
  · rename_i hn; exact h a ha (Or.inl hn) d (List.mem_filter.mp hda).1

/-- What the arguments hold: views, in every way a callee may come to depend
    on them, and closures, by name. -/
def heldOfArgs (Γ : Ctx) (args : List Var) : List Dep :=
  allKinds (args.flatMap (fun a => if (argE Γ a).ty = .int then [] else roots (memDeps (argE Γ a).held))) ++
    argNames Γ args

def resMode (fn : Fn) : Mode := if fn.resOwn then .own else .bor

/-- The roots what a package's environment depends on: the package (or what
    it borrows from), and what it holds. -/
def recvRoots (c : Var) (Ec : Entry) : List Var :=
  roots (memDeps (derive c Ec .self)) ++ roots (memDeps Ec.held)

/-- What a call through a package returns: what its interface says, and, as
    the method may lend part of the receiver, anything the package reaches. -/
def recvRes (c : Var) (Ec : Entry) (E : Entry) : Entry :=
  { E with path := E.path ++ allKinds (recvRoots c Ec),
           held := ownHeld E.mode.ownSlot E.ty (E.held ++ allKinds (recvRoots c Ec)) }

/-- The call's result: it borrows what the summary says it borrows, and
    may hold whatever the arguments held. -/
def callRes (Γ : Ctx) (fn : Fn) (args : List Var) : Entry :=
  ⟨fn.resTy, resMode fn, true,
   fn.lends.flatMap (argDeps Γ args) ++ heldOfArgs Γ args,
   ownHeld fn.resOwn fn.resTy (fn.rholds.flatMap (argDeps Γ args) ++ heldOfArgs Γ args), false, false⟩

@[simp] theorem callRes_dtor (Γ : Ctx) (fn : Fn) (args : List Var) : (callRes Γ fn args).dtor = false := rfl
@[simp] theorem recvRes_dtor (c : Var) (Ec E : Entry) : (recvRes c Ec E).dtor = E.dtor := rfl
@[simp] theorem callRes_dbind (Γ : Ctx) (fn : Fn) (args : List Var) : (callRes Γ fn args).dbind = false := rfl
@[simp] theorem recvRes_dbind (c : Var) (Ec E : Entry) : (recvRes c Ec E).dbind = E.dbind := rfl

/-- What `inout` parameter `i` holds views of after the call. -/
def outHeld (Γ : Ctx) (fn : Fn) (args : List Var) (i : Nat) : List Dep :=
  (fn.outHolds.filter (fun o => o.1 == i)).flatMap (fun o => argDeps Γ args (o.2.1, o.2.2))

/-- The context after the call, parameter by parameter (from index `i`):
    a `sink` argument is moved, an `inout` argument is changed as the
    summary allows, and holds what the callee stored into it. -/
def callPostAux (Γ0 : Ctx) (fn : Fn) (args : List Var) :
    List (PMode × Ty) → List Var → Nat → Ctx → Ctx
  | (.sink, _) :: ps, a :: as, i, Γ =>
      callPostAux Γ0 fn args ps as (i + 1)
        (setE (kill .replace false a Γ) a { argE Γ0 a with live := false, dtor := false })
  | (.inout b, t) :: ps, a :: as, i, Γ =>
      callPostAux Γ0 fn args ps as (i + 1)
        (setE (kill b t.elem.holdsView a Γ) a
          { argE Γ0 a with held := if t.holdsView then
              (argE Γ0 a).held ++ outHeld Γ0 fn args i ++ heldOfArgs Γ0 args else (argE Γ0 a).held })
  | (.inp, _) :: ps, _ :: as, i, Γ => callPostAux Γ0 fn args ps as (i + 1) Γ
  | _, _, _, Γ => Γ

/-- Running the closures handed to a call ends what their changes end (a
    binding changed by name holds no views). -/
def killNames (ds : List Dep) (Γ : Ctx) : Ctx :=
  ds.foldr (fun d Γ => kill d.kind.bound false d.root Γ) Γ

def callPost (Γ : Ctx) (fn : Fn) (args : List Var) : Ctx :=
  killNames (mutNames Γ args) (callPostAux Γ fn args fn.params args 0 Γ)

/-- A binding a closure handed to a call may change is changed by the call:
    it allows the change, is a `Vec` whose elements hold no views, is not
    lent out, not passed beside the closure but as an `inout` argument of
    that very bound (the callee's code is checked against the change), and
    reached from no argument but by a closure that may change it the same
    way (§2.11: not a view, a borrow, nor a closure that reads it; the
    callee tells no two of them apart). -/
def NamesFree (Γ : Ctx) (F : List Var) (ps : List (PMode × Ty)) (args : List Var) : Prop :=
  ∀ d ∈ mutNames Γ args, canDo (argE Γ d.root).mode d.kind.bound ∧
    (∃ s, (argE Γ d.root).ty = .vec s ∧ s.holdsView = false) ∧ d.root ∉ F ∧
    (d.root ∉ args ∨ ∃ (i : Nat) (t : Ty), args[i]? = some d.root ∧
      ps[i]? = some (PMode.inout d.kind.bound, t)) ∧
    ∀ a ∈ args, ((argE Γ a).ty ≠ .int ∨ (argE Γ a).mode = .rootb) →
      ∀ d' ∈ (argE Γ a).vdeps, d'.root = d.root → d'.kind.bound = d.kind.bound

def PMode.moves : PMode → Bool
  | .inp => false
  | _ => true

def paramOK : PMode → Ty → Entry → Prop
  | .inp, t, E => E.ty = t
  | .sink, t, E => E.ty = t ∧ E.mode = .own ∧ t.owning = true
  | .inout b, t, E => E.ty = t ∧ canDo E.mode b ∧ t.owning = true

/-- A2-drop.2: what a call moves (a `sink` argument), changes (an `inout`
    one, by its bound) and kills by name (`killNames`) ends no view a
    binding that may run a destructor holds: `DtorSafe` for each of
    `callPost`'s kills. -/
def CallDtorSafe (Γ : Ctx) (ps : List (PMode × Ty)) (args : List Var) : Prop :=
  (∀ i (h : i < ps.length),
    (ps[i].1 = .sink → DtorSafe Γ .replace false (args.getD i 0)) ∧
    (∀ b, ps[i].1 = .inout b → DtorSafe Γ b ps[i].2.elem.holdsView (args.getD i 0))) ∧
  (∀ d ∈ mutNames Γ args, DtorSafe Γ d.kind.bound false d.root) ∧
  -- a destructor binding gains no view: as an `inout` argument, it holds none
  (∀ i (h : i < ps.length) b, ps[i].1 = .inout b → ∀ Ea, Γ (args.getD i 0) = some Ea →
    Ea.dbind = true → ps[i].2.holdsView = false)

/-- With no binding that runs a destructor, every call is safe. -/
theorem CallDtorSafe.of_none {Γ : Ctx} (h : ∀ v E, Γ v = some E → E.dtor = false ∧ E.dbind = false)
    (ps : List (PMode × Ty)) (args : List Var) : CallDtorSafe Γ ps args :=
  ⟨fun _ _ => ⟨fun _ => DtorSafe.of_none (fun v E hE => (h v E hE).1) _ _ _,
      fun _ _ => DtorSafe.of_none (fun v E hE => (h v E hE).1) _ _ _⟩,
    fun _ _ => DtorSafe.of_none (fun v E hE => (h v E hE).1) _ _ _,
    fun _ _ _ _ Ea hEa hd => by rw [(h _ Ea hEa).2] at hd; cases hd⟩

/-- A call that only borrows, and kills nothing by name, is safe. -/
theorem CallDtorSafe.of_inp {Γ : Ctx} {ps : List (PMode × Ty)} {args : List Var}
    (hp : ∀ q ∈ ps, q.1 = .inp) (hn : mutNames Γ args = []) : CallDtorSafe Γ ps args := by
  refine ⟨fun i hi => ⟨fun hs => ?_, fun b hb => ?_⟩, fun d hd => ?_, fun i hi b hb => ?_⟩
  · have := hp _ (List.getElem_mem hi); rw [hs] at this; cases this
  · have := hp _ (List.getElem_mem hi); rw [hb] at this; cases this
  · rw [hn] at hd; cases hd
  · have := hp _ (List.getElem_mem hi); rw [hb] at this; cases this

/-- A call, checked against the callee's summary.  Each argument is live
    and of its parameter's type; one that moves or may change is not frozen
    and reaches the callee through no other argument (§2.1, §2.4). -/
def CallT (P : Prog) (Γ : Ctx) (F : List Var) (f : Nat) (args : List Var) (E : Entry)
    (Γ' : Ctx) : Prop :=
  ∃ fn, P[f]? = some fn ∧ args.length = fn.params.length ∧
    (∀ i (h : i < fn.params.length), ∃ Ea, Γ (args.getD i 0) = some Ea ∧ Ea.live = true ∧
        paramOK fn.params[i].1 fn.params[i].2 Ea ∧
        -- an argument moved or changed is reached by no other argument in
        -- memory; a `sink` by nothing at all; an `inout` argument only by a
        -- name of the parameter's own bound: a closure that changes it as
        -- the callee's own code may (the callee may run it, and its code is
        -- checked against that: §2.11, A2-6a (I))
        (fn.params[i].1.moves = true →
          args.getD i 0 ∉ F ∧ args.getD i 0 ∉ roots (memDeps Ea.vdeps) ∧
          (fn.params[i].1 = .sink → args.getD i 0 ∉ roots Ea.vdeps) ∧
          (∀ b, fn.params[i].1 = .inout b → ∀ d ∈ Ea.vdeps,
            d.root = args.getD i 0 → d.kind.bound = b ∧ b ≠ .none) ∧
          ∀ j < fn.params.length, j ≠ i →
            args.getD j 0 ≠ args.getD i 0 ∧
            args.getD i 0 ∉ roots (memDeps (argE Γ (args.getD j 0)).vdeps) ∧
            (fn.params[i].1 = .sink → args.getD i 0 ∉ roots (argE Γ (args.getD j 0)).vdeps) ∧
            (∀ b, fn.params[i].1 = .inout b → ∀ d ∈ (argE Γ (args.getD j 0)).vdeps,
              d.root = args.getD i 0 → d.kind.bound = b ∧ b ≠ .none)) ∧
        (fn.params[i].1 = .sink ∨ fn.params[i].1 = .inout .replace → NoPin Γ (args.getD i 0))) ∧
    NamesFree Γ F fn.params args ∧ CallDtorSafe Γ fn.params args ∧
    E = callRes Γ fn args ∧ Γ' = callPost Γ fn args

/-! ### Statements -/

/-- Source code: no run-time forms.  What has not started running yet (a
    binding's body, the rest of a sequence, a branch, a loop body) is
    source; run-time forms appear only where execution is. -/
def Stmt.src : Stmt → Bool
  | .skip => true
  | .seq a b => a.src && b.src
  | .letv _ _ s => s.src
  | .letcall _ _ _ s => s.src
  | .assign _ _ => true
  | .ite _ a b => a.src && b.src
  | .while _ s => s.src
  | .push _ _ => true
  | .free _ => true
  | .scope _ _ => false
  | .rbind _ _ => false
  | .frozen _ _ => false
  | .panic => true
  | .letrec _ _ s => s.src
  | .catchR _ _ _ => false
  | .unpair _ _ _ s => s.src
  | .callc _ _ _ _ s => s.src
  | .letd _ _ _ s => s.src
  | .scopeD _ _ _ => false

/-! ### Functions -/

/-- What a closure a function is handed may change by name, as far as the
    function can tell: any of its own view-free `inout` parameters (a
    closure captures a binding `inout` only when it holds no views,
    `CapsOK`; the caller may hand it one of them captured).  A closure-typed
    borrowed parameter holds them all by name, so running it, or handing it
    on, ends their views and is checked against them (A2-6a (I), the h285
    rule in the calculus); the call replaces these symbolic names by the
    closure's own. -/
def symNames (ps : List (PMode × Ty)) : List Dep :=
  (List.range ps.length).filterMap fun i =>
    match (ps[i]? : Option (PMode × Ty)) with
    | some (PMode.inout b, t) =>
      if t.holdsView = false ∧ b ≠ .none ∧ b ≠ .replace then some ⟨i, Kind.name b t⟩ else none
    | _ => none

theorem mem_symNames {ps : List (PMode × Ty)} {w : Var} {b : Eff} {t : Ty} :
    (⟨w, .name b t⟩ : Dep) ∈ symNames ps ↔
      ps[w]? = some (.inout b, t) ∧ t.holdsView = false ∧ b ≠ .none ∧ b ≠ .replace := by
  unfold symNames
  simp only [List.mem_filterMap, List.mem_range]
  constructor
  · rintro ⟨i, hi, hf⟩
    split at hf
    · rename_i b' t' hp
      split at hf
      · simp only [Option.some.injEq, Dep.mk.injEq, Kind.name.injEq] at hf
        obtain ⟨rfl, rfl, rfl⟩ := hf
        exact ⟨hp, by assumption⟩
      · cases hf
    · cases hf
  · rintro ⟨hp, hc⟩
    refine ⟨w, (List.getElem?_eq_some_iff.mp hp).1, ?_⟩
    rw [hp]; simp [hc]

theorem mem_symNames' {ps : List (PMode × Ty)} {d : Dep} (hd : d ∈ symNames ps) :
    ∃ w b t, d = ⟨w, .name b t⟩ ∧ ps[w]? = some (.inout b, t) ∧ t.holdsView = false ∧
      b ≠ .none ∧ b ≠ .replace := by
  unfold symNames at hd
  simp only [List.mem_filterMap, List.mem_range] at hd
  obtain ⟨i, _, hf⟩ := hd
  split at hf
  · rename_i b t hp
    split at hf
    · simp only [Option.some.injEq] at hf; subst hf
      exact ⟨i, b, t, rfl, hp, by assumption⟩
    · cases hf
  · cases hf

theorem elem_holdsView (t : Ty) : t.elem.holdsView = t.holdsView := by
  cases t <;> rfl

/-- May a value of this type hold a closure (and so hold bindings by name)? -/
def Ty.hasFn : Ty → Bool
  | .int => false
  | .vec t => t.hasFn
  | .slice t => t.hasFn
  | .prod a b => a.hasFn || b.hasFn
  | .sum a b => a.hasFn || b.hasFn
  | .fn _ => true

theorem hasFn_holdsView {t : Ty} (h : t.hasFn = true) : t.holdsView = true := by
  induction t with
  | int => cases h
  | vec t ih => exact ih h
  | slice _ _ => rfl
  | prod a b iha ihb =>
    simp only [Ty.hasFn, Bool.or_eq_true] at h
    simp only [Ty.holdsView, Bool.or_eq_true]
    exact h.imp iha ihb
  | sum a b iha ihb =>
    simp only [Ty.hasFn, Bool.or_eq_true] at h
    simp only [Ty.holdsView, Bool.or_eq_true]
    exact h.imp iha ihb
  | fn _ => rfl

/-- A parameter's entry: a borrowed one depends on nothing the callee can
    see; every parameter whose type may hold a closure holds the symbolic
    names (what it was handed may change any `inout` parameter). -/
def paramE (ps : List (PMode × Ty)) : PMode × Ty → Entry
  | (.inp, t) => ⟨t, .rootb, true, [], if t.hasFn then symNames ps else [], false, false⟩
  | (.inout b, t) => ⟨t, .inout b, true, [], if t.hasFn then symNames ps else [], false, false⟩
  | (.sink, t) => ⟨t, .own, true, [], if t.hasFn then symNames ps else [], false, false⟩

/-- The callee's own view of its parameters: they depend on nothing it can
    see, but a closure it is handed, which may change its `inout`
    parameters.  The result slot starts empty. -/
def sigCtx (fn : Fn) : Ctx := fun v =>
  if h : v < fn.params.length then some (paramE fn.params fn.params[v])
  else if v = fn.params.length then some ⟨fn.resTy, resMode fn, false, [], [], false, false⟩
  else none

/-- A summary pair names a parameter the caller still has after the call. -/
def lendable (fn : Fn) (j : Nat) : Prop :=
  ∃ h : j < fn.params.length, fn.params[j].1 = .inp ∨ ∃ b, fn.params[j].1 = .inout b

/-- An `inout` argument is the binding that owns the value — an owner, or
    an `inout` parameter of the caller's — of any owning type (a `Vec`, a
    struct, an enum, a closure).  A borrow of it, or a second name for a
    parameter (`: ~ c p`, a borrow in the calculus), is never passed: the
    callee may replace what is there (h295: a copy of a parameter passed
    `inout` to a function that replaced one of its fields). -/
theorem paramOK_inout {b : Eff} {t : Ty} {E : Entry} (h : paramOK (.inout b) t E) :
    (E.mode = .own ∨ ∃ b', E.mode = .inout b' ∧ b.le b') ∧ t.owning = true := by
  obtain ⟨_, hc, ho⟩ := h
  exact ⟨hc, ho⟩

/-- A summary pair names a kind its parameter's type can carry: what depends
    on an `inout` parameter that has no handle of its own (a struct, an enum,
    a closure: its value is inline) depends on it inside, never on a handle
    (`derive` makes a `.self` dependency on such a root a view). -/
def kindFits (fn : Fn) (j : Nat) (k : Kind) : Prop :=
  ∀ b t, fn.params[j]? = some (.inout b, t) → rootKind t k = k

/-- Every variable a statement names (binders included). -/
def Expr.vars : Expr → List Var
  | .lit _ => []
  | .var x => [x]
  | .add a b => a.vars ++ b.vars
  | .lt a b => a.vars ++ b.vars
  | .len x => [x]
  | .slen x => [x]
  | .isl x => [x]

def Rhs.vars : Rhs → List Var
  | .expr e => e.vars
  | .new _ => []
  | .var y => [y]
  | .borrow y => [y]
  | .at y i => y :: i.vars
  | .view y => [y]
  | .sat y i => y :: i.vars
  | .pop y => [y]
  | .pair y z => [y, z]
  | .fst y => [y]
  | .snd y => [y]
  | .inl y _ => [y]
  | .inr _ y => [y]
  | .getl y => [y]
  | .getr y => [y]
  | .takel y => [y]
  | .taker y => [y]
  | .pack _ _ _ y cs => y :: cs.map (·.1)

def Stmt.vars : Stmt → List Var
  | .skip => []
  | .seq a b => a.vars ++ b.vars
  | .letv x r s => x :: r.vars ++ s.vars
  | .letcall x _ args s => x :: args ++ s.vars
  | .assign x r => x :: r.vars
  | .ite c a b => c.vars ++ a.vars ++ b.vars
  | .while c s => c.vars ++ s.vars
  | .push x y => [x, y]
  | .free x => [x]
  | .scope x s => x :: s.vars
  | .rbind p s => p :: s.vars
  | .frozen z s => z ++ s.vars
  | .panic => []
  | .letrec x _ s => x :: s.vars
  | .catchR x _ s => x :: s.vars
  | .unpair y x z s => y :: x :: z :: s.vars
  | .callc x c _ zs s => x :: c :: zs ++ s.vars
  | .letd x _ r s => x :: r.vars ++ s.vars
  | .scopeD x _ s => x :: s.vars



end A2
