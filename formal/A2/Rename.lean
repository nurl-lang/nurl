import A2.NameWf
import A2.Fresh
import A2.DomTy

/-! A2 — a callee's body, checked once against its own view of its
parameters, is well-typed where a call places it.

The call renames the callee's variables apart from the caller's (`ρ`).  The
caller's context, as the renamed body sees it, is `canon Γa`: each callee
binding lifted (`liftE`), and every other binding — the frame — as the
caller has it.  A lifted entry may additionally depend on anything the
arguments held (`allKinds R`): those roots are frozen for the call, so
nothing in the body can end them. -/

namespace A2

def Dep.ren (ρ : Var → Var) (d : Dep) : Dep := ⟨ρ d.root, d.kind⟩

def rds (ρ : Var → Var) (ds : List Dep) : List Dep := ds.map (Dep.ren ρ)

/-- The lift of dependencies: a region's are what it stands for (`σ`),
    every other one is renamed. -/
def rdsπ (ρ : Var → Var) (isPi : Var → Bool) (σ : Var → List Dep) (ds : List Dep) : List Dep :=
  ds.flatMap fun d => if isPi d.root then σ d.root else [Dep.ren ρ d]

theorem mem_rdsπ {ρ : Var → Var} {isPi : Var → Bool} {σ : Var → List Dep} {ds : List Dep} {e : Dep} :
    e ∈ rdsπ ρ isPi σ ds ↔
      ∃ d ∈ ds, (isPi d.root = true ∧ e ∈ σ d.root) ∨ (isPi d.root = false ∧ e = Dep.ren ρ d) := by
  unfold rdsπ
  simp only [List.mem_flatMap]
  constructor
  · rintro ⟨d, hd, he⟩
    refine ⟨d, hd, ?_⟩
    cases hp : isPi d.root
    · rw [hp] at he; simp at he; exact Or.inr ⟨rfl, he⟩
    · rw [hp] at he; simp at he; exact Or.inl ⟨rfl, he⟩
  · rintro ⟨d, hd, ⟨hp, he⟩ | ⟨hp, rfl⟩⟩
    · exact ⟨d, hd, by rw [hp]; simpa using he⟩
    · exact ⟨d, hd, by rw [hp]; simp⟩


def liftMode : Mode → Mode
  | .inout _ => .own
  | m => m

/-- The setting of one call. -/
structure RSetup where
  ρ   : Var → Var
  R   : List Var
  pe  : Var → Entry
  Φ   : Ctx
  Fc  : List Var
  bnd : Var → Option (Eff × Bool)   -- an `inout` parameter's bound and whether it holds views
  pty : Var → Ty                     -- an `inout` parameter's type
  N   : List Dep                     -- what the arguments hold by name, of the frame
  sym : List Dep                     -- the callee's symbolic names on its `inout` parameters
  isPi : Var → Bool := fun _ => false   -- AGORA-937: the callee's parameter regions
  σ : Var → List Dep := fun _ => []      -- AGORA-937: what each region stands for, at the caller
  /-- AGORA-937 stage 3: a region is lifted as a ghost binding, renamed (`ρ`)
      to a caller binding of mode `.region`, not substituted (`isPi` is
      then nothing). Every setup made today leaves it `false`. -/
  ghost : Bool := false
  /-- AGORA-937 stage 3: the callee's region indices, whether or not the
      lift substitutes them (`isPi` is these where it does: `AbsOK`). -/
  isReg : Var → Bool := fun _ => false
  /-- AGORA-937 (3d): what the arguments hold in memory, each of their own
      dependencies; what they hold, in every way, is these composed (`A`). -/
  Rd : List Dep := allKinds R
  /-- AGORA-937 (3d): what the call freezes: what the arguments to
      parameters with no region hold in memory (the callee does not track
      it). The lift adds these, composed (`A`); a region's memory comes
      back through the substitution instead. -/
  Rf : List Dep := Rd
  /-- AGORA-937 (3d): the lent parameters with a region: their argument's
      memory comes back through the region, so their lift keeps only the
      argument's names. -/
  peReg : Var → Bool := fun _ => false

namespace RSetup
variable (S : RSetup)

/-- Anything the arguments held: views, in every way, and closures, by name. -/
def A : List Dep := compAll S.Rf ++ S.N

/-- AGORA-937 (3d): everything the arguments hold, in every way: what the
    lift adds and what the regions stand for. -/
def B : List Dep := compAll S.Rd ++ S.N

open Classical in
noncomputable def inv (y : Var) : Option Var :=
  if h : ∃ v, S.ρ v = y then some (Classical.choose h) else none

/-- Agora #916: what a lift adds to an entry's `held`: what the arguments
    hold, or, for a held-fresh borrow holding memory, only what they hold
    by name. -/
def heldA (E : Entry) : List Dep :=
  if E.heldFresh && E.mode == .bor && E.ty != .int then (if E.ty.hasFn then S.N else []) else S.A

/-- Whether a lift is precise on `held`. -/
def HeldP (E : Entry) : Prop := E.heldFresh = true ∧ E.mode = .bor ∧ E.ty ≠ .int

theorem heldA_P {E : Entry} (h : HeldP E) : S.heldA E = if E.ty.hasFn then S.N else [] := by
  obtain ⟨h1, h2, h3⟩ := h; simp [heldA, h1, h2, h3]

/-- AGORA-909: ... at most what the arguments hold by name, and nothing for
    a type that holds no closure: a value of such a type holds no name
    (`WFv.names_nil_fn`). -/
theorem heldA_P_sub {E : Entry} (h : HeldP E) : S.heldA E ⊆ S.N := by
  rw [S.heldA_P h]; split
  · exact List.Subset.refl _
  · exact List.nil_subset _

theorem heldA_notP {E : Entry} (h : ¬ HeldP E) : S.heldA E = S.A := by
  unfold heldA; split
  · rename_i hc; simp only [Bool.and_eq_true, beq_iff_eq, bne_iff_ne, ne_eq] at hc
    exact absurd ⟨hc.1.1, hc.1.2, hc.2⟩ h
  · rfl

/-- `heldA` reads only the bit, the mode and the type. -/
@[simp] theorem heldA_with_live (E : Entry) (l : Bool) : S.heldA { E with live := l } = S.heldA E := rfl
@[simp] theorem heldA_with_dtor (E : Entry) (l d : Bool) :
    S.heldA { E with live := l, dtor := d } = S.heldA E := rfl

@[simp] theorem heldA_of {E : Entry} (h : E.heldFresh = false) : S.heldA E = S.A := by
  simp [heldA, h]

theorem heldA_own {E : Entry} (h : E.mode.ownSlot = true) : S.heldA E = S.A := by
  unfold heldA; cases hm : E.mode <;> simp_all [Mode.ownSlot]

theorem heldA_sub (E : Entry) : S.heldA E ⊆ S.A := by
  unfold heldA; split
  · split
    · exact fun d hd => List.mem_append_right _ hd
    · exact List.nil_subset _
  · exact List.Subset.refl _


def liftE (v : Var) (E : Entry) : Entry :=
  if E.mode = .rootb then { S.pe v with live := E.live, fresh := false, heldFresh := false, held := rds S.ρ (memDeps E.held) ++ (if S.peReg v then nameDeps (S.pe v).held else (S.pe v).held) } else
    ⟨E.ty, liftMode E.mode, E.live,
     -- Agora #909: a fresh borrow, holding memory, reaches only the frame's own
     -- blocks (`FreshOK`), so nothing the arguments hold
     rds S.ρ E.path ++ (if E.mode.ownSlot || (E.fresh && E.ty != .int) then [] else S.A),
     -- Agora #916: ... and a held-fresh borrow holds, in memory, only the frame's
     -- own blocks, so nothing the arguments hold in memory (their names it may)
     rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty (S.heldA E), E.dtor, E.dbind, E.fresh, E.heldFresh⟩

/-- Agora #916: a lift keeps the bit, but a borrowed parameter's is never
    set: what it is lifted to is the caller's. -/
theorem liftE_heldFresh (v : Var) (E : Entry) :
    (S.liftE v E).heldFresh = if E.mode = .rootb then false else E.heldFresh := by
  unfold liftE; split <;> rfl

@[simp] theorem liftE_heldFresh_false {v : Var} {E : Entry} (h : E.heldFresh = false) :
    (S.liftE v E).heldFresh = false := by
  rw [liftE_heldFresh]; split <;> simp [h]

/-- Agora #909: a lift keeps the bit, but a borrowed parameter's is never
    set: what it is lifted to is the caller's. -/
theorem liftE_fresh (v : Var) (E : Entry) :
    (S.liftE v E).fresh = if E.mode = .rootb then false else E.fresh := by
  unfold liftE; split <;> rfl

theorem liftE_fresh_of {v : Var} {E : Entry} (h : E.mode ≠ .rootb) : (S.liftE v E).fresh = E.fresh := by
  rw [liftE_fresh, ite_eq_right h]

/-- ... and a lift of an entry that is not fresh is not. -/
@[simp] theorem liftE_fresh_false {v : Var} {E : Entry} (h : E.fresh = false) : (S.liftE v E).fresh = false := by
  rw [liftE_fresh]; split <;> simp [h]

/-- AGORA-937: a lifted dependency on a parameter's region is what the region
    stands for at the caller (`σ`), but a name on a region is dropped: no
    region is ever changed by name (`name_kill_not_region`), so it could end
    nothing (agora #4191). Any other dependency is kept; names stay names,
    which keeps `EntryWeaker.dheld`'s name/non-name split. -/
noncomputable def subD (d : Dep) : List Dep :=
  match S.inv d.root with
  | some v => if S.isPi v then
      (if d.kind.isName then [] else (S.σ v).map fun e => ⟨e.root, A2.comp e.kind d.kind⟩) else [d]
  | none => [d]

/-- ... applied to what a lifted entry depends on and holds. -/
noncomputable def subE (E : Entry) : Entry :=
  { E with path := E.path.flatMap S.subD, held := E.held.flatMap S.subD }

/-- AGORA-937: the substitution changes only what an entry depends on and
    holds. -/
@[simp] theorem subE_ty (E : Entry) : (S.subE E).ty = E.ty := rfl
@[simp] theorem subE_mode (E : Entry) : (S.subE E).mode = E.mode := rfl
@[simp] theorem subE_live (E : Entry) : (S.subE E).live = E.live := rfl
@[simp] theorem subE_dtor (E : Entry) : (S.subE E).dtor = E.dtor := rfl
@[simp] theorem subE_dbind (E : Entry) : (S.subE E).dbind = E.dbind := rfl
@[simp] theorem subE_fresh (E : Entry) : (S.subE E).fresh = E.fresh := rfl
@[simp] theorem subE_heldFresh (E : Entry) : (S.subE E).heldFresh = E.heldFresh := rfl
@[simp] theorem subE_path (E : Entry) : (S.subE E).path = E.path.flatMap S.subD := rfl
@[simp] theorem subE_held (E : Entry) : (S.subE E).held = E.held.flatMap S.subD := rfl

/-- What a substituted entry depends on: what it depended on, substituted. -/
theorem subE_vdeps (E : Entry) : (S.subE E).vdeps = E.vdeps.flatMap S.subD := by
  unfold Entry.vdeps
  simp only [subE_mode, subE_path, subE_held, List.flatMap_append]
  by_cases ho : E.mode.ownSlot = true
  · simp [ho]
  · simp [ho]

/-- AGORA-937 (3d): what a region `v` stands for, reached at `k`: one of its
    dependencies, composed with `k`, a memory way. -/
def σC (v : Var) (k : Kind) (e : Dep) : Prop :=
  ∃ e0 ∈ S.σ v, e = ⟨e0.root, A2.comp e0.kind k⟩ ∧ k.isName = false

/-- A substituted dependency is either kept, or one a region stands for. -/
theorem mem_subD {d e : Dep} (h : e ∈ S.subD d) :
    e = d ∨ ∃ v, S.inv d.root = some v ∧ S.isPi v = true ∧ S.σC v d.kind e := by
  unfold subD at h
  split at h
  · rename_i v hv
    cases hp : S.isPi v
    · rw [hp] at h; simp at h; exact Or.inl h
    · cases hk : d.kind.isName
      · rw [hp, hk] at h
        simp only [↓reduceIte, Bool.false_eq_true, List.mem_map] at h
        obtain ⟨e0, he0, rfl⟩ := h
        exact Or.inr ⟨v, hv, hp, e0, he0, rfl, hk⟩
      · rw [hp, hk] at h; simp at h
  · simp at h; exact Or.inl h

/-- A dependency on no region is kept. -/
theorem subD_of_not {d : Dep} (h : ∀ v, S.inv d.root = some v → S.isPi v = false) : S.subD d = [d] := by
  unfold subD; split
  · rename_i v hv; rw [h v hv]; simp
  · rfl

/-- AGORA-937 (agora #4191): a name is kept, or dropped (on a region) ... -/
theorem mem_subD_name {d e : Dep} (hk : d.kind.isName = true) (h : e ∈ S.subD d) : e = d := by
  unfold subD at h
  split at h
  · split at h
    · simp at h
    · exact List.mem_singleton.mp h
  · exact List.mem_singleton.mp h

/-- ... and a name on no region is kept. -/
theorem subD_name {d : Dep} (_hk : d.kind.isName = true)
    (hnp : ∀ v, S.inv d.root = some v → S.isPi v = false) : S.subD d = [d] :=
  S.subD_of_not hnp

/-- ... so what a region stands for replaces only a dependency that is no
    name. -/
theorem mem_subD_sub {d e : Dep} (h : e ∈ S.subD d) (hne : e ≠ d) : d.kind.isName = false := by
  cases hk : d.kind.isName
  · rfl
  · exact absurd (S.mem_subD_name hk h) hne

/-- What a substitution of a list holds: each dependency kept, or one a
    region it named stands for. -/
theorem mem_flatMap_subD {ds : List Dep} {e : Dep} (h : e ∈ ds.flatMap S.subD) :
    ∃ d ∈ ds, e = d ∨ ∃ v, S.inv d.root = some v ∧ S.isPi v = true ∧ S.σC v d.kind e := by
  obtain ⟨d, hd, he⟩ := List.mem_flatMap.mp h
  exact ⟨d, hd, S.mem_subD he⟩

/-- ... and keeps every dependency on no region. -/
theorem mem_flatMap_subD_of {ds : List Dep} {d : Dep} (hd : d ∈ ds)
    (h : ∀ v, S.inv d.root = some v → S.isPi v = false) : d ∈ ds.flatMap S.subD :=
  List.mem_flatMap.mpr ⟨d, hd, by rw [S.subD_of_not h]; exact List.mem_singleton_self _⟩

/-- AGORA-937: the substitution is monotone in what it substitutes. -/
theorem flatMap_subD_mono {ds ds' : List Dep} (h : ds ⊆ ds') : ds.flatMap S.subD ⊆ ds'.flatMap S.subD :=
  fun _ he => by
    obtain ⟨d, hd, he⟩ := List.mem_flatMap.mp he
    exact List.mem_flatMap.mpr ⟨d, h hd, he⟩

/-- ... and a dependency that is no name comes only from one that is no
    name: a name is kept as itself, or dropped (`mem_subD_name`). -/
theorem mem_flatMap_subD_nonname {ds : List Dep} {e : Dep} (he : e ∈ ds.flatMap S.subD)
    (hk : e.kind.isName = false) : ∃ d ∈ ds, d.kind.isName = false ∧ e ∈ S.subD d := by
  obtain ⟨d, hd, hed⟩ := List.mem_flatMap.mp he
  refine ⟨d, hd, ?_, hed⟩
  cases hdk : d.kind.isName
  · rfl
  · have := S.mem_subD_name hdk hed; subst this; rw [hk] at hdk; cases hdk

/-- AGORA-937: ... so what a substituted list depends on in memory comes from
    what it did. -/
theorem memDeps_flatMap_subD (X : List Dep) : memDeps (X.flatMap S.subD) ⊆ (memDeps X).flatMap S.subD :=
  fun e he => by
    obtain ⟨he1, hk⟩ := List.mem_filter.mp he
    obtain ⟨d, hd, hdk, hed⟩ := S.mem_flatMap_subD_nonname he1 (by simpa using hk)
    exact List.mem_flatMap.mpr ⟨d, List.mem_filter.mpr ⟨hd, by simp [hdk]⟩, hed⟩

/-- ... so two lists that agree on what is no name substitute to two that
    agree on it. -/
theorem flatMap_subD_nonname_congr {ds ds' : List Dep}
    (h : ∀ d, d.kind.isName = false → (d ∈ ds' ↔ d ∈ ds)) {e : Dep} (hk : e.kind.isName = false) :
    e ∈ ds'.flatMap S.subD ↔ e ∈ ds.flatMap S.subD := by
  constructor
  · intro he
    obtain ⟨d, hd, hdk, hed⟩ := S.mem_flatMap_subD_nonname he hk
    exact List.mem_flatMap.mpr ⟨d, (h d hdk).mp hd, hed⟩
  · intro he
    obtain ⟨d, hd, hdk, hed⟩ := S.mem_flatMap_subD_nonname he hk
    exact List.mem_flatMap.mpr ⟨d, (h d hdk).mpr hd, hed⟩

/-- AGORA-937: the substitution keeps a weakening: it changes only what an
    entry depends on and holds, monotonically, and keeps names as names. -/
theorem subE_weaker {E E' : Entry} (hw : EntryWeaker E E') : EntryWeaker (S.subE E) (S.subE E') where
  ty := by simp [hw.ty]
  mode := by simp [hw.mode]
  fixed := fun hf => by
    have hf0 : E.fixed := by simpa only [Entry.fixed_def, subE_mode, subE_ty] using hf
    rw [hw.fixed hf0]
  live := fun hl => by
    obtain ⟨hl0, hp, hh⟩ := hw.live (by simpa using hl)
    exact ⟨by simpa using hl0, fun hos => S.flatMap_subD_mono (hp (by simpa using hos)),
      S.flatMap_subD_mono hh⟩
  dtor := fun hd => by
    obtain ⟨hd', hh⟩ := hw.dtor (by simpa using hd)
    exact ⟨by simpa using hd', S.flatMap_subD_mono hh⟩
  dbind := by simp [hw.dbind]
  raise := fun hd => by simpa using hw.raise (by simpa using hd)
  dheld := fun hdb hos hn d hk => by
    simp only [subE_held]
    exact S.flatMap_subD_nonname_congr (hw.dheld (by simpa using hdb) (by simpa using hos)
      (by simpa using hn)) hk
  fresh := fun hl hn hb hf => by
    obtain ⟨hf0, hsub⟩ := hw.fresh (by simpa using hl) (by simpa using hn) (by simpa using hb)
      (by simpa using hf)
    exact ⟨by simpa using hf0, S.flatMap_subD_mono hsub⟩
  heldFresh := fun hn hb hhf => by
    simpa using hw.heldFresh (by simpa using hn) (by simpa using hb) (by simpa using hhf)

noncomputable def canon (Γa : Ctx) : Ctx := fun y =>
  match S.inv y with
  | some v => if S.isPi v then none else (Γa v).map (S.subE ∘ S.liftE v)
  | none => S.Φ y

end RSetup

/-- What a call setting must satisfy. -/
structure RSetup.OK (S : RSetup) : Prop where
  inj    : ∀ v w, S.ρ v = S.ρ w → v = w
  /-- AGORA-937: what a region stands for is what the arguments hold, in every
      way: the frame's roots the call freezes (`σ_sub`). -/
  σ_sub  : ∀ v, S.σ v ⊆ allKinds S.R
  /-- (AGORA-937, 3d: what a region stands for is the argument's own
      memory dependencies, each reached as the argument reaches it; the lift
      composes kinds, `subD`.) -/
  σ_mem : ∀ v d, d ∈ S.σ v → d.kind.isName = false
  Rout   : ∀ r ∈ S.R, ∀ v, S.ρ v ≠ r
  Rd_sub : ∀ d ∈ S.Rd, d.root ∈ S.R ∧ d.kind.isName = false
  Rf_sub : ∀ d ∈ S.Rf, d ∈ S.Rd
  σ_Rd   : ∀ v, S.σ v ⊆ S.Rd
  Rroot  : ∀ r ∈ S.R, ∃ E, S.Φ r = some E ∧ E.mode.isRoot = true
  Fcout  : ∀ v, S.ρ v ∉ S.Fc
  pe_rb  : ∀ v, (S.pe v).mode = .rootb
  -- what a borrowed parameter depends on in memory is the frame's
  pe_out : ∀ v, ∀ d ∈ (S.pe v).vdeps, d.kind.isName = false →
             (∀ w, S.ρ w ≠ d.root) ∧ ∃ E, S.Φ d.root = some E ∧ E.mode.isRoot = true
  -- the frame: nothing in it depends on the callee's own bindings, and what
  -- depends on an `inout` argument is already ended for everything the
  -- callee may do to it
  Φsat   : ∀ y E, S.Φ y = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
             ∀ d ∈ E.vdeps, ∀ v, S.ρ v = d.root →
               ∃ b hv, S.bnd v = some (b, hv) ∧ b.kills hv d.kind = false
  Φwf    : ∀ y E, S.Φ y = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
             ∀ r ∈ roots E.vdeps, (∀ v, S.ρ v ≠ r) → ∃ Er, S.Φ r = some Er ∧ Er.mode.isRoot = true
  Φρ     : ∀ v, S.Φ (S.ρ v) = none
  Φio    : ∀ y E b, S.Φ y = some E → E.mode ≠ .inout b
  -- A2-drop.2: a borrowed parameter runs no destructor, and a dead frame
  -- binding depends on nothing (the call cleans it)
  pe_dtor : ∀ v, (S.pe v).dtor = false
  pe_dbind : ∀ v, (S.pe v).dbind = false
  -- only a binding `letd` made may run a destructor, in the frame too
  Φarm   : ∀ y E, S.Φ y = some E → E.dtor = true → E.dbind = true
  Φview  : ∀ y E, S.Φ y = some E → E.dbind = true → E.ty.holdsView = true
  Φdead  : ∀ y E, S.Φ y = some E → E.live = false → E.dbind = false → E.vdeps = []
  -- A2-drop.2: a frame binding `letd` made keeps what it views, live or
  -- dead: of the callee's bindings only an `inout` argument, else a frame root
  Φdb    : ∀ y E, S.Φ y = some E → E.dbind = true → E.mode.ownSlot = true →
             (E.ty ≠ .int ∨ E.mode = .rootb) → ∀ d ∈ E.vdeps, d.kind.isName = false →
               (∃ v bh, S.ρ v = d.root ∧ S.bnd v = some bh) ∨
               ((∀ v, S.ρ v ≠ d.root) ∧ ∃ Er, S.Φ d.root = some Er ∧ Er.mode.isRoot = true)
  -- … an armed one views an `inout` argument only as its bound spares
  -- (`CallDtorSafe`), live or dead
  Φdt    : ∀ y E, S.Φ y = some E → E.dtor = true → E.mode.ownSlot = true →
             (E.ty ≠ .int ∨ E.mode = .rootb) → ∀ d ∈ E.vdeps, d.kind.isName = false →
               ∀ v, S.ρ v = d.root → ∃ b hv, S.bnd v = some (b, hv) ∧ b.kills hv d.kind = false
  -- … and what a closure handed to the call may change by name ends none of
  -- its views
  ΦN     : ∀ y E, S.Φ y = some E → E.dtor = true → E.mode.ownSlot = true →
             ∀ d ∈ S.N, d.kind.bound ≠ .none → hitsMem d.kind.bound false d.root E = false
  -- what a borrowed parameter holds: what the arguments held, or (when its
  -- type can hold a closure) an `inout` argument by name, as the callee's
  -- symbolic name says
  pe_held : ∀ v, ∀ d ∈ (S.pe v).held, d ∈ S.A ∨ (d ∈ rds S.ρ S.sym ∧ (S.pe v).ty.hasFn = true) ∨
    (d.kind.isName = false ∧ S.peReg v = true)
  pe_names : ∀ v, ∀ d ∈ (S.pe v).vdeps, d.kind.isName = true →
               d ∈ S.N ∨ (d ∈ rds S.ρ S.sym ∧ (S.pe v).ty.hasFn = true)
  -- the symbolic names: each an `inout` parameter that holds no views and
  -- is not replaced, by its own bound and type
  sym_ok : ∀ d ∈ S.sym, ∃ w b t, d = ⟨w, .name b t⟩ ∧ S.bnd w = some (b, false) ∧ S.pty w = t ∧
             b ≠ .none ∧ b ≠ .replace
  sym_of : ∀ w b t, S.bnd w = some (b, false) → S.pty w = t → b ≠ .none → b ≠ .replace →
             ⟨w, .name b t⟩ ∈ S.sym
  -- what the arguments hold by name of the frame: frame bindings, of the
  -- frame's view; what may change them is not lent, ended in the frame
  -- already, and reached from an argument only by a name of the same bound
  N_name : ∀ d ∈ S.N, d.kind.isName = true
  N_out  : ∀ d ∈ S.N, (∀ w, S.ρ w ≠ d.root) ∧ ∃ E, S.Φ d.root = some E ∧ E.mode.isRoot = true
  N_named : DepsNamed S.Φ S.N
  N_mut  : ∀ d ∈ S.N, d.kind.bound ≠ .none → d.root ∉ S.Fc ∧ d.root ∉ S.R ∧
             (∃ Er, S.Φ d.root = some Er ∧ canDo Er.mode d.kind.bound ∧
               ∃ s, Er.ty = .vec s ∧ s.holdsView = false) ∧
             (∀ v, ∀ d' ∈ (S.pe v).vdeps, d'.root = d.root → d'.kind.bound = d.kind.bound) ∧
             (∀ d' ∈ S.N, d'.root = d.root → d'.kind.bound = d.kind.bound) ∧
             (∀ y E, S.Φ y = some E → E.live = true → hits d.kind.bound false d.root E = false)
  Φrb    : ∀ y E, S.Φ y = some E → E.mode = .rootb → E.live = true
  Φnamed : ∀ y E, S.Φ y = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
             ∀ d ∈ E.vdeps, ∀ b t, d.kind = .name b t →
               (∃ v bh, S.ρ v = d.root ∧ S.bnd v = some bh ∧ S.pty v = t ∧ b ≠ .replace ∧
                  bh.1 ≠ .replace ∧ t.holdsView = false) ∨
               ((∀ v, S.ρ v ≠ d.root) ∧ ∃ Er, S.Φ d.root = some Er ∧ Er.live = true ∧ Er.held = [] ∧
                  Er.ty = t ∧
                  Er.mode.ownSlot = true ∧ (b = .none ∨ b ≠ .replace ∧ canDo Er.mode b) ∧ t.holdsView = false)

/-- Agora #916: a lift adds nothing in memory to a held-fresh borrow. -/
theorem RSetup.memDeps_heldA {S : RSetup} {E : Entry} (h : S.OK) (hp : RSetup.HeldP E) : memDeps (S.heldA E) = [] := by
  exact List.filter_eq_nil_iff.mpr fun d hd => by simp [h.N_name d (S.heldA_P_sub hp hd)]

/-- ... and keeps every name the arguments hold (`allKinds` names none). -/
theorem RSetup.name_mem_heldA {S : RSetup} (hS : S.OK) {E : Entry} {d : Dep} (hd : d ∈ S.A) (hn : d.kind.isName = true)
    (hfn : E.ty.hasFn = true) : d ∈ S.heldA E := by
  unfold RSetup.heldA
  by_cases hc : (E.heldFresh && E.mode == .bor && E.ty != .int) = true
  · rw [ite_eq_left hc, ite_eq_left hfn]
    rcases List.mem_append.mp hd with h | h
    · obtain ⟨d0, hd0, k, hk, rfl⟩ := mem_compAll.mp h
      have hn0 := (hS.Rd_sub d0 (hS.Rf_sub d0 hd0)).2
      obtain ⟨r, a⟩ := d0; simp only at hn hn0
      rcases hk with rfl | rfl | rfl | rfl <;> cases a <;> simp_all [comp, Kind.isName]
    · exact h
  · rw [ite_eq_right hc]; exact hd

/-- AGORA-937 (item 2): its region by its handle, what a lent parameter
    holding views holds of its region (`regionP`); so its lift reproduces
    what the argument holds, each in its own way (`comp a .self = a`). -/
def RSetup.RegViews (S : RSetup) (R : List Dep) : Prop :=
  ∀ d ∈ R, d.kind = .self ∧ S.isReg d.root = true

/-- The callee's own contexts, as the call sets them up: a borrowed
    parameter depends on nothing it can see but its region's views (AGORA-937)
    and, when it may hold a closure, the `inout` parameters by their symbolic
    names; an `inout` parameter carries its bound; one that is fixed stays
    live and holds nothing. -/
def RSetup.AbsOK (S : RSetup) (Γa : Ctx) : Prop :=
  (∀ v E, Γa v = some E → E.mode = .rootb → E.ty = (S.pe v).ty ∧ E.path = [] ∧
     ∃ R, S.RegViews R ∧ E.held = R ++ (if E.ty.hasFn then S.sym else [])) ∧
  (∀ v E b, Γa v = some E → E.mode = .inout b →
     E.ty.owning = true ∧ S.bnd v = some (b, E.ty.elem.holdsView)) ∧
  (∀ v bh, S.bnd v = some bh → ∃ E, Γa v = some E ∧ E.mode = .inout bh.1 ∧ E.ty = S.pty v ∧
     (E.fixed → E.live = true ∧ E.held = [])) ∧
  -- AGORA-937: a callee binding is a region exactly at a region's index ...
  (∀ v E, Γa v = some E → (E.mode = .region ↔ S.isReg v = true) ∧
     -- ... a region binding holds an integer's place: nothing (`regionE`);
     -- every step keeps a binding's type
     (E.mode = .region → E.ty = .int)) ∧
  -- ... a region's index is always bound ...
  (∀ v, S.isReg v = true → ∃ E, Γa v = some E ∧ E.mode = .region) ∧
  -- ... and the lift substitutes a region exactly where it does not lift
  -- regions as ghost bindings (`ghost`, stage 3)
  (∀ v, S.isPi v = (S.isReg v && !S.ghost))

namespace RSetup
variable {S : RSetup} {Γa : Ctx}

/-- AGORA-937: a callee binding that is no region is at no region's index. -/
theorem AbsOK.notPi {Γa : Ctx} (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    (hnr : E.mode ≠ .region) : S.isPi v = false := by
  cases hp : S.isPi v
  · rfl
  · rw [hab.2.2.2.2.2 v] at hp
    simp only [Bool.and_eq_true, Bool.not_eq_true'] at hp
    exact absurd ((hab.2.2.2.1 v E hE).1.mpr hp.1) hnr

/-- AGORA-937: an unbound callee variable is at no region's index: every
    region's is bound. -/
theorem AbsOK.notPiFresh {Γa : Ctx} (hab : S.AbsOK Γa) {v : Var} (hv : Γa v = none) :
    S.isPi v = false := by
  cases hp : S.isPi v
  · rfl
  · rw [hab.2.2.2.2.2 v] at hp
    simp only [Bool.and_eq_true] at hp
    obtain ⟨E, hE, _⟩ := hab.2.2.2.2.1 v hp.1; rw [hv] at hE; cases hE

/-- AGORA-937 stage 3: an unbound callee variable is at no region's index. -/
theorem AbsOK.notRegFresh {Γa : Ctx} (hab : S.AbsOK Γa) {v : Var} (hv : Γa v = none) :
    S.isReg v = false := by
  cases hp : S.isReg v
  · rfl
  · obtain ⟨E, hE, _⟩ := hab.2.2.2.2.1 v hp; rw [hv] at hE; cases hE

/-- AGORA-937 stage 3: where regions are lifted as ghost bindings, no index
    is a region's to substitute: a region is an ordinary renamed root. -/
theorem AbsOK.ghost_notPi {Γa : Ctx} (hab : S.AbsOK Γa) (hgh : S.ghost = true) (v : Var) :
    S.isPi v = false := by
  rw [hab.2.2.2.2.2 v, hgh]; simp

/-- AGORA-937: a callee binding at no region's index is no region (where
    regions are substituted, not lifted as ghost bindings). -/
theorem AbsOK.ne_region {Γa : Ctx} (hab : S.AbsOK Γa) (hg : S.ghost = false) {v : Var} {E : Entry}
    (hE : Γa v = some E) (hnp : S.isPi v = false) : E.mode ≠ .region := fun hr => by
  have := (hab.2.2.2.1 v E hE).1.mp hr
  rw [hab.2.2.2.2.2 v, this, hg] at hnp; cases hnp


/-- AGORA-937 (item 2): a binding that is no region is at no region's index. -/
theorem AbsOK.notReg {Γa : Ctx} (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    (hm : E.mode ≠ .region) : S.isReg v = false := by
  cases h : S.isReg v with
  | false => rfl
  | true => exact absurd ((hab.2.2.2.1 v E hE).1.mpr h) hm

/-- AGORA-937 stage 3: an index that is no region's is none to substitute. -/
theorem AbsOK.notPi_of_notReg {Γa : Ctx} (hab : S.AbsOK Γa) {v : Var} (hnr : S.isReg v = false) :
    S.isPi v = false := by
  rw [hab.2.2.2.2.2 v, hnr]; rfl

/-- AGORA-937 stage 3: where regions are substituted, an index that is no
    region's to substitute is no region's at all. -/
theorem AbsOK.notReg_of_notPi {Γa : Ctx} (hab : S.AbsOK Γa) (hg : S.ghost = false) {v : Var}
    (hnp : S.isPi v = false) : S.isReg v = false := by
  rw [hab.2.2.2.2.2 v, hg] at hnp; simpa using hnp

theorem inv_ρ (h : S.OK) (v : Var) : S.inv (S.ρ v) = some v := by
  unfold inv
  have hex : ∃ w, S.ρ w = S.ρ v := ⟨v, rfl⟩
  rw [dite_eq_left hex]
  congr
  exact h.inj _ _ (Classical.choose_spec hex)

theorem inv_none {y : Var} (hy : ∀ v, S.ρ v ≠ y) : S.inv y = none := by
  unfold inv
  rw [dite_eq_right]
  exact fun ⟨v, hv⟩ => hy v hv

/-- AGORA-937: what `inv` names is where the call places it. -/
theorem ρ_of_inv {y v : Var} (hv : S.inv y = some v) : S.ρ v = y := by
  unfold inv at hv
  split at hv
  · rename_i hy; simp only [Option.some.injEq] at hv; subst hv; exact Classical.choose_spec hy
  · cases hv

/-- A callee binding at no region's index is lifted, then substituted, where
    the call places it (AGORA-937: the lift is region-general). -/
theorem canon_ρs (h : S.OK) (Γa : Ctx) {v : Var} (hnp : S.isPi v = false) :
    S.canon Γa (S.ρ v) = (Γa v).map (S.subE ∘ S.liftE v) := by
  simp only [canon, inv_ρ h, hnp, Bool.false_eq_true, ↓reduceIte]

/-- ... so a callee binding is bound where the call places it. -/
theorem canon_some (h : S.OK) {Γa : Ctx} {v : Var} {E : Entry} (hv : Γa v = some E)
    (hnp : S.isPi v = false) : S.canon Γa (S.ρ v) = some (S.subE (S.liftE v E)) := by
  rw [canon_ρs h Γa hnp, hv]; rfl


theorem canon_frame (Γa : Ctx) {y : Var} (hy : ∀ v, S.ρ v ≠ y) : S.canon Γa y = S.Φ y := by
  simp [canon, inv_none hy]

/-- AGORA-937: a lifted context's binding, with regions: a callee binding
    that is no region, lifted and substituted; nothing at a region's index;
    or the frame's. -/
theorem canon_ρ_sub (h : S.OK) (Γa : Ctx) (v : Var) :
    S.canon Γa (S.ρ v) = if S.isPi v then none else (Γa v).map (S.subE ∘ S.liftE v) := by
  simp only [canon, inv_ρ h]

theorem canon_cases_sub (h : S.OK) (Γa : Ctx) (y : Var) :
    (∃ v, S.ρ v = y ∧ S.isPi v = false ∧ S.canon Γa y = (Γa v).map (S.subE ∘ S.liftE v)) ∨
    (∃ v, S.ρ v = y ∧ S.isPi v = true ∧ S.canon Γa y = none) ∨
    ((∀ v, S.ρ v ≠ y) ∧ S.canon Γa y = S.Φ y) := by
  by_cases hy : ∃ v, S.ρ v = y
  · obtain ⟨v, rfl⟩ := hy
    cases hp : S.isPi v
    · exact Or.inl ⟨v, rfl, hp, by rw [canon_ρ_sub h, hp]; rfl⟩
    · exact Or.inr (Or.inl ⟨v, rfl, hp, by rw [canon_ρ_sub h, hp]; rfl⟩)
  · have hy' : ∀ v, S.ρ v ≠ y := fun v hv => hy ⟨v, hv⟩
    exact Or.inr (Or.inr ⟨hy', canon_frame Γa hy'⟩)

/-- AGORA-937: `canon_upd` with regions: a binding at no region's index is
    lifted, then substituted. -/
theorem canon_upds (h : S.OK) (Γa : Ctx) {x : Var} (hnp : S.isPi x = false) (oE : Option Entry) :
    S.canon (upd Γa x oE) = upd (S.canon Γa) (S.ρ x) (oE.map (S.subE ∘ S.liftE x)) := by
  funext y
  rcases canon_cases_sub h (upd Γa x oE) y with ⟨v, rfl, hp, hc⟩ | ⟨v, rfl, hp, hc⟩ | ⟨hy, hc⟩
  · rw [hc]
    by_cases hvx : v = x
    · subst hvx; simp
    · rw [upd_ne _ _ hvx, upd_ne _ _ (fun e => hvx (h.inj _ _ e)), canon_ρs h _ hp]
  · rw [hc]
    have hvx : v ≠ x := fun e => by rw [e, hnp] at hp; cases hp
    rw [upd_ne _ _ (fun e => hvx (h.inj _ _ e)), canon_ρ_sub h, hp]; rfl
  · rw [hc, upd_ne _ _ (fun e => hy x e.symm), canon_frame _ hy]

theorem canon_setEs (h : S.OK) (Γa : Ctx) {x : Var} (hnp : S.isPi x = false) (E : Entry) :
    S.canon (setE Γa x E) = setE (S.canon Γa) (S.ρ x) (S.subE (S.liftE x E)) := by
  unfold setE; rw [canon_upds h _ hnp]; rfl

theorem mem_rds {ρ : Var → Var} {ds : List Dep} {d : Dep} : d ∈ rds ρ ds ↔ ∃ d0 ∈ ds, d = d0.ren ρ := by
  simp [rds, eq_comm]

/-- Renaming lists with the same memory views gives the same memory views. -/
theorem rds_mem_congr {ρ : Var → Var} {L L' : List Dep}
    (h : ∀ d, d.kind.isName = false → (d ∈ L' ↔ d ∈ L)) {d : Dep} (hnm : d.kind.isName = false) :
    d ∈ rds ρ L' ↔ d ∈ rds ρ L := by
  constructor <;> intro hd <;> obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
  · exact mem_rds.mpr ⟨d0, (h d0 (by simpa [Dep.ren] using hnm)).mp hd0, rfl⟩
  · exact mem_rds.mpr ⟨d0, (h d0 (by simpa [Dep.ren] using hnm)).mpr hd0, rfl⟩

theorem mem_allKinds {rs : List Var} {d : Dep} (h : d ∈ allKinds rs) : d.root ∈ rs := by
  simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil,
    or_false] at h
  obtain ⟨r, hr, hd⟩ := h
  rcases hd with rfl | rfl | rfl | rfl <;> exact hr

/-- AGORA-937: what a region stands for is rooted in the caller's frame: no
    callee binding is its root, and the frame binds it as a root. -/
theorem σ_frame (h : S.OK) {v : Var} {d : Dep} (hd : d ∈ S.σ v) :
    (∀ w, S.ρ w ≠ d.root) ∧ ∃ E, S.Φ d.root = some E ∧ E.mode.isRoot = true := by
  have hr : d.root ∈ S.R := mem_allKinds (h.σ_sub v hd)
  exact ⟨h.Rout _ hr, h.Rroot _ hr⟩

/-- ... and so is one composed with it (AGORA-937, 3d: `subD` composes
    kinds). -/
theorem σ_frameC (h : S.OK) {v : Var} {e : Dep} {k : Kind} (he : S.σC v k e) :
    (∀ w, S.ρ w ≠ e.root) ∧ ∃ E, S.Φ e.root = some E ∧ E.mode.isRoot = true := by
  obtain ⟨e0, he0, rfl, _⟩ := he
  simpa using S.σ_frame h he0

theorem σC.notName (h : S.OK) {v : Var} {e : Dep} {k : Kind} (he : S.σC v k e) : e.kind.isName = false := by
  obtain ⟨e0, he0, rfl, hk⟩ := he
  exact comp_isName (h.σ_mem v e0 he0) hk

theorem σC.sub (h : S.OK) {v : Var} {e : Dep} {k : Kind} (he : S.σC v k e) : e ∈ allKinds S.R := by
  obtain ⟨e0, he0, rfl, hk⟩ := he
  have hr := mem_allKinds (h.σ_sub v he0)
  have hnk := comp_isName (h.σ_mem v e0 he0) hk
  unfold allKinds; refine List.mem_flatMap.mpr ⟨e0.root, hr, ?_⟩
  generalize A2.comp e0.kind k = c at hnk ⊢
  cases c <;> simp_all [Kind.isName]

/-- ... so the lift's substitution names no callee binding where it put
    what a region stands for. -/
theorem subD_frame (h : S.OK) {d e : Dep} (he : e ∈ S.subD d) :
    e = d ∨ ((∀ w, S.ρ w ≠ e.root) ∧ ∃ E, S.Φ e.root = some E ∧ E.mode.isRoot = true) := by
  rcases S.mem_subD he with rfl | ⟨v, _, _, hv⟩
  · exact Or.inl rfl
  · exact Or.inr (S.σ_frameC h hv)


/-- ... in what it holds too. -/
theorem mem_subE_held_ρ (h : S.OK) {E : Entry} {d : Dep} {w : Var} (hd : d ∈ (S.subE E).held)
    (hdr : d.root = S.ρ w) : d ∈ E.held := by
  rw [subE_held] at hd
  obtain ⟨d1, hd1, hdd⟩ := List.mem_flatMap.mp hd
  rcases S.subD_frame h hdd with rfl | ⟨hout, _⟩
  · exact hd1
  · exact absurd hdr.symm (hout w)

theorem mem_A {d : Dep} : d ∈ S.A ↔ d ∈ compAll S.Rf ∨ d ∈ S.N := List.mem_append

theorem mem_B {d : Dep} : d ∈ S.B ↔ d ∈ compAll S.Rd ∨ d ∈ S.N := List.mem_append

theorem compAll_Rf (h : S.OK) {d : Dep} (hd : d ∈ compAll S.Rf) : d ∈ compAll S.Rd :=
  compAll_mono (fun e he => h.Rf_sub e he) hd

theorem A_sub_B (h : S.OK) : S.A ⊆ S.B := fun _ hd => by
  rcases mem_A.mp hd with hd | hd
  · exact mem_B.mpr (Or.inl (S.compAll_Rf h hd))
  · exact mem_B.mpr (Or.inr hd)

/-- AGORA-937 (3d): what the arguments hold in memory, composed, is on a
    frozen root, in a memory way. -/
theorem compAll_Rd (h : S.OK) {d : Dep} (hd : d ∈ compAll S.Rd) : d.root ∈ S.R ∧ d.kind.isName = false := by
  obtain ⟨d0, hd0, k, hk, rfl⟩ := mem_compAll.mp hd
  obtain ⟨hr, hn⟩ := h.Rd_sub d0 hd0
  refine ⟨hr, ?_⟩
  obtain ⟨r, a⟩ := d0; simp only at hn ⊢
  rcases hk with rfl | rfl | rfl | rfl <;> cases a <;> simp_all [comp, Kind.isName]

theorem compAll_Rd_ak (h : S.OK) {d : Dep} (hd : d ∈ compAll S.Rd) : d ∈ allKinds S.R := by
  obtain ⟨hr, hn⟩ := S.compAll_Rd h hd
  unfold allKinds; refine List.mem_flatMap.mpr ⟨d.root, hr, ?_⟩
  obtain ⟨r, k⟩ := d; simp only at hn ⊢
  cases k <;> simp_all [Kind.isName]

theorem mem_A_ak (h : S.OK) {d : Dep} (hd : d ∈ S.A) : d ∈ allKinds S.R ∨ d ∈ S.N := by
  rcases mem_A.mp hd with hd | hd
  · exact Or.inl (S.compAll_Rd_ak h (S.compAll_Rf h hd))
  · exact Or.inr hd

/-- ... and stays so composed with a memory way (`comp_assoc`). -/
theorem compAll_comp {D : List Dep} {d : Dep} (hd : d ∈ compAll D) {k : Kind}
    (hk : k = .self ∨ k = .inner ∨ k = .view ∨ k = .share) :
    (⟨d.root, comp d.kind k⟩ : Dep) ∈ compAll D := by
  obtain ⟨d0, hd0, k0, hk0, rfl⟩ := mem_compAll.mp hd
  refine mem_compAll.mpr ⟨d0, hd0, comp k0 k, ?_, by simp [comp_assoc]⟩
  rcases hk0 with rfl | rfl | rfl | rfl <;> rcases hk with rfl | rfl | rfl | rfl <;> simp [comp]

theorem kind4 {k : Kind} (hk : k.isName = false) : k = .self ∨ k = .inner ∨ k = .view ∨ k = .share := by
  cases k <;> simp_all [Kind.isName]

theorem Rf_nil (h : S.OK) (hR : S.R = []) : S.Rf = [] :=
  List.eq_nil_of_subset_nil fun d hd => by
    have := (h.Rd_sub d (h.Rf_sub d hd)).1; rw [hR] at this; cases this

theorem Rd_nil (h : S.OK) (hR : S.R = []) : S.Rd = [] :=
  List.eq_nil_of_subset_nil fun d hd => by have := (h.Rd_sub d hd).1; rw [hR] at this; cases this

/-- AGORA-937: a change to a callee binding at no region's index hits a
    substituted entry exactly where it hits the entry: the substitution keeps
    every dependency on it, and what a region stands for is the frame's. -/
theorem hits_subE (h : S.OK) {x : Var} (hnp : S.isPi x = false) (e : Eff) (hv : Bool) (E : Entry) :
    hits e hv (S.ρ x) (S.subE E) = hits e hv (S.ρ x) E := by
  unfold hits
  rw [subE_vdeps, subE_ty, subE_mode]
  congr 1
  apply Bool.eq_iff_iff.mpr
  simp only [List.any_eq_true, Bool.and_eq_true, beq_iff_eq]
  constructor
  · rintro ⟨d', hd', hr, hk⟩
    obtain ⟨d, hd, hed⟩ := List.mem_flatMap.mp hd'
    rcases S.subD_frame h hed with rfl | ⟨hout, _⟩
    · exact ⟨d', hd, hr, hk⟩
    · exact absurd hr.symm (hout x)
  · rintro ⟨d, hd, hr, hk⟩
    refine ⟨d, S.mem_flatMap_subD_of hd (fun w hw => ?_), hr, hk⟩
    rw [hr, inv_ρ h] at hw; cases hw; exact hnp

/-- ... so the change commutes with the substitution. -/
theorem killE_subE (h : S.OK) {x : Var} (hnp : S.isPi x = false) (e : Eff) (hv : Bool) (E : Entry) :
    killE e hv (S.ρ x) (S.subE E) = S.subE (killE e hv (S.ρ x) E) := by
  unfold killE; rw [hits_subE h hnp]; split <;> rfl

/-- AGORA-937: the substitution adds no view of a callee binding: what it
    puts in place of a region's is the frame's (`subD_frame`). So a change to
    one ends in memory no more of a substituted entry than of the entry. -/
theorem hitsMem_subE (h : S.OK) {e : Eff} {hv : Bool} {x : Var} {E : Entry}
    (hE : hitsMem e hv (S.ρ x) E = false) : hitsMem e hv (S.ρ x) (S.subE E) = false := by
  unfold hitsMem at hE ⊢
  rw [subE_vdeps, subE_ty, subE_mode]
  simp only [Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true, beq_iff_eq,
    Bool.not_eq_true'] at hE ⊢
  rcases hE with hE | hE
  · exact Or.inl hE
  · refine Or.inr fun d' hd' hk => ?_
    obtain ⟨d, hd, hed⟩ := List.mem_flatMap.mp hd'
    rcases S.subD_frame h hed with rfl | ⟨hout, _⟩
    · exact hE d' hd hk
    · exact hout x hk.1.1.symm

/-- What the arguments held lies outside the callee, at roots of the frame. -/
theorem mem_B_ak (h : S.OK) {d : Dep} (hd : d ∈ S.B) : d ∈ allKinds S.R ∨ d ∈ S.N := by
  rcases mem_B.mp hd with hd | hd
  · exact Or.inl (S.compAll_Rd_ak h hd)
  · exact Or.inr hd

theorem B_out (h : S.OK) {d : Dep} (hd : d ∈ S.B) : ∀ w, S.ρ w ≠ d.root := by
  rcases mem_B.mp hd with hd | hd
  · exact h.Rout _ (S.compAll_Rd h hd).1
  · exact (h.N_out d hd).1

theorem B_root (h : S.OK) {d : Dep} (hd : d ∈ S.B) : ∃ E, S.Φ d.root = some E ∧ E.mode.isRoot = true := by
  rcases mem_B.mp hd with hd | hd
  · exact h.Rroot _ (S.compAll_Rd h hd).1
  · exact (h.N_out d hd).2

theorem A_out (h : S.OK) {d : Dep} (hd : d ∈ S.A) : ∀ w, S.ρ w ≠ d.root := by
  rcases S.mem_A_ak h hd with hd | hd
  · exact h.Rout _ (mem_allKinds hd)
  · exact (h.N_out d hd).1

theorem A_mem (h : S.OK) {d : Dep} (hd : d ∈ S.A) (hn : (!d.kind.isName) = true) : d ∈ allKinds S.R := by
  rcases S.mem_A_ak h hd with hd | hd
  · exact hd
  · rw [h.N_name d hd] at hn; cases hn

theorem A_root (h : S.OK) {d : Dep} (hd : d ∈ S.A) : ∃ E, S.Φ d.root = some E ∧ E.mode.isRoot = true := by
  rcases S.mem_A_ak h hd with hd | hd
  · exact h.Rroot _ (mem_allKinds hd)
  · exact (h.N_out d hd).2

theorem liftMode_ownSlot (m : Mode) : (liftMode m).ownSlot = m.ownSlot := by cases m <;> rfl
theorem liftMode_isRoot (m : Mode) : (liftMode m).isRoot = m.isRoot := by cases m <;> rfl
theorem liftMode_rootb {m : Mode} : liftMode m = .rootb ↔ m = .rootb := by cases m <;> simp [liftMode]

/-- What a lift adds to an entry's dependencies that matter: to a borrow's
    path, what the arguments hold (none to a fresh one's), and to `held`,
    `heldA`. -/
def liftDeps (E : Entry) : List Dep :=
  (if E.mode.ownSlot || (E.fresh && E.ty != .int) then [] else S.A) ++ ownHeld E.mode.ownSlot E.ty (S.heldA E)

theorem liftDeps_sub (E : Entry) : S.liftDeps E ⊆ S.A := by
  intro d hd
  rcases List.mem_append.mp hd with h | h
  · split at h
    · cases h
    · exact h
  · exact S.heldA_sub E (ownHeld_sub _ _ _ h)

theorem liftDeps_own {E : Entry} (h : E.mode.ownSlot = true) : S.liftDeps E = ownHeld true E.ty S.A := by
  simp [liftDeps, h, S.heldA_own h]

theorem mem_liftE_vdeps {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) {d : Dep} :
    d ∈ (S.liftE v E).vdeps ↔ (∃ d0 ∈ E.vdeps, d = d0.ren S.ρ) ∨ d ∈ S.liftDeps E := by
  have hv : (S.liftE v E).vdeps = (if E.mode.ownSlot then [] else
        rds S.ρ E.path ++ (if E.fresh && E.ty != .int then [] else S.A)) ++
      (rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty (S.heldA E)) := by
    simp only [liftE, hrb, ↓reduceIte, Entry.vdeps, liftMode_ownSlot]
    cases E.mode.ownSlot <;> simp
  rw [hv]
  unfold Entry.vdeps liftDeps
  cases ho : E.mode.ownSlot
  · split <;> simp [mem_rds] <;> grind
  · simp [mem_rds]
    all_goals grind

theorem liftE_vdeps_cases {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) {d : Dep}
    (hd : d ∈ (S.liftE v E).vdeps) : (∃ d0 ∈ E.vdeps, d = d0.ren S.ρ) ∨ d ∈ S.A :=
  ((mem_liftE_vdeps hrb).mp hd).imp id (fun h => S.liftDeps_sub E h)

theorem liftE_ty (v : Var) {E : Entry} (hrb : E.mode ≠ .rootb) : (S.liftE v E).ty = E.ty := by
  simp [liftE, hrb]

/-- A lift of no borrowed parameter, in closed form: `liftE`'s second branch. -/
theorem liftE_of_ne (v : Var) {E : Entry} (hrb : E.mode ≠ .rootb) :
    S.liftE v E = ⟨E.ty, liftMode E.mode, E.live,
      rds S.ρ E.path ++ (if E.mode.ownSlot || (E.fresh && E.ty != .int) then [] else S.A),
      rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty (S.heldA E), E.dtor, E.dbind, E.fresh, E.heldFresh⟩ := by
  unfold liftE; split
  · exact absurd ‹_› hrb
  · rfl

/-- A borrow's lift, in closed form: its path and what it holds renamed, and
    what the arguments hold added unless it is fresh (or held-fresh). -/
theorem liftE_of_bor (v : Var) {E : Entry} (hm : E.mode = .bor) :
    S.liftE v E = ⟨E.ty, .bor, E.live, rds S.ρ E.path ++ (if E.fresh && E.ty != .int then [] else S.A),
      rds S.ρ E.held ++ ownHeld false E.ty (S.heldA E), E.dtor, E.dbind, E.fresh, E.heldFresh⟩ := by
  simp [liftE, hm, liftMode, Mode.ownSlot]

theorem liftE_mode (v : Var) {E : Entry} (hrb : E.mode ≠ .rootb) : (S.liftE v E).mode = liftMode E.mode := by
  simp [liftE, hrb]

/-- AGORA-937: a lifted and substituted binding that is no borrowed
    parameter and no region is, as a root of a change, a `Vec` exactly when
    it was (`Entry.rvec`). -/
theorem subE_liftE_rvec {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) (hnr : E.mode ≠ .region) :
    (S.subE (S.liftE v E)).rvec = E.rvec := by
  unfold Entry.rvec
  rw [subE_ty, subE_mode, liftE_ty v hrb, liftE_mode v hrb]
  cases hm : E.mode <;> simp_all [liftMode] <;> rfl

/-- The caller's view of a callee binding other than a borrowed parameter
    is never fixed: an `inout` parameter is the caller's own binding. -/
theorem liftE_not_fixed {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) : ¬ (S.liftE v E).fixed := by
  intro h
  rcases h with h | ⟨b, h, _⟩ <;> rw [liftE_mode v hrb] at h
  · exact hrb (liftMode_rootb.mp h)
  · cases hm : E.mode <;> rw [hm] at h <;> simp [liftMode] at h

/-- What a callee binding that may be held by name holds, the caller sees it
    hold. -/
theorem liftE_held_named {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) (ho : E.mode.ownSlot = true)
    (hh : E.held = []) (hv : E.ty.holdsView = false) : (S.liftE v E).held = [] := by
  simp [liftE, hrb, hh, ho, ownHeld, hv, rds]

/-- ... nor is anything of a lifted mode. -/
theorem not_fixed_liftMode {E : Entry} {m : Mode} (hm : E.mode = liftMode m) (hrb : m ≠ .rootb) :
    ¬ E.fixed := by
  rintro (h | ⟨b, h, _⟩) <;> rw [hm] at h
  · exact hrb (liftMode_rootb.mp h)
  · cases hq : m <;> rw [hq] at h <;> simp [liftMode] at h

theorem beq_rootb_liftMode (m : Mode) : (liftMode m == .rootb) = (m == .rootb) := by
  cases m <;> rfl

/-- An effect the callee may have does not touch the frame. -/
def Allowed (S : RSetup) (e : Eff) (hv : Bool) (x : Var) : Prop :=
  S.bnd x = none ∨ ∃ b hb, S.bnd x = some (b, hb) ∧ ∀ k, e.kills hv k = true → b.kills hb k = true

/-- A symbolic name, where the call places it: an `inout` argument, by the
    parameter's bound. -/
theorem sym_ren (h : S.OK) {d : Dep} (hd : d ∈ rds S.ρ S.sym) :
    ∃ w b t, d = ⟨S.ρ w, .name b t⟩ ∧ S.bnd w = some (b, false) ∧ S.pty w = t ∧ b ≠ .none ∧
      b ≠ .replace := by
  obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
  obtain ⟨w, b, t, rfl, hb, ht, hbn, hbr⟩ := h.sym_ok d0 hd0
  exact ⟨w, b, t, rfl, hb, ht, hbn, hbr⟩

/-- What a borrowed parameter depends on: the frame, at a root the callee
    cannot name, or an `inout` argument by a symbolic name. -/
theorem pe_dep (h : S.OK) {v : Var} {d : Dep} (hd : d ∈ (S.pe v).vdeps) :
    ((∀ w, S.ρ w ≠ d.root) ∧ ∃ E, S.Φ d.root = some E ∧ E.mode.isRoot = true) ∨
    (d ∈ rds S.ρ S.sym ∧ (S.pe v).ty.hasFn = true) := by
  cases hn : d.kind.isName
  · exact Or.inl (h.pe_out v d hd hn)
  · rcases h.pe_names v d hd hn with hN | hs
    · exact Or.inl (h.N_out d hN)
    · exact Or.inr hs

/-- AGORA-937 (3d): what a lifted borrowed parameter depends on: the
    caller's (its argument's path), what the callee's own entry holds,
    renamed (its region, by its handle, and its symbolic names), or what
    the arguments hold. -/
theorem liftE_rootb_dep (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    (hrb : E.mode = .rootb) {d : Dep} (hd : d ∈ (S.liftE v E).vdeps) :
    d ∈ (S.pe v).vdeps ∨
      (∃ u, d = ⟨S.ρ u, .self⟩ ∧ S.isReg u = true ∧ (⟨u, .self⟩ : Dep) ∈ E.held) := by
  obtain ⟨_, _, R, hR, hh⟩ := hab.1 v E hE hrb
  simp only [liftE, hrb, ↓reduceIte, Entry.vdeps, List.mem_append] at hd
  rcases hd with hd | hd | hd
  · left; unfold Entry.vdeps; exact List.mem_append_left _ hd
  · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
    obtain ⟨hd0, hnm⟩ := List.mem_filter.mp hd0
    have hd0' := hd0
    rw [hh] at hd0
    rcases List.mem_append.mp hd0 with hd0 | hd0
    · obtain ⟨hk, hreg⟩ := hR d0 hd0
      have hd0s : (⟨d0.root, .self⟩ : Dep) ∈ E.held := by
        obtain ⟨r, k⟩ := d0; simp only at hk ⊢; subst hk; exact hd0'
      exact Or.inr ⟨d0.root, by simp [Dep.ren, hk], hreg, hd0s⟩
    · split at hd0
      · obtain ⟨w, b, t, rfl, _⟩ := h.sym_ok d0 hd0
        simp [Kind.isName] at hnm
      · cases hd0
  · left; unfold Entry.vdeps
    split at hd
    · exact List.mem_append_right _ (List.mem_filter.mp hd).1
    · exact List.mem_append_right _ hd

/-- A borrowed parameter reaches nothing the callee can name but an `inout`
    argument, by a symbolic name. -/
theorem pe_ρ (h : S.OK) {v x : Var} {d : Dep} (hd : d ∈ (S.pe v).vdeps) (hr : d.root = S.ρ x) :
    ∃ b t, d = ⟨S.ρ x, .name b t⟩ ∧ S.bnd x = some (b, false) ∧ S.pty x = t ∧ b ≠ .none ∧
      b ≠ .replace ∧ (S.pe v).ty.hasFn = true := by
  rcases pe_dep h hd with ⟨hout, _⟩ | ⟨hs, hf⟩
  · exact absurd hr.symm (hout x)
  · obtain ⟨w, b, t, rfl, hb, ht, hbn, hbr⟩ := sym_ren h hs
    have := h.inj _ _ hr; subst this
    exact ⟨b, t, rfl, hb, ht, hbn, hbr, hf⟩

/-- AGORA-937 (3d): ... and a lifted borrowed parameter reaches a callee
    binding only by a symbolic name, or its own region, by its handle. -/
theorem liftE_rootb_ρ (h : S.OK) (hab : S.AbsOK Γa) {v x : Var} {E : Entry} (hE : Γa v = some E)
    (hrb : E.mode = .rootb) {d : Dep} (hd : d ∈ (S.liftE v E).vdeps) (hr : d.root = S.ρ x) :
    (∃ b t, d = ⟨S.ρ x, .name b t⟩ ∧ S.bnd x = some (b, false) ∧ S.pty x = t ∧ b ≠ .none ∧
      b ≠ .replace ∧ (S.pe v).ty.hasFn = true) ∨
    (d = ⟨S.ρ x, .self⟩ ∧ S.isReg x = true) := by
  rcases liftE_rootb_dep h hab hE hrb hd with hd | ⟨u, rfl, hreg, _⟩
  · exact Or.inl (pe_ρ h hd hr)
  · have := h.inj _ _ hr; subst this; exact Or.inr ⟨rfl, hreg⟩

theorem hits_false_of {e : Eff} {hv : Bool} {x : Var} {E : Entry}
    (h : ∀ d ∈ E.vdeps, d.root = x → e.kills hv d.kind = false) : hits e hv x E = false := by
  unfold hits
  cases h1 : E.vdeps.any (fun d => d.root == x && e.kills hv d.kind) with
  | false => simp
  | true =>
    obtain ⟨d, hd, hdd⟩ := List.any_eq_true.mp h1
    simp only [Bool.and_eq_true, beq_iff_eq] at hdd
    rw [h d hd hdd.1] at hdd; cases hdd.2

/-- Hitting a lifted entry is hitting the entry it lifts, for an effect the
    callee may have: a symbolic name is never ended (the parameter is not
    replaced), whether the closure handed over holds the argument or not. -/
theorem hits_lift' (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    {e : Eff} {hv : Bool} {x : Var} (ha : Allowed S e hv x) (hxr : S.isReg x = false ∨ e.kills hv .view = false) :
    hits e hv (S.ρ x) (S.liftE v E) = hits e hv x E := by
  by_cases hrb : E.mode = .rootb
  · -- on neither side is anything hit: the abstract entry holds only
    -- symbolic names, the lifted one names of `inout` arguments
    have hsym : ∀ b t, S.bnd x = some (b, false) → b ≠ .replace → e.kills hv (.name b t) = false := by
      intro b t hb hbr
      rcases ha with hn | ⟨b', hb', hbb, hk⟩
      · rw [hn] at hb; cases hb
      · rw [hb] at hbb; cases hbb
        cases e with
        | replace =>
          have := hk (.name b t) rfl
          cases b <;> simp [Eff.kills] at this <;> exact absurd rfl hbr
        | _ => rfl
    obtain ⟨_, hp, R, hR, hh⟩ := hab.1 v E hE hrb
    have h1 : hits e hv x E = false := by
      unfold hits
      simp only [Entry.vdeps, hp, hh, Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true,
        beq_iff_eq, not_and, Bool.not_eq_true]
      refine Or.inr fun d hd hr => ?_
      rw [hrb] at hd
      simp only [Mode.ownSlot, Bool.false_eq_true, ↓reduceIte, List.nil_append, List.mem_append] at hd
      rcases hd with hd | hd
      · -- AGORA-937 (item 2): a view of a region, which `x` is not, or which
        -- (item 3) the change through the region ends no view of
        rcases hxr with hxr | hk
        · exact absurd (hr ▸ (hR d hd).2) (by rw [hxr]; simp)
        · rw [(hR d hd).1]; simpa using Eff.kills_self_of_view (by simpa using hk)
      have hd' : d ∈ S.sym := by
        split at hd
        · exact hd
        · cases hd
      obtain ⟨w, b, t, rfl, hb, _, _, hbr⟩ := h.sym_ok d hd'
      simp only at hr; subst hr
      exact hsym b t hb hbr
    rw [h1]
    refine hits_false_of fun d hd hr => ?_
    -- AGORA-937 (3d): the lift holds the caller's (its argument's path, its
    -- names) and the callee's own memory, renamed: its region, by its handle
    rcases liftE_rootb_dep h hab hE hrb hd with hd | ⟨u, rfl, _, hu⟩
    · obtain ⟨b, t, rfl, hb, _, _, hbr, _⟩ := pe_ρ h hd hr
      exact hsym b t hb hbr
    · have hx : u = x := h.inj _ _ hr
      have h1' := h1
      unfold hits at h1'
      simp only [Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true, beq_iff_eq, not_and,
        Bool.not_eq_true] at h1'
      rcases h1' with h1' | h1'
      · simp [hrb] at h1'
      · exact h1' ⟨u, .self⟩ (by simp [Entry.vdeps, hrb, Mode.ownSlot, hu]) hx
  · unfold hits
    rw [liftE_ty v hrb, liftE_mode v hrb, beq_rootb_liftMode]
    congr 1
    rw [Bool.eq_iff_iff]
    simp only [List.any_eq_true, Bool.and_eq_true, beq_iff_eq]
    constructor
    · rintro ⟨d, hd, hr, hk⟩
      rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
      · exact ⟨d0, hd0, h.inj _ _ hr, hk⟩
      · exact absurd hr.symm (A_out h ha x)
    · rintro ⟨d0, hd0, hr, hk⟩
      exact ⟨d0.ren S.ρ, (mem_liftE_vdeps hrb).mpr (Or.inl ⟨d0, hd0, rfl⟩), by simp [Dep.ren, hr], hk⟩

theorem liftE_live (v : Var) (E : Entry) : (S.liftE v E).live = E.live := by
  unfold liftE; split <;> rfl

theorem liftE_dead (v : Var) (E : Entry) :
    S.liftE v { E with live := false } = { S.liftE v E with live := false } := by
  unfold liftE; split <;> simp_all

/-- A binding moved out (`live` and `dtor` cleared; never a borrowed
    parameter, which no rule moves). -/
theorem liftE_moved (v : Var) {E : Entry} (hrb : E.mode ≠ .rootb) :
    S.liftE v { E with live := false, dtor := false } = { S.liftE v E with live := false, dtor := false } := by
  unfold liftE; split <;> simp_all

theorem killE_lift' (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    {e : Eff} {hv : Bool} {x : Var} (ha : Allowed S e hv x) (hxr : S.isReg x = false ∨ e.kills hv .view = false) :
    killE e hv (S.ρ x) (S.liftE v E) = S.liftE v (killE e hv x E) := by
  unfold killE
  rw [hits_lift' h hab hE ha hxr]
  split
  · exact (liftE_dead v E).symm
  · rfl

theorem Eff.kills_mono {e b : Eff} (hle : e.le b) (hv : Bool) (k : Kind) (hk : e.kills hv k = true) :
    b.kills hv k = true := by
  unfold Eff.le Eff.leb at hle
  cases e <;> cases b <;> cases k <;> simp_all [Eff.kills]

theorem killE_frame (h : S.OK) {e : Eff} {hv : Bool} {x : Var} (ha : Allowed S e hv x)
    {y : Var} {E : Entry} (hy : S.Φ y = some E) : killE e hv (S.ρ x) E = E := by
  by_cases hl : E.live = true
  · unfold killE
    cases hh : hits e hv (S.ρ x) E with
    | false => rfl
    | true =>
      exfalso
      unfold hits at hh
      simp only [Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq,
        List.any_eq_true] at hh
      obtain ⟨hn, d, hd, hr, hk⟩ := hh
      obtain ⟨b, hv', hb, hkb⟩ := h.Φsat y E hy hl hn d hd x hr.symm
      rcases ha with hn' | ⟨b', hb'⟩
      · rw [hn'] at hb; cases hb
      · obtain ⟨hbb, hb', hle⟩ := hb'
        rw [hb] at hb'; cases hb'
        rw [hle _ hk] at hkb; cases hkb
  · unfold killE
    split
    · cases E; simp_all
    · rfl

/-- A2-drop.2: lifting keeps what a binding depends on in memory where the
    renaming puts it; what it may additionally hold, the arguments' (`A`),
    is no callee binding's. -/
theorem hitsMem_lift (h : S.OK) {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) (e : Eff) (hv : Bool)
    (x : Var) : hitsMem e hv (S.ρ x) (S.liftE v E) = hitsMem e hv x E := by
  have hg : ((S.liftE v E).ty != .int || (S.liftE v E).mode == .rootb) =
      (E.ty != .int || E.mode == .rootb) := by
    rw [liftE_ty v hrb, liftE_mode v hrb]
    have : (liftMode E.mode == .rootb) = (E.mode == .rootb) := by
      cases E.mode <;> first | rfl | exact absurd rfl hrb
    rw [this]
  unfold hitsMem; rw [hg]
  congr 1
  apply Bool.eq_iff_iff.mpr
  rw [List.any_eq_true, List.any_eq_true]
  constructor
  · intro ⟨d, hd, hk⟩
    rcases (mem_liftE_vdeps hrb).mp hd with ⟨d0, hd0, hdeq⟩ | ha
    · subst hdeq
      refine ⟨d0, hd0, ?_⟩
      simp only [Bool.and_eq_true, beq_iff_eq, Dep.ren] at hk ⊢
      exact ⟨⟨h.inj _ _ hk.1.1, hk.1.2⟩, hk.2⟩
    · simp only [Bool.and_eq_true, beq_iff_eq] at hk
      exact absurd hk.1.1.symm (A_out h (S.liftDeps_sub E ha) x)
  · intro ⟨d0, hd0, hk⟩
    refine ⟨d0.ren S.ρ, (mem_liftE_vdeps hrb).mpr (Or.inl ⟨d0, hd0, rfl⟩), ?_⟩
    simp only [Bool.and_eq_true, beq_iff_eq, Dep.ren] at hk ⊢
    exact ⟨⟨by rw [hk.1.1], hk.1.2⟩, hk.2⟩

/-- A2-drop.2: renaming keeps an effect safe for the bindings that run a
    destructor. The callee's own keep their flag and their views through
    `liftE` (`hitsMem_lift`); a borrowed parameter runs none; the frame's
    live ones are not reached (`Φsat`), and its dead ones depend on
    nothing. -/
theorem DtorSafe.canon (h : S.OK) {e : Eff} {hv : Bool} {x : Var}
    (ha : Allowed S e hv x) (hd : DtorSafe Γa e hv x) : DtorSafe (S.canon Γa) e hv (S.ρ x) := by
  intro y E hy hdt hos
  rcases canon_cases_sub h Γa y with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨hyf, hc⟩
  · rw [hc] at hy
    obtain ⟨Ea, hEa, rfl⟩ := Option.map_eq_some_iff.mp hy
    simp only [Function.comp, subE_dtor, subE_mode] at hdt hos ⊢
    apply hitsMem_subE h
    by_cases hrb : Ea.mode = .rootb
    · simp only [liftE, hrb, ↓reduceIte, h.pe_dtor] at hdt; cases hdt
    · rw [hitsMem_lift h hrb]
      exact hd v Ea hEa (by simpa [liftE, hrb] using hdt)
        (by rw [liftE_mode v hrb, liftMode_ownSlot] at hos; exact hos)
  · rw [hc] at hy; cases hy
  · rw [hc] at hy
    by_cases hl : E.live = true
    · have := killE_frame h ha hy
      unfold killE at this
      cases hh : hits e hv (S.ρ x) E with
      | false => exact hitsMem_of_hits hh
      | true => rw [hh] at this; simp only [↓reduceIte] at this; rw [← this] at hl; cases hl
    · -- dead and armed (a maybe-moved one): what it views of the callee's is
      -- an `inout` argument its bound spares (`Φdt`), as for a live one
      unfold hitsMem
      cases hg : (E.ty != .int || E.mode == .rootb) with
      | false => rfl
      | true =>
        have hg' : E.ty ≠ .int ∨ E.mode = .rootb := by
          simpa only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq] using hg
        simp only [Bool.true_and, List.any_eq_false, Bool.and_eq_true, beq_iff_eq, not_and]
        intro d hdd hr hk
        obtain ⟨b, hb1, hbx, hkb⟩ := h.Φdt y E hy hdt hos hg' d hdd (by simpa using hr.2) x hr.1.symm
        rcases ha with ha | ⟨b', hb2, hbx', hkill⟩
        · rw [ha] at hbx; cases hbx
        · rw [hbx'] at hbx; cases hbx
          rw [hkill d.kind hk] at hkb; cases hkb


/-- AGORA-374: renaming keeps a context free of dependencies inside an
    element by its index on a binding the callee may grow: the callee's own
    entries keep their dependencies through `liftE` (a borrowed parameter's
    are names and handles), and the frame's, live or armed, depend on the
    argument only in ways its bound spares (`Φsat`, `Φdt`), which a growth
    the bound allows (`Allowed … .realloc`) does not. -/
theorem NoIdx.canon (h : S.OK) (hab : S.AbsOK Γa) {hv : Bool} {x : Var}
    (ha : Allowed S .realloc hv x) (hn : NoIdx Γa x) : NoIdx (S.canon Γa) (S.ρ x) := by
  rintro k ⟨y, E, hy, hnt, hl, hd⟩ i rfl
  rcases canon_cases_sub h Γa y with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨_, hc⟩
  · rw [hc] at hy
    obtain ⟨Ea, hEa, rfl⟩ := Option.map_eq_some_iff.mp hy
    simp only [Function.comp_apply] at hnt hl hd
    rw [subE_vdeps] at hd
    obtain ⟨d1, hd1, hdd⟩ := List.mem_flatMap.mp hd
    rcases S.subD_frame h hdd with rfl | ⟨hout, _⟩
    · by_cases hrb : Ea.mode = .rootb
      · rcases liftE_rootb_ρ h hab hEa hrb hd1 rfl with ⟨b, t, he, _⟩ | ⟨he, _⟩ <;> cases he
      · rcases liftE_vdeps_cases hrb hd1 with ⟨⟨r0, k0⟩, hd0, he⟩ | hA
        · simp only [Dep.ren, Dep.mk.injEq] at he
          obtain ⟨hr, rfl⟩ := he
          have hr0 := h.inj _ _ hr; subst hr0
          refine hn _ ⟨v, Ea, hEa, ?_, ?_, hd0⟩ i rfl
          · rw [subE_ty, subE_mode, liftE_ty v hrb, liftE_mode v hrb] at hnt
            exact hnt.imp id (fun h' => absurd (liftMode_rootb.mp h') hrb)
          · rw [subE_live, liftE_live, subE_dtor, liftE_dtor' h v Ea, subE_mode, liftE_mode v hrb,
              liftMode_ownSlot] at hl
            simpa [hrb] using hl
        · exact A_out h hA x rfl
    · exact hout x rfl
  · rw [hc] at hy; cases hy
  · rw [hc] at hy
    obtain ⟨b, hv', hbx, hk⟩ : ∃ b hv', S.bnd x = some (b, hv') ∧ b.kills hv' (.innerAt i) = false := by
      rcases hl with hl | ⟨hdt, hos⟩
      · exact h.Φsat y E hy hl hnt _ hd x rfl
      · exact h.Φdt y E hy hdt hos hnt _ hd rfl x rfl
    rcases ha with ha | ⟨b', hb', hbx', hkill⟩
    · rw [ha] at hbx; cases hbx
    · rw [hbx'] at hbx; cases hbx
      rw [hkill (.innerAt i) (by simp [Eff.kills])] at hk; cases hk

/-- AGORA-937 (3d, route U): a change that spares a borrowed parameter's
    views of its root spares them where the call places it: a lifted
    parameter's held is the callee's, renamed, and the argument's own (no
    callee root, `pe_out`); the frame's are spared by the `inout`
    parameter's bound (`Φsat`), which allows the change (`Allowed`). -/
theorem HeldOK.canon (h : S.OK) {Γa : Ctx} {e : Eff} {x : Var} (ha : Allowed S e false x)
    (hd : HeldOK Γa e x) : HeldOK (S.canon Γa) e (S.ρ x) := by
  intro y E hy hm d hdh hdr hk
  have hn : d.kind.isName = false := by rcases hk with h | h <;> rw [h] <;> rfl
  rcases canon_cases_sub h Γa y with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨_, hc⟩
  · rw [hc] at hy
    obtain ⟨Ea, hEa, rfl⟩ := Option.map_eq_some_iff.mp hy
    simp only [Function.comp, subE_mode] at hm
    by_cases hrb : Ea.mode = .rootb
    · have hdh' : d ∈ (S.liftE v Ea).held := S.mem_subE_held_ρ h hdh hdr
      unfold liftE at hdh'; simp only [hrb, ↓reduceIte] at hdh'
      rcases List.mem_append.mp hdh' with h1 | h1
      · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
        have hx : d0.root = x := h.inj _ _ hdr
        exact hd v Ea hEa hrb d0 (List.mem_filter.mp hd0).1 hx hk
      · have hpe : d ∈ (S.pe v).held := by
          split at h1
          · exact (List.mem_filter.mp h1).1
          · exact h1
        have := (h.pe_out v d (by unfold Entry.vdeps; exact List.mem_append_right _ hpe) hn).1 x
        exact absurd hdr.symm this
    · rw [liftE_mode _ hrb] at hm
      exact absurd (by cases hme : Ea.mode <;> simp_all [liftMode]) hrb
  · rw [hc] at hy; cases hy
  · rw [hc] at hy
    have hl := h.Φrb y E hy hm
    obtain ⟨b, hv, hb, hk'⟩ := h.Φsat y E hy hl (Or.inr hm) d
      (by unfold Entry.vdeps; exact List.mem_append_right _ hdh) x hdr.symm
    rcases ha with hnb | ⟨b', hb', hbb, hall⟩
    · rw [hnb] at hb; cases hb
    · rw [hb] at hbb; cases hbb
      cases hkk : e.kills false d.kind
      · rfl
      · exact absurd (hall _ hkk) (by rw [hk']; simp)
theorem canon_kill' (h : S.OK) (hab : S.AbsOK Γa) {e : Eff} {hv : Bool} {x : Var}
    (ha : Allowed S e hv x) (hnp : S.isPi x = false) (hxr : S.isReg x = false ∨ e.kills hv .view = false) :
    S.canon (kill e hv x Γa) = kill e hv (S.ρ x) (S.canon Γa) := by
  funext y
  rcases canon_cases_sub h Γa y with ⟨v, rfl, hp, hc⟩ | ⟨v, rfl, hp, hc⟩ | ⟨hy, hc⟩
  · rw [canon_ρs h _ hp, A2.kill, A2.kill, hc]
    cases hE : Γa v with
    | none => rfl
    | some E =>
      simp only [Option.map_some, Function.comp]
      rw [killE_subE h hnp, killE_lift' h hab hE ha hxr]
  · rw [A2.kill, hc, canon_ρ_sub h, hp]; rfl
  · rw [canon_frame _ hy, A2.kill, hc]
    cases hE : S.Φ y with
    | none => rfl
    | some E => simp only [Option.map_some]; rw [killE_frame h ha hE]

theorem hits_lift (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    {e : Eff} {hv : Bool} {x : Var} (ha : Allowed S e hv x) (hxr : S.isReg x = false) :
    hits e hv (S.ρ x) (S.liftE v E) = hits e hv x E := hits_lift' h hab hE ha (Or.inl hxr)

theorem killE_lift (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    {e : Eff} {hv : Bool} {x : Var} (ha : Allowed S e hv x) (hxr : S.isReg x = false) :
    killE e hv (S.ρ x) (S.liftE v E) = S.liftE v (killE e hv x E) := killE_lift' h hab hE ha (Or.inl hxr)

theorem canon_kill (h : S.OK) (hab : S.AbsOK Γa) {e : Eff} {hv : Bool} {x : Var}
    (ha : Allowed S e hv x) (hnp : S.isPi x = false) (hxr : S.isReg x = false) :
    S.canon (kill e hv x Γa) = kill e hv (S.ρ x) (S.canon Γa) := canon_kill' h hab ha hnp (Or.inl hxr)

/-- AGORA-937: `canon_exitScope` with regions, for a binding at no region's
    index. -/
theorem canon_exitScopes (h : S.OK) (hab : S.AbsOK Γa) {x : Var} (ha : Allowed S .replace false x)
    (hnr : S.isReg x = false) :
    S.canon (exitScope x Γa) = exitScope (S.ρ x) (S.canon Γa) := by
  have hnp := hab.notPi_of_notReg hnr
  unfold exitScope
  rw [canon_upds h _ hnp, canon_kill h hab ha hnp hnr]
  rfl

theorem append_sub {a b c d : List Dep} (h1 : a ⊆ b) (h2 : c ⊆ d) : a ++ c ⊆ b ++ d := by
  intro x hx
  rcases List.mem_append.mp hx with h | h
  · exact List.mem_append_left _ (h1 h)
  · exact List.mem_append_right _ (h2 h)

theorem rds_subset {ρ : Var → Var} {a b : List Dep} (hs : a ⊆ b) : rds ρ a ⊆ rds ρ b := by
  intro d hd
  obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
  exact mem_rds.mpr ⟨d0, hs hd0, rfl⟩

/-- A2-drop.2: lifting keeps whether a binding may run a destructor, and was
    made by `letd`; a borrowed parameter's entry is neither. -/
theorem liftE_dbind (h : S.OK) (v : Var) (E : Entry) :
    (S.liftE v E).dbind = if E.mode = .rootb then false else E.dbind := by
  unfold liftE; split <;> simp [h.pe_dbind]

theorem liftE_dtor' (h : S.OK) (v : Var) (E : Entry) :
    (S.liftE v E).dtor = if E.mode = .rootb then false else E.dtor := by
  unfold liftE; split <;> simp [h.pe_dtor]

theorem ownHeld_sub_mono {o : Bool} {t : Ty} {X Y : List Dep} (h : X ⊆ Y) : ownHeld o t X ⊆ ownHeld o t Y := by
  unfold ownHeld; split
  · exact List.Subset.refl _
  · exact h

/-- Agora #916: a weaker entry is lifted with at least as much: a held-fresh
    weaker borrow has a held-fresh stronger one (`EntryWeaker.heldFresh`). -/
theorem heldA_mono {E E' : Entry} (hw : EntryWeaker E E') : S.heldA E ⊆ S.heldA E' := by
  by_cases hp : HeldP E'
  · have hE : HeldP E := ⟨hw.heldFresh hp.2.2 hp.2.1 hp.1, by rw [← hw.mode]; exact hp.2.1,
      by rw [← hw.ty]; exact hp.2.2⟩
    rw [S.heldA_P hp, S.heldA_P hE, hw.ty]; exact List.Subset.refl _
  · rw [S.heldA_notP hp]; exact S.heldA_sub E

theorem liftE_weaker {v : Var} {E E' : Entry} (hw : EntryWeaker E E') (hnr : E.mode = .region → E.ty = .int) :
    EntryWeaker (S.liftE v E) (S.liftE v E') := by
  have hw0 := hw
  have hdb := hw.dbind
  have hra := hw.raise
  have hdh := hw.dheld
  have hwf := hw.fresh
  obtain ⟨ht, hm, hr, hl, hd⟩ := hw
  by_cases hrb : E.mode = .rootb
  · rw [hr (Or.inl hrb)]; exact EntryWeaker.refl _
  · have hrb' : E'.mode ≠ .rootb := by rw [hm]; exact hrb
    refine ⟨by rw [liftE_ty v hrb', liftE_ty v hrb, ht], by rw [liftE_mode v hrb', liftE_mode v hrb, hm],
      fun h' => absurd h' (liftE_not_fixed hrb), fun hl' => ?_, fun h => by
        simp only [liftE, hrb, hrb', ↓reduceIte] at h ⊢
        obtain ⟨hd', hh⟩ := hd h
        refine ⟨hd', ?_⟩
        rw [hm, ht]; exact append_sub (rds_subset hh) (ownHeld_sub_mono (S.heldA_mono hw0)),
      by simp only [liftE, hrb, hrb', ↓reduceIte]; exact hdb,
      fun h => by simp only [liftE, hrb, hrb', ↓reduceIte] at h ⊢; exact hra h,
      fun h hos hn d hnm => by
        simp only [liftE, hrb, hrb', ↓reduceIte] at h hos hn ⊢
        have hos0 : E.mode.ownSlot = true := by rwa [liftMode_ownSlot] at hos
        have hn0 : E.ty ≠ .int ∨ E.mode = .rootb := by
          rcases hn with h' | h'
          · exact Or.inl h'
          · exact absurd (liftMode_rootb.mp h') hrb
        rw [hm, ht, S.heldA_own hos0, S.heldA_own (by rw [hm]; exact hos0)]
        simp only [List.mem_append]
        rw [rds_mem_congr (hdh h hos0 hn0) hnm],
      fun hl' hn' hb' hf' => by
        simp only [liftE, hrb, hrb', ↓reduceIte] at hl' hn' hb' hf' ⊢
        have hb0 : E'.mode = .bor := by revert hb'; cases E'.mode <;> simp [liftMode]
        obtain ⟨hfE, hsub⟩ := hwf hl' hn' hb0 hf'
        have hEb : E.mode = .bor := by rw [← hm]; exact hb0
        have hEn : E.ty ≠ .int := by rw [← ht]; exact hn'
        refine ⟨hfE, ?_⟩
        simp [hEb, hb0, Mode.ownSlot, hfE, hf', hEn, hn']
        exact rds_subset hsub,
      fun hn hb hhf => by
        rw [liftE_heldFresh, ite_eq_right hrb'] at hhf; rw [liftE_heldFresh, ite_eq_right hrb]
        rw [liftE_ty v hrb'] at hn; rw [liftE_mode v hrb'] at hb
        have hb0 : E'.mode = .bor := by revert hb; cases E'.mode <;> simp [liftMode]
        exact hw0.heldFresh hn hb0 hhf⟩
    rw [liftE_live] at hl'
    obtain ⟨hl0, hp, hh⟩ := hl hl'
    refine ⟨by rw [liftE_live]; exact hl0, fun ho => ?_, ?_⟩
    · rw [liftE_mode v hrb, liftMode_ownSlot] at ho
      simp only [liftE, hrb, ↓reduceIte, hm, ho, Bool.false_or, ht]
      by_cases hfl : (E'.fresh && E.ty != .int) = true
      · simp only [Bool.and_eq_true, bne_iff_ne, ne_eq] at hfl
        -- (a region binding is an integer's place: it is no case here)
        have hb0 : E'.mode = .bor := by
          have hnr' : E.mode ≠ .region := fun hr => hfl.2 (hnr hr)
          rw [hm]; revert ho hrb hnr'; cases E.mode <;> simp [Mode.ownSlot]
        obtain ⟨hfE, _⟩ := hwf hl' (by rw [ht]; exact hfl.2) hb0 hfl.1
        simp [hfE, hfl.1, hfl.2]
        exact rds_subset (hp ho)
      · rw [ite_eq_right hfl]
        exact append_sub (rds_subset (hp ho)) (by split <;> simp)
    · simp only [liftE, hrb, ↓reduceIte, hm, ht]
      exact append_sub (rds_subset hh) (ownHeld_sub_mono (S.heldA_mono hw0))

theorem liftE_root (h : S.OK) {v : Var} {E : Entry} :
    (S.liftE v E).mode.isRoot = E.mode.isRoot := by
  by_cases hrb : E.mode = .rootb
  · simp only [liftE, hrb, ↓reduceIte]; rw [h.pe_rb]
  · rw [liftE_mode v hrb, liftMode_isRoot]

theorem liftE_rootb (h : S.OK) {v : Var} {E : Entry} : (S.liftE v E).mode = .rootb ↔ E.mode = .rootb := by
  by_cases hrb : E.mode = .rootb
  · simp only [liftE, hrb, ↓reduceIte]; rw [h.pe_rb]; simp
  · rw [liftE_mode v hrb, liftMode_rootb]

theorem liftE_ty' (_h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E) :
    (S.liftE v E).ty = E.ty := by
  by_cases hrb : E.mode = .rootb
  · simp [liftE, hrb, (hab.1 v E hE hrb).1]
  · exact liftE_ty v hrb

/-- A3.5: an owner (or an `inout` parameter) stays one where the call places
    it. -/
theorem lockOf_lift_os {v : Var} {E : Entry} (hos : E.mode.ownSlot = true) : (S.liftE v E).mode.ownSlot = true := by
  have hrb : E.mode ≠ .rootb := fun h => by rw [h] at hos; cases hos
  rw [liftE_mode v hrb, liftMode_ownSlot]; exact hos

/-- A3.5: so a share `withLock` may check out stays one. -/
theorem _root_.A2.Entry.lockOf.lift {v : Var} {E : Entry} {t : Ty} (hty : (S.liftE v E).ty = E.ty)
    (h : E.lockOf t) : (S.liftE v E).lockOf t := by
  rcases h with h | h
  · exact Or.inl (hty.trans h)
  · exact Or.inr (hty.trans h)

/-- AGORA-937: a dependency the substitution keeps, on a callee binding, is on
    no region: a region's would have been replaced by what it stands for,
    whose roots are the frame's, or (a name) dropped. -/
theorem subD_kept (h : S.OK) {r : Var} {k : Kind} {e : Dep} (he : e ∈ S.subD ⟨S.ρ r, k⟩)
    (her : e.root = S.ρ r) : S.isPi r = false := by
  cases hp : S.isPi r
  · rfl
  · exfalso
    cases hk : k.isName
    · simp only [subD, inv_ρ h, hp, hk, Bool.false_eq_true, ↓reduceIte, List.mem_map] at he
      obtain ⟨e0, he0, rfl⟩ := he
      exact (S.σ_frame h he0).1 r her.symm
    · simp [subD, inv_ρ h, hp, hk] at he

/-- ... so its root is bound where the call places the body, as the callee
    bound it. -/
theorem canon_root_sub (h : S.OK) {r : Var} {Er : Entry} (hEr : Γa r = some Er) (hro : Er.mode.isRoot = true)
    (hnp : S.isPi r = false) :
    ∃ E', S.canon Γa (S.ρ r) = some E' ∧ E'.mode.isRoot = true :=
  ⟨S.subE (S.liftE r Er), by rw [canon_ρ_sub h, hnp, hEr]; rfl, by
    rw [subE_mode, liftE_root h]; exact hro⟩

theorem canon_frameRoot (_h : S.OK) {r : Var} (hr : ∀ v, S.ρ v ≠ r)
    (hex : ∃ Er, S.Φ r = some Er ∧ Er.mode.isRoot = true) :
    ∃ E', S.canon Γa r = some E' ∧ E'.mode.isRoot = true := by
  rw [canon_frame _ hr]; exact hex

/-- AGORA-937: a kept or substituted dependency of a lifted binding is
    rooted where the call places the body: a callee root (on no region,
    `subD_kept`) lifted, a frame root, or what a region stands for, which is
    the frame's (`σ_frame`). -/
theorem canon_root_of_subD (h : S.OK) (hab : S.AbsOK Γa) {d e : Dep} (he : e ∈ S.subD d)
    (hd : (∃ r Er, d.root = S.ρ r ∧ Γa r = some Er ∧ Er.mode.isRoot = true ∧
        (d.kind.isName = true → Er.mode ≠ .region)) ∨
      ((∀ w, S.ρ w ≠ d.root) ∧ ∃ E, S.Φ d.root = some E ∧ E.mode.isRoot = true)) :
    ∃ E', S.canon Γa e.root = some E' ∧ E'.mode.isRoot = true := by
  rcases S.mem_subD he with rfl | ⟨v, _, _, hv⟩
  · rcases hd with ⟨r, Er, hr, hEr, hro, hnr⟩ | ⟨hout, hex⟩
    · have hnp : S.isPi r = false := by
        cases hk : e.kind.isName
        · obtain ⟨dr, dk⟩ := e
          simp only at hr hk; subst hr
          exact subD_kept h he rfl
        · exact hab.notPi hEr (hnr hk)
      rw [hr]; exact canon_root_sub h hEr hro hnp
    · exact canon_frameRoot h hout hex
  · obtain ⟨hout, hex⟩ := S.σ_frameC h hv
    exact canon_frameRoot h hout hex

/-- AGORA-937: `canon_wf`'s first clause with regions: a live lifted binding's
    roots are bound where the call places the body, as roots. A dependency is
    kept (a callee root, lifted, or a frame root) or is what a region stands
    for (a frame root). -/
theorem canon_live_sub (h : S.OK) (hab : S.AbsOK Γa) (hw : CtxWF Γa) (hnW : NameWF Γa) {y : Var} {E' : Entry}
    (hy : S.canon Γa y = some E') (hl : E'.live = true) (hn : E'.ty ≠ .int ∨ E'.mode = .rootb)
    {r : Var} (hr : r ∈ roots E'.vdeps) : ∃ Er, S.canon Γa r = some Er ∧ Er.mode.isRoot = true := by
  rcases canon_cases_sub h Γa y with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨hyf, hc⟩
  · rw [hc] at hy
    cases hE : Γa v with
    | none => rw [hE] at hy; cases hy
    | some E =>
      rw [hE] at hy; simp only [Option.map_some, Option.some.injEq, Function.comp] at hy; subst hy
      rw [subE_vdeps] at hr
      obtain ⟨e, he, rfl⟩ := List.mem_map.mp hr
      obtain ⟨d, hd, hed⟩ := List.mem_flatMap.mp he
      refine canon_root_of_subD h hab hed ?_
      by_cases hrb : E.mode = .rootb
      · have hsym : ∀ {d : Dep}, d ∈ rds S.ρ S.sym → (∃ r Er, d.root = S.ρ r ∧ Γa r = some Er ∧
            Er.mode.isRoot = true ∧ (d.kind.isName = true → Er.mode ≠ .region)) := by
          intro d hs
          obtain ⟨w, b, t, rfl, hb, _, _, _⟩ := sym_ren h hs
          obtain ⟨Ew, hEw, hm, _⟩ := hab.2.2.1 w (b, false) hb
          exact ⟨w, Ew, rfl, hEw, by rw [hm]; rfl, fun _ => by rw [hm]; simp⟩
        rcases liftE_rootb_dep h hab hE hrb hd with hd | ⟨u, rfl, hreg, _⟩
        · rcases pe_dep h hd with ⟨hout, hex⟩ | ⟨hs, _⟩
          · exact Or.inr ⟨hout, hex⟩
          · exact Or.inl (hsym hs)
        · obtain ⟨Eu, hEu, hmu⟩ := hab.2.2.2.2.1 u hreg
          exact Or.inl ⟨u, Eu, rfl, hEu, by rw [hmu]; rfl, fun hk => by simp [Kind.isName] at hk⟩
      · rw [subE_live, liftE_live] at hl
        have hn' : E.ty ≠ .int ∨ E.mode = .rootb := by
          rcases hn with h' | h'
          · rw [subE_ty, liftE_ty v hrb] at h'; exact Or.inl h'
          · rw [subE_mode, liftE_rootb h] at h'; exact absurd h' hrb
        rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
        · obtain ⟨Er, hEr, hro⟩ := hw v E hE hl hn' d0.root (List.mem_map_of_mem hd0)
          -- a name's root owns its slot (`NameWF`), and a region does not
          refine Or.inl ⟨d0.root, Er, rfl, hEr, hro, fun hk => ?_⟩
          cases hkd : d0.kind with
          | name b t =>
            obtain ⟨Er', hEr', _, _, _, ho, _⟩ := hnW v E hE hl hn' d0 hd0 b t hkd
            rw [hEr] at hEr'; cases hEr'
            intro hr; rw [hr] at ho; cases ho
          | _ => simp [Dep.ren, hkd, Kind.isName] at hk
        · exact Or.inr ⟨A_out h ha, A_root h ha⟩
  · rw [hc] at hy; cases hy
  · rw [hc] at hy
    by_cases hrr : ∃ v, S.ρ v = r
    · obtain ⟨v, rfl⟩ := hrr
      obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
      obtain ⟨b, hv, hb, _⟩ := h.Φsat y E' hy hl hn d hd v hdr.symm
      obtain ⟨Ev, hEv, hm, _⟩ := hab.2.2.1 v (b, hv) hb
      -- (an `inout` argument's binding: no region, so at no region's index)
      exact canon_root_sub h hEv (by rw [hm]; rfl) (hab.notPi hEv (by rw [hm]; simp))
    · have hout : ∀ v, S.ρ v ≠ r := fun v hv => hrr ⟨v, hv⟩
      exact canon_frameRoot h hout (h.Φwf y E' hy hl hn r hr hout)

/-- AGORA-937: `canon_wf` with regions: the lifted context is well formed
    under the lift's substitution. -/
theorem canon_wf_sub (h : S.OK) (hab : S.AbsOK Γa) (hw : CtxWF Γa) (hnW : NameWF Γa) :
    CtxWF (S.canon Γa) := by
  refine ⟨fun y E' hy hl hn r hr => canon_live_sub h hab hw hnW hy hl hn hr,
    fun y E' hy hd hos hn d hdd hnm => ?_, fun y E' hy ha => ?_, fun y E' hy hd => ?_⟩
  · rcases canon_cases_sub h Γa y with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨hyf, hc⟩
    · rw [hc] at hy
      cases hE : Γa v with
      | none => rw [hE] at hy; cases hy
      | some E =>
        rw [hE] at hy; simp only [Option.map_some, Option.some.injEq, Function.comp] at hy; subst hy
        rw [subE_dbind] at hd
        rw [subE_vdeps] at hdd
        obtain ⟨d1, hd1, hdd1⟩ := List.mem_flatMap.mp hdd
        by_cases hrb : E.mode = .rootb
        · rw [liftE_dbind h, ite_eq_left hrb] at hd; cases hd
        · rw [liftE_dbind h, ite_eq_right hrb] at hd
          have hos0 : E.mode.ownSlot = true := by rwa [subE_mode, liftE_mode v hrb, liftMode_ownSlot] at hos
          have hn' : E.ty ≠ .int ∨ E.mode = .rootb := by
            rcases hn with h' | h'
            · rw [subE_ty, liftE_ty v hrb] at h'; exact Or.inl h'
            · rw [subE_mode, liftE_rootb h] at h'; exact absurd h' hrb
          rcases S.mem_subD hdd1 with rfl | ⟨_, _, _, hv⟩
          · refine canon_root_of_subD h hab hdd1 ?_
            rcases liftE_vdeps_cases hrb hd1 with ⟨d0, hd0, rfl⟩ | ha
            · obtain ⟨Er, hEr, hro⟩ := hw.dtor v E hE hd hos0 hn' d0 hd0 (by simpa [Dep.ren] using hnm)
              exact Or.inl ⟨d0.root, Er, rfl, hEr, hro, fun hk => absurd hk (by simpa [Dep.ren] using hnm)⟩
            · exact Or.inr ⟨A_out h ha, A_root h ha⟩
          · obtain ⟨hout, hex⟩ := S.σ_frameC h hv
            exact canon_frameRoot h hout hex
    · rw [hc] at hy; cases hy
    · rw [hc] at hy
      rcases h.Φdb y E' hy hd hos hn d hdd hnm with ⟨v, bh, hv, hb⟩ | ⟨hout, hex⟩
      · obtain ⟨Ev, hEv, hm, _⟩ := hab.2.2.1 v bh hb
        rw [← hv]; exact canon_root_sub h hEv (by rw [hm]; rfl) (hab.notPi hEv (by rw [hm]; simp))
      · exact canon_frameRoot h hout hex
  · rcases canon_cases_sub h Γa y with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨hyf, hc⟩
    · rw [hc] at hy
      cases hE : Γa v with
      | none => rw [hE] at hy; cases hy
      | some E =>
        rw [hE] at hy; simp only [Option.map_some, Option.some.injEq, Function.comp] at hy; subst hy
        rw [subE_dtor] at ha; rw [subE_dbind]
        by_cases hrb : E.mode = .rootb
        · rw [liftE_dtor' h, ite_eq_left hrb] at ha; cases ha
        · rw [liftE_dtor' h, ite_eq_right hrb] at ha
          rw [liftE_dbind h, ite_eq_right hrb]; exact hw.arm v E hE ha
    · rw [hc] at hy; cases hy
    · rw [hc] at hy; exact h.Φarm y E' hy ha
  · rcases canon_cases_sub h Γa y with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨hyf, hc⟩
    · rw [hc] at hy
      cases hE : Γa v with
      | none => rw [hE] at hy; cases hy
      | some E =>
        rw [hE] at hy; simp only [Option.map_some, Option.some.injEq, Function.comp] at hy; subst hy
        rw [subE_dbind] at hd; rw [subE_ty]
        by_cases hrb : E.mode = .rootb
        · rw [liftE_dbind h, ite_eq_left hrb] at hd; cases hd
        · rw [liftE_dbind h, ite_eq_right hrb] at hd
          rw [liftE_ty v hrb]; exact hw.view v E hE hd
    · rw [hc] at hy; cases hy
    · rw [hc] at hy; exact h.Φview y E' hy hd

theorem allKinds_notName {rs : List Var} {d : Dep} (h : d ∈ allKinds rs) : d.kind.isName = false := by
  simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil, or_false] at h
  obtain ⟨r, _, hd⟩ := h
  rcases hd with rfl | rfl | rfl | rfl <;> rfl

/-- A symbolic name, where the call places it, names a binding the caller's
    view has: the `inout` argument, lifted, owns its slot, holds nothing and
    allows the bound. -/
theorem sym_named (h : S.OK) (hab : S.AbsOK Γa) {d : Dep} (hs : d ∈ rds S.ρ S.sym) {b : Eff} {t : Ty}
    (hk : d.kind = .name b t) :
    ∃ Er, S.canon Γa d.root = some Er ∧ Er.live = true ∧ Er.held = [] ∧ Er.ty = t ∧
      Er.mode.ownSlot = true ∧ (b = .none ∨ b ≠ .replace ∧ canDo Er.mode b) ∧ t.holdsView = false := by
  obtain ⟨w, b', t', hd, hb, hpt, _, hbr⟩ := sym_ren h hs
  subst hd
  simp only [Kind.name.injEq] at hk
  obtain ⟨hb1, ht1⟩ := hk
  subst hb1 ht1
  obtain ⟨Ew, hEw, hm, hty, hfx⟩ := hab.2.2.1 w (b', false) hb
  obtain ⟨_, hbs⟩ := hab.2.1 w Ew b' hEw hm
  rw [hb] at hbs; simp only [Option.some.injEq, Prod.mk.injEq] at hbs
  have hvv : Ew.ty.holdsView = false := by rw [← elem_holdsView]; exact hbs.2.symm
  obtain ⟨hlv, hhv'⟩ := hfx (Or.inr ⟨b', hm, hbr, hvv⟩)
  have hrb' : Ew.mode ≠ .rootb := by rw [hm]; simp
  -- (an `inout` parameter: no region)
  have hnp : S.isPi w = false := hab.notPi hEw (by rw [hm]; simp)
  refine ⟨S.subE (S.liftE w Ew), canon_some h hEw hnp, by rw [subE_live, liftE_live]; exact hlv,
    by rw [subE_held, liftE_held_named hrb' (by rw [hm]; rfl) hhv' hvv]; rfl,
    by rw [subE_ty, liftE_ty _ hrb', hty, hpt],
    by rw [subE_mode, liftE_mode _ hrb', hm]; rfl, Or.inr ⟨hbr, ?_⟩, by rw [← hpt, ← hty]; exact hvv⟩
  rw [subE_mode, liftE_mode _ hrb', hm]; exact Or.inl rfl

/-- AGORA-937: `canon_names` with regions. What a region stands for names
    nothing (it is every memory way of reaching the arguments' roots), and a
    kept name dependency on a callee binding is on no region. -/
theorem canon_names_sub (h : S.OK) (hab : S.AbsOK Γa) (hn : NameWF Γa) : NameWF (S.canon Γa) := by
  intro y E' hy hl hnn e he b t hk
  rcases canon_cases_sub h Γa y with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨hyf, hc⟩
  · rw [hc] at hy
    cases hE : Γa v with
    | none => rw [hE] at hy; cases hy
    | some E =>
      rw [hE] at hy; simp only [Option.map_some, Option.some.injEq, Function.comp] at hy; subst hy
      rw [subE_vdeps] at he
      obtain ⟨d, hd, hed⟩ := List.mem_flatMap.mp he
      rcases S.mem_subD hed with rfl | ⟨_, _, _, hv⟩
      · by_cases hrb : E.mode = .rootb
        · have hN' : e ∈ S.N ∨ e ∈ rds S.ρ S.sym := by
            rcases liftE_rootb_dep h hab hE hrb hd with hd | ⟨u, rfl, _, _⟩
            · rcases h.pe_names v e hd (by rw [hk]; rfl) with hN | ⟨hs, _⟩
              · exact Or.inl hN
              · exact Or.inr hs
            · cases hk
          rcases hN' with hN | hs
          · obtain ⟨Er, hEr, hlr, hhr, ht, ho, hc', hhv⟩ := h.N_named e hN b t hk
            exact ⟨Er, by rw [canon_frame _ (h.N_out e hN).1]; exact hEr, hlr, hhr, ht, ho, hc', hhv⟩
          · exact sym_named h hab hs hk
        · rw [subE_live, liftE_live] at hl
          have hn' : E.ty ≠ .int ∨ E.mode = .rootb := by
            rcases hnn with h' | h'
            · rw [subE_ty, liftE_ty v hrb] at h'; exact Or.inl h'
            · rw [subE_mode, liftE_rootb h] at h'; exact absurd h' hrb
          rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
          · obtain ⟨Er, hEr, hlr, hhr, ht, ho, hc', hhv⟩ := hn v E hE hl hn' d0 hd0 b t hk
            have hrb' : Er.mode ≠ .rootb := fun e => by rw [e] at ho; cases ho
            have hnp : S.isPi d0.root = false := hab.notPi hEr (fun e => by rw [e] at ho; cases ho)
            refine ⟨S.subE (S.liftE d0.root Er), by
                show S.canon Γa (S.ρ d0.root) = _; rw [canon_ρ_sub h, hnp, hEr]; rfl,
              by rw [subE_live, liftE_live]; exact hlr,
              by rw [subE_held, liftE_held_named hrb' ho hhr (by rw [ht]; exact hhv)]; rfl,
              by rw [subE_ty, liftE_ty _ hrb', ht], by rw [subE_mode, liftE_mode _ hrb', liftMode_ownSlot]; exact ho,
              ?_, hhv⟩
            rcases hc' with hb | ⟨hbr, _⟩
            · exact Or.inl hb
            · exact Or.inr ⟨hbr, Or.inl (by
                rw [subE_mode, liftE_mode _ hrb']; cases hm : Er.mode <;> simp_all [liftMode, Mode.ownSlot])⟩
          · rcases S.mem_A_ak h ha with ha | ha
            · have := allKinds_notName ha; rw [hk] at this; cases this
            · obtain ⟨Er, hEr, hlr, hhr, ht, ho, hc', hhv⟩ := h.N_named e ha b t hk
              exact ⟨Er, by rw [canon_frame _ (h.N_out e ha).1]; exact hEr, hlr, hhr, ht, ho, hc', hhv⟩
      · have := allKinds_notName (hv.sub h); rw [hk] at this; cases this
  · rw [hc] at hy; cases hy
  · rw [hc] at hy
    rcases h.Φnamed y E' hy hl hnn e he b t hk with ⟨v, bh, hρ, hb, hpt, hbr, hbh, hhv⟩ |
        ⟨hout, Er, hEr, hlr, hhr, ht, ho, hc', hhv⟩
    · obtain ⟨Ev, hEv, hmv, htv, hfx⟩ := hab.2.2.1 v bh hb
      have hrb' : Ev.mode ≠ .rootb := by rw [hmv]; simp
      have hvv : Ev.ty.holdsView = false := by rw [htv, hpt]; exact hhv
      obtain ⟨hlv, hhv'⟩ := hfx (Or.inr ⟨bh.1, hmv, hbh, hvv⟩)
      have hnp : S.isPi v = false := hab.notPi hEv (by rw [hmv]; simp)
      refine ⟨S.subE (S.liftE v Ev), by rw [← hρ, canon_ρ_sub h, hnp, hEv]; rfl,
        by rw [subE_live, liftE_live]; exact hlv,
        by rw [subE_held, liftE_held_named hrb' (by rw [hmv]; rfl) hhv' hvv]; rfl,
        by rw [subE_ty, liftE_ty _ hrb', htv, hpt],
        by rw [subE_mode, liftE_mode _ hrb', hmv]; rfl, Or.inr ⟨hbr, ?_⟩, hhv⟩
      rw [subE_mode, liftE_mode _ hrb', hmv]; exact Or.inl rfl
    · exact ⟨Er, by rw [canon_frame _ hout]; exact hEr, hlr, hhr, ht, ho, hc', hhv⟩

/-- AGORA-937: `canon_weaker` with regions: a weakening of the callee context
    is one of the lifted context. A region's index is dropped on both sides,
    and the substitution keeps a weakening (`subE_weaker`). -/
theorem canon_weaker_sub (h : S.OK) {Γa Γa' : Ctx} (hab' : S.AbsOK Γa') (hw : Weaker Γa Γa') :
    Weaker (S.canon Γa) (S.canon Γa') := by
  refine ⟨fun y => ⟨?_, fun E E' h1 h2 => ?_⟩, canon_wf_sub h hab' hw.wf hw.names,
    canon_names_sub h hab' hw.names⟩
  · rcases canon_cases_sub h Γa y with ⟨v, rfl, hp, hc⟩ | ⟨v, rfl, hp, hc⟩ | ⟨hy, hc⟩
    · rw [hc, canon_ρ_sub h, hp]; simp only [Option.map_eq_none_iff, ↓reduceIte, Bool.false_eq_true]
      exact (hw.1 v).1
    · rw [hc, canon_ρ_sub h, hp]; simp
    · rw [hc, canon_frame _ hy]
  · rcases canon_cases_sub h Γa y with ⟨v, rfl, hp, hc⟩ | ⟨v, rfl, hp, hc⟩ | ⟨hy, hc⟩
    · rw [hc] at h1; rw [canon_ρ_sub h, hp] at h2
      simp only [↓reduceIte, Bool.false_eq_true] at h2
      cases hE : Γa v with
      | none => rw [hE] at h1; cases h1
      | some E0 =>
        cases hE' : Γa' v with
        | none => rw [hE'] at h2; cases h2
        | some E0' =>
          rw [hE] at h1; rw [hE'] at h2
          simp only [Option.map_some, Option.some.injEq, Function.comp] at h1 h2
          subst h1 h2
          have hwe := (hw.1 v).2 E0 E0' hE hE'
          exact S.subE_weaker (liftE_weaker hwe
            (fun hr => by rw [← hwe.ty]; exact (hab'.2.2.2.1 v E0' hE').2 (by rw [hwe.mode]; exact hr)))
    · rw [hc] at h1; cases h1
    · rw [hc] at h1; rw [canon_frame _ hy] at h2
      rw [h1] at h2; cases h2; exact EntryWeaker.refl _

theorem AbsOK.weaker {Γa Γa' : Ctx} (hab : S.AbsOK Γa) (hw : Weaker Γa Γa') : S.AbsOK Γa' := by
  refine ⟨fun v E' hv hm => ?_, fun v E' b hv hm => ?_, fun v bh hb => ?_, fun v E' hv => by
    obtain ⟨E, hE, hwe⟩ := hw.get' hv; rw [hwe.mode, hwe.ty]; exact hab.2.2.2.1 v E hE, fun v hp => by
    obtain ⟨E, hE, hm⟩ := hab.2.2.2.2.1 v hp; obtain ⟨E', hE', hwe⟩ := hw.get hE
    exact ⟨E', hE', by rw [hwe.mode]; exact hm⟩, hab.2.2.2.2.2⟩
  · obtain ⟨E, hE, hwe⟩ := hw.get' hv
    have hm' : E.mode = .rootb := by rw [← hwe.mode]; exact hm
    rw [hwe.fixed (Or.inl hm')]; exact hab.1 v E hE hm'
  · obtain ⟨E, hE, hwe⟩ := hw.get' hv
    rw [hwe.1]; exact hab.2.1 v E b hE (by rw [← hwe.mode]; exact hm)
  · obtain ⟨E, hE, hm, ht, hfx⟩ := hab.2.2.1 v bh hb
    obtain ⟨E', hE', hwe⟩ := hw.get hE
    refine ⟨E', hE', by rw [hwe.mode]; exact hm, by rw [hwe.1]; exact ht, fun hf => ?_⟩
    have hf0 : E.fixed := by simp only [Entry.fixed_def] at hf ⊢; rw [hwe.mode, hwe.1] at hf; exact hf
    rw [hwe.fixed hf0]; exact hfx hf0

theorem AbsOK.kill {Γa : Ctx} (hab : S.AbsOK Γa) (e : Eff) (hv : Bool) (x : Var) :
    S.AbsOK (A2.kill e hv x Γa) := by
  refine ⟨fun v E' hv' hm => ?_, fun v E' b hv' hm => ?_, fun v bh hb => ?_, fun v E' hv' => by
    obtain ⟨E, hE, _, _⟩ := kill_cmode hv'
    simp only [A2.kill, hE, Option.map_some, Option.some.injEq] at hv'; subst hv'
    rw [killE_mode, killE_ty]; exact hab.2.2.2.1 v E hE, fun v hp => by
    obtain ⟨E, hE, hm⟩ := hab.2.2.2.2.1 v hp
    exact ⟨killE e hv x E, by simp [A2.kill, hE], by rw [killE_mode]; exact hm⟩, hab.2.2.2.2.2⟩
  · obtain ⟨E, hE, _, _⟩ := kill_cmode hv'
    simp only [A2.kill, hE, Option.map_some, Option.some.injEq] at hv'; subst hv'
    rw [killE_mode] at hm
    rw [killE_ty, killE_path, killE_held]; exact hab.1 v E hE hm
  · obtain ⟨E, hE, _, _⟩ := kill_cmode hv'
    simp only [A2.kill, hE, Option.map_some, Option.some.injEq] at hv'; subst hv'
    rw [killE_mode] at hm; rw [killE_ty]; exact hab.2.1 v E b hE hm
  · obtain ⟨E, hE, hm, hty, hfx⟩ := hab.2.2.1 v bh hb
    refine ⟨killE e hv x E, by simp [A2.kill, hE], by rw [killE_mode, hm], by rw [killE_ty, hty], fun hf => ?_⟩
    have hf0 : E.fixed := by unfold Entry.fixed at hf ⊢; rw [killE_mode, killE_ty] at hf; exact hf
    have hk : killE e hv x E = E := killE_nil (root_vdeps (by rw [hm]; rfl) (hfx hf0).2) e hv x
    rw [hk]; exact hfx hf0

theorem AbsOK.setE {Γa : Ctx} (hab : S.AbsOK Γa) {x : Var} {E : Entry} (hrb : E.mode ≠ .rootb)
    (hio : ∀ b, E.mode = .inout b → E.ty.owning = true ∧ S.bnd x = some (b, E.ty.elem.holdsView))
    (hbx : ∀ bh, S.bnd x = some bh → E.mode = .inout bh.1)
    (hbt : ∀ bh, S.bnd x = some bh → E.ty = S.pty x)
    (hfx : ∀ bh, S.bnd x = some bh → E.fixed → E.live = true ∧ E.held = [])
    (hnr : (E.mode = .region ↔ S.isReg x = true) ∧ (E.mode = .region → E.ty = .int)) :
    S.AbsOK (A2.setE Γa x E) := by
  refine ⟨fun v E' hv' hm => ?_, fun v E' b hv' hm => ?_, fun v bh hb => ?_, fun v E' hv' => by
    by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv'; subst hv'; exact hnr
    · simp only [A2.setE, upd_ne _ _ hvx] at hv'; exact hab.2.2.2.1 v E' hv', fun v hp => by
    by_cases hvx : v = x
    · subst hvx; exact ⟨E, by simp [A2.setE], hnr.1.mpr hp⟩
    · obtain ⟨E0, h0, hm⟩ := hab.2.2.2.2.1 v hp
      exact ⟨E0, by simp [A2.setE, upd_ne _ _ hvx, h0], hm⟩, hab.2.2.2.2.2⟩
  · by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv'; subst hv'; exact absurd hm hrb
    · simp only [A2.setE, upd_ne _ _ hvx] at hv'; exact hab.1 v E' hv' hm
  · by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv'; subst hv'; exact hio b hm
    · simp only [A2.setE, upd_ne _ _ hvx] at hv'; exact hab.2.1 v E' b hv' hm
  · by_cases hvx : v = x
    · subst hvx; exact ⟨E, by simp [A2.setE], hbx bh hb, hbt bh hb, hfx bh hb⟩
    · obtain ⟨E0, h0, hm0, ht0, hf0⟩ := hab.2.2.1 v bh hb
      exact ⟨E0, by simp [A2.setE, upd_ne _ _ hvx, h0], hm0, ht0, hf0⟩

theorem AbsOK.exitScope {Γa : Ctx} (hab : S.AbsOK Γa) {x : Var} (hbx : S.bnd x = none)
    (hnp : S.isReg x = false) : S.AbsOK (A2.exitScope x Γa) := by
  have hk := hab.kill .replace false x
  refine ⟨fun v E' hv' hm => ?_, fun v E' b hv' hm => ?_, fun v bh hb => ?_, fun v E' hv' => by
    have hvx : v ≠ x := fun e => by subst e; simp [A2.exitScope] at hv'
    simp only [A2.exitScope, upd_ne _ _ hvx] at hv'; exact hk.2.2.2.1 v E' hv', fun v hp => by
    have hvx : v ≠ x := fun e => by subst e; rw [hnp] at hp; cases hp
    obtain ⟨E0, h0, hm⟩ := hk.2.2.2.2.1 v hp
    exact ⟨E0, by simp [A2.exitScope, upd_ne _ _ hvx, h0], hm⟩, hk.2.2.2.2.2⟩
  · have hvx : v ≠ x := fun e => by subst e; simp [A2.exitScope] at hv'
    simp only [A2.exitScope, upd_ne _ _ hvx] at hv'; exact hk.1 v E' hv' hm
  · have hvx : v ≠ x := fun e => by subst e; simp [A2.exitScope] at hv'
    simp only [A2.exitScope, upd_ne _ _ hvx] at hv'; exact hk.2.1 v E' b hv' hm
  · have hvx : v ≠ x := fun e => by subst e; rw [hbx] at hb; cases hb
    obtain ⟨E0, h0, hm0, ht0, hf0⟩ := hk.2.2.1 v bh hb
    exact ⟨E0, by simp [A2.exitScope, upd_ne _ _ hvx, h0], hm0, ht0, hf0⟩

theorem EntryWeaker.mk' {E E' : Entry} (ht : E'.ty = E.ty) (hm : E'.mode = E.mode)
    (hrb : ¬ E.fixed) (hl : E'.live = E.live) (hp : E.mode.ownSlot = false → E.path ⊆ E'.path)
    (hh : E.held ⊆ E'.held) (hd : E.dtor = true → E'.dtor = true := by intro h; simp_all [RSetup.liftE])
    (hdb : E'.dbind = E.dbind := by simp_all [RSetup.liftE_dbind])
    (hra : E'.dtor = true → E.dtor = true ∨ E.dbind = true := by
      intro hh; simp_all [RSetup.liftE_dtor'])
    (hdh : E.dbind = true → E.mode.ownSlot = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
      ∀ d, d.kind.isName = false → (d ∈ E'.held ↔ d ∈ E.held) := by intro hh; simp_all [RSetup.liftE])
    (hf : E'.live = true → E'.ty ≠ .int → E'.mode = .bor → E'.fresh = true →
      E.fresh = true ∧ E'.path ⊆ E.path := by intro _ _ _ hfr; fresh_ew)
    (hg : E'.ty ≠ .int → E'.mode = .bor → E'.heldFresh = true → E.heldFresh = true := by
      intro _ _ hhf; heldfresh_ew) :
    EntryWeaker E E' :=
  ⟨ht, hm, fun h' => absurd h' hrb, fun h' => ⟨by rw [← hl]; exact h', hp, hh⟩, fun h => ⟨hd h, hh⟩,
    hdb, hra, hdh, hf, hg⟩

/-- A borrow weakened to hold MORE: `H` contains what it held. It never
    drops anything held; it is no way to shrink `held`. -/
theorem EntryWeaker.held_sup {E : Entry} {H : List Dep} (hH : E.held ⊆ H) (hb : E.mode = .bor) :
    EntryWeaker E { E with held := H } :=
  ⟨rfl, rfl, fun hf => (by rcases hf with h | ⟨_, h, _⟩ <;> rw [hb] at h <;> cases h),
    fun hl => ⟨hl, fun _ => List.Subset.refl _, hH⟩, fun hd => ⟨hd, hH⟩, rfl, fun hd => Or.inl hd,
    fun _ ho => (by rw [hb] at ho; cases ho), fun _ _ _ hf => ⟨hf, List.Subset.refl _⟩, fun _ _ hg => hg⟩

theorem allKinds_comp {R : List Var} {k : Kind} (hk : k.isName = false) :
    (allKinds R).map (fun d => (⟨d.root, comp d.kind k⟩ : Dep)) ⊆ allKinds R := by
  intro d hd
  obtain ⟨d0, hd0, rfl⟩ := List.mem_map.mp hd
  have hr := mem_allKinds hd0
  have hk0 : d0.kind = .self ∨ d0.kind = .inner ∨ d0.kind = .view ∨ d0.kind = .share := by
    simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil,
      or_false] at hd0
    obtain ⟨r, _, h⟩ := hd0
    rcases h with rfl | rfl | rfl | rfl <;> simp
  simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil,
    or_false]
  refine ⟨d0.root, hr, ?_⟩
  cases k with
  | name b t => cases hk
  | _ => rcases hk0 with h | h | h | h <;> rw [h] <;> simp [comp]

theorem A_comp (h : S.OK) {k : Kind} (hk : k.isName = false) :
    S.A.map (fun d => (⟨d.root, comp d.kind k⟩ : Dep)) ⊆ S.A := by
  intro d hd
  obtain ⟨d0, hd0, rfl⟩ := List.mem_map.mp hd
  rcases mem_A.mp hd0 with h0 | h0
  · exact mem_A.mpr (Or.inl (compAll_comp h0 (kind4 hk)))
  · have hn := h.N_name d0 h0
    obtain ⟨r, kd⟩ := d0
    cases kd with
    | name b t =>
      have : comp (.name b t) k = .name b t := by cases k <;> simp [comp]
      simp only [this]; exact mem_A.mpr (Or.inr h0)
    | _ => simp [Kind.isName] at hn

/-- What a lifted binding lends is what the binding it lifts lends, renamed,
    or something the arguments held. -/
theorem derive_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey) (k : Kind)
    (hk : k.isName = false) :
    derive (S.ρ y) (S.liftE y Ey) k ⊆ rds S.ρ (derive y Ey k) ++ S.A := by
  intro d hd
  unfold derive at hd ⊢
  rw [liftE_root h] at hd
  cases hrt : Ey.mode.isRoot with
  | true =>
    simp only [hrt, ↓reduceIte, List.mem_singleton] at hd ⊢
    subst hd
    refine List.mem_append_left _ (mem_rds.mpr ⟨_, List.mem_singleton_self _, ?_⟩)
    simp [Dep.ren, liftE_ty' h hab hy]
  | false =>
    simp only [hrt, Bool.false_eq_true, ↓reduceIte] at hd ⊢
    have hrb : Ey.mode ≠ .rootb := fun e => by rw [e] at hrt; cases hrt
    have hos : Ey.mode.ownSlot = false := by cases hm : Ey.mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
    have hpath : ∀ d ∈ (S.liftE y Ey).path, d ∈ rds S.ρ Ey.path ∨ d ∈ S.A := by
      intro d hd
      simp only [liftE, hrb, ↓reduceIte, List.mem_append] at hd
      rcases hd with hd | hd
      · exact Or.inl hd
      · split at hd
        · cases hd
        · exact Or.inr hd
    obtain ⟨d1, hd1, rfl⟩ := List.mem_map.mp hd
    rcases hpath d1 hd1 with hd1 | hd1
    · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd1
      exact List.mem_append_left _ (mem_rds.mpr ⟨_, List.mem_map_of_mem hd0, rfl⟩)
    · exact List.mem_append_right _ (A_comp h hk (List.mem_map_of_mem hd1))

/-- Agora #909: a fresh source stays one where the call places it: an
    owner or an `inout` parameter is lifted to an owner, a fresh borrow to a
    fresh borrow. -/
theorem freshSrc_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (hs : FreshSrc Γa y) : FreshSrc (S.canon Γa) (S.ρ y) := by
  obtain ⟨E, hE, hc⟩ := hs
  rw [hy] at hE; cases hE
  -- (a fresh source is a frame binding or a borrow: no region)
  have hnp : S.isPi y = false := hab.notPi hy (by
    rcases hc with (h1 | ⟨b, h1⟩) | ⟨h1, _⟩ <;> rw [h1] <;> simp)
  refine ⟨S.subE (S.liftE y Ey), canon_some h hy hnp, ?_⟩
  rw [subE_mode, subE_fresh, subE_live, subE_ty]
  rcases hc with hfr | ⟨hb, hf, hl, hn⟩
  · have hrb : Ey.mode ≠ .rootb := by rcases hfr with h1 | ⟨b, h1⟩ <;> rw [h1] <;> simp
    left; rw [liftE_mode y hrb]
    rcases hfr with h1 | ⟨b, h1⟩ <;> rw [h1] <;> exact Or.inl rfl
  · have hrb : Ey.mode ≠ .rootb := by rw [hb]; simp
    right
    exact ⟨by rw [liftE_mode y hrb, hb]; rfl, by rw [S.liftE_fresh_of hrb]; exact hf,
      by rw [liftE_live]; exact hl, by rw [liftE_ty y hrb]; exact hn⟩

/-- Agora #916: a held-fresh source stays one where the call places it: an
    owner or an `inout` parameter of a type that holds no views is lifted to
    one, a held-fresh borrow to a held-fresh borrow. -/
theorem heldSrc_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (hs : HeldSrc Γa y) : HeldSrc (S.canon Γa) (S.ρ y) := by
  obtain ⟨E, hE, hc⟩ := hs
  rw [hy] at hE; cases hE
  -- (a held-fresh source owns its slot or is a borrow: no region)
  have hnp : S.isPi y = false := hab.notPi hy (by
    rcases hc with ⟨hos, _⟩ | ⟨h1, _⟩
    · intro e; rw [e] at hos; cases hos
    · rw [h1]; simp)
  refine ⟨S.subE (S.liftE y Ey), canon_some h hy hnp, ?_⟩
  rw [subE_mode, subE_ty, subE_heldFresh, subE_live]
  rcases hc with ⟨hos, hv⟩ | ⟨hb, hf, hl⟩
  · have hrb : Ey.mode ≠ .rootb := fun e => by rw [e] at hos; cases hos
    exact Or.inl ⟨by rw [liftE_mode y hrb, liftMode_ownSlot]; exact hos, by rw [liftE_ty y hrb]; exact hv⟩
  · have hrb : Ey.mode ≠ .rootb := by rw [hb]; simp
    exact Or.inr ⟨by rw [liftE_mode y hrb, hb]; rfl, by rw [liftE_heldFresh, ite_eq_right hrb]; exact hf,
      by rw [liftE_live]; exact hl⟩

/-- ... and what is borrowed from it is renamed exactly: a fresh borrow's
    lift adds nothing the arguments hold. -/
theorem derive_lift_eq (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (hs : FreshSrc Γa y) (k : Kind) : derive (S.ρ y) (S.liftE y Ey) k = rds S.ρ (derive y Ey k) := by
  obtain ⟨E, hE, hc⟩ := hs
  rw [hy] at hE; cases hE
  unfold derive
  rw [liftE_root h]
  rcases hc with hfr | ⟨hb, hf, hl, hn⟩
  · have hr : Ey.mode.isRoot = true := by rcases hfr with h1 | ⟨b, h1⟩ <;> rw [h1] <;> rfl
    simp only [hr, ↓reduceIte, rds, List.map_cons, List.map_nil, Dep.ren, liftE_ty' h hab hy]
  · have hr : Ey.mode.isRoot = false := by rw [hb]; rfl
    have hrb : Ey.mode ≠ .rootb := by rw [hb]; simp
    have hp : (S.liftE y Ey).path = rds S.ρ Ey.path := by
      simp [liftE, hb, Mode.ownSlot, hf, hn]
    simp only [hr, Bool.false_eq_true, ↓reduceIte, hp, rds, List.map_map]
    rfl

theorem liftE_held {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) :
    (S.liftE v E).held = rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty (S.heldA E) := by
  simp [liftE, hrb]

/-- ... all the arguments hold, of an entry whose lift is not precise. -/
theorem liftE_held_A {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) (hp : ¬ HeldP E) :
    (S.liftE v E).held = rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty S.A := by
  rw [liftE_held hrb, S.heldA_notP hp]

/-- ... and at most that, of any. -/
theorem liftE_held_sub {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) :
    (S.liftE v E).held ⊆ rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty S.A := by
  rw [liftE_held hrb]; exact append_sub (List.Subset.refl _) (ownHeld_sub_mono (S.heldA_sub E))

/-- Agora #916: a held-fresh source's lift holds, in memory, only what it held, renamed: an owner
    of a type that holds no views holds no memory of the arguments, a
    held-fresh borrow is lifted precisely. -/
theorem heldSrc_held_lift (_h : S.OK) {y : Var} {Ey : Entry} (hy : Γa y = some Ey) (hn : Ey.ty ≠ .int)
    (hs : HeldSrc Γa y) : (S.liftE y Ey).held ⊆ rds S.ρ Ey.held ++ (if Ey.ty.hasFn then S.N else []) := by
  obtain ⟨E, hE, hc⟩ := hs
  rw [hy] at hE; cases hE
  rcases hc with ⟨hos, hv⟩ | ⟨hb, hf, _⟩
  · have hrb : Ey.mode ≠ .rootb := fun e => by rw [e] at hos; cases hos
    rw [liftE_held hrb, S.heldA_own hos, hos]
    simp [ownHeld, hv]
  · have hrb : Ey.mode ≠ .rootb := by rw [hb]; simp
    rw [liftE_held hrb, S.heldA_P ⟨hf, hb, hn⟩, hb]
    simp only [Mode.ownSlot, ownHeld_false]; exact List.Subset.refl _

theorem held_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey) :
    (S.liftE y Ey).held ⊆ rds S.ρ Ey.held ++ S.A := by
  by_cases hrb : Ey.mode = .rootb
  · -- AGORA-937 (3d): the callee's own memory, renamed, and the argument's names
    simp only [liftE, hrb, ↓reduceIte]
    intro d hd
    rcases List.mem_append.mp hd with hd | hd
    · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
      exact List.mem_append_left _ (List.mem_map_of_mem (List.mem_filter.mp hd0).1)
    · -- (the argument's names, or, with no region, what it holds: no memory of a region's)
      have hd' : d ∈ (S.pe y).held ∧ (d.kind.isName = true ∨ S.peReg y = false) := by
        split at hd
        · exact ⟨(List.mem_filter.mp hd).1, Or.inl (by simpa using (List.mem_filter.mp hd).2)⟩
        · rename_i hr; exact ⟨hd, Or.inr (by simpa using hr)⟩
      rcases h.pe_held y d hd'.1 with hA | ⟨hs, hf⟩ | ⟨hn, hr⟩
      · exact List.mem_append_right _ hA
      · obtain ⟨hty, _, R, _, hh⟩ := hab.1 y Ey hy hrb
        rw [hty, hf] at hh; simp only [↓reduceIte] at hh
        have hsub : S.sym ⊆ Ey.held := by rw [hh]; exact List.subset_append_right _ _
        exact List.mem_append_left _ (List.map_subset _ hsub hs)
      · exfalso; rcases hd'.2 with h' | h'
        · rw [h'] at hn; cases hn
        · rw [h'] at hr; cases hr
  · rw [liftE_held hrb]; exact append_sub (List.Subset.refl _) ((ownHeld_sub _ _ _).trans (S.heldA_sub _))

/-- A borrowed binding, or one a copy is lent from, holds what it lifts, and
    anything the arguments held. -/
theorem held_lift_bor (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey) (t : Ty) :
    (S.liftE y Ey).held ⊆ rds S.ρ Ey.held ++ ownHeld false t S.A := by
  rw [ownHeld_false]; exact held_lift h hab hy

theorem exprT_ren (h : S.OK) (hab : S.AbsOK Γa) {e : Expr} (he : ExprT Γa e)
    (hvs : ∀ v ∈ e.vars, S.isPi v = false) :
    ExprT (S.canon Γa) (e.rename S.ρ) := by
  induction he with
  | lit => exact ExprT.lit
  | var hx hl ht =>
    exact ExprT.var (canon_some h hx (hvs _ (by simp [Expr.vars]))) (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_ty, liftE_ty' h hab hx]; exact ht)
  | add _ _ iha ihb =>
    exact ExprT.add (iha fun v hv => hvs v (by simp [Expr.vars, hv]))
      (ihb fun v hv => hvs v (by simp [Expr.vars, hv]))
  | lt _ _ iha ihb =>
    exact ExprT.lt (iha fun v hv => hvs v (by simp [Expr.vars, hv]))
      (ihb fun v hv => hvs v (by simp [Expr.vars, hv]))
  | dec _ iha => exact ExprT.dec (iha fun v hv => hvs v (by simp [Expr.vars, hv]))
  | len hx hl ht =>
    exact ExprT.len (canon_some h hx (hvs _ (by simp [Expr.vars]))) (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_ty, liftE_ty' h hab hx]; exact ht)
  | slen hx hl ht =>
    exact ExprT.slen (canon_some h hx (hvs _ (by simp [Expr.vars]))) (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_ty, liftE_ty' h hab hx]; exact ht)
  | isl hx hl ht =>
    exact ExprT.isl (canon_some h hx (hvs _ (by simp [Expr.vars]))) (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_ty, liftE_ty' h hab hx]; exact ht)
  | any => exact ExprT.any

theorem liftE_indep {E : Entry} (hrb : E.mode ≠ .rootb) (x v : Var) : S.liftE x E = S.liftE v E := by
  simp [liftE, hrb]

theorem allowed_own (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey) (hm : Ey.mode = .own)
    (e : Eff) (hv : Bool) : Allowed S e hv y := by
  left
  cases hb : S.bnd y with
  | none => rfl
  | some bh =>
    obtain ⟨E, hE, hmE, _⟩ := hab.2.2.1 y bh hb
    rw [hy] at hE; cases hE; rw [hm] at hmE; cases hmE

theorem allowed_canDo' (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    {e : Eff} (hcan : canDo Ey.mode e) : Allowed S e Ey.ty.elem.holdsView y := by
  rcases hcan with hm | ⟨b, hm, hle⟩
  · exact allowed_own hab hy hm e _
  · obtain ⟨_, hb⟩ := hab.2.1 y Ey b hy hm
    exact Or.inr ⟨b, _, hb, fun k hk => Eff.kills_mono hle _ k hk⟩

theorem allowed_canDo (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} {t : Ty} (hy : Γa y = some Ey)
    (ht : Ey.ty = .vec t) {e : Eff} (hcan : canDo Ey.mode e) : Allowed S e t.holdsView y := by
  have h := allowed_canDo' hab hy hcan
  rw [ht] at h; exact h

theorem canDo_lift {m : Mode} {e : Eff} (h : canDo m e) : canDo (liftMode m) e := by
  rcases h with rfl | ⟨b, rfl, _⟩ <;> exact Or.inl rfl

theorem intE_lift (x : Var) : EntryWeaker intE (S.liftE x intE) := by
  have he : S.liftE x intE = ⟨.int, .bor, true, S.A, S.A, false, false, false, false⟩ := by
    simp [liftE, intE, liftMode, rds, Mode.ownSlot, ownHeld_false]
  rw [he]
  exact EntryWeaker.mk' rfl rfl (by simp [intE]) rfl (fun _ => by simp [intE]) (by simp [intE])

/-- A3.2: the binding a lock's payload is checked out to, where the call
    places it. -/
theorem lockE_lift (x : Var) (t : Ty) : EntryWeaker (lockE t) (S.liftE x (lockE t)) := by
  by_cases ht : t = .int
  · subst ht
    have he : lockE .int = intE := by simp [lockE]
    rw [he]; exact intE_lift x
  · have he : lockE t = ⟨t, .own, true, [], [], false, false, false, false⟩ := by simp [lockE, ht]
    rw [he]
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp) (fun h => by simp at h) (by simp [liftE])
      (fun hh => by simp [liftE] at hh) (fun hh => by simp at hh)

theorem elemE_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (t : Ty) (x : Var) : EntryWeaker (elemE (S.ρ y) (S.liftE y Ey) t) (S.liftE x (elemE y Ey t)) := by
  have hl := held_lift h hab hy
  cases t with
  | int =>
    show EntryWeaker intE (S.liftE x intE)
    exact intE_lift x
  | slice s =>
    rw [S.liftE_of_bor x (elemE_mode y Ey _)]
    refine EntryWeaker.mk' (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (fun _ => ?_) ?_
    · simp only [elemE, Bool.false_and, Bool.false_eq_true, ↓reduceIte]
      exact hl
    · simp only [elemE, ownHeld_false]; exact hl
  | vec s =>
    rw [S.liftE_of_bor x (elemE_mode y Ey _)]
    refine EntryWeaker.mk' (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (fun _ => ?_) ?_
    · simp only [elemE, Bool.false_and, Bool.false_eq_true, ↓reduceIte]
      exact derive_lift h hab hy .inner rfl
    · simp only [elemE, ownHeld_false]; exact hl
  | prod a b =>
    rw [S.liftE_of_bor x (elemE_mode y Ey _)]
    refine EntryWeaker.mk' (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (fun _ => ?_) ?_
    · simp only [elemE, Bool.false_and, Bool.false_eq_true, ↓reduceIte]
      exact derive_lift h hab hy .inner rfl
    · simp only [elemE, ownHeld_false]; exact hl
  | sum a b =>
    rw [S.liftE_of_bor x (elemE_mode y Ey _)]
    refine EntryWeaker.mk' (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (fun _ => ?_) ?_
    · simp only [elemE, Bool.false_and, Bool.false_eq_true, ↓reduceIte]
      exact derive_lift h hab hy .inner rfl
    · simp only [elemE, ownHeld_false]; exact hl
  | fn ms =>
    rw [S.liftE_of_bor x (elemE_mode y Ey _)]
    refine EntryWeaker.mk' (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (fun _ => ?_) ?_
    · simp only [elemE, Bool.false_and, Bool.false_eq_true, ↓reduceIte]
      exact derive_lift h hab hy .inner rfl
    · simp only [elemE, ownHeld_false]; exact hl
  | arc ms =>
    rw [S.liftE_of_bor x (elemE_mode y Ey _)]
    refine EntryWeaker.mk' (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (fun _ => ?_) ?_
    · simp only [elemE, Bool.false_and, Bool.false_eq_true, ↓reduceIte]
      exact derive_lift h hab hy .inner rfl
    · simp only [elemE, ownHeld_false]; exact hl
  | rguard ms =>
    rw [S.liftE_of_bor x (elemE_mode y Ey _)]
    refine EntryWeaker.mk' (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (fun _ => ?_) ?_
    · simp only [elemE, Bool.false_and, Bool.false_eq_true, ↓reduceIte]
      exact derive_lift h hab hy .inner rfl
    · simp only [elemE, ownHeld_false]; exact hl
  | lk ms =>
    rw [S.liftE_of_bor x (elemE_mode y Ey _)]
    refine EntryWeaker.mk' (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (fun _ => ?_) ?_
    · simp only [elemE, Bool.false_and, Bool.false_eq_true, ↓reduceIte]
      exact derive_lift h hab hy .inner rfl
    · simp only [elemE, ownHeld_false]; exact hl
  | cell ms =>
    rw [S.liftE_of_bor x (elemE_mode y Ey _)]
    refine EntryWeaker.mk' (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (fun _ => ?_) ?_
    · simp only [elemE, Bool.false_and, Bool.false_eq_true, ↓reduceIte]
      exact derive_lift h hab hy .inner rfl
    · simp only [elemE, ownHeld_false]; exact hl
  | dtor f a =>
    rw [S.liftE_of_bor x (elemE_mode y Ey _)]
    refine EntryWeaker.mk' (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (by simp [elemE]) (fun _ => ?_) ?_
    · simp only [elemE, Bool.false_and, Bool.false_eq_true, ↓reduceIte]
      exact derive_lift h hab hy .inner rfl
    · simp only [elemE, ownHeld_false]; exact hl

theorem popE_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    {t : Ty} (ht : Ey.ty = .vec t) (hrb : Ey.mode ≠ .rootb) (hos : Ey.mode.ownSlot = true) (x : Var) :
    EntryWeaker (popE (S.ρ y) (S.liftE y Ey) t) (S.liftE x (popE y Ey t)) := by
  have hv : ownHeld true (Ty.vec t) S.A = ownHeld true t S.A := by simp [ownHeld, Ty.holdsView]
  have hl : (S.liftE y Ey).held = rds S.ρ Ey.held ++ ownHeld true t S.A := by
    rw [liftE_held hrb, S.heldA_own hos, hos, ht, hv]
  cases t with
  | vec s =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    show (S.liftE y Ey).held ⊆ _
    rw [hl, liftE_held (by simp [popE])]; simp [popE, Mode.ownSlot]
  | prod a b =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    show (S.liftE y Ey).held ⊆ _
    rw [hl, liftE_held (by simp [popE])]; simp [popE, Mode.ownSlot]
  | sum a b =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    show (S.liftE y Ey).held ⊆ _
    rw [hl, liftE_held (by simp [popE])]; simp [popE, Mode.ownSlot]
  | fn ms =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    show (S.liftE y Ey).held ⊆ _
    rw [hl, liftE_held (by simp [popE])]; simp [popE, Mode.ownSlot]
  | arc ms =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    show (S.liftE y Ey).held ⊆ _
    rw [hl, liftE_held (by simp [popE])]; simp [popE, Mode.ownSlot]
  | rguard ms =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    show (S.liftE y Ey).held ⊆ _
    rw [hl, liftE_held (by simp [popE])]; simp [popE, Mode.ownSlot]
  | lk ms =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    show (S.liftE y Ey).held ⊆ _
    rw [hl, liftE_held (by simp [popE])]; simp [popE, Mode.ownSlot]
  | cell ms =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    show (S.liftE y Ey).held ⊆ _
    rw [hl, liftE_held (by simp [popE])]; simp [popE, Mode.ownSlot]
  | int => exact elemE_lift h hab hy .int x
  | slice s => exact elemE_lift h hab hy (.slice s) x
  | dtor f a =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    show (S.liftE y Ey).held ⊆ _
    rw [hl, liftE_held (by simp [popE])]; simp [popE, Mode.ownSlot]

/-- AGORA-909: the source of a fresh field or payload read, lifted: a frame
    binding or a fresh, held-fresh borrow of a type that holds no views,
    holding nothing, stays one, and its lift holds nothing (an owner's held
    lifts by `ownHeld`; a held-fresh borrow's by `heldA`, which adds no name
    to a type that holds no closure, `hasFn_holdsView`). -/
theorem projSrc_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (hsrc : Ey.mode.frame ∨ (Ey.mode = .bor ∧ Ey.fresh = true ∧ Ey.heldFresh = true))
    (hhv : Ey.ty.holdsView = false) (hh : Ey.held = []) (hn : Ey.ty ≠ .int) :
    ((S.liftE y Ey).mode.frame ∨ ((S.liftE y Ey).mode = .bor ∧ (S.liftE y Ey).fresh = true ∧
      (S.liftE y Ey).heldFresh = true)) ∧ (S.liftE y Ey).ty.holdsView = false ∧ (S.liftE y Ey).held = [] ∧
    projDeps (S.ρ y) (S.liftE y Ey) = rds S.ρ (projDeps y Ey) := by
  have hrb : Ey.mode ≠ .rootb := by
    rcases hsrc with (h1 | ⟨_, h1⟩) | ⟨h1, _⟩ <;> rw [h1] <;> simp
  have hfn : Ey.ty.hasFn = false := by
    cases h' : Ey.ty.hasFn
    · rfl
    · exact absurd (hasFn_holdsView h') (by simp [hhv])
  rcases hsrc with hfr | ⟨hb, hf, hhf⟩
  · have hos : Ey.mode.ownSlot = true := by rcases hfr with h1 | ⟨_, h1⟩ <;> rw [h1] <;> rfl
    have hlos : (S.liftE y Ey).mode.ownSlot = true := by
      rw [liftE_mode y hrb]; rcases hfr with h1 | ⟨_, h1⟩ <;> rw [h1] <;> rfl
    refine ⟨Or.inl ?_, by rw [liftE_ty' h hab hy]; exact hhv, ?_, ?_⟩
    · rw [liftE_mode y hrb]; rcases hfr with h1 | ⟨_, h1⟩ <;> rw [h1] <;> exact Or.inl rfl
    · rw [liftE_held hrb, hh, hos]; simp [ownHeld, hhv, rds]
    · simp only [projDeps, hos, hlos, ↓reduceIte, rds, List.map_cons, List.map_nil, Dep.ren]
  · have hP : HeldP Ey := ⟨hhf, hb, hn⟩
    have hlb : (S.liftE y Ey).mode = .bor := by rw [liftE_mode y hrb, hb]; rfl
    refine ⟨Or.inr ⟨hlb, by simp [liftE_fresh, hrb, hf], by simp [liftE_heldFresh, hrb, hhf]⟩,
      by rw [liftE_ty' h hab hy]; exact hhv, ?_, ?_⟩
    · rw [liftE_held hrb, hh, S.heldA_P hP, hb]; simp [Mode.ownSlot, hfn, rds]
    · have hlp : (S.liftE y Ey).path = rds S.ρ Ey.path := by
        simp [liftE, hb, Mode.ownSlot, hf, hn]
      simp only [projDeps, hlb, hb, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte, reduceCtorEq, hlp]

/-- ... and the read itself lifts exactly: fresh and held-fresh, it holds
    nothing, and its path is the source's, renamed. -/
theorem projE_fresh_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (hsrc : Ey.mode.frame ∨ (Ey.mode = .bor ∧ Ey.fresh = true ∧ Ey.heldFresh = true))
    (hhv : Ey.ty.holdsView = false) (hh : Ey.held = []) (hn : Ey.ty ≠ .int) {a : Ty}
    (hav : a.holdsView = false) (x : Var) :
    EntryWeaker { projE (S.ρ y) (S.liftE y Ey) a with fresh := true, heldFresh := true }
      (S.liftE x { projE y Ey a with fresh := true, heldFresh := true }) := by
  obtain ⟨_, _, hlh, hpd⟩ := projSrc_lift h hab hy hsrc hhv hh hn
  have hafn : a.hasFn = false := by
    cases h' : a.hasFn
    · rfl
    · exact absurd (hasFn_holdsView h') (by simp [hav])
  by_cases hai : a = .int
  · subst hai
    exact EntryWeaker.mk' (by simp [projE, liftE, intE]) (by simp [projE, liftE, intE, liftMode])
      (by simp [projE, intE]) (by simp [projE, liftE, intE]) (fun _ d hd => by simp [projE, intE] at hd)
      (fun d hd => by simp [projE, intE] at hd) (hf := fun _ hn _ _ => absurd (by simp [liftE, projE, intE]) hn)
  · have heq : S.liftE x { projE y Ey a with fresh := true, heldFresh := true } =
        { projE (S.ρ y) (S.liftE y Ey) a with fresh := true, heldFresh := true } := by
      cases a <;> first
        | exact absurd rfl hai
        | (simp only [projE, hlh, hh, projHeld_nil, hpd]
           simp [liftE, Mode.ownSlot, heldA, hafn, rds, liftMode])
    rw [heq]; exact EntryWeaker.refl _

/-- A field read, where the call places it. -/
theorem projE_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (t : Ty) (x : Var) :
    EntryWeaker (projE (S.ρ y) (S.liftE y Ey) t) (S.liftE x (projE y Ey t)) := by
  have hl := held_lift h hab hy
  have hpd : projDeps (S.ρ y) (S.liftE y Ey) ⊆ rds S.ρ (projDeps y Ey) ++ S.A := by
    by_cases hrb : Ey.mode = .rootb
    · have hm : (S.liftE y Ey).mode = .rootb := (liftE_rootb h).mpr hrb
      simp only [projDeps, hm, hrb, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte]
      intro d hd; simp at hd; subst hd; simp [rds, Dep.ren]
    have hm' : (S.liftE y Ey).mode ≠ .rootb := fun e => hrb ((liftE_rootb h).mp e)
    have hos : (S.liftE y Ey).mode.ownSlot = Ey.mode.ownSlot := by
      rw [liftE_mode y hrb]; cases hm : Ey.mode <;> rfl
    unfold projDeps; rw [hos]; simp only [hm', hrb, ↓reduceIte]
    split
    · intro d hd; simp at hd; subst hd; simp [rds, Dep.ren]
    · rename_i hos'
      have : (liftMode Ey.mode).ownSlot = false := by
        cases hm : Ey.mode <;> simp_all [liftMode, Mode.ownSlot]
      have hf : Ey.mode.ownSlot = false := by simpa using hos'
      intro d hd
      have := (by simpa [liftE, hrb, this, hf] using hd :
        d ∈ rds S.ρ Ey.path ∨ (Ey.fresh = true → Ey.ty = Ty.int) ∧ d ∈ S.A)
      rcases this with h1 | h1
      · exact List.mem_append.mpr (Or.inl h1)
      · exact List.mem_append.mpr (Or.inr h1.2)
  -- (AGORA-937: the lift keeps whether the struct's slot owns its value,
  -- so the field depends on what the lifted struct holds where it did)
  have hosl : (S.liftE y Ey).mode.ownSlot = Ey.mode.ownSlot := by
    by_cases hrb : Ey.mode = .rootb
    · rw [(liftE_rootb h).mpr hrb, hrb]
    · rw [liftE_mode y hrb]; cases hm : Ey.mode <;> simp_all [liftMode, Mode.ownSlot]
  have hph : ∀ t' : Ty, projHeld (S.liftE y Ey).mode.ownSlot t' (S.liftE y Ey).held ⊆
      rds S.ρ (projHeld Ey.mode.ownSlot t' Ey.held) ++ S.A := by
    intro t' d hd
    rw [hosl] at hd
    unfold projHeld at hd ⊢
    split at hd
    · cases hd
    · rename_i hc; simp only [hc]; exact hl hd
  cases t with
  | int => exact intE_lift x
  | _ =>
    refine EntryWeaker.mk' (by simp [projE, liftE]) (by simp [projE, liftE, liftMode])
      (by simp [projE]) (by simp [projE, liftE]) (fun _ => ?_) ?_
    · intro d hd
      have hd' := List.mem_append.mp (by simpa only [projE] using hd)
      simp only [projE, liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot,
        rds, List.map_append]
      rcases hd' with hd | hd
      · rcases List.mem_append.mp (hpd hd) with h1 | h1
        · exact List.mem_append_left _ (List.mem_append_left _ h1)
        · exact List.mem_append_right _ h1
      · rcases List.mem_append.mp (hph _ hd) with h1 | h1
        · exact List.mem_append_left _ (List.mem_append_right _ h1)
        · exact List.mem_append_right _ h1
    · simp only [projE, liftE, reduceCtorEq, ↓reduceIte]; exact hl

/-- A3.1: a payload lent, where the call places it. -/
theorem getE_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (t : Ty) (x : Var) : EntryWeaker (getE (S.ρ y) (S.liftE y Ey) t) (S.liftE x (getE y Ey t)) := by
  have hl := held_lift h hab hy
  cases t with
  | int =>
    show EntryWeaker intE (S.liftE x intE)
    exact intE_lift x
  | _ =>
    rw [S.liftE_of_ne x (by simp [getE])]
    refine EntryWeaker.mk' (by simp [getE]) (by simp [getE, liftMode])
      (by simp [getE]) (by simp [getE]) (fun _ => ?_) ?_
    · simp only [getE, Mode.ownSlot, Bool.false_and, Bool.false_or, Bool.false_eq_true, ↓reduceIte]
      exact derive_lift h hab hy .share rfl
    · simp only [getE, Mode.ownSlot, ownHeld_false]; exact hl

/-- A field moved out of a struct taken apart, where the call places it. -/
theorem ownHeld_lift {X L : List Dep} {t : Ty} (hl : X ⊆ rds S.ρ L ++ S.A) :
    ownHeld true t X ⊆ rds S.ρ (ownHeld true t L) ++ ownHeld true t S.A := by
  unfold ownHeld; split
  · intro d hd; cases hd
  · exact hl

theorem compE_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (t : Ty) (x : Var) : EntryWeaker (compE (S.liftE y Ey) t) (S.liftE x (compE Ey t)) := by
  have hl := held_lift h hab hy
  cases t with
  | int => exact intE_lift x
  | slice s =>
    rw [S.liftE_of_ne x (by simp [compE])]
    refine EntryWeaker.mk' (by simp [compE]) (by simp [compE, liftMode])
      (by simp [compE]) (by simp [compE]) (fun _ => ?_) ?_
    · simp only [compE, Mode.ownSlot, Bool.false_and, Bool.false_or, Bool.false_eq_true, ↓reduceIte]
      exact hl
    · simp only [compE, Mode.ownSlot]; exact hl
  | vec s =>
    rw [S.liftE_of_ne x (by simp [compE])]
    refine EntryWeaker.mk' (by simp [compE]) (by simp [compE, liftMode])
      (by simp [compE]) (by simp [compE]) (fun h' => by simp [compE, Mode.ownSlot] at h') ?_
    simp only [compE, Mode.ownSlot]; exact ownHeld_lift hl
  | prod a b =>
    rw [S.liftE_of_ne x (by simp [compE])]
    refine EntryWeaker.mk' (by simp [compE]) (by simp [compE, liftMode])
      (by simp [compE]) (by simp [compE]) (fun h' => by simp [compE, Mode.ownSlot] at h') ?_
    simp only [compE, Mode.ownSlot]; exact ownHeld_lift hl
  | sum a b =>
    rw [S.liftE_of_ne x (by simp [compE])]
    refine EntryWeaker.mk' (by simp [compE]) (by simp [compE, liftMode])
      (by simp [compE]) (by simp [compE]) (fun h' => by simp [compE, Mode.ownSlot] at h') ?_
    simp only [compE, Mode.ownSlot]; exact ownHeld_lift hl
  | fn ms =>
    rw [S.liftE_of_ne x (by simp [compE])]
    refine EntryWeaker.mk' (by simp [compE]) (by simp [compE, liftMode])
      (by simp [compE]) (by simp [compE]) (fun h' => by simp [compE, Mode.ownSlot] at h') ?_
    simp only [compE, Mode.ownSlot]; exact ownHeld_lift hl
  | arc ms =>
    rw [S.liftE_of_ne x (by simp [compE])]
    refine EntryWeaker.mk' (by simp [compE]) (by simp [compE, liftMode])
      (by simp [compE]) (by simp [compE]) (fun h' => by simp [compE, Mode.ownSlot] at h') ?_
    simp only [compE, Mode.ownSlot]; exact ownHeld_lift hl
  | rguard ms =>
    rw [S.liftE_of_ne x (by simp [compE])]
    refine EntryWeaker.mk' (by simp [compE]) (by simp [compE, liftMode])
      (by simp [compE]) (by simp [compE]) (fun h' => by simp [compE, Mode.ownSlot] at h') ?_
    simp only [compE, Mode.ownSlot]; exact ownHeld_lift hl
  | lk ms =>
    rw [S.liftE_of_ne x (by simp [compE])]
    refine EntryWeaker.mk' (by simp [compE]) (by simp [compE, liftMode])
      (by simp [compE]) (by simp [compE]) (fun h' => by simp [compE, Mode.ownSlot] at h') ?_
    simp only [compE, Mode.ownSlot]; exact ownHeld_lift hl
  | cell ms =>
    rw [S.liftE_of_ne x (by simp [compE])]
    refine EntryWeaker.mk' (by simp [compE]) (by simp [compE, liftMode])
      (by simp [compE]) (by simp [compE]) (fun h' => by simp [compE, Mode.ownSlot] at h') ?_
    simp only [compE, Mode.ownSlot]; exact ownHeld_lift hl
  | dtor f a =>
    rw [S.liftE_of_ne x (by simp [compE])]
    refine EntryWeaker.mk' (by simp [compE]) (by simp [compE, liftMode])
      (by simp [compE]) (by simp [compE]) (fun h' => by simp [compE, Mode.ownSlot] at h') ?_
    simp only [compE, Mode.ownSlot]; exact ownHeld_lift hl

theorem AbsOK.setE' {Γ0 Γ1 : Ctx} (hab : S.AbsOK Γ1) (hab0 : S.AbsOK Γ0) {x : Var} {E0 E : Entry}
    (hx : Γ0 x = some E0) (hm : E.mode = E0.mode) (ht : E.ty = E0.ty) (hrb : E.mode ≠ .rootb)
    (hfx : E.fixed → E.live = true ∧ E.held = []) :
    S.AbsOK (A2.setE Γ1 x E) := by
  refine hab.setE hrb (fun b hb => ?_) (fun bh hb => ?_) (fun bh hb => ?_) (fun _ _ => hfx)
    (by rw [hm, ht]; exact hab0.2.2.2.1 x E0 hx)
  · rw [ht]; exact hab0.2.1 x E0 b hx (hm ▸ hb)
  · obtain ⟨E', hE', hm', _⟩ := hab0.2.2.1 x bh hb
    rw [hx] at hE'; cases hE'; rw [hm]; exact hm'
  · obtain ⟨E', hE', _, ht', _⟩ := hab0.2.2.1 x bh hb
    rw [hx] at hE'; cases hE'; rw [ht]; exact ht'

theorem AbsOK.fresh {Γ : Ctx} (hab : S.AbsOK Γ) {x : Var} (hx : Γ x = none) : S.bnd x = none := by
  cases hb : S.bnd x with
  | none => rfl
  | some bh => obtain ⟨E, hE, _⟩ := hab.2.2.1 x bh hb; rw [hx] at hE; cases hE

/-- A fixed `inout` binding of the callee is live and holds nothing. -/
theorem AbsOK.fixed {Γ : Ctx} (hab : S.AbsOK Γ) {v : Var} {E : Entry} (hv : Γ v = some E)
    (hf : E.fixed) (hrb : E.mode ≠ .rootb) : E.live = true ∧ E.held = [] := by
  rcases hf with h | ⟨b, hb, _⟩
  · exact absurd h hrb
  · obtain ⟨_, hbv⟩ := hab.2.1 v E b hv hb
    obtain ⟨E', hE', _, _, hfx⟩ := hab.2.2.1 v _ hbv
    rw [hv] at hE'; cases hE'
    exact hfx (Or.inr ⟨b, hb, by assumption⟩)

theorem AbsOK.add {Γ Γ1 : Ctx} (hab0 : S.AbsOK Γ) (hab : S.AbsOK Γ1) {x : Var} (hx : Γ x = none)
    {E : Entry} (hm : E.mode = .own ∨ E.mode = .bor) : S.AbsOK (A2.setE Γ1 x E) := by
  have hbx := hab0.fresh hx
  have hnp := hab0.notRegFresh hx
  refine hab.setE (by rcases hm with hm | hm <;> rw [hm] <;> simp) (fun b hb => ?_) (fun bh hb => ?_)
    (fun bh hb => ?_) (fun bh hb => ?_) (by rcases hm with hm | hm <;> rw [hm] <;> simp [hnp])
  · rcases hm with hm | hm <;> rw [hm] at hb <;> cases hb
  · rw [hbx] at hb; cases hb
  · rw [hbx] at hb; cases hb
  · rw [hbx] at hb; cases hb

/-- Nothing the call can see pins a binding the callee may replace: a
    borrowed parameter's dependencies are outside the callee, and the frame
    holds by name no `inout` argument the callee may replace (`Φsat`). -/
theorem NoPin.lift (h : S.OK) (_hab : S.AbsOK Γa) {y : Var}
    (hb : ∀ bh, S.bnd y = some bh → bh.1 = .replace) : NoPin (S.canon Γa) (S.ρ y) := by
  intro q E hq hm d hd hbd hdr
  rcases canon_cases_sub h Γa q with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨hqf, hc⟩
  · rw [hc] at hq
    cases hE : Γa v with
    | none => rw [hE] at hq; cases hq
    | some E0 =>
      rw [hE] at hq; simp only [Option.map_some, Option.some.injEq, Function.comp] at hq; subst hq
      replace hd : d ∈ (S.liftE v E0).vdeps := by
        rw [subE_vdeps] at hd
        obtain ⟨d1, hd1, hdd⟩ := List.mem_flatMap.mp hd
        rcases S.subD_frame h hdd with rfl | ⟨hout, _⟩
        · exact hd1
        · exact absurd hdr.symm (hout _)
      have hrb : E0.mode = .rootb := (liftE_rootb h).mp hm
      rcases liftE_rootb_ρ h _hab hE hrb hd hdr with ⟨b, t, rfl, hbb, _, _, hbr, _⟩ | ⟨rfl, _⟩
      · exact hbr (hb _ hbb)
      · simp [Kind.bound] at hbd
  · rw [hc] at hq; cases hq
  · rw [hc] at hq
    obtain ⟨b, hv, hbb, hk⟩ := h.Φsat q E hq (h.Φrb q E hq hm) (Or.inr hm) d hd y hdr.symm
    have := hb _ hbb; simp only at this; subst this
    obtain ⟨r, k⟩ := d
    cases k <;> simp_all [Kind.bound, Eff.kills]


/-- A2-drop.2: a callee binding no `letd` binding views stays unviewed where
    the call places it: the frame views, of the callee's, only its `inout`
    arguments. -/
theorem DbindSafe.canon (h : S.OK) {x : Var} (hbx : S.bnd x = none) (hd : DbindSafe Γa x) :
    DbindSafe (S.canon Γa) (S.ρ x) := by
  intro y E hy hdb hos hn d hdd hnm hdx
  rcases canon_cases_sub h Γa y with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨_, hc⟩
  · rw [hc] at hy
    obtain ⟨Ea, hEa, rfl⟩ := Option.map_eq_some_iff.mp hy
    simp only [Function.comp_apply, subE_dbind, subE_mode, subE_ty] at hdb hos hn hdd
    replace hdd : d ∈ (S.liftE v Ea).vdeps := by
      rw [subE_vdeps] at hdd
      obtain ⟨d1, hd1, hdd'⟩ := List.mem_flatMap.mp hdd
      rcases S.subD_frame h hdd' with rfl | ⟨hout, _⟩
      · exact hd1
      · exact absurd hdx.symm (hout _)
    by_cases hrb : Ea.mode = .rootb
    · rw [liftE_dbind h, ite_eq_left hrb] at hdb; cases hdb
    · rw [liftE_dbind h, ite_eq_right hrb] at hdb
      have hos0 : Ea.mode.ownSlot = true := by rwa [liftE_mode v hrb, liftMode_ownSlot] at hos
      have hn' : Ea.ty ≠ .int ∨ Ea.mode = .rootb := by
        rcases hn with h' | h'
        · rw [liftE_ty v hrb] at h'; exact Or.inl h'
        · rw [liftE_rootb h] at h'; exact absurd h' hrb
      rcases liftE_vdeps_cases hrb hdd with ⟨d0, hd0, rfl⟩ | ha
      · exact hd v Ea hEa hdb hos0 hn' d0 hd0 (by simpa [Dep.ren] using hnm) (h.inj _ _ hdx)
      · exact A_out h ha x hdx.symm
  · rw [hc] at hy; cases hy
  · rw [hc] at hy
    rcases h.Φdb y E hy hdb hos hn d hdd hnm with ⟨v, bh, hv, hb⟩ | ⟨hout, _⟩
    · have := h.inj _ _ (hv.trans hdx); subst this; rw [hbx] at hb; cases hb
    · exact hout x hdx.symm

/-- What follows a panic may assume no `letd` binding views more, where the
    call places it too: a binding keeps its mode and type, so its lifted
    views are its views renamed, and the same frame ones. -/
theorem DKeep.canon (h : S.OK) {Δa : Ctx} (hdk : DKeep Γa Δa [])
    (hm : ∀ v E, Δa v = some E → ∃ E0, Γa v = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty ∧
      (E0.fixed → E = E0)) :
    DKeep (S.canon Γa) (S.canon Δa) [] := by
  intro y E' hy hd hos hn _
  rcases canon_cases_sub h Δa y with ⟨v, rfl, hp, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨hyf, hc⟩
  · rw [hc] at hy
    obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hy
    simp only [Function.comp, subE_dbind, subE_mode, subE_ty] at hd hos hn
    by_cases hrb : E1.mode = .rootb
    · rw [liftE_dbind h, ite_eq_left hrb] at hd; cases hd
    · rw [liftE_dbind h, ite_eq_right hrb] at hd
      have hos1 : E1.mode.ownSlot = true := by rwa [liftE_mode v hrb, liftMode_ownSlot] at hos
      have hn1 : E1.ty ≠ .int ∨ E1.mode = .rootb := by
        rcases hn with h' | h'
        · rw [liftE_ty v hrb] at h'; exact Or.inl h'
        · rw [liftE_rootb h] at h'; exact absurd h' hrb
      obtain ⟨E0, h0, hd0, hos0, hn0, hs0⟩ := hdk v E1 h1 hd hos1 hn1 (by simp)
      obtain ⟨E0', h0', hm0, ht0, _⟩ := hm v E1 h1
      rw [h0] at h0'; cases h0'
      have hrb0 : E0.mode ≠ .rootb := by rw [← hm0]; exact hrb
      refine ⟨S.subE (S.liftE v E0), canon_some h h0 hp,
        by rw [subE_dbind, liftE_dbind h, ite_eq_right hrb0]; exact hd0,
        by rw [subE_mode, liftE_mode v hrb0, liftMode_ownSlot]; exact hos0,
        by rw [subE_ty, subE_mode, liftE_ty v hrb0, liftE_mode v hrb0]; rw [liftE_ty v hrb, liftE_mode v hrb] at hn
           rw [← ht0, ← hm0]; exact hn,
        fun d hdd hnm => ?_⟩
      -- (a dependency that is no name comes from one that is no name)
      simp only [Function.comp] at hdd
      rw [subE_vdeps] at hdd ⊢
      obtain ⟨d1, hd1, hdd1⟩ := S.mem_flatMap_subD_nonname hdd hnm
      refine List.mem_flatMap.mpr ⟨d1, ?_, hdd1.2⟩
      rcases (mem_liftE_vdeps hrb).mp hd1 with ⟨d0, hd0', rfl⟩ | ha
      · exact (mem_liftE_vdeps hrb0).mpr
          (Or.inl ⟨d0, hs0 d0 hd0' (by simpa [Dep.ren] using hdd1.1), rfl⟩)
      · refine (mem_liftE_vdeps hrb0).mpr (Or.inr ?_)
        rw [S.liftDeps_own hos1] at ha; rw [S.liftDeps_own hos0, ← ht0]; exact ha
  · rw [hc] at hy; cases hy
  · rw [hc] at hy
    exact ⟨E', by rw [canon_frame Γa hyf]; exact hy, hd, hos, hn, fun d hdd _ => hdd⟩

/-- ... and keeps every binding `letd` made one. -/
theorem DStay.canon (h : S.OK) {Δa : Ctx} (hst : DStay Γa Δa []) : DStay (S.canon Γa) (S.canon Δa) [] := by
  intro y E hy hd hos _
  rcases canon_cases_sub h Γa y with ⟨v, rfl, hp, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨hyf, hc⟩
  · rw [hc] at hy
    obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hy
    simp only [Function.comp, subE_dbind, subE_mode] at hd hos
    by_cases hrb : E1.mode = .rootb
    · rw [liftE_dbind h, ite_eq_left hrb] at hd; cases hd
    · rw [liftE_dbind h, ite_eq_right hrb] at hd
      have hos1 : E1.mode.ownSlot = true := by rwa [liftE_mode v hrb, liftMode_ownSlot] at hos
      obtain ⟨E2, h2, hd2, hos2⟩ := hst v E1 h1 hd hos1 (by simp)
      have hrb2 : E2.mode ≠ .rootb := fun h' => by rw [h'] at hos2; cases hos2
      exact ⟨S.subE (S.liftE v E2), canon_some h h2 hp,
        by rw [subE_dbind, liftE_dbind h, ite_eq_right hrb2]; exact hd2,
        by rw [subE_mode, liftE_mode v hrb2, liftMode_ownSlot]; exact hos2⟩
  · rw [hc] at hy; cases hy
  · rw [hc] at hy
    exact ⟨E, by rw [canon_frame Δa hyf]; exact hy, hd, hos⟩

/-- What ending a fresh callee binding asks, where the call places it. -/
theorem EndOK.lift (h : S.OK) (hab : S.AbsOK Γa) {x : Var} (hbx : S.bnd x = none) (he : EndOK Γa x) :
    EndOK (S.canon Γa) (S.ρ x) :=
  ⟨NoPin.lift h hab (fun bh hb => by rw [hbx] at hb; cases hb), DtorSafe.canon h (Or.inl hbx) he.2.1,
    DbindSafe.canon h hbx he.2.2⟩

theorem bnd_own (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey) (hm : Ey.mode = .own) :
    ∀ bh, S.bnd y = some bh → bh.1 = .replace := fun bh hb => by
  obtain ⟨E, hE, hmE, _⟩ := hab.2.2.1 y bh hb
  rw [hy] at hE; cases hE; rw [hm] at hmE; cases hmE

theorem bnd_replace (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (hm : Ey.mode = .own ∨ Ey.mode = .inout .replace ∨ Ey.mode = .bor) :
    ∀ bh, S.bnd y = some bh → bh.1 = .replace := fun bh hb => by
  obtain ⟨E, hE, hmE, _⟩ := hab.2.2.1 y bh hb
  rw [hy] at hE; cases hE
  rcases hm with hm | hm | hm <;> rw [hm] at hmE
  · cases hmE
  · exact (Mode.inout.inj hmE).symm
  · cases hmE

theorem PushArg.ty_at {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hp : PushArg Γ F y Ey t D Γ1) (hy : Γ y = some Ey) {x : Var} {Ex Ex1 : Entry} (hx : Γ x = some Ex)
    (hx1 : Γ1 x = some Ex1) : Ex1.ty = Ex.ty := by
  cases hp with
  | move =>
    by_cases hxy : x = y
    · subst hxy; simp only [A2.setE, upd_same, Option.some.injEq] at hx1
      rw [hy] at hx; cases hx; subst hx1; rfl
    · simp only [A2.setE, upd_ne _ _ hxy, A2.kill, hx, Option.map_some, Option.some.injEq] at hx1
      subst hx1; exact killE_ty _ _ _ _
  | int => rw [hx] at hx1; cases hx1; rfl
  | slice => rw [hx] at hx1; cases hx1; rfl


theorem PushArg.dbind_at {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hp : PushArg Γ F y Ey t D Γ1) (hy : Γ y = some Ey) {x : Var} {Ex Ex1 : Entry} (hx : Γ x = some Ex)
    (hx1 : Γ1 x = some Ex1) : Ex1.dbind = Ex.dbind := by
  cases hp with
  | move =>
    by_cases hxy : x = y
    · subst hxy; simp only [A2.setE, upd_same, Option.some.injEq] at hx1
      rw [hy] at hx; cases hx; subst hx1; rfl
    · simp only [A2.setE, upd_ne _ _ hxy, A2.kill, hx, Option.map_some, Option.some.injEq] at hx1
      subst hx1; exact killE_dbind _ _ _ _
  | int => rw [hx] at hx1; cases hx1; rfl
  | slice => rw [hx] at hx1; cases hx1; rfl
theorem PushArg.mode_at {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hp : PushArg Γ F y Ey t D Γ1) (hy : Γ y = some Ey) {x : Var} {Ex Ex1 : Entry} (hx : Γ x = some Ex)
    (hx1 : Γ1 x = some Ex1) : Ex1.mode = Ex.mode := by
  cases hp with
  | move =>
    by_cases hxy : x = y
    · subst hxy; simp only [A2.setE, upd_same, Option.some.injEq] at hx1
      rw [hy] at hx; cases hx; subst hx1; rfl
    · simp only [A2.setE, upd_ne _ _ hxy, A2.kill, hx, Option.map_some, Option.some.injEq] at hx1
      subst hx1; exact killE_mode _ _ _ _
  | int => rw [hx] at hx1; cases hx1; rfl
  | slice => rw [hx] at hx1; cases hx1; rfl

theorem PushArg.absOK {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hy : Γ y = some Ey) (hp : PushArg Γ F y Ey t D Γ1) (hab : S.AbsOK Γ) : S.AbsOK Γ1 := by
  cases hp with
  | move _ hm _ _ => exact (hab.kill _ _ _).setE' hab hy rfl rfl (by rw [hm]; simp) (by simp [hm])
  | int => exact hab
  | slice => exact hab

theorem EditArg.absOK {Γ Γ1 : Ctx} {F : List Var} {op : Edit} {t : Ty} {D : List Dep}
    (h : EditArg Γ F op t D Γ1) (hab : S.AbsOK Γ) : S.AbsOK Γ1 := by
  cases h with
  | push hy _ _ hpa => exact PushArg.absOK hy hpa hab
  | trunc _ => exact hab
  | set _ hy _ _ hpa => exact PushArg.absOK hy hpa hab

/-- A closure literal's captures, checked in the callee, hold where the
    call places it. -/
theorem CapsOK.lift (h : S.OK) (hab : S.AbsOK Γa) {Fa : List Var} {D D1 : List Dep}
    {cs : List (Var × PMode × Ty)} (hc : CapsOK Γa Fa D cs) (hD : D1 ⊆ (rds S.ρ D ++ S.A).flatMap S.subD) :
    CapsOK (S.canon Γa) S.Fc D1 (cs.map fun c => (S.ρ c.1, c.2)) := by
  have hroot1 : ∀ d ∈ D1, ∀ v, d.root = S.ρ v → ∃ d0 ∈ D, d0.root = v ∧ d.kind = d0.kind := by
    intro d hd v hv
    obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp (hD hd)
    rcases S.subD_frame h hde with rfl | ⟨hout, _⟩
    · rcases List.mem_append.mp he with hd' | hd'
      · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd'
        exact ⟨d0, hd0, h.inj _ _ hv, rfl⟩
      · exact absurd hv.symm (A_out h hd' v)
    · exact absurd hv.symm (hout v)
  -- (a capture owns its slot: no region)
  have hcnp : ∀ c ∈ cs, ∀ Ev, Γa c.1 = some Ev → Ev.mode.ownSlot = true → S.isPi c.1 = false :=
    fun c _ Ev hEv ho => hab.notPi hEv (fun e => by rw [e] at ho; cases ho)
  have hargE : ∀ c ∈ cs, ∀ Ev, Γa c.1 = some Ev → Ev.mode.ownSlot = true →
      argE (S.canon Γa) (S.ρ c.1) = S.subE (S.liftE c.1 Ev) := by
    intro c hc' Ev hEv ho
    unfold argE; rw [canon_some h hEv (hcnp c hc' Ev hEv ho)]; rfl
  refine ⟨?_, fun c' hc' => ?_⟩
  · have he : ((cs.map fun c => (S.ρ c.1, c.2)).map (·.1)) = (cs.map (·.1)).map S.ρ := by
      simp [List.map_map, Function.comp_def]
    rw [he]; exact List.Pairwise.map S.ρ (fun a b hne e => hne (h.inj a b e)) hc.1
  · obtain ⟨c, hc1, rfl⟩ := List.mem_map.mp hc'
    obtain ⟨Ev, hEv, hl, hh, ht, ho, hhv, hmode⟩ := hc.2 c hc1
    have hrb : Ev.mode ≠ .rootb := fun e => by rw [e] at ho; cases ho
    refine ⟨S.subE (S.liftE c.1 Ev), canon_some h hEv (hcnp c hc1 Ev hEv ho), by rw [subE_live, liftE_live]; exact hl,
      by rw [subE_held, liftE_held_named hrb ho hh (by rw [ht]; exact hhv)]; rfl,
      by rw [subE_ty, liftE_ty _ hrb]; exact ht, by rw [subE_mode, liftE_mode _ hrb, liftMode_ownSlot]; exact ho,
      hhv, ?_⟩
    rcases hmode with ⟨hinp, hrd⟩ | ⟨b, s, hb, hbn, hbr, hcan, hcF, hts, hsv, hnD, hnc⟩
    · refine Or.inl ⟨hinp, fun d hd hdr hn => ?_⟩
      obtain ⟨d0, hd0, hr0, hk0⟩ := hroot1 d hd c.1 hdr
      rw [hk0]; exact hrd d0 hd0 hr0 (hk0 ▸ hn)
    · refine Or.inr ⟨b, s, hb, hbn, hbr, by rw [subE_mode, liftE_mode _ hrb]; exact canDo_lift hcan, h.Fcout _, hts,
        hsv, fun d hd hdr => ?_, fun c'' hc'' d hd hdr => ?_⟩
      · obtain ⟨d0, hd0, hr0, _⟩ := hroot1 d hd c.1 hdr
        exact hnD d0 hd0 hr0
      · obtain ⟨c2, hc2, rfl⟩ := List.mem_map.mp hc''
        obtain ⟨Ev2, hEv2, _, _, _, ho2, _⟩ := hc.2 c2 hc2
        have hrb2 : Ev2.mode ≠ .rootb := fun e => by rw [e] at ho2; cases ho2
        rw [hargE c2 hc2 Ev2 hEv2 ho2, subE_held] at hd
        obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp hd
        rcases S.subD_frame h hde with rfl | ⟨hout, _⟩
        · simp only [liftE, hrb2, ↓reduceIte] at he
          rcases List.mem_append.mp he with hd' | hd'
          · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd'
            have hae : argE Γa c2.1 = Ev2 := by unfold argE; rw [hEv2]; rfl
            exact hnc c2 hc2 d0 (by rw [hae]; exact hd0) (h.inj _ _ hdr)
          · exact A_out h (S.heldA_sub _ (ownHeld_sub _ _ _ hd')) c.1 hdr.symm
        · exact hout c.1 hdr.symm

theorem app_lift {a b a0 b0 X : List Dep} (ha : a ⊆ rds S.ρ a0 ++ X)
    (hb : b ⊆ rds S.ρ b0 ++ X) : a ++ b ⊆ rds S.ρ (a0 ++ b0) ++ X := by
  intro d hd
  simp only [rds, List.map_append, List.mem_append] at hd ha hb ⊢
  rcases hd with hd | hd
  · rcases List.mem_append.mp (ha hd) with h1 | h1
    · exact Or.inl (Or.inl h1)
    · exact Or.inr h1
  · rcases List.mem_append.mp (hb hd) with h1 | h1
    · exact Or.inl (Or.inr h1)
    · exact Or.inr h1


/-- Agora #909's own example: a borrowed parameter's path, where the call
    places it, is the caller's argument, renamed: `derive` of a root names
    the root itself. -/
theorem derive_lift_rootb (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (hm : Ey.mode = .rootb) (k : Kind) : derive (S.ρ y) (S.liftE y Ey) k = rds S.ρ (derive y Ey k) := by
  have hr : Ey.mode.isRoot = true := by rw [hm]; rfl
  unfold derive
  rw [liftE_root h, hr]
  simp only [↓reduceIte, rds, List.map_cons, List.map_nil, Dep.ren, liftE_ty' h hab hy]

/-- AGORA-937: a dependency the substitution keeps stays kept with its kind
    composed: what it was kept for (no region) holds of it still. -/
theorem subD_keep_comp (h : S.OK) {d : Dep} (hd : d ∈ S.subD d) (k : Kind) :
    (⟨d.root, comp d.kind k⟩ : Dep) ∈ S.subD ⟨d.root, comp d.kind k⟩ := by
  obtain ⟨r, kd⟩ := d
  simp only at hd ⊢
  cases hi : S.inv r with
  | none => simp [subD, hi]
  | some v =>
    cases hp : S.isPi v
    · simp [subD, hi, hp]
    · cases hk : kd.isName
      · exfalso
        simp only [subD, hi, hp, hk, Bool.false_eq_true, ↓reduceIte, List.mem_map] at hd
        obtain ⟨e0, he0, he⟩ := hd
        exact (S.σ_frame h he0).1 v (by rw [S.ρ_of_inv hi]; exact (congrArg Dep.root he).symm)
      · exfalso; simp [subD, hi, hp, hk] at hd

/-- AGORA-937: what is derived from a substituted entry is at most what is
    derived from the entry, substituted: the lift composes kinds, and
    composing is associative (`comp_assoc`). -/
theorem derive_subE (h : S.OK) {y : Var} (hnp : S.isPi y = false) (E : Entry) {k : Kind}
    (hk : k.isName = false) : derive (S.ρ y) (S.subE E) k ⊆ (derive (S.ρ y) E k).flatMap S.subD := by
  unfold derive
  rw [subE_mode, subE_ty]
  split
  · intro d hd
    rw [List.mem_singleton] at hd; subst hd
    exact S.mem_flatMap_subD_of (List.mem_singleton_self _)
      (fun w hw => by rw [inv_ρ h] at hw; cases hw; exact hnp)
  · intro e he
    rw [subE_path] at he
    obtain ⟨d', hd', rfl⟩ := List.mem_map.mp he
    obtain ⟨d, hd, hd'd⟩ := List.mem_flatMap.mp hd'
    refine List.mem_flatMap.mpr ⟨⟨d.root, comp d.kind k⟩, List.mem_map_of_mem hd, ?_⟩
    by_cases hdd : d' = d
    · subst hdd; exact S.subD_keep_comp h hd'd k
    · have hkd := S.mem_subD_sub hd'd hdd
      rcases S.mem_subD hd'd with e0 | ⟨v, hv, hp, hσ⟩
      · exact absurd e0 hdd
      · -- AGORA-937 (3d): the lift composes kinds, so deriving commutes with it (`comp_assoc`)
        have hck : (comp d.kind k).isName = false := comp_isName hkd hk
        obtain ⟨e0, he0, rfl, _⟩ := hσ
        simp only [subD, hv, hp, hck, Bool.false_eq_true, ↓reduceIte, List.mem_map]
        exact ⟨e0, he0, by rw [comp_assoc]⟩

/-- ... and is it, exactly, where what is derived is on no region. -/
theorem derive_subE_keep (h : S.OK) {y : Var} (hnp : S.isPi y = false) {E : Entry} (k : Kind)
    (hkeep : E.mode.isRoot = false → ∀ d ∈ E.path, ∀ v, S.inv d.root = some v → S.isPi v = false) :
    derive (S.ρ y) (S.subE E) k = derive (S.ρ y) E k ∧
      (derive (S.ρ y) E k).flatMap S.subD = derive (S.ρ y) E k := by
  have hkept : ∀ {ds : List Dep}, (∀ d ∈ ds, ∀ v, S.inv d.root = some v → S.isPi v = false) →
      ds.flatMap S.subD = ds := by
    intro ds hds
    induction ds with
    | nil => rfl
    | cons d ds ih =>
      rw [List.flatMap_cons, S.subD_of_not (hds d (by simp)), ih (fun d' hd' => hds d' (by simp [hd']))]
      rfl
  unfold derive
  rw [subE_mode, subE_ty]
  split
  · refine ⟨rfl, hkept ?_⟩
    intro d hd v hv; rw [List.mem_singleton] at hd; subst hd; rw [inv_ρ h] at hv; cases hv; exact hnp
  · rename_i hr
    have hk := hkeep (by simpa using hr)
    rw [subE_path, hkept hk]
    refine ⟨rfl, hkept ?_⟩
    intro d hd v hv
    obtain ⟨d0, hd0, rfl⟩ := List.mem_map.mp hd
    exact hk d0 hd0 v hv

/-- AGORA-937: what a fresh source's lift depends on is on no region: a
    fresh borrow is rooted at frame bindings (`FreshOK`). -/
theorem fresh_keep (h : S.OK) (hab : S.AbsOK Γa) (hfo : FreshOK Γa) {y : Var} {Ey : Entry}
    (hy : Γa y = some Ey) (hs : FreshSrc Γa y) :
    (S.liftE y Ey).mode.isRoot = false →
      ∀ d ∈ (S.liftE y Ey).path, ∀ v, S.inv d.root = some v → S.isPi v = false := by
  intro hr d hd v hv
  obtain ⟨E, hE, hc⟩ := hs
  rw [hy] at hE; cases hE
  rcases hc with hfr | ⟨hb, hf, hl, hn⟩
  · exfalso; rw [liftE_root h] at hr; rcases hfr with h1 | ⟨b, h1⟩ <;> rw [h1] at hr <;> cases hr
  · have hp : (S.liftE y Ey).path = rds S.ρ Ey.path := by
      simp [liftE, hb, Mode.ownSlot, hf, hn]
    rw [hp] at hd
    obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
    obtain ⟨_, hfr⟩ := hfo y Ey hy hl hn hb hf
    obtain ⟨_, Er, hEr, hfm⟩ := hfr d0 hd0
    simp only [Dep.ren, inv_ρ h, Option.some.injEq] at hv; subst hv
    exact hab.notPi hEr (by rcases hfm with h1 | ⟨b, h1⟩ <;> rw [h1] <;> simp)

/-- AGORA-937: an entry whose path the substitution narrows is stronger than
    the substituted entry: exactly so where it is fresh. -/
theorem ew_sub_path {X : Entry} {P : List Dep} (hP : P ⊆ X.path.flatMap S.subD)
    (hf : X.fresh = true → X.path.flatMap S.subD ⊆ P) (hfx : ¬ X.fixed) :
    EntryWeaker { S.subE X with path := P } (S.subE X) :=
  ⟨rfl, rfl, fun h' => absurd (by simpa only [Entry.fixed_def, subE_mode, subE_ty] using h') hfx,
    fun hl => ⟨hl, fun _ => hP, List.Subset.refl _⟩, fun hd => ⟨hd, List.Subset.refl _⟩, rfl,
    fun hd => Or.inl hd, fun _ _ _ _ _ => Iff.rfl, fun _ _ _ hfr => ⟨hfr, hf hfr⟩, fun _ _ hg => hg⟩

/-- AGORA-937: ... and so is a borrow that holds less. -/
theorem ew_sub_held {X : Entry} {H : List Dep} (hH : H ⊆ X.held) (hos : X.mode.ownSlot = false)
    (hfx : ¬ X.fixed) : EntryWeaker { X with held := H } X :=
  ⟨rfl, rfl, fun h' => absurd (by simpa only [Entry.fixed_def] using h') hfx,
    fun hl => ⟨hl, fun _ => List.Subset.refl _, hH⟩, fun hd => ⟨hd, hH⟩, rfl,
    fun hd => Or.inl hd, fun _ h' => absurd h' (by simp [hos]), fun _ _ _ hfr => ⟨hfr, List.Subset.refl _⟩,
    fun _ _ hg => hg⟩

/-- ... so, after a lift that is weaker, it is weaker than the lift substituted. -/
theorem ew_sub_lift {X E3 : Entry} (hw : EntryWeaker X E3) {P : List Dep} (hP : P ⊆ X.path.flatMap S.subD)
    (hf : X.fresh = true → X.path.flatMap S.subD ⊆ P) (hfx : ¬ X.fixed) :
    EntryWeaker { S.subE X with path := P } (S.subE E3) :=
  (S.ew_sub_path hP hf hfx).trans (S.subE_weaker hw)

/-- AGORA-937: an element read of a substituted entry, against the read
    substituted. -/
theorem elemE_subE (h : S.OK) {y : Var} (hnp : S.isPi y = false) (E : Entry) (t : Ty) (f : Bool)
    (hkeep : f = true → E.mode.isRoot = false →
      ∀ d ∈ E.path, ∀ v, S.inv d.root = some v → S.isPi v = false) :
    EntryWeaker { elemE (S.ρ y) (S.subE E) t with fresh := f } (S.subE { elemE (S.ρ y) E t with fresh := f }) := by
  by_cases h1 : t = .int
  · subst h1; exact EntryWeaker.refl _
  by_cases h2 : ∃ s, t = .slice s
  · obtain ⟨s, rfl⟩ := h2; exact EntryWeaker.refl _
  have h2' : ∀ s, t ≠ .slice s := fun s e => h2 ⟨s, e⟩
  have hel : ∀ E' : Entry, elemE (S.ρ y) E' t =
      ⟨t, .bor, true, derive (S.ρ y) E' .inner, E'.held, false, false, false, false⟩ := fun E' => by
    cases t <;> simp_all [elemE]
  rw [hel, hel]
  exact S.ew_sub_path (X := ⟨t, .bor, true, derive (S.ρ y) E .inner, E.held, false, false, f, false⟩)
    (P := derive (S.ρ y) (S.subE E) .inner) (derive_subE h hnp E rfl)
    (fun hft => by
      obtain ⟨h1, h2⟩ := derive_subE_keep h hnp .inner (hkeep hft)
      show (derive (S.ρ y) E .inner).flatMap S.subD ⊆ derive (S.ρ y) (S.subE E) .inner
      rw [h1, h2]; exact List.Subset.refl _) (by simp)

/-- ... and so is what is taken out. -/
theorem popE_subE (E : Entry) (t : Ty) :
    EntryWeaker (popE (S.ρ y) (S.subE E) t) (S.subE (popE (S.ρ y) E t)) := by
  cases t <;> exact EntryWeaker.refl _

/-- ... and what a share reads. -/
theorem getE_subE (h : S.OK) {y : Var} (hnp : S.isPi y = false) (E : Entry) (t : Ty) :
    EntryWeaker (getE (S.ρ y) (S.subE E) t) (S.subE (getE (S.ρ y) E t)) := by
  by_cases h1 : t = .int
  · subst h1; exact EntryWeaker.refl _
  have hge : ∀ E' : Entry, getE (S.ρ y) E' t =
      ⟨t, .bor, true, derive (S.ρ y) E' .share, E'.held, false, false, false, false⟩ := fun E' => by
    cases t <;> simp_all [getE]
  rw [hge, hge]
  exact S.ew_sub_path (X := ⟨t, .bor, true, derive (S.ρ y) E .share, E.held, false, false, false, false⟩)
    (P := derive (S.ρ y) (S.subE E) .share) (derive_subE h hnp E rfl) (fun hft => by cases hft) (by simp)

/-- ... and a field read. -/
theorem projDeps_subE (h : S.OK) {y : Var} (hnp : S.isPi y = false) (E : Entry) :
    projDeps (S.ρ y) (S.subE E) ⊆ (projDeps (S.ρ y) E).flatMap S.subD := by
  have hkp : ∀ k : Kind, (⟨S.ρ y, k⟩ : Dep) ∈ S.subD ⟨S.ρ y, k⟩ := fun k => by
    rw [S.subD_of_not (fun w hw => by simp only [inv_ρ h, Option.some.injEq] at hw; subst hw; exact hnp)]
    exact List.mem_singleton_self _
  unfold projDeps
  rw [subE_mode]
  split
  · intro d hd; rw [List.mem_singleton] at hd; subst hd
    exact List.mem_flatMap.mpr ⟨_, List.mem_singleton_self _, hkp _⟩
  · split
    · intro d hd; rw [List.mem_singleton] at hd; subst hd
      exact List.mem_flatMap.mpr ⟨_, List.mem_singleton_self _, hkp _⟩
    · exact List.Subset.refl _

theorem projE_subE (h : S.OK) {y : Var} (hnp : S.isPi y = false) (E : Entry) (t : Ty) (f : Bool)
    (hkeep : f = true → E.held = [] ∧ (E.mode.ownSlot = false → E.mode ≠ .rootb →
      ∀ d ∈ E.path, ∀ v, S.inv d.root = some v → S.isPi v = false)) :
    EntryWeaker { projE (S.ρ y) (S.subE E) t with fresh := f, heldFresh := f }
      (S.subE { projE (S.ρ y) E t with fresh := f, heldFresh := f }) := by
  have hkept : ∀ {ds : List Dep}, (∀ d ∈ ds, ∀ v, S.inv d.root = some v → S.isPi v = false) →
      ds.flatMap S.subD = ds := by
    intro ds hds
    induction ds with
    | nil => rfl
    | cons d ds ih =>
      rw [List.flatMap_cons, S.subD_of_not (hds d (by simp)), ih (fun d' hd' => hds d' (by simp [hd']))]
      rfl
  by_cases h1 : t = .int
  · subst h1; exact EntryWeaker.refl _
  have hpe : ∀ E' : Entry, projE (S.ρ y) E' t =
      ⟨t, .bor, true, projDeps (S.ρ y) E' ++ projHeld E'.mode.ownSlot t E'.held, E'.held, false, false, false,
        false⟩ := fun E' => by
    cases t <;> simp_all [projE]
  -- (AGORA-937: the substitution keeps the struct's mode, so the field
  -- depends on what the substituted struct holds where it did)
  have hphs : projHeld (S.subE E).mode.ownSlot t (S.subE E).held =
      (projHeld E.mode.ownSlot t E.held).flatMap S.subD := by
    rw [subE_mode, subE_held]; unfold projHeld; split <;> rfl
  rw [hpe, hpe]
  refine S.ew_sub_path (X := ⟨t, .bor, true, projDeps (S.ρ y) E ++ projHeld E.mode.ownSlot t E.held, E.held,
      false, false, f, f⟩)
    (P := projDeps (S.ρ y) (S.subE E) ++ projHeld (S.subE E).mode.ownSlot t (S.subE E).held) ?_ ?_ (by simp)
  · show projDeps (S.ρ y) (S.subE E) ++ projHeld (S.subE E).mode.ownSlot t (S.subE E).held ⊆
      (projDeps (S.ρ y) E ++ projHeld E.mode.ownSlot t E.held).flatMap S.subD
    rw [List.flatMap_append, hphs]
    exact append_sub (S.projDeps_subE h hnp E) (List.Subset.refl _)
  · intro hft
    obtain ⟨hh, hk⟩ := hkeep hft
    show (projDeps (S.ρ y) E ++ projHeld E.mode.ownSlot t E.held).flatMap S.subD ⊆
      projDeps (S.ρ y) (S.subE E) ++ projHeld (S.subE E).mode.ownSlot t (S.subE E).held
    rw [hphs]
    have hkp : ∀ d ∈ projDeps (S.ρ y) E, ∀ v, S.inv d.root = some v → S.isPi v = false := by
      intro d hd v hv
      unfold projDeps at hd
      split at hd
      · rw [List.mem_singleton] at hd; subst hd; rw [inv_ρ h] at hv; cases hv; exact hnp
      · split at hd
        · rw [List.mem_singleton] at hd; subst hd; rw [inv_ρ h] at hv; cases hv; exact hnp
        · rename_i ho hrb; exact hk (by simpa using ho) hrb d hd v hv
    have hpd : projDeps (S.ρ y) (S.subE E) = projDeps (S.ρ y) E := by
      unfold projDeps
      rw [subE_mode, subE_path]
      split
      · rfl
      · split
        · rfl
        · rename_i ho hrb; exact hkept (hk (by simpa using ho) hrb)
    rw [hh, projHeld_nil, List.append_nil, List.flatMap_nil, List.append_nil, hpd, hkept hkp]
    exact List.Subset.refl _

/-- AGORA-937: a fresh read's source (`projSrc_lift`) is lifted to one that
    holds nothing and depends on no region. -/
theorem proj_keep (h : S.OK) (hab : S.AbsOK Γa) (hfo : FreshOK Γa) {y : Var} {Ey : Entry}
    (hy : Γa y = some Ey) (hl : Ey.live = true)
    (hsrc : Ey.mode.frame ∨ (Ey.mode = .bor ∧ Ey.fresh = true ∧ Ey.heldFresh = true))
    (hhv : Ey.ty.holdsView = false) (hh : Ey.held = []) (hn : Ey.ty ≠ .int) :
    (S.liftE y Ey).held = [] ∧ ((S.liftE y Ey).mode.ownSlot = false → (S.liftE y Ey).mode ≠ .rootb →
      ∀ d ∈ (S.liftE y Ey).path, ∀ v, S.inv d.root = some v → S.isPi v = false) := by
  obtain ⟨h1, -, h3, _⟩ := projSrc_lift h hab hy hsrc hhv hh hn
  refine ⟨h3, fun hos _ => ?_⟩
  have hs : FreshSrc Γa y := by
    rcases hsrc with hfr | ⟨hb, hfr, _⟩
    · exact ⟨Ey, hy, Or.inl hfr⟩
    · exact ⟨Ey, hy, Or.inr ⟨hb, hfr, hl, hn⟩⟩
  refine fresh_keep h hab hfo hy hs ?_
  rcases h1 with hm | ⟨hm, _⟩
  · exfalso; rcases hm with hm | ⟨b, hm⟩ <;> rw [hm] at hos <;> cases hos
  · rw [hm]; rfl

/-- AGORA-937: a field taken out of a substituted entry is the field
    substituted. -/
theorem compE_subE (E : Entry) (t : Ty) : compE (S.subE E) t = S.subE (compE E t) := by
  unfold compE
  split
  · rfl
  · rfl
  · simp only [subE, ownHeld]
    split <;> rfl

theorem subE_lockE (t : Ty) : S.subE (lockE t) = lockE t := by
  unfold lockE; split <;> rfl

/-- Agora #909's own example: what a value handed to `vec_push` depends on,
    where the call places it, is what it depended on in the callee, renamed,
    and what the arguments hold (`S.A`). A borrowed parameter's view among
    them: its path is the caller's argument (`derive_lift_rootb`), and what it
    holds is what the argument holds (`held_lift`, `S.pe`), inside `S.A`. -/
theorem pushArg_ren_sub (h : S.OK) (hab : S.AbsOK Γa) {Fa : List Var} {y : Var} {Ey : Entry} {t : Ty}
    {D : List Dep} {Γa1 : Ctx} (hy : Γa y = some Ey) (hp : PushArg Γa Fa y Ey t D Γa1)
    {D' : List Dep} {Γc1 : Ctx} (hpa : PushArg (S.canon Γa) S.Fc (S.ρ y) (S.liftE y Ey) t D' Γc1) :
    D' ⊆ rds S.ρ D ++ S.A := by
  have hcat : ∀ {X Y L M : List Dep}, X ⊆ rds S.ρ L ++ S.A → Y ⊆ rds S.ρ M ++ S.A →
      X ++ Y ⊆ rds S.ρ (L ++ M) ++ S.A := by
    intro X Y L M hX hY d hd
    rw [rds, List.map_append]
    rcases List.mem_append.mp hd with h1 | h1
    · rcases List.mem_append.mp (hX h1) with h2 | h2
      · exact List.mem_append_left _ (List.mem_append_left _ h2)
      · exact List.mem_append_right _ h2
    · rcases List.mem_append.mp (hY h1) with h2 | h2
      · exact List.mem_append_left _ (List.mem_append_right _ h2)
      · exact List.mem_append_right _ h2
  cases hp with
  | move _ hm _ _ _ =>
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    cases hpa with
    | move => exact held_lift h hab hy
    | int => intro d hd; cases hd
    | slice hm' => rw [liftE_mode y hrb, hm] at hm'; rcases hm' with h1 | h1 <;> cases h1
  | int => cases hpa with
    | int => intro d hd; cases hd
    | move ho => simp [Ty.owning] at ho
  | slice hm =>
    cases hpa with
    | move _ hm' =>
      rcases hm with h1 | h1
      · rw [liftE_mode y (by rw [h1]; simp), h1] at hm'; cases hm'
      · have := (liftE_rootb h (v := y)).mpr h1; rw [hm'] at this; cases this
    | slice _ =>
      by_cases hrb : Ey.mode = .rootb
      · -- a view of a borrowed parameter: its path, renamed; what it holds, the argument's
        rw [derive_lift_rootb h hab hy hrb]
        exact hcat (fun d hd => List.mem_append_left _ hd) (held_lift h hab hy)
      · exact hcat (derive_lift h hab hy .self rfl) (held_lift h hab hy)

/-- AGORA-937: what a callee binding stores, where the call places it, is
    what it stored, renamed and substituted, or something the arguments held. -/
theorem pushArg_rens (h : S.OK) (hab : S.AbsOK Γa) {Fa : List Var} {y : Var} {Ey : Entry} {t : Ty}
    {D : List Dep} {Γa1 : Ctx} (hy : Γa y = some Ey) (hnp : S.isPi y = false)
    (hp : PushArg Γa Fa y Ey t D Γa1) :
    ∃ D', PushArg (S.canon Γa) S.Fc (S.ρ y) (S.subE (S.liftE y Ey)) t D' (S.canon Γa1) ∧
      D' ⊆ (rds S.ρ D ++ S.A).flatMap S.subD ∧
      (Ey.ty = t → D' ⊆ (rds S.ρ D ++ ownHeld true t S.A).flatMap S.subD) := by
  cases hp with
  | move ho hm hyF _ hds =>
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    have hctx : S.canon (setE (kill .replace false y Γa) y { Ey with live := false, dtor := false }) =
        setE (kill .replace false (S.ρ y) (S.canon Γa)) (S.ρ y)
          { S.subE (S.liftE y Ey) with live := false, dtor := false } := by
      rw [canon_setEs h _ hnp, canon_kill h hab (allowed_own hab hy hm _ _) hnp (hab.notReg hy (by rw [hm]; simp)), liftE_moved _ hrb]; rfl
    rw [hctx]
    refine ⟨_, PushArg.move ho (by rw [subE_mode, liftE_mode y hrb, hm]; rfl) (h.Fcout y)
      (NoPin.lift h hab (bnd_own hab hy hm)) (DtorSafe.canon h (allowed_own hab hy hm _ _) hds),
      S.flatMap_subD_mono (held_lift h hab hy), fun hty => ?_⟩
    rw [subE_held, liftE_held hrb, S.heldA_own (by rw [hm]; rfl), hm, hty]; exact List.Subset.refl _
  | int => exact ⟨[], PushArg.int, by simp, fun _ => by simp⟩
  | @slice s hm =>
    have hsl : ownHeld true (Ty.slice s) S.A = S.A := by simp [ownHeld, Ty.holdsView]
    have hpa' : PushArg (S.canon Γa) S.Fc (S.ρ y) (S.liftE y Ey) (.slice s)
        (derive (S.ρ y) (S.liftE y Ey) .self ++ (S.liftE y Ey).held) (S.canon Γa) := by
      refine PushArg.slice ?_
      rcases hm with hm | hm
      · left; rw [liftE_mode y (by rw [hm]; simp), hm]; rfl
      · right; rw [liftE_rootb h]; exact hm
    -- (what it depends on: `pushArg_ren_sub`, a borrowed parameter's view among them)
    have hs := pushArg_ren_sub h hab hy (PushArg.slice (F := Fa) hm) hpa'
    have hpa : PushArg (S.canon Γa) S.Fc (S.ρ y) (S.subE (S.liftE y Ey)) (.slice s)
        (derive (S.ρ y) (S.subE (S.liftE y Ey)) .self ++ (S.subE (S.liftE y Ey)).held) (S.canon Γa) := by
      refine PushArg.slice ?_
      rw [subE_mode]
      rcases hm with hm | hm
      · left; rw [liftE_mode y (by rw [hm]; simp), hm]; rfl
      · right; rw [liftE_rootb h]; exact hm
    have hD : derive (S.ρ y) (S.subE (S.liftE y Ey)) .self ++ (S.subE (S.liftE y Ey)).held ⊆
        (rds S.ρ (derive y Ey .self ++ Ey.held) ++ S.A).flatMap S.subD := by
      refine fun d hd => S.flatMap_subD_mono hs ?_
      rw [List.flatMap_append]
      rcases List.mem_append.mp hd with hd | hd
      · exact List.mem_append_left _ (derive_subE h hnp _ rfl hd)
      · exact List.mem_append_right _ hd
    exact ⟨_, hpa, hD, fun _ => by rw [hsl]; exact hD⟩

/-- Agora #916: ... and what it stores holds, in memory, only what it did in
    the callee, renamed, when the stored value is the frame's own in path and
    in what it holds (`FreshSrc`, `HeldSrc`): the lift adds it no memory of the
    arguments. -/
theorem pushArg_ren_held (h : S.OK) (hab : S.AbsOK Γa) {Fa : List Var} {y : Var} {Ey : Entry} {t : Ty}
    {D : List Dep} {Γa1 : Ctx} (hy : Γa y = some Ey) (hn : Ey.ty ≠ .int) (hp : PushArg Γa Fa y Ey t D Γa1)
    {D' : List Dep} {Γc1 : Ctx} (hpa : PushArg (S.canon Γa) S.Fc (S.ρ y) (S.liftE y Ey) t D' Γc1)
    (hfs : FreshSrc Γa y) (hhs : HeldSrc Γa y) : memDeps D' ⊆ rds S.ρ (memDeps D) := by
  -- (what the lift keeps of a list, in memory: its memory, renamed)
  have hmr : ∀ L : List Dep, memDeps (rds S.ρ L) = rds S.ρ (memDeps L) := by
    intro L; unfold memDeps; simp only [rds, List.filter_map]; rfl
  have hsub : ∀ {X L : List Dep}, X ⊆ rds S.ρ L ++ S.N → memDeps X ⊆ rds S.ρ (memDeps L) := by
    intro X L hX d hd
    obtain ⟨hdX, hdn⟩ := List.mem_filter.mp hd
    rcases List.mem_append.mp (hX hdX) with h1 | h1
    · rw [← hmr]; exact List.mem_filter.mpr ⟨h1, hdn⟩
    · simp [h.N_name d h1] at hdn
  have hlift : (S.liftE y Ey).held ⊆ rds S.ρ Ey.held ++ S.N :=
    (heldSrc_held_lift h hy hn hhs).trans (append_sub (List.Subset.refl _) (by
      split
      · exact List.Subset.refl _
      · exact List.nil_subset _))
  have hrb : Ey.mode ≠ .rootb := by
    obtain ⟨E0, h0, hc⟩ := hfs; rw [hy] at h0; cases h0
    rcases hc with hfr | ⟨hb, _⟩
    · rcases hfr with h1 | ⟨b, h1⟩ <;> rw [h1] <;> simp
    · rw [hb]; simp
  cases hp with
  | move _ hm _ _ _ =>
    cases hpa with
    | move => exact hsub hlift
    | int => intro d hd; cases hd
    | slice hm' =>
      rw [liftE_mode y hrb, hm] at hm'; rcases hm' with h1 | h1 <;> cases h1
  | int => cases hpa with
    | int => intro d hd; cases hd
    | move ho => simp [Ty.owning] at ho
  | slice hm =>
    cases hpa with
    | move _ hm' => rw [liftE_mode y hrb] at hm'; rcases hm with h1 | h1 <;> rw [h1] at hm' <;> cases hm'
    | slice _ =>
      rw [derive_lift_eq h hab hy hfs]
      refine hsub ((append_sub (List.Subset.refl (rds S.ρ (derive y Ey .self))) hlift).trans ?_)
      · intro d hd
        rcases List.mem_append.mp hd with h1 | h1
        · exact List.mem_append_left _ (by rw [rds, List.map_append]; exact List.mem_append_left _ h1)
        · rcases List.mem_append.mp h1 with h2 | h2
          · exact List.mem_append_left _ (by rw [rds, List.map_append]; exact List.mem_append_right _ h2)
          · exact List.mem_append_right _ h2

/-- AGORA-937: `pushArg_ren_held` with regions: what the stored value's
    substituted lift holds in memory is that of its lift, substituted. -/
theorem pushArg_ren_helds (h : S.OK) (hab : S.AbsOK Γa) {Fa : List Var} {y : Var} {Ey : Entry} {t : Ty}
    {D : List Dep} {Γa1 : Ctx} (hy : Γa y = some Ey) (hnp : S.isPi y = false) (hn : Ey.ty ≠ .int)
    (hp : PushArg Γa Fa y Ey t D Γa1)
    {D' : List Dep} {Γc1 : Ctx} (hpa : PushArg (S.canon Γa) S.Fc (S.ρ y) (S.subE (S.liftE y Ey)) t D' Γc1)
    (hfs : FreshSrc Γa y) (hhs : HeldSrc Γa y) : memDeps D' ⊆ (rds S.ρ (memDeps D)).flatMap S.subD := by
  -- (the same push of the lift, before the substitution)
  obtain ⟨D0, Γc0, hpa0, hD0⟩ : ∃ D0 Γc0, PushArg (S.canon Γa) S.Fc (S.ρ y) (S.liftE y Ey) t D0 Γc0 ∧
      D' ⊆ D0.flatMap S.subD := by
    cases hpa with
    | move ho hm hF hpin hds => exact ⟨_, _, PushArg.move ho hm hF hpin hds, List.Subset.refl _⟩
    | int => exact ⟨[], _, PushArg.int, List.Subset.refl _⟩
    | slice hm =>
      refine ⟨_, _, PushArg.slice hm, fun d hd => ?_⟩
      rw [List.flatMap_append]
      rcases List.mem_append.mp hd with hd | hd
      · exact List.mem_append_left _ (derive_subE h hnp _ rfl hd)
      · exact List.mem_append_right _ hd
  have hm0 : memDeps D' ⊆ memDeps (D0.flatMap S.subD) := fun e he =>
    List.mem_filter.mpr ⟨hD0 (List.mem_filter.mp he).1, (List.mem_filter.mp he).2⟩
  exact hm0.trans ((S.memDeps_flatMap_subD D0).trans
    (S.flatMap_subD_mono (pushArg_ren_held h hab hy hn hp hpa0 hfs hhs)))

/-- A right-hand side of the callee, where the call places it. AGORA-937: it
    reads no region (`hvs`), and its result is the lift substituted; a fresh
    borrow is on no region (`FreshOK`). -/
theorem RhsT.ren (h : S.OK) (hab : S.AbsOK Γa) (hfo : FreshOK Γa) {Fa : List Var} {r : Rhs} {E : Entry}
    {Γa1 : Ctx} (hr : RhsT Γa Fa r E Γa1) (hvs : ∀ v ∈ r.vars, S.isPi v = false) :
    ∃ E', RhsT (S.canon Γa) S.Fc (r.rename S.ρ) E' (S.canon Γa1) ∧
      ∀ x, EntryWeaker E' (S.subE (S.liftE x E)) := by
  cases hr with
  | expr he =>
    exact ⟨intE, RhsT.expr (exprT_ren h hab he (fun v hv => hvs v (by simpa [Rhs.vars] using hv))),
      fun x => S.subE_weaker (intE_lift x)⟩
  | new ht =>
    refine ⟨_, RhsT.new ht, fun x => S.subE_weaker (E := ⟨.vec _, .own, true, [], [], false, false, false, false⟩) ?_⟩
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp)
  | slit =>
    -- AGORA-980: nothing to lift; the lifted entry is the literal's, reading
    -- the arguments' (`S.A`), weaker on every field (by computation)
    refine ⟨_, RhsT.slit, fun x => S.subE_weaker (E := ⟨.slice .int, .bor, true, [], [], false, false, false, false⟩) ?_⟩
    exact EntryWeaker.mk' rfl rfl (by simp [Entry.fixed]) rfl (fun _ => List.nil_subset _) (List.nil_subset _)
      (fun h => by cases h) rfl (fun h => by cases h) (fun h => by cases h) (fun _ _ _ h => by cases h)
      (fun _ _ h => by cases h)
  | @moveOwn y Ey hy hl hm hyF _ hds =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    have hctx : S.canon (setE (kill .replace false y Γa) y { Ey with live := false, dtor := false }) =
        setE (kill .replace false (S.ρ y) (S.canon Γa)) (S.ρ y)
          { S.subE (S.liftE y Ey) with live := false, dtor := false } := by
      rw [canon_setEs h _ hpy, canon_kill h hab (allowed_own hab hy hm _ _) hpy (hab.notReg hy (by rw [hm]; simp)), liftE_moved _ hrb]; rfl
    rw [hctx]
    refine ⟨_, RhsT.moveOwn hc (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_mode, liftE_mode y hrb, hm]; rfl)
      (h.Fcout y) (NoPin.lift h hab (bnd_own hab hy hm))
      (DtorSafe.canon h (allowed_own hab hy hm _ _) hds), fun x => ?_⟩
    have he : S.liftE x ⟨Ey.ty, .own, true, [], Ey.held, false, false, false, false⟩ =
        ⟨(S.liftE y Ey).ty, .own, true, [], (S.liftE y Ey).held, false, false, false, false⟩ := by
      simp [liftE, heldA, hm, liftMode, rds, Mode.ownSlot]
    rw [he]; exact EntryWeaker.refl _
  | @take y Ey t hy hl hty hhv hcan hdb hyF _ hds =>
    -- Agora #826: an `inout .replace` parameter's take is its caller's owner's
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    have hos := hcan.ownSlot
    have hrb : Ey.mode ≠ .rootb := fun e => by rw [e] at hos; cases hos
    have hm3 : Ey.mode = .own ∨ Ey.mode = .bor ∨ Ey.mode = .inout .replace := by
      rcases canDo_replace_cases hcan with e | e
      · exact Or.inl e
      · exact Or.inr (Or.inr e)
    have hm3' : Ey.mode = .own ∨ Ey.mode = .inout .replace ∨ Ey.mode = .bor := by
      rcases hm3 with e | e | e
      · exact Or.inl e
      · exact Or.inr (Or.inr e)
      · exact Or.inr (Or.inl e)
    have hal : Allowed S .replace false y := by
      have := allowed_canDo' hab hy hcan
      rwa [hty, show (Ty.vec t).elem = t from rfl, hhv] at this
    have hvt : (Ty.vec t).holdsView = false := by simpa [Ty.holdsView] using hhv
    have hctx : S.canon (setE (kill .replace false y Γa) y ⟨Ey.ty, Ey.mode, true, [], [], false, false, false, false⟩) =
        setE (kill .replace false (S.ρ y) (S.canon Γa)) (S.ρ y)
          ⟨(S.subE (S.liftE y Ey)).ty, (S.subE (S.liftE y Ey)).mode, true, [], [], false, false, false, false⟩ := by
      rw [canon_setEs h _ hpy, canon_kill h hab hal hpy (hab.notReg hy (fun h' => by have := hcan.ownSlot; rw [h'] at this; cases this)),
        subE_ty, subE_mode, liftE_ty y hrb, liftE_mode y hrb]
      congr 1
      simp [subE, liftE, hrb, rds, hos, ownHeld, hty, hvt]
    rw [hctx]
    refine ⟨_, RhsT.take hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty y hrb]; exact hty) hhv
      (by rw [subE_mode, liftE_mode y hrb]; exact canDo_lift hcan) (by simp [liftE, hrb, hdb]) (h.Fcout y)
      (NoPin.lift h hab (bnd_replace hab hy hm3')) (DtorSafe.canon h hal hds), fun x => ?_⟩
    have he : S.liftE x ⟨Ey.ty, .own, true, [], Ey.held, false, false, false, false⟩ =
        ⟨(S.liftE y Ey).ty, .own, true, [], (S.liftE y Ey).held, false, false, false, false⟩ := by
      simp [liftE, hrb, liftMode, rds, hos, S.heldA_own hos, show Mode.ownSlot .own = true from rfl]
    rw [he]; exact EntryWeaker.refl _
  | @copyRoot y Ey hy hl hm =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    refine ⟨_, RhsT.copyRoot hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_mode, liftE_rootb h]; exact hm),
      fun x => ?_⟩
    have old : EntryWeaker ⟨(S.liftE y Ey).ty, .bor, true, derive (S.ρ y) (S.liftE y Ey) .self, (S.liftE y Ey).held,
        false, false, false, false⟩ (S.liftE x ⟨Ey.ty, .bor, true, derive y Ey .self, Ey.held, false, false, false, false⟩) := by
      refine EntryWeaker.mk' (by rw [liftE_ty x (by simp)]; exact (liftE_ty' h hab hy).symm)
        (by simp [liftE, liftMode]) (by simp) (by simp [liftE]) (fun _ => ?_) ?_
      · simp only [liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot]
        exact derive_lift h hab hy .self rfl
      · simp only [liftE, reduceCtorEq, ↓reduceIte]; exact held_lift h hab hy
    exact S.ew_sub_lift old (derive_subE h hpy _ rfl) (fun hf => by cases hf) (by simp)
  | @copyBor y Ey hy hl hm =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    refine ⟨_, RhsT.copyBor hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_mode, liftE_mode y hrb, hm]; rfl),
      fun x => ?_⟩
    have he : S.liftE x { Ey with dtor := false, dbind := false } =
        { S.liftE y Ey with dtor := false, dbind := false } := by simp [liftE, hrb, heldA]
    rw [he]; exact EntryWeaker.refl _
  | @moveUp y Ey ms q q' hy hl hm hyF _ hds hty hle =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    have hctx : S.canon (setE (kill .replace false y Γa) y { Ey with live := false, dtor := false }) =
        setE (kill .replace false (S.ρ y) (S.canon Γa)) (S.ρ y)
          { S.subE (S.liftE y Ey) with live := false, dtor := false } := by
      rw [canon_setEs h _ hpy, canon_kill h hab (allowed_own hab hy hm _ _) hpy (hab.notReg hy (by rw [hm]; simp)), liftE_moved _ hrb]; rfl
    rw [hctx]
    refine ⟨_, RhsT.moveUp hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_mode, liftE_mode y hrb, hm]; rfl)
      (h.Fcout y) (NoPin.lift h hab (bnd_own hab hy hm))
      (DtorSafe.canon h (allowed_own hab hy hm _ _) hds) (by rw [subE_ty, liftE_ty y hrb]; exact hty) hle,
      fun x => S.subE_weaker (E := ⟨.fn ms q', .own, true, [], (S.liftE y Ey).held, false, false, false, false⟩) ?_⟩
    have hoh : ownHeld true Ey.ty S.A ⊆ ownHeld true (.fn ms q') S.A := by
      rw [hty]
      cases q with
      | any => rw [hle.any_eq]; exact List.Subset.refl _
      | _ => simp [ownHeld, Ty.holdsView]
    refine EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') ?_
    simp only [liftE, hm, reduceCtorEq, ↓reduceIte, Mode.ownSlot]
    intro d hd
    rcases List.mem_append.mp hd with hd | hd
    · exact List.mem_append_left _ hd
    · exact List.mem_append_right _ (hoh (ownHeld_sub_mono (S.heldA_sub Ey) hd))
  | @copyUp y Ey ms q q' hy hl hm hty hle =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    refine ⟨_, RhsT.copyUp hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_mode, liftE_mode y hrb, hm]; rfl)
      (by rw [subE_ty, liftE_ty y hrb]; exact hty) hle,
      fun x => S.subE_weaker (E := { S.liftE y Ey with ty := .fn ms q', dtor := false, dbind := false }) ?_⟩
    -- (AGORA-909: a held-fresh borrow's lift holds the arguments' names only
    -- where its type holds a closure; `q.Le q'` keeps that, `Cross.Le.views`)
    have he : S.liftE x { Ey with ty := .fn ms q', dtor := false, dbind := false } =
        { { S.liftE y Ey with ty := .fn ms q', dtor := false, dbind := false } with
          held := rds S.ρ Ey.held ++ S.heldA { Ey with ty := .fn ms q' } } := by
      simp [liftE, hm, Mode.ownSlot, ownHeld, hty, heldA]
    rw [he]
    refine EntryWeaker.held_sup ?_ (by simp [liftE, hm, liftMode])
    simp only [liftE, hm, reduceCtorEq, ↓reduceIte, Mode.ownSlot, ownHeld_false]
    refine append_sub (List.Subset.refl _) ?_
    have hqv : q.views = true → q'.views = true := fun hv => by
      cases hq : q'.views
      · rw [hle.views hq] at hv; cases hv
      · rfl
    unfold heldA
    rw [hty, hm]
    cases hc : Ey.heldFresh <;> cases hv : q.views <;> cases hv' : q'.views <;> simp_all [Ty.hasFn]
  | @borrow y Ey t f hy hl ht hf =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    refine ⟨_, RhsT.borrow (f := f) hc (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_ty, liftE_ty' h hab hy]; exact ht)
      (fun hft => freshSrc_lift h hab hy (hf hft)), fun x => ?_⟩
    have old : EntryWeaker ⟨(S.liftE y Ey).ty, .bor, true, derive (S.ρ y) (S.liftE y Ey) .self,
        (S.liftE y Ey).held, false, false, f, false⟩
        (S.liftE x ⟨Ey.ty, .bor, true, derive y Ey .self, Ey.held, false, false, f, false⟩) := by
      cases f with
      | false =>
        refine EntryWeaker.mk' (by rw [liftE_ty x (by simp)]; exact (liftE_ty' h hab hy).symm)
          (by simp [liftE, liftMode]) (by simp) (by simp [liftE]) (fun _ => ?_) ?_
        · simp only [liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_eq_true,
            Bool.false_or, Bool.false_and]
          exact derive_lift h hab hy .self rfl
        · simp only [liftE, reduceCtorEq, ↓reduceIte]; exact held_lift h hab hy
      | true =>
        -- Agora #909: a fresh borrow is renamed exactly (`derive_lift_eq`)
        have heq := derive_lift_eq h hab hy (hf rfl) .self
        have hlp : (S.liftE x ⟨Ey.ty, .bor, true, derive y Ey .self, Ey.held, false, false, true, false⟩).path =
            rds S.ρ (derive y Ey .self) := by
          simp [liftE, Mode.ownSlot, ht]
        have hrp : (⟨(S.liftE y Ey).ty, .bor, true, derive (S.ρ y) (S.liftE y Ey) .self, (S.liftE y Ey).held,
            false, false, true, false⟩ : Entry).path = rds S.ρ (derive y Ey .self) := heq
        refine EntryWeaker.mk' (by rw [liftE_ty x (by simp)]; exact (liftE_ty' h hab hy).symm)
          (by simp [liftE, liftMode]) (by simp) (by simp [liftE]) (fun _ => ?_) ?_
          (hf := fun _ _ _ _ => ⟨rfl, ?_⟩)
        · rw [hlp, hrp]; exact List.Subset.refl _
        · simp only [liftE, reduceCtorEq, ↓reduceIte]; exact held_lift h hab hy
        · rw [hlp, hrp]; exact List.Subset.refl _
    exact S.ew_sub_lift old (P := derive (S.ρ y) (S.subE (S.liftE y Ey)) .self) (derive_subE h hpy _ rfl)
      (fun hft => by
        obtain ⟨h1, h2⟩ := derive_subE_keep h hpy .self (fresh_keep h hab hfo hy (hf hft))
        show (derive (S.ρ y) (S.liftE y Ey) .self).flatMap S.subD ⊆ derive (S.ρ y) (S.subE (S.liftE y Ey)) .self
        rw [h1, h2]; exact List.Subset.refl _) (by simp)
  | @«at» y i Ey t f hy hl ht hi hf =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    refine ⟨_, RhsT.at (f := f) hc (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_ty, liftE_ty' h hab hy]; exact ht)
      (exprT_ren h hab hi (fun v hv => hvs v (by simp [Rhs.vars, hv])))
      (fun hft => ⟨freshSrc_lift h hab hy (hf hft).1, (hf hft).2⟩), fun x => ?_⟩
    have old : EntryWeaker { elemE (S.ρ y) (S.liftE y Ey) t with fresh := f }
        (S.liftE x { elemE y Ey t with fresh := f }) := by
      cases f with
      | false =>
        rw [Entry.with_fresh_eq (by cases t <;> rfl), Entry.with_fresh_eq (by cases t <;> rfl)]
        exact elemE_lift h hab hy t x
      | true =>
        -- Agora #909: a fresh element borrow is renamed exactly (`derive_lift_eq`)
        obtain ⟨hs, hns⟩ := hf rfl
        have heq := derive_lift_eq h hab hy hs .inner
        -- the lift in closed form once, not unfolded in every case below
        rw [S.liftE_of_bor x (E := { elemE y Ey t with fresh := true }) (elemE_mode y Ey t)]
        cases t
        case int =>
          exact EntryWeaker.mk' (by simp [elemE, intE]) (by simp [elemE, intE])
            (by simp [elemE, intE]) (by simp [elemE, intE]) (fun _ d hd => by simp [elemE, intE] at hd)
            (fun d hd => by simp [elemE, intE] at hd) (hf := fun _ hn _ _ => absurd (by simp [elemE, intE]) hn)
        case slice s => exact absurd rfl (hns s)
        all_goals
          refine EntryWeaker.mk' (by simp [elemE]) (by simp [elemE]) (by simp [elemE])
            (by simp [elemE]) (fun _ => ?_) ?_ (hf := fun _ _ _ _ => ⟨rfl, ?_⟩)
          · simp only [elemE]; rw [heq]; simp
          · simp only [elemE, ownHeld_false]; exact held_lift h hab hy
          · simp only [elemE]; rw [heq]; simp
    exact (S.elemE_subE h hpy _ t f (fun hft => fresh_keep h hab hfo hy (hf hft).1)).trans (S.subE_weaker old)
  | @view y Ey t fv hv hy hl ht hhv hfs0 hhs =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    -- (Agora #916: a fresh view's source is an owner or an `inout` parameter,
    -- lifted to an owner)
    have hfs : fv = true → FreshSrc Γa y := fun hf => by
      obtain ⟨E0, h0, hm⟩ := hfs0 hf; exact ⟨E0, h0, Or.inl hm⟩
    have hfl : fv = true → ∃ E', S.canon Γa (S.ρ y) = some E' ∧ E'.mode.frame := fun hf => by
      obtain ⟨E0, h0, hm⟩ := hfs0 hf
      rw [hy] at h0; cases h0
      have hrb : Ey.mode ≠ .rootb := by rcases hm with h1 | ⟨b, h1⟩ <;> rw [h1] <;> simp
      refine ⟨S.subE (S.liftE y Ey), hc, ?_⟩
      rw [subE_mode, liftE_mode y hrb]; rcases hm with h1 | ⟨b, h1⟩ <;> rw [h1] <;> exact Or.inl rfl
    refine ⟨_, RhsT.view (f := fv) (h := hv) hc (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_ty, liftE_ty' h hab hy]; exact ht) hhv
      hfl (fun hh => heldSrc_lift h hab hy (hhs hh)), fun x => ?_⟩
    have old : EntryWeaker ⟨.slice t, .bor, true, derive (S.ρ y) (S.liftE y Ey) .view, (S.liftE y Ey).held,
        false, false, fv, hv⟩ (S.liftE x ⟨.slice t, .bor, true, derive y Ey .view, Ey.held, false, false, fv, hv⟩) := by
      refine EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode])
        (by simp) (by simp [liftE]) (fun _ => ?_) ?_ (hg := fun _ _ hhf => by simpa [liftE] using hhf)
        (hf := fun _ _ _ hfr => by
          -- Agora #916: a fresh view is renamed exactly, as a fresh borrow is
          simp only [liftE, reduceCtorEq, ↓reduceIte] at hfr
          subst hfr
          refine ⟨rfl, ?_⟩
          show (S.liftE x ⟨.slice t, .bor, true, derive y Ey .view, Ey.held, false, false, true, hv⟩).path ⊆
            derive (S.ρ y) (S.liftE y Ey) .view
          rw [derive_lift_eq h hab hy (hfs rfl)]
          simp [liftE, Mode.ownSlot])
      · cases fv with
        | false =>
          simp only [liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_or]
          exact derive_lift h hab hy .view rfl
        | true =>
          show derive (S.ρ y) (S.liftE y Ey) .view ⊆
            (S.liftE x ⟨.slice t, .bor, true, derive y Ey .view, Ey.held, false, false, true, hv⟩).path
          rw [derive_lift_eq h hab hy (hfs rfl)]
          simp [liftE, Mode.ownSlot]
      · -- Agora #916: a held-fresh view holds what its source does, renamed: no
        -- memory of the arguments
        show (S.liftE y Ey).held ⊆
          (S.liftE x ⟨.slice t, .bor, true, derive y Ey .view, Ey.held, false, false, fv, hv⟩).held
        rw [S.liftE_held (v := x) (E := ⟨.slice t, .bor, true, derive y Ey .view, Ey.held, false, false, fv, hv⟩)
          (by simp)]
        simp only [Mode.ownSlot, ownHeld_false]
        cases hv with
        | false => rw [S.heldA_of rfl]; exact held_lift h hab hy
        | true =>
          rw [S.heldA_P ⟨rfl, rfl, by simp⟩]
          refine (heldSrc_held_lift h hy (by rw [ht]; simp) (hhs rfl)).trans
            (append_sub (List.Subset.refl _) ?_)
          simp only [ht, Ty.hasFn]
          by_cases ht' : t.hasFn = true <;> simp [ht']
    exact S.ew_sub_lift old (P := derive (S.ρ y) (S.subE (S.liftE y Ey)) .view) (derive_subE h hpy _ rfl)
      (fun hft => by
        obtain ⟨h1, h2⟩ := derive_subE_keep h hpy .view (fresh_keep h hab hfo hy (hfs hft))
        show (derive (S.ρ y) (S.liftE y Ey) .view).flatMap S.subD ⊆ derive (S.ρ y) (S.subE (S.liftE y Ey)) .view
        rw [h1, h2]; exact List.Subset.refl _) (by simp)
  | @sat y i Ey t f hy hl ht hi hf =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    refine ⟨_, RhsT.sat (f := f) hc (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_ty, liftE_ty' h hab hy]; exact ht)
      (exprT_ren h hab hi (fun v hv => hvs v (by simp [Rhs.vars, hv])))
      (fun hft => ⟨freshSrc_lift h hab hy (hf hft).1, (hf hft).2⟩), fun x => ?_⟩
    have old : EntryWeaker { elemE (S.ρ y) (S.liftE y Ey) t with fresh := f }
        (S.liftE x { elemE y Ey t with fresh := f }) := by
      cases f with
      | false =>
        rw [Entry.with_fresh_eq (by cases t <;> rfl), Entry.with_fresh_eq (by cases t <;> rfl)]
        exact elemE_lift h hab hy t x
      | true =>
        -- AGORA-909: a fresh element read through a slice is renamed exactly (`derive_lift_eq`)
        obtain ⟨hs, hns⟩ := hf rfl
        have heq := derive_lift_eq h hab hy hs .inner
        -- the lift in closed form once, not unfolded in every case below
        rw [S.liftE_of_bor x (E := { elemE y Ey t with fresh := true }) (elemE_mode y Ey t)]
        cases t
        case int =>
          exact EntryWeaker.mk' (by simp [elemE, intE]) (by simp [elemE, intE])
            (by simp [elemE, intE]) (by simp [elemE, intE]) (fun _ d hd => by simp [elemE, intE] at hd)
            (fun d hd => by simp [elemE, intE] at hd) (hf := fun _ hn _ _ => absurd (by simp [elemE, intE]) hn)
        case slice s => exact absurd rfl (hns s)
        all_goals
          refine EntryWeaker.mk' (by simp [elemE]) (by simp [elemE]) (by simp [elemE])
            (by simp [elemE]) (fun _ => ?_) ?_ (hf := fun _ _ _ _ => ⟨rfl, ?_⟩)
          · simp only [elemE]; rw [heq]; simp
          · simp only [elemE, ownHeld_false]; exact held_lift h hab hy
          · simp only [elemE]; rw [heq]; simp
    exact (S.elemE_subE h hpy _ t f (fun hft => fresh_keep h hab hfo hy (hf hft).1)).trans (S.subE_weaker old)
  | @pop y Ey t hy hl ht hcan hyF hds =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    have hrb : Ey.mode ≠ .rootb := by
      rcases hcan with hm | ⟨b, hm, _⟩ <;> rw [hm] <;> simp
    have hos : Ey.mode.ownSlot = true := by rcases hcan with hm | ⟨b, hm, _⟩ <;> rw [hm] <;> rfl
    rw [canon_kill h hab (allowed_canDo hab hy ht hcan) hpy (hab.notReg hy (fun h' => by have := hcan.ownSlot; rw [h'] at this; cases this))]
    exact ⟨_, RhsT.pop hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab hy]; exact ht)
      (by rw [subE_mode, liftE_mode y hrb]; exact canDo_lift hcan) (h.Fcout y)
      (DtorSafe.canon h (allowed_canDo hab hy ht hcan) hds),
      fun x => (S.popE_subE _ t).trans (S.subE_weaker (popE_lift h hab hy ht hrb hos x))⟩
  | @remove y ix Ey t hy hl ht hcan hyF hds hix =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    have hrb : Ey.mode ≠ .rootb := by
      rcases hcan with hm | ⟨b, hm, _⟩ <;> rw [hm] <;> simp
    have hos : Ey.mode.ownSlot = true := by rcases hcan with hm | ⟨b, hm, _⟩ <;> rw [hm] <;> rfl
    rw [canon_kill h hab (allowed_canDo hab hy ht hcan) hpy (hab.notReg hy (fun h' => by have := hcan.ownSlot; rw [h'] at this; cases this))]
    exact ⟨_, RhsT.remove hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab hy]; exact ht)
      (by rw [subE_mode, liftE_mode y hrb]; exact canDo_lift hcan) (h.Fcout y)
      (DtorSafe.canon h (allowed_canDo hab hy ht hcan) hds)
      (exprT_ren h hab hix (fun v hv => hvs v (by simp [Rhs.vars, hv]))),
      fun x => (S.popE_subE _ t).trans (S.subE_weaker (popE_lift h hab hy ht hrb hos x))⟩
  | @pair y z Ey Ez Γa1 Γa2 Dy Dz hy hly hpa1 hz hlz hpa2 hzd =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hpz : S.isPi z = false := hvs z (by simp [Rhs.vars])
    have hc1 := canon_some h hy hpy
    obtain ⟨D1, hp1, hD1, hD1o⟩ := pushArg_rens h hab hy hpy hpa1
    have hab1 := PushArg.absOK (S := S) hy hpa1 hab
    have hc2 := canon_some h hz hpz
    obtain ⟨D2, hp2, hD2, hD2o⟩ := pushArg_rens h hab1 hz hpz hpa2
    have hty1 := liftE_ty' h hab hy
    have hty2 := liftE_ty' h hab1 hz
    have hty1' : (S.subE (S.liftE y Ey)).ty = Ey.ty := by rw [subE_ty, hty1]
    have hty2' : (S.subE (S.liftE z Ez)).ty = Ez.ty := by rw [subE_ty, hty2]
    rw [← hty1'] at hp1
    rw [← hty2'] at hp2
    have hzd' : (S.subE (S.liftE z Ez)).mode.ownSlot = true → S.ρ z ∉ roots D1 := by
      intro hos hr
      rw [subE_mode] at hos
      have hos' : Ez.mode.ownSlot = true := by
        by_cases hrb : Ez.mode = .rootb
        · rw [(liftE_rootb h).mpr hrb] at hos; cases hos
        · rw [liftE_mode z hrb] at hos; cases hm : Ez.mode <;> simp_all [liftMode, Mode.ownSlot]
      obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
      obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp (hD1 hd)
      rcases S.subD_frame h hde with rfl | ⟨hout, _⟩
      · rcases List.mem_append.mp he with h1 | h1
        · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
          have : d0.root = z := h.inj _ _ hdr
          exact hzd hos' (this ▸ List.mem_map_of_mem hd0)
        · exact A_out h h1 z hdr.symm
      · exact hout z hdr.symm
    refine ⟨_, RhsT.pair hc1 (by rw [subE_live, liftE_live]; exact hly) hp1 hc2
      (by rw [subE_live, liftE_live]; exact hlz) hp2 hzd', fun x => ?_⟩
    refine EntryWeaker.mk' (by rw [subE_ty, liftE_ty x (by simp)]; simp [hty1, hty2]) (by simp [liftE, liftMode])
      (by simp) (by simp [liftE]) (fun h' => by simp [Mode.ownSlot] at h') ?_
    have key : (rds S.ρ Dy ++ ownHeld true Ey.ty S.A) ++ (rds S.ρ Dz ++ ownHeld true Ez.ty S.A) ⊆
        (S.liftE x ⟨.prod Ey.ty Ez.ty, .own, true, [], Dy ++ Dz, false, false, false, false⟩).held := by
      simp only [liftE, reduceCtorEq, ↓reduceIte]
      have hm1 : ownHeld true Ey.ty S.A ⊆ ownHeld true (.prod Ey.ty Ez.ty) S.A :=
        ownHeld_mono (fun h => by simp [Ty.holdsView, h]) _
      have hm2 : ownHeld true Ez.ty S.A ⊆ ownHeld true (.prod Ey.ty Ez.ty) S.A :=
        ownHeld_mono (fun h => by simp [Ty.holdsView, h]) _
      exact app_lift (fun d hd => append_sub (List.Subset.refl _) hm1 hd)
        (fun d hd => append_sub (List.Subset.refl _) hm2 hd)
    rw [subE_held]
    intro d hd
    refine S.flatMap_subD_mono key ?_
    rw [List.flatMap_append]
    rcases List.mem_append.mp hd with hd | hd
    · exact List.mem_append_left _ (hD1o rfl hd)
    · exact List.mem_append_right _ (hD2o rfl hd)
  | @fst y Ey a b f hy hl ht hf =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    -- (AGORA-909: a fresh read's source lifts to one holding nothing, `projSrc_lift`)
    have hfl : f = true → ((S.subE (S.liftE y Ey)).mode.frame ∨ ((S.subE (S.liftE y Ey)).mode = .bor ∧
        (S.subE (S.liftE y Ey)).fresh = true ∧ (S.subE (S.liftE y Ey)).heldFresh = true)) ∧
        (S.subE (S.liftE y Ey)).ty.holdsView = false ∧ (S.subE (S.liftE y Ey)).held = [] ∧
        ∀ s, a ≠ .slice s := fun hft => by
      obtain ⟨hsrc, hhv, hh, hns⟩ := hf hft
      obtain ⟨h1, h2, h3, _⟩ := projSrc_lift h hab hy hsrc hhv hh (Ty.undtor_ne_int_of ht)
      rw [subE_mode, subE_fresh, subE_heldFresh, subE_ty, subE_held, h3]
      exact ⟨h1, h2, rfl, hns⟩
    refine ⟨_, RhsT.fst (f := f) hc (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_ty, liftE_ty' h hab hy]; exact ht) hfl, fun x => ?_⟩
    have old : EntryWeaker { projE (S.ρ y) (S.liftE y Ey) a with fresh := f, heldFresh := f }
        (S.liftE x { projE y Ey a with fresh := f, heldFresh := f }) := by
      cases f with
      | false =>
        rw [Entry.with_fresh_held_eq (by cases a <;> rfl) (by cases a <;> rfl),
          Entry.with_fresh_held_eq (by cases a <;> rfl) (by cases a <;> rfl)]
        exact projE_lift h hab hy a x
      | true =>
        obtain ⟨hsrc, hhv, hh, _⟩ := hf rfl
        have hav : a.holdsView = false := by
          have := Ty.holdsView_undtor Ey.ty; rw [ht] at this; simp [Ty.holdsView] at this; simp_all
        exact projE_fresh_lift h hab hy hsrc hhv hh (Ty.undtor_ne_int_of ht) hav x
    exact (S.projE_subE h hpy _ a f (fun hft => by
      obtain ⟨hsrc, hhv, hh, _⟩ := hf hft
      exact S.proj_keep h hab hfo hy hl hsrc hhv hh (Ty.undtor_ne_int_of ht))).trans (S.subE_weaker old)
  | @snd y Ey a b f hy hl ht hf =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    have hfl : f = true → ((S.subE (S.liftE y Ey)).mode.frame ∨ ((S.subE (S.liftE y Ey)).mode = .bor ∧
        (S.subE (S.liftE y Ey)).fresh = true ∧ (S.subE (S.liftE y Ey)).heldFresh = true)) ∧
        (S.subE (S.liftE y Ey)).ty.holdsView = false ∧ (S.subE (S.liftE y Ey)).held = [] ∧
        ∀ s, b ≠ .slice s := fun hft => by
      obtain ⟨hsrc, hhv, hh, hns⟩ := hf hft
      obtain ⟨h1, h2, h3, _⟩ := projSrc_lift h hab hy hsrc hhv hh (Ty.undtor_ne_int_of ht)
      rw [subE_mode, subE_fresh, subE_heldFresh, subE_ty, subE_held, h3]
      exact ⟨h1, h2, rfl, hns⟩
    refine ⟨_, RhsT.snd (f := f) hc (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_ty, liftE_ty' h hab hy]; exact ht) hfl, fun x => ?_⟩
    have old : EntryWeaker { projE (S.ρ y) (S.liftE y Ey) b with fresh := f, heldFresh := f }
        (S.liftE x { projE y Ey b with fresh := f, heldFresh := f }) := by
      cases f with
      | false =>
        rw [Entry.with_fresh_held_eq (by cases b <;> rfl) (by cases b <;> rfl),
          Entry.with_fresh_held_eq (by cases b <;> rfl) (by cases b <;> rfl)]
        exact projE_lift h hab hy b x
      | true =>
        obtain ⟨hsrc, hhv, hh, _⟩ := hf rfl
        have hav : b.holdsView = false := by
          have := Ty.holdsView_undtor Ey.ty; rw [ht] at this; simp [Ty.holdsView] at this; simp_all
        exact projE_fresh_lift h hab hy hsrc hhv hh (Ty.undtor_ne_int_of ht) hav x
    exact (S.projE_subE h hpy _ b f (fun hft => by
      obtain ⟨hsrc, hhv, hh, _⟩ := hf hft
      exact S.proj_keep h hab hfo hy hl hsrc hhv hh (Ty.undtor_ne_int_of ht))).trans (S.subE_weaker old)
  | @inl y b Ey Γa1 D hy hly hpa hb =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc1 := canon_some h hy hpy
    obtain ⟨D1, hp1, hD1, hD1o⟩ := pushArg_rens h hab hy hpy hpa
    have hty1 := liftE_ty' h hab hy
    have hty1' : (S.subE (S.liftE y Ey)).ty = Ey.ty := by rw [subE_ty, hty1]
    rw [← hty1'] at hp1
    refine ⟨_, RhsT.inl hc1 (by rw [subE_live, liftE_live]; exact hly) hp1 hb, fun x => ?_⟩
    refine EntryWeaker.mk' (by rw [subE_ty, liftE_ty x (by simp)]; simp [hty1]) (by simp [liftE, liftMode])
      (by simp) (by simp [liftE]) (fun h' => by simp [Mode.ownSlot] at h') ?_
    have key : rds S.ρ D ++ ownHeld true Ey.ty S.A ⊆
        (S.liftE x ⟨.sum Ey.ty b, .own, true, [], D, false, false, false, false⟩).held := by
      simp only [liftE, reduceCtorEq, ↓reduceIte]
      exact fun d hd => append_sub (List.Subset.refl _)
        (ownHeld_mono (fun h => by simp [Ty.holdsView, h]) _) hd
    rw [subE_held]
    exact fun d hd => S.flatMap_subD_mono key (hD1o rfl hd)
  | @inr a y Ey Γa1 D hy hly hpa ha =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc1 := canon_some h hy hpy
    obtain ⟨D1, hp1, hD1, hD1o⟩ := pushArg_rens h hab hy hpy hpa
    have hty1 := liftE_ty' h hab hy
    have hty1' : (S.subE (S.liftE y Ey)).ty = Ey.ty := by rw [subE_ty, hty1]
    rw [← hty1'] at hp1
    refine ⟨_, RhsT.inr hc1 (by rw [subE_live, liftE_live]; exact hly) hp1 ha, fun x => ?_⟩
    refine EntryWeaker.mk' (by rw [subE_ty, liftE_ty x (by simp)]; simp [hty1]) (by simp [liftE, liftMode])
      (by simp) (by simp [liftE]) (fun h' => by simp [Mode.ownSlot] at h') ?_
    have key : rds S.ρ D ++ ownHeld true Ey.ty S.A ⊆
        (S.liftE x ⟨.sum a Ey.ty, .own, true, [], D, false, false, false, false⟩).held := by
      simp only [liftE, reduceCtorEq, ↓reduceIte]
      exact fun d hd => append_sub (List.Subset.refl _)
        (ownHeld_mono (fun h => by simp [Ty.holdsView, h]) _) hd
    rw [subE_held]
    exact fun d hd => S.flatMap_subD_mono key (hD1o rfl hd)
  | @pack fs te ms q y cs Ey Γa1 D hy hly hte hpa hcaps hq =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc1 := canon_some h hy hpy
    obtain ⟨D1, hp1, hD1, hD1o⟩ := pushArg_rens h hab hy hpy hpa
    have hty1 := liftE_ty' h hab hy
    refine ⟨_, RhsT.pack hc1 (by rw [subE_live, liftE_live]; exact hly) (by rw [subE_ty, hty1]; exact hte) hp1
      (CapsOK.lift h (PushArg.absOK hy hpa hab) hcaps hD1) (hq.map _), fun x => ?_⟩
    refine EntryWeaker.mk' (by rw [subE_ty, liftE_ty x (by simp)]) (by simp [liftE, liftMode]) (by simp)
      (by simp [liftE]) (fun h' => by simp [Mode.ownSlot] at h') ?_
    have key : ∀ d, d ∈ rds S.ρ D ++ ownHeld true te S.A ∨ d ∈ capDeps (cs.map fun c => (S.ρ c.1, c.2)) →
        d ∈ (S.liftE x ⟨.fn ms q, .own, true, [], D ++ capDeps cs, false, false, false, false⟩).held := by
      intro d hd
      simp only [liftE, reduceCtorEq, ↓reduceIte]
      rcases hd with hd' | hd
      · rcases List.mem_append.mp hd' with hd' | hd'
        · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd'
          exact List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_append_left _ hd0, rfl⟩)
        · exact List.mem_append_right _ (ownHeld_mono hq.holdsView _ hd')
      · obtain ⟨c', hc', rfl⟩ := List.mem_map.mp hd
        obtain ⟨c, hc, rfl⟩ := List.mem_map.mp hc'
        exact List.mem_append_left _ (mem_rds.mpr ⟨⟨c.1, .name c.2.1.bound c.2.2⟩,
          List.mem_append_right _ (List.mem_map_of_mem hc), rfl⟩)
    rw [subE_held]
    intro d hd
    rcases List.mem_append.mp hd with hd | hd
    · obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp (hD1o hte hd)
      exact List.mem_flatMap.mpr ⟨e, key e (Or.inl he), hde⟩
    · -- a capture is a statement variable, so on no region
      have hnp : ∀ v, S.inv d.root = some v → S.isPi v = false := by
        obtain ⟨c', hc', rfl⟩ := List.mem_map.mp hd
        obtain ⟨c, hc, rfl⟩ := List.mem_map.mp hc'
        intro v hv; rw [inv_ρ h] at hv; cases hv
        exact hvs c.1 (by simp [Rhs.vars]; exact Or.inr ⟨c.2.1, c.2.2, hc⟩)
      exact List.mem_flatMap.mpr ⟨d, key d (Or.inr hd), by rw [S.subD_of_not hnp]; exact List.mem_singleton_self _⟩
  | @getl y Ey a b f hy hl ht hf =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    -- (AGORA-909: a fresh read's source lifts to one holding nothing, `projSrc_lift`)
    have hfl : f = true → ((S.subE (S.liftE y Ey)).mode.frame ∨ ((S.subE (S.liftE y Ey)).mode = .bor ∧
        (S.subE (S.liftE y Ey)).fresh = true ∧ (S.subE (S.liftE y Ey)).heldFresh = true)) ∧
        (S.subE (S.liftE y Ey)).ty.holdsView = false ∧ (S.subE (S.liftE y Ey)).held = [] ∧
        ∀ s, a ≠ .slice s := fun hft => by
      obtain ⟨hsrc, hhv, hh, hns⟩ := hf hft
      obtain ⟨h1, h2, h3, _⟩ := projSrc_lift h hab hy hsrc hhv hh (Ty.undtor_ne_int_of_sum ht)
      rw [subE_mode, subE_fresh, subE_heldFresh, subE_ty, subE_held, h3]
      exact ⟨h1, h2, rfl, hns⟩
    refine ⟨_, RhsT.getl (f := f) hc (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_ty, liftE_ty' h hab hy]; exact ht) hfl, fun x => ?_⟩
    have old : EntryWeaker { projE (S.ρ y) (S.liftE y Ey) a with fresh := f, heldFresh := f }
        (S.liftE x { projE y Ey a with fresh := f, heldFresh := f }) := by
      cases f with
      | false =>
        rw [Entry.with_fresh_held_eq (by cases a <;> rfl) (by cases a <;> rfl),
          Entry.with_fresh_held_eq (by cases a <;> rfl) (by cases a <;> rfl)]
        exact projE_lift h hab hy a x
      | true =>
        obtain ⟨hsrc, hhv, hh, _⟩ := hf rfl
        have hav : a.holdsView = false := by
          have := Ty.holdsView_undtor Ey.ty; rw [ht] at this; simp [Ty.holdsView] at this; simp_all
        exact projE_fresh_lift h hab hy hsrc hhv hh (Ty.undtor_ne_int_of_sum ht) hav x
    exact (S.projE_subE h hpy _ a f (fun hft => by
      obtain ⟨hsrc, hhv, hh, _⟩ := hf hft
      exact S.proj_keep h hab hfo hy hl hsrc hhv hh (Ty.undtor_ne_int_of_sum ht))).trans (S.subE_weaker old)
  | @getr y Ey a b f hy hl ht hf =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    have hfl : f = true → ((S.subE (S.liftE y Ey)).mode.frame ∨ ((S.subE (S.liftE y Ey)).mode = .bor ∧
        (S.subE (S.liftE y Ey)).fresh = true ∧ (S.subE (S.liftE y Ey)).heldFresh = true)) ∧
        (S.subE (S.liftE y Ey)).ty.holdsView = false ∧ (S.subE (S.liftE y Ey)).held = [] ∧
        ∀ s, b ≠ .slice s := fun hft => by
      obtain ⟨hsrc, hhv, hh, hns⟩ := hf hft
      obtain ⟨h1, h2, h3, _⟩ := projSrc_lift h hab hy hsrc hhv hh (Ty.undtor_ne_int_of_sum ht)
      rw [subE_mode, subE_fresh, subE_heldFresh, subE_ty, subE_held, h3]
      exact ⟨h1, h2, rfl, hns⟩
    refine ⟨_, RhsT.getr (f := f) hc (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_ty, liftE_ty' h hab hy]; exact ht) hfl, fun x => ?_⟩
    have old : EntryWeaker { projE (S.ρ y) (S.liftE y Ey) b with fresh := f, heldFresh := f }
        (S.liftE x { projE y Ey b with fresh := f, heldFresh := f }) := by
      cases f with
      | false =>
        rw [Entry.with_fresh_held_eq (by cases b <;> rfl) (by cases b <;> rfl),
          Entry.with_fresh_held_eq (by cases b <;> rfl) (by cases b <;> rfl)]
        exact projE_lift h hab hy b x
      | true =>
        obtain ⟨hsrc, hhv, hh, _⟩ := hf rfl
        have hav : b.holdsView = false := by
          have := Ty.holdsView_undtor Ey.ty; rw [ht] at this; simp [Ty.holdsView] at this; simp_all
        exact projE_fresh_lift h hab hy hsrc hhv hh (Ty.undtor_ne_int_of_sum ht) hav x
    exact (S.projE_subE h hpy _ b f (fun hft => by
      obtain ⟨hsrc, hhv, hh, _⟩ := hf hft
      exact S.proj_keep h hab hfo hy hl hsrc hhv hh (Ty.undtor_ne_int_of_sum ht))).trans (S.subE_weaker old)
  | @takel y Ey a b hy hl hm hty hyF _ hds =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    have hctx : S.canon (setE (kill .replace false y Γa) y { Ey with live := false, dtor := false }) =
        setE (kill .replace false (S.ρ y) (S.canon Γa)) (S.ρ y)
          { S.subE (S.liftE y Ey) with live := false, dtor := false } := by
      rw [canon_setEs h _ hpy, canon_kill h hab (allowed_own hab hy hm _ _) hpy (hab.notReg hy (by rw [hm]; simp)), liftE_moved _ hrb]; rfl
    rw [hctx]
    exact ⟨_, RhsT.takel hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_mode, liftE_mode y hrb, hm]; rfl)
      (by rw [subE_ty, liftE_ty' h hab hy]; exact hty) (h.Fcout y) (NoPin.lift h hab (bnd_own hab hy hm))
      (DtorSafe.canon h (allowed_own hab hy hm _ _) hds),
      fun x => by rw [S.compE_subE]; exact S.subE_weaker (compE_lift h hab hy a x)⟩
  | @taker y Ey a b hy hl hm hty hyF _ hds =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc : S.canon Γa (S.ρ y) = some (S.subE (S.liftE y Ey)) := canon_some h hy hpy
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    have hctx : S.canon (setE (kill .replace false y Γa) y { Ey with live := false, dtor := false }) =
        setE (kill .replace false (S.ρ y) (S.canon Γa)) (S.ρ y)
          { S.subE (S.liftE y Ey) with live := false, dtor := false } := by
      rw [canon_setEs h _ hpy, canon_kill h hab (allowed_own hab hy hm _ _) hpy (hab.notReg hy (by rw [hm]; simp)), liftE_moved _ hrb]; rfl
    rw [hctx]
    exact ⟨_, RhsT.taker hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_mode, liftE_mode y hrb, hm]; rfl)
      (by rw [subE_ty, liftE_ty' h hab hy]; exact hty) (h.Fcout y) (NoPin.lift h hab (bnd_own hab hy hm))
      (DtorSafe.canon h (allowed_own hab hy hm _ _) hds),
      fun x => by rw [S.compE_subE]; exact S.subE_weaker (compE_lift h hab hy b x)⟩
  | @arcNew t y Ey Γa1 D hy hly hty hvd hpl hpc hng hpa =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc1 := canon_some h hy hpy
    obtain ⟨D1, hp1, _, _⟩ := pushArg_rens h hab hy hpy hpa
    have hty1 := liftE_ty' h hab hy
    refine ⟨_, RhsT.arcNew hc1 (by rw [subE_live, liftE_live]; exact hly) (by rw [subE_ty, hty1]; exact hty)
      hvd hpl hpc hng hp1,
      fun x => S.subE_weaker (E := ⟨.arc t, .own, true, [], [], false, false, false, false⟩) ?_⟩
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp)
  | @lockNew t y Ey Γa1 D hy hly hty hvd hpl hng hpa =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc1 := canon_some h hy hpy
    obtain ⟨D1, hp1, _, _⟩ := pushArg_rens h hab hy hpy hpa
    have hty1 := liftE_ty' h hab hy
    refine ⟨_, RhsT.lockNew hc1 (by rw [subE_live, liftE_live]; exact hly) (by rw [subE_ty, hty1]; exact hty)
      hvd hpl hng hp1,
      fun x => S.subE_weaker (E := ⟨.lk t, .own, true, [], [], false, false, false, false⟩) ?_⟩
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp)
  | @arcClone a Ea t ha hl ht =>
    have hpv : S.isPi a = false := hvs a (by simp [Rhs.vars])
    have hc := canon_some h ha hpv
    refine ⟨_, RhsT.arcClone hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab ha]; exact ht),
      fun x => S.subE_weaker (E := ⟨.arc t, .own, true, [], [], false, false, false, false⟩) ?_⟩
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp)
  | @atomic op a e1 e2 Ea ha hl ht he1 he2 =>
    have hpv : S.isPi a = false := hvs a (by simp [Rhs.vars])
    have hc := canon_some h ha hpv
    exact ⟨intE, RhsT.atomic hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab ha]; exact ht)
      (exprT_ren h hab he1 (fun v hv => hvs v (by simp [Rhs.vars, hv])))
      (exprT_ren h hab he2 (fun v hv => hvs v (by simp [Rhs.vars, hv]))), fun x => S.subE_weaker (intE_lift x)⟩
  | @chanSend a y Ea Ey s Γa1 D ha hl ht hy hly htyy hpa =>
    have hpv : S.isPi a = false := hvs a (by simp [Rhs.vars])
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hca := canon_some h ha hpv
    have hc1 := canon_some h hy hpy
    obtain ⟨D1, hp1, _, _⟩ := pushArg_rens h hab hy hpy hpa
    exact ⟨intE, RhsT.chanSend hca (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab ha]; exact ht)
      hc1 (by rw [subE_live, liftE_live]; exact hly) (by rw [subE_ty, liftE_ty' h hab hy]; exact htyy) hp1,
      fun x => S.subE_weaker (intE_lift x)⟩
  | @chanRecv w a Ea s ha hl ht =>
    have hpv : S.isPi a = false := hvs a (by simp [Rhs.vars])
    have hc := canon_some h ha hpv
    refine ⟨_, RhsT.chanRecv hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab ha]; exact ht),
      fun x => S.subE_weaker (E := ⟨.sum .int s, .own, true, [], [], false, false, false, false⟩) ?_⟩
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp)
  | @chanClose a Ea s ha hl ht =>
    have hpv : S.isPi a = false := hvs a (by simp [Rhs.vars])
    have hc := canon_some h ha hpv
    exact ⟨intE, RhsT.chanClose hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab ha]; exact ht),
      fun x => S.subE_weaker (intE_lift x)⟩
  | @lockTake a Ea t ha hl ht =>
    have hpv : S.isPi a = false := hvs a (by simp [Rhs.vars])
    have hc := canon_some h ha hpv
    exact ⟨_, RhsT.lockTake hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab ha]; exact ht),
      fun x => by have := S.subE_weaker (S.lockE_lift x t); rwa [subE_lockE] at this⟩
  | @lockRestore a y Ea Ey t Γa1 D ha hl ht hy hly htyy hpa =>
    have hpv : S.isPi a = false := hvs a (by simp [Rhs.vars])
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hca := canon_some h ha hpv
    have hc1 := canon_some h hy hpy
    obtain ⟨D1, hp1, _, _⟩ := pushArg_rens h hab hy hpy hpa
    exact ⟨intE, RhsT.lockRestore hca (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab ha]; exact ht)
      hc1 (by rw [subE_live, liftE_live]; exact hly) (by rw [subE_ty, liftE_ty' h hab hy]; exact htyy) hp1,
      fun x => S.subE_weaker (intE_lift x)⟩
  | @lockClone a Ea t ha hl ht =>
    have hpv : S.isPi a = false := hvs a (by simp [Rhs.vars])
    have hc := canon_some h ha hpv
    refine ⟨_, RhsT.lockClone hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab ha]; exact ht),
      fun x => S.subE_weaker (E := ⟨.lk t, .own, true, [], [], false, false, false, false⟩) ?_⟩
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp)
  | @cellNew t y Ey Γa1 D hy hly hty hvd hpl hng hpa =>
    have hpy : S.isPi y = false := hvs y (by simp [Rhs.vars])
    have hc1 := canon_some h hy hpy
    obtain ⟨D1, hp1, _, _⟩ := pushArg_rens h hab hy hpy hpa
    have hty1 := liftE_ty' h hab hy
    refine ⟨_, RhsT.cellNew hc1 (by rw [subE_live, liftE_live]; exact hly) (by rw [subE_ty, hty1]; exact hty)
      hvd hpl hng hp1,
      fun x => S.subE_weaker (E := ⟨.cell t, .own, true, [], [], false, false, false, false⟩) ?_⟩
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp)
  | @cellClone a Ea t ha hl ht =>
    have hpv : S.isPi a = false := hvs a (by simp [Rhs.vars])
    have hc := canon_some h ha hpv
    refine ⟨_, RhsT.cellClone hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab ha]; exact ht),
      fun x => S.subE_weaker (E := ⟨.cell t, .own, true, [], [], false, false, false, false⟩) ?_⟩
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp)
  | @glob g t hsy htok =>
    refine ⟨_, RhsT.glob hsy htok,
      fun x => S.subE_weaker (E := ⟨t, .own, true, [], [], false, false, false, false⟩) ?_⟩
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp)
  | @rwRead a Ea t ha hl ht hnc =>
    have hpv : S.isPi a = false := hvs a (by simp [Rhs.vars])
    have hc := canon_some h ha hpv
    refine ⟨_, RhsT.rwRead hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab ha]; exact ht) hnc,
      fun x => S.subE_weaker (E := ⟨.rguard t, .own, true, [], [], false, false, false, false⟩) ?_⟩
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp)
  | @rwTryRead a Ea t ha hl ht hnc =>
    have hpv : S.isPi a = false := hvs a (by simp [Rhs.vars])
    have hc := canon_some h ha hpv
    refine ⟨_, RhsT.rwTryRead hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab ha]; exact ht) hnc,
      fun x => S.subE_weaker (E := ⟨.sum .int (.rguard t), .own, true, [], [], false, false, false, false⟩) ?_⟩
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp)
  | @rwTryWrite a Ea t ha hl ht =>
    have hpv : S.isPi a = false := hvs a (by simp [Rhs.vars])
    have hc := canon_some h ha hpv
    refine ⟨_, RhsT.rwTryWrite hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab ha]; exact ht),
      fun x => S.subE_weaker (E := ⟨.sum .int .int, .own, true, [], [], false, false, false, false⟩) ?_⟩
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp)
  | @arcGet a Ea t ha hl ht hhv hfn =>
    have hpv : S.isPi a = false := hvs a (by simp [Rhs.vars])
    have hc := canon_some h ha hpv
    exact ⟨_, RhsT.arcGet hc (by rw [subE_live, liftE_live]; exact hl) (by rw [subE_ty, liftE_ty' h hab ha]; exact ht) hhv hfn,
      fun x => (S.getE_subE h hpv _ t).trans (S.subE_weaker (getE_lift h hab ha t x))⟩

theorem mem_allKinds_iff {L : List Var} {d : Dep} : d ∈ allKinds L ↔ d.root ∈ L ∧ d.kind.isName = false := by
  constructor
  · intro h
    refine ⟨mem_allKinds h, ?_⟩
    simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil,
      or_false] at h
    obtain ⟨r, _, h⟩ := h
    rcases h with rfl | rfl | rfl | rfl <;> rfl
  · intro ⟨hd, hk⟩
    simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil, or_false]
    exact ⟨d.root, hd, by obtain ⟨r, k⟩ := d; cases k <;> simp_all [Kind.isName]⟩

/-- Pointwise: each entry of `Γ` is at least as strong as `Γ'`'s. -/
def PW (Γ Γ' : Ctx) : Prop :=
  ∀ v, (Γ v = none ↔ Γ' v = none) ∧ ∀ E E', Γ v = some E → Γ' v = some E' → EntryWeaker E E'

theorem PW.weaker {Γ Γ' : Ctx} (h : PW Γ Γ') (hw : CtxWF Γ') (hn : NameWF Γ') : Weaker Γ Γ' := ⟨h, hw, hn⟩

theorem PW.refl (Γ : Ctx) : PW Γ Γ := fun v => ⟨Iff.rfl, fun E E' h1 h2 => by
  rw [h1] at h2; cases h2; exact EntryWeaker.refl _⟩

theorem PW.kill {Γ Γ' : Ctx} (h : PW Γ Γ') (e : Eff) (hv : Bool) (x : Var) :
    PW (A2.kill e hv x Γ) (A2.kill e hv x Γ') := by
  intro v
  refine ⟨?_, fun E E' h1 h2 => ?_⟩
  · simp only [A2.kill, Option.map_eq_none_iff]; exact (h v).1
  · simp only [A2.kill] at h1 h2
    cases hE : Γ v with
    | none => rw [hE] at h1; cases h1
    | some E0 =>
      cases hE' : Γ' v with
      | none => rw [hE'] at h2; cases h2
      | some E0' =>
        rw [hE] at h1; rw [hE'] at h2; cases h1; cases h2
        exact killE_weaker ((h v).2 E0 E0' hE hE')

theorem PW.setE {Γ Γ' : Ctx} (h : PW Γ Γ') {x : Var} {E E' : Entry} (he : EntryWeaker E E') :
    PW (A2.setE Γ x E) (A2.setE Γ' x E') := by
  intro v
  by_cases hvx : v = x
  · subst hvx; simp only [A2.setE, upd_same, reduceCtorEq, iff_self, Option.some.injEq, true_and]
    intro a b ha hb; subst ha hb; exact he
  · simp only [A2.setE, upd_ne _ _ hvx]; exact h v

theorem getD_mem' {args : List Var} {i : Nat} (hi : i < args.length) : args.getD i 0 ∈ args := by
  simp only [List.getD, List.getElem?_eq_getElem hi, Option.getD_some]; exact List.getElem_mem hi

theorem getD_map {args : List Var} {i : Nat} (hi : i < args.length) (ρ : Var → Var) :
    (args.map ρ).getD i 0 = ρ (args.getD i 0) := by
  simp [List.getD, hi]

/-- AGORA-937: ... with regions: an argument at no region's index is its
    binding lifted, then substituted. -/
theorem argE_canons (h : S.OK) {a : Var} {Ea : Entry} (ha : Γa a = some Ea) (hnp : S.isPi a = false) :
    argE (S.canon Γa) (S.ρ a) = S.subE (S.liftE a Ea) := by
  unfold argE; rw [canon_some h ha hnp]; rfl

/-- AGORA-937: with no memory frozen (`S.R = []`), what a region stands for
    is nothing, so the substitution only drops what depends on a region. -/
theorem mem_subE_held_of_R (h : S.OK) (hR : S.R = []) {X : Entry} {d : Dep} (hd : d ∈ (S.subE X).held) :
    d ∈ X.held := by
  rw [subE_held] at hd
  obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp hd
  rcases S.mem_subD hde with rfl | ⟨v, _, _, hσ⟩
  · exact he
  · have := hσ.sub h; rw [hR] at this; simp [allKinds] at this

/-- AGORA-937 (turn-on 3): a lifted dependency on a region stands for what
    the region stands for, or is dropped (a name). -/
theorem mem_subD_pi {S : RSetup} (h : S.OK) {w : Var} {k : Kind} {e : Dep} (hp : S.isPi w = true)
    (he : e ∈ S.subD ⟨S.ρ w, k⟩) : S.σC w k e := by
  unfold subD at he
  simp only [inv_ρ h, hp, ↓reduceIte] at he
  cases hk : k.isName <;> simp only [hk, Bool.false_eq_true, ↓reduceIte, List.not_mem_nil, List.mem_map] at he
  obtain ⟨e0, he0, rfl⟩ := he
  exact ⟨e0, he0, rfl, hk⟩

/-- AGORA-937 (agora #4147): no name is on a region. A live binding that may
    hold memory names only roots that own their slot (`NameWF`), and a region
    does not. -/
theorem no_name_on_region (hab : S.AbsOK Γa) (hnw : NameWF Γa) {v : Var} {E : Entry}
    (hE : Γa v = some E) (hl : E.live = true) (hnn : E.ty ≠ .int ∨ E.mode = .rootb) {d : Dep}
    (hd : d ∈ E.vdeps) (hk : d.kind.isName = true) : S.isPi d.root = false := by
  cases hkd : d.kind with
  | name b t =>
    obtain ⟨Er, hEr, _, _, _, ho, _⟩ := hnw v E hE hl hnn d hd b t hkd
    exact hab.notPi hEr (fun e => by rw [e] at ho; cases ho)
  | _ => simp [hkd, Kind.isName] at hk

/-- ... so neither is a name on a live borrow's path, of a type that may
    hold memory. -/
theorem path_names_not_region (hab : S.AbsOK Γa) (hnw : NameWF Γa) {v : Var} {E : Entry}
    (hE : Γa v = some E) (hl : E.live = true) (hmb : E.mode = .bor) (hni : E.ty ≠ .int) :
    ∀ d ∈ E.path, d.kind.isName = true → S.isPi d.root = false := fun d hd hk =>
  no_name_on_region hab hnw hE hl (Or.inl hni) (by simp [Entry.vdeps, hmb, Mode.ownSlot, hd]) hk

/-- AGORA-927: an argument whose dependencies are all bindings' keeps them so
    under the renaming: a renamed one is the renamed binding's, and what a
    lift adds is the caller's frame's. AGORA-937, with regions, for an
    argument at no region's index: a kept dependency is on no region (one on
    a region was replaced or, a name, dropped, `subD_kept`), so the renamed
    binding's, and one a region stood for is the frame's. -/
theorem argE_canon_rooted (h : S.OK) (hab : S.AbsOK Γa) {a : Var} (hnp : S.isPi a = false)
    (hr : ∀ d ∈ (argE Γa a).vdeps, (Γa d.root).isSome) :
    ∀ d ∈ (argE (S.canon Γa) (S.ρ a)).vdeps, (S.canon Γa d.root).isSome := by
  intro d hd
  cases ha : Γa a with
  | none =>
    unfold argE at hd; rw [canon_ρs h _ hnp, ha] at hd
    simp [intE, Entry.vdeps, Mode.ownSlot] at hd
  | some Ea =>
    have hr : ∀ d ∈ Ea.vdeps, (Γa d.root).isSome := by unfold argE at hr; rw [ha] at hr; exact hr
    rw [argE_canons h ha hnp, subE_vdeps] at hd
    obtain ⟨d1, hd1, hdd⟩ := List.mem_flatMap.mp hd
    rcases S.mem_subD hdd with rfl | ⟨v, _, _, hσ⟩
    · by_cases hrb : Ea.mode = .rootb
      · have hsym : ∀ {d : Dep}, d ∈ rds S.ρ S.sym → (S.canon Γa d.root).isSome = true := by
          intro d hs
          obtain ⟨w, b, t, rfl, hb, _, _, _⟩ := sym_ren h hs
          obtain ⟨Ew, hEw, hm, _⟩ := hab.2.2.1 w (b, false) hb
          show (S.canon Γa (S.ρ w)).isSome = true
          rw [canon_some h hEw (hab.notPi hEw (by rw [hm]; simp))]; rfl
        rcases liftE_rootb_dep h hab ha hrb hd1 with hd1 | ⟨u, rfl, hreg, _⟩
        · rcases pe_dep h hd1 with ⟨hout, hex⟩ | ⟨hs, _⟩
          · obtain ⟨E', hE', _⟩ := canon_frameRoot (Γa := Γa) h hout hex
            rw [hE']; rfl
          · exact hsym hs
        · obtain ⟨Eu, hEu, _⟩ := hab.2.2.2.2.1 u hreg
          have hp : S.isPi u = false := subD_kept h hdd rfl
          show (S.canon Γa (S.ρ u)).isSome = true; rw [canon_some h hEu hp]; rfl
      · rcases liftE_vdeps_cases hrb hd1 with ⟨d0, hd0, rfl⟩ | hA
        · have hp : S.isPi d0.root = false := subD_kept h hdd rfl
          have := hr d0 hd0
          cases h0 : Γa d0.root with
          | none => rw [h0] at this; cases this
          | some E0 => show (S.canon Γa (S.ρ d0.root)).isSome = true; rw [canon_some h h0 hp]; rfl
        · obtain ⟨E', hE', _⟩ := canon_frameRoot (Γa := Γa) h (A_out h hA) (A_root h hA)
          rw [hE']; rfl
    · obtain ⟨hout, hex⟩ := S.σ_frameC h hσ
      obtain ⟨E', hE', _⟩ := canon_frameRoot (Γa := Γa) h hout hex
      rw [hE']; rfl

theorem sub_rds_append {a b : List Dep} {L : List Dep} (ha : a ⊆ rds S.ρ L ++ S.A)
    (hb : b ⊆ rds S.ρ L ++ S.A) : a ++ b ⊆ rds S.ρ L ++ S.A := by
  intro d hd; rcases List.mem_append.mp hd with h | h
  · exact ha h
  · exact hb h

theorem sub_mono {a L L' : List Dep} (ha : a ⊆ rds S.ρ L ++ S.A) (hL : L ⊆ L') :
    a ⊆ rds S.ρ L' ++ S.A :=
  fun _ hd => append_sub (rds_subset hL) (List.Subset.refl _) (ha hd)

/-- AGORA-937: a substituted dependency is kept, or something the arguments
    held (what a region stands for). -/
theorem mem_subD_A (h : S.OK) {d e : Dep} (he : e ∈ S.subD d) : e = d ∨ e ∈ S.B := by
  rcases S.mem_subD he with rfl | ⟨v, _, _, hσ⟩
  · exact Or.inl rfl
  · obtain ⟨e0, he0, rfl, hk⟩ := hσ
    exact Or.inr (mem_B.mpr (Or.inl (mem_compAll.mpr ⟨e0, h.σ_Rd _ he0, _, kind4 hk, rfl⟩)))

/-- AGORA-937: what a substituted entry depends on, it depended on, or the
    arguments hold it. -/
theorem mem_subE_vdeps_A (h : S.OK) {L : Entry} {d : Dep} (hd : d ∈ (S.subE L).vdeps) :
    d ∈ L.vdeps ∨ d ∈ S.B := by
  rw [subE_vdeps] at hd
  obtain ⟨d1, hd1, hdd⟩ := List.mem_flatMap.mp hd
  rcases S.mem_subD_A h hdd with rfl | hA
  · exact Or.inl hd1
  · exact Or.inr hA

/-- AGORA-937: a name a substituted entry holds, the entry held: what a region
    stands for holds no name. -/
theorem mem_subE_name (h : S.OK) {L : Entry} {d : Dep} (hd : d ∈ (S.subE L).vdeps)
    (hn : d.kind.isName = true) : d ∈ L.vdeps := by
  rw [subE_vdeps] at hd
  obtain ⟨d1, hd1, hdd⟩ := List.mem_flatMap.mp hd
  rcases S.mem_subD hdd with rfl | ⟨v, _, _, hσ⟩
  · exact hd1
  · have := allKinds_notName (hσ.sub h); rw [hn] at this; cases this

/-- AGORA-937: a name a substituted list holds, the list held. -/
theorem mem_flatMap_subD_name (h : S.OK) {X : List Dep} {d : Dep} (hd : d ∈ X.flatMap S.subD)
    (hn : d.kind.isName = true) : d ∈ X := by
  obtain ⟨d1, hd1, hdd⟩ := List.mem_flatMap.mp hd
  rcases S.mem_subD hdd with rfl | ⟨v, _, _, hσ⟩
  · exact hd1
  · have := allKinds_notName (hσ.sub h); rw [hn] at this; cases this

/-- ... and every name the entry held on no region, it holds (`subD_name`). -/
theorem mem_subE_of_name {L : Entry} {d : Dep} (hd : d ∈ L.vdeps) (hn : d.kind.isName = true)
    (hnp : ∀ v, S.inv d.root = some v → S.isPi v = false) : d ∈ (S.subE L).vdeps := by
  rw [subE_vdeps]
  exact List.mem_flatMap.mpr ⟨d, hd, by rw [S.subD_name hn hnp]; exact List.mem_singleton_self d⟩

/-- AGORA-937: a list of dependencies the substitution keeps, it keeps whole. -/
theorem flatMap_subD_fix {L : List Dep} (hf : ∀ d ∈ L, S.subD d = [d]) : L.flatMap S.subD = L := by
  induction L with
  | nil => rfl
  | cons d L ih =>
    rw [List.flatMap_cons, hf d (List.mem_cons_self ..),
      ih (fun d' hd' => hf d' (List.mem_cons_of_mem _ hd'))]
    rfl

theorem argDeps_lift (h : S.OK) (hab : S.AbsOK Γa) {args : List Var} {j : Nat} (hj : j < args.length)
    {Ea : Entry} (hEa : Γa (args.getD j 0) = some Ea) (hnp : S.isPi (args.getD j 0) = false)
    (k : Kind) (hk : k.isName = false) :
    argDeps (S.canon Γa) (args.map S.ρ) (j, k) ⊆ (rds S.ρ (argDeps Γa args (j, k)) ++ S.A).flatMap S.subD := by
  unfold argDeps
  simp only [getD_map hj, argE_canons h hEa hnp, subE_ty, liftE_ty' h hab hEa]
  have hae : argE Γa (args.getD j 0) = Ea := by unfold argE; rw [hEa]; rfl
  rw [hae]
  split
  · simp
  · -- AGORA-937 (3d): what a region stands for comes back by the substitution
    intro d hd
    obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp (derive_subE h hnp _ hk hd)
    exact List.mem_flatMap.mpr ⟨e, derive_lift h hab hEa k hk he, hde⟩

theorem vdeps_sub {E E' : Entry} (hw : EntryWeaker E E') (hl : E'.live = true) : E.vdeps ⊆ E'.vdeps := by
  obtain ⟨_, hm, _, hlv⟩ := hw
  obtain ⟨_, hp, hh⟩ := hlv hl
  unfold Entry.vdeps; rw [hm]
  cases ho : E.mode.ownSlot with
  | true => exact append_sub (List.Subset.refl _) hh
  | false => exact append_sub (hp ho) hh


/-- What a borrowed parameter depends on in the callee: the symbolic names
    of the `inout` parameters, when its type may hold a closure. -/
theorem vdeps_rootb (hab : S.AbsOK Γa) {a : Var} {Ea : Entry} (hEa : Γa a = some Ea)
    (hrb : Ea.mode = .rootb) :
    ∃ R, S.RegViews R ∧ Ea.vdeps = R ++ (if (S.pe a).ty.hasFn then S.sym else []) := by
  obtain ⟨hty, hp, R, hR, hh⟩ := hab.1 a Ea hEa hrb
  exact ⟨R, hR, by
    simp only [Entry.vdeps, hp, hh, hrb, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte, List.nil_append, hty]⟩

/-- A borrowed parameter's abstract entry holds the symbolic name of an
    `inout` parameter whenever its type may hold a closure. -/
theorem abs_sym (hab : S.AbsOK Γa) {a : Var} {Ea : Entry} (hEa : Γa a = some Ea) (hrb : Ea.mode = .rootb)
    (hf : (S.pe a).ty.hasFn = true) {d : Dep} (hd : d ∈ S.sym) : d ∈ Ea.vdeps := by
  obtain ⟨R, _, hv⟩ := vdeps_rootb hab hEa hrb
  rw [hv, hf]; simp [hd]

/-- What a lifted binding holds by name: what the binding it lifts does, or
    what the arguments do. -/
theorem names_liftE (h : S.OK) (hab : S.AbsOK Γa) {a : Var} {Ea : Entry} (hEa : Γa a = some Ea) {d : Dep}
    (hd : d ∈ (S.liftE a Ea).vdeps) (hn : d.kind.isName = true) :
    (∃ d0 ∈ Ea.vdeps, d = d0.ren S.ρ) ∨ d ∈ S.N := by
  by_cases hrb : Ea.mode = .rootb
  · rcases liftE_rootb_dep h hab hEa hrb hd with hd | ⟨u, rfl, _, _⟩
    · rcases h.pe_names a d hd hn with hN | ⟨hs, hf⟩
      · exact Or.inr hN
      · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hs
        exact Or.inl ⟨d0, abs_sym hab hEa hrb hf hd0, rfl⟩
    · simp [Kind.isName] at hn
  · rcases liftE_vdeps_cases hrb hd with h1 | h1
    · exact Or.inl h1
    · rcases S.mem_A_ak h h1 with h2 | h2
      · rw [allKinds_notName h2] at hn; cases hn
      · exact Or.inr h2

/-- Every argument of a well-typed call is bound. -/
theorem CallT.args_some {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    (hc : CallT P Γ F f args E Γ1) : ∀ a ∈ args, ∃ Ea, Γ a = some Ea := by
  obtain ⟨fn, _, hlen, hargs, _⟩ := hc
  intro a ha
  obtain ⟨i, hi, rfl⟩ := mem_args ha
  obtain ⟨Ea, hEa, _⟩ := hargs i (hlen ▸ hi)
  exact ⟨Ea, hEa⟩

/-- AGORA-937 (agora #4191): no region is ever changed by name. A kill by
    name (`killNames` of what a closure handed to a call may change,
    `mutNames`) targets a root the call may change (`NamesFree`): one that
    owns its slot, so no region (`AbsOK`). So a name on a region ends
    nothing, and the lift's substitution drops it (`subD`). -/
theorem name_kill_not_region (hab : S.AbsOK Γa) {F : List Var} {ps : List (PMode × Ty)}
    {args : List Var} (hnf : NamesFree Γa F ps args) :
    ∀ d ∈ mutNames Γa args, S.isPi d.root = false := by
  intro d hd
  obtain ⟨hcan, _⟩ := hnf d hd
  cases hE : Γa d.root with
  | none => exact hab.notPiFresh hE
  | some E0 =>
    have hae : argE Γa d.root = E0 := by unfold argE; rw [hE]; rfl
    rw [hae] at hcan
    exact hab.notPi hE (by rcases hcan with hm | ⟨b, hm, _⟩ <;> rw [hm] <;> simp)

theorem name_kill_notReg (hab : S.AbsOK Γa) {F : List Var} {ps : List (PMode × Ty)}
    {args : List Var} (hnf : NamesFree Γa F ps args) :
    ∀ d ∈ mutNames Γa args, S.isReg d.root = false := by
  intro d hd
  obtain ⟨hcan, _⟩ := hnf d hd
  cases hE : Γa d.root with
  | none => exact hab.notRegFresh hE
  | some E0 =>
    have hae : argE Γa d.root = E0 := by unfold argE; rw [hE]; rfl
    rw [hae] at hcan
    exact hab.notReg hE (by rcases hcan with hm | ⟨b, hm, _⟩ <;> rw [hm] <;> simp)

/-- What a closure handed to a call in the callee may change, where the call
    places it: what it may change in the callee, or what the arguments'
    closures may. -/
theorem mem_mutNames_canon (h : S.OK) (hab : S.AbsOK Γa) {args : List Var}
    (hargs : ∀ a ∈ args, ∃ Ea, Γa a = some Ea) (hvs : ∀ a ∈ args, S.isPi a = false) {d : Dep}
    (hd : d ∈ mutNames (S.canon Γa) (args.map S.ρ)) :
    d ∈ rds S.ρ (mutNames Γa args) ∨ (d ∈ S.N ∧ d.kind.bound ≠ .none) := by
  unfold mutNames at hd ⊢
  obtain ⟨hd, hb⟩ := List.mem_filter.mp hd
  simp only [argNames, List.flatMap_map, List.mem_flatMap] at hd
  obtain ⟨a, ha, hda⟩ := hd
  obtain ⟨Ea, hEa⟩ := hargs a ha
  rw [argE_canons h hEa (hvs a ha), subE_ty, liftE_ty' h hab hEa] at hda
  have hae : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
  split at hda
  · simp at hda
  · rename_i hn
    obtain ⟨hdv, hdn⟩ := List.mem_filter.mp hda
    rcases names_liftE h hab hEa (S.mem_subE_name h hdv hdn) hdn with ⟨d0, hd0, rfl⟩ | hN
    · refine Or.inl (mem_rds.mpr ⟨d0, List.mem_filter.mpr ⟨?_, hb⟩, rfl⟩)
      simp only [argNames, List.mem_flatMap]
      exact ⟨a, ha, by rw [hae, ite_eq_right hn]; exact List.mem_filter.mpr ⟨hd0, hdn⟩⟩
    · exact Or.inr ⟨hN, by simpa using hb⟩

/-- What a closure the callee hands to a call may change, where the call
    places it: a closure the renamed call hands over may change it too, or
    it is an `inout` argument the callee's symbolic name stands for (which
    the closure handed over may or may not hold). -/
theorem mutNames_canon_sub (h : S.OK) (hab : S.AbsOK Γa) {F : List Var} {ps : List (PMode × Ty)}
    {args : List Var} (hnf : NamesFree Γa F ps args)
    (hargs : ∀ a ∈ args, ∃ Ea, Γa a = some Ea) (hvs : ∀ a ∈ args, S.isPi a = false) :
    ∀ d ∈ rds S.ρ (mutNames Γa args), d ∈ mutNames (S.canon Γa) (args.map S.ρ) ∨
      ∃ w b t, d = ⟨S.ρ w, .name b t⟩ ∧ S.bnd w = some (b, false) ∧ b ≠ .replace := by
  intro d hd
  obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
  have hnp0 := name_kill_not_region hab hnf d0 hd0
  unfold mutNames at hd0 ⊢
  obtain ⟨hd0, hb⟩ := List.mem_filter.mp hd0
  simp only [argNames, List.mem_flatMap] at hd0
  obtain ⟨a, ha, hda⟩ := hd0
  obtain ⟨Ea, hEa⟩ := hargs a ha
  have hae : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
  rw [hae] at hda
  split at hda
  · simp at hda
  · rename_i hn
    obtain ⟨hdv, hdn⟩ := List.mem_filter.mp hda
    by_cases hrb : Ea.mode = .rootb
    · -- a symbolic name
      have hs : d0 ∈ S.sym := by
        obtain ⟨R, hR, hv⟩ := vdeps_rootb hab hEa hrb
        rw [hv] at hdv
        rcases List.mem_append.mp hdv with hdv | hdv
        · -- AGORA-937 (item 2): a view of a region is no name
          have hk := (hR d0 hdv).1
          rw [hk] at hdn; simp [Kind.isName] at hdn
        · split at hdv
          · exact hdv
          · cases hdv
      obtain ⟨w, b, t, rfl, hbw, _, _, hbr⟩ := h.sym_ok d0 hs
      exact Or.inr ⟨w, b, t, rfl, hbw, hbr⟩
    · refine Or.inl (List.mem_filter.mpr ⟨?_, hb⟩)
      simp only [argNames, List.flatMap_map, List.mem_flatMap]
      refine ⟨a, ha, ?_⟩
      rw [argE_canons h hEa (hvs a ha), subE_ty, liftE_ty' h hab hEa, ite_eq_right hn]
      exact List.mem_filter.mpr ⟨S.mem_subE_of_name ((mem_liftE_vdeps hrb).mpr (Or.inl ⟨d0, hdv, rfl⟩))
        (by simpa [Dep.ren] using hdn) (fun v hv => by
          simp only [Dep.ren, inv_ρ h, Option.some.injEq] at hv; subst hv; exact hnp0), hdn⟩

theorem kills_isName {e : Eff} (he : e ≠ .replace) (hv : Bool) {k : Kind} (hk : k.isName = true) :
    e.kills hv k = false := by
  cases k with
  | name b t => cases e <;> simp_all [Eff.kills]
  | _ => simp [Kind.isName] at hk

theorem isName_of_bound {k : Kind} (h : k.bound ≠ .none) : k.isName = true := by
  cases k <;> simp_all [Kind.bound, Kind.isName]

theorem N_bound (h : S.OK) {d : Dep} (hd : d ∈ S.N) (hb : d.kind.bound ≠ .none) :
    d.kind.bound ≠ .replace := by
  have hn := h.N_name d hd
  obtain ⟨r, k⟩ := d
  cases k with
  | name b t =>
    obtain ⟨_, _, _, _, _, _, hc, _⟩ := h.N_named _ hd b t rfl
    rcases hc with hc | ⟨hc, _⟩
    · exact absurd hc hb
    · exact hc
  | _ => simp [Kind.isName] at hn

/-- What the arguments' closures may change ends nothing the call can see:
    the frame has ended it already, and nothing else reaches it but by name. -/
theorem canon_quiet (h : S.OK) (_hab : S.AbsOK Γa) {d : Dep} (hd : d ∈ S.N) (hb : d.kind.bound ≠ .none) :
    ∀ v E, S.canon Γa v = some E → E.live = true → hits d.kind.bound false d.root E = false := by
  obtain ⟨_, hR, _, hpe, _, hΦ⟩ := h.N_mut d hd hb
  have hbr := N_bound h hd hb
  intro y E hy hl
  rcases canon_cases_sub h Γa y with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨_, hc⟩
  · rw [hc] at hy
    cases hE : Γa v with
    | none => rw [hE] at hy; cases hy
    | some E0 =>
      rw [hE] at hy; simp only [Option.map_some, Option.some.injEq, Function.comp] at hy; subst hy
      refine hits_false_of fun d' hd' hdr => ?_
      rcases S.mem_subE_vdeps_A h hd' with hd' | ha
      case inr =>
        rcases S.mem_B_ak h ha with ha | ha
        · exact absurd (hdr ▸ mem_allKinds ha) hR
        · exact kills_isName hbr false (h.N_name d' ha)
      by_cases hrb : E0.mode = .rootb
      · rcases liftE_rootb_dep h _hab hE hrb hd' with hd' | ⟨u, rfl, _, _⟩
        · exact kills_isName hbr false (isName_of_bound (by rw [hpe v d' hd' hdr]; exact hb))
        · exact absurd hdr ((h.N_out d hd).1 u)
      · rcases liftE_vdeps_cases hrb hd' with ⟨d0, _, rfl⟩ | ha
        · exact absurd hdr ((h.N_out d hd).1 d0.root)
        · rcases S.mem_A_ak h ha with ha | ha
          · exact absurd (hdr ▸ mem_allKinds ha) hR
          · exact kills_isName hbr false (h.N_name d' ha)
  · rw [hc] at hy; cases hy
  · rw [hc] at hy; exact hΦ y E hy hl

/-- The kills `ds` leave one binding (in any order). -/
def killAll (ds : List Dep) (E : Entry) : Entry :=
  if ds.any (fun d => hits d.kind.bound false d.root E) then { E with live := false } else E

theorem hits_live (e : Eff) (hv : Bool) (x : Var) (E : Entry) (l : Bool) :
    hits e hv x { E with live := l } = hits e hv x E := rfl

theorem killE_killAll (d : Dep) (ds : List Dep) (E : Entry) :
    killE d.kind.bound false d.root (killAll ds E) = killAll (d :: ds) E := by
  have hh : hits d.kind.bound false d.root (killAll ds E) = hits d.kind.bound false d.root E := by
    unfold killAll; split <;> rfl
  unfold killE; rw [hh]
  unfold killAll
  simp only [List.any_cons]
  by_cases h1 : ds.any (fun d => hits d.kind.bound false d.root E) = true <;>
  by_cases h2 : hits d.kind.bound false d.root E = true <;> simp [h1, h2]

theorem killNames_eq : ∀ (ds : List Dep) (Γ : Ctx) (v : Var),
    A2.killNames ds Γ v = (Γ v).map (killAll ds)
  | [], Γ, v => by
    cases h : Γ v <;> simp [A2.killNames, killAll, h]
  | d :: ds, Γ, v => by
    show A2.kill _ _ _ (A2.killNames ds Γ) v = _
    simp only [A2.kill, killNames_eq ds Γ v, Option.map_map]
    cases Γ v with
    | none => rfl
    | some E =>
      simp only [Option.map_some, Function.comp, Option.some.injEq]
      exact killE_killAll d ds E

theorem hits_mono {e : Eff} {hv : Bool} {x : Var} {E E' : Entry} (hw : EntryWeaker E E')
    (hl : E'.live = true) (hh : hits e hv x E = true) : hits e hv x E' = true := by
  unfold hits at hh ⊢
  rw [hw.1, hw.mode]
  simp only [Bool.and_eq_true] at hh ⊢
  refine ⟨hh.1, ?_⟩
  obtain ⟨d, hd, hdd⟩ := List.any_eq_true.mp hh.2
  exact List.any_eq_true.mpr ⟨d, vdeps_sub hw hl hd, hdd⟩

theorem killAll_weaker {M ds : List Dep} {E E' : Entry} (hw : EntryWeaker E E')
    (hds : ∀ d ∈ ds, d ∈ M ∨ (E.fixed → E.live = true → hits d.kind.bound false d.root E = false))
    (hM : ∀ d ∈ M, d ∈ ds ∨ (E'.live = true → hits d.kind.bound false d.root E' = false)) :
    EntryWeaker (killAll M E) (killAll ds E') := by
  have hkM : ∀ {E0 : Entry}, (killAll M E0).ty = E0.ty ∧ (killAll M E0).mode = E0.mode ∧
      (killAll M E0).path = E0.path ∧ (killAll M E0).held = E0.held := by
    intro E0; unfold killAll; split <;> exact ⟨rfl, rfl, rfl, rfl⟩
  have hkd : ∀ {E0 : Entry}, (killAll ds E0).ty = E0.ty ∧ (killAll ds E0).mode = E0.mode ∧
      (killAll ds E0).path = E0.path ∧ (killAll ds E0).held = E0.held := by
    intro E0; unfold killAll; split <;> exact ⟨rfl, rfl, rfl, rfl⟩
  -- a live `E'` no kill of `ds` hits: no kill of `M` hits `E`
  have hnoM : E'.live = true → ds.any (fun d => hits d.kind.bound false d.root E') = false →
      M.any (fun d => hits d.kind.bound false d.root E) = false := by
    intro hl hn
    cases h1 : M.any (fun d => hits d.kind.bound false d.root E) with
    | false => rfl
    | true =>
      obtain ⟨d, hd, hh⟩ := List.any_eq_true.mp h1
      have hh' := hits_mono hw hl hh
      rcases hM d hd with hd' | hq
      · have : ds.any (fun d => hits d.kind.bound false d.root E') = true :=
          List.any_eq_true.mpr ⟨d, hd', hh'⟩
        rw [hn] at this; cases this
      · rw [hq hl] at hh'; cases hh'
  by_cases hrb : E.fixed
  · have he := hw.fixed hrb
    rw [he] at hnoM ⊢
    -- the same entry: `M` and `ds` hit it alike
    have hsame : killAll M E = killAll ds E := by
      cases hl : E.live with
      | false =>
        unfold killAll; split <;> split <;> first | rfl | (cases E; simp_all)
      | true =>
        cases hn : ds.any (fun d => hits d.kind.bound false d.root E) with
        | false =>
          unfold killAll; rw [hnoM hl hn, hn]
        | true =>
          obtain ⟨d, hd, hh⟩ := List.any_eq_true.mp hn
          have hm : M.any (fun d => hits d.kind.bound false d.root E) = true := by
            rcases hds d hd with hdM | hq
            · exact List.any_eq_true.mpr ⟨d, hdM, hh⟩
            · rw [hq hrb hl] at hh; cases hh
          unfold killAll; rw [hm, hn]
    rw [hsame]; exact EntryWeaker.refl _
  · refine ⟨by rw [hkd.1, hkM.1, hw.1], by rw [hkd.2.1, hkM.2.1, hw.mode],
      fun e => absurd (by simp only [Entry.fixed_def] at e ⊢; rw [hkM.2.1, hkM.1] at e; exact e) hrb,
      fun hl' => ?_,
      fun h => by
        have hkdt : ∀ {Ms : List Dep} {E0 : Entry}, (killAll Ms E0).dtor = E0.dtor := by
          intro Ms E0; unfold killAll; split <;> rfl
        rw [hkdt] at h ⊢; rw [hkM.2.2.2, hkd.2.2.2]; exact hw.dtor h,
      by
        have hkdb : ∀ {Ms : List Dep} {E0 : Entry}, (killAll Ms E0).dbind = E0.dbind := by
          intro Ms E0; unfold killAll; split <;> rfl
        rw [hkdb, hkdb]; exact hw.dbind,
      fun h => by
        have hkdt : ∀ {Ms : List Dep} {E0 : Entry}, (killAll Ms E0).dtor = E0.dtor := by
          intro Ms E0; unfold killAll; split <;> rfl
        have hkdb : ∀ {Ms : List Dep} {E0 : Entry}, (killAll Ms E0).dbind = E0.dbind := by
          intro Ms E0; unfold killAll; split <;> rfl
        rw [hkdt] at h ⊢; rw [hkdb]; exact hw.raise h,
      fun h hos hn d hnm => by
        have hkdb : ∀ {Ms : List Dep} {E0 : Entry}, (killAll Ms E0).dbind = E0.dbind := by
          intro Ms E0; unfold killAll; split <;> rfl
        rw [hkdb] at h; rw [hkM.2.1] at hos; rw [hkM.1, hkM.2.1] at hn
        rw [hkM.2.2.2, hkd.2.2.2]; exact hw.dheld h hos hn d hnm,
      fun hlv hnt hbm hfr => by
        have hkf : ∀ {Ms : List Dep} {E0 : Entry}, (killAll Ms E0).fresh = E0.fresh := by
          intro Ms E0; unfold killAll; split <;> rfl
        have hkp : ∀ {Ms : List Dep} {E0 : Entry}, (killAll Ms E0).path = E0.path := by
          intro Ms E0; unfold killAll; split <;> rfl
        have hkt : ∀ {Ms : List Dep} {E0 : Entry}, (killAll Ms E0).ty = E0.ty := by
          intro Ms E0; unfold killAll; split <;> rfl
        have hkm : ∀ {Ms : List Dep} {E0 : Entry}, (killAll Ms E0).mode = E0.mode := by
          intro Ms E0; unfold killAll; split <;> rfl
        rw [hkf] at hfr ⊢; rw [hkp, hkp]; rw [hkt] at hnt; rw [hkm] at hbm
        exact hw.fresh (by unfold killAll at hlv; split at hlv <;> simp_all) hnt hbm hfr,
      fun hnt hbm hhf => by
        have hkt : ∀ {Ms : List Dep} {E0 : Entry}, (killAll Ms E0).ty = E0.ty := by
          intro Ms E0; unfold killAll; split <;> rfl
        have hkm : ∀ {Ms : List Dep} {E0 : Entry}, (killAll Ms E0).mode = E0.mode := by
          intro Ms E0; unfold killAll; split <;> rfl
        have hkh : ∀ {Ms : List Dep} {E0 : Entry}, (killAll Ms E0).heldFresh = E0.heldFresh := by
          intro Ms E0; unfold killAll; split <;> rfl
        rw [hkt] at hnt; rw [hkm] at hbm; rw [hkh] at hhf ⊢
        exact hw.heldFresh hnt hbm hhf⟩
    have hl0 : E'.live = true ∧ ds.any (fun d => hits d.kind.bound false d.root E') = false := by
      unfold killAll at hl'; split at hl'
      · simp at hl'
      · rename_i hn; exact ⟨hl', by simpa using hn⟩
    obtain ⟨hlE, hp, hh⟩ := hw.live hl0.1
    refine ⟨?_, fun ho => ?_, ?_⟩
    · unfold killAll; rw [hnoM hl0.1 hl0.2]; exact hlE
    · rw [hkM.2.2.1, hkd.2.2.1]; exact hp (by rw [← hkM.2.1]; exact ho)
    · rw [hkM.2.2.2, hkd.2.2.2]; exact hh

/-- Running more closures, each either among those run on the weaker side or
    ending nothing there, keeps a context as strong. -/
theorem PW.killNames' {X Y : Ctx} (hp : PW X Y) {M ds : List Dep}
    (hds : ∀ d ∈ ds, d ∈ M ∨ ∀ v E, X v = some E → E.fixed → E.live = true →
      hits d.kind.bound false d.root E = false)
    (hM : ∀ d ∈ M, d ∈ ds ∨ ∀ v E, Y v = some E → E.live = true → hits d.kind.bound false d.root E = false) :
    PW (A2.killNames M X) (A2.killNames ds Y) := by
  intro v
  rw [killNames_eq, killNames_eq]
  refine ⟨by simp only [Option.map_eq_none_iff]; exact (hp v).1, fun E E' h1 h2 => ?_⟩
  cases hX : X v with
  | none => rw [hX] at h1; cases h1
  | some E0 =>
    cases hY : Y v with
    | none => rw [hY] at h2; cases h2
    | some E0' =>
      rw [hX] at h1; rw [hY] at h2
      simp only [Option.map_some, Option.some.injEq] at h1 h2; subst h1 h2
      exact killAll_weaker ((hp v).2 E0 E0' hX hY)
        (fun d hd => (hds d hd).imp id (fun hq hf hl => hq v E0 hX hf hl))
        (fun d hd => (hM d hd).imp id (fun hq hl => hq v E0' hY hl))

theorem AbsOK.killNames {Γ : Ctx} (hab : S.AbsOK Γ) : ∀ ds, S.AbsOK (A2.killNames ds Γ)
  | [] => hab
  | _ :: ds => show S.AbsOK (A2.kill _ _ _ (A2.killNames ds Γ)) from (AbsOK.killNames hab ds).kill _ _ _

/-- `canon_killNames` where a kill may be of a region, when it ends no view. -/
theorem canon_killNames' (h : S.OK) {Γ : Ctx} (hab : S.AbsOK Γ) :
    ∀ (ds : List Dep), (∀ d ∈ ds, Allowed S d.kind.bound false d.root) →
      (∀ d ∈ ds, S.isPi d.root = false) →
      (∀ d ∈ ds, S.isReg d.root = false ∨ d.kind.bound.kills false .view = false) →
      S.canon (A2.killNames ds Γ) = A2.killNames (rds S.ρ ds) (S.canon Γ)
  | [], _, _, _ => rfl
  | d :: ds, hal, hnp, hnr => by
    show S.canon (A2.kill _ _ _ (A2.killNames ds Γ)) = A2.kill _ _ _ (A2.killNames (rds S.ρ ds) (S.canon Γ))
    rw [canon_kill' h (hab.killNames ds) (hal d (by simp)) (hnp d (by simp)) (hnr d (by simp)),
      canon_killNames' h hab ds (fun d' hd' => hal d' (by simp [hd'])) (fun d' hd' => hnp d' (by simp [hd']))
        (fun d' hd' => hnr d' (by simp [hd']))]
    rfl

theorem canon_killNames (h : S.OK) {Γ : Ctx} (hab : S.AbsOK Γ) (ds : List Dep)
    (hal : ∀ d ∈ ds, Allowed S d.kind.bound false d.root) (hnp : ∀ d ∈ ds, S.isPi d.root = false)
    (hnr : ∀ d ∈ ds, S.isReg d.root = false) :
    S.canon (A2.killNames ds Γ) = A2.killNames (rds S.ρ ds) (S.canon Γ) :=
  canon_killNames' h hab ds hal hnp fun d hd => Or.inl (hnr d hd)

theorem PW.killNames {Γ Γ' : Ctx} (hp : PW Γ Γ') : ∀ ds, PW (A2.killNames ds Γ) (A2.killNames ds Γ')
  | [] => hp
  | _ :: ds => show PW (A2.kill _ _ _ (A2.killNames ds Γ)) (A2.kill _ _ _ (A2.killNames ds Γ')) from
      (PW.killNames hp ds).kill _ _ _

/-- A2-drop.2: what the arguments' closures may change of the frame, by
    name, no destructor binding views: the frame's live ones are not
    reached (`N_mut`), its dead ones depend on nothing, and the callee's
    own reach the frame only through what the arguments held — the views
    of other roots (`N_mut`: not `R`'s) and names. -/
theorem DtorSafe.canon_N (h : S.OK) {d : Dep} (hN : d ∈ S.N) (hb : d.kind.bound ≠ .none) :
    DtorSafe (S.canon Γa) d.kind.bound false d.root := by
  obtain ⟨_, hR, _, _, _, hlive⟩ := h.N_mut d hN hb
  have hout := (h.N_out d hN).1
  intro y E hy hdt hos
  rcases canon_cases_sub h Γa y with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨_, hc⟩
  · rw [hc] at hy
    obtain ⟨Ea, _, rfl⟩ := Option.map_eq_some_iff.mp hy
    simp only [Function.comp_apply, subE_dtor, subE_mode] at hdt hos ⊢
    by_cases hrb : Ea.mode = .rootb
    · simp only [liftE, hrb, ↓reduceIte, h.pe_dtor] at hdt; cases hdt
    · unfold hitsMem
      simp only [Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true, beq_iff_eq, not_and,
        Bool.not_eq_true']
      refine Or.inr fun d' hd' hr _ => ?_
      rw [subE_vdeps] at hd'
      obtain ⟨d1, hd1, hdd⟩ := List.mem_flatMap.mp hd'
      rcases S.mem_subD hdd with rfl | ⟨w, _, _, hσ⟩
      · rcases liftE_vdeps_cases hrb hd1 with ⟨d0, _, rfl⟩ | ha
        · exact hout d0.root hr.1
        · rcases S.mem_A_ak h ha with ha | ha
          · exact hR (hr.1 ▸ mem_allKinds ha)
          · have := h.N_name d' ha; rw [hr.2] at this; cases this
      · exact hR (hr.1 ▸ mem_allKinds (hσ.sub h))
  · rw [hc] at hy; cases hy
  · rw [hc] at hy
    by_cases hl : E.live = true
    · exact hitsMem_of_hits (hlive y E hy hl)
    · exact h.ΦN y E hy hdt hos d hN hb

/-- A2-drop.2: a call's moves, changes and kills by name stay safe where
    the call places the callee's body. -/
theorem CallDtorSafe.canon (h : S.OK) (hab : S.AbsOK Γa) {ps : List (PMode × Ty)} {args : List Var}
    (hargs : ∀ a ∈ args, ∃ Ea, Γa a = some Ea) (hlen : args.length = ps.length)
    (hok : ∀ i (hi : i < ps.length), ∃ Ea, Γa (args.getD i 0) = some Ea ∧ paramOK ps[i].1 ps[i].2 Ea)
    (hal : ∀ d ∈ mutNames Γa args, Allowed S d.kind.bound false d.root)
    (hds : CallDtorSafe Γa ps args) (hvs : ∀ a ∈ args, S.isPi a = false) :
    CallDtorSafe (S.canon Γa) ps (args.map S.ρ) := by
  refine ⟨fun i hi => ⟨fun hs => ?_, fun b hb => ?_⟩, fun d hd => ?_, fun i hi b hb Ea hEa => ?_⟩
  · obtain ⟨Ea, hEa, hpo⟩ := hok i hi
    rw [hs] at hpo
    rw [getD_map (hlen ▸ hi)]
    exact DtorSafe.canon h (allowed_own hab hEa hpo.2.1 _ _) ((hds.1 i hi).1 hs)
  · obtain ⟨Ea, hEa, hpo⟩ := hok i hi
    rw [hb] at hpo
    obtain ⟨hty, hcan, _⟩ := hpo
    rw [getD_map (hlen ▸ hi)]
    have ha := allowed_canDo' hab hEa hcan
    rw [hty] at ha
    exact DtorSafe.canon h ha ((hds.1 i hi).2 b hb)
  · rcases mem_mutNames_canon h hab hargs hvs hd with hd | ⟨hN, hb⟩
    · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
      exact DtorSafe.canon h (hal d0 hd0) (hds.2.1 d0 hd0)
    · exact DtorSafe.canon_N h hN hb
  · -- an `inout` argument `letd` made, lifted, is one before
    obtain ⟨Ea0, hEa0, _⟩ := hok i hi
    have hia : i < args.length := hlen ▸ hi
    rw [getD_map hia, canon_some h hEa0 (hvs _ (by simp only [List.getD, List.getElem?_eq_getElem hia, Option.getD_some]; exact List.getElem_mem hia)), Option.some.injEq] at hEa
    subst hEa
    rw [subE_dbind, liftE_dbind h]
    split
    · rfl
    · exact hds.2.2 i hi b hb Ea0 hEa0

/-- AGORA-937 (B3): an effect ends no more with `hv` false. -/
theorem Eff.kills_hv_mono {e : Eff} {k : Kind} (h : e.kills false k = true) (hv : Bool) :
    e.kills hv k = true := by
  cases e <;> cases k <;> cases hv <;> simp_all [Eff.kills]

/-- AGORA-937 (B3): what a lifted borrowed parameter holds in memory: a
    callee region's index, renamed, or a frame root (one a region stands
    for, so in `R`, or one the argument's entry depends on). -/
theorem liftE_rootb_held_mem (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry}
    (hE : Γa v = some E) (hrb : E.mode = .rootb) {d : Dep}
    (hd : d ∈ (S.subE (S.liftE v E)).held) (hk : d.kind.isName = false) :
    (∃ u, d.root = S.ρ u ∧ S.isReg u = true) ∨
    ((∀ w, S.ρ w ≠ d.root) ∧ (d.root ∈ S.R ∨ d ∈ (S.pe v).vdeps)) := by
  rw [subE_held] at hd
  obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp hd
  rcases S.mem_subD hde with rfl | ⟨u, _, _, e0, he0, rfl, hk0⟩
  · simp only [liftE, hrb, ↓reduceIte, List.mem_append] at he
    rcases he with he | he
    · obtain ⟨e1, he1, rfl⟩ := mem_rds.mp he
      obtain ⟨he1', hn1⟩ := List.mem_filter.mp he1
      obtain ⟨_, _, R, hR, hh⟩ := hab.1 v E hE hrb
      rw [hh] at he1'
      rcases List.mem_append.mp he1' with hr | hs
      · exact Or.inl ⟨e1.root, rfl, (hR e1 hr).2⟩
      · exfalso
        split at hs
        · obtain ⟨w, b, t, rfl, _⟩ := h.sym_ok e1 hs
          simp [Kind.isName] at hn1
        · cases hs
    · split at he
      · exfalso; have := (List.mem_filter.mp he).2; simp [hk] at this
      · have hv : d ∈ (S.pe v).vdeps := by unfold Entry.vdeps; exact List.mem_append_right _ he
        exact Or.inr ⟨(h.pe_out v d hv hk).1, Or.inr hv⟩
  · refine Or.inr ⟨(S.σ_frameC h ⟨e0, he0, rfl, hk0⟩).1, Or.inl ?_⟩
    show e0.root ∈ S.R
    exact mem_allKinds (h.σ_sub u he0)

/-- What a closure handed to a call may change is changed by the call, where
    the call places it. -/
theorem namesFree_lift (h : S.OK) (hab : S.AbsOK Γa) {Fa : List Var} {ps : List (PMode × Ty)}
    {args : List Var} (hargs : ∀ a ∈ args, ∃ Ea, Γa a = some Ea) (hvs : ∀ a ∈ args, S.isPi a = false)
    (hnf : NamesFree Γa Fa ps args) :
    NamesFree (S.canon Γa) S.Fc ps (args.map S.ρ) := by
  intro d hd
  rcases mem_mutNames_canon h hab hargs hvs hd with hd | ⟨hN, hb⟩
  case inr =>
    -- what the arguments' closures may change
    obtain ⟨hFc, hR, ⟨Er, hEr, hcan, s, hts, hsv⟩, hpe, hN', hhit⟩ := h.N_mut d hN hb
    have hout := (h.N_out d hN).1
    have hae : argE (S.canon Γa) d.root = Er := by unfold argE; rw [canon_frame _ hout, hEr]; rfl
    refine ⟨by rw [hae]; exact hcan, ⟨s, by rw [hae]; exact hts, hsv⟩, hFc, Or.inl fun hm => ?_,
      fun a' ha' _ d' hd' hr' => ?_, fun p Ep hp hm d' hd' hr' hha => ?_⟩
    rotate_right
    · -- AGORA-937 (B3): a frame binding is reached by the closures' change as
      -- by none (`N_mut`); a lifted borrowed parameter holds nothing on it in
      -- memory (it is a frame root, in no region, and the arguments reach it
      -- only by names of the change's bound)
      rcases canon_cases_sub h Γa p with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨_, hc⟩ <;> rw [hc] at hp
      · obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp hp
        simp only [Function.comp, subE_mode] at hm
        have hrb : E.mode = .rootb := (liftE_rootb h).mp hm
        exfalso
        have hk : d'.kind.isName = false := by rcases hha.2.2.2 with h' | h' <;> rw [h'] <;> rfl
        rcases liftE_rootb_held_mem h hab hE hrb hha.2.1 hk with ⟨u, hu, _⟩ | ⟨_, hR' | hpv⟩
        · exact hout u (hu.symm.trans hr')
        · exact hR (hr' ▸ hR')
        · have := hpe v d' hpv hr'
          rcases hha.2.2.2 with h' | h' <;> rw [h'] at this <;> exact hb this.symm
      · cases hp
      · have hl := h.Φrb p Ep hp hm
        have h0 := hhit p Ep hp hl
        simp only [hits, hm, beq_self_eq_true, Bool.or_true, Bool.true_and, List.any_eq_false,
          Bool.and_eq_true, beq_iff_eq, not_and, Bool.not_eq_true] at h0
        exact h0 d' hd' hr'
    · obtain ⟨a, _, he⟩ := List.mem_map.mp hm; exact hout a he
    · obtain ⟨a, ha, rfl⟩ := List.mem_map.mp ha'
      obtain ⟨Ea, hEa⟩ := hargs a ha
      rw [argE_canons h hEa (hvs a ha)] at hd'
      rcases S.mem_subE_vdeps_A h hd' with hd' | ha2
      · by_cases hrb : Ea.mode = .rootb
        · rcases liftE_rootb_dep h hab hEa hrb hd' with hd' | ⟨u, rfl, _, _⟩
          · exact hpe a d' hd' hr'
          · exact absurd hr' (hout u)
        · rcases liftE_vdeps_cases hrb hd' with ⟨d1, _, rfl⟩ | ha2
          · exact absurd hr' (hout d1.root)
          · rcases S.mem_A_ak h ha2 with ha2 | ha2
            · exact absurd (hr' ▸ mem_allKinds ha2) hR
            · exact hN' d' ha2 hr'
      · rcases S.mem_B_ak h ha2 with ha2 | ha2
        · exact absurd (hr' ▸ mem_allKinds ha2) hR
        · exact hN' d' ha2 hr'
  obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
  obtain ⟨hcan, ⟨s, hts, hsv⟩, hF, hna, hoth, hnh0⟩ := hnf d0 hd0
  have hex : ∃ E0, Γa d0.root = some E0 := by
    cases hE : Γa d0.root with
    | some E0 => exact ⟨E0, rfl⟩
    | none =>
      exfalso; unfold argE at hcan; rw [hE] at hcan
      rcases hcan with hm | ⟨b, hm, _⟩ <;> simp [intE] at hm
  obtain ⟨E0, hE0⟩ := hex
  have hae0 : argE Γa d0.root = E0 := by unfold argE; rw [hE0]; rfl
  rw [hae0] at hcan hts
  have hrb0 : E0.mode ≠ .rootb := fun e => by rw [e] at hcan; rcases hcan with hm | ⟨b, hm, _⟩ <;> cases hm
  -- (what a closure may change owns its slot: no region)
  have hnp0 : S.isPi d0.root = false := hab.notPi hE0 (by
    rcases hcan with hm | ⟨b, hm, _⟩ <;> rw [hm] <;> simp)
  refine ⟨?_, ⟨s, ?_, hsv⟩, h.Fcout _, ?_, fun a' ha' hn' d' hd' hr' => ?_,
    fun p Ep hp hm d' hd' hr' hha => ?_⟩
  rotate_right
  · -- AGORA-937 (B3): a lifted borrowed parameter holds nothing in memory on a
    -- callee binding that is no region; a frame binding's dependency on a
    -- renamed one is on an `inout` parameter, spared by its bound
    -- (`Φsat`), which bounds every change the callee's closures make there
    have hr0 : d'.root = S.ρ d0.root := hr'
    show d0.kind.bound.kills false d'.kind = false
    rcases canon_cases_sub h Γa p with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨_, hc⟩ <;> rw [hc] at hp
    · obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp hp
      simp only [Function.comp, subE_mode] at hm
      have hrb : E.mode = .rootb := (liftE_rootb h).mp hm
      exfalso
      have hk : d'.kind.isName = false := by rcases hha.2.2.2 with h' | h' <;> rw [h'] <;> rfl
      rcases liftE_rootb_held_mem h hab hE hrb hha.2.1 hk with ⟨u, hu, hreg⟩ | ⟨hout', _⟩
      · have := h.inj _ _ (hu.symm.trans hr0); subst this
        have := ((hab.2.2.2.1 _ E0 hE0).1).mpr hreg
        rcases hcan with hm' | ⟨b, hm', _⟩ <;> rw [hm'] at this <;> cases this
      · exact hout' d0.root hr0.symm
    · cases hp
    · have hl := h.Φrb p Ep hp hm
      obtain ⟨b, hv, hbv, hkb⟩ := h.Φsat p Ep hp hl (Or.inr hm) d' hd' d0.root hr0.symm
      obtain ⟨E1, hE1, hm1, _⟩ := hab.2.2.1 d0.root (b, hv) hbv
      rw [hE0] at hE1; cases hE1
      rcases hcan with hm' | ⟨b', hm', hle⟩ <;> rw [hm'] at hm1 <;> cases hm1
      cases hk : d0.kind.bound.kills false d'.kind
      · rfl
      · have := Eff.kills_hv_mono (Eff.kills_mono hle false d'.kind hk) hv
        rw [this] at hkb; cases hkb
  · show canDo (argE (S.canon Γa) (S.ρ d0.root)).mode d0.kind.bound
    rw [argE_canons h hE0 hnp0, subE_mode, liftE_mode _ hrb0]; exact canDo_lift hcan
  · show (argE (S.canon Γa) (S.ρ d0.root)).ty = _
    rw [argE_canons h hE0 hnp0, subE_ty, liftE_ty _ hrb0]; exact hts
  · rcases hna with hna | ⟨i, t, hai, hpi⟩
    · refine Or.inl fun hm => ?_
      obtain ⟨a, ha, he⟩ := List.mem_map.mp hm
      exact hna (h.inj _ _ he ▸ ha)
    · exact Or.inr ⟨i, t, by rw [List.getElem?_map, hai]; rfl, hpi⟩
  · obtain ⟨a, ha, rfl⟩ := List.mem_map.mp ha'
    obtain ⟨Ea, hEa⟩ := hargs a ha
    rw [argE_canons h hEa (hvs a ha)] at hn' hd'
    have hae : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
    have hn1 : Ea.ty ≠ .int ∨ Ea.mode = .rootb := by
      rcases hn' with h' | h'
      · rw [subE_ty, liftE_ty' h hab hEa] at h'; exact Or.inl h'
      · rw [subE_mode, liftE_rootb h] at h'; exact Or.inr h'
    rcases S.mem_subE_vdeps_A h hd' with hd' | hak
    case inr => exact absurd hr' ((B_out h hak) d0.root ∘ Eq.symm)
    by_cases hrb : Ea.mode = .rootb
    · rcases liftE_rootb_dep h hab hEa hrb hd' with hd'' | ⟨u, rfl, _, hu⟩
      · -- a symbolic name's image: the abstract parameter holds the symbolic name
        obtain ⟨b, t, rfl, hb, hpt, hbn, hbr, hf⟩ := pe_ρ h hd'' hr'
        exact hoth a ha (by rw [hae]; exact hn1) ⟨d0.root, .name b t⟩
          (by rw [hae]; exact abs_sym hab hEa hrb hf (h.sym_of _ b t hb hpt hbn hbr)) rfl
      · -- its own region, by its handle
        exact hoth a ha (by rw [hae]; exact hn1) ⟨u, .self⟩
          (by rw [hae]; simp [Entry.vdeps, hrb, Mode.ownSlot, hu]) (h.inj _ _ hr')
    · rcases liftE_vdeps_cases hrb hd' with ⟨d1, hd1, rfl⟩ | hak
      · exact hoth a ha (by rw [hae]; exact hn1) d1 (by rw [hae]; exact hd1) (h.inj _ _ hr')
      · exact absurd hr' ((A_out h hak) d0.root ∘ Eq.symm)

/-- What a call through a package returns, where a call places it. -/
theorem recvRes_lift (h : S.OK) (hab : S.AbsOK Γa) {c : Var} {Ec E E' : Entry} (hc : Γa c = some Ec)
    (hmo : E.mode = .own ∨ E.mode = .bor) (hE0 : E.dbind = false) (x : Var) (hEf : E.fresh = false)
    (hw : EntryWeaker E' (S.liftE x E)) :
    EntryWeaker (recvRes (S.ρ c) (S.liftE c Ec) E') (S.liftE x (recvRes c Ec E)) := by
  have hrb : E.mode ≠ .rootb := by rcases hmo with h' | h' <;> rw [h'] <;> simp
  have hdbw := hw.dbind
  have hraw := hw.raise
  -- the receiver's roots, lifted
  have hA : recvDeps (S.ρ c) (S.liftE c Ec) ⊆
      rds S.ρ (recvDeps c Ec) ++ S.A := by
    intro d hd
    obtain ⟨d0, hd0, k, hk, rfl⟩ := mem_recvDeps.mp hd
    have hkn : k.isName = false := by rcases hk with rfl | rfl | rfl | rfl <;> rfl
    -- a dependency of the lifted receiver: one of the receiver's, renamed, or the arguments'
    have hcase : ∀ {X Y : List Dep}, X ⊆ rds S.ρ Y ++ S.A → (∀ d1 ∈ memDeps Y,
        (⟨d1.root, comp d1.kind k⟩ : Dep) ∈ recvDeps c Ec) → d0 ∈ memDeps X →
        (⟨d0.root, comp d0.kind k⟩ : Dep) ∈ rds S.ρ (recvDeps c Ec) ++ S.A := by
      intro X Y hXY hY hd0
      obtain ⟨hd0X, hn0⟩ := List.mem_filter.mp hd0
      rcases List.mem_append.mp (hXY hd0X) with h1 | h1
      · obtain ⟨d1, hd1, rfl⟩ := mem_rds.mp h1
        exact List.mem_append_left _ (mem_rds.mpr ⟨_, hY d1 (List.mem_filter.mpr ⟨hd1, by simpa [Dep.ren] using hn0⟩), rfl⟩)
      · rcases mem_A.mp h1 with hA0 | hA0
        · exact List.mem_append_right _ (mem_A.mpr (Or.inl (compAll_comp hA0 hk)))
        · rw [h.N_name d0 hA0] at hn0; cases hn0
    rcases List.mem_append.mp hd0 with hd0 | hd0
    · exact hcase (derive_lift h hab hc .self rfl)
        (fun d1 hd1 => mem_recvDeps.mpr ⟨d1, List.mem_append_left _ hd1, k, hk, rfl⟩) hd0
    · exact hcase (held_lift h hab hc)
        (fun d1 hd1 => mem_recvDeps.mpr ⟨d1, List.mem_append_right _ hd1, k, hk, rfl⟩) hd0
  obtain ⟨ht, hm, _, hl, hdw⟩ := hw
  have hty : (S.liftE x E).ty = E.ty := liftE_ty x hrb
  have hmd : (S.liftE x E).mode = liftMode E.mode := liftE_mode x hrb
  have hos : (liftMode E.mode).ownSlot = E.mode.ownSlot := liftMode_ownSlot _
  have hpath : (S.liftE x E).path = rds S.ρ E.path ++ (if E.mode.ownSlot then [] else S.A) := by
    simp [liftE, hrb, hEf]
  have hheld : (S.liftE x E).held ⊆ rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty S.A := S.liftE_held_sub hrb
  have hrrb : (recvRes c Ec E).mode ≠ .rootb := hrb
  have hpath2 : (S.liftE x (recvRes c Ec E)).path =
      rds S.ρ (E.path ++ recvDeps c Ec) ++ (if E.mode.ownSlot then [] else S.A) := by
    simp [liftE, recvRes, hrb, hEf]
  have hheld2 : (S.liftE x (recvRes c Ec E)).held =
      rds S.ρ (ownHeld E.mode.ownSlot E.ty (E.held ++ recvDeps c Ec)) ++
        ownHeld E.mode.ownSlot E.ty S.A := by
    simp [liftE, recvRes, hrb]
  have hE'os : E'.mode.ownSlot = E.mode.ownSlot := by rw [← hm, hmd, hos]
  have hE'ty : E'.ty = E.ty := by rw [← ht, hty]
  have hheldR : E'.held ⊆ (S.liftE x E).held →
      (recvRes (S.ρ c) (S.liftE c Ec) E').held ⊆ (S.liftE x (recvRes c Ec E)).held := by
    intro hh1
    show ownHeld E'.mode.ownSlot E'.ty (E'.held ++ _) ⊆ (S.liftE x (recvRes c Ec E)).held
    rw [hE'os, hE'ty, hheld2]
    replace hh1 := hh1.trans hheld
    by_cases hc0 : (E.mode.ownSlot && !E.ty.holdsView) = true
    · simp only [ownHeld, hc0, ↓reduceIte]; intro d hd; cases hd
    · simp only [ownHeld, hc0, Bool.false_eq_true, ↓reduceIte] at hh1 ⊢
      simp only [rds, List.map_append] at hh1 ⊢
      intro d hd
      rcases List.mem_append.mp hd with hd | hd
      · rcases List.mem_append.mp (hh1 hd) with h1 | h1
        · exact List.mem_append_left _ (List.mem_append_left _ h1)
        · exact List.mem_append_right _ h1
      · rcases List.mem_append.mp (hA hd) with h1 | h1
        · exact List.mem_append_left _ (List.mem_append_right _ h1)
        · exact List.mem_append_right _ h1
  have hlx : (S.liftE x E).dbind = E.dbind := by simp [liftE, hrb]
  have hlxt : (S.liftE x E).dtor = E.dtor := by simp [liftE, hrb]
  have hE'0 : E'.dbind = false := by rw [← hdbw, hlx, hE0]
  refine ⟨?_, ?_, fun h' => ?_, fun hl' => ?_, fun hd' => ?_, ?_, fun hd' => ?_, fun hd' => ?_,
      fun _ _ _ hfr => by simp [liftE, recvRes, hrb, hEf] at hfr,
      fun _ _ hhf => by simp [liftE, recvRes, hrb] at hhf⟩
  · show (S.liftE x (recvRes c Ec E)).ty = E'.ty
    rw [← ht, hty]; simp [liftE, recvRes, hrb]
  · show (S.liftE x (recvRes c Ec E)).mode = E'.mode
    rw [← hm, hmd]; simp [liftE, recvRes, hrb]
  · exfalso
    change E'.mode = .rootb ∨ ∃ b, E'.mode = .inout b ∧ b ≠ .replace ∧ E'.ty.holdsView = false at h'
    rw [← hm, hmd] at h'
    rcases h' with h' | ⟨b, h', _⟩
    · exact hrb (liftMode_rootb.mp h')
    · cases hq : E.mode <;> rw [hq] at h' <;> simp [liftMode] at h'
  · have hlE : (S.liftE x E).live = true := by
      have : (S.liftE x (recvRes c Ec E)).live = E.live := by simp [liftE, recvRes, hrb]
      rw [liftE_live]; rw [this] at hl'; exact hl'
    obtain ⟨hl1, hp1, hh1⟩ := hl hlE
    refine ⟨hl1, fun hos' => ?_, ?_⟩
    · change E'.mode.ownSlot = false at hos'
      have hosE : E.mode.ownSlot = false := by rw [← hm, hmd, hos] at hos'; exact hos'
      have hp := hp1 hos'
      rw [hpath, hosE] at hp
      rw [hpath2, hosE]
      simp only [Bool.false_eq_true, ↓reduceIte, rds, List.map_append] at hp ⊢
      intro d hd
      rcases List.mem_append.mp hd with hd | hd
      · rcases List.mem_append.mp (hp hd) with h1 | h1
        · exact List.mem_append_left _ (List.mem_append_left _ h1)
        · exact List.mem_append_right _ h1
      · rcases List.mem_append.mp (hA hd) with h1 | h1
        · exact List.mem_append_left _ (List.mem_append_right _ h1)
        · exact List.mem_append_right _ h1
    · exact hheldR hh1
  · obtain ⟨hd1, hh1⟩ := hdw hd'
    refine ⟨?_, hheldR hh1⟩
    have : (S.liftE x E).dtor = E.dtor := by simp [liftE, hrb]
    rw [this] at hd1
    simp [liftE, recvRes, hrb, hd1]
  · simp [liftE, recvRes, hrb, hE0, hE'0]
  · have hd0 : E.dtor = true := by simpa [liftE, recvRes, hrb] using hd'
    rcases hraw (by rw [hlxt]; exact hd0) with h1 | h1
    · exact Or.inl (by simpa [recvRes] using h1)
    · exact Or.inr (by simpa [recvRes] using h1)
  · simp [recvRes, hE'0] at hd'

theorem flatMap_lift {l : List (Nat × Kind)} {fc fa : Nat × Kind → List Dep}
    (hf : ∀ jk ∈ l, fc jk ⊆ rds S.ρ (fa jk) ++ S.A) :
    l.flatMap fc ⊆ rds S.ρ (l.flatMap fa) ++ S.A := by
  intro d hd
  obtain ⟨jk, hjk, hd'⟩ := List.mem_flatMap.mp hd
  rcases List.mem_append.mp (hf jk hjk hd') with h1 | h1
  · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
    exact List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_flatMap.mpr ⟨jk, hjk, hd0⟩, rfl⟩)
  · exact List.mem_append_right _ h1

/-- AGORA-937 (3d): `flatMap_lift` / `app_lift`, substituted. -/
theorem flatMap_liftS {l : List (Nat × Kind)} {fc fa : Nat × Kind → List Dep}
    (hf : ∀ jk ∈ l, fc jk ⊆ (rds S.ρ (fa jk) ++ S.A).flatMap S.subD) :
    l.flatMap fc ⊆ (rds S.ρ (l.flatMap fa) ++ S.A).flatMap S.subD := by
  intro d hd
  obtain ⟨jk, hjk, hd'⟩ := List.mem_flatMap.mp hd
  obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp (hf jk hjk hd')
  refine List.mem_flatMap.mpr ⟨e, ?_, hde⟩
  rcases List.mem_append.mp he with h1 | h1
  · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
    exact List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_flatMap.mpr ⟨jk, hjk, hd0⟩, rfl⟩)
  · exact List.mem_append_right _ h1

theorem app_liftS {a b a0 b0 : List Dep} (ha : a ⊆ (rds S.ρ a0 ++ S.A).flatMap S.subD)
    (hb : b ⊆ (rds S.ρ b0 ++ S.A).flatMap S.subD) : a ++ b ⊆ (rds S.ρ (a0 ++ b0) ++ S.A).flatMap S.subD := by
  have hmono : ∀ {x x0 : List Dep}, x0 ⊆ a0 ++ b0 → x ⊆ (rds S.ρ x0 ++ S.A).flatMap S.subD →
      x ⊆ (rds S.ρ (a0 ++ b0) ++ S.A).flatMap S.subD := by
    intro x x0 hx0 hx d hd
    obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp (hx hd)
    refine List.mem_flatMap.mpr ⟨e, ?_, hde⟩
    rcases List.mem_append.mp he with h1 | h1
    · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
      exact List.mem_append_left _ (mem_rds.mpr ⟨d0, hx0 hd0, rfl⟩)
    · exact List.mem_append_right _ h1
  intro d hd
  rcases List.mem_append.mp hd with hd | hd
  · exact hmono (List.subset_append_left _ _) ha hd
  · exact hmono (List.subset_append_right _ _) hb hd

theorem outHeld_lift (h : S.OK) (hab : S.AbsOK Γa) {fn : Fn} {args : List Var}
    (houts : ∀ o ∈ fn.outHolds, o.2.1 < args.length ∧ o.2.2.isName = false)
    (hargs : ∀ j < args.length, ∃ Ea, Γa (args.getD j 0) = some Ea) (hvs : ∀ a ∈ args, S.isPi a = false) (i : Nat) :
    outHeld (S.canon Γa) fn (args.map S.ρ) i ⊆ (rds S.ρ (outHeld Γa fn args i) ++ S.A).flatMap S.subD := by
  intro d hd
  unfold outHeld at hd ⊢
  obtain ⟨o, ho, hd'⟩ := List.mem_flatMap.mp hd
  have hom := (List.mem_filter.mp ho).1
  obtain ⟨Ea, hEa⟩ := hargs o.2.1 (houts o hom).1
  obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp
    (argDeps_lift h hab (houts o hom).1 hEa (hvs _ (getD_mem' (houts o hom).1)) o.2.2 (houts o hom).2 hd')
  refine List.mem_flatMap.mpr ⟨e, ?_, hde⟩
  rcases List.mem_append.mp he with h1 | h1
  · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
    exact List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_flatMap.mpr ⟨o, ho, hd0⟩, rfl⟩)
  · exact List.mem_append_right _ h1

theorem resMode_ne (fn : Fn) : resMode fn ≠ .rootb := by unfold resMode; split <;> simp
theorem resMode_notInout (fn : Fn) (b : Eff) : resMode fn ≠ .inout b := by unfold resMode; split <;> simp

/-- A call's result is never fixed. -/
theorem callRes_not_fixed (Γ : Ctx) (fn : Fn) (args : List Var) : ¬ (callRes Γ fn args).fixed := by
  simp only [Entry.fixed_def, callRes]
  rintro (h | ⟨b, h, _⟩)
  · exact resMode_ne fn h
  · exact resMode_notInout fn b h
theorem liftMode_resMode (fn : Fn) : liftMode (resMode fn) = resMode fn := by unfold resMode; split <;> rfl

theorem resMode_ownSlot (fn : Fn) : (resMode fn).ownSlot = fn.resOwn := by
  unfold resMode; cases fn.resOwn <;> rfl

theorem liftE_callRes (Γ : Ctx) (fn : Fn) (args : List Var) (x : Var) :
    S.liftE x (callRes Γ fn args) =
      ⟨fn.resTy, resMode fn, true,
       rds S.ρ (fn.lends.flatMap (argDeps Γ args) ++ heldOfArgs Γ args) ++
         (if (resMode fn).ownSlot then [] else S.A),
       rds S.ρ (ownHeld fn.resOwn fn.resTy (fn.rholds.flatMap (argDeps Γ args) ++ heldOfArgs Γ args)) ++
         ownHeld fn.resOwn fn.resTy S.A, false, false, false, false⟩ := by
  simp only [liftE, heldA, callRes, resMode_ne fn, ↓reduceIte, liftMode_resMode, resMode_ownSlot, Bool.false_and,
    Bool.or_false, Bool.false_eq_true]

/-- AGORA-937: a dependency on a frame root is kept. -/
theorem subD_frameRoot {e : Dep} (hout : ∀ w, S.ρ w ≠ e.root) : S.subD e = [e] :=
  S.subD_of_not (fun w hw => absurd (ρ_of_inv hw) (hout w))

/-- AGORA-937: the substitution keeps a dependency on a frame root, and one
    on a callee binding at no region's index. -/
theorem subD_keep (h : S.OK) {d : Dep}
    (hd : (∀ w, S.ρ w ≠ d.root) ∨ ∃ w, d.root = S.ρ w ∧ S.isPi w = false) :
    S.subD d = [d] := by
  rcases hd with hout | ⟨w, hw, hp⟩
  · exact S.subD_frameRoot hout
  · apply S.subD_of_not; intro u hu; rw [hw, inv_ρ h] at hu; cases hu; exact hp

/-- AGORA-937: the substitution keeps a lifted entry whose own dependencies
    are on no region: what the lift adds is the frame's, or a borrowed
    parameter's (`pe_out`), or (by name) an `inout` parameter's symbolic
    name, on no region either (`hsym`). -/
theorem subE_liftE_fix (h : S.OK) {v : Var} {E : Entry}
    (hE : E.mode ≠ .rootb → ∀ d ∈ E.path ++ E.held, S.isPi d.root = false)
    (hEb : E.mode = .rootb → ∀ d ∈ E.held, S.isPi d.root = false)
    (hsym : ∀ d ∈ S.sym, S.isPi d.root = false) :
    S.subE (S.liftE v E) = S.liftE v E := by
  have key : ∀ L : List Dep, (∀ d ∈ L, (∀ w, S.ρ w ≠ d.root) ∨
      ∃ w, d.root = S.ρ w ∧ S.isPi w = false) → L.flatMap S.subD = L :=
    fun L hL => S.flatMap_subD_fix fun d hd => S.subD_keep h (hL d hd)
  have hfix : ∀ E' : Entry, E'.path.flatMap S.subD = E'.path → E'.held.flatMap S.subD = E'.held →
      S.subE E' = E' := by
    intro E' hp hh; cases E'; simp only [subE] at hp hh ⊢; rw [hp, hh]
  have hA : ∀ d ∈ S.A, (∀ w, S.ρ w ≠ d.root) ∨
      ∃ w, d.root = S.ρ w ∧ S.isPi w = false := fun d hd => Or.inl (A_out h hd)
  by_cases hrb : E.mode = .rootb
  · have hpe : ∀ d ∈ (S.pe v).path ++ (S.pe v).held, (∀ w, S.ρ w ≠ d.root) ∨
        ∃ w, d.root = S.ρ w ∧ S.isPi w = false := by
      intro d hd
      have hdv : d ∈ (S.pe v).vdeps := by
        unfold Entry.vdeps; rw [h.pe_rb v]; exact hd
      cases hk : d.kind.isName
      · exact Or.inl (h.pe_out v d hdv hk).1
      · rcases h.pe_names v d hdv hk with hN | ⟨hs, _⟩
        · exact Or.inl (h.N_out d hN).1
        · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hs
          exact Or.inr ⟨d0.root, rfl, hsym d0 hd0⟩
    apply hfix
    · simp only [liftE, hrb, ↓reduceIte]
      exact key _ fun d hd => hpe d (List.mem_append_left _ hd)
    · -- AGORA-937 (3d): the callee's own memory, renamed, on no region; and the argument's names
      simp only [liftE, hrb, ↓reduceIte]
      refine key _ fun d hd => ?_
      rcases List.mem_append.mp hd with h1 | h1
      · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
        exact Or.inr ⟨d0.root, rfl, hEb hrb d0 (List.mem_filter.mp hd0).1⟩
      · refine hpe d (List.mem_append_right _ ?_)
        split at h1
        · exact (List.mem_filter.mp h1).1
        · exact h1
  · have hR : ∀ L : List Dep, L ⊆ E.path ++ E.held → ∀ d ∈ rds S.ρ L,
        (∀ w, S.ρ w ≠ d.root) ∨ ∃ w, d.root = S.ρ w ∧ S.isPi w = false := by
      intro L hL d hd
      obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
      exact Or.inr ⟨d0.root, rfl, hE hrb d0 (hL hd0)⟩
    apply hfix
    · simp only [liftE, hrb, ↓reduceIte]
      refine key _ fun d hd => ?_
      rcases List.mem_append.mp hd with h1 | h1
      · exact hR _ (List.subset_append_left _ _) d h1
      · split at h1
        · cases h1
        · exact hA d h1
    · simp only [liftE, hrb, ↓reduceIte]
      refine key _ fun d hd => ?_
      rcases List.mem_append.mp hd with h1 | h1
      · exact hR _ (List.subset_append_right _ _) d h1
      · exact hA d (S.heldA_sub E (ownHeld_sub _ _ _ h1))

/-- AGORA-937: the substitution is idempotent: what it gives it keeps. -/
theorem subD_idem (h : S.OK) {d e : Dep} (he : e ∈ S.subD d) : S.subD e = [e] := by
  rcases S.mem_subD he with rfl | ⟨v, _, _, hσ⟩
  · by_cases hi : ∃ w, S.inv e.root = some w ∧ S.isPi w = true
    · obtain ⟨w, hw, hp⟩ := hi
      exfalso
      cases hk : e.kind.isName
      · have hσ : S.σC w e.kind e := by
          have : S.subD e = (S.σ w).map fun e' => (⟨e'.root, A2.comp e'.kind e.kind⟩ : Dep) := by
            simp only [subD, hw, hp, hk, Bool.false_eq_true, ↓reduceIte]
          rw [this] at he
          obtain ⟨e0, he0, he'⟩ := List.mem_map.mp he
          exact ⟨e0, he0, he'.symm, hk⟩
        exact absurd (ρ_of_inv hw) ((S.σ_frameC h hσ).1 w)
      · -- a name on a region is dropped, so not kept
        have : S.subD e = [] := by simp only [subD, hw, hp, hk, ↓reduceIte]
        rw [this] at he; cases he
    · exact S.subD_of_not (fun w hw => by
        cases hp : S.isPi w
        · rfl
        · exact absurd ⟨w, hw, hp⟩ hi)
  · exact S.subD_frameRoot (S.σ_frameC h hσ).1

/-- ... so a kept dependency is on no region, and any dependency on its
    root is kept. -/
theorem subD_fix_reKind (h : S.OK) {e : Dep} (he : S.subD e = [e]) (k : Kind) :
    S.subD ⟨e.root, k⟩ = [⟨e.root, k⟩] := by
  refine S.subD_of_not (fun w hw => ?_)
  cases hp : S.isPi w
  · rfl
  · exfalso
    cases hen : e.kind.isName
    · have : S.subD e = (S.σ w).map fun e' => (⟨e'.root, A2.comp e'.kind e.kind⟩ : Dep) := by
        simp only [subD, hw, hp, hen, Bool.false_eq_true, ↓reduceIte]
      rw [this] at he
      have hmem : e ∈ (S.σ w).map fun e' => (⟨e'.root, A2.comp e'.kind e.kind⟩ : Dep) := by
        rw [he]; exact List.mem_singleton_self e
      obtain ⟨e0, he0, he'⟩ := List.mem_map.mp hmem
      exact (S.σ_frameC h ⟨e0, he0, he'.symm, hen⟩).1 w (ρ_of_inv hw)
    · have : S.subD e = [] := by simp only [subD, hw, hp, hen, ↓reduceIte]
      rw [this] at he; cases he

/-- ... and a list of kept dependencies under a bound stays under its
    substitution. -/
theorem sub_flatMap_of_fix {L X : List Dep} (hf : ∀ d ∈ L, S.subD d = [d]) (hL : L ⊆ X) :
    L ⊆ X.flatMap S.subD :=
  fun d hd => List.mem_flatMap.mpr ⟨d, hL hd, by rw [hf d hd]; exact List.mem_singleton_self d⟩

/-- AGORA-937: what is borrowed from a substituted entry at no region's index
    is kept by the substitution. -/
theorem derive_subE_fix (h : S.OK) {a : Var} (hnp : S.isPi a = false) (L : Entry) (k : Kind) :
    ∀ d ∈ derive (S.ρ a) (S.subE L) k, S.subD d = [d] := by
  intro d hd
  unfold derive at hd
  split at hd
  · rw [List.mem_singleton] at hd; subst hd
    exact S.subD_of_not (fun w hw => by rw [inv_ρ h] at hw; cases hw; exact hnp)
  · obtain ⟨e, he, rfl⟩ := List.mem_map.mp hd
    rw [subE_path] at he
    obtain ⟨e1, _, he1⟩ := List.mem_flatMap.mp he
    exact S.subD_fix_reKind h (S.subD_idem h he1) _

/-- ... so are an argument's dependencies, and what the arguments hold. -/
theorem argDeps_canon_fix (h : S.OK) {args : List Var} {j : Nat} (hj : j < args.length) {Ea : Entry}
    (hEa : Γa (args.getD j 0) = some Ea) (hnp : S.isPi (args.getD j 0) = false) (k : Kind) :
    ∀ d ∈ argDeps (S.canon Γa) (args.map S.ρ) (j, k), S.subD d = [d] := by
  intro d hd
  unfold argDeps at hd
  simp only [getD_map hj, argE_canons h hEa hnp] at hd
  split at hd
  · cases hd
  · exact derive_subE_fix h hnp _ k d hd

theorem heldOfArgs_canon_fix (h : S.OK) {args : List Var} (hall : ∀ a ∈ args, ∃ Ea, Γa a = some Ea)
    (hvs : ∀ a ∈ args, S.isPi a = false) : ∀ d ∈ heldOfArgs (S.canon Γa) (args.map S.ρ), S.subD d = [d] := by
  intro d hd
  unfold heldOfArgs at hd
  rcases List.mem_append.mp hd with hd | hd
  · obtain ⟨e, he, k, _, rfl⟩ := mem_compAll.mp hd
    obtain ⟨a', ha', _, hm⟩ := mem_argMem.mp he
    obtain ⟨a, ha, rfl⟩ := List.mem_map.mp ha'
    obtain ⟨Ea, hEa⟩ := hall a ha
    rw [argE_canons h hEa (hvs a ha)] at hm
    have hem := List.mem_filter.mp hm
    rw [subE_held] at hem
    obtain ⟨e1, _, he1⟩ := List.mem_flatMap.mp hem.1
    exact S.subD_fix_reKind h (S.subD_idem h he1) _
  · -- a name an argument holds is kept: one on a region was dropped
    obtain ⟨b, hb, hdb⟩ := List.mem_flatMap.mp hd
    obtain ⟨a, ha, rfl⟩ := List.mem_map.mp hb
    obtain ⟨Ea, hEa⟩ := hall a ha
    rw [argE_canons h hEa (hvs a ha)] at hdb
    split at hdb
    · cases hdb
    · have hdv := (List.mem_filter.mp hdb).1
      rw [subE_vdeps] at hdv
      obtain ⟨d1, _, hd1⟩ := List.mem_flatMap.mp hdv
      exact S.subD_idem h hd1

/-- AGORA-937: ... and so does what an `inout` argument holds after the call. -/
theorem outHeld_canon_fix (h : S.OK) {fn : Fn} {args : List Var}
    (houts : ∀ o ∈ fn.outHolds, o.2.1 < args.length ∧ o.2.2.isName = false)
    (hargs : ∀ j < args.length, ∃ Ea, Γa (args.getD j 0) = some Ea) (hvs : ∀ a ∈ args, S.isPi a = false)
    (i : Nat) : ∀ d ∈ outHeld (S.canon Γa) fn (args.map S.ρ) i, S.subD d = [d] := by
  intro d hd
  unfold outHeld at hd
  obtain ⟨o, ho, hdo⟩ := List.mem_flatMap.mp hd
  have hoj := houts o (List.mem_filter.mp ho).1
  obtain ⟨Ea, hEa⟩ := hargs o.2.1 hoj.1
  exact argDeps_canon_fix h hoj.1 hEa (hvs _ (getD_mem' hoj.1)) o.2.2 d hdo

/-- AGORA-937 (3d): substituting commutes with composing a memory way: what
    a dependency is substituted by, composed, is what the dependency
    composed is substituted by (`comp_assoc`). -/
theorem mem_subD_comp (h : S.OK) {d e : Dep} (he : e ∈ S.subD d) {k : Kind} (hk : k.isName = false) :
    (⟨e.root, comp e.kind k⟩ : Dep) ∈ S.subD ⟨d.root, comp d.kind k⟩ := by
  rcases S.mem_subD he with rfl | ⟨v, hv, hp, e0, he0, rfl, hdk⟩
  · rw [S.subD_fix_reKind h (S.subD_idem h he)]; exact List.mem_singleton_self _
  · have hck : (comp d.kind k).isName = false := comp_isName hdk hk
    simp only [subD, hv, hp, hck, Bool.false_eq_true, ↓reduceIte, List.mem_map]
    exact ⟨e0, he0, by simp [comp_assoc]⟩

theorem heldOfArgs_lift (h : S.OK) (hab : S.AbsOK Γa) {args : List Var}
    (hargs : ∀ a ∈ args, ∃ Ea, Γa a = some Ea) (hvs : ∀ a ∈ args, S.isPi a = false) :
    heldOfArgs (S.canon Γa) (args.map S.ρ) ⊆ (rds S.ρ (heldOfArgs Γa args) ++ S.A).flatMap S.subD := by
  intro d hd
  unfold heldOfArgs at hd ⊢
  rcases List.mem_append.mp hd with hd | hd
  · -- AGORA-937 (3d): an argument's own memory dependency, substituted, composed
    obtain ⟨d0, hd0, k, hk, rfl⟩ := mem_compAll.mp hd
    have hkn : k.isName = false := by rcases hk with rfl | rfl | rfl | rfl <;> rfl
    obtain ⟨a', ha', hni, hm⟩ := mem_argMem.mp hd0
    obtain ⟨a, ha, rfl⟩ := List.mem_map.mp ha'
    obtain ⟨Ea, hEa⟩ := hargs a ha
    rw [argE_canons h hEa (hvs a ha)] at hni hm
    rw [subE_ty, liftE_ty' h hab hEa] at hni
    have hae : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
    obtain ⟨hm, hn0⟩ := List.mem_filter.mp hm
    have hn0 : d0.kind.isName = false := by simpa using hn0
    rw [subE_held] at hm
    obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp hm
    have hen : e.kind.isName = false := by
      rcases S.mem_subD hde with rfl | ⟨_, _, _, _, _, _, hk'⟩
      · exact hn0
      · exact hk'
    refine List.mem_flatMap.mpr ⟨⟨e.root, comp e.kind k⟩, ?_, S.mem_subD_comp h hde hkn⟩
    rcases List.mem_append.mp (held_lift h hab hEa he) with h1 | h1
    · obtain ⟨d1, hd1, rfl⟩ := mem_rds.mp h1
      exact List.mem_append_left _ (mem_rds.mpr ⟨⟨d1.root, comp d1.kind k⟩, List.mem_append_left _
        (mem_compAll.mpr ⟨d1, mem_argMem.mpr ⟨a, ha, by rw [hae]; exact hni,
          by rw [hae]; exact List.mem_filter.mpr ⟨hd1, by simpa [Dep.ren] using hen⟩⟩, k, hk, rfl⟩), rfl⟩)
    · exact List.mem_append_right _ (A_comp h hkn (List.mem_map_of_mem h1))
  · simp only [argNames, List.flatMap_map, List.mem_flatMap] at hd
    obtain ⟨a, ha, hda⟩ := hd
    obtain ⟨Ea, hEa⟩ := hargs a ha
    rw [argE_canons h hEa (hvs a ha), subE_ty, liftE_ty' h hab hEa] at hda
    have hae : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
    split at hda
    · simp at hda
    · rename_i hn
      have hd' := List.mem_filter.mp hda
      -- (a name is kept: what a region stands for is no name)
      have hdL : d ∈ (S.liftE a Ea).vdeps ∧ S.subD d = [d] := by
        have h0 := hd'.1
        rw [subE_vdeps] at h0
        obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp h0
        rcases S.mem_subD hde with rfl | ⟨v, _, _, hσ⟩
        · exact ⟨he, S.subD_idem h hde⟩
        · have := hσ.notName h
          have h2 : d.kind.isName = true := by simpa using hd'.2
          rw [h2] at this; cases this
      refine List.mem_flatMap.mpr ⟨d, ?_, by rw [hdL.2]; exact List.mem_singleton_self _⟩
      rcases names_liftE h hab hEa hdL.1 (by simpa using hd'.2) with ⟨d0, hd0, rfl⟩ | hN
      · refine List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_append_right _ ?_, rfl⟩)
        simp only [argNames, List.mem_flatMap]
        exact ⟨a, ha, by rw [hae, ite_eq_right hn]; exact List.mem_filter.mpr ⟨hd0, hd'.2⟩⟩
      · exact List.mem_append_right _ (mem_A.mpr (Or.inr hN))


theorem callRes_lift (h : S.OK) (hab : S.AbsOK Γa) {fn : Fn} {args : List Var}
    (hl : ∀ jk ∈ fn.lends ++ fn.rholds, jk.1 < args.length ∧ jk.2.isName = false)
    (hargs : ∀ j < args.length, ∃ Ea, Γa (args.getD j 0) = some Ea) (hvs : ∀ a ∈ args, S.isPi a = false) (x : Var) :
    EntryWeaker (callRes (S.canon Γa) fn (args.map S.ρ)) (S.subE (S.liftE x (callRes Γa fn args))) := by
  have hall : ∀ a ∈ args, ∃ Ea, Γa a = some Ea := by
    intro a ha; obtain ⟨i, hi, rfl⟩ := mem_args ha; exact hargs i hi
  have hA : ∀ jk ∈ fn.lends ++ fn.rholds, argDeps (S.canon Γa) (args.map S.ρ) jk ⊆
      (rds S.ρ (argDeps Γa args jk) ++ S.A).flatMap S.subD := by
    intro jk hjk
    obtain ⟨Ea, hEa⟩ := hargs jk.1 (hl jk hjk).1
    exact argDeps_lift h hab (hl jk hjk).1 hEa (hvs _ (getD_mem' (hl jk hjk).1)) jk.2 (hl jk hjk).2
  have hH := heldOfArgs_lift h hab hall hvs
  -- (what the canon context's arguments depend on is kept by the substitution)
  have hF : ∀ (L : List (Nat × Kind)), (∀ jk ∈ L, jk ∈ fn.lends ++ fn.rholds) →
      ∀ d ∈ L.flatMap (argDeps (S.canon Γa) (args.map S.ρ)) ++ heldOfArgs (S.canon Γa) (args.map S.ρ),
        S.subD d = [d] := by
    intro L hL d hd
    rcases List.mem_append.mp hd with hd | hd
    · obtain ⟨jk, hjk, hd'⟩ := List.mem_flatMap.mp hd
      obtain ⟨Ea, hEa⟩ := hargs jk.1 (hl jk (hL jk hjk)).1
      exact argDeps_canon_fix h (hl jk (hL jk hjk)).1 hEa (hvs _ (getD_mem' (hl jk (hL jk hjk)).1)) jk.2 d hd'
    · exact heldOfArgs_canon_fix h hall hvs d hd
  rw [liftE_callRes]
  refine EntryWeaker.mk' rfl rfl (callRes_not_fixed _ _ _) rfl (fun _ => ?_) ?_
  · rename_i ho
    simp only [callRes] at ho
    simp only [subE_path, ho, Bool.false_eq_true, ↓reduceIte]
    exact app_liftS (S := S) (flatMap_liftS (S := S) (fun jk hjk => hA jk (List.mem_append_left _ hjk))) hH
  · show ownHeld fn.resOwn fn.resTy _ ⊆ (S.subE _).held
    rw [subE_held]
    by_cases hc0 : (fn.resOwn && !fn.resTy.holdsView) = true
    · simp only [ownHeld, hc0, ↓reduceIte]; intro d hd; cases hd
    · simp only [ownHeld, hc0, Bool.false_eq_true, ↓reduceIte]
      exact app_liftS (S := S) (flatMap_liftS (S := S) (fun jk hjk => hA jk (List.mem_append_right _ hjk))) hH

theorem callPostAux_lift (h : S.OK) (hab0 : S.AbsOK Γa) {fn : Fn} {args : List Var}
    (houts : ∀ o ∈ fn.outHolds, o.2.1 < args.length ∧ o.2.2.isName = false)
    (hargs : ∀ j < args.length, ∃ Ea, Γa (args.getD j 0) = some Ea) (hvs : ∀ a ∈ args, S.isPi a = false) :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx) (Γc : Ctx),
      (∀ pa ∈ ps.zip as, ∃ Ea, Γa pa.2 = some Ea ∧ paramOK pa.1.1 pa.1.2 Ea) →
      -- A2-drop.2: an `inout` argument `letd` made holds no views (`CallDtorSafe`)
      (∀ pa ∈ ps.zip as, ∀ b, pa.1.1 = .inout b → ∀ Ea, Γa pa.2 = some Ea → Ea.dbind = true →
        pa.1.2.holdsView = false) →
      S.AbsOK Γ → PW Γc (S.canon Γ) →
      PW (callPostAux (S.canon Γa) fn (args.map S.ρ) ps (as.map S.ρ) i Γc)
        (S.canon (callPostAux Γa fn args ps as i Γ))
  | [], _, _, _, _, _, _, _, hpw => by simpa [callPostAux] using hpw
  | _ :: _, [], _, _, _, _, _, _, hpw => by simpa [callPostAux] using hpw
  | (pm, t) :: ps, a :: as, i, Γ, Γc, hz, hdv, hab, hpw => by
    obtain ⟨Ea, hEa, hpo⟩ := hz ((pm, t), a) (by simp)
    have hz' : ∀ pa ∈ ps.zip as, ∃ Ea, Γa pa.2 = some Ea ∧ paramOK pa.1.1 pa.1.2 Ea :=
      fun pa hpa => hz pa (by simp [hpa])
    have hdv' : ∀ pa ∈ ps.zip as, ∀ b, pa.1.1 = .inout b → ∀ Ea, Γa pa.2 = some Ea → Ea.dbind = true →
        pa.1.2.holdsView = false := fun pa hpa => hdv pa (by simp [hpa])
    have hae0 : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
    cases pm with
    | inp => exact callPostAux_lift h hab0 houts hargs hvs ps as (i + 1) Γ Γc hz' hdv' hab hpw
    | sink =>
      obtain ⟨_, hm, _⟩ := hpo
      have hrb : Ea.mode ≠ .rootb := by rw [hm]; simp
      -- (a moved argument owns its slot: no region)
      have hnp : S.isPi a = false := hab0.notPi hEa (by rw [hm]; simp)
      have hae : argE (S.canon Γa) (S.ρ a) = S.subE (S.liftE a Ea) := argE_canons h hEa hnp
      simp only [callPostAux, List.map_cons]
      apply callPostAux_lift h hab0 houts hargs hvs ps as (i + 1) _ _ hz' hdv'
      · refine (hab.kill _ _ _).setE (by simp [hae0, hrb]) (fun b hb => ?_) (fun bh hb => ?_)
          (fun bh hb => ?_) (fun _ _ hf => absurd hf (by simp [hae0, hm]))
          (by simp only [hae0]; exact hab0.2.2.2.1 a Ea hEa)
        · simp [hae0, hm] at hb
        · obtain ⟨E, hE, hmE, _⟩ := hab0.2.2.1 a bh hb
          rw [hEa] at hE; cases hE; rw [hm] at hmE; cases hmE
        · obtain ⟨E, hE, hmE, _⟩ := hab0.2.2.1 a bh hb
          rw [hEa] at hE; cases hE; rw [hm] at hmE; cases hmE
      · rw [canon_setEs h _ hnp, canon_kill h hab (allowed_own hab0 hEa hm _ _) hnp (hab0.notReg hEa (by rw [hm]; simp)), hae, hae0,
          liftE_moved _ hrb]
        exact PW.setE (hpw.kill _ _ _) (EntryWeaker.refl _)
    | inout b =>
      obtain ⟨ht, hcan, _⟩ := hpo
      have hrb : Ea.mode ≠ .rootb := by
        rcases hcan with hm | ⟨b', hm, _⟩ <;> rw [hm] <;> simp
      -- (a changed argument owns its slot: no region)
      have hnp : S.isPi a = false := hab0.notPi hEa (by
        rcases hcan with hm | ⟨b', hm, _⟩ <;> rw [hm] <;> simp)
      have hae : argE (S.canon Γa) (S.ρ a) = S.subE (S.liftE a Ea) := argE_canons h hEa hnp
      simp only [callPostAux, List.map_cons]
      apply callPostAux_lift h hab0 houts hargs hvs ps as (i + 1) _ _ hz' hdv'
      · refine (hab.kill _ _ _).setE (by simp [hae0, hrb]) (fun b' hb => ?_) (fun bh hb => ?_)
          (fun bh hb => ?_) (fun _ _ hf => ?_) (by simp only [hae0]; exact hab0.2.2.2.1 a Ea hEa)
        · simp only [hae0] at hb ⊢
          exact hab0.2.1 a Ea b' hEa hb
        · obtain ⟨E, hE, hmE, _⟩ := hab0.2.2.1 a bh hb
          rw [hEa] at hE; cases hE; simp only [hae0]; exact hmE
        · obtain ⟨E, hE, _, htE, _⟩ := hab0.2.2.1 a bh hb
          rw [hEa] at hE; cases hE; simp only [hae0]; exact htE
        · -- a fixed `inout` argument holds nothing, and still holds nothing
          simp only [hae0] at hf
          have hf0 : Ea.fixed := hf
          obtain ⟨hl0, hh0⟩ := hab0.fixed hEa hf0 hrb
          have hv0 : Ea.ty.holdsView = false := by
            rcases hf0 with h' | ⟨_, _, _, h'⟩
            · exact absurd h' hrb
            · exact h'
          have hsv : t.holdsView = false := by
            have h' := hv0; rw [ht] at h'; exact h'
          simp only [hae0, hsv]; exact ⟨hl0, by simp [hh0]⟩
      · have hal := allowed_canDo' hab0 hEa hcan
        rw [ht] at hal
        rw [canon_setEs h _ hnp, canon_kill h hab hal hnp
          (hab0.notReg hEa (fun h' => by have := hcan.ownSlot; rw [h'] at this; cases this)), hae, hae0]
        refine PW.setE (hpw.kill _ _ _) ?_
        -- AGORA-937 (3d): what the caller's context adds, substituted, is among what
        -- the lift adds, substituted (`outHeld_lift`, `heldOfArgs_lift`)
        have h1 := outHeld_lift h hab0 houts hargs hvs i
        have h2 := heldOfArgs_lift h hab0 (fun a ha => by
          obtain ⟨j, hj, rfl⟩ := mem_args ha; exact hargs j hj) hvs
        by_cases hv : t.holdsView = true
        · have hnb : (Ea.mode == Mode.bor) = false := by
            rcases hcan with h1 | ⟨b', h1, _⟩ <;> simp [h1]
          have hoA : ownHeld Ea.mode.ownSlot Ea.ty S.A = S.A := by rw [ht]; simp [ownHeld, hv]
          have hheld : (S.subE (S.liftE a Ea)).held ++ outHeld (S.canon Γa) fn (args.map S.ρ) i ++
              heldOfArgs (S.canon Γa) (args.map S.ρ) ⊆
              (S.subE (S.liftE a { Ea with heldFresh := false, held := Ea.held ++ outHeld Γa fn args i ++ heldOfArgs Γa args })).held := by
            have hl0 : (S.subE (S.liftE a Ea)).held = (rds S.ρ Ea.held ++ S.A).flatMap S.subD := by
              simp only [subE_held, liftE, hrb, ↓reduceIte, heldA, hnb, Bool.and_false, Bool.false_and,
                Bool.false_eq_true, hoA]
            have hl1 : (S.subE (S.liftE a { Ea with heldFresh := false, held := Ea.held ++ outHeld Γa fn args i ++ heldOfArgs Γa args })).held =
                (rds S.ρ (Ea.held ++ outHeld Γa fn args i ++ heldOfArgs Γa args) ++ S.A).flatMap S.subD := by
              simp only [subE_held, liftE, hrb, ↓reduceIte, heldA, hnb, Bool.and_false, Bool.false_and,
                Bool.false_eq_true, hoA]
            rw [hl0, hl1]
            exact app_liftS (S := S) (app_liftS (S := S) (List.Subset.refl _) h1) h2
          simp only [hv, ↓reduceIte]
          refine EntryWeaker.mk' ?_ ?_ ?_ ?_ ?_ hheld (hdh := fun hh => by
            have hdb : Ea.dbind = true := by simpa [subE_dbind, liftE, hrb] using hh
            exact absurd (hdv ((.inout b, t), a) (by simp) b rfl Ea hEa hdb) (by simp [hv]))
            (hf := fun _ _ hb _ => absurd hb (by
              rcases hcan with h1 | ⟨b', h1, _⟩ <;> simp [subE_mode, liftE, h1, liftMode]))
            (hg := fun _ hb _ => absurd hb (by
              rcases hcan with h1 | ⟨b', h1, _⟩ <;> simp [subE_mode, liftE, h1, liftMode]))
          · simp [liftE, hrb]
          · simp [liftE, hrb]
          · intro hf
            exact liftE_not_fixed (S := S) (v := a) hrb (by simpa using hf)
          · simp [liftE, hrb]
          · intro _; simp [liftE, hrb]
        · simp only [hv, Bool.false_eq_true, ↓reduceIte]
          have : ({ Ea with heldFresh := Ea.heldFresh, held := Ea.held } : Entry) = Ea := rfl
          rw [this]; exact EntryWeaker.refl _

theorem mem_zip_getD {ps : List (PMode × Ty)} {as : List Var} {pa : (PMode × Ty) × Var}
    (h : pa ∈ ps.zip as) : ∃ k, ∃ hk : k < ps.length, k < as.length ∧ pa = (ps[k], as.getD k 0) := by
  obtain ⟨k, hk, he⟩ := List.getElem_of_mem h
  have hk1 : k < ps.length := by simp at hk; omega
  have hk2 : k < as.length := by simp at hk; omega
  refine ⟨k, hk1, hk2, ?_⟩
  rw [← he]; simp [List.getD, hk2]

/-- AGORA-937: a dependency of a substituted entry on a callee binding was
    one of the entry: what a region stands for is the frame's. -/
theorem mem_subE_ρ (h : S.OK) {E : Entry} {d : Dep} {w : Var} (hd : d ∈ (S.subE E).vdeps)
    (hdr : d.root = S.ρ w) : d ∈ E.vdeps := by
  rw [subE_vdeps] at hd
  obtain ⟨d1, hd1, hdd⟩ := List.mem_flatMap.mp hd
  rcases S.subD_frame h hdd with rfl | ⟨hout, _⟩
  · exact hd1
  · exact absurd hdr.symm (hout w)

/-- ... so the substitution adds no callee root, in memory or at all. -/
theorem roots_subE_ρ (h : S.OK) {E : Entry} {w : Var} (hr : S.ρ w ∈ roots (S.subE E).vdeps) :
    S.ρ w ∈ roots E.vdeps := by
  obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
  exact List.mem_map.mpr ⟨d, S.mem_subE_ρ h hd hdr, hdr⟩

/-- ... nor to a list of dependencies. -/
theorem roots_flatMap_subD_ρ (h : S.OK) {X : List Dep} {w : Var} (hr : S.ρ w ∈ roots (X.flatMap S.subD)) :
    S.ρ w ∈ roots X := by
  obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
  obtain ⟨d1, hd1, hdd⟩ := List.mem_flatMap.mp hd
  rcases S.subD_frame h hdd with rfl | ⟨hout, _⟩
  · exact List.mem_map.mpr ⟨d, hd1, hdr⟩
  · exact absurd hdr (hout w ∘ Eq.symm)

theorem roots_subE_ρ_mem (h : S.OK) {E : Entry} {w : Var} (hr : S.ρ w ∈ roots (memDeps (S.subE E).vdeps)) :
    S.ρ w ∈ roots (memDeps E.vdeps) := by
  obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
  obtain ⟨hd, hdn⟩ := List.mem_filter.mp hd
  exact List.mem_map.mpr ⟨d, List.mem_filter.mpr ⟨S.mem_subE_ρ h hd hdr, hdn⟩, hdr⟩

theorem roots_liftE_ρ (h : S.OK) (hab : S.AbsOK Γa) {v a : Var} {E : Entry} (hE : Γa v = some E)
    (hn : a ∉ roots E.vdeps) : S.ρ a ∉ roots (S.liftE v E).vdeps := by
  intro hr
  obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
  by_cases hrb : E.mode = .rootb
  · rcases liftE_rootb_ρ h hab hE hrb hd hdr with ⟨b, t, rfl, hb, hpt, hbn, hbr, hf⟩ | ⟨rfl, _⟩
    · exact hn (List.mem_map.mpr ⟨⟨a, .name b t⟩, abs_sym hab hE hrb hf (h.sym_of a b t hb hpt hbn hbr), rfl⟩)
    · -- its own region, by its handle
      rcases liftE_rootb_dep h hab hE hrb hd with _ | ⟨u, he, _, hu⟩
      · obtain ⟨b, t, he, _⟩ := pe_ρ h ‹_› rfl; exact absurd (congrArg Dep.kind he) (by simp)
      · have : u = a := h.inj _ _ (congrArg Dep.root he).symm; subst this
        exact hn (List.mem_map.mpr ⟨⟨u, .self⟩, by simp [Entry.vdeps, hrb, Mode.ownSlot, hu], rfl⟩)
  · rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
    · apply hn
      have : d0.root = a := h.inj _ _ hdr
      exact this ▸ List.mem_map_of_mem hd0
    · exact A_out h ha a hdr.symm

/-- ... and in memory: a symbolic name is a name. -/
theorem roots_liftE_ρ_mem (h : S.OK) (hab : S.AbsOK Γa) {v a : Var} {E : Entry} (hE : Γa v = some E)
    (hn : a ∉ roots (memDeps E.vdeps)) : S.ρ a ∉ roots (memDeps (S.liftE v E).vdeps) := by
  intro hr
  obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
  obtain ⟨hd, hdn⟩ := List.mem_filter.mp hd
  by_cases hrb : E.mode = .rootb
  · rcases liftE_rootb_ρ h hab hE hrb hd hdr with ⟨b, t, rfl, _⟩ | ⟨rfl, _⟩
    · simp [Kind.isName] at hdn
    · -- its own region, by its handle, which the callee's entry holds
      rcases liftE_rootb_dep h hab hE hrb hd with hd' | ⟨u, he, _, hu⟩
      · obtain ⟨b, t, he, _⟩ := pe_ρ h hd' rfl; exact absurd (congrArg Dep.kind he) (by simp)
      · have : u = a := h.inj _ _ (congrArg Dep.root he).symm; subst this
        exact hn (List.mem_map.mpr ⟨⟨u, .self⟩, List.mem_filter.mpr
          ⟨by simp [Entry.vdeps, hrb, Mode.ownSlot, hu], by simp [Kind.isName]⟩, rfl⟩)
  · rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
    · apply hn
      have : d0.root = a := h.inj _ _ hdr
      exact this ▸ List.mem_map_of_mem (List.mem_filter.mpr ⟨hd0, hdn⟩)
    · exact A_out h ha a hdr.symm

/-- The context after a call's parameters are handed back is made of the
    entries before, of the same mode, and (for a borrowed one) of the same
    dependencies: only the arguments moved or changed, none of them borrowed,
    are rebound. -/
theorem callPostAux_entry {Γ0 : Ctx} {fn : Fn} {args : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ pa ∈ ps.zip as, pa.1.1.moves = true → ∃ E0, Γ0 pa.2 = some E0 ∧ E0.mode ≠ .rootb) →
      (∀ v E1, Γ v = some E1 → ∃ E0, Γ0 v = some E0 ∧ E1.mode = E0.mode ∧
        (E0.mode = .rootb → E1.vdeps = E0.vdeps)) →
      ∀ v E, callPostAux Γ0 fn args ps as i Γ v = some E →
        ∃ E0, Γ0 v = some E0 ∧ E.mode = E0.mode ∧ (E0.mode = .rootb → E.vdeps = E0.vdeps) := by
  intro ps
  induction ps with
  | nil => intro as i Γ _ hI v E hv; cases as <;> exact hI v E hv
  | cons q ps ih =>
    intro as i Γ hz hI v E hv
    obtain ⟨pm, t⟩ := q
    cases as with
    | nil => cases pm <;> exact hI v E hv
    | cons a as =>
      have hz' : ∀ pa ∈ ps.zip as, pa.1.1.moves = true → ∃ E0, Γ0 pa.2 = some E0 ∧ E0.mode ≠ .rootb :=
        fun pa hpa => hz pa (by simp [hpa])
      -- killing keeps modes and dependencies
      have hIk : ∀ e hv, ∀ v E1, A2.kill e hv a Γ v = some E1 → ∃ E0, Γ0 v = some E0 ∧
          E1.mode = E0.mode ∧ (E0.mode = .rootb → E1.vdeps = E0.vdeps) := by
        intro e hv v E1 h1
        simp only [A2.kill] at h1
        obtain ⟨E2, h2, rfl⟩ := Option.map_eq_some_iff.mp h1
        obtain ⟨E0, h0, hm0, hvd⟩ := hI v E2 h2
        exact ⟨E0, h0, by rw [killE_mode, hm0], fun hr => by rw [killE_vdeps, hvd hr]⟩
      have hset : pm.moves = true → ∀ (E' : Entry) (hm : E'.mode = (argE Γ0 a).mode) (e hv),
          ∀ v E1, setE (A2.kill e hv a Γ) a E' v = some E1 → ∃ E0, Γ0 v = some E0 ∧
            E1.mode = E0.mode ∧ (E0.mode = .rootb → E1.vdeps = E0.vdeps) := by
        intro hpm E' hm e hv v E1 h1
        by_cases hva : v = a
        · subst hva
          simp only [A2.setE, upd_same, Option.some.injEq] at h1; subst h1
          obtain ⟨E0, h0, hrb⟩ := hz ((pm, t), v) (by simp) hpm
          have hae : argE Γ0 v = E0 := by unfold argE; rw [h0]; rfl
          exact ⟨E0, h0, by rw [hm, hae], fun hr => absurd hr hrb⟩
        · simp only [A2.setE, upd_ne _ _ hva] at h1; exact hIk _ _ v E1 h1
      cases pm with
      | inp => exact ih as (i + 1) Γ hz' hI v E hv
      | sink =>
        simp only [callPostAux] at hv
        exact ih as (i + 1) _ hz' (hset rfl _ (by rfl) _ _) v E hv
      | inout b =>
        simp only [callPostAux] at hv
        exact ih as (i + 1) _ hz' (hset rfl _ (by rfl) _ _) v E hv

/-- No entry of the caller's view is an `inout` one: the callee's `inout`
    parameters are the caller's own bindings. -/
theorem canon_noio (h : S.OK) {y : Var} {E : Entry} (hy : S.canon Γa y = some E) (b : Eff) :
    E.mode ≠ .inout b := by
  rcases canon_cases_sub h Γa y with ⟨v, rfl, _, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨_, hc⟩
  · rw [hc] at hy
    cases hE : Γa v with
    | none => rw [hE] at hy; cases hy
    | some E0 =>
      rw [hE] at hy; simp only [Option.map_some, Option.some.injEq, Function.comp] at hy; subst hy
      rw [subE_mode]
      by_cases hrb : E0.mode = .rootb
      · simp only [liftE, hrb, ↓reduceIte]; rw [h.pe_rb]; simp
      · rw [liftE_mode v hrb]; cases E0.mode <;> simp [liftMode]
  · rw [hc] at hy; cases hy
  · rw [hc] at hy; exact h.Φio y E b hy

/-- A symbolic name's change, where the call places it, ends nothing fixed
    after the call's parameters are handed back: a borrowed binding reaches
    the `inout` argument only by name, and the parameter is not replaced. -/
theorem sym_quiet (h : S.OK) (_hab : S.AbsOK Γa) {w : Var} {b : Eff}
    (hb : S.bnd w = some (b, false)) (hbr : b ≠ .replace) {fn : Fn} {args : List Var}
    (hz : ∀ pa ∈ fn.params.zip (args.map S.ρ), pa.1.1.moves = true →
      ∃ E0, S.canon Γa pa.2 = some E0 ∧ E0.mode ≠ .rootb) :
    ∀ v E, callPostAux (S.canon Γa) fn (args.map S.ρ) fn.params (args.map S.ρ) 0 (S.canon Γa) v = some E →
      E.fixed → E.live = true → hits b false (S.ρ w) E = false := by
  intro v E hv hf _
  obtain ⟨E0, h0, hm, hvd⟩ := callPostAux_entry fn.params (args.map S.ρ) 0 (S.canon Γa) hz
    (fun v E1 h1 => ⟨E1, h1, rfl, fun _ => rfl⟩) v E hv
  have hrb : E0.mode = .rootb := by
    rcases hf with hf | ⟨b', hm', _⟩
    · rw [← hm]; exact hf
    · exact absurd (hm ▸ hm') (canon_noio h h0 b')
  refine hits_false_of fun d hd hdr => ?_
  rw [hvd hrb] at hd
  rcases canon_cases_sub h Γa v with ⟨v', rfl, _, hc⟩ | ⟨v', rfl, _, hc⟩ | ⟨_, hc⟩
  · rw [hc] at h0
    cases hE : Γa v' with
    | none => rw [hE] at h0; cases h0
    | some E1 =>
      rw [hE] at h0; simp only [Option.map_some, Option.some.injEq, Function.comp] at h0; subst h0
      have hrb1 : E1.mode = .rootb := (liftE_rootb h).mp (by rwa [subE_mode] at hrb)
      rcases S.mem_subE_vdeps_A h hd with hd | hA
      · rcases liftE_rootb_ρ h _hab hE hrb1 hd hdr with ⟨b', t, rfl, hb', _, _, _, _⟩ | ⟨rfl, _⟩
        · rw [hb] at hb'; simp only [Option.some.injEq, Prod.mk.injEq] at hb'
          exact kills_isName hbr false rfl
        · -- a region by its handle: a change that is no replacement keeps a handle
          cases b <;> simp_all [Eff.kills]
      · exact absurd hdr.symm (B_out h hA w)
  · rw [hc] at h0; cases h0
  · rw [hc] at h0
    obtain ⟨b', hv', hb', hk⟩ := h.Φsat v E0 h0 (h.Φrb v E0 h0 hrb) (Or.inr hrb) d hd w hdr.symm
    rw [hb] at hb'; simp only [Option.some.injEq, Prod.mk.injEq] at hb'
    obtain ⟨rfl, rfl⟩ := hb'
    exact hk

theorem paramOK_lift (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    {pm : PMode} {t : Ty} (hp : paramOK pm t E) : paramOK pm t (S.liftE v E) := by
  cases pm with
  | inp => show _ = _; rw [liftE_ty' h hab hE]; exact hp
  | sink =>
    obtain ⟨ht, hm, hs⟩ := hp
    have hrb : E.mode ≠ .rootb := by rw [hm]; simp
    exact ⟨by rw [liftE_ty v hrb]; exact ht, by rw [liftE_mode v hrb, hm]; rfl, hs⟩
  | inout b =>
    obtain ⟨ht, hcan, hs⟩ := hp
    have hrb : E.mode ≠ .rootb := by rcases hcan with hm | ⟨b', hm, _⟩ <;> rw [hm] <;> simp
    exact ⟨by rw [liftE_ty v hrb]; exact ht, by rw [liftE_mode v hrb]; exact canDo_lift hcan, hs⟩

/-- AGORA-937: a parameter's check reads only the type and the mode, which
    the substitution keeps. -/
theorem paramOK_subE {pm : PMode} {t : Ty} {E : Entry} (hp : paramOK pm t E) : paramOK pm t (S.subE E) := by
  cases pm <;> exact hp

theorem AbsOK.callPostAux {Γa : Ctx} (hab0 : S.AbsOK Γa) {fn : Fn} {args : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ pa ∈ ps.zip as, ∃ Ea, Γa pa.2 = some Ea ∧ paramOK pa.1.1 pa.1.2 Ea) →
      S.AbsOK Γ → S.AbsOK (A2.callPostAux Γa fn args ps as i Γ)
  | [], _, _, _, _, hab => by simpa [A2.callPostAux] using hab
  | _ :: _, [], _, _, _, hab => by simpa [A2.callPostAux] using hab
  | (pm, t) :: ps, a :: as, i, Γ, hz, hab => by
    obtain ⟨Ea, hEa, hpo⟩ := hz ((pm, t), a) (by simp)
    have hz' : ∀ pa ∈ ps.zip as, ∃ Ea, Γa pa.2 = some Ea ∧ paramOK pa.1.1 pa.1.2 Ea :=
      fun pa hpa => hz pa (by simp [hpa])
    have hae0 : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
    cases pm with
    | inp => exact AbsOK.callPostAux hab0 ps as (i + 1) Γ hz' hab
    | sink =>
      obtain ⟨_, hm, _⟩ := hpo
      simp only [A2.callPostAux]
      exact AbsOK.callPostAux hab0 ps as (i + 1) _ hz'
        ((hab.kill _ _ _).setE' hab0 hEa (by simp [hae0]) (by simp [hae0]) (by simp [hae0, hm])
          (fun hf => absurd hf (by simp [hae0, hm])))
    | inout b =>
      obtain ⟨ht, hcan, _⟩ := hpo
      have hrb : Ea.mode ≠ .rootb := by
        rcases hcan with hm | ⟨b', hm, _⟩ <;> rw [hm] <;> simp
      simp only [A2.callPostAux]
      exact AbsOK.callPostAux hab0 ps as (i + 1) _ hz'
        ((hab.kill _ _ _).setE' hab0 hEa (by simp [hae0]) (by simp [hae0]) (by simp [hae0, hrb])
          (fun hf => by
            simp only [hae0] at hf ⊢
            have hf0 : Ea.fixed := hf
            obtain ⟨hl0, hh0⟩ := hab0.fixed hEa hf0 hrb
            have hv0 : t.holdsView = false := by
              rcases hf0 with h' | ⟨_, _, _, h'⟩
              · exact absurd h' hrb
              · rw [ht] at h'; exact h'
            simp [hv0, hl0, hh0]))

/-- AGORA-937 (turn-on 2): with no memory frozen (`S.R = []`), what each
    region stands for is nothing (`σ_sub`). -/
theorem σ_nil_of_R (h : S.OK) (hR : S.R = []) (v : Var) : S.σ v = [] :=
  List.eq_nil_of_subset_nil fun d hd => by
    have := h.σ_sub v hd; rw [hR] at this; simp [allKinds] at this

/-- AGORA-937 (turn-on 2): ... so a dependency a substituted entry holds was
    held, and is on no region: one on a region is dropped (a name) or
    replaced by what the region stands for, nothing. -/
theorem mem_subE_held_notPi_of_R (h : S.OK) (hR : S.R = []) {X : Entry} {d : Dep}
    (hd : d ∈ (S.subE X).held) : d ∈ X.held ∧ ∀ v, S.inv d.root = some v → S.isPi v = false := by
  rw [subE_held] at hd
  obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp hd
  unfold subD at hde
  split at hde
  · rename_i v hv
    cases hp : S.isPi v
    · rw [hp] at hde; simp only [Bool.false_eq_true, ↓reduceIte, List.mem_singleton] at hde
      subst hde
      exact ⟨he, fun w hw => by rw [hv] at hw; cases hw; exact hp⟩
    · rw [hp, S.σ_nil_of_R h hR] at hde
      simp at hde
  · rename_i hv
    simp only [List.mem_singleton] at hde
    subst hde
    exact ⟨he, fun w hw => by rw [hv] at hw; cases hw⟩

/-- Agora #295, AGORA-937 (turn-on 2): the lift of a call's `ThruFn`
    premise. In the callee's body the arguments may hold views of the
    callee's own regions only; where the call places the body, a region
    stands for what the outer call's arguments held, and that is nothing
    when the outer call passed no views (`S.R = []`): so the lifted call
    passes no views, which is the premise there (`callR_regions_of_nil`). -/
theorem callR_canon (h : S.OK) (hab : S.AbsOK Γa) {args : List Var} (hR : S.R = [])
    (hc : ∀ r ∈ callR Γa args, ∃ E, Γa r = some E ∧ E.mode = .region)
    (hvs : ∀ a ∈ args, S.isPi a = false) :
    ∀ r ∈ callR (S.canon Γa) (args.map S.ρ), ∃ E, S.canon Γa r = some E ∧ E.mode = .region := by
  -- with no views passed, what the arguments held is names only
  have hA : ∀ d ∈ S.A, d.kind.isName = true := by
    intro d hd
    rcases List.mem_append.mp hd with hd | hd
    · rw [S.Rf_nil h hR] at hd; simp [compAll] at hd
    · exact h.N_name d hd
  intro r hr
  obtain ⟨a', ha', hty, hr⟩ := mem_callR.mp hr
  obtain ⟨a, ha, rfl⟩ := List.mem_map.mp ha'
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
  have hdn : d.kind.isName = false := by simpa using (List.mem_filter.mp hd).2
  have hdh := (List.mem_filter.mp hd).1
  cases hE : Γa a with
  | none =>
    exfalso; apply hty; unfold argE; rw [canon_ρs h _ (hvs a ha), hE]; rfl
  | some E =>
    rw [argE_canons h hE (hvs a ha)] at hty hdh
    rw [subE_ty] at hty
    obtain ⟨hdh, hdnp⟩ := S.mem_subE_held_notPi_of_R h hR hdh
    by_cases hrb : E.mode = .rootb
    · -- AGORA-937 (3d): a borrowed parameter: its own memory, renamed (its region,
      -- by its handle), and its argument's names
      simp only [RSetup.liftE, hrb, ↓reduceIte] at hdh
      rcases List.mem_append.mp hdh with hdr | hdA
      · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hdr
        obtain ⟨_, _, R, hRv, hh⟩ := hab.1 a E hE hrb
        replace hd0 := (List.mem_filter.mp hd0).1
        rw [hh] at hd0
        rcases List.mem_append.mp hd0 with hd0 | hd0
        · obtain ⟨_, hreg⟩ := hRv d0 hd0
          obtain ⟨Er, hEr, hm⟩ := hab.2.2.2.2.1 _ hreg
          cases hgh : S.ghost
          · have hpi : S.isPi d0.root = true := by rw [hab.2.2.2.2.2, hreg, hgh]; rfl
            rw [hdnp d0.root (by simp only [Dep.ren]; exact S.inv_ρ h _)] at hpi; cases hpi
          · refine ⟨S.subE (S.liftE d0.root Er), ?_, ?_⟩
            · simp only [Dep.ren]; rw [canon_ρs h Γa (hab.ghost_notPi hgh _), hEr]; rfl
            · rw [subE_mode, liftE_mode _ (by rw [hm]; simp), hm]; rfl
        · split at hd0
          · obtain ⟨w, b, t, rfl, _⟩ := h.sym_ok d0 hd0
            simp [Dep.ren, Kind.isName] at hdn
          · cases hd0
      · split at hdA
        · have := (List.mem_filter.mp hdA).2; rw [hdn] at this; cases this
        · rename_i hpr
          rcases h.pe_held a d hdA with hdA | ⟨hds, _⟩ | ⟨_, hr⟩
          · rw [hA d hdA] at hdn; cases hdn
          · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hds
            obtain ⟨w, b, t, rfl, _⟩ := h.sym_ok d0 hd0
            simp [Dep.ren, Kind.isName] at hdn
          · rw [hr] at hpr; cases hpr rfl
    · simp only [RSetup.liftE, hrb, ↓reduceIte] at hty hdh
      rcases List.mem_append.mp hdh with hdr | hdo
      · -- what the argument held itself, renamed: a region's, by the
        -- premise, and so dropped by the substitution
        obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hdr
        have hm : d0 ∈ memDeps (argE Γa a).held := by
          unfold argE; rw [hE]
          exact List.mem_filter.mpr ⟨hd0, by simpa [Dep.ren] using hdn⟩
        have : d0.root ∈ callR Γa args :=
          mem_callR.mpr ⟨a, ha, by unfold argE; rw [hE]; exact hty, List.mem_map_of_mem hm⟩
        obtain ⟨Er, hEr, hreg⟩ := hc _ this
        cases hgh : S.ghost
        · -- substituted: a region's dependency is dropped, so none is here
          have hpi : S.isPi d0.root = true := by
            rw [hab.2.2.2.2.2, (hab.2.2.2.1 _ Er hEr).1.mp hreg, hgh]; rfl
          rw [hdnp d0.root (by simp only [Dep.ren]; exact S.inv_ρ h _)] at hpi
          cases hpi
        · -- AGORA-937 stage 3, lifted as a ghost binding: the region,
          -- renamed, is a region binding where the call places the body
          refine ⟨S.subE (S.liftE d0.root Er), ?_, ?_⟩
          · simp only [Dep.ren]; rw [canon_ρs h Γa (hab.ghost_notPi hgh _), hEr]; rfl
          · rw [subE_mode, liftE_mode _ (by rw [hreg]; simp), hreg]; rfl
      · -- what the lift adds: names only
        unfold ownHeld at hdo
        split at hdo
        · cases hdo
        · rw [hA d (S.heldA_sub _ hdo)] at hdn; cases hdn

theorem A_names (h : S.OK) (hR : S.R = []) : ∀ d ∈ S.A, d.kind.isName = true := by
  intro d hd
  rcases List.mem_append.mp hd with hd | hd
  · rw [S.Rf_nil h hR] at hd; simp [compAll] at hd
  · exact h.N_name d hd

/-- AGORA-937 B4: **what a lifted argument holds in memory** where the call
    passed no views: what the argument held, renamed. -/
theorem memDeps_lift (h : S.OK) (hab : S.AbsOK Γa) (hR : S.R = []) {a : Var} {E : Entry}
    (hE : Γa a = some E) (hnp : S.isPi a = false) {d : Dep}
    (hd : d ∈ memDeps (argE (S.canon Γa) (S.ρ a)).held) :
    ∃ d0 ∈ memDeps E.held, d = d0.ren S.ρ := by
  rw [argE_canons h hE hnp] at hd
  have hdn : d.kind.isName = false := by simpa using (List.mem_filter.mp hd).2
  obtain ⟨hdh, _⟩ := S.mem_subE_held_notPi_of_R h hR (List.mem_filter.mp hd).1
  have hA := A_names h hR
  by_cases hrb : E.mode = .rootb
  · simp only [RSetup.liftE, hrb, ↓reduceIte] at hdh
    rcases List.mem_append.mp hdh with hdr | hdA
    · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hdr; exact ⟨d0, hd0, rfl⟩
    · split at hdA
      · have := (List.mem_filter.mp hdA).2; rw [hdn] at this; cases this
      · rename_i hpr
        rcases h.pe_held a d hdA with hdA | ⟨hds, _⟩ | ⟨_, hr⟩
        · rw [hA d hdA] at hdn; cases hdn
        · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hds
          obtain ⟨w, b, t, rfl, _⟩ := h.sym_ok d0 hd0
          simp [Dep.ren, Kind.isName] at hdn
        · rw [hr] at hpr; cases hpr rfl
  · rw [liftE_held hrb] at hdh
    rcases List.mem_append.mp hdh with hdr | hdo
    · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hdr
      exact ⟨d0, List.mem_filter.mpr ⟨hd0, by simpa [Dep.ren] using hdn⟩, rfl⟩
    · unfold ownHeld at hdo
      split at hdo
      · cases hdo
      · rw [hA d (S.heldA_sub _ hdo)] at hdn; cases hdn

theorem argE_canon_ty (h : S.OK) (hab : S.AbsOK Γa) {a : Var} (hnp : S.isPi a = false) :
    (argE (S.canon Γa) (S.ρ a)).ty = (argE Γa a).ty := by
  cases hE : Γa a with
  | none => unfold argE; rw [canon_ρs h _ hnp, hE]; rfl
  | some E =>
    rw [argE_canons h hE hnp, subE_ty, liftE_ty' h hab hE]
    unfold argE; rw [hE]; rfl

/-- ... so the roots it passes views of are the call's own, renamed. -/
theorem callR_lift (h : S.OK) (hab : S.AbsOK Γa) (hR : S.R = []) {args : List Var}
    (hvs : ∀ a ∈ args, S.isPi a = false) {r : Var} (hr : r ∈ callR (S.canon Γa) (args.map S.ρ)) :
    ∃ w ∈ callR Γa args, r = S.ρ w := by
  obtain ⟨a', ha', hty, hr⟩ := mem_callR.mp hr
  obtain ⟨a, ha, rfl⟩ := List.mem_map.mp ha'
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
  cases hE : Γa a with
  | none => exact absurd (by unfold argE; rw [canon_ρs h _ (hvs a ha), hE]; rfl) hty
  | some E =>
    obtain ⟨d0, hd0, rfl⟩ := memDeps_lift h hab hR hE (hvs a ha) hd
    refine ⟨d0.root, mem_callR.mpr ⟨a, ha, ?_, ?_⟩, rfl⟩
    · rw [← argE_canon_ty h hab (hvs a ha)]; exact hty
    · unfold argE; rw [hE]; exact List.mem_map_of_mem hd0


/-- A dependency of a lifted argument on a renamed binding that is no
    `inout` parameter: the argument's own, renamed. -/
theorem vdeps_lift_root (h : S.OK) (hR : S.R = []) {a w : Var} {E : Entry} (hE : Γa a = some E)
    (hnp : S.isPi a = false) (hbw : S.bnd w = none) {d : Dep}
    (hd : d ∈ (argE (S.canon Γa) (S.ρ a)).vdeps) (hr : d.root = S.ρ w) :
    ∃ d0 ∈ E.vdeps, d0.root = w ∧ d0.kind = d.kind := by
  rw [argE_canons h hE hnp, subE_vdeps] at hd
  obtain ⟨d1, hd1, hdd⟩ := List.mem_flatMap.mp hd
  have hdd' : d = d1 := by
    rcases S.subD_frame h hdd with e | ⟨hout, _⟩
    · exact e
    · exact absurd hr.symm (hout w)
  subst hdd'
  have hnρ : ∀ e : Dep, (∀ v, S.ρ v ≠ e.root) → e.root = S.ρ w → False := fun e he her => he w her.symm
  have hsym : ∀ e ∈ rds S.ρ S.sym, e.root = S.ρ w → False := fun e he her => by
    obtain ⟨w', b, t, rfl, hb, _⟩ := sym_ren h he
    have := h.inj _ _ her; subst this; rw [hbw] at hb; cases hb
  have hA : ∀ e ∈ S.A, e.root = S.ρ w → False := fun e he her => by
    rcases List.mem_append.mp he with he | he
    · rw [S.Rf_nil h hR] at he; simp [compAll] at he
    · exact hnρ e (h.N_out e he).1 her
  have hpe : ∀ e ∈ (S.pe a).vdeps, e.root = S.ρ w → False := fun e he her => by
    cases hk : e.kind.isName
    · exact hnρ e (h.pe_out a e he hk).1 her
    · rcases h.pe_names a e he hk with hN | ⟨hs, _⟩
      · exact hnρ e (h.N_out e hN).1 her
      · exact hsym e hs her
  by_cases hrb : E.mode = .rootb
  · have hpm : (S.pe a).mode.ownSlot = false := by rw [h.pe_rb]; rfl
    unfold Entry.vdeps at hd1
    simp only [RSetup.liftE, hrb, ↓reduceIte, hpm, Bool.false_eq_true] at hd1
    rcases List.mem_append.mp hd1 with hp | hh
    · exact (hpe d (by unfold Entry.vdeps; rw [hpm]; exact List.mem_append_left _ hp) hr).elim
    rcases List.mem_append.mp hh with hr' | hp'
    · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hr'
      refine ⟨d0, ?_, h.inj _ _ hr, rfl⟩
      unfold Entry.vdeps; exact List.mem_append_right _ (List.mem_filter.mp hd0).1
    · have hp'' : d ∈ (S.pe a).held := by
        split at hp'
        · exact (List.mem_filter.mp hp').1
        · exact hp'
      exact (hpe d (by unfold Entry.vdeps; rw [hpm]; exact List.mem_append_right _ hp'') hr).elim
  · rcases liftE_vdeps_cases hrb hd1 with ⟨d0, hd0, rfl⟩ | hdA
    · exact ⟨d0, hd0, h.inj _ _ hr, rfl⟩
    · exact (hA d hdA hr).elim

/-- ... and on its path. -/
theorem path_lift_root (h : S.OK) (hR : S.R = []) {a w : Var} {E : Entry} (hE : Γa a = some E)
    (hnp : S.isPi a = false) (hbw : S.bnd w = none) {d : Dep}
    (hd : d ∈ (argE (S.canon Γa) (S.ρ a)).path) (hr : d.root = S.ρ w) :
    ∃ d0 ∈ E.path, d0.root = w := by
  rw [argE_canons h hE hnp, subE_path] at hd
  obtain ⟨d1, hd1, hdd⟩ := List.mem_flatMap.mp hd
  have hdd' : d = d1 := by
    rcases S.subD_frame h hdd with e | ⟨hout, _⟩
    · exact e
    · exact absurd hr.symm (hout w)
  subst hdd'
  by_cases hrb : E.mode = .rootb
  · simp only [RSetup.liftE, hrb, ↓reduceIte] at hd1
    have hpm : (S.pe a).mode.ownSlot = false := by rw [h.pe_rb]; rfl
    cases hk : d.kind.isName
    · exact absurd hr.symm ((h.pe_out a d (by unfold Entry.vdeps; rw [hpm]; exact List.mem_append_left _ hd1) hk).1 w)
    · rcases h.pe_names a d (by unfold Entry.vdeps; rw [hpm]; exact List.mem_append_left _ hd1) hk with hN | ⟨hs, _⟩
      · exact absurd hr.symm ((h.N_out d hN).1 w)
      · obtain ⟨w', b, t, rfl, hb, _⟩ := sym_ren h hs
        have := h.inj _ _ hr; subst this; rw [hbw] at hb; cases hb
  · simp only [RSetup.liftE, hrb, ↓reduceIte] at hd1
    rcases List.mem_append.mp hd1 with hr' | hA
    · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hr'
      exact ⟨d0, hd0, h.inj _ _ hr⟩
    · split at hA
      · cases hA
      · rcases List.mem_append.mp hA with hA | hA
        · rw [S.Rf_nil h hR] at hA; simp [compAll] at hA
        · exact absurd hr.symm ((h.N_out d hA).1 w)


/-- AGORA-937 B4: **a through-call's premise, where the call places the
    callee** (the outer call passed no views): what the arguments pass views
    of is the callee's own, renamed, and nothing of the frame depends on it. -/
theorem callThruOK_canon (h : S.OK) (hab : S.AbsOK Γa) (hR : S.R = []) {P : Prog} {Fa : List Var}
    {fn : Fn} {args : List Var} (hlen : args.length = fn.params.length)
    (hexA : ∀ a ∈ args, ∃ Ea, Γa a = some Ea) (hvs : ∀ a ∈ args, S.isPi a = false)
    (hpost : PW (callPost (S.canon Γa) fn (args.map S.ρ)) (S.canon (callPost Γa fn args)))
    (hc : CallThruOK P Γa Fa fn args) : CallThruOK P (S.canon Γa) S.Fc fn (args.map S.ρ) := by
  obtain ⟨hcalls, hnf, hnv, hvw, hio, hw⟩ := hc
  have hgi : ∀ i, i < fn.params.length → ∃ E, Γa (args.getD i 0) = some E ∧ S.isPi (args.getD i 0) = false ∧
      (args.map S.ρ).getD i 0 = S.ρ (args.getD i 0) := fun i hi => by
    have hia : i < args.length := hlen ▸ hi
    obtain ⟨E, hE⟩ := hexA _ (getD_mem' hia)
    exact ⟨E, hE, hvs _ (getD_mem' hia), getD_map hia _⟩
  have hae : ∀ {a : Var} {E : Entry}, Γa a = some E → argE Γa a = E := fun hE => by unfold argE; rw [hE]; rfl
  refine ⟨hcalls, fun a' ha' ms q => ?_, fun i hi hhv => ?_, fun i hi hhv hty e he => ?_, hio, fun w' hw' => ?_⟩
  · obtain ⟨a, ha, rfl⟩ := List.mem_map.mp ha'
    rw [argE_canon_ty h hab (hvs a ha)]; exact hnf a ha ms q
  · obtain ⟨E, hE, hnp, hg⟩ := hgi i hi
    rw [hg, argE_canon_ty h hab hnp]
    rcases hnv i hi hhv with hint | hnil
    · exact Or.inl hint
    · refine Or.inr (List.eq_nil_iff_forall_not_mem.mpr fun d hd => ?_)
      obtain ⟨d0, hd0, _⟩ := memDeps_lift h hab hR hE hnp hd
      rw [hae hE] at hnil; rw [hnil] at hd0; cases hd0
  · obtain ⟨E, hE, hnp, hg⟩ := hgi i hi
    rw [hg] at hty he
    rw [argE_canon_ty h hab hnp] at hty
    obtain ⟨e0, he0, rfl⟩ := memDeps_lift h hab hR hE hnp he
    rw [← hae hE] at he0
    obtain ⟨hk, hdis⟩ := hvw i hi hhv hty e0 he0
    refine ⟨hk, fun j hj hji hhvj htyj e' he' => ?_⟩
    obtain ⟨Ej, hEj, hnpj, hgj⟩ := hgi j hj
    rw [hgj] at htyj he'
    rw [argE_canon_ty h hab hnpj] at htyj
    obtain ⟨e0', he0', rfl⟩ := memDeps_lift h hab hR hEj hnpj he'
    rw [← hae hEj] at he0'
    exact fun heq => hdis j hj hji hhvj htyj e0' he0' (h.inj _ _ heq)
  · obtain ⟨w, hwR, rfl⟩ := callR_lift h hab hR hvs hw'
    obtain ⟨hna, hkind, hpath, hvec, hlive, hdt, -, ⟨Er, t, hEr, hl, hmo, hty, hhv⟩⟩ := hw w hwR
    have hdom : DomTy Γa (callPost Γa fn args) :=
      DomTy.killNames (callPostAux_domTy _ _ _ _ hexA (DomTy.refl Γa)) _
    obtain ⟨E0, hE0, hm0, -⟩ := hdom.2 w Er hEr
    have hreg : S.isReg w = false := by
      cases hr : S.isReg w
      · rfl
      · have := (hab.2.2.2.1 w E0 hE0).1.mpr hr
        rw [← hm0, hmo] at this; cases this
    have hpi : S.isPi w = false := by rw [hab.2.2.2.2.2 w, hreg]; rfl
    have hbw : S.bnd w = none := by
      cases hb : S.bnd w with
      | none => rfl
      | some bh =>
        obtain ⟨E, hE, hmE, _⟩ := hab.2.2.1 w bh hb
        rw [hE0] at hE; cases hE; rw [← hm0, hmo] at hmE; cases hmE
    have hal : Allowed S .dropIn false w := Or.inl hbw
    refine ⟨fun hm => ?_, fun a' ha' d hd hr => ?_, fun a' ha' d hd hr => ?_, fun i hi hinp hr => ?_,
      fun y E hy hlE => ?_, fun y E hy hdE hos => ?_, h.Fcout w, ?_⟩
    · obtain ⟨a, ha, he⟩ := List.mem_map.mp hm
      exact hna (h.inj _ _ he ▸ ha)
    · obtain ⟨a, ha, rfl⟩ := List.mem_map.mp ha'
      obtain ⟨E, hE⟩ := hexA a ha
      obtain ⟨d0, hd0, hr0, hk0⟩ := vdeps_lift_root h hR hE (hvs a ha) hbw hd hr
      rw [← hk0]; exact hkind a ha d0 (by rw [hae hE]; exact hd0) hr0
    · obtain ⟨a, ha, rfl⟩ := List.mem_map.mp ha'
      obtain ⟨E, hE⟩ := hexA a ha
      obtain ⟨d0, hd0, hr0⟩ := path_lift_root h hR hE (hvs a ha) hbw hd hr
      exact hpath a ha d0 (by rw [hae hE]; exact hd0) hr0
    · obtain ⟨E, hE, hnp, hg⟩ := hgi i hi
      rw [hg] at hr
      obtain ⟨e, he, her⟩ := List.mem_map.mp hr
      obtain ⟨e0, he0, rfl⟩ := memDeps_lift h hab hR hE hnp he
      refine hvec i hi hinp (List.mem_map.mpr ⟨e0, by rw [hae hE]; exact he0, h.inj _ _ her⟩)
    · rcases canon_cases_sub h Γa y with ⟨v, rfl, hnp, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨hy', hc⟩
      · rw [hc] at hy
        obtain ⟨E1, hE1, rfl⟩ := Option.map_eq_some_iff.mp hy
        simp only [Function.comp, subE_live, liftE_live] at hlE
        simp only [Function.comp]
        rw [hits_subE h hpi, hits_lift h hab hE1 hal hreg]
        exact hlive v E1 hE1 hlE
      · rw [hc] at hy; cases hy
      · rw [hc] at hy
        by_cases hcd : E.ty ≠ .int ∨ E.mode = .rootb
        · exact hits_false_of fun d hd hr => by
            obtain ⟨b, hv, hb, _⟩ := h.Φsat y E hy hlE hcd d hd w hr.symm
            rw [hbw] at hb; cases hb
        · unfold hits
          have : (E.ty != .int || E.mode == .rootb) = false := by
            simp only [not_or, ne_eq, Decidable.not_not] at hcd
            simp [hcd.1, hcd.2]
          rw [this]; rfl
    · rcases canon_cases_sub h Γa y with ⟨v, rfl, hnp, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨hy', hc⟩
      · rw [hc] at hy
        obtain ⟨E1, hE1, rfl⟩ := Option.map_eq_some_iff.mp hy
        simp only [Function.comp, subE_dtor, subE_mode] at hdE hos ⊢
        rw [liftE_dtor' h] at hdE
        by_cases hrb : E1.mode = .rootb
        · rw [if_pos hrb] at hdE; cases hdE
        rw [if_neg hrb] at hdE
        refine hitsMem_subE h ?_
        rw [hitsMem_lift h hrb]
        rw [liftE_mode _ hrb, liftMode_ownSlot] at hos
        exact hdt v E1 hE1 hdE hos
      · rw [hc] at hy; cases hy
      · rw [hc] at hy
        by_cases hcd : E.ty ≠ .int ∨ E.mode = .rootb
        · unfold hitsMem
          simp only [Bool.and_eq_false_iff, List.any_eq_false]
          refine Or.inr fun d hd hdd => ?_
          simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hdd
          obtain ⟨⟨hr, hn⟩, _⟩ := hdd
          obtain ⟨b, hv, hb, _⟩ := h.Φdt y E hy hdE hos hcd d hd hn w hr.symm
          rw [hbw] at hb; cases hb
        · unfold hitsMem
          have : (E.ty != .int || E.mode == .rootb) = false := by
            simp only [not_or, ne_eq, Decidable.not_not] at hcd
            simp [hcd.1, hcd.2]
          rw [this]; rfl
    · have hc' := canon_some h hEr hpi
      obtain ⟨hn, hwk⟩ := hpost (S.ρ w)
      cases h1 : callPost (S.canon Γa) fn (args.map S.ρ) (S.ρ w) with
      | none => rw [hn.mp h1] at hc'; cases hc'
      | some Er' =>
        have hW := hwk Er' _ h1 hc'
        have hrb : Er.mode ≠ .rootb := by rw [hmo]; simp
        refine ⟨Er', t, rfl, (hW.live (by rw [subE_live, liftE_live]; exact hl)).1, ?_, ?_, hhv⟩
        · rw [← hW.mode, subE_mode, liftE_mode _ hrb, hmo]; rfl
        · rw [← hW.ty, subE_ty, liftE_ty _ hrb, hty]

/-- A call in the callee's body, where the call places it. -/
theorem callT_ren (h : S.OK) (hab : S.AbsOK Γa) {P : Prog} (hP : ProgOK P) {Fa : List Var} {f : Nat}
    {args : List Var} {E : Entry} {Γa1 : Ctx} (hc : CallT P Γa Fa f args E Γa1)
    (hR : ThruFn P f → S.R = []) (hvs : ∀ a ∈ args, S.isPi a = false) :
    ∃ E' Γ', CallT P (S.canon Γa) S.Fc f (args.map S.ρ) E' Γ' ∧ PW Γ' (S.canon Γa1) ∧
      ∀ x, EntryWeaker E' (S.subE (S.liftE x E)) := by
  obtain ⟨fn, hf, hlen, hargs, hnf, hds, rfl, rfl, hg⟩ := hc
  have hfn : FnOK P fn := hP fn (List.mem_of_getElem? hf)
  obtain ⟨_, _, _, _, _, _, hlends, hrholds, houts, _⟩ := hfn
  have hex : ∀ j < args.length, ∃ Ea, Γa (args.getD j 0) = some Ea := by
    intro j hj; obtain ⟨Ea, h1, _⟩ := hargs j (hlen ▸ hj); exact ⟨Ea, h1⟩
  have hexA : ∀ a ∈ args, ∃ Ea, Γa a = some Ea := by
    intro a ha; obtain ⟨j, hj, rfl⟩ := mem_args ha; exact hex j hj
  have hlr : ∀ jk ∈ fn.lends ++ fn.rholds, jk.1 < args.length ∧ jk.2.isName = false := by
    intro jk hjk
    rcases List.mem_append.mp hjk with hj | hj
    · obtain ⟨⟨hl, _⟩, hk⟩ := hlends jk hj; exact ⟨by omega, hk⟩
    · obtain ⟨⟨hl, _⟩, hk⟩ := hrholds jk hj; exact ⟨by omega, hk⟩
  have hou : ∀ o ∈ fn.outHolds, o.2.1 < args.length ∧ o.2.2.isName = false := by
    intro o ho; obtain ⟨⟨hl, _⟩, hk⟩ := houts o ho; exact ⟨by omega, hk⟩
  have hz : ∀ pa ∈ fn.params.zip args, ∃ Ea, Γa pa.2 = some Ea ∧ paramOK pa.1.1 pa.1.2 Ea := by
    intro pa hpa
    obtain ⟨k, hk, _, rfl⟩ := mem_zip_getD hpa
    obtain ⟨Ea, hEa, _, hok, _⟩ := hargs k hk
    exact ⟨Ea, hEa, hok⟩
  have hal : ∀ d ∈ mutNames Γa args, Allowed S d.kind.bound false d.root := by
    intro d hd
    obtain ⟨hcan, ⟨s, hts, hsv⟩, _⟩ := hnf d hd
    cases hE : Γa d.root with
    | none =>
      exfalso; unfold argE at hcan; rw [hE] at hcan
      rcases hcan with hm | ⟨b, hm, _⟩ <;> simp [intE] at hm
    | some E0 =>
      have hae : argE Γa d.root = E0 := by unfold argE; rw [hE]; rfl
      rw [hae] at hcan hts
      have := allowed_canDo hab hE hts hcan
      rwa [hsv] at this
  -- what a closure handed over may change owns its slot: no region
  have hnpN : ∀ d ∈ mutNames Γa args, S.isPi d.root = false := name_kill_not_region hab hnf
  have hpost : PW (callPost (S.canon Γa) fn (args.map S.ρ)) (S.canon (callPost Γa fn args)) := by
    unfold callPost
    rw [canon_killNames h (AbsOK.callPostAux hab fn.params args 0 Γa hz hab) _ hal hnpN
      (fun d hd => name_kill_notReg hab hnf d hd)]
    have hdv : ∀ pa ∈ fn.params.zip args, ∀ b, pa.1.1 = .inout b → ∀ Ea, Γa pa.2 = some Ea →
        Ea.dbind = true → pa.1.2.holdsView = false := by
      intro pa hpa b hb Ea hEa hd
      obtain ⟨k, hk, _, rfl⟩ := mem_zip_getD hpa
      exact absurd hd (by rw [hds.2.2 k hk b hb Ea hEa]; simp)
    refine PW.killNames' (callPostAux_lift h hab hou hex hvs fn.params args 0 Γa _ hz hdv hab (PW.refl _))
      (fun d hd => ?_) (fun d hd => ?_)
    · rcases mutNames_canon_sub h hab hnf hexA hvs d hd with hd | ⟨w, b, t, rfl, hbw, hbr⟩
      · exact Or.inl hd
      · refine Or.inr (sym_quiet h hab hbw hbr fun pa hpa hm => ?_)
        obtain ⟨k, hk, hka, rfl⟩ := mem_zip_getD hpa
        have hka' : k < args.length := by simpa using hka
        obtain ⟨Ea, hEa, _, hok, _⟩ := hargs k hk
        simp only at hm ⊢
        rw [getD_map hka', canon_some h hEa (hvs _ (getD_mem' hka'))]
        refine ⟨_, rfl, ?_⟩
        rw [subE_mode]
        revert hok hm; generalize fn.params[k] = q; obtain ⟨pm, t⟩ := q
        cases pm with
        | inp => intro hm; simp [PMode.moves] at hm
        | sink =>
          intro _ hok
          have hrb : Ea.mode ≠ .rootb := by rw [hok.2.1]; simp
          rw [liftE_mode _ hrb, hok.2.1]; simp [liftMode]
        | inout b' =>
          intro _ hok
          have hrb : Ea.mode ≠ .rootb := by
            rcases hok.2.1 with hm | ⟨_, hm, _⟩ <;> rw [hm] <;> simp
          rw [liftE_mode _ hrb]; cases hm' : Ea.mode <;> simp_all [liftMode]
    · rcases mem_mutNames_canon h hab hexA hvs hd with hd | ⟨hN, hb⟩
      · exact Or.inl hd
      · exact Or.inr (canon_quiet h (AbsOK.callPostAux hab fn.params args 0 Γa hz hab) hN hb)
  refine ⟨_, _, ⟨fn, hf, by simp [hlen], fun i hi => ?_, namesFree_lift h hab hexA hvs hnf,
    CallDtorSafe.canon h hab hexA hlen (fun i hi => by
      obtain ⟨Ea, hEa, _, hok, _⟩ := hargs i hi; exact ⟨Ea, hEa, hok⟩) hal hds hvs, rfl, rfl,
      fun ht => (hg ht).imp (fun hg' => callR_canon h hab (hR ht) hg' hvs)
        (fun hc' => callThruOK_canon h hab (hR ht) hlen hexA hvs hpost hc')⟩, ?_,
    fun x => callRes_lift h hab hlr hex hvs x⟩
  · obtain ⟨Ea, hEa, hl, hok, hmv, _⟩ := hargs i hi
    have hia : i < args.length := hlen ▸ hi
    rw [getD_map hia]
    refine ⟨_, canon_some h hEa (hvs _ (getD_mem' hia)), by rw [subE_live, liftE_live]; exact hl,
      S.paramOK_subE (paramOK_lift h hab hEa hok), fun hm => ?_, fun hpm => ?_⟩
    · obtain ⟨hF, hroot, hsk, hself, hoth⟩ := hmv hm
      refine ⟨h.Fcout _, fun hr => roots_liftE_ρ_mem h hab hEa hroot (roots_subE_ρ_mem h hr),
        fun hs hr => roots_liftE_ρ h hab hEa (hsk hs) (roots_subE_ρ h hr),
        fun b hb d hd hdr => ?_, fun j hj hji => ?_⟩
      · -- the argument's own names on itself: it is not borrowed
        have hd := S.mem_subE_ρ h hd hdr
        have hrb : Ea.mode ≠ .rootb := by
          rw [hb] at hok; rcases hok.2.1 with hm' | ⟨_, hm', _⟩ <;> rw [hm'] <;> simp
        rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
        · exact hself b hb d0 hd0 (h.inj _ _ hdr)
        · exact absurd hdr.symm (A_out h ha _)
      have hja : j < args.length := hlen ▸ hj
      obtain ⟨hne, hnr, hns, hnb⟩ := hoth j hj hji
      obtain ⟨Ej, hEj⟩ := hex j hja
      rw [getD_map hja, argE_canons h hEj (hvs _ (getD_mem' hja))]
      have hae : argE Γa (args.getD j 0) = Ej := by unfold argE; rw [hEj]; rfl
      rw [hae] at hnr hns hnb
      refine ⟨fun e => hne (h.inj _ _ e), fun hr => roots_liftE_ρ_mem h hab hEj hnr (roots_subE_ρ_mem h hr),
        fun hs hr => roots_liftE_ρ h hab hEj (hns hs) (roots_subE_ρ h hr), fun b hb d hd hdr => ?_⟩
      have hd := S.mem_subE_ρ h hd hdr
      -- an `inout` argument reached by name: by the parameter's bound, as
      -- the callee's symbolic name says (or as the callee's own closure does)
      by_cases hrb : Ej.mode = .rootb
      · rcases liftE_rootb_ρ h hab hEj hrb hd hdr with ⟨b', t, rfl, hb', hpt, hbn, hbr, hf⟩ | ⟨rfl, _⟩
        · exact hnb b hb ⟨args.getD i 0, .name b' t⟩
            (abs_sym hab hEj hrb hf (h.sym_of _ b' t hb' hpt hbn hbr)) rfl
        · -- its own region, by its handle, which the callee's entry holds
          rcases liftE_rootb_dep h hab hEj hrb hd with hd' | ⟨u, he, _, hu⟩
          · obtain ⟨b', t, he, _⟩ := pe_ρ h hd' rfl; exact absurd (congrArg Dep.kind he) (by simp)
          · have : u = args.getD i 0 := h.inj _ _ (congrArg Dep.root he).symm; subst this
            exact hnb b hb ⟨args.getD i 0, .self⟩ (by
              unfold Entry.vdeps; simp only [hrb, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte]
              exact List.mem_append_right _ hu) rfl
      · rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
        · exact hnb b hb d0 hd0 (h.inj _ _ hdr)
        · exact absurd hdr.symm (A_out h ha _)
    · refine NoPin.lift h hab fun bh hb => ?_
      obtain ⟨E, hE, hmE, _⟩ := hab.2.2.1 _ bh hb
      rw [hEa] at hE; cases hE
      rcases hpm with hs | hs
      · rw [hs] at hok; obtain ⟨_, hmo, _⟩ := hok; rw [hmo] at hmE; cases hmE
      · rw [hs] at hok; obtain ⟨_, hcan, _⟩ := hok
        rcases hcan with hmo | ⟨b, hmo, hle⟩
        · rw [hmo] at hmE; cases hmE
        · rw [hmo] at hmE; cases hmE
          cases hb1 : bh.1 <;> rw [hb1] at hle <;> simp_all [Eff.le, Eff.leb]
  · exact hpost


/-! ### The callee's contexts stay as the call set them up -/

theorem RhsT.absOK {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1)
    (hab : S.AbsOK Γ) : S.AbsOK Γ1 := by
  cases hr with
  | @moveOwn y Ey hy _ hm _ _ =>
    exact (hab.kill _ _ _).setE' hab hy rfl rfl (by rw [hm]; simp) (fun hf => absurd hf (by simp [hm]))
  | @moveUp y Ey _ _ _ hy _ hm =>
    exact (hab.kill _ _ _).setE' hab hy rfl rfl (by rw [hm]; simp) (fun hf => absurd hf (by simp [hm]))
  | pop => exact hab.kill _ _ _
  | remove => exact hab.kill _ _ _
  | pair hy _ hpa1 hz _ hpa2 _ => exact PushArg.absOK hz hpa2 (PushArg.absOK hy hpa1 hab)
  | inl hy _ hpa _ => exact PushArg.absOK hy hpa hab
  | inr hy _ hpa _ => exact PushArg.absOK hy hpa hab
  | pack hy _ _ hpa => exact PushArg.absOK hy hpa hab
  | arcNew hy _ _ _ _ _ _ hpa => exact PushArg.absOK hy hpa hab
  | lockNew hy _ _ _ _ _ hpa => exact PushArg.absOK hy hpa hab
  | cellNew hy _ _ _ _ _ hpa => exact PushArg.absOK hy hpa hab
  | chanSend _ _ _ hy _ _ hpa => exact PushArg.absOK hy hpa hab
  | lockRestore _ _ _ hy _ _ hpa => exact PushArg.absOK hy hpa hab
  | @takel y Ey _ _ hy _ hm _ _ _ =>
    exact (hab.kill _ _ _).setE' hab hy rfl rfl (by rw [hm]; simp) (fun hf => absurd hf (by simp [hm]))
  | @taker y Ey _ _ hy _ hm _ _ _ =>
    exact (hab.kill _ _ _).setE' hab hy rfl rfl (by rw [hm]; simp) (fun hf => absurd hf (by simp [hm]))
  | @take y Ey _ hy _ _ _ hcan =>
    exact (hab.kill _ _ _).setE' hab hy rfl rfl
      (fun e => by have := hcan.ownSlot; rw [e] at this; cases this) (fun _ => ⟨rfl, rfl⟩)
  | _ => exact hab

theorem CallT.absOK {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    (hc : CallT P Γ F f args E Γ1) (hab : S.AbsOK Γ) : S.AbsOK Γ1 ∧ (E.mode = .own ∨ E.mode = .bor) ∧
      E.live = true := by
  obtain ⟨fn, _, _, hargs, _, _, rfl, rfl, _⟩ := hc
  refine ⟨(AbsOK.callPostAux hab fn.params args 0 Γ (fun pa hpa => ?_) hab).killNames _, ?_, rfl⟩
  · obtain ⟨k, hk, _, rfl⟩ := mem_zip_getD hpa
    obtain ⟨Ea, hEa, _, hok, _⟩ := hargs k hk
    exact ⟨Ea, hEa, hok⟩
  · simp only [callRes, resMode]; split <;> simp

theorem roots_sub {a b : List Dep} (h : a ⊆ b) : roots a ⊆ roots b := by
  intro r hr
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
  exact List.mem_map_of_mem (h hd)

theorem roots_lift_ρ (h : S.OK) {a : Var} {D : List Dep} {L : List Dep} (hD : D ⊆ rds S.ρ L ++ S.A)
    (hn : a ∉ roots L) : S.ρ a ∉ roots D := by
  intro hr
  obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
  rcases List.mem_append.mp (hD hd) with h1 | h1
  · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
    exact hn (h.inj _ _ hdr ▸ List.mem_map_of_mem hd0)
  · exact A_out h h1 a hdr.symm

theorem liftE_vdeps_sub {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) :
    (S.liftE v E).vdeps ⊆ rds S.ρ E.vdeps ++ S.A := by
  intro d hd
  rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
  · exact List.mem_append_left _ (mem_rds.mpr ⟨d0, hd0, rfl⟩)
  · exact List.mem_append_right _ ha

theorem allowed_replace (hab : S.AbsOK Γa) {x : Var} {Ex : Entry} (hx : Γa x = some Ex)
    (hm : Ex.mode = .own ∨ Ex.mode = .bor ∨ Ex.mode = .inout .replace) (hv : Bool) :
    Allowed S .replace hv x := by
  cases hb : S.bnd x with
  | none => exact Or.inl hb
  | some bh =>
    obtain ⟨E, hE, hmE, _⟩ := hab.2.2.1 x bh hb
    rw [hx] at hE; cases hE
    obtain ⟨b, hb'⟩ := bh
    refine Or.inr ⟨b, hb', hb, fun k _ => ?_⟩
    rcases hm with hm | hm | hm <;> rw [hm] at hmE <;> cases hmE
    cases k <;> rfl

/-- ... so a receiver's roots, substituted (for a receiver at no region's
    index). -/
theorem allKinds_recvRoots_subE (h : S.OK) {c : Var} (hnp : S.isPi c = false) (L : Entry) :
    recvDeps (S.ρ c) (S.subE L) ⊆ (recvDeps (S.ρ c) L).flatMap S.subD := by
  intro d hd
  obtain ⟨d0, hd0, k, hk, rfl⟩ := mem_recvDeps.mp hd
  have hkn : k.isName = false := by rcases hk with rfl | rfl | rfl | rfl <;> rfl
  -- AGORA-937 (3d): the substitution composes kinds, and composing is associative
  have hsrc : ∃ e ∈ memDeps (derive (S.ρ c) L .self) ++ memDeps L.held, d0 ∈ S.subD e := by
    rcases List.mem_append.mp hd0 with h1 | h1
    · obtain ⟨h1, hn⟩ := List.mem_filter.mp h1
      obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp (derive_subE h hnp L rfl h1)
      have hen : e.kind.isName = false := by
        rcases S.mem_subD hde with rfl | ⟨v, _, _, e0, _, _, hk'⟩
        · simpa using hn
        · exact hk'
      exact ⟨e, List.mem_append_left _ (List.mem_filter.mpr ⟨he, by simp [hen]⟩), hde⟩
    · obtain ⟨h1, hn⟩ := List.mem_filter.mp h1
      rw [subE_held] at h1
      obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp h1
      have hen : e.kind.isName = false := by
        rcases S.mem_subD hde with rfl | ⟨v, _, _, e0, _, _, hk'⟩
        · simpa using hn
        · exact hk'
      exact ⟨e, List.mem_append_right _ (List.mem_filter.mpr ⟨he, by simp [hen]⟩), hde⟩
  obtain ⟨e, he, hde⟩ := hsrc
  refine List.mem_flatMap.mpr ⟨⟨e.root, comp e.kind k⟩, mem_recvDeps.mpr ⟨e, he, k, hk, rfl⟩, ?_⟩
  rcases S.mem_subD hde with rfl | ⟨v, hv, hp, e0, he0, rfl, hk'⟩
  · rw [S.subD_fix_reKind h (S.subD_idem h hde)]; exact List.mem_singleton_self _
  · have hck : (comp e.kind k).isName = false := comp_isName hk' hkn
    simp only [subD, hv, hp, hck, Bool.false_eq_true, ↓reduceIte, List.mem_map]
    exact ⟨e0, he0, by rw [comp_assoc]⟩

/-- What a call through a package adds to what it returns (`recvRes`). -/
def recvAdd (E : Entry) (X : List Dep) : Entry :=
  { E with path := E.path ++ X, held := ownHeld E.mode.ownSlot E.ty (E.held ++ X), heldFresh := false }

/-- ... keeps a weakening, with what the receiver reaches widened. -/
theorem recvRes_weaker {E' B : Entry} {X Y : List Dep} (hw : EntryWeaker E' B) (hXY : X ⊆ Y)
    (hmo : B.mode = .own ∨ B.mode = .bor) (hdb : B.dbind = false) (hf : B.fresh = false) :
    EntryWeaker (recvAdd E' X) (recvAdd B Y) := by
  unfold recvAdd
  obtain ⟨ht, hm, _, hl, hd, hdbw, hra, _, _, _⟩ := hw
  have hheld : E'.held ⊆ B.held →
      ownHeld E'.mode.ownSlot E'.ty (E'.held ++ X) ⊆ ownHeld B.mode.ownSlot B.ty (B.held ++ Y) := by
    intro h1; rw [hm, ht]; unfold ownHeld; split
    · exact List.Subset.refl _
    · exact append_sub h1 hXY
  refine ⟨ht, hm, fun hfx => ?_, fun hl' => ?_, fun hd' => ?_, hdbw, hra, fun hd' => ?_,
    fun _ _ _ hfr => ?_, fun _ _ hhf => ?_⟩
  · exfalso
    change E'.mode = .rootb ∨ ∃ b, E'.mode = .inout b ∧ b ≠ .replace ∧ E'.ty.holdsView = false at hfx
    rw [← hm] at hfx
    rcases hmo with h1 | h1 <;> rw [h1] at hfx <;> simp at hfx
  · obtain ⟨h1, h2, h3⟩ := hl hl'
    exact ⟨h1, fun ho => append_sub (h2 ho) hXY, hheld h3⟩
  · obtain ⟨h1, h2⟩ := hd hd'; exact ⟨h1, hheld h2⟩
  · exact absurd (show E'.dbind = true from hd') (by rw [← hdbw, hdb]; simp)
  · exact absurd (show B.fresh = true from hfr) (by rw [hf]; simp)
  · exact absurd (show false = true from hhf) (by simp)

theorem subE_recvRes (c : Var) (L B : Entry) :
    S.subE (recvRes c L B) = recvAdd (S.subE B) ((recvDeps c L).flatMap S.subD) := by
  simp only [subE, recvRes, recvAdd, List.flatMap_append]
  unfold ownHeld; split <;> simp [List.flatMap_append]

/-- AGORA-937: `recvRes_lift` with regions, for a receiver at no region's
    index: the lift, substituted, of what the call returns. -/
theorem recvRes_lifts (h : S.OK) (hab : S.AbsOK Γa) {c : Var} {Ec E E' : Entry} (hc : Γa c = some Ec)
    (hnp : S.isPi c = false) (hmo : E.mode = .own ∨ E.mode = .bor) (hE0 : E.dbind = false) (x : Var)
    (hEf : E.fresh = false) (hw : EntryWeaker E' (S.subE (S.liftE x E))) :
    EntryWeaker (recvRes (S.ρ c) (S.subE (S.liftE c Ec)) E') (S.subE (S.liftE x (recvRes c Ec E))) := by
  have hrb : E.mode ≠ .rootb := by rcases hmo with h' | h' <;> rw [h'] <;> simp
  have h1 := S.subE_weaker (recvRes_lift h hab hc hmo hE0 x hEf (EntryWeaker.refl (S.liftE x E)))
  refine EntryWeaker.trans ?_ h1
  rw [subE_recvRes]
  exact recvRes_weaker hw (allKinds_recvRoots_subE h hnp _)
    (by rw [subE_mode, liftE_mode x hrb]; rcases hmo with h' | h' <;> rw [h'] <;> simp [liftMode])
    (by rw [subE_dbind, liftE_dbind h, ite_eq_right hrb]; exact hE0)
    (by rw [subE_fresh, S.liftE_fresh_of hrb]; exact hEf)

theorem src_rename (ρ : Var → Var) (s : Stmt) : (s.rename ρ).src = s.src := by
  induction s <;> simp_all [Stmt.rename, Stmt.src]

/-- A2-drop.3a: renaming keeps what a statement moves first. -/
theorem movedFirst_rename (ρ : Var → Var) (s : Stmt) : (s.rename ρ).movedFirst = s.movedFirst.map ρ := by
  induction s with
  | letd x f r s ih => cases r <;> simp [Stmt.rename, Rhs.rename, Stmt.movedFirst, ih]
  | assign y r => cases r <;> simp [Stmt.rename, Rhs.rename, Stmt.movedFirst]
  | _ => simp [Stmt.rename, Stmt.movedFirst]

theorem mem_movedFirst_rename {ρ : Var → Var} {s : Stmt} {x : Var} (h : x ∈ s.movedFirst) :
    ρ x ∈ (s.rename ρ).movedFirst := by
  rw [movedFirst_rename]; exact List.mem_map_of_mem h

/-- A2-drop.3a: renaming keeps what a statement assigns. -/
theorem assigns_rename (ρ : Var → Var) (s : Stmt) : (s.rename ρ).assigns = s.assigns.map ρ := by
  induction s <;> simp_all [Stmt.rename, Stmt.assigns]

theorem not_mem_assigns_rename {ρ : Var → Var} (hinj : ∀ v w, ρ v = ρ w → v = w) {s : Stmt} {x : Var}
    (h : x ∉ s.assigns) : ρ x ∉ (s.rename ρ).assigns := by
  rw [assigns_rename]; intro hm
  obtain ⟨y, hy, hyx⟩ := List.mem_map.mp hm
  exact h (hinj _ _ hyx ▸ hy)

theorem dtorHead_rename {ρ : Var → Var} (hinj : ∀ v w, ρ v = ρ w → v = w) {s : Stmt} {x : Var}
    (h : x ∈ s.movedFirst ∧ x ∉ s.assigns) : ρ x ∈ (s.rename ρ).movedFirst ∧ ρ x ∉ (s.rename ρ).assigns :=
  ⟨mem_movedFirst_rename h.1, not_mem_assigns_rename hinj h.2⟩

/-- A context with the same bindings, modes and types, and the same
    borrowed parameters, as one the call set up. -/
theorem AbsOK.of_same {Γa Δa : Ctx} (hab : S.AbsOK Γa) (hdom : ∀ v, (Γa v).isSome = (Δa v).isSome)
    (hm : ∀ v E, Δa v = some E → ∃ E0, Γa v = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty ∧
      (E0.fixed → E = E0)) : S.AbsOK Δa := by
  refine ⟨fun v E hv hrb => ?_, fun v E b hv hio => ?_, fun v bh hb => ?_, fun v E hv => by
    obtain ⟨E0, h0, hm0, ht0, _⟩ := hm v E hv; rw [hm0, ht0]; exact hab.2.2.2.1 v E0 h0, fun v hp => by
    obtain ⟨E0, h0, hm0⟩ := hab.2.2.2.2.1 v hp
    have hd := hdom v; rw [h0] at hd
    cases hΔ : Δa v with
    | none => rw [hΔ] at hd; cases hd
    | some E =>
      obtain ⟨E1, h1, hme, _, _⟩ := hm v E hΔ
      rw [h0] at h1; cases h1
      exact ⟨E, rfl, by rw [hme]; exact hm0⟩, hab.2.2.2.2.2⟩
  · obtain ⟨E0, h0, hm0, _, he⟩ := hm v E hv
    rw [he (Or.inl (hm0 ▸ hrb))] at hrb ⊢
    exact hab.1 v E0 h0 hrb
  · obtain ⟨E0, h0, hm0, ht0, _⟩ := hm v E hv
    rw [ht0]; exact hab.2.1 v E0 b h0 (hm0 ▸ hio)
  · obtain ⟨E0, h0, hm0, ht0, hf0⟩ := hab.2.2.1 v bh hb
    have hs := hdom v; rw [h0] at hs
    obtain ⟨E, hE⟩ := Option.isSome_iff_exists.mp hs.symm
    obtain ⟨E1, h1, hm1, ht1, he⟩ := hm v E hE
    rw [h0] at h1; cases h1
    refine ⟨E, hE, by rw [hm1, hm0], by rw [ht1, ht0], fun hf => ?_⟩
    have hf1 : E0.fixed := by simp only [Entry.fixed_def] at hf ⊢; rw [hm1, ht1] at hf; exact hf
    rw [he hf1]; exact hf0 hf1

/-- Agora #909: a fresh borrow of the callee stays one where the call places
    it: its lift adds nothing the arguments hold, and its roots, the
    callee's own bindings, are lifted to owners. -/
theorem freshE_lift (h : S.OK) {Γa : Ctx} (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : FreshE Γa E) :
    FreshE (S.canon Γa) (S.subE (S.liftE v E)) := by
  intro hl hn hb hf
  rw [subE_live] at hl; rw [subE_ty] at hn; rw [subE_mode] at hb; rw [subE_fresh] at hf
  by_cases hrb : E.mode = .rootb
  · simp [liftE, hrb] at hf
  rw [liftE_live] at hl; rw [liftE_ty v hrb] at hn; rw [liftE_mode v hrb] at hb
  rw [S.liftE_fresh_of hrb] at hf
  have hEb : E.mode = .bor := by revert hb hrb; cases E.mode <;> simp [liftMode]
  obtain ⟨hne, hd⟩ := hE hl hn hEb hf
  have hp : (S.liftE v E).path = rds S.ρ E.path := by simp [liftE, hEb, Mode.ownSlot, hf, hn]
  -- AGORA-937: a fresh borrow's path is on frame bindings, so on no region:
  -- the substitution keeps it
  have hps : (S.subE (S.liftE v E)).path = rds S.ρ E.path := by
    rw [subE_path, hp]
    refine S.flatMap_subD_fix fun d hdd => ?_
    obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hdd
    obtain ⟨_, Er, hEr, hm⟩ := hd d0 hd0
    have hnp : S.isPi d0.root = false := hab.notPi hEr (by
      rcases hm with h1 | ⟨b, h1⟩ <;> rw [h1] <;> simp)
    exact S.subD_of_not fun w hw => by
      simp only [Dep.ren, inv_ρ h, Option.some.injEq] at hw; subst hw; exact hnp
  rw [hps]
  refine ⟨by simpa [rds] using hne, fun d hdd => ?_⟩
  obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hdd
  obtain ⟨hk, Er, hEr, hm⟩ := hd d0 hd0
  have hrbr : Er.mode ≠ .rootb := by rcases hm with h1 | ⟨b, h1⟩ <;> rw [h1] <;> simp
  have hnp : S.isPi d0.root = false := hab.notPi hEr (by
    rcases hm with h1 | ⟨b, h1⟩ <;> rw [h1] <;> simp)
  refine ⟨hk, S.subE (S.liftE d0.root Er), canon_some h hEr hnp, ?_⟩
  rw [subE_mode, liftE_mode _ hrbr]
  rcases hm with h1 | ⟨b, h1⟩ <;> rw [h1] <;> exact Or.inl rfl

/-- Agora #909: a context the callee may assume after a panic or an exit keeps
    fresh borrows fresh, seen from the call: the caller's are the frame's own
    entries (`S.Φ`), whose roots keep their modes; the callee's are lifted,
    fresh where the callee may assume them (`hsrc`). -/
theorem canon_freshT (h : S.OK) {Γa Δa : Ctx} (habΔ : S.AbsOK Δa) (hfa : FreshOK Γa)
    (hdom' : ∀ y, (S.canon Γa y).isSome = (S.canon Δa y).isSome)
    (hm' : ∀ y E, S.canon Δa y = some E → ∃ E0, S.canon Γa y = some E0 ∧ E.mode = E0.mode ∧
      E.ty = E0.ty ∧ (E0.fixed → E = E0))
    (hsrc : FreshOK Γa → FreshOK Δa) :
    FreshOK (S.canon Γa) → FreshOK (S.canon Δa) := by
  intro hf y E hy
  unfold canon at hy
  split at hy
  · rename_i v _
    split at hy
    · cases hy
    · obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hy
      exact freshE_lift h habΔ (hsrc hfa _ E1 h1)
  · rename_i hinv
    have hyΓ : S.canon Γa y = some E := by unfold canon; rw [hinv]; exact hy
    refine (hf y E hyΓ).mono (fun r Er hr hmr => ?_)
    cases hE : S.canon Δa r with
    | none => have := hdom' r; rw [hr, hE] at this; cases this
    | some E' =>
      obtain ⟨E0, h0, hme, _⟩ := hm' r E' hE
      rw [hr] at h0; cases h0
      exact ⟨E', rfl, hme ▸ hmr⟩

theorem canon_same (h : S.OK) {Γa Δa : Ctx} (hab : S.AbsOK Γa)
    (hdom : ∀ v, (Γa v).isSome = (Δa v).isSome)
    (hm : ∀ v E, Δa v = some E → ∃ E0, Γa v = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty ∧
      (E0.fixed → E = E0)) :
    (∀ y, (S.canon Γa y).isSome = (S.canon Δa y).isSome) ∧
    (∀ y E, S.canon Δa y = some E → ∃ E0, S.canon Γa y = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty ∧
      (E0.fixed → E = E0)) := by
  have habΔ := hab.of_same hdom hm
  refine ⟨fun y => ?_, fun y E hy => ?_⟩
  · rcases canon_cases_sub h Γa y with ⟨v, rfl, hp, hc⟩ | ⟨v, rfl, hp, hc⟩ | ⟨hyf, hc⟩
    · rw [hc, canon_ρs h Δa hp]; have := hdom v; cases h1 : Γa v <;> cases h2 : Δa v <;> simp_all
    · rw [hc, canon_ρ_sub h, hp]; rfl
    · rw [hc, canon_frame Δa hyf]
  · rcases canon_cases_sub h Δa y with ⟨v, rfl, hp, hc⟩ | ⟨v, rfl, _, hc⟩ | ⟨hyf, hc⟩
    · rw [hc] at hy
      obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hy
      obtain ⟨E0, h0, hm0, ht0, hrb⟩ := hm v E1 h1
      refine ⟨S.subE (S.liftE v E0), canon_some h h0 hp, ?_, ?_, fun hr => ?_⟩
      · simp only [Function.comp, subE_mode]
        by_cases hrb0 : E0.mode = .rootb
        · rw [hrb (Or.inl hrb0)]
        · have hrb1 : E1.mode ≠ .rootb := by rw [hm0]; exact hrb0
          rw [liftE_mode v hrb1, liftE_mode v hrb0, hm0]
      · simp only [Function.comp, subE_ty]
        rw [liftE_ty' h habΔ h1, liftE_ty' h hab h0, ht0]
      · by_cases hrb0 : E0.mode = .rootb
        · simp only [Function.comp]; rw [hrb (Or.inl hrb0)]
        · exact absurd (by simpa only [Entry.fixed_def, subE_mode, subE_ty] using hr) (liftE_not_fixed hrb0)
    · rw [hc] at hy; cases hy
    · rw [hc] at hy
      exact ⟨E, by rw [canon_frame Γa hyf]; exact hy, rfl, rfl, fun _ => rfl⟩

/-- An effect on a root, with no views among the elements: a callee binding
    that allows it reaches nothing of the frame it does not change. -/
theorem allowed_canDo_false (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    {e : Eff} (hcan : canDo Ey.mode e) : Allowed S e false y := by
  rcases hcan with hm | ⟨b, hm, hle⟩
  · exact allowed_own hab hy hm e _
  · obtain ⟨_, hb⟩ := hab.2.1 y Ey b hy hm
    refine Or.inr ⟨b, _, hb, fun k hk => ?_⟩
    have h1 := Eff.kills_mono hle false k hk
    cases b <;> cases k <;> cases Ey.ty.elem.holdsView <;> simp_all [Eff.kills]

/-- AGORA-937: the substitution keeps a lifted borrow's path when no memory
    root of its path, and no name on it, is a region's index: the lift renames
    the path and adds only what the arguments held, the frame's. -/
theorem subE_liftE_path_bor (h : S.OK) {x : Var} {E : Entry} (hmx : E.mode = .bor)
    (hroot : ∀ d0 ∈ memDeps E.path, S.isPi d0.root = false)
    (hnm : ∀ d0 ∈ E.path, d0.kind.isName = true → S.isPi d0.root = false) :
    (S.subE (S.liftE x E)).path = (S.liftE x E).path := by
  have hpath : (S.liftE x E).path = rds S.ρ E.path ++ (if E.fresh && E.ty != .int then [] else S.A) := by
    simp [liftE, hmx, Mode.ownSlot]
  rw [subE_path]; apply S.flatMap_subD_fix; intro d hd
  rw [hpath] at hd
  rcases List.mem_append.mp hd with hd | hd
  · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
    apply S.subD_of_not; intro w hw
    simp only [Dep.ren, inv_ρ h, Option.some.injEq] at hw; subst hw
    cases hk : d0.kind.isName
    · exact hroot d0 (List.mem_filter.mpr ⟨hd0, by simp [hk]⟩)
    · exact hnm d0 hd0 hk
  · split at hd
    · cases hd
    · exact S.subD_frameRoot (A_out h hd)

/-- Ending what an entry depends on makes it say less, when a fixed entry
    is left as it is. -/
theorem _root_.A2.entryWeaker_killE {e : Eff} {hv : Bool} {x : Var} {E : Entry}
    (hfix : E.fixed → killE e hv x E = E) : EntryWeaker E (killE e hv x E) := by
  by_cases hf : E.fixed
  · rw [hfix hf]; exact EntryWeaker.refl E
  · unfold killE; split
    · exact ⟨rfl, rfl, fun h => absurd h hf, fun h => by simp at h,
        fun h => ⟨h, List.Subset.refl _⟩, rfl, fun h => Or.inl h, fun _ _ _ _ _ => Iff.rfl,
      fun _ _ _ hfr => (by fresh_ew),
      fun _ _ hhf => by heldfresh_ew⟩
    · exact EntryWeaker.refl E

/-! #### AGORA-937 (item 3): what a change through a region does where the call places it -/

/-- The substitution of a lifted dependency list, when every region it names
    stands for nothing: the dependencies on no region, renamed. -/
theorem flatMap_subD_rds (h : S.OK) {L : List Dep}
    (hσ : ∀ d0 ∈ L, S.isPi d0.root = true → d0.kind.isName = false → S.σ d0.root = []) :
    (rds S.ρ L).flatMap S.subD = rds S.ρ (L.filter (fun d => !S.isPi d.root)) := by
  induction L with
  | nil => rfl
  | cons d0 L ih =>
    have ih' := ih (fun d hd => hσ d (List.mem_cons_of_mem _ hd))
    simp only [rds, List.map_cons, List.flatMap_cons, List.filter_cons] at ih' ⊢
    have hsd : S.subD (d0.ren S.ρ) = if S.isPi d0.root then [] else [d0.ren S.ρ] := by
      unfold subD
      simp only [Dep.ren, inv_ρ h]
      by_cases hp : S.isPi d0.root = true
      · by_cases hk : d0.kind.isName = true
        · simp [hp, hk]
        · simp [hp, hk, hσ d0 (by simp) hp (by simpa using hk)]
      · simp [hp]
    rw [hsd, ih']
    cases S.isPi d0.root <;> simp

/-- What a lifted borrow's substituted path reaches in memory: its own
    roots that are no region, renamed, when a region stands for nothing and
    the lift adds no memory (`S.A` holds only names when `S.R = []`). -/
theorem memDeps_subE_liftE_bor (h : S.OK) {x : Var} {E : Entry} (hmx : E.mode = .bor)
    (hA : (E.fresh && E.ty != .int) = true ∨ S.R = [])
    (hσ : ∀ d0 ∈ E.path, S.isPi d0.root = true → d0.kind.isName = false → S.σ d0.root = []) :
    memDeps (S.subE (S.liftE x E)).path = rds S.ρ ((memDeps E.path).filter (fun d => !S.isPi d.root)) := by
  have hpath : (S.liftE x E).path = rds S.ρ E.path ++ (if E.fresh && E.ty != .int then [] else S.A) := by
    simp [liftE, hmx, Mode.ownSlot]
  rw [subE_path, hpath, List.flatMap_append, flatMap_subD_rds h hσ]
  have hAm : memDeps ((if E.fresh && E.ty != .int then [] else S.A).flatMap S.subD) = [] := by
    split
    · rfl
    · rename_i hnf
      have hR : S.R = [] := hA.resolve_left hnf
      unfold memDeps
      apply List.filter_eq_nil_iff.mpr
      intro d hd
      obtain ⟨a, ha, hda⟩ := List.mem_flatMap.mp hd
      have hna : a.kind.isName = true := by
        unfold RSetup.A at ha; rw [S.Rf_nil h hR] at ha
        simp only [compAll, List.flatMap_nil, List.nil_append] at ha
        exact h.N_name a ha
      rw [S.mem_subD_name hna hda]; simp [hna]
  unfold memDeps at hAm ⊢
  rw [List.filter_append, hAm, List.append_nil]
  simp only [rds, List.filter_map, List.filter_filter]
  congr 1
  apply List.filter_congr
  intro d _
  simp [Function.comp, Dep.ren, Bool.and_comm]

theorem kill_killNames_comm (e : Eff) (hv : Bool) (x : Var) : ∀ (ds : List Dep) (Γ : Ctx),
    A2.kill e hv x (A2.killNames ds Γ) = A2.killNames ds (A2.kill e hv x Γ)
  | [], _ => rfl
  | d :: ds, Γ => by
    show A2.kill e hv x (A2.kill _ _ _ (A2.killNames ds Γ)) = A2.kill _ _ _ (A2.killNames ds (A2.kill e hv x Γ))
    rw [kill_comm, kill_killNames_comm e hv x ds Γ]

/-- AGORA-937 (3d): what a list of changes ends depends only on which
    changes it holds. -/
theorem killNames_congr {L1 L2 : List Dep} (hL : ∀ d, d ∈ L1 ↔ d ∈ L2) (Γ : Ctx) :
    A2.killNames L1 Γ = A2.killNames L2 Γ := by
  funext v
  rw [killNames_eq, killNames_eq]
  congr 1
  funext E
  unfold killAll
  have : L1.any (fun d => hits d.kind.bound false d.root E) = L2.any (fun d => hits d.kind.bound false d.root E) := by
    rw [Bool.eq_iff_iff]; simp only [List.any_eq_true]
    exact ⟨fun ⟨d, hd, hh⟩ => ⟨d, (hL d).mp hd, hh⟩, fun ⟨d, hd, hh⟩ => ⟨d, (hL d).mpr hd, hh⟩⟩
  rw [this]

theorem killNames_append (xs ys : List Dep) (Γ : Ctx) :
    A2.killNames (xs ++ ys) Γ = A2.killNames xs (A2.killNames ys Γ) := List.foldr_append

/-- Kills commute, so a list of them may run in two groups. -/
theorem killNames_split (p : Dep → Bool) : ∀ (ds : List Dep) (Γ : Ctx),
    A2.killNames ds Γ = A2.killNames (ds.filter p) (A2.killNames (ds.filter (fun d => !p d)) Γ)
  | [], _ => rfl
  | d :: ds, Γ => by
    cases hpd : p d with
    | true =>
      simp only [List.filter_cons, hpd, ↓reduceIte, Bool.not_true, Bool.false_eq_true]
      show A2.kill _ _ _ (A2.killNames ds Γ) = A2.kill _ _ _ (A2.killNames _ _)
      rw [killNames_split p ds Γ]
    | false =>
      simp only [List.filter_cons, hpd, Bool.false_eq_true, ↓reduceIte, Bool.not_false]
      show A2.kill _ _ _ (A2.killNames ds Γ) = A2.killNames _ (A2.kill _ _ _ (A2.killNames _ Γ))
      rw [killNames_split p ds Γ, kill_killNames_comm]

/-- A change through a region that ends no view of it ends no fixed entry:
    a borrowed parameter depends on the region only by a view (`RegViews`)
    and on the rest by name; a fixed `inout` one holds nothing. So it only
    weakens the context. -/
theorem weaker_kill_region (h : S.OK) {Γ : Ctx} (hab : S.AbsOK Γ) (hw : CtxWF Γ) (hn : NameWF Γ)
    {e : Eff} {r : Var} (hk : e.kills false .view = false) (he : e ≠ .replace) :
    Weaker Γ (A2.kill e false r Γ) := by
  refine ⟨fun v => ⟨?_, fun E E' h1 h2 => ?_⟩, hw.kill e false r, hn.kill e false r⟩
  · simp [A2.kill]
  · simp only [A2.kill, h1, Option.map_some, Option.some.injEq] at h2; subst h2
    refine entryWeaker_killE fun hf => ?_
    have hno : ∀ d ∈ E.vdeps, d.root = r → e.kills false d.kind = false := by
      intro d hd _
      rcases hf with hrb | ⟨b, hm, _, _⟩
      · obtain ⟨R, hR, hv⟩ := vdeps_rootb hab h1 hrb
        rw [hv] at hd
        rcases List.mem_append.mp hd with hd | hd
        · rw [(hR d hd).1]; exact Eff.kills_self_of_view hk
        · split at hd
          · obtain ⟨w, b, t, rfl, _, _, _, _⟩ := h.sym_ok d hd
            exact kills_isName he false rfl
          · cases hd
      · obtain ⟨_, hb⟩ := hab.2.1 v E b h1 hm
        obtain ⟨E0, h0, _, _, hfx⟩ := hab.2.2.1 v _ hb
        rw [h1] at h0; cases h0
        have hheld : E.held = [] := (hfx (Or.inr ⟨b, hm, by assumption, by assumption⟩)).2
        have hos : E.mode.ownSlot = true := by rw [hm]; rfl
        simp [Entry.vdeps, hos, hheld] at hd
    unfold killE
    rw [ite_eq_right_iff.mpr fun hh => absurd hh (by rw [hits_false_of hno]; simp)]

theorem weaker_killNames_region (h : S.OK) {Γ : Ctx} (hab : S.AbsOK Γ) (hw : CtxWF Γ) (hn : NameWF Γ) :
    ∀ ds : List Dep, (∀ d ∈ ds, d.kind.bound.kills false .view = false ∧ d.kind.bound ≠ .replace) →
      Weaker Γ (A2.killNames ds Γ)
  | [], _ => Weaker.refl hw hn
  | d :: ds, hd => by
    have ih := weaker_killNames_region h hab hw hn ds (fun d' hd' => hd d' (List.mem_cons_of_mem _ hd'))
    exact ih.trans (weaker_kill_region h (hab.killNames ds) ih.wf ih.names (hd d (by simp)).1 (hd d (by simp)).2)

/-- AGORA-937 (item 3): a region binding, lifted and substituted, is a
    region, of the same type and as a root of a change the same. -/
theorem subE_liftE_region {v : Var} {E : Entry} (hr : E.mode = .region) :
    (S.subE (S.liftE v E)).mode = .region ∧ (S.subE (S.liftE v E)).ty = E.ty ∧
      (S.subE (S.liftE v E)).rvec = E.rvec := by
  have hrb : E.mode ≠ .rootb := by rw [hr]; simp
  refine ⟨by rw [subE_mode, liftE_mode v hrb, hr]; rfl, by rw [subE_ty, liftE_ty v hrb], ?_⟩
  unfold Entry.rvec
  rw [subE_ty, subE_mode, liftE_ty v hrb, liftE_mode v hrb, hr]; rfl

/-- A region has no bound: only an `inout` parameter has one. -/
theorem allowed_region (hab : S.AbsOK Γa) {r : Var} {Er : Entry} (hEr : Γa r = some Er)
    (hr : Er.mode = .region) (e : Eff) : Allowed S e false r := by
  left
  cases hb : S.bnd r with
  | none => rfl
  | some bh =>
    obtain ⟨E, hE, hm, _⟩ := hab.2.2.1 r bh hb
    rw [hEr] at hE; cases hE; rw [hr] at hm; cases hm

/-- AGORA-937 (3d): **a change inside a region's elements, where the call
    places it**. The caller's `.dropIn` on a root `r` its argument views hits
    a lifted callee binding exactly where the callee's on the region `u`
    hits it: the region stands for views of `r` (or its handle), no other
    region does, nothing the lift adds is on `r` in memory, and a lent
    parameter's argument reaches `r` only at a view or its handle. -/
theorem hits_subE_region (h : S.OK) (hab : S.AbsOK Γa) {v u r : Var} {E : Entry} (hE : Γa v = some E)
    (hu : S.isPi u = true)
    (hσk : ∀ e ∈ S.σ u, e.kind = .view ∨ e.kind = .self)
    (hr : ∃ e ∈ S.σ u, e.root = r)
    (hoth : ∀ u', S.isPi u' = true → u' ≠ u → ∀ e ∈ S.σ u', e.root ≠ r)
    (hA : ∀ d ∈ S.A, d.root = r → d.kind.isName = true)
    (hpe : ∀ w, ∀ d ∈ (S.pe w).vdeps, d.root = r → d.kind = .view ∨ d.kind = .self ∨ d.kind.isName = true) :
    hits .dropIn false r (S.subE (S.liftE v E)) = hits .dropIn false u E := by
  have hce : ∀ {a k : Kind}, (a = .view ∨ a = .self) → (k = .view ∨ k = .inner ∨ k = .share) →
      Eff.dropIn.kills false (comp a k) = Eff.dropIn.kills false k := by
    intro a k ha hk; rcases ha with rfl | rfl <;> rcases hk with rfl | rfl | rfl <;> rfl
  have hk0 : ∀ k : Kind, k = .view ∨ k = .self ∨ k.isName = true → Eff.dropIn.kills false k = false := by
    intro k hk; rcases hk with rfl | rfl | hk
    · rfl
    · rfl
    · cases k <;> simp_all [Kind.isName, Eff.kills]
  have hpre : ((S.subE (S.liftE v E)).ty != .int || (S.subE (S.liftE v E)).mode == .rootb) =
      (E.ty != .int || E.mode == .rootb) := by
    rw [subE_ty, subE_mode, liftE_ty' h hab hE]
    congr 1
    cases hm : E.mode == .rootb
    · have : (S.liftE v E).mode ≠ .rootb := fun e => by
        have := (liftE_rootb h).mp e; simp [this] at hm
      simpa using this
    · have : E.mode = .rootb := by simpa using hm
      simpa using (liftE_rootb h).mpr this
  unfold hits
  rw [hpre]
  congr 1
  rw [Bool.eq_iff_iff]
  simp only [List.any_eq_true, Bool.and_eq_true, beq_iff_eq]
  -- a lifted dependency on a region the call reaches is the callee's own, renamed
  have hown : ∀ {u' : Var} {e : Dep}, e ∈ (S.liftE v E).vdeps → e.root = S.ρ u' → S.isPi u' = true →
      e.kind.isName = false → ∃ d0 ∈ E.vdeps, e = d0.ren S.ρ := by
    intro u' e he her hpu hen
    by_cases hrb : E.mode = .rootb
    · rcases liftE_rootb_dep h hab hE hrb he with he | ⟨w, rfl, _, hw⟩
      · rcases pe_dep h he with ⟨hout, _⟩ | ⟨hs, _⟩
        · exact absurd her.symm (hout u')
        · obtain ⟨w, b, t, rfl, _⟩ := sym_ren h hs; simp [Kind.isName] at hen
      · exact ⟨⟨w, .self⟩, by simp [Entry.vdeps, hrb, Mode.ownSlot, hw], rfl⟩
    · rcases liftE_vdeps_cases hrb he with h1 | ha
      · exact h1
      · exact absurd her.symm (A_out h ha u')
  constructor
  · rintro ⟨d, hd, hdr, hk⟩
    rw [subE_vdeps] at hd
    obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp hd
    rcases S.mem_subD hde with rfl | ⟨u'', hv'', hp'', e0, he0, rfl, hek⟩
    · -- kept: on no region, so not `r`'s in a way the change ends
      exfalso
      by_cases hrb : E.mode = .rootb
      · rcases liftE_rootb_dep h hab hE hrb he with he | ⟨w, rfl, _, _⟩
        · rw [hk0 _ (hpe v d he hdr)] at hk; cases hk
        · exact (S.σ_frame h (Classical.choose_spec hr).1).1 w
            (by rw [(Classical.choose_spec hr).2]; exact hdr)
      · rcases liftE_vdeps_cases hrb he with ⟨d0, _, rfl⟩ | ha
        · exact (S.σ_frame h (Classical.choose_spec hr).1).1 d0.root
            (by rw [(Classical.choose_spec hr).2]; exact hdr)
        · rw [hk0 _ (Or.inr (Or.inr (hA d ha hdr)))] at hk; cases hk
    · -- what a region stands for: only `u`'s reaches `r`
      have hu'' : u'' = u := Classical.byContradiction fun hne => hoth u'' hp'' hne e0 he0 hdr
      subst hu''
      obtain ⟨d0, hd0, rfl⟩ := hown he (S.ρ_of_inv hv'').symm hp'' hek
      have hd0u : d0.root = u'' := by
        have := hv''; simp only [Dep.ren, inv_ρ h] at this; exact Option.some.inj this
      refine ⟨d0, hd0, hd0u, ?_⟩
      have hk4 : d0.kind = .self ∨ d0.kind = .inner ∨ d0.kind = .view ∨ d0.kind = .share :=
        kind4 (by simpa [Dep.ren] using hek)
      simp only [Dep.ren] at hk
      rcases hk4 with hs | hk4
      · exfalso
        rw [hs, comp_self_r] at hk
        rw [hk0 _ ((hσk e0 he0).elim (fun h => Or.inl h) (fun h => Or.inr (Or.inl h)))] at hk
        cases hk
      · have hk4' : d0.kind = .view ∨ d0.kind = .inner ∨ d0.kind = .share := by
          rcases hk4 with h1 | h1 | h1 <;> simp [h1]
        rwa [hce (hσk e0 he0) hk4'] at hk
  · rintro ⟨d0, hd0, hd0r, hk⟩
    have hn0 : d0.kind.isName = false := by
      cases hk0' : d0.kind.isName
      · rfl
      · rw [hk0 _ (Or.inr (Or.inr hk0'))] at hk; cases hk
    have hrem : d0.kind = .inner ∨ d0.kind = .share := by
      rcases kind4 hn0 with h1 | h1 | h1 | h1 <;> rw [h1] at hk ⊢ <;> simp_all [Eff.kills]
    have hlift : d0.ren S.ρ ∈ (S.liftE v E).vdeps := by
      by_cases hrb : E.mode = .rootb
      · obtain ⟨_, hp, R, _, hh⟩ := hab.1 v E hE hrb
        have hd0h : d0 ∈ E.held := by
          simp only [Entry.vdeps, hrb, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte, hp, List.nil_append] at hd0
          exact hd0
        simp only [liftE, hrb, ↓reduceIte, Entry.vdeps, h.pe_rb v, Mode.ownSlot, Bool.false_eq_true]
        exact List.mem_append_right _ (List.mem_append_left _
          (List.mem_map_of_mem (List.mem_filter.mpr ⟨hd0h, by simp [hn0]⟩)))
      · exact (mem_liftE_vdeps hrb).mpr (Or.inl ⟨d0, hd0, rfl⟩)
    obtain ⟨e0, he0, he0r⟩ := hr
    refine ⟨⟨e0.root, comp e0.kind d0.kind⟩, ?_, he0r, ?_⟩
    · rw [subE_vdeps]
      refine List.mem_flatMap.mpr ⟨d0.ren S.ρ, hlift, ?_⟩
      simp only [subD, Dep.ren, hd0r, inv_ρ h, hu, hn0, ↓reduceIte, Bool.false_eq_true, List.mem_map]
      exact ⟨e0, he0, rfl⟩
    · rw [hce (hσk e0 he0) (by rcases hrem with h1 | h1 <;> simp [h1])]; exact hk

/-- AGORA-937 (3d): ... so the callee's change inside the region's elements,
    where the call places it, is the caller's on `r`: the frame holds nothing
    such a change ends (the call's entry kill). -/
theorem canon_kill_region (h : S.OK) (hab : S.AbsOK Γa) {u r : Var} (hu : S.isPi u = true)
    (hσk : ∀ e ∈ S.σ u, e.kind = .view ∨ e.kind = .self)
    (hr : ∃ e ∈ S.σ u, e.root = r)
    (hoth : ∀ u', S.isPi u' = true → u' ≠ u → ∀ e ∈ S.σ u', e.root ≠ r)
    (hA : ∀ d ∈ S.A, d.root = r → d.kind.isName = true)
    (hpe : ∀ w, ∀ d ∈ (S.pe w).vdeps, d.root = r → d.kind = .view ∨ d.kind = .self ∨ d.kind.isName = true)
    (hΦ : ∀ y E, S.Φ y = some E → E.live = true → hits .dropIn false r E = false) :
    S.canon (kill .dropIn false u Γa) = kill .dropIn false r (S.canon Γa) := by
  funext y
  rcases canon_cases_sub h Γa y with ⟨v, rfl, hp, hc⟩ | ⟨v, rfl, hp, hc⟩ | ⟨hy, hc⟩
  · rw [canon_ρs h _ hp, A2.kill, A2.kill, hc]
    cases hE : Γa v with
    | none => rfl
    | some E =>
      simp only [Option.map_some, Function.comp, Option.some.injEq]
      unfold killE
      rw [hits_subE_region h hab hE hu hσk hr hoth hA hpe]
      split
      · rw [liftE_dead]; rfl
      · rfl
  · rw [A2.kill, hc, canon_ρ_sub h, hp]; rfl
  · rw [canon_frame _ hy, A2.kill, hc]
    cases hE : S.Φ y with
    | none => rfl
    | some E =>
      simp only [Option.map_some, Option.some.injEq]; unfold killE
      cases hl : E.live
      · split
        · cases E; simp_all
        · rfl
      · rw [hΦ y E hE hl]; rfl

/-- A change strictly inside elements ends no name: in memory it ends what it
    ends. -/
theorem hitsMem_dropIn (hv : Bool) (x : Var) (E : Entry) : hitsMem .dropIn hv x E = hits .dropIn hv x E := by
  unfold hitsMem hits
  congr 1
  congr 1
  funext d
  cases hk : d.kind <;> simp [Kind.isName, Eff.kills]

/-- AGORA-937 (3d): ... and no binding that may run a destructor views `r`
    where the caller's change ends it, as none views the region where the
    callee's does. -/
theorem dtorSafe_region (h : S.OK) (hab : S.AbsOK Γa) {u r : Var} (hu : S.isPi u = true)
    (hσk : ∀ e ∈ S.σ u, e.kind = .view ∨ e.kind = .self)
    (hr : ∃ e ∈ S.σ u, e.root = r)
    (hoth : ∀ u', S.isPi u' = true → u' ≠ u → ∀ e ∈ S.σ u', e.root ≠ r)
    (hA : ∀ d ∈ S.A, d.root = r → d.kind.isName = true)
    (hpe : ∀ w, ∀ d ∈ (S.pe w).vdeps, d.root = r → d.kind = .view ∨ d.kind = .self ∨ d.kind.isName = true)
    (hΦd : ∀ y E, S.Φ y = some E → E.dtor = true → E.mode.ownSlot = true → hitsMem .dropIn false r E = false)
    (hds : DtorSafe Γa .dropIn false u) : DtorSafe (S.canon Γa) .dropIn false r := by
  intro y E' hy hd hos
  rcases canon_cases_sub h Γa y with ⟨v, rfl, hp, hc⟩ | ⟨v, rfl, hp, hc⟩ | ⟨hy', hc⟩
  · rw [hc] at hy
    cases hE : Γa v with
    | none => rw [hE] at hy; cases hy
    | some E =>
      rw [hE] at hy; simp only [Option.map_some, Option.some.injEq, Function.comp] at hy; subst hy
      have hrb : E.mode ≠ .rootb := fun hm => by
        rw [subE_dtor, liftE_dtor' h, ite_eq_left hm] at hd; cases hd
      rw [hitsMem_dropIn, hits_subE_region h hab hE hu hσk hr hoth hA hpe, ← hitsMem_dropIn]
      refine hds v E hE (by rw [subE_dtor, liftE_dtor' h, ite_eq_right hrb] at hd; exact hd) ?_
      rw [subE_mode, liftE_mode v hrb, liftMode_ownSlot] at hos; exact hos
  · rw [hc] at hy; cases hy
  · rw [hc] at hy
    exact hΦd y E' hy hd hos

/-- AGORA-937 (3d): what a call setting provides for a change through one
    of its regions to be placed exactly: what each region stands for is a view
    of a root, or its handle, of no other region; the call freezes nothing (so
    the lift adds no memory); a lent argument reaches such a root only at a
    view, its handle, or by name; no frame binding is ended by a change inside
    the root's elements (the call's entry kill); and the root is a live owned
    `Vec` of the frame, lent to no one. -/
def ThruReady (S : RSetup) : Prop :=
  S.Rf = [] ∧ ∀ u, S.isPi u = true →
    (∀ e ∈ S.σ u, e.kind = .view ∨ e.kind = .self) ∧
    ∀ e ∈ S.σ u, (∀ u', S.isPi u' = true → u' ≠ u → ∀ e' ∈ S.σ u', e'.root ≠ e.root) ∧
      (∀ w, ∀ d ∈ (S.pe w).vdeps, d.root = e.root → d.kind = .view ∨ d.kind = .self ∨ d.kind.isName = true) ∧
      (∀ y E, S.Φ y = some E → E.live = true → hits .dropIn false e.root E = false) ∧
      (∀ y E, S.Φ y = some E → E.dtor = true → E.mode.ownSlot = true → hitsMem .dropIn false e.root E = false) ∧
      e.root ∉ S.Fc ∧ ∃ Er, S.Φ e.root = some Er ∧ Er.live = true ∧ Er.mode = .own ∧ Er.rvec = true

/-- With nothing frozen, what the lift adds is names. -/
theorem ThruReady.A_name (h : S.OK) (ht : S.ThruReady) {d : Dep} (hd : d ∈ S.A) : d.kind.isName = true := by
  rcases mem_A.mp hd with hd | hd
  · rw [ht.1] at hd; simp [compAll] at hd
  · exact h.N_name d hd

/-- The kill a change inside a region's elements puts on a root. -/
def regionKill (e : Dep) : Dep := ⟨e.root, .name .dropIn .int⟩

/-- AGORA-937 (3d): the callee's change inside the region `u`'s elements,
    placed, is the caller's on every root the region stands for. -/
theorem canon_kill_region_all (h : S.OK) (ht : S.ThruReady) {u : Var} (hu : S.isPi u = true) :
    ∀ (es : List Dep), es ≠ [] → es ⊆ S.σ u → ∀ (Γa : Ctx), S.AbsOK Γa →
      A2.killNames (es.map regionKill) (S.canon Γa) = S.canon (kill .dropIn false u Γa)
  | [], hne, _, _, _ => absurd rfl hne
  | e :: es, _, hsub, Γa, hab => by
    obtain ⟨hσk, hroots⟩ := ht.2 u hu
    have he : e ∈ S.σ u := hsub (List.mem_cons_self ..)
    obtain ⟨hoth, hpe, hΦ, _⟩ := hroots e he
    have hkr : S.canon (kill .dropIn false u Γa) = kill .dropIn false e.root (S.canon Γa) :=
      canon_kill_region h hab hu hσk ⟨e, he, rfl⟩ hoth (fun d hd _ => ht.A_name h hd) hpe hΦ
    show kill .dropIn false e.root (A2.killNames (es.map regionKill) (S.canon Γa)) = _
    cases es with
    | nil => exact hkr.symm
    | cons e' es' =>
      rw [canon_kill_region_all h ht hu (e' :: es') (List.cons_ne_nil _ _)
        (fun d hd => hsub (List.mem_cons_of_mem _ hd)) Γa hab]
      have hkr' : S.canon (kill .dropIn false u (kill .dropIn false u Γa)) =
          kill .dropIn false e.root (S.canon (kill .dropIn false u Γa)) :=
        canon_kill_region h (hab.kill _ _ _) hu hσk ⟨e, he, rfl⟩ hoth (fun d hd _ => ht.A_name h hd) hpe hΦ
      rw [← hkr']
      congr 1
      funext v
      simp only [A2.kill, Option.map_map, Function.comp_def, killE_idem]

/-- ... and so are the callee's changes inside several regions' elements:
    each region's, on every root it stands for. -/
theorem canon_killNames_region (h : S.OK) (ht : S.ThruReady) :
    ∀ (L : List Dep), (∀ d ∈ L, S.isPi d.root = true ∧ d.kind = .name .dropIn .int ∧ S.σ d.root ≠ []) →
      ∀ (Γa : Ctx), S.AbsOK Γa →
      A2.killNames (L.flatMap fun d => (S.σ d.root).map regionKill) (S.canon Γa) = S.canon (A2.killNames L Γa)
  | [], _, _, _ => rfl
  | d :: L, hL, Γa, hab => by
    obtain ⟨hu, hk, hne⟩ := hL d (List.mem_cons_self ..)
    have ih := canon_killNames_region h ht L (fun d' hd' => hL d' (List.mem_cons_of_mem _ hd')) Γa hab
    show A2.killNames ((S.σ d.root).map regionKill ++ L.flatMap _) (S.canon Γa) =
      S.canon (kill d.kind.bound false d.root (A2.killNames L Γa))
    rw [show ∀ (xs ys : List Dep) (Γ : Ctx), A2.killNames (xs ++ ys) Γ = A2.killNames xs (A2.killNames ys Γ)
      from fun xs ys Γ => List.foldr_append, ih, hk]
    exact canon_kill_region_all h ht hu _ hne (List.Subset.refl _) _ (hab.killNames _)

/-- AGORA-937 (3d): what a lifted, substituted borrow's path depends on in
    memory, when the call freezes nothing: a dependency of the borrow's on no
    region, renamed, or what a region on it stands for, composed. -/
theorem mem_memDeps_subE_liftE_bor (h : S.OK) (ht : S.ThruReady) {x : Var} {E : Entry} (hmx : E.mode = .bor)
    {d : Dep} :
    d ∈ memDeps (S.subE (S.liftE x E)).path ↔
      (∃ d0 ∈ memDeps E.path, S.isPi d0.root = false ∧ d = d0.ren S.ρ) ∨
      (∃ d0 ∈ memDeps E.path, S.isPi d0.root = true ∧ ∃ e ∈ S.σ d0.root, d = ⟨e.root, comp e.kind d0.kind⟩) := by
  have hpath : (S.liftE x E).path = rds S.ρ E.path ++ (if E.fresh && E.ty != .int then [] else S.A) := by
    simp [liftE, hmx, Mode.ownSlot]
  rw [subE_path, hpath, List.flatMap_append]
  have hAm : ∀ d ∈ memDeps ((if E.fresh && E.ty != .int then [] else S.A).flatMap S.subD), False := by
    intro d hd
    obtain ⟨hd, hn⟩ := List.mem_filter.mp hd
    split at hd
    · cases hd
    · obtain ⟨a, ha, hda⟩ := List.mem_flatMap.mp hd
      have hna := ht.A_name h ha
      rw [S.mem_subD_name hna hda] at hn; simp [hna] at hn
  constructor
  · intro hd
    obtain ⟨hd, hn⟩ := List.mem_filter.mp hd
    rcases List.mem_append.mp hd with hd | hd
    · obtain ⟨e, he, hde⟩ := List.mem_flatMap.mp hd
      obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp he
      have hn0 : d0.kind.isName = false := by
        rcases S.mem_subD hde with rfl | ⟨_, _, _, _, _, _, hk⟩
        · simpa [Dep.ren] using hn
        · simpa [Dep.ren] using hk
      have hd0m : d0 ∈ memDeps E.path := List.mem_filter.mpr ⟨hd0, by simp [hn0]⟩
      cases hp : S.isPi d0.root
      · left
        refine ⟨d0, hd0m, hp, ?_⟩
        have hk := S.subD_of_not (d := d0.ren S.ρ) (fun w hw => by
          simp only [Dep.ren, inv_ρ h] at hw; cases hw; exact hp)
        rw [hk, List.mem_singleton] at hde; exact hde
      · right
        refine ⟨d0, hd0m, hp, ?_⟩
        simp only [subD, Dep.ren, inv_ρ h, hp, hn0, ↓reduceIte, Bool.false_eq_true, List.mem_map] at hde
        obtain ⟨e, he, rfl⟩ := hde
        exact ⟨e, he, rfl⟩
    · exact absurd (List.mem_filter.mpr ⟨hd, hn⟩) (fun h' => hAm d h')
  · rintro (⟨d0, hd0, hp, rfl⟩ | ⟨d0, hd0, hp, e, he, rfl⟩)
    · obtain ⟨hd0, hn0⟩ := List.mem_filter.mp hd0
      refine List.mem_filter.mpr ⟨List.mem_append_left _ (List.mem_flatMap.mpr ⟨d0.ren S.ρ,
        List.mem_map_of_mem hd0, ?_⟩), by simpa [Dep.ren] using hn0⟩
      rw [S.subD_of_not (fun w hw => by simp only [Dep.ren, inv_ρ h] at hw; cases hw; exact hp)]
      exact List.mem_singleton_self _
    · obtain ⟨hd0, hn0⟩ := List.mem_filter.mp hd0
      have hn0 : d0.kind.isName = false := by simpa using hn0
      refine List.mem_filter.mpr ⟨List.mem_append_left _ (List.mem_flatMap.mpr ⟨d0.ren S.ρ,
        List.mem_map_of_mem hd0, ?_⟩), ?_⟩
      · simp only [subD, Dep.ren, inv_ρ h, hp, hn0, ↓reduceIte, Bool.false_eq_true, List.mem_map]
        exact ⟨e, he, rfl⟩
      · simp [comp_isName (h.σ_mem _ e he) hn0]

/-- Agora #295: a change through a borrow in a callee's body is typed where
    the call places it. Its memory roots are the callee's own, renamed, none
    of them frozen (`Fcout`), each allowing its effect as a callee binding
    did (`canDo_lift`, `Allowed`). AGORA-937 (item 3): a root may be a
    region (`ThruOKR`). Where the call lifts regions as ghost bindings it
    stays one, and the kill there ends no view (`canon_killNames'`). Where it
    substitutes them, a change through a region is placed by a call that
    passes no views (`S.R = []`), so the region stands for nothing and drops
    out of the path (`memDeps_subE_liftE_bor`): the call's context then knows
    more than the callee's, which it weakens to (`weaker_killNames_region`). -/
theorem editB_ren_facts (h : S.OK) (hab : S.AbsOK Γa)
    {Fa : List Var} {Γa1 : Ctx} {x : Var} {op : Edit} {Ex Ex1 : Entry} {t : Ty}
    {D : List Dep} (hx : Γa x = some Ex) (hmx : Ex.mode = .bor) (hl : Ex.live = true)
    (hty : Ex.ty = .vec t)
    (harg : EditArg Γa Fa op t D Γa1) (hyx : ∀ y, op.stored = some y → y ≠ x) (hx1 : Γa1 x = some Ex1)
    (hl1 : Ex1.live = true) (hthru : ThruOKR Γa1 Fa op Ex.ty Ex1.path)
    (hloc : S.R = [] ∨ Ex.fresh = true) (hvs : ∀ v ∈ op.vars, S.isPi v = false)
    (hnm : ∀ d ∈ Ex.path, d.kind.isName = true → S.isPi d.root = false)
    (hRp : ∀ d0 ∈ memDeps Ex.path, S.isPi d0.root = true → S.R = [])
    (hw1 : CtxWF Γa1) (hn1 : NameWF Γa1)
    (hwT : CtxWF (A2.setE (A2.killThru op Ex.ty Ex1.path Γa1) x Ex1))
    (hnT : NameWF (A2.setE (A2.killThru op Ex.ty Ex1.path Γa1) x Ex1)) :
    (∃ D', EditArg (S.canon Γa) S.Fc (op.rename S.ρ) t D' (S.canon Γa1)) ∧
    (∀ y, (op.rename S.ρ).stored = some y → y ≠ S.ρ x) ∧
    ThruOKR (S.canon Γa1) S.Fc (op.rename S.ρ) (S.liftE x Ex1).ty (S.subE (S.liftE x Ex1)).path ∧
    Weaker (A2.setE (A2.killThru (op.rename S.ρ) (S.liftE x Ex1).ty (S.subE (S.liftE x Ex1)).path (S.canon Γa1))
        (S.ρ x) (S.subE (S.liftE x Ex1)))
      (S.canon (A2.setE (A2.killThru op Ex.ty Ex1.path Γa1) x Ex1)) := by
  have hab1 : S.AbsOK Γa1 := EditArg.absOK harg hab
  have hE1 : Ex1 = Ex := harg.at_ne hyx hx hx1 hl1
  subst hE1
  have hrb : Ex1.mode ≠ .rootb := by rw [hmx]; simp
  have hty1 : (S.liftE x Ex1).ty = Ex1.ty := liftE_ty x hrb
  have hnpx : S.isPi x = false := hab1.notPi hx1 (by rw [hmx]; simp)
  -- a region stands for nothing where a change goes through it
  have hσ : ∀ d0 ∈ Ex1.path, S.isPi d0.root = true → d0.kind.isName = false → S.σ d0.root = [] :=
    fun d0 hd0 hp hk => S.σ_nil_of_R h (hRp d0 (List.mem_filter.mpr ⟨hd0, by simp [hk]⟩) hp) _
  have hA : (Ex1.fresh && Ex1.ty != .int) = true ∨ S.R = [] := by
    rcases hloc with hR | hf
    · exact Or.inr hR
    · exact Or.inl (by simp [hf, hty])
  have hmemS := memDeps_subE_liftE_bor (x := x) h hmx hA hσ
  -- each root of the change: an owner, or a region
  have hroot : ∀ d0 ∈ memDeps Ex1.path, ∃ Er, Γa1 d0.root = some Er ∧ Er.mode ≠ .rootb ∧
      (Er.mode ≠ .region → Er.live = true ∧ canDo Er.mode (op.effAt d0.kind (decide (Er.ty = Ex1.ty)) Er.rvec)) ∧
      (Er.mode = .region → (op.effAt d0.kind (decide (Er.ty = Ex1.ty)) Er.rvec).kills false .view = false) := by
    intro d0 hd0
    obtain ⟨_, _, Er, hEr, hlv, hcan, _, _⟩ := hthru d0 hd0
    refine ⟨Er, hEr, ?_, fun hnr => ⟨hlv.live hnr, hcan.toCanDo hnr⟩, fun hr => ?_⟩
    · rcases hcan with h' | ⟨h', _⟩
      · rcases h' with h' | ⟨b, h', _⟩ <;> rw [h'] <;> simp
      · rw [h']; simp
    · rcases hcan with h' | ⟨_, hk⟩
      · exfalso; have := h'.ownSlot; rw [hr] at this; cases this
      · exact hk
  -- every root's effect is the same where the call places it
  have harge : ∀ d0 ∈ memDeps Ex1.path, S.isPi d0.root = false →
      (argE (S.canon Γa1) (S.ρ d0.root)).ty = (argE Γa1 d0.root).ty ∧
      (argE (S.canon Γa1) (S.ρ d0.root)).rvec = (argE Γa1 d0.root).rvec := by
    intro d0 hd0 hnp0
    obtain ⟨Er, hEr, hrbr, hown, hreg⟩ := hroot d0 hd0
    have hae : argE Γa1 d0.root = Er := by unfold argE; rw [hEr]; rfl
    rw [argE_canons h hEr hnp0, hae]
    by_cases hr : Er.mode = .region
    · obtain ⟨_, ht, hv⟩ := subE_liftE_region (v := d0.root) hr; exact ⟨ht, hv⟩
    · exact ⟨by rw [subE_ty, liftE_ty _ hrbr], subE_liftE_rvec hrbr hr⟩
  -- what the change is handed, where the call places it
  obtain ⟨D', harg'⟩ : ∃ D', EditArg (S.canon Γa) S.Fc (op.rename S.ρ) t D' (S.canon Γa1) := by
    cases harg with
    | @push y _ _ _ _ hy hly htyy hpa =>
      have hnpy : S.isPi y = false := hvs y (by simp [Edit.vars])
      obtain ⟨D', hpa', _⟩ := pushArg_rens h hab hy hnpy hpa
      exact ⟨D', EditArg.push (canon_some h hy hnpy) (by rw [subE_live, liftE_live]; exact hly)
        (by rw [subE_ty, liftE_ty' h hab hy]; exact htyy) hpa'⟩
    | trunc hie =>
      exact ⟨[], EditArg.trunc (exprT_ren h hab hie (fun v hv => hvs v (by simpa [Edit.vars] using hv)))⟩
    | @set _ y _ _ _ _ hie hy hly htyy hpa =>
      have hnpy : S.isPi y = false := hvs y (by simp [Edit.vars])
      obtain ⟨D', hpa', _⟩ := pushArg_rens h hab hy hnpy hpa
      exact ⟨D', EditArg.set (exprT_ren h hab hie (fun v hv => hvs v (by simp [Edit.vars, hv])))
        (canon_some h hy hnpy) (by rw [subE_live, liftE_live]; exact hly)
        (by rw [subE_ty, liftE_ty' h hab hy]; exact htyy) hpa'⟩
  have hyx' : ∀ y, (op.rename S.ρ).stored = some y → y ≠ S.ρ x := by
    intro y hy
    rw [Edit.stored_rename] at hy
    obtain ⟨y0, hy0, rfl⟩ := Option.map_eq_some_iff.mp hy
    exact fun e => hyx y0 hy0 (h.inj _ _ e)
  have hthru' : ThruOKR (S.canon Γa1) S.Fc (op.rename S.ρ) (S.liftE x Ex1).ty (S.subE (S.liftE x Ex1)).path := by
    intro d hd
    rw [hmemS] at hd
    obtain ⟨d0, hd0', rfl⟩ := mem_rds.mp hd
    obtain ⟨hd0, hnp0⟩ := List.mem_filter.mp hd0'
    have hnp0 : S.isPi d0.root = false := by simpa using hnp0
    obtain ⟨_, hy0, Er, hEr, _, _, hds, hsh, hho⟩ := hthru d0 hd0
    obtain ⟨Er', hEr', hrbr, hown, hreg⟩ := hroot d0 hd0
    rw [hEr] at hEr'; cases hEr'
    have hae : argE Γa1 d0.root = Er := by unfold argE; rw [hEr]; rfl
    obtain ⟨hte, hve⟩ := harge d0 hd0 hnp0
    rw [hae] at hte hve
    rw [argE_canons h hEr hnp0] at hte hve
    refine ⟨h.Fcout _, fun y hy => ?_, S.subE (S.liftE d0.root Er), canon_some h hEr hnp0, ?_, ?_, ?_,
      ⟨by simpa [Dep.ren] using hsh, ?_⟩⟩
    · rw [Edit.stored_rename] at hy
      obtain ⟨y0, hy0', rfl⟩ := Option.map_eq_some_iff.mp hy
      exact fun e => hy0 y0 hy0' (h.inj _ _ e)
    · by_cases hr : Er.mode = .region
      · exact Or.inr (subE_liftE_region hr).1
      · exact Or.inl (by rw [subE_live, liftE_live]; exact (hown hr).1)
    · show ThruCanDo _ ((op.rename S.ρ).effAt d0.kind (decide ((S.subE (S.liftE d0.root Er)).ty = (S.liftE x Ex1).ty))
        (S.subE (S.liftE d0.root Er)).rvec)
      rw [hte, hve, hty1, Edit.effAt_rename]
      by_cases hr : Er.mode = .region
      · exact Or.inr ⟨(subE_liftE_region hr).1, hreg hr⟩
      · refine Or.inl ?_
        rw [subE_mode, liftE_mode _ hrbr]; exact canDo_lift (hown hr).2
    · show DtorSafe _ ((op.rename S.ρ).effAt d0.kind (decide ((S.subE (S.liftE d0.root Er)).ty = (S.liftE x Ex1).ty))
        (S.subE (S.liftE d0.root Er)).rvec) false _
      rw [hte, hve, hty1, Edit.effAt_rename]
      by_cases hr : Er.mode = .region
      · exact DtorSafe.canon h (allowed_region hab1 hEr hr _) hds
      · exact DtorSafe.canon h (allowed_canDo_false hab1 hEr (hown hr).2) hds
    · show HeldOK _ ((op.rename S.ρ).effAt d0.kind (decide ((S.subE (S.liftE d0.root Er)).ty = (S.liftE x Ex1).ty))
        (S.subE (S.liftE d0.root Er)).rvec) _
      rw [hte, hve, hty1, Edit.effAt_rename]
      by_cases hr : Er.mode = .region
      · exact HeldOK.canon h (allowed_region hab1 hEr hr _) hho
      · exact HeldOK.canon h (allowed_canDo_false hab1 hEr (hown hr).2) hho
  refine ⟨⟨D', harg'⟩, hyx', hthru', ?_⟩
  -- the kills: the callee's on regions first, which only weaken; the rest commute with the lift
  let f : Dep → Dep := fun d => ⟨d.root, .name (op.effAt d.kind (decide ((argE Γa1 d.root).ty = Ex1.ty))
    (argE Γa1 d.root).rvec) .int⟩
  have hthruD : thruDeps op Γa1 Ex1.ty Ex1.path = (memDeps Ex1.path).map f := rfl
  let p : Dep → Bool := fun d => !S.isPi d.root
  have hsplit := killNames_split p ((memDeps Ex1.path).map f) Γa1
  have hfp : ∀ q : Dep → Bool, (∀ d, q (f d) = q d) → ((memDeps Ex1.path).map f).filter q =
      ((memDeps Ex1.path).filter q).map f := by
    intro q hq; rw [List.filter_map]; congr 1
    apply List.filter_congr; intro d _; simp [Function.comp, hq]
  rw [hfp p (fun _ => rfl), hfp (fun d => !p d) (fun _ => rfl)] at hsplit
  let ΓR := A2.killNames (((memDeps Ex1.path).filter (fun d => !p d)).map f) Γa1
  have hRw : Weaker Γa1 ΓR := by
    refine weaker_killNames_region h hab1 hw1 hn1 _ fun d hd => ?_
    obtain ⟨d0, hd0', rfl⟩ := List.mem_map.mp hd
    obtain ⟨hd0, hp0⟩ := List.mem_filter.mp hd0'
    have hp0 : S.isPi d0.root = true := by simpa [p] using hp0
    obtain ⟨Er, hEr, _, _, hreg⟩ := hroot d0 hd0
    have hr : Er.mode = .region := (hab1.2.2.2.1 d0.root Er hEr).1.mpr (by
      rw [hab1.2.2.2.2.2 d0.root] at hp0; simp at hp0; exact hp0.1)
    have hae : argE Γa1 d0.root = Er := by unfold argE; rw [hEr]; rfl
    simp only [f, Kind.bound, hae]
    exact ⟨hreg hr, Edit.effAt_ne_replace _ _ _ _⟩
  have hcw := canon_weaker_sub h (hab1.killNames _) hRw
  have hcan : S.canon (A2.killNames (((memDeps Ex1.path).filter p).map f) ΓR) =
      A2.killNames (rds S.ρ (((memDeps Ex1.path).filter p).map f)) (S.canon ΓR) := by
    refine canon_killNames' h (hab1.killNames _) _ (fun d hd => ?_) (fun d hd => ?_) (fun d hd => ?_)
    all_goals
      obtain ⟨d0, hd0', rfl⟩ := List.mem_map.mp hd
      obtain ⟨hd0, hp0⟩ := List.mem_filter.mp hd0'
      have hnp0 : S.isPi d0.root = false := by simpa [p] using hp0
      obtain ⟨Er, hEr, _, hown, hreg⟩ := hroot d0 hd0
      have hae : argE Γa1 d0.root = Er := by unfold argE; rw [hEr]; rfl
      simp only [f, Kind.bound, hae]
    · by_cases hr : Er.mode = .region
      · exact allowed_region hab1 hEr hr _
      · exact allowed_canDo_false hab1 hEr (hown hr).2
    · exact hnp0
    · by_cases hr : Er.mode = .region
      · exact Or.inr (hreg hr)
      · exact Or.inl (hab1.notReg hEr hr)
  -- the call's own kills are the callee's on its roots that are no region, renamed
  have hthruD' : thruDeps (op.rename S.ρ) (S.canon Γa1) (S.liftE x Ex1).ty (S.subE (S.liftE x Ex1)).path =
      rds S.ρ (((memDeps Ex1.path).filter p).map f) := by
    unfold thruDeps
    rw [hmemS]
    simp only [rds, List.map_map]
    apply List.map_congr_left
    intro d hd
    obtain ⟨hd0, hnp0⟩ := List.mem_filter.mp hd
    have hnp0 : S.isPi d.root = false := by simpa [p] using hnp0
    obtain ⟨hte, hve⟩ := harge d hd0 hnp0
    simp only [Function.comp, Dep.ren, Edit.effAt_rename, hte, hve, hty1, f]
  have habT : S.AbsOK (A2.setE (A2.killThru op Ex1.ty Ex1.path Γa1) x Ex1) :=
    (hab1.killNames _).setE' hab1 hx1 rfl rfl hrb (fun hf => absurd hf (by simp [Entry.fixed, hmx]))
  have hcwT := canon_wf_sub h habT hwT hnT
  have hcnT := canon_names_sub h habT hnT
  rw [canon_setEs h _ hnpx] at hcwT hcnT ⊢
  unfold A2.killThru at hcwT hcnT ⊢
  rw [hthruD, hsplit, hcan] at hcwT hcnT ⊢
  rw [hthruD']
  have hkw : ∀ L : List Dep, Weaker (A2.killNames L (S.canon Γa1)) (A2.killNames L (S.canon ΓR)) := by
    intro L
    induction L with
    | nil => exact hcw
    | cons d L ih => exact ih.kill _ _ _
  exact ⟨PW.setE (hkw _).1 (EntryWeaker.refl _), hcwT, hcnT⟩

/-- AGORA-937 (3d): `editB_ren_facts` where the call is ready for a change
    through a region (`ThruReady`). -/
theorem editB_ren_facts_thru (h : S.OK) (hab : S.AbsOK Γa)
    {Fa : List Var} {Γa1 : Ctx} {x : Var} {op : Edit} {Ex Ex1 : Entry} {t : Ty}
    {D : List Dep} (hx : Γa x = some Ex) (hmx : Ex.mode = .bor) (hl : Ex.live = true)
    (hty : Ex.ty = .vec t)
    (harg : EditArg Γa Fa op t D Γa1) (hyx : ∀ y, op.stored = some y → y ≠ x) (hx1 : Γa1 x = some Ex1)
    (hl1 : Ex1.live = true) (hthru : ThruOKR Γa1 Fa op Ex.ty Ex1.path)
    (ht : S.ThruReady) (hvs : ∀ v ∈ op.vars, S.isPi v = false)
    (hnm : ∀ d ∈ Ex.path, d.kind.isName = true → S.isPi d.root = false)
    (hw1 : CtxWF Γa1) (hn1 : NameWF Γa1)
    (hwT : CtxWF (A2.setE (A2.killThru op Ex.ty Ex1.path Γa1) x Ex1))
    (hnT : NameWF (A2.setE (A2.killThru op Ex.ty Ex1.path Γa1) x Ex1)) :
    (∃ D', EditArg (S.canon Γa) S.Fc (op.rename S.ρ) t D' (S.canon Γa1)) ∧
    (∀ y, (op.rename S.ρ).stored = some y → y ≠ S.ρ x) ∧
    ThruOKR (S.canon Γa1) S.Fc (op.rename S.ρ) (S.liftE x Ex1).ty (S.subE (S.liftE x Ex1)).path ∧
    Weaker (A2.setE (A2.killThru (op.rename S.ρ) (S.liftE x Ex1).ty (S.subE (S.liftE x Ex1)).path (S.canon Γa1))
        (S.ρ x) (S.subE (S.liftE x Ex1)))
      (S.canon (A2.setE (A2.killThru op Ex.ty Ex1.path Γa1) x Ex1)) := by
  have hab1 : S.AbsOK Γa1 := EditArg.absOK harg hab
  have hE1 : Ex1 = Ex := harg.at_ne hyx hx hx1 hl1
  subst hE1
  have hrb : Ex1.mode ≠ .rootb := by rw [hmx]; simp
  have hty1 : (S.liftE x Ex1).ty = Ex1.ty := liftE_ty x hrb
  have hnpx : S.isPi x = false := hab1.notPi hx1 (by rw [hmx]; simp)
  -- each root of the change: an owner, or a region
  have hroot : ∀ d0 ∈ memDeps Ex1.path, ∃ Er, Γa1 d0.root = some Er ∧ Er.mode ≠ .rootb ∧
      (Er.mode ≠ .region → Er.live = true ∧ canDo Er.mode (op.effAt d0.kind (decide (Er.ty = Ex1.ty)) Er.rvec)) ∧
      (Er.mode = .region → (op.effAt d0.kind (decide (Er.ty = Ex1.ty)) Er.rvec).kills false .view = false) := by
    intro d0 hd0
    obtain ⟨_, _, Er, hEr, hlv, hcan, _, _⟩ := hthru d0 hd0
    refine ⟨Er, hEr, ?_, fun hnr => ⟨hlv.live hnr, hcan.toCanDo hnr⟩, fun hr => ?_⟩
    · rcases hcan with h' | ⟨h', _⟩
      · rcases h' with h' | ⟨b, h', _⟩ <;> rw [h'] <;> simp
      · rw [h']; simp
    · rcases hcan with h' | ⟨_, hk⟩
      · exfalso; have := h'.ownSlot; rw [hr] at this; cases this
      · exact hk
  -- every root's effect is the same where the call places it
  have harge : ∀ d0 ∈ memDeps Ex1.path, S.isPi d0.root = false →
      (argE (S.canon Γa1) (S.ρ d0.root)).ty = (argE Γa1 d0.root).ty ∧
      (argE (S.canon Γa1) (S.ρ d0.root)).rvec = (argE Γa1 d0.root).rvec := by
    intro d0 hd0 hnp0
    obtain ⟨Er, hEr, hrbr, hown, hreg⟩ := hroot d0 hd0
    have hae : argE Γa1 d0.root = Er := by unfold argE; rw [hEr]; rfl
    rw [argE_canons h hEr hnp0, hae]
    by_cases hr : Er.mode = .region
    · obtain ⟨_, ht, hv⟩ := subE_liftE_region (v := d0.root) hr; exact ⟨ht, hv⟩
    · exact ⟨by rw [subE_ty, liftE_ty _ hrbr], subE_liftE_rvec hrbr hr⟩
  -- what the change is handed, where the call places it
  obtain ⟨D', harg'⟩ : ∃ D', EditArg (S.canon Γa) S.Fc (op.rename S.ρ) t D' (S.canon Γa1) := by
    cases harg with
    | @push y _ _ _ _ hy hly htyy hpa =>
      have hnpy : S.isPi y = false := hvs y (by simp [Edit.vars])
      obtain ⟨D', hpa', _⟩ := pushArg_rens h hab hy hnpy hpa
      exact ⟨D', EditArg.push (canon_some h hy hnpy) (by rw [subE_live, liftE_live]; exact hly)
        (by rw [subE_ty, liftE_ty' h hab hy]; exact htyy) hpa'⟩
    | trunc hie =>
      exact ⟨[], EditArg.trunc (exprT_ren h hab hie (fun v hv => hvs v (by simpa [Edit.vars] using hv)))⟩
    | @set _ y _ _ _ _ hie hy hly htyy hpa =>
      have hnpy : S.isPi y = false := hvs y (by simp [Edit.vars])
      obtain ⟨D', hpa', _⟩ := pushArg_rens h hab hy hnpy hpa
      exact ⟨D', EditArg.set (exprT_ren h hab hie (fun v hv => hvs v (by simp [Edit.vars, hv])))
        (canon_some h hy hnpy) (by rw [subE_live, liftE_live]; exact hly)
        (by rw [subE_ty, liftE_ty' h hab hy]; exact htyy) hpa'⟩
  have hyx' : ∀ y, (op.rename S.ρ).stored = some y → y ≠ S.ρ x := by
    intro y hy
    rw [Edit.stored_rename] at hy
    obtain ⟨y0, hy0, rfl⟩ := Option.map_eq_some_iff.mp hy
    exact fun e => hyx y0 hy0 (h.inj _ _ e)
  -- a change through a region: inside its elements, so on each root it stands for, inside its elements
  have hreg_in : ∀ d0 ∈ memDeps Ex1.path, S.isPi d0.root = true →
      d0.kind = .inner ∧ op.effAt d0.kind (decide ((argE Γa1 d0.root).ty = Ex1.ty)) (argE Γa1 d0.root).rvec = .dropIn ∧
      ∃ Er, Γa1 d0.root = some Er ∧ Er.mode = .region := by
    intro d0 hd0 hp0
    obtain ⟨Er, hEr, _, _, hreg⟩ := hroot d0 hd0
    have hr : Er.mode = .region := (hab1.2.2.2.1 d0.root Er hEr).1.mpr (by
      rw [hab1.2.2.2.2.2 d0.root] at hp0; simp at hp0; exact hp0.1)
    have hae : argE Γa1 d0.root = Er := by unfold argE; rw [hEr]; rfl
    have hrv : Er.rvec = true := by simp [Entry.rvec, hr]
    have hk := hreg hr
    rw [hae, hrv]
    rw [hrv] at hk
    have hie : ∀ k, (Edit.inEff k true).kills false .view = false → k = .inner ∧ Edit.inEff k true = .dropIn := by
      intro k hk'
      unfold Edit.inEff at hk' ⊢
      by_cases hki : k = .inner
      · simp [hki]
      · simp [hki, Eff.kills] at hk'
    refine ⟨?_, ?_, Er, hEr, hr⟩
    · cases op with
      | push y =>
        simp only [Edit.effAt] at hk
        split at hk
        · simp [Eff.kills] at hk
        · exact (hie _ hk).1
      | trunc e => exact (hie _ hk).1
      | set e y => exact (hie _ hk).1
    · cases op with
      | push y =>
        simp only [Edit.effAt] at hk ⊢
        split at hk
        · simp [Eff.kills] at hk
        · rename_i hns; rw [ite_eq_right hns]; exact (hie _ hk).2
      | trunc e => exact (hie _ hk).2
      | set e y => exact (hie _ hk).2
  -- what a region stands for, reached through the change's path: inside a live owned `Vec`'s
  -- elements, where the caller's change is the callee's on the region
  have himg : ∀ d0 ∈ memDeps Ex1.path, S.isPi d0.root = true → ∀ e ∈ S.σ d0.root,
      comp e.kind d0.kind = .inner ∧ ∃ Er, S.canon Γa1 e.root = some Er ∧
        argE (S.canon Γa1) e.root = Er ∧ Er.live = true ∧ Er.mode = .own ∧
        ∀ b : Bool, (op.rename S.ρ).effAt (comp e.kind d0.kind) b Er.rvec = .dropIn := by
    intro d0 hd0 hp0 e he
    obtain ⟨hki, _, _, _, _⟩ := hreg_in d0 hd0 hp0
    obtain ⟨hσk, hroots⟩ := ht.2 d0.root hp0
    obtain ⟨_, _, _, _, _, Er, hEr, hErl, hErm, hErv⟩ := hroots e he
    have hck : comp e.kind d0.kind = .inner := by
      rw [hki]; rcases hσk e he with h' | h' <;> rw [h'] <;> rfl
    have hcan : S.canon Γa1 e.root = some Er := by rw [canon_frame _ (S.σ_frame h he).1]; exact hEr
    refine ⟨hck, Er, hcan, by unfold argE; rw [hcan]; rfl, hErl, hErm, fun b => ?_⟩
    rw [hck, hErv, Edit.effAt_rename]
    cases op <;> simp [Edit.effAt, Edit.inEff]
  have hthru' : ThruOKR (S.canon Γa1) S.Fc (op.rename S.ρ) (S.liftE x Ex1).ty (S.subE (S.liftE x Ex1)).path := by
    intro d hd
    rcases (S.mem_memDeps_subE_liftE_bor h ht hmx).mp hd with ⟨d0, hd0, hnp0, rfl⟩ | ⟨d0, hd0, hp0, e, he, rfl⟩
    · -- a root of the callee's, renamed: as before
      obtain ⟨_, hy0, Er, hEr, _, _, hds, hsh, hho⟩ := hthru d0 hd0
      obtain ⟨Er', hEr', hrbr, hown, hreg⟩ := hroot d0 hd0
      rw [hEr] at hEr'; cases hEr'
      have hae : argE Γa1 d0.root = Er := by unfold argE; rw [hEr]; rfl
      obtain ⟨hte, hve⟩ := harge d0 hd0 hnp0
      rw [hae] at hte hve
      rw [argE_canons h hEr hnp0] at hte hve
      refine ⟨h.Fcout _, fun y hy => ?_, S.subE (S.liftE d0.root Er), canon_some h hEr hnp0, ?_, ?_, ?_,
        ⟨by simpa [Dep.ren] using hsh, ?_⟩⟩
      · rw [Edit.stored_rename] at hy
        obtain ⟨y0, hy0', rfl⟩ := Option.map_eq_some_iff.mp hy
        exact fun e => hy0 y0 hy0' (h.inj _ _ e)
      · by_cases hr : Er.mode = .region
        · exact Or.inr (subE_liftE_region hr).1
        · exact Or.inl (by rw [subE_live, liftE_live]; exact (hown hr).1)
      · show ThruCanDo _ ((op.rename S.ρ).effAt d0.kind (decide ((S.subE (S.liftE d0.root Er)).ty = (S.liftE x Ex1).ty))
          (S.subE (S.liftE d0.root Er)).rvec)
        rw [hte, hve, hty1, Edit.effAt_rename]
        by_cases hr : Er.mode = .region
        · exact Or.inr ⟨(subE_liftE_region hr).1, hreg hr⟩
        · refine Or.inl ?_
          rw [subE_mode, liftE_mode _ hrbr]; exact canDo_lift (hown hr).2
      · show DtorSafe _ ((op.rename S.ρ).effAt d0.kind (decide ((S.subE (S.liftE d0.root Er)).ty = (S.liftE x Ex1).ty))
          (S.subE (S.liftE d0.root Er)).rvec) false _
        rw [hte, hve, hty1, Edit.effAt_rename]
        by_cases hr : Er.mode = .region
        · exact DtorSafe.canon h (allowed_region hab1 hEr hr _) hds
        · exact DtorSafe.canon h (allowed_canDo_false hab1 hEr (hown hr).2) hds
      · show HeldOK _ ((op.rename S.ρ).effAt d0.kind (decide ((S.subE (S.liftE d0.root Er)).ty = (S.liftE x Ex1).ty))
          (S.subE (S.liftE d0.root Er)).rvec) _
        rw [hte, hve, hty1, Edit.effAt_rename]
        by_cases hr : Er.mode = .region
        · exact HeldOK.canon h (allowed_region hab1 hEr hr _) hho
        · exact HeldOK.canon h (allowed_canDo_false hab1 hEr (hown hr).2) hho
    · -- what a region stands for: a live owned `Vec` of the frame's, changed inside its elements
      obtain ⟨_, heff, Eu, hEu, _⟩ := hreg_in d0 hd0 hp0
      obtain ⟨hσk, hroots⟩ := ht.2 d0.root hp0
      obtain ⟨hoth, hpe, _, hΦd, hFc, _⟩ := hroots e he
      have hout := (S.σ_frame h he).1
      obtain ⟨hck, Er, hcan, hae, hErl, hErm, heffE⟩ := himg d0 hd0 hp0 e he
      have heff' : (op.rename S.ρ).effAt (comp e.kind d0.kind)
          (decide ((argE (S.canon Γa1) e.root).ty = (S.liftE x Ex1).ty)) (argE (S.canon Γa1) e.root).rvec = .dropIn := by
        rw [hae]; exact heffE _
      obtain ⟨_, _, Eu', hEu', _, _, hds, _⟩ := hthru d0 hd0
      rw [hEu] at hEu'; cases hEu'
      have hds' : DtorSafe Γa1 .dropIn false d0.root := by
        have hae0 : argE Γa1 d0.root = Eu := by unfold argE; rw [hEu]; rfl
        have he' := heff; rw [hae0] at he'; rw [he'] at hds; exact hds
      refine ⟨hFc, fun y hy => ?_, Er, hcan, Or.inl hErl, ?_, ?_, by simp [hck], ?_⟩
      · rw [Edit.stored_rename] at hy
        obtain ⟨y0, _, rfl⟩ := Option.map_eq_some_iff.mp hy
        exact fun e' => hout y0 e'.symm
      · show ThruCanDo Er ((op.rename S.ρ).effAt (comp e.kind d0.kind) (decide (Er.ty = (S.liftE x Ex1).ty)) Er.rvec)
        rw [← hae, heff']; exact Or.inl (Or.inl (by rw [hae]; exact hErm))
      · show DtorSafe (S.canon Γa1) ((op.rename S.ρ).effAt (comp e.kind d0.kind) (decide (Er.ty = (S.liftE x Ex1).ty))
          Er.rvec) false e.root
        rw [← hae, heff']
        exact dtorSafe_region h hab1 hp0 hσk ⟨e, he, rfl⟩ hoth (fun d hd _ => ht.A_name h hd) hpe hΦd hds'
      · show HeldOK (S.canon Γa1) ((op.rename S.ρ).effAt (comp e.kind d0.kind) (decide (Er.ty = (S.liftE x Ex1).ty))
          Er.rvec) e.root
        rw [← hae, heff']; exact HeldOK.of_kills _ rfl rfl
  refine ⟨⟨D', harg'⟩, hyx', hthru', ?_⟩
  -- the kills: the callee's on its own roots, renamed; on a region standing for nothing,
  -- which only weaken; on a region standing for roots, the caller's on those roots
  let f : Dep → Dep := fun d => ⟨d.root, .name (op.effAt d.kind (decide ((argE Γa1 d.root).ty = Ex1.ty))
    (argE Γa1 d.root).rvec) .int⟩
  have hthruD : thruDeps op Γa1 Ex1.ty Ex1.path = (memDeps Ex1.path).map f := rfl
  let M := memDeps Ex1.path
  let p : Dep → Bool := fun d => !S.isPi d.root
  let qn : Dep → Bool := fun d => S.isPi d.root && !(S.σ d.root).isEmpty
  let qe : Dep → Bool := fun d => S.isPi d.root && (S.σ d.root).isEmpty
  let Lnr := (M.filter p).map f
  let Lne := (M.filter qn).map f
  let Le := (M.filter qe).map f
  have hmemL : ∀ d, d ∈ M.map f ↔ d ∈ Lnr ++ (Lne ++ Le) := by
    intro d
    constructor
    · intro hd
      obtain ⟨d0, hd0, rfl⟩ := List.mem_map.mp hd
      cases hp : S.isPi d0.root
      · exact List.mem_append_left _ (List.mem_map.mpr ⟨d0, List.mem_filter.mpr ⟨hd0, by simp [p, hp]⟩, rfl⟩)
      · cases he : (S.σ d0.root).isEmpty
        · exact List.mem_append_right _ (List.mem_append_left _
            (List.mem_map.mpr ⟨d0, List.mem_filter.mpr ⟨hd0, by simp [qn, hp, he]⟩, rfl⟩))
        · exact List.mem_append_right _ (List.mem_append_right _
            (List.mem_map.mpr ⟨d0, List.mem_filter.mpr ⟨hd0, by simp [qe, hp, he]⟩, rfl⟩))
    · intro hd
      rcases List.mem_append.mp hd with hd | hd
      · obtain ⟨d0, hd0, rfl⟩ := List.mem_map.mp hd; exact List.mem_map_of_mem (List.mem_filter.mp hd0).1
      · rcases List.mem_append.mp hd with hd | hd
        · obtain ⟨d0, hd0, rfl⟩ := List.mem_map.mp hd; exact List.mem_map_of_mem (List.mem_filter.mp hd0).1
        · obtain ⟨d0, hd0, rfl⟩ := List.mem_map.mp hd; exact List.mem_map_of_mem (List.mem_filter.mp hd0).1
  have hsplit : A2.killNames (M.map f) Γa1 = A2.killNames Lnr (A2.killNames Lne (A2.killNames Le Γa1)) := by
    rw [killNames_congr hmemL, killNames_append, killNames_append]
  have hfreg : ∀ d0 ∈ M, S.isPi d0.root = true → (f d0).kind = .name .dropIn .int := by
    intro d0 hd0 hp0
    simp only [f, (hreg_in d0 hd0 hp0).2.1]
  let ΓE := A2.killNames Le Γa1
  let ΓN := A2.killNames Lne ΓE
  have hRw : Weaker Γa1 ΓE := by
    refine weaker_killNames_region h hab1 hw1 hn1 _ fun d hd => ?_
    obtain ⟨d0, hd0', rfl⟩ := List.mem_map.mp hd
    obtain ⟨hd0, hq⟩ := List.mem_filter.mp hd0'
    have hp0 : S.isPi d0.root = true := by simp only [qe, Bool.and_eq_true] at hq; exact hq.1
    rw [hfreg d0 hd0 hp0]; exact ⟨rfl, by decide⟩
  have hcw := canon_weaker_sub h (hab1.killNames _) hRw
  have hne : S.canon ΓN = A2.killNames (Lne.flatMap fun d => (S.σ d.root).map regionKill) (S.canon ΓE) := by
    refine (canon_killNames_region h ht Lne (fun d hd => ?_) ΓE (hab1.killNames _)).symm
    obtain ⟨d0, hd0', rfl⟩ := List.mem_map.mp hd
    obtain ⟨hd0, hq⟩ := List.mem_filter.mp hd0'
    simp only [qn, Bool.and_eq_true, Bool.not_eq_true'] at hq
    refine ⟨hq.1, hfreg d0 hd0 hq.1, ?_⟩
    intro hn; rw [hn] at hq; simp at hq
  have habN : S.AbsOK ΓN := (hab1.killNames _).killNames _
  have hcan : S.canon (A2.killNames Lnr ΓN) = A2.killNames (rds S.ρ Lnr) (S.canon ΓN) := by
    refine canon_killNames' h habN _ (fun d hd => ?_) (fun d hd => ?_) (fun d hd => ?_)
    all_goals
      obtain ⟨d0, hd0', rfl⟩ := List.mem_map.mp hd
      obtain ⟨hd0, hp0⟩ := List.mem_filter.mp hd0'
      have hnp0 : S.isPi d0.root = false := by simpa [p] using hp0
      obtain ⟨Er, hEr, _, hown, hreg⟩ := hroot d0 hd0
      have hae : argE Γa1 d0.root = Er := by unfold argE; rw [hEr]; rfl
      simp only [f, Kind.bound, hae]
    · by_cases hr : Er.mode = .region
      · exact allowed_region hab1 hEr hr _
      · exact allowed_canDo_false hab1 hEr (hown hr).2
    · exact hnp0
    · by_cases hr : Er.mode = .region
      · exact Or.inr (hreg hr)
      · exact Or.inl (hab1.notReg hEr hr)
  -- the caller's kills: its own roots' renamed, and the roots the regions stand for
  have hthruD' : ∀ d, d ∈ thruDeps (op.rename S.ρ) (S.canon Γa1) (S.liftE x Ex1).ty (S.subE (S.liftE x Ex1)).path ↔
      d ∈ rds S.ρ Lnr ++ Lne.flatMap fun d => (S.σ d.root).map regionKill := by
    intro d
    unfold thruDeps
    simp only [List.mem_map, List.mem_append, List.mem_flatMap]
    constructor
    · rintro ⟨d', hd', rfl⟩
      rcases (S.mem_memDeps_subE_liftE_bor h ht hmx).mp hd' with ⟨d0, hd0, hnp0, rfl⟩ | ⟨d0, hd0, hp0, e, he, rfl⟩
      · left
        obtain ⟨hte, hve⟩ := harge d0 hd0 hnp0
        refine mem_rds.mpr ⟨f d0, List.mem_map.mpr ⟨d0, List.mem_filter.mpr ⟨hd0, by simp [p, hnp0]⟩, rfl⟩, ?_⟩
        simp only [f, Dep.ren, Edit.effAt_rename, hte, hve, hty1]
      · right
        obtain ⟨hck, Er, _, hae, _, _, heffE⟩ := himg d0 hd0 hp0 e he
        have hσne : (S.σ d0.root).isEmpty = false := by
          cases hσ : S.σ d0.root with
          | nil => rw [hσ] at he; cases he
          | cons _ _ => rfl
        refine ⟨f d0, List.mem_map.mpr ⟨d0, List.mem_filter.mpr ⟨hd0, by simp [qn, hp0, hσne]⟩, rfl⟩,
          e, he, ?_⟩
        simp only [regionKill, hae, heffE]
    · rintro (hd | ⟨d1, hd1, hd⟩)
      · obtain ⟨d2, hd2, rfl⟩ := mem_rds.mp hd
        obtain ⟨d0, hd0', rfl⟩ := List.mem_map.mp hd2
        obtain ⟨hd0, hp0⟩ := List.mem_filter.mp hd0'
        have hnp0 : S.isPi d0.root = false := by simpa [p] using hp0
        obtain ⟨hte, hve⟩ := harge d0 hd0 hnp0
        refine ⟨d0.ren S.ρ, (S.mem_memDeps_subE_liftE_bor h ht hmx).mpr (Or.inl ⟨d0, hd0, hnp0, rfl⟩), ?_⟩
        simp only [f, Dep.ren, Edit.effAt_rename, hte, hve, hty1]
      · obtain ⟨d0, hd0', rfl⟩ := List.mem_map.mp hd1
        obtain ⟨hd0, hq⟩ := List.mem_filter.mp hd0'
        have hp0 : S.isPi d0.root = true := by simp only [qn, Bool.and_eq_true] at hq; exact hq.1
        obtain ⟨e, he, rfl⟩ := hd
        obtain ⟨_, Er, _, hae, _, _, heffE⟩ := himg d0 hd0 hp0 e he
        refine ⟨⟨e.root, comp e.kind d0.kind⟩,
          (S.mem_memDeps_subE_liftE_bor h ht hmx).mpr (Or.inr ⟨d0, hd0, hp0, e, he, rfl⟩), ?_⟩
        simp only [regionKill, hae, heffE]
  have habT : S.AbsOK (A2.setE (A2.killThru op Ex1.ty Ex1.path Γa1) x Ex1) :=
    (hab1.killNames _).setE' hab1 hx1 rfl rfl hrb (fun hf => absurd hf (by simp [Entry.fixed, hmx]))
  have hcwT := canon_wf_sub h habT hwT hnT
  have hcnT := canon_names_sub h habT hnT
  rw [canon_setEs h _ hnpx] at hcwT hcnT ⊢
  unfold A2.killThru at hcwT hcnT ⊢
  rw [hthruD, hsplit, hcan, hne] at hcwT hcnT ⊢
  rw [← killNames_append] at hcwT hcnT ⊢
  rw [killNames_congr hthruD']
  have hkw : ∀ L : List Dep, Weaker (A2.killNames L (S.canon Γa1)) (A2.killNames L (S.canon ΓE)) := by
    intro L
    induction L with
    | nil => exact hcw
    | cons d L ih => exact ih.kill _ _ _
  exact ⟨PW.setE (hkw _).1 (EntryWeaker.refl _), hcwT, hcnT⟩

theorem editB_ren (h : S.OK) (hab : S.AbsOK Γa)
    {P : Prog} {Fa : List Var} {Γa1 : Ctx} {x : Var} {op : Edit} {Ex Ex1 : Entry} {t : Ty}
    {D : List Dep} {b : Bool} (hx : Γa x = some Ex) (hmx : Ex.mode = .bor) (hl : Ex.live = true)
    (hty : Ex.ty = .vec t) (hhv : t.holdsView = false)
    (harg : EditArg Γa Fa op t D Γa1) (hyx : ∀ y, op.stored = some y → y ≠ x) (hx1 : Γa1 x = some Ex1)
    (hl1 : Ex1.live = true) (hthru : ThruOKR Γa1 Fa op Ex.ty Ex1.path)
    (hdf : op.drops = true → t.dtorFree = true) (hbf : b = false → Ex.fresh = true)
    (hloc : S.R = [] ∨ Ex.fresh = true) (hvs : ∀ v ∈ op.vars, S.isPi v = false)
    (hnm : ∀ d ∈ Ex.path, d.kind.isName = true → S.isPi d.root = false)
    (hRp : ∀ d0 ∈ memDeps Ex.path, S.isPi d0.root = true → S.R = [])
    (hw : CtxWF Γa) (hn : NameWF Γa)
    (hwT : CtxWF (A2.setE (A2.killThru op Ex.ty Ex1.path Γa1) x Ex1))
    (hnT : NameWF (A2.setE (A2.killThru op Ex.ty Ex1.path Γa1) x Ex1)) :
    StmtT P ξ (S.canon Γa) S.Fc ((Stmt.edit b x op).rename S.ρ)
      (S.canon (A2.setE (A2.killThru op Ex.ty Ex1.path Γa1) x Ex1)) := by
  obtain ⟨⟨D', harg'⟩, hyx', hthru', hW⟩ :=
    editB_ren_facts h hab hx hmx hl hty harg hyx hx1 hl1 hthru hloc hvs hnm hRp (harg.wf hw) (harg.names hn)
      hwT hnT
  have hE1 : Ex1 = Ex := harg.at_ne hyx hx hx1 hl1
  subst hE1
  have hrb : Ex1.mode ≠ .rootb := by rw [hmx]; simp
  have hty1 : (S.liftE x Ex1).ty = Ex1.ty := liftE_ty x hrb
  have hnpx : S.isPi x = false := hab.notPi hx (by rw [hmx]; simp)
  have hT := StmtT.editB (P := P) (ξ := ξ) (x := S.ρ x) (Ex := S.subE (S.liftE x Ex1))
    (Ex1 := S.subE (S.liftE x Ex1))
    (canon_some h hx hnpx) (by rw [subE_mode, liftE_mode x hrb, hmx]; rfl)
    (by rw [subE_live, liftE_live]; exact hl)
    (by rw [subE_ty, hty1]; exact hty) hhv (h.Fcout x) harg' hyx' (canon_some h hx1 hnpx)
    (by rw [subE_live, liftE_live]; exact hl1) (by rw [subE_ty]; exact hthru')
    (by rw [Edit.drops_rename]; exact hdf) (b := b)
    (fun hb0 => by rw [subE_fresh, S.liftE_fresh_of hrb]; exact hbf hb0)
  rw [subE_ty] at hT
  -- AGORA-937 (item 3): what the call knows after the change is at least what the callee does
  exact StmtT.sub (Weaker.refl (canon_wf_sub h hab hw hn) (canon_names_sub h hab hn)) hT (Or.inr hW)

/-- AGORA-937 (3d): `editB_ren` where the call is ready for a change through a region. -/
theorem editB_ren_thru (h : S.OK) (hab : S.AbsOK Γa)
    {P : Prog} {Fa : List Var} {Γa1 : Ctx} {x : Var} {op : Edit} {Ex Ex1 : Entry} {t : Ty}
    {D : List Dep} {b : Bool} (hx : Γa x = some Ex) (hmx : Ex.mode = .bor) (hl : Ex.live = true)
    (hty : Ex.ty = .vec t) (hhv : t.holdsView = false)
    (harg : EditArg Γa Fa op t D Γa1) (hyx : ∀ y, op.stored = some y → y ≠ x) (hx1 : Γa1 x = some Ex1)
    (hl1 : Ex1.live = true) (hthru : ThruOKR Γa1 Fa op Ex.ty Ex1.path)
    (hdf : op.drops = true → t.dtorFree = true) (hbf : b = false → Ex.fresh = true)
    (ht : S.ThruReady) (hvs : ∀ v ∈ op.vars, S.isPi v = false)
    (hnm : ∀ d ∈ Ex.path, d.kind.isName = true → S.isPi d.root = false)
    (hw : CtxWF Γa) (hn : NameWF Γa)
    (hwT : CtxWF (A2.setE (A2.killThru op Ex.ty Ex1.path Γa1) x Ex1))
    (hnT : NameWF (A2.setE (A2.killThru op Ex.ty Ex1.path Γa1) x Ex1)) :
    StmtT P ξ (S.canon Γa) S.Fc ((Stmt.edit b x op).rename S.ρ)
      (S.canon (A2.setE (A2.killThru op Ex.ty Ex1.path Γa1) x Ex1)) := by
  obtain ⟨⟨D', harg'⟩, hyx', hthru', hW⟩ :=
    editB_ren_facts_thru h hab hx hmx hl hty harg hyx hx1 hl1 hthru ht hvs hnm (harg.wf hw) (harg.names hn)
      hwT hnT
  have hE1 : Ex1 = Ex := harg.at_ne hyx hx hx1 hl1
  subst hE1
  have hrb : Ex1.mode ≠ .rootb := by rw [hmx]; simp
  have hty1 : (S.liftE x Ex1).ty = Ex1.ty := liftE_ty x hrb
  have hnpx : S.isPi x = false := hab.notPi hx (by rw [hmx]; simp)
  have hT := StmtT.editB (P := P) (ξ := ξ) (x := S.ρ x) (Ex := S.subE (S.liftE x Ex1))
    (Ex1 := S.subE (S.liftE x Ex1))
    (canon_some h hx hnpx) (by rw [subE_mode, liftE_mode x hrb, hmx]; rfl)
    (by rw [subE_live, liftE_live]; exact hl)
    (by rw [subE_ty, hty1]; exact hty) hhv (h.Fcout x) harg' hyx' (canon_some h hx1 hnpx)
    (by rw [subE_live, liftE_live]; exact hl1) (by rw [subE_ty]; exact hthru')
    (by rw [Edit.drops_rename]; exact hdf) (b := b)
    (fun hb0 => by rw [subE_fresh, S.liftE_fresh_of hrb]; exact hbf hb0)
  rw [subE_ty] at hT
  -- AGORA-937 (item 3): what the call knows after the change is at least what the callee does
  exact StmtT.sub (Weaker.refl (canon_wf_sub h hab hw hn) (canon_names_sub h hab hn)) hT (Or.inr hW)

/-! ### Agora #295: a view stored through a borrow, where the call places it -/

theorem AbsOK.killHv {Γ : Ctx} (hab : S.AbsOK Γ) : ∀ ks, S.AbsOK (A2.killHv ks Γ)
  | [] => hab
  | (_, _, _) :: ks => show S.AbsOK (A2.kill _ _ _ (A2.killHv ks Γ)) from (AbsOK.killHv hab ks).kill _ _ _

theorem canon_killHv (h : S.OK) {Γ : Ctx} (hab : S.AbsOK Γ) :
    ∀ (ks : List (Eff × Bool × Var)), (∀ k ∈ ks, Allowed S k.1 k.2.1 k.2.2) →
      (∀ k ∈ ks, S.isPi k.2.2 = false) → (∀ k ∈ ks, S.isReg k.2.2 = false) →
      S.canon (A2.killHv ks Γ) = A2.killHv (ks.map fun k => (k.1, k.2.1, S.ρ k.2.2)) (S.canon Γ)
  | [], _, _, _ => rfl
  | (e, b, r) :: ks, hal, hnp, hnr => by
    show S.canon (A2.kill e b r (A2.killHv ks Γ)) = A2.kill e b (S.ρ r) (A2.killHv _ (S.canon Γ))
    rw [canon_kill h (hab.killHv ks) (hal _ List.mem_cons_self) (hnp _ List.mem_cons_self)
        (hnr _ List.mem_cons_self),
      canon_killHv h hab ks (fun k hk => hal k (List.mem_cons_of_mem _ hk))
        (fun k hk => hnp k (List.mem_cons_of_mem _ hk)) (fun k hk => hnr k (List.mem_cons_of_mem _ hk))]

/-- Holding more, at bindings that are no borrowed parameter: a fixed
    `inout` parameter's type holds no views, so it holds nothing more. -/
theorem AbsOK.holdOn {Γ : Ctx} (hab : S.AbsOK Γ) {rs : List Var} {D : List Dep}
    (hrs : ∀ v ∈ rs, ∀ E, Γ v = some E → E.mode ≠ .rootb) : S.AbsOK (A2.holdOn rs D Γ) := by
  refine ⟨fun v E' hv hm => ?_, fun v E' b hv hm => ?_, fun v bh hb => ?_, fun v E' hv => by
    obtain ⟨E, hE, rfl⟩ := holdOn_get hv
    split <;> (try simp only [Entry.hold_mode]) <;> exact hab.2.2.2.1 v E hE, fun v hp => by
    obtain ⟨E, hE, hm⟩ := hab.2.2.2.2.1 v hp
    refine ⟨if v ∈ rs then E.hold D else E, by rw [holdOn_some hE], ?_⟩
    split <;> (try simp only [Entry.hold_mode]) <;> exact hm, hab.2.2.2.2.2⟩
  · obtain ⟨E, hE, rfl⟩ := holdOn_get hv
    by_cases hvr : v ∈ rs
    · rw [ite_eq_left hvr] at hm; exact absurd hm (hrs v hvr E hE)
    · rw [ite_eq_right hvr] at hm ⊢; exact hab.1 v E hE hm
  · obtain ⟨E, hE, rfl⟩ := holdOn_get hv
    have hmt : (if v ∈ rs then E.hold D else E).mode = E.mode ∧
        (if v ∈ rs then E.hold D else E).ty = E.ty := by split <;> exact ⟨rfl, rfl⟩
    rw [hmt.1] at hm; rw [hmt.2]; exact hab.2.1 v E b hE hm
  · obtain ⟨E, hE, hm, hty, hfx⟩ := hab.2.2.1 v bh hb
    refine ⟨_, holdOn_some hE, by split <;> exact hm, by split <;> exact hty, fun hf => ?_⟩
    have hf0 : E.fixed := by simp only [Entry.fixed_def] at hf ⊢; split at hf <;> exact hf
    have hv : E.ty.holdsView = false := by
      rcases hf0 with h' | ⟨b, _, _, hv⟩
      · rw [hm] at h'; cases h'
      · exact hv
    rw [E.hold_noView hv, ite_self]; exact hfx hf0

/-- A callee binding that holds `D'` too, where the call places it, says no
    more than the lifted binding holding `D`, when `D'` is `D` renamed or
    less. -/
theorem liftE_hold_weaker {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) (hdb : E.dbind = false)
    (hos : E.mode.ownSlot = true)
    {D D' : List Dep} (hD : D' ⊆ rds S.ρ D ++ S.A) : EntryWeaker ((S.liftE v E).hold D') (S.liftE v (E.hold D)) := by
  have hl : ∀ E0 : Entry, E0.mode ≠ .rootb → S.liftE v E0 = ⟨E0.ty, liftMode E0.mode, E0.live,
      rds S.ρ E0.path ++ (if E0.mode.ownSlot || (E0.fresh && E0.ty != .int) then [] else S.A),
      rds S.ρ E0.held ++ ownHeld E0.mode.ownSlot E0.ty (S.heldA E0), E0.dtor, E0.dbind, E0.fresh,
      E0.heldFresh⟩ := fun E0 h0 => by
    simp only [RSetup.liftE, h0, ↓reduceIte]
  have hrb' : (E.hold D).mode ≠ .rootb := hrb
  have hhA : S.heldA (E.hold D) = S.heldA E := rfl
  rw [hl E hrb, hl (E.hold D) hrb']
  refine ⟨rfl, rfl, fun hf => absurd hf ?_, fun hl' => ⟨hl', fun _ => List.Subset.refl _, ?_⟩,
    fun h => ⟨h, ?_⟩, rfl, fun h => Or.inl h, fun h => by simp [Entry.hold, hdb] at h,
      fun _ _ _ hfr => ⟨hfr, List.Subset.refl _⟩,
      fun _ _ hhf => hhf⟩
  · intro hf
    rcases hf with h' | ⟨b, h', _⟩
    · exact hrb (liftMode_rootb.mp h')
    · cases hm : E.mode <;> rw [hm] at h' <;> simp [liftMode] at h'
  all_goals
    rw [hhA]
    simp only [Entry.hold, rds, List.map_append]
    intro d hd
    simp only [List.mem_append] at hd ⊢
    rcases hd with (hd | hd) | hd
    · exact Or.inl (Or.inl hd)
    · exact Or.inr hd
    · by_cases hv : E.ty.holdsView = true
      · rw [ownHeld_views true hv] at hd
        rcases List.mem_append.mp (hD hd) with h1 | h1
        · refine Or.inl (Or.inr ?_)
          rw [ownHeld_views true hv]
          obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
          exact List.mem_map_of_mem hd0
        · -- (what the arguments hold, which an owner of a type that holds
          -- views is lifted with already)
          refine Or.inr ?_
          rw [S.heldA_own hos, hos, ownHeld_views true hv]; exact h1
      · have hv' : E.ty.holdsView = false := by simpa using hv
        simp [ownHeld, hv'] at hd

/-- AGORA-937: the substitution commutes with holding more. -/
theorem subE_hold (E : Entry) (D : List Dep) : S.subE (E.hold D) = (S.subE E).hold (D.flatMap S.subD) := by
  unfold subE Entry.hold ownHeld
  simp only [List.flatMap_append]
  split <;> simp_all

/-- ... and holding less is stronger. -/
theorem ew_hold_mono {E : Entry} (hrb : E.mode ≠ .rootb) (hdb : E.dbind = false) {A B : List Dep}
    (hAB : A ⊆ B) : EntryWeaker (E.hold A) (E.hold B) := by
  have hsub : (E.hold A).held ⊆ (E.hold B).held := by
    unfold Entry.hold ownHeld
    split
    · exact List.Subset.refl _
    · exact fun d hd => by
        rcases List.mem_append.mp hd with h1 | h1
        · exact List.mem_append_left _ h1
        · exact List.mem_append_right _ (hAB h1)
  refine ⟨rfl, rfl, fun hf => ?_, fun hl => ⟨hl, fun _ => List.Subset.refl _, hsub⟩,
    fun hd => ⟨hd, hsub⟩, rfl, fun h => Or.inl h, fun h => by simp [Entry.hold, hdb] at h,
    fun _ _ _ hfr => ⟨hfr, List.Subset.refl _⟩, fun _ _ hhf => hhf⟩
  rcases hf with h' | ⟨b, _, _, hv⟩
  · exact absurd h' hrb
  · have hv' : E.ty.holdsView = false := by simpa [Entry.hold] using hv
    simp [Entry.hold, ownHeld, hv']

/-- AGORA-937: `liftE_hold_weaker` with regions: what the rule's change
    through a borrow makes its roots hold is at least as strong as the
    substituted lift of what they hold in the callee. -/
theorem liftE_hold_weakers {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) (hdb : E.dbind = false)
    (hos : E.mode.ownSlot = true) {D D' : List Dep} (hD : D' ⊆ (rds S.ρ D ++ S.A).flatMap S.subD) :
    EntryWeaker ((S.subE (S.liftE v E)).hold D') (S.subE (S.liftE v (E.hold D))) := by
  have hrb' : (S.subE (S.liftE v E)).mode ≠ .rootb := by
    rw [subE_mode, liftE_mode v hrb]; exact fun e => hrb (liftMode_rootb.mp e)
  have hdb' : (S.subE (S.liftE v E)).dbind = false := by
    simp only [subE_dbind, RSetup.liftE, hrb, ↓reduceIte]; exact hdb
  refine (ew_hold_mono hrb' hdb' hD).trans ?_
  rw [← subE_hold]
  exact S.subE_weaker (liftE_hold_weaker hrb hdb hos (List.Subset.refl _))

/-- The roots holding more, where the call places them: what the rule says
    is at least as strong as the lifted context (AGORA-937: substituted). -/
theorem PW.holdOn_canons (h : S.OK) {Γ : Ctx} {rs : List Var} {D D' : List Dep}
    (hD : D' ⊆ (rds S.ρ D ++ S.A).flatMap S.subD)
    (hrs : ∀ v ∈ rs, ∀ E, Γ v = some E → E.mode ≠ .rootb ∧ E.dbind = false ∧ E.mode.ownSlot = true) :
    PW (A2.holdOn (rs.map S.ρ) D' (S.canon Γ)) (S.canon (A2.holdOn rs D Γ)) := by
  intro y
  have hmem : ∀ v, S.ρ v ∈ rs.map S.ρ ↔ v ∈ rs := fun v => by
    constructor
    · intro hm; obtain ⟨w, hw, he⟩ := List.mem_map.mp hm; rw [← h.inj _ _ he]; exact hw
    · exact List.mem_map_of_mem
  rcases canon_cases_sub h Γ y with ⟨v, rfl, hp, hc⟩ | ⟨v, rfl, hp, hc⟩ | ⟨hy, hc⟩
  · rw [canon_ρs h _ hp]
    cases hE : Γ v with
    | none =>
      rw [A2.holdOn, hc, hE]; simp [A2.holdOn, hE]
    | some E =>
      rw [A2.holdOn, hc, hE, holdOn_some hE]
      refine ⟨by simp, fun E1 E2 h1 h2 => ?_⟩
      simp only [Option.map_some, Option.some.injEq, Function.comp] at h1 h2
      subst h1 h2
      by_cases hvr : v ∈ rs
      · rw [ite_eq_left ((hmem v).mpr hvr), ite_eq_left hvr]
        exact liftE_hold_weakers (hrs v hvr E hE).1 (hrs v hvr E hE).2.1 (hrs v hvr E hE).2.2 hD
      · rw [ite_eq_right (fun h' => hvr ((hmem v).mp h')), ite_eq_right hvr]
        exact EntryWeaker.refl _
  · rw [canon_ρ_sub h, hp]
    simp [A2.holdOn, hc]
  · have hyr : y ∉ rs.map S.ρ := fun hm => by
      obtain ⟨w, _, he⟩ := List.mem_map.mp hm; exact hy w he
    rw [canon_frame _ hy]
    cases hE : S.Φ y with
    | none => simp [A2.holdOn, hc, hE]
    | some E =>
      refine ⟨by simp [A2.holdOn, hc, hE], fun E1 E2 h1 h2 => ?_⟩
      simp only [A2.holdOn, hc, hE, Option.map_some, Option.some.injEq, ite_eq_right hyr] at h1
      subst h1; cases Option.some.inj h2; exact EntryWeaker.refl _

/-- Agora #295: what `editBV_ren` needs of a change through a borrow `x`
    of element type that holds views, where a call places it: the path's
    memory dependencies renamed, the roots allowing it there (`ThruOK`), the
    kills commuting with the lift, and `ThruV` for anything stored that is
    the renamed `DD` or less.  (Shared with `takeBV`, AGORA-897.) -/
theorem editBV_ren_facts (h : S.OK)
    {Fa : List Var} {Γa1 : Ctx} {x : Var} {op : Edit} {Ex1 : Entry} {DD : List Dep}
    (hab1 : S.AbsOK Γa1) (hmx : Ex1.mode = .bor)
    (hthru : ThruOK Γa1 Fa op Ex1.ty Ex1.path) (hV : ThruV Γa1 op Ex1.ty Ex1.path DD)
    (hloc : S.Rf = [] ∨ (Ex1.fresh = true ∧ Ex1.ty ≠ .int))
    (hnm : ∀ d ∈ Ex1.path, d.kind.isName = true → S.isPi d.root = false) :
    memDeps (S.liftE x Ex1).path = rds S.ρ (memDeps Ex1.path) ∧
    ThruOK (S.canon Γa1) S.Fc (op.rename S.ρ) (S.liftE x Ex1).ty (S.liftE x Ex1).path ∧
    S.canon (killThruV op Ex1.ty Ex1.path Γa1) =
      killThruV (op.rename S.ρ) (S.liftE x Ex1).ty (S.liftE x Ex1).path (S.canon Γa1) ∧
    (∀ D2, D2 ⊆ (rds S.ρ DD ++ S.A).flatMap S.subD →
      ThruV (S.canon Γa1) (op.rename S.ρ) (S.liftE x Ex1).ty (S.liftE x Ex1).path D2) ∧
    (S.subE (S.liftE x Ex1)).path = (S.liftE x Ex1).path := by
  have hrb : Ex1.mode ≠ .rootb := by rw [hmx]; simp
  -- the lift adds names only: what the outer call's arguments held by name
  have hpath : (S.liftE x Ex1).path = rds S.ρ Ex1.path ++ (if Ex1.fresh && Ex1.ty != .int then [] else S.A) := by
    simp [liftE, hmx, Mode.ownSlot]
  -- the lift adds names only: what the outer call's arguments held by name; or
  -- (Agora #909) nothing at all, for a fresh borrow
  have hmem : memDeps (S.liftE x Ex1).path = rds S.ρ (memDeps Ex1.path) := by
    rw [hpath]
    split
    · rw [List.append_nil]; unfold memDeps; simp only [rds, List.filter_map]; rfl
    · rename_i hnf
      rcases hloc with hR | hf
      · have hmemA : memDeps S.A = [] := by
          unfold RSetup.A; rw [hR]
          simp only [compAll, List.flatMap_nil, List.nil_append]
          exact List.filter_eq_nil_iff.mpr fun d hd => by simp [h.N_name d hd]
        unfold memDeps at hmemA ⊢
        rw [List.filter_append, hmemA, List.append_nil]
        simp only [rds, List.filter_map]; rfl
      · exfalso; apply hnf; simp [hf.1, hf.2]
  have hty1 : (S.liftE x Ex1).ty = Ex1.ty := liftE_ty x hrb
  -- AGORA-937: no memory root of the path is a region: each owns its slot
  -- (`ThruOK`)
  have hroot : ∀ d0 ∈ memDeps Ex1.path, S.isPi d0.root = false := fun d0 hd0 => by
    obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d0 hd0
    exact hab1.notPi hEr (fun e => by have := hcan.ownSlot; rw [e] at this; cases this)
  -- ... so the substitution keeps the lifted path
  have hpfix : (S.subE (S.liftE x Ex1)).path = (S.liftE x Ex1).path := subE_liftE_path_bor h hmx hroot hnm
  -- every root keeps its type where the call places it
  have hargty : ∀ r, S.isPi r = false → (argE (S.canon Γa1) (S.ρ r)).ty = (argE Γa1 r).ty := by
    intro r hnp
    cases hr : Γa1 r with
    | none => unfold argE; rw [canon_ρs h _ hnp, hr]; rfl
    | some Er => rw [argE_canons h hr hnp, subE_ty, liftE_ty' h hab1 hr]; unfold argE; rw [hr]; rfl
  have hrv : ∀ d0 ∈ memDeps Ex1.path, (argE (S.canon Γa1) (S.ρ d0.root)).rvec = (argE Γa1 d0.root).rvec :=
    fun d0 hd0 => by
      obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d0 hd0
      have hrbr : Er.mode ≠ .rootb := by rcases hcan with h' | ⟨b, h', _⟩ <;> rw [h'] <;> simp
      rw [argE_canons h hEr (hroot d0 hd0), subE_liftE_rvec hrbr (fun h' => by have := hcan.ownSlot; rw [h'] at this; cases this)]
      unfold argE; rw [hEr]; rfl
  -- each root allows its effect, with views among its elements if its type holds them
  have hal : ∀ k ∈ thruKills op Γa1 Ex1.ty Ex1.path, Allowed S k.1 k.2.1 k.2.2 := by
    intro k hk
    obtain ⟨d0, hd0, rfl⟩ := mem_thruKills.mp hk
    obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d0 hd0
    have hae : argE Γa1 d0.root = Er := by unfold argE; rw [hEr]; rfl
    show Allowed S (op.effAt d0.kind (decide ((argE Γa1 d0.root).ty = Ex1.ty)) (argE Γa1 d0.root).rvec)
      (argE Γa1 d0.root).ty.holdsView d0.root
    rw [hae]
    have := allowed_canDo' hab1 hEr hcan
    rwa [elem_holdsView] at this
  -- the kills commute with the lift
  have hkills : thruKills (op.rename S.ρ) (S.canon Γa1) (S.liftE x Ex1).ty (S.liftE x Ex1).path =
      (thruKills op Γa1 Ex1.ty Ex1.path).map fun k => (k.1, k.2.1, S.ρ k.2.2) := by
    unfold thruKills
    rw [hmem, hty1]
    simp only [rds, List.map_map]
    apply List.map_congr_left
    intro d hd
    simp only [Function.comp, Dep.ren, Edit.effAt_rename, hargty d.root (hroot d hd), hrv d hd]
  have heqK : S.canon (killThruV op Ex1.ty Ex1.path Γa1) =
      killThruV (op.rename S.ρ) (S.liftE x Ex1).ty (S.liftE x Ex1).path (S.canon Γa1) := by
    unfold killThruV
    rw [canon_killHv h hab1 _ hal (fun k hk => by
      obtain ⟨d0, hd0, rfl⟩ := mem_thruKills.mp hk; exact hroot d0 hd0) (fun k hk => by
      obtain ⟨d0, hd0, rfl⟩ := mem_thruKills.mp hk
      obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d0 hd0
      exact hab1.notReg hEr (fun e => by have := hcan.ownSlot; rw [e] at this; cases this)), hkills]
  have hthru' : ThruOK (S.canon Γa1) S.Fc (op.rename S.ρ) (S.liftE x Ex1).ty (S.liftE x Ex1).path := by
    intro d hd
    rw [hmem] at hd
    obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
    have hnp0 := hroot d0 hd0
    obtain ⟨_, hy0, Er, hEr, hlr, hcan, hds, hsh, hho⟩ := hthru d0 hd0
    have hrbr : Er.mode ≠ .rootb := by rcases hcan with h' | ⟨b, h', _⟩ <;> rw [h'] <;> simp
    refine ⟨h.Fcout _, fun y hy => ?_, S.subE (S.liftE d0.root Er), by
      show S.canon Γa1 (S.ρ d0.root) = _; exact canon_some h hEr hnp0,
      by rw [subE_live, liftE_live]; exact hlr, ?_, ?_, ⟨by simpa [Dep.ren] using hsh, ?_⟩⟩
    · rw [Edit.stored_rename] at hy
      obtain ⟨y0, hy0', rfl⟩ := Option.map_eq_some_iff.mp hy
      exact fun e => hy0 y0 hy0' (h.inj _ _ e)
    · rw [subE_liftE_rvec hrbr (fun h' => by have := hcan.ownSlot; rw [h'] at this; cases this), subE_mode, subE_ty, liftE_mode _ hrbr, liftE_ty _ hrbr, hty1,
        Edit.effAt_rename]
      exact canDo_lift hcan
    · rw [subE_liftE_rvec hrbr (fun h' => by have := hcan.ownSlot; rw [h'] at this; cases this), subE_ty, liftE_ty _ hrbr, hty1, Edit.effAt_rename]
      exact DtorSafe.canon h (allowed_canDo_false hab1 hEr hcan) hds
    · rw [subE_liftE_rvec hrbr (fun h' => by have := hcan.ownSlot; rw [h'] at this; cases this), subE_ty, liftE_ty _ hrbr, hty1, Edit.effAt_rename]
      exact HeldOK.canon h (allowed_canDo_false hab1 hEr hcan) hho
  refine ⟨hmem, hthru', heqK, fun D2 hD2 d hd => ?_, hpfix⟩
  rw [hmem] at hd
  obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
  obtain ⟨hds, hdb, hrD⟩ := hV d0 hd0
  obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d0 hd0
  have hrbr : Er.mode ≠ .rootb := by rcases hcan with h' | ⟨b, h', _⟩ <;> rw [h'] <;> simp
  have hae : argE Γa1 d0.root = Er := by unfold argE; rw [hEr]; rfl
  have hae' : argE (S.canon Γa1) (S.ρ d0.root) = S.subE (S.liftE d0.root Er) :=
    argE_canons h hEr (hroot d0 hd0)
  rw [hae] at hds hdb
  refine ⟨?_, ?_, fun hr => ?_⟩
  · show DtorSafe (S.canon Γa1) ((op.rename S.ρ).effAt d0.kind
      (decide ((argE (S.canon Γa1) (S.ρ d0.root)).ty = (S.liftE x Ex1).ty))
      (argE (S.canon Γa1) (S.ρ d0.root)).rvec)
      (argE (S.canon Γa1) (S.ρ d0.root)).ty.holdsView (S.ρ d0.root)
    rw [hae', subE_liftE_rvec hrbr (fun h' => by have := hcan.ownSlot; rw [h'] at this; cases this), subE_ty, liftE_ty _ hrbr, hty1, Edit.effAt_rename]
    have := allowed_canDo' hab1 hEr hcan
    rw [elem_holdsView] at this
    exact DtorSafe.canon h this hds
  · show (argE (S.canon Γa1) (S.ρ d0.root)).dbind = false
    rw [hae', subE_dbind, liftE_dbind h, ite_eq_right hrbr]; exact hdb
  · obtain ⟨d1, hd1, he⟩ := List.mem_map.mp hr
    obtain ⟨d3, hd3, hd13⟩ := List.mem_flatMap.mp (hD2 hd1)
    rcases S.mem_subD hd13 with rfl | ⟨v, _, _, hv⟩
    · rcases List.mem_append.mp hd3 with h2 | h2
      · obtain ⟨d2, hd2, rfl⟩ := mem_rds.mp h2
        exact hrD (by rw [← h.inj _ _ he]; exact List.mem_map_of_mem hd2)
      · -- (Agora #909's own example: what the arguments hold is rooted at no
        -- callee binding, so at no root of the path)
        exact A_out h h2 d0.root (by simpa [Dep.ren] using he.symm)
    · -- (AGORA-937: what a region stands for is the frame's, at no root of the path)
      exact (S.σ_frameC h hv).1 d0.root (by simpa [Dep.ren] using he.symm)

/-- Agora #295, a view stored through a borrow in a callee's body, where the
    call places it: as `editB_ren`; what the stored value depends on in
    memory, where the call places it, is what it did in the callee, renamed
    (the call passes no views, `S.R = []`), so what the rule makes each root
    and the borrow hold is at most what the lifted context says (`PW`).
    AGORA-937: the change reads no region (`hvs`), and the lift is
    substituted. -/
theorem editBV_ren (h : S.OK) (hab : S.AbsOK Γa) {b : Bool} (hloc : b = true → S.Rf = []) {P : Prog} (hP : ProgOK P)
    {Fa : List Var} {Γa1 : Ctx} {x : Var} {op : Edit} {Ex Ex1 : Entry} {t : Ty} {D : List Dep}
    (hw : CtxWF Γa) (hn : NameWF Γa)
    (hx : Γa x = some Ex) (hmx : Ex.mode = .bor) (hl : Ex.live = true)
    (hty : Ex.ty = .vec t) (hhv : t.holdsView = true)
    (hfn : t.hasFn = false ∨ ∀ d ∈ D, d.kind.isName = true →
      d ∈ Ex1.held ∧ ∀ r ∈ roots (memDeps Ex1.path), (argE Γa1 r).ty.holdsView = true →
        d ∈ (argE Γa1 r).held) (hxF : x ∉ Fa)
    (harg : EditArg Γa Fa op t D Γa1) (hyx : ∀ y, op.stored = some y → y ≠ x) (hx1 : Γa1 x = some Ex1)
    (hl1 : Ex1.live = true) (hne : memDeps Ex1.path ≠ []) (hthru : ThruOK Γa1 Fa op Ex.ty Ex1.path)
    (hV : ThruV Γa1 op Ex.ty Ex1.path (memDeps D)) (hdf : op.drops = true → t.dtorFree = true)
    (hbf : b = false → Ex.fresh = true)
    (hbs : b = false → Ex.heldFresh = false ∨ ∀ y, op.stored = some y → FreshSrc Γa y ∧ HeldSrc Γa y)
    (hvs : ∀ v ∈ op.vars, S.isPi v = false) :
    StmtT P ξ (S.canon Γa) S.Fc ((Stmt.edit b x op).rename S.ρ)
      (S.canon (A2.setE (holdThru (memDeps D) Ex1.path (killThruV op Ex.ty Ex1.path Γa1)) x
        { Ex1 with held := Ex1.held ++ memDeps D })) ∧
    S.AbsOK (A2.setE (holdThru (memDeps D) Ex1.path (killThruV op Ex.ty Ex1.path Γa1)) x
        { Ex1 with held := Ex1.held ++ memDeps D }) := by
  -- the callee's own typing, for what its context guarantees
  have hT0 := StmtT.editBV (P := P) (ξ := ξ) hx hmx hl hty hhv hfn hxF harg hyx hx1 hl1 hne hthru hV hdf hbf hbs
  have hwo := hT0.wf hP hw
  have hno := hT0.names hP rfl hn
  have hab1 : S.AbsOK Γa1 := EditArg.absOK harg hab
  have hE1 : Ex1 = Ex := harg.at_ne hyx hx hx1 hl1
  subst hE1
  have hrb : Ex1.mode ≠ .rootb := by rw [hmx]; simp
  -- AGORA-937: the borrow is no region
  have hnpx : S.isPi x = false := hab.notPi hx (by rw [hmx]; simp)
  -- (Agora #916: a call that passes views places an `edit false`, whose borrow
  -- is fresh)
  have hloc' : S.Rf = [] ∨ (Ex1.fresh = true ∧ Ex1.ty ≠ .int) := by
    cases b with
    | true => exact Or.inl (hloc rfl)
    | false => exact Or.inr ⟨hbf rfl, by rw [hty]; simp⟩
  obtain ⟨hmem, hthru', heqK, hVg0, hpfix⟩ := editBV_ren_facts h hab1 hmx hthru hV hloc'
    (path_names_not_region hab hn hx hl hmx (by rw [hty]; simp))
  have hmemA : b = true → memDeps S.A = [] := by
    intro hbt
    unfold RSetup.A; rw [hloc hbt]
    simp only [compAll, List.flatMap_nil, List.nil_append]
    exact List.filter_eq_nil_iff.mpr fun d hd => by simp [h.N_name d hd]
  have hty1 : (S.liftE x Ex1).ty = Ex1.ty := liftE_ty x hrb
  have hroots : roots (memDeps (S.liftE x Ex1).path) = (roots (memDeps Ex1.path)).map S.ρ := by
    rw [hmem]; simp [roots, rds, List.map_map, Function.comp_def, Dep.ren]
  have hlx : (S.liftE x Ex1).held = rds S.ρ Ex1.held ++ S.heldA Ex1 := by
    rw [liftE_held hrb]; simp [hmx, Mode.ownSlot, ownHeld]
  -- what the change is handed, where the call places it, in memory: what it
  -- was, renamed, and what the arguments hold, substituted
  have hmapp : ∀ L M : List Dep, memDeps (L ++ M) = memDeps L ++ memDeps M := fun L M => by
    unfold memDeps; exact List.filter_append ..
  have hmrds : memDeps (rds S.ρ D) = rds S.ρ (memDeps D) := by
    unfold memDeps; simp only [rds, List.filter_map]; rfl
  have hmr : ∀ {D' : List Dep}, D' ⊆ (rds S.ρ D ++ S.A).flatMap S.subD →
      memDeps D' ⊆ (rds S.ρ (memDeps D) ++ memDeps S.A).flatMap S.subD := by
    intro D' hs
    rw [← hmrds, ← hmapp]
    have hs' : memDeps D' ⊆ memDeps ((rds S.ρ D ++ S.A).flatMap S.subD) := fun e he =>
      List.mem_filter.mpr ⟨hs (List.mem_filter.mp he).1, (List.mem_filter.mp he).2⟩
    exact hs'.trans (S.memDeps_flatMap_subD _)
  have hmw : ∀ {D' : List Dep}, D' ⊆ (rds S.ρ D ++ S.A).flatMap S.subD →
      memDeps D' ⊆ (rds S.ρ (memDeps D) ++ S.A).flatMap S.subD := fun hs =>
    (hmr hs).trans (S.flatMap_subD_mono
      (append_sub (List.Subset.refl _) (fun d hd => (List.mem_filter.mp hd).1)))
  -- (precisely what it was, of an `edit true`, placed by a call that passes
  -- no views)
  have hmemsub : ∀ {D' : List Dep}, b = true → D' ⊆ (rds S.ρ D ++ S.A).flatMap S.subD →
      memDeps D' ⊆ (rds S.ρ (memDeps D)).flatMap S.subD := by
    intro D' hbt hs
    have := hmr hs
    rwa [hmemA hbt, List.append_nil] at this
  -- (Agora #916: or, of an `edit false`, the stored value is the frame's own,
  -- in path and in what it holds, and the lift adds it no memory of the
  -- arguments: `pushArg_ren_helds`)
  have hmemsub' : ∀ {y : Var} {Ey : Entry} {Γb : Ctx} {D' : List Dep} {Γc : Ctx},
      (b = true ∨ ∀ y, op.stored = some y → FreshSrc Γa y ∧ HeldSrc Γa y) →
      op.stored = some y → Γa y = some Ey → S.isPi y = false → Ey.ty = t → PushArg Γa Fa y Ey t D Γb →
      PushArg (S.canon Γa) S.Fc (S.ρ y) (S.subE (S.liftE y Ey)) t D' Γc →
      D' ⊆ (rds S.ρ D ++ S.A).flatMap S.subD → memDeps D' ⊆ (rds S.ρ (memDeps D)).flatMap S.subD := by
    intro y Ey Γb D' Γc hpre hst hy hnpy htyy hpa hpa' hs
    rcases hpre with hbt | hp
    · exact hmemsub hbt hs
    · obtain ⟨hfs, hhs⟩ := hp y hst
      exact pushArg_ren_helds h hab hy hnpy
        (by rw [htyy]; intro e; rw [e] at hhv; simp [Ty.holdsView] at hhv) hpa hpa' hfs hhs
  have hpre : b = true ∨ Ex1.heldFresh = true → b = true ∨ ∀ y, op.stored = some y → FreshSrc Γa y ∧ HeldSrc Γa y := by
    intro hc
    cases b with
    | true => exact Or.inl rfl
    | false =>
      rcases hc with hc | hc
      · cases hc
      · exact Or.inr ((hbs rfl).resolve_left (by rw [hc]; simp))
  obtain ⟨D', harg', hDw, hDp, hsD'⟩ : ∃ D', EditArg (S.canon Γa) S.Fc (op.rename S.ρ) t D' (S.canon Γa1) ∧
      memDeps D' ⊆ (rds S.ρ (memDeps D) ++ S.A).flatMap S.subD ∧
      (b = true ∨ Ex1.heldFresh = true → memDeps D' ⊆ (rds S.ρ (memDeps D)).flatMap S.subD) ∧
      D' ⊆ (rds S.ρ D ++ S.A).flatMap S.subD := by
    cases harg with
    | @push y _ _ _ _ hy hly htyy hpa =>
      have hnpy : S.isPi y = false := hvs y (by simp [Edit.vars])
      obtain ⟨D', hpa', hs, _⟩ := pushArg_rens h hab hy hnpy hpa
      exact ⟨D', EditArg.push (canon_some h hy hnpy) (by rw [subE_live, liftE_live]; exact hly)
        (by rw [subE_ty, liftE_ty' h hab hy]; exact htyy) hpa', hmw hs,
        fun hc => hmemsub' (hpre hc) rfl hy hnpy htyy hpa hpa' hs, hs⟩
    | trunc hie =>
      exact ⟨[], EditArg.trunc (exprT_ren h hab hie (fun v hv => hvs v (by simpa [Edit.vars] using hv))),
        (fun _ h => by cases h), (fun _ _ h => by cases h), (fun _ h => by cases h)⟩
    | @set _ y _ _ _ _ hie hy hly htyy hpa =>
      have hnpy : S.isPi y = false := hvs y (by simp [Edit.vars])
      obtain ⟨D', hpa', hs, _⟩ := pushArg_rens h hab hy hnpy hpa
      exact ⟨D', EditArg.set (exprT_ren h hab hie (fun v hv => hvs v (by simp [Edit.vars, hv])))
        (canon_some h hy hnpy) (by rw [subE_live, liftE_live]; exact hly)
        (by rw [subE_ty, liftE_ty' h hab hy]; exact htyy) hpa', hmw hs,
        fun hc => hmemsub' (hpre hc) rfl hy hnpy htyy hpa hpa' hs, hs⟩
  -- AGORA-901: what the stored value captures by name, where the call places
  -- it: its own names, renamed, which the borrow and its view-holding owners
  -- held, renamed; or what the call's arguments hold by name, which the lift
  -- adds to the borrow and to every owner whose type holds views (AGORA-937:
  -- the substitution keeps the names it gave, `subD_idem`)
  have hfn' : t.hasFn = false ∨ ∀ d ∈ D', d.kind.isName = true →
      d ∈ (S.subE (S.liftE x Ex1)).held ∧ ∀ r ∈ roots (memDeps (S.subE (S.liftE x Ex1)).path),
        (argE (S.canon Γa1) r).ty.holdsView = true → d ∈ (argE (S.canon Γa1) r).held := by
    rcases hfn with hf | hf
    · exact Or.inl hf
    cases htf : t.hasFn
    · exact Or.inl rfl
    -- (AGORA-909: the borrow's type holds a closure, so the lift keeps the names)
    have hxfn : Ex1.ty.hasFn = true := by
      rw [hty]; simpa [Ty.hasFn] using htf
    refine Or.inr fun d hd hnm => ?_
    -- (what the substitution gave, it keeps, `subD_idem`)
    have hdk : S.subD d = [d] := by
      obtain ⟨d1, _, hd1⟩ := List.mem_flatMap.mp (hsD' hd); exact S.subD_idem h hd1
    have hkeep : ∀ {X : List Dep}, d ∈ X → d ∈ X.flatMap S.subD := fun hX =>
      List.mem_flatMap.mpr ⟨d, hX, by rw [hdk]; exact List.mem_singleton_self d⟩
    have hlo : ∀ r, r ∈ roots (memDeps Ex1.path) → ∃ Er, Γa1 r = some Er ∧ argE (S.canon Γa1) (S.ρ r) =
        S.subE (S.liftE r Er) ∧ (Er.ty.holdsView = true → (S.liftE r Er).held = rds S.ρ Er.held ++ S.A) ∧
        (S.liftE r Er).ty = Er.ty := by
      intro r hr
      obtain ⟨Er, hEr, hos, _⟩ := hthru.root hr
      have hrbr : Er.mode ≠ .rootb := fun h' => by rw [h'] at hos; cases hos
      have hnpr : S.isPi r = false := hab1.notPi hEr (fun h' => by rw [h'] at hos; cases hos)
      exact ⟨Er, hEr, argE_canons h hEr hnpr,
        fun hv => by rw [liftE_held hrbr, S.heldA_own hos]; simp [hos, ownHeld, hv], liftE_ty _ hrbr⟩
    rw [hpfix, hroots, subE_held]
    rcases List.mem_append.mp (S.mem_flatMap_subD_name h (hsD' hd) hnm) with h1 | h1
    · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
      obtain ⟨hx0, hr0⟩ := hf d0 hd0 hnm
      refine ⟨hkeep (by rw [hlx]; exact List.mem_append_left _ (mem_rds.mpr ⟨d0, hx0, rfl⟩)),
        fun r' hr' hv' => ?_⟩
      obtain ⟨r, hr, rfl⟩ := List.mem_map.mp hr'
      obtain ⟨Er, hEr, hae, hheld, hty'⟩ := hlo r hr
      have hae0 : argE Γa1 r = Er := by unfold argE; rw [hEr]; rfl
      rw [hae, subE_ty, hty'] at hv'
      rw [hae, subE_held, hheld hv']
      exact hkeep (List.mem_append_left _
        (mem_rds.mpr ⟨d0, by rw [← hae0]; exact hr0 r hr (by rw [hae0]; exact hv'), rfl⟩))
    · refine ⟨hkeep (by rw [hlx]; exact List.mem_append_right _ (RSetup.name_mem_heldA h h1 hnm hxfn)),
        fun r' hr' hv' => ?_⟩
      obtain ⟨r, hr, rfl⟩ := List.mem_map.mp hr'
      obtain ⟨Er, hEr, hae, hheld, hty'⟩ := hlo r hr
      rw [hae, subE_ty, hty'] at hv'
      rw [hae, subE_held, hheld hv']
      exact hkeep (List.mem_append_right _ h1)
  have hyx' : ∀ y, (op.rename S.ρ).stored = some y → y ≠ S.ρ x := by
    intro y hy
    rw [Edit.stored_rename] at hy
    obtain ⟨y0, hy0, rfl⟩ := Option.map_eq_some_iff.mp hy
    exact fun e => hyx y0 hy0 (h.inj _ _ e)
  have hV' := hVg0 (memDeps D') hDw
  have hT := StmtT.editBV (P := P) (ξ := ξ) (x := S.ρ x) (Ex := S.subE (S.liftE x Ex1))
    (Ex1 := S.subE (S.liftE x Ex1))
    (canon_some h hx hnpx) (by rw [subE_mode, liftE_mode x hrb, hmx]; rfl)
    (by rw [subE_live, liftE_live]; exact hl)
    (by rw [subE_ty, hty1]; exact hty) hhv hfn' (h.Fcout x) harg' hyx' (canon_some h hx1 hnpx)
    (by rw [subE_live, liftE_live]; exact hl1) (by rw [hpfix, hmem]; simpa [rds] using hne)
    (by rw [subE_ty, hpfix]; exact hthru') (by rw [subE_ty, hpfix]; exact hV')
    (by rw [Edit.drops_rename]; exact hdf)
    (fun hb => by rw [subE_fresh, S.liftE_fresh_of hrb]; exact hbf hb)
    (fun hb => by
      -- Agora #916: a borrow that is not held-fresh stays one, and what is
      -- stored stays the frame's own where the call places it
      rcases hbs hb with hf | hp
      · exact Or.inl (by rw [subE_heldFresh, liftE_heldFresh]; simp [hrb, hf])
      · refine Or.inr fun y' hy' => ?_
        rw [Edit.stored_rename] at hy'
        obtain ⟨y0, hy0, rfl⟩ := Option.map_eq_some_iff.mp hy'
        obtain ⟨hfs, hhs⟩ := hp y0 hy0
        obtain ⟨Ey0, hEy0, _⟩ := id hfs
        exact ⟨freshSrc_lift h hab hEy0 hfs, heldSrc_lift h hab hEy0 hhs⟩)
  -- the roots are owners or `inout` parameters made by no `letd`
  have hrs : ∀ v ∈ roots (memDeps Ex1.path), ∀ E, killThruV op Ex1.ty Ex1.path Γa1 v = some E →
      E.mode ≠ .rootb ∧ E.dbind = false ∧ E.mode.ownSlot = true := by
    intro v hv E hE
    obtain ⟨E0, h0, hm0, _, _, _, _, hb0, _⟩ := killHv_same hE
    obtain ⟨Er, hEr, hos, _⟩ := hthru.root hv
    rw [hEr] at h0; cases h0
    refine ⟨fun h' => ?_, by rw [hb0]; exact hV.dbind hv hEr, by rw [hm0]; exact hos⟩
    rw [hm0] at h'; rw [h'] at hos; cases hos
  have habo : S.AbsOK (A2.setE (holdThru (memDeps D) Ex1.path (killThruV op Ex1.ty Ex1.path Γa1)) x
      { Ex1 with held := Ex1.held ++ memDeps D }) :=
    ((hab1.killHv _).holdOn fun v hv E hE => (hrs v hv E hE).1).setE' hab1 hx1 rfl rfl hrb
      (fun hf => absurd hf (by simp [Entry.fixed, hmx]))
  refine ⟨?_, habo⟩
  have hwc := canon_wf_sub h habo hwo hno
  have hnc := canon_names_sub h habo hno
  rw [canon_setEs h _ hnpx] at hwc hnc ⊢
  refine StmtT.weakenOut (canon_wf_sub h hab hw hn) (canon_names_sub h hab hn) hT
    (Or.inr ⟨PW.setE ?_ ?_, hwc, hnc⟩)
  · show PW (A2.holdOn (roots (memDeps (S.subE (S.liftE x Ex1)).path)) (memDeps D')
      (killThruV (op.rename S.ρ) (S.subE (S.liftE x Ex1)).ty (S.subE (S.liftE x Ex1)).path (S.canon Γa1)))
      (S.canon (A2.holdOn (roots (memDeps Ex1.path)) (memDeps D) (killThruV op Ex1.ty Ex1.path Γa1)))
    rw [subE_ty, hpfix, hroots, ← heqK]
    exact PW.holdOn_canons h hDw hrs
  · -- the borrow holds what was stored, renamed and substituted, or less
    have hl' : S.liftE x Ex1 = ⟨Ex1.ty, liftMode Ex1.mode, Ex1.live,
        rds S.ρ Ex1.path ++ (if Ex1.fresh && Ex1.ty != .int then [] else S.A),
        rds S.ρ Ex1.held ++ S.heldA Ex1, Ex1.dtor, Ex1.dbind, Ex1.fresh, Ex1.heldFresh⟩ := by
      simp [RSetup.liftE, hmx, Mode.ownSlot, ownHeld, RSetup.heldA]
    have hl'' : S.liftE x { Ex1 with held := Ex1.held ++ memDeps D } = ⟨Ex1.ty, liftMode Ex1.mode,
        Ex1.live, rds S.ρ Ex1.path ++ (if Ex1.fresh && Ex1.ty != .int then [] else S.A),
        rds S.ρ (Ex1.held ++ memDeps D) ++ S.heldA Ex1, Ex1.dtor, Ex1.dbind, Ex1.fresh, Ex1.heldFresh⟩ := by
      simp [RSetup.liftE, hmx, Mode.ownSlot, ownHeld, RSetup.heldA]
    -- (Agora #909's own example: a borrow that is not held-fresh is lifted
    -- with all the arguments hold)
    have hDh : memDeps D' ⊆ (rds S.ρ (memDeps D) ++ S.heldA Ex1).flatMap S.subD := by
      by_cases hhf : Ex1.heldFresh = true
      · exact (hDp (Or.inr hhf)).trans (S.flatMap_subD_mono (fun e he => List.mem_append_left _ he))
      · rw [S.heldA_of (by simpa using hhf)]; exact hDw
    have hsub1 : rds S.ρ Ex1.held ++ S.heldA Ex1 ⊆ rds S.ρ (Ex1.held ++ memDeps D) ++ S.heldA Ex1 :=
      append_sub (by simp only [rds, List.map_append]; exact List.subset_append_left _ _) (List.Subset.refl _)
    have hsub2 : rds S.ρ (memDeps D) ++ S.heldA Ex1 ⊆ rds S.ρ (Ex1.held ++ memDeps D) ++ S.heldA Ex1 :=
      append_sub (by simp only [rds, List.map_append]; exact List.subset_append_right _ _) (List.Subset.refl _)
    rw [hl', hl'']
    refine ew_sub_held (X := S.subE ⟨Ex1.ty, liftMode Ex1.mode,
        Ex1.live, rds S.ρ Ex1.path ++ (if Ex1.fresh && Ex1.ty != .int then [] else S.A),
        rds S.ρ (Ex1.held ++ memDeps D) ++ S.heldA Ex1, Ex1.dtor, Ex1.dbind, Ex1.fresh, Ex1.heldFresh⟩) ?_
      (by simp [hmx, liftMode, Mode.ownSlot]) (by simp [hmx, liftMode])
    show (rds S.ρ Ex1.held ++ S.heldA Ex1).flatMap S.subD ++ memDeps D' ⊆
      (rds S.ρ (Ex1.held ++ memDeps D) ++ S.heldA Ex1).flatMap S.subD
    exact List.append_subset.mpr ⟨S.flatMap_subD_mono hsub1, hDh.trans (S.flatMap_subD_mono hsub2)⟩

/-- Agora #632: the gate on a payload taken out of an enum of a destructor
    type reads the enum's type, which a call's renaming keeps. -/
theorem TakeOK.canon (h : S.OK) {P : Prog} {Γ : Ctx} (hab : S.AbsOK Γ) {r : Rhs} (ht : TakeOK P Γ r) :
    TakeOK P (S.canon Γ) (r.rename S.ρ) := by
  intro y Ey g u hry hy hgy
  have key : ∀ y0, S.ρ y0 = y → (r = .takel y0 ∨ r = .taker y0) → EnumGlueOK P g u := by
    intro y0 hy0 hr0
    rw [← hy0, canon_ρ_sub h] at hy
    split at hy
    · cases hy
    cases h0 : Γ y0 with
    | none => rw [h0] at hy; cases hy
    | some E0 =>
      rw [h0] at hy; simp only [Option.map_some, Option.some.injEq, Function.comp] at hy
      refine ht y0 E0 g u hr0 h0 ?_
      rw [← liftE_ty' h hab h0, ← subE_ty, hy]; exact hgy
  cases r <;> simp [Rhs.rename] at hry
  · exact key _ hry (Or.inl rfl)
  · exact key _ hry (Or.inr rfl)

/-! ### Agora #871: the exit targets of a renamed body -/

/-- The callee's exit targets, at the contexts its own are renamed to. -/
def liftX (ξ : Exits) : Exits := fun n Γc =>
  ∃ Γa, Γc = S.canon Γa ∧ S.AbsOK Γa ∧ CtxWF Γa ∧ NameWF Γa ∧ ξ n Γa

theorem liftX_none {n : Nat} {Γc : Ctx} (hx : S.liftX .none n Γc) : False := by
  obtain ⟨_, _, _, _, _, h⟩ := hx; exact h

theorem liftX_up (h : S.OK) {ξ : Exits} {n : Nat} {Γa : Ctx} (hab : S.AbsOK Γa) (hw : CtxWF Γa)
    (hn : NameWF Γa) (hx : ξ.up n Γa) : (S.liftX ξ).up n (S.canon Γa) := by
  rcases hx with hx | ⟨Γ0, hw0, hx⟩
  · exact Or.inl ⟨Γa, rfl, hab, hw, hn, hx⟩
  · have hab0 := hab.weaker hw0
    exact Or.inr ⟨S.canon Γ0, canon_weaker_sub h hab0 hw0, Γ0, rfl, hab0, hw0.wf, hw0.names, hx⟩

theorem liftX_under (h : S.OK) {ξ : Exits} {x : Var} (hbx : S.bnd x = none)
    (hnp : S.isReg x = false) :
    ∀ n Γc, S.liftX (ξ.under x) n Γc → (S.liftX ξ).under (S.ρ x) n Γc := by
  rintro n _ ⟨Γa, rfl, hab, hw, hn, he, hx⟩
  refine ⟨EndOK.lift h hab hbx he, ?_⟩
  rw [← canon_exitScopes h hab (Or.inl hbx) hnp]
  have hwk := (Weaker.refl hw hn).exitScope x he.2.2
  exact ⟨A2.exitScope x Γa, rfl, hab.exitScope hbx hnp, hwk.2.1, hwk.2.2, hx⟩

theorem liftX_underD (h : S.OK) {ξ : Exits} {x : Var} {Γ0 : Ctx} (_ : S.AbsOK Γ0) (hbx : S.bnd x = none)
    (hnp : S.isReg x = false) :
    ∀ n Γc, S.liftX (ξ.underD x) n Γc → (S.liftX ξ).underD (S.ρ x) n Γc := by
  rintro n _ ⟨Γa, rfl, hab, hw, hn, he, hd, hx⟩
  refine ⟨EndOK.lift h hab hbx he, fun E hE => ?_, ?_⟩
  · rw [canon_ρs h _ (hab.notPi_of_notReg hnp)] at hE
    obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hE
    obtain ⟨hrb, hdv⟩ := hd E0 h0
    simp only [Function.comp_apply, subE_mode, subE_dbind, subE_ty]
    refine ⟨by rw [liftE_mode x hrb]; cases hm : E0.mode <;> simp_all [liftMode], fun hv => ?_⟩
    rw [liftE_dbind h]; simp only [hrb, ↓reduceIte]
    exact hdv (by rwa [liftE_ty' h hab h0] at hv)
  · rw [← canon_exitScopes h hab (Or.inl hbx) hnp]
    have hwk := (Weaker.refl hw hn).exitScope x he.2.2
    exact ⟨A2.exitScope x Γa, rfl, hab.exitScope hbx hnp, hwk.2.1, hwk.2.2, hx⟩

theorem liftX_blk (h : S.OK) {ξ : Exits} {Δa : Ctx} (habΔ : S.AbsOK Δa) (hwΔ : CtxWF Δa) :
    ∀ n Γc, S.liftX (ξ.blk Δa) n Γc → (S.liftX ξ).blk (S.canon Δa) n Γc := by
  rintro (_ | n) _ ⟨Γa, rfl, hab, hw, hn, hx⟩
  · rcases hx with rfl | hx
    · exact Or.inl rfl
    · exact Or.inr (canon_weaker_sub h habΔ hx)
  · exact ⟨Γa, rfl, hab, hw, hn, hx⟩

/-- AGORA-889: what moves out through a borrow, where a call places it: the
    owner `compE` makes of the lifted borrow holds no more than the lifted
    owner does (an integer's lift only adds what the call's arguments hold by
    name). -/
theorem compE_liftE_weaker {x y : Var} {Ex : Entry} {t : Ty} (hhv : t.holdsView = false) :
    EntryWeaker (compE (S.liftE x Ex) t) (S.liftE y (compE Ex t)) := by
  by_cases hint : t = .int
  · subst hint
    refine ⟨rfl, rfl, fun hf => ?_, fun _ => ⟨rfl, fun _ d hd => by simp [compE, intE] at hd,
      fun d hd => by simp [compE, intE] at hd⟩,
      fun h => by simp [compE, intE] at h, rfl, fun h => by simp [liftE, compE, intE] at h,
      fun h => by simp [compE, intE] at h,
      fun _ _ _ hfr => (by fresh_ew),
      fun _ _ hhf => by heldfresh_ew⟩
    simp [Entry.fixed, compE, intE] at hf
  · have heq : S.liftE y (compE Ex t) = compE (S.liftE x Ex) t := by
      cases t <;> simp_all [liftE, compE, liftMode, ownHeld, rds, Mode.ownSlot, Ty.holdsView]
    rw [heq]; exact EntryWeaker.refl _

/-- AGORA-897: ... and for an element type that holds views, the owner
    (or the slice's borrow) `compE` makes of the lifted borrow is the lifted
    one: both hold what the borrow holds, renamed, and what the call's
    arguments hold. -/
theorem compE_liftE_weakerV {x y : Var} {Ex : Entry} {t : Ty} (hmx : Ex.mode = .bor)
    (hhv : t.holdsView = true) : EntryWeaker (compE (S.liftE x Ex) t) (S.liftE y (compE Ex t)) := by
  have hrb : Ex.mode ≠ .rootb := by rw [hmx]; simp
  -- (Agora #916: a held-fresh borrow's lift holds less, so the field taken
  -- out of it, as the rule makes it, holds at most what the lift says)
  have hH : (S.liftE x Ex).held ⊆ rds S.ρ Ex.held ++ S.A := by
    rw [liftE_held hrb]; simp only [hmx, Mode.ownSlot, ownHeld, Bool.false_and, Bool.false_eq_true, ↓reduceIte]
    exact append_sub (List.Subset.refl _) (S.heldA_sub _)
  by_cases hs : ∃ s, t = .slice s
  · obtain ⟨s, rfl⟩ := hs
    have hR : S.liftE y (compE Ex (.slice s)) =
        ⟨.slice s, .bor, true, rds S.ρ Ex.held ++ S.A, rds S.ρ Ex.held ++ S.A, false, false, false, false⟩ := by
      simp [compE, liftE, heldA, liftMode, Mode.ownSlot, ownHeld, Ty.holdsView]
    rw [hR]; simp only [compE]
    exact EntryWeaker.mk' rfl rfl (by simp [Entry.fixed]) rfl (fun _ => hH) hH (by simp) rfl (by simp) (by simp)
      (by intro _ _ _ hfr; simp at hfr) (by intro _ _ hhf; simp at hhf)
  · have hc : ∀ E : Entry, compE E t = ⟨t, .own, true, [], ownHeld true t E.held, false, false, false, false⟩ := by
      intro E; cases t <;> first | (simp [Ty.holdsView] at hhv; done) | (exact absurd ⟨_, rfl⟩ hs) | rfl
    have hoh : ∀ X : List Dep, ownHeld true t X = X := fun X => by simp [ownHeld, hhv]
    have hR : S.liftE y ⟨t, .own, true, [], ownHeld true t Ex.held, false, false, false, false⟩ =
        ⟨t, .own, true, [], rds S.ρ Ex.held ++ S.A, false, false, false, false⟩ := by
      simp [liftE, heldA, liftMode, Mode.ownSlot, hoh, rds]
    rw [hc, hc, hR]
    exact EntryWeaker.mk' rfl rfl (by simp [Entry.fixed]) rfl (fun h => by simp [Mode.ownSlot] at h)
      (by rw [hoh]; exact hH) (by simp) rfl (by simp) (by simp)
      (by intro _ _ hb; simp at hb) (by intro _ hb; simp at hb)

/-- AGORA-937 (3d): what the rename asks of a through-changing statement's
    call: that it passes no views, or that it is ready for a change through
    its regions and the statement calls no through-changing function. -/
def ThruOrReady (S : RSetup) (P : Prog) (s : Stmt) : Prop :=
  S.R = [] ∨ (S.ThruReady ∧ ∀ g ∈ s.calls, ¬ ThruFn P g)

theorem ThruOrReady.sub {P : Prog} {s s' : Stmt} (h : S.ThruOrReady P s) (hc : ∀ g ∈ s'.calls, g ∈ s.calls) :
    S.ThruOrReady P s' :=
  h.imp id fun ⟨ht, hn⟩ => ⟨ht, fun g hg => hn g (hc g hg)⟩

/-- ... so where it calls a through-changing function, the outer call (the
    setting) passes no views: `S.R = []` of the setting, not of the inner call. -/
theorem ThruOrReady.call {P : Prog} {s : Stmt} (h : S.ThruOrReady P s) {f : Nat} (hf : f ∈ s.calls)
    (ht : ThruFn P f) : S.R = [] :=
  h.resolve_right fun ⟨_, hn⟩ => hn f hf ht

/-- ... and the call freezes nothing. -/
theorem ThruOrReady.Rf (h0 : S.OK) {P : Prog} {s : Stmt} (h : S.ThruOrReady P s) : S.Rf = [] :=
  h.elim (S.Rf_nil h0) fun ⟨ht, _⟩ => ht.1

/-- The renaming lemma: a callee's source statement, typed in its own
    contexts, is typed where the call places it, in the caller's view of
    those contexts. A statement that may change elements through a borrow
    (`s.Thru P`) is placed by a call that either passed no views
    (`S.R = []`, from `CallT`'s guard, Agora #295), or (AGORA-937 3d) is
    ready for a change through its regions (`S.ThruReady`) while the
    statement calls no through-changing function (`ThruOrReady`). -/
theorem StmtT.ren (h : S.OK) {P : Prog} (hP : ProgOK P) {Γa : Ctx} {Fa : List Var} {s : Stmt}
    {Δa : Ctx} (hd : StmtT P ξ Γa Fa s Δa) : s.src = true → S.AbsOK Γa → CtxWF Γa → NameWF Γa →
    FreshOK Γa → (s.Thru P → S.ThruOrReady P s) → (∀ v ∈ s.vars, S.isReg v = false) →
    StmtT P (S.liftX ξ) (S.canon Γa) S.Fc (s.rename S.ρ) (S.canon Δa) ∧ S.AbsOK Δa := by
  induction hd with
  | skip => exact fun _ hab _ _ _ _ _ => ⟨StmtT.skip, hab⟩
  | @seq _ Γ Γ1 Δ F a b hb ta tb iha ihb =>
    intro hs hab hw hn hfo hT hvs
    simp only [Stmt.src, Bool.and_eq_true] at hs
    obtain ⟨t1, ab1⟩ := iha hs.1 hab hw hn hfo (fun ht => (hT ht.seq_l).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    obtain ⟨t2, ab2⟩ := ihb hs.2 ab1 (ta.wf hP hw) (ta.names hP hs.1 hn) (ta.freshOK hP hs.1 hfo) (fun ht => (hT ht.seq_r).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    exact ⟨StmtT.seq (by rw [src_rename]; exact hb) t1 t2, ab2⟩
  | @letv _ Γ Γ1 Δ F x r k E hks hx hxF hr hk hpe hnd ih =>
    intro _ hab hw hn hfo hT hvs
    obtain ⟨E', hr', hE'⟩ := RhsT.ren h hab hfo hr (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, hv]))))
    obtain ⟨hn1, hEn, _⟩ := hr.names hn
    have hab1 := RhsT.absOK (S := S) hr hab
    obtain ⟨hmo, _⟩ := RhsT.out hr
    obtain ⟨hw1, hdom, _, hEr⟩ := hr.wf hw
    have hx1 : Γ1 x = none := by have := hdom x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    have hwx := hw1.add hx1 hEr (fun hd => absurd hd (by simp [hr.dtor_false.2]))
      (fun ha => absurd ha (by simp [hr.dtor_false.1])) (fun hd => absurd hd (by simp [hr.dtor_false.2]))
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) hEn
    have habx := hab.add hab1 hx hmo
    obtain ⟨tk, abk⟩ := ih hks habx hwx hnx (by obtain ⟨h1, hE, _⟩ := hr.freshOK hfo; exact h1.bind hx1 hE)
      (fun ht => (hT ht.letv).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    have hnpx := hab.notPiFresh hx
    have hnrx := hab.notRegFresh hx
    have tk := tk.mono (S.liftX_under h (hab.fresh hx) hnrx)
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx hnrx⟩
    rw [canon_exitScopes h abk (Or.inl hbx) (hab.notRegFresh hx)]
    have hwc := canon_wf_sub h habx hwx hnx
    have hnc := canon_names_sub h habx hnx
    rw [canon_setEs h _ hnpx] at hwc hnc tk
    exact StmtT.letv (by rw [src_rename]; exact hks) (by rw [canon_ρs h _ hnpx, hx]; rfl) (h.Fcout x) hr'
      (StmtT.weakenIn ⟨PW.setE (PW.refl _) (hE' x), hwc, hnc⟩ tk)
      (EndOK.lift h abk hbx hpe) (fun hmo' => by
        have hl := (hE' x).1
        have hm := (hE' x).mode
        rcases hmo with hmo | hmo <;> simp only [subE_ty, subE_mode, liftE, hmo, reduceCtorEq, ite_false, liftMode] at hl hm
        · first | (rw [← hl]; exact hnd hmo) | (rw [hl]; exact hnd hmo)
        · first | (rw [← hm] at hmo'; cases hmo') | (rw [hm] at hmo'; cases hmo'))
  | @withLock _ Γ Δ F a x k Ea t hks hx hxF ha hla hta hk hpe hroot hav hxl hna ih =>
    intro _ hab hw hn hfo hT hvs
    have hca : S.canon Γ (S.ρ a) = some (S.subE (S.liftE a Ea)) :=
      canon_some h ha ((hab.notPi_of_notReg (hvs a (by simp [Stmt.vars]))))
    have hnpx := hab.notPiFresh hx
    have hnrx := hab.notRegFresh hx
    have hmo : (lockE t).mode = .own ∨ (lockE t).mode = .bor := by
      unfold lockE; split <;> simp [intE]
    have hwx := hw.add hx (E := lockE t) (fun _ _ r hr => by simp [roots] at hr)
      (fun hd => absurd hd (by simp)) (fun ha => absurd ha (by simp)) (fun hd => absurd hd (by simp))
    have hnx := NameWF.setE hn (E := lockE t) (fun Ex h => by rw [hx] at h; cases h)
      (fun Ex h => by rw [hx] at h; cases h) (fun _ _ => by unfold NameOK; rw [lockE_vdeps]; exact DepsNamed.nil _)
    have habx := hab.add hab hx hmo
    obtain ⟨tk, abk⟩ := ih hks habx hwx hnx (hfo.bind hx (FreshE.of_fresh (lockE_fresh t)))
      (fun ht => (hT ht.withLock).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    have tk := tk.mono (ξ' := .none) (fun _ _ h' => (S.liftX_none h').elim)
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx hnrx⟩
    rw [canon_exitScopes h abk (Or.inl hbx) (hab.notRegFresh hx)]
    have hwc := canon_wf_sub h habx hwx hnx
    have hnc := canon_names_sub h habx hnx
    rw [canon_setEs h _ hnpx] at hwc hnc tk
    exact StmtT.withLock (by rw [src_rename]; exact hks) (by rw [canon_ρs h _ hnpx, hx]; rfl) (h.Fcout x) hca
      (by rw [subE_live, liftE_live]; exact hla) (Entry.lockOf.lift (liftE_ty' h hab ha) hta)
      (StmtT.weakenIn ⟨PW.setE (PW.refl _) (by simpa only [subE_lockE] using S.subE_weaker (lockE_lift x t)),
        hwc, hnc⟩ tk)
      (EndOK.lift h abk hbx hpe)
      (by
        rw [subE_mode]; unfold RSetup.liftE; split
        · simp [h.pe_rb, Mode.isRoot]
        · cases hm : Ea.mode <;> simp_all [liftMode, Mode.isRoot])
      (by
        rw [Stmt.vars_rename]; intro hm
        obtain ⟨w, hw, he⟩ := List.mem_map.mp hm
        exact hav (h.inj _ _ he ▸ hw))
      (by
        obtain ⟨E, hE, hl⟩ := hxl
        exact ⟨S.subE (S.liftE x E), by rw [canon_ρs h _ hnpx, hE]; rfl, by rw [subE_live, liftE_live]; exact hl⟩)
      (fun hd => not_mem_assigns_rename h.inj (hna hd))
  | @letd _ Γ Γ1 Δ F x f r k E t H τ hks hx hxF hr hown hty hstr hview hdtor hH hk hpe hna ih =>
    intro _ hab hw hn hfo hT hvs
    obtain ⟨E', hr', hE'⟩ := RhsT.ren h hab hfo hr (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, hv]))))
    obtain ⟨hn1, hEn, _⟩ := hr.names hn
    have hab1 := RhsT.absOK (S := S) hr hab
    obtain ⟨hmo, hlive⟩ := RhsT.out hr
    obtain ⟨hw1, hdom, _, hEr⟩ := hr.wf hw
    have hx1 : Γ1 x = none := by have := hdom x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    -- the armed binding, as `letd` records it
    have hos : E.mode.ownSlot = true := by rw [hown]; rfl
    have hv1 : (Entry.arm { E with ty := τ, held := H }).vdeps = H := by simp [Entry.vdeps, Entry.arm, hos]
    -- (A2-drop.3a: a struct or an enum, or its destructor type: no integer)
    have hne : E.ty ≠ .int := hty.ne_int hstr
    have hov : τ.holdsView = E.ty.holdsView := by
      rcases hty with ⟨rfl, h' | ⟨g, h'⟩⟩ | ⟨_, _, h'⟩
      · rw [h']; rfl
      · rw [h']; rfl
      · rw [h']
    have hdv : τ.dtorViews = τ.holdsView := hty.scopeD.dtorViews
    have hroot := hH.root hown (hEr hlive (Or.inl hne))
    have hwx := hw1.add hx1 (E := Entry.arm { E with ty := τ, held := H })
      (fun _ _ r hr0 => by
        rw [hv1] at hr0; obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr0; exact hroot d hd)
      (fun _ _ _ d hd _ => by rw [hv1] at hd; exact hroot d hd) (fun h => h)
      (fun h => by simp only [Entry.arm, Ty.dtorViews, Bool.and_eq_true] at h; exact h.2)
    have hnx := NameWF.setE hn1 (E := Entry.arm { E with ty := τ, held := H }) (fun Ex h => by rw [hx1] at h; cases h)
      (fun Ex h => by rw [hx1] at h; cases h) (fun hl _ => (hEn hl (Or.inl hne)).widen hown hH)
    have habx := hab.add hab1 hx (E := Entry.arm { E with ty := τ, held := H }) hmo
    obtain ⟨tk, abk⟩ := ih hks habx hwx hnx (by
      obtain ⟨h1, _, _⟩ := hr.freshOK hfo
      exact h1.bind hx1 (fun _ _ hb _ => by simp [Entry.arm, hown] at hb)) (fun ht => (hT ht.letd).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    have hnpx := hab.notPiFresh hx
    have hnrx := hab.notRegFresh hx
    have tk := tk.mono (S.liftX_underD h hab1 (hab.fresh hx) hnrx)
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx hnrx⟩
    rw [canon_exitScopes h abk (Or.inl hbx) (hab.notRegFresh hx)]
    have hwc := canon_wf_sub h habx hwx hnx
    have hnc := canon_names_sub h habx hnx
    rw [canon_setEs h _ hnpx] at hwc hnc tk
    have hl := (hE' x).1
    have hm := (hE' x).mode
    simp only [subE_ty, subE_mode, liftE, hown, reduceCtorEq, ite_false, liftMode] at hl hm
    have hm' : E'.mode = .own := hm.symm
    -- where the call places the body, the binding is read as viewing what
    -- the arguments held as well: `letd` records that of memory there too
    have hEq0 : S.liftE x (Entry.arm { E with ty := τ, held := H }) =
        ⟨τ, .own, E.live, rds S.ρ E.path, rds S.ρ H ++ ownHeld true E.ty S.A, τ.dtorViews,
          τ.dtorViews, E.fresh, E.heldFresh⟩ := by
      have hoh : ownHeld true τ S.A = ownHeld true E.ty S.A := by simp only [ownHeld, hov]
      simp [liftE, hown, Entry.arm, liftMode, Mode.ownSlot, hoh, heldA]
    -- (AGORA-937: and substituted)
    have hEq : S.subE (S.liftE x (Entry.arm { E with ty := τ, held := H })) =
        ⟨τ, .own, E.live, (rds S.ρ E.path).flatMap S.subD,
          (rds S.ρ H ++ ownHeld true E.ty S.A).flatMap S.subD, τ.dtorViews,
          τ.dtorViews, E.fresh, E.heldFresh⟩ := by rw [hEq0]; rfl
    have hlh0 : (S.liftE x E).held = rds S.ρ E.held ++ ownHeld true E.ty S.A := by
      simp [liftE, hown, Mode.ownSlot, heldA]
    have hsub0 : (S.subE (S.liftE x E)).held ⊆ (rds S.ρ H ++ ownHeld true E.ty S.A).flatMap S.subD := by
      rw [subE_held, hlh0]; exact S.flatMap_subD_mono (append_sub (rds_subset hH.1) (List.Subset.refl _))
    obtain ⟨hE'l, -, hE'h⟩ := (hE' x).live (by rw [subE_live, liftE_live]; exact hlive)
    obtain ⟨X, hX1, hX2, hX3⟩ : ∃ X : List Dep,
        (∀ d ∈ X, d.kind.isName = false ∧ ∃ Er, S.canon Γ1 d.root = some Er ∧ Er.mode.isRoot = true) ∧
        X ⊆ (rds S.ρ H ++ ownHeld true E.ty S.A).flatMap S.subD ∧
        (E.ty.holdsView = true → ∀ d ∈ (rds S.ρ H ++ ownHeld true E.ty S.A).flatMap S.subD,
          d.kind.isName = false → d ∈ X) := by
      by_cases hv : E.ty.holdsView = true
      · refine ⟨((rds S.ρ H ++ ownHeld true E.ty S.A).flatMap S.subD).filter (fun d => !d.kind.isName),
          fun d hd => ?_, fun d hd => (List.mem_filter.mp hd).1,
          fun _ d hd hnm => List.mem_filter.mpr ⟨hd, by simp [hnm]⟩⟩
        obtain ⟨hd, hnm⟩ := List.mem_filter.mp hd
        have hnm' : d.kind.isName = false := by simpa using hnm
        refine ⟨hnm', ?_⟩
        obtain ⟨d1, hd1, hdd⟩ := List.mem_flatMap.mp hd
        -- (a name is kept as it is, or dropped: what is substituted is no name)
        have hnr : d1.kind.isName = true → False := fun hk => by
          have := S.mem_subD_name hk hdd; subst this; rw [hk] at hnm'; cases hnm'
        refine canon_root_of_subD h hab1 hdd ?_
        rcases List.mem_append.mp hd1 with hd1 | hd1
        · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd1
          obtain ⟨Er, hEr0, hro⟩ := hroot d0 hd0
          exact Or.inl ⟨d0.root, Er, rfl, hEr0, hro, fun hk => (hnr hk).elim⟩
        · simp only [ownHeld, hv, Bool.not_true, Bool.and_false, Bool.false_eq_true, ↓reduceIte] at hd1
          exact Or.inr ⟨A_out h hd1, A_root h hd1⟩
      · exact ⟨[], (fun _ hd => by cases hd), List.nil_subset _, fun hv' => absurd hv' hv⟩
    have hH' : HeldUp (S.canon Γ1) E' (E'.held ++ X) :=
      ⟨List.subset_append_left _ _, fun d hd => by
        rcases List.mem_append.mp hd with hd | hd
        · exact Or.inl hd
        · exact Or.inr (hX1 d hd)⟩
    have hsub : E'.held ++ X ⊆ (rds S.ρ H ++ ownHeld true E.ty S.A).flatMap S.subD := fun d hd => by
      rcases List.mem_append.mp hd with hd | hd
      · exact hsub0 (hE'h hd)
      · exact hX2 hd
    have hEW : EntryWeaker (Entry.arm { E' with ty := τ, held := E'.held ++ X })
        (S.subE (S.liftE x (Entry.arm { E with ty := τ, held := H }))) := by
      rw [hEq]
      refine ⟨rfl, hm, fun hf => ?_, fun _ => ⟨hE'l, fun ho => ?_, hsub⟩,
        fun hd => ⟨by simpa [Entry.arm] using hd, hsub⟩, by simp [Entry.arm],
        fun hd => Or.inl (by simpa [Entry.arm] using hd),
        fun hdb _ _ d hnm => ⟨fun hd => List.mem_append_right _
          (hX3 (by rw [← hov, ← hdv]; simpa [Entry.arm] using hdb) d hd hnm), fun hd => hsub hd⟩,
      fun _ _ hb _ => (by cases hb),
      fun _ hb _ => (by cases hb)⟩
      · simp [Entry.fixed, Entry.arm, hm'] at hf
      · simp [Entry.arm, hm', Mode.ownSlot] at ho
    exact StmtT.letd (H := E'.held ++ X) (by rw [src_rename]; exact hks) (by rw [canon_ρs h _ hnpx, hx]; rfl)
      (h.Fcout x) hr' hm' (by first | (rw [← hl]; exact hty) | (rw [hl]; exact hty)) hstr hview
      (by
        refine ⟨⟨hdtor.1.1, fun g hg hne => ?_⟩, fun y Ey g u hry hy hgy => ?_⟩
        · obtain ⟨i, r0, k0, hig, hk0⟩ := hdtor.1.2 g (by first | (rw [← hl]; exact hg) | (rw [hl]; exact hg)) hne
          exact ⟨i, S.ρ r0, k0.rename S.ρ, hig, by rw [hk0]; simp [Stmt.rename]⟩
        · have key : ∀ y0, S.ρ y0 = y → (r = .takel y0 ∨ r = .taker y0) → EnumGlueOK P g u := by
            intro y0 hy0 hr0
            rw [← hy0, canon_ρ_sub h] at hy
            split at hy
            · cases hy
            cases h0 : Γ y0 with
            | none => rw [h0] at hy; cases hy
            | some E0 =>
              rw [h0] at hy; simp only [Option.map_some, Option.some.injEq, Function.comp] at hy
              refine hdtor.2 y0 E0 g u hr0 h0 ?_
              rw [← liftE_ty' h hab h0, ← subE_ty, hy]; exact hgy
          cases r <;> simp [Rhs.rename] at hry
          · exact key _ hry (Or.inl rfl)
          · exact key _ hry (Or.inr rfl)) hH'
      (StmtT.weakenIn ⟨PW.setE (PW.refl _) hEW, hwc, hnc⟩ tk)
      (EndOK.lift h abk hbx hpe) (not_mem_assigns_rename h.inj hna)
  | @callc _ Γ Γ1 Δ F x c j zs k Ec E ms q σ sig hks hx hxF hc htc hj hσ hhd hout hcT hnz hk hpe hdk ih =>
    intro _ hab hw hn hfo hT hvs
    -- (the interface is a function the statement calls: a call through one
    -- that changes elements through a borrow is a call of such a function,
    -- AGORA-395)
    obtain ⟨E', Γ', hc', hpw, hE'⟩ := callT_ren h hab hP hcT (fun ht => (hT (thru_call (by simp [Stmt.calls]) ht)).call (by simp [Stmt.calls]) ht)
      (fun v hv => (hab.notPi_of_notReg (hvs v (by rcases List.mem_cons.mp hv with rfl | hv <;> simp [Stmt.vars, hv]))))
    obtain ⟨hn1, hEn, _⟩ := hcT.names hP hn
    obtain ⟨hab1, hmo, _⟩ := CallT.absOK (S := S) hcT hab
    obtain ⟨hw1, hdm, hE⟩ := hcT.wf hP hw
    have hx1 : Γ1 x = none := by have := hdm.1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    have hlc : Ec.live = true := by
      obtain ⟨fn, _, hlen, hargs, _⟩ := hcT
      obtain ⟨Ea, hEa, hl, _⟩ := hargs 0 (by rw [← hlen]; simp)
      simp only [List.getD_cons_zero] at hEa; rw [hc] at hEa; cases hEa; exact hl
    have hdb0 : E.dbind = false := hcT.dtor_false.2
    have hwx := hw1.add hx1 (fun _ _ => recvRes_roots hw hdm hc hlc (fun h => by rw [h] at htc; cases htc) hE)
      (fun hd => absurd hd (by simp [hdb0])) (fun ha => absurd ha (by simp [hcT.dtor_false.1]))
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) (recvRes_named (c := c) (Ec := Ec) hEn)
    have habx := hab.add hab1 hx (E := recvRes c Ec E) hmo
    obtain ⟨tk, abk⟩ := ih hks habx hwx hnx (by
      obtain ⟨h1, _, _⟩ := hcT.freshOK hfo
      have hEf : E.fresh = false := by
        obtain ⟨_, _, _, _, _, _, hE, _, _⟩ := hcT; rw [hE]; rfl
      exact h1.bind hx1 (FreshE.of_fresh (by rw [recvRes_fresh]; exact hEf))) (fun ht => (hT ht.callc).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    have hnpx := hab.notPiFresh hx
    have hnrx := hab.notRegFresh hx
    have tk := tk.mono (S.liftX_under h (hab.fresh hx) hnrx)
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx hnrx⟩
    rw [canon_exitScopes h abk (Or.inl hbx) (hab.notRegFresh hx)]
    have hwc := canon_wf_sub h habx hwx hnx
    have hnc := canon_names_sub h habx hnx
    rw [canon_setEs h _ hnpx] at hwc hnc tk
    have hnrc : S.isReg c = false := hvs c (by simp [Stmt.vars])
    have hnpc : S.isPi c = false := hab.notPi_of_notReg hnrc
    refine StmtT.callc (Ec := S.subE (S.liftE c Ec)) (by rw [src_rename]; exact hks)
      (by rw [canon_ρs h _ hnpx, hx]; rfl) (h.Fcout x)
      (canon_some h hc hnpc) (by rw [subE_ty, liftE_ty' h hab hc]; exact htc) hj hσ
      (by rw [subE_ty, liftE_ty' h hab hc]; exact hhd) hout hc'
      (fun z hz d hd hb hdr => ?_)
      (StmtT.weakenIn ⟨PW.setE hpw (recvRes_lifts h hab hc hnpc hmo hdb0 x (by
        obtain ⟨_, _, _, _, _, _, hEeq, _, _⟩ := hcT; rw [hEeq]; rfl) (hE' x)), hwc, hnc⟩ tk)
      (EndOK.lift h abk hbx hpe) (fun ho hd => dtorHead_rename h.inj (hdk ho hd))
    -- no argument is a binding the receiver may change: in the callee, nor
    -- where the call places it (what the arguments held names the frame; a
    -- symbolic name's image names an `inout` argument the receiver names)
    obtain ⟨z0, hz0, rfl⟩ := List.mem_map.mp hz
    replace hd := S.mem_subE_ρ h hd hdr
    by_cases hrb : Ec.mode = .rootb
    · rcases liftE_rootb_ρ h hab hc hrb hd hdr with ⟨b, t, rfl, hbw, hpt, hbn, hbr, hf⟩ | ⟨rfl, _⟩
      · exact hnz z0 hz0 ⟨z0, .name b t⟩ (abs_sym hab hc hrb hf (h.sym_of _ b t hbw hpt hbn hbr)) hb rfl
      · -- its region, by its handle: no change by name
        simp [Kind.bound] at hb
    · rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
      · exact hnz z0 hz0 d0 hd0 hb (h.inj _ _ hdr)
      · exact A_out h ha z0 hdr.symm
  | @callcE _ Γ Γ1 Δ F x c j zs k Ec E ms q σ sig b hks hx hxF hc htc hcan hq hj hσ hsp hsl hsr hso hny hdc hcT hk
      hpe hnσ hdk ih =>
    intro _ hab hw hn hfo hT hvs
    -- the package may be replaced: what depends on it ends where it is placed
    have hal : Allowed S .replace false c := by
      rcases allowed_canDo' hab hc hcan with h0 | ⟨b', hb', hbb, hk'⟩
      · exact Or.inl h0
      · exact Or.inr ⟨b', hb', hbb, fun k' _ => hk' k' (by cases k' <;> rfl)⟩
    have habk : S.AbsOK (A2.kill .replace false c Γ) := hab.kill _ _ _
    obtain ⟨E', Γ', hc', hpw, hE'⟩ := callT_ren h habk hP hcT (fun ht => absurd ht hnσ)
      (fun v hv => (hab.notPi_of_notReg (hvs v (by rcases List.mem_cons.mp hv with rfl | hv <;> simp [Stmt.vars, hv]))))
    obtain ⟨hn1, hEn, _⟩ := hcT.names hP (hn.kill .replace false c)
    obtain ⟨hab1, hmo, _⟩ := CallT.absOK (S := S) hcT habk
    obtain ⟨hw1, hdm, hE⟩ := hcT.wf hP (hw.kill .replace false c)
    have hxk : A2.kill .replace false c Γ x = none := by simp [A2.kill, hx]
    have hx1 : Γ1 x = none := by have := hdm.1 x; rw [hxk] at this; cases h' : Γ1 x <;> simp_all
    have hdb0 : E.dbind = false := hcT.dtor_false.2
    have hwx := (hw1.add hx1 (fun _ _ => hE) (fun hd => absurd hd (by simp [hdb0]))
      (fun ha => absurd ha (by simp [hcT.dtor_false.1])) (fun hd => absurd hd (by simp [hdb0]))).kill .replace false c
    have hnx := (NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h)
      hEn).kill .replace false c
    have habx := (habk.add hab1 hxk hmo).kill .replace false c
    obtain ⟨tk, abk⟩ := ih hks habx hwx hnx (by
      obtain ⟨h1, hE, _⟩ := hcT.freshOK (hfo.kill _ _ _)
      exact (h1.bind hx1 hE).kill _ _ _) (fun ht => (hT ht.callcE).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    have hnpx := hab.notPiFresh hx
    have hnrx := hab.notRegFresh hx
    have tk := tk.mono (S.liftX_under h (hab.fresh hx) hnrx)
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx hnrx⟩
    rw [canon_exitScopes h abk (Or.inl hbx) (hab.notRegFresh hx)]
    have hwc := canon_wf_sub h habx hwx hnx
    have hnc := canon_names_sub h habx hnx
    have hnrc : S.isReg c = false := hvs c (by simp [Stmt.vars])
    have hnpc : S.isPi c = false := hab.notPi_of_notReg hnrc
    rw [canon_kill h (habk.add hab1 hxk hmo) hal hnpc hnrc, canon_setEs h _ hnpx] at hwc hnc tk
    rw [canon_kill h hab hal hnpc hnrc] at hc'
    have hrb : Ec.mode ≠ .rootb := by rcases hcan with h0 | ⟨b', h0, _⟩ <;> rw [h0] <;> simp
    have hbr : ∀ bh, S.bnd c = some bh → bh.1 = .replace := by
      refine bnd_replace hab hc ?_
      rcases canDo_replace_cases hcan with h0 | h0
      · exact Or.inl h0
      · exact Or.inr (Or.inl h0)
    have hsp' : (∃ ps, sig.params = (.inout b, .fn ms q) :: ps ∧ (S.subE (S.liftE c Ec)).ty = .fn ms q ∧ Cross.send.Le q ∧
          ∀ z ∈ zs.map S.ρ, ∀ d ∈ (argE (S.canon Γ) z).vdeps, (S.canon Γ d.root).isSome) ∨
        (sig.params = [(.sink, (S.subE (S.liftE c Ec)).ty)] ∧ zs.map S.ρ = [] ∧ (S.subE (S.liftE c Ec)).vdeps = [] ∧
          (S.subE (S.liftE c Ec)).mode = .own ∧ (S.subE (S.liftE c Ec)).live = true ∧ q.drops = true ∧ sig.resOwn = false) := by
      rcases hsp with ⟨ps, h1, h2, h3, h4⟩ | ⟨h1, hz, hv, hm, hl, hd, hr⟩
      · refine Or.inl ⟨ps, h1, by rw [subE_ty, liftE_ty' h hab hc]; exact h2, h3, fun z' hz' => ?_⟩
        obtain ⟨z, hz, rfl⟩ := List.mem_map.mp hz'
        exact argE_canon_rooted h hab ((hab.notPi_of_notReg (hvs z (by simp [Stmt.vars, hz])))) (h4 z hz)
      · refine Or.inr ⟨by rw [subE_ty, liftE_ty' h hab hc]; exact h1, by rw [hz]; rfl, ?_,
          by rw [subE_mode, liftE_mode c hrb, hm]; rfl, by rw [subE_live, liftE_live]; exact hl, hd, hr⟩
        have ho : Ec.mode.ownSlot = true := by rw [hm]; rfl
        have hh : Ec.held = [] := by simpa [Entry.vdeps, ho] using hv
        have hvw : Ec.ty.holdsView = false := by
          rw [← Ty.holdsView_undtor, htc]; cases q <;> simp_all [Ty.holdsView]
        rw [subE_vdeps]
        simp [Entry.vdeps, liftE_mode c hrb, hm, liftMode, liftE_held_named hrb ho hh hvw, Mode.ownSlot]
    exact StmtT.callcE (Ec := S.subE (S.liftE c Ec)) (by rw [src_rename]; exact hks) (by rw [canon_ρs h _ hnpx, hx]; rfl) (h.Fcout x)
      (canon_some h hc hnpc) (by rw [subE_ty, liftE_ty' h hab hc]; exact htc)
      (by rw [subE_mode, liftE_mode c hrb]; exact canDo_lift hcan) hq hj hσ hsp' hsl hsr hso
      (NoPin.lift h hab hbr) (DtorSafe.canon h hal hdc) (by simpa using hc')
      (StmtT.weakenIn ⟨(hpw.setE (hE' x)).kill _ _ _, hwc, hnc⟩ tk) (EndOK.lift h abk hbx hpe) hnσ
      (fun ho hd => dtorHead_rename h.inj (hdk ho hd))
  | @letcall _ Γ Γ1 Δ F x f args k E hks hx hxF hc hk hpe hdk ih =>
    intro _ hab hw hn hfo hT hvs
    obtain ⟨E', Γ', hc', hpw, hE'⟩ := callT_ren h hab hP hc (fun ht => (hT (thru_call (by simp [Stmt.calls]) ht)).call (by simp [Stmt.calls]) ht)
      (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, hv]))))
    obtain ⟨hn1, hEn, _⟩ := hc.names hP hn
    obtain ⟨hab1, hmo, _⟩ := CallT.absOK (S := S) hc hab
    obtain ⟨hw1, hdm, hE⟩ := hc.wf hP hw
    have hx1 : Γ1 x = none := by have := hdm.1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    have hwx := hw1.add hx1 (fun _ _ => hE) (fun hd => absurd hd (by simp [hc.dtor_false.2]))
      (fun ha => absurd ha (by simp [hc.dtor_false.1])) (fun hd => absurd hd (by simp [hc.dtor_false.2]))
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) hEn
    have habx := hab.add hab1 hx hmo
    obtain ⟨tk, abk⟩ := ih hks habx hwx hnx (by obtain ⟨h1, hE, _⟩ := hc.freshOK hfo; exact h1.bind hx1 hE)
      (fun ht => (hT ht.letcall).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    have hnpx := hab.notPiFresh hx
    have hnrx := hab.notRegFresh hx
    have tk := tk.mono (S.liftX_under h (hab.fresh hx) hnrx)
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx hnrx⟩
    rw [canon_exitScopes h abk (Or.inl hbx) (hab.notRegFresh hx)]
    have hwc := canon_wf_sub h habx hwx hnx
    have hnc := canon_names_sub h habx hnx
    rw [canon_setEs h _ hnpx] at hwc hnc tk
    exact StmtT.letcall (by rw [src_rename]; exact hks) (by rw [canon_ρs h _ hnpx, hx]; rfl) (h.Fcout x) hc'
      (StmtT.weakenIn ⟨PW.setE hpw (hE' x), hwc, hnc⟩ tk)
      (EndOK.lift h abk hbx hpe) (fun fn hf ho hd => dtorHead_rename h.inj (hdk fn hf ho hd))
  | scope => intro hs; simp [Stmt.src] at hs
  | scopeD => intro hs; simp [Stmt.src] at hs
  | scopeL => intro hs; simp [Stmt.src] at hs
  | rbind => intro hs; simp [Stmt.src] at hs
  | frozen => intro hs; simp [Stmt.src] at hs
  | panic hwf hnΔ hdom hm hdk hst hfΔ =>
    intro _ hab _ _ hfo _ _
    have habΔ := hab.of_same hdom hm
    obtain ⟨hdom', hm'⟩ := canon_same h hab hdom hm
    exact ⟨StmtT.panic (canon_wf_sub h habΔ hwf hnΔ) (canon_names_sub h habΔ hnΔ) hdom' hm' (DKeep.canon h hdk hm)
      (DStay.canon h hst) (canon_freshT h habΔ hfo hdom' hm' hfΔ), habΔ⟩
  | @letrec _ Γ Γ1 Δ F x f k E fn hks hx hxF hf hp hty ho hc hk hpe ih =>
    intro _ hab hw hn hfo hT hvs
    obtain ⟨E', Γ', hc', hpw, hE'⟩ := callT_ren h hab hP hc (fun ht => (hT (thru_call (by simp [Stmt.calls]) ht)).call (by simp [Stmt.calls]) ht)
      (fun v hv => by simp at hv)
    obtain ⟨hn1, hEn, _⟩ := hc.names hP hn
    obtain ⟨hab1, hmo, _⟩ := CallT.absOK (S := S) hc hab
    obtain ⟨hw1, hdm, hE⟩ := hc.wf hP hw
    have hx1 : Γ1 x = none := by have := hdm.1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    have hwx := hw1.add hx1 (fun _ _ => hE) (fun hd => absurd hd (by simp [hc.dtor_false.2]))
      (fun ha => absurd ha (by simp [hc.dtor_false.1])) (fun hd => absurd hd (by simp [hc.dtor_false.2]))
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) hEn
    have habx := hab.add hab1 hx hmo
    obtain ⟨tk, abk⟩ := ih hks habx hwx hnx (by obtain ⟨h1, hE, _⟩ := hc.freshOK hfo; exact h1.bind hx1 hE)
      (fun ht => (hT ht.letrec).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    have hnpx := hab.notPiFresh hx
    have hnrx := hab.notRegFresh hx
    have tk := tk.mono (S.liftX_under h (hab.fresh hx) hnrx)
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx hnrx⟩
    rw [canon_exitScopes h abk (Or.inl hbx) (hab.notRegFresh hx)]
    have hwc := canon_wf_sub h habx hwx hnx
    have hnc := canon_names_sub h habx hnx
    rw [canon_setEs h _ hnpx] at hwc hnc tk
    exact StmtT.letrec (by rw [src_rename]; exact hks) (by rw [canon_ρs h _ hnpx, hx]; rfl) (h.Fcout x) hf hp
      hty ho hc' (StmtT.weakenIn ⟨PW.setE hpw (hE' x), hwc, hnc⟩ tk)
      (EndOK.lift h abk hbx hpe)
  | catchR => intro hs; simp [Stmt.src] at hs
  | @assign _ Γ Γ1 F x r Ex E hx hxF hmodes hr hty hxd hsome hpin hds hxdb htk =>
    intro _ hab hw hn hfo hT hvs
    obtain ⟨E', hr', hE'⟩ := RhsT.ren h hab hfo hr (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, hv]))))
    have hnrx : S.isReg x = false := hvs x (by simp [Stmt.vars])
    have hnpx : S.isPi x = false := hab.notPi_of_notReg hnrx
    have hab1 := RhsT.absOK (S := S) hr hab
    obtain ⟨hmo, hlive⟩ := RhsT.out hr
    have hrbE : E.mode ≠ .rootb := by rcases hmo with hm | hm <;> rw [hm] <;> simp
    have hrbx : Ex.mode ≠ .rootb := by
      rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩ <;> rw [h1] <;> simp
    have hos : Ex.mode.ownSlot = E.mode.ownSlot := by
      rcases hmodes with ⟨h1, h2⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rw [h1, h2] <;> rfl
    have hw' := hE' x
    have hm' : E'.mode = liftMode E.mode := by rw [← hw'.mode, subE_mode, liftE_mode x hrbE]
    have hty' : E'.ty = E.ty := by rw [← hw'.1, subE_ty, liftE_ty x hrbE]
    have hmx' : (S.subE (S.liftE x Ex)).mode = liftMode Ex.mode := by rw [subE_mode]; exact liftE_mode x hrbx
    have hal : Allowed S .replace false x := allowed_replace hab hx (by
      rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩
      · exact Or.inl h1
      · exact Or.inr (Or.inr h1)
      · exact Or.inr (Or.inl h1)) false
    have hT := StmtT.assign (P := P) (ξ := .none) hx hxF hmodes hr hty hxd hsome hpin hds hxdb htk
    have hwo := hT.wf hP hw
    have hno := hT.names hP rfl hn
    have habo : S.AbsOK (setE (A2.kill .replace false x Γ1) x { E with mode := Ex.mode }) :=
      (hab1.kill _ _ _).setE' hab hx rfl hty hrbx (fun hf => absurd hf (by
        rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩ <;> simp [h1]))
    refine ⟨?_, habo⟩
    have hwc := canon_wf_sub h habo hwo hno
    have hnc := canon_names_sub h habo hno
    rw [canon_setEs h _ hnpx, canon_kill h hab1 hal hnpx hnrx] at hwc hnc ⊢
    have hT' := StmtT.assign (P := P) (ξ := .none) (x := S.ρ x) (Ex := S.subE (S.liftE x Ex)) (E := E')
      (F := S.Fc) (canon_some h hx hnpx) (h.Fcout x) (by
        rw [hmx', hm']
        rcases hmodes with ⟨h1, h2⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rw [h1, h2]
        · exact Or.inl ⟨rfl, rfl⟩
        · exact Or.inl ⟨rfl, rfl⟩
        · exact Or.inr (Or.inr ⟨rfl, rfl⟩))
      hr' (by rw [hty', subE_ty, liftE_ty x hrbx, hty]) (by
        have hnl : S.ρ x ∉ roots (S.liftE x E).vdeps := roots_lift_ρ h (liftE_vdeps_sub hrbE) hxd
        exact fun hm => hnl (roots_subE_ρ h (roots_sub (vdeps_sub hw' (by
          rw [subE_live, liftE_live]; exact hlive)) hm)))
      (by rw [canon_ρs h _ hnpx]; simpa using hsome)
      (NoPin.lift h hab (bnd_replace hab hx (by
        rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩
        · exact Or.inl h1
        · exact Or.inr (Or.inl h1)
        · exact Or.inr (Or.inr h1))))
      (DtorSafe.canon h hal hds) (by rw [subE_dbind, liftE_dbind h, ite_eq_right hrbx]; exact hxdb)
      (TakeOK.canon h hab htk)
    refine StmtT.weakenOut (canon_wf_sub h hab hw hn) (canon_names_sub h hab hn) hT'.ofNone
      (Or.inr ⟨PW.setE (PW.refl _) ?_, hwc, hnc⟩)
    -- (Agora #916: the binding is read as a borrow exactly when its value is)
    have hhA : S.heldA { E with mode := Ex.mode } = S.heldA E := by
      rcases hmodes with ⟨h1, h2⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> simp [heldA, h1, h2]
    have hf : S.liftE x { E with mode := Ex.mode } =
        ⟨E.ty, liftMode Ex.mode, E.live,
         rds S.ρ E.path ++ (if Ex.mode.ownSlot || (E.fresh && E.ty != .int) then [] else S.A),
         rds S.ρ E.held ++ ownHeld Ex.mode.ownSlot E.ty (S.heldA E), E.dtor, E.dbind, E.fresh, E.heldFresh⟩ := by
      simp only [liftE, hrbx, ↓reduceIte]; rw [hhA]
    have hf' : S.liftE x E =
        ⟨E.ty, liftMode E.mode, E.live,
         rds S.ρ E.path ++ (if E.mode.ownSlot || (E.fresh && E.ty != .int) then [] else S.A),
         rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty (S.heldA E), E.dtor, E.dbind, E.fresh, E.heldFresh⟩ := by
      simp only [liftE, hrbE, ↓reduceIte]
    rw [hf, hmx']
    rw [hf'] at hw'
    have hdbw : E'.dbind = E.dbind := by have := hw'.dbind; simpa using this.symm
    have hwf' := hw'.fresh
    have hhw := hw'.heldFresh
    obtain ⟨_, _, _, hlv, hdv⟩ := hw'
    refine EntryWeaker.mk' hty'.symm rfl (not_fixed_liftMode rfl hrbx) ?_ (fun ho => ?_) ?_
      (fun hd => (hdv hd).1) (hdh := fun hh => by
        have : E'.dbind = true := hh
        rw [hdbw, hr.dtor_false.2] at this; cases this)
      (hf := fun hl' hn' hb' hfr => by
        -- Agora #909: a fresh borrow assigned is the lift of the fresh borrow given
        have hEx : Ex.mode = .bor := by
          revert hb'; cases hme : Ex.mode <;> simp [liftMode]
        have hEb : E.mode = .bor := by
          rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨_, h2⟩
          · rw [h1] at hEx; cases hEx
          · rw [h1] at hEx; cases hEx
          · exact h2
        obtain ⟨h1, h2⟩ := hwf' (by simpa using hl') (by simpa using hn') (by simp [hEb, liftMode]) hfr
        exact ⟨h1, by simpa [hEb, hEx, Mode.ownSlot] using h2⟩)
      (hg := fun hn' hb' hhf => by
        -- Agora #916: ... and so a held-fresh one
        have hEx : Ex.mode = .bor := by
          revert hb'; cases hme : Ex.mode <;> simp [liftMode]
        have hEb : E.mode = .bor := by
          rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨_, h2⟩
          · rw [h1] at hEx; cases hEx
          · rw [h1] at hEx; cases hEx
          · exact h2
        exact hhw (by simpa using hn') (by simp [hEb, liftMode]) hhf)
    · show E.live = E'.live
      rw [hlive]; exact ((hlv hlive).1).symm
    · have ho' : E.mode.ownSlot = false := by
        rw [← hos]; simpa [liftMode_ownSlot] using ho
      rw [hos]
      exact (hlv hlive).2.1 (by rw [hm', liftMode_ownSlot]; exact ho')
    · rw [hos]; exact (hlv hlive).2.2
  | @ite _ Γ Δ F c a b ha hb hc ta tb iha ihb =>
    intro _ hab hw hn hfo hT hvs
    obtain ⟨t1, ab1⟩ := iha ha hab hw hn hfo (fun ht => (hT ht.ite_l).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    obtain ⟨t2, _⟩ := ihb hb hab hw hn hfo (fun ht => (hT ht.ite_r).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    exact ⟨StmtT.ite (by rw [src_rename]; exact ha) (by rw [src_rename]; exact hb)
      (exprT_ren h hab hc (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, hv]))))) t1 t2, ab1⟩
  | @«while» _ Γ F c k hk hc tk ih =>
    intro _ hab hw hn hfo hT hvs
    obtain ⟨t, _⟩ := ih hk hab hw hn hfo (fun ht => (hT ht.wh).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    exact ⟨StmtT.while (by rw [src_rename]; exact hk) (exprT_ren h hab hc (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, hv]))))) t, hab⟩
  | @push _ Γ Γ1 F x y Ex Ey Ex1 t D hx hl hty hcan hxF hy hly htyy hyx hpa hxD hx1 hl1 hds hdb =>
    intro _ hab hw hn hfo hT hvs
    have hnrx : S.isReg x = false := hvs x (by simp [Stmt.vars])
    have hnpx : S.isPi x = false := hab.notPi_of_notReg hnrx
    have hnry : S.isReg y = false := hvs y (by simp [Stmt.vars])
    have hnpy : S.isPi y = false := hab.notPi_of_notReg hnry
    obtain ⟨D', hpa', hD', hD'o⟩ := pushArg_rens h hab hy hnpy hpa
    have hab1 := PushArg.absOK (S := S) hy hpa hab
    have hrbx : Ex.mode ≠ .rootb := by rcases hcan with hm | ⟨b, hm, _⟩ <;> rw [hm] <;> simp
    obtain ⟨E0, h0, hm1⟩ := (hpa.domMode hy).2 x Ex1 hx1
    rw [hx] at h0; cases h0
    have hrb1 : Ex1.mode ≠ .rootb := by rw [hm1]; exact hrbx
    have hT := StmtT.push (P := P) (ξ := .none) hx hl hty hcan hxF hy hly htyy hyx hpa hxD hx1 hl1 hds hdb
    have hwo := hT.wf hP hw
    have hno := hT.names hP rfl hn
    have habo : S.AbsOK (setE (A2.kill .realloc t.holdsView x Γ1) x
        { Ex1 with held := Ex1.held ++ ownHeld true t D }) :=
      (hab1.kill _ _ _).setE' hab1 hx1 rfl rfl hrb1 (fun hf => by
        have hf0 : Ex1.fixed := hf
        obtain ⟨hl0, hh0⟩ := hab1.fixed hx1 hf0 hrb1
        have hty1 : Ex1.ty = .vec t := by rw [PushArg.ty_at hpa hy hx hx1, hty]
        have hv : t.holdsView = false := by
          rcases hf0 with h' | ⟨_, _, _, h'⟩
          · exact absurd h' hrb1
          · rw [hty1] at h'; exact h'
        exact ⟨hl0, by simp [hh0, ownHeld, hv]⟩)
    refine ⟨?_, habo⟩
    have hwc := canon_wf_sub h habo hwo hno
    have hnc := canon_names_sub h habo hno
    rw [canon_setEs h _ hnpx, canon_kill h hab1 (allowed_canDo hab hx hty hcan) hnpx (hab.notReg hx (fun h' => by have := hcan.ownSlot; rw [h'] at this; cases this))] at hwc hnc ⊢
    have hty1 : Ex1.ty = .vec t := by rw [PushArg.ty_at hpa hy hx hx1, hty]
    -- (Agora #916: an owner, or an `inout` parameter, is lifted with all the
    -- arguments hold)
    have hhA1 : S.heldA Ex1 = S.A :=
      S.heldA_own (by rw [PushArg.mode_at hpa hy hx hx1]; exact hcan.ownSlot)
    have hhA1' : S.heldA { Ex1 with held := Ex1.held ++ ownHeld true t D } = S.A := hhA1
    have hown' : ownHeld true t S.A ⊆ ownHeld Ex1.mode.ownSlot Ex1.ty S.A := by
      intro d h1
      rw [hty1]
      cases Ex1.mode.ownSlot
      · simp only [ownHeld_false]; exact ownHeld_sub _ _ _ h1
      · have : ownHeld true (Ty.vec t) S.A = ownHeld true t S.A := by simp [ownHeld, Ty.holdsView]
        rw [this]; exact h1
    have hD'' : D' ⊆ (rds S.ρ D ++ ownHeld Ex1.mode.ownSlot Ex1.ty S.A).flatMap S.subD :=
      fun d hd => S.flatMap_subD_mono (append_sub (List.Subset.refl _) hown') (hD'o htyy hd)
    have hLh : (S.liftE x Ex1).held = rds S.ρ Ex1.held ++ ownHeld Ex1.mode.ownSlot Ex1.ty S.A := by
      rw [liftE_held hrb1, hhA1]
    have hLh' : (S.liftE x { Ex1 with held := Ex1.held ++ ownHeld true t D }).held =
        rds S.ρ (Ex1.held ++ ownHeld true t D) ++ ownHeld Ex1.mode.ownSlot Ex1.ty S.A := by
      rw [liftE_held (E := { Ex1 with held := Ex1.held ++ ownHeld true t D }) hrb1, hhA1']
    -- (Agora #782: what is pushed into a `letd` binding, it views already)
    have hsubL : (S.subE (S.liftE x Ex1)).dbind = true → ownHeld true t D' ⊆ (S.subE (S.liftE x Ex1)).held := by
      intro hd
      have hd0 : Ex1.dbind = true := by simpa [liftE, hrb1] using hd
      have hsub := hdb hd0
      by_cases hv : t.holdsView = true
      · rw [ownHeld_views true hv D', subE_held, hLh]
        have hD0 : rds S.ρ D ⊆ rds S.ρ Ex1.held := by
          rw [← ownHeld_views true hv D]; exact rds_subset hsub
        exact fun d hd' => S.flatMap_subD_mono (append_sub hD0 (List.Subset.refl _)) (hD'' hd')
      · have hv' : t.holdsView = false := by simpa using hv
        simp [ownHeld, hv']
    have hxD' : S.ρ x ∉ roots D' := fun hm =>
      roots_lift_ρ h (List.Subset.refl _) hxD (S.roots_flatMap_subD_ρ h (roots_sub hD' hm))
    have hT' := StmtT.push (P := P) (ξ := .none) (F := S.Fc) (x := S.ρ x) (y := S.ρ y)
      (Ex := S.subE (S.liftE x Ex)) (Ey := S.subE (S.liftE y Ey)) (Ex1 := S.subE (S.liftE x Ex1)) (t := t)
      (D := D') (canon_some h hx hnpx) (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_ty, liftE_ty' h hab hx]; exact hty)
      (by rw [subE_mode, liftE_mode x hrbx]; exact canDo_lift hcan) (h.Fcout x)
      (canon_some h hy hnpy) (by rw [subE_live, liftE_live]; exact hly)
      (by rw [subE_ty, liftE_ty' h hab hy]; exact htyy)
      (fun e => hyx (h.inj _ _ e)) hpa' hxD'
      (canon_some h hx1 hnpx) (by rw [subE_live, liftE_live]; exact hl1)
      (DtorSafe.canon h (allowed_canDo hab hx hty hcan) hds)
      hsubL
    refine StmtT.weakenOut (canon_wf_sub h hab hw hn) (canon_names_sub h hab hn) hT'.ofNone
      (Or.inr ⟨PW.setE (PW.refl _) ?_, hwc, hnc⟩)
    -- what the binding holds: all the arguments hold, and the value's
    -- dependencies, renamed and substituted
    have hmono : ∀ {L : List Dep}, L ⊆ Ex1.held ++ ownHeld true t D →
        (rds S.ρ L ++ ownHeld Ex1.mode.ownSlot Ex1.ty S.A).flatMap S.subD ⊆
          (S.subE (S.liftE x { Ex1 with held := Ex1.held ++ ownHeld true t D })).held := by
      intro L hL
      rw [subE_held, hLh']
      exact S.flatMap_subD_mono (append_sub (rds_subset hL) (List.Subset.refl _))
    refine EntryWeaker.mk' (by simp [liftE, hrb1]) (by simp [liftE, hrb1])
      (not_fixed_liftMode (by simp [liftE, hrb1]) hrb1) (by simp [liftE, hrb1]) (fun _ => by simp [liftE, hrb1]) ?_
      (hf := fun _ _ hb _ => absurd hb (by
        rw [show Ex1.mode = Ex.mode from PushArg.mode_at hpa hy hx hx1]
        rcases hcan with h1 | ⟨b', h1, _⟩ <;> simp [liftE, h1, liftMode]))
      (hg := fun _ hb _ => absurd hb (by
        rw [show Ex1.mode = Ex.mode from PushArg.mode_at hpa hy hx hx1]
        rcases hcan with h1 | ⟨b', h1, _⟩ <;> simp [liftE, h1, liftMode]))
      (hdh := fun hh _ _ d _ => by
        have hd0 : Ex1.dbind = true := by simpa [liftE, hrb1] using hh
        have hsub := hdb hd0
        have hsl := hsubL (by simpa [liftE, hrb1] using hd0)
        rw [subE_held, hLh] at hsl
        constructor
        · intro h1
          refine List.mem_append_left _ ?_
          rw [subE_held, hLh]
          rw [subE_held, hLh'] at h1
          exact S.flatMap_subD_mono (append_sub (rds_subset (List.append_subset.mpr
            ⟨List.Subset.refl _, hsub⟩)) (List.Subset.refl _)) h1
        · intro h1
          rcases List.mem_append.mp h1 with h1 | h1
          · rw [subE_held, hLh] at h1
            exact hmono (List.subset_append_left _ _) h1
          · exact hmono (List.subset_append_left _ _) (hsl h1))
    refine List.append_subset.mpr ⟨?_, ?_⟩
    · rw [subE_held, hLh]; exact hmono (List.subset_append_left _ _)
    · intro d hd
      by_cases hv : t.holdsView = true
      · rw [ownHeld_views true hv D'] at hd
        refine hmono (L := ownHeld true t D) (List.subset_append_right _ _) ?_
        rw [ownHeld_views true hv D]; exact hD'' hd
      · have hv' : t.holdsView = false := by simpa using hv
        simp [ownHeld, hv'] at hd
  | @free _ Γ F x E t hx hl hm hty hxF hpe hdf =>
    intro _ hab _ _ _ _ hvs
    have hrb : E.mode ≠ .rootb := by rw [hm]; simp
    have hbx : S.bnd x = none := by
      cases hb : S.bnd x with
      | none => rfl
      | some bh =>
        obtain ⟨E', hE', hmE, _⟩ := hab.2.2.1 x bh hb
        rw [hx] at hE'; cases hE'; rw [hm] at hmE; cases hmE
    refine ⟨?_, (hab.kill _ _ _).setE' hab hx rfl rfl hrb (fun hf => absurd hf (by simp [hm]))⟩
    have hnrx : S.isReg x = false := hvs x (by simp [Stmt.vars])
    have hnpx : S.isPi x = false := hab.notPi_of_notReg hnrx
    rw [canon_setEs h _ hnpx, canon_kill h hab (allowed_own hab hx hm _ _) hnpx (hab.notReg hx (by rw [hm]; simp)), liftE_moved _ hrb]
    exact StmtT.free (canon_some h hx hnpx) (by rw [subE_live, liftE_live]; exact hl)
      (by rw [subE_mode, liftE_mode x hrb, hm]; rfl) (by rw [subE_ty, liftE_ty' h hab hx]; exact hty) (h.Fcout x)
      (EndOK.lift h hab hbx hpe) hdf
  | @unpair ξ Γ Δ F y x z k E a b hks hy hl hm hty hyF hx hz hxz hxF hzF hk _ hdy hpze hpxe hdx hdz ih =>
    intro _ hab hw hn hfo hT hvs
    have hrep := canDo_replace_cases hm
    have hrb : E.mode ≠ .rootb := by rcases hrep with h1 | h1 <;> rw [h1] <;> simp
    have hxy : x ≠ y := fun e => by rw [e, hy] at hx; cases hx
    have hzy : z ≠ y := fun e => by rw [e, hy] at hz; cases hz
    have hab1 : S.AbsOK (setE (kill .replace false y Γ) y { E with live := false, dtor := false }) :=
      (hab.kill _ _ _).setE' hab hy rfl rfl hrb (fun hf => absurd hf (by
        rcases hrep with h1 | h1 <;> simp [h1]))
    have hcm : ∀ t, (compE E t).mode = .own ∨ (compE E t).mode = .bor := by
      intro t; cases t <;> simp [compE, intE]
    have habx := AbsOK.add hab hab1 hx (hcm a)
    have habz := AbsOK.add hab habx hz (hcm b)
    have hw3 := hw.unpair (a := a) (b := b) hy hl hm.ownSlot (unpair_ne_int hty) hx hz hxz
    have hn3 := hn.unpair (a := a) (b := b) hy hl (unpair_ne_int hty) hx hz hxz
    obtain ⟨tk, abk⟩ := ih hks habz hw3 hn3 (by
      obtain ⟨h1, _⟩ := hfo.moved hy
      have h2 := h1.bind (setE_none (kill_at_none hx _ _ _) hxy) (FreshE.of_fresh (compE_fresh E a))
      exact h2.bind (setE_none (setE_none (kill_at_none hz _ _ _) hzy) (fun e => hxz e.symm))
        (FreshE.of_fresh (compE_fresh E b))) (fun ht => (hT ht.unpair).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    have tk := tk.mono (ξ' := ((S.liftX ξ).under (S.ρ x)).under (S.ρ z))
      (fun n Γc hh => ⟨(S.liftX_under h (hab.fresh hz) (hab.notRegFresh hz) n Γc hh).1,
        S.liftX_under h (hab.fresh hx) (hab.notRegFresh hx) _ _ (S.liftX_under h (hab.fresh hz) (hab.notRegFresh hz) n Γc hh).2⟩)
    have hbx := hab.fresh hx
    have hbz := hab.fresh hz
    have hnpx := hab.notPiFresh hx
    have hnrx := hab.notRegFresh hx
    have hnpz := hab.notPiFresh hz
    have hnrz := hab.notRegFresh hz
    have hnry : S.isReg y = false := hvs y (by simp [Stmt.vars])
    have hnpy : S.isPi y = false := hab.notPi_of_notReg hnry
    have hpz := EndOK.lift h abk hbz hpze
    have hpx := EndOK.lift h (abk.exitScope hbz hnrz) hbx hpxe
    rw [canon_exitScopes h abk (Or.inl hbz) (hab.notRegFresh hz)] at hpx
    refine ⟨?_, (abk.exitScope hbz hnrz).exitScope hbx hnrx⟩
    rw [canon_exitScopes h (abk.exitScope hbz hnrz) (Or.inl hbx) (hab.notRegFresh hx), canon_exitScopes h abk (Or.inl hbz) (hab.notRegFresh hz)]
    have hwc := canon_wf_sub h habz hw3 hn3
    have hnc := canon_names_sub h habz hn3
    have hal : Allowed S .replace false y := allowed_replace hab hy (by
      rcases hrep with h1 | h1
      · exact Or.inl h1
      · exact Or.inr (Or.inr h1)) false
    rw [canon_setEs h _ hnpz, canon_setEs h _ hnpx, canon_setEs h _ hnpy, canon_kill h hab hal hnpy hnry,
      liftE_moved _ hrb] at hwc hnc tk
    have hxz' : S.ρ x ≠ S.ρ z := fun e => hxz (h.inj _ _ e)
    have hcl : ∀ t w, EntryWeaker (compE (S.subE (S.liftE y E)) t) (S.subE (S.liftE w (compE E t))) :=
      fun t w => by rw [compE_subE]; exact S.subE_weaker (compE_lift h hab hy t w)
    refine StmtT.unpair (by rw [src_rename]; exact hks) (canon_some h hy hnpy)
      (by rw [subE_live, liftE_live]; exact hl) (by
        rw [subE_mode, liftE_mode y hrb]; rcases hrep with h1 | h1 <;> rw [h1] <;> exact Or.inl rfl)
      (by rw [subE_ty, liftE_ty' h hab hy]; exact hty)
      (h.Fcout y) (by rw [canon_ρs h _ hnpx, hx]; rfl) (by rw [canon_ρs h _ hnpz, hz]; rfl) hxz' (h.Fcout x)
      (h.Fcout z)
      (StmtT.weakenIn ⟨PW.setE (PW.setE (PW.refl _) (hcl a x)) (hcl b z),
        hwc, hnc⟩ tk) (NoPin.lift h hab (bnd_replace hab hy (by
          rcases hrep with h1 | h1
          · exact Or.inl h1
          · exact Or.inr (Or.inl h1)))) (DtorSafe.canon h hal hdy) hpz hpx
      (fun ha => dtorHead_rename h.inj (hdx ha)) (fun hb => dtorHead_rename h.inj (hdz hb))
  | @editB ξ0 Γ Γ1 F x op Ex Ex1 t D b hx hmx hl hty hhv hxF0 harg hyx hx1 hl1 hthru hdf hbf =>
    intro hsrc0 hab hw hn hfo hT hvs
    have hab1 : S.AbsOK Γ1 := EditArg.absOK harg hab
    have hm1 : Ex1.mode = .bor := by rw [harg.at_ne hyx hx hx1 hl1, hmx]
    -- Agora #909: an edit through a fresh borrow (`edit false`) needs no S.R = [];
    -- AGORA-937 (3d): an `edit true` is placed by a call that passes no views, or
    -- one ready for a change through its regions
    have hcase : ((S.R = [] ∨ Ex.fresh = true) ∧ (∀ d0 ∈ memDeps Ex.path, S.isPi d0.root = true → S.R = [])) ∨
        S.ThruReady := by
      cases b with
      | false =>
        refine Or.inl ⟨Or.inr (hbf rfl), fun d0 hd0 hp => ?_⟩
        exfalso
        have hty0 : Ex.ty ≠ .int := by rw [hty]; simp
        obtain ⟨_, hfr⟩ := hfo x Ex hx hl hty0 hmx (hbf rfl)
        obtain ⟨_, Er, hEr, hfm⟩ := hfr d0 (List.mem_filter.mp hd0).1
        rw [hab.notPi hEr (fun hr => Mode.region_not_frame (hr ▸ hfm))] at hp; cases hp
      | true =>
        rcases hT (.inl rfl) with hR | ⟨ht, _⟩
        · exact Or.inl ⟨Or.inl hR, fun _ _ _ => hR⟩
        · exact Or.inr ht
    have htyp := StmtT.editB (P := P) (ξ := ξ0) (b := b) hx hmx hl hty hhv hxF0 harg hyx hx1 hl1 hthru hdf hbf
    have hren : StmtT P (S.liftX ξ0) (S.canon Γ) S.Fc ((Stmt.edit b x op).rename S.ρ)
        (S.canon (A2.setE (A2.killThru op Ex.ty Ex1.path Γ1) x Ex1)) := by
      rcases hcase with ⟨hloc, hRp⟩ | ht
      · exact editB_ren h hab hx hmx hl hty hhv harg hyx hx1 hl1 hthru hdf hbf hloc
          (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, hv]))))
          (path_names_not_region hab hn hx hl hmx (by rw [hty]; simp))
          hRp hw hn (StmtT.wf hP htyp hw) (StmtT.names hP htyp rfl hn)
      · exact editB_ren_thru h hab hx hmx hl hty hhv harg hyx hx1 hl1 hthru hdf hbf ht
          (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, hv]))))
          (path_names_not_region hab hn hx hl hmx (by rw [hty]; simp))
          hw hn (StmtT.wf hP htyp hw) (StmtT.names hP htyp rfl hn)
    refine ⟨hren, ?_⟩
    exact (hab1.killNames (thruDeps op Γ1 Ex.ty Ex1.path)).setE' hab1 hx1 rfl rfl (by rw [hm1]; simp)
      (fun hf => absurd hf (by simp [Entry.fixed, hm1]))
  | @editBV _ Γ Γ1 F x op Ex Ex1 t D b hx hmx hl hty hhv hfn hxF harg hyx hx1 hl1 hne hthru hV hdf hbf hbs =>
    intro _ hab hw hn hfo hT hvs
    -- Agora #916: an `edit true` is placed by a call that passes no views;
    -- an `edit false` by any
    exact editBV_ren h hab (fun hbt => (hT (.inl (by simpa [Stmt.hasThru] using hbt))).Rf h) hP hw hn hx hmx hl hty hhv
      hfn hxF harg hyx hx1 hl1 hne hthru hV hdf hbf hbs (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, hv]))))
  | @takeB _ Γ Δ F x y i k Ex t hks hy hyF hx hmx hl hty hhv hxF hie hthru hnd hk hpe ih =>
    -- AGORA-889: `editB`'s truncation where the call places it
    -- (`editB_ren_facts`), then `y` bound to the element, as `letv` binds
    intro _ hab hw hn hfo hT hvs
    obtain ⟨-, -, hthru', hW⟩ : _ ∧ _ ∧ _ ∧ _ := by
      rcases hT (.inl rfl) with hR | ⟨ht, _⟩
      · exact editB_ren_facts h hab hx hmx hl hty
          (EditArg.trunc (t := t) hie) (fun _ h' => by cases h') hx hl hthru (Or.inl hR)
          (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, Edit.vars] at hv ⊢; simp [hv]))))
          (path_names_not_region hab hn hx hl hmx (by rw [hty]; simp)) (fun _ _ _ => hR) hw hn
          (takeB_ctxWF0 hw hx hmx hl) (takeB_nameWF0 hn hx hmx hl)
      · exact editB_ren_facts_thru h hab hx hmx hl hty
          (EditArg.trunc (t := t) hie) (fun _ h' => by cases h') hx hl hthru ht
          (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, Edit.vars] at hv ⊢; simp [hv]))))
          (path_names_not_region hab hn hx hl hmx (by rw [hty]; simp)) hw hn
          (takeB_ctxWF0 hw hx hmx hl) (takeB_nameWF0 hn hx hmx hl)
    have hrb : Ex.mode ≠ .rootb := by rw [hmx]; simp
    have hab2 : S.AbsOK (A2.setE (A2.killThru (.trunc i) Ex.ty Ex.path Γ) x Ex) :=
      (hab.killNames _).setE' hab hx rfl rfl hrb (fun hf => absurd hf (by simp [Entry.fixed, hmx]))
    have hmo : (compE Ex t).mode = .own ∨ (compE Ex t).mode = .bor := by
      cases t <;> simp [compE, intE]
    have habb := hab.add hab2 hy hmo
    have hwb := takeB_ctxWF (i := i) hw hy hx hmx hl hty
    have hnb := takeB_nameWF (i := i) hn hy hx hmx hl hty
    obtain ⟨tk, abk⟩ := ih hks habb hwb hnb (by
      have hyx : y ≠ x := fun e => by rw [e, hx] at hy; cases hy
      have h1 : FreshOK (A2.setE (killThru (.trunc i) Ex.ty Ex.path Γ) x Ex) :=
        hfo.reset ((FreshLe.refl Γ).killNames _) ((KeepsFrame.refl Γ).killNames _) hx rfl rfl rfl rfl rfl
      exact h1.bind (setE_none (killNames_none hy _) hyx) (FreshE.of_fresh (compE_fresh Ex t))) (fun _ => (hT (.inl rfl)).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    have hbx := hab.fresh hy
    have hnpy := hab.notPiFresh hy
    have hnry := hab.notRegFresh hy
    have hnrx : S.isReg x = false := hvs x (by simp [Stmt.vars])
    have hnpx : S.isPi x = false := hab.notPi_of_notReg hnrx
    have tk := tk.mono (S.liftX_under h hbx hnry)
    refine ⟨?_, abk.exitScope hbx hnry⟩
    rw [canon_exitScopes h abk (Or.inl hbx) (hab.notRegFresh hy)]
    have hwc := canon_wf_sub h habb hwb hnb
    have hnc := canon_names_sub h habb hnb
    rw [canon_setEs h _ hnpy] at hwc hnc tk
    have hty1 : (S.subE (S.liftE x Ex)).ty = .vec t := by rw [subE_ty, liftE_ty x hrb, hty]
    exact StmtT.takeB (by rw [src_rename]; exact hks) (by rw [canon_ρs h _ hnpy, hy]; rfl) (h.Fcout y)
      (canon_some h hx hnpx) (by rw [subE_mode, liftE_mode x hrb, hmx]; rfl)
      (by rw [subE_live, liftE_live]; exact hl)
      hty1 hhv (h.Fcout x) (exprT_ren h hab hie (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, hv])))))
      (by rw [subE_ty]; exact hthru')
      (fun hd => dtorHead_rename h.inj (hnd hd))
      -- AGORA-937 (item 3): what the call knows after the truncation is at least what the callee does
      (StmtT.weakenIn ⟨PW.setE hW.1 (by rw [compE_subE]; exact S.subE_weaker (compE_liftE_weaker hhv)),
        hwc, hnc⟩ tk)
      (EndOK.lift h abk hbx hpe)
  | @takeBV _ Γ Δ F x y i k Ex t hks hy hyF hx hmx hl hty hhv hxF hie hne hthru hV hnd hk hpe ih =>
    -- AGORA-897: `editBV`'s truncation where the call places it
    -- (`editBV_ren_facts`), then `y` bound to the element, as `letv` binds
    intro _ hab hw hn hfo hT hvs
    obtain ⟨hmem, hthru', heqK, hVg, hpfix⟩ := editBV_ren_facts (x := x) h hab hmx hthru hV
      (Or.inl ((hT (.inl rfl)).Rf h))
      (path_names_not_region hab hn hx hl hmx (by rw [hty]; simp))
    have hne' : memDeps (S.liftE x Ex).path ≠ [] := by rw [hmem]; simpa [rds] using hne
    have hrb : Ex.mode ≠ .rootb := by rw [hmx]; simp
    have hab2 : S.AbsOK (A2.setE (A2.killThruV (.trunc i) Ex.ty Ex.path Γ) x Ex) :=
      (hab.killHv _).setE' hab hx rfl rfl hrb (fun hf => absurd hf (by simp [Entry.fixed, hmx]))
    have hmo : (compE Ex t).mode = .own ∨ (compE Ex t).mode = .bor := by
      cases t <;> simp [compE, intE]
    have habb := hab.add hab2 hy hmo
    have hwb := takeBV_ctxWF (i := i) hw hy hx hmx hl hty
    have hnb := takeBV_nameWF (i := i) hn hy hx hmx hl hty
    obtain ⟨tk, abk⟩ := ih hks habb hwb hnb (by
      have hyx : y ≠ x := fun e => by rw [e, hx] at hy; cases hy
      have h1 : FreshOK (A2.setE (killThruV (.trunc i) Ex.ty Ex.path Γ) x Ex) :=
        hfo.reset ((FreshLe.refl Γ).killHv _) ((KeepsFrame.refl Γ).killHv _) hx rfl rfl rfl rfl rfl
      exact h1.bind (setE_none (killHv_none hy _) hyx) (FreshE.of_fresh (compE_fresh Ex t))) (fun _ => (hT (.inl rfl)).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    have hbx := hab.fresh hy
    have hnpy := hab.notPiFresh hy
    have hnry := hab.notRegFresh hy
    have hnrx : S.isReg x = false := hvs x (by simp [Stmt.vars])
    have hnpx : S.isPi x = false := hab.notPi_of_notReg hnrx
    have tk := tk.mono (S.liftX_under h hbx hnry)
    refine ⟨?_, abk.exitScope hbx hnry⟩
    rw [canon_exitScopes h abk (Or.inl hbx) (hab.notRegFresh hy)]
    have hwc := canon_wf_sub h habb hwb hnb
    have hnc := canon_names_sub h habb hnb
    rw [canon_setEs h _ hnpy, canon_setEs h _ hnpx, heqK, ← hpfix] at hwc hnc tk
    have hty1 : (S.subE (S.liftE x Ex)).ty = .vec t := by rw [subE_ty, liftE_ty x hrb, hty]
    exact StmtT.takeBV (by rw [src_rename]; exact hks) (by rw [canon_ρs h _ hnpy, hy]; rfl) (h.Fcout y)
      (canon_some h hx hnpx) (by rw [subE_mode, liftE_mode x hrb, hmx]; rfl)
      (by rw [subE_live, liftE_live]; exact hl)
      hty1 hhv (h.Fcout x) (exprT_ren h hab hie (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, hv])))))
      (by rw [hpfix]; exact hne') (by rw [subE_ty, hpfix]; exact hthru')
      (by rw [subE_ty, hpfix]; exact hVg [] (fun _ h' => by cases h'))
      (fun hd => dtorHead_rename h.inj (hnd hd))
      (StmtT.weakenIn ⟨PW.setE (PW.refl _) (by rw [compE_subE]; exact S.subE_weaker (compE_liftE_weakerV hmx hhv)),
        hwc, hnc⟩ tk)
      (EndOK.lift h abk hbx hpe)
  | @withElem _ Γ Γ1 Δ1 Δ F y x i k Ey E hks hx hxF hy hmy he hpin hds hr hk hpush hnix hpe hyv hdf ihs ihp =>
    intro _ hab hw hn hfo hT hvs
    -- an owner of the callee is bound to no argument: what depends on it ends where it is placed
    have hal : Allowed S .replace false y := allowed_own hab hy hmy .replace false
    have habk : S.AbsOK (A2.kill .replace false y Γ) := hab.kill _ _ _
    obtain ⟨E', hr', hE'⟩ := RhsT.ren h habk (hfo.kill _ _ _) hr (fun v hv => (hab.notPi_of_notReg (hvs v (by simp only [Rhs.vars, List.mem_singleton] at hv; simp [Stmt.vars, hv]))))
    have hnpx := hab.notPiFresh hx
    have hnrx := hab.notRegFresh hx
    have hnry : S.isReg y = false := hvs y (by simp [Stmt.vars])
    have hnpy : S.isPi y = false := hab.notPi_of_notReg hnry
    obtain ⟨hn1, hEn, _⟩ := hr.names (hn.kill .replace false y)
    have hab1 := RhsT.absOK (S := S) hr habk
    obtain ⟨hmo, _⟩ := RhsT.out hr
    obtain ⟨hw1, hdom, _, hEr⟩ := hr.wf (hw.kill .replace false y)
    have hx1 : Γ1 x = none := by
      have := hdom x; simp only [A2.kill, hx, Option.map_none] at this; cases h' : Γ1 x <;> simp_all
    have hwx := hw1.add hx1 hEr (fun hd => absurd hd (by simp [hr.dtor_false.2]))
      (fun ha => absurd ha (by simp [hr.dtor_false.1])) (fun hd => absurd hd (by simp [hr.dtor_false.2]))
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) hEn
    have habx := hab.add hab1 hx hmo
    have hfx : FreshOK (setE Γ1 x E) := by
      obtain ⟨h1, hE, _⟩ := hr.freshOK (hfo.kill .replace false y); exact h1.bind hx1 hE
    obtain ⟨tk, abk⟩ := ihs hks habx hwx hnx hfx (fun ht => (hT ht.withElem).sub (fun g hg => by simp [Stmt.calls, hg]))
      (fun v hv => hvs v (by simp [Stmt.vars, hv]))
    have tk := tk.mono (ξ' := .none) (fun _ _ h' => (S.liftX_none h').elim)
    obtain ⟨tp, abp⟩ := ihp rfl abk (hk.wf hP hwx) (hk.names hP hks hnx) (hk.freshOK hP hks hfx) (fun ht => by
      rcases ht with h' | ⟨g, hg, _⟩ <;> simp [Stmt.hasThru, Stmt.calls] at *)
      (fun v hv => hvs v (by simp [Stmt.vars] at hv ⊢; rcases hv with rfl | rfl <;> simp))
    have hbx := hab.fresh hx
    refine ⟨?_, abp.exitScope hbx hnrx⟩
    rw [canon_exitScopes h abp (Or.inl hbx) (hab.notRegFresh hx)]
    have hwc := canon_wf_sub h habx hwx hnx
    have hnc := canon_names_sub h habx hnx
    rw [canon_setEs h _ hnpx] at hwc hnc tk
    rw [canon_kill h hab hal hnpy hnry] at hr'
    exact StmtT.withElem (by rw [src_rename]; exact hks) (by rw [canon_ρs h _ hnpx, hx]; rfl) (h.Fcout x)
      (canon_some h hy hnpy) (by rw [subE_mode, liftE_mode y (by rw [hmy]; simp), hmy]; rfl)
      (exprT_ren h hab he (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, hv])))))
      (NoPin.lift h hab (bnd_own hab hy hmy)) (DtorSafe.canon h hal hds) hr'
      (StmtT.weakenIn ⟨PW.setE (PW.refl _) (hE' x), hwc, hnc⟩ tk)
      (tp.mono (ξ' := .none) (fun _ _ h' => (S.liftX_none h').elim))
      (NoIdx.canon h abp (allowed_own hab hy hmy .realloc false) hnix) (EndOK.lift h abp hbx hpe)
      (by
        rw [Stmt.vars_rename]; intro hm
        obtain ⟨w, hw', he'⟩ := List.mem_map.mp hm
        exact hyv (h.inj _ _ he' ▸ hw'))
      (by
        have hl := (hE' x).1
        have hrb : E.mode ≠ .rootb := by rcases (RhsT.out hr).1 with h' | h' <;> rw [h'] <;> simp
        rw [← hl, subE_ty, liftE_ty x hrb]; exact hdf)
  | @insert _ Γ Δ F x y i he _ hpu hnix ih =>
    intro _ hab hw hn hfo hT hvs
    obtain ⟨tp, abp⟩ := ih rfl hab hw hn hfo hT
      (fun v hv => hvs v (by simp [Stmt.vars] at hv ⊢; rcases hv with rfl | rfl <;> simp))
    obtain ⟨Ex, t, hx, hty, hcan⟩ := push_canDo hpu
    exact ⟨StmtT.insert (exprT_ren h hab he (fun v hv => (hab.notPi_of_notReg (hvs v (by simp [Stmt.vars, hv]))))) (h.Fcout x) (tp.mono (ξ' := .none) (fun _ _ h' => (S.liftX_none h').elim))
      (NoIdx.canon h abp (allowed_canDo hab hx hty hcan) hnix), abp⟩
  | @sub _ Γ Γ0 Δ0 Δ F k hw0 tk ho ih =>
    intro hs hab hw hn hfo hT hvs
    have hab0 := hab.weaker hw0
    obtain ⟨t, abΔ0⟩ := ih hs hab0 hw0.2.1 hw0.2.2 (hfo.weaker hw0) hT hvs
    have hwc := canon_weaker_sub h hab0 hw0
    rcases ho with rfl | hwo
    · exact ⟨StmtT.weakenIn hwc t, abΔ0⟩
    · have abΔ := abΔ0.weaker hwo
      exact ⟨StmtT.sub hwc t (Or.inr (canon_weaker_sub h abΔ hwo)), abΔ⟩

  | exit hup hwf hnΔ hdom hm hdk hst hfΔ =>
    intro _ hab hw hn hfo _ _
    have habΔ := hab.of_same hdom hm
    obtain ⟨hdom', hm'⟩ := canon_same h hab hdom hm
    exact ⟨StmtT.exit (S.liftX_up h hab hw hn hup) (canon_wf_sub h habΔ hwf hnΔ) (canon_names_sub h habΔ hnΔ) hdom' hm'
      (DKeep.canon h hdk hm) (DStay.canon h hst) (canon_freshT h habΔ hfo hdom' hm' hfΔ), habΔ⟩
  | loop hsrc _ hwf hnΔ hdom hm hdk hst hfΔ ih =>
    intro hs hab hw hn hfo hT hvs
    obtain ⟨tb, _⟩ := ih hsrc hab hw hn hfo (fun ht => hT (ht.mono (fun h => h) (fun _ hg => hg))) hvs
    have habΔ := hab.of_same hdom hm
    obtain ⟨hdom', hm'⟩ := canon_same h hab hdom hm
    exact ⟨StmtT.loop (by rw [src_rename]; exact hsrc) tb (canon_wf_sub h habΔ hwf hnΔ) (canon_names_sub h habΔ hnΔ)
      hdom' hm' (DKeep.canon h hdk hm) (DStay.canon h hst) (canon_freshT h habΔ hfo hdom' hm' hfΔ), habΔ⟩
  | block hb ih =>
    intro hs hab hw hn hfo hT hvs
    obtain ⟨tb, abΔ⟩ := ih hs hab hw hn hfo hT hvs
    exact ⟨StmtT.block (tb.mono (S.liftX_blk h abΔ (hb.wf hP hw))), abΔ⟩
/-! ### AGORA-937 stage 3: a ghost setting

A call setting `S` made ghost: its regions are lifted as bindings of their
own (renamed, `ghost`), so nothing is substituted (`isPi`, `σ` empty), and
the roots the arguments reach only through regions are not frozen: `R'`,
a part of `S.R`. Every other part of the setting is `S`'s. -/

/-- `S`, with regions lifted as ghost bindings and only `R'` frozen. -/
def ghostify (S : RSetup) (R' : List Var) : RSetup :=
  { S with R := R', Rd := allKinds R', Rf := allKinds R', σ := fun _ => [], isPi := fun _ => false, ghost := true }

@[simp] theorem ghostify_ρ (S : RSetup) (R' : List Var) : (S.ghostify R').ρ = S.ρ := rfl
@[simp] theorem ghostify_R (S : RSetup) (R' : List Var) : (S.ghostify R').R = R' := rfl
@[simp] theorem ghostify_isPi (S : RSetup) (R' : List Var) (v : Var) : (S.ghostify R').isPi v = false := rfl
@[simp] theorem ghostify_ghost (S : RSetup) (R' : List Var) : (S.ghostify R').ghost = true := rfl

/-- **A ghost setting is a setting**: from any setting, freezing only a
    part `R'` of its roots, where what its borrowed parameters hold is still
    what the arguments hold of `R'` or by name (`pe_held`). -/
theorem OK.ghostify {S : RSetup} (h : S.OK) {R' : List Var} (hR : ∀ r ∈ R', r ∈ S.R)
    (hpe : ∀ v, ∀ d ∈ (S.pe v).held,
      d ∈ allKinds R' ++ S.N ∨ (d ∈ rds S.ρ S.sym ∧ (S.pe v).ty.hasFn = true)) :
    (S.ghostify R').OK where
  inj := h.inj
  σ_sub := fun _ _ hd => by cases hd
  σ_mem := fun _ _ hd => by cases hd
  Rout := fun r hr => h.Rout r (hR r hr)
  Rd_sub := fun d hd => ⟨mem_allKinds hd, allKinds_notName hd⟩
  σ_Rd := fun _ _ hd => by cases hd
  Rf_sub := fun _ hd => hd
  Rroot := fun r hr => h.Rroot r (hR r hr)
  Fcout := h.Fcout
  pe_rb := h.pe_rb
  pe_out := h.pe_out
  Φsat := h.Φsat
  Φwf := h.Φwf
  Φρ := h.Φρ
  Φio := h.Φio
  pe_dtor := h.pe_dtor
  pe_dbind := h.pe_dbind
  Φarm := h.Φarm
  Φview := h.Φview
  Φdead := h.Φdead
  Φdb := h.Φdb
  Φdt := h.Φdt
  ΦN := h.ΦN
  pe_held := fun v d hd => by
    rcases hpe v d hd with hA | hs
    · left
      rcases List.mem_append.mp hA with hA | hA
      · refine List.mem_append_left _ (mem_compAll.mpr ⟨d, hA, .self, Or.inl rfl, ?_⟩)
        obtain ⟨r, k⟩ := d; cases k <;> rfl
      · exact List.mem_append_right _ hA
    · exact Or.inr (Or.inl hs)
  pe_names := h.pe_names
  sym_ok := h.sym_ok
  sym_of := h.sym_of
  N_name := h.N_name
  N_out := h.N_out
  N_named := h.N_named
  N_mut := fun d hd hb => by
    obtain ⟨h1, h2, h3⟩ := h.N_mut d hd hb
    exact ⟨h1, fun h' => h2 (hR _ h'), h3⟩
  Φrb := h.Φrb
  Φnamed := h.Φnamed

/-- ... and a context fit for `S`'s lift is fit for the ghost one's: no index
    is then a region's to substitute (`isPi` empty, `ghost`). -/
theorem AbsOK.ghostify {S : RSetup} {Γa : Ctx} (hab : S.AbsOK Γa) (R' : List Var) :
    (S.ghostify R').AbsOK Γa :=
  ⟨hab.1, hab.2.1, hab.2.2.1, hab.2.2.2.1, hab.2.2.2.2.1, fun v => by simp⟩

/-- **The renaming lemma applies to a ghost setting**: a callee statement
    typed in its own contexts is typed where a ghost setting places it, with
    each region a renamed binding of its own (AGORA-937 stage 3; the body
    may change elements through a borrow as long as the frozen part `R'` is
    empty). -/
theorem StmtT.ren_ghost {S : RSetup} (h : S.OK) {R' : List Var} (hR : ∀ r ∈ R', r ∈ S.R)
    (hpe : ∀ v, ∀ d ∈ (S.pe v).held,
      d ∈ allKinds R' ++ S.N ∨ (d ∈ rds S.ρ S.sym ∧ (S.pe v).ty.hasFn = true))
    {P : Prog} (hP : ProgOK P) {ξ : Exits} {Γa : Ctx} {Fa : List Var} {s : Stmt} {Δa : Ctx}
    (hd : StmtT P ξ Γa Fa s Δa) (hs : s.src = true) (hab : S.AbsOK Γa) (hw : CtxWF Γa)
    (hn : NameWF Γa) (hfo : FreshOK Γa) (hT : s.Thru P → R' = [])
    (hvs : ∀ v ∈ s.vars, S.isReg v = false) :
    StmtT P ((S.ghostify R').liftX ξ) ((S.ghostify R').canon Γa) S.Fc (s.rename S.ρ)
      ((S.ghostify R').canon Δa) ∧ (S.ghostify R').AbsOK Δa :=
  StmtT.ren (h.ghostify hR hpe) hP hd hs (hab.ghostify R') hw hn hfo (fun ht => Or.inl (hT ht)) hvs

end RSetup

end A2
