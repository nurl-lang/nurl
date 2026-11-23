import C.Sub

/-!
# C4: whole programs (AGORA-970)

`ProgOK` asks each function to be `FnOK`: its body types from the callee's
own view of its parameters (`sigCtx`) and ends as its summary says. `fnOKB`
decides that, given the body's certificate. The domain is the variables
the function uses, its parameters, result slot and body's (`fnDomA`).
`progOKB` checks every function. A
program it accepts, with an entry statement `checkC` accepts, never gets
stuck (`checked_program_safe`). That is the end-to-end statement of
phase C for A1: run the checker on the certificate, and A1's soundness
theorem covers the program.
-/

namespace C

open A1

/-- `lendable`, decided. -/
def lendableB (fn : Fn) (j : Nat) : Bool :=
  match fn.params[j]? with
  | some (.inp, _) => true
  | some (.inout _, _) => true
  | _ => false

theorem lendableB_sound {fn : Fn} {j : Nat} (h : lendableB fn j = true) : lendable fn j := by
  unfold lendableB at h
  split at h
  · rename_i t hj
    obtain ⟨hlt, he⟩ := List.getElem?_eq_some_iff.mp hj
    exact ⟨hlt, Or.inl (by rw [he])⟩
  · rename_i b t hj
    obtain ⟨hlt, he⟩ := List.getElem?_eq_some_iff.mp hj
    exact ⟨hlt, Or.inr ⟨b, by rw [he]⟩⟩
  · cases h

/-- What the body's end must be (`FnOK`'s result and `inout` clauses). -/
def endOKB (fn : Fn) (Δ : Ctx) : Bool :=
  (match Δ fn.params.length with
   | some Er => Er.live && decide (Er.ty = fn.resTy) && decide (Er.mode = resMode fn) &&
       Er.path.all (fun d => decide ((d.root, d.kind) ∈ fn.lends)) &&
       Er.held.all (fun d => decide ((d.root, d.kind) ∈ fn.rholds))
   | none => false) &&
  (List.range fn.params.length).all fun i =>
    match fn.params[i]? with
    | some (.inout _, _) => (match Δ i with
        | some Ei => Ei.live && Ei.held.all (fun d => decide ((i, d.root, d.kind) ∈ fn.outHolds))
        | none => false)
    | _ => true

/-- The variables a function's check ranges over: its parameters, its
    result slot and the variables its body names (github#2242's review: not
    every slot up to `nvars`). -/
def fnDomA (fn : Fn) : List Var :=
  (List.range fn.nvars).filter fun v => decide (v ≤ fn.params.length) || decide (v ∈ fn.body.vars)

/-- `FnOK`, decided, with the body's certificate. -/
def fnOKB (P : Prog) (fn : Fn) (c : Cert) : Bool :=
  fn.body.src && decide (fn.params.length < fn.nvars) && fn.body.vars.all (fun v => decide (v < fn.nvars)) &&
  fn.resTy.ok && (!fn.resOwn || isVecB fn.resTy) &&
  fn.params.all (fun pt => pt.2.ok && (decide (pt.1 = .inp) || isVecB pt.2)) &&
  fn.lends.all (fun jk => lendableB fn jk.1) && fn.rholds.all (fun jk => lendableB fn jk.1) &&
  fn.outHolds.all (fun o => lendableB fn o.2.1) &&
  (match checkC P (fnDomA fn) c (sigCtx fn) [] fn.body with
   | some Δ => endOKB fn Δ
   | none => false)

theorem sigCtx_supported {fn : Fn} (h : fn.params.length < fn.nvars) :
    Supported (sigCtx fn) (fnDomA fn) := by
  intro v hv
  have hv' : ¬ (v < fn.nvars ∧ (v ≤ fn.params.length ∨ v ∈ fn.body.vars)) := by
    simpa [fnDomA, List.mem_filter, decide_eq_true_eq] using hv
  have h1 : ¬ v < fn.params.length := fun hlt =>
    hv' ⟨Nat.lt_trans hlt h, Or.inl (Nat.le_of_lt hlt)⟩
  have h2 : ¬ v = fn.params.length := fun e => hv' ⟨e ▸ h, Or.inl (Nat.le_of_eq e)⟩
  simp [sigCtx, h1, h2]

theorem fnOKB_sound {P : Prog} {fn : Fn} {c : Cert} (h : fnOKB P fn c = true) : FnOK P fn := by
  simp only [fnOKB, Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true'] at h
  obtain ⟨⟨⟨⟨⟨⟨⟨⟨⟨hsrc, hlen⟩, hvars⟩, hres⟩, hown⟩, hps⟩, hl⟩, hr⟩, ho⟩, hchk⟩ := h
  refine ⟨hsrc, hlen, fun v hv => of_decide_eq_true (List.all_eq_true.mp hvars v hv), hres, fun e => ?_,
    fun pt hpt => ?_, fun jk hjk => lendableB_sound (List.all_eq_true.mp hl jk hjk),
    fun jk hjk => lendableB_sound (List.all_eq_true.mp hr jk hjk),
    fun o hoo => lendableB_sound (List.all_eq_true.mp ho o hoo), ?_⟩
  · rcases hown with h0 | h0
    · rw [e] at h0; cases h0
    · exact isVecB_sound h0
  · have := List.all_eq_true.mp hps pt hpt
    simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq] at this
    refine ⟨this.1, fun hne => ?_⟩
    rcases this.2 with h0 | h0
    · exact absurd h0 hne
    · exact isVecB_sound h0
  · split at hchk
    · rename_i Δ hΔ
      have hD : ∀ v ∈ fn.body.vars, v ∈ fnDomA fn := fun v hv => by
        simp only [fnDomA, List.mem_filter, List.mem_range, Bool.or_eq_true, decide_eq_true_eq]
        exact ⟨of_decide_eq_true (List.all_eq_true.mp hvars v hv), Or.inr hv⟩
      obtain ⟨ht, _⟩ := checkC_sound (P := P) c (sigCtx_supported hlen) hD hΔ
      refine ⟨Δ, ht, ?_, ?_⟩
      · simp only [endOKB, Bool.and_eq_true] at hchk
        obtain ⟨hres', _⟩ := hchk
        split at hres'
        · rename_i Er hEr
          simp only [Bool.and_eq_true, decide_eq_true_eq] at hres'
          obtain ⟨⟨⟨⟨hlv, hty⟩, hm⟩, hp⟩, hh⟩ := hres'
          exact ⟨Er, hEr, hlv, hty, hm, fun d hd => of_decide_eq_true (List.all_eq_true.mp hp d hd),
            fun d hd => of_decide_eq_true (List.all_eq_true.mp hh d hd)⟩
        · cases hres'
      · intro i hi b hb
        simp only [endOKB, Bool.and_eq_true] at hchk
        have := List.all_eq_true.mp hchk.2 i (List.mem_range.mpr hi)
        rw [List.getElem?_eq_getElem hi] at this
        have hpi : fn.params[i] = (.inout b, fn.params[i].2) := by rw [← hb]
        rw [hpi] at this
        simp only at this
        split at this
        · rename_i Ei hEi
          simp only [Bool.and_eq_true] at this
          exact ⟨Ei, hEi, this.1, fun d hd => of_decide_eq_true (List.all_eq_true.mp this.2 d hd)⟩
        · cases this
    · cases hchk

/-- `ProgOK`, decided, with one certificate per function. -/
def progOKB (P : Prog) (certs : Nat → Cert) : Bool :=
  (List.range P.length).all fun i => match P[i]? with
    | some fn => fnOKB P fn (certs i)
    | none => false

theorem progOKB_sound {P : Prog} {certs : Nat → Cert} (h : progOKB P certs = true) : ProgOK P := by
  intro fn hfn
  obtain ⟨i, hi, rfl⟩ := List.getElem_of_mem hfn
  have := List.all_eq_true.mp h i (List.mem_range.mpr hi)
  rw [List.getElem?_eq_getElem hi] at this
  exact fnOKB_sound this

/-- Phase C for A1, end to end: a program whose certificates the checker
    accepts, with an entry statement it accepts that is source syntax and
    whose variables fit the initial store (the theorem's premises: the
    checker's acceptance alone does not give them), never gets stuck from
    the empty store. -/
theorem checked_program_safe {P : Prog} {certs : Nat → Cert} (hP : progOKB P certs = true)
    {s : Stmt} {c : Cert} {Δ : Ctx} (hc : checkC P s.vars c (fun _ => none) [] s = some Δ)
    (hs : s.src = true) {nv : Nat} (hv : ∀ v ∈ s.vars, v < nv) {m' : Mem} {s' : Stmt}
    (hr : Steps P (emptyMem nv) s (.ok m' s')) : ¬ Stuck P m' s' :=
  checkedC_memory_safe (progOKB_sound hP) hc hs hv hr

end C
