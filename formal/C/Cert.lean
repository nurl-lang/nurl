module

public import C.A2Prog

@[expose] public section

/-!
# C13: a program's certificate claims (AGORA-1019)

`certOK2B P s nv` is everything the checker decides about a whole program
`P` run from entry statement `s` over `nv` variable slots: the program
(`progOK2B`), the entry statement (`checkA2`, `stmtCodesB`, `s.src`) and the
slot bound. One boolean, so a certificate discharges it with one `decide`
that the kernel checks, and gets A2's three end-to-end theorems about that
program: it never gets stuck (`cert_safe`), a finished run has freed every
allocation (`cert_leak_end`), and so has a run ended by a panic no
`recover` frame catches (`cert_leak_panic`).

The claims' statements use A2's semantics only (`Steps`, `Stuck`,
`emptyMem`, `Mem.alloc`); the checker is how they are proved, not what they
say.
-/

namespace C

open A2

/-- The checker's whole verdict on program `P` with entry statement `s`
    over `nv` slots. -/
def certOK2B (P : Prog) (s : Stmt) (nv : Nat) : Bool :=
  progOK2B P && (checkA2 P s.vars (fun _ => none) [] s).isSome && stmtCodesB P s && s.src &&
    s.vars.all (fun v => decide (v < nv))

theorem certOK2B_parts {P : Prog} {s : Stmt} {nv : Nat} (h : certOK2B P s nv = true) :
    progOK2B P = true ∧ (∃ Δ, checkA2 P s.vars (fun _ => none) [] s = some Δ) ∧
      stmtCodesB P s = true ∧ s.src = true ∧ ∀ v ∈ s.vars, v < nv := by
  simp only [certOK2B, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq, Option.isSome_iff_exists] at h
  obtain ⟨⟨⟨⟨hP, hc⟩, hsc⟩, hs⟩, hv⟩ := h
  exact ⟨hP, hc, hsc, hs, hv⟩

/-- The checker's typing of the entry statement and the program, from its
    verdict. -/
theorem certOK2B_typed {P : Prog} {s : Stmt} {nv : Nat} (h : certOK2B P s nv = true) :
    ProgOK P ∧ ProgCodes P ∧ (∃ Δ, StmtT P .none (fun _ => none) [] s Δ) ∧ s.src = true ∧
      s.codesOK P ∧ ∀ v ∈ s.vars, v < nv := by
  obtain ⟨hP, ⟨Δ, hc⟩, hsc, hs, hv⟩ := certOK2B_parts h
  obtain ⟨hok, hcodes⟩ := progOK2B_sound hP
  obtain ⟨ht, _⟩ := checkA2_sound (ξ := .none) (fun _ _ => rfl) (fun v hv => hv) hc
  exact ⟨hok, hcodes, ⟨Δ, ht⟩, hs, stmtCodesB_sound hsc, hv⟩

/-- `M.safe`: a run of an accepted program from the empty store never gets
    stuck: it finishes, panics, or runs on. -/
theorem cert_safe {P : Prog} {s : Stmt} {nv : Nat} (h : certOK2B P s nv = true) :
    ∀ m' s', Steps P (emptyMem nv) s (.ok m' s') → ¬ Stuck P m' s' := by
  obtain ⟨hok, hcodes, ⟨_, ht⟩, hs, hsc, hv⟩ := certOK2B_typed h
  exact fun _ _ hr => memory_safe hok hcodes ht hs hsc hv hr

/-- `M.leak`, a finished run: every allocation has been freed. -/
theorem cert_leak_end {P : Prog} {s : Stmt} {nv : Nat} (h : certOK2B P s nv = true) :
    ∀ m', Steps P (emptyMem nv) s (.ok m' .skip) → ∀ i, m'.alloc i = false := by
  obtain ⟨hok, hcodes, ⟨_, ht⟩, hs, hsc, hv⟩ := certOK2B_typed h
  exact fun _ hr => no_leak_end hok hcodes ht hs hsc hv hr

/-- `M.leak`, a run ended by an uncaught panic: every allocation has been
    freed by the unwinding. -/
theorem cert_leak_panic {P : Prog} {s : Stmt} {nv : Nat} (h : certOK2B P s nv = true) :
    ∀ m', Steps P (emptyMem nv) s (.panic m') → ∀ i, m'.alloc i = false := by
  obtain ⟨hok, hcodes, ⟨_, ht⟩, hs, hsc, hv⟩ := certOK2B_typed h
  exact fun _ hr => no_leak_panic hok hcodes ht hs hsc hv hr

/-! ### A witness

The term nurlc and nurl-cert's translator (`tolean.nu`) make of
`tools/ncore/certify/vec_push_len.nu` (a `Vec` built, pushed twice, its
length read, dropped at the end), and its claims, the verdict decided by
the kernel: what a bundle's Claims.lean states, here inside the proof. -/

/-- `vec_push_len.nu`'s `main`. -/
def certWitnessMain : Fn :=
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := (.block (.letv 4 (.expr .any) (.letv 5 (.expr .any)
      (.seq (.letv 1 (.new .int) (.letv 2 (.var 1) (.seq (.push 2 5) (.seq (.push 2 4)
        (.letv 3 (.expr (.len 2)) (.assign 0 (.expr .any))))))) (.exit 0))))), nvars := 7 }

def certWitness : Prog := [certWitnessMain]

theorem cert_witness_ok : certOK2B certWitness (.letcall 0 0 [] .skip) 1 = true := by decide +kernel

theorem cert_witness_safe :
    ∀ m' s', Steps certWitness (emptyMem 1) (.letcall 0 0 [] .skip) (.ok m' s') → ¬ Stuck certWitness m' s' :=
  cert_safe cert_witness_ok

theorem cert_witness_leak :
    (∀ m', Steps certWitness (emptyMem 1) (.letcall 0 0 [] .skip) (.ok m' .skip) → ∀ i, m'.alloc i = false) ∧
    (∀ m', Steps certWitness (emptyMem 1) (.letcall 0 0 [] .skip) (.panic m') → ∀ i, m'.alloc i = false) :=
  ⟨cert_leak_end cert_witness_ok, cert_leak_panic cert_witness_ok⟩

/-! ### What the claims cover (AGORA-1030)

The core IR does not track a program's numbers, and the translation writes
each untracked one as `Expr.any`. A model step on a condition of that kind
goes either way, so the runs a claim quantifies over take every arm the
program can take, whatever its numbers. (With `.lit 0` in its place, as
before, the model took only the else arm of every `if`.) -/

/-- Both arms of a condition on an untracked number are steps of the model. -/
theorem ite_any_both (P : Prog) (m : Mem) (a b : Stmt) :
    Step P m (.ite .any a b) (.ok m a) ∧ Step P m (.ite .any a b) (.ok m b) :=
  ⟨.iteT (n := 1) .any (by decide), .iteF .any⟩

/-- ... and a loop on one unfolds to such a condition: each round may stop
    or go round (`ite_any_both` on what this steps to). -/
theorem while_any_unfolds (P : Prog) (m : Mem) (s : Stmt) :
    Step P m (.while .any s) (.ok m (.ite .any (.seq s (.while .any s)) .skip)) :=
  .while

end C
