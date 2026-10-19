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

/-- The end of `x`'s scope: what borrows from it ends, and it is gone. -/
def exitScope (x : Var) (Γ : Ctx) : Ctx := upd (kill .replace false x Γ) x none

/-- At the end of a borrowed parameter `p`'s scope, what depends on `p`
    depends on what `p` borrowed (`D`). -/
def reroot (p : Var) (D : List Dep) (ds : List Dep) : List Dep :=
  ds.flatMap (fun d => if d.root = p then D.map (fun d' => ⟨d'.root, comp d'.kind d.kind⟩) else [d])

def rerootE (p : Var) (D : List Dep) (E : Entry) : Entry :=
  { E with path := reroot p D E.path, held := reroot p D E.held }

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
def EntryWeaker (E E' : Entry) : Prop :=
  E'.ty = E.ty ∧ E'.mode = E.mode ∧
  (E.fixed → E' = E) ∧
  (E'.live = true → E.live = true ∧ (E.mode.ownSlot = false → E.path ⊆ E'.path) ∧
    E.held ⊆ E'.held)

/-- A context's live entries depend only on roots it has.  (An integer's
    dependencies say nothing: it holds no memory.) -/
def CtxWF (Γ : Ctx) : Prop :=
  ∀ v E, Γ v = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → ∀ r ∈ roots E.vdeps,
    ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true

/-- May a binding in this mode undergo effect `e`? -/
def canDo (m : Mode) (e : Eff) : Prop :=
  m = .own ∨ ∃ b, m = .inout b ∧ e.le b

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

def intE : Entry := ⟨.int, .bor, true, [], []⟩

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
  | .slice s => ⟨.slice s, .bor, true, E.held, E.held⟩
  | .vec s => ⟨.vec s, .bor, true, derive y E .inner, E.held⟩
  | .prod a b => ⟨.prod a b, .bor, true, derive y E .inner, E.held⟩
  | .sum a b => ⟨.sum a b, .bor, true, derive y E .inner, E.held⟩
  | .fn ms => ⟨.fn ms, .bor, true, derive y E .inner, E.held⟩

/-- An element moved out of `y` by `vec_pop`: an element `Vec` or struct is
    owned. -/
def popE (y : Var) (E : Entry) : Ty → Entry
  | .vec s => ⟨.vec s, .own, true, [], E.held⟩
  | .prod a b => ⟨.prod a b, .own, true, [], E.held⟩
  | .sum a b => ⟨.sum a b, .own, true, [], E.held⟩
  | .fn ms => ⟨.fn ms, .own, true, [], E.held⟩
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
  | t => ⟨t, .bor, true, projDeps y E ++ E.held, E.held⟩

/-- What an owned value holds: nothing, if its type holds no views (no view
    and no closure lies inside it, so what it was made from says nothing). -/
def ownHeld (o : Bool) (t : Ty) (H : List Dep) : List Dep := if o && !t.holdsView then [] else H

/-- A field moved out of a struct that is taken apart. -/
def compE (E : Entry) : Ty → Entry
  | .int => intE
  | .slice s => ⟨.slice s, .bor, true, E.held, E.held⟩
  | t => ⟨t, .own, true, [], ownHeld true t E.held⟩

/-- The element type of a `Vec`. -/
def Ty.elem : Ty → Ty
  | .vec t => t
  | t => t

/-- Handing `y` to `vec_push`: an element `Vec` moves, anything else is
    copied with what it depends on (`D`, which the container then holds). -/
inductive PushArg (Γ : Ctx) (F : List Var) (y : Var) (E : Entry) : Ty → List Dep → Ctx → Prop
  | move {t : Ty} :
      t.owning = true → E.mode = .own → y ∉ F → NoPin Γ y →
      PushArg Γ F y E t E.held (setE (kill .replace false y Γ) y { E with live := false })
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
  | new {t : Ty} : t.ok = true → RhsT Γ F (.new t) ⟨.vec t, .own, true, [], []⟩ Γ
  | moveOwn {y : Var} {E : Entry} :
      Γ y = some E → E.live = true → E.mode = .own → y ∉ F → NoPin Γ y →
      RhsT Γ F (.var y) ⟨E.ty, .own, true, [], E.held⟩
        (setE (kill .replace false y Γ) y { E with live := false })
  | copyRoot {y : Var} {E : Entry} :
      Γ y = some E → E.live = true → E.mode = .rootb →
      RhsT Γ F (.var y) ⟨E.ty, .bor, true, derive y E .self, E.held⟩ Γ
  | copyBor {y : Var} {E : Entry} :
      Γ y = some E → E.live = true → E.mode = .bor → RhsT Γ F (.var y) E Γ
  | borrow {y : Var} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .vec t →
      RhsT Γ F (.borrow y) ⟨E.ty, .bor, true, derive y E .self, E.held⟩ Γ
  | at {y : Var} {i : Expr} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .vec t → ExprT Γ i →
      RhsT Γ F (.at y i) (elemE y E t) Γ
  | view {y : Var} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .vec t → t.holdsView = false →
      RhsT Γ F (.view y) ⟨.slice t, .bor, true, derive y E .view, E.held⟩ Γ
  | sat {y : Var} {i : Expr} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .slice t → ExprT Γ i →
      RhsT Γ F (.sat y i) (elemE y E t) Γ
  | pop {y : Var} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .vec t → canDo E.mode .drop → y ∉ F →
      RhsT Γ F (.pop y) (popE y E t) (kill .drop t.holdsView y Γ)
  | pair {y z : Var} {Ey Ez : Entry} {Γ1 Γ2 : Ctx} {Dy Dz : List Dep} :
      Γ y = some Ey → Ey.live = true → PushArg Γ F y Ey Ey.ty Dy Γ1 →
      Γ1 z = some Ez → Ez.live = true → PushArg Γ1 F z Ez Ez.ty Dz Γ2 →
      (Ez.mode.ownSlot = true → z ∉ roots Dy) →
      RhsT Γ F (.pair y z) ⟨.prod Ey.ty Ez.ty, .own, true, [], Dy ++ Dz⟩ Γ2
  | fst {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.ty = .prod a b → RhsT Γ F (.fst y) (projE y E a) Γ
  | snd {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.ty = .prod a b → RhsT Γ F (.snd y) (projE y E b) Γ
  | inl {y : Var} {b : Ty} {Ey : Entry} {Γ1 : Ctx} {D : List Dep} :
      Γ y = some Ey → Ey.live = true → PushArg Γ F y Ey Ey.ty D Γ1 → b.ok = true →
      RhsT Γ F (.inl y b) ⟨.sum Ey.ty b, .own, true, [], D⟩ Γ1
  | inr {a : Ty} {y : Var} {Ey : Entry} {Γ1 : Ctx} {D : List Dep} :
      Γ y = some Ey → Ey.live = true → PushArg Γ F y Ey Ey.ty D Γ1 → a.ok = true →
      RhsT Γ F (.inr a y) ⟨.sum a Ey.ty, .own, true, [], D⟩ Γ1
  | getl {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.ty = .sum a b → RhsT Γ F (.getl y) (projE y E a) Γ
  | getr {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.ty = .sum a b → RhsT Γ F (.getr y) (projE y E b) Γ
  | takel {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.mode = .own → E.ty = .sum a b → y ∉ F → NoPin Γ y →
      RhsT Γ F (.takel y) (compE E a) (setE (kill .replace false y Γ) y { E with live := false })
  | taker {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.mode = .own → E.ty = .sum a b → y ∉ F → NoPin Γ y →
      RhsT Γ F (.taker y) (compE E b) (setE (kill .replace false y Γ) y { E with live := false })
  | pack {fs : List Nat} {te : Ty} {ms : List Nat} {y : Var} {cs : List (Var × PMode × Ty)} {Ey : Entry}
      {Γ1 : Ctx} {D : List Dep} :
      Γ y = some Ey → Ey.live = true → Ey.ty = te → PushArg Γ F y Ey te D Γ1 → CapsOK Γ1 F D cs →
      RhsT Γ F (.pack fs te ms y cs) ⟨.fn ms, .own, true, [], D ++ capDeps cs⟩ Γ1

/-! ### Calls -/

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
   ownHeld fn.resOwn fn.resTy (fn.rholds.flatMap (argDeps Γ args) ++ heldOfArgs Γ args)⟩

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
        (setE (kill .replace false a Γ) a { argE Γ0 a with live := false })
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
    lent out, not passed beside the closure, and reached from no argument
    but by a closure that may change it (§2.11: not a view, a borrow, nor a
    closure that reads it). -/
def NamesFree (Γ : Ctx) (F : List Var) (args : List Var) : Prop :=
  ∀ d ∈ mutNames Γ args, canDo (argE Γ d.root).mode d.kind.bound ∧
    (∃ s, (argE Γ d.root).ty = .vec s ∧ s.holdsView = false) ∧ d.root ∉ F ∧ d.root ∉ args ∧
    ∀ a ∈ args, ((argE Γ a).ty ≠ .int ∨ (argE Γ a).mode = .rootb) →
      ∀ d' ∈ (argE Γ a).vdeps, d'.root = d.root → d'.kind.bound ≠ .none

def PMode.moves : PMode → Bool
  | .inp => false
  | _ => true

def paramOK : PMode → Ty → Entry → Prop
  | .inp, t, E => E.ty = t
  | .sink, t, E => E.ty = t ∧ E.mode = .own ∧ t.owning = true
  | .inout b, t, E => E.ty = t ∧ canDo E.mode b ∧ ∃ s, t = .vec s

/-- A call, checked against the callee's summary.  Each argument is live
    and of its parameter's type; one that moves or may change is not frozen
    and reaches the callee through no other argument (§2.1, §2.4). -/
def CallT (P : Prog) (Γ : Ctx) (F : List Var) (f : Nat) (args : List Var) (E : Entry)
    (Γ' : Ctx) : Prop :=
  ∃ fn, P[f]? = some fn ∧ args.length = fn.params.length ∧
    (∀ i (h : i < fn.params.length), ∃ Ea, Γ (args.getD i 0) = some Ea ∧ Ea.live = true ∧
        paramOK fn.params[i].1 fn.params[i].2 Ea ∧
        (fn.params[i].1.moves = true →
          args.getD i 0 ∉ F ∧ args.getD i 0 ∉ roots Ea.vdeps ∧
          ∀ j < fn.params.length, j ≠ i →
            args.getD j 0 ≠ args.getD i 0 ∧ args.getD i 0 ∉ roots (argE Γ (args.getD j 0)).vdeps) ∧
        (fn.params[i].1 = .sink ∨ fn.params[i].1 = .inout .replace → NoPin Γ (args.getD i 0))) ∧
    NamesFree Γ F args ∧ E = callRes Γ fn args ∧ Γ' = callPost Γ fn args

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

/-! ### Functions -/

def paramE : PMode × Ty → Entry
  | (.inp, t) => ⟨t, .rootb, true, [], []⟩
  | (.inout b, t) => ⟨t, .inout b, true, [], []⟩
  | (.sink, t) => ⟨t, .own, true, [], []⟩

/-- The callee's own view of its parameters: they depend on nothing it can
    see.  The result slot starts empty. -/
def sigCtx (fn : Fn) : Ctx := fun v =>
  if h : v < fn.params.length then some (paramE fn.params[v])
  else if v = fn.params.length then some ⟨fn.resTy, resMode fn, false, [], []⟩
  else none

/-- A summary pair names a parameter the caller still has after the call. -/
def lendable (fn : Fn) (j : Nat) : Prop :=
  ∃ h : j < fn.params.length, fn.params[j].1 = .inp ∨ ∃ b, fn.params[j].1 = .inout b

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



end A2
