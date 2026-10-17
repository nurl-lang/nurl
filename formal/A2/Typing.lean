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
  | _, _ => .inner

/-- The handle of a borrowed slice parameter is a view. -/
def rootKind (t : Ty) (k : Kind) : Kind :=
  match t, k with
  | .slice _, .self => .view
  | .prod _ _, .self => .view
  | .sum _ _, .self => .view
  | .fn _ _, .self => .view
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

/-- `E'` says no more than `E`: it may be dead where `E` is live, and depend
    on more.  A borrowed parameter's entry is fixed; an owner's `path` says
    nothing (an owner is reached through its own slot). -/
def EntryWeaker (E E' : Entry) : Prop :=
  E'.ty = E.ty ∧ E'.mode = E.mode ∧
  (E.mode = .rootb → E' = E) ∧
  (E'.live = true → E.live = true ∧ (E.mode.ownSlot = false → E.path ⊆ E'.path) ∧
    E.held ⊆ E'.held)

/-- A context's live entries depend only on roots it has.  (An integer's
    dependencies say nothing: it holds no memory.) -/
def CtxWF (Γ : Ctx) : Prop :=
  ∀ v E, Γ v = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → ∀ r ∈ roots E.vdeps,
    ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true

def Weaker (Γ Γ' : Ctx) : Prop :=
  (∀ v, (Γ v = none ↔ Γ' v = none) ∧
    ∀ E E', Γ v = some E → Γ' v = some E' → EntryWeaker E E') ∧ CtxWF Γ'

/-- May a binding in this mode undergo effect `e`? -/
def canDo (m : Mode) (e : Eff) : Prop :=
  m = .own ∨ ∃ b, m = .inout b ∧ e.le b

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
  | .fn a r => ⟨.fn a r, .bor, true, derive y E .inner, E.held⟩

/-- An element moved out of `y` by `vec_pop`: an element `Vec` or struct is
    owned. -/
def popE (y : Var) (E : Entry) : Ty → Entry
  | .vec s => ⟨.vec s, .own, true, [], E.held⟩
  | .prod a b => ⟨.prod a b, .own, true, [], E.held⟩
  | .sum a b => ⟨.sum a b, .own, true, [], E.held⟩
  | .fn a r => ⟨.fn a r, .own, true, [], E.held⟩
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

/-- A field moved out of a struct that is taken apart. -/
def compE (E : Entry) : Ty → Entry
  | .int => intE
  | .slice s => ⟨.slice s, .bor, true, E.held, E.held⟩
  | t => ⟨t, .own, true, [], E.held⟩

/-- The element type of a `Vec`. -/
def Ty.elem : Ty → Ty
  | .vec t => t
  | t => t

/-- Handing `y` to `vec_push`: an element `Vec` moves, anything else is
    copied with what it depends on (`D`, which the container then holds). -/
inductive PushArg (Γ : Ctx) (F : List Var) (y : Var) (E : Entry) : Ty → List Dep → Ctx → Prop
  | move {t : Ty} :
      t.owning = true → E.mode = .own → y ∉ F →
      PushArg Γ F y E t E.held (setE (kill .replace false y Γ) y { E with live := false })
  | int : PushArg Γ F y E .int [] Γ
  | slice {s : Ty} :
      (E.mode = .bor ∨ E.mode = .rootb) →
      PushArg Γ F y E (.slice s) (derive y E .self ++ E.held) Γ

inductive RhsT (Γ : Ctx) (F : List Var) : Rhs → Entry → Ctx → Prop
  | expr {e : Expr} : ExprT Γ e → RhsT Γ F (.expr e) intE Γ
  | new {t : Ty} : t.ok = true → RhsT Γ F (.new t) ⟨.vec t, .own, true, [], []⟩ Γ
  | moveOwn {y : Var} {E : Entry} :
      Γ y = some E → E.live = true → E.mode = .own → y ∉ F →
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
      Γ y = some E → E.live = true → E.mode = .own → E.ty = .sum a b → y ∉ F →
      RhsT Γ F (.takel y) (compE E a) (setE (kill .replace false y Γ) y { E with live := false })
  | taker {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.mode = .own → E.ty = .sum a b → y ∉ F →
      RhsT Γ F (.taker y) (compE E b) (setE (kill .replace false y Γ) y { E with live := false })
  | pack {f : Nat} {te a r : Ty} {y : Var} {Ey : Entry} {Γ1 : Ctx} {D : List Dep} :
      Γ y = some Ey → Ey.live = true → Ey.ty = te → PushArg Γ F y Ey te D Γ1 → a.ok = true →
      r.ok = true → RhsT Γ F (.pack f te a r y) ⟨.fn a r, .own, true, [], D⟩ Γ1

/-! ### Calls -/

def argE (Γ : Ctx) (a : Var) : Entry := (Γ a).getD intE

/-- What the summary pair `(j, k)` means at this call.  An integer argument
    lends nothing. -/
def argDeps (Γ : Ctx) (args : List Var) (jk : Nat × Kind) : List Dep :=
  if (argE Γ (args.getD jk.1 0)).ty = .int then []
  else derive (args.getD jk.1 0) (argE Γ (args.getD jk.1 0)) jk.2

/-- Every dependency of every kind on the given roots. -/
def allKinds (rs : List Var) : List Dep :=
  rs.flatMap (fun r => [⟨r, .self⟩, ⟨r, .inner⟩, ⟨r, .view⟩])

/-- What the arguments hold views of, in every way a callee may come to
    depend on it.  An integer holds nothing. -/
def heldOfArgs (Γ : Ctx) (args : List Var) : List Dep :=
  allKinds (args.flatMap (fun a => if (argE Γ a).ty = .int then [] else roots (argE Γ a).held))

def resMode (fn : Fn) : Mode := if fn.resOwn then .own else .bor

/-- The call's result: it borrows what the summary says it borrows, and
    may hold whatever the arguments held. -/
def callRes (Γ : Ctx) (fn : Fn) (args : List Var) : Entry :=
  ⟨fn.resTy, resMode fn, true,
   fn.lends.flatMap (argDeps Γ args) ++ heldOfArgs Γ args,
   fn.rholds.flatMap (argDeps Γ args) ++ heldOfArgs Γ args⟩

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
          { argE Γ0 a with held := (argE Γ0 a).held ++ outHeld Γ0 fn args i ++ heldOfArgs Γ0 args })
  | (.inp, _) :: ps, _ :: as, i, Γ => callPostAux Γ0 fn args ps as (i + 1) Γ
  | _, _, _, Γ => Γ

def callPost (Γ : Ctx) (fn : Fn) (args : List Var) : Ctx :=
  callPostAux Γ fn args fn.params args 0 Γ

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
            args.getD j 0 ≠ args.getD i 0 ∧ args.getD i 0 ∉ roots (argE Γ (args.getD j 0)).vdeps)) ∧
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
  | .pack _ _ _ _ y => [y]

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



end A2
