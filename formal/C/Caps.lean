import C.Cert
import A2.Reach

/-!
# C16: what a program can run, decided (AGORA-1013)

`A2/Reach.lean` proves that a run names only functions of a set `A` closed
under the program's names (`ProgFns`), from a configuration that names only
`A`, and so never reads the program outside `A` (`Steps.agree`). This file
decides it for a list `L`: `capsOKB P s L` checks that the entry statement
`s` and every function of `L` name only functions of `L`. The kernel
evaluates it with one `decide`, and the certificate gets, for program `P`
run from `s` on the empty store:

* `caps_names`: every configuration a run reaches names only functions of
  `L`, in what is left to run and in what memory holds;
* `caps_runs`: **a program that has the same functions at the indices of
  `L`, whatever it has elsewhere, has exactly the same runs.** A function
  outside `L` is never entered: its code could be anything, a call of the
  network or a write to a file, and no run would change.

For a program that spawns threads (A3, `C/Cert3.lean`), the same for every
interleaving: `caps3_names` and `caps3_runs` (`C/Caps3.lean`, apart so that
a single-threaded program's certificate does not load A3), from
`A3/Reach.lean`.

`reachB P s` (`C/CapsWitness.lean`, with the witnesses) computes such a list, the closure of the entry's names; the
certificate does not trust it, it checks it (`capsOKB`). What each function
of `L` may do outside the model (its calls of the runtime) is the
certificate's capability table, a trusted row (`docs/dev/CERTIFICATE.md`):
the theorem bounds which functions run, the table says what each does.

The statements use A2's semantics only (`Steps`, `emptyMem`, `Stmt.fnsIn`,
`MemFns`); the checker is how they are proved.
-/

namespace C
open A2

/-! ### The names, as lists -/

/-- Every destructor index a type holds, anywhere in it (more than
    `Ty.Reaps` hands to a reap: a sound bound). -/
def tyDtors : Ty → List Nat
  | .vec t => tyDtors t
  | .slice t => tyDtors t
  | .prod a b => tyDtors a ++ tyDtors b
  | .sum a b => tyDtors a ++ tyDtors b
  | .arc t => tyDtors t
  | .lk t => tyDtors t
  | .cell t => tyDtors t
  | .dtor f t => f :: tyDtors t
  | .rguard u => tyDtors u
  | .int | .fn _ _ => []

theorem tyDtors_nest (n f : Nat) (u : Ty) : f ∈ tyDtors (Ty.nest n (.dtor f u)) := by
  induction n with
  | zero => simp [tyDtors]
  | succ n ih => simpa [tyDtors] using ih

theorem tyDtors_undtor {t : Ty} {f : Nat} (h : f ∈ tyDtors t.undtor) : f ∈ tyDtors t := by
  induction t with
  | dtor g t ih => exact List.mem_cons_of_mem _ (ih h)
  | _ => exact h

/-- What a reap of a block of type `t` hands to a frame is in `tyDtors t`. -/
theorem reaps_mem_dtors {t : Ty} {f : Nat} {u : Ty} (h : t.Reaps f u) : f ∈ tyDtors t := by
  induction h with
  | nest => exact tyDtors_nest _ _ _
  | chan he _ ih =>
    apply tyDtors_undtor
    rw [he]; simp [tyDtors, ih]

/-- The functions a right-hand side names. -/
def rhsNames : Rhs → List Nat
  | .pack fs _ _ _ _ => fs
  | .arcNew t _ => tyDtors t
  | .lockNew t _ => tyDtors t
  | .cellNew t _ => tyDtors t
  | _ => []

/-- The functions a statement names. -/
def stmtNames : Stmt → List Nat
  | .seq a b => stmtNames a ++ stmtNames b
  | .letv _ r s => rhsNames r ++ stmtNames s
  | .letcall _ f _ s => f :: stmtNames s
  | .assign _ r => rhsNames r
  | .ite _ a b => stmtNames a ++ stmtNames b
  | .while _ s => stmtNames s
  | .scope _ s => stmtNames s
  | .rbind _ s => stmtNames s
  | .frozen _ s => stmtNames s
  | .letrec _ f s => f :: stmtNames s
  | .catchR _ _ s => stmtNames s
  | .unpair _ _ _ s => stmtNames s
  | .callc _ _ _ _ _ s => stmtNames s
  | .letd _ f r s => f :: (rhsNames r ++ stmtNames s)
  | .scopeD _ f s => f :: stmtNames s
  | .withLock _ _ s => stmtNames s
  | .scopeL _ t _ s => tyDtors t ++ stmtNames s
  | .withElem _ _ _ s => stmtNames s
  | .callcE _ _ _ _ s => stmtNames s
  | .block s => stmtNames s
  | .loop s => stmtNames s
  | .takeB _ _ _ s => stmtNames s
  -- (each constructor written out, as `A2.Stmt.fnsIn`: no wildcard's
  -- equation lemma for every certificate to load)
  | .skip | .push _ _ | .free _ | .panic | .edit _ _ _ | .insert _ _ _ | .exit _ => []

/-- The functions a function names: its body's, and its result type's
    destructor. -/
def fnNames (fn : Fn) : List Nat := stmtNames fn.body ++ fn.resTy.dhead.toList

theorem rhs_fnsIn_of {A : Nat → Prop} {r : Rhs} (h : ∀ f ∈ rhsNames r, A f) : r.fnsIn A := by
  cases r <;> simp only [Rhs.fnsIn, rhsNames] at h ⊢ <;>
    first
      | trivial
      | exact h
      | exact fun f u hr => h f (reaps_mem_dtors hr)

/-- A statement whose names are all in `A` names only `A`. -/
theorem stmt_fnsIn_of {A : Nat → Prop} {s : Stmt} (h : ∀ f ∈ stmtNames s, A f) : s.fnsIn A := by
  induction s with
  | seq a b iha ihb =>
    simp only [stmtNames, List.mem_append] at h
    exact ⟨iha fun f hf => h f (.inl hf), ihb fun f hf => h f (.inr hf)⟩
  | ite c a b iha ihb =>
    simp only [stmtNames, List.mem_append] at h
    exact ⟨iha fun f hf => h f (.inl hf), ihb fun f hf => h f (.inr hf)⟩
  | letv x r s ih =>
    simp only [stmtNames, List.mem_append] at h
    exact ⟨rhs_fnsIn_of fun f hf => h f (.inl hf), ih fun f hf => h f (.inr hf)⟩
  | assign x r => exact rhs_fnsIn_of h
  | letcall x f args s ih =>
    simp only [stmtNames, List.mem_cons] at h
    exact ⟨h f (.inl rfl), ih fun g hg => h g (.inr hg)⟩
  | letrec x f s ih =>
    simp only [stmtNames, List.mem_cons] at h
    exact ⟨h f (.inl rfl), ih fun g hg => h g (.inr hg)⟩
  | scopeD x f s ih =>
    simp only [stmtNames, List.mem_cons] at h
    exact ⟨h f (.inl rfl), ih fun g hg => h g (.inr hg)⟩
  | letd x f r s ih =>
    simp only [stmtNames, List.mem_cons, List.mem_append] at h
    exact ⟨h f (.inl rfl), rhs_fnsIn_of fun g hg => h g (.inr (.inl hg)),
      ih fun g hg => h g (.inr (.inr hg))⟩
  | scopeL k t x s ih =>
    simp only [stmtNames, List.mem_append] at h
    exact ⟨fun f u hr => h f (.inl (reaps_mem_dtors hr)), ih fun g hg => h g (.inr hg)⟩
  | «while» _ _ ih | scope _ _ ih | rbind _ _ ih | frozen _ _ ih | catchR _ _ _ ih | unpair _ _ _ _ ih
  | callc _ _ _ _ _ _ ih | withLock _ _ _ ih | withElem _ _ _ _ ih | callcE _ _ _ _ _ ih | block _ ih
  | loop _ ih | takeB _ _ _ _ ih =>
    exact ih h
  | _ => trivial

/-- A function whose names are all in `A` names only `A`. -/
theorem fn_fnsIn_of {A : Nat → Prop} {fn : Fn} (h : ∀ f ∈ fnNames fn, A f) : fn.fnsIn A := by
  simp only [fnNames, List.mem_append] at h
  refine ⟨stmt_fnsIn_of fun f hf => h f (.inl hf), fun g hg => h g (.inr ?_)⟩
  simp [hg]

/-! ### The check -/

/-- Every function of `L` the program has names only functions of `L`. -/
def progFnsB (P : Prog) (L : List Nat) : Bool :=
  L.all fun f => match P[f]? with
    | some fn => (fnNames fn).all (· ∈ L)
    | none => true

/-- **The whole check**: the entry statement and every function of `L` name
    only functions of `L`. -/
def capsOKB (P : Prog) (s : Stmt) (L : List Nat) : Bool :=
  (stmtNames s).all (· ∈ L) && progFnsB P L

theorem progFnsB_sound {P : Prog} {L : List Nat} (h : progFnsB P L = true) : ProgFns (· ∈ L) P := by
  intro f fn hf hL
  simp only [progFnsB, List.all_eq_true] at h
  have := h f hL
  rw [hf] at this
  simp only [List.all_eq_true, decide_eq_true_eq] at this
  exact fn_fnsIn_of this

theorem capsOKB_parts {P : Prog} {s : Stmt} {L : List Nat} (h : capsOKB P s L = true) :
    s.fnsIn (· ∈ L) ∧ ProgFns (· ∈ L) P := by
  simp only [capsOKB, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at h
  exact ⟨stmt_fnsIn_of h.1, progFnsB_sound h.2⟩

/-- The empty store names nothing. -/
theorem memFns_empty (A : Nat → Prop) (nv : Nat) : MemFns A (emptyMem nv) :=
  ⟨fun _ _ _ h => (by cases h), fun _ _ h => (by cases h), fun _ _ h => (by cases h)⟩

/-! ### The claims -/

/-- Every configuration a run of an accepted program reaches names only
    functions of `L`: in what is left to run, and in what memory holds (its
    packages' code, its blocks' destructors). -/
theorem caps_names {P : Prog} {s : Stmt} {L : List Nat} (h : capsOKB P s L = true) (nv : Nat) :
    (∀ m' s', Steps P (emptyMem nv) s (.ok m' s') → s'.fnsIn (· ∈ L) ∧ MemFns (· ∈ L) m') ∧
      (∀ m', Steps P (emptyMem nv) s (.panic m') → MemFns (· ∈ L) m') := by
  obtain ⟨hs, hP⟩ := capsOKB_parts h
  refine ⟨fun m' s' hr => ?_, fun m' hr => ?_⟩
  · obtain ⟨h1, h2⟩ := ((hr.fns hP (memFns_empty _ nv) hs).1 _ _ rfl); exact ⟨h2, h1⟩
  · exact (hr.fns hP (memFns_empty _ nv) hs).2 _ rfl

/-- **`N.cap`'s theorem: a function outside `L` never runs.** Any program
    with the same functions at the indices of `L`, whatever its functions
    elsewhere, has exactly the runs of `P` from `s`: the same configurations
    reached, the same panics. -/
theorem caps_runs {P : Prog} {s : Stmt} {L : List Nat} (h : capsOKB P s L = true) {P' : Prog}
    (hag : ∀ f ∈ L, P'[f]? = P[f]?) (nv : Nat) (r : Res) :
    Steps P (emptyMem nv) s r ↔ Steps P' (emptyMem nv) s r := by
  obtain ⟨hs, hP⟩ := capsOKB_parts h
  exact steps_agree_iff hP hag (memFns_empty _ nv) hs

end C
