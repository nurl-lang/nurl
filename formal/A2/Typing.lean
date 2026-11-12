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
  /-- A2-drop.2: the binding was made by `letd`, of a type that holds
      views: it runs a destructor whenever it owns a value, and the
      destructor reads what the value views.  (One of a type that holds no
      views reads only what the binding owns: it needs no care.)  It never
      changes. -/
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

/-- A2-drop.2: the binding `letd` makes. It is armed, and remembered as
    `letd`'s, when its type holds views: its destructor reads them. (A
    destructor of a type that holds no views reads only what its binding
    owns, so such a binding needs no care.)  A2-drop.3a: both flags are read
    off the binding's type, a destructor type (`Ty.dtorViews`): `letd` binds
    every owned value of one, wherever it came from (`StmtT.letd`). -/
def Entry.arm (E : Entry) : Entry := { E with dtor := E.ty.dtorViews, dbind := E.ty.dtorViews }

def roots (ds : List Dep) : List Var := ds.map (·.root)

/-- A2-drop.2: what `letd` may record its binding as viewing: what the
    value views, and perhaps more memory, of roots bound in `Γ`.  (Where a
    call places a callee's body, its bindings are read as viewing anything
    the arguments held; the checker records exactly what the value views.) -/
def HeldUp (Γ : Ctx) (E : Entry) (H : List Dep) : Prop :=
  E.held ⊆ H ∧ ∀ d ∈ H, d ∈ E.held ∨
    (d.kind.isName = false ∧ ∃ Er, Γ d.root = some Er ∧ Er.mode.isRoot = true)

theorem HeldUp.refl (Γ : Ctx) (E : Entry) : HeldUp Γ E E.held :=
  ⟨List.Subset.refl _, fun _ h => Or.inl h⟩

/-- ... so an owner records only roots its value's views have, or bound ones. -/
theorem HeldUp.root {Γ : Ctx} {E : Entry} {H : List Dep} (hH : HeldUp Γ E H) (hmo : E.mode = .own)
    (hr : ∀ r ∈ roots E.vdeps, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) :
    ∀ d ∈ H, ∃ Er, Γ d.root = some Er ∧ Er.mode.isRoot = true := by
  have hos : E.mode.ownSlot = true := by rw [hmo]; rfl
  intro d hd
  rcases hH.2 d hd with hd | ⟨_, hex⟩
  · exact hr d.root (by simp only [Entry.vdeps, hos, ↓reduceIte, List.nil_append]; exact List.mem_map_of_mem hd)
  · exact hex

/-- Composing a dependency (how `p` reaches a root, `a`) with how a value
    reaches `p` (`b`). -/
def comp : Kind → Kind → Kind
  | .self, k => k
  | k, .self => k
  | .view, .view => .view
  | .name b t, _ => .name b t
  | _, .name b t => .name b t
  | .share, _ => .share   -- A3.1: what is reached inside a payload stays inside it
  | _, .share => .share
  | _, _ => .inner

/-- The handle of a borrowed slice parameter is a view. -/
def rootKind (t : Ty) (k : Kind) : Kind :=
  match t, k with
  | .slice _, .self => .view
  | .prod _ _, .self => .view
  | .sum _ _, .self => .view
  | .fn _ _, .self => .view
  | .dtor _ _, .self => .view   -- A2-drop.3: a destructor value is lent as a struct is
  | _, k => k

/-- A root lends in the way asked, or (a whole struct, view or closure) as a view. -/
theorem rootKind_cases (t : Ty) (k : Kind) : rootKind t k = k ∨ (k = .self ∧ rootKind t k = .view) := by
  cases t <;> cases k <;> simp [rootKind]

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

/-- A memory view of `r` that `hitsMem` does not hit is one `e` spares. -/
theorem hitsMem_kills {e : Eff} {hv : Bool} {r : Var} {E : Entry} (h : hitsMem e hv r E = false)
    (hg : E.ty ≠ .int ∨ E.mode = .rootb) {d : Dep} (hd : d ∈ E.vdeps) (hr : d.root = r)
    (hnm : d.kind.isName = false) : e.kills hv d.kind = false := by
  unfold hitsMem at h
  have hg' : (E.ty != .int || E.mode == .rootb) = true := by rcases hg with h' | h' <;> simp [h']
  rw [hg', Bool.true_and, List.any_eq_false] at h
  have := h d hd
  cases hk : e.kills hv d.kind
  · rfl
  · exact absurd (by simp [hr, hnm, hk]) this

/-- A2-drop.2: no binding `letd` made, armed or not, views `x` in memory:
    what a scope's end asks, so that a moved-out destructor binding keeps
    no view of a binding that is gone (a join may arm it again). -/
def DbindSafe (Γ : Ctx) (x : Var) : Prop :=
  ∀ v E, Γ v = some E → E.dbind = true → E.mode.ownSlot = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
    ∀ d ∈ E.vdeps, d.kind.isName = false → d.root ≠ x

theorem DbindSafe.of_none {Γ : Ctx} (h : ∀ v E, Γ v = some E → E.dbind = false) (x : Var) :
    DbindSafe Γ x :=
  fun v E hE hd => by rw [h v E hE] at hd; cases hd

/-- Agora #633: `x`, if `letd` made it, views nothing of its own in memory:
    what `DbindSafe Γ x` asks of `x` itself.  A destructor frame keeps it for
    its binding (`StmtT.scopeD`): the glue its end calls takes the binding as
    a `sink` argument, which reaches nothing of itself (`CallT`). -/
def DSelf (Γ : Ctx) (x : Var) : Prop :=
  ∀ E, Γ x = some E → E.dbind = true → E.mode.ownSlot = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
    ∀ d ∈ E.vdeps, d.kind.isName = false → d.root ≠ x

theorem DbindSafe.self {Γ : Ctx} {x : Var} (h : DbindSafe Γ x) : DSelf Γ x :=
  fun E hE => h x E hE

theorem DSelf.of_dbind {Γ : Ctx} {x : Var} (h : ∀ E, Γ x = some E → E.dbind = false) : DSelf Γ x :=
  fun E hE hd => by rw [h E hE] at hd; cases hd

/-- A2-drop.2: ... and every one in `Γ`, outside `sp`, is one in `Γ'`: a
    binding never stops being `letd`'s. -/
def DStay (Γ Γ' : Ctx) (sp : List Var) : Prop :=
  ∀ v E, Γ v = some E → E.dbind = true → E.mode.ownSlot = true → v ∉ sp →
    ∃ E', Γ' v = some E' ∧ E'.dbind = true ∧ E'.mode.ownSlot = true

theorem DStay.refl (Γ : Ctx) (sp : List Var) : DStay Γ Γ sp :=
  fun _ E hv hd hos _ => ⟨E, hv, hd, hos⟩

theorem DStay.trans {Γ1 Γ2 Γ3 : Ctx} {sp sp' : List Var} (h1 : DStay Γ1 Γ2 sp) (h2 : DStay Γ2 Γ3 sp')
    (hsp : ∀ v, v ∉ sp → v ∉ sp') : DStay Γ1 Γ3 sp := fun v E hv hd hos hvs => by
  obtain ⟨E2, h2v, hd2, hos2⟩ := h1 v E hv hd hos hvs
  exact h2 v E2 h2v hd2 hos2 (hsp v hvs)

theorem DStay.mono {Γ Γ' : Ctx} {sp sp' : List Var} (h : DStay Γ Γ' sp) (hsp : ∀ v, v ∉ sp' → v ∉ sp) :
    DStay Γ Γ' sp' := fun v E hv hd hos hvs => h v E hv hd hos (hsp v hvs)

/-- A2-drop.2: every binding `letd` made in `Γ'`, outside `sp`, was one in
    `Γ`, and views no more in memory: a destructor binding gains no view. -/
def DKeep (Γ Γ' : Ctx) (sp : List Var) : Prop :=
  ∀ v E', Γ' v = some E' → E'.dbind = true → E'.mode.ownSlot = true → (E'.ty ≠ .int ∨ E'.mode = .rootb) →
    v ∉ sp → ∃ E, Γ v = some E ∧ E.dbind = true ∧ E.mode.ownSlot = true ∧
      (E.ty ≠ .int ∨ E.mode = .rootb) ∧ ∀ d ∈ E'.vdeps, d.kind.isName = false → d ∈ E.vdeps

theorem DKeep.refl (Γ : Ctx) (sp : List Var) : DKeep Γ Γ sp :=
  fun _ E hv hd hos hn _ => ⟨E, hv, hd, hos, hn, fun _ h _ => h⟩

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
      `letd` may be armed again (the maybe-moved join), and what it views in
      memory is what the value `letd` gave it views, so no weakening adds to
      it. -/
  dbind : E'.dbind = E.dbind
  raise : E'.dtor = true → E.dtor = true ∨ E.dbind = true
  dheld : E.dbind = true → E.mode.ownSlot = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
            ∀ d, d.kind.isName = false → (d ∈ E'.held ↔ d ∈ E.held)

/-- A context's live entries depend only on roots it has.  (An integer's
    dependencies say nothing: it holds no memory.)  A2-drop.2: so does, in
    memory, an owner that may run a destructor, live or not: its views are
    what the destructor will read. -/
structure CtxWF (Γ : Ctx) : Prop where
  live : ∀ v E, Γ v = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) → ∀ r ∈ roots E.vdeps,
    ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true
  dtor : ∀ v E, Γ v = some E → E.dbind = true → E.mode.ownSlot = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
    ∀ d ∈ E.vdeps, d.kind.isName = false → ∃ Er, Γ d.root = some Er ∧ Er.mode.isRoot = true
  /-- ... and only a binding `letd` made may run one ... -/
  arm  : ∀ v E, Γ v = some E → E.dtor = true → E.dbind = true
  /-- ... of a type that holds views. -/
  view : ∀ v E, Γ v = some E → E.dbind = true → E.ty.holdsView = true

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

/-- What `letd` may add to what its binding records views no closure by name. -/
theorem NameOK.widen {Γ : Ctx} {E : Entry} {H : List Dep} (h : NameOK Γ E) (hmo : E.mode = .own)
    (hH : HeldUp Γ E H) : NameOK Γ { E with held := H } := by
  have hos : E.mode.ownSlot = true := by rw [hmo]; rfl
  intro d hd b t hk
  have hd' : d ∈ H := by simpa [Entry.vdeps, hos] using hd
  rcases hH.2 d hd' with hd | ⟨hnm, _⟩
  · exact h d (by simp [Entry.vdeps, hos, hd]) b t hk
  · rw [hk] at hnm; simp [Kind.isName] at hnm

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
      -- (Agora #632: through a destructor type too, as `getl` / `getr` lend)
      Γ x = some E → E.live = true → E.ty.undtor = .sum a b → ExprT Γ (.isl x)

/-- An element read out of `y` (entry `E`), of type `t`: an integer is
    copied, a stored view is copied with what it depends on, an element
    `Vec` is lent. -/
def elemE (y : Var) (E : Entry) : Ty → Entry
  | .int => intE
  | .slice s => ⟨.slice s, .bor, true, E.held, E.held, false, false⟩
  | .vec s => ⟨.vec s, .bor, true, derive y E .inner, E.held, false, false⟩
  | .prod a b => ⟨.prod a b, .bor, true, derive y E .inner, E.held, false, false⟩
  | .sum a b => ⟨.sum a b, .bor, true, derive y E .inner, E.held, false, false⟩
  | .fn ms q => ⟨.fn ms q, .bor, true, derive y E .inner, E.held, false, false⟩
  | .arc t => ⟨.arc t, .bor, true, derive y E .inner, E.held, false, false⟩
  | .lk t => ⟨.lk t, .bor, true, derive y E .inner, E.held, false, false⟩
  | .cell t => ⟨.cell t, .bor, true, derive y E .inner, E.held, false, false⟩
  | .dtor f t => ⟨.dtor f t, .bor, true, derive y E .inner, E.held, false, false⟩

/-- An element moved out of `y` by `vec_pop`: an element `Vec` or struct is
    owned. -/
def popE (y : Var) (E : Entry) : Ty → Entry
  | .vec s => ⟨.vec s, .own, true, [], E.held, false, false⟩
  | .prod a b => ⟨.prod a b, .own, true, [], E.held, false, false⟩
  | .sum a b => ⟨.sum a b, .own, true, [], E.held, false, false⟩
  | .fn ms q => ⟨.fn ms q, .own, true, [], E.held, false, false⟩
  | .arc t => ⟨.arc t, .own, true, [], E.held, false, false⟩
  | .lk t => ⟨.lk t, .own, true, [], E.held, false, false⟩
  | .cell t => ⟨.cell t, .own, true, [], E.held, false, false⟩
  | .dtor f t => ⟨.dtor f t, .own, true, [], E.held, false, false⟩
  | t => elemE y E t

/-- Agora #607: what moves out of a drained `Vec` is owned, at its own type. -/
@[simp] theorem popE_nest (y : Var) (E : Entry) (n f : Nat) (t : Ty) :
    popE y E (Ty.nest n (.dtor f t)) = ⟨Ty.nest n (.dtor f t), .own, true, [], E.held, false, false⟩ := by
  cases n <;> rfl

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

/-- A field read is lent (A2-drop.3a: so `letv` binds it, whatever its type). -/
@[simp] theorem projE_mode (y : Var) (E : Entry) (t : Ty) : (projE y E t).mode = .bor := by
  cases t <;> rfl

/-- A3.1: `arc_get y`'s payload, lent: a borrow through a share
    (`Kind.share`) of `y`, which a borrowed share passes on (`derive`). It
    ends with `y` like any borrow, and a change through a borrow refuses
    it (`ThruOK`): what it reaches lies in a block's payload, which nothing
    writes. -/
def getE (y : Var) (E : Entry) : Ty → Entry
  | .int => intE
  | t => ⟨t, .bor, true, derive y E .share, E.held, false, false⟩

/-- A3.3: `rguard_get g` of a read guard `g` (`rw_read`'s owned share, of
    type `arc (prod (lk t) t)`, holding nothing) is `arcGet g` and then its
    second field: what it lends of the payload depends on `g` through a
    share, and on nothing else.  So `ThruOK` and `canDo` refuse every change
    through it (a copy of it is a borrow too, which `paramOK` refuses as an
    `inout` argument), and the guard's scope ends it (`exitScope g`). -/
theorem rguard_get_path {t : Ty} (ht : t ≠ .int) (g y : Var) :
    (projE y (getE g ⟨.arc (.prod (.lk t) t), .own, true, [], [], false, false⟩ (.prod (.lk t) t)) t).path =
      [⟨g, .share⟩] := by
  cases t <;> simp_all [projE, getE, derive, projDeps, rootKind, Mode.isRoot, Mode.ownSlot]

/-- A3.2/A3.5: `E` holds a share of a lock block whose payload is a `t`, which
    `withLock` checks out: a lock share, or a cell share (A3.5's third cut:
    an owner's, or a borrowed root's, a library's `in` handle parameter; a
    lent cell share is the share, `lendOf`).  `withLock` asks a root. -/
def Entry.lockOf (E : Entry) (t : Ty) : Prop :=
  E.ty = .lk t ∨ E.ty = .cell t

/-- A3.2: the binding a lock's payload is checked out to (`withLock`): owned,
    holding nothing (a payload views nothing); an integer is a plain integer
    binding, as `unpair` binds an integer field. -/
def lockE (t : Ty) : Entry := if t = .int then intE else ⟨t, .own, true, [], [], false, false⟩

@[simp] theorem lockE_dtor (t : Ty) : (lockE t).dtor = false := by unfold lockE; split <;> rfl
@[simp] theorem lockE_dbind (t : Ty) : (lockE t).dbind = false := by unfold lockE; split <;> rfl
@[simp] theorem lockE_ty (t : Ty) : (lockE t).ty = t := by unfold lockE; split <;> simp_all [intE]
@[simp] theorem lockE_live (t : Ty) : (lockE t).live = true := by unfold lockE; split <;> rfl
@[simp] theorem lockE_path (t : Ty) : (lockE t).path = [] := by unfold lockE; split <;> rfl
@[simp] theorem lockE_held (t : Ty) : (lockE t).held = [] := by unfold lockE; split <;> rfl
@[simp] theorem lockE_vdeps (t : Ty) : (lockE t).vdeps = [] := by
  unfold lockE; split <;> simp [Entry.vdeps, intE, Mode.ownSlot]

/-- What an owned value holds: nothing, if its type holds no views (no view
    and no closure lies inside it, so what it was made from says nothing). -/
def ownHeld (o : Bool) (t : Ty) (H : List Dep) : List Dep := if o && !t.holdsView then [] else H

/-- A field moved out of a struct that is taken apart. -/
def compE (E : Entry) : Ty → Entry
  | .int => intE
  | .slice s => ⟨.slice s, .bor, true, E.held, E.held, false, false⟩
  | t => ⟨t, .own, true, [], ownHeld true t E.held, false, false⟩

/-- What `takel` / `taker` take a payload out of is an enum under its
    destructor type, if any. -/
theorem take_undtor {τ a b : Ty} {G : Nat → Prop} (h : τ = .sum a b ∨ ∃ f, τ = .dtor f (.sum a b) ∧ G f) :
    τ.undtor = .sum a b := by
  rcases h with h | ⟨f, h, _⟩ <;> subst h <;> rfl

theorem take_ne_int {τ a b : Ty} {G : Nat → Prop} (h : τ = .sum a b ∨ ∃ f, τ = .dtor f (.sum a b) ∧ G f) :
    τ ≠ .int := by
  rcases h with h | ⟨f, h, _⟩ <;> subst h <;> simp

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
@[simp] theorem getE_dtor (y : Var) (E : Entry) (t : Ty) : (getE y E t).dtor = false := by
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
@[simp] theorem getE_dbind (y : Var) (E : Entry) (t : Ty) : (getE y E t).dbind = false := by
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
  | new {t : Ty} : (Ty.vec t).ok = true →  -- (A2-drop.3b: its elements hold no destructor value)
      RhsT Γ F (.new t) ⟨.vec t, .own, true, [], [], false, false⟩ Γ
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
  /-- A3.5b, subsumption: an owned closure moved as one of a class above its
      own (`Cross.Le`): a `sync` one where a `send` or an `any` one is
      declared.  The step is `moveOwn`'s; only the type forgets where the
      closure may cross. -/
  | moveUp {y : Var} {E : Entry} {ms : List Nat} {q q' : Cross} :
      Γ y = some E → E.live = true → E.mode = .own → y ∉ F → NoPin Γ y → DtorSafe Γ .replace false y →
      E.ty = .fn ms q → q.Le q' →
      RhsT Γ F (.var y) ⟨.fn ms q', .own, true, [], E.held, false, false⟩
        (setE (kill .replace false y Γ) y { E with live := false, dtor := false })
  /-- ... and a borrowed closure copied as one of a class above its own (the
      step is `copyBor`'s). -/
  | copyUp {y : Var} {E : Entry} {ms : List Nat} {q q' : Cross} :
      Γ y = some E → E.live = true → E.mode = .bor → E.ty = .fn ms q → q.Le q' →
      RhsT Γ F (.var y) { E with ty := .fn ms q', dtor := false, dbind := false } Γ
  | borrow {y : Var} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .vec t →
      RhsT Γ F (.borrow y) ⟨E.ty, .bor, true, derive y E .self, E.held, false, false⟩ Γ
  | at {y : Var} {i : Expr} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .vec t → ExprT Γ i →
      RhsT Γ F (.at y i) (elemE y E t) Γ
  | view {y : Var} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .vec t → t.holdsView = false →
      -- (A3.1's slices of shares: its elements may be shares, lent as
      -- `vec_at` lends them)
      RhsT Γ F (.view y) ⟨.slice t, .bor, true, derive y E .view, E.held, false, false⟩ Γ
  | sat {y : Var} {i : Expr} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .slice t → ExprT Γ i →
      RhsT Γ F (.sat y i) (elemE y E t) Γ
  | pop {y : Var} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .vec t → canDo E.mode .drop → y ∉ F →
      DtorSafe Γ .drop t.holdsView y →
      RhsT Γ F (.pop y) (popE y E t) (kill .drop t.holdsView y Γ)
  /-- `vec_remove y i`, typed as `vec_pop` (the element moves out; which
      one is no part of the typing, `MInv.perm`). A2-drop.3b: the drain's
      `vec_remove y 0`; Agora #607: any index. -/
  | remove {y : Var} {i : Expr} {E : Entry} {t : Ty} :
      Γ y = some E → E.live = true → E.ty = .vec t → canDo E.mode .drop → y ∉ F →
      DtorSafe Γ .drop t.holdsView y → ExprT Γ i →
      RhsT Γ F (.remove y i) (popE y E t) (kill .drop t.holdsView y Γ)
  | pair {y z : Var} {Ey Ez : Entry} {Γ1 Γ2 : Ctx} {Dy Dz : List Dep} :
      Γ y = some Ey → Ey.live = true → PushArg Γ F y Ey Ey.ty Dy Γ1 →
      Γ1 z = some Ez → Ez.live = true → PushArg Γ1 F z Ez Ez.ty Dz Γ2 →
      (Ez.mode.ownSlot = true → z ∉ roots Dy) →
      RhsT Γ F (.pair y z) ⟨.prod Ey.ty Ez.ty, .own, true, [], Dy ++ Dz, false, false⟩ Γ2
  | fst {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.ty.undtor = .prod a b → RhsT Γ F (.fst y) (projE y E a) Γ
  | snd {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.ty.undtor = .prod a b → RhsT Γ F (.snd y) (projE y E b) Γ
  | inl {y : Var} {b : Ty} {Ey : Entry} {Γ1 : Ctx} {D : List Dep} :
      Γ y = some Ey → Ey.live = true → PushArg Γ F y Ey Ey.ty D Γ1 → b.ok = true →
      RhsT Γ F (.inl y b) ⟨.sum Ey.ty b, .own, true, [], D, false, false⟩ Γ1
  | inr {a : Ty} {y : Var} {Ey : Entry} {Γ1 : Ctx} {D : List Dep} :
      Γ y = some Ey → Ey.live = true → PushArg Γ F y Ey Ey.ty D Γ1 → a.ok = true →
      RhsT Γ F (.inr a y) ⟨.sum a Ey.ty, .own, true, [], D, false, false⟩ Γ1
  -- (A2-drop.3a: a payload of a destructor enum is lent through the type,
  -- as a field of a destructor struct is; the destructor stays with the
  -- whole value.  Taking one out, `takel` / `taker`, stays refused there:
  -- the enum's destructor would never run.)
  | getl {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.ty.undtor = .sum a b → RhsT Γ F (.getl y) (projE y E a) Γ
  | getr {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.ty.undtor = .sum a b → RhsT Γ F (.getr y) (projE y E b) Γ
  | takel {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.mode = .own →
      -- (Agora #632: or an enum under its destructor type, the payload one
      -- that holds a destructor value: the statement that binds it, `letd` or
      -- `assign`, asks that the enum's destructor is its glue, `TakeOK`)
      (E.ty = .sum a b ∨ ∃ f, E.ty = .dtor f (.sum a b) ∧ a.holdsDtor = true) → y ∉ F → NoPin Γ y →
      DtorSafe Γ .replace false y →
      RhsT Γ F (.takel y) (compE E a) (setE (kill .replace false y Γ) y { E with live := false, dtor := false })
  | taker {y : Var} {E : Entry} {a b : Ty} :
      Γ y = some E → E.live = true → E.mode = .own →
      (E.ty = .sum a b ∨ ∃ f, E.ty = .dtor f (.sum a b) ∧ b.holdsDtor = true) → y ∉ F → NoPin Γ y →
      DtorSafe Γ .replace false y →
      RhsT Γ F (.taker y) (compE E b) (setE (kill .replace false y Γ) y { E with live := false, dtor := false })
  /-- A closure literal.  A3.5b: its type says what its environment may hold
      (`q`), from the environment's type and the captures by name
      (`Cross.Fits`): one that holds no view and captures nothing by name is
      Send (a spawn's, and since A3.5's second cut a lock's or a channel's),
      one that also holds no cell share Sync (an `Arc`'s), one that holds no
      share at all bare. -/
  | pack {fs : List Nat} {te : Ty} {ms : List Nat} {q : Cross} {y : Var} {cs : List (Var × PMode × Ty)}
      {Ey : Entry} {Γ1 : Ctx} {D : List Dep} :
      Γ y = some Ey → Ey.live = true → Ey.ty = te → PushArg Γ F y Ey te D Γ1 → CapsOK Γ1 F D cs →
      q.Fits te cs →
      -- (a closure the environment holds that may change a binding by name:
      -- running this package changes it, its name is among what it holds)
      RhsT Γ F (.pack fs te ms y cs) ⟨.fn ms q, .own, true, [], D ++ capDeps cs, false, false⟩ Γ1
  /-- A3.1: `y`'s value, of a type that holds no view and no closure, moves
      into a fresh block (an owner moves its tree, which becomes the block's
      payload; an integer is copied); the result is an owned share, which
      holds nothing (the payload views nothing). -/
  | arcNew {t : Ty} {y : Var} {Ey : Entry} {Γ1 : Ctx} {D : List Dep} :
      Γ y = some Ey → Ey.live = true → Ey.ty = t →
      -- (A2-drop.3d: a block's payload owns no destructor value, or (Agora
      -- #610) is one at its top, which the sweep hands to a destructor frame
      -- of the thread whose step leaves its block unreached, `Mem.sweepD`, or
      -- (Agora #755) a drained `Vec` of them at any depth, `Ty.dnest`, which
      -- that frame drains)
      (t.dtorFree = true ∨ t.dnest = true) → t.holdsView = false ∧ t.hasFn = false →
      -- A3.5: an `Arc`'s payload is reached from every thread that holds a
      -- share, so it holds no library handle (a cell share is not Sync)
      t.hasCell = false →
      PushArg Γ F y Ey t D Γ1 →
      RhsT Γ F (.arcNew t y) ⟨.arc t, .own, true, [], [], false, false⟩ Γ1
  /-- A3.1: a new share of the block `a` shares: owned, holding nothing. -/
  | arcClone {a : Var} {E : Entry} {t : Ty} :
      Γ a = some E → E.live = true → E.ty = .arc t →
      RhsT Γ F (.arcClone a) ⟨.arc t, .own, true, [], [], false, false⟩ Γ
  /-- A3.1: the payload, lent through a share of `a` (`getE`), so it ends
      with `a` like any borrow. A handle into the payload lands through that
      share (`Landed`), so it is valid while the block lives. The payload
      holds no view and no closure. -/
  | arcGet {a : Var} {E : Entry} {t : Ty} :
      Γ a = some E → E.live = true → E.ty = .arc t → t.holdsView = false → t.hasFn = false →
      RhsT Γ F (.arcGet a) (getE a E t) Γ
  /-- A3.2: `locked_new`: `y`'s value, of a type that holds no view and no
      closure that holds bindings by name (it is Send) — `arc`, lock and
      (A3.5's second cut) cell shares it may hold, which the lock's block
      keeps alive, a cell share past the crossing check (`EvalR.lockNew`) —
      moves into a fresh lock block; the result is an owned lock share, which
      holds nothing. -/
  | lockNew {t : Ty} {y : Var} {Ey : Entry} {Γ1 : Ctx} {D : List Dep} :
      Γ y = some Ey → Ey.live = true → Ey.ty = t →
      t.dtorFree = true → t.holdsView = false ∧ t.hasFn = false →
      PushArg Γ F y Ey t D Γ1 →
      RhsT Γ F (.lockNew t y) ⟨.lk t, .own, true, [], [], false, false⟩ Γ1
  /-- A3.2: `Locked_share`: a new share of the lock block `a` shares: owned,
      holding nothing. -/
  | lockClone {a : Var} {E : Entry} {t : Ty} :
      Γ a = some E → E.live = true → E.ty = .lk t →
      RhsT Γ F (.lockClone a) ⟨.lk t, .own, true, [], [], false, false⟩ Γ
  /-- A3.3: `rw_read a`: a read guard of the lock (an `RwLocked`) `a` (a
      live share) shares: an owned `arc` share of a new view of its payload,
      holding nothing.  What `arcGet` lends through it is frozen (`getE`'s
      `share` dependency, which `ThruOK` and `canDo` refuse every change
      through) and ends with the guard. -/
  | rwRead {a : Var} {E : Entry} {t : Ty} :
      Γ a = some E → E.live = true → E.ty = .lk t →
      -- A3.5's second cut: read guards lend the value to several threads at
      -- once, so it faces the Sync question, as an `Arc`'s payload does (h357)
      t.hasCell = false →
      RhsT Γ F (.rwRead a) ⟨.arc (.prod (.lk t) t), .own, true, [], [], false, false⟩ Γ
  /-- A3.3: `rw_try_read a`: `rw_read`'s guard as an owned option
      (`Option` is `sum int _`), holding nothing; matched by value
      (`taker`), its `some` is `rw_read`'s entry.  A read guard lends the
      payload to every reader at once, so the payload holds no library handle
      (a cell share is not Sync, A3.5). -/
  | rwTryRead {a : Var} {E : Entry} {t : Ty} :
      Γ a = some E → E.live = true → E.ty = .lk t → t.hasCell = false →
      RhsT Γ F (.rwTryRead a) ⟨.sum .int (.arc (.prod (.lk t) t)), .own, true, [], [], false, false⟩ Γ
  /-- A3.3: `rw_try_write a`'s answer: an owned option of an integer, holding
      nothing; the write itself is `withLock`'s check-out (`Stmt.withTryWrite`). -/
  | rwTryWrite {a : Var} {E : Entry} {t : Ty} :
      Γ a = some E → E.live = true → E.ty = .lk t →
      RhsT Γ F (.rwTryWrite a) ⟨.sum .int .int, .own, true, [], [], false, false⟩ Γ
  /-- A3.4: an `Atomic`'s operation, through a live share of an integer lock
      block (`Atomic` is `lk int`): an integer. -/
  | atomic {op : AOp} {a : Var} {e1 e2 : Expr} {E : Entry} :
      Γ a = some E → E.live = true → E.ty = .lk .int → ExprT Γ e1 → ExprT Γ e2 →
      RhsT Γ F (.atomic op a e1 e2) intE Γ
  /-- A3.4: `chan_send a y`, through a live share of a channel of `s`:
      `y`'s value, an `s` (which holds no view: `Ty.ok`, as a lock's payload;
      A3.5's second cut: a cell share it may hold, past the crossing check,
      `EvalR.chanSend`), is handed over as `vec_push` takes it (`PushArg`: an
      owner moves, an integer is copied); the answer is an integer. -/
  | chanSend {a y : Var} {Ea Ey : Entry} {s : Ty} {Γ1 : Ctx} {D : List Dep} :
      Γ a = some Ea → Ea.live = true → Ea.ty = .lk (.prod (.vec s) .int) →
      Γ y = some Ey → Ey.live = true → Ey.ty = s → PushArg Γ F y Ey s D Γ1 →
      RhsT Γ F (.chanSend a y) intE Γ1
  /-- A3.4: `chan_recv` / `chan_try_recv`, through a live share of a channel
      (`Channel s` is `lk (prod (vec s) int)`: its queue and its flag): an
      owned `Option s` (`sum int s`), holding nothing (`s` holds no view:
      `Ty.ok`; the shares it holds the queue's block kept alive). -/
  | chanRecv {w : Bool} {a : Var} {E : Entry} {s : Ty} :
      Γ a = some E → E.live = true → E.ty = .lk (.prod (.vec s) .int) →
      RhsT Γ F (.chanRecv w a) ⟨.sum .int s, .own, true, [], [], false, false⟩ Γ
  /-- A3.4: `chan_close`, through a live share of a channel. -/
  | chanClose {a : Var} {E : Entry} {s : Ty} :
      Γ a = some E → E.live = true → E.ty = .lk (.prod (.vec s) .int) →
      RhsT Γ F (.chanClose a) intE Γ
  /-- A3.5: a library handle's constructor: `y`'s value, of a type that holds
      no view and no closure that holds bindings by name (a lock's payload:
      A3.5's second cut, shares it may hold, a cell share past the crossing
      check, `EvalR.cellNew`), moves into a fresh lock block; the result is an
      owned cell share, which holds nothing. -/
  | cellNew {t : Ty} {y : Var} {Ey : Entry} {Γ1 : Ctx} {D : List Dep} :
      Γ y = some Ey → Ey.live = true → Ey.ty = t →
      t.dtorFree = true → t.holdsView = false ∧ t.hasFn = false →
      PushArg Γ F y Ey t D Γ1 →
      RhsT Γ F (.cellNew t y) ⟨.cell t, .own, true, [], [], false, false⟩ Γ1
  /-- A3.5: a copy of a library handle (`PNCounter_share`): a new owned cell
      share, from one a live binding holds — an owner's, or (A3.5's third
      cut) a borrow's: a lent cell share is the share (`lendOf`), as the
      runtime's `PNCounter_share` copies a handle it was lent. -/
  | cellClone {a : Var} {E : Entry} {t : Ty} :
      Γ a = some E → E.live = true → E.ty = .cell t →
      RhsT Γ F (.cellClone a) ⟨.cell t, .own, true, [], [], false, false⟩ Γ
  /-- A3.6: a read of a module global set at start: an owned share of its
      block, holding nothing (a clone of the global's handle, which the global
      keeps).  Its type synchronises itself (`Ty.sync`: a lock share, or an
      `Arc` of no library handle), so a global is never a `Vec` (h263), a
      cell share or any owned tree; and no rule writes a global. -/
  | glob {g : Nat} {t : Ty} :
      t.sync = true → t.ok = true →
      RhsT Γ F (.glob g t) ⟨t, .own, true, [], [], false, false⟩ Γ
  /-- A3.2's second cut: `locked_take a`, through a live lock share of a
      `Locked t`: the payload, owned, of its type, holding nothing (it views
      nothing; its shares the block kept alive) — `withLock`'s `lockE t`
      (an integer is a plain integer). -/
  | lockTake {a : Var} {E : Entry} {t : Ty} :
      Γ a = some E → E.live = true → E.ty = .lk t →
      RhsT Γ F (.lockTake a) (lockE t) Γ
  /-- ... `locked_restore a y`: `y`'s value, a `t`, is handed back as
      `vec_push` takes it (`PushArg`: an owner moves and its entry dies, an
      integer is copied), as `chan_send` hands its value over; the answer is
      an integer. -/
  | lockRestore {a y : Var} {Ea Ey : Entry} {t : Ty} {Γ1 : Ctx} {D : List Dep} :
      Γ a = some Ea → Ea.live = true → Ea.ty = .lk t →
      Γ y = some Ey → Ey.live = true → Ey.ty = t → PushArg Γ F y Ey t D Γ1 →
      RhsT Γ F (.lockRestore a y) intE Γ1

/-! ### Calls -/

/-- A2-drop.2: a right-hand side makes a value no binding has made its own
    yet: it runs no destructor (only `letd` arms a binding). -/
theorem RhsT.dtor_false {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (h : RhsT Γ F r E Γ1) :
    E.dtor = false ∧ E.dbind = false := by
  cases h <;> simp

theorem RhsT.out {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1) :
    (E.mode = .own ∨ E.mode = .bor) ∧ E.live = true := by
  cases hr with
  | expr => exact ⟨Or.inr rfl, rfl⟩
  | new => exact ⟨Or.inl rfl, rfl⟩
  | moveOwn => exact ⟨Or.inl rfl, rfl⟩
  | copyRoot => exact ⟨Or.inr rfl, rfl⟩
  | copyBor _ hl hm => exact ⟨Or.inr hm, hl⟩
  | moveUp => exact ⟨Or.inl rfl, rfl⟩
  | copyUp _ hl hm => exact ⟨Or.inr hm, hl⟩
  | borrow => exact ⟨Or.inr rfl, rfl⟩
  | @«at» _ _ _ t => cases t <;> exact ⟨Or.inr rfl, rfl⟩
  | view => exact ⟨Or.inr rfl, rfl⟩
  | @sat _ _ _ t => cases t <;> exact ⟨Or.inr rfl, rfl⟩
  | @pop _ _ t => cases t <;> first | exact ⟨Or.inl rfl, rfl⟩ | exact ⟨Or.inr rfl, rfl⟩
  | @remove _ _ _ t => cases t <;> first | exact ⟨Or.inl rfl, rfl⟩ | exact ⟨Or.inr rfl, rfl⟩
  | pair => exact ⟨Or.inl rfl, rfl⟩
  | @fst _ _ a => cases a <;> exact ⟨Or.inr rfl, rfl⟩
  | @snd _ _ _ b => cases b <;> exact ⟨Or.inr rfl, rfl⟩
  | inl => exact ⟨Or.inl rfl, rfl⟩
  | inr => exact ⟨Or.inl rfl, rfl⟩
  | pack => exact ⟨Or.inl rfl, rfl⟩
  | @getl _ _ a => cases a <;> exact ⟨Or.inr rfl, rfl⟩
  | @getr _ _ _ b => cases b <;> exact ⟨Or.inr rfl, rfl⟩
  | @takel _ _ a => cases a <;> first | exact ⟨Or.inl rfl, rfl⟩ | exact ⟨Or.inr rfl, rfl⟩
  | @taker _ _ _ b => cases b <;> first | exact ⟨Or.inl rfl, rfl⟩ | exact ⟨Or.inr rfl, rfl⟩
  | arcNew => exact ⟨Or.inl rfl, rfl⟩
  | arcClone => exact ⟨Or.inl rfl, rfl⟩
  | @arcGet _ _ t => cases t <;> exact ⟨Or.inr rfl, rfl⟩
  | lockNew => exact ⟨Or.inl rfl, rfl⟩
  | lockClone => exact ⟨Or.inl rfl, rfl⟩
  | rwRead => exact ⟨Or.inl rfl, rfl⟩
  | rwTryRead => exact ⟨Or.inl rfl, rfl⟩
  | rwTryWrite => exact ⟨Or.inl rfl, rfl⟩
  | atomic => exact ⟨Or.inr rfl, rfl⟩
  | chanSend => exact ⟨Or.inr rfl, rfl⟩
  | chanRecv => exact ⟨Or.inl rfl, rfl⟩
  | chanClose => exact ⟨Or.inr rfl, rfl⟩
  | cellNew => exact ⟨Or.inl rfl, rfl⟩
  | cellClone => exact ⟨Or.inl rfl, rfl⟩
  | glob => exact ⟨Or.inl rfl, rfl⟩
  | @lockTake _ _ t => unfold lockE; split <;> first | exact ⟨Or.inl rfl, rfl⟩ | exact ⟨Or.inr rfl, rfl⟩
  | lockRestore => exact ⟨Or.inr rfl, rfl⟩

/-- What the summary pair `(j, k)` means at this call.  An integer argument
    lends nothing. -/
def argDeps (Γ : Ctx) (args : List Var) (jk : Nat × Kind) : List Dep :=
  if (argE Γ (args.getD jk.1 0)).ty = .int then []
  else derive (args.getD jk.1 0) (argE Γ (args.getD jk.1 0)) jk.2

/-- Every dependency of every kind on the given roots. -/
def allKinds (rs : List Var) : List Dep :=
  rs.flatMap (fun r => [⟨r, .self⟩, ⟨r, .inner⟩, ⟨r, .view⟩, ⟨r, .share⟩])


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
  -- a binding `letd` made is not handed over `inout`: the call's renaming
  -- gives an argument the callee's parameter entry back, which is no such
  -- binding (A2-drop.2; a gap of the claim, nurlc allows it)
  (∀ i (h : i < ps.length) b, ps[i].1 = .inout b → ∀ Ea, Γ (args.getD i 0) = some Ea →
    Ea.dbind = false)

/-- With no binding that runs a destructor, every call is safe. -/
theorem CallDtorSafe.of_none {Γ : Ctx} (h : ∀ v E, Γ v = some E → E.dtor = false ∧ E.dbind = false)
    (ps : List (PMode × Ty)) (args : List Var) : CallDtorSafe Γ ps args :=
  ⟨fun _ _ => ⟨fun _ => DtorSafe.of_none (fun v E hE => (h v E hE).1) _ _ _,
      fun _ _ => DtorSafe.of_none (fun v E hE => (h v E hE).1) _ _ _⟩,
    fun _ _ => DtorSafe.of_none (fun v E hE => (h v E hE).1) _ _ _,
    fun _ _ _ _ Ea hEa => (h _ Ea hEa).2⟩

/-- A call that only borrows, and kills nothing by name, is safe. -/
theorem CallDtorSafe.of_inp {Γ : Ctx} {ps : List (PMode × Ty)} {args : List Var}
    (hp : ∀ q ∈ ps, q.1 = .inp) (hn : mutNames Γ args = []) : CallDtorSafe Γ ps args := by
  refine ⟨fun i hi => ⟨fun hs => ?_, fun b hb => ?_⟩, fun d hd => ?_, fun i hi b hb => ?_⟩
  · have := hp _ (List.getElem_mem hi); rw [hs] at this; cases this
  · have := hp _ (List.getElem_mem hi); rw [hb] at this; cases this
  · rw [hn] at hd; cases hd
  · have := hp _ (List.getElem_mem hi); rw [hb] at this; cases this

/-- The roots of what the arguments hold views of. -/
def callR (Γ : Ctx) (args : List Var) : List Var :=
  args.flatMap (fun a => if (argE Γ a).ty = .int then [] else roots (memDeps (argE Γ a).held))

theorem mem_callR {Γ : Ctx} {args : List Var} {r : Var} :
    r ∈ callR Γ args ↔ ∃ a ∈ args, (argE Γ a).ty ≠ .int ∧ r ∈ roots (memDeps (argE Γ a).held) := by
  unfold callR
  simp only [List.mem_flatMap]
  constructor
  · rintro ⟨a, ha, hr⟩; split at hr
    · simp at hr
    · exact ⟨a, ha, by assumption, hr⟩
  · rintro ⟨a, ha, hn, hr⟩; exact ⟨a, ha, by rw [ite_eq_right hn]; exact hr⟩

/-! ### Changes of elements through a borrow (Agora #295) -/

/-- What a change of elements through a borrow does to a root it reaches,
    by the kind of the borrow's dependency on it: a push through a copy of
    the root's own handle (`.self`), the root of the borrow's own type
    (`sameTy`), is the root's own push (the borrowed `Vec` is the root's
    whole tree): `.realloc`. Anything else (a truncation, an element set)
    may change the elements of any node of the root's tree: `.drop`. -/
def Edit.effAt : Edit → Kind → Bool → Eff
  | .push _, k, sameTy => if k = .self ∧ sameTy = true then .realloc else .drop
  | .trunc _, _, _ => .drop
  | .set _ _, _, _ => .drop

/-- The binding whose value a change of elements stores: what `push` and
    `set` are handed. -/
def Edit.stored : Edit → Option Var
  | .push y => some y
  | .trunc _ => none
  | .set _ y => some y

theorem Edit.effAt_ne_replace (op : Edit) (k : Kind) (s : Bool) : op.effAt k s ≠ .replace := by
  cases op with
  | push => simp only [Edit.effAt]; split <;> simp
  | trunc => simp [Edit.effAt]
  | set => simp [Edit.effAt]

theorem Edit.effAt_ne_none (op : Edit) (k : Kind) (s : Bool) : op.effAt k s ≠ .none := by
  cases op with
  | push => simp only [Edit.effAt]; split <;> simp
  | trunc => simp [Edit.effAt]
  | set => simp [Edit.effAt]

theorem Edit.effAt_le_drop (op : Edit) (k : Kind) (s : Bool) : (op.effAt k s).le .drop := by
  cases op with
  | push => simp only [Edit.effAt]; split <;> decide
  | trunc => simp only [Edit.effAt]; decide
  | set => simp only [Edit.effAt]; decide

/-- What a change does to a root does not depend on what it is handed. -/
@[simp] theorem Edit.effAt_rename (ρ : Var → Var) (op : Edit) (k : Kind) (s : Bool) :
    (op.rename ρ).effAt k s = op.effAt k s := by
  cases op <;> rfl

/-- `.realloc` is a push through a copy of a same-typed root's handle. -/
theorem Edit.effAt_realloc {op : Edit} {k : Kind} {s : Bool} (h : op.effAt k s = .realloc) :
    (∃ y, op = .push y) ∧ k = .self ∧ s = true := by
  cases op with
  | push y =>
    simp only [Edit.effAt] at h
    split at h
    · rename_i hk; exact ⟨⟨y, rfl⟩, hk.1, hk.2⟩
    · cases h
  | trunc _ => simp [Edit.effAt] at h
  | set _ _ => simp [Edit.effAt] at h

/-- A renamed change stores what it stored, renamed. -/
@[simp] theorem Edit.drops_rename (ρ : Var → Var) (op : Edit) : (op.rename ρ).drops = op.drops := by
  cases op <;> rfl

@[simp] theorem Edit.stored_rename (ρ : Var → Var) (op : Edit) :
    (op.rename ρ).stored = op.stored.map ρ := by
  cases op <;> rfl

/-- The per-root effects of a change through a borrow whose path is `P`, of
    type `tx`: each memory root of `P`, with `Edit.effAt` of its kind, as a
    dependency by name of that bound (the `.int` is only a tag). `killNames`
    reads a dependency `⟨r, .name e _⟩` as `kill e false r`: the effect `e`
    on `r`, whose changed node's elements hold no views. So the kills of a
    change through a borrow are `killNames`, and its lemmas apply. -/
def thruDeps (op : Edit) (Γ : Ctx) (tx : Ty) (P : List Dep) : List Dep :=
  (memDeps P).map fun d => ⟨d.root, .name (op.effAt d.kind (decide ((argE Γ d.root).ty = tx))) .int⟩

/-- What a change through a borrow (of type `tx`, path `P`) ends: on each
    memory root, what its effect there ends. -/
def killThru (op : Edit) (tx : Ty) (P : List Dep) (Γ : Ctx) : Ctx :=
  killNames (thruDeps op Γ tx P) Γ

theorem mem_thruDeps {op : Edit} {Γ : Ctx} {tx : Ty} {P : List Dep} {d : Dep} :
    d ∈ thruDeps op Γ tx P ↔ ∃ d0 ∈ memDeps P, d = ⟨d0.root,
      .name (op.effAt d0.kind (decide ((argE Γ d0.root).ty = tx))) .int⟩ := by
  unfold thruDeps
  simp only [List.mem_map]
  constructor
  · rintro ⟨d0, hd0, rfl⟩; exact ⟨d0, hd0, rfl⟩
  · rintro ⟨d0, hd0, rfl⟩; exact ⟨d0, hd0, rfl⟩

/-- The kills of a change through a borrow are effects below `.replace`,
    with no views among the elements. -/
theorem thruDeps_bound {op : Edit} {Γ : Ctx} {tx : Ty} {P : List Dep} {d : Dep}
    (hd : d ∈ thruDeps op Γ tx P) : d.kind.bound ≠ .replace ∧ d.kind.bound ≠ .none ∧
      d.kind.bound.le .drop ∧ d.kind.isName = true := by
  obtain ⟨d0, _, rfl⟩ := mem_thruDeps.mp hd
  exact ⟨Edit.effAt_ne_replace _ _ _, Edit.effAt_ne_none _ _ _, Edit.effAt_le_drop _ _ _, rfl⟩

/-- What a change through a borrow of type `tx`, whose path is `P`, asks of
    each root `d.root` it reaches in memory, in the context after its
    argument is handed over: the root is not lent out, is not the value
    stored (`Edit.stored`), is live, allows its effect (`Edit.effAt`; so it
    owns its slot), and that effect ends no view a destructor will read.
    A3.1: no dependency is through a share (`Kind.share`): what such a
    borrow reaches may lie in a block's payload, which nothing writes. -/
def ThruOK (Γ1 : Ctx) (F : List Var) (op : Edit) (tx : Ty) (P : List Dep) : Prop :=
  ∀ d ∈ memDeps P, d.root ∉ F ∧ (∀ y, op.stored = some y → d.root ≠ y) ∧
    ∃ Er, Γ1 d.root = some Er ∧ Er.live = true ∧
      canDo Er.mode (op.effAt d.kind (decide (Er.ty = tx))) ∧
      DtorSafe Γ1 (op.effAt d.kind (decide (Er.ty = tx))) false d.root ∧
      d.kind ≠ .share

theorem ThruOK.noShare {Γ1 : Ctx} {F : List Var} {op : Edit} {tx : Ty} {P : List Dep}
    (h : ThruOK Γ1 F op tx P) : ∀ d ∈ memDeps P, d.kind ≠ .share := fun d hd => by
  obtain ⟨_, _, _, _, _, _, _, h⟩ := h d hd
  exact h

/-! #### A view stored through a borrow (Agora #295, `StmtT.editBV`) -/

/-- Effects run in turn, each on a binding, with whether that binding's
    elements hold views (`kill`'s `hv`). -/
def killHv : List (Eff × Bool × Var) → Ctx → Ctx
  | [], Γ => Γ
  | (e, hv, r) :: ks, Γ => kill e hv r (killHv ks Γ)

/-- The per-root effects of a change through a borrow (those of
    `thruDeps`), each with whether the root's type holds views. -/
def thruKills (op : Edit) (Γ : Ctx) (tx : Ty) (P : List Dep) : List (Eff × Bool × Var) :=
  (memDeps P).map fun d =>
    (op.effAt d.kind (decide ((argE Γ d.root).ty = tx)), (argE Γ d.root).ty.holdsView, d.root)

/-- What a change through a borrow that may store a view ends: on each
    memory root, what its effect there ends, the root's elements holding
    views if its type does, as the owner's own `push` does (`kill .realloc
    t.holdsView`): a root that may hold the view also ends the borrows of its
    whole handle, which do not hold what the view depends on. -/
def killThruV (op : Edit) (tx : Ty) (P : List Dep) (Γ : Ctx) : Ctx :=
  killHv (thruKills op Γ tx P) Γ

theorem mem_thruKills {op : Edit} {Γ : Ctx} {tx : Ty} {P : List Dep} {k : Eff × Bool × Var} :
    k ∈ thruKills op Γ tx P ↔ ∃ d ∈ memDeps P,
      k = (op.effAt d.kind (decide ((argE Γ d.root).ty = tx)), (argE Γ d.root).ty.holdsView, d.root) := by
  unfold thruKills
  simp only [List.mem_map]
  constructor
  · rintro ⟨d, hd, rfl⟩; exact ⟨d, hd, rfl⟩
  · rintro ⟨d, hd, rfl⟩; exact ⟨d, hd, rfl⟩

theorem killHv_entry {Γ : Ctx} : ∀ (ks : List (Eff × Bool × Var)) {v : Var} {E : Entry}, Γ v = some E →
    ∃ E', killHv ks Γ v = some E' ∧ (E' = E ∨ E' = { E with live := false })
  | [], _, E, hv => ⟨E, hv, Or.inl rfl⟩
  | (e, b, r) :: ks, v, E, hv => by
    obtain ⟨E1, h1, hE1⟩ := killHv_entry ks hv
    refine ⟨killE e b r E1, by show (killHv ks Γ v).map _ = _; rw [h1]; rfl, ?_⟩
    unfold killE
    split
    · rcases hE1 with rfl | rfl <;> exact Or.inr rfl
    · exact hE1

theorem killHv_isSome (ks : List (Eff × Bool × Var)) (Γ : Ctx) (v : Var) :
    (killHv ks Γ v).isSome = (Γ v).isSome := by
  induction ks with
  | nil => rfl
  | cons k ks ih =>
    obtain ⟨e, b, r⟩ := k
    show ((killHv ks Γ v).map _).isSome = _
    rw [Option.isSome_map]; exact ih

/-- What the kills leave of a binding: its mode, type, path, held and flags. -/
theorem killHv_same {Γ : Ctx} {ks : List (Eff × Bool × Var)} {v : Var} {E' : Entry}
    (h : killHv ks Γ v = some E') : ∃ E, Γ v = some E ∧ E'.mode = E.mode ∧ E'.ty = E.ty ∧
      E'.vdeps = E.vdeps ∧ E'.held = E.held ∧ E'.dtor = E.dtor ∧ E'.dbind = E.dbind ∧
      (E'.live = true → E.live = true) := by
  cases hE : Γ v with
  | none =>
    have := killHv_isSome ks Γ v
    rw [h, hE] at this; cases this
  | some E =>
    obtain ⟨E1, h1, hE1⟩ := killHv_entry ks hE
    rw [h] at h1; cases h1
    rcases hE1 with rfl | rfl
    · exact ⟨_, rfl, rfl, rfl, rfl, rfl, rfl, rfl, id⟩
    · exact ⟨_, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => by cases h⟩

/-- An entry that also holds `D`, if its type holds views (`ownHeld`: a
    value of a type that holds no views holds nothing). -/
def Entry.hold (D : List Dep) (E : Entry) : Entry := { E with held := E.held ++ ownHeld true E.ty D }

/-- The bindings of `rs` also hold `D`. -/
def holdOn (rs : List Var) (D : List Dep) (Γ : Ctx) : Ctx := fun v =>
  (Γ v).map fun E => if v ∈ rs then E.hold D else E

/-- What a change through a borrow whose path is `P` that stores a value
    depending on `D` leaves its memory roots holding: `D` too. The change
    lands in the tree of one of them, which the typing cannot tell apart
    (`MInv.thru_owner`), so each holds it, as the owner of a `push` does. -/
def holdThru (D P : List Dep) (Γ : Ctx) : Ctx := holdOn (roots (memDeps P)) D Γ

@[simp] theorem Entry.hold_ty (D : List Dep) (E : Entry) : (E.hold D).ty = E.ty := rfl
@[simp] theorem Entry.hold_mode (D : List Dep) (E : Entry) : (E.hold D).mode = E.mode := rfl
@[simp] theorem Entry.hold_live (D : List Dep) (E : Entry) : (E.hold D).live = E.live := rfl
@[simp] theorem Entry.hold_path (D : List Dep) (E : Entry) : (E.hold D).path = E.path := rfl
@[simp] theorem Entry.hold_held (D : List Dep) (E : Entry) :
    (E.hold D).held = E.held ++ ownHeld true E.ty D := rfl
@[simp] theorem Entry.hold_dtor (D : List Dep) (E : Entry) : (E.hold D).dtor = E.dtor := rfl
@[simp] theorem Entry.hold_dbind (D : List Dep) (E : Entry) : (E.hold D).dbind = E.dbind := rfl

theorem Entry.hold_vdeps (D : List Dep) (E : Entry) :
    (E.hold D).vdeps = E.vdeps ++ ownHeld true E.ty D := by
  show (if E.mode.ownSlot then [] else E.path) ++ (E.held ++ ownHeld true E.ty D) = _
  unfold Entry.vdeps; rw [List.append_assoc]

/-- A binding of a type that holds no views holds nothing more. -/
theorem Entry.hold_noView {E : Entry} (h : E.ty.holdsView = false) (D : List Dep) : E.hold D = E := by
  cases E; simp_all [Entry.hold, ownHeld]

theorem holdOn_some {rs : List Var} {D : List Dep} {Γ : Ctx} {v : Var} {E : Entry} (h : Γ v = some E) :
    holdOn rs D Γ v = some (if v ∈ rs then E.hold D else E) := by
  simp [holdOn, h]

theorem holdOn_none {rs : List Var} {D : List Dep} {Γ : Ctx} {v : Var} (h : Γ v = none) :
    holdOn rs D Γ v = none := by
  simp [holdOn, h]

/-- What a binding is after `holdOn`: what it was, perhaps holding more. -/
theorem holdOn_get {rs : List Var} {D : List Dep} {Γ : Ctx} {v : Var} {E' : Entry}
    (h : holdOn rs D Γ v = some E') : ∃ E, Γ v = some E ∧ (E' = if v ∈ rs then E.hold D else E) := by
  cases hE : Γ v with
  | none => rw [holdOn_none hE] at h; cases h
  | some E => rw [holdOn_some hE] at h; exact ⟨E, rfl, (Option.some.inj h).symm⟩

theorem holdOn_isSome (rs : List Var) (D : List Dep) (Γ : Ctx) (v : Var) :
    (holdOn rs D Γ v).isSome = (Γ v).isSome := by
  cases hE : Γ v with
  | none => rw [holdOn_none hE]
  | some E => rw [holdOn_some hE]; rfl

/-- What a change through a borrow that may store a view asks of each memory
    root `d.root` of the borrow's path `P`, beyond `ThruOK`, `D` being what
    the stored value depends on in memory: its effect, the root's elements
    holding views if its type does, ends no view a destructor will read
    (`killThruV`); it was not made by `letd` (a destructor binding gains no
    view, as `StmtT.push` asks); and what is stored depends on no root of
    the path (no tree views itself). -/
def ThruV (Γ1 : Ctx) (op : Edit) (tx : Ty) (P D : List Dep) : Prop :=
  ∀ d ∈ memDeps P,
    DtorSafe Γ1 (op.effAt d.kind (decide ((argE Γ1 d.root).ty = tx))) (argE Γ1 d.root).ty.holdsView d.root ∧
    (argE Γ1 d.root).dbind = false ∧ d.root ∉ roots D

/-- A memory root of a change through a borrow owns its slot and is not lent
    out. -/
theorem ThruOK.root {Γ1 : Ctx} {F : List Var} {op : Edit} {tx : Ty} {P : List Dep}
    (h : ThruOK Γ1 F op tx P) {r : Var} (hr : r ∈ roots (memDeps P)) :
    ∃ Er, Γ1 r = some Er ∧ Er.mode.ownSlot = true ∧ r ∉ F := by
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
  obtain ⟨hF, _, Er, hEr, _, hcan, _⟩ := h d hd
  exact ⟨Er, hEr, hcan.ownSlot, hF⟩

/-- ... so no borrow is one. -/
theorem ThruOK.not_root {Γ1 : Ctx} {F : List Var} {op : Edit} {tx : Ty} {P : List Dep}
    (h : ThruOK Γ1 F op tx P) {x : Var} {Ex : Entry} (hx : Γ1 x = some Ex) (hos : Ex.mode.ownSlot = false) :
    x ∉ roots (memDeps P) := fun hr => by
  obtain ⟨Er, hEr, ho, _⟩ := h.root hr
  rw [hx] at hEr; cases hEr; rw [hos] at ho; cases ho

theorem ThruV.dbind {Γ1 : Ctx} {op : Edit} {tx : Ty} {P D : List Dep} (h : ThruV Γ1 op tx P D) {r : Var}
    (hr : r ∈ roots (memDeps P)) {E : Entry} (hE : Γ1 r = some E) : E.dbind = false := by
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
  have := (h d hd).2.1
  simpa [argE, hE] using this

theorem ThruV.notD {Γ1 : Ctx} {op : Edit} {tx : Ty} {P D : List Dep} (h : ThruV Γ1 op tx P D) {r : Var}
    (hr : r ∈ roots (memDeps P)) : r ∉ roots D := by
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
  exact (h d hd).2.2

/-- What a change kills is on a root none of whose memory `D` depends on. -/
theorem ThruV.kills {Γ1 : Ctx} {op : Edit} {tx : Ty} {P D : List Dep} (h : ThruV Γ1 op tx P D) :
    ∀ k ∈ thruKills op Γ1 tx P, k.2.2 ∉ roots D := by
  intro k hk
  obtain ⟨d, hd, rfl⟩ := mem_thruKills.mp hk
  exact (h d hd).2.2

/-- Memory dependencies are none by name. -/
theorem memDeps_noName {D : List Dep} : ∀ d ∈ memDeps D, d.kind.isName = false := fun d hd => by
  simpa [memDeps] using (List.mem_filter.mp hd).2

/-- What a change of elements is handed: the value `vec_push` stores (as
    `PushArg` takes it; an element `Vec` moves), the integer expression a
    truncation evaluates, which only reads, or both, for `vec_set`: the
    index it reads and the value it stores (as `vec_push` does). -/
inductive EditArg (Γ : Ctx) (F : List Var) : Edit → Ty → List Dep → Ctx → Prop
  | push {y : Var} {Ey : Entry} {t : Ty} {D : List Dep} {Γ1 : Ctx} :
      Γ y = some Ey → Ey.live = true → Ey.ty = t → PushArg Γ F y Ey t D Γ1 →
      EditArg Γ F (.push y) t D Γ1
  | trunc {i : Expr} {t : Ty} : ExprT Γ i → EditArg Γ F (.trunc i) t [] Γ
  | set {i : Expr} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep} {Γ1 : Ctx} :
      ExprT Γ i → Γ y = some Ey → Ey.live = true → Ey.ty = t → PushArg Γ F y Ey t D Γ1 →
      EditArg Γ F (.set i y) t D Γ1

/-- Does a statement change a `Vec`'s elements through a borrow
    (`.edit true`, Agora #295)? The step ignores the flag, so the guard
    rests on it: no rule may type `.edit false` through a borrow. An owner
    rule for `.edit false` must ask `canDo` of the target itself. -/
def Stmt.hasThru : Stmt → Bool
  | .seq a b => a.hasThru || b.hasThru
  | .ite _ a b => a.hasThru || b.hasThru
  | .letv _ _ s => s.hasThru
  | .letcall _ _ _ s => s.hasThru
  | .while _ s => s.hasThru
  | .scope _ s => s.hasThru
  | .rbind _ s => s.hasThru
  | .frozen _ s => s.hasThru
  | .letrec _ _ s => s.hasThru
  | .catchR _ _ s => s.hasThru
  | .unpair _ _ _ s => s.hasThru
  | .callc _ _ _ _ s => s.hasThru
  | .letd _ _ _ s => s.hasThru
  | .scopeD _ _ s => s.hasThru
  | .edit b _ _ => b
  | .withLock _ _ s => s.hasThru
  | .scopeL _ _ _ s => s.hasThru
  | .withElem _ _ _ s => s.hasThru
  | .callcE _ _ _ _ s => s.hasThru
  | _ => false

/-- The functions a statement calls by index: a call, a `recover` body, a
    destructor (Agora #295). A call through a package is not listed: the
    code it runs is never a `ThruFn` (`Implements`). -/
def Stmt.calls : Stmt → List Nat
  | .seq a b => a.calls ++ b.calls
  | .ite _ a b => a.calls ++ b.calls
  | .letv _ _ s => s.calls
  | .letcall _ f _ s => f :: s.calls
  | .while _ s => s.calls
  | .scope _ s => s.calls
  | .rbind _ s => s.calls
  | .frozen _ s => s.calls
  | .letrec _ f s => f :: s.calls
  | .catchR _ _ s => s.calls
  | .unpair _ _ _ s => s.calls
  | .callc _ _ _ _ s => s.calls
  | .letd _ f _ s => f :: s.calls
  | .scopeD _ f s => f :: s.calls
  | .withLock _ _ s => s.calls
  | .scopeL _ _ _ s => s.calls
  | .withElem _ _ _ s => s.calls
  | .callcE _ _ _ _ s => s.calls
  | _ => []

/-- A function that changes elements through a borrow, or calls one that
    does (Agora #295). A call into one passes no argument that holds views
    (`CallT`): inside it, every borrow's memory roots are the callee's own
    or a parameter's, which is what keeps a change through a borrow sound
    when the body is lifted into its caller's frame (`Rename`). -/
inductive ThruFn (P : Prog) : Nat → Prop
  | here {f : Nat} {fn : Fn} : P[f]? = some fn → fn.body.hasThru = true → ThruFn P f
  | call {f g : Nat} {fn : Fn} : P[f]? = some fn → g ∈ fn.body.calls → ThruFn P g → ThruFn P f

/-- A statement changes elements through a borrow, or calls a function that
    may (Agora #295). -/
def Stmt.Thru (P : Prog) (s : Stmt) : Prop := s.hasThru = true ∨ ∃ g ∈ s.calls, ThruFn P g

theorem ThruFn.of_body {P : Prog} {f : Nat} {fn : Fn} (hf : P[f]? = some fn) :
    fn.body.Thru P → ThruFn P f
  | .inl h => .here hf h
  | .inr ⟨_, hg, ht⟩ => .call hf hg ht

namespace Stmt.Thru
variable {P : Prog}

/-- What a part of a statement does through a borrow, or calls, the
    statement does. -/
theorem mono {s t : Stmt} (hh : s.hasThru = true → t.hasThru = true)
    (hc : ∀ g ∈ s.calls, g ∈ t.calls) : s.Thru P → t.Thru P
  | .inl h => .inl (hh h)
  | .inr ⟨g, hg, ht⟩ => .inr ⟨g, hc g hg, ht⟩

theorem seq_l {a b : Stmt} (h : a.Thru P) : (Stmt.seq a b).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])
theorem seq_r {a b : Stmt} (h : b.Thru P) : (Stmt.seq a b).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])
theorem ite_l {c : Expr} {a b : Stmt} (h : a.Thru P) : (Stmt.ite c a b).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])
theorem ite_r {c : Expr} {a b : Stmt} (h : b.Thru P) : (Stmt.ite c a b).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])
theorem wh {c : Expr} {k : Stmt} (h : k.Thru P) : (Stmt.while c k).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])
theorem letv {x : Var} {r : Rhs} {k : Stmt} (h : k.Thru P) : (Stmt.letv x r k).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])
theorem withLock {a x : Var} {k : Stmt} (h : k.Thru P) : (Stmt.withLock a x k).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])
theorem letcall {x : Var} {f : Nat} {args : List Var} {k : Stmt} (h : k.Thru P) :
    (Stmt.letcall x f args k).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])
theorem letrec {x : Var} {f : Nat} {k : Stmt} (h : k.Thru P) : (Stmt.letrec x f k).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])
theorem unpair {y x z : Var} {k : Stmt} (h : k.Thru P) : (Stmt.unpair y x z k).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])
theorem callc {x c : Var} {j : Nat} {zs : List Var} {k : Stmt} (h : k.Thru P) :
    (Stmt.callc x c j zs k).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])
theorem letd {x : Var} {f : Nat} {r : Rhs} {k : Stmt} (h : k.Thru P) : (Stmt.letd x f r k).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])
theorem withElem {v x : Var} {i : Expr} {k : Stmt} (h : k.Thru P) : (Stmt.withElem v i x k).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])
theorem callcE {x c : Var} {j : Nat} {zs : List Var} {k : Stmt} (h : k.Thru P) :
    (Stmt.callcE x c j zs k).Thru P :=
  h.mono (fun h => by simp [hasThru, h]) (fun g hg => by simp [calls, hg])

end Stmt.Thru

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
    E = callRes Γ fn args ∧ Γ' = callPost Γ fn args ∧
    -- a call into a function that changes elements through a borrow passes
    -- no argument that holds views (Agora #295: `ThruFn`)
    (ThruFn P f → callR Γ args = [])

/-! ### Statements -/

/-- A2-drop.3a: the bindings a statement moves before anything else of it
    runs: a head of `letd y f (.var w)`s, which may end in a move into
    another binding, `assign y (.var w)`. A binder that may hold an owned
    value of a destructor type but runs no destructor itself (a call's
    result, `unpair`'s fields, a `sink` parameter) hands the value over this
    way. Nothing runs in between, so nothing can panic or end the value
    first. A `letd`'s scope ends where the binder's does, and runs the
    destructor (`scopeD`) where the binder would (an `unpair` hands its
    fields on in turn, Agora #616); a binding the value is
    assigned to is of the same type, whose own binder answers for it. -/
def Stmt.movedFirst : Stmt → List Var
  | .letd _ _ (.var w) s => w :: s.movedFirst
  | .assign _ (.var w) => [w]
  | .unpair y _ _ _ => [y]   -- (Agora #616: taken apart, its fields handed on in turn)
  | _ => []

/-- Agora #616: a drop glue's tail does nothing but hand values on: each
    to a `letd` (whose frame runs its destructor), or taken apart in turn,
    and at the end the integer result is set.  So taking a struct apart by
    hand (`unpair`) skips no work its glue would do. -/
def Stmt.pureGlue : Stmt → Bool
  | .letd _ _ (.var _) s => s.pureGlue
  | .letd _ _ (.takel _) s => s.pureGlue
  | .letd _ _ (.taker _) s => s.pureGlue
  | .unpair _ _ _ s => s.pureGlue
  | .assign _ (.expr _) => true
  | .skip => true
  | _ => false

/-- A2-drop.3a: the bindings a statement may give a new value (`assign`),
    anywhere in it.  A binding that may own a value of a destructor type
    (or of a struct or an enum holding one) is given none: the old value's
    drop would run no destructor (`DropSlot`).  Its binder says so of its
    scope (`letd`, a call's result, `unpair`'s fields, a `sink` or `inout`
    parameter: `FnOK`); a program replaces such a value by moving it to a
    `letd`, whose scope runs the destructor, and binding the new one. -/
def Stmt.assigns : Stmt → List Var
  | .assign y _ => [y]
  | .seq a b => a.assigns ++ b.assigns
  | .ite _ a b => a.assigns ++ b.assigns
  | .while _ s => s.assigns
  | .letv _ _ s => s.assigns
  | .letcall _ _ _ s => s.assigns
  | .scope _ s => s.assigns
  | .rbind _ s => s.assigns
  | .frozen _ s => s.assigns
  | .letrec _ _ s => s.assigns
  | .catchR _ _ s => s.assigns
  | .unpair _ _ _ s => s.assigns
  | .callc _ _ _ _ s => s.assigns
  | .letd _ _ _ s => s.assigns
  | .scopeD _ _ s => s.assigns
  | .withLock _ _ s => s.assigns
  | .scopeL _ _ _ s => s.assigns
  | .withElem _ _ _ s => s.assigns
  | .callcE _ _ _ _ s => s.assigns
  | _ => []

/-- A2-drop.3a: how many times a statement may give `x` a new value on one
    path: a sequence adds, a branch takes the larger, a loop may repeat.  A
    function's result of a destructor type is set at most once (`FnOK`), so
    no value of it is dropped by a second assignment. -/
def Stmt.asgMax (x : Var) : Stmt → Nat
  | .assign y _ => if y = x then 1 else 0
  | .seq a b => a.asgMax x + b.asgMax x
  | .ite _ a b => max (a.asgMax x) (b.asgMax x)
  | .while _ s => 2 * s.asgMax x
  | .letv _ _ s => s.asgMax x
  | .letcall _ _ _ s => s.asgMax x
  | .scope _ s => s.asgMax x
  | .rbind _ s => s.asgMax x
  | .frozen _ s => s.asgMax x
  | .letrec _ _ s => s.asgMax x
  | .catchR _ _ s => s.asgMax x
  | .unpair _ _ _ s => s.asgMax x
  | .callc _ _ _ _ s => s.asgMax x
  | .letd _ _ _ s => s.asgMax x
  | .scopeD _ _ s => s.asgMax x
  | .withLock _ _ s => s.asgMax x
  | .scopeL _ _ _ s => s.asgMax x
  | .withElem _ _ _ s => s.asgMax x
  | .callcE _ _ _ _ s => s.asgMax x
  | _ => 0

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
  | fn _ _ => exact h
  | arc t ih => exact ih h
  | lk t ih => exact ih h
  | cell t ih => exact ih h
  | dtor _ t ih => exact ih h

/-- A3.5b: the environment of a Send closure (its type's `q` is not `any`)
    holds no view, so no closure that holds bindings by name, and the closure
    captures nothing by name. -/
theorem Cross.Fits.send {q : Cross} {te : Ty} {cs : List (Var × PMode × Ty)} (h : q.Fits te cs)
    (hq : q.views = false) : te.holdsView = false ∧ te.hasFn = false ∧ cs = [] := by
  obtain ⟨hv, hc⟩ := h.1 hq
  refine ⟨hv, ?_, hc⟩
  cases hf : te.hasFn
  · rfl
  · rw [hasFn_holdsView hf] at hv; cases hv

/-- A3.5b: an environment that may hold views is a closure's whose type says
    it may. -/
theorem Cross.Fits.holdsView {q : Cross} {te : Ty} {cs : List (Var × PMode × Ty)} {ms : List Nat}
    (h : q.Fits te cs) (hv : te.holdsView = true) : (Ty.fn ms q).holdsView = true := by
  cases q with
  | any => rfl
  | _ => rw [(h.1 rfl).1] at hv; cases hv

/-- A package that captures nothing by name: what its environment is valid
    through is everything it holds. -/
@[simp] theorem envDeps_nil (H : List Dep) : envDeps [] H = H := by
  simp [envDeps, ownWriter, capRootsW]

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
  | .remove y i => y :: i.vars
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
  | .arcNew _ y => [y]
  | .arcClone a => [a]
  | .arcGet a => [a]
  | .lockNew _ y => [y]
  | .lockClone a => [a]
  | .rwRead a => [a]
  | .rwTryRead a => [a]
  | .rwTryWrite a => [a]
  | .atomic _ a e1 e2 => a :: e1.vars ++ e2.vars
  | .chanSend a y => [a, y]
  | .chanRecv _ a => [a]
  | .chanClose a => [a]
  | .cellNew _ y => [y]
  | .cellClone a => [a]
  | .glob _ _ => []
  | .lockTake a => [a]
  | .lockRestore a y => [a, y]

def Edit.vars : Edit → List Var
  | .push y => [y]
  | .trunc i => i.vars
  | .set i y => i.vars ++ [y]

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
  | .edit _ x op => x :: op.vars
  | .withLock a x s => x :: a :: s.vars
  | .scopeL _ _ x s => x :: s.vars
  | .insert x i y => x :: y :: i.vars
  | .withElem v i x s => x :: v :: i.vars ++ s.vars
  | .callcE x c _ zs s => x :: c :: zs ++ s.vars

theorem Expr.vars_rename (ρ : Var → Var) (e : Expr) : (e.rename ρ).vars = e.vars.map ρ := by
  induction e <;> simp_all [Expr.rename, Expr.vars]

theorem Rhs.vars_rename (ρ : Var → Var) (r : Rhs) : (r.rename ρ).vars = r.vars.map ρ := by
  cases r <;> simp [Rhs.rename, Rhs.vars, Expr.vars_rename]

theorem Edit.vars_rename (ρ : Var → Var) (op : Edit) : (op.rename ρ).vars = op.vars.map ρ := by
  cases op <;> simp [Edit.rename, Edit.vars, Expr.vars_rename]

theorem Stmt.vars_rename (ρ : Var → Var) (s : Stmt) : (s.rename ρ).vars = s.vars.map ρ := by
  induction s <;> simp_all [Stmt.rename, Stmt.vars, Rhs.vars_rename, Expr.vars_rename, Edit.vars_rename]



end A2
